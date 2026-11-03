import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/core/theme/klarna_tokens.dart';
import 'package:workforce_os/widgets/core/app_card.dart';
import 'package:workforce_os/widgets/core/status_chip.dart';

void main() {
  group('QA-2: Real Device Form Factor & Responsive Layout Tests', () {
    testWidgets('Small Device (375x812) layout renders without RenderFlex overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            primaryColor: AppColors.primary,
            scaffoldBackgroundColor: AppColors.surfaceWhite,
          ),
          home: Scaffold(
            appBar: AppBar(
              title: const Text("Timesheet"),
              backgroundColor: Colors.white,
            ),
            body: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.slateBg,
                                  borderRadius: AppRadius.borderSm,
                                ),
                                child: Text("28 Aug", style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Text("8h 0m", style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary)),
                            ],
                          ),
                          const StatusChip(
                            type: StatusType.success,
                            label: "Present",
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("IN: 09:30 AM", style: AppTypography.caption),
                          Text("OUT: 06:30 PM", style: AppTypography.caption),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.slateBg,
                                  borderRadius: AppRadius.borderSm,
                                ),
                                child: Text("31 Aug", style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Text("—", style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary)),
                            ],
                          ),
                          const StatusChip(
                            type: StatusType.neutral,
                            label: "Pending Check-In",
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("IN: —", style: AppTypography.caption),
                          Text("OUT: —", style: AppTypography.caption),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text("28 Aug"), findsOneWidget);
      expect(find.text("Present"), findsOneWidget);
      expect(find.text("31 Aug"), findsOneWidget);
      expect(find.text("Pending Check-In"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Large Device (390x844) layout renders cleanly with zero overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            primaryColor: AppColors.primary,
            scaffoldBackgroundColor: AppColors.surfaceWhite,
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text("Attendance & Leave")),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("August 2026 Attendance Summary", style: AppTypography.titleMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildStatItem("Present", "1", AppColors.mintFg)),
                            Expanded(child: _buildStatItem("Week Off", "10", AppColors.slateFg)),
                            Expanded(child: _buildStatItem("Absent LOP", "19", AppColors.peachFg)),
                            Expanded(child: _buildStatItem("Scheduled", "1", AppColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text("August 2026 Attendance Summary"), findsOneWidget);
      expect(find.text("Present"), findsOneWidget);
      expect(find.text("Absent LOP"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _buildStatItem(String label, String value, Color color) {
  return Column(
    children: [
      Text(
        value,
        style: AppTypography.titleLarge.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(label, style: AppTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
  );
}
