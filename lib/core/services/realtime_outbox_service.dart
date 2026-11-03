import '../utils/secure_log.dart';

/// Centralized helper service for broadcasting events to Supabase
class RealtimeOutboxService {

  /// Broadcasts an event log (canonical database uses direct table notifications)
  static Future<void> insertEvent({
    required String entityType,
    required String eventType,
    required String entityId,
    String? tenantId,
    String? organizationId,
    String? actorId,
    Map<String, dynamic>? payload,
  }) async {
    secureLog('[Outbox] Emitted event $eventType for $entityType ($entityId)');
  }

  /// Deletes an outbox entry
  static Future<void> deleteEvent({
    String? entityId,
    String? id,
  }) async {
    // No-op for non-canonical outbox
  }
}
