-- Migration: company_members_invitations (CORRIGÉ)
-- Tables: companies, company_members, invitations
-- RLS: members see own company/colleagues; only owners manage members/invitations
-- Corrections appliquées :
--   1. Un utilisateur peut s'auto-insérer comme 'owner' dans company_members
--      SEULEMENT si aucun membre n'existe encore pour cette company_id
--      (permet de créer le premier owner sans cercle vicieux).
--   2. La personne invitée peut lire SON invitation par email,
--      même si elle n'est pas encore membre de l'entreprise.

-- ============================================================
-- 1. ENUM TYPES
-- ============================================================

DROP TYPE IF EXISTS public.company_member_role CASCADE;
CREATE TYPE public.company_member_role AS ENUM ('owner', 'terrain');

DROP TYPE IF EXISTS public.invitation_status CASCADE;
CREATE TYPE public.invitation_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');

-- ============================================================
-- 2. TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.companies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_members (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL,  -- references auth.users via RLS (no FK to keep public-schema clean)
    role        public.company_member_role NOT NULL DEFAULT 'terrain',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.invitations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    role        public.company_member_role NOT NULL DEFAULT 'terrain',
    token       TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
    status      public.invitation_status NOT NULL DEFAULT 'pending',
    expires_at  TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '7 days'),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 3. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_company_members_company_id ON public.company_members(company_id);
CREATE INDEX IF NOT EXISTS idx_company_members_user_id    ON public.company_members(user_id);
CREATE INDEX IF NOT EXISTS idx_invitations_company_id     ON public.invitations(company_id);
CREATE INDEX IF NOT EXISTS idx_invitations_token          ON public.invitations(token);
CREATE INDEX IF NOT EXISTS idx_invitations_email          ON public.invitations(email);

-- ============================================================
-- 4. HELPER FUNCTIONS (must be created BEFORE RLS policies)
-- ============================================================

-- Returns true if the current user is a member of the given company
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

-- Returns true if the current user is an owner of the given company
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

-- NOUVEAU : retourne true si AUCUN membre n'existe encore pour cette company_id
-- (utilisé pour autoriser la création du tout premier owner)
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

-- ============================================================
-- 5. ENABLE RLS
-- ============================================================

ALTER TABLE public.companies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations     ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 6. RLS POLICIES — companies
-- ============================================================

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

-- ============================================================
-- 7. RLS POLICIES — company_members
-- ============================================================

DROP POLICY IF EXISTS "members_select_colleagues" ON public.company_members;
CREATE POLICY "members_select_colleagues"
ON public.company_members FOR SELECT TO authenticated
USING (public.is_company_member(company_id));

-- CORRIGÉ : un owner peut ajouter des membres, OU un utilisateur peut
-- s'auto-insérer comme 'owner' si c'est le tout premier membre de la company
-- (et seulement comme owner, et seulement pour lui-même — user_id = auth.uid()).
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

-- ============================================================
-- 8. RLS POLICIES — invitations
-- ============================================================

DROP POLICY IF EXISTS "members_select_invitations" ON public.invitations;
CREATE POLICY "members_select_invitations"
ON public.invitations FOR SELECT TO authenticated
USING (public.is_company_member(company_id));

-- NOUVEAU : la personne invitée peut lire SON invitation par email,
-- même si elle n'est pas encore membre (nécessaire pour la page d'acceptation).
DROP POLICY IF EXISTS "invitee_select_own_invitation" ON public.invitations;
CREATE POLICY "invitee_select_own_invitation"
ON public.invitations FOR SELECT TO authenticated
USING (email = (auth.jwt() ->> 'email'));

DROP POLICY IF EXISTS "owners_insert_invitations" ON public.invitations;
CREATE POLICY "owners_insert_invitations"
ON public.invitations FOR INSERT TO authenticated
WITH CHECK (public.is_company_owner(company_id));

-- CORRIGÉ : un owner peut tout modifier (ex: révoquer), ET la personne
-- invitée peut modifier SA propre invitation pendante pour l'accepter
-- (ex: passer status à 'accepted'). À restreindre côté application pour
-- n'autoriser que le changement de statut, pas company_id/role/email.
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
