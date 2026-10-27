import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/shift_tracking_service.dart';
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
    try {
      final hasNotif = await PushNotificationService.instance.isPermissionGranted();
      setState(() {
        _isNotificationGranted = hasNotif;
      });
    } catch (_) {
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
        await Geolocator.openLocationSettings();
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
        setState(() {
          _errorMessage = 'Location permission is permanently denied. Please tap "Open Settings" below.';
          _isRequesting = false;
        });
        await Geolocator.openAppSettings();
        return;
      }

      if (permission == LocationPermission.denied) {
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
      final isPermanentlyDenied = await PushNotificationService.instance.isPermanentlyDenied();
      if (isPermanentlyDenied) {
        setState(() {
          _errorMessage = 'Notification permission is disabled in App Settings. Please tap "Open Settings" below.';
          _isRequesting = false;
        });
        await PushNotificationService.instance.openNotificationSettings();
        return;
      }

      final granted = await PushNotificationService.instance.requestNotificationPermission();
      if (granted) {
        setState(() {
          _isNotificationGranted = true;
          _errorMessage = null;
          _isRequesting = false;
        });

        // Trigger welcome confirmation in notification tray
        PushNotificationService.instance.triggerTestNotification(
          title: "🔔 Notifications Enabled",
          body: "You're all set to receive HR announcements, leave approvals, and payslip alerts.",
          route: "home",
        );

        _checkAllGranted();
        return;
      }

      final checkAgain = await PushNotificationService.instance.isPermissionGranted();
      if (checkAgain) {
        setState(() {
          _isNotificationGranted = true;
          _errorMessage = null;
          _isRequesting = false;
        });
        _checkAllGranted();
        return;
      }

      final deniedNow = await PushNotificationService.instance.isPermanentlyDenied();
      if (deniedNow) {
        setState(() {
          _errorMessage = 'Notification permission is disabled. Tap "Open Settings" to enable.';
          _isRequesting = false;
        });
        await PushNotificationService.instance.openNotificationSettings();
        return;
      }

      setState(() {
        _errorMessage = 'Notification permission is required to receive company alerts and payslips. Please grant it.';
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
      // Immediately transmit device GPS to live fleet radar upon permission grant
      ShiftTrackingService.instance.syncCurrentDeviceLocation();
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
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
                          if (_errorMessage!.contains("Settings")) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(CupertinoIcons.gear, size: 14, color: AppColors.primary),
                                label: const Text(
                                  "Open Settings",
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                                onPressed: () async {
                                  await PushNotificationService.instance.openNotificationSettings();
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  if (!kIsWeb && Platform.isAndroid) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            CupertinoIcons.info_circle_fill,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "OnePlus / Oppo / Vivo / Realme / Xiaomi: Ensure 'Lock screen' and 'Banners' are enabled, and set Lock screen notifications to 'Show title and body'.",
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                height: 1.35,
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
                                }
                                if (!_isNotificationGranted && mounted) {
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
