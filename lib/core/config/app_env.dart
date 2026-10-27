import 'package:flutter/foundation.dart';

/// JOY PeopleHR — Strict Environment Architecture & Production Guard
///
/// Supported Environments:
/// - DEV: Local & Developer testing
/// - QA: Internal QA Team verification & Firebase App Distribution (joy-qa)
/// - STAGING: UAT / Pilot client testing (joy-hr-uat, joy-pilot)
/// - PRODUCTION: Real customer deployments (Google Play / Signed Release)
enum AppEnvironment {
  dev,
  qa,
  staging,
  production;

  static AppEnvironment fromString(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'qa':
        return AppEnvironment.qa;
      case 'staging':
      case 'uat':
        return AppEnvironment.staging;
      case 'prod':
      case 'production':
        return AppEnvironment.production;
      case 'dev':
      case 'development':
      default:
        return AppEnvironment.dev;
    }
  }

  String get label {
    switch (this) {
      case AppEnvironment.dev:
        return 'Development';
      case AppEnvironment.qa:
        return 'QA / Test';
      case AppEnvironment.staging:
        return 'Staging / UAT';
      case AppEnvironment.production:
        return 'Production';
    }
  }

  String get channel {
    switch (this) {
      case AppEnvironment.dev:
        return 'DEV';
      case AppEnvironment.qa:
        return 'QA';
      case AppEnvironment.staging:
        return 'INTERNAL_UAT';
      case AppEnvironment.production:
        return 'PRODUCTION';
    }
  }
}

class AppEnv {
  // ── Environment Resolution ──────────────────────────────────────────
  static const String _rawEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
  static final AppEnvironment current = AppEnvironment.fromString(_rawEnv);

  static bool get isProduction => current == AppEnvironment.production;
  static bool get isStaging => current == AppEnvironment.staging;
  static bool get isQa => current == AppEnvironment.qa;
  static bool get isDev => current == AppEnvironment.dev;

  // ── Production Safety Constraints ───────────────────────────────────
  /// Debug menus are strictly disabled in production
  static bool get allowDebugMenus => !isProduction && (kDebugMode || isDev || isQa);

  /// Test mock biometric flows are strictly disabled in production
  static bool get allowMockBiometrics => !isProduction && isDev;

  /// Synthetic employee test generators are strictly disabled in production
  static bool get allowSyntheticTestData => !isProduction && (isDev || isQa);

  /// Dev auto-login allowed only in DEV environment under Debug mode
  static bool get allowDevAutoLogin => isDev && kDebugMode;

  // ── Build Metadata ──────────────────────────────────────────────────
  static const String versionName = String.fromEnvironment('APP_VERSION', defaultValue: '1.1.6');
  static const String versionCode = String.fromEnvironment('APP_BUILD_CODE', defaultValue: '24');
  static const String commitSha = String.fromEnvironment('GIT_COMMIT_SHA', defaultValue: 'HEAD');
  static const String branch = String.fromEnvironment('GIT_BRANCH', defaultValue: 'main');
  static const String buildTimestamp = String.fromEnvironment('BUILD_TIMESTAMP', defaultValue: '2026-09-12T10:00:00Z');
  static const String buildNumber = String.fromEnvironment('BUILD_NUMBER', defaultValue: '184');

  // ── Backend Endpoints Configuration ─────────────────────────────────
  static String get supabaseUrl {
    const override = String.fromEnvironment('SUPABASE_URL');
    if (override.isNotEmpty) return override;

    switch (current) {
      case AppEnvironment.production:
        return 'https://ysiajemrqakfngasehhi.supabase.co';
      case AppEnvironment.staging:
        return 'https://ysiajemrqakfngasehhi.supabase.co';
      case AppEnvironment.qa:
        return 'https://ysiajemrqakfngasehhi.supabase.co';
      case AppEnvironment.dev:
        return 'https://ysiajemrqakfngasehhi.supabase.co';
    }
  }

  static String get supabaseAnonKey {
    const override = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (override.isNotEmpty) return override;

    return 'sb_publishable_i_pb_iFcxX0BEJFok_XfZA_gZF3W8mj';
  }

  // ── Hardware Biometric Connector URL ────────────────────────────────
  static String get connectorBaseUrl {
    const override = String.fromEnvironment('JOY_CONNECTOR_URL');
    if (override.isNotEmpty) return override;

    switch (current) {
      case AppEnvironment.production:
        return 'http://127.0.0.1:11108';
      case AppEnvironment.staging:
        return 'http://127.0.0.1:11108';
      case AppEnvironment.qa:
        return 'http://127.0.0.1:11108';
      case AppEnvironment.dev:
        return 'http://127.0.0.1:11108';
    }
  }

  // ── Hard Startup Verification ───────────────────────────────────────
  static void verifyConfiguration() {
    if (isProduction) {
      if (kDebugMode) {
        debugPrint('[SECURITY WARNING] Production environment running in Flutter Debug mode.');
      }
      assert(!allowMockBiometrics, 'MOCK BIOMETRICS CANNOT BE ACTIVE IN PRODUCTION');
      assert(!allowDevAutoLogin, 'DEV AUTO LOGIN CANNOT BE ACTIVE IN PRODUCTION');
    }
  }

  /// Safe diagnostic string for Settings -> About & Crashlytics
  static Map<String, String> get diagnosticInfo => {
    'environment': current.name.toUpperCase(),
    'version': '$versionName+$versionCode',
    'build_number': buildNumber,
    'channel': current.channel,
    'commit_sha': commitSha,
    'branch': branch,
    'build_time': buildTimestamp,
    'is_production': isProduction.toString(),
  };
}
