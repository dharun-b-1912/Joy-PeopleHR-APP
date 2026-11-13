import 'dart:typed_data';
import 'dart:math' as math;
import 'package:universal_io/io.dart';
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
      Map<String, dynamic>? data = await withTimeout(
        client
            .from('document_requests')
            .select()
            .eq('id', widget.requestId)
            .maybeSingle(),
      );

      data ??= await withTimeout(
        client
            .from('document_requirements')
            .select()
            .eq('id', widget.requestId)
            .maybeSingle(),
      );

      if (data != null && mounted) {
        setState(() {
          _req = DocumentRequirementModel(
            id: data!['id'].toString(),
            employeeId: data['employee_id']?.toString() ?? '',
            documentType: data['document_type']?.toString() ??
                data['document_type_id']?.toString() ??
                widget.initialModel?.documentType ??
                'Document',
            title: data['document_title']?.toString() ??
                data['title']?.toString() ??
                'Required Document',
            description: data['request_message']?.toString() ??
                data['description']?.toString() ??
                '',
            isMandatory: data['is_required'] == true || data['required'] == true,
            dueDate: DateTime.tryParse(data['due_date']?.toString() ?? ''),
            status: (data['status']?.toString() ?? 'REQUIRED').toUpperCase(),
            rejectionReason: data['rejection_reason']?.toString(),
            requestedBy: data['requested_by_name']?.toString() ??
                data['requested_by']?.toString() ??
                'HR Team',
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
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

      String resolvedEmpUuid = '';
      String resolvedOrgId = '';

      if (user.employeeUuid != null && uuidRegex.hasMatch(user.employeeUuid!)) {
        resolvedEmpUuid = user.employeeUuid!;
      } else if (user.dataId.isNotEmpty && uuidRegex.hasMatch(user.dataId)) {
        resolvedEmpUuid = user.dataId;
      }

      if (user.organizationId != null && uuidRegex.hasMatch(user.organizationId!)) {
        resolvedOrgId = user.organizationId!;
      }

      // Resolve authoritative UUIDs from Supabase session if needed
      final authUser = client.auth.currentUser;
      if (authUser != null && (resolvedEmpUuid.isEmpty || resolvedOrgId.isEmpty)) {
        try {
          final profile = await client
              .from('user_profiles')
              .select('employee_id, organization_id')
              .or('auth_user_id.eq.${authUser.id},id.eq.${authUser.id}')
              .maybeSingle();
          if (profile != null) {
            final pEmpId = profile['employee_id']?.toString() ?? '';
            final pOrgId = profile['organization_id']?.toString() ?? '';
            if (resolvedEmpUuid.isEmpty && uuidRegex.hasMatch(pEmpId)) {
              resolvedEmpUuid = pEmpId;
            }
            if (resolvedOrgId.isEmpty && uuidRegex.hasMatch(pOrgId)) {
              resolvedOrgId = pOrgId;
            }
          }
        } catch (_) {}
      }

      // Lookup in employees table if still needed
      if (resolvedEmpUuid.isEmpty || resolvedOrgId.isEmpty) {
        try {
          final empRow = await client
              .from('employees')
              .select('id, organization_id')
              .eq('employee_code', user.employeeId.isNotEmpty ? user.employeeId : empId)
              .maybeSingle();
          if (empRow != null) {
            final eId = empRow['id']?.toString() ?? '';
            final oId = empRow['organization_id']?.toString() ?? '';
            if (resolvedEmpUuid.isEmpty && uuidRegex.hasMatch(eId)) {
              resolvedEmpUuid = eId;
            }
            if (resolvedOrgId.isEmpty && uuidRegex.hasMatch(oId)) {
              resolvedOrgId = oId;
            }
          }
        } catch (_) {}
      }

      if (resolvedOrgId.isEmpty) {
        resolvedOrgId = '0c621892-e938-4707-9957-13534ea32c19';
      }
      if (resolvedEmpUuid.isEmpty) {
        resolvedEmpUuid = user.dataId.isNotEmpty ? user.dataId : empId;
      }

      // Canonical 4-segment storage path: <org_uuid>/<emp_uuid>/documents/<filename>
      final storagePath = '$resolvedOrgId/$resolvedEmpUuid/documents/${DateTime.now().millisecondsSinceEpoch}_$cleanName';
      String fileUrl = '';

      // Read bytes (including from local filePath on mobile if bytes weren't preloaded)
      Uint8List? resolvedBytes = fileBytes != null ? Uint8List.fromList(fileBytes) : null;
      if ((resolvedBytes == null || resolvedBytes.isEmpty) &&
          _selectedFile!.filePath != null &&
          _selectedFile!.filePath!.isNotEmpty) {
        try {
          resolvedBytes = await File(_selectedFile!.filePath!).readAsBytes();
        } catch (readErr) {
          debugPrint('[DOC_UPLOAD] Failed reading local file bytes: $readErr');
        }
      }

      if (resolvedBytes == null || resolvedBytes.isEmpty) {
        throw Exception('Could not read file data. Please re-select the document file.');
      }

      // 1. Upload Binary to employee-documents Supabase Storage Bucket (Primary)
      debugPrint(
          '[DOC_UPLOAD] [1/3] Uploading binary bytes to Supabase storage "employee-documents" at: $storagePath');
      await client.storage.from('employee-documents').uploadBinary(
            storagePath,
            resolvedBytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      try {
        fileUrl = await client.storage
            .from('employee-documents')
            .createSignedUrl(storagePath, 31536000);
      } catch (signErr) {
        debugPrint('[DOC_UPLOAD] createSignedUrl notice: $signErr');
        fileUrl = storagePath;
      }
      debugPrint(
          '[DOC_UPLOAD] [1/3] Upload to employee-documents SUCCESS -> $storagePath');

      // 2. Resolve canonical document_type_id UUID from public.document_types
      String? resolvedDocTypeId;
      try {
        final targetType = (_req?.documentType ?? _req?.title ?? '').trim().toLowerCase();
        final typesRes = await client
            .from('document_types')
            .select('id, name, display_name, code')
            .limit(50);
        final list = List<Map<String, dynamic>>.from(typesRes as List);
        if (list.isNotEmpty) {
          Map<String, dynamic>? matched;
          if (targetType.isNotEmpty) {
            for (final row in list) {
              final idStr = row['id']?.toString() ?? '';
              final nameStr = (row['name']?.toString() ?? '').toLowerCase();
              final dispStr = (row['display_name']?.toString() ?? '').toLowerCase();
              final codeStr = (row['code']?.toString() ?? '').toLowerCase();
              if (idStr.toLowerCase() == targetType ||
                  codeStr == targetType ||
                  nameStr == targetType ||
                  dispStr == targetType ||
                  (nameStr.isNotEmpty && targetType.contains(nameStr)) ||
                  (dispStr.isNotEmpty && targetType.contains(dispStr))) {
                matched = row;
                break;
              }
            }
          }
          resolvedDocTypeId = (matched ?? list.first)['id']?.toString();
        }
      } catch (dtErr) {
        debugPrint('[DOC_UPLOAD] document_types lookup notice: $dtErr');
      }

      // 3. Insert canonical row in employee_documents (roll back binary if insert fails)
      final docId = _generateUuid();
      debugPrint(
          '[DOC_UPLOAD] [2/3] Inserting employee_documents row with ID: $docId, emp: $resolvedEmpUuid, org: $resolvedOrgId');
      try {
        await client.from('employee_documents').insert({
          'id': docId,
          'organization_id': resolvedOrgId,
          'employee_id': resolvedEmpUuid,
          if (resolvedDocTypeId != null && resolvedDocTypeId.isNotEmpty)
            'document_type_id': resolvedDocTypeId,
          'file_name': fileName,
          'storage_path': storagePath,
          'file_size_bytes': resolvedBytes.length,
          'mime_type': mimeType,
          'verification_status': 'PENDING',
        });
        debugPrint(
            '[DOC_UPLOAD] ✓ employee_documents row inserted successfully!');
      } catch (docErr) {
        debugPrint('[DOC_UPLOAD] employee_documents insert error: $docErr');
        try {
          await client.storage.from('employee-documents').remove([storagePath]);
        } catch (_) {}
        rethrow;
      }

      // 4. Update request status on document_requests / document_requirements
      final nowIso = DateTime.now().toIso8601String();
      try {
        await client.from('document_requests').update({
          'status': 'SUBMITTED',
          'updated_at': nowIso,
        }).eq('id', widget.requestId);
      } catch (_) {}
      try {
        await client.from('document_requirements').update({
          'status': 'SUBMITTED',
          'document_id': docId,
          'updated_at': nowIso,
        }).eq('id', widget.requestId);
      } catch (_) {}

      // 5. Notify HR Web via Realtime Notification Event
      try {
        final notifUuid = _generateUuid();
        await client.from('notification_events').insert({
          'id': notifUuid,
          'organization_id': resolvedOrgId,
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
            'document_id': docId,
            'employee_id': resolvedEmpUuid,
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
