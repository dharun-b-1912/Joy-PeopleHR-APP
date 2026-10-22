// leave_application_workflow_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workforce_os/models/employee_models.dart';
import 'package:workforce_os/repositories/supabase/supabase_leave_repository.dart';

void main() {
  group('JOY PeopleHR Leave Application Workflow & Schema Hardening', () {
    test('1. LeaveRequestModel copyWith preserves and updates fields correctly', () {
      final req = LeaveRequestModel(
        id: 'req-temp-01',
        employeeId: '0ce6436c-e9b4-4e0e-9102-93ea238be0df',
        type: LeaveType.casual,
        leaveTypeId: '0f2240de-0ac5-4178-8f1d-20a68114f48d',
        leaveTypeCode: 'CL',
        leaveTypeName: 'Casual Leave',
        startDate: DateTime(2026, 10, 21),
        endDate: DateTime(2026, 10, 21),
        daysCount: 1.0,
        reason: 'Function',
        status: LeaveStatus.pending,
        createdAt: DateTime(2026, 10, 21, 10, 0),
        managerId: 'mgr-01',
        managerName: 'Reporting Manager',
      );

      final updated = req.copyWith(
        id: 'persisted-uuid-12345',
        status: LeaveStatus.approved,
      );

      expect(updated.id, 'persisted-uuid-12345');
      expect(updated.status, LeaveStatus.approved);
      expect(updated.employeeId, req.employeeId);
      expect(updated.leaveTypeId, req.leaveTypeId);
      expect(updated.daysCount, 1.0);
      expect(updated.reason, 'Function');
    });

    test('2. Structured PostgREST Error Formatter transforms error codes into safe, actionable messages', () {
      // 23502: missing required value (e.g. organization_id null)
      const err23502 = PostgrestException(
        message: 'null value in column "organization_id" of relation "leave_requests" violates not-null constraint',
        code: '23502',
      );
      final msg23502 = SupabaseLeaveRepository.formatPostgrestErrorForTesting(err23502);
      expect(msg23502, contains('A required field was missing'));
      expect(msg23502, contains('Ref: LV-'));
      expect(msg23502, isNot(contains('violates not-null')));

      // 42501: permission or RLS violation
      const err42501 = PostgrestException(
        message: 'new row violates row-level security policy for table "leave_requests"',
        code: '42501',
      );
      final msg42501 = SupabaseLeaveRepository.formatPostgrestErrorForTesting(err42501);
      expect(msg42501, contains('Permission denied'));
      expect(msg42501, contains('Ref: LV-'));

      // PGRST204: column mismatch / missing column in schema cache
      const errPgrst204 = PostgrestException(
        message: "Could not find the 'approver_id' column of 'leave_requests' in the schema cache",
        code: 'PGRST204',
      );
      final msgPgrst204 = SupabaseLeaveRepository.formatPostgrestErrorForTesting(errPgrst204);
      expect(msgPgrst204, contains('Database column configuration mismatch'));
      expect(msgPgrst204, contains('Ref: LV-'));

      // 23505: unique constraint / duplicate
      const err23505 = PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
      final msg23505 = SupabaseLeaveRepository.formatPostgrestErrorForTesting(err23505);
      expect(msg23505, contains('already exists'));
    });

    test('3. Leave Type code and name parsing resolves proper enums', () {
      expect(SupabaseLeaveRepository.parseLeaveType('Casual Leave (CL)'), LeaveType.casual);
      expect(SupabaseLeaveRepository.parseLeaveType('Sick Leave (SL)'), LeaveType.sick);
      expect(SupabaseLeaveRepository.parseLeaveType('Earned Leave (EL)'), LeaveType.earned);
      expect(SupabaseLeaveRepository.parseLeaveType('Annual Privilege Leave'), LeaveType.earned);
      expect(SupabaseLeaveRepository.parseLeaveType('Medical Recovery Leave'), LeaveType.sick);
    });

    test('4. Half-day calculation and session representation', () {
      final halfDayReq = LeaveRequestModel(
        id: 'hd-01',
        employeeId: 'emp-uuid',
        type: LeaveType.casual,
        startDate: DateTime(2026, 10, 21),
        endDate: DateTime(2026, 10, 21),
        daysCount: 0.5,
        isHalfDay: true,
        halfDaySession: 'First Half',
        reason: 'Doctor appointment',
        status: LeaveStatus.pending,
        createdAt: DateTime.now(),
      );

      expect(halfDayReq.isHalfDay, isTrue);
      expect(halfDayReq.daysCount, 0.5);
      expect(halfDayReq.halfDaySession, 'First Half');
    });

    test('5. Multi-day request date formatting and payload validation', () {
      final multiReq = LeaveRequestModel(
        id: 'multi-01',
        employeeId: 'emp-uuid-1234',
        type: LeaveType.earned,
        startDate: DateTime(2026, 10, 21),
        endDate: DateTime(2026, 10, 25),
        daysCount: 5.0,
        isHalfDay: false,
        reason: 'Annual family vacation',
        status: LeaveStatus.pending,
        createdAt: DateTime.now(),
      );

      final startIso = multiReq.startDate.toIso8601String().split('T')[0];
      final endIso = multiReq.endDate.toIso8601String().split('T')[0];

      expect(startIso, '2026-10-21');
      expect(endIso, '2026-10-25');
      expect(multiReq.daysCount, 5.0);
    });
  });
}
