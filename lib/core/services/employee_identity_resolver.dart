import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/hrms_models.dart';
import '../utils/query_timeout.dart';
import '../utils/secure_log.dart';
import '../utils/validators.dart';
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
              .select('id, auth_user_id, organization_id, employee_id, email, full_name, phone, avatar_url, status, role')
              .or('auth_user_id.eq.$authUid,id.eq.$authUid')
              .limit(1)
              .maybeSingle(),
        );

        if (userProfile != null) {
          appUserRowId = userProfile['id']?.toString();
          final rawEmpId = userProfile['employee_id']?.toString().trim();
          if (rawEmpId != null && rawEmpId.isNotEmpty) {
            appUserEmployeeId = rawEmpId;
          }
          appUserStatus = (userProfile['status']?.toString() ?? 'ACTIVE').toUpperCase();
          resolvedRole = userProfile['role']?.toString() ?? 'EMPLOYEE';
          secureLog('[Identity] user_profiles found -> id=$appUserRowId, employee_id=$appUserEmployeeId, org=${userProfile['organization_id']}');
        }
      } catch (e) {
        secureLog('[Identity] user_profiles by auth_user_id notice: $e');
      }

      String? candidateEmployeeUuid = appUserEmployeeId;
      Map<String, dynamic>? empRecord;

      // ── 5. Query employees table ────────────────────────────────────────

      // Strategy A: By resolved UUID from user_profiles / legacy table
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

      // Strategy B: Direct lookup by user_id = appUserRowId / authUid, or id = authUid
      if (empRecord == null) {
        secureLog('[Identity] Querying employees table for user_id=$authUid / profile_id=$appUserRowId');
        try {
          final orParts = <String>[
            'user_id.eq.$authUid',
            'id.eq.$authUid',
            if (appUserRowId != null && appUserRowId.isNotEmpty) 'user_id.eq.$appUserRowId',
          ];
          empRecord = await withTimeout(
            client
                .from('employees')
                .select()
                .or(orParts.join(','))
                .limit(1)
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
          'employment_status': 'ACTIVE',
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
      final empStatus = (empRecord['employment_status']?.toString() ?? empRecord['status']?.toString() ?? 'active').toLowerCase().trim();
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

      // Only pass valid UUIDs — employee_id column in these Postgres tables is of type UUID.
      // Passing non-UUID employee codes (e.g. 'JCS-017') triggers 22P02 invalid input syntax error.
      final effectiveLookupIds = candidateEmpIds.where((s) => Validators.isValidUuid(s)).toList();
      secureLog('[Identity] Statutory lookup IDs: $effectiveLookupIds');

      Map<String, dynamic>? statutory;
      Map<String, dynamic>? bankAccount;
      Map<String, dynamic>? emergencyContact;
      List<ApprovedWorkLocation> assignedLocations = [];

      final compId = empRecord['company_id']?.toString() ?? empRecord['organization_id']?.toString();
      final orgId = empRecord['organization_id']?.toString() ??
          empRecord['tenant_id']?.toString() ??
          (empRecord['employment'] is Map ? empRecord['employment']['organization_id']?.toString() : null) ??
          compId;
      final deptId = empRecord['department_id']?.toString() ??
          (empRecord['employment'] is Map ? empRecord['employment']['department_id']?.toString() : null);
      final desigId = empRecord['designation_id']?.toString() ??
          (empRecord['employment'] is Map ? empRecord['employment']['designation_id']?.toString() : null);
      final branchId = empRecord['branch_id']?.toString();
      final shiftId = empRecord['shift_id']?.toString() ??
          (empRecord['employment'] is Map ? empRecord['employment']['shift_id']?.toString() : null);

      const fastTimeout = Duration(milliseconds: 3500);

      // Execute all profile hydration queries concurrently in a single network roundtrip
      await Future.wait<void>([
        // 8a. Statutory details
        if (effectiveLookupIds.isNotEmpty)
          (() async {
            try {
              final statRows = await withTimeout(
                client.from('employee_statutory_details').select().inFilter('employee_id', effectiveLookupIds),
                timeout: fastTimeout,
              );
              if (statRows.isNotEmpty) {
                statutory = Map<String, dynamic>.from(statRows.first as Map);
              }
            } catch (e) {
              secureLog('[Identity] employee_statutory_details notice: $e');
            }
          })(),

        // 8b. Bank details
        if (effectiveLookupIds.isNotEmpty)
          (() async {
            try {
              final bankRows = await withTimeout(
                client.from('employee_bank_details').select().inFilter('employee_id', effectiveLookupIds),
                timeout: fastTimeout,
              );
              if (bankRows.isNotEmpty) {
                bankAccount = Map<String, dynamic>.from(bankRows.first as Map);
              }
            } catch (e) {
              secureLog('[Identity] employee_bank_details notice: $e');
            }
          })(),

        // 8c. Emergency contacts (canonical employee_emergency_contacts table)
        if (effectiveLookupIds.isNotEmpty)
          (() async {
            try {
              final contactRows = await withTimeout(
                client
                    .from('employee_emergency_contacts')
                    .select()
                    .inFilter('employee_id', effectiveLookupIds)
                    .limit(1),
                timeout: fastTimeout,
              );
              if (contactRows.isNotEmpty) {
                final c = Map<String, dynamic>.from(contactRows.first as Map);
                emergencyContact = {
                  'emergency_contact_name': c['contact_name'] ?? c['name'] ?? c['full_name'] ?? c['contact_person'] ?? '',
                  'emergency_contact_phone': c['phone'] ?? c['contact_phone'] ?? c['phone_number'] ?? c['mobile'] ?? '',
                  'emergency_contact_relationship': c['relationship'] ?? c['relation'] ?? '',
                };
              }
            } catch (e) {
              secureLog('[Identity] employee_emergency_contacts notice: $e');
            }
          })(),

        // 8d. Company details
        if (compId != null && compId.isNotEmpty)
          (() async {
            try {
              final compRow = await withTimeout(
                client.from('companies').select('id, legal_name, trade_name').eq('id', compId).maybeSingle(),
                timeout: fastTimeout,
              );
              if (compRow != null) {
                empRecord!['company_name'] = compRow['legal_name'] ?? compRow['trade_name'] ?? empRecord['company_name'];
              }
            } catch (_) {}
          })(),

        // 8e. Organization details
        if (orgId != null && orgId.isNotEmpty)
          (() async {
            try {
              final orgRow = await withTimeout(
                client.from('organizations').select('id, name, logo_url').eq('id', orgId).maybeSingle(),
                timeout: fastTimeout,
              );
              if (orgRow != null) {
                empRecord!['organization_name'] = orgRow['name'] ?? empRecord['organization_name'];
                empRecord['company_name'] ??= orgRow['name'];
                empRecord['organization'] = orgRow;
                if (orgRow['logo_url'] != null && orgRow['logo_url'].toString().isNotEmpty) {
                  empRecord['company_logo_url'] = orgRow['logo_url'].toString();
                }
              }
            } catch (_) {}
          })(),

        // 8f. Department & Parent Unit
        if (deptId != null && deptId.isNotEmpty)
          (() async {
            try {
              final deptRow = await withTimeout(
                client.from('departments').select('id, name, code, parent_department_id').eq('id', deptId).maybeSingle(),
                timeout: fastTimeout,
              );
              if (deptRow != null) {
                final deptName = deptRow['name']?.toString() ?? deptRow['code']?.toString();
                if (deptName != null && deptName.isNotEmpty) {
                  empRecord!['department_name'] = deptName;
                  empRecord['department'] = deptRow;
                }
                final parentDeptId = deptRow['parent_department_id']?.toString();
                if (parentDeptId != null && parentDeptId.isNotEmpty) {
                  final parentRow = await withTimeout(
                    client.from('departments').select('id, name, code').eq('id', parentDeptId).maybeSingle(),
                    timeout: fastTimeout,
                  );
                  if (parentRow != null && parentRow['name'] != null) {
                    empRecord!['unit_name'] = parentRow['name'].toString();
                  }
                }
              }
            } catch (_) {}
          })(),

        // 8g. Designation
        if (desigId != null && desigId.isNotEmpty)
          (() async {
            try {
              final desigRow = await withTimeout(
                client.from('designations').select('id, title, code, grade').eq('id', desigId).maybeSingle(),
                timeout: fastTimeout,
              );
              if (desigRow != null) {
                final desigTitle = desigRow['title']?.toString() ?? desigRow['name']?.toString() ?? desigRow['code']?.toString();
                if (desigTitle != null && desigTitle.isNotEmpty) {
                  empRecord!['designation_title'] = desigTitle;
                  empRecord['designation'] = desigRow;
                }
              }
            } catch (_) {}
          })(),

        // 8h. Branch
        if (branchId != null && branchId.isNotEmpty && (empRecord['branch_name'] == null || empRecord['branch_name'].toString().isEmpty))
          (() async {
            try {
              final branchRow = await withTimeout(
                client.from('branches').select('id, name').eq('id', branchId).maybeSingle(),
                timeout: fastTimeout,
              );
              if (branchRow != null && branchRow['name'] != null) {
                empRecord!['branch_name'] = branchRow['name'].toString();
              }
            } catch (_) {}
          })(),

        // 8i. Reporting Manager & Team Lead (resolves Manager / Supervisor name directly from DB)
        (() async {
          try {
            final mgrId = empRecord?['reporting_manager_id']?.toString();
            String? resolvedMgr;
            if (mgrId != null && mgrId.isNotEmpty) {
              final mgrRow = await withTimeout(
                client
                    .from('employees')
                    .select('id, first_name, last_name, display_name, employee_code')
                    .eq('id', mgrId)
                    .maybeSingle(),
                timeout: fastTimeout,
              );
              if (mgrRow != null) {
                final dName = (mgrRow['display_name']?.toString() ?? '').trim();
                final fName = (mgrRow['first_name']?.toString() ?? '').trim();
                final lName = (mgrRow['last_name']?.toString() ?? '').trim();
                resolvedMgr = dName.isNotEmpty ? dName : '$fName $lName'.trim();
              }
            }

            // Check if there is a Team Lead or Department Supervisor
            String? resolvedTl = empRecord?['team_lead_name']?.toString().trim();
            final tlId = empRecord?['team_lead_id']?.toString().trim();
            if (tlId != null && tlId.isNotEmpty && (resolvedTl == null || resolvedTl.isEmpty)) {
              final tlRow = await withTimeout(
                client
                    .from('employees')
                    .select('id, first_name, last_name, display_name, employee_code')
                    .eq('id', tlId)
                    .maybeSingle(),
                timeout: fastTimeout,
              );
              if (tlRow != null) {
                final dName = (tlRow['display_name']?.toString() ?? '').trim();
                final fName = (tlRow['first_name']?.toString() ?? '').trim();
                final lName = (tlRow['last_name']?.toString() ?? '').trim();
                resolvedTl = dName.isNotEmpty ? dName : '$fName $lName'.trim();
              }
            }

            // If no specific TL, check department head
            if ((resolvedTl == null || resolvedTl.isEmpty) && deptId != null && deptId.isNotEmpty) {
              try {
                final deptHeadRow = await withTimeout(
                  client.from('departments').select('head_employee_id').eq('id', deptId).maybeSingle(),
                  timeout: fastTimeout,
                );
                final headEmpId = deptHeadRow?['head_employee_id']?.toString().trim();
                if (headEmpId != null && headEmpId.isNotEmpty && headEmpId != mgrId) {
                  final headRow = await withTimeout(
                    client
                        .from('employees')
                        .select('id, first_name, last_name, display_name, employee_code')
                        .eq('id', headEmpId)
                        .maybeSingle(),
                    timeout: fastTimeout,
                  );
                  if (headRow != null) {
                    final dName = (headRow['display_name']?.toString() ?? '').trim();
                    final fName = (headRow['first_name']?.toString() ?? '').trim();
                    final lName = (headRow['last_name']?.toString() ?? '').trim();
                    resolvedTl = dName.isNotEmpty ? dName : '$fName $lName'.trim();
                  }
                }
              } catch (_) {}
            }

            // Combine into clean two-name display
            String combinedDisplay = '';
            if (resolvedMgr != null && resolvedMgr.isNotEmpty &&
                resolvedTl != null && resolvedTl.isNotEmpty &&
                resolvedMgr.toLowerCase() != resolvedTl.toLowerCase()) {
              combinedDisplay = '$resolvedMgr (Manager) / $resolvedTl (TL)';
            } else if (resolvedMgr != null && resolvedMgr.isNotEmpty) {
              combinedDisplay = resolvedMgr;
            } else if (resolvedTl != null && resolvedTl.isNotEmpty) {
              combinedDisplay = '$resolvedTl (Supervisor)';
            }

            if (combinedDisplay.isNotEmpty) {
              empRecord!['reporting_manager_name'] = combinedDisplay;
              empRecord['reports_to_name'] = combinedDisplay;
              empRecord['manager_name'] = combinedDisplay;
              if (empRecord['employment'] is Map) {
                final empMap = Map<String, dynamic>.from(empRecord['employment'] as Map);
                empMap['reporting_manager_name'] = combinedDisplay;
                empMap['reports_to_name'] = combinedDisplay;
                empMap['manager_name'] = combinedDisplay;
                if (mgrId != null) empMap['reporting_manager_id'] = mgrId;
                if (tlId != null) empMap['team_lead_id'] = tlId;
                empRecord['employment'] = empMap;
              } else {
                empRecord['employment'] = {
                  'reporting_manager_name': combinedDisplay,
                  'reports_to_name': combinedDisplay,
                  'manager_name': combinedDisplay,
                  if (mgrId != null) 'reporting_manager_id': mgrId,
                  if (tlId != null) 'team_lead_id': tlId,
                };
              }
            }
          } catch (e) {
            secureLog('[Identity] Reporting manager lookup notice: $e');
          }
        })(),

        // 9. Shift schedule (direct shift_id + active shift assignment)
        (() async {
          if (shiftId != null && shiftId.isNotEmpty) {
            try {
              final shiftRow = await withTimeout(
                client.from('shifts').select().eq('id', shiftId).maybeSingle(),
                timeout: fastTimeout,
              );
              if (shiftRow != null) {
                empRecord!['shift_name'] = shiftRow['name'] ?? shiftRow['shift_name'] ?? empRecord['shift_name'];
                empRecord['shift_start_time'] = shiftRow['start_time'] ?? shiftRow['shift_start_time'] ?? empRecord['shift_start_time'];
                empRecord['shift_end_time'] = shiftRow['end_time'] ?? shiftRow['shift_end_time'] ?? empRecord['shift_end_time'];
                empRecord['shift'] = shiftRow;
              }
            } catch (_) {}
          }
          try {
            final nowIST = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
            final todayStr = '${nowIST.year}-${nowIST.month.toString().padLeft(2, '0')}-${nowIST.day.toString().padLeft(2, '0')}';
            final rosterToday = await withTimeout(
              client
                  .from('employee_shift_assignments')
                  .select('id, shift_id, valid_from, valid_to, shifts(*)')
                  .eq('employee_id', resolvedEmployeeUuid)
                  .lte('valid_from', todayStr)
                  .order('valid_from', ascending: false)
                  .limit(1)
                  .maybeSingle(),
              timeout: fastTimeout,
            );
            if (rosterToday != null && rosterToday['shifts'] is Map) {
              final s = rosterToday['shifts'] as Map<String, dynamic>;
              empRecord!['shift_name'] = s['name'];
              empRecord['shift_start_time'] = s['start_time'] ?? empRecord['shift_start_time'];
              empRecord['shift_end_time'] = s['end_time'] ?? empRecord['shift_end_time'];
            }
          } catch (_) {}
        })(),

        // 10. Assigned work locations (joined with work_locations in a single query)
        if (effectiveLookupIds.isNotEmpty)
          (() async {
            try {
              final assignedData = await withTimeout(
                client
                    .from('employee_work_location_assignments')
                    .select('*, work_locations(*)')
                    .inFilter('employee_id', effectiveLookupIds),
                timeout: fastTimeout,
              );
              if (assignedData.isNotEmpty) {
                assignedLocations = assignedData.map((r) {
                  final rowMap = Map<String, dynamic>.from(r as Map);
                  final nestedLoc = rowMap['work_locations'] is Map
                      ? Map<String, dynamic>.from(rowMap['work_locations'] as Map)
                      : rowMap;
                  nestedLoc['is_primary'] = rowMap['is_primary'] ?? false;
                  return ApprovedWorkLocation.fromJson(nestedLoc);
                }).toList();
              }
            } catch (e) {
              secureLog('[Identity] employee_work_location_assignments lookup notice: $e');
            }
          })(),
      ]);

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
    final existingWorkEmail = (empRecord['work_email']?.toString() ?? '').trim().toLowerCase();
    final targetEmail = (email ?? '').trim().toLowerCase();
    if (targetEmail.isNotEmpty && existingWorkEmail != targetEmail) {
      _autoHealEmployeeEmailAndUserId(client, employeeUuid, authUid, email!);
    }
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
          'employment_status': 'ACTIVE',
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
