import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/attendance_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/break_models.dart';
import '../../../../models/hrms_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../screens/my_day_timeline_screen.dart';

class BreakManagementSection extends StatefulWidget {
  final bool compact;
  const BreakManagementSection({super.key, this.compact = false});

  @override
  State<BreakManagementSection> createState() => _BreakManagementSectionState();
}

class _BreakManagementSectionState extends State<BreakManagementSection> {
  Timer? _tickTimer;
  DateTime _now = DateTime.now();
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.compact;
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  String _formatMins(int mins) {
    final safe = mins < 0 ? 0 : mins;
    final h = safe ~/ 60;
    final m = safe % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h 00m';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String _formatTimer(Duration d) {
    final safe = d.isNegative ? Duration.zero : d;
    final hh = safe.inHours.toString().padLeft(2, '0');
    final mm = (safe.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (safe.inSeconds % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String _formatClock(DateTime dt) {
    final local = dt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    return '${hour12.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $amPm';
  }

  DateTime? _parseShiftEnd(String shiftEndStr, DateTime? checkInTime) {
    if (checkInTime == null || shiftEndStr.trim().isEmpty) return null;
    try {
      final clean = shiftEndStr.trim().toUpperCase();
      final isPm = clean.contains('PM');
      final isAm = clean.contains('AM');
      final parts = clean.replaceAll(RegExp(r'[^0-9:]'), '').split(':');
      if (parts.length < 2) return null;
      var h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      if (isPm && h < 12) h += 12;
      if (isAm && h == 12) h = 0;
      var dt = DateTime(
        checkInTime.year,
        checkInTime.month,
        checkInTime.day,
        h,
        m,
      );
      if (dt.isBefore(checkInTime)) {
        dt = dt.add(const Duration(days: 1));
      }
      return dt;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleStartBreak(BreakCategory category) async {
    final summary = AttendanceService.instance.breakSummary;
    final matches = summary.policy.categories.where((c) => c.category == category);
    final cfg = matches.isNotEmpty ? matches.first : null;
    final isPaid = cfg?.paid ??
        (category == BreakCategory.tea ||
            category == BreakCategory.coffee ||
            category == BreakCategory.rest);
    final maxMins = cfg?.maxMinutesPerBreak ?? 15;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _BreakConfirmDialog(
        icon: category.icon,
        accentColor: category.themeColor,
        title: 'Start ${category.label}?',
        badgeLabel: isPaid ? 'Paid Break • Max ${maxMins}m' : 'Unpaid Break • Max ${maxMins}m',
        description:
            'Your work timer will pause and ${category.label.toLowerCase()} time will be recorded.',
        confirmLabel: category.startActionLabel,
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await AttendanceService.instance.startBreak(category);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.success ? AppColors.primary : AppColors.statusError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleEndBreak() async {
    final active = AttendanceService.instance.breakSummary.activeBreak;
    final category = active?.category ?? BreakCategory.tea;
    final elapsedMins = active != null ? active.elapsedMinutesAt(_now) : 0;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _BreakConfirmDialog(
        icon: category.icon,
        accentColor: category.themeColor,
        title: 'End ${category.label}?',
        badgeLabel: 'Elapsed: ${_formatMins(elapsedMins)}',
        description: 'Confirm to end your ${category.label.toLowerCase()} and resume working.',
        confirmLabel: 'End ${category.label}',
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await AttendanceService.instance.endBreak();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.success ? AppColors.primary : AppColors.statusError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _colorForEntry(TimelineEntry entry) {
    if (entry.isUpcoming) return const Color(0xFF64748B);
    switch (entry.type) {
      case TimelineEntryType.work:
        return const Color(0xFF059669); // Green
      case TimelineEntryType.paidBreak:
        return const Color(0xFF0D9488); // Teal
      case TimelineEntryType.unpaidBreak:
        return const Color(0xFFD97706); // Orange
      case TimelineEntryType.overtime:
        return const Color(0xFF7C3AED); // Purple
      case TimelineEntryType.exception:
        return const Color(0xFFDC2626); // Red
      case TimelineEntryType.checkIn:
      case TimelineEntryType.scheduledShiftEnd:
      case TimelineEntryType.checkOut:
        return const Color(0xFF0F172A); // Dark Navy
    }
  }

  IconData _iconForEntry(TimelineEntry entry) {
    switch (entry.type) {
      case TimelineEntryType.checkIn:
        return CupertinoIcons.arrow_right_circle_fill;
      case TimelineEntryType.work:
        return CupertinoIcons.briefcase_fill;
      case TimelineEntryType.paidBreak:
        return CupertinoIcons.flame_fill;
      case TimelineEntryType.unpaidBreak:
        return CupertinoIcons.pause_circle_fill;
      case TimelineEntryType.overtime:
        return CupertinoIcons.bolt_fill;
      case TimelineEntryType.scheduledShiftEnd:
        return CupertinoIcons.flag_fill;
      case TimelineEntryType.checkOut:
        return CupertinoIcons.checkmark_seal_fill;
      case TimelineEntryType.exception:
        return CupertinoIcons.exclamationmark_triangle_fill;
    }
  }

  void _showEventDetails(TimelineEntry entry) {
    final brk = entry.breakEvent;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconForEntry(entry), color: _colorForEntry(entry)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.title,
                    style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (entry.durationMinutes != null)
                  Text(
                    _formatMins(entry.durationMinutes!),
                    style: AppTypography.bodyRegular.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _colorForEntry(entry),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailRow(label: 'Start Time', value: _formatClock(entry.startAt)),
            if (entry.endAt != null)
              _DetailRow(label: 'End Time', value: _formatClock(entry.endAt!)),
            if (entry.subtitle != null)
              _DetailRow(label: 'Classification', value: entry.subtitle!),
            if (brk != null) ...[
              _DetailRow(label: 'Source', value: brk.source.toUpperCase()),
              if (brk.deviceStartedAt != null)
                _DetailRow(
                  label: 'Device Start',
                  value: _formatClock(brk.deviceStartedAt!),
                ),
              if (brk.deviceEndedAt != null)
                _DetailRow(
                  label: 'Device End',
                  value: _formatClock(brk.deviceEndedAt!),
                ),
              if (brk.approvalStatus != null &&
                  brk.approvalStatus != 'NOT_REQUIRED')
                _DetailRow(label: 'Approval Status', value: brk.approvalStatus!),
              if (brk.correctionReferenceId != null)
                _DetailRow(
                  label: 'HR Correction',
                  value: 'Corrected by HR (${brk.status})',
                ),
              if (brk.notes != null && brk.notes!.trim().isNotEmpty)
                _DetailRow(label: 'Notes', value: brk.notes!),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AttendanceService.instance,
      builder: (context, _) {
        final service = AttendanceService.instance;
        final session = service.session;
        final summary = service.breakSummary;
        final user = UserService.instance.currentUser;
        final busy = service.isBreakProcessing;

        final activeBreak = summary.activeBreak;
        final activeBreakElapsed = activeBreak != null
            ? _now.difference(activeBreak.startedAt)
            : Duration.zero;

        final liveBreakMins = summary.totalBreakMinutes +
            (activeBreak != null ? activeBreak.elapsedMinutesAt(_now) : 0);

        final grossElapsed = session.checkInTime != null
            ? (session.checkOutTime ?? _now).difference(session.checkInTime!)
            : Duration.zero;
        final netWorkingMins = (grossElapsed.inMinutes -
                summary.unpaidBreakMinutes -
                summary.autoDeductedBreakMinutes)
            .clamp(0, 1440);

        final scheduledEndDt = _parseShiftEnd(user.shiftEnd, session.checkInTime);
        final timeline = buildUnifiedAttendanceTimeline(
          checkInTime: session.checkInTime,
          checkOutTime: session.checkOutTime,
          summary: summary,
          now: _now,
          scheduledShiftEnd: scheduledEndDt,
        );

        final visibleTimeline = _expanded || timeline.length <= 4
            ? timeline
            : timeline.sublist(timeline.length - 4);

        final Color headerBg;
        final Color headerAccent;
        final String stateTitle;
        final Duration activeTimerDuration;

        if (summary.isOnBreak && activeBreak != null) {
          headerBg = activeBreak.isPaid
              ? const Color(0xFFF0FDFA)
              : const Color(0xFFFFFBEB);
          headerAccent = activeBreak.isPaid
              ? const Color(0xFF0D9488)
              : const Color(0xFFD97706);
          stateTitle =
              '${activeBreak.category.label.toUpperCase()} IN PROGRESS · ${activeBreak.isPaid ? "PAID" : "UNPAID"}';
          activeTimerDuration = activeBreakElapsed;
        } else if (session.status == AttendanceStatus.checkedIn) {
          headerBg = const Color(0xFFECFDF5);
          headerAccent = const Color(0xFF059669);
          stateTitle = 'WORKING NOW';
          activeTimerDuration = Duration(minutes: netWorkingMins) +
              Duration(seconds: grossElapsed.inSeconds % 60);
        } else if (session.status == AttendanceStatus.checkedOut) {
          headerBg = const Color(0xFFF1F5F9);
          headerAccent = const Color(0xFF0F172A);
          stateTitle = 'ATTENDANCE COMPLETED';
          activeTimerDuration = Duration(minutes: summary.netPayableMinutes);
        } else {
          headerBg = AppColors.slateBg;
          headerAccent = AppColors.textSecondary;
          stateTitle = 'NOT CHECKED IN';
          activeTimerDuration = Duration.zero;
        }

        // Only show eligible categories whose maxPerDay hasn't been reached, sorted by policy/display order
        final eligibleCategories = summary.policy.categories.where((cfg) {
          if (!cfg.enabled) return false;
          final usedToday = summary.todayBreaks
              .where((b) => b.category == cfg.category && b.status.toUpperCase() != 'CANCELLED')
              .length;
          return usedToday < cfg.maxPerDay;
        }).toList()
          ..sort(
            (a, b) => a.effectiveDisplayOrder.compareTo(b.effectiveDisplayOrder),
          );

        return AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Live Attendance Status & Active Timer Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius: AppRadius.borderSm,
                  border: Border.all(color: headerAccent.withValues(alpha: 0.28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: headerAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stateTitle,
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w800,
                              color: headerAccent,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        if (session.status != AttendanceStatus.notCheckedIn)
                          Text(
                            _formatTimer(activeTimerDuration),
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shift ${user.shiftStart} – ${user.shiftEnd}'
                      '${session.checkInTime != null ? " · In ${_formatClock(session.checkInTime!)}" : ""}'
                      '${session.checkOutTime != null ? " · Out ${_formatClock(session.checkOutTime!)}" : ""}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),

                    // 2. State-Aware Next Action
                    if (session.status == AttendanceStatus.checkedIn &&
                        summary.isOnBreak &&
                        activeBreak != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: busy ? null : _handleEndBreak,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: headerAccent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.borderSm,
                            ),
                          ),
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(activeBreak.category.icon, size: 18),
                          label: Text(
                            'End ${activeBreak.category.label} & Resume Work',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ] else if (session.status == AttendanceStatus.checkedIn &&
                        !summary.isOnBreak &&
                        eligibleCategories.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ResponsiveBreakActionGrid(
                        actions: eligibleCategories
                            .map(
                              (cfg) => BreakActionButtonData(
                                label: cfg.category.startActionLabel,
                                icon: cfg.category.icon,
                                accentColor: cfg.category.themeColor,
                                onPressed: busy
                                    ? null
                                    : () => _handleStartBreak(cfg.category),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // 3. Responsive Working & Break Summary Grid (Zero Horizontal Overflow)
              ResponsiveMetricGrid(
                maxColumns: 3,
                items: [
                  ResponsiveMetricItem(
                    label: 'Working',
                    value: session.status == AttendanceStatus.checkedOut &&
                            summary.netPayableMinutes > 0
                        ? _formatMins(summary.netPayableMinutes)
                        : _formatMins(netWorkingMins),
                    valueColor: AppColors.workingGreen,
                    highlight: true,
                  ),
                  ResponsiveMetricItem(
                    label: 'Total Break',
                    value: _formatMins(liveBreakMins),
                    valueColor: AppColors.textPrimary,
                  ),
                  ResponsiveMetricItem(
                    label: 'Paid Break',
                    value: _formatMins(summary.paidBreakMinutes),
                    valueColor: AppColors.paidBreakTeal,
                  ),
                  ResponsiveMetricItem(
                    label: 'Unpaid Break',
                    value: _formatMins(summary.unpaidBreakMinutes),
                    valueColor: AppColors.unpaidBreakOrange,
                  ),
                  ResponsiveMetricItem(
                    label: 'Paid Left',
                    value: '${summary.remainingPaidAllowanceMinutes}m',
                    valueColor: AppColors.statusInfo,
                  ),
                  if (summary.approvedOtMinutes > 0)
                    ResponsiveMetricItem(
                      label: 'Approved OT',
                      value: _formatMins(summary.approvedOtMinutes),
                      valueColor: AppColors.overtimePurple,
                    ),
                ],
              ),

              // 4. Home shows a prominent link to My Day Timeline; full page shows the vertical timeline
              if (widget.compact) ...[
                const SizedBox(height: AppSpacing.sm),
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => const MyDayTimelineScreen(),
                    ),
                  ),
                  borderRadius: AppRadius.borderSm,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.scaffoldBg,
                      borderRadius: AppRadius.borderSm,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Today's attendance summary",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              color: const Color(0xFF334155),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "View full timeline",
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Today's Live Attendance Timeline",
                    style: AppTypography.bodyRegular.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  if (timeline.length > 4)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded ? 'Show Recent' : 'View Full Day (${timeline.length})',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              if (timeline.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.slateBg,
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: Text(
                    'No attendance events yet today. Check in to start your live work & break timeline.',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                  ),
                )
              else
                Column(
                  children: List.generate(visibleTimeline.length, (idx) {
                    final item = visibleTimeline[idx];
                    final isLast = idx == visibleTimeline.length - 1;
                    final color = _colorForEntry(item);
                    final timeStr = item.endAt != null
                        ? '${_formatClock(item.startAt)} – ${_formatClock(item.endAt!)}'
                        : _formatClock(item.startAt);

                    return InkWell(
                      onTap: () => _showEventDetails(item),
                      borderRadius: AppRadius.borderMd,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Vertical Rail + Circular Icon
                            SizedBox(
                              width: 28,
                              child: Column(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: item.isCurrent
                                          ? color
                                          : color.withValues(alpha: 0.14),
                                      border: Border.all(
                                        color: color,
                                        width: item.isCurrent ? 2 : 1.2,
                                      ),
                                    ),
                                    child: Icon(
                                      _iconForEntry(item),
                                      size: 12,
                                      color: item.isCurrent ? Colors.white : color,
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        margin: const EdgeInsets.symmetric(vertical: 2),
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Event Card Body
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(bottom: isLast ? 2 : 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.isCurrent
                                        ? color.withValues(alpha: 0.08)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: item.isCurrent
                                          ? color.withValues(alpha: 0.45)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    item.title,
                                                    style: AppTypography.caption.copyWith(
                                                      fontWeight: FontWeight.w800,
                                                      color: item.isUpcoming
                                                          ? const Color(0xFF64748B)
                                                          : const Color(0xFF0F172A),
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (item.isCurrent) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: color,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text(
                                                      'LIVE',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.subtitle != null
                                                  ? '$timeStr · ${item.subtitle}'
                                                  : timeStr,
                                              style: AppTypography.caption.copyWith(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (item.durationMinutes != null)
                                        Text(
                                          _formatMins(item.durationMinutes!),
                                          style: AppTypography.caption.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: color,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakConfirmDialog extends StatefulWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String badgeLabel;
  final String description;
  final String confirmLabel;

  const _BreakConfirmDialog({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.badgeLabel,
    required this.description,
    required this.confirmLabel,
  });

  @override
  State<_BreakConfirmDialog> createState() => _BreakConfirmDialogState();
}

class _BreakConfirmDialogState extends State<_BreakConfirmDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _floatAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _scaleAnim = Tween<double>(begin: 0.94, end: 1.10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _floatAnim = Tween<double>(begin: 2.0, end: -4.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _pulseAnim = Tween<double>(begin: 0.14, end: 0.34).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.accentColor.withValues(alpha: _pulseAnim.value * 0.45),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.accentColor.withValues(alpha: 0.15),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                    ),
                    child: Transform.translate(
                      offset: Offset(0, _floatAnim.value),
                      child: Transform.scale(
                        scale: _scaleAnim.value,
                        child: Icon(
                          widget.icon,
                          size: 30,
                          color: widget.accentColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.badgeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: widget.accentColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.description,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: const Color(0xFF475569),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable Break Management actions card shared between Home and My Day Timeline.
class BreakActionsCard extends StatelessWidget {
  final BreakSummaryState summary;
  final bool busy;
  final Future<void> Function(BreakCategory category) onStartBreak;
  final Future<void> Function() onEndBreak;

  const BreakActionsCard({
    super.key,
    required this.summary,
    required this.busy,
    required this.onStartBreak,
    required this.onEndBreak,
  });

  @override
  Widget build(BuildContext context) {
    final active = summary.activeBreak;
    final orderedCats = List<BreakCategoryConfig>.from(summary.policy.categories)
      ..removeWhere((c) => !c.enabled)
      ..sort((a, b) => a.effectiveDisplayOrder.compareTo(b.effectiveDisplayOrder));

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                active != null ? 'BREAK IN PROGRESS' : 'BREAK MANAGEMENT',
                style: AppTypography.overline.copyWith(
                  letterSpacing: 0.7,
                  color: active != null ? active.category.themeColor : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (active != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (active.isPaid
                            ? AppColors.paidBreakTeal
                            : AppColors.unpaidBreakOrange)
                        .withValues(alpha: 0.12),
                    borderRadius: AppRadius.borderPill,
                  ),
                  child: Text(
                    active.isPaid ? 'PAID' : 'UNPAID',
                    style: AppTypography.overline.copyWith(
                      color: active.isPaid
                          ? AppColors.paidBreakTeal
                          : AppColors.unpaidBreakOrange,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (active != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: active.category.themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.borderSm,
                  ),
                ),
                onPressed: busy ? null : onEndBreak,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(active.category.icon, size: 18),
                label: Text(
                  'End ${active.category.label} & Resume Work',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            ResponsiveBreakActionGrid(
              actions: orderedCats.map((cat) {
                final used = summary.todayBreaks
                    .where((b) =>
                        b.category == cat.category &&
                        b.status.toUpperCase() != 'CANCELLED')
                    .length;
                final eligible = used < cat.maxPerDay && !busy;
                return BreakActionButtonData(
                  label: cat.category.startActionLabel,
                  icon: cat.category.icon,
                  accentColor: cat.category.themeColor,
                  onPressed: eligible ? () => onStartBreak(cat.category) : null,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
