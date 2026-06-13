-- ============================================================
-- Transport Module — Groupe Robert Integration
-- Migration: 20260613100000_transport_module.sql
-- ============================================================

-- 1. ENUM: transport status
DROP TYPE IF EXISTS public.transport_status CASCADE;
CREATE TYPE public.transport_status AS ENUM (
  'pending',
  'assigned',
  'en_route',
  'picked_up',
  'delivered',
  'cancelled'
);

-- 2. TABLE: transport_requests
CREATE TABLE IF NOT EXISTS public.transport_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lot_id              TEXT NOT NULL,
  company_id          UUID,
  container_id        TEXT,
  pickup_address      TEXT NOT NULL,
  dropoff_address     TEXT NOT NULL,
  scheduled_time      TIMESTAMPTZ,
  transporter         TEXT NOT NULL DEFAULT 'Groupe Robert',
  external_reference  TEXT,
  transport_status    public.transport_status NOT NULL DEFAULT 'pending',
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_transport_requests_lot_id
  ON public.transport_requests(lot_id);

CREATE INDEX IF NOT EXISTS idx_transport_requests_status
  ON public.transport_requests(transport_status);

CREATE INDEX IF NOT EXISTS idx_transport_requests_external_ref
  ON public.transport_requests(external_reference);

CREATE INDEX IF NOT EXISTS idx_transport_requests_created_at
  ON public.transport_requests(created_at DESC);

-- 4. updated_at trigger function
CREATE OR REPLACE FUNCTION public.set_transport_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_transport_requests_updated_at ON public.transport_requests;
CREATE TRIGGER trg_transport_requests_updated_at
  BEFORE UPDATE ON public.transport_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.set_transport_updated_at();

-- 5. Enable RLS
ALTER TABLE public.transport_requests ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies — open access for authenticated users (admin + client)
DROP POLICY IF EXISTS "authenticated_read_transport_requests" ON public.transport_requests;
CREATE POLICY "authenticated_read_transport_requests"
  ON public.transport_requests
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "authenticated_insert_transport_requests" ON public.transport_requests;
CREATE POLICY "authenticated_insert_transport_requests"
  ON public.transport_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_transport_requests" ON public.transport_requests;
CREATE POLICY "authenticated_update_transport_requests"
  ON public.transport_requests
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- 7. Mock data
DO $$
DECLARE
  tr1 UUID := gen_random_uuid();
  tr2 UUID := gen_random_uuid();
  tr3 UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.transport_requests (
    id, lot_id, container_id, pickup_address, dropoff_address,
    scheduled_time, transporter, external_reference, transport_status, notes
  ) VALUES
    (tr1, 'lot-0848', 'CT-001',
     '1250 rue Notre-Dame Ouest, Montréal, QC H3C 1K4',
     '3500 boul. Industriel, Laval, QC H7L 4R3',
     now() + interval '2 hours', 'Groupe Robert', 'GR-2026-00841',
     'assigned', 'Collecte cuivre — lot urgent'),
    (tr2, 'lot-0846', 'CT-003',
     '875 av. Sainte-Croix, Saint-Laurent, QC H4L 3Y2',
     '3500 boul. Industriel, Laval, QC H7L 4R3',
     now() + interval '5 hours', 'Groupe Robert', 'GR-2026-00842',
     'en_route', 'Acier profilé — chantier rénovation'),
    (tr3, 'lot-0844', 'CT-001',
     '1250 rue Notre-Dame Ouest, Montréal, QC H3C 1K4',
     '3500 boul. Industriel, Laval, QC H7L 4R3',
     now() - interval '3 hours', 'Groupe Robert', 'GR-2026-00839',
     'delivered', 'Laiton — livraison complétée')
  ON CONFLICT (id) DO NOTHING;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Mock data insertion failed: %', SQLERRM;
END $$;
