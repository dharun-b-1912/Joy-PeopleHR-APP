import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/workforce_request_modal.dart';

class ExpenseClaimModal extends StatefulWidget {
  const ExpenseClaimModal({super.key});

  @override
  State<ExpenseClaimModal> createState() => _ExpenseClaimModalState();
}

class _ExpenseClaimModalState extends State<ExpenseClaimModal> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = "Travel & Meals";
  String? _errorText;

  Uint8List? _receiptBytes;
  String? _receiptFileName;
  int? _receiptSizeBytes;
  bool _isSubmitting = false;

  final List<String> _categories = const [
    "Travel & Meals",
    "Lodging & Accommodation",
    "Client Entertainment",
    "IT Hardware & Tools",
    "Office Supplies",
    "Fuel & Transport",
    "Others",
  ];

  Future<void> _pickReceipt() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'webp'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _receiptBytes = file.bytes;
            _receiptFileName = file.name;
            _receiptSizeBytes = file.size;
            _errorText = null;
          });
        }
      }
    } catch (e) {
      setState(() => _errorText = "Failed to select receipt: $e");
    }
  }

  void _clearReceipt() {
    setState(() {
      _receiptBytes = null;
      _receiptFileName = null;
      _receiptSizeBytes = null;
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (title.isEmpty) {
      setState(() => _errorText = "Please enter an expense title / purpose");
      return;
    }
    if (amount <= 0) {
      setState(() => _errorText = "Please enter a valid expense amount (> ₹0)");
      return;
    }

    setState(() => _isSubmitting = true);

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final success = await MoreModulesController.instance.submitExpenseClaim(
      title: title,
      category: _selectedCategory,
      amount: amount,
      description: _descController.text.trim(),
      receiptBytes: _receiptBytes,
      receiptFileName: _receiptFileName,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            success
                ? "✓ Expense claim submitted with proof (Pending Review)"
                : "Submission failed. Please try again.",
          ),
          backgroundColor: success ? AppColors.primary : AppColors.statusError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkForceOSRequestModal(
      title: "New Expense Claim",
      subtitle: "Submit an expense reimbursement request.",
      primaryButtonLabel: _isSubmitting ? "Submitting..." : "Submit Expense Claim",
      onPrimaryPressed: _handleSubmit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Expense Category", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
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
          AppSpacing.gapMD,
          Text("Title / Purpose", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            style: AppTypography.bodyRegular,
            decoration: InputDecoration(
              hintText: "e.g., Client lunch at Bangalore Tech Park",
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
          Text("Amount (₹)", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixText: "₹ ",
              prefixStyle: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
              hintText: "0.00",
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
          Text("Bill / Receipt Proof (Photo / PDF)", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (_receiptFileName == null) ...[
            InkWell(
              onTap: _pickReceipt,
              borderRadius: AppRadius.borderMd,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.slateBg,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: AppColors.borderSubtle, style: BorderStyle.solid),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.camera, size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      "Upload Bill / Receipt Photo",
                      style: AppTypography.bodyRegular.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.mintBg,
                borderRadius: AppRadius.borderMd,
                border: Border.all(color: AppColors.mintFg.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.checkmark_seal_fill, size: 20, color: AppColors.mintFg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _receiptFileName!,
                          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_receiptSizeBytes != null)
                          Text(
                            _formatSize(_receiptSizeBytes!),
                            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: AppColors.textMuted),
                    onPressed: _clearReceipt,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
          AppSpacing.gapMD,
          Text("Notes / Details (Optional)", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            maxLines: 2,
            style: AppTypography.bodyRegular,
            decoration: InputDecoration(
              hintText: "Add any additional details or merchant reference...",
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
