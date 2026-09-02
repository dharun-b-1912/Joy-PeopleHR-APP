import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_relations_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';

class CommunicationDetailScreen extends StatefulWidget {
  final CommunicationModel communication;

  const CommunicationDetailScreen({super.key, required this.communication});

  @override
  State<CommunicationDetailScreen> createState() => _CommunicationDetailScreenState();
}

class _CommunicationDetailScreenState extends State<CommunicationDetailScreen> {
  bool _isAcknowledging = false;
  late bool _isAcknowledged;

  @override
  void initState() {
    super.initState();
    _isAcknowledged = widget.communication.acknowledgedAt != null;
  }

  Future<void> _handleAcknowledge() async {
    setState(() => _isAcknowledging = true);
    final ok = await MoreModulesController.instance.acknowledgeCommunication(widget.communication.id);
    if (mounted) {
      setState(() {
        _isAcknowledging = false;
        if (ok) _isAcknowledged = true;
      });
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✓ Communication acknowledged successfully!"),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final comm = widget.communication;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Company Announcement", style: AppTypography.titleLarge),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Card
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.lavenderBg,
                          borderRadius: AppRadius.borderSm,
                        ),
                        child: Text(
                          comm.communicationType,
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.lavenderFg),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (comm.priority == 'URGENT')
                        const StatusChip(label: "URGENT", type: StatusType.error)
                      else if (comm.priority == 'IMPORTANT')
                        const StatusChip(label: "IMPORTANT", type: StatusType.warning),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(comm.title, style: AppTypography.titleLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(CupertinoIcons.person_crop_circle, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text("By ${comm.authorName}", style: AppTypography.caption),
                      const SizedBox(width: 12),
                      const Icon(CupertinoIcons.calendar, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        "${comm.publishAt.day}/${comm.publishAt.month}/${comm.publishAt.year}",
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Message Body
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comm.body,
                    style: AppTypography.bodyRegular.copyWith(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Mandatory Acknowledgement Action Box
            if (comm.requiresAcknowledgement) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isAcknowledged ? AppColors.mintBg : Colors.white,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(
                    color: _isAcknowledged ? AppColors.mintFg.withValues(alpha: 0.3) : AppColors.borderSubtle,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isAcknowledged ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.exclamationmark_circle_fill,
                          color: _isAcknowledged ? AppColors.mintFg : AppColors.alertFg,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isAcknowledged ? "Acknowledged" : "Employee Sign-off Required",
                                style: AppTypography.titleMedium.copyWith(
                                  color: _isAcknowledged ? AppColors.mintFg : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                _isAcknowledged
                                    ? "You acknowledged this communication."
                                    : "Please confirm that you have read and understood this company announcement.",
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!_isAcknowledged) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _isAcknowledging ? null : _handleAcknowledge,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
                          ),
                          child: _isAcknowledging
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  "Acknowledge & Confirm Receipt",
                                  style: AppTypography.bodyRegular.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
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
