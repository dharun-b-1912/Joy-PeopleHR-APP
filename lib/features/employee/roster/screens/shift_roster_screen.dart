import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../../../widgets/core/status_chip.dart';

class ShiftRosterScreen extends StatefulWidget {
  const ShiftRosterScreen({super.key});

  @override
  State<ShiftRosterScreen> createState() => _ShiftRosterScreenState();
}

class _ShiftRosterScreenState extends State<ShiftRosterScreen> {
  @override
  void initState() {
    super.initState();
    MoreModulesController.instance.loadAllData();
  }

  // Resolves appearance dynamically based on backend configuration & category
  _ShiftAppearance _resolveAppearance(ShiftRosterModel item, bool isToday) {
    if (item.isOffDay || item.shiftCategory == 'OFF') {
      return const _ShiftAppearance(
        bgColor: AppColors.slateBg,
        fgColor: AppColors.slateFg,
        icon: CupertinoIcons.moon_fill,
        categoryBadgeBg: Color(0xFFF1F5F9),
        categoryBadgeFg: Color(0xFF64748B),
      );
    }

    if (item.shiftCategory == 'NIGHT' || item.isOvernight) {
      return const _ShiftAppearance(
        bgColor: Color(0xFFEDE9FE),
        fgColor: Color(0xFF7C3AED),
        icon: CupertinoIcons.moon_stars_fill,
        categoryBadgeBg: Color(0xFFEDE9FE),
        categoryBadgeFg: Color(0xFF7C3AED),
      );
    }

    if (item.shiftCategory == 'EVENING') {
      return const _ShiftAppearance(
        bgColor: Color(0xFFFEF3C7),
        fgColor: Color(0xFFD97706),
        icon: CupertinoIcons.sun_haze_fill,
        categoryBadgeBg: Color(0xFFFEF3C7),
        categoryBadgeFg: Color(0xFFB45309),
      );
    }

    if (item.shiftCategory == 'MORNING') {
      return const _ShiftAppearance(
        bgColor: Color(0xFFE0F2FE),
        fgColor: Color(0xFF0284C7),
        icon: CupertinoIcons.sun_min_fill,
        categoryBadgeBg: Color(0xFFE0F2FE),
        categoryBadgeFg: Color(0xFF0369A1),
      );
    }

    // Standard Day Shift
    if (isToday) {
      return const _ShiftAppearance(
        bgColor: AppColors.mintBg,
        fgColor: AppColors.mintFg,
        icon: CupertinoIcons.sun_max_fill,
        categoryBadgeBg: AppColors.mintBg,
        categoryBadgeFg: AppColors.mintFg,
      );
    }

    return const _ShiftAppearance(
      bgColor: Color(0xFFECFDF5),
      fgColor: Color(0xFF059669),
      icon: CupertinoIcons.sun_max_fill,
      categoryBadgeBg: Color(0xFFECFDF5),
      categoryBadgeFg: Color(0xFF047857),
    );
  }

  void _showShiftDetailsSheet(BuildContext context, ShiftRosterModel item, bool isToday) {
    final appearance = _resolveAppearance(item, isToday);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header with Icon & Title
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: appearance.bgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(appearance.icon, color: appearance.fgColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.shiftName,
                            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${item.date.day}/${item.date.month}/${item.date.year}",
                            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (isToday)
                      const StatusChip(label: "Today", type: StatusType.success)
                    else if (item.isUpdated)
                      const StatusChip(
                        label: "Updated",
                        customBg: Color(0xFFFEF3C7),
                        customFg: Color(0xFFD97706),
                      )
                    else
                      StatusChip(
                        label: item.shiftCategoryLabel,
                        customBg: appearance.categoryBadgeBg,
                        customFg: appearance.categoryBadgeFg,
                      ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 16),

                // Schedule Details List
                _buildDetailRow(
                  label: "Scheduled Time",
                  value: item.isOffDay ? "Weekly Rest" : "${item.startTime} – ${item.endTime}",
                  isBold: true,
                ),
                if (!item.isOffDay) ...[
                  _buildDetailRow(
                    label: "Scheduled Span",
                    value: item.rawSpanMinutes > 0
                        ? "${item.rawSpanMinutes ~/ 60}h ${item.rawSpanMinutes % 60 > 0 ? '${item.rawSpanMinutes % 60}m' : ''}".trim()
                        : "8h 30m",
                  ),
                  _buildDetailRow(
                    label: "Configured Break",
                    value: item.breakMinutes > 0 ? "${item.breakMinutes}m" : "None",
                  ),
                  _buildDetailRow(
                    label: "Scheduled Work",
                    value: item.formattedDuration,
                    isHighlight: true,
                  ),
                  _buildDetailRow(
                    label: "Overnight Shift",
                    value: item.isOvernight ? "Yes (Crosses midnight)" : "No (Same-day)",
                  ),
                ],
                _buildDetailRow(
                  label: "Work Location",
                  value: item.location,
                ),
                _buildDetailRow(
                  label: "Shift Policy",
                  value: item.policyName,
                ),
                _buildDetailRow(
                  label: "Assigned By",
                  value: item.assignedBy,
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    bool isBold = false,
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: AppTypography.bodyRegular.copyWith(
              fontWeight: isBold || isHighlight ? FontWeight.bold : FontWeight.w500,
              color: isHighlight ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final rosters = controller.rosters;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("Shift Roster", style: AppTypography.titleLarge),
          ),
          body: controller.isLoading && rosters.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: Colors.white,
                  onRefresh: () => controller.loadAllData(),
                  child: rosters.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          children: const [
                            SizedBox(height: 80),
                            EmptyStateWidget(
                              icon: CupertinoIcons.square_grid_2x2,
                              title: "No shift roster available",
                              description: "Your schedule for this week will appear here.",
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                          itemCount: rosters.length,
                          itemBuilder: (context, index) {
                            final item = rosters[index];
                            final now = DateTime.now();
                            final isToday = now.year == item.date.year &&
                                now.month == item.date.month &&
                                now.day == item.date.day;
                            final appearance = _resolveAppearance(item, isToday);

                            return Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.md),
                              child: InkWell(
                                onTap: () => _showShiftDetailsSheet(context, item, isToday),
                                borderRadius: BorderRadius.circular(16),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Dynamic Category / Appearance Icon
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: appearance.bgColor,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Icon(
                                            appearance.icon,
                                            color: appearance.fgColor,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      AppSpacing.hGapMD,

                                      // Schedule Content Block
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Row 1: Date & Status Badges
                                            Row(
                                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                               children: [
                                                 Expanded(
                                                   child: Text(
                                                     "${item.date.day}/${item.date.month}/${item.date.year}",
                                                     style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                                                     maxLines: 1,
                                                     overflow: TextOverflow.ellipsis,
                                                   ),
                                                 ),
                                                 const SizedBox(width: 8),
                                                 if (isToday)
                                                   const StatusChip(label: "Today", type: StatusType.success)
                                                 else if (item.isUpdated)
                                                   const StatusChip(
                                                     label: "Updated",
                                                     customBg: Color(0xFFFEF3C7),
                                                     customFg: Color(0xFFD97706),
                                                   )
                                                 else if (item.shiftCategory == 'NIGHT' || item.isOvernight)
                                                   const StatusChip(
                                                     label: "Night",
                                                     customBg: Color(0xFFEDE9FE),
                                                     customFg: Color(0xFF7C3AED),
                                                   )
                                                 else if (item.shiftCategory == 'EVENING')
                                                   const StatusChip(
                                                     label: "Evening",
                                                     customBg: Color(0xFFFEF3C7),
                                                     customFg: Color(0xFFB45309),
                                                   ),
                                               ],
                                             ),
                                            const SizedBox(height: 3),

                                            // Row 2: Shift Name
                                            Text(
                                              item.shiftName,
                                              style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600),
                                            ),

                                            // Row 3: Location
                                            Text(
                                              item.location,
                                              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 6),

                                            // Row 4: Start - End & Scheduled Duration
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  item.isOffDay ? "Weekly Off" : "${item.startTime} – ${item.endTime}",
                                                  style: AppTypography.bodyRegular.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: item.isOffDay ? AppColors.textSecondary : AppColors.primary,
                                                  ),
                                                ),
                                                Text(
                                                  item.formattedDuration,
                                                  style: AppTypography.caption.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color: item.isOffDay ? AppColors.textSecondary : AppColors.textPrimary,
                                                  ),
                                                ),
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
                          },
                        ),
                ),
        );
      },
    );
  }
}

class _ShiftAppearance {
  final Color bgColor;
  final Color fgColor;
  final IconData icon;
  final Color categoryBadgeBg;
  final Color categoryBadgeFg;

  const _ShiftAppearance({
    required this.bgColor,
    required this.fgColor,
    required this.icon,
    required this.categoryBadgeBg,
    required this.categoryBadgeFg,
  });
}
