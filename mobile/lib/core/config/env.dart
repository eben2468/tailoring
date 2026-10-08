/// Build-time configuration. The app holds no secrets — only the API address.
///
///   flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1
///
/// The default targets the local Docker stack from the Android emulator (10.0.2.2 = host machine).
abstract final class Env {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api/v1');
  static const appName = 'Nutɔfe';
}
