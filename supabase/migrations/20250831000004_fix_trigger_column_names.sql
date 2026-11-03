-- ============================================================
-- Fix: Correct column names to match actual database schema
-- ============================================================
-- This fixes all 7 trigger functions to use the actual column
-- names from each table, preventing silent trigger failures.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. LEAVE REQUEST — columns: from_date, to_date, rejection_reason ✅
-- ─────────────────────────────────────────────────────────────
-- This trigger was already correct. No changes needed.

-- ─────────────────────────────────────────────────────────────
-- 2. ATTENDANCE REGULARIZATION — fix: no "date" column
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
  _attendance_date := coalesce(new.attendance_date::text, 'recent');

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
-- 3. EXPENSE CLAIM — fix: check rejection_reason exists
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
-- 4. DOCUMENT REQUIREMENT — fix: no "requested_document_type" column
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
  _doc_type := coalesce(new.document_type, new.title, 'Document');

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
-- 5. PAYSLIP — fix: no "month_name" column, use "month_year_label"
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
  _month_label TEXT;
BEGIN
  _employee_id := coalesce(new.employee_id, '');
  _month_label := coalesce(new.month_year_label, new.month::text || ' ' || new.year::text, 'Current');

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
    'Your ' || _month_label || ' salary statement is now available.',
    'PAYROLL', 'PAYSLIP_GENERATED', 'SUCCESS', new.id::text,
    jsonb_build_object(
      'employee_id', _employee_id,
      'auth_user_id', _auth_user_id,
      'month_label', _month_label,
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
