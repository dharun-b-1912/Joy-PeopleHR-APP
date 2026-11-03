// lib/core/services/shift_duration_calculator.dart
// ============================================================================
// WorkforceOS — Enterprise Shift Duration & Schedule Calculation Engine
// Clean domain service for calculating raw spans, overnight rules, breaks & net work
// ============================================================================

class ShiftCalculationResult {
  final int spanMinutes;
  final int breakMinutes;
  final int scheduledWorkMinutes;
  final bool crossesMidnight;
  final String formattedSpan;
  final String formattedScheduledWork;
  final String formattedBreak;
  final String startTimeAMPM;
  final String endTimeAMPM;

  const ShiftCalculationResult({
    required this.spanMinutes,
    required this.breakMinutes,
    required this.scheduledWorkMinutes,
    required this.crossesMidnight,
    required this.formattedSpan,
    required this.formattedScheduledWork,
    required this.formattedBreak,
    required this.startTimeAMPM,
    required this.endTimeAMPM,
  });
}

class ShiftDurationCalculator {
  const ShiftDurationCalculator._();
  static const ShiftDurationCalculator instance = ShiftDurationCalculator._();

  /// Parses 24-hour ("14:30", "14:30:00") or 12-hour ("02:30 PM") string into minutes from midnight (0..1439).
  int? parseTimeToMinutes(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty || timeStr.trim() == '—') {
      return null;
    }
    final clean = timeStr.trim();
    final ampmMatch = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$', caseSensitive: false).firstMatch(clean);
    if (ampmMatch == null) return null;

    int hour = int.tryParse(ampmMatch.group(1) ?? '0') ?? 0;
    final int minute = int.tryParse(ampmMatch.group(2) ?? '0') ?? 0;
    final String? ampm = ampmMatch.group(3)?.toUpperCase();

    if (ampm != null) {
      if (ampm == 'PM' && hour < 12) hour += 12;
      if (ampm == 'AM' && hour == 12) hour = 0;
    }
    return (hour * 60) + minute;
  }

  /// Formats any time string into 12-hour AM/PM format (e.g., "09:00 AM", "10:30 PM").
  String formatTimeAMPM(String? timeStr, {String fallback = '09:00 AM'}) {
    final mins = parseTimeToMinutes(timeStr);
    if (mins == null) return fallback;
    final hour24 = mins ~/ 60;
    final min = mins % 60;
    final ampm = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return "${hour12.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')} $ampm";
  }

  /// Determines if a shift crosses midnight into the next calendar day.
  bool isOvernight({
    required String? startTime,
    required String? endTime,
    bool? explicitCrossesMidnight,
  }) {
    if (explicitCrossesMidnight != null) return explicitCrossesMidnight;
    final start = parseTimeToMinutes(startTime);
    final end = parseTimeToMinutes(endTime);
    if (start == null || end == null) return false;
    return end < start;
  }

  /// Calculates total scheduled span in minutes between start and end.
  int calculateSpanMinutes({
    required String? startTime,
    required String? endTime,
    bool? explicitCrossesMidnight,
  }) {
    final start = parseTimeToMinutes(startTime);
    final end = parseTimeToMinutes(endTime);
    if (start == null || end == null) return 0;

    final crosses = isOvernight(
      startTime: startTime,
      endTime: endTime,
      explicitCrossesMidnight: explicitCrossesMidnight,
    );

    if (crosses || end < start) {
      return (1440 - start) + end;
    }
    return end - start;
  }

  /// Calculates net scheduled work minutes (Span - Break).
  int calculateScheduledWorkMinutes({
    required int spanMinutes,
    required int breakMinutes,
  }) {
    final net = spanMinutes - breakMinutes;
    return net > 0 ? net : 0;
  }

  /// Formats duration in minutes into clean human-readable text (e.g. "9h", "8h 30m", "45m").
  String formatDuration(int minutes) {
    if (minutes <= 0) return '0h';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${mins}m';
    }
  }

  /// Complete single-call calculator for shift schedule metadata.
  ShiftCalculationResult calculate({
    required String? startTime,
    required String? endTime,
    int? breakMinutes,
    bool? explicitCrossesMidnight,
    bool isOffDay = false,
  }) {
    if (isOffDay) {
      return const ShiftCalculationResult(
        spanMinutes: 0,
        breakMinutes: 0,
        scheduledWorkMinutes: 0,
        crossesMidnight: false,
        formattedSpan: '0h',
        formattedScheduledWork: 'No scheduled work',
        formattedBreak: '0m',
        startTimeAMPM: 'Week Off',
        endTimeAMPM: 'Week Off',
      );
    }

    final startAMPM = formatTimeAMPM(startTime, fallback: '09:00 AM');
    final endAMPM = formatTimeAMPM(endTime, fallback: '06:00 PM');
    final crosses = isOvernight(
      startTime: startTime,
      endTime: endTime,
      explicitCrossesMidnight: explicitCrossesMidnight,
    );
    final span = calculateSpanMinutes(
      startTime: startTime,
      endTime: endTime,
      explicitCrossesMidnight: crosses,
    );
    final brk = breakMinutes ?? (span >= 540 ? 60 : (span >= 480 ? 30 : 0));
    final netWork = calculateScheduledWorkMinutes(spanMinutes: span, breakMinutes: brk);

    return ShiftCalculationResult(
      spanMinutes: span,
      breakMinutes: brk,
      scheduledWorkMinutes: netWork,
      crossesMidnight: crosses,
      formattedSpan: formatDuration(span),
      formattedScheduledWork: "${formatDuration(netWork)} scheduled",
      formattedBreak: formatDuration(brk),
      startTimeAMPM: startAMPM,
      endTimeAMPM: endAMPM,
    );
  }
}
