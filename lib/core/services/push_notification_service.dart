import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
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

  final title = message.notification?.title ?? message.data['title'] ?? 'JOY PeopleHR';
  final body = message.notification?.body ?? message.data['body'] ?? message.data['message'] ?? '';
  final route = message.data['route'] ?? message.data['screen'] ?? 'home';

  // Always persist background notifications so the bell tray has them when the app is opened
  try {
    await LocalNotificationStore.instance.initialize();
    if (title.isNotEmpty || body.isNotEmpty) {
      await LocalNotificationStore.instance.addNotification(
        title: title,
        body: body,
        route: route.toString(),
        data: Map<String, dynamic>.from(message.data),
      );
    }
  } catch (e) {
    secureLog('[PushNotificationService] Background store notice: $e');
  }

  // If this is a data-only push message, the Android system won't display it automatically.
  // We display it in the system notification tray using local notifications with sound and vibration.
  if (message.notification == null && (title.isNotEmpty || body.isNotEmpty)) {
    try {
      final localNotifications = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await localNotifications.initialize(initSettings);

      const channel = AndroidNotificationChannel(
        'joy_peoplehr_high_importance',
        'JOY PeopleHR Notifications',
        description: 'Critical notifications for attendance, leaves, announcements, and documents.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );

      final androidImpl = localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(channel);

      final int notifId = (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) & 0x7FFFFFFF;

      await localNotifications.show(
        notifId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.message,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      secureLog('[PushNotificationService] Background local notification error: $e');
    }
  }
}

class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._internal();
  PushNotificationService._internal();

  FirebaseMessaging? _fcmInstance;
  FirebaseMessaging get _fcm => _fcmInstance ??= FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'joy_peoplehr_high_importance',
    'JOY PeopleHR Notifications',
    description: 'Critical notifications for attendance, leaves, announcements, and documents.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    enableLights: true,
  );

  /// Global navigator key for notification deep-linking
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Callback for tab navigation from notifications (set by MainTabShell)
  static void Function(int tabIndex)? onNavigateToTab;

  /// Callback for opening specific screens from notifications
  static void Function(String screen, {Map<String, dynamic>? params})? onOpenScreen;

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (kIsWeb) {
      try {
        await LocalNotificationStore.instance.initialize();
      } catch (e) {
        secureLog('[PushNotificationService] Web local notification store notice: $e');
      }
      _isInitialized = true;
      logProcess('PUSH', 'Web notification store initialized (Realtime notification stream active)');
      return;
    }

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

      // 3. Configure local notifications for foreground popups and system tray
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

        // Explicitly request notification permissions on Android 13+
        final androidImplementation =
            _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidImplementation?.requestNotificationsPermission();

        // Create Android High Importance Channel
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

      // 5. Subscribe to FCM topics (all_employees, all, etc.)
      await _subscribeToTopics();

      // Listen to token refresh events
      _fcm.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        _saveTokenToSupabase(newToken);
        _syncTokenToUpstash(newToken);
      });

      // 6. Setup Foreground Notification Listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        secureLog('[PushNotificationService] Foreground message: ${message.notification?.title}');
        _showForegroundNotification(message);
        _storeNotification(message);
        _showInAppBanner(message);
      });

      // 7. Setup Background / Terminated Click Listeners
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        secureLog('[PushNotificationService] Notification clicked from background: ${message.data}');
        _storeNotification(message);
        _handleNotificationNavigation(message.data);
      });

      // Check if opened from a terminated state
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        secureLog('[PushNotificationService] Opened from terminated notification: ${initialMessage.data}');
        _storeNotification(initialMessage);
        _handleNotificationNavigation(initialMessage.data);
      }

      // 8. Re-sync topics and token whenever user logs in or switches
      UserService.instance.addListener(() {
        if (_fcmToken != null) {
          _saveTokenToSupabase(_fcmToken!);
          _syncTokenToUpstash(_fcmToken!);
        }
        _subscribeToTopics();
      });

      // Also listen to Supabase Auth state changes for instant login token sync & topic subscribe
      if (SupabaseConfig.isConfigured) {
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
          if (data.session != null) {
            if (_fcmToken != null) {
              _saveTokenToSupabase(_fcmToken!);
              _syncTokenToUpstash(_fcmToken!);
            }
            _subscribeToTopics();
          }
        });
      }

      // 9. Initialize local notification store
      await LocalNotificationStore.instance.initialize();

      _isInitialized = true;
      secureLog('[PushNotificationService] Push notifications initialized successfully.');
    } catch (e) {
      secureLog('[PushNotificationService] Initialization error: $e');
    }
  }

  /// Subscribe to global, organization, employee, and user topics
  Future<void> _subscribeToTopics() async {
    try {
      await _fcm.subscribeToTopic('all');
      await _fcm.subscribeToTopic('all_employees');

      final user = UserService.instance.currentUser;
      final orgId = user.organizationId ?? user.companyId;
      if (orgId.isNotEmpty) {
        await _fcm.subscribeToTopic('org_$orgId');
      }
      final empId = user.resolvedEmployeeId;
      if (empId.isNotEmpty) {
        await _fcm.subscribeToTopic('emp_$empId');
      }
      final authUid = Supabase.instance.client.auth.currentUser?.id;
      if (authUid != null && authUid.isNotEmpty) {
        await _fcm.subscribeToTopic('user_$authUid');
      }
      final userEmail = (user.officeEmail?.isNotEmpty == true ? user.officeEmail! : user.personalEmail).toLowerCase();
      final authEmail = (Supabase.instance.client.auth.currentUser?.email ?? '').toLowerCase();
      if (userEmail.contains('dharun') || authEmail.contains('dharun')) {
        await _fcm.subscribeToTopic('dharun');
      }
      secureLog('[PushNotificationService] Subscribed to topics (all_employees, all, emp_$empId, user_$authUid)');
    } catch (e) {
      secureLog('[PushNotificationService] Topic subscription notice: $e');
    }
  }

  Future<void> _syncFcmToken() async {
    try {
      _fcmToken = await _fcm.getToken();
      secureLog('[PushNotificationService] Retrieved FCM Token: $_fcmToken');
      if (_fcmToken != null) {
        await _saveTokenToSupabase(_fcmToken!);
        await _syncTokenToUpstash(_fcmToken!);
      }
    } catch (e) {
      secureLog('[PushNotificationService] Could not retrieve FCM token: $e');
    }
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      final user = UserService.instance.currentUser;
      if (SupabaseConfig.isConfigured) {
        final authUid = Supabase.instance.client.auth.currentUser?.id;
        final employeeId = user.resolvedEmployeeId;

        // 1. Sync to employee_device_tokens table
        try {
          await Supabase.instance.client.from('employee_device_tokens').upsert([
            {
              'employee_id': employeeId.isNotEmpty ? employeeId : (authUid ?? 'anonymous'),
              'auth_user_id': authUid ?? '',
              'fcm_token': token,
              'platform': defaultTargetPlatform.name.toLowerCase(),
              'updated_at': DateTime.now().toIso8601String(),
            }
          ], onConflict: 'fcm_token');
          secureLog('[PushNotificationService] Token synced to employee_device_tokens');
        } catch (e) {
          secureLog('[PushNotificationService] employee_device_tokens upsert notice: $e');
        }

        // 2. Sync to push_subscriptions table
        if (authUid != null && authUid.isNotEmpty) {
          try {
            await Supabase.instance.client.from('push_subscriptions').upsert([
              {
                'user_id': authUid,
                'endpoint': token,
                'p256dh_key': 'fcm-mobile-token',
                'auth_key': 'fcm',
                'browser': 'Flutter Mobile App',
                'os': defaultTargetPlatform.name,
                'device': 'Mobile',
                'last_seen_at': DateTime.now().toIso8601String(),
              }
            ], onConflict: 'user_id,endpoint');
            secureLog('[PushNotificationService] Token synced to push_subscriptions');
          } catch (e) {
            secureLog('[PushNotificationService] push_subscriptions upsert notice: $e');
          }
        }
      }
    } catch (e) {
      secureLog('[PushNotificationService] Error caching token: $e');
    }
  }

  /// Syncs FCM token to Upstash Redis as an ultra-reliable backup channel
  Future<void> _syncTokenToUpstash(String token) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('https://powerful-marmot-162532.upstash.io/pipeline')
      );
      request.headers.set('Authorization', 'Bearer gQAAAAAAAnrkAAIgcDI0NjFkYzJlOWE5YWQ0ODVhOWYwYWNmYzFkNWJmM2FjZQ');
      request.headers.set('Content-Type', 'application/json');

      final user = UserService.instance.currentUser;
      final authUid = Supabase.instance.client.auth.currentUser?.id;
      final empId = user.resolvedEmployeeId;
      final userEmail = (user.officeEmail?.isNotEmpty == true ? user.officeEmail! : user.personalEmail).toLowerCase();
      final authEmail = (Supabase.instance.client.auth.currentUser?.email ?? '').toLowerCase();

      final commands = [
        ['SET', 'fcm_token:latest', token],
        ['SADD', 'fcm_tokens:all', token],
      ];
      if (userEmail.isNotEmpty) {
        commands.add(['SET', 'fcm_token:email:$userEmail', token]);
      }
      if (authEmail.isNotEmpty && authEmail != userEmail) {
        commands.add(['SET', 'fcm_token:email:$authEmail', token]);
      }
      if (userEmail.contains('dharun') || authEmail.contains('dharun')) {
        commands.add(['SET', 'fcm_token:dharun', token]);
      }
      if (empId.isNotEmpty) {
        commands.add(['SET', 'fcm_token:emp:$empId', token]);
      }
      if (authUid != null && authUid.isNotEmpty) {
        commands.add(['SET', 'fcm_token:user:$authUid', token]);
      }

      request.write(jsonEncode(commands));
      final response = await request.close();
      await response.drain();
      secureLog('[PushNotificationService] FCM token successfully cached to Upstash Redis');
    } catch (e) {
      secureLog('[PushNotificationService] Upstash token sync notice: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final title = message.notification?.title ?? message.data['title'] ?? 'JOY PeopleHR';
    final body = message.notification?.body ?? message.data['body'] ?? message.data['message'] ?? '';

    if ((message.notification != null || body.isNotEmpty) && !kIsWeb && _isInitialized) {
      // Safe 32-bit signed integer ID
      final int notifId = (message.messageId?.hashCode ?? title.hashCode) & 0x7FFFFFFF;
      try {
        _localNotifications.show(
          notifId,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              category: AndroidNotificationCategory.message,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: jsonEncode(message.data),
        );
      } catch (e) {
        secureLog('[PushNotificationService] Failed to show foreground notification: $e');
      }
    }
  }

  /// Store the notification in local persistent storage for the notification tray.
  void _storeNotification(RemoteMessage message) {
    final title = message.notification?.title ?? message.data['title'] ?? 'JOY PeopleHR';
    final body = message.notification?.body ?? message.data['body'] ?? message.data['message'] ?? '';
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
    final title = message.notification?.title ?? message.data['title'] ?? 'JOY PeopleHR';
    final body = message.notification?.body ?? message.data['body'] ?? message.data['message'] ?? '';
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

  /// Dispatches an immediate test push notification with sound and haptics for verification
  Future<void> triggerTestNotification({
    required String title,
    required String body,
    String route = 'home',
    Map<String, dynamic>? data,
  }) async {
    final payload = {
      'route': route,
      if (data != null) ...data,
    };

    if (!kIsWeb && _isInitialized) {
      try {
        await _localNotifications.show(
          DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: jsonEncode(payload),
        );
      } catch (e) {
        secureLog('[PushNotificationService] Failed to show local notification: $e');
      }
    }

    // Store in notification tray
    LocalNotificationStore.instance.addNotification(
      title: title,
      body: body,
      route: route,
      data: payload,
    );

    // Show in-app banner with alert sound and haptic feedback
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      InAppNotificationBanner.show(
        context,
        title: title,
        body: body,
        route: route,
        data: payload,
        onTap: () => _handleNotificationNavigation(payload),
      );
    }
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
