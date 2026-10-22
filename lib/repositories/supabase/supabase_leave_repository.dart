// supabase_leave_repository.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/services/push_sender_service.dart';
import '../../core/services/realtime_outbox_service.dart';
import '../../core/services/user_service.dart';
import '../../core/theme/klarna_tokens.dart';
import '../../core/utils/query_timeout.dart';
import '../../core/utils/secure_log.dart';
import '../../core/utils/validators.dart';
import '../../models/employee_models.dart';
import '../interfaces/employee_repository.dart';

/// WorkForceOS — Production Supabase Leave Repository
/// Single Source of Truth for Leave Types, Entitlements Ledger, Requests, and Approvals
class SupabaseLeaveRepository implements ILeaveRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<LeaveTypeConfigModel>> getLeaveTypes(
      String organizationId) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];
      final user = UserService.instance.currentUser;
      final orgId = user.companyId.isNotEmpty ? user.companyId : organizationId;

      final data = await withTimeout(
        _client
            .from('leave_types')
            .select()
            .eq('is_active', true)
            .order('name', ascending: true),
      );

      if (data.isEmpty) {
        secureLog(
            '[Leave] No active leave types configured in DB for $orgId — using standard catalog');
        return [
          LeaveTypeConfigModel(
            id: 'lt-cl',
            organizationId: orgId,
            code: 'CL',
            name: 'Casual Leave',
            description: 'Paid casual leave for personal needs',
            category: 'Paid',
            isPaid: true,
            isActive: true,
            allowHalfDay: true,
          ),
          LeaveTypeConfigModel(
            id: 'lt-sl',
            organizationId: orgId,
            code: 'SL',
            name: 'Sick Leave',
            description: 'Medical and sick recovery leave',
            category: 'Paid',
            isPaid: true,
            isActive: true,
            allowHalfDay: true,
          ),
          LeaveTypeConfigModel(
            id: 'lt-el',
            organizationId: orgId,
            code: 'EL',
            name: 'Earned Leave',
            description: 'Annual privilege vacation leave',
            category: 'Paid',
            isPaid: true,
            isActive: true,
            allowHalfDay: false,
          ),
          LeaveTypeConfigModel(
            id: 'lt-co',
            organizationId: orgId,
            code: 'CO',
            name: 'Comp-Off',
            description: 'Compensatory off for holiday duty',
            category: 'Compensatory',
            isPaid: true,
            isActive: true,
            allowHalfDay: true,
          ),
        ];
      }

      return data
          .map<LeaveTypeConfigModel>((m) => LeaveTypeConfigModel.fromJson(m))
          .toList();
    } catch (e) {
      secureLog('[Leave] getLeaveTypes error: $e');
      return [];
    }
  }

  @override
  Future<LeaveBalanceModel> getLeaveBalances(String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) {
        return LeaveBalanceModel.empty();
      }

      final user = UserService.instance.currentUser;
      final candidateIds = <String>{
        employeeId,
        user.dataId,
        if (user.employeeUuid?.isNotEmpty == true) user.employeeUuid!,
      }.where((id) => Validators.isValidUuid(id)).toList();

      if (candidateIds.isEmpty) {
        return LeaveBalanceModel.empty();
      }

      final targetId = candidateIds.first;
      final orFilter = candidateIds.map((id) => 'employee_id.eq.$id').join(',');

      // 1. Fetch balances from canonical leave_balances
      final data = await withTimeout(
        _client
            .from('leave_balances')
            .select('*, leave_types(id, name, code, is_paid, annual_quota)')
            .or(orFilter),
      );

      // 2. Fetch approved leave requests to accurately tally used days
      List<dynamic> approvedRequestsData = [];
      try {
        approvedRequestsData = await withTimeout(
          _client
              .from('leave_requests')
              .select('*, leave_types(id, name, code)')
              .or(orFilter)
              .eq('status', 'APPROVED'),
        );
      } catch (e) {
        secureLog('[Leave] approved requests fetch notice: $e');
      }

      final approvedDaysByType = <String, double>{};
      for (final req in approvedRequestsData) {
        final reqTypeMap = req['leave_types'] is Map ? req['leave_types'] as Map : null;
        final code = (reqTypeMap?['code'] ?? req['leave_type_code'] ?? '').toString().toUpperCase();
        final name = (reqTypeMap?['name'] ?? req['leave_type_name'] ?? '').toString().toLowerCase();
        final days = ((req['total_days'] ??
                    req['working_days'] ??
                    req['leave_days_deducted'] ??
                    req['days_count'] ??
                    req['total_calendar_days']) as num?)
                ?.toDouble() ??
            1.0;

        String key = code;
        if (name.contains('casual') || key == 'CL') {
          key = 'CL';
        } else if (name.contains('sick') ||
            name.contains('medical') ||
            key == 'SL') {
          key = 'SL';
        } else if (name.contains('earned') ||
            name.contains('privilege') ||
            name.contains('annual') ||
            key == 'EL' ||
            key == 'PL') {
          key = 'EL';
        } else if (name.contains('maternity') || key == 'ML') {
          key = 'ML';
        } else if (key.isEmpty) {
          key = name;
        }

        approvedDaysByType[key] = (approvedDaysByType[key] ?? 0.0) + days;
      }

      final currentMonth = DateTime.now().month; // 1-12 (e.g. 8 for August)

      if (data.isEmpty) {
        final clUsed = approvedDaysByType['CL'] ?? 0.0;
        final slUsed = approvedDaysByType['SL'] ?? 0.0;
        final elUsed = approvedDaysByType['EL'] ?? 0.0;

        const clQuota = 12.0;
        const slQuota = 10.0;
        const elQuota = 15.0;

        secureLog(
            '[Leave] Baseline 12-month auto-calculation for $targetId (Month $currentMonth): CL (12 total, 1.0/mo, used=$clUsed), SL (10 total, 0.83/mo, used=$slUsed), EL (15 total, 1.25/mo, used=$elUsed)');
        return LeaveBalanceModel(
          items: [
            DynamicLeaveBalanceItem(
              leaveTypeId: 'lt-cl',
              leaveTypeCode: 'CL',
              leaveTypeName: 'Casual Leave',
              available: (clQuota - clUsed).clamp(0.0, 100.0),
              used: clUsed,
              granted: clQuota,
              opening: clQuota,
              annualQuota: clQuota,
              monthlyAccrualRate: 1.0,
              accruedTillDate: (1.0 * currentMonth).clamp(0.0, clQuota),
              accrualFrequency: 'Monthly',
              colorBg: AppColors.mintBg,
              colorFg: AppColors.mintFg,
            ),
            DynamicLeaveBalanceItem(
              leaveTypeId: 'lt-sl',
              leaveTypeCode: 'SL',
              leaveTypeName: 'Sick Leave',
              available: (slQuota - slUsed).clamp(0.0, 100.0),
              used: slUsed,
              granted: slQuota,
              opening: slQuota,
              annualQuota: slQuota,
              monthlyAccrualRate: 0.83,
              accruedTillDate:
                  ((slQuota / 12) * currentMonth).clamp(0.0, slQuota),
              accrualFrequency: 'Monthly',
              colorBg: AppColors.lavenderBg,
              colorFg: AppColors.lavenderFg,
            ),
            DynamicLeaveBalanceItem(
              leaveTypeId: 'lt-el',
              leaveTypeCode: 'EL',
              leaveTypeName: 'Earned Leave',
              available: (elQuota - elUsed).clamp(0.0, 100.0),
              used: elUsed,
              granted: elQuota,
              opening: elQuota,
              annualQuota: elQuota,
              monthlyAccrualRate: 1.25,
              accruedTillDate:
                  ((elQuota / 12) * currentMonth).clamp(0.0, elQuota),
              accrualFrequency: 'Monthly',
              colorBg: AppColors.skyBg,
              colorFg: AppColors.skyFg,
            ),
          ],
          casualAvailable: (clQuota - clUsed).clamp(0.0, 100.0),
          casualUsed: clUsed,
          sickAvailable: (slQuota - slUsed).clamp(0.0, 100.0),
          sickUsed: slUsed,
          earnedAvailable: (elQuota - elUsed).clamp(0.0, 100.0),
          earnedUsed: elUsed,
        );
      }

      final items = <DynamicLeaveBalanceItem>[];
      var casualAvail = 0.0, casualUsed = 0.0;
      var sickAvail = 0.0, sickUsed = 0.0;
      var earnedAvail = 0.0, earnedUsed = 0.0;

      for (int i = 0; i < data.length; i++) {
        final row = data[i];
        final typeObj =
            row['leave_types'] is Map ? row['leave_types'] as Map : null;
        final typeId = (typeObj?['id'] ?? row['leave_type_id'])?.toString();
        final code =
            (typeObj?['code'] ?? row['leave_type_code'] ?? 'LT-${i + 1}')
                .toString();
        final name =
            (typeObj?['name'] ?? row['leave_type_name'] ?? 'Leave').toString();
        final lowerName = '$name $code'.toLowerCase();

        final key = _isCasual(lowerName)
            ? 'CL'
            : _isSick(lowerName)
                ? 'SL'
                : _isEarned(lowerName)
                    ? 'EL'
                    : code.toUpperCase();
        final approvedForThisType = approvedDaysByType[key] ??
            approvedDaysByType[code.toUpperCase()] ??
            0.0;

        final rawUsed = ((row['consumed'] ?? row['used']) as num?)?.toDouble() ?? 0.0;
        final used = rawUsed > 0
            ? rawUsed
            : (approvedRequestsData.isNotEmpty ? approvedForThisType : rawUsed);
        final annualQuota = ((typeObj?['annual_quota'] ??
                    row['annual_quota'] ??
                    row['granted'] ??
                    row['opening_balance']) as num?)
                ?.toDouble() ??
            12.0;
        final opening = ((row['carried_forward'] ?? row['opening_balance']) as num?)?.toDouble() ??
            annualQuota;
        final accrued = (row['accrued'] as num?)?.toDouble() ?? 0.0;
        final monthlyRate = double.parse(
            (annualQuota > 0 ? annualQuota / 12 : 0.0).toStringAsFixed(2));
        final accruedTillDate = (accrued > 0 ? accrued : (monthlyRate * currentMonth))
            .clamp(0.0, annualQuota > 0 ? annualQuota : 999.0);
        final rawBalance = ((row['closing_balance'] ?? row['balance']) as num?)?.toDouble();
        final avail = ((rawBalance != null && rawBalance > 0)
                ? rawBalance
                : (annualQuota - used))
            .clamp(0.0, 999.0);

        // Assign aesthetic badge colors based on leave type code/name
        final colorPair = _resolveBadgeColors(name, code, i);

        items.add(DynamicLeaveBalanceItem(
          leaveTypeId: typeId,
          leaveTypeCode: code,
          leaveTypeName: name,
          available: avail,
          used: used,
          granted: annualQuota,
          opening: opening,
          annualQuota: annualQuota,
          monthlyAccrualRate: monthlyRate,
          accruedTillDate: accruedTillDate,
          accrualFrequency: 'Monthly',
          colorBg: colorPair.$1,
          colorFg: colorPair.$2,
        ));

        if (_isSick(lowerName)) {
          sickAvail += avail;
          sickUsed += used;
        } else if (_isEarned(lowerName)) {
          earnedAvail += avail;
          earnedUsed += used;
        } else if (_isCasual(lowerName)) {
          casualAvail += avail;
          casualUsed += used;
        }
      }

      secureLog(
          '[Leave] Loaded ${items.length} dynamic balances from leave_balances for $targetId');
      return LeaveBalanceModel(
        items: items,
        casualAvailable: casualAvail,
        casualUsed: casualUsed,
        sickAvailable: sickAvail,
        sickUsed: sickUsed,
        earnedAvailable: earnedAvail,
        earnedUsed: earnedUsed,
      );
    } catch (e) {
      secureLog('[Leave] getLeaveBalances error: $e');
      return LeaveBalanceModel.empty();
    }
  }

  // ── Leave Requests ─────────────────────────────────────────────────────────

  @override
  Future<List<LeaveRequestModel>> getLeaveRequests(String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) {
        return [];
      }

      final user = UserService.instance.currentUser;
      final targetId = (user.employeeUuid?.isNotEmpty == true)
          ? user.employeeUuid!
          : (user.dataId.isNotEmpty ? user.dataId : employeeId);

      final candidateIds = <String>{
        targetId,
        employeeId,
        user.dataId,
        if (user.employeeUuid?.isNotEmpty == true) user.employeeUuid!,
      }.where((id) => Validators.isValidUuid(id)).toList();

      if (candidateIds.isEmpty) {
        return [];
      }

      final orFilter = candidateIds.map((id) => 'employee_id.eq.$id').join(',');

      final data = await withTimeout(
        _client
            .from('leave_requests')
            .select('*, leave_types(id, name, code, is_paid)')
            .or(orFilter)
            .order('created_at', ascending: false),
      );

      if (data.isEmpty) {
        secureLog('[Leave] No leave requests found in DB for $targetId');
        return [];
      }

      return data.map<LeaveRequestModel>((map) {
        final ltMap = map['leave_types'] is Map ? map['leave_types'] as Map : null;
        final typeName = (ltMap?['name'] ?? map['leave_type_name'] ?? map['leave_type_code'] ?? 'Casual Leave').toString();
        final typeCode = (ltMap?['code'] ?? map['leave_type_code'] ?? 'CL').toString();
        final startRaw = (map['start_date'] ?? map['from_date'] ?? '').toString();
        final endRaw = (map['end_date'] ?? map['to_date'] ?? startRaw).toString();
        return LeaveRequestModel(
          id: map['id'].toString(),
          employeeId: map['employee_id']?.toString() ?? targetId,
          type: parseLeaveType('$typeName $typeCode'),
          leaveTypeId: (ltMap?['id'] ?? map['leave_type_id'])?.toString(),
          leaveTypeCode: typeCode,
          leaveTypeName: typeName,
          startDate:
              DateTime.tryParse(startRaw) ?? DateTime.now(),
          endDate:
              DateTime.tryParse(endRaw) ?? DateTime.now(),
          daysCount: ((map['total_days'] ??
                      map['leave_days_deducted'] ??
                      map['working_days']) as num?)
                  ?.toDouble() ??
              1.0,
          reason: map['reason']?.toString() ?? '',
          status: _parseStatus(map['status']),
          createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
              DateTime.tryParse(map['submitted_at']?.toString() ?? '') ??
              DateTime.now(),
          approverId: (map['approved_by'] ?? map['manager_id'])?.toString(),
          approverName: map['manager_name']?.toString(),
          managerId: (map['approved_by'] ?? map['manager_id'])?.toString(),
          managerName: map['manager_name']?.toString(),
          currentApproverName: map['current_approver_name']?.toString(),
          rejectionReason: map['rejection_reason']?.toString() ??
              map['comments']?.toString(),
          isHalfDay: map['is_half_day'] as bool? ?? false,
          halfDaySession: map['half_day_session']?.toString(),
        );
      }).toList();
    } catch (e) {
      secureLog('[Leave] getLeaveRequests error: $e');
      return [];
    }
  }

  @override
  Future<LeaveRequestModel> applyLeave(LeaveRequestModel request) async {
    final user = UserService.instance.currentUser;
    final typeName = request.leaveTypeName ?? _leaveTypeName(request.type);
    String typeCode = request.leaveTypeCode ?? _leaveTypeCode(request.type);
    String typeId = request.leaveTypeId ?? '';

    // 1. Authoritative Leave Type Resolution
    if (typeId.isEmpty || !Validators.isValidUuid(typeId)) {
      try {
        final types =
            await _client.from('leave_types').select('id, code, name');
        for (final t in types) {
          final code = t['code']?.toString().toUpperCase() ?? '';
          final name = t['name']?.toString().toLowerCase() ?? '';
          if (code == typeCode.toUpperCase() ||
              name == typeName.toLowerCase() ||
              _matchesType('$name $code', request.type)) {
            typeId = t['id']?.toString() ?? '';
            typeCode = t['code']?.toString() ?? typeCode;
            break;
          }
        }
      } catch (e) {
        secureLog('[Leave] leave_types lookup notice: $e');
      }
    }

    if (typeId.isEmpty || !Validators.isValidUuid(typeId)) {
      switch (request.type) {
        case LeaveType.sick:
          typeId = '0f2240de-0ac5-4178-8f1d-20a68114f48e';
          break;
        case LeaveType.earned:
          typeId = '0f2240de-0ac5-4178-8f1d-20a68114f48f';
          break;
        case LeaveType.casual:
        default:
          typeId = '0f2240de-0ac5-4178-8f1d-20a68114f48d';
          break;
      }
    }

    // 2. Authoritative Employee & Organization Identity Resolution
    final targetEmployeeId = user.resolvedEmployeeId;
    if (targetEmployeeId.isEmpty) {
      throw Exception('Could not resolve your employee identity. Please log out and sign in again.');
    }

    String effectiveOrgId = (user.organizationId?.isNotEmpty == true && Validators.isValidUuid(user.organizationId!))
        ? user.organizationId!
        : (Validators.isValidUuid(user.tenantId) ? user.tenantId : '');

    if (effectiveOrgId.isEmpty && Validators.isValidUuid(targetEmployeeId)) {
      try {
        final empData = await _client
            .from('employees')
            .select('organization_id')
            .eq('id', targetEmployeeId)
            .maybeSingle();
        if (empData != null && empData['organization_id'] != null) {
          effectiveOrgId = empData['organization_id'].toString();
        }
      } catch (e) {
        secureLog('[Leave] Error resolving employee organization_id: $e');
      }
    }

    if (effectiveOrgId.isEmpty) {
      effectiveOrgId = '0c621892-e938-4707-9957-13534ea32c19'; // Default Joy Corporate Solutions Org ID
    }

    final managerId = request.managerId ?? user.reportsToId;
    final startDateStr = request.startDate.toIso8601String().split('T')[0];
    final endDateStr = request.endDate.toIso8601String().split('T')[0];
    final daysCountVal = request.daysCount > 0 ? request.daysCount : (request.isHalfDay ? 0.5 : 1.0);

    // 3. Overlapping Leave Request / Idempotency Guard
    try {
      final existing = await _client
          .from('leave_requests')
          .select('id, status, start_date, end_date')
          .eq('employee_id', targetEmployeeId)
          .inFilter('status', ['PENDING', 'APPROVED'])
          .lte('start_date', endDateStr)
          .gte('end_date', startDateStr)
          .maybeSingle();

      if (existing != null) {
        final existingStatus = existing['status'] ?? 'PENDING';
        throw Exception(
            'You already have an active $existingStatus leave request overlapping with this date range ($startDateStr to $endDateStr).');
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('overlapping with')) {
        rethrow;
      }
    }

    // 4. Schema-Compliant Payload matching PostgreSQL table public.leave_requests
    final payload = <String, dynamic>{
      'organization_id': effectiveOrgId,
      'employee_id': targetEmployeeId,
      'leave_type_id': typeId,
      'start_date': startDateStr,
      'end_date': endDateStr,
      'total_days': daysCountVal,
      'is_half_day': request.isHalfDay,
      'reason': request.reason.trim(),
      'status': 'PENDING',
    };

    String generatedRequestId = request.id;
    try {
      final insertedRow =
          await _client.from('leave_requests').insert(payload).select().single();
      generatedRequestId = insertedRow['id']?.toString() ?? request.id;
      secureLog(
          '[Leave] Leave request successfully inserted into Supabase -> ID: $generatedRequestId, type: $typeName');
    } on PostgrestException catch (e) {
      final formattedError = _formatPostgrestError(e);
      throw Exception(formattedError);
    } catch (e) {
      secureLog('[Leave] Direct insert failure: $e');
      rethrow;
    }

    // 5. Outbox notification sync via centralized service (non-blocking)
    try {
      await RealtimeOutboxService.insertEvent(
        entityType: 'LEAVE_REQUEST',
        eventType: 'CREATED',
        entityId: generatedRequestId,
        tenantId: effectiveOrgId,
        actorId: targetEmployeeId,
        payload: {
          ...payload,
          'id': generatedRequestId,
          'leave_type_name': typeName,
          'leave_type_code': typeCode,
          if (managerId != null && managerId.isNotEmpty) 'manager_id': managerId,
        },
      );
    } catch (e) {
      secureLog('[Leave] Outbox notification notice: $e');
    }

    // 6. Send push notification to the reporting manager/HR (non-blocking)
    if (managerId != null && managerId.isNotEmpty) {
      try {
        final dateRange =
            '${request.startDate.day}/${request.startDate.month} - ${request.endDate.day}/${request.endDate.month}';
        await PushSenderService.instance.sendToEmployee(
          employeeId: managerId,
          title: 'New Leave Request',
          body:
              '${user.name} has requested $typeName ($dateRange) — $daysCountVal day(s)',
          route: 'leaves',
          data: {
            'leave_id': generatedRequestId,
            'employee_name': user.name,
          },
        );
      } catch (e) {
        secureLog('[Leave] Push to manager notice: $e');
      }
    }

    return request.copyWith(id: generatedRequestId);
  }

  @visibleForTesting
  static String formatPostgrestErrorForTesting(PostgrestException e) =>
      _formatPostgrestError(e);

  static String _formatPostgrestError(PostgrestException e) {
    final correlationId = 'LV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    secureLog(
        '[Leave][DB_ERROR][$correlationId] code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');

    switch (e.code) {
      case '23502':
        return 'A required field was missing. Please verify your leave details and try again. (Ref: $correlationId)';
      case '23503':
        return 'Invalid employee or leave type configuration. (Ref: $correlationId)';
      case '23505':
        return 'A leave request already exists for this date range. (Ref: $correlationId)';
      case '23514':
        return 'The requested leave dates or duration are invalid. (Ref: $correlationId)';
      case '42501':
        return 'Permission denied: You can only submit leave for your authorized employee profile. (Ref: $correlationId)';
      case '22P02':
        return 'Invalid data format submitted. Please check your selections and try again. (Ref: $correlationId)';
      case 'PGRST204':
        return 'Database column configuration mismatch. (Ref: $correlationId)';
      default:
        if (e.message.isNotEmpty &&
            !e.message.toLowerCase().contains('violates') &&
            !e.message.toLowerCase().contains('syntax')) {
          return '${e.message} (Ref: $correlationId)';
        }
        return 'Your leave request could not be submitted. Please try again. Reference: $correlationId';
    }
  }

  @override
  Future<void> cancelLeave(String requestId, {String? reason}) async {
    final user = UserService.instance.currentUser;
    final orgId = user.tenantId;

    try {
      // 1. Check existing leave request before deletion
      final row = await _client
          .from('leave_requests')
          .select('*')
          .eq('id', requestId)
          .maybeSingle();

      if (row != null) {
        final status = (row['status']?.toString() ?? '').toUpperCase();
        final totalDays = (row['total_days'] as num?)?.toDouble() ?? 0.0;
        final empId = row['employee_id']?.toString() ?? user.resolvedEmployeeId;
        final leaveTypeId = row['leave_type_id']?.toString();

        // 2. If already approved, reverse the consumed balance via ledger entry
        if (status == 'APPROVED' && totalDays > 0 && leaveTypeId != null) {
          try {
            await _client.from('leave_ledger_entries').insert({
              'id': 'led-rev-${DateTime.now().millisecondsSinceEpoch}',
              'organization_id': orgId,
              'employee_id': empId,
              'leave_type_id': leaveTypeId,
              'entry_type': 'ADJUSTMENT',
              'units': totalDays,
              'transaction_date':
                  DateTime.now().toIso8601String().split('T')[0],
              'remarks': 'Reversal on leave withdrawal / deletion ($requestId)',
              'created_at': DateTime.now().toIso8601String(),
            });
            secureLog(
                '[Leave] Ledger entry reversed for approved leave id=$requestId (units: $totalDays)');
          } catch (ledErr) {
            secureLog('[Leave] Ledger reversal notice: $ledErr');
          }
        }
      }

      // 3. Authoritative canonical DELETE from 'leave_requests'
      await _client.from('leave_requests').delete().eq('id', requestId);
      secureLog(
          '[Leave] Leave request row permanently deleted in Supabase -> $requestId');

      // 4. Clean up any related notification_events tied to this request
      try {
        await _client
            .from('notification_events')
            .delete()
            .ilike('action_url', '%$requestId%');
      } catch (_) {}

      // Send push notification to the reporting manager
      final managerId = user.reportsToId;
      if (managerId != null && managerId.isNotEmpty) {
        try {
          await PushSenderService.instance.sendToEmployee(
            employeeId: managerId,
            title: 'Leave Withdrawn',
            body: '${user.name} has withdrawn and removed their leave request.',
            route: 'leaves',
            data: {'leave_id': requestId},
          );
        } catch (e) {
          secureLog('[Leave] Push cancellation notice: $e');
        }
      }
    } catch (e) {
      secureLog('[Leave] cancelLeave failed: $e');
      rethrow;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static (Color, Color) _resolveBadgeColors(
      String name, String code, int index) {
    final lower = '$name $code'.toLowerCase();
    if (lower.contains('casual') || lower.contains('cl')) {
      return (AppColors.mintBg, AppColors.mintFg);
    } else if (lower.contains('sick') ||
        lower.contains('sl') ||
        lower.contains('medical')) {
      return (AppColors.lavenderBg, AppColors.lavenderFg);
    } else if (lower.contains('earned') ||
        lower.contains('el') ||
        lower.contains('annual') ||
        lower.contains('privilege')) {
      return (AppColors.skyBg, AppColors.skyFg);
    } else if (lower.contains('maternity') ||
        lower.contains('paternity') ||
        lower.contains('parental')) {
      return (AppColors.roseBg, AppColors.roseFg);
    } else if (lower.contains('comp') || lower.contains('off')) {
      return (AppColors.peachBg, AppColors.peachFg);
    }
    const defaultColors = [
      (AppColors.mintBg, AppColors.mintFg),
      (AppColors.lavenderBg, AppColors.lavenderFg),
      (AppColors.skyBg, AppColors.skyFg),
      (AppColors.roseBg, AppColors.roseFg),
    ];
    return defaultColors[index % defaultColors.length];
  }

  static bool _isSick(String s) =>
      s.contains('sick') || s.contains('medical') || s.contains('sl');
  static bool _isEarned(String s) =>
      s.contains('earned') ||
      s.contains('privilege') ||
      s.contains('annual') ||
      s.contains('el');
  static bool _isCasual(String s) =>
      s.contains('casual') || s.contains('cl') || s.contains('personal');

  static bool _matchesType(String name, LeaveType type) {
    switch (type) {
      case LeaveType.casual:
        return _isCasual(name);
      case LeaveType.sick:
        return _isSick(name);
      case LeaveType.earned:
        return _isEarned(name);
      case LeaveType.maternity:
        return name.contains('maternity');
      case LeaveType.paternity:
        return name.contains('paternity');
    }
  }

  static String _leaveTypeName(LeaveType type) {
    switch (type) {
      case LeaveType.casual:
        return 'Casual Leave';
      case LeaveType.sick:
        return 'Sick Leave';
      case LeaveType.earned:
        return 'Earned Leave';
      case LeaveType.maternity:
        return 'Maternity Leave';
      case LeaveType.paternity:
        return 'Paternity Leave';
    }
  }

  static String _leaveTypeCode(LeaveType type) {
    switch (type) {
      case LeaveType.casual:
        return 'CL';
      case LeaveType.sick:
        return 'SL';
      case LeaveType.earned:
        return 'EL';
      case LeaveType.maternity:
        return 'ML';
      case LeaveType.paternity:
        return 'PL';
    }
  }


  static LeaveStatus _parseStatus(dynamic s) {
    final str = s?.toString().toUpperCase().trim() ?? 'PENDING';
    if (str == 'APPROVED') return LeaveStatus.approved;
    if (str == 'REJECTED') return LeaveStatus.rejected;
    if (str == 'CANCELLED' || str == 'WITHDRAWN') return LeaveStatus.cancelled;
    return LeaveStatus.pending;
  }

  static LeaveType parseLeaveType(String s) {
    final lower = s.toLowerCase();
    if (_isSick(lower)) return LeaveType.sick;
    if (_isEarned(lower)) return LeaveType.earned;
    if (lower.contains('maternity')) return LeaveType.maternity;
    if (lower.contains('paternity')) return LeaveType.paternity;
    return LeaveType.casual;
  }
}
