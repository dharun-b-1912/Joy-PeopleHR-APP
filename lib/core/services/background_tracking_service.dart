// Joy PeopleHR — Enterprise Background GPS Tracking Service Bridge
// ============================================================================
// Provides a clean, stable interface for background shift tracking state.
// Relies on GeolocatorLocationService (official Android Location Service)
// rather than unapproved background isolates to prevent Android 14+ (API 34-36)
// ForegroundServiceStartNotAllowedException and Low Memory Killer crashes.
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Initializes the background service state.
  /// Called during app boot.
  Future<void> initialize() async {
    if (_isConfigured || kIsWeb) return;
    _isConfigured = true;
    secureLog('[BackgroundTracking] Background tracking state initialized safely (Native Geolocator Bridge)');
  }

  /// Records active shift tracking parameters.
  Future<void> start({
    required String employeeId,
    required String organizationId,
    required String employeeName,
    required String employeeCode,
  }) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefBgTrackingActive, true);
      await prefs.setString(_kPrefBgTrackingEmpId, employeeId);
      await prefs.setString(_kPrefBgTrackingOrgId, organizationId);
      await prefs.setString(_kPrefBgTrackingEmpName, employeeName);
      await prefs.setString(_kPrefBgTrackingEmpCode, employeeCode);
      secureLog('[BackgroundTracking] Active tracking state stored for $employeeName ($employeeCode)');
    } catch (e) {
      secureLog('[BackgroundTracking] start notice: $e');
    }
  }

  /// Clears active tracking state on employee checkout.
  Future<void> stop() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefBgTrackingActive, false);
      await prefs.setDouble(_kPrefBgTrackingCumDist, 0.0);
      secureLog('[BackgroundTracking] Active tracking state stopped');
    } catch (e) {
      secureLog('[BackgroundTracking] stop notice: $e');
    }
  }
}
