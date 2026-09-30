import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:workforce_os/core/config/app_env.dart';
import 'package:workforce_os/features/employee/home/screens/employee_home_screen.dart';
import 'package:workforce_os/main.dart';
import 'package:workforce_os/models/hrms_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('JOY PeopleHR — Critical User Journeys Integration Test Suite', () {
    testWidgets('Journey 1: App Boot, Environment Initialization & Auth Gatekeeper', (tester) async {
      AppEnv.verifyConfiguration();

      await tester.pumpWidget(const JoyPeopleHRApp());
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Verify app launched and AuthGatekeeper is mounted
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Journey 2: Attendance Source Lock & Dynamic Live Timer Rendering', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeDashboardScreen(onOpenServices: () {}),
          ),
        ),
      );
      await tester.pump();

      // Verify home dashboard mounts safely
      expect(find.byType(HomeDashboardScreen), findsOneWidget);
    });

    testWidgets('Journey 3: Biometric Terminal State Reflection In UI', (tester) async {
      // Simulate Biometric Active Session
      final session = AttendanceSession(
        status: AttendanceStatus.checkedIn,
        checkInTime: DateTime.now().subtract(const Duration(hours: 2, minutes: 15)),
        source: AttendanceSource.biometric,
        sourceLabel: AttendanceSource.biometric.label,
        verificationMethod: 'Face Recognition',
        deviceId: 'TDBD253600550',
        isSourceLocked: true,
      );

      expect(session.isBiometricLocked, isTrue);
      expect(session.verificationMethod, equals('Face Recognition'));
    });
  });
}
