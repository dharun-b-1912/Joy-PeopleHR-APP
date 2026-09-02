import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/secure_log.dart';
import '../../models/employee_models.dart';
import '../../models/employee_relations_models.dart';
import '../../repositories/interfaces/employee_repository.dart';
import '../../repositories/supabase/supabase_employee_relations_repository.dart';
import '../../repositories/supabase/supabase_more_modules_repository.dart';
import '../services/document_upload_service.dart';
import '../services/user_service.dart';

class MoreModulesController extends ChangeNotifier {
  static final MoreModulesController instance =
      MoreModulesController._internal(SupabaseMoreModulesRepository());
  MoreModulesController._internal(this._repo);

  final IMoreModulesRepository _repo;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<EmployeeServiceConfigModel> serviceConfigs = [];
  List<ShiftRosterModel> rosters = [];
  List<PayslipModel> payslips = [];
  List<ExpenseClaimModel> claims = [];
  List<DigitalLetterModel> letters = [];
  List<DocumentModel> documents = [];
  List<PerformanceGoalModel> goals = [];
  List<AnnouncementModel> announcements = [];
  List<ComplaintModel> complaints = [];

  // Module A, B, C state
  List<HelpdeskTicketModel> helpdeskTickets = [];
  List<ServiceDefinitionModel> serviceDefinitions = [];
  List<ServiceRequestModel> serviceRequests = [];
  List<CommunicationModel> communicationsList = [];

  int get pendingClaimsCount => claims.where((c) => c.status == ExpenseStatus.pending).length;
  int get actionRequiredDocsCount => documents.where((d) => d.isPending || d.isRejected).length;
  int get pendingGrievancesCount => complaints.where((c) => c.status == ComplaintStatus.submitted || c.status == ComplaintStatus.underReview).length;
  int get openTicketsCount => helpdeskTickets.where((t) => t.status == HelpdeskStatus.open || t.status == HelpdeskStatus.inProgress).length;
  int get unreadCommunicationsCount => communicationsList.where((c) => !c.isRead).length;

  RealtimeChannel? _documentsChannel;
  String? _subscribedDocEmpId;

  void initialize() {
    UserService.instance.addListener(loadAllData);
    loadAllData();
  }

  void _subscribeRealtime(String employeeId) {
    if (_subscribedDocEmpId == employeeId && _documentsChannel != null) return;
    _documentsChannel?.unsubscribe();

    try {
      _subscribedDocEmpId = employeeId;
      _documentsChannel = Supabase.instance.client
          .channel('more-modules-realtime-$employeeId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'employee_service_configs',
          callback: (payload) {
            secureLog('[REALTIME] employee_service_configs change event');
            loadAllData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'expense_claims',
          callback: (payload) {
            secureLog('[REALTIME] expense_claims change event');
            loadAllData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'digital_letters',
          callback: (payload) {
            secureLog('[REALTIME] digital_letters change event');
            loadAllData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'helpdesk_tickets',
          callback: (payload) {
            secureLog('[REALTIME] helpdesk_tickets change event');
            loadAllData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'helpdesk_messages',
          callback: (payload) {
            secureLog('[REALTIME] helpdesk_messages change event');
            loadAllData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_definitions',
          callback: (payload) {
            secureLog('[REALTIME] service_definitions change event');
            loadAllData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_requests',
          callback: (payload) {
            secureLog('[REALTIME] service_requests change event');
            loadAllData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'communications',
          callback: (payload) {
            secureLog('[REALTIME] communications change event');
            loadAllData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'employee_documents',
          callback: (payload) {
            secureLog('[REALTIME] employee_documents change event');
            _silentRefreshDocuments();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shift_rosters',
          callback: (payload) {
            secureLog('[REALTIME] shift_rosters change event');
            _silentRefreshDocuments();
          },
        )
        ..subscribe();
    } catch (e) {
      secureLog('[REALTIME] More Modules subscription notice: $e');
    }
  }

  Future<void> _silentRefreshDocuments() async {
    try {
      final user = UserService.instance.currentUser;
      final empId = user.resolvedEmployeeId;
      final results = await Future.wait([
        _repo.getPayslips(empId),
        _repo.getDocuments(empId, companyId: user.tenantId, requesterRole: user.role),
        _repo.getShiftRoster(empId),
        _repo.getExpenseClaims(empId),
        _repo.getDigitalLetters(empId),
      ]);
      payslips = results[0] as List<PayslipModel>;
      documents = results[1] as List<DocumentModel>;
      rosters = results[2] as List<ShiftRosterModel>;
      claims = results[3] as List<ExpenseClaimModel>;
      letters = results[4] as List<DigitalLetterModel>;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadAllData() async {
    final hasExistingData = documents.isNotEmpty || rosters.isNotEmpty || letters.isNotEmpty;
    if (!hasExistingData) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final user = UserService.instance.currentUser;
      final empId = user.resolvedEmployeeId;
      if (empId.isNotEmpty) {
        _subscribeRealtime(empId);
      }

      final results = await Future.wait([
        _repo.getServiceConfigs(user.tenantId),
        _repo.getShiftRoster(empId),
        _repo.getPayslips(empId),
        _repo.getExpenseClaims(empId),
        _repo.getDigitalLetters(empId),
        _repo.getDocuments(empId, companyId: user.tenantId, requesterRole: user.role),
        _repo.getAnnouncements(),
        _repo.getComplaints(empId),
        SupabaseEmployeeRelationsRepository.instance.getHelpdeskTickets(empId),
        SupabaseEmployeeRelationsRepository.instance.getServiceDefinitions(),
        SupabaseEmployeeRelationsRepository.instance.getServiceRequests(empId),
        SupabaseEmployeeRelationsRepository.instance.getCommunications(empId),
        _repo.getPerformanceGoals(empId),
      ]);

      serviceConfigs = results[0] as List<EmployeeServiceConfigModel>;
      rosters = results[1] as List<ShiftRosterModel>;
      payslips = results[2] as List<PayslipModel>;
      claims = results[3] as List<ExpenseClaimModel>;
      letters = results[4] as List<DigitalLetterModel>;
      documents = results[5] as List<DocumentModel>;
      announcements = results[6] as List<AnnouncementModel>;
      complaints = results[7] as List<ComplaintModel>;
      helpdeskTickets = results[8] as List<HelpdeskTicketModel>;
      serviceDefinitions = results[9] as List<ServiceDefinitionModel>;
      serviceRequests = results[10] as List<ServiceRequestModel>;
      communicationsList = results[11] as List<CommunicationModel>;
      goals = results[12] as List<PerformanceGoalModel>;
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> uploadDocument({
    required String documentType,
    required String fileName,
    required String fileExtension,
    required String fileSize,
    Uint8List? fileBytes,
    String? filePath,
  }) async {
    try {
      final user = UserService.instance.currentUser;
      final empId = user.resolvedEmployeeId;

      if (empId.isEmpty) {
        secureLog('[MoreModulesController] uploadDocument error: Employee ID missing');
        return false;
      }

      Uint8List? bytes = fileBytes;
      if (bytes == null && filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) {
        secureLog('[MoreModulesController] uploadDocument error: No file content found');
        return false;
      }

      final storageUrl = await DocumentUploadService.instance.uploadEmployeeDocument(
        employeeId: empId,
        documentType: documentType,
        fileName: fileName,
        bytes: bytes,
        documentCategory: 'PERSONAL',
        tenantId: user.tenantId,
        employeeName: user.name,
      );

      if (storageUrl != null) {
        await loadAllData();
        return true;
      }
      return false;
    } catch (e) {
      secureLog('[MoreModulesController] uploadDocument exception: $e');
      return false;
    }
  }

  Future<bool> submitExpenseClaim({
    required String title,
    required String category,
    required double amount,
    required String description,
    Uint8List? receiptBytes,
    String? receiptFileName,
  }) async {
    try {
      final user = UserService.instance.currentUser;
      String? uploadedUrl;

      if (receiptBytes != null && receiptFileName != null && receiptFileName.isNotEmpty) {
        uploadedUrl = await DocumentUploadService.instance.uploadExpenseReceipt(
          tenantId: user.tenantId,
          employeeId: user.resolvedEmployeeId,
          bytes: receiptBytes,
          fileName: receiptFileName,
        );
      }

      final claim = ExpenseClaimModel(
        id: "exp-${DateTime.now().millisecondsSinceEpoch}",
        title: title,
        category: category,
        amount: amount,
        date: DateTime.now(),
        description: description,
        status: ExpenseStatus.pending,
        attachmentName: receiptFileName,
        receiptUrl: uploadedUrl,
      );
      await _repo.submitExpenseClaim(claim);
      await loadAllData();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteDocument(String documentId, {String? storagePath, String? fileUrl}) async {
    try {
      final ok = await DocumentUploadService.instance.deleteDocument(
        documentId,
        storagePath: storagePath,
        fileUrl: fileUrl,
      );
      if (ok) {
        documents.removeWhere((d) => d.id == documentId);
        notifyListeners();
        _silentRefreshDocuments();
      }
      return ok;
    } catch (e) {
      secureLog('[MoreModulesController] deleteDocument error: $e');
      return false;
    }
  }

  Future<void> acknowledgeDigitalLetter(String letterId, {String? signatureData}) async {
    try {
      await _repo.acknowledgeDigitalLetter(letterId, signatureData: signatureData);
      await loadAllData();
    } catch (_) {}
  }

  Future<bool> submitComplaint({
    required String subject,
    required String category,
    required String description,
  }) async {
    try {
      final user = UserService.instance.currentUser;
      final companyId = user.tenantId;

      final isPosh = category == "POSH Complaint";
      final ComplaintDestinationType destType = isPosh 
          ? ComplaintDestinationType.poshCommittee 
          : ComplaintDestinationType.companyAdmin;
      final String destName = isPosh ? "POSH Committee" : "Company Admin";

      final complaint = ComplaintModel(
        id: "cmp-${DateTime.now().millisecondsSinceEpoch}",
        subject: subject,
        category: category,
        description: description,
        createdAt: DateTime.now(),
        status: ComplaintStatus.submitted,
        companyId: companyId,
        destinationType: destType,
        destinationId: null,
        destinationName: destName,
      );
      await _repo.submitComplaint(complaint);
      await loadAllData();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitHelpdeskTicket({
    required String category,
    required String subject,
    required String description,
    required TicketPriority priority,
    Uint8List? attachmentBytes,
    String? attachmentFileName,
  }) async {
    try {
      final tkt = await SupabaseEmployeeRelationsRepository.instance.submitHelpdeskTicket(
        category: category,
        subject: subject,
        description: description,
        priority: priority,
        attachmentBytes: attachmentBytes,
        attachmentFileName: attachmentFileName,
      );
      if (tkt != null) {
        await loadAllData();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> sendTicketMessage(String ticketId, String message) async {
    try {
      final msg = await SupabaseEmployeeRelationsRepository.instance.sendTicketMessage(ticketId, message);
      if (msg != null) {
        await loadAllData();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> withdrawHelpdeskTicket(String ticketId) async {
    try {
      helpdeskTickets.removeWhere((t) => t.id == ticketId || t.ticketNumber == ticketId);
      complaints.removeWhere((c) => c.id == ticketId);
      notifyListeners();

      final ok = await SupabaseEmployeeRelationsRepository.instance.withdrawHelpdeskTicket(ticketId);
      await loadAllData();
      return ok;
    } catch (_) {
      await loadAllData();
      return false;
    }
  }

  Future<bool> submitServiceRequest({
    required ServiceDefinitionModel definition,
    required Map<String, dynamic> formData,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    try {
      final req = await SupabaseEmployeeRelationsRepository.instance.submitServiceRequest(
        definition: definition,
        formData: formData,
        attachments: attachments,
      );
      if (req != null) {
        await loadAllData();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> acknowledgeCommunication(String communicationId) async {
    try {
      final ok = await SupabaseEmployeeRelationsRepository.instance.acknowledgeCommunication(communicationId);
      if (ok) {
        await loadAllData();
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  void dispose() {
    _documentsChannel?.unsubscribe();
    super.dispose();
  }
}
