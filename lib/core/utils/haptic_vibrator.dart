import 'haptic_vibrator_stub.dart'
    if (dart.library.js_interop) 'haptic_vibrator_web.dart' as impl;

class HapticVibrator {
  static Future<void> vibrateAlert({bool urgent = false}) =>
      impl.triggerPlatformVibration(urgent: urgent);
}

