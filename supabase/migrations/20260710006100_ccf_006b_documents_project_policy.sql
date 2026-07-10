-- ============================================================
-- CCF-006b — Documents : policy documents_project_select complète
-- ============================================================
--
-- ORDRE D'EXÉCUTION :
--   Après  : 20260710005000_ccf_005_ccf_projects_participants.sql
--            (crée public.project_participants)
--   Après  : 20260710006000_ccf_006_documents.sql
--            (crée la table documents et la policy partielle)
--
-- POURQUOI UNE MIGRATION SÉPARÉE :
--   ccf_006 référençait public.project_participants dans la policy
--   documents_project_select. Si ccf_005 n'était pas encore appliqué
--   lors de l'exécution de ccf_006, Postgres levait l'erreur 42P01
--   (relation "public.project_participants" does not exist).
--
--   ccf_006 a été corrigé pour ne contenir qu'une policy minimale
--   (owner_org_id uniquement). La présente migration ccf_006b remplace
--   cette policy par la version complète, garantissant que
--   project_participants existe déjà (ccf_005 > ccf_006 > ccf_006b).
--
-- CONTENU :
--   1. Remplacement de documents_project_select (version complète)
--      — owner_org_id OU participant actif du projet lié
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. POLICY documents_project_select — version complète
-- ════════════════════════════════════════════════════════════
-- project : visible au propriétaire ET à tous les participants actifs
-- du projet lié (object_type = 'project' via project_participants).
-- ════════════════════════════════════════════════════════════

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
