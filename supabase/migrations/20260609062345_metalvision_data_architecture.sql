-- METALTRACE Data Architecture
-- Tables: raw_measurements, global_stats, object_profiles
-- Strict data isolation: raw_measurements filtered by client_id
-- global_stats and object_profiles are anonymous (no client_id)

-- ─────────────────────────────────────────────
-- 1. TABLES
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.raw_measurements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL,
    -- Gemini Vision analysis outputs
    metal_type_predicted TEXT,
    confidence NUMERIC(4,3),
    width_cm NUMERIC(10,2),
    height_cm NUMERIC(10,2),
    depth_cm NUMERIC(10,2),
    volume_estimated_m3 NUMERIC(12,6),
    compaction_visual NUMERIC(4,3),
    purity_visual NUMERIC(4,3),
    object_type TEXT,
    raw_analysis_json JSONB,
    -- Official measurement fields (filled by ConfirmOfficialMeasurement)
    official_weight_kg NUMERIC(12,3),
    official_metal_type TEXT,
    density_real NUMERIC(12,4),
    price_paid NUMERIC(12,2),
    -- Metadata
    reference_size_cm NUMERIC(10,2),
    metal_price_per_kg NUMERIC(10,4),
    density_override NUMERIC(10,4),
    image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Global stats: anonymized, no client_id
CREATE TABLE IF NOT EXISTS public.global_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metal_type TEXT NOT NULL UNIQUE,
    density_mean NUMERIC(12,4),
    compaction_mean NUMERIC(6,4),
    purity_mean NUMERIC(6,4),
    volume_error_mean NUMERIC(12,6),
    nb_measurements INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Object profiles: anonymized, no client_id
CREATE TABLE IF NOT EXISTS public.object_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    object_type TEXT NOT NULL UNIQUE,
    avg_width_cm NUMERIC(10,2),
    avg_height_cm NUMERIC(10,2),
    avg_depth_cm NUMERIC(10,2),
    avg_weight_kg NUMERIC(12,3),
    density_mean NUMERIC(12,4),
    nb_measurements INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ─────────────────────────────────────────────
-- 2. INDEXES
-- ─────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_raw_measurements_client_id ON public.raw_measurements(client_id);
CREATE INDEX IF NOT EXISTS idx_raw_measurements_metal_type ON public.raw_measurements(metal_type_predicted);
CREATE INDEX IF NOT EXISTS idx_raw_measurements_object_type ON public.raw_measurements(object_type);
CREATE INDEX IF NOT EXISTS idx_raw_measurements_created_at ON public.raw_measurements(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_global_stats_metal_type ON public.global_stats(metal_type);
CREATE INDEX IF NOT EXISTS idx_object_profiles_object_type ON public.object_profiles(object_type);

-- ─────────────────────────────────────────────
-- 3. UPDATED_AT TRIGGER FUNCTION
-- ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_raw_measurements_updated_at ON public.raw_measurements;
CREATE TRIGGER set_raw_measurements_updated_at
    BEFORE UPDATE ON public.raw_measurements
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_global_stats_updated_at ON public.global_stats;
CREATE TRIGGER set_global_stats_updated_at
    BEFORE UPDATE ON public.global_stats
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_object_profiles_updated_at ON public.object_profiles;
CREATE TRIGGER set_object_profiles_updated_at
    BEFORE UPDATE ON public.object_profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─────────────────────────────────────────────
-- 4. ENABLE RLS
-- ─────────────────────────────────────────────

ALTER TABLE public.raw_measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.global_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.object_profiles ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────
-- 5. RLS POLICIES
-- ─────────────────────────────────────────────

-- raw_measurements: each client sees only their own rows
DROP POLICY IF EXISTS "clients_manage_own_raw_measurements" ON public.raw_measurements;
CREATE POLICY "clients_manage_own_raw_measurements"
ON public.raw_measurements
FOR ALL
TO authenticated
USING (client_id = auth.uid())
WITH CHECK (client_id = auth.uid());

-- Service role bypass for raw_measurements (needed for UpdateGlobalStats which reads all rows)
DROP POLICY IF EXISTS "service_role_raw_measurements" ON public.raw_measurements;
CREATE POLICY "service_role_raw_measurements"
ON public.raw_measurements
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- global_stats: public read, service_role write
DROP POLICY IF EXISTS "public_read_global_stats" ON public.global_stats;
CREATE POLICY "public_read_global_stats"
ON public.global_stats
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "service_role_global_stats" ON public.global_stats;
CREATE POLICY "service_role_global_stats"
ON public.global_stats
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- object_profiles: public read, service_role write
DROP POLICY IF EXISTS "public_read_object_profiles" ON public.object_profiles;
CREATE POLICY "public_read_object_profiles"
ON public.object_profiles
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "service_role_object_profiles" ON public.object_profiles;
CREATE POLICY "service_role_object_profiles"
ON public.object_profiles
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- anon read for global_stats and object_profiles (needed by API routes)
DROP POLICY IF EXISTS "anon_read_global_stats" ON public.global_stats;
CREATE POLICY "anon_read_global_stats"
ON public.global_stats
FOR SELECT
TO anon
USING (true);

DROP POLICY IF EXISTS "anon_read_object_profiles" ON public.object_profiles;
CREATE POLICY "anon_read_object_profiles"
ON public.object_profiles
FOR SELECT
TO anon
USING (true);
