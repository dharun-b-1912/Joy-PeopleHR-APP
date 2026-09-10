import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';
import 'user_service.dart';

class AvatarService {
  static final AvatarService instance = AvatarService._internal();
  AvatarService._internal();

  static const String canonicalBucket = 'employee-profile-pictures';
  static const String fallbackBucket = 'employee-documents';

  /// Upload and activate employee avatar with canonical storage path
  /// Path format: <organization_uuid>/<employee_uuid>/profile/<file_uuid>.jpg
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

    final user = UserService.instance.currentUser;
    final employeeId = (employeeIdOverride != null && employeeIdOverride.isNotEmpty)
        ? employeeIdOverride
        : (user.employeeId.isNotEmpty
            ? user.employeeId
            : user.dataId);

    final orgId = (organizationIdOverride != null && organizationIdOverride.isNotEmpty)
        ? organizationIdOverride
        : (user.organizationId != null && user.organizationId!.isNotEmpty
            ? user.organizationId!
            : '0c621892-e938-4707-9957-13534ea32c19');

    if (employeeId.isEmpty) {
      secureLog('[AvatarService] Error: No active employee ID found');
      return null;
    }

    try {
      final client = Supabase.instance.client;
      final fileUuid = 'avt_${DateTime.now().millisecondsSinceEpoch}_${employeeId.length > 8 ? employeeId.substring(0, 8) : employeeId}';
      final canonicalPath = '$orgId/$employeeId/profile/$fileUuid.jpg';
      String targetBucket = canonicalBucket;

      try {
        await client.storage.from(targetBucket).uploadBinary(
          canonicalPath,
          imageBytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
            cacheControl: '3600',
          ),
        );
      } catch (uploadErr) {
        secureLog('[AvatarService] Canonical bucket upload note: $uploadErr. Trying fallback bucket.');
        targetBucket = fallbackBucket;
        await client.storage.from(targetBucket).uploadBinary(
          canonicalPath,
          imageBytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
            cacheControl: '3600',
          ),
        );
      }

      // Update employee record with canonical storage path
      await client.from('employees').update({
        'avatar_url': canonicalPath,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', employeeId);

      secureLog('[AvatarService] Successfully updated employee avatar_url to: $canonicalPath');

      // Generate signed URL for immediate view
      final signedUrl = await getSignedAvatarUrl(canonicalPath);
      return signedUrl;
    } catch (e) {
      secureLog('[AvatarService] uploadAndActivateAvatar error: $e');
      return null;
    }
  }

  /// Remove avatar
  Future<bool> removeAvatar({String? employeeIdOverride}) async {
    if (!SupabaseConfig.isConfigured) return false;

    final user = UserService.instance.currentUser;
    final employeeId = (employeeIdOverride != null && employeeIdOverride.isNotEmpty)
        ? employeeIdOverride
        : (user.employeeId.isNotEmpty
            ? user.employeeId
            : user.dataId);

    if (employeeId.isEmpty) return false;

    try {
      final client = Supabase.instance.client;
      await client.from('employees').update({
        'avatar_url': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', employeeId);

      secureLog('[AvatarService] Removed avatar for employee: $employeeId');
      return true;
    } catch (e) {
      secureLog('[AvatarService] removeAvatar error: $e');
      return false;
    }
  }

  /// Generate short-lived signed URL for avatar display
  Future<String?> getSignedAvatarUrl(String? avatarPathOrUrl, {int expiresIn = 3600}) async {
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
    } catch (_) {
      try {
        final client = Supabase.instance.client;
        final signedUrl = await client.storage
            .from(fallbackBucket)
            .createSignedUrl(avatarPathOrUrl, expiresIn);
        return signedUrl;
      } catch (e) {
        secureLog('[AvatarService] getSignedAvatarUrl error: $e');
        return null;
      }
    }
  }
}
