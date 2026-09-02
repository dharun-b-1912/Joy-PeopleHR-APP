// ============================================================
// JOY PeopleHR — Employee Relations, Helpdesk & Services Models
// ============================================================

enum HelpdeskStatus {
  open,
  assigned,
  inProgress,
  waitingForEmployee,
  waitingForHr,
  escalated,
  resolved,
  closed,
  reopened,
}

enum TicketPriority {
  low,
  medium,
  high,
  urgent,
}

class HelpdeskMessageModel {
  final String id;
  final String ticketId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String message;
  final String visibility; // EMPLOYEE or INTERNAL
  final List<Map<String, dynamic>> attachments;
  final DateTime createdAt;

  HelpdeskMessageModel({
    required this.id,
    required this.ticketId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.visibility,
    this.attachments = const [],
    required this.createdAt,
  });

  factory HelpdeskMessageModel.fromJson(Map<String, dynamic> json) {
    return HelpdeskMessageModel(
      id: json['id']?.toString() ?? '',
      ticketId: json['ticket_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? 'Support Agent',
      senderRole: json['sender_role']?.toString() ?? 'HR',
      message: json['message']?.toString() ?? '',
      visibility: json['visibility']?.toString() ?? 'EMPLOYEE',
      attachments: (json['attachments'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class HelpdeskTicketModel {
  final String id;
  final String ticketNumber;
  final String employeeId;
  final String? employeeCode;
  final String employeeName;
  final String? department;
  final String category;
  final String subject;
  final String description;
  final TicketPriority priority;
  final HelpdeskStatus status;
  final String? assignedToName;
  final int slaHours;
  final DateTime? slaDueAt;
  final DateTime? resolvedAt;
  final String? resolutionSummary;
  final List<Map<String, dynamic>> attachments;
  final DateTime createdAt;

  HelpdeskTicketModel({
    required this.id,
    required this.ticketNumber,
    required this.employeeId,
    this.employeeCode,
    required this.employeeName,
    this.department,
    required this.category,
    required this.subject,
    required this.description,
    required this.priority,
    required this.status,
    this.assignedToName,
    this.slaHours = 48,
    this.slaDueAt,
    this.resolvedAt,
    this.resolutionSummary,
    this.attachments = const [],
    required this.createdAt,
  });

  factory HelpdeskTicketModel.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status']?.toString() ?? 'OPEN').toUpperCase();
    HelpdeskStatus st = HelpdeskStatus.open;
    if (rawStatus == 'ASSIGNED') st = HelpdeskStatus.assigned;
    if (rawStatus == 'IN_PROGRESS') st = HelpdeskStatus.inProgress;
    if (rawStatus == 'WAITING_FOR_EMPLOYEE') st = HelpdeskStatus.waitingForEmployee;
    if (rawStatus == 'WAITING_FOR_HR') st = HelpdeskStatus.waitingForHr;
    if (rawStatus == 'ESCALATED') st = HelpdeskStatus.escalated;
    if (rawStatus == 'RESOLVED') st = HelpdeskStatus.resolved;
    if (rawStatus == 'CLOSED') st = HelpdeskStatus.closed;
    if (rawStatus == 'REOPENED') st = HelpdeskStatus.reopened;

    final rawPri = (json['priority']?.toString() ?? 'MEDIUM').toUpperCase();
    TicketPriority pri = TicketPriority.medium;
    if (rawPri == 'LOW') pri = TicketPriority.low;
    if (rawPri == 'HIGH') pri = TicketPriority.high;
    if (rawPri == 'URGENT') pri = TicketPriority.urgent;

    return HelpdeskTicketModel(
      id: json['id']?.toString() ?? '',
      ticketNumber: json['ticket_number']?.toString() ?? 'TKT-000',
      employeeId: json['employee_id']?.toString() ?? '',
      employeeCode: json['employee_code']?.toString(),
      employeeName: json['employee_name']?.toString() ?? 'Employee',
      department: json['department']?.toString(),
      category: json['category']?.toString() ?? 'General HR',
      subject: json['subject']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      priority: pri,
      status: st,
      assignedToName: json['assigned_to_name']?.toString(),
      slaHours: (json['sla_hours'] as num?)?.toInt() ?? 48,
      slaDueAt: DateTime.tryParse(json['sla_due_at']?.toString() ?? ''),
      resolvedAt: DateTime.tryParse(json['resolved_at']?.toString() ?? ''),
      resolutionSummary: json['resolution_summary']?.toString(),
      attachments: (json['attachments'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

// ============================================================
// DYNAMIC SERVICE DEFINITIONS & REQUESTS
// ============================================================

enum ServiceFieldType {
  text,
  textarea,
  number,
  date,
  datetime,
  dropdown,
  multiSelect,
  checkbox,
  radio,
  amount,
  attachment,
}

class ServiceFormFieldModel {
  final String id;
  final String label;
  final ServiceFieldType type;
  final bool required;
  final String? placeholder;
  final List<String> options;
  final String? helpText;

  ServiceFormFieldModel({
    required this.id,
    required this.label,
    required this.type,
    this.required = true,
    this.placeholder,
    this.options = const [],
    this.helpText,
  });

  factory ServiceFormFieldModel.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type']?.toString() ?? 'TEXT').toUpperCase();
    ServiceFieldType ft = ServiceFieldType.text;
    if (rawType == 'TEXTAREA') ft = ServiceFieldType.textarea;
    if (rawType == 'NUMBER') ft = ServiceFieldType.number;
    if (rawType == 'DATE') ft = ServiceFieldType.date;
    if (rawType == 'DATETIME') ft = ServiceFieldType.datetime;
    if (rawType == 'DROPDOWN') ft = ServiceFieldType.dropdown;
    if (rawType == 'MULTI_SELECT') ft = ServiceFieldType.multiSelect;
    if (rawType == 'CHECKBOX') ft = ServiceFieldType.checkbox;
    if (rawType == 'RADIO') ft = ServiceFieldType.radio;
    if (rawType == 'AMOUNT') ft = ServiceFieldType.amount;
    if (rawType == 'ATTACHMENT') ft = ServiceFieldType.attachment;

    return ServiceFormFieldModel(
      id: json['id']?.toString() ?? 'field',
      label: json['label']?.toString() ?? 'Field',
      type: ft,
      required: json['required'] == true,
      placeholder: json['placeholder']?.toString(),
      options: (json['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
      helpText: json['helpText']?.toString() ?? json['help_text']?.toString(),
    );
  }
}

class ServiceDefinitionModel {
  final String id;
  final String code;
  final String name;
  final String category;
  final String? description;
  final String icon;
  final bool enabled;
  final bool employeeVisible;
  final bool requiresAttachment;
  final int slaHours;
  final List<ServiceFormFieldModel> formSchema;

  ServiceDefinitionModel({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    this.description,
    this.icon = 'file-text',
    this.enabled = true,
    this.employeeVisible = true,
    this.requiresAttachment = false,
    this.slaHours = 48,
    this.formSchema = const [],
  });

  factory ServiceDefinitionModel.fromJson(Map<String, dynamic> json) {
    final schemaList = (json['form_schema'] as List?)
            ?.map((e) => ServiceFormFieldModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];

    return ServiceDefinitionModel(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Service',
      category: json['category']?.toString() ?? 'General',
      description: json['description']?.toString(),
      icon: json['icon']?.toString() ?? 'file-text',
      enabled: json['enabled'] != false,
      employeeVisible: json['employee_visible'] != false,
      requiresAttachment: json['requires_attachment'] == true,
      slaHours: (json['sla_hours'] as num?)?.toInt() ?? 48,
      formSchema: schemaList,
    );
  }
}

class ServiceRequestModel {
  final String id;
  final String requestNumber;
  final String employeeId;
  final String? employeeCode;
  final String employeeName;
  final String? serviceDefinitionId;
  final String serviceName;
  final String category;
  final String status; // SUBMITTED, PENDING_MANAGER, PENDING_HR, APPROVED, REJECTED, ACTION_REQUIRED, COMPLETED
  final String priority;
  final Map<String, dynamic> formData;
  final List<Map<String, dynamic>> attachments;
  final String? assignedToName;
  final int currentStep;
  final String? rejectionReason;
  final String? resolutionNotes;
  final DateTime submittedAt;
  final DateTime? completedAt;

  ServiceRequestModel({
    required this.id,
    required this.requestNumber,
    required this.employeeId,
    this.employeeCode,
    required this.employeeName,
    this.serviceDefinitionId,
    required this.serviceName,
    required this.category,
    required this.status,
    this.priority = 'MEDIUM',
    this.formData = const {},
    this.attachments = const [],
    this.assignedToName,
    this.currentStep = 1,
    this.rejectionReason,
    this.resolutionNotes,
    required this.submittedAt,
    this.completedAt,
  });

  factory ServiceRequestModel.fromJson(Map<String, dynamic> json) {
    return ServiceRequestModel(
      id: json['id']?.toString() ?? '',
      requestNumber: json['request_number']?.toString() ?? 'SR-000',
      employeeId: json['employee_id']?.toString() ?? '',
      employeeCode: json['employee_code']?.toString(),
      employeeName: json['employee_name']?.toString() ?? 'Employee',
      serviceDefinitionId: json['service_definition_id']?.toString(),
      serviceName: json['service_name']?.toString() ?? 'Service Request',
      category: json['category']?.toString() ?? 'General',
      status: json['status']?.toString() ?? 'SUBMITTED',
      priority: json['priority']?.toString() ?? 'MEDIUM',
      formData: (json['form_data'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? {},
      attachments: (json['attachments'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      assignedToName: json['assigned_to_name']?.toString(),
      currentStep: (json['current_step'] as num?)?.toInt() ?? 1,
      rejectionReason: json['rejection_reason']?.toString(),
      resolutionNotes: json['resolution_notes']?.toString(),
      submittedAt: DateTime.tryParse(json['submitted_at']?.toString() ?? '') ?? DateTime.now(),
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
    );
  }
}

// ============================================================
// COMMUNICATION / ANNOUNCEMENT MODEL
// ============================================================

class CommunicationModel {
  final String id;
  final String title;
  final String body;
  final String communicationType;
  final String priority;
  final String status;
  final bool requiresAcknowledgement;
  final String authorName;
  final DateTime publishAt;
  final DateTime? acknowledgedAt;
  final bool isRead;

  CommunicationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.communicationType,
    required this.priority,
    required this.status,
    required this.requiresAcknowledgement,
    required this.authorName,
    required this.publishAt,
    this.acknowledgedAt,
    this.isRead = false,
  });

  factory CommunicationModel.fromJson(Map<String, dynamic> json, {DateTime? userAckDate, bool isRead = false}) {
    return CommunicationModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['content']?.toString() ?? json['body']?.toString() ?? '',
      communicationType: json['category']?.toString() ?? json['communication_type']?.toString() ?? 'ANNOUNCEMENT',
      priority: json['is_pinned'] == true ? 'IMPORTANT' : (json['priority']?.toString() ?? 'NORMAL'),
      status: json['status']?.toString() ?? 'PUBLISHED',
      requiresAcknowledgement: json['requires_acknowledgement'] == true,
      authorName: json['author_name']?.toString() ?? json['category']?.toString() ?? 'HR Team',
      publishAt: DateTime.tryParse(json['publish_at']?.toString() ?? json['created_at']?.toString() ?? '') ?? DateTime.now(),
      acknowledgedAt: userAckDate ?? DateTime.tryParse(json['acknowledged_at']?.toString() ?? ''),
      isRead: isRead || json['is_read'] == true,
    );
  }

  CommunicationModel copyWith({
    String? id,
    String? title,
    String? body,
    String? communicationType,
    String? priority,
    String? status,
    bool? requiresAcknowledgement,
    String? authorName,
    DateTime? publishAt,
    DateTime? acknowledgedAt,
    bool? isRead,
  }) {
    return CommunicationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      communicationType: communicationType ?? this.communicationType,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      requiresAcknowledgement: requiresAcknowledgement ?? this.requiresAcknowledgement,
      authorName: authorName ?? this.authorName,
      publishAt: publishAt ?? this.publishAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      isRead: isRead ?? this.isRead,
    );
  }
}
