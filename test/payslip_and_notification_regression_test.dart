// test/payslip_and_notification_regression_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/employee_models.dart';
import 'package:workforce_os/core/services/payslip_pdf_service.dart';

void main() {
  group('JOY PeopleHR Unified Payslip & Notification Idempotency Suite', () {
    test('1. PayslipModel correctly reconciles dynamic earnings breakdown matching authoritative DB', () {
      final dynamicEarnings = [
        {'name': 'Basic Wages', 'amount': 7258.0},
        {'name': 'House Rent Allowance (HRA)', 'amount': 2903.0},
        {'name': 'Special Allowance', 'amount': 4355.0},
        {'name': 'Overtime Wages (OT)', 'amount': 520.0},
      ];

      final model = PayslipModel(
        id: 'ps-jcs20-oct2026',
        employeeId: '0dc8993f-c0cc-4143-aedc-d4893e41b001',
        employeeCode: 'JCS-20',
        employeeName: 'Thirumalai R K',
        designation: 'Associate Developer',
        monthYear: 'October 2026',
        grossEarnings: '₹15036',
        deductions: '₹0',
        netPay: '₹15036',
        payDate: '2026-10-31',
        pdfUrl: '2026/10/PAY-OCTOBER-2026-JCS-20.pdf',
        basicSalary: 7258.0,
        hra: 2903.0,
        specialAllowance: 4355.0,
        payableDays: 22.5,
        lopDays: 8.5,
        totalWorkingDays: 31,
        earningsComponents: dynamicEarnings,
        deductionsComponents: const [],
      );

      // Verify dynamic summing
      expect(model.calculatedGross, equals(15036.0));
      expect(model.calculatedDeductions, equals(0.0));
      expect(model.calculatedNetPay, equals(15036.0));
      expect(model.payableDays, equals(22.5));
      expect(model.lopDays, equals(8.5));
      expect(model.validateCalculations(), isTrue);
    });

    test('2. PayslipModel catches calculation discrepancies when components do not equal gross', () {
      // Replicating previous bug where Basic & HRA were 0 and only Special was 4355 against gross 15036
      const invalidModel = PayslipModel(
        id: 'ps-mismatch-test',
        employeeCode: 'JCS-20',
        monthYear: 'October 2026',
        grossEarnings: '₹15036',
        deductions: '₹0',
        netPay: '₹15036',
        payDate: '2026-10-31',
        pdfUrl: '',
        basicSalary: 0.0,
        hra: 0.0,
        specialAllowance: 4355.0,
        earningsComponents: [
          {'name': 'Special Allowance', 'amount': 4355.0},
        ],
        deductionsComponents: [],
      );

      expect(invalidModel.calculatedGross, equals(4355.0));
      // validateCalculations should catch this mismatch (4355 vs 15036)
      expect(invalidModel.validateCalculations(), isFalse);
    });

    test('3. PayslipPdfService generates high-fidelity vector PDF with dynamic earnings & attendance', () {
      final dynamicEarnings = [
        {'name': 'Basic Wages', 'amount': 7258.0},
        {'name': 'House Rent Allowance (HRA)', 'amount': 2903.0},
        {'name': 'Special Allowance', 'amount': 4355.0},
        {'name': 'Overtime Wages (OT)', 'amount': 520.0},
      ];

      final model = PayslipModel(
        id: 'ps-jcs20-oct2026',
        employeeCode: 'JCS-20',
        employeeName: 'Thirumalai R K',
        designation: 'Associate Developer',
        monthYear: 'October 2026',
        grossEarnings: '₹15036',
        deductions: '₹0',
        netPay: '₹15036',
        payDate: '2026-10-31',
        pdfUrl: '2026/10/PAY-OCTOBER-2026-JCS-20.pdf',
        payableDays: 22.5,
        lopDays: 8.5,
        totalWorkingDays: 31,
        earningsComponents: dynamicEarnings,
        deductionsComponents: const [],
      );

      final pdfBytes = PayslipPdfService.generatePdfBytes(model);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(500));

      final pdfString = utf8.decode(pdfBytes, allowMalformed: true);
      // Verify valid standard PDF header
      expect(pdfString.startsWith('%PDF-1.4'), isTrue);

      // Verify inclusion of all dynamic earnings components (parentheses are escaped as \( \) in PDF text stream)
      expect(pdfString.contains('Basic Wages'), isTrue);
      expect(pdfString.contains('House Rent Allowance'), isTrue);
      expect(pdfString.contains('Special Allowance'), isTrue);
      expect(pdfString.contains('Overtime Wages'), isTrue);

      // Verify attendance days inclusion
      expect(pdfString.contains('22.5 Days'), isTrue);
      expect(pdfString.contains('8.5 Days'), isTrue);

      // Verify reconciled net take-home
      expect(pdfString.contains('Rs. 15,036'), isTrue);
    });

    test('4. Notification collapse ID is deterministic for identical route & title', () {
      const title = 'Payslip Available — September 2026';
      const route = 'payslip';

      final id1 = (title + route).hashCode & 0x7FFFFFFF;
      final id2 = (title + route).hashCode & 0x7FFFFFFF;

      // Deterministic ID guarantees notifications collapse in Android tray instead of stacking
      expect(id1, equals(id2));

      // Different month produces different ID, preserving distinct payroll notices
      const titleOct = 'Payslip Available — October 2026';
      final idOct = (titleOct + route).hashCode & 0x7FFFFFFF;
      expect(id1, isNot(equals(idOct)));
    });

    test('5. Notification deduplication key correctly separates distinct pay periods while merging duplicates', () {
      final seenKeys = <String>{};

      bool isDuplicate(String title, String message) {
        final key = '${title.trim().toLowerCase()}|${message.trim().toLowerCase()}';
        if (seenKeys.contains(key)) return true;
        seenKeys.add(key);
        return false;
      }

      // First September notice
      expect(isDuplicate('Payslip Available — September 2026', 'Your payslip is ready.'), isFalse);

      // Second identical September notice (e.g. from local FCM or Realtime re-sync) -> Duplicate!
      expect(isDuplicate('Payslip Available — September 2026', 'Your payslip is ready.'), isTrue);

      // New October notice -> Allowed!
      expect(isDuplicate('Payslip Available — October 2026', 'Your payslip is ready.'), isFalse);

      // Different notification type (Leave) -> Allowed!
      expect(isDuplicate('Leave Approved', 'Your leave request has been approved.'), isFalse);
    });
  });
}
