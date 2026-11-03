import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../../../widgets/core/status_chip.dart';

class PerformanceScreen extends StatelessWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final goals = controller.goals;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("Performance & OKRs", style: AppTypography.titleLarge),
          ),
          body: controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : goals.isEmpty
                  ? const EmptyStateWidget(
                      icon: CupertinoIcons.scope,
                      title: "No goals assigned",
                      description: "Your quarterly OKRs and key results will appear here.",
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                      itemCount: goals.length,
                      itemBuilder: (context, index) {
                        final item = goals[index];
                        final percentInt = (item.progressPercent * 100).toInt();

                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: AppCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(item.title, style: AppTypography.titleMedium),
                                    ),
                                    StatusChip(
                                      label: item.status,
                                      type: item.status == "Achieved" ? StatusType.success : StatusType.info,
                                    ),
                                  ],
                                ),
                                AppSpacing.gapXXS,
                                Text("Category: ${item.category}", style: AppTypography.bodySmall),
                                Text("Target: ${item.targetDate}", style: AppTypography.caption),
                                AppSpacing.gapMD,
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("Progress", style: AppTypography.caption),
                                    Text("$percentInt%", style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: item.progressPercent,
                                    backgroundColor: AppColors.slateBg,
                                    color: AppColors.primary,
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }
}
