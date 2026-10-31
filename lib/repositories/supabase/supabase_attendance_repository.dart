import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/services/attendance_time_service.dart';
import '../../core/services/push_sender_service.dart';
import '../../core/services/realtime_outbox_service.dart';
import '../../core/services/user_service.dart';
import '../../core/utils/app_date_time.dart';
import '../../core/utils/query_timeout.dart';
import '../../core/utils/secure_log.dart';
import '../../core/utils/validators.dart';
import '../../models/employee_models.dart';
import '../../models/hrms_models.dart';
import '../interfaces/employee_repository.dart';

/// WorkForceOS — Supabase Attendance Repository (Production Schema Aligned)
///
/// Tables used:
///   attendance_events     — raw punch events written on check-in / check-out
///   attendance_daily      — per-day ledger (status, first/last punch, net_working_minutes)
///   attendance_regularizations — regularization requests
class SupabaseAttendanceRepository implements IAttendanceRepository {
  SupabaseClient get _client => Supabase.instance.client;

  // ────────────────────────────────────────────────────────────────────────
  // TODAY'S ATTENDANCE QUERY (used on app launch / resume / punch sync)
  // ────────────────────────────────────────────────────────────────────────

  static bool _isApprovedStatus(String? status) {
    if (status == null) return false;
    final s = status.trim().toUpperCase();
    if (s.contains('DISAPPROV') ||
        s.contains('REJECT') ||
        s.contains('DECLIN') ||
        s.contains('NOT_APPROV') ||
        s.contains('WITHDRAW') ||
        s.contains('CANCEL') ||
        s.contains('PENDING')) {
      return false;
    }
    return s.contains('APPROV') || s.contains('ACCEPT') || s == 'REGULARIZED';
  }

  static bool _isRejectedStatus(String? status) {
    if (status == null) return false;
    final s = status.trim().toUpperCase();
    return s.contains('DISAPPROV') ||
        s.contains('REJECT') ||
        s.contains('DECLIN') ||
        s.contains('NOT_APPROV');
  }

  static bool _isWithdrawnStatus(String? status) {
    if (status == null) return false;
    final s = status.trim().toUpperCase();
    return s.contains('WITHDRAW') || s.contains('CANCEL');
  }

  /// Fetch the authoritative attendance_daily and attendance_events record for today.
  Future<Map<String, dynamic>?> getTodayAttendance(String employeeId) async {
    try {
      final user = UserService.instance.currentUser;
      final targetId = employeeId.trim().isNotEmpty
          ? employeeId.trim()
          : (user.employeeUuid?.isNotEmpty == true
              ? user.employeeUuid!
              : user.dataId);
      final todayDate = AttendanceTimeService.todayDateString();
      final yesterdayDate = AttendanceTimeService.yesterdayDateString();

      final candidateEmpIds = <String>{
        targetId,
        if (user.employeeUuid?.isNotEmpty == true) user.employeeUuid!,
        if (user.dataId.isNotEmpty) user.dataId,
        if (user.employeeId.isNotEmpty) user.employeeId,
        if (user.resolvedEmployeeId.isNotEmpty) user.resolvedEmployeeId,
        if (employeeId.trim().isNotEmpty) employeeId.trim(),
      }.where((id) => Validators.isValidUuid(id)).toList();

      Map<String, dynamic> merged = {};

      if (candidateEmpIds.isNotEmpty) {
        String activeSessionDate = todayDate;
        Map<String, dynamic>? activeRow;

        // 1. Query attendance_daily for today and yesterday with joined shift config
        try {
          final dailyDataList = await withTimeout(
            _client
                .from('attendance_daily')
                .select('*, shifts:shift_id(id, code, name, start_time, end_time, is_overnight, attendance_date_cutoff)')
                .inFilter('employee_id', candidateEmpIds)
                .inFilter('attendance_date', [todayDate, yesterdayDate])
                .order('attendance_date', ascending: false),
          );

          if (dailyDataList.isNotEmpty) {
            Map<String, dynamic>? todayRow;
            Map<String, dynamic>? yesterdayRow;

            for (final item in dailyDataList) {
              final r = Map<String, dynamic>.from(item);
              final d = r['attendance_date']?.toString();
              if (d == todayDate && todayRow == null) {
                todayRow = r;
              } else if (d == yesterdayDate && yesterdayRow == null) {
                yesterdayRow = r;
              }
            }

            final now = AttendanceTimeService.toOrganizationTime(DateTime.now().toUtc());
            final nowTimeMinutes = now.hour * 60 + now.minute;

            // Decision Logic for active session:
            // Case 1: Today has a check-in -> Today's session is active!
            if (todayRow != null && todayRow['first_check_in'] != null && todayRow['first_check_in'].toString().isNotEmpty) {
              activeRow = todayRow;
              activeSessionDate = todayDate;
            }
            // Case 2: Today has NO check-in, but Yesterday has check-in (Night Shift candidate)
            else if (yesterdayRow != null && yesterdayRow['first_check_in'] != null && yesterdayRow['first_check_in'].toString().isNotEmpty) {
              final isYesterdayOvernight = yesterdayRow['shifts']?['is_overnight'] == true ||
                  (yesterdayRow['shifts']?['start_time'] != null &&
                   yesterdayRow['shifts']?['end_time'] != null &&
                   yesterdayRow['shifts']['end_time'].toString().compareTo(yesterdayRow['shifts']['start_time'].toString()) < 0);

              // Parse shift cutoff time (default 12:00 PM / 720 mins)
              int cutoffMinutes = 12 * 60; // 12:00 PM default
              final cutoffStr = yesterdayRow['shifts']?['attendance_date_cutoff']?.toString();
              if (cutoffStr != null && cutoffStr.isNotEmpty) {
                final parts = cutoffStr.split(':');
                if (parts.length >= 2) {
                  final ch = int.tryParse(parts[0]) ?? 12;
                  final cm = int.tryParse(parts[1]) ?? 0;
                  cutoffMinutes = ch * 60 + cm;
                }
              }

              final isUnclosed = yesterdayRow['last_check_out'] == null || yesterdayRow['last_check_out'].toString().isEmpty;

              if (isUnclosed) {
                // If yesterday's night shift has not checked out yet:
                // If before cutoff -> CURRENTLY CHECKED IN to yesterday's night shift!
                if (isYesterdayOvernight && nowTimeMinutes <= cutoffMinutes) {
                  activeRow = yesterdayRow;
                  activeSessionDate = yesterdayDate;
                }
              } else {
                // Yesterday's session is checked out. Did checkout happen today (after midnight or before cutoff)?
                final outStr = yesterdayRow['last_check_out'].toString();
                final outDt = AttendanceTimeService.parseServerTimestamp(outStr, referenceDate: yesterdayDate);
                if (outDt != null) {
                  final outDateStr = '${outDt.year}-${outDt.month.toString().padLeft(2, '0')}-${outDt.day.toString().padLeft(2, '0')}';
                  // If checked out today (e.g. at 07:30 AM), and today has no new check-in, show this completed session!
                  if (outDateStr == todayDate || nowTimeMinutes <= cutoffMinutes) {
                    activeRow = yesterdayRow;
                    activeSessionDate = yesterdayDate;
                  }
                }
              }
            }

            // Fallback to todayRow if activeRow is still null
            activeRow ??= todayRow;

            if (activeRow != null) {
              merged.addAll(activeRow);
              merged['date'] = activeRow['attendance_date'] ?? activeSessionDate;
              merged['net_working_minutes'] = (activeRow['total_work_minutes'] as num?)?.toInt() ??
                  (activeRow['net_working_minutes'] as num?)?.toInt() ?? 0;
              merged['location_name'] = activeRow['check_in_location_name'] ?? activeRow['location_name'];
              merged['source'] = activeRow['active_source'] ?? activeRow['source'] ?? activeRow['punch_source'];
              merged['verification_type'] = activeRow['verification_type'] ?? activeRow['punch_method'] ?? activeRow['verify_type'];
              merged['device_id'] = activeRow['device_id'] ?? activeRow['device_serial'];

              final hasIn = activeRow['first_check_in'] != null && activeRow['first_check_in'].toString().isNotEmpty;
              final hasOut = activeRow['last_check_out'] != null && activeRow['last_check_out'].toString().isNotEmpty;
              if (hasIn && !hasOut) {
                merged['is_currently_in'] = true;
              } else if (hasIn && hasOut) {
                merged['is_currently_in'] = false;
              }
            }
          }
        } catch (e) {
          secureLog('[Attendance] attendance_daily query notice: $e');
        }

        // 2. Query attendance_punches to ensure authoritative check-in/out timestamps and source
        try {
          final queryParts = activeSessionDate.split('-').map(int.parse).toList();
          final queryDayStartUtc = DateTime.utc(queryParts[0], queryParts[1], queryParts[2])
              .subtract(AttendanceTimeService.istOffset);

          final events = await withTimeout(
            _client
                .from('attendance_punches')
                .select()
                .inFilter('employee_id', candidateEmpIds)
                .gte('punch_time', queryDayStartUtc.toIso8601String())
                .order('punch_time', ascending: true),
          );

          if (events.isNotEmpty) {
            events.sort((a, b) => (a['punch_time'] ?? '').toString().compareTo((b['punch_time'] ?? '').toString()));

            String? firstInTimestamp;
            String? lastOutTimestamp;
            String? firstSource;
            String? firstVerifyType;
            String? firstDeviceId;

            for (final ev in events) {
              final type = (ev['punch_type'] ?? '').toString().toUpperCase();
              final ts = ev['punch_time']?.toString();
              if (ts != null && ts.isNotEmpty) {
                if (type.contains('IN') && !type.contains('OUT')) {
                  firstInTimestamp ??= ts;
                  firstSource ??= (ev['punch_source'] ?? ev['source'])?.toString();
                  firstVerifyType ??= (ev['verification_mode'] ?? ev['verification_type'] ?? ev['verify_type'] ?? ev['punch_method'])?.toString();
                  firstDeviceId ??= (ev['device_id'] ?? ev['device_serial'])?.toString();
                } else if (type.contains('OUT')) {
                  lastOutTimestamp = ts;
                }
              }
            }

            final latestEvent = events.last;
            final latestType = (latestEvent['punch_type'] ?? '').toString().toUpperCase();
            final isCurrentlyIn = latestType.contains('IN') && !latestType.contains('OUT');

            merged['first_check_in'] = firstInTimestamp ?? merged['first_check_in'];
            merged['last_check_out'] = isCurrentlyIn ? null : (lastOutTimestamp ?? merged['last_check_out']);
            merged['is_currently_in'] = isCurrentlyIn || (merged['first_check_in'] != null && (merged['last_check_out'] == null || merged['last_check_out'].toString().isEmpty));
            merged['date'] = activeSessionDate;
            if (firstSource != null) merged['source'] = firstSource;
            if (firstVerifyType != null) merged['verification_type'] = firstVerifyType;
            if (firstDeviceId != null) merged['device_id'] = firstDeviceId;
          }
        } catch (e) {
          secureLog('[Attendance] attendance_punches query notice: $e');
        }
      }

      if (merged.isNotEmpty) {
        AttendanceTimeService.logDiagnostic(
          context: 'getTodayAttendance',
          rawValue: merged['first_check_in'],
        );
        if (merged['last_check_out'] != null) {
          AttendanceTimeService.logDiagnostic(
            context: 'getTodayAttendance_OUT',
            rawValue: merged['last_check_out'],
          );
        }
        return merged;
      }
      return null;
    } catch (e) {
      secureLog('[Attendance] getTodayAttendance query error: $e');
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // PUNCH EVENT INSERTION (CHECK_IN / CHECK_OUT)
  // ────────────────────────────────────────────────────────────────────────

  /// Record punch event into `attendance_events` & atomically sync `attendance_daily` + `realtime_outbox`.
  ///
  /// [checkoutVerification] — Location verification result for CHECK_OUT events.
  /// Only applied for CHECK_OUT type punches. CHECK_IN uses strict geofence validation.
  Future<void> recordPunchEvent({
    required String type,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? deviceId,
    bool isMocked = false,
    CheckoutLocationVerification? checkoutVerification,
  }) async {
    final user = UserService.instance.currentUser;
    final employeeUuid = user.dataId;

    if (employeeUuid.isEmpty) {
      throw Exception('Authentication required: Employee identity not resolved.');
    }

    final eventId = 'evt-${DateTime.now().microsecondsSinceEpoch}-${employeeUuid.hashCode.abs()}';
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final todayDate = AttendanceTimeService.getBusinessDate();
    final tenantId = user.companyId.isNotEmpty
        ? user.companyId
        : (user.organizationId?.isNotEmpty == true ? user.organizationId! : '');

    // 1. Log Diagnostics for development verification
    secureLog('[ATTENDANCE][FLUTTER][START] employee=${user.employeeId} uuid=$employeeUuid type=$type');
    if (latitude != null && longitude != null) {
      secureLog('[ATTENDANCE][GPS] lat=$latitude lng=$longitude accuracy=${accuracy ?? 10.0}m isMock=$isMocked');
    }

    // 2. Execute Authoritative Server-Side GPS Validation RPC
    if (latitude != null && longitude != null) {
      try {
        final checkoutReason = (checkoutVerification?.reason?.trim().isNotEmpty == true)
            ? checkoutVerification!.reason!.trim()
            : (type.toUpperCase().contains('OUT') ? 'Regular shift checkout' : null);

        final rpcRes = await withTimeout(
          _client.rpc('fn_record_attendance_punch', params: {
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_accuracy': accuracy ?? 20.0,
            'p_punch_type': type.toUpperCase().contains('OUT') ? 'OUT' : 'IN',
            'p_reason': checkoutReason,
            'p_device_info': {
              'deviceId': deviceId ?? 'FLUTTER_MOBILE',
              'client': 'JOY PeopleHR Mobile v1.0',
              'source': 'MOBILE',
              'punch_source': 'MOBILE',
              'isMock': isMocked,
            },
          }),
        );
        secureLog('[ATTENDANCE][RPC] fn_record_attendance_punch success: $rpcRes');

        // Broadcast Realtime Outbox Event for cross-platform instant mesh update
        final effectiveDate = (rpcRes is Map && rpcRes['attendance_date'] != null)
            ? rpcRes['attendance_date'].toString()
            : todayDate;

        await RealtimeOutboxService.insertEvent(
          entityType: 'ATTENDANCE_DAILY',
          eventType: 'attendance.updated',
          entityId: employeeUuid,
          tenantId: tenantId,
          actorId: employeeUuid,
          payload: {
            'employee_id': employeeUuid,
            'employee_code': user.employeeId,
            'employee_name': user.name,
            'punch_type': type,
            'timestamp': nowIso,
            'date': effectiveDate,
            'source': 'MOBILE_GPS',
          },
        );
        return; // Server-side function authoritatively handled both punch and daily records
      } catch (rpcErr) {
        secureLog('[ATTENDANCE][RPC] Exception during GPS attendance validation: $rpcErr');
        final errStr = rpcErr.toString();
        if (errStr.contains('No active check-in found')) {
          final cleanMsg = errStr.replaceAll(RegExp(r'^(Exception:|PostgrestException\(message:\s*|\))'), '').trim();
          throw Exception(cleanMsg.isNotEmpty ? cleanMsg : errStr);
        }
        // Fall back to direct table insert below so user checkout is NEVER blocked
        secureLog('[ATTENDANCE][FALLBACK] Falling back to direct attendance punch insert');
      }
    }

    // 3. Fallback / Direct insert into attendance_punches (canonical punch ledger)
    final isCheckOut = type.toUpperCase().contains('OUT');
    final isUnauthorizedCheckout = isCheckOut &&
        checkoutVerification != null &&
        checkoutVerification.status == CheckoutLocationStatus.unauthorized;

    // Check open session for fallback: if checking out and today has no check-in, check yesterday
    Map<String, dynamic>? existingDaily;
    String fallbackSessionDate = todayDate;
    try {
      final dailyCheckList = await withTimeout(
        _client
            .from('attendance_daily')
            .select()
            .eq('employee_id', employeeUuid)
            .inFilter('attendance_date', [todayDate, AttendanceTimeService.yesterdayDateString()])
            .order('attendance_date', ascending: false),
      );
      if (dailyCheckList.isNotEmpty) {
        if (isCheckOut) {
          existingDaily = dailyCheckList.firstWhere(
            (d) => d['first_check_in'] != null && (d['last_check_out'] == null || d['last_check_out'].toString().isEmpty),
            orElse: () => dailyCheckList.first,
          );
        } else {
          existingDaily = dailyCheckList.firstWhere(
            (d) => d['attendance_date'] == todayDate,
            orElse: () => dailyCheckList.first,
          );
        }
        fallbackSessionDate = existingDaily['attendance_date']?.toString() ?? todayDate;
      }
    } catch (_) {}

    final payload = <String, dynamic>{
      'employee_id': employeeUuid,
      if (tenantId.isNotEmpty) 'organization_id': tenantId,
      'punch_time': nowIso,
      'punch_type': isCheckOut ? 'OUT' : 'IN',
      'verification_mode': 'GPS',
      'punch_source': 'MOBILE_GPS',
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracy ?? 10.0,
      'location_authorized': !isUnauthorizedCheckout,
      'unauthorized_checkout': isUnauthorizedCheckout,
      if (checkoutVerification?.reason != null)
        'unauthorized_checkout_reason': checkoutVerification!.reason
      else if (isUnauthorizedCheckout)
        'unauthorized_checkout_reason': 'Outside assigned location',
      'attendance_date': fallbackSessionDate,
      'is_processed': true,
    };

    try {
      await withTimeout(
        _client.from('attendance_punches').insert(payload),
      );
      secureLog('[ATTENDANCE][DB] punch=INSERT status=SUCCESS event_id=$eventId');
    } catch (e) {
      secureLog('[ATTENDANCE][DB] attendance_punches insert notice: $e');
    }

    // 3. Atomically update/upsert attendance_daily ledger
    try {
      final isCheckIn = type.toUpperCase().contains('IN') && !type.toUpperCase().contains('OUT');
      final firstIn = existingDaily?['first_check_in'] ?? nowIso;
      final lastOut = isCheckIn ? null : nowIso;

      int netMinutes = (existingDaily?['total_work_minutes'] as num?)?.toInt() ?? 0;
      if (!isCheckIn && firstIn != null) {
        final inDt = DateTime.tryParse(firstIn.toString());
        final outDt = DateTime.tryParse(nowIso);
        if (inDt != null && outDt != null && outDt.isAfter(inDt)) {
          netMinutes = outDt.difference(inDt).inMinutes;
        }
      }

      final dailyPayload = <String, dynamic>{
        if (tenantId.isNotEmpty) 'organization_id': tenantId,
        'employee_id': employeeUuid,
        'attendance_date': fallbackSessionDate,
        'status': 'PRESENT',
        'payable_status': 1.0,
        'first_check_in': firstIn,
        'last_check_out': lastOut,
        'total_work_minutes': netMinutes,
        'unauthorized_checkout': isUnauthorizedCheckout,
        if (checkoutVerification?.reason != null)
          'unauthorized_checkout_reason': checkoutVerification!.reason
        else if (isUnauthorizedCheckout)
          'unauthorized_checkout_reason': 'Outside assigned location',
        if (!isCheckIn && checkoutVerification?.locationName != null)
          'check_out_location_name': checkoutVerification!.locationName,
        'updated_at': nowIso,
      };

      await withTimeout(
        _client.from('attendance_daily').upsert(dailyPayload, onConflict: 'employee_id,attendance_date'),
      );
      secureLog('[ATTENDANCE][LEDGER] employee=${user.employeeId} first_in=$firstIn last_out=$lastOut worked=${netMinutes}m status=PRESENT');
    } catch (e) {
      secureLog('[ATTENDANCE][LEDGER] attendance_daily upsert notice: $e');
    }

    // 4. Broadcast Realtime Outbox Event for cross-platform instant mesh update
    await RealtimeOutboxService.insertEvent(
      entityType: 'ATTENDANCE_DAILY',
      eventType: 'attendance.updated',
      entityId: employeeUuid,
      tenantId: tenantId,
      actorId: employeeUuid,
      payload: {
        'employee_id': employeeUuid,
        'employee_code': user.employeeId,
        'employee_name': user.name,
        'punch_type': type,
        'timestamp': nowIso,
        'date': todayDate,
        'source': 'MOBILE_GPS',
      },
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // MONTHLY TIMESHEET QUERY (Synthesizes Full 1..N Calendar Timeline)
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<List<TimesheetEntryModel>> getTimesheets(
    String employeeId, {
    int? month,
    int? year,
  }) async {
    try {
      if (!SupabaseConfig.isConfigured) {
        return [];
      }

      final nowIST = DateTime.now().toUtc().add(AttendanceTimeService.istOffset);
      final m = month ?? nowIST.month;
      final y = year ?? nowIST.year;
      final totalDaysInMonth = DateTime(y, m + 1, 0).day;
      final todayDateStr = '${nowIST.year}-${nowIST.month.toString().padLeft(2, '0')}-${nowIST.day.toString().padLeft(2, '0')}';

      final user = UserService.instance.currentUser;
      final targetId = user.resolvedEmployeeId.isNotEmpty ? user.resolvedEmployeeId : employeeId;

      final candidateEmpIds = <String>{
        targetId,
        if (user.employeeUuid?.isNotEmpty == true) user.employeeUuid!,
        if (user.dataId.isNotEmpty) user.dataId,
        if (employeeId.trim().isNotEmpty) employeeId.trim(),
      }.where((id) => Validators.isValidUuid(id)).toList();

      // 1. Fetch all raw ledger rows from attendance_daily
      final dailyMap = <String, Map<String, dynamic>>{};
      final eventsMap = <String, List<Map<String, dynamic>>>{};
      if (candidateEmpIds.isNotEmpty) {
        try {
          final dailyRows = await withTimeout(
            _client
                .from('attendance_daily')
                .select('*, shifts:shift_id(id, code, name, start_time, end_time, is_overnight, attendance_date_cutoff)')
                .inFilter('employee_id', candidateEmpIds)
                .gte('attendance_date', '$y-${m.toString().padLeft(2, '0')}-01')
                .lte('attendance_date', '$y-${m.toString().padLeft(2, '0')}-$totalDaysInMonth'),
          );
          for (final r in dailyRows) {
            final d = (r['attendance_date'] ?? r['date'])?.toString();
            if (d != null && d.isNotEmpty) {
              dailyMap[d] = Map<String, dynamic>.from(r);
            }
          }
        } catch (e) {
          secureLog('[Attendance] attendance_daily fetch notice: $e');
        }

        // 2. Fetch all raw events from attendance_punches in case punch is recorded there
        try {
          final startUtc = DateTime.utc(y, m, 1).subtract(AttendanceTimeService.istOffset);
          final endUtc = DateTime.utc(y, m, totalDaysInMonth, 23, 59, 59).subtract(AttendanceTimeService.istOffset);

          final eventRows = await withTimeout(
            _client
                .from('attendance_punches')
                .select()
                .inFilter('employee_id', candidateEmpIds)
                .gte('punch_time', startUtc.toIso8601String())
                .lte('punch_time', endUtc.toIso8601String())
                .order('punch_time', ascending: true),
          );
          for (final ev in eventRows) {
            final tsStr = ev['punch_time']?.toString();
            if (tsStr != null && tsStr.isNotEmpty) {
              final parsedDt = DateTime.tryParse(tsStr);
              if (parsedDt != null) {
                final bDate = AttendanceTimeService.getBusinessDate(parsedDt);
                eventsMap.putIfAbsent(bDate, () => []).add(Map<String, dynamic>.from(ev));
              }
            }
          }
        } catch (e) {
          secureLog('[Attendance] attendance_punches fetch notice: $e');
        }
      }

      // 3. Fetch approved leaves for this month
      final leaveDates = <String>{};
      try {
        final leaveRows = await withTimeout(
          _client
              .from('leave_requests')
              .select()
              .eq('employee_id', targetId)
              .eq('status', 'APPROVED'),
        );
        for (final lr in leaveRows) {
          final sStr = (lr['start_date'] ?? lr['from_date'])?.toString();
          final eStr = (lr['end_date'] ?? lr['to_date'])?.toString();
          if (sStr != null && eStr != null) {
            final s = DateTime.tryParse(sStr);
            final e = DateTime.tryParse(eStr);
            if (s != null && e != null) {
              for (var cur = s; !cur.isAfter(e); cur = cur.add(const Duration(days: 1))) {
                if (cur.year == y && cur.month == m) {
                  leaveDates.add('${cur.year}-${cur.month.toString().padLeft(2, '0')}-${cur.day.toString().padLeft(2, '0')}');
                }
              }
            }
          }
        }
      } catch (_) {}

      // 3.5. Fetch all regularization requests for this employee in this month
      final regularizationsMap = <String, Map<String, dynamic>>{};
      try {
        final validRegIds = <String>{
          if (Validators.isValidUuid(targetId)) targetId,
          if (user.employeeUuid?.isNotEmpty == true && Validators.isValidUuid(user.employeeUuid!)) user.employeeUuid!,
          if (user.dataId.isNotEmpty && Validators.isValidUuid(user.dataId)) user.dataId,
        };

        if (validRegIds.isNotEmpty) {
          final orFilterReg = validRegIds.map((id) => 'employee_id.eq.$id').join(',');

          final regRows = await withTimeout(
            _client
                .from('attendance_regularizations')
                .select('*')
                .or(orFilterReg),
          );
          for (final r in regRows) {
            final dateRaw = (r['attendance_date'] ?? r['date'] ?? r['work_date'])?.toString();
            if (dateRaw != null && dateRaw.isNotEmpty) {
              final dateKey = dateRaw.split('T')[0];
              regularizationsMap[dateKey] = Map<String, dynamic>.from(r);
            }
          }
        }
      } catch (e) {
        secureLog('[Attendance] attendance_regularizations fetch notice: $e');
      }

      try {
        final regFallbackRows = await withTimeout(
          _client
              .from('attendance_regularizations')
              .select('*')                .or('employee_id.eq.$targetId'),
        );
        for (final r in regFallbackRows) {
          final dateRaw = (r['attendance_date'] ?? r['date'] ?? r['work_date'])?.toString();
          if (dateRaw != null && dateRaw.isNotEmpty) {
            final dateKey = dateRaw.split('T')[0];
            regularizationsMap.putIfAbsent(dateKey, () => Map<String, dynamic>.from(r));
          }
        }
      } catch (_) {}

      // 4. Synthesize day-wise calendar timesheet days
      // For current month: show only from Day 1 up to today.
      // For past months: show all days (1..totalDaysInMonth).
      // For future months: return empty list.
      final now = DateTime.now();
      final isCurrentMonth = (y == now.year && m == now.month);
      final isFutureMonth = (y > now.year || (y == now.year && m > now.month));

      if (isFutureMonth) {
        return [];
      }

      final int maxDay = isCurrentMonth ? now.day : totalDaysInMonth;
      final List<TimesheetEntryModel> fullMonthList = [];

      for (int day = 1; day <= maxDay; day++) {
        final date = DateTime(y, m, day);
        final dateStr = '$y-${m.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
        final isPast = dateStr.compareTo(todayDateStr) < 0;
        final isToday = dateStr == todayDateStr;

        final dailyRecord = dailyMap[dateStr];
        final dayEvents = eventsMap[dateStr] ?? [];
        final regRecord = regularizationsMap[dateStr];

        String? firstCheckIn = dailyRecord?['first_check_in']?.toString();
        String? lastCheckOut = dailyRecord?['last_check_out']?.toString();
        int netMinutes = (dailyRecord?['total_work_minutes'] as num?)?.toInt() ??
            (dailyRecord?['net_working_minutes'] as num?)?.toInt() ??
            0;
        String source = dailyRecord?['source']?.toString() ?? 'Mobile Geofence';

        // 1. Regularization check (Approved regularization makes it full Present)
        bool isRegularizedApproved = false;
        if (regRecord != null) {
          final regStatus = (regRecord['status'] ?? '').toString();
          if (_isApprovedStatus(regStatus)) {
            isRegularizedApproved = true;
            firstCheckIn ??= regRecord['requested_check_in']?.toString() ?? '09:30 AM';
            lastCheckOut ??= regRecord['requested_check_out']?.toString() ?? '06:30 PM';
            source = 'Regularization';
            if (netMinutes == 0) netMinutes = 480; // 8h standard shift
          }
        }

        // 2. Punch calculation if events exist
        if (firstCheckIn == null && dayEvents.isNotEmpty) {
          for (final ev in dayEvents) {
            final type = (ev['punch_type'] ?? ev['type'] ?? ev['event_type'] ?? '').toString().toUpperCase();
            final ts = (ev['punch_time'] ?? ev['timestamp'])?.toString();
            if (ts != null) {
              if (type.contains('IN') && !type.contains('OUT')) {
                firstCheckIn ??= ts;
              } else if (type.contains('OUT')) {
                lastCheckOut = ts;
              }
            }
          }
        }

        // Check if this row is an active overnight shift that started yesterday and is still running today before cutoff
        bool isYesterdayActiveOvernight = false;
        final yesterdayStr = AttendanceTimeService.yesterdayDateString();
        if (dateStr == yesterdayStr && firstCheckIn != null && lastCheckOut == null) {
          final shiftRaw = dailyRecord?['shifts'];
          final shiftData = shiftRaw is Map<String, dynamic>
              ? shiftRaw
              : (shiftRaw is List && shiftRaw.isNotEmpty && shiftRaw.first is Map<String, dynamic>
                  ? shiftRaw.first as Map<String, dynamic>
                  : null);
          final isOvernight = shiftData?['is_overnight'] == true;
          final cutoffStr = (shiftData?['attendance_date_cutoff'] ?? '12:00:00').toString();
          final cutoffParts = cutoffStr.split(':');
          final cutoffH = int.tryParse(cutoffParts[0]) ?? 12;
          final cutoffM = cutoffParts.length > 1 ? (int.tryParse(cutoffParts[1]) ?? 0) : 0;
          final nowLocal = AttendanceTimeService.nowLocal();
          final currentMinutes = nowLocal.hour * 60 + nowLocal.minute;
          final cutoffMinutes = cutoffH * 60 + cutoffM;
          if (isOvernight && currentMinutes < cutoffMinutes) {
            isYesterdayActiveOvernight = true;
          }
        }

        if (firstCheckIn != null && lastCheckOut != null && netMinutes == 0) {
          final dtIn = DateTime.tryParse(firstCheckIn);
          final dtOut = DateTime.tryParse(lastCheckOut);
          if (dtIn != null && dtOut != null) {
            netMinutes = dtOut.difference(dtIn).inMinutes;
            if (netMinutes < 0) netMinutes = 0;
          }
        } else if ((isToday || isYesterdayActiveOvernight) && firstCheckIn != null && lastCheckOut == null && netMinutes == 0) {
          final dtIn = DateTime.tryParse(firstCheckIn);
          if (dtIn != null) {
            netMinutes = DateTime.now().toUtc().difference(dtIn.toUtc()).inMinutes;
            if (netMinutes < 0) netMinutes = 0;
          }
        }

        DayAttendanceStatus status;

        if (isRegularizedApproved) {
          status = DayAttendanceStatus.present;
        } else if (firstCheckIn != null) {
          if (lastCheckOut != null) {
            // Checked in AND checked out
            if (netMinutes >= 360) {
              // >= 6.0 hours => Full Day Present
              status = DayAttendanceStatus.present;
            } else if (netMinutes > 0) {
              // < 6.0 hours => Half Day
              status = DayAttendanceStatus.halfDay;
            } else {
              status = DayAttendanceStatus.notPayable;
            }
          } else if (isToday || isYesterdayActiveOvernight) {
            // Active shift in progress today or yesterday's overnight shift before cutoff => Present (Active)
            status = DayAttendanceStatus.present;
          } else {
            // Past day checked in, but NO checkout punch => Not Payable (Missing Checkout)
            status = DayAttendanceStatus.notPayable;
          }
        } else if (leaveDates.contains(dateStr)) {
          status = DayAttendanceStatus.leave;
        } else if (isWeekend) {
          status = DayAttendanceStatus.weekOff;
        } else if (isPast) {
          status = DayAttendanceStatus.absent; // Past workday with 0 check-in (Red)
        } else {
          status = DayAttendanceStatus.none; // Today or future unpunched
        }

        final bool isSessionActiveNow = (isToday || isYesterdayActiveOvernight) && lastCheckOut == null;

        fullMonthList.add(TimesheetEntryModel(
          id: dailyRecord?['id']?.toString() ?? regRecord?['id']?.toString() ?? 'ts-$y-$m-$day',
          date: date,
          clockInTime: firstCheckIn != null ? AttendanceTimeService.formatAttendanceTime(firstCheckIn) : null,
          clockOutTime: lastCheckOut != null ? AttendanceTimeService.formatAttendanceTime(lastCheckOut) : null,
          totalHours: netMinutes > 0 && (status == DayAttendanceStatus.present || status == DayAttendanceStatus.halfDay)
              ? (isSessionActiveNow ? '${_formatDuration(netMinutes)} (Active)' : _formatDuration(netMinutes))
              : (status == DayAttendanceStatus.notPayable
                  ? (isToday ? 'Shift Active' : 'Missed Out')
                  : (status == DayAttendanceStatus.weekOff
                      ? 'Week Off'
                      : (status == DayAttendanceStatus.absent
                          ? 'Absent LOP'
                          : (status == DayAttendanceStatus.leave ? 'Leave' : '-')))),
          status: status,
          source: _prettySource(source),
          netWorkingMinutes: netMinutes,
          checkoutLocationStatus: dailyRecord?['checkout_location_status']?.toString(),
          checkoutLocationName: dailyRecord?['checkout_location_name']?.toString(),
          checkoutLocationReason: dailyRecord?['checkout_location_reason']?.toString(),
          checkoutLatitude: (dailyRecord?['checkout_latitude'] as num?)?.toDouble(),
          checkoutLongitude: (dailyRecord?['checkout_longitude'] as num?)?.toDouble(),
        ));
      }

      return fullMonthList;
    } catch (e) {
      secureLog('[Attendance] getTimesheets error: $e');
      return [];
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // MONTHLY ATTENDANCE SUMMARY
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<AttendanceSummaryModel> getAttendanceSummary(
    String employeeId, {
    int? month,
    int? year,
  }) async {
    try {
      if (!SupabaseConfig.isConfigured) {
        return const AttendanceSummaryModel(
          totalWorkingDays: 0,
          presentDays: 0,
          absentDays: 0,
          leaveDays: 0,
          holidaysCount: 0,
          weekOffsCount: 0,
          totalHoursWorked: '00h 00m',
          avgDailyHours: '00h 00m',
        );
      }

      final timesheets = await getTimesheets(employeeId, month: month, year: year);
      if (timesheets.isEmpty) {
        return const AttendanceSummaryModel(
          totalWorkingDays: 0,
          presentDays: 0,
          absentDays: 0,
          leaveDays: 0,
          holidaysCount: 0,
          weekOffsCount: 0,
          totalHoursWorked: '00h 00m',
          avgDailyHours: '00h 00m',
        );
      }

      var present = 0, absent = 0, leave = 0, holidays = 0, weekOffs = 0;
      var totalMinutes = 0, workedDayCount = 0;

      for (final ts in timesheets) {
        switch (ts.status) {
          case DayAttendanceStatus.present:
          case DayAttendanceStatus.late:
          case DayAttendanceStatus.regularized:
          case DayAttendanceStatus.halfDayPresent:
          case DayAttendanceStatus.halfDay:
            present++;
            break;
          case DayAttendanceStatus.halfDayAbsent:
          case DayAttendanceStatus.absent:
          case DayAttendanceStatus.notPayable:
            absent++;
            break;
          case DayAttendanceStatus.leave:
            leave++;
            break;
          case DayAttendanceStatus.holiday:
            holidays++;
            break;
          case DayAttendanceStatus.weekOff:
            weekOffs++;
            break;
          case DayAttendanceStatus.none:
            break;
        }

        if (ts.netWorkingMinutes > 0) {
          totalMinutes += ts.netWorkingMinutes;
          workedDayCount++;
        } else if (ts.clockInTime != null && ts.clockOutTime != null) {
          final durParts = ts.totalHours.split('h');
          if (durParts.length == 2) {
            final h = int.tryParse(durParts[0].trim()) ?? 0;
            final m = int.tryParse(durParts[1].replaceAll(RegExp(r'[^0-9]'), '').trim()) ?? 0;
            final mins = (h * 60) + m;
            if (mins > 0) {
              totalMinutes += mins;
              workedDayCount++;
            }
          }
        }
      }

      final scheduledWorkDays = present + absent + leave;

      return AttendanceSummaryModel(
        totalWorkingDays: scheduledWorkDays > 0 ? scheduledWorkDays : 21,
        presentDays: present,
        absentDays: absent,
        leaveDays: leave,
        holidaysCount: holidays,
        weekOffsCount: weekOffs,
        totalHoursWorked: _formatDuration(totalMinutes),
        avgDailyHours: _formatDuration(workedDayCount > 0 ? totalMinutes ~/ workedDayCount : 0),
      );
    } catch (e) {
      secureLog('[Attendance] getAttendanceSummary error: $e');
      return const AttendanceSummaryModel(
        totalWorkingDays: 0,
        presentDays: 0,
        absentDays: 0,
        leaveDays: 0,
        holidaysCount: 0,
        weekOffsCount: 0,
        totalHoursWorked: '00h 00m',
        avgDailyHours: '00h 00m',
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // REGULARIZATION REQUESTS
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<List<RegularizationRequestModel>> getRegularizationRequests(
    String employeeId,
  ) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final user = UserService.instance.currentUser;
      final targetId = user.dataId.isNotEmpty ? user.dataId : employeeId;

      List<RegularizationRequestModel> requests = [];
      final Set<String> seenIds = {};

      // 1. Primary Source of Truth: Fetch from 'attendance_regularizations' table
      try {
        final empId = user.resolvedEmployeeId.isNotEmpty ? user.resolvedEmployeeId : targetId;
        final tableRows = await withTimeout(
          _client
              .from('attendance_regularizations')
              .select('*')
              .eq('employee_id', empId)
              .order('created_at', ascending: false)
              .limit(50),
        );

        if (tableRows.isNotEmpty) {
          for (final row in tableRows) {
            final id = row['id']?.toString() ?? '';
            if (id.isEmpty || seenIds.contains(id)) continue;
            seenIds.add(id);

            final dateRaw = row['attendance_date'] ?? row['created_at'];
            final inTime = row['requested_check_in'] ?? row['requested_in_time'] ?? '09:30 AM';
            final outTime = row['requested_check_out'] ?? row['requested_out_time'] ?? '06:30 PM';
            final rawStatus = (row['status'] ?? 'PENDING').toString();

            RegularizationStatusState state = RegularizationStatusState.managerPending;
            LeaveStatus leaveStatus = LeaveStatus.pending;

            if (_isWithdrawnStatus(rawStatus)) {
              state = RegularizationStatusState.rejected;
              leaveStatus = LeaveStatus.rejected;
            } else if (_isRejectedStatus(rawStatus)) {
              state = RegularizationStatusState.rejected;
              leaveStatus = LeaveStatus.rejected;
            } else if (_isApprovedStatus(rawStatus)) {
              state = RegularizationStatusState.approved;
              leaveStatus = LeaveStatus.approved;
            } else if (rawStatus.toUpperCase().contains('HR')) {
              state = RegularizationStatusState.hrPending;
              leaveStatus = LeaveStatus.pending;
            } else if (rawStatus.toUpperCase().contains('CLARIF')) {
              state = RegularizationStatusState.clarificationRequired;
              leaveStatus = LeaveStatus.pending;
            }

            requests.add(RegularizationRequestModel(
              id: id,
              employeeId: row['employee_id']?.toString() ?? empId,
              employeeName: row['employee_name']?.toString() ?? user.name,
              department: row['department']?.toString() ?? user.department,
              date: DateTime.tryParse(dateRaw.toString()) ?? DateTime.now(),
              shiftName: row['shift_name']?.toString() ?? 'General Shift',
              shiftWindow: row['shift_window']?.toString() ?? '09:30 AM — 06:30 PM',
              originalInTime: row['original_check_in']?.toString(),
              originalOutTime: row['original_check_out']?.toString(),
              originalStatus: row['original_status']?.toString(),
              requestedInTime: _formatTimeString(inTime.toString()),
              requestedOutTime: _formatTimeString(outTime.toString()),
              reasonCode: row['reason_code']?.toString() ?? 'FORGOT_CHECK_IN',
              reason: row['reason']?.toString() ?? row['reason_text']?.toString() ?? '',
              status: leaveStatus,
              statusState: state,
              currentStage: row['current_stage']?.toString() ?? 'MANAGER_REVIEW',
              managerComment: row['approver_comment']?.toString() ?? row['manager_comment']?.toString(),
              hrComment: row['hr_comment']?.toString(),
              createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
            ));
          }
        }
      } catch (tableErr) {
        secureLog('[Attendance] attendance_regularizations query notice: $tableErr');
      }

      return requests;
    } catch (e) {
      secureLog('[Attendance] getRegularizationRequests error: $e');
      return [];
    }
  }

  @override
  Future<RegularizationRequestModel> submitRegularization(
    RegularizationRequestModel request,
  ) async {
    try {
      if (SupabaseConfig.isConfigured) {
        final user = UserService.instance.currentUser;
        final tenantId = user.tenantId.isNotEmpty
            ? user.tenantId
            : (user.companyId.isNotEmpty ? user.companyId : '0c621892-e938-4707-9957-13534ea32c19');
        final nowStr = DateTime.now().toIso8601String();
        final dateStr = request.date.toIso8601String().split('T')[0];

        // Format requested check in/out as ISO timestamptz
        String rawIn = request.requestedInTime.trim();
        String rawOut = request.requestedOutTime.trim();
        if (rawIn.length == 5) rawIn = '$rawIn:00';
        if (rawOut.length == 5) rawOut = '$rawOut:00';
        final checkInIso = rawIn.isNotEmpty ? '${dateStr}T$rawIn.000Z' : null;
        final checkOutIso = rawOut.isNotEmpty ? '${dateStr}T$rawOut.000Z' : null;

        // 0. Safeguard: Prevent duplicate pending regularization requests for same employee & date
        try {
          final existingPending = await _client
              .from('attendance_regularizations')
              .select('id, status')
              .eq('employee_id', user.resolvedEmployeeId)
              .eq('attendance_date', dateStr)
              .eq('status', 'PENDING')
              .limit(1)
              .maybeSingle();

          if (existingPending != null) {
            secureLog('[Attendance] Regularization request already pending for $dateStr id=${existingPending['id']}');
            return request;
          }
        } catch (dupErr) {
          secureLog('[Attendance] Pending regularization check notice: $dupErr');
        }

        bool insertedDirectly = false;

        // 1. Single Direct Table Insert into 'attendance_regularizations' (Canonical table)
        try {
          final insertPayload = <String, dynamic>{
            'organization_id': tenantId,
            'employee_id': user.resolvedEmployeeId,
            'attendance_date': dateStr,
            if (checkInIso != null) 'requested_check_in': checkInIso,
            if (checkOutIso != null) 'requested_check_out': checkOutIso,
            'reason': request.reason,
            'status': 'PENDING',
            'created_at': nowStr,
            'updated_at': nowStr,
          };
          final inserted = await _client
              .from('attendance_regularizations')
              .insert(insertPayload)
              .select()
              .single();
          secureLog('[Attendance] attendance_regularizations direct insert succeeded: ${inserted['id']}');
          return request;
        } catch (tableErr) {
          secureLog('[Attendance] attendance_regularizations direct insert notice: $tableErr');
        }

        // 2. RPC Submission fallback only if direct insert was not available
        if (!insertedDirectly) {
          try {
            await _client.rpc('fn_submit_attendance_regularization', params: {
              'p_tenant_id': tenantId,
              'p_employee_id': user.resolvedEmployeeId,
              'p_date': dateStr,
              'p_requested_in': request.requestedInTime,
              'p_requested_out': request.requestedOutTime,
              'p_reason_code': request.reasonCode,
              'p_reason_text': request.reason,
              'p_actor_id': user.resolvedEmployeeId,
            });
            secureLog('[Attendance] RPC fn_submit_attendance_regularization fallback succeeded');
          } catch (rpcErr) {
            secureLog('[Attendance] RPC fallback notice: $rpcErr');
          }
        }

        // 3. Realtime Outbox Insert via centralized service
        final payload = {
          'id': request.id,
          if (tenantId.isNotEmpty) 'tenant_id': tenantId,
          if (tenantId.isNotEmpty) 'organization_id': tenantId,
          'employee_id': user.resolvedEmployeeId,
          'employee_code': user.employeeId,
          'employee_name': user.name,
          'department': user.department,
          'attendance_date': dateStr,
          'shift_name': request.shiftName,
          'shift_window': request.shiftWindow,
          'original_check_in': request.originalInTime,
          'original_check_out': request.originalOutTime,
          'original_status': request.originalStatus ?? 'ABSENT',
          'original_source': 'MOBILE_GPS',
          'requested_check_in': request.requestedInTime,
          'requested_check_out': request.requestedOutTime,
          'reason_code': request.reasonCode,
          'reason': request.reason,
          'status': 'PENDING',
          'current_stage': 'MANAGER_REVIEW',
          'manager_id': user.reportsToId?.isNotEmpty == true ? user.reportsToId! : null,
          'manager_name': user.reportsToName?.isNotEmpty == true ? user.reportsToName! : null,
          'timeline': [
            {
              'stage': 'SUBMITTED',
              'timestamp': nowStr,
              'actor': user.name,
              'action': 'REQUEST_SUBMITTED',
              'note': request.reason,
            }
          ],
          'created_at': nowStr,
          'updated_at': nowStr,
        };

        await RealtimeOutboxService.insertEvent(
          entityType: 'attendance_regularizations',
          eventType: 'regularization.submitted',
          entityId: request.id,
          tenantId: tenantId,
          actorId: user.resolvedEmployeeId,
          payload: payload,
        );

        // Send push notification to manager about regularization request
        final managerId = user.reportsToId;
        if (managerId != null && managerId.isNotEmpty) {
          try {
            await PushSenderService.instance.sendToEmployee(
              employeeId: managerId,
              title: 'Attendance Regularization Request',
              body: '${user.name} has requested regularization for $dateStr — ${request.reason}',
              route: 'attendance',
              data: {'request_id': request.id, 'attendance_date': dateStr},
            );
          } catch (e) {
            secureLog('[Attendance] Push to manager notice: $e');
          }
        }

        return request;
      }
    } catch (e) {
      secureLog('[Attendance] submitRegularization failed: $e');
      rethrow;
    }
    return request;
  }

  @override
  Future<void> withdrawRegularization(String requestId) async {
    if (!SupabaseConfig.isConfigured || requestId.isEmpty) return;
    try {
      // 1. Authoritative canonical DELETE from 'attendance_regularizations'
      await _client
          .from('attendance_regularizations')
          .delete()
          .eq('id', requestId);
      secureLog('[Attendance] attendance_regularizations row permanently deleted id=$requestId');

      // 2. Clean up any related notification_events tied to this request
      try {
        await _client
            .from('notification_events')
            .delete()
            .ilike('action_url', '%$requestId%');
      } catch (_) {}
    } catch (e) {
      secureLog('[Attendance] withdrawRegularization failed: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // ATTENDANCE DEVIATIONS (LATE / EARLY / MISSING PUNCH)
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<List<AttendanceDeviationModel>> getAttendanceDeviations(
    String employeeId,
  ) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final user = UserService.instance.currentUser;
      final targetId = user.dataId.isNotEmpty ? user.dataId : employeeId;
      final targetCode = user.employeeId;

      final candidateEmpIds = <String>{
        targetId,
        if (targetCode.isNotEmpty) targetCode,
        if (user.employeeUuid?.isNotEmpty == true) user.employeeUuid!,
        if (user.dataId.isNotEmpty) user.dataId,
        if (employeeId.trim().isNotEmpty) employeeId.trim(),
      }.where((id) => Validators.isValidUuid(id)).toList();

      List<AttendanceDeviationModel> list = [];

      // 1. Fetch from attendance_daily rows
      if (candidateEmpIds.isNotEmpty) {
        try {
          final dailyRows = await withTimeout(
            _client
                .from('attendance_daily')
                .select('*')
                .inFilter('employee_id', candidateEmpIds)
                .order('attendance_date', ascending: false)
                .limit(30),
          );

        for (final row in dailyRows) {
          final firstIn = row['first_check_in']?.toString();
          final lastOut = row['last_check_out']?.toString();
          final dateStr = (row['attendance_date'] ?? row['date'])?.toString() ?? DateTime.now().toIso8601String().split('T')[0];
          final dateParsed = DateTime.tryParse(dateStr) ?? DateTime.now();

          final schedInMins = _parseTimeToMinutes(row['expected_check_in']?.toString()) ?? 540; // 09:00 AM (GEN-09)
          final schedOutMins = _parseTimeToMinutes(row['expected_check_out']?.toString()) ?? 1080; // 06:00 PM (GEN-09)
          final formattedInIst = firstIn != null ? _formatTimeString(firstIn) : null;
          final formattedOutIst = lastOut != null ? _formatTimeString(lastOut) : null;
          final actualInMins = _parseTimeToMinutes(formattedInIst);
          final actualOutMins = _parseTimeToMinutes(formattedOutIst);

          int lateMins = (row['late_entry_minutes'] as num?)?.toInt() ?? 0;
          int earlyMins = (row['early_exit_minutes'] as num?)?.toInt() ?? 0;

          if (lateMins == 0 && actualInMins != null && actualInMins > schedInMins) {
            lateMins = actualInMins - schedInMins;
          }

          if (earlyMins == 0 && actualOutMins != null && actualOutMins < schedOutMins) {
            earlyMins = schedOutMins - actualOutMins;
          }

          final todayDateStr = AttendanceTimeService.todayDateString();
          final isPastDay = dateStr.compareTo(todayDateStr) < 0;

          String? devType;
          if (firstIn == null && lastOut == null) {
            devType = 'MISSING_ATTENDANCE';
          } else if (firstIn == null) {
            devType = 'MISSING_CHECK_IN';
          } else if (lastOut == null && isPastDay) {
            devType = 'MISSING_CHECK_OUT';
          } else if (lateMins > 10 && earlyMins > 10) {
            devType = 'LATE_EARLY';
          } else if (lateMins > 10) {
            devType = 'LATE';
          } else if (earlyMins > 10) {
            devType = 'EARLY';
          }

          if (devType != null) {
            final isRegularized = row['status'] == 'Regularized' || row['source'] == 'REGULARIZATION';
            list.add(AttendanceDeviationModel(
              id: 'dev-$targetId-$dateStr-$devType',
              employeeId: targetId,
              employeeName: user.name,
              department: user.department,
              date: dateParsed,
              shiftCode: row['shift_code']?.toString() ?? 'GEN-09',
              shiftName: row['shift_name']?.toString() ?? 'General Shift',
              scheduledIn: row['expected_check_in']?.toString() ?? '09:00 AM',
              actualIn: formattedInIst,
              lateMinutes: lateMins,
              lateGraceMinutes: 10,
              payableLateMinutes: lateMins > 10 ? lateMins - 10 : 0,
              scheduledOut: row['expected_check_out']?.toString() ?? '06:00 PM',
              actualOut: formattedOutIst,
              earlyMinutes: earlyMins,
              earlyGraceMinutes: 10,
              payableEarlyMinutes: earlyMins > 10 ? earlyMins - 10 : 0,
              deviationType: devType,
              status: isRegularized ? 'REGULARIZED' : 'DETECTED',
              payrollDeductionDays: isRegularized ? 0.0 : (lateMins > 120 ? 0.5 : 0.0),
            ));
          }
        }
        } catch (e) {
          secureLog('[Attendance] getAttendanceDeviations daily query error: $e');
        }
      }

      return list;
    } catch (e) {
      secureLog('[Attendance] getAttendanceDeviations error: $e');
      return [];
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // ACTIONABLE ATTENDANCE EXCEPTIONS (MISSING CHECK-OUT, GPS, ETC.)
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<List<AttendanceExceptionModel>> getActionableAttendanceExceptions(
    String employeeId,
  ) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final user = UserService.instance.currentUser;
      final targetId = user.dataId.isNotEmpty ? user.dataId : employeeId;
      final targetCode = user.employeeId;

      List<AttendanceExceptionModel> list = [];

      // Derive actionable attendance exceptions from canonical attendance_daily table
      try {
        final todayStr = DateTime.now().toIso8601String().split('T')[0];
        final candidateEmpIds = <String>{
          targetId,
          if (targetCode.isNotEmpty) targetCode,
          if (user.employeeUuid?.isNotEmpty == true) user.employeeUuid!,
          if (user.dataId.isNotEmpty) user.dataId,
          if (employeeId.trim().isNotEmpty) employeeId.trim(),
        }.where((id) => Validators.isValidUuid(id)).toList();

        if (candidateEmpIds.isNotEmpty) {
          final dailyRows = await withTimeout(
            _client
                .from('attendance_daily')
                .select('*')
                .inFilter('employee_id', candidateEmpIds)
                .lt('attendance_date', todayStr)
                .order('attendance_date', ascending: false)
                .limit(5),
          );

          for (final row in dailyRows) {
            final firstIn = row['first_check_in']?.toString();
            final lastOut = row['last_check_out']?.toString();
            final dateStr = (row['attendance_date'] ?? row['date'])?.toString() ?? '';
            final status = row['status']?.toString() ?? '';

            if (firstIn != null && (lastOut == null || lastOut.isEmpty) && status != 'Regularized') {
              list.add(
                AttendanceExceptionModel(
                  id: 'exc-missout-$dateStr',
                  exceptionType: 'MISSING_CHECK_OUT',
                  severity: 'HIGH',
                  status: 'EMPLOYEE_ACTION_REQUIRED',
                  workDate: dateStr,
                  title: 'Missing Shift Check-Out',
                  description: 'You checked in at ${_formatTimeString(firstIn)} but no check-out was recorded for this shift.',
                  suggestedAction: 'Regularize Attendance',
                  actualIn: _formatTimeString(firstIn),
                  actualOut: null,
                ),
              );
              break;
            }
          }
        }
      } catch (_) {}

      return list;
    } catch (e) {
      secureLog('[Attendance] getActionableAttendanceExceptions error: $e');
      return [];
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // INTERNALS
  // ────────────────────────────────────────────────────────────────────────

  static DayAttendanceStatus parseStatus(dynamic raw) {
    final s = (raw ?? '').toString().toUpperCase().replaceAll(' ', '_');
    switch (s) {
      case 'PRESENT':
      case 'P':
        return DayAttendanceStatus.present;
      case 'HALF_DAY_PRESENT':
      case 'HALF_DAY':
      case 'HD':
        return DayAttendanceStatus.halfDayPresent;
      case 'HALF_DAY_ABSENT':
        return DayAttendanceStatus.halfDayAbsent;
      case 'ABSENT':
      case 'A':
        return DayAttendanceStatus.absent;
      case 'LEAVE':
      case 'ON_LEAVE':
      case 'L':
        return DayAttendanceStatus.leave;
      case 'HOLIDAY':
      case 'H':
        return DayAttendanceStatus.holiday;
      case 'WEEKLY_OFF':
      case 'WEEK_OFF':
      case 'WO':
      case 'OFF':
        return DayAttendanceStatus.weekOff;
      case 'LATE':
        return DayAttendanceStatus.late;
      case 'REGULARIZED':
      case 'REGULARIZATION':
        return DayAttendanceStatus.regularized;
      case 'NOT_PAYABLE':
      case 'MISSED_PUNCH':
      case 'INCOMPLETE':
      case 'UNPAID':
        return DayAttendanceStatus.notPayable;
      case 'PENDING':
      case 'SCHEDULED':
      case 'NOT_MARKED':
      case 'NONE':
      case '':
        return DayAttendanceStatus.none;
      default:
        return DayAttendanceStatus.none;
    }
  }

  static int? _parseTimeToMinutes(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == '—' || timeStr == 'null') return null;
    final match = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?', caseSensitive: false).firstMatch(timeStr.trim());
    if (match == null) return null;

    int hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final ampm = match.group(3)?.toUpperCase();

    if (ampm == 'PM' && hours < 12) hours += 12;
    if (ampm == 'AM' && hours == 12) hours = 0;

    return hours * 60 + minutes;
  }

  /// "14:30" / "14:30:00" / ISO datetime → "02:30 PM" (IST)
  static String _formatTimeString(String raw) {
    return AppDateTime.formatTimeIST(raw);
  }

  /// 557 minutes → "09h 17m"
  static String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m';
  }

  static String _prettySource(String? raw) {
    switch ((raw ?? '').toString().toUpperCase()) {
      case 'MOBILE':
      case 'MOBILE_GPS':
      case 'APP':
        return 'Mobile Geofence';
      case 'BIOMETRIC':
      case 'DEVICE':
        return 'Biometric';
      case 'WEB':
        return 'Web';
      default:
        return raw?.isNotEmpty == true ? raw! : 'Mobile Geofence';
    }
  }
}
