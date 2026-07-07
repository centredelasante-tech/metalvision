-- ============================================================
-- MT-000A (CORRIGÉ) — Migration 20260707110100
-- Fonction : is_platform_superadmin()
-- Rôle : supervision plateforme — accès exceptionnel aux regroupements
-- ============================================================
--
-- PRINCIPE D'ARCHITECTURE (non négociable) :
--   Seul le véritable administrateur plateforme (role = 'admin') peut
--   disposer d'un accès exceptionnel aux regroupements.
--   project_admin ne doit JAMAIS obtenir automatiquement ces droits.
--
-- SOURCE DE VÉRITÉ : auth.jwt() -> 'app_metadata' ->> 'role'
--   - Contrôlé exclusivement par le service-role / les admins plateforme
--   - Jamais modifiable par l'utilisateur lui-même
--   - raw_user_meta_data intentionnellement EXCLU (modifiable par l'utilisateur)
-- ============================================================

-- is_platform_superadmin()
-- Vérifie que l'utilisateur courant a le rôle 'admin' UNIQUEMENT.
-- project_admin intentionnellement exclu — séparation stricte des domaines.
CREATE OR REPLACE FUNCTION public.is_platform_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
$$;
