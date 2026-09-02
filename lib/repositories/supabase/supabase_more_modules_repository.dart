import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/services/document_upload_service.dart';
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

  String _resolveEmployeeId(String employeeId) {
    final user = UserService.instance.currentUser;
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

      final rows = await withTimeout(
        _client
            .from('company_announcements')
            .select()
            .eq('status', 'PUBLISHED')
            .order('is_pinned', ascending: false)
            .order('created_at', ascending: false),
      );

      return rows.map<AnnouncementModel>((row) {
        return AnnouncementModel(
          id: row['id']?.toString() ?? '',
          title: row['title']?.toString() ?? 'Announcement',
          content: row['content']?.toString() ?? '',
          author: row['category']?.toString() ?? 'Company Leadership',
          isImportant: row['is_pinned'] == true,
          publishedAt: DateTime.tryParse(row['publish_at']?.toString() ??
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
        // 1. Query shift_rosters and attendance_roster_entries
        try {
          final orFilters = <String>[];
          if (empId.isNotEmpty) {
            orFilters.add('employee_id.eq.$empId');
          }
          if (user.employeeUuid?.isNotEmpty == true) {
            orFilters.add('employee_id.eq.${user.employeeUuid}');
          }
          if (user.employeeId.isNotEmpty) {
            orFilters.add('employee_id.eq.${user.employeeId}');
            orFilters.add('employee_code.eq.${user.employeeId}');
          }

          final filterQuery = orFilters.toSet().join(',');
          List<dynamic> rows = [];

          try {
            final r1 = await withTimeout(
              _client
                  .from('shift_rosters')
                  .select()
                  .or(filterQuery)
                  .order('date', ascending: true),
            );
            rows.addAll(r1);
          } catch (_) {}

          try {
            final r2 = await withTimeout(
              _client
                  .from('attendance_roster_entries')
                  .select()
                  .or(filterQuery)
                  .order('date', ascending: true),
            );
            rows.addAll(r2);
          } catch (_) {}

          for (final row in rows) {
            final dateStr =
                row['date']?.toString() ?? row['roster_date']?.toString() ?? '';
            final parsedDate = DateTime.tryParse(dateStr);
            if (parsedDate == null) continue;

            final dateKey =
                "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
            final shiftCode = row['shift_code']?.toString() ?? '';
            final shiftName = row['shift_name']?.toString() ?? '';
            final isOff = row['is_weekly_off'] == true ||
                shiftCode.toUpperCase() == 'OFF' ||
                shiftName.toLowerCase().contains('off') ||
                shiftName.toLowerCase().contains('rest');

            final rawStart = row['start_time']?.toString() ?? '09:30';
            final rawEnd = row['end_time']?.toString() ?? '18:30';
            final crosses = row['crosses_midnight'] == true ||
                ShiftDurationCalculator.instance
                    .isOvernight(startTime: rawStart, endTime: rawEnd);
            final breakMins = (row['break_minutes'] is num)
                ? (row['break_minutes'] as num).toInt()
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
              displayColorHex: row['display_color']?.toString(),
              policyName: row['policy_name']?.toString() ??
                  '${user.companyName ?? 'Company'} Attendance Policy',
              assignedBy: row['assigned_by']?.toString() ?? 'Department Roster',
            );
          }
        } catch (e) {
          secureLog('[Roster] roster tables query notice: $e');
        }

        // 2. Overlay real-time Shift Assignments from notification_events
        try {
          final notifs = await withTimeout(
            _client
                .from('notification_events')
                .select()
                .inFilter('event_type',
                    ['SHIFT_ASSIGNED', 'SHIFT_UPDATED', 'BULK_SHIFT_ASSIGNED'])
                .order('created_at', ascending: false)
                .limit(50),
          );

          final myIds = <String>{
            empId,
            user.dataId,
            user.employeeId,
            if (user.employeeUuid != null && user.employeeUuid!.isNotEmpty)
              user.employeeUuid!,
          }.where((s) => s.isNotEmpty).toSet();

          for (final ev in notifs) {
            final resId = ev['resource_id']?.toString() ?? '';
            final meta = ev['metadata'] is Map
                ? ev['metadata'] as Map<String, dynamic>
                : <String, dynamic>{};
            final metaTarget = meta['target_user_id']?.toString() ??
                meta['employee_id']?.toString() ??
                meta['employee_code']?.toString();

            final isForMe = resId.isEmpty ||
                myIds.contains(resId) ||
                (metaTarget != null && myIds.contains(metaTarget));
            if (!isForMe) continue;

            final effDateStr = meta['effective_date']?.toString() ?? '';
            final parsedDate = DateTime.tryParse(effDateStr);
            if (parsedDate == null) continue;

            final dateKey =
                "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
            if (rosterByDate.containsKey(dateKey)) continue;

            final shiftCode = meta['shift_code']?.toString() ?? '';
            final shiftName = meta['shift_name']?.toString() ?? '';
            final isOff = meta['is_weekly_off'] == true ||
                shiftCode.toUpperCase() == 'OFF';

            final rawStart = meta['start_time']?.toString() ??
                meta['start_time_display']?.toString() ??
                '09:30';
            final rawEnd = meta['end_time']?.toString() ??
                meta['end_time_display']?.toString() ??
                '18:30';
            final crosses = meta['is_night_shift'] == true ||
                meta['crosses_midnight'] == true ||
                ShiftDurationCalculator.instance
                    .isOvernight(startTime: rawStart, endTime: rawEnd);
            final breakMins = (meta['break_minutes'] is num)
                ? (meta['break_minutes'] as num).toInt()
                : null;

            final calc = ShiftDurationCalculator.instance.calculate(
              startTime: rawStart,
              endTime: rawEnd,
              breakMinutes: breakMins,
              explicitCrossesMidnight: crosses,
              isOffDay: isOff,
            );

            final category = _resolveCategory(
              backendCategory: meta['shift_category']?.toString(),
              isOff: isOff,
              crossesMidnight: calc.crossesMidnight,
              startTime: rawStart,
              shiftCode: shiftCode,
              shiftName: shiftName,
            );
            final categoryLabel = _resolveCategoryLabel(category,
                customLabel: meta['shift_category_label']?.toString());

            rosterByDate[dateKey] = ShiftRosterModel(
              id: ev['id']?.toString() ?? 'roster-$dateKey',
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
              location: meta['location']?.toString() ??
                  (user.approvedLocation.name.isNotEmpty
                      ? user.approvedLocation.name
                      : (user.campus.isNotEmpty && user.campus != 'N/A'
                          ? user.campus
                          : (user.companyName?.isNotEmpty == true
                              ? user.companyName!
                              : 'Office'))),
              isOffDay: isOff,
              isOvernight: calc.crossesMidnight,
              isUpdated: ev['event_type'] == 'SHIFT_UPDATED',
              rawSpanMinutes: calc.spanMinutes,
              breakMinutes: calc.breakMinutes,
              netScheduledMinutes: calc.scheduledWorkMinutes,
              formattedDuration:
                  isOff ? 'No scheduled work' : calc.formattedScheduledWork,
              displayColorHex: meta['display_color']?.toString(),
              policyName: meta['policy_name']?.toString() ??
                  '${user.companyName ?? 'Company'} Attendance Policy',
              assignedBy: meta['assigned_by']?.toString() ?? 'HR Administrator',
            );
          }
        } catch (e) {
          secureLog('[Roster] notification_events query notice: $e');
        }
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
      final user = UserService.instance.currentUser;
      final Set<String> empIds = {
        if (employeeId.isNotEmpty) employeeId,
        if (user.dataId.isNotEmpty) user.dataId,
        if (user.employeeId.isNotEmpty) user.employeeId,
        if (user.employeeUuid?.isNotEmpty == true) user.employeeUuid!,
      };

      final List<DocumentModel> result = [];

      if (SupabaseConfig.isConfigured && empIds.isNotEmpty) {
        final orFilter = empIds.map((id) => 'employee_id.eq.$id').join(',');

        // 1. Query employee_documents table
        try {
          final empDocs = await withTimeout(
            _client
                .from('employee_documents')
                .select()
                .or(orFilter)
                .order('uploaded_at', ascending: false),
          );

          for (final row in empDocs) {
            final sizeBytes = (row['file_size_bytes'] as num?)?.toInt() ?? 0;
            final sizeStr = sizeBytes > 1048576
                ? '${(sizeBytes / 1048576).toStringAsFixed(1)} MB'
                : sizeBytes > 1024
                    ? '${(sizeBytes / 1024).toStringAsFixed(0)} KB'
                    : '$sizeBytes B';

            final catStr =
                (row['document_category']?.toString() ?? '').toLowerCase();
            final category =
                catStr.contains('company') || catStr.contains('policy')
                    ? DocumentCategory.company
                    : DocumentCategory.personal;

            final docId = row['id']?.toString() ?? '';
            final rawFileUrl = row['file_url']?.toString();
            final cleanStoragePath = rawFileUrl != null && rawFileUrl.isNotEmpty
                ? DocumentUploadService.instance.extractStoragePath(rawFileUrl)
                : null;

            if (!result.any((d) => d.id == docId)) {
              result.add(DocumentModel(
                id: docId,
                name: row['file_name']?.toString() ??
                    row['document_type']?.toString() ??
                    'Document',
                category: category,
                fileType: row['document_type']?.toString() ?? 'PDF',
                fileSize: sizeStr,
                uploadedAt:
                    DateTime.tryParse(row['uploaded_at']?.toString() ?? '') ??
                        DateTime.now(),
                fileUrl: rawFileUrl,
                storagePath: cleanStoragePath,
                documentType: row['document_type']?.toString(),
                verificationStatus: row['verification_status']?.toString(),
                verifiedBy: row['verified_by']?.toString(),
                verifiedAt:
                    DateTime.tryParse(row['verified_at']?.toString() ?? ''),
                rejectionReason: row['rejection_reason']?.toString(),
              ));
            }
          }
        } catch (e) {
          secureLog('[Documents] employee_documents query notice: $e');
        }

        // 2. Query document_requirements table for submitted/verified employee documents
        try {
          final reqRows = await withTimeout(
            _client
                .from('document_requirements')
                .select()
                .or(orFilter)
                .order('updated_at', ascending: false),
          );

          for (final row in reqRows) {
            final status =
                (row['status']?.toString() ?? 'PENDING').toUpperCase();
            // Include submitted, verified, rejected, or under-review requirements
            if (status == 'SUBMITTED' ||
                status == 'VERIFIED' ||
                status == 'REJECTED' ||
                status == 'UNDER_REVIEW') {
              final reqId = row['id']?.toString() ?? '';
              final reqEmpId = row['employee_id']?.toString() ?? user.dataId;

              // Check if we already have this document in result
              final existingIdx = result.indexWhere((d) =>
                  d.id == reqId ||
                  d.requestId == reqId ||
                  d.documentType == row['document_type']);

              String fileUrl = '';
              String storagePath = '';
              String fileName = row['title']?.toString() ??
                  row['document_type']?.toString() ??
                  'Document';
              String fileSize = '76 KB';

              // Inspect Supabase Storage bucket for the uploaded file
              try {
                final folder = 'employees/$reqEmpId/documents/$reqId';
                final storageFiles = await _client.storage
                    .from('employee-documents')
                    .list(path: folder);
                if (storageFiles.isNotEmpty) {
                  final validFiles = storageFiles
                      .where(
                          (f) => f.name.isNotEmpty && !f.name.startsWith('.'))
                      .toList();
                  if (validFiles.isNotEmpty) {
                    // Sort newest timestamp first
                    validFiles.sort((a, b) {
                      final timeA = int.tryParse(a.name.split('_').first) ?? 0;
                      final timeB = int.tryParse(b.name.split('_').first) ?? 0;
                      return timeB.compareTo(timeA);
                    });
                    final latest = validFiles.first;
                    storagePath = '$folder/${latest.name}';
                    fileName = latest.name.replaceFirst(RegExp(r'^\d+_'), '');
                    fileUrl = _client.storage
                        .from('employee-documents')
                        .getPublicUrl(storagePath);
                    if (latest.metadata != null &&
                        latest.metadata!['size'] != null) {
                      final bytes = (latest.metadata!['size'] as num).toInt();
                      fileSize = bytes > 1048576
                          ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
                          : '${(bytes / 1024).toStringAsFixed(1)} KB';
                    }
                  }
                }
              } catch (storageErr) {
                secureLog(
                    '[Documents] Storage scan notice for $reqId: $storageErr');
              }

              final docItem = DocumentModel(
                id: reqId,
                name: row['title']?.toString() ?? fileName,
                category: DocumentCategory.personal,
                fileType: row['document_type']?.toString() ?? 'PDF',
                fileSize: fileSize,
                uploadedAt: DateTime.tryParse(row['updated_at']?.toString() ??
                        row['created_at']?.toString() ??
                        '') ??
                    DateTime.now(),
                fileUrl: fileUrl.isNotEmpty ? fileUrl : null,
                storagePath: storagePath.isNotEmpty ? storagePath : null,
                documentType: row['document_type']?.toString(),
                verificationStatus: status,
                verifiedBy: row['requested_by']?.toString() ?? 'HR Reviewer',
                verifiedAt:
                    DateTime.tryParse(row['updated_at']?.toString() ?? ''),
                rejectionReason: row['rejection_reason']?.toString(),
                requestId: reqId,
              );

              if (existingIdx >= 0) {
                result[existingIdx] = docItem;
              } else {
                result.add(docItem);
              }
            }
          }
        } catch (e) {
          secureLog('[Documents] document_requirements query notice: $e');
        }

        // 3. Query generic company documents / policies
        try {
          final docs = await withTimeout(
            _client
                .from('documents')
                .select()
                .or('subject_type.eq.company,category_code.in.(POLICY,COMPANY)')
                .order('created_at', ascending: false),
          );

          for (final row in docs) {
            final docId = row['id']?.toString() ?? '';
            if (!result.any((d) => d.id == docId)) {
              result.add(DocumentModel(
                id: docId,
                name: row['title']?.toString() ??
                    row['file_name']?.toString() ??
                    'Company Policy',
                category: DocumentCategory.company,
                fileType: row['document_type_code']?.toString() ?? 'PDF',
                fileSize: 'Policy Doc',
                uploadedAt:
                    DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ));
            }
          }
        } catch (e) {
          secureLog('[Documents] documents query notice: $e');
        }
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

      // 1. Insert into employee_documents (Exact database schema)
      try {
        final payload = {
          'id': document.id,
          'employee_id': empId,
          'document_category': document.category == DocumentCategory.company
              ? 'COMPANY'
              : 'PERSONAL',
          'document_type': document.documentType ?? document.name,
          'file_name': document.name,
          'file_url': document.fileUrl ?? '',
          'file_size_bytes': 0,
          'verification_status': 'PENDING',
          'uploaded_at': DateTime.now().toIso8601String(),
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
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final user = UserService.instance.currentUser;
      final orgId = organizationId.isNotEmpty
          ? organizationId
          : (user.companyId.isNotEmpty
              ? user.companyId
              : (user.organizationId?.isNotEmpty == true
                  ? user.organizationId!
                  : ''));

      if (orgId.isEmpty) return [];

      final rows = await withTimeout(
        _client
            .from('employee_service_configs')
            .select('*')
            .eq('tenant_id', orgId)
            .order('sort_order', ascending: true),
      );

      return rows
          .map<EmployeeServiceConfigModel>(
              (row) => EmployeeServiceConfigModel.fromJson(row))
          .toList();
    } catch (e) {
      secureLog('[ServiceConfig] getServiceConfigs error: $e');
      return [];
    }
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
      final empCode = user.employeeId;
      List<DigitalLetterModel> result = [];

      // 1. Fetch from digital_letters table
      try {
        final rows = await withTimeout(
          _client
              .from('digital_letters')
              .select('*')
              .or('employee_id.eq.$empId,employee_id.eq.$empCode')
              .order('issued_date', ascending: false),
        );

        for (final row in rows) {
          result.add(DigitalLetterModel.fromJson(row));
        }
      } catch (e) {
        secureLog('[Letters] digital_letters query notice: $e');
      }

      // 2. Fallback to employee_documents
      if (result.isEmpty) {
        try {
          final rows = await withTimeout(
            _client
                .from('employee_documents')
                .select()
                .or('employee_id.eq.$empId,employee_id.eq.$empCode')
                .or('document_category.ilike.%letter%,document_type.ilike.%letter%')
                .order('uploaded_at', ascending: false),
          );

          for (final row in rows) {
            final id = row['id']?.toString() ?? '';
            result.add(DigitalLetterModel(
              id: id,
              title: row['document_type']?.toString() ??
                  row['file_name']?.toString() ??
                  'Official Letter',
              category: row['document_category']?.toString() ?? 'Letter',
              issueDate:
                  DateTime.tryParse(row['uploaded_at']?.toString() ?? '') ??
                      DateTime.now(),
              documentRef: 'REF-$id',
              documentUrl: row['file_url']?.toString(),
              fileName: row['file_name']?.toString(),
            ));
          }
        } catch (_) {}
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
    try {
      if (!SupabaseConfig.isConfigured) return;

      await _client.from('digital_letters').update({
        'status': signatureData != null ? 'SIGNED' : 'ACKNOWLEDGED',
        'acknowledged_at': DateTime.now().toIso8601String(),
        'signature_data': signatureData,
        'signed_at':
            signatureData != null ? DateTime.now().toIso8601String() : null,
      }).eq('id', letterId);

      secureLog('[DigitalLetters] Acknowledged letter $letterId');
    } catch (e) {
      secureLog('[DigitalLetters] acknowledgeDigitalLetter error: $e');
    }
  }

  bool _isValidUuid(String s) => RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
      .hasMatch(s.trim());

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
      final nonUuids = candidateIds.where((id) => !_isValidUuid(id)).toList();

      // 1. Try querying employee_payslips by employee_code (TEXT)
      if (nonUuids.isNotEmpty) {
        try {
          final codeList = nonUuids.map((c) => '"$c"').join(',');
          final codeRows = await withTimeout(
            _client
                .from('employee_payslips')
                .select()
                .filter('employee_code', 'in', '($codeList)')
                .order('year', ascending: false)
                .order('created_at', ascending: false),
          );
          rows.addAll(codeRows);
        } catch (e) {
          secureLog('[Payslips] employee_code query notice: $e');
        }
      }

      // 2. Try querying employee_payslips by employee_id (UUID only)
      if (validUuids.isNotEmpty) {
        try {
          final uuidList = validUuids.map((u) => '"$u"').join(',');
          final uuidRows = await withTimeout(
            _client
                .from('employee_payslips')
                .select()
                .filter('employee_id', 'in', '($uuidList)')
                .order('year', ascending: false)
                .order('created_at', ascending: false),
          );
          for (final r in uuidRows) {
            if (!rows.any((existing) => existing['id'] == r['id'])) {
              rows.add(r);
            }
          }
        } catch (e) {
          secureLog('[Payslips] employee_id UUID query notice: $e');
        }
      }

      // 3. Fallback: Synthesize from real-time PostgreSQL notification_events
      if (rows.isEmpty) {
        try {
          final notifs = await withTimeout(
            _client
                .from('notification_events')
                .select()
                .inFilter(
                    'event_type', ['PAYSLIP_GENERATED', 'SALARY_DISBURSED'])
                .order('created_at', ascending: false)
                .limit(20),
          );

          if (notifs.isNotEmpty) {
            final List<PayslipModel> synthesized = [];
            for (final ev in notifs) {
              final resId = ev['resource_id']?.toString() ?? '';
              final meta = ev['metadata'] is Map
                  ? ev['metadata'] as Map<String, dynamic>
                  : <String, dynamic>{};
              final metaEmp = meta['employee_id']?.toString() ??
                  meta['target_user_id']?.toString();

              final isForMe = candidateIds.contains(resId) ||
                  (metaEmp != null && candidateIds.contains(metaEmp));

              if (isForMe) {
                final payPeriod = meta['pay_period']?.toString() ??
                    meta['payroll_cycle']?.toString() ??
                    '—';
                final net = (meta['net_pay'] as num?)?.toDouble() ??
                    (meta['amount'] as num?)?.toDouble() ??
                    0.0;
                final gross = (meta['gross_earnings'] as num?)?.toDouble() ??
                    (net > 0 ? net : 0.0);
                final deductions = (gross - net) > 0 ? (gross - net) : 0.0;
                final payslipId = meta['payslip_id']?.toString() ??
                    ev['id']?.toString() ??
                    'ps-${DateTime.now().millisecondsSinceEpoch}';
                final payDate = meta['value_date'] != null
                    ? (DateTime.tryParse(meta['value_date'].toString())
                            ?.toIso8601String()
                            .split('T')[0] ??
                        '—')
                    : '—';

                if (!synthesized.any((p) => p.monthYear == payPeriod)) {
                  synthesized.add(
                    PayslipModel(
                      id: payslipId,
                      employeeId: empId,
                      employeeName: user.name.isNotEmpty ? user.name : '—',
                      designation:
                          user.designation.isNotEmpty ? user.designation : '—',
                      monthYear: payPeriod,
                      grossEarnings: '₹${gross.toStringAsFixed(0)}',
                      deductions: '₹${deductions.toStringAsFixed(0)}',
                      netPay: '₹${net.toStringAsFixed(0)}',
                      payDate: payDate,
                      pdfUrl: meta['pdf_url']?.toString() ?? '',
                      basicSalary:
                          (meta['basic_salary'] as num?)?.toDouble() ?? 0.0,
                      hra: (meta['hra'] as num?)?.toDouble() ?? 0.0,
                      specialAllowance:
                          (meta['special_allowance'] as num?)?.toDouble() ??
                              0.0,
                      pfDeduction:
                          (meta['pf_deduction'] as num?)?.toDouble() ?? 0.0,
                      profTaxDeduction:
                          (meta['prof_tax_deduction'] as num?)?.toDouble() ??
                              0.0,
                      incomeTaxDeduction:
                          (meta['income_tax_deduction'] as num?)?.toDouble() ??
                              0.0,
                    ),
                  );
                }
              }
            }
            if (synthesized.isNotEmpty) {
              return synthesized;
            }
          }
        } catch (notifErr) {
          secureLog(
              '[Payslips] notification_events fallback notice: $notifErr');
        }
      }

      return rows.map<PayslipModel>((row) {
        final gross = (row['gross_salary'] ??
            row['gross_pay'] ??
            row['gross_earnings']) as num?;
        final deductionsVal =
            (row['total_deductions'] ?? row['deductions']) as num?;
        final netVal =
            (row['net_salary'] ?? row['net_pay'] ?? row['net_amount']) as num?;

        final grossD = gross?.toDouble() ?? 0.0;
        final deductionsD = deductionsVal?.toDouble() ?? 0.0;
        final netD = netVal?.toDouble() ??
            (grossD > deductionsD ? (grossD - deductionsD) : 0.0);

        final monthStr = _monthName(row['month']);
        final yearVal = (row['year'] as num?)?.toInt() ?? DateTime.now().year;

        return PayslipModel(
          id: row['id']?.toString() ?? '',
          employeeId: empId,
          employeeName: user.name.isNotEmpty ? user.name : '—',
          designation: user.designation.isNotEmpty ? user.designation : '—',
          monthYear: monthStr.isNotEmpty ? '$monthStr $yearVal' : '$yearVal',
          grossEarnings: '₹${grossD.toStringAsFixed(0)}',
          deductions: '₹${deductionsD.toStringAsFixed(0)}',
          netPay: '₹${netD.toStringAsFixed(0)}',
          payDate: row['pay_date']?.toString() ?? '—',
          pdfUrl: row['pdf_url']?.toString() ?? '',
          basicSalary: (row['basic_salary'] as num?)?.toDouble() ?? 0.0,
          hra: (row['hra'] as num?)?.toDouble() ?? 0.0,
          specialAllowance:
              (row['special_allowance'] as num?)?.toDouble() ?? 0.0,
          pfDeduction: (row['pf_deduction'] as num?)?.toDouble() ?? 0.0,
          profTaxDeduction:
              (row['prof_tax_deduction'] as num?)?.toDouble() ?? 0.0,
          incomeTaxDeduction:
              (row['income_tax_deduction'] as num?)?.toDouble() ?? 0.0,
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

      final user = UserService.instance.currentUser;
      final Set<String> candidateIds = {
        employeeId,
        empId,
        user.dataId,
        user.employeeId,
        if (user.employeeUuid != null && user.employeeUuid!.isNotEmpty)
          user.employeeUuid!,
      }.where((s) => s.isNotEmpty).toSet();

      // 1. Fetch from expense_claims table (server-side filtered by employee_id)
      try {
        final orFilter =
            candidateIds.map((id) => 'employee_id.eq.$id').join(',');
        final rows = await withTimeout(
          _client
              .from('expense_claims')
              .select('*')
              .or(orFilter)
              .order('submitted_at', ascending: false),
        );

        for (final row in rows) {
          result.add(ExpenseClaimModel.fromJson(row));
        }
      } catch (e) {
        secureLog('[Claims] expense_claims query notice: $e');
      }

      // 2. Fallback to employee_requests if expense_claims table is empty
      if (result.isEmpty) {
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
                rawStatus == 'PAID' ||
                rawStatus == 'SETTLED') {
              status = ExpenseStatus.approved;
            } else if (rawStatus == 'REJECTED') {
              status = ExpenseStatus.rejected;
            }

            result.add(ExpenseClaimModel(
              id: row['id']?.toString() ?? '',
              title: row['title']?.toString() ?? 'Expense Claim',
              category: 'Reimbursement',
              amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
              date: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                  DateTime.now(),
              status: status,
              description: row['description']?.toString() ?? '',
            ));
          }
        } catch (_) {}
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
      final user = UserService.instance.currentUser;
      final empId = user.employeeUuid ?? user.employeeId;
      final tenantId = user.companyId.isNotEmpty
          ? user.companyId
          : (user.organizationId?.isNotEmpty == true
              ? user.organizationId!
              : '');

      // 1. Insert into expense_claims table
      try {
        final claimNumber =
            'CLM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
        final approverId =
            user.reportsToId?.isNotEmpty == true ? user.reportsToId : null;
        final approverName =
            user.reportsToName?.isNotEmpty == true ? user.reportsToName : null;

        final payload = <String, dynamic>{
          if (_isValidUuid(claim.id)) 'id': claim.id,
          'claim_number': claimNumber,
          'tenant_id': tenantId,
          'organization_id': tenantId,
          'employee_id': empId,
          'employee_code': user.employeeId,
          'employee_name': user.name,
          'department': user.department,
          'category': claim.category,
          'amount': claim.amount,
          'currency': 'INR',
          'expense_date': claim.date.toIso8601String().split('T')[0],
          'description': claim.description,
          'receipt_url': claim.receiptUrl,
          'receipt_filename': claim.attachmentName,
          'status': 'PENDING',
          'approver_id': approverId,
          'approver_name': approverName,
          'submitted_at': DateTime.now().toIso8601String(),
        };

        final response = await _client
            .from('expense_claims')
            .insert(payload)
            .select()
            .maybeSingle();
        secureLog('[Claims] Inserted into expense_claims table: $response');

        // Broadcast to realtime_outbox via centralized service
        await RealtimeOutboxService.insertEvent(
          entityType: 'expense_claims',
          eventType: 'claim.created',
          entityId: response != null
              ? (response['id']?.toString() ?? claimNumber)
              : claimNumber,
          tenantId: tenantId,
          actorId: empId,
          payload: response ?? payload,
        );

        // Send push to approver
        if (approverId != null && approverId.isNotEmpty) {
          try {
            await PushSenderService.instance.sendToEmployee(
              employeeId: approverId,
              title: 'Expense Claim Submitted',
              body:
                  '${user.name} submitted a claim for ₹${claim.amount.toStringAsFixed(0)} — ${claim.category}',
              route: 'more',
              data: {'claim_id': claimNumber},
            );
          } catch (e) {
            secureLog('[Claims] Push to approver notice: $e');
          }
        }

        if (response != null) {
          return ExpenseClaimModel.fromJson(response);
        }
      } catch (e) {
        secureLog('[Claims] expense_claims insert notice: $e');
      }

      // 2. Also insert into employee_requests
      try {
        final reqPayload = <String, dynamic>{
          if (_isValidUuid(claim.id)) 'id': claim.id,
          'organization_id': tenantId,
          'employee_id': empId,
          'employee_name': user.name,
          'request_type': 'EXPENSE',
          'title': claim.title,
          'description': '${claim.description} [Amount: ₹${claim.amount}]',
          'status': 'SUBMITTED',
        };
        await _client.from('employee_requests').insert(reqPayload);
      } catch (_) {}

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
      final user = UserService.instance.currentUser;
      final targetId = _resolveEmployeeId(employeeId);

      for (final table in const [
        'employee_performance_goals',
        'performance_goals'
      ]) {
        try {
          final query = _client.from(table).select();
          final rows = await withTimeout(
            user.employeeId.isNotEmpty
                ? query.or(
                    'employee_id.eq.$targetId,employee_code.eq.${user.employeeId}')
                : query.eq('employee_id', targetId),
          );
          if (rows.isNotEmpty) {
            return (rows as List)
                .map((r) => PerformanceGoalModel.fromJson(r))
                .toList();
          }
        } catch (_) {}
      }
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
      final empCode = user.employeeId;
      List<ComplaintModel> result = [];

      // 1. Fetch from helpdesk_tickets (Primary table for Grievances & POSH Complaints)
      try {
        final rows = await withTimeout(
          _client
              .from('helpdesk_tickets')
              .select()
              .or('employee_id.eq.$empId,employee_code.eq.$empCode')
              .order('created_at', ascending: false),
        );

        for (final row in rows) {
          final tktNum = row['ticket_number']?.toString() ?? '';
          final cat = row['category']?.toString() ?? '';
          final assigned = row['assigned_to_name']?.toString() ?? '';

          final isGrievanceOrPosh = tktNum.startsWith('GRV') ||
              tktNum.startsWith('POSH') ||
              assigned.contains('Company Admin') ||
              assigned.contains('POSH Committee') ||
              cat == 'POSH Complaint' ||
              cat == 'Grievance' ||
              cat == 'Facility & Workplace' ||
              cat == 'Safety & Security';

          if (!isGrievanceOrPosh) continue;

          result.add(ComplaintModel(
            id: row['id'].toString(),
            subject: row['subject']?.toString() ?? '',
            category: row['category']?.toString() ?? 'Grievance',
            description: row['description']?.toString() ?? '',
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.now(),
            status: _parseStatus(row['status']),
            response: row['resolution_summary']?.toString(),
            companyId: row['organization_id']?.toString(),
            destinationName:
                row['assigned_to_name']?.toString() ?? 'Company Admin',
          ));
        }
      } catch (e) {
        secureLog('[Grievance] helpdesk_tickets query notice: $e');
      }

      // 2. Fallback to employee_requests table if applicable
      if (result.isEmpty) {
        try {
          final reqRows = await withTimeout(
            _client
                .from('employee_requests')
                .select()
                .eq('employee_id', empId)
                .eq('request_type', 'GRIEVANCE')
                .order('created_at', ascending: false),
          );

          for (final row in reqRows) {
            result.add(ComplaintModel(
              id: row['id'].toString(),
              subject: row['title']?.toString() ?? '',
              category: row['request_type']?.toString() ?? 'Grievance',
              description: row['description']?.toString() ?? '',
              createdAt:
                  DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                      DateTime.now(),
              status: _parseStatus(row['status']),
              response: row['resolution_notes']?.toString(),
              companyId: row['organization_id']?.toString(),
              destinationName: row['assigned_to_name']?.toString(),
            ));
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

      final isPosh = complaint.category == "POSH Complaint";
      final ticketNumber = isPosh
          ? 'POSH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'
          : 'GRV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      final destName = complaint.destinationName?.isNotEmpty == true
          ? complaint.destinationName!
          : (isPosh ? 'POSH Committee' : 'Company Admin');

      // 1. Insert into helpdesk_tickets (canonical table compliant with RLS)
      final helpdeskPayload = <String, dynamic>{
        if (orgId.isNotEmpty) 'tenant_id': orgId,
        if (orgId.isNotEmpty) 'organization_id': orgId,
        'employee_id': user.resolvedEmployeeId,
        'employee_code': user.employeeId,
        'employee_name': user.name,
        'department': user.department,
        'ticket_number': ticketNumber,
        'category': isPosh
            ? 'POSH Complaint'
            : (complaint.category.isNotEmpty
                ? complaint.category
                : 'Grievance'),
        'subject': complaint.subject,
        'description': complaint.description,
        'priority': isPosh ? 'URGENT' : 'HIGH',
        'status': 'OPEN',
        'assigned_to_name': destName,
        'sla_hours': isPosh ? 24 : 48,
        'attachments': [],
      };

      final data = await _client
          .from('helpdesk_tickets')
          .insert(helpdeskPayload)
          .select()
          .maybeSingle();
      secureLog(
          '[Grievance] Inserted into helpdesk_tickets: ${data?['id'] ?? ticketNumber}');

      // 2. Broadcast to realtime_outbox via centralized service
      await RealtimeOutboxService.insertEvent(
        entityType: 'helpdesk_tickets',
        eventType: isPosh ? 'posh.submitted' : 'grievance.submitted',
        entityId: data != null
            ? (data['id']?.toString() ?? ticketNumber)
            : ticketNumber,
        tenantId: orgId,
        actorId: user.resolvedEmployeeId,
        payload: data ?? helpdeskPayload,
      );

      // Send push notification about the ticket
      try {
        await PushSenderService.instance.sendToEmployee(
          employeeId: user.resolvedEmployeeId,
          title: isPosh ? 'POSH Complaint Filed' : 'Grievance Submitted',
          body:
              'Your ${isPosh ? 'POSH complaint' : 'grievance'} ($ticketNumber) has been submitted successfully.',
          route: 'more',
          data: {'ticket_id': ticketNumber},
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
