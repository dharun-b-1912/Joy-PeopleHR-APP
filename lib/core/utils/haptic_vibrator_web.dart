import 'dart:js_interop';

@JS('navigator.vibrate')
external bool _navigatorVibrate(JSAny pattern);

Future<void> triggerPlatformVibration({bool urgent = false}) async {
  try {
    final List<int> pattern = urgent ? [400, 150, 400, 150, 400] : [300, 140, 300];
    _navigatorVibrate(pattern.map((e) => e.toJS).toList().toJS);
  } catch (_) {}
}

