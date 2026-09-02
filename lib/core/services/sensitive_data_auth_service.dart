import '../../repositories/supabase/supabase_auth_repository.dart';

/// Service abstraction for verifying employee password before revealing sensitive payroll data.
/// Connects to Supabase Auth password re-authentication.
class SensitiveDataAuthService {
  static final SensitiveDataAuthService instance = SensitiveDataAuthService._internal();
  SensitiveDataAuthService._internal();

  /// Verifies user password against Supabase Auth without storing local state
  Future<bool> verifyPassword(String password) async {
    return SupabaseAuthRepository().verifyPassword(password);
  }
}
