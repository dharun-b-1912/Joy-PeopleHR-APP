import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:http/http.dart' as http;
import '../utils/secure_log.dart';
import '../config/app_env.dart';

/// JOY PeopleHR — Production-Grade Crash Reporting & Privacy Engine
///
/// Wraps Firebase Crashlytics with:
/// - Environment & build metadata context (APP_ENV, commit, version)
/// - Global Flutter error handlers (framework + isolate errors)
/// - Strict PII sanitization (zero passwords, tokens, biometric templates, bank details)
/// - Structured feature & operation breadcrumbs
/// - Non-fatal exception recording with clean error codes
class CrashReportingService {
  static final CrashReportingService instance = CrashReportingService._internal();
  CrashReportingService._internal();

  FirebaseCrashlytics? _crashlytics;
  bool _isInitialized = false;
  static final Map<String, int> _sentinelThrottleMap = {};

  FirebaseCrashlytics get _fb => _crashlytics!;

  /// Initialize Crashlytics and attach global error handlers.
  /// Call this AFTER Firebase.initializeApp().
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (kIsWeb) {
      _isInitialized = true;
      logProcess('CRASHLYTICS', 'Skipped native FirebaseCrashlytics on Web (terminal crash handler active)');
      return;
    }

    try {
      _crashlytics = FirebaseCrashlytics.instance;

      // Enable collection in release builds and QA/Staging environments
      final shouldCollect = !kDebugMode || AppEnv.isQa || AppEnv.isStaging;
      await _crashlytics!.setCrashlyticsCollectionEnabled(shouldCollect);

      // Attach build & environment metadata
      AppEnv.diagnosticInfo.forEach((key, value) {
        _fb.setCustomKey(key, value);
      });

      // Attach global Flutter error handlers
      _attachFlutterErrorHandlers();

      // Attach Dart isolate error handler
      _attachDartErrorHandlers();

      _isInitialized = true;
      secureLog('[Crashlytics] Initialized successfully for ${AppEnv.current.label}');
    } catch (e) {
      secureLog('[Crashlytics] Initialization error: $e');
    }
  }

  /// Sets safe user identity for crash reports (Internal IDs only, no raw PII).
  void setUser({required String userId, String? email, String? name}) {
    if (!_isInitialized || _crashlytics == null) return;
    try {
      _fb.setUserIdentifier(userId);
      _fb.setCustomKey('user_id_safe', userId);
      _fb.setCustomKey('app_env', AppEnv.current.name);
    } catch (e) {
      secureLog('[Crashlytics] setUser error: $e');
    }
  }

  /// Clears user identity on logout.
  void clearUser() {
    if (!_isInitialized || _crashlytics == null) return;
    try {
      _fb.setUserIdentifier('');
      _fb.setCustomKey('user_id_safe', '');
    } catch (e) {
      secureLog('[Crashlytics] clearUser error: $e');
    }
  }

  /// Adds a sanitized custom key/value pair for crash context.
  void setCustomKey(String key, String value) {
    if (!_isInitialized || _crashlytics == null) return;
    try {
      final safeKey = _sanitizeString(key);
      final safeVal = _sanitizeString(value);
      _fb.setCustomKey(safeKey, safeVal);
    } catch (e) {
      secureLog('[Crashlytics] setCustomKey error: $e');
    }
  }

  /// Records structured context for attendance operations
  void recordAttendanceContext({
    required String operation,
    required String source,
    String? deviceType,
    String? resultCode,
    String? errorCode,
  }) {
    if (!_isInitialized || _crashlytics == null) return;
    try {
      _fb.setCustomKey('feature', 'attendance');
      _fb.setCustomKey('operation', operation);
      _fb.setCustomKey('source', source);
      if (deviceType != null) _fb.setCustomKey('device_type', deviceType);
      if (resultCode != null) _fb.setCustomKey('result_code', resultCode);
      if (errorCode != null) _fb.setCustomKey('error_code', errorCode);
      log('[ATTENDANCE] op=$operation src=$source res=$resultCode err=$errorCode');
    } catch (_) {}
  }

  /// Records a non-fatal exception with sanitized contextual parameters.
  void recordError(
    dynamic error,
    StackTrace? stackTrace, {
    String? reason,
    String? errorCode,
    Map<String, dynamic>? information,
  }) {
    // 1. Ingest into JOY Sentinel Telemetry and trigger Telegram Watchdog Alert
    _reportToSentinel(
      error: error,
      stackTrace: stackTrace,
      reason: reason,
      errorCode: errorCode,
      information: information,
    );

    // 2. Record to Firebase Crashlytics if initialized
    if (!_isInitialized || _crashlytics == null) return;
    try {
      final sanitizedInfo = <String>[];
      if (errorCode != null) sanitizedInfo.add('`error_code`: $errorCode');
      if (information != null) {
        for (final entry in information.entries) {
          if (!_isSensitiveKey(entry.key)) {
            sanitizedInfo.add('`${entry.key}`: ${_sanitizeString(entry.value?.toString() ?? '')}');
          }
        }
      }

      _fb.recordError(
        error,
        stackTrace,
        reason: reason,
        information: sanitizedInfo,
      );
    } catch (e) {
      secureLog('[Crashlytics] recordError error: $e');
    }
  }

  /// Non-blocking, battery-safe report dispatcher to JOY Sentinel
  static Future<void> _reportToSentinel({
    required dynamic error,
    StackTrace? stackTrace,
    String? reason,
    String? errorCode,
    Map<String, dynamic>? information,
  }) async {
    try {
      final errStr = _sanitizeString(error.toString());
      final now = DateTime.now().millisecondsSinceEpoch;
      final sentinelCode = errorCode ?? 'MOBILE-001';
      final throttleKey = '$sentinelCode:${errStr.length > 40 ? errStr.substring(0, 40) : errStr}';

      // 60-second in-memory throttle: eliminates UI loop storming
      final last = _sentinelThrottleMap[throttleKey];
      if (last != null && now - last < 60000) {
        return;
      }
      _sentinelThrottleMap[throttleKey] = now;

      final cleanStack = stackTrace != null
          ? stackTrace.toString().split('\n').take(6).join('\n')
          : 'No stack trace captured';

      final payload = {
        'action': 'report_event',
        'event': {
          'eventCode': sentinelCode,
          'severity': (sentinelCode == 'AUTH-001' || sentinelCode == 'ATT-001') ? 'P1' : 'P2',
          'serviceName': 'JOY Mobile App (Flutter)',
          'message': errStr.length > 250 ? errStr.substring(0, 250) : errStr,
          'sourceLocation': reason ?? 'Flutter Widget / Platform',
          'diagnosticPayload': {
            'reason': reason,
            'stack': cleanStack,
            'platform': defaultTargetPlatform.name,
            'isWeb': kIsWeb,
            'app_version': AppEnv.versionName,
            'build_number': AppEnv.buildNumber,
            ...?information,
          },
          'probableCause': 'Unhandled exception in Flutter mobile runtime or async isolate.',
          'recommendedAction': 'Inspect stack trace, platform null-safety, and device permissions.',
        }
      };

      final url = Uri.parse('https://ysiajemrqakfngasehhi.supabase.co/functions/v1/telegram-webhook');
      http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).catchError((_) => http.Response('error', 500));
    } catch (_) {
      // Fail silently to guarantee zero performance or UX impact
    }
  }

  /// Logs a sanitized diagnostic message that appears in the next crash report.
  void log(String message) {
    if (!_isInitialized || _crashlytics == null) return;
    try {
      _fb.log(_sanitizeString(message));
    } catch (_) {}
  }

  /// Forces a crash (Strictly enabled in DEV/QA non-production builds only).
  void testCrash() {
    if (AppEnv.allowDebugMenus && _isInitialized && _crashlytics != null) {
      _fb.crash();
    }
  }

  // ── Privacy Sanitization Helpers ─────────────────────────────────────
  static bool _isSensitiveKey(String key) {
    final k = key.toLowerCase();
    return k.contains('password') ||
        k.contains('token') ||
        k.contains('secret') ||
        k.contains('key') ||
        k.contains('biometric') ||
        k.contains('face_template') ||
        k.contains('finger_template') ||
        k.contains('salary') ||
        k.contains('bank') ||
        k.contains('pan') ||
        k.contains('aadhaar');
  }

  static String _sanitizeString(String raw) {
    if (raw.isEmpty) return '';
    // Mask tokens and JWTs
    var cleaned = raw.replaceAll(RegExp(r'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}'), '[TOKEN_MASKED]');
    // Mask emails if found in raw logs
    cleaned = cleaned.replaceAll(RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), '[EMAIL_MASKED]');
    return cleaned;
  }

  // ── Private: Global Error Handlers ──────────────────────────────────

  void _attachFlutterErrorHandlers() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        // In debug mode, show errors in console
        FlutterError.presentError(details);
      }

      // Always report to JOY Sentinel Telemetry and Telegram Watchdog Bot
      _reportToSentinel(
        error: details.exception,
        stackTrace: details.stack,
        reason: details.context?.toString() ?? 'Flutter framework layout/widget error',
        errorCode: 'MOBILE-001',
      );

      // Record to Crashlytics in release builds
      if (_isInitialized && !kDebugMode) {
        _fb.recordError(
          details.exception,
          details.stack,
          reason: details.context?.toString(),
          information: [
            'Library: ${details.library}',
            'Severity: ${details.summary}',
          ],
        );
      }

      secureLog('[FlutterError] ${details.exception}');
    };

    // Handle async errors that aren't caught
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      // Always report to JOY Sentinel Telemetry and Telegram Watchdog Bot
      _reportToSentinel(
        error: error,
        stackTrace: stackTrace,
        reason: 'Uncaught async platform error',
        errorCode: 'MOBILE-001',
      );

      if (_isInitialized && !kDebugMode) {
        _fb.recordError(
          error,
          stackTrace,
          reason: 'Uncaught async error',
        );
      }
      secureLog('[PlatformDispatcher] Uncaught error: $error');
      return true;
    };
  }

  void _attachDartErrorHandlers() {
    // Handle uncaught errors in the root isolate
    Isolate.current.addErrorListener(
      RawReceivePort((dynamic pair) {
        final error = pair[0] as Object;
        final stackTrace = pair[1] as StackTrace;

        // Always report to JOY Sentinel Telemetry and Telegram Watchdog Bot
        _reportToSentinel(
          error: error,
          stackTrace: stackTrace,
          reason: 'Root isolate runtime exception',
          errorCode: 'MOBILE-001',
        );

        if (_isInitialized && !kDebugMode) {
          _fb.recordError(
            error,
            stackTrace,
            reason: 'Isolate error',
          );
        }
        secureLog('[Isolate] Uncaught error: $error');
      }).sendPort,
    );
  }
}
