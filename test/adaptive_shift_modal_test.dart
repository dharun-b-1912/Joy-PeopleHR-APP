import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/widgets/attendance/adaptive_shift_modal.dart';
import 'package:workforce_os/core/services/shift_adaptive_service.dart';

void main() {
  testWidgets('AdaptiveShiftModal renders nearest auto-detected shift and available shifts correctly', (WidgetTester tester) async {
    const detectedShift = CompanyShift(
      id: 'shift-gen-corp',
      organizationId: 'org-test',
      name: 'General Day Shift (Corporate)',
      code: 'GEN-10',
      startTime: '09:30:00',
      endTime: '18:30:00',
    );

    const shift1 = CompanyShift(
      id: 'shift-1',
      organizationId: 'org-test',
      name: 'General Day Shift 1',
      code: 'GEN-01',
      startTime: '08:30:00',
      endTime: '17:30:00',
    );

    const shift2 = CompanyShift(
      id: 'shift-2',
      organizationId: 'org-test',
      name: 'General Corporate Shift 2',
      code: 'GEN-02',
      startTime: '09:00:00',
      endTime: '18:00:00',
    );

    CompanyShift? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await AdaptiveShiftModal.show(
                    context: context,
                    detectedShift: detectedShift,
                    availableShifts: const [detectedShift, shift1, shift2],
                    locationName: 'Joy Corporate Solutions Private Limited (HQ)',
                    distanceMeters: 0,
                  );
                },
                child: const Text('Open Modal'),
              );
            },
          ),
        ),
      ),
    );

    // Tap to open modal
    await tester.tap(find.text('Open Modal'));
    await tester.pumpAndSettle();

    // Verify modal title & auto-detected label
    expect(find.text('Confirm Shift Check-In'), findsOneWidget);
    expect(find.text('AUTO-DETECTED NEAREST'), findsOneWidget);
    expect(find.text('General Day Shift (Corporate)'), findsOneWidget);
    expect(find.text('• 0m away'), findsOneWidget);
    expect(find.text('Available Factory Shifts'), findsOneWidget);

    // Verify alternative factory shifts are visible
    expect(find.text('General Day Shift 1'), findsOneWidget);
    expect(find.text('General Corporate Shift 2'), findsOneWidget);

    // Verify buttons
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm & Check In'), findsOneWidget);

    // Select alternative shift
    await tester.tap(find.text('General Day Shift 1'));
    await tester.pumpAndSettle();

    // Confirm
    await tester.tap(find.text('Confirm & Check In'));
    await tester.pumpAndSettle();

    // Verify confirmed result is the selected shift
    expect(result, isNotNull);
    expect(result!.id, equals('shift-1'));
    expect(result!.name, equals('General Day Shift 1'));
  });
}

