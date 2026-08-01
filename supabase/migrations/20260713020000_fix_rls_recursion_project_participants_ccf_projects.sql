-- =============================================================================
-- Migration: Fix RLS infinite recursion between project_participants and
--            ccf_projects
-- Timestamp: 20260713020000
--
-- Problem (found live on METALVISION-DEMO while testing the 6 demo accounts,
-- reproduced directly with `SET LOCAL ROLE authenticated` + JWT claim for
-- producteur@demo.metaltrace.ca):
--
--   ERROR: 42P17: infinite recursion detected in policy for relation
--   "project_participants"
--
-- 2 policies create a mutual recursion cycle, same class of bug as
-- 20260711060000 (capabilities / opportunity_capabilities):
--
--   project_participants_select   → raw EXISTS subquery into ccf_projects
--   ccf_projects_participant_select → raw EXISTS subquery into project_participants
--
-- Each subquery is evaluated subject to the target table's own RLS, which
-- immediately re-enters the other table's policy → infinite loop. This only
-- surfaced for non-superadmin roles: ccf_projects_superadmin_select short-
-- circuits the OR chain for the superadmin account before the recursive
-- branch is evaluated, masking the bug for that one account.
--
-- Fix: same technique as 20260711060000 — encapsulate every cross-table
-- EXISTS check inside a SECURITY DEFINER function (SET search_path = public).
-- Both tables have relforcerowsecurity = false, so a SECURITY DEFINER
-- function owned by the table owner bypasses RLS on its target table
-- entirely, breaking the cycle. This is the same pattern already used by
-- is_organization_member(), is_organization_owner() and user_project_ids().
--
-- Also: ccf_projects_participant_select duplicated coverage already provided
-- safely by the existing ccf_projects_via_user_project_ids policy (which
-- already uses the SECURITY DEFINER function user_project_ids()). The
-- participant branch of ccf_projects_participant_select is therefore dropped
-- outright rather than rewritten; only the coordinator-org-member branch is
-- kept (renamed for clarity).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP 1 — SECURITY DEFINER helper function
-- ---------------------------------------------------------------------------

-- Used by project_participants_select (USING branch 1):
--     "Is the current user a member of the coordinator organisation of the
--      project this participant row belongs to?"
CREATE OR REPLACE FUNCTION public.is_project_coordinator_org_member(
    p_project_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.ccf_projects p
        WHERE p.id = p_project_id
          AND public.is_organization_member(p.coordinator_org_id)
    );
$$;

-- ---------------------------------------------------------------------------
-- STEP 2 — Rewrite the 2 affected policies
-- ---------------------------------------------------------------------------

-- ── TABLE: project_participants ─────────────────────────────────────────────

-- Policy 1: project_participants_select
-- Was: EXISTS (SELECT 1 FROM ccf_projects p WHERE p.id = project_id AND
--              is_organization_member(p.coordinator_org_id))
--      OR is_organization_member(organization_id)
-- Now: raw subquery replaced by the SECURITY DEFINER helper above.
DROP POLICY IF EXISTS "project_participants_select" ON public.project_participants;
CREATE POLICY "project_participants_select"
    ON public.project_participants
    FOR SELECT
    TO authenticated
    USING (
        public.is_project_coordinator_org_member(project_id)
        OR public.is_organization_member(organization_id)
    );

-- ── TABLE: ccf_projects ─────────────────────────────────────────────────────

-- Policy 2: ccf_projects_participant_select
-- Was: is_organization_member(coordinator_org_id)
--      OR EXISTS (SELECT 1 FROM project_participants pp WHERE
--                 pp.project_id = ccf_projects.id AND
--                 is_organization_member(pp.organization_id) AND
--                 pp.status = 'active')
-- Now: the participant branch (raw subquery into project_participants) is
-- dropped — it is redundant with the existing ccf_projects_via_user_project_ids
-- policy, which already grants the same access safely via the SECURITY
-- DEFINER function user_project_ids(). Only the coordinator-org-member branch
-- is kept, renamed to reflect what it actually checks.
DROP POLICY IF EXISTS "ccf_projects_participant_select" ON public.ccf_projects;
CREATE POLICY "ccf_projects_coordinator_org_select"
    ON public.ccf_projects
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(coordinator_org_id)
    );

-- ---------------------------------------------------------------------------
-- Note: project_participants_update / project_participants_coordinator_insert
-- still contain raw EXISTS subqueries into ccf_projects. These are safe after
-- this fix: ccf_projects's remaining SELECT policies
-- (ccf_projects_coordinator_org_select, ccf_projects_superadmin_select,
-- ccf_projects_via_user_project_ids) no longer reference project_participants
-- raw, so there is no cycle left to close on the write path.
-- =============================================================================
