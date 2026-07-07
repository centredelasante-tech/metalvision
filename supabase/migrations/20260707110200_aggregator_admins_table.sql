-- ============================================================
-- MT-000A — Migration 3 of 4
-- File: 20260707110200_aggregator_admins_table.sql
-- Purpose: Create the aggregator_admins table with full
--          lifecycle support (nomination, revocation, history,
--          primary_admin, co_admin roles).
--
-- GOVERNANCE PRINCIPLE:
-- Group administration is ALWAYS explicitly assigned.
-- It is NEVER deduced automatically from any other role.
-- Being an owner of a member company does NOT make someone
-- an admin of a regroupement.
--
-- This table is designed as a generic, reusable component
-- for all current and future regroupements.
-- ============================================================

-- ── ENUM: aggregator_admin_role ───────────────────────────────
-- Defines the explicit group roles for regroupement governance.
-- These are INDEPENDENT of platform roles (admin, project_admin).
-- ─────────────────────────────────────────────────────────────
DROP TYPE IF EXISTS public.aggregator_admin_role CASCADE;
CREATE TYPE public.aggregator_admin_role AS ENUM (
  'primary_admin',  -- Principal administrator of the regroupement
  'co_admin'        -- Co-administrator with delegated rights
);

COMMENT ON TYPE public.aggregator_admin_role IS
'Explicit group roles for regroupement governance.
Independent of platform roles (admin, project_admin).
primary_admin: principal administrator.
co_admin: co-administrator with delegated rights.';

-- ── TABLE: aggregator_admins ──────────────────────────────────
-- Records the explicit assignment of administrative roles
-- within a regroupement.
--
-- Lifecycle fields:
--   granted_at    — when the role was assigned
--   granted_by    — who assigned the role (audit trail)
--   revoked_at    — when the role was revoked (NULL = active)
--   revoked_by    — who revoked the role (audit trail)
--   notes         — optional justification or context
--
-- A NULL revoked_at means the assignment is currently active.
-- A non-NULL revoked_at means the assignment has been revoked.
-- Historical records are NEVER deleted — only revoked.
--
-- The UNIQUE constraint on (aggregator_id, user_id) where
-- revoked_at IS NULL is enforced via a partial unique index
-- to allow multiple historical records for the same person.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.aggregator_admins (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregator_id  UUID        NOT NULL REFERENCES public.aggregators(id) ON DELETE CASCADE,
  user_id        UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role           public.aggregator_admin_role NOT NULL DEFAULT 'co_admin',

  -- Nomination fields
  granted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  granted_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,

  -- Revocation fields (NULL = currently active)
  revoked_at     TIMESTAMPTZ,
  revoked_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,

  -- Optional context
  notes          TEXT,

  -- Audit
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Constraint: revoked_at must be after granted_at when set
  CONSTRAINT aggregator_admins_revocation_date_check
    CHECK (revoked_at IS NULL OR revoked_at >= granted_at)
);

COMMENT ON TABLE public.aggregator_admins IS
'Explicit assignment of administrative roles within a regroupement.
Group administration is ALWAYS explicitly assigned — never deduced from other roles.
Records are never deleted; revocation is tracked via revoked_at.
This table is the single source of truth for is_aggregator_admin() checks.';

COMMENT ON COLUMN public.aggregator_admins.role IS
'Group role: primary_admin or co_admin. Independent of platform roles.';

COMMENT ON COLUMN public.aggregator_admins.granted_at IS
'Timestamp when the administrative role was explicitly assigned.';

COMMENT ON COLUMN public.aggregator_admins.granted_by IS
'User who assigned the role. Required for audit trail.';

COMMENT ON COLUMN public.aggregator_admins.revoked_at IS
'Timestamp when the role was revoked. NULL means the assignment is currently active.';

COMMENT ON COLUMN public.aggregator_admins.revoked_by IS
'User who revoked the role. Required for audit trail.';

COMMENT ON COLUMN public.aggregator_admins.notes IS
'Optional justification or context for the nomination or revocation.';

-- ── PARTIAL UNIQUE INDEX ──────────────────────────────────────
-- A user can only hold ONE active role per regroupement at a time.
-- Historical (revoked) records are allowed to accumulate.
-- ─────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS idx_aggregator_admins_active_unique
  ON public.aggregator_admins (aggregator_id, user_id)
  WHERE revoked_at IS NULL;

-- ── PERFORMANCE INDEXES ───────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_aggregator_admins_aggregator_id
  ON public.aggregator_admins (aggregator_id);

CREATE INDEX IF NOT EXISTS idx_aggregator_admins_user_id
  ON public.aggregator_admins (user_id);

CREATE INDEX IF NOT EXISTS idx_aggregator_admins_active
  ON public.aggregator_admins (aggregator_id, user_id)
  WHERE revoked_at IS NULL;

-- ── FUNCTION: is_aggregator_admin(UUID) ──────────────────────
-- Checks whether the current user has an ACTIVE administrative
-- role (primary_admin or co_admin) in the given regroupement.
--
-- GOVERNANCE: This function queries aggregator_admins ONLY.
-- It does NOT consider company ownership or platform roles.
-- Platform superadmin access is handled separately via
-- is_platform_superadmin() in RLS policies.
--
-- SECURITY DEFINER: Runs with the privileges of the function
-- owner to avoid RLS recursion on aggregator_admins itself.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_aggregator_admin(p_aggregator_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.aggregator_admins aa
    WHERE aa.aggregator_id = p_aggregator_id
      AND aa.user_id = auth.uid()
      AND aa.revoked_at IS NULL
  )
$$;

COMMENT ON FUNCTION public.is_aggregator_admin(UUID) IS
'Returns true if the current user has an active (non-revoked) administrative role
in the given regroupement (primary_admin or co_admin).
Does NOT consider company ownership or platform roles.
Use alongside is_platform_superadmin() in Regroupements RLS policies.';

-- ── ENABLE RLS ────────────────────────────────────────────────
ALTER TABLE public.aggregator_admins ENABLE ROW LEVEL SECURITY;
