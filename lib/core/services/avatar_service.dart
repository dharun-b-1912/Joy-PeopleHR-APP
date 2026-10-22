import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';
import 'media_compression_service.dart';
import 'user_service.dart';

class AvatarService {
  static final AvatarService instance = AvatarService._internal();
  AvatarService._internal();

  static const String canonicalBucket = 'employee-documents';
  static final RegExp _uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Authoritatively resolve valid RFC-4122 UUIDs for employee and organization
  Future<({String employeeUuid, String orgUuid})> _resolveAuthoritativeIds({
    String? employeeIdOverride,
    String? organizationIdOverride,
  }) async {
    final client = Supabase.instance.client;
    final user = UserService.instance.currentUser;

    String employeeUuid = '';
    String orgUuid = '';

    // 1. Direct check on overrides
    if (employeeIdOverride != null && _uuidRegex.hasMatch(employeeIdOverride.trim())) {
      employeeUuid = employeeIdOverride.trim();
    }
    if (organizationIdOverride != null && _uuidRegex.hasMatch(organizationIdOverride.trim())) {
      orgUuid = organizationIdOverride.trim();
    }

    // 2. Direct check on current user model
    if (employeeUuid.isEmpty && user.employeeUuid != null && _uuidRegex.hasMatch(user.employeeUuid!.trim())) {
      employeeUuid = user.employeeUuid!.trim();
    }
    if (employeeUuid.isEmpty && user.dataId.isNotEmpty && _uuidRegex.hasMatch(user.dataId.trim())) {
      employeeUuid = user.dataId.trim();
    }

    if (orgUuid.isEmpty && user.organizationId != null && _uuidRegex.hasMatch(user.organizationId!.trim())) {
      orgUuid = user.organizationId!.trim();
    }

    // 3. Resolve from Supabase authenticated user session
    final authUser = client.auth.currentUser;
    if (authUser != null && (employeeUuid.isEmpty || orgUuid.isEmpty)) {
      try {
        final profile = await client
            .from('user_profiles')
            .select('id, employee_id, organization_id')
            .or('auth_user_id.eq.${authUser.id},id.eq.${authUser.id}')
            .maybeSingle();

        if (profile != null) {
          final pEmpId = profile['employee_id']?.toString() ?? '';
          final pOrgId = profile['organization_id']?.toString() ?? '';
          if (employeeUuid.isEmpty && _uuidRegex.hasMatch(pEmpId)) {
            employeeUuid = pEmpId;
          }
          if (orgUuid.isEmpty && _uuidRegex.hasMatch(pOrgId)) {
            orgUuid = pOrgId;
          }
        }
      } catch (e) {
        secureLog('[AvatarService] user_profiles resolution notice: $e');
      }
    }

    // 4. Resolve from employees table by code or email if still not a UUID
    if (employeeUuid.isEmpty || orgUuid.isEmpty) {
      try {
        final candidateCodes = [
          user.employeeId,
          if (employeeIdOverride != null) employeeIdOverride,
          user.dataId,
        ].where((c) => c.isNotEmpty).toSet().toList();

        for (final code in candidateCodes) {
          final empRow = await client
              .from('employees')
              .select('id, organization_id')
              .eq('employee_code', code)
              .maybeSingle();

          if (empRow != null) {
            final eId = empRow['id']?.toString() ?? '';
            final oId = empRow['organization_id']?.toString() ?? '';
            if (employeeUuid.isEmpty && _uuidRegex.hasMatch(eId)) {
              employeeUuid = eId;
            }
            if (orgUuid.isEmpty && _uuidRegex.hasMatch(oId)) {
              orgUuid = oId;
            }
            if (employeeUuid.isNotEmpty && orgUuid.isNotEmpty) break;
          }
        }
      } catch (e) {
        secureLog('[AvatarService] employees table lookup notice: $e');
      }
    }

    // Fallback defaults if still empty
    if (orgUuid.isEmpty) {
      orgUuid = '0c621892-e938-4707-9957-13534ea32c19';
    }

    return (employeeUuid: employeeUuid, orgUuid: orgUuid);
  }

  /// Upload and activate employee avatar with canonical storage path
  /// Path format: <organization_uuid>/<employee_uuid>/documents/avatar_<timestamp>.jpg
  /// Strictly satisfies PostgreSQL Storage RLS can_access_storage_object()
  Future<String?> uploadAndActivateAvatar({
    required Uint8List imageBytes,
    String? fileName,
    String? employeeIdOverride,
    String? organizationIdOverride,
  }) async {
    return uploadAndActivateAvatarBytes(
      imageBytes,
      fileName: fileName,
      employeeIdOverride: employeeIdOverride,
      organizationIdOverride: organizationIdOverride,
    );
  }

  /// Upload avatar bytes
  Future<String?> uploadAndActivateAvatarBytes(
    Uint8List imageBytes, {
    String? fileName,
    String? employeeIdOverride,
    String? organizationIdOverride,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;

    final resolved = await _resolveAuthoritativeIds(
      employeeIdOverride: employeeIdOverride,
      organizationIdOverride: organizationIdOverride,
    );

    final employeeUuid = resolved.employeeUuid;
    final orgId = resolved.orgUuid;

    if (employeeUuid.isEmpty) {
      secureLog('[AvatarService] Error: No valid employee UUID found for storage upload');
      return null;
    }

    try {
      final client = Supabase.instance.client;
      final fileTimestamp = DateTime.now().millisecondsSinceEpoch;
      // Canonical 4-segment path: <org_uuid>/<emp_uuid>/documents/<filename>
      // Segment 3 MUST be 'documents' for employee-documents bucket per can_access_storage_object()
      final canonicalPath = '$orgId/$employeeUuid/documents/avatar_$fileTimestamp.jpg';
      const targetBucket = canonicalBucket;

      Uint8List bytesToUpload = imageBytes;
      if (!kIsWeb && imageBytes.lengthInBytes > 250 * 1024) {
        try {
          final compResult = await MediaCompressionService.instance.compressReceiptImage(
            inputBytes: imageBytes,
            fileName: 'avatar.jpg',
            targetQuality: 88,
            maxDimension: 1024,
          );
          if (compResult.wasCompressed) {
            bytesToUpload = compResult.bytes;
            secureLog('[AvatarService] Avatar compressed for upload: ${compResult.summary}');
          }
        } catch (e) {
          secureLog('[AvatarService] Avatar pre-compression notice: $e');
        }
      }

      secureLog('[AvatarService] Uploading avatar to $targetBucket at $canonicalPath (${bytesToUpload.lengthInBytes} bytes)');

      await client.storage.from(targetBucket).uploadBinary(
        canonicalPath,
        bytesToUpload,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
          cacheControl: '3600',
        ),
      );

      // Generate a 1-year (31,536,000s) signed URL for universal cross-platform rendering
      final signedUrl = await client.storage
          .from(targetBucket)
          .createSignedUrl(canonicalPath, 31536000);

      secureLog('[AvatarService] Avatar upload succeeded, generated signed URL: $signedUrl');

      final user = UserService.instance.currentUser;
      final nowIso = DateTime.now().toIso8601String();

      // 1. Update employees table by id (UUID)
      try {
        await client.from('employees').update({
          'avatar_url': signedUrl,
          'updated_at': nowIso,
        }).eq('id', employeeUuid);
        secureLog('[AvatarService] Updated employees table by id: $employeeUuid');
      } catch (empErr) {
        secureLog('[AvatarService] Notice updating employees by id: $empErr');
      }

      // Also update by employee_code if known
      if (user.employeeId.isNotEmpty) {
        try {
          await client.from('employees').update({
            'avatar_url': signedUrl,
            'updated_at': nowIso,
          }).eq('employee_code', user.employeeId);
        } catch (_) {}
      }

      // 2. Update user_profiles table if user is authenticated
      final authUser = client.auth.currentUser;
      if (authUser != null) {
        try {
          await client.from('user_profiles').update({
            'avatar_url': signedUrl,
            'updated_at': nowIso,
          }).or('auth_user_id.eq.${authUser.id},id.eq.${authUser.id}');
          secureLog('[AvatarService] Updated user_profiles table for authUser: ${authUser.id}');
        } catch (upErr) {
          secureLog('[AvatarService] Notice updating user_profiles: $upErr');
        }
      }

      // 3. Update in-memory UserService state immediately
      UserService.instance.updateProfileImage(signedUrl);
      if (user.employeeUuid == null || user.employeeUuid!.isEmpty) {
        UserService.instance.setUser(user.copyWith(
          employeeUuid: employeeUuid,
          profileImage: signedUrl,
        ));
      }

      return signedUrl;
    } catch (e) {
      secureLog('[AvatarService] uploadAndActivateAvatar error: $e');
      rethrow;
    }
  }

  /// Remove avatar
  Future<bool> removeAvatar({String? employeeIdOverride}) async {
    if (!SupabaseConfig.isConfigured) return false;

    final resolved = await _resolveAuthoritativeIds(
      employeeIdOverride: employeeIdOverride,
    );
    final employeeUuid = resolved.employeeUuid;
    if (employeeUuid.isEmpty) return false;

    try {
      final client = Supabase.instance.client;
      final user = UserService.instance.currentUser;
      final nowIso = DateTime.now().toIso8601String();

      await client.from('employees').update({
        'avatar_url': null,
        'updated_at': nowIso,
      }).eq('id', employeeUuid);

      if (user.employeeId.isNotEmpty) {
        try {
          await client.from('employees').update({
            'avatar_url': null,
            'updated_at': nowIso,
          }).eq('employee_code', user.employeeId);
        } catch (_) {}
      }

      final authUser = client.auth.currentUser;
      if (authUser != null) {
        try {
          await client.from('user_profiles').update({
            'avatar_url': null,
            'updated_at': nowIso,
          }).or('auth_user_id.eq.${authUser.id},id.eq.${authUser.id}');
        } catch (_) {}
      }

      UserService.instance.updateProfileImage('');
      secureLog('[AvatarService] Removed avatar for employee: $employeeUuid');
      return true;
    } catch (e) {
      secureLog('[AvatarService] removeAvatar error: $e');
      return false;
    }
  }

  /// Generate short-lived or long-lived signed URL for avatar display
  Future<String?> getSignedAvatarUrl(String? avatarPathOrUrl, {int expiresIn = 31536000}) async {
    if (avatarPathOrUrl == null || avatarPathOrUrl.isEmpty) return null;

    if (avatarPathOrUrl.startsWith('http://') || avatarPathOrUrl.startsWith('https://') || avatarPathOrUrl.startsWith('data:')) {
      return avatarPathOrUrl;
    }

    try {
      final client = Supabase.instance.client;
      final signedUrl = await client.storage
          .from(canonicalBucket)
          .createSignedUrl(avatarPathOrUrl, expiresIn);
      return signedUrl;
    } catch (e) {
      secureLog('[AvatarService] getSignedAvatarUrl error: $e');
      return null;
    }
  }
}
