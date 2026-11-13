import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../widgets/core/app_card.dart';
import '../repositories/garment_repository.dart';

class FloorProductionQcScreen extends StatefulWidget {
  final String? initialUnitId;
  const FloorProductionQcScreen({super.key, this.initialUnitId});

  @override
  State<FloorProductionQcScreen> createState() => _FloorProductionQcScreenState();
}

class _FloorProductionQcScreenState extends State<FloorProductionQcScreen> {
  final GarmentRepository _repo = GarmentRepository.instance;
  late String _workDate;
  String? _unitId;
  String? _orderId;
  String? _styleId;
  String? _operationId;
  String _allocationMode = 'INDIVIDUAL';
  String _splitMethod = 'EQUAL';
  String? _employeeId;
  final Set<String> _sharedParticipants = {};

  final _producedCtrl = TextEditingController(text: '100');
  final _acceptedCtrl = TextEditingController(text: '96');
  final _rejectedCtrl = TextEditingController(text: '2');
  final _reworkCtrl = TextEditingController(text: '2');
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _workDate = DateTime.now().toIso8601String().split('T').first;
    _unitId = widget.initialUnitId;
    if (_repo.operations.isNotEmpty) _operationId = _repo.operations.first.id;
    if (_repo.workers.isNotEmpty) _employeeId = _repo.workers.first.employeeId;
    if (_repo.orders.isNotEmpty) {
      _orderId = _repo.orders.first.id;
      _styleId = _repo.orders.first.styleId;
    }
  }

  @override
  void dispose() {
    _producedCtrl.dispose();
    _acceptedCtrl.dispose();
    _rejectedCtrl.dispose();
    _reworkCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_operationId == null || _operationId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an operation.')));
      return;
    }
    if (_allocationMode == 'INDIVIDUAL' && (_employeeId == null || _employeeId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a worker.')));
      return;
    }

    setState(() => _submitting = true);
    final accepted = int.tryParse(_acceptedCtrl.text.trim()) ?? 0;
    final produced = int.tryParse(_producedCtrl.text.trim()) ?? 0;
    final rejected = int.tryParse(_rejectedCtrl.text.trim()) ?? 0;
    final rework = int.tryParse(_reworkCtrl.text.trim()) ?? 0;

    final workerGrade = _repo.workers.where((w) => w.employeeId == _employeeId).firstOrNull?.skillGrade;
    final estRate = _repo.resolveEstimatedRate(
      _operationId!,
      styleId: _styleId,
      orderId: _orderId,
      unitId: _unitId,
      skillGrade: workerGrade,
    );
    final estAmount = accepted * estRate;

    final payload = <String, dynamic>{
      'work_date': _workDate,
      'production_unit_id': _unitId,
      'order_id': _orderId,
      'style_id': _styleId,
      'operation_id': _operationId,
      'allocation_mode': _allocationMode,
      'shared_split_method': _allocationMode == 'SHARED_LINE' ? _splitMethod : null,
      'employee_id': _allocationMode == 'INDIVIDUAL' ? _employeeId : null,
      'produced_qty': produced,
      'accepted_qty': accepted,
      'rejected_qty': rejected,
      'rework_qty': rework,
      'applied_unit_rate': estRate,
      'computed_piece_amount': estAmount,
      'qc_status': (accepted > 0 || rejected > 0 || rework > 0) ? 'QC_VERIFIED' : 'PENDING',
      'approval_status': 'SUBMITTED',
      'rejection_reason_code': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      'client_idempotency_key': 'garm_prod_${DateTime.now().millisecondsSinceEpoch}',
    };

    final online = await _repo.submitOrQueueProductionEntry(payload);
    if (!mounted) return;
    setState(() => _submitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          online
              ? 'Submitted QC production entry (${_repo.currencyCode} ${estAmount.toStringAsFixed(2)}).'
              : 'Offline mode: Entry queued for automatic sync.',
        ),
        backgroundColor: online ? AppColors.primary : Colors.orange.shade800,
      ),
    );
    if (online) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accepted = int.tryParse(_acceptedCtrl.text.trim()) ?? 0;
    final workerGrade = _repo.workers.where((w) => w.employeeId == _employeeId).firstOrNull?.skillGrade;
    final estRate = (_operationId != null && _operationId!.isNotEmpty)
        ? _repo.resolveEstimatedRate(_operationId!, styleId: _styleId, orderId: _orderId, unitId: _unitId, skillGrade: workerGrade)
        : 0.0;
    final estAmount = accepted * estRate;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Production & QC Entry', style: AppTypography.titleLarge),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Calculation Mode', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Individual Op', style: TextStyle(fontSize: 12))),
                          selected: _allocationMode == 'INDIVIDUAL',
                          onSelected: (_) => setState(() => _allocationMode = 'INDIVIDUAL'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Shared Line', style: TextStyle(fontSize: 12))),
                          selected: _allocationMode == 'SHARED_LINE',
                          onSelected: (_) => setState(() => _allocationMode = 'SHARED_LINE'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _unitId ?? '',
                    decoration: const InputDecoration(labelText: 'Factory / Line / Unit', border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('All / Unspecified')),
                      ..._repo.units.map((u) => DropdownMenuItem(value: u.id, child: Text(u.unitName))),
                    ],
                    onChanged: (v) => setState(() => _unitId = (v == null || v.isEmpty) ? null : v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _orderId ?? '',
                    decoration: const InputDecoration(labelText: 'Production Order', border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('No Order Link')),
                      ..._repo.orders.map((o) => DropdownMenuItem(value: o.id, child: Text(o.orderNumber))),
                    ],
                    onChanged: (v) => setState(() => _orderId = (v == null || v.isEmpty) ? null : v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _operationId,
                    decoration: const InputDecoration(labelText: 'Operation *', border: OutlineInputBorder(), isDense: true),
                    items: _repo.operations
                        .map((o) => DropdownMenuItem(value: o.id, child: Text('${o.operationName} (${o.operationCode})')))
                        .toList(),
                    onChanged: (v) => setState(() => _operationId = v),
                  ),
                  const SizedBox(height: 12),
                  if (_allocationMode == 'INDIVIDUAL')
                    DropdownButtonFormField<String>(
                      initialValue: _employeeId,
                      decoration: const InputDecoration(labelText: 'Worker *', border: OutlineInputBorder(), isDense: true),
                      items: _repo.workers
                          .map((w) => DropdownMenuItem(value: w.employeeId, child: Text(w.displayName)))
                          .toList(),
                      onChanged: (v) => setState(() => _employeeId = v),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _splitMethod,
                          decoration: const InputDecoration(labelText: 'Shared Split Rule', border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'EQUAL', child: Text('EQUAL Split')),
                            DropdownMenuItem(value: 'BY_HOURS', child: Text('BY_HOURS Split')),
                            DropdownMenuItem(value: 'BY_SKILL_WEIGHT', child: Text('BY_SKILL_WEIGHT Split')),
                          ],
                          onChanged: (v) => setState(() => _splitMethod = v ?? 'EQUAL'),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: _repo.workers.map((w) {
                            final sel = _sharedParticipants.contains(w.employeeId);
                            return FilterChip(
                              label: Text(w.displayName, style: const TextStyle(fontSize: 11)),
                              selected: sel,
                              onSelected: (v) => setState(() {
                                if (v) {
                                  _sharedParticipants.add(w.employeeId);
                                } else {
                                  _sharedParticipants.remove(w.employeeId);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Production & QC Quantities', style: AppTypography.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _producedCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Produced Qty', border: OutlineInputBorder(), isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _acceptedCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Accepted QC', border: OutlineInputBorder(), isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rejectedCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Rejected Qty', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _reworkCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Rework Qty', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(labelText: 'Rejection / QC Remarks (Optional)', border: OutlineInputBorder(), isDense: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Applicable Piece Rate', style: AppTypography.caption),
                      Text('${_repo.currencyCode} ${estRate.toStringAsFixed(2)} / accepted pc', style: AppTypography.titleMedium),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Est. Earnings', style: AppTypography.caption),
                      Text(
                        '${_repo.currencyCode} ${estAmount.toStringAsFixed(2)}',
                        style: AppTypography.titleLarge.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.borderPill),
                ),
                onPressed: _submitting ? null : _submit,
                icon: const Icon(CupertinoIcons.checkmark_alt_circle_fill),
                label: Text(_submitting ? 'Submitting...' : 'Submit Production & QC Entry'),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
