// lib/core/env.dart
/// URL base del backend.
/// Puedes sobreescribirla en tiempo de build:
/// flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
const String kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
