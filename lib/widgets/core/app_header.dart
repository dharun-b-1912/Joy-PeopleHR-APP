import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/klarna_tokens.dart';

/// Reusable Klarna-style Header Component with Aura Gradient & Safe-Area Support
class AppHeader extends StatelessWidget {
  final String subtitle;
  final String title;
  final Widget? rightAction;
  final Widget? bottomWidget;
  final LinearGradient gradient;

  const AppHeader({
    super.key,
    required this.subtitle,
    required this.title,
    this.rightAction,
    this.bottomWidget,
    this.gradient = AppColors.emeraldAuraHeader,
  });

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top + 16;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          topPadding,
          AppSpacing.screenHorizontal,
          bottomWidget != null ? AppSpacing.lg : 16,
        ),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppRadius.sheet),
          ),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: AppTypography.displayHeader,
                    ),
                  ],
                ),
              ),
              if (rightAction != null) rightAction!,
            ],
          ),
          if (bottomWidget != null) ...[
            AppSpacing.gapMD,
            bottomWidget!,
          ],
        ],
      ),
    ),
  );
}
}
