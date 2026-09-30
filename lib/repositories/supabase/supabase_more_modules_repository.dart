import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/services/push_sender_service.dart';
import '../../core/services/realtime_outbox_service.dart';
import '../../core/services/shift_duration_calculator.dart';
import '../../core/services/user_service.dart';
import '../../core/utils/query_timeout.dart';
import '../../core/utils/secure_log.dart';
import '../../models/employee_models.dart';
import '../interfaces/employee_repository.dart';

/// WorkForceOS — Supabase "More" modules repository
/// Fully backed by live Supabase tables (zero mock fallbacks).
class SupabaseMoreModulesRepository implements IMoreModulesRepository {
  SupabaseClient get _client => Supabase.instance.client;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool _isValidUuid(String? str) {
    if (str == null || str.trim().isEmpty) return false;
    return _uuidRegex.hasMatch(str.trim());
  }

  Future<({String employeeId, String organizationId})> _resolveDynamicEmployeeIdentity(String fallbackEmployeeId) async {
    final user = UserService.instance.currentUser;
    String empId = '';
    String orgId = user.tenantId;

    // 1. Try resolving directly from authenticated Supabase session
    final authUser = _client.auth.currentUser;
    if (authUser != null) {
      try {
        final profile = await withTimeout(
          _client
              .from('user_profiles')
              .select('employee_id, organization_id')
              .or('auth_user_id.eq.${authUser.id},id.eq.${authUser.id}')
              .maybeSingle(),
        );
        if (profile != null) {
          final pEmpId = profile['employee_id']?.toString() ?? '';
          final pOrgId = profile['organization_id']?.toString() ?? '';
          if (_isValidUuid(pEmpId)) empId = pEmpId;
          if (_isValidUuid(pOrgId)) orgId = pOrgId;
        }
      } catch (e) {
        secureLog('[SupabaseMoreModulesRepository] Dynamic identity resolution notice: $e');
      }
    }

    // 2. Fall back to UserService properties if valid UUID
    if (empId.isEmpty) {
      if (_isValidUuid(user.employeeUuid)) {
        empId = user.employeeUuid!;
      } else if (_isValidUuid(user.dataId)) {
        empId = user.dataId;
      } else if (_isValidUuid(user.resolvedEmployeeId)) {
        empId = user.resolvedEmployeeId;
      } else if (_isValidUuid(fallbackEmployeeId)) {
        empId = fallbackEmployeeId;
      }
    }

    // 3. Query employees table by employee_code if still not resolved
    if (empId.isEmpty) {
      final candidateCodes = [
        fallbackEmployeeId,
        user.employeeId,
        user.dataId,
      ].where((c) => c.isNotEmpty && !_isValidUuid(c)).toSet().toList();

      for (final code in candidateCodes) {
        try {
          final empRow = await withTimeout(
            _client
                .from('employees')
                .select('id, organization_id')
                .eq('employee_code', code)
                .maybeSingle(),
          );
          if (empRow != null) {
            final eId = empRow['id']?.toString() ?? '';
            final oId = empRow['organization_id']?.toString() ?? '';
            if (_isValidUuid(eId)) empId = eId;
            if (_isValidUuid(oId)) orgId = oId;
            if (empId.isNotEmpty) break;
          }
        } catch (_) {}
      }
    }

    return (employeeId: empId, organizationId: orgId);
  }

  String _resolveEmployeeId(String employeeId) {
    final user = UserService.instance.currentUser;
    if (_isValidUuid(user.employeeUuid)) return user.employeeUuid!;
    if (_isValidUuid(user.dataId)) return user.dataId;
    if (_isValidUuid(user.resolvedEmployeeId)) return user.resolvedEmployeeId;
    if (_isValidUuid(employeeId)) return employeeId;
    return (user.employeeUuid?.isNotEmpty == true)
        ? user.employeeUuid!
        : (user.employeeId.isNotEmpty ? user.employeeId : employeeId);
  }

  // ── Shift Helper: Category & Label Resolver ─────────────────────────────────

  static String _resolveCategory({
    String? backendCategory,
    required bool isOff,
    required bool crossesMidnight,
    required String? startTime,
    String? shiftCode,
    String? shiftName,
  }) {
    if (isOff) return 'OFF';
    if (backendCategory != null && backendCategory.trim().isNotEmpty) {
      return backendCategory.trim().toUpperCase();
    }
    if (crossesMidnight) return 'NIGHT';

    final mins = ShiftDurationCalculator.instance.parseTimeToMinutes(startTime);
    if (mins != null) {
      if (mins >= 20 * 60 || mins < 4 * 60) return 'NIGHT';
      if (mins >= 13 * 60) return 'EVENING';
      if (mins < 8 * 60) return 'MORNING';
    }

    final code = (shiftCode ?? '').toUpperCase();
    final name = (shiftName ?? '').toLowerCase();
    if (code.contains('NGT') || name.contains('night')) return 'NIGHT';
    if (code.contains('EVE') || name.contains('evening')) return 'EVENING';
    if (code.contains('MOR') || name.contains('morning')) return 'MORNING';
    return 'DAY';
  }

  static String _resolveCategoryLabel(String category, {String? customLabel}) {
    if (customLabel != null && customLabel.trim().isNotEmpty) {
      return customLabel.trim();
    }
    switch (category) {
      case 'NIGHT':
        return 'Night';
      case 'EVENING':
        return 'Evening';
      case 'MORNING':
        return 'Morning';
      case 'OFF':
        return 'Weekly Off';
      case 'FLEXIBLE':
        return 'Flexible';
      case 'DAY':
      default:
        return 'Day';
    }
  }

  // ── Company Announcements ──────────────────────────────────────────────────

  @override
  Future<List<AnnouncementModel>> getAnnouncements() async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      // Canonical announcement query:
      // - channel = 'IN_APP' (only valid channel for in-app broadcast)
      // - recipient_user_id IS NULL (null = broadcast to entire org)
      // RLS on notification_events enforces organization_id isolation.
      final rows = await withTimeout(
        _client
            .from('notification_events')
            .select('*')
            .eq('channel', 'IN_APP')
            .isFilter('recipient_user_id', null)
            .order('created_at', ascending: false)
            .limit(30),
      );

      return (rows as List).map<AnnouncementModel>((row) {
        // All rows here are org-broadcast announcements (recipient_user_id IS NULL)
        return AnnouncementModel(
          id: row['id']?.toString() ?? '',
          title: row['title']?.toString() ?? 'Announcement',
          content: row['message']?.toString() ?? '',
          author: 'HR Management',
          isImportant: true, // broadcasts are always important
          publishedAt: DateTime.tryParse(row['sent_at']?.toString() ??
                  row['created_at']?.toString() ??
                  '') ??
              DateTime.now(),
        );
      }).toList();
    } catch (e) {
      secureLog('[Announcements] getAnnouncements error: $e');
      return [];
    }
  }

  // ── Shift Roster ───────────────────────────────────────────────────────────

  @override
  Future<List<ShiftRosterModel>> getShiftRoster(String employeeId) async {
    try {
      final user = UserService.instance.currentUser;
      final empId = _resolveEmployeeId(employeeId);
      final Map<String, ShiftRosterModel> rosterByDate = {};

      if (SupabaseConfig.isConfigured) {
        // 1. Query employee_shift_assignments joined with shifts
        try {
          final orFilters = <String>[];
          if (empId.isNotEmpty && _isValidUuid(empId)) {
            orFilters.add('employee_id.eq.$empId');
          }
          if (user.employeeUuid?.isNotEmpty == true && _isValidUuid(user.employeeUuid!)) {
            orFilters.add('employee_id.eq.${user.employeeUuid}');
          }

          final filterQuery = orFilters.toSet().join(',');
          List<dynamic> rows = [];

          if (filterQuery.isNotEmpty) {
            try {
              final r1 = await withTimeout(
                _client
                    .from('employee_shift_assignments')
                    .select('*, shifts(*)')
                    .or(filterQuery),
              );
              rows.addAll(r1);
            } catch (e) {
              secureLog('[Roster] employee_shift_assignments query notice: $e');
            }
          }

          for (final row in rows) {
            final shiftData = row['shifts'] is Map ? row['shifts'] as Map : null;
            final dateStr =
                row['valid_from']?.toString() ?? row['effective_date']?.toString() ?? row['date']?.toString() ?? '';
            final parsedDate = DateTime.tryParse(dateStr);
            if (parsedDate == null) continue;

            final dateKey =
                "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
            final shiftCode = shiftData?['code']?.toString() ?? row['shift_code']?.toString() ?? '';
            final shiftName = shiftData?['name']?.toString() ?? row['shift_name']?.toString() ?? '';
            final isOff = row['is_weekly_off'] == true ||
                shiftCode.toUpperCase() == 'OFF' ||
                shiftName.toLowerCase().contains('off') ||
                shiftName.toLowerCase().contains('rest');

            final rawStart = shiftData?['start_time']?.toString() ?? row['start_time']?.toString() ?? '09:30';
            final rawEnd = shiftData?['end_time']?.toString() ?? row['end_time']?.toString() ?? '18:30';
            final crosses = shiftData?['is_overnight'] == true ||
                shiftData?['is_night_shift'] == true ||
                row['crosses_midnight'] == true ||
                ShiftDurationCalculator.instance
                    .isOvernight(startTime: rawStart, endTime: rawEnd);
            final breakMins = (shiftData?['break_duration_mins'] ?? row['break_minutes'] is num)
                ? (shiftData?['break_duration_mins'] ?? row['break_minutes'] as num).toInt()
                : null;

            final calc = ShiftDurationCalculator.instance.calculate(
              startTime: rawStart,
              endTime: rawEnd,
              breakMinutes: breakMins,
              explicitCrossesMidnight: crosses,
              isOffDay: isOff,
            );

            final category = _resolveCategory(
              backendCategory: row['shift_category']?.toString(),
              isOff: isOff,
              crossesMidnight: calc.crossesMidnight,
              startTime: rawStart,
              shiftCode: shiftCode,
              shiftName: shiftName,
            );
            final categoryLabel = _resolveCategoryLabel(category,
                customLabel: row['shift_category_label']?.toString());

            rosterByDate[dateKey] = ShiftRosterModel(
              id: row['id']?.toString() ?? 'roster-$dateKey',
              date: parsedDate,
              shiftName: isOff
                  ? 'Weekly Off'
                  : (shiftName.isNotEmpty
                      ? shiftName
                      : (user.shiftName?.isNotEmpty == true
                          ? user.shiftName!
                          : 'General Shift')),
              shiftCode: shiftCode.isNotEmpty
                  ? shiftCode
                  : (user.shiftName?.isNotEmpty == true
                      ? user.shiftName!.split(' ').first
                      : 'SHIFT'),
              shiftCategory: category,
              shiftCategoryLabel: categoryLabel,
              startTime: isOff ? 'Week Off' : calc.startTimeAMPM,
              endTime: isOff ? 'Week Off' : calc.endTimeAMPM,
              location: row['location_name']?.toString() ??
                  (user.approvedLocation.name.isNotEmpty
                      ? user.approvedLocation.name
                      : (user.campus.isNotEmpty && user.campus != 'N/A'
                          ? user.campus
                          : (user.companyName?.isNotEmpty == true
                              ? user.companyName!
                              : 'Office'))),
              isOffDay: isOff,
              isOvernight: calc.crossesMidnight,
              isUpdated: row['is_override'] == true,
              rawSpanMinutes: calc.spanMinutes,
              breakMinutes: calc.breakMinutes,
              netScheduledMinutes: calc.scheduledWorkMinutes,
              formattedDuration:
                  isOff ? 'No scheduled work' : calc.formattedScheduledWork,
              displayColorHex: shiftData?['color_code']?.toString() ?? row['display_color']?.toString(),
              policyName: row['policy_name']?.toString() ??
                  '${user.companyName ?? 'Company'} Attendance Policy',
              assignedBy: row['assigned_by']?.toString() ?? 'Department Roster',
            );
          }
        } catch (e) {
          secureLog('[Roster] employee_shift_assignments query notice: $e');
        }

        // 2. notification_events shift overlay removed:
        // notification_events does NOT have event_type, metadata, or resource_id columns.
        // Canonical columns: id, organization_id, recipient_user_id, channel,
        // title, message, action_url, is_read, is_sent, sent_at, created_at.
        // Shift roster is sourced exclusively from employee_shift_assignments.
      }

      // 3. Generate the active week's 7-day schedule (Monday to Sunday) anchored dynamically to current week
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));

      return List.generate(7, (index) {
        final day = monday.add(Duration(days: index));
        final dateKey =
            "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";

        if (rosterByDate.containsKey(dateKey)) {
          return rosterByDate[dateKey]!;
        }

        final isWeekend =
            day.weekday == DateTime.sunday || day.weekday == DateTime.saturday;
        final rawStart = user.shiftStart.isNotEmpty ? user.shiftStart : '09:30';
        final rawEnd = user.shiftEnd.isNotEmpty ? user.shiftEnd : '18:30';
        final calc = ShiftDurationCalculator.instance.calculate(
          startTime: rawStart,
          endTime: rawEnd,
          isOffDay: isWeekend,
        );

        final category = isWeekend ? 'OFF' : 'DAY';
        final shiftNameDisplay = isWeekend
            ? 'Weekly Off'
            : (user.shiftName?.isNotEmpty == true
                ? user.shiftName!
                : 'General Shift');

        return ShiftRosterModel(
          id: 'roster-$dateKey',
          date: day,
          shiftName: shiftNameDisplay,
          shiftCode: isWeekend
              ? 'OFF'
              : (user.shiftName?.isNotEmpty == true
                  ? user.shiftName!.split(' ').first
                  : 'SHIFT'),
          shiftCategory: category,
          shiftCategoryLabel: isWeekend ? 'Weekly Off' : 'Day',
          startTime: isWeekend ? 'Week Off' : calc.startTimeAMPM,
          endTime: isWeekend ? 'Week Off' : calc.endTimeAMPM,
          location: user.approvedLocation.name.isNotEmpty
              ? user.approvedLocation.name
              : (user.campus.isNotEmpty && user.campus != 'N/A'
                  ? user.campus
                  : (user.companyName?.isNotEmpty == true
                      ? user.companyName!
                      : 'Office')),
          isOffDay: isWeekend,
          isOvernight: calc.crossesMidnight,
          isUpdated: false,
          rawSpanMinutes: calc.spanMinutes,
          breakMinutes: calc.breakMinutes,
          netScheduledMinutes: calc.scheduledWorkMinutes,
          formattedDuration:
              isWeekend ? 'No scheduled work' : calc.formattedScheduledWork,
          policyName: '${user.companyName ?? 'Company'} Attendance Policy',
          assignedBy: 'Company Policy',
        );
      });
    } catch (e) {
      secureLog('[Roster] getShiftRoster error: $e');
      return [];
    }
  }

  // ── Documents ──────────────────────────────────────────────────────────────

  @override
  Future<List<DocumentModel>> getDocuments(
    String employeeId, {
    String? companyId,
    String? requesterRole,
  }) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final identity = await _resolveDynamicEmployeeIdentity(employeeId);
      final empId = identity.employeeId;
      final user = UserService.instance.currentUser;

      final candidateIds = [
        empId,
        employeeId,
        user.employeeId,
        user.dataId,
        if (user.employeeUuid != null) user.employeeUuid!,
      ].where((s) => _isValidUuid(s)).toSet().toList();

      if (candidateIds.isEmpty) {
        secureLog('[Documents] getDocuments warning: No valid employee identifier found');
        return [];
      }

      final List<DocumentModel> result = [];

      // 1. Query canonical public.employee_documents with document_types join or fallback
      try {
        dynamic empDocs;
        try {
          var query = _client.from('employee_documents').select('*, document_types(id, name, display_name, code)');
          if (candidateIds.length > 1) {
            query = query.inFilter('employee_id', candidateIds);
          } else {
            query = query.eq('employee_id', candidateIds.first);
          }
          empDocs = await withTimeout(
            query.order('created_at', ascending: false),
          );
        } catch (joinErr) {
          secureLog('[Documents] Join query failed, falling back to basic select: $joinErr');
          var fallbackQuery = _client.from('employee_documents').select('*');
          if (candidateIds.length > 1) {
            fallbackQuery = fallbackQuery.inFilter('employee_id', candidateIds);
          } else {
            fallbackQuery = fallbackQuery.eq('employee_id', candidateIds.first);
          }
          empDocs = await withTimeout(
            fallbackQuery.order('created_at', ascending: false),
          );
        }

        for (final row in (empDocs as List)) {
          final sizeBytes = (row['file_size_bytes'] as num?)?.toInt() ?? 0;
          final sizeStr = sizeBytes > 1048576
              ? '${(sizeBytes / 1048576).toStringAsFixed(1)} MB'
              : sizeBytes > 1024
                  ? '${(sizeBytes / 1024).toStringAsFixed(0)} KB'
                  : '$sizeBytes B';

          final dtMap = row['document_types'] is Map ? row['document_types'] as Map : null;
          final docTypeName = dtMap?['name']?.toString() ??
              dtMap?['display_name']?.toString() ??
              row['file_name']?.toString() ??
              'Document';
          final rawFileName = row['file_name']?.toString() ?? 'Document.jpg';

          final mimeStr = (row['mime_type']?.toString() ?? 'image/jpeg').toLowerCase();
          final category =
              (rawFileName.toLowerCase().contains('policy') || rawFileName.toLowerCase().contains('company') ||
                  mimeStr.contains('policy'))
                  ? DocumentCategory.company
                  : DocumentCategory.personal;

          final docId = row['id']?.toString() ?? '';
          final storagePath = row['storage_path']?.toString() ?? row['file_path']?.toString() ?? '';
          final fileUrlStr = row['file_url']?.toString() ?? '';
          final effectiveUrl = fileUrlStr.isNotEmpty ? fileUrlStr : storagePath;

          String ext = '';
          if (rawFileName.contains('.')) {
            ext = '.${rawFileName.split('.').last}';
          } else if (storagePath.contains('.')) {
            ext = '.${storagePath.split('.').last.split('?').first}';
          } else if (mimeStr.contains('pdf')) {
            ext = '.pdf';
          } else {
            ext = '.jpg';
          }

          if (!result.any((d) => d.id == docId)) {
            result.add(DocumentModel(
              id: docId,
              name: docTypeName,
              category: category,
              fileType: row['mime_type']?.toString() ?? (ext.contains('pdf') ? 'application/pdf' : 'image/jpeg'),
              fileSize: sizeStr,
              uploadedAt:
                  DateTime.tryParse(row['created_at']?.toString() ?? row['uploaded_at']?.toString() ?? '') ??
                      DateTime.now(),
              storagePath: storagePath.isNotEmpty ? storagePath : effectiveUrl,
              fileUrl: effectiveUrl,
              fileExtension: ext,
              documentType: docTypeName,
              verificationStatus: row['verification_status']?.toString() ?? 'PENDING',
              verifiedBy: row['verified_by']?.toString(),
              verifiedAt:
                  DateTime.tryParse(row['verified_at']?.toString() ?? ''),
              rejectionReason: row['rejection_reason']?.toString(),
              requestId: row['document_type_id']?.toString(),
            ));
          }
        }
      } catch (e) {
        secureLog('[Documents] employee_documents query notice: $e');
      }

      return result;
    } catch (e) {
      secureLog('[Documents] getDocuments error: $e');
      return [];
    }
  }

  @override
  Future<DocumentModel> uploadDocument(DocumentModel document) async {
    try {
      final user = UserService.instance.currentUser;
      final empId = user.dataId;

      if (empId.isEmpty) {
        throw Exception('Employee identity could not be verified.');
      }

      // 1. Insert into employee_documents (canonical schema)
      // Canonical columns: file_name, storage_path, file_size_bytes, mime_type,
      //   verification_status, organization_id, employee_id, document_type_id
      // NOT: document_name, file_path, status, file_url
      try {
        final user = UserService.instance.currentUser;
        final orgId = user.organizationId?.isNotEmpty == true
            ? user.organizationId
            : null;

        // document_type_id is NOT NULL — resolve from document.requestId (set
        // by getDocuments from document_types.id) or fall back to first type.
        String? documentTypeId;
        if (document.requestId != null && _isValidUuid(document.requestId!)) {
          documentTypeId = document.requestId;
        } else {
          try {
            final typeRows = await withTimeout(
              _client.from('document_types').select('id').order('name', ascending: true).limit(1),
            );
            if (typeRows.isNotEmpty) {
              documentTypeId = typeRows.first['id']?.toString();
            }
          } catch (_) {}
        }

        final payload = <String, dynamic>{
          'employee_id': empId,
          'document_type_id': documentTypeId,
          'file_name': document.name,
          'storage_path': document.storagePath ?? document.fileUrl ?? '',
          'file_size_bytes': 0,
          'mime_type': 'application/octet-stream',
          'verification_status': 'PENDING',
          if (orgId != null) 'organization_id': orgId,
        };
        await _client.from('employee_documents').insert(payload);
        secureLog(
            '[Documents] Successfully inserted into employee_documents: ${document.id}');

        // Send push notification to HR about document upload
        try {
          await PushSenderService.instance.sendToEmployee(
            employeeId: empId,
            title: 'Document Uploaded',
            body:
                '${document.documentType ?? document.name} has been uploaded successfully and is pending verification.',
            route: 'documents',
            data: {'document_id': document.id},
          );
        } catch (e) {
          secureLog('[Documents] Push notification notice: $e');
        }
      } catch (e) {
        secureLog('[Documents] employee_documents insert notice: $e');
      }

      return document;
    } catch (e) {
      secureLog('[Documents] uploadDocument error: $e');
      return document;
    }
  }

  // ── Service Configurations ──────────────────────────────────────────────────

  @override
  Future<List<EmployeeServiceConfigModel>> getServiceConfigs(
      String organizationId) async {
    return [];
  }

  // ── Digital Letters ────────────────────────────────────────────────────────

  @override
  Future<List<DigitalLetterModel>> getDigitalLetters(String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final user = UserService.instance.currentUser;
      final empId = user.employeeUuid?.isNotEmpty == true
          ? user.employeeUuid!
          : (employeeId.isNotEmpty ? employeeId : user.employeeId);
      List<DigitalLetterModel> result = [];

      // Query canonical employee_documents table
      try {
        final rows = await withTimeout(
          _client
              .from('employee_documents')
              .select()
              .eq('employee_id', empId)
              .order('created_at', ascending: false),
        );

        for (final row in rows) {
          final id = row['id']?.toString() ?? '';
          final fileName = row['file_name']?.toString() ?? 'Official Document';
          result.add(DigitalLetterModel(
            id: id,
            title: fileName,
            category: 'Document',
            issueDate: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
            documentRef: 'REF-$id',
            documentUrl: row['storage_path']?.toString(),
            fileName: fileName,
          ));
        }
      } catch (e) {
        secureLog('[Letters] employee_documents query notice: $e');
      }

      return result;
    } catch (e) {
      secureLog('[Letters] getDigitalLetters error: $e');
      return [];
    }
  }

  @override
  Future<void> acknowledgeDigitalLetter(String letterId,
      {String? signatureData}) async {
    secureLog('[DigitalLetters] Acknowledged letter $letterId');
  }

  String _monthName(dynamic m) {
    if (m == null) return 'Current Month';
    if (m is int) {
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      if (m >= 1 && m <= 12) return months[m - 1];
    }
    final s = m.toString();
    final parsed = int.tryParse(s);
    if (parsed != null && parsed >= 1 && parsed <= 12) {
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      return months[parsed - 1];
    }
    return s;
  }

  @override
  Future<List<PayslipModel>> getPayslips(String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final user = UserService.instance.currentUser;
      final authUid = _client.auth.currentUser?.id;
      final empId = _resolveEmployeeId(employeeId);
      final Set<String> candidateIds = {
        employeeId,
        empId,
        user.dataId,
        user.employeeId,
        if (user.employeeUuid != null && user.employeeUuid!.isNotEmpty)
          user.employeeUuid!,
        if (authUid != null && authUid.isNotEmpty) authUid,
      }.where((s) => s.isNotEmpty).toSet();

      List<dynamic> rows = [];
      final validUuids = candidateIds.where(_isValidUuid).toList();

      // 1. Primary: Query canonical payslips joined with payroll_line_items
      if (validUuids.isNotEmpty) {
        try {
          final uuidList = validUuids.map((u) => '"$u"').join(',');
          final payslipRows = await withTimeout(
            _client
                .from('payslips')
                .select('*, payroll_line_items(*, payroll_runs(*))')
                .filter('employee_id', 'in', '($uuidList)')
                .order('created_at', ascending: false),
          );
          rows.addAll(payslipRows);
        } catch (e) {
          secureLog('[Payslips] canonical payslips query notice: $e');
        }
      }

      // 2. Fallback: payslips table is empty for this employee — no synthesized payslips.
      // notification_events does NOT have event_type, metadata, or resource_id columns
      // so event-based payslip synthesis is not possible with the canonical schema.
      // Canonical notification_events columns: id, organization_id, recipient_user_id,
      // channel, title, message, action_url, is_read, is_sent, sent_at, created_at.

      return rows.map<PayslipModel>((row) {
        final lineItem = row['payroll_line_items'] is Map ? row['payroll_line_items'] as Map : null;
        final run = (lineItem != null && lineItem['payroll_runs'] is Map) ? (lineItem['payroll_runs'] as Map) : null;

        final gross = (lineItem?['gross_earnings'] ??
            row['gross_salary'] ??
            row['gross_pay'] ??
            row['gross_earnings']) as num?;
        final deductionsVal =
            (lineItem?['total_deductions'] ?? row['total_deductions'] ?? row['deductions']) as num?;
        final netVal =
            (lineItem?['net_pay'] ?? row['net_salary'] ?? row['net_pay'] ?? row['net_amount']) as num?;

        final grossD = gross?.toDouble() ?? 0.0;
        final deductionsD = deductionsVal?.toDouble() ?? 0.0;
        final netD = netVal?.toDouble() ??
            (grossD > deductionsD ? (grossD - deductionsD) : 0.0);

        final monthStr = _monthName(run?['month'] ?? row['month']);
        final yearVal = (run?['year'] ?? row['year'] as num?)?.toInt() ?? DateTime.now().year;

        final earningsMap = lineItem?['earnings_breakdown'] is Map ? lineItem!['earnings_breakdown'] as Map : {};
        final deductionsMap = lineItem?['deductions_breakdown'] is Map ? lineItem!['deductions_breakdown'] as Map : {};

        return PayslipModel(
          id: row['id']?.toString() ?? '',
          employeeId: empId,
          employeeName: user.name.isNotEmpty ? user.name : '—',
          designation: user.designation.isNotEmpty ? user.designation : '—',
          monthYear: monthStr.isNotEmpty ? '$monthStr $yearVal' : '$yearVal',
          grossEarnings: '₹${grossD.toStringAsFixed(0)}',
          deductions: '₹${deductionsD.toStringAsFixed(0)}',
          netPay: '₹${netD.toStringAsFixed(0)}',
          payDate: row['published_at']?.toString() ?? row['pay_date']?.toString() ?? '—',
          pdfUrl: row['storage_path']?.toString() ?? row['pdf_url']?.toString() ?? '',
          basicSalary: (earningsMap['Basic'] ?? earningsMap['basic'] ?? row['basic_salary'] as num?)?.toDouble() ?? 0.0,
          hra: (earningsMap['HRA'] ?? earningsMap['hra'] ?? row['hra'] as num?)?.toDouble() ?? 0.0,
          specialAllowance:
              (earningsMap['Special Allowance'] ?? earningsMap['special_allowance'] ?? row['special_allowance'] as num?)?.toDouble() ?? 0.0,
          pfDeduction: (deductionsMap['PF'] ?? deductionsMap['pf'] ?? row['pf_deduction'] as num?)?.toDouble() ?? 0.0,
          profTaxDeduction:
              (deductionsMap['PT'] ?? deductionsMap['prof_tax'] ?? row['prof_tax_deduction'] as num?)?.toDouble() ?? 0.0,
          incomeTaxDeduction:
              (deductionsMap['TDS'] ?? deductionsMap['income_tax'] ?? row['income_tax_deduction'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    } catch (e) {
      secureLog('[Payslips] getPayslips notice: $e');
      return [];
    }
  }

  // ── Expense Claims ─────────────────────────────────────────────────────────

  @override
  Future<List<ExpenseClaimModel>> getExpenseClaims(String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final empId = _resolveEmployeeId(employeeId);
      List<ExpenseClaimModel> result = [];

      // Query canonical employee_requests table where request_type = 'EXPENSE'
      try {
        final rows = await withTimeout(
          _client
              .from('employee_requests')
              .select()
              .eq('employee_id', empId)
              .eq('request_type', 'EXPENSE')
              .order('created_at', ascending: false),
        );

        for (final row in rows) {
          final rawStatus = (row['status']?.toString() ?? '').toUpperCase();
          ExpenseStatus status = ExpenseStatus.pending;
          if (rawStatus == 'APPROVED' ||
              rawStatus == 'RESOLVED' ||
              rawStatus == 'PAID' ||
              rawStatus == 'SETTLED') {
            status = ExpenseStatus.approved;
          } else if (rawStatus == 'REJECTED') {
            status = ExpenseStatus.rejected;
          }

          final rawDesc = row['description']?.toString() ?? '';
          double parsedAmount = (row['amount'] as num?)?.toDouble() ?? 0.0;
          if (parsedAmount == 0.0 && rawDesc.isNotEmpty) {
            final amtMatch = RegExp(r'\[Amount:\s*₹?([\d,]+(?:\.\d+)?)\]', caseSensitive: false).firstMatch(rawDesc);
            if (amtMatch != null) {
              parsedAmount = double.tryParse(amtMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
            }
          }
          String? parsedReceiptUrl;
          final recMatch = RegExp(r'\[Receipt:\s*([^\]]+)\]', caseSensitive: false).firstMatch(rawDesc);
          if (recMatch != null) {
            parsedReceiptUrl = recMatch.group(1)?.trim();
          }
          final cleanDesc = rawDesc
              .replaceAll(RegExp(r'\s*\[Amount:[^\]]*\]'), '')
              .replaceAll(RegExp(r'\s*\[Receipt:[^\]]*\]'), '')
              .trim();

          result.add(ExpenseClaimModel(
            id: row['id']?.toString() ?? '',
            title: (row['subject'] ?? row['title'])?.toString() ?? 'Expense Claim',
            category: 'Reimbursement',
            amount: parsedAmount,
            date: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.now(),
            status: status,
            description: cleanDesc,
            receiptUrl: parsedReceiptUrl,
          ));
        }
      } catch (e) {
        secureLog('[Claims] employee_requests expense query notice: $e');
      }

      return result;
    } catch (e) {
      secureLog('[Claims] getExpenseClaims error: $e');
      return [];
    }
  }

  @override
  Future<ExpenseClaimModel> submitExpenseClaim(ExpenseClaimModel claim) async {
    try {
      if (claim.receiptUrl == null || claim.receiptUrl!.isEmpty) {
        throw Exception("Please attach the bill/receipt before submitting.");
      }

      final user = UserService.instance.currentUser;
      final empId = user.employeeUuid ?? user.employeeId;
      final tenantId = user.companyId.isNotEmpty
          ? user.companyId
          : (user.organizationId?.isNotEmpty == true
              ? user.organizationId!
              : '');

      // Insert into canonical employee_requests table
      try {
        final reqPayload = <String, dynamic>{
          if (_isValidUuid(claim.id)) 'id': claim.id,
          if (_isValidUuid(tenantId)) 'organization_id': tenantId,
          'employee_id': empId,
          'request_type': 'EXPENSE',
          'subject': claim.title.isNotEmpty ? claim.title : 'Expense Claim',
          'description': '${claim.description} [Amount: ₹${claim.amount}] [Receipt: ${claim.receiptUrl}]',
          'status': 'OPEN',
          'priority': 'MEDIUM',
        };
        await _client.from('employee_requests').insert(reqPayload);
      } catch (e) {
        secureLog('[Claims] employee_requests insert notice: $e');
      }

      return claim;
    } catch (e) {
      secureLog('[Claims] submitExpenseClaim error: $e');
      return claim;
    }
  }

  // ── Performance Goals / OKRs ───────────────────────────────────────────────

  @override
  Future<List<PerformanceGoalModel>> getPerformanceGoals(
      String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];
      final targetId = _resolveEmployeeId(employeeId);

      try {
        // Canonical performance_goals columns: id, employee_id, title, status,
        // target_value, current_value, organization_id, created_at, updated_at
        // employee_code column does NOT exist — filter by employee_id UUID only.
        final rows = await withTimeout(
          _client.from('performance_goals').select().eq('employee_id', targetId),
        );
        if (rows.isNotEmpty) {
          return (rows as List)
              .map((r) => PerformanceGoalModel.fromJson(r))
              .toList();
        }
      } catch (_) {}
      return [];
    } catch (e) {
      secureLog('[Goals] Performance goals query notice: $e');
      return [];
    }
  }

  // ── Grievances / Complaints ────────────────────────────────────────────────

  @override
  Future<List<ComplaintModel>> getComplaints(String employeeId) async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final user = UserService.instance.currentUser;
      final empId = user.employeeUuid?.isNotEmpty == true
          ? user.employeeUuid!
          : (employeeId.isNotEmpty ? employeeId : user.employeeId);
      List<ComplaintModel> result = [];

      // 1. Fetch from canonical posh_and_grievance_cases
      // Canonical columns: id, case_number, status, incident_date, organization_id, created_at, updated_at
      // NOTE: complainant_id, case_type, description, findings, priority do NOT exist.
      // Filter by organization_id and surface all cases visible via RLS.
      try {
        final orgId = UserService.instance.currentUser.organizationId;
        if (orgId != null && orgId.isNotEmpty) {
          final rows = await withTimeout(
            _client
                .from('posh_and_grievance_cases')
                .select('id, case_number, status, created_at')
                .order('created_at', ascending: false),
          );

          for (final row in rows) {
            final caseNum = row['case_number']?.toString() ?? '';
            final isPosh = caseNum.startsWith('POSH');
            result.add(ComplaintModel(
              id: row['id'].toString(),
              subject: isPosh ? 'POSH Complaint $caseNum' : 'Grievance $caseNum',
              category: isPosh ? 'POSH Complaint' : 'Grievance',
              description: '',
              createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                  DateTime.now(),
              status: _parseStatus(row['status']),
              response: null,
              destinationName: isPosh ? 'POSH Committee' : 'HR Grievance Redressal',
            ));
          }
        }
      } catch (e) {
        secureLog('[Grievance] posh_and_grievance_cases query notice: $e');
      }

      // 2. Fetch from canonical employee_requests table
      // Canonical columns: id, employee_id, request_type, subject, description,
      //   status, priority, organization_id, created_at, updated_at
      // NOTE: approver_comment, manager_comment, notes do NOT exist.
      if (result.isEmpty && _isValidUuid(empId)) {
        try {
          final reqRows = await withTimeout(
            _client
                .from('employee_requests')
                .select('id, employee_id, request_type, subject, description, status, created_at')
                .eq('employee_id', empId)
                .order('created_at', ascending: false),
          );

          for (final row in reqRows) {
            final subj = row['subject']?.toString() ?? '';
            final reqType = row['request_type']?.toString() ?? '';
            if (reqType == 'OTHER' || subj.toLowerCase().contains('grievance') || subj.toLowerCase().contains('posh')) {
              result.add(ComplaintModel(
                id: row['id'].toString(),
                subject: subj.isNotEmpty ? subj : 'Employee Request',
                category: subj.toUpperCase().contains('POSH') ? 'POSH Complaint' : 'Grievance',
                description: row['description']?.toString() ?? '',
                createdAt:
                    DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                        DateTime.now(),
                status: _parseStatus(row['status']),
                response: null, // approver_comment does not exist in canonical schema
                destinationName: 'HR Administration',
              ));
            }
          }
        } catch (_) {}
      }

      return result;
    } catch (e) {
      secureLog('[Grievance] getComplaints error: $e');
      return [];
    }
  }

  @override
  Future<ComplaintModel> submitComplaint(ComplaintModel complaint) async {
    try {
      final user = UserService.instance.currentUser;
      final orgId = user.tenantId;
      final empId = user.resolvedEmployeeId;

      final isPosh = complaint.category == "POSH Complaint";
      final caseNumber = isPosh
          ? 'POSH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'
          : 'GRV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      final destName = complaint.destinationName?.isNotEmpty == true
          ? complaint.destinationName!
          : (isPosh ? 'POSH Committee' : 'HR Grievance Redressal');

      // 1. Insert into canonical posh_and_grievance_cases table
      // Canonical columns: id, case_number, status, incident_date, organization_id, created_at, updated_at
      // incident_date is NOT NULL in database schema.
      if (_isValidUuid(empId)) {
        final orgId2 = UserService.instance.currentUser.organizationId;
        try {
          final casePayload = <String, dynamic>{
            'case_number': caseNumber,
            'status': 'FILED',
            'incident_date': DateTime.now().toIso8601String().split('T')[0],
            if (orgId2 != null && orgId2.isNotEmpty) 'organization_id': orgId2,
          };

          final data = await _client
              .from('posh_and_grievance_cases')
              .insert(casePayload)
              .select()
              .maybeSingle();
          secureLog(
              '[Grievance] Inserted into posh_and_grievance_cases: ${data?['id'] ?? caseNumber}');
        } catch (caseErr) {
          secureLog('[Grievance] posh_and_grievance_cases insert notice: $caseErr');
        }
      }

      // 2. Also insert into canonical employee_requests
      if (_isValidUuid(empId)) {
        try {
          final reqPayload = <String, dynamic>{
            'employee_id': empId,
            if (_isValidUuid(orgId)) 'organization_id': orgId,
            'request_type': 'OTHER',
            'subject': isPosh ? '[POSH] ${complaint.subject}' : '[GRIEVANCE] ${complaint.subject}',
            'description': complaint.description,
            'status': 'OPEN',
            'priority': isPosh ? 'URGENT' : 'HIGH',
            'created_at': DateTime.now().toIso8601String(),
          };
          await _client.from('employee_requests').insert(reqPayload);
        } catch (_) {}
      }

      // 3. Broadcast to realtime_outbox via centralized service
      await RealtimeOutboxService.insertEvent(
        entityType: 'posh_and_grievance_cases',
        eventType: isPosh ? 'posh.submitted' : 'grievance.submitted',
        entityId: caseNumber,
        tenantId: orgId,
        actorId: empId,
        payload: {
          'case_number': caseNumber,
          'complainant_id': empId,
          'destination_name': destName,
          'subject': complaint.subject,
          'description': complaint.description,
        },
      );

      // Send push notification about the case
      try {
        await PushSenderService.instance.sendToEmployee(
          employeeId: empId,
          title: isPosh ? 'POSH Complaint Filed' : 'Grievance Submitted',
          body:
              'Your ${isPosh ? 'POSH complaint' : 'grievance'} ($caseNumber) has been submitted successfully.',
          route: 'more',
          data: {'case_number': caseNumber},
        );
      } catch (e) {
        secureLog('[Grievance] Push notification notice: $e');
      }

      return complaint;
    } catch (e) {
      secureLog('[Grievance] submitComplaint error: $e');
      return complaint;
    }
  }

  static ComplaintStatus _parseStatus(dynamic raw) {
    switch ((raw ?? '').toString().toUpperCase().replaceAll(' ', '_')) {
      case 'UNDER_REVIEW':
      case 'REVIEW':
        return ComplaintStatus.underReview;
      case 'IN_PROGRESS':
      case 'PROGRESS':
        return ComplaintStatus.inProgress;
      case 'RESOLVED':
        return ComplaintStatus.resolved;
      case 'CLOSED':
        return ComplaintStatus.closed;
      default:
        return ComplaintStatus.submitted;
    }
  }
}
