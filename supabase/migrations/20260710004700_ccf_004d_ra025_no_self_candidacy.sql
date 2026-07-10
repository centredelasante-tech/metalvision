-- ============================================================
-- CCF-004d — MVP-RA-025 : Séparation coordonnateur / candidat
--            enforce_no_self_candidacy()
-- ============================================================
--
-- ORDRE D'EXÉCUTION :
--   Après  : 20260710004600_ccf_004c_ra024_event_types.sql
--   Avant  : 20260710005000_ccf_005_ccf_projects_participants.sql
--
-- POURQUOI UNE MIGRATION SÉPARÉE (pas dans ccf_004c) :
--   Chaque migration ccf_004* documente un ajout fonctionnel distinct
--   et immuable. Modifier ccf_004c après coup briserait la traçabilité
--   séquentielle de la série ccf_004*. ccf_004d est la migration
--   dédiée à MVP-RA-025.
--
-- RÈGLE MÉTIER (MVP-RA-025) :
--   Dans le MVP, une organisation coordinatrice d'une opportunité
--   ne peut pas être candidate sur cette même opportunité.
--   Si opportunities.coordinator_org_id = capabilities.organization_id,
--   l'association ne peut pas être créée dans opportunity_capabilities.
--   S'applique uniquement à l'INSERT — opportunity_id et capability_id
--   sont déjà immuables après création par enforce_opp_cap_update_scope(),
--   donc pas besoin de revalider à l'UPDATE.
--
-- CONTENU :
--   1. Fonction trigger enforce_no_self_candidacy()
--   2. Trigger BEFORE INSERT sur opportunity_capabilities
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. FONCTION TRIGGER : enforce_no_self_candidacy
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.enforce_no_self_candidacy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_coordinator_org_id UUID;
    v_capability_org_id  UUID;
BEGIN
    SELECT coordinator_org_id INTO v_coordinator_org_id
    FROM public.opportunities WHERE id = NEW.opportunity_id;

    SELECT organization_id INTO v_capability_org_id
    FROM public.capabilities WHERE id = NEW.capability_id;

    IF v_coordinator_org_id = v_capability_org_id THEN
        RAISE EXCEPTION
            'MVP-RA-025 : l''organisation coordinatrice d''une opportunité ne peut pas être candidate sur sa propre opportunité (org %).',
            v_coordinator_org_id
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 2. TRIGGER BEFORE INSERT sur opportunity_capabilities
-- ════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS enforce_no_self_candidacy ON public.opportunity_capabilities;
CREATE TRIGGER enforce_no_self_candidacy
    BEFORE INSERT ON public.opportunity_capabilities
    FOR EACH ROW EXECUTE FUNCTION public.enforce_no_self_candidacy();
