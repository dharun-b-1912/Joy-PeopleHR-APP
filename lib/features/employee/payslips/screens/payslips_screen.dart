import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/payslip_pdf_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import 'payslip_detail_screen.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  @override
  void initState() {
    super.initState();
    MoreModulesController.instance.loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final payslips = controller.payslips;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("Payslips & Form 16", style: AppTypography.titleLarge),
          ),
          body: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: Colors.white,
            onRefresh: () => controller.loadAllData(),
            child: controller.isLoading && payslips.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : payslips.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        children: const [
                          SizedBox(height: 80),
                          EmptyStateWidget(
                            icon: CupertinoIcons.doc_text,
                            title: "No payslips available",
                            description: "Your monthly salary slips will appear here.",
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                        itemCount: payslips.length,
                        itemBuilder: (context, index) {
                          final item = payslips[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PayslipDetailScreen(payslip: item),
                                ),
                              );
                            },
                            borderRadius: AppRadius.borderMd,
                            child: AppCard(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.formattedPeriod,
                                          style: AppTypography.titleLarge,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            item.netPay,
                                            style: AppTypography.titleLarge.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            "Net Salary",
                                            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  AppSpacing.gapSM,
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 4,
                                    children: [
                                      Text("Gross: ${item.grossEarnings}", style: AppTypography.bodySmall),
                                      Text("Deductions: ${item.deductions}", style: AppTypography.bodySmall),
                                      Text("Paid on ${item.formattedPayDate}", style: AppTypography.caption),
                                    ],
                                  ),
                                  const Divider(height: 20, color: AppColors.borderSubtle),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(CupertinoIcons.eye, size: 14, color: AppColors.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            "View Payslip",
                                            style: AppTypography.bodySmall.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(CupertinoIcons.arrow_down_doc, size: 18, color: AppColors.textSecondary),
                                        onPressed: () async {
                                          final cleanName = "Payslip_${item.monthYear.replaceAll(' ', '_')}.pdf";
                                          final user = UserService.instance.currentUser;
                                          final ok = await PayslipPdfService.generateAndDownload(item, user: user);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(ok ? "✓ '$cleanName' downloaded" : "✓ Salary Slip downloaded"),
                                                backgroundColor: AppColors.primary,
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        );
      },
    );
  }
}
