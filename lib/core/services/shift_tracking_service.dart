import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';
import 'attendance_service.dart';
import 'background_tracking_service.dart';
import 'user_service.dart';

/// ShiftTrackingService
///
/// Manages enterprise real-time GPS location tracking for field and shift employees.
/// - Active whenever employee has Location ON during their assigned shift timing,
///   as well as throughout active check-in sessions.
/// - Runs continuously in background via Android Foreground Service notification.
/// - Features military-grade stationary anchor anti-drift filtering (filters out indoor GPS flutter).
/// - Calculates running cumulative travel distance for shift expense/reimbursement.
/// - Syncs to `employee_live_locations` and `employee_location_trails` via Supabase.
class ShiftTrackingService extends ChangeNotifier with WidgetsBindingObserver {
  static final ShiftTrackingService instance = ShiftTrackingService._internal();
  ShiftTrackingService._internal();

  /// Minimum walking speed required to consider the user in motion (0.75 m/s = 2.7 km/h)
  static const double minWalkingSpeedMps = 0.75;

  /// Minimum displacement required to trigger a telemetry ping when moving (20 meters)
  static const double minDisplacementMeters = 20.0;

  /// Maximum GPS accuracy uncertainty acceptable to accumulate distance (65 meters — industry standard for smartphone road tracking)
  static const double maxAcceptableAccuracyMeters = 65.0;

  StreamSubscription<Position>? _positionSub;
  Timer? _stationaryHeartbeatTimer;
  Timer? _shiftWindowMonitorTimer;

  Position? _lastRecordedPosition;
  Position? get lastRecordedPosition => _lastRecordedPosition;

  Position? _stationaryAnchor;
  Position? get stationaryAnchor => _stationaryAnchor;

  double _cumulativeDistanceMeters = 0.0;
  double get cumulativeDistanceMeters => _cumulativeDistanceMeters;

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  bool _isMoving = false;
  bool get isMoving => _isMoving;

  DateTime? _lastPingTime;
  DateTime? get lastPingTime => _lastPingTime;

  String? _telemetryAccessToken;
  DateTime? _telemetryTokenExpiresAt;

  Future<String?> _getTelemetryAccessToken() async {
    // 1. Authoritative: Use current authenticated employee's active session token
    if (SupabaseConfig.isConfigured) {
      try {
        final auth = Supabase.instance.client.auth;
        var session = auth.currentSession;

        // If session is null, attempt recovery from persisted local storage
        if (session == null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            final tokenKey = "sb-${Uri.parse(SupabaseConfig.url).host.split(".").first}-auth-token";
            final rawToken = prefs.getString(tokenKey);
            if (rawToken != null && rawToken.trim().isNotEmpty) {
              final recoveredRes = await auth.recoverSession(rawToken);
              session = recoveredRes.session;
            }
          } catch (recoverErr) {
            secureLog('[ShiftTracking] Session recovery attempt notice: $recoverErr');
          }
        }

        // If session is expired, refresh it proactively
        if (session != null && session.isExpired) {
          try {
            final refreshed = await auth.refreshSession();
            session = refreshed.session ?? auth.currentSession;
          } catch (refreshErr) {
            secureLog('[ShiftTracking] Session refresh attempt notice: $refreshErr');
          }
        }

        final sessionToken = session?.accessToken;
        if (sessionToken != null && sessionToken.isNotEmpty) {
          return sessionToken;
        }
      } catch (e) {
        secureLog('[ShiftTracking] Auth token read error: $e');
      }
    }

    if (_telemetryAccessToken != null &&
        _telemetryTokenExpiresAt != null &&
        DateTime.now().isBefore(_telemetryTokenExpiresAt!)) {
      return _telemetryAccessToken;
    }

    return null;
  }

  Future<bool> _syncLiveLocationViaTelemetry(Map<String, dynamic> payload) async {
    final token = await _getTelemetryAccessToken();
    if (token == null) return false;

    try {
      final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/employee_live_locations?on_conflict=organization_id,employee_id');
      final res = await http.post(
        uri,
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return true;
      }
      secureLog('[ShiftTracking] Telemetry live upsert failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      secureLog('[ShiftTracking] Telemetry live upsert error: $e');
    }
    return false;
  }

  Future<bool> _insertTrailViaTelemetry(Map<String, dynamic> payload) async {
    final token = await _getTelemetryAccessToken();
    if (token == null) return false;

    try {
      final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/employee_location_trails');
      final res = await http.post(
        uri,
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return true;
      }
      secureLog('[ShiftTracking] Telemetry trail insert failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      secureLog('[ShiftTracking] Telemetry trail insert error: $e');
    }
    return false;
  }

  Future<void> _loadTodayCumulativeDistance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final key = 'shift_dist_${now.year}_${now.month}_${now.day}';
      _cumulativeDistanceMeters = prefs.getDouble(key) ?? 0.0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistCumulativeDistance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final key = 'shift_dist_${now.year}_${now.month}_${now.day}';
      await prefs.setDouble(key, _cumulativeDistanceMeters);
    } catch (_) {}
  }

  /// Initializes shift tracking listener tied to attendance status and shift timing
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    AttendanceService.instance.addListener(_handleAttendanceStateChange);
    UserService.instance.addListener(_handleAttendanceStateChange);

    // Periodically re-check attendance & shift window every 2 minutes (catches biometric machine punches)
    _shiftWindowMonitorTimer?.cancel();
    _shiftWindowMonitorTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (UserService.instance.isLoggedIn) {
        AttendanceService.instance.fetchTodayAttendance();
      }
      _handleAttendanceStateChange();
    });

    _handleAttendanceStateChange();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAttendanceStateChange();
    }
  }

  /// Parses time strings (e.g., "09:30 AM", "6:30 PM", "09:00", "18:00")
  TimeOfDay? _parseTimeOfDay(String timeStr) {
    if (timeStr.trim().isEmpty) return null;
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPm = clean.contains('PM');
      final isAm = clean.contains('AM');

      final numericPart = clean.replaceAll(RegExp(r'[^0-9:]'), '').trim();
      final parts = numericPart.split(':');
      if (parts.isEmpty) return null;

      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;

      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  /// Determines if current local time falls within the employee's assigned shift hours
  bool isCurrentlyWithinShiftWindow() {
    final user = UserService.instance.currentUser;
    if (!UserService.instance.isLoggedIn) return false;

    // Parse user's assigned shift start and end times
    final startStr = user.shiftStart.trim();
    final endStr = user.shiftEnd.trim();

    final now = DateTime.now();

    TimeOfDay? startTime = _parseTimeOfDay(startStr);
    TimeOfDay? endTime = _parseTimeOfDay(endStr);

    // Default shift window: 08:30 AM to 07:00 PM if unspecified
    startTime ??= const TimeOfDay(hour: 8, minute: 30);
    endTime ??= const TimeOfDay(hour: 19, minute: 0);

    // Include a 30-minute grace window before shift start
    final startDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      startTime.hour,
      startTime.minute,
    ).subtract(const Duration(minutes: 30));

    // Include a 30-minute grace window after shift end
    DateTime endDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      endTime.hour,
      endTime.minute,
    ).add(const Duration(minutes: 30));

    // Handle overnight shifts spanning past midnight
    if (endDateTime.isBefore(startDateTime)) {
      endDateTime = endDateTime.add(const Duration(days: 1));
    }

    return now.isAfter(startDateTime) && now.isBefore(endDateTime);
  }

  void _handleAttendanceStateChange() {
    final session = AttendanceService.instance.session;
    final isCheckedIn = session.isCheckedIn;
    final isCheckedOut = session.isCheckedOut;
    final isOnLeave = session.isOnLeave;
    final isLoggedIn = UserService.instance.isLoggedIn;

    // Strict privacy rule: If employee is on approved leave today OR has clocked out, never track GPS!
    if (isOnLeave || isCheckedOut) {
      if (_isTracking) {
        stopShiftTracking();
      }
      return;
    }

    if (isLoggedIn) {
      final isShiftActive = isCurrentlyWithinShiftWindow();
      // Track continuously if employee is checked in (via mobile or biometric) OR within assigned shift hours
      if (isCheckedIn || isShiftActive) {
        final status = isCheckedIn ? 'on_duty' : 'active_shift';

        // Sync initial/current position safely
        try {
          syncCurrentDeviceLocation(status: status);
        } catch (_) {}

        // Start continuous stream safely when employee is logged in with location enabled
        if (!_isTracking) {
          final isAppForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
          if (isAppForeground) {
            startShiftTracking();
          }
        }
      } else {
        // Outside shift hours and not checked in -> clean standby stop
        if (_isTracking) {
          stopShiftTracking();
        }
      }
    } else {
      if (_isTracking) {
        stopShiftTracking();
      }
    }
  }

  /// Immediately transmits current device GPS to Supabase fleet radar with high-accuracy satellite fix
  Future<bool> syncCurrentDeviceLocation({String status = 'on_duty'}) async {
    final session = AttendanceService.instance.session;
    if (session.isOnLeave || session.isCheckedOut) {
      return false;
    }

    final user = UserService.instance.currentUser;
    if (user.dataId.isEmpty && user.employeeId.isEmpty) return false;

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return false;
    }

    final isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationServiceEnabled) {
      return false;
    }

    // 1. High-accuracy satellite hardware acquisition (prioritize best precision)
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      secureLog('[ShiftTracking] Navigation-accuracy GPS timeout/error ($e), trying high accuracy...');
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (e2) {
        secureLog('[ShiftTracking] High-accuracy timeout/error ($e2)');
      }
    }

    final bool isFirstEverFix = _lastRecordedPosition == null;

    // 2. If satellite fix acquired with acceptable precision, record it immediately
    if (pos != null) {
      secureLog('[ShiftTracking] GPS acquired: (${pos.latitude}, ${pos.longitude}, acc: ±${pos.accuracy.toStringAsFixed(1)}m)');
      await _recordPosition(
        pos,
        isInitial: isFirstEverFix,
        isRoutineSync: false,
        forcedStatus: status,
      );
      return true;
    }

    // 3. Fallback to cached position if it has acceptable accuracy (<= 65m)
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && lastKnown.accuracy <= maxAcceptableAccuracyMeters) {
        secureLog('[ShiftTracking] Using verified accurate cached fix: ±${lastKnown.accuracy.toStringAsFixed(1)}m');
        await _recordPosition(
          lastKnown,
          isInitial: isFirstEverFix,
          isRoutineSync: false,
          forcedStatus: status,
        );
        return true;
      }
    } catch (_) {}

    secureLog('[ShiftTracking] Failed to acquire fresh satellite fix.');
    return _lastRecordedPosition != null;
  }

  /// Retrieves historical travel waypoints from Supabase for a given calendar date (YYYY-MM-DD)
  Future<List<Map<String, dynamic>>> getHistoricalTrails(String dateStr) async {
    final user = UserService.instance.currentUser;
    final orgId = (user.organizationId != null && user.organizationId!.isNotEmpty)
        ? user.organizationId!
        : (user.companyId.isNotEmpty ? user.companyId : '0c621892-e938-4707-9957-13534ea32c19');
    final empId = user.dataId.isNotEmpty ? user.dataId : user.employeeId;

    if (orgId.isEmpty || empId.isEmpty) return [];

    DateTime dayStart;
    DateTime dayEnd;
    if (dateStr.contains('-')) {
      final parts = dateStr.split('-').map(int.parse).toList();
      dayStart = DateTime(parts[0], parts[1], parts[2], 0, 0, 0, 0).toUtc();
      dayEnd = DateTime(parts[0], parts[1], parts[2], 23, 59, 59, 999).toUtc();
    } else {
      final now = DateTime.now();
      dayStart = DateTime(now.year, now.month, now.day, 0, 0, 0, 0).toUtc();
      dayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toUtc();
    }

    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('employee_location_trails')
          .select('*')
          .eq('organization_id', orgId)
          .eq('employee_id', empId)
          .gte('recorded_at', dayStart.toIso8601String())
          .lte('recorded_at', dayEnd.toIso8601String())
          .order('recorded_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(res as List);
      if (list.isNotEmpty) return list;
    } catch (e) {
      secureLog('[ShiftTracking] Standard historical trails fetch error: $e');
    }

    // Telemetry transport fallback query for full authorization
    try {
      final token = await _getTelemetryAccessToken();
      if (token != null) {
        final queryUrl = '${SupabaseConfig.url}/rest/v1/employee_location_trails'
            '?organization_id=eq.$orgId'
            '&employee_id=eq.$empId'
            '&recorded_at=gte.${dayStart.toIso8601String()}'
            '&recorded_at=lte.${dayEnd.toIso8601String()}'
            '&order=recorded_at.asc';
        final response = await http.get(
          Uri.parse(queryUrl),
          headers: {
            'apikey': SupabaseConfig.anonKey,
            'Authorization': 'Bearer $token',
          },
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return List<Map<String, dynamic>>.from(data as List);
        }
      }
    } catch (e) {
      secureLog('[ShiftTracking] Telemetry fallback trails error: $e');
    }

    return [];
  }

  /// Starts the GPS stream with 35m distance filtering and Android Foreground Service
  Future<void> startShiftTracking() async {
    if (_isTracking) return;

    final user = UserService.instance.currentUser;
    if (user.dataId.isEmpty && user.employeeId.isEmpty) return;

    // Check location permission
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      secureLog('[ShiftTracking] Location permission not granted. Skipping track.');
      return;
    }

    _isTracking = true;
    _stationaryAnchor = null;
    _lastRecordedPosition = null;
    await _loadTodayCumulativeDistance();
    notifyListeners();

    // Start persistent background service (survives app swipe / closure)
    final empId = user.dataId.isNotEmpty ? user.dataId : user.employeeId;
    final orgId = (user.organizationId != null && user.organizationId!.isNotEmpty)
        ? user.organizationId!
        : '0c621892-e938-4707-9957-13534ea32c19';
    BackgroundTrackingService.instance.start(
      employeeId: empId,
      organizationId: orgId,
      employeeName: user.name,
      employeeCode: user.employeeId,
    );

    secureLog('[ShiftTracking] Shift tracking STARTED for ${user.name} (Foreground Service Active)');

    // 1. Capture initial location immediately upon starting
    try {
      final initialPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await _recordPosition(initialPos, isInitial: true);
    } catch (e) {
      secureLog('[ShiftTracking] Initial position capture failed: $e');
    }

    // 2. Stream updates with 30-meter distance filter & Foreground Notification (Google Fused Location)
    late final LocationSettings locationSettings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 15, // 15-meter displacement trigger
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "JOY PeopleHR • GPS Tracking Active",
          notificationText: "High-accuracy Google Maps GPS active during work hours",
          enableWakeLock: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 15,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      );
    }

    try {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (pos) => _recordPosition(pos),
        onError: (err) => secureLog('[ShiftTracking] Stream error: $err'),
      );
    } catch (e) {
      secureLog('[ShiftTracking] Foreground stream failed ($e), falling back to standard stream...');
      try {
        _positionSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
          ),
        ).listen(
          (pos) => _recordPosition(pos),
          onError: (err) => secureLog('[ShiftTracking] Fallback stream error: $err'),
        );
      } catch (e2) {
        secureLog('[ShiftTracking] Fallback stream failed: $e2');
      }
    }

    // 3. 10-Minute stationary heartbeat so HR radar knows device is alive while idle
    _stationaryHeartbeatTimer?.cancel();
    _stationaryHeartbeatTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      if (!_isTracking) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        await _recordPosition(pos, isHeartbeat: true);
      } catch (e) {
        secureLog('[ShiftTracking] Heartbeat failed: $e');
      }
    });
  }

  /// Evaluates displacement, accuracy, and syncs to Supabase with anti-drift stationary filtering
  Future<void> _recordPosition(
    Position currentPos, {
    bool isInitial = false,
    bool isHeartbeat = false,
    bool isRoutineSync = false,
    String? forcedStatus,
  }) async {
    final user = UserService.instance.currentUser;
    final orgId = (user.organizationId != null && user.organizationId!.isNotEmpty)
        ? user.organizationId!
        : (user.companyId.isNotEmpty ? user.companyId : '0c621892-e938-4707-9957-13534ea32c19');
    final empId = user.dataId.isNotEmpty ? user.dataId : user.employeeId;

    if (orgId.isEmpty || empId.isEmpty) return;

    // Strict demo account rule: Never broadcast telemetry for demo or ghost accounts
    final email = (user.officeEmail ?? user.personalEmail).toLowerCase().trim();
    final isDemoOrTest = user.employeeId == 'JCS-099' ||
        email.contains('demo') ||
        email.contains('joypeoplehr.com') ||
        user.name.toUpperCase().contains('ARJUN KUMAR') ||
        user.name.toUpperCase().contains('DEMO');
    if (isDemoOrTest) {
      secureLog('[ShiftTracking] Telemetry broadcast suppressed for demo account: ${user.employeeId}');
      if (_isTracking) stopShiftTracking();
      return;
    }

    // Strict privacy rule: If user is checked out or on leave, reject tracking!
    final session = AttendanceService.instance.session;
    if (session.isOnLeave || session.isCheckedOut) {
      if (_isTracking) stopShiftTracking();
      return;
    }

    // Strict security rule: Filter out mocked/spoofed locations
    if (currentPos.isMocked) {
      secureLog('[ShiftTracking] Rejected spoofed/mocked GPS fix');
      return;
    }

    // Filter out Android Studio Emulator default location (Googleplex, Mountain View CA: ~37.42, -122.08)
    final bool isGooglePlexEmulator = (currentPos.latitude >= 37.41 && currentPos.latitude <= 37.43) &&
        (currentPos.longitude >= -122.09 && currentPos.longitude <= -122.07);
    if (isGooglePlexEmulator) {
      secureLog('[ShiftTracking] Rejected default Android emulator Googleplex location');
      return;
    }

    // Debounce rapid duplicate pings within 3 seconds
    if (_lastPingTime != null &&
        DateTime.now().difference(_lastPingTime!).inSeconds < 3 &&
        !isInitial) {
      return;
    }

    // 1. Evaluate speed directly from hardware GPS Doppler sensor.
    // Speed < 0.75 m/s (~2.7 km/h) or <= 0 indicates stationary/desk idle.
    final double rawSpeed = currentPos.speed > 0 ? currentPos.speed : 0.0;
    final bool isMovingBySpeed = rawSpeed >= minWalkingSpeedMps;

    // 2. Measure displacement from previous recorded position
    double displacement = 0.0;
    if (_lastRecordedPosition != null && !isInitial) {
      displacement = Geolocator.distanceBetween(
        _lastRecordedPosition!.latitude,
        _lastRecordedPosition!.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );
    }

    // 3. STATIONARY ANCHOR FILTER:
    // When an employee sits at a desk, GPS fluctuates within a 10m-35m radius.
    // We anchor to _stationaryAnchor. As long as fixes remain within anchor zone
    // or speed is stationary (< 0.75 m/s), distance accumulated is strictly 0.00 km.
    _stationaryAnchor ??= currentPos;

    final double distanceFromAnchor = Geolocator.distanceBetween(
      _stationaryAnchor!.latitude,
      _stationaryAnchor!.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );

    // True physical transit detection:
    // (a) Moving speed >= 0.75 m/s (~2.7 km/h) AND displacement from anchor >= 20m
    // OR (b) Physical displacement from anchor >= 25m with acceptable accuracy fix (<= 65m)
    //      (this reliably captures walking, cycling, or vehicle transit even when Android GPS reports speed = 0.0)
    final bool isAccurateFix = currentPos.accuracy <= maxAcceptableAccuracyMeters;
    final bool hasBrokenAnchor = distanceFromAnchor >= minDisplacementMeters &&
        (isMovingBySpeed || (isAccurateFix && distanceFromAnchor >= 25.0));

    final bool isMoving = hasBrokenAnchor || (isMovingBySpeed && displacement >= minDisplacementMeters);

    final isCheckedIn = AttendanceService.instance.session.isCheckedIn;
    final isShiftActive = isCurrentlyWithinShiftWindow();

    if (!isMoving) {
      // User is stationary! Suppress micro-drift jitter.
      displacement = 0.0;

      // If user relocated to a new stationary desk/place while app was closed or idle:
      // (a) If minor drift (< 200m), quietly adopt new anchor without adding fake walking distance.
      // (b) If genuine geographic transit (>= 200m) occurred while app was backgrounded/restarted during active shift,
      //     preserve the real travel displacement!
      if (distanceFromAnchor >= 200.0 && isAccurateFix && (isCheckedIn || isShiftActive)) {
        _cumulativeDistanceMeters += distanceFromAnchor;
        _stationaryAnchor = currentPos;
        _persistCumulativeDistance();
        secureLog('[ShiftTracking] Captured transit relocation across app restart: +${(distanceFromAnchor / 1000).toStringAsFixed(2)}km');
      } else if (distanceFromAnchor > 45.0 && isAccurateFix) {
        _stationaryAnchor = currentPos;
      }
    } else {
      // User is in active transit (walking, biking, driving)
      // Accumulate real travel displacement and advance anchor
      _cumulativeDistanceMeters += displacement;
      _stationaryAnchor = currentPos;
      _persistCumulativeDistance();
    }

    _isMoving = isMoving;
    _lastRecordedPosition = currentPos;
    _lastPingTime = DateTime.now();
    notifyListeners();

    final status = forcedStatus ??
        (isMoving
            ? 'moving'
            : (isCheckedIn
                ? 'on_duty'
                : (isShiftActive ? 'active_shift' : 'stationary')));

    // Read real hardware device battery level and charging state
    int? batteryLevel;
    bool isCharging = false;
    try {
      final battery = Battery();
      batteryLevel = await battery.batteryLevel;
      final state = await battery.batteryState;
      isCharging = state == BatteryState.charging || state == BatteryState.full;
    } catch (e) {
      secureLog('[ShiftTracking] Battery check error: $e');
    }

    try {
      final supabase = Supabase.instance.client;

      // 1. Update Live Fleet Radar (single row per employee)
      final livePayload = {
        'organization_id': orgId,
        'employee_id': empId,
        'employee_name': user.name,
        'employee_code': user.employeeId,
        'department_name': user.department,
        'latitude': currentPos.latitude,
        'longitude': currentPos.longitude,
        'accuracy': currentPos.accuracy,
        'speed': rawSpeed,
        'battery_level': batteryLevel,
        'is_charging': isCharging,
        'is_moving': isMoving,
        'status': status,
        'cumulative_distance_meters': _cumulativeDistanceMeters,
        'last_pinged_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      try {
        await supabase.from('employee_live_locations').upsert(
          livePayload,
          onConflict: 'organization_id,employee_id',
        );
      } catch (upsertErr) {
        secureLog('[ShiftTracking] Standard live upsert rejected ($upsertErr), using telemetry transport bridge...');
        await _syncLiveLocationViaTelemetry(livePayload);
      }

      // 2. Insert into Breadcrumb Trail
      // STRICT TRAIL RULES:
      // - Heartbeats NEVER insert breadcrumb points.
      // - Stationary jitter NEVER inserts breadcrumb points.
      // - Genuine shift start (isInitial) OR actual transit (isMoving with displacement >= 20m or distance from anchor >= 25m)
      final bool hasRealMovement = displacement >= minDisplacementMeters || distanceFromAnchor >= 25.0;
      final bool shouldRecordTrail = isAccurateFix &&
          !isHeartbeat &&
          (isInitial || (isMoving && hasRealMovement));

      if (shouldRecordTrail) {
        final trailPayload = {
          'organization_id': orgId,
          'employee_id': empId,
          'latitude': currentPos.latitude,
          'longitude': currentPos.longitude,
          'accuracy': currentPos.accuracy,
          'speed': rawSpeed,
          'battery_level': batteryLevel,
          'displacement_meters': isInitial ? 0.0 : displacement,
          'cumulative_distance_meters': _cumulativeDistanceMeters,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
          'metadata': {
            'is_initial': isInitial,
            'is_heartbeat': isHeartbeat,
            'status': status,
            'is_charging': isCharging,
          },
        };

        try {
          await supabase.from('employee_location_trails').insert(trailPayload);
          _flushOfflineTrails(supabase);
        } catch (trailErr) {
          secureLog('[ShiftTracking] Standard trail insert rejected ($trailErr), trying telemetry transport bridge...');
          final ok = await _insertTrailViaTelemetry(trailPayload);
          if (ok) {
            _flushOfflineTrails(supabase);
          } else {
            await _queueOfflineTrail(trailPayload);
          }
        }
      }

      secureLog(
        '[ShiftTracking] Radar updated: (${currentPos.latitude.toStringAsFixed(5)}, ${currentPos.longitude.toStringAsFixed(5)}) '
        'Speed: ${rawSpeed.toStringAsFixed(2)}m/s | Moving: $isMoving | Dist: ${(_cumulativeDistanceMeters / 1000).toStringAsFixed(2)}km | '
        'Trail: $shouldRecordTrail',
      );
    } catch (e) {
      secureLog('[ShiftTracking] Supabase sync error: $e');
    }
  }

  static const String _kOfflineTrailQueueKey = 'sp_offline_location_trails_queue';

  /// Caches waypoints locally when network drops so travel routes have zero missing gaps
  Future<void> _queueOfflineTrail(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_kOfflineTrailQueueKey) ?? [];
      if (existing.length < 250) {
        existing.add(jsonEncode(payload));
        await prefs.setStringList(_kOfflineTrailQueueKey, existing);
        secureLog('[ShiftTracking] Stored offline trail waypoint locally (total: ${existing.length})');
      }
    } catch (_) {}
  }

  /// Automatically sends pending offline waypoints to Supabase when network connectivity returns
  Future<void> _flushOfflineTrails(SupabaseClient supabase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queued = prefs.getStringList(_kOfflineTrailQueueKey);
      if (queued == null || queued.isEmpty) return;

      final List<Map<String, dynamic>> itemsToInsert = [];
      for (final item in queued) {
        try {
          itemsToInsert.add(Map<String, dynamic>.from(jsonDecode(item)));
        } catch (_) {}
      }

      if (itemsToInsert.isNotEmpty) {
        try {
          await supabase.from('employee_location_trails').insert(itemsToInsert);
          await prefs.remove(_kOfflineTrailQueueKey);
          secureLog('[ShiftTracking] Flushed ${itemsToInsert.length} offline waypoints to Supabase');
        } catch (_) {
          // Try flushing sequentially through telemetry bridge
          int flushed = 0;
          final remaining = <String>[];
          for (final item in itemsToInsert) {
            final ok = await _insertTrailViaTelemetry(item);
            if (ok) {
              flushed++;
            } else {
              remaining.add(jsonEncode(item));
            }
          }
          if (flushed > 0) {
            await prefs.setStringList(_kOfflineTrailQueueKey, remaining);
            secureLog('[ShiftTracking] Telemetry bridge flushed $flushed offline waypoints');
          }
        }
      }
    } catch (e) {
      secureLog('[ShiftTracking] Pending offline flush retry on next fix: $e');
    }
  }

  /// Stops tracking when outside shift hours or on explicit logout
  Future<void> stopShiftTracking() async {
    if (!_isTracking) return;

    _positionSub?.cancel();
    _positionSub = null;
    _stationaryHeartbeatTimer?.cancel();
    _stationaryHeartbeatTimer = null;
    _isTracking = false;
    notifyListeners();

    // Stop persistent background service
    BackgroundTrackingService.instance.stop();

    final user = UserService.instance.currentUser;
    final orgId = user.companyId;
    final empId = user.employeeUuid ?? user.employeeId;

    secureLog('[ShiftTracking] Shift tracking STOPPED for ${user.name}');

    // Mark status as off_duty on the radar
    if (orgId.isNotEmpty && empId.isNotEmpty) {
      try {
        await Supabase.instance.client
            .from('employee_live_locations')
            .update({
              'status': 'off_duty',
              'is_moving': false,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('organization_id', orgId)
            .eq('employee_id', empId);
      } catch (e) {
        secureLog('[ShiftTracking] Off-duty update error: $e');
      }
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stationaryHeartbeatTimer?.cancel();
    _shiftWindowMonitorTimer?.cancel();
    AttendanceService.instance.removeListener(_handleAttendanceStateChange);
    UserService.instance.removeListener(_handleAttendanceStateChange);
    super.dispose();
  }
}
