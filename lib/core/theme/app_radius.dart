import 'package:flutter/material.dart';

/// Klarna-style Shape Geometry & Radius Tokens
class AppRadius {
  AppRadius._();

  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 18.0;
  static const double squircle = 22.0;
  static const double lg = 24.0;
  static const double card = 26.0;
  static const double sheet = 28.0;
  static const double pill = 100.0;

  // BorderRadius instances
  static BorderRadius get borderXs => BorderRadius.circular(xs);
  static BorderRadius get borderSm => BorderRadius.circular(sm);
  static BorderRadius get borderMd => BorderRadius.circular(md);
  static BorderRadius get borderSquircle => BorderRadius.circular(squircle);
  static BorderRadius get borderLg => BorderRadius.circular(lg);
  static BorderRadius get borderCard => BorderRadius.circular(card);
  static BorderRadius get borderSheet => const BorderRadius.vertical(top: Radius.circular(sheet));
  static BorderRadius get borderPill => BorderRadius.circular(pill);
}
