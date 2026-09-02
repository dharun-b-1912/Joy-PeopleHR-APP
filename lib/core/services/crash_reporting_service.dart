import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/secure_log.dart';

/// WorkForceOS — Crash Reporting Service
///
/// Wraps Firebase Crashlytics with:
/// - Global Flutter error handlers (errors + platform errors)
/// - Dart isolate error handler
/// - User identity tracking
/// - Custom key/value breadcrumbs
/// - Non-fatal exception recording
class CrashReportingService {
  static final CrashReportingService instance = CrashReportingService._internal();
  CrashReportingService._internal();

  FirebaseCrashlytics? _crashlytics;
  bool _isInitialized = false;

  FirebaseCrashlytics get _fb => _crashlytics!;

  /// Initialize Crashlytics and attach global error handlers.
  /// Call this AFTER Firebase.initializeApp().
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _crashlytics = FirebaseCrashlytics.instance;

      // Enable collection in release builds only
      await _crashlytics!.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Attach global Flutter error handlers
      _attachFlutterErrorHandlers();

      // Attach Dart error handler
      _attachDartErrorHandlers();

      _isInitialized = true;
      secureLog('[Crashlytics] Initialized successfully');
    } catch (e) {
      secureLog('[Crashlytics] Initialization error: $e');
    }
  }

  /// Sets the user identity for crash reports.
  void setUser({required String userId, String? email, String? name}) {
    if (!_isInitialized) return;
    try {
      _fb.setUserIdentifier(userId);
      if (email != null) _fb.setCustomKey('user_email', email);
      if (name != null) _fb.setCustomKey('user_name', name);
    } catch (e) {
      secureLog('[Crashlytics] setUser error: $e');
    }
  }

  /// Clears user identity on logout.
  void clearUser() {
    if (!_isInitialized) return;
    try {
      _fb.setUserIdentifier('');
      _fb.setCustomKey('user_email', '');
      _fb.setCustomKey('user_name', '');
    } catch (e) {
      secureLog('[Crashlytics] clearUser error: $e');
    }
  }

  /// Adds a custom key/value pair for crash context.
  void setCustomKey(String key, String value) {
    if (!_isInitialized) return;
    try {
      _fb.setCustomKey(key, value);
    } catch (e) {
      secureLog('[Crashlytics] setCustomKey error: $e');
    }
  }

  /// Records a non-fatal exception.
  void recordError(dynamic error, StackTrace? stackTrace, {String? reason, Map<String, dynamic>? information}) {
    if (!_isInitialized) return;
    try {
      _fb.recordError(
        error,
        stackTrace,
        reason: reason,
        information: information?.entries.map((e) => '`${e.key}`: ${e.value}').toList() ?? [],
      );
    } catch (e) {
      secureLog('[Crashlytics] recordError error: $e');
    }
  }

  /// Logs a message that appears in the next crash report.
  void log(String message) {
    if (!_isInitialized) return;
    try {
      _fb.log(message);
    } catch (_) {}
  }

  /// Forces a crash (for testing only, debug builds only).
  void testCrash() {
    if (kDebugMode && _isInitialized) {
      _fb.crash();
    }
  }

  // ── Private: Global Error Handlers ──────────────────────────────────

  void _attachFlutterErrorHandlers() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        // In debug mode, show errors in console
        FlutterError.presentError(details);
      }

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
