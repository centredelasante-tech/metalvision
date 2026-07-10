-- ============================================================
-- CCF-006 — Documents (métadonnées et stockage)
-- ============================================================
--
-- CONTENU :
--   1. Table documents
--   2. Contrainte CHECK MVP-RA-026
--   3. Indexes
--   4. RLS (selon visibility : organization_private, project, confidential)
--
-- DÉPENDANCES :
--   ccf_001 (enums, document_visibility)
--   ccf_002 (organizations, is_organization_member, is_organization_owner)
--   ccf_003 (mandates)
--   ccf_004 (opportunities)
--   ccf_005 (ccf_projects, project_participants)
--   ccf_009 (is_platform_superadmin)
--
-- NOTE : La policy "documents_project_select" (qui référence project_participants)
--        est définie dans ccf_006b (20260710006100) pour garantir que la table
--        project_participants existe déjà au moment de la validation de la policy.
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. TABLE : documents
-- ════════════════════════════════════════════════════════════
-- Les documents sont des objets métier gouvernés, versionnés et classifiés.
-- object_type + object_id forment une référence polymorphique gouvernée.
-- visibility détermine qui peut lire le document (RLS §4).
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
-- 2. CONTRAINTE CHECK — MVP-RA-026
-- ════════════════════════════════════════════════════════════
-- Un document de visibility = 'project' doit obligatoirement avoir
-- object_type = 'project'. Garantit la cohérence sémantique de la
-- référence polymorphique pour les documents de portée projet.
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.documents
    DROP CONSTRAINT IF EXISTS documents_project_visibility_requires_project_object;

ALTER TABLE public.documents
    ADD CONSTRAINT documents_project_visibility_requires_project_object
    CHECK (
        visibility <> 'project'
        OR object_type = 'project'
    );

-- ════════════════════════════════════════════════════════════
-- 3. INDEXES
-- ════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_documents_owner_org    ON public.documents (owner_org_id);
CREATE INDEX IF NOT EXISTS idx_documents_object       ON public.documents (object_type, object_id);
CREATE INDEX IF NOT EXISTS idx_documents_visibility   ON public.documents (visibility);
CREATE INDEX IF NOT EXISTS idx_documents_status       ON public.documents (status);

-- ════════════════════════════════════════════════════════════
-- 4. RLS
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

-- NOTE : "documents_project_select" est défini dans ccf_006b
-- (20260710006100_ccf_006b_documents_project_policy.sql)
-- car il référence public.project_participants créée dans ccf_005.
-- PostgreSQL valide les références de tables dans les policies RLS
-- au moment du parsing — la policy doit donc être créée après
-- que la table project_participants existe dans la base.

-- confidential : MVP-RA-027 — accès restreint selon le contexte métier de l'objet
-- 5 branches :
--   1. owner_org_id     — déposant (toujours visible)
--   2. opportunity      — coordinateur de l'opportunité liée
--   3. project          — coordinateur du projet lié (ccf_projects)
--   4. value_report     — coordinateur du projet parent via value_reports → ccf_projects
--   5. mandate          — émetteur ou récepteur du mandat lié
DROP POLICY IF EXISTS "documents_confidential_select" ON public.documents;
CREATE POLICY "documents_confidential_select"
    ON public.documents
    FOR SELECT
    TO authenticated
    USING (
        visibility = 'confidential'
        AND (
            -- 1. Le déposant (organisation propriétaire) voit toujours son propre document
            public.is_organization_member(owner_org_id)

            -- 2. Coordinateur de l'opportunité liée
            OR (
                object_type = 'opportunity'
                AND EXISTS (
                    SELECT 1 FROM public.opportunities o
                    WHERE o.id = documents.object_id
                      AND public.is_organization_member(o.coordinator_org_id)
                )
            )

            -- 3. Coordinateur du projet lié (ccf_projects)
            OR (
                object_type = 'project'
                AND EXISTS (
                    SELECT 1 FROM public.ccf_projects p
                    WHERE p.id = documents.object_id
                      AND public.is_organization_member(p.coordinator_org_id)
                )
            )

            -- 4. Coordinateur du projet parent via value_reports → ccf_projects
            OR (
                object_type = 'value_report'
                AND EXISTS (
                    SELECT 1
                    FROM public.value_reports vr
                    JOIN public.ccf_projects p ON p.id = vr.project_id
                    WHERE vr.id = documents.object_id
                      AND public.is_organization_member(p.coordinator_org_id)
                )
            )

            -- 5. Émetteur ou récepteur du mandat lié
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

            -- 'organization' et 'capability' : couverts par la clause owner_org_id seule.
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

-- ── DELETE : absence volontaire — MVP-DA-006 ──────────────────
-- Aucune policy DELETE n'est définie sur public.documents.
-- La suppression physique d'un document est interdite par conception (MVP-DA-006).
-- Le cycle de vie est géré exclusivement via la colonne status
-- ('draft' → 'submitted' → 'approved' | 'rejected' → 'archived').
-- Toute tentative de DELETE sera rejetée par RLS (aucune policy = deny-all).

-- ── Super-admin : lecture complète ────────────────────────────
DROP POLICY IF EXISTS "documents_superadmin_select" ON public.documents;
CREATE POLICY "documents_superadmin_select"
    ON public.documents
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());
