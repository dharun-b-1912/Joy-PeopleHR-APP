-- ============================================================
-- Create employee_device_tokens table for FCM token storage
-- ============================================================
-- The send-push Edge Function looks up FCM tokens from this
-- table. Without it, no push notifications can be delivered.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.employee_device_tokens (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employee_id TEXT NOT NULL,
  auth_user_id TEXT DEFAULT '',
  fcm_token TEXT NOT NULL,
  platform TEXT DEFAULT 'android',
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Prevent duplicate FCM tokens
CREATE UNIQUE INDEX IF NOT EXISTS idx_employee_device_tokens_fcm_token
  ON public.employee_device_tokens (fcm_token);

-- Allow lookup by employee_id
CREATE INDEX IF NOT EXISTS idx_employee_device_tokens_employee_id
  ON public.employee_device_tokens (employee_id);

-- Allow lookup by auth_user_id
CREATE INDEX IF NOT EXISTS idx_employee_device_tokens_auth_user_id
  ON public.employee_device_tokens (auth_user_id);

-- Enable RLS
ALTER TABLE public.employee_device_tokens ENABLE ROW LEVEL SECURITY;

-- Allow service role to read/write (Edge Function uses service role)
CREATE POLICY "Service role can manage device tokens"
  ON public.employee_device_tokens
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- Also create a minimal profiles table if it doesn't exist
-- (used by some queries for auth_user_id lookup)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY,
  employee_id TEXT DEFAULT '',
  fcm_token TEXT DEFAULT '',
  device_platform TEXT DEFAULT '',
  last_active_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can manage profiles"
  ON public.profiles
  FOR ALL
  USING (true)
  WITH CHECK (true);
