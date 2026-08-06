-- =============================================================================
-- ⚠️  BANDEAU DE CORRECTION — LIRE AVANT TOUTE ACTION (ajouté 2026-08-06)
-- =============================================================================
-- Cette version CORRIGE le fichier tel qu'appliqué historiquement sur
-- METALVISION-DEMO (commit `2a80e75`, 2026-08-01). Voir
-- supabase/MIGRATIONS_TIMELINE.md pour la table de correspondance complète et
-- les empreintes SHA-256 des deux versions.
--
-- CE QUI A CHANGÉ ET POURQUOI :
-- L'ancien STEP 3 de ce fichier (`DROP POLICY IF EXISTS
-- "ccf_projects_via_user_project_ids" ON public.ccf_projects;`) reposait sur
-- l'affirmation, en en-tête, que cette policy était « ABSENTE en production ».
-- Vérification live directe contre `dlbewgsoboaycbpypcus` le 2026-08-06
-- (GATE de préparation du déploiement production, lecture seule) : cette
-- affirmation était FAUSSE. La policy `ccf_projects_via_user_project_ids`
-- (`USING (id IN (SELECT user_project_ids()))`) est bien PRÉSENTE et ACTIVE
-- en production aujourd'hui. L'argument de redondance fonctionnelle avancé
-- par l'ancien en-tête (couverture strictement identique à
-- `is_ccf_project_participant()`) n'a jamais été validé par un test
-- comportemental contre la production — ce n'était donc pas la simple
-- formalité documentaire que le fichier prétendait, mais une suppression
-- réelle d'une policy RLS active si le fichier avait été appliqué tel quel.
--
-- CORRECTION APPORTÉE : le STEP 3 (DROP POLICY) est retiré de cette version.
-- Cette migration corrigée ne touche donc plus `ccf_projects_via_user_project_ids`
-- du tout — ni suppression, ni modification. La suppression éventuelle de
-- cette policy redevient une décision strictement séparée, non prise ici,
-- qui devra être précédée d'une validation comportementale explicite
-- (rôle `authenticated` simulé) avant toute nouvelle proposition.
--
-- PORTÉE DE CETTE VERSION CORRIGÉE : uniquement STEP 1 (fonction
-- `get_ccf_project_coordinator_org`) et STEP 2 (2 policies réconciliées :
-- `project_participants_select`, `ccf_projects_participant_select`). C'est la
-- seule version destinée à une éventuelle application future en production.
--
-- ÉTAT SUR METALVISION-DEMO : DEMO a reçu la version ORIGINALE de ce fichier
-- (avec l'ancien STEP 3, commit `2a80e75`) — cette correction ne rétroagit
-- pas sur DEMO. La policy `ccf_projects_via_user_project_ids` a donc bien été
-- supprimée sur DEMO au moment de cette application historique ; elle reste
-- présente sur production. Cet écart DEMO/production est désormais
-- documenté et assumé — voir MIGRATIONS_TIMELINE.md.
--
-- STATUT PRODUCTION : cette version corrigée n'a PAS été appliquée à
-- `dlbewgsoboaycbpypcus` à ce stade. Seule `get_my_portal_role()` a fait
-- l'objet d'une application distincte et séparée en production (voir GATE
-- correspondant) — aucune autre migration ou policy n'a été touchée.
-- =============================================================================

-- =============================================================================
-- Migration: Réconciliation project_participants / ccf_projects avec l'état
--            RÉEL de production (METALVISION, dlbewgsoboaycbpypcus)
-- Timestamp: 20260801010000
--
-- BROUILLON — NON APPLIQUÉE EN PRODUCTION. Rédigée sur autorisation explicite
-- pour documenter dans git l'état RLS déjà en vigueur en production sur ces 2
-- tables, jamais capturé par aucune migration versionnée. Ne remplace PAS
-- 20260713020000 (qui reste l'historique réel de ce qui a été investigué et
-- appliqué sur METALVISION-DEMO) — cette migration la RECONCILIE avec l'état
-- de production, constaté en direct le 2026-08-01 :
--
--   project_participants_select      → is_organization_member(get_ccf_project_coordinator_org(project_id))
--                                       OR is_organization_member(organization_id)
--   ccf_projects_participant_select  → is_organization_member(coordinator_org_id)
--                                       OR is_ccf_project_participant(id)
--   ccf_projects_via_user_project_ids → PRÉSENTE en production (vérifiée le
--                                        2026-08-06) — non touchée par cette
--                                        version corrigée, voir bandeau ci-dessus.
--
-- get_ccf_project_coordinator_org() existe en production (SECURITY DEFINER,
-- search_path=public) mais n'a JAMAIS eu de CREATE FUNCTION dans aucune
-- migration committée — appliquée directement en base à un moment non
-- documenté. Cette migration la verse enfin dans l'historique versionné.
--
-- is_ccf_project_participant() est déjà versionnée (20260710009000,
-- ccf_009_rls_functions.sql) et déjà identique sur DEMO et production
-- (vérifié par comparaison littérale des deux corps de fonction) — non
-- retouchée ici.
--
-- Nettoyage contrôlé des objets introduits uniquement sur DEMO par
-- 20260713020000 (is_project_coordinator_org_member(), et le renommage de
-- ccf_projects_participant_select en ccf_projects_coordinator_org_select) :
-- supprimés ci-dessous pour ne conserver qu'un seul état canonique, celui de
-- production.
--
-- Aucune donnée n'est touchée par cette migration : uniquement des objets de
-- catalogue (fonctions, policies). Aucun INSERT/UPDATE/DELETE/TRUNCATE.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP 1 — Fonction manquante côté DEMO, reproduite à l'identique de production
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_ccf_project_coordinator_org(p_project_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
    SELECT coordinator_org_id FROM public.ccf_projects WHERE id = p_project_id;
$function$;

-- ---------------------------------------------------------------------------
-- STEP 2 — Réécriture des 2 policies à l'identique de production
-- ---------------------------------------------------------------------------

-- ── TABLE: project_participants ─────────────────────────────────────────────

DROP POLICY IF EXISTS "project_participants_select" ON public.project_participants;
CREATE POLICY "project_participants_select"
    ON public.project_participants
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(public.get_ccf_project_coordinator_org(project_id))
        OR public.is_organization_member(organization_id)
    );

-- ── TABLE: ccf_projects ─────────────────────────────────────────────────────

-- Restaure le nom d'origine (ccf_projects_participant_select) et la branche
-- participant via is_ccf_project_participant(), à l'identique de production.
DROP POLICY IF EXISTS "ccf_projects_coordinator_org_select" ON public.ccf_projects;
DROP POLICY IF EXISTS "ccf_projects_participant_select" ON public.ccf_projects;
CREATE POLICY "ccf_projects_participant_select"
    ON public.ccf_projects
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(coordinator_org_id)
        OR public.is_ccf_project_participant(id)
    );

-- ---------------------------------------------------------------------------
-- STEP 3 — Nettoyage contrôlé : fonction introduite uniquement sur DEMO par
--          20260713020000, plus référencée par aucune policy après STEP 2
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.is_project_coordinator_org_member(uuid);
-- =============================================================================
