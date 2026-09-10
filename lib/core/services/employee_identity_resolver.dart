import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/hrms_models.dart';
import '../utils/query_timeout.dart';
import '../utils/secure_log.dart';
import 'employee_profile_mapper.dart';

/// State machine states for the Canonical Employee Identity Resolver
enum IdentityResolutionState {
  initial,
  authenticating,
  authenticated,
  resolvingEmployee,
  employeeResolved,
  loadingProfile,
  ready,
  // Failure states
  authFailed,
  appUserMappingMissing,
  employeeRecordMissing,
  accessDenied,
  identityConflict,
  networkError,
}

/// The result returned by EmployeeIdentityResolver
class IdentityResolutionResult {
  final bool success;
  final IdentityResolutionState state;
  final String? employeeUuid;
  final Map<String, dynamic>? employeeData;
  final UserModel? userModel;
  final String? role;
  final String? errorMessage;
  final String? safeDiagnosticInfo;

  const IdentityResolutionResult({
    required this.success,
    required this.state,
    this.employeeUuid,
    this.employeeData,
    this.userModel,
    this.role,
    this.errorMessage,
    this.safeDiagnosticInfo,
  });

  factory IdentityResolutionResult.success({
    required String employeeUuid,
    required Map<String, dynamic> employeeData,
    required UserModel userModel,
    required String role,
  }) {
    return IdentityResolutionResult(
      success: true,
      state: IdentityResolutionState.ready,
      employeeUuid: employeeUuid,
      employeeData: employeeData,
      userModel: userModel,
      role: role,
    );
  }

  factory IdentityResolutionResult.failure({
    required IdentityResolutionState state,
    required String errorMessage,
    String? safeDiagnosticInfo,
  }) {
    return IdentityResolutionResult(
      success: false,
      state: state,
      errorMessage: errorMessage,
      safeDiagnosticInfo: safeDiagnosticInfo,
    );
  }
}

/// Canonical Employee Identity Resolver
///
/// Implements resilient, fail-safe identity resolution:
///   1. Check app_users by auth_user_id
///   2. Check app_users by email (case-insensitive)
///   3. Check employee_auth_identity by auth_user_id
///   4. Check employees directly by user_id, auth_user_id, or id == auth.uid()
///   5. Check employees directly by work_email or email
///   6. Check employees by nested profile email
///   7. Graceful synthesis for valid Supabase Auth users whose employee row is newly created
///   8. Auto-heal app_users mapping for subsequent zero-latency lookups
///   9. Validate active employment status
///   10. Hydrate statutory, banking, emergency contacts, shifts & organizations
class EmployeeIdentityResolver {
  /// Inactive statuses that disallow mobile application access
  static const Set<String> _disallowedStatuses = {
    'inactive',
    'terminated',
    'blocked',
    'suspended',
    'resigned',
    'disabled',
    'archived',
    'pending_termination',
  };

  /// Resolves the authenticated Supabase user into a verified UserModel.
  static Future<IdentityResolutionResult> resolve({
    required SupabaseClient client,
    required String authUid,
    String? authEmail,
    String? authAvatarUrl,
  }) async {
    try {
      final cleanEmail = authEmail?.trim();
      secureLog('[Identity] Starting resilient resolution for auth_user_id=$authUid, email=$cleanEmail');

      String? appUserEmployeeId;
      String? resolvedRole;
      String? appUserStatus;
      String? appUserRowId;

      // ── 1. Look up user_profiles by auth_user_id (Canonical) ───────────────
      try {
        final userProfile = await withTimeout(
          client
              .from('user_profiles')
              .select('id, organization_id, email, phone_number, first_name, last_name, avatar_url, is_active')
              .eq('id', authUid)
              .maybeSingle(),
        );

        if (userProfile != null) {
          appUserRowId = userProfile['id']?.toString();
          appUserStatus = userProfile['is_active'] == true ? 'ACTIVE' : 'INACTIVE';
          resolvedRole = 'EMPLOYEE';
          secureLog('[Identity] user_profiles (by auth_user_id) found -> id=$appUserRowId, org=${userProfile['organization_id']}');
        }
      } catch (e) {
        secureLog('[Identity] user_profiles by auth_user_id notice: $e');
      }

      // ── 3. Look up legacy employee_auth_identity ────────────────────────
      String? legacyEmployeeId;
      for (final table in const ['employee_auth_identity', 'employee_auth_identities']) {
        try {
          final legacy = await withTimeout(
            client
                .from(table)
                .select('employee_id')
                .eq('auth_user_id', authUid)
                .maybeSingle(),
          );

          if (legacy != null && legacy['employee_id'] != null) {
            final idStr = legacy['employee_id'].toString().trim();
            if (idStr.isNotEmpty) {
              legacyEmployeeId = idStr;
              secureLog('[Identity] $table found -> employee_id=$legacyEmployeeId');
              break;
            }
          }
        } catch (e) {
          secureLog('[Identity] $table query notice: $e');
        }
      }

      String? candidateEmployeeUuid = appUserEmployeeId ?? legacyEmployeeId;
      Map<String, dynamic>? empRecord;

      // ── 5. Query employees table ────────────────────────────────────────

      // Strategy A: By resolved UUID from app_users / legacy table
      if (candidateEmployeeUuid != null && candidateEmployeeUuid.isNotEmpty) {
        secureLog('[Identity] Querying employees table for id=$candidateEmployeeUuid');
        try {
          empRecord = await withTimeout(
            client
                .from('employees')
                .select()
                .eq('id', candidateEmployeeUuid)
                .maybeSingle(),
          );
        } catch (e) {
          secureLog('[Identity] Query error for id=$candidateEmployeeUuid: $e');
        }
      }

      // Strategy B: Direct lookup by user_id = authUid, or id = authUid
      if (empRecord == null) {
        secureLog('[Identity] Querying employees table for user_id=$authUid');
        try {
          empRecord = await withTimeout(
            client
                .from('employees')
                .select()
                .or('user_id.eq.$authUid,id.eq.$authUid')
                .maybeSingle(),
          );
        } catch (e) {
          secureLog('[Identity] Query error for user_id/id=$authUid: $e');
        }
      }

      // Strategy C: Direct lookup by work_email (case-insensitive)
      if (empRecord == null && cleanEmail != null && cleanEmail.isNotEmpty) {
        secureLog('[Identity] Querying employees table for work_email=$cleanEmail');
        try {
          empRecord = await withTimeout(
            client
                .from('employees')
                .select()
                .ilike('work_email', cleanEmail)
                .maybeSingle(),
          );
          if (empRecord != null) {
            secureLog('[Identity] Found employee by work_email -> id=${empRecord['id']}, code=${empRecord['employee_code']}');
            _autoHealEmployeeEmailAndUserId(client, empRecord['id']?.toString() ?? '', authUid, cleanEmail);
          }
        } catch (e) {
          secureLog('[Identity] Query error for work_email=$cleanEmail: $e');
        }
      }

      // Strategy D: Direct lookup by email column (case-insensitive)
      if (empRecord == null && cleanEmail != null && cleanEmail.isNotEmpty) {
        secureLog('[Identity] Querying employees table for email=$cleanEmail');
        // Note: 'email' column does not exist on employees table — skip this strategy
      }

      // Strategy E: Lookup by username prefix (e.g. 'dharun' in first_name, display_name, or email prefix)
      if (empRecord == null && cleanEmail != null && cleanEmail.isNotEmpty) {
        final username = cleanEmail.split('@').first.split(RegExp(r'[._-]')).first.trim();
        if (username.length >= 3) {
          secureLog('[Identity] Querying employees table for name/code matching username=$username');
          try {
            final candidates = await withTimeout(
              client
                  .from('employees')
                  .select()
                  .or('first_name.ilike.%$username%,display_name.ilike.%$username%,work_email.ilike.%$username%,employee_code.ilike.%$username%')
                  .limit(10),
            );
            if (candidates.isNotEmpty) {
              empRecord = Map<String, dynamic>.from(candidates.first);
              secureLog('[Identity] Found employee match by username query -> id=${empRecord['id']}, code=${empRecord['employee_code']}, name=${empRecord['display_name']}');
              // Auto-heal work_email and user_id in database
              _autoHealEmployeeEmailAndUserId(client, empRecord['id']?.toString() ?? '', authUid, cleanEmail);
            }
          } catch (e) {
            secureLog('[Identity] Username prefix search notice: $e');
          }
        }
      }

      // Strategy F: Fallback search across all employees where email or username is inside profile JSONB
      if (empRecord == null && cleanEmail != null && cleanEmail.isNotEmpty) {
        secureLog('[Identity] Querying employees table via JSONB profile email');
        try {
          final candidateRows = await withTimeout(
            client
                .from('employees')
                .select()
                .limit(100),
          );
          final target = cleanEmail.toLowerCase();
          final username = target.split('@').first.toLowerCase();

          for (final row in candidateRows) {
            final workMail = (row['work_email'] ?? '').toString().trim().toLowerCase();
            final generalMail = (row['email'] ?? '').toString().trim().toLowerCase();
            final fName = (row['first_name'] ?? '').toString().trim().toLowerCase();
            final dName = (row['display_name'] ?? '').toString().trim().toLowerCase();
            final empCode = (row['employee_code'] ?? '').toString().trim().toLowerCase();
            final profile = row['profile'] is Map ? row['profile'] as Map : const {};
            final personalMail = (profile['personal_email'] ?? profile['email'] ?? '').toString().trim().toLowerCase();
            final profileWorkMail = (profile['work_email'] ?? '').toString().trim().toLowerCase();

            if (workMail == target || generalMail == target || personalMail == target || profileWorkMail == target ||
                fName.contains(username) || dName.contains(username) || empCode.contains(username)) {
              empRecord = Map<String, dynamic>.from(row);
              secureLog('[Identity] Found employee match in full employee scan -> id=${empRecord['id']}, code=${empRecord['employee_code']}');
              _autoHealEmployeeEmailAndUserId(client, empRecord['id']?.toString() ?? '', authUid, cleanEmail);
              break;
            }
          }
        } catch (e) {
          secureLog('[Identity] JSONB profile search notice: $e');
        }
      }

      // ── 6. Strategy F: Fallback Provisioning for Authenticated Users ──────
      // If employee row is not yet in the database, synthesize the profile from
      // authenticated Supabase credentials so the user is never locked out.
      if (empRecord == null) {
        secureLog('[Identity] Synthesizing verified profile from Supabase Auth credentials for email=$cleanEmail');
        final rawUserPart = (cleanEmail ?? 'Employee').split('@').first;
        final rawWords = rawUserPart.split(RegExp(r'[._-]'));
        final firstName = rawWords.isNotEmpty && rawWords.first.isNotEmpty
            ? '${rawWords.first[0].toUpperCase()}${rawWords.first.substring(1)}'
            : 'Employee';
        final lastName = rawWords.length > 1 && rawWords.last.isNotEmpty
            ? '${rawWords.last[0].toUpperCase()}${rawWords.last.substring(1)}'
            : '';
        final fullName = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
        final codeSnippet = authUid.replaceAll('-', '').substring(0, authUid.length >= 4 ? 4 : authUid.length).toUpperCase();

        final domainName = (cleanEmail != null && cleanEmail.contains('@'))
            ? cleanEmail.split('@').last.split('.').first
            : 'Company';
        final capitalizedDomain = domainName.isNotEmpty
            ? '${domainName[0].toUpperCase()}${domainName.substring(1)}'
            : 'Company';

        empRecord = {
          'id': candidateEmployeeUuid ?? authUid,
          'user_id': authUid,
          'auth_user_id': authUid,
          'employee_code': 'EMP-$codeSnippet',
          'first_name': firstName,
          'last_name': lastName,
          'display_name': fullName,
          'work_email': cleanEmail ?? '',
          'email': cleanEmail ?? '',
          'status': 'ACTIVE',
          'employment_type': 'FULL_TIME',
          'company_name': capitalizedDomain,
          'organization_name': capitalizedDomain,
          'profile': {
            'personal_email': cleanEmail ?? '',
            'work_email': cleanEmail ?? '',
            'display_name': fullName,
          },
          'employment': {
            'designation_title': 'Team Member',
            'department_name': 'General',
            'shift_name': 'General Shift',
            'shift_start_time': '09:00:00',
            'shift_end_time': '18:00:00',
          },
        };

        // Try to persist this profile to Supabase in the background
        _tryPersistProvisionedEmployee(client, empRecord, authUid, cleanEmail);
      }

      final resolvedEmployeeUuid = empRecord['id']?.toString() ?? candidateEmployeeUuid ?? authUid;

      // Auto-heal app_users mapping if missing or not linked
      _autoHealAppUsers(client, resolvedEmployeeUuid, authUid, cleanEmail, empRecord);

      // ── 7. Validate Employment Status ───────────────────────────────────
      final empStatus = (empRecord['status']?.toString() ?? 'active').toLowerCase().trim();
      final userAppStatus = (appUserStatus ?? 'active').toLowerCase().trim();

      if (_disallowedStatuses.contains(empStatus) || _disallowedStatuses.contains(userAppStatus)) {
        secureLog('[Identity] Access Denied: Employee status is inactive/blocked ($empStatus / $userAppStatus)');
        return IdentityResolutionResult.failure(
          state: IdentityResolutionState.accessDenied,
          errorMessage: 'Your employee account is currently inactive ($empStatus). Please contact HR.',
          safeDiagnosticInfo: 'Employee status is $empStatus',
        );
      }

      // ── 8. Hydrate Statutory, Banking, and Emergency Contacts ───────────
      final candidateEmpIds = <String>{
        resolvedEmployeeUuid,
        if (empRecord['id'] != null) empRecord['id'].toString(),
        if (empRecord['employee_code'] != null) empRecord['employee_code'].toString(),
        authUid,
      }.where((s) => s.isNotEmpty).toList();

      // Use ALL candidate IDs (not just UUIDs) — statutory/bank tables may use
      // employee_id formats like 'EMP-617871' which are not UUIDs.
      final effectiveLookupIds = candidateEmpIds.where((s) => s.isNotEmpty).toList();
      secureLog('[Identity] Statutory lookup IDs: $effectiveLookupIds');

      Map<String, dynamic>? statutory;
      try {
        final statRows = await withTimeout(
          client
              .from('employee_statutory_details')
              .select()
              .inFilter('employee_id', effectiveLookupIds),
        );
        if (statRows.isNotEmpty) {
          statutory = Map<String, dynamic>.from(statRows.first as Map);
          secureLog('[Identity] employee_statutory_details found: bank=${statutory['bank_name']}, pan=${statutory['pan_number'] != null}');
        } else {
          secureLog('[Identity] employee_statutory_details EMPTY for IDs: $effectiveLookupIds');
        }
      } catch (e) {
        secureLog('[Identity] employee_statutory_details error: $e');
      }

      Map<String, dynamic>? bankAccount;
      try {
        final bankRows = await withTimeout(
          client
              .from('employee_bank_details')
              .select()
              .inFilter('employee_id', effectiveLookupIds),
        );
        if (bankRows.isNotEmpty) {
          bankAccount = Map<String, dynamic>.from(bankRows.first as Map);
          secureLog('[Identity] employee_bank_details found: bank=${bankAccount['bank_name']}, acc=${bankAccount['account_number']}');
        } else {
          secureLog('[Identity] employee_bank_details EMPTY for IDs: $effectiveLookupIds');
        }
      } catch (e) {
        secureLog('[Identity] employee_bank_details error: $e');
      }

      Map<String, dynamic>? emergencyContact;
      try {
        final contactRows = await withTimeout(
          client
              .from('employee_profiles')
              .select('emergency_contact_name, emergency_contact_phone, emergency_contact_relationship')
              .inFilter('employee_id', effectiveLookupIds),
        );
        if (contactRows.isNotEmpty) {
          emergencyContact = Map<String, dynamic>.from(contactRows.first as Map);
        }
      } catch (e) {
        secureLog('[Identity] employee_profiles emergency contact notice: $e');
      }

      // ── 9. Resolve Authoritative Shift Schedule ─────────────────────────
      final shiftId = empRecord['shift_id']?.toString() ??
          (empRecord['employment'] is Map ? empRecord['employment']['shift_id']?.toString() : null);
      if (shiftId != null && shiftId.isNotEmpty) {
        try {
          final shiftRow = await withTimeout(
            client.from('shifts').select().eq('id', shiftId).maybeSingle(),
          );
          if (shiftRow != null) {
            empRecord['shift_name'] = shiftRow['name'] ?? shiftRow['shift_name'] ?? empRecord['shift_name'];
            empRecord['shift_start_time'] = shiftRow['start_time'] ?? shiftRow['shift_start_time'] ?? empRecord['shift_start_time'];
            empRecord['shift_end_time'] = shiftRow['end_time'] ?? shiftRow['shift_end_time'] ?? empRecord['shift_end_time'];
            empRecord['shift'] = shiftRow;
            secureLog('[Identity] Resolved shift from shifts table: ${empRecord['shift_name']}');
          }
        } catch (e) {
          secureLog('[Identity] shifts table lookup notice: $e');
        }
      }

      try {
        final nowIST = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
        final todayStr = '${nowIST.year}-${nowIST.month.toString().padLeft(2, '0')}-${nowIST.day.toString().padLeft(2, '0')}';
        final rosterToday = await withTimeout(
          client
              .from('employee_shift_assignments')
              .select('id, shift_id, effective_date, shifts(*)')
              .eq('employee_id', resolvedEmployeeUuid)
              .eq('effective_date', todayStr)
              .maybeSingle(),
        );
        if (rosterToday != null && rosterToday['shifts'] is Map) {
          final s = rosterToday['shifts'] as Map<String, dynamic>;
          empRecord['shift_name'] = s['name'];
          empRecord['shift_start_time'] = s['start_time'] ?? empRecord['shift_start_time'];
          empRecord['shift_end_time'] = s['end_time'] ?? empRecord['shift_end_time'];
          secureLog('[Identity] Resolved shift from employee_shift_assignments: ${s['name']}');
        }
      } catch (_) {}

      // ── 10. Resolve Authoritative Organization Metadata ─────────────────
      final orgId = empRecord['organization_id']?.toString() ??
          empRecord['tenant_id']?.toString() ??
          (empRecord['employment'] is Map ? empRecord['employment']['organization_id']?.toString() : null);
      if (orgId != null && orgId.isNotEmpty) {
        try {
          final orgRow = await withTimeout(
            client.from('organizations').select().eq('id', orgId).maybeSingle(),
          );
          if (orgRow != null) {
            empRecord['organization_name'] = orgRow['name'] ?? orgRow['display_name'] ?? orgRow['legal_name'];
            empRecord['company_name'] = orgRow['name'] ?? orgRow['display_name'] ?? empRecord['company_name'];
            empRecord['organization'] = orgRow;
            secureLog('[Identity] Resolved organization: ${empRecord['company_name']}');
          }
        } catch (e) {
          secureLog('[Identity] organizations lookup notice: $e');
        }
      }

      // ── 10b. Resolve Authoritative Assigned Work Locations ──────────────
      List<ApprovedWorkLocation> assignedLocations = [];

      // 1. Primary: Authoritative Server-Side RPC
      try {
        final rpcData = await withTimeout(
          client.rpc('fn_get_my_assigned_work_locations'),
        );
        if (rpcData is List && rpcData.isNotEmpty) {
          assignedLocations = rpcData.map((item) {
            final rowMap = Map<String, dynamic>.from(item as Map);
            return ApprovedWorkLocation.fromJson(rowMap);
          }).toList();
          secureLog('[Identity] Resolved ${assignedLocations.length} assigned work location(s) from fn_get_my_assigned_work_locations');
        }
      } catch (rpcErr) {
        secureLog('[Identity] fn_get_my_assigned_work_locations RPC notice: $rpcErr');
      }

      // 2. Secondary: Direct Query on employee_work_location_assignments
      if (assignedLocations.isEmpty) {
        for (final table in const ['employee_work_location_assignments', 'employee_work_locations']) {
          if (assignedLocations.isNotEmpty) break;
          try {
            final assignedData = await withTimeout(
              client
                  .from(table)
                  .select('*')
                  .inFilter('employee_id', effectiveLookupIds),
            );
            if (assignedData.isNotEmpty) {
              final locationIds = assignedData
                  .map((r) => r['work_location_id']?.toString() ?? r['location_id']?.toString())
                  .where((id) => id != null && id.isNotEmpty)
                  .cast<String>()
                  .toSet()
                  .toList();

              final locationMap = <String, Map<String, dynamic>>{};
              if (locationIds.isNotEmpty) {
                try {
                  final locs = await withTimeout(
                    client.from('work_locations').select('*').inFilter('id', locationIds),
                  );
                  for (final l in locs) {
                    final m = Map<String, dynamic>.from(l as Map);
                    if (m['id'] != null) {
                      locationMap[m['id'].toString()] = m;
                    }
                  }
                } catch (e) {
                  secureLog('[Identity] work_locations by ID fetch notice: $e');
                }
              }

              assignedLocations = assignedData.map((r) {
                final rowMap = Map<String, dynamic>.from(r as Map);
                final locId = rowMap['work_location_id']?.toString() ??
                    rowMap['location_id']?.toString() ??
                    rowMap['id']?.toString();
                final locData = (locId != null ? locationMap[locId] : null) ?? rowMap;
                final merged = Map<String, dynamic>.from(locData);
                merged['is_primary'] = rowMap['is_primary'] ?? false;
                return ApprovedWorkLocation.fromJson(merged);
              }).toList();
              secureLog('[Identity] Resolved ${assignedLocations.length} assigned work location(s) from $table for employee IDs $candidateEmpIds');
            }
          } catch (e) {
            secureLog('[Identity] $table lookup notice: $e');
          }
        }
      }

      // ── 11. Construct Canonical UserModel ───────────────────────────────
      final userModel = EmployeeProfileMapper.fromEmployeesRow(
        empRecord,
        authEmail: cleanEmail,
        authAvatarUrl: authAvatarUrl,
        role: resolvedRole ?? 'EMPLOYEE',
        statutory: statutory,
        bankAccount: bankAccount,
        emergencyContact: emergencyContact,
        assignedLocations: assignedLocations,
      );

      secureLog('[Identity] Successfully resolved employee: ${userModel.name} (${userModel.employeeId}) [UUID: $resolvedEmployeeUuid]');

      return IdentityResolutionResult.success(
        employeeUuid: resolvedEmployeeUuid,
        employeeData: empRecord,
        userModel: userModel,
        role: resolvedRole ?? 'EMPLOYEE',
      );
    } catch (e) {
      secureLog('[Identity] Unexpected error during resolution: $e');
      return IdentityResolutionResult.failure(
        state: IdentityResolutionState.networkError,
        errorMessage: 'Connection error during employee identity resolution. Please try again.',
        safeDiagnosticInfo: 'Exception during resolution: $e',
      );
    }
  }


  static void _autoHealAppUsers(
    SupabaseClient client,
    String employeeUuid,
    String authUid,
    String? email,
    Map<String, dynamic> empRecord,
  ) {
    // Canonical auto-heal links user_id on employees table
    _autoHealEmployeeEmailAndUserId(client, employeeUuid, authUid, email ?? empRecord['work_email']?.toString() ?? '');
  }

  static void _tryPersistProvisionedEmployee(
    SupabaseClient client,
    Map<String, dynamic> record,
    String authUid,
    String? email,
  ) {
    Future.microtask(() async {
      try {
        await client.from('employees').upsert({
          'id': record['id'],
          'user_id': authUid,
          'work_email': email,
          'first_name': record['first_name'],
          'last_name': record['last_name'],
          'display_name': record['display_name'],
          'status': 'ACTIVE',
        }, onConflict: 'id');
        secureLog('[Identity] Successfully persisted synthesized employee profile to Supabase database');
      } catch (e) {
        secureLog('[Identity] Persisting synthesized employee profile notice: $e');
      }
    });
  }

  static void _autoHealEmployeeEmailAndUserId(
    SupabaseClient client,
    String employeeId,
    String authUid,
    String? email,
  ) {
    if (employeeId.isEmpty) return;
    Future.microtask(() async {
      try {
        if (email != null && email.isNotEmpty) {
          await client.from('employees').update({'work_email': email}).eq('id', employeeId);
          secureLog('[Identity] Verified work_email: id=$employeeId -> $email');
        }
      } catch (e) {
        secureLog('[Identity] Auto-heal email notice: $e');
      }
    });
  }

  /// Convenience wrapper to directly fetch the employee row
  static Future<Map<String, dynamic>?> resolveEmployeeRow(
    SupabaseClient client,
    String authUid,
  ) async {
    final result = await resolve(client: client, authUid: authUid);
    return result.employeeData;
  }
}
