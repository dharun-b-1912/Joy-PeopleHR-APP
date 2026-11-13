import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/user_service.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../core/utils/secure_log.dart';
import '../services/face_attend_service.dart';
import '../utils/face_quality_analyzer.dart';
import '../widgets/face_capture_dial.dart';

class FaceEnrolmentScreen extends StatefulWidget {
  const FaceEnrolmentScreen({super.key});

  @override
  State<FaceEnrolmentScreen> createState() => _FaceEnrolmentScreenState();
}

class _FaceEnrolmentScreenState extends State<FaceEnrolmentScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _consentAccepted = false;
  String _selectedLang = 'en';
  bool _submitting = false;
  bool _testingMatch = false;
  bool _isGuidedScanning = false;
  bool _justCaptured = false;
  double _scanProgress = 0.0;
  String? _statusMsg;
  String? _qualityWarning;
  RealtimeChannel? _templateChannel;

  FaceCaptureAngle _activeAngle = FaceCaptureAngle.front;
  final Map<FaceCaptureAngle, Uint8List> _capturedAngles = {};

  static const List<FaceCaptureAngle> _angleOrder = [
    FaceCaptureAngle.front,
    FaceCaptureAngle.left,
    FaceCaptureAngle.right,
  ];

  static const Map<String, String> _consentText = {
    'en':
        'I voluntarily consent to capturing and storing my 1:1 facial template solely for attendance verification within my employer organization. My template is isolated in private encrypted storage and can be withdrawn and permanently deleted at any time.',
    'hi':
        'मैं केवल अपनी कंपनी की उपस्थिति सत्यापन के लिए 1:1 फेस टेम्पलेट कैप्चर करने और सुरक्षित रूप से संग्रहीत करने की सहमति देता/देती हूँ। मैं किसी भी समय अपनी सहमति वापस ले सकता/सकती हूँ।',
    'ta':
        'என் நிறுவனத்தில் வருகை பதிவைச் சரிபார்க்க மட்டுமே எனது முகத் தரவை பாதுகாப்பாகச் சேமிக்க சம்மதிக்கிறேன். எந்த நேரத்திலும் இந்தச் சம்மதத்தைத் திரும்பப் பெற்று தரவை நிரந்தரமாக அழிக்கலாம்.',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFrontCamera();
    FaceAttendService.instance.fetchTenantStatus();
    _subscribeTemplateRealtime();
  }

  void _subscribeTemplateRealtime() {
    final user = UserService.instance.currentUser;
    final orgId = user.organizationId ?? '';
    final empId = (user.employeeUuid?.isNotEmpty == true ? user.employeeUuid! : user.employeeId);
    if (orgId.isEmpty || empId.isEmpty) return;

    _templateChannel = Supabase.instance.client
        .channel('faceattend_emp_tpl_$empId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'faceattend_templates',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'employee_id',
            value: empId,
          ),
          callback: (_) {
            if (mounted) {
              FaceAttendService.instance.fetchTenantStatus();
            }
          },
        )
        .subscribe();
  }

  Future<void> _initFrontCamera() async {
    try {
      final perm = await Permission.camera.request();
      if (!perm.isGranted) {
        secureLog('[FaceEnrolment] Camera permission denied: $perm');
        if (mounted) setState(() => _cameraReady = false);
        return;
      }

      final cams = await availableCameras();
      if (cams.isEmpty) {
        secureLog('[FaceEnrolment] No cameras available');
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
      secureLog('[FaceEnrolment] Camera init error: $e');
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _cameraController;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (camera != null) {
        camera.dispose();
        _cameraController = null;
        if (mounted) setState(() => _cameraReady = false);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null && !_submitting) {
        _initFrontCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isGuidedScanning = false;
    _templateChannel?.unsubscribe();
    _cameraController?.dispose();
    super.dispose();
  }

  String _angleLabel(FaceCaptureAngle angle) {
    switch (angle) {
      case FaceCaptureAngle.front:
        return 'Front';
      case FaceCaptureAngle.left:
        return 'Left';
      case FaceCaptureAngle.right:
        return 'Right';
    }
  }

  String _angleInstruction(FaceCaptureAngle angle) {
    final step = _angleOrder.indexOf(angle) + 1;
    switch (angle) {
      case FaceCaptureAngle.front:
        return '$step/3 • Look Straight Inside Circle';
      case FaceCaptureAngle.left:
        return '$step/3 • Slowly Turn Head Left';
      case FaceCaptureAngle.right:
        return '$step/3 • Slowly Turn Head Right';
    }
  }

  Future<Uint8List?> _takeFrame() async {
    if (_cameraReady && _cameraController != null) {
      final shot = await _cameraController!.takePicture();
      return shot.readAsBytes();
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
    );
    return picked?.readAsBytes();
  }

  /// Auto-guided 3-angle scan: enlarges dial, animates green progress ring,
  /// captures Front -> Left -> Right automatically without needing button clicks
  /// while turning, and runs low-light / blur / glare checks on every frame.
  Future<void> _startGuidedScan({FaceCaptureAngle? singleRetakeAngle}) async {
    if (_submitting || _isGuidedScanning) return;

    setState(() {
      _isGuidedScanning = true;
      _qualityWarning = null;
      _statusMsg = null;
      if (singleRetakeAngle != null) {
        _activeAngle = singleRetakeAngle;
      } else {
        final next = _angleOrder.cast<FaceCaptureAngle?>().firstWhere(
              (a) => a != null && !_capturedAngles.containsKey(a),
              orElse: () => FaceCaptureAngle.front,
            );
        _activeAngle = next ?? FaceCaptureAngle.front;
      }
      _scanProgress = _capturedAngles.length / _angleOrder.length;
    });

    try {
      final anglesToCapture = singleRetakeAngle != null
          ? <FaceCaptureAngle>[singleRetakeAngle]
          : _angleOrder.where((a) => !_capturedAngles.containsKey(a)).toList();

      if (anglesToCapture.isEmpty) {
        _capturedAngles.clear();
        anglesToCapture.addAll(_angleOrder);
      }

      for (final angle in anglesToCapture) {
        if (!mounted || !_isGuidedScanning) return;

        setState(() {
          _activeAngle = angle;
          _justCaptured = false;
          _qualityWarning = null;
        });

        // Smoothly animate green progress across this step (~1.7s so user can turn head)
        const ticks = 10;
        final stepBase = _capturedAngles.length / _angleOrder.length;
        final stepSpan = 1.0 / _angleOrder.length;
        for (var t = 1; t <= ticks; t++) {
          await Future.delayed(const Duration(milliseconds: 165));
          if (!mounted || !_isGuidedScanning) return;
          setState(() {
            _scanProgress = (stepBase + stepSpan * (t / ticks) * 0.85).clamp(0.0, 1.0);
          });
        }

        final bytes = await _takeFrame();
        if (!mounted || !_isGuidedScanning) return;
        if (bytes == null || bytes.isEmpty) {
          setState(() {
            _isGuidedScanning = false;
            _statusMsg = 'Capture cancelled.';
          });
          return;
        }

        // Check lighting, glare, blur, and lens obstruction
        final quality = await FaceQualityAnalyzer.analyze(bytes);
        if (!mounted || !_isGuidedScanning) return;
        if (!quality.ok) {
          setState(() {
            _isGuidedScanning = false;
            _qualityWarning = quality.warningMessage;
            _scanProgress = _capturedAngles.length / _angleOrder.length;
          });
          return;
        }

        setState(() {
          _capturedAngles[angle] = bytes;
          _justCaptured = true;
          _scanProgress = _capturedAngles.length / _angleOrder.length;
        });

        await Future.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        setState(() => _justCaptured = false);
      }

      if (mounted) {
        setState(() {
          _isGuidedScanning = false;
          _scanProgress = _capturedAngles.length / _angleOrder.length;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGuidedScanning = false;
          _statusMsg = 'Camera capture error: $e';
        });
      }
    }
  }

  void _cancelGuidedScan() {
    setState(() {
      _isGuidedScanning = false;
      _justCaptured = false;
      _scanProgress = _capturedAngles.length / _angleOrder.length;
    });
  }

  Future<void> _submitEnrolment() async {
    final frontBytes = _capturedAngles[FaceCaptureAngle.front];
    if (frontBytes == null) {
      setState(() => _statusMsg = 'Please complete the 3-angle face scan first.');
      return;
    }
    if (!_consentAccepted) {
      setState(() => _statusMsg = 'Please review and accept the biometric consent notice first.');
      return;
    }

    setState(() {
      _submitting = true;
      _statusMsg = null;
    });

    try {
      final st = FaceAttendService.instance.status;
      final res = await FaceAttendService.instance.enrolFaceTemplate(
        imageBytes: frontBytes,
        leftImageBytes: _capturedAngles[FaceCaptureAngle.left],
        rightImageBytes: _capturedAngles[FaceCaptureAngle.right],
        consentVersion: st.consentVersionRequired,
        languageCode: _selectedLang,
      );

      if (!mounted) return;
      if (res['ok'] == true) {
        final tpl = res['template'] as Map?;
        final approvalState = tpl?['enrolment_status']?.toString() ?? 'PENDING_APPROVAL';
        final isActive = approvalState == 'ACTIVE';
        setState(() {
          _statusMsg = isActive
              ? '3-angle face template enrolled and active for FaceAttend.'
              : '3-angle face template submitted and awaiting HR approval.';
        });
        await _showAckDialog(
          title: isActive ? 'Face Enrolment Active' : 'Enrolment Submitted',
          icon: CupertinoIcons.checkmark_seal_fill,
          iconColor: const Color(0xFF16A34A),
          message: isActive
              ? 'Your 3-angle face template is verified and active for FaceAttend check-in/out.'
              : 'Your 3-angle face template has been securely saved and sent to HR for approval. This screen will update automatically once HR approves or revokes it.',
          badgeText: 'Status: $approvalState',
        );
      } else {
        setState(() => _statusMsg = 'Enrolment failed: ${res['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      if (mounted) setState(() => _statusMsg = 'Enrolment error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showAckDialog({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String message,
    required String badgeText,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 34),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: iconColor),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  String _nonEmpty(dynamic primary, String fallback) {
    final s = primary?.toString().trim() ?? '';
    return s.isNotEmpty ? s : fallback.trim();
  }

  String _formatNowTime() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Future<void> _testFaceMatchAgainstDatabase() async {
    if (_testingMatch || _isGuidedScanning || _submitting) return;
    setState(() {
      _testingMatch = true;
      _qualityWarning = null;
      _statusMsg = null;
    });

    try {
      final bytes = await _takeFrame();
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _testingMatch = false);
        return;
      }

      final quality = await FaceQualityAnalyzer.analyze(bytes);
      if (!mounted) return;
      if (!quality.ok) {
        setState(() {
          _testingMatch = false;
          _qualityWarning = quality.warningMessage;
        });
        return;
      }

      // Open live verification dialog immediately and transition in real time when server responds
      await _showLiveVerificationDialog(bytes);
      if (mounted) {
        setState(() => _testingMatch = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testingMatch = false;
          _statusMsg = 'Verification test error: $e';
        });
      }
    }
  }

  Future<void> _showLiveVerificationDialog(Uint8List frameBytes) async {
    if (!mounted) return;
    final sw = Stopwatch()..start();
    bool started = false;
    Map<String, dynamic>? result;
    String? errorMsg;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Live Face Verification',
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim, _) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (!started) {
              started = true;
              // Kick off verification once and tick the live timer every 100ms
              Future.microtask(() async {
                final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
                  if (ctx.mounted && result == null && errorMsg == null) {
                    setDialogState(() {});
                  }
                });
                try {
                  final res = await FaceAttendService.instance.testVerifyFaceMatch(frameBytes);
                  sw.stop();
                  ticker.cancel();
                  if (ctx.mounted) {
                    setDialogState(() => result = res);
                  }
                } catch (e) {
                  sw.stop();
                  ticker.cancel();
                  if (ctx.mounted) {
                    setDialogState(() => errorMsg = e.toString());
                  }
                }
              });
            }

            final isDone = result != null || errorMsg != null;
            final matched = result?['matched'] == true;
            final sim = result?['face_similarity'];
            final provider = result?['provider_code']?.toString() ?? 'COMPREFACE';
            final simLabel =
                sim != null ? '${(sim as num).toStringAsFixed(1)}% Match' : 'No Score';
            final latencyMs =
                (result?['latency_ms'] as num?)?.toInt() ?? sw.elapsedMilliseconds;
            final empMap = result?['employee'] is Map
                ? Map<String, dynamic>.from(result!['employee'] as Map)
                : null;
            final currentUser = UserService.instance.currentUser;
            final name = _nonEmpty(empMap?['name'], currentUser.name);
            final employeeCode =
                _nonEmpty(empMap?['employee_code'], currentUser.employeeId);
            final department =
                _nonEmpty(empMap?['department'], currentUser.department);
            final organizationName =
                _nonEmpty(empMap?['organization_name'], '');
            final message = errorMsg ??
                result?['message']?.toString() ??
                'Identity verified against database.';

            return Center(
              child: Material(
                color: Colors.transparent,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: !isDone
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 58,
                                height: 58,
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Verifying Face in Real Time...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Comparing live capture with CompreFace 1:1 template',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: const Color(0xFFBBF7D0)),
                                ),
                                child: Text(
                                  'LIVE SCAN • ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF15803D),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.4, end: 1.0),
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.elasticOut,
                                builder: (_, scale, child) =>
                                    Transform.scale(scale: scale, child: child),
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: (matched
                                            ? const Color(0xFF16A34A)
                                            : Colors.redAccent)
                                        .withValues(alpha: 0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    matched
                                        ? CupertinoIcons.checkmark_seal_fill
                                        : CupertinoIcons.xmark_shield_fill,
                                    color: matched
                                        ? const Color(0xFF16A34A)
                                        : Colors.redAccent,
                                    size: 40,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                matched ? 'Identity Verified' : 'Face Did Not Match',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: matched
                                          ? const Color(0xFFECFDF5)
                                          : const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: matched
                                            ? const Color(0xFF86EFAC)
                                            : const Color(0xFFFECACA),
                                      ),
                                    ),
                                    child: Text(
                                      '$simLabel • $provider',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: matched
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'LIVE • ${latencyMs}ms • ${_formatNowTime()}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (matched) ...[
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    children: [
                                      _identityRow('Employee Name', name),
                                      const Divider(height: 14),
                                      _identityRow(
                                        'Employee Code',
                                        employeeCode.isNotEmpty ? employeeCode : '—',
                                      ),
                                      const Divider(height: 14),
                                      _identityRow(
                                        'Department',
                                        department.isNotEmpty ? department : 'General',
                                      ),
                                      if (organizationName.isNotEmpty) ...[
                                        const Divider(height: 14),
                                        _identityRow('Organization', organizationName),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: matched
                                        ? const Color(0xFF16A34A)
                                        : Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Done',
                                    style: TextStyle(fontWeight: FontWeight.w700),
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
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.88, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _identityRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }

  Future<void> _withdrawAndErase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Erase Biometric Data?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'This will permanently delete your stored 3-angle face photos and withdraw your biometric consent. You can re-enrol anytime.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Confirm & Erase'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    final ok = await FaceAttendService.instance
        .withdrawConsentAndDeleteBiometrics('Employee requested deletion from mobile app');
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _consentAccepted = false;
      _capturedAngles.clear();
      _activeAngle = FaceCaptureAngle.front;
      _scanProgress = 0.0;
      _qualityWarning = null;
      _statusMsg = ok
          ? 'Consent withdrawn and face template permanently erased.'
          : 'Could not erase biometric data. Please retry.';
    });
    if (ok) {
      await _showAckDialog(
        title: 'Face Data Permanently Erased',
        icon: CupertinoIcons.trash_fill,
        iconColor: Colors.redAccent,
        message: 'Your biometric consent has been withdrawn and all stored face photos have been deleted.',
        badgeText: 'Status: DELETED',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FaceAttendService.instance,
      builder: (context, _) {
        final st = FaceAttendService.instance.status;
        final capturedCount = _capturedAngles.length;
        final allCaptured = capturedCount == _angleOrder.length;
        final dialColor = (_isGuidedScanning || _testingMatch || allCaptured)
            ? const Color(0xFF16A34A)
            : const Color(0xFF0284C7);

        return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('JOY FaceAttend Enrolment & Privacy'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.borderMd,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Status', style: AppTypography.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Template: ${st.templateStatus ?? "Not Enrolled"}  •  Consent: ${st.hasActiveConsent ? "Granted (${st.consentVersionRequired})" : "Not Granted"}  •  Retention: ${st.retentionDays} days',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Centered Round Portrait Capture Dial (enlarges & turns green during guided scan)
          Center(
            child: FaceCaptureDial(
              cameraController: _cameraController,
              cameraReady: _cameraReady,
              progress: _testingMatch
                  ? 1.0
                  : _isGuidedScanning
                      ? _scanProgress
                      : (capturedCount / _angleOrder.length),
              ringColor: dialColor,
              angle: _activeAngle,
              isScanning: _isGuidedScanning || _testingMatch,
              justCaptured: _justCaptured,
              warningMessage: _qualityWarning,
              instruction: _testingMatch
                  ? 'Verifying Your Face Identity...'
                  : allCaptured && !_isGuidedScanning
                      ? 'All 3 Angles Verified • Ready to Submit'
                      : _angleInstruction(_activeAngle),
            ),
          ),
          const SizedBox(height: 16),

          // 3-Angle Progress Chips (Front / Left / Right — tap any to retake)
          Row(
            children: _angleOrder.map((angle) {
              final bytes = _capturedAngles[angle];
              final isSelected = _activeAngle == angle;
              final isDone = bytes != null;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: AppRadius.borderMd,
                    onTap: (_submitting || _isGuidedScanning)
                        ? null
                        : () => _startGuidedScan(singleRetakeAngle: angle),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFFECFDF5)
                            : isSelected
                                ? const Color(0xFFF0FDF4)
                                : Colors.white,
                        borderRadius: AppRadius.borderMd,
                        border: Border.all(
                          color: isSelected
                              ? dialColor
                              : isDone
                                  ? const Color(0xFF86EFAC)
                                  : Colors.grey.shade300,
                          width: isSelected ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (bytes != null)
                            ClipOval(
                              child: Image.memory(bytes, width: 22, height: 22, fit: BoxFit.cover),
                            )
                          else
                            Icon(
                              CupertinoIcons.circle,
                              size: 16,
                              color: isSelected ? dialColor : Colors.grey.shade400,
                            ),
                          const SizedBox(width: 6),
                          Text(
                            _angleLabel(angle),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDone ? const Color(0xFF15803D) : AppColors.textPrimary,
                            ),
                          ),
                          if (isDone) ...[
                            const SizedBox(width: 4),
                            const Icon(CupertinoIcons.checkmark_alt, size: 13, color: Color(0xFF16A34A)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Guided Auto-Scan Button (no manual clicking while turning Left/Right)
          if (_isGuidedScanning)
            OutlinedButton.icon(
              onPressed: _cancelGuidedScan,
              icon: const Icon(CupertinoIcons.xmark_circle, size: 18, color: Colors.redAccent),
              label: Text(
                'Scanning ${_angleLabel(_activeAngle)}... (Tap to Cancel)',
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _submitting ? null : () => _startGuidedScan(),
              icon: Icon(
                allCaptured ? CupertinoIcons.refresh : CupertinoIcons.viewfinder,
                size: 18,
              ),
              label: Text(
                allCaptured
                    ? 'Rescan All 3 Angles'
                    : capturedCount == 0
                        ? 'Start Guided 3-Angle Scan (Hands-Free)'
                        : 'Resume Scan ($capturedCount/3 Done)',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF16A34A),
                side: const BorderSide(color: Color(0xFF16A34A), width: 1.4),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          const SizedBox(height: 16),

          // Multilingual Consent Card
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Explicit Consent (${st.consentVersionRequired})',
                          style: AppTypography.titleMedium),
                      DropdownButton<String>(
                        value: _selectedLang,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'en', child: Text('English')),
                          DropdownMenuItem(value: 'hi', child: Text('हिन्दी')),
                          DropdownMenuItem(value: 'ta', child: Text('தமிழ்')),
                        ],
                        onChanged: (v) => setState(() => _selectedLang = v ?? 'en'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _consentText[_selectedLang] ?? _consentText['en']!,
                    style: AppTypography.bodySmall.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _consentAccepted,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _consentAccepted = v ?? false),
                    title: const Text(
                      'I agree to 1:1 biometric attendance verification.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_statusMsg != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: AppRadius.borderMd,
              ),
              child: Text(_statusMsg!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],

          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_submitting || _isGuidedScanning || !allCaptured) ? null : _submitEnrolment,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(CupertinoIcons.checkmark_shield_fill),
            label: Text(
              _submitting
                  ? 'Uploading Optimized 3-Angle Template...'
                  : allCaptured
                      ? 'Submit 3-Angle Face Enrolment'
                      : 'Complete 3-Angle Scan to Enrol ($capturedCount/3)',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

          if (st.templateStatus == 'ACTIVE') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (_testingMatch || _isGuidedScanning || _submitting)
                  ? null
                  : _testFaceMatchAgainstDatabase,
              icon: _testingMatch
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.person_crop_circle_badge_checkmark,
                      color: Color(0xFF0284C7)),
              label: Text(
                _testingMatch
                    ? 'Verifying Your Face...'
                    : 'Verify Your Face',
                style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0284C7), width: 1.3),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ],

          if (st.hasActiveConsent || st.templateStatus != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _withdrawAndErase,
              icon: const Icon(CupertinoIcons.trash, color: Colors.redAccent),
              label: const Text(
                'Withdraw Consent & Permanently Erase My Face Data',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
      },
    );
  }
}
