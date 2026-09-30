import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/hrms_models.dart';
import '../../repositories/supabase/supabase_attendance_repository.dart';
import '../controllers/employee_controller.dart';
import '../services/attendance_time_service.dart';
import '../utils/secure_log.dart';
import 'location_service.dart';
import 'user_service.dart';

class CheckInResult {
  final bool success;
  final String message;

  /// Whether checkout requires a reason from the employee (unauthorized/GPS unavailable)
  final bool requiresReason;

  /// Location verification result (for checkout)
  final CheckoutLocationVerification? verification;

  const CheckInResult({
    required this.success,
    required this.message,
    this.requiresReason = false,
    this.verification,
  });
}

/// App-wide Attendance Service managing Live Check-In State & Real Supabase Synchronization
class AttendanceService extends ChangeNotifier {
  static final AttendanceService instance = AttendanceService._internal();
  AttendanceService._internal();

  final SupabaseAttendanceRepository _repository = SupabaseAttendanceRepository();

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  AttendanceSession _session = const AttendanceSession(
    status: AttendanceStatus.notCheckedIn,
  );

  AttendanceSession get session => _session;

  Timer? _ticker;

  RealtimeChannel? _attendanceChannel;
  String? _subscribedEmpId;

  /// Initializes session listener and loads today's real attendance from Supabase
  void initializeSession() {
    UserService.instance.addListener(() {
      fetchTodayAttendance();
    });
    fetchTodayAttendance();
  }

  void _subscribeRealtime(String employeeId) {
    if (_subscribedEmpId == employeeId && _attendanceChannel != null) return;
    _attendanceChannel?.unsubscribe();

    try {
      _subscribedEmpId = employeeId;
      _attendanceChannel = Supabase.instance.client
          .channel('attendance-realtime-$employeeId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_daily',
          callback: (payload) {
            secureLog('[REALTIME] attendance_daily event (${payload.eventType.name}) -> refreshing attendance');
            fetchTodayAttendance();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_punches',
          callback: (payload) {
            secureLog('[REALTIME] attendance_punches event (${payload.eventType.name}) -> refreshing attendance');
            fetchTodayAttendance();
          },
        )
        ..subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            secureLog('[REALTIME] Subscribed attendance-realtime-$employeeId (attendance_daily, attendance_punches)');
          }
        });
    } catch (e) {
      secureLog('[REALTIME] Attendance subscription notice: $e');
    }
  }

  /// Fetches today's authoritative attendance from Supabase for the currently logged-in employee session
  Future<void> fetchTodayAttendance() async {
    final user = UserService.instance.currentUser;
    if (!UserService.instance.isLoggedIn || user.dataId.isEmpty) {
      _attendanceChannel?.unsubscribe();
      _attendanceChannel = null;
      _subscribedEmpId = null;
      _session = const AttendanceSession(status: AttendanceStatus.notCheckedIn);
      _ticker?.cancel();
      notifyListeners();
      return;
    }

    _subscribeRealtime(user.dataId);

    try {
      final dailyRow = await _repository.getTodayAttendance(user.dataId);

      if (dailyRow != null) {
        final firstIn = dailyRow['first_check_in']?.toString();
        final lastOut = dailyRow['last_check_out']?.toString();
        final netMins = (dailyRow['net_working_minutes'] as num?)?.toInt();
        final isCurrentlyIn = dailyRow['is_currently_in'] == true;

        DateTime? checkInDt;
        DateTime? checkOutDt;

        if (firstIn != null && firstIn.isNotEmpty) {
          checkInDt = AttendanceTimeService.parseServerTimestamp(firstIn, referenceDate: dailyRow['date']?.toString());
        }
        if (lastOut != null && lastOut.isNotEmpty) {
          checkOutDt = AttendanceTimeService.parseServerTimestamp(lastOut, referenceDate: dailyRow['date']?.toString());
        }

        final rawSource = dailyRow['source']?.toString();
        final attendanceSource = AttendanceSource.fromValue(rawSource);
        final verifyMethod = dailyRow['verification_type']?.toString();
        final deviceId = dailyRow['device_id']?.toString();
        final isSourceLocked = attendanceSource != AttendanceSource.unassigned;

        if (checkInDt != null) {
          final isCheckedOut = !isCurrentlyIn && checkOutDt != null && checkOutDt.isAfter(checkInDt);
          if (isCheckedOut) {
            _session = AttendanceSession(
              status: AttendanceStatus.checkedOut,
              checkInTime: checkInDt,
              checkOutTime: checkOutDt,
              netWorkingMinutes: netMins,
              checkInLocationName: dailyRow['location_name']?.toString() ?? user.campus,
              source: attendanceSource,
              sourceLabel: attendanceSource.label,
              verificationMethod: verifyMethod,
              deviceId: deviceId,
              isSourceLocked: isSourceLocked,
            );
            _ticker?.cancel();
          } else {
            _session = AttendanceSession(
              status: AttendanceStatus.checkedIn,
              checkInTime: checkInDt,
              checkInLocationName: dailyRow['location_name']?.toString() ?? user.campus,
              source: attendanceSource,
              sourceLabel: attendanceSource.label,
              verificationMethod: verifyMethod,
              deviceId: deviceId,
              isSourceLocked: isSourceLocked,
            );
            _startTickerIfNeeded();
          }
        } else {
          _session = const AttendanceSession(status: AttendanceStatus.notCheckedIn);
          _ticker?.cancel();
        }
      } else {
        _session = const AttendanceSession(status: AttendanceStatus.notCheckedIn);
        _ticker?.cancel();
      }

      final checkInFormatted = _session.checkInTime != null
          ? AttendanceTimeService.formatAttendanceTime(_session.checkInTime!)
          : null;
      final sessionKey =
          '${user.dataId}|${_session.status.name}|${checkInFormatted ?? ""}|${_session.checkOutTime?.toIso8601String() ?? ""}';
      if (_lastLoggedSessionKey != sessionKey) {
        _lastLoggedSessionKey = sessionKey;
        logSessionBanner(
          event: 'ATTENDANCE STATE SYNCED FOR ACTIVE SESSION',
          isLoggedIn: true,
          employeeName: user.name,
          employeeCode: user.employeeId,
          employeeUuid: user.dataId,
          email: user.officeEmail ?? user.personalEmail,
          attendanceStatus: _session.status.name.toUpperCase(),
          checkInTime: checkInFormatted,
          source: _session.sourceLabel,
        );
      }
    } catch (e) {
      secureLog('[Attendance] fetchTodayAttendance error: $e');
    } finally {
      notifyListeners();
    }
  }

  String? _lastLoggedSessionKey;

  void _startTickerIfNeeded() {
    _ticker?.cancel();
    _ticker = null;
    // Live timer ticking is handled locally by isolated leaf widgets (e.g. AttendanceLiveTimerWidget)
    // to prevent full-screen tree re-rendering, frame drops, and battery drain.
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Perform Real Check-In with location validation & Supabase event insertion
  /// Perform Real Check-In with location validation & Supabase event insertion
  Future<CheckInResult> performCheckIn({
    required UserLocationResult location,
    required ApprovedWorkLocation approvedLocation,
  }) async {
    if (_isProcessing) {
      return const CheckInResult(
        success: false,
        message: "Processing check-in request. Please wait...",
      );
    }

    // 1. Geofence validation: If HR configured coordinates & radius in the DB, enforce it
    final targetLoc = location.targetLocation ?? approvedLocation;
    final hasCoords = targetLoc.latitude != 0.0 || targetLoc.longitude != 0.0;
    final hasRadius = targetLoc.allowedRadiusMeters > 0;

    if (hasCoords && hasRadius && (!location.isInside || location.state == AttendanceGpsState.outsideRadius)) {
      final locName = targetLoc.name.isNotEmpty ? targetLoc.name : 'Assigned Location';
      final radius = targetLoc.allowedRadiusMeters;
      final distStr = location.formattedDistance;
      return CheckInResult(
        success: false,
        message: "Outside authorized zone: You are $distStr away from $locName (Allowed: ${radius.round()}m).",
      );
    }

    // 2. Prevent re-checking in once shift is completed for today (Option A: Single-Shift Policy)
    if (_session.status == AttendanceStatus.checkedOut) {
      return const CheckInResult(
        success: false,
        message: "Your shift for today is already completed. If you checked out by mistake, please apply for Attendance Regularization.",
      );
    }

    // 3. Prevent duplicate check-in
    if (_session.isCheckedIn) {
      final timeStr = _session.checkInTime != null
          ? AttendanceTimeService.formatAttendanceTime(_session.checkInTime!)
          : 'earlier';
      final src = (_session.sourceLabel != null && _session.sourceLabel!.isNotEmpty)
          ? _session.sourceLabel!.toLowerCase()
          : 'biometric';
      return CheckInResult(
        success: false,
        message: "You're already checked in at $timeStr via $src.",
      );
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // 3. Real Supabase insertion into attendance_punches & attendance_daily via RPC
      await _repository.recordPunchEvent(
        type: 'CHECK_IN',
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracyMeters,
        isMocked: location.isMock,
      );

      // 4. Authoritatively refresh session directly from database
      await fetchTodayAttendance();
      unawaited(NotificationController.instance.loadNotifications());

      final locName = location.targetLocation?.name ?? approvedLocation.name;
      return CheckInResult(
        success: true,
        message: "Checked in successfully at $locName (${location.distanceMeters.toStringAsFixed(0)}m).",
      );
    } catch (e) {
      secureLog('[Attendance] Check-in operation failed: $e');
      final errStr = e.toString();
      if (errStr.toLowerCase().contains('already checked in')) {
        await fetchTodayAttendance();
        return const CheckInResult(
          success: true,
          message: "You are already checked in for today's shift.",
        );
      }
      final cleanMsg = errStr.replaceAll(RegExp(r'^(Exception:\s*|PostgrestException\(message:\s*|\))'), '').trim();
      return CheckInResult(
        success: false,
        message: cleanMsg.isNotEmpty ? cleanMsg : "Check-in failed. Please check your connection and try again.",
      );
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Perform Real Check-Out with Supabase event insertion & GPS evidence
  ///
  /// [verification] — Location verification result from evaluateCheckoutLocation()
  /// [reason] — Employee's reason (required if verification.requiresReason)
  ///
  /// IMPORTANT: Check-in remains strict. Checkout is ALWAYS allowed but location
  /// is verified and classified for audit purposes.
  Future<CheckInResult> performCheckOut({
    UserLocationResult? location,
    CheckoutLocationVerification? verification,
    String? reason,
  }) async {
    if (_isProcessing) {
      return const CheckInResult(
        success: false,
        message: "Processing check-out request. Please wait...",
      );
    }

    if (!_session.isCheckedIn) {
      return const CheckInResult(
        success: false,
        message: "Check-out failed: You are not currently checked in.",
      );
    }

    _isProcessing = true;
    notifyListeners();

    try {
      final loc = location ?? LocationService.instance.currentResult;

      // Use provided verification or evaluate fresh
      final locVerification = verification ?? await LocationService.instance.evaluateCheckoutLocation();

      // If verification requires a reason but none provided, return error
      if (locVerification.requiresReason && (reason == null || reason.trim().isEmpty)) {
        _isProcessing = false;
        notifyListeners();
        return CheckInResult(
          success: false,
          message: locVerification.statusMessage,
          requiresReason: true,
          verification: locVerification,
        );
      }

      // Attach reason to verification if provided
      final verifiedWithReason = reason != null && reason.trim().isNotEmpty
          ? CheckoutLocationVerification(
              status: locVerification.status,
              locationName: locVerification.locationName,
              reason: reason.trim(),
              latitude: locVerification.latitude,
              longitude: locVerification.longitude,
              accuracyMeters: locVerification.accuracyMeters,
              distanceToNearestMeters: locVerification.distanceToNearestMeters,
              matchedLocation: locVerification.matchedLocation,
            )
          : locVerification;

      // 1. Real Supabase insertion into attendance_punches & attendance_daily
      //    with location verification data
      await _repository.recordPunchEvent(
        type: 'CHECK_OUT',
        latitude: loc.latitude != 0 ? loc.latitude : null,
        longitude: loc.longitude != 0 ? loc.longitude : null,
        accuracy: loc.accuracyMeters > 0 ? loc.accuracyMeters : null,
        isMocked: loc.isMock,
        checkoutVerification: verifiedWithReason,
      );

      // 2. Authoritatively refresh session directly from database
      _ticker?.cancel();
      await fetchTodayAttendance();
      unawaited(NotificationController.instance.loadNotifications());

      return CheckInResult(
        success: true,
        message: verifiedWithReason.statusMessage,
        verification: verifiedWithReason,
      );
    } catch (e) {
      secureLog('[Attendance] Check-out operation failed: $e');
      final errStr = e.toString();
      final cleanMsg = errStr.replaceAll(RegExp(r'^(Exception:\s*|PostgrestException\(message:\s*|\))'), '').trim();
      return CheckInResult(
        success: false,
        message: cleanMsg.isNotEmpty ? cleanMsg : "Check-out failed. Please check your connection and try again.",
      );
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Get dynamic elapsed working duration since check-in
  Duration get elapsedWorkingDuration {
    if (!_session.isCheckedIn || _session.checkInTime == null) {
      if (_session.isCheckedOut && _session.netWorkingMinutes != null) {
        return Duration(minutes: _session.netWorkingMinutes!);
      }
      if (_session.isCheckedOut && _session.checkInTime != null && _session.checkOutTime != null) {
        return AttendanceTimeService.calculateDuration(
          checkIn: _session.checkInTime,
          checkOut: _session.checkOutTime,
        );
      }
      return Duration.zero;
    }
    return AttendanceTimeService.calculateDuration(checkIn: _session.checkInTime);
  }

  /// Formatted timer string HH:MM:SS
  String get formattedTimer {
    return AttendanceTimeService.formatDurationTimer(elapsedWorkingDuration);
  }
}
