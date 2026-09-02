// app_services_catalog.dart
// ============================================================================
// WorkForceOS — Production Applet & Navigation Service Catalog
// UI Navigation routes and action tiles (Zero mock data)
// ============================================================================

import 'package:flutter/cupertino.dart';
import '../core/theme/klarna_tokens.dart';
import 'hrms_models.dart';

final List<AppletTileModel> quickServices = [
  const AppletTileModel(
    id: "regularize",
    label: "Regularize",
    icon: CupertinoIcons.arrow_2_squarepath,
    bg: KlarnaWorkForceTokens.iconBgRose,
    fg: KlarnaWorkForceTokens.iconFgRose,
  ),
  const AppletTileModel(
    id: "apply_leave",
    label: "Leave",
    icon: CupertinoIcons.calendar,
    bg: KlarnaWorkForceTokens.iconBgLavender,
    fg: KlarnaWorkForceTokens.iconFgLavender,
  ),
  const AppletTileModel(
    id: "payslip",
    label: "Payslip",
    icon: CupertinoIcons.doc_text,
    bg: KlarnaWorkForceTokens.iconBgSky,
    fg: KlarnaWorkForceTokens.iconFgSky,
  ),
  const AppletTileModel(
    id: "claims",
    label: "Claims",
    icon: CupertinoIcons.money_dollar_circle,
    bg: KlarnaWorkForceTokens.iconBgPeach,
    fg: KlarnaWorkForceTokens.iconFgPeach,
  ),
  const AppletTileModel(
    id: "helpdesk",
    label: "HR Helpdesk",
    icon: CupertinoIcons.question_circle_fill,
    bg: KlarnaWorkForceTokens.iconBgSky,
    fg: KlarnaWorkForceTokens.iconFgSky,
  ),
];

final List<AppletTileModel> allServicesList = [
  const AppletTileModel(
    id: "geo",
    label: "Geo\nAttendance",
    icon: CupertinoIcons.clock,
    bg: KlarnaWorkForceTokens.iconBgMint,
    fg: KlarnaWorkForceTokens.iconFgMint,
  ),
  const AppletTileModel(
    id: "leave",
    label: "Apply Leave",
    icon: CupertinoIcons.calendar,
    bg: KlarnaWorkForceTokens.iconBgLavender,
    fg: KlarnaWorkForceTokens.iconFgLavender,
  ),
  const AppletTileModel(
    id: "payslip",
    label: "Payslips &\nForm 16",
    icon: CupertinoIcons.doc_text,
    bg: KlarnaWorkForceTokens.iconBgSky,
    fg: KlarnaWorkForceTokens.iconFgSky,
  ),
  const AppletTileModel(
    id: "tax",
    label: "Tax\nCalculator",
    icon: CupertinoIcons.table_badge_more,
    bg: KlarnaWorkForceTokens.iconBgLemon,
    fg: KlarnaWorkForceTokens.iconFgLemon,
  ),
  const AppletTileModel(
    id: "roster",
    label: "Shift Roster",
    icon: CupertinoIcons.square_grid_2x2,
    bg: KlarnaWorkForceTokens.iconBgTeal,
    fg: KlarnaWorkForceTokens.iconFgTeal,
  ),
  const AppletTileModel(
    id: "expense",
    label: "Expense\nClaims",
    icon: CupertinoIcons.money_dollar_circle,
    bg: KlarnaWorkForceTokens.iconBgPeach,
    fg: KlarnaWorkForceTokens.iconFgPeach,
  ),
  const AppletTileModel(
    id: "overtime",
    label: "Overtime\nTracker",
    icon: CupertinoIcons.bolt,
    bg: KlarnaWorkForceTokens.iconBgRose,
    fg: KlarnaWorkForceTokens.iconFgRose,
  ),
  const AppletTileModel(
    id: "okrs",
    label: "OKRs &\nGoals",
    icon: CupertinoIcons.scope,
    bg: KlarnaWorkForceTokens.iconBgMint,
    fg: KlarnaWorkForceTokens.iconFgMint,
  ),
  const AppletTileModel(
    id: "letters",
    label: "Digital\nLetters",
    icon: CupertinoIcons.rosette,
    bg: KlarnaWorkForceTokens.iconBgSky,
    fg: KlarnaWorkForceTokens.iconFgSky,
  ),
  const AppletTileModel(
    id: "sos",
    label: "Emergency\nSOS",
    icon: CupertinoIcons.exclamationmark_triangle,
    bg: KlarnaWorkForceTokens.iconBgAlert,
    fg: KlarnaWorkForceTokens.iconFgAlert,
  ),
];

final List<PassCardModel> passCardsList = [
  const PassCardModel(
    id: "work",
    label: "Work Pass",
    title: "Digital Biometric Pass",
    subtitle: "NFC & QR Workplace Access",
  ),
  const PassCardModel(
    id: "insurance",
    label: "Insurance Card",
    title: "Group Health Cover",
    subtitle: "Active Corporate Employee Cover",
  ),
  const PassCardModel(
    id: "meal",
    label: "Meal Pass",
    title: "Campus Meal Wallet",
    subtitle: "Campus Dining & Smart Card",
  ),
];
