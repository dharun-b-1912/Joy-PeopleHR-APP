import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';
import '../../../../widgets/workforce_request_modal.dart';
import '../dialogs/upload_document_modal.dart';
import 'document_viewer_screen.dart';

void showUploadDocumentModal(BuildContext context) {
  showWorkForceRequestModal(
    context: context,
    builder: (ctx) => const UploadDocumentModal(),
  );
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  @override
  void initState() {
    super.initState();
    MoreModulesController.instance.loadAllData();
  }

  Future<void> _handleDeleteDocument(BuildContext context, DocumentModel doc) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.peachBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(CupertinoIcons.trash_fill, color: AppColors.peachFg, size: 22),
            ),
            const SizedBox(width: 12),
            Text("Delete Document", style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Are you sure you want to delete '${doc.name}'? This will permanently remove the document from your profile and the database.",
          style: AppTypography.bodyRegular.copyWith(color: AppColors.textSecondary, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text("Cancel", style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.roseFg,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Delete Permanently", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await MoreModulesController.instance.deleteDocument(
        doc.id,
        storagePath: doc.storagePath,
        fileUrl: doc.fileUrl,
      );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ok ? "✓ '${doc.name}' deleted permanently." : "Failed to delete document. Please try again."),
            backgroundColor: ok ? AppColors.primary : AppColors.roseFg,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final docs = controller.documents;
        final companyDocs = docs.where((d) => d.category == DocumentCategory.company).toList();
        final personalDocs = docs.where((d) => d.category == DocumentCategory.personal).toList();

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("Documents", style: AppTypography.titleLarge),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.cloud_upload, color: AppColors.primary),
                onPressed: () => showUploadDocumentModal(context),
              ),
            ],
          ),
          body: controller.isLoading && docs.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => controller.loadAllData(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                    children: [
                      Text("Company Documents", style: AppTypography.titleMedium),
                    const SizedBox(height: 4),
                    Text("Official policy guides, handbooks & benefits info.", style: AppTypography.caption),
                    AppSpacing.gapMD,
                    if (companyDocs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text("No company policies published yet.", style: AppTypography.bodySmall),
                      )
                    else
                      ...companyDocs.map((item) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => DocumentViewerScreen(document: item)),
                              );
                            },
                            borderRadius: AppRadius.borderMd,
                            child: AppCard(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(
                                      color: AppColors.lavenderBg,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      CupertinoIcons.doc_text_fill,
                                      color: AppColors.lavenderFg,
                                      size: 20,
                                    ),
                                  ),
                                  AppSpacing.hGapMD,
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: AppTypography.titleMedium,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "${item.fileType} • ${item.fileSize}",
                                          style: AppTypography.caption,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 85),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: StatusChip(
                                            label: "Company",
                                            type: StatusType.info,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (context) => DocumentViewerScreen(document: item)),
                                            );
                                          },
                                          borderRadius: AppRadius.borderPill,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppColors.slateBg,
                                              borderRadius: AppRadius.borderPill,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(CupertinoIcons.eye_fill, size: 12, color: AppColors.primary),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "View",
                                                  style: AppTypography.caption.copyWith(
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    AppSpacing.gapLG,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "My Documents (${personalDocs.length})",
                                style: AppTypography.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Official verified employee files (Driving Licence, ID, Certificates).",
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.add, color: AppColors.primary, size: 20),
                          onPressed: () => showUploadDocumentModal(context),
                        ),
                      ],
                    ),
                    AppSpacing.gapMD,
                    if (personalDocs.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.slateBg.withValues(alpha: 0.5),
                          borderRadius: AppRadius.borderMd,
                        ),
                        child: Column(
                          children: [
                            const Icon(CupertinoIcons.doc_on_clipboard, size: 32, color: AppColors.textMuted),
                            AppSpacing.gapSM,
                            Text("No personal documents uploaded yet", style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text("Upload your identity proof or certificates safely.", style: AppTypography.caption, textAlign: TextAlign.center),
                            AppSpacing.gapMD,
                            AppButton(
                              label: "Upload Document",
                              icon: CupertinoIcons.cloud_upload,
                              variant: AppButtonVariant.secondaryPill,
                              onPressed: () => showUploadDocumentModal(context),
                            ),
                          ],
                        ),
                      )
                    else
                      ...personalDocs.map((item) {
                        final isVer = item.isVerified;
                        final isRej = item.isRejected;
                        final isPend = item.isPending;

                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => DocumentViewerScreen(document: item)),
                              );
                            },
                            borderRadius: AppRadius.borderMd,
                            child: AppCard(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: isVer
                                              ? AppColors.mintBg
                                              : isRej
                                                  ? AppColors.peachBg
                                                  : AppColors.lavenderBg,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isVer
                                              ? CupertinoIcons.checkmark_seal_fill
                                              : isRej
                                                  ? CupertinoIcons.exclamationmark_triangle_fill
                                                  : CupertinoIcons.doc_text_fill,
                                          color: isVer
                                              ? AppColors.mintFg
                                              : isRej
                                                  ? AppColors.peachFg
                                                  : AppColors.lavenderFg,
                                          size: 22,
                                        ),
                                      ),
                                      AppSpacing.hGapMD,
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              style: AppTypography.titleMedium,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              "${item.fileType} • ${item.fileSize}",
                                              style: AppTypography.caption,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          StatusChip(
                                            label: isVer
                                                ? "Verified"
                                                : isRej
                                                    ? "Rejected"
                                                    : isPend
                                                        ? "Review"
                                                        : "Personal",
                                            type: isVer
                                                ? StatusType.success
                                                : isRej
                                                    ? StatusType.error
                                                    : isPend
                                                        ? StatusType.warning
                                                        : StatusType.neutral,
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(builder: (context) => DocumentViewerScreen(document: item)),
                                                  );
                                                },
                                                borderRadius: AppRadius.borderPill,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.slateBg,
                                                    borderRadius: AppRadius.borderPill,
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(CupertinoIcons.eye_fill, size: 12, color: AppColors.primary),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        "View",
                                                        style: AppTypography.caption.copyWith(
                                                          color: AppColors.primary,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: PopupMenuButton<String>(
                                                  icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 16, color: AppColors.textMuted),
                                                  padding: EdgeInsets.zero,
                                                  splashRadius: 14,
                                                  tooltip: "Options",
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  onSelected: (value) {
                                                    if (value == 'delete') {
                                                      _handleDeleteDocument(context, item);
                                                    }
                                                  },
                                                  itemBuilder: (ctx) => [
                                                    PopupMenuItem<String>(
                                                      value: 'delete',
                                                      child: Row(
                                                        children: [
                                                          const Icon(CupertinoIcons.trash, size: 16, color: AppColors.roseFg),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            "Delete",
                                                            style: AppTypography.caption.copyWith(
                                                              color: AppColors.roseFg,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (isRej && item.rejectionReason != null && item.rejectionReason!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppColors.peachBg,
                                        borderRadius: AppRadius.borderSm,
                                      ),
                                      child: Text(
                                        "Rejection Reason: ${item.rejectionReason}",
                                        style: AppTypography.caption.copyWith(color: AppColors.peachFg, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showUploadDocumentModal(context),
            backgroundColor: AppColors.primary,
            icon: const Icon(CupertinoIcons.cloud_upload, color: Colors.white),
            label: Text("Upload Document", style: AppTypography.bodyLarge.copyWith(color: Colors.white)),
          ),
        );
      },
    );
  }
}
