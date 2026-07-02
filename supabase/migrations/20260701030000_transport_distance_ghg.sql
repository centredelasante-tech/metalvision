-- ============================================================
-- Transport Distance & GHG Emissions
-- Migration: 20260701030000_transport_distance_ghg.sql
-- ============================================================

-- 1. Add distance/GHG columns to transport_requests
ALTER TABLE public.transport_requests
  ADD COLUMN IF NOT EXISTS distance_km          NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS ghg_transport_kgco2e NUMERIC(12,4),
  ADD COLUMN IF NOT EXISTS emission_factor_used NUMERIC(10,6),
  ADD COLUMN IF NOT EXISTS weight_tonnes        NUMERIC(10,4);

-- 2. Add transport_request_id FK to raw_measurements
ALTER TABLE public.raw_measurements
  ADD COLUMN IF NOT EXISTS transport_request_id UUID
    REFERENCES public.transport_requests(id) ON DELETE SET NULL;

-- 3. Index on raw_measurements(transport_request_id)
CREATE INDEX IF NOT EXISTS idx_raw_measurements_transport_request_id
  ON public.raw_measurements(transport_request_id);
