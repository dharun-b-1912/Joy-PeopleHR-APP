import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/local_notification_store.dart';
import '../../core/utils/secure_log.dart';
import '../../models/employee_models.dart';
import '../../repositories/interfaces/employee_repository.dart';
import '../../repositories/supabase/supabase_notification_repository.dart';
import '../services/user_service.dart';

class NotificationController extends ChangeNotifier {
  static final NotificationController instance =
      NotificationController._internal(SupabaseNotificationRepository());
  NotificationController._internal(this._repo);

  final INotificationRepository _repo;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  List<NotificationItemModel> _notifications = [];
  List<NotificationItemModel> get notifications => _notifications;

  List<ActivityItemModel> _activities = [];
  List<ActivityItemModel> get activities => _activities;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  RealtimeChannel? _notificationChannel;
  String? _subscribedTargetId;

  final Set<String> _dismissedIds = {};
  final Set<String> _readIds = {};

  void initialize() {
    UserService.instance.addListener(() {
      loadNotifications();
    });
    loadNotifications();
  }

  Future<void> refresh() => loadNotifications();

  void _subscribeRealtime(String targetId) {
    if (_subscribedTargetId == targetId && _notificationChannel != null) return;
    _notificationChannel?.unsubscribe();

    try {
      _subscribedTargetId = targetId;
      _notificationChannel = Supabase.instance.client
          .channel('notifications-realtime-$targetId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notification_events',
          callback: (payload) {
            secureLog('[REALTIME] notification_events change event -> refreshing notifications');
            loadNotifications();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'document_requirements',
          callback: (payload) {
            secureLog('[REALTIME] document_requirements change event -> refreshing notifications');
            loadNotifications();
          },
        )
        ..subscribe();
    } catch (e) {
      secureLog('[REALTIME] Notification subscription notice: $e');
    }
  }

  String _getStorageKey(String targetId, String suffix) => 'notif_${targetId}_$suffix';

  Future<void> _loadPersistedState(String targetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissedList = prefs.getStringList(_getStorageKey(targetId, 'dismissed')) ?? [];
      final readList = prefs.getStringList(_getStorageKey(targetId, 'read')) ?? [];
      _dismissedIds.addAll(dismissedList);
      _readIds.addAll(readList);
    } catch (e) {
      secureLog('[NotificationController] _loadPersistedState notice: $e');
    }
  }

  Future<void> _persistState(String targetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_getStorageKey(targetId, 'dismissed'), _dismissedIds.toList());
      await prefs.setStringList(_getStorageKey(targetId, 'read'), _readIds.toList());
    } catch (e) {
      secureLog('[NotificationController] _persistState notice: $e');
    }
  }

  Future<void> loadNotifications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = UserService.instance.currentUser;
      final targetId = user.resolvedEmployeeId;

      if (targetId.isNotEmpty) {
        await _loadPersistedState(targetId);
        _subscribeRealtime(targetId);
      }

      final fetched = await _repo.getNotifications(targetId);
      final activities = await _repo.getRecentActivities(targetId);

      // Filter out permanently dismissed notifications and apply read status
      _notifications = fetched
          .where((n) => !_dismissedIds.contains(n.id))
          .map((n) {
            if (_readIds.contains(n.id) && !n.isRead) {
              return NotificationItemModel(
                id: n.id,
                title: n.title,
                message: n.message,
                timestamp: n.timestamp,
                isRead: true,
                icon: n.icon,
                notificationType: n.notificationType,
                entityType: n.entityType,
                entityId: n.entityId,
                dueDate: n.dueDate,
                status: n.status,
                rejectionReason: n.rejectionReason,
              );
            }
            return n;
          })
          .toList();

      _activities = activities;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Unable to load notifications. Please check your connection.';
      secureLog('[NotificationController] loadNotifications error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markAsRead(String id) async {
    _readIds.add(id);
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final old = _notifications[idx];
      _notifications[idx] = NotificationItemModel(
        id: old.id,
        title: old.title,
        message: old.message,
        timestamp: old.timestamp,
        isRead: true,
        icon: old.icon,
        notificationType: old.notificationType,
        entityType: old.entityType,
        entityId: old.entityId,
        dueDate: old.dueDate,
        status: old.status,
        rejectionReason: old.rejectionReason,
      );
      notifyListeners();
    }
    final user = UserService.instance.currentUser;
    final targetId = user.resolvedEmployeeId;
    if (targetId.isNotEmpty) {
      await _persistState(targetId);
    }
    await LocalNotificationStore.instance.markAsRead(id);
    await _repo.markNotificationAsRead(id);
  }

  Future<void> dismissAndRemoveNotification(String id) async {
    _dismissedIds.add(id);
    _readIds.add(id);
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();

    final user = UserService.instance.currentUser;
    final targetId = user.resolvedEmployeeId;
    if (targetId.isNotEmpty) {
      await _persistState(targetId);
    }
    await LocalNotificationStore.instance.removeNotification(id);
    await _repo.deleteNotification(id);
  }

  Future<void> clearAllNotifications() async {
    for (final n in _notifications) {
      _dismissedIds.add(n.id);
      _readIds.add(n.id);
    }
    _notifications.clear();
    notifyListeners();

    final user = UserService.instance.currentUser;
    final targetId = user.resolvedEmployeeId;
    if (targetId.isNotEmpty) {
      await _persistState(targetId);
    }
    await LocalNotificationStore.instance.clearAll();
  }
}
