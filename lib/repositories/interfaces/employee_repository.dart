import '../../models/employee_models.dart';

abstract class ILeaveRepository {
  Future<LeaveBalanceModel> getLeaveBalances(String employeeId);
  Future<List<LeaveRequestModel>> getLeaveRequests(String employeeId);
  Future<List<LeaveTypeConfigModel>> getLeaveTypes(String organizationId);
  Future<LeaveRequestModel> applyLeave(LeaveRequestModel request);
  Future<void> cancelLeave(String requestId, {String? reason});
}

abstract class IAttendanceRepository {
  Future<List<TimesheetEntryModel>> getTimesheets(String employeeId, {int? month, int? year});
  Future<AttendanceSummaryModel> getAttendanceSummary(String employeeId, {int? month, int? year});
  Future<List<RegularizationRequestModel>> getRegularizationRequests(String employeeId);
  Future<RegularizationRequestModel> submitRegularization(RegularizationRequestModel request);
  Future<void> withdrawRegularization(String requestId);
  Future<List<AttendanceDeviationModel>> getAttendanceDeviations(String employeeId);
  Future<List<AttendanceExceptionModel>> getActionableAttendanceExceptions(String employeeId);
}

abstract class IMoreModulesRepository {
  Future<List<EmployeeServiceConfigModel>> getServiceConfigs(String organizationId);
  Future<List<ShiftRosterModel>> getShiftRoster(String employeeId);
  Future<List<PayslipModel>> getPayslips(String employeeId);
  Future<List<ExpenseClaimModel>> getExpenseClaims(String employeeId);
  Future<ExpenseClaimModel> submitExpenseClaim(ExpenseClaimModel claim);

  Future<List<DigitalLetterModel>> getDigitalLetters(String employeeId);
  Future<void> acknowledgeDigitalLetter(String letterId, {String? signatureData});
  Future<List<DocumentModel>> getDocuments(String employeeId, {String? companyId, String? requesterRole});
  Future<DocumentModel> uploadDocument(DocumentModel document);

  Future<List<PerformanceGoalModel>> getPerformanceGoals(String employeeId);
  Future<List<AnnouncementModel>> getAnnouncements();
  Future<List<ComplaintModel>> getComplaints(String employeeId);
  Future<ComplaintModel> submitComplaint(ComplaintModel complaint);
}

abstract class INotificationRepository {
  Future<List<NotificationItemModel>> getNotifications(String employeeId);
  Future<List<ActivityItemModel>> getRecentActivities(String employeeId);
  Future<void> markNotificationAsRead(String notificationId);
  Future<void> deleteNotification(String notificationId);
}
