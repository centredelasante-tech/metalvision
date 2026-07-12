-- ============================================================
-- INC-DATA-01 — Restauration des tables MRV effacées par le reset CCF
-- Migration: 20260712130000_incdata01_restore_mrv_tables.sql
-- ============================================================
--
-- CONTEXTE :
-- 20260710999000_reset_and_reapply_ccf_full.sql contient
-- "DROP SCHEMA IF EXISTS public CASCADE;" et porte l'avertissement
-- "STAGING UNIQUEMENT — NE PAS APPLIQUER EN PRODUCTION". Il a
-- pourtant été exécuté en production. Les migrations de
-- réapplication qui ont suivi (20260710999100, 20260711000000)
-- n'ont recréé que le domaine CCF, une partie des agrégateurs et
-- 3 tables (companies, company_members, invitations).
--
-- 10 tables préexistantes n'ont jamais été recréées. Sur ces 10,
-- confirmé par grep sur src/ que 8 sont encore activement
-- utilisées par le code : raw_measurements, containers,
-- transport_requests, scan_events, global_stats, object_profiles,
-- app_settings, verifier_observations.
-- (clients et audit_learning_log : 0 référence dans src/, non
-- recréées ici — mortes.)
--
-- Ce fichier reconstruit fidèlement le DDL final (tables, colonnes,
-- index, triggers, policies RLS) tel qu'il existait juste avant le
-- reset, en assemblant l'historique complet des migrations
-- pré-reset : 20260609062345, 20260609063000, 20260613100000,
-- 20260628150000, 20260630090000, 20260630090100, 20260630090200,
-- 20260630090300, 20260630090400, 20260630150000, 20260701010000,
-- 20260701020000, 20260701030000, 20260703200000.
--
-- Aucune donnée n'est restaurée (confirmé par l'utilisateur : base
-- de test/démo, pas de perte de données réelles). Les tables sont
-- recréées vides.
--
-- Dépendances déjà présentes en production (vérifié par inventaire réel
-- information_schema.tables le 12 juillet, pas seulement par lecture des
-- migrations — voir correctif ci-dessous) :
--   is_company_member(), is_company_owner()  — définies dans 20260710999000,
--     interrogent déjà organization_members (pas company_members)
--   is_admin_from_auth()                      — réappliquée en 20260710999100
--   organizations                             — créée DIRECTEMENT par
--     20260710999000 (pas via un rename depuis companies)
--   project_activity_logs                     — réappliquée en 20260710999100
--
-- CORRECTIF (12 juillet, après premier échec de push) : la première version
-- de ce fichier référençait `public.companies(id)` en FK, en supposant que
-- 20260711000000_reapply_invitations_five_files.sql avait recréé cette
-- table. Le push a échoué avec `relation "public.companies" does not
-- exist` — confirmé par inventaire réel que cette migration n'a en fait
-- jamais été appliquée en production, malgré sa présence dans l'historique
-- git. La table réellement utilisée par tout le domaine CCF est
-- `organizations` (créée directement par le reset, pas par renommage).
-- Les 3 FK `company_id` ci-dessous pointent donc vers `organizations(id)`.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ────────────────────────────────────────────────────────────
-- Fonctions trigger utilitaires (jamais réappliquées après le reset)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_transport_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 1. raw_measurements
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.raw_measurements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL,
    company_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    metal_type_predicted TEXT,
    confidence NUMERIC(4,3),
    width_cm NUMERIC(10,2),
    height_cm NUMERIC(10,2),
    depth_cm NUMERIC(10,2),
    volume_estimated_m3 NUMERIC(12,6),
    compaction_visual NUMERIC(4,3),
    purity_visual NUMERIC(4,3),
    object_type TEXT,
    raw_analysis_json JSONB,
    official_weight_kg NUMERIC(12,3),
    official_metal_type TEXT,
    density_real NUMERIC(12,4),
    price_paid NUMERIC(12,2),
    reference_size_cm NUMERIC(10,2),
    metal_price_per_kg NUMERIC(10,4),
    density_override NUMERIC(10,4),
    image_url TEXT,
    status TEXT NOT NULL DEFAULT 'submitted'
        CHECK (status IN ('submitted', 'processed', 'invoiced')),
    notes TEXT,
    weight_kg NUMERIC,
    container_id UUID,
    transport_request_id UUID,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- NOTE : container_id est déclaré SANS REFERENCES ici volontairement.
-- public.containers n'existe pas encore à ce stade du script (créée
-- plus bas, section 4) — un CREATE TABLE avec REFERENCES vers une
-- table inexistante échoue immédiatement (confirmé par un premier
-- échec de push : `relation "public.containers" does not exist`).
-- La contrainte FK réelle est ajoutée en section 4bis, une fois
-- containers créée.

CREATE INDEX IF NOT EXISTS idx_raw_measurements_client_id ON public.raw_measurements(client_id);
CREATE INDEX IF NOT EXISTS idx_raw_measurements_metal_type ON public.raw_measurements(metal_type_predicted);
CREATE INDEX IF NOT EXISTS idx_raw_measurements_object_type ON public.raw_measurements(object_type);
CREATE INDEX IF NOT EXISTS idx_raw_measurements_created_at ON public.raw_measurements(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_raw_measurements_company_id ON public.raw_measurements(company_id);

DROP TRIGGER IF EXISTS set_raw_measurements_updated_at ON public.raw_measurements;
CREATE TRIGGER set_raw_measurements_updated_at
    BEFORE UPDATE ON public.raw_measurements
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.raw_measurements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_raw_measurements" ON public.raw_measurements;
CREATE POLICY "service_role_raw_measurements"
ON public.raw_measurements FOR ALL TO service_role
USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "client can read own measurements" ON public.raw_measurements;
CREATE POLICY "client can read own measurements"
ON public.raw_measurements FOR SELECT TO authenticated
USING (client_id = auth.uid());

DROP POLICY IF EXISTS "client can insert own measurements" ON public.raw_measurements;
CREATE POLICY "client can insert own measurements"
ON public.raw_measurements FOR INSERT TO authenticated
WITH CHECK (client_id = auth.uid());

DROP POLICY IF EXISTS "client can update own measurements" ON public.raw_measurements;
CREATE POLICY "client can update own measurements"
ON public.raw_measurements FOR UPDATE TO authenticated
USING (client_id = auth.uid()) WITH CHECK (client_id = auth.uid());

DROP POLICY IF EXISTS "company_members_select_raw_measurements" ON public.raw_measurements;
CREATE POLICY "company_members_select_raw_measurements"
ON public.raw_measurements FOR SELECT TO authenticated
USING (company_id IS NOT NULL AND public.is_company_member(company_id));

DROP POLICY IF EXISTS "company_members_insert_raw_measurements" ON public.raw_measurements;
CREATE POLICY "company_members_insert_raw_measurements"
ON public.raw_measurements FOR INSERT TO authenticated
WITH CHECK (company_id IS NOT NULL AND public.is_company_member(company_id));

DROP POLICY IF EXISTS "company_members_update_raw_measurements" ON public.raw_measurements;
CREATE POLICY "company_members_update_raw_measurements"
ON public.raw_measurements FOR UPDATE TO authenticated
USING (company_id IS NOT NULL AND public.is_company_member(company_id))
WITH CHECK (company_id IS NOT NULL AND public.is_company_member(company_id));

-- ────────────────────────────────────────────────────────────
-- 2. global_stats
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.global_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metal_type TEXT NOT NULL UNIQUE,
    density_mean NUMERIC(12,4),
    compaction_mean NUMERIC(6,4),
    purity_mean NUMERIC(6,4),
    volume_error_mean NUMERIC(12,6),
    nb_measurements INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_global_stats_metal_type ON public.global_stats(metal_type);

DROP TRIGGER IF EXISTS set_global_stats_updated_at ON public.global_stats;
CREATE TRIGGER set_global_stats_updated_at
    BEFORE UPDATE ON public.global_stats
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.global_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public read" ON public.global_stats;
CREATE POLICY "public read" ON public.global_stats FOR SELECT USING (true);

DROP POLICY IF EXISTS "system update" ON public.global_stats;
CREATE POLICY "system update" ON public.global_stats FOR UPDATE USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_global_stats" ON public.global_stats;
CREATE POLICY "service_role_global_stats"
ON public.global_stats FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_read_global_stats" ON public.global_stats;
CREATE POLICY "anon_read_global_stats"
ON public.global_stats FOR SELECT TO anon USING (true);

-- ────────────────────────────────────────────────────────────
-- 3. object_profiles
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.object_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    object_type TEXT NOT NULL UNIQUE,
    avg_width_cm NUMERIC(10,2),
    avg_height_cm NUMERIC(10,2),
    avg_depth_cm NUMERIC(10,2),
    avg_weight_kg NUMERIC(12,3),
    density_mean NUMERIC(12,4),
    nb_measurements INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_object_profiles_object_type ON public.object_profiles(object_type);

DROP TRIGGER IF EXISTS set_object_profiles_updated_at ON public.object_profiles;
CREATE TRIGGER set_object_profiles_updated_at
    BEFORE UPDATE ON public.object_profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.object_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public read" ON public.object_profiles;
CREATE POLICY "public read" ON public.object_profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "system update" ON public.object_profiles;
CREATE POLICY "system update" ON public.object_profiles FOR UPDATE USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_object_profiles" ON public.object_profiles;
CREATE POLICY "service_role_object_profiles"
ON public.object_profiles FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_read_object_profiles" ON public.object_profiles;
CREATE POLICY "anon_read_object_profiles"
ON public.object_profiles FOR SELECT TO anon USING (true);

-- ────────────────────────────────────────────────────────────
-- 4. containers
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.containers (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    qr_code     TEXT        NOT NULL,
    name        TEXT        NOT NULL,
    location    TEXT,
    status      TEXT        NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT containers_qr_code_unique UNIQUE (qr_code),
    CONSTRAINT containers_status_check CHECK (status IN ('active', 'inactive', 'maintenance'))
);

CREATE INDEX IF NOT EXISTS idx_containers_company_id ON public.containers (company_id);
CREATE INDEX IF NOT EXISTS idx_containers_qr_code ON public.containers (qr_code);

ALTER TABLE public.containers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "containers_select_members" ON public.containers;
CREATE POLICY "containers_select_members"
    ON public.containers FOR SELECT TO authenticated
    USING (public.is_company_member(company_id));

DROP POLICY IF EXISTS "containers_insert_owners" ON public.containers;
CREATE POLICY "containers_insert_owners"
    ON public.containers FOR INSERT TO authenticated
    WITH CHECK (public.is_company_owner(company_id));

DROP POLICY IF EXISTS "containers_update_owners" ON public.containers;
CREATE POLICY "containers_update_owners"
    ON public.containers FOR UPDATE TO authenticated
    USING (public.is_company_owner(company_id))
    WITH CHECK (public.is_company_owner(company_id));

DROP POLICY IF EXISTS "containers_delete_owners" ON public.containers;
CREATE POLICY "containers_delete_owners"
    ON public.containers FOR DELETE TO authenticated
    USING (public.is_company_owner(company_id));

-- 4bis. Maintenant que containers existe, (ré)ajouter le FK depuis raw_measurements
ALTER TABLE public.raw_measurements
    ADD CONSTRAINT raw_measurements_container_id_fkey
    FOREIGN KEY (container_id) REFERENCES public.containers(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_raw_measurements_container_id ON public.raw_measurements (container_id);

-- ────────────────────────────────────────────────────────────
-- 5. scan_events (avec chaîne de hachage)
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.scan_events (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    container_id    UUID        NOT NULL REFERENCES public.containers(id) ON DELETE CASCADE,
    company_id      UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id         UUID        NOT NULL,
    action_type     TEXT        NOT NULL,
    gps_lat         NUMERIC(10,7),
    gps_lng         NUMERIC(10,7),
    gps_accuracy_m  NUMERIC(6,2),
    scanned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    previous_hash   TEXT,
    event_hash      TEXT NOT NULL DEFAULT '',
    CONSTRAINT scan_events_action_type_check CHECK (action_type IN ('depot', 'collecte', 'verification'))
);

-- La valeur par défaut '' sur event_hash n'existait pas historiquement
-- (colonne posée NOT NULL après backfill) ; elle est ajoutée ici
-- uniquement pour permettre CREATE TABLE IF NOT EXISTS sur une table
-- vide sans erreur, puis retirée pour retrouver le comportement exact
-- d'origine où le trigger BEFORE INSERT calcule toujours la valeur.
ALTER TABLE public.scan_events ALTER COLUMN event_hash DROP DEFAULT;

CREATE INDEX IF NOT EXISTS idx_scan_events_company_id ON public.scan_events (company_id);
CREATE INDEX IF NOT EXISTS idx_scan_events_container_id ON public.scan_events (container_id);
CREATE INDEX IF NOT EXISTS idx_scan_events_scanned_at ON public.scan_events (scanned_at);
CREATE INDEX IF NOT EXISTS idx_scan_events_container_scanned ON public.scan_events (container_id, scanned_at);

CREATE OR REPLACE FUNCTION public.compute_scan_event_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
    v_previous_hash TEXT;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(NEW.container_id::TEXT));

    SELECT event_hash
    INTO   v_previous_hash
    FROM   public.scan_events
    WHERE  container_id = NEW.container_id
    ORDER  BY scanned_at DESC
    LIMIT  1;

    NEW.previous_hash := v_previous_hash;

    NEW.event_hash := encode(
        digest(
            COALESCE(NEW.previous_hash, '') ||
            NEW.container_id::TEXT          ||
            NEW.company_id::TEXT            ||
            NEW.user_id::TEXT               ||
            NEW.action_type                 ||
            COALESCE(NEW.gps_lat::TEXT, '') ||
            COALESCE(NEW.gps_lng::TEXT, '') ||
            NEW.scanned_at::TEXT,
            'sha256'
        ),
        'hex'
    );

    RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_compute_scan_event_hash ON public.scan_events;
CREATE TRIGGER trg_compute_scan_event_hash
    BEFORE INSERT ON public.scan_events
    FOR EACH ROW
    EXECUTE FUNCTION public.compute_scan_event_hash();

CREATE OR REPLACE FUNCTION public.verify_container_chain(p_container_id UUID)
RETURNS TABLE (
    event_id   UUID,
    scanned_at TIMESTAMPTZ,
    is_valid   BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
    r              RECORD;
    v_running_hash TEXT := NULL;
    v_expected     TEXT;
BEGIN
    FOR r IN
        SELECT
            se.id, se.container_id, se.company_id, se.user_id, se.action_type,
            se.gps_lat, se.gps_lng, se.scanned_at, se.previous_hash, se.event_hash
        FROM public.scan_events se
        WHERE se.container_id = p_container_id
        ORDER BY se.scanned_at ASC
    LOOP
        v_expected := encode(
            digest(
                COALESCE(v_running_hash, '')   ||
                r.container_id::TEXT           ||
                r.company_id::TEXT             ||
                r.user_id::TEXT                ||
                r.action_type                  ||
                COALESCE(r.gps_lat::TEXT, '')  ||
                COALESCE(r.gps_lng::TEXT, '')  ||
                r.scanned_at::TEXT,
                'sha256'
            ),
            'hex'
        );

        event_id   := r.id;
        scanned_at := r.scanned_at;
        is_valid   := (r.event_hash = v_expected);

        RETURN NEXT;
        v_running_hash := r.event_hash;
    END LOOP;
END;
$func$;

ALTER TABLE public.scan_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "scan_events_select_members" ON public.scan_events;
CREATE POLICY "scan_events_select_members"
    ON public.scan_events FOR SELECT TO authenticated
    USING (public.is_company_member(company_id));

DROP POLICY IF EXISTS "scan_events_insert_members" ON public.scan_events;
CREATE POLICY "scan_events_insert_members"
    ON public.scan_events FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid() AND public.is_company_member(company_id));

-- ────────────────────────────────────────────────────────────
-- 6. transport_requests
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.transport_requests (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lot_id                TEXT NOT NULL,
  company_id            UUID,
  container_id          TEXT,
  pickup_address        TEXT NOT NULL,
  dropoff_address       TEXT NOT NULL,
  scheduled_time        TIMESTAMPTZ,
  transporter           TEXT NOT NULL DEFAULT 'Groupe Robert',
  external_reference    TEXT,
  transport_status      TEXT NOT NULL DEFAULT 'pending',
  notes                 TEXT,
  provider              TEXT NOT NULL DEFAULT 'internal',
  driver_name           TEXT,
  truck_number          TEXT,
  arrival_eta           TIMESTAMPTZ,
  gps_start             JSONB,
  gps_end               JSONB,
  proof_photo_url       TEXT,
  proof_document_url    TEXT,
  transport_mode        TEXT DEFAULT 'camion',
  client_transporter_name TEXT,
  distance_km           NUMERIC(10,2),
  ghg_transport_kgco2e  NUMERIC(12,4),
  emission_factor_used  NUMERIC(10,6),
  weight_tonnes         NUMERIC(10,4),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transport_requests_lot_id ON public.transport_requests(lot_id);
CREATE INDEX IF NOT EXISTS idx_transport_requests_status ON public.transport_requests(transport_status);
CREATE INDEX IF NOT EXISTS idx_transport_requests_external_ref ON public.transport_requests(external_reference);
CREATE INDEX IF NOT EXISTS idx_transport_requests_created_at ON public.transport_requests(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transport_requests_provider ON public.transport_requests(provider);

DROP TRIGGER IF EXISTS trg_transport_requests_updated_at ON public.transport_requests;
CREATE TRIGGER trg_transport_requests_updated_at
  BEFORE UPDATE ON public.transport_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.set_transport_updated_at();

ALTER TABLE public.transport_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_read_transport_requests" ON public.transport_requests;
CREATE POLICY "authenticated_read_transport_requests"
  ON public.transport_requests FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_transport_requests" ON public.transport_requests;
CREATE POLICY "authenticated_insert_transport_requests"
  ON public.transport_requests FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_transport_requests" ON public.transport_requests;
CREATE POLICY "authenticated_update_transport_requests"
  ON public.transport_requests FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- 6bis. Maintenant que transport_requests existe, ajouter le FK depuis raw_measurements
ALTER TABLE public.raw_measurements DROP CONSTRAINT IF EXISTS raw_measurements_transport_request_id_fkey;
ALTER TABLE public.raw_measurements
    ADD CONSTRAINT raw_measurements_transport_request_id_fkey
    FOREIGN KEY (transport_request_id) REFERENCES public.transport_requests(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_raw_measurements_transport_request_id ON public.raw_measurements(transport_request_id);

-- ────────────────────────────────────────────────────────────
-- 7. app_settings
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.app_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL UNIQUE,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.app_settings (key, value, description)
VALUES (
  'external_transport_enabled',
  'false'::jsonb,
  'Enable external transport provider integration. Set to true to activate external carrier flow.'
)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_read_settings" ON public.app_settings;
CREATE POLICY "admin_read_settings"
  ON public.app_settings FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "admin_update_settings" ON public.app_settings;
CREATE POLICY "admin_update_settings"
  ON public.app_settings FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ────────────────────────────────────────────────────────────
-- 8. verifier_observations
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.verifier_observations (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_log_id  UUID        NOT NULL REFERENCES public.project_activity_logs(id) ON DELETE CASCADE,
    verifier_id      UUID        NOT NULL,
    observation_text TEXT        NOT NULL,
    status           TEXT        NOT NULL,
    created_at       TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT verifier_observations_status_check
        CHECK (status IN ('conforme', 'non_conforme', 'a_clarifier'))
);

CREATE INDEX IF NOT EXISTS idx_verifier_observations_activity_log_id ON public.verifier_observations (activity_log_id);
CREATE INDEX IF NOT EXISTS idx_verifier_observations_verifier_id ON public.verifier_observations (verifier_id);

ALTER TABLE public.verifier_observations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "verifier_observations_select" ON public.verifier_observations;
CREATE POLICY "verifier_observations_select"
    ON public.verifier_observations FOR SELECT TO authenticated
    USING (verifier_id = auth.uid() OR public.is_admin_from_auth());

DROP POLICY IF EXISTS "verifier_observations_insert" ON public.verifier_observations;
CREATE POLICY "verifier_observations_insert"
    ON public.verifier_observations FOR INSERT TO authenticated
    WITH CHECK (verifier_id = auth.uid());

DROP POLICY IF EXISTS "verifier_observations_update" ON public.verifier_observations;
CREATE POLICY "verifier_observations_update"
    ON public.verifier_observations FOR UPDATE TO authenticated
    USING (verifier_id = auth.uid()) WITH CHECK (verifier_id = auth.uid());

DROP POLICY IF EXISTS "verifier_observations_delete" ON public.verifier_observations;
CREATE POLICY "verifier_observations_delete"
    ON public.verifier_observations FOR DELETE TO authenticated
    USING (verifier_id = auth.uid());

-- ============================================================
-- Vérification post-application (à exécuter manuellement) :
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public' AND table_name IN (
--   'raw_measurements','global_stats','object_profiles','containers',
--   'scan_events','transport_requests','app_settings','verifier_observations'
-- ) ORDER BY table_name;
-- Doit retourner exactement ces 8 lignes.
-- ============================================================
