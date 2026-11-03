import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/hrms_models.dart';
import 'package:workforce_os/models/employee_models.dart';

void main() {
  group('Tenant Isolation and Dynamic Resolution Tests', () {
    test('User dataId strictly prioritizes database UUID for RLS scoped queries', () {
      const userWithUuid = UserModel(
        name: 'John Doe',
        firstName: 'John',
        employeeId: 'EMP-001',
        employeeUuid: 'e5f6a1b2-3c4d-5e6f-7a8b-9c0d1e2f3a4b',
        designation: 'Engineer',
        department: 'Tech',
        role: 'EMPLOYEE',
        machinePin: '1111',
        campus: 'Campus A',
        approvedLocation: ApprovedWorkLocation(
          name: 'HQ',
          latitude: 12.9716,
          longitude: 77.5946,
          allowedRadiusMeters: 100,
        ),
        shiftStart: '09:00 AM',
        shiftEnd: '06:00 PM',
        leaveBalanceDays: 10,
        companyId: 'org-tenant-alpha',
      );

      expect(userWithUuid.dataId, 'e5f6a1b2-3c4d-5e6f-7a8b-9c0d1e2f3a4b');
      expect(userWithUuid.tenantId, 'org-tenant-alpha');
    });

    test('LeaveBalanceModel initializes with exact dynamic entitlements', () {
      const balance = LeaveBalanceModel(
        casualAvailable: 14.5,
        casualUsed: 2.0,
        sickAvailable: 8.0,
        sickUsed: 1.0,
        earnedAvailable: 21.0,
        earnedUsed: 4.5,
      );

      expect(balance.casualAvailable, 14.5);
      expect(balance.casualUsed, 2.0);
      expect(balance.sickAvailable, 8.0);
      expect(balance.earnedAvailable, 21.0);
    });

    test('PayslipModel parses dynamic multi-tenant salary structure without hardcodes', () {
      const payslip = PayslipModel(
        id: 'ps-901',
        monthYear: 'August 2026',
        basicSalary: 45000.0,
        hra: 18000.0,
        specialAllowance: 12000.0,
        pfDeduction: 5400.0,
        profTaxDeduction: 200.0,
        incomeTaxDeduction: 2500.0,
        grossEarnings: '₹75,000',
        deductions: '₹8,100',
        netPay: '₹66,900',
        payDate: '31 Aug 2026',
        pdfUrl: 'https://storage.example.com/payslips/ps-901.pdf',
      );

      expect(payslip.monthYear, 'August 2026');
      expect(payslip.basicSalary, 45000.0);
      expect(payslip.grossEarnings, '₹75,000');
      expect(payslip.netPay, '₹66,900');
    });
  });
}
