import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/klarna_tokens.dart';

enum SubmitButtonState { idle, submitting, success, disabled }

/// Universal Enterprise Submit Button with Double-Tap Protection
/// and Animated State Transitions: IDLE → SUBMITTING → SUCCESS
class WorkForceSubmitButton extends StatefulWidget {
  final String label;
  final String? submittingLabel;
  final String? successLabel;
  final Future<bool> Function()? onSubmit;
  final VoidCallback? onSuccess;
  final bool isDisabled;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double height;
  final double? width;

  const WorkForceSubmitButton({
    super.key,
    required this.label,
    this.submittingLabel,
    this.successLabel,
    this.onSubmit,
    this.onSuccess,
    this.isDisabled = false,
    this.backgroundColor,
    this.foregroundColor,
    this.height = 48,
    this.width,
  });

  @override
  State<WorkForceSubmitButton> createState() => _WorkForceSubmitButtonState();
}

class _WorkForceSubmitButtonState extends State<WorkForceSubmitButton> with SingleTickerProviderStateMixin {
  SubmitButtonState _state = SubmitButtonState.idle;
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  Future<void> _handlePress() async {
    // 1. Double-tap protection
    if (_state != SubmitButtonState.idle || widget.isDisabled || widget.onSubmit == null) {
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _state = SubmitButtonState.submitting);

    try {
      final success = await widget.onSubmit!();
      if (!mounted) return;

      if (success) {
        setState(() => _state = SubmitButtonState.success);
        HapticFeedback.mediumImpact();
        await Future.delayed(AppMotion.successFeedback);
        if (mounted) {
          widget.onSuccess?.call();
          setState(() => _state = SubmitButtonState.idle);
        }
      } else {
        setState(() => _state = SubmitButtonState.idle);
      }
    } catch (_) {
      if (mounted) setState(() => _state = SubmitButtonState.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInactive = widget.isDisabled || _state == SubmitButtonState.disabled;
    final bg = _state == SubmitButtonState.success
        ? AppColors.primary
        : (isInactive
            ? AppColors.textMuted.withValues(alpha: 0.2)
            : (widget.backgroundColor ?? AppColors.primary));
    final fg = widget.foregroundColor ?? Colors.white;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: child,
      ),
      child: GestureDetector(
        onTapDown: (_) {
          if (_state == SubmitButtonState.idle && !isInactive) {
            _pressController.forward();
          }
        },
        onTapUp: (_) {
          if (_state == SubmitButtonState.idle && !isInactive) {
            _pressController.reverse();
            _handlePress();
          }
        },
        onTapCancel: () => _pressController.reverse(),
        child: AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.curveStandard,
          height: widget.height,
          width: widget.width ?? double.infinity,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.borderMd,
            boxShadow: isInactive
                ? []
                : [
                    BoxShadow(
                      color: bg.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: AppMotion.fast,
              child: _buildContent(fg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color fg) {
    switch (_state) {
      case SubmitButtonState.submitting:
        return Row(
          key: const ValueKey('submitting'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
            const SizedBox(width: 10),
            Text(
              widget.submittingLabel ?? "Submitting...",
              style: AppTypography.bodyRegular.copyWith(
                color: fg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );

      case SubmitButtonState.success:
        return Row(
          key: const ValueKey('success'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.checkmark_circle_fill, color: fg, size: 20),
            const SizedBox(width: 8),
            Text(
              widget.successLabel ?? "Submitted",
              style: AppTypography.bodyRegular.copyWith(
                color: fg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );

      case SubmitButtonState.idle:
      case SubmitButtonState.disabled:
        return Text(
          widget.label,
          key: const ValueKey('idle'),
          style: AppTypography.bodyLarge.copyWith(
            color: widget.isDisabled ? AppColors.textMuted : fg,
            fontWeight: FontWeight.bold,
          ),
        );
    }
  }
}
