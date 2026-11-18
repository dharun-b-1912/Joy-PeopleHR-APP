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
        if (mounted) {
          Navigator.of(context).pop(isActive);
        }
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
        if (!st.employeeFaceEnabled) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
              title: const Text('Face Attendance Exemption'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFCD34D), width: 2),
                      ),
                      child: const Icon(CupertinoIcons.camera_fill, color: Color(0xFFB45309), size: 38),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Exempted from Camera Attendance',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'HR has exempted your account from mobile face scanning.\n\nReason: ${st.employeeExemptionReason ?? "Camera damaged / broken or standard clock-in authorized"}.\n\nYou do not need to enrol your face. You can perform standard one-tap location-verified check-in on the Home screen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Back to Home'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final capturedCount = _capturedAngles.length;
        final allCaptured = capturedCount == _angleOrder.length;
        final dialColor = (_isGuidedScanning || _testingMatch || allCaptured)
            ? const Color(0xFF16A34A)
            : const Color(0xFF0284C7);

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FaceID Enrolment',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                Text(
                  '3-Angle 192-D Biometric Registration',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: Colors.grey.shade200, height: 1),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            children: [
              // 1. Sleek Status & Telemetry Header Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: st.templateStatus == 'ACTIVE'
                        ? [const Color(0xFFECFDF5), const Color(0xFFDCFCE7)]
                        : [Colors.white, const Color(0xFFF8FAFC)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: st.templateStatus == 'ACTIVE'
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: st.templateStatus == 'ACTIVE'
                            ? const Color(0xFF10B981)
                            : const Color(0xFF0F172A),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        st.templateStatus == 'ACTIVE'
                            ? CupertinoIcons.checkmark_seal_fill
                            : CupertinoIcons.person_crop_circle_badge_plus,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            st.templateStatus == 'ACTIVE'
                                ? 'Face Profile Active'
                                : (st.templateStatus == 'PENDING_APPROVAL'
                                    ? 'Awaiting HR Approval'
                                    : '3-Angle Setup Required'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'DPDP Compliant • Stored on isolated private cloud • ${st.retentionDays}d retention',
                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: st.templateStatus == 'ACTIVE'
                            ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        st.templateStatus ?? 'UNENROLLED',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: st.templateStatus == 'ACTIVE'
                              ? const Color(0xFF16A34A)
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. High-Tech Camera Viewport Card
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
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
              ),
              const SizedBox(height: 14),

              // 3. Apple FaceID Style 3-Angle Cards Gallery
              Row(
                children: _angleOrder.map((angle) {
                  final bytes = _capturedAngles[angle];
                  final isSelected = _activeAngle == angle;
                  final isDone = bytes != null;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: (_submitting || _isGuidedScanning)
                            ? null
                            : () => _startGuidedScan(singleRetakeAngle: angle),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isDone
                                ? const Color(0xFFF0FDF4)
                                : isSelected
                                    ? const Color(0xFFEFF6FF)
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF2563EB)
                                  : isDone
                                      ? const Color(0xFF86EFAC)
                                      : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.8 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (bytes != null)
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF16A34A), width: 1.5),
                                  ),
                                  child: ClipOval(
                                    child: Image.memory(bytes, fit: BoxFit.cover),
                                  ),
                                )
                              else
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _angleIcon(angle),
                                    size: 20,
                                    color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade500,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                _angleLabel(angle),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDone
                                      ? const Color(0xFF15803D)
                                      : isSelected
                                          ? const Color(0xFF1D4ED8)
                                          : const Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isDone ? 'Captured' : (isSelected ? 'Scanning' : 'Pending'),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDone ? const Color(0xFF16A34A) : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // 4. Guided Hands-Free Scan Action Button
              if (_isGuidedScanning)
                OutlinedButton.icon(
                  onPressed: _cancelGuidedScan,
                  icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: Colors.redAccent),
                  label: Text(
                    'Scanning ${_angleLabel(_activeAngle)}... Tap to Cancel',
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _submitting ? null : () => _startGuidedScan(),
                  icon: Icon(
                    allCaptured ? CupertinoIcons.refresh_thick : CupertinoIcons.viewfinder,
                    size: 18,
                  ),
                  label: Text(
                    allCaptured
                        ? 'Rescan 3-Angle Profile'
                        : capturedCount == 0
                            ? 'Start Hands-Free 3-Angle Scan'
                            : 'Resume 3-Angle Scan ($capturedCount/3 Done)',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              const SizedBox(height: 16),

              // 5. Modern Language Chips & Multilingual Biometric Consent Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.shield_lefthalf_fill, color: Color(0xFF07563D), size: 17),
                        const SizedBox(width: 8),
                        Text(
                          'Privacy Notice (${st.consentVersionRequired})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Wrap(
                          spacing: 6,
                          children: [
                            _buildLanguageChip(code: 'en', label: 'EN', flag: '🇬🇧'),
                            _buildLanguageChip(code: 'hi', label: 'हिन्दी', flag: '🇮🇳'),
                            _buildLanguageChip(code: 'ta', label: 'தமிழ்', flag: '🇮🇳'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Text(
                        _consentText[_selectedLang] ?? _consentText['en']!,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildConsentToggleCard(st),
                  ],
                ),
              ),

              if (_statusMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    _statusMsg!,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: (_submitting || _isGuidedScanning || !allCaptured || !_consentAccepted)
                    ? null
                    : _submitEnrolment,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(CupertinoIcons.checkmark_shield_fill),
                label: Text(
                  _submitting
                      ? 'Uploading Encrypted Biometric Template...'
                      : allCaptured
                          ? (_consentAccepted ? 'Submit & Activate Face Profile' : 'Accept Consent to Continue')
                          : 'Complete All 3 Angles ($capturedCount/3)',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),

              if (st.templateStatus == 'ACTIVE') ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: (_testingMatch || _isGuidedScanning || _submitting)
                      ? null
                      : _testFaceMatchAgainstDatabase,
                  icon: _testingMatch
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.checkmark_seal_fill, color: Color(0xFF16A34A), size: 16),
                  label: Text(
                    _testingMatch ? 'Verifying 1:1 Match...' : 'Test Facial Match Against Database',
                    style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF16A34A), width: 1.3),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],

              if (st.hasActiveConsent || st.templateStatus != null) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _submitting ? null : _withdrawAndErase,
                  icon: const Icon(CupertinoIcons.trash, color: Colors.redAccent, size: 15),
                  label: const Text(
                    'Withdraw Consent & Erase Face Data',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLanguageChip({
    required String code,
    required String label,
    required String flag,
  }) {
    final isSelected = _selectedLang == code;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _selectedLang = code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsentToggleCard(FaceAttendStatus st) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _consentAccepted = !_consentAccepted),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _consentAccepted ? const Color(0xFFF0FDF4) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _consentAccepted ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
            width: _consentAccepted ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _consentAccepted ? const Color(0xFF16A34A) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _consentAccepted ? const Color(0xFF16A34A) : Colors.grey.shade400,
                  width: 1.8,
                ),
              ),
              child: _consentAccepted
                  ? const Icon(CupertinoIcons.checkmark_alt, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'I Agree to 1:1 Biometric Verification',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Encrypted 192-D vectors only. Auto-purged after ${st.retentionDays} days per DPDP Act standards.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _angleIcon(FaceCaptureAngle angle) {
    switch (angle) {
      case FaceCaptureAngle.front:
        return CupertinoIcons.person_crop_circle_fill;
      case FaceCaptureAngle.left:
        return CupertinoIcons.arrow_left_circle_fill;
      case FaceCaptureAngle.right:
        return CupertinoIcons.arrow_right_circle_fill;
    }
  }
}
