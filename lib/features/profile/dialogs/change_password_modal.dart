import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/klarna_tokens.dart';
import '../../../repositories/supabase/supabase_auth_repository.dart';
import '../../../widgets/core/app_button.dart';

void showChangePasswordModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const ChangePasswordModal(),
  );
}

class ChangePasswordModal extends StatefulWidget {
  const ChangePasswordModal({super.key});

  @override
  State<ChangePasswordModal> createState() => _ChangePasswordModalState();
}

class _ChangePasswordModalState extends State<ChangePasswordModal> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitChangePassword() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty) {
      setState(() {
        _statusMessage = "Please enter your current password.";
        _isSuccess = false;
      });
      return;
    }

    if (newPassword.length < 8) {
      setState(() {
        _statusMessage = "New password must be at least 8 characters long.";
        _isSuccess = false;
      });
      return;
    }

    if (newPassword == currentPassword) {
      setState(() {
        _statusMessage = "New password must be different from your current password.";
        _isSuccess = false;
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _statusMessage = "New password and confirm password do not match.";
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final success = await SupabaseAuthRepository().changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (success) {
          _isSuccess = true;
          _statusMessage =
              "Password changed successfully! Signing you out for security...";
        } else {
          _isSuccess = false;
          _statusMessage =
              "Current password is incorrect. Please try again.";
        }
      });

      // On success: close dialog, then sign out and redirect to login
      if (success && mounted) {
        Timer(const Duration(seconds: 2), () async {
          if (!mounted) return;
          Navigator.of(context).pop(); // Close the modal
          // Sign out to force re-authentication with new password
          await SupabaseAuthRepository().signOut();
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Change Password", style: AppTypography.titleLarge),
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
              "Choose a strong password. Your new password will be required on next login.",
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

            // Current Password
            TextField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrent,
              decoration: InputDecoration(
                labelText: "Current Password",
                prefixIcon: const Icon(CupertinoIcons.lock, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurrent ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 20),
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
                border: OutlineInputBorder(borderRadius: AppRadius.borderMd),
              ),
            ),
            AppSpacing.gapMD,

            // New Password
            TextField(
              controller: _newPasswordController,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: "New Password",
                prefixIcon: const Icon(CupertinoIcons.lock_shield, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 20),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
                border: OutlineInputBorder(borderRadius: AppRadius.borderMd),
              ),
            ),
            AppSpacing.gapMD,

            // Confirm New Password
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: "Confirm New Password",
                prefixIcon: const Icon(CupertinoIcons.lock_shield_fill, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 20),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                border: OutlineInputBorder(borderRadius: AppRadius.borderMd),
              ),
            ),
            AppSpacing.gapLG,

            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: _isLoading ? "Updating..." : "Update Password",
                variant: AppButtonVariant.primaryPill,
                icon: CupertinoIcons.checkmark_shield_fill,
                onPressed: _isLoading ? null : _submitChangePassword,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
