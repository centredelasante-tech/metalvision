-- ============================================================
-- CCF-004c — MVP-RA-024 : Relance d'une candidature retirée
--            Types d'événements + trigger d'émission
-- ============================================================
--
-- ORDRE D'EXÉCUTION :
--   Après  : 20260710004500_ccf_004b_ra023_event_types.sql
--   Avant  : 20260710005000_ccf_005_ccf_projects_participants.sql
--
-- POURQUOI UNE MIGRATION SÉPARÉE (pas dans ccf_004b) :
--   ccf_004b couvre MVP-RA-023 (removed, withdrawn).
--   MVP-RA-024 introduit trois nouvelles valeurs d'enum et redéfinit
--   la fonction emit_opportunity_capability_status_event() pour couvrir
--   les transitions de relance. Séparer les deux migrations préserve
--   l'immuabilité de ccf_004b et rend l'historique des fonctionnalités
--   explicitement traçable par migration.
--
-- CONTENU :
--   1. ALTER TYPE ccf_event_type — ajout des trois valeurs MVP-RA-024
--   2. Remplacement de emit_opportunity_capability_status_event()
--      pour couvrir les cinq transitions (RA-023 + RA-024)
--   3. Recréation du trigger AFTER UPDATE (DROP + CREATE)
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. EXTENSION DE ccf_event_type (MVP-RA-024)
-- ════════════════════════════════════════════════════════════
-- Ajout de :
--   'opportunity_capability_reinvited'            — relance initiée par le coordonnateur
--                                                   (withdrawn → pending_reacceptance)
--   'opportunity_capability_reaccepted'           — acceptation par l'org candidate
--                                                   (pending_reacceptance → active)
--   'opportunity_capability_reinvitation_declined'— refus par l'org candidate
--                                                   (pending_reacceptance → withdrawn)
--
-- Note : opportunity_capability_removed et opportunity_capability_withdrawn
-- ont déjà été ajoutés dans ccf_004b. Les blocs DO ci-dessous utilisent
-- le même mécanisme idempotent via vérification pg_enum.
--
-- ALTER TYPE … ADD VALUE est non transactionnel en PostgreSQL :
-- il ne peut pas être annulé dans un bloc BEGIN/COMMIT.
-- Le bloc DO vérifie l'existence avant d'ajouter pour garantir
-- l'idempotence (rejeu sûr).
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumtypid = 'public.ccf_event_type'::regtype
          AND enumlabel = 'opportunity_capability_reinvited'
    ) THEN
        ALTER TYPE public.ccf_event_type ADD VALUE 'opportunity_capability_reinvited';
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumtypid = 'public.ccf_event_type'::regtype
          AND enumlabel = 'opportunity_capability_reaccepted'
    ) THEN
        ALTER TYPE public.ccf_event_type ADD VALUE 'opportunity_capability_reaccepted';
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumtypid = 'public.ccf_event_type'::regtype
          AND enumlabel = 'opportunity_capability_reinvitation_declined'
    ) THEN
        ALTER TYPE public.ccf_event_type ADD VALUE 'opportunity_capability_reinvitation_declined';
    END IF;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 2. REMPLACEMENT DE emit_opportunity_capability_status_event()
-- ════════════════════════════════════════════════════════════
-- Cette version remplace celle de ccf_004b et couvre l'ensemble
-- des cinq transitions métier (MVP-RA-023 + MVP-RA-024) :
--
--   removed              ← active              → opportunity_capability_removed
--   withdrawn            ← active              → opportunity_capability_withdrawn
--   pending_reacceptance ← withdrawn           → opportunity_capability_reinvited
--   active               ← pending_reacceptance → opportunity_capability_reaccepted
--   withdrawn            ← pending_reacceptance → opportunity_capability_reinvitation_declined
--
-- actor_id : résolu depuis profiles via auth.uid() (MVP-DA-010).
-- organization_id : organisation de l'acteur déterminée selon la transition :
--   removed / reinvited  → coordinator_org_id de l'opportunité (acteur = coordonnateur)
--   withdrawn / reaccepted / reinvitation_declined → organization_id de la capacité
--                                                    (acteur = organisation candidate)
-- payload : contient opportunity_id, capability_id, old_status, new_status.
--
-- object_type / object_id : 'opportunity' / NEW.opportunity_id pour toutes les branches.
--   Choix délibéré : l'événement est ancré sur l'opportunité (entité agrégat),
--   pas sur la capacité, pour cohérence avec le reste du domaine CCF où
--   business_events référence toujours l'entité coordinatrice de la relation.
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
    v_actor_is_coordinator boolean := false;
BEGIN
    -- Ne rien faire si status n'a pas changé
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    -- ── Résolution de l'event_type selon la transition ────────
    IF OLD.status = 'active' AND NEW.status = 'removed' THEN
        v_event_type         := 'opportunity_capability_removed';
        v_actor_is_coordinator := true;

    ELSIF OLD.status = 'active' AND NEW.status = 'withdrawn' THEN
        v_event_type         := 'opportunity_capability_withdrawn';
        v_actor_is_coordinator := false;

    ELSIF OLD.status = 'withdrawn' AND NEW.status = 'pending_reacceptance' THEN
        v_event_type         := 'opportunity_capability_reinvited';
        v_actor_is_coordinator := true;

    ELSIF OLD.status = 'pending_reacceptance' AND NEW.status = 'active' THEN
        v_event_type         := 'opportunity_capability_reaccepted';
        v_actor_is_coordinator := false;

    ELSIF OLD.status = 'pending_reacceptance' AND NEW.status = 'withdrawn' THEN
        v_event_type         := 'opportunity_capability_reinvitation_declined';
        v_actor_is_coordinator := false;

    ELSE
        -- Transition active→active (mise à jour fit_score uniquement) :
        -- pas d'événement métier de changement de statut à émettre.
        RETURN NEW;
    END IF;

    -- ── Résolution de l'actor_id (MVP-DA-010) ─────────────────
    SELECT id INTO v_actor_id
    FROM public.profiles
    WHERE id = auth.uid()
    LIMIT 1;

    -- ── Résolution de l'organization_id selon l'acteur ────────
    IF v_actor_is_coordinator THEN
        -- Coordonnateur : organization_id = coordinator_org_id de l'opportunité
        SELECT coordinator_org_id INTO v_org_id
        FROM public.opportunities
        WHERE id = NEW.opportunity_id;
    ELSE
        -- Organisation candidate : organization_id = organization_id de la capacité
        SELECT organization_id INTO v_org_id
        FROM public.capabilities
        WHERE id = NEW.capability_id;
    END IF;

    -- ── Insertion de l'événement métier ───────────────────────
    INSERT INTO public.business_events (
        event_type,
        object_type,
        object_id,
        actor_id,
        organization_id,
        payload
    ) VALUES (
        v_event_type,
        -- object_type = 'opportunity' / object_id = NEW.opportunity_id pour toutes les branches.
        -- L'événement est ancré sur l'opportunité (entité agrégat), pas sur la capacité,
        -- pour cohérence avec le reste du domaine CCF.
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
-- Remplace le trigger créé dans ccf_004b.
-- S'exécute après enforce_opp_cap_update_scope (BEFORE UPDATE),
-- donc uniquement si la mise à jour a été validée.
-- Couvre l'ensemble des transitions MVP-RA-023 + MVP-RA-024.
-- ════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS emit_opportunity_capability_status_event
    ON public.opportunity_capabilities;

CREATE TRIGGER emit_opportunity_capability_status_event
    AFTER UPDATE OF status ON public.opportunity_capabilities
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION public.emit_opportunity_capability_status_event();
