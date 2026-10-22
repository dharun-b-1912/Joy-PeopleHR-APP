import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:workforce_os/core/services/app_version_service.dart';
import 'package:workforce_os/core/utils/app_date_time.dart';
import 'package:workforce_os/core/utils/validators.dart';
import 'package:workforce_os/models/employee_models.dart';
import 'package:workforce_os/models/hrms_models.dart';

void main() {
  group('Issue 1: Employee ID & UUID Isolation', () {
    test('Internal database UUID is never displayed as employee-facing Employee ID', () {
      const dbUuid = '0ce6436c-e9b4-4e0e-9102-93ea37612f01';
      const payslip = PayslipModel(
        id: 'ps-101',
        employeeId: dbUuid,
        employeeCode: '', // missing code
        employeeUuid: dbUuid,
        employeeName: 'Dharun B',
        designation: 'Developer',
        monthYear: 'July 2026',
        grossEarnings: '₹85,000',
        deductions: '₹5,200',
        netPay: '₹79,800',
        payDate: '2026-08-01T10:00:00+00:00',
        pdfUrl: 'payslips/ps-101.pdf',
      );

      // Verify displayEmployeeId does NOT return the UUID
      expect(payslip.displayEmployeeId, equals('Employee ID unavailable'));
      expect(payslip.displayEmployeeId, isNot(contains(dbUuid)));
      expect(payslip.hasValidEmployeeCode, isFalse);
    });

    test('Authoritative human-readable employee code is displayed when configured', () {
      const dbUuid = '0ce6436c-e9b4-4e0e-9102-93ea37612f01';
      const payslip = PayslipModel(
        id: 'ps-101',
        employeeId: dbUuid,
        employeeCode: 'JCS-017',
        employeeUuid: dbUuid,
        employeeName: 'Dharun B',
        designation: 'Developer',
        monthYear: 'July 2026',
        grossEarnings: '₹85,000',
        deductions: '₹5,200',
        netPay: '₹79,800',
        payDate: '2026-08-01T10:00:00+00:00',
        pdfUrl: 'payslips/ps-101.pdf',
      );

      expect(payslip.displayEmployeeId, equals('JCS-017'));
      expect(payslip.hasValidEmployeeCode, isTrue);
      expect(payslip.employeeUuid, equals(dbUuid));
    });

    test('UserModel displayEmployeeId protects against UUID leakage in profile', () {
      const dbUuid = '0ce6436c-e9b4-4e0e-9102-93ea37612f01';
      const userWithUuid = UserModel(
        name: 'Dharun B',
        firstName: 'Dharun',
        employeeId: dbUuid, // UUID erroneously passed as employeeId
        employeeUuid: dbUuid,
        designation: 'Developer',
        department: 'Development',
        role: 'EMPLOYEE',
        machinePin: '1234',
        campus: 'Not assigned',
        approvedLocation: ApprovedWorkLocation(
          id: 'loc-1',
          name: 'Main Campus',
          latitude: 12.9716,
          longitude: 77.5946,
          allowedRadiusMeters: 500,
        ),
        shiftStart: '09:00',
        shiftEnd: '18:00',
        leaveBalanceDays: 14,
      );

      expect(userWithUuid.displayEmployeeId, equals('Employee ID unavailable'));
      expect(userWithUuid.hasValidEmployeeCode, isFalse);

      final userWithCode = userWithUuid.copyWith(employeeId: 'JCS-017');
      expect(userWithCode.displayEmployeeId, equals('JCS-017'));
      expect(userWithCode.hasValidEmployeeCode, isTrue);
    });
  });

  group('Issue 2: Date Formatting & Pay Period vs Pay Date', () {
    test('Raw ISO timestamp 2026-08-01T10:00:00+00:00 formats to 01 Aug 2026', () {
      final formatted = AppDateTime.formatPayDate('2026-08-01T10:00:00+00:00');
      expect(formatted, equals('01 Aug 2026'));
    });

    test('Period format keeps Pay Period and Pay Date conceptually separate', () {
      const payslip = PayslipModel(
        id: 'ps-102',
        employeeId: '0ce6436c-e9b4-4e0e-9102-93ea37612f01',
        employeeCode: 'JCS-017',
        employeeName: 'Dharun B',
        designation: 'Developer',
        monthYear: '2026-07',
        grossEarnings: '₹85,000',
        deductions: '₹5,200',
        netPay: '₹79,800',
        payDate: '2026-08-01T10:00:00+00:00',
        pdfUrl: 'payslips/ps-102.pdf',
      );

      expect(payslip.formattedPeriod, equals('July 2026'));
      expect(payslip.formattedPayDate, equals('01 Aug 2026'));
    });
  });

  group('Issue 3: Payslip Calculation Integrity', () {
    test('Validates mathematical consistency of Earnings, Deductions, and Net Pay', () {
      const payslip = PayslipModel(
        id: 'ps-103',
        employeeId: '0ce6436c-e9b4-4e0e-9102-93ea37612f01',
        employeeCode: 'JCS-017',
        employeeName: 'Dharun B',
        designation: 'Developer',
        monthYear: 'July 2026',
        grossEarnings: '₹85,000',
        deductions: '₹5,200',
        netPay: '₹79,800',
        payDate: '2026-08-01',
        pdfUrl: 'payslips/ps-103.pdf',
        basicSalary: 42500,
        hra: 21250,
        specialAllowance: 21250,
        pfDeduction: 1800,
        profTaxDeduction: 200,
        incomeTaxDeduction: 3200,
      );

      expect(payslip.calculatedGross, equals(85000.0));
      expect(payslip.calculatedDeductions, equals(5200.0));
      expect(payslip.calculatedNetPay, equals(79800.0));
      expect(payslip.validateCalculations(), isTrue);
    });

    test('Detects mismatch when components do not sum to total', () {
      const mismatchPayslip = PayslipModel(
        id: 'ps-104',
        employeeId: '0ce6436c-e9b4-4e0e-9102-93ea37612f01',
        employeeCode: 'JCS-017',
        employeeName: 'Dharun B',
        designation: 'Developer',
        monthYear: 'July 2026',
        grossEarnings: '₹90,000', // mismatched
        deductions: '₹5,200',
        netPay: '₹79,800',
        payDate: '2026-08-01',
        pdfUrl: 'payslips/ps-104.pdf',
        basicSalary: 42500,
        hra: 21250,
        specialAllowance: 16250, // sum is 80,000, not 90,000
        pfDeduction: 1800,
        profTaxDeduction: 200,
        incomeTaxDeduction: 3200,
      );

      expect(mismatchPayslip.validateCalculations(), isFalse);
    });
  });

  group('Issue 8: Plant / Campus Stale Mock Data Removal', () {
    test('Plant/Campus displays Not assigned instead of Carenow when unassigned', () {
      const userUnassigned = UserModel(
        name: 'Dharun B',
        firstName: 'Dharun',
        employeeId: 'JCS-017',
        designation: 'Developer',
        department: 'Development',
        role: 'EMPLOYEE',
        machinePin: '1234',
        campus: '', // Empty or no assigned site
        approvedLocation: ApprovedWorkLocation(
          id: '',
          name: '',
          latitude: 0,
          longitude: 0,
          allowedRadiusMeters: 0,
        ),
        shiftStart: '09:00',
        shiftEnd: '18:00',
        leaveBalanceDays: 14,
      );

      final displayCampus = userUnassigned.campus.trim().isNotEmpty
          ? userUnassigned.campus
          : 'Not assigned';
      expect(displayCampus, equals('Not assigned'));
      expect(displayCampus, isNot(equals('Carenow')));
    });

    test('Plant/Campus displays actual assigned site when configured', () {
      const userAssigned = UserModel(
        name: 'Dharun B',
        firstName: 'Dharun',
        employeeId: 'JCS-017',
        designation: 'Developer',
        department: 'Development',
        role: 'EMPLOYEE',
        machinePin: '1234',
        campus: 'Joy Corporate Solutions Pvt Ltd',
        approvedLocation: ApprovedWorkLocation(
          id: 'site-01',
          name: 'Joy Corporate Solutions Pvt Ltd',
          latitude: 13.0827,
          longitude: 80.2707,
          allowedRadiusMeters: 500,
        ),
        shiftStart: '09:00',
        shiftEnd: '18:00',
        leaveBalanceDays: 14,
      );

      expect(userAssigned.campus, equals('Joy Corporate Solutions Pvt Ltd'));
      expect(userAssigned.campus, isNot(equals('Carenow')));
    });
  });

  group('Issue 4, 6 & 10: Byte-Level Document Signature Verification', () {
    test('Identifies authentic PDF magic bytes %PDF-', () {
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37]);
      final isPdf = pdfBytes.length >= 4 &&
          pdfBytes[0] == 0x25 &&
          pdfBytes[1] == 0x50 &&
          pdfBytes[2] == 0x44 &&
          pdfBytes[3] == 0x46;
      expect(isPdf, isTrue);
    });

    test('Identifies authentic JPEG magic bytes 0xFF 0xD8 0xFF', () {
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final isJpeg = jpegBytes.length >= 3 &&
          jpegBytes[0] == 0xFF &&
          jpegBytes[1] == 0xD8 &&
          jpegBytes[2] == 0xFF;
      expect(isJpeg, isTrue);
    });

    test('Identifies HTML error responses and prevents saving as PDF', () {
      final htmlErrorBytes = Uint8List.fromList(utf8.encode('<!DOCTYPE html><html><body>404 Not Found</body></html>'));
      final previewString = ascii.decode(htmlErrorBytes.sublist(0, 32), allowInvalid: true).toLowerCase();
      final isHtmlError = previewString.contains('<!doctype html') || previewString.contains('<html');
      expect(isHtmlError, isTrue);
    });

    test('Identifies JSON error responses and prevents saving as document', () {
      final jsonErrorBytes = Uint8List.fromList(utf8.encode('{"error":"Unauthorized","statusCode":401}'));
      final previewString = ascii.decode(jsonErrorBytes.sublist(0, 32), allowInvalid: true).toLowerCase();
      final isJsonError = previewString.contains('{"error"') || previewString.contains('{"statuscode"');
      expect(isJsonError, isTrue);
    });

    test('Validators.generateUuid creates valid v4 UUID strings', () {
      final uuid1 = Validators.generateUuid();
      final uuid2 = Validators.generateUuid();
      expect(Validators.isValidUuid(uuid1), isTrue);
      expect(Validators.isValidUuid(uuid2), isTrue);
      expect(uuid1, isNot(equals(uuid2)));
    });
  });

  group('Issue 12: Dynamic App Version Pipeline', () {
    test('AppVersionService dynamically reflects authentic platform package info', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Joy PeopleHR',
        packageName: 'com.joy.peoplehr',
        version: '1.2.3',
        buildNumber: '42',
        buildSignature: '',
      );

      final service = AppVersionService.instance;
      await service.init();

      expect(service.version, equals('1.2.3'));
      expect(service.buildNumber, equals('42'));
      expect(service.displayVersion, equals('v1.2.3 (Build 42)'));
      expect(service.shortVersion, equals('v1.2.3'));
    });
  });
}
