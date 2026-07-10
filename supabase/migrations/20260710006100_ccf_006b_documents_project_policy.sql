-- ============================================================
-- CCF-006b — Policy documents_project_select
-- ============================================================
--
-- RAISON D'ÊTRE :
--   La policy "documents_project_select" référence public.project_participants,
--   table créée dans ccf_005 (timestamp 005000).
--
--   PostgreSQL valide les références de tables dans les corps de policies RLS
--   au moment du parsing de l'instruction CREATE POLICY — pas à l'exécution.
--   Si ccf_006 (timestamp 006000) tente de créer cette policy dans la même
--   transaction que la table documents, et que project_participants n'est pas
--   encore visible dans le search_path courant, PostgreSQL lève :
--     ERROR 42P01: relation "public.project_participants" does not exist
--
--   En isolant cette policy dans ccf_006b (timestamp 006100), on garantit
--   que project_participants est déjà présente dans le catalogue avant
--   que cette policy soit parsée et compilée.
--
-- DÉPENDANCES :
--   ccf_005 (project_participants) — doit être appliqué avant ce fichier
--   ccf_006 (documents table)      — doit être appliqué avant ce fichier
-- ============================================================

-- project : propriétaire OU participant actif du projet lié
-- MVP-RA-025 : un participant actif (project_participants) peut lire
-- les documents de portée projet attachés à son projet.
DROP POLICY IF EXISTS "documents_project_select" ON public.documents;
CREATE POLICY "documents_project_select"
    ON public.documents
    FOR SELECT
    TO authenticated
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
