-- =============================================================================
-- Migration: Fix RLS infinite recursion between opportunities and
--            opportunity_capabilities
-- Timestamp: 20260713030000
--
-- Problem (found live on METALVISION-DEMO while testing the 6 demo accounts,
-- same session as 20260713020000, reproduced directly with
-- `SET LOCAL ROLE authenticated` + JWT claim for producteur@demo.metaltrace.ca):
--
--   ERROR: 42P17: infinite recursion detected in policy for relation
--   "opportunities"
--
-- Same class of bug as 20260711060000 (capabilities / opportunity_capabilities)
-- and 20260713020000 (project_participants / ccf_projects), but on a
-- different pair of tables that migration 20260711060000 did not touch:
--
--   opportunities_coordinator_select        → raw EXISTS into
--                                              opportunity_capabilities JOIN capabilities
--   opp_cap_member_select                   → raw EXISTS into opportunities
--   opp_cap_update_coordinator_or_candidate → raw EXISTS into opportunities
--   opp_cap_coordinator_admin_insert        → raw EXISTS into opportunities
--
-- Note: migration 20260712010000 ("S04 NO-OP") claims this exact fix — a
-- function named is_opportunity_visible_via_active_candidacy() — was
-- "already applied in migration 20260711070000 (INC-S03-07)". Verified live:
-- neither that function nor that migration file exists. The claim was never
-- true; this migration performs the fix for real.
--
-- Fix: same technique as 20260711060000 / 20260713020000 — encapsulate every
-- cross-table EXISTS check inside a SECURITY DEFINER function
-- (SET search_path = public). Both tables have relforcerowsecurity = false,
-- so a SECURITY DEFINER function owned by the table owner bypasses RLS on
-- its target table entirely, breaking the cycle.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP 1 — SECURITY DEFINER helper functions
-- ---------------------------------------------------------------------------

-- Used by opp_cap_member_select (USING branch 1):
--     "Is the current user a member of the coordinator organisation of the
--      opportunity this opportunity_capabilities row belongs to?"
CREATE OR REPLACE FUNCTION public.is_opportunity_coordinator_org_member(
    p_opportunity_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.opportunities o
        WHERE o.id = p_opportunity_id
          AND public.is_organization_member(o.coordinator_org_id)
    );
$$;

-- Used by opp_cap_update_coordinator_or_candidate and
-- opp_cap_coordinator_admin_insert:
--     "Does the current user own (admin of) the coordinator organisation of
--      the opportunity this opportunity_capabilities row belongs to?"
CREATE OR REPLACE FUNCTION public.is_opportunity_coordinator_org_owner(
    p_opportunity_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.opportunities o
        WHERE o.id = p_opportunity_id
          AND public.is_organization_owner(o.coordinator_org_id)
    );
$$;

-- Used by opportunities_coordinator_select (USING branch 2):
--     "Is this opportunity linked to an active candidacy (opportunity_capabilities
--      row with status='active') whose capability belongs to an organisation
--      the current user is a member of?"
CREATE OR REPLACE FUNCTION public.is_opportunity_via_active_candidacy_member(
    p_opportunity_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.opportunity_capabilities oc
        JOIN public.capabilities c ON c.id = oc.capability_id
        WHERE oc.opportunity_id = p_opportunity_id
          AND oc.status = 'active'
          AND public.is_organization_member(c.organization_id)
    );
$$;

-- ---------------------------------------------------------------------------
-- STEP 2 — Rewrite the 4 affected policies
-- ---------------------------------------------------------------------------

-- ── TABLE: opportunities ────────────────────────────────────────────────────

DROP POLICY IF EXISTS "opportunities_coordinator_select" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_select"
    ON public.opportunities
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(coordinator_org_id)
        OR public.is_opportunity_via_active_candidacy_member(id)
    );

-- ── TABLE: opportunity_capabilities ─────────────────────────────────────────

DROP POLICY IF EXISTS "opp_cap_member_select" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_member_select"
    ON public.opportunity_capabilities
    FOR SELECT
    TO authenticated
    USING (
        public.is_opportunity_coordinator_org_member(opportunity_id)
        OR public.is_opportunity_capability_via_capability_member(capability_id)
    );

DROP POLICY IF EXISTS "opp_cap_update_coordinator_or_candidate" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_update_coordinator_or_candidate"
    ON public.opportunity_capabilities
    FOR UPDATE
    TO authenticated
    USING (
        public.is_opportunity_coordinator_org_owner(opportunity_id)
        OR public.is_opportunity_capability_via_capability_owner(capability_id)
    )
    WITH CHECK (
        public.is_opportunity_coordinator_org_owner(opportunity_id)
        OR public.is_opportunity_capability_via_capability_owner(capability_id)
    );

DROP POLICY IF EXISTS "opp_cap_coordinator_admin_insert" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_coordinator_admin_insert"
    ON public.opportunity_capabilities
    FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_opportunity_coordinator_org_owner(opportunity_id)
    );
-- =============================================================================
