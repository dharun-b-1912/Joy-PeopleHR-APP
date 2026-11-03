import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_env.dart';
import 'env_config.dart';

/// WorkForceOS — Supabase Project Configuration
///
/// Reads credentials from [EnvConfig] which loads from --dart-define flags.
/// For production builds, always pass SUPABASE_URL and SUPABASE_ANON_KEY
/// via --dart-define to avoid hardcoding secrets in source.
class SupabaseConfig {
  static String get url => AppEnv.supabaseUrl;
  static String get anonKey => AppEnv.supabaseAnonKey;

  static bool get isInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool get isConfigured =>
      isInitialized &&
      url.isNotEmpty &&
      url.startsWith('https://') &&
      anonKey.isNotEmpty &&
      anonKey.startsWith('sb_publishable_');
}
