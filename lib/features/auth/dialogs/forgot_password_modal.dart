import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../repositories/supabase/supabase_auth_repository.dart';
import '../../../widgets/core/app_button.dart';

void showForgotPasswordModal(BuildContext context, {String? initialEmail}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ForgotPasswordModal(initialEmail: initialEmail),
  );
}

class ForgotPasswordModal extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordModal({super.key, this.initialEmail});

  @override
  State<ForgotPasswordModal> createState() => _ForgotPasswordModalState();
}

class _ForgotPasswordModalState extends State<ForgotPasswordModal> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submitReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _statusMessage = "Please enter a valid work email address.";
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final success = await SupabaseAuthRepository().resetPasswordForEmail(email);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (success) {
          _isSuccess = true;
          _statusMessage =
              "Password reset instructions sent to $email. Please check your inbox.";
        } else {
          _isSuccess = false;
          _statusMessage = "Failed to send reset link. Please verify your email.";
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomInset + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Reset Password", style: AppTypography.titleLarge),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.slateBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.xmark, size: 16, color: AppColors.slateFg),
                ),
              ),
            ],
          ),
          AppSpacing.gapSM,
          Text(
            "Enter your registered corporate email address to receive a secure Supabase Auth recovery link.",
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          AppSpacing.gapLG,

          if (_statusMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isSuccess ? AppColors.mintBg : AppColors.roseBg,
                borderRadius: AppRadius.borderMd,
              ),
              child: Row(
                children: [
                  Icon(
                    _isSuccess
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.exclamationmark_triangle_fill,
                    color: _isSuccess ? AppColors.mintFg : AppColors.roseFg,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: AppTypography.caption.copyWith(
                        color: _isSuccess ? AppColors.mintFg : AppColors.roseFg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.gapMD,
          ],

          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: "Work Email",
              hintText: "employee@company.com",
              prefixIcon: const Icon(CupertinoIcons.mail, size: 20),
              border: OutlineInputBorder(borderRadius: AppRadius.borderMd),
            ),
          ),
          AppSpacing.gapLG,

          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: _isLoading ? "Sending..." : "Send Reset Link",
              variant: AppButtonVariant.primaryPill,
              icon: CupertinoIcons.paperplane_fill,
              onPressed: _isLoading ? null : _submitReset,
            ),
          ),
        ],
      ),
    );
  }
}
