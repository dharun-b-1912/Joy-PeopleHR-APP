import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/secure_log.dart';
import '../../models/employee_models.dart';
import '../../repositories/interfaces/employee_repository.dart';
import '../../repositories/supabase/supabase_leave_repository.dart';
import '../services/user_service.dart';

class LeaveController extends ChangeNotifier {
  static final LeaveController instance =
      LeaveController._internal(SupabaseLeaveRepository());
  LeaveController._internal(this._leaveRepository);

  final ILeaveRepository _leaveRepository;
  RealtimeChannel? _leaveChannel;
  String? _subscribedEmployeeId;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  LeaveBalanceModel? _balance;
  LeaveBalanceModel? get balance => _balance;

  List<LeaveRequestModel> _requests = [];
  List<LeaveRequestModel> get requests => _requests;

  List<LeaveTypeConfigModel> _leaveTypes = [];
  List<LeaveTypeConfigModel> get leaveTypes => _leaveTypes;

  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    UserService.instance.addListener(_loadData);
    _loadData();
  }

  Future<void> refresh() => _loadData();

  Future<void> _loadData() async {
    final hasExistingData = _requests.isNotEmpty || _balance != null;
    if (!hasExistingData) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final user = UserService.instance.currentUser;
      final employeeId = user.resolvedEmployeeId;

      if (employeeId.isNotEmpty) {
        _subscribeRealtime(employeeId);
      }

      final results = await Future.wait([
        _leaveRepository.getLeaveTypes(user.tenantId),
        _leaveRepository.getLeaveBalances(employeeId),
        _leaveRepository.getLeaveRequests(employeeId),
      ]);

      _leaveTypes = results[0] as List<LeaveTypeConfigModel>;
      _balance = results[1] as LeaveBalanceModel?;
      _requests = results[2] as List<LeaveRequestModel>;
    } catch (e) {
      _errorMessage = "Failed to load leave data: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribeRealtime(String employeeId) {
    if (_subscribedEmployeeId == employeeId && _leaveChannel != null) return;
    _leaveChannel?.unsubscribe();

    try {
      _subscribedEmployeeId = employeeId;
      _leaveChannel = Supabase.instance.client
          .channel('leave-realtime-$employeeId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'leave_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'employee_id',
            value: employeeId,
          ),
          callback: (payload) {
            secureLog('[REALTIME] leave_requests event for $employeeId');
            _silentRefresh();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'leave_balances',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'employee_id',
            value: employeeId,
          ),
          callback: (payload) {
            secureLog('[REALTIME] leave_balances event for $employeeId');
            _silentRefresh();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'leave_types',
          callback: (payload) {
            secureLog('[REALTIME] leave_types catalog event');
            _silentRefresh();
          },
        )
        ..subscribe();
    } catch (e) {
      secureLog('[REALTIME] Leave subscription notice: $e');
    }
  }

  Future<void> _silentRefresh() async {
    try {
      final user = UserService.instance.currentUser;
      final employeeId = user.resolvedEmployeeId;
      _leaveTypes = await _leaveRepository.getLeaveTypes(user.tenantId);
      _balance = await _leaveRepository.getLeaveBalances(employeeId);
      _requests = await _leaveRepository.getLeaveRequests(employeeId);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> applyLeave({
    required LeaveType type,
    String? leaveTypeId,
    String? leaveTypeCode,
    String? leaveTypeName,
    required DateTime startDate,
    required DateTime endDate,
    double? customDays,
    bool isHalfDay = false,
    String? halfDaySession,
    String reason = "",
  }) async {
    try {
      final user = UserService.instance.currentUser;
      final days = customDays ?? (isHalfDay ? 0.5 : (endDate.difference(startDate).inDays + 1).toDouble());

      final approverId = user.reportsToId;
      final approverName = user.reportsToName;

      final newReq = LeaveRequestModel(
        id: "lv-${DateTime.now().millisecondsSinceEpoch}",
        employeeId: user.resolvedEmployeeId,
        type: type,
        leaveTypeId: leaveTypeId,
        leaveTypeCode: leaveTypeCode,
        leaveTypeName: leaveTypeName,
        startDate: startDate,
        endDate: endDate,
        daysCount: days,
        isHalfDay: isHalfDay,
        halfDaySession: halfDaySession,
        reason: reason,
        status: LeaveStatus.pending,
        createdAt: DateTime.now(),
        approverId: approverId,
        approverName: approverName,
        managerId: approverId,
        managerName: approverName,
      );

      await _leaveRepository.applyLeave(newReq);
      await _loadData();
      return true;
    } catch (e) {
      _errorMessage = "Failed to apply leave: $e";
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelLeave(String requestId, {String? reason}) async {
    try {
      await _leaveRepository.cancelLeave(requestId, reason: reason);
      await _loadData();
      return true;
    } catch (e) {
      _errorMessage = "Failed to cancel leave: $e";
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    UserService.instance.removeListener(_loadData);
    _leaveChannel?.unsubscribe();
    super.dispose();
  }
}
