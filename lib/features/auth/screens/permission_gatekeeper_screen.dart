import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../core/utils/secure_log.dart';
import '../../../widgets/core/app_button.dart';

/// PermissionGatekeeperScreen — Mandatory permission enrollment screen.
///
/// Forces the employee to grant Location + Notification permissions
/// before they can access the main app. This screen is shown after
/// successful login or session restore.
class PermissionGatekeeperScreen extends StatefulWidget {
  final VoidCallback onPermissionsGranted;

  const PermissionGatekeeperScreen({
    super.key,
    required this.onPermissionsGranted,
  });

  @override
  State<PermissionGatekeeperScreen> createState() =>
      _PermissionGatekeeperScreenState();
}

class _PermissionGatekeeperScreenState extends State<PermissionGatekeeperScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  bool _isLocationGranted = false;
  bool _isNotificationGranted = false;
  bool _isRequesting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();

    // Check current permission status on load
    _checkCurrentPermissions();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentPermissions() async {
    // Check location
    LocationPermission locPerm = await Geolocator.checkPermission();
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    setState(() {
      _isLocationGranted =
          serviceEnabled &&
          (locPerm == LocationPermission.always ||
              locPerm == LocationPermission.whileInUse);
    });

    // Check notification
    // On Android 13+ we can check via permission_handler
    try {
      final notifPerm = await Permission.notification.status;
      setState(() {
        _isNotificationGranted = notifPerm.isGranted;
      });
    } catch (_) {
      // permission_handler may not be available, assume granted on older Android
      setState(() {
        _isNotificationGranted = true;
      });
    }

    // If both already granted, auto-proceed
    if (_isLocationGranted && _isNotificationGranted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          widget.onPermissionsGranted();
        }
      });
    }
  }

  // ─── Location Permission ────────────────────────────────────
  Future<void> _requestLocationPermission() async {
    if (_isRequesting) return;
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });

    try {
      // 1. Check if GPS hardware/service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Open device location settings
        await Geolocator.openLocationSettings();
        // Wait for user to return
        await Future.delayed(const Duration(seconds: 2));
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() {
            _errorMessage = 'Please enable GPS/Location in device settings to continue.';
            _isRequesting = false;
          });
          return;
        }
      }

      // 2. Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        // Permanently denied — must open app settings
        setState(() {
          _errorMessage = 'Location permission was permanently denied. Please enable it in App Settings.';
          _isRequesting = false;
        });
        await Geolocator.openAppSettings();
        return;
      }

      if (permission == LocationPermission.denied) {
        // Request permission
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        setState(() {
          _isLocationGranted = true;
          _errorMessage = null;
          _isRequesting = false;
        });
        _checkAllGranted();
      } else {
        setState(() {
          _errorMessage = 'Location permission is required for attendance clocking. Please grant it to continue.';
          _isRequesting = false;
        });
      }
    } catch (e) {
      secureLog('[PermissionGatekeeper] Location request error: $e');
      setState(() {
        _errorMessage = 'Failed to request location permission. Please try again.';
        _isRequesting = false;
      });
    }
  }

  // ─── Notification Permission ────────────────────────────────
  Future<void> _requestNotificationPermission() async {
    if (_isRequesting) return;
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });

    try {
      // Use the FCM service which already handles permission request
      await PushNotificationService.instance.initialize();

      // Check via permission_handler
      try {
        final status = await Permission.notification.status;
        if (status.isGranted) {
          setState(() {
            _isNotificationGranted = true;
            _errorMessage = null;
            _isRequesting = false;
          });
          _checkAllGranted();
          return;
        }

        // Request again if not granted
        final result = await Permission.notification.request();
        if (result.isGranted) {
          setState(() {
            _isNotificationGranted = true;
            _errorMessage = null;
            _isRequesting = false;
          });
          _checkAllGranted();
          return;
        }
      } catch (_) {
        // permission_handler not available — FCM init already requested
        setState(() {
          _isNotificationGranted = true;
          _errorMessage = null;
          _isRequesting = false;
        });
        _checkAllGranted();
        return;
      }

      setState(() {
        _errorMessage = 'Notification permission is required to receive work updates. Please grant it.';
        _isRequesting = false;
      });
    } catch (e) {
      secureLog('[PermissionGatekeeper] Notification request error: $e');
      setState(() {
        _errorMessage = 'Failed to request notification permission. Please try again.';
        _isRequesting = false;
      });
    }
  }

  void _checkAllGranted() {
    if (_isLocationGranted && _isNotificationGranted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          widget.onPermissionsGranted();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allGranted = _isLocationGranted && _isNotificationGranted;

    return PopScope(
      canPop: false, // Prevent back navigation — must grant permissions
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // Header
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.shield_lefthalf_fill,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Permissions Required",
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "JOY PeopleHR needs the following permissions to function properly. Please grant them to continue.",
                    style: AppTypography.bodyRegular.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 36),

                  // ─── Location Permission Card ─────────────
                  _PermissionCard(
                    icon: CupertinoIcons.location_solid,
                    iconColor: AppColors.primary,
                    iconBg: AppColors.skyBg,
                    title: "Location Access",
                    subtitle: "Required for attendance clock-in/out and geofence verification",
                    isGranted: _isLocationGranted,
                    onTap: _isLocationGranted ? null : _requestLocationPermission,
                    isProcessing: _isRequesting,
                  ),

                  const SizedBox(height: 14),

                  // ─── Notification Permission Card ─────────
                  _PermissionCard(
                    icon: CupertinoIcons.bell_fill,
                    iconColor: AppColors.primaryAccent,
                    iconBg: AppColors.peachBg,
                    title: "Notifications",
                    subtitle: "Receive leave approvals, regularization updates, and work alerts",
                    isGranted: _isNotificationGranted,
                    onTap: _isNotificationGranted ? null : _requestNotificationPermission,
                    isProcessing: _isRequesting,
                  ),

                  // Error message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.statusError.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.statusError.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.exclamationmark_circle_fill,
                            size: 18,
                            color: AppColors.statusError,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.statusError,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(flex: 3),

                  // ─── Continue Button ──────────────────────
                  if (allGranted)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: AppButton(
                        label: "Continue to App",
                        variant: AppButtonVariant.primaryPill,
                        icon: CupertinoIcons.arrow_right,
                        onPressed: widget.onPermissionsGranted,
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: AppButton(
                        label: _isRequesting ? "Requesting..." : "Grant Permissions",
                        variant: AppButtonVariant.primaryPill,
                        icon: CupertinoIcons.shield_lefthalf_fill,
                        onPressed: _isRequesting
                            ? null
                            : () async {
                                if (!_isLocationGranted) {
                                  await _requestLocationPermission();
                                } else if (!_isNotificationGranted) {
                                  await _requestNotificationPermission();
                                }
                              },
                      ),
                    ),

                  const SizedBox(height: 16),
                  Text(
                    "You can change these permissions later in device settings",
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Permission Card Widget ────────────────────────────────────
class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool isGranted;
  final VoidCallback? onTap;
  final bool isProcessing;

  const _PermissionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.isGranted,
    this.onTap,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isGranted ? AppColors.mintBg : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isGranted
                ? AppColors.mintFg.withValues(alpha: 0.3)
                : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isGranted ? AppColors.mintBg : iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isGranted ? CupertinoIcons.checkmark_circle_fill : icon,
                size: 22,
                color: isGranted ? AppColors.mintFg : iconColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isGranted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.mintFg.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Granted",
                  style: AppTypography.caption.copyWith(
                    color: AppColors.mintFg,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              )
            else if (isProcessing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            else
              const Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
