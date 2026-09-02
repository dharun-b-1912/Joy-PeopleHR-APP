import 'package:flutter/material.dart';

/// Centralized semantic color tokens for WorkForceOS Enterprise (Klarna-style Mobile UX)
class AppColors {
  AppColors._();

  // --- BRAND PRIMARIES ---
  static const Color primary = Color(0xFF07563D);        // WorkForce Emerald
  static const Color primaryAccent = Color(0xFF10B981);  // Mint Emerald
  static const Color pillBlack = Color(0xFF0F172A);      // Deep Slate (Dominant Buttons/Cards)
  static const Color scaffoldBg = Color(0xFFF8FAFC);     // Light Slate Background
  static const Color surfaceWhite = Colors.white;
  static const Color surfaceSubtle = Color(0xFFF1F5F9);
  static const Color borderSubtle = Color(0x0A000000);   // Subtle 4% Black Border
  static const Color borderLight = Color(0xFFF1F5F9);

  // --- TEXT COLORED HIERARCHY ---
  static const Color textPrimary = Color(0xFF0F172A);    // Dark Slate
  static const Color textSecondary = Color(0xFF64748B);  // Slate 500
  static const Color textMuted = Color(0xFF94A3B8);      // Slate 400
  static const Color textOnDark = Colors.white;
  static const Color textOnDarkMuted = Color(0x99FFFFFF); // 60% White

  // --- STATUS & HR SEMANTICS ---
  static const Color statusSuccess = Color(0xFF047857);
  static const Color statusSuccessBg = Color(0xFFDCFCE7); 
  
  static const Color statusWarning = Color(0xFFEA580C);
  static const Color statusWarningBg = Color(0xFFFFEDD5);

  static const Color statusError = Color(0xFFDC2626);
  static const Color statusErrorBg = Color(0xFFFEE2E2);

  static const Color statusInfo = Color(0xFF0284C7);
  static const Color statusInfoBg = Color(0xFFE0F2FE);

  // --- PASTEL APPLET SQUIRCLES ---
  static const Color mintBg = Color(0xFFDCFCE7);
  static const Color mintFg = Color(0xFF047857);

  static const Color lavenderBg = Color(0xFFEDE9FE);
  static const Color lavenderFg = Color(0xFF7C3AED);

  static const Color skyBg = Color(0xFFE0F2FE);
  static const Color skyFg = Color(0xFF0284C7);

  static const Color peachBg = Color(0xFFFFEDD5);
  static const Color peachFg = Color(0xFFEA580C);

  static const Color roseBg = Color(0xFFFFE4E6);
  static const Color roseFg = Color(0xFFE11D48);

  static const Color lemonBg = Color(0xFFFEF9C3);
  static const Color lemonFg = Color(0xFFA16207);

  static const Color tealBg = Color(0xFFCCFBF1);
  static const Color tealFg = Color(0xFF0D9488);

  static const Color alertBg = Color(0xFFFEE2E2);
  static const Color alertFg = Color(0xFFDC2626);

  static const Color slateBg = Color(0xFFF1F5F9);
  static const Color slateFg = Color(0xFF475569);

  // --- AURA GRADIENTS ---
  static const LinearGradient emeraldAuraHeader = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE6F4EA), // Soft Mint Mist
      Color(0xFFDCFCE7), // Spring Green Tint
      Color(0xFFF0FDF4), // Cream Mint
      Color(0xFFFFFFFF), // Pure Surface White
    ],
    stops: [0.0, 0.32, 0.66, 1.0],
  );

  static const LinearGradient approvalsAuraHeader = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEDE9FE), // Lavender Mist
      Color(0xFFE6F4EA), // Soft Mint
      Color(0xFFF0FDF4), // White Green
    ],
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF042F2E), // Deep Emerald Slate
      Color(0xFF0B1B17), // Forest Shadow
      Color(0xFF0F172A), // Dark Navy Slate
    ],
    stops: [0.0, 0.55, 1.0],
  );
}
