import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../widgets/core/app_card.dart';
import '../../../widgets/core/status_chip.dart';
import '../repositories/garment_repository.dart';

class WorkerGarmentEarningsScreen extends StatefulWidget {
  const WorkerGarmentEarningsScreen({super.key});

  @override
  State<WorkerGarmentEarningsScreen> createState() => _WorkerGarmentEarningsScreenState();
}

class _WorkerGarmentEarningsScreenState extends State<WorkerGarmentEarningsScreen> {
  final GarmentRepository _repo = GarmentRepository.instance;

  @override
  void initState() {
    super.initState();
    _repo.loadWorkerSelfService();
  }

  void _openDisputeDialog(String? allocationId) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise Earnings Dispute'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Describe missing pieces, rate issue, or attendance mismatch...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final text = reasonCtrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _repo.raiseWorkerDispute(reason: text, targetAllocationId: allocationId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dispute raised to Supervisor & HR Payroll.')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final totalAccepted = _repo.myAllocations.fold<int>(
          0,
          (sum, a) => sum + ((a['allocated_accepted_qty'] as num?)?.toInt() ?? 0),
        );
        final totalPieceEarned = _repo.myAllocations.fold<double>(
          0.0,
          (sum, a) => sum + ((a['earned_piece_amount'] as num?)?.toDouble() ?? 0.0),
        );

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('My Garment Earnings', style: AppTypography.titleLarge),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.exclamationmark_bubble, color: AppColors.textPrimary),
                onPressed: () => _openDisputeDialog(null),
              ),
            ],
          ),
          body: !_repo.isEntitled && !_repo.isLoading
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Garment Workforce Add-On is not enabled for your organization.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _repo.loadWorkerSelfService(),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Wage Method', style: AppTypography.caption),
                                  const SizedBox(height: 4),
                                  Text(_repo.workerWageMethod, style: AppTypography.titleMedium),
                                  Text(_repo.workerPayFrequency, style: AppTypography.caption.copyWith(color: AppColors.primary)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Approved Pieces', style: AppTypography.caption),
                                  const SizedBox(height: 4),
                                  Text('$totalAccepted pcs', style: AppTypography.titleMedium.copyWith(color: AppColors.primary)),
                                  Text('${_repo.currencyCode} ${totalPieceEarned.toStringAsFixed(0)}', style: AppTypography.caption),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Advance / Loan Balance', style: AppTypography.titleMedium),
                            Text(
                              '${_repo.currencyCode} ${_repo.workerAdvanceBalance.toStringAsFixed(2)}',
                              style: AppTypography.titleMedium.copyWith(color: AppColors.alertFg),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Published Garment Payslips', style: AppTypography.titleMedium),
                      const SizedBox(height: 8),
                      if (_repo.myPayslips.isEmpty)
                        AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Text('No published garment payslips yet.', style: AppTypography.bodySmall),
                        )
                      else
                        ..._repo.myPayslips.map(
                          (p) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.wageMethodSnapshot, style: AppTypography.titleMedium),
                                      Text('Days: ${p.payableDays} • Acc: ${p.acceptedQty} pcs • Ded: ${_repo.currencyCode} ${p.totalDeductions}', style: AppTypography.caption),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('${_repo.currencyCode} ${p.netPayable.toStringAsFixed(0)}', style: AppTypography.titleMedium.copyWith(color: AppColors.primary)),
                                      StatusChip(label: p.disbursementStatus, type: StatusType.success),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Text('Daily Production & QC Breakdown', style: AppTypography.titleMedium),
                      const SizedBox(height: 8),
                      ..._repo.myAllocations.map((a) {
                        final id = a['id']?.toString();
                        final opId = a['operation_id']?.toString();
                        final op = _repo.operations.where((o) => o.id == opId).firstOrNull;
                        final acc = (a['allocated_accepted_qty'] as num?)?.toInt() ?? 0;
                        final rej = (a['allocated_rejected_qty'] as num?)?.toInt() ?? 0;
                        final rew = (a['allocated_rework_qty'] as num?)?.toInt() ?? 0;
                        final amt = (a['earned_piece_amount'] as num?)?.toDouble() ?? 0.0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.all(14),
                            onTap: () => _openDisputeDialog(id),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(op?.operationName ?? 'Production Task', style: AppTypography.titleMedium),
                                    Text('${a['work_date']} • Acc: $acc • Rej: $rej • Rework: $rew', style: AppTypography.caption),
                                  ],
                                ),
                                Text(
                                  '${_repo.currencyCode} ${amt.toStringAsFixed(0)}',
                                  style: AppTypography.titleMedium.copyWith(color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
