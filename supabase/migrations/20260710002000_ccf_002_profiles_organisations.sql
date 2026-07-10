-- ============================================================
-- CCF-002 — Profils, Organisations, Membres d'organisation
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   RT-03 : companies = organizations dans le domaine collaboratif.
--            La table "companies" existante est RENOMMÉE en "organizations"
--            et "company_members" en "organization_members".
--            Ordre non négociable : 1a → 1a-bis → 1a-ter → 1b → 1c → 1d.
--
-- ORDRE D'EXÉCUTION DANS CETTE MIGRATION :
--   1a.      Renommer tables et type ENUM
--   1a-bis.  Renommer la colonne "role" en "org_role" dans organization_members
--   1a-ter.  Renommer la colonne "company_id" en "organization_id" dans organization_members
--   1b.      Ajouter nouvelles colonnes (AVANT de toucher aux valeurs d'enum)
--   1c.      Recopier la notion "terrain" dans operational_profile
--            (AVANT de renommer les valeurs d'enum)
--   1d.      Renommer les valeurs d'enum
--   2.       Créer la table profiles
--   3.       Adapter les fonctions helper existantes
--   4.       Créer les alias minces pour le domaine CCF
--   5.       Indexes
--   6.       RLS sur les nouvelles tables
--
-- IMPORTANT : Les fonctions is_company_member(), is_company_owner(),
--   company_has_no_members() sont CONSERVÉES sous leurs noms originaux
--   pour ne pas casser les policies existantes qui les appellent.
--   Des alias minces is_organization_member() et is_organization_owner()
--   sont ajoutés pour le nouveau code CCF.
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 1a — Renommer tables et type ENUM
-- ════════════════════════════════════════════════════════════

ALTER TABLE IF EXISTS public.companies RENAME TO organizations;
ALTER TABLE IF EXISTS public.company_members RENAME TO organization_members;
ALTER TYPE public.company_member_role RENAME TO org_role;

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 1a-bis — Renommer la colonne "role" en "org_role"
-- CRITIQUE : doit être exécuté APRÈS le renommage du type (1a)
--            et AVANT l'ajout de colonnes (1b) et le UPDATE (1c).
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.organization_members RENAME COLUMN role TO org_role;

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 1a-ter — Renommer la colonne "company_id" en "organization_id"
-- CRITIQUE : doit être exécuté APRÈS le renommage de la table (1a)
--            et AVANT toute référence à om.organization_id dans les fonctions.
--            Sans ce renommage, la colonne s'appelle encore "company_id"
--            et toutes les requêtes WHERE om.organization_id = ... échouent
--            avec ERROR 42703: column om.organization_id does not exist.
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.organization_members RENAME COLUMN company_id TO organization_id;

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 1b — Ajouter nouvelles colonnes
-- (AVANT de toucher aux valeurs d'enum)
-- ════════════════════════════════════════════════════════════

-- Nouvelles colonnes sur organizations
ALTER TABLE public.organizations
    ADD COLUMN IF NOT EXISTS type                  text,
    ADD COLUMN IF NOT EXISTS status                text NOT NULL DEFAULT 'active'
        CHECK (status IN ('draft', 'active', 'suspended', 'archived')),
    ADD COLUMN IF NOT EXISTS neq                   text,
    ADD COLUMN IF NOT EXISTS address               text,
    ADD COLUMN IF NOT EXISTS region                text,
    ADD COLUMN IF NOT EXISTS maturity_level        text,
    ADD COLUMN IF NOT EXISTS primary_contact_email text,
    ADD COLUMN IF NOT EXISTS updated_at            TIMESTAMPTZ NOT NULL DEFAULT now();

-- Nouvelles colonnes sur organization_members
ALTER TABLE public.organization_members
    ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('invited', 'active', 'suspended', 'revoked')),
    ADD COLUMN IF NOT EXISTS operational_profile text NOT NULL DEFAULT 'bureau'
        CHECK (operational_profile IN ('bureau', 'terrain')),
    ADD COLUMN IF NOT EXISTS invited_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ;

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 1c — Recopier la notion "terrain" dans operational_profile
-- CRITIQUE : doit être exécuté AVANT le renommage des valeurs d'enum (1d)
-- La colonne s'appelle maintenant "org_role" (renommée en 1a-bis).
-- La valeur 'terrain' existe encore dans l'enum à ce stade.
-- ════════════════════════════════════════════════════════════

UPDATE public.organization_members
    SET operational_profile = 'terrain'
    WHERE org_role = 'terrain';

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 1d — Renommer les valeurs d'enum
-- (seulement maintenant, après la recopie de 1c)
-- ════════════════════════════════════════════════════════════

ALTER TYPE public.org_role RENAME VALUE 'owner' TO 'admin';
ALTER TYPE public.org_role RENAME VALUE 'terrain' TO 'membre';

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 2 — Table profiles
-- ════════════════════════════════════════════════════════════
-- Profil applicatif utilisateur, isolé de auth.users.
-- Tous les champs actor_id, user_id, generated_by de l'application
-- référencent profiles.id — jamais auth.users directement (MVP-DA-010).
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.profiles (
    id         UUID PRIMARY KEY,
    -- id = auth.users.id (synchronisé par trigger, pas de FK explicite
    -- pour garder le schéma public propre — convention Supabase)
    email      text NOT NULL,
    full_name  text,
    status     text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Trigger : création automatique du profil à l'inscription
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', split_part(NEW.email, '@', 1))
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 3 — Adapter les fonctions helper existantes
-- Les noms sont CONSERVÉS pour ne pas casser les policies existantes.
-- Seul le corps est mis à jour pour pointer vers les tables renommées
-- et les colonnes renommées (organization_id, org_role au lieu de company_id, role).
-- ════════════════════════════════════════════════════════════

-- is_company_member() — pointe maintenant vers organization_members
CREATE OR REPLACE FUNCTION public.is_company_member(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_company_id
          AND om.user_id = auth.uid()
    );
$$;

-- is_company_owner() — pointe maintenant vers organization_members avec org_role = 'admin'
CREATE OR REPLACE FUNCTION public.is_company_owner(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_company_id
          AND om.user_id = auth.uid()
          AND om.org_role = 'admin'
    );
$$;

-- company_has_no_members() — pointe maintenant vers organization_members
CREATE OR REPLACE FUNCTION public.company_has_no_members(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_company_id
    );
$$;

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 4 — Alias minces pour le domaine CCF
-- Le nouveau code CCF utilise ces fonctions.
-- Les policies CCF (migration 010) n'appellent JAMAIS
-- is_company_member() ni is_company_owner() — domaines séparés.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_organization_member(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_org_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_organization_owner(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_org_id
          AND om.user_id = auth.uid()
          AND om.org_role = 'admin'
          AND om.status = 'active'
    );
$$;

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 5 — Indexes
-- ════════════════════════════════════════════════════════════

-- organizations
CREATE INDEX IF NOT EXISTS idx_organizations_status ON public.organizations (status);
CREATE INDEX IF NOT EXISTS idx_organizations_neq    ON public.organizations (neq) WHERE neq IS NOT NULL;

-- organization_members
CREATE INDEX IF NOT EXISTS idx_org_members_org_id  ON public.organization_members (organization_id);
CREATE INDEX IF NOT EXISTS idx_org_members_user_id ON public.organization_members (user_id);
CREATE INDEX IF NOT EXISTS idx_org_members_status  ON public.organization_members (status);

-- Contrainte unique : un utilisateur ne peut avoir qu'un seul rôle actif par organisation
CREATE UNIQUE INDEX IF NOT EXISTS uq_org_members_active
    ON public.organization_members (organization_id, user_id)
    WHERE status IN ('active', 'invited');

-- profiles
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles (email);

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 6 — RLS sur profiles
-- (organizations et organization_members ont déjà RLS activé
--  depuis la migration company_members_invitations)
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Un utilisateur peut lire et modifier son propre profil
DROP POLICY IF EXISTS "profiles_self_all" ON public.profiles;
CREATE POLICY "profiles_self_all"
    ON public.profiles
    FOR ALL
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Super-admin plateforme : lecture complète des profils
DROP POLICY IF EXISTS "profiles_superadmin_select" ON public.profiles;
CREATE POLICY "profiles_superadmin_select"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());
