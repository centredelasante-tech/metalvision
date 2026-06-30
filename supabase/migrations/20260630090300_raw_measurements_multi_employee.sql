-- Migration: raw_measurements multi-employee model
-- Timestamp: 20260630090300
--
-- Changes:
--   1. Add nullable company_id UUID → companies(id) ON DELETE CASCADE
--   2. Create index on company_id
--   3. Replace client_id-based RLS policies with is_company_member(company_id) policies
--      for SELECT / INSERT / UPDATE (authenticated role)
--   4. Keep service_role_raw_measurements policy unchanged
--   5. Do NOT drop client_id (will be removed in a later migration)

-- ============================================================
-- 1. Add company_id column (nullable — old rows have no company_id)
-- ============================================================
ALTER TABLE public.raw_measurements
    ADD COLUMN IF NOT EXISTS company_id UUID
        REFERENCES public.companies(id) ON DELETE CASCADE;

-- ============================================================
-- 2. Index on company_id
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_raw_measurements_company_id
    ON public.raw_measurements(company_id);

-- ============================================================
-- 3. Replace old client_id-based RLS policies
--    (drop any policy that was based on client_id = auth.uid())
-- ============================================================

-- Drop the old catch-all policy that used client_id = auth.uid()
DROP POLICY IF EXISTS "clients_manage_own_raw_measurements" ON public.raw_measurements;

-- ── SELECT: any member of the company can read its lots ──────
DROP POLICY IF EXISTS "company_members_select_raw_measurements" ON public.raw_measurements;
CREATE POLICY "company_members_select_raw_measurements"
ON public.raw_measurements
FOR SELECT
TO authenticated
USING (
    company_id IS NOT NULL
    AND public.is_company_member(company_id)
);

-- ── INSERT: any member of the company can create lots ────────
DROP POLICY IF EXISTS "company_members_insert_raw_measurements" ON public.raw_measurements;
CREATE POLICY "company_members_insert_raw_measurements"
ON public.raw_measurements
FOR INSERT
TO authenticated
WITH CHECK (
    company_id IS NOT NULL
    AND public.is_company_member(company_id)
);

-- ── UPDATE: any member of the company can update its lots ────
DROP POLICY IF EXISTS "company_members_update_raw_measurements" ON public.raw_measurements;
CREATE POLICY "company_members_update_raw_measurements"
ON public.raw_measurements
FOR UPDATE
TO authenticated
USING (
    company_id IS NOT NULL
    AND public.is_company_member(company_id)
)
WITH CHECK (
    company_id IS NOT NULL
    AND public.is_company_member(company_id)
);

-- ============================================================
-- 4. service_role policy — kept as-is (recreated idempotently)
-- ============================================================
DROP POLICY IF EXISTS "service_role_raw_measurements" ON public.raw_measurements;
CREATE POLICY "service_role_raw_measurements"
ON public.raw_measurements
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
