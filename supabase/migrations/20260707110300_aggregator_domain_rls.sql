-- ============================================================
-- MT-000A (CORRIGÉ) — Migration 20260707110300
-- RLS Policies — Domaine Regroupements
-- ============================================================
--
-- PRINCIPES D'ARCHITECTURE (non négociables) :
--   1. is_platform_superadmin() = accès exceptionnel (role='admin' UNIQUEMENT)
--      project_admin n'obtient AUCUN droit implicite sur les regroupements.
--   2. is_aggregator_admin(UUID) = source de vérité des admins de regroupement
--      Basé exclusivement sur aggregator_admins (revoked_at IS NULL).
--   3. Aucune policy ne référence is_project_admin() ou is_platform_admin()
--      dans ce domaine.
--   4. Séparation stricte : rôles de regroupement ≠ rôles d'organisation.
--      Un owner d'entreprise n'est jamais automatiquement admin d'un regroupement.
--
-- TABLES COUVERTES :
--   aggregators, aggregator_admins, credit_sales, credit_sale_lots,
--   credit_lots, distribution_rules, member_distribution_overrides,
--   credit_sale_allocations, operational_units
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- TABLE : aggregators
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.aggregators ENABLE ROW LEVEL SECURITY;

-- Superadmin : accès complet (CRUD)
DROP POLICY IF EXISTS "aggregators_superadmin_all" ON public.aggregators;
CREATE POLICY "aggregators_superadmin_all"
    ON public.aggregators
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Admin de regroupement : lecture de son regroupement
DROP POLICY IF EXISTS "aggregators_admin_select" ON public.aggregators;
CREATE POLICY "aggregators_admin_select"
    ON public.aggregators
    FOR SELECT
    TO authenticated
    USING (public.is_aggregator_admin(id));

-- Membre d'une entreprise affiliée : lecture du regroupement de son entreprise
DROP POLICY IF EXISTS "aggregators_member_select" ON public.aggregators;
CREATE POLICY "aggregators_member_select"
    ON public.aggregators
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.companies c
            WHERE c.aggregator_id = aggregators.id
              AND public.is_company_member(c.id)
        )
    );

-- ════════════════════════════════════════════════════════════
-- TABLE : aggregator_admins
-- ════════════════════════════════════════════════════════════

-- RLS déjà activé dans la migration 110200

-- Superadmin : accès complet (CRUD + historique)
DROP POLICY IF EXISTS "aggregator_admins_superadmin_all" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_superadmin_all"
    ON public.aggregator_admins
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Admin de regroupement : lecture des admins de son regroupement
DROP POLICY IF EXISTS "aggregator_admins_admin_select" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_select"
    ON public.aggregator_admins
    FOR SELECT
    TO authenticated
    USING (public.is_aggregator_admin(aggregator_id));

-- Admin de regroupement : nomination d'un co-admin dans son regroupement
DROP POLICY IF EXISTS "aggregator_admins_admin_insert" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_insert"
    ON public.aggregator_admins
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

-- Admin de regroupement : révocation (UPDATE revoked_at) dans son regroupement
-- La suppression physique est interdite — seul UPDATE est autorisé pour révoquer.
DROP POLICY IF EXISTS "aggregator_admins_admin_update" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_update"
    ON public.aggregator_admins
    FOR UPDATE
    TO authenticated
    USING (public.is_aggregator_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

-- Utilisateur : lecture de son propre enregistrement (actif ou révoqué)
DROP POLICY IF EXISTS "aggregator_admins_self_select" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_self_select"
    ON public.aggregator_admins
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- ════════════════════════════════════════════════════════════
-- TABLE : credit_sales
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.credit_sales ENABLE ROW LEVEL SECURITY;

-- Superadmin : accès complet
DROP POLICY IF EXISTS "credit_sales_superadmin_all" ON public.credit_sales;
CREATE POLICY "credit_sales_superadmin_all"
    ON public.credit_sales
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Admin de regroupement : accès complet à ses ventes de crédits
DROP POLICY IF EXISTS "credit_sales_admin_all" ON public.credit_sales;
CREATE POLICY "credit_sales_admin_all"
    ON public.credit_sales
    FOR ALL
    TO authenticated
    USING (public.is_aggregator_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

-- Membre d'une entreprise affiliée : lecture des ventes de son regroupement
DROP POLICY IF EXISTS "credit_sales_member_select" ON public.credit_sales;
CREATE POLICY "credit_sales_member_select"
    ON public.credit_sales
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.companies c
            WHERE c.aggregator_id = credit_sales.aggregator_id
              AND public.is_company_member(c.id)
        )
    );

-- ════════════════════════════════════════════════════════════
-- TABLE : credit_sale_lots
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.credit_sale_lots ENABLE ROW LEVEL SECURITY;

-- Superadmin : accès complet
DROP POLICY IF EXISTS "credit_sale_lots_superadmin_all" ON public.credit_sale_lots;
CREATE POLICY "credit_sale_lots_superadmin_all"
    ON public.credit_sale_lots
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Admin de regroupement : accès complet via la vente de crédits associée
DROP POLICY IF EXISTS "credit_sale_lots_admin_all" ON public.credit_sale_lots;
CREATE POLICY "credit_sale_lots_admin_all"
    ON public.credit_sale_lots
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.credit_sales cs
            WHERE cs.id = credit_sale_lots.credit_sale_id
              AND public.is_aggregator_admin(cs.aggregator_id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.credit_sales cs
            WHERE cs.id = credit_sale_lots.credit_sale_id
              AND public.is_aggregator_admin(cs.aggregator_id)
        )
    );

-- Membre d'une entreprise affiliée : lecture via la vente de crédits
DROP POLICY IF EXISTS "credit_sale_lots_member_select" ON public.credit_sale_lots;
CREATE POLICY "credit_sale_lots_member_select"
    ON public.credit_sale_lots
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.credit_sales cs
            JOIN public.companies c ON c.aggregator_id = cs.aggregator_id
            WHERE cs.id = credit_sale_lots.credit_sale_id
              AND public.is_company_member(c.id)
        )
    );

-- ════════════════════════════════════════════════════════════
-- TABLE : credit_lots
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.credit_lots ENABLE ROW LEVEL SECURITY;

-- Superadmin : accès complet
DROP POLICY IF EXISTS "credit_lots_superadmin_all" ON public.credit_lots;
CREATE POLICY "credit_lots_superadmin_all"
    ON public.credit_lots
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Admin de regroupement : accès complet via le projet associé
DROP POLICY IF EXISTS "credit_lots_admin_all" ON public.credit_lots;
CREATE POLICY "credit_lots_admin_all"
    ON public.credit_lots
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.projects p
            JOIN public.operational_units ou ON ou.id = p.operational_unit_id
            JOIN public.companies c ON c.id = ou.company_id
            JOIN public.aggregators agg ON agg.id = c.aggregator_id
            WHERE p.id = credit_lots.project_id
              AND public.is_aggregator_admin(agg.id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.projects p
            JOIN public.operational_units ou ON ou.id = p.operational_unit_id
            JOIN public.companies c ON c.id = ou.company_id
            JOIN public.aggregators agg ON agg.id = c.aggregator_id
            WHERE p.id = credit_lots.project_id
              AND public.is_aggregator_admin(agg.id)
        )
    );

-- Membre d'une entreprise : lecture des lots de crédits de ses projets
DROP POLICY IF EXISTS "credit_lots_member_select" ON public.credit_lots;
CREATE POLICY "credit_lots_member_select"
    ON public.credit_lots
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.projects p
            JOIN public.operational_units ou ON ou.id = p.operational_unit_id
            WHERE p.id = credit_lots.project_id
              AND public.is_company_member(ou.company_id)
        )
    );

-- ════════════════════════════════════════════════════════════
-- TABLE : distribution_rules
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.distribution_rules ENABLE ROW LEVEL SECURITY;

-- Superadmin : accès complet
DROP POLICY IF EXISTS "distribution_rules_superadmin_all" ON public.distribution_rules;
CREATE POLICY "distribution_rules_superadmin_all"
    ON public.distribution_rules
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Admin de regroupement : accès complet aux règles de son regroupement
DROP POLICY IF EXISTS "distribution_rules_admin_all" ON public.distribution_rules;
CREATE POLICY "distribution_rules_admin_all"
    ON public.distribution_rules
    FOR ALL
    TO authenticated
    USING (public.is_aggregator_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

-- Membre d'une entreprise affiliée : lecture des règles de son regroupement
DROP POLICY IF EXISTS "distribution_rules_member_select" ON public.distribution_rules;
CREATE POLICY "distribution_rules_member_select"
    ON public.distribution_rules
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.companies c
            WHERE c.aggregator_id = distribution_rules.aggregator_id
              AND public.is_company_member(c.id)
        )
    );

-- ════════════════════════════════════════════════════════════
-- TABLE : member_distribution_overrides
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.member_distribution_overrides ENABLE ROW LEVEL SECURITY;

-- Superadmin : accès complet
DROP POLICY IF EXISTS "mdo_superadmin_all" ON public.member_distribution_overrides;
CREATE POLICY "mdo_superadmin_all"
    ON public.member_distribution_overrides
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Admin de regroupement : accès complet aux overrides de son regroupement
DROP POLICY IF EXISTS "mdo_admin_all" ON public.member_distribution_overrides;
CREATE POLICY "mdo_admin_all"
    ON public.member_distribution_overrides
    FOR ALL
    TO authenticated
    USING (public.is_aggregator_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

-- Membre d'une entreprise : lecture de ses propres overrides
DROP POLICY IF EXISTS "mdo_member_select_own" ON public.member_distribution_overrides;
CREATE POLICY "mdo_member_select_own"
    ON public.member_distribution_overrides
    FOR SELECT
    TO authenticated
    USING (public.is_company_member(company_id));

-- ════════════════════════════════════════════════════════════
-- TABLE : credit_sale_allocations
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.credit_sale_allocations ENABLE ROW LEVEL SECURITY;

-- Superadmin : accès complet
DROP POLICY IF EXISTS "csa_superadmin_all" ON public.credit_sale_allocations;
CREATE POLICY "csa_superadmin_all"
    ON public.credit_sale_allocations
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Admin de regroupement : accès complet via la vente de crédits associée
DROP POLICY IF EXISTS "csa_admin_all" ON public.credit_sale_allocations;
CREATE POLICY "csa_admin_all"
    ON public.credit_sale_allocations
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.credit_sales cs
            WHERE cs.id = credit_sale_allocations.credit_sale_id
              AND public.is_aggregator_admin(cs.aggregator_id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.credit_sales cs
            WHERE cs.id = credit_sale_allocations.credit_sale_id
              AND public.is_aggregator_admin(cs.aggregator_id)
        )
    );

-- Membre d'une entreprise : lecture de ses propres allocations
DROP POLICY IF EXISTS "csa_member_select_own" ON public.credit_sale_allocations;
CREATE POLICY "csa_member_select_own"
    ON public.credit_sale_allocations
    FOR SELECT
    TO authenticated
    USING (public.is_company_member(company_id));

-- ════════════════════════════════════════════════════════════
-- TABLE : operational_units
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.operational_units ENABLE ROW LEVEL SECURITY;

-- Superadmin : accès complet
DROP POLICY IF EXISTS "operational_units_superadmin_all" ON public.operational_units;
CREATE POLICY "operational_units_superadmin_all"
    ON public.operational_units
    FOR ALL
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Owner d'entreprise : gestion complète des unités opérationnelles de son entreprise
DROP POLICY IF EXISTS "operational_units_owner_all" ON public.operational_units;
CREATE POLICY "operational_units_owner_all"
    ON public.operational_units
    FOR ALL
    TO authenticated
    USING (public.is_company_owner(company_id))
    WITH CHECK (public.is_company_owner(company_id));

-- Membre d'entreprise : lecture des unités opérationnelles de son entreprise
DROP POLICY IF EXISTS "operational_units_member_select" ON public.operational_units;
CREATE POLICY "operational_units_member_select"
    ON public.operational_units
    FOR SELECT
    TO authenticated
    USING (public.is_company_member(company_id));
