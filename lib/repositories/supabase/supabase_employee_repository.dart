// supabase_employee_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/employee_identity_resolver.dart';
import '../../core/services/user_service.dart';
import '../../core/utils/secure_log.dart';
import '../../models/hrms_models.dart';

/// WorkForceOS — Supabase Employee Repository
///
/// Resolves the current employee profile using the authenticated session.
/// Identity chain (schema-aligned):
///   auth.uid() → app_users.auth_user_id → app_users.employee_id → employees.*
class SupabaseEmployeeRepository {
  SupabaseClient get _client => Supabase.instance.client;

  /// Load the current authenticated employee's full profile.
  /// Throws if no Supabase session exists.
  Future<UserModel?> getCurrentEmployee() async {
    try {
      final authUser = _client.auth.currentUser;
      if (authUser == null) {
        secureLog('[Employee] No authenticated user');
        return null;
      }

      secureLog('[Employee] Resolving employee for uid=${authUser.id}');

      final resolution = await EmployeeIdentityResolver.resolve(
        client: _client,
        authUid: authUser.id,
        authEmail: authUser.email,
        authAvatarUrl: authUser.userMetadata?['avatar_url'] as String?,
      );

      if (resolution.success && resolution.userModel != null) {
        UserService.instance.setUser(resolution.userModel!);
        secureLog('[Employee] Profile loaded → ${resolution.userModel!.name} (${resolution.userModel!.employeeId})');
        return resolution.userModel;
      } else {
        secureLog('[Employee] Failed to resolve employee: ${resolution.state}');
        return null;
      }
    } catch (e) {
      secureLog('[Employee] getCurrentEmployee error: $e');
      return null;
    }
  }

  /// Reload the current employee profile (e.g. after profile edit).
  Future<UserModel?> refreshCurrentEmployee() => getCurrentEmployee();
}
