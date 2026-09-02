import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';
import 'media_compression_service.dart';
import 'realtime_outbox_service.dart';
import 'user_service.dart';

class DocumentUploadService {
  static final DocumentUploadService instance = DocumentUploadService._internal();
  DocumentUploadService._internal();

  SupabaseClient get _supabase => Supabase.instance.client;

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
  Future<String?> getSignedUrl(String pathOrUrl, {int expiresIn = 3600}) async {
    try {
      if (!SupabaseConfig.isConfigured) return null;
      final cleanPath = extractStoragePath(pathOrUrl);
      if (cleanPath.isEmpty) return null;

      final signedUrl = await _supabase.storage
          .from('employee-documents')
          .createSignedUrl(cleanPath, expiresIn);
      return signedUrl;
    } catch (e) {
      secureLog('[Storage] createSignedUrl error: $e');
      try {
        final cleanPath = extractStoragePath(pathOrUrl);
        return _supabase.storage.from('employee-documents').getPublicUrl(cleanPath);
      } catch (_) {
        return null;
      }
    }
  }

  /// Download file bytes from Supabase Storage
  Future<Uint8List?> downloadFileBytes(String pathOrUrl) async {
    try {
      if (!SupabaseConfig.isConfigured) return null;
      final cleanPath = extractStoragePath(pathOrUrl);
      final bytes = await _supabase.storage.from('employee-documents').download(cleanPath);
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
    try {
      if (!SupabaseConfig.isConfigured) return null;
      final sanitizedName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = 'tenants/$tenantId/services/$employeeId/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';
      try {
        await _supabase.storage.from('employee-documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );
        final url = _supabase.storage.from('employee-documents').getPublicUrl(path);
        return url;
      } catch (e) {
        secureLog('[Storage] Document upload notice: $e');
        return 'storage://employee-documents/$path';
      }
    } catch (e) {
      secureLog('[Storage] uploadDocument error: $e');
      return null;
    }
  }

  /// Upload receipt proof (photo/PDF) to multi-tenant Supabase Storage pool
  /// with automatic quality-preserving compression for images.
  Future<String?> uploadExpenseReceipt({
    required String tenantId,
    required String employeeId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      if (!SupabaseConfig.isConfigured) return null;

      // 1. Perform smart quality-preserving compression
      final compResult = await MediaCompressionService.instance.compressReceiptImage(
        inputBytes: bytes,
        fileName: fileName,
        targetQuality: 85,
        maxDimension: 1920,
      );

      final sanitizedName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = 'tenants/$tenantId/claims/$employeeId/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';

      try {
        await _supabase.storage.from('employee-documents').uploadBinary(
          path,
          compResult.bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );
        final url = _supabase.storage.from('employee-documents').getPublicUrl(path);
        secureLog('[Storage] Uploaded receipt ($path) | ${compResult.summary}');
        return url;
      } catch (e) {
        secureLog('[Storage] Receipt upload notice: $e');
        return 'storage://employee-documents/$path';
      }
    } catch (e) {
      secureLog('[Storage] uploadExpenseReceipt error: $e');
      return null;
    }
  }

  /// Upload file bytes or binary to Supabase Storage bucket 'employee-documents'
  /// and index in authoritative 'employee_documents' table.
  Future<String?> uploadEmployeeDocument({
    required String employeeId,
    required String documentType,
    required String fileName,
    Uint8List? bytes,
    File? file,
    String? documentCategory,
    String? tenantId,
    String? employeeName,
  }) async {
    try {
      if (!SupabaseConfig.isConfigured) return null;
      if (employeeId.isEmpty) {
        secureLog('[Storage] Error: employeeId cannot be empty for uploadEmployeeDocument');
        return null;
      }

      Uint8List? fileBytes = bytes;
      if (fileBytes == null && file != null) {
        if (await file.exists()) {
          fileBytes = await file.readAsBytes();
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        secureLog('[Storage] Error: No file bytes provided for upload');
        return null;
      }

      final sanitizedName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final docId = 'doc-${DateTime.now().millisecondsSinceEpoch}';
      final path = 'employees/$employeeId/documents/$docId/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';

      String fileUrl = '';

      // 1. Upload file binary to Supabase Storage bucket 'employee-documents'
      try {
        await _supabase.storage.from('employee-documents').uploadBinary(
          path,
          fileBytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );
        fileUrl = _supabase.storage.from('employee-documents').getPublicUrl(path);
        secureLog('[Storage] Successfully uploaded document to employee-documents/$path');
      } catch (e) {
        secureLog('[Storage] Storage upload notice: $e');
        fileUrl = 'storage://employee-documents/$path';
      }

      final fileSize = fileBytes.length;

      // 2. Index record in authoritative 'employee_documents' table (Exact database schema)
      try {
        final normalizedCat = _normalizeDocumentCategory(documentCategory, documentType);
        final user = UserService.instance.currentUser;
        final orgTenantId = (tenantId?.isNotEmpty == true) ? tenantId! : user.tenantId;

        final payload = {
          'id': docId,
          'employee_id': employeeId,
          if (orgTenantId.isNotEmpty) 'tenant_id': orgTenantId,
          'document_category': normalizedCat,
          'document_type': documentType,
          'file_name': fileName,
          'file_url': fileUrl.isNotEmpty ? fileUrl : 'storage://employee-documents/$path',
          'file_size_bytes': fileSize,
          'verification_status': 'Pending',
          'uploaded_at': DateTime.now().toIso8601String(),
        };

        await _supabase.from('employee_documents').insert(payload);
        secureLog('[Storage] Successfully indexed record in employee_documents table: $docId');

        // Broadcast to realtime_outbox via centralized service
        await RealtimeOutboxService.insertEvent(
          entityType: 'employee_documents',
          eventType: 'document.uploaded',
          entityId: docId,
          tenantId: orgTenantId,
          actorId: employeeId,
          payload: payload,
        );
      } catch (e) {
        secureLog('[Storage] employee_documents table insert error: $e');
      }

      return fileUrl.isNotEmpty ? fileUrl : path;
    } catch (e) {
      secureLog('[Storage] uploadEmployeeDocument error: $e');
      return null;
    }
  }

  static String _normalizeDocumentCategory(String? category, String docType) {
    final combined = '${category ?? ''} $docType'.toUpperCase();
    if (combined.contains('IDENTITY') ||
        combined.contains('LICENSE') ||
        combined.contains('LICENCE') ||
        combined.contains('AADHAAR') ||
        combined.contains('PAN') ||
        combined.contains('PASSPORT') ||
        combined.contains('VOTER')) {
      return 'Identity';
    }
    if (combined.contains('EDUCATION') ||
        combined.contains('DEGREE') ||
        combined.contains('DIPLOMA') ||
        combined.contains('CERTIFICATE') ||
        combined.contains('MARKSHEET') ||
        combined.contains('10TH') ||
        combined.contains('12TH')) {
      return 'Education';
    }
    return 'Other';
  }

  /// Permanently delete document from employee_documents table and storage bucket
  Future<bool> deleteDocument(String documentId, {String? storagePath, String? fileUrl}) async {
    try {
      if (!SupabaseConfig.isConfigured) return false;
      final user = UserService.instance.currentUser;

      // 1. Delete from storage bucket if path or url exists
      final targetPath = storagePath ?? fileUrl;
      if (targetPath != null && targetPath.isNotEmpty) {
        try {
          final cleanPath = extractStoragePath(targetPath);
          if (cleanPath.isNotEmpty) {
            await _supabase.storage.from('employee-documents').remove([cleanPath]);
          }
        } catch (storageErr) {
          secureLog('[Storage] File removal notice: $storageErr');
        }
      }

      // 2. Delete from database table employee_documents
      await _supabase.from('employee_documents').delete().eq('id', documentId);

      // 3. Broadcast deletion event to realtime_outbox via centralized service
      await RealtimeOutboxService.insertEvent(
        entityType: 'employee_documents',
        eventType: 'document.deleted',
        entityId: documentId,
        tenantId: user.tenantId,
        actorId: user.resolvedEmployeeId,
        payload: {'id': documentId, 'deleted': true},
      );

      secureLog('[Storage] Document $documentId permanently deleted');
      return true;
    } catch (e) {
      secureLog('[Storage] deleteDocument error: $e');
      return false;
    }
  }
}
