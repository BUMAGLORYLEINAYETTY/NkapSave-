import 'package:dio/dio.dart';
import '../../../core/services/api_service.dart';
import '../domain/nkapbot_models.dart';

/// Talks to POST /nkapbot/chat. Returns a parsed [NkapBotResponse] for
/// every call — on any error we surface a graceful fallback rather than
/// throwing, so the UI doesn't need a global error boundary.
class NkapBotRepository {
  const NkapBotRepository();

  Future<NkapBotResponse> sendMessage({
    required String message,
    required List<NkapBotMessage> conversationHistory,
    required List<String> enabledFeatures,
  }) async {
    try {
      final res = await ApiService.dio.post(
        '/nkapbot/chat',
        data: {
          'message': message,
          'conversation_history':
              conversationHistory.map((m) => m.toApiTurn()).toList(),
          'enabled_features': enabledFeatures,
        },
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return NkapBotResponse.fromJson(data);
      }
      return NkapBotResponse.fallback(
        'Something came back I could not read. Please try again.',
      );
    } on DioException catch (e) {
      // Try to surface the backend's `detail` field if present, otherwise
      // a generic message keyed by status code.
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) {
        return NkapBotResponse.fallback(data['detail'] as String);
      }
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return NkapBotResponse.fallback(
          'Your session has expired — please sign in again.',
        );
      }
      return NkapBotResponse.fallback(
        "NkapBot can't reach the server right now. Please try again.",
      );
    } catch (_) {
      return NkapBotResponse.fallback(
        'Something went wrong. Please try again in a moment.',
      );
    }
  }
}
