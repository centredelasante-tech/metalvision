-- ============================================================
-- MT-000A — Migration 1 of 4
-- File: 20260707110000_document_is_platform_admin.sql
-- Purpose: Document the is_platform_admin() function for
--          Git/Supabase synchronisation.
--
-- IMPORTANT: This migration does NOT modify any existing
-- behaviour. It only creates a formal record of the function
-- so that the Git repository and the Supabase database are
-- in sync.
--
-- Context: is_platform_admin() was referenced in the project
-- architecture but was never committed to the migrations
-- repository. This migration corrects that gap.
--
-- Scope: Platform Roles only.
-- This function MUST NOT be used as a governance key for
-- the Regroupements domain. See migration 3 for the correct
-- superadmin function dedicated to that domain.
-- ============================================================

-- ── ROLE ARCHITECTURE DOCUMENTATION ─────────────────────────
--
-- PLATFORM ROLES (stored in auth.users metadata)
-- ┌─────────────────┬──────────────────────────────────────────────────────┐
-- │ Role            │ Description                                          │
-- ├─────────────────┼──────────────────────────────────────────────────────┤
-- │ admin           │ True platform superadmin. Full access to everything. │
-- │ project_admin   │ Project-level admin. NO implicit access to groups.   │
-- └─────────────────┴──────────────────────────────────────────────────────┘
--
-- GROUP ROLES (stored in aggregator_admins table — explicit assignment)
-- ┌─────────────────┬──────────────────────────────────────────────────────┐
-- │ Role            │ Description                                          │
-- ├─────────────────┼──────────────────────────────────────────────────────┤
-- │ primary_admin   │ Primary administrator of a regroupement.             │
-- │ co_admin        │ Co-administrator of a regroupement.                  │
-- │ member          │ Standard member of a regroupement.                   │
-- │ observer        │ Read-only observer of a regroupement.                │
-- └─────────────────┴──────────────────────────────────────────────────────┘
--
-- GOVERNANCE PRINCIPLE:
-- Platform roles and group roles are INDEPENDENT.
-- A project_admin NEVER receives implicit rights on a regroupement.
-- Group administration is ALWAYS explicitly assigned.
-- The only role with exceptional access to ALL regroupements
-- is the true platform superadmin (role = 'admin').
-- ============================================================

-- ── FUNCTION: is_platform_admin() ────────────────────────────
-- Checks whether the current user has either 'admin' OR
-- 'project_admin' platform role.
--
-- USAGE: Other platform domains (MRV, transport, etc.)
-- This function is intentionally kept broad to avoid
-- regressions in existing domains that depend on it.
--
-- WARNING: Do NOT use this function as a governance key for
-- the Regroupements domain. Use is_platform_superadmin()
-- instead (see migration 20260707110100).
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_platform_admin()
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
      OR au.raw_user_meta_data->>'role' = 'project_admin'
      OR au.raw_app_meta_data->>'role' = 'admin'
      OR au.raw_app_meta_data->>'role' = 'project_admin'
    )
  )
$$;

COMMENT ON FUNCTION public.is_platform_admin() IS
'Checks whether the current user has admin OR project_admin platform role.
Used by existing platform domains (MRV, transport, etc.).
DO NOT use for Regroupements domain governance — use is_platform_superadmin() instead.
Documented in migration 20260707110000 for Git/Supabase synchronisation.';
