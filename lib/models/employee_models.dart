import 'package:flutter/material.dart';
import '../core/utils/app_date_time.dart';

// --- LEAVE MODELS ---
enum LeaveType { casual, sick, earned, maternity, paternity }

enum LeaveStatus { pending, approved, rejected, cancelled }

class LeaveTypeConfigModel {
  final String id;
  final String organizationId;
  final String code;
  final String name;
  final String? description;
  final String category;
  final bool isPaid;
  final bool isActive;
  final bool allowHalfDay;
  final bool allowHourly;
  final double maxDaysPerRequest;
  final double minDaysPerRequest;
  final bool attachmentRequired;
  final bool approvalRequired;

  const LeaveTypeConfigModel({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.name,
    this.description,
    this.category = 'Paid',
    this.isPaid = true,
    this.isActive = true,
    this.allowHalfDay = true,
    this.allowHourly = false,
    this.maxDaysPerRequest = 14.0,
    this.minDaysPerRequest = 0.5,
    this.attachmentRequired = false,
    this.approvalRequired = true,
  });

  factory LeaveTypeConfigModel.fromJson(Map<String, dynamic> json) {
    return LeaveTypeConfigModel(
      id: json['id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      code: json['code']?.toString() ?? 'LV',
      name: json['name']?.toString() ?? 'Leave',
      description: json['description']?.toString(),
      category: json['category']?.toString() ?? 'Paid',
      isPaid: json['is_paid'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      allowHalfDay: json['allow_half_day'] as bool? ?? true,
      allowHourly: json['allow_hourly'] as bool? ?? false,
      maxDaysPerRequest: (json['max_days_per_request'] as num?)?.toDouble() ?? 14.0,
      minDaysPerRequest: (json['min_days_per_request'] as num?)?.toDouble() ?? 0.5,
      attachmentRequired: json['attachment_required'] as bool? ?? false,
      approvalRequired: json['approval_required'] as bool? ?? true,
    );
  }
}

class DynamicLeaveBalanceItem {
  final String? leaveTypeId;
  final String leaveTypeCode;
  final String leaveTypeName;
  final double available;
  final double used;
  final double? granted;
  final double? opening;
  final double annualQuota;
  final double monthlyAccrualRate;
  final double accruedTillDate;
  final String accrualFrequency;
  final Color? colorBg;
  final Color? colorFg;

  const DynamicLeaveBalanceItem({
    this.leaveTypeId,
    required this.leaveTypeCode,
    required this.leaveTypeName,
    required this.available,
    required this.used,
    this.granted,
    this.opening,
    this.annualQuota = 12.0,
    this.monthlyAccrualRate = 1.0,
    this.accruedTillDate = 12.0,
    this.accrualFrequency = "Monthly",
    this.colorBg,
    this.colorFg,
  });
}

class LeaveBalanceModel {
  final List<DynamicLeaveBalanceItem> items;
  final double casualAvailable;
  final double casualUsed;
  final double sickAvailable;
  final double sickUsed;
  final double earnedAvailable;
  final double earnedUsed;

  const LeaveBalanceModel({
    this.items = const [],
    required this.casualAvailable,
    required this.casualUsed,
    required this.sickAvailable,
    required this.sickUsed,
    required this.earnedAvailable,
    required this.earnedUsed,
  });

  factory LeaveBalanceModel.empty() {
    return const LeaveBalanceModel(
      items: [],
      casualAvailable: 0,
      casualUsed: 0,
      sickAvailable: 0,
      sickUsed: 0,
      earnedAvailable: 0,
      earnedUsed: 0,
    );
  }
}

class LeaveRequestModel {
  final String id;
  final String employeeId;
  final LeaveType type;
  final String? leaveTypeId;
  final String? leaveTypeCode;
  final String? leaveTypeName;
  final DateTime startDate;
  final DateTime endDate;
  final double daysCount;
  final String reason;
  final LeaveStatus status;
  final DateTime createdAt;
  final String? approverId;
  final String? approverName;
  final String? managerId;
  final String? managerName;
  final String? currentApproverName;
  final String? rejectionReason;
  final bool isHalfDay;
  final String? halfDaySession;

  const LeaveRequestModel({
    required this.id,
    required this.employeeId,
    required this.type,
    this.leaveTypeId,
    this.leaveTypeCode,
    this.leaveTypeName,
    required this.startDate,
    required this.endDate,
    required this.daysCount,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.approverId,
    this.approverName,
    this.managerId,
    this.managerName,
    this.currentApproverName,
    this.rejectionReason,
    this.isHalfDay = false,
    this.halfDaySession,
  });

  LeaveRequestModel copyWith({
    String? id,
    String? employeeId,
    LeaveType? type,
    String? leaveTypeId,
    String? leaveTypeCode,
    String? leaveTypeName,
    DateTime? startDate,
    DateTime? endDate,
    double? daysCount,
    String? reason,
    LeaveStatus? status,
    DateTime? createdAt,
    String? approverId,
    String? approverName,
    String? managerId,
    String? managerName,
    String? currentApproverName,
    String? rejectionReason,
    bool? isHalfDay,
    String? halfDaySession,
  }) {
    return LeaveRequestModel(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      type: type ?? this.type,
      leaveTypeId: leaveTypeId ?? this.leaveTypeId,
      leaveTypeCode: leaveTypeCode ?? this.leaveTypeCode,
      leaveTypeName: leaveTypeName ?? this.leaveTypeName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      daysCount: daysCount ?? this.daysCount,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      approverId: approverId ?? this.approverId,
      approverName: approverName ?? this.approverName,
      managerId: managerId ?? this.managerId,
      managerName: managerName ?? this.managerName,
      currentApproverName: currentApproverName ?? this.currentApproverName,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      isHalfDay: isHalfDay ?? this.isHalfDay,
      halfDaySession: halfDaySession ?? this.halfDaySession,
    );
  }
}

// --- ATTENDANCE & REGULARIZATION MODELS ---
enum DayAttendanceStatus { 
  present, 
  absent, 
  leave, 
  holiday, 
  weekOff, 
  halfDay, 
  halfDayPresent,
  halfDayAbsent,
  late, 
  regularized,
  notPayable,
  none,
}

class TimesheetEntryModel {
  final String id;
  final DateTime date;
  final String? clockInTime;
  final String? clockOutTime;
  final String totalHours;
  final DayAttendanceStatus status;
  final String source; // e.g. Mobile, Web, Biometric

  // Checkout location verification fields
  final String? checkoutLocationStatus; // assigned_location, main_office, other_authorized, unauthorized, gps_unavailable
  final String? checkoutLocationName;
  final String? checkoutLocationReason;
  final double? checkoutLatitude;
  final double? checkoutLongitude;
  final int netWorkingMinutes;

  const TimesheetEntryModel({
    required this.id,
    required this.date,
    this.clockInTime,
    this.clockOutTime,
    required this.totalHours,
    required this.status,
    this.source = "Mobile",
    this.netWorkingMinutes = 0,
    this.checkoutLocationStatus,
    this.checkoutLocationName,
    this.checkoutLocationReason,
    this.checkoutLatitude,
    this.checkoutLongitude,
  });

  /// Standard shift working minutes (capped at 8h / 480 mins)
  int get regularMinutes => netWorkingMinutes > 480 ? 480 : (netWorkingMinutes < 0 ? 0 : netWorkingMinutes);

  /// Overtime minutes (any time beyond 8h / 480 mins)
  int get overtimeMinutes => netWorkingMinutes > 480 ? netWorkingMinutes - 480 : 0;

  /// Formatted regular work duration, e.g. "8h 00m" or "6h 30m"
  String get formattedRegularHours {
    if (regularMinutes <= 0) return '0h 00m';
    final h = regularMinutes ~/ 60;
    final m = regularMinutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  /// Formatted overtime duration, e.g. "1h 30m"
  String get formattedOvertimeHours {
    if (overtimeMinutes <= 0) return '0h 00m';
    final h = overtimeMinutes ~/ 60;
    final m = overtimeMinutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  /// Human-readable checkout location label for admin/employee display
  String? get checkoutLocationLabel {
    if (checkoutLocationStatus == null) return null;
    switch (checkoutLocationStatus) {
      case 'assigned_location':
        return checkoutLocationName ?? 'Assigned Location';
      case 'main_office':
        return 'Main Office';
      case 'other_authorized':
        return checkoutLocationName ?? 'Other Location';
      case 'unauthorized':
        return 'Unknown Location';
      case 'gps_unavailable':
        return 'GPS Unavailable';
      default:
        return null;
    }
  }
}

class AttendanceSummaryModel {
  final int totalWorkingDays;
  final int presentDays;
  final int absentDays;
  final int leaveDays;
  final int holidaysCount;
  final int weekOffsCount;
  final String totalHoursWorked;
  final String avgDailyHours;

  const AttendanceSummaryModel({
    required this.totalWorkingDays,
    required this.presentDays,
    required this.absentDays,
    required this.leaveDays,
    required this.holidaysCount,
    required this.weekOffsCount,
    required this.totalHoursWorked,
    required this.avgDailyHours,
  });
}

enum RegularizationStatusState {
  managerPending,
  hrPending,
  approved,
  rejected,
  clarificationRequired,
}

class RegularizationRequestModel {
  final String id;
  final String employeeId;
  final String employeeName;
  final String department;
  final DateTime date;
  final String shiftName;
  final String shiftWindow;
  final String? originalInTime;
  final String? originalOutTime;
  final String? originalStatus;
  final String requestedInTime;
  final String requestedOutTime;
  final String reasonCode;
  final String reason;
  final LeaveStatus status;
  final RegularizationStatusState statusState;
  final String currentStage;
  final String? managerComment;
  final String? hrComment;
  final DateTime createdAt;

  const RegularizationRequestModel({
    required this.id,
    required this.employeeId,
    this.employeeName = '',
    this.department = '',
    required this.date,
    this.shiftName = 'General Shift',
    this.shiftWindow = '09:30 AM — 06:30 PM',
    this.originalInTime,
    this.originalOutTime,
    this.originalStatus,
    required this.requestedInTime,
    required this.requestedOutTime,
    this.reasonCode = 'FORGOT_CHECK_IN',
    required this.reason,
    required this.status,
    this.statusState = RegularizationStatusState.managerPending,
    this.currentStage = 'MANAGER_REVIEW',
    this.managerComment,
    this.hrComment,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? date;
}

// --- ATTENDANCE DEVIATION MODEL (LATE / EARLY / MISSING PUNCH) ---
class AttendanceDeviationModel {
  final String id;
  final String employeeId;
  final String employeeName;
  final String department;
  final DateTime date;
  final String shiftCode;
  final String shiftName;
  final String scheduledIn;
  final String? actualIn;
  final int lateMinutes;
  final int lateGraceMinutes;
  final int payableLateMinutes;
  final String scheduledOut;
  final String? actualOut;
  final int earlyMinutes;
  final int earlyGraceMinutes;
  final int payableEarlyMinutes;
  final String deviationType; // LATE, EARLY, LATE_EARLY, MISSING_CHECK_IN, MISSING_CHECK_OUT
  final String status; // DETECTED, PENDING_ACTION, MANAGER_REVIEW, HR_REVIEW, REGULARIZED, REJECTED
  final String? regularizationRequestId;
  final double payrollDeductionDays;

  const AttendanceDeviationModel({
    required this.id,
    required this.employeeId,
    this.employeeName = '',
    this.department = '',
    required this.date,
    this.shiftCode = 'GEN-09',
    this.shiftName = 'General Shift',
    this.scheduledIn = '09:30 AM',
    this.actualIn,
    this.lateMinutes = 0,
    this.lateGraceMinutes = 10,
    this.payableLateMinutes = 0,
    this.scheduledOut = '06:30 PM',
    this.actualOut,
    this.earlyMinutes = 0,
    this.earlyGraceMinutes = 10,
    this.payableEarlyMinutes = 0,
    required this.deviationType,
    this.status = 'DETECTED',
    this.regularizationRequestId,
    this.payrollDeductionDays = 0.0,
  });

  bool get isLate => lateMinutes > lateGraceMinutes;
  bool get isEarly => earlyMinutes > earlyGraceMinutes;
  bool get isRegularized => status == 'REGULARIZED';
  bool get isUnderReview => status == 'MANAGER_REVIEW' || status == 'HR_REVIEW' || status == 'REGULARIZATION_PENDING';
}

// --- SHIFT ROSTER MODEL ---
class ShiftRosterModel {
  final String id;
  final DateTime date;
  final String shiftName;
  final String shiftCode;
  final String shiftCategory; // DAY, MORNING, EVENING, NIGHT, FLEXIBLE, ROTATIONAL, CUSTOM, OFF
  final String shiftCategoryLabel;
  final String startTime;
  final String endTime;
  final String location;
  final bool isOffDay;
  final bool isOvernight;
  final bool isUpdated;
  final int rawSpanMinutes;
  final int breakMinutes;
  final int netScheduledMinutes;
  final String formattedDuration;
  final String? displayColorHex;
  final String policyName;
  final String assignedBy;

  const ShiftRosterModel({
    required this.id,
    required this.date,
    required this.shiftName,
    this.shiftCode = '',
    this.shiftCategory = 'DAY',
    this.shiftCategoryLabel = 'Day Shift',
    required this.startTime,
    required this.endTime,
    required this.location,
    this.isOffDay = false,
    this.isOvernight = false,
    this.isUpdated = false,
    this.rawSpanMinutes = 0,
    this.breakMinutes = 0,
    this.netScheduledMinutes = 0,
    this.formattedDuration = '',
    this.displayColorHex,
    this.policyName = 'Corporate Attendance v1',
    this.assignedBy = 'Department Roster',
  });
}

// --- PAYSLIP MODEL ---
class PayslipModel {
  final String id;
  final String employeeId;
  final String employeeCode;
  final String? employeeUuid;
  final String employeeName;
  final String designation;
  final String monthYear;
  final String grossEarnings;
  final String deductions;
  final String netPay;
  final String payDate;
  final String pdfUrl;
  final double basicSalary;
  final double hra;
  final double specialAllowance;
  final double pfDeduction;
  final double profTaxDeduction;
  final double incomeTaxDeduction;
  final double payableDays;
  final double lopDays;
  final int totalWorkingDays;
  final List<Map<String, dynamic>> earningsComponents;
  final List<Map<String, dynamic>> deductionsComponents;

  const PayslipModel({
    required this.id,
    this.employeeId = "",
    this.employeeCode = "",
    this.employeeUuid,
    this.employeeName = "",
    this.designation = "",
    required this.monthYear,
    required this.grossEarnings,
    required this.deductions,
    required this.netPay,
    required this.payDate,
    required this.pdfUrl,
    this.basicSalary = 0.0,
    this.hra = 0.0,
    this.specialAllowance = 0.0,
    this.pfDeduction = 0.0,
    this.profTaxDeduction = 0.0,
    this.incomeTaxDeduction = 0.0,
    this.payableDays = 30.0,
    this.lopDays = 0.0,
    this.totalWorkingDays = 30,
    this.earningsComponents = const [],
    this.deductionsComponents = const [],
  });

  /// Guaranteed employee-facing code (e.g. "JCS-017").
  /// Never displays database UUID.
  String get displayEmployeeId {
    final code = employeeCode.trim().isNotEmpty ? employeeCode.trim() : employeeId.trim();
    if (code.isEmpty || RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(code)) {
      return 'Employee ID unavailable';
    }
    return code;
  }

  /// Formatted pay date (e.g. "01 Aug 2026")
  String get formattedPayDate => AppDateTime.formatPayDate(payDate);

  /// Formatted period title (e.g. "July 2026")
  String get formattedPeriod => AppDateTime.formatPeriod(monthYear);

  /// Whether this payslip has a valid human-readable employee code (not a UUID)
  bool get hasValidEmployeeCode =>
      displayEmployeeId != 'Employee ID unavailable';

  /// Sum of earnings components (authoritative dynamic components first, fallback to individual fields)
  double get calculatedGross {
    if (earningsComponents.isNotEmpty) {
      return earningsComponents.fold(0.0, (sum, item) {
        final amt = item['amount'];
        final val = (amt is num) ? amt.toDouble() : (double.tryParse(amt?.toString() ?? '') ?? 0.0);
        return sum + val;
      });
    }
    return basicSalary + hra + specialAllowance;
  }

  /// Sum of deductions components
  double get calculatedDeductions {
    if (deductionsComponents.isNotEmpty) {
      return deductionsComponents.fold(0.0, (sum, item) {
        final amt = item['amount'];
        final val = (amt is num) ? amt.toDouble() : (double.tryParse(amt?.toString() ?? '') ?? 0.0);
        return sum + val;
      });
    }
    return pfDeduction + profTaxDeduction + incomeTaxDeduction;
  }

  /// Net pay calculated from components
  double get calculatedNetPay => calculatedGross - calculatedDeductions;

  /// Validates: SUM(earnings) == gross, SUM(deductions) == deductions, gross - deductions == netPay
  bool validateCalculations() {
    final grossNum = double.tryParse(grossEarnings.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final dedNum = double.tryParse(deductions.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final netNum = double.tryParse(netPay.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

    // Component level validation if components are populated
    if (calculatedGross > 0 && (calculatedGross - grossNum).abs() > 1.0) {
      return false;
    }
    if (calculatedDeductions > 0 && (calculatedDeductions - dedNum).abs() > 1.0) {
      return false;
    }

    if (grossNum > 0 && dedNum >= 0 && netNum > 0) {
      final expectedNet = grossNum - dedNum;
      if ((expectedNet - netNum).abs() > 1.0) {
        return false;
      }
    }
    return true;
  }
}


// --- EXPENSE CLAIM MODEL ---
enum ExpenseStatus { pending, approved, rejected, reimbursed, draft }

class ExpenseClaimModel {
  final String id;
  final String title;
  final String category;
  final double amount;
  final double? approvedAmount;
  final DateTime date;
  final String description;
  final ExpenseStatus status;
  final String? attachmentName;
  final String? receiptUrl;
  final String? claimNumber;
  final String? approverName;
  final String? approverComment;
  final String? rejectionReason;
  final String? reimbursementReference;

  const ExpenseClaimModel({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    this.approvedAmount,
    required this.date,
    required this.description,
    required this.status,
    this.attachmentName,
    this.receiptUrl,
    this.claimNumber,
    this.approverName,
    this.approverComment,
    this.rejectionReason,
    this.reimbursementReference,
  });

  factory ExpenseClaimModel.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? '').toString().toUpperCase();
    ExpenseStatus st = ExpenseStatus.pending;
    if (statusStr == 'APPROVED') st = ExpenseStatus.approved;
    if (statusStr == 'REJECTED') st = ExpenseStatus.rejected;
    if (statusStr == 'REIMBURSED') st = ExpenseStatus.reimbursed;
    if (statusStr == 'DRAFT') st = ExpenseStatus.draft;

    return ExpenseClaimModel(
      id: json['id']?.toString() ?? '',
      claimNumber: json['claim_number']?.toString() ?? 'CLM-001',
      title: json['description']?.toString() ?? json['title']?.toString() ?? 'Expense Reimbursement',
      category: json['category']?.toString() ?? 'General',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      approvedAmount: (json['approved_amount'] as num?)?.toDouble(),
      date: DateTime.tryParse(json['expense_date']?.toString() ?? json['submitted_at']?.toString() ?? '') ?? DateTime.now(),
      description: json['description']?.toString() ?? '',
      status: st,
      receiptUrl: json['receipt_url']?.toString(),
      attachmentName: json['receipt_filename']?.toString(),
      approverName: json['approver_name']?.toString(),
      approverComment: json['approver_comment']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      reimbursementReference: json['reimbursement_reference']?.toString(),
    );
  }
}

// --- EMPLOYEE TASK MODELS ---
enum TaskPriority { low, medium, high, urgent }

enum TaskStatus { pending, inProgress, completed, blocked, cancelled }

class TaskModel {
  final String id;
  final String title;
  final String description;
  final String? assignedToId;
  final String? assignedToName;
  final String? assignedById;
  final String? assignedByName;
  final DateTime? assignedDate;
  final DateTime? dueDate;
  final DateTime? completedDate;
  final TaskPriority priority;
  final TaskStatus status;
  final int progressPercent;

  const TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    this.assignedToId,
    this.assignedToName,
    this.assignedById,
    this.assignedByName,
    this.assignedDate,
    this.dueDate,
    this.completedDate,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    this.progressPercent = 0,
  });
}

// --- DIGITAL LETTER MODEL ---
class DigitalLetterModel {
  final String id;
  final String title;
  final String category;
  final DateTime issueDate;
  final DateTime? effectiveDate;
  final String documentRef;
  final String? documentUrl;
  final String documentType;
  final String? fileName;
  final String? referenceNumber;
  final String? contentBody;
  final bool requiresSignature;
  final String status;
  final String? signatureData;
  final DateTime? signedAt;
  final String? issuedByName;

  const DigitalLetterModel({
    required this.id,
    required this.title,
    required this.category,
    required this.issueDate,
    this.effectiveDate,
    required this.documentRef,
    this.documentUrl,
    this.documentType = "pdf",
    this.fileName,
    this.referenceNumber,
    this.contentBody,
    this.requiresSignature = false,
    this.status = 'PUBLISHED',
    this.signatureData,
    this.signedAt,
    this.issuedByName,
  });

  bool get isSigned => status.toUpperCase() == 'SIGNED' || status.toUpperCase() == 'ACKNOWLEDGED';

  factory DigitalLetterModel.fromJson(Map<String, dynamic> json) {
    return DigitalLetterModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Official Letter',
      category: json['letter_type']?.toString() ?? json['category']?.toString() ?? 'HR Letter',
      issueDate: DateTime.tryParse(json['issued_date']?.toString() ?? json['created_at']?.toString() ?? '') ?? DateTime.now(),
      effectiveDate: DateTime.tryParse(json['effective_date']?.toString() ?? ''),
      documentRef: json['letter_number']?.toString() ?? json['document_ref']?.toString() ?? 'LET-001',
      documentUrl: json['document_url']?.toString() ?? json['file_url']?.toString(),
      documentType: (json['document_url']?.toString() ?? '').toLowerCase().endsWith('.png') ||
              (json['document_url']?.toString() ?? '').toLowerCase().endsWith('.jpg')
          ? 'image'
          : 'pdf',
      fileName: json['title']?.toString(),
      referenceNumber: json['letter_number']?.toString(),
      contentBody: json['description']?.toString(),
      requiresSignature: json['requires_signature'] == true,
      status: (json['status']?.toString() ?? 'PUBLISHED').toUpperCase(),
      signatureData: json['signature_data']?.toString(),
      signedAt: DateTime.tryParse(json['signed_at']?.toString() ?? ''),
      issuedByName: json['issued_by_name']?.toString() ?? 'HR Department',
    );
  }
}

// --- DOCUMENT MODEL ---
enum DocumentCategory { company, personal }

class DocumentModel {
  final String id;
  final String name;
  final DocumentCategory category;
  final String fileType;
  final String fileSize;
  final DateTime uploadedAt;
  final String companyId;
  final String? employeeId;
  final String? documentType;
  final String? fileExtension;
  final String? storagePath;
  final String? uploadedBy;
  final bool isPrivate;
  final String? fileUrl;
  final String? verificationStatus; // VERIFIED | SUBMITTED | REJECTED | PENDING
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? rejectionReason;
  final String? requestId;

  const DocumentModel({
    required this.id,
    required this.name,
    required this.category,
    required this.fileType,
    required this.fileSize,
    required this.uploadedAt,
    this.companyId = "",
    this.employeeId,
    this.documentType,
    this.fileExtension,
    this.storagePath,
    this.uploadedBy,
    this.isPrivate = false,
    this.fileUrl,
    this.verificationStatus,
    this.verifiedBy,
    this.verifiedAt,
    this.rejectionReason,
    this.requestId,
  });

  bool get isVerified {
    final s = (verificationStatus ?? '').toUpperCase().trim();
    return s == 'VERIFIED' || s == 'APPROVED' || s == 'ACCEPTED' || s == 'VALIDATED';
  }

  bool get isRejected {
    final s = (verificationStatus ?? '').toUpperCase().trim();
    return s == 'REJECTED' || s == 'REUPLOAD_REQUIRED' || s == 'DECLINED' || s == 'FAILED';
  }

  bool get isPending {
    final s = (verificationStatus ?? '').toUpperCase().trim();
    return s == 'SUBMITTED' || s == 'PENDING' || s == 'UNDER_REVIEW' || s == 'REVIEW' || s == 'IN_REVIEW' || s.isEmpty;
  }
}


// --- PERFORMANCE GOAL MODEL ---
class PerformanceGoalModel {
  final String id;
  final String title;
  final String category;
  final double progressPercent;
  final String targetDate;
  final String status; // On Track | Needs Attention | Achieved

  const PerformanceGoalModel({
    required this.id,
    required this.title,
    required this.category,
    required this.progressPercent,
    required this.targetDate,
    required this.status,
  });

  factory PerformanceGoalModel.fromJson(Map<String, dynamic> json) {
    final rawProgress = json['progress_percent'] ?? json['progress'] ?? 0.0;
    final progress = (rawProgress is num) ? rawProgress.toDouble() : (double.tryParse(rawProgress.toString()) ?? 0.0);
    final normalizedProgress = progress > 1.0 ? (progress / 100.0) : progress;

    return PerformanceGoalModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['goal_name']?.toString() ?? 'Goal',
      category: json['category']?.toString() ?? 'General',
      progressPercent: normalizedProgress.clamp(0.0, 1.0),
      targetDate: json['target_date']?.toString() ?? json['due_date']?.toString() ?? 'Q4',
      status: json['status']?.toString() ?? 'In Progress',
    );
  }
}

// --- ANNOUNCEMENT / COMMUNICATION MODEL ---
class AnnouncementModel {
  final String id;
  final String title;
  final String content;
  final String author;
  final DateTime publishedAt;
  final bool isImportant;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    required this.publishedAt,
    this.isImportant = false,
  });
}

// --- COMPLAINT / GRIEVANCE MODEL ---
enum ComplaintStatus { submitted, underReview, inProgress, resolved, closed }
enum ComplaintDestinationType { normalApprover, poshCommittee, companyAdmin }

class ComplaintModel {
  final String id;
  final String subject;
  final String category;
  final String description;
  final DateTime createdAt;
  final ComplaintStatus status;
  final String? response;
  final String? companyId;
  final ComplaintDestinationType? destinationType;
  final String? destinationId;
  final String? destinationName;

  const ComplaintModel({
    required this.id,
    required this.subject,
    required this.category,
    required this.description,
    required this.createdAt,
    required this.status,
    this.response,
    this.companyId,
    this.destinationType,
    this.destinationId,
    this.destinationName,
  });
}


// --- NOTIFICATION & ACTIVITY FEED MODELS ---
class NotificationItemModel {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final IconData icon;
  final String? notificationType;
  final String? entityType;
  final String? entityId;
  final DateTime? dueDate;
  final String? status;
  final String? rejectionReason;

  const NotificationItemModel({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    required this.icon,
    this.notificationType,
    this.entityType,
    this.entityId,
    this.dueDate,
    this.status,
    this.rejectionReason,
  });
}

class DocumentRequirementModel {
  final String id;
  final String employeeId;
  final String documentType;
  final String title;
  final String description;
  final bool isMandatory;
  final DateTime? dueDate;
  final String status;
  final String? rejectionReason;
  final String? requestedBy;
  final String? documentId;
  final DateTime createdAt;

  const DocumentRequirementModel({
    required this.id,
    required this.employeeId,
    required this.documentType,
    required this.title,
    this.description = '',
    this.isMandatory = true,
    this.dueDate,
    this.status = 'REQUIRED',
    this.rejectionReason,
    this.requestedBy,
    this.documentId,
    required this.createdAt,
  });

  bool get isPending => status == 'REQUIRED' || status == 'PENDING' || status == 'REUPLOAD_REQUIRED';
  bool get isSubmitted => status == 'SUBMITTED' || status == 'UNDER_REVIEW';
  bool get isVerified => status == 'VERIFIED' || status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';
}

class ActivityItemModel {
  final String id;
  final String title;
  final String subtitle;
  final String timeAgo;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String? entityType;
  final String? entityId;
  final String? status;
  final String? badge;

  const ActivityItemModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timeAgo,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    this.entityType,
    this.entityId,
    this.status,
    this.badge,
  });
}

class AttendanceExceptionModel {
  final String id;
  final String exceptionType;
  final String severity;
  final String status;
  final String workDate;
  final String title;
  final String description;
  final String suggestedAction;
  final String? actualIn;
  final String? actualOut;

  const AttendanceExceptionModel({
    required this.id,
    required this.exceptionType,
    required this.severity,
    required this.status,
    required this.workDate,
    required this.title,
    required this.description,
    required this.suggestedAction,
    this.actualIn,
    this.actualOut,
  });

  factory AttendanceExceptionModel.fromJson(Map<String, dynamic> json) {
    return AttendanceExceptionModel(
      id: json['id']?.toString() ?? '',
      exceptionType: json['exception_type']?.toString() ?? 'EXCEPTION',
      severity: json['severity']?.toString() ?? 'MEDIUM',
      status: json['status']?.toString() ?? 'OPEN',
      workDate: json['work_date']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Attendance Issue',
      description: json['description']?.toString() ?? '',
      suggestedAction: json['suggested_action']?.toString() ?? 'Regularize',
      actualIn: json['actual_in']?.toString(),
      actualOut: json['actual_out']?.toString(),
    );
  }
}

// --- EMPLOYEE SERVICE CONFIGURATION MODEL ---
class EmployeeServiceConfigModel {
  final String id;
  final String serviceId;
  final String serviceName;
  final String subtitle;
  final String iconName;
  final bool isEnabled;
  final bool isVisibleToEmployee;
  final String badgeType;
  final int sortOrder;

  const EmployeeServiceConfigModel({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.subtitle,
    required this.iconName,
    this.isEnabled = true,
    this.isVisibleToEmployee = true,
    this.badgeType = 'NONE',
    this.sortOrder = 0,
  });

  factory EmployeeServiceConfigModel.fromJson(Map<String, dynamic> json) {
    return EmployeeServiceConfigModel(
      id: json['id']?.toString() ?? '',
      serviceId: json['service_id']?.toString() ?? '',
      serviceName: json['service_name']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      iconName: json['icon_name']?.toString() ?? 'square_grid_2x2',
      isEnabled: json['is_enabled'] as bool? ?? true,
      isVisibleToEmployee: json['is_visible_to_employee'] as bool? ?? true,
      badgeType: json['badge_type']?.toString() ?? 'NONE',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}



