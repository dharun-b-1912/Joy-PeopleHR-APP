import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/break_models.dart';

void main() {
  group('BreakModels & State Logic', () {
    test('BreakCategory maps codes and labels accurately', () {
      expect(BreakCategory.fromCode('LUNCH'), BreakCategory.lunch);
      expect(BreakCategory.fromCode('MEAL'), BreakCategory.lunch);
      expect(BreakCategory.fromCode('TEA'), BreakCategory.tea);
      expect(BreakCategory.fromCode('COFFEE'), BreakCategory.coffee);
      expect(BreakCategory.fromCode('PERSONAL'), BreakCategory.personal);
      expect(BreakCategory.fromCode('REST'), BreakCategory.rest);
      expect(BreakCategory.fromCode('UNKNOWN'), BreakCategory.other);
      expect(BreakCategory.lunch.code, 'LUNCH');
      expect(BreakCategory.tea.label, 'Tea Break');
    });

    test('BreakEventModel computes live elapsed minutes when ACTIVE', () {
      final start = DateTime(2026, 11, 12, 13, 0);
      final now = DateTime(2026, 11, 12, 13, 27);
      final ev = BreakEventModel(
        id: 'brk-1',
        category: BreakCategory.lunch,
        isPaid: false,
        startedAt: start,
        status: 'ACTIVE',
      );
      expect(ev.isActive, true);
      expect(ev.elapsedMinutesAt(now), 27);
    });

    test('BreakSummaryState computes remaining paid allowance accurately', () {
      const policy = BreakPolicySummary(paidBreakAllowanceMinutes: 15);
      const summary = BreakSummaryState(
        workState: EmployeeWorkState.working,
        policy: policy,
        paidBreakMinutes: 10,
        unpaidBreakMinutes: 30,
      );
      expect(summary.totalBreakMinutes, 40);
      expect(summary.remainingPaidAllowanceMinutes, 5);
      expect(summary.isOnBreak, false);
    });

    test('BreakPolicySummary parses categories from Supabase JSONB map', () {
      final policy = BreakPolicySummary.fromMap({
        'id': 'pol-uuid',
        'name': 'Plant Policy',
        'version': 2,
        'paid_break_allowance_minutes': 20,
        'max_unpaid_break_minutes': 60,
        'categories': [
          {
            'code': 'LUNCH',
            'label': 'Meal Break',
            'paid': false,
            'max_minutes_per_break': 45,
            'max_per_day': 1,
            'enabled': true,
          },
          {
            'code': 'TEA',
            'label': 'Tea Break',
            'paid': true,
            'max_minutes_per_break': 20,
            'max_per_day': 2,
            'enabled': true,
          },
        ],
      });
      expect(policy.name, 'Plant Policy');
      expect(policy.version, 2);
      expect(policy.paidBreakAllowanceMinutes, 20);
      expect(policy.categories.length, 2);
      expect(policy.categories.first.category, BreakCategory.tea);
      expect(policy.categories[1].category, BreakCategory.lunch);
      expect(policy.categories[1].label, 'Meal Break');
    });
  });

  group('Unified Attendance Timeline Builder', () {
    test('TEST A: Check In -> Work -> Lunch -> Work Resumed -> Check Out', () {
      final checkIn = DateTime(2026, 11, 12, 9, 0);
      final lunchStart = DateTime(2026, 11, 12, 13, 0);
      final lunchEnd = DateTime(2026, 11, 12, 13, 45);
      final checkOut = DateTime(2026, 11, 12, 18, 0);

      final summary = BreakSummaryState(
        workState: EmployeeWorkState.checkedOut,
        policy: const BreakPolicySummary(),
        todayBreaks: [
          BreakEventModel(
            id: 'brk-lunch',
            category: BreakCategory.lunch,
            isPaid: false,
            startedAt: lunchStart,
            endedAt: lunchEnd,
            durationMinutes: 45,
            status: 'COMPLETED',
          ),
        ],
      );

      final entries = buildUnifiedAttendanceTimeline(
        checkInTime: checkIn,
        checkOutTime: checkOut,
        summary: summary,
        now: checkOut,
      );

      expect(
        entries.map((e) => e.type).toList(),
        [
          TimelineEntryType.checkIn,
          TimelineEntryType.work,
          TimelineEntryType.unpaidBreak,
          TimelineEntryType.work,
          TimelineEntryType.checkOut,
        ],
      );
      expect(entries[1].durationMinutes, 240); // 09:00 -> 13:00
      expect(entries[2].durationMinutes, 45);
      expect(entries[3].durationMinutes, 255); // 13:45 -> 18:00
    });

    test('TEST B: Tea (Paid) and Coffee (Paid) breaks appear in order', () {
      final checkIn = DateTime(2026, 11, 12, 9, 0);
      final now = DateTime(2026, 11, 12, 17, 0);

      final summary = BreakSummaryState(
        workState: EmployeeWorkState.working,
        policy: const BreakPolicySummary(),
        todayBreaks: [
          BreakEventModel(
            id: 'brk-tea',
            category: BreakCategory.tea,
            isPaid: true,
            startedAt: DateTime(2026, 11, 12, 11, 0),
            endedAt: DateTime(2026, 11, 12, 11, 15),
            durationMinutes: 15,
            status: 'COMPLETED',
          ),
          BreakEventModel(
            id: 'brk-coffee',
            category: BreakCategory.coffee,
            isPaid: true,
            startedAt: DateTime(2026, 11, 12, 16, 0),
            endedAt: DateTime(2026, 11, 12, 16, 10),
            durationMinutes: 10,
            status: 'COMPLETED',
          ),
        ],
      );

      final entries = buildUnifiedAttendanceTimeline(
        checkInTime: checkIn,
        checkOutTime: null,
        summary: summary,
        now: now,
      );

      final paidBreaks =
          entries.where((e) => e.type == TimelineEntryType.paidBreak).toList();
      expect(paidBreaks.length, 2);
      expect(paidBreaks[0].title, 'TEA BREAK');
      expect(paidBreaks[1].title, 'COFFEE BREAK');
      expect(entries.last.isCurrent, true);
      expect(entries.last.title, 'WORKING NOW');
    });

    test('TEST C: Active break preserved across restart timestamp', () {
      final checkIn = DateTime(2026, 11, 12, 9, 0);
      final breakStart = DateTime(2026, 11, 12, 13, 0);
      final reopenedAt = DateTime(2026, 11, 12, 13, 18);

      final activeBreak = BreakEventModel(
        id: 'brk-active',
        category: BreakCategory.lunch,
        isPaid: false,
        startedAt: breakStart,
        status: 'ACTIVE',
      );

      final summary = BreakSummaryState(
        workState: EmployeeWorkState.onBreak,
        policy: const BreakPolicySummary(),
        activeBreak: activeBreak,
        todayBreaks: [activeBreak],
      );

      final entries = buildUnifiedAttendanceTimeline(
        checkInTime: checkIn,
        checkOutTime: null,
        summary: summary,
        now: reopenedAt,
      );

      expect(entries.last.type, TimelineEntryType.unpaidBreak);
      expect(entries.last.isCurrent, true);
      expect(entries.last.durationMinutes, 18);
    });

    test('TEST E: Approved OT and BreakExceptionModel included in timeline', () {
      final checkIn = DateTime(2026, 11, 12, 9, 0);
      final shiftEnd = DateTime(2026, 11, 12, 18, 0);
      final checkOut = DateTime(2026, 11, 12, 20, 0);

      final exception = BreakExceptionModel.fromMap({
        'id': 'exc-1',
        'exception_type': 'EXCESS_UNPAID_BREAK',
        'severity': 'WARNING',
        'title': 'Unpaid break limit exceeded',
        'details': 'Exceeded 60m limit by 15m',
        'status': 'OPEN',
        'created_at': '2026-11-12T14:00:00.000',
      });

      final summary = BreakSummaryState(
        workState: EmployeeWorkState.checkedOut,
        policy: const BreakPolicySummary(),
        approvedOtMinutes: 120,
        exceptions: [exception],
      );

      final entries = buildUnifiedAttendanceTimeline(
        checkInTime: checkIn,
        checkOutTime: checkOut,
        scheduledShiftEnd: shiftEnd,
        summary: summary,
        now: checkOut,
      );

      expect(entries.any((e) => e.type == TimelineEntryType.overtime && e.durationMinutes == 120), true);
      expect(entries.any((e) => e.type == TimelineEntryType.exception && e.title == 'EXCESS UNPAID BREAK'), true);
      expect(entries.last.type, TimelineEntryType.checkOut);
    });

    test('BreakCategory ordering and distinct icons/colors follow specification', () {
      const policy = BreakPolicySummary();
      final sorted = List<BreakCategoryConfig>.from(policy.categories)
        ..sort((a, b) => a.effectiveDisplayOrder.compareTo(b.effectiveDisplayOrder));

      expect(
        sorted.map((c) => c.category.startActionLabel).toList(),
        [
          'Start Tea',
          'Start Lunch',
          'Start Coffee',
          'Start Personal Break',
          'Start Other Break',
        ],
      );
      expect(BreakCategory.tea.icon != BreakCategory.coffee.icon, true);
      expect(BreakCategory.tea.themeColor != BreakCategory.coffee.themeColor, true);
      expect(BreakCategory.personal.icon != BreakCategory.other.icon, true);
    });
  });
}
