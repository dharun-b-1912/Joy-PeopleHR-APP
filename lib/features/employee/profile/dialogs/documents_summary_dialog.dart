import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../core/utils/secure_log.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/core/status_chip.dart';

class DocumentsSummaryDialog extends StatefulWidget {
  const DocumentsSummaryDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DocumentsSummaryDialog(),
    );
  }

  @override
  State<DocumentsSummaryDialog> createState() => _DocumentsSummaryDialogState();
}

class _DocumentsSummaryDialogState extends State<DocumentsSummaryDialog> {
  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRealDocuments();
  }

  Future<void> _fetchRealDocuments() async {
    final user = UserService.instance.currentUser;
    final empId = user.dataId;
    if (empId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('employee_documents')
          .select()
          .eq('employee_id', empId)
          .order('uploaded_at', ascending: false);

      if (mounted) {
        setState(() {
          _documents = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      secureLog('[DocumentsDialog] Error fetching documents: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.mintBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.folder_fill, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Official Documents",
                      style: AppTypography.titleLarge.copyWith(fontSize: 18),
                    ),
                    Text(
                      "Authenticated, tenant-isolated employee records.",
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            )
          else if (_documents.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.slateBg,
                borderRadius: AppRadius.borderMd,
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                children: [
                  const Icon(CupertinoIcons.doc_text, size: 28, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  Text(
                    "No documents on record",
                    style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "No verified or signed documents have been uploaded to your profile yet.",
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._documents.map((d) {
              final title = d['document_name'] ?? d['title'] ?? d['file_name'] ?? 'Official Document';
              final category = d['document_type'] ?? d['category'] ?? 'General';
              final status = (d['verification_status'] ?? d['status'] ?? 'UPLOADED').toString().toUpperCase();
              final isVerified = status == 'VERIFIED' || status == 'APPROVED';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.slateBg,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.mintBg,
                        borderRadius: AppRadius.borderSquircle,
                      ),
                      child: const Icon(CupertinoIcons.doc_text_fill, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.toString(),
                            style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            category.toString(),
                            style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(
                      label: status,
                      type: isVerified ? StatusType.success : StatusType.info,
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 16),
          AppButton(
            label: "Close",
            variant: AppButtonVariant.secondaryPill,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
