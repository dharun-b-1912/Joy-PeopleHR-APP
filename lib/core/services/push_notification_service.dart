import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../../firebase_options.dart';
import '../../widgets/notification_banner.dart';
import '../utils/haptic_vibrator.dart';
import '../utils/secure_log.dart';
import 'local_notification_store.dart';
import 'user_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  secureLog('[PushNotificationService] Background message received: ${message.messageId}');

  // Handle Biometric Punch and Background Shift Tracking Wake-Up Commands
  final rawAction = (message.data['action'] ?? message.data['type'] ?? '').toString().toUpperCase();
  if (rawAction == 'START_SHIFT_TRACKING' ||
      rawAction == 'BIOMETRIC_PUNCH_IN' ||
      rawAction == 'BIOMETRIC_CHECKIN' ||
      rawAction == 'CHECK_IN' ||
      rawAction == 'FETCH_LOCATION') {
    await _handleBackgroundLocationWakeup(message.data, isStart: true);
  } else if (rawAction == 'STOP_SHIFT_TRACKING' ||
      rawAction == 'BIOMETRIC_PUNCH_OUT' ||
      rawAction == 'CHECK_OUT') {
    await _handleBackgroundLocationWakeup(message.data, isStart: false);
  }

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
      const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
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
            icon: '@drawable/ic_stat_notify',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: 'JOY PeopleHR',
            ),
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      secureLog('[PushNotificationService] Background local notification error: $e');
    }
  }
}

/// Executes background GPS telemetry sync when a Biometric Punch or Shift Tracking trigger arrives
Future<void> _handleBackgroundLocationWakeup(Map<String, dynamic> data, {required bool isStart}) async {
  try {
    if (!SupabaseConfig.isConfigured) return;

    // Ensure Supabase client is available in background isolate
    try {
      if (!Supabase.instance.isInitialized) {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          publishableKey: SupabaseConfig.anonKey,
        );
      }
    } catch (_) {}

    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) {
      secureLog('[PushNotificationService] Background location wakeup: permission not granted');
      return;
    }
    final isGpsOn = await Geolocator.isLocationServiceEnabled();
    if (!isGpsOn) {
      secureLog('[PushNotificationService] Background location wakeup: GPS is turned off on device');
      return;
    }

    final supabase = Supabase.instance.client;
    String? empId = data['employee_id']?.toString();
    String? orgId = data['organization_id']?.toString();

    // If employee_id is not in data payload, attempt to resolve from current authenticated session
    if (empId == null || empId.isEmpty) {
      final authUid = supabase.auth.currentUser?.id;
      if (authUid != null && authUid.isNotEmpty) {
        final empRes = await supabase
            .from('employees')
            .select('id, organization_id')
            .eq('user_id', authUid)
            .maybeSingle();
        if (empRes != null) {
          empId = empRes['id']?.toString();
          orgId ??= empRes['organization_id']?.toString();
        }
      }
    }

    if (empId == null || empId.isEmpty || empId == 'e0000000-0000-4000-8000-fcad91430e98') {
      secureLog('[PushNotificationService] Background location wakeup rejected (unresolved or demo employee ID: $empId)');
      return;
    }
    orgId ??= '0c621892-e938-4707-9957-13534ea32c19';

    if (!isStart) {
      // Check-out / Stop shift tracking: mark status as checked_out
      await supabase.from('employee_live_locations').update({
        'status': 'checked_out',
        'motion_state': 'stationary',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('organization_id', orgId).eq('employee_id', empId);
      secureLog('[PushNotificationService] Background location wakeup: employee $empId marked checked_out');
      return;
    }

    // 1. Fast position retrieval: last known position first
    Position? pos = await Geolocator.getLastKnownPosition();
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      secureLog('[PushNotificationService] Background high-accuracy GPS acquisition note: $e');
    }

    if (pos == null) {
      secureLog('[PushNotificationService] Background location wakeup: could not acquire GPS fix');
      return;
    }

    // 2. Read real hardware battery level and charging state
    int? batteryLevel;
    bool isCharging = false;
    try {
      final battery = Battery();
      batteryLevel = await battery.batteryLevel;
      final state = await battery.batteryState;
      isCharging = (state == BatteryState.charging || state == BatteryState.full);
    } catch (_) {}

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final isMoving = pos.speed > 0.8;

    // 3. Upsert into employee_live_locations for the HR Live Dashboard
    await supabase.from('employee_live_locations').upsert([
      {
        'organization_id': orgId,
        'employee_id': empId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy_meters': pos.accuracy,
        'speed_mps': pos.speed,
        'heading_degrees': pos.heading,
        'altitude_meters': pos.altitude,
        'status': isMoving ? 'moving' : 'on_duty',
        'battery_percentage': batteryLevel,
        'is_charging': isCharging,
        'motion_state': isMoving ? 'moving' : 'stationary',
        'recorded_at': nowIso,
        'updated_at': nowIso,
      }
    ], onConflict: 'organization_id,employee_id');

    // 4. Record breadcrumb waypoint in employee_location_trails
    await supabase.from('employee_location_trails').insert({
      'organization_id': orgId,
      'employee_id': empId,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracy_meters': pos.accuracy,
      'speed_mps': pos.speed,
      'heading_degrees': pos.heading,
      'motion_state': isMoving ? 'moving' : 'stationary',
      'battery_percentage': batteryLevel,
      'recorded_at': nowIso,
    });

    secureLog('[PushNotificationService] Background GPS telemetry synced on biometric trigger for employee: $empId (${pos.latitude}, ${pos.longitude})');
  } catch (e) {
    secureLog('[PushNotificationService] Background location wakeup error: $e');
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
  bool _isLocalNotificationsInitialized = false;
  bool get isLocalNotificationsInitialized => _isLocalNotificationsInitialized;

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

  /// Checks if notification permission is currently granted by the user / OS
  Future<bool> isPermissionGranted() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      secureLog('[PushNotificationService] isPermissionGranted notice: $e');
      return false;
    }
  }

  /// Checks if notification permission has been permanently denied
  Future<bool> isPermanentlyDenied() async {
    if (kIsWeb) return false;
    try {
      final status = await Permission.notification.status;
      return status.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  static const MethodChannel _settingsChannel = MethodChannel('com.joypeoplehr.app/settings');

  /// Opens the device app settings screen so user can manually configure permissions
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Opens direct App Notification Settings on Android (OnePlus, Oppo ColorOS, Vivo, Realme, Xiaomi)
  /// where the user can enable "Lock screen", "Banners", and "Show title and body"
  Future<bool> openNotificationSettings() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      try {
        final res = await _settingsChannel.invokeMethod<bool>('openNotificationSettings');
        if (res == true) return true;
      } catch (e) {
        secureLog('[PushNotificationService] openNotificationSettings error: $e');
      }
    }
    return await openAppSettings();
  }

  /// Opens the high-importance notification channel settings
  Future<bool> openChannelSettings({String channelId = 'joy_peoplehr_high_importance'}) async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      try {
        final res = await _settingsChannel.invokeMethod<bool>('openChannelSettings', {'channelId': channelId});
        if (res == true) return true;
      } catch (e) {
        secureLog('[PushNotificationService] openChannelSettings error: $e');
      }
    }
    return await openAppSettings();
  }

  /// Requests exemption from battery optimizations so the OS (ColorOS/Vivo/Realme) does not kill background notifications
  Future<bool> requestBatteryOptimizationExemption() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      try {
        final res = await _settingsChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
        if (res == true) return true;
      } catch (_) {}
      try {
        final isIgnored = await Permission.ignoreBatteryOptimizations.isGranted;
        if (!isIgnored) {
          final status = await Permission.ignoreBatteryOptimizations.request();
          return status.isGranted;
        }
        return true;
      } catch (_) {}
    }
    return false;
  }

  /// Explicitly requests notification permission from the user on Android (13+) and iOS
  Future<bool> requestNotificationPermission() async {
    if (kIsWeb) return true;
    try {
      // 1. Android 13+ local notifications permission
      final androidImpl =
          _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final androidGranted = await androidImpl?.requestNotificationsPermission();

      // 2. iOS local notifications permission
      final iosImpl =
          _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 3. Permission handler (triggers native OS permission dialog)
      final status = await Permission.notification.request();

      // 4. Firebase Messaging permission
      try {
        await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}

      // 5. Request Battery Optimization Exemption on Android (prevents lock screen kills on Oppo/Vivo/OnePlus/Xiaomi)
      if (Platform.isAndroid) {
        try {
          final isIgnored = await Permission.ignoreBatteryOptimizations.isGranted;
          if (!isIgnored) {
            await Permission.ignoreBatteryOptimizations.request();
          }
        } catch (_) {}
      }

      final granted = status.isGranted || androidGranted == true || iosGranted == true;
      secureLog('[PushNotificationService] requestNotificationPermission outcome: granted=$granted, status=$status');
      return granted;
    } catch (e) {
      secureLog('[PushNotificationService] requestNotificationPermission error: $e');
      return false;
    }
  }

  /// Initializes the local notification plugin and high-importance notification channel immediately
  Future<void> initLocalNotifications() async {
    if (_isLocalNotificationsInitialized || kIsWeb) return;

    try {
      const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
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

      _isLocalNotificationsInitialized = true;
      secureLog('[PushNotificationService] Local notification system initialized with high-importance channel.');
    } catch (e) {
      secureLog('[PushNotificationService] Local notification init notice: $e');
    }
  }

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
      // 1. Initialize local notifications first so alerts & tray work immediately
      await initLocalNotifications();

      // 2. Set background messaging handler
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (e) {
        secureLog('[PushNotificationService] onBackgroundMessage notice: $e');
      }

      // 3. User permission is requested deliberately via PermissionGatekeeper or Notification screen

      // 4. Set iOS foreground presentation options
      try {
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}

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
        _storeNotification(message);
        _handleNotificationNavigation(message.data);
      });

      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        secureLog('[PushNotificationService] Opened from terminated notification: ${initialMessage.data}');
        _storeNotification(initialMessage);
        _handleNotificationNavigation(initialMessage.data);
      }

      // 7. Retrieve and sync FCM Token (safe & resilient)
      try {
        await _syncFcmToken();
        await _subscribeToTopics();

        _fcm.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          _saveTokenToSupabase(newToken);
          _syncTokenToUpstash(newToken);
        });
      } catch (e) {
        secureLog('[PushNotificationService] Token sync / topic subscription notice: $e');
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
      _isInitialized = true;
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
        String employeeId = user.resolvedEmployeeId;

        // Fallback: If user.resolvedEmployeeId is still resolving, resolve directly from DB by auth user ID
        if (employeeId.isEmpty && authUid != null && authUid.isNotEmpty) {
          try {
            final empRes = await Supabase.instance.client
                .from('employees')
                .select('id')
                .eq('user_id', authUid)
                .maybeSingle();
            if (empRes != null && empRes['id'] != null) {
              employeeId = empRes['id'].toString();
            }
          } catch (_) {}
        }

        // 1. Sync to employee_device_tokens table
        try {
          final nowIso = DateTime.now().toIso8601String();
          await Supabase.instance.client.from('employee_device_tokens').upsert([
            {
              'employee_id': employeeId.isNotEmpty ? employeeId : (authUid ?? 'anonymous'),
              'auth_user_id': authUid ?? '',
              if (user.organizationId?.isNotEmpty == true) 'organization_id': user.organizationId,
              'fcm_token': token,
              'platform': defaultTargetPlatform.name.toLowerCase(),
              'token_status': 'ACTIVE',
              'last_active_at': nowIso,
              'updated_at': nowIso,
            }
          ], onConflict: 'auth_user_id,fcm_token');
          secureLog('[PushNotificationService] Token synced to employee_device_tokens for employee: $employeeId, authUser: $authUid');
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

  /// Cleanly unregisters token and unsubscribes from personal topics on logout
  Future<void> onLogout() async {
    try {
      final user = UserService.instance.currentUser;
      final empId = user.resolvedEmployeeId;
      final authUid = Supabase.instance.client.auth.currentUser?.id;

      if (_fcmToken != null && SupabaseConfig.isConfigured) {
        try {
          await Supabase.instance.client
              .from('employee_device_tokens')
              .delete()
              .eq('fcm_token', _fcmToken!);
          secureLog('[PushNotificationService] Unregistered device token on logout');
        } catch (_) {}
      }

      if (empId.isNotEmpty) {
        try {
          await _fcm.unsubscribeFromTopic('emp_$empId');
        } catch (_) {}
      }
      if (authUid != null && authUid.isNotEmpty) {
        try {
          await _fcm.unsubscribeFromTopic('user_$authUid');
        } catch (_) {}
      }
    } catch (e) {
      secureLog('[PushNotificationService] onLogout notice: $e');
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

    if ((message.notification != null || body.isNotEmpty) && !kIsWeb) {
      if (!_isLocalNotificationsInitialized) {
        initLocalNotifications();
      }
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
              icon: '@drawable/ic_stat_notify',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              styleInformation: BigTextStyleInformation(
                body,
                contentTitle: title,
                summaryText: 'JOY PeopleHR',
              ),
              category: AndroidNotificationCategory.message,
              visibility: NotificationVisibility.public,
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

    if (!kIsWeb) {
      if (!_isLocalNotificationsInitialized) {
        await initLocalNotifications();
      }
      try {
        // Deterministic ID derived from title and route collapses duplicate push alerts
        final int notifId = (title + route).hashCode & 0x7FFFFFFF;
        await _localNotifications.show(
          notifId,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: '@drawable/ic_stat_notify',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              styleInformation: BigTextStyleInformation(
                body,
                contentTitle: title,
                summaryText: 'JOY PeopleHR',
              ),
              category: AndroidNotificationCategory.message,
              visibility: NotificationVisibility.public,
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

  /// Dispatches a targeted break-ending / break-exceeded alert to the employee
  /// currently on break, with multi-pulse haptic vibration, local push, and banner.
  Future<void> showBreakAlertNotification({
    required String title,
    required String body,
    required String breakId,
    bool isExceeded = false,
  }) async {
    // Trigger real platform vibration (navigator.vibrate on Web, HapticFeedback.vibrate on Mobile)
    await HapticVibrator.vibrateAlert(urgent: isExceeded);

    final payload = <String, dynamic>{
      'route': 'attendance',
      'type': isExceeded ? 'break_exceeded' : 'break_ending',
      'break_id': breakId,
    };

    if (!kIsWeb) {
      if (!_isLocalNotificationsInitialized) {
        await initLocalNotifications();
      }
      try {
        final int notifId = ('brk_${breakId}_${isExceeded ? 'exp' : 'warn'}').hashCode & 0x7FFFFFFF;
        final vibrationPattern = Int64List.fromList(
          isExceeded ? [0, 450, 180, 450, 180, 450] : [0, 350, 160, 350],
        );
        await _localNotifications.show(
          notifId,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: '@drawable/ic_stat_notify',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              vibrationPattern: vibrationPattern,
              enableLights: true,
              styleInformation: BigTextStyleInformation(
                body,
                contentTitle: title,
                summaryText: 'Break Policy Alert',
              ),
              category: AndroidNotificationCategory.reminder,
              visibility: NotificationVisibility.public,
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
        secureLog('[PushNotificationService] Failed to show break alert: $e');
      }
    }

    LocalNotificationStore.instance.addNotification(
      title: title,
      body: body,
      route: 'attendance',
      data: payload,
    );

    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      InAppNotificationBanner.show(
        context,
        title: title,
        body: body,
        route: 'attendance',
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
        case 'lms':
        case 'courses':
        case 'training':
        case 'lms_reminder':
        case 'LMS_REMINDER':
          onOpenScreen?.call('lms', params: data);
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
