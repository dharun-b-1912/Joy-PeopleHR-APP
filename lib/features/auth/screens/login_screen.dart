import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../widgets/core/app_button.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_text_field.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  final AuthController? controller;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
    this.controller,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthController _authController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _authController = widget.controller ?? AuthController();
    _authController.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _authController.removeListener(_onControllerChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleLoginSubmit() async {
    if (_authController.isLoading) return;
    FocusScope.of(context).unfocus();
    final success = await _authController.login(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (mounted && success) {
      widget.onLoginSuccess();
    }
  }

  void _navigateToForgotPassword() {
    _authController.clearError();
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ForgotPasswordScreen(
          authController: _authController,
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _authController;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Branding & Header
                  const AuthHeader(
                    title: "Welcome back",
                    subtitle: "Sign in to access your workspace",
                  ),
                  AppSpacing.gapXXL,

                  // Error Banner
                  if (controller.errorMessage != null) ...[
                    AuthErrorBanner(errorMessage: controller.errorMessage!),
                    AppSpacing.gapMD,
                  ],

                  // Work Email Input Field
                  AuthTextField(
                    label: "Work Email",
                    hintText: "Enter your work email",
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: CupertinoIcons.mail,
                    textInputAction: TextInputAction.next,
                  ),
                  AppSpacing.gapMD,

                  // Password Input Field
                  AuthTextField(
                    label: "Password",
                    hintText: "Enter your password",
                    controller: _passwordController,
                    isPassword: true,
                    prefixIcon: CupertinoIcons.lock,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleLoginSubmit(),
                  ),

                  // Forgot Password Text Link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: controller.isLoading ? null : _navigateToForgotPassword,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        "Forgot password?",
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),

                  AppSpacing.gapLG,

                  // Sign In Primary Button
                  SizedBox(
                    height: 50,
                    child: AppButton(
                      label: controller.isLoading ? "Signing in..." : "Sign In",
                      variant: AppButtonVariant.primaryPill,
                      icon: CupertinoIcons.arrow_right,
                      onPressed: controller.isLoading ? null : _handleLoginSubmit,
                    ),
                  ),

                  AppSpacing.gapXXL,

                  // Security Microcopy Footer
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.lock_shield,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(width: 6),
                      Text(
                        "Secure employee access",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
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
    );
  }
}
