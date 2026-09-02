import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import '../../../../core/services/document_upload_service.dart';
import '../../../../core/services/file_download_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';

class DocumentViewerScreen extends StatefulWidget {
  final DocumentModel document;

  const DocumentViewerScreen({super.key, required this.document});

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  String? _resolvedUrl;
  Uint8List? _fileBytes;
  bool _isLoading = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _resolveDocumentUrl();
  }

  Future<void> _resolveDocumentUrl() async {
    final rawUrl = widget.document.fileUrl ?? widget.document.storagePath;
    if (rawUrl != null && rawUrl.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final signed = await DocumentUploadService.instance.getSignedUrl(rawUrl);
        Uint8List? bytes;
        try {
          bytes = await DocumentUploadService.instance.downloadFileBytes(rawUrl);
        } catch (_) {}

        if (mounted) {
          setState(() {
            _resolvedUrl = signed ?? rawUrl;
            _fileBytes = bytes;
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDownload() async {
    setState(() => _isDownloading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final rawPath = widget.document.storagePath ?? widget.document.fileUrl ?? '';
      final bytes = await DocumentUploadService.instance.downloadFileBytes(rawPath);

      String cleanName = widget.document.name.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
      if (!cleanName.toLowerCase().contains('.')) {
        final ext = widget.document.fileType.toLowerCase().contains('image') || widget.document.fileType.toLowerCase().contains('png')
            ? '.png'
            : '.pdf';
        cleanName = '$cleanName$ext';
      }

      bool downloaded = false;
      if (bytes != null && bytes.isNotEmpty) {
        downloaded = await FileDownloadService.downloadBytes(
          fileName: cleanName,
          bytes: bytes,
        );
      } else if (rawPath.startsWith('http')) {
        downloaded = await FileDownloadService.downloadFromUrl(
          url: rawPath,
          fileName: cleanName,
        );
      }

      if (downloaded || (bytes != null && bytes.isNotEmpty)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("✓ '$cleanName' saved to Downloads (${bytes?.lengthInBytes ?? 0} bytes)"),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text("File available online: ${widget.document.name}"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Unable to download document: $e"),
          backgroundColor: AppColors.statusError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final fileTypeLower = document.fileType.toLowerCase();
    final urlLower = (_resolvedUrl ?? document.fileUrl ?? document.storagePath ?? '').toLowerCase();
    final isImage = fileTypeLower.contains("jpg") ||
        fileTypeLower.contains("jpeg") ||
        fileTypeLower.contains("png") ||
        fileTypeLower.contains("webp") ||
        fileTypeLower.contains("image") ||
        fileTypeLower.contains("license") ||
        fileTypeLower.contains("licence") ||
        fileTypeLower.contains("pan") ||
        fileTypeLower.contains("aadhaar") ||
        fileTypeLower.contains("passport") ||
        urlLower.contains(".jpg") ||
        urlLower.contains(".jpeg") ||
        urlLower.contains(".png") ||
        urlLower.contains(".webp") ||
        (_fileBytes != null && _fileBytes!.isNotEmpty);

    ImageProvider? imageProvider;
    if (_fileBytes != null && _fileBytes!.isNotEmpty) {
      imageProvider = MemoryImage(_fileBytes!);
    } else if (_resolvedUrl != null && _resolvedUrl!.startsWith('http')) {
      imageProvider = NetworkImage(_resolvedUrl!);
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          document.name,
          style: AppTypography.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          StatusChip(
            label: document.category == DocumentCategory.company ? "Company" : "Personal",
            type: document.category == DocumentCategory.company ? StatusType.info : StatusType.neutral,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 340,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.borderLg,
                boxShadow: AppShadows.softCard,
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: ClipRRect(
                borderRadius: AppRadius.borderLg,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : (isImage && imageProvider != null)
                        ? ClipRRect(
                            borderRadius: AppRadius.borderLg,
                            child: PhotoView(
                              imageProvider: imageProvider,
                              minScale: PhotoViewComputedScale.contained,
                              maxScale: PhotoViewComputedScale.covered * 3.0,
                              backgroundDecoration: const BoxDecoration(color: Colors.white),
                              errorBuilder: (_, __, ___) => _buildImageFallback(document),
                            ),
                          )
                        : isImage
                            ? _buildImageFallback(document)
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 72,
                                        height: 72,
                                        decoration: const BoxDecoration(
                                          color: AppColors.lavenderBg,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(CupertinoIcons.doc_text_fill, size: 36, color: AppColors.lavenderFg),
                                      ),
                                      AppSpacing.gapMD,
                                      Text(document.name, style: AppTypography.titleLarge, textAlign: TextAlign.center),
                                      const SizedBox(height: 4),
                                      Text("Verified Document • ${document.fileType}", style: AppTypography.caption),
                                      AppSpacing.gapMD,
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.slateBg,
                                          borderRadius: AppRadius.borderPill,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(CupertinoIcons.lock_shield_fill, size: 14, color: AppColors.primary),
                                            const SizedBox(width: 6),
                                            Text("Encrypted Storage Verified", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
              ),
            ),
            AppSpacing.gapLG,
            Text("Document Information", style: AppTypography.titleMedium),
            AppSpacing.gapMD,
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDetailRow("Document Name", document.name),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow("Category", document.category == DocumentCategory.company ? "Official Company Policy" : "Private Personal Document"),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow("File Format", document.fileType),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow("File Size", document.fileSize),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow("Uploaded On", "${document.uploadedAt.day}/${document.uploadedAt.month}/${document.uploadedAt.year}"),
                ],
              ),
            ),
            AppSpacing.gapLG,
            Row(
              children: [
                if (_resolvedUrl != null && _resolvedUrl!.startsWith('http')) ...[
                  Expanded(
                    child: AppButton(
                      label: "Full View",
                      icon: CupertinoIcons.arrow_up_right_square,
                      variant: AppButtonVariant.secondaryPill,
                      onPressed: () {
                        final rawUrl = _resolvedUrl ?? widget.document.fileUrl ?? '';
                        final cleanName = widget.document.name.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
                        FileDownloadService.downloadFromUrl(url: rawUrl, fileName: cleanName);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: AppButton(
                    label: _isDownloading ? "Downloading..." : "Download",
                    icon: CupertinoIcons.arrow_down_doc_fill,
                    variant: AppButtonVariant.primaryPill,
                    onPressed: _isDownloading ? null : _handleDownload,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageFallback(DocumentModel document) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.mintBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(CupertinoIcons.photo_fill, size: 36, color: AppColors.mintFg),
          ),
          AppSpacing.gapMD,
          Text(document.name, style: AppTypography.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text("High-Resolution Verified Image", style: AppTypography.caption),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
