import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../../../widgets/core/status_chip.dart';
import '../../../../widgets/workforce_request_modal.dart';
import '../dialogs/expense_claim_modal.dart';

class ExpenseClaimsScreen extends StatelessWidget {
  const ExpenseClaimsScreen({super.key});

  void _showNewClaimDialog(BuildContext context) {
    showWorkForceRequestModal(
      context: context,
      builder: (ctx) => const ExpenseClaimModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final claims = controller.claims;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("Expense Claims", style: AppTypography.titleLarge),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.add, color: AppColors.primary),
                onPressed: () => _showNewClaimDialog(context),
              ),
            ],
          ),
          body: controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : claims.isEmpty
                  ? EmptyStateWidget(
                      icon: CupertinoIcons.money_dollar_circle,
                      title: "No expense claims yet",
                      description: "Submit reimbursement claims with bill receipts for HR and Finance review.",
                      actionLabel: "Submit Claim",
                      onAction: () => _showNewClaimDialog(context),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                      itemCount: claims.length,
                      itemBuilder: (context, index) {
                        final item = claims[index];
                        StatusType chipType = StatusType.warning;
                        String statusLabel = "Pending Review";

                        if (item.status == ExpenseStatus.approved) {
                          chipType = StatusType.success;
                          statusLabel = "Approved";
                        } else if (item.status == ExpenseStatus.reimbursed) {
                          chipType = StatusType.info;
                          statusLabel = "Reimbursed";
                        } else if (item.status == ExpenseStatus.rejected) {
                          chipType = StatusType.error;
                          statusLabel = "Rejected";
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: AppCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            style: AppTypography.titleMedium,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (item.claimNumber != null)
                                            Text(
                                              item.claimNumber!,
                                              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    StatusChip(label: statusLabel, type: chipType),
                                  ],
                                ),
                                AppSpacing.gapXXS,
                                Text("Category: ${item.category}", style: AppTypography.bodySmall),
                                AppSpacing.gapSM,
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "₹${item.amount.toStringAsFixed(2)}",
                                          style: AppTypography.titleLarge.copyWith(color: AppColors.primary),
                                        ),
                                        if (item.approvedAmount != null && item.approvedAmount != item.amount)
                                          Text(
                                            "Approved: ₹${item.approvedAmount!.toStringAsFixed(2)}",
                                            style: AppTypography.caption.copyWith(color: AppColors.mintFg, fontWeight: FontWeight.bold),
                                          ),
                                      ],
                                    ),
                                    Text(
                                      "${item.date.day}/${item.date.month}/${item.date.year}",
                                      style: AppTypography.caption,
                                    ),
                                  ],
                                ),
                                if (item.attachmentName != null && item.attachmentName!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.slateBg,
                                      borderRadius: AppRadius.borderSm,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(CupertinoIcons.paperclip, size: 14, color: AppColors.primary),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            item.attachmentName!,
                                            style: AppTypography.caption.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (item.description.isNotEmpty) ...[
                                  const Divider(height: 16, color: AppColors.borderSubtle),
                                  Text(item.description, style: AppTypography.bodyRegular),
                                ],
                                if (item.rejectionReason != null && item.rejectionReason!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    "Rejection Reason: ${item.rejectionReason}",
                                    style: AppTypography.caption.copyWith(color: AppColors.statusError, fontWeight: FontWeight.bold),
                                  ),
                                ],
                                if (item.reimbursementReference != null && item.reimbursementReference!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    "Ref: ${item.reimbursementReference}",
                                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showNewClaimDialog(context),
            backgroundColor: AppColors.primary,
            icon: const Icon(CupertinoIcons.add, color: Colors.white),
            label: Text("New Claim", style: AppTypography.bodyLarge.copyWith(color: Colors.white)),
          ),
        );
      },
    );
  }
}
