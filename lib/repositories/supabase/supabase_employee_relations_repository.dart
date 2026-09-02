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

      final idFilter = candidateIds.map((c) => '"$c"').join(',');
      final rows = await _client
          .from('helpdesk_tickets')
          .select('*')
          .filter('employee_id', 'in', '($idFilter)')
          .order('created_at', ascending: false);

      return (rows as List)
          .where((r) {
            final num = r['ticket_number']?.toString() ?? '';
            return !num.startsWith('GRV') && !num.startsWith('POSH');
          })
          .map((r) => HelpdeskTicketModel.fromJson(r))
          .toList();
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
      final tenantId = orgId;

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

      final insertPayload = {
        if (tenantId.isNotEmpty) 'tenant_id': tenantId,
        if (orgId.isNotEmpty) 'organization_id': orgId,
        'employee_id': empId,
        'employee_code': user.employeeId,
        'employee_name': user.name,
        'department': user.department,
        'ticket_number': ticketNumber,
        'category': category,
        'subject': subject,
        'description': description,
        'priority': priorityStr,
        'status': 'OPEN',
        'sla_hours': priority == TicketPriority.urgent ? 4 : priority == TicketPriority.high ? 24 : 48,
        'attachments': attachments,
      };

      final data = await _client.from('helpdesk_tickets').insert(insertPayload).select().single();
      secureLog('[HelpdeskRepo] Ticket submitted successfully: ${data['id']} ($ticketNumber)');

      // Sync event to realtime_outbox via centralized service
      await RealtimeOutboxService.insertEvent(
        entityType: 'helpdesk_tickets',
        eventType: 'ticket.created',
        entityId: data['id']?.toString() ?? ticketNumber,
        tenantId: tenantId,
        actorId: empId,
        payload: data,
      );

      return HelpdeskTicketModel.fromJson(data);
    } catch (e) {
      secureLog('[HelpdeskRepo] submitTicket error: $e');
      return null;
    }
  }

  Future<List<HelpdeskMessageModel>> getTicketMessages(String ticketId) async {
    if (!SupabaseConfig.isConfigured) return [];
    try {
      final rows = await _client
          .from('helpdesk_messages')
          .select('*')
          .eq('ticket_id', ticketId)
          .eq('visibility', 'EMPLOYEE') // Never expose internal notes to mobile
          .order('created_at', ascending: true);

      return (rows as List).map((r) => HelpdeskMessageModel.fromJson(r)).toList();
    } catch (e) {
      secureLog('[HelpdeskRepo] getMessages error: $e');
      return [];
    }
  }

  Future<HelpdeskMessageModel?> sendTicketMessage(String ticketId, String message) async {
    if (!SupabaseConfig.isConfigured) return null;
    try {
      final user = UserService.instance.currentUser;
      final tenantId = user.companyId.isNotEmpty
          ? user.companyId
          : (user.organizationId?.isNotEmpty == true ? user.organizationId! : '');
      final payload = {
        'tenant_id': tenantId,
        'ticket_id': ticketId,
        'sender_id': user.employeeUuid ?? user.employeeId,
        'sender_name': user.name,
        'sender_role': 'EMPLOYEE',
        'message': message,
        'visibility': 'EMPLOYEE',
      };

      final data = await _client.from('helpdesk_messages').insert(payload).select().single();
      return HelpdeskMessageModel.fromJson(data);
    } catch (e) {
      secureLog('[HelpdeskRepo] sendMessage error: $e');
      return null;
    }
  }

  Future<bool> withdrawHelpdeskTicket(String ticketId) async {
    if (!SupabaseConfig.isConfigured) return false;
    try {
      final user = UserService.instance.currentUser;
      final orgId = user.tenantId;

      // 1. Delete associated messages
      try {
        await _client.from('helpdesk_messages').delete().eq('ticket_id', ticketId);
      } catch (_) {}

      // 2. Delete the ticket permanently from helpdesk_tickets
      try {
        await _client.from('helpdesk_tickets').delete().eq('id', ticketId);
      } catch (_) {}
      try {
        await _client.from('helpdesk_tickets').delete().eq('ticket_number', ticketId);
      } catch (_) {}

      // 3. Sync deletion to realtime_outbox via centralized service
      await RealtimeOutboxService.deleteEvent(entityId: ticketId);
      await RealtimeOutboxService.insertEvent(
        entityType: 'helpdesk_tickets',
        eventType: 'ticket.deleted',
        entityId: ticketId,
        tenantId: orgId,
        actorId: user.resolvedEmployeeId,
        payload: {'id': ticketId, 'deleted': true},
      );

      secureLog('[HelpdeskRepo] Ticket $ticketId permanently withdrawn and deleted');
      return true;
    } catch (e) {
      secureLog('[HelpdeskRepo] withdrawHelpdeskTicket error: $e');
      return false;
    }
  }

  // ============================================================
  // 2. DYNAMIC SERVICE DEFINITIONS & REQUESTS
  // ============================================================

  Future<List<ServiceDefinitionModel>> getServiceDefinitions() async {
    if (!SupabaseConfig.isConfigured) return [];
    try {
      final rows = await _client
          .from('service_definitions')
          .select('*')
          .eq('enabled', true)
          .eq('employee_visible', true)
          .order('name', ascending: true);

      return (rows as List).map((r) => ServiceDefinitionModel.fromJson(r)).toList();
    } catch (e) {
      secureLog('[HelpdeskRepo] getDefinitions error: $e');
      return [];
    }
  }

  Future<List<ServiceRequestModel>> getServiceRequests(String employeeId) async {
    if (!SupabaseConfig.isConfigured) return [];
    try {
      final user = UserService.instance.currentUser;
      final Set<String> candidateIds = {
        employeeId,
        user.dataId,
        user.employeeId,
        if (user.employeeUuid != null && user.employeeUuid!.isNotEmpty) user.employeeUuid!,
      }.where((s) => s.isNotEmpty).toSet();

      final idFilter = candidateIds.map((c) => '"$c"').join(',');
      final rows = await _client
          .from('service_requests')
          .select('*')
          .filter('employee_id', 'in', '($idFilter)')
          .order('submitted_at', ascending: false);

      return (rows as List).map((r) => ServiceRequestModel.fromJson(r)).toList();
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

      final insertPayload = {
        'tenant_id': tenantId,
        'organization_id': tenantId,
        'employee_id': empId,
        'employee_code': user.employeeId,
        'employee_name': user.name,
        'department': user.department,
        'service_definition_id': definition.id.isNotEmpty ? definition.id : null,
        'service_code': definition.code,
        'service_name': definition.name,
        'category': definition.category,
        'request_number': reqNumber,
        'status': 'SUBMITTED',
        'priority': 'MEDIUM',
        'form_data': formData,
        'attachments': attachments,
      };

      final data = await _client.from('service_requests').insert(insertPayload).select().single();
      return ServiceRequestModel.fromJson(data);
    } catch (e) {
      secureLog('[HelpdeskRepo] submitRequest error: $e');
      return null;
    }
  }

  // ============================================================
  // 3. COMMUNICATIONS & ACKNOWLEDGEMENTS
  // ============================================================

  Future<List<CommunicationModel>> getCommunications(String employeeId) async {
    if (!SupabaseConfig.isConfigured) return [];
    try {
      final user = UserService.instance.currentUser;
      final empId = user.employeeUuid ?? user.employeeId;

      List<dynamic> allRows = [];

      // 1. Fetch from company_announcements table
      try {
        final annRows = await _client
            .from('company_announcements')
            .select('*')
            .order('is_pinned', ascending: false)
            .order('created_at', ascending: false);
        allRows.addAll(annRows);
      } catch (e) {
        secureLog('[HelpdeskRepo] company_announcements notice: $e');
      }

      // 2. Fetch from communications table
      try {
        final commRows = await _client
            .from('communications')
            .select('*')
            .order('created_at', ascending: false);
        allRows.addAll(commRows);
      } catch (e) {
        secureLog('[HelpdeskRepo] communications notice: $e');
      }

      // 3. Fetch user acknowledgements
      final Map<String, dynamic> ackMap = {};
      try {
        final ackRows = await _client
            .from('communication_recipients')
            .select('*')
            .eq('employee_id', empId);
        for (final a in ackRows) {
          ackMap[a['communication_id']?.toString() ?? ''] = a;
        }
      } catch (_) {}

      final List<CommunicationModel> result = [];
      for (final r in allRows) {
        final commId = r['id']?.toString() ?? '';
        if (result.any((item) => item.id == commId)) continue;

        final ack = ackMap[commId];
        final ackDate = ack != null ? DateTime.tryParse(ack['acknowledged_at']?.toString() ?? '') : null;
        final isRead = ack != null && ack['read_at'] != null;

        result.add(CommunicationModel.fromJson(r, userAckDate: ackDate, isRead: isRead));
      }
      return result;
    } catch (e) {
      secureLog('[HelpdeskRepo] getCommunications error: $e');
      return [];
    }
  }

  Future<bool> acknowledgeCommunication(String communicationId) async {
    if (!SupabaseConfig.isConfigured) return false;
    try {
      final user = UserService.instance.currentUser;
      final empId = user.employeeUuid ?? user.employeeId;
      final tenantId = user.companyId.isNotEmpty
          ? user.companyId
          : (user.organizationId?.isNotEmpty == true ? user.organizationId! : '');

      await _client.from('communication_recipients').upsert({
        'tenant_id': tenantId,
        'communication_id': communicationId,
        'employee_id': empId,
        'delivery_status': 'DELIVERED',
        'read_at': DateTime.now().toIso8601String(),
        'acknowledged_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      secureLog('[HelpdeskRepo] acknowledge error: $e');
      return false;
    }
  }

  Future<bool> markCommunicationAsRead(String communicationId) async {
    if (!SupabaseConfig.isConfigured || communicationId.isEmpty) return false;
    try {
      final user = UserService.instance.currentUser;
      final empId = user.resolvedEmployeeId;
      final tenantId = user.companyId.isNotEmpty
          ? user.companyId
          : (user.organizationId?.isNotEmpty == true ? user.organizationId! : '');

      try {
        await _client.from('communication_recipients').upsert({
          if (tenantId.isNotEmpty) 'tenant_id': tenantId,
          'communication_id': communicationId,
          'employee_id': empId,
          'delivery_status': 'DELIVERED',
          'read_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      try {
        await _client.from('company_announcement_reads').upsert({
          if (tenantId.isNotEmpty) 'tenant_id': tenantId,
          'announcement_id': communicationId,
          'employee_id': empId,
          'read_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      return true;
    } catch (e) {
      secureLog('[HelpdeskRepo] markCommunicationAsRead error: $e');
      return false;
    }
  }
}
