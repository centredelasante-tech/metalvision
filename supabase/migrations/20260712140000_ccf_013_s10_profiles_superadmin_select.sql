-- ============================================================
-- CCF-013 — S10 (Administration) : accès superadmin à profiles
-- Migration: 20260712140000_ccf_013_s10_profiles_superadmin_select.sql
-- ============================================================
--
-- CONTEXTE :
-- L'écran S10 (/admin) doit permettre à un admin plateforme de
-- consulter les utilisateurs à travers toutes les organisations
-- (E14-T01 : « Admin plateforme peut contrôler les référentiels »,
-- backlog technique v1.0).
--
-- `organizations` et `organization_members` ont déjà une policy
-- superadmin (`organizations_superadmin_all`, `org_members_superadmin_all`,
-- toutes deux basées sur is_platform_superadmin()) — mais `profiles`
-- n'en a aucune. Vérifié en production (pg_policies) le 12 juillet :
--   profiles_select_org_members : id = auth.uid() OR même organisation active
--   profiles_own_select         : id = auth.uid() (sous-ensemble redondant)
--   profiles_own_update         : id = auth.uid()
--
-- Sans cette policy, une jointure organization_members → profiles
-- pour lister les utilisateurs d'une organisation dont l'admin
-- plateforme n'est PAS membre renverrait un profil vide/null par
-- ligne — échec silencieux au même titre qu'INC-S02-09 (ADR-MVP.md
-- §7), pas une erreur visible.
--
-- Additive uniquement : les 2 policies SELECT existantes sur
-- profiles ne sont pas touchées (plusieurs policies permissives sur
-- une même commande sont combinées par OR en PostgreSQL RLS).
-- ============================================================

DROP POLICY IF EXISTS "profiles_superadmin_select" ON public.profiles;
CREATE POLICY "profiles_superadmin_select"
ON public.profiles
FOR SELECT
TO authenticated
USING (public.is_platform_superadmin());
