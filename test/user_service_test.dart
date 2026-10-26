import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce_os/models/hrms_models.dart';
import 'package:workforce_os/core/services/user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserService Session Persistence Tests', () {
    test('Persists and restores UserModel correctly via SharedPreferences', () async {
      const testUser = UserModel(
        name: 'Dharun B',
        firstName: 'Dharun',
        employeeId: 'JCS-017',
        employeeUuid: '298c50e2-8255-4673-b67d-d421e42eaec3',
        designation: 'Digital Marketing Specialist',
        department: 'Digital Marketing',
        role: 'EMPLOYEE',
        machinePin: '1234',
        campus: 'Coimbatore HQ',
        approvedLocation: ApprovedWorkLocation(
          name: 'Joy Corporate Solutions',
          latitude: 11.08444,
          longitude: 77.12625,
          allowedRadiusMeters: 100,
        ),
        shiftStart: '09:30 AM',
        shiftEnd: '06:30 PM',
        leaveBalanceDays: 12.5,
        companyId: 'd6b7b209-1e16-43b9-a4bc-6fefad09528f',
        officeEmail: 'dharun@joyglobalcorp.com',
      );

      final userService = UserService.instance;
      await userService.persistUser(testUser);

      // Verify SharedPreferences content
      final prefs = await SharedPreferences.getInstance();
      final isLoggedInFlag = prefs.getBool('sp_is_logged_in_v1');
      final rawCached = prefs.getString('sp_cached_user_model_v1');

      expect(isLoggedInFlag, true);
      expect(rawCached, isNotNull);
      expect(rawCached!.isNotEmpty, true);

      // Clear memory state to simulate cold app launch
      await userService.clearUser();
      expect(userService.isLoggedIn, false);

      // Re-populate mock storage to simulate persistent disk after process restart
      SharedPreferences.setMockInitialValues({
        'sp_is_logged_in_v1': true,
        'sp_cached_user_model_v1': rawCached,
      });

      final restored = await userService.loadCachedUser();
      expect(restored, isNotNull);
      expect(restored!.name, 'Dharun B');
      expect(restored.employeeId, 'JCS-017');
      expect(userService.isLoggedIn, true);
      expect(await userService.isSessionPersisted(), true);
    });

    test('Refuses to persist Guest user', () async {
      final userService = UserService.instance;
      const guest = UserModel(
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
      );

      await userService.persistUser(guest);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sp_is_logged_in_v1'), isNull);
      expect(prefs.getString('sp_cached_user_model_v1'), isNull);
    });
  });
}
