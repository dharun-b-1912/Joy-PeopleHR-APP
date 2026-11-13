import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/core/app_button.dart';
import '../controllers/auth_controller.dart';
import '../models/multi_method_auth_models.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/otp_pin_field.dart';
import 'company_selection_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  final AuthController? controller;

  const LoginScreen({
    super.key,
    this.onLoginSuccess,
    this.controller,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthController _authController;
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _showingMethodSelection = true;
  String _countryCode = '+91';

  static const _countryCodes = ['+91', '+971', '+65', '+44', '+1'];

  @override
  void initState() {
    super.initState();
    _authController = widget.controller ?? AuthController();
    _authController.addListener(_onControllerChanged);
    _authController.loadLoginConfig();
  }

  @override
  void dispose() {
    _authController.removeListener(_onControllerChanged);
    if (widget.controller == null) {
      _authController.dispose();
    }
    _identifierController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _chooseMethod(LoginMethod method) {
    _authController.selectLoginMethod(method);
    _identifierController.clear();
    _passwordController.clear();
    _otpController.clear();
    unawaited(_authController.warmUpGateway());
    setState(() {
      _showingMethodSelection = false;
    });
  }

  void _backToMethods() {
    _authController.clearError();
    _authController.resetOtpFlow();
    _passwordController.clear();
    _otpController.clear();
    setState(() {
      _showingMethodSelection = true;
    });
  }

  Future<void> _handleSubmit() async {
    if (_authController.isLoading) return;
    final method = _authController.selectedMethod;

    bool ok = false;
    if (method == LoginMethod.mobileOtp) {
      if (_authController.otpChallengeId == null) {
        await _authController.requestMobileOtp(
          mobile: _identifierController.text,
          countryCode: _countryCode,
        );
        return;
      }
      ok = await _authController.verifyMobileOtp(otp: _otpController.text);
    } else {
      ok = await _authController.loginWithMethod(
        method: method,
        identifier: _identifierController.text,
        password: _passwordController.text,
        countryCode: _countryCode,
      );
    }

    if (ok && mounted) {
      widget.onLoginSuccess?.call();
    }
  }

  void _openForgotPassword() {
    _authController.clearError();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(authController: _authController),
      ),
    );
  }

  IconData _methodIcon(LoginMethod m) {
    switch (m) {
      case LoginMethod.employeeIdPassword:
        return CupertinoIcons.person_crop_rectangle_fill;
      case LoginMethod.mobilePassword:
        return CupertinoIcons.device_phone_portrait;
      case LoginMethod.mobileOtp:
        return CupertinoIcons.chat_bubble_text_fill;
      case LoginMethod.emailPassword:
        return CupertinoIcons.mail_solid;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthHeader(
                    title: 'Employee & Workforce Login',
                    subtitle: 'Sign in to your workspace',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWhite,
                      borderRadius: AppRadius.borderLg,
                      border: Border.all(color: AppColors.borderLight),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildWorkspaceBanner(),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 230),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0.04, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slide,
                                  child: child,
                                ),
                              );
                            },
                            child: _authController.requiresCompanySelection
                                ? KeyedSubtree(
                                    key: const ValueKey('step_company_select'),
                                    child: CompanySelectionScreen(
                                      companies: _authController.companies,
                                      isLoading: _authController.isLoading,
                                      errorMessage: _authController.errorMessage,
                                      onCancel: _authController.cancelCompanySelection,
                                      onSelectCompany: (orgId) async {
                                        final ok = await _authController
                                            .confirmCompanySelection(orgId);
                                        if (ok && mounted) {
                                          widget.onLoginSuccess?.call();
                                        }
                                      },
                                    ),
                                  )
                                : _showingMethodSelection
                                    ? KeyedSubtree(
                                        key: const ValueKey('step_method_select'),
                                        child: _buildMethodSelectionStep(),
                                      )
                                    : KeyedSubtree(
                                        key: ValueKey(
                                          'step_credentials_${_authController.selectedMethod.apiValue}',
                                        ),
                                        child: _buildCredentialsStep(),
                                      ),
                          ),
                        ],
                      ),
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

  Widget _buildWorkspaceBanner() {
    // Multi-tenant SaaS: before login, only show an explicit organization name if scoped;
    // never show a specific tenant company until authentication succeeds.
    final displayTitle = _authController.loginConfig.organizationName;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: displayTitle == null || displayTitle.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey('workspace_banner_$displayTitle'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.mintBg.withValues(alpha: 0.55),
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.apartment_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayTitle,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMethodSelectionStep() {
    final cfg = _authController.loginConfig;
    final methods = cfg.enabledMethods;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select your login method',
          style: AppTypography.titleLarge.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose how you would like to sign in to your employee account.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_authController.isLoadingConfig)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ...methods.map((method) {
            final isRecommended = cfg.factoryRecommendedMethod == method;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                key: ValueKey('method_card_${method.apiValue}'),
                onTap: () => _chooseMethod(method),
                borderRadius: AppRadius.borderMd,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceWhite,
                    borderRadius: AppRadius.borderMd,
                    border: Border.all(
                      color: isRecommended
                          ? AppColors.primary.withValues(alpha: 0.45)
                          : AppColors.borderLight,
                      width: isRecommended ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.mintBg,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          _methodIcon(method),
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              method.title,
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (isRecommended) ...[
                              const SizedBox(height: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.mintBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Recommended for factory & site workers',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.mintFg,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 3),
                            Text(
                              method.subtitle,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              'Single identity account',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            TextButton(
              onPressed: _openForgotPassword,
              child: const Text('Need help?'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCredentialsStep() {
    final method = _authController.selectedMethod;
    final hasError = _authController.errorMessage != null;
    final isOtpSent =
        method == LoginMethod.mobileOtp && _authController.otpChallengeId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            TextButton.icon(
              onPressed: _authController.isLoading ? null : _backToMethods,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Change Login Method'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: AppColors.primary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.mintBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                method.title,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: AppColors.mintFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hasError) ...[
          AuthErrorBanner(errorMessage: _authController.errorMessage!),
          if (_authController.errorCode == 'DUPLICATE_PHONE')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _chooseMethod(LoginMethod.employeeIdPassword),
                child: const Text('Switch to Employee ID + Password'),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],

        if (method == LoginMethod.employeeIdPassword)
          AuthTextField(
            label: 'Employee ID / Worker Code',
            hintText: 'e.g. EMP-101',
            controller: _identifierController,
            prefixIcon: CupertinoIcons.person_badge_plus,
            onChanged: (_) => _authController.clearError(),
          )
        else if (method == LoginMethod.emailPassword)
          AuthTextField(
            label: 'Registered Email Address',
            hintText: 'name@company.com',
            controller: _identifierController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: CupertinoIcons.mail,
            onChanged: (_) => _authController.clearError(),
          )
        else if (!(method == LoginMethod.mobileOtp && isOtpSent))
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Code',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _countryCode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.borderMd,
                        ),
                      ),
                      items: _countryCodes
                          .map(
                            (code) => DropdownMenuItem(
                              value: code,
                              child: Text(code),
                            ),
                          )
                          .toList(),
                      onChanged: isOtpSent
                          ? null
                          : (val) {
                              if (val != null) setState(() => _countryCode = val);
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AuthTextField(
                  label: 'Registered Mobile Number',
                  hintText: '98765 43210',
                  controller: _identifierController,
                  enabled: !isOtpSent,
                  keyboardType: TextInputType.phone,
                  prefixIcon: CupertinoIcons.phone,
                  textInputAction: method == LoginMethod.mobileOtp
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onSubmitted: method == LoginMethod.mobileOtp
                      ? (_) => _handleSubmit()
                      : null,
                  onChanged: (_) => _authController.clearError(),
                ),
              ),
            ],
          ),

        if (!(method == LoginMethod.mobileOtp && isOtpSent))
          const SizedBox(height: AppSpacing.md),

        if (method != LoginMethod.mobileOtp) ...[
          AuthTextField(
            label: 'Password',
            hintText: 'Enter your password',
            controller: _passwordController,
            isPassword: true,
            prefixIcon: CupertinoIcons.lock,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleSubmit(),
            onChanged: (_) => _authController.clearError(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _authController.isLoading ? null : _openForgotPassword,
              child: const Text('Forgot Password?'),
            ),
          ),
        ] else if (isOtpSent) ...[
          Center(
            child: Column(
              children: [
                Text(
                  'OTP Verification',
                  style: AppTypography.titleLarge.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'We have sent a verification code to',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      _authController.otpMaskedDestination ?? 'your mobile',
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _otpController.clear();
                        _authController.resetOtpFlow();
                      },
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                      ),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                OtpPinField(
                  controller: _otpController,
                  enabled: !_authController.isLoading,
                  hasError: hasError &&
                      (_authController.errorCode == 'OTP_INVALID' ||
                          _authController.errorCode == 'OTP_MAX_ATTEMPTS'),
                  onChanged: (_) => _authController.clearError(),
                  onCompleted: (_) => _handleSubmit(),
                ),
                const SizedBox(height: 10),
                Text(
                  !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                      ? 'Waiting to auto-detect SMS · or type 6 digits above'
                      : 'Enter or paste your 6-digit SMS code',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 12),
                if (_authController.otpCooldownSeconds > 0)
                  Text(
                    'Resend OTP in ${_authController.otpCooldownSeconds}s',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  Column(
                    children: [
                      Text(
                        'Resend OTP via',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _authController.isLoading
                            ? null
                            : () => _authController.requestMobileOtp(
                                  mobile: _identifierController.text,
                                  countryCode: _countryCode,
                                ),
                        icon: const Icon(
                          Icons.sms_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          'SMS',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 10,
                          ),
                          side: const BorderSide(
                            color: Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        SizedBox(
          width: double.infinity,
          height: 50,
          child: AppButton(
            label: _authController.isLoading
                ? (method == LoginMethod.mobileOtp && !isOtpSent
                    ? 'Sending OTP...'
                    : 'Verifying...')
                : (method == LoginMethod.mobileOtp
                    ? (isOtpSent ? 'Verify & Sign In' : 'Send Login OTP')
                    : 'Sign In'),
            variant: AppButtonVariant.primaryPill,
            icon: CupertinoIcons.arrow_right,
            onPressed: _authController.isLoading ? null : _handleSubmit,
          ),
        ),
      ],
    );
  }
}
