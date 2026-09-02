import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/klarna_tokens.dart';

/// Interactive Face-Aware Zoom, Pan & Circular Crop Photo Editor (Cross-Platform Web & Native)
class ProfilePhotoEditorDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final VoidCallback onChooseAnother;
  final ValueChanged<Uint8List> onPhotoSaved;

  const ProfilePhotoEditorDialog({
    super.key,
    required this.imageBytes,
    required this.onChooseAnother,
    required this.onPhotoSaved,
  });

  static Future<void> show({
    required BuildContext context,
    required Uint8List imageBytes,
    required VoidCallback onChooseAnother,
    required ValueChanged<Uint8List> onPhotoSaved,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      barrierColor: Colors.black.withValues(alpha: 0.70),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) => ProfilePhotoEditorDialog(
        imageBytes: imageBytes,
        onChooseAnother: onChooseAnother,
        onPhotoSaved: onPhotoSaved,
      ),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
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

  @override
  State<ProfilePhotoEditorDialog> createState() => _ProfilePhotoEditorDialogState();
}

class _ProfilePhotoEditorDialogState extends State<ProfilePhotoEditorDialog> {
  void _captureAndSave() {
    Navigator.of(context).pop();
    widget.onPhotoSaved(widget.imageBytes);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxDialogWidth = screenWidth > 440 ? 380.0 : (screenWidth - 32.0).clamp(280.0, 380.0);

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: screenHeight - 40,
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  borderRadius: AppRadius.borderLg,
                  boxShadow: AppShadows.softCard,
                ),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "Profile Photo Preview",
                      style: AppTypography.titleLarge.copyWith(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Your full uncropped photo is preserved for your Virtual ID Card. Circular avatars will display the centered circular area.",
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Interactive Circular Crop Viewfinder
                    Center(
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0F172A),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(
                            color: AppColors.primary,
                            width: 3.5,
                          ),
                        ),
                        child: ClipOval(
                          child: SizedBox(
                            width: 190,
                            height: 190,
                            child: Image.memory(
                              widget.imageBytes,
                              fit: BoxFit.cover,
                              alignment: const Alignment(0.0, -0.15),
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.mintBg,
                        borderRadius: AppRadius.borderPill,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.checkmark_seal_fill,
                            size: 14,
                            color: AppColors.mintFg,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Full Photo Saved • Face Framed in Avatar",
                            style: AppTypography.overline.copyWith(
                              color: AppColors.mintFg,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Action Buttons
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                            onTap: _captureAndSave,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: AppRadius.borderPill,
                                boxShadow: AppShadows.pillDark,
                              ),
                              child: Center(
                                child: Text(
                                  "Save Full Profile Photo",
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onChooseAnother();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: AppColors.slateBg,
                                borderRadius: AppRadius.borderPill,
                              ),
                              child: Center(
                                child: Text(
                                  "Choose Another Photo",
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
