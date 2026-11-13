import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/core/app_button.dart';
import '../models/multi_method_auth_models.dart';
import '../widgets/auth_error_banner.dart';

class CompanySelectionScreen extends StatefulWidget {
  final List<CompanyMembershipOption> companies;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function(String organizationId) onSelectCompany;
  final VoidCallback onCancel;

  const CompanySelectionScreen({
    super.key,
    required this.companies,
    required this.isLoading,
    this.errorMessage,
    required this.onSelectCompany,
    required this.onCancel,
  });

  @override
  State<CompanySelectionScreen> createState() => _CompanySelectionScreenState();
}

class _CompanySelectionScreenState extends State<CompanySelectionScreen> {
  late String _selectedOrgId;

  @override
  void initState() {
    super.initState();
    final def = widget.companies.firstWhere(
      (c) => c.isDefault,
      orElse: () => widget.companies.first,
    );
    _selectedOrgId = def.organizationId;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.mintBg,
            borderRadius: AppRadius.borderMd,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Company Workspace',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.mintFg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your employee identity has access to ${widget.companies.length} active companies.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (widget.errorMessage != null) ...[
          AuthErrorBanner(errorMessage: widget.errorMessage!),
          const SizedBox(height: AppSpacing.md),
        ],
        ...widget.companies.map((company) {
          final isSelected = _selectedOrgId == company.organizationId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: widget.isLoading
                  ? null
                  : () => setState(() => _selectedOrgId = company.organizationId),
              borderRadius: AppRadius.borderMd,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.mintBg.withValues(alpha: 0.55)
                      : AppColors.surfaceWhite,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.borderLight,
                    width: isSelected ? 1.8 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.apartment_rounded,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company.companyName ?? company.organizationName,
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (company.companyName != null &&
                                  company.companyName != company.organizationName)
                                company.organizationName,
                              if (company.employeeCode != null &&
                                  company.employeeCode!.isNotEmpty)
                                'ID: ${company.employeeCode}',
                              company.roleCode.replaceAll('_', ' ').toUpperCase(),
                            ].join(' · '),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected ? AppColors.primary : AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: AppButton(
            label: widget.isLoading ? 'Switching...' : 'Continue to Workspace',
            variant: AppButtonVariant.primaryPill,
            onPressed: widget.isLoading
                ? null
                : () => widget.onSelectCompany(_selectedOrgId),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: widget.isLoading ? null : widget.onCancel,
          child: const Text('Back to Sign In'),
        ),
      ],
    );
  }
}
