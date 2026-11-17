/// Pre-configured OAuth 2.0 credentials for Notes For Me (project: aldavelabs).
class AuthConfig {
  static const String clientId =
      '702325277685-n5dbp1jhf9i14prhtbtusc40apto0r3h.apps.googleusercontent.com';

  static const String projectId = 'aldavelabs';
  static const String authUri = 'https://accounts.google.com/o/oauth2/auth';
  static const String tokenUri = 'https://oauth2.googleapis.com/token';

  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const String desktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '',
  );

  static const String desktopClientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
    defaultValue: '',
  );

  static String get effectiveDesktopClientId =>
      desktopClientId.trim().isNotEmpty ? desktopClientId.trim() : clientId;
}
