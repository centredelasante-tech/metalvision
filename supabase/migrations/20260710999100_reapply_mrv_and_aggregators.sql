BEGIN;

-- ============================================================
-- RÉAPPLICATION MRV + DOMAINE AGRÉGATEURS
-- Migration: 20260710999100_reapply_mrv_and_aggregators.sql
-- ============================================================
--
-- ⚠️  À APPLIQUER APRÈS 20260710999000_reset_and_reapply_ccf_full.sql ⚠️
--
-- Ce fichier réapplique dans l'ordre :
--   1. 20260628140000_mrv_iso14064.sql        — Domaine MRV / ISO 14064-2
--   2. Création des tables agrégateurs        — Tables manquantes (jamais
--      créées explicitement dans une migration antérieure)
--   3. 20260707110000_document_is_platform_admin.sql — Fonctions RLS helper
--   4. 20260707110100_is_platform_superadmin.sql     — is_platform_superadmin()
--   5. 20260707110200_aggregator_admins_table.sql    — aggregator_admins + is_aggregator_admin()
--   6. 20260707110300_aggregator_domain_rls.sql      — RLS domaine agrégateurs
--   7. 20260707120000_mt000a_governance_fixes.sql    — Correctifs gouvernance
--   8. 20260707130000_mt000b_unique_primary_admin_index.sql — Index unique primary_admin
--
-- APRÈS APPLICATION, vérifier :
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' ORDER BY table_name;
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- SECTION 1 — DOMAINE MRV / ISO 14064-2
-- Source : 20260628140000_mrv_iso14064.sql
-- ════════════════════════════════════════════════════════════

-- ── 1.1 ENUM TYPES ───────────────────────────────────────────
DROP TYPE IF EXISTS public.project_status CASCADE;
CREATE TYPE public.project_status AS ENUM ('draft', 'active', 'verified');

DROP TYPE IF EXISTS public.verification_status CASCADE;
CREATE TYPE public.verification_status AS ENUM ('planned', 'in_progress', 'completed');

-- ── 1.2 CORE TABLES ──────────────────────────────────────────

-- projects (MRV)
CREATE TABLE IF NOT EXISTS public.projects (
  id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                    UUID,
  operational_unit_id          UUID,  -- FK vers operational_units (ajouté pour le domaine agrégateurs)
  name                         TEXT NOT NULL,
  description                  TEXT,
  system_boundaries            JSONB,
  baseline_description         TEXT,
  project_scenario_description TEXT,
  start_date                   DATE,
  end_date                     DATE,
  status                       public.project_status DEFAULT 'draft'::public.project_status,
  created_at                   TIMESTAMPTZ DEFAULT now()
);

-- emission_factors
CREATE TABLE IF NOT EXISTS public.emission_factors (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category            TEXT NOT NULL,
  source_reference    TEXT,
  unit                TEXT NOT NULL,
  value               FLOAT8 NOT NULL,
  uncertainty_percent FLOAT8 DEFAULT 5.0,
  valid_from          DATE,
  valid_to            DATE,
  version             TEXT DEFAULT '1.0',
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- project_activity_logs
CREATE TABLE IF NOT EXISTS public.project_activity_logs (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id                    UUID REFERENCES public.projects(id) ON DELETE CASCADE,
  activity_type                 TEXT NOT NULL,
  related_lot_id                UUID,
  related_container_id          UUID,
  related_transport_request_id  UUID,
  raw_data_ref                  UUID,
  ghg_emissions_baseline_kgco2e FLOAT8,
  ghg_emissions_project_kgco2e  FLOAT8,
  ghg_reduction_kgco2e          FLOAT8,
  uncertainty_percent           FLOAT8,
  timestamp                     TIMESTAMPTZ DEFAULT now(),
  actor_id                      UUID
);

-- evidence_files
CREATE TABLE IF NOT EXISTS public.evidence_files (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id              UUID REFERENCES public.projects(id) ON DELETE CASCADE,
  file_url                TEXT,
  type                    TEXT,
  related_activity_log_id UUID REFERENCES public.project_activity_logs(id) ON DELETE SET NULL,
  gps                     JSONB,
  timestamp               TIMESTAMPTZ DEFAULT now(),
  actor_id                UUID
);

-- verification_sessions
CREATE TABLE IF NOT EXISTS public.verification_sessions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id       UUID REFERENCES public.projects(id) ON DELETE CASCADE,
  verifier_org     TEXT,
  verifier_contact TEXT,
  scope            JSONB,
  status           public.verification_status DEFAULT 'planned'::public.verification_status,
  report_url       TEXT,
  comments         TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- ── 1.3 INDEXES ──────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_projects_client_id ON public.projects(client_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON public.projects(status);
CREATE INDEX IF NOT EXISTS idx_activity_logs_project_id ON public.project_activity_logs(project_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_timestamp ON public.project_activity_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_evidence_files_project_id ON public.evidence_files(project_id);
CREATE INDEX IF NOT EXISTS idx_evidence_files_log_id ON public.evidence_files(related_activity_log_id);
CREATE INDEX IF NOT EXISTS idx_verification_sessions_project_id ON public.verification_sessions(project_id);
CREATE INDEX IF NOT EXISTS idx_emission_factors_category ON public.emission_factors(category);

-- ── 1.4 (supprimé) ───────────────────────────────────────────
-- Les définitions non sécurisées de is_project_admin(), is_verifier()
-- et is_project_client() (lisant raw_user_meta_data/raw_app_meta_data)
-- ont été retirées. Les versions sécurisées via auth.jwt() sont définies
-- en Section 3 et constituent la seule définition active de ces fonctions.

-- ── 1.5 ENABLE RLS ───────────────────────────────────────────
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emission_factors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evidence_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_sessions ENABLE ROW LEVEL SECURITY;

-- ── 1.6 RLS POLICIES ─────────────────────────────────────────

DROP POLICY IF EXISTS "admin_manage_projects" ON public.projects;
CREATE POLICY "admin_manage_projects" ON public.projects
FOR ALL TO authenticated
USING (public.is_project_admin())
WITH CHECK (public.is_project_admin());

DROP POLICY IF EXISTS "client_read_own_projects" ON public.projects;
CREATE POLICY "client_read_own_projects" ON public.projects
FOR SELECT TO authenticated
USING (client_id = auth.uid() OR public.is_project_client());

DROP POLICY IF EXISTS "verifier_read_projects" ON public.projects;
CREATE POLICY "verifier_read_projects" ON public.projects
FOR SELECT TO authenticated
USING (public.is_verifier());

DROP POLICY IF EXISTS "admin_manage_emission_factors" ON public.emission_factors;
CREATE POLICY "admin_manage_emission_factors" ON public.emission_factors
FOR ALL TO authenticated
USING (public.is_project_admin())
WITH CHECK (public.is_project_admin());

DROP POLICY IF EXISTS "authenticated_read_emission_factors" ON public.emission_factors;
CREATE POLICY "authenticated_read_emission_factors" ON public.emission_factors
FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "admin_manage_activity_logs" ON public.project_activity_logs;
CREATE POLICY "admin_manage_activity_logs" ON public.project_activity_logs
FOR ALL TO authenticated
USING (public.is_project_admin())
WITH CHECK (public.is_project_admin());

DROP POLICY IF EXISTS "verifier_read_activity_logs" ON public.project_activity_logs;
CREATE POLICY "verifier_read_activity_logs" ON public.project_activity_logs
FOR SELECT TO authenticated
USING (public.is_verifier());

DROP POLICY IF EXISTS "client_read_activity_logs" ON public.project_activity_logs;
CREATE POLICY "client_read_activity_logs" ON public.project_activity_logs
FOR SELECT TO authenticated
USING (
  public.is_project_client() AND
  EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id = project_id AND p.client_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "admin_manage_evidence_files" ON public.evidence_files;
CREATE POLICY "admin_manage_evidence_files" ON public.evidence_files
FOR ALL TO authenticated
USING (public.is_project_admin())
WITH CHECK (public.is_project_admin());

DROP POLICY IF EXISTS "verifier_read_evidence_files" ON public.evidence_files;
CREATE POLICY "verifier_read_evidence_files" ON public.evidence_files
FOR SELECT TO authenticated
USING (public.is_verifier());

DROP POLICY IF EXISTS "client_read_evidence_files" ON public.evidence_files;
CREATE POLICY "client_read_evidence_files" ON public.evidence_files
FOR SELECT TO authenticated
USING (
  public.is_project_client() AND
  EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id = project_id AND p.client_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "admin_manage_verification_sessions" ON public.verification_sessions;
CREATE POLICY "admin_manage_verification_sessions" ON public.verification_sessions
FOR ALL TO authenticated
USING (public.is_project_admin())
WITH CHECK (public.is_project_admin());

DROP POLICY IF EXISTS "verifier_read_verification_sessions" ON public.verification_sessions;
CREATE POLICY "verifier_read_verification_sessions" ON public.verification_sessions
FOR SELECT TO authenticated
USING (public.is_verifier());

DROP POLICY IF EXISTS "client_read_verification_sessions" ON public.verification_sessions;
CREATE POLICY "client_read_verification_sessions" ON public.verification_sessions
FOR SELECT TO authenticated
USING (public.is_project_client());

-- ── 1.7 MOCK DATA MRV ────────────────────────────────────────
DO $$
DECLARE
  proj1_id UUID := gen_random_uuid();
  proj2_id UUID := gen_random_uuid();
  log1_id  UUID := gen_random_uuid();
  log2_id  UUID := gen_random_uuid();
  ef1_id   UUID := gen_random_uuid();
  ef2_id   UUID := gen_random_uuid();
  ef3_id   UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.emission_factors (id, category, source_reference, unit, value, uncertainty_percent, valid_from, valid_to, version)
  VALUES
    (ef1_id, 'transport_routier', 'ADEME 2023 - Camion 20t', 'kgCO2e/tkm', 0.062, 5.0, '2023-01-01', '2025-12-31', '2023.1'),
    (ef2_id, 'transport_ferroviaire', 'ADEME 2023 - Train fret', 'kgCO2e/tkm', 0.0028, 3.0, '2023-01-01', '2025-12-31', '2023.1'),
    (ef3_id, 'recyclage_acier', 'ADEME 2023 - Acier recyclé vs primaire', 'kgCO2e/kg', -1.85, 8.0, '2023-01-01', '2025-12-31', '2023.1')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.projects (id, name, description, system_boundaries, baseline_description, project_scenario_description, start_date, end_date, status)
  VALUES
    (proj1_id, 'Recyclage Acier Montréal 2024', 'Projet de recyclage de ferraille industrielle - Zone Montréal',
     jsonb_build_object('geographic', 'Grand Montréal', 'activities', ARRAY['collecte', 'transport', 'recyclage']),
     'Transport par camion diesel, recyclage acier primaire (baseline 2022)',
     'Transport optimisé multi-modal, recyclage acier secondaire',
     '2024-01-01', '2024-12-31', 'active'::public.project_status),
    (proj2_id, 'Collecte Aluminium Québec 2024', 'Collecte et recyclage aluminium - Province Québec',
     jsonb_build_object('geographic', 'Province Québec', 'activities', ARRAY['collecte', 'tri', 'recyclage']),
     'Collecte individuelle, transport diesel longue distance',
     'Collecte groupée, transport ferroviaire partiel',
     '2024-03-01', '2024-12-31', 'draft'::public.project_status)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.project_activity_logs (id, project_id, activity_type, ghg_emissions_baseline_kgco2e, ghg_emissions_project_kgco2e, ghg_reduction_kgco2e, uncertainty_percent, timestamp)
  VALUES
    (log1_id, proj1_id, 'transport', 248.5, 89.2, 159.3, 6.2, now() - interval '15 days'),
    (log2_id, proj1_id, 'recyclage', 1850.0, 185.0, 1665.0, 8.5, now() - interval '10 days')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.evidence_files (project_id, file_url, type, related_activity_log_id, gps, timestamp)
  VALUES
    (proj1_id, '/evidence/transport-bon-livraison-001.pdf', 'bon_livraison', log1_id,
     jsonb_build_object('lat', 45.5017, 'lng', -73.5673, 'accuracy_m', 10), now() - interval '15 days'),
    (proj1_id, '/evidence/pesee-officielle-001.jpg', 'photo_pesee', log2_id,
     jsonb_build_object('lat', 45.4972, 'lng', -73.6103, 'accuracy_m', 5), now() - interval '10 days')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.verification_sessions (project_id, verifier_org, verifier_contact, scope, status, comments)
  VALUES
    (proj1_id, 'Bureau Veritas Canada', 'jean.dupont@bureauveritas.ca',
     jsonb_build_object('period', '2024-Q1-Q2', 'activities', ARRAY['transport', 'recyclage'], 'standard', 'ISO 14064-2:2019'),
     'planned'::public.verification_status, 'Vérification planifiée pour Q3 2024')
  ON CONFLICT (id) DO NOTHING;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'MRV mock data insertion failed: %', SQLERRM;
END $$;


-- ════════════════════════════════════════════════════════════
-- SECTION 2 — TABLES DU DOMAINE AGRÉGATEURS
-- Ces tables n'ont jamais été créées dans une migration dédiée.
-- Elles sont requises par 20260707110200 et 20260707110300.
-- ════════════════════════════════════════════════════════════

-- ── 2.1 Ajout de la colonne aggregator_id sur organizations ──
-- La table organizations existe (créée par ccf_002 / RT-03).
-- On ajoute aggregator_id si elle n'existe pas encore.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'organizations'
      AND column_name  = 'aggregator_id'
  ) THEN
    ALTER TABLE public.organizations ADD COLUMN aggregator_id UUID;
  END IF;
END $$;

-- ── 2.2 TABLE : aggregators ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.aggregators (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- FK : organizations.aggregator_id → aggregators.id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'organizations'
      AND constraint_name   = 'fk_organizations_aggregator_id'
  ) THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT fk_organizations_aggregator_id
      FOREIGN KEY (aggregator_id) REFERENCES public.aggregators(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ── 2.3 TABLE : operational_units ────────────────────────────
CREATE TABLE IF NOT EXISTS public.operational_units (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name            TEXT        NOT NULL,
    description     TEXT,
    location        TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- FK : projects.operational_unit_id → operational_units.id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'projects'
      AND constraint_name   = 'fk_projects_operational_unit_id'
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT fk_projects_operational_unit_id
      FOREIGN KEY (operational_unit_id) REFERENCES public.operational_units(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ── 2.4 TABLE : credit_lots ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.credit_lots (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID        NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    quantity_tco2e  FLOAT8      NOT NULL CHECK (quantity_tco2e > 0),
    vintage_year    INT         NOT NULL,
    status          TEXT        NOT NULL DEFAULT 'available'
                                CHECK (status IN ('available', 'reserved', 'sold', 'retired')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2.5 TABLE : credit_sales ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.credit_sales (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_id   UUID        NOT NULL REFERENCES public.aggregators(id) ON DELETE CASCADE,
    buyer_name      TEXT        NOT NULL,
    sale_date       DATE        NOT NULL DEFAULT CURRENT_DATE,
    total_tco2e     FLOAT8      NOT NULL CHECK (total_tco2e > 0),
    price_per_tco2e FLOAT8,
    currency        TEXT        NOT NULL DEFAULT 'CAD',
    status          TEXT        NOT NULL DEFAULT 'draft'
                                CHECK (status IN ('draft', 'confirmed', 'settled', 'cancelled')),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2.6 TABLE : credit_sale_lots ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.credit_sale_lots (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_sale_id  UUID        NOT NULL REFERENCES public.credit_sales(id) ON DELETE CASCADE,
    credit_lot_id   UUID        NOT NULL REFERENCES public.credit_lots(id) ON DELETE RESTRICT,
    quantity_tco2e  FLOAT8      NOT NULL CHECK (quantity_tco2e > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2.7 TABLE : distribution_rules ───────────────────────────
CREATE TABLE IF NOT EXISTS public.distribution_rules (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_id   UUID        NOT NULL REFERENCES public.aggregators(id) ON DELETE CASCADE,
    rule_type       TEXT        NOT NULL DEFAULT 'proportional'
                                CHECK (rule_type IN ('proportional', 'equal', 'custom')),
    parameters      JSONB,
    effective_from  DATE        NOT NULL DEFAULT CURRENT_DATE,
    effective_to    DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2.8 TABLE : member_distribution_overrides ────────────────
CREATE TABLE IF NOT EXISTS public.member_distribution_overrides (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_id   UUID        NOT NULL REFERENCES public.aggregators(id) ON DELETE CASCADE,
    organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    override_ratio  FLOAT8      NOT NULL CHECK (override_ratio >= 0 AND override_ratio <= 1),
    reason          TEXT,
    effective_from  DATE        NOT NULL DEFAULT CURRENT_DATE,
    effective_to    DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (aggregator_id, organization_id, effective_from)
);

-- ── 2.9 TABLE : credit_sale_allocations ──────────────────────
CREATE TABLE IF NOT EXISTS public.credit_sale_allocations (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_sale_id   UUID        NOT NULL REFERENCES public.credit_sales(id) ON DELETE CASCADE,
    organization_id  UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    allocated_tco2e  FLOAT8      NOT NULL CHECK (allocated_tco2e > 0),
    allocated_amount FLOAT8,
    currency         TEXT        NOT NULL DEFAULT 'CAD',
    status           TEXT        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'paid', 'disputed')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2.10 INDEXES ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_aggregators_id ON public.aggregators(id);
CREATE INDEX IF NOT EXISTS idx_operational_units_organization_id ON public.operational_units(organization_id);
CREATE INDEX IF NOT EXISTS idx_credit_lots_project_id ON public.credit_lots(project_id);
CREATE INDEX IF NOT EXISTS idx_credit_lots_status ON public.credit_lots(status);
CREATE INDEX IF NOT EXISTS idx_credit_sales_aggregator_id ON public.credit_sales(aggregator_id);
CREATE INDEX IF NOT EXISTS idx_credit_sale_lots_sale_id ON public.credit_sale_lots(credit_sale_id);
CREATE INDEX IF NOT EXISTS idx_credit_sale_lots_lot_id ON public.credit_sale_lots(credit_lot_id);
CREATE INDEX IF NOT EXISTS idx_distribution_rules_aggregator_id ON public.distribution_rules(aggregator_id);
CREATE INDEX IF NOT EXISTS idx_mdo_aggregator_id ON public.member_distribution_overrides(aggregator_id);
CREATE INDEX IF NOT EXISTS idx_mdo_organization_id ON public.member_distribution_overrides(organization_id);
CREATE INDEX IF NOT EXISTS idx_csa_sale_id ON public.credit_sale_allocations(credit_sale_id);
CREATE INDEX IF NOT EXISTS idx_csa_organization_id ON public.credit_sale_allocations(organization_id);
CREATE INDEX IF NOT EXISTS idx_organizations_aggregator_id ON public.organizations(aggregator_id);
CREATE INDEX IF NOT EXISTS idx_projects_operational_unit_id ON public.projects(operational_unit_id);


-- ════════════════════════════════════════════════════════════
-- SECTION 3 — FONCTIONS RLS HELPER (DOMAINE PLATEFORME)
-- Source : 20260707110000_document_is_platform_admin.sql
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_project_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') IN ('project_admin', 'admin')
$$;

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') IN ('project_admin', 'admin')
$$;

CREATE OR REPLACE FUNCTION public.is_verifier()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'verifier'
$$;

CREATE OR REPLACE FUNCTION public.is_project_client()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') IN ('project_client', 'client')
$$;

CREATE OR REPLACE FUNCTION public.is_admin_from_auth()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
$$;


-- ════════════════════════════════════════════════════════════
-- SECTION 4 — is_platform_superadmin()
-- Source : 20260707110100_is_platform_superadmin.sql
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_platform_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
$$;


-- ════════════════════════════════════════════════════════════
-- SECTION 5 — TABLE aggregator_admins + is_aggregator_admin()
-- Source : 20260707110200_aggregator_admins_table.sql
-- ════════════════════════════════════════════════════════════

DROP TYPE IF EXISTS public.aggregator_admin_role CASCADE;
CREATE TYPE public.aggregator_admin_role AS ENUM ('primary_admin', 'co_admin');

CREATE TABLE IF NOT EXISTS public.aggregator_admins (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_id  UUID        NOT NULL REFERENCES public.aggregators(id) ON DELETE CASCADE,
    user_id        UUID        NOT NULL,
    role           public.aggregator_admin_role NOT NULL DEFAULT 'co_admin',
    nominated_by   UUID,
    nominated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_by     UUID,
    revoked_at     TIMESTAMPTZ,
    revocation_reason TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_aggregator_admins_aggregator_id
    ON public.aggregator_admins (aggregator_id);

CREATE INDEX IF NOT EXISTS idx_aggregator_admins_user_id
    ON public.aggregator_admins (user_id);

CREATE INDEX IF NOT EXISTS idx_aggregator_admins_active
    ON public.aggregator_admins (aggregator_id, user_id)
    WHERE revoked_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_aggregator_admins_active_role
    ON public.aggregator_admins (aggregator_id, user_id)
    WHERE revoked_at IS NULL;

DROP FUNCTION IF EXISTS public.is_aggregator_admin(UUID) CASCADE;
CREATE OR REPLACE FUNCTION public.is_aggregator_admin(p_aggregator_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.aggregator_admins aa
        WHERE aa.aggregator_id = p_aggregator_id
          AND aa.user_id = auth.uid()
          AND aa.revoked_at IS NULL
    )
$$;

ALTER TABLE public.aggregator_admins ENABLE ROW LEVEL SECURITY;


-- ════════════════════════════════════════════════════════════
-- SECTION 6 — RLS DOMAINE AGRÉGATEURS
-- Source : 20260707110300_aggregator_domain_rls.sql
-- ════════════════════════════════════════════════════════════

-- TABLE : aggregators
ALTER TABLE public.aggregators ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "aggregators_superadmin_all" ON public.aggregators;
CREATE POLICY "aggregators_superadmin_all"
    ON public.aggregators FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "aggregators_admin_select" ON public.aggregators;
CREATE POLICY "aggregators_admin_select"
    ON public.aggregators FOR SELECT TO authenticated
    USING (public.is_aggregator_admin(id));

DROP POLICY IF EXISTS "aggregators_member_select" ON public.aggregators;
CREATE POLICY "aggregators_member_select"
    ON public.aggregators FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.organizations o
            WHERE o.aggregator_id = aggregators.id
              AND public.is_organization_member(o.id)
        )
    );

-- TABLE : aggregator_admins (RLS déjà activé section 5)

DROP POLICY IF EXISTS "aggregator_admins_superadmin_all" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_superadmin_all"
    ON public.aggregator_admins FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "aggregator_admins_admin_select" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_select"
    ON public.aggregator_admins FOR SELECT TO authenticated
    USING (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "aggregator_admins_admin_insert" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_insert"
    ON public.aggregator_admins FOR INSERT TO authenticated
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "aggregator_admins_admin_update" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_update"
    ON public.aggregator_admins FOR UPDATE TO authenticated
    USING (public.is_aggregator_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "aggregator_admins_self_select" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_self_select"
    ON public.aggregator_admins FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- TABLE : credit_sales
ALTER TABLE public.credit_sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "credit_sales_superadmin_all" ON public.credit_sales;
CREATE POLICY "credit_sales_superadmin_all"
    ON public.credit_sales FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "credit_sales_admin_all" ON public.credit_sales;
CREATE POLICY "credit_sales_admin_all"
    ON public.credit_sales FOR ALL TO authenticated
    USING (public.is_aggregator_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "credit_sales_member_select" ON public.credit_sales;
CREATE POLICY "credit_sales_member_select"
    ON public.credit_sales FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.organizations o
            WHERE o.aggregator_id = credit_sales.aggregator_id
              AND public.is_organization_member(o.id)
        )
    );

-- TABLE : credit_sale_lots
ALTER TABLE public.credit_sale_lots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "credit_sale_lots_superadmin_all" ON public.credit_sale_lots;
CREATE POLICY "credit_sale_lots_superadmin_all"
    ON public.credit_sale_lots FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "credit_sale_lots_admin_all" ON public.credit_sale_lots;
CREATE POLICY "credit_sale_lots_admin_all"
    ON public.credit_sale_lots FOR ALL TO authenticated
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
    ON public.credit_sale_lots FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.credit_sales cs
            JOIN public.organizations o ON o.aggregator_id = cs.aggregator_id
            WHERE cs.id = credit_sale_lots.credit_sale_id
              AND public.is_organization_member(o.id)
        )
    );

-- TABLE : credit_lots
ALTER TABLE public.credit_lots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "credit_lots_superadmin_all" ON public.credit_lots;
CREATE POLICY "credit_lots_superadmin_all"
    ON public.credit_lots FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "credit_lots_admin_all" ON public.credit_lots;
CREATE POLICY "credit_lots_admin_all"
    ON public.credit_lots FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.projects p
            JOIN public.operational_units ou ON ou.id = p.operational_unit_id
            JOIN public.organizations org ON org.id = ou.organization_id
            JOIN public.aggregators agg ON agg.id = org.aggregator_id
            WHERE p.id = credit_lots.project_id
              AND public.is_aggregator_admin(agg.id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.projects p
            JOIN public.operational_units ou ON ou.id = p.operational_unit_id
            JOIN public.organizations org ON org.id = ou.organization_id
            JOIN public.aggregators agg ON agg.id = org.aggregator_id
            WHERE p.id = credit_lots.project_id
              AND public.is_aggregator_admin(agg.id)
        )
    );

DROP POLICY IF EXISTS "credit_lots_member_select" ON public.credit_lots;
CREATE POLICY "credit_lots_member_select"
    ON public.credit_lots FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.projects p
            JOIN public.operational_units ou ON ou.id = p.operational_unit_id
            WHERE p.id = credit_lots.project_id
              AND public.is_organization_member(ou.organization_id)
        )
    );

-- TABLE : distribution_rules
ALTER TABLE public.distribution_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "distribution_rules_superadmin_all" ON public.distribution_rules;
CREATE POLICY "distribution_rules_superadmin_all"
    ON public.distribution_rules FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "distribution_rules_admin_all" ON public.distribution_rules;
CREATE POLICY "distribution_rules_admin_all"
    ON public.distribution_rules FOR ALL TO authenticated
    USING (public.is_aggregator_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "distribution_rules_member_select" ON public.distribution_rules;
CREATE POLICY "distribution_rules_member_select"
    ON public.distribution_rules FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.organizations o
            WHERE o.aggregator_id = distribution_rules.aggregator_id
              AND public.is_organization_member(o.id)
        )
    );

-- TABLE : member_distribution_overrides
ALTER TABLE public.member_distribution_overrides ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mdo_superadmin_all" ON public.member_distribution_overrides;
CREATE POLICY "mdo_superadmin_all"
    ON public.member_distribution_overrides FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "mdo_admin_all" ON public.member_distribution_overrides;
CREATE POLICY "mdo_admin_all"
    ON public.member_distribution_overrides FOR ALL TO authenticated
    USING (public.is_aggregator_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_admin(aggregator_id));

DROP POLICY IF EXISTS "mdo_member_select_own" ON public.member_distribution_overrides;
CREATE POLICY "mdo_member_select_own"
    ON public.member_distribution_overrides FOR SELECT TO authenticated
    USING (public.is_organization_member(organization_id));

-- TABLE : credit_sale_allocations
ALTER TABLE public.credit_sale_allocations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "csa_superadmin_all" ON public.credit_sale_allocations;
CREATE POLICY "csa_superadmin_all"
    ON public.credit_sale_allocations FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "csa_admin_all" ON public.credit_sale_allocations;
CREATE POLICY "csa_admin_all"
    ON public.credit_sale_allocations FOR ALL TO authenticated
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
    ON public.credit_sale_allocations FOR SELECT TO authenticated
    USING (public.is_organization_member(organization_id));

-- TABLE : operational_units
ALTER TABLE public.operational_units ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "operational_units_superadmin_all" ON public.operational_units;
CREATE POLICY "operational_units_superadmin_all"
    ON public.operational_units FOR ALL TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

DROP POLICY IF EXISTS "operational_units_owner_all" ON public.operational_units;
CREATE POLICY "operational_units_owner_all"
    ON public.operational_units FOR ALL TO authenticated
    USING (public.is_organization_owner(organization_id))
    WITH CHECK (public.is_organization_owner(organization_id));

DROP POLICY IF EXISTS "operational_units_member_select" ON public.operational_units;
CREATE POLICY "operational_units_member_select"
    ON public.operational_units FOR SELECT TO authenticated
    USING (public.is_organization_member(organization_id));


-- ════════════════════════════════════════════════════════════
-- SECTION 7 — CORRECTIFS GOUVERNANCE AGRÉGATEURS
-- Source : 20260707120000_mt000a_governance_fixes.sql
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_platform_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
$$;

CREATE OR REPLACE FUNCTION public.is_aggregator_primary_admin(p_aggregator_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.aggregator_admins aa
        WHERE aa.aggregator_id = p_aggregator_id
          AND aa.user_id       = auth.uid()
          AND aa.role          = 'primary_admin'
          AND aa.revoked_at    IS NULL
    )
$$;

-- Correction : aggregator_admins_superadmin_all → SELECT + INSERT + UPDATE (jamais DELETE)
DROP POLICY IF EXISTS "aggregator_admins_superadmin_all" ON public.aggregator_admins;

CREATE POLICY "aggregator_admins_superadmin_select"
    ON public.aggregator_admins FOR SELECT TO authenticated
    USING (public.is_platform_superadmin());

CREATE POLICY "aggregator_admins_superadmin_insert"
    ON public.aggregator_admins FOR INSERT TO authenticated
    WITH CHECK (public.is_platform_superadmin());

CREATE POLICY "aggregator_admins_superadmin_update"
    ON public.aggregator_admins FOR UPDATE TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- Correction : INSERT/UPDATE → is_aggregator_primary_admin() (pas is_aggregator_admin())
DROP POLICY IF EXISTS "aggregator_admins_admin_insert" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_insert"
    ON public.aggregator_admins FOR INSERT TO authenticated
    WITH CHECK (public.is_aggregator_primary_admin(aggregator_id));

DROP POLICY IF EXISTS "aggregator_admins_admin_update" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_update"
    ON public.aggregator_admins FOR UPDATE TO authenticated
    USING  (public.is_aggregator_primary_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_primary_admin(aggregator_id));

CREATE OR REPLACE FUNCTION public.transfer_aggregator_primary_admin(
    p_aggregator_id       UUID,
    p_new_primary_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
    v_caller_id       UUID := auth.uid();
    v_old_primary_id  UUID;
    v_old_primary_row UUID;
    v_co_admin_row    UUID;
BEGIN
    IF NOT (
        public.is_aggregator_primary_admin(p_aggregator_id)
        OR public.is_platform_superadmin()
    ) THEN
        RAISE EXCEPTION
            'Autorisation refusée : seul le primary_admin actif ou le super-admin plateforme peut transférer le rôle primary_admin (aggregator_id = %)',
            p_aggregator_id;
    END IF;

    SELECT id, user_id
    INTO v_old_primary_row, v_old_primary_id
    FROM public.aggregator_admins
    WHERE aggregator_id = p_aggregator_id
      AND role          = 'primary_admin'
      AND revoked_at    IS NULL
    LIMIT 1;

    IF v_old_primary_id IS NULL THEN
        RAISE EXCEPTION 'Aucun primary_admin actif trouvé pour le regroupement %', p_aggregator_id;
    END IF;

    IF v_old_primary_id = p_new_primary_user_id THEN
        RAISE EXCEPTION 'Le nouveau primary_admin est déjà le primary_admin actif (user_id = %)', p_new_primary_user_id;
    END IF;

    UPDATE public.aggregator_admins
    SET revoked_at = now(), revoked_by = v_caller_id, revocation_reason = 'transfert de rôle'
    WHERE id = v_old_primary_row;

    SELECT id INTO v_co_admin_row
    FROM public.aggregator_admins
    WHERE aggregator_id = p_aggregator_id
      AND user_id       = p_new_primary_user_id
      AND revoked_at    IS NULL
    LIMIT 1;

    IF v_co_admin_row IS NOT NULL THEN
        UPDATE public.aggregator_admins
        SET revoked_at = now(), revoked_by = v_caller_id, revocation_reason = 'transfert de rôle — promotion primary_admin'
        WHERE id = v_co_admin_row;
    END IF;

    INSERT INTO public.aggregator_admins (aggregator_id, user_id, role, nominated_by, nominated_at)
    VALUES (p_aggregator_id, p_new_primary_user_id, 'primary_admin', v_caller_id, now());
END;
$func$;

DROP POLICY IF EXISTS "operational_units_aggregator_admin_select" ON public.operational_units;
CREATE POLICY "operational_units_aggregator_admin_select"
    ON public.operational_units FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.organizations org
            WHERE org.id = operational_units.organization_id
              AND public.is_aggregator_admin(org.aggregator_id)
        )
    );


-- ════════════════════════════════════════════════════════════
-- SECTION 8 — INDEX UNIQUE primary_admin
-- Source : 20260707130000_mt000b_unique_primary_admin_index.sql
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_equivalent_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename  = 'aggregator_admins'
          AND indexname <> 'idx_one_active_primary_admin'
          AND indexdef ILIKE '%aggregator_id%'
          AND indexdef ILIKE '%primary_admin%'
          AND indexdef ILIKE '%revoked_at IS NULL%'
          AND indexdef ILIKE '%UNIQUE%'
    ) INTO v_equivalent_exists;

    IF v_equivalent_exists THEN
        RAISE NOTICE 'MT-000B : Un index unique partiel équivalent existe déjà sur aggregator_admins. La création de idx_one_active_primary_admin est ignorée.';
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_primary_admin
    ON public.aggregator_admins (aggregator_id)
    WHERE role = 'primary_admin'
      AND revoked_at IS NULL;


-- ════════════════════════════════════════════════════════════
-- INVENTAIRE FINAL — Les trois domaines doivent coexister
-- ════════════════════════════════════════════════════════════
--
-- Après application, exécuter :
--
--   SELECT table_name
--   FROM information_schema.tables
--   WHERE table_schema = 'public'
--   ORDER BY table_name;
--
-- Résultat attendu (domaines) :
--
--   CCF (16 tables) :
--     ai_assistance_logs, audit_logs, business_events, capabilities,
--     ccf_projects, documents, logistics_steps, mandate_actions,
--     mandates, opportunities, opportunity_capabilities,
--     organization_members, organizations, profiles,
--     project_participants, value_reports
--
--   MRV / ISO 14064-2 (5 tables) :
--     emission_factors, evidence_files, project_activity_logs,
--     projects, verification_sessions
--
--   Agrégateurs (9 tables) :
--     aggregator_admins, aggregators,
--     credit_lots, credit_sale_allocations, credit_sale_lots,
--     credit_sales, distribution_rules,
--     member_distribution_overrides, operational_units
--
-- ============================================================

COMMIT;
