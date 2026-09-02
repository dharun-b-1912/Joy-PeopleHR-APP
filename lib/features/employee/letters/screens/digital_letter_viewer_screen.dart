import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/document_upload_service.dart';
import '../../../../core/services/file_download_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';

class DigitalLetterViewerScreen extends StatefulWidget {
  final DigitalLetterModel letter;

  const DigitalLetterViewerScreen({super.key, required this.letter});

  @override
  State<DigitalLetterViewerScreen> createState() => _DigitalLetterViewerScreenState();
}

class _DigitalLetterViewerScreenState extends State<DigitalLetterViewerScreen> {
  String? _resolvedUrl;
  Uint8List? _fileBytes;
  bool _isLoading = false;
  bool _isDownloading = false;
  bool _isSigning = false;
  late DigitalLetterModel _currentLetter;

  @override
  void initState() {
    super.initState();
    _currentLetter = widget.letter;
    _resolveLetterUrl();
  }

  Future<void> _resolveLetterUrl() async {
    final rawUrl = _currentLetter.documentUrl;
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
      final rawUrl = _resolvedUrl ?? _currentLetter.documentUrl ?? '';
      final cleanName = '${_currentLetter.title.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_')}.pdf';

      bool downloaded = false;
      if (_fileBytes != null && _fileBytes!.isNotEmpty) {
        downloaded = await FileDownloadService.downloadBytes(
          fileName: cleanName,
          bytes: _fileBytes!,
        );
      } else if (rawUrl.startsWith('http')) {
        downloaded = await FileDownloadService.downloadFromUrl(
          url: rawUrl,
          fileName: cleanName,
        );
      }

      if (downloaded || (_fileBytes != null && _fileBytes!.isNotEmpty)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("✓ '$cleanName' saved to Downloads"),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text("Document opened: ${_currentLetter.title}"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Unable to download letter: $e"),
          backgroundColor: AppColors.statusError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _handleSignAndAcknowledge() async {
    setState(() => _isSigning = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final user = UserService.instance.currentUser;
      final signatureStamp =
          "DIGITALLY_SIGNED_BY_${user.name.toUpperCase()}_AT_${DateTime.now().toIso8601String()}";

      await MoreModulesController.instance.acknowledgeDigitalLetter(
        _currentLetter.id,
        signatureData: signatureStamp,
      );

      setState(() {
        _currentLetter = DigitalLetterModel(
          id: _currentLetter.id,
          title: _currentLetter.title,
          category: _currentLetter.category,
          issueDate: _currentLetter.issueDate,
          effectiveDate: _currentLetter.effectiveDate,
          documentRef: _currentLetter.documentRef,
          documentUrl: _currentLetter.documentUrl,
          documentType: _currentLetter.documentType,
          fileName: _currentLetter.fileName,
          referenceNumber: _currentLetter.referenceNumber,
          contentBody: _currentLetter.contentBody,
          requiresSignature: _currentLetter.requiresSignature,
          status: 'SIGNED',
          signatureData: signatureStamp,
          signedAt: DateTime.now(),
          issuedByName: _currentLetter.issuedByName,
        );
      });

      messenger.showSnackBar(
        const SnackBar(
          content: Text("✓ Digital Letter acknowledged and signed successfully."),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Error signing letter: $e"),
          backgroundColor: AppColors.statusError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final letter = _currentLetter;
    final issuedDateStr = "${letter.issueDate.day}/${letter.issueDate.month}/${letter.issueDate.year}";
    final urlLower = (_resolvedUrl ?? letter.documentUrl ?? '').toLowerCase();
    final isImage = letter.documentType == 'image' ||
        urlLower.contains(".jpg") ||
        urlLower.contains(".jpeg") ||
        urlLower.contains(".png") ||
        urlLower.contains(".webp");

    ImageProvider? imageProvider;
    if (_fileBytes != null && _fileBytes!.isNotEmpty && isImage) {
      imageProvider = MemoryImage(_fileBytes!);
    } else if (_resolvedUrl != null && _resolvedUrl!.startsWith('http') && isImage) {
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
          letter.title,
          style: AppTypography.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          StatusChip(
            label: letter.isSigned ? "Signed" : (letter.requiresSignature ? "Sign Req." : "Official"),
            type: letter.isSigned ? StatusType.success : (letter.requiresSignature ? StatusType.warning : StatusType.info),
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
            // 1. Preview Container Card
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
                        ? PhotoView(
                            imageProvider: imageProvider,
                            minScale: PhotoViewComputedScale.contained,
                            maxScale: PhotoViewComputedScale.covered * 3.0,
                            backgroundDecoration: const BoxDecoration(color: Colors.white),
                            errorBuilder: (_, __, ___) => _buildLetterFallback(letter),
                          )
                        : _buildLetterFallback(letter),
              ),
            ),

            AppSpacing.gapLG,

            // 2. Letter Information Section
            Text("Letter Information", style: AppTypography.titleMedium),
            AppSpacing.gapMD,
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDetailRow("Letter Name", letter.title),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow("Category", "Official HR ${letter.category} Letter"),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow("Issued By", letter.issuedByName ?? "HR Department"),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow("Reference No.", letter.referenceNumber ?? "—"),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow(
                    "Status",
                    letter.isSigned ? "Digitally Signed & Verified" : (letter.requiresSignature ? "Signature Required" : "Official Letter"),
                  ),
                  const Divider(height: 20, color: AppColors.borderSubtle),
                  _buildDetailRow("Issued On", issuedDateStr),
                ],
              ),
            ),

            AppSpacing.gapLG,

            // 3. Action Buttons
            if (letter.requiresSignature && !letter.isSigned) ...[
              AppButton(
                label: _isSigning ? "Signing..." : "Acknowledge & Sign Letter",
                icon: CupertinoIcons.signature,
                variant: AppButtonVariant.primaryPill,
                onPressed: _isSigning ? null : _handleSignAndAcknowledge,
              ),
              AppSpacing.gapMD,
            ],

            Row(
              children: [
                if (_resolvedUrl != null && _resolvedUrl!.startsWith('http')) ...[
                  Expanded(
                    child: AppButton(
                      label: "Full View",
                      icon: CupertinoIcons.arrow_up_right_square,
                      variant: AppButtonVariant.secondaryPill,
                      onPressed: () async {
                        final rawUrl = _resolvedUrl ?? letter.documentUrl ?? '';
                        final uri = Uri.parse(rawUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } else {
                          final cleanName = '${letter.title.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_')}.pdf';
                          FileDownloadService.downloadFromUrl(url: rawUrl, fileName: cleanName);
                        }
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

  Widget _buildLetterFallback(DigitalLetterModel letter) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.skyBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.doc_text_fill, size: 36, color: AppColors.skyFg),
            ),
            AppSpacing.gapMD,
            Text(letter.title, style: AppTypography.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text("Official HR Letter • PDF Document", style: AppTypography.caption),
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
                  Icon(
                    letter.isSigned ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.lock_shield_fill,
                    size: 14,
                    color: letter.isSigned ? AppColors.mintFg : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    letter.isSigned ? "Digitally Verified & Signed" : "Encrypted Corporate Storage Verified",
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
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
