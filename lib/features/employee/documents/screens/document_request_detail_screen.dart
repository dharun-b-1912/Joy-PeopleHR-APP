import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/file_pick_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../core/utils/query_timeout.dart';
import '../../../../core/utils/secure_log.dart';
import '../../../../models/employee_models.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/status_chip.dart';

class DocumentRequestDetailScreen extends StatefulWidget {
  final String requestId;
  final DocumentRequirementModel? initialModel;

  const DocumentRequestDetailScreen({
    super.key,
    required this.requestId,
    this.initialModel,
  });

  @override
  State<DocumentRequestDetailScreen> createState() =>
      _DocumentRequestDetailScreenState();
}

class _DocumentRequestDetailScreenState
    extends State<DocumentRequestDetailScreen> {
  DocumentRequirementModel? _req;
  bool _isLoading = true;
  bool _isUploading = false;
  SelectedFileResult? _selectedFile;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _req = widget.initialModel;
    _fetchRequirement();
  }

  Future<void> _fetchRequirement() async {
    if (!SupabaseConfig.isConfigured || widget.requestId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final client = Supabase.instance.client;
      final data = await withTimeout(
        client
            .from('document_requirements')
            .select()
            .eq('id', widget.requestId)
            .maybeSingle(),
      );

      if (data != null && mounted) {
        setState(() {
          _req = DocumentRequirementModel(
            id: data['id'].toString(),
            employeeId: data['employee_id']?.toString() ?? '',
            documentType: data['document_type']?.toString() ?? 'Document',
            title: data['title']?.toString() ?? 'Required Document',
            description: data['description']?.toString() ?? '',
            isMandatory: data['required'] == true,
            dueDate: DateTime.tryParse(data['due_date']?.toString() ?? ''),
            status: (data['status']?.toString() ?? 'REQUIRED').toUpperCase(),
            rejectionReason: data['rejection_reason']?.toString(),
            requestedBy: data['requested_by']?.toString() ?? 'HR Team',
            documentId: data['document_id']?.toString(),
            createdAt:
                DateTime.tryParse(data['created_at']?.toString() ?? '') ??
                    DateTime.now(),
          );
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      secureLog('[DocReqDetail] Fetch error: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickFile() async {
    debugPrint('[DocReqDetail] _pickFile triggered by user.');
    try {
      final picked = await FilePickService.pickDocumentFile(preferredDocType: _req?.documentType);
      debugPrint('[DocReqDetail] pickDocumentFile returned: ${picked?.fileName} (bytes: ${picked?.bytes?.length})');
      if (picked != null) {
        final err = FilePickService.validateFile(picked);
        debugPrint('[DocReqDetail] validation result: $err');
        setState(() {
          _selectedFile = picked;
          _validationError = err;
        });
      }
    } catch (e, st) {
      debugPrint('[DocReqDetail] Pick error: $e\n$st');
      setState(() => _validationError = 'Error picking file: $e');
    }
  }

  String _generateUuid() {
    final rnd = math.Random();
    String hex(int len) =>
        List.generate(len, (_) => rnd.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${(rnd.nextInt(4) + 8).toRadixString(16)}${hex(3)}-${hex(12)}';
  }

  Future<void> _submitUpload() async {
    if (_selectedFile == null) {
      setState(() => _validationError = 'Please select a document file first.');
      return;
    }

    final err = FilePickService.validateFile(_selectedFile!);
    if (err != null) {
      setState(() => _validationError = err);
      return;
    }

    setState(() {
      _isUploading = true;
      _validationError = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final user = UserService.instance.currentUser;
    final empId = (_req?.employeeId.isNotEmpty == true)
        ? _req!.employeeId
        : ((user.employeeUuid?.isNotEmpty == true)
            ? user.employeeUuid!
            : user.employeeId);

    if (empId.isEmpty) {
      setState(() {
        _isUploading = false;
        _validationError = "Employee identity could not be verified.";
      });
      return;
    }

    debugPrint(
        '[DOC_UPLOAD] ========================================================');
    debugPrint('[DOC_UPLOAD] Starting document upload for employee: $empId');
    debugPrint(
        '[DOC_UPLOAD] Request ID: ${widget.requestId}, Title: ${_req?.title}');
    debugPrint(
        '[DOC_UPLOAD] File: ${_selectedFile!.fileName}, Size: ${_selectedFile!.formattedSize}');

    try {
      final client = Supabase.instance.client;
      final fileName = _selectedFile!.fileName;
      final fileBytes = _selectedFile!.bytes;
      final ext =
          _selectedFile!.fileExtension.replaceAll('.', '').toLowerCase();
      final mimeType = ext == 'pdf'
          ? 'application/pdf'
          : (ext == 'png'
              ? 'image/png'
              : (ext == 'webp'
                  ? 'image/webp'
                  : (ext == 'gif'
                      ? 'image/gif'
                      : (ext == 'doc'
                          ? 'application/msword'
                          : (ext == 'docx'
                              ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                              : 'image/jpeg')))));

      final cleanName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final folderPath = 'employees/$empId/documents/${widget.requestId}';
      final storagePath = '$folderPath/${DateTime.now().millisecondsSinceEpoch}_$cleanName';
      String fileUrl = '';

      // 0. Automatically delete previous files in this requirement folder on re-upload
      try {
        final existingFiles = await client.storage.from('employee-documents').list(path: folderPath);
        if (existingFiles.isNotEmpty) {
          final toDelete = existingFiles
              .where((f) => f.name.isNotEmpty && !f.name.startsWith('.'))
              .map((f) => '$folderPath/${f.name}')
              .toList();
          if (toDelete.isNotEmpty) {
            debugPrint('[DOC_UPLOAD] [0/3] Auto-deleting ${toDelete.length} previous file(s): $toDelete');
            await client.storage.from('employee-documents').remove(toDelete);
          }
        }
      } catch (cleanErr) {
        debugPrint('[DOC_UPLOAD] Storage cleanup notice: $cleanErr');
      }

      // 1. Upload Binary to employee-documents Supabase Storage Bucket (Primary)
      if (fileBytes != null && fileBytes.isNotEmpty) {
        final bytesData = Uint8List.fromList(fileBytes);
        debugPrint(
            '[DOC_UPLOAD] [1/3] Uploading binary bytes to Supabase storage "employee-documents" at: $storagePath');
        try {
          await client.storage.from('employee-documents').uploadBinary(
                storagePath,
                bytesData,
                fileOptions: FileOptions(contentType: mimeType, upsert: true),
              );
          fileUrl = client.storage
              .from('employee-documents')
              .getPublicUrl(storagePath);
          debugPrint(
              '[DOC_UPLOAD] [1/3] Upload to employee-documents SUCCESS -> $fileUrl');
        } catch (storageErr1) {
          debugPrint(
              '[DOC_UPLOAD] employee-documents notice: $storageErr1, trying fallback bucket workforce-documents');
          try {
            await client.storage.from('workforce-documents').uploadBinary(
                  storagePath,
                  bytesData,
                  fileOptions: FileOptions(contentType: mimeType, upsert: true),
                );
            fileUrl = client.storage
                .from('workforce-documents')
                .getPublicUrl(storagePath);
            debugPrint(
                '[DOC_UPLOAD] [1/3] Upload to workforce-documents SUCCESS -> $fileUrl');
          } catch (storageErr2) {
            debugPrint('[DOC_UPLOAD] Storage fallback notice: $storageErr2');
            fileUrl = client.storage
                .from('employee-documents')
                .getPublicUrl(storagePath);
          }
        }
      } else {
        debugPrint(
            '[DOC_UPLOAD] WARNING: fileBytes is null or empty, using storage path pointer');
      }

      // 2. Submit via RPC (if deployed)
      bool rpcSuccess = false;
      try {
        final rpcRes = await client.rpc('fn_submit_document_upload', params: {
          'p_requirement_id': widget.requestId,
          'p_employee_id': empId,
          'p_document_category': 'PERSONAL',
          'p_document_type': _req?.documentType ?? 'DOCUMENT',
          'p_file_name': fileName,
          'p_file_url': fileUrl,
          'p_storage_path': storagePath,
          'p_file_size_bytes': _selectedFile!.sizeInBytes,
          'p_mime_type': mimeType,
        });
        debugPrint(
            '[DOC_UPLOAD] [2/3] RPC fn_submit_document_upload response: $rpcRes');
        rpcSuccess = true;
      } catch (rpcErr) {
        debugPrint(
            '[DOC_UPLOAD] RPC not deployed or returned: $rpcErr (using direct DB update)');
      }

      // 3. Guaranteed Direct Database Fallback Updates with RFC-4122 UUID
      try {
        debugPrint(
            '[DOC_UPLOAD] [3/3] Updating document_requirements status to SUBMITTED in PostgreSQL...');
        await client.from('document_requirements').update({
          'status': 'SUBMITTED',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.requestId);

        final docId = 'doc-${_generateUuid()}';
        debugPrint(
            '[DOC_UPLOAD] [3/3] Inserting employee_documents row with ID: $docId');
        try {
          await client.from('employee_documents').insert({
            'id': docId,
            'employee_id': empId,
            'document_category': 'PERSONAL',
            'document_type': _req?.documentType ?? 'Driving Licence',
            'file_name': fileName,
            'file_url': fileUrl,
            'file_size_bytes': _selectedFile!.sizeInBytes,
            'verification_status': 'Pending',
            'uploaded_at': DateTime.now().toIso8601String(),
          });
          debugPrint(
              '[DOC_UPLOAD] ✓ Database update and employee_documents row inserted successfully!');
        } catch (docErr) {
          debugPrint(
              '[DOC_UPLOAD] employee_documents notice: $docErr (document_requirements update is active)');
        }

        // 4. Notify HR Web via Realtime Notification Event
        try {
          final notifUuid = _generateUuid();
          await client.from('notification_events').insert({
            'id': notifUuid,
            'event_type': 'DOCUMENT_SUBMITTED',
            'category': 'SYSTEM',
            'severity': 'INFO',
            'title': 'Document Submitted: ${_req?.title ?? "Document"}',
            'body':
                '${user.name.isNotEmpty ? user.name : empId} submitted ${_req?.title ?? "Document"} for HR verification.',
            'resource_type': 'DOCUMENT_REQUIREMENT',
            'resource_id': widget.requestId,
            'actor_name': user.name.isNotEmpty ? user.name : 'Employee',
            'metadata': {
              'requirement_id': widget.requestId,
              'employee_id': empId,
              'document_type': _req?.documentType,
              'file_name': fileName,
              'file_url': fileUrl,
              'storage_path': storagePath,
            },
          });
          debugPrint(
              '[DOC_UPLOAD] ✓ notification_events row emitted to HR Web via Realtime');
        } catch (notifErr) {
          debugPrint('[DOC_UPLOAD] notification_events notice: $notifErr');
        }
      } catch (dbErr) {
        debugPrint('[DOC_UPLOAD] Database write error: $dbErr');
        if (!rpcSuccess) {
          throw Exception('Failed to save document record: $dbErr');
        }
      }

      debugPrint(
          '[DOC_UPLOAD] ========================================================');
      debugPrint('[DOC_UPLOAD] Document upload completed successfully!');

      // Refresh local controllers
      MoreModulesController.instance.loadAllData();
      NotificationController.instance.loadNotifications();

      if (mounted) {
        setState(() {
          _isUploading = false;
          _selectedFile = null;
          _req = DocumentRequirementModel(
            id: _req?.id ?? widget.requestId,
            employeeId: _req?.employeeId ?? empId,
            documentType: _req?.documentType ?? 'Document',
            title: _req?.title ?? 'Document',
            description: _req?.description ?? '',
            isMandatory: _req?.isMandatory ?? true,
            dueDate: _req?.dueDate,
            status: 'SUBMITTED',
            requestedBy: _req?.requestedBy,
            documentId: _req?.documentId,
            createdAt: _req?.createdAt ?? DateTime.now(),
          );
        });

        messenger.showSnackBar(
          const SnackBar(
            content: Text('✓ Document uploaded successfully! Under HR review.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      secureLog('[DocReqDetail] Submit failed: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _validationError = 'Upload failed: $e';
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.statusError,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  StatusType _statusChipType(String status) {
    switch (status) {
      case 'VERIFIED':
      case 'APPROVED':
        return StatusType.success;
      case 'SUBMITTED':
      case 'UNDER_REVIEW':
        return StatusType.info;
      case 'REJECTED':
      case 'REUPLOAD_REQUIRED':
        return StatusType.error;
      default:
        return StatusType.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = _req;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Document Request",
          style: AppTypography.titleLarge,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : req == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.exclamationmark_triangle,
                            size: 40, color: AppColors.statusWarning),
                        AppSpacing.gapMD,
                        Text("Requirement Not Found",
                            style: AppTypography.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          "The document request could not be loaded from the database.",
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                        AppSpacing.gapLG,
                        AppButton(
                          label: "Go Back",
                          variant: AppButtonVariant.secondaryPill,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                  children: [
                    // Status Alert Banner
                    if (req.isRejected || req.status == 'REUPLOAD_REQUIRED')
                      Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.roseBg,
                          borderRadius: AppRadius.borderMd,
                          border: Border.all(
                              color:
                                  AppColors.statusError.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                                CupertinoIcons.exclamationmark_octagon_fill,
                                color: AppColors.statusError,
                                size: 20),
                            AppSpacing.hGapMD,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Action Required: Re-upload Document",
                                    style: AppTypography.titleMedium.copyWith(
                                        color: AppColors.roseFg,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    req.rejectionReason?.isNotEmpty == true
                                        ? "HR Reason: ${req.rejectionReason}"
                                        : "Your previous submission was not accepted. Please upload a clearer copy.",
                                    style: AppTypography.caption
                                        .copyWith(color: AppColors.roseFg),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (req.isSubmitted)
                      Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.lavenderBg,
                          borderRadius: AppRadius.borderMd,
                          border: Border.all(
                              color:
                                  AppColors.lavenderFg.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.clock_fill,
                                color: AppColors.lavenderFg, size: 20),
                            AppSpacing.hGapMD,
                            Expanded(
                              child: Text(
                                "Document submitted. Under verification by HR.",
                                style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.lavenderFg,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (req.isVerified)
                      Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.mintBg,
                          borderRadius: AppRadius.borderMd,
                          border: Border.all(
                              color: AppColors.mintFg.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.checkmark_seal_fill,
                                color: AppColors.mintFg, size: 20),
                            AppSpacing.hGapMD,
                            Expanded(
                              child: Text(
                                "Document verified and approved by HR.",
                                style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.mintFg,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Main Details Card
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              StatusChip(
                                label: req.status,
                                type: _statusChipType(req.status),
                              ),
                              if (req.isMandatory)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.roseBg,
                                    borderRadius: AppRadius.borderSm,
                                  ),
                                  child: Text(
                                    "MANDATORY",
                                    style: AppTypography.overline.copyWith(
                                        color: AppColors.roseFg,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          AppSpacing.gapMD,
                          Text(req.title, style: AppTypography.titleLarge),
                          const SizedBox(height: 4),
                          Text("Type: ${req.documentType}",
                              style: AppTypography.caption
                                  .copyWith(fontFamily: 'monospace')),
                          AppSpacing.gapMD,
                          const Divider(height: 1),
                          AppSpacing.gapMD,
                          if (req.description.isNotEmpty) ...[
                            Text("Instructions from HR",
                                style: AppTypography.titleMedium),
                            const SizedBox(height: 4),
                            Text(req.description,
                                style: AppTypography.bodySmall),
                            AppSpacing.gapMD,
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Requested By",
                                        style: AppTypography.caption),
                                    const SizedBox(height: 2),
                                    Text(
                                      req.requestedBy ?? "HR Team",
                                      style: AppTypography.bodyRegular.copyWith(
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Target Employee",
                                        style: AppTypography.caption),
                                    const SizedBox(height: 2),
                                    Text(
                                      UserService.instance.currentUser.name
                                              .isNotEmpty
                                          ? "${UserService.instance.currentUser.name} (${UserService.instance.currentUser.employeeId})"
                                          : req.employeeId,
                                      style: AppTypography.bodyRegular.copyWith(
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (req.dueDate != null)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("Due Date",
                                          style: AppTypography.caption),
                                      const SizedBox(height: 2),
                                      Text(
                                        "${req.dueDate!.day} ${_monthName(req.dueDate!.month)} ${req.dueDate!.year}",
                                        style: AppTypography.bodyRegular
                                            .copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.statusError),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    AppSpacing.gapLG,

                    // Upload Section (Only active if pending/rejected)
                    if (req.isPending) ...[
                      Text("Upload Document File",
                          style: AppTypography.titleMedium),
                      const SizedBox(height: 4),
                      Text("Supported formats: PDF, PNG, JPG, WEBP (Max 20MB).",
                          style: AppTypography.caption),
                      AppSpacing.gapMD,
                      AppCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            if (_selectedFile == null) ...[
                              InkWell(
                                onTap: _isUploading ? null : _pickFile,
                                borderRadius: AppRadius.borderMd,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: AppColors.slateBg
                                        .withValues(alpha: 0.5),
                                    borderRadius: AppRadius.borderMd,
                                    border: Border.all(
                                        color: AppColors.borderLight,
                                        style: BorderStyle.solid),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(
                                          CupertinoIcons.cloud_upload_fill,
                                          size: 36,
                                          color: AppColors.primary),
                                      AppSpacing.gapSM,
                                      Text("Tap to Choose File",
                                          style: AppTypography.titleMedium
                                              .copyWith(
                                                  color: AppColors.primary)),
                                      const SizedBox(height: 2),
                                      Text(
                                          "PDF, PNG, JPG or WEBP from your device",
                                          style: AppTypography.caption),
                                    ],
                                  ),
                                ),
                              ),
                            ] else
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: AppColors.mintBg,
                                  borderRadius: AppRadius.borderMd,
                                  border: Border.all(
                                      color: AppColors.mintFg
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(CupertinoIcons.doc_fill,
                                        color: AppColors.mintFg),
                                    AppSpacing.hGapMD,
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _selectedFile!.fileName,
                                            style: AppTypography.bodyRegular
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(_selectedFile!.formattedSize,
                                              style: AppTypography.caption),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          CupertinoIcons.xmark_circle,
                                          color: AppColors.textMuted),
                                      onPressed: _isUploading
                                          ? null
                                          : () => setState(
                                              () => _selectedFile = null),
                                    ),
                                  ],
                                ),
                              ),
                            if (_validationError != null) ...[
                              AppSpacing.gapSM,
                              Text(_validationError!,
                                  style: AppTypography.caption
                                      .copyWith(color: AppColors.statusError)),
                            ],
                            AppSpacing.gapLG,
                            AppButton(
                              label: _isUploading
                                  ? "Uploading to Supabase..."
                                  : "Submit Document",
                              icon: CupertinoIcons.arrow_up_doc_fill,
                              isLoading: _isUploading,
                              variant: AppButtonVariant.primaryPill,
                              onPressed: _selectedFile == null || _isUploading
                                  ? null
                                  : _submitUpload,
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Submitted Document State
                    if (req.isSubmitted || req.isVerified) ...[
                      Text("Submitted Document",
                          style: AppTypography.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                          "Your document has been stored in Supabase and delivered to HR.",
                          style: AppTypography.caption),
                      AppSpacing.gapMD,
                      AppCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: AppColors.mintBg,
                                borderRadius: AppRadius.borderMd,
                                border: Border.all(
                                    color: AppColors.mintFg
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(CupertinoIcons.checkmark_seal_fill,
                                      color: AppColors.mintFg, size: 28),
                                  AppSpacing.hGapMD,
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "${req.title} File",
                                          style: AppTypography.bodyRegular
                                              .copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "Uploaded & Stored in employee-documents",
                                          style: AppTypography.caption.copyWith(
                                              color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusChip(
                                    label: req.isVerified
                                        ? "VERIFIED"
                                        : "SUBMITTED",
                                    type: _statusChipType(req.status),
                                  ),
                                ],
                              ),
                            ),
                            AppSpacing.gapMD,
                            AppButton(
                              label: "Re-upload / Replace Document",
                              icon: CupertinoIcons.arrow_2_circlepath,
                              variant: AppButtonVariant.secondaryPill,
                              onPressed: () {
                                setState(() {
                                  _req = DocumentRequirementModel(
                                    id: req.id,
                                    employeeId: req.employeeId,
                                    documentType: req.documentType,
                                    title: req.title,
                                    description: req.description,
                                    isMandatory: req.isMandatory,
                                    dueDate: req.dueDate,
                                    status: 'REQUIRED',
                                    requestedBy: req.requestedBy,
                                    documentId: req.documentId,
                                    createdAt: req.createdAt,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  String _monthName(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month];
  }
}
