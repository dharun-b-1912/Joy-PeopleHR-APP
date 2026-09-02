import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/klarna_tokens.dart';

/// Lightweight, high-performance Flutter-native skeleton shimmer
/// Eliminates heavy third-party dependencies and excessive repaint cycles.
class AppSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;

  const AppSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.shape,
  });

  const AppSkeleton.rect({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  }) : shape = null;

  const AppSkeleton.circle({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = null,
        shape = const CircleBorder();

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();

  // ── Pre-built Composite Skeletons ──────────────────────────────────────────

  /// Standard Card Skeleton
  static Widget card({double height = 90, EdgeInsetsGeometry? padding}) {
    return Container(
      height: height,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.borderLg,
        border: Border.all(color: AppColors.borderSubtle.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const AppSkeleton.circle(size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppSkeleton.rect(width: 140, height: 14, borderRadius: AppRadius.borderSm),
                const SizedBox(height: 8),
                AppSkeleton.rect(width: 90, height: 10, borderRadius: AppRadius.borderSm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Attendance Record Row Skeleton
  static Widget attendanceRow() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.borderLg,
        border: Border.all(color: AppColors.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          AppSkeleton.rect(width: 50, height: 38, borderRadius: AppRadius.borderMd),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeleton.rect(width: 120, height: 12, borderRadius: AppRadius.borderSm),
                const SizedBox(height: 6),
                AppSkeleton.rect(width: 80, height: 10, borderRadius: AppRadius.borderSm),
              ],
            ),
          ),
          AppSkeleton.rect(width: 60, height: 22, borderRadius: AppRadius.borderPill),
        ],
      ),
    );
  }

  /// Leave Balance Card Skeleton
  static Widget leaveBalanceCard() {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.borderLg,
        border: Border.all(color: AppColors.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSkeleton.circle(size: 32),
          const SizedBox(height: 12),
          AppSkeleton.rect(width: 40, height: 20, borderRadius: AppRadius.borderSm),
          const SizedBox(height: 6),
          AppSkeleton.rect(width: 80, height: 10, borderRadius: AppRadius.borderSm),
        ],
      ),
    );
  }
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.shimmer,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: ShapeDecoration(
          color: const Color(0xFFE2E8F0),
          shape: widget.shape ??
              RoundedRectangleBorder(
                borderRadius: widget.borderRadius ?? AppRadius.borderSm,
              ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: ShapeDecoration(
            color: Color.lerp(
              const Color(0xFFE6EDF5),
              const Color(0xFFF1F5F9),
              _animation.value,
            ),
            shape: widget.shape ??
                RoundedRectangleBorder(
                  borderRadius: widget.borderRadius ?? AppRadius.borderSm,
                ),
          ),
        );
      },
    );
  }
}
