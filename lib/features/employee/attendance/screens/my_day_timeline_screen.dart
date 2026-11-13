import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/attendance_service.dart';
import '../../../../core/services/attendance_time_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/break_models.dart';
import '../../../../repositories/supabase/supabase_attendance_repository.dart';
import '../widgets/break_management_section.dart';

class MyDayTimelineScreen extends StatefulWidget {
  final DateTime? initialDate;
  const MyDayTimelineScreen({super.key, this.initialDate});

  @override
  State<MyDayTimelineScreen> createState() => _MyDayTimelineScreenState();
}

class _MyDayTimelineScreenState extends State<MyDayTimelineScreen> {
  final _repo = SupabaseAttendanceRepository();
  late DateTime _selectedDate;
  Timer? _liveTicker;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _dailyRow;
  BreakSummaryState _summary = const BreakSummaryState();
  DateTime? _checkInTime;
  DateTime? _checkOutTime;
  DateTime? _scheduledShiftEnd;
  String _shiftLabel = 'General Shift';
  String _shiftWindow = '09:30 AM – 06:30 PM';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    AttendanceService.instance.addListener(_onLiveAttendanceChanged);
    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isToday) setState(() {});
    });
    _loadDay();
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    AttendanceService.instance.removeListener(_onLiveAttendanceChanged);
    super.dispose();
  }

  void _onLiveAttendanceChanged() {
    if (_isToday && mounted) {
      setState(() {
        final svc = AttendanceService.instance;
        final user = UserService.instance.currentUser;
        _summary = svc.breakSummary;
        _checkInTime = svc.session.checkInTime;
        _checkOutTime = svc.session.checkOutTime;
        _shiftLabel = user.shiftName ?? 'General Shift';
        _shiftWindow = '${user.shiftStart} – ${user.shiftEnd}';
      });
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  String get _dateKey =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-'
      '${_selectedDate.month.toString().padLeft(2, '0')}-'
      '${_selectedDate.day.toString().padLeft(2, '0')}';

  Future<void> _loadDay() async {
    if (_isToday) {
      await AttendanceService.instance.fetchTodayAttendance();
      if (!mounted) return;
      final svc = AttendanceService.instance;
      final user = UserService.instance.currentUser;
      setState(() {
        _loading = false;
        _error = null;
        _summary = svc.breakSummary;
        _checkInTime = svc.session.checkInTime;
        _checkOutTime = svc.session.checkOutTime;
        _shiftLabel = user.shiftName ?? 'General Shift';
        _shiftWindow = '${user.shiftStart} – ${user.shiftEnd}';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = UserService.instance.currentUser;
      final empId = user.resolvedEmployeeId;
      final orgId = user.organizationId ?? '';
      if (empId.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Employee profile is still syncing.';
        });
        return;
      }

      final snap = await _repo.fetchDayAttendanceSnapshot(
        employeeId: empId,
        organizationId: orgId,
        attendanceDate: _dateKey,
      );

      if (!mounted) return;

      final daily = snap['daily'] as Map<String, dynamic>?;
      final policy = snap['policy'] as BreakPolicySummary? ?? const BreakPolicySummary();
      final breaks = (snap['breaks'] as List<BreakEventModel>?) ?? const [];
      final exceptions = (snap['exceptions'] as List<BreakExceptionModel>?) ?? const [];
      final otMins = (snap['approvedOtMinutes'] as int?) ?? 0;

      final checkIn = daily?['first_check_in'] != null
          ? DateTime.tryParse(daily!['first_check_in'].toString())?.toLocal()
          : null;
      final checkOut = daily?['last_check_out'] != null
          ? DateTime.tryParse(daily!['last_check_out'].toString())?.toLocal()
          : null;

      BreakEventModel? activeBrk;
      int paidMins = 0;
      int unpaidMins = 0;
      for (final b in breaks) {
        if (b.isActive) activeBrk = b;
        final dur = b.durationMinutes ?? 0;
        if (b.isPaid) {
          paidMins += dur;
        } else {
          unpaidMins += dur;
        }
      }

      final workState = checkOut != null
          ? EmployeeWorkState.checkedOut
          : (checkIn != null
              ? (activeBrk != null ? EmployeeWorkState.onBreak : EmployeeWorkState.working)
              : EmployeeWorkState.notCheckedIn);

      final shiftMap = daily?['shifts'] is Map
          ? Map<String, dynamic>.from(daily!['shifts'] as Map)
          : null;

      DateTime? shiftEndDt;
      if (shiftMap?['end_time'] != null) {
        final parts = shiftMap!['end_time'].toString().split(':');
        if (parts.length >= 2) {
          shiftEndDt = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            int.tryParse(parts[0]) ?? 18,
            int.tryParse(parts[1]) ?? 30,
          );
        }
      }

      setState(() {
        _dailyRow = daily;
        _checkInTime = checkIn;
        _checkOutTime = checkOut;
        _scheduledShiftEnd = shiftEndDt;
        _shiftLabel = shiftMap?['name']?.toString() ?? 'General Shift';
        if (shiftMap?['start_time'] != null && shiftMap?['end_time'] != null) {
          _shiftWindow =
              '${shiftMap!['start_time'].toString().substring(0, 5)} – ${shiftMap['end_time'].toString().substring(0, 5)}';
        }
        _summary = BreakSummaryState(
          workState: workState,
          activeBreak: activeBrk,
          todayBreaks: breaks,
          exceptions: exceptions,
          policy: policy,
          paidBreakMinutes: (daily?['paid_break_minutes'] as num?)?.toInt() ?? paidMins,
          unpaidBreakMinutes:
              (daily?['unpaid_break_minutes'] as num?)?.toInt() ?? unpaidMins,
          autoDeductedBreakMinutes:
              (daily?['auto_deducted_break_minutes'] as num?)?.toInt() ?? 0,
          netPayableMinutes:
              (daily?['net_payable_minutes'] as num?)?.toInt() ?? 0,
          approvedOtMinutes: otMins,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load day timeline: $e';
      });
    }
  }

  void _changeDay(int deltaDays) {
    final next = _selectedDate.add(Duration(days: deltaDays));
    final today = DateTime.now();
    if (next.isAfter(DateTime(today.year, today.month, today.day))) return;
    setState(() => _selectedDate = next);
    _loadDay();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadDay();
    }
  }

  String _fmtMinutes(int mins) {
    final m = mins < 0 ? 0 : mins;
    final h = m ~/ 60;
    final rem = m % 60;
    return h > 0 ? '${h}h ${rem}m' : '${rem}m';
  }

  String _fmtClock(DateTime? dt) {
    if (dt == null) return '—';
    return AttendanceTimeService.formatAttendanceTime(dt);
  }

  Color _entryColor(TimelineEntryType type) {
    switch (type) {
      case TimelineEntryType.work:
        return const Color(0xFF047857);
      case TimelineEntryType.paidBreak:
        return const Color(0xFF0F766E);
      case TimelineEntryType.unpaidBreak:
        return const Color(0xFFD97706);
      case TimelineEntryType.overtime:
        return const Color(0xFF7C3AED);
      case TimelineEntryType.exception:
        return const Color(0xFFDC2626);
      case TimelineEntryType.scheduledShiftEnd:
        return const Color(0xFF64748B);
      case TimelineEntryType.checkIn:
      case TimelineEntryType.checkOut:
        return const Color(0xFF0F172A);
    }
  }

  IconData _entryIcon(TimelineEntry entry) {
    if (entry.breakEvent != null) return entry.breakEvent!.category.icon;
    switch (entry.type) {
      case TimelineEntryType.checkIn:
        return Icons.login_rounded;
      case TimelineEntryType.work:
        return Icons.work_outline_rounded;
      case TimelineEntryType.paidBreak:
        return Icons.emoji_food_beverage_rounded;
      case TimelineEntryType.unpaidBreak:
        return Icons.restaurant_rounded;
      case TimelineEntryType.overtime:
        return Icons.bolt_rounded;
      case TimelineEntryType.scheduledShiftEnd:
        return Icons.schedule_rounded;
      case TimelineEntryType.checkOut:
        return Icons.logout_rounded;
      case TimelineEntryType.exception:
        return Icons.warning_amber_rounded;
    }
  }

  Future<void> _handleBreakAction(Future<CheckInResult> Function() action) async {
    final res = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.success ? AppColors.primary : const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showEventDetail(TimelineEntry entry) {
    final color = _entryColor(entry.type);
    final brk = entry.breakEvent;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(_entryIcon(entry), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (entry.subtitle != null)
                        Text(
                          entry.subtitle!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _detailRow('Start Time', _fmtClock(entry.startAt)),
            _detailRow('End Time', entry.endAt != null ? _fmtClock(entry.endAt) : (entry.isCurrent ? 'In Progress' : '—')),
            if (entry.durationMinutes != null)
              _detailRow('Duration', _fmtMinutes(entry.durationMinutes!)),
            if (brk != null) ...[
              _detailRow('Classification', brk.isPaid ? 'Paid Break' : 'Unpaid Break'),
              _detailRow('Applicable Policy', '${_summary.policy.name} (v${_summary.policy.version})'),
              _detailRow('Start Source', brk.source),
              if (brk.endSource != null) _detailRow('End Source', brk.endSource!),
              if (brk.approvalStatus != null)
                _detailRow('Approval Status', brk.approvalStatus!),
              if (brk.correctionReferenceId != null)
                _detailRow('HR Correction Ref', brk.correctionReferenceId!),
            ],
            if (entry.exceptionEvent != null) ...[
              _detailRow('Severity', entry.exceptionEvent!.severity),
              _detailRow('Resolution Status', entry.exceptionEvent!.resolutionStatus),
              _detailRow('Details', entry.exceptionEvent!.description),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final entries = buildUnifiedAttendanceTimeline(
      checkInTime: _checkInTime,
      checkOutTime: _checkOutTime,
      scheduledShiftEnd: _scheduledShiftEnd,
      summary: _summary,
      now: _isToday ? now : (_checkOutTime ?? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59)),
    );

    final grossSpanMins = _checkInTime == null
        ? 0
        : ((_checkOutTime ?? (_isToday ? now : _checkInTime!))
            .difference(_checkInTime!)
            .inMinutes
            .clamp(0, 1440));
    final netWorkMins = _summary.netPayableMinutes > 0
        ? _summary.netPayableMinutes
        : (grossSpanMins - _summary.unpaidBreakMinutes).clamp(0, 1440);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'My Day Timeline',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleLarge.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (!_isToday)
            TextButton(
              onPressed: () {
                final t = DateTime.now();
                setState(() => _selectedDate = DateTime(t.year, t.month, t.day));
                _loadDay();
              },
              child: Text(
                'Today',
                style: AppTypography.caption.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          IconButton(
            onPressed: _loadDay,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadDay,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Date Selector Bar (responsive for 320px+ screens)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeDay(-1),
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: AppRadius.borderSm,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 15,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _isToday ? 'Today · $_dateKey' : _dateKey,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isToday ? null : () => _changeDay(1),
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5)),
              ),

            // Daily Summary Card
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.borderMd,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
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
                              _shiftLabel,
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Shift: $_shiftWindow',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.workingGreenBg,
                          borderRadius: AppRadius.borderPill,
                        ),
                        child: Text(
                          _summary.workState.name.toUpperCase(),
                          style: AppTypography.overline.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.workingGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ResponsiveMetricGrid(
                    maxColumns: 4,
                    items: [
                      ResponsiveMetricItem(label: 'Check In', value: _fmtClock(_checkInTime)),
                      ResponsiveMetricItem(label: 'Check Out', value: _fmtClock(_checkOutTime)),
                      ResponsiveMetricItem(label: 'Total Span', value: _fmtMinutes(grossSpanMins)),
                      ResponsiveMetricItem(
                        label: 'Net Work',
                        value: _fmtMinutes(netWorkMins),
                        valueColor: AppColors.workingGreen,
                        highlight: true,
                      ),
                      ResponsiveMetricItem(
                        label: 'Paid Break',
                        value: _fmtMinutes(_summary.paidBreakMinutes),
                        valueColor: AppColors.paidBreakTeal,
                      ),
                      ResponsiveMetricItem(
                        label: 'Unpaid Break',
                        value: _fmtMinutes(_summary.unpaidBreakMinutes),
                        valueColor: AppColors.unpaidBreakOrange,
                      ),
                      ResponsiveMetricItem(
                        label: 'Paid Left',
                        value: _fmtMinutes(_summary.remainingPaidAllowanceMinutes),
                        valueColor: AppColors.statusInfo,
                      ),
                      ResponsiveMetricItem(
                        label: 'Approved OT',
                        value: _fmtMinutes(_summary.approvedOtMinutes),
                        valueColor: AppColors.overtimePurple,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Shared Live Break Actions (Today only, when checked in)
            if (_isToday &&
                _summary.workState != EmployeeWorkState.notCheckedIn &&
                _summary.workState != EmployeeWorkState.checkedOut) ...[
              const SizedBox(height: AppSpacing.md),
              BreakActionsCard(
                summary: _summary,
                busy: AttendanceService.instance.isBreakProcessing,
                onStartBreak: (cat) =>
                    _handleBreakAction(() => AttendanceService.instance.startBreak(cat)),
                onEndBreak: () =>
                    _handleBreakAction(() => AttendanceService.instance.endBreak()),
              ),
            ],

            const SizedBox(height: 16),
            const Text(
              'CHRONOLOGICAL DAY TIMELINE',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 10),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  _dailyRow == null
                      ? 'No attendance or break records found for $_dateKey.'
                      : 'Attendance session has no recorded check-in timestamp.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      _buildTimelineRow(entries[i], isLast: i == entries.length - 1),
                  ],
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildTimelineRow(TimelineEntry entry, {required bool isLast}) {
    final color = _entryColor(entry.type);
    return InkWell(
      onTap: () => _showEventDetail(entry),
      borderRadius: BorderRadius.circular(10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 34,
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: entry.isCurrent ? Border.all(color: color, width: 2) : null,
                    ),
                    child: Icon(_entryIcon(entry), size: 15, color: color),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: const Color(0xFFE2E8F0)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 4 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (entry.isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'LIVE',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: color),
                            ),
                          )
                        else if (entry.durationMinutes != null && entry.durationMinutes! > 0)
                          Text(
                            _fmtMinutes(entry.durationMinutes!),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtClock(entry.startAt)}${entry.endAt != null ? " → ${_fmtClock(entry.endAt)}" : ""}'
                      '${entry.subtitle != null ? " · ${entry.subtitle}" : ""}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
