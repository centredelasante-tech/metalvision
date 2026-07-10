-- ============================================================
-- CCF-003 — Mandats et permissions
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   RT-07 : Validation de mandates.permissions.actions[] par trigger
--            contre la table de référence mandate_actions.
--            Pas de validation applicative seule.
--
-- CONTENU :
--   1. Table mandate_actions (catalogue fermé des 10 actions)
--   2. Table mandates
--   3. Trigger de validation des actions JSONB
--   4. Indexes
--   5. RLS
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. TABLE : mandate_actions (catalogue de référence fermé)
-- ════════════════════════════════════════════════════════════
-- Table de référence contenant le catalogue fermé des actions
-- autorisées dans mandates.permissions.actions[].
-- Toute nouvelle action doit être ajoutée ici avant d'être
-- utilisable dans une policy ou un écran.
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.mandate_actions (
    code        text PRIMARY KEY,
    label       text NOT NULL,
    description text,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed du catalogue fermé des 10 actions (Cahier fonctionnel v1.2 §4.2)
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

-- ════════════════════════════════════════════════════════════
-- 2. TABLE : mandates
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.mandates (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issuer_org_id    UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    receiver_org_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    mandate_scope    public.mandate_scope NOT NULL,
    permissions      jsonb NOT NULL,
    -- permissions.actions[] doit contenir uniquement des codes de mandate_actions
    -- Validé par le trigger validate_mandate_permissions_trigger (voir §3)
    status           text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'pending_acceptance', 'active', 'expired', 'revoked')),
    start_date       TIMESTAMPTZ,
    end_date         TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT mandates_different_orgs CHECK (issuer_org_id != receiver_org_id)
);

-- ════════════════════════════════════════════════════════════
-- 3. TRIGGER : validation des actions JSONB (RT-07)
-- ════════════════════════════════════════════════════════════
-- Valide que chaque élément du tableau permissions.actions[]
-- existe dans mandate_actions. Rejette l'insertion sinon.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.validate_mandate_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_action text;
    v_actions jsonb;
BEGIN
    -- Extraire le tableau d'actions
    v_actions := COALESCE(NEW.permissions -> 'actions', '[]'::jsonb);

    -- Vérifier que c'est bien un tableau
    IF jsonb_typeof(v_actions) != 'array' THEN
        RAISE EXCEPTION
            'mandates.permissions.actions doit être un tableau JSON (reçu: %)',
            jsonb_typeof(v_actions);
    END IF;

    -- Rejeter un tableau d'actions vide
    IF jsonb_array_length(v_actions) = 0 THEN
        RAISE EXCEPTION 'mandates.permissions.actions doit contenir au moins une action du catalogue mandate_actions.';
    END IF;

    -- Valider chaque action contre le catalogue fermé
    FOR v_action IN
        SELECT jsonb_array_elements_text(v_actions)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.mandate_actions WHERE code = v_action
        ) THEN
            RAISE EXCEPTION
                'Action de mandat invalide : "%" n''existe pas dans le catalogue mandate_actions. '
                'Actions autorisées : read_capabilities, propose_participation, invite_project_org, '
                'accept_project_invitation, manage_project_participants, approve_documents, '
                'submit_logistics_proof, update_logistics_step, generate_value_report, request_ai_summary',
                v_action;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_mandate_permissions_trigger ON public.mandates;
CREATE TRIGGER validate_mandate_permissions_trigger
    BEFORE INSERT OR UPDATE ON public.mandates
    FOR EACH ROW EXECUTE FUNCTION public.validate_mandate_permissions();

-- ════════════════════════════════════════════════════════════
-- 4. INDEXES
-- ════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_mandates_issuer_org   ON public.mandates (issuer_org_id);
CREATE INDEX IF NOT EXISTS idx_mandates_receiver_org ON public.mandates (receiver_org_id);
CREATE INDEX IF NOT EXISTS idx_mandates_status       ON public.mandates (status);

-- Index partiel pour les mandats actifs (optimise les policies RLS)
CREATE INDEX IF NOT EXISTS idx_mandates_active
    ON public.mandates (issuer_org_id, receiver_org_id)
    WHERE status = 'active';

-- ════════════════════════════════════════════════════════════
-- 5. RLS
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.mandates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mandate_actions ENABLE ROW LEVEL SECURITY;

-- mandate_actions : lecture publique pour les utilisateurs authentifiés
DROP POLICY IF EXISTS "mandate_actions_authenticated_select" ON public.mandate_actions;
CREATE POLICY "mandate_actions_authenticated_select"
    ON public.mandate_actions
    FOR SELECT
    TO authenticated
    USING (true);

-- mandates : SELECT — l'organisation émettrice ou réceptrice peut lire ses mandats
DROP POLICY IF EXISTS "mandates_org_select" ON public.mandates;
CREATE POLICY "mandates_org_select"
    ON public.mandates
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(issuer_org_id)
        OR public.is_organization_member(receiver_org_id)
    );

-- mandates : INSERT — seul un admin de l'organisation émettrice peut créer un mandat
DROP POLICY IF EXISTS "mandates_issuer_admin_insert" ON public.mandates;
CREATE POLICY "mandates_issuer_admin_insert"
    ON public.mandates
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_organization_owner(issuer_org_id));

-- mandates : UPDATE — admin émetteur (gestion) ou admin récepteur (acceptation/révocation)
DROP POLICY IF EXISTS "mandates_org_admin_update" ON public.mandates;
CREATE POLICY "mandates_org_admin_update"
    ON public.mandates
    FOR UPDATE
    TO authenticated
    USING (
        public.is_organization_owner(issuer_org_id)
        OR public.is_organization_owner(receiver_org_id)
    )
    WITH CHECK (
        public.is_organization_owner(issuer_org_id)
        OR public.is_organization_owner(receiver_org_id)
    );

-- mandates : super-admin plateforme — accès complet (sauf DELETE)
DROP POLICY IF EXISTS "mandates_superadmin_select" ON public.mandates;
CREATE POLICY "mandates_superadmin_select"
    ON public.mandates
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());
