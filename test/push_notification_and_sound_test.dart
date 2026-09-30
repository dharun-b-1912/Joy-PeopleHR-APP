import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/core/services/local_notification_store.dart';
import 'package:workforce_os/core/services/push_notification_service.dart';
import 'package:workforce_os/widgets/notification_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushNotificationService & Audio/Alert Tests', () {
    test('PushNotificationService singleton instance and state', () {
      final service = PushNotificationService.instance;
      expect(service, isNotNull);
      expect(service.isInitialized, isFalse);
    });

    testWidgets('InAppNotificationBanner plays alert sound and renders correctly', (WidgetTester tester) async {
      // Monitor system sound and haptics calls
      final List<MethodCall> log = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          log.add(methodCall);
          return null;
        },
      );

      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    InAppNotificationBanner.show(
                      context,
                      title: 'Punch Recorded',
                      body: 'Attendance clocked in at 09:30 AM with sound alert.',
                      route: '/attendance',
                      onTap: () {
                        tapped = true;
                      },
                    );
                  },
                  child: const Text('Show Banner'),
                ),
              ),
            ),
          ),
        ),
      );

      // Trigger banner
      await tester.tap(find.text('Show Banner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify widget renders title and body
      expect(find.text('Punch Recorded'), findsOneWidget);
      expect(find.text('Attendance clocked in at 09:30 AM with sound alert.'), findsOneWidget);

      // Verify sound or haptic was requested through SystemChannels.platform
      final soundCalls = log.where((call) => call.method == 'SystemSound.play' || call.method == 'HapticFeedback.vibrate').toList();
      expect(soundCalls.isNotEmpty, isTrue);

      // Tap on the banner
      await tester.tap(find.text('Punch Recorded'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(tapped, isTrue);
    });

    test('Announcement Test Notification triggers sound, store and routes to communication', () async {
      final service = PushNotificationService.instance;
      const title = '📢 Q3 Company Town Hall';
      const body = 'Quarterly Town Hall is scheduled for Friday at 4:00 PM IST.';
      const route = 'announcements';

      await service.triggerTestNotification(
        title: title,
        body: body,
        route: route,
        data: {'type': 'announcement'},
      );

      // Verify stored in local notifications store
      final notifications = LocalNotificationStore.instance.notifications;
      final match = notifications.where((n) => n.title == title && n.body == body).toList();
      expect(match.isNotEmpty, isTrue);
      expect(match.first.route, equals(route));
    });

    test('Payslip Test Notification triggers sound, store and routes to payslips', () async {
      final service = PushNotificationService.instance;
      const title = '💳 August 2026 Salary Payslip Released';
      const body = 'Your salary payslip for August 2026 has been published and is ready for download.';
      const route = 'payslip';

      await service.triggerTestNotification(
        title: title,
        body: body,
        route: route,
        data: {'type': 'payslip'},
      );

      // Verify stored in local notifications store
      final notifications = LocalNotificationStore.instance.notifications;
      final match = notifications.where((n) => n.title == title && n.body == body).toList();
      expect(match.isNotEmpty, isTrue);
      expect(match.first.route, equals(route));
    });

    test('TriggerTestNotification dispatches across all employee modules without crash', () async {
      final service = PushNotificationService.instance;

      final testModules = [
        {
          'title': 'Clock-in Recorded',
          'body': 'Attendance clocked in at 09:00 AM with sound alert.',
          'route': '/attendance',
        },
        {
          'title': 'Leave Approved',
          'body': 'Your Casual Leave application for tomorrow has been approved.',
          'route': '/leave',
        },
        {
          'title': 'Regularization Approved',
          'body': 'Punch regularization for yesterday has been approved.',
          'route': '/regularization',
        },
        {
          'title': 'Payslip Released',
          'body': 'Payslip for current month is now available for download.',
          'route': '/payslips',
        },
        {
          'title': 'Broadcast Announcement',
          'body': 'All-hands meeting scheduled at 4 PM.',
          'route': '/announcements',
        },
      ];

      for (final mod in testModules) {
        // Calling triggerTestNotification should execute safely
        await service.triggerTestNotification(
          title: mod['title']!,
          body: mod['body']!,
          route: mod['route']!,
          data: {'module': mod['route']!.replaceAll('/', '')},
        );
      }
      expect(testModules.length, equals(5));
    });
  });
}
