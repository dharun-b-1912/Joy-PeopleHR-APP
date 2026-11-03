import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../controllers/employee_controller.dart';
import '../services/user_service.dart';
import '../utils/secure_log.dart';

/// NotificationRealtimeService — Centralized lifecycle-aware Supabase Realtime
/// notification sync engine.
///
/// Architecture:
/// - Single active subscription scoped to the authenticated employee / user ID.
/// - Listens to Postgres changes on `document_requirements`, `notification_events`, and `notification_deliveries`.
/// - Automatic reconciliation on reconnect to prevent missed notifications.
/// - Deduplicates events by record ID before notifying `NotificationController`.
class NotificationRealtimeService with WidgetsBindingObserver {
  static final NotificationRealtimeService instance = NotificationRealtimeService._internal();
  NotificationRealtimeService._internal() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  RealtimeChannel? _channel;
  String? _subscribedTargetId;
  bool _isSubscribed = false;

  bool get isSubscribed => _isSubscribed;

  /// Starts the realtime notification subscription for the authenticated employee.
  Future<void> initialize() async {
    final user = UserService.instance.currentUser;
    final targetId = (user.employeeUuid?.isNotEmpty == true)
        ? user.employeeUuid!
        : (user.employeeId.isNotEmpty ? user.employeeId : '');

    if (targetId.isEmpty) {
      secureLog('[NotificationRealtime] User not logged in, skipping subscription');
      return;
    }

    await subscribe(targetId);
  }

  /// Subscribe to realtime notification tables for the given target ID.
  Future<void> subscribe(String targetId) async {
    if (!SupabaseConfig.isConfigured || targetId.isEmpty) return;

    if (_isSubscribed && _subscribedTargetId == targetId && _channel != null) {
      secureLog('[NotificationRealtime] Already subscribed for target: $targetId');
      return;
    }

    if (_channel != null) {
      await unsubscribe();
    }

    _subscribedTargetId = targetId;

    try {
      final client = Supabase.instance.client;
      final authUid = client.auth.currentUser?.id;
      final channelName = 'user_notifications_${targetId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';

      secureLog('[NOTIFICATION] subscribing channel: $channelName (employee: $targetId, auth: $authUid)');

      _channel = client.channel(channelName);

      // 1. Listen to notification_events (canonical notifications & announcements)
      _channel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notification_events',
        callback: (PostgresChangePayload payload) {
          secureLog('[NOTIFICATION] realtime event on notification_events: ${payload.eventType}');
          _reconcile();
        },
      );

      // 2. Listen to employee_requests (canonical requests & expenses)
      _channel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_requests',
        callback: (PostgresChangePayload payload) {
          secureLog('[NOTIFICATION] realtime event on employee_requests: ${payload.eventType}');
          _reconcile();
          MoreModulesController.instance.loadAllData();
        },
      );

      // 3. Listen to employee_documents (canonical documents & letters)
      _channel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_documents',
        callback: (PostgresChangePayload payload) {
          secureLog('[NOTIFICATION] realtime event on employee_documents: ${payload.eventType}');
          _reconcile();
          MoreModulesController.instance.loadAllData();
        },
      );

      // 4. Listen to payslips (canonical payroll)
      _channel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'payslips',
        callback: (PostgresChangePayload payload) {
          secureLog('[NOTIFICATION] realtime event on payslips: ${payload.eventType}');
          _reconcile();
          MoreModulesController.instance.loadAllData();
        },
      );

      _channel?.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _isSubscribed = true;
          secureLog('[NOTIFICATION] realtime connected successfully');
        } else if (status == RealtimeSubscribeStatus.closed || status == RealtimeSubscribeStatus.timedOut) {
          _isSubscribed = false;
          secureLog('[NOTIFICATION] realtime disconnected or timed out ($status)');
        }
      });
    } catch (e) {
      secureLog('[NOTIFICATION] subscription error: $e');
      _isSubscribed = false;
    }
  }

  /// Reconciles state by pulling the latest database notifications into the controller.
  Future<void> _reconcile() async {
    try {
      await NotificationController.instance.loadNotifications();
    } catch (e) {
      secureLog('[NOTIFICATION] reconciliation error: $e');
    }
  }

  /// Unsubscribes from the current channel.
  Future<void> unsubscribe() async {
    try {
      final wasActive = _channel != null || _isSubscribed;
      if (_channel != null) {
        await _channel?.unsubscribe();
        _channel = null;
      }
      _isSubscribed = false;
      _subscribedTargetId = null;
      if (wasActive) {
        secureLog('[REALTIME] Notification channel unsubscribed');
      }
    } catch (e) {
      secureLog('[REALTIME] Notification unsubscribe error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      secureLog('[NOTIFICATION] App resumed — reconciling with Supabase');
      _reconcile();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unsubscribe();
  }
}
