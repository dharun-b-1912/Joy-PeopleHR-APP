import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/core/app_button.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final AuthController authController;

  const ForgotPasswordScreen({
    super.key,
    required this.authController,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifierController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _useMobileOtp = false;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onChanged);
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    final c = widget.authController;
    c.clearError();

    if (!_useMobileOtp) {
      final ok = await c.sendPasswordReset(_identifierController.text);
      if (ok && mounted) {
        setState(() => _isComplete = true);
      }
      return;
    }

    if (c.resetChallengeId == null) {
      await c.requestMobileResetOtp(mobile: _identifierController.text);
      return;
    }

    final ok = await c.verifyMobileResetOtp(
      otp: _otpController.text,
      newPassword: _newPasswordController.text,
    );
    if (ok && mounted) {
      setState(() => _isComplete = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.authController;
    final otpStage = _useMobileOtp && c.resetChallengeId != null;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthHeader(
                    title: 'Account Recovery',
                    subtitle: 'Reset your password via Email link or Mobile OTP',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWhite,
                      borderRadius: AppRadius.borderLg,
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: _isComplete
                        ? Column(
                            children: [
                              const Icon(
                                CupertinoIcons.check_mark_circled_solid,
                                color: AppColors.primary,
                                size: 54,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _useMobileOtp
                                    ? 'Password Updated'
                                    : 'Recovery Link Sent',
                                style: AppTypography.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _useMobileOtp
                                    ? 'You can now sign in with your new password.'
                                    : 'If an active account matches your details, password reset instructions have been sent.',
                                textAlign: TextAlign.center,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: AppButton(
                                  label: 'Back to Sign In',
                                  variant: AppButtonVariant.primaryPill,
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Email / Emp ID'),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Mobile OTP'),
                                  ),
                                ],
                                selected: {_useMobileOtp},
                                onSelectionChanged: (sel) {
                                  c.clearError();
                                  setState(() {
                                    _useMobileOtp = sel.first;
                                    _identifierController.clear();
                                    _otpController.clear();
                                    _newPasswordController.clear();
                                  });
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              if (c.errorMessage != null) ...[
                                AuthErrorBanner(errorMessage: c.errorMessage!),
                                const SizedBox(height: AppSpacing.md),
                              ],
                              if (!otpStage) ...[
                                AuthTextField(
                                  label: _useMobileOtp
                                      ? 'Registered Mobile Number'
                                      : 'Email Address or Employee ID',
                                  hintText: _useMobileOtp
                                      ? '98765 43210'
                                      : 'employee@company.com or EMP-101',
                                  controller: _identifierController,
                                  keyboardType: _useMobileOtp
                                      ? TextInputType.phone
                                      : TextInputType.emailAddress,
                                  prefixIcon: _useMobileOtp
                                      ? CupertinoIcons.phone
                                      : CupertinoIcons.mail,
                                  onChanged: (_) => c.clearError(),
                                ),
                              ] else ...[
                                Text(
                                  'Enter the 6-digit OTP sent to ${c.resetMaskedDestination ?? 'your mobile'}',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.mintFg,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                AuthTextField(
                                  label: '6-Digit OTP',
                                  hintText: '123456',
                                  controller: _otpController,
                                  keyboardType: TextInputType.number,
                                  prefixIcon: CupertinoIcons.number_square,
                                  onChanged: (_) => c.clearError(),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                AuthTextField(
                                  label: 'New Password',
                                  hintText: 'Minimum 8 characters',
                                  controller: _newPasswordController,
                                  isPassword: true,
                                  prefixIcon: CupertinoIcons.lock,
                                  onChanged: (_) => c.clearError(),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.lg),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: AppButton(
                                  label: c.isLoading
                                      ? 'Processing...'
                                      : (!_useMobileOtp
                                          ? 'Send Reset Link'
                                          : (otpStage
                                              ? 'Update Password'
                                              : 'Send Reset OTP')),
                                  variant: AppButtonVariant.primaryPill,
                                  onPressed: c.isLoading ? null : _submit,
                                ),
                              ),
                            ],
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
