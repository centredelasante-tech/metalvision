-- ============================================================
-- MRV ISO 14064-2 Module — MetalVision
-- Migration: 20260628140000_mrv_iso14064.sql
-- ============================================================

-- ── 1. ENUM TYPES ────────────────────────────────────────────
DROP TYPE IF EXISTS public.project_status CASCADE;
CREATE TYPE public.project_status AS ENUM ('draft', 'active', 'verified');

DROP TYPE IF EXISTS public.verification_status CASCADE;
CREATE TYPE public.verification_status AS ENUM ('planned', 'in_progress', 'completed');

-- ── 2. CORE TABLES ───────────────────────────────────────────

-- projects
CREATE TABLE IF NOT EXISTS public.projects (
  id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                    UUID,
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

-- ── 3. INDEXES ───────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_projects_client_id ON public.projects(client_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON public.projects(status);
CREATE INDEX IF NOT EXISTS idx_activity_logs_project_id ON public.project_activity_logs(project_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_timestamp ON public.project_activity_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_evidence_files_project_id ON public.evidence_files(project_id);
CREATE INDEX IF NOT EXISTS idx_evidence_files_log_id ON public.evidence_files(related_activity_log_id);
CREATE INDEX IF NOT EXISTS idx_verification_sessions_project_id ON public.verification_sessions(project_id);
CREATE INDEX IF NOT EXISTS idx_emission_factors_category ON public.emission_factors(category);

-- ── 4. HELPER FUNCTIONS (before RLS) ─────────────────────────

CREATE OR REPLACE FUNCTION public.is_project_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id = auth.uid()
    AND (
      au.raw_user_meta_data->>'role' = 'project_admin'
      OR au.raw_user_meta_data->>'role' = 'admin'
      OR au.raw_app_meta_data->>'role' = 'project_admin'
      OR au.raw_app_meta_data->>'role' = 'admin'
    )
  )
$$;

CREATE OR REPLACE FUNCTION public.is_verifier()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id = auth.uid()
    AND (
      au.raw_user_meta_data->>'role' = 'verifier'
      OR au.raw_app_meta_data->>'role' = 'verifier'
    )
  )
$$;

CREATE OR REPLACE FUNCTION public.is_project_client()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id = auth.uid()
    AND (
      au.raw_user_meta_data->>'role' = 'project_client'
      OR au.raw_user_meta_data->>'role' = 'client'
      OR au.raw_app_meta_data->>'role' = 'project_client'
      OR au.raw_app_meta_data->>'role' = 'client'
    )
  )
$$;

-- ── 5. ENABLE RLS ────────────────────────────────────────────
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emission_factors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evidence_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_sessions ENABLE ROW LEVEL SECURITY;

-- ── 6. RLS POLICIES ──────────────────────────────────────────

-- projects: admin full access, client reads own, verifier reads all
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

-- emission_factors: admin manages, all authenticated read
DROP POLICY IF EXISTS "admin_manage_emission_factors" ON public.emission_factors;
CREATE POLICY "admin_manage_emission_factors" ON public.emission_factors
FOR ALL TO authenticated
USING (public.is_project_admin())
WITH CHECK (public.is_project_admin());

DROP POLICY IF EXISTS "authenticated_read_emission_factors" ON public.emission_factors;
CREATE POLICY "authenticated_read_emission_factors" ON public.emission_factors
FOR SELECT TO authenticated
USING (true);

-- project_activity_logs: admin full, verifier read, client read own project
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

-- evidence_files: admin full, verifier read, client read own
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

-- verification_sessions: admin full, verifier full read, client read
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

-- ── 7. UPDATED_AT TRIGGER ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mrv_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.created_at = OLD.created_at;
  RETURN NEW;
END;
$$;

-- ── 8. MOCK DATA ─────────────────────────────────────────────
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
  -- Emission factors
  INSERT INTO public.emission_factors (id, category, source_reference, unit, value, uncertainty_percent, valid_from, valid_to, version)
  VALUES
    (ef1_id, 'transport_routier', 'ADEME 2023 - Camion 20t', 'kgCO2e/tkm', 0.062, 5.0, '2023-01-01', '2025-12-31', '2023.1'),
    (ef2_id, 'transport_ferroviaire', 'ADEME 2023 - Train fret', 'kgCO2e/tkm', 0.0028, 3.0, '2023-01-01', '2025-12-31', '2023.1'),
    (ef3_id, 'recyclage_acier', 'ADEME 2023 - Acier recyclé vs primaire', 'kgCO2e/kg', -1.85, 8.0, '2023-01-01', '2025-12-31', '2023.1')
  ON CONFLICT (id) DO NOTHING;

  -- Projects
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

  -- Activity logs
  INSERT INTO public.project_activity_logs (id, project_id, activity_type, ghg_emissions_baseline_kgco2e, ghg_emissions_project_kgco2e, ghg_reduction_kgco2e, uncertainty_percent, timestamp)
  VALUES
    (log1_id, proj1_id, 'transport', 248.5, 89.2, 159.3, 6.2, now() - interval '15 days'),
    (log2_id, proj1_id, 'recyclage', 1850.0, 185.0, 1665.0, 8.5, now() - interval '10 days')
  ON CONFLICT (id) DO NOTHING;

  -- Evidence files
  INSERT INTO public.evidence_files (project_id, file_url, type, related_activity_log_id, gps, timestamp)
  VALUES
    (proj1_id, '/evidence/transport-bon-livraison-001.pdf', 'bon_livraison', log1_id,
     jsonb_build_object('lat', 45.5017, 'lng', -73.5673, 'accuracy_m', 10), now() - interval '15 days'),
    (proj1_id, '/evidence/pesee-officielle-001.jpg', 'photo_pesee', log2_id,
     jsonb_build_object('lat', 45.4972, 'lng', -73.6103, 'accuracy_m', 5), now() - interval '10 days')
  ON CONFLICT (id) DO NOTHING;

  -- Verification sessions
  INSERT INTO public.verification_sessions (project_id, verifier_org, verifier_contact, scope, status, comments)
  VALUES
    (proj1_id, 'Bureau Veritas Canada', 'jean.dupont@bureauveritas.ca',
     jsonb_build_object('period', '2024-Q1-Q2', 'activities', ARRAY['transport', 'recyclage'], 'standard', 'ISO 14064-2:2019'),
     'planned'::public.verification_status, 'Vérification planifiée pour Q3 2024')
  ON CONFLICT (id) DO NOTHING;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Mock data insertion failed: %', SQLERRM;
END $$;
