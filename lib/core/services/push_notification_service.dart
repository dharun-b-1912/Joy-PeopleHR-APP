import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../firebase_options.dart';
import '../../widgets/notification_banner.dart';
import '../utils/secure_log.dart';
import 'local_notification_store.dart';
import 'user_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  secureLog('[PushNotificationService] Background message received: ${message.messageId}');
}

class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._internal();
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;
  bool _isInitialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'joy_peoplehr_high_importance',
    'JOY PeopleHR Notifications',
    description: 'Critical notifications for attendance, leaves, announcements, and documents.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Global navigator key for notification deep-linking
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Callback for tab navigation from notifications (set by MainTabShell)
  static void Function(int tabIndex)? onNavigateToTab;

  /// Callback for opening specific screens from notifications
  static void Function(String screen, {Map<String, dynamic>? params})? onOpenScreen;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Set background messaging handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 2. Request user permissions (iOS + Android 13+)
      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      secureLog('[PushNotificationService] Notification authorization status: ${settings.authorizationStatus}');

      // 3. Configure local notifications for foreground popups
      if (!kIsWeb) {
        const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
        const iosInit = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

        const initSettings = InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        );

        await _localNotifications.initialize(
          initSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            if (response.payload != null && response.payload!.isNotEmpty) {
              try {
                final data = jsonDecode(response.payload!) as Map<String, dynamic>;
                _handleNotificationNavigation(data);
              } catch (_) {}
            }
          },
        );

        // Create Android High Importance Channel
        final androidImplementation =
            _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidImplementation?.createNotificationChannel(_channel);

        // Set iOS foreground presentation options
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // 4. Retrieve and sync FCM Token
      await _syncFcmToken();

      // Listen to token refresh events
      _fcm.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        _saveTokenToSupabase(newToken);
      });

      // 5. Setup Foreground Notification Listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        secureLog('[PushNotificationService] Foreground message: ${message.notification?.title}');
        _showForegroundNotification(message);
        _storeNotification(message);
        _showInAppBanner(message);
      });

      // 6. Setup Background / Terminated Click Listeners
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        secureLog('[PushNotificationService] Notification clicked from background: ${message.data}');
        _handleNotificationNavigation(message.data);
      });

      // Check if opened from a terminated state
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        secureLog('[PushNotificationService] Opened from terminated notification: ${initialMessage.data}');
        _handleNotificationNavigation(initialMessage.data);
      }

      // 7. Sync token whenever user logs in or switches
      UserService.instance.addListener(() {
        if (_fcmToken != null) {
          _saveTokenToSupabase(_fcmToken!);
        }
      });

      // 8. Initialize local notification store
      await LocalNotificationStore.instance.initialize();

      _isInitialized = true;
      secureLog('[PushNotificationService] Push notifications initialized successfully.');
    } catch (e) {
      secureLog('[PushNotificationService] Initialization error: $e');
    }
  }

  Future<void> _syncFcmToken() async {
    try {
      _fcmToken = await _fcm.getToken();
      secureLog('[PushNotificationService] Retrieved FCM Token: $_fcmToken');
      if (_fcmToken != null) {
        await _saveTokenToSupabase(_fcmToken!);
      }
    } catch (e) {
      secureLog('[PushNotificationService] Could not retrieve FCM token: $e');
    }
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      final user = UserService.instance.currentUser;
      final authUserId = Supabase.instance.client.auth.currentUser?.id;
      final empId = (user.employeeUuid?.isNotEmpty == true)
          ? user.employeeUuid!
          : (user.employeeId.isNotEmpty ? user.employeeId : user.dataId);

      if (empId.isEmpty && (authUserId == null || authUserId.isEmpty)) return;

      final client = Supabase.instance.client;
      final platformStr = kIsWeb
          ? 'web'
          : (Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown'));

      // 1. Upsert into profiles table (creates if not exists)
      if (authUserId != null && authUserId.isNotEmpty) {
        try {
          await client.from('profiles').upsert({
            'id': authUserId,
            'employee_id': empId,
            'fcm_token': token,
            'device_platform': platformStr,
            'last_active_at': DateTime.now().toIso8601String(),
          }, onConflict: 'id');
        } catch (_) {}
      }

      // 2. Upsert into employee_device_tokens table
      try {
        await client.from('employee_device_tokens').upsert({
          'employee_id': empId,
          'auth_user_id': authUserId ?? '',
          'fcm_token': token,
          'platform': platformStr,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'fcm_token');
      } catch (_) {}

      secureLog('[PushNotificationService] FCM token synced with Supabase for ${user.name}');
    } catch (e) {
      secureLog('[PushNotificationService] Error saving token to Supabase: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null && !kIsWeb) {
      _localNotifications.show(
        notification.hashCode,
        notification.title ?? 'JOY PeopleHR',
        notification.body ?? '',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: android?.smallIcon ?? '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Store the notification in local persistent storage for the notification tray.
  void _storeNotification(RemoteMessage message) {
    final title = message.notification?.title ?? 'JOY PeopleHR';
    final body = message.notification?.body ?? '';
    final route = message.data['route'] ?? message.data['screen'] ?? message.data['type'] ?? 'home';

    if (title.isNotEmpty || body.isNotEmpty) {
      LocalNotificationStore.instance.addNotification(
        title: title,
        body: body,
        route: route.toString(),
        data: Map<String, dynamic>.from(message.data),
      );
    }
  }

  /// Show an in-app banner overlay when the app is in the foreground.
  void _showInAppBanner(RemoteMessage message) {
    final title = message.notification?.title ?? 'JOY PeopleHR';
    final body = message.notification?.body ?? '';
    final route = message.data['route'] ?? message.data['screen'] ?? message.data['type'] ?? 'home';

    if (title.isEmpty && body.isEmpty) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    InAppNotificationBanner.show(
      context,
      title: title,
      body: body,
      route: route.toString(),
      data: Map<String, dynamic>.from(message.data),
      onTap: () => _handleNotificationNavigation(message.data),
    );
  }

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    if (data.isEmpty) return;

    final route = data['route'] ?? data['screen'] ?? data['type'];
    final context = navigatorKey.currentContext;
    if (context == null) return;

    secureLog('[PushNotificationService] Navigating to notification route: $route');

    // Deep link navigation based on notification payload
    try {
      switch (route) {
        // Tab navigation (0=Home, 1=Attendance, 2=Leave, 3=More, 4=Profile)
        case 'home':
          onNavigateToTab?.call(0);
          break;
        case 'attendance':
        case 'regularization':
        case 'checkin':
        case 'checkout':
        case 'REGULARIZATION_APPROVED':
        case 'REGULARIZATION_REJECTED':
        case 'REGULARIZATION_PENDING':
          onNavigateToTab?.call(1);
          break;
        case 'leaves':
        case 'leave':
        case 'leave_request':
        case 'leave_approval':
        case 'LEAVE_APPROVED':
        case 'LEAVE_REJECTED':
        case 'LEAVE_PENDING':
          onNavigateToTab?.call(2);
          break;
        case 'more':
        case 'modules':
          onNavigateToTab?.call(3);
          break;
        case 'profile':
        case 'settings':
          onNavigateToTab?.call(4);
          break;

        // Screen-specific navigation
        case 'documents':
        case 'document':
        case 'document_upload':
        case 'DOCUMENT_VERIFIED':
        case 'DOCUMENT_REJECTED':
        case 'DOCUMENT_COMPLETED':
          onOpenScreen?.call('documents', params: data);
          break;
        case 'announcements':
        case 'announcement':
        case 'communication':
        case 'ANNOUNCEMENT_PUBLISHED':
        case 'COMMUNICATION_PUBLISHED':
          onOpenScreen?.call('announcements', params: data);
          break;
        case 'payslip':
        case 'salary':
        case 'PAYSLIP_GENERATED':
        case 'SALARY_DISBURSED':
          onOpenScreen?.call('payslip', params: data);
          break;
        case 'expense':
        case 'expense_claim':
        case 'EXPENSE_APPROVED':
        case 'EXPENSE_REJECTED':
        case 'EXPENSE_PAID':
        case 'EXPENSE_SETTLED':
          onOpenScreen?.call('expense', params: data);
          break;
        case 'letter':
        case 'digital_letter':
          onOpenScreen?.call('letter', params: data);
          break;
        case 'announcement_detail':
          onOpenScreen?.call('announcement_detail', params: data);
          break;

        default:
          secureLog('[PushNotificationService] Unknown route: $route');
          break;
      }
    } catch (e) {
      secureLog('[PushNotificationService] Navigation handling exception: $e');
    }
  }
}
