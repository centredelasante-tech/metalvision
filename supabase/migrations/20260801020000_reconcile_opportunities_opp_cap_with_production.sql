-- =============================================================================
-- Migration: Réconciliation opportunities / opportunity_capabilities avec
--            l'état RÉEL de production (METALVISION, dlbewgsoboaycbpypcus)
-- Timestamp: 20260801020000
--
-- BROUILLON — NON APPLIQUÉE. Rédigée sur autorisation explicite pour
-- documenter dans git l'état RLS déjà en vigueur en production sur ces 2
-- tables, jamais capturé par aucune migration versionnée. Ne remplace PAS
-- 20260713030000 (historique réel de l'investigation/correctif appliqué sur
-- METALVISION-DEMO) — cette migration la RECONCILIE avec l'état de
-- production, constaté en direct le 2026-08-01 :
--
--   opportunities_coordinator_select        → is_organization_member(coordinator_org_id)
--                                              OR is_opportunity_visible_via_active_candidacy(id)
--   opp_cap_member_select                   → sous-requête brute vers opportunities
--   opp_cap_update_coordinator_or_candidate → sous-requête brute vers opportunities
--   opp_cap_coordinator_admin_insert        → sous-requête brute vers opportunities
--
-- Contrairement à ce qu'affirmait 20260712010000 ("S04 NO-OP") et à ce que
-- j'avais moi-même écrit dans 20260713030000, is_opportunity_visible_via_
-- active_candidacy() EXISTE réellement en production (SECURITY DEFINER,
-- search_path=public) — vérifié par pg_get_functiondef le 2026-08-01. Elle
-- n'a simplement jamais eu de CREATE FUNCTION dans une migration committée.
-- Cette migration la verse enfin dans l'historique versionné, sous son nom
-- réel de production.
--
-- Les 3 policies de opportunity_capabilities restent, en production, des
-- sous-requêtes brutes vers opportunities (jamais réécrites en fonctions
-- SECURITY DEFINER). Ce n'est plus dangereux aujourd'hui : opportunities ne
-- boucle plus en brut vers opportunity_capabilities (branche 2 déjà
-- encapsulée), donc plus de cycle — vérifié empiriquement en production
-- (lecture seule, identité réelle non-superadmin, 2026-08-01 : aucune
-- récursion). Cette migration reproduit fidèlement cette forme plutôt que
-- d'imposer la réécriture complète que j'avais faite sur DEMO.
--
-- is_opportunity_capability_via_capability_member() et
-- is_opportunity_capability_via_capability_owner() sont déjà identiques sur
-- DEMO et production (héritées de 20260711060000) — non retouchées ici.
--
-- Nettoyage contrôlé des objets introduits uniquement sur DEMO par
-- 20260713030000 (is_opportunity_coordinator_org_member(),
-- is_opportunity_coordinator_org_owner(),
-- is_opportunity_via_active_candidacy_member()) : supprimés ci-dessous pour
-- ne conserver qu'un seul état canonique, celui de production.
--
-- Aucune donnée n'est touchée par cette migration : uniquement des objets de
-- catalogue (fonctions, policies). Aucun INSERT/UPDATE/DELETE/TRUNCATE.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP 1 — Fonction manquante côté DEMO, reproduite à l'identique de
--          production (nom réel : is_opportunity_visible_via_active_candidacy)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_opportunity_visible_via_active_candidacy(p_opportunity_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.opportunity_capabilities oc
        JOIN public.capabilities c ON c.id = oc.capability_id
        WHERE oc.opportunity_id = p_opportunity_id
          AND oc.status = 'active'
          AND public.is_organization_member(c.organization_id)
    );
$function$;

-- ---------------------------------------------------------------------------
-- STEP 2 — Réécriture des 4 policies à l'identique de production
-- ---------------------------------------------------------------------------

-- ── TABLE: opportunities ────────────────────────────────────────────────────

DROP POLICY IF EXISTS "opportunities_coordinator_select" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_select"
    ON public.opportunities
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(coordinator_org_id)
        OR public.is_opportunity_visible_via_active_candidacy(id)
    );

-- ── TABLE: opportunity_capabilities ─────────────────────────────────────────
-- Reproduit à l'identique la forme "sous-requête brute" observée en
-- production (non ré-encapsulée en fonction SECURITY DEFINER, contrairement
-- à 20260713030000 sur DEMO — voir justification en en-tête).

DROP POLICY IF EXISTS "opp_cap_member_select" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_member_select"
    ON public.opportunity_capabilities
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_capabilities.opportunity_id
              AND public.is_organization_member(o.coordinator_org_id)
        )
        OR public.is_opportunity_capability_via_capability_member(capability_id)
    );

DROP POLICY IF EXISTS "opp_cap_update_coordinator_or_candidate" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_update_coordinator_or_candidate"
    ON public.opportunity_capabilities
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_capabilities.opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
        OR public.is_opportunity_capability_via_capability_owner(capability_id)
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_capabilities.opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
        OR public.is_opportunity_capability_via_capability_owner(capability_id)
    );

DROP POLICY IF EXISTS "opp_cap_coordinator_admin_insert" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_coordinator_admin_insert"
    ON public.opportunity_capabilities
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_capabilities.opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
    );

-- ---------------------------------------------------------------------------
-- STEP 3 — Nettoyage contrôlé : fonctions introduites uniquement sur DEMO par
--          20260713030000, plus référencées par aucune policy après STEP 2
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.is_opportunity_via_active_candidacy_member(uuid);
DROP FUNCTION IF EXISTS public.is_opportunity_coordinator_org_member(uuid);
DROP FUNCTION IF EXISTS public.is_opportunity_coordinator_org_owner(uuid);
-- =============================================================================
