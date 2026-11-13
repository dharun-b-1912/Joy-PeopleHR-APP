import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum FaceCaptureAngle {
  front,
  left,
  right,
}

/// Circular portrait camera dial with animated enlargement, smooth radial
/// green progress ring, face-oval alignment guide, and quality warning pill.
class FaceCaptureDial extends StatelessWidget {
  final CameraController? cameraController;
  final bool cameraReady;
  final double progress; // 0.0 .. 1.0
  final Color ringColor;
  final String instruction;
  final FaceCaptureAngle angle;
  final Uint8List? capturedPreviewBytes;
  final bool isScanning;
  final bool justCaptured;
  final String? warningMessage;
  final double? diameter;

  const FaceCaptureDial({
    super.key,
    required this.cameraController,
    required this.cameraReady,
    required this.progress,
    required this.ringColor,
    required this.instruction,
    this.angle = FaceCaptureAngle.front,
    this.capturedPreviewBytes,
    this.isScanning = false,
    this.justCaptured = false,
    this.warningMessage,
    this.diameter,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final baseSize = diameter ?? math.min(screenW * 0.66, 246.0);
    final size = isScanning ? math.min(screenW * 0.80, baseSize + 38.0) : baseSize;
    final hasWarning = warningMessage != null && warningMessage!.isNotEmpty;
    final effectiveColor = hasWarning ? const Color(0xFFD97706) : ringColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Instruction / status pill above the circular dial
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: effectiveColor.withValues(alpha: 0.50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasWarning ? CupertinoIcons.exclamationmark_triangle_fill : _angleIcon(angle),
                size: 15,
                color: effectiveColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  instruction,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Enlarging circular dial container
        AnimatedContainer(
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutBack,
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, animatedProgress, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final liveSize = constraints.biggest.shortestSide;
                  final innerSize = math.max(120.0, liveSize - 24);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer radial tick + smooth progress arc dial
                      CustomPaint(
                        size: Size(liveSize, liveSize),
                        painter: _DialRingPainter(
                          progress: animatedProgress,
                          activeColor: effectiveColor,
                        ),
                      ),
                      // Round portrait camera viewport
                      Container(
                        width: innerSize,
                        height: innerSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0F172A),
                          boxShadow: [
                            BoxShadow(
                              color: effectiveColor.withValues(alpha: isScanning ? 0.28 : 0.16),
                              blurRadius: isScanning ? 24 : 16,
                              spreadRadius: isScanning ? 3 : 1,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (capturedPreviewBytes != null)
                                Image.memory(capturedPreviewBytes!, fit: BoxFit.cover)
                              else if (cameraReady &&
                                  cameraController != null &&
                                  cameraController!.value.isInitialized)
                                _buildPortraitCroppedPreview(cameraController!)
                              else
                                const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(CupertinoIcons.camera, color: Colors.white70, size: 38),
                                      SizedBox(height: 8),
                                      Text(
                                        'Tap Start Below\nto Open Front Camera',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              if (capturedPreviewBytes == null)
                                CustomPaint(
                                  painter: _FaceOvalGuidePainter(
                                    color: effectiveColor,
                                    angle: angle,
                                  ),
                                ),
                              if (justCaptured)
                                Container(
                                  color: const Color(0xFF16A34A).withValues(alpha: 0.28),
                                  child: const Center(
                                    child: Icon(
                                      CupertinoIcons.checkmark_circle_fill,
                                      color: Colors.white,
                                      size: 56,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (hasWarning) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.lightbulb_fill, size: 16, color: Color(0xFFB45309)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    warningMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPortraitCroppedPreview(CameraController ctrl) {
    final previewSize = ctrl.value.previewSize;
    final w = previewSize != null ? math.min(previewSize.width, previewSize.height) : 480.0;
    final h = previewSize != null ? math.max(previewSize.width, previewSize.height) : 640.0;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: w,
        height: h,
        child: CameraPreview(ctrl),
      ),
    );
  }

  IconData _angleIcon(FaceCaptureAngle a) {
    switch (a) {
      case FaceCaptureAngle.left:
        return CupertinoIcons.arrow_left_circle_fill;
      case FaceCaptureAngle.right:
        return CupertinoIcons.arrow_right_circle_fill;
      case FaceCaptureAngle.front:
        return CupertinoIcons.person_crop_circle_fill;
    }
  }
}

class _DialRingPainter extends CustomPainter {
  final double progress;
  final Color activeColor;

  _DialRingPainter({
    required this.progress,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const totalTicks = 36;
    final activeTicks = (totalTicks * progress).round();

    for (var i = 0; i < totalTicks; i++) {
      final theta = -math.pi / 2 + (2 * math.pi * i) / totalTicks;
      final isMajor = i % 3 == 0;
      final isActive = i < activeTicks;
      final outerR = radius;
      final innerR = radius - (isMajor ? 9.5 : 5.5);

      final p1 = Offset(center.dx + innerR * math.cos(theta), center.dy + innerR * math.sin(theta));
      final p2 = Offset(center.dx + outerR * math.cos(theta), center.dy + outerR * math.sin(theta));

      final tickPaint = Paint()
        ..color = isActive ? activeColor : Colors.grey.shade300
        ..strokeWidth = isMajor ? 2.8 : 1.7
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(p1, p2, tickPaint);
    }

    if (progress > 0) {
      final arcPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 11),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DialRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.activeColor != activeColor;
  }
}

class _FaceOvalGuidePainter extends CustomPainter {
  final Color color;
  final FaceCaptureAngle angle;

  _FaceOvalGuidePainter({
    required this.color,
    required this.angle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.62,
      height: size.height * 0.78,
    );

    final bgPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()..addOval(ovalRect);
    final maskPath = Path.combine(PathOperation.difference, bgPath, holePath);
    canvas.drawPath(maskPath, Paint()..color = Colors.black.withValues(alpha: 0.30));

    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    canvas.drawOval(ovalRect, borderPaint);

    if (angle != FaceCaptureAngle.front) {
      final dir = angle == FaceCaptureAngle.left ? -1.0 : 1.0;
      final arrowPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round;
      final ax = center.dx + dir * (ovalRect.width * 0.30);
      final ay = center.dy;
      canvas.drawLine(Offset(ax - dir * 10, ay), Offset(ax + dir * 6, ay), arrowPaint);
      canvas.drawLine(Offset(ax + dir * 6, ay), Offset(ax, ay - 6), arrowPaint);
      canvas.drawLine(Offset(ax + dir * 6, ay), Offset(ax, ay + 6), arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceOvalGuidePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.angle != angle;
  }
}
