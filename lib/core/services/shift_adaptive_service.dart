import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';
import 'user_service.dart';

/// Represents an authoritative company shift definition
class CompanyShift {
  final String id;
  final String organizationId;
  final String name;
  final String code;
  final String startTime; // "HH:mm:ss" or "HH:mm"
  final String endTime;   // "HH:mm:ss" or "HH:mm"
  final int graceEntryMinutes;
  final int graceExitMinutes;
  final bool isOvernight;
  final bool isActive;

  const CompanyShift({
    required this.id,
    required this.organizationId,
    required this.name,
    this.code = '',
    required this.startTime,
    required this.endTime,
    this.graceEntryMinutes = 15,
    this.graceExitMinutes = 15,
    this.isOvernight = false,
    this.isActive = true,
  });

  factory CompanyShift.fromJson(Map<String, dynamic> json) {
    return CompanyShift(
      id: json['id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['shift_name']?.toString() ?? 'General Shift',
      code: json['code']?.toString() ?? json['shift_code']?.toString() ?? '',
      startTime: json['start_time']?.toString() ?? '09:00:00',
      endTime: json['end_time']?.toString() ?? '18:00:00',
      graceEntryMinutes: (json['grace_entry_minutes'] as num?)?.toInt() ?? 15,
      graceExitMinutes: (json['grace_exit_minutes'] as num?)?.toInt() ?? 15,
      isOvernight: json['is_overnight'] == true,
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'organization_id': organizationId,
    'name': name,
    'code': code,
    'start_time': startTime,
    'end_time': endTime,
    'grace_entry_minutes': graceEntryMinutes,
    'grace_exit_minutes': graceExitMinutes,
    'is_overnight': isOvernight,
    'is_active': isActive,
  };

  /// Converts "08:30:00" to "08:30 AM"
  String get formattedStart => _formatTime(startTime);

  /// Converts "17:30:00" to "05:30 PM"
  String get formattedEnd => _formatTime(endTime);

  /// "08:30 AM – 05:30 PM"
  String get formattedRange => '$formattedStart – $formattedEnd';

  static String _formatTime(String raw) {
    if (raw.toUpperCase().contains('AM') || raw.toUpperCase().contains('PM')) {
      return raw.trim();
    }
    final parts = raw.trim().split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        final suffix = h >= 12 ? 'PM' : 'AM';
        final h12 = h % 12 == 0 ? 12 : h % 12;
        return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $suffix';
      }
    }
    return raw;
  }

  /// Start time in minutes from midnight (0–1439)
  int get startMinutesFromMidnight {
    final parts = startTime.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return (h * 60) + m;
    }
    return 540; // Default 09:00 AM
  }

  /// End time in minutes from midnight (0–1439)
  int get endMinutesFromMidnight {
    final parts = endTime.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return (h * 60) + m;
    }
    return 1080; // Default 18:00
  }

  /// Returns clean duration label (e.g. "9 hrs" or "8.5 hrs")
  String get formattedDuration {
    final start = startMinutesFromMidnight;
    var end = endMinutesFromMidnight;
    if (end < start || isOvernight) {
      end += 1440;
    }
    final diffMins = end - start;
    final hours = diffMins / 60.0;
    if (hours == hours.roundToDouble()) {
      return '${hours.toInt()} hrs';
    }
    return '${hours.toStringAsFixed(1)} hrs';
  }
}

/// Service that auto-detects nearest company shifts and manages manual overrides
class ShiftAdaptiveService {
  static final ShiftAdaptiveService instance = ShiftAdaptiveService._internal();
  ShiftAdaptiveService._internal();

  static const String _kShiftCacheKey = 'sp_cached_company_shifts_v1';
  List<CompanyShift> _cachedShifts = [];

  List<CompanyShift> get cachedShifts => List.unmodifiable(_cachedShifts);

  /// Fetches all active shifts for the company, falling back to local storage
  Future<List<CompanyShift>> getCompanyShifts({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedShifts.isNotEmpty) {
      return _cachedShifts;
    }

    // 1. Load from local cache first for instant UI response
    if (_cachedShifts.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawJson = prefs.getString(_kShiftCacheKey);
        if (rawJson != null && rawJson.isNotEmpty) {
          final list = jsonDecode(rawJson) as List<dynamic>;
          _cachedShifts = list.map((e) => CompanyShift.fromJson(e as Map<String, dynamic>)).toList();
        }
      } catch (e) {
        secureLog('[ShiftAdaptive] Local shift cache read notice: $e');
      }
    }

    // 2. Fetch fresh shifts from Supabase
    if (SupabaseConfig.isConfigured) {
      try {
        final user = UserService.instance.currentUser;
        final orgId = user.organizationId?.isNotEmpty == true
            ? user.organizationId!
            : (user.companyId.isNotEmpty ? user.companyId : null);

        var query = Supabase.instance.client
            .from('shifts')
            .select('*')
            .eq('is_active', true);

        if (orgId != null && orgId.isNotEmpty) {
          query = query.eq('organization_id', orgId);
        }

        final response = await query.order('start_time', ascending: true);
        final freshShifts = (response as List<dynamic>)
            .map((item) => CompanyShift.fromJson(item as Map<String, dynamic>))
            .toList();

        if (freshShifts.isNotEmpty) {
          _cachedShifts = freshShifts;
          // Persist to local storage for factory gate offline resiliency
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kShiftCacheKey, jsonEncode(freshShifts.map((s) => s.toJson()).toList()));
          } catch (_) {}
          secureLog('[ShiftAdaptive] Loaded ${_cachedShifts.length} active company shifts from database.');
        }
      } catch (e) {
        secureLog('[ShiftAdaptive] Supabase shifts query notice: $e');
      }
    }

    // 3. Fallback: If company has no shifts in DB, generate standard factory rotational shifts
    if (_cachedShifts.isEmpty) {
      _cachedShifts = _createDefaultFactoryShifts();
    }

    return _cachedShifts;
  }

  /// Authoritative Shift Resolution implementing the shared 6-Tier Hierarchy:
  /// - Tier 1: Approved Employee-Specific Assignment (employee_shift_assignments)
  /// - Tier 2: Approved Shift Roster Rotation (shift_rosters)
  /// - Tier 5: Automatic Adaptive Inference using closest window to current punch time
  Future<CompanyShift> resolveAdaptiveShift({
    required List<CompanyShift> companyShifts,
    DateTime? referenceTime,
  }) async {
    final now = referenceTime ?? DateTime.now();
    final todayDate =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final user = UserService.instance.currentUser;
    final empUuid = user.employeeUuid;

    if (SupabaseConfig.isConfigured && empUuid != null && empUuid.isNotEmpty) {
      final client = Supabase.instance.client;

      // Tier 1: Check employee_shift_assignments
      try {
        final assignments = await client
            .from('employee_shift_assignments')
            .select('shift_id, effective_from, effective_to, valid_from, valid_to')
            .eq('employee_id', empUuid)
            .lte('effective_from', todayDate)
            .order('effective_from', ascending: false)
            .limit(1);

        if (assignments.isNotEmpty) {
          final assigned = Map<String, dynamic>.from(assignments[0] as Map);
          final toDate = (assigned['effective_to'] ?? assigned['valid_to'])?.toString();
          if (toDate == null || toDate.isEmpty || toDate.compareTo(todayDate) >= 0) {
            final shiftId = assigned['shift_id']?.toString();
            final match = companyShifts.firstWhere(
              (s) => s.id == shiftId,
              orElse: () => CompanyShift.fromJson(assigned),
            );
            if (match.id.isNotEmpty) {
              secureLog('[ShiftAdaptive] Inferred Tier 1 assigned shift: ${match.name} (${match.code})');
              return match;
            }
          }
        }
      } catch (e) {
        secureLog('[ShiftAdaptive] Tier 1 assignment query notice: $e');
      }

      // Tier 2: Check shift_rosters for today
      try {
        final rosters = await client
            .from('shift_rosters')
            .select('shift_id, shift_code, shift_name')
            .eq('employee_id', empUuid)
            .eq('roster_date', todayDate)
            .limit(1);

        if (rosters.isNotEmpty) {
          final roster = Map<String, dynamic>.from(rosters[0] as Map);
          final shiftId = roster['shift_id']?.toString();
          final shiftCode = roster['shift_code']?.toString();
          final match = companyShifts.firstWhere(
            (s) => (shiftId != null && s.id == shiftId) || (shiftCode != null && s.code == shiftCode),
            orElse: () => companyShifts.first,
          );
          secureLog('[ShiftAdaptive] Inferred Tier 2 roster shift: ${match.name} (${match.code})');
          return match;
        }
      } catch (e) {
        secureLog('[ShiftAdaptive] Tier 2 roster query notice: $e');
      }
    }

    // Tier 5: Fall back to deterministic proximity window matching
    return detectNearestShift(shifts: companyShifts, referenceTime: now);
  }

  /// Automatically deduces the nearest shift window based on current clock time
  CompanyShift detectNearestShift({
    required List<CompanyShift> shifts,
    DateTime? referenceTime,
  }) {
    if (shifts.isEmpty) {
      return _createDefaultShiftFromCurrentUser();
    }

    final now = referenceTime ?? DateTime.now();
    final nowMinutes = (now.hour * 60) + now.minute;

    CompanyShift nearestShift = shifts.first;
    int smallestDiff = 1440; // Max difference in a 24h clock

    for (final shift in shifts) {
      final shiftMins = shift.startMinutesFromMidnight;
      // Circular 24-hour distance calculation
      int diff = (nowMinutes - shiftMins).abs();
      if (diff > 720) {
        diff = 1440 - diff;
      }

      if (diff < smallestDiff) {
        smallestDiff = diff;
        nearestShift = shift;
      }
    }

    return nearestShift;
  }

  CompanyShift _createDefaultShiftFromCurrentUser() {
    final user = UserService.instance.currentUser;
    return CompanyShift(
      id: '',
      organizationId: user.organizationId ?? user.companyId,
      name: user.shiftStart.isNotEmpty ? 'General Shift' : 'Factory Shift',
      code: 'GEN-01',
      startTime: user.shiftStart.isNotEmpty ? user.shiftStart : '09:00:00',
      endTime: user.shiftEnd.isNotEmpty ? user.shiftEnd : '18:00:00',
    );
  }

  List<CompanyShift> _createDefaultFactoryShifts() {
    final user = UserService.instance.currentUser;
    final orgId = user.organizationId ?? user.companyId;
    return [
      CompanyShift(
        id: 'shift-gen-corp',
        organizationId: orgId,
        name: 'General Day Shift (Corporate)',
        code: 'GEN-10',
        startTime: '09:30:00',
        endTime: '18:30:00',
        graceEntryMinutes: 15,
      ),
      CompanyShift(
        id: 'shift-rot-1',
        organizationId: orgId,
        name: 'General Day Shift 1',
        code: 'GEN-01',
        startTime: '08:30:00',
        endTime: '17:30:00',
        graceEntryMinutes: 15,
      ),
      CompanyShift(
        id: 'shift-rot-2',
        organizationId: orgId,
        name: 'General Corporate Shift 2',
        code: 'GEN-02',
        startTime: '09:00:00',
        endTime: '18:00:00',
        graceEntryMinutes: 15,
      ),
      CompanyShift(
        id: 'shift-rot-3',
        organizationId: orgId,
        name: 'General Day Shift 3',
        code: 'GEN-03',
        startTime: '09:00:00',
        endTime: '16:30:00',
        graceEntryMinutes: 15,
      ),
      CompanyShift(
        id: 'shift-rot-morn',
        organizationId: orgId,
        name: 'Factory Shift 1 (Morning)',
        code: 'S1-MORN',
        startTime: '06:00:00',
        endTime: '14:00:00',
        graceEntryMinutes: 30,
      ),
      CompanyShift(
        id: 'shift-rot-eve',
        organizationId: orgId,
        name: 'Factory Shift 2 (Evening)',
        code: 'S2-EVE',
        startTime: '14:00:00',
        endTime: '22:00:00',
        graceEntryMinutes: 30,
      ),
      CompanyShift(
        id: 'shift-rot-ngt',
        organizationId: orgId,
        name: 'Factory Shift 3 (Night)',
        code: 'S3-NGT',
        startTime: '22:00:00',
        endTime: '06:00:00',
        isOvernight: true,
        graceEntryMinutes: 30,
      ),
    ];
  }
}
