-- =============================================================================
-- Migration: Fix RLS recursion on opportunities + S04 business events helpers
-- Timestamp: 20260712010000
--
-- Problem (INC-S03 follow-up):
--   opportunities_coordinator_select contains a direct sub-query on
--   opportunity_capabilities JOIN capabilities, which triggers RLS evaluation
--   on capabilities → which queries opportunity_capabilities → cycle.
--
-- Fix:
--   1. SECURITY DEFINER function is_opportunity_visible_via_active_candidacy()
--      encapsulates the cross-table EXISTS, bypassing RLS on capabilities.
--   2. opportunities_coordinator_select rewritten to call that function.
--
-- Also adds:
--   3. RLS INSERT policy for business_events so the frontend can emit
--      opportunity_created / opportunity_qualified events.
--   4. RLS UPDATE policy for opportunities so coordinator can qualify.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. SECURITY DEFINER helper — breaks the 3-table RLS cycle
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_opportunity_visible_via_active_candidacy(
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
-- 2. Rewrite opportunities_coordinator_select (was in ccf_004 / ccf_010)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "opportunities_coordinator_select" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_select"
    ON public.opportunities
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(coordinator_org_id)
        OR public.is_opportunity_visible_via_active_candidacy(id)
    );

-- ---------------------------------------------------------------------------
-- 3. UPDATE policy — coordinator/admin can qualify (draft → qualified)
--    and update other fields
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "opportunities_coordinator_update" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_update"
    ON public.opportunities
    FOR UPDATE
    TO authenticated
    USING (public.is_organization_member(coordinator_org_id))
    WITH CHECK (public.is_organization_member(coordinator_org_id));

-- ---------------------------------------------------------------------------
-- 4. business_events INSERT — allow authenticated users to emit events
--    for objects they own/coordinate (frontend-side emission)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "business_events_actor_insert" ON public.business_events;
CREATE POLICY "business_events_actor_insert"
    ON public.business_events
    FOR INSERT
    TO authenticated
    WITH CHECK (
        actor_id = (SELECT id FROM public.profiles WHERE user_id = auth.uid() LIMIT 1)
    );
