import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/core/services/shift_adaptive_service.dart';

void main() {
  group('ShiftAdaptiveService Tests', () {
    final factoryShifts = [
      const CompanyShift(
        id: 'shift-1',
        organizationId: 'org-factory-1',
        name: 'Shift 1 (Morning)',
        code: 'S1',
        startTime: '06:00:00',
        endTime: '14:00:00',
      ),
      const CompanyShift(
        id: 'shift-2',
        organizationId: 'org-factory-1',
        name: 'Shift 2 (Afternoon)',
        code: 'S2',
        startTime: '14:00:00',
        endTime: '22:00:00',
      ),
      const CompanyShift(
        id: 'shift-3',
        organizationId: 'org-factory-1',
        name: 'Shift 3 (Night)',
        code: 'S3',
        startTime: '22:00:00',
        endTime: '06:00:00',
        isOvernight: true,
      ),
      const CompanyShift(
        id: 'shift-gen',
        organizationId: 'org-factory-1',
        name: 'General Day Shift',
        code: 'GEN',
        startTime: '08:30:00',
        endTime: '17:30:00',
      ),
    ];

    test('Early check-in at 05:40 AM automatically matches Shift 1 (06:00 AM)', () {
      final checkInTime = DateTime(2026, 10, 29, 5, 40);
      final detected = ShiftAdaptiveService.instance.detectNearestShift(
        shifts: factoryShifts,
        referenceTime: checkInTime,
      );

      expect(detected.id, equals('shift-1'));
      expect(detected.name, equals('Shift 1 (Morning)'));
      expect(detected.formattedStart, equals('06:00 AM'));
      expect(detected.formattedEnd, equals('02:00 PM'));
    });

    test('Check-in at 08:45 AM matches General Day Shift (08:30 AM)', () {
      final checkInTime = DateTime(2026, 10, 29, 8, 45);
      final detected = ShiftAdaptiveService.instance.detectNearestShift(
        shifts: factoryShifts,
        referenceTime: checkInTime,
      );

      expect(detected.id, equals('shift-gen'));
      expect(detected.name, equals('General Day Shift'));
    });

    test('Check-in at 13:50 (01:50 PM) matches Shift 2 (02:00 PM)', () {
      final checkInTime = DateTime(2026, 10, 29, 13, 50);
      final detected = ShiftAdaptiveService.instance.detectNearestShift(
        shifts: factoryShifts,
        referenceTime: checkInTime,
      );

      expect(detected.id, equals('shift-2'));
      expect(detected.name, equals('Shift 2 (Afternoon)'));
    });

    test('Check-in at 21:40 (09:40 PM) matches Shift 3 (10:00 PM)', () {
      final checkInTime = DateTime(2026, 10, 29, 21, 40);
      final detected = ShiftAdaptiveService.instance.detectNearestShift(
        shifts: factoryShifts,
        referenceTime: checkInTime,
      );

      expect(detected.id, equals('shift-3'));
      expect(detected.name, equals('Shift 3 (Night)'));
      expect(detected.isOvernight, isTrue);
    });

    test('Cross-midnight rollover: Check-in at 23:55 still matches 22:00 Night Shift over 06:00 AM', () {
      final checkInTime = DateTime(2026, 10, 29, 23, 55);
      final detected = ShiftAdaptiveService.instance.detectNearestShift(
        shifts: factoryShifts,
        referenceTime: checkInTime,
      );

      expect(detected.id, equals('shift-3'));
    });

    test('Formatted time range converts military time to 12-hour AM/PM format', () {
      const shift = CompanyShift(
        id: 'test',
        organizationId: 'org',
        name: 'Factory Custom',
        startTime: '07:15:00',
        endTime: '16:45:00',
      );

      expect(shift.formattedStart, equals('07:15 AM'));
      expect(shift.formattedEnd, equals('04:45 PM'));
      expect(shift.formattedRange, equals('07:15 AM – 04:45 PM'));
    });
  });
}
