import 'package:flutter/material.dart';

enum BreakCategory {
  lunch,
  tea,
  coffee,
  personal,
  rest,
  other;

  /// Centralized default display order:
  /// 1. Start Tea, 2. Start Lunch, 3. Start Coffee,
  /// 4. Start Personal Break, 5. Start Rest, 6. Start Other Break.
  int get defaultDisplayOrder {
    switch (this) {
      case BreakCategory.tea:
        return 1;
      case BreakCategory.lunch:
        return 2;
      case BreakCategory.coffee:
        return 3;
      case BreakCategory.personal:
        return 4;
      case BreakCategory.rest:
        return 5;
      case BreakCategory.other:
        return 6;
    }
  }

  String get startActionLabel {
    switch (this) {
      case BreakCategory.tea:
        return 'Start Tea';
      case BreakCategory.lunch:
        return 'Start Lunch';
      case BreakCategory.coffee:
        return 'Start Coffee';
      case BreakCategory.personal:
        return 'Start Personal Break';
      case BreakCategory.rest:
        return 'Start Rest';
      case BreakCategory.other:
        return 'Start Other Break';
    }
  }

  /// Centralized, distinct icon mapping per break category.
  IconData get icon {
    switch (this) {
      case BreakCategory.tea:
        return Icons.emoji_food_beverage_rounded;
      case BreakCategory.lunch:
        return Icons.restaurant_rounded;
      case BreakCategory.coffee:
        return Icons.coffee_rounded;
      case BreakCategory.personal:
        return Icons.pause_circle_outline_rounded;
      case BreakCategory.rest:
        return Icons.self_improvement_rounded;
      case BreakCategory.other:
        return Icons.more_horiz_rounded;
    }
  }

  /// Centralized theme color per break category.
  Color get themeColor {
    switch (this) {
      case BreakCategory.tea:
        return const Color(0xFF0F766E); // Teal
      case BreakCategory.lunch:
        return const Color(0xFFD97706); // Orange
      case BreakCategory.coffee:
        return const Color(0xFF78350F); // Warm brown (distinct from Tea)
      case BreakCategory.personal:
        return const Color(0xFFEA580C); // Neutral orange
      case BreakCategory.rest:
        return const Color(0xFF0D9488); // Soft teal
      case BreakCategory.other:
        return const Color(0xFF475569); // Neutral slate grey
    }
  }

  String get code {
    switch (this) {
      case BreakCategory.lunch:
        return 'LUNCH';
      case BreakCategory.tea:
        return 'TEA';
      case BreakCategory.coffee:
        return 'COFFEE';
      case BreakCategory.personal:
        return 'PERSONAL';
      case BreakCategory.rest:
        return 'REST';
      case BreakCategory.other:
        return 'OTHER';
    }
  }

  String get label {
    switch (this) {
      case BreakCategory.lunch:
        return 'Lunch Break';
      case BreakCategory.tea:
        return 'Tea Break';
      case BreakCategory.coffee:
        return 'Coffee Break';
      case BreakCategory.personal:
        return 'Personal Break';
      case BreakCategory.rest:
        return 'Rest Break';
      case BreakCategory.other:
        return 'Other Break';
    }
  }

  static BreakCategory fromCode(String? raw) {
    final norm = (raw ?? '').trim().toUpperCase();
    switch (norm) {
      case 'LUNCH':
      case 'MEAL':
        return BreakCategory.lunch;
      case 'TEA':
        return BreakCategory.tea;
      case 'COFFEE':
        return BreakCategory.coffee;
      case 'PERSONAL':
        return BreakCategory.personal;
      case 'REST':
        return BreakCategory.rest;
      default:
        return BreakCategory.other;
    }
  }
}

enum EmployeeWorkState {
  notCheckedIn,
  working,
  onBreak,
  checkedOut;

  static EmployeeWorkState fromString(String? raw) {
    final norm = (raw ?? '').trim().toUpperCase();
    switch (norm) {
      case 'WORKING':
        return EmployeeWorkState.working;
      case 'ON_BREAK':
        return EmployeeWorkState.onBreak;
      case 'CHECKED_OUT':
        return EmployeeWorkState.checkedOut;
      default:
        return EmployeeWorkState.notCheckedIn;
    }
  }
}

class BreakCategoryConfig {
  final BreakCategory category;
  final String label;
  final bool paid;
  final int maxMinutesPerBreak;
  final int maxPerDay;
  final bool enabled;
  final int displayOrder;

  const BreakCategoryConfig({
    required this.category,
    required this.label,
    required this.paid,
    required this.maxMinutesPerBreak,
    required this.maxPerDay,
    required this.enabled,
    int? displayOrder,
  }) : displayOrder = displayOrder ?? 99;

  int get effectiveDisplayOrder =>
      displayOrder == 99 ? category.defaultDisplayOrder : displayOrder;

  factory BreakCategoryConfig.fromMap(Map<String, dynamic> map) {
    final cat = BreakCategory.fromCode(map['code']?.toString());
    return BreakCategoryConfig(
      category: cat,
      label: map['label']?.toString().isNotEmpty == true
          ? map['label'].toString()
          : cat.label,
      paid: (map['is_paid'] ?? map['paid']) == true,
      maxMinutesPerBreak:
          ((map['max_duration_minutes'] ?? map['max_minutes_per_break']) as num?)
                  ?.toInt() ??
              30,
      maxPerDay:
          ((map['max_occurrences'] ?? map['max_per_day']) as num?)?.toInt() ?? 2,
      enabled: map['enabled'] != false,
      displayOrder: (map['display_order'] as num?)?.toInt() ?? cat.defaultDisplayOrder,
    );
  }
}

class BreakPolicySummary {
  final String id;
  final String name;
  final int version;
  final int paidBreakAllowanceMinutes;
  final int maxUnpaidBreakMinutes;
  final int autoDeductMinutes;
  final int autoDeductAfterMinutes;
  final bool mandatoryLunchBreak;
  final List<BreakCategoryConfig> categories;

  const BreakPolicySummary({
    this.id = 'default',
    this.name = 'Standard Break Policy',
    this.version = 1,
    this.paidBreakAllowanceMinutes = 15,
    this.maxUnpaidBreakMinutes = 60,
    this.autoDeductMinutes = 30,
    this.autoDeductAfterMinutes = 300,
    this.mandatoryLunchBreak = false,
    this.categories = const [
      BreakCategoryConfig(
        category: BreakCategory.tea,
        label: 'Tea Break',
        paid: true,
        maxMinutesPerBreak: 15,
        maxPerDay: 2,
        enabled: true,
        displayOrder: 1,
      ),
      BreakCategoryConfig(
        category: BreakCategory.lunch,
        label: 'Lunch Break',
        paid: false,
        maxMinutesPerBreak: 60,
        maxPerDay: 1,
        enabled: true,
        displayOrder: 2,
      ),
      BreakCategoryConfig(
        category: BreakCategory.coffee,
        label: 'Coffee Break',
        paid: true,
        maxMinutesPerBreak: 15,
        maxPerDay: 1,
        enabled: true,
        displayOrder: 3,
      ),
      BreakCategoryConfig(
        category: BreakCategory.personal,
        label: 'Personal Break',
        paid: false,
        maxMinutesPerBreak: 20,
        maxPerDay: 2,
        enabled: true,
        displayOrder: 4,
      ),
      BreakCategoryConfig(
        category: BreakCategory.other,
        label: 'Other Break',
        paid: false,
        maxMinutesPerBreak: 30,
        maxPerDay: 2,
        enabled: true,
        displayOrder: 6,
      ),
    ],
  });

  factory BreakPolicySummary.fromMap(Map<String, dynamic> map) {
    final rawCats = map['categories'];
    final parsedCats = <BreakCategoryConfig>[];
    if (rawCats is List) {
      for (final item in rawCats) {
        if (item is Map<String, dynamic>) {
          parsedCats.add(BreakCategoryConfig.fromMap(item));
        } else if (item is Map) {
          parsedCats.add(
            BreakCategoryConfig.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final autoHours = (map['automatic_break_after_hours'] as num?)?.toDouble();
    final autoAfterMins = (map['auto_deduct_after_minutes'] as num?)?.toInt() ??
        (autoHours != null ? (autoHours * 60).round() : 300);
    parsedCats.sort(
      (a, b) => a.effectiveDisplayOrder.compareTo(b.effectiveDisplayOrder),
    );
    return BreakPolicySummary(
      id: map['id']?.toString() ?? 'default',
      name: (map['policy_name'] ?? map['name'])?.toString() ??
          'Standard Break Policy',
      version: (map['version'] as num?)?.toInt() ?? 1,
      paidBreakAllowanceMinutes:
          (map['paid_break_allowance_minutes'] as num?)?.toInt() ?? 15,
      maxUnpaidBreakMinutes:
          (map['max_unpaid_break_minutes'] as num?)?.toInt() ?? 60,
      autoDeductMinutes:
          ((map['automatic_break_minutes'] ?? map['auto_deduct_minutes'])
                      as num?)
                  ?.toInt() ??
              30,
      autoDeductAfterMinutes: autoAfterMins,
      mandatoryLunchBreak:
          (map['mandatory_breaks'] ?? map['mandatory_lunch_break']) == true,
      categories: parsedCats.isNotEmpty
          ? parsedCats
          : const BreakPolicySummary().categories,
    );
  }
}

class BreakEventModel {
  final String id;
  final BreakCategory category;
  final bool isPaid;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? deviceStartedAt;
  final DateTime? deviceEndedAt;
  final int? durationMinutes;
  final String status;
  final String source;
  final String? endSource;
  final String? approvalStatus;
  final String? correctionReferenceId;
  final String? notes;
  final bool isExcess;

  const BreakEventModel({
    required this.id,
    required this.category,
    required this.isPaid,
    required this.startedAt,
    this.endedAt,
    this.deviceStartedAt,
    this.deviceEndedAt,
    this.durationMinutes,
    required this.status,
    this.source = 'MOBILE',
    this.endSource,
    this.approvalStatus,
    this.correctionReferenceId,
    this.notes,
    this.isExcess = false,
  });

  bool get isActive => status == 'ACTIVE' && endedAt == null;

  int elapsedMinutesAt(DateTime now) {
    if (durationMinutes != null && !isActive && durationMinutes! > 0) {
      return durationMinutes!;
    }
    final end = endedAt ?? now;
    final mins = end.difference(startedAt).inMinutes;
    return mins < 0 ? 0 : mins;
  }

  factory BreakEventModel.fromMap(Map<String, dynamic> map) {
    return BreakEventModel(
      id: map['id']?.toString() ?? '',
      category: BreakCategory.fromCode(map['break_category']?.toString()),
      isPaid: map['is_paid'] == true,
      startedAt:
          DateTime.tryParse(map['started_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'].toString())?.toLocal()
          : null,
      deviceStartedAt: map['device_started_at'] != null
          ? DateTime.tryParse(map['device_started_at'].toString())?.toLocal()
          : null,
      deviceEndedAt: map['device_ended_at'] != null
          ? DateTime.tryParse(map['device_ended_at'].toString())?.toLocal()
          : null,
      durationMinutes: (map['duration_minutes'] as num?)?.toInt(),
      status: map['status']?.toString() ?? 'COMPLETED',
      source: (map['start_source'] ?? map['source'])?.toString() ?? 'MOBILE',
      endSource: map['end_source']?.toString(),
      approvalStatus: map['approval_status']?.toString(),
      correctionReferenceId: map['correction_reference_id']?.toString(),
      notes: map['notes']?.toString(),
      isExcess: (map['exceeds_limit'] ?? map['is_excess']) == true,
    );
  }
}

class BreakExceptionModel {
  final String id;
  final String exceptionType;
  final String severity;
  final String description;
  final String resolutionStatus;
  final DateTime createdAt;

  const BreakExceptionModel({
    required this.id,
    required this.exceptionType,
    required this.severity,
    required this.description,
    required this.resolutionStatus,
    required this.createdAt,
  });

  factory BreakExceptionModel.fromMap(Map<String, dynamic> map) {
    return BreakExceptionModel(
      id: map['id']?.toString() ?? '',
      exceptionType: map['exception_type']?.toString() ?? 'EXCEPTION',
      severity: map['severity']?.toString() ?? 'MEDIUM',
      description:
          (map['description'] ?? map['details'])?.toString() ?? 'Policy alert',
      resolutionStatus:
          (map['resolution_status'] ?? map['status'])?.toString() ?? 'OPEN',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

class BreakSummaryState {
  final EmployeeWorkState workState;
  final BreakEventModel? activeBreak;
  final List<BreakEventModel> todayBreaks;
  final List<BreakExceptionModel> exceptions;
  final BreakPolicySummary policy;
  final int paidBreakMinutes;
  final int unpaidBreakMinutes;
  final int autoDeductedBreakMinutes;
  final int netPayableMinutes;
  final int approvedOtMinutes;

  const BreakSummaryState({
    this.workState = EmployeeWorkState.notCheckedIn,
    this.activeBreak,
    this.todayBreaks = const [],
    this.exceptions = const [],
    this.policy = const BreakPolicySummary(),
    this.paidBreakMinutes = 0,
    this.unpaidBreakMinutes = 0,
    this.autoDeductedBreakMinutes = 0,
    this.netPayableMinutes = 0,
    this.approvedOtMinutes = 0,
  });

  int get totalBreakMinutes => paidBreakMinutes + unpaidBreakMinutes;

  int get remainingPaidAllowanceMinutes {
    final rem = policy.paidBreakAllowanceMinutes - paidBreakMinutes;
    return rem > 0 ? rem : 0;
  }

  bool get isOnBreak =>
      workState == EmployeeWorkState.onBreak && activeBreak != null;
}

enum TimelineEntryType {
  checkIn,
  work,
  paidBreak,
  unpaidBreak,
  overtime,
  scheduledShiftEnd,
  checkOut,
  exception,
}

class TimelineEntry {
  final String id;
  final TimelineEntryType type;
  final String title;
  final String? subtitle;
  final DateTime startAt;
  final DateTime? endAt;
  final int? durationMinutes;
  final bool isCurrent;
  final bool isUpcoming;
  final bool? isPaid;
  final BreakEventModel? breakEvent;
  final BreakExceptionModel? exceptionEvent;

  const TimelineEntry({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    required this.startAt,
    this.endAt,
    this.durationMinutes,
    this.isCurrent = false,
    this.isUpcoming = false,
    this.isPaid,
    this.breakEvent,
    this.exceptionEvent,
  });
}

/// Builds a unified chronological attendance timeline from persisted events.
List<TimelineEntry> buildUnifiedAttendanceTimeline({
  required DateTime? checkInTime,
  required DateTime? checkOutTime,
  required BreakSummaryState summary,
  required DateTime now,
  DateTime? scheduledShiftEnd,
}) {
  if (checkInTime == null) return const [];

  final entries = <TimelineEntry>[];
  final sortedBreaks = List<BreakEventModel>.from(summary.todayBreaks)
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  entries.add(
    TimelineEntry(
      id: 'evt-checkin',
      type: TimelineEntryType.checkIn,
      title: 'CHECKED IN',
      subtitle: 'Attendance session started',
      startAt: checkInTime,
    ),
  );

  DateTime cursor = checkInTime;

  for (var i = 0; i < sortedBreaks.length; i++) {
    final brk = sortedBreaks[i];
    if (brk.startedAt.isAfter(cursor)) {
      final workMins = brk.startedAt.difference(cursor).inMinutes;
      if (workMins >= 0) {
        entries.add(
          TimelineEntry(
            id: 'work-seg-$i',
            type: TimelineEntryType.work,
            title: i == 0 ? 'WORKING' : 'WORK RESUMED',
            subtitle: 'Active work session',
            startAt: cursor,
            endAt: brk.startedAt,
            durationMinutes: workMins,
          ),
        );
      }
    }

    final brkEnd = brk.endedAt ?? (brk.isActive ? now : brk.startedAt);
    final brkMins = brk.elapsedMinutesAt(now);
    entries.add(
      TimelineEntry(
        id: 'brk-${brk.id}',
        type: brk.isPaid
            ? TimelineEntryType.paidBreak
            : TimelineEntryType.unpaidBreak,
        title: brk.isActive
            ? '${brk.category.label.toUpperCase()} IN PROGRESS'
            : brk.category.label.toUpperCase(),
        subtitle:
            '${brk.isPaid ? "PAID" : "UNPAID"}${brk.isExcess ? " · EXCEEDED LIMIT" : ""}',
        startAt: brk.startedAt,
        endAt: brk.isActive ? null : brkEnd,
        durationMinutes: brkMins,
        isCurrent: brk.isActive,
        isPaid: brk.isPaid,
        breakEvent: brk,
      ),
    );

    cursor = brkEnd;
  }

  final hasActiveBreak = sortedBreaks.any((b) => b.isActive);

  if (!hasActiveBreak) {
    final endCursor = checkOutTime ?? now;
    if (!endCursor.isBefore(cursor)) {
      final workMins = endCursor.difference(cursor).inMinutes;
      entries.add(
        TimelineEntry(
          id: 'work-tail',
          type: TimelineEntryType.work,
          title: checkOutTime == null ? 'WORKING NOW' : 'WORK SESSION',
          subtitle: checkOutTime == null
              ? 'Live active work interval'
              : 'Completed work interval',
          startAt: cursor,
          endAt: checkOutTime,
          durationMinutes: workMins,
          isCurrent: checkOutTime == null,
        ),
      );
    }
  }

  if (scheduledShiftEnd != null &&
      checkOutTime == null &&
      scheduledShiftEnd.isAfter(now)) {
    entries.add(
      TimelineEntry(
        id: 'sched-shift-end',
        type: TimelineEntryType.scheduledShiftEnd,
        title: 'SCHEDULED SHIFT END',
        subtitle: 'Expected end of shift',
        startAt: scheduledShiftEnd,
        isUpcoming: true,
      ),
    );
  }

  if (summary.approvedOtMinutes > 0 && checkOutTime != null) {
    final otStart =
        checkOutTime.subtract(Duration(minutes: summary.approvedOtMinutes));
    entries.add(
      TimelineEntry(
        id: 'approved-ot',
        type: TimelineEntryType.overtime,
        title: 'APPROVED OVERTIME',
        subtitle: 'Payroll-eligible OT',
        startAt: otStart.isBefore(checkInTime) ? checkInTime : otStart,
        endAt: checkOutTime,
        durationMinutes: summary.approvedOtMinutes,
      ),
    );
  }

  for (final ex in summary.exceptions) {
    entries.add(
      TimelineEntry(
        id: 'exc-${ex.id}',
        type: TimelineEntryType.exception,
        title: ex.exceptionType.replaceAll('_', ' '),
        subtitle: '${ex.description} · ${ex.resolutionStatus}',
        startAt: ex.createdAt,
        exceptionEvent: ex,
      ),
    );
  }

  if (checkOutTime != null) {
    entries.add(
      TimelineEntry(
        id: 'evt-checkout',
        type: TimelineEntryType.checkOut,
        title: 'CHECKED OUT',
        subtitle: 'Attendance completed',
        startAt: checkOutTime,
      ),
    );
  }

  return entries;
}
