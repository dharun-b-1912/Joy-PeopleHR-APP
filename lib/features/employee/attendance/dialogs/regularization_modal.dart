import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/workforce_request_modal.dart';

void showRegularizationModal(BuildContext context) {
  showWorkForceRequestModal(
    context: context,
    builder: (ctx) => const RegularizationModal(),
  );
}

class RegularizationModal extends StatefulWidget {
  const RegularizationModal({super.key});

  @override
  State<RegularizationModal> createState() => _RegularizationModalState();
}

class _RegularizationModalState extends State<RegularizationModal> {
  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 1));

  String _allocatedShiftName = "General Shift";
  String _allocatedShiftWindow = "09:30 AM — 06:30 PM";
  bool _isOffDay = false;

  TimeOfDay _inTime = const TimeOfDay(hour: 9, minute: 30);
  TimeOfDay _outTime = const TimeOfDay(hour: 18, minute: 30);
  final TextEditingController _reasonController = TextEditingController();
  String? _errorText;

  final List<String> _quickReasons = const [
    "Forgot to check in",
    "Forgot to check out",
    "Biometric punch issue",
    "Client meeting / On site",
    "System / Mobile app issue",
  ];

  @override
  void initState() {
    super.initState();
    _updateShiftForDate(_selectedDate);
  }

  void _updateShiftForDate(DateTime date) {
    final rosters = MoreModulesController.instance.rosters;
    ShiftRosterModel? matchingRoster;

    try {
      matchingRoster = rosters.firstWhere(
        (r) => r.date.day == date.day && r.date.month == date.month && r.date.year == date.year,
      );
    } catch (_) {
      matchingRoster = null;
    }

    if (matchingRoster != null) {
      if (matchingRoster.isOffDay) {
        _isOffDay = true;
        _allocatedShiftName = "Week Off / Off Day";
        _allocatedShiftWindow = "No shift assigned for this date";
      } else {
        _isOffDay = false;
        _allocatedShiftName = matchingRoster.shiftName;
        _allocatedShiftWindow = "${matchingRoster.startTime} — ${matchingRoster.endTime}";
        _parseShiftTimes(matchingRoster.startTime, matchingRoster.endTime);
      }
    } else {
      final user = UserService.instance.currentUser;
      final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
      if (isWeekend) {
        _isOffDay = true;
        _allocatedShiftName = "Week Off";
        _allocatedShiftWindow = "No shift assigned for this date";
      } else {
        _isOffDay = false;
        _allocatedShiftName = "General Shift";
        _allocatedShiftWindow = "${user.shiftStart} — ${user.shiftEnd}";
        _parseShiftTimes(user.shiftStart, user.shiftEnd);
      }
    }
  }

  void _parseShiftTimes(String startStr, String endStr) {
    _inTime = _parseTimeOfDay(startStr) ?? const TimeOfDay(hour: 9, minute: 30);
    _outTime = _parseTimeOfDay(endStr) ?? const TimeOfDay(hour: 18, minute: 30);
  }

  TimeOfDay? _parseTimeOfDay(String timeStr) {
    try {
      final parts = timeStr.trim().split(' ');
      final times = parts[0].split(':');
      int hour = int.parse(times[0]);
      final minute = int.parse(times[1]);
      if (parts.length > 1) {
        final ampm = parts[1].toUpperCase();
        if (ampm == "PM" && hour < 12) hour += 12;
        if (ampm == "AM" && hour == 12) hour = 0;
      }
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
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
        _selectedDate = picked;
        _updateShiftForDate(picked);
      });
    }
  }

  Future<void> _pickInTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _inTime,
    );
    if (picked != null) {
      setState(() => _inTime = picked);
    }
  }

  Future<void> _pickOutTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _outTime,
    );
    if (picked != null) {
      setState(() => _outTime = picked);
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? "PM" : "AM";
    final minute = dt.minute.toString().padLeft(2, '0');
    return "${hour.toString().padLeft(2, '0')}:$minute $period";
  }

  @override
  Widget build(BuildContext context) {
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Regularize Attendance",
                            style: AppTypography.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Correct a missed or incorrect attendance record.",
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
                Text("Date", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: AppRadius.borderMd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.slateBg,
                      borderRadius: AppRadius.borderMd,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(CupertinoIcons.calendar, size: 18, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Text(
                              "${_selectedDate.day} ${_selectedDate.month == 1 ? 'Jan' : _selectedDate.month == 2 ? 'Feb' : _selectedDate.month == 3 ? 'Mar' : _selectedDate.month == 4 ? 'Apr' : _selectedDate.month == 5 ? 'May' : _selectedDate.month == 6 ? 'Jun' : _selectedDate.month == 7 ? 'Jul' : _selectedDate.month == 8 ? 'Aug' : _selectedDate.month == 9 ? 'Sep' : _selectedDate.month == 10 ? 'Oct' : _selectedDate.month == 11 ? 'Nov' : 'Dec'} ${_selectedDate.year}",
                              style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
                AppSpacing.gapMD,
                Text("Shift", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isOffDay ? AppColors.slateBg : AppColors.mintBg,
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _isOffDay ? CupertinoIcons.moon_fill : CupertinoIcons.clock_fill,
                          size: 18,
                          color: _isOffDay ? AppColors.slateFg : AppColors.mintFg,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _allocatedShiftName,
                              style: AppTypography.bodyRegular.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _isOffDay ? AppColors.slateFg : AppColors.mintFg,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _allocatedShiftWindow,
                              style: AppTypography.caption.copyWith(
                                color: (_isOffDay ? AppColors.slateFg : AppColors.mintFg).withValues(alpha: 0.85),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapMD,
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Clock In", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _pickInTime,
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
                                  Text(_formatTimeOfDay(_inTime), style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                                  const Icon(CupertinoIcons.clock, size: 16, color: AppColors.textMuted),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Clock Out", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _pickOutTime,
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
                                  Text(_formatTimeOfDay(_outTime), style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                                  const Icon(CupertinoIcons.clock, size: 16, color: AppColors.textMuted),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapMD,
                Text("Reason", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _reasonController,
                  maxLines: 3,
                  onChanged: (_) {
                    if (_errorText != null) setState(() => _errorText = null);
                  },
                  style: AppTypography.bodyRegular,
                  decoration: InputDecoration(
                    hintText: "Why do you need attendance regularization?",
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _quickReasons.map((r) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _reasonController.text = r;
                          _errorText = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.mintBg,
                          borderRadius: AppRadius.borderPill,
                        ),
                        child: Text(
                          r,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.mintFg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                AppSpacing.gapXL,
                AppButton(
                  label: "Submit Request",
                  icon: CupertinoIcons.arrow_right,
                  isFullWidth: true,
                  variant: AppButtonVariant.primaryPill,
                  onPressed: () async {
                    if (_isOffDay) {
                      setState(() => _errorText = "No shift assigned for this date (Week Off)");
                      return;
                    }

                    final reason = _reasonController.text.trim();
                    if (reason.isEmpty) {
                      setState(() => _errorText = "Please enter a reason for regularization");
                      return;
                    }

                    final inStr = _formatTimeOfDay(_inTime);
                    final outStr = _formatTimeOfDay(_outTime);

                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);

                    final success = await AttendanceDetailController.instance.submitRegularization(
                      date: _selectedDate,
                      inTime: inStr,
                      outTime: outStr,
                      reason: reason,
                      shiftName: _allocatedShiftName,
                      shiftWindow: _allocatedShiftWindow,
                    );

                    if (mounted) {
                      nav.pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(success ? "Regularization request submitted (Pending Approval)" : "Submission failed."),
                          backgroundColor: success ? AppColors.primary : AppColors.statusError,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
