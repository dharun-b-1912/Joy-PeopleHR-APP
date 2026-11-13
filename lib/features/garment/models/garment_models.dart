class GarmentUnitModel {
  final String id;
  final String unitCode;
  final String unitName;
  final String unitType;
  final String lineStage;
  final String? pieceRateModeOverride;
  final String? sharedSplitMethodOverride;
  final int dailyTargetQty;

  const GarmentUnitModel({
    required this.id,
    required this.unitCode,
    required this.unitName,
    required this.unitType,
    required this.lineStage,
    this.pieceRateModeOverride,
    this.sharedSplitMethodOverride,
    this.dailyTargetQty = 0,
  });

  factory GarmentUnitModel.fromJson(Map<String, dynamic> j) => GarmentUnitModel(
        id: j['id']?.toString() ?? '',
        unitCode: j['unit_code']?.toString() ?? '',
        unitName: j['unit_name']?.toString() ?? '',
        unitType: j['unit_type']?.toString() ?? 'LINE',
        lineStage: j['line_stage']?.toString() ?? 'STITCHING',
        pieceRateModeOverride: j['piece_rate_mode_override']?.toString(),
        sharedSplitMethodOverride: j['shared_split_method_override']?.toString(),
        dailyTargetQty: (j['daily_target_qty'] as num?)?.toInt() ?? 0,
      );
}

class GarmentWorkerModel {
  final String id;
  final String employeeId;
  final String displayName;
  final String employeeCode;
  final String workerCategory;
  final String skillGrade;
  final double skillWeightage;
  final String? primaryUnitId;
  final String? primaryTeamId;
  final String defaultWageMethod;
  final String defaultPaymentFrequency;

  const GarmentWorkerModel({
    required this.id,
    required this.employeeId,
    required this.displayName,
    required this.employeeCode,
    required this.workerCategory,
    required this.skillGrade,
    required this.skillWeightage,
    this.primaryUnitId,
    this.primaryTeamId,
    required this.defaultWageMethod,
    required this.defaultPaymentFrequency,
  });
}

class GarmentOperationModel {
  final String id;
  final String operationCode;
  final String operationName;
  final String departmentStage;
  final double defaultSmv;

  const GarmentOperationModel({
    required this.id,
    required this.operationCode,
    required this.operationName,
    required this.departmentStage,
    required this.defaultSmv,
  });

  factory GarmentOperationModel.fromJson(Map<String, dynamic> j) => GarmentOperationModel(
        id: j['id']?.toString() ?? '',
        operationCode: j['operation_code']?.toString() ?? '',
        operationName: j['operation_name']?.toString() ?? '',
        departmentStage: j['department_stage']?.toString() ?? 'STITCHING',
        defaultSmv: (j['default_smv'] as num?)?.toDouble() ?? 1.0,
      );
}

class GarmentStyleModel {
  final String id;
  final String styleCode;
  final String styleName;

  const GarmentStyleModel({required this.id, required this.styleCode, required this.styleName});

  factory GarmentStyleModel.fromJson(Map<String, dynamic> j) => GarmentStyleModel(
        id: j['id']?.toString() ?? '',
        styleCode: j['style_code']?.toString() ?? '',
        styleName: j['style_name']?.toString() ?? '',
      );
}

class GarmentOrderModel {
  final String id;
  final String orderNumber;
  final String styleId;
  final String? productionUnitId;
  final int targetQuantity;
  final int completedQuantity;
  final String status;

  const GarmentOrderModel({
    required this.id,
    required this.orderNumber,
    required this.styleId,
    this.productionUnitId,
    required this.targetQuantity,
    required this.completedQuantity,
    required this.status,
  });

  factory GarmentOrderModel.fromJson(Map<String, dynamic> j) => GarmentOrderModel(
        id: j['id']?.toString() ?? '',
        orderNumber: j['order_number']?.toString() ?? '',
        styleId: j['style_id']?.toString() ?? '',
        productionUnitId: j['production_unit_id']?.toString(),
        targetQuantity: (j['target_quantity'] as num?)?.toInt() ?? 0,
        completedQuantity: (j['completed_quantity'] as num?)?.toInt() ?? 0,
        status: j['status']?.toString() ?? 'IN_PROGRESS',
      );
}

class GarmentRateCardModel {
  final String id;
  final String operationId;
  final String? styleId;
  final String? orderId;
  final String? productionUnitId;
  final String? skillGrade;
  final double ratePerUnit;
  final double reworkRatePerUnit;
  final String effectiveFrom;

  const GarmentRateCardModel({
    required this.id,
    required this.operationId,
    this.styleId,
    this.orderId,
    this.productionUnitId,
    this.skillGrade,
    required this.ratePerUnit,
    required this.reworkRatePerUnit,
    required this.effectiveFrom,
  });

  factory GarmentRateCardModel.fromJson(Map<String, dynamic> j) => GarmentRateCardModel(
        id: j['id']?.toString() ?? '',
        operationId: j['operation_id']?.toString() ?? '',
        styleId: j['style_id']?.toString(),
        orderId: j['order_id']?.toString(),
        productionUnitId: j['production_unit_id']?.toString(),
        skillGrade: j['skill_grade']?.toString(),
        ratePerUnit: (j['rate_per_unit'] as num?)?.toDouble() ?? 0.0,
        reworkRatePerUnit: (j['rework_rate_per_unit'] as num?)?.toDouble() ?? 0.0,
        effectiveFrom: j['effective_from']?.toString() ?? '',
      );
}

class GarmentProductionEntryModel {
  final String id;
  final String workDate;
  final String? employeeId;
  final String operationId;
  final String allocationMode;
  final int producedQty;
  final int acceptedQty;
  final int rejectedQty;
  final int reworkQty;
  final double computedPieceAmount;
  final String qcStatus;
  final String approvalStatus;

  const GarmentProductionEntryModel({
    required this.id,
    required this.workDate,
    this.employeeId,
    required this.operationId,
    required this.allocationMode,
    required this.producedQty,
    required this.acceptedQty,
    required this.rejectedQty,
    required this.reworkQty,
    required this.computedPieceAmount,
    required this.qcStatus,
    required this.approvalStatus,
  });

  factory GarmentProductionEntryModel.fromJson(Map<String, dynamic> j) => GarmentProductionEntryModel(
        id: j['id']?.toString() ?? '',
        workDate: j['work_date']?.toString() ?? '',
        employeeId: j['employee_id']?.toString(),
        operationId: j['operation_id']?.toString() ?? '',
        allocationMode: j['allocation_mode']?.toString() ?? 'INDIVIDUAL',
        producedQty: (j['produced_qty'] as num?)?.toInt() ?? 0,
        acceptedQty: (j['accepted_qty'] as num?)?.toInt() ?? 0,
        rejectedQty: (j['rejected_qty'] as num?)?.toInt() ?? 0,
        reworkQty: (j['rework_qty'] as num?)?.toInt() ?? 0,
        computedPieceAmount: (j['computed_piece_amount'] as num?)?.toDouble() ?? 0.0,
        qcStatus: j['qc_status']?.toString() ?? 'PENDING',
        approvalStatus: j['approval_status']?.toString() ?? 'SUBMITTED',
      );
}

class GarmentPayrollLineModel {
  final String id;
  final String wageMethodSnapshot;
  final double payableDays;
  final double workedHours;
  final double overtimeHours;
  final int acceptedQty;
  final int rejectedQty;
  final int reworkQty;
  final double grossEarnings;
  final double totalDeductions;
  final double netPayable;
  final String disbursementStatus;
  final String createdAt;

  const GarmentPayrollLineModel({
    required this.id,
    required this.wageMethodSnapshot,
    required this.payableDays,
    required this.workedHours,
    required this.overtimeHours,
    required this.acceptedQty,
    required this.rejectedQty,
    required this.reworkQty,
    required this.grossEarnings,
    required this.totalDeductions,
    required this.netPayable,
    required this.disbursementStatus,
    required this.createdAt,
  });

  factory GarmentPayrollLineModel.fromJson(Map<String, dynamic> j) => GarmentPayrollLineModel(
        id: j['id']?.toString() ?? '',
        wageMethodSnapshot: j['wage_method_snapshot']?.toString() ?? 'PIECE_RATE',
        payableDays: (j['payable_days'] as num?)?.toDouble() ?? 0.0,
        workedHours: (j['worked_hours'] as num?)?.toDouble() ?? 0.0,
        overtimeHours: (j['overtime_hours'] as num?)?.toDouble() ?? 0.0,
        acceptedQty: (j['accepted_qty'] as num?)?.toInt() ?? 0,
        rejectedQty: (j['rejected_qty'] as num?)?.toInt() ?? 0,
        reworkQty: (j['rework_qty'] as num?)?.toInt() ?? 0,
        grossEarnings: (j['gross_earnings'] as num?)?.toDouble() ?? 0.0,
        totalDeductions: (j['total_deductions'] as num?)?.toDouble() ?? 0.0,
        netPayable: (j['net_payable'] as num?)?.toDouble() ?? 0.0,
        disbursementStatus: j['disbursement_status']?.toString() ?? 'PENDING',
        createdAt: j['created_at']?.toString() ?? '',
      );
}

