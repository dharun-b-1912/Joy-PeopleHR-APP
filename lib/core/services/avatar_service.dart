import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_service.dart';
import '../utils/secure_log.dart';

/// Representation of processed responsive variants from single high-quality master
class AvatarMultiVariants {
  final Uint8List master;
  final Uint8List large;  // 512x512
  final Uint8List medium; // 256x256
  final Uint8List small;  // 96x96

  const AvatarMultiVariants({
    required this.master,
    required this.large,
    required this.medium,
    required this.small,
  });
}

/// Enterprise Canonical Avatar Management Service for Flutter (Web & Native compatible)
class AvatarService {
  AvatarService._();
  static final AvatarService instance = AvatarService._();

  static const String storageBucket = 'workforce-avatars';
  static const String fallbackBucket = 'profile-media';

  /// Process uncompressed crop source into crisp Master + Derived Variants
  Future<AvatarMultiVariants> processMultiVariants(Uint8List imageBytes) async {
    try {
      if (kIsWeb) {
        // On Web, imageBytes are already processed by HTML5 canvas/camera
        return AvatarMultiVariants(
          master: imageBytes,
          large: imageBytes,
          medium: imageBytes,
          small: imageBytes,
        );
      }

      // Generate all 3 variants directly from original source crop to prevent degradation
      final master = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 1024,
        minHeight: 1024,
        quality: 92,
        format: CompressFormat.jpeg,
      );

      final large = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 512,
        minHeight: 512,
        quality: 90,
        format: CompressFormat.jpeg,
      );

      final medium = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 256,
        minHeight: 256,
        quality: 90,
        format: CompressFormat.jpeg,
      );

      final small = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 96,
        minHeight: 96,
        quality: 88,
        format: CompressFormat.jpeg,
      );

      return AvatarMultiVariants(
        master: master,
        large: large,
        medium: medium,
        small: small,
      );
    } catch (e) {
      secureLog('[AvatarService] Compression note: $e');
      return AvatarMultiVariants(
        master: imageBytes,
        large: imageBytes,
        medium: imageBytes,
        small: imageBytes,
      );
    }
  }

  /// Upload, replace, and activate canonical avatar with atomic versioning & storage fallback
  Future<String?> uploadAndActivateAvatarBytes(Uint8List imageBytes, {String? fileName}) async {
    final user = UserService.instance.currentUser;
    final employeeId = user.employeeUuid ?? user.employeeId;
    final tenantId = user.companyId.isNotEmpty
        ? user.companyId
        : (user.organizationId?.isNotEmpty == true ? user.organizationId! : '');

    if (employeeId.isEmpty) {
      secureLog('[AvatarService] Error: No active employee ID found');
      return null;
    }

    try {
      final client = Supabase.instance.client;
      final variants = await processMultiVariants(imageBytes);

      // 1. Fetch current employee version
      int currentVersion = 1;

      try {
        final empRow = await client
            .from('employees')
            .select('avatar_version, avatar_asset_id, avatar_url')
            .eq('id', employeeId)
            .maybeSingle();

        if (empRow != null) {
          currentVersion = (empRow['avatar_version'] as int?) ?? 1;
        }
      } catch (_) {}

      final nextVersion = currentVersion + 1;
      final basePath = 'avatars/tenant/$tenantId/organisation/$tenantId/employee/$employeeId/v/$nextVersion';
      final masterPath = '$basePath/master.jpg';
      final largePath = '$basePath/512.jpg';
      final mediumPath = '$basePath/256.jpg';
      final smallPath = '$basePath/96.jpg';
      final assetId = 'avt-${DateTime.now().millisecondsSinceEpoch}';

      // 2. Upload new versioned object (with fallback to data URI if storage bucket is not configured)
      String targetBucket = storageBucket;
      String activeUrl;
      bool storageUploadSucceeded = false;

      try {
        await client.storage.from(targetBucket).uploadBinary(
          masterPath,
          variants.master,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
        final publicUrl = client.storage.from(targetBucket).getPublicUrl(masterPath);
        activeUrl = '$publicUrl?v=$nextVersion';
        storageUploadSucceeded = true;

        // Upload derived variants in parallel
        await Future.wait([
          client.storage.from(targetBucket).uploadBinary(
            largePath,
            variants.large,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          ),
          client.storage.from(targetBucket).uploadBinary(
            mediumPath,
            variants.medium,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          ),
          client.storage.from(targetBucket).uploadBinary(
            smallPath,
            variants.small,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          ),
        ]);
      } catch (uploadErr) {
        secureLog('[AvatarService] Primary bucket note, trying fallback bucket: $uploadErr');
        try {
          targetBucket = fallbackBucket;
          await client.storage.from(targetBucket).uploadBinary(
            masterPath,
            variants.master,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
          final publicUrl = client.storage.from(targetBucket).getPublicUrl(masterPath);
          activeUrl = '$publicUrl?v=$nextVersion';
          storageUploadSucceeded = true;

          await Future.wait([
            client.storage.from(targetBucket).uploadBinary(
              largePath,
              variants.large,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            ),
            client.storage.from(targetBucket).uploadBinary(
              mediumPath,
              variants.medium,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            ),
            client.storage.from(targetBucket).uploadBinary(
              smallPath,
              variants.small,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            ),
          ]);
        } catch (fallbackErr) {
          secureLog('[AvatarService] Storage bucket unavailable, using high-res data URI: $fallbackErr');
          final base64String = base64Encode(variants.large);
          activeUrl = 'data:image/jpeg;base64,$base64String';
          targetBucket = 'data-uri';
        }
      }

      // 3. Create Canonical Avatar Asset record
      try {
        await client.from('employee_avatar_assets').insert({
          'id': assetId,
          'tenant_id': tenantId,
          'organisation_id': tenantId,
          'employee_id': employeeId,
          'storage_bucket': targetBucket,
          'storage_path': storageUploadSucceeded ? masterPath : 'data-uri',
          'master_path': storageUploadSucceeded ? masterPath : null,
          'large_path': storageUploadSucceeded ? largePath : null,
          'medium_path': storageUploadSucceeded ? mediumPath : null,
          'small_path': storageUploadSucceeded ? smallPath : null,
          'mime_type': 'image/jpeg',
          'width': 1024,
          'height': 1024,
          'master_width': 1024,
          'master_height': 1024,
          'original_size_bytes': imageBytes.length,
          'stored_size_bytes': variants.large.length,
          'master_size_bytes': variants.master.length,
          'version': nextVersion,
          'status': 'ACTIVE',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });

        // Mark older assets as SUPERSEDED
        await client
            .from('employee_avatar_assets')
            .update({'status': 'SUPERSEDED'})
            .eq('employee_id', employeeId)
            .neq('id', assetId);
      } catch (assetErr) {
        secureLog('[AvatarService] Asset row insert note: $assetErr');
      }

      // 4. Update Employees Table Reference
      await client.from('employees').update({
        'avatar_url': activeUrl,
        'avatar_asset_id': assetId,
        'avatar_version': nextVersion,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', employeeId);

      // 5. Update local user state
      UserService.instance.updateProfileImage(activeUrl);
      secureLog('[AvatarService] Avatar successfully updated to v$nextVersion');
      return activeUrl;
    } catch (e) {
      secureLog('[AvatarService] Error updating profile photo: $e');
      rethrow;
    }
  }

  /// Remove profile photo and reset to initials
  Future<void> removeAvatar() async {
    final user = UserService.instance.currentUser;
    final employeeId = user.employeeUuid ?? user.employeeId;

    if (employeeId.isEmpty) return;

    try {
      final client = Supabase.instance.client;

      await client.from('employees').update({
        'avatar_url': null,
        'avatar_asset_id': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', employeeId);

      try {
        await client
            .from('employee_avatar_assets')
            .update({'status': 'DELETED'})
            .eq('employee_id', employeeId);
      } catch (_) {}

      UserService.instance.updateProfileImage('');
      secureLog('[AvatarService] Profile photo removed successfully');
    } catch (e) {
      secureLog('[AvatarService] Error removing avatar: $e');
      rethrow;
    }
  }
}
