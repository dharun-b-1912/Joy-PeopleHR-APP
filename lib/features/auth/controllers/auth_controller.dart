import 'package:flutter/material.dart';
import '../../../core/services/user_service.dart';
import '../../../core/utils/validators.dart';
import '../../../models/hrms_models.dart';
import '../../../repositories/interfaces/auth_repository.dart';
import '../../../repositories/supabase/supabase_auth_repository.dart';

class AuthController extends ChangeNotifier {
  final IAuthRepository _authRepository;

  AuthController({IAuthRepository? authRepository})
      : _authRepository = authRepository ?? SupabaseAuthRepository();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  UserModel? get currentUser => UserService.instance.currentUser;
  bool get isAuthenticated => UserService.instance.isLoggedIn;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedPassword = password.trim();

    if (trimmedEmail.isEmpty) {
      _errorMessage = "Enter your work email";
      notifyListeners();
      return false;
    }

    if (!Validators.isValidEmail(trimmedEmail)) {
      _errorMessage = "Enter a valid work email";
      notifyListeners();
      return false;
    }

    if (trimmedPassword.isEmpty) {
      _errorMessage = "Enter your password";
      notifyListeners();
      return false;
    }

    if (trimmedPassword.length < 6) {
      _errorMessage = "Password must be at least 6 characters";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authRepository.authenticateUser(
        identifier: trimmedEmail,
        password: trimmedPassword,
      );

      _isLoading = false;

      if (result.success && result.user != null) {
        notifyListeners();
        return true;
      } else {
        _errorMessage = result.errorMessage ?? "Invalid work email or password.";
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = "Authentication failed. Please check your credentials.";
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !Validators.isValidEmail(trimmedEmail)) {
      _errorMessage = "Enter a valid work email";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final success = await _authRepository.resetPasswordForEmail(trimmedEmail);
    _isLoading = false;
    if (!success) {
      _errorMessage = "Failed to send reset link. Verify your work email.";
    }
    notifyListeners();
    return success;
  }

  Future<void> logout() async {
    await _authRepository.signOut();
    notifyListeners();
  }
}
