import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/workforce_request_modal.dart';

class GrievanceModal extends StatefulWidget {
  const GrievanceModal({super.key});

  @override
  State<GrievanceModal> createState() => _GrievanceModalState();
}

class _GrievanceModalState extends State<GrievanceModal> {
  final _subjectController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = "Facility & Workplace";
  String? _errorText;

  final List<String> _categories = const [
    "Facility & Workplace",
    "IT & Systems",
    "HR & Policy",
    "Safety & Security",
    "POSH Complaint",
  ];

  @override
  Widget build(BuildContext context) {
    return WorkForceOSRequestModal(
      title: "New Grievance",
      subtitle: "Tell us what you need help with.",
      primaryButtonLabel: "Submit Grievance",
      onPrimaryPressed: () async {
        final subject = _subjectController.text.trim();
        final desc = _descController.text.trim();
        if (subject.isEmpty) {
          setState(() => _errorText = "Please enter a subject for your grievance");
          return;
        }
        if (desc.isEmpty) {
          setState(() => _errorText = "Please provide a detailed description");
          return;
        }

        final nav = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);

        final success = await MoreModulesController.instance.submitComplaint(
          subject: subject,
          category: _selectedCategory,
          description: desc,
        );

        if (mounted) {
          nav.pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(success ? "Grievance submitted successfully!" : "We couldn't determine the recipient. Please contact HR admin."),
              backgroundColor: success ? AppColors.primary : AppColors.statusError,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Category", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.slateBg,
              borderRadius: AppRadius.borderMd,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                isExpanded: true,
                icon: const Icon(CupertinoIcons.chevron_down, size: 16, color: AppColors.textMuted),
                style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedCategory = val;
                      _errorText = null;
                    });
                  }
                },
              ),
            ),
          ),
          if (_selectedCategory == "POSH Complaint") ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.mintBg,
                borderRadius: AppRadius.borderMd,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(CupertinoIcons.lock_shield_fill, size: 18, color: AppColors.mintFg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Confidential Complaint",
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.mintFg),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "This complaint will be handled confidentially through your company's designated POSH process.",
                          style: AppTypography.caption.copyWith(color: AppColors.mintFg.withValues(alpha: 0.9), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          AppSpacing.gapMD,
          Text("Subject", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _subjectController,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            style: AppTypography.bodyRegular,
            decoration: InputDecoration(
              hintText: "Short summary of the issue...",
              hintStyle: AppTypography.bodyRegular.copyWith(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.slateBg,
              border: OutlineInputBorder(
                borderRadius: AppRadius.borderMd,
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          AppSpacing.gapMD,
          Text("Detailed Description", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            maxLines: 3,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            style: AppTypography.bodyRegular,
            decoration: InputDecoration(
              hintText: "Explain the issue in detail...",
              hintStyle: AppTypography.bodyRegular.copyWith(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.slateBg,
              border: OutlineInputBorder(
                borderRadius: AppRadius.borderMd,
                borderSide: BorderSide.none,
              ),
              errorText: _errorText,
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }
}
