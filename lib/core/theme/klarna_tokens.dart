import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';

export 'app_colors.dart';
export 'app_typography.dart';
export 'app_spacing.dart';
export 'app_radius.dart';
export 'app_shadows.dart';

/// Legacy KlarnaWorkForceTokens wrapper pointing to semantic tokens
class KlarnaWorkForceTokens {
  // Gradients
  static const LinearGradient emeraldAuraHeader = AppColors.emeraldAuraHeader;
  static const LinearGradient approvalsAura = AppColors.approvalsAuraHeader;
  static const LinearGradient darkCardGradient = AppColors.darkCardGradient;

  // Primaries
  static const Color primary = AppColors.primary;
  static const Color primaryAccent = AppColors.primaryAccent;
  static const Color pillBlack = AppColors.pillBlack;
  static const Color scaffoldBg = AppColors.scaffoldBg;

  // Klarna Palette
  static const Color klarnaPink = Color(0xFFFFB3C7);
  static const Color klarnaPinkSoft = Color(0xFFFFF0F5);
  static const Color klarnaPinkDeep = Color(0xFFE87A9A);
  static const Color klarnaBlack = Color(0xFF111111);
  static const Color klarnaDarkCharcoal = Color(0xFF1E1E1E);
  static const Color klarnaOffWhite = Color(0xFFF9F9FA);

  // Pastel Squircles
  static const Color iconBgMint = AppColors.mintBg;
  static const Color iconFgMint = AppColors.mintFg;

  static const Color iconBgLavender = AppColors.lavenderBg;
  static const Color iconFgLavender = AppColors.lavenderFg;

  static const Color iconBgSky = AppColors.skyBg;
  static const Color iconFgSky = AppColors.skyFg;

  static const Color iconBgPeach = AppColors.peachBg;
  static const Color iconFgPeach = AppColors.peachFg;

  static const Color iconBgRose = AppColors.roseBg;
  static const Color iconFgRose = AppColors.roseFg;

  static const Color iconBgLemon = AppColors.lemonBg;
  static const Color iconFgLemon = AppColors.lemonFg;

  static const Color iconBgTeal = AppColors.tealBg;
  static const Color iconFgTeal = AppColors.tealFg;

  static const Color iconBgAlert = AppColors.alertBg;
  static const Color iconFgAlert = AppColors.alertFg;

  static const Color iconBgSlate = AppColors.slateBg;
  static const Color iconFgSlate = AppColors.slateFg;

  // Radii
  static const double cardRadius = AppRadius.card;
  static const double pillRadius = AppRadius.pill;
  static const double squircleRadius = AppRadius.squircle;

  // Shadows
  static List<BoxShadow> softCardShadow = AppShadows.softCard;
  static List<BoxShadow> pillShadow = AppShadows.pillDark;
  static List<BoxShadow> glassShadow = AppShadows.glassNav;
}
