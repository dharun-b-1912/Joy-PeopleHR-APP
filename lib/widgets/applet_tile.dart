import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/klarna_tokens.dart';
import '../models/hrms_models.dart';

class AppletTileWidget extends StatefulWidget {
  final AppletTileModel tile;
  final VoidCallback? onTap;
  final bool compact;

  const AppletTileWidget({
    super.key,
    required this.tile,
    this.onTap,
    this.compact = false,
  });

  @override
  State<AppletTileWidget> createState() => _AppletTileWidgetState();
}

class _AppletTileWidgetState extends State<AppletTileWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
    HapticFeedback.lightImpact();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final double boxSize = widget.compact ? 56.0 : 52.0;
    final double iconSize = widget.compact ? 24.0 : 22.0;
    const double fontSize = 11.0;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                color: widget.tile.bg,
                borderRadius: AppRadius.borderSquircle,
                boxShadow: AppShadows.appletTile(widget.tile.fg),
              ),
              child: Center(
                child: Icon(
                  widget.tile.icon,
                  color: widget.tile.fg,
                  size: iconSize,
                ),
              ),
            ),
            AppSpacing.gapXS,
            FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.compact ? 64 : 56,
                ),
                child: Text(
                  widget.tile.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
