import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/employee_models.dart';
import 'package:workforce_os/core/services/shift_duration_calculator.dart';
import 'package:workforce_os/core/utils/app_date_time.dart';

void main() {
  group('Shift Duration Calculator Edge Cases', () {
    test('Same start and end time (0-minute shift)', () {
      final calc = ShiftDurationCalculator.instance.calculate(
        startTime: '09:00',
        endTime: '09:00',
      );
      expect(calc.spanMinutes, 0);
      expect(calc.scheduledWorkMinutes, 0);
    });

    test('1-hour shift with 30min break', () {
      final calc = ShiftDurationCalculator.instance.calculate(
        startTime: '09:00',
        endTime: '10:00',
        breakMinutes: 30,
      );
      expect(calc.spanMinutes, 60);
      expect(calc.breakMinutes, 30);
      expect(calc.scheduledWorkMinutes, 30);
    });

    test('Overnight shift spanning 2 days', () {
      final calc = ShiftDurationCalculator.instance.calculate(
        startTime: '22:00',
        endTime: '06:00',
        breakMinutes: 30,
      );
      expect(calc.crossesMidnight, true);
      expect(calc.spanMinutes, 480); // 8 hours
      expect(calc.scheduledWorkMinutes, 450); // 7h 30m
    });

    test('Long 12-hour shift', () {
      final calc = ShiftDurationCalculator.instance.calculate(
        startTime: '06:00',
        endTime: '18:00',
        breakMinutes: 60,
      );
      expect(calc.spanMinutes, 720);
      expect(calc.scheduledWorkMinutes, 660);
    });

    test('Weekly off returns zero work minutes', () {
      final calc = ShiftDurationCalculator.instance.calculate(
        startTime: '09:00',
        endTime: '18:00',
        isOffDay: true,
      );
      expect(calc.scheduledWorkMinutes, 0);
      expect(calc.formattedScheduledWork, 'No scheduled work');
    });
  });

  group('AppDateTime Edge Cases', () {
    test('toIST converts UTC to IST correctly', () {
      final utc = DateTime.utc(2026, 9, 1, 4, 30); // 04:30 UTC
      final ist = AppDateTime.toIST(utc);
      expect(ist.hour, 10); // 04:30 + 5:30 = 10:00 IST
      expect(ist.minute, 0);
    });

    test('parseToIST handles ISO 8601 strings', () {
      final result = AppDateTime.parseToIST('2026-09-01T12:00:00Z');
      expect(result, isNotNull);
      expect(result!.hour, 17); // 12:00 UTC + 5:30 = 17:30 IST
      expect(result.minute, 30);
    });

    test('parseToIST handles plain time strings', () {
      final result = AppDateTime.parseToIST('09:30:00');
      expect(result, isNotNull);
      expect(result!.hour, 9);
      expect(result.minute, 30);
    });

    test('parseToIST returns null for invalid input', () {
      expect(AppDateTime.parseToIST(null), null);
      expect(AppDateTime.parseToIST(''), null);
      // Strings without time patterns or ISO dates return null
      expect(AppDateTime.parseToIST('not-a-date'), null);
    });

    test('formatTimeIST formats correctly', () {
      expect(AppDateTime.formatTimeIST('2026-09-01T04:30:00Z'), '10:00 AM');
      expect(AppDateTime.formatTimeIST('2026-09-01T12:00:00Z'), '05:30 PM');
      expect(AppDateTime.formatTimeIST(null), '—');
    });

    test('elapsed calculates duration correctly', () {
      final checkIn = DateTime(2026, 9, 1, 9, 30);
      final checkOut = DateTime(2026, 9, 1, 18, 30);
      final elapsed = AppDateTime.elapsed(checkIn, checkOut);
      expect(elapsed.inHours, 9);
    });

    test('elapsed returns zero for null checkIn', () {
      final elapsed = AppDateTime.elapsed(null);
      expect(elapsed, Duration.zero);
    });

    test('formatDuration formats HH:MM:SS', () {
      expect(AppDateTime.formatDuration(const Duration(hours: 8, minutes: 30, seconds: 15)), '08:30:15');
      expect(AppDateTime.formatDuration(const Duration(hours: 0, minutes: 5, seconds: 0)), '00:05:00');
      expect(AppDateTime.formatDuration(Duration.zero), '00:00:00');
    });
  });

  group('Document Model Tests', () {
    test('DocumentModel verification status parsing', () {
      final verified = DocumentModel(
        id: 'doc-1',
        name: 'ID Proof',
        category: DocumentCategory.personal,
        fileType: 'pdf',
        fileSize: '1.2 MB',
        uploadedAt: DateTime.now(),
        verificationStatus: 'VERIFIED',
      );
      expect(verified.isVerified, true);
      expect(verified.isRejected, false);
      expect(verified.isPending, false);

      final rejected = DocumentModel(
        id: 'doc-2',
        name: 'Address Proof',
        category: DocumentCategory.personal,
        fileType: 'jpg',
        fileSize: '500 KB',
        uploadedAt: DateTime.now(),
        verificationStatus: 'REJECTED',
      );
      expect(rejected.isRejected, true);

      final pending = DocumentModel(
        id: 'doc-3',
        name: 'Certificate',
        category: DocumentCategory.personal,
        fileType: 'pdf',
        fileSize: '2 MB',
        uploadedAt: DateTime.now(),
        verificationStatus: 'SUBMITTED',
      );
      expect(pending.isPending, true);
    });

    test('DocumentModel handles empty status', () {
      final doc = DocumentModel(
        id: 'doc-4',
        name: 'Test',
        category: DocumentCategory.company,
        fileType: 'pdf',
        fileSize: '1 MB',
        uploadedAt: DateTime.now(),
      );
      expect(doc.isPending, true); // empty status = pending
    });
  });

  group('DigitalLetterModel Tests', () {
    test('fromJson parses letter correctly', () {
      final json = {
        'id': 'let-001',
        'title': 'Experience Certificate',
        'letter_type': 'HR Letter',
        'issued_date': '2026-09-01',
        'letter_number': 'LET-001',
        'document_url': 'https://example.com/letter.pdf',
        'status': 'PUBLISHED',
      };

      final letter = DigitalLetterModel.fromJson(json);
      expect(letter.title, 'Experience Certificate');
      expect(letter.documentType, 'pdf');
      expect(letter.isSigned, false);
    });

    test('Letter isSigned detects signed status', () {
      final signed = DigitalLetterModel(
        id: 'let-002',
        title: 'Offer Letter',
        category: 'HR Letter',
        issueDate: DateTime.now(),
        documentRef: 'LET-002',
        status: 'SIGNED',
      );
      expect(signed.isSigned, true);

      final acknowledged = DigitalLetterModel(
        id: 'let-003',
        title: 'Policy',
        category: 'Policy',
        issueDate: DateTime.now(),
        documentRef: 'LET-003',
        status: 'ACKNOWLEDGED',
      );
      expect(acknowledged.isSigned, true);
    });
  });

  group('PerformanceGoalModel Tests', () {
    test('fromJson normalizes progress to 0.0-1.0 range', () {
      final json1 = {'id': 'g-1', 'title': 'Goal 1', 'category': 'Q4', 'progress_percent': 75, 'target_date': 'Q4', 'status': 'On Track'};
      final goal1 = PerformanceGoalModel.fromJson(json1);
      expect(goal1.progressPercent, 0.75);

      final json2 = {'id': 'g-2', 'title': 'Goal 2', 'category': 'Q4', 'progress': 0.5, 'target_date': 'Q4', 'status': 'In Progress'};
      final goal2 = PerformanceGoalModel.fromJson(json2);
      expect(goal2.progressPercent, 0.5);
    });
  });

  group('NotificationItemModel Tests', () {
    test('NotificationItemModel preserves all fields', () {
      final item = NotificationItemModel(
        id: 'n-001',
        title: 'Leave Approved',
        message: 'Your leave request has been approved',
        timestamp: DateTime.now(),
        isRead: false,
        icon: Icons.info,
        notificationType: 'LEAVE_APPROVED',
        entityType: 'leave_request',
        entityId: 'lv-001',
      );

      expect(item.id, 'n-001');
      expect(item.isRead, false);
      expect(item.notificationType, 'LEAVE_APPROVED');
      expect(item.entityType, 'leave_request');
    });
  });

  group('AttendanceDeviationModel Tests', () {
    test('Deviation model calculates late/early correctly', () {
      final deviation = AttendanceDeviationModel(
        id: 'dev-001',
        employeeId: 'EMP-001',
        date: DateTime.now(),
        scheduledIn: '09:30 AM',
        actualIn: '09:45 AM',
        lateMinutes: 15,
        lateGraceMinutes: 10,
        payableLateMinutes: 5,
        scheduledOut: '06:30 PM',
        actualOut: '06:25 PM',
        earlyMinutes: 5,
        earlyGraceMinutes: 10,
        payableEarlyMinutes: 0,
        deviationType: 'LATE',
        status: 'DETECTED',
      );

      expect(deviation.isLate, true); // 15 > 10 grace
      expect(deviation.isEarly, false); // 5 < 10 grace
      expect(deviation.isRegularized, false);
      expect(deviation.isUnderReview, false);
    });

    test('Regularized deviation shows as regularized', () {
      final deviation = AttendanceDeviationModel(
        id: 'dev-002',
        employeeId: 'EMP-001',
        date: DateTime.now(),
        scheduledIn: '09:30 AM',
        lateMinutes: 30,
        lateGraceMinutes: 10,
        payableLateMinutes: 20,
        scheduledOut: '06:30 PM',
        earlyMinutes: 0,
        earlyGraceMinutes: 10,
        payableEarlyMinutes: 0,
        deviationType: 'LATE',
        status: 'REGULARIZED',
      );

      expect(deviation.isRegularized, true);
    });
  });
}
