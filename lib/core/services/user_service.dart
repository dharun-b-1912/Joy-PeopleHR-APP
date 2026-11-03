import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/hrms_models.dart';
import '../utils/secure_log.dart';
import 'crash_reporting_service.dart';
import 'employee_realtime_service.dart';
import 'location_service.dart';
import 'notification_realtime_service.dart';

class UserService extends ChangeNotifier {
  static final UserService instance = UserService._internal();
  UserService._internal();

  static const String _kCachedUserKey = 'sp_cached_user_model_v1';
  static const String _kIsLoggedInKey = 'sp_is_logged_in_v1';
  static const String _kAuthEmailKey = 'sp_auth_email_v1';
  static const String _kEmployeeUuidKey = 'sp_employee_uuid_v1';

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  /// Neutral placeholder used while logged out — never exposes dummy data.
  static const UserModel _guestUser = UserModel(
    name: 'Guest',
    firstName: 'Guest',
    employeeId: '',
    designation: '',
    department: '',
    role: 'EMPLOYEE',
    machinePin: '',
    campus: '',
    approvedLocation: ApprovedWorkLocation(
      name: 'Office',
      latitude: 0,
      longitude: 0,
      allowedRadiusMeters: 100,
    ),
    shiftStart: '09:30 AM',
    shiftEnd: '06:30 PM',
    leaveBalanceDays: 0,
    employmentType: 'Full Time',
    personalEmail: '',
    contactNumber: '',
    address: '',
  );

  UserModel _currentUser = _guestUser;
  UserModel get currentUser => _currentUser;
  List<UserModel> get availableUsers => _isLoggedIn ? [_currentUser] : [];

  /// Fail-safe local filesystem file path for indestructible session persistence
  Future<File?> _getLocalSessionFile() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/user_session_v2.json');
    } catch (_) {
      return null;
    }
  }

  /// Checks whether a valid persistent login flag is stored on this device
  Future<bool> isSessionPersisted() async {
    if (_isLoggedIn && _currentUser.name.isNotEmpty && _currentUser.name != 'Guest') {
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCachedUserKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final flag = prefs.getBool(_kIsLoggedInKey) ?? false;
        if (!flag) {
          await prefs.setBool(_kIsLoggedInKey, true);
        }
        return true;
      }
      final flag = prefs.getBool(_kIsLoggedInKey) ?? false;
      if (flag) return true;

      // Fail-safe: check filesystem backup file
      final file = await _getLocalSessionFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Restores user profile instantly from local device storage without waiting for network
  Future<UserModel?> loadCachedUser() async {
    // If already in-memory, return immediately
    if (_isLoggedIn && _currentUser.name.isNotEmpty && _currentUser.name != 'Guest') {
      return _currentUser;
    }

    // 1. Primary storage: SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final isFlagged = prefs.getBool(_kIsLoggedInKey) ?? false;
      final rawJson = prefs.getString(_kCachedUserKey);
      if (rawJson != null && rawJson.trim().isNotEmpty) {
        final map = jsonDecode(rawJson) as Map<String, dynamic>;
        final user = UserModel.fromJson(map);
        final isValidEmp = user.name.isNotEmpty && user.name != 'Guest';
        if (isValidEmp) {
          _currentUser = user;
          _isLoggedIn = true;
          if (!isFlagged) {
            await prefs.setBool(_kIsLoggedInKey, true);
          }
          // Self-heal filesystem backup if missing
          try {
            final file = await _getLocalSessionFile();
            if (file != null && (!await file.exists() || (await file.length()) == 0)) {
              await file.writeAsString(rawJson, flush: true);
            }
          } catch (_) {}

          notifyListeners();
          secureLog('[UserService] Restored cached session from SharedPreferences: ${user.name} (${user.employeeId}) [persistedFlag=$isFlagged]');
          return user;
        }
      }
    } catch (e, st) {
      secureLog('[UserService] Notice reading SharedPreferences: $e\n$st');
    }

    // 2. Secondary fail-safe storage: Local filesystem session file
    try {
      final file = await _getLocalSessionFile();
      if (file != null && await file.exists()) {
        final rawJson = await file.readAsString();
        if (rawJson.trim().isNotEmpty) {
          final map = jsonDecode(rawJson) as Map<String, dynamic>;
          final user = UserModel.fromJson(map);
          final isValidEmp = user.name.isNotEmpty && user.name != 'Guest';
          if (isValidEmp) {
            _currentUser = user;
            _isLoggedIn = true;

            // Self-heal SharedPreferences
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_kCachedUserKey, rawJson);
              await prefs.setBool(_kIsLoggedInKey, true);
            } catch (_) {}

            notifyListeners();
            secureLog('[UserService] Restored cached session from filesystem backup: ${user.name} (${user.employeeId})');
            return user;
          }
        }
      }
    } catch (e, st) {
      secureLog('[UserService] Notice reading filesystem backup session: $e\n$st');
    }

    return null;
  }

  /// Explicitly write UserModel to device disk storage (both SharedPreferences + atomic file)
  Future<void> persistUser(UserModel newUser) async {
    // Strict Guard: Never persist a Guest / dummy user model
    if (newUser.name == 'Guest' || newUser.name.trim().isEmpty) {
      secureLog('[UserService] Refusing to persist empty or Guest user model');
      return;
    }

    try {
      final userJson = jsonEncode(newUser.toJson());

      // 1. Commit to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedUserKey, userJson);
      await prefs.setBool(_kIsLoggedInKey, true);
      if (newUser.officeEmail != null && newUser.officeEmail!.isNotEmpty) {
        await prefs.setString(_kAuthEmailKey, newUser.officeEmail!);
      } else if (newUser.personalEmail.isNotEmpty) {
        await prefs.setString(_kAuthEmailKey, newUser.personalEmail);
      }
      if (newUser.employeeUuid != null && newUser.employeeUuid!.isNotEmpty) {
        await prefs.setString(_kEmployeeUuidKey, newUser.employeeUuid!);
      }

      // 2. Commit atomic flush to persistent local file on device
      try {
        final file = await _getLocalSessionFile();
        if (file != null) {
          await file.writeAsString(userJson, flush: true);
        }
      } catch (fileErr) {
        secureLog('[UserService] Notice persisting file backup: $fileErr');
      }

      secureLog('[UserService] Successfully persisted user ${newUser.name} (${newUser.employeeId}) to redundant disk storage (jsonLen=${userJson.length})');
    } catch (e, st) {
      secureLog('[UserService] Failed to persist user model to storage: $e\n$st');
    }
  }

  void setUser(UserModel newUser) {
    final previousId = _isLoggedIn ? _currentUser.dataId : null;
    _currentUser = newUser;
    _isLoggedIn = true;

    if (previousId != newUser.dataId) {
      logProcess(
        'SESSION',
        'Active employee session -> ${newUser.name} (${newUser.employeeId})',
      );
    }

    notifyListeners();

    // Persist to local disk storage
    persistUser(newUser);

    // Track user in Crashlytics for error reports
    CrashReportingService.instance.setUser(
      userId: newUser.dataId,
      email: newUser.officeEmail ?? newUser.personalEmail,
      name: newUser.name,
    );
    CrashReportingService.instance.setCustomKey('employee_code', newUser.employeeId);
    CrashReportingService.instance.setCustomKey('department', newUser.department);
    CrashReportingService.instance.setCustomKey('role', newUser.role);

    // Automatically initialize/subscribe to real-time channels when logged in
    if (newUser.dataId.isNotEmpty && previousId != newUser.dataId) {
      EmployeeRealtimeService.instance.subscribe(
        newUser.dataId,
        authEmail: newUser.officeEmail ?? newUser.personalEmail,
      );
      NotificationRealtimeService.instance.subscribe(newUser.dataId);
      LocationService.instance.refreshLocationsAndEvaluate();
    }
  }

  Future<void> clearUser() async {
    final wasLoggedIn = _isLoggedIn;
    final prevName = _currentUser.name;
    final prevCode = _currentUser.employeeId;
    _currentUser = _guestUser;
    _isLoggedIn = false;

    // Clean up local disk storage (both SharedPreferences and filesystem backup)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsLoggedInKey, false);
      await prefs.remove(_kCachedUserKey);
      await prefs.remove(_kAuthEmailKey);
      await prefs.remove(_kEmployeeUuidKey);

      final file = await _getLocalSessionFile();
      if (file != null && await file.exists()) {
        await file.delete();
      }
      secureLog('[UserService] Cleared persistent user storage from all layers');
    } catch (_) {}

    if (wasLoggedIn) {
      logSessionBanner(
        event: 'USER SESSION CLEARED (prev: $prevName [$prevCode])',
        isLoggedIn: false,
      );
      // Clear Crashlytics user identity
      CrashReportingService.instance.clearUser();

      // Cleanly remove all real-time channels on logout
      EmployeeRealtimeService.instance.unsubscribe();
      NotificationRealtimeService.instance.unsubscribe();
      LocationService.instance.unsubscribeRealtime();
    }

    notifyListeners();
  }

  void switchUser(UserModel newUser) {
    setUser(newUser);
  }

  void updateProfileImage(String imagePath) {
    if (_currentUser.profileImage == imagePath) {
      return; // Prevent flickering loop
    }

    _currentUser = _currentUser.copyWith(profileImage: imagePath);
    notifyListeners();
  }

  void updateEmergencyContact(EmergencyContactModel newContact) {
    _currentUser = _currentUser.copyWith(emergencyContact: newContact);
    notifyListeners();
  }
}
