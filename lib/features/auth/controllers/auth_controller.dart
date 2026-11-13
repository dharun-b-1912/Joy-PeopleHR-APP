import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/user_service.dart';
import '../../../repositories/interfaces/auth_repository.dart';
import '../../../repositories/supabase/supabase_auth_repository.dart';
import '../models/multi_method_auth_models.dart';
import '../services/auth_gateway_service.dart';

typedef SessionHydrator = Future<void> Function(String refreshToken);

class AuthController extends ChangeNotifier {
  final IAuthRepository _authRepository;
  final AuthGatewayService _gatewayService;
  final SessionHydrator _sessionHydrator;

  AuthController({
    IAuthRepository? authRepository,
    AuthGatewayService? gatewayService,
    SessionHydrator? sessionHydrator,
  })  : _authRepository = authRepository ?? SupabaseAuthRepository(),
        _gatewayService = gatewayService ?? AuthGatewayService(),
        _sessionHydrator = sessionHydrator ?? _defaultSessionHydrator;

  static Future<void> _defaultSessionHydrator(String refreshToken) async {
    await Supabase.instance.client.auth.setSession(refreshToken);
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingConfig = false;
  bool get isLoadingConfig => _isLoadingConfig;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _errorCode;
  String? get errorCode => _errorCode;

  PublicLoginConfig _loginConfig = PublicLoginConfig.defaults();
  PublicLoginConfig get loginConfig => _loginConfig;

  LoginMethod _selectedMethod = LoginMethod.employeeIdPassword;
  LoginMethod get selectedMethod => _selectedMethod;

  bool _requiresCompanySelection = false;
  bool get requiresCompanySelection => _requiresCompanySelection;

  List<CompanyMembershipOption> _companies = const [];
  List<CompanyMembershipOption> get companies => _companies;

  String? _pendingRefreshToken;
  String? _pendingAccessToken;

  String? _otpChallengeId;
  String? get otpChallengeId => _otpChallengeId;

  String? _otpMaskedDestination;
  String? get otpMaskedDestination => _otpMaskedDestination;

  String? _otpOrganizationName;
  String? get otpOrganizationName => _otpOrganizationName;

  String? _otpCompanyName;
  String? get otpCompanyName => _otpCompanyName;

  int _otpCooldownSeconds = 0;
  int get otpCooldownSeconds => _otpCooldownSeconds;

  String? _resetChallengeId;
  String? get resetChallengeId => _resetChallengeId;

  String? _resetMaskedDestination;
  String? get resetMaskedDestination => _resetMaskedDestination;

  Timer? _cooldownTimer;

  bool get isAuthenticated => UserService.instance.isLoggedIn;

  void clearError() {
    if (_errorMessage != null || _errorCode != null) {
      _errorMessage = null;
      _errorCode = null;
      notifyListeners();
    }
  }

  Future<void> warmUpGateway() async {
    await _gatewayService.warmUp();
  }

  String _normalizeMobileInput(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  Future<void> loadLoginConfig({String? organizationId}) async {
    _isLoadingConfig = true;
    notifyListeners();
    try {
      final cfg = await _gatewayService.fetchPublicLoginConfig(
        organizationId: organizationId,
      );
      _loginConfig = cfg;
      if (cfg.enabledMethods.contains(cfg.defaultLoginMethod)) {
        _selectedMethod = cfg.defaultLoginMethod;
      } else if (cfg.enabledMethods.isNotEmpty) {
        _selectedMethod = cfg.enabledMethods.first;
      }
    } finally {
      _isLoadingConfig = false;
      notifyListeners();
    }
  }

  void selectLoginMethod(LoginMethod method) {
    _selectedMethod = method;
    _errorMessage = null;
    _errorCode = null;
    resetOtpFlow(notify: false);
    notifyListeners();
  }

  void resetOtpFlow({bool notify = true}) {
    _otpChallengeId = null;
    _otpMaskedDestination = null;
    _otpOrganizationName = null;
    _otpCompanyName = null;
    _otpCooldownSeconds = 0;
    _cooldownTimer?.cancel();
    if (notify) notifyListeners();
  }

  void cancelCompanySelection() {
    _requiresCompanySelection = false;
    _companies = const [];
    _pendingRefreshToken = null;
    _pendingAccessToken = null;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();
  }

  void _startCooldownTimer(int seconds) {
    _cooldownTimer?.cancel();
    _otpCooldownSeconds = seconds;
    notifyListeners();
    if (seconds <= 0) return;

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_otpCooldownSeconds <= 1) {
        _otpCooldownSeconds = 0;
        timer.cancel();
      } else {
        _otpCooldownSeconds -= 1;
      }
      notifyListeners();
    });
  }

  Future<bool> _completeSingleSession(MultiMethodGatewayResult res) async {
    final refreshToken = res.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      _errorMessage = 'Session token was not returned. Please try again.';
      notifyListeners();
      return false;
    }

    if (res.requiresCompanySelection && res.companies.length > 1) {
      _pendingRefreshToken = refreshToken;
      _pendingAccessToken = res.accessToken;
      _companies = res.companies;
      _requiresCompanySelection = true;
      notifyListeners();
      return false;
    }

    await _sessionHydrator(refreshToken).timeout(const Duration(seconds: 10));
    try {
      final restoredUser = await _authRepository
          .restoreSession()
          .timeout(const Duration(seconds: 10));
      if (restoredUser != null) {
        UserService.instance.setUser(restoredUser);
      }
    } catch (_) {
      // Session JWT is already hydrated; home screen listener will complete background sync
    }
    return true;
  }

  Future<bool> loginWithMethod({
    required LoginMethod method,
    required String identifier,
    required String password,
    String countryCode = '+91',
  }) async {
    if (identifier.trim().isEmpty) {
      _errorMessage = 'Please enter your login credential.';
      notifyListeners();
      return false;
    }
    if (password.isEmpty) {
      _errorMessage = 'Please enter your password.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();

    try {
      final res = await _gatewayService.loginWithPassword(
        method: method,
        identifier: identifier.trim(),
        password: password,
        countryCode: countryCode,
      );

      if (!res.ok) {
        _errorMessage = res.message ?? 'Invalid login credentials.';
        _errorCode = res.code;
        return false;
      }

      return await _completeSingleSession(res);
    } catch (e) {
      _errorMessage = 'Unable to sign in right now. Check your internet connection.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Legacy email+password signature preserved for backwards-compatibility
  Future<bool> login({
    required String email,
    required String password,
  }) {
    final trimmed = email.trim();
    final inferredMethod = trimmed.contains('@')
        ? LoginMethod.emailPassword
        : RegExp(r'^\+?\d{10,15}$').hasMatch(trimmed.replaceAll(RegExp(r'[\s\-()]'), ''))
            ? LoginMethod.mobilePassword
            : LoginMethod.employeeIdPassword;

    return loginWithMethod(
      method: inferredMethod,
      identifier: trimmed,
      password: password,
    );
  }

  Future<bool> requestMobileOtp({
    required String mobile,
    String countryCode = '+91',
  }) async {
    final normalizedMobile = _normalizeMobileInput(mobile);
    if (normalizedMobile.length < 10) {
      _errorMessage = 'Please enter a valid 10-digit registered mobile number.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();

    try {
      final res = await _gatewayService.requestMobileOtp(
        mobile: normalizedMobile,
        countryCode: countryCode,
      );

      if (!res.ok || res.challengeId == null) {
        _errorMessage = res.message ?? 'Could not send login OTP.';
        _errorCode = res.code;
        if (res.cooldownSeconds != null && res.cooldownSeconds! > 0) {
          _startCooldownTimer(res.cooldownSeconds!);
        }
        return false;
      }

      _otpChallengeId = res.challengeId;
      _otpMaskedDestination = res.maskedDestination;
      _otpOrganizationName = res.organizationName;
      _otpCompanyName = res.companyName;
      _startCooldownTimer(
        res.cooldownSeconds ?? _loginConfig.otpResendCooldownSeconds,
      );
      return true;
    } catch (_) {
      _errorMessage = 'Unable to send SMS OTP. Check your network connection.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyMobileOtp({required String otp}) async {
    if (_otpChallengeId == null) {
      _errorMessage = 'Please request an OTP first.';
      notifyListeners();
      return false;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(otp.trim())) {
      _errorMessage = 'Enter the 6-digit OTP sent to your mobile number.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();

    try {
      final res = await _gatewayService.verifyMobileOtp(
        challengeId: _otpChallengeId!,
        otp: otp.trim(),
      );

      if (!res.ok) {
        _errorMessage = res.message ?? 'Invalid or expired OTP code.';
        _errorCode = res.code;
        return false;
      }

      return await _completeSingleSession(res);
    } catch (_) {
      _errorMessage = 'OTP verification failed. Please retry.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmCompanySelection(String organizationId) async {
    final refreshToken = _pendingRefreshToken;
    final accessToken = _pendingAccessToken;
    if (refreshToken == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (accessToken != null && accessToken.isNotEmpty) {
        await _gatewayService.switchCompanyContext(
          accessToken: accessToken,
          organizationId: organizationId,
        );
      }

      await _sessionHydrator(refreshToken);
      final restoredUser = await _authRepository.restoreSession();
      if (restoredUser != null) {
        UserService.instance.setUser(restoredUser);
      }

      _requiresCompanySelection = false;
      _pendingRefreshToken = null;
      _pendingAccessToken = null;
      _companies = const [];
      return true;
    } catch (_) {
      _errorMessage = 'Failed to load the selected company workspace.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendPasswordReset(String identifier) async {
    if (identifier.trim().isEmpty) {
      _errorMessage = 'Please enter your registered email or Employee ID.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _gatewayService.requestPasswordRecovery(
        recoveryMethod: 'email',
        identifier: identifier.trim(),
      );
      if (!res.ok) {
        _errorMessage = res.message ?? 'Could not send reset email.';
        return false;
      }
      return true;
    } catch (_) {
      _errorMessage = 'Unable to send reset instructions right now.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestMobileResetOtp({
    required String mobile,
    String countryCode = '+91',
  }) async {
    final digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      _errorMessage = 'Please enter a valid 10-digit registered mobile number.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _gatewayService.requestPasswordRecovery(
        recoveryMethod: 'mobile_otp',
        identifier: mobile.trim(),
        countryCode: countryCode,
      );
      if (!res.ok || res.challengeId == null) {
        _errorMessage = res.message ?? 'Could not send password reset OTP.';
        return false;
      }
      _resetChallengeId = res.challengeId;
      _resetMaskedDestination = res.maskedDestination;
      _startCooldownTimer(res.cooldownSeconds ?? 30);
      return true;
    } catch (_) {
      _errorMessage = 'Failed to request reset OTP.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyMobileResetOtp({
    required String otp,
    required String newPassword,
  }) async {
    if (_resetChallengeId == null) {
      _errorMessage = 'Request a reset OTP first.';
      notifyListeners();
      return false;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(otp.trim())) {
      _errorMessage = 'Enter the 6-digit verification code.';
      notifyListeners();
      return false;
    }
    if (newPassword.length < 8) {
      _errorMessage = 'Password must be at least 8 characters.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _gatewayService.verifyRecoveryOtpReset(
        challengeId: _resetChallengeId!,
        otp: otp.trim(),
        newPassword: newPassword,
      );
      if (!res.ok) {
        _errorMessage = res.message ?? 'Could not reset password.';
        return false;
      }
      _resetChallengeId = null;
      _resetMaskedDestination = null;
      return true;
    } catch (_) {
      _errorMessage = 'Password reset failed.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
      final orgId = UserService.instance.currentUser.companyId;
      if (accessToken != null && accessToken.isNotEmpty) {
        await _gatewayService.recordSessionEvent(
          accessToken: accessToken,
          eventType: 'logout',
          organizationId: orgId,
        );
      }
    } catch (_) {}

    resetOtpFlow(notify: false);
    cancelCompanySelection();
    await _authRepository.signOut();
    notifyListeners();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }
}
