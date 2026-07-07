-- ============================================================
-- MT-000A — Migration 4 of 4
-- File: 20260707110300_aggregator_domain_rls.sql
-- Purpose: Create RLS policies for all Regroupements domain
--          tables using ONLY is_aggregator_admin() and
--          is_platform_superadmin().
--
-- GOVERNANCE RULE (NON-NEGOTIABLE):
-- is_platform_admin() MUST NEVER appear in this migration.
-- All platform-level access in this domain uses
-- is_platform_superadmin() exclusively.
--
-- Tables covered:
--   aggregators
--   aggregator_admins
--   credit_sales
--   credit_sale_lots
--   credit_lots
--   distribution_rules
--   member_distribution_overrides
--   credit_sale_allocations
--   operational_units (aggregator-adjacent)
--
-- Also adds the missing UNIQUE constraint on
-- credit_sale_allocations(credit_sale_id, company_id)
-- required for the upsert in /api/aggregator/calculate-sale.
-- ============================================================

-- ── PREREQUISITE: UNIQUE constraint on credit_sale_allocations
-- Required for the upsert in /api/aggregator/calculate-sale.
-- Uses IF NOT EXISTS pattern via a DO block for idempotency.
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'credit_sale_allocations'
      AND constraint_name = 'csa_unique_sale_company'
  ) THEN
    ALTER TABLE public.credit_sale_allocations
      ADD CONSTRAINT csa_unique_sale_company
      UNIQUE (credit_sale_id, company_id);
  END IF;
END $$;

-- ============================================================
-- 1. TABLE: aggregators
-- ─────────────────────────────────────────────────────────────
-- Platform superadmin: full access to all aggregators.
-- Aggregator admin: reads their own aggregator.
-- Members (via companies.aggregator_id): read their aggregator.
-- ============================================================

DROP POLICY IF EXISTS "aggregators_superadmin_all" ON public.aggregators;
CREATE POLICY "aggregators_superadmin_all"
  ON public.aggregators
  FOR ALL
  TO authenticated
  USING (public.is_platform_superadmin())
  WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "aggregators_admin_select" ON public.aggregators;
CREATE POLICY "aggregators_admin_select"
  ON public.aggregators
  FOR SELECT
  TO authenticated
  USING (public.is_aggregator_admin(id));

DROP POLICY IF EXISTS "aggregators_member_select" ON public.aggregators;
CREATE POLICY "aggregators_member_select"
  ON public.aggregators
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.companies c
      JOIN public.company_members cm ON cm.company_id = c.id
      WHERE c.aggregator_id = aggregators.id
        AND cm.user_id = auth.uid()
    )
  );

-- ============================================================
-- 2. TABLE: aggregator_admins
-- ─────────────────────────────────────────────────────────────
-- Platform superadmin: full access (nominate/revoke anyone).
-- Aggregator primary_admin: can read all admins of their group,
--   and nominate/revoke co_admins (enforced at app layer).
-- Any aggregator admin: can read the admin list of their group.
-- The admin themselves: can read their own record.
-- ============================================================

DROP POLICY IF EXISTS "aggregator_admins_superadmin_all" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_superadmin_all"
  ON public.aggregator_admins
  FOR ALL
  TO authenticated
  USING (public.is_platform_superadmin())
  WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "aggregator_admins_admin_select" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_select"
  ON public.aggregator_admins
  FOR SELECT
  TO authenticated
  USING (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "aggregator_admins_self_select" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_self_select"
  ON public.aggregator_admins
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "aggregator_admins_admin_insert" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_insert"
  ON public.aggregator_admins
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_aggregator_admin(aggregator_id)
    OR public.is_platform_superadmin()
  );

DROP POLICY IF EXISTS "aggregator_admins_admin_update" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_update"
  ON public.aggregator_admins
  FOR UPDATE
  TO authenticated
  USING (
    public.is_aggregator_admin(aggregator_id)
    OR public.is_platform_superadmin()
  )
  WITH CHECK (
    public.is_aggregator_admin(aggregator_id)
    OR public.is_platform_superadmin()
  );

-- ============================================================
-- 3. TABLE: credit_sales
-- ─────────────────────────────────────────────────────────────
-- Platform superadmin: full access.
-- Aggregator admin: full access to their aggregator's sales.
-- Members: read-only access to their aggregator's sales.
-- ============================================================

DROP POLICY IF EXISTS "credit_sales_superadmin_all" ON public.credit_sales;
CREATE POLICY "credit_sales_superadmin_all"
  ON public.credit_sales
  FOR ALL
  TO authenticated
  USING (public.is_platform_superadmin())
  WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "credit_sales_admin_all" ON public.credit_sales;
CREATE POLICY "credit_sales_admin_all"
  ON public.credit_sales
  FOR ALL
  TO authenticated
  USING (public.is_aggregator_admin(aggregator_id))
  WITH CHECK (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "credit_sales_member_select" ON public.credit_sales;
CREATE POLICY "credit_sales_member_select"
  ON public.credit_sales
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.companies c
      JOIN public.company_members cm ON cm.company_id = c.id
      WHERE c.aggregator_id = credit_sales.aggregator_id
        AND cm.user_id = auth.uid()
    )
  );

-- ============================================================
-- 4. TABLE: credit_sale_lots
-- ─────────────────────────────────────────────────────────────
-- Access follows credit_sales: admin manages, members read.
-- ============================================================

DROP POLICY IF EXISTS "credit_sale_lots_superadmin_all" ON public.credit_sale_lots;
CREATE POLICY "credit_sale_lots_superadmin_all"
  ON public.credit_sale_lots
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.credit_sales cs
      WHERE cs.id = credit_sale_lots.credit_sale_id
        AND public.is_platform_superadmin()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.credit_sales cs
      WHERE cs.id = credit_sale_lots.credit_sale_id
        AND public.is_platform_superadmin()
    )
  );

DROP POLICY IF EXISTS "credit_sale_lots_admin_all" ON public.credit_sale_lots;
CREATE POLICY "credit_sale_lots_admin_all"
  ON public.credit_sale_lots
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.credit_sales cs
      WHERE cs.id = credit_sale_lots.credit_sale_id
        AND public.is_aggregator_admin(cs.aggregator_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.credit_sales cs
      WHERE cs.id = credit_sale_lots.credit_sale_id
        AND public.is_aggregator_admin(cs.aggregator_id)
    )
  );

DROP POLICY IF EXISTS "credit_sale_lots_member_select" ON public.credit_sale_lots;
CREATE POLICY "credit_sale_lots_member_select"
  ON public.credit_sale_lots
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.credit_sales cs
      JOIN public.companies c ON c.aggregator_id = cs.aggregator_id
      JOIN public.company_members cm ON cm.company_id = c.id
      WHERE cs.id = credit_sale_lots.credit_sale_id
        AND cm.user_id = auth.uid()
    )
  );

-- ============================================================
-- 5. TABLE: credit_lots
-- ─────────────────────────────────────────────────────────────
-- Platform superadmin: full access.
-- Aggregator admin: full access to lots linked to their
--   aggregator's projects (via project → company → aggregator).
-- Members: read-only access to their own company's lots.
-- ============================================================

DROP POLICY IF EXISTS "credit_lots_superadmin_all" ON public.credit_lots;
CREATE POLICY "credit_lots_superadmin_all"
  ON public.credit_lots
  FOR ALL
  TO authenticated
  USING (public.is_platform_superadmin())
  WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "credit_lots_admin_all" ON public.credit_lots;
CREATE POLICY "credit_lots_admin_all"
  ON public.credit_lots
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.projects p
      JOIN public.companies c ON c.id = p.client_id
      WHERE p.id = credit_lots.project_id
        AND public.is_aggregator_admin(c.aggregator_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.projects p
      JOIN public.companies c ON c.id = p.client_id
      WHERE p.id = credit_lots.project_id
        AND public.is_aggregator_admin(c.aggregator_id)
    )
  );

DROP POLICY IF EXISTS "credit_lots_member_select" ON public.credit_lots;
CREATE POLICY "credit_lots_member_select"
  ON public.credit_lots
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.projects p
      JOIN public.company_members cm ON cm.company_id = p.client_id
      WHERE p.id = credit_lots.project_id
        AND cm.user_id = auth.uid()
    )
  );

-- ============================================================
-- 6. TABLE: distribution_rules
-- ─────────────────────────────────────────────────────────────
-- Platform superadmin: full access.
-- Aggregator admin: full access to their aggregator's rules.
-- Members: read-only access to their aggregator's rules.
-- ============================================================

DROP POLICY IF EXISTS "distribution_rules_superadmin_all" ON public.distribution_rules;
CREATE POLICY "distribution_rules_superadmin_all"
  ON public.distribution_rules
  FOR ALL
  TO authenticated
  USING (public.is_platform_superadmin())
  WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "distribution_rules_admin_all" ON public.distribution_rules;
CREATE POLICY "distribution_rules_admin_all"
  ON public.distribution_rules
  FOR ALL
  TO authenticated
  USING (public.is_aggregator_admin(aggregator_id))
  WITH CHECK (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "distribution_rules_member_select" ON public.distribution_rules;
CREATE POLICY "distribution_rules_member_select"
  ON public.distribution_rules
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.companies c
      JOIN public.company_members cm ON cm.company_id = c.id
      WHERE c.aggregator_id = distribution_rules.aggregator_id
        AND cm.user_id = auth.uid()
    )
  );

-- ============================================================
-- 7. TABLE: member_distribution_overrides
-- ─────────────────────────────────────────────────────────────
-- Platform superadmin: full access.
-- Aggregator admin: full access to their aggregator's overrides.
-- The concerned member: read-only access to their own override.
-- ============================================================

DROP POLICY IF EXISTS "mdo_superadmin_all" ON public.member_distribution_overrides;
CREATE POLICY "mdo_superadmin_all"
  ON public.member_distribution_overrides
  FOR ALL
  TO authenticated
  USING (public.is_platform_superadmin())
  WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "mdo_admin_all" ON public.member_distribution_overrides;
CREATE POLICY "mdo_admin_all"
  ON public.member_distribution_overrides
  FOR ALL
  TO authenticated
  USING (public.is_aggregator_admin(aggregator_id))
  WITH CHECK (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "mdo_member_select_own" ON public.member_distribution_overrides;
CREATE POLICY "mdo_member_select_own"
  ON public.member_distribution_overrides
  FOR SELECT
  TO authenticated
  USING (public.is_company_member(company_id));

-- ============================================================
-- 8. TABLE: credit_sale_allocations
-- ─────────────────────────────────────────────────────────────
-- Platform superadmin: full access.
-- Aggregator admin: full access (needed for calculate-sale API).
-- The concerned member: read-only access to their own allocation.
-- ============================================================

DROP POLICY IF EXISTS "csa_superadmin_all" ON public.credit_sale_allocations;
CREATE POLICY "csa_superadmin_all"
  ON public.credit_sale_allocations
  FOR ALL
  TO authenticated
  USING (public.is_platform_superadmin())
  WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "csa_admin_all" ON public.credit_sale_allocations;
CREATE POLICY "csa_admin_all"
  ON public.credit_sale_allocations
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.credit_sales cs
      WHERE cs.id = credit_sale_allocations.credit_sale_id
        AND public.is_aggregator_admin(cs.aggregator_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.credit_sales cs
      WHERE cs.id = credit_sale_allocations.credit_sale_id
        AND public.is_aggregator_admin(cs.aggregator_id)
    )
  );

DROP POLICY IF EXISTS "csa_member_select_own" ON public.credit_sale_allocations;
CREATE POLICY "csa_member_select_own"
  ON public.credit_sale_allocations
  FOR SELECT
  TO authenticated
  USING (public.is_company_member(company_id));

-- ============================================================
-- 9. TABLE: operational_units
-- ─────────────────────────────────────────────────────────────
-- Platform superadmin: full access.
-- Company owner: manages their own company's units.
-- Company member: read-only access to their company's units.
-- Note: operational_units are company-scoped, not aggregator-
-- scoped, so is_company_owner/is_company_member are appropriate.
-- ============================================================

DROP POLICY IF EXISTS "operational_units_superadmin_all" ON public.operational_units;
CREATE POLICY "operational_units_superadmin_all"
  ON public.operational_units
  FOR ALL
  TO authenticated
  USING (public.is_platform_superadmin())
  WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "operational_units_owner_all" ON public.operational_units;
CREATE POLICY "operational_units_owner_all"
  ON public.operational_units
  FOR ALL
  TO authenticated
  USING (public.is_company_owner(company_id))
  WITH CHECK (public.is_company_owner(company_id));

DROP POLICY IF EXISTS "operational_units_member_select" ON public.operational_units;
CREATE POLICY "operational_units_member_select"
  ON public.operational_units
  FOR SELECT
  TO authenticated
  USING (public.is_company_member(company_id));
