import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../repositories/supabase/supabase_employee_repository.dart';
import '../controllers/employee_controller.dart';
import '../utils/secure_log.dart';
import 'attendance_service.dart';
import 'employee_profile_mapper.dart';
import 'local_notification_store.dart';
import 'location_service.dart';
import 'user_service.dart';

/// Connection status states for Employee Realtime Service
enum RealtimeConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// WorkForceOS — Employee Realtime Synchronization Service
///
/// Subscribes to real-time Postgres UPDATE changes on the `employees` table,
/// strictly scoped to the authenticated employee's UUID.
///
/// Flow:
///   HR Web App updates employees row
///          ↓
///   Supabase Realtime (UPDATE event on id=eq.<employeeUuid>)
///          ↓
///   EmployeeRealtimeService
///          ↓
///   EmployeeProfileMapper.fromEmployeesRow()
///          ↓
///   UserService.instance.setUser()
///          ↓
///   Profile / Home / Virtual ID UI auto-updates
class EmployeeRealtimeService with WidgetsBindingObserver {
  static final EmployeeRealtimeService instance = EmployeeRealtimeService._internal();
  EmployeeRealtimeService._internal() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  RealtimeChannel? _channel;
  String? _activeEmployeeUuid;
  String? _authEmail;
  bool _isSubscribed = false;
  bool _isReconciling = false;
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.disconnected;

  RealtimeConnectionStatus get status => _status;
  bool get isSubscribed => _isSubscribed;
  String? get activeEmployeeUuid => _activeEmployeeUuid;

  /// Subscribe to real-time profile changes for the specified employee UUID.
  ///
  /// Prevents duplicate subscriptions to the same employee.
  /// Cleans up any previous employee subscription if switching accounts.
  Future<void> subscribe(String employeeUuid, {String? authEmail}) async {
    final trimmedUuid = employeeUuid.trim();
    if (trimmedUuid.isEmpty) {
      secureLog('[Realtime] Cannot subscribe with empty employee UUID');
      return;
    }

    // If already subscribed to this exact employee, skip duplicate
    if (_isSubscribed && _activeEmployeeUuid == trimmedUuid && _channel != null) {
      secureLog('[Realtime] Already subscribed to employee $trimmedUuid');
      return;
    }

    // If switching employees or existing channel active, clean up first
    if (_channel != null) {
      await unsubscribe();
    }

    _activeEmployeeUuid = trimmedUuid;
    _authEmail = authEmail;
    _status = RealtimeConnectionStatus.connecting;

    try {
      secureLog('[Realtime] Creating scoped channel for employee_id=$trimmedUuid');

      // Scoped channel name
      final channelName = 'employee_profile_$trimmedUuid';
      final channel = Supabase.instance.client.channel(channelName);

      // Scoped Postgres change listener: ALL events on employees where id = employeeUuid
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employees',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] employees table change event received for employee $trimmedUuid');
          _handleEmployeeUpdate(payload.newRecord, trimmedUuid);
        },
      );

      // Scoped Postgres change listener: ALL events on employee_emergency_contacts
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_emergency_contacts',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'employee_id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] employee_emergency_contacts change event received for employee $trimmedUuid');
          reconcile();
        },
      );

      // Scoped Postgres change listener: ALL events on employee_bank_details
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_bank_details',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'employee_id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] employee_bank_details change event received for employee $trimmedUuid');
          reconcile();
        },
      );

      // Scoped Postgres change listener: ALL events on employee_statutory_details
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_statutory_details',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'employee_id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] employee_statutory_details change event received for employee $trimmedUuid');
          reconcile();
        },
      );

      // Scoped Postgres change listener: ALL events on work_locations
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'work_locations',
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] work_locations change event received');
          reconcile();
          LocationService.instance.refreshLocationsAndEvaluate();
          LocalNotificationStore.instance.addNotification(
            title: 'Work Location Updated',
            body: 'HR has updated your assigned work locations.',
            route: 'home',
          );
        },
      );

      // Scoped Postgres change listener: ALL events on user_profiles (role, status, profile mappings)
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'user_profiles',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] user_profiles change event received for employee $trimmedUuid');
          reconcile();
        },
      );

      // Scoped Postgres change listener: ALL events on assets for real-time asset assignment updates
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'assets',
        callback: (PostgresChangePayload payload) {
          final empId = payload.newRecord['employee_id']?.toString() ?? payload.oldRecord['employee_id']?.toString();
          final custId = payload.newRecord['custodian_id']?.toString() ?? payload.oldRecord['custodian_id']?.toString();
          if (empId == trimmedUuid || custId == trimmedUuid || empId == null) {
            secureLog('[REALTIME] assets change event received for employee $trimmedUuid');
            reconcile();
          }
        },
      );

      // Scoped Postgres change listener: ALL events on shifts
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'shifts',
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] shifts table change event received');
          reconcile();
        },
      );

      // Scoped Postgres change listener: ALL events on employee_profile_media for photo versioning & status
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_profile_media',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'employee_id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] Profile media change event received for employee $trimmedUuid');
          _handleProfileMediaChange(payload.newRecord, trimmedUuid);
        },
      );

      // Scoped Postgres change listener: ALL events on employee_avatar_assets for canonical avatar sync
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_avatar_assets',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'employee_id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] Canonical avatar asset change event received for employee $trimmedUuid');
          reconcile();
        },
      );

      // Scoped Postgres change listener: ALL events on leave_requests for instant approval/rejection/withdrawal sync
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'leave_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'employee_id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] leave_requests event received for employee $trimmedUuid (type: ${payload.eventType})');
          LeaveController.instance.refresh();
          AttendanceDetailController.instance.refresh();
          if (payload.eventType != PostgresChangeEvent.delete) {
            final status = payload.newRecord['status']?.toString() ?? 'updated';
            LocalNotificationStore.instance.addNotification(
              title: 'Leave Request $status',
              body: 'Your leave request has been $status by HR.',
              route: 'leaves',
            );
          }
        },
      );

      // Scoped Postgres change listener: ALL events on leave_balances for live balance updates
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'leave_balances',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'employee_id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] leave_balances change event received for employee $trimmedUuid');
          LeaveController.instance.refresh();
          LocalNotificationStore.instance.addNotification(
            title: 'Leave Balance Updated',
            body: 'HR has updated your leave balance.',
            route: 'leaves',
          );
        },
      );

      // Scoped Postgres change listener: ALL events on employee_shift_assignments for real-time shift sync
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_shift_assignments',
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] Shift schedule change event received');
          MoreModulesController.instance.loadAllData();
          reconcile();
          LocalNotificationStore.instance.addNotification(
            title: 'Shift Schedule Updated',
            body: 'HR has updated your shift schedule.',
            route: 'attendance',
          );
        },
      );

      // Scoped Postgres change listener: ALL events on attendance_regularizations
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'attendance_regularizations',
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] attendance_regularizations event received (type: ${payload.eventType})');
          AttendanceService.instance.fetchTodayAttendance();
          AttendanceDetailController.instance.refresh();
          NotificationController.instance.loadNotifications();

          if (payload.eventType != PostgresChangeEvent.delete) {
            final status = payload.newRecord['status']?.toString() ?? 'updated';
            LocalNotificationStore.instance.addNotification(
              title: 'Regularization $status',
              body: 'HR has $status your attendance regularization request.',
              route: 'attendance',
            );
          }
        },
      );

      // Scoped Postgres change listener: ALL events on attendance_daily for real-time attendance status
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'attendance_daily',
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] attendance_daily change event received');
          AttendanceService.instance.fetchTodayAttendance();
          AttendanceDetailController.instance.refresh();
        },
      );

      // Scoped Postgres change listener: ALL events on attendance_punches for raw punch sync
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'attendance_punches',
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] attendance_punches change event received');
          AttendanceService.instance.fetchTodayAttendance();
          AttendanceDetailController.instance.refresh();
        },
      );

      // Scoped Postgres change listener: ALL events on notification_events (Announcements & Alerts)
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notification_events',
        callback: (PostgresChangePayload payload) {
          final isAnnouncement = payload.newRecord['recipient_user_id'] == null;
          final title = payload.newRecord['title'] ?? (isAnnouncement ? 'Company Announcement' : 'Notification');
          final message = payload.newRecord['message'] ?? payload.newRecord['content'] ?? 'New notification from HR.';
          final actionUrl = payload.newRecord['action_url']?.toString();

          secureLog('[REALTIME] notification_events event received: $title (isAnnouncement: $isAnnouncement)');
          NotificationController.instance.loadNotifications();
          if (isAnnouncement) {
            MoreModulesController.instance.loadAllData();
          }

          LocalNotificationStore.instance.addNotification(
            title: isAnnouncement ? '📢 $title' : title,
            body: message,
            route: isAnnouncement ? 'announcements' : (actionUrl ?? 'home'),
          );
        },
      );

      // Scoped Postgres change listener: ALL events on payslips / payroll
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'payslips',
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] payslips change event received');
          MoreModulesController.instance.loadAllData();
          LocalNotificationStore.instance.addNotification(
            title: '💳 Payslip Released',
            body: 'Your latest salary payslip has been published by HR.',
            route: 'payslip',
          );
        },
      );

      // Scoped Postgres change listener: ALL events on employee_documents (Letters & Docs)
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_documents',
        callback: (PostgresChangePayload payload) {
          final title = payload.newRecord['document_name'] ?? 'Document';
          secureLog('[REALTIME] employee_documents change event received: $title');
          MoreModulesController.instance.loadAllData();
          LocalNotificationStore.instance.addNotification(
            title: '📄 New Document: $title',
            body: 'HR has updated your employee documents.',
            route: 'documents',
          );
        },
      );

      // Scoped Postgres change listener: ALL events on employee_requests (Expenses & Helpdesk)
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_requests',
        callback: (PostgresChangePayload payload) {
          final status = payload.newRecord['status'] ?? 'updated';
          secureLog('[REALTIME] employee_requests change event received (status: $status)');
          MoreModulesController.instance.loadAllData();
          LocalNotificationStore.instance.addNotification(
            title: 'Request $status',
            body: 'HR has $status your request.',
            route: 'requests',
          );
        },
      );

      // Scoped Postgres change listener: ALL events on employee_documents for real-time doc sync
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employee_documents',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'employee_id',
          value: trimmedUuid,
        ),
        callback: (PostgresChangePayload payload) {
          secureLog('[REALTIME] Employee documents change event received for employee $trimmedUuid');
          MoreModulesController.instance.loadAllData();
        },
      );

      // Scoped Postgres change listener: ALL events on document_requirements for real-time doc requests from HR
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'document_requirements',
        callback: (PostgresChangePayload payload) {
          final title = payload.newRecord['title'] ?? 'Document Request';
          final dueDate = payload.newRecord['due_date'] ?? '';
          secureLog('[FLUTTER][DOC_REQ] New document requested from HR: $title (Due: $dueDate)');
          NotificationController.instance.loadNotifications();
          MoreModulesController.instance.loadAllData();
          LocalNotificationStore.instance.addNotification(
            title: '📋 Document Requested: $title',
            body: 'HR has requested an official document upload.${dueDate.isNotEmpty ? ' Due: $dueDate' : ''}',
            route: 'documents',
          );
        },
      );

      // Scoped Postgres change listener: ALL events on notification_events for real-time push events from HR
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notification_events',
        callback: (PostgresChangePayload payload) {
          final title = payload.newRecord['title'] ?? 'Notification';
          final message = payload.newRecord['message'] ?? payload.newRecord['body'] ?? '';
          secureLog('[FLUTTER][NOTIFY_EVENT] Realtime notification event received: $title');
          NotificationController.instance.loadNotifications();
          LocalNotificationStore.instance.addNotification(
            title: title.toString(),
            body: message.toString(),
            route: payload.newRecord['route']?.toString() ?? 'home',
          );
        },
      );

      // Scoped Postgres change listener: ALL events on notification_deliveries for real-time push inbox
      final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(trimmedUuid);
      if (isUuid) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notification_deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_user_id',
            value: trimmedUuid,
          ),
          callback: (PostgresChangePayload payload) {
            secureLog('[REALTIME] New notification delivery received for employee $trimmedUuid');
            NotificationController.instance.loadNotifications();
          },
        );
      }

      // Subscribe and track status
      channel.subscribe((status, [error]) {
        switch (status) {
          case RealtimeSubscribeStatus.subscribed:
            _isSubscribed = true;
            _status = RealtimeConnectionStatus.connected;
            secureLog('[REALTIME] Connected & subscribed to employee channel for $trimmedUuid');
            break;
          case RealtimeSubscribeStatus.closed:
            _isSubscribed = false;
            _status = RealtimeConnectionStatus.disconnected;
            secureLog('[REALTIME] Channel closed for employee $trimmedUuid');
            break;
          case RealtimeSubscribeStatus.timedOut:
            _status = RealtimeConnectionStatus.error;
            secureLog('[REALTIME] Subscription timed out for employee $trimmedUuid');
            break;
          default:
            break;
        }
      });

      _channel = channel;
    } catch (e) {
      _status = RealtimeConnectionStatus.error;
      secureLog('[REALTIME] Failed to initialize subscription: $e');
    }
  }

  /// Handles incoming UPDATE payload from Supabase Realtime
  Future<void> _handleEmployeeUpdate(Map<String, dynamic> newRecord, String expectedEmployeeUuid) async {
    try {
      secureLog('[REALTIME] Processing update payload. Keys: ${newRecord.keys.join(', ')}');

      // Security validation: verify payload matches authenticated employee UUID
      final recordId = newRecord['id']?.toString();
      if (recordId != null && recordId.isNotEmpty && recordId != expectedEmployeeUuid) {
        secureLog('[REALTIME] Security check warning: Received update for unexpected ID $recordId');
        return;
      }

      // Check status: if employee was terminated/inactive, trigger sign-out
      final status = (newRecord['status']?.toString() ?? 'active').toLowerCase().trim();
      if (status == 'inactive' ||
          status == 'terminated' ||
          status == 'blocked' ||
          status == 'suspended' ||
          status == 'resigned' ||
          status == 'disabled') {
        secureLog('[REALTIME] Employee status changed to $status — clearing session');
        unsubscribe();
        UserService.instance.clearUser();
        Supabase.instance.client.auth.signOut().catchError((_) {});
        return;
      }

      // 1. Immediately parse incoming record if populated
      if (newRecord.isNotEmpty) {
        final updatedUserModel = EmployeeProfileMapper.fromEmployeesRow(
          newRecord,
          authEmail: _authEmail,
          role: UserService.instance.currentUser.role,
        );
        UserService.instance.setUser(updatedUserModel);
        secureLog('[REALTIME] UserModel updated immediately -> ${updatedUserModel.name} (${updatedUserModel.designation}, Shift: ${updatedUserModel.shift})');
      }

      // 2. Fetch complete row from database to ensure all relations/JSONB fields are synced
      await reconcile();

      // 3. Refresh modules and attendance
      MoreModulesController.instance.loadAllData();
      AttendanceService.instance.fetchTodayAttendance();
    } catch (e) {
      secureLog('[REALTIME] Error processing employee update payload: $e');
    }
  }

  /// Handles incoming change payload from employee_profile_media table
  Future<void> _handleProfileMediaChange(Map<String, dynamic> record, String expectedEmployeeUuid) async {
    try {
      final status = (record['status']?.toString() ?? '').toUpperCase().trim();
      final mediaVersion = record['media_version'] as int? ?? 1;
      final mediaUrl = record['media_url']?.toString() ?? record['url']?.toString() ?? record['profile_photo_url']?.toString();

      secureLog('[REALTIME] Profile media update: status=$status, version=$mediaVersion, url=$mediaUrl');

      if (status == 'ACTIVE' && mediaUrl != null && mediaUrl.isNotEmpty) {
        final versionedUrl = mediaUrl.contains('?')
            ? '$mediaUrl&v=$mediaVersion'
            : '$mediaUrl?v=$mediaVersion';
        UserService.instance.updateProfileImage(versionedUrl);
      } else if (status == 'DELETED') {
        UserService.instance.updateProfileImage('');
      } else {
        await reconcile();
      }
    } catch (e) {
      secureLog('[REALTIME] Error handling profile media change: $e');
    }
  }

  bool _pendingReconcile = false;

  /// Reconcile current employee profile against the database.
  /// Called on app resume, real-time database events, or network recovery.
  Future<void> reconcile() async {
    if (!UserService.instance.isLoggedIn) return;

    if (_isReconciling) {
      _pendingReconcile = true;
      return;
    }

    final currentId = UserService.instance.currentUser.dataId;
    if (currentId.isEmpty) return;

    _isReconciling = true;
    try {
      secureLog('[Realtime] Reconciling employee profile with database');
      await SupabaseEmployeeRepository().getCurrentEmployee();
    } catch (e) {
      secureLog('[Realtime] Reconciliation error: $e');
    } finally {
      _isReconciling = false;
      if (_pendingReconcile) {
        _pendingReconcile = false;
        // Schedule follow-up reconcile after brief delay to batch rapid multi-table updates
        Future.delayed(const Duration(milliseconds: 150), () {
          reconcile();
        });
      }
    }
  }

  /// Cleanly unsubscribe and remove the realtime channel.
  Future<void> unsubscribe() async {
    if (_channel != null) {
      try {
        await Supabase.instance.client.removeChannel(_channel!);
        secureLog('[Realtime] Removed channel for employee $_activeEmployeeUuid');
      } catch (e) {
        secureLog('[Realtime] Error removing channel: $e');
      }
    }
    _channel = null;
    _activeEmployeeUuid = null;
    _isSubscribed = false;
    _status = RealtimeConnectionStatus.disconnected;
  }

  DateTime? _lastReconcileTime;

  /// App lifecycle listener: Reconcile on app foreground (throttled 10s)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastReconcileTime != null && now.difference(_lastReconcileTime!).inSeconds < 10) {
        return;
      }
      _lastReconcileTime = now;
      secureLog('[Realtime] App resumed to foreground — triggering profile reconciliation');
      reconcile();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unsubscribe();
  }
}
