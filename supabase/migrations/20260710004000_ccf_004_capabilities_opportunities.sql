-- ============================================================
-- CCF-004 — Capacités et Opportunités
-- ============================================================
--
-- CONTENU :
--   1. Table capabilities
--   2. Table opportunities
--   3. Table opportunity_capabilities (jonction)
--   4. Indexes
--   5. RLS
--   6. Trigger enforce_opp_cap_update_scope (MVP-RA-023)
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. TABLE : capabilities
-- ════════════════════════════════════════════════════════════
-- Représente ce qu'une organisation peut accomplir.
-- Base de la création de valeur collaborative (modèle COVI).
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.capabilities (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    material_type   text,
    monthly_volume  numeric,
    location        text,
    availability    text,
    maturity        text,
    status          text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'declared', 'qualified', 'suspended', 'archived')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ════════════════════════════════════════════════════════════
-- 2. TABLE : opportunities
-- ════════════════════════════════════════════════════════════
-- Possibilité qualifiée de créer de la valeur collective.
-- Précède la création de projets collaboratifs.
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.opportunities (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title               text NOT NULL,
    description         text,
    coordinator_org_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    region              text,
    target_volume       numeric,
    priority            text,
    status              text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'qualified', 'converted', 'closed', 'archived')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ════════════════════════════════════════════════════════════
-- 3. TABLE : opportunity_capabilities (jonction)
-- ════════════════════════════════════════════════════════════
-- Relie les capacités aux opportunités avec un score de correspondance.
-- MVP-RA-023 : status étendu à ('active', 'removed', 'withdrawn').
--   'removed'   = retiré par le coordonnateur de l'opportunité.
--   'withdrawn' = retrait autonome par l'organisation candidate.
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.opportunity_capabilities (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    opportunity_id UUID NOT NULL REFERENCES public.opportunities(id) ON DELETE CASCADE,
    capability_id  UUID NOT NULL REFERENCES public.capabilities(id) ON DELETE CASCADE,
    fit_score      numeric CHECK (fit_score >= 0 AND fit_score <= 100),
    status         text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'removed', 'withdrawn')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (opportunity_id, capability_id)
);

-- ════════════════════════════════════════════════════════════
-- 4. INDEXES
-- ════════════════════════════════════════════════════════════

-- capabilities
CREATE INDEX IF NOT EXISTS idx_capabilities_org_id ON public.capabilities (organization_id);
CREATE INDEX IF NOT EXISTS idx_capabilities_status ON public.capabilities (status);

-- opportunities
CREATE INDEX IF NOT EXISTS idx_opportunities_coordinator ON public.opportunities (coordinator_org_id);
CREATE INDEX IF NOT EXISTS idx_opportunities_status      ON public.opportunities (status);

-- opportunity_capabilities
CREATE INDEX IF NOT EXISTS idx_opp_cap_opportunity ON public.opportunity_capabilities (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_opp_cap_capability  ON public.opportunity_capabilities (capability_id);

-- ════════════════════════════════════════════════════════════
-- 5. RLS
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.capabilities          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opportunities         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opportunity_capabilities ENABLE ROW LEVEL SECURITY;

-- ── capabilities ─────────────────────────────────────────────

-- SELECT : l'organisation propriétaire peut lire ses capacités,
--          ET un coordinateur d'opportunité peut voir les capacités
--          candidates associées à son opportunité (liaison active).
DROP POLICY IF EXISTS "capabilities_owner_select" ON public.capabilities;
CREATE POLICY "capabilities_owner_select"
    ON public.capabilities
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(organization_id)
        OR EXISTS (
            SELECT 1 FROM public.opportunity_capabilities oc
            JOIN public.opportunities o ON o.id = oc.opportunity_id
            WHERE oc.capability_id = capabilities.id
              AND oc.status = 'active'
              AND public.is_organization_member(o.coordinator_org_id)
        )
    );

-- INSERT : seul un admin de l'organisation peut déclarer une capacité
DROP POLICY IF EXISTS "capabilities_owner_admin_insert" ON public.capabilities;
CREATE POLICY "capabilities_owner_admin_insert"
    ON public.capabilities
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_organization_owner(organization_id));

-- UPDATE : seul un admin de l'organisation peut modifier une capacité
DROP POLICY IF EXISTS "capabilities_owner_admin_update" ON public.capabilities;
CREATE POLICY "capabilities_owner_admin_update"
    ON public.capabilities
    FOR UPDATE
    TO authenticated
    USING (public.is_organization_owner(organization_id))
    WITH CHECK (public.is_organization_owner(organization_id));

-- Super-admin : lecture complète
DROP POLICY IF EXISTS "capabilities_superadmin_select" ON public.capabilities;
CREATE POLICY "capabilities_superadmin_select"
    ON public.capabilities
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());

-- ── opportunities ─────────────────────────────────────────────

-- SELECT : l'organisation coordinatrice peut lire ses opportunités,
--          ET une organisation candidate peut voir l'opportunité à
--          laquelle sa capacité est associée (liaison active).
DROP POLICY IF EXISTS "opportunities_coordinator_select" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_select"
    ON public.opportunities
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(coordinator_org_id)
        OR EXISTS (
            SELECT 1 FROM public.opportunity_capabilities oc
            JOIN public.capabilities c ON c.id = oc.capability_id
            WHERE oc.opportunity_id = opportunities.id
              AND oc.status = 'active'
              AND public.is_organization_member(c.organization_id)
        )
    );

-- INSERT : seul un admin de l'organisation coordinatrice peut créer
DROP POLICY IF EXISTS "opportunities_coordinator_admin_insert" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_admin_insert"
    ON public.opportunities
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_organization_owner(coordinator_org_id));

-- UPDATE : seul un admin de l'organisation coordinatrice peut modifier
DROP POLICY IF EXISTS "opportunities_coordinator_admin_update" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_admin_update"
    ON public.opportunities
    FOR UPDATE
    TO authenticated
    USING (public.is_organization_owner(coordinator_org_id))
    WITH CHECK (public.is_organization_owner(coordinator_org_id));

-- Super-admin : lecture complète
DROP POLICY IF EXISTS "opportunities_superadmin_select" ON public.opportunities;
CREATE POLICY "opportunities_superadmin_select"
    ON public.opportunities
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());

-- ── opportunity_capabilities ──────────────────────────────────

-- SELECT : visible par les membres des organisations liées
DROP POLICY IF EXISTS "opp_cap_member_select" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_member_select"
    ON public.opportunity_capabilities
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_member(o.coordinator_org_id)
        )
        OR
        EXISTS (
            SELECT 1 FROM public.capabilities c
            WHERE c.id = capability_id
              AND public.is_organization_member(c.organization_id)
        )
    );

-- INSERT : admin de l'organisation coordinatrice de l'opportunité
DROP POLICY IF EXISTS "opp_cap_coordinator_admin_insert" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_coordinator_admin_insert"
    ON public.opportunity_capabilities
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
    );

-- UPDATE (MVP-RA-023) : policy élargie — coordonnateur OU organisation candidate.
--   Le trigger enforce_opp_cap_update_scope (section 6) limite ensuite
--   précisément ce que chacun peut modifier :
--     • coordonnateur : peut modifier fit_score et passer status → 'removed'
--     • organisation candidate : peut uniquement passer status → 'withdrawn'
--       (uniquement sur sa propre capacité, uniquement depuis 'active')
DROP POLICY IF EXISTS "opp_cap_coordinator_admin_update" ON public.opportunity_capabilities;
DROP POLICY IF EXISTS "opp_cap_update_coordinator_or_candidate" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_update_coordinator_or_candidate"
    ON public.opportunity_capabilities
    FOR UPDATE
    TO authenticated
    USING (
        -- Coordonnateur de l'opportunité
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
        OR
        -- Organisation candidate (propriétaire de la capacité liée)
        EXISTS (
            SELECT 1 FROM public.capabilities c
            WHERE c.id = capability_id
              AND public.is_organization_owner(c.organization_id)
        )
    )
    WITH CHECK (
        -- Coordonnateur de l'opportunité
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
        OR
        -- Organisation candidate (propriétaire de la capacité liée)
        EXISTS (
            SELECT 1 FROM public.capabilities c
            WHERE c.id = capability_id
              AND public.is_organization_owner(c.organization_id)
        )
    );

-- Super-admin : lecture complète
DROP POLICY IF EXISTS "opp_cap_superadmin_select" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_superadmin_select"
    ON public.opportunity_capabilities
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());

-- ════════════════════════════════════════════════════════════
-- 6. TRIGGER : enforce_opp_cap_update_scope (MVP-RA-023)
-- ════════════════════════════════════════════════════════════
-- La policy RLS ci-dessus autorise deux acteurs à faire un UPDATE.
-- Ce trigger BEFORE UPDATE affine les droits en rejetant toute
-- modification hors périmètre :
--
--   Coordonnateur (admin de coordinator_org_id) :
--     - Peut modifier fit_score (toute valeur valide).
--     - Peut passer status de 'active' → 'removed'.
--     - Ne peut PAS passer status → 'withdrawn'.
--     - Ne peut PAS modifier opportunity_id, capability_id, created_at.
--
--   Organisation candidate (admin de la org propriétaire de la capacité) :
--     - Peut UNIQUEMENT passer status de 'active' → 'withdrawn'.
--     - Ne peut PAS modifier fit_score, opportunity_id, capability_id,
--       created_at, ni passer status vers toute autre valeur.
--     - Ne peut PAS retirer ('removed') — c'est le rôle du coordonnateur.
--
-- Toute tentative hors périmètre lève une exception SQLSTATE P0001.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.enforce_opp_cap_update_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_coordinator  boolean := false;
    v_is_candidate    boolean := false;
BEGIN
    -- Déterminer le rôle de l'appelant sur cette ligne
    SELECT EXISTS (
        SELECT 1 FROM public.opportunities o
        WHERE o.id = NEW.opportunity_id
          AND public.is_organization_owner(o.coordinator_org_id)
    ) INTO v_is_coordinator;

    SELECT EXISTS (
        SELECT 1 FROM public.capabilities c
        WHERE c.id = NEW.capability_id
          AND public.is_organization_owner(c.organization_id)
    ) INTO v_is_candidate;

    -- ── Champs immuables (pour tous) ──────────────────────────
    IF NEW.opportunity_id <> OLD.opportunity_id THEN
        RAISE EXCEPTION 'opportunity_id est immuable sur opportunity_capabilities'
            USING ERRCODE = 'P0001';
    END IF;
    IF NEW.capability_id <> OLD.capability_id THEN
        RAISE EXCEPTION 'capability_id est immuable sur opportunity_capabilities'
            USING ERRCODE = 'P0001';
    END IF;
    IF NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'created_at est immuable sur opportunity_capabilities'
            USING ERRCODE = 'P0001';
    END IF;

    -- ── Règles coordonnateur ──────────────────────────────────
    IF v_is_coordinator THEN
        -- Le coordonnateur ne peut pas passer status → 'withdrawn'
        IF NEW.status = 'withdrawn' THEN
            RAISE EXCEPTION 'Le coordonnateur ne peut pas passer status à ''withdrawn'' — seule l''organisation candidate peut se retirer'
                USING ERRCODE = 'P0001';
        END IF;
        -- Transitions de status autorisées pour le coordonnateur :
        -- active → removed  (retrait par le coordonnateur)
        -- active → active   (pas de changement de status, ex. mise à jour fit_score)
        -- removed → removed (idempotent)
        IF NEW.status NOT IN ('active', 'removed') THEN
            RAISE EXCEPTION 'Transition de status non autorisée pour le coordonnateur : % → %',
                OLD.status, NEW.status
                USING ERRCODE = 'P0001';
        END IF;
        RETURN NEW;
    END IF;

    -- ── Règles organisation candidate ────────────────────────
    IF v_is_candidate THEN
        -- L'organisation candidate ne peut QUE passer status active → withdrawn
        IF NOT (OLD.status = 'active' AND NEW.status = 'withdrawn') THEN
            RAISE EXCEPTION 'L''organisation candidate ne peut que passer status de ''active'' à ''withdrawn'' (état actuel : %)',
                OLD.status
                USING ERRCODE = 'P0001';
        END IF;
        -- fit_score ne doit pas changer
        IF NEW.fit_score IS DISTINCT FROM OLD.fit_score THEN
            RAISE EXCEPTION 'L''organisation candidate ne peut pas modifier fit_score'
                USING ERRCODE = 'P0001';
        END IF;
        RETURN NEW;
    END IF;

    -- Aucun rôle reconnu (ne devrait pas arriver si la policy RLS est correcte)
    RAISE EXCEPTION 'Accès refusé : l''utilisateur courant n''est ni coordonnateur ni organisation candidate pour cette liaison'
        USING ERRCODE = 'P0001';
END;
$$;

DROP TRIGGER IF EXISTS enforce_opp_cap_update_scope ON public.opportunity_capabilities;
CREATE TRIGGER enforce_opp_cap_update_scope
    BEFORE UPDATE ON public.opportunity_capabilities
    FOR EACH ROW EXECUTE FUNCTION public.enforce_opp_cap_update_scope();
