import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../repositories/supabase/supabase_auth_repository.dart';
import '../../../widgets/core/app_button.dart';

Future<bool?> showVerifyPasswordModal(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const VerifyPasswordModal(),
  );
}

class VerifyPasswordModal extends StatefulWidget {
  const VerifyPasswordModal({super.key});

  @override
  State<VerifyPasswordModal> createState() => _VerifyPasswordModalState();
}

class _VerifyPasswordModalState extends State<VerifyPasswordModal> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() {
        _errorMessage = "Please enter your current account password.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isValid = await SupabaseAuthRepository().verifyPassword(password);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (isValid) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _errorMessage = "Authentication failed. Incorrect password.";
        });
      }
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
              Text("Verify Password", style: AppTypography.titleLarge),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
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
            "Re-authenticate your Supabase Auth credentials to view unmasked sensitive statutory & bank account details.",
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          AppSpacing.gapLG,

          if (_errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.roseBg,
                borderRadius: AppRadius.borderMd,
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: AppColors.roseFg,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.roseFg,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.gapMD,
          ],

          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: "Account Password",
              prefixIcon: const Icon(CupertinoIcons.lock_shield, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: OutlineInputBorder(borderRadius: AppRadius.borderMd),
            ),
          ),
          AppSpacing.gapLG,

          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: _isLoading ? "Verifying..." : "Authenticate & Unmask Details",
              variant: AppButtonVariant.primaryPill,
              icon: CupertinoIcons.lock_open_fill,
              onPressed: _isLoading ? null : _verify,
            ),
          ),
        ],
      ),
    );
  }
}
