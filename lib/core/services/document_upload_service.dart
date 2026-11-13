import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';
import 'media_compression_service.dart';
import 'realtime_outbox_service.dart';

class DocumentUploadService {
  static final DocumentUploadService instance = DocumentUploadService._internal();
  DocumentUploadService._internal();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Human-readable error message from the most recent failed upload attempt.
  String? lastError;

  /// Extract raw storage path from a file URL or storage URI
  String extractStoragePath(String rawUrl) {
    if (rawUrl.startsWith('storage://employee-documents/')) {
      return rawUrl.replaceFirst('storage://employee-documents/', '');
    }
    if (rawUrl.contains('/employee-documents/')) {
      final idx = rawUrl.indexOf('/employee-documents/');
      return rawUrl.substring(idx + '/employee-documents/'.length).split('?').first;
    }
    return rawUrl;
  }

  /// Generate a secure signed URL for private bucket access (valid for 1 hour)
  Future<String?> getSignedUrl(String pathOrUrl, {String bucket = 'employee-documents', int expiresIn = 3600}) async {
    try {
      if (!SupabaseConfig.isConfigured) return null;
      final cleanPath = extractStoragePath(pathOrUrl);
      if (cleanPath.isEmpty) return null;

      final signedUrl = await _supabase.storage
          .from(bucket)
          .createSignedUrl(cleanPath, expiresIn);
      return signedUrl;
    } catch (e) {
      secureLog('[Storage] createSignedUrl error: $e');
      return null;
    }
  }

  /// Download file bytes from Supabase Storage
  Future<Uint8List?> downloadFileBytes(String pathOrUrl, {String bucket = 'employee-documents'}) async {
    try {
      if (!SupabaseConfig.isConfigured) return null;
      final cleanPath = extractStoragePath(pathOrUrl);
      final bytes = await _supabase.storage.from(bucket).download(cleanPath);
      return bytes;
    } catch (e) {
      secureLog('[Storage] downloadFileBytes error: $e');
      return null;
    }
  }

  /// Upload generic document/attachment bytes to multi-tenant Supabase Storage pool
  Future<String?> uploadDocument({
    required String tenantId,
    required String employeeId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    return uploadEmployeeDocument(
      employeeId: employeeId,
      documentType: 'ATTACHMENT',
      fileName: fileName,
      bytes: bytes,
      organizationId: tenantId,
    );
  }

  /// Upload receipt proof (photo/PDF) to multi-tenant Supabase Storage pool
  Future<String?> uploadExpenseReceipt({
    required String tenantId,
    required String employeeId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      if (!SupabaseConfig.isConfigured) return null;

      final compResult = await MediaCompressionService.instance.compressReceiptImage(
        inputBytes: bytes,
        fileName: fileName,
        targetQuality: 85,
        maxDimension: 1920,
      );

      return await uploadEmployeeDocument(
        employeeId: employeeId,
        documentType: 'RECEIPT',
        fileName: fileName,
        bytes: compResult.bytes,
        organizationId: tenantId,
      );
    } catch (e) {
      secureLog('[Storage] uploadExpenseReceipt error: $e');
      return null;
    }
  }

  /// Upload file bytes or binary to Supabase Storage bucket 'employee-documents'
  /// Canonical Path: <organization_uuid>/<employee_uuid>/documents/<file_uuid>.<extension>
  Future<String?> uploadEmployeeDocument({
    required String employeeId,
    required String documentType,
    required String fileName,
    String? documentTypeId,
    Uint8List? bytes,
    File? file,
    String? documentCategory,
    String? tenantId,
    String? employeeName,
    String? organizationId,
  }) async {
    try {
      if (!SupabaseConfig.isConfigured) {
        secureLog('[Storage] Error: Supabase is not configured.');
        return null;
      }

      final authUser = _supabase.auth.currentUser;
      if (authUser == null) {
        secureLog('[Storage] Error: No authenticated Supabase session.');
        return null;
      }

      // 1. Resolve canonical identity strictly following architecture rules:
      // auth.uid() -> user_profiles -> employee_id -> employees -> organization_id
      String resolvedOrgId = organizationId ?? tenantId ?? '';
      String resolvedEmpId = employeeId;

      try {
        final profileRes = await _supabase
            .from('user_profiles')
            .select('id, organization_id, employee_id')
            .or('auth_user_id.eq.${authUser.id},id.eq.${authUser.id}')
            .maybeSingle();

        if (profileRes != null) {
          final upEmpId = profileRes['employee_id']?.toString() ?? '';
          final upProfileId = profileRes['id']?.toString() ?? '';

          // Look up canonical employees row by id or user_id to ensure UUID
          var empQuery = _supabase.from('employees').select('id, organization_id');
          if (upEmpId.isNotEmpty) {
            empQuery = empQuery.or('id.eq.$upEmpId,user_id.eq.$upProfileId');
          } else {
            empQuery = empQuery.eq('user_id', upProfileId);
          }

          final empRes = await empQuery.limit(1).maybeSingle();
          if (empRes != null) {
            resolvedEmpId = empRes['id']?.toString() ?? resolvedEmpId;
            resolvedOrgId = empRes['organization_id']?.toString() ?? resolvedOrgId;
          } else {
            resolvedOrgId = profileRes['organization_id']?.toString() ?? resolvedOrgId;
            resolvedEmpId = upEmpId.isNotEmpty ? upEmpId : resolvedEmpId;
          }
        }
      } catch (e) {
        secureLog('[Storage] Strict identity resolution notice: $e');
      }

      if (resolvedEmpId.isEmpty || resolvedOrgId.isEmpty) {
        secureLog('[Storage] Error: Could not resolve employee_id ($resolvedEmpId) or organization_id ($resolvedOrgId)');
        return null;
      }

      // 2. Prepare file bytes
      Uint8List? fileBytes = bytes;
      if (fileBytes == null && file != null) {
        if (await file.exists()) {
          fileBytes = await file.readAsBytes();
        }
      }

      lastError = null;
      if (fileBytes == null || fileBytes.isEmpty) {
        lastError = 'No file content found. Please re-select the document.';
        secureLog('[Storage] Error: No file bytes provided for upload');
        return null;
      }

      // Validate max file size (20MB = 20971520 bytes)
      if (fileBytes.length > 20971520) {
        lastError = 'File exceeds maximum allowed size of 20 MB.';
        secureLog('[Storage] Error: File size (${fileBytes.length} bytes) exceeds 20MB limit');
        return null;
      }

      // 3. Resolve document_type_id from public.document_types
      String? resolvedDocTypeId = documentTypeId;
      if (resolvedDocTypeId == null || resolvedDocTypeId.isEmpty) {
        try {
          final cleanType = documentType.replaceAll(RegExp(r'[^a-zA-Z0-9_\s]'), '').trim();
          final dtRes = await _supabase
              .from('document_types')
              .select('id, name, display_name, code')
              .or('name.ilike.%$cleanType%,display_name.ilike.%$cleanType%,code.ilike.%$cleanType%')
              .limit(1)
              .maybeSingle();

          if (dtRes != null) {
            resolvedDocTypeId = dtRes['id']?.toString();
          } else {
            // Fallback: get first available document_type
            final fallbackDt = await _supabase
                .from('document_types')
                .select('id')
                .limit(1)
                .maybeSingle();
            if (fallbackDt != null) {
              resolvedDocTypeId = fallbackDt['id']?.toString();
            }
          }
        } catch (e) {
          secureLog('[Storage] Document type resolution notice: $e');
        }
      }

      if (resolvedDocTypeId == null || resolvedDocTypeId.isEmpty) {
        lastError = 'Document type configuration not found for "$documentType".';
        secureLog('[Storage] Error: Could not resolve document_type_id for "$documentType"');
        return null;
      }

      // 4. Generate canonical storage path
      final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.')).toLowerCase() : '.pdf';
      final fileUuid = 'f_${DateTime.now().millisecondsSinceEpoch}_${resolvedEmpId.substring(0, resolvedEmpId.length >= 8 ? 8 : resolvedEmpId.length)}';
      final canonicalPath = '$resolvedOrgId/$resolvedEmpId/documents/$fileUuid$ext';
      const bucketName = 'employee-documents';

      String mimeType = 'application/pdf';
      if (ext == '.png') {
        mimeType = 'image/png';
      } else if (ext == '.jpg' || ext == '.jpeg' || ext == '.jfif') {
        mimeType = 'image/jpeg';
      } else if (ext == '.webp') {
        mimeType = 'image/webp';
      } else if (ext == '.gif') {
        mimeType = 'image/gif';
      } else if (ext == '.doc') {
        mimeType = 'application/msword';
      } else if (ext == '.docx') {
        mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      }

      // 5. Upload binary to Supabase Storage bucket 'employee-documents'
      try {
        await _supabase.storage.from(bucketName).uploadBinary(
          canonicalPath,
          fileBytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: mimeType,
          ),
        );
        secureLog('[Storage] Successfully uploaded document binary to $bucketName/$canonicalPath');
      } catch (e) {
        lastError = 'Storage upload failed: $e';
        secureLog('[Storage] Storage upload error: $e');
        return null;
      }

      final fileSize = fileBytes.length;

      // 6. Insert metadata record in canonical 'employee_documents' table
      try {
        final payload = <String, dynamic>{
          'organization_id': resolvedOrgId,
          'employee_id': resolvedEmpId,
          'document_type_id': resolvedDocTypeId,
          'file_name': fileName,
          'storage_path': canonicalPath,
          'file_size_bytes': fileSize,
          'mime_type': mimeType,
          'verification_status': 'PENDING',
        };

        final insertRes = await _supabase.from('employee_documents').insert(payload).select('id').single();
        final docId = insertRes['id'] as String;
        secureLog('[Storage] Successfully inserted metadata in employee_documents table: $docId');

        // Broadcast to realtime_outbox
        try {
          await RealtimeOutboxService.insertEvent(
            entityType: 'employee_documents',
            eventType: 'document.uploaded',
            entityId: docId,
            tenantId: resolvedOrgId,
            actorId: resolvedEmpId,
            payload: payload,
          );
        } catch (_) {}

        return canonicalPath;
      } catch (e) {
        lastError = 'Database record save failed: $e';
        secureLog('[Storage] employee_documents table insert error: $e. Rolling back uploaded storage binary.');
        try {
          await _supabase.storage.from(bucketName).remove([canonicalPath]);
        } catch (_) {}
        return null;
      }
    } catch (e) {
      lastError ??= 'Document upload error: $e';
      secureLog('[Storage] uploadEmployeeDocument fatal exception: $e');
      return null;
    }
  }

  /// Delete document by ID from database and storage
  Future<bool> deleteDocument(String documentId, {String? storagePath, String? fileUrl}) async {
    try {
      if (!SupabaseConfig.isConfigured) return false;

      String? pathToDelete = storagePath ?? fileUrl;
      if (pathToDelete == null || pathToDelete.isEmpty) {
        final doc = await _supabase
            .from('employee_documents')
            .select('storage_path')
            .eq('id', documentId)
            .maybeSingle();
        if (doc != null) {
          pathToDelete = doc['storage_path'] as String?;
        }
      }

      await _supabase.from('employee_documents').delete().eq('id', documentId);

      if (pathToDelete != null && pathToDelete.isNotEmpty) {
        await _supabase.storage.from('employee-documents').remove([extractStoragePath(pathToDelete)]);
      }

      return true;
    } catch (e) {
      secureLog('[Storage] deleteDocument error: $e');
      return false;
    }
  }
}
