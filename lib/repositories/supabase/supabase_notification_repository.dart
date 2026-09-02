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
///   notification_deliveries — per-user inbox rows
///       (recipient_user_id, channel, status, read_at, created_at)
///   notification_events     — broadcast content
///       (title, body, category, severity, actor_name, created_at)
///   activity_log            — org feed
///       (actor_name, action, entity, type, created_at)
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

      // 1. HR Document Requests for this employee (table: document_requirements)
      try {
        final orFilters = <String>{
          if (targetId.isNotEmpty) 'employee_id.eq.$targetId',
          if (user.employeeUuid?.isNotEmpty == true) 'employee_id.eq.${user.employeeUuid}',
          if (user.employeeId.isNotEmpty) 'employee_id.eq.${user.employeeId}',
        }.join(',');

        if (orFilters.isEmpty) {
          // No valid employee ID — return empty to avoid data leakage
          return [];
        }
        final docReqs = await withTimeout(
          _client
              .from('document_requirements')
              .select()
              .or(orFilters)
              .order('created_at', ascending: false)
              .limit(20),
        );

        for (final req in docReqs) {
          final status = (req['status']?.toString() ?? 'PENDING').toUpperCase();
          if (status == 'VERIFIED' || status == 'COMPLETED' || status == 'RESOLVED' || status == 'CANCELLED') {
            continue;
          }

          final title = req['title']?.toString() ?? 'Document Requested by HR';
          final docType = req['requested_document_type'] ?? req['document_type'] ?? req['requirement_type'] ?? 'Required Verification';
          final dueDateStr = req['due_date']?.toString();
          final desc = req['description']?.toString() ??
              (dueDateStr != null && dueDateStr.isNotEmpty
                  ? 'HR requested: $docType (Due: $dueDateStr)'
                  : 'HR requested you to upload: $docType');
          final createdAt = DateTime.tryParse(req['created_at']?.toString() ?? '') ?? DateTime.now();
          final isRead = req['is_read'] == true;
          final dueDate = dueDateStr != null ? DateTime.tryParse(dueDateStr) : null;
          final reqId = req['id']?.toString() ?? 'doc-req-${createdAt.millisecondsSinceEpoch}';

          if (!list.any((item) => item.id == reqId)) {
            list.add(
              NotificationItemModel(
                id: reqId,
                title: title,
                message: desc,
                timestamp: createdAt,
                isRead: isRead,
                icon: CupertinoIcons.folder_badge_plus,
                notificationType: 'DOCUMENT_REQUEST',
                entityType: 'DOCUMENT_REQUIREMENT',
                entityId: reqId,
                dueDate: dueDate,
                status: status,
                rejectionReason: req['rejection_reason']?.toString(),
              ),
            );
          }
        }
      } catch (e) {
        secureLog('[Notify] document_requirements notice: $e');
      }

      // 2. Direct Notification Events targeted to this employee
      try {
        final eventRows = await withTimeout(
          _client
              .from('notification_events')
              .select('id, title, body, category, severity, event_type, actor_name, resource_id, metadata, created_at')
              .order('created_at', ascending: false)
              .limit(25),
        );

        for (final ev in eventRows) {
          final resId = ev['resource_id']?.toString() ?? '';
          final meta = ev['metadata'];
          final metaTarget = meta is Map ? (meta['target_user_id'] ?? meta['employee_id'] ?? meta['user_id'])?.toString() : null;

          final myIds = <String>{
            targetId,
            employeeId,
            user.dataId,
            user.employeeId,
            if (user.employeeUuid != null && user.employeeUuid!.isNotEmpty) user.employeeUuid!,
            if (authUid != null && authUid.isNotEmpty) authUid,
          }.where((s) => s.isNotEmpty).toSet();

          // Announcements and communications are for ALL employees — don't filter by resource_id
          final eventType = ev['event_type']?.toString() ?? '';
          final isBroadcast = eventType.contains('ANNOUNCEMENT') || eventType.contains('COMMUNICATION');

          final isForMe = isBroadcast ||
              myIds.contains(resId) ||
              (metaTarget != null && myIds.contains(metaTarget));

          if (isForMe) {
            final evId = ev['id']?.toString() ?? 'ev-${ev['created_at']}';
            if (!list.any((item) => item.id == evId)) {
              final createdAt = DateTime.tryParse(ev['created_at']?.toString() ?? '') ?? DateTime.now();
              final eventType = ev['event_type']?.toString() ?? 'GENERAL';
              final isDocReq = eventType.contains('DOCUMENT');
              final reqId = meta is Map ? meta['requirement_id']?.toString() : (isDocReq ? resId : null);

              list.add(
                NotificationItemModel(
                  id: evId,
                  title: _sOr(ev['title'], 'Notification'),
                  message: _sOr(ev['body'], ''),
                  timestamp: createdAt,
                  isRead: false,
                  icon: _iconForEvent(ev),
                  notificationType: isDocReq ? 'DOCUMENT_REQUEST' : eventType,
                  entityType: isDocReq ? 'DOCUMENT_REQUIREMENT' : null,
                  entityId: reqId,
                  status: meta is Map ? meta['status']?.toString() : null,
                  rejectionReason: meta is Map ? meta['rejection_reason']?.toString() : null,
                ),
              );
            }
          }
        }
      } catch (e) {
        secureLog('[Notify] notification_events query notice: $e');
      }

      // 3. Deliveries for this recipient
      try {
        final filters = <String>{
          if (authUid != null && _isValidUuid(authUid)) 'recipient_user_id.eq.$authUid',
          if (targetId.isNotEmpty) 'recipient_employee_id.eq.$targetId',
          if (user.employeeId.isNotEmpty) 'recipient_employee_id.eq.${user.employeeId}',
          if (user.employeeUuid != null && user.employeeUuid!.isNotEmpty) 'recipient_employee_id.eq.${user.employeeUuid}',
        };

        if (filters.isNotEmpty) {
          final filterStr = filters.join(',');
          final deliveries = await withTimeout(
            _client
                .from('notification_deliveries')
                .select('id, notification_id, status, read_at, dismissed_at, created_at')
                .or(filterStr)
                .order('created_at', ascending: false)
                .limit(30),
          );

          if (deliveries.isNotEmpty) {
            final eventIds = deliveries
                .map((d) => d['notification_id']?.toString())
                .whereType<String>()
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList();

            final Map<String, Map<String, dynamic>> eventsById = {};
            if (eventIds.isNotEmpty) {
              try {
                final events = await withTimeout(
                  _client
                      .from('notification_events')
                      .select('id, title, body, category, severity, event_type, actor_name, created_at')
                      .inFilter('id', eventIds),
                );
                for (final e in events) {
                  eventsById[e['id'].toString()] = e;
                }
              } catch (_) {}
            }

            for (final d in deliveries) {
              final event = eventsById[d['notification_id']?.toString() ?? ''];
              final createdAt = DateTime.tryParse(d['created_at']?.toString() ?? '') ??
                  DateTime.tryParse(event?['created_at']?.toString() ?? '') ??
                  DateTime.now();
              final isRead = d['read_at'] != null ||
                  d['dismissed_at'] != null ||
                  (d['status']?.toString().toUpperCase() == 'READ') ||
                  (d['status']?.toString().toUpperCase() == 'DISMISSED');

              final docId = d['id'].toString();
              if (!list.any((item) => item.id == docId)) {
                list.add(
                  NotificationItemModel(
                    id: docId,
                    title: _sOr(event?['title'], 'Notification'),
                    message: _sOr(event?['body'], ''),
                    timestamp: createdAt,
                    isRead: isRead,
                    icon: _iconForEvent(event),
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        secureLog('[Notify] notification_deliveries error: $e');
      }

      // 4. Realtime Outbox Notifications (Regularization Approved / Rejected, Late/Early Deviations)
      try {
        final outboxFilter = <String>{
          'entity_type.eq.notifications',
          'entity_type.eq.attendance_regularization_requests',
        };
        if (targetId.isNotEmpty) {
          outboxFilter.add('actor_id.eq.$targetId');
        }
        final outboxRows = await withTimeout(
          _client
              .from('realtime_outbox')
              .select('*')
              .or(outboxFilter.join(','))
              .order('created_at', ascending: false)
              .limit(20),
        );

        for (final row in outboxRows) {
          final payload = row['payload'];
          if (payload is Map<String, dynamic>) {
            final recId = payload['recipient_employee_id']?.toString() ?? payload['employee_id']?.toString() ?? row['actor_id']?.toString() ?? '';
            final recCode = payload['recipient_code']?.toString() ?? payload['employee_code']?.toString() ?? '';

            if (targetId.isNotEmpty && (recId == targetId || recCode == user.employeeId || recId == user.employeeId)) {
              final evId = row['id']?.toString() ?? 'outbox-${row['created_at']}';
              if (!list.any((item) => item.id == evId)) {
                final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now();
                final title = payload['title']?.toString() ??
                    (row['event_type']?.toString().contains('approved') == true
                        ? 'Attendance Regularization Approved'
                        : 'Attendance Update');
                final body = payload['body']?.toString() ??
                    (row['event_type']?.toString().contains('approved') == true
                        ? 'Your attendance regularization for ${payload['attendance_date'] ?? 'recently'} was approved.'
                        : 'Your attendance regularization status was updated.');

                list.add(
                  NotificationItemModel(
                    id: evId,
                    title: title,
                    message: body,
                    timestamp: createdAt,
                    isRead: false,
                    icon: CupertinoIcons.checkmark_seal_fill,
                    notificationType: 'ATTENDANCE_REGULARIZATION',
                    entityType: 'ATTENDANCE',
                    entityId: row['entity_id']?.toString(),
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        secureLog('[Notify] realtime_outbox notification query notice: $e');
      }

      // 5. Company Announcements (table: company_announcements) — visible to ALL employees
      try {
        final announcements = await withTimeout(
          _client
              .from('company_announcements')
              .select('id, title, content, category, status, publish_at, expires_at, created_at')
              .eq('status', 'PUBLISHED')
              .order('publish_at', ascending: false)
              .limit(10),
        );

        for (final ann in announcements) {
          final tsStr = ann['publish_at']?.toString() ?? ann['created_at']?.toString() ?? '';
          final createdAt = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();

          // Skip expired announcements
          final expiresAt = ann['expires_at']?.toString();
          if (expiresAt != null && expiresAt.isNotEmpty) {
            final expDt = DateTime.tryParse(expiresAt);
            if (expDt != null && expDt.isBefore(DateTime.now())) continue;
          }

          final evId = 'ann-${ann['id']}';
          if (!list.any((item) => item.id == evId)) {
            final category = ann['category']?.toString() ?? 'General';
            list.add(
              NotificationItemModel(
                id: evId,
                title: '📢 $category · ${ann['title'] ?? 'Announcement'}',
                message: ann['content']?.toString() ?? 'A new company announcement has been published.',
                timestamp: createdAt,
                isRead: false,
                icon: CupertinoIcons.speaker_2_fill,
                notificationType: 'ANNOUNCEMENT',
                entityType: 'ANNOUNCEMENT',
                entityId: ann['id']?.toString(),
              ),
            );
          }
        }
      } catch (e) {
        secureLog('[Notify] company_announcements query notice: $e');
      }

      // 6. Communications (table: communications) — visible to ALL employees
      try {
        final comms = await withTimeout(
          _client
              .from('communications')
              .select('id, title, communication_type, priority, status, publish_at, created_at')
              .eq('status', 'PUBLISHED')
              .order('publish_at', ascending: false)
              .limit(10),
        );

        for (final comm in comms) {
          final tsStr = comm['publish_at']?.toString() ?? comm['created_at']?.toString() ?? '';
          final createdAt = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();

          final evId = 'comm-${comm['id']}';
          if (!list.any((item) => item.id == evId)) {
            final type = comm['communication_type']?.toString() ?? 'Announcement';
            final priority = comm['priority']?.toString() ?? 'NORMAL';
            list.add(
              NotificationItemModel(
                id: evId,
                title: '📢 $type · ${comm['title'] ?? 'Company Update'}',
                message: priority == 'URGENT'
                    ? 'URGENT: ${comm['title'] ?? 'Company Communication'}'
                    : '${comm['title'] ?? 'New company communication'}',
                timestamp: createdAt,
                isRead: false,
                icon: CupertinoIcons.speaker_2_fill,
                notificationType: 'COMMUNICATION',
                entityType: 'COMMUNICATION',
                entityId: comm['id']?.toString(),
              ),
            );
          }
        }
      } catch (e) {
        secureLog('[Notify] communications query notice: $e');
      }

      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Intelligent Content & Entity Deduplication:
      final List<NotificationItemModel> deduplicated = [];
      final Set<String> seenKeys = {};

      for (final item in list) {
        // Extract normalized date if present in message (e.g. 2026-08-28)
        final dateMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(item.message);
        final dateKey = dateMatch != null ? dateMatch.group(0) : '';

        // If it's a regularization notification, deduplicate by date + type
        String dedupKey;
        if (item.notificationType == 'ATTENDANCE_REGULARIZATION' || item.title.toLowerCase().contains('regularization')) {
          dedupKey = "reg_${item.entityId ?? ''}_$dateKey";
        } else if (item.notificationType == 'DOCUMENT_REQUEST' || item.title.toLowerCase().contains('document')) {
          dedupKey = "doc_${item.entityId ?? ''}_${item.message.toLowerCase().trim()}";
        } else {
          // Standard title + message key
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
      final targetCode = user.employeeId.isNotEmpty ? user.employeeId : employeeId;
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      final targetUuid = (user.employeeUuid != null && uuidRegex.hasMatch(user.employeeUuid!))
          ? user.employeeUuid!
          : (uuidRegex.hasMatch(user.dataId)
              ? user.dataId
              : (uuidRegex.hasMatch(employeeId) ? employeeId : null));
      final targetId = targetUuid ?? targetCode;
      final List<_ActivitySortItem> aggregated = [];

      // 24-Hour Strict Time Window Cutoff
      final cutoff24h = DateTime.now().subtract(const Duration(hours: 24));
      final cutoffIso = cutoff24h.toUtc().toIso8601String();

      // Database background cleanup: automatically purge delivery / transient event rows older than 24 hours
      unawaited(() async {
        try {
          await _client.from('notification_deliveries').delete().lt('created_at', cutoffIso);
        } catch (_) {}
        try {
          await _client.from('realtime_outbox').delete().lt('created_at', cutoffIso);
        } catch (_) {}
      }());

      // 1. Live Announcements & Broadcasts (table: communications)
      try {
        final comms = await withTimeout(
          _client
              .from('communications')
              .select('id, title, communication_type, priority, publish_at, created_at, status')
              .eq('status', 'PUBLISHED')
              .order('publish_at', ascending: false)
              .limit(5),
        );
        for (final comm in comms) {
          final tsStr = comm['publish_at']?.toString() ?? comm['created_at']?.toString() ?? '';
          final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
          if (ts.isBefore(cutoff24h)) continue;

          final type = comm['communication_type']?.toString() ?? 'Announcement';
          final title = 'Announcement · $type';
          final subtitle = comm['title']?.toString() ?? 'Company Broadcast';
          final priority = comm['priority']?.toString() ?? 'NORMAL';

          aggregated.add(
            _ActivitySortItem(
              ActivityItemModel(
                id: comm['id']?.toString() ?? 'comm-$tsStr',
                title: title,
                subtitle: subtitle,
                timeAgo: _relativeTime(ts),
                icon: CupertinoIcons.speaker_2_fill,
                iconBg: priority == 'URGENT' ? KlarnaWorkForceTokens.iconBgRose : KlarnaWorkForceTokens.iconBgSky,
                iconFg: priority == 'URGENT' ? KlarnaWorkForceTokens.iconFgRose : KlarnaWorkForceTokens.iconFgSky,
                entityType: 'COMMUNICATION',
                entityId: comm['id']?.toString(),
                badge: priority == 'URGENT' ? 'URGENT' : null,
              ),
              ts,
            ),
          );
        }
      } catch (e) {
        secureLog('[RecentActivities] communications query notice: $e');
      }

      // 2. HR Helpdesk Support Tickets (table: helpdesk_tickets) — filtered by employee
      try {
        final tktQuery = _client.from('helpdesk_tickets').select('id, ticket_number, subject, category, status, created_at, updated_at');
        final tkts = await withTimeout(
          targetId.isNotEmpty
              ? tktQuery.eq('employee_id', targetId).order('created_at', ascending: false).limit(5)
              : tktQuery.eq('employee_id', '___NONE___').order('created_at', ascending: false).limit(5),
        );
        for (final tkt in tkts) {
          final tsStr = tkt['updated_at']?.toString() ?? tkt['created_at']?.toString() ?? '';
          final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
          if (ts.isBefore(cutoff24h)) continue;

          final num = tkt['ticket_number']?.toString() ?? 'Ticket';
          final status = tkt['status']?.toString() ?? 'OPEN';
          final title = 'Helpdesk · $status';
          final subtitle = '${tkt['subject']} ($num)';

          aggregated.add(
            _ActivitySortItem(
              ActivityItemModel(
                id: tkt['id']?.toString() ?? 'tkt-$tsStr',
                title: title,
                subtitle: subtitle,
                timeAgo: _relativeTime(ts),
                icon: CupertinoIcons.question_circle_fill,
                iconBg: KlarnaWorkForceTokens.iconBgSky,
                iconFg: KlarnaWorkForceTokens.iconFgSky,
                entityType: 'HELPDESK',
                entityId: tkt['id']?.toString(),
                status: status,
              ),
              ts,
            ),
          );
        }
      } catch (e) {
        secureLog('[RecentActivities] helpdesk_tickets notice: $e');
      }

      // 3. Employee Service Requests (table: service_requests) — filtered by employee
      try {
        final srvQuery = _client.from('service_requests').select('id, request_number, service_name, status, submitted_at, updated_at');
        final srvs = await withTimeout(
          targetId.isNotEmpty
              ? srvQuery.eq('employee_id', targetId).order('submitted_at', ascending: false).limit(5)
              : srvQuery.eq('employee_id', '___NONE___').order('submitted_at', ascending: false).limit(5),
        );
        for (final srv in srvs) {
          final tsStr = srv['updated_at']?.toString() ?? srv['submitted_at']?.toString() ?? '';
          final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
          if (ts.isBefore(cutoff24h)) continue;

          final num = srv['request_number']?.toString() ?? 'Req';
          final status = srv['status']?.toString() ?? 'SUBMITTED';
          final title = 'Service Request · $status';
          final subtitle = '${srv['service_name']} ($num)';

          aggregated.add(
            _ActivitySortItem(
              ActivityItemModel(
                id: srv['id']?.toString() ?? 'srv-$tsStr',
                title: title,
                subtitle: subtitle,
                timeAgo: _relativeTime(ts),
                icon: CupertinoIcons.square_stack_3d_up_fill,
                iconBg: KlarnaWorkForceTokens.iconBgMint,
                iconFg: KlarnaWorkForceTokens.iconFgMint,
                entityType: 'SERVICE_REQUEST',
                entityId: srv['id']?.toString(),
                status: status,
              ),
              ts,
            ),
          );
        }
      } catch (e) {
        secureLog('[RecentActivities] service_requests notice: $e');
      }

      // 4. Expense Claims (table: expense_claims) — filtered by employee
      try {
        final clmQuery = _client.from('expense_claims').select();
        final claims = await withTimeout(
          targetId.isNotEmpty
              ? clmQuery.eq('employee_id', targetId).order('created_at', ascending: false).limit(5)
              : clmQuery.eq('employee_id', '___NONE___').order('created_at', ascending: false).limit(5),
        );
        for (final clm in claims) {
          final tsStr = clm['created_at']?.toString() ??
              clm['submitted_at']?.toString() ??
              clm['date']?.toString() ??
              clm['claim_date']?.toString() ??
              '';
          final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
          if (ts.isBefore(cutoff24h)) continue;

          final status = clm['status']?.toString() ?? 'PENDING';
          final amt = clm['amount'] != null ? '₹${clm['amount']}' : '';
          final claimDesc = clm['description']?.toString() ??
              clm['title']?.toString() ??
              clm['category']?.toString() ??
              clm['claim_number']?.toString() ??
              'Reimbursement';
          final title = 'Expense Claim · $status';
          final subtitle = '$claimDesc $amt'.trim();

          aggregated.add(
            _ActivitySortItem(
              ActivityItemModel(
                id: clm['id']?.toString() ?? 'clm-$tsStr',
                title: title,
                subtitle: subtitle,
                timeAgo: _relativeTime(ts),
                icon: CupertinoIcons.money_dollar_circle_fill,
                iconBg: KlarnaWorkForceTokens.iconBgPeach,
                iconFg: KlarnaWorkForceTokens.iconFgPeach,
                entityType: 'CLAIM',
                entityId: clm['id']?.toString(),
                status: status,
              ),
              ts,
            ),
          );
        }
      } catch (e) {
        secureLog('[RecentActivities] expense_claims notice: $e');
      }

      // 5. Attendance Regularization Requests & Approvals
      try {
        final regQuery = _client.from('attendance_regularization_requests').select();
        final regs = await withTimeout(
          targetId.isNotEmpty
              ? regQuery.eq('employee_id', targetId).order('created_at', ascending: false).limit(5)
              : regQuery.eq('employee_id', '___NONE___').order('created_at', ascending: false).limit(5),
        );
        for (final reg in regs) {
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
      } catch (e) {
        secureLog('[RecentActivities] regularization notice: $e');
      }

      // 6. HR Document Requests & Verification
      try {
        final docQuery = _client.from('document_requirements').select();
        final docReqs = await withTimeout(
          targetId.isNotEmpty
              ? docQuery.eq('employee_id', targetId).order('created_at', ascending: false).limit(5)
              : docQuery.eq('employee_id', '___NONE___').order('created_at', ascending: false).limit(5),
        );
        for (final req in docReqs) {
          final tsStr = req['created_at']?.toString() ?? '';
          final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
          if (ts.isBefore(cutoff24h)) continue;

          final docType = req['requested_document_type'] ?? req['document_type'] ?? req['title'] ?? 'Document Verification';
          final status = (req['status']?.toString() ?? 'REQUIRED').toUpperCase();
          final title = 'Document Request · $status';
          final subtitle = '$docType requested by HR';

          aggregated.add(
            _ActivitySortItem(
              ActivityItemModel(
                id: req['id']?.toString() ?? 'doc-$tsStr',
                title: title,
                subtitle: subtitle,
                timeAgo: _relativeTime(ts),
                icon: CupertinoIcons.folder_badge_plus,
                iconBg: KlarnaWorkForceTokens.iconBgSky,
                iconFg: KlarnaWorkForceTokens.iconFgSky,
                entityType: 'DOCUMENT_REQUEST',
                entityId: req['id']?.toString(),
                status: status,
              ),
              ts,
            ),
          );
        }
      } catch (e) {
        secureLog('[RecentActivities] document_requirements notice: $e');
      }

      // 7. Payslips Released
      try {
        for (final table in const ['employee_payslips', 'payslips']) {
          try {
            dynamic payslips;
            if (targetUuid != null) {
              payslips = await withTimeout(
                _client.from(table).select().eq('employee_id', targetUuid).order('created_at', ascending: false).limit(3),
              );
            }
            if ((payslips == null || payslips.isEmpty) && targetCode.isNotEmpty) {
              payslips = await withTimeout(
                _client.from(table).select().eq('employee_code', targetCode).order('created_at', ascending: false).limit(3),
              );
            }
            if (payslips != null && payslips.isNotEmpty) {
              for (final p in payslips) {
                final tsStr = p['created_at']?.toString() ?? '';
                final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
                if (ts.isBefore(cutoff24h)) continue;

                final month = p['month_name'] ?? p['month'] ?? 'Salary';
                final year = p['year'] ?? '';
                const title = 'Payslip Released';
                final subtitle = '$month $year Salary Statement available'.trim();

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
              break;
            }
          } catch (_) {}
        }
      } catch (e) {
        secureLog('[RecentActivities] payslips notice: $e');
      }

      // 8. Leave Requests
      try {
        final query = _client.from('leave_requests').select();
        final leaves = await withTimeout(
          targetId.isNotEmpty
              ? query.eq('employee_id', targetId).order('created_at', ascending: false).limit(5)
              : query.eq('employee_id', '___NONE___').order('created_at', ascending: false).limit(5),
        );
        for (final l in leaves) {
          final tsStr = l['created_at']?.toString() ?? '';
          final ts = DateTime.tryParse(tsStr)?.toLocal() ?? DateTime.now();
          if (ts.isBefore(cutoff24h)) continue;

          final type = l['leave_type']?.toString() ?? 'Leave';
          final status = l['status']?.toString() ?? 'Pending';
          final title = 'Leave Request · $status';
          final subtitle = '$type Request submitted';

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
        await _client.from('notification_deliveries').update({
          'read_at': DateTime.now().toIso8601String(),
          'status': 'READ',
        }).eq('id', notificationId);
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
        // 1. Update status to DISMISSED and set dismissed_at on deliveries
        try {
          await _client.from('notification_deliveries').update({
            'status': 'DISMISSED',
            'dismissed_at': DateTime.now().toIso8601String(),
            'read_at': DateTime.now().toIso8601String(),
          }).eq('id', notificationId);
        } catch (_) {}

        // 2. Try direct delete from deliveries
        try {
          await _client.from('notification_deliveries').delete().eq('id', notificationId);
        } catch (_) {}

        // 3. Try delete from notification_events
        try {
          await _client.from('notification_events').delete().eq('id', notificationId);
        } catch (_) {}

        // 4. Try delete from realtime_outbox
        try {
          await _client.from('realtime_outbox').delete().eq('id', notificationId);
        } catch (_) {}
      }

      // 5. If document requirement, update as dismissed
      if (notificationId.startsWith('doc-req-')) {
        final actualId = notificationId.replaceFirst('doc-req-', '');
        if (_isValidUuid(actualId)) {
          try {
            await _client.from('document_requirements').update({
              'is_read': true,
              'status': 'COMPLETED',
            }).eq('id', actualId);
          } catch (_) {}
        }
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

  static IconData _iconForEvent(Map<String, dynamic>? event) {
    if (event == null) return CupertinoIcons.bell_fill;
    final hay =
        '${event['category']} ${event['event_type']} ${event['severity']}'
            .toLowerCase();
    if (hay.contains('leave')) return CupertinoIcons.calendar;
    if (hay.contains('shift') || hay.contains('roster')) {
      return CupertinoIcons.calendar_today;
    }
    if (hay.contains('attendance') || hay.contains('check_in') || hay.contains('checkin')) {
      return CupertinoIcons.clock_fill;
    }
    if (hay.contains('payslip') || hay.contains('payroll') || hay.contains('payment')) {
      return CupertinoIcons.doc_text_fill;
    }
    if (hay.contains('announce') || hay.contains('broadcast')) {
      return CupertinoIcons.speaker_2_fill;
    }
    if (hay.contains('approv')) return CupertinoIcons.checkmark_circle_fill;
    if (hay.contains('alert') || hay.contains('critical')) {
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
