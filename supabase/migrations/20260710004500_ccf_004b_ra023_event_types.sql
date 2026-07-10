-- ============================================================
-- CCF-004b — MVP-RA-023 : Types d'événements retrait candidature
--            + trigger d'émission d'événement métier
-- ============================================================
--
-- ORDRE D'EXÉCUTION :
--   Après  : 20260710004000_ccf_004_capabilities_opportunities.sql
--   Avant  : 20260710005000_ccf_005_ccf_projects_participants.sql
--
-- POURQUOI UNE MIGRATION SÉPARÉE (pas dans ccf_001) :
--   ccf_001 crée public.ccf_event_type avec DROP TYPE … CASCADE.
--   Modifier ccf_001 après coup casserait toutes les migrations
--   qui dépendent de ce type (ccf_008, etc.).
--   ALTER TYPE … ADD VALUE est idempotent via le bloc DO ci-dessous
--   et ne casse aucune dépendance existante.
--
-- POURQUOI PAS DANS ccf_004 :
--   Le trigger emit_opportunity_capability_status_event insère dans
--   public.business_events, créée dans ccf_008. PostgreSQL valide
--   l'existence de la table cible à la compilation de la fonction
--   PL/pgSQL (LANGUAGE plpgsql). Placer la fonction dans ccf_004
--   (timestamp 004000, avant ccf_008 à 008000) provoquerait une
--   erreur 42P01 lors de l'application séquentielle des migrations.
--   Le timestamp 004500 place cette migration après ccf_004 mais
--   avant ccf_005 — la fonction est compilée après ccf_008 lors
--   d'une application complète depuis zéro, et peut être appliquée
--   en incrémental sur un schéma existant où ccf_008 est déjà présent.
--
-- CONTENU :
--   1. ALTER TYPE ccf_event_type — ajout des deux nouvelles valeurs
--   2. Fonction trigger emit_opportunity_capability_status_event
--   3. Trigger AFTER UPDATE sur opportunity_capabilities
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. EXTENSION DE ccf_event_type (MVP-RA-023)
-- ════════════════════════════════════════════════════════════
-- Ajout de :
--   'opportunity_capability_removed'   — retrait par le coordonnateur
--   'opportunity_capability_withdrawn' — retrait autonome par l'org candidate
--
-- ALTER TYPE … ADD VALUE est non transactionnel en PostgreSQL :
-- il ne peut pas être annulé dans un bloc BEGIN/COMMIT.
-- Le bloc DO ci-dessous vérifie l'existence avant d'ajouter
-- pour garantir l'idempotence (rejeu sûr).
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumtypid = 'public.ccf_event_type'::regtype
          AND enumlabel = 'opportunity_capability_removed'
    ) THEN
        ALTER TYPE public.ccf_event_type ADD VALUE 'opportunity_capability_removed';
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumtypid = 'public.ccf_event_type'::regtype
          AND enumlabel = 'opportunity_capability_withdrawn'
    ) THEN
        ALTER TYPE public.ccf_event_type ADD VALUE 'opportunity_capability_withdrawn';
    END IF;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 2. FONCTION TRIGGER : emit_opportunity_capability_status_event
-- ════════════════════════════════════════════════════════════
-- Déclenché AFTER UPDATE sur opportunity_capabilities.
-- Insère un événement métier dans business_events lorsque
-- le champ status change vers 'removed' ou 'withdrawn'.
--
-- Logique :
--   OLD.status → NEW.status = 'removed'   → event_type = 'opportunity_capability_removed'
--   OLD.status → NEW.status = 'withdrawn' → event_type = 'opportunity_capability_withdrawn'
--   Tout autre changement de status → aucun événement émis.
--
-- actor_id : résolu depuis profiles via auth.uid() (MVP-DA-010).
-- organization_id : organisation de l'acteur (coordonnateur ou candidate)
--   déterminée selon le nouveau status :
--     'removed'   → coordinator_org_id de l'opportunité
--     'withdrawn' → organization_id de la capacité
-- payload : contient opportunity_id, capability_id, old_status, new_status.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.emit_opportunity_capability_status_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_type    public.ccf_event_type;
    v_actor_id      UUID;
    v_org_id        UUID;
BEGIN
    -- Ne rien faire si status n'a pas changé ou si la nouvelle valeur
    -- n'est pas un statut de retrait géré par MVP-RA-023.
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF NEW.status = 'removed' THEN
        v_event_type := 'opportunity_capability_removed';
    ELSIF NEW.status = 'withdrawn' THEN
        v_event_type := 'opportunity_capability_withdrawn';
    ELSE
        -- Transition vers 'active' ou toute autre valeur : pas d'événement métier
        RETURN NEW;
    END IF;

    -- Résoudre l'actor_id depuis profiles (MVP-DA-010 : jamais auth.users directement)
    SELECT id INTO v_actor_id
    FROM public.profiles
    WHERE id = auth.uid()
    LIMIT 1;

    -- Résoudre l'organization_id selon le type d'acteur
    IF NEW.status = 'removed' THEN
        -- Coordonnateur : organization_id = coordinator_org_id de l'opportunité
        SELECT coordinator_org_id INTO v_org_id
        FROM public.opportunities
        WHERE id = NEW.opportunity_id;
    ELSIF NEW.status = 'withdrawn' THEN
        -- Organisation candidate : organization_id = organization_id de la capacité
        SELECT organization_id INTO v_org_id
        FROM public.capabilities
        WHERE id = NEW.capability_id;
    END IF;

    INSERT INTO public.business_events (
        event_type,
        object_type,
        object_id,
        actor_id,
        organization_id,
        payload
    ) VALUES (
        v_event_type,
        'opportunity',
        NEW.opportunity_id,
        v_actor_id,
        v_org_id,
        jsonb_build_object(
            'opportunity_id', NEW.opportunity_id,
            'capability_id',  NEW.capability_id,
            'old_status',     OLD.status,
            'new_status',     NEW.status
        )
    );

    RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 3. TRIGGER AFTER UPDATE sur opportunity_capabilities
-- ════════════════════════════════════════════════════════════
-- S'exécute après enforce_opp_cap_update_scope (BEFORE UPDATE),
-- donc uniquement si la mise à jour a été validée.
-- ════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS emit_opportunity_capability_status_event
    ON public.opportunity_capabilities;

CREATE TRIGGER emit_opportunity_capability_status_event
    AFTER UPDATE OF status ON public.opportunity_capabilities
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION public.emit_opportunity_capability_status_event();
