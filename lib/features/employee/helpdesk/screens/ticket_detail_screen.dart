import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_relations_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';

class TicketDetailScreen extends StatelessWidget {
  final HelpdeskTicketModel ticket;

  const TicketDetailScreen({super.key, required this.ticket});

  @override
  Widget build(BuildContext context) {
    StatusType chipType = StatusType.warning;
    String statusLabel = "Open";

    if (ticket.status == HelpdeskStatus.inProgress || ticket.status == HelpdeskStatus.assigned) {
      chipType = StatusType.info;
      statusLabel = "In Progress";
    } else if (ticket.status == HelpdeskStatus.resolved || ticket.status == HelpdeskStatus.closed) {
      chipType = StatusType.success;
      statusLabel = "Resolved";
    }

    final isUrgentOrHigh =
        ticket.priority == TicketPriority.urgent || ticket.priority == TicketPriority.high;
    final priorityLabel = "${ticket.priority.name.toUpperCase()} Priority";

    final createdDateStr =
        "${ticket.createdAt.day.toString().padLeft(2, '0')}/${ticket.createdAt.month.toString().padLeft(2, '0')}/${ticket.createdAt.year}";
    final createdTimeStr =
        "${ticket.createdAt.hour.toString().padLeft(2, '0')}:${ticket.createdAt.minute.toString().padLeft(2, '0')}";

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ticket.ticketNumber,
              style: AppTypography.titleMedium.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              ticket.category,
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StatusChip(label: statusLabel, type: chipType)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Ticket Overview Card
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.lavenderBg,
                          borderRadius: AppRadius.borderSm,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.tag_fill, size: 12, color: AppColors.lavenderFg),
                            const SizedBox(width: 6),
                            Text(
                              ticket.category,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.lavenderFg,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isUrgentOrHigh ? AppColors.peachBg : AppColors.slateBg,
                          borderRadius: AppRadius.borderSm,
                        ),
                        child: Text(
                          priorityLabel,
                          style: AppTypography.caption.copyWith(
                            color: isUrgentOrHigh ? AppColors.peachFg : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.gapMD,
                  Text(
                    ticket.subject,
                    style: AppTypography.titleLarge.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  AppSpacing.gapSM,
                  const Divider(height: 1, color: AppColors.borderSubtle),
                  AppSpacing.gapSM,
                  Text(
                    "Description",
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ticket.description,
                    style: AppTypography.bodyRegular.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            AppSpacing.gapMD,

            // 2. HR Resolution Card (if resolved / answered)
            if (ticket.resolutionSummary != null && ticket.resolutionSummary!.isNotEmpty) ...[
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppColors.mintBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.checkmark_seal_fill,
                            size: 16,
                            color: AppColors.mintFg,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "HR Resolution & Notes",
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.mintFg,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.gapSM,
                    const Divider(height: 1, color: AppColors.borderSubtle),
                    AppSpacing.gapSM,
                    Text(
                      ticket.resolutionSummary!,
                      style: AppTypography.bodyRegular.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              AppSpacing.gapMD,
            ],

            // 3. Ticket Information & SLA Details Card
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Ticket Information",
                    style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  AppSpacing.gapMD,
                  _infoRow("Submitted Date", "$createdDateStr at $createdTimeStr"),
                  _infoRow("Assigned Team", ticket.assignedToName ?? "HR Operations & Support"),
                  _infoRow("Department", (ticket.department != null && ticket.department!.isNotEmpty) ? ticket.department! : "General"),
                  _infoRow("Response SLA", "${ticket.slaHours} hours response window"),
                  _infoRow(
                    "Current Status",
                    statusLabel,
                    valueColor: chipType == StatusType.success
                        ? AppColors.mintFg
                        : (chipType == StatusType.info ? AppColors.skyFg : AppColors.peachFg),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
          Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
