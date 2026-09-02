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

  /// Fetch upcoming colleague birthdays and work anniversaries (Today + next 30 days)
  Future<List<CelebrationModel>> getColleagueCelebrations() async {
    try {
      final user = UserService.instance.currentUser;
      final orgId = user.organizationId?.isNotEmpty == true
          ? user.organizationId!
          : (user.companyId.isNotEmpty ? user.companyId : '');

      dynamic query = _client.from('employees').select();

      if (orgId.isNotEmpty) {
        query = query.or('organization_id.eq.$orgId,company_id.eq.$orgId,tenant_id.eq.$orgId');
      }

      final List<dynamic> rows = await query.limit(200);
      final List<CelebrationModel> celebrations = [];
      final now = DateTime.now();

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final isActive = map['is_active'] != false &&
            (map['status'] == null || map['status'].toString().toUpperCase() == 'ACTIVE');
        if (!isActive) continue;

        final empId = map['id']?.toString() ?? '';
        final firstName = map['first_name']?.toString() ?? '';
        final lastName = map['last_name']?.toString() ?? '';
        final rawDisplayName = map['display_name']?.toString();
        final name = (rawDisplayName != null && rawDisplayName.trim().isNotEmpty)
            ? rawDisplayName.trim()
            : ('$firstName $lastName'.trim().isNotEmpty ? '$firstName $lastName'.trim() : 'Colleague');

        final avatarUrl = map['avatar_url']?.toString();
        final department = map['department_name']?.toString() ??
            (map['employment'] is Map ? map['employment']['department']?.toString() : null) ??
            'General';
        final designation = map['designation_title']?.toString() ??
            (map['employment'] is Map ? map['employment']['designation']?.toString() : null) ??
            'Team Member';

        // 1. Parse Date of Birth
        String? dobStr = map['date_of_birth']?.toString() ??
            map['dob']?.toString() ??
            map['birth_date']?.toString();
        if (dobStr == null && map['profile'] is Map) {
          dobStr = map['profile']['date_of_birth']?.toString() ??
              map['profile']['dob']?.toString() ??
              map['profile']['birth_date']?.toString();
        }
        if (dobStr == null && map['personal_details'] is Map) {
          dobStr = map['personal_details']['dob']?.toString() ??
              map['personal_details']['date_of_birth']?.toString();
        }
        if (dobStr != null && dobStr.isNotEmpty) {
          final dob = DateTime.tryParse(dobStr.split('T')[0]);
          if (dob != null) {
            // Check if birthday falls within next 30 days or is today
            final bdayThisYear = DateTime(now.year, dob.month, dob.day);
            final diffDays = bdayThisYear.difference(DateTime(now.year, now.month, now.day)).inDays;
            final bdayNextYear = DateTime(now.year + 1, dob.month, dob.day);
            final diffDaysNextYear = bdayNextYear.difference(DateTime(now.year, now.month, now.day)).inDays;

            if (diffDays >= 0 && diffDays <= 30) {
              celebrations.add(CelebrationModel(
                id: 'bday-$empId-${bdayThisYear.year}',
                employeeId: empId,
                employeeName: name,
                avatarUrl: avatarUrl,
                department: department,
                designation: designation,
                type: CelebrationType.birthday,
                date: bdayThisYear,
              ));
            } else if (diffDays < 0 && diffDaysNextYear <= 30) {
              celebrations.add(CelebrationModel(
                id: 'bday-$empId-${bdayNextYear.year}',
                employeeId: empId,
                employeeName: name,
                avatarUrl: avatarUrl,
                department: department,
                designation: designation,
                type: CelebrationType.birthday,
                date: bdayNextYear,
              ));
            }
          }
        }

        // 2. Parse Date of Joining (Work Anniversary)
        String? dojStr = map['date_of_joining']?.toString() ??
            map['joining_date']?.toString() ??
            map['doj']?.toString() ??
            map['hire_date']?.toString();
        if (dojStr == null && map['employment'] is Map) {
          dojStr = map['employment']['date_of_joining']?.toString() ??
              map['employment']['joining_date']?.toString() ??
              map['employment']['doj']?.toString() ??
              map['employment']['hire_date']?.toString();
        }
        if (dojStr != null && dojStr.isNotEmpty) {
          final doj = DateTime.tryParse(dojStr.split('T')[0]);
          if (doj != null && doj.year < now.year) {
            final anniThisYear = DateTime(now.year, doj.month, doj.day);
            final diffDays = anniThisYear.difference(DateTime(now.year, now.month, now.day)).inDays;
            final anniNextYear = DateTime(now.year + 1, doj.month, doj.day);
            final diffDaysNextYear = anniNextYear.difference(DateTime(now.year, now.month, now.day)).inDays;

            if (diffDays >= 0 && diffDays <= 30) {
              final years = now.year - doj.year;
              if (years > 0) {
                celebrations.add(CelebrationModel(
                  id: 'anni-$empId-${anniThisYear.year}',
                  employeeId: empId,
                  employeeName: name,
                  avatarUrl: avatarUrl,
                  department: department,
                  designation: designation,
                  type: CelebrationType.workAnniversary,
                  date: anniThisYear,
                  yearsOfService: years,
                ));
              }
            } else if (diffDays < 0 && diffDaysNextYear <= 30) {
              final years = (now.year + 1) - doj.year;
              if (years > 0) {
                celebrations.add(CelebrationModel(
                  id: 'anni-$empId-${anniNextYear.year}',
                  employeeId: empId,
                  employeeName: name,
                  avatarUrl: avatarUrl,
                  department: department,
                  designation: designation,
                  type: CelebrationType.workAnniversary,
                  date: anniNextYear,
                  yearsOfService: years,
                ));
              }
            }
          }
        }
      }

      // Sort by days until celebration
      celebrations.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
      return celebrations;
    } catch (e) {
      secureLog('[Employee] getColleagueCelebrations error: $e');
      return [];
    }
  }
}
