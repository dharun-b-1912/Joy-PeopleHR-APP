import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/attendance_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../repositories/supabase/supabase_attendance_repository.dart';
import 'my_day_timeline_screen.dart';

class WorkHoursSummaryScreen extends StatefulWidget {
  const WorkHoursSummaryScreen({super.key});

  @override
  State<WorkHoursSummaryScreen> createState() => _WorkHoursSummaryScreenState();
}

class _WorkHoursSummaryScreenState extends State<WorkHoursSummaryScreen> {
  final _repo = SupabaseAttendanceRepository();
  String _range = 'THIS_MONTH';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, int> _approvedOtByDate = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      late DateTime from;
      if (_range == 'THIS_WEEK') {
        from = now.subtract(Duration(days: now.weekday - 1));
      } else if (_range == 'LAST_30') {
        from = now.subtract(const Duration(days: 30));
      } else {
        from = DateTime(now.year, now.month, 1);
      }

      final fromStr = _fmtDate(from);
      final toStr = _fmtDate(now);
      final empId = UserService.instance.currentUser.resolvedEmployeeId;

      final results = await Future.wait([
        _repo.fetchWorkHoursRange(
          employeeId: empId,
          fromDate: fromStr,
          toDate: toStr,
        ),
        _repo.fetchApprovedOtMinutesRange(
          employeeId: empId,
          fromDate: fromStr,
          toDate: toStr,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = results[0] as List<Map<String, dynamic>>;
        _approvedOtByDate = results[1] as Map<String, int>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load work hours summary: $e';
      });
    }
  }

  String _fmtMins(int mins) {
    final m = mins < 0 ? 0 : mins;
    final h = m ~/ 60;
    final rem = m % 60;
    return h > 0 ? '${h}h ${rem}m' : '${rem}m';
  }

  String _fmtReadableDate(String dateStr, {required bool isToday}) {
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return dateStr;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final wd = weekdays[(parsed.weekday - 1).clamp(0, 6)];
    final mo = months[(parsed.month - 1).clamp(0, 11)];
    final base = '$wd, ${parsed.day.toString().padLeft(2, '0')} $mo ${parsed.year}';
    return isToday ? '$base · Today' : base;
  }

  /// Authoritative net work minutes matching MyDayTimelineScreen:
  /// 1) Persisted net_payable_minutes (> 0)
  /// 2) Persisted total_work_minutes (> 0)
  /// 3) Live/span calculation from first_check_in..last_check_out (or now if today & active)
  int _resolveRowNetMinutes(Map<String, dynamic> r, String todayKey) {
    final persistedNet = (r['net_payable_minutes'] as num?)?.toInt() ?? 0;
    if (persistedNet > 0) return persistedNet;

    final persistedTotal = (r['total_work_minutes'] as num?)?.toInt() ?? 0;
    if (persistedTotal > 0) return persistedTotal;

    final dateStr = r['attendance_date']?.toString() ?? '';
    final isToday = dateStr == todayKey;
    final unpaid = (r['unpaid_break_minutes'] as num?)?.toInt() ?? 0;
    final autoDeduct = (r['auto_deducted_break_minutes'] as num?)?.toInt() ?? 0;

    final checkIn = r['first_check_in'] != null
        ? DateTime.tryParse(r['first_check_in'].toString())?.toLocal()
        : (isToday ? AttendanceService.instance.session.checkInTime : null);
    if (checkIn == null) return 0;

    final checkOut = r['last_check_out'] != null
        ? DateTime.tryParse(r['last_check_out'].toString())?.toLocal()
        : (isToday ? (AttendanceService.instance.session.checkOutTime ?? DateTime.now()) : null);
    if (checkOut == null) return 0;

    final gross = checkOut.difference(checkIn).inMinutes.clamp(0, 1440);
    return (gross - unpaid - autoDeduct).clamp(0, 1440);
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = _fmtDate(DateTime.now());

    int totalNet = 0;
    int totalPaidBrk = 0;
    int totalUnpaidBrk = 0;
    int totalAutoDeduct = 0;
    int totalApprovedOt = 0;
    int exceptionDays = 0;

    for (final r in _rows) {
      final dateStr = r['attendance_date']?.toString() ?? '';
      totalNet += _resolveRowNetMinutes(r, todayKey);
      totalPaidBrk += (r['paid_break_minutes'] as num?)?.toInt() ?? 0;
      totalUnpaidBrk += (r['unpaid_break_minutes'] as num?)?.toInt() ?? 0;
      totalAutoDeduct += (r['auto_deducted_break_minutes'] as num?)?.toInt() ?? 0;
      totalApprovedOt += _approvedOtByDate[dateStr] ?? 0;
      if (r['has_break_exception'] == true) exceptionDays++;
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Work Hours Summary',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleLarge.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _rangeChip('THIS_WEEK', 'This Week'),
                  _rangeChip('THIS_MONTH', 'This Month'),
                  _rangeChip('LAST_30', 'Last 30 Days'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ResponsiveMetricGrid(
                  maxColumns: 3,
                  items: [
                    ResponsiveMetricItem(
                      label: 'Net Payable',
                      value: _fmtMins(totalNet),
                      valueColor: AppColors.workingGreen,
                      highlight: true,
                    ),
                    ResponsiveMetricItem(
                      label: 'Paid Breaks',
                      value: _fmtMins(totalPaidBrk),
                      valueColor: AppColors.paidBreakTeal,
                    ),
                    ResponsiveMetricItem(
                      label: 'Unpaid + Auto',
                      value: _fmtMins(totalUnpaidBrk + totalAutoDeduct),
                      valueColor: AppColors.unpaidBreakOrange,
                    ),
                    ResponsiveMetricItem(
                      label: 'Approved OT',
                      value: _fmtMins(totalApprovedOt),
                      valueColor: AppColors.overtimePurple,
                    ),
                    ResponsiveMetricItem(
                      label: 'Days Logged',
                      value: '${_rows.length}',
                      valueColor: AppColors.textPrimary,
                    ),
                    ResponsiveMetricItem(
                      label: 'Exceptions',
                      value: '$exceptionDays',
                      valueColor: AppColors.statusError,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'DAILY BREAKDOWN (TAP TO VIEW TIMELINE)',
                style: AppTypography.overline.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.7,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.statusErrorBg,
                    borderRadius: AppRadius.borderMd,
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _error!,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.statusError),
                  ),
                )
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.borderMd,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'No attendance records found for the selected range.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyRegular,
                  ),
                )
              else
                ..._rows.map((r) {
                  final dateStr = r['attendance_date']?.toString() ?? '';
                  final parsedDate = DateTime.tryParse(dateStr);
                  final isToday = dateStr == todayKey;
                  final isActiveShift =
                      isToday && r['first_check_in'] != null && r['last_check_out'] == null;
                  final netMins = _resolveRowNetMinutes(r, todayKey);
                  final paidM = (r['paid_break_minutes'] as num?)?.toInt() ?? 0;
                  final unpaidM = (r['unpaid_break_minutes'] as num?)?.toInt() ?? 0;
                  final hasExc = r['has_break_exception'] == true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppRadius.borderMd,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 4,
                      ),
                      onTap: parsedDate == null
                          ? null
                          : () => Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (_) => MyDayTimelineScreen(initialDate: parsedDate),
                                ),
                              ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _fmtReadableDate(dateStr, isToday: isToday),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isActiveShift)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.workingGreenBg,
                                borderRadius: AppRadius.borderPill,
                              ),
                              child: Text(
                                'LIVE',
                                style: AppTypography.overline.copyWith(
                                  fontSize: 9.5,
                                  color: AppColors.workingGreen,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Paid: ${_fmtMins(paidM)} · Unpaid: ${_fmtMins(unpaidM)}${hasExc ? " · Exception" : ""}',
                          style: AppTypography.bodySmall.copyWith(
                            color: hasExc ? AppColors.statusError : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _fmtMins(netMins),
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.workingGreen,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rangeChip(String key, String label) {
    final active = _range == key;
    return ChoiceChip(
      label: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: active ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
      selected: active,
      selectedColor: AppColors.workingGreenBg,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: active ? AppColors.workingGreenBorder : const Color(0xFFE2E8F0),
      ),
      onSelected: (_) {
        setState(() => _range = key);
        _load();
      },
    );
  }
}
