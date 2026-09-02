import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Standardized Klarna-style Shadow & Elevation Tokens
class AppShadows {
  AppShadows._();

  static List<BoxShadow> get softCard => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get pillDark => [
        BoxShadow(
          color: AppColors.pillBlack.withValues(alpha: 0.22),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get glassNav => [
        BoxShadow(
          color: AppColors.pillBlack.withValues(alpha: 0.12),
          blurRadius: 30,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> appletTile(Color fgColor) => [
        BoxShadow(
          color: fgColor.withValues(alpha: 0.08),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get bottomSheet => [
        BoxShadow(
          color: AppColors.pillBlack.withValues(alpha: 0.2),
          blurRadius: 40,
          offset: const Offset(0, -8),
        ),
      ];
}
