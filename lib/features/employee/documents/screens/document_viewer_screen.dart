import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _resolveDocumentUrl();
  }

  Future<void> _resolveDocumentUrl() async {
    final rawUrl = widget.document.storagePath ?? widget.document.fileUrl;
    if (rawUrl != null && rawUrl.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      try {
        final cleanPath = DocumentUploadService.instance.extractStoragePath(rawUrl);
        final signed = await DocumentUploadService.instance.getSignedUrl(cleanPath);
        final bytes = await DocumentUploadService.instance.downloadFileBytes(cleanPath);

        if (mounted) {
          setState(() {
            _resolvedUrl = signed;
            _fileBytes = bytes;
            _isLoading = false;
            if (_fileBytes == null && (_resolvedUrl == null || !_resolvedUrl!.startsWith('http'))) {
              _errorMessage = "Document file is missing or inaccessible.";
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Document could not be opened.";
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Document storage path not found.";
        });
      }
    }
  }

  String _getCleanFileName() {
    String cleanName = widget.document.name.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
    if (!cleanName.toLowerCase().contains('.')) {
      final ext = widget.document.fileExtension ?? (_isImageDocument() ? '.jpg' : '.pdf');
      cleanName = '$cleanName$ext';
    }
    return cleanName;
  }

  bool _isImageDocument() {
    final fileTypeLower = widget.document.fileType.toLowerCase();
    final urlLower = (_resolvedUrl ?? widget.document.fileUrl ?? widget.document.storagePath ?? '').toLowerCase();
    return fileTypeLower.contains("jpg") ||
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
  }

  void _handleFullView() {
    final isImg = _isImageDocument();
    final rawUrl = _resolvedUrl ?? widget.document.fileUrl ?? '';

    if (isImg && (_fileBytes != null || (rawUrl.isNotEmpty && rawUrl.startsWith('http')))) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FullScreenInteractiveViewer(
            title: widget.document.name,
            fileBytes: _fileBytes,
            imageUrl: rawUrl.startsWith('http') ? rawUrl : null,
          ),
        ),
      );
    } else if (rawUrl.isNotEmpty && rawUrl.startsWith('http')) {
      final uri = Uri.parse(rawUrl);
      launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (_fileBytes != null && _fileBytes!.isNotEmpty) {
      final cleanName = _getCleanFileName();
      FileDownloadService.downloadBytes(
        fileName: cleanName,
        bytes: _fileBytes!,
      );
    } else {
      _handleDownload();
    }
  }

  Future<void> _handleDownload() async {
    setState(() => _isDownloading = true);
    final messenger = ScaffoldMessenger.of(context);
    final cleanName = _getCleanFileName();

    try {
      final rawPath = widget.document.storagePath ?? widget.document.fileUrl ?? '';
      Uint8List? bytes = _fileBytes;
      if (bytes == null || bytes.isEmpty) {
        bytes = await DocumentUploadService.instance.downloadFileBytes(rawPath);
      }

      bool downloaded = false;
      if (bytes != null && bytes.isNotEmpty) {
        downloaded = await FileDownloadService.downloadBytes(
          fileName: cleanName,
          bytes: bytes,
        );
      }

      final downloadUrl = _resolvedUrl ?? widget.document.fileUrl;
      if (!downloaded && downloadUrl != null && downloadUrl.startsWith('http')) {
        downloaded = await FileDownloadService.downloadFromUrl(
          url: downloadUrl,
          fileName: cleanName,
        );
      }

      if (downloaded) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("✓ '$cleanName' saved to Downloads"),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: "OPEN",
              textColor: Colors.white,
              onPressed: () {
                FileDownloadService.openDownloadedFile(cleanName);
              },
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text("Download complete: $cleanName"),
            backgroundColor: AppColors.primary,
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
    final isImage = _isImageDocument();

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
            GestureDetector(
              onTap: _handleFullView,
              child: Container(
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
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                            : _errorMessage != null
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: const BoxDecoration(
                                              color: AppColors.peachBg,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 28, color: AppColors.peachFg),
                                          ),
                                          AppSpacing.gapMD,
                                          Text(
                                            _errorMessage!,
                                            style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            "Please check your internet or try re-uploading.",
                                            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : (isImage && imageProvider != null)
                                    ? PhotoView(
                                        imageProvider: imageProvider,
                                        minScale: PhotoViewComputedScale.contained,
                                        maxScale: PhotoViewComputedScale.covered * 3.0,
                                        backgroundDecoration: const BoxDecoration(color: Colors.white),
                                        errorBuilder: (_, __, ___) => _buildImageFallback(document),
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
                                                    Text("Tap to Full View", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: AppRadius.borderPill,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.arrow_up_right_circle_fill, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text("Full View", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                Expanded(
                  child: AppButton(
                    label: "Full View",
                    icon: CupertinoIcons.arrow_up_right_square,
                    variant: AppButtonVariant.secondaryPill,
                    onPressed: _handleFullView,
                  ),
                ),
                const SizedBox(width: 10),
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

class FullScreenInteractiveViewer extends StatelessWidget {
  final String title;
  final Uint8List? fileBytes;
  final String? imageUrl;

  const FullScreenInteractiveViewer({
    super.key,
    required this.title,
    this.fileBytes,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (fileBytes != null && fileBytes!.isNotEmpty) {
      imageProvider = MemoryImage(fileBytes!);
    } else if (imageUrl != null && imageUrl!.startsWith('http')) {
      imageProvider = NetworkImage(imageUrl!);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: imageProvider != null
          ? PhotoView(
              imageProvider: imageProvider,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4.0,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            )
          : const Center(
              child: Text("Document Preview Unavailable", style: TextStyle(color: Colors.white70)),
            ),
    );
  }
}
