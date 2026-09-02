import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/file_pick_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/workforce_request_modal.dart';

class UploadDocumentModal extends StatefulWidget {
  const UploadDocumentModal({super.key});

  @override
  State<UploadDocumentModal> createState() => _UploadDocumentModalState();
}

class _UploadDocumentModalState extends State<UploadDocumentModal> {
  String _selectedDocType = "Aadhaar Card";
  SelectedFileResult? _selectedFile;
  String? _validationError;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  final List<String> _docTypes = const [
    "Aadhaar Card",
    "PAN Card",
    "Passport",
    "Driving Licence",
    "Educational Certificate",
    "Bank Document",
    "Previous Employment",
    "Other",
  ];

  Future<void> _pickFile() async {
    final picked = await FilePickService.pickDocumentFile(preferredDocType: _selectedDocType);
    if (picked != null) {
      final err = FilePickService.validateFile(picked);
      setState(() {
        _selectedFile = picked;
        _validationError = err;
      });
    }
  }

  Future<void> _startUpload() async {
    if (_selectedFile == null) {
      setState(() => _validationError = "Please select a document file to upload.");
      return;
    }
    final err = FilePickService.validateFile(_selectedFile!);
    if (err != null) {
      setState(() => _validationError = err);
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.5;
      _validationError = null;
    });

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final success = await MoreModulesController.instance.uploadDocument(
      documentType: _selectedDocType,
      fileName: _selectedFile!.fileName,
      fileExtension: _selectedFile!.fileExtension,
      fileSize: _selectedFile!.formattedSize,
      fileBytes: _selectedFile!.bytes != null ? Uint8List.fromList(_selectedFile!.bytes!) : null,
      filePath: _selectedFile!.filePath,
    );

    if (mounted) {
      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(success ? "Document uploaded successfully!" : "Upload failed."),
          backgroundColor: success ? AppColors.primary : AppColors.statusError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkForceOSRequestModal(
      title: "Upload Document",
      subtitle: "Add a personal document to your secure employee records.",
      primaryButtonLabel: _isUploading ? "Uploading (${(_uploadProgress * 100).toInt()}%)..." : "Upload Document",
      isSubmitting: _isUploading,
      onPrimaryPressed: _startUpload,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Document Type", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.slateBg,
              borderRadius: AppRadius.borderMd,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDocType,
                isExpanded: true,
                icon: const Icon(CupertinoIcons.chevron_down, size: 16, color: AppColors.textMuted),
                style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                items: _docTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: _isUploading
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() {
                            _selectedDocType = val;
                            _validationError = null;
                          });
                        }
                      },
              ),
            ),
          ),
          AppSpacing.gapMD,
          Text("File Selection", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _isUploading ? null : _pickFile,
            borderRadius: AppRadius.borderMd,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.slateBg,
                borderRadius: AppRadius.borderMd,
                border: Border.all(
                  color: _validationError != null ? AppColors.statusError : AppColors.borderSubtle,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.mintBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _selectedFile != null ? CupertinoIcons.doc_text_fill : CupertinoIcons.folder_badge_plus,
                      color: AppColors.mintFg,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFile != null ? _selectedFile!.fileName : "No file chosen yet",
                          style: AppTypography.bodyRegular.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _selectedFile != null ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _selectedFile != null
                              ? "${_selectedFile!.fileExtension.toUpperCase()} • ${_selectedFile!.formattedSize}"
                              : "Tap to select PDF, JPG, PNG or DOCX (Max 10 MB)",
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppRadius.borderSm,
                      boxShadow: AppShadows.softCard,
                    ),
                    child: Text(
                      _selectedFile != null ? "Change" : "Choose File",
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 8),
            Text(
              _validationError!,
              style: AppTypography.caption.copyWith(color: AppColors.statusError, fontWeight: FontWeight.w500),
            ),
          ],
          if (_isUploading) ...[
            AppSpacing.gapMD,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Uploading to secure cloud...", style: AppTypography.caption),
                Text("${(_uploadProgress * 100).toInt()}%", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: AppColors.slateBg,
                color: AppColors.primary,
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
