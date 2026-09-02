import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/hrms_models.dart';
import 'package:workforce_os/core/services/shift_duration_calculator.dart';
import 'package:workforce_os/core/services/employee_profile_mapper.dart';

void main() {
  group('Multi-Tenant Data Independence Tests', () {
    test('Company A Employee Profile is completely dynamic and isolated', () {
      final compAUser = EmployeeProfileMapper.fromEmployeesRow(
        {
          'id': 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
          'employee_code': 'CORP-A-101',
          'first_name': 'Alice',
          'last_name': 'Smith',
          'display_name': 'Alice Smith',
          'work_email': 'alice@company-a.com',
          'status': 'ACTIVE',
          'employment_type': 'FULL_TIME',
          'company_name': 'Company A Technologies',
          'designation': 'HR Lead',
          'department': 'People Operations',
          'branch_name': 'Mumbai Regional Office',
        },
      );

      expect(compAUser.name, 'Alice Smith');
      expect(compAUser.employeeId, 'CORP-A-101');
      expect(compAUser.dataId, 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d');
      expect(compAUser.companyName, 'Company A Technologies');
      expect(compAUser.department, 'People Operations');
      expect(compAUser.designation, 'HR Lead');
    });

    test('Company B Employee Profile is completely dynamic and isolated', () {
      final compBUser = EmployeeProfileMapper.fromEmployeesRow(
        {
          'id': 'f9e8d7c6-b5a4-3210-fedc-ba9876543210',
          'employee_code': 'CORP-B-999',
          'first_name': 'Rahul',
          'last_name': 'Verma',
          'display_name': 'Rahul Verma',
          'work_email': 'rahul@company-b.org',
          'status': 'ACTIVE',
          'employment_type': 'CONTRACT',
          'company_name': 'Company B Logistics',
          'designation': 'Supply Chain Director',
          'department': 'Logistics & Fleet',
          'branch_name': 'Bengaluru Hub',
        },
      );

      expect(compBUser.name, 'Rahul Verma');
      expect(compBUser.employeeId, 'CORP-B-999');
      expect(compBUser.dataId, 'f9e8d7c6-b5a4-3210-fedc-ba9876543210');
      expect(compBUser.companyName, 'Company B Logistics');
      expect(compBUser.department, 'Logistics & Fleet');
      expect(compBUser.designation, 'Supply Chain Director');
    });

    test('Shift Roster dynamic computation operates correctly for any tenant shift hours', () {
      final morningShift = ShiftDurationCalculator.instance.calculate(
        startTime: '06:00 AM',
        endTime: '02:30 PM',
      );
      expect(morningShift.spanMinutes, 510);
      expect(morningShift.scheduledWorkMinutes, 480);
      expect(morningShift.crossesMidnight, false);

      final nightShift = ShiftDurationCalculator.instance.calculate(
        startTime: '10:00 PM',
        endTime: '06:00 AM',
      );
      expect(nightShift.spanMinutes, 480);
      expect(nightShift.crossesMidnight, true);
    });

    test('ApprovedWorkLocation multi-location parsing has zero hardcoded coordinates', () {
      final loc1 = ApprovedWorkLocation.fromJson({
        'id': 'loc-1',
        'location_name': 'Noida Development Center',
        'latitude': 28.5355,
        'longitude': 77.3910,
        'allowed_radius_meters': 150,
      });

      final loc2 = ApprovedWorkLocation.fromJson({
        'id': 'loc-2',
        'location_name': 'Pune Plant 4',
        'latitude': 18.5204,
        'longitude': 73.8567,
        'allowed_radius_meters': 300,
      });

      expect(loc1.name, 'Noida Development Center');
      expect(loc1.latitude, 28.5355);
      expect(loc2.name, 'Pune Plant 4');
      expect(loc2.allowedRadiusMeters, 300);
    });
  });
}
