import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/klarna_tokens.dart';
import '../utils/secure_log.dart';
import 'app_version_service.dart';

/// Data model representing remote and local version comparison state
class AppUpdateInfo {
  final String currentVersion;
  final int currentBuildNumber;
  final String latestVersion;
  final int latestBuildNumber;
  final String releaseNotes;
  final String playStoreUrl;
  final bool isForceUpdate;
  final bool isUpdateAvailable;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.releaseNotes,
    required this.playStoreUrl,
    required this.isForceUpdate,
    required this.isUpdateAvailable,
  });

  factory AppUpdateInfo.upToDate({
    required String currentVersion,
    required int currentBuildNumber,
  }) {
    return AppUpdateInfo(
      currentVersion: currentVersion,
      currentBuildNumber: currentBuildNumber,
      latestVersion: currentVersion,
      latestBuildNumber: currentBuildNumber,
      releaseNotes: 'You are using the latest version of JOY PeopleHR.',
      playStoreUrl: 'https://play.google.com/store/apps/details?id=com.joypeoplehr.app',
      isForceUpdate: false,
      isUpdateAvailable: false,
    );
  }
}

/// Service managing remote version discovery, snooze cooldowns, and Play Store redirection
class AppUpdateService extends ChangeNotifier {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  static const String _prefSnoozeKey = 'app_update_snooze_timestamp';
  static const String _defaultPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.joypeoplehr.app';
  static const String _defaultMarketUrl = 'market://details?id=com.joypeoplehr.app';

  AppUpdateInfo? _updateInfo;
  bool _isChecking = false;

  AppUpdateInfo? get updateInfo => _updateInfo;
  bool get isChecking => _isChecking;
  bool get hasUpdate => _updateInfo?.isUpdateAvailable ?? false;

  /// Checks for newer versions against remote Supabase config
  Future<AppUpdateInfo> checkForUpdate({bool ignoreSnooze = false}) async {
    if (_isChecking && _updateInfo != null) return _updateInfo!;
    _isChecking = true;
    notifyListeners();

    try {
      await AppVersionService.instance.init();
      final currentVer = AppVersionService.instance.version;
      final currentBuild = int.tryParse(AppVersionService.instance.buildNumber) ?? 31;

      // Query Supabase for remote version config
      Map<String, dynamic>? remoteRow;
      try {
        final res = await Supabase.instance.client
            .from('app_versions')
            .select('*')
            .eq('platform', 'android')
            .eq('is_active', true)
            .maybeSingle();
        remoteRow = res;
      } catch (e) {
        secureLog('[AppUpdate] Notice: app_versions query fallback: $e');
      }

      if (remoteRow != null) {
        final latestVer = (remoteRow['latest_version'] as String?) ?? currentVer;
        final latestBuild = (remoteRow['latest_build_number'] as num?)?.toInt() ?? currentBuild;
        final releaseNotes = (remoteRow['release_notes'] as String?) ??
            '• Unified payslips with accurate deductions\n• Automated leave calculation improvements\n• Clean push notifications\n• Upgraded top UI aura styling';
        final playStoreUrl = (remoteRow['play_store_url'] as String?) ?? _defaultPlayStoreUrl;
        final isForce = (remoteRow['is_force_update'] as bool?) ?? false;

        final isAvailable = latestBuild > currentBuild;

        _updateInfo = AppUpdateInfo(
          currentVersion: currentVer,
          currentBuildNumber: currentBuild,
          latestVersion: latestVer,
          latestBuildNumber: latestBuild,
          releaseNotes: releaseNotes,
          playStoreUrl: playStoreUrl,
          isForceUpdate: isForce,
          isUpdateAvailable: isAvailable,
        );
      } else {
        // Fallback: If remote table is unreachable, current build is considered up-to-date
        _updateInfo = AppUpdateInfo.upToDate(
          currentVersion: currentVer,
          currentBuildNumber: currentBuild,
        );
      }
    } catch (e) {
      secureLog('[AppUpdate] General check error: $e');
      final currentVer = AppVersionService.instance.version;
      final currentBuild = int.tryParse(AppVersionService.instance.buildNumber) ?? 31;
      _updateInfo = AppUpdateInfo.upToDate(
        currentVersion: currentVer,
        currentBuildNumber: currentBuild,
      );
    } finally {
      _isChecking = false;
      notifyListeners();
    }

    return _updateInfo!;
  }

  /// Checks if the employee snoozed update prompt within the last 24 hours
  Future<bool> isSnoozed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozeTimestamp = prefs.getInt(_prefSnoozeKey);
      if (snoozeTimestamp == null) return false;

      final snoozedAt = DateTime.fromMillisecondsSinceEpoch(snoozeTimestamp);
      final difference = DateTime.now().difference(snoozedAt);
      return difference.inHours < 24;
    } catch (_) {
      return false;
    }
  }

  /// Snoozes non-forced update prompts for 24 hours
  Future<void> snoozeUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefSnoozeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Opens the official Google Play Store app page
  Future<void> openPlayStore({String? targetUrl}) async {
    final webUrl = targetUrl?.isNotEmpty == true ? targetUrl! : _defaultPlayStoreUrl;
    final marketUri = Uri.parse(_defaultMarketUrl);
    final webUri = Uri.parse(webUrl);

    try {
      if (await canLaunchUrl(marketUri)) {
        await launchUrl(marketUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      secureLog('[AppUpdate] Could not open Play Store: $e');
    }
  }

  /// Triggers update: first attempts Google Play native in-app update, then falls back to store link
  Future<void> performUpdate({String? targetUrl, bool immediate = true}) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final updateInfo = await InAppUpdate.checkForUpdate();
        if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
          if (immediate && updateInfo.immediateUpdateAllowed) {
            final result = await InAppUpdate.performImmediateUpdate();
            if (result == AppUpdateResult.success) return;
          } else if (updateInfo.flexibleUpdateAllowed) {
            final result = await InAppUpdate.startFlexibleUpdate();
            if (result == AppUpdateResult.success) {
              await InAppUpdate.completeFlexibleUpdate();
              return;
            }
          }
        }
      } catch (e) {
        secureLog('[AppUpdate] Native Google Play in-app update notice: $e (falling back to store URL)');
      }
    }

    // Direct store launch fallback
    await openPlayStore(targetUrl: targetUrl);
  }

  /// Evaluates update state and presents the update modal dialog if available
  Future<void> checkAndShowUpdateDialog(BuildContext context, {bool forceShow = false}) async {
    final info = await checkForUpdate(ignoreSnooze: forceShow);
    if (!context.mounted) return;

    if (!info.isUpdateAvailable) {
      if (forceShow) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  "You're using the latest version of JOY PeopleHR (${info.currentVersion})",
                  style: AppTypography.bodyRegular.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!forceShow && !info.isForceUpdate) {
      final snoozed = await isSnoozed();
      if (snoozed) return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: !info.isForceUpdate,
        builder: (dialogCtx) => AppUpdateDialog(info: info),
      );
    }
  }
}

/// Modern Klarna-styled dialog presenting the update announcement
class AppUpdateDialog extends StatelessWidget {
  final AppUpdateInfo info;

  const AppUpdateDialog({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !info.isForceUpdate,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppShadows.softCard,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon Header with Emerald Aura
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.mintBg,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.arrow_down_circle_fill,
                      color: AppColors.primary,
                      size: 34,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                "New Version Available",
                style: AppTypography.displayHeader.copyWith(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                "A fresh update for JOY PeopleHR is ready on the Google Play Store with performance upgrades and enhancements.",
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Version Badges Comparison
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.slateBg,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          "INSTALLED",
                          style: AppTypography.overline.copyWith(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "v${info.currentVersion}",
                          style: AppTypography.bodyRegular.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Icon(
                      CupertinoIcons.arrow_right,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    Column(
                      children: [
                        Text(
                          "LATEST",
                          style: AppTypography.overline.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "v${info.latestVersion}",
                          style: AppTypography.bodyRegular.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Release Notes Preview
              Text(
                "WHAT'S NEW",
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.45,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Primary CTA: Update Now (Native In-App Update / Store)
              ElevatedButton(
                onPressed: () async {
                  if (!info.isForceUpdate) {
                    Navigator.of(context).pop();
                  }
                  await AppUpdateService.instance.performUpdate(
                    targetUrl: info.playStoreUrl,
                    immediate: info.isForceUpdate,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.borderPill,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.cloud_download_fill, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      info.isForceUpdate ? "Update Required Now" : "Update from Play Store",
                      style: AppTypography.bodyRegular.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Secondary CTA: Remind Me Later
              if (!info.isForceUpdate) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await AppUpdateService.instance.snoozeUpdate();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    "Remind Me Later",
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
