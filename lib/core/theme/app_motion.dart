import 'package:flutter/material.dart';

/// JOY PeopleHR Enterprise Motion & Animation Design Tokens
/// Core Philosophy: "FAST ACTION → SUBTLE FEEDBACK → CLEAR RESULT"
class AppMotion {
  // Durations
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 340);
  static const Duration successFeedback = Duration(milliseconds: 320);
  static const Duration pageTransition = Duration(milliseconds: 260);
  static const Duration shimmer = Duration(milliseconds: 1400);

  // Easing Curves
  static const Curve curveStandard = Curves.easeInOutCubic;
  static const Curve curveEnter = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveSpring = Curves.easeOutBack;

  /// Check if user has enabled reduced motion in their OS accessibility settings
  static bool isReducedMotion(BuildContext context) {
    return MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
  }
}

/// Standardized, subtle Enterprise Page Transitions
class AppTransitions {
  /// Enterprise Slide-up + Fade for Modals and Forms (260ms)
  static PageRouteBuilder<T> slideUp<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppMotion.pageTransition,
      reverseTransitionDuration: AppMotion.normal,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (AppMotion.isReducedMotion(context)) {
          return FadeTransition(opacity: animation, child: child);
        }
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: AppMotion.curveEnter,
          reverseCurve: AppMotion.curveExit,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.08),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  /// Enterprise Slide-right + Fade for Detail screens (240ms)
  static PageRouteBuilder<T> slideRight<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppMotion.pageTransition,
      reverseTransitionDuration: AppMotion.normal,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (AppMotion.isReducedMotion(context)) {
          return FadeTransition(opacity: animation, child: child);
        }
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: AppMotion.curveEnter,
          reverseCurve: AppMotion.curveExit,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0.0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  /// Subtle Fade-through transition for Tabs (180ms)
  static PageRouteBuilder<T> fadeThrough<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppMotion.normal,
      reverseTransitionDuration: AppMotion.fast,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }
}
