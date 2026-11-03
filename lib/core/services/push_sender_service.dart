import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';

/// PushSenderService — Send FCM push notifications from the app.
///
/// Calls the `send-push` Supabase Edge Function which uses Firebase Admin SDK
/// to deliver push notifications to employee devices.
///
/// Also calls the `send_push_notification` RPC as a fallback for database-side triggers.
class PushSenderService {
  PushSenderService._();
  static final PushSenderService instance = PushSenderService._();

  /// Send a push notification to a specific employee.
  ///
  /// [employeeId] — the employee UUID or employee_id
  /// [title] — notification title
  /// [body] — notification body text
  /// [route] — deep-link route (e.g. 'leaves', 'attendance', 'documents')
  /// [data] — optional extra data payload
  Future<bool> sendToEmployee({
    required String employeeId,
    required String title,
    required String body,
    String route = 'home',
    Map<String, dynamic>? data,
  }) async {
    if (!SupabaseConfig.isConfigured) return false;

    try {
      final client = Supabase.instance.client;

      // Method 1: Call Edge Function directly
      try {
        final response = await client.functions.invoke(
          'send-push',
          body: {
            'employee_id': employeeId,
            'title': title,
            'body': body,
            'route': route,
            'data': data ?? {},
          },
        );

        if (response.status == 200) {
          secureLog('[PushSender] Edge function sent push to $employeeId');
          return true;
        }
      } catch (e) {
        secureLog('[PushSender] Edge function call failed, trying RPC: $e');
      }

      // Method 2: Fallback to database RPC
      try {
        await client.rpc('send_push_notification', params: {
          'p_employee_id': employeeId,
          'p_title': title,
          'p_body': body,
          'p_route': route,
          'p_data': data ?? {},
        });
        secureLog('[PushSender] RPC sent push to $employeeId');
        return true;
      } catch (e) {
        secureLog('[PushSender] RPC also failed: $e');
      }

      return false;
    } catch (e) {
      secureLog('[PushSender] Error: $e');
      return false;
    }
  }

  /// Send push to multiple employees at once.
  Future<int> sendToMultiple({
    required List<String> employeeIds,
    required String title,
    required String body,
    String route = 'home',
    Map<String, dynamic>? data,
  }) async {
    int sentCount = 0;
    for (final empId in employeeIds) {
      final success = await sendToEmployee(
        employeeId: empId,
        title: title,
        body: body,
        route: route,
        data: data,
      );
      if (success) sentCount++;
    }
    return sentCount;
  }

  /// Convenience: Send leave-related push notification.
  Future<bool> sendLeaveNotification({
    required String employeeId,
    required String status, // APPROVED, REJECTED, PENDING
    required String leaveType,
    String? dateRange,
    String? rejectionReason,
  }) async {
    final title = 'Leave ${status[0].toUpperCase()}${status.substring(1).toLowerCase()}';
    final body = rejectionReason != null && rejectionReason.isNotEmpty
        ? 'Your $leaveType request was $status. Reason: $rejectionReason'
        : 'Your $leaveType request has been ${status.toLowerCase()}${dateRange != null ? ' for $dateRange' : ''}';

    return sendToEmployee(
      employeeId: employeeId,
      title: title,
      body: body,
      route: 'leaves',
      data: {'status': status, 'leave_type': leaveType},
    );
  }

  /// Convenience: Send attendance regularization push notification.
  Future<bool> sendRegularizationNotification({
    required String employeeId,
    required String status,
    String? attendanceDate,
  }) async {
    final title = 'Regularization ${status[0].toUpperCase()}${status.substring(1).toLowerCase()}';
    final body = attendanceDate != null
        ? 'Your attendance regularization for $attendanceDate was ${status.toLowerCase()}.'
        : 'Your attendance regularization request was ${status.toLowerCase()}.';

    return sendToEmployee(
      employeeId: employeeId,
      title: title,
      body: body,
      route: 'attendance',
      data: {'status': status, 'attendance_date': attendanceDate ?? ''},
    );
  }

  /// Convenience: Send document request push notification.
  Future<bool> sendDocumentRequestNotification({
    required String employeeId,
    required String documentType,
    String? dueDate,
  }) async {
    const title = 'Document Required by HR';
    final body = dueDate != null
        ? 'Please upload your $documentType by $dueDate.'
        : 'HR has requested you to upload: $documentType';

    return sendToEmployee(
      employeeId: employeeId,
      title: title,
      body: body,
      route: 'documents',
      data: {'document_type': documentType, 'due_date': dueDate ?? ''},
    );
  }

  /// Convenience: Send payslip notification.
  Future<bool> sendPayslipNotification({
    required String employeeId,
    required String monthName,
    required String year,
  }) async {
    return await sendToEmployee(
      employeeId: employeeId,
      title: 'Payslip Released',
      body: 'Your $monthName $year salary statement is now available.',
      route: 'more',
      data: {'month': monthName, 'year': year},
    );
  }

  /// Convenience: Send announcement push to all employees.
  Future<int> sendAnnouncementToAll({
    required String title,
    required String body,
    required List<String> employeeIds,
    String priority = 'NORMAL',
  }) async {
    return sendToMultiple(
      employeeIds: employeeIds,
      title: title,
      body: body,
      route: 'announcements',
      data: {'priority': priority},
    );
  }
}
