import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/user_service.dart';
import '../models/garment_models.dart';

class GarmentRepository extends ChangeNotifier {
  static final GarmentRepository instance = GarmentRepository._internal();
  GarmentRepository._internal();

  static const String _kOfflineAttKey = 'garment_offline_att_queue_v1';
  static const String _kOfflineProdKey = 'garment_offline_prod_queue_v1';

  bool isLoading = false;
  bool isEntitled = false;
  String? orgId;
  String currencyCode = 'INR';
  String? lastError;

  List<GarmentUnitModel> units = [];
  List<GarmentWorkerModel> workers = [];
  List<GarmentStyleModel> styles = [];
  List<GarmentOperationModel> operations = [];
  List<GarmentOrderModel> orders = [];
  List<GarmentRateCardModel> rateCards = [];
  List<GarmentProductionEntryModel> recentEntries = [];

  // Worker ESS data
  String workerWageMethod = 'Not Assigned';
  String workerPayFrequency = 'WEEKLY';
  double workerAdvanceBalance = 0.0;
  List<Map<String, dynamic>> myAllocations = [];
  List<GarmentPayrollLineModel> myPayslips = [];

  // Offline Queue counts
  int queuedAttendanceCount = 0;
  int queuedProductionCount = 0;

  SupabaseClient get _client => Supabase.instance.client;

  bool isSupervisorUser() {
    final role = UserService.instance.currentUser.role.toUpperCase();
    return role.contains('ADMIN') ||
        role.contains('HR') ||
        role.contains('MANAGER') ||
        role.contains('LEAD') ||
        role.contains('TL') ||
        role.contains('SUPERVISOR');
  }

  Future<String?> resolveActiveOrgId() async {
    final cached = UserService.instance.currentUser.companyId;
    if (cached.isNotEmpty) {
      orgId = cached;
      return cached;
    }
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final profile = await _client
          .from('user_profiles')
          .select('organization_id')
          .eq('auth_user_id', uid)
          .maybeSingle();
      final resolved = profile?['organization_id']?.toString();
      if (resolved != null && resolved.isNotEmpty) {
        orgId = resolved;
      }
      return resolved;
    } catch (_) {
      return orgId;
    }
  }

  Future<bool> checkEntitlement() async {
    final id = await resolveActiveOrgId();
    if (id == null || id.isEmpty) {
      isEntitled = false;
      notifyListeners();
      return false;
    }
    try {
      final row = await _client
          .from('organization_addon_entitlements')
          .select('is_enabled')
          .eq('organization_id', id)
          .eq('addon_key', 'garment_workforce')
          .maybeSingle();
      isEntitled = row?['is_enabled'] == true;
    } catch (e) {
      lastError = e.toString();
    }
    await _refreshOfflineCounts();
    notifyListeners();
    return isEntitled;
  }

  Future<void> _refreshOfflineCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final attRaw = prefs.getStringList(_kOfflineAttKey) ?? [];
      final prodRaw = prefs.getStringList(_kOfflineProdKey) ?? [];
      queuedAttendanceCount = attRaw.length;
      queuedProductionCount = prodRaw.length;
    } catch (_) {}
  }

  Future<void> loadSupervisorWorkspace() async {
    isLoading = true;
    lastError = null;
    notifyListeners();
    try {
      final ok = await checkEntitlement();
      if (!ok || orgId == null) {
        isLoading = false;
        notifyListeners();
        return;
      }

      final id = orgId!;
      final results = await Future.wait<dynamic>([
        _client.from('garment_org_settings').select('currency_code').eq('organization_id', id).maybeSingle(),
        _client.from('garment_production_units').select('*').eq('organization_id', id).order('unit_name'),
        _client.from('garment_worker_profiles').select('*').eq('organization_id', id).eq('is_active', true),
        _client.from('employees').select('id, employee_code, display_name, first_name, last_name').eq('organization_id', id),
        _client.from('garment_styles').select('*').eq('organization_id', id).eq('is_active', true),
        _client.from('garment_operations').select('*').eq('organization_id', id).eq('is_active', true).order('sequence_order'),
        _client.from('garment_production_orders').select('*').eq('organization_id', id).order('start_date', ascending: false),
        _client.from('garment_piece_rate_cards').select('*').eq('organization_id', id).eq('is_active', true),
        _client.from('garment_production_entries').select('*').eq('organization_id', id).order('created_at', ascending: false).limit(25),
      ]);

      final settingsRow = results[0] as Map<String, dynamic>?;
      if (settingsRow != null && settingsRow['currency_code'] != null) {
        currencyCode = settingsRow['currency_code'].toString();
      }

      units = (results[1] as List).map((e) => GarmentUnitModel.fromJson(Map<String, dynamic>.from(e))).toList();

      final empMap = <String, Map<String, dynamic>>{};
      for (final raw in (results[3] as List)) {
        final m = Map<String, dynamic>.from(raw);
        empMap[m['id'].toString()] = m;
      }

      workers = (results[2] as List).map((raw) {
        final w = Map<String, dynamic>.from(raw);
        final eid = w['employee_id']?.toString() ?? '';
        final emp = empMap[eid];
        final name = emp?['display_name']?.toString().trim().isNotEmpty == true
            ? emp!['display_name'].toString()
            : '${emp?['first_name'] ?? ''} ${emp?['last_name'] ?? ''}'.trim();
        return GarmentWorkerModel(
          id: w['id']?.toString() ?? '',
          employeeId: eid,
          displayName: name.isNotEmpty ? name : eid,
          employeeCode: emp?['employee_code']?.toString() ?? '',
          workerCategory: w['worker_category']?.toString() ?? 'PIECE_RATE',
          skillGrade: w['skill_grade']?.toString() ?? 'GRADE_B',
          skillWeightage: (w['skill_weightage'] as num?)?.toDouble() ?? 1.0,
          primaryUnitId: w['primary_unit_id']?.toString(),
          primaryTeamId: w['primary_team_id']?.toString(),
          defaultWageMethod: w['default_wage_method']?.toString() ?? 'PIECE_RATE',
          defaultPaymentFrequency: w['default_payment_frequency']?.toString() ?? 'WEEKLY',
        );
      }).toList();

      styles = (results[4] as List).map((e) => GarmentStyleModel.fromJson(Map<String, dynamic>.from(e))).toList();
      operations = (results[5] as List).map((e) => GarmentOperationModel.fromJson(Map<String, dynamic>.from(e))).toList();
      orders = (results[6] as List).map((e) => GarmentOrderModel.fromJson(Map<String, dynamic>.from(e))).toList();
      rateCards = (results[7] as List).map((e) => GarmentRateCardModel.fromJson(Map<String, dynamic>.from(e))).toList();
      recentEntries = (results[8] as List).map((e) => GarmentProductionEntryModel.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      lastError = e.toString();
    } finally {
      await _refreshOfflineCounts();
      isLoading = false;
      notifyListeners();
    }
  }

  double resolveEstimatedRate(String operationId, {String? styleId, String? orderId, String? unitId, String? skillGrade}) {
    final matching = rateCards.where((c) => c.operationId == operationId).toList();
    if (matching.isEmpty) return 0.0;
    matching.sort((a, b) {
      int score(GarmentRateCardModel r) =>
          (r.orderId == orderId ? 8 : 0) +
          (r.styleId == styleId ? 4 : 0) +
          (r.productionUnitId == unitId ? 2 : 0) +
          (r.skillGrade == skillGrade ? 1 : 0);
      return score(b).compareTo(score(a));
    });
    return matching.first.ratePerUnit;
  }

  Future<bool> submitOrQueueAttendanceBatch(List<Map<String, dynamic>> rows) async {
    final id = orgId ?? await resolveActiveOrgId();
    if (id == null || rows.isEmpty) return false;
    try {
      await _client.rpc('fn_submit_garment_floor_batch', params: {
        'p_organization_id': id,
        'p_attendance_items': rows,
        'p_production_items': [],
      });
      await loadSupervisorWorkspace();
      return true;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_kOfflineAttKey) ?? [];
      for (final r in rows) {
        existing.add(jsonEncode(r));
      }
      await prefs.setStringList(_kOfflineAttKey, existing);
      await _refreshOfflineCounts();
      notifyListeners();
      return false;
    }
  }

  Future<bool> submitOrQueueProductionEntry(Map<String, dynamic> entryPayload) async {
    final id = orgId ?? await resolveActiveOrgId();
    if (id == null) return false;
    try {
      await _client.rpc('fn_submit_garment_floor_batch', params: {
        'p_organization_id': id,
        'p_attendance_items': [],
        'p_production_items': [entryPayload],
      });
      await loadSupervisorWorkspace();
      return true;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_kOfflineProdKey) ?? [];
      existing.add(jsonEncode(entryPayload));
      await prefs.setStringList(_kOfflineProdKey, existing);
      await _refreshOfflineCounts();
      notifyListeners();
      return false;
    }
  }

  Future<int> syncOfflineQueue() async {
    final id = orgId ?? await resolveActiveOrgId();
    if (id == null) return 0;
    final prefs = await SharedPreferences.getInstance();
    final attRaw = prefs.getStringList(_kOfflineAttKey) ?? [];
    final prodRaw = prefs.getStringList(_kOfflineProdKey) ?? [];
    if (attRaw.isEmpty && prodRaw.isEmpty) return 0;

    final attItems = attRaw.map((s) => Map<String, dynamic>.from(jsonDecode(s))).toList();
    final prodItems = prodRaw.map((s) => Map<String, dynamic>.from(jsonDecode(s))).toList();

    await _client.rpc('fn_submit_garment_floor_batch', params: {
      'p_organization_id': id,
      'p_attendance_items': attItems,
      'p_production_items': prodItems,
    });

    await prefs.remove(_kOfflineAttKey);
    await prefs.remove(_kOfflineProdKey);
    final count = attItems.length + prodItems.length;
    await loadSupervisorWorkspace();
    return count;
  }

  Future<void> loadWorkerSelfService() async {
    isLoading = true;
    notifyListeners();
    try {
      final ok = await checkEntitlement();
      final empUuid = UserService.instance.currentUser.employeeUuid;
      if (!ok || orgId == null || empUuid == null || empUuid.isEmpty) {
        isLoading = false;
        notifyListeners();
        return;
      }

      final id = orgId!;
      final res = await Future.wait<dynamic>([
        _client.from('garment_wage_assignments').select('*').eq('organization_id', id).eq('employee_id', empUuid).eq('is_active', true).order('effective_from', ascending: false).limit(1),
        _client.from('garment_operations').select('*').eq('organization_id', id),
        _client.from('garment_production_allocations').select('*').eq('organization_id', id).eq('employee_id', empUuid).order('work_date', ascending: false).limit(40),
        _client.from('garment_advances_ledger').select('balance_remaining').eq('organization_id', id).eq('employee_id', empUuid).eq('status', 'APPROVED'),
        _client.from('garment_payroll_lines').select('*').eq('organization_id', id).eq('employee_id', empUuid).eq('worker_payslip_published', true).order('created_at', ascending: false),
      ]);

      final assignList = res[0] as List;
      if (assignList.isNotEmpty) {
        final a = Map<String, dynamic>.from(assignList.first);
        workerWageMethod = a['wage_method']?.toString() ?? 'PIECE_RATE';
        workerPayFrequency = a['payment_frequency']?.toString() ?? 'WEEKLY';
      }

      operations = (res[1] as List).map((e) => GarmentOperationModel.fromJson(Map<String, dynamic>.from(e))).toList();
      myAllocations = (res[2] as List).map((e) => Map<String, dynamic>.from(e)).toList();

      double advSum = 0.0;
      for (final raw in (res[3] as List)) {
        advSum += (raw['balance_remaining'] as num?)?.toDouble() ?? 0.0;
      }
      workerAdvanceBalance = advSum;

      myPayslips = (res[4] as List).map((e) => GarmentPayrollLineModel.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      lastError = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> raiseWorkerDispute({required String reason, String? targetAllocationId}) async {
    final id = orgId ?? await resolveActiveOrgId();
    final empUuid = UserService.instance.currentUser.employeeUuid;
    if (id == null || empUuid == null || empUuid.isEmpty) {
      throw Exception('Missing employee profile context');
    }

    await _client.from('garment_correction_requests').insert({
      'organization_id': id,
      'request_type': 'WORKER_DISPUTE',
      'target_table': targetAllocationId != null ? 'garment_production_allocations' : 'garment_payroll_lines',
      'target_record_id': targetAllocationId ?? (myPayslips.isNotEmpty ? myPayslips.first.id : empUuid),
      'work_date': DateTime.now().toIso8601String().split('T').first,
      'employee_id': empUuid,
      'requested_by_employee_id': empUuid,
      'reason': reason,
      'requested_changes_json': {'source': 'FLUTTER_WORKER_ESS'},
      'status': 'PENDING',
    });
  }
}

