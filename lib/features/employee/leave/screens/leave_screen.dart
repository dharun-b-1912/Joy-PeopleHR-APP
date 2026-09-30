import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/app_header.dart';
import '../../../../widgets/core/app_skeleton.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../../../widgets/core/status_chip.dart';
import '../dialogs/apply_leave_modal.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LeaveController.instance.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      LeaveController.instance.refresh();
    }
  }

  void _showApplyLeaveModal(BuildContext context) {
    showApplyLeaveModal(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: ListenableBuilder(
        listenable: LeaveController.instance,
        builder: (context, _) {
          final controller = LeaveController.instance;
          final balance = controller.balance;
          final requests = controller.requests;

          return RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: Colors.white,
            onRefresh: () => controller.refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.only(bottom: AppSpacing.bottomNavClearance),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppHeader(
                    subtitle: "Balances & Applications",
                    title: "Leave",
                  ),
                  AppSpacing.gapLG,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Dynamic / Live Leave Balance Cards
                        if (balance != null)
                          _buildBalancesSection(balance)
                        else if (controller.isLoading)
                          SizedBox(
                            height: 120,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              children: List.generate(3, (_) => AppSkeleton.leaveBalanceCard()),
                            ),
                          ),

                        AppSpacing.gapXL,

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                "Leave History",
                                style: AppTypography.titleLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _showApplyLeaveModal(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: AppRadius.borderPill),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(CupertinoIcons.add, size: 16),
                              label: const Text("Apply Leave"),
                            ),
                          ],
                        ),

                        AppSpacing.gapMD,

                        if (controller.isLoading)
                          Column(
                            children: List.generate(4, (_) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: AppSkeleton.card(height: 84),
                            )),
                          )
                        else if (requests.isEmpty)
                          EmptyStateWidget(
                            icon: CupertinoIcons.calendar,
                            title: "No leave requests yet",
                            description: "Submit your first leave request using the button above.",
                            actionLabel: "Apply Leave",
                            onAction: () => _showApplyLeaveModal(context),
                          )
                        else
                          Column(
                            children: requests.map((req) {
                              StatusType chipType = StatusType.warning;
                              String statusText = "Pending";
                              if (req.status == LeaveStatus.approved) {
                                chipType = StatusType.success;
                                statusText = "Approved";
                              } else if (req.status == LeaveStatus.rejected) {
                                chipType = StatusType.error;
                                statusText = "Rejected";
                              } else if (req.status == LeaveStatus.cancelled) {
                                chipType = StatusType.neutral;
                                statusText = "Cancelled";
                              }

                              final typeLabel = req.leaveTypeName?.isNotEmpty == true
                                  ? req.leaveTypeName!
                                  : (req.type == LeaveType.casual
                                      ? "Casual Leave"
                                      : req.type == LeaveType.sick
                                          ? "Sick Leave"
                                          : req.type == LeaveType.earned
                                              ? "Earned Leave"
                                              : req.type == LeaveType.maternity
                                                  ? "Maternity Leave"
                                                  : req.type == LeaveType.paternity
                                                      ? "Paternity Leave"
                                                      : "Leave");

                              final daysText = req.isHalfDay
                                  ? "0.5 Day (${req.halfDaySession ?? 'Half Day'})"
                                  : (req.daysCount % 1 == 0
                                      ? "${req.daysCount.toInt()} Day(s)"
                                      : "${req.daysCount} Day(s)");

                              final managerDisplay = req.managerName ?? req.approverName;

                              return Container(
                                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "$typeLabel · $daysText",
                                              style: AppTypography.titleMedium,
                                            ),
                                          ),
                                          StatusChip(label: statusText, type: chipType),
                                        ],
                                      ),
                                      AppSpacing.gapXXS,
                                      Text(
                                        "${_formatDate(req.startDate)} - ${_formatDate(req.endDate)}",
                                        style: AppTypography.bodySmall,
                                      ),
                                      if (req.reason.isNotEmpty) ...[
                                        AppSpacing.gapSM,
                                        Text(
                                          "Reason: ${req.reason}",
                                          style: AppTypography.bodyRegular.copyWith(
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                      if (req.rejectionReason?.isNotEmpty == true && req.status == LeaveStatus.rejected) ...[
                                        AppSpacing.gapXXS,
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.roseBg,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            "Rejection Note: ${req.rejectionReason}",
                                            style: AppTypography.caption.copyWith(
                                              color: AppColors.roseFg,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (managerDisplay != null && managerDisplay.isNotEmpty) ...[
                                        AppSpacing.gapXXS,
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              req.status == LeaveStatus.approved
                                                  ? "Approved by: $managerDisplay"
                                                  : "Reporting Manager: $managerDisplay",
                                              style: AppTypography.caption.copyWith(
                                                color: AppColors.textMuted,
                                              ),
                                            ),
                                            if (req.status == LeaveStatus.pending)
                                              GestureDetector(
                                                onTap: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: const Text("Cancel Leave Request"),
                                                      content: const Text("Are you sure you want to cancel this pending leave request?"),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(ctx, false),
                                                          child: const Text("No"),
                                                        ),
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(ctx, true),
                                                          style: TextButton.styleFrom(foregroundColor: AppColors.roseFg),
                                                          child: const Text("Yes, Cancel"),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true) {
                                                    await LeaveController.instance.cancelLeave(req.id);
                                                  }
                                                },
                                                child: Text(
                                                  "Withdraw Request",
                                                  style: AppTypography.caption.copyWith(
                                                    color: AppColors.roseFg,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalancesSection(LeaveBalanceModel balance) {
    if (balance.items.isNotEmpty) {
      if (balance.items.length <= 3) {
        return Row(
          children: balance.items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final availText = item.available % 1 == 0
                ? "${item.available.toInt()}"
                : "${item.available}";
            final usedText = item.used % 1 == 0
                ? "${item.used.toInt()} used"
                : "${item.used} used";
            final annualText = "${item.annualQuota % 1 == 0 ? item.annualQuota.toInt() : item.annualQuota} Annual";

            return Expanded(
              child: Container(
                margin: EdgeInsets.only(
                  right: idx < balance.items.length - 1 ? 10 : 0,
                ),
                child: _buildBalanceCard(
                  item: item,
                  title: item.leaveTypeName,
                  avail: availText,
                  used: usedText,
                  annual: annualText,
                  bg: item.colorBg ?? AppColors.mintBg,
                  fg: item.colorFg ?? AppColors.mintFg,
                ),
              ),
            );
          }).toList(),
        );
      } else {
        // Horizontally scrollable if more than 3 leave categories exist in DB
        return SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: balance.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, idx) {
              final item = balance.items[idx];
              final availText = item.available % 1 == 0
                  ? "${item.available.toInt()}"
                  : "${item.available}";
              final usedText = item.used % 1 == 0
                  ? "${item.used.toInt()} used"
                  : "${item.used} used";
              final annualText = "${item.annualQuota % 1 == 0 ? item.annualQuota.toInt() : item.annualQuota} Annual";

              return SizedBox(
                width: 120,
                child: _buildBalanceCard(
                  item: item,
                  title: item.leaveTypeName,
                  avail: availText,
                  used: usedText,
                  annual: annualText,
                  bg: item.colorBg ?? AppColors.mintBg,
                  fg: item.colorFg ?? AppColors.mintFg,
                ),
              );
            },
          ),
        );
      }
    }

    // Default state when no entitlements row exists yet in DB
    return Row(
      children: [
        Expanded(
          child: _buildBalanceCard(
            title: "Casual (CL)",
            avail: "${balance.casualAvailable.toInt()}",
            used: "${balance.casualUsed.toInt()} used",
            annual: "12 Annual",
            bg: AppColors.mintBg,
            fg: AppColors.mintFg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildBalanceCard(
            title: "Sick (SL)",
            avail: "${balance.sickAvailable.toInt()}",
            used: "${balance.sickUsed.toInt()} used",
            annual: "10 Annual",
            bg: AppColors.lavenderBg,
            fg: AppColors.lavenderFg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildBalanceCard(
            title: "Earned (EL)",
            avail: "${balance.earnedAvailable.toInt()}",
            used: "${balance.earnedUsed.toInt()} used",
            annual: "15 Annual",
            bg: AppColors.skyBg,
            fg: AppColors.skyFg,
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard({
    DynamicLeaveBalanceItem? item,
    required String title,
    required String avail,
    required String used,
    required String annual,
    required Color bg,
    required Color fg,
  }) {
    return GestureDetector(
      onTap: () => _showAccrualDetailsModal(item, title, avail, used, annual, fg),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.borderMd,
          border: Border.all(color: fg.withValues(alpha: 0.15), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: fg, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(CupertinoIcons.info_circle, size: 12, color: fg.withValues(alpha: 0.7)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              avail,
              style: AppTypography.titleLarge.copyWith(color: fg, fontWeight: FontWeight.w800, fontSize: 22),
            ),
            Text(
              "$used · $annual",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(color: fg.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccrualDetailsModal(
    DynamicLeaveBalanceItem? item,
    String title,
    String avail,
    String used,
    String annual,
    Color themeFg,
  ) {
    const monthNames = [
      "", "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ];
    final curMonthNum = DateTime.now().month;
    final curMonthName = monthNames[curMonthNum];
    final annualQuota = item?.annualQuota ?? (title.contains("Casual") ? 12.0 : title.contains("Sick") ? 10.0 : 15.0);
    final monthlyRate = item?.monthlyAccrualRate ?? (annualQuota / 12);
    final accruedTillNow = item?.accruedTillDate ?? (monthlyRate * curMonthNum);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "12-Month Automated Accrual Breakdown",
                          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark_circle_fill, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.slateBg,
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: Column(
                    children: [
                      _buildModalMetricRow("Total 12-Month Annual Quota", "${annualQuota.toStringAsFixed(annualQuota.truncateToDouble() == annualQuota ? 0 : 1)} Days"),
                      const Divider(height: 14),
                      _buildModalMetricRow("Monthly Accrual Rate", "+${monthlyRate.toStringAsFixed(2)} Day(s) / Month"),
                      const Divider(height: 14),
                      _buildModalMetricRow("Accrued Till $curMonthName (Month $curMonthNum)", "~${accruedTillNow.toStringAsFixed(1)} Days"),
                      const Divider(height: 14),
                      _buildModalMetricRow("Total Consumed / Used", used),
                      const Divider(height: 14),
                      _buildModalMetricRow("Available Current Balance", "$avail Days", isHighlight: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderPill),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Got It", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalMetricRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
            color: isHighlight ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.bold,
            color: isHighlight ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
  }
}
