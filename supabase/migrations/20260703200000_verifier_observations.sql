-- Migration: verifier_observations table
-- Timestamp: 20260703200000

-- ============================================================
-- 1. TABLE: verifier_observations
-- ============================================================
CREATE TABLE IF NOT EXISTS public.verifier_observations (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_log_id  UUID        NOT NULL REFERENCES public.project_activity_logs(id) ON DELETE CASCADE,
    verifier_id      UUID        NOT NULL,
    observation_text TEXT        NOT NULL,
    status           TEXT        NOT NULL,
    created_at       TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT verifier_observations_status_check
        CHECK (status IN ('conforme', 'non_conforme', 'a_clarifier'))
);

-- ============================================================
-- 2. INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_verifier_observations_activity_log_id
    ON public.verifier_observations (activity_log_id);

CREATE INDEX IF NOT EXISTS idx_verifier_observations_verifier_id
    ON public.verifier_observations (verifier_id);

-- ============================================================
-- 3. ENABLE RLS
-- ============================================================
ALTER TABLE public.verifier_observations ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. HELPER FUNCTION: is_admin_from_auth
-- (safe: queries auth.users metadata, no circular dependency)
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_admin_from_auth()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
SELECT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id = auth.uid()
    AND (
        au.raw_user_meta_data->>'role' = 'admin'
        OR au.raw_app_meta_data->>'role' = 'admin'
    )
)
$$;

-- ============================================================
-- 5. RLS POLICIES — verifier_observations
-- ============================================================

-- SELECT: verifier reads own observations OR admin reads all
DROP POLICY IF EXISTS "verifier_observations_select" ON public.verifier_observations;
CREATE POLICY "verifier_observations_select"
    ON public.verifier_observations
    FOR SELECT
    TO authenticated
    USING (
        verifier_id = auth.uid()
        OR public.is_admin_from_auth()
    );

-- INSERT: only the connected verifier (verifier_id must equal auth.uid())
DROP POLICY IF EXISTS "verifier_observations_insert" ON public.verifier_observations;
CREATE POLICY "verifier_observations_insert"
    ON public.verifier_observations
    FOR INSERT
    TO authenticated
    WITH CHECK (verifier_id = auth.uid());

-- UPDATE: only the verifier who created the observation
DROP POLICY IF EXISTS "verifier_observations_update" ON public.verifier_observations;
CREATE POLICY "verifier_observations_update"
    ON public.verifier_observations
    FOR UPDATE
    TO authenticated
    USING (verifier_id = auth.uid())
    WITH CHECK (verifier_id = auth.uid());

-- DELETE: only the verifier who created the observation
DROP POLICY IF EXISTS "verifier_observations_delete" ON public.verifier_observations;
CREATE POLICY "verifier_observations_delete"
    ON public.verifier_observations
    FOR DELETE
    TO authenticated
    USING (verifier_id = auth.uid());
