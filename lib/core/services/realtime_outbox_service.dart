import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/secure_log.dart';
import 'user_service.dart';

/// Centralized helper service for broadcasting events to Supabase `realtime_outbox`
class RealtimeOutboxService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Broadcasts an event to `realtime_outbox`
  static Future<void> insertEvent({
    required String entityType,
    required String eventType,
    required String entityId,
    String? tenantId,
    String? organizationId,
    String? actorId,
    Map<String, dynamic>? payload,
  }) async {
    if (!SupabaseConfig.isConfigured) return;

    try {
      final user = UserService.instance.currentUser;
      final resolvedTenantId = (tenantId?.isNotEmpty == true)
          ? tenantId!
          : user.tenantId;
      final resolvedOrgId = (organizationId?.isNotEmpty == true)
          ? organizationId!
          : (resolvedTenantId.isNotEmpty ? resolvedTenantId : user.tenantId);
      final resolvedActorId = (actorId?.isNotEmpty == true)
          ? actorId!
          : user.resolvedEmployeeId;

      await _client.from('realtime_outbox').insert({
        if (resolvedTenantId.isNotEmpty) 'tenant_id': resolvedTenantId,
        if (resolvedOrgId.isNotEmpty) 'organization_id': resolvedOrgId,
        'entity_type': entityType,
        'entity_id': entityId,
        'event_type': eventType,
        if (resolvedActorId.isNotEmpty) 'actor_id': resolvedActorId,
        if (payload != null) 'payload': payload,
      });

      secureLog('[Outbox] Emitted event $eventType for $entityType ($entityId)');
    } catch (e) {
      secureLog('[Outbox] Event emit notice: $e');
    }
  }

  /// Deletes an outbox entry by entity_id or id
  static Future<void> deleteEvent({
    String? entityId,
    String? id,
  }) async {
    if (!SupabaseConfig.isConfigured) return;

    try {
      if (id != null && id.isNotEmpty) {
        await _client.from('realtime_outbox').delete().eq('id', id);
      } else if (entityId != null && entityId.isNotEmpty) {
        await _client.from('realtime_outbox').delete().eq('entity_id', entityId);
      }
    } catch (e) {
      secureLog('[Outbox] Delete event notice: $e');
    }
  }
}
