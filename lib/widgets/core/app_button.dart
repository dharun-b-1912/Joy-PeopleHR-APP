import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/klarna_tokens.dart';

enum AppButtonVariant { primaryPill, secondaryPill, outlinePill, textPill }

/// Standardized Klarna-style Pill Button Widget
class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final Color? customBgColor;
  final Color? customFgColor;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primaryPill,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.customBgColor,
    this.customFgColor,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.forward();
      HapticFeedback.lightImpact();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.reverse();
      widget.onPressed!();
    }
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Border? border;

    switch (widget.variant) {
      case AppButtonVariant.secondaryPill:
        bg = widget.customBgColor ?? AppColors.slateBg;
        fg = widget.customFgColor ?? AppColors.textPrimary;
        border = null;
        break;
      case AppButtonVariant.outlinePill:
        bg = Colors.transparent;
        fg = widget.customFgColor ?? AppColors.textPrimary;
        border = Border.all(color: AppColors.textMuted.withValues(alpha: 0.4));
        break;
      case AppButtonVariant.textPill:
        bg = Colors.transparent;
        fg = widget.customFgColor ?? AppColors.primary;
        border = null;
        break;
      case AppButtonVariant.primaryPill:
        bg = widget.customBgColor ?? AppColors.pillBlack;
        fg = widget.customFgColor ?? Colors.white;
        border = null;
        break;
    }

    final bool disabled = widget.onPressed == null || widget.isLoading;

    Widget child = Row(
      mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          AppSpacing.hGapSM,
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyRegular.copyWith(
                fontWeight: FontWeight.w700,
                color: disabled ? fg.withValues(alpha: 0.5) : fg,
              ),
            ),
          ),
        ),
      ],
    );

    return GestureDetector(
      onTapDown: disabled ? null : _onTapDown,
      onTapUp: disabled ? null : _onTapUp,
      onTapCancel: disabled ? null : _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: disabled ? bg.withValues(alpha: 0.6) : bg,
            borderRadius: AppRadius.borderPill,
            border: border,
            boxShadow: widget.variant == AppButtonVariant.primaryPill && !disabled
                ? AppShadows.pillDark
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
