import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/theme/klarna_tokens.dart';
import 'core/app_button.dart';

/// Standardized Klarna-style Centered Modal Shell for Employee Requests
class WorkForceOSRequestModal extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final String primaryButtonLabel;
  final IconData primaryButtonIcon;
  final VoidCallback onPrimaryPressed;
  final bool isSubmitting;

  const WorkForceOSRequestModal({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.primaryButtonLabel,
    this.primaryButtonIcon = CupertinoIcons.arrow_right,
    required this.onPrimaryPressed,
    this.isSubmitting = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxModalWidth = screenWidth > 480 ? 440.0 : (screenWidth - 32.0).clamp(280.0, 440.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxModalWidth),

          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.borderLg,
            boxShadow: AppShadows.softCard,
          ),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header & Soft Circular Close Button Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTypography.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.slateBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),

                AppSpacing.gapLG,

                // Feature Content
                child,

                AppSpacing.gapXL,

                // Primary CTA Action Button
                AppButton(
                  label: primaryButtonLabel,
                  icon: primaryButtonIcon,
                  isFullWidth: true,
                  isLoading: isSubmitting,
                  variant: AppButtonVariant.primaryPill,
                  onPressed: onPrimaryPressed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper function to launch any WorkForceOS Request Modal with scale/fade transition
Future<T?> showWorkForceRequestModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: "Dismiss",
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim1, anim2) => builder(ctx),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(
          CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(
          opacity: anim1,
          child: child,
        ),
      );
    },
  );
}

typedef JoyPeopleHRRequestModal = WorkForceOSRequestModal;
const showJoyPeopleHRRequestModal = showWorkForceRequestModal;
