-- MetalVision: clients + audit_learning_log tables
-- Adds: clients (with RLS), audit_learning_log (with RLS)
-- Also adds exact user-specified RLS policies on raw_measurements, global_stats, object_profiles

-- ─────────────────────────────────────────────
-- 1. TABLE: clients
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ─────────────────────────────────────────────
-- 2. TABLE: audit_learning_log
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.audit_learning_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT,
    metal_type TEXT,
    object_type TEXT,
    measurement_id UUID,
    delta_density NUMERIC(12,4),
    delta_compaction NUMERIC(6,4),
    delta_purity NUMERIC(6,4),
    nb_measurements_before INT,
    nb_measurements_after INT,
    triggered_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ─────────────────────────────────────────────
-- 3. INDEXES
-- ─────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_clients_created_at ON public.clients(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_learning_log_metal_type ON public.audit_learning_log(metal_type);
CREATE INDEX IF NOT EXISTS idx_audit_learning_log_created_at ON public.audit_learning_log(created_at DESC);

-- ─────────────────────────────────────────────
-- 4. ENABLE RLS
-- ─────────────────────────────────────────────

ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_learning_log ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────
-- 5. RLS POLICIES: clients
-- ─────────────────────────────────────────────

DROP POLICY IF EXISTS "clients_manage_own_clients" ON public.clients;
CREATE POLICY "clients_manage_own_clients"
ON public.clients
FOR ALL
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "service_role_clients" ON public.clients;
CREATE POLICY "service_role_clients"
ON public.clients
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- ─────────────────────────────────────────────
-- 6. RLS POLICIES: audit_learning_log
-- ─────────────────────────────────────────────

-- Public read: authenticated users can read audit logs
DROP POLICY IF EXISTS "public read audit_learning_log" ON public.audit_learning_log;
CREATE POLICY "public read audit_learning_log"
ON public.audit_learning_log
FOR SELECT
TO authenticated
USING (true);

-- System write: only service_role can insert/update audit logs
DROP POLICY IF EXISTS "system update audit_learning_log" ON public.audit_learning_log;
CREATE POLICY "system update audit_learning_log"
ON public.audit_learning_log
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- ─────────────────────────────────────────────
-- 7. EXACT USER-SPECIFIED POLICIES: raw_measurements
-- (Supplement existing policies with named policies from spec)
-- ─────────────────────────────────────────────

DROP POLICY IF EXISTS "client can read own measurements" ON public.raw_measurements;
CREATE POLICY "client can read own measurements"
ON public.raw_measurements
FOR SELECT
TO authenticated
USING (client_id = auth.uid());

DROP POLICY IF EXISTS "client can insert own measurements" ON public.raw_measurements;
CREATE POLICY "client can insert own measurements"
ON public.raw_measurements
FOR INSERT
TO authenticated
WITH CHECK (client_id = auth.uid());

DROP POLICY IF EXISTS "client can update own measurements" ON public.raw_measurements;
CREATE POLICY "client can update own measurements"
ON public.raw_measurements
FOR UPDATE
TO authenticated
USING (client_id = auth.uid())
WITH CHECK (client_id = auth.uid());

-- ─────────────────────────────────────────────
-- 8. EXACT USER-SPECIFIED POLICIES: global_stats
-- ─────────────────────────────────────────────

DROP POLICY IF EXISTS "public read" ON public.global_stats;
CREATE POLICY "public read"
ON public.global_stats
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "system update" ON public.global_stats;
CREATE POLICY "system update"
ON public.global_stats
FOR UPDATE
USING (auth.role() = 'service_role');

-- ─────────────────────────────────────────────
-- 9. EXACT USER-SPECIFIED POLICIES: object_profiles
-- ─────────────────────────────────────────────

DROP POLICY IF EXISTS "public read" ON public.object_profiles;
CREATE POLICY "public read"
ON public.object_profiles
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "system update" ON public.object_profiles;
CREATE POLICY "system update"
ON public.object_profiles
FOR UPDATE
USING (auth.role() = 'service_role');
