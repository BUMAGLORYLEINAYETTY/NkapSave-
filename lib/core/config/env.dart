import 'package:flutter/foundation.dart' show kIsWeb;

/// Environment configuration. Set at build time via --dart-define.
///
/// Examples:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///   flutter build apk --dart-define=API_BASE_URL=https://api.nkapsave.com
class Env {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Backend host (no trailing slash). On web defaults to localhost;
  /// on mobile defaults to the Android-emulator host alias.
  static String get apiBaseUrl => _override.isNotEmpty
      ? _override
      : (kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000');

  /// API path prefix. Override only for staging/legacy.
  static const String apiPrefix = String.fromEnvironment(
    'API_PREFIX',
    defaultValue: '/api/v1',
  );

  static String get apiUrl => '$apiBaseUrl$apiPrefix';

  /// Static asset / uploaded files origin (without prefix).
  static String get assetOrigin => apiBaseUrl;
}
