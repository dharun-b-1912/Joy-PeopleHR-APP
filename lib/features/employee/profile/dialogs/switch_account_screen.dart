import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';

class SwitchAccountScreen extends StatelessWidget {
  const SwitchAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserService.instance,
      builder: (context, _) {
        final activeUser = UserService.instance.currentUser;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("Active Account", style: AppTypography.titleLarge),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSpacing.gapMD,
                Text("Current Authenticated Session", style: AppTypography.bodyRegular.copyWith(color: AppColors.textMuted)),
                AppSpacing.gapMD,
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            activeUser.name.isNotEmpty
                                ? activeUser.name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
                                : 'U',
                            style: AppTypography.bodyLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      AppSpacing.hGapMD,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(activeUser.name, style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                            Text("${activeUser.role} • ${activeUser.employeeId}", style: AppTypography.caption),
                            if (activeUser.officeEmail != null && activeUser.officeEmail!.isNotEmpty)
                              Text(activeUser.officeEmail!, style: AppTypography.overline.copyWith(color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const StatusChip(
                        label: "Active",
                        type: StatusType.success,
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapLG,
                Text("Enterprise Multi-Tenant Identity", style: AppTypography.titleMedium),
                const SizedBox(height: 4),
                Text(
                  "JOY PeopleHR is bound to your secure enterprise identity. To sign into another organization or role, please log out and authenticate.",
                  style: AppTypography.caption,
                ),
                AppSpacing.gapXL,
                AppButton(
                  label: "Sign Out of Account",
                  icon: CupertinoIcons.square_arrow_right,
                  variant: AppButtonVariant.secondaryPill,
                  isFullWidth: true,
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    UserService.instance.clearUser();
                    if (context.mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
