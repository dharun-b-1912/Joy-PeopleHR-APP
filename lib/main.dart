import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workforce_os/core/config/supabase_config.dart';
import 'package:workforce_os/core/services/attendance_service.dart';
import 'package:workforce_os/core/services/location_service.dart';
import 'package:workforce_os/core/services/shift_tracking_service.dart';
import 'package:workforce_os/core/services/background_tracking_service.dart';
import 'package:workforce_os/core/services/user_service.dart';
import 'package:workforce_os/core/theme/klarna_tokens.dart';
import 'package:workforce_os/core/utils/secure_log.dart';
import 'package:workforce_os/features/auth/screens/login_screen.dart';
import 'package:workforce_os/features/employee/attendance/screens/attendance_screen.dart';
import 'package:workforce_os/features/employee/home/screens/employee_home_screen.dart';
import 'package:workforce_os/features/employee/leave/screens/leave_screen.dart';
import 'package:workforce_os/features/employee/more/screens/more_screen.dart';
import 'package:workforce_os/features/employee/profile/screens/profile_screen.dart';
import 'package:workforce_os/features/employee/lms/screens/employee_lms_catalog_screen.dart';
import 'package:workforce_os/repositories/supabase/supabase_auth_repository.dart';
import 'package:workforce_os/widgets/floating_bottom_nav.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:workforce_os/core/services/push_notification_service.dart';
import 'package:workforce_os/core/services/app_version_service.dart';
import 'package:workforce_os/core/services/app_update_service.dart';
import 'package:workforce_os/core/services/crash_reporting_service.dart';
import 'package:workforce_os/core/config/app_env.dart';
import 'package:workforce_os/features/auth/screens/permission_gatekeeper_screen.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  logBootHeader();
  logProcess('BOOT', 'Starting JOY PeopleHR Flutter App (Web=$kIsWeb, Debug=$kDebugMode)');

  // Global Flutter framework error & crash handler
  FlutterError.onError = (FlutterErrorDetails details) {
    logCrash(
      'FlutterError.onError',
      details.exception,
      details.stack,
      reason: details.context?.toString(),
    );
    FlutterError.presentError(details);
    CrashReportingService.instance.recordError(
      details.exception,
      details.stack,
      reason: details.context?.toString(),
    );
  };

  // Global PlatformDispatcher uncaught async error & crash handler
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logCrash('PlatformDispatcher.onError', error, stack);
    CrashReportingService.instance.recordError(
      error,
      stack,
      reason: 'Uncaught asynchronous platform error',
    );
    return true;
  };

  AppEnv.verifyConfiguration();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Supabase — always runs with real credentials.
  try {
    logProcess('SUPABASE', 'Initializing Supabase client → ${SupabaseConfig.url}');
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    logProcess('SUPABASE', 'Initialized successfully → ${SupabaseConfig.url}');
  } catch (e, st) {
    logError('SUPABASE', e, st, 'Supabase.initialize failed');
  }

  // Authoritative session integrity check on boot:
  // Purges any unauthorized ghost Dharun sessions before cached profiles can preload into memory
  await _sanitizeGhostSessionsBeforeBoot();

  // Preload cached user session from disk before mounting UI
  final preloadedUser = await UserService.instance.loadCachedUser();
  if (preloadedUser != null) {
    logProcess('BOOT', 'Preloaded cached user from disk: ${preloadedUser.name} (${preloadedUser.employeeId})');
  } else {
    logProcess('BOOT', 'No preloaded user found on device disk');
  }

  // Launch UI immediately after Supabase init; initialize telemetry & push non-blockingly
  unawaited(_initializePlatformServices());

  logProcess('BOOT', 'Launching JoyPeopleHRApp root widget');
  runApp(const JoyPeopleHRApp());
}

Future<void> _sanitizeGhostSessionsBeforeBoot() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString('sp_cached_user_model_v1');
    if (rawJson == null || rawJson.trim().isEmpty) return;

    final map = jsonDecode(rawJson) as Map<String, dynamic>;
    final name = (map['name'] ?? '').toString().trim().toUpperCase();
    final empId = (map['employeeId'] ?? map['employee_id'] ?? '').toString().trim().toUpperCase();
    final email = (map['officeEmail'] ?? map['personalEmail'] ?? '').toString().trim().toLowerCase();

    var currentSession = Supabase.instance.client.auth.currentSession;
    if (currentSession == null) {
      final tokenKey = "sb-${Uri.parse(SupabaseConfig.url).host.split(".").first}-auth-token";
      final rawToken = prefs.getString(tokenKey) ?? prefs.getString("flutter.$tokenKey");
      if (rawToken != null && rawToken.trim().isNotEmpty) {
        try {
          final res = await Supabase.instance.client.auth.recoverSession(rawToken);
          currentSession = res.session;
        } catch (_) {}
      }
    }

    final sessionEmail = currentSession?.user.email?.toLowerCase().trim();

    final isDemoCache = empId == 'JCS-099' ||
        email.contains('demo') ||
        email.contains('joypeoplehr.com') ||
        name.contains('DEMO') ||
        name.contains('ARJUN KUMAR');

    if (isDemoCache) {
      // Production Safety: Allow legitimate Google Play Reviewer session, purge unauthorized ghost sessions
      final isLegitimateDemoSession = sessionEmail == 'demo.employee@joypeoplehr.com';
      if (!isLegitimateDemoSession) {
        secureLog('[BOOT-SECURITY] Authoritatively purging unauthorized demo ghost session from device disk');
        await UserService.instance.clearUser();
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        return;
      }
    }

    final isDharunCache = empId == 'JCS-017' ||
        email.contains('dharun') ||
        name == 'DHARUN' ||
        name == 'DHARUN B';

    if (isDharunCache) {
      final isLegitimateDharun = sessionEmail == 'dharun@joyglobalcorp.com' ||
          sessionEmail == 'bdharun1912@gmail.com';

      if (!isLegitimateDharun) {
        secureLog('[BOOT-SECURITY] Authoritatively purging unauthorized Dharun ghost session from device disk');
        await UserService.instance.clearUser();
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
      }
    }
  } catch (e) {
    secureLog('[BOOT-SECURITY] Sanitization notice: $e');
  }
}

Future<void> _initializePlatformServices() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await CrashReportingService.instance.initialize();
    logProcess('FIREBASE', 'Initialized with Crashlytics');
  } catch (e) {
    secureLog('[Firebase] Initialization notice (expected on Web if unconfigured): $e');
  }

  try {
    await PushNotificationService.instance.initialize();
    logProcess('PUSH', 'PushNotificationService initialized');
  } catch (e) {
    secureLog('[Push] Initialization notice: $e');
  }

  logProcess('SERVICES', 'Initializing AttendanceService, LocationService & ShiftTrackingService');
  AttendanceService.instance.initializeSession();
  LocationService.instance.initialize();
  ShiftTrackingService.instance.initialize();
  await BackgroundTrackingService.instance.initialize();
  await AppVersionService.instance.init();
}

class JoyPeopleHRApp extends StatelessWidget {
  const JoyPeopleHRApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      title: 'JOY PeopleHR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.scaffoldBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.primaryAccent,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: SmoothFastTransitionsBuilder(),
            TargetPlatform.iOS: SmoothFastTransitionsBuilder(),
            TargetPlatform.windows: SmoothFastTransitionsBuilder(),
            TargetPlatform.macOS: SmoothFastTransitionsBuilder(),
            TargetPlatform.linux: SmoothFastTransitionsBuilder(),
            TargetPlatform.fuchsia: SmoothFastTransitionsBuilder(),
          },
        ),
      ),
      home: const AuthGatekeeper(),
    );
  }
}

/// Ultra-smooth 0.5x responsive page transition builder (180ms easeOutCubic curve)
class SmoothFastTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothFastTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final secondaryCurvedAnimation = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.06, 0.0),
        end: Offset.zero,
      ).animate(curvedAnimation),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.03, 0.0),
          ).animate(secondaryCurvedAnimation),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1.0, end: 0.9).animate(secondaryCurvedAnimation),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AuthGatekeeper extends StatefulWidget {
  const AuthGatekeeper({super.key});

  @override
  State<AuthGatekeeper> createState() => _AuthGatekeeperState();
}

class _AuthGatekeeperState extends State<AuthGatekeeper> {
  late bool _isCheckingSession;
  late bool _isAuthenticated;
  bool _permissionsGranted = false;
  bool _isCheckingSessionRunning = false;
  bool _pendingSessionCheck = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Fast path: if user was preloaded from disk in main(), start immediately authenticated
    final isAlreadyLogged = UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest';
    _isAuthenticated = isAlreadyLogged;
    _permissionsGranted = isAlreadyLogged;
    _isCheckingSession = !isAlreadyLogged;

    UserService.instance.addListener(_onUserChanged);
    _checkSession();
    _listenToAuthChanges();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    UserService.instance.removeListener(_onUserChanged);
    super.dispose();
  }

  void _listenToAuthChanges() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        final hasSess = data.session != null;
        logProcess('AUTH', 'onAuthStateChange: ${event.name} (hasSession=$hasSess, reason=${data.signOutReason})');
        if (!mounted) return;

        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed ||
            event == AuthChangeEvent.initialSession) {
          if (data.session != null) {
            if (_isCheckingSessionRunning) {
              _pendingSessionCheck = true;
            } else {
              _checkSession();
            }
          }
        } else if (event == AuthChangeEvent.signedOut) {
          // Never clear local persistent session on involuntary signedOut events!
          // Gotrue emits involuntary signedOut on cold boot, network disconnects,
          // or during token refresh delays.
          // Explicit user-initiated signouts are handled via SupabaseAuthRepository.signOut()
          // which directly invokes UserService.instance.clearUser().
          // Only on web with an explicit user-initiated signout (e.g. from another tab) do we clear.
          if (kIsWeb && data.signOutReason == SignOutReason.userInitiated) {
            await UserService.instance.clearUser();
            if (mounted) {
              setState(() {
                _isAuthenticated = false;
              });
            }
          }
        }
      },
    );
  }

  void _onUserChanged() {
    if (mounted) {
      final isLogged = UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest';
      setState(() {
        _isAuthenticated = isLogged;
        if (isLogged) {
          _isCheckingSession = false;
          _permissionsGranted = true;
        }
      });
    }
  }

  Future<void> _checkSession() async {
    if (_isCheckingSessionRunning) {
      _pendingSessionCheck = true;
      return;
    }
    _isCheckingSessionRunning = true;

    try {
      logProcess('AUTH', 'Checking existing session & device cache...');
      bool hasPermissions = kIsWeb;

      // 0. Security Guard: Purge any unauthorized ghost sessions (e.g. stale Dharun test cache)
      // If an employee device has Dharun cached but NO active Supabase Auth session matching Dharun's email,
      // purge the cached profile from disk immediately so the employee is directed to the clean login screen.
      try {
        final cachedUser = await UserService.instance.loadCachedUser();
        if (cachedUser != null) {
          var currentSession = Supabase.instance.client.auth.currentSession;
          if (currentSession == null) {
            try {
              final prefs = await SharedPreferences.getInstance();
              final tokenKey = "sb-${Uri.parse(SupabaseConfig.url).host.split(".").first}-auth-token";
              final rawToken = prefs.getString(tokenKey) ?? prefs.getString("flutter.$tokenKey");
              if (rawToken != null && rawToken.trim().isNotEmpty) {
                final recovered = await Supabase.instance.client.auth.recoverSession(rawToken);
                currentSession = recovered.session;
              }
            } catch (_) {}
          }

          final sessionEmail = currentSession?.user.email?.toLowerCase().trim();

          final isDemoUser = cachedUser.employeeId == 'JCS-099' ||
              (cachedUser.officeEmail?.toLowerCase().contains('demo') ?? false) ||
              (cachedUser.officeEmail?.toLowerCase().contains('joypeoplehr.com') ?? false) ||
              cachedUser.name.trim().toUpperCase().contains('ARJUN KUMAR') ||
              cachedUser.name.trim().toUpperCase().contains('DEMO');

          if (isDemoUser) {
            final isLegitimateDemoSession = sessionEmail == 'demo.employee@joypeoplehr.com';
            if (!isLegitimateDemoSession) {
              secureLog('[Security] Purging unauthorized demo ghost session from employee device');
              await UserService.instance.clearUser();
              try {
                await Supabase.instance.client.auth.signOut();
              } catch (_) {}
            }
          }

          final isDharunCache = cachedUser.employeeId == 'JCS-017' ||
              (cachedUser.officeEmail?.toLowerCase().contains('dharun') ?? false) ||
              cachedUser.name.trim().toUpperCase() == 'DHARUN' ||
              cachedUser.name.trim().toUpperCase() == 'DHARUN B';

          if (isDharunCache) {
            final isLegitimateDharun = sessionEmail == 'dharun@joyglobalcorp.com' ||
                sessionEmail == 'bdharun1912@gmail.com';

            if (!isLegitimateDharun) {
              secureLog('[Security] Purging unauthorized ghost Dharun session from employee device');
              await UserService.instance.clearUser();
              try {
                await Supabase.instance.client.auth.signOut();
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        secureLog('[Security] Session sanitization notice: $e');
      }

      // 1. Check if authenticated user model exists locally with verified session
      final cached = await UserService.instance.loadCachedUser();
      final isPersisted = await UserService.instance.isSessionPersisted();
      final currentSession = Supabase.instance.client.auth.currentSession;
      final hasLocalUser = (cached != null || isPersisted) &&
          UserService.instance.isLoggedIn &&
          UserService.instance.currentUser.name != 'Guest' &&
          currentSession != null;

      final prefs = await SharedPreferences.getInstance();
      final isEnrolled = prefs.getBool('sp_permissions_enrolled_v1') ?? false;

      // If legitimate local user is already verified with active session, proceed immediately
      if (hasLocalUser && mounted) {
        setState(() {
          _isAuthenticated = true;
          _permissionsGranted = true;
          _isCheckingSession = false;
        });
      }

      // 2. Non-blocking bounded session restore with max 4-second timeout
      final results = await Future.wait<dynamic>([
        SupabaseAuthRepository().restoreSession().timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            secureLog('[AuthGatekeeper] restoreSession timed out, falling back to local session');
            return null;
          },
        ),
        if (!kIsWeb)
          (() async {
            try {
              final locPerm = await Geolocator.checkPermission();
              final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
              final hasLoc = isServiceEnabled &&
                  (locPerm == LocationPermission.always || locPerm == LocationPermission.whileInUse);
              final hasNotif = await PushNotificationService.instance.isPermissionGranted();
              return hasLoc && hasNotif;
            } catch (e) {
              secureLog('[AuthGatekeeper] Permission check notice: $e');
              return false;
            }
          })().timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          ),
      ]);

      final user = results.isNotEmpty ? results[0] : null;
      if (!kIsWeb && results.length > 1) {
        // Authenticated employees with existing sessions or enrolled permissions never get blocked
        hasPermissions = hasLocalUser || isEnrolled || results[1] == true || _permissionsGranted;
      } else {
        hasPermissions = true;
      }

      // If user came from restoreSession OR verified active Supabase session with local user:
      final currentActiveSession = Supabase.instance.client.auth.currentSession;
      final bool isAuth;
      if (user != null) {
        isAuth = true;
      } else if (currentActiveSession != null &&
          UserService.instance.isLoggedIn &&
          UserService.instance.currentUser.name != 'Guest') {
        isAuth = true;
      } else {
        // No valid Supabase session exists on this device — strictly unauthenticated
        await UserService.instance.clearUser();
        isAuth = false;
      }

      logProcess('AUTH', 'Session restore complete', data: {
        'isAuthenticated': isAuth,
        'name': user?.name ?? UserService.instance.currentUser.name,
        'employeeId': user?.employeeId ?? UserService.instance.currentUser.employeeId,
        'permissionsGranted': hasPermissions,
      });

      if (mounted) {
        setState(() {
          _isCheckingSession = false;
          _isAuthenticated = isAuth;
          _permissionsGranted = hasPermissions || isAuth;
        });

        // Check for updates on startup (catches security and mandatory updates early)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            AppUpdateService.instance.checkAndShowUpdateDialog(context);
          }
        });
      }
    } catch (e, st) {
      secureLog('[AuthGatekeeper] _checkSession error: $e\n$st');
    } finally {
      _isCheckingSessionRunning = false;
      if (mounted && _isCheckingSession) {
        setState(() {
          _isCheckingSession = false;
        });
      }
      if (_pendingSessionCheck && mounted) {
        _pendingSessionCheck = false;
        unawaited(_checkSession());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveSession = _isAuthenticated ||
        UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isCheckingSession
          ? const _StartupSplashScreen(key: ValueKey('splash'))
          : (!hasActiveSession
              ? LoginScreen(
                  key: const ValueKey('login'),
                  onLoginSuccess: () async {
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('sp_permissions_enrolled_v1', true);
                    } catch (_) {}
                    bool hasPerms = kIsWeb;
                    if (!kIsWeb) {
                      try {
                        final locPerm = await Geolocator.checkPermission();
                        final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
                        final hasLoc = isServiceEnabled &&
                            (locPerm == LocationPermission.always || locPerm == LocationPermission.whileInUse);
                        final hasNotif = await PushNotificationService.instance.isPermissionGranted();
                        hasPerms = hasLoc && hasNotif;
                      } catch (_) {}
                    }
                    final curUser = UserService.instance.currentUser;
                    await UserService.instance.persistUser(curUser);
                    logProcess('AUTH', 'Login succeeded → entering app shell', data: {
                      'name': curUser.name,
                      'employeeId': curUser.employeeId,
                      'companyId': curUser.companyId,
                      'permissionsGranted': hasPerms,
                    });
                    if (mounted) {
                      setState(() {
                        _isAuthenticated = true;
                        _permissionsGranted = hasPerms;
                      });
                    }
                  },
                )
              : (!_permissionsGranted
                  ? PermissionGatekeeperScreen(
                      key: const ValueKey('permissions'),
                      onPermissionsGranted: () async {
                        logProcess('PERMISSIONS', 'All required permissions granted');
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('sp_permissions_enrolled_v1', true);
                        } catch (_) {}
                        if (mounted) {
                          setState(() {
                            _permissionsGranted = true;
                          });
                        }
                      },
                    )
                  : const MainTabShell(key: ValueKey('home')))),
    );
  }
}

/// Lightweight, fast Startup Splash Screen
class _StartupSplashScreen extends StatefulWidget {
  const _StartupSplashScreen({super.key});

  @override
  State<_StartupSplashScreen> createState() => _StartupSplashScreenState();
}

class _StartupSplashScreenState extends State<_StartupSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnimation = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        width: 60,
                        height: 60,
                        cacheWidth: 180,
                        cacheHeight: 180,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            CupertinoIcons.person_2_fill,
                            color: Color(0xFF07563D),
                            size: 36,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  "JOY PeopleHR",
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    "People • Culture • Workspace",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 96,
                  height: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainTabShell extends StatefulWidget {
  const MainTabShell({super.key});

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class TabDescriptor {
  final IconData icon;
  final String label;
  final Widget screen;
  final int? badge;

  TabDescriptor({
    required this.icon,
    required this.label,
    required this.screen,
    this.badge,
  });
}

class _MainTabShellState extends State<MainTabShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    UserService.instance.addListener(_onUserChanged);

    // Register notification navigation callbacks
    PushNotificationService.onNavigateToTab = (int tabIndex) {
      if (mounted && tabIndex >= 0 && tabIndex < _getTabs().length) {
        setState(() => _currentIndex = tabIndex);
      }
    };

    PushNotificationService.onOpenScreen = (String screen, {Map<String, dynamic>? params}) {
      if (mounted) {
        if (screen == 'lms') {
          Navigator.of(context).push(
            CupertinoPageRoute(builder: (_) => const EmployeeLmsCatalogScreen()),
          );
        }
      }
    };

    // Evaluate in-app updates seamlessly on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.instance.checkAndShowUpdateDialog(context);
      }
    });
  }

  @override
  void dispose() {
    PushNotificationService.onNavigateToTab = null;
    PushNotificationService.onOpenScreen = null;
    UserService.instance.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) {
      final tabsCount = _getTabs().length;
      setState(() {
        if (_currentIndex >= tabsCount) {
          _currentIndex = 0;
        }
      });
    }
  }

  List<TabDescriptor> _getTabs() {
    final user = UserService.instance.currentUser;

    return [
      TabDescriptor(
        icon: CupertinoIcons.house_fill,
        label: 'Home',
        screen: HomeDashboardScreen(
          key: ValueKey(user.employeeId),
          onOpenServices: () {
            // "View All" in Quick Actions switches directly to 'More' tab (index 3)
            setState(() => _currentIndex = 3);
          },
        ),
      ),
      TabDescriptor(
        icon: CupertinoIcons.clock_fill,
        label: 'Attendance',
        screen: const AttendanceScreen(),
      ),
      TabDescriptor(
        icon: CupertinoIcons.calendar,
        label: 'Leave',
        screen: const LeaveScreen(),
      ),
      TabDescriptor(
        icon: CupertinoIcons.square_grid_2x2_fill,
        label: 'More',
        screen: const MoreScreen(),
      ),
      TabDescriptor(
        icon: CupertinoIcons.person_crop_circle_fill,
        label: 'Profile',
        screen: const ProfileScreen(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _getTabs();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex < tabs.length ? _currentIndex : 0,
              children: tabs.map((t) => t.screen).toList(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingBottomNav(
                currentIndex: _currentIndex < tabs.length ? _currentIndex : 0,
                items: tabs
                    .map((t) => {
                          'icon': t.icon,
                          'label': t.label,
                          'badge': t.badge,
                        })
                    .toList(),
                onTap: (index) {
                  if (index >= 0 && index < tabs.length) {
                    logProcess('NAVIGATION', 'Switched tab → ${tabs[index].label} (index=$index)');
                  }
                  setState(() => _currentIndex = index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
