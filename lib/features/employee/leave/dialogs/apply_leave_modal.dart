import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../repositories/supabase/supabase_leave_repository.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/workforce_request_modal.dart';

void showApplyLeaveModal(BuildContext context) {
  showWorkForceRequestModal(
    context: context,
    builder: (ctx) => const ApplyLeaveModal(),
  );
}

class ApplyLeaveModal extends StatefulWidget {
  const ApplyLeaveModal({super.key});

  @override
  State<ApplyLeaveModal> createState() => _ApplyLeaveModalState();
}

class _ApplyLeaveModalState extends State<ApplyLeaveModal> {
  String? _selectedTypeId;
  String _selectedTypeName = "Casual Leave";
  String _selectedTypeCode = "CL";
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  DateTime _endDate = DateTime.now().add(const Duration(days: 2));
  bool _isHalfDay = false;
  String _halfDaySession = "First Half"; // "First Half" or "Second Half"
  final TextEditingController _reasonController = TextEditingController();
  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final controller = LeaveController.instance;
    if (controller.leaveTypes.isNotEmpty) {
      final first = controller.leaveTypes.first;
      _selectedTypeId = first.id;
      _selectedTypeName = first.name;
      _selectedTypeCode = first.code;
    } else if (controller.balance?.items.isNotEmpty == true) {
      final first = controller.balance!.items.first;
      _selectedTypeId = first.leaveTypeId;
      _selectedTypeName = first.leaveTypeName;
      _selectedTypeCode = first.leaveTypeCode;
    }
  }

  double get _availableDays {
    final b = LeaveController.instance.balance;
    if (b == null) return 0;

    for (final item in b.items) {
      if ((_selectedTypeId != null && item.leaveTypeId == _selectedTypeId) ||
          item.leaveTypeCode == _selectedTypeCode ||
          item.leaveTypeName == _selectedTypeName) {
        return item.available;
      }
    }

    final lower = _selectedTypeName.toLowerCase();
    if (lower.contains('sick') || lower.contains('medical')) return b.sickAvailable;
    if (lower.contains('earned') || lower.contains('privilege') || lower.contains('annual')) return b.earnedAvailable;
    return b.casualAvailable;
  }

  double get _requestedDaysCount {
    if (_isHalfDay) return 0.5;
    final startOnly = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final endOnly = DateTime(_endDate.year, _endDate.month, _endDate.day);
    if (endOnly.isBefore(startOnly)) return 0;
    if (startOnly.isAtSameMomentAs(endOnly)) return 1.0;

    // Calculate working days excluding standard weekly offs (Saturday & Sunday)
    var workingDays = 0.0;
    var cur = startOnly;
    while (!cur.isAfter(endOnly)) {
      final isWeekend = cur.weekday == DateTime.saturday || cur.weekday == DateTime.sunday;
      if (!isWeekend) {
        workingDays += 1.0;
      }
      cur = cur.add(const Duration(days: 1));
    }

    return workingDays > 0 ? workingDays : (endOnly.difference(startOnly).inDays + 1).toDouble();
  }

  int get _calendarDaysCount {
    final startOnly = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final endOnly = DateTime(_endDate.year, _endDate.month, _endDate.day);
    if (endOnly.isBefore(startOnly)) return 0;
    return endOnly.difference(startOnly).inDays + 1;
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
        _errorText = null;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _errorText = null;
      });
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return "${dt.day} ${months[dt.month]} ${dt.year}";
  }

  Future<void> _handleSubmit() async {
    final duration = _requestedDaysCount;
    final avail = _availableDays;

    if (duration <= 0) {
      setState(() => _errorText = "Please select a valid date range.");
      return;
    }

    if (duration > avail && avail > 0) {
      setState(() => _errorText = "Requested duration ($duration days) exceeds available balance ($avail days).");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final success = await LeaveController.instance.applyLeave(
        type: SupabaseLeaveRepository.parseLeaveType(_selectedTypeName),
        leaveTypeId: _selectedTypeId,
        leaveTypeCode: _selectedTypeCode,
        leaveTypeName: _selectedTypeName,
        startDate: _startDate,
        endDate: _isHalfDay ? _startDate : _endDate,
        customDays: duration,
        isHalfDay: _isHalfDay,
        halfDaySession: _isHalfDay ? _halfDaySession : null,
        reason: _reasonController.text.trim(),
      );

      if (mounted) {
        if (success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Leave request for $duration day(s) submitted to your reporting manager."),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          setState(() {
            _errorText = LeaveController.instance.errorMessage ?? "Failed to submit leave request.";
            _isSubmitting = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = "Error submitting leave: $e";
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final avail = _availableDays;
    final duration = _requestedDaysCount;
    final user = UserService.instance.currentUser;
    final managerName = user.reportsToName?.isNotEmpty == true ? user.reportsToName! : "Reporting Manager";

    final controller = LeaveController.instance;
    final List<Map<String, String>> dynamicOptions = [];

    if (controller.leaveTypes.isNotEmpty) {
      for (final t in controller.leaveTypes) {
        dynamicOptions.add({
          'id': t.id,
          'code': t.code,
          'name': t.name,
          'label': '${t.name} (${t.code})',
        });
      }
    } else if (controller.balance?.items.isNotEmpty == true) {
      for (final item in controller.balance!.items) {
        dynamicOptions.add({
          'id': item.leaveTypeId ?? '',
          'code': item.leaveTypeCode,
          'name': item.leaveTypeName,
          'label': '${item.leaveTypeName} (${item.leaveTypeCode})',
        });
      }
    } else {
      dynamicOptions.addAll([
        {'id': 'lt-cl', 'code': 'CL', 'name': 'Casual Leave', 'label': 'Casual Leave (CL)'},
        {'id': 'lt-sl', 'code': 'SL', 'name': 'Sick Leave', 'label': 'Sick Leave (SL)'},
        {'id': 'lt-el', 'code': 'EL', 'name': 'Earned Leave', 'label': 'Earned Leave (EL)'},
      ]);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.borderLg,
            boxShadow: AppShadows.softCard,
          ),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Apply for Leave",
                            style: AppTypography.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Request time off from your organization balance.",
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.slateBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),

                AppSpacing.gapLG,

                // Dynamic Leave Type Dropdown
                Text("Leave Type", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.slateBg,
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: dynamicOptions.any((o) => o['name'] == _selectedTypeName)
                          ? _selectedTypeName
                          : dynamicOptions.first['name'],
                      isExpanded: true,
                      icon: const Icon(CupertinoIcons.chevron_down, size: 16, color: AppColors.textMuted),
                      style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      items: dynamicOptions.map((opt) {
                        return DropdownMenuItem<String>(
                          value: opt['name'],
                          child: Text(opt['label']!),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final selected = dynamicOptions.firstWhere((o) => o['name'] == val);
                          setState(() {
                            _selectedTypeName = selected['name']!;
                            _selectedTypeCode = selected['code']!;
                            _selectedTypeId = selected['id'];
                            _errorText = null;
                          });
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Available Balance Pill
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.mintBg,
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.checkmark_seal_fill, size: 16, color: AppColors.mintFg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: "$_selectedTypeName Balance: ",
                            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, color: AppColors.mintFg),
                            children: [
                              TextSpan(
                                text: "${avail.toStringAsFixed(avail.truncateToDouble() == avail ? 0 : 1)} days available",
                                style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.mintFg),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                AppSpacing.gapMD,

                // Half Day Option Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Half Day Leave", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                    CupertinoSwitch(
                      value: _isHalfDay,
                      activeTrackColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() {
                          _isHalfDay = val;
                          if (val) _endDate = _startDate;
                        });
                      },
                    ),
                  ],
                ),

                if (_isHalfDay) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _halfDaySession = "First Half"),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _halfDaySession == "First Half" ? AppColors.primary : AppColors.slateBg,
                              borderRadius: AppRadius.borderPill,
                            ),
                            child: Center(
                              child: Text(
                                "First Half (Morning)",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _halfDaySession == "First Half" ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _halfDaySession = "Second Half"),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _halfDaySession == "Second Half" ? AppColors.primary : AppColors.slateBg,
                              borderRadius: AppRadius.borderPill,
                            ),
                            child: Center(
                              child: Text(
                                "Second Half (Afternoon)",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _halfDaySession == "Second Half" ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                AppSpacing.gapMD,

                // Dates Selection
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isHalfDay ? "Date" : "Start Date", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _pickStartDate,
                            borderRadius: AppRadius.borderMd,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.slateBg,
                                borderRadius: AppRadius.borderMd,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDate(_startDate), style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                                  const Icon(CupertinoIcons.calendar, size: 16, color: AppColors.textMuted),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isHalfDay) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("End Date", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: _pickEndDate,
                              borderRadius: AppRadius.borderMd,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.slateBg,
                                  borderRadius: AppRadius.borderMd,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDate(_endDate), style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                                    const Icon(CupertinoIcons.calendar, size: 16, color: AppColors.textMuted),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                AppSpacing.gapMD,

                // Duration & Reporting Manager Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.slateBg,
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Leave Duration", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                          Text(
                            _isHalfDay
                                ? "0.5 Day ($_halfDaySession)"
                                : _calendarDaysCount > duration
                                    ? "$duration Working Day${duration == 1 ? '' : 's'} (${_calendarDaysCount - duration.toInt()} Weekend off excluded)"
                                    : "$duration Day${duration == 1 ? '' : 's'}",
                            style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Approval Routed To", style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                          Row(
                            children: [
                              const Icon(CupertinoIcons.person_crop_circle_badge_checkmark, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                managerName,
                                style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                AppSpacing.gapMD,

                // Reason input
                Text("Reason", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _reasonController,
                  maxLines: 2,
                  onChanged: (_) {
                    if (_errorText != null) setState(() => _errorText = null);
                  },
                  style: AppTypography.bodyRegular,
                  decoration: InputDecoration(
                    hintText: "Reason for time off...",
                    hintStyle: AppTypography.bodyRegular.copyWith(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.slateBg,
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.borderMd,
                      borderSide: BorderSide.none,
                    ),
                    errorText: _errorText,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),

                AppSpacing.gapLG,

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: _isSubmitting ? "Submitting..." : "Submit Leave Request",
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    isFullWidth: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
