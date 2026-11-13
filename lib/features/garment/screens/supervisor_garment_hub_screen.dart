import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../widgets/core/app_card.dart';
import '../../../widgets/core/status_chip.dart';
import '../repositories/garment_repository.dart';
import 'floor_attendance_screen.dart';
import 'floor_production_qc_screen.dart';
import 'worker_garment_earnings_screen.dart';

class SupervisorGarmentHubScreen extends StatefulWidget {
  const SupervisorGarmentHubScreen({super.key});

  @override
  State<SupervisorGarmentHubScreen> createState() => _SupervisorGarmentHubScreenState();
}

class _SupervisorGarmentHubScreenState extends State<SupervisorGarmentHubScreen> {
  final GarmentRepository _repo = GarmentRepository.instance;
  String? _selectedUnitId;

  @override
  void initState() {
    super.initState();
    _repo.loadSupervisorWorkspace();
  }

  Future<void> _syncOffline() async {
    try {
      final count = await _repo.syncOfflineQueue();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced $count queued offline entry(ies) successfully.'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed (still queued locally): $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final totalPending = _repo.queuedAttendanceCount + _repo.queuedProductionCount;
        final totalAccepted = _repo.recentEntries.fold<int>(0, (s, e) => s + e.acceptedQty);
        final totalProduced = _repo.recentEntries.fold<int>(0, (s, e) => s + e.producedQty);

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Garment Floor Hub', style: AppTypography.titleLarge),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.refresh, color: AppColors.textPrimary),
                onPressed: () => _repo.loadSupervisorWorkspace(),
              ),
            ],
          ),
          body: !_repo.isEntitled && !_repo.isLoading
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AppCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.lock_shield_fill, size: 42, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text('Garment Workforce Add-On Disabled', style: AppTypography.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            'Ask your Organization Admin to activate garment_workforce in the web SaaS Add-On controls.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _repo.loadSupervisorWorkspace(),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                    children: [
                      if (totalPending > 0) ...[
                        AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.cloud_upload_fill, color: Colors.orange),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$totalPending offline floor record(s) queued locally',
                                  style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _syncOffline,
                                child: const Text('Sync Now'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedUnitId ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Active Factory / Line',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('All Factory Units & Lines')),
                            ..._repo.units.map((u) => DropdownMenuItem(value: u.id, child: Text('${u.unitName} (${u.unitCode})'))),
                          ],
                          onChanged: (v) => setState(() => _selectedUnitId = (v == null || v.isEmpty) ? null : v),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Active Workers', style: AppTypography.caption),
                                  const SizedBox(height: 4),
                                  Text('${_repo.workers.length}', style: AppTypography.titleLarge),
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
                                  Text('Recent Accepted', style: AppTypography.caption),
                                  const SizedBox(height: 4),
                                  Text('$totalAccepted / $totalProduced', style: AppTypography.titleLarge.copyWith(color: AppColors.primary)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _actionCard(
                        icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                        title: '1. Daily Floor Attendance & OT',
                        subtitle: 'Bulk mark Present, Half-Day, Absent, Leave & Overtime',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(builder: (_) => FloorAttendanceScreen(initialUnitId: _selectedUnitId)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _actionCard(
                        icon: CupertinoIcons.scissors,
                        title: '2. Production & QC Output Entry',
                        subtitle: 'Log Individual or Shared-Line accepted/rejected/rework pieces',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(builder: (_) => FloorProductionQcScreen(initialUnitId: _selectedUnitId)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _actionCard(
                        icon: CupertinoIcons.money_dollar_circle,
                        title: '3. Worker Piece Earnings View',
                        subtitle: 'Check personal wage breakdown, payslips & raise disputes',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(builder: (_) => const WorkerGarmentEarningsScreen()),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Recent Floor Entries', style: AppTypography.titleMedium),
                      const SizedBox(height: 8),
                      ..._repo.recentEntries.take(10).map((e) {
                        final op = _repo.operations.where((o) => o.id == e.operationId).firstOrNull;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(op?.operationName ?? 'Operation', style: AppTypography.titleMedium),
                                    Text('${e.workDate} • Prod: ${e.producedQty} • Acc: ${e.acceptedQty} • Rej: ${e.rejectedQty}', style: AppTypography.caption),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${_repo.currencyCode} ${e.computedPieceAmount.toStringAsFixed(0)}', style: AppTypography.titleMedium.copyWith(color: AppColors.primary)),
                                    StatusChip(
                                      label: e.qcStatus,
                                      type: e.qcStatus == 'QC_VERIFIED' ? StatusType.success : StatusType.warning,
                                    ),
                                  ],
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

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.mintBg, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleMedium),
                Text(subtitle, style: AppTypography.bodySmall),
              ],
            ),
          ),
          const Icon(CupertinoIcons.chevron_forward, size: 16, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
