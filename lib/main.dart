import 'dart:async';
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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Fast path: if user was preloaded from disk in main(), start immediately authenticated
    final isAlreadyLogged = UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest';
    _isAuthenticated = isAlreadyLogged;
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
          if (!_isAuthenticated && data.session != null) {
            _checkSession();
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
        }
      });
    }
  }

  Future<void> _checkSession() async {
    if (_isCheckingSessionRunning) return;
    _isCheckingSessionRunning = true;

    try {
      logProcess('AUTH', 'Checking existing session & device cache...');
      bool hasPermissions = kIsWeb;

      // 1. Load locally cached user model immediately (0ms latency, works offline)
      final cached = await UserService.instance.loadCachedUser();
      final isPersisted = await UserService.instance.isSessionPersisted();
      final hasLocalUser = cached != null ||
          isPersisted ||
          (UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest');

      // If local user is already found on disk, mark as authenticated right away
      if (hasLocalUser && mounted) {
        setState(() {
          _isAuthenticated = true;
          _isCheckingSession = false;
        });
      }

      final results = await Future.wait<dynamic>([
        SupabaseAuthRepository().restoreSession(),
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
          })(),
      ]);

      final user = results[0];
      if (!kIsWeb && results.length > 1) {
        // If permissions were already verified earlier, preserve them unless explicitly revoked
        hasPermissions = results[1] == true || _permissionsGranted;
      }

      // If user came from restoreSession OR local disk cache was present OR user was already logged in,
      // KEEP USER AUTHENTICATED! Never downgrade an active session on transient Wi-Fi/LTE network drops.
      final isAuth = _isAuthenticated ||
          user != null ||
          (UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest') ||
          hasLocalUser;

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
          _permissionsGranted = hasPermissions;
        });
      }
    } finally {
      _isCheckingSessionRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isCheckingSession
          ? const _StartupSplashScreen(key: ValueKey('splash'))
          : (!_isAuthenticated
              ? LoginScreen(
                  key: const ValueKey('login'),
                  onLoginSuccess: () async {
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
                      onPermissionsGranted: () {
                        logProcess('PERMISSIONS', 'All required permissions granted');
                        setState(() {
                          _permissionsGranted = true;
                        });
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
