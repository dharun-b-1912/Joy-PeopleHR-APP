// employee_profile_mapper.dart — maps employees table row to canonical UserModel
import '../../models/hrms_models.dart';


/// WorkForceOS — employees row → UserModel mapper.
///
/// Aligned to the real Supabase schema. The employees table exposes:
///   id, organization_id, company_id, branch_id, department_id, designation_id,
///   employee_code, first_name, last_name, middle_name, display_name,
///   work_email, avatar_url, status, employment_type, profile (jsonb),
///   employment (jsonb), company_name, branch_name, department_name,
///   designation_title …
///
/// Extended personal fields (phone, address, personal email, DOJ, emergency
/// contact…) live inside the `profile` jsonb; shift/reporting data lives in
/// `employment` jsonb. Every lookup is defensive so partial data never breaks
/// the app.
class EmployeeProfileMapper {
  /// Map a full employees row (+ optional auth fallback email) to UserModel.
  static UserModel fromEmployeesRow(
    Map<String, dynamic> emp, {
    String? authEmail,
    String? authAvatarUrl,
    String? role = 'EMPLOYEE',
    Map<String, dynamic>? statutory,
    Map<String, dynamic>? bankAccount,
    Map<String, dynamic>? emergencyContact,
    List<ApprovedWorkLocation>? assignedLocations,
  }) {
    final profile = _asMap(emp['profile']);
    final employment = _asMap(emp['employment']);

    final firstName = _s(emp['first_name']) ?? '';
    final lastName = _s(emp['last_name']) ?? '';
    final displayName =
        _s(emp['display_name']) ?? '$firstName $lastName'.trim();

    // ── Shift (employment jsonb, shift object, top-level fallback) ────────
    Map<String, dynamic> shiftObj = const {};
    if (emp['shift'] is Map) {
      shiftObj = Map<String, dynamic>.from(emp['shift'] as Map);
    } else if (employment['shift'] is Map) {
      shiftObj = Map<String, dynamic>.from(employment['shift'] as Map);
    }

    final shiftName = _first(shiftObj, employment, ['shift_name', 'name', 'shift_label', 'shift']) ??
        _first(emp, profile, ['shift_name', 'shift', 'shift_label']) ??
        '';
    var shiftStart = _first(shiftObj, employment, ['shift_start_time', 'start_time', 'shift_start', 'expected_check_in']) ??
        _first(emp, profile, ['shift_start_time', 'shift_start', 'expected_check_in']) ??
        '';
    var shiftEnd = _first(shiftObj, employment, ['shift_end_time', 'end_time', 'shift_end', 'expected_check_out']) ??
        _first(emp, profile, ['shift_end_time', 'shift_end', 'expected_check_out']) ??
        '';
    if (_looksLikeTime(shiftStart)) shiftStart = _formatTime(shiftStart);
    if (_looksLikeTime(shiftEnd)) shiftEnd = _formatTime(shiftEnd);

    final hasTiming = shiftName.contains('(') || shiftName.contains('AM') || shiftName.contains('PM') || shiftName.contains('–') || shiftName.contains('-');
    final shiftDisplay = shiftName.isNotEmpty
        ? (hasTiming ? shiftName : '$shiftName${shiftStart.isNotEmpty ? ' ($shiftStart - $shiftEnd)' : ''}')
        : shiftStart.isNotEmpty
            ? '$shiftStart - $shiftEnd'
            : 'General Shift';

    // ── Reporting chain (employment jsonb) ────────────────────────────────
    final reportsToId = _first(employment, emp, [
      'reports_to_id',
      'manager_id',
      'reporting_manager_id',
      'manager_employee_id',
    ]);
    final reportsToName = _first(employment, emp, [
      'reports_to_name',
      'manager_name',
      'reporting_manager_name',
    ]);

    // ── Personal fields (profile jsonb, top-level fallback) ───────────────
    final phone = _first(profile, emp,
        ['phone', 'mobile', 'contact_number', 'phone_number']) ??
        '';
    final address = _resolveAddress(profile, emp);
    final personalEmail = _first(profile, emp,
        ['personal_email', 'alternate_email', 'secondary_email']);
    final joiningDate = _first(employment, emp, [
      'date_of_joining',
      'joining_date',
      'doj',
      'date_of_hire',
      'hire_date',
    ]) ?? _first(profile, emp, ['date_of_joining', 'joining_date', 'doj']);
    final campus = _first(employment, emp, [
          'location_name',
          'campus',
          'work_location',
          'branch_name',
        ]) ??
        _s(emp['branch_name']) ??
        '';

    final designation = _first(employment, emp, [
          'designation_title',
          'designation',
          'job_title',
          'title',
          'role_title',
          'designation_name',
        ]) ??
        _first(profile, emp, [
          'designation_title',
          'designation',
          'job_title',
          'title',
        ]) ??
        '';

    final department = _first(employment, emp, [
          'department_name',
          'department',
          'dept_name',
          'dept',
        ]) ??
        _first(profile, emp, [
          'department_name',
          'department',
        ]) ??
        '';

    final unit = _first(employment, emp, [
          'unit_name',
          'unit',
          'business_unit',
        ]) ??
        _first(profile, emp, [
          'unit_name',
          'unit',
        ]);

    // ── Bank & Statutory (Map authentic records or fallback fields) ────────────
    final rawBank = bankAccount ??
        (_asMap(emp['bank']).isNotEmpty
            ? _asMap(emp['bank'])
            : (_asMap(profile['bank']).isNotEmpty ? _asMap(profile['bank']) : <String, dynamic>{}));
    final rawStat = statutory ??
        (_asMap(emp['statutory']).isNotEmpty
            ? _asMap(emp['statutory'])
            : (_asMap(profile['statutory']).isNotEmpty ? _asMap(profile['statutory']) : <String, dynamic>{}));

    final rawAcc = rawBank['account_number']?.toString() ??
        rawBank['bank_account_number']?.toString() ??
        _s(emp['account_number']) ??
        _s(profile['account_number']) ??
        _s(emp['bank_account_number']) ??
        _s(profile['bank_account_number']);

    final rawPf = rawStat['pf_number']?.toString() ??
        _s(emp['pf_number']) ??
        _s(profile['pf_number']);

    final rawEsi = rawStat['esi_number']?.toString() ??
        _s(emp['esi_number']) ??
        _s(profile['esi_number']);

    final rawPan = rawStat['pan_number']?.toString() ??
        rawStat['pan']?.toString() ??
        _s(emp['pan_number']) ??
        _s(profile['pan_number']);

    final rawUan = rawStat['uan_number']?.toString() ??
        rawStat['uan']?.toString() ??
        _s(emp['uan_number']) ??
        _s(profile['uan_number']);

    final taxRegime = rawStat['tax_regime']?.toString() ??
        _s(emp['tax_regime']) ??
        _s(profile['tax_regime']);

    final bankName = rawBank['bank_name']?.toString() ??
        _s(emp['bank_name']) ??
        _s(profile['bank_name']);

    final branchName = rawBank['branch_name']?.toString() ??
        rawBank['bank_branch']?.toString() ??
        _s(emp['bank_branch']) ??
        _s(profile['branch_name']);

    final ifscCode = rawBank['ifsc_code']?.toString() ??
        rawBank['ifsc']?.toString() ??
        _s(emp['ifsc_code']) ??
        _s(profile['ifsc_code']);

    final accHolder = rawBank['account_holder_name']?.toString() ??
        _s(emp['account_holder_name']) ??
        _s(profile['account_holder_name']);

    PayrollStatutoryModel? payrollModel;
    if (rawBank.isNotEmpty || rawStat.isNotEmpty || rawAcc != null || rawPan != null || rawPf != null || rawEsi != null || rawUan != null || bankName != null) {
      payrollModel = PayrollStatutoryModel(
        bankName: bankName,
        branchName: branchName,
        accountNumber: rawAcc != null && rawAcc.length > 4 ? '•••• •••• ${rawAcc.substring(rawAcc.length - 4)}' : rawAcc,
        rawAccountNumber: rawAcc,
        ifscCode: ifscCode,
        accountHolderName: accHolder,
        panNumber: rawPan != null && rawPan.length > 4 ? '•••• •••• ${rawPan.substring(rawPan.length - 4)}' : rawPan,
        rawPanNumber: rawPan,
        uanNumber: rawUan != null && rawUan.length > 4 ? '•••• •••• ${rawUan.substring(rawUan.length - 4)}' : rawUan,
        rawUanNumber: rawUan,
        pfNumber: rawPf != null && rawPf.length > 4 ? '•••• •••• ${rawPf.substring(rawPf.length - 4)}' : rawPf,
        rawPfNumber: rawPf,
        esiNumber: rawEsi != null && rawEsi.length > 4 ? '•••• •••• ${rawEsi.substring(rawEsi.length - 4)}' : rawEsi,
        rawEsiNumber: rawEsi,
        taxRegime: taxRegime != null ? (taxRegime == 'OLD' ? 'OLD Regime' : 'NEW Regime (Sec 115BAC)') : null,
      );
    }

    EmergencyContactModel? contactModel;
    if (emergencyContact != null) {
      final name = emergencyContact['name']?.toString() ?? emergencyContact['contact_name']?.toString();
      final phone = emergencyContact['primary_phone']?.toString() ?? emergencyContact['phone']?.toString();
      final rel = emergencyContact['relationship']?.toString();
      if ((name != null && name.isNotEmpty) || (phone != null && phone.isNotEmpty)) {
        contactModel = EmergencyContactModel(
          name: name ?? '',
          relationship: rel ?? '',
          phone: phone ?? '',
        );
      }
    } else {
      contactModel = _mapEmergencyContact(profile, emp);
    }

    // ── Deduplicate & Resolve Authoritative Work Locations ──────────────
    List<ApprovedWorkLocation> deduplicatedLocations = [];
    if (assignedLocations != null && assignedLocations.isNotEmpty) {
      final Map<String, ApprovedWorkLocation> unique = {};
      for (final loc in assignedLocations) {
        final key = (loc.id != null && loc.id!.isNotEmpty)
            ? loc.id!
            : loc.name.trim().toLowerCase();
        if (!unique.containsKey(key)) {
          unique[key] = loc;
        } else if (loc.isPrimary && !unique[key]!.isPrimary) {
          unique[key] = loc;
        }
      }
      deduplicatedLocations = unique.values.toList();
      deduplicatedLocations.sort((a, b) => (b.isPrimary ? 1 : 0).compareTo(a.isPrimary ? 1 : 0));
    }

    ApprovedWorkLocation defaultApprovedLocation;
    if (deduplicatedLocations.isNotEmpty) {
      defaultApprovedLocation = deduplicatedLocations.firstWhere(
        (l) => l.isPrimary,
        orElse: () => deduplicatedLocations.first,
      );
    } else {
      defaultApprovedLocation = ApprovedWorkLocation(
        name: (campus.isNotEmpty && campus != '—') ? campus : 'Work Location',
        latitude: _d(_first(profile, emp, ['work_latitude', 'latitude'])) ?? 0.0,
        longitude: _d(_first(profile, emp, ['work_longitude', 'longitude'])) ?? 0.0,
        allowedRadiusMeters: _d(_first(profile, emp, [
              'allowed_radius_meters',
              'geofence_radius_meters',
              'geo_fence_radius_meters',
              'radius_meters',
              'radius'
            ])) ??
            0.0,
        accuracyRequirementMeters: 50.0,
      );
    }

    return UserModel(
      name: displayName.isNotEmpty ? displayName : 'Employee',
      firstName: firstName.isNotEmpty ? firstName : displayName.split(' ').first,
      employeeId: _s(emp['employee_code']) ?? _s(emp['id']) ?? '',
      employeeUuid: _s(emp['id']),
      companyUuid: _s(emp['company_id']),
      designation: designation,
      department: department,
      unit: unit,
      role: role ?? 'EMPLOYEE',
      machinePin: _first(profile, emp, ['machine_pin', 'pin', 'biometric_pin']) ?? '',
      campus: campus.isNotEmpty ? campus : defaultApprovedLocation.name,
      approvedLocation: defaultApprovedLocation,
      shiftStart: shiftStart,
      shiftEnd: shiftEnd,
      shiftName: shiftDisplay,
      leaveBalanceDays:
          _d(_first(profile, employment, ['leave_balance_days'])) ?? 0.0,
      reportsToId: reportsToId,
      reportsToName: reportsToName,
      companyId: _s(emp['organization_id']) ?? _s(emp['company_id']) ?? '',
      companyName: _first(emp, profile, ['organization_name', 'company_name', 'display_name', 'legal_name']) ??
          (_s(emp['company_name'])?.isNotEmpty == true ? _s(emp['company_name'])! : ''),
      companyLogoUrl: _first(emp, profile, ['organization_logo_url', 'company_logo_url', 'logo_url']),
      employmentType:
          _s(emp['employment_type'])?.replaceAll('_', ' ').toUpperCase() ??
              '',
      status: _s(emp['status']),
      joiningDate: joiningDate,
      personalEmail: personalEmail ?? authEmail ?? '',
      officeEmail: _s(emp['work_email']) ?? authEmail ?? '',
      contactNumber: phone,
      address: address,
      emergencyContact: contactModel,
      payrollStatutory: payrollModel,
      profileImage: _s(emp['avatar_url']) ?? authAvatarUrl,
      assignedLocations: deduplicatedLocations,
    );
  }

  static String _resolveAddress(Map<String, dynamic> profile, Map<String, dynamic> emp) {
    String formatAddrObj(dynamic addr) {
      if (addr is String) return addr.trim();
      if (addr is Map<String, dynamic>) {
        final l1 = addr['address_line1'] ?? addr['line1'] ?? addr['street'] ?? '';
        final l2 = addr['address_line2'] ?? addr['line2'] ?? '';
        final city = addr['city'] ?? '';
        final state = addr['state'] ?? '';
        final pin = addr['postal_code'] ?? addr['pincode'] ?? addr['zip'] ?? '';
        final parts = [l1, l2, city, state, pin].map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
      return '';
    }

    final curr = formatAddrObj(profile['current_address']);
    if (curr.isNotEmpty) return curr;

    final perm = formatAddrObj(profile['permanent_address']);
    if (perm.isNotEmpty) return perm;

    final addr = formatAddrObj(profile['address']).isNotEmpty
        ? formatAddrObj(profile['address'])
        : formatAddrObj(emp['address']);
    if (addr.isNotEmpty) return addr;

    final res = formatAddrObj(profile['residential_address']);
    if (res.isNotEmpty) return res;

    return '';
  }

  static EmergencyContactModel? _mapEmergencyContact(Map<String, dynamic> profile, Map<String, dynamic> emp) {
    final raw = profile['emergency_contact'] ?? emp['emergency_contact'];
    if (raw is Map<String, dynamic>) {
      final name = _s(raw['name']) ?? _s(raw['contact_name']) ?? '';
      final phone = _s(raw['phone']) ?? _s(raw['number']) ?? _s(raw['primary_phone']) ?? '';
      final rel = _s(raw['relationship']) ?? '';
      if (name.isNotEmpty || phone.isNotEmpty) {
        return EmergencyContactModel(
          name: name,
          relationship: rel,
          phone: phone,
        );
      }
    }
    final rawList = profile['emergency_contacts'] ?? emp['emergency_contacts'];
    if (rawList is List && rawList.isNotEmpty) {
      final first = rawList.first;
      if (first is Map<String, dynamic>) {
        final name = _s(first['name']) ?? _s(first['contact_name']) ?? '';
        final phone = _s(first['phone']) ?? _s(first['mobile']) ?? _s(first['primary_phone']) ?? '';
        final rel = _s(first['relationship']) ?? '';
        if (name.isNotEmpty || phone.isNotEmpty) {
          return EmergencyContactModel(
            name: name,
            relationship: rel,
            phone: phone,
          );
        }
      }
    }
    return null;
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map<String, dynamic> ? value : const {};

  static String? _s(dynamic v) => v?.toString();

  static double? _d(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  /// First non-empty string among [keys] checked in [primary] then [fallback].
  static String? _first(
    Map<String, dynamic> primary,
    Map<String, dynamic> fallback,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = primary[k] ?? fallback[k];
      if (v != null) {
        if (v is Map) {
          final extracted = v['name'] ?? v['title'] ?? v['department_name'] ?? v['designation_title'];
          if (extracted != null && extracted.toString().trim().isNotEmpty) {
            return extracted.toString().trim();
          }
        } else if (v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
    }
    return null;
  }

  static bool _looksLikeTime(String s) =>
      RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(s.trim());

  /// "14:30" / "14:30:00" → "02:30 PM"
  static String _formatTime(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 2) return raw;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return raw;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $suffix';
  }
}

