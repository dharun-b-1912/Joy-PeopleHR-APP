import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/user_service.dart';
import '../utils/face_embedding_engine.dart';
import '../utils/face_image_optimizer.dart';

class FaceAttendStatus {
  final bool isEntitled;
  final bool moduleEnabled;
  final bool faceRequiredOnCheckIn;
  final bool faceRequiredOnCheckOut;
  final bool livenessEnabled;
  final bool gpsEnabled;
  final String geofenceMode;
  final bool offlineQueueEnabled;
  final bool manualFallbackEnabled;
  final String consentVersionRequired;
  final bool hasActiveConsent;
  final String? templateStatus;
  final int retentionDays;

  const FaceAttendStatus({
    required this.isEntitled,
    required this.moduleEnabled,
    required this.faceRequiredOnCheckIn,
    required this.faceRequiredOnCheckOut,
    required this.livenessEnabled,
    required this.gpsEnabled,
    required this.geofenceMode,
    required this.offlineQueueEnabled,
    required this.manualFallbackEnabled,
    required this.consentVersionRequired,
    required this.hasActiveConsent,
    this.templateStatus,
    this.retentionDays = 90,
  });

  static const disabled = FaceAttendStatus(
    isEntitled: false,
    moduleEnabled: false,
    faceRequiredOnCheckIn: false,
    faceRequiredOnCheckOut: false,
    livenessEnabled: true,
    gpsEnabled: true,
    geofenceMode: 'REQUIRED',
    offlineQueueEnabled: false,
    manualFallbackEnabled: true,
    consentVersionRequired: 'v1.0',
    hasActiveConsent: false,
    templateStatus: null,
  );
}

class FaceAttendChallenge {
  final String id;
  final String challengeNonce;
  final String challengeType;
  final String challengePrompt;
  final String expiresAt;

  const FaceAttendChallenge({
    required this.id,
    required this.challengeNonce,
    required this.challengeType,
    required this.challengePrompt,
    required this.expiresAt,
  });
}

class FaceAttendVerificationResult {
  final bool ok;
  final bool punchCommitted;
  final String decision;
  final String message;
  final String? attemptId;
  final bool canOfferManualFallback;
  final String? providerCode;
  final bool isProductionBiometric;
  final String? providerNotice;
  final double? faceSimilarity;
  final double? livenessScore;
  final double? distanceMeters;

  const FaceAttendVerificationResult({
    required this.ok,
    required this.punchCommitted,
    required this.decision,
    required this.message,
    this.attemptId,
    this.canOfferManualFallback = false,
    this.providerCode,
    this.isProductionBiometric = false,
    this.providerNotice,
    this.faceSimilarity,
    this.livenessScore,
    this.distanceMeters,
  });
}

class FaceAttendService extends ChangeNotifier {
  static final FaceAttendService instance = FaceAttendService._internal();
  FaceAttendService._internal();

  static const String _offlineQueueKey = 'joy_faceattend_offline_queue_v1';

  FaceAttendStatus _status = FaceAttendStatus.disabled;
  FaceAttendStatus get status => _status;

  int _offlinePendingCount = 0;
  int get offlinePendingCount => _offlinePendingCount;

  Future<FaceAttendStatus> fetchTenantStatus() async {
    final user = UserService.instance.currentUser;
    final orgId = user.organizationId ?? '';
    final empId = (user.employeeUuid?.isNotEmpty == true ? user.employeeUuid! : user.employeeId);

    if (orgId.isEmpty || empId.isEmpty) {
      _status = FaceAttendStatus.disabled;
      notifyListeners();
      return _status;
    }

    try {
      final client = Supabase.instance.client;
      final entRes = await client
          .from('organization_addon_entitlements')
          .select('is_enabled')
          .eq('organization_id', orgId)
          .eq('addon_key', 'face_attend')
          .maybeSingle();

      final isEntitled = entRes?['is_enabled'] == true;
      if (!isEntitled) {
        _status = FaceAttendStatus.disabled;
        notifyListeners();
        return _status;
      }

      final settingsRes = await client
          .from('faceattend_org_settings')
          .select('*')
          .eq('organization_id', orgId)
          .maybeSingle();

      final consentRes = await client
          .from('faceattend_consents')
          .select('status, consent_version')
          .eq('organization_id', orgId)
          .eq('employee_id', empId)
          .eq('status', 'GRANTED')
          .order('granted_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final templateRes = await client
          .from('faceattend_templates')
          .select('enrolment_status')
          .eq('organization_id', orgId)
          .eq('employee_id', empId)
          .neq('enrolment_status', 'DELETED')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      _status = FaceAttendStatus(
        isEntitled: true,
        moduleEnabled: settingsRes?['module_enabled'] ?? true,
        faceRequiredOnCheckIn: (settingsRes?['face_verification_enabled'] ?? true) &&
            (settingsRes?['require_face_on_checkin'] ?? true),
        faceRequiredOnCheckOut: (settingsRes?['face_verification_enabled'] ?? true) &&
            (settingsRes?['require_face_on_checkout'] ?? true),
        livenessEnabled: settingsRes?['liveness_enabled'] ?? true,
        gpsEnabled: settingsRes?['gps_verification_enabled'] ?? true,
        geofenceMode: (settingsRes?['geofence_mode'] as String?) ?? 'REQUIRED',
        offlineQueueEnabled: settingsRes?['offline_queue_enabled'] ?? false,
        manualFallbackEnabled: settingsRes?['manual_fallback_enabled'] ?? true,
        consentVersionRequired: (settingsRes?['consent_version_required'] as String?) ?? 'v1.0',
        hasActiveConsent: consentRes != null && consentRes['status'] == 'GRANTED',
        templateStatus: templateRes?['enrolment_status'] as String?,
        retentionDays: (settingsRes?['retention_days_images'] as int?) ?? 90,
      );
      await _refreshOfflineCount();
      notifyListeners();
      return _status;
    } catch (e) {
      debugPrint('[FaceAttendService] fetchTenantStatus error: $e');
      return _status;
    }
  }

  Future<FaceAttendChallenge?> issueChallenge() async {
    final res = await Supabase.instance.client.functions.invoke(
      'face-attend-verify',
      body: {'action': 'issue_challenge'},
    );
    final data = res.data as Map<String, dynamic>?;
    if (data == null || data['ok'] != true || data['challenge'] == null) {
      return null;
    }
    final ch = data['challenge'] as Map<String, dynamic>;
    return FaceAttendChallenge(
      id: ch['id']?.toString() ?? '',
      challengeNonce: ch['challenge_nonce']?.toString() ?? '',
      challengeType: ch['challenge_type']?.toString() ?? 'BLINK_AND_TURN',
      challengePrompt: ch['challenge_prompt']?.toString() ?? 'Look at camera & blink once',
      expiresAt: ch['expires_at']?.toString() ?? '',
    );
  }

  Future<String?> _buildBackfillDigestFromBase64(Map? enrolledImages) async {
    if (enrolledImages == null) return null;
    final frontB64 = enrolledImages['front']?.toString();
    if (frontB64 == null || frontB64.isEmpty) return null;
    try {
      final frontBytes = base64Decode(frontB64);
      final frontEmb = await FaceEmbeddingEngine.extract(frontBytes);
      if (frontEmb.embedding.isEmpty) return null;

      final digestMap = <String, dynamic>{
        'v': 2,
        'front': frontEmb.embedding,
      };

      final leftB64 = enrolledImages['left']?.toString();
      if (leftB64 != null && leftB64.isNotEmpty) {
        final leftEmb = await FaceEmbeddingEngine.extract(base64Decode(leftB64));
        if (leftEmb.embedding.isNotEmpty) {
          digestMap['left'] = leftEmb.embedding;
        }
      }

      final rightB64 = enrolledImages['right']?.toString();
      if (rightB64 != null && rightB64.isNotEmpty) {
        final rightEmb = await FaceEmbeddingEngine.extract(base64Decode(rightB64));
        if (rightEmb.embedding.isNotEmpty) {
          digestMap['right'] = rightEmb.embedding;
        }
      }

      return jsonEncode(digestMap);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> testVerifyFaceMatch(Uint8List imageBytes) async {
    final optimized = await FaceImageOptimizer.optimizeForFaceVerify(imageBytes);
    final liveEmb = await FaceEmbeddingEngine.extract(optimized);
    if (!liveEmb.hasFace) {
      return {
        'ok': false,
        'matched': false,
        'face_similarity': 0.0,
        'provider_code': 'BUILTIN_FACE_ENGINE',
        'message': liveEmb.errorReason ?? 'No clear face detected in camera frame.',
      };
    }

    final reqBody = <String, dynamic>{
      'action': 'test_verify',
      'image_base64': base64Encode(optimized),
      'live_embedding': liveEmb.embedding,
    };

    var res = await Supabase.instance.client.functions.invoke(
      'face-attend-verify',
      body: reqBody,
    );
    var data = Map<String, dynamic>.from(
      (res.data as Map?) ?? {'ok': false, 'matched': false, 'message': 'Unknown error'},
    );

    if (data['needs_embedding_backfill'] == true) {
      final backfillDigest = await _buildBackfillDigestFromBase64(data['enrolled_images_base64'] as Map?);
      if (backfillDigest != null) {
        reqBody['backfill_digest'] = backfillDigest;
        res = await Supabase.instance.client.functions.invoke(
          'face-attend-verify',
          body: reqBody,
        );
        data = Map<String, dynamic>.from(
          (res.data as Map?) ?? {'ok': false, 'matched': false, 'message': 'Unknown error'},
        );
      }
    }

    return data;
  }

  Future<Map<String, dynamic>> enrolFaceTemplate({
    required Uint8List imageBytes,
    Uint8List? leftImageBytes,
    Uint8List? rightImageBytes,
    required String consentVersion,
    required String languageCode,
  }) async {
    final frontOpt = await FaceImageOptimizer.optimizeForFaceVerify(imageBytes);
    final leftOpt = leftImageBytes != null
        ? await FaceImageOptimizer.optimizeForFaceVerify(leftImageBytes)
        : null;
    final rightOpt = rightImageBytes != null
        ? await FaceImageOptimizer.optimizeForFaceVerify(rightImageBytes)
        : null;

    final frontEmb = await FaceEmbeddingEngine.extract(frontOpt);
    if (!frontEmb.hasFace) {
      return {
        'ok': false,
        'error': frontEmb.errorReason ?? 'Could not detect a clear face in the Front photo. Please retake in good lighting.',
      };
    }

    final leftEmb = (leftOpt != null && leftOpt.isNotEmpty)
        ? await FaceEmbeddingEngine.extract(leftOpt)
        : null;
    final rightEmb = (rightOpt != null && rightOpt.isNotEmpty)
        ? await FaceEmbeddingEngine.extract(rightOpt)
        : null;

    final digestMap = <String, dynamic>{
      'v': 2,
      'front': frontEmb.embedding,
      if (leftEmb != null && leftEmb.embedding.isNotEmpty) 'left': leftEmb.embedding,
      if (rightEmb != null && rightEmb.embedding.isNotEmpty) 'right': rightEmb.embedding,
    };

    final sideImages = <String, String>{};
    if (leftOpt != null && leftOpt.isNotEmpty) {
      sideImages['left'] = base64Encode(leftOpt);
    }
    if (rightOpt != null && rightOpt.isNotEmpty) {
      sideImages['right'] = base64Encode(rightOpt);
    }

    final res = await Supabase.instance.client.functions.invoke(
      'face-attend-verify',
      body: {
        'action': 'enrol_template',
        'image_base64': base64Encode(frontOpt),
        if (sideImages.isNotEmpty) 'side_images': sideImages,
        'sandbox_digest': jsonEncode(digestMap),
        'consent_version': consentVersion,
        'language_code': languageCode,
      },
    );
    await fetchTenantStatus();
    return Map<String, dynamic>.from((res.data as Map?) ?? {'ok': false, 'error': 'Unknown error'});
  }

  Future<FaceAttendVerificationResult> verifyAndCommit({
    required String punchType,
    required Uint8List imageBytes,
    required String challengeNonce,
    required double? latitude,
    required double? longitude,
    required double? accuracyMeters,
    required bool isMockLocation,
    required bool blinkDetected,
    required bool headMovementDetected,
    required int captureDurationMs,
    String? reason,
    String? idempotencyKey,
  }) async {
    final optimizedBytes = await FaceImageOptimizer.optimizeForFaceVerify(imageBytes);
    final liveEmb = await FaceEmbeddingEngine.extract(optimizedBytes);
    if (!liveEmb.hasFace) {
      return FaceAttendVerificationResult(
        ok: false,
        punchCommitted: false,
        decision: 'IMAGE_QUALITY_FAILED',
        message: liveEmb.errorReason ?? 'No clear face detected in frame. Please center your face in good lighting.',
        canOfferManualFallback: true,
        providerCode: 'BUILTIN_FACE_ENGINE',
        isProductionBiometric: true,
      );
    }

    final correlationId = _generateUuidV4();
    final payload = <String, dynamic>{
      'action': 'verify_and_commit',
      'correlation_id': correlationId,
      'idempotency_key': idempotencyKey ?? correlationId,
      'punch_type': punchType,
      'image_base64': base64Encode(optimizedBytes),
      'live_embedding': liveEmb.embedding,
      'challenge_nonce': challengeNonce,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'gps_captured_at': DateTime.now().toUtc().toIso8601String(),
      'is_mock_location': isMockLocation,
      'reason': reason,
      'challenge_signals': {
        'blinkDetected': blinkDetected,
        'headMovementDetected': headMovementDetected,
        'captureDurationMs': captureDurationMs,
        'frameCount': 4,
        'faceDetectedCount': 1,
        'liveEmbedding': liveEmb.embedding,
      },
    };

    try {
      var res = await Supabase.instance.client.functions.invoke(
        'face-attend-verify',
        body: payload,
      );
      var data = Map<String, dynamic>.from((res.data as Map?) ?? {});
      if (data['needs_embedding_backfill'] == true) {
        final backfillDigest = await _buildBackfillDigestFromBase64(data['enrolled_images_base64'] as Map?);
        if (backfillDigest != null) {
          payload['backfill_digest'] = backfillDigest;
          res = await Supabase.instance.client.functions.invoke(
            'face-attend-verify',
            body: payload,
          );
          data = Map<String, dynamic>.from((res.data as Map?) ?? {});
        }
      }
      final scores = (data['scores'] as Map?) ?? {};
      return FaceAttendVerificationResult(
        ok: data['ok'] == true,
        punchCommitted: data['punch_committed'] == true,
        decision: data['decision']?.toString() ?? 'PROVIDER_UNAVAILABLE',
        message: data['message']?.toString() ?? 'Verification completed.',
        attemptId: data['attempt_id']?.toString(),
        canOfferManualFallback: data['can_offer_manual_fallback'] == true,
        providerCode: data['provider_code']?.toString(),
        isProductionBiometric: data['is_production_biometric'] == true,
        providerNotice: data['provider_notice']?.toString(),
        faceSimilarity: (scores['face_similarity'] as num?)?.toDouble(),
        livenessScore: (scores['liveness_score'] as num?)?.toDouble(),
        distanceMeters: (scores['distance_meters'] as num?)?.toDouble(),
      );
    } catch (e) {
      if (_status.offlineQueueEnabled) {
        await _queueOfflineVerification(payload);
        return const FaceAttendVerificationResult(
          ok: false,
          punchCommitted: false,
          decision: 'MANUAL_REVIEW_REQUIRED',
          message:
              'Offline mode: Attendance queued as PENDING VERIFICATION. It will NOT be marked present until server verifies upon reconnect.',
          canOfferManualFallback: true,
        );
      }
      return FaceAttendVerificationResult(
        ok: false,
        punchCommitted: false,
        decision: 'PROVIDER_UNAVAILABLE',
        message: 'Network or verification service error: $e',
        canOfferManualFallback: _status.manualFallbackEnabled,
      );
    }
  }

  Future<bool> requestManualFallback({
    required String punchType,
    required String reason,
    String? attemptId,
    double? latitude,
    double? longitude,
  }) async {
    final res = await Supabase.instance.client.functions.invoke(
      'face-attend-verify',
      body: {
        'action': 'request_fallback',
        'punch_type': punchType,
        'reason': reason,
        'attempt_id': attemptId,
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    final data = res.data as Map<String, dynamic>?;
    return data?['ok'] == true;
  }

  Future<bool> withdrawConsentAndDeleteBiometrics(String reason) async {
    final res = await Supabase.instance.client.functions.invoke(
      'face-attend-verify',
      body: {'action': 'withdraw_and_delete', 'reason': reason},
    );
    final data = res.data as Map<String, dynamic>?;
    await fetchTenantStatus();
    return data?['ok'] == true;
  }

  Future<void> _queueOfflineVerification(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_offlineQueueKey) ?? [];
    payload['is_offline_sync'] = true;
    payload['queued_status'] = 'PENDING_FACE_VERIFICATION';
    existing.add(jsonEncode(payload));
    await prefs.setStringList(_offlineQueueKey, existing);
    await _refreshOfflineCount();
    notifyListeners();
  }

  Future<void> _refreshOfflineCount() async {
    final prefs = await SharedPreferences.getInstance();
    _offlinePendingCount = (prefs.getStringList(_offlineQueueKey) ?? []).length;
  }

  String _generateUuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

