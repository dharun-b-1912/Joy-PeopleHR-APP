import 'dart:async';
import 'package:flutter/cupertino.dart';
// flutter/foundation not needed — debugPrint available via cupertino
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/theme/klarna_tokens.dart';
import '../../core/services/user_service.dart';
import '../../core/utils/query_timeout.dart';
import '../../core/utils/secure_log.dart';
import '../../models/employee_models.dart';
import '../interfaces/employee_repository.dart';

/// WorkForceOS — Supabase Notification Repository (schema-aligned)
///
/// Tables used:
///   notification_events — unified notification + announcement bus
///       Canonical columns: id, organization_id, recipient_user_id,
///       channel, title, message, action_url, is_read, is_sent, sent_at, created_at
///
/// Broadcast announcements: recipient_user_id IS NULL, channel = 'IN_APP'
/// Targeted notifications: recipient_user_id = user_profiles.id, channel = 'IN_APP' or 'PUSH'
///
/// Note: notification_events does NOT have: body, event_type, metadata,
///       resource_id, category, severity — do not reference these.
class SupabaseNotificationRepository implements INotificationRepository {
  SupabaseClient get _client => Supabase.instance.client;

  static bool _isValidUuid(String? str) {
    if (str == null || str.isEmpty) return false;
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(str.trim());
  }

  @override
  Future<List<NotificationItemModel>> getNotifications(String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) {
        return [];
      }

      final authUid = _client.auth.currentUser?.id;
      final user = UserService.instance.currentUser;
      final targetId = (user.employeeUuid?.isNotEmpty == true) ? user.employeeUuid! : employeeId;

      final List<NotificationItemModel> list = [];

      // 1. Resolve user profile ID from auth user ID
      String? userProfileId;
      if (authUid != null && _isValidUuid(authUid)) {
        try {
          final profileRow = await withTimeout(
            _client.from('user_profiles').select('id').or('auth_user_id.eq.$authUid,id.eq.$authUid').maybeSingle(),
          );
          userProfileId = profileRow?['id']?.toString();
        } catch (_) {}
      }

      // 2. Direct Notification Events targeted to this employee or broadcast (canonical table: notification_events)
      try {
        final orFilters = <String>{
          if (userProfileId != null && _isValidUuid(userProfileId)) 'recipient_user_id.eq.$userProfileId',
          if (targetId.isNotEmpty && _isValidUuid(targetId)) 'recipient_user_id.eq.$targetId',
          if (authUid != null && _isValidUuid(authUid)) 'recipient_user_id.eq.$authUid',
          'recipient_user_id.is.null',
        }.join(',');

        final eventQuery = _client
            .from('notification_events')
            .select('*');

        final eventRows = await withTimeout(
          orFilters.isNotEmpty
              ? eventQuery.or(orFilters).order('created_at', ascending: false).limit(40)
              : eventQuery.order('created_at', ascending: false).limit(40),
        );

        for (final ev in eventRows) {
          final evId = ev['id']?.toString() ?? 'ev-${ev['created_at']}';
          final createdAt = DateTime.tryParse(ev['created_at']?.toString() ?? '') ?? DateTime.now();
          final isRead = ev['is_read'] == true;
          final title = _sOr(ev['title'], 'Notification');
          final message = _sOr(ev['message'], '');
          final recipient = ev['recipient_user_id']?.toString();

          // Privacy guard: Personal & supervisor alerts (check-in/out, leave/regularization approvals,
          // payslips, individual training reminders) must NEVER leak as broadcast alerts when recipient is null.
          final hay = '$title $message'.toLowerCase();
          final isPersonalOrScopedAlert = hay.contains('check-in') ||
              hay.contains('checkin') ||
              hay.contains('check-out') ||
              hay.contains('checkout') ||
              hay.contains('late') ||
              hay.contains('punch') ||
              hay.contains('regularization') ||
              hay.contains('leave application') ||
              hay.contains('leave approved') ||
              hay.contains('leave rejected') ||
              hay.contains('payslip') ||
              hay.contains('training pending') ||
              hay.contains('your mandatory training') ||
              hay.contains('your break');

          if (isPersonalOrScopedAlert && (recipient == null || recipient.isEmpty)) {
            continue;
          }

          list.add(
            NotificationItemModel(
              id: evId,
              title: title,
              message: message,
              timestamp: createdAt,
              isRead: isRead,
              icon: _iconForEvent(ev),
            ),
          );
        }
      } catch (e) {
        secureLog('[Notify] notification_events query notice: $e');
      }

      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Intelligent Content & Entity Deduplication:
      final List<NotificationItemModel> deduplicated = [];
      final Set<String> seenKeys = {};

      for (final item in list) {
        final dateMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(item.message);
        final dateKey = dateMatch != null ? dateMatch.group(0) : '';

        String dedupKey;
        if (item.notificationType == 'ATTENDANCE_REGULARIZATION' || item.title.toLowerCase().contains('regularization')) {
          dedupKey = "reg_${item.entityId ?? ''}_$dateKey";
        } else if (item.notificationType == 'DOCUMENT_REQUEST' || item.title.toLowerCase().contains('document')) {
          dedupKey = "doc_${item.entityId ?? ''}_${item.message.toLowerCase().trim()}";
        } else {
          final normalizedMsg = item.message.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
          final normalizedTitle = item.title.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
          final shortMsg = normalizedMsg.length > 40 ? normalizedMsg.substring(0, 40) : normalizedMsg;
          dedupKey = "${normalizedTitle}_$shortMsg";
        }

        if (!seenKeys.contains(dedupKey)) {
          seenKeys.add(dedupKey);
          deduplicated.add(item);
        }
      }

      return deduplicated;
    } catch (e) {
      secureLog('[Notify] getNotifications error: $e');
      return [];
    }
  }

  @override
  Future<List<ActivityItemModel>> getRecentActivities(String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) {
        return [];
      }

      final user = UserService.instance.currentUser;
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      final targetUuid = (user.employeeUuid != null && uuidRegex.hasMatch(user.employeeUuid!))
          ? user.employeeUuid!
          : (uuidRegex.hasMatch(user.dataId)
              ? user.dataId
              : (uuidRegex.hasMatch(employeeId) ? employeeId : null));
      final List<_ActivitySortItem> aggregated = [];

      // 24-Hour Strict Time Window Cutoff
      final cutoff24h = DateTime.now().subtract(const Duration(hours: 24));

      // 1. Employee's Own Check-in / Check-out punches (table: attendance_punches)
      try {
        if (targetUuid != null) {
          final punches = await withTimeout(
            _client
                .from('attendance_punches')
                .select('*')
                .eq('employee_id', targetUuid)
                .order('punch_time', ascending: false)
                .limit(5),
          );
          for (final p in punches) {
            final tsStr = p['punch_time']?.toString() ?? p['created_at']?.toString() ?? '';
            final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
            if (ts.isBefore(cutoff24h)) continue;

            final type = (p['punch_type'] ?? '').toString().toUpperCase();
            final isCheckIn = type.contains('IN') && !type.contains('OUT');
            final title = isCheckIn ? 'Check-In Recorded' : 'Check-Out Recorded';
            final source = p['punch_source'] ?? p['source'] ?? 'Mobile';
            final subtitle = isCheckIn
                ? 'Check-in verified via $source'
                : 'Check-out recorded via $source';

            aggregated.add(
              _ActivitySortItem(
                ActivityItemModel(
                  id: p['id']?.toString() ?? 'punch-$tsStr',
                  title: title,
                  subtitle: subtitle,
                  timeAgo: _relativeTime(ts),
                  icon: isCheckIn ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.arrow_right_circle_fill,
                  iconBg: isCheckIn ? KlarnaWorkForceTokens.iconBgMint : KlarnaWorkForceTokens.iconBgRose,
                  iconFg: isCheckIn ? KlarnaWorkForceTokens.iconFgMint : KlarnaWorkForceTokens.iconFgRose,
                  entityType: 'ATTENDANCE',
                  entityId: p['id']?.toString(),
                ),
                ts,
              ),
            );
          }
        }
      } catch (e) {
        secureLog('[RecentActivities] attendance_punches query notice: $e');
      }

      // 2. Live Announcements & Broadcasts (table: notification_events)
      // STRICT FILTER: Only broadcast company announcements where recipient_user_id IS NULL.
      // Supervisor attendance alerts (check-in, check-out, late check-in) are strictly routed
      // to the Reporting Manager / TL hierarchy via push & inbox, and MUST NEVER be exposed in Recent Activities.
      try {
        final notifs = await withTimeout(
          _client
              .from('notification_events')
              .select('*')
              .filter('recipient_user_id', 'is', 'null')
              .order('created_at', ascending: false)
              .limit(15),
        );
        for (final notif in notifs) {
          final tsStr = notif['created_at']?.toString() ?? '';
          final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
          if (ts.isBefore(cutoff24h)) continue;

          final title = notif['title']?.toString() ?? 'Notification';
          final subtitle = notif['message']?.toString() ?? notif['body']?.toString() ?? 'Company Event';
          final meta = notif['metadata'] is Map ? (notif['metadata'] as Map) : const {};
          final notifEmpId = meta['employee_id']?.toString() ?? meta['target_employee_id']?.toString();
          final notifEmpCode = meta['employee_code']?.toString();
          final recipientId = notif['recipient_user_id']?.toString() ?? notif['recipient_employee_id']?.toString();

          final lowerTitle = title.toLowerCase();
          final lowerSubtitle = subtitle.toLowerCase();
          final isPunchBroadcast = lowerTitle.contains('check-in') ||
              lowerTitle.contains('check-out') ||
              lowerTitle.contains('punch');

          // If this is an attendance punch notification: strictly show ONLY if it belongs to THIS employee
          if (isPunchBroadcast) {
            final matchesEmp = (targetUuid != null && notifEmpId == targetUuid) ||
                (user.employeeId.isNotEmpty && notifEmpCode == user.employeeId) ||
                (user.name.isNotEmpty && lowerSubtitle.contains(user.name.toLowerCase()));
            if (!matchesEmp) {
              // SKIP check-ins from any other employee (e.g. Monishraj A, etc.)
              continue;
            }
          } else {
            // For general notifications, if a recipient is specified, it MUST match this employee
            if (recipientId != null && recipientId.isNotEmpty) {
              final authUid = _client.auth.currentUser?.id;
              final isMe = (targetUuid != null && recipientId == targetUuid) ||
                  (user.dataId.isNotEmpty && recipientId == user.dataId) ||
                  (authUid != null && recipientId == authUid);
              if (!isMe) {
                continue;
              }
            }
          }

          // Strictly filter out any attendance punch/late/shift notifications from employee Recent Activities
          final eventType = notif['event_type']?.toString().toLowerCase() ?? '';
          final category = notif['category']?.toString().toLowerCase() ?? '';
          if (eventType.startsWith('attendance.') || category.contains('attendance')) {
            continue;
          }

          final hay = '$title $subtitle'.toLowerCase();
          if (hay.contains('check-in') ||
              hay.contains('checkin') ||
              hay.contains('check-out') ||
              hay.contains('checkout') ||
              hay.contains('checked in') ||
              hay.contains('checked out') ||
              hay.contains('late') ||
              hay.contains('punch') ||
              hay.contains('attendance') ||
              hay.contains('biometric') ||
              hay.contains('shift')) {
            continue;
          }

          aggregated.add(
            _ActivitySortItem(
              ActivityItemModel(
                id: notif['id']?.toString() ?? 'notif-$tsStr',
                title: title,
                subtitle: subtitle,
                timeAgo: _relativeTime(ts),
                icon: CupertinoIcons.bell_fill,
                iconBg: KlarnaWorkForceTokens.iconBgSky,
                iconFg: KlarnaWorkForceTokens.iconFgSky,
                entityType: 'NOTIFICATION',
                entityId: notif['id']?.toString(),
              ),
              ts,
            ),
          );
        }
      } catch (e) {
        secureLog('[RecentActivities] notification_events query notice: $e');
      }

      // 2. Employee Requests (table: employee_requests) — filtered by employee
      try {
        if (targetUuid != null) {
          final reqRows = await withTimeout(
            _client.from('employee_requests').select('*').eq('employee_id', targetUuid).order('created_at', ascending: false).limit(5),
          );
          for (final r in reqRows) {
            final tsStr = r['updated_at']?.toString() ?? r['created_at']?.toString() ?? '';
            final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
            if (ts.isBefore(cutoff24h)) continue;

            final status = r['status']?.toString() ?? 'PENDING';
            final title = 'Request · $status';
            final subtitle = '${r['subject']}';

            aggregated.add(
              _ActivitySortItem(
                ActivityItemModel(
                  id: r['id']?.toString() ?? 'req-$tsStr',
                  title: title,
                  subtitle: subtitle,
                  timeAgo: _relativeTime(ts),
                  icon: CupertinoIcons.square_stack_3d_up_fill,
                  iconBg: KlarnaWorkForceTokens.iconBgMint,
                  iconFg: KlarnaWorkForceTokens.iconFgMint,
                  entityType: 'EMPLOYEE_REQUEST',
                  entityId: r['id']?.toString(),
                  status: status,
                ),
                ts,
              ),
            );
          }
        }
      } catch (e) {
        secureLog('[RecentActivities] employee_requests notice: $e');
      }

      // 3. Attendance Regularizations
      try {
        if (targetUuid != null) {
          final regRows = await withTimeout(
            _client.from('attendance_regularizations').select().eq('employee_id', targetUuid).order('created_at', ascending: false).limit(5),
          );
          for (final reg in regRows) {
            final tsStr = reg['updated_at']?.toString() ?? reg['created_at']?.toString() ?? '';
            final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
            if (ts.isBefore(cutoff24h)) continue;

            final status = (reg['status'] ?? 'PENDING').toString().toUpperCase();
            final attDate = reg['attendance_date']?.toString() ?? 'Recent date';
            final title = 'Regularization · $status';
            final subtitle = 'Attendance adjustment for $attDate';

            final isApproved = status == 'APPROVED';
            final isRejected = status == 'REJECTED';
            final iconBg = isApproved
                ? KlarnaWorkForceTokens.iconBgMint
                : (isRejected ? KlarnaWorkForceTokens.iconBgRose : KlarnaWorkForceTokens.iconBgLavender);
            final iconFg = isApproved
                ? KlarnaWorkForceTokens.iconFgMint
                : (isRejected ? KlarnaWorkForceTokens.iconFgRose : KlarnaWorkForceTokens.iconFgLavender);

            aggregated.add(
              _ActivitySortItem(
                ActivityItemModel(
                  id: reg['id']?.toString() ?? 'reg-$tsStr',
                  title: title,
                  subtitle: subtitle,
                  timeAgo: _relativeTime(ts),
                  icon: CupertinoIcons.arrow_2_squarepath,
                  iconBg: iconBg,
                  iconFg: iconFg,
                  entityType: 'REGULARIZATION',
                  entityId: reg['id']?.toString(),
                  status: status,
                ),
                ts,
              ),
            );
          }
        }
      } catch (e) {
        secureLog('[RecentActivities] attendance_regularizations notice: $e');
      }

      // 4. Payslips Released
      try {
        if (targetUuid != null) {
          final payslips = await withTimeout(
            _client.from('payslips').select().eq('employee_id', targetUuid).order('created_at', ascending: false).limit(3),
          );
          if (payslips.isNotEmpty) {
            for (final p in payslips) {
              final tsStr = p['created_at']?.toString() ?? '';
              final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
              if (ts.isBefore(cutoff24h)) continue;

              const title = 'Payslip Released';
              final subtitle = 'Payslip #${p['payslip_number'] ?? ''} available'.trim();

              aggregated.add(
                _ActivitySortItem(
                  ActivityItemModel(
                    id: p['id']?.toString() ?? 'pay-$tsStr',
                    title: title,
                    subtitle: subtitle,
                    timeAgo: _relativeTime(ts),
                    icon: CupertinoIcons.doc_text_fill,
                    iconBg: KlarnaWorkForceTokens.iconBgMint,
                    iconFg: KlarnaWorkForceTokens.iconFgMint,
                    entityType: 'PAYSLIP',
                    entityId: p['id']?.toString(),
                  ),
                  ts,
                ),
              );
            }
          }
        }
      } catch (e) {
        secureLog('[RecentActivities] payslips notice: $e');
      }

      // 5. Leave Requests
      try {
        if (targetUuid != null) {
          final leaves = await withTimeout(
            _client.from('leave_requests').select().eq('employee_id', targetUuid).order('created_at', ascending: false).limit(5),
          );
          for (final l in leaves) {
            final tsStr = l['created_at']?.toString() ?? '';
            final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
            if (ts.isBefore(cutoff24h)) continue;

            final status = l['status']?.toString() ?? 'PENDING';
            final title = 'Leave Request · $status';
            final subtitle = 'Leave from ${l['start_date'] ?? l['from_date']} to ${l['end_date'] ?? l['to_date']}';

            aggregated.add(
              _ActivitySortItem(
                ActivityItemModel(
                  id: l['id']?.toString() ?? 'leave-$tsStr',
                  title: title,
                  subtitle: subtitle,
                  timeAgo: _relativeTime(ts),
                  icon: CupertinoIcons.calendar,
                  iconBg: KlarnaWorkForceTokens.iconBgLavender,
                  iconFg: KlarnaWorkForceTokens.iconFgLavender,
                  entityType: 'LEAVE',
                  entityId: l['id']?.toString(),
                  status: status,
                ),
                ts,
              ),
            );
          }
        }
      } catch (e) {
        secureLog('[RecentActivities] leave_requests error: $e');
      }

      // Sort aggregated list by newest first within 24h window
      final valid24h = aggregated.where((item) => !item.createdAt.isBefore(cutoff24h)).toList();
      valid24h.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (valid24h.isNotEmpty) {
        return valid24h.map((item) => item.model).take(15).toList();
      }

      return [];
    } catch (e) {
      secureLog('[Notify] getRecentActivities error: $e');
      return [];
    }
  }

  @override
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      if (!SupabaseConfig.isConfigured || notificationId.isEmpty) return;
      if (_isValidUuid(notificationId)) {
        final nowStr = DateTime.now().toIso8601String();
        try {
          await _client.from('notification_events').update({
            'is_read': true,
          }).eq('id', notificationId);
        } catch (_) {}

        try {
          await _client.from('notification_deliveries').update({
            'status': 'READ',
            'read_at': nowStr,
          }).eq('notification_id', notificationId);
        } catch (_) {}
      }
    } catch (e) {
      secureLog('[Notify] markAsRead failed: $e');
    }
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    try {
      if (!SupabaseConfig.isConfigured || notificationId.isEmpty) return;

      if (_isValidUuid(notificationId)) {
        await _client.from('notification_events').delete().eq('id', notificationId);
      }

      secureLog('[Notify] deleteNotification finished for $notificationId');
    } catch (e) {
      secureLog('[Notify] deleteNotification notice: $e');
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  static String _sOr(dynamic v, String fallback) {
    final s = v?.toString() ?? '';
    return s.isEmpty ? fallback : s;
  }

  /// Today → clock time; <24h → "Xh ago"; else "Xd ago".
  static String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inHours >= 24) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $suffix';
  }

  /// Returns an icon based on real notification_events columns (title, message, channel).
  /// notification_events does NOT have category/event_type/severity columns.
  static IconData _iconForEvent(Map<String, dynamic>? event) {
    if (event == null) return CupertinoIcons.bell_fill;
    final channel = event['channel']?.toString().toLowerCase() ?? '';
    final hay = '${event['title']} ${event['message']}'.toLowerCase();
    if (hay.contains('leave')) return CupertinoIcons.calendar;
    if (hay.contains('shift') || hay.contains('roster')) {
      return CupertinoIcons.calendar_today;
    }
    if (hay.contains('attendance') || hay.contains('check_in') || hay.contains('checkin')) {
      return CupertinoIcons.clock_fill;
    }
    if (hay.contains('payslip') || hay.contains('payroll') || hay.contains('payment') || hay.contains('salary')) {
      return CupertinoIcons.doc_text_fill;
    }
    if (hay.contains('lms') || hay.contains('training') || hay.contains('course') || channel == 'lms_reminder') {
      return CupertinoIcons.book_fill;
    }
    if (hay.contains('announce') || hay.contains('broadcast') || channel == 'push') {
      return CupertinoIcons.speaker_2_fill;
    }
    if (hay.contains('approv')) return CupertinoIcons.checkmark_circle_fill;
    if (hay.contains('alert') || hay.contains('urgent') || hay.contains('critical')) {
      return CupertinoIcons.exclamationmark_triangle_fill;
    }
    return CupertinoIcons.bell_fill;
  }
}

class _ActivitySortItem {
  final ActivityItemModel model;
  final DateTime createdAt;
  _ActivitySortItem(this.model, this.createdAt);
}
