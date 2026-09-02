import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_relations_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';

class ServiceRequestDetailScreen extends StatelessWidget {
  final ServiceRequestModel request;

  const ServiceRequestDetailScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    StatusType chipType = StatusType.warning;
    String statusLabel = "Submitted";

    if (request.status == 'APPROVED' || request.status == 'COMPLETED') {
      chipType = StatusType.success;
      statusLabel = "Completed";
    } else if (request.status == 'IN_REVIEW' || request.status == 'PROCESSING') {
      chipType = StatusType.info;
      statusLabel = "Processing";
    } else if (request.status == 'ACTION_REQUIRED') {
      chipType = StatusType.error;
      statusLabel = "Action Required";
    } else if (request.status == 'REJECTED') {
      chipType = StatusType.error;
      statusLabel = "Rejected";
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(request.requestNumber, style: AppTypography.titleMedium.copyWith(fontFamily: 'monospace')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StatusChip(label: statusLabel, type: chipType)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service Header Card
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.serviceName, style: AppTypography.titleLarge),
                  const SizedBox(height: 4),
                  Text("Category: ${request.category}", style: AppTypography.caption),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Submitted: ${request.submittedAt.day}/${request.submittedAt.month}/${request.submittedAt.year}",
                        style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                      ),
                      if (request.assignedToName != null)
                        Text(
                          "Agent: ${request.assignedToName}",
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Submitted Form Data Recap
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Submitted Information", style: AppTypography.titleMedium),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  ...request.formData.entries.map((entry) {
                    final keyLabel = entry.key.replaceAll('_', ' ').toUpperCase();
                    final valStr = entry.value.toString();

                    if (valStr.startsWith('http')) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.paperclip, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Attached File ($keyLabel)",
                                style: AppTypography.bodyRegular.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(keyLabel, style: AppTypography.caption.copyWith(fontSize: 10, color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          Text(valStr, style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            if (request.resolutionNotes != null && request.resolutionNotes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.mintBg,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: AppColors.mintFg.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(CupertinoIcons.checkmark_shield_fill, color: AppColors.mintFg, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("HR Processing Summary", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.mintFg)),
                          const SizedBox(height: 4),
                          Text(request.resolutionNotes!, style: AppTypography.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (request.rejectionReason != null && request.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.alertBg,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: AppColors.alertFg.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: AppColors.alertFg, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Rejection Reason", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.alertFg)),
                          const SizedBox(height: 4),
                          Text(request.rejectionReason!, style: AppTypography.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
