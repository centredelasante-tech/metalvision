-- ============================================================
-- Migration: invitations_only
-- Creates ONLY the invitation_status enum and invitations table.
-- Does NOT touch: companies, company_members, company_member_role,
--                 is_company_member(), is_company_owner(), company_has_no_members().
-- RLS policies use is_organization_member() / is_organization_owner()
-- (already present) and reference public.org_role (already present).
-- ============================================================

-- 1. ENUM TYPE
DROP TYPE IF EXISTS public.invitation_status CASCADE;
CREATE TYPE public.invitation_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');

-- 2. TABLE
CREATE TABLE public.invitations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    role        public.org_role NOT NULL DEFAULT 'membre',
    token       TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
    status      public.invitation_status NOT NULL DEFAULT 'pending',
    expires_at  TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '7 days'),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at TIMESTAMPTZ
);

-- 3. INDEXES
CREATE INDEX IF NOT EXISTS idx_invitations_company_id ON public.invitations(company_id);
CREATE INDEX IF NOT EXISTS idx_invitations_token      ON public.invitations(token);
CREATE INDEX IF NOT EXISTS idx_invitations_email      ON public.invitations(email);

-- 4. ENABLE RLS
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

-- 5. RLS POLICIES
DROP POLICY IF EXISTS "members_select_invitations" ON public.invitations;
CREATE POLICY "members_select_invitations" ON public.invitations FOR SELECT TO authenticated
    USING (public.is_organization_member(company_id));

DROP POLICY IF EXISTS "invitee_select_own_invitation" ON public.invitations;
CREATE POLICY "invitee_select_own_invitation" ON public.invitations FOR SELECT TO authenticated
    USING (email = (auth.jwt() ->> 'email'));

DROP POLICY IF EXISTS "owners_insert_invitations" ON public.invitations;
CREATE POLICY "owners_insert_invitations" ON public.invitations FOR INSERT TO authenticated
    WITH CHECK (public.is_organization_owner(company_id));

DROP POLICY IF EXISTS "owners_update_invitations" ON public.invitations;
CREATE POLICY "owners_update_invitations" ON public.invitations FOR UPDATE TO authenticated
    USING (public.is_organization_owner(company_id) OR (email = (auth.jwt() ->> 'email') AND status = 'pending'))
    WITH CHECK (public.is_organization_owner(company_id) OR (email = (auth.jwt() ->> 'email')));

DROP POLICY IF EXISTS "owners_delete_invitations" ON public.invitations;
CREATE POLICY "owners_delete_invitations" ON public.invitations FOR DELETE TO authenticated
    USING (public.is_organization_owner(company_id));
