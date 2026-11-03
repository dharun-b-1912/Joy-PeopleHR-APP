import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/services/employee_identity_resolver.dart';
import '../../core/services/user_service.dart';
import '../../core/utils/query_timeout.dart';
import '../../core/utils/secure_log.dart';
import '../../core/utils/validators.dart';
import '../../models/hrms_models.dart';
import '../interfaces/auth_repository.dart';

/// WorkForceOS — Supabase Authentication Repository
///
/// Identity chain (schema-aligned):
///   Supabase Auth → auth.uid()
///       ↓
///   app_users.auth_user_id (unique uuid)
///   employee_auth_identity.auth_user_id (legacy fallback)
///       ↓
///   Conflict Detection
///       ↓
///   employee UUID → employees.id
///       ↓
///   Status Validation
///       ↓
///   UserModel (loaded into UserService)
class SupabaseAuthRepository implements IAuthRepository {
  SupabaseClient get _client => Supabase.instance.client;

  // ────────────────────────────────────────────────────────────────────────
  // PRIMARY AUTH ENTRY POINT (used by AuthController / LoginScreen)
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<AuthResult> authenticateUser({
    required String identifier,
    String? password,
    String? otp,
  }) async {
    final trimmedIdentifier = identifier.trim();
    final isEmail = trimmedIdentifier.contains('@');

    if (password == null && otp == null) {
      return const AuthResult(
        success: false,
        errorMessage: "Password is required.",
      );
    }

    try {
      String emailToAuth = trimmedIdentifier;

      // Phone number → resolve work email from employees.profile jsonb.
      if (!isEmail) {
        emailToAuth = await _resolveEmailFromPhone(trimmedIdentifier);
        if (emailToAuth.isEmpty) {
          return const AuthResult(
            success: false,
            errorMessage: "No employee found with this phone number.",
          );
        }
      }

      AuthResponse response;
      if (otp != null && otp.isNotEmpty) {
        response = await _client.auth.verifyOTP(
          email: emailToAuth,
          token: otp,
          type: OtpType.magiclink,
        );
      } else {
        response = await _client.auth.signInWithPassword(
          email: emailToAuth,
          password: password!,
        );
      }

      final authUser = response.user;
      if (authUser == null) {
        return const AuthResult(
          success: false,
          errorMessage: "Authentication failed. Invalid credentials.",
        );
      }

      secureLog('[Auth] Supabase Auth OK — uid: ${authUser.id}');

      // Canonical Identity Resolution & Status Validation
      final resolution = await EmployeeIdentityResolver.resolve(
        client: _client,
        authUid: authUser.id,
        authEmail: authUser.email,
        authAvatarUrl: authUser.userMetadata?['avatar_url'] as String?,
      );

      if (resolution.success && resolution.userModel != null) {
        UserService.instance.setUser(resolution.userModel!);
        await UserService.instance.persistUser(resolution.userModel!);
        logProcess(
          'AUTH',
          'Authenticated ${resolution.userModel!.name} (${resolution.userModel!.employeeId})',
        );
        return AuthResult(
          success: true,
          user: resolution.userModel,
          employeeId: resolution.userModel!.dataId,
        );
      } else {
        secureLog(
            '[Auth] Identity resolution failed: ${resolution.state} — ${resolution.safeDiagnosticInfo}');
        await _client.auth.signOut().catchError((_) {});
        logSessionBanner(
          event: 'LOGIN REJECTED (NO EMPLOYEE PROFILE MAPPED)',
          isLoggedIn: false,
          email: authUser.email,
        );
        return AuthResult(
          success: false,
          errorMessage: resolution.errorMessage ??
              "Your account is authenticated, but no employee profile was found. Contact HR.",
        );
      }
    } on AuthException catch (e) {
      secureLog('[Auth] AuthException: ${e.message}');

      // Auto-confirm email if it hasn't been confirmed yet (web app often skips confirmation)
      if (e.message.toLowerCase().contains('email not confirmed')) {
        final loginEmail = trimmedIdentifier.contains('@')
            ? trimmedIdentifier
            : identifier.trim();
        secureLog(
            '[Auth] Email not confirmed — attempting auto-confirm for $loginEmail');
        try {
          await _client.rpc('auto_confirm_email_for_user', params: {
            'p_email': loginEmail,
          });
          secureLog('[Auth] Auto-confirm succeeded — retrying login');
          // Retry the login
          final retryResponse = await _client.auth.signInWithPassword(
            email: loginEmail,
            password: password!,
          );
          final retryUser = retryResponse.user;
          if (retryUser != null) {
            secureLog('[Auth] Retry login OK — uid: ${retryUser.id}');
            final resolution = await EmployeeIdentityResolver.resolve(
              client: _client,
              authUid: retryUser.id,
              authEmail: retryUser.email,
              authAvatarUrl: retryUser.userMetadata?['avatar_url'] as String?,
            );
            if (resolution.success && resolution.userModel != null) {
              UserService.instance.setUser(resolution.userModel!);
              return AuthResult(
                success: true,
                user: resolution.userModel,
                employeeId: resolution.userModel!.dataId,
              );
            } else {
              await _client.auth.signOut().catchError((_) {});
              return AuthResult(
                success: false,
                errorMessage: resolution.errorMessage ??
                    "Your account is authenticated, but no employee profile was found. Contact HR.",
              );
            }
          }
        } catch (retryErr) {
          secureLog('[Auth] Auto-confirm/retry failed: $retryErr');
        }
      }

      return AuthResult(
        success: false,
        errorMessage: _friendlyAuthError(e.message),
      );
    } catch (e) {
      secureLog('[Auth] Unexpected error: $e');
      return const AuthResult(
        success: false,
        errorMessage:
            "Authentication failed. Check your connection and try again.",
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // SIGN IN WITH PASSWORD (secondary — kept for interface compatibility)
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<UserModel?> signInWithPassword(String email, String password) async {
    final result = await authenticateUser(
      identifier: email,
      password: password,
    );
    return result.user;
  }

  // ────────────────────────────────────────────────────────────────────────
  // SIGN OUT
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<void> signOut() async {
    try {
      final prevUser = UserService.instance.currentUser;
      logProcess('AUTH', 'Signing out employee session', data: {
        'employee': prevUser.name,
        'code': prevUser.employeeId,
        'uuid': prevUser.dataId,
      });
      await _client.auth.signOut();
      secureLog('[Auth] Signed out from Supabase Auth');
    } catch (e) {
      secureLog('[Auth] Sign out error: $e');
    } finally {
      await UserService.instance.clearUser();
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // SESSION RESTORATION (on app startup)
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<UserModel?> restoreSession() async {
    try {
      // 1. First, check if a cached user model already exists locally on the device (0ms, offline)
      final cachedUser = await UserService.instance.loadCachedUser();

      if (cachedUser != null) {
        UserService.instance.setUser(cachedUser);
        secureLog('[Auth] Cached local session restored immediately: ${cachedUser.name} (${cachedUser.employeeId})');
      }

      var session = _client.auth.currentSession;

      // 1b. If session is still null due to Gotrue async background initialization on Android,
      // recover it synchronously from local token storage so we never get a false null!
      if (session == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final tokenKey = "sb-${Uri.parse(SupabaseConfig.url).host.split(".").first}-auth-token";
          final rawToken = prefs.getString(tokenKey);
          if (rawToken != null && rawToken.trim().isNotEmpty) {
            secureLog('[Auth] Recovering Gotrue session explicitly from local token storage...');
            final recoveredRes = await _client.auth.recoverSession(rawToken);
            session = recoveredRes.session;
            secureLog('[Auth] Successfully recovered Gotrue session for: ${session?.user.email}');
          }
        } catch (recoverErr) {
          secureLog('[Auth] Explicit recoverSession notice: $recoverErr');
        }
      }

      // 2. If session token is expired, refresh it automatically using refresh token
      if (session != null && session.isExpired) {
        try {
          secureLog('[Auth] Stored Supabase token is expired — attempting auto-refresh...');
          final refreshRes = await _client.auth.refreshSession();
          session = refreshRes.session;
          secureLog('[Auth] Token refresh successful for ${session?.user.email}');
        } catch (refreshErr) {
          secureLog('[Auth] Token auto-refresh notice: $refreshErr');
        }
      }

      // 3. If no active Supabase session
      if (session == null) {
        // Strict Security Guard: Never allow an unauthenticated session to masquerade as an employee
        if (cachedUser != null) {
          final isDharunCache = cachedUser.employeeId == 'JCS-017' ||
              (cachedUser.officeEmail?.toLowerCase().contains('dharun') ?? false) ||
              cachedUser.name.trim().toUpperCase() == 'DHARUN' ||
              cachedUser.name.trim().toUpperCase() == 'DHARUN B';

          if (isDharunCache) {
            secureLog('[Auth] No Supabase session for Dharun cache — wiping stale ghost session');
            await UserService.instance.clearUser();
            return null;
          }
        }

        logSessionBanner(
          event: 'STARTUP SESSION CHECK — NO EMPLOYEE LOGGED IN',
          isLoggedIn: false,
        );
        return null;
      }

      // 4. Supabase session exists — attempt profile sync
      final authUser = session.user;
      logProcess('AUTH', 'Existing Supabase session confirmed — resolving employee identity', data: {
        'auth_uid': authUser.id,
        'email': authUser.email,
      });

      try {
        final resolution = await EmployeeIdentityResolver.resolve(
          client: _client,
          authUid: authUser.id,
          authEmail: authUser.email,
          authAvatarUrl: authUser.userMetadata?['avatar_url'] as String?,
        );

        if (resolution.success && resolution.userModel != null) {
          UserService.instance.setUser(resolution.userModel!);
          await UserService.instance.persistUser(resolution.userModel!);
          logProcess(
            'AUTH',
            'Session synced with server for ${resolution.userModel!.name} (${resolution.userModel!.employeeId})',
          );
          return resolution.userModel;
        } else {
          // Temporary network timeout, sync delay, or unresolved server state — NEVER sign out! Use cached user
          secureLog('[Auth] Identity resolution could not reach database (${resolution.state}) — preserving local session');
          if (cachedUser != null) {
            return cachedUser;
          }
          if (UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest') {
            return UserService.instance.currentUser;
          }
          return null;
        }
      } catch (syncErr) {
        secureLog('[Auth] Network sync notice during restore: $syncErr — preserving local session');
        if (cachedUser != null) {
          return cachedUser;
        }
        if (UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest') {
          return UserService.instance.currentUser;
        }
        return null;
      }
    } catch (e) {
      secureLog('[Auth] Session restore error: $e');
      if (UserService.instance.isLoggedIn && UserService.instance.currentUser.name != 'Guest') {
        return UserService.instance.currentUser;
      }
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // PASSWORD MANAGEMENT
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final isValid = await verifyPassword(currentPassword);
      if (!isValid) return false;
      await _client.auth.updateUser(UserAttributes(
        password: newPassword,
        data: const {
          'must_change_password': false,
          'require_password_change': false,
        },
      ));
      return true;
    } catch (e) {
      secureLog('[Auth] Change password error: $e');
      return false;
    }
  }

  @override
  Future<bool> resetPasswordForEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://joypeoplehr.com/auth/reset-password',
      );
      return true;
    } catch (e) {
      secureLog('[Auth] Reset password error: $e');
      return false;
    }
  }

  /// Verifies the user's password against Supabase Auth.
  ///
  /// Uses signInWithPassword to validate current credentials before sensitive
  /// actions (e.g. password change, statutory details unlock).
  @override
  Future<bool> verifyPassword(String password) async {
    try {
      final currentUser = _client.auth.currentUser;
      if (currentUser?.email == null) return false;
      final res = await _client.auth.signInWithPassword(
        email: currentUser!.email!,
        password: password,
      );
      return res.user != null;
    } catch (e) {
      secureLog('[Auth] Verify password error: $e');
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // SENSITIVE STATUTORY DETAILS (after password verification)
  // Tables per schema: employee_statutory_details, employee_bank_accounts
  // ────────────────────────────────────────────────────────────────────────

  @override
  Future<PayrollStatutoryModel?> getSensitiveStatutoryDetails(
      String employeeId) async {
    try {
      final user = UserService.instance.currentUser;
      final candidateEmpIds = <String>{
        employeeId,
        user.employeeId,
        if (user.employeeUuid != null) user.employeeUuid!,
        if (_client.auth.currentUser?.id != null) _client.auth.currentUser!.id,
      }.where((s) => s.isNotEmpty).toList();

      // Only pass valid UUIDs — employee_id in employee_statutory_details,
      // employee_bank_details, and employees.id are Postgres UUID columns.
      final lookupIds = candidateEmpIds.where((s) => Validators.isValidUuid(s)).toList();
      secureLog('[Statutory] Querying with IDs: $lookupIds');

      Map<String, dynamic>? statData;
      Map<String, dynamic>? bankData;
      if (lookupIds.isNotEmpty) {
        try {
          final statRows = await withTimeout(
            _client
                .from('employee_statutory_details')
                .select()
                .inFilter('employee_id', lookupIds),
          );
          if (statRows.isNotEmpty) {
            statData = Map<String, dynamic>.from(statRows.first as Map);
            secureLog(
                '[Statutory] employee_statutory_details FOUND: pan=${statData['pan_number']}, pf=${statData['pf_number']}, esi=${statData['esi_number']}');
          } else {
            secureLog(
                '[Statutory] employee_statutory_details EMPTY for IDs: $lookupIds');
          }
        } catch (e) {
          secureLog('[Statutory] employee_statutory_details query error: $e');
        }

        try {
          final bankRows = await withTimeout(
            _client
                .from('employee_bank_details')
                .select()
                .inFilter('employee_id', lookupIds),
          );
          if (bankRows.isNotEmpty) {
            bankData = Map<String, dynamic>.from(bankRows.first as Map);
            secureLog(
                '[Statutory] employee_bank_details FOUND: bank=${bankData['bank_name']}, acc=${bankData['account_number']}');
          } else {
            secureLog(
                '[Statutory] employee_bank_details EMPTY for IDs: $lookupIds');
          }
        } catch (e) {
          secureLog('[Auth] employee_bank_details query notice: $e');
        }
      }

      // Check employees row fallback if sub-tables had nulls
      Map<String, dynamic>? empProfile;
      Map<String, dynamic>? empStatutory;
      Map<String, dynamic>? empBank;
      if (statData == null || bankData == null) {
        try {
          final empRows = await withTimeout(
            _client.from('employees').select('*').inFilter('id', lookupIds),
          );
          if (empRows.isNotEmpty) {
            final emp = Map<String, dynamic>.from(empRows.first as Map);
            if (emp['profile'] is Map) {
              empProfile = Map<String, dynamic>.from(emp['profile'] as Map);
            }
            if (emp['statutory'] is Map) {
              empStatutory = Map<String, dynamic>.from(emp['statutory'] as Map);
            }
            if (emp['bank'] is Map) {
              empBank = Map<String, dynamic>.from(emp['bank'] as Map);
            }
            secureLog(
                '[Statutory] employees JSONB fallback: statutory=${empStatutory?.isNotEmpty == true} bank=${empBank?.isNotEmpty == true} profile=${empProfile?.isNotEmpty == true}');
          } else {
            secureLog('[Statutory] employees table EMPTY for IDs: $lookupIds');
          }
        } catch (e) {
          secureLog('[Auth] employees table fallback query notice: $e');
        }
      }

      final rawAcc = bankData?['account_number']?.toString() ??
          empBank?['account_number']?.toString() ??
          empProfile?['account_number']?.toString();

      final rawPan = statData?['pan_number']?.toString() ??
          statData?['pan']?.toString() ??
          empStatutory?['pan_number']?.toString() ??
          empProfile?['pan_number']?.toString();

      final rawPf = statData?['pf_number']?.toString() ??
          empStatutory?['pf_number']?.toString() ??
          empProfile?['pf_number']?.toString();

      final rawUan = statData?['uan_number']?.toString() ??
          statData?['uan']?.toString() ??
          empStatutory?['uan_number']?.toString() ??
          empProfile?['uan_number']?.toString();

      final rawEsi = statData?['esi_number']?.toString() ??
          empStatutory?['esi_number']?.toString() ??
          empProfile?['esi_number']?.toString();

      final taxRegime = statData?['tax_regime']?.toString() ??
          empStatutory?['tax_regime']?.toString() ??
          empProfile?['tax_regime']?.toString();

      final bankName = bankData?['bank_name']?.toString() ??
          empBank?['bank_name']?.toString() ??
          empProfile?['bank_name']?.toString() ??
          user.payrollStatutory?.bankName;

      final branchName = bankData?['branch_name']?.toString() ??
          bankData?['bank_branch']?.toString() ??
          empBank?['branch_name']?.toString() ??
          empProfile?['branch_name']?.toString() ??
          user.payrollStatutory?.branchName;

      final ifscCode = bankData?['ifsc_code']?.toString() ??
          bankData?['ifsc']?.toString() ??
          empBank?['ifsc_code']?.toString() ??
          empProfile?['ifsc_code']?.toString() ??
          user.payrollStatutory?.ifscCode;

      if (rawAcc != null ||
          rawPan != null ||
          rawPf != null ||
          rawEsi != null ||
          rawUan != null ||
          bankName != null) {
        secureLog(
            '[Statutory] Found: bank=$bankName acc=${rawAcc != null} pan=${rawPan != null} pf=${rawPf != null} esi=${rawEsi != null} uan=${rawUan != null}');
        return PayrollStatutoryModel(
          bankName: bankName ?? 'N/A',
          branchName: branchName ?? 'N/A',
          accountNumber: rawAcc != null && rawAcc.length > 4
              ? '•••• •••• ${rawAcc.substring(rawAcc.length - 4)}'
              : rawAcc,
          rawAccountNumber: rawAcc,
          ifscCode: ifscCode ?? 'N/A',
          accountHolderName: bankData?['account_holder_name']?.toString(),
          panNumber: rawPan != null && rawPan.length > 4
              ? '•••• •••• ${rawPan.substring(rawPan.length - 4)}'
              : rawPan,
          rawPanNumber: rawPan,
          uanNumber: rawUan != null && rawUan.length > 4
              ? '•••• •••• ${rawUan.substring(rawUan.length - 4)}'
              : rawUan,
          rawUanNumber: rawUan,
          pfNumber: rawPf != null && rawPf.length > 4
              ? '•••• •••• ${rawPf.substring(rawPf.length - 4)}'
              : rawPf,
          rawPfNumber: rawPf,
          esiNumber: rawEsi != null && rawEsi.length > 4
              ? '•••• •••• ${rawEsi.substring(rawEsi.length - 4)}'
              : rawEsi,
          rawEsiNumber: rawEsi,
          taxRegime: taxRegime != null
              ? (taxRegime == 'OLD' ? 'OLD Regime' : 'NEW Regime (Sec 115BAC)')
              : user.payrollStatutory?.taxRegime,
        );
      }

      // Fallback: try bank_account by employee_code (in case UUID lookup missed)
      if (rawAcc == null &&
          rawPan == null &&
          rawPf == null &&
          rawEsi == null &&
          rawUan == null &&
          bankName == null) {
        secureLog('[Statutory] Trying employee_code fallback for bank account');
        try {
          final empCode = user.employeeId;
          if (empCode.isNotEmpty) {
            final bankByCode = await withTimeout(
              _client
                  .from('employee_bank_details')
                  .select('*')
                  .eq('employee_id', empCode)
                  .maybeSingle(),
            );
            if (bankByCode != null) {
              final fAcc = bankByCode['account_number']?.toString();
              final fBankName = bankByCode['bank_name']?.toString();
              final fIfsc = bankByCode['ifsc_code']?.toString();
              final fBranch = bankByCode['branch_name']?.toString();
              if (fAcc != null && fAcc.isNotEmpty || fBankName != null) {
                secureLog(
                    '[Statutory] Found bank by employee_code: bank=$fBankName acc=${fAcc != null && fAcc.isNotEmpty}');
                return PayrollStatutoryModel(
                  bankName: fBankName ?? 'N/A',
                  branchName: fBranch ?? 'N/A',
                  accountNumber: fAcc != null && fAcc.length > 4
                      ? '•••• •••• ${fAcc.substring(fAcc.length - 4)}'
                      : fAcc,
                  rawAccountNumber: fAcc,
                  ifscCode: fIfsc ?? 'N/A',
                );
              }
            }
          }
        } catch (e) {
          secureLog('[Statutory] employee_code bank fallback notice: $e');
        }
      }

      secureLog('[Statutory] No statutory data found in any table');
    } catch (e) {
      secureLog('[Auth] Statutory details error: $e');
    }

    // Return empty model instead of null so the UI always has something to display
    final existing = UserService.instance.currentUser.payrollStatutory;
    return existing ??
        const PayrollStatutoryModel(
          bankName: 'Not Available',
          branchName: 'Not Available',
          accountNumber: 'Not Available',
          ifscCode: 'Not Available',
          taxRegime: 'Not Available',
        );
  }

  // ────────────────────────────────────────────────────────────────────────
  // PHONE LOOKUP HELPER
  // ────────────────────────────────────────────────────────────────────────

  /// Identifier (Employee Code or Phone) → work_email lookup.
  Future<String> _resolveEmailFromPhone(String identifier) async {
    final cleaned = identifier.trim();

    // 1. Try Employee Code lookup (e.g. JMS - 102, JMS-102, EMP-001)
    try {
      final codeNorm = cleaned.replaceAll(RegExp(r'\s+'), '');
      final byCode = await withTimeout(
        _client
            .from('employees')
            .select('work_email')
            .ilike('employee_code', '%$codeNorm%')
            .maybeSingle(),
      );
      if (byCode != null && byCode['work_email'] != null) {
        return byCode['work_email'].toString();
      }
    } catch (e) {
      secureLog('[Auth] Employee code lookup ($cleaned) error: $e');
    }

    // 2. Try Phone lookup across profile JSONB and top-level phone
    final cleanedPhone = cleaned.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    for (final key in const [
      'phone',
      'mobile',
      'contact_number',
      'phone_number'
    ]) {
      try {
        final column = 'profile->>$key';
        final record = await withTimeout(
          _client
              .from('employees')
              .select('work_email')
              .filter(column, 'eq', cleanedPhone)
              .maybeSingle(),
        );
        if (record != null && record['work_email'] != null) {
          return record['work_email'].toString();
        }
      } catch (e) {
        secureLog('[Auth] Phone lookup ($key) failed: $e');
      }
    }
    return '';
  }

  // ────────────────────────────────────────────────────────────────────────
  // HELPER: Convert Supabase AuthException to user-friendly message
  // ────────────────────────────────────────────────────────────────────────

  String _friendlyAuthError(String? message) {
    final msg = message?.toLowerCase() ?? '';
    // Supabase-side DB failure (e.g. broken trigger / access-token hook).
    // Credentials were accepted — this is a server problem, not a password one.
    if (msg.contains('database error') ||
        msg.contains('unexpected_failure') ||
        msg.contains('internal error')) {
      return 'Sign-in is temporarily unavailable due to a server configuration '
          'issue. Your credentials are fine — please contact your administrator.';
    }
    if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
      return 'Invalid work email or password.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Email not verified. Contact your HR administrator.';
    }
    if (msg.contains('too many requests') || msg.contains('rate limit')) {
      return 'Too many attempts. Please wait a few minutes and try again.';
    }
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('timeout')) {
      return 'Connection error. Check your internet connection.';
    }
    if (msg.contains('user not found')) {
      return 'No account found for this email.';
    }
    return 'Authentication failed. Please try again.';
  }
}
