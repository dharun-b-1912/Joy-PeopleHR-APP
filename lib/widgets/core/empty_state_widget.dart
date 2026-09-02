import 'package:flutter/material.dart';
import '../../core/theme/klarna_tokens.dart';
import 'app_button.dart';

/// Reusable Klarna-style Empty State Widget
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    this.bg = AppColors.mintBg,
    this.fg = AppColors.mintFg,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppRadius.borderSquircle,
                boxShadow: AppShadows.appletTile(fg),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: fg,
                  size: 28,
                ),
              ),
            ),
            AppSpacing.gapLG,
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.titleLarge,
            ),
            AppSpacing.gapXS,
            Text(
              description,
              textAlign: TextAlign.center,
              style: AppTypography.bodyRegular,
            ),
            if (actionLabel != null && onAction != null) ...[
              AppSpacing.gapXL,
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: AppButtonVariant.primaryPill,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
