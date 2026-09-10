import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/hrms_models.dart';
import '../utils/secure_log.dart';
import 'user_service.dart';

/// Authoritative Attendance & GPS State Machine Enum
enum AttendanceGpsState {
  initializing,
  requestingPermission,
  locationDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  scanning,
  lowAccuracy,
  outsideRadius,
  insideRadius,
  checkingIn,
  checkedIn,
  checkingOut,
  checkedOut,
  gpsError,
  offline,
  reconnecting,
}

/// Rich Result Model representing live location telemetry & geofence evaluation
class UserLocationResult {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double distanceMeters;
  final bool isInside;
  final ApprovedWorkLocation? targetLocation;
  final AttendanceGpsState state;
  final String? errorMessage;
  final DateTime timestamp;
  final bool isMock;

  const UserLocationResult({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters = 0.0,
    required this.distanceMeters,
    required this.isInside,
    this.targetLocation,
    required this.state,
    this.errorMessage,
    required this.timestamp,
    this.isMock = false,
  });

  /// Factory for initial locating state
  factory UserLocationResult.locating() => UserLocationResult(
        latitude: 0,
        longitude: 0,
        accuracyMeters: 0,
        distanceMeters: 0,
        isInside: false,
        state: AttendanceGpsState.scanning,
        timestamp: DateTime.now(),
      );

  /// Factory for error states
  factory UserLocationResult.error(String msg, {AttendanceGpsState state = AttendanceGpsState.gpsError}) =>
      UserLocationResult(
        latitude: 0,
        longitude: 0,
        accuracyMeters: 0,
        distanceMeters: 0,
        isInside: false,
        state: state,
        errorMessage: msg,
        timestamp: DateTime.now(),
      );

  /// Format distance for human-friendly UI display (e.g. 42m, 184m, 1.4 km)
  String get formattedDistance {
    if (state == AttendanceGpsState.scanning ||
        state == AttendanceGpsState.initializing ||
        (latitude == 0.0 && longitude == 0.0)) {
      return 'Locating...';
    }
    if (distanceMeters < 1) return '< 1m';
    if (distanceMeters < 1000) return '${distanceMeters.round()}m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  /// Format accuracy for human-friendly UI display (e.g. ±8m)
  String get formattedAccuracy => '±${accuracyMeters.round()}m';
}

/// Service handling automatic GPS monitoring, multi-location geofencing,
/// state transitions, and Supabase Realtime synchronization
class LocationService extends ChangeNotifier {
  static final LocationService instance = LocationService._internal();
  LocationService._internal();

  UserLocationResult _currentResult = UserLocationResult.locating();
  UserLocationResult get currentResult => _currentResult;

  List<ApprovedWorkLocation> _authorizedLocations = [];
  List<ApprovedWorkLocation> get authorizedLocations => List.unmodifiable(_authorizedLocations);

  bool _isAcquiring = false;
  bool get isAcquiring => _isAcquiring;

  StreamSubscription<Position>? _positionStreamSub;
  Timer? _periodicAdaptiveTimer;
  RealtimeChannel? _locationChannel;
  String? _subscribedOrgId;

  // State Transition Tracking
  AttendanceGpsState _previousState = AttendanceGpsState.initializing;
  AttendanceGpsState get previousState => _previousState;

  // Geofence Entry Stream / Callbacks
  final _geofenceEntryController = StreamController<ApprovedWorkLocation>.broadcast();
  Stream<ApprovedWorkLocation> get onGeofenceEntered => _geofenceEntryController.stream;

  DateTime? _lastGeofencePromptTime;
  String? _lastPromptedLocationId;

  /// Initializes the service and starts automatic tracking
  Future<void> initialize() async {
    UserService.instance.addListener(() {
      fetchAuthorizedLocations().then((_) => evaluateLiveLocation());
    });

    await fetchAuthorizedLocations();
    await evaluateLiveLocation();
    startAutomaticTracking();
  }

  /// Starts live background/foreground position stream with battery efficiency
  void startAutomaticTracking() {
    _positionStreamSub?.cancel();
    _periodicAdaptiveTimer?.cancel();

    // 1. Geolocator Distance-Filter Stream (only triggers when moving ≥ 8 meters)
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );

    try {
      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position pos) {
          _processPosition(pos);
        },
        onError: (err) {
          secureLog('[GPS Stream] Error: $err');
          _evaluateFallbackPosition();
        },
      );
    } catch (e) {
      secureLog('[GPS Stream] Init error: $e');
    }

    // 2. Adaptive periodic verification (every 25 seconds while app is foregrounded)
    _periodicAdaptiveTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      evaluateLiveLocation(silent: true);
    });
  }

  /// Pauses automatic tracking when app goes to background
  void pauseTracking() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _periodicAdaptiveTimer?.cancel();
    _periodicAdaptiveTimer = null;
  }

  /// Resumes automatic tracking when app comes back to foreground
  void resumeTracking() {
    startAutomaticTracking();
    evaluateLiveLocation();
  }

  /// Subscribes to Supabase Realtime changes for work_locations, assignments, and policies
  void _subscribeRealtime(String orgId) {
    if (_subscribedOrgId == orgId && _locationChannel != null) return;
    _locationChannel?.unsubscribe();

    try {
      _subscribedOrgId = orgId;
      _locationChannel = Supabase.instance.client
          .channel('gps-locations-$orgId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'work_locations',
            callback: (payload) {
              secureLog('[REALTIME GPS] work_locations changed -> updating geofence parameters');
              refreshLocationsAndEvaluate();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'employee_work_location_assignments',
            callback: (payload) {
              secureLog('[REALTIME GPS] employee_work_location_assignments changed -> updating employee assignments');
              refreshLocationsAndEvaluate();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'employee_work_locations',
            callback: (payload) {
              secureLog('[REALTIME GPS] employee_work_locations changed -> updating employee assignments');
              refreshLocationsAndEvaluate();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'attendance_location_policy',
            callback: (payload) {
              secureLog('[REALTIME GPS] attendance_location_policy changed -> re-evaluating');
              refreshLocationsAndEvaluate();
            },
          )
          .subscribe();
    } catch (e) {
      secureLog('[REALTIME GPS] Subscription notice: $e');
    }
  }

  /// Fetches authorized work locations dynamically from Supabase
  Future<List<ApprovedWorkLocation>> fetchAuthorizedLocations() async {
    final user = UserService.instance.currentUser;
    final orgId = user.companyId.isNotEmpty
        ? user.companyId
        : (user.organizationId?.isNotEmpty == true ? user.organizationId! : '');
    final empId = user.dataId.isNotEmpty ? user.dataId : user.employeeId;

    if (orgId.isNotEmpty) {
      _subscribeRealtime(orgId);
    }

    try {
      final client = Supabase.instance.client;

      // 1. Primary: Authoritative server-side RPC fn_get_my_assigned_work_locations
      try {
        final rpcResult = await client.rpc('fn_get_my_assigned_work_locations');
        if (rpcResult is List && rpcResult.isNotEmpty) {
          final mapped = rpcResult.map((item) {
            return ApprovedWorkLocation.fromJson(Map<String, dynamic>.from(item as Map));
          }).toList();

          final Map<String, ApprovedWorkLocation> unique = {};
          for (final loc in mapped) {
            final key = (loc.id != null && loc.id!.isNotEmpty) ? loc.id! : loc.name.trim().toLowerCase();
            if (!unique.containsKey(key)) {
              unique[key] = loc;
            } else if (loc.isPrimary && !unique[key]!.isPrimary) {
              unique[key] = loc;
            }
          }
          final deduplicated = unique.values.toList();
          deduplicated.sort((a, b) => (b.isPrimary ? 1 : 0).compareTo(a.isPrimary ? 1 : 0));

          if (deduplicated.isNotEmpty) {
            _authorizedLocations = deduplicated;
            secureLog('[GPS] Loaded ${deduplicated.length} location(s) from fn_get_my_assigned_work_locations');
            return _authorizedLocations;
          }
        }
      } catch (rpcErr) {
        secureLog('[GPS] fn_get_my_assigned_work_locations RPC notice: $rpcErr');
      }

      // 2. Secondary: Direct query on employee_work_location_assignments
      final candidateEmpIds = <String>{
        empId,
        user.dataId,
        user.employeeId,
        if (user.employeeUuid != null && user.employeeUuid!.isNotEmpty) user.employeeUuid!,
      }.where((s) => s.isNotEmpty).toList();

      if (candidateEmpIds.isNotEmpty) {
        for (final table in const ['employee_work_location_assignments', 'employee_work_locations']) {
          try {
            final assignedData = await client
                .from(table)
                .select('*')
                .inFilter('employee_id', candidateEmpIds);

            if (assignedData.isNotEmpty) {
              final locationIds = assignedData
                  .map((r) => r['work_location_id']?.toString() ?? r['location_id']?.toString())
                  .where((id) => id != null && id.isNotEmpty)
                  .cast<String>()
                  .toSet()
                  .toList();

              final locationMap = <String, Map<String, dynamic>>{};
              if (locationIds.isNotEmpty) {
                try {
                  final locs = await client.from('work_locations').select('*').inFilter('id', locationIds);
                  for (final l in locs) {
                    final m = Map<String, dynamic>.from(l as Map);
                    if (m['id'] != null) {
                      locationMap[m['id'].toString()] = m;
                    }
                  }
                } catch (e) {
                  secureLog('[LocationService] work_locations by ID fetch notice: $e');
                }
              }

              final mapped = assignedData.map((r) {
                final rowMap = Map<String, dynamic>.from(r as Map);
                final locId = rowMap['work_location_id']?.toString() ??
                    rowMap['location_id']?.toString() ??
                    rowMap['id']?.toString();
                final locData = (locId != null ? locationMap[locId] : null) ?? rowMap;
                final merged = Map<String, dynamic>.from(locData);
                merged['is_primary'] = rowMap['is_primary'] ?? false;
                return ApprovedWorkLocation.fromJson(merged);
              }).toList();

              final Map<String, ApprovedWorkLocation> unique = {};
              for (final loc in mapped) {
                final key = (loc.id != null && loc.id!.isNotEmpty)
                    ? loc.id!
                    : loc.name.trim().toLowerCase();
                if (!unique.containsKey(key)) {
                  unique[key] = loc;
                } else if (loc.isPrimary && !unique[key]!.isPrimary) {
                  unique[key] = loc;
                }
              }
              final deduplicated = unique.values.toList();
              deduplicated.sort((a, b) => (b.isPrimary ? 1 : 0).compareTo(a.isPrimary ? 1 : 0));

              if (deduplicated.isNotEmpty) {
                _authorizedLocations = deduplicated;
                secureLog('[GPS] Loaded ${deduplicated.length} location(s) from $table');
                return _authorizedLocations;
              }
            }
          } catch (assignErr) {
            secureLog('[GPS] $table query notice: $assignErr');
          }
        }
      }

      // 3. Tertiary: user.assignedLocations
      if (user.assignedLocations.isNotEmpty) {
        _authorizedLocations = List.from(user.assignedLocations);
        secureLog('[GPS] Loaded ${_authorizedLocations.length} location(s) from user.assignedLocations');
        return _authorizedLocations;
      }

      // 4. Default: Query active work_locations for current organization
      if (orgId.isNotEmpty) {
        try {
          final orgLocs = await client
              .from('work_locations')
              .select('*')
              .eq('is_active', true)
              .eq('organization_id', orgId);

          if (orgLocs.isNotEmpty) {
            _authorizedLocations = orgLocs
                .map((l) => ApprovedWorkLocation.fromJson(Map<String, dynamic>.from(l as Map)))
                .toList();
            secureLog('[GPS] Loaded ${_authorizedLocations.length} active org location(s)');
            return _authorizedLocations;
          }
        } catch (orgErr) {
          secureLog('[GPS] org work_locations query notice: $orgErr');
        }
      }

      _authorizedLocations = [];
    } catch (e) {
      secureLog('[GPS] Error fetching work locations: $e');
      _authorizedLocations = user.assignedLocations.isNotEmpty ? List.from(user.assignedLocations) : [];
    }

    return _authorizedLocations;
  }

  /// Full Refresh: Loads locations and evaluates live GPS
  Future<UserLocationResult> refreshLocationsAndEvaluate() async {
    final freshLocations = await fetchAuthorizedLocations();
    if (freshLocations.isNotEmpty) {
      final user = UserService.instance.currentUser;
      final primary = freshLocations.firstWhere(
        (l) => l.isPrimary,
        orElse: () => freshLocations.first,
      );
      final updatedUser = user.copyWith(
        approvedLocation: primary,
        assignedLocations: freshLocations,
      );
      UserService.instance.setUser(updatedUser);
    }
    return evaluateLiveLocation(silent: true);
  }

  /// Real Device GPS / Network Acquisition & Evaluation with fast resilient fallback
  Future<UserLocationResult> evaluateLiveLocation({bool silent = false}) async {
    if (_isAcquiring) return _currentResult;
    _isAcquiring = true;

    // Preserve existing valid coordinates instead of wiping to 0,0
    if (!silent && _currentResult.latitude == 0.0) {
      _currentResult = UserLocationResult.locating();
      notifyListeners();
    }

    try {
      // 1. Check if device location service (GPS hardware) is enabled
      bool serviceEnabled = true;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } catch (e) {
        secureLog('[GPS] isLocationServiceEnabled check notice: $e');
      }

      if (!serviceEnabled) {
        // Try requesting anyway or report disabled
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          _transitionTo(UserLocationResult.error(
            'Location services or permissions are disabled. Please enable GPS in device settings.',
            state: AttendanceGpsState.locationDisabled,
          ));
          _isAcquiring = false;
          return _currentResult;
        }
      }

      // 2. Check and request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _transitionTo(UserLocationResult.error(
            'Location permission is required for attendance clocking.',
            state: AttendanceGpsState.permissionDenied,
          ));
          _isAcquiring = false;
          return _currentResult;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _transitionTo(UserLocationResult.error(
          'Location permissions are permanently denied. Please enable them in App Settings.',
          state: AttendanceGpsState.permissionPermanentlyDenied,
        ));
        _isAcquiring = false;
        return _currentResult;
      }

      // 3. Acquire Real Fresh Device Position
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (posErr) {
        secureLog('[GPS] High accuracy timeout ($posErr), attempting standard accuracy');
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            ),
          );
        } catch (medErr) {
          secureLog('[GPS] Medium accuracy error ($medErr), attempting last known fix');
          try {
            position = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }
      }

      if (position == null || (position.latitude == 0.0 && position.longitude == 0.0)) {
        _transitionTo(UserLocationResult.error(
          'Unable to acquire device GPS signal. Please move to an open area and tap Re-scan GPS.',
          state: AttendanceGpsState.gpsError,
        ));
        _isAcquiring = false;
        return _currentResult;
      }

      _processPosition(position);
    } catch (e) {
      secureLog('[GPS] Position acquisition exception: $e');
      _transitionTo(UserLocationResult.error(
        'Unable to determine your location: ${e.toString().replaceAll('Exception:', '').trim()}',
        state: AttendanceGpsState.gpsError,
      ));
    } finally {
      _isAcquiring = false;
      notifyListeners();
    }

    return _currentResult;
  }

  /// Processes live position updates against authorized geofences
  void _processPosition(Position position) {
    if (position.latitude == 0.0 && position.longitude == 0.0) {
      _transitionTo(UserLocationResult.error(
        'Scanning GPS signal...',
        state: AttendanceGpsState.scanning,
      ));
      return;
    }

    if (_authorizedLocations.isEmpty) {
      fetchAuthorizedLocations();
    }

    final user = UserService.instance.currentUser;
    final List<ApprovedWorkLocation> locations;
    if (_authorizedLocations.isNotEmpty) {
      locations = _authorizedLocations;
    } else if (user.assignedLocations.isNotEmpty) {
      locations = user.assignedLocations;
    } else {
      locations = [user.approvedLocation];
    }

    final validLocations = locations.where((l) => l.latitude != 0.0 || l.longitude != 0.0).toList();

    ApprovedWorkLocation? insideLocation;
    ApprovedWorkLocation? nearestLocation;
    double minDistance = double.infinity;
    double insideDistance = 0.0;

    if (validLocations.isNotEmpty) {
      for (final loc in validLocations) {
        final dist = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          loc.latitude,
          loc.longitude,
        );

        final baseRadius = loc.allowedRadiusMeters > 0 ? loc.allowedRadiusMeters : 200.0;
        final accuracyMargin = (position.accuracy > 0 && position.accuracy < 250)
            ? (position.accuracy * 0.5)
            : 0.0;
        final effectiveRadius = baseRadius + accuracyMargin;

        if (dist <= effectiveRadius) {
          if (insideLocation == null || dist < insideDistance) {
            insideLocation = loc;
            insideDistance = dist;
          }
        }

        if (dist < minDistance) {
          minDistance = dist;
          nearestLocation = loc;
        }
      }
    }

    final primaryLocation = locations.firstWhere(
      (l) => l.isPrimary,
      orElse: () => locations.first,
    );

    final ApprovedWorkLocation target;
    final double targetDistance;
    final bool isInside;

    if (insideLocation != null) {
      // 1. Employee is physically inside an assigned workplace!
      target = insideLocation;
      targetDistance = insideDistance;
      isInside = true;
    } else if (nearestLocation != null) {
      // 2. Employee is closest to this assigned workplace
      target = nearestLocation;
      targetDistance = minDistance;
      final targetBaseRadius = target.allowedRadiusMeters > 0 ? target.allowedRadiusMeters : 200.0;
      final accuracyMargin = (position.accuracy > 0 && position.accuracy < 250)
          ? (position.accuracy * 0.5)
          : 0.0;
      isInside = minDistance <= (targetBaseRadius + accuracyMargin);
    } else {
      // 3. Fallback to primary location
      target = primaryLocation;
      targetDistance = 0.0;
      isInside = true; // Fallback without strict coordinates
    }

    final targetRadius = target.allowedRadiusMeters > 0 ? target.allowedRadiusMeters : 200.0;
    final isAccuracyTooLow = position.accuracy > (targetRadius * 2.0);

    AttendanceGpsState newState;
    if (isInside) {
      newState = isAccuracyTooLow ? AttendanceGpsState.lowAccuracy : AttendanceGpsState.insideRadius;
    } else {
      newState = AttendanceGpsState.outsideRadius;
    }

    final newResult = UserLocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      distanceMeters: targetDistance,
      isInside: isInside && !isAccuracyTooLow,
      targetLocation: target,
      state: newState,
      errorMessage: isAccuracyTooLow
          ? 'GPS accuracy (±${position.accuracy.toStringAsFixed(0)}m) is too low for geofence validation. Move to an open outdoor area.'
          : null,
      timestamp: position.timestamp,
      isMock: position.isMocked,
    );

    // Geofence Entry Transition Detection (OUTSIDE -> INSIDE)
    if (_previousState == AttendanceGpsState.outsideRadius && newState == AttendanceGpsState.insideRadius) {
      _handleGeofenceEntered(target);
    }

    _transitionTo(newResult);

    final ageSeconds = DateTime.now().difference(position.timestamp).inSeconds;
    secureLog(
      '\n================== GPS CHECK DIAGNOSTIC ==================\n'
      'employee_id: ${user.employeeId.isNotEmpty ? user.employeeId : user.dataId}\n'
      'organization_id: ${user.companyId.isNotEmpty ? user.companyId : (user.organizationId ?? "—")}\n'
      'selected_work_location_id: ${target.id}\n'
      'selected_work_location_name: ${target.name}\n'
      'configured: lat=${target.latitude.toStringAsFixed(7)}, lng=${target.longitude.toStringAsFixed(7)}, radius=${target.allowedRadiusMeters.round()}m\n'
      'device: lat=${position.latitude.toStringAsFixed(7)}, lng=${position.longitude.toStringAsFixed(7)}, accuracy=±${position.accuracy.round()}m\n'
      'gps_timestamp: ${position.timestamp.toIso8601String()} (age: ${ageSeconds}s)\n'
      'calculated_distance_meters: ${minDistance.toStringAsFixed(1)}m\n'
      'inside_radius: ${isInside && !isAccuracyTooLow}\n'
      'result_state: $newState\n'
      '==========================================================\n',
    );
  }

  /// Triggers smart geofence entered event with anti-spam cooldown
  void _handleGeofenceEntered(ApprovedWorkLocation target) {
    final now = DateTime.now();
    if (_lastGeofencePromptTime != null &&
        _lastPromptedLocationId == target.id &&
        now.difference(_lastGeofencePromptTime!).inMinutes < 5) {
      return; // Cooldown active to prevent repetitive prompts
    }

    _lastGeofencePromptTime = now;
    _lastPromptedLocationId = target.id;
    _geofenceEntryController.add(target);
    secureLog('[GEOFENCE] Entered authorized radius for ${target.name}');
  }

  void _evaluateFallbackPosition() async {
    try {
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        _processPosition(lastPos);
      }
    } catch (_) {}
  }

  void _transitionTo(UserLocationResult result) {
    _previousState = _currentResult.state;
    _currentResult = result;
    notifyListeners();
  }

  /// Opens System App Settings
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Opens Device Location Settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Cleanly unsubscribe realtime location channels on logout
  void unsubscribeRealtime() {
    _locationChannel?.unsubscribe();
    _locationChannel = null;
    _subscribedOrgId = null;
  }

  // ────────────────────────────────────────────────────────────────────────
  // CHECKOUT LOCATION VERIFICATION
  // ────────────────────────────────────────────────────────────────────────

  /// Evaluates WHERE the employee is checking out from.
  ///
  /// This is an ADDITIONAL verification layer — it does NOT block checkout.
  /// It classifies the location for audit purposes:
  ///   - assigned_location: Inside assigned work location geofence
  ///   - main_office: At company main/head office
  ///   - other_authorized: At another registered work location
  ///   - unauthorized: At an unknown location (reason required)
  ///   - gps_unavailable: Could not obtain GPS (reason required)
  ///
  /// Check-in remains strict (must be inside authorized geofence).
  Future<CheckoutLocationVerification> evaluateCheckoutLocation() async {
    // 1. Try to get a fresh GPS fix
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (posErr) {
      secureLog('[CHECKOUT-VERIFY] High accuracy timeout ($posErr), trying medium');
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } catch (medErr) {
        secureLog('[CHECKOUT-VERIFY] Medium accuracy error ($medErr), trying last known');
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }
    }

    // If no GPS at all → gps_unavailable
    if (position == null || (position.latitude == 0.0 && position.longitude == 0.0)) {
      secureLog('[CHECKOUT-VERIFY] No GPS signal available — classified as gps_unavailable');
      return const CheckoutLocationVerification(
        status: CheckoutLocationStatus.gpsUnavailable,
        locationName: 'GPS Unavailable',
        latitude: 0,
        longitude: 0,
        accuracyMeters: 0,
        distanceToNearestMeters: 0,
      );
    }

    // 2. Ensure we have authorized locations loaded
    if (_authorizedLocations.isEmpty) {
      await fetchAuthorizedLocations();
    }

    final locations = _authorizedLocations.isNotEmpty
        ? _authorizedLocations
        : [UserService.instance.currentUser.approvedLocation];

    final validLocations = locations.where((l) => l.latitude != 0.0 || l.longitude != 0.0).toList();

    // 3. Calculate distance to each authorized location
    ApprovedWorkLocation? nearestLocation;
    double minDistance = double.infinity;

    for (final loc in validLocations) {
      final dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        loc.latitude,
        loc.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearestLocation = loc;
      }
    }

    // Also check if employee's profile-approved location is different from the list
    final profileLocation = UserService.instance.currentUser.approvedLocation;
    if (profileLocation.latitude != 0.0 || profileLocation.longitude != 0.0) {
      final profileDist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        profileLocation.latitude,
        profileLocation.longitude,
      );
      if (profileDist < minDistance) {
        minDistance = profileDist;
        nearestLocation = profileLocation;
      }
    }

    // 4. Classify the location
    if (nearestLocation == null || minDistance.isInfinite) {
      // No locations to compare against — treat as unauthorized
      secureLog('[CHECKOUT-VERIFY] No authorized locations available — classified as unauthorized');
      return CheckoutLocationVerification(
        status: CheckoutLocationStatus.unauthorized,
        locationName: 'Unknown Location',
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        distanceToNearestMeters: 0,
      );
    }

    final targetRadius = nearestLocation.allowedRadiusMeters;
    final hasRadius = targetRadius > 0;
    final isInsideAssigned = hasRadius ? minDistance <= targetRadius : minDistance <= 100;

    // Check if this is a main/head office
    final isMainOffice = _isMainOffice(nearestLocation);

    if (isInsideAssigned) {
      // Employee is inside the nearest authorized location's geofence
      if (isMainOffice) {
        // Also check if this is their PRIMARY assigned location
        if (nearestLocation.isPrimary) {
          secureLog('[CHECKOUT-VERIFY] Inside assigned location (primary) → assigned_location');
          return CheckoutLocationVerification(
            status: CheckoutLocationStatus.assignedLocation,
            locationName: nearestLocation.name,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            distanceToNearestMeters: minDistance,
            matchedLocation: nearestLocation,
          );
        } else {
          secureLog('[CHECKOUT-VERIFY] Inside main office (not primary) → main_office');
          return CheckoutLocationVerification(
            status: CheckoutLocationStatus.mainOffice,
            locationName: nearestLocation.name,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            distanceToNearestMeters: minDistance,
            matchedLocation: nearestLocation,
          );
        }
      } else {
        // Not main office — check if it's their primary assigned location
        if (nearestLocation.isPrimary) {
          secureLog('[CHECKOUT-VERIFY] Inside assigned location → assigned_location');
          return CheckoutLocationVerification(
            status: CheckoutLocationStatus.assignedLocation,
            locationName: nearestLocation.name,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            distanceToNearestMeters: minDistance,
            matchedLocation: nearestLocation,
          );
        } else {
          // Inside another authorized location (not primary)
          secureLog('[CHECKOUT-VERIFY] Inside other authorized location → other_authorized');
          return CheckoutLocationVerification(
            status: CheckoutLocationStatus.otherAuthorized,
            locationName: nearestLocation.name,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            distanceToNearestMeters: minDistance,
            matchedLocation: nearestLocation,
          );
        }
      }
    }

    // 5. Employee is OUTSIDE all authorized geofences
    // Check if they're reasonably close to any location (within 500m) but outside geofence
    if (minDistance <= 500 && nearestLocation.allowedRadiusMeters > 0) {
      // Close to a location but outside geofence — still classify as that location
      // with a note that they're slightly outside
      if (isMainOffice) {
        secureLog('[CHECKOUT-VERIFY] Near main office but outside geofence (${minDistance.round()}m) → main_office');
        return CheckoutLocationVerification(
          status: CheckoutLocationStatus.mainOffice,
          locationName: '${nearestLocation.name} (outside geofence)',
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          distanceToNearestMeters: minDistance,
          matchedLocation: nearestLocation,
        );
      } else if (nearestLocation.isPrimary) {
        secureLog('[CHECKOUT-VERIFY] Near assigned location but outside geofence → assigned_location');
        return CheckoutLocationVerification(
          status: CheckoutLocationStatus.assignedLocation,
          locationName: '${nearestLocation.name} (outside geofence)',
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          distanceToNearestMeters: minDistance,
          matchedLocation: nearestLocation,
        );
      } else {
        secureLog('[CHECKOUT-VERIFY] Near other authorized location but outside geofence → other_authorized');
        return CheckoutLocationVerification(
          status: CheckoutLocationStatus.otherAuthorized,
          locationName: '${nearestLocation.name} (outside geofence)',
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          distanceToNearestMeters: minDistance,
          matchedLocation: nearestLocation,
        );
      }
    }

    // 6. Truly unknown location — far from all authorized locations
    secureLog('[CHECKOUT-VERIFY] Unknown location (${minDistance.round()}m from nearest) → unauthorized');
    return CheckoutLocationVerification(
      status: CheckoutLocationStatus.unauthorized,
      locationName: 'Unknown Location',
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      distanceToNearestMeters: minDistance,
    );
  }

  /// Determines if a work location is the main/head office.
  /// Checks: location_type, name keywords, and whether it's flagged as headquarters.
  bool _isMainOffice(ApprovedWorkLocation location) {
    final type = (location.locationType ?? '').toUpperCase();
    final name = location.name.toLowerCase();

    // Check location_type field
    if (type == 'HEAD_OFFICE' || type == 'HEADQUARTERS' || type == 'MAIN_OFFICE' || type == 'HQ') {
      return true;
    }

    // Check name for common main office keywords
    if (name.contains('head office') || name.contains('headquarters') ||
        name.contains('main office') || name.contains('corporate') ||
        name.contains(' hq') || name.contains('hq ')) {
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _periodicAdaptiveTimer?.cancel();
    _geofenceEntryController.close();
    _locationChannel?.unsubscribe();
    super.dispose();
  }
}
