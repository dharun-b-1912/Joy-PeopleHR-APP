// attendance_time_service.dart
// ============================================================================
// WorkForceOS — Centralized Attendance Time & Timezone Service
// Enforces UTC Database Contract with Authoritative Organization Timezone Rendering
// ============================================================================

import '../utils/secure_log.dart';

class AttendanceTimeService {
  static const String defaultTimezone = 'Asia/Kolkata';
  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  /// Resolves the timezone offset for a configured timezone identifier
  static Duration getOffset([String? timezone]) {
    final tz = (timezone ?? defaultTimezone).toLowerCase();
    if (tz.contains('kolkata') || tz.contains('ist') || tz.contains('india') || tz.contains('calcutta')) {
      return istOffset;
    }
    return istOffset; // Default to India Standard Time (UTC+05:30)
  }

  /// Converts any [DateTime] instance to the authoritative organization local time
  static DateTime toOrganizationTime(DateTime dt, [String? timezone]) {
    final utc = dt.toUtc();
    final offset = getOffset(timezone);
    final adjusted = utc.add(offset);
    return DateTime(
      adjusted.year,
      adjusted.month,
      adjusted.day,
      adjusted.hour,
      adjusted.minute,
      adjusted.second,
      adjusted.millisecond,
      adjusted.microsecond,
    );
  }

  /// Returns current DateTime in organization timezone
  static DateTime nowLocal([String? timezone]) => toOrganizationTime(DateTime.now().toUtc(), timezone);

  /// Parses a raw backend timestamptz string or ISO timestamp into an organization local [DateTime].
  ///
  /// Supports:
  ///   - Postgres timestamptz: '2026-08-25T09:42:41.780231+00:00', '2026-08-25 12:34:32.174602+00'
  ///   - ISO 8601 UTC: '2026-08-25T09:42:41Z'
  ///   - Plain TIME strings: '15:12:41', '09:30 AM', '18:30'
  static DateTime? parseServerTimestamp(dynamic raw, {String? timezone, String? referenceDate}) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty || str == 'null' || str == '—') return null;

    // 1. Check for ISO / Postgres timestamptz with date component
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return toOrganizationTime(parsed, timezone);
    }

    // 2. Parse 12-hour or 24-hour time strings (e.g. "03:12 PM", "15:12:41", "09:30")
    final match12 = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)$', caseSensitive: false).firstMatch(str);
    if (match12 != null) {
      int h = int.parse(match12.group(1)!);
      final m = int.parse(match12.group(2)!);
      final s = match12.group(3) != null ? int.parse(match12.group(3)!) : 0;
      final isPm = match12.group(4)!.toUpperCase() == 'PM';
      if (isPm && h < 12) h += 12;
      if (!isPm && h == 12) h = 0;

      final base = _resolveBaseDate(referenceDate, timezone);
      return DateTime(base.year, base.month, base.day, h, m, s);
    }

    final match24 = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(str);
    if (match24 != null) {
      final h = int.parse(match24.group(1)!);
      final m = int.parse(match24.group(2)!);
      final s = match24.group(3) != null ? int.parse(match24.group(3)!) : 0;

      final base = _resolveBaseDate(referenceDate, timezone);
      return DateTime(base.year, base.month, base.day, h, m, s);
    }

    return null;
  }

  static DateTime _resolveBaseDate(String? referenceDate, String? timezone) {
    if (referenceDate != null && referenceDate.isNotEmpty) {
      final p = DateTime.tryParse(referenceDate);
      if (p != null) return p;
    }
    return toOrganizationTime(DateTime.now().toUtc(), timezone);
  }

  /// Determines the authoritative attendance business date (`YYYY-MM-DD`) in organization timezone.
  /// (Crucial: 20:30 UTC on Aug 24 is 02:00 AM Aug 25 in Asia/Kolkata -> Returns '2026-08-25').
  static String getBusinessDate([DateTime? utcInstant, String? timezone]) {
    final instant = utcInstant ?? DateTime.now().toUtc();
    final local = toOrganizationTime(instant, timezone);
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  /// Authoritative today date string ('YYYY-MM-DD')
  static String todayDateString([String? timezone]) => getBusinessDate(null, timezone);

  /// Authoritative yesterday date string ('YYYY-MM-DD') in organization timezone
  static String yesterdayDateString([String? timezone]) {
    final nowLocal = toOrganizationTime(DateTime.now().toUtc(), timezone);
    final yesterdayLocal = nowLocal.subtract(const Duration(days: 1));
    return '${yesterdayLocal.year}-${yesterdayLocal.month.toString().padLeft(2, '0')}-${yesterdayLocal.day.toString().padLeft(2, '0')}';
  }

  /// Formats any backend timestamp or time string into a clean display time (e.g. "03:12:41 PM" or "03:12 PM").
  static String formatAttendanceTime(
    dynamic raw, {
    bool withSeconds = false,
    String? timezone,
    String? referenceDate,
    String fallback = '—',
  }) {
    if (raw == null) return fallback;
    final str = raw.toString().trim();
    if (str.isEmpty || str == 'null' || str == '—') return fallback;

    final dt = parseServerTimestamp(raw, timezone: timezone, referenceDate: referenceDate);
    if (dt == null) return raw.toString();

    final h24 = dt.hour;
    final m = dt.minute;
    final s = dt.second;
    final suffix = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;

    final hh = h12.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');

    if (withSeconds) {
      final ss = s.toString().padLeft(2, '0');
      return '$hh:$mm:$ss $suffix';
    }
    return '$hh:$mm $suffix';
  }

  /// Formats attendance business date into "25 Aug, 2026" or "Tuesday, 25 Aug 2026"
  static String formatAttendanceDate(dynamic raw, {bool full = false, String? timezone, String fallback = '—'}) {
    if (raw == null) return fallback;
    final str = raw.toString().trim();
    if (str.isEmpty || str == 'null' || str == '—') return fallback;

    DateTime? dt = DateTime.tryParse(str);
    dt ??= parseServerTimestamp(raw, timezone: timezone);
    if (dt == null) return str;

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];

    if (full) {
      return '$dayName, ${dt.day} $monthName ${dt.year}';
    }
    return '${dt.day} $monthName, ${dt.year}';
  }

  /// Calculates net worked duration between IN and OUT times, accounting for approved breaks
  static Duration calculateDuration({
    DateTime? checkIn,
    DateTime? checkOut,
    int breakMinutes = 0,
    String? timezone,
  }) {
    if (checkIn == null) return Duration.zero;
    final end = checkOut ?? toOrganizationTime(DateTime.now().toUtc(), timezone);
    final totalDiff = end.difference(checkIn);
    if (totalDiff.isNegative) return Duration.zero;

    final netMinutes = totalDiff.inMinutes - breakMinutes;
    return netMinutes > 0 ? Duration(minutes: netMinutes) : Duration.zero;
  }

  /// Formats Duration to HH:MM:SS
  static String formatDurationTimer(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Formats Duration to readable string e.g. "7h 45m"
  static String formatDurationReadable(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '${h}h ${m}m';
  }

  /// Prints unified timezone diagnostic log for development debugging
  static void logDiagnostic({
    required String context,
    required dynamic rawValue,
    String? timezone,
  }) {
    final orgTz = timezone ?? defaultTimezone;
    final parsed = parseServerTimestamp(rawValue, timezone: orgTz);
    final display = formatAttendanceTime(rawValue, timezone: orgTz, withSeconds: true);

    secureLog(
      '[ATTENDANCE_TIME_DIAGNOSTIC][$context] '
      'RAW: $rawValue | ORG_TZ: $orgTz | LOCAL: $parsed | DISPLAY: $display',
    );
  }
}
