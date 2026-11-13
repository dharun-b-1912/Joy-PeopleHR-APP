import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/app_version_service.dart';
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
import '../../locations/screens/employee_location_screen.dart';
import '../../payslips/screens/payslips_screen.dart';
import '../../performance/screens/performance_screen.dart';
import '../../roster/screens/shift_roster_screen.dart';
import '../../attendance/screens/attendance_screen.dart';
import '../../attendance/screens/my_day_timeline_screen.dart';
import '../../attendance/screens/work_hours_summary_screen.dart';
import '../../attendance/screens/break_history_screen.dart';
import '../../lms/screens/employee_lms_catalog_screen.dart';
import '../../../garment/repositories/garment_repository.dart';
import '../../../garment/screens/supervisor_garment_hub_screen.dart';
import '../../../garment/screens/worker_garment_earnings_screen.dart';
import '../../../face_attend/services/face_attend_service.dart';
import '../../../face_attend/screens/face_enrolment_screen.dart';

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
    GarmentRepository.instance.checkEntitlement();
    FaceAttendService.instance.fetchTenantStatus();
  }

  void _navigateToModule(BuildContext context, String id) {
    Widget target;
    switch (id) {
      case 'face_attend_enrolment':
        target = const FaceEnrolmentScreen();
        break;
      case 'garment_supervisor':
        target = const SupervisorGarmentHubScreen();
        break;
      case 'garment_earnings':
        target = const WorkerGarmentEarningsScreen();
        break;
      case 'locations':
      case 'location':
        target = const EmployeeLocationScreen();
        break;
      case 'my_day_timeline':
        target = const MyDayTimelineScreen();
        break;
      case 'attendance_calendar':
        target = const AttendanceScreen(initialTabIndex: 1);
        break;
      case 'work_hours_summary':
        target = const WorkHoursSummaryScreen();
        break;
      case 'break_history':
        target = const BreakHistoryScreen();
        break;
      case 'regularization':
        target = const AttendanceScreen(initialTabIndex: 2);
        break;
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
      case 'lms':
      case 'learning':
      case 'training':
      case 'courses':
        target = const EmployeeLmsCatalogScreen();
        break;
      default:
        target = const ShiftRosterScreen();
    }
    Navigator.push(context, CupertinoPageRoute(builder: (_) => target));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        MoreModulesController.instance,
        GarmentRepository.instance,
        FaceAttendService.instance,
      ]),
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final garmentRepo = GarmentRepository.instance;
        final faceAttend = FaceAttendService.instance;

        // Categorized modules catalog
        final sections = [
          if (faceAttend.status.isEntitled)
            {
              'title': 'JOY FaceAttend',
              'modules': [
                {
                  'id': 'face_attend_enrolment',
                  'title': 'Face Enrolment & Privacy',
                  'subtitle': faceAttend.status.templateStatus == 'ACTIVE'
                      ? 'Enrolled & Active'
                      : (faceAttend.status.templateStatus ?? 'Tap to consent & enrol'),
                  'icon': CupertinoIcons.person_crop_circle_badge_checkmark,
                  'bg': AppColors.skyBg,
                  'fg': AppColors.skyFg,
                  'badge': faceAttend.offlinePendingCount > 0
                      ? '${faceAttend.offlinePendingCount} Queued'
                      : 'Add-On',
                  'badgeType': faceAttend.offlinePendingCount > 0
                      ? StatusType.warning
                      : StatusType.success,
                },
              ],
            },
          if (garmentRepo.isEntitled)
            {
              'title': 'Garment & Piece-Rate',
              'modules': [
                if (garmentRepo.isSupervisorUser())
                  {
                    'id': 'garment_supervisor',
                    'title': 'Supervisor Floor Hub',
                    'subtitle': 'Daily attendance, QC & piece output',
                    'icon': CupertinoIcons.scissors,
                    'bg': AppColors.mintBg,
                    'fg': AppColors.mintFg,
                    'badge': (garmentRepo.queuedAttendanceCount + garmentRepo.queuedProductionCount) > 0
                        ? '${garmentRepo.queuedAttendanceCount + garmentRepo.queuedProductionCount} Offline'
                        : 'Add-On',
                    'badgeType': (garmentRepo.queuedAttendanceCount + garmentRepo.queuedProductionCount) > 0
                        ? StatusType.warning
                        : StatusType.success,
                  },
                {
                  'id': 'garment_earnings',
                  'title': 'My Garment Earnings',
                  'subtitle': 'Piece ledger, QC & payslips',
                  'icon': CupertinoIcons.money_dollar_circle_fill,
                  'bg': AppColors.skyBg,
                  'fg': AppColors.skyFg,
                  'badge': null,
                  'badgeType': StatusType.info,
                },
              ],
            },
          {
            'title': 'Attendance & Time',
            'modules': [
              {
                'id': 'my_day_timeline',
                'title': 'My Day Timeline',
                'subtitle': 'Complete work, break & attendance history',
                'icon': CupertinoIcons.time_solid,
                'bg': AppColors.mintBg,
                'fg': AppColors.mintFg,
                'badge': 'Live',
                'badgeType': StatusType.success,
              },
              {
                'id': 'attendance_calendar',
                'title': 'Attendance Calendar',
                'subtitle': 'Monthly status & daily view',
                'icon': CupertinoIcons.calendar,
                'bg': AppColors.skyBg,
                'fg': AppColors.skyFg,
                'badge': null,
                'badgeType': StatusType.info,
              },
              {
                'id': 'work_hours_summary',
                'title': 'Work Hours Summary',
                'subtitle': 'Daily, weekly & monthly payable hours',
                'icon': CupertinoIcons.chart_bar_alt_fill,
                'bg': AppColors.mintBg,
                'fg': AppColors.mintFg,
                'badge': null,
                'badgeType': StatusType.info,
              },
              {
                'id': 'break_history',
                'title': 'Break History',
                'subtitle': 'Tea, lunch & break logs (30 days)',
                'icon': Icons.emoji_food_beverage_rounded,
                'bg': AppColors.peachBg,
                'fg': AppColors.peachFg,
                'badge': null,
                'badgeType': StatusType.info,
              },
              {
                'id': 'regularization',
                'title': 'Attendance Regularization',
                'subtitle': 'Missing punch or correction requests',
                'icon': CupertinoIcons.arrow_2_circlepath,
                'bg': AppColors.skyBg,
                'fg': AppColors.skyFg,
                'badge': null,
                'badgeType': StatusType.info,
              },
            ],
          },
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
              {
                'id': 'locations',
                'title': 'Locations',
                'subtitle': 'Live GPS & travel timeline',
                'icon': CupertinoIcons.location_solid,
                'bg': AppColors.mintBg,
                'fg': AppColors.mintFg,
                'badge': 'Live',
                'badgeType': StatusType.success,
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
            'title': 'Employee Services',
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
              {
                'id': 'lms',
                'title': 'Learning & LMS',
                'subtitle': 'YouTube courses & assessments',
                'icon': CupertinoIcons.book_fill,
                'bg': AppColors.skyBg,
                'fg': AppColors.skyFg,
                'badge': 'Training',
                'badgeType': StatusType.success,
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
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: AppColors.moreHeaderGradient,
                  ),
                  child: const AppHeader(
                    transparent: true,
                    subtitle: "All Employee Services",
                    title: "More",
                  ),
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
                        "JOY PeopleHR • People & Culture",
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const AppVersionBadge(),
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
