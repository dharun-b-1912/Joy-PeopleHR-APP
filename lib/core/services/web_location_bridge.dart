import 'package:geolocator/geolocator.dart';
import 'web_location_bridge_stub.dart'
    if (dart.library.html) 'web_location_bridge_web.dart';

class WebLocationBridge {
  static Future<Position?> getPosition({
    bool enableHighAccuracy = true,
    int timeoutSeconds = 14,
  }) {
    return getDirectWebPosition(
      enableHighAccuracy: enableHighAccuracy,
      timeoutSeconds: timeoutSeconds,
    );
  }

  static bool checkIsSecureContext() {
    return isWebSecureContext();
  }
}

