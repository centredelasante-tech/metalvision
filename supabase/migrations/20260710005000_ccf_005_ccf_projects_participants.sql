-- ============================================================
-- CCF-005 — Projets CCF et Participants
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   RT-01/RT-02 : La table "projects" existante (domaine MRV ISO 14064)
--                 et son ENUM "project_status" ne sont PAS touchés.
--                 Le domaine collaboratif utilise la table "ccf_projects"
--                 avec ses propres colonnes status (TEXT+CHECK) et phase (TEXT+CHECK).
--   RT-05 : Aucun ENUM Postgres partagé pour les statuts/phases.
--            ccf_projects.phase était explicitement nommé dans la liste
--            des champs à traiter en TEXT + CHECK (décision 4).
--            L'ENUM public.ccf_project_phase est supprimé.
--
-- CONTENU :
--   1. Suppression de l'ENUM public.ccf_project_phase (si présent depuis ccf_001)
--   2. Table ccf_projects (phase en TEXT+CHECK, pas ENUM)
--   3. Table project_participants
--   4. Indexes
--   5. RLS
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. Suppression de l'ENUM public.ccf_project_phase
-- Conformément à la décision RT-05 : TEXT + CHECK par table,
-- aucun ENUM Postgres partagé pour les statuts/phases.
-- ccf_projects.phase est implémenté en TEXT + CHECK ci-dessous.
-- ════════════════════════════════════════════════════════════

DROP TYPE IF EXISTS public.ccf_project_phase CASCADE;

-- ════════════════════════════════════════════════════════════
-- 2. TABLE : ccf_projects
-- ════════════════════════════════════════════════════════════
-- Projet collaboratif CCF (Centre de Consolidation Ferroviaire).
-- Distinct de la table "projects" du domaine MRV ISO 14064.
-- Transforme une opportunité qualifiée en exécution coordonnée.
-- phase et status sont tous deux TEXT + CHECK (décision RT-05).
-- ════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════
-- 3. TABLE : project_participants
-- ════════════════════════════════════════════════════════════
-- Relie les organisations aux projets CCF avec un rôle contextuel.
-- Aucun droit de projet sans une ligne project_participants active.
-- Le mandate_id lie la participation à un mandat explicite.
-- ════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════
-- 4. INDEXES
-- ════════════════════════════════════════════════════════════

-- ccf_projects
CREATE INDEX IF NOT EXISTS idx_ccf_projects_coordinator ON public.ccf_projects (coordinator_org_id);
CREATE INDEX IF NOT EXISTS idx_ccf_projects_opportunity ON public.ccf_projects (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_ccf_projects_status      ON public.ccf_projects (status);
CREATE INDEX IF NOT EXISTS idx_ccf_projects_phase       ON public.ccf_projects (phase);

-- project_participants
CREATE INDEX IF NOT EXISTS idx_project_participants_project ON public.project_participants (project_id);
CREATE INDEX IF NOT EXISTS idx_project_participants_org     ON public.project_participants (organization_id);
CREATE INDEX IF NOT EXISTS idx_project_participants_status  ON public.project_participants (status);

-- Index partiel pour les participants actifs (optimise les policies RLS)
CREATE INDEX IF NOT EXISTS idx_project_participants_active
    ON public.project_participants (project_id, organization_id)
    WHERE status = 'active';

-- ════════════════════════════════════════════════════════════
-- 5. RLS
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.ccf_projects        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_participants ENABLE ROW LEVEL SECURITY;

-- ── ccf_projects ──────────────────────────────────────────────

-- SELECT : coordinateur ou participant actif du projet
DROP POLICY IF EXISTS "ccf_projects_participant_select" ON public.ccf_projects;
CREATE POLICY "ccf_projects_participant_select"
    ON public.ccf_projects
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(coordinator_org_id)
        OR
        EXISTS (
            SELECT 1 FROM public.project_participants pp
            WHERE pp.project_id = ccf_projects.id
              AND public.is_organization_member(pp.organization_id)
              AND pp.status = 'active'
        )
    );

-- INSERT : seul un admin de l'organisation coordinatrice peut créer un projet
DROP POLICY IF EXISTS "ccf_projects_coordinator_admin_insert" ON public.ccf_projects;
CREATE POLICY "ccf_projects_coordinator_admin_insert"
    ON public.ccf_projects
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_organization_owner(coordinator_org_id));

-- UPDATE : seul un admin de l'organisation coordinatrice peut modifier
DROP POLICY IF EXISTS "ccf_projects_coordinator_admin_update" ON public.ccf_projects;
CREATE POLICY "ccf_projects_coordinator_admin_update"
    ON public.ccf_projects
    FOR UPDATE
    TO authenticated
    USING (public.is_organization_owner(coordinator_org_id))
    WITH CHECK (public.is_organization_owner(coordinator_org_id));

-- Super-admin : lecture complète
DROP POLICY IF EXISTS "ccf_projects_superadmin_select" ON public.ccf_projects;
CREATE POLICY "ccf_projects_superadmin_select"
    ON public.ccf_projects
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());

-- ── project_participants ──────────────────────────────────────

-- SELECT : coordinateur du projet ou membre de l'organisation participante
DROP POLICY IF EXISTS "project_participants_select" ON public.project_participants;
CREATE POLICY "project_participants_select"
    ON public.project_participants
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_member(p.coordinator_org_id)
        )
        OR public.is_organization_member(organization_id)
    );

-- INSERT : admin de l'organisation coordinatrice du projet
DROP POLICY IF EXISTS "project_participants_coordinator_insert" ON public.project_participants;
CREATE POLICY "project_participants_coordinator_insert"
    ON public.project_participants
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.id = project_id
              AND public.is_organization_owner(p.coordinator_org_id)
        )
    );

-- UPDATE : coordinateur (gestion) ou admin de l'org invitée (acceptation de son propre statut)
DROP POLICY IF EXISTS "project_participants_update" ON public.project_participants;
CREATE POLICY "project_participants_update"
    ON public.project_participants
    FOR UPDATE
    TO authenticated
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
