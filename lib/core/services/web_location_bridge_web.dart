// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:geolocator/geolocator.dart';
import '../utils/secure_log.dart';

/// Direct HTML5 Geolocation Bridge optimized for iOS Safari & Android Chrome
Future<Position?> getDirectWebPosition({
  bool enableHighAccuracy = true,
  int timeoutSeconds = 14,
}) async {
  try {
    // 1. Check if startup warmup or user gesture already cached valid coordinates (< 45s)
    try {
      final lastKnown = js.context['joyLastKnownLocation'];
      if (lastKnown != null) {
        final lat = (lastKnown['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (lastKnown['lng'] as num?)?.toDouble() ?? 0.0;
        final acc = (lastKnown['accuracy'] as num?)?.toDouble() ?? 10.0;
        final tsMs = (lastKnown['timestamp'] as num?)?.toInt() ?? 0;
        final ageMs = DateTime.now().millisecondsSinceEpoch - tsMs;
        if (lat != 0.0 && lng != 0.0 && ageMs < 45000) {
          secureLog('[WebLocationBridge] Instant return of cached warmup position: ($lat, $lng)');
          return Position(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
            accuracy: acc,
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
          );
        }
      }
    } catch (cacheErr) {
      secureLog('[WebLocationBridge] Cache inspection notice: $cacheErr');
    }

    final geolocation = html.window.navigator.geolocation;

    final completer = Completer<Position?>();

    void handleSuccess(html.Geoposition pos) {
      if (completer.isCompleted) return;
      final coords = pos.coords;
      if (coords == null) {
        completer.complete(null);
        return;
      }
      final lat = coords.latitude?.toDouble() ?? 0.0;
      final lng = coords.longitude?.toDouble() ?? 0.0;
      final acc = coords.accuracy?.toDouble() ?? 10.0;
      final ts = pos.timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(pos.timestamp!)
          : DateTime.now();

      completer.complete(Position(
        latitude: lat,
        longitude: lng,
        timestamp: ts,
        accuracy: acc,
        altitude: coords.altitude?.toDouble() ?? 0.0,
        altitudeAccuracy: coords.altitudeAccuracy?.toDouble() ?? 0.0,
        heading: coords.heading?.toDouble() ?? 0.0,
        headingAccuracy: 0.0,
        speed: coords.speed?.toDouble() ?? 0.0,
        speedAccuracy: 0.0,
      ));
    }

    void handleError(dynamic err) {
      if (completer.isCompleted) return;
      secureLog('[WebLocationBridge] Primary position acquisition note: $err');

      // If high accuracy timed out or had trouble (common in iOS Safari indoors),
      // gracefully fall back to standard accuracy with 60-second cached fix
      if (enableHighAccuracy) {
        secureLog('[WebLocationBridge] Retrying with standard accuracy for iOS Safari...');
        geolocation.getCurrentPosition(
          enableHighAccuracy: false,
          timeout: const Duration(seconds: 12),
          maximumAge: const Duration(minutes: 1),
        ).then((fallbackPos) {
          handleSuccess(fallbackPos);
        }).catchError((fallbackErr) {
          if (!completer.isCompleted) {
            secureLog('[WebLocationBridge] Fallback location acquisition note: $fallbackErr');
            completer.complete(null);
          }
        });
        return;
      }

      completer.complete(null);
    }

    geolocation.getCurrentPosition(
      enableHighAccuracy: enableHighAccuracy,
      timeout: Duration(seconds: timeoutSeconds),
      maximumAge: const Duration(seconds: 0),
    ).then(handleSuccess).catchError(handleError);

    return await completer.future.timeout(
      Duration(seconds: timeoutSeconds + 2),
      onTimeout: () => null,
    );
  } catch (e) {
    secureLog('[WebLocationBridge] Exception in direct web position: $e');
    return null;
  }
}

bool isWebSecureContext() {
  try {
    return html.window.isSecureContext ?? true;
  } catch (_) {
    return true;
  }
}
