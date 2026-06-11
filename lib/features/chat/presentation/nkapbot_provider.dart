import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/nkapbot_repository.dart';
import '../domain/nkapbot_models.dart';

/// Immutable conversation state held by [NkapBotController].
class NkapBotState {
  final List<NkapBotMessage> messages;
  final bool isLoading;
  final String? error;

  const NkapBotState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  NkapBotState copyWith({
    List<NkapBotMessage>? messages,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return NkapBotState(
      messages:  messages  ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error:     clearError ? null : (error ?? this.error),
    );
  }
}

/// Holds the conversation, talks to the repository, exposes [send] /
/// [clear]. Created once and reused for the whole app session so messages
/// survive sheet/screen lifecycles.
class NkapBotController extends StateNotifier<NkapBotState> {
  NkapBotController(this._repo) : super(const NkapBotState());

  final NkapBotRepository _repo;

  Future<void> send({
    required String message,
    required List<String> enabledFeatures,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || state.isLoading) return;

    final userTurn = NkapBotMessage(
      role: NkapBotRole.user,
      text: trimmed,
      time: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, userTurn],
      isLoading: true,
      clearError: true,
    );

    final res = await _repo.sendMessage(
      message: trimmed,
      conversationHistory: state.messages,
      enabledFeatures: enabledFeatures,
    );

    final botTurn = NkapBotMessage(
      role: NkapBotRole.assistant,
      text: res.message,
      cardType: res.cardType,
      cardData: res.cardData,
      category: res.category,
      time: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, botTurn],
      isLoading: false,
    );
  }

  void clear() {
    state = const NkapBotState();
  }
}

final nkapBotRepositoryProvider = Provider<NkapBotRepository>(
  (_) => const NkapBotRepository(),
);

final nkapBotControllerProvider =
    StateNotifierProvider<NkapBotController, NkapBotState>(
  (ref) => NkapBotController(ref.read(nkapBotRepositoryProvider)),
);
