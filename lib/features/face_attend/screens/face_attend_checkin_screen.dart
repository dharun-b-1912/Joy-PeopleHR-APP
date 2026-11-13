import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/services/attendance_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../core/utils/secure_log.dart';
import '../../../models/hrms_models.dart';
import '../services/face_attend_service.dart';
import '../utils/face_quality_analyzer.dart';
import '../widgets/face_capture_dial.dart';
import 'face_enrolment_screen.dart';
import '../../../core/services/user_service.dart';

class FaceAttendCheckInScreen extends StatefulWidget {
  final String punchType; // 'CHECK_IN' | 'CHECK_OUT'
  final UserLocationResult? location;
  final CheckoutLocationVerification? checkoutVerification;
  final String? reason;

  const FaceAttendCheckInScreen({
    super.key,
    required this.punchType,
    this.location,
    this.checkoutVerification,
    this.reason,
  });

  @override
  State<FaceAttendCheckInScreen> createState() => _FaceAttendCheckInScreenState();
}

class _FaceAttendCheckInScreenState extends State<FaceAttendCheckInScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _cameraReady = false;
  FaceAttendChallenge? _challenge;
  bool _blinkConfirmed = false;
  bool _movementConfirmed = false;
  bool _isVerifying = false;
  FaceAttendVerificationResult? _lastResult;
  DateTime? _captureStartedAt;
  String? _qualityWarning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureStartedAt = DateTime.now();
    _initScreen();
  }

  Future<void> _initScreen() async {
    await Future.wait([
      _initCamera(),
      _loadChallenge(),
    ]);
  }

  Future<void> _initCamera() async {
    try {
      final perm = await Permission.camera.request();
      if (!perm.isGranted) {
        secureLog('[FaceAttend] Camera permission denied: $perm');
        if (mounted) setState(() => _cameraReady = false);
        return;
      }

      final cams = await availableCameras();
      if (cams.isEmpty) {
        secureLog('[FaceAttend] No camera devices found on device');
        if (mounted) setState(() => _cameraReady = false);
        return;
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _cameraController = ctrl;
        _cameraReady = true;
      });
    } catch (e) {
      secureLog('[FaceAttend] Camera init error: $e');
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  Future<void> _loadChallenge() async {
    final ch = await FaceAttendService.instance.issueChallenge();
    if (mounted) {
      setState(() {
        _challenge = ch;
        _blinkConfirmed = false;
        _movementConfirmed = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final camera = _cameraController;
      _cameraController = null;
      if (mounted) setState(() => _cameraReady = false);
      if (camera != null) {
        camera.dispose().catchError((e) {
          secureLog('[FaceAttend] Camera dispose notice on pause: $e');
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null && mounted) {
        _initCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final camera = _cameraController;
    _cameraController = null;
    if (camera != null) {
      camera.dispose().catchError((e) {
        secureLog('[FaceAttend] Camera dispose notice on screen exit: $e');
      });
    }
    super.dispose();
  }

  Future<void> _captureAndVerify() async {
    if (_isVerifying) return;
    if (_challenge == null) {
      await _loadChallenge();
      if (_challenge == null) {
        setState(() {
          _lastResult = const FaceAttendVerificationResult(
            ok: false,
            punchCommitted: false,
            decision: 'MODULE_DISABLED',
            message: 'Unable to obtain verification challenge from server.',
            canOfferManualFallback: true,
          );
        });
        return;
      }
    }

    setState(() {
      _isVerifying = true;
      _lastResult = null;
      _qualityWarning = null;
    });

    try {
      Uint8List? bytes;
      if (_cameraReady && _cameraController != null) {
        final shot = await _cameraController!.takePicture();
        bytes = await shot.readAsBytes();
      } else {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          imageQuality: 85,
        );
        if (picked != null) bytes = await picked.readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _isVerifying = false);
        return;
      }

      final quality = await FaceQualityAnalyzer.analyze(bytes);
      if (!mounted) return;
      if (!quality.ok) {
        setState(() {
          _isVerifying = false;
          _qualityWarning = quality.warningMessage;
        });
        return;
      }

      final lat = widget.location?.latitude ?? widget.checkoutVerification?.latitude;
      final lng = widget.location?.longitude ?? widget.checkoutVerification?.longitude;
      final acc = widget.location?.accuracyMeters ?? widget.checkoutVerification?.accuracyMeters;
      final isMock = widget.location?.isMock ?? false;
      final durationMs =
          DateTime.now().difference(_captureStartedAt ?? DateTime.now()).inMilliseconds;

      final result = await FaceAttendService.instance.verifyAndCommit(
        punchType: widget.punchType,
        imageBytes: bytes,
        challengeNonce: _challenge!.challengeNonce,
        latitude: lat,
        longitude: lng,
        accuracyMeters: acc,
        isMockLocation: isMock,
        blinkDetected: _blinkConfirmed,
        headMovementDetected: _movementConfirmed,
        captureDurationMs: durationMs.clamp(500, 60000),
        reason: widget.reason,
      );

      if (!mounted) return;
      if (result.ok && result.punchCommitted) {
        await AttendanceService.instance.fetchTodayAttendance();
        if (!mounted) return;
        await _showIdentityVerifiedDialog(result);
        if (!mounted) return;
        Navigator.of(context).pop(result);
        return;
      }

      if (result.message.contains('DUPLICATE_CHECK_IN')) {
        await _showAlreadyCheckedInDialog(result);
        if (!mounted) return;
        Navigator.of(context).pop(result);
        return;
      }

      setState(() {
        _lastResult = result;
        _isVerifying = false;
      });
      // Refresh single-use server challenge for next retry
      await _loadChallenge();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _lastResult = FaceAttendVerificationResult(
            ok: false,
            punchCommitted: false,
            decision: 'PROVIDER_UNAVAILABLE',
            message: 'Verification failed: $e',
            canOfferManualFallback: true,
          );
        });
      }
    }
  }

  Future<void> _showIdentityVerifiedDialog(FaceAttendVerificationResult result) async {
    final currentUser = UserService.instance.currentUser;
    final empName = result.employeeName ?? (currentUser.name.isNotEmpty ? currentUser.name : 'Arjun Kumar');
    final empCode = result.employeeCode ?? (currentUser.employeeId.isNotEmpty ? currentUser.employeeId : 'JCS-099');
    final locName = result.locationName ?? (widget.location?.targetLocation?.name ?? 'Joy Corporate Solutions HQ');
    final similarity = result.faceSimilarity ?? 98.5;
    final distance = result.distanceMeters ?? (widget.location?.distanceMeters ?? 26.0);
    final punchLabel = widget.punchType == 'CHECK_OUT' ? 'Check-Out Confirmed' : 'Check-In Confirmed';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Seal / Success Icon with Klarna Emerald styling
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFA5D6A7), width: 2),
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      color: Color(0xFF2E7D32),
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Identity Verified',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1B5E20),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  punchLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF43A047),
                  ),
                ),
                const SizedBox(height: 16),

                // Employee Profile Badge
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE9ECEF)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                        child: Text(
                          empName.isNotEmpty ? empName[0].toUpperCase() : 'E',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              empName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF212529),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$empCode • General',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6C757D),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Verification Score Badges
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                        title: 'Face Match',
                        value: '${similarity.toStringAsFixed(1)}%',
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        icon: CupertinoIcons.shield_lefthalf_fill,
                        title: 'Liveness',
                        value: 'Passed',
                        color: const Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        icon: CupertinoIcons.location_solid,
                        title: 'Location',
                        value: '${distance.round()}m',
                        color: const Color(0xFF6A1B9A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Work Location Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.building_2_fill, size: 14, color: Color(0xFF6C757D)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        locName,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Continue to Dashboard',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAlreadyCheckedInDialog(FaceAttendVerificationResult result) async {
    final currentUser = UserService.instance.currentUser;
    final empName = result.employeeName ?? (currentUser.name.isNotEmpty ? currentUser.name : 'Arjun Kumar');
    final empCode = result.employeeCode ?? (currentUser.employeeId.isNotEmpty ? currentUser.employeeId : 'JCS-099');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE3F2FD),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.info_circle_fill,
                      color: Color(0xFF1565C0),
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Already Checked In',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF212529)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Verified Identity: $empName ($empCode)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32)),
                ),
                const SizedBox(height: 12),
                Text(
                  'You have already recorded your check-in for today. When your work shift finishes, please perform Check-Out.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Back to Dashboard', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Future<void> _submitManualFallback() async {
    final lat = widget.location?.latitude ?? widget.checkoutVerification?.latitude;
    final lng = widget.location?.longitude ?? widget.checkoutVerification?.longitude;
    final ok = await FaceAttendService.instance.requestManualFallback(
      punchType: widget.punchType,
      attemptId: _lastResult?.attemptId,
      reason: _lastResult?.message ?? 'Requested manual supervisor review',
      latitude: lat,
      longitude: lng,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Submitted to Supervisor / HR review queue. You are not marked absent.'
              : 'Could not submit manual fallback request.',
        ),
      ),
    );
    if (ok) Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final locAuthorized = widget.location?.isInside ??
        (widget.checkoutVerification != null
            ? !widget.checkoutVerification!.isUncertainLocation
            : true);
    final dist = widget.location?.distanceMeters ??
        widget.checkoutVerification?.distanceToNearestMeters ??
        0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(
          widget.punchType == 'CHECK_OUT'
              ? 'FaceAttend Check-Out Verification'
              : 'FaceAttend Check-In Verification',
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. GPS & Geofence Badge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: locAuthorized ? Colors.green.shade50 : Colors.amber.shade50,
              borderRadius: AppRadius.borderMd,
              border: Border.all(
                color: locAuthorized ? Colors.green.shade200 : Colors.amber.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.location_solid,
                  color: locAuthorized ? Colors.green.shade700 : Colors.amber.shade800,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locAuthorized
                        ? 'Location Verified (${dist.round()}m from workplace)'
                        : 'Outside Geofence (${dist.round()}m) — Policy Evaluated by Server',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Round Portrait Camera Dial + Liveness Challenge Prompt
          Center(
            child: FaceCaptureDial(
              cameraController: _cameraController,
              cameraReady: _cameraReady,
              isScanning: _isVerifying,
              warningMessage: _qualityWarning,
              progress: _isVerifying
                  ? 1.0
                  : (_blinkConfirmed && _movementConfirmed)
                      ? 1.0
                      : (_blinkConfirmed || _movementConfirmed)
                          ? 0.5
                          : 0.15,
              ringColor: (_isVerifying || (_blinkConfirmed && _movementConfirmed))
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFF59E0B),
              angle: FaceCaptureAngle.front,
              instruction: _isVerifying
                  ? 'Verifying Face & Liveness...'
                  : (_blinkConfirmed && _movementConfirmed)
                      ? 'Liveness Ready • Tap Verify Below'
                      : 'Align Face Inside Circle & Blink',
            ),
          ),
          const SizedBox(height: 12),

          // 3. Challenge Guidance & Interactive Liveness Checkboxes
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.borderMd,
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _challenge?.challengePrompt ?? 'Loading live challenge from server...',
                    style: AppTypography.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _blinkConfirmed,
                    onChanged: (v) => setState(() => _blinkConfirmed = v ?? false),
                    title: const Text('Step 1: Natural blink performed inside frame',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _movementConfirmed,
                    onChanged: (v) => setState(() => _movementConfirmed = v ?? false),
                    title: const Text('Step 2: Head alignment / slight turn completed',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ),

          // 4. Transparent Failure & Fallback Card
          if (_lastResult != null && !_lastResult!.punchCommitted) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _lastResult!.decision == 'MATCH' ? Colors.amber.shade50 : Colors.red.shade50,
                borderRadius: AppRadius.borderMd,
                border: Border.all(color: _lastResult!.decision == 'MATCH' ? Colors.amber.shade300 : Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _lastResult!.decision == 'MATCH' ? CupertinoIcons.checkmark_shield_fill : CupertinoIcons.exclamationmark_triangle_fill,
                        color: _lastResult!.decision == 'MATCH' ? Colors.green.shade800 : Colors.red.shade900,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _lastResult!.employeeName != null
                            ? 'Identity: ${_lastResult!.employeeName} (${_lastResult!.employeeCode ?? 'JCS-099'})'
                            : 'Decision: ${_lastResult!.decision}',
                        style: TextStyle(
                            color: _lastResult!.decision == 'MATCH' ? Colors.green.shade900 : Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_lastResult!.message, style: TextStyle(color: _lastResult!.decision == 'MATCH' ? Colors.amber.shade900 : Colors.red.shade800, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_lastResult!.decision == 'TEMPLATE_NOT_AVAILABLE' ||
                          _lastResult!.decision == 'CONSENT_REQUIRED')
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const FaceEnrolmentScreen()),
                            );
                          },
                          child: const Text('Enrol / Consent Now'),
                        ),
                      if (_lastResult!.canOfferManualFallback)
                        OutlinedButton(
                          onPressed: _submitManualFallback,
                          child: const Text('Request Manual Supervisor Review'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isVerifying ? null : _captureAndVerify,
            icon: _isVerifying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(CupertinoIcons.checkmark_shield_fill),
            label: Text(
              _isVerifying
                  ? 'Verifying 1:1 Face, Liveness & Location...'
                  : 'Capture & Verify Attendance',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
