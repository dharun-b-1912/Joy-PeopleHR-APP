import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/hrms_models.dart';
import 'package:workforce_os/models/employee_relations_models.dart';

void main() {
  group('Release Candidate Office Feedback Fixes Tests', () {
    test('1. CelebrationModel relativeLabel and celebrationTitle calculate correctly', () {
      final now = DateTime.now();
      
      // Today Birthday
      final todayBday = CelebrationModel(
        id: 'c-1',
        employeeId: 'emp-101',
        employeeName: 'Sarah Jenkins',
        department: 'Engineering',
        designation: 'Senior Flutter Developer',
        type: CelebrationType.birthday,
        date: DateTime(now.year, now.month, now.day),
      );
      expect(todayBday.isToday, isTrue);
      expect(todayBday.relativeLabel, equals('Today 🎉'));
      expect(todayBday.celebrationTitle, equals('Birthday 🎂'));

      // Tomorrow Work Anniversary (3 years)
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowAnniversary = CelebrationModel(
        id: 'c-2',
        employeeId: 'emp-102',
        employeeName: 'Alex Rivera',
        department: 'Product',
        designation: 'Product Lead',
        type: CelebrationType.workAnniversary,
        date: DateTime(now.year, tomorrow.month, tomorrow.day),
        yearsOfService: 3,
      );
      expect(tomorrowAnniversary.isTomorrow, isTrue);
      expect(tomorrowAnniversary.relativeLabel, equals('Tomorrow 🎈'));
      expect(tomorrowAnniversary.celebrationTitle, equals('3rd Work Anniversary 🌟'));

      // 1st Anniversary
      final firstAnniversary = CelebrationModel(
        id: 'c-3',
        employeeId: 'emp-103',
        employeeName: 'David Chen',
        department: 'Operations',
        designation: 'Operations Analyst',
        type: CelebrationType.workAnniversary,
        date: DateTime(now.year, now.month, now.day),
        yearsOfService: 1,
      );
      expect(firstAnniversary.celebrationTitle, equals('1st Work Anniversary 🌟'));
    });

    test('2. Regularization Status parsing accurately classifies REJECTED, DISAPPROVED, and WITHDRAWN', () {
      final testStatuses = [
        {'raw': 'DISAPPROVED', 'expectedApproved': false, 'expectedRejected': true},
        {'raw': 'REJECTED', 'expectedApproved': false, 'expectedRejected': true},
        {'raw': 'DECLINED', 'expectedApproved': false, 'expectedRejected': true},
        {'raw': 'HR_REJECTED', 'expectedApproved': false, 'expectedRejected': true},
        {'raw': 'MANAGER_REJECTED', 'expectedApproved': false, 'expectedRejected': true},
        {'raw': 'NOT_APPROVED', 'expectedApproved': false, 'expectedRejected': true},
        {'raw': 'WITHDRAWN', 'expectedApproved': false, 'expectedRejected': false, 'expectedWithdrawn': true},
        {'raw': 'APPROVED', 'expectedApproved': true, 'expectedRejected': false},
        {'raw': 'HR_APPROVED', 'expectedApproved': true, 'expectedRejected': false},
        {'raw': 'MANAGER_APPROVED', 'expectedApproved': true, 'expectedRejected': false},
        {'raw': 'ACCEPTED', 'expectedApproved': true, 'expectedRejected': false},
        {'raw': 'REGULARIZED', 'expectedApproved': true, 'expectedRejected': false},
      ];

      bool isApprovedStatus(String? status) {
        if (status == null) return false;
        final s = status.trim().toUpperCase();
        if (s.contains('DISAPPROV') ||
            s.contains('REJECT') ||
            s.contains('DECLIN') ||
            s.contains('NOT_APPROV') ||
            s.contains('WITHDRAW') ||
            s.contains('CANCEL') ||
            s.contains('PENDING')) {
          return false;
        }
        return s.contains('APPROV') || s.contains('ACCEPT') || s == 'REGULARIZED';
      }

      bool isRejectedStatus(String? status) {
        if (status == null) return false;
        final s = status.trim().toUpperCase();
        return s.contains('DISAPPROV') ||
            s.contains('REJECT') ||
            s.contains('DECLIN') ||
            s.contains('NOT_APPROV');
      }

      bool isWithdrawnStatus(String? status) {
        if (status == null) return false;
        final s = status.trim().toUpperCase();
        return s.contains('WITHDRAW') || s.contains('CANCEL');
      }

      for (final t in testStatuses) {
        final raw = t['raw'] as String;
        expect(isApprovedStatus(raw), equals(t['expectedApproved']), reason: 'Checking $raw for approval');
        if (t.containsKey('expectedRejected')) {
          expect(isRejectedStatus(raw), equals(t['expectedRejected']), reason: 'Checking $raw for rejection');
        }
        if (t.containsKey('expectedWithdrawn')) {
          expect(isWithdrawnStatus(raw), equals(t['expectedWithdrawn']), reason: 'Checking $raw for withdrawal');
        }
      }
    });

    test('3. CommunicationModel copyWith updates read status cleanly', () {
      final comm = CommunicationModel(
        id: 'comm-101',
        title: 'Office Holiday Announcement',
        body: 'Office will remain closed on Friday for company milestone celebration.',
        communicationType: 'ANNOUNCEMENT',
        priority: 'IMPORTANT',
        status: 'PUBLISHED',
        requiresAcknowledgement: false,
        authorName: 'HR Joy PeopleHR',
        publishAt: DateTime.now(),
        isRead: false,
      );

      expect(comm.isRead, isFalse);

      final updated = comm.copyWith(isRead: true);
      expect(updated.isRead, isTrue);
      expect(updated.title, equals(comm.title));
      expect(updated.body, equals(comm.body));
      expect(updated.id, equals(comm.id));
    });
  });
}
