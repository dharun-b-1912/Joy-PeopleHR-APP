// Stub implementation for mobile and non-web platforms
import 'package:geolocator/geolocator.dart';

Future<Position?> getDirectWebPosition({
  bool enableHighAccuracy = true,
  int timeoutSeconds = 14,
}) async {
  return null;
}

bool isWebSecureContext() => true;

