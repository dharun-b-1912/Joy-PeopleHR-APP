import '../../models/hrms_models.dart';

class AuthResult {
  final bool success;
  final UserModel? user;
  final String? employeeId;
  final String? errorMessage;

  const AuthResult({
    required this.success,
    this.user,
    this.employeeId,
    this.errorMessage,
  });
}

abstract class IAuthRepository {
  /// Authenticate via Supabase Auth using email (or phone) + password or OTP.
  Future<AuthResult> authenticateUser({
    required String identifier,
    String? password,
    String? otp,
  });

  /// Sign in using Supabase Auth signInWithPassword(email, password)
  /// Resolves identity: auth.uid() -> app_users -> employees -> UserModel
  Future<UserModel?> signInWithPassword(String email, String password);

  /// Sign out current Supabase auth session
  Future<void> signOut();

  /// Restore active Supabase session on app startup
  Future<UserModel?> restoreSession();

  /// Change user password using Supabase Auth updateUser
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Send password reset link to user's email via resetPasswordForEmail
  Future<bool> resetPasswordForEmail(String email);

  /// Verify user password against Supabase Auth without altering session
  Future<bool> verifyPassword(String password);

  /// Fetch sensitive statutory & bank details after successful password verification
  Future<PayrollStatutoryModel?> getSensitiveStatutoryDetails(String employeeId);
}
