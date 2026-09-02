import 'package:flutter/material.dart';

/// Shared Geographic Coordinate Representation
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint({required this.latitude, required this.longitude});

  bool get isValid =>
      latitude >= -90.0 &&
      latitude <= 90.0 &&
      longitude >= -180.0 &&
      longitude <= 180.0 &&
      (latitude != 0.0 || longitude != 0.0);

  @override
  String toString() => 'GeoPoint(lat: $latitude, lng: $longitude)';
}

/// Approved Work Location Details
class ApprovedWorkLocation {
  final String? id;
  final String name;
  final String? code;
  final String? locationType;
  final String? address;
  final double latitude;
  final double longitude;
  final double allowedRadiusMeters;
  final double accuracyRequirementMeters;
  final bool isPrimary;

  const ApprovedWorkLocation({
    this.id,
    required this.name,
    this.code,
    this.locationType,
    this.address,
    required this.latitude,
    required this.longitude,
    required this.allowedRadiusMeters,
    this.accuracyRequirementMeters = 50.0,
    this.isPrimary = true,
  });

  GeoPoint get point => GeoPoint(latitude: latitude, longitude: longitude);

  factory ApprovedWorkLocation.fromJson(Map<String, dynamic> json) {
    return ApprovedWorkLocation(
      id: json['id']?.toString() ?? json['location_id']?.toString(),
      name: json['name']?.toString() ?? json['location_name']?.toString() ?? 'Assigned Work Location',
      code: json['code']?.toString() ?? json['location_code']?.toString(),
      locationType: json['location_type']?.toString() ?? 'OFFICE',
      address: json['address']?.toString(),
      latitude: ((json['latitude'] ?? 0.0) as num).toDouble(),
      longitude: ((json['longitude'] ?? 0.0) as num).toDouble(),
      allowedRadiusMeters: ((json['allowed_radius_meters'] ??
              json['geofence_radius_meters'] ??
              json['geo_fence_radius_meters'] ??
              json['radius_meters'] ??
              json['radius']) as num?)
          ?.toDouble() ??
          0.0,
      accuracyRequirementMeters: ((json['accuracy_requirement_meters'] ?? 50.0) as num).toDouble(),
      isPrimary: json['is_primary'] == true,
    );
  }
}

/// Checkout Location Verification Result
///
/// Represents the result of evaluating WHERE an employee is checking out from.
/// This is an ADDITIONAL layer — it does NOT block checkout. It only classifies
/// the location for audit purposes.
///
/// Check-in remains strict (must be inside authorized geofence).
/// Checkout is always allowed, but location is verified and recorded.
class CheckoutLocationVerification {
  /// Classification of checkout location
  final CheckoutLocationStatus status;

  /// Human-readable location name (e.g., "Client A", "Head Office", "Unknown")
  final String locationName;

  /// Employee's reason for unauthorized/GPS-unavailable checkout
  final String? reason;

  /// Captured GPS coordinates at checkout
  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// Distance to nearest authorized location (for display)
  final double distanceToNearestMeters;

  /// The matched authorized location (if any)
  final ApprovedWorkLocation? matchedLocation;

  const CheckoutLocationVerification({
    required this.status,
    required this.locationName,
    this.reason,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.distanceToNearestMeters,
    this.matchedLocation,
  });

  /// Whether this verification requires a reason from the employee
  bool get requiresReason =>
      status == CheckoutLocationStatus.unauthorized ||
      status == CheckoutLocationStatus.gpsUnavailable;

  /// Whether a valid non-empty reason has been supplied
  bool get isReasonProvided => reason != null && reason!.trim().isNotEmpty;

  /// Whether the employee is at an unknown/uncertain location
  bool get isUncertainLocation =>
      status == CheckoutLocationStatus.unauthorized ||
      status == CheckoutLocationStatus.gpsUnavailable;

  /// Human-readable status message for the employee
  String get statusMessage {
    switch (status) {
      case CheckoutLocationStatus.assignedLocation:
        return 'Checked out from assigned location ($locationName)';
      case CheckoutLocationStatus.mainOffice:
        return 'Checked out from main office ($locationName)';
      case CheckoutLocationStatus.otherAuthorized:
        return 'Checked out from $locationName';
      case CheckoutLocationStatus.unauthorized:
        return 'Checked out from an unrecognized location';
      case CheckoutLocationStatus.gpsUnavailable:
        return 'Checked out without GPS verification';
      default:
        return 'Checked out';
    }
  }

  /// Short label for admin dashboard
  String get shortLabel {
    switch (status) {
      case CheckoutLocationStatus.assignedLocation:
        return locationName;
      case CheckoutLocationStatus.mainOffice:
        return 'Main Office';
      case CheckoutLocationStatus.otherAuthorized:
        return locationName;
      case CheckoutLocationStatus.unauthorized:
        return 'Unknown Location';
      case CheckoutLocationStatus.gpsUnavailable:
        return 'GPS Unavailable';
      default:
        return 'Unknown';
    }
  }

  /// Convert to Map for database storage
  Map<String, dynamic> toMap() => {
    'checkout_location_status': status.value,
    'checkout_location_name': locationName,
    'checkout_location_reason': reason,
    'checkout_latitude': latitude,
    'checkout_longitude': longitude,
    'checkout_accuracy_meters': accuracyMeters,
  };
}

/// Enum representing the classification of a checkout location
class CheckoutLocationStatus {
  final String value;
  const CheckoutLocationStatus._(this.value);

  /// Employee is inside their assigned work location geofence
  static const assignedLocation = CheckoutLocationStatus._('assigned_location');

  /// Employee is at the company's main/head office
  static const mainOffice = CheckoutLocationStatus._('main_office');

  /// Employee is at another registered work location (not their primary)
  static const otherAuthorized = CheckoutLocationStatus._('other_authorized');

  /// Employee is at an unknown location (not in any registered location)
  static const unauthorized = CheckoutLocationStatus._('unauthorized');

  /// GPS could not be obtained at all
  static const gpsUnavailable = CheckoutLocationStatus._('gps_unavailable');

  static CheckoutLocationStatus fromValue(String? value) {
    switch (value) {
      case 'assigned_location': return assignedLocation;
      case 'main_office': return mainOffice;
      case 'other_authorized': return otherAuthorized;
      case 'unauthorized': return unauthorized;
      case 'gps_unavailable': return gpsUnavailable;
      default: return assignedLocation;
    }
  }

  @override
  String toString() => value;
}

class EmergencyContactModel {
  final String name;
  final String relationship;
  final String phone;

  const EmergencyContactModel({
    required this.name,
    required this.relationship,
    required this.phone,
  });
}

class PayrollStatutoryModel {
  final String? bankName;
  final String? branchName;
  final String? accountNumber;
  final String? rawAccountNumber;
  final String? ifscCode;
  final String? accountHolderName;
  final String? panNumber;
  final String? rawPanNumber;
  final String? uanNumber;
  final String? rawUanNumber;
  final String? pfNumber;
  final String? rawPfNumber;
  final String? esiNumber;
  final String? rawEsiNumber;
  final String? taxRegime;

  const PayrollStatutoryModel({
    this.bankName,
    this.branchName,
    this.accountNumber,
    this.rawAccountNumber,
    this.ifscCode,
    this.accountHolderName,
    this.panNumber,
    this.rawPanNumber,
    this.uanNumber,
    this.rawUanNumber,
    this.pfNumber,
    this.rawPfNumber,
    this.esiNumber,
    this.rawEsiNumber,
    this.taxRegime,
  });
}

class CompanyAssetModel {
  final String id;
  final String assetName;
  final String assetId;
  final String category; // IT Hardware, Peripheral, Mobile, Access Card
  final String assignedDate;
  final String status; // Active, Returned, Under Repair, Pending Return
  final IconData icon;

  const CompanyAssetModel({
    required this.id,
    required this.assetName,
    required this.assetId,
    required this.category,
    required this.assignedDate,
    required this.status,
    this.icon = Icons.laptop_mac,
  });
}

class UserModel {
  final String name;
  final String firstName;
  final String employeeId;

  /// Real primary key of the employees row (employees.id).
  /// All FK columns (attendance_daily.employee_id, leave_entitlements.employee_id,
  /// leave_requests.employee_id …) reference this — NOT the employee_code.
  final String? employeeUuid;

  /// Real primary key of the legal-entity company row (companies.id).
  /// Used when inserting rows whose company_id FK must point at a company,
  /// e.g. leave_requests.company_id. Falls back to [companyId] (org id).
  final String? companyUuid;
  final String designation;
  final String department;
  final String role;
  final String machinePin;
  final String campus;
  final ApprovedWorkLocation approvedLocation;
  final String shiftStart;
  final String shiftEnd;
  final String? shiftName; // e.g. "General Shift (09:00 AM - 06:00 PM)"
  final double leaveBalanceDays;
  final String? reportsToId;
  final String? reportsToName;
  final String companyId;
  final String? companyName;

  final String employmentType;
  final String? status; // active | inactive | on_leave
  final String? joiningDate; // ISO date string e.g. "2026-07-17"
  final String personalEmail;
  final String? officeEmail;
  final String contactNumber;
  final String address;
  final EmergencyContactModel? emergencyContact;
  final PayrollStatutoryModel? payrollStatutory;
  final String? profileImage;
  final List<CompanyAssetModel> assignedAssets;
  final List<ApprovedWorkLocation> assignedLocations;

  const UserModel({
    required this.name,
    required this.firstName,
    required this.employeeId,
    this.employeeUuid,
    this.companyUuid,
    required this.designation,
    required this.department,
    required this.role,
    required this.machinePin,
    required this.campus,
    required this.approvedLocation,
    required this.shiftStart,
    required this.shiftEnd,
    this.shiftName,
    required this.leaveBalanceDays,
    this.reportsToId,
    this.reportsToName,
    this.companyId = "",
    this.companyName,
    this.employmentType = "Full Time",
    this.status,
    this.joiningDate,
    this.personalEmail = "",
    this.officeEmail,
    this.contactNumber = "",
    this.address = "",
    this.emergencyContact,
    this.payrollStatutory,
    this.profileImage,
    this.assignedAssets = const [],
    this.assignedLocations = const [],
  });

  /// Id to use for DB queries — prefers the employees.id PK, falls back to code.
  String get dataId =>
      (employeeUuid?.isNotEmpty == true) ? employeeUuid! : employeeId;

  String? get organizationId => companyId.isNotEmpty ? companyId : null;
  String? get organizationName => companyName;

  /// Pure dynamic tenant identifier resolved directly from the user's DB entity
  String get tenantId =>
      companyId.isNotEmpty ? companyId : (organizationId?.isNotEmpty == true ? organizationId! : '');

  /// Reliable employee UUID identifier preferring the primary key employees.id
  String get resolvedEmployeeId =>
      (employeeUuid?.isNotEmpty == true) ? employeeUuid! : (employeeId.isNotEmpty ? employeeId : dataId);

  bool get canAccessTeam => false;
  bool get canApproveRequests => false;
  bool get canViewTeamAttendance => false;
  bool get canManageTeam => false;
  bool get canViewPersonalWorkspace => true;
  String get shift => shiftName ?? (shiftStart.isNotEmpty ? '$shiftStart - $shiftEnd' : 'General Shift');

  UserModel copyWith({
    String? name,
    String? firstName,
    String? employeeId,
    String? employeeUuid,
    String? companyUuid,
    String? designation,
    String? department,
    String? role,
    String? machinePin,
    String? campus,
    ApprovedWorkLocation? approvedLocation,
    String? shiftStart,
    String? shiftEnd,
    String? shiftName,
    double? leaveBalanceDays,
    String? reportsToId,
    String? reportsToName,
    String? companyId,
    String? companyName,
    String? employmentType,
    String? status,
    String? joiningDate,
    String? personalEmail,
    String? officeEmail,
    String? contactNumber,
    String? address,
    EmergencyContactModel? emergencyContact,
    PayrollStatutoryModel? payrollStatutory,
    String? profileImage,
    List<CompanyAssetModel>? assignedAssets,
    List<ApprovedWorkLocation>? assignedLocations,
  }) {
    return UserModel(
      name: name ?? this.name,
      firstName: firstName ?? this.firstName,
      employeeId: employeeId ?? this.employeeId,
      employeeUuid: employeeUuid ?? this.employeeUuid,
      companyUuid: companyUuid ?? this.companyUuid,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      role: role ?? this.role,
      machinePin: machinePin ?? this.machinePin,
      campus: campus ?? this.campus,
      approvedLocation: approvedLocation ?? this.approvedLocation,
      shiftStart: shiftStart ?? this.shiftStart,
      shiftEnd: shiftEnd ?? this.shiftEnd,
      shiftName: shiftName ?? this.shiftName,
      leaveBalanceDays: leaveBalanceDays ?? this.leaveBalanceDays,
      reportsToId: reportsToId ?? this.reportsToId,
      reportsToName: reportsToName ?? this.reportsToName,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      employmentType: employmentType ?? this.employmentType,
      status: status ?? this.status,
      joiningDate: joiningDate ?? this.joiningDate,
      personalEmail: personalEmail ?? this.personalEmail,
      officeEmail: officeEmail ?? this.officeEmail,
      contactNumber: contactNumber ?? this.contactNumber,
      address: address ?? this.address,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      payrollStatutory: payrollStatutory ?? this.payrollStatutory,
      profileImage: profileImage ?? this.profileImage,
      assignedAssets: assignedAssets ?? this.assignedAssets,
      assignedLocations: assignedLocations ?? this.assignedLocations,
    );
  }
}

class PoshCommitteeConfigModel {
  final String id;
  final String companyId;
  final String committeeName;
  final bool isActive;
  final List<String> memberIds;

  const PoshCommitteeConfigModel({
    required this.id,
    required this.companyId,
    required this.committeeName,
    required this.isActive,
    required this.memberIds,
  });
}

class CompanyOrganizationModel {
  final String companyId;
  final String companyName;
  final String companyAdminId;
  final String companyAdminName;
  final PoshCommitteeConfigModel? poshCommittee;

  const CompanyOrganizationModel({
    required this.companyId,
    required this.companyName,
    required this.companyAdminId,
    required this.companyAdminName,
    this.poshCommittee,
  });
}

class AppletTileModel {
  final String id;
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;

  const AppletTileModel({
    required this.id,
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });
}

class PassCardModel {
  final String id;
  final String label;
  final String title;
  final String subtitle;

  const PassCardModel({
    required this.id,
    required this.label,
    required this.title,
    required this.subtitle,
  });
}

enum ApprovalType { leave, regularization, expense }

class ApprovalRequestModel {
  final String id;
  final ApprovalType type;
  final String employee;
  final String initials;
  final String department;
  final String appliedAgo;
  final String title;
  final String detail;
  final String reason;
  final String? impact;

  const ApprovalRequestModel({
    required this.id,
    required this.type,
    required this.employee,
    required this.initials,
    required this.department,
    required this.appliedAgo,
    required this.title,
    required this.detail,
    required this.reason,
    this.impact,
  });
}

class CompletedApprovalModel {
  final String id;
  final String employee;
  final String initials;
  final String title;
  final String status;
  final String when;

  const CompletedApprovalModel({
    required this.id,
    required this.employee,
    required this.initials,
    required this.title,
    required this.status,
    required this.when,
  });
}

class PunchLogModel {
  final String label;
  final String time;
  final String place;

  const PunchLogModel({
    required this.label,
    required this.time,
    required this.place,
  });
}

class TeamMemberModel {
  final String name;
  final String role;
  final String initials;
  final String status; // 'In office' | 'On leave' | 'Remote'

  const TeamMemberModel({
    required this.name,
    required this.role,
    required this.initials,
    required this.status,
  });
}

enum AttendanceStatus { notCheckedIn, checkedIn, checkedOut }

class AttendanceSession {
  final AttendanceStatus status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final int? netWorkingMinutes;
  final String? checkInLocationName;
  final double? checkInDistanceMeters;

  const AttendanceSession({
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.netWorkingMinutes,
    this.checkInLocationName,
    this.checkInDistanceMeters,
  });

  bool get isCheckedIn => status == AttendanceStatus.checkedIn;
  bool get isCheckedOut => status == AttendanceStatus.checkedOut;
}

