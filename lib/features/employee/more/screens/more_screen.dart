import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/app_header.dart';
import '../../../../widgets/core/status_chip.dart';
import '../../claims/screens/expense_claims_screen.dart';
import '../../communication/screens/communication_screen.dart';
import '../../documents/screens/documents_screen.dart';
import '../../grievance/screens/complaint_screen.dart';
import '../../helpdesk/screens/helpdesk_screen.dart';
import '../../letters/screens/digital_letters_screen.dart';
import '../../payslips/screens/payslips_screen.dart';
import '../../performance/screens/performance_screen.dart';
import '../../roster/screens/shift_roster_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  @override
  void initState() {
    super.initState();
    MoreModulesController.instance.initialize();
  }

  void _navigateToModule(BuildContext context, String id) {
    Widget target;
    switch (id) {
      case 'roster':
        target = const ShiftRosterScreen();
        break;
      case 'payslip':
        target = const PayslipsScreen();
        break;
      case 'expense':
      case 'claims':
        target = const ExpenseClaimsScreen();
        break;
      case 'helpdesk':
        target = const HelpdeskScreen();
        break;
      case 'complaint':
        target = const ComplaintScreen();
        break;
      case 'letters':
        target = const DigitalLettersScreen();
        break;
      case 'docs':
        target = const DocumentsScreen();
        break;
      case 'announcements':
      case 'communication':
        target = const CommunicationScreen();
        break;
      case 'performance':
      case 'okrs':
      case 'goals':
        target = const PerformanceScreen();
        break;
      default:
        target = const ShiftRosterScreen();
    }
    Navigator.push(context, CupertinoPageRoute(builder: (_) => target));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;

        // Categorized modules catalog
        final sections = [
          {
            'title': 'Work & Schedule',
            'modules': [
              {
                'id': 'roster',
                'title': 'Shift Roster',
                'subtitle': 'Weekly schedule & shifts',
                'icon': CupertinoIcons.square_grid_2x2,
                'bg': AppColors.mintBg,
                'fg': AppColors.mintFg,
                'badge': null,
                'badgeType': StatusType.info,
              },
            ],
          },
          {
            'title': 'Payroll & Finance',
            'modules': [
              {
                'id': 'payslip',
                'title': 'Payslips & Form 16',
                'subtitle': 'Salary statements & tax',
                'icon': CupertinoIcons.doc_text,
                'bg': AppColors.skyBg,
                'fg': AppColors.skyFg,
                'badge': null,
                'badgeType': StatusType.info,
              },
              {
                'id': 'expense',
                'title': 'Expense Claims',
                'subtitle': 'Reimbursements & claims',
                'icon': CupertinoIcons.money_dollar_circle,
                'bg': AppColors.peachBg,
                'fg': AppColors.peachFg,
                'badge': controller.pendingClaimsCount > 0 ? "${controller.pendingClaimsCount} Pending" : null,
                'badgeType': StatusType.warning,
              },
            ],
          },
          {
            'title': 'HR Services & Support',
            'modules': [
              {
                'id': 'helpdesk',
                'title': 'HR Helpdesk',
                'subtitle': 'Support & inquiries',
                'icon': CupertinoIcons.question_circle_fill,
                'bg': AppColors.skyBg,
                'fg': AppColors.skyFg,
                'badge': controller.openTicketsCount > 0 ? "${controller.openTicketsCount} Active" : null,
                'badgeType': StatusType.info,
              },
              {
                'id': 'complaint',
                'title': 'Grievance / Complaint',
                'subtitle': 'Formal workplace cases',
                'icon': CupertinoIcons.exclamationmark_triangle,
                'bg': AppColors.alertBg,
                'fg': AppColors.alertFg,
                'badge': controller.pendingGrievancesCount > 0 ? "${controller.pendingGrievancesCount} Under Review" : null,
                'badgeType': StatusType.info,
              },
            ],
          },
          {
            'title': 'Documents & Records',
            'modules': [
              {
                'id': 'letters',
                'title': 'Digital Letters',
                'subtitle': 'HR & Offer letters',
                'icon': CupertinoIcons.rosette,
                'bg': AppColors.skyBg,
                'fg': AppColors.skyFg,
                'badge': null,
                'badgeType': StatusType.info,
              },
              {
                'id': 'docs',
                'title': 'Documents',
                'subtitle': 'Company & Personal',
                'icon': CupertinoIcons.folder,
                'bg': AppColors.mintBg,
                'fg': AppColors.mintFg,
                'badge': controller.actionRequiredDocsCount > 0 ? "${controller.actionRequiredDocsCount} Action Required" : null,
                'badgeType': StatusType.error,
              },
            ],
          },
          {
            'title': 'Company & Growth',
            'modules': [
              {
                'id': 'announcements',
                'title': 'Communication',
                'subtitle': 'Company Broadcasts',
                'icon': CupertinoIcons.speaker_2,
                'bg': AppColors.lavenderBg,
                'fg': AppColors.lavenderFg,
                'badge': controller.unreadCommunicationsCount > 0
                    ? "${controller.unreadCommunicationsCount} New"
                    : null,
                'badgeType': StatusType.info,
              },
              {
                'id': 'performance',
                'title': 'Performance & Goals',
                'subtitle': 'Quarterly OKRs & Targets',
                'icon': CupertinoIcons.scope,
                'bg': AppColors.mintBg,
                'fg': AppColors.mintFg,
                'badge': controller.goals.isNotEmpty ? "${controller.goals.length} Goals" : null,
                'badgeType': StatusType.info,
              },
            ],
          },
        ];

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: AppSpacing.bottomNavClearance),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppHeader(
                  subtitle: "All Employee Services",
                  title: "More",
                ),
                AppSpacing.gapSM,
                ...sections.map((section) {
                  final title = section['title'] as String;
                  final rawModules = section['modules'] as List<Map<String, dynamic>>;

                  final filteredModules = rawModules.where((item) {
                    final id = item['id'] as String;
                    if (controller.serviceConfigs.isNotEmpty) {
                      final cfg = controller.serviceConfigs.where((c) => c.serviceId == id).firstOrNull;
                      if (cfg != null && (!cfg.isEnabled || !cfg.isVisibleToEmployee)) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();

                  if (filteredModules.isEmpty) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.screenHorizontal,
                      right: AppSpacing.screenHorizontal,
                      bottom: AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 6),
                          child: Text(
                            title.toUpperCase(),
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        ...filteredModules.map((item) {
                          final badgeText = item['badge'] as String?;
                          final badgeType = item['badgeType'] as StatusType;

                          return Container(
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: AppCard(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              onTap: () => _navigateToModule(context, item['id'] as String),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: item['bg'] as Color,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(item['icon'] as IconData, color: item['fg'] as Color, size: 22),
                                  ),
                                  AppSpacing.hGapMD,
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['title'] as String,
                                          style: AppTypography.titleMedium,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          item['subtitle'] as String,
                                          style: AppTypography.bodySmall,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (badgeText != null) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: StatusChip(
                                        label: badgeText,
                                        type: badgeType,
                                      ),
                                    ),
                                    AppSpacing.hGapSM,
                                  ],
                                  const Icon(CupertinoIcons.chevron_forward, size: 16, color: AppColors.textMuted),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }),
                AppSpacing.gapLG,
                Center(
                  child: Column(
                    children: [
                      Text(
                        "JOY PeopleHR Enterprise Mobile",
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.slateBg,
                          borderRadius: AppRadius.borderPill,
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Text(
                          "v1.0.0 (Build 5)",
                          style: AppTypography.overline.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapLG,
              ],
            ),
          ),
        );
      },
    );
  }
}
