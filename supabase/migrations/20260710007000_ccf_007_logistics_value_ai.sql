-- ============================================================
-- CCF-007 — Étapes logistiques, Rapports de valeur, Logs IA
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   Ordre inversé (RT — décision 7) : logistics_steps et value_reports
--   sont créés AVANT business_events et audit_logs (migration 008),
--   car business_events.object_type référence des cibles qui doivent
--   déjà exister au moment de la création de la table.
--
-- CONTENU :
--   1. Table logistics_steps
--   2. Table value_reports
--   3. Table ai_assistance_logs
--   4. Indexes
--   5. RLS
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. TABLE : logistics_steps
-- ════════════════════════════════════════════════════════════
-- Étapes logistiques d'un projet CCF.
-- responsible_org_id désigne l'organisation qui doit reporter l'étape.
-- Seule elle (ou le coordinateur) peut la modifier.
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

-- ════════════════════════════════════════════════════════════
-- 2. TABLE : value_reports
-- ════════════════════════════════════════════════════════════
-- Rapport de valeur créée pour un projet CCF.
-- generated_by référence profiles.id (MVP-DA-010 — jamais auth.users).
-- ════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════
-- 3. TABLE : ai_assistance_logs
-- ════════════════════════════════════════════════════════════
-- Journal des interactions avec l'agent IA.
-- L'agent IA utilise toujours le JWT de l'utilisateur appelant.
-- user_id référence profiles.id (MVP-DA-010).
-- ════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════
-- 4. INDEXES
-- ════════════════════════════════════════════════════════════

-- logistics_steps
CREATE INDEX IF NOT EXISTS idx_logistics_steps_project     ON public.logistics_steps (project_id);
CREATE INDEX IF NOT EXISTS idx_logistics_steps_responsible ON public.logistics_steps (responsible_org_id);
CREATE INDEX IF NOT EXISTS idx_logistics_steps_status      ON public.logistics_steps (status);

-- value_reports
CREATE INDEX IF NOT EXISTS idx_value_reports_project      ON public.value_reports (project_id);
CREATE INDEX IF NOT EXISTS idx_value_reports_generated_by ON public.value_reports (generated_by);
CREATE INDEX IF NOT EXISTS idx_value_reports_status       ON public.value_reports (status);

-- ai_assistance_logs
CREATE INDEX IF NOT EXISTS idx_ai_logs_user_id     ON public.ai_assistance_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_object      ON public.ai_assistance_logs (object_type, object_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_created_at  ON public.ai_assistance_logs (created_at DESC);

-- ════════════════════════════════════════════════════════════
-- 5. RLS
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.logistics_steps   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.value_reports     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_assistance_logs ENABLE ROW LEVEL SECURITY;

-- ── logistics_steps ───────────────────────────────────────────

-- SELECT : coordinateur du projet ou membre de l'org responsable
-- Condition additionnelle (RT-04 §3) : un membre "bureau" sans mandat
-- spécifique ne peut pas modifier une étape logistique même s'il
-- appartient à l'organisation responsable.
DROP POLICY IF EXISTS "logistics_steps_select" ON public.logistics_steps;
CREATE POLICY "logistics_steps_select"
    ON public.logistics_steps
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_member(p.coordinator_org_id)
        )
        OR public.is_organization_member(responsible_org_id)
    );

-- UPDATE : coordinateur du projet OU membre de l'org responsable
-- avec org_role = 'admin' OU operational_profile = 'terrain'
-- (un membre "bureau" sans mandat spécifique ne peut pas modifier)
DROP POLICY IF EXISTS "logistics_steps_update" ON public.logistics_steps;
CREATE POLICY "logistics_steps_update"
    ON public.logistics_steps
    FOR UPDATE
    TO authenticated
    USING (
        -- Coordinateur du projet (admin)
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
        OR
        -- Membre de l'org responsable avec rôle admin OU profil terrain
        EXISTS (
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
        OR
        EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = responsible_org_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
              AND (om.org_role = 'admin' OR om.operational_profile = 'terrain')
        )
    );

-- INSERT : coordinateur du projet
DROP POLICY IF EXISTS "logistics_steps_coordinator_insert" ON public.logistics_steps;
CREATE POLICY "logistics_steps_coordinator_insert"
    ON public.logistics_steps
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
    );

-- Super-admin : lecture complète
DROP POLICY IF EXISTS "logistics_steps_superadmin_select" ON public.logistics_steps;
CREATE POLICY "logistics_steps_superadmin_select"
    ON public.logistics_steps
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());

-- ── value_reports ─────────────────────────────────────────────

-- SELECT : participants actifs du projet
DROP POLICY IF EXISTS "value_reports_participant_select" ON public.value_reports;
CREATE POLICY "value_reports_participant_select"
    ON public.value_reports
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_member(p.coordinator_org_id)
        )
        OR
        EXISTS (
            SELECT 1 FROM public.project_participants pp
            WHERE pp.project_id = value_reports.project_id
              AND public.is_organization_member(pp.organization_id)
              AND pp.status = 'active'
        )
    );

-- INSERT : admin de l'organisation coordinatrice
DROP POLICY IF EXISTS "value_reports_coordinator_insert" ON public.value_reports;
CREATE POLICY "value_reports_coordinator_insert"
    ON public.value_reports
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
    );

-- UPDATE : admin de l'organisation coordinatrice
DROP POLICY IF EXISTS "value_reports_coordinator_update" ON public.value_reports;
CREATE POLICY "value_reports_coordinator_update"
    ON public.value_reports
    FOR UPDATE
    TO authenticated
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

-- ── ai_assistance_logs ────────────────────────────────────────

-- SELECT : l'utilisateur peut lire ses propres logs IA
DROP POLICY IF EXISTS "ai_logs_self_select" ON public.ai_assistance_logs;
CREATE POLICY "ai_logs_self_select"
    ON public.ai_assistance_logs
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- INSERT : l'utilisateur peut créer ses propres logs IA
DROP POLICY IF EXISTS "ai_logs_self_insert" ON public.ai_assistance_logs;
CREATE POLICY "ai_logs_self_insert"
    ON public.ai_assistance_logs
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- Super-admin : lecture complète
DROP POLICY IF EXISTS "ai_logs_superadmin_select" ON public.ai_assistance_logs;
CREATE POLICY "ai_logs_superadmin_select"
    ON public.ai_assistance_logs
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());
