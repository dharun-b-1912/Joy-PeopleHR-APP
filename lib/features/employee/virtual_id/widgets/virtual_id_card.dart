import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/hrms_models.dart';
import '../../../../widgets/core/avatar_image_helper.dart';
import '../../../../widgets/core/status_chip.dart';

class VirtualIdCard extends StatelessWidget {
  final UserModel user;

  const VirtualIdCard({super.key, required this.user});

  String get _userInitials {
    final name = user.name.trim();
    if (name.isEmpty) return "EM";
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final p1 = parts[0];
      final p2 = parts[1];
      final i1 = p1.isNotEmpty ? p1[0] : '';
      final i2 = p2.isNotEmpty ? p2[0] : '';
      if (i1.isNotEmpty || i2.isNotEmpty) {
        return "$i1$i2".toUpperCase();
      }
    }
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 520,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // 1. Full-Bleed Profile Photo Background Hero
            Positioned.fill(
              child: buildAvatarHeroWidget(user.profileImage, _userInitials),
            ),

            // 2. Multi-Stop Gradient Overlay (Darkens top & bottom for legibility)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.60),
                      Colors.black.withValues(alpha: 0.10),
                      Colors.black.withValues(alpha: 0.75),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.35, 0.68, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Main Content Stack
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Floating Header: Working Company Logo/Badge + WORK ID
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: (user.companyLogoUrl != null && user.companyLogoUrl!.isNotEmpty)
                                  ? ClipOval(
                                      child: Image.network(
                                        user.companyLogoUrl!,
                                        cacheWidth: 120,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Center(
                                          child: Icon(
                                            CupertinoIcons.building_2_fill,
                                            color: Colors.white,
                                            size: 15,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(
                                        CupertinoIcons.building_2_fill,
                                        color: Colors.white,
                                        size: 15,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (user.companyName?.isNotEmpty == true
                                        ? user.companyName!
                                        : (user.organizationName?.isNotEmpty == true ? user.organizationName! : 'ORGANIZATION'))
                                    .toUpperCase(),
                                softWrap: true,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const StatusChip(
                        label: "WORK ID",
                        type: StatusType.info,
                        icon: CupertinoIcons.checkmark_seal_fill,
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Bottom Identity Section (Layered over gradient)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 23,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        CupertinoIcons.checkmark_alt_circle_fill,
                        color: AppColors.mintFg,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.designation,
                    style: AppTypography.bodyRegular.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.employeeId.isNotEmpty ? user.employeeId : "—",
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primaryAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      fontSize: 12,
                    ),
                  ),

                  AppSpacing.gapSM,
                  const Divider(height: 1, color: Colors.white24),
                  AppSpacing.gapSM,

                  // Workplace Information Strip (Department • Campus)
                  Text(
                    "${user.department.isNotEmpty ? user.department.toUpperCase() : '—'}  •  ${user.campus.isNotEmpty ? user.campus.toUpperCase() : '—'}",
                    style: AppTypography.overline.copyWith(
                      color: Colors.white70,
                      letterSpacing: 0.8,
                      fontSize: 10,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Active Employee Status Chip
                  const StatusChip(
                    label: "Active Employee",
                    type: StatusType.success,
                    icon: CupertinoIcons.circle_fill,
                  ),

                  const SizedBox(height: 6),

                  // Working Company Name below Active Employee Status
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.building_2_fill,
                        size: 13,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          user.companyName?.isNotEmpty == true
                              ? user.companyName!
                              : (user.organizationName?.isNotEmpty == true ? user.organizationName! : '—'),
                          style: AppTypography.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  AppSpacing.gapMD,

                  // Footer
                  Center(
                    child: Text(
                      "Official Verified Employee Credential",
                      style: AppTypography.overline.copyWith(
                        color: Colors.white54,
                        fontSize: 9,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
