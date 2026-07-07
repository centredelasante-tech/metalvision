-- ============================================================
-- MT-000A — Migration 2 of 4
-- File: 20260707110100_is_platform_superadmin.sql
-- Purpose: Create is_platform_superadmin() — the dedicated
--          superadmin function for the Regroupements domain.
--
-- GOVERNANCE PRINCIPLE:
-- The only role with exceptional access to ALL regroupements
-- is the true platform superadmin (role = 'admin' exclusively).
-- project_admin MUST NEVER be included here.
--
-- This function is the ONLY platform-level access key
-- authorised for use in Regroupements RLS policies.
-- is_platform_admin() must never be used in that domain.
-- ============================================================

-- ── FUNCTION: is_platform_superadmin() ───────────────────────
-- Checks whether the current user has the 'admin' platform
-- role EXCLUSIVELY.
--
-- CRITICAL: project_admin is intentionally excluded.
-- A project_admin must be explicitly added to aggregator_admins
-- if they need to administer a regroupement.
--
-- USAGE: Regroupements domain RLS policies only.
-- All other domains continue to use is_platform_admin() or
-- is_admin_from_auth() as appropriate.
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_platform_superadmin()
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

COMMENT ON FUNCTION public.is_platform_superadmin() IS
'Checks whether the current user has the true platform superadmin role (admin ONLY).
project_admin is intentionally excluded — it never grants implicit access to regroupements.
Use this function exclusively in Regroupements domain RLS policies.
Never use is_platform_admin() in the Regroupements domain.';
