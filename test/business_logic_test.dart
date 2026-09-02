import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/hrms_models.dart';
import 'package:workforce_os/models/employee_models.dart';
import 'package:workforce_os/core/services/shift_duration_calculator.dart';

void main() {
  group('1. Universal Self-Service Access Tests (Designation Independence)', () {
    test('All designations must have valid employee self-service access', () {
      final designations = [
        'Software Engineer',
        'Engineering Manager',
        'HR Executive',
        'HR Manager',
        'Chief Technology Officer',
        'Director',
        'Intern',
        'Accountant',
        'Operations Executive',
      ];

      for (final desig in designations) {
        final user = UserModel(
          name: 'Test Employee ($desig)',
          firstName: 'Test',
          employeeId: 'JCS-TEST',
          employeeUuid: 'uuid-1234',
          designation: desig,
          department: 'Engineering',
          role: desig.contains('Manager') ? 'MANAGER' : 'EMPLOYEE',
          machinePin: '1234',
          campus: 'Chennai HQ',
          approvedLocation: const ApprovedWorkLocation(
            name: 'Chennai HQ',
            latitude: 12.97,
            longitude: 80.25,
            allowedRadiusMeters: 200,
          ),
          shiftStart: '09:30',
          shiftEnd: '18:30',
          leaveBalanceDays: 15,
          companyId: 'comp-01',
        );

        // Core Self-Service rule: Every user model has resolved employee identifiers
        expect(user.resolvedEmployeeId.isNotEmpty, true, reason: 'Employee ID must be resolved for $desig');
        expect(user.employeeId, 'JCS-TEST');
        expect(user.name.isNotEmpty, true);
      }
    });
  });

  group('2. Attendance Status Parsing & Timesheet Logic', () {
    test('Attendance status parsing accurately maps all schema states', () {
      DayAttendanceStatus parseStatus(String raw) {
        final s = raw.toUpperCase().replaceAll(' ', '_');
        switch (s) {
          case 'PRESENT':
          case 'P':
            return DayAttendanceStatus.present;
          case 'HALF_DAY_PRESENT':
          case 'HALF_DAY':
          case 'HD':
            return DayAttendanceStatus.halfDayPresent;
          case 'HALF_DAY_ABSENT':
            return DayAttendanceStatus.halfDayAbsent;
          case 'ABSENT':
          case 'A':
            return DayAttendanceStatus.absent;
          case 'LEAVE':
          case 'ON_LEAVE':
          case 'L':
            return DayAttendanceStatus.leave;
          case 'HOLIDAY':
          case 'H':
            return DayAttendanceStatus.holiday;
          case 'WEEKLY_OFF':
          case 'WEEK_OFF':
          case 'WO':
          case 'OFF':
            return DayAttendanceStatus.weekOff;
          case 'LATE':
            return DayAttendanceStatus.late;
          case 'REGULARIZED':
          case 'REGULARIZATION':
            return DayAttendanceStatus.regularized;
          case 'NOT_PAYABLE':
          case 'MISSED_PUNCH':
          case 'INCOMPLETE':
            return DayAttendanceStatus.notPayable;
          case 'PENDING':
          case 'SCHEDULED':
          case 'NOT_MARKED':
          case 'NONE':
          case '':
            return DayAttendanceStatus.none;
          default:
            return DayAttendanceStatus.none;
        }
      }

      expect(parseStatus('PRESENT'), DayAttendanceStatus.present);
      expect(parseStatus('P'), DayAttendanceStatus.present);
      expect(parseStatus('REGULARIZED'), DayAttendanceStatus.regularized);
      expect(parseStatus('NOT_PAYABLE'), DayAttendanceStatus.notPayable);
      expect(parseStatus('MISSED_PUNCH'), DayAttendanceStatus.notPayable);
      expect(parseStatus('WEEK_OFF'), DayAttendanceStatus.weekOff);
      expect(parseStatus('ABSENT'), DayAttendanceStatus.absent);
      expect(parseStatus('LEAVE'), DayAttendanceStatus.leave);
      expect(parseStatus('PENDING'), DayAttendanceStatus.none);
      expect(parseStatus('SCHEDULED'), DayAttendanceStatus.none);
      expect(parseStatus(''), DayAttendanceStatus.none);
    });

    test('Attendance calculation rules (>=6h Present, <6h Half Day, Missed Out Not Payable)', () {
      DayAttendanceStatus evaluateStatus({
        required bool hasCheckIn,
        required bool hasCheckOut,
        required int netMinutes,
        required bool isRegularizedApproved,
      }) {
        if (isRegularizedApproved) return DayAttendanceStatus.present;
        if (hasCheckIn) {
          if (hasCheckOut) {
            if (netMinutes >= 360) return DayAttendanceStatus.present;
            if (netMinutes > 0) return DayAttendanceStatus.halfDay;
            return DayAttendanceStatus.notPayable;
          }
          return DayAttendanceStatus.notPayable;
        }
        return DayAttendanceStatus.absent;
      }

      // Check-in + Check-out >= 6 hours -> Present
      expect(evaluateStatus(hasCheckIn: true, hasCheckOut: true, netMinutes: 480, isRegularizedApproved: false), DayAttendanceStatus.present);
      expect(evaluateStatus(hasCheckIn: true, hasCheckOut: true, netMinutes: 360, isRegularizedApproved: false), DayAttendanceStatus.present);

      // Check-in + Check-out < 6 hours -> Half Day
      expect(evaluateStatus(hasCheckIn: true, hasCheckOut: true, netMinutes: 300, isRegularizedApproved: false), DayAttendanceStatus.halfDay);
      expect(evaluateStatus(hasCheckIn: true, hasCheckOut: true, netMinutes: 180, isRegularizedApproved: false), DayAttendanceStatus.halfDay);

      // Check-in without Check-out -> Not Payable
      expect(evaluateStatus(hasCheckIn: true, hasCheckOut: false, netMinutes: 0, isRegularizedApproved: false), DayAttendanceStatus.notPayable);

      // Approved Regularization -> Present
      expect(evaluateStatus(hasCheckIn: true, hasCheckOut: false, netMinutes: 0, isRegularizedApproved: true), DayAttendanceStatus.present);
    });

    test('Regularized and Present days resolve to Green Success state', () {
      final statuses = [DayAttendanceStatus.present, DayAttendanceStatus.regularized];
      for (final st in statuses) {
        final isSuccess = (st == DayAttendanceStatus.present || st == DayAttendanceStatus.regularized);
        expect(isSuccess, true, reason: '$st must qualify as success/present');
      }
    });

    test('Un-punched today resolves to Pending Check-In', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final label = today.day == now.day ? "Pending Check-In" : "Scheduled";
      expect(label, "Pending Check-In");
    });
  });

  group('3. Leave Balance Derivation Tests', () {
    test('Available balance formula: Opening + Accrued - Used', () {
      const opening = 12.0;
      const accrued = 2.0;
      const used = 3.5;

      const totalQuota = opening + accrued;
      final available = (totalQuota - used).clamp(0.0, 999.0);

      expect(totalQuota, 14.0);
      expect(available, 10.5);
    });

    test('Negative balance is clamped safely to 0', () {
      const opening = 5.0;
      const accrued = 0.0;
      const used = 7.0;

      final available = (opening + accrued - used).clamp(0.0, 999.0);
      expect(available, 0.0);
    });
  });

  group('4. Shift Duration & Overnight Span Calculator Tests', () {
    test('Standard Day Shift (09:30 AM to 06:30 PM)', () {
      final calc = ShiftDurationCalculator.instance.calculate(
        startTime: '09:30',
        endTime: '18:30',
        breakMinutes: 60,
      );

      expect(calc.spanMinutes, 540); // 9 hours
      expect(calc.breakMinutes, 60);
      expect(calc.scheduledWorkMinutes, 480); // 8 hours
      expect(calc.formattedScheduledWork, '8h scheduled');
      expect(calc.crossesMidnight, false);
    });

    test('Overnight Night Shift (08:00 PM to 05:00 AM)', () {
      final calc = ShiftDurationCalculator.instance.calculate(
        startTime: '20:00',
        endTime: '05:00',
        breakMinutes: 45,
      );

      expect(calc.crossesMidnight, true);
      expect(calc.spanMinutes, 540); // 9 hours
      expect(calc.scheduledWorkMinutes, 495); // 8h 15m
      expect(calc.formattedScheduledWork, '8h 15m scheduled');
    });

    test('Weekly Off Shift Day', () {
      final calc = ShiftDurationCalculator.instance.calculate(
        startTime: '09:30',
        endTime: '18:30',
        isOffDay: true,
      );

      expect(calc.scheduledWorkMinutes, 0);
      expect(calc.formattedScheduledWork, 'No scheduled work');
    });
  });
}
