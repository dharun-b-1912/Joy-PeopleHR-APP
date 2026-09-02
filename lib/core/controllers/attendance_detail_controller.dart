import 'package:flutter/material.dart';
import '../../models/employee_models.dart';
import '../../repositories/interfaces/employee_repository.dart';
import '../../repositories/supabase/supabase_attendance_repository.dart';
import '../services/user_service.dart';

class AttendanceDetailController extends ChangeNotifier {
  static final AttendanceDetailController instance =
      AttendanceDetailController._internal(SupabaseAttendanceRepository());
  AttendanceDetailController._internal(this._attendanceRepository);

  final IAttendanceRepository _attendanceRepository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  DateTime _selectedMonth = DateTime.now();
  DateTime get selectedMonth => _selectedMonth;

  List<TimesheetEntryModel> _timesheets = [];
  List<TimesheetEntryModel> get timesheets => _timesheets;

  AttendanceSummaryModel? _summary;
  AttendanceSummaryModel? get summary => _summary;

  List<RegularizationRequestModel> _regularizations = [];
  List<RegularizationRequestModel> get regularizations => _regularizations;

  List<AttendanceDeviationModel> _deviations = [];
  List<AttendanceDeviationModel> get deviations => _deviations;

  List<AttendanceExceptionModel> _actionableExceptions = [];
  List<AttendanceExceptionModel> get actionableExceptions => _actionableExceptions;

  AttendanceDeviationModel? get todayDeviation {
    final now = DateTime.now();
    try {
      return _deviations.firstWhere(
        (d) =>
            d.date.year == now.year &&
            d.date.month == now.month &&
            d.date.day == now.day &&
            !d.isRegularized,
      );
    } catch (_) {
      return _deviations.isNotEmpty && !_deviations.first.isRegularized ? _deviations.first : null;
    }
  }

  AttendanceExceptionModel? get latestActionableException {
    return _actionableExceptions.isNotEmpty ? _actionableExceptions.first : null;
  }

  void initialize() {
    UserService.instance.addListener(_loadData);
    _loadData();
  }

  Future<void> setMonth(DateTime month) async {
    _selectedMonth = month;
    await _loadData();
  }

  Future<void> nextMonth() async {
    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    await _loadData();
  }

  Future<void> previousMonth() async {
    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    await _loadData();
  }

  Future<void> refresh() => _loadData();

  Future<void> _loadData() async {
    final hasExistingData = _timesheets.isNotEmpty;
    if (!hasExistingData) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final employeeId = UserService.instance.currentUser.resolvedEmployeeId;
      final results = await Future.wait([
        _attendanceRepository.getTimesheets(
          employeeId,
          month: _selectedMonth.month,
          year: _selectedMonth.year,
        ),
        _attendanceRepository.getAttendanceSummary(
          employeeId,
          month: _selectedMonth.month,
          year: _selectedMonth.year,
        ),
        _attendanceRepository.getRegularizationRequests(employeeId),
        _attendanceRepository.getAttendanceDeviations(employeeId),
        _attendanceRepository.getActionableAttendanceExceptions(employeeId),
      ]);

      final fetchedTimesheets = results[0] as List<TimesheetEntryModel>;
      fetchedTimesheets.sort((a, b) => b.date.compareTo(a.date));
      _timesheets = fetchedTimesheets;
      _summary = results[1] as AttendanceSummaryModel?;
      _regularizations = results[2] as List<RegularizationRequestModel>;
      _deviations = results[3] as List<AttendanceDeviationModel>;
      _actionableExceptions = results[4] as List<AttendanceExceptionModel>;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitRegularization({
    required DateTime date,
    required String inTime,
    required String outTime,
    required String reason,
    String shiftName = 'General Shift',
    String shiftWindow = '09:30 AM — 06:30 PM',
    String reasonCode = 'FORGOT_CHECK_IN',
  }) async {
    try {
      final user = UserService.instance.currentUser;
      final employeeId = user.resolvedEmployeeId;
      final req = RegularizationRequestModel(
        id: "reg-${DateTime.now().millisecondsSinceEpoch}",
        employeeId: employeeId,
        employeeName: user.name,
        department: user.department,
        date: date,
        shiftName: shiftName,
        shiftWindow: shiftWindow,
        requestedInTime: inTime,
        requestedOutTime: outTime,
        reasonCode: reasonCode,
        reason: reason,
        status: LeaveStatus.pending,
        statusState: RegularizationStatusState.managerPending,
        currentStage: 'MANAGER_REVIEW',
      );

      await _attendanceRepository.submitRegularization(req);
      await _loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> withdrawRegularization(String requestId) async {
    try {
      _regularizations.removeWhere((r) => r.id == requestId);
      notifyListeners();
      await _attendanceRepository.withdrawRegularization(requestId);
      await _loadData();
      return true;
    } catch (e) {
      await _loadData();
      return false;
    }
  }
}
