-- ============================================================
-- CCF-006 — Documents (métadonnées et stockage)
-- ============================================================
--
-- CONTENU :
--   1. Table documents
--   2. Indexes
--   3. RLS (selon visibility : organization_private, project, confidential)
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. TABLE : documents
-- ════════════════════════════════════════════════════════════
-- Les documents sont des objets métier gouvernés, versionnés et classifiés.
-- object_type + object_id forment une référence polymorphique gouvernée.
-- visibility détermine qui peut lire le document (RLS §3).
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.documents (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_org_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    object_type   text NOT NULL
        CHECK (object_type IN (
            'organization',
            'capability',
            'opportunity',
            'project',
            'mandate',
            'value_report'
        )),
    object_id     UUID NOT NULL,
    -- object_id est une référence polymorphique — la table cible est déterminée par object_type
    title         text NOT NULL,
    category      text,
    version       text NOT NULL DEFAULT '1.0',
    visibility    public.document_visibility NOT NULL DEFAULT 'organization_private',
    storage_path  text,
    -- storage_path : chemin dans le bucket Supabase Storage
    status        text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'submitted', 'approved', 'rejected', 'archived')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ════════════════════════════════════════════════════════════
-- 2. INDEXES
-- ════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_documents_owner_org    ON public.documents (owner_org_id);
CREATE INDEX IF NOT EXISTS idx_documents_object       ON public.documents (object_type, object_id);
CREATE INDEX IF NOT EXISTS idx_documents_visibility   ON public.documents (visibility);
CREATE INDEX IF NOT EXISTS idx_documents_status       ON public.documents (status);

-- ════════════════════════════════════════════════════════════
-- 3. RLS
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

-- ── SELECT selon visibility ───────────────────────────────────

-- organization_private : seuls les membres de l'organisation propriétaire
DROP POLICY IF EXISTS "documents_org_private_select" ON public.documents;
CREATE POLICY "documents_org_private_select"
    ON public.documents
    FOR SELECT
    TO authenticated
    USING (
        visibility = 'organization_private'
        AND public.is_organization_member(owner_org_id)
    );

-- project : tous les participants actifs du projet lié
DROP POLICY IF EXISTS "documents_project_select" ON public.documents;
CREATE POLICY "documents_project_select"
    ON public.documents
    FOR SELECT
    TO authenticated
    USING (
        visibility = 'project'
        AND (
            -- Membre de l'organisation propriétaire
            public.is_organization_member(owner_org_id)
            OR
            -- Participant actif au projet lié (via object_type = 'project')
            (
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

-- confidential : seuls le déposant (org propriétaire) et le coordinateur du projet
DROP POLICY IF EXISTS "documents_confidential_select" ON public.documents;
CREATE POLICY "documents_confidential_select"
    ON public.documents
    FOR SELECT
    TO authenticated
    USING (
        visibility = 'confidential'
        AND (
            -- Membre de l'organisation propriétaire (déposant)
            public.is_organization_member(owner_org_id)
            OR
            -- Admin de l'organisation coordinatrice du projet lié
            (
                object_type = 'project'
                AND EXISTS (
                    SELECT 1 FROM public.ccf_projects p
                    WHERE p.id = documents.object_id
                      AND public.is_organization_member(p.coordinator_org_id)
                )
            )
        )
    );

-- ── INSERT : admin de l'organisation propriétaire ─────────────
DROP POLICY IF EXISTS "documents_owner_admin_insert" ON public.documents;
CREATE POLICY "documents_owner_admin_insert"
    ON public.documents
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_organization_owner(owner_org_id));

-- ── UPDATE : admin de l'organisation propriétaire ─────────────
DROP POLICY IF EXISTS "documents_owner_admin_update" ON public.documents;
CREATE POLICY "documents_owner_admin_update"
    ON public.documents
    FOR UPDATE
    TO authenticated
    USING (public.is_organization_owner(owner_org_id))
    WITH CHECK (public.is_organization_owner(owner_org_id));

-- ── Super-admin : lecture complète ────────────────────────────
DROP POLICY IF EXISTS "documents_superadmin_select" ON public.documents;
CREATE POLICY "documents_superadmin_select"
    ON public.documents
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());
