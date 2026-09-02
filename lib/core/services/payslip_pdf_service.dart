import 'dart:convert';
import 'dart:typed_data';
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
    final bytes = generatePdfBytes(payslip, user: user);
    final cleanMonth = payslip.monthYear.replaceAll(' ', '_');
    final empCode = payslip.employeeId.isNotEmpty
        ? payslip.employeeId
        : (user?.employeeId.isNotEmpty == true ? user!.employeeId : 'Employee');
    final fileName = "Payslip_${cleanMonth}_$empCode.pdf";

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
        : (user?.organizationName?.isNotEmpty == true ? user!.organizationName! : '—');

    // 2. Employee Profile Details
    final empName = payslip.employeeName.isNotEmpty
        ? payslip.employeeName
        : (user?.name.isNotEmpty == true ? user!.name : '—');
    final empCode = payslip.employeeId.isNotEmpty
        ? payslip.employeeId
        : (user?.employeeId.isNotEmpty == true ? user!.employeeId : '—');
    final dept = user?.department.isNotEmpty == true ? user!.department : '—';
    final desig = payslip.designation.isNotEmpty
        ? payslip.designation
        : (user?.designation.isNotEmpty == true ? user!.designation : '—');
    final payDate = payslip.payDate.isNotEmpty ? payslip.payDate : '—';
    final payPeriod = payslip.monthYear.isNotEmpty ? payslip.monthYear : '—';

    // 3. Financial Computations
    final basic = payslip.basicSalary;
    final hra = payslip.hra;
    final special = payslip.specialAllowance;
    double gross = _parseCurrency(payslip.grossEarnings);
    if (gross <= 0 && (basic > 0 || hra > 0 || special > 0)) {
      gross = basic + hra + special;
    }

    final pf = payslip.pfDeduction;
    final pt = payslip.profTaxDeduction;
    final incomeTax = payslip.incomeTaxDeduction;
    
    // Parse deductions and net pay from payslip model or calculate
    double totalDeductions = _parseCurrency(payslip.deductions);
    if (totalDeductions <= 0 && (pf > 0 || pt > 0 || incomeTax > 0)) {
      totalDeductions = pf + pt + incomeTax;
    }
    
    // Compute exact TDS as residual if needed
    final tds = (totalDeductions - pf - pt) > 0 ? (totalDeductions - pf - pt) : incomeTax;
    
    double netPay = _parseCurrency(payslip.netPay);
    if (netPay <= 0 && gross > 0) {
      netPay = gross - totalDeductions;
    }

    final netPayStr = "Rs. ${_formatInr(netPay.toInt())}";
    final netInWords = _numberToWordsIndian(netPay.toInt());

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
    sb.writeln("q 0.96 0.97 0.98 rg 0.86 0.88 0.90 RG 1 w 40 635 515 85 re B Q");

    // Column 1: Labels & Values
    writeText(55, 698, "F2", 8.5, 0.45, 0.45, 0.45, "EMPLOYEE NAME:");
    writeText(155, 698, "F2", 9.0, 0.1, 0.1, 0.1, empName);

    writeText(55, 680, "F2", 8.5, 0.45, 0.45, 0.45, "EMPLOYEE ID:");
    writeText(155, 680, "F1", 9.0, 0.1, 0.1, 0.1, empCode);

    writeText(55, 662, "F2", 8.5, 0.45, 0.45, 0.45, "DEPARTMENT:");
    writeText(155, 662, "F1", 9.0, 0.1, 0.1, 0.1, dept);

    writeText(55, 644, "F2", 8.5, 0.45, 0.45, 0.45, "DESIGNATION:");
    writeText(155, 644, "F1", 9.0, 0.1, 0.1, 0.1, desig);

    // Column 2: Labels & Values
    writeText(330, 698, "F2", 8.5, 0.45, 0.45, 0.45, "PAYABLE DAYS:");
    writeText(430, 698, "F1", 9.0, 0.1, 0.1, 0.1, "30 Days");

    writeText(330, 680, "F2", 8.5, 0.45, 0.45, 0.45, "PAYMENT MODE:");
    writeText(430, 680, "F2", 9.0, 0.05, 0.45, 0.25, "Direct Transfer (Settled)");

    writeText(330, 662, "F2", 8.5, 0.45, 0.45, 0.45, "CURRENCY:");
    writeText(430, 662, "F1", 9.0, 0.1, 0.1, 0.1, "INR (Indian Rupee)");

    writeText(330, 644, "F2", 8.5, 0.45, 0.45, 0.45, "STATEMENT REF:");
    writeText(430, 644, "F1", 8.5, 0.3, 0.3, 0.3, "PS-$payPeriod-$empCode");

    // --- EARNINGS & DEDUCTIONS DUAL TABLES ---
    // Earnings Table Header (Teal / Emerald)
    sb.writeln("q 0.05 0.36 0.23 rg 40 598 250 22 re f Q");
    writeText(50, 605, "F2", 9.5, 1.0, 1.0, 1.0, "EARNINGS");
    writeText(220, 605, "F2", 9.5, 1.0, 1.0, 1.0, "AMOUNT");

    // Deductions Table Header (Rose / Crimson)
    sb.writeln("q 0.75 0.20 0.20 rg 305 598 250 22 re f Q");
    writeText(315, 605, "F2", 9.5, 1.0, 1.0, 1.0, "DEDUCTIONS");
    writeText(485, 605, "F2", 9.5, 1.0, 1.0, 1.0, "AMOUNT");

    // Row 1 (Zebra Light Background)
    sb.writeln("q 0.97 0.97 0.97 rg 40 576 250 22 re f 305 576 250 22 re f Q");
    writeText(50, 583, "F1", 9.0, 0.15, 0.15, 0.15, "Basic Salary");
    writeText(220, 583, "F2", 9.0, 0.1, 0.1, 0.1, "Rs. ${_formatInr(basic.toInt())}");
    writeText(315, 583, "F1", 9.0, 0.15, 0.15, 0.15, "Provident Fund (EPF)");
    writeText(485, 583, "F2", 9.0, 0.1, 0.1, 0.1, "Rs. ${_formatInr(pf.toInt())}");

    // Row 2 (White Background)
    writeText(50, 561, "F1", 9.0, 0.15, 0.15, 0.15, "House Rent Allowance (HRA)");
    writeText(220, 561, "F2", 9.0, 0.1, 0.1, 0.1, "Rs. ${_formatInr(hra.toInt())}");
    writeText(315, 561, "F1", 9.0, 0.15, 0.15, 0.15, "Professional Tax (PT)");
    writeText(485, 561, "F2", 9.0, 0.1, 0.1, 0.1, "Rs. ${_formatInr(pt.toInt())}");

    // Row 3 (Zebra Light Background)
    sb.writeln("q 0.97 0.97 0.97 rg 40 532 250 22 re f 305 532 250 22 re f Q");
    writeText(50, 539, "F1", 9.0, 0.15, 0.15, 0.15, "Special Allowance");
    writeText(220, 539, "F2", 9.0, 0.1, 0.1, 0.1, "Rs. ${_formatInr(special.toInt())}");
    writeText(315, 539, "F1", 9.0, 0.15, 0.15, 0.15, "Income Tax (TDS)");
    writeText(485, 539, "F2", 9.0, 0.1, 0.1, 0.1, "Rs. ${_formatInr(tds.toInt())}");

    // Table Outlines
    sb.writeln("q 0.85 0.85 0.85 RG 1 w 40 532 250 88 re S 305 532 250 88 re S Q");

    // --- TOTALS BAR ---
    sb.writeln("q 0.93 0.95 0.96 rg 0.75 0.75 0.75 RG 1 w 40 505 250 24 re B 305 505 250 24 re B Q");
    writeText(50, 513, "F2", 9.5, 0.05, 0.36, 0.23, "Gross Salary Earnings:");
    writeText(215, 513, "F2", 9.5, 0.05, 0.36, 0.23, "Rs. ${_formatInr(gross.toInt())}");
    writeText(315, 513, "F2", 9.5, 0.75, 0.20, 0.20, "Total Deductions:");
    writeText(480, 513, "F2", 9.5, 0.75, 0.20, 0.20, "Rs. ${_formatInr(totalDeductions.toInt())}");

    // --- NET PAYABLE SALARY HIGHLIGHT BOX ---
    sb.writeln("q 0.05 0.36 0.23 rg 40 425 515 62 re f Q");
    writeText(55, 465, "F2", 11.0, 1.0, 1.0, 1.0, "NET PAYABLE SALARY TRANSFERRED:");
    writeText(370, 461, "F2", 16.0, 1.0, 1.0, 1.0, netPayStr);
    writeText(55, 440, "F1", 9.0, 0.85, 0.95, 0.90, "Amount in Words: $netInWords");

    // --- LEGAL & STATUTORY FOOTER ---
    writeText(40, 385, "F1", 8.0, 0.45, 0.45, 0.45, "*** This is a computer-generated payslip and does not require a physical signature. ***");
    writeText(40, 372, "F1", 7.5, 0.55, 0.55, 0.55, "Authorized by $companyName • Generated on: ${DateTime.now().toUtc().toIso8601String().substring(0, 10)}");
    writeText(40, 360, "F1", 7.5, 0.55, 0.55, 0.55, "JOY PeopleHR Enterprise Compensation Engine • Authenticated Digital Record");

    // Divider Line
    sb.writeln("q 0.85 0.85 0.85 RG 1 w 40 345 m 555 345 l S Q");

    // Signatory Block
    writeText(390, 305, "F2", 9.0, 0.2, 0.2, 0.2, "For $companyName");
    writeText(390, 275, "F1", 8.0, 0.4, 0.4, 0.4, "Authorized Signatory");

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
