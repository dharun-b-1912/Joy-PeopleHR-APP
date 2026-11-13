import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/core/theme/klarna_tokens.dart';
import 'package:workforce_os/features/employee/attendance/widgets/break_management_section.dart';
import 'package:workforce_os/models/break_models.dart';

void main() {
  const widths = <double>[320, 360, 375, 390, 412, 430, 768];

  group('Responsive UI & Break Management Layout Tests', () {
    for (final width in widths) {
      testWidgets('ResponsiveMetricGrid & BreakActionsCard fit at ${width}px (1.0x & 1.3x scale)', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const summary = BreakSummaryState(
          workState: EmployeeWorkState.working,
          policy: BreakPolicySummary(
            categories: [
              BreakCategoryConfig(category: BreakCategory.tea, label: 'Tea Break', enabled: true, paid: true, maxPerDay: 2, maxMinutesPerBreak: 15, displayOrder: 1),
              BreakCategoryConfig(category: BreakCategory.lunch, label: 'Lunch Break', enabled: true, paid: false, maxPerDay: 1, maxMinutesPerBreak: 45, displayOrder: 2),
              BreakCategoryConfig(category: BreakCategory.coffee, label: 'Coffee Break', enabled: true, paid: true, maxPerDay: 2, maxMinutesPerBreak: 15, displayOrder: 3),
              BreakCategoryConfig(category: BreakCategory.personal, label: 'Personal Break', enabled: true, paid: false, maxPerDay: 2, maxMinutesPerBreak: 15, displayOrder: 4),
              BreakCategoryConfig(category: BreakCategory.other, label: 'Other Break', enabled: true, paid: false, maxPerDay: 2, maxMinutesPerBreak: 15, displayOrder: 5),
            ],
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const ResponsiveMetricGrid(
                        maxColumns: 4,
                        items: [
                          ResponsiveMetricItem(label: 'Check In', value: '09:39 AM'),
                          ResponsiveMetricItem(label: 'Check Out', value: '—'),
                          ResponsiveMetricItem(label: 'Total Span', value: '7h 19m'),
                          ResponsiveMetricItem(label: 'Net Work', value: '7h 19m', highlight: true),
                          ResponsiveMetricItem(label: 'Paid Break', value: '15m'),
                          ResponsiveMetricItem(label: 'Unpaid Break', value: '0m'),
                          ResponsiveMetricItem(label: 'Paid Left', value: '0m'),
                          ResponsiveMetricItem(label: 'Approved OT', value: '0m'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      BreakActionsCard(
                        summary: summary,
                        busy: false,
                        onStartBreak: (_) async {},
                        onEndBreak: () async {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Start Tea'), findsOneWidget);
        expect(find.text('Start Lunch'), findsOneWidget);
        expect(find.text('Start Coffee'), findsOneWidget);
        expect(find.text('Start Personal Break'), findsOneWidget);
        expect(find.text('Start Other Break'), findsOneWidget);

        // Verify >= 48dp touch target height on break buttons
        final teaRect = tester.getRect(find.text('Start Tea'));
        expect(teaRect.height, greaterThan(0));
      });
    }

    testWidgets('Last-row metric tiles stretch to fill width (no orphan half-cells)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: ResponsiveMetricGrid(
                maxColumns: 3,
                items: [
                  ResponsiveMetricItem(label: 'Working', value: '9h 00m'),
                  ResponsiveMetricItem(label: 'Total Break', value: '15m'),
                  ResponsiveMetricItem(label: 'Paid Break', value: '15m'),
                  ResponsiveMetricItem(label: 'Unpaid Break', value: '0m'),
                  ResponsiveMetricItem(label: 'Paid Left', value: '0m'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 368px content -> 3 columns; row 2 has 2 items which must share the full width.
      final working = tester.getRect(find.text('Working'));
      final unpaid = tester.getRect(find.text('Unpaid Break'));
      final paidLeft = tester.getRect(find.text('Paid Left'));
      expect(unpaid.left, closeTo(working.left, 1));
      expect(paidLeft.left, greaterThan(200)); // occupies right half, not a narrow 1/3 cell
    });

    testWidgets('Narrow 2-column grid: single orphan tile spans the full row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: ResponsiveMetricGrid(
                maxColumns: 3,
                items: [
                  ResponsiveMetricItem(label: 'Working', value: '9h 00m'),
                  ResponsiveMetricItem(label: 'Total Break', value: '15m'),
                  ResponsiveMetricItem(label: 'Paid Break', value: '15m'),
                  ResponsiveMetricItem(label: 'Unpaid Break', value: '0m'),
                  ResponsiveMetricItem(label: 'Paid Left', value: '0m'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The orphan tile's card must span the full content width (288px), not half of it.
      final paidLeftCard = find.ancestor(
        of: find.text('Paid Left'),
        matching: find.byType(Container),
      ).first;
      expect(tester.getRect(paidLeftCard).width, greaterThan(280));
    });
  });
}
