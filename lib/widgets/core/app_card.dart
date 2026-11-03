import 'package:flutter/material.dart';
import '../../core/theme/klarna_tokens.dart';

enum AppCardVariant { standard, heroDark, pastelAccent }

/// Reusable Klarna-style Card Surface Component
class AppCard extends StatelessWidget {
  final Widget child;
  final AppCardVariant variant;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final double? width;

  const AppCard({
    super.key,
    required this.child,
    this.variant = AppCardVariant.standard,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.radius = AppRadius.card,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    List<BoxShadow> shadow;
    Border? border;

    switch (variant) {
      case AppCardVariant.heroDark:
        bg = AppColors.pillBlack;
        shadow = AppShadows.pillDark;
        border = null;
        break;
      case AppCardVariant.pastelAccent:
        bg = backgroundColor ?? AppColors.mintBg;
        shadow = [];
        border = Border.all(color: AppColors.borderSubtle);
        break;
      case AppCardVariant.standard:
        bg = backgroundColor ?? AppColors.surfaceWhite;
        shadow = AppShadows.softCard;
        border = Border.all(color: AppColors.borderSubtle);
        break;
    }

    Widget content = Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
        border: border,
      ),
      child: child,
    );

    if (onTap != null) {
      return _BouncyCard(
        onTap: onTap!,
        child: content,
      );
    }

    return content;
  }
}

class _BouncyCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _BouncyCard({required this.child, required this.onTap});

  @override
  State<_BouncyCard> createState() => _BouncyCardState();
}

class _BouncyCardState extends State<_BouncyCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.975).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
