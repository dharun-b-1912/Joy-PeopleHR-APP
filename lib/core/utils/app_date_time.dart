/// WorkForceOS — Authoritative DateTime & Timezone Utility (Asia/Kolkata / IST)
///
/// Ensures all attendance timestamps, daily check-in/out records, and timesheets
/// are parsed and displayed consistently in IST (UTC+05:30), while database
/// transactions continue using standard UTC/timestamptz.
class AppDateTime {
  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  /// Converts any [DateTime] to Asia/Kolkata (IST: UTC+5:30)
  static DateTime toIST(DateTime dt) {
    final utc = dt.toUtc();
    return utc.add(istOffset);
  }

  /// Parses a raw backend timestamp or time string into an IST [DateTime].
  ///
  /// Supports:
  ///   - ISO 8601 strings: '2026-08-25T12:00:00Z', '2026-08-25T17:30:00+05:30'
  ///   - Postgres timestamptz: '2026-08-25 12:00:00+00', '2026-08-25 17:30:00.123456+05:30'
  ///   - Plain TIME strings: '17:30:00', '09:30'
  static DateTime? parseToIST(dynamic raw, [String? dateStr]) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty || str == 'null') return null;

    // 1. Try direct DateTime.tryParse (handles both 'T' and space-separated timestamptz)
    final dt = DateTime.tryParse(str);
    if (dt != null) {
      return toIST(dt);
    }

    // 2. Parse plain TIME string e.g. "09:30:00" or "18:30"
    final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(str);
    if (timeMatch != null) {
      final h = int.parse(timeMatch.group(1)!);
      final m = int.parse(timeMatch.group(2)!);
      final s = timeMatch.group(3) != null ? int.parse(timeMatch.group(3)!) : 0;

      final nowIST = toIST(DateTime.now().toUtc());
      DateTime baseDate = nowIST;
      if (dateStr != null && dateStr.isNotEmpty) {
        final parsedDate = DateTime.tryParse(dateStr);
        if (parsedDate != null) {
          baseDate = parsedDate;
        }
      }

      return DateTime(baseDate.year, baseDate.month, baseDate.day, h, m, s);
    }

    return null;
  }

  /// Formats any raw timestamp or time value into a clean IST time string (e.g. "09:30 AM", "05:30 PM")
  static String formatTimeIST(dynamic raw, [String? fallback = '—']) {
    if (raw == null) return fallback ?? '—';
    final parsed = parseToIST(raw);
    if (parsed == null) return raw.toString();

    final h = parsed.hour;
    final m = parsed.minute;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $suffix';
  }

  /// Formats hour and minute into "hh:mm a"
  static String formatHHMM(int h, int m) {
    final suffix = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $suffix';
  }

  /// Calculates elapsed duration between two IST datetimes or from checkIn to now
  static Duration elapsed(DateTime? checkIn, [DateTime? checkOut]) {
    if (checkIn == null) return Duration.zero;
    final end = checkOut ?? toIST(DateTime.now().toUtc());
    final diff = end.difference(checkIn);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Formats a duration into "HH:MM:SS"
  static String formatDuration(Duration duration) {
    final h = duration.inHours.toString().padLeft(2, '0');
    final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static const List<String> _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static const List<String> _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /// Returns 3-letter month abbreviation (1 = Jan, 12 = Dec)
  static String shortMonth(int month) {
    if (month >= 1 && month <= 12) return _shortMonths[month - 1];
    return '';
  }

  /// Returns full month name (1 = January, 12 = December)
  static String fullMonth(int month) {
    if (month >= 1 && month <= 12) return _fullMonths[month - 1];
    return '';
  }

  /// Formats any raw date/timestamp into "DD Mon YYYY" (e.g. "01 Aug 2026")
  static String formatDate(dynamic raw, [String fallback = '—']) {
    if (raw == null) return fallback;
    final str = raw.toString().trim();
    if (str.isEmpty || str == 'null' || str == '—') return fallback;

    // Already in human format e.g. "01 Aug 2026" or "1 Aug 2026"
    final humanMatch = RegExp(r'^\d{1,2}\s+[A-Za-z]{3,}\s+\d{4}$').firstMatch(str);
    if (humanMatch != null) return str;

    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else {
      dt = DateTime.tryParse(str);
    }

    if (dt != null) {
      final ist = toIST(dt);
      final day = ist.day.toString().padLeft(2, '0');
      final month = shortMonth(ist.month);
      return '$day $month ${ist.year}';
    }

    // Try parsing YYYY-MM-DD
    final dateOnlyMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(str);
    if (dateOnlyMatch != null) {
      final y = int.parse(dateOnlyMatch.group(1)!);
      final m = int.parse(dateOnlyMatch.group(2)!);
      final d = int.parse(dateOnlyMatch.group(3)!);
      return '${d.toString().padLeft(2, '0')} ${shortMonth(m)} $y';
    }

    return str;
  }

  /// Specifically formats pay date ensuring no ISO string is shown to employees
  static String formatPayDate(dynamic raw, [String fallback = '—']) {
    return formatDate(raw, fallback);
  }

  /// Formats payroll period (e.g. "2026-07" -> "July 2026", "July 2026" -> "July 2026")
  static String formatPeriod(dynamic raw, [String fallback = 'Current Month']) {
    if (raw == null) return fallback;
    final str = raw.toString().trim();
    if (str.isEmpty || str == 'null') return fallback;

    // Check YYYY-MM format
    final ymMatch = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(str);
    if (ymMatch != null) {
      final year = ymMatch.group(1)!;
      final m = int.parse(ymMatch.group(2)!);
      return '${fullMonth(m)} $year';
    }

    // Check Month Year format (already e.g. "July 2026")
    final myMatch = RegExp(r'^[A-Za-z]+\s+\d{4}$').firstMatch(str);
    if (myMatch != null) return str;

    // If ISO date string is passed, extract Month Year
    final dt = DateTime.tryParse(str);
    if (dt != null) {
      return '${fullMonth(dt.month)} ${dt.year}';
    }

    return str;
  }
}
