-- ============================================================================
-- Auto-confirm emails for new Supabase Auth users
-- ============================================================================
-- The web app creates auth users but doesn't confirm their email.
-- This trigger auto-confirms so mobile app login works immediately.
-- ============================================================================

-- Function to auto-confirm email on user creation
CREATE OR REPLACE FUNCTION public.auto_confirm_user_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Auto-confirm email so signInWithPassword works immediately
  IF NEW.email_confirmed_at IS NULL AND NEW.email IS NOT NULL THEN
    NEW.email_confirmed_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

-- Attach trigger to auth.users (fires before insert)
DROP TRIGGER IF EXISTS trg_auto_confirm_email ON auth.users;
CREATE TRIGGER trg_auto_confirm_email
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_confirm_user_email();

-- ============================================================================
-- Create missing fn_get_employee_authorized_locations RPC function
-- ============================================================================
-- Used by LocationService to fetch employee's assigned work locations
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_employee_authorized_locations(
  p_tenant_id TEXT,
  p_employee_id TEXT
)
RETURNS TABLE (
  id UUID,
  name TEXT,
  code TEXT,
  location_type TEXT,
  address TEXT,
  latitude NUMERIC,
  longitude NUMERIC,
  allowed_radius_meters NUMERIC,
  accuracy_requirement_meters NUMERIC,
  is_primary BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- 1. Try employee-specific work location assignments
  RETURN QUERY
  SELECT
    wl.id,
    wl.name,
    wl.code,
    wl.location_type,
    wl.address,
    wl.latitude,
    wl.longitude,
    wl.geofence_radius_meters AS allowed_radius_meters,
    wl.accuracy_requirement_meters,
    ewl.is_primary
  FROM public.employee_work_locations ewl
  JOIN public.work_locations wl ON ewl.work_location_id = wl.id
  WHERE ewl.employee_id = p_employee_id
    AND ewl.is_active = true
    AND wl.is_active = true
    AND (p_tenant_id IS NULL OR wl.organization_id = p_tenant_id OR wl.tenant_id = p_tenant_id);

  -- 2. If no employee-specific locations, return all active org locations
  IF NOT FOUND AND p_tenant_id IS NOT NULL AND p_tenant_id != '' THEN
    RETURN QUERY
    SELECT
      wl.id,
      wl.name,
      wl.code,
      wl.location_type,
      wl.address,
      wl.latitude,
      wl.longitude,
      wl.geofence_radius_meters AS allowed_radius_meters,
      wl.accuracy_requirement_meters,
      false AS is_primary
    FROM public.work_locations wl
    WHERE wl.is_active = true
      AND (wl.organization_id = p_tenant_id OR wl.tenant_id = p_tenant_id);
  END IF;
END;
$$;
