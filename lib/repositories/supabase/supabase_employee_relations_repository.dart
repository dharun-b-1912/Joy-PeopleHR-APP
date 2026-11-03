import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/services/document_upload_service.dart';
import '../../core/services/realtime_outbox_service.dart';
import '../../core/services/user_service.dart';
import '../../core/utils/secure_log.dart';
import '../../models/employee_relations_models.dart';

class SupabaseEmployeeRelationsRepository {
  static final SupabaseEmployeeRelationsRepository instance =
      SupabaseEmployeeRelationsRepository._internal();

  SupabaseEmployeeRelationsRepository._internal();

  SupabaseClient get _client => Supabase.instance.client;

  // ============================================================
  // 1. HELPDESK TICKETS & CONVERSATIONS
  // ============================================================

  static bool _isValidUuid(String? str) {
    if (str == null || str.isEmpty) return false;
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(str.trim());
  }

  Future<List<HelpdeskTicketModel>> getHelpdeskTickets(String employeeId) async {
    if (!SupabaseConfig.isConfigured) return [];
    try {
      final user = UserService.instance.currentUser;
      final Set<String> candidateIds = {
        employeeId,
        user.dataId,
        user.employeeId,
        if (user.employeeUuid != null && user.employeeUuid!.isNotEmpty) user.employeeUuid!,
      }.where((s) => s.isNotEmpty).toSet();

      final validUuids = candidateIds.where(_isValidUuid).toList();
      List<HelpdeskTicketModel> list = [];

      // 1. Primary: Fetch from canonical employee_requests table
      if (validUuids.isNotEmpty) {
        try {
          final idFilter = validUuids.map((c) => '"$c"').join(',');
          final reqRows = await _client
              .from('employee_requests')
              .select('*')
              .filter('employee_id', 'in', '($idFilter)')
              .order('created_at', ascending: false);

          for (final r in reqRows) {
            final id = r['id']?.toString() ?? '';
            final statusStr = r['status']?.toString() ?? 'PENDING';
            HelpdeskStatus status = HelpdeskStatus.open;
            if (statusStr == 'IN_REVIEW' || statusStr == 'IN_PROGRESS') status = HelpdeskStatus.inProgress;
            if (statusStr == 'APPROVED' || statusStr == 'FULFILLED' || statusStr == 'RESOLVED') status = HelpdeskStatus.resolved;
            if (statusStr == 'REJECTED' || statusStr == 'CANCELLED' || statusStr == 'CLOSED') status = HelpdeskStatus.closed;

            final priorityStr = r['priority']?.toString() ?? 'MEDIUM';
            TicketPriority priority = TicketPriority.medium;
            if (priorityStr == 'URGENT') priority = TicketPriority.urgent;
            if (priorityStr == 'HIGH') priority = TicketPriority.high;
            if (priorityStr == 'LOW') priority = TicketPriority.low;

            list.add(HelpdeskTicketModel(
              id: id,
              ticketNumber: 'REQ-${id.length > 8 ? id.substring(0, 8).toUpperCase() : id}',
              employeeId: r['employee_id']?.toString() ?? '',
              employeeName: user.name,
              department: user.department,
              category: r['request_type']?.toString() ?? 'General Request',
              subject: r['subject']?.toString() ?? 'Request',
              description: r['description']?.toString() ?? '',
              priority: priority,
              status: status,
              slaHours: 48,
              createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
            ));
          }
        } catch (e) {
          secureLog('[HelpdeskRepo] employee_requests query notice: $e');
        }
      }

      return list;
    } catch (e) {
      secureLog('[HelpdeskRepo] getTickets error: $e');
      return [];
    }
  }

  Future<HelpdeskTicketModel?> submitHelpdeskTicket({
    required String category,
    required String subject,
    required String description,
    required TicketPriority priority,
    Uint8List? attachmentBytes,
    String? attachmentFileName,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;
    try {
      final user = UserService.instance.currentUser;
      final empId = user.resolvedEmployeeId;
      final orgId = user.tenantId;

      List<Map<String, dynamic>> attachments = [];
      if (attachmentBytes != null && attachmentFileName != null && attachmentFileName.isNotEmpty) {
        final uploadedUrl = await DocumentUploadService.instance.uploadDocument(
          tenantId: orgId,
          employeeId: empId,
          bytes: attachmentBytes,
          fileName: attachmentFileName,
        );
        if (uploadedUrl != null) {
          attachments.add({
            'name': attachmentFileName,
            'url': uploadedUrl,
            'size': attachmentBytes.length,
          });
        }
      }

      final ticketNumber = 'TKT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      final priorityStr = priority == TicketPriority.urgent
          ? 'URGENT'
          : priority == TicketPriority.high
              ? 'HIGH'
              : priority == TicketPriority.low
                  ? 'LOW'
                  : 'MEDIUM';

      // 1. Primary insert into canonical employee_requests table
      if (_isValidUuid(empId)) {
        try {
          final insertPayload = <String, dynamic>{
            'employee_id': empId,
            if (_isValidUuid(orgId)) 'organization_id': orgId,
            'request_type': 'OTHER',
            'subject': subject.isNotEmpty ? subject : 'Helpdesk Ticket',
            'description': description,
            'priority': priorityStr,
            'status': 'OPEN',
            'created_at': DateTime.now().toIso8601String(),
          };

          final data = await _client.from('employee_requests').insert(insertPayload).select().single();
          secureLog('[HelpdeskRepo] Request submitted to employee_requests: ${data['id']}');

          // Sync event to realtime_outbox via centralized service
          await RealtimeOutboxService.insertEvent(
            entityType: 'employee_requests',
            eventType: 'request.created',
            entityId: data['id']?.toString() ?? ticketNumber,
            tenantId: orgId,
            actorId: empId,
            payload: data,
          );

          return HelpdeskTicketModel(
            id: data['id'].toString(),
            ticketNumber: ticketNumber,
            employeeId: empId,
            employeeName: user.name,
            department: user.department,
            category: category,
            subject: subject,
            description: description,
            priority: priority,
            status: HelpdeskStatus.open,
            slaHours: priority == TicketPriority.urgent ? 4 : priority == TicketPriority.high ? 24 : 48,
            createdAt: DateTime.now(),
          );
        } catch (e) {
          secureLog('[HelpdeskRepo] employee_requests insert notice: $e');
        }
      }

      return null;
    } catch (e) {
      secureLog('[HelpdeskRepo] submitTicket error: $e');
      return null;
    }
  }

  Future<List<HelpdeskMessageModel>> getTicketMessages(String ticketId) async {
    return [];
  }

  Future<HelpdeskMessageModel?> sendTicketMessage(String ticketId, String message) async {
    return null;
  }

  Future<bool> withdrawHelpdeskTicket(String ticketId) async {
    if (!SupabaseConfig.isConfigured) return false;
    try {
      final user = UserService.instance.currentUser;
      final orgId = user.tenantId;

      if (_isValidUuid(ticketId)) {
        try {
          await _client.from('employee_requests').update({
            'status': 'CLOSED',
            'resolution_notes': 'Cancelled / Withdrawn by employee',
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', ticketId);
        } catch (_) {}
      }

      // Sync deletion to realtime_outbox via centralized service
      await RealtimeOutboxService.deleteEvent(entityId: ticketId);
      await RealtimeOutboxService.insertEvent(
        entityType: 'employee_requests',
        eventType: 'request.cancelled',
        entityId: ticketId,
        tenantId: orgId,
        actorId: user.resolvedEmployeeId,
        payload: {'id': ticketId, 'cancelled': true},
      );

      secureLog('[HelpdeskRepo] Request $ticketId marked CANCELLED');
      return true;
    } catch (e) {
      secureLog('[HelpdeskRepo] withdrawHelpdeskTicket error: $e');
      return false;
    }
  }

  // ============================================================
  // 2. DYNAMIC SERVICE DEFINITIONS & REQUESTS (MAPPED TO CANONICAL employee_requests)
  // ============================================================

  Future<List<ServiceDefinitionModel>> getServiceDefinitions() async {
    // Canonical 64-table database models requests directly in employee_requests
    return [];
  }

  Future<List<ServiceRequestModel>> getServiceRequests(String employeeId) async {
    if (!SupabaseConfig.isConfigured) return [];
    try {
      final user = UserService.instance.currentUser;
      final empId = user.employeeUuid ?? user.employeeId;

      final rows = await _client
          .from('employee_requests')
          .select('*')
          .eq('employee_id', empId)
          .order('created_at', ascending: false);

      return (rows as List).map((r) {
        final reqId = r['id']?.toString() ?? '';
        return ServiceRequestModel(
          id: reqId,
          requestNumber: r['request_number']?.toString() ?? (reqId.length >= 8 ? 'REQ-${reqId.substring(0, 8).toUpperCase()}' : 'REQ-001'),
          employeeId: r['employee_id']?.toString() ?? empId,
          employeeName: r['employee_name']?.toString() ?? user.name,
          serviceName: r['title']?.toString() ?? r['request_type']?.toString() ?? 'Service Request',
          category: r['request_type']?.toString() ?? 'General',
          status: r['status']?.toString() ?? 'SUBMITTED',
          priority: r['priority']?.toString() ?? 'MEDIUM',
          formData: {'description': r['description']},
          submittedAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      secureLog('[HelpdeskRepo] getRequests error: $e');
      return [];
    }
  }

  Future<ServiceRequestModel?> submitServiceRequest({
    required ServiceDefinitionModel definition,
    required Map<String, dynamic> formData,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    if (!SupabaseConfig.isConfigured) return null;
    try {
      final user = UserService.instance.currentUser;
      final empId = user.employeeUuid ?? user.employeeId;
      final tenantId = user.companyId.isNotEmpty
          ? user.companyId
          : (user.organizationId?.isNotEmpty == true ? user.organizationId! : '');
      final reqNumber = 'SR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      final insertPayload = <String, dynamic>{
        if (_isValidUuid(tenantId)) 'organization_id': tenantId,
        'employee_id': empId,
        'request_type': definition.category.isNotEmpty ? definition.category : 'HELP_DESK',
        'subject': definition.name.isNotEmpty ? definition.name : 'Helpdesk Request',
        'description': formData.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
        'status': 'OPEN',
        'priority': 'MEDIUM',
      };

      final data = await _client.from('employee_requests').insert(insertPayload).select().single();
      final reqId = data['id']?.toString() ?? '';
      return ServiceRequestModel(
        id: reqId,
        requestNumber: reqNumber,
        employeeId: empId,
        employeeName: user.name,
        serviceName: definition.name,
        category: definition.category,
        status: 'SUBMITTED',
        formData: formData,
        submittedAt: DateTime.now(),
      );
    } catch (e) {
      secureLog('[HelpdeskRepo] submitRequest error: $e');
      return null;
    }
  }

  // ============================================================
  // 3. COMMUNICATIONS & ACKNOWLEDGEMENTS (CANONICAL notification_events)
  // ============================================================

  Future<List<CommunicationModel>> getCommunications(String employeeId) async {
    if (!SupabaseConfig.isConfigured) return [];
    try {
      // Query canonical company-wide announcements from notification_events
      // recipient_user_id IS NULL ensures private employee notifications are excluded
      final rows = await _client
          .from('notification_events')
          .select('*')
          .eq('channel', 'IN_APP')
          .isFilter('recipient_user_id', null)
          .order('created_at', ascending: false)
          .limit(50);

      final List<CommunicationModel> result = [];
      for (final r in rows) {
        final id = r['id']?.toString() ?? '';
        final isRead = r['is_read'] == true;
        result.add(CommunicationModel(
          id: id,
          title: r['title']?.toString() ?? 'Announcement',
          body: r['message']?.toString() ?? '',
          communicationType: 'ANNOUNCEMENT',
          priority: 'NORMAL',
          status: 'PUBLISHED',
          requiresAcknowledgement: false,
          authorName: 'HR Management',
          publishAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
          isRead: isRead,
        ));
      }
      return result;
    } catch (e) {
      secureLog('[HelpdeskRepo] getCommunications error: $e');
      return [];
    }
  }

  Future<bool> acknowledgeCommunication(String communicationId) async {
    if (!SupabaseConfig.isConfigured || communicationId.isEmpty) return false;
    try {
      await _client
          .from('notification_events')
          .update({'is_read': true})
          .eq('id', communicationId);
      return true;
    } catch (e) {
      secureLog('[HelpdeskRepo] acknowledge error: $e');
      return false;
    }
  }

  Future<bool> markCommunicationAsRead(String communicationId) async {
    if (!SupabaseConfig.isConfigured || communicationId.isEmpty) return false;
    try {
      final nowStr = DateTime.now().toIso8601String();
      try {
        await _client
            .from('notification_events')
            .update({'is_read': true})
            .eq('id', communicationId);
      } catch (_) {}

      try {
        await _client
            .from('notification_deliveries')
            .update({
              'status': 'READ',
              'read_at': nowStr,
            })
            .eq('notification_id', communicationId);
      } catch (_) {}

      return true;
    } catch (e) {
      secureLog('[HelpdeskRepo] markCommunicationAsRead error: $e');
      return false;
    }
  }
}
