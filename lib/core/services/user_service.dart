import 'package:flutter/material.dart';
import '../../models/hrms_models.dart';
import 'crash_reporting_service.dart';
import 'employee_realtime_service.dart';
import 'location_service.dart';
import 'notification_realtime_service.dart';

class UserService extends ChangeNotifier {
  static final UserService instance = UserService._internal();
  UserService._internal();

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

  void setUser(UserModel newUser) {
    final previousId = _isLoggedIn ? _currentUser.dataId : null;
    _currentUser = newUser;
    _isLoggedIn = true;
    notifyListeners();

    // Track user in Crashlytics for error reports
    CrashReportingService.instance.setUser(
      userId: newUser.dataId,
      email: newUser.officeEmail ?? newUser.personalEmail,
      name: newUser.name,
    );
    CrashReportingService.instance.setCustomKey('employee_code', newUser.employeeId);
    CrashReportingService.instance.setCustomKey('department', newUser.department);
    CrashReportingService.instance.setCustomKey('role', newUser.role);

    // Automatically initialize/subscribe to real-time profile updates if switching or newly logged in
    if (newUser.dataId.isNotEmpty && previousId != newUser.dataId) {
      EmployeeRealtimeService.instance.subscribe(
        newUser.dataId,
        authEmail: newUser.officeEmail ?? newUser.personalEmail,
      );
    }
  }

  void clearUser() {
    _currentUser = _guestUser;
    _isLoggedIn = false;
    notifyListeners();

    // Clear Crashlytics user identity
    CrashReportingService.instance.clearUser();

    // Cleanly remove all real-time channels on logout
    EmployeeRealtimeService.instance.unsubscribe();
    NotificationRealtimeService.instance.unsubscribe();
    LocationService.instance.unsubscribeRealtime();
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
