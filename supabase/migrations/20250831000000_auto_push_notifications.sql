-- ============================================================
-- Auto-push notifications via pg_net + Edge Function
-- ============================================================
-- This migration creates a trigger that automatically sends
-- FCM push notifications whenever a new row is inserted into
-- `notification_events`. It calls the `send-push` Edge Function
-- using Supabase's pg_net HTTP extension.
--
-- Prerequisites:
--   1. Enable pg_net extension: create extension if not exists pg_net;
--   2. Deploy the send-push Edge Function
--   3. Set FIREBASE_SERVICE_ACCOUNT secret
-- ============================================================

-- 1. Enable pg_net if not already enabled
create extension if not exists pg_net with schema extensions;

-- 2. Create the trigger function that sends push notifications
create or replace function public.send_push_on_notification_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _employee_id text;
  _auth_user_id text;
  _title text;
  _body text;
  _route text;
  _meta jsonb;
  _edge_url text;
  _payload jsonb;
begin
  -- Extract fields from the new notification_event row
  _title := coalesce(new.title, 'JOY PeopleHR');
  _body := coalesce(new.body, '');
  _route := coalesce(new.event_type, 'home');

  -- Try to get recipient from metadata
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

  -- Build the Edge Function URL
  -- Replace <project-ref> with your actual Supabase project reference
  _edge_url := current_setting('app.settings.supabase_url', true);
  if _edge_url is null or _edge_url = '' then
    _edge_url := 'https://ysiajemrqakfngasehhi.supabase.co';
  end if;
  _edge_url := _edge_url || '/functions/v1/send-push';

  -- Build the payload
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

  -- Call the Edge Function asynchronously (fire-and-forget)
  perform net.http_post(
    url := _edge_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.supabase_anon_key', true)
    ),
    body := _payload::text
  );

  return new;
end;
$$;

-- 3. Create the trigger on notification_events
drop trigger if exists trigger_send_push_on_notification on public.notification_events;
create trigger trigger_send_push_on_notification
  after insert on public.notification_events
  for each row
  execute function public.send_push_on_notification_event();

-- ============================================================
-- Also trigger on notification_deliveries for direct messages
-- ============================================================
create or replace function public.send_push_on_notification_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _employee_id text;
  _auth_user_id text;
  _title text;
  _body text;
  _event_record record;
  _edge_url text;
  _payload jsonb;
begin
  -- Only send for pending deliveries
  if new.status is not null and new.status != 'PENDING' and new.status != 'DELIVERED' then
    return new;
  end if;

  -- Get the recipient info
  _auth_user_id := coalesce(new.recipient_user_id, '');
  _employee_id := coalesce(new.recipient_employee_id, '');

  -- Try to get title/body from the linked notification event
  if new.notification_id is not null then
    select title, body, event_type into _event_record
    from public.notification_events
    where id = new.notification_id;

    if found then
      _title := coalesce(_event_record.title, 'JOY PeopleHR');
      _body := coalesce(_event_record.body, '');
    end if;
  end if;

  -- Fallback defaults
  _title := coalesce(_title, 'New Notification');
  _body := coalesce(_body, 'You have a new notification.');

  -- Build the Edge Function URL
  _edge_url := current_setting('app.settings.supabase_url', true);
  if _edge_url is null or _edge_url = '' then
    _edge_url := 'https://ysiajemrqakfngasehhi.supabase.co';
  end if;
  _edge_url := _edge_url || '/functions/v1/send-push';

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

  perform net.http_post(
    url := _edge_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.supabase_anon_key', true)
    ),
    body := _payload::text
  );

  return new;
end;
$$;

drop trigger if exists trigger_send_push_on_delivery on public.notification_deliveries;
create trigger trigger_send_push_on_delivery
  after insert on public.notification_deliveries
  for each row
  execute function public.send_push_on_notification_delivery();

-- ============================================================
-- Helper: RPC to send push from app code (optional)
-- ============================================================
create or replace function public.send_push_notification(
  p_employee_id text,
  p_title text,
  p_body text,
  p_route text default 'home',
  p_data jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  _edge_url text;
  _payload jsonb;
  _auth_user_id text;
begin
  -- Look up auth_user_id from profiles if we only have employee_id
  if p_employee_id is not null and p_employee_id != '' then
    select id into _auth_user_id
    from public.profiles
    where employee_id = p_employee_id
    limit 1;
  end if;

  _edge_url := current_setting('app.settings.supabase_url', true);
  if _edge_url is null or _edge_url = '' then
    _edge_url := 'https://ysiajemrqakfngasehhi.supabase.co';
  end if;
  _edge_url := _edge_url || '/functions/v1/send-push';

  _payload := jsonb_build_object(
    'employee_id', p_employee_id,
    'auth_user_id', coalesce(_auth_user_id, ''),
    'title', p_title,
    'body', p_body,
    'route', p_route,
    'data', p_data
  );

  perform net.http_post(
    url := _edge_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.supabase_anon_key', true)
    ),
    body := _payload::text
  );

  return jsonb_build_object('success', true, 'message', 'Push notification queued');
end;
$$;
