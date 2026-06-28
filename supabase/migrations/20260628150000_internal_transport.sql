-- ============================================================
-- Internal Transport System — MetalVision
-- Migration: 20260628150000_internal_transport.sql
-- Replaces Groupe Robert external transport with internal mode
-- ============================================================

-- 1. Drop old transport_status enum and recreate with internal statuses
ALTER TABLE public.transport_requests
  ALTER COLUMN transport_status TYPE TEXT;

DROP TYPE IF EXISTS public.transport_status CASCADE;

-- 2. Add new columns to transport_requests
ALTER TABLE public.transport_requests
  ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'internal',
  ADD COLUMN IF NOT EXISTS driver_name TEXT,
  ADD COLUMN IF NOT EXISTS truck_number TEXT,
  ADD COLUMN IF NOT EXISTS arrival_eta TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS gps_start JSONB,
  ADD COLUMN IF NOT EXISTS gps_end JSONB,
  ADD COLUMN IF NOT EXISTS proof_photo_url TEXT,
  ADD COLUMN IF NOT EXISTS proof_document_url TEXT,
  ADD COLUMN IF NOT EXISTS transport_mode TEXT DEFAULT 'camion',
  ADD COLUMN IF NOT EXISTS client_transporter_name TEXT;

-- 3. Update existing records to use internal provider
UPDATE public.transport_requests
  SET provider = 'internal',
      transport_status = CASE
        WHEN transport_status IN ('pending', 'assigned') THEN 'scheduled'
        WHEN transport_status IN ('en_route', 'picked_up') THEN 'in_transit'
        WHEN transport_status = 'delivered' THEN 'delivered'
        ELSE 'scheduled'
      END
  WHERE provider IS NULL OR provider != 'client';

-- 4. Create app_settings table for feature flags
CREATE TABLE IF NOT EXISTS public.app_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL UNIQUE,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Insert default settings
INSERT INTO public.app_settings (key, value, description)
VALUES (
  'external_transport_enabled',
  'false'::jsonb,
  'Enable external transport provider integration. Set to true to activate external carrier flow.'
)
ON CONFLICT (key) DO NOTHING;

-- 6. Enable RLS on app_settings
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_read_settings" ON public.app_settings;
CREATE POLICY "admin_read_settings"
  ON public.app_settings
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "admin_update_settings" ON public.app_settings;
CREATE POLICY "admin_update_settings"
  ON public.app_settings
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- 7. Add index on provider
CREATE INDEX IF NOT EXISTS idx_transport_requests_provider
  ON public.transport_requests(provider);

-- 8. Update mock data to use internal transport
UPDATE public.transport_requests
  SET provider = 'internal',
      driver_name = 'Jean Tremblay',
      truck_number = 'QC-4821-A',
      transport_mode = 'camion',
      arrival_eta = now() + interval '2 hours'
  WHERE transport_status = 'scheduled'
  AND driver_name IS NULL;
