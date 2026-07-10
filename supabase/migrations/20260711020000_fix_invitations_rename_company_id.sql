-- ============================================================
-- Migration: fix_invitations_rename_company_id
-- Problem: 20260711010000_invitations_only.sql created the invitations
--          table with column company_id (referencing organizations.id).
--          The earlier rename migration (20260710013000) ran BEFORE the
--          table existed, so the rename was a no-op.
--          The frontend inserts with organization_id, causing silent RLS
--          failures and the "Inviter un membre" button never appearing.
-- Fix:
--   1. Rename company_id → organization_id on the table.
--   2. Rename the index to match.
--   3. Drop and recreate all RLS policies that referenced company_id.
-- ============================================================

-- 1. Rename the column (idempotent guard via DO block)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'invitations'
          AND column_name  = 'company_id'
    ) THEN
        ALTER TABLE public.invitations RENAME COLUMN company_id TO organization_id;
    END IF;
END;
$$;

-- 2. Rename the index (drop old, recreate)
DROP INDEX IF EXISTS public.idx_invitations_company_id;
CREATE INDEX IF NOT EXISTS idx_invitations_organization_id ON public.invitations(organization_id);

-- 3. Recreate RLS policies using organization_id

DROP POLICY IF EXISTS "members_select_invitations" ON public.invitations;
CREATE POLICY "members_select_invitations"
    ON public.invitations FOR SELECT TO authenticated
    USING (public.is_organization_member(organization_id));

DROP POLICY IF EXISTS "owners_insert_invitations" ON public.invitations;
CREATE POLICY "owners_insert_invitations"
    ON public.invitations FOR INSERT TO authenticated
    WITH CHECK (public.is_organization_owner(organization_id));

DROP POLICY IF EXISTS "owners_update_invitations" ON public.invitations;
CREATE POLICY "owners_update_invitations"
    ON public.invitations FOR UPDATE TO authenticated
    USING (
        public.is_organization_owner(organization_id)
        OR (email = (auth.jwt() ->> 'email') AND status = 'pending')
    )
    WITH CHECK (
        public.is_organization_owner(organization_id)
        OR (email = (auth.jwt() ->> 'email'))
    );

DROP POLICY IF EXISTS "owners_delete_invitations" ON public.invitations;
CREATE POLICY "owners_delete_invitations"
    ON public.invitations FOR DELETE TO authenticated
    USING (public.is_organization_owner(organization_id));
