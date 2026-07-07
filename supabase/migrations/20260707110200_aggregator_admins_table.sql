-- ============================================================
-- MT-000A (CORRIGÉ) — Migration 20260707110200
-- Table : aggregator_admins
-- Fonction : is_aggregator_admin(UUID)
-- ============================================================
--
-- PRINCIPES D'ARCHITECTURE (non négociables) :
--   1. aggregator_admins est la SEULE source de vérité des administrateurs
--      de regroupement — jamais company_members, jamais owner, jamais
--      aucune déduction automatique.
--   2. Les nominations et révocations sont historisées.
--      La suppression physique d'un administrateur est INTERDITE.
--      La révocation se fait exclusivement via revoked_at IS NOT NULL.
--   3. is_aggregator_admin() ne consulte jamais company_members.role.
--   4. Source de vérité des rôles plateforme : app_metadata uniquement.
-- ============================================================

-- ── 1. ENUM : rôles d'administration de regroupement ─────────
DROP TYPE IF EXISTS public.aggregator_admin_role CASCADE;
CREATE TYPE public.aggregator_admin_role AS ENUM ('primary_admin', 'co_admin');

-- ── 2. TABLE : aggregator_admins ─────────────────────────────
-- Historique complet des nominations et révocations.
-- Aucune suppression physique autorisée (revoked_at IS NOT NULL = révoqué).
CREATE TABLE IF NOT EXISTS public.aggregator_admins (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_id  UUID        NOT NULL REFERENCES public.aggregators(id) ON DELETE CASCADE,
    user_id        UUID        NOT NULL,
    -- user_id référence auth.users via RLS (pas de FK pour garder le schéma public propre)
    role           public.aggregator_admin_role NOT NULL DEFAULT 'co_admin',
    nominated_by   UUID,
    -- nominated_by référence auth.users (l'admin qui a nommé)
    nominated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_by     UUID,
    -- revoked_by référence auth.users (l'admin qui a révoqué)
    revoked_at     TIMESTAMPTZ,
    -- NULL = actif ; NOT NULL = révoqué (suppression physique interdite)
    revocation_reason TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 3. INDEXES ───────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_aggregator_admins_aggregator_id
    ON public.aggregator_admins (aggregator_id);

CREATE INDEX IF NOT EXISTS idx_aggregator_admins_user_id
    ON public.aggregator_admins (user_id);

-- Index partiel pour les admins actifs (revoked_at IS NULL) — optimise is_aggregator_admin()
CREATE INDEX IF NOT EXISTS idx_aggregator_admins_active
    ON public.aggregator_admins (aggregator_id, user_id)
    WHERE revoked_at IS NULL;

-- ── 4. CONTRAINTE : un seul rôle actif par (aggregator, user) ─
-- Un utilisateur ne peut avoir qu'un seul rôle actif par regroupement.
-- Détecté par définition de contrainte (pas uniquement par nom).
CREATE UNIQUE INDEX IF NOT EXISTS uq_aggregator_admins_active_role
    ON public.aggregator_admins (aggregator_id, user_id)
    WHERE revoked_at IS NULL;

-- ── 5. FONCTION HELPER : is_aggregator_admin(UUID) ───────────
-- Vérifie si l'utilisateur courant est admin actif d'un regroupement donné.
-- Source de vérité : public.aggregator_admins UNIQUEMENT.
-- Ne consulte JAMAIS company_members.role.
-- Ne confère AUCUN droit à project_admin.
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

-- ── 6. ENABLE RLS ────────────────────────────────────────────
ALTER TABLE public.aggregator_admins ENABLE ROW LEVEL SECURITY;
