import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/secure_log.dart';

/// LocalNotificationStore — Persists FCM push notifications locally
/// so they appear in the in-app notification tray even after app restart.
///
/// Stores up to 100 most recent notifications in SharedPreferences.
class LocalNotificationStore extends ChangeNotifier {
  static final LocalNotificationStore instance = LocalNotificationStore._();
  LocalNotificationStore._();

  static const String _storageKey = 'local_push_notifications';
  static const int _maxNotifications = 100;

  final List<LocalNotification> _notifications = [];
  List<LocalNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Initialize — load persisted notifications from disk.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_storageKey) ?? [];
      _notifications.clear();
      for (final jsonStr in raw) {
        try {
          _notifications.add(LocalNotification.fromJson(jsonDecode(jsonStr)));
        } catch (_) {}
      }
      _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notifyListeners();
      secureLog('[LocalNotificationStore] Loaded ${_notifications.length} persisted notifications');
    } catch (e) {
      secureLog('[LocalNotificationStore] Initialize error: $e');
    }
  }

  /// Add a new notification from FCM message.
  Future<void> addNotification({
    required String title,
    required String body,
    String? route,
    Map<String, dynamic>? data,
  }) async {
    final notification = LocalNotification(
      id: 'fcm-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      body: body,
      route: route ?? data?['route'] ?? 'home',
      data: data,
      timestamp: DateTime.now(),
      source: 'push',
    );

    // Deduplicate by title+body within last 5 seconds
    final recentDuplicate = _notifications.any((n) =>
        n.title == title &&
        n.body == body &&
        DateTime.now().difference(n.timestamp).inSeconds < 5);
    if (recentDuplicate) return;

    _notifications.insert(0, notification);

    // Trim to max
    if (_notifications.length > _maxNotifications) {
      _notifications.removeRange(_maxNotifications, _notifications.length);
    }

    notifyListeners();
    await _persist();
  }

  /// Mark a notification as read.
  Future<void> markAsRead(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1 && !_notifications[idx].isRead) {
      _notifications[idx] = _notifications[idx].copyWith(isRead: true);
      notifyListeners();
      await _persist();
    }
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead() async {
    bool changed = false;
    for (int i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  /// Remove a notification.
  Future<void> removeNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
    await _persist();
  }

  /// Clear all notifications.
  Future<void> clearAll() async {
    _notifications.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _notifications.map((n) => jsonEncode(n.toJson())).toList();
      await prefs.setStringList(_storageKey, jsonList);
    } catch (e) {
      secureLog('[LocalNotificationStore] Persist error: $e');
    }
  }
}

/// Local notification model for persisting FCM messages.
class LocalNotification {
  final String id;
  final String title;
  final String body;
  final String route;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  final String source; // 'push', 'system', 'realtime'
  final bool isRead;

  const LocalNotification({
    required this.id,
    required this.title,
    required this.body,
    this.route = 'home',
    this.data,
    required this.timestamp,
    this.source = 'push',
    this.isRead = false,
  });

  LocalNotification copyWith({
    String? id,
    String? title,
    String? body,
    String? route,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    String? source,
    bool? isRead,
  }) {
    return LocalNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      route: route ?? this.route,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'route': route,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'isRead': isRead,
  };

  factory LocalNotification.fromJson(Map<String, dynamic> json) {
    return LocalNotification(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      route: json['route'] ?? 'home',
      data: json['data'] is Map ? Map<String, dynamic>.from(json['data']) : null,
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      source: json['source'] ?? 'push',
      isRead: json['isRead'] ?? false,
    );
  }
}
