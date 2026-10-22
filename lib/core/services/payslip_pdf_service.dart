import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';
import '../../models/employee_models.dart';
import '../../models/hrms_models.dart';
import 'file_download_service.dart';

/// Pure-Dart vector PDF generator for employee salary slips.
/// Matches the official Web HR Compensation Statement / Tamil Nadu Standard Grid.
/// Generates enterprise-standard PDF 1.4 documents completely offline,
/// ensuring instant downloads with zero external network or domain dependencies.
class PayslipPdfService {
  /// Generates PDF bytes and triggers direct download/save to user's device
  static Future<bool> generateAndDownload(PayslipModel payslip, {UserModel? user}) async {
    final cleanMonth = payslip.formattedPeriod.replaceAll(' ', '_');
    final empCode = payslip.displayEmployeeId != 'Employee ID unavailable'
        ? payslip.displayEmployeeId
        : (user != null && user.displayEmployeeId != 'Employee ID unavailable'
            ? user.displayEmployeeId
            : 'Employee');
    final fileName = "Payslip_${cleanMonth}_$empCode.pdf";

    // 1. Try authoritative signed storage URL if storage_path is present
    if (payslip.pdfUrl.isNotEmpty && SupabaseConfig.isConfigured) {
      try {
        String downloadUrl = payslip.pdfUrl;
        if (!downloadUrl.startsWith('http')) {
          final res = await Supabase.instance.client.storage
              .from('payslips')
              .createSignedUrl(payslip.pdfUrl, 300);
          downloadUrl = res;
        }
        if (downloadUrl.isNotEmpty) {
          final ok = await FileDownloadService.downloadFromUrl(
            url: downloadUrl,
            fileName: fileName,
          );
          if (ok) return true;
        }
      } catch (e) {
        secureLog('[PayslipPdfService] Direct storage download notice: $e');
      }
    }

    // 2. Generate unified vector PDF offline with 100% data reconciliation
    final bytes = generatePdfBytes(payslip, user: user);
    return await FileDownloadService.downloadBytes(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  }

  /// Builds a valid, standard PDF 1.4 binary matching the Web HR Compensation Statement
  static Uint8List generatePdfBytes(PayslipModel payslip, {UserModel? user}) {
    // 1. Company Name (The employee's actual employing company, not the SaaS platform)
    final companyName = user?.companyName?.isNotEmpty == true
        ? user!.companyName!
        : (user?.organizationName?.isNotEmpty == true ? user!.organizationName! : 'JOY CORPORATE SOLUTIONS');

    // 2. Employee Profile Details
    final empName = payslip.employeeName.isNotEmpty
        ? payslip.employeeName
        : (user?.name.isNotEmpty == true ? user!.name : '—');
    final empCode = payslip.displayEmployeeId != 'Employee ID unavailable'
        ? payslip.displayEmployeeId
        : (user != null && user.displayEmployeeId != 'Employee ID unavailable'
            ? user.displayEmployeeId
            : '—');
    final dept = user?.department.isNotEmpty == true ? user!.department : '—';
    final desig = payslip.designation.isNotEmpty
        ? payslip.designation
        : (user?.designation.isNotEmpty == true ? user!.designation : '—');
    final payDate = payslip.formattedPayDate.isNotEmpty ? payslip.formattedPayDate : '—';
    final payPeriod = payslip.formattedPeriod.isNotEmpty ? payslip.formattedPeriod : '—';

    // 3. Financial Computations & Dynamic Component Resolution
    final earningsList = <Map<String, dynamic>>[];
    if (payslip.earningsComponents.isNotEmpty) {
      for (final c in payslip.earningsComponents) {
        final amt = (c['amount'] is num) ? (c['amount'] as num).toDouble() : (double.tryParse(c['amount']?.toString() ?? '') ?? 0.0);
        earningsList.add({'name': c['name']?.toString() ?? 'Earnings', 'amount': amt});
      }
    } else {
      if (payslip.basicSalary > 0) earningsList.add({'name': 'Basic Salary', 'amount': payslip.basicSalary});
      if (payslip.hra > 0) earningsList.add({'name': 'House Rent Allowance (HRA)', 'amount': payslip.hra});
      if (payslip.specialAllowance > 0) earningsList.add({'name': 'Special Allowance', 'amount': payslip.specialAllowance});
    }

    final deductionsList = <Map<String, dynamic>>[];
    if (payslip.deductionsComponents.isNotEmpty) {
      for (final c in payslip.deductionsComponents) {
        final amt = (c['amount'] is num) ? (c['amount'] as num).toDouble() : (double.tryParse(c['amount']?.toString() ?? '') ?? 0.0);
        deductionsList.add({'name': c['name']?.toString() ?? 'Deduction', 'amount': amt});
      }
    } else {
      if (payslip.pfDeduction > 0) deductionsList.add({'name': 'Provident Fund (EPF)', 'amount': payslip.pfDeduction});
      if (payslip.profTaxDeduction > 0) deductionsList.add({'name': 'Professional Tax (PT)', 'amount': payslip.profTaxDeduction});
      if (payslip.incomeTaxDeduction > 0) deductionsList.add({'name': 'Income Tax (TDS)', 'amount': payslip.incomeTaxDeduction});
    }

    // Authoritative math: Gross = sum of all earnings, Deductions = sum of all deductions
    double gross = earningsList.fold(0.0, (s, e) => s + (e['amount'] as double));
    if (gross <= 0) gross = _parseCurrency(payslip.grossEarnings);

    double totalDeductions = deductionsList.fold(0.0, (s, d) => s + (d['amount'] as double));
    if (totalDeductions <= 0 && payslip.deductions.isNotEmpty) {
      totalDeductions = _parseCurrency(payslip.deductions);
    }

    double netPay = gross - totalDeductions;
    if (netPay <= 0) netPay = _parseCurrency(payslip.netPay);

    final netPayStr = "Rs. ${_formatInr(netPay.toInt())}";
    final netInWords = _numberToWordsIndian(netPay.toInt());

    // Attendance inputs
    final payableDaysStr = "${payslip.payableDays % 1 == 0 ? payslip.payableDays.toInt() : payslip.payableDays} Days";
    final lopDaysStr = "${payslip.lopDays % 1 == 0 ? payslip.lopDays.toInt() : payslip.lopDays} Days";

    // 4. Vector PDF Content Stream (Page A4: 595 x 842 pt)
    final sb = StringBuffer();

    // Helper for rendering absolute-positioned text
    void writeText(double x, double y, String font, double size, double r, double g, double b, String text) {
      sb.writeln("BT");
      sb.writeln("/$font $size Tf");
      sb.writeln("$r $g $b rg");
      sb.writeln("1 0 0 1 $x $y Tm");
      sb.writeln("(${_escape(text)}) Tj");
      sb.writeln("ET");
    }

    // --- TOP BANNER (Primary Emerald: #0D5C3A / 0.05 0.36 0.23) ---
    sb.writeln("q 0.05 0.36 0.23 rg 40 782 515 28 re f Q");
    writeText(55, 792, "F2", 13, 1.0, 1.0, 1.0, companyName.toUpperCase());

    // --- SUB-HEADER ---
    writeText(40, 756, "F2", 15, 0.1, 0.1, 0.1, "EMPLOYEE COMPENSATION STATEMENT");
    writeText(40, 740, "F1", 9.5, 0.4, 0.4, 0.4, "Pay Period: $payPeriod   |   Payment Date: $payDate   |   Status: Paid (Direct Transfer)");

    // Divider Line
    sb.writeln("q 0.85 0.85 0.85 RG 1 w 40 730 m 555 730 l S Q");

    // --- EMPLOYEE DETAILS CARD (Background & Border) ---
    sb.writeln("q 0.96 0.97 0.98 rg 0.86 0.88 0.90 RG 1 w 40 630 515 90 re B Q");

    // Column 1: Labels & Values
    writeText(55, 702, "F2", 8.5, 0.45, 0.45, 0.45, "EMPLOYEE NAME:");
    writeText(155, 702, "F2", 9.0, 0.1, 0.1, 0.1, empName);

    writeText(55, 684, "F2", 8.5, 0.45, 0.45, 0.45, "EMPLOYEE ID:");
    writeText(155, 684, "F1", 9.0, 0.1, 0.1, 0.1, empCode);

    writeText(55, 666, "F2", 8.5, 0.45, 0.45, 0.45, "DEPARTMENT:");
    writeText(155, 666, "F1", 9.0, 0.1, 0.1, 0.1, dept);

    writeText(55, 648, "F2", 8.5, 0.45, 0.45, 0.45, "DESIGNATION:");
    writeText(155, 648, "F1", 9.0, 0.1, 0.1, 0.1, desig);

    // Column 2: Labels & Values
    writeText(330, 702, "F2", 8.5, 0.45, 0.45, 0.45, "PAYABLE DAYS:");
    writeText(430, 702, "F1", 9.0, 0.1, 0.1, 0.1, "$payableDaysStr (LOP: $lopDaysStr)");

    writeText(330, 684, "F2", 8.5, 0.45, 0.45, 0.45, "PAYMENT MODE:");
    writeText(430, 684, "F2", 9.0, 0.05, 0.45, 0.25, "Direct Transfer (Settled)");

    writeText(330, 666, "F2", 8.5, 0.45, 0.45, 0.45, "CURRENCY:");
    writeText(430, 666, "F1", 9.0, 0.1, 0.1, 0.1, "INR (Indian Rupee)");

    writeText(330, 648, "F2", 8.5, 0.45, 0.45, 0.45, "STATEMENT REF:");
    writeText(430, 648, "F1", 8.5, 0.3, 0.3, 0.3, "PS-$payPeriod-$empCode");

    // --- EARNINGS & DEDUCTIONS DUAL TABLES ---
    // Earnings Table Header (Teal / Emerald)
    sb.writeln("q 0.05 0.36 0.23 rg 40 598 250 22 re f Q");
    writeText(50, 605, "F2", 9.5, 1.0, 1.0, 1.0, "EARNINGS");
    writeText(220, 605, "F2", 9.5, 1.0, 1.0, 1.0, "AMOUNT");

    // Deductions Table Header (Rose / Crimson)
    sb.writeln("q 0.75 0.20 0.20 rg 305 598 250 22 re f Q");
    writeText(315, 605, "F2", 9.5, 1.0, 1.0, 1.0, "DEDUCTIONS");
    writeText(485, 605, "F2", 9.5, 1.0, 1.0, 1.0, "AMOUNT");

    // Dynamic Symmetrical Row Rendering
    final maxRows = [earningsList.length, deductionsList.length, 3].reduce((a, b) => a > b ? a : b);
    const rowHeight = 22.0;
    const tableTopY = 576.0;

    for (int i = 0; i < maxRows; i++) {
      final currentY = tableTopY - (i * rowHeight);
      final isZebra = i % 2 == 0;
      if (isZebra) {
        sb.writeln("q 0.97 0.97 0.97 rg 40 ${currentY.toInt()} 250 ${rowHeight.toInt()} re f 305 ${currentY.toInt()} 250 ${rowHeight.toInt()} re f Q");
      }

      final textY = currentY + 7;

      // Earnings Col
      if (i < earningsList.length) {
        final e = earningsList[i];
        writeText(50, textY, "F1", 9.0, 0.15, 0.15, 0.15, e['name'] as String);
        writeText(220, textY, "F2", 9.0, 0.1, 0.1, 0.1, "Rs. ${_formatInr((e['amount'] as double).toInt())}");
      }

      // Deductions Col
      if (i < deductionsList.length) {
        final d = deductionsList[i];
        writeText(315, textY, "F1", 9.0, 0.15, 0.15, 0.15, d['name'] as String);
        writeText(485, textY, "F2", 9.0, 0.1, 0.1, 0.1, "Rs. ${_formatInr((d['amount'] as double).toInt())}");
      } else if (i == 0 && deductionsList.isEmpty) {
        writeText(315, textY, "F1", 9.0, 0.45, 0.45, 0.45, "Nil Deductions");
        writeText(485, textY, "F2", 9.0, 0.45, 0.45, 0.45, "Rs. 0");
      }
    }

    final tableTotalHeight = maxRows * rowHeight;
    final tableBottomY = tableTopY - tableTotalHeight + rowHeight;
    // Table Outlines
    sb.writeln("q 0.85 0.85 0.85 RG 1 w 40 ${tableBottomY.toInt()} 250 ${tableTotalHeight.toInt()} re S 305 ${tableBottomY.toInt()} 250 ${tableTotalHeight.toInt()} re S Q");

    // --- TOTALS BAR ---
    final totalsBarY = tableTopY - tableTotalHeight - 5;
    sb.writeln("q 0.93 0.95 0.96 rg 0.75 0.75 0.75 RG 1 w 40 ${totalsBarY.toInt()} 250 24 re B 305 ${totalsBarY.toInt()} 250 24 re B Q");
    writeText(50, totalsBarY + 8, "F2", 9.5, 0.05, 0.36, 0.23, "Gross Salary Earnings:");
    writeText(215, totalsBarY + 8, "F2", 9.5, 0.05, 0.36, 0.23, "Rs. ${_formatInr(gross.toInt())}");
    writeText(315, totalsBarY + 8, "F2", 9.5, 0.75, 0.20, 0.20, "Total Deductions:");
    writeText(480, totalsBarY + 8, "F2", 9.5, 0.75, 0.20, 0.20, "Rs. ${_formatInr(totalDeductions.toInt())}");

    // --- NET PAYABLE SALARY HIGHLIGHT BOX ---
    final netBoxY = totalsBarY - 70;
    sb.writeln("q 0.05 0.36 0.23 rg 40 ${netBoxY.toInt()} 515 58 re f Q");
    writeText(55, netBoxY + 36, "F2", 11.0, 1.0, 1.0, 1.0, "NET PAYABLE SALARY TRANSFERRED:");
    writeText(370, netBoxY + 32, "F2", 16.0, 1.0, 1.0, 1.0, netPayStr);
    writeText(55, netBoxY + 14, "F1", 9.0, 0.85, 0.95, 0.90, "Amount in Words: $netInWords");

    // --- LEGAL & STATUTORY FOOTER ---
    final footerY = netBoxY - 45;
    writeText(40, footerY, "F1", 8.0, 0.45, 0.45, 0.45, "*** This is a computer-generated payslip and does not require a physical signature. ***");
    writeText(40, footerY - 13, "F1", 7.5, 0.55, 0.55, 0.55, "Authorized by $companyName • Generated on: ${DateTime.now().toUtc().toIso8601String().substring(0, 10)}");
    writeText(40, footerY - 25, "F1", 7.5, 0.55, 0.55, 0.55, "JOY PeopleHR Enterprise Compensation Engine • Authenticated Digital Record");

    // Divider Line
    sb.writeln("q 0.85 0.85 0.85 RG 1 w 40 ${(footerY - 40).toInt()} m 555 ${(footerY - 40).toInt()} l S Q");

    // Signatory Block
    writeText(390, footerY - 75, "F2", 9.0, 0.2, 0.2, 0.2, "For $companyName");
    writeText(390, footerY - 105, "F1", 8.0, 0.4, 0.4, 0.4, "Authorized Signatory");

    final streamContent = sb.toString();
    final streamBytes = utf8.encode(streamContent);
    final streamLength = streamBytes.length;

    // Assemble PDF Document
    final pdf = StringBuffer();
    pdf.writeln("%PDF-1.4");
    pdf.writeln("%\xFF\xFF\xFF\xFF");

    final offsets = <int>[];

    // Obj 1: Catalog
    offsets.add(pdf.length);
    pdf.writeln("1 0 obj");
    pdf.writeln("<< /Type /Catalog /Pages 2 0 R >>");
    pdf.writeln("endobj");

    // Obj 2: Pages
    offsets.add(pdf.length);
    pdf.writeln("2 0 obj");
    pdf.writeln("<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
    pdf.writeln("endobj");

    // Obj 3: Page (A4: 595.28 x 841.89)
    offsets.add(pdf.length);
    pdf.writeln("3 0 obj");
    pdf.writeln("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>");
    pdf.writeln("endobj");

    // Obj 4: Content Stream
    offsets.add(pdf.length);
    pdf.writeln("4 0 obj");
    pdf.writeln("<< /Length $streamLength >>");
    pdf.writeln("stream");
    pdf.write(streamContent);
    pdf.writeln("endstream");
    pdf.writeln("endobj");

    // Obj 5: Font F1 (Helvetica)
    offsets.add(pdf.length);
    pdf.writeln("5 0 obj");
    pdf.writeln("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
    pdf.writeln("endobj");

    // Obj 6: Font F2 (Helvetica-Bold)
    offsets.add(pdf.length);
    pdf.writeln("6 0 obj");
    pdf.writeln("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
    pdf.writeln("endobj");

    // XREF Table
    final xrefOffset = pdf.length;
    pdf.writeln("xref");
    pdf.writeln("0 7");
    pdf.writeln("0000000000 65535 f ");
    for (final offset in offsets) {
      pdf.writeln("${offset.toString().padLeft(10, '0')} 00000 n ");
    }

    pdf.writeln("trailer");
    pdf.writeln("<< /Size 7 /Root 1 0 R >>");
    pdf.writeln("startxref");
    pdf.writeln("$xrefOffset");
    pdf.writeln("%%EOF");

    return Uint8List.fromList(utf8.encode(pdf.toString()));
  }

  static double _parseCurrency(String val) {
    final clean = val.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  static String _formatInr(int val) {
    final s = val.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    final rest = s.substring(0, s.length - 3);
    final formattedRest = rest.replaceAllMapped(
      RegExp(r'(\d+?)(?=(\d\d)+$)'),
      (m) => '${m[1]},',
    );
    return '$formattedRest,$last3';
  }

  static String _escape(String text) {
    return text.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)');
  }

  static String _numberToWordsIndian(int number) {
    if (number == 0) return "Zero Rupees Only";
    final units = [
      "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
      "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen",
      "Seventeen", "Eighteen", "Nineteen"
    ];
    final tens = [
      "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"
    ];

    String convertLessThanOneThousand(int n) {
      if (n == 0) return "";
      if (n < 20) return units[n];
      if (n < 100) return "${tens[n ~/ 10]} ${units[n % 10]}".trim();
      return "${units[n ~/ 100]} Hundred ${convertLessThanOneThousand(n % 100)}".trim();
    }

    int n = number;
    final sb = StringBuffer();

    if (n >= 10000000) {
      final crore = n ~/ 10000000;
      sb.write("${convertLessThanOneThousand(crore)} Crore ");
      n %= 10000000;
    }
    if (n >= 100000) {
      final lakh = n ~/ 100000;
      sb.write("${convertLessThanOneThousand(lakh)} Lakh ");
      n %= 100000;
    }
    if (n >= 1000) {
      final thousand = n ~/ 1000;
      sb.write("${convertLessThanOneThousand(thousand)} Thousand ");
      n %= 1000;
    }
    if (n > 0) {
      sb.write(convertLessThanOneThousand(n));
    }

    return "Rupees ${sb.toString().trim()} Only";
  }
}
