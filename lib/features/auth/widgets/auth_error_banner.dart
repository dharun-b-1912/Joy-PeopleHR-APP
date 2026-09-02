import 'package:flutter/cupertino.dart';
import '../../../core/theme/klarna_tokens.dart';

class AuthErrorBanner extends StatelessWidget {
  final String errorMessage;

  const AuthErrorBanner({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    if (errorMessage.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.roseBg,
        borderRadius: AppRadius.borderMd,
        border: Border.all(
          color: AppColors.roseFg.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: AppColors.roseFg,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorMessage,
              style: AppTypography.caption.copyWith(
                color: AppColors.roseFg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
