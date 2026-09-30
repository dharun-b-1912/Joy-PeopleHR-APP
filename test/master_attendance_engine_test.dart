import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/core/config/app_env.dart';
import 'package:workforce_os/core/services/attendance_time_service.dart';
import 'package:workforce_os/models/hrms_models.dart';

void main() {
  group('JOY PeopleHR — Unified Multi-Mode Attendance & Source Locking Suite', () {
    test('Gate 01: Biometric Check-In locks session source to BIOMETRIC', () {
      final session = AttendanceSession(
        status: AttendanceStatus.checkedIn,
        checkInTime: DateTime(2026, 9, 12, 9, 0, 0),
        source: AttendanceSource.biometric,
        sourceLabel: AttendanceSource.biometric.label,
        verificationMethod: 'Face Recognition',
        deviceId: 'TDBD253600550',
        isSourceLocked: true,
      );

      expect(session.isCheckedIn, isTrue);
      expect(session.isBiometricLocked, isTrue);
      expect(session.source, equals(AttendanceSource.biometric));
      expect(session.sourceLabel, equals('Biometric Terminal'));
      expect(session.verificationMethod, equals('Face Recognition'));
      expect(session.deviceId, equals('TDBD253600550'));
    });

    test('Gate 02: Mobile Check-In locks session source to MOBILE', () {
      final session = AttendanceSession(
        status: AttendanceStatus.checkedIn,
        checkInTime: DateTime(2026, 9, 12, 8, 55, 0),
        source: AttendanceSource.mobile,
        sourceLabel: AttendanceSource.mobile.label,
        verificationMethod: 'GPS Geofence',
        deviceId: 'FLUTTER_MOBILE',
        isSourceLocked: true,
      );

      expect(session.isCheckedIn, isTrue);
      expect(session.isMobileLocked, isTrue);
      expect(session.source, equals(AttendanceSource.mobile));
      expect(session.sourceLabel, equals('Mobile GPS'));
      expect(session.isBiometricLocked, isFalse);
    });

    test('Gate 03: Dynamic Working Timer accurately computes elapsed duration from first_in', () {
      final checkInTime = DateTime(2026, 9, 12, 9, 0, 0);
      final simulatedNow = DateTime(2026, 9, 12, 11, 35, 20);

      final duration = simulatedNow.difference(checkInTime);
      final formatted = AttendanceTimeService.formatDurationTimer(duration);

      expect(formatted, equals('02:35:20'));
    });

    test('Gate 04: Checked-Out shift derives duration from net_working_minutes', () {
      const session = AttendanceSession(
        status: AttendanceStatus.checkedOut,
        netWorkingMinutes: 510, // 8h 30m
        source: AttendanceSource.biometric,
        isSourceLocked: true,
      );

      expect(session.isCheckedOut, isTrue);
      expect(session.netWorkingMinutes, equals(510));
      final hours = session.netWorkingMinutes! ~/ 60;
      final mins = session.netWorkingMinutes! % 60;
      expect('${hours}h ${mins}m', equals('8h 30m'));
    });

    test('Gate 05: AttendanceSource enum correctly classifies raw payload values', () {
      expect(AttendanceSource.fromValue('BIOMETRIC_ADMS'), equals(AttendanceSource.biometric));
      expect(AttendanceSource.fromValue('FACE_RECOGNITION'), equals(AttendanceSource.biometric));
      expect(AttendanceSource.fromValue('FINGERPRINT'), equals(AttendanceSource.biometric));
      expect(AttendanceSource.fromValue('MOBILE_GPS'), equals(AttendanceSource.mobile));
      expect(AttendanceSource.fromValue('APP'), equals(AttendanceSource.mobile));
      expect(AttendanceSource.fromValue('MANUAL_ADMIN'), equals(AttendanceSource.manual));
      expect(AttendanceSource.fromValue(null), equals(AttendanceSource.unassigned));
    });

    test('Gate 06: AppEnv metadata exposes correct environment diagnostics', () {
      final diag = AppEnv.diagnosticInfo;
      expect(diag.containsKey('environment'), isTrue);
      expect(diag.containsKey('version'), isTrue);
      expect(diag.containsKey('channel'), isTrue);
      expect(diag.containsKey('commit_sha'), isTrue);
      expect(diag.containsKey('is_production'), isTrue);
    });

    test('Gate 07: Production safety guard prevents test overrides in production', () {
      // In production mode, mock biometrics and dev auto login are strictly false
      if (AppEnv.isProduction) {
        expect(AppEnv.allowMockBiometrics, isFalse);
        expect(AppEnv.allowDevAutoLogin, isFalse);
        expect(AppEnv.allowSyntheticTestData, isFalse);
      }
    });

    test('Gate 08: CheckoutLocationVerification classifies inside assigned location correctly', () {
      const verification = CheckoutLocationVerification(
        status: CheckoutLocationStatus.assignedLocation,
        locationName: 'Joy PeopleHR HQ',
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 8.5,
        distanceToNearestMeters: 12.0,
      );

      expect(verification.requiresReason, isFalse);
      expect(verification.shortLabel, equals('Joy PeopleHR HQ'));
    });

    test('Gate 09: CheckoutLocationVerification requires reason when unauthorized or GPS off', () {
      const unauthVerification = CheckoutLocationVerification(
        status: CheckoutLocationStatus.unauthorized,
        locationName: 'Unknown',
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 15.0,
        distanceToNearestMeters: 4500.0,
      );

      expect(unauthVerification.requiresReason, isTrue);
      expect(unauthVerification.isUncertainLocation, isTrue);
    });
  });
}
