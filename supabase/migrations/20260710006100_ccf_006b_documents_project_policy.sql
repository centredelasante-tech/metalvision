-- ============================================================
-- CCF-006b — Documents : policies complètes (project_participants + ccf_projects)
-- ============================================================
--
-- ORDRE D'EXÉCUTION :
--   Après  : 20260710005000_ccf_005_ccf_projects_participants.sql
--            (crée public.ccf_projects et public.project_participants)
--   Après  : 20260710006000_ccf_006_documents.sql
--            (crée la table documents et les policies partielles)
--
-- POURQUOI UNE MIGRATION SÉPARÉE :
--   ccf_006 référençait public.project_participants et public.ccf_projects
--   dans ses policies. Si ccf_005 n'était pas encore appliqué lors de
--   l'exécution de ccf_006, Postgres levait l'erreur 42P01.
--
--   ccf_006 a été corrigé pour ne contenir que des policies sans référence
--   à ces tables. La présente migration ccf_006b remplace ces policies par
--   leurs versions complètes, garantissant que ccf_projects et
--   project_participants existent déjà (ccf_005 > ccf_006 > ccf_006b).
--
-- CONTENU :
--   1. Remplacement de documents_project_select (version complète)
--      — owner_org_id OU participant actif du projet lié
--   2. Remplacement de documents_confidential_select (version complète)
--      — MVP-RA-027 : inclut la clause coordinateur de projet (ccf_projects)
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

-- ════════════════════════════════════════════════════════════
-- 2. POLICY documents_confidential_select — version complète
-- ════════════════════════════════════════════════════════════
-- MVP-RA-027 — Confidentialité restrictive.
-- Inclut la clause coordinateur de projet (public.ccf_projects),
-- qui ne pouvait pas être référencée dans ccf_006 (risque 42P01).
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "documents_confidential_select" ON public.documents;
CREATE POLICY "documents_confidential_select"
    ON public.documents
    FOR SELECT
    TO authenticated
    USING (
        visibility = 'confidential'
        AND (
            -- Le déposant (organisation propriétaire) voit toujours son propre document
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
                      AND (public.is_organization_member(m.issuer_org_id)
                           OR public.is_organization_member(m.receiver_org_id))
                )
            )
            -- 'organization' et 'capability' : couverts par la première clause (owner_org_id) seule.
            -- 'value_report' : couverture en attente — voir note ci-dessous.
        )
    );
