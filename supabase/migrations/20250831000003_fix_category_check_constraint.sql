-- ============================================================
-- Fix: Use valid category values that match the CHECK constraint
-- ============================================================
-- Valid categories: APPROVAL, SECURITY, INTEGRATION, PLATFORM,
--   BILLING, SUPPORT, ATTENDANCE, PAYROLL, SYSTEM
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. LEAVE REQUEST APPROVED / REJECTED
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_employee_on_leave_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _employee_id TEXT;
  _auth_user_id TEXT := '';
  _title TEXT;
  _body TEXT;
  _status TEXT;
  _old_status TEXT;
  _leave_type TEXT;
  _rejection_reason TEXT;
BEGIN
  _status := upper(coalesce(new.status, ''));
  _old_status := upper(coalesce(old.status, ''));

  IF _status = _old_status THEN RETURN new; END IF;
  IF _status != 'APPROVED' AND _status != 'REJECTED' THEN RETURN new; END IF;

  _employee_id := coalesce(new.employee_id, '');
  _leave_type := coalesce(new.leave_type_name, new.leave_type_code, 'Leave');
  _rejection_reason := new.rejection_reason;

  BEGIN
    SELECT id INTO _auth_user_id
    FROM public.profiles
    WHERE employee_id = _employee_id OR id = _employee_id
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    _auth_user_id := '';
  END;

  IF _status = 'APPROVED' THEN
    _title := 'Leave Approved ✅';
    _body := 'Your ' || _leave_type || ' request has been approved.';
    IF new.from_date IS NOT NULL AND new.to_date IS NOT NULL THEN
      _body := _body || ' (' || new.from_date::text || ' to ' || new.to_date::text || ')';
    END IF;
  ELSE
    _title := 'Leave Rejected ❌';
    _body := 'Your ' || _leave_type || ' request was rejected.';
    IF _rejection_reason IS NOT NULL AND _rejection_reason != '' THEN
      _body := _body || ' Reason: ' || _rejection_reason;
    END IF;
  END IF;

  INSERT INTO public.notification_events (
    title, body, category, event_type, severity, resource_id, metadata
  ) VALUES (
    _title, _body, 'APPROVAL', 'LEAVE_' || _status,
    CASE WHEN _status = 'APPROVED' THEN 'SUCCESS' ELSE 'WARNING' END,
    new.id::text,
    jsonb_build_object(
      'employee_id', _employee_id,
      'auth_user_id', _auth_user_id,
      'leave_type', _leave_type,
      'status', _status,
      'from_date', coalesce(new.from_date::text, ''),
      'to_date', coalesce(new.to_date::text, ''),
      'rejection_reason', coalesce(_rejection_reason, ''),
      'target_employee_id', _employee_id,
      'route', 'leaves'
    )
  );

  IF _auth_user_id != '' THEN
    INSERT INTO public.notification_deliveries (
      recipient_user_id, recipient_employee_id, notification_id, channel, status
    )
    SELECT _auth_user_id, _employee_id, ne.id, 'PUSH', 'PENDING'
    FROM public.notification_events ne
    WHERE ne.resource_id = new.id::text AND ne.event_type = 'LEAVE_' || _status
    ORDER BY ne.created_at DESC LIMIT 1;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_leave_status ON public.leave_requests;
CREATE TRIGGER trigger_notify_leave_status
  AFTER UPDATE OF status ON public.leave_requests
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_employee_on_leave_status_change();


-- ─────────────────────────────────────────────────────────────
-- 2. ATTENDANCE REGULARIZATION APPROVED / REJECTED
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_employee_on_regularization_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _employee_id TEXT;
  _auth_user_id TEXT := '';
  _title TEXT;
  _body TEXT;
  _status TEXT;
  _old_status TEXT;
  _attendance_date TEXT;
BEGIN
  _status := upper(coalesce(new.status, ''));
  _old_status := upper(coalesce(old.status, ''));

  IF _status = _old_status THEN RETURN new; END IF;
  IF _status != 'APPROVED' AND _status != 'REJECTED' THEN RETURN new; END IF;

  _employee_id := coalesce(new.employee_id, '');
  _attendance_date := coalesce(new.attendance_date::text, new.date::text, 'recent');

  BEGIN
    SELECT id INTO _auth_user_id
    FROM public.profiles
    WHERE employee_id = _employee_id OR id = _employee_id
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    _auth_user_id := '';
  END;

  IF _status = 'APPROVED' THEN
    _title := 'Regularization Approved ✅';
    _body := 'Your attendance regularization for ' || _attendance_date || ' has been approved.';
  ELSE
    _title := 'Regularization Rejected ❌';
    _body := 'Your attendance regularization for ' || _attendance_date || ' was rejected.';
    IF new.rejection_reason IS NOT NULL AND new.rejection_reason != '' THEN
      _body := _body || ' Reason: ' || new.rejection_reason;
    END IF;
  END IF;

  INSERT INTO public.notification_events (
    title, body, category, event_type, severity, resource_id, metadata
  ) VALUES (
    _title, _body, 'ATTENDANCE', 'REGULARIZATION_' || _status,
    CASE WHEN _status = 'APPROVED' THEN 'SUCCESS' ELSE 'WARNING' END,
    new.id::text,
    jsonb_build_object(
      'employee_id', _employee_id,
      'auth_user_id', _auth_user_id,
      'status', _status,
      'attendance_date', _attendance_date,
      'target_employee_id', _employee_id,
      'route', 'attendance'
    )
  );

  IF _auth_user_id != '' THEN
    INSERT INTO public.notification_deliveries (
      recipient_user_id, recipient_employee_id, notification_id, channel, status
    )
    SELECT _auth_user_id, _employee_id, ne.id, 'PUSH', 'PENDING'
    FROM public.notification_events ne
    WHERE ne.resource_id = new.id::text AND ne.event_type = 'REGULARIZATION_' || _status
    ORDER BY ne.created_at DESC LIMIT 1;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_regularization_status ON public.attendance_regularization_requests;
CREATE TRIGGER trigger_notify_regularization_status
  AFTER UPDATE OF status ON public.attendance_regularization_requests
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_employee_on_regularization_status_change();


-- ─────────────────────────────────────────────────────────────
-- 3. EXPENSE CLAIM APPROVED / REJECTED
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_employee_on_expense_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _employee_id TEXT;
  _auth_user_id TEXT := '';
  _title TEXT;
  _body TEXT;
  _status TEXT;
  _old_status TEXT;
  _amount TEXT;
BEGIN
  _status := upper(coalesce(new.status, ''));
  _old_status := upper(coalesce(old.status, ''));

  IF _status = _old_status THEN RETURN new; END IF;
  IF _status != 'APPROVED' AND _status != 'REJECTED' AND _status != 'PAID' AND _status != 'SETTLED' THEN RETURN new; END IF;

  _employee_id := coalesce(new.employee_id, '');
  _amount := CASE WHEN new.amount IS NOT NULL THEN '₹' || new.amount::text ELSE '' END;

  BEGIN
    SELECT id INTO _auth_user_id
    FROM public.profiles
    WHERE employee_id = _employee_id OR id = _employee_id
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    _auth_user_id := '';
  END;

  IF _status IN ('APPROVED', 'PAID', 'SETTLED') THEN
    _title := 'Expense Claim Approved ✅';
    _body := 'Your expense claim ' || _amount || ' has been approved.';
  ELSE
    _title := 'Expense Claim Rejected ❌';
    _body := 'Your expense claim ' || _amount || ' was rejected.';
    IF new.rejection_reason IS NOT NULL AND new.rejection_reason != '' THEN
      _body := _body || ' Reason: ' || new.rejection_reason;
    END IF;
  END IF;

  INSERT INTO public.notification_events (
    title, body, category, event_type, severity, resource_id, metadata
  ) VALUES (
    _title, _body, 'APPROVAL', 'EXPENSE_' || _status,
    CASE WHEN _status IN ('APPROVED', 'PAID', 'SETTLED') THEN 'SUCCESS' ELSE 'WARNING' END,
    new.id::text,
    jsonb_build_object(
      'employee_id', _employee_id,
      'auth_user_id', _auth_user_id,
      'status', _status,
      'amount', coalesce(new.amount::text, '0'),
      'claim_number', coalesce(new.claim_number, ''),
      'target_employee_id', _employee_id,
      'route', 'expense'
    )
  );

  IF _auth_user_id != '' THEN
    INSERT INTO public.notification_deliveries (
      recipient_user_id, recipient_employee_id, notification_id, channel, status
    )
    SELECT _auth_user_id, _employee_id, ne.id, 'PUSH', 'PENDING'
    FROM public.notification_events ne
    WHERE ne.resource_id = new.id::text AND ne.event_type = 'EXPENSE_' || _status
    ORDER BY ne.created_at DESC LIMIT 1;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_expense_status ON public.expense_claims;
CREATE TRIGGER trigger_notify_expense_status
  AFTER UPDATE OF status ON public.expense_claims
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_employee_on_expense_status_change();


-- ─────────────────────────────────────────────────────────────
-- 4. DOCUMENT REQUIREMENT VERIFIED / REJECTED
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_employee_on_document_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _employee_id TEXT;
  _auth_user_id TEXT := '';
  _title TEXT;
  _body TEXT;
  _status TEXT;
  _old_status TEXT;
  _doc_type TEXT;
BEGIN
  _status := upper(coalesce(new.status, ''));
  _old_status := upper(coalesce(old.status, ''));

  IF _status = _old_status THEN RETURN new; END IF;
  IF _status != 'VERIFIED' AND _status != 'REJECTED' AND _status != 'COMPLETED' THEN RETURN new; END IF;

  _employee_id := coalesce(new.employee_id, '');
  _doc_type := coalesce(new.requested_document_type, new.document_type, new.title, 'Document');

  BEGIN
    SELECT id INTO _auth_user_id
    FROM public.profiles
    WHERE employee_id = _employee_id OR id = _employee_id
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    _auth_user_id := '';
  END;

  IF _status IN ('VERIFIED', 'COMPLETED') THEN
    _title := 'Document Verified ✅';
    _body := 'Your ' || _doc_type || ' has been verified by HR.';
  ELSE
    _title := 'Document Rejected ❌';
    _body := 'Your ' || _doc_type || ' submission was rejected by HR.';
    IF new.rejection_reason IS NOT NULL AND new.rejection_reason != '' THEN
      _body := _body || ' Reason: ' || new.rejection_reason;
    END IF;
  END IF;

  INSERT INTO public.notification_events (
    title, body, category, event_type, severity, resource_id, metadata
  ) VALUES (
    _title, _body, 'SUPPORT', 'DOCUMENT_' || _status,
    CASE WHEN _status IN ('VERIFIED', 'COMPLETED') THEN 'SUCCESS' ELSE 'WARNING' END,
    new.id::text,
    jsonb_build_object(
      'employee_id', _employee_id,
      'auth_user_id', _auth_user_id,
      'document_type', _doc_type,
      'status', _status,
      'target_employee_id', _employee_id,
      'route', 'documents'
    )
  );

  IF _auth_user_id != '' THEN
    INSERT INTO public.notification_deliveries (
      recipient_user_id, recipient_employee_id, notification_id, channel, status
    )
    SELECT _auth_user_id, _employee_id, ne.id, 'PUSH', 'PENDING'
    FROM public.notification_events ne
    WHERE ne.resource_id = new.id::text AND ne.event_type = 'DOCUMENT_' || _status
    ORDER BY ne.created_at DESC LIMIT 1;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_document_status ON public.document_requirements;
CREATE TRIGGER trigger_notify_document_status
  AFTER UPDATE OF status ON public.document_requirements
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_employee_on_document_status_change();


-- ─────────────────────────────────────────────────────────────
-- 5. PAYSLIP RELEASED (INSERT trigger)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_employee_on_payslip_released()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _employee_id TEXT;
  _auth_user_id TEXT := '';
  _month_name TEXT;
  _year TEXT;
BEGIN
  _employee_id := coalesce(new.employee_id, '');
  _month_name := coalesce(new.month_name, new.month::text, 'Current');
  _year := coalesce(new.year::text, extract(year from now())::text);

  BEGIN
    SELECT id INTO _auth_user_id
    FROM public.profiles
    WHERE employee_id = _employee_id OR id = _employee_id
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    _auth_user_id := '';
  END;

  INSERT INTO public.notification_events (
    title, body, category, event_type, severity, resource_id, metadata
  ) VALUES (
    'Payslip Released 💰',
    'Your ' || _month_name || ' ' || _year || ' salary statement is now available.',
    'PAYROLL', 'PAYSLIP_GENERATED', 'SUCCESS', new.id::text,
    jsonb_build_object(
      'employee_id', _employee_id,
      'auth_user_id', _auth_user_id,
      'month_name', _month_name,
      'year', _year,
      'target_employee_id', _employee_id,
      'route', 'payslip'
    )
  );

  IF _auth_user_id != '' THEN
    INSERT INTO public.notification_deliveries (
      recipient_user_id, recipient_employee_id, notification_id, channel, status
    )
    SELECT _auth_user_id, _employee_id, ne.id, 'PUSH', 'PENDING'
    FROM public.notification_events ne
    WHERE ne.resource_id = new.id::text AND ne.event_type = 'PAYSLIP_GENERATED'
    ORDER BY ne.created_at DESC LIMIT 1;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_payslip_released ON public.employee_payslips;
CREATE TRIGGER trigger_notify_payslip_released
  AFTER INSERT ON public.employee_payslips
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_employee_on_payslip_released();


-- ─────────────────────────────────────────────────────────────
-- 6. ANNOUNCEMENT PUBLISHED
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_employees_on_announcement_published()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _old_status TEXT;
  _new_status TEXT;
  _emp RECORD;
BEGIN
  _old_status := upper(coalesce(old.status, ''));
  _new_status := upper(coalesce(new.status, ''));

  IF _old_status = _new_status OR _new_status != 'PUBLISHED' THEN
    RETURN new;
  END IF;

  INSERT INTO public.notification_events (
    title, body, category, event_type, severity, resource_id, metadata
  ) VALUES (
    '📢 ' || coalesce(new.title, 'New Announcement'),
    coalesce(new.content, 'A new announcement has been published.'),
    'SYSTEM', 'ANNOUNCEMENT_PUBLISHED',
    CASE WHEN new.priority = 'URGENT' THEN 'CRITICAL' ELSE 'INFO' END,
    new.id::text,
    jsonb_build_object(
      'announcement_id', new.id::text,
      'title', coalesce(new.title, ''),
      'priority', coalesce(new.priority, 'NORMAL'),
      'category', coalesce(new.category, 'General'),
      'target_employee_id', '',
      'route', 'announcements'
    )
  );

  BEGIN
    FOR _emp IN
      SELECT DISTINCT p.id AS auth_user_id, COALESCE(p.employee_id, '') AS employee_id
      FROM public.profiles p
      WHERE p.fcm_token IS NOT NULL AND p.fcm_token != ''
    LOOP
      INSERT INTO public.notification_deliveries (
        recipient_user_id, recipient_employee_id, notification_id, channel, status
      )
      SELECT _emp.auth_user_id, _emp.employee_id, ne.id, 'PUSH', 'PENDING'
      FROM public.notification_events ne
      WHERE ne.event_type = 'ANNOUNCEMENT_PUBLISHED' AND ne.resource_id = new.id::text
      ORDER BY ne.created_at DESC LIMIT 1;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_announcement_published ON public.company_announcements;
CREATE TRIGGER trigger_notify_announcement_published
  AFTER UPDATE OF status ON public.company_announcements
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_employees_on_announcement_published();


-- ─────────────────────────────────────────────────────────────
-- 7. COMMUNICATION PUBLISHED
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_employees_on_communication_published()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _old_status TEXT;
  _new_status TEXT;
  _emp RECORD;
BEGIN
  _old_status := upper(coalesce(old.status, ''));
  _new_status := upper(coalesce(new.status, ''));

  IF _old_status = _new_status OR _new_status != 'PUBLISHED' THEN
    RETURN new;
  END IF;

  INSERT INTO public.notification_events (
    title, body, category, event_type, severity, resource_id, metadata
  ) VALUES (
    '📢 ' || coalesce(new.title, 'New Communication'),
    coalesce(new.body, 'A new communication has been published.'),
    'SYSTEM', 'COMMUNICATION_PUBLISHED',
    CASE WHEN new.priority = 'URGENT' THEN 'CRITICAL' ELSE 'INFO' END,
    new.id::text,
    jsonb_build_object(
      'communication_id', new.id::text,
      'title', coalesce(new.title, ''),
      'priority', coalesce(new.priority, 'NORMAL'),
      'communication_type', coalesce(new.communication_type, 'General'),
      'target_employee_id', '',
      'route', 'announcements'
    )
  );

  BEGIN
    FOR _emp IN
      SELECT DISTINCT p.id AS auth_user_id, COALESCE(p.employee_id, '') AS employee_id
      FROM public.profiles p
      WHERE p.fcm_token IS NOT NULL AND p.fcm_token != ''
    LOOP
      INSERT INTO public.notification_deliveries (
        recipient_user_id, recipient_employee_id, notification_id, channel, status
      )
      SELECT _emp.auth_user_id, _emp.employee_id, ne.id, 'PUSH', 'PENDING'
      FROM public.notification_events ne
      WHERE ne.event_type = 'COMMUNICATION_PUBLISHED' AND ne.resource_id = new.id::text
      ORDER BY ne.created_at DESC LIMIT 1;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_communication_published ON public.communications;
CREATE TRIGGER trigger_notify_communication_published
  AFTER UPDATE OF status ON public.communications
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_employees_on_communication_published();
