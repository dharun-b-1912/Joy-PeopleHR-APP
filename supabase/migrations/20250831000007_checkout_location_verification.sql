-- ============================================================================
-- Checkout Location Verification Layer
-- ============================================================================
-- Adds columns to store WHERE the checkout happened:
--   assigned_location  → Employee is inside their assigned work location geofence
--   main_office        → Employee is at the company's main/head office
--   other_authorized   → Employee is at another registered work location
--   unauthorized       → Employee is at an unknown location (reason required)
--   gps_unavailable    → GPS could not be obtained (reason required)
--
-- Check-in logic is NOT changed. This layer only applies to checkout.
-- ============================================================================

-- 1. Add checkout location verification columns to attendance_events
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_events' AND column_name = 'checkout_location_status'
  ) THEN
    ALTER TABLE attendance_events ADD COLUMN checkout_location_status TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_events' AND column_name = 'checkout_location_name'
  ) THEN
    ALTER TABLE attendance_events ADD COLUMN checkout_location_name TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_events' AND column_name = 'checkout_location_reason'
  ) THEN
    ALTER TABLE attendance_events ADD COLUMN checkout_location_reason TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_events' AND column_name = 'checkout_accuracy_meters'
  ) THEN
    ALTER TABLE attendance_events ADD COLUMN checkout_accuracy_meters NUMERIC;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_events' AND column_name = 'checkout_latitude'
  ) THEN
    ALTER TABLE attendance_events ADD COLUMN checkout_latitude NUMERIC;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_events' AND column_name = 'checkout_longitude'
  ) THEN
    ALTER TABLE attendance_events ADD COLUMN checkout_longitude NUMERIC;
  END IF;
END $$;

-- 2. Add checkout location verification columns to attendance_daily (for admin dashboard)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_daily' AND column_name = 'checkout_location_status'
  ) THEN
    ALTER TABLE attendance_daily ADD COLUMN checkout_location_status TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_daily' AND column_name = 'checkout_location_name'
  ) THEN
    ALTER TABLE attendance_daily ADD COLUMN checkout_location_name TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_daily' AND column_name = 'checkout_location_reason'
  ) THEN
    ALTER TABLE attendance_daily ADD COLUMN checkout_location_reason TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_daily' AND column_name = 'checkout_latitude'
  ) THEN
    ALTER TABLE attendance_daily ADD COLUMN checkout_latitude NUMERIC;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attendance_daily' AND column_name = 'checkout_longitude'
  ) THEN
    ALTER TABLE attendance_daily ADD COLUMN checkout_longitude NUMERIC;
  END IF;
END $$;

-- 3. Create an enum-like check constraint for checkout_location_status
DO $$
BEGIN
  -- Drop existing constraint if any
  ALTER TABLE attendance_events DROP CONSTRAINT IF EXISTS chk_checkout_location_status;
  ALTER TABLE attendance_events ADD CONSTRAINT chk_checkout_location_status
    CHECK (checkout_location_status IS NULL OR checkout_location_status IN (
      'assigned_location', 'main_office', 'other_authorized', 'unauthorized', 'gps_unavailable'
    ));

  ALTER TABLE attendance_daily DROP CONSTRAINT IF EXISTS chk_daily_checkout_location_status;
  ALTER TABLE attendance_daily ADD CONSTRAINT chk_daily_checkout_location_status
    CHECK (checkout_location_status IS NULL OR checkout_location_status IN (
      'assigned_location', 'main_office', 'other_authorized', 'unauthorized', 'gps_unavailable'
    ));
END $$;

-- 4. Create a view for admin dashboard to easily see checkout verification details
CREATE OR REPLACE VIEW v_attendance_checkout_verification AS
SELECT
  ad.id AS daily_id,
  ad.employee_id,
  ad.employee_code,
  ad.employee_name,
  ad.date,
  ad.status,
  ad.first_check_in,
  ad.last_check_out,
  ad.net_working_minutes,
  ad.checkout_location_status,
  ad.checkout_location_name,
  ad.checkout_location_reason,
  ad.checkout_latitude,
  ad.checkout_longitude,
  ad.department,
  ad.designation,
  -- Human-readable checkout location label
  CASE ad.checkout_location_status
    WHEN 'assigned_location' THEN 'Assigned Location (' || COALESCE(ad.checkout_location_name, 'Known') || ')'
    WHEN 'main_office' THEN 'Main Office (' || COALESCE(ad.checkout_location_name, 'Head Office') || ')'
    WHEN 'other_authorized' THEN 'Other Location (' || COALESCE(ad.checkout_location_name, 'Registered') || ')'
    WHEN 'unauthorized' THEN 'Unauthorized Location - Reason: ' || COALESCE(ad.checkout_location_reason, 'No reason provided')
    WHEN 'gps_unavailable' THEN 'GPS Unavailable - Reason: ' || COALESCE(ad.checkout_location_reason, 'No reason provided')
    ELSE 'Not Verified'
  END AS checkout_location_label,
  -- Color coding for admin dashboard
  CASE ad.checkout_location_status
    WHEN 'assigned_location' THEN 'green'
    WHEN 'main_office' THEN 'blue'
    WHEN 'other_authorized' THEN 'teal'
    WHEN 'unauthorized' THEN 'orange'
    WHEN 'gps_unavailable' THEN 'red'
    ELSE 'gray'
  END AS checkout_location_color
FROM attendance_daily ad
WHERE ad.last_check_out IS NOT NULL;
