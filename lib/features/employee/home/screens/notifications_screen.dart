import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/local_notification_store.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/app_header.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../attendance/screens/attendance_screen.dart';
import '../../claims/screens/expense_claims_screen.dart';
import '../../communication/screens/communication_screen.dart';
import '../../documents/screens/documents_screen.dart';
import '../../grievance/screens/complaint_screen.dart';
import '../../leave/screens/leave_screen.dart';
import '../../letters/screens/digital_letters_screen.dart';
import '../../payslips/screens/payslips_screen.dart';
import '../../performance/screens/performance_screen.dart';
import '../../roster/screens/shift_roster_screen.dart';
import '../../documents/screens/document_request_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationController.instance.loadNotifications();
      // Mark all local FCM notifications as read when screen opens
      LocalNotificationStore.instance.markAllAsRead();
    });
  }

  void _handleFCMNotificationTap(dynamic item) {
    LocalNotificationStore.instance.removeNotification(item.id);
    NotificationController.instance.dismissAndRemoveNotification(item.id);
    final route = item.route ?? 'home';
    final context = this.context;

    // Navigate based on the route stored in the notification
    switch (route) {
      case 'attendance':
      case 'regularization':
        Navigator.push(context, CupertinoPageRoute(builder: (_) => const AttendanceScreen(initialTabIndex: 2)));
        break;
      case 'documents':
      case 'document':
        Navigator.push(context, CupertinoPageRoute(builder: (_) => const DocumentsScreen()));
        break;
      case 'leaves':
      case 'leave':
        Navigator.push(context, CupertinoPageRoute(builder: (_) => const LeaveScreen()));
        break;
      case 'payslip':
      case 'salary':
        Navigator.push(context, CupertinoPageRoute(builder: (_) => const PayslipsScreen()));
        break;
      case 'announcements':
      case 'communication':
        Navigator.push(context, CupertinoPageRoute(builder: (_) => const CommunicationScreen()));
        break;
      case 'expense':
        Navigator.push(context, CupertinoPageRoute(builder: (_) => const ExpenseClaimsScreen()));
        break;
      case 'letter':
        Navigator.push(context, CupertinoPageRoute(builder: (_) => const DigitalLettersScreen()));
        break;
      default:
        Navigator.pop(context); // Just dismiss the notification screen
        break;
    }
  }

  void _handleNotificationTap(NotificationItemModel item) {
    // 1. Permanently remove notification from all records, local state & DB
    NotificationController.instance.dismissAndRemoveNotification(item.id);

    // 2. Direct deep navigation to respective feature screen
    final lowerTitle = item.title.toLowerCase();
    final lowerMsg = item.message.toLowerCase();
    final combined = "$lowerTitle $lowerMsg";
    final nType = item.notificationType?.toUpperCase() ?? '';
    final eType = item.entityType?.toUpperCase() ?? '';

    Widget? targetScreen;

    if (nType == 'ATTENDANCE_REGULARIZATION' ||
        eType == 'ATTENDANCE_REGULARIZATION' ||
        combined.contains("regularization") ||
        combined.contains("regularize") ||
        combined.contains("regularized")) {
      // Direct deep navigation to Attendance Regularization Requests Tab
      targetScreen = const AttendanceScreen(initialTabIndex: 2);
    } else if (nType.contains('DOCUMENT') ||
        eType.contains('DOCUMENT') ||
        combined.contains("document") ||
        combined.contains("kyc") ||
        combined.contains("verified") ||
        combined.contains("verification") ||
        item.id.startsWith('doc-req-')) {
      targetScreen = const DocumentsScreen();
    } else if (combined.contains("leave")) {
      targetScreen = const LeaveScreen();
    } else if (combined.contains("payslip") || combined.contains("salary") || combined.contains("payroll")) {
      targetScreen = const PayslipsScreen();
    } else if (nType.contains('ANNOUNCEMENT') || nType.contains('COMMUNICATION') ||
        combined.contains("announcement") || combined.contains("townhall") || combined.contains("broadcast") ||
        combined.contains("holiday") || combined.contains("communication")) {
      targetScreen = const CommunicationScreen();
    } else if (combined.contains("shift") || combined.contains("roster") || combined.contains("schedule")) {
      targetScreen = const ShiftRosterScreen();
    } else if (combined.contains("expense") || combined.contains("claim") || combined.contains("reimbursement")) {
      targetScreen = const ExpenseClaimsScreen();
    } else if (combined.contains("document") || combined.contains("kyc") || combined.contains("verification")) {
      if (item.entityId != null && item.entityId!.isNotEmpty) {
        targetScreen = DocumentRequestDetailScreen(requestId: item.entityId!);
      } else {
        targetScreen = const DocumentsScreen();
      }
    } else if (combined.contains("letter") || combined.contains("appointment")) {
      targetScreen = const DigitalLettersScreen();
    } else if (combined.contains("performance") || combined.contains("goal") || combined.contains("okr")) {
      targetScreen = const PerformanceScreen();
    } else if (combined.contains("grievance") || combined.contains("complaint") || combined.contains("support") || combined.contains("ticket")) {
      targetScreen = const ComplaintScreen();
    } else if (combined.contains("check-in") || combined.contains("check-out") || combined.contains("attendance")) {
      targetScreen = const AttendanceScreen(initialTabIndex: 0);
    }

    if (targetScreen != null) {
      Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => targetScreen!),
      );
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month]}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationController.instance,
      builder: (context, _) {
        final controller = NotificationController.instance;
        final notifications = controller.notifications;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          body: SafeArea(
            child: Column(
              children: [
                AppHeader(
                  title: "Notifications",
                  subtitle: "Updates & Alerts",
                  rightAction: IconButton(
                    icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.white70, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: LocalNotificationStore.instance,
                    builder: (context, _) {
                      // Merge Supabase notifications with local FCM notifications
                      final localNotifs = LocalNotificationStore.instance.notifications;
                      final allNotifications = <_UnifiedNotification>[];

                      // Add Supabase notifications
                      for (final n in notifications) {
                        allNotifications.add(_UnifiedNotification(
                          id: n.id,
                          title: n.title,
                          body: n.message,
                          timestamp: n.timestamp,
                          isRead: n.isRead,
                          icon: n.icon,
                          source: 'supabase',
                          onTap: () => _handleNotificationTap(n),
                        ));
                      }

                      // Add local FCM notifications (skip duplicates)
                      for (final ln in localNotifs) {
                        final isDuplicate = allNotifications.any((existing) =>
                            existing.title == ln.title && existing.body == ln.body &&
                            existing.timestamp.difference(ln.timestamp).abs().inSeconds < 10);
                        if (!isDuplicate) {
                          allNotifications.add(_UnifiedNotification(
                            id: ln.id,
                            title: ln.title,
                            body: ln.body,
                            timestamp: ln.timestamp,
                            isRead: ln.isRead,
                            icon: CupertinoIcons.bell_fill,
                            source: 'push',
                            onTap: () => _handleFCMNotificationTap(ln),
                          ));
                        }
                      }

                      // Sort by newest first
                      allNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                      return controller.isLoading && allNotifications.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: AppColors.primary),
                                  SizedBox(height: 12),
                                  Text("Loading notifications...", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                ],
                              ),
                            )
                          : controller.hasError && allNotifications.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(CupertinoIcons.exclamationmark_circle, size: 44, color: AppColors.statusError),
                                        const SizedBox(height: 12),
                                        Text("Unable to load notifications", style: AppTypography.titleMedium),
                                        const SizedBox(height: 4),
                                        Text(
                                          controller.errorMessage ?? "Please check your network connection.",
                                          style: AppTypography.caption,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          icon: const Icon(CupertinoIcons.refresh, size: 16),
                                          label: const Text("Retry"),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: AppRadius.borderPill),
                                          ),
                                          onPressed: () => controller.loadNotifications(),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  color: AppColors.primary,
                                  onRefresh: () async {
                                    await controller.loadNotifications();
                                    await LocalNotificationStore.instance.initialize();
                                  },
                                  child: allNotifications.isEmpty
                                      ? ListView(
                                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                          children: const [
                                            SizedBox(height: 100),
                                            EmptyStateWidget(
                                              icon: CupertinoIcons.bell_slash,
                                              title: "No notifications",
                                              description: "You're all caught up! New updates will appear here.",
                                            ),
                                          ],
                                        )
                                      : Column(
                                          children: [
                                            if (allNotifications.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: AppSpacing.screenHorizontal,
                                                  vertical: 6,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(
                                                      "${allNotifications.length} notification${allNotifications.length > 1 ? 's' : ''}",
                                                      style: AppTypography.caption.copyWith(
                                                        color: AppColors.textMuted,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    TextButton.icon(
                                                      onPressed: () {
                                                        NotificationController.instance.clearAllNotifications();
                                                      },
                                                      icon: const Icon(CupertinoIcons.clear_thick, size: 13, color: AppColors.primary),
                                                      label: Text(
                                                        "Clear All",
                                                        style: AppTypography.caption.copyWith(
                                                          color: AppColors.primary,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            Expanded(
                                              child: ListView.builder(
                                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                                                itemCount: allNotifications.length,
                                                itemBuilder: (context, index) {
                                                  final item = allNotifications[index];
                                                  final isUnread = !item.isRead;
                                                  final isPush = item.source == 'push';

                                                  return Container(
                                                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                                                    child: Dismissible(
                                                      key: ValueKey(item.id),
                                                      direction: DismissDirection.endToStart,
                                                      background: Container(
                                                        alignment: Alignment.centerRight,
                                                        padding: const EdgeInsets.only(right: 20),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.statusError.withValues(alpha: 0.1),
                                                          borderRadius: AppRadius.borderMd,
                                                        ),
                                                        child: const Icon(CupertinoIcons.trash, color: AppColors.statusError),
                                                      ),
                                                      onDismissed: (_) {
                                                        NotificationController.instance.dismissAndRemoveNotification(item.id);
                                                      },
                                                      child: InkWell(
                                                        onTap: item.onTap,
                                                        borderRadius: AppRadius.borderMd,
                                                        child: AppCard(
                                                          padding: const EdgeInsets.all(16),
                                                          child: Row(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              // Unread dot indicator
                                                              Container(
                                                                width: 10,
                                                                height: 10,
                                                                margin: const EdgeInsets.only(top: 14, right: 12),
                                                                decoration: BoxDecoration(
                                                                  color: isUnread ? (isPush ? Colors.orange : AppColors.primary) : Colors.transparent,
                                                                  shape: BoxShape.circle,
                                                                ),
                                                              ),
                                                              // Notification Icon
                                                              Container(
                                                                width: 40,
                                                                height: 40,
                                                                decoration: BoxDecoration(
                                                                  color: isUnread ? (isPush ? const Color(0xFFFFF3E0) : AppColors.mintBg) : AppColors.slateBg,
                                                                  shape: BoxShape.circle,
                                                                ),
                                                                child: Center(
                                                                  child: Icon(
                                                                    item.icon,
                                                                    size: 18,
                                                                    color: isUnread ? (isPush ? const Color(0xFFF57C00) : AppColors.mintFg) : AppColors.textMuted,
                                                                  ),
                                                                ),
                                                              ),
                                                              AppSpacing.hGapMD,
                                                              // Title & Message Content
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Row(
                                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                                      children: [
                                                                        Expanded(
                                                                          child: Text(
                                                                            item.title,
                                                                            style: AppTypography.titleMedium.copyWith(
                                                                              fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                                                                              color: isUnread ? AppColors.textPrimary : AppColors.textSecondary,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        const SizedBox(width: 8),
                                                                        Text(
                                                                          _formatTimestamp(item.timestamp),
                                                                          style: AppTypography.overline.copyWith(
                                                                            color: isUnread ? AppColors.primary : AppColors.textMuted,
                                                                            fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    const SizedBox(height: 4),
                                                                    Text(
                                                                      item.body,
                                                                      style: AppTypography.bodySmall.copyWith(
                                                                        color: isUnread ? AppColors.textPrimary : AppColors.textMuted,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                  );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Unified notification model that merges Supabase and FCM notifications.
class _UnifiedNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final IconData icon;
  final String source;
  final VoidCallback? onTap;

  const _UnifiedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.isRead,
    required this.icon,
    required this.source,
    this.onTap,
  });
}
