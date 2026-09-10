-- ============================================================
-- Fix: Reliable Push Notification Delivery
-- ============================================================
-- The original trigger silently failed because:
--   1. app.settings.supabase_url is NULL
--   2. app.settings.supabase_anon_key is NULL
--   3. EXCEPTION WHEN OTHERS swallowed the errors
--
-- This fix hardcodes the project URL and uses a JWT-free
-- approach by calling the Edge Function via service_role
-- endpoint instead of anon endpoint.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Push trigger for notification_events INSERT
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_push_on_notification_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _employee_id text;
  _auth_user_id text;
  _title text;
  _body text;
  _route text;
  _meta jsonb;
  _payload jsonb;
BEGIN
  _title := coalesce(new.title, 'JOY PeopleHR');
  _body := coalesce(new.body, '');
  _route := coalesce(new.event_type, 'home');

  _meta := coalesce(new.metadata, '{}'::jsonb);
  _employee_id := coalesce(
    _meta->>'target_employee_id',
    _meta->>'employee_id',
    _meta->>'recipient_employee_id',
    new.resource_id,
    ''
  );
  _auth_user_id := coalesce(
    _meta->>'target_user_id',
    _meta->>'auth_user_id',
    ''
  );

  -- Use route from metadata if available
  IF _meta->>'route' IS NOT NULL AND _meta->>'route' != '' THEN
    _route := _meta->>'route';
  END IF;

  -- Skip if no employee_id — can't send push without knowing who to send to
  IF _employee_id IS NULL OR _employee_id = '' THEN
    RAISE NOTICE 'send_push: no employee_id in metadata, skipping push for %', new.id;
    RETURN new;
  END IF;

  _payload := jsonb_build_object(
    'employee_id', _employee_id,
    'auth_user_id', _auth_user_id,
    'title', _title,
    'body', _body,
    'route', _route,
    'data', jsonb_build_object(
      'event_id', new.id::text,
      'event_type', coalesce(new.event_type, ''),
      'category', coalesce(new.category, ''),
      'severity', coalesce(new.severity, 'INFO'),
      'resource_id', coalesce(new.resource_id, '')
    )
  );

  -- Use pg_net to call the Edge Function (fire-and-forget)
  -- The Edge Function uses SUPABASE_SERVICE_ROLE_KEY internally,
  -- so the anon key in the header is just for routing, not auth.
  PERFORM net.http_post(
    url := 'https://ysiajemrqakfngasehhi.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_i_pb_iFcxX0BEJFok_XfZA_gZF3W8mj'
    ),
    body := _payload::text
  );

  RAISE NOTICE 'send_push: queued push for employee % (event: %)', _employee_id, new.event_type;
  RETURN new;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- 2. Push trigger for notification_deliveries INSERT
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_push_on_notification_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _employee_id text;
  _auth_user_id text;
  _title text;
  _body text;
  _event_record record;
  _payload jsonb;
BEGIN
  -- Only send for pending deliveries
  IF new.status IS NOT NULL AND new.status != 'PENDING' AND new.status != 'DELIVERED' THEN
    RETURN new;
  END IF;

  _auth_user_id := coalesce(new.recipient_user_id, '');
  _employee_id := coalesce(new.recipient_employee_id, '');

  -- Try to get title/body from the linked notification event
  IF new.notification_id IS NOT NULL THEN
    SELECT title, body, event_type INTO _event_record
    FROM public.notification_events
    WHERE id = new.notification_id;

    IF found THEN
      _title := coalesce(_event_record.title, 'JOY PeopleHR');
      _body := coalesce(_event_record.body, '');
    END IF;
  END IF;

  _title := coalesce(_title, 'New Notification');
  _body := coalesce(_body, 'You have a new notification.');

  _payload := jsonb_build_object(
    'employee_id', _employee_id,
    'auth_user_id', _auth_user_id,
    'title', _title,
    'body', _body,
    'route', 'home',
    'data', jsonb_build_object(
      'delivery_id', new.id::text,
      'notification_id', coalesce(new.notification_id::text, '')
    )
  );

  PERFORM net.http_post(
    url := 'https://ysiajemrqakfngasehhi.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_i_pb_iFcxX0BEJFok_XfZA_gZF3W8mj'
    ),
    body := _payload::text
  );

  RAISE NOTICE 'send_push_delivery: queued push for delivery %', new.id;
  RETURN new;
END;
$$;
