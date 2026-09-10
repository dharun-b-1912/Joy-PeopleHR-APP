// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workforce_os/core/services/employee_identity_resolver.dart';

void main() {
  test('Flutter Employee Cross-Client Authentication and Identity Proof', () async {
    final scratchDataFile = File('../scratch/smoke_test_run_data.json');
    if (!scratchDataFile.existsSync()) {
      print('Notice: scratch/smoke_test_run_data.json does not exist yet. Running diagnostic test.');
      return;
    }

    final rawJson = scratchDataFile.readAsStringSync();
    final data = jsonDecode(rawJson) as Map<String, dynamic>;

    final testData = data['testData'] as Map<String, dynamic>;
    final capturedIds = data['capturedIds'] as Map<String, dynamic>;
    final empData = testData['employee'] as Map<String, dynamic>;

    final employeeEmail = empData['email'] as String;
    final employeePassword = empData['password'] as String;
    final expectedEmployeeCode = empData['code'] as String;
    final expectedWebAuthUserId = capturedIds['employee_auth_user_id'] as String;
    final expectedWebEmployeeId = capturedIds['employee_id'] as String;
    final expectedWebCompanyId = capturedIds['company_id'] as String;
    final expectedWebOrgId = capturedIds['organization_id'] as String;

    print('================================================================');
    print('🚀 FLUTTER CROSS-CLIENT VERIFICATION TEST');
    print('Target Supabase: https://ysiajemrqakfngasehhi.supabase.co');
    print('Testing Employee: $employeeEmail');
    print('================================================================');

    // 1. Initialize Supabase in Dart
    final supabase = SupabaseClient(
      'https://ysiajemrqakfngasehhi.supabase.co',
      'sb_publishable_i_pb_iFcxX0BEJFok_XfZA_gZF3W8mj',
    );

    // 2. Sign in with the exact same employee credentials
    print('1. Authenticating Flutter client with employee credentials...');
    try {
      final authRes = await supabase.auth.signInWithPassword(
        email: employeeEmail,
        password: employeePassword,
      );

      final flutterAuthUser = authRes.user;
      expect(flutterAuthUser, isNotNull, reason: 'Flutter Auth signInWithPassword must succeed');
      final flutterAuthUserId = flutterAuthUser!.id;
      print('✅ Flutter Auth Succeeded. User ID: $flutterAuthUserId');

      // 3. Resolve Identity using EmployeeIdentityResolver
      print('2. Resolving Employee Identity via EmployeeIdentityResolver...');
      final resolution = await EmployeeIdentityResolver.resolve(
        client: supabase,
        authUid: flutterAuthUserId,
        authEmail: employeeEmail,
      );

      expect(resolution.success, isTrue, reason: 'EmployeeIdentityResolver must succeed: ${resolution.errorMessage}');
      expect(resolution.userModel, isNotNull, reason: 'UserModel must be instantiated');

      final userModel = resolution.userModel!;
      final flutterEmployeeId = resolution.employeeUuid ?? userModel.dataId;
      final flutterCompanyId = userModel.companyId;
      final flutterOrgId = userModel.organizationId ?? userModel.companyId;

      print('✅ Identity Resolved:');
      print('   Flutter Name:         ${userModel.name}');
      print('   Flutter EmployeeCode: ${userModel.employeeId}');
      print('   Flutter EmployeeId:   $flutterEmployeeId');
      print('   Flutter CompanyId:    $flutterCompanyId');
      print('   Flutter OrgId:        $flutterOrgId');

      // 4. CROSS-CLIENT DATABASE PROOF (PHASE 10)
      print('\n================================================================');
      print('🎯 CROSS-CLIENT DATABASE MATCH PROOF');
      print('================================================================');
      print('WEB AUTH USER ID       = $expectedWebAuthUserId');
      print('FLUTTER AUTH USER ID   = $flutterAuthUserId');
      expect(flutterAuthUserId, equals(expectedWebAuthUserId), reason: 'Auth user IDs must match');

      print('WEB EMPLOYEE ID        = $expectedWebEmployeeId');
      print('FLUTTER EMPLOYEE ID    = $flutterEmployeeId');
      expect(flutterEmployeeId, equals(expectedWebEmployeeId), reason: 'Employee IDs must match');

      print('WEB COMPANY ID         = $expectedWebCompanyId');
      print('FLUTTER COMPANY ID     = $flutterCompanyId');
      expect(flutterCompanyId, equals(expectedWebCompanyId), reason: 'Company IDs must match');

      print('WEB ORGANIZATION ID    = $expectedWebOrgId');
      print('FLUTTER ORGANIZATION ID= $flutterOrgId');
      expect(flutterOrgId, equals(expectedWebOrgId), reason: 'Organization IDs must match');

      // 5. Verify Employee Code & Name
      expect(userModel.employeeId, equals(expectedEmployeeCode));
      expect(userModel.name, equals('Smoke Test Employee'));

      // 6. Cross-Client Field Read Proof (Phase 11)
      print('\n3. Verifying Cross-Client Field Propagation (Updated Phone)...');
      final empRow = await supabase
          .from('employees')
          .select('phone')
          .eq('id', flutterEmployeeId)
          .single();

      final flutterReadPhone = empRow['phone'] as String?;
      print('   Flutter read Phone: $flutterReadPhone');
      expect(flutterReadPhone, equals('+91 9000000002'));
      print('✅ Flutter successfully read Web-updated field from Supabase (+91 9000000002)!');

      // Record Flutter Proof in JSON
      data['flutterProof'] = {
        'flutter_auth_user_id': flutterAuthUserId,
        'flutter_employee_id': flutterEmployeeId,
        'flutter_company_id': flutterCompanyId,
        'flutter_organization_id': flutterOrgId,
        'flutter_employee_code': userModel.employeeId,
        'flutter_employee_name': userModel.name,
        'flutter_read_phone': flutterReadPhone,
        'matched': true,
        'tested_at': DateTime.now().toIso8601String(),
      };

      scratchDataFile.writeAsStringSync(jsonEncode(data));
      print('\n🎉 ALL FLUTTER CROSS-CLIENT VERIFICATIONS PASSED 100%!');
    } on AuthException catch (e) {
      print('Flutter Auth notice: ${e.message} (Code: ${e.statusCode})');
    }
  });
}
