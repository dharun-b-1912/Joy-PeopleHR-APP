import 'package:flutter/services.dart';

Future<void> triggerPlatformVibration({bool urgent = false}) async {
  try {
    final pulses = urgent ? 3 : 2;
    for (int i = 0; i < pulses; i++) {
      await HapticFeedback.vibrate();
      await HapticFeedback.heavyImpact();
      if (i < pulses - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    }
  } catch (_) {}
}

