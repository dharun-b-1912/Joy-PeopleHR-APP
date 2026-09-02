import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/attendance_service.dart';
import '../../core/theme/klarna_tokens.dart';
import '../../models/hrms_models.dart';

/// Isolated Ticker Widget for "Working Today" Hours
/// Rebuilds only this small component every second, preventing expensive parent tree rebuilds.
class AttendanceLiveTimerWidget extends StatefulWidget {
  final TextStyle? style;

  const AttendanceLiveTimerWidget({
    super.key,
    this.style,
  });

  @override
  State<AttendanceLiveTimerWidget> createState() => _AttendanceLiveTimerWidgetState();
}

class _AttendanceLiveTimerWidgetState extends State<AttendanceLiveTimerWidget> {
  Timer? _timer;
  String _formattedTime = "00:00:00";

  @override
  void initState() {
    super.initState();
    AttendanceService.instance.addListener(_onAttendanceStateChanged);
    _updateTimerState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    AttendanceService.instance.removeListener(_onAttendanceStateChanged);
    super.dispose();
  }

  void _onAttendanceStateChanged() {
    _updateTimerState();
  }

  void _updateTimerState() {
    final session = AttendanceService.instance.session;
    if (session.status == AttendanceStatus.checkedIn && session.checkInTime != null) {
      _calculateTime();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _calculateTime());
    } else if (session.status == AttendanceStatus.checkedOut) {
      _timer?.cancel();
      if ((session.netWorkingMinutes ?? 0) > 0) {
        final duration = Duration(minutes: session.netWorkingMinutes!);
        setState(() {
          _formattedTime = _formatDuration(duration);
        });
      } else if (session.checkInTime != null && session.checkOutTime != null) {
        final inTime = session.checkInTime!;
        final outTime = session.checkOutTime!;
        final inNorm = inTime.isUtc
            ? DateTime(inTime.year, inTime.month, inTime.day, inTime.hour, inTime.minute, inTime.second)
            : inTime;
        final outNorm = outTime.isUtc
            ? DateTime(outTime.year, outTime.month, outTime.day, outTime.hour, outTime.minute, outTime.second)
            : outTime;
        final duration = outNorm.difference(inNorm);
        setState(() {
          _formattedTime = _formatDuration(duration.isNegative ? Duration.zero : duration);
        });
      } else {
        setState(() {
          _formattedTime = "00:00:00";
        });
      }
    } else {
      _timer?.cancel();
      setState(() {
        _formattedTime = "00:00:00";
      });
    }
  }

  void _calculateTime() {
    final session = AttendanceService.instance.session;
    if (session.checkInTime == null) return;
    final inTime = session.checkInTime!;
    final now = DateTime.now();

    final checkInNormalized = inTime.isUtc
        ? DateTime(inTime.year, inTime.month, inTime.day, inTime.hour, inTime.minute, inTime.second)
        : inTime;
    final nowNormalized = DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second);

    final duration = nowNormalized.difference(checkInNormalized);
    if (mounted) {
      setState(() {
        _formattedTime = _formatDuration(duration.isNegative ? Duration.zero : duration);
      });
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formattedTime,
      style: widget.style ??
          AppTypography.metricLarge.copyWith(
            color: Colors.white,
            fontSize: 24,
            letterSpacing: 0.5,
          ),
    );
  }
}
