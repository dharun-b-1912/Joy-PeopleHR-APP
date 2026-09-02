import 'package:flutter/material.dart';
import '../../core/theme/klarna_tokens.dart';

enum StatusType { success, warning, error, info, neutral, purple }

/// Universal Klarna-style Status Pill Badge (Icon/Dot + Label + Soft Pastel Background)
class StatusChip extends StatelessWidget {
  final String label;
  final StatusType type;
  final IconData? icon;
  final Color? customBg;
  final Color? customFg;

  const StatusChip({
    super.key,
    required this.label,
    this.type = StatusType.neutral,
    this.icon,
    this.customBg,
    this.customFg,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;

    if (customBg != null && customFg != null) {
      bg = customBg!;
      fg = customFg!;
    } else {
      switch (type) {
        case StatusType.success:
          bg = AppColors.mintBg;
          fg = AppColors.mintFg;
          break;
        case StatusType.warning:
          bg = const Color(0xFFFEF3C7);
          fg = const Color(0xFFD97706);
          break;
        case StatusType.error:
          bg = AppColors.roseBg;
          fg = AppColors.roseFg;
          break;
        case StatusType.info:
          bg = AppColors.skyBg;
          fg = AppColors.skyFg;
          break;
        case StatusType.purple:
          bg = AppColors.lavenderBg;
          fg = AppColors.lavenderFg;
          break;
        case StatusType.neutral:
          bg = AppColors.slateBg;
          fg = AppColors.slateFg;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.borderPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10.5, color: fg),
            const SizedBox(width: 3.5),
          ] else ...[
            Container(
              width: 4.5,
              height: 4.5,
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 3.5),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: fg,
                fontSize: 10.5,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
