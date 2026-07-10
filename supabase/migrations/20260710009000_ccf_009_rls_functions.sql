-- ============================================================
-- CCF-009 — Fonctions RLS utilitaires du domaine CCF
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   RT-04 : Fonctions RLS dans le schéma PUBLIC, pas auth.
--            Cohérent avec toutes les autres fonctions helper existantes.
--            Nommées public.user_org_ids() et public.user_project_ids().
--
-- RÈGLES CRITIQUES (MVP-RA-021 et MVP-RA-022) :
--   - Ces fonctions DOIVENT être créées AVANT les policies RLS (migration 010).
--   - Aucune policy CCF ne doit contourner ces fonctions par une logique locale.
--   - Le service role ne doit jamais servir à un flux utilisateur normal.
--
-- SÉPARATION DES DOMAINES RLS :
--   - is_company_member() / is_company_owner() → domaine Regroupements/MRV
--     (pointent vers organization_members depuis la migration 002)
--   - is_organization_member() / is_organization_owner() → domaine CCF
--     (alias minces créés dans la migration 002)
--   - public.user_org_ids() / public.user_project_ids() → domaine CCF
--     (fonctions utilitaires créées dans cette migration)
--   Les policies CCF (migration 010) n'appellent JAMAIS is_company_member()
--   ni les fonctions du domaine Regroupements/MRV.
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. public.user_org_ids()
-- ════════════════════════════════════════════════════════════
-- Retourne les organization_id où l'utilisateur courant est membre actif.
-- Utilisée dans les policies RLS du domaine CCF.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.user_org_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT organization_id
    FROM public.organization_members
    WHERE user_id = auth.uid()
      AND status = 'active';
$$;

-- ════════════════════════════════════════════════════════════
-- 2. public.user_project_ids()
-- ════════════════════════════════════════════════════════════
-- Retourne les project_id (ccf_projects) où l'utilisateur courant
-- participe via une organisation active dans project_participants.
-- Dépend de public.user_org_ids().
-- NOTE : LANGUAGE plpgsql utilisé pour différer la résolution de
--        public.project_participants à l'exécution (pas à la compilation).
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.user_project_ids()
RETURNS SETOF UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT pp.project_id
    FROM public.project_participants pp
    WHERE pp.organization_id = ANY(SELECT public.user_org_ids())
      AND pp.status = 'active';
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 3. public.is_ccf_project_coordinator(UUID)
-- ════════════════════════════════════════════════════════════
-- Retourne true si l'utilisateur courant est admin d'une organisation
-- coordinatrice du projet CCF donné.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_ccf_project_coordinator(p_project_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.ccf_projects p
        WHERE p.id = p_project_id
          AND p.coordinator_org_id = ANY(
              SELECT organization_id
              FROM public.organization_members
              WHERE user_id = auth.uid()
                AND org_role = 'admin'
                AND status = 'active'
          )
    );
$$;

-- ════════════════════════════════════════════════════════════
-- 4. public.is_ccf_project_participant(UUID)
-- ════════════════════════════════════════════════════════════
-- Retourne true si l'utilisateur courant est membre actif d'une
-- organisation participant activement au projet CCF donné.
-- NOTE : LANGUAGE plpgsql utilisé pour différer la résolution de
--        public.project_participants à l'exécution (pas à la compilation).
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_ccf_project_participant(p_project_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM public.project_participants pp
        WHERE pp.project_id = p_project_id
          AND pp.organization_id = ANY(SELECT public.user_org_ids())
          AND pp.status = 'active'
    );
END;
$$;

-- ════════════════════════════════════════════════════════════
-- NOTE : Séparation explicite des domaines RLS
-- ════════════════════════════════════════════════════════════
-- Domaine Regroupements/MRV (existant) :
--   is_company_member(UUID)  → organization_members (renommé depuis companies)
--   is_company_owner(UUID)   → organization_members avec role = 'admin'
--   is_aggregator_admin(UUID) → aggregator_admins
--
-- Domaine CCF (nouveau) :
--   is_organization_member(UUID) → organization_members, status = 'active'
--   is_organization_owner(UUID)  → organization_members, role = 'admin', status = 'active'
--   user_org_ids()               → organization_members, status = 'active'
--   user_project_ids()           → project_participants via user_org_ids()
--   is_ccf_project_coordinator() → ccf_projects + organization_members
--   is_ccf_project_participant() → project_participants + user_org_ids()
--
-- Les deux domaines coexistent dans la même base Supabase.
-- Une policy du domaine CCF qui appellerait accidentellement
-- is_company_member() créerait une fuite de données inter-domaines.
-- Cette séparation est documentée dans ADR-MVP.md.
