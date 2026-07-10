-- ============================================================
-- CCF-010 — Policies RLS consolidées du domaine CCF
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   RT-04 : Toutes les policies CCF référencent public.user_org_ids()
--            et public.user_project_ids() — jamais is_company_member()
--            ni les fonctions du domaine Regroupements/MRV.
--
-- PRÉREQUIS : Migration 009 (fonctions RLS) doit être appliquée avant.
--
-- CONTENU :
--   Policies RLS supplémentaires et consolidées pour les tables CCF
--   qui nécessitent des règles basées sur user_org_ids() et
--   user_project_ids() (fonctions créées en migration 009).
--
-- NOTE : Les policies de base ont déjà été créées dans les migrations
--   002 à 008 (avec is_organization_member/owner). Cette migration
--   ajoute les policies qui dépendent des fonctions de migration 009.
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. POLICIES SUPPLÉMENTAIRES — organizations
-- ════════════════════════════════════════════════════════════

-- SELECT étendu : visible si l'org participe à un projet commun
DROP POLICY IF EXISTS "organizations_project_participant_select" ON public.organizations;
CREATE POLICY "organizations_project_participant_select"
    ON public.organizations
    FOR SELECT
    TO authenticated
    USING (
        -- Membre direct de l'organisation
        id = ANY(SELECT public.user_org_ids())
        OR
        -- Organisation participante à un projet commun
        EXISTS (
            SELECT 1 FROM public.project_participants pp
            WHERE pp.organization_id = organizations.id
              AND pp.project_id = ANY(SELECT public.user_project_ids())
              AND pp.status = 'active'
        )
        OR
        -- Organisation coordinatrice d'un projet accessible
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.coordinator_org_id = organizations.id
              AND p.id = ANY(SELECT public.user_project_ids())
        )
    );

-- INSERT : tout utilisateur authentifié peut créer une organisation
-- (le premier membre s'auto-insère comme admin via la policy organization_members)
DROP POLICY IF EXISTS "organizations_authenticated_insert" ON public.organizations;
CREATE POLICY "organizations_authenticated_insert"
    ON public.organizations
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- UPDATE : admin de l'organisation uniquement
DROP POLICY IF EXISTS "organizations_admin_update" ON public.organizations;
CREATE POLICY "organizations_admin_update"
    ON public.organizations
    FOR UPDATE
    TO authenticated
    USING (id = ANY(
        SELECT organization_id FROM public.organization_members
        WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    ))
    WITH CHECK (id = ANY(
        SELECT organization_id FROM public.organization_members
        WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
    ));

-- Super-admin : accès complet
DROP POLICY IF EXISTS "organizations_superadmin_all" ON public.organizations;
CREATE POLICY "organizations_superadmin_all"
    ON public.organizations
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- ════════════════════════════════════════════════════════════
-- 2. POLICIES SUPPLÉMENTAIRES — organization_members
-- ════════════════════════════════════════════════════════════

-- SELECT : membres de la même organisation
DROP POLICY IF EXISTS "org_members_same_org_select" ON public.organization_members;
CREATE POLICY "org_members_same_org_select"
    ON public.organization_members
    FOR SELECT
    TO authenticated
    USING (organization_id = ANY(SELECT public.user_org_ids()));

-- INSERT : admin de l'organisation OU auto-insertion du premier admin
DROP POLICY IF EXISTS "org_members_admin_insert" ON public.organization_members;
CREATE POLICY "org_members_admin_insert"
    ON public.organization_members
    FOR INSERT
    TO authenticated
    WITH CHECK (
        -- Admin existant peut ajouter des membres
        organization_id = ANY(
            SELECT organization_id FROM public.organization_members
            WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
        )
        OR
        -- Premier membre : auto-insertion comme admin
        (
            user_id = auth.uid()
            AND role = 'admin'
            AND NOT EXISTS (
                SELECT 1 FROM public.organization_members
                WHERE organization_id = organization_members.organization_id
            )
        )
    );

-- UPDATE : admin de l'organisation
DROP POLICY IF EXISTS "org_members_admin_update" ON public.organization_members;
CREATE POLICY "org_members_admin_update"
    ON public.organization_members
    FOR UPDATE
    TO authenticated
    USING (
        organization_id = ANY(
            SELECT organization_id FROM public.organization_members
            WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
        )
    )
    WITH CHECK (
        organization_id = ANY(
            SELECT organization_id FROM public.organization_members
            WHERE user_id = auth.uid() AND role = 'admin' AND status = 'active'
        )
    );

-- Super-admin : accès complet
DROP POLICY IF EXISTS "org_members_superadmin_all" ON public.organization_members;
CREATE POLICY "org_members_superadmin_all"
    ON public.organization_members
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- ════════════════════════════════════════════════════════════
-- 3. POLICIES SUPPLÉMENTAIRES — capabilities
-- ════════════════════════════════════════════════════════════

-- SELECT étendu : visible si liée à une opportunité ou un projet accessible
DROP POLICY IF EXISTS "capabilities_project_context_select" ON public.capabilities;
CREATE POLICY "capabilities_project_context_select"
    ON public.capabilities
    FOR SELECT
    TO authenticated
    USING (
        -- Propriétaire direct
        organization_id = ANY(SELECT public.user_org_ids())
        OR
        -- Liée à une opportunité d'un projet accessible
        EXISTS (
            SELECT 1 FROM public.opportunity_capabilities oc
            JOIN public.opportunities o ON o.id = oc.opportunity_id
            WHERE oc.capability_id = capabilities.id
              AND o.coordinator_org_id = ANY(SELECT public.user_org_ids())
        )
    );

-- ════════════════════════════════════════════════════════════
-- 4. POLICIES SUPPLÉMENTAIRES — opportunities
-- ════════════════════════════════════════════════════════════

-- SELECT étendu : visible si liée à un projet accessible
DROP POLICY IF EXISTS "opportunities_project_context_select" ON public.opportunities;
CREATE POLICY "opportunities_project_context_select"
    ON public.opportunities
    FOR SELECT
    TO authenticated
    USING (
        -- Coordinateur direct
        coordinator_org_id = ANY(SELECT public.user_org_ids())
        OR
        -- Liée à un projet accessible
        EXISTS (
            SELECT 1 FROM public.ccf_projects p
            WHERE p.opportunity_id = opportunities.id
              AND p.id = ANY(SELECT public.user_project_ids())
        )
    );

-- ════════════════════════════════════════════════════════════
-- 5. POLICIES SUPPLÉMENTAIRES — ccf_projects
-- ════════════════════════════════════════════════════════════

-- SELECT via user_project_ids() (complément des policies de migration 005)
DROP POLICY IF EXISTS "ccf_projects_via_user_project_ids" ON public.ccf_projects;
CREATE POLICY "ccf_projects_via_user_project_ids"
    ON public.ccf_projects
    FOR SELECT
    TO authenticated
    USING (id = ANY(SELECT public.user_project_ids()));

-- ════════════════════════════════════════════════════════════
-- 6. POLICIES SUPPLÉMENTAIRES — documents
-- ════════════════════════════════════════════════════════════

-- SELECT via user_project_ids() pour les documents de visibilité 'project'
DROP POLICY IF EXISTS "documents_via_project_ids" ON public.documents;
CREATE POLICY "documents_via_project_ids"
    ON public.documents
    FOR SELECT
    TO authenticated
    USING (
        visibility = 'project'
        AND object_type = 'project'
        AND object_id = ANY(SELECT public.user_project_ids())
    );

-- ════════════════════════════════════════════════════════════
-- 7. RÉSUMÉ DES TESTS RLS OBLIGATOIRES (§6.3 Backlog v1.0)
-- ════════════════════════════════════════════════════════════
-- RLS-001 : Org A ne peut pas lire les capacités privées de Org B
--           sans projet commun.
-- RLS-002 : Un admin d'org ne peut pas accéder à un projet sans
--           ligne project_participants.
-- RLS-003 : Tous les participants actifs peuvent lire un document
--           de visibilité 'project'.
-- RLS-004 : Seuls le déposant et le coordinateur peuvent lire un
--           document 'confidential'.
-- RLS-005 : Seuls responsible_org_id ou le coordinateur peuvent
--           modifier une étape logistique.
-- RLS-006 : L'agent IA ne peut résumer qu'un document déjà
--           accessible à l'utilisateur.
-- RLS-007 : Aucun flux UI n'utilise le service role côté client.
