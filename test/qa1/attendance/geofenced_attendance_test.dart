import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workforce_os/models/hrms_models.dart';

void main() {
  group('1. Location Validation & Geofence Tests', () {
    const headOffice = ApprovedWorkLocation(
      id: 'loc-hq-01',
      name: 'Head Office',
      latitude: 11.0168,
      longitude: 76.9558,
      allowedRadiusMeters: 100,
      isPrimary: true,
    );

    const clientSiteA = ApprovedWorkLocation(
      id: 'loc-client-a',
      name: 'Client Site A',
      latitude: 11.0500,
      longitude: 76.9900,
      allowedRadiusMeters: 150,
      isPrimary: false,
    );

    test('Employee inside assigned location is AUTHORIZED', () {
      // Point 30m away from Head Office
      final distance = Geolocator.distanceBetween(
        11.0168,
        76.9558,
        11.0170,
        76.9560,
      );
      expect(distance <= headOffice.allowedRadiusMeters, true);
    });

    test('Employee outside assigned location is UNAUTHORIZED', () {
      // Point 5km away from Head Office
      final distance = Geolocator.distanceBetween(
        11.0168,
        76.9558,
        11.0600,
        76.9900,
      );
      expect(distance <= headOffice.allowedRadiusMeters, false);
    });

    test('Employee assigned to multiple locations is authorized at ANY valid workplace', () {
      final assignedLocations = [headOffice, clientSiteA];

      // Standing inside Client Site A (25m away from Client Site A)
      const currentLat = 11.0501;
      const currentLng = 76.9902;

      final insideAny = assignedLocations.any((loc) {
        final dist = Geolocator.distanceBetween(currentLat, currentLng, loc.latitude, loc.longitude);
        return dist <= loc.allowedRadiusMeters;
      });

      expect(insideAny, true);
    });

    test('Employee outside all assigned locations is rejected for strict check-in', () {
      final assignedLocations = [headOffice, clientSiteA];

      // Standing at an unauthorized location 15km away
      const currentLat = 11.1500;
      const currentLng = 77.1000;

      final insideAny = assignedLocations.any((loc) {
        final dist = Geolocator.distanceBetween(currentLat, currentLng, loc.latitude, loc.longitude);
        return dist <= loc.allowedRadiusMeters;
      });

      expect(insideAny, false);
    });
  });

  group('2. Checkout Location Verification & Reason Validation', () {
    test('CheckoutLocationVerification requires reason for unauthorized location', () {
      const unauthorized = CheckoutLocationVerification(
        status: CheckoutLocationStatus.unauthorized,
        locationName: 'Unknown Location',
        latitude: 11.1500,
        longitude: 77.1000,
        accuracyMeters: 12.0,
        distanceToNearestMeters: 15400,
        reason: 'Emergency Client Meeting at off-site facility',
      );

      expect(unauthorized.requiresReason, true);
      expect(unauthorized.isReasonProvided, true);
      expect(unauthorized.reason?.trim().isNotEmpty, true);
      expect(unauthorized.toMap()['checkout_location_status'], 'unauthorized');
      expect(unauthorized.toMap()['checkout_location_reason'], 'Emergency Client Meeting at off-site facility');
    });

    test('Empty or whitespace-only reason is marked as not provided', () {
      const emptyReasonVerification = CheckoutLocationVerification(
        status: CheckoutLocationStatus.unauthorized,
        locationName: 'Unknown Location',
        latitude: 11.1500,
        longitude: 77.1000,
        accuracyMeters: 12.0,
        distanceToNearestMeters: 15400,
        reason: '   ',
      );

      expect(emptyReasonVerification.requiresReason, true);
      expect(emptyReasonVerification.isReasonProvided, false);
    });

    test('Authorized checkout does not require a reason', () {
      const authorized = CheckoutLocationVerification(
        status: CheckoutLocationStatus.assignedLocation,
        locationName: 'Head Office',
        latitude: 11.0168,
        longitude: 76.9558,
        accuracyMeters: 8.0,
        distanceToNearestMeters: 38,
      );

      expect(authorized.requiresReason, false);
      expect(authorized.reason, null);
      expect(authorized.toMap()['checkout_location_status'], 'assigned_location');
    });

    test('Fresh GPS coordinates at checkout are preserved in database payload', () {
      const checkoutVerification = CheckoutLocationVerification(
        status: CheckoutLocationStatus.unauthorized,
        locationName: 'Client Office Block B',
        latitude: 11.0850,
        longitude: 77.0120,
        accuracyMeters: 15.0,
        distanceToNearestMeters: 8200,
        reason: 'Onsite deployment with customer team',
      );

      final map = checkoutVerification.toMap();
      expect(map['checkout_latitude'], 11.0850);
      expect(map['checkout_longitude'], 77.0120);
      expect(map['checkout_accuracy_meters'], 15.0);
      expect(map['checkout_location_reason'], 'Onsite deployment with customer team');
    });
  });

  group('3. Multi-Tenant Tenant Isolation & Security Tests', () {
    test('User dataId correctly resolves employee database UUID', () {
      const employee = UserModel(
        name: 'Sarah Connor',
        firstName: 'Sarah',
        employeeId: 'EMP-771',
        employeeUuid: 'b1c2d3e4-f5a6-7b8c-9d0e-1f2a3b4c5d6e',
        designation: 'Field Operations Specialist',
        department: 'Operations',
        role: 'EMPLOYEE',
        machinePin: '9988',
        campus: 'Main Facility',
        approvedLocation: ApprovedWorkLocation(
          name: 'Main Facility',
          latitude: 13.0827,
          longitude: 80.2707,
          allowedRadiusMeters: 120,
        ),
        shiftStart: '09:00 AM',
        shiftEnd: '06:00 PM',
        leaveBalanceDays: 12,
        companyId: 'tenant-enterprise-01',
      );

      expect(employee.dataId, 'b1c2d3e4-f5a6-7b8c-9d0e-1f2a3b4c5d6e');
      expect(employee.tenantId, 'tenant-enterprise-01');
    });
  });
}
