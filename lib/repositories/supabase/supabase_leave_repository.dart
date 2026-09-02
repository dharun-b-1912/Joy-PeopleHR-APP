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
import '../../models/employee_models.dart';
import '../interfaces/employee_repository.dart';

/// WorkForceOS — Production Supabase Leave Repository
/// Single Source of Truth for Leave Types, Entitlements Ledger, Requests, and Approvals
class SupabaseLeaveRepository implements ILeaveRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<LeaveTypeConfigModel>> getLeaveTypes(String organizationId) async {
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
        secureLog('[Leave] No active leave types configured in DB for $orgId — using standard catalog');
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

      return data.map<LeaveTypeConfigModel>((m) => LeaveTypeConfigModel.fromJson(m)).toList();
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
      final targetId = (user.employeeUuid?.isNotEmpty == true)
          ? user.employeeUuid!
          : (user.employeeId.isNotEmpty ? user.employeeId : employeeId);

      final orFilter = <String>{
        'employee_id.eq.$targetId',
        if (user.employeeId.isNotEmpty) 'employee_id.eq.${user.employeeId}',
        if (user.employeeUuid?.isNotEmpty == true) 'employee_id.eq.${user.employeeUuid}',
      }.join(',');

      // 1. Fetch entitlements
      final data = await withTimeout(
        _client
            .from('leave_entitlements')
            .select()
            .or(orFilter),
      );

      // 2. Fetch approved leave requests to accurately tally used days
      List<dynamic> approvedRequestsData = [];
      try {
        approvedRequestsData = await withTimeout(
          _client
              .from('leave_requests')
              .select()
              .or(orFilter)
              .ilike('status', 'approved'),
        );
      } catch (e) {
        secureLog('[Leave] approved requests fetch notice: $e');
      }

      final approvedDaysByType = <String, double>{};
      for (final req in approvedRequestsData) {
        final code = (req['leave_type_code'] ?? '').toString().toUpperCase();
        final name = (req['leave_type_name'] ?? '').toString().toLowerCase();
        final days = ((req['working_days'] ?? req['leave_days_deducted'] ?? req['days_count'] ?? req['total_calendar_days']) as num?)?.toDouble() ?? 1.0;

        String key = code;
        if (name.contains('casual') || key == 'CL') {
          key = 'CL';
        } else if (name.contains('sick') || name.contains('medical') || key == 'SL') {
          key = 'SL';
        } else if (name.contains('earned') || name.contains('privilege') || name.contains('annual') || key == 'EL' || key == 'PL') {
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

        secureLog('[Leave] Baseline 12-month auto-calculation for $targetId (Month $currentMonth): CL (12 total, 1.0/mo, used=$clUsed), SL (10 total, 0.83/mo, used=$slUsed), EL (15 total, 1.25/mo, used=$elUsed)');
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
              accruedTillDate: ((slQuota / 12) * currentMonth).clamp(0.0, slQuota),
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
              accruedTillDate: ((elQuota / 12) * currentMonth).clamp(0.0, elQuota),
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
        final typeId = row['leave_type_id']?.toString();
        final code = row['leave_type_code']?.toString() ?? 'LT-${i + 1}';
        final name = row['leave_type_name']?.toString() ?? 'Leave';
        final lowerName = '$name $code'.toLowerCase();

        final key = _isCasual(lowerName) ? 'CL' : _isSick(lowerName) ? 'SL' : _isEarned(lowerName) ? 'EL' : code.toUpperCase();
        final approvedForThisType = approvedDaysByType[key] ?? approvedDaysByType[code.toUpperCase()] ?? 0.0;

        final rawUsed = (row['used'] as num?)?.toDouble() ?? 0.0;
        final used = approvedRequestsData.isNotEmpty ? approvedForThisType : rawUsed;
        final granted = (row['granted'] as num?)?.toDouble() ?? (row['opening_balance'] as num?)?.toDouble() ?? 0.0;
        final opening = (row['opening_balance'] as num?)?.toDouble() ?? granted;
        final accrued = (row['accrued'] as num?)?.toDouble() ?? 0.0;
        final annualQuota = granted;
        final monthlyRate = double.parse((annualQuota > 0 ? annualQuota / 12 : 0.0).toStringAsFixed(2));
        final accruedTillDate = (monthlyRate * currentMonth).clamp(0.0, annualQuota > 0 ? annualQuota : 999.0);
        final totalQuota = granted + accrued;
        final avail = (totalQuota - used).clamp(0.0, 999.0);

        // Assign aesthetic badge colors based on leave type code/name
        final colorPair = _resolveBadgeColors(name, code, i);

        items.add(DynamicLeaveBalanceItem(
          leaveTypeId: typeId,
          leaveTypeCode: code,
          leaveTypeName: name,
          available: avail,
          used: used,
          granted: granted,
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

      secureLog('[Leave] Loaded ${items.length} dynamic entitlements from Supabase for $targetId');
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
          : (user.employeeId.isNotEmpty ? user.employeeId : employeeId);

      final orFilter = <String>{
        'employee_id.eq.$targetId',
        if (user.employeeId.isNotEmpty) 'employee_id.eq.${user.employeeId}',
        if (user.employeeUuid?.isNotEmpty == true) 'employee_id.eq.${user.employeeUuid}',
      }.join(',');

      final data = await withTimeout(
        _client
            .from('leave_requests')
            .select()
            .or(orFilter)
            .order('created_at', ascending: false),
      );

      if (data.isEmpty) {
        secureLog('[Leave] No leave requests found in DB for $targetId');
        return [];
      }

      return data.map<LeaveRequestModel>((map) {
        final typeStr = (map['leave_type_name'] ?? map['leave_type_code'] ?? 'Leave')
            .toString();
        return LeaveRequestModel(
          id: map['id'].toString(),
          employeeId: map['employee_id']?.toString() ?? targetId,
          type: parseLeaveType(typeStr),
          leaveTypeId: map['leave_type_id']?.toString(),
          leaveTypeCode: map['leave_type_code']?.toString(),
          leaveTypeName: map['leave_type_name']?.toString() ?? typeStr,
          startDate: DateTime.tryParse(map['from_date'].toString()) ?? DateTime.now(),
          endDate: DateTime.tryParse(map['to_date'].toString()) ?? DateTime.now(),
          daysCount: (map['leave_days_deducted'] as num?)?.toDouble() ??
              (map['working_days'] as num?)?.toDouble() ??
              1.0,
          reason: map['reason']?.toString() ?? '',
          status: _parseStatus(map['status']),
          createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
              DateTime.tryParse(map['submitted_at']?.toString() ?? '') ??
              DateTime.now(),
          approverId: map['manager_id']?.toString(),
          approverName: map['manager_name']?.toString(),
          managerId: map['manager_id']?.toString(),
          managerName: map['manager_name']?.toString(),
          currentApproverName: map['current_approver_name']?.toString(),
          rejectionReason: map['rejection_reason']?.toString() ?? map['comments']?.toString(),
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

    // Resolve matching catalog row or fallback code & id
    String typeCode = request.leaveTypeCode ?? _leaveTypeCode(request.type);
    String typeId = request.leaveTypeId ?? '';

    if (typeId.isEmpty) {
      try {
        final types = await _client.from('leave_types').select('id, code, name');
        for (final t in types) {
          final n = '${t['name']} ${t['code']}'.toLowerCase();
          if (_matchesType(n, request.type) || t['name'] == typeName) {
            typeId = t['id']?.toString() ?? '';
            typeCode = t['code']?.toString() ?? typeCode;
            break;
          }
        }
      } catch (e) {
        secureLog('[Leave] leave_types lookup notice: $e');
      }
    }

    if (typeId.isEmpty) {
      typeId = _leaveTypeId(request.type);
    }

    final targetEmployeeId = user.resolvedEmployeeId;
    final orgId = user.tenantId;
    final compId = user.companyUuid?.isNotEmpty == true
        ? user.companyUuid!
        : (user.companyId.isNotEmpty ? user.companyId : orgId);
    final managerId = request.managerId ?? user.reportsToId;
    final managerName = request.managerName ?? user.reportsToName;
    final currentApprover = (managerName != null && managerName.isNotEmpty)
        ? (managerName.contains('(') ? managerName : '$managerName (Reporting Manager)')
        : 'Reporting Manager';

    // Canonical direct insert into leave_requests with guaranteed schema compliance
    final payload = <String, dynamic>{
      if (orgId.isNotEmpty) 'organization_id': orgId,
      if (compId.isNotEmpty) 'company_id': compId,
      'employee_id': targetEmployeeId,
      'request_code': 'LV-${DateTime.now().millisecondsSinceEpoch}',
      'employee_name': user.name,
      'leave_type_id': typeId,
      'leave_type_name': typeName,
      'leave_type_code': typeCode,
      'from_date': request.startDate.toIso8601String().split('T')[0],
      'to_date': request.endDate.toIso8601String().split('T')[0],
      'total_calendar_days': (request.endDate.difference(request.startDate).inDays + 1),
      'working_days': request.daysCount > 0 ? (request.daysCount.toInt() == request.daysCount ? request.daysCount.toInt() : request.daysCount.ceil()) : 1,
      'leave_days_deducted': request.daysCount > 0 ? (request.daysCount.toInt() == request.daysCount ? request.daysCount.toInt() : request.daysCount.ceil()) : 1,
      'reason': request.reason,
      'status': 'Pending',
      if (managerId != null && managerId.isNotEmpty) 'manager_id': managerId,
      if (managerName != null && managerName.isNotEmpty) 'manager_name': managerName,
      'current_approver_name': currentApprover,
      'is_half_day': request.isHalfDay,
      'half_day_session': request.halfDaySession,
      'submitted_at': DateTime.now().toIso8601String(),
    };

    if (user.department.isNotEmpty && user.department != 'N/A') {
      payload['department_name'] = user.department;
    }

    try {
      await _client.from('leave_requests').insert(payload);
      secureLog('[Leave] Leave request successfully inserted into Supabase → $typeName');
    } catch (e) {
      secureLog('[Leave] Direct insert failed: $e. Retrying minimal payload...');
      final minimalPayload = Map<String, dynamic>.from(payload);
      minimalPayload.remove('department_name');
      await _client.from('leave_requests').insert(minimalPayload);
      secureLog('[Leave] Leave request inserted with minimal payload → $typeName');
    }

    // Outbox notification sync via centralized service
    await RealtimeOutboxService.insertEvent(
      entityType: 'LEAVE_REQUEST',
      eventType: 'CREATED',
      entityId: payload['request_code'],
      tenantId: orgId,
      actorId: targetEmployeeId,
      payload: payload,
    );

    // Send push notification to the reporting manager/HR
    if (managerId != null && managerId.isNotEmpty) {
      try {
        final dateRange = '${request.startDate.day}/${request.startDate.month} - ${request.endDate.day}/${request.endDate.month}';
        await PushSenderService.instance.sendToEmployee(
          employeeId: managerId,
          title: 'New Leave Request',
          body: '${user.name} has requested $typeName ($dateRange) — ${request.daysCount} day(s)',
          route: 'leaves',
          data: {'leave_id': payload['request_code'] ?? '', 'employee_name': user.name},
        );
      } catch (e) {
        secureLog('[Leave] Push to manager notice: $e');
      }
    }

    return request;
  }

  @override
  Future<void> cancelLeave(String requestId, {String? reason}) async {
    final user = UserService.instance.currentUser;
    final orgId = user.tenantId;

    try {
      await _client
          .from('leave_requests')
          .update({
            'status': 'Cancelled',
            'rejection_reason': reason ?? 'Cancelled by employee',
          })
          .eq('id', requestId);
      secureLog('[Leave] Leave request cancelled successfully in Supabase -> $requestId');
    } catch (e) {
      secureLog('[Leave] cancelLeave by ID notice: $e. Retrying by request_code...');
      try {
        await _client
            .from('leave_requests')
            .update({
              'status': 'Cancelled',
              'rejection_reason': reason ?? 'Cancelled by employee',
            })
            .eq('request_code', requestId);
      } catch (_) {}
    }

    // Outbox notification for cancellation via centralized service
    await RealtimeOutboxService.insertEvent(
      entityType: 'LEAVE_REQUEST',
      eventType: 'CANCELLED',
      entityId: requestId,
      tenantId: orgId,
      actorId: user.resolvedEmployeeId,
      payload: {
        'id': requestId,
        'status': 'Cancelled',
        'rejection_reason': reason ?? 'Cancelled by employee',
      },
    );

    // Send push notification to the reporting manager
    final managerId = user.reportsToId;
    if (managerId != null && managerId.isNotEmpty) {
      try {
        await PushSenderService.instance.sendToEmployee(
          employeeId: managerId,
          title: 'Leave Cancelled',
          body: '${user.name} has cancelled their leave request.',
          route: 'leaves',
          data: {'leave_id': requestId},
        );
      } catch (e) {
        secureLog('[Leave] Push cancellation notice: $e');
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static (Color, Color) _resolveBadgeColors(String name, String code, int index) {
    final lower = '$name $code'.toLowerCase();
    if (lower.contains('casual') || lower.contains('cl')) {
      return (AppColors.mintBg, AppColors.mintFg);
    } else if (lower.contains('sick') || lower.contains('sl') || lower.contains('medical')) {
      return (AppColors.lavenderBg, AppColors.lavenderFg);
    } else if (lower.contains('earned') || lower.contains('el') || lower.contains('annual') || lower.contains('privilege')) {
      return (AppColors.skyBg, AppColors.skyFg);
    } else if (lower.contains('maternity') || lower.contains('paternity') || lower.contains('parental')) {
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
      s.contains('earned') || s.contains('privilege') || s.contains('annual') || s.contains('el');
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

  static String _leaveTypeId(LeaveType type) {
    switch (type) {
      case LeaveType.casual:
        return 'lt-cl';
      case LeaveType.sick:
        return 'lt-sl';
      case LeaveType.earned:
        return 'lt-el';
      case LeaveType.maternity:
        return 'lt-ml';
      case LeaveType.paternity:
        return 'lt-pl';
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
