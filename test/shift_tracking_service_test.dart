import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workforce_os/core/services/shift_tracking_service.dart';

void main() {
  group('ShiftTrackingService & Geofencing Telemetry Tests', () {
    test('ShiftTrackingService has 20m minimum displacement threshold', () {
      expect(ShiftTrackingService.minDisplacementMeters, equals(20.0));
    });

    test('Geolocator displacement calculation correctly evaluates >20m threshold', () {
      // Point A: Bangalore HQ Office
      const lat1 = 12.9716;
      const lon1 = 77.5946;

      // Point B: ~10 meters displacement (should NOT trigger ping)
      const lat2 = 12.97165;
      const lon2 = 77.59465;
      final dist1 = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
      expect(dist1 < ShiftTrackingService.minDisplacementMeters, isTrue,
          reason: 'Displacement under 20m should be ignored to save battery');

      // Point C: ~120 meters displacement (SHOULD trigger ping)
      const lat3 = 12.9726;
      const lon3 = 77.5952;
      final dist2 = Geolocator.distanceBetween(lat1, lon1, lat3, lon3);
      expect(dist2 >= ShiftTrackingService.minDisplacementMeters, isTrue,
          reason: 'Displacement >= 50m should trigger GPS telemetry');
    });

    test('Cumulative distance tracking accumulates properly', () {
      double runningTotal = 0.0;
      final displacements = [62.4, 85.0, 114.2, 53.8];

      for (final d in displacements) {
        if (d >= ShiftTrackingService.minDisplacementMeters) {
          runningTotal += d;
        }
      }

      expect(runningTotal, closeTo(315.4, 0.01));
      expect((runningTotal / 1000).toStringAsFixed(2), equals('0.32'));
    });
  });
}
