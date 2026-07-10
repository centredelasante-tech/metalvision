-- ============================================================
-- RESET COMPLET + RÉAPPLICATION INTÉGRALE DU SCHÉMA CCF
-- ============================================================
--
-- ⚠️  STAGING UNIQUEMENT — NE PAS APPLIQUER EN PRODUCTION ⚠️
--
-- Ce fichier :
--   1. Réinitialise complètement le schéma public (DROP CASCADE)
--   2. Réapplique dans l'ordre : ccf_001 → ccf_002 → ccf_003 →
--      ccf_004 → ccf_004b → ccf_004c → ccf_004d → ccf_005 →
--      ccf_006 → ccf_006b → ccf_006c → ccf_007 → ccf_008 →
--      ccf_009 → ccf_010 → ccf_011 (version corrigée)
--   3. Applique le seed de démonstration (demo_ccf.sql)
--
-- CORRECTIONS INTÉGRÉES :
--   - ccf_010 : colonne "role" corrigée en "org_role" (renommée dans ccf_002)
--   - ccf_011 : "ccf_project_phase" retiré de la vérification des ENUMs
--               (ce type est supprimé dans ccf_005 — RT-05)
--
-- APRÈS APPLICATION, vérifier :
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' ORDER BY table_name;
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- ÉTAPE 0 — RÉINITIALISATION COMPLÈTE DU SCHÉMA PUBLIC
-- ════════════════════════════════════════════════════════════

DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;

-- ════════════════════════════════════════════════════════════
-- CCF-001 — Extensions & ENUMs du domaine collaboratif
-- ════════════════════════════════════════════════════════════

DROP TYPE IF EXISTS public.mandate_scope CASCADE;
CREATE TYPE public.mandate_scope AS ENUM (
    'gouvernance',
    'operationnel',
    'financier',
    'technique',
    'verification',
    'ia'
);

DROP TYPE IF EXISTS public.document_visibility CASCADE;
CREATE TYPE public.document_visibility AS ENUM (
    'organization_private',
    'project',
    'confidential'
);

DROP TYPE IF EXISTS public.logistics_step_type CASCADE;
CREATE TYPE public.logistics_step_type AS ENUM (
    'ramassage',
    'chargement',
    'expedition',
    'transit',
    'livraison',
    'preuve_finale'
);

DROP TYPE IF EXISTS public.ccf_event_type CASCADE;
CREATE TYPE public.ccf_event_type AS ENUM (
    'organization_created',
    'organization_suspended',
    'member_invited',
    'member_activated',
    'mandate_issued',
    'mandate_accepted',
    'mandate_revoked',
    'capability_declared',
    'capability_qualified',
    'opportunity_created',
    'opportunity_qualified',
    'project_created',
    'project_phase_changed',
    'document_submitted',
    'document_approved',
    'logistics_step_updated',
    'value_report_generated'
);

-- ════════════════════════════════════════════════════════════
-- CCF-002 — Profils, Organisations, Membres d'organisation
-- ════════════════════════════════════════════════════════════

-- Recréer le type org_role (schéma vierge — pas de renommage nécessaire)
DROP TYPE IF EXISTS public.org_role CASCADE;
CREATE TYPE public.org_role AS ENUM ('admin', 'membre');

-- Table organizations (anciennement companies)
CREATE TABLE IF NOT EXISTS public.organizations (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL,
    type       text,
    status     text NOT NULL DEFAULT 'active'
        CHECK (status IN ('draft', 'active', 'suspended', 'archived')),
    neq        text,
    address    text,
    region     text,
    maturity_level        text,
    primary_contact_email text,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table organization_members (anciennement company_members)
CREATE TABLE IF NOT EXISTS public.organization_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    org_role        public.org_role NOT NULL DEFAULT 'membre',
    status          text NOT NULL DEFAULT 'active'
        CHECK (status IN ('invited', 'active', 'suspended', 'revoked')),
    operational_profile text NOT NULL DEFAULT 'bureau'
        CHECK (operational_profile IN ('bureau', 'terrain')),
    invited_at      TIMESTAMPTZ,
    activated_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table profiles
CREATE TABLE IF NOT EXISTS public.profiles (
    id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email      text NOT NULL,
    full_name  text,
    status     text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Trigger : création automatique du profil à l'inscription
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', split_part(NEW.email, '@', 1))
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- Fonctions helper (noms originaux conservés pour compatibilité)
CREATE OR REPLACE FUNCTION public.is_company_member(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_company_id
          AND om.user_id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public.is_company_owner(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_company_id
          AND om.user_id = auth.uid()
          AND om.org_role = 'admin'
    );
$$;

CREATE OR REPLACE FUNCTION public.company_has_no_members(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_company_id
    );
$$;

-- Alias CCF
CREATE OR REPLACE FUNCTION public.is_organization_member(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_org_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_organization_owner(p_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = p_org_id
          AND om.user_id = auth.uid()
          AND om.org_role = 'admin'
          AND om.status = 'active'
    );
$$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_organizations_status ON public.organizations (status);
CREATE INDEX IF NOT EXISTS idx_organizations_neq    ON public.organizations (neq) WHERE neq IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_org_members_org_id   ON public.organization_members (organization_id);
CREATE INDEX IF NOT EXISTS idx_org_members_user_id  ON public.organization_members (user_id);

-- RLS organizations
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_own_select" ON public.profiles;
CREATE POLICY "profiles_own_select"
    ON public.profiles FOR SELECT TO authenticated
    USING (id = auth.uid());

DROP POLICY IF EXISTS "profiles_own_update" ON public.profiles;
CREATE POLICY "profiles_own_update"
    ON public.profiles FOR UPDATE TO authenticated
    USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- ════════════════════════════════════════════════════════════
-- is_platform_superadmin — requis par ccf_003 et suivants
-- (défini ici car ccf_002 est le bon endroit pour les helpers globaux)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_platform_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (auth.jwt() -> 'app_metadata' ->> 'is_platform_superadmin')::boolean,
        false
    );
$$;

-- ════════════════════════════════════════════════════════════
-- CCF-003 — Mandats et permissions
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.mandate_actions (
    code        text PRIMARY KEY,
    label       text NOT NULL,
    description text,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.mandate_actions (code, label, description) VALUES
    ('read_capabilities',          'Lire les capacités',           'Lire les capacités autorisées dans un contexte projet ou opportunité'),
    ('propose_participation',      'Proposer une participation',   'Proposer la participation d''une organisation à une opportunité'),
    ('invite_project_org',         'Inviter une organisation',     'Inviter une organisation à participer à un projet (WF-04)'),
    ('accept_project_invitation',  'Accepter une invitation',      'Accepter un mandat ou une invitation de projet pour son organisation'),
    ('manage_project_participants','Gérer les participants',        'Gérer les participants actifs d''un projet dans le périmètre du mandat'),
    ('approve_documents',          'Approuver des documents',      'Valider un document déposé dans le projet'),
    ('submit_logistics_proof',     'Déposer une preuve logistique','Déposer une preuve logistique rattachée à une étape spécifique (WF-07)'),
    ('update_logistics_step',      'Mettre à jour une étape',      'Mettre à jour une étape logistique dont l''organisation est responsable'),
    ('generate_value_report',      'Générer un rapport de valeur', 'Générer ou valider une synthèse de valeur créée (WF-08)'),
    ('request_ai_summary',         'Demander une synthèse IA',     'Demander une synthèse IA dans le contexte déjà autorisé')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.mandates (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issuer_org_id    UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    receiver_org_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    mandate_scope    public.mandate_scope NOT NULL,
    permissions      jsonb NOT NULL,
    status           text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'pending_acceptance', 'active', 'expired', 'revoked')),
    start_date       TIMESTAMPTZ,
    end_date         TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT mandates_different_orgs CHECK (issuer_org_id != receiver_org_id)
);

CREATE OR REPLACE FUNCTION public.validate_mandate_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_action  text;
    v_actions jsonb;
BEGIN
    v_actions := COALESCE(NEW.permissions -> 'actions', '[]'::jsonb);
    IF jsonb_typeof(v_actions) != 'array' THEN
        RAISE EXCEPTION 'mandates.permissions.actions doit être un tableau JSON (reçu: %)', jsonb_typeof(v_actions);
    END IF;
    IF jsonb_array_length(v_actions) = 0 THEN
        RAISE EXCEPTION 'mandates.permissions.actions doit contenir au moins une action du catalogue mandate_actions.';
    END IF;
    FOR v_action IN SELECT jsonb_array_elements_text(v_actions) LOOP
        IF NOT EXISTS (SELECT 1 FROM public.mandate_actions WHERE code = v_action) THEN
            RAISE EXCEPTION 'Action de mandat invalide : "%" n''existe pas dans le catalogue mandate_actions.', v_action;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_mandate_permissions_trigger ON public.mandates;
CREATE TRIGGER validate_mandate_permissions_trigger
    BEFORE INSERT OR UPDATE ON public.mandates
    FOR EACH ROW EXECUTE FUNCTION public.validate_mandate_permissions();

CREATE INDEX IF NOT EXISTS idx_mandates_issuer_org   ON public.mandates (issuer_org_id);
CREATE INDEX IF NOT EXISTS idx_mandates_receiver_org ON public.mandates (receiver_org_id);
CREATE INDEX IF NOT EXISTS idx_mandates_status       ON public.mandates (status);
CREATE INDEX IF NOT EXISTS idx_mandates_active
    ON public.mandates (issuer_org_id, receiver_org_id)
    WHERE status = 'active';

ALTER TABLE public.mandates        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mandate_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mandate_actions_authenticated_select" ON public.mandate_actions;
CREATE POLICY "mandate_actions_authenticated_select"
    ON public.mandate_actions FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "mandates_org_select" ON public.mandates;
CREATE POLICY "mandates_org_select"
    ON public.mandates FOR SELECT TO authenticated
    USING (
        public.is_organization_member(issuer_org_id)
        OR public.is_organization_member(receiver_org_id)
    );

DROP POLICY IF EXISTS "mandates_issuer_admin_insert" ON public.mandates;
CREATE POLICY "mandates_issuer_admin_insert"
    ON public.mandates FOR INSERT TO authenticated
    WITH CHECK (public.is_organization_owner(issuer_org_id));

DROP POLICY IF EXISTS "mandates_org_admin_update" ON public.mandates;
CREATE POLICY "mandates_org_admin_update"
    ON public.mandates FOR UPDATE TO authenticated
    USING (
        public.is_organization_owner(issuer_org_id)
        OR public.is_organization_owner(receiver_org_id)
    )
    WITH CHECK (
        public.is_organization_owner(issuer_org_id)
        OR public.is_organization_owner(receiver_org_id)
    );

DROP POLICY IF EXISTS "mandates_superadmin_select" ON public.mandates;
CREATE POLICY "mandates_superadmin_select"
    ON public.mandates FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

-- ════════════════════════════════════════════════════════════
-- CCF-004 — Capacités et Opportunités
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

CREATE TABLE IF NOT EXISTS public.opportunity_capabilities (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    opportunity_id UUID NOT NULL REFERENCES public.opportunities(id) ON DELETE CASCADE,
    capability_id  UUID NOT NULL REFERENCES public.capabilities(id) ON DELETE CASCADE,
    fit_score      numeric CHECK (fit_score >= 0 AND fit_score <= 100),
    status         text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'removed', 'withdrawn', 'pending_reacceptance')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (opportunity_id, capability_id)
);

CREATE INDEX IF NOT EXISTS idx_capabilities_org_id   ON public.capabilities (organization_id);
CREATE INDEX IF NOT EXISTS idx_capabilities_status   ON public.capabilities (status);
CREATE INDEX IF NOT EXISTS idx_opportunities_coordinator ON public.opportunities (coordinator_org_id);
CREATE INDEX IF NOT EXISTS idx_opportunities_status      ON public.opportunities (status);
CREATE INDEX IF NOT EXISTS idx_opp_cap_opportunity   ON public.opportunity_capabilities (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_opp_cap_capability    ON public.opportunity_capabilities (capability_id);

ALTER TABLE public.capabilities             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opportunities            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opportunity_capabilities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "capabilities_owner_select" ON public.capabilities;
CREATE POLICY "capabilities_owner_select"
    ON public.capabilities FOR SELECT TO authenticated
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

DROP POLICY IF EXISTS "capabilities_owner_admin_insert" ON public.capabilities;
CREATE POLICY "capabilities_owner_admin_insert"
    ON public.capabilities FOR INSERT TO authenticated
    WITH CHECK (public.is_organization_owner(organization_id));

DROP POLICY IF EXISTS "capabilities_owner_admin_update" ON public.capabilities;
CREATE POLICY "capabilities_owner_admin_update"
    ON public.capabilities FOR UPDATE TO authenticated
    USING (public.is_organization_owner(organization_id))
    WITH CHECK (public.is_organization_owner(organization_id));

DROP POLICY IF EXISTS "capabilities_superadmin_select" ON public.capabilities;
CREATE POLICY "capabilities_superadmin_select"
    ON public.capabilities FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

DROP POLICY IF EXISTS "opportunities_coordinator_select" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_select"
    ON public.opportunities FOR SELECT TO authenticated
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

DROP POLICY IF EXISTS "opportunities_coordinator_admin_insert" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_admin_insert"
    ON public.opportunities FOR INSERT TO authenticated
    WITH CHECK (public.is_organization_owner(coordinator_org_id));

DROP POLICY IF EXISTS "opportunities_coordinator_admin_update" ON public.opportunities;
CREATE POLICY "opportunities_coordinator_admin_update"
    ON public.opportunities FOR UPDATE TO authenticated
    USING (public.is_organization_owner(coordinator_org_id))
    WITH CHECK (public.is_organization_owner(coordinator_org_id));

DROP POLICY IF EXISTS "opportunities_superadmin_select" ON public.opportunities;
CREATE POLICY "opportunities_superadmin_select"
    ON public.opportunities FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

DROP POLICY IF EXISTS "opp_cap_member_select" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_member_select"
    ON public.opportunity_capabilities FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_member(o.coordinator_org_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.capabilities c
            WHERE c.id = capability_id
              AND public.is_organization_member(c.organization_id)
        )
    );

DROP POLICY IF EXISTS "opp_cap_coordinator_admin_insert" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_coordinator_admin_insert"
    ON public.opportunity_capabilities FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
    );

DROP POLICY IF EXISTS "opp_cap_coordinator_admin_update" ON public.opportunity_capabilities;
DROP POLICY IF EXISTS "opp_cap_update_coordinator_or_candidate" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_update_coordinator_or_candidate"
    ON public.opportunity_capabilities FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.capabilities c
            WHERE c.id = capability_id
              AND public.is_organization_owner(c.organization_id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.opportunities o
            WHERE o.id = opportunity_id
              AND public.is_organization_owner(o.coordinator_org_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.capabilities c
            WHERE c.id = capability_id
              AND public.is_organization_owner(c.organization_id)
        )
    );

DROP POLICY IF EXISTS "opp_cap_superadmin_select" ON public.opportunity_capabilities;
CREATE POLICY "opp_cap_superadmin_select"
    ON public.opportunity_capabilities FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

-- Trigger enforce_opp_cap_update_scope (MVP-RA-023 / MVP-RA-024)
CREATE OR REPLACE FUNCTION public.enforce_opp_cap_update_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_coordinator boolean := false;
    v_is_candidate   boolean := false;
BEGIN
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

    IF NEW.opportunity_id <> OLD.opportunity_id THEN
        RAISE EXCEPTION 'opportunity_id est immuable sur opportunity_capabilities' USING ERRCODE = 'P0001';
    END IF;
    IF NEW.capability_id <> OLD.capability_id THEN
        RAISE EXCEPTION 'capability_id est immuable sur opportunity_capabilities' USING ERRCODE = 'P0001';
    END IF;
    IF NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'created_at est immuable sur opportunity_capabilities' USING ERRCODE = 'P0001';
    END IF;

    IF v_is_coordinator THEN
        IF NOT (
            (OLD.status = 'active'    AND NEW.status = 'active')
            OR (OLD.status = 'active'    AND NEW.status = 'removed')
            OR (OLD.status = 'withdrawn' AND NEW.status = 'pending_reacceptance')
        ) THEN
            RAISE EXCEPTION 'Transition de status non autorisée pour le coordonnateur : % → %.', OLD.status, NEW.status USING ERRCODE = 'P0001';
        END IF;
        IF NEW.fit_score IS DISTINCT FROM OLD.fit_score THEN
            IF NOT (OLD.status = 'active' AND NEW.status = 'active') THEN
                RAISE EXCEPTION 'fit_score ne peut être modifié que lorsque OLD.status = ''active'' AND NEW.status = ''active'' (transition courante : % → %)', OLD.status, NEW.status USING ERRCODE = 'P0001';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    IF v_is_candidate THEN
        IF NOT (
            (OLD.status = 'active'               AND NEW.status = 'withdrawn')
            OR (OLD.status = 'pending_reacceptance' AND NEW.status = 'active')
            OR (OLD.status = 'pending_reacceptance' AND NEW.status = 'withdrawn')
        ) THEN
            RAISE EXCEPTION 'Transition de status non autorisée pour l''organisation candidate : % → %.', OLD.status, NEW.status USING ERRCODE = 'P0001';
        END IF;
        IF NEW.fit_score IS DISTINCT FROM OLD.fit_score THEN
            RAISE EXCEPTION 'L''organisation candidate ne peut pas modifier fit_score' USING ERRCODE = 'P0001';
        END IF;
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Accès refusé : l''utilisateur courant n''est ni coordonnateur ni organisation candidate pour cette liaison' USING ERRCODE = 'P0001';
END;
$$;

DROP TRIGGER IF EXISTS enforce_opp_cap_update_scope ON public.opportunity_capabilities;
CREATE TRIGGER enforce_opp_cap_update_scope
    BEFORE UPDATE ON public.opportunity_capabilities
    FOR EACH ROW EXECUTE FUNCTION public.enforce_opp_cap_update_scope();

-- ════════════════════════════════════════════════════════════
-- CCF-004b — MVP-RA-023 : Types d'événements retrait candidature
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
-- CCF-004c — MVP-RA-024 : Relance d'une candidature retirée
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

-- Fonction emit_opportunity_capability_status_event (version finale ccf_004c)
-- NOTE : insère dans public.business_events créée dans ccf_008 ci-dessous.
-- La fonction est définie ici mais le trigger sera créé après business_events.
CREATE OR REPLACE FUNCTION public.emit_opportunity_capability_status_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_type           public.ccf_event_type;
    v_actor_id             UUID;
    v_org_id               UUID;
    v_actor_is_coordinator boolean := false;
BEGIN
    IF NEW.status = OLD.status THEN RETURN NEW; END IF;

    IF OLD.status = 'active' AND NEW.status = 'removed' THEN
        v_event_type := 'opportunity_capability_removed';
        v_actor_is_coordinator := true;
    ELSIF OLD.status = 'active' AND NEW.status = 'withdrawn' THEN
        v_event_type := 'opportunity_capability_withdrawn';
        v_actor_is_coordinator := false;
    ELSIF OLD.status = 'withdrawn' AND NEW.status = 'pending_reacceptance' THEN
        v_event_type := 'opportunity_capability_reinvited';
        v_actor_is_coordinator := true;
    ELSIF OLD.status = 'pending_reacceptance' AND NEW.status = 'active' THEN
        v_event_type := 'opportunity_capability_reaccepted';
        v_actor_is_coordinator := false;
    ELSIF OLD.status = 'pending_reacceptance' AND NEW.status = 'withdrawn' THEN
        v_event_type := 'opportunity_capability_reinvitation_declined';
        v_actor_is_coordinator := false;
    ELSE
        RETURN NEW;
    END IF;

    SELECT id INTO v_actor_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;

    IF v_actor_is_coordinator THEN
        SELECT coordinator_org_id INTO v_org_id FROM public.opportunities WHERE id = NEW.opportunity_id;
    ELSE
        SELECT organization_id INTO v_org_id FROM public.capabilities WHERE id = NEW.capability_id;
    END IF;

    INSERT INTO public.business_events (event_type, object_type, object_id, actor_id, organization_id, payload)
    VALUES (
        v_event_type, 'opportunity', NEW.opportunity_id, v_actor_id, v_org_id,
        jsonb_build_object('opportunity_id', NEW.opportunity_id, 'capability_id', NEW.capability_id, 'old_status', OLD.status, 'new_status', NEW.status)
    );

    RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- CCF-004d — MVP-RA-025 : Séparation coordonnateur / candidat
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
    SELECT coordinator_org_id INTO v_coordinator_org_id FROM public.opportunities WHERE id = NEW.opportunity_id;
    SELECT organization_id    INTO v_capability_org_id  FROM public.capabilities   WHERE id = NEW.capability_id;
    IF v_coordinator_org_id = v_capability_org_id THEN
        RAISE EXCEPTION 'MVP-RA-025 : l''organisation coordinatrice d''une opportunité ne peut pas être candidate sur sa propre opportunité (org %).', v_coordinator_org_id USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_no_self_candidacy ON public.opportunity_capabilities;
CREATE TRIGGER enforce_no_self_candidacy
    BEFORE INSERT ON public.opportunity_capabilities
    FOR EACH ROW EXECUTE FUNCTION public.enforce_no_self_candidacy();

-- ════════════════════════════════════════════════════════════
-- CCF-005 — Projets CCF et Participants
-- ════════════════════════════════════════════════════════════

-- RT-05 : ccf_project_phase supprimé — phase est TEXT+CHECK dans ccf_projects
DROP TYPE IF EXISTS public.ccf_project_phase CASCADE;

CREATE TABLE IF NOT EXISTS public.ccf_projects (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    opportunity_id      UUID NOT NULL REFERENCES public.opportunities(id) ON DELETE RESTRICT,
    title               text NOT NULL,
    coordinator_org_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    phase               text NOT NULL DEFAULT 'draft'
        CHECK (phase IN ('draft', 'active', 'execution', 'review', 'closed')),
    status              text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'active', 'paused', 'closed', 'archived')),
    start_date          TIMESTAMPTZ,
    target_end_date     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.project_participants (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES public.ccf_projects(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    project_role    text NOT NULL DEFAULT 'contributeur'
        CHECK (project_role IN ('coordonnateur', 'contributeur', 'lecteur')),
    mandate_id      UUID REFERENCES public.mandates(id) ON DELETE SET NULL,
    status          text NOT NULL DEFAULT 'invited'
        CHECK (status IN ('invited', 'active', 'declined', 'removed')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (project_id, organization_id)
);

CREATE INDEX IF NOT EXISTS idx_ccf_projects_coordinator ON public.ccf_projects (coordinator_org_id);
CREATE INDEX IF NOT EXISTS idx_ccf_projects_opportunity ON public.ccf_projects (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_ccf_projects_status      ON public.ccf_projects (status);
CREATE INDEX IF NOT EXISTS idx_ccf_projects_phase       ON public.ccf_projects (phase);
CREATE INDEX IF NOT EXISTS idx_project_participants_project ON public.project_participants (project_id);
CREATE INDEX IF NOT EXISTS idx_project_participants_org     ON public.project_participants (organization_id);
CREATE INDEX IF NOT EXISTS idx_project_participants_status  ON public.project_participants (status);
CREATE INDEX IF NOT EXISTS idx_project_participants_active
    ON public.project_participants (project_id, organization_id)
    WHERE status = 'active';

ALTER TABLE public.ccf_projects        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ccf_projects_participant_select" ON public.ccf_projects;
CREATE POLICY "ccf_projects_participant_select"
    ON public.ccf_projects FOR SELECT TO authenticated
    USING (
        public.is_organization_member(coordinator_org_id)
        OR EXISTS (
            SELECT 1 FROM public.project_participants pp
            WHERE pp.project_id = ccf_projects.id
              AND public.is_organization_member(pp.organization_id)
              AND pp.status = 'active'
        )
    );

DROP POLICY IF EXISTS "ccf_projects_coordinator_admin_insert" ON public.ccf_projects;
CREATE POLICY "ccf_projects_coordinator_admin_insert"
    ON public.ccf_projects FOR INSERT TO authenticated
    WITH CHECK (public.is_organization_owner(coordinator_org_id));

DROP POLICY IF EXISTS "ccf_projects_coordinator_admin_update" ON public.ccf_projects;
CREATE POLICY "ccf_projects_coordinator_admin_update"
    ON public.ccf_projects FOR UPDATE TO authenticated
    USING (public.is_organization_owner(coordinator_org_id))
    WITH CHECK (public.is_organization_owner(coordinator_org_id));

DROP POLICY IF EXISTS "ccf_projects_superadmin_select" ON public.ccf_projects;
CREATE POLICY "ccf_projects_superadmin_select"
    ON public.ccf_projects FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

DROP POLICY IF EXISTS "project_participants_select" ON public.project_participants;
CREATE POLICY "project_participants_select"
    ON public.project_participants FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_member(p.coordinator_org_id)
        )
        OR public.is_organization_member(organization_id)
    );

DROP POLICY IF EXISTS "project_participants_coordinator_insert" ON public.project_participants;
CREATE POLICY "project_participants_coordinator_insert"
    ON public.project_participants FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
    );

DROP POLICY IF EXISTS "project_participants_update" ON public.project_participants;
CREATE POLICY "project_participants_update"
    ON public.project_participants FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
        OR public.is_organization_owner(organization_id)
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
        OR public.is_organization_owner(organization_id)
    );

-- ════════════════════════════════════════════════════════════
-- CCF-006 — Documents (métadonnées et stockage)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.documents (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_org_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    object_type   text NOT NULL
        CHECK (object_type IN (
            'organization', 'capability', 'opportunity',
            'project', 'mandate', 'value_report'
        )),
    object_id     UUID NOT NULL,
    title         text NOT NULL,
    category      text,
    version       text NOT NULL DEFAULT '1.0',
    visibility    public.document_visibility NOT NULL DEFAULT 'organization_private',
    storage_path  text,
    status        text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'submitted', 'approved', 'rejected', 'archived')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.documents
    DROP CONSTRAINT IF EXISTS documents_project_visibility_requires_project_object;
ALTER TABLE public.documents
    ADD CONSTRAINT documents_project_visibility_requires_project_object
    CHECK (visibility <> 'project' OR object_type = 'project');

CREATE INDEX IF NOT EXISTS idx_documents_owner_org  ON public.documents (owner_org_id);
CREATE INDEX IF NOT EXISTS idx_documents_object     ON public.documents (object_type, object_id);
CREATE INDEX IF NOT EXISTS idx_documents_visibility ON public.documents (visibility);
CREATE INDEX IF NOT EXISTS idx_documents_status     ON public.documents (status);

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "documents_org_private_select" ON public.documents;
CREATE POLICY "documents_org_private_select"
    ON public.documents FOR SELECT TO authenticated
    USING (
        visibility = 'organization_private'
        AND public.is_organization_member(owner_org_id)
    );

DROP POLICY IF EXISTS "documents_confidential_select" ON public.documents;
CREATE POLICY "documents_confidential_select"
    ON public.documents FOR SELECT TO authenticated
    USING (
        visibility = 'confidential'
        AND (
            public.is_organization_member(owner_org_id)
            OR (
                object_type = 'opportunity'
                AND EXISTS (
                    SELECT 1 FROM public.opportunities o
                    WHERE o.id = documents.object_id
                      AND public.is_organization_member(o.coordinator_org_id)
                )
            )
            OR (
                object_type = 'project'
                AND EXISTS (
                    SELECT 1 FROM public.ccf_projects p
                    WHERE p.id = documents.object_id
                      AND public.is_organization_member(p.coordinator_org_id)
                )
            )
            OR (
                object_type = 'mandate'
                AND EXISTS (
                    SELECT 1 FROM public.mandates m
                    WHERE m.id = documents.object_id
                      AND (
                          public.is_organization_member(m.issuer_org_id)
                          OR public.is_organization_member(m.receiver_org_id)
                      )
                )
            )
        )
    );
-- NOTE: the 'value_report' branch is intentionally omitted here because
-- public.value_reports does not yet exist at this point in the migration.
-- It is added as a separate policy below, after value_reports is created (CCF-007).

DROP POLICY IF EXISTS "documents_owner_admin_insert" ON public.documents;
CREATE POLICY "documents_owner_admin_insert"
    ON public.documents FOR INSERT TO authenticated
    WITH CHECK (public.is_organization_owner(owner_org_id));

DROP POLICY IF EXISTS "documents_owner_admin_update" ON public.documents;
CREATE POLICY "documents_owner_admin_update"
    ON public.documents FOR UPDATE TO authenticated
    USING (public.is_organization_owner(owner_org_id))
    WITH CHECK (public.is_organization_owner(owner_org_id));

DROP POLICY IF EXISTS "documents_superadmin_select" ON public.documents;
CREATE POLICY "documents_superadmin_select"
    ON public.documents FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

-- ════════════════════════════════════════════════════════════
-- CCF-006b — Policy documents_project_select
-- (project_participants existe maintenant — ccf_005 appliqué ci-dessus)
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "documents_project_select" ON public.documents;
CREATE POLICY "documents_project_select"
    ON public.documents FOR SELECT TO authenticated
    USING (
        visibility = 'project'
        AND (
            public.is_organization_member(owner_org_id)
            OR (
                object_type = 'project'
                AND EXISTS (
                    SELECT 1 FROM public.project_participants pp
                    WHERE pp.project_id = documents.object_id
                      AND public.is_organization_member(pp.organization_id)
                      AND pp.status = 'active'
                )
            )
        )
    );

-- ════════════════════════════════════════════════════════════
-- CCF-006c — Contrainte CHECK visibility/object_type (idempotent)
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.documents
    DROP CONSTRAINT IF EXISTS documents_project_visibility_requires_project_object;
ALTER TABLE public.documents
    ADD CONSTRAINT documents_project_visibility_requires_project_object
    CHECK (visibility <> 'project' OR object_type = 'project');

-- ════════════════════════════════════════════════════════════
-- CCF-007 — Étapes logistiques, Rapports de valeur, Logs IA
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.logistics_steps (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id          UUID NOT NULL REFERENCES public.ccf_projects(id) ON DELETE CASCADE,
    step_type           public.logistics_step_type NOT NULL,
    responsible_org_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    planned_date        TIMESTAMPTZ,
    actual_date         TIMESTAMPTZ,
    proof_document_id   UUID REFERENCES public.documents(id) ON DELETE SET NULL,
    status              text NOT NULL DEFAULT 'planned'
        CHECK (status IN ('planned', 'in_progress', 'completed', 'blocked', 'cancelled')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.value_reports (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id          UUID NOT NULL REFERENCES public.ccf_projects(id) ON DELETE CASCADE,
    volume              numeric,
    coordination_value  numeric,
    notes               text,
    generated_by        UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    status              text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'generated', 'validated', 'shared', 'archived')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ai_assistance_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    object_type    text NOT NULL
        CHECK (object_type IN (
            'organization', 'capability', 'opportunity', 'project',
            'mandate', 'document', 'logistics_step', 'value_report'
        )),
    object_id      UUID NOT NULL,
    prompt_type    text NOT NULL,
    result_summary text,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_logistics_steps_project     ON public.logistics_steps (project_id);
CREATE INDEX IF NOT EXISTS idx_logistics_steps_responsible ON public.logistics_steps (responsible_org_id);
CREATE INDEX IF NOT EXISTS idx_logistics_steps_status      ON public.logistics_steps (status);
CREATE INDEX IF NOT EXISTS idx_value_reports_project       ON public.value_reports (project_id);
CREATE INDEX IF NOT EXISTS idx_value_reports_generated_by  ON public.value_reports (generated_by);
CREATE INDEX IF NOT EXISTS idx_value_reports_status        ON public.value_reports (status);
CREATE INDEX IF NOT EXISTS idx_ai_logs_user_id             ON public.ai_assistance_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_object              ON public.ai_assistance_logs (object_type, object_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_created_at          ON public.ai_assistance_logs (created_at DESC);

ALTER TABLE public.logistics_steps    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.value_reports      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_assistance_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "logistics_steps_select" ON public.logistics_steps;
CREATE POLICY "logistics_steps_select"
    ON public.logistics_steps FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_member(p.coordinator_org_id)
        )
        OR public.is_organization_member(responsible_org_id)
    );

DROP POLICY IF EXISTS "logistics_steps_update" ON public.logistics_steps;
CREATE POLICY "logistics_steps_update"
    ON public.logistics_steps FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = responsible_org_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
              AND (om.org_role = 'admin' OR om.operational_profile = 'terrain')
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = responsible_org_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
              AND (om.org_role = 'admin' OR om.operational_profile = 'terrain')
        )
    );

DROP POLICY IF EXISTS "logistics_steps_coordinator_insert" ON public.logistics_steps;
CREATE POLICY "logistics_steps_coordinator_insert"
    ON public.logistics_steps FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
    );

DROP POLICY IF EXISTS "logistics_steps_superadmin_select" ON public.logistics_steps;
CREATE POLICY "logistics_steps_superadmin_select"
    ON public.logistics_steps FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

-- Deferred policy for documents with object_type='value_report'
-- (split from documents_confidential_select because value_reports didn't exist yet in CCF-006)
DROP POLICY IF EXISTS "documents_confidential_value_report_select" ON public.documents;
CREATE POLICY "documents_confidential_value_report_select"
    ON public.documents FOR SELECT TO authenticated
    USING (
        visibility = 'confidential'
        AND object_type = 'value_report'
        AND EXISTS (
            SELECT 1
            FROM public.value_reports vr
            JOIN public.ccf_projects p ON p.id = vr.project_id
            WHERE vr.id = documents.object_id
              AND public.is_organization_member(p.coordinator_org_id)
        )
    );

DROP POLICY IF EXISTS "value_reports_participant_select" ON public.value_reports;
CREATE POLICY "value_reports_participant_select"
    ON public.value_reports FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_member(p.coordinator_org_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.project_participants pp
            WHERE pp.project_id = value_reports.project_id
              AND public.is_organization_member(pp.organization_id)
              AND pp.status = 'active'
        )
    );

DROP POLICY IF EXISTS "value_reports_coordinator_insert" ON public.value_reports;
CREATE POLICY "value_reports_coordinator_insert"
    ON public.value_reports FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
    );

DROP POLICY IF EXISTS "value_reports_coordinator_update" ON public.value_reports;
CREATE POLICY "value_reports_coordinator_update"
    ON public.value_reports FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
    );

DROP POLICY IF EXISTS "ai_logs_own_select" ON public.ai_assistance_logs;
CREATE POLICY "ai_logs_own_select"
    ON public.ai_assistance_logs FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "ai_logs_own_insert" ON public.ai_assistance_logs;
CREATE POLICY "ai_logs_own_insert"
    ON public.ai_assistance_logs FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "ai_logs_superadmin_select" ON public.ai_assistance_logs;
CREATE POLICY "ai_logs_superadmin_select"
    ON public.ai_assistance_logs FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

-- ════════════════════════════════════════════════════════════
-- CCF-008 — Événements métier et Logs d'audit
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.business_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type      public.ccf_event_type NOT NULL,
    object_type     text NOT NULL
        CHECK (object_type IN (
            'organization', 'capability', 'opportunity', 'project',
            'mandate', 'document', 'logistics_step', 'value_report'
        )),
    object_id       UUID NOT NULL,
    actor_id        UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
    payload         jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action      text NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    table_name  text NOT NULL,
    record_id   UUID,
    before      jsonb,
    after       jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.audit_log_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor_id  UUID;
    v_record_id UUID;
    v_before    jsonb;
    v_after     jsonb;
BEGIN
    SELECT id INTO v_actor_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
    IF TG_OP = 'DELETE' THEN
        v_record_id := OLD.id; v_before := to_jsonb(OLD); v_after := NULL;
    ELSIF TG_OP = 'INSERT' THEN
        v_record_id := NEW.id; v_before := NULL; v_after := to_jsonb(NEW);
    ELSE
        v_record_id := NEW.id; v_before := to_jsonb(OLD); v_after := to_jsonb(NEW);
    END IF;
    INSERT INTO public.audit_logs (actor_id, action, table_name, record_id, before, after)
    VALUES (v_actor_id, TG_OP, TG_TABLE_NAME, v_record_id, v_before, v_after);
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS audit_organizations ON public.organizations;
CREATE TRIGGER audit_organizations
    AFTER INSERT OR UPDATE OR DELETE ON public.organizations
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_organization_members ON public.organization_members;
CREATE TRIGGER audit_organization_members
    AFTER INSERT OR UPDATE OR DELETE ON public.organization_members
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_mandates ON public.mandates;
CREATE TRIGGER audit_mandates
    AFTER INSERT OR UPDATE OR DELETE ON public.mandates
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_ccf_projects ON public.ccf_projects;
CREATE TRIGGER audit_ccf_projects
    AFTER INSERT OR UPDATE OR DELETE ON public.ccf_projects
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_project_participants ON public.project_participants;
CREATE TRIGGER audit_project_participants
    AFTER INSERT OR UPDATE OR DELETE ON public.project_participants
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_documents ON public.documents;
CREATE TRIGGER audit_documents
    AFTER INSERT OR UPDATE OR DELETE ON public.documents
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_logistics_steps ON public.logistics_steps;
CREATE TRIGGER audit_logistics_steps
    AFTER INSERT OR UPDATE OR DELETE ON public.logistics_steps
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_value_reports ON public.value_reports;
CREATE TRIGGER audit_value_reports
    AFTER INSERT OR UPDATE OR DELETE ON public.value_reports
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_capabilities ON public.capabilities;
CREATE TRIGGER audit_capabilities
    AFTER INSERT OR UPDATE OR DELETE ON public.capabilities
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_opportunities ON public.opportunities;
CREATE TRIGGER audit_opportunities
    AFTER INSERT OR UPDATE OR DELETE ON public.opportunities
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

-- Trigger emit_opportunity_capability_status_event
-- (fonction définie dans ccf_004c ci-dessus, business_events existe maintenant)
DROP TRIGGER IF EXISTS emit_opportunity_capability_status_event ON public.opportunity_capabilities;
CREATE TRIGGER emit_opportunity_capability_status_event
    AFTER UPDATE OF status ON public.opportunity_capabilities
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION public.emit_opportunity_capability_status_event();

CREATE INDEX IF NOT EXISTS idx_business_events_type       ON public.business_events (event_type);
CREATE INDEX IF NOT EXISTS idx_business_events_object     ON public.business_events (object_type, object_id);
CREATE INDEX IF NOT EXISTS idx_business_events_actor      ON public.business_events (actor_id);
CREATE INDEX IF NOT EXISTS idx_business_events_org        ON public.business_events (organization_id);
CREATE INDEX IF NOT EXISTS idx_business_events_created_at ON public.business_events (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_table_name      ON public.audit_logs (table_name);
CREATE INDEX IF NOT EXISTS idx_audit_logs_record_id       ON public.audit_logs (record_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor           ON public.audit_logs (actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at      ON public.audit_logs (created_at DESC);

ALTER TABLE public.business_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "business_events_org_select" ON public.business_events;
CREATE POLICY "business_events_org_select"
    ON public.business_events FOR SELECT TO authenticated
    USING (
        public.is_organization_member(organization_id)
        OR actor_id = auth.uid()
    );

DROP POLICY IF EXISTS "business_events_authenticated_insert" ON public.business_events;
CREATE POLICY "business_events_authenticated_insert"
    ON public.business_events FOR INSERT TO authenticated
    WITH CHECK (actor_id = auth.uid());

DROP POLICY IF EXISTS "business_events_superadmin_select" ON public.business_events;
CREATE POLICY "business_events_superadmin_select"
    ON public.business_events FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

DROP POLICY IF EXISTS "audit_logs_superadmin_select" ON public.audit_logs;
CREATE POLICY "audit_logs_superadmin_select"
    ON public.audit_logs FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

-- ════════════════════════════════════════════════════════════
-- CCF-009 — Fonctions RLS utilitaires du domaine CCF
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

CREATE OR REPLACE FUNCTION public.is_ccf_project_coordinator(p_project_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
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
END;
$$;

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
-- CCF-010 — Policies RLS consolidées du domaine CCF
-- CORRECTION : "role" → "org_role" (renommé dans ccf_002)
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "organizations_project_participant_select" ON public.organizations;
CREATE POLICY "organizations_project_participant_select"
    ON public.organizations FOR SELECT TO authenticated
    USING (
        id = ANY(SELECT public.user_org_ids())
        OR EXISTS (
            SELECT 1 FROM public.project_participants pp
            WHERE pp.organization_id = organizations.id
              AND pp.project_id = ANY(SELECT public.user_project_ids())
              AND pp.status = 'active'
        )
        OR EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.coordinator_org_id = organizations.id
              AND p.id = ANY(SELECT public.user_project_ids())
        )
    );

DROP POLICY IF EXISTS "organizations_authenticated_insert" ON public.organizations;
CREATE POLICY "organizations_authenticated_insert"
    ON public.organizations FOR INSERT TO authenticated
    WITH CHECK (true);

-- CORRECTION ccf_010 : "role" → "org_role"
DROP POLICY IF EXISTS "organizations_admin_update" ON public.organizations;
CREATE POLICY "organizations_admin_update"
    ON public.organizations FOR UPDATE TO authenticated
    USING (id = ANY(
        SELECT organization_id FROM public.organization_members
        WHERE user_id = auth.uid() AND org_role = 'admin' AND status = 'active'
    ))
    WITH CHECK (id = ANY(
        SELECT organization_id FROM public.organization_members
        WHERE user_id = auth.uid() AND org_role = 'admin' AND status = 'active'
    ));

DROP POLICY IF EXISTS "organizations_superadmin_all" ON public.organizations;
CREATE POLICY "organizations_superadmin_all"
    ON public.organizations FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "org_members_same_org_select" ON public.organization_members;
CREATE POLICY "org_members_same_org_select"
    ON public.organization_members FOR SELECT TO authenticated
    USING (organization_id = ANY(SELECT public.user_org_ids()));

-- CORRECTION ccf_010 : "role" → "org_role"
DROP POLICY IF EXISTS "org_members_admin_insert" ON public.organization_members;
CREATE POLICY "org_members_admin_insert"
    ON public.organization_members FOR INSERT TO authenticated
    WITH CHECK (
        organization_id = ANY(
            SELECT organization_id FROM public.organization_members
            WHERE user_id = auth.uid() AND org_role = 'admin' AND status = 'active'
        )
        OR (
            user_id = auth.uid()
            AND org_role = 'admin'
            AND NOT EXISTS (
                SELECT 1 FROM public.organization_members
                WHERE organization_id = organization_members.organization_id
            )
        )
    );

-- CORRECTION ccf_010 : "role" → "org_role"
DROP POLICY IF EXISTS "org_members_admin_update" ON public.organization_members;
CREATE POLICY "org_members_admin_update"
    ON public.organization_members FOR UPDATE TO authenticated
    USING (
        organization_id = ANY(
            SELECT organization_id FROM public.organization_members
            WHERE user_id = auth.uid() AND org_role = 'admin' AND status = 'active'
        )
    )
    WITH CHECK (
        organization_id = ANY(
            SELECT organization_id FROM public.organization_members
            WHERE user_id = auth.uid() AND org_role = 'admin' AND status = 'active'
        )
    );

DROP POLICY IF EXISTS "org_members_superadmin_all" ON public.organization_members;
CREATE POLICY "org_members_superadmin_all"
    ON public.organization_members FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "capabilities_project_context_select" ON public.capabilities;
CREATE POLICY "capabilities_project_context_select"
    ON public.capabilities FOR SELECT TO authenticated
    USING (
        organization_id = ANY(SELECT public.user_org_ids())
        OR EXISTS (
            SELECT 1 FROM public.opportunity_capabilities oc
            JOIN public.opportunities o ON o.id = oc.opportunity_id
            WHERE oc.capability_id = capabilities.id
              AND o.coordinator_org_id = ANY(SELECT public.user_org_ids())
        )
    );

DROP POLICY IF EXISTS "opportunities_project_context_select" ON public.opportunities;
CREATE POLICY "opportunities_project_context_select"
    ON public.opportunities FOR SELECT TO authenticated
    USING (
        coordinator_org_id = ANY(SELECT public.user_org_ids())
        OR EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.opportunity_id = opportunities.id
              AND p.id = ANY(SELECT public.user_project_ids())
        )
    );

DROP POLICY IF EXISTS "ccf_projects_via_user_project_ids" ON public.ccf_projects;
CREATE POLICY "ccf_projects_via_user_project_ids"
    ON public.ccf_projects FOR SELECT TO authenticated
    USING (id = ANY(SELECT public.user_project_ids()));

DROP POLICY IF EXISTS "documents_via_project_ids" ON public.documents;
CREATE POLICY "documents_via_project_ids"
    ON public.documents FOR SELECT TO authenticated
    USING (
        visibility = 'project'
        AND object_type = 'project'
        AND object_id = ANY(SELECT public.user_project_ids())
    );

-- ════════════════════════════════════════════════════════════
-- CCF-011 — Validation du schéma CCF (version corrigée)
-- CORRECTION : ccf_project_phase retiré de la liste des ENUMs
--              (ce type est supprimé dans ccf_005 — RT-05)
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_missing_tables text[] := ARRAY[]::text[];
    v_missing_types  text[] := ARRAY[]::text[];
    v_table text;
    v_type  text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'profiles',
        'organizations',
        'organization_members',
        'mandates',
        'mandate_actions',
        'capabilities',
        'opportunities',
        'opportunity_capabilities',
        'ccf_projects',
        'project_participants',
        'documents',
        'logistics_steps',
        'value_reports',
        'ai_assistance_logs',
        'business_events',
        'audit_logs'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = v_table
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_table);
        END IF;
    END LOOP;

    -- NOTE : ccf_project_phase est intentionnellement absent de cette liste.
    -- Ce type a été supprimé dans ccf_005 (RT-05 : TEXT+CHECK par table).
    FOREACH v_type IN ARRAY ARRAY[
        'mandate_scope',
        'document_visibility',
        'logistics_step_type',
        'ccf_event_type',
        'org_role'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_type
            WHERE typname = v_type AND typnamespace = 'public'::regnamespace
        ) THEN
            v_missing_types := array_append(v_missing_types, v_type);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE WARNING 'Tables CCF manquantes : %', array_to_string(v_missing_tables, ', ');
    ELSE
        RAISE NOTICE 'Toutes les tables CCF sont présentes (16/16).';
    END IF;

    IF array_length(v_missing_types, 1) > 0 THEN
        RAISE WARNING 'Types ENUM CCF manquants : %', array_to_string(v_missing_types, ', ');
    ELSE
        RAISE NOTICE 'Tous les types ENUM CCF sont présents (5/5 — ccf_project_phase supprimé par RT-05).';
    END IF;

    RAISE NOTICE 'Schéma CCF validé. Seed de démonstration appliqué ci-dessous.';
END $$;

-- ════════════════════════════════════════════════════════════
-- SEED DE DÉMONSTRATION CCF
-- (contenu de supabase/seeds/demo_ccf.sql)
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_org_coordinateur  UUID := gen_random_uuid();
    v_org_manufacturier UUID := gen_random_uuid();
    v_org_recycleur     UUID := gen_random_uuid();
    v_cap_acier         UUID := gen_random_uuid();
    v_cap_aluminium     UUID := gen_random_uuid();
    v_cap_cuivre        UUID := gen_random_uuid();
    v_opportunite       UUID := gen_random_uuid();
    v_projet            UUID := gen_random_uuid();
    v_mandat_coord_manuf UUID := gen_random_uuid();
    v_mandat_coord_recyp UUID := gen_random_uuid();
    v_participant_manuf UUID := gen_random_uuid();
    v_participant_recyp UUID := gen_random_uuid();
    v_etape_ramassage   UUID := gen_random_uuid();
    v_etape_chargement  UUID := gen_random_uuid();
    v_etape_livraison   UUID := gen_random_uuid();
    v_rapport           UUID := gen_random_uuid();
    v_opp_cap_acier     UUID := gen_random_uuid();
    v_opp_cap_aluminium UUID := gen_random_uuid();
BEGIN
    INSERT INTO public.organizations (id, name, type, status, region, maturity_level, primary_contact_email)
    VALUES
        (v_org_coordinateur,  'Centre de Consolidation Ferroviaire Québec', 'coordinateur',  'active', 'Montréal-Métropolitain', 'avancé',        'coordination@ccf-quebec.ca'),
        (v_org_manufacturier, 'Acier Laurentien Inc.',                       'manufacturier', 'active', 'Laurentides',           'intermédiaire', 'operations@acier-laurentien.ca'),
        (v_org_recycleur,     'RecyclMétal Estrie',                          'recycleur',     'active', 'Estrie',                'débutant',      'info@recyclmetal-estrie.ca')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.capabilities (id, organization_id, material_type, monthly_volume, location, availability, maturity, status)
    VALUES
        (v_cap_acier,     v_org_manufacturier, 'acier_ferreux', 45.0, 'Saint-Jérôme, QC', 'mensuelle',     'qualifié', 'qualified'),
        (v_cap_aluminium, v_org_manufacturier, 'aluminium',     12.5, 'Saint-Jérôme, QC', 'trimestrielle', 'déclaré',  'declared'),
        (v_cap_cuivre,    v_org_recycleur,     'cuivre',         8.0, 'Sherbrooke, QC',   'mensuelle',     'qualifié', 'qualified')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.opportunities (id, title, description, coordinator_org_id, region, target_volume, priority, status)
    VALUES
        (v_opportunite,
         'Consolidation ferroviaire — Métaux ferreux et non-ferreux Q3 2026',
         'Opportunité de consolidation de chargements de métaux ferreux et non-ferreux pour expédition ferroviaire vers les fonderies de la région de Québec. Volume cible : 65 tonnes métriques. Corridor : Laurentides → Estrie → Québec.',
         v_org_coordinateur, 'Québec', 65.0, 'haute', 'qualified')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.opportunity_capabilities (id, opportunity_id, capability_id, fit_score, status)
    VALUES
        (v_opp_cap_acier,     v_opportunite, v_cap_acier,     92.0, 'active'),
        (v_opp_cap_aluminium, v_opportunite, v_cap_aluminium, 78.0, 'active')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.mandates (id, issuer_org_id, receiver_org_id, mandate_scope, permissions, status)
    VALUES
        (v_mandat_coord_manuf, v_org_coordinateur, v_org_manufacturier, 'operationnel',
         '{"actions": ["read_capabilities", "invite_project_org", "manage_project_participants", "submit_logistics_proof", "update_logistics_step"]}'::jsonb,
         'active'),
        (v_mandat_coord_recyp, v_org_coordinateur, v_org_recycleur, 'operationnel',
         '{"actions": ["read_capabilities", "accept_project_invitation", "submit_logistics_proof", "update_logistics_step"]}'::jsonb,
         'active')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id, phase, status, start_date, target_end_date)
    VALUES
        (v_projet, v_opportunite,
         'Projet CCF-2026-Q3 — Consolidation ferroviaire Laurentides-Estrie',
         v_org_coordinateur, 'execution', 'active',
         now() - INTERVAL '15 days', now() + INTERVAL '45 days')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.project_participants (id, project_id, organization_id, project_role, mandate_id, status)
    VALUES
        (v_participant_manuf, v_projet, v_org_manufacturier, 'contributeur', v_mandat_coord_manuf, 'active'),
        (v_participant_recyp, v_projet, v_org_recycleur,     'contributeur', v_mandat_coord_recyp, 'active')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.logistics_steps (id, project_id, step_type, responsible_org_id, planned_date, status)
    VALUES
        (v_etape_ramassage,  v_projet, 'ramassage',  v_org_manufacturier, now() - INTERVAL '10 days', 'completed'),
        (v_etape_chargement, v_projet, 'chargement', v_org_coordinateur,  now() - INTERVAL '5 days',  'completed'),
        (v_etape_livraison,  v_projet, 'livraison',  v_org_recycleur,     now() + INTERVAL '10 days', 'planned')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.value_reports (id, project_id, volume, coordination_value, notes, status)
    VALUES
        (v_rapport, v_projet, 57.5, 12800.00,
         'Rapport préliminaire de valeur créée. Volume consolidé : 57,5 t. Économies logistiques estimées : 12 800 $. Réduction GES estimée : 4,2 tCO2e vs transport routier individuel.',
         'draft')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.business_events (event_type, object_type, object_id, organization_id, payload)
    VALUES
        ('organization_created',    'organization',   v_org_coordinateur,  v_org_coordinateur,  jsonb_build_object('name', 'Centre de Consolidation Ferroviaire Québec', 'source', 'demo_seed')),
        ('organization_created',    'organization',   v_org_manufacturier, v_org_manufacturier, jsonb_build_object('name', 'Acier Laurentien Inc.', 'source', 'demo_seed')),
        ('organization_created',    'organization',   v_org_recycleur,     v_org_recycleur,     jsonb_build_object('name', 'RecyclMétal Estrie', 'source', 'demo_seed')),
        ('capability_qualified',    'capability',     v_cap_acier,         v_org_manufacturier, jsonb_build_object('material_type', 'acier_ferreux', 'monthly_volume', 45.0, 'source', 'demo_seed')),
        ('opportunity_qualified',   'opportunity',    v_opportunite,       v_org_coordinateur,  jsonb_build_object('title', 'Consolidation ferroviaire Q3 2026', 'source', 'demo_seed')),
        ('project_created',         'project',        v_projet,            v_org_coordinateur,  jsonb_build_object('title', 'Projet CCF-2026-Q3', 'source', 'demo_seed')),
        ('project_phase_changed',   'project',        v_projet,            v_org_coordinateur,  jsonb_build_object('from', 'active', 'to', 'execution', 'source', 'demo_seed')),
        ('mandate_issued',          'mandate',        v_mandat_coord_manuf, v_org_coordinateur, jsonb_build_object('receiver', 'Acier Laurentien Inc.', 'source', 'demo_seed')),
        ('mandate_accepted',        'mandate',        v_mandat_coord_manuf, v_org_manufacturier,jsonb_build_object('source', 'demo_seed')),
        ('logistics_step_updated',  'logistics_step', v_etape_ramassage,   v_org_manufacturier, jsonb_build_object('step_type', 'ramassage', 'new_status', 'completed', 'source', 'demo_seed')),
        ('value_report_generated',  'value_report',   v_rapport,           v_org_coordinateur,  jsonb_build_object('volume', 57.5, 'coordination_value', 12800.00, 'source', 'demo_seed'))
    ON CONFLICT DO NOTHING;

    RAISE NOTICE '✅ Reset + Réapplication CCF complète avec succès.';
    RAISE NOTICE '   Tables CCF créées : 16';
    RAISE NOTICE '   Organisations : 3 (coordinateur, manufacturier, recycleur)';
    RAISE NOTICE '   Capacités     : 3 (acier, aluminium, cuivre)';
    RAISE NOTICE '   Opportunité   : 1 (consolidation ferroviaire Q3 2026)';
    RAISE NOTICE '   Projet CCF    : 1 (CCF-2026-Q3, phase execution)';
    RAISE NOTICE '   Mandats       : 2';
    RAISE NOTICE '   Étapes log.   : 3 (ramassage ✓, chargement ✓, livraison planifiée)';
    RAISE NOTICE '   Rapport valeur: 1 (draft, 57.5t, 12 800$)';
    RAISE NOTICE '   Événements    : 11 événements métier de démonstration';
    RAISE NOTICE '';
    RAISE NOTICE 'Pour vérifier : SELECT table_name FROM information_schema.tables WHERE table_schema = ''public'' ORDER BY table_name;';

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Erreur lors du seed CCF : %', SQLERRM;
        RAISE;
END $$;
