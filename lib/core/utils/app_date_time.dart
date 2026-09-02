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
}
