import 'package:flutter/cupertino.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/klarna_tokens.dart';
import '../utils/secure_log.dart';
import 'app_update_service.dart';

class AppVersionService {
  static final AppVersionService instance = AppVersionService._internal();
  AppVersionService._internal();

  PackageInfo? _info;
  bool _initialized = false;

  /// Default fallback version matching current release in pubspec.yaml
  static const String fallbackVersion = '1.1.10';
  static const String fallbackBuildNumber = '31';

  Future<void> init() async {
    if (_initialized && _info != null) return;
    try {
      _info = await PackageInfo.fromPlatform();
      _initialized = true;
      secureLog('[AppVersion] Dynamically loaded package info: version=${_info?.version}, build=${_info?.buildNumber}');
    } catch (e) {
      secureLog('[AppVersion] PackageInfo.fromPlatform fallback notice: $e');
      _initialized = true;
    }
  }

  /// Package/App version (e.g. "1.0.9")
  String get version => (_info?.version.isNotEmpty == true) ? _info!.version : fallbackVersion;

  /// Build number / Version code (e.g. "14")
  String get buildNumber => (_info?.buildNumber.isNotEmpty == true) ? _info!.buildNumber : fallbackBuildNumber;

  /// Full formatted display version e.g. "v1.0.9 (Build 14)"
  String get displayVersion {
    final v = version;
    final b = buildNumber;
    return b.isNotEmpty ? 'v$v (Build $b)' : 'v$v';
  }

  /// Short display version e.g. "v1.0.9"
  String get shortVersion => 'v$version';
}

/// Reusable UI widget that dynamically displays the authentic app version badge
class AppVersionBadge extends StatefulWidget {
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;

  const AppVersionBadge({
    super.key,
    this.textStyle,
    this.padding,
  });

  @override
  State<AppVersionBadge> createState() => _AppVersionBadgeState();
}

class _AppVersionBadgeState extends State<AppVersionBadge> {
  late String _displayVersion;

  @override
  void initState() {
    super.initState();
    _displayVersion = AppVersionService.instance.displayVersion;
    _refreshVersion();
  }

  Future<void> _refreshVersion() async {
    await AppVersionService.instance.init();
    if (mounted) {
      setState(() {
        _displayVersion = AppVersionService.instance.displayVersion;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppUpdateService.instance,
      builder: (context, _) {
        final hasUpdate = AppUpdateService.instance.hasUpdate;

        return GestureDetector(
          onTap: () => AppUpdateService.instance.checkAndShowUpdateDialog(context, forceShow: true),
          child: Container(
            padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: hasUpdate ? AppColors.mintBg : AppColors.slateBg,
              borderRadius: AppRadius.borderPill,
              border: Border.all(
                color: hasUpdate ? AppColors.primaryAccent : AppColors.borderSubtle,
                width: hasUpdate ? 1.2 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasUpdate) ...[
                  const Icon(
                    CupertinoIcons.arrow_up_circle_fill,
                    size: 13,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  hasUpdate ? "$_displayVersion • Update Ready" : _displayVersion,
                  style: widget.textStyle ??
                      AppTypography.overline.copyWith(
                        color: hasUpdate ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
