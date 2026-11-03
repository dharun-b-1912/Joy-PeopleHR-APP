import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/hrms_models.dart';
import 'package:workforce_os/models/employee_models.dart';
import 'package:workforce_os/models/employee_relations_models.dart';
import 'package:workforce_os/core/utils/validators.dart';

void main() {
  group('Auth Flow Tests', () {
    test('Email validation accepts valid emails', () {
      expect(Validators.isValidEmail('user@example.com'), true);
      expect(Validators.isValidEmail('user.auth@domain.co.in'), true);
      expect(Validators.isValidEmail('test.user+tag@domain.co.in'), true);
    });

    test('Email validation rejects invalid emails', () {
      expect(Validators.isValidEmail(''), false);
      expect(Validators.isValidEmail('notanemail'), false);
      expect(Validators.isValidEmail('@domain.com'), false);
      expect(Validators.isValidEmail('user@'), false);
      expect(Validators.isValidEmail('user@.com'), false);
    });

    test('Phone validation accepts valid Indian phone numbers', () {
      expect(Validators.isValidPhone('9791817437'), true);
      expect(Validators.isValidPhone('+919791817437'), true);
      expect(Validators.isValidPhone('91 9791817437'), true);
      expect(Validators.isValidPhone('9791-817-437'), true);
    });

    test('Phone validation rejects invalid numbers', () {
      expect(Validators.isValidPhone(''), false);
      expect(Validators.isValidPhone('123'), false);
      expect(Validators.isValidPhone('abc'), false);
    });

    test('Filename sanitization prevents path traversal', () {
      expect(Validators.sanitizeFileName('../../../etc/passwd'), isNot(contains('..')));
      expect(Validators.sanitizeFileName('test\\file.txt'), isNot(contains('\\')));
      expect(Validators.sanitizeFileName('normal-file.pdf'), 'normal-file.pdf');
      expect(Validators.sanitizeFileName('file with spaces.txt'), 'file_with_spaces.txt');
    });

    test('UserModel resolves employee ID correctly', () {
      const user = UserModel(
        name: 'Test User',
        firstName: 'Test',
        employeeId: 'EMP-001',
        employeeUuid: 'EMP-617871',
        designation: 'Software Engineer',
        department: 'Engineering',
        role: 'EMPLOYEE',
        machinePin: '1234',
        campus: 'Chennai HQ',
        approvedLocation: ApprovedWorkLocation(
          name: 'Chennai HQ',
          latitude: 12.97,
          longitude: 80.25,
          allowedRadiusMeters: 200,
        ),
        shiftStart: '09:30 AM',
        shiftEnd: '06:30 PM',
        leaveBalanceDays: 15,
        companyId: 'org-joy-01',
      );

      // dataId should prefer employeeUuid
      expect(user.dataId, 'EMP-617871');
      expect(user.resolvedEmployeeId, 'EMP-617871');
      expect(user.tenantId, 'org-joy-01');
    });

    test('UserModel falls back to employeeId when no UUID', () {
      const user = UserModel(
        name: 'Test User',
        firstName: 'Test',
        employeeId: 'EMP-001',
        designation: 'Engineer',
        department: 'Engineering',
        role: 'EMPLOYEE',
        machinePin: '1234',
        campus: 'Chennai HQ',
        approvedLocation: ApprovedWorkLocation(
          name: 'Office',
          latitude: 0,
          longitude: 0,
          allowedRadiusMeters: 100,
        ),
        shiftStart: '09:30',
        shiftEnd: '18:30',
        leaveBalanceDays: 15,
      );

      expect(user.dataId, 'EMP-001');
    });

    test('UserModel copyWith preserves all fields', () {
      const original = UserModel(
        name: 'Original',
        firstName: 'Original',
        employeeId: 'JCS-001',
        employeeUuid: 'uuid-1',
        designation: 'Engineer',
        department: 'Eng',
        role: 'EMPLOYEE',
        machinePin: '1234',
        campus: 'HQ',
        approvedLocation: ApprovedWorkLocation(
          name: 'HQ',
          latitude: 12.0,
          longitude: 80.0,
          allowedRadiusMeters: 200,
        ),
        shiftStart: '09:30',
        shiftEnd: '18:30',
        leaveBalanceDays: 15,
        companyId: 'org-1',
      );

      final updated = original.copyWith(
        name: 'Updated',
        profileImage: 'https://example.com/photo.jpg',
      );

      expect(updated.name, 'Updated');
      expect(updated.employeeId, 'JCS-001'); // preserved
      expect(updated.employeeUuid, 'uuid-1'); // preserved
      expect(updated.profileImage, 'https://example.com/photo.jpg');
      expect(updated.companyId, 'org-1'); // preserved
    });
  });

  group('PayrollStatutoryModel Tests', () {
    test('Masked values contain bullet characters', () {
      const model = PayrollStatutoryModel(
        accountNumber: '•••• •••• 6789',
        rawAccountNumber: '50100123456789',
        panNumber: '•••• •••• 234F',
        rawPanNumber: 'ABCDE1234F',
      );

      expect(model.accountNumber!.contains('•'), true);
      expect(model.rawAccountNumber, '50100123456789');
      expect(model.panNumber!.contains('•'), true);
      expect(model.rawPanNumber, 'ABCDE1234F');
    });

    test('Empty model shows N/A defaults', () {
      const model = PayrollStatutoryModel(
        bankName: 'Not Available',
        accountNumber: 'Not Available',
        ifscCode: 'Not Available',
      );

      expect(model.bankName, 'Not Available');
      expect(model.rawAccountNumber, null);
    });
  });

  group('Leave Model Tests', () {
    test('LeaveBalanceModel.empty() returns zero balances', () {
      final empty = LeaveBalanceModel.empty();
      expect(empty.casualAvailable, 0);
      expect(empty.sickAvailable, 0);
      expect(empty.earnedAvailable, 0);
      expect(empty.items, isEmpty);
    });

    test('LeaveRequestModel preserves all fields', () {
      final request = LeaveRequestModel(
        id: 'lv-001',
        employeeId: 'EMP-001',
        type: LeaveType.casual,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 3),
        daysCount: 3,
        reason: 'Family function',
        status: LeaveStatus.pending,
        createdAt: DateTime.now(),
      );

      expect(request.id, 'lv-001');
      expect(request.type, LeaveType.casual);
      expect(request.daysCount, 3);
      expect(request.status, LeaveStatus.pending);
    });

    test('Leave request status transitions', () {
      final statuses = [
        LeaveStatus.pending,
        LeaveStatus.approved,
        LeaveStatus.rejected,
        LeaveStatus.cancelled,
      ];

      expect(statuses.length, 4);
      expect(statuses.contains(LeaveStatus.pending), true);
      expect(statuses.contains(LeaveStatus.approved), true);
    });
  });

  group('Attendance Model Tests', () {
    test('TimesheetEntryModel calculates regular and overtime minutes', () {
      final entry = TimesheetEntryModel(
        id: 'ts-001',
        date: DateTime(2026, 9, 1),
        clockInTime: '09:30 AM',
        clockOutTime: '07:00 PM',
        totalHours: '9h 30m',
        status: DayAttendanceStatus.present,
        netWorkingMinutes: 570, // 9h 30m
      );

      expect(entry.regularMinutes, 480); // capped at 8h
      expect(entry.overtimeMinutes, 90); // 1h 30m overtime
      expect(entry.formattedRegularHours, '8h 00m');
      expect(entry.formattedOvertimeHours, '1h 30m');
    });

    test('TimesheetEntryModel handles zero minutes', () {
      final entry = TimesheetEntryModel(
        id: 'ts-002',
        date: DateTime(2026, 9, 1),
        totalHours: '0h 00m',
        status: DayAttendanceStatus.absent,
        netWorkingMinutes: 0,
      );

      expect(entry.regularMinutes, 0);
      expect(entry.overtimeMinutes, 0);
      expect(entry.formattedRegularHours, '0h 00m');
    });

    test('TimesheetEntryModel handles negative minutes safely', () {
      final entry = TimesheetEntryModel(
        id: 'ts-003',
        date: DateTime(2026, 9, 1),
        totalHours: '0h 00m',
        status: DayAttendanceStatus.notPayable,
        netWorkingMinutes: -30,
      );

      expect(entry.regularMinutes, 0); // clamped to 0
      expect(entry.overtimeMinutes, 0);
    });

    test('DayAttendanceStatus covers all states', () {
      const allStatuses = DayAttendanceStatus.values;
      expect(allStatuses.length, 12);
      expect(allStatuses.contains(DayAttendanceStatus.present), true);
      expect(allStatuses.contains(DayAttendanceStatus.absent), true);
      expect(allStatuses.contains(DayAttendanceStatus.leave), true);
      expect(allStatuses.contains(DayAttendanceStatus.weekOff), true);
      expect(allStatuses.contains(DayAttendanceStatus.halfDay), true);
    });

    test('AttendanceSession tracks state correctly', () {
      const notCheckedIn = AttendanceSession(
        status: AttendanceStatus.notCheckedIn,
      );
      expect(notCheckedIn.isCheckedIn, false);
      expect(notCheckedIn.isCheckedOut, false);

      final checkedIn = AttendanceSession(
        status: AttendanceStatus.checkedIn,
        checkInTime: DateTime(2026, 9, 1, 9, 30),
      );
      expect(checkedIn.isCheckedIn, true);
      expect(checkedIn.isCheckedOut, false);

      final checkedOut = AttendanceSession(
        status: AttendanceStatus.checkedOut,
        checkInTime: DateTime(2026, 9, 1, 9, 30),
        checkOutTime: DateTime(2026, 9, 1, 18, 30),
        netWorkingMinutes: 540,
      );
      expect(checkedOut.isCheckedOut, true);
      expect(checkedOut.netWorkingMinutes, 540);
    });
  });

  group('Checkout Location Verification Tests', () {
    test('CheckoutLocationStatus has all states', () {
      expect(CheckoutLocationStatus.assignedLocation.value, 'assigned_location');
      expect(CheckoutLocationStatus.mainOffice.value, 'main_office');
      expect(CheckoutLocationStatus.otherAuthorized.value, 'other_authorized');
      expect(CheckoutLocationStatus.unauthorized.value, 'unauthorized');
      expect(CheckoutLocationStatus.gpsUnavailable.value, 'gps_unavailable');
    });

    test('CheckoutLocationStatus.fromValue parses correctly', () {
      expect(
        CheckoutLocationStatus.fromValue('assigned_location'),
        CheckoutLocationStatus.assignedLocation,
      );
      expect(
        CheckoutLocationStatus.fromValue('main_office'),
        CheckoutLocationStatus.mainOffice,
      );
      expect(
        CheckoutLocationStatus.fromValue('unknown'),
        CheckoutLocationStatus.assignedLocation, // default
      );
    });

    test('CheckoutLocationVerification requiresReason for unauthorized', () {
      const unauthorized = CheckoutLocationVerification(
        status: CheckoutLocationStatus.unauthorized,
        locationName: 'Unknown',
        latitude: 0,
        longitude: 0,
        accuracyMeters: 0,
        distanceToNearestMeters: 0,
      );
      expect(unauthorized.requiresReason, true);

      const assigned = CheckoutLocationVerification(
        status: CheckoutLocationStatus.assignedLocation,
        locationName: 'Office',
        latitude: 12.0,
        longitude: 80.0,
        accuracyMeters: 10,
        distanceToNearestMeters: 50,
      );
      expect(assigned.requiresReason, false);
    });
  });

  group('ApprovedWorkLocation Tests', () {
    test('fromJson parses work location correctly', () {
      final json = {
        'id': 'loc-001',
        'name': 'Chennai HQ',
        'latitude': 12.97,
        'longitude': 80.25,
        'allowed_radius_meters': 200,
        'is_primary': true,
        'location_type': 'OFFICE',
      };

      final loc = ApprovedWorkLocation.fromJson(json);
      expect(loc.id, 'loc-001');
      expect(loc.name, 'Chennai HQ');
      expect(loc.latitude, 12.97);
      expect(loc.allowedRadiusMeters, 200);
      expect(loc.isPrimary, true);
    });

    test('fromJson handles missing fields gracefully', () {
      final json = <String, dynamic>{};
      final loc = ApprovedWorkLocation.fromJson(json);
      expect(loc.name, 'Work Location');
      expect(loc.latitude, 0.0);
      expect(loc.allowedRadiusMeters, 0.0);
    });

    test('GeoPoint validates coordinates', () {
      const valid = GeoPoint(latitude: 12.97, longitude: 80.25);
      expect(valid.isValid, true);

      const zero = GeoPoint(latitude: 0, longitude: 0);
      expect(zero.isValid, false);

      const outOfRange = GeoPoint(latitude: 91, longitude: 181);
      expect(outOfRange.isValid, false);
    });
  });

  group('ExpenseClaimModel Tests', () {
    test('fromJson parses expense claim correctly', () {
      final json = {
        'id': 'exp-001',
        'description': 'Client lunch',
        'category': 'Meals',
        'amount': 1500.0,
        'expense_date': '2026-09-01',
        'status': 'APPROVED',
        'receipt_url': 'https://example.com/receipt.pdf',
      };

      final claim = ExpenseClaimModel.fromJson(json);
      expect(claim.id, 'exp-001');
      expect(claim.title, 'Client lunch');
      expect(claim.amount, 1500.0);
      expect(claim.status, ExpenseStatus.approved);
    });

    test('fromJson handles all status values', () {
      final statuses = {
        'PENDING': ExpenseStatus.pending,
        'APPROVED': ExpenseStatus.approved,
        'REJECTED': ExpenseStatus.rejected,
        'REIMBURSED': ExpenseStatus.reimbursed,
        'DRAFT': ExpenseStatus.draft,
      };

      for (final entry in statuses.entries) {
        final json = {
          'id': 'exp-001',
          'description': 'Test',
          'category': 'General',
          'amount': 100.0,
          'expense_date': '2026-09-01',
          'status': entry.key,
        };
        final claim = ExpenseClaimModel.fromJson(json);
        expect(claim.status, entry.value, reason: 'Status ${entry.key} should map to ${entry.value}');
      }
    });
  });

  group('HelpdeskTicketModel Tests', () {
    test('fromJson parses ticket correctly', () {
      final json = {
        'id': 'tkt-001',
        'ticket_number': 'TKT-001',
        'employee_id': 'EMP-001',
        'employee_name': 'Test User',
        'category': 'General HR',
        'subject': 'Salary query',
        'description': 'Need clarification on deductions',
        'priority': 'HIGH',
        'status': 'IN_PROGRESS',
        'created_at': '2026-09-01T10:00:00Z',
      };

      final ticket = HelpdeskTicketModel.fromJson(json);
      expect(ticket.ticketNumber, 'TKT-001');
      expect(ticket.priority, TicketPriority.high);
      expect(ticket.status, HelpdeskStatus.inProgress);
    });
  });

  group('ServiceDefinitionModel Tests', () {
    test('fromJson parses service definition', () {
      final json = {
        'id': 'svc-001',
        'code': 'TOOL_REQUEST',
        'name': 'Tool Request',
        'category': 'IT',
        'enabled': true,
        'employee_visible': true,
        'sla_hours': 48,
        'form_schema': [
          {'id': 'field1', 'label': 'Tool Name', 'type': 'TEXT', 'required': true},
          {'id': 'field2', 'label': 'Quantity', 'type': 'NUMBER', 'required': true},
        ],
      };

      final def = ServiceDefinitionModel.fromJson(json);
      expect(def.code, 'TOOL_REQUEST');
      expect(def.formSchema.length, 2);
      expect(def.formSchema[0].label, 'Tool Name');
      expect(def.formSchema[0].type, ServiceFieldType.text);
    });
  });
}
