import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/payslip_pdf_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';

class PayslipDetailScreen extends StatelessWidget {
  final PayslipModel payslip;

  const PayslipDetailScreen({super.key, required this.payslip});

  @override
  Widget build(BuildContext context) {
    final user = UserService.instance.currentUser;
    final empName = payslip.employeeName.isNotEmpty
        ? payslip.employeeName
        : (user.name.isNotEmpty ? user.name : "—");

    // Employee ID: Never render database UUID. Always use employee code.
    String empId = payslip.displayEmployeeId;
    if (empId == 'Employee ID unavailable' && user.displayEmployeeId != 'Employee ID unavailable') {
      empId = user.displayEmployeeId;
    }

    final periodDisplay = payslip.formattedPeriod;
    final payDateDisplay = payslip.formattedPayDate;

    final companyName = user.companyName?.isNotEmpty == true
        ? user.companyName!
        : (user.organizationName?.isNotEmpty == true ? user.organizationName! : "—");
    final totalDeductionsVal = double.tryParse(payslip.deductions.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final pfVal = payslip.pfDeduction;
    final ptVal = payslip.profTaxDeduction;
    final tdsVal = (totalDeductionsVal - pfVal - ptVal) > 0 ? (totalDeductionsVal - pfVal - ptVal) : payslip.incomeTaxDeduction;
    final hasDeductions = totalDeductionsVal > 0 || pfVal > 0 || ptVal > 0 || tdsVal > 0 || payslip.deductionsComponents.isNotEmpty;

    // Validate calculations and log diagnostic notice if mismatch detected
    if (!payslip.validateCalculations()) {
      // ignore: avoid_print
      print('[DIAGNOSTICS] PAYSLIP_CALCULATION_MISMATCH for payslip ${payslip.id}');
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("$periodDisplay Payslip", style: AppTypography.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_down_doc, color: AppColors.primary),
            onPressed: () => _downloadPdf(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER SUMMARY CARD ---
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(companyName, style: AppTypography.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                            Text("Official Monthly Salary Slip", style: AppTypography.caption),
                          ],
                        ),
                      ),
                      const StatusChip(label: "Paid", type: StatusType.success),
                    ],
                  ),
                  const Divider(height: 24, color: AppColors.borderSubtle),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildPayHeaderCol("EMPLOYEE NAME", empName),
                      _buildPayHeaderCol("EMPLOYEE ID", empId),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildPayHeaderCol("DESIGNATION", payslip.designation.isNotEmpty ? payslip.designation : user.designation),
                      _buildPayHeaderCol("PAY DATE", payDateDisplay),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildPayHeaderCol("PAYABLE DAYS", "${payslip.payableDays % 1 == 0 ? payslip.payableDays.toInt() : payslip.payableDays} Days"),
                      _buildPayHeaderCol("LOP / UNPAID", "${payslip.lopDays % 1 == 0 ? payslip.lopDays.toInt() : payslip.lopDays} Days"),
                    ],
                  ),
                ],
              ),
            ),
            AppSpacing.gapLG,

            // --- EARNINGS BREAKDOWN ---
            Text("Earnings Breakdown", style: AppTypography.titleMedium),
            AppSpacing.gapMD,
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (payslip.earningsComponents.isNotEmpty) ...[
                    for (final comp in payslip.earningsComponents) ...[
                      _buildAmountRow(
                        comp['name']?.toString() ?? 'Earnings',
                        "₹${((comp['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}",
                      ),
                      const SizedBox(height: 10),
                    ],
                  ] else ...[
                    _buildAmountRow("Basic Salary", payslip.basicSalary > 0 ? "₹${payslip.basicSalary.toInt()}" : "₹0"),
                    const SizedBox(height: 10),
                    _buildAmountRow("House Rent Allowance (HRA)", payslip.hra > 0 ? "₹${payslip.hra.toInt()}" : "₹0"),
                    const SizedBox(height: 10),
                    _buildAmountRow("Special Allowance", payslip.specialAllowance > 0 ? "₹${payslip.specialAllowance.toInt()}" : "₹0"),
                    const SizedBox(height: 10),
                  ],
                  const Divider(height: 16, color: AppColors.borderSubtle),
                  _buildAmountRow("Gross Salary Earnings", payslip.grossEarnings, isBold: true),
                ],
              ),
            ),
            AppSpacing.gapLG,

            // --- DEDUCTIONS BREAKDOWN ---
            Text("DEDUCTIONS", style: AppTypography.titleMedium),
            AppSpacing.gapMD,
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (payslip.deductionsComponents.isNotEmpty) ...[
                    for (final comp in payslip.deductionsComponents) ...[
                      _buildAmountRow(
                        comp['name']?.toString() ?? 'Deduction',
                        "₹${((comp['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}",
                      ),
                      const SizedBox(height: 10),
                    ],
                  ] else if (hasDeductions) ...[
                    if (pfVal > 0) ...[
                      _buildAmountRow("Provident Fund (EPF)", "₹${pfVal.toInt()}"),
                      const SizedBox(height: 10),
                    ],
                    if (ptVal > 0) ...[
                      _buildAmountRow("Professional Tax (PT)", "₹${ptVal.toInt()}"),
                      const SizedBox(height: 10),
                    ],
                    if (tdsVal > 0) ...[
                      _buildAmountRow("Income Tax (TDS)", "₹${tdsVal.toInt()}"),
                      const SizedBox(height: 10),
                    ],
                  ] else ...[
                    _buildAmountRow("Nil Deductions", "₹0", color: AppColors.textSecondary),
                    const SizedBox(height: 10),
                  ],
                  const Divider(height: 16, color: AppColors.borderSubtle),
                  _buildAmountRow("Total Deductions", payslip.deductions, isBold: true, color: AppColors.statusError),
                ],
              ),
            ),
            AppSpacing.gapLG,

            // --- NET PAYABLE CARD ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: AppRadius.borderLg,
                boxShadow: AppShadows.softCard,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("NET PAYABLE SALARY", style: AppTypography.caption.copyWith(color: Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("Credited to Salary Account", style: AppTypography.caption.copyWith(color: Colors.white60)),
                    ],
                  ),
                  Text(
                    payslip.netPay,
                    style: AppTypography.metricLarge.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            AppSpacing.gapLG,

            // --- DOWNLOAD PDF BUTTON ---
            AppButton(
              label: "Download PDF Payslip",
              icon: CupertinoIcons.arrow_down_doc,
              isFullWidth: true,
              variant: AppButtonVariant.primaryPill,
              onPressed: () => _downloadPdf(context),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadPdf(BuildContext context) async {
    final cleanName = "Payslip_${payslip.monthYear.replaceAll(' ', '_')}.pdf";
    final user = UserService.instance.currentUser;
    final ok = await PayslipPdfService.generateAndDownload(payslip, user: user);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? "✓ '$cleanName' downloaded successfully" : "✓ Salary Slip downloaded"),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildPayHeaderCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.overline),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildAmountRow(String label, String amount, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold)
              : AppTypography.bodySmall,
        ),
        Text(
          amount,
          style: isBold
              ? AppTypography.bodyRegular.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color ?? AppColors.textPrimary,
                )
              : AppTypography.bodySmall.copyWith(color: color),
        ),
      ],
    );
  }
}
