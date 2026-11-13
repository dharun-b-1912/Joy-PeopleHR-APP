import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../widgets/core/app_card.dart';
import '../repositories/garment_repository.dart';

class FloorAttendanceScreen extends StatefulWidget {
  final String? initialUnitId;
  const FloorAttendanceScreen({super.key, this.initialUnitId});

  @override
  State<FloorAttendanceScreen> createState() => _FloorAttendanceScreenState();
}

class _FloorAttendanceScreenState extends State<FloorAttendanceScreen> {
  final GarmentRepository _repo = GarmentRepository.instance;
  late String _workDate;
  String? _selectedUnitId;
  bool _submitting = false;

  final Map<String, String> _statusMap = {};
  final Map<String, double> _hoursMap = {};
  final Map<String, double> _otMap = {};

  @override
  void initState() {
    super.initState();
    _workDate = DateTime.now().toIso8601String().split('T').first;
    _selectedUnitId = widget.initialUnitId;
    if (_repo.workers.isEmpty) {
      _repo.loadSupervisorWorkspace();
    }
  }

  Future<void> _submitBatch() async {
    final scoped = _repo.workers
        .where((w) => _selectedUnitId == null || _selectedUnitId!.isEmpty || w.primaryUnitId == _selectedUnitId)
        .toList();
    if (scoped.isEmpty) return;

    setState(() => _submitting = true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rows = <Map<String, dynamic>>[];

    for (var i = 0; i < scoped.length; i++) {
      final w = scoped[i];
      final st = _statusMap[w.employeeId] ?? 'PRESENT';
      final factor = st == 'PRESENT' ? 1.0 : (st == 'HALF_DAY' ? 0.5 : 0.0);
      final hrs = _hoursMap[w.employeeId] ?? (st == 'PRESENT' ? 8.0 : (st == 'HALF_DAY' ? 4.0 : 0.0));
      final ot = _otMap[w.employeeId] ?? 0.0;

      rows.add({
        'employee_id': w.employeeId,
        'work_date': _workDate,
        'production_unit_id': _selectedUnitId ?? w.primaryUnitId,
        'team_id': w.primaryTeamId,
        'status': st,
        'payable_day_factor': factor,
        'worked_hours': hrs,
        'overtime_hours': ot,
        'client_idempotency_key': 'garm_att_${ts}_$i',
      });
    }

    final syncedOnline = await _repo.submitOrQueueAttendanceBatch(rows);
    if (!mounted) return;
    setState(() => _submitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          syncedOnline
              ? 'Synced ${rows.length} attendance records to server.'
              : 'Offline mode: Queued ${rows.length} records locally for sync.',
        ),
        backgroundColor: syncedOnline ? AppColors.primary : Colors.orange.shade800,
      ),
    );
    if (syncedOnline) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final scopedWorkers = _repo.workers
            .where((w) => _selectedUnitId == null || _selectedUnitId!.isEmpty || w.primaryUnitId == _selectedUnitId)
            .toList();

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Floor Attendance', style: AppTypography.titleLarge),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.tryParse(_workDate) ?? DateTime.now(),
                                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now().add(const Duration(days: 7)),
                                );
                                if (picked != null) {
                                  setState(() => _workDate = picked.toIso8601String().split('T').first);
                                }
                              },
                              icon: const Icon(CupertinoIcons.calendar, size: 16),
                              label: Text(_workDate, style: const TextStyle(fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedUnitId ?? '',
                              isExpanded: true,
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(value: '', child: Text('All Units', overflow: TextOverflow.ellipsis)),
                                ..._repo.units.map(
                                  (u) => DropdownMenuItem(value: u.id, child: Text(u.unitName, overflow: TextOverflow.ellipsis)),
                                ),
                              ],
                              onChanged: (v) => setState(() => _selectedUnitId = (v == null || v.isEmpty) ? null : v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: scopedWorkers.isEmpty
                    ? Center(child: Text('No garment workers found.', style: AppTypography.bodySmall))
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                        itemCount: scopedWorkers.length,
                        itemBuilder: (context, idx) {
                          final w = scopedWorkers[idx];
                          final st = _statusMap[w.employeeId] ?? 'PRESENT';
                          final hrs = _hoursMap[w.employeeId] ?? (st == 'PRESENT' ? 8.0 : (st == 'HALF_DAY' ? 4.0 : 0.0));
                          final ot = _otMap[w.employeeId] ?? 0.0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          w.displayName,
                                          style: AppTypography.titleMedium,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(w.defaultWageMethod, style: AppTypography.caption.copyWith(color: AppColors.primary)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    children: ['PRESENT', 'HALF_DAY', 'ABSENT', 'LEAVE'].map((option) {
                                      final selected = st == option;
                                      return ChoiceChip(
                                        label: Text(option.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)),
                                        selected: selected,
                                        selectedColor: AppColors.primary.withValues(alpha: 0.18),
                                        onSelected: (_) {
                                          setState(() {
                                            _statusMap[w.employeeId] = option;
                                            _hoursMap[w.employeeId] = option == 'PRESENT' ? 8.0 : (option == 'HALF_DAY' ? 4.0 : 0.0);
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text('Hrs: ${hrs.toStringAsFixed(1)}', style: AppTypography.caption),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(CupertinoIcons.minus_circle, size: 18),
                                        onPressed: () => setState(() => _hoursMap[w.employeeId] = (hrs - 0.5).clamp(0.0, 24.0)),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(CupertinoIcons.plus_circle, size: 18),
                                        onPressed: () => setState(() => _hoursMap[w.employeeId] = (hrs + 0.5).clamp(0.0, 24.0)),
                                      ),
                                      const Spacer(),
                                      Text('OT: ${ot.toStringAsFixed(1)}h', style: AppTypography.caption),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(CupertinoIcons.minus_circle, size: 18),
                                        onPressed: () => setState(() => _otMap[w.employeeId] = (ot - 0.5).clamp(0.0, 12.0)),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(CupertinoIcons.plus_circle, size: 18),
                                        onPressed: () => setState(() => _otMap[w.employeeId] = (ot + 0.5).clamp(0.0, 12.0)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderPill),
                      ),
                      onPressed: _submitting ? null : _submitBatch,
                      icon: const Icon(CupertinoIcons.checkmark_shield_fill),
                      label: Text(_submitting ? 'Submitting...' : 'Save & Sync Floor Attendance (${scopedWorkers.length})'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
