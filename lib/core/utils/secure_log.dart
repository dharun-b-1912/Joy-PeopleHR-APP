import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

bool _loggerInitialized = false;
final Logger _rootLogger = Logger.detached('JoyPeopleHR');

void _ensureLoggerInitialized() {
  if (_loggerInitialized) return;
  _loggerInitialized = true;
  // Silence third-party SDK debug spam (Supabase raw JWT dumps, Postgrest GET URLs) on Logger.root
  Logger.root.level = Level.OFF;
  _rootLogger.level = Level.ALL;
  _rootLogger.onRecord.listen((LogRecord record) {
    final line = record.message;
    debugPrint(line);
    // ignore: avoid_print
    print(line);
    _forwardToTerminalBridge(line);
  });
}

void _forwardToTerminalBridge(String line) {
  if (!kIsWeb || !(kDebugMode || kProfileMode)) return;
  try {
    http
        .post(
          Uri.parse('http://127.0.0.1:8089/log'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'line': line}),
        )
        .ignore();
  } catch (_) {}
}

void _emitLine(String line, [Level level = Level.INFO]) {
  _ensureLoggerInitialized();
  _rootLogger.log(level, line);
}

String _formatTimestamp() {
  final now = DateTime.now();
  final h = now.hour.toString().padLeft(2, '0');
  final m = now.minute.toString().padLeft(2, '0');
  final s = now.second.toString().padLeft(2, '0');
  final ms = now.millisecond.toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

/// Sanitize any accidental Unicode symbols into clean ASCII so Windows PowerShell
/// (Windows-1252 / CP437) never renders garbled characters like "âš™ï¸" or "â†’".
String _toCleanAscii(String input) {
  return input
      .replaceAll('→', '->')
      .replaceAll('—', '--')
      .replaceAll('–', '-')
      .replaceAll('•', '*')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
}

String _inferModule(String message) {
  final upper = message.toUpperCase();
  if (upper.contains('CRASH') || upper.contains('FATAL') || upper.contains('UNCAUGHT')) {
    return 'CRASH';
  }
  if (upper.contains('REALTIME') || upper.contains('CHANNEL') || upper.contains('SUBSCRIB')) {
    return 'REALTIME';
  }
  if (upper.contains('GPS') || upper.contains('GEOFENCE') || upper.contains('LOCATION')) {
    return 'GPS';
  }
  if (upper.contains('AUTH') || upper.contains('LOGIN') || upper.contains('SESSION') || upper.contains('IDENTITY')) {
    return 'AUTH';
  }
  if (upper.contains('ATTENDANCE') || upper.contains('PUNCH') || upper.contains('CHECK-IN') || upper.contains('CHECKOUT')) {
    return 'ATTENDANCE';
  }
  if (upper.contains('DOC') || upper.contains('UPLOAD') || upper.contains('STORAGE')) {
    return 'DOCUMENT';
  }
  if (upper.contains('NOTIF') || upper.contains('PUSH')) {
    return 'NOTIFICATION';
  }
  return 'SYSTEM';
}

String _inferStatus(String message) {
  final upper = message.toUpperCase();
  if (upper.contains('CRASH') || upper.contains('FATAL') || upper.contains('UNCAUGHT')) {
    return 'CRASH';
  }
  if (upper.contains('ERROR') || upper.contains('FAILED') || upper.contains('EXCEPTION') || upper.contains('DENIED')) {
    return 'ERROR';
  }
  if (upper.contains('NOTICE') || upper.contains('WARN')) {
    return 'WARN';
  }
  return 'OK';
}

/// Print the startup table header on app boot.
void logBootHeader() {
  _emitLine('================================================================');
  _emitLine('  JOY PEOPLEHR FLUTTER -- LIVE MONITOR (http://localhost:8080)');
  _emitLine('================================================================');
  _emitLine('TIME         | MODULE       | STATUS | DETAILS');
  _emitLine('-------------+--------------+--------+--------------------------');
}

/// Structured terminal logger for Flutter debug/profile/release sessions.
/// Emits clean structured logs that appear in `adb logcat -s flutter` on Android.
void secureLog(String message) {
  final ts = _formatTimestamp();
  final cleanMsg = _toCleanAscii(message).replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
  final mod = _inferModule(message).padRight(12);
  final status = _inferStatus(message).padRight(6);
  _emitLine('$ts | $mod | $status | $cleanMsg');
}

/// Explicitly log a process step to the terminal and native logcat.
void logProcess(String module, String step, {Map<String, dynamic>? data}) {
  final ts = _formatTimestamp();
  final mod = _toCleanAscii(module).toUpperCase().padRight(12);
  final cleanStep = _toCleanAscii(step);
  String details = cleanStep;
  if (data != null && data.isNotEmpty) {
    final formattedPairs = data.entries
        .map((e) => '${e.key}=${_toCleanAscii(e.value?.toString() ?? "")}')
        .join(', ');
    details = '$cleanStep ($formattedPairs)';
  }
  _emitLine('$ts | $mod | OK     | $details');
}

/// Explicitly log a caught error with optional stack trace to the terminal.
void logError(String module, Object error, [StackTrace? stackTrace, String? context]) {
  final ts = _formatTimestamp();
  final mod = _toCleanAscii(module).toUpperCase();
  final ctx = (context != null && context.isNotEmpty) ? ' (${_toCleanAscii(context)})' : '';
  _emitLine('----------------------------------------------------------------', Level.SEVERE);
  _emitLine('$ts | ${mod.padRight(12)} | ERROR  | Exception$ctx: ${_toCleanAscii(error.toString())}', Level.SEVERE);
  if (stackTrace != null) {
    final lines = stackTrace
        .toString()
        .split('\n')
        .take(6)
        .map((l) => '             |              |        |   at ${_toCleanAscii(l.trim())}');
    for (final l in lines) {
      _emitLine(l, Level.SEVERE);
    }
  }
  _emitLine('----------------------------------------------------------------', Level.SEVERE);
}

/// Explicitly log an uncaught framework or zone crash to the terminal.
void logCrash(String source, Object error, StackTrace? stackTrace, {String? reason}) {
  if (kDebugMode || kProfileMode) {
    final ts = _formatTimestamp();
    _emitLine('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!', Level.SHOUT);
    _emitLine('$ts | CRASH        | FATAL  | UNCAUGHT EXCEPTION IN ${_toCleanAscii(source)}', Level.SHOUT);
    if (reason != null && reason.isNotEmpty) {
      _emitLine('             |              |        | Reason : ${_toCleanAscii(reason)}', Level.SHOUT);
    }
    _emitLine('             |              |        | Error  : ${_toCleanAscii(error.toString())}', Level.SHOUT);
    if (stackTrace != null) {
      final lines = stackTrace
          .toString()
          .split('\n')
          .take(8)
          .map((l) => '             |              |        |   at ${_toCleanAscii(l.trim())}');
      for (final l in lines) {
        _emitLine(l, Level.SHOUT);
      }
    }
    _emitLine('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!', Level.SHOUT);
  }
}

/// Explicitly log a structured Session, Attendance & Realtime Summary card in pure ASCII.
void logSessionBanner({
  required String event,
  required bool isLoggedIn,
  String? employeeName,
  String? employeeCode,
  String? employeeUuid,
  String? email,
  String? attendanceStatus,
  String? checkInTime,
  String? source,
}) {
  if (kDebugMode || kProfileMode) {
    final ts = _formatTimestamp();
    final cleanEvent = _toCleanAscii(event);
    _emitLine('================================================================');
    _emitLine('  [SESSION & REALTIME TRACKER] $cleanEvent ($ts)');
    _emitLine('----------------------------------------------------------------');
    if (isLoggedIn) {
      final rawAtt = _toCleanAscii(attendanceStatus ?? '');
      final normAtt = (rawAtt == 'CHECKEDIN' || rawAtt == 'CHECKED_IN')
          ? 'CHECKED IN'
          : (rawAtt == 'CHECKEDOUT' || rawAtt == 'CHECKED_OUT')
              ? 'CHECKED OUT'
              : (rawAtt.isEmpty || rawAtt == 'NOTCHECKEDIN' || rawAtt == 'NOT_CHECKED_IN')
                  ? 'NOT CHECKED IN'
                  : rawAtt;
      final attStr = checkInTime != null
          ? '$normAtt (In: ${_toCleanAscii(checkInTime)} via ${_toCleanAscii(source ?? "Mobile GPS")})'
          : normAtt;
      _emitLine('  * Login Status     : LOGGED IN (Active Session)');
      _emitLine('  * Employee         : ${_toCleanAscii(employeeName ?? "Unknown")} [${_toCleanAscii(employeeCode ?? "N/A")}]');
      _emitLine('  * Employee UUID    : ${_toCleanAscii(employeeUuid ?? "N/A")}');
      _emitLine('  * Work Email       : ${_toCleanAscii(email ?? "N/A")}');
      _emitLine('  * Today Attendance : $attStr');
      _emitLine('  * Realtime Sync    : ACTIVE (Profile, Attendance, Push, GPS)');
    } else {
      _emitLine('  * Login Status     : NOT LOGGED IN (Waiting on Login Screen)');
      _emitLine('  * Active Employee  : None (No employee logged in)');
      _emitLine('  * Today Attendance : NOT CHECKED IN');
      _emitLine('  * Realtime Sync    : STANDBY (Awaiting Login)');
    }
    _emitLine('================================================================');
  }
}
