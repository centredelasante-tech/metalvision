-- =============================================================================
-- Migration: Réconciliation project_participants / ccf_projects avec l'état
--            RÉEL de production (METALVISION, dlbewgsoboaycbpypcus)
-- Timestamp: 20260801010000
--
-- BROUILLON — NON APPLIQUÉE. Rédigée sur autorisation explicite pour
-- documenter dans git l'état RLS déjà en vigueur en production sur ces 2
-- tables, jamais capturé par aucune migration versionnée. Ne remplace PAS
-- 20260713020000 (qui reste l'historique réel de ce qui a été investigué et
-- appliqué sur METALVISION-DEMO) — cette migration la RECONCILIE avec l'état
-- de production, constaté en direct le 2026-08-01 :
--
--   project_participants_select      → is_organization_member(get_ccf_project_coordinator_org(project_id))
--                                       OR is_organization_member(organization_id)
--   ccf_projects_participant_select  → is_organization_member(coordinator_org_id)
--                                       OR is_ccf_project_participant(id)
--   ccf_projects_via_user_project_ids → ABSENTE en production
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
-- Décision distincte signalée pour confirmation explicite : suppression de
-- ccf_projects_via_user_project_ids (présente sur DEMO depuis la migration
-- de base 20260710999000, absente en production). Elle devient totalement
-- redondante une fois ccf_projects_participant_select restaurée avec sa
-- branche is_ccf_project_participant(id) : les deux couvrent exactement le
-- même ensemble de lignes (un projet est retourné par user_project_ids() ssi
-- l'utilisateur est participant actif — exactement ce que vérifie
-- is_ccf_project_participant()). Sa suppression ne retire donc aucun accès
-- réel, mais c'est un choix distinct de la simple réconciliation des 2
-- policies principales — à valider explicitement avant exécution.
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
-- STEP 3 — Décision distincte signalée : suppression de la policy redondante
--          absente en production (voir justification en en-tête)
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "ccf_projects_via_user_project_ids" ON public.ccf_projects;

-- ---------------------------------------------------------------------------
-- STEP 4 — Nettoyage contrôlé : fonction introduite uniquement sur DEMO par
--          20260713020000, plus référencée par aucune policy après STEP 2
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.is_project_coordinator_org_member(uuid);
-- =============================================================================
