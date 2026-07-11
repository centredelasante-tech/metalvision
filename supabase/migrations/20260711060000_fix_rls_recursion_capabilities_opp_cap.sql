-- =============================================================================
-- Migration: Fix RLS infinite recursion between capabilities and
--            opportunity_capabilities
-- Timestamp: 20260711060000
--
-- Problem: 4 policies create a mutual recursion cycle:
--   capabilities_owner_select          → queries opportunity_capabilities
--   capabilities_project_context_select → queries opportunity_capabilities
--   opp_cap_member_select              → queries capabilities
--   opp_cap_update_coordinator_or_candidate → queries capabilities
--
-- Fix: Encapsulate every cross-table EXISTS check inside a SECURITY DEFINER
--      function (SET search_path = public).  The function bypasses RLS on the
--      target table, breaking the cycle.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP 1 — SECURITY DEFINER helper functions
-- ---------------------------------------------------------------------------

-- 1a. Used by capabilities_owner_select (USING branch 2):
--     "Is this capability linked to an opportunity whose coordinator org the
--      current user is a member of?"
CREATE OR REPLACE FUNCTION public.is_capability_candidate_org_member(
    p_capability_id uuid
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
        JOIN public.opportunities o ON o.id = oc.opportunity_id
        WHERE oc.capability_id = p_capability_id
          AND oc.status = 'active'
          AND public.is_organization_member(o.coordinator_org_id)
    );
$$;

-- 1b. Used by capabilities_project_context_select (USING branch 2):
--     "Is this capability linked to an opportunity whose coordinator org is
--      one of the current user's organisations?"
CREATE OR REPLACE FUNCTION public.is_capability_linked_to_user_coord_org(
    p_capability_id uuid
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
        JOIN public.opportunities o ON o.id = oc.opportunity_id
        WHERE oc.capability_id = p_capability_id
          AND o.coordinator_org_id = ANY(SELECT public.user_org_ids())
    );
$$;

-- 1c. Used by opp_cap_member_select (USING branch 2):
--     "Is the capability's owning organisation one the current user is a
--      member of?"
CREATE OR REPLACE FUNCTION public.is_opportunity_capability_via_capability_member(
    p_capability_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.capabilities c
        WHERE c.id = p_capability_id
          AND public.is_organization_member(c.organization_id)
    );
$$;

-- 1d. Used by opp_cap_update_coordinator_or_candidate (USING + WITH CHECK,
--     candidate branch):
--     "Is the capability's owning organisation one the current user owns?"
CREATE OR REPLACE FUNCTION public.is_opportunity_capability_via_capability_owner(
    p_capability_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.capabilities c
        WHERE c.id = p_capability_id
          AND public.is_organization_owner(c.organization_id)
    );
$$;

-- ---------------------------------------------------------------------------
-- STEP 2 — Rewrite the 4 affected policies
-- ---------------------------------------------------------------------------

-- ── TABLE: capabilities ────────────────────────────────────────────────────

-- Policy 1: capabilities_owner_select
DROP POLICY IF EXISTS "capabilities_owner_select" ON public.capabilities;
CREATE POLICY "capabilities_owner_select"
    ON public.capabilities
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(organization_id)
        OR public.is_capability_candidate_org_member(id)
    );

-- Policy 2: capabilities_project_context_select
DROP POLICY IF EXISTS "capabilities_project_context_select" ON public.capabilities;
CREATE POLICY "capabilities_project_context_select"
    ON public.capabilities
    FOR SELECT
    TO authenticated
    USING (
        organization_id = ANY(SELECT public.user_org_ids())
        OR public.is_capability_linked_to_user_coord_org(id)
    );

-- ── TABLE: opportunity_capabilities ───────────────────────────────────────

-- Policy 3: opp_cap_member_select
DROP POLICY IF EXISTS "opp_cap_member_select" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_member_select"
    ON public.opportunity_capabilities
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_member(o.coordinator_org_id)
        )
        OR public.is_opportunity_capability_via_capability_member(capability_id)
    );

-- Policy 4: opp_cap_update_coordinator_or_candidate
DROP POLICY IF EXISTS "opp_cap_update_coordinator_or_candidate" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_update_coordinator_or_candidate"
    ON public.opportunity_capabilities
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
        OR public.is_opportunity_capability_via_capability_owner(capability_id)
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
        OR public.is_opportunity_capability_via_capability_owner(capability_id)
    );
