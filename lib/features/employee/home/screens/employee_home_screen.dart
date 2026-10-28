import '../../../../core/services/shift_duration_calculator.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/attendance_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/shift_tracking_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/app_services_catalog.dart';
import '../../../../models/hrms_models.dart';
import '../../../../widgets/applet_tile.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/avatar_image_helper.dart';
import '../../../../widgets/core/status_chip.dart';
import '../../attendance/dialogs/regularization_modal.dart';
import '../../claims/screens/expense_claims_screen.dart';
import '../../helpdesk/screens/helpdesk_screen.dart';
import '../../leave/dialogs/apply_leave_modal.dart';
import '../../payslips/screens/payslips_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../../../repositories/supabase/supabase_employee_repository.dart';
import '../../virtual_id/dialogs/virtual_id_card_dialog.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/attendance/attendance_live_timer.dart';
import '../../../../core/services/local_notification_store.dart';
import '../../locations/screens/employee_location_screen.dart';
import '../../../../core/services/push_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'notifications_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  final VoidCallback onOpenServices;

  const HomeDashboardScreen({
    super.key,
    required this.onOpenServices,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> with WidgetsBindingObserver {
  UserModel get currentUser => UserService.instance.currentUser;
  StreamSubscription<ApprovedWorkLocation>? _geofenceSubscription;
  bool _isNotificationPermissionGranted = true;


  String _getEffectiveShiftStart(UserModel user) {
    final now = DateTime.now();
    final rosters = MoreModulesController.instance.rosters;
    if (rosters.isNotEmpty) {
      for (final r in rosters) {
        if (r.date.year == now.year && r.date.month == now.month && r.date.day == now.day) {
          if (!r.isOffDay && r.startTime.trim().isNotEmpty && r.startTime != 'Week Off' && r.startTime != '—') {
            final formatted = ShiftDurationCalculator.instance.formatTimeAMPM(r.startTime, fallback: '');
            if (formatted.isNotEmpty) return formatted;
          }
        }
      }
    }
    if (user.shiftStart.trim().isNotEmpty && user.shiftStart.trim() != '—') {
      final formatted = ShiftDurationCalculator.instance.formatTimeAMPM(user.shiftStart, fallback: '');
      if (formatted.isNotEmpty) return formatted;
    }
    return "09:30 AM";
  }

  String _getEffectiveShiftEnd(UserModel user) {
    final now = DateTime.now();
    final rosters = MoreModulesController.instance.rosters;
    if (rosters.isNotEmpty) {
      for (final r in rosters) {
        if (r.date.year == now.year && r.date.month == now.month && r.date.day == now.day) {
          if (!r.isOffDay && r.endTime.trim().isNotEmpty && r.endTime != 'Week Off' && r.endTime != '—') {
            final formatted = ShiftDurationCalculator.instance.formatTimeAMPM(r.endTime, fallback: '');
            if (formatted.isNotEmpty) return formatted;
          }
        }
      }
    }
    if (user.shiftEnd.trim().isNotEmpty && user.shiftEnd.trim() != '—') {
      final formatted = ShiftDurationCalculator.instance.formatTimeAMPM(user.shiftEnd, fallback: '');
      if (formatted.isNotEmpty) return formatted;
    }
    return "06:30 PM";
  }

  String get _timeBasedGreeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning,";
    if (hour < 17) return "Good afternoon,";
    return "Good evening,";
  }

  String get _userInitials {
    final name = currentUser.name.trim();
    if (name.isEmpty) return "EM";
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final p1 = parts[0];
      final p2 = parts[1];
      final i1 = p1.isNotEmpty ? p1[0] : '';
      final i2 = p2.isNotEmpty ? p2[0] : '';
      if (i1.isNotEmpty || i2.isNotEmpty) {
        return "$i1$i2".toUpperCase();
      }
    }
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocationService.instance.addListener(_onStateChange);
    AttendanceService.instance.addListener(_onStateChange);
    NotificationController.instance.addListener(_onStateChange);
    UserService.instance.addListener(_onStateChange);
    MoreModulesController.instance.addListener(_onStateChange);
    NotificationController.instance.initialize();

    // Subscribe to Automatic Geofence Entry Prompt
    _geofenceSubscription = LocationService.instance.onGeofenceEntered.listen((loc) {
      if (mounted && !AttendanceService.instance.session.isCheckedIn) {
        _showSmartGeofencePrompt(loc);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocationService.instance.evaluateLiveLocation();
      AttendanceService.instance.fetchTodayAttendance();
      ShiftTrackingService.instance.syncCurrentDeviceLocation();
      ShiftTrackingService.instance.startShiftTracking();
      _checkNotificationPermission();
      MoreModulesController.instance.loadAllData();
      SupabaseEmployeeRepository().getCurrentEmployee();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _geofenceSubscription?.cancel();
    LocationService.instance.removeListener(_onStateChange);
    AttendanceService.instance.removeListener(_onStateChange);
    NotificationController.instance.removeListener(_onStateChange);
    UserService.instance.removeListener(_onStateChange);
    MoreModulesController.instance.removeListener(_onStateChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotificationPermission();
      LocationService.instance.resumeTracking();
      AttendanceService.instance.fetchTodayAttendance();
      ShiftTrackingService.instance.syncCurrentDeviceLocation();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      LocationService.instance.pauseTracking();
    }
  }

  Future<void> _checkNotificationPermission() async {
    if (kIsWeb) return;
    try {
      final granted = await PushNotificationService.instance.isPermissionGranted();
      if (mounted && _isNotificationPermissionGranted != granted) {
        setState(() {
          _isNotificationPermissionGranted = granted;
        });
      }
    } catch (_) {}
  }

  void _onStateChange() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Displays smart non-blocking prompt when employee arrives at work location
  void _showSmartGeofencePrompt(ApprovedWorkLocation location) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              CupertinoIcons.location_fill,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "You're at ${location.name}",
                    style: AppTypography.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "You are inside the attendance zone. Ready to clock in.",
                    style: AppTypography.overline.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: "Check In",
          textColor: AppColors.primaryAccent,
          onPressed: _handleCheckIn,
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderMd,
        ),
      ),
    );
  }

  bool _isTodayWeekOff() {
    final now = DateTime.now();
    final rosters = MoreModulesController.instance.rosters;
    if (rosters.isNotEmpty) {
      final todayRoster = rosters.firstWhere(
        (r) => r.date.year == now.year && r.date.month == now.month && r.date.day == now.day,
        orElse: () => ShiftRosterModel(
          id: '',
          date: now,
          shiftName: (now.weekday == DateTime.sunday || now.weekday == DateTime.saturday) ? 'Weekly Off' : 'General Shift',
          shiftCode: (now.weekday == DateTime.sunday || now.weekday == DateTime.saturday) ? 'OFF' : 'GEN-01',
          shiftCategory: (now.weekday == DateTime.sunday || now.weekday == DateTime.saturday) ? 'OFF' : 'DAY',
          shiftCategoryLabel: (now.weekday == DateTime.sunday || now.weekday == DateTime.saturday) ? 'Weekly Off' : 'Day',
          startTime: '',
          endTime: '',
          location: '',
          isOffDay: (now.weekday == DateTime.sunday || now.weekday == DateTime.saturday),
          isOvernight: false,
          isUpdated: false,
          rawSpanMinutes: 0,
          breakMinutes: 0,
          netScheduledMinutes: 0,
          formattedDuration: '',
          policyName: '',
          assignedBy: '',
        ),
      );
      return todayRoster.isOffDay ||
          todayRoster.shiftCategory == 'OFF' ||
          todayRoster.shiftName.toLowerCase().contains('off') ||
          todayRoster.shiftName.toLowerCase().contains('rest');
    }
    return now.weekday == DateTime.sunday || now.weekday == DateTime.saturday;
  }

  Future<void> _handleCheckIn() async {
    if (AttendanceService.instance.isProcessing) return;
    if (AttendanceService.instance.session.isCheckedIn) return;

    if (_isTodayWeekOff()) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  CupertinoIcons.moon_stars_fill,
                  color: Color(0xFFD97706),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Weekly Off Today",
                      style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Non-working Day",
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today is scheduled as your Weekly Off. Are you sure you want to check in for work today?",
                style: AppTypography.bodyRegular.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      "No, Go Back",
                      style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      "Yes, Check In",
                      style: AppTypography.bodyRegular.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;
    }

    final location = await LocationService.instance.evaluateLiveLocation();
    final result = await AttendanceService.instance.performCheckIn(
      location: location,
      approvedLocation: currentUser.approvedLocation,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              result.success
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.exclamationmark_triangle_fill,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.message,
                style: AppTypography.bodyLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: result.success ? AppColors.primary : AppColors.statusError,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderMd,
        ),
      ),
    );
  }

  Future<void> _handleCheckOut() async {
    if (AttendanceService.instance.isProcessing) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Verifying your location for checkout...",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Step 1: Evaluate WHERE the employee is checking out from
    final verification = await LocationService.instance.evaluateCheckoutLocation();

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Step 2: If verification requires a reason, show reason input dialog
    String? reason;
    if (verification.requiresReason) {
      reason = await _showReasonInputDialog(verification);
      if (reason == null) return; // Employee cancelled
    }

    if (!mounted) return;

    // Step 3: Show confirmation dialog with location verification info
    final confirmed = await _showCheckOutConfirmationDialog(verification);

    if (confirmed != true) return;
    if (!mounted) return;

    // Step 4: Perform check-out with verification data
    final result = await AttendanceService.instance.performCheckOut(
      verification: verification,
      reason: reason,
    );

    if (!mounted) return;

    // Show location-specific success/failure message
    final snackBarColor = result.success ? AppColors.primary : AppColors.statusError;
    final snackBarIcon = result.success
        ? CupertinoIcons.checkmark_circle_fill
        : CupertinoIcons.exclamationmark_triangle_fill;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(snackBarIcon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.message,
                style: AppTypography.bodyLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: snackBarColor,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderMd,
        ),
      ),
    );
  }

  /// Shows a reason input dialog when checkout location is unauthorized or GPS unavailable
  Future<String?> _showReasonInputDialog(CheckoutLocationVerification verification) async {
    final reasonController = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final screenWidth = MediaQuery.sizeOf(dialogCtx).width;
        final maxDialogWidth = screenWidth > 440 ? 380.0 : (screenWidth - 32.0).clamp(280.0, 380.0);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasText = reasonController.text.trim().length >= 3;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxDialogWidth),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWhite,
                      borderRadius: AppRadius.borderLg,
                      boxShadow: AppShadows.softCard,
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Location status icon
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: verification.status == CheckoutLocationStatus.gpsUnavailable
                                ? AppColors.peachBg
                                : AppColors.lemonBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            verification.status == CheckoutLocationStatus.gpsUnavailable
                                ? CupertinoIcons.location_slash
                                : CupertinoIcons.question_circle,
                            color: verification.status == CheckoutLocationStatus.gpsUnavailable
                                ? AppColors.peachFg
                                : AppColors.lemonFg,
                            size: 26,
                          ),
                        ),
                        AppSpacing.gapMD,
                        Text(
                          verification.status == CheckoutLocationStatus.gpsUnavailable
                              ? "Location Unavailable"
                              : "Different Location Detected",
                          style: AppTypography.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          verification.status == CheckoutLocationStatus.gpsUnavailable
                              ? "We couldn't verify your GPS location. Please provide a reason for checking out without location verification."
                              : "You are checking out from an unrecognized location. Please provide a reason for your records.",
                          style: AppTypography.bodyRegular.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (verification.status != CheckoutLocationStatus.gpsUnavailable &&
                            verification.latitude != 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Captured: ${verification.latitude.toStringAsFixed(5)}, ${verification.longitude.toStringAsFixed(5)}",
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Reason text field
                        TextField(
                          controller: reasonController,
                          maxLines: 3,
                          minLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: "Enter reason (minimum 3 characters)...",
                            hintStyle: AppTypography.bodyRegular.copyWith(
                              color: AppColors.textMuted,
                            ),
                            filled: true,
                            fillColor: AppColors.slateBg,
                            border: OutlineInputBorder(
                              borderRadius: AppRadius.borderMd,
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        AppSpacing.gapMD,
                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                            onTap: hasText
                                ? () => Navigator.of(dialogCtx).pop(reasonController.text.trim())
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                color: hasText ? AppColors.primary : AppColors.textMuted,
                                borderRadius: AppRadius.borderPill,
                                boxShadow: hasText ? AppShadows.pillDark : [],
                              ),
                              child: Center(
                                child: Text(
                                  "Submit & Continue",
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Cancel button
                        SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                            onTap: () => Navigator.of(dialogCtx).pop(null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.slateBg,
                                borderRadius: AppRadius.borderPill,
                              ),
                              child: Center(
                                child: Text(
                                  "Cancel",
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Shows the checkout confirmation dialog with location verification status
  Future<bool?> _showCheckOutConfirmationDialog(CheckoutLocationVerification verification) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final screenWidth = MediaQuery.sizeOf(dialogCtx).width;
        final maxDialogWidth = screenWidth > 440 ? 380.0 : (screenWidth - 32.0).clamp(280.0, 380.0);

        // Determine icon and color based on verification status
        IconData statusIcon = CupertinoIcons.checkmark_circle_fill;
        Color statusColor = AppColors.statusSuccess;
        String statusLabel = verification.locationName;
        Color statusBgColor = AppColors.statusSuccessBg;

        switch (verification.status) {
          case CheckoutLocationStatus.assignedLocation:
            statusIcon = CupertinoIcons.checkmark_circle_fill;
            statusColor = AppColors.statusSuccess;
            statusLabel = verification.locationName;
            statusBgColor = AppColors.statusSuccessBg;
            break;
          case CheckoutLocationStatus.mainOffice:
            statusIcon = CupertinoIcons.building_2_fill;
            statusColor = AppColors.primary;
            statusLabel = 'Main Office - ${verification.locationName}';
            statusBgColor = AppColors.skyBg;
            break;
          case CheckoutLocationStatus.otherAuthorized:
            statusIcon = CupertinoIcons.location_fill;
            statusColor = AppColors.tealFg;
            statusLabel = verification.locationName;
            statusBgColor = AppColors.tealBg;
            break;
          case CheckoutLocationStatus.unauthorized:
            statusIcon = CupertinoIcons.exclamationmark_triangle_fill;
            statusColor = AppColors.lemonFg;
            statusLabel = 'Unknown Location';
            statusBgColor = AppColors.lemonBg;
            break;
          case CheckoutLocationStatus.gpsUnavailable:
            statusIcon = CupertinoIcons.location_slash;
            statusColor = AppColors.peachFg;
            statusLabel = 'GPS Unavailable';
            statusBgColor = AppColors.peachBg;
            break;
          default:
            break;
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxDialogWidth),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  borderRadius: AppRadius.borderLg,
                  boxShadow: AppShadows.softCard,
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Location status icon
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: statusBgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 26),
                    ),
                    AppSpacing.gapMD,
                    Text(
                      "Confirm Check-Out",
                      style: AppTypography.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    // Location verification badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusBgColor,
                        borderRadius: AppRadius.borderPill,
                      ),
                      child: Text(
                        statusLabel,
                        style: AppTypography.bodySmall.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (verification.reason != null && verification.reason!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Reason: ${verification.reason}",
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      "After checking out, you won\u2019t be able to check in again today.",
                      style: AppTypography.bodyRegular.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapLG,
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: () => Navigator.of(dialogCtx).pop(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: AppRadius.borderPill,
                            boxShadow: AppShadows.pillDark,
                          ),
                          child: Center(
                            child: Text(
                              "Confirm Check-Out",
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: () => Navigator.of(dialogCtx).pop(false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.slateBg,
                            borderRadius: AppRadius.borderPill,
                          ),
                          child: Center(
                            child: Text(
                              "Cancel",
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }


  bool _isRefreshingHome = false;

  Future<void> _handlePullToRefresh() async {
    if (_isRefreshingHome) return;
    _isRefreshingHome = true;
    try {
      await Future.wait([
        LocationService.instance.evaluateLiveLocation(),
        AttendanceService.instance.fetchTodayAttendance(),
        NotificationController.instance.refresh(),
        MoreModulesController.instance.loadAllData(),
        AttendanceDetailController.instance.refresh(),
        SupabaseEmployeeRepository().getCurrentEmployee(),
      ]);
    } catch (_) {
    } finally {
      _isRefreshingHome = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topSafeArea = MediaQuery.of(context).padding.top + 16;
    final locationResult = LocationService.instance.currentResult;
    final attendanceSession = AttendanceService.instance.session;
    final isCheckedIn = attendanceSession.isCheckedIn;

    return Stack(
      children: [
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 380,
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.emeraldAuraHeader,
              ),
            ),
          ),
          RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: Colors.white,
            edgeOffset: MediaQuery.paddingOf(context).top,
            displacement: 40,
            onRefresh: _handlePullToRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                topSafeArea,
                AppSpacing.screenHorizontal,
                AppSpacing.bottomNavClearance,
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _timeBasedGreeting,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentUser.firstName,
                            style: AppTypography.displayHeader,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (currentUser.companyName != null && currentUser.companyName!.isNotEmpty)
                                ? currentUser.companyName!
                                : "Organization",
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            "${currentUser.department.isNotEmpty && currentUser.department != 'N/A' ? (currentUser.unit?.isNotEmpty == true ? '${currentUser.department.trim()} / ${currentUser.unit!.trim()}' : currentUser.department.trim()) : (currentUser.designation.isNotEmpty ? currentUser.designation.trim() : 'Workforce')} · ${(locationResult.targetLocation?.name ?? (currentUser.approvedLocation.name.isNotEmpty && currentUser.approvedLocation.name != 'Work Location' ? currentUser.approvedLocation.name : (currentUser.campus.isNotEmpty && currentUser.campus != '—' ? currentUser.campus : 'Workplace')))}",
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListenableBuilder(
                        listenable: Listenable.merge([
                          NotificationController.instance,
                          LocalNotificationStore.instance,
                        ]),
                        builder: (context, _) {
                          final count = NotificationController.instance.unreadCount +
                              LocalNotificationStore.instance.unreadCount;
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(builder: (_) => const NotificationsScreen()),
                              );
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(
                                    CupertinoIcons.bell,
                                    size: 20,
                                    color: AppColors.textPrimary,
                                  ),
                                  if (count > 0)
                                    Positioned(
                                      top: 10,
                                      right: 11,
                                      child: Container(
                                        width: 9,
                                        height: 9,
                                        decoration: BoxDecoration(
                                          color: AppColors.statusError,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      AppSpacing.hGapMD,
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(builder: (_) => const ProfileScreen()),
                          );
                        },
                        child: WorkforceAvatar(
                          pathOrUrl: currentUser.profileImage,
                          fallbackInitials: _userInitials,
                          size: 44,
                          variant: AvatarVariant.small,
                          backgroundColor: AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              AppSpacing.gapLG,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                      // 1. Current Location Card (Live Automated Geofence Engine)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            if (locationResult.state == AttendanceGpsState.permissionDenied) {
                              final granted = await LocationService.instance.requestLocationPermission();
                              if (!granted && mounted) {
                                await LocationService.instance.openAppSettings();
                              }
                            } else if (locationResult.state == AttendanceGpsState.permissionPermanentlyDenied) {
                              LocationService.instance.openAppSettings();
                            } else if (locationResult.state == AttendanceGpsState.locationDisabled) {
                              LocationService.instance.openLocationSettings();
                            } else {
                              LocationService.instance.refreshLocationsAndEvaluate();
                            }
                          },
                          child: AppCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: locationResult.isInside
                                            ? AppColors.mintBg
                                            : (locationResult.state == AttendanceGpsState.locationDisabled ||
                                                    locationResult.state == AttendanceGpsState.permissionDenied ||
                                                    locationResult.state == AttendanceGpsState.permissionPermanentlyDenied
                                                ? AppColors.roseBg
                                                : (locationResult.state == AttendanceGpsState.scanning ||
                                                        locationResult.state == AttendanceGpsState.initializing
                                                    ? AppColors.skyBg
                                                    : AppColors.peachBg)),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        locationResult.state == AttendanceGpsState.locationDisabled ||
                                                locationResult.state == AttendanceGpsState.permissionDenied ||
                                                locationResult.state == AttendanceGpsState.permissionPermanentlyDenied
                                            ? CupertinoIcons.location_slash
                                            : (locationResult.state == AttendanceGpsState.scanning ||
                                                    locationResult.state == AttendanceGpsState.initializing
                                                ? CupertinoIcons.compass
                                                : CupertinoIcons.location_solid),
                                        size: 17,
                                        color: locationResult.isInside
                                            ? AppColors.mintFg
                                            : (locationResult.state == AttendanceGpsState.locationDisabled ||
                                                    locationResult.state == AttendanceGpsState.permissionDenied ||
                                                    locationResult.state == AttendanceGpsState.permissionPermanentlyDenied
                                                ? AppColors.roseFg
                                                : (locationResult.state == AttendanceGpsState.scanning ||
                                                        locationResult.state == AttendanceGpsState.initializing
                                                    ? AppColors.skyFg
                                                    : AppColors.peachFg)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                        decoration: BoxDecoration(
                                          color: locationResult.state == AttendanceGpsState.scanning ||
                                                  locationResult.state == AttendanceGpsState.initializing
                                              ? AppColors.skyBg
                                              : (locationResult.isInside
                                                  ? AppColors.mintBg
                                                  : (locationResult.state == AttendanceGpsState.locationDisabled ||
                                                          locationResult.state == AttendanceGpsState.permissionDenied ||
                                                          locationResult.state == AttendanceGpsState.permissionPermanentlyDenied
                                                      ? AppColors.roseBg
                                                      : AppColors.slateBg)),
                                          borderRadius: AppRadius.borderPill,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              locationResult.state == AttendanceGpsState.scanning ||
                                                      locationResult.state == AttendanceGpsState.initializing
                                                  ? CupertinoIcons.arrow_2_circlepath
                                                  : (locationResult.isInside
                                                      ? CupertinoIcons.checkmark_alt
                                                      : CupertinoIcons.location),
                                              size: 9.5,
                                              color: locationResult.state == AttendanceGpsState.scanning ||
                                                      locationResult.state == AttendanceGpsState.initializing
                                                  ? AppColors.skyFg
                                                  : (locationResult.isInside
                                                      ? AppColors.mintFg
                                                      : (locationResult.state == AttendanceGpsState.locationDisabled ||
                                                              locationResult.state == AttendanceGpsState.permissionDenied
                                                          ? AppColors.roseFg
                                                          : AppColors.textSecondary)),
                                            ),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                locationResult.state == AttendanceGpsState.scanning ||
                                                        locationResult.state == AttendanceGpsState.initializing
                                                    ? "GPS: Locating..."
                                                    : (locationResult.isInside
                                                        ? "In Range"
                                                        : (locationResult.state == AttendanceGpsState.locationDisabled
                                                            ? "GPS Off"
                                                            : (locationResult.state == AttendanceGpsState.permissionDenied
                                                                ? "Permission"
                                                                : "Out of Range"))),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                style: AppTypography.overline.copyWith(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: locationResult.state == AttendanceGpsState.scanning ||
                                                          locationResult.state == AttendanceGpsState.initializing
                                                      ? AppColors.skyFg
                                                      : (locationResult.isInside
                                                          ? AppColors.mintFg
                                                          : (locationResult.state == AttendanceGpsState.locationDisabled ||
                                                                  locationResult.state == AttendanceGpsState.permissionDenied
                                                              ? AppColors.roseFg
                                                              : AppColors.textSecondary)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                AppSpacing.gapSM,
                                Text(
                                  locationResult.targetLocation?.name ??
                                      (currentUser.approvedLocation.name.isNotEmpty
                                          ? currentUser.approvedLocation.name
                                          : (currentUser.campus.isNotEmpty
                                              ? currentUser.campus
                                              : (currentUser.assignedLocations.isNotEmpty
                                                  ? currentUser.assignedLocations.first.name
                                                  : 'No work location assigned'))),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                AppSpacing.gapXS,
                                locationResult.state == AttendanceGpsState.scanning ||
                                         locationResult.state == AttendanceGpsState.initializing ||
                                         (locationResult.latitude == 0.0 && locationResult.longitude == 0.0)
                                     ? const StatusChip(
                                         label: "Locating GPS...",
                                         type: StatusType.info,
                                         icon: CupertinoIcons.compass,
                                       )
                                     : locationResult.state == AttendanceGpsState.locationDisabled
                                         ? const StatusChip(
                                             label: "GPS Disabled (Turn on)",
                                             type: StatusType.warning,
                                             icon: CupertinoIcons.exclamationmark_triangle_fill,
                                           )
                                         : locationResult.state == AttendanceGpsState.permissionDenied
                                             ? const StatusChip(
                                                 label: "Permission Required (Tap)",
                                                 type: StatusType.warning,
                                                 icon: CupertinoIcons.location_slash,
                                               )
                                             : locationResult.state == AttendanceGpsState.permissionPermanentlyDenied
                                                 ? const StatusChip(
                                                     label: "Permission Denied (Settings)",
                                                     type: StatusType.error,
                                                     icon: CupertinoIcons.exclamationmark_circle_fill,
                                                   )
                                                 : locationResult.state == AttendanceGpsState.lowAccuracy
                                                     ? StatusChip(
                                                         label: "Low GPS (${locationResult.formattedAccuracy})",
                                                         type: StatusType.warning,
                                                         icon: CupertinoIcons.exclamationmark_triangle_fill,
                                                       )
                                                     : locationResult.targetLocation == null && currentUser.assignedLocations.isEmpty
                                                         ? const StatusChip(
                                                             label: "No Assigned Location",
                                                             type: StatusType.error,
                                                             icon: CupertinoIcons.slash_circle,
                                                           )
                                                         : locationResult.isInside
                                                             ? StatusChip(
                                                                 label: "Inside (${locationResult.formattedDistance})",
                                                                 type: StatusType.success,
                                                                 icon: CupertinoIcons.checkmark_circle_fill,
                                                               )
                                                             : StatusChip(
                                                                 label: "Outside (${locationResult.formattedDistance} away)",
                                                                 type: StatusType.warning,
                                                                 icon: CupertinoIcons.exclamationmark_triangle_fill,
                                                               ),
                                const SizedBox(height: 8),
                                 if (isCheckedIn) ...[
                                   Container(
                                     width: double.infinity,
                                     padding: const EdgeInsets.symmetric(vertical: 8),
                                     decoration: BoxDecoration(
                                       color: attendanceSession.isBiometricLocked ? const Color(0xFFEFF6FF) : AppColors.mintBg,
                                       borderRadius: AppRadius.borderPill,
                                     ),
                                     child: Center(
                                       child: Row(
                                         mainAxisSize: MainAxisSize.min,
                                         children: [
                                           Icon(
                                             attendanceSession.isBiometricLocked
                                                 ? CupertinoIcons.bolt_fill
                                                 : CupertinoIcons.checkmark_alt_circle_fill,
                                             size: 14,
                                             color: attendanceSession.isBiometricLocked ? const Color(0xFF2563EB) : AppColors.mintFg,
                                           ),
                                           const SizedBox(width: 4),
                                           Text(
                                             attendanceSession.isBiometricLocked
                                                 ? (attendanceSession.verificationMethod != null &&
                                                         attendanceSession.verificationMethod!.isNotEmpty &&
                                                         attendanceSession.verificationMethod!.toUpperCase() != 'BIOMETRIC'
                                                     ? "Biometric (${attendanceSession.verificationMethod})"
                                                     : "Biometric In")
                                                 : "Mobile In",
                                             style: AppTypography.caption.copyWith(
                                               fontWeight: FontWeight.w800,
                                               color: attendanceSession.isBiometricLocked ? const Color(0xFF2563EB) : AppColors.mintFg,
                                             ),
                                           ),
                                         ],
                                       ),
                                     ),
                                   ),
                                   ListenableBuilder(
                                     listenable: ShiftTrackingService.instance,
                                     builder: (context, _) {
                                       final tracking = ShiftTrackingService.instance;
                                       if (!tracking.isTracking) return const SizedBox.shrink();
                                       final km = (tracking.cumulativeDistanceMeters / 1000).toStringAsFixed(2);
                                       final isMoving = tracking.isMoving;
                                       return Padding(
                                         padding: const EdgeInsets.only(top: 6),
                                         child: Material(
                                           color: Colors.transparent,
                                           child: InkWell(
                                             borderRadius: BorderRadius.circular(12),
                                             onTap: () {
                                               Navigator.of(context).push(
                                                 MaterialPageRoute(
                                                   builder: (_) => const EmployeeLocationScreen(),
                                                 ),
                                               );
                                             },
                                             child: Container(
                                               width: double.infinity,
                                               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                               decoration: BoxDecoration(
                                                 color: const Color(0xFFF0FDF4),
                                                 borderRadius: BorderRadius.circular(12),
                                                 border: Border.all(color: const Color(0xFFBBF7D0)),
                                               ),
                                               child: Row(
                                                 mainAxisAlignment: MainAxisAlignment.center,
                                                 children: [
                                                   const Icon(CupertinoIcons.location_fill, size: 12, color: Color(0xFF15803D)),
                                                   const SizedBox(width: 5),
                                                   Flexible(
                                                     child: Text(
                                                       isMoving
                                                           ? "Shift GPS • ${km}km"
                                                           : "GPS Active • ${km}km",
                                                       maxLines: 1,
                                                       overflow: TextOverflow.ellipsis,
                                                       style: const TextStyle(
                                                         fontSize: 10.5,
                                                         fontWeight: FontWeight.w700,
                                                         color: Color(0xFF15803D),
                                                       ),
                                                     ),
                                                   ),
                                                   const SizedBox(width: 4),
                                                   const Icon(CupertinoIcons.chevron_right, size: 10, color: Color(0xFF15803D)),
                                                 ],
                                               ),
                                             ),
                                           ),
                                         ),
                                       );
                                     },
                                   ),
                                 ] else if (attendanceSession.status == AttendanceStatus.checkedOut)
                                   Container(
                                     width: double.infinity,
                                     padding: const EdgeInsets.symmetric(vertical: 8),
                                     decoration: BoxDecoration(
                                       color: AppColors.slateBg,
                                       borderRadius: AppRadius.borderPill,
                                     ),
                                     child: Center(
                                       child: Row(
                                         mainAxisSize: MainAxisSize.min,
                                         children: [
                                           const Icon(
                                             CupertinoIcons.checkmark_seal_fill,
                                             size: 14,
                                             color: AppColors.primary,
                                           ),
                                           const SizedBox(width: 4),
                                           Text(
                                             "Shift Completed",
                                             style: AppTypography.caption.copyWith(
                                               fontWeight: FontWeight.w800,
                                               color: AppColors.textPrimary,
                                             ),
                                           ),
                                         ],
                                       ),
                                     ),
                                   )
                                else if (locationResult.isInside)
                                  GestureDetector(
                                    onTap: AttendanceService.instance.isProcessing ? null : _handleCheckIn,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: AppRadius.borderPill,
                                        boxShadow: AppShadows.pillDark,
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (AttendanceService.instance.isProcessing) ...[
                                              const SizedBox(
                                                width: 13,
                                                height: 13,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ] else ...[
                                              const Icon(
                                                CupertinoIcons.checkmark_circle_fill,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 5),
                                            ],
                                            Text(
                                              AttendanceService.instance.isProcessing
                                                  ? "Checking In..."
                                                  : "Check In Now",
                                              style: AppTypography.caption.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () async {
                                          if (locationResult.state == AttendanceGpsState.locationDisabled) {
                                            LocationService.instance.openLocationSettings();
                                          } else if (locationResult.state == AttendanceGpsState.permissionDenied) {
                                            final granted = await LocationService.instance.requestLocationPermission();
                                            if (!granted && mounted) {
                                              await LocationService.instance.openAppSettings();
                                            }
                                          } else if (locationResult.state == AttendanceGpsState.permissionPermanentlyDenied) {
                                            LocationService.instance.openAppSettings();
                                          } else {
                                            LocationService.instance.refreshLocationsAndEvaluate();
                                          }
                                        },
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            color: AppColors.slateBg,
                                            borderRadius: AppRadius.borderPill,
                                          ),
                                          child: Center(
                                            child: Text(
                                              locationResult.state == AttendanceGpsState.locationDisabled
                                                  ? "Turn on GPS"
                                                  : (locationResult.state == AttendanceGpsState.permissionDenied
                                                      ? "Grant Permission"
                                                      : (locationResult.state == AttendanceGpsState.permissionPermanentlyDenied
                                                          ? "Open App Settings"
                                                          : (locationResult.state == AttendanceGpsState.scanning ||
                                                                  locationResult.state == AttendanceGpsState.initializing
                                                              ? "Acquiring GPS..."
                                                              : "Check In Disabled"))),
                                              style: AppTypography.caption.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: locationResult.state == AttendanceGpsState.locationDisabled ||
                                                        locationResult.state == AttendanceGpsState.permissionDenied
                                                    ? AppColors.primary
                                                    : AppColors.textMuted,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        locationResult.state == AttendanceGpsState.locationDisabled
                                            ? "Location service required"
                                            : (locationResult.state == AttendanceGpsState.permissionDenied ||
                                                    locationResult.state == AttendanceGpsState.permissionPermanentlyDenied
                                                ? "Location permission required"
                                                : (locationResult.state == AttendanceGpsState.scanning ||
                                                        locationResult.state == AttendanceGpsState.initializing
                                                    ? "Locating nearest facility..."
                                                    : (locationResult.targetLocation == null && currentUser.assignedLocations.isEmpty
                                                        ? "Contact HR to assign a location"
                                                        : "Move within ${locationResult.targetLocation?.allowedRadiusMeters.round() ?? 150}m of this location"))),
                                        style: AppTypography.overline.copyWith(
                                          color: AppColors.statusWarning,
                                          fontSize: 9.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      AppSpacing.hGapMD,

                      // 2. Today's Working Shift Card
                      Expanded(
                        child: AppCard(
                          variant: AppCardVariant.heroDark,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      isCheckedIn
                                          ? (attendanceSession.isBiometricLocked
                                              ? "Biometric Active"
                                              : "Working Today")
                                          : (AttendanceService.instance.session.isCheckedOut
                                              ? "Today's Work"
                                              : "Upcoming Shift"),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.caption.copyWith(
                                        color: isCheckedIn && attendanceSession.isBiometricLocked
                                            ? AppColors.primaryAccent
                                            : AppColors.textOnDarkMuted,
                                        fontWeight: isCheckedIn && attendanceSession.isBiometricLocked
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isCheckedIn
                                          ? AppColors.primaryAccent
                                          : (AttendanceService.instance.session.isCheckedOut
                                              ? const Color(0xFF60A5FA)
                                              : AppColors.textMuted),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                              AppSpacing.gapSM,
                              isCheckedIn
                                  ? const AttendanceLiveTimerWidget()
                                  : Text(
                                      AttendanceService.instance.session.isCheckedOut &&
                                              (AttendanceService.instance.session.netWorkingMinutes ?? 0) > 0
                                          ? "${(AttendanceService.instance.session.netWorkingMinutes! ~/ 60)}h ${(AttendanceService.instance.session.netWorkingMinutes! % 60)}m"
                                          : "00:00:00",
                                      style: AppTypography.metricLarge.copyWith(
                                        color: Colors.white,
                                        fontSize: 24,
                                      ),
                                    ),
                              AppSpacing.gapSM,
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: AppRadius.borderPill,
                                ),
                                child: Text(
                                  isCheckedIn
                                      ? "Shift ends at ${_getEffectiveShiftEnd(currentUser)}"
                                      : (AttendanceService.instance.session.isCheckedOut
                                          ? "Completed for today"
                                          : "Shift starts at ${_getEffectiveShiftStart(currentUser)}"),
                                  style: AppTypography.caption.copyWith(
                                    fontSize: 10.5,
                                    color: isCheckedIn
                                        ? AppColors.primaryAccent
                                        : AppColors.textOnDarkMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              AppSpacing.gapSM,
                              isCheckedIn
                                  ? GestureDetector(
                                      onTap: AttendanceService.instance.isProcessing ? null : _handleCheckOut,
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.mintBg,
                                          borderRadius: AppRadius.borderPill,
                                        ),
                                        child: Center(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (AttendanceService.instance.isProcessing) ...[
                                                const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: AppColors.mintFg,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                              ] else ...[
                                                const Icon(
                                                  CupertinoIcons.checkmark_alt_circle_fill,
                                                  size: 14,
                                                  color: AppColors.mintFg,
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                AttendanceService.instance.isProcessing
                                                    ? "Checking out..."
                                                    : "Check-out",
                                                style: AppTypography.caption.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.mintFg,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: AppRadius.borderPill,
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              CupertinoIcons.checkmark_alt_circle_fill,
                                              size: 14,
                                              color: Colors.white.withValues(alpha: 0.3),
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                AttendanceService.instance.session.isCheckedOut
                                                    ? "Checked Out"
                                                    : "Check-out",
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTypography.caption.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white.withValues(alpha: 0.3),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                if (!_isNotificationPermissionGranted && !kIsWeb) ...[
                  AppSpacing.gapLG,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(CupertinoIcons.bell_slash_fill, size: 16, color: Color(0xFFDC2626)),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Notifications Disabled",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Enable notifications to receive lock screen check-in alerts and approvals.",
                                style: TextStyle(fontSize: 10.5, color: Color(0xFF991B1B)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            final granted = await PushNotificationService.instance.requestNotificationPermission();
                            if (!granted && mounted) {
                              await PushNotificationService.instance.openNotificationSettings();
                            }
                            await _checkNotificationPermission();
                          },
                          child: const Text("Enable", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
                AppSpacing.gapXXL,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Quick Actions",
                      style: AppTypography.titleLarge,
                    ),
                    GestureDetector(
                      onTap: widget.onOpenServices,
                      child: Row(
                        children: [
                          Text(
                            "View All",
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            CupertinoIcons.chevron_right,
                            size: 12,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapMD,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: quickServices.map((tile) {
                    return Expanded(
                      child: Center(
                        child: AppletTileWidget(
                          tile: tile,
                          onTap: () {
                            switch (tile.id) {
                              case "regularize":
                                showRegularizationModal(context);
                                break;
                              case "apply_leave":
                                showApplyLeaveModal(context);
                                break;
                              case "payslip":
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(builder: (_) => const PayslipsScreen()),
                                );
                                break;
                              case "claims":
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(builder: (_) => const ExpenseClaimsScreen()),
                                );
                                break;
                              case "helpdesk":
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(builder: (_) => const HelpdeskScreen()),
                                );
                                break;
                              default:
                                widget.onOpenServices();
                            }
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
                AppSpacing.gapXXL,
                _buildCelebrationsSection(),
                AppSpacing.gapXXL,
                Text(
                  "Passes & Cards",
                  style: AppTypography.titleLarge,
                ),
                AppSpacing.gapMD,
                GestureDetector(
                  onTap: () => showVirtualIdCardDialog(context, currentUser),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: AppColors.darkCardGradient,
                      borderRadius: AppRadius.borderCard,
                      boxShadow: AppShadows.pillDark,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            StatusChip(
                              label: "Work Pass",
                              type: StatusType.info,
                              icon: CupertinoIcons.checkmark_seal_fill,
                            ),
                            Icon(
                              CupertinoIcons.radiowaves_right,
                              size: 20,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                        AppSpacing.gapLG,
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentUser.name,
                                    style: AppTypography.titleLarge.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  AppSpacing.gapXS,
                                  Text(
                                    "${currentUser.designation} · ${currentUser.department}",
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textOnDarkMuted,
                                    ),
                                  ),
                                  AppSpacing.gapXXS,
                                  Text(
                                    "ID: ${currentUser.employeeId.isNotEmpty ? currentUser.employeeId : '—'}",
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.primaryAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppSpacing.hGapMD,
                            WorkforceAvatar(
                              pathOrUrl: currentUser.profileImage,
                              fallbackInitials: _userInitials,
                              size: 56,
                              variant: AvatarVariant.medium,
                              backgroundColor: AppColors.primary,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCelebrationsSection() {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final celebrations = MoreModulesController.instance.celebrations;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSpacing.gapXXL,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text("Celebrations", style: AppTypography.titleLarge),
                    const SizedBox(width: 8),
                    const Text("🎉", style: TextStyle(fontSize: 18)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: celebrations.isNotEmpty ? AppColors.peachBg : AppColors.slateBg,
                    borderRadius: AppRadius.borderPill,
                  ),
                  child: Text(
                    celebrations.isNotEmpty ? "${celebrations.length} Upcoming" : "None this week",
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: celebrations.isNotEmpty ? AppColors.peachFg : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            AppSpacing.gapMD,
            if (celebrations.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.borderCard,
                  border: Border.all(color: AppColors.borderSubtle),
                  boxShadow: AppShadows.softCard,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: AppColors.mintBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(CupertinoIcons.sparkles, color: AppColors.mintFg, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "No celebrations this week",
                            style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Colleague birthdays and work anniversaries will appear here.",
                            style: AppTypography.caption.copyWith(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: celebrations.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final c = celebrations[index];
                  final isBday = c.type == CelebrationType.birthday;
                  final isToday = c.isToday;

                  return Container(
                    width: 255,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppRadius.borderCard,
                      border: Border.all(
                        color: isToday
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.borderSubtle,
                        width: isToday ? 1.5 : 1,
                      ),
                      boxShadow: AppShadows.softCard,
                    ),
                    child: Row(
                      children: [
                        WorkforceAvatar(
                          pathOrUrl: c.avatarUrl,
                          fallbackInitials: c.employeeName.isNotEmpty
                              ? (c.employeeName.length >= 2
                                  ? c.employeeName.substring(0, 2).toUpperCase()
                                  : c.employeeName.toUpperCase())
                              : "EM",
                          size: 46,
                          variant: AvatarVariant.small,
                          backgroundColor: isBday ? AppColors.peachBg : AppColors.mintBg,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isToday
                                      ? AppColors.primary
                                      : (isBday ? AppColors.peachBg : AppColors.mintBg),
                                  borderRadius: AppRadius.borderPill,
                                ),
                                child: Text(
                                  c.relativeLabel,
                                  style: AppTypography.caption.copyWith(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: isToday
                                        ? Colors.white
                                        : (isBday ? AppColors.peachFg : AppColors.mintFg),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c.employeeName,
                                style: AppTypography.bodySmall.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                c.celebrationTitle,
                                style: AppTypography.caption.copyWith(
                                  fontSize: 10.5,
                                  color: isBday ? const Color(0xFFD97706) : AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
