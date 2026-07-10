-- ============================================================
-- Étape 1 — Renommage company_id → organization_id sur invitations
-- + Recréation de la table avec la bonne FK (organizations)
-- + Mise à jour de la RPC get_invitation_by_token
-- + Mise à jour des policies RLS
--
-- Contexte : la migration ccf_002 a renommé companies → organizations
-- et a droppé companies CASCADE, emportant invitations avec elle.
-- Cette migration recrée invitations proprement avec organization_id.
-- ============================================================

-- ============================================================
-- 1. RECRÉATION DE LA TABLE invitations
--    (idempotente : DROP IF EXISTS + CREATE)
-- ============================================================

DROP TABLE IF EXISTS public.invitations CASCADE;

CREATE TABLE public.invitations (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    email           TEXT        NOT NULL,
    role            public.org_role NOT NULL DEFAULT 'membre'::public.org_role,
    token           TEXT        NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
    status          public.invitation_status NOT NULL DEFAULT 'pending',
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '7 days'),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at     TIMESTAMPTZ
);

-- Proof : SELECT column_name FROM information_schema.columns
--         WHERE table_name='invitations' ORDER BY ordinal_position;
-- Expected columns (in order):
--   id, organization_id, email, role, token, status, expires_at, created_at, accepted_at

-- ============================================================
-- 2. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_invitations_organization_id ON public.invitations(organization_id);
CREATE INDEX IF NOT EXISTS idx_invitations_token           ON public.invitations(token);
CREATE INDEX IF NOT EXISTS idx_invitations_email           ON public.invitations(email);

-- ============================================================
-- 3. ENABLE RLS
-- ============================================================

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. RLS POLICIES (using organization_id + is_organization_member / is_organization_owner)
-- ============================================================

-- Members of the organization can see all invitations for that org
DROP POLICY IF EXISTS "members_select_invitations" ON public.invitations;
CREATE POLICY "members_select_invitations"
ON public.invitations FOR SELECT TO authenticated
USING (public.is_organization_member(organization_id));

-- The invitee can read their own invitation by email (before they are a member)
DROP POLICY IF EXISTS "invitee_select_own_invitation" ON public.invitations;
CREATE POLICY "invitee_select_own_invitation"
ON public.invitations FOR SELECT TO authenticated
USING (email = (auth.jwt() ->> 'email'));

-- Only org owners/admins can create invitations
DROP POLICY IF EXISTS "owners_insert_invitations" ON public.invitations;
CREATE POLICY "owners_insert_invitations"
ON public.invitations FOR INSERT TO authenticated
WITH CHECK (public.is_organization_owner(organization_id));

-- Owners can update any invitation; invitee can accept their own pending invitation
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

-- Only owners can delete invitations
DROP POLICY IF EXISTS "owners_delete_invitations" ON public.invitations;
CREATE POLICY "owners_delete_invitations"
ON public.invitations FOR DELETE TO authenticated
USING (public.is_organization_owner(organization_id));

-- ============================================================
-- 5. HELPER FUNCTIONS: is_organization_member / is_organization_owner
--    (idempotent — CREATE OR REPLACE)
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_organization_member(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_organization_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_organization_owner(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_organization_id
          AND om.user_id = auth.uid()
          AND om.org_role = 'admin'
          AND om.status = 'active'
    );
$$;

-- ============================================================
-- 6. RPC: get_invitation_by_token (updated for organizations)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_invitation_by_token(p_token TEXT)
RETURNS TABLE(
    invitation_id   UUID,
    organization_id UUID,
    organization_name TEXT,
    email           TEXT,
    role            TEXT,
    status          TEXT,
    expires_at      TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.id                AS invitation_id,
        i.organization_id   AS organization_id,
        o.name              AS organization_name,
        i.email             AS email,
        i.role::TEXT        AS role,
        i.status::TEXT      AS status,
        i.expires_at        AS expires_at
    FROM public.invitations i
    JOIN public.organizations o ON o.id = i.organization_id
    WHERE i.token = p_token
      AND i.status = 'pending'
      AND i.expires_at > now();
END;
$$;

-- Grant execute to anon so unauthenticated users can preview the invitation
GRANT EXECUTE ON FUNCTION public.get_invitation_by_token(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_invitation_by_token(TEXT) TO authenticated;

-- ============================================================
-- VALIDATION QUERY (run manually to confirm):
-- SELECT column_name
-- FROM information_schema.columns
-- WHERE table_name = 'invitations'
-- ORDER BY ordinal_position;
-- Expected: id, organization_id, email, role, token, status, expires_at, created_at, accepted_at
-- ============================================================
