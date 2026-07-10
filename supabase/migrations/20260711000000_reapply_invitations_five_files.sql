-- ============================================================
-- REAPPLY: Five invitation migration files in chronological order
-- Reason: DROP SCHEMA public CASCADE removed these tables/objects.
-- Files reapplied (in order):
--   1. 20260630060000_company_members_invitations.sql
--   2. 20260630061000_company_members_rls_bugfixes.sql
--   3. 20260630070000_get_invitation_by_token_rpc.sql
--   4. 20260630070100_invitations_accepted_at.sql
--   5. 20260630080000_fix_owners_insert_members_invitation.sql
-- ============================================================

-- ============================================================
-- FILE 1: 20260630060000_company_members_invitations.sql
-- Tables: companies, company_members, invitations
-- ============================================================

-- 1. ENUM TYPES
DROP TYPE IF EXISTS public.company_member_role CASCADE;
CREATE TYPE public.company_member_role AS ENUM ('owner', 'terrain');

DROP TYPE IF EXISTS public.invitation_status CASCADE;
CREATE TYPE public.invitation_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');

-- 2. TABLES
DROP TABLE IF EXISTS public.invitations   CASCADE;
DROP TABLE IF EXISTS public.company_members CASCADE;
DROP TABLE IF EXISTS public.companies     CASCADE;

CREATE TABLE public.companies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.company_members (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL,
    role        public.company_member_role NOT NULL DEFAULT 'terrain',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, user_id)
);

CREATE TABLE public.invitations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    role        public.company_member_role NOT NULL DEFAULT 'terrain',
    token       TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
    status      public.invitation_status NOT NULL DEFAULT 'pending',
    expires_at  TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '7 days'),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. INDEXES
CREATE INDEX IF NOT EXISTS idx_company_members_company_id ON public.company_members(company_id);
CREATE INDEX IF NOT EXISTS idx_company_members_user_id    ON public.company_members(user_id);
CREATE INDEX IF NOT EXISTS idx_invitations_company_id     ON public.invitations(company_id);
CREATE INDEX IF NOT EXISTS idx_invitations_token          ON public.invitations(token);
CREATE INDEX IF NOT EXISTS idx_invitations_email          ON public.invitations(email);

-- 4. HELPER FUNCTIONS (must be created BEFORE RLS policies)

CREATE OR REPLACE FUNCTION public.is_company_member(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.company_members cm
        WHERE cm.company_id = p_company_id
          AND cm.user_id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public.is_company_owner(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.company_members cm
        WHERE cm.company_id = p_company_id
          AND cm.user_id = auth.uid()
          AND cm.role = 'owner'
    );
$$;

CREATE OR REPLACE FUNCTION public.company_has_no_members(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM public.company_members cm
        WHERE cm.company_id = p_company_id
    );
$$;

-- 5. ENABLE RLS
ALTER TABLE public.companies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations     ENABLE ROW LEVEL SECURITY;

-- 6. RLS POLICIES — companies
DROP POLICY IF EXISTS "members_select_own_company" ON public.companies;
CREATE POLICY "members_select_own_company"
ON public.companies FOR SELECT TO authenticated
USING (public.is_company_member(id));

DROP POLICY IF EXISTS "owners_update_company" ON public.companies;
CREATE POLICY "owners_update_company"
ON public.companies FOR UPDATE TO authenticated
USING (public.is_company_owner(id))
WITH CHECK (public.is_company_owner(id));

DROP POLICY IF EXISTS "owners_delete_company" ON public.companies;
CREATE POLICY "owners_delete_company"
ON public.companies FOR DELETE TO authenticated
USING (public.is_company_owner(id));

DROP POLICY IF EXISTS "authenticated_insert_company" ON public.companies;
CREATE POLICY "authenticated_insert_company"
ON public.companies FOR INSERT TO authenticated
WITH CHECK (true);

-- 7. RLS POLICIES — company_members
DROP POLICY IF EXISTS "members_select_colleagues" ON public.company_members;
CREATE POLICY "members_select_colleagues"
ON public.company_members FOR SELECT TO authenticated
USING (public.is_company_member(company_id));

DROP POLICY IF EXISTS "owners_insert_members" ON public.company_members;
CREATE POLICY "owners_insert_members"
ON public.company_members FOR INSERT TO authenticated
WITH CHECK (
  public.is_company_owner(company_id)
  OR (
    public.company_has_no_members(company_id)
    AND user_id = auth.uid()
    AND role = 'owner'
  )
);

DROP POLICY IF EXISTS "owners_update_members" ON public.company_members;
CREATE POLICY "owners_update_members"
ON public.company_members FOR UPDATE TO authenticated
USING (public.is_company_owner(company_id))
WITH CHECK (public.is_company_owner(company_id));

DROP POLICY IF EXISTS "owners_delete_members" ON public.company_members;
CREATE POLICY "owners_delete_members"
ON public.company_members FOR DELETE TO authenticated
USING (public.is_company_owner(company_id));

-- 8. RLS POLICIES — invitations
DROP POLICY IF EXISTS "members_select_invitations" ON public.invitations;
CREATE POLICY "members_select_invitations"
ON public.invitations FOR SELECT TO authenticated
USING (public.is_company_member(company_id));

DROP POLICY IF EXISTS "invitee_select_own_invitation" ON public.invitations;
CREATE POLICY "invitee_select_own_invitation"
ON public.invitations FOR SELECT TO authenticated
USING (email = (auth.jwt() ->> 'email'));

DROP POLICY IF EXISTS "owners_insert_invitations" ON public.invitations;
CREATE POLICY "owners_insert_invitations"
ON public.invitations FOR INSERT TO authenticated
WITH CHECK (public.is_company_owner(company_id));

DROP POLICY IF EXISTS "owners_update_invitations" ON public.invitations;
CREATE POLICY "owners_update_invitations"
ON public.invitations FOR UPDATE TO authenticated
USING (
  public.is_company_owner(company_id)
  OR (email = (auth.jwt() ->> 'email') AND status = 'pending')
)
WITH CHECK (
  public.is_company_owner(company_id)
  OR (email = (auth.jwt() ->> 'email'))
);

DROP POLICY IF EXISTS "owners_delete_invitations" ON public.invitations;
CREATE POLICY "owners_delete_invitations"
ON public.invitations FOR DELETE TO authenticated
USING (public.is_company_owner(company_id));

-- ============================================================
-- FILE 2: 20260630061000_company_members_rls_bugfixes.sql
-- ============================================================

DROP POLICY IF EXISTS "bootstrap_first_owner" ON public.company_members;
CREATE POLICY "bootstrap_first_owner"
ON public.company_members
FOR INSERT
TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND role = 'owner'
    AND NOT EXISTS (
        SELECT 1
        FROM public.company_members existing
        WHERE existing.company_id = company_members.company_id
    )
);

DROP POLICY IF EXISTS "invitee_select_own_invitation" ON public.invitations;
CREATE POLICY "invitee_select_own_invitation"
ON public.invitations
FOR SELECT
TO authenticated
USING (
    email = (auth.jwt() ->> 'email')
);

-- ============================================================
-- FILE 3: 20260630070000_get_invitation_by_token_rpc.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_invitation_by_token(p_token TEXT)
RETURNS TABLE(
    invitation_id   UUID,
    company_id      UUID,
    company_name    TEXT,
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
        i.id            AS invitation_id,
        i.company_id    AS company_id,
        c.name          AS company_name,
        i.email         AS email,
        i.role::TEXT    AS role,
        i.status::TEXT  AS status,
        i.expires_at    AS expires_at
    FROM public.invitations i
    JOIN public.companies c ON c.id = i.company_id
    WHERE i.token = p_token
      AND i.status = 'pending'
      AND i.expires_at > now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_invitation_by_token(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_invitation_by_token(TEXT) TO authenticated;

-- ============================================================
-- FILE 4: 20260630070100_invitations_accepted_at.sql
-- ============================================================

ALTER TABLE public.invitations
ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

-- ============================================================
-- FILE 5: 20260630080000_fix_owners_insert_members_invitation.sql
-- ============================================================

DROP POLICY IF EXISTS "owners_insert_members" ON public.company_members;

CREATE POLICY "owners_insert_members"
ON public.company_members FOR INSERT TO authenticated
WITH CHECK (
  -- Condition 1: an existing owner of this company is inserting
  public.is_company_owner(company_id)

  OR

  -- Condition 2: first-member bootstrap — no members yet, user self-inserts as owner
  (
    public.company_has_no_members(company_id)
    AND user_id = auth.uid()
    AND role = 'owner'
  )

  OR

  -- Condition 3: invited user self-inserts — a valid pending invitation exists
  (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.invitations inv
      WHERE inv.email       = (auth.jwt() ->> 'email')
        AND inv.company_id  = company_id
        AND inv.role        = role
        AND inv.status      = 'pending'
        AND inv.expires_at  > now()
    )
  )
);
