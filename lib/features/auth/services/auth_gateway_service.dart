import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_env.dart';
import '../models/multi_method_auth_models.dart';

class AuthGatewayService {
  final http.Client _httpClient;
  final String Function() _urlProvider;
  final String Function() _anonKeyProvider;

  AuthGatewayService({
    http.Client? httpClient,
    String Function()? urlProvider,
    String Function()? anonKeyProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _urlProvider = urlProvider ?? (() => AppEnv.supabaseUrl),
        _anonKeyProvider = anonKeyProvider ?? (() => AppEnv.supabaseAnonKey);

  Uri _gatewayUri() {
    final base = _urlProvider().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/functions/v1/auth-gateway');
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'mobile';
    }
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'apikey': _anonKeyProvider(),
    };
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    final response = await _httpClient
        .post(
          _gatewayUri(),
          headers: headers,
          body: jsonEncode({
            ...body,
            'devicePlatform': _platformName(),
          }),
        )
        .timeout(const Duration(seconds: 25));

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Fallback below
    }

    return <String, dynamic>{
      'ok': false,
      'message': 'Authentication service error (${response.statusCode}).',
    };
  }

  Future<void> warmUp() async {
    try {
      await _httpClient
          .post(
            _gatewayUri(),
            headers: {
              'Content-Type': 'application/json',
              'apikey': _anonKeyProvider(),
            },
            body: jsonEncode({
              'action': 'warmup',
              'devicePlatform': _platformName(),
            }),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Best-effort non-blocking edge pre-warm
    }
  }

  Future<PublicLoginConfig> fetchPublicLoginConfig({
    String? organizationId,
  }) async {
    try {
      final res = await _post({
        'action': 'get_login_config',
        if (organizationId != null) 'organizationId': organizationId,
      });
      if (res['ok'] == true) {
        return PublicLoginConfig.fromJson(res);
      }
    } catch (_) {
      // Fall back safely to defaults on offline launch
    }
    return PublicLoginConfig.defaults();
  }

  Future<MultiMethodGatewayResult> loginWithPassword({
    required LoginMethod method,
    required String identifier,
    required String password,
    String countryCode = '+91',
    String? organizationId,
  }) async {
    final res = await _post({
      'action': 'login_with_password',
      'method': method.apiValue,
      'identifier': identifier.trim(),
      'password': password,
      'countryCode': countryCode,
      if (organizationId != null) 'organizationId': organizationId,
    });
    return MultiMethodGatewayResult.fromJson(res);
  }

  Future<MultiMethodGatewayResult> requestMobileOtp({
    required String mobile,
    String countryCode = '+91',
    String? organizationId,
    String purpose = 'login',
  }) async {
    final res = await _post({
      'action': 'request_login_otp',
      'mobile': mobile.trim(),
      'countryCode': countryCode,
      'purpose': purpose,
      if (organizationId != null) 'organizationId': organizationId,
    });
    return MultiMethodGatewayResult.fromJson(res);
  }

  Future<MultiMethodGatewayResult> verifyMobileOtp({
    required String challengeId,
    required String otp,
  }) async {
    final res = await _post({
      'action': 'verify_login_otp',
      'challengeId': challengeId,
      'otp': otp.trim(),
    });
    return MultiMethodGatewayResult.fromJson(res);
  }

  Future<MultiMethodGatewayResult> requestPasswordRecovery({
    required String recoveryMethod,
    required String identifier,
    String countryCode = '+91',
  }) async {
    final res = await _post({
      'action': 'request_password_recovery',
      'recoveryMethod': recoveryMethod,
      'identifier': identifier.trim(),
      'countryCode': countryCode,
    });
    return MultiMethodGatewayResult.fromJson(res);
  }

  Future<MultiMethodGatewayResult> verifyRecoveryOtpReset({
    required String challengeId,
    required String otp,
    required String newPassword,
  }) async {
    final res = await _post({
      'action': 'verify_recovery_otp_reset',
      'challengeId': challengeId,
      'otp': otp.trim(),
      'newPassword': newPassword,
    });
    return MultiMethodGatewayResult.fromJson(res);
  }

  Future<MultiMethodGatewayResult> switchCompanyContext({
    required String accessToken,
    required String organizationId,
  }) async {
    final res = await _post(
      {
        'action': 'switch_company_context',
        'organizationId': organizationId,
      },
      accessToken: accessToken,
    );
    return MultiMethodGatewayResult.fromJson(res);
  }

  Future<void> recordSessionEvent({
    required String accessToken,
    required String eventType,
    String? organizationId,
  }) async {
    try {
      await _post(
        {
          'action': 'record_session_event',
          'eventType': eventType,
          if (organizationId != null) 'organizationId': organizationId,
        },
        accessToken: accessToken,
      );
    } catch (_) {
      // Non-blocking audit call
    }
  }
}

