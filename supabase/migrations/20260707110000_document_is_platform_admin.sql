-- ============================================================
-- MT-000A (CORRIGÉ) — Migration 20260707110000
-- Correction des fonctions RLS helper : source de vérité exclusive = app_metadata
-- Principe : auth.jwt() -> app_metadata uniquement (jamais raw_user_meta_data)
-- ============================================================
--
-- FAILLE CORRIGÉE :
--   Les versions précédentes lisaient raw_user_meta_data->>'role', un champ
--   modifiable par l'utilisateur lui-même via l'API Supabase Auth.
--   Seul raw_app_meta_data (= app_metadata dans le JWT) est contrôlé
--   exclusivement par le service-role / les administrateurs de la plateforme.
--
-- RÈGLE D'ARCHITECTURE (non négociable) :
--   Toute vérification de rôle plateforme doit utiliser :
--     (auth.jwt() -> 'app_metadata' ->> 'role')
--   ou de manière équivalente via auth.users :
--     au.raw_app_meta_data->>'role'
--   JAMAIS : raw_user_meta_data, user_metadata
-- ============================================================

-- ── 1. is_project_admin() ─────────────────────────────────────
-- Rôle : accès admin aux domaines MRV/projets (project_admin OU admin)
-- Domaine : MRV uniquement — INTERDIT dans le domaine Regroupements
-- Source de vérité : raw_app_meta_data exclusivement
CREATE OR REPLACE FUNCTION public.is_project_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') IN ('project_admin', 'admin')
$$;

-- ── 2. is_platform_admin() ────────────────────────────────────
-- Rôle : alias documenté de is_project_admin() — même périmètre
-- Domaine : MRV/transport uniquement — INTERDIT dans le domaine Regroupements
-- Source de vérité : raw_app_meta_data exclusivement
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') IN ('project_admin', 'admin')
$$;

-- ── 3. is_verifier() ──────────────────────────────────────────
-- Rôle : accès lecture aux données MRV pour les vérificateurs tiers
-- Source de vérité : raw_app_meta_data exclusivement
CREATE OR REPLACE FUNCTION public.is_verifier()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'verifier'
$$;

-- ── 4. is_project_client() ────────────────────────────────────
-- Rôle : accès lecture à ses propres projets MRV
-- Source de vérité : raw_app_meta_data exclusivement
CREATE OR REPLACE FUNCTION public.is_project_client()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') IN ('project_client', 'client')
$$;

-- ── 5. is_admin_from_auth() ───────────────────────────────────
-- Rôle : vérifie role = 'admin' uniquement (domaine Observations)
-- Source de vérité : raw_app_meta_data exclusivement
-- Note : fonctionnellement identique à is_platform_superadmin()
--        conservé pour compatibilité avec les policies existantes
CREATE OR REPLACE FUNCTION public.is_admin_from_auth()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
$$;
