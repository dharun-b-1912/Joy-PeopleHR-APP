/// WorkForceOS — Environment Configuration
///
/// Production secrets are injected via --dart-define at build time.
/// Development defaults are provided for `flutter run` convenience.
///
/// Production build:
///   flutter build apk --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///                      --dart-define=SUPABASE_ANON_KEY=sb_xxx
///
/// IMPORTANT: Never commit real production keys to source control.
class EnvConfig {
  // ── Supabase ────────────────────────────────────────────────────────
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ysiajemrqakfngasehhi.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_i_pb_iFcxX0BEJFok_XfZA_gZF3W8mj',
  );

  // ── Firebase (injected by FlutterFire CLI via firebase_options.dart) ─
  // Firebase keys are managed separately and are safe to include in source
  // per Google's guidance (they're restricted by API key restrictions).

  // ── Feature Flags ───────────────────────────────────────────────────
  static const bool enablePushNotifications = bool.fromEnvironment(
    'ENABLE_PUSH_NOTIFICATIONS',
    defaultValue: true,
  );

  static const bool enableGpsTracking = bool.fromEnvironment(
    'ENABLE_GPS_TRACKING',
    defaultValue: true,
  );

  static const bool enableDebugLogging = bool.fromEnvironment(
    'ENABLE_DEBUG_LOGGING',
    defaultValue: true, // Only true in debug; overridden to false in release
  );

  // ── Development Auth Auto-Login (Debug Only) ──────────────────────────
  static const bool devAutoLogin = bool.fromEnvironment(
    'DEV_AUTO_LOGIN',
    defaultValue: true,
  );

  static const String devAuthEmail = String.fromEnvironment(
    'DEV_AUTH_EMAIL',
    defaultValue: '',
  );

  static const String devAuthPassword = String.fromEnvironment(
    'DEV_AUTH_PASSWORD',
    defaultValue: '',
  );

  // ── App Info ────────────────────────────────────────────────────────
  static const String appName = 'JOY PeopleHR';
  static const String appVersion = '1.0.1';

  /// Validates that required configuration is present.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseUrl.startsWith('https://') &&
      supabaseAnonKey.isNotEmpty;
}
