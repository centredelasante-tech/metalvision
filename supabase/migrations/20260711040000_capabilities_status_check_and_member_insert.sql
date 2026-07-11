-- ─────────────────────────────────────────────────────────────────────────────
-- Migration : capabilities — CHECK constraint + RLS member insert
-- Ticket    : E06-T02 / MVP-DA-015 / MVP-DA-011
-- Validated : 2026-07-11
--   • is_organization_member(p_org_id) exists — SECURITY DEFINER, active only
--   • Existing data: only 'declared' (1) and 'qualified' (2) — both in allowed list
--   • No guard UPDATE needed before adding the CHECK constraint
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. CHECK constraint on capabilities.status
--    Allowed values: draft, declared, qualified, suspended, archived
--    (TEXT + CHECK per MVP-DA-015 — no ENUM conversion)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.capabilities
    DROP CONSTRAINT IF EXISTS capabilities_status_check;

ALTER TABLE public.capabilities
    ADD CONSTRAINT capabilities_status_check
    CHECK (status IN ('draft', 'declared', 'qualified', 'suspended', 'archived'));

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. RLS — capabilities_member_insert
--    Replaces capabilities_owner_admin_insert.
--    Any active org member may INSERT, but only with status = 'draft'.
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "capabilities_owner_admin_insert" ON public.capabilities;
DROP POLICY IF EXISTS "capabilities_member_insert"      ON public.capabilities;

CREATE POLICY "capabilities_member_insert"
    ON public.capabilities
    FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_organization_member(organization_id)
        AND status = 'draft'
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. capabilities_owner_admin_update — intentionally left untouched
--    Only owner/admin may advance the status (is_organization_owner()).
-- ─────────────────────────────────────────────────────────────────────────────
