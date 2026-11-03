import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce_os/models/hrms_models.dart';
import 'package:workforce_os/core/services/user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('Session lifecycle: Once employee logs in, closing and killing app preserves session 100%', () async {
    const employee = UserModel(
      name: 'Ravi Kumar',
      firstName: 'Ravi',
      employeeId: 'EMP-1002',
      employeeUuid: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      designation: 'Operations Lead',
      department: 'Factory Operations',
      role: 'EMPLOYEE',
      machinePin: '9988',
      campus: 'Joy Factory Unit 1',
      approvedLocation: ApprovedWorkLocation(
        name: 'Factory Campus',
        latitude: 11.0844,
        longitude: 77.1262,
        allowedRadiusMeters: 200,
      ),
      shiftStart: '08:30 AM',
      shiftEnd: '05:30 PM',
      leaveBalanceDays: 15,
      companyId: 'org-factory-1',
      officeEmail: 'ravi.kumar@factory.com',
    );

    // 1. Employee logs in and persists session
    final userService = UserService.instance;
    await userService.persistUser(employee);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sp_is_logged_in_v1'), isTrue);
    expect(prefs.getString('sp_cached_user_model_v1'), isNotNull);

    // 2. Simulate complete cold start / app kill by calling loadCachedUser
    final restored = await userService.loadCachedUser();
    expect(restored, isNotNull);
    expect(restored!.name, 'Ravi Kumar');
    expect(restored.employeeId, 'EMP-1002');
    expect(userService.isLoggedIn, isTrue);

    // 3. Verify isSessionPersisted returns true
    final isPersisted = await userService.isSessionPersisted();
    expect(isPersisted, isTrue);
  });
}

