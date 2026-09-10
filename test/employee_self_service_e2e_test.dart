// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workforce_os/core/services/employee_identity_resolver.dart';

void main() {
  const supabaseUrl = 'https://ysiajemrqakfngasehhi.supabase.co';
  const supabaseAnonKey = 'sb_publishable_i_pb_iFcxX0BEJFok_XfZA_gZF3W8mj';

  const empAEmail = 'e2e.employee.1788509696336@joypeoplehr.com';
  const empAPassword = 'JoyEmployee@2026';
  const expectedEmpAId = '7ea078b3-0a7e-47ce-82b7-ea9d33ab6da5';

  const empBEmail = 'e2e.employee.b.1788510620285@joypeoplehr.com';
  const empBPassword = 'JoyEmployeeB@2026';
  const expectedEmpBId = '1d9e2f8b-70f7-4704-a16f-200b251f0839';

  group('Flutter Real Client Self-Service & Isolation Validation', () {
    late SupabaseClient client;

    setUp(() {
      client = SupabaseClient(supabaseUrl, supabaseAnonKey);
    });

    test('Employee A: Authentication, Identity Resolution & Self-Service Data', () async {
      print('\n[FLUTTER] 1. Authenticating Employee A...');
      final authRes = await client.auth.signInWithPassword(
        email: empAEmail,
        password: empAPassword,
      );
      expect(authRes.user, isNotNull);
      final authUid = authRes.user!.id;
      print('[FLUTTER] Employee A Auth UID: $authUid');

      // Identity Resolver
      final resolution = await EmployeeIdentityResolver.resolve(
        client: client,
        authUid: authUid,
        authEmail: empAEmail,
      );
      expect(resolution.success, isTrue);
      expect(resolution.employeeUuid, equals(expectedEmpAId));
      print('[FLUTTER] Employee A Identity Resolved: empId=${resolution.employeeUuid}, name=${resolution.userModel?.name}');

      // Attendance
      final attRows = await client.from('attendance_daily').select('*').eq('employee_id', expectedEmpAId);
      expect(attRows.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee A Attendance Daily: ${attRows.length} record(s)');

      // Punches
      final punchRows = await client.from('attendance_punches').select('*').eq('employee_id', expectedEmpAId);
      expect(punchRows.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee A Punches: ${punchRows.length} record(s)');

      // Leave Balances
      final leaveBalances = await client.from('leave_balances').select('*').eq('employee_id', expectedEmpAId);
      expect(leaveBalances.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee A Leave Balances: ${leaveBalances.length} record(s)');

      // Leave Requests
      final leaveRequests = await client.from('leave_requests').select('*').eq('employee_id', expectedEmpAId);
      expect(leaveRequests.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee A Leave Requests: ${leaveRequests.length} record(s)');

      // Employee Requests
      final empRequests = await client.from('employee_requests').select('*').eq('employee_id', expectedEmpAId);
      expect(empRequests.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee A Employee Requests: ${empRequests.length} record(s)');

      // Payslips
      final payslips = await client.from('payslips').select('*').eq('employee_id', expectedEmpAId);
      expect(payslips.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee A Payslips: ${payslips.length} record(s)');

      // Documents
      final documents = await client.from('employee_documents').select('*').eq('employee_id', expectedEmpAId);
      expect(documents.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee A Documents: ${documents.length} record(s)');

      // Cross-Isolation Verification: Employee A cannot read Employee B punches or payslips
      final bPunches = await client.from('attendance_punches').select('*').eq('employee_id', expectedEmpBId);
      expect(bPunches.length, equals(0));
      print('[FLUTTER] Employee A -> Employee B Punches Query: 0 rows (ISOLATED)');

      final bPayslips = await client.from('payslips').select('*').eq('employee_id', expectedEmpBId);
      expect(bPayslips.length, equals(0));
      print('[FLUTTER] Employee A -> Employee B Payslips Query: 0 rows (ISOLATED)');
    });

    test('Employee B: Authentication, Identity Resolution & Self-Service Data', () async {
      print('\n[FLUTTER] 2. Authenticating Employee B...');
      final authRes = await client.auth.signInWithPassword(
        email: empBEmail,
        password: empBPassword,
      );
      expect(authRes.user, isNotNull);
      final authUid = authRes.user!.id;
      print('[FLUTTER] Employee B Auth UID: $authUid');

      // Identity Resolver
      final resolution = await EmployeeIdentityResolver.resolve(
        client: client,
        authUid: authUid,
        authEmail: empBEmail,
      );
      expect(resolution.success, isTrue);
      expect(resolution.employeeUuid, equals(expectedEmpBId));
      print('[FLUTTER] Employee B Identity Resolved: empId=${resolution.employeeUuid}, name=${resolution.userModel?.name}');

      // Attendance
      final attRows = await client.from('attendance_daily').select('*').eq('employee_id', expectedEmpBId);
      expect(attRows.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee B Attendance Daily: ${attRows.length} record(s)');

      // Punches
      final punchRows = await client.from('attendance_punches').select('*').eq('employee_id', expectedEmpBId);
      expect(punchRows.length, greaterThanOrEqualTo(1));
      print('[FLUTTER] Employee B Punches: ${punchRows.length} record(s)');

      // Cross-Isolation Verification: Employee B cannot read Employee A punches or payslips
      final aPunches = await client.from('attendance_punches').select('*').eq('employee_id', expectedEmpAId);
      expect(aPunches.length, equals(0));
      print('[FLUTTER] Employee B -> Employee A Punches Query: 0 rows (ISOLATED)');

      final aPayslips = await client.from('payslips').select('*').eq('employee_id', expectedEmpAId);
      expect(aPayslips.length, equals(0));
      print('[FLUTTER] Employee B -> Employee A Payslips Query: 0 rows (ISOLATED)');
    });
  });
}
