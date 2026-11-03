// Joy PeopleHR — Enterprise Background GPS Tracking Service
// ============================================================================
// Keeps GPS tracking alive even when the employee swipes away or kills the app.
// Uses an independent Android Foreground Service running in a dedicated isolate.
// Automatically syncs displacement (>25m) and heartbeat fixes to Supabase.
// ============================================================================

import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';

const String _kPrefBgTrackingActive = 'sp_bg_tracking_active_v1';
const String _kPrefBgTrackingEmpId = 'sp_bg_tracking_emp_id_v1';
const String _kPrefBgTrackingOrgId = 'sp_bg_tracking_org_id_v1';
const String _kPrefBgTrackingEmpName = 'sp_bg_tracking_emp_name_v1';
const String _kPrefBgTrackingEmpCode = 'sp_bg_tracking_emp_code_v1';
const String _kPrefBgTrackingCumDist = 'sp_bg_tracking_cum_dist_v1';

class BackgroundTrackingService {
  static final BackgroundTrackingService instance = BackgroundTrackingService._internal();
  BackgroundTrackingService._internal();

  bool _isConfigured = false;

  /// Initializes the background service configuration.
  /// Must be called during app boot.
  Future<void> initialize() async {
    if (_isConfigured || kIsWeb) return;

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'joy_peoplehr_shift_tracking',
        initialNotificationTitle: 'JOY PeopleHR • Shift Tracking Active',
        initialNotificationContent: 'GPS active during shift hours',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onBackgroundServiceStart,
        onBackground: onIosBackground,
      ),
    );

    _isConfigured = true;
    secureLog('[BackgroundTracking] Background service configured successfully');

    // Auto-resume tracking if shift was active before phone reboot / force close
    final prefs = await SharedPreferences.getInstance();
    final wasActive = prefs.getBool(_kPrefBgTrackingActive) ?? false;
    if (wasActive) {
      final isRunning = await service.isRunning();
      if (!isRunning) {
        secureLog('[BackgroundTracking] Resuming interrupted shift tracking in background...');
        await service.startService();
      }
    }
  }

  /// Starts the persistent background tracking service.
  /// Survives app swipe / closure from Recent Apps.
  Future<void> start({
    required String employeeId,
    required String organizationId,
    required String employeeName,
    required String employeeCode,
  }) async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefBgTrackingActive, true);
    await prefs.setString(_kPrefBgTrackingEmpId, employeeId);
    await prefs.setString(_kPrefBgTrackingOrgId, organizationId);
    await prefs.setString(_kPrefBgTrackingEmpName, employeeName);
    await prefs.setString(_kPrefBgTrackingEmpCode, employeeCode);

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      secureLog('[BackgroundTracking] Persistent background service STARTED for $employeeName ($employeeCode)');
    }
  }

  /// Stops the persistent background tracking service when employee checks out.
  Future<void> stop() async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefBgTrackingActive, false);
    await prefs.setDouble(_kPrefBgTrackingCumDist, 0.0);

    final service = FlutterBackgroundService();
    service.invoke('stopService');
    secureLog('[BackgroundTracking] Persistent background service STOPPED');
  }
}

/// Standalone Background Service Entry Point
/// Runs in an independent background isolate decoupled from the UI Activity.
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Initialize Supabase in background isolate
  try {
    if (!Supabase.instance.isInitialized) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
      );
    }
  } catch (e) {
    // Already initialized
  }

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((_) async {
    await service.stopSelf();
  });

  // Read session parameters from disk
  final prefs = await SharedPreferences.getInstance();
  final empId = prefs.getString(_kPrefBgTrackingEmpId) ?? '';
  final orgId = prefs.getString(_kPrefBgTrackingOrgId) ?? '0c621892-e938-4707-9957-13534ea32c19';
  final empName = prefs.getString(_kPrefBgTrackingEmpName) ?? 'Employee';
  final empCode = prefs.getString(_kPrefBgTrackingEmpCode) ?? '';
  double cumulativeDistanceMeters = prefs.getDouble(_kPrefBgTrackingCumDist) ?? 0.0;

  if (empId.isEmpty) {
    await service.stopSelf();
    return;
  }

  Position? lastFix;
  final battery = Battery();

  // Helper function to sync a GPS fix to Supabase
  Future<void> recordFix(Position pos, {bool isHeartbeat = false}) async {
    if (empId.isEmpty) return;

    double displacement = 0.0;
    if (lastFix != null) {
      displacement = Geolocator.distanceBetween(
        lastFix!.latitude,
        lastFix!.longitude,
        pos.latitude,
        pos.longitude,
      );
    }

    final speedKmh = pos.speed > 0 ? (pos.speed * 3.6) : 0.0;
    final isMoving = displacement >= 20.0 || speedKmh >= 2.5;

    if (isMoving && displacement >= 20.0 && displacement < 2500.0) {
      cumulativeDistanceMeters += displacement;
      await prefs.setDouble(_kPrefBgTrackingCumDist, cumulativeDistanceMeters);
    }

    lastFix = pos;

    // Read real battery level
    int? batteryLevel;
    try {
      batteryLevel = await battery.batteryLevel;
    } catch (_) {}

    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final supabase = Supabase.instance.client;

    // 1. Update live radar location
    try {
      await supabase.from('employee_live_locations').upsert({
        'organization_id': orgId,
        'employee_id': empId,
        'employee_name': empName,
        'employee_code': empCode,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'speed': speedKmh,
        'battery_level': batteryLevel,
        'is_moving': isMoving,
        'status': isMoving ? 'moving' : 'on_duty',
        'cumulative_distance_meters': cumulativeDistanceMeters,
        'last_pinged_at': nowUtc,
        'updated_at': nowUtc,
      }, onConflict: 'organization_id,employee_id');
    } catch (_) {}

    // 2. Insert into breadcrumb trail if moving or initial fix
    if (isMoving && displacement >= 20.0) {
      try {
        await supabase.from('employee_location_trails').insert({
          'organization_id': orgId,
          'employee_id': empId,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracy': pos.accuracy,
          'speed': speedKmh,
          'battery_level': batteryLevel,
          'displacement_meters': displacement,
          'cumulative_distance_meters': cumulativeDistanceMeters,
          'recorded_at': nowUtc,
          'metadata': {
            'source': 'persistent_background_service',
            'is_moving': isMoving,
          },
        });
      } catch (_) {}
    }

    // 3. Update Android Foreground Notification text
    if (service is AndroidServiceInstance) {
      final kmStr = (cumulativeDistanceMeters / 1000).toStringAsFixed(1);
      final speedText = isMoving ? '${speedKmh.round()} km/h' : 'Stationary';
      service.setForegroundNotificationInfo(
        title: 'JOY PeopleHR • Shift Active ($empCode)',
        content: 'Distance: $kmStr km • $speedText • GPS Active',
      );
    }
  }

  // Initial position fix upon background startup
  try {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    await recordFix(pos, isHeartbeat: true);
  } catch (_) {}

  // 1. Listen to real GPS stream with 20m displacement filter
  StreamSubscription<Position>? posStream;
  try {
    late final LocationSettings locSettings;
    if (Platform.isAndroid) {
      locSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 20,
        intervalDuration: const Duration(seconds: 15),
      );
    } else {
      locSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      );
    }

    posStream = Geolocator.getPositionStream(locationSettings: locSettings).listen(
      (pos) => recordFix(pos),
      onError: (_) {},
    );
  } catch (_) {}

  // 2. Periodic 5-minute stationary heartbeat timer
  final heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await recordFix(pos, isHeartbeat: true);
    } catch (_) {}
  });

  service.on('stopService').listen((_) {
    posStream?.cancel();
    heartbeatTimer.cancel();
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}
