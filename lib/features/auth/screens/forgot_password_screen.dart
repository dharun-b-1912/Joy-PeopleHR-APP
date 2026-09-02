import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../widgets/core/app_button.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final AuthController authController;
  final String? initialEmail;

  const ForgotPasswordScreen({
    super.key,
    required this.authController,
    this.initialEmail,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController;
  bool _isSuccess = false;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    widget.authController.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onControllerChanged);
    _emailController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleResetSubmit() async {
    widget.authController.clearError();
    final success = await widget.authController.sendPasswordReset(_emailController.text);
    if (mounted && success) {
      setState(() {
        _isSuccess = true;
        _successMessage =
            "Reset instructions sent to ${_emailController.text.trim()}. Please check your email inbox.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.authController;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Branding & Header
                  const AuthHeader(
                    title: "Reset Password",
                    subtitle: "Enter your work email to receive a secure recovery link.",
                  ),
                  AppSpacing.gapXXL,

                  // Error / Success Banner
                  if (controller.errorMessage != null) ...[
                    AuthErrorBanner(errorMessage: controller.errorMessage!),
                    AppSpacing.gapMD,
                  ],

                  if (_isSuccess && _successMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.mintBg,
                        borderRadius: AppRadius.borderMd,
                        border: Border.all(color: AppColors.mintFg.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: AppColors.mintFg,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.mintFg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapMD,
                  ],

                  // Work Email Input Field
                  AuthTextField(
                    label: "Work Email",
                    hintText: "Enter your work email",
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: CupertinoIcons.mail,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleResetSubmit(),
                  ),
                  AppSpacing.gapLG,

                  // Send Reset Link Primary Button
                  SizedBox(
                    height: 50,
                    child: AppButton(
                      label: controller.isLoading ? "Sending..." : "Send Reset Link",
                      variant: AppButtonVariant.primaryPill,
                      icon: CupertinoIcons.paperplane_fill,
                      onPressed: controller.isLoading ? null : _handleResetSubmit,
                    ),
                  ),

                  AppSpacing.gapXL,

                  // Back to Login Link
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(CupertinoIcons.arrow_left, size: 16, color: AppColors.primary),
                      label: Text(
                        "Back to Login",
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
