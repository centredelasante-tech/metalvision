-- ============================================================
-- Tests — Migration 05 (verification_outcomes)
-- ============================================================
--
-- STATUT : PROPOSITION SOUMISE POUR REVUE — NON EXÉCUTÉE.
-- À exécuter APRÈS avoir appliqué 05_carbon_verification_outcomes.sql,
-- jamais avant. Même discipline que tests/02, tests/04 et tests/07 : script
-- de validation SÉPARÉ de la migration elle-même, jamais mélangé.
--
-- STRUCTURE : script encapsulé dans un unique BEGIN; ... ROLLBACK; explicite.
-- Le résumé (section finale) est affiché AVANT le ROLLBACK. Aucune donnée
-- créée par ce script ne persiste après son exécution.
--
-- FIXTURES — un seul projet MRV réel ('...6001'), SIX sessions de
-- vérification aux périodes engagées non chevauchantes (sauf S5, construite
-- délibérément pour chevaucher S1 et déclencher l'EXCLUDE de la section 1) :
--   S1 ('...7001') — cycle de vie complet : planned -> in_progress ->
--     completed, chemin de succès PUIS supersession. Période janvier 2026.
--   S2 ('...7002') — teste spécifiquement la branche « aucun vérificateur
--     assigné » (verifier_user_id NULL, appelée par le super-admin). Période
--     avril 2026.
--   S3 ('...7003') — teste la divergence > 1% entre verified_reduction_tco2e
--     et la valeur calculée suggérée. Période février 2026.
--   S4 ('...7004') — teste les rejets NaN / eligible > verified. Aucune
--     activité (calculated_reduction_tco2e = 0), donc la vérification de
--     divergence ne s'applique jamais ici. Période mars 2026.
--   S5 ('...7005') — teste l'EXCLUDE (périodes 'completed' chevauchantes
--     pour le MÊME projet). Période 15-20 janvier 2026, chevauche S1.
--   S6 ('...7006') — teste le CHECK « completed exige période + vérificateur »
--     directement (aucune période, aucun vérificateur assigné).
--
-- Profils : RÉUTILISATION de 6 profils réels existants (même motif que
-- tests/07/tests/04). pg_temp.carbon_test_set_actor_role() (nouveau, ce
-- fichier) simule un rôle JWT ARBITRAIRE (pas seulement superadmin/rien) —
-- nécessaire pour is_project_admin()/is_project_client(), qui dépendent de
-- auth.jwt()->'app_metadata'->>'role' IN (...) et non d'une simple adhésion
-- organisationnelle.
--
-- ⚠️ HYPOTHÈSE NON VÉRIFIÉE PAR CE SCRIPT (B32) : la migration 05 n'ajoute
-- aucun REVOKE/GRANT sur verification_sessions elle-même (table du chantier
-- MRV antérieur, jamais durcie au niveau privilèges de table dans aucun
-- fichier examiné) — B32 suppose donc que `authenticated` détient déjà le
-- privilège UPDATE au niveau table (convention Supabase par défaut : GRANT
-- large aux tables `public`, RLS comme gate principal), sans quoi B32
-- échouerait avec « permission denied » plutôt que de démontrer le filtrage
-- RLS silencieux (0 ligne affectée) qu'il prétend tester. À reconfirmer en
-- direct avant exécution réelle si l'environnement diffère de cette
-- hypothèse.
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. Table de résultats + helpers d'assertion et de simulation d'acteur
-- ────────────────────────────────────────────────────────────
CREATE TABLE public._carbon_migration_test_results (
    id        SERIAL PRIMARY KEY,
    section   TEXT NOT NULL,
    assertion TEXT NOT NULL,
    detail    TEXT NULL,
    passed    BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_assert(
    p_section TEXT, p_assertion TEXT, p_condition BOOLEAN, p_detail TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public._carbon_migration_test_results(section, assertion, detail, passed)
    VALUES (p_section, p_assertion, p_detail, COALESCE(p_condition, false));
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_assert_raises(
    p_section TEXT, p_assertion TEXT, p_sql TEXT, p_expected_fragment TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_msg TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        PERFORM pg_temp.carbon_test_assert(p_section, p_assertion, false, 'Aucune exception levée (attendue).');
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
        IF p_expected_fragment IS NULL OR v_msg ILIKE '%' || p_expected_fragment || '%' THEN
            PERFORM pg_temp.carbon_test_assert(p_section, p_assertion, true, v_msg);
        ELSE
            PERFORM pg_temp.carbon_test_assert(p_section, p_assertion, false, 'Message inattendu: ' || v_msg);
        END IF;
    END;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_set_actor(p_user_id UUID, p_superadmin BOOLEAN DEFAULT false) RETURNS VOID
LANGUAGE sql AS $$
    SELECT set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', p_user_id::text,
            'role', 'authenticated',
            'app_metadata', CASE WHEN p_superadmin THEN jsonb_build_object('role', 'admin') ELSE jsonb_build_object() END
        )::text,
        true
    );
$$;

-- Simulation d'un rôle JWT ARBITRAIRE (pas seulement superadmin/rien) — requis
-- pour is_project_admin()/is_project_client() (§7, RLS verification_outcomes),
-- qui dépendent de auth.jwt()->'app_metadata'->>'role', pas d'une adhésion
-- organisationnelle.
CREATE OR REPLACE FUNCTION pg_temp.carbon_test_set_actor_role(p_user_id UUID, p_role TEXT) RETURNS VOID
LANGUAGE sql AS $$
    SELECT set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', p_user_id::text, 'role', 'authenticated', 'app_metadata', jsonb_build_object('role', p_role))::text,
        true
    );
$$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_clear_actor() RETURNS VOID
LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims', '{}', true);
$$;

-- ────────────────────────────────────────────────────────────
-- 1. PRÉVALIDATION — structure attendue de la migration 05
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert('A1', 'table verification_outcomes existe',
        to_regclass('public.verification_outcomes') IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('A2', 'RLS activé sur verification_outcomes',
        COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname = 'verification_outcomes' AND relnamespace = 'public'::regnamespace), false));
    PERFORM pg_temp.carbon_test_assert('A3', 'index unique partiel (verification_session_id, status=active) présent',
        EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = 'public' AND tablename = 'verification_outcomes'
              AND indexname = 'idx_verification_outcomes_one_active_per_session'
              AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%verification_session_id%'
        ));
    PERFORM pg_temp.carbon_test_assert('A4', 'CHECK anti-NaN présents sur les trois colonnes numériques',
        EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                WHERE t.relname = 'verification_outcomes' AND c.contype = 'c'
                  AND pg_get_constraintdef(c.oid) ILIKE '%calculated_reduction_tco2e%' AND pg_get_constraintdef(c.oid) ILIKE '%NaN%')
        AND EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                WHERE t.relname = 'verification_outcomes' AND c.contype = 'c'
                  AND pg_get_constraintdef(c.oid) ILIKE '%verified_reduction_tco2e%' AND pg_get_constraintdef(c.oid) ILIKE '%NaN%')
        AND EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                WHERE t.relname = 'verification_outcomes' AND c.contype = 'c'
                  AND pg_get_constraintdef(c.oid) ILIKE '%eligible_tco2e%' AND pg_get_constraintdef(c.oid) ILIKE '%NaN%'));
    PERFORM pg_temp.carbon_test_assert('A5', 'verification_sessions gagne reporting_period_start/end et verifier_user_id',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='verification_sessions' AND column_name='reporting_period_start')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='verification_sessions' AND column_name='reporting_period_end')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='verification_sessions' AND column_name='verifier_user_id' AND data_type='uuid'));
    PERFORM pg_temp.carbon_test_assert('A6', 'CHECK verification_sessions_completed_requires_period_and_verifier présent',
        EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                WHERE t.relname = 'verification_sessions' AND c.contype = 'c'
                  AND c.conname = 'verification_sessions_completed_requires_period_and_verifier'));
    PERFORM pg_temp.carbon_test_assert('A7', 'EXCLUDE verification_sessions_no_overlapping_completed_periods présent',
        EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                WHERE t.relname = 'verification_sessions' AND c.contype = 'x'
                  AND c.conname = 'verification_sessions_no_overlapping_completed_periods'));
    PERFORM pg_temp.carbon_test_assert('A8', 'complete_verification_session(uuid,numeric,numeric,uuid,text) existe, EXECUTE authenticated/anon révoqué',
        to_regprocedure('public.complete_verification_session(uuid,numeric,numeric,uuid,text)') IS NOT NULL
        AND has_function_privilege('authenticated', 'public.complete_verification_session(uuid,numeric,numeric,uuid,text)'::regprocedure, 'EXECUTE')
        AND NOT has_function_privilege('anon', 'public.complete_verification_session(uuid,numeric,numeric,uuid,text)'::regprocedure, 'EXECUTE'));
    PERFORM pg_temp.carbon_test_assert('A9', 'carbon_capacity_consumed_for_session(uuid) existe (stub), SANS EXECUTE à authenticated, retourne 0',
        to_regprocedure('public.carbon_capacity_consumed_for_session(uuid)') IS NOT NULL
        AND NOT has_function_privilege('authenticated', 'public.carbon_capacity_consumed_for_session(uuid)'::regprocedure, 'EXECUTE')
        AND public.carbon_capacity_consumed_for_session(gen_random_uuid()) = 0);
    PERFORM pg_temp.carbon_test_assert('A10', 'is_assigned_verifier(uuid) existe, EXECUTE authenticated',
        to_regprocedure('public.is_assigned_verifier(uuid)') IS NOT NULL
        AND has_function_privilege('authenticated', 'public.is_assigned_verifier(uuid)'::regprocedure, 'EXECUTE'));
    PERFORM pg_temp.carbon_test_assert('A11', 'triggers guard_update/reject_delete existent sur verification_outcomes',
        EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'verification_outcomes' AND tg.tgname = 'verification_outcomes_guard_update')
        AND EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'verification_outcomes' AND tg.tgname = 'verification_outcomes_reject_delete'));
    PERFORM pg_temp.carbon_test_assert('A12', 'can_view_carbon_event(uuid,uuid,uuid,uuid) : signature inchangée, corps référence désormais is_assigned_verifier()',
        to_regprocedure('public.can_view_carbon_event(uuid,uuid,uuid,uuid)') IS NOT NULL
        AND pg_get_functiondef('public.can_view_carbon_event(uuid,uuid,uuid,uuid)'::regprocedure) ILIKE '%is_assigned_verifier(%');
    PERFORM pg_temp.carbon_test_assert('A13', 'policy verification_sessions_assigned_verifier_update existe',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='verification_sessions' AND policyname='verification_sessions_assigned_verifier_update'));
    PERFORM pg_temp.carbon_test_assert('A14', 'privilèges de table : authenticated a SELECT seulement sur verification_outcomes',
        has_table_privilege('authenticated', 'public.verification_outcomes', 'SELECT')
        AND NOT has_table_privilege('authenticated', 'public.verification_outcomes', 'INSERT')
        AND NOT has_table_privilege('authenticated', 'public.verification_outcomes', 'UPDATE')
        AND NOT has_table_privilege('authenticated', 'public.verification_outcomes', 'DELETE'));
END $$;

-- ────────────────────────────────────────────────────────────
-- 2. FIXTURES
-- ────────────────────────────────────────────────────────────

INSERT INTO public.projects (id, name, status)
VALUES ('33333333-3333-3333-3333-333333336001', 'TEST-05 Projet MRV', 'active');

INSERT INTO public.verification_sessions (id, project_id, verifier_org, verifier_contact, status)
VALUES
    ('33333333-3333-3333-3333-333333337001', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337002', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337003', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337004', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337005', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337006', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned');

-- Profils — RÉUTILISATION de 6 profils réels existants (voir en-tête).
DO $$
DECLARE
    v_profile_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_profile_ids
    FROM (SELECT id FROM public.profiles ORDER BY created_at LIMIT 6) sub;

    IF COALESCE(array_length(v_profile_ids, 1), 0) < 6 THEN
        RAISE EXCEPTION 'Fixtures impossibles : au moins 6 profils réels distincts sont requis dans public.profiles pour exécuter ce script (trouvés : %). Provisionner des comptes de test via l''API Auth de Supabase avant de relancer.', COALESCE(array_length(v_profile_ids, 1), 0);
    END IF;

    PERFORM set_config('carbon_test.profile_superadmin',       v_profile_ids[1]::text, false);
    PERFORM set_config('carbon_test.profile_verifier_assigned', v_profile_ids[2]::text, false);
    PERFORM set_config('carbon_test.profile_verifier_other',    v_profile_ids[3]::text, false);
    PERFORM set_config('carbon_test.profile_project_admin',     v_profile_ids[4]::text, false);
    PERFORM set_config('carbon_test.profile_project_client',    v_profile_ids[5]::text, false);
    PERFORM set_config('carbon_test.profile_outsider',          v_profile_ids[6]::text, false);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_profile(p_key TEXT) RETURNS UUID
LANGUAGE sql AS $$ SELECT current_setting('carbon_test.profile_' || p_key)::UUID $$;

-- S1 (période janvier 2026) : assignation directe du vérificateur (bypass
-- RLS, rôle propriétaire des tables — pas de RPC d'assignation, voir « POINT
-- OUVERT » de la migration) puis passage à in_progress.
UPDATE public.verification_sessions
SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned'),
    reporting_period_start = '2026-01-01', reporting_period_end = '2026-01-31',
    status = 'in_progress'
WHERE id = '33333333-3333-3333-3333-333333337001';

-- Activité DANS la période S1 : 750 + 3250 = 4000 kg -> 4.0000 tCO2e exactement.
INSERT INTO public.project_activity_logs (id, project_id, activity_type, ghg_reduction_kgco2e, "timestamp")
VALUES
    ('33333333-3333-3333-3333-333333338001', '33333333-3333-3333-3333-333333336001', 'transport', 750.0, '2026-01-10'::timestamptz),
    ('33333333-3333-3333-3333-333333338002', '33333333-3333-3333-3333-333333336001', 'recyclage', 3250.0, '2026-01-20'::timestamptz),
    -- HORS période S1 (avant reporting_period_start) — doit être exclue du calcul.
    ('33333333-3333-3333-3333-333333338003', '33333333-3333-3333-3333-333333336001', 'transport', 999999.0, '2025-12-01'::timestamptz);

-- S3 (février 2026) : vérificateur assigné, activité 1000 kg -> 1.0000 tCO2e.
UPDATE public.verification_sessions
SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned'),
    reporting_period_start = '2026-02-01', reporting_period_end = '2026-02-28',
    status = 'in_progress'
WHERE id = '33333333-3333-3333-3333-333333337003';

INSERT INTO public.project_activity_logs (id, project_id, activity_type, ghg_reduction_kgco2e, "timestamp")
VALUES ('33333333-3333-3333-3333-333333338004', '33333333-3333-3333-3333-333333336001', 'recyclage', 1000.0, '2026-02-15'::timestamptz);

-- S4 (mars 2026) : vérificateur assigné, AUCUNE activité (calculated = 0).
UPDATE public.verification_sessions
SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned'),
    reporting_period_start = '2026-03-01', reporting_period_end = '2026-03-31',
    status = 'in_progress'
WHERE id = '33333333-3333-3333-3333-333333337004';

-- S2 (avril 2026) : période renseignée, verifier_user_id délibérément NULL —
-- seul le super-admin peut donc atteindre l'intérieur de la RPC (is_assigned_verifier()
-- ne peut jamais être vraie tant que verifier_user_id est NULL).
UPDATE public.verification_sessions
SET reporting_period_start = '2026-04-01', reporting_period_end = '2026-04-30',
    status = 'in_progress'
WHERE id = '33333333-3333-3333-3333-333333337002';

-- ────────────────────────────────────────────────────────────
-- 3. PORTE D'AUTHENTIFICATION / D'AUTORISATION / DE PRÉPARATION DE SESSION
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert_raises('B1', 'complete_verification_session() rejette un appelant non authentifié',
        format($sql$SELECT public.complete_verification_session(%L, 4, 4, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337001'),
        'Authentification requise');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B2', 'complete_verification_session() rejette un appelant authentifié ni vérificateur assigné ni super-admin',
        format($sql$SELECT public.complete_verification_session(%L, 4, 4, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337001'),
        'Accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    -- S6 : status encore 'planned' à ce stade (jamais touchée par les fixtures
    -- ci-dessus) — teste le rejet "planned rencontré" avant même la
    -- vérification de période/vérificateur.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B3', 'complete_verification_session() rejette une session encore planned',
        format($sql$SELECT public.complete_verification_session(%L, 4, 4, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337006'),
        'planned rencontré');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    -- S2 : in_progress, période renseignée, verifier_user_id NULL — seul le
    -- super-admin atteint cette branche (is_assigned_verifier() ne peut
    -- jamais être vraie tant que verifier_user_id est NULL).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B4', 'complete_verification_session() rejette une session sans vérificateur assigné',
        format($sql$SELECT public.complete_verification_session(%L, 4, 4, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337002'),
        'aucun vérificateur assigné');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 4. CHEMIN DE SUCCÈS (S1) — calcul, arrondi, journalisation, transition
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_outcome_id UUID;
    v_calculated NUMERIC;
    v_verified   NUMERIC;
    v_eligible   NUMERIC;
    v_supersedes UUID;
    v_verified_by UUID;
    v_status_id  TEXT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    v_outcome_id := public.complete_verification_session('33333333-3333-3333-3333-333333337001', 4, 4, NULL, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM set_config('carbon_test.outcome_s1_v1', v_outcome_id::text, false);

    SELECT calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, supersedes_outcome_id, verified_by, status
    INTO v_calculated, v_verified, v_eligible, v_supersedes, v_verified_by, v_status_id
    FROM public.verification_outcomes WHERE id = v_outcome_id;

    PERFORM pg_temp.carbon_test_assert('B5', 'calculated_reduction_tco2e = 4.0000 (750+3250 kg dans la période, 999999 kg hors période exclue)',
        v_calculated = 4.0000, v_calculated::text);
    PERFORM pg_temp.carbon_test_assert('B6', 'résultat créé : status=active, supersedes_outcome_id NULL, verified_by=vérificateur assigné',
        v_status_id = 'active' AND v_supersedes IS NULL AND v_verified_by = pg_temp.carbon_test_profile('verifier_assigned'));

    PERFORM pg_temp.carbon_test_assert('B7', 'verification_sessions S1 transitionne à completed',
        (SELECT status::text FROM public.verification_sessions WHERE id = '33333333-3333-3333-3333-333333337001') = 'completed');

    PERFORM pg_temp.carbon_test_assert('B8', 'événement verification_session_completed journalisé',
        EXISTS (SELECT 1 FROM public.carbon_business_events
                WHERE event_type = 'verification_session_completed' AND object_type = 'verification_session'
                  AND object_id = '33333333-3333-3333-3333-333333337001'));

    PERFORM pg_temp.carbon_test_assert('B9', 'événement verification_outcome_recorded journalisé (pas superseded, premier résultat)',
        EXISTS (SELECT 1 FROM public.carbon_business_events
                WHERE event_type = 'verification_outcome_recorded' AND object_type = 'verification_outcome'
                  AND object_id = v_outcome_id AND verification_session_id = '33333333-3333-3333-3333-333333337001'));
END $$;

-- ────────────────────────────────────────────────────────────
-- 5. SUPERSESSION (S1, deuxième appel)
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B10', 'supersession sans adjustment_reason rejetée (obligatoire dès qu''un résultat actif existe)',
        format($sql$SELECT public.complete_verification_session(%L, 5, 5, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337001'),
        'adjustment_reason est obligatoire pour corriger');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_outcome_id UUID;
    v_status_old TEXT;
    v_active_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    v_outcome_id := public.complete_verification_session('33333333-3333-3333-3333-333333337001', 5, 5, NULL, 'Correction test B11');
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT status INTO v_status_old FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v1', true), '')::UUID;
    SELECT count(*) INTO v_active_count FROM public.verification_outcomes WHERE verification_session_id = '33333333-3333-3333-3333-333333337001' AND status = 'active';

    PERFORM pg_temp.carbon_test_assert('B11', 'supersession avec adjustment_reason réussit : nouveau résultat actif, ancien superseded, un seul actif',
        v_status_old = 'superseded' AND v_active_count = 1);

    PERFORM pg_temp.carbon_test_assert('B12', 'nouveau résultat référence l''ancien VERS L''ARRIÈRE (supersedes_outcome_id)',
        (SELECT supersedes_outcome_id FROM public.verification_outcomes WHERE id = v_outcome_id)::text = current_setting('carbon_test.outcome_s1_v1', true));

    PERFORM pg_temp.carbon_test_assert('B13', 'événement verification_outcome_superseded journalisé (pas recorded, résultat actif préexistant)',
        EXISTS (SELECT 1 FROM public.carbon_business_events
                WHERE event_type = 'verification_outcome_superseded' AND object_type = 'verification_outcome' AND object_id = v_outcome_id));

    PERFORM set_config('carbon_test.outcome_s1_v2', v_outcome_id::text, false);
END $$;

-- ────────────────────────────────────────────────────────────
-- 6. DIVERGENCE > 1 % (S3) et NaN / eligible > verified (S4)
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B14', 'divergence > 1%% de la valeur calculée suggérée sans adjustment_reason rejetée (S3 : calculé 1.0, fourni 2.0)',
        format($sql$SELECT public.complete_verification_session(%L, 2, 2, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337003'),
        'diverge de plus de 1%');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_outcome_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    v_outcome_id := public.complete_verification_session('33333333-3333-3333-3333-333333337003', 2, 2, NULL, 'Écart justifié test B15');
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B15', 'divergence > 1%% AVEC adjustment_reason réussit',
        v_outcome_id IS NOT NULL);
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B16', 'verified_reduction_tco2e = NaN rejeté (S4)',
        format($sql$SELECT public.complete_verification_session(%L, 'NaN'::numeric, 1, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337004'),
        'NaN interdit');
    PERFORM pg_temp.carbon_test_assert_raises('B17', 'eligible_tco2e = NaN rejeté (S4)',
        format($sql$SELECT public.complete_verification_session(%L, 1, 'NaN'::numeric, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337004'),
        'NaN interdit');
    PERFORM pg_temp.carbon_test_assert_raises('B18', 'eligible_tco2e > verified_reduction_tco2e rejeté (S4)',
        format($sql$SELECT public.complete_verification_session(%L, 5, 10, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337004'),
        'ne peut pas dépasser');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 7. STRUCTUREL — CHECK completed, EXCLUDE périodes, garde UPDATE, DELETE,
--    doublon actif par INSERT direct.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    -- S6 : ni période ni vérificateur — CHECK rejette le passage direct à completed.
    PERFORM pg_temp.carbon_test_assert_raises('B19', 'UPDATE direct : status=completed sans période ni vérificateur rejeté (CHECK)',
        format($sql$UPDATE public.verification_sessions SET status = 'completed' WHERE id = %L$sql$,
               '33333333-3333-3333-3333-333333337006'),
        'verification_sessions_completed_requires_period_and_verifier');
END $$;

DO $$
BEGIN
    -- S5 : période 15-20 janvier 2026, chevauche S1 (1-31 janvier, déjà
    -- completed) — même projet. Vérificateur assigné directement (bypass),
    -- puis tentative de passage à completed.
    UPDATE public.verification_sessions
    SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned'),
        reporting_period_start = '2026-01-15', reporting_period_end = '2026-01-20'
    WHERE id = '33333333-3333-3333-3333-333333337005';

    PERFORM pg_temp.carbon_test_assert_raises('B20', 'UPDATE direct : status=completed avec période chevauchant une autre session completed du même projet rejeté (EXCLUDE)',
        format($sql$UPDATE public.verification_sessions SET status = 'completed' WHERE id = %L$sql$,
               '33333333-3333-3333-3333-333333337005'),
        'verification_sessions_no_overlapping_completed_periods');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B21', 'INSERT direct : second résultat actif pour une session qui en a déjà un rejeté (index unique partiel)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verified_by) VALUES (%L, 1, 1, 1, %L)$sql$,
               '33333333-3333-3333-3333-333333337001', pg_temp.carbon_test_profile('verifier_assigned')),
        'idx_verification_outcomes_one_active_per_session');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B22', 'UPDATE direct : re-tenter status=active sur un résultat déjà superseded rejeté (terminal)',
        format($sql$UPDATE public.verification_outcomes SET status = 'active' WHERE id = %L$sql$,
               current_setting('carbon_test.outcome_s1_v1', true)),
        'déjà superseded');
    PERFORM pg_temp.carbon_test_assert_raises('B23', 'UPDATE direct : changement de verified_reduction_tco2e simultané à une transition de status rejeté',
        format($sql$UPDATE public.verification_outcomes SET status = 'superseded', verified_reduction_tco2e = 99 WHERE id = %L$sql$,
               current_setting('carbon_test.outcome_s1_v2', true)),
        'seule la colonne status');
    PERFORM pg_temp.carbon_test_assert_raises('B24', 'DELETE direct rejeté (append-only)',
        format($sql$DELETE FROM public.verification_outcomes WHERE id = %L$sql$,
               current_setting('carbon_test.outcome_s1_v2', true)));
END $$;

-- ────────────────────────────────────────────────────────────
-- 8. RLS verification_outcomes — audience alignée sur verification_sessions
--    + vérificateur assigné, sous le rôle réel `authenticated`.
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('project_admin'), 'project_admin');
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B25', 'RLS : admin de projet (is_project_admin()) voit le résultat',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('project_client'), 'project_client');
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B26', 'RLS : client de projet (is_project_client()) voit le résultat',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B27', 'RLS : vérificateur assigné à la session voit le résultat',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    -- verifier_other : rôle JWT 'verifier' générique, mais PAS assigné à
    -- CETTE session précise (verification_sessions.verifier_user_id pointe
    -- vers verifier_assigned, pas verifier_other) — is_assigned_verifier()
    -- doit renvoyer faux pour ce profil sur cette session.
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('verifier_other'), 'verifier');
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B28', 'RLS : vérificateur NON assigné à cette session précise (rôle verifier générique) NE voit PAS le résultat',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B29', 'RLS : appelant sans aucune relation (ni admin/client/vérificateur/super-admin) NE voit PAS le résultat',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), true);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B30', 'RLS : super-admin plateforme voit le résultat indépendamment de toute relation',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 9. RLS verification_sessions — nouvelle policy UPDATE réservée au
--    vérificateur assigné (§10, section 4 de la migration).
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    SET LOCAL ROLE authenticated;
    UPDATE public.verification_sessions SET comments = 'test B31' WHERE id = '33333333-3333-3333-3333-333333337001';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B31', 'RLS UPDATE : le vérificateur assigné peut modifier sa propre session',
        (SELECT comments FROM public.verification_sessions WHERE id = '33333333-3333-3333-3333-333333337001') = 'test B31');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_updated_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('verifier_other'), 'verifier');
    SET LOCAL ROLE authenticated;
    UPDATE public.verification_sessions SET comments = 'contournement B32' WHERE id = '33333333-3333-3333-3333-333333337001';
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B32', 'RLS UPDATE : un vérificateur NON assigné à cette session NE peut PAS la modifier (0 ligne affectée, RLS silencieuse plutôt qu''erreur)',
        v_updated_count = 0, v_updated_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 10. GATE FINAL — count(*) ET count(DISTINCT section), aucun échec.
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_total    INT;
    v_distinct INT;
    v_failed   INT;
BEGIN
    SELECT count(*), count(DISTINCT section), count(*) FILTER (WHERE NOT passed)
    INTO v_total, v_distinct, v_failed
    FROM public._carbon_migration_test_results;

    IF v_total <> 46 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertions exécutées, 46 attendues (test manquant, label dupliqué, ou bloc non exécuté).', v_total;
    END IF;

    IF v_distinct <> 46 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % labels DISTINCTS sur % lignes totales (46 attendus pour les deux) — un label a été exécuté plus d''une fois, masquant potentiellement un test jamais atteint.', v_distinct, v_total;
    END IF;

    IF v_failed <> 0 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertion(s) sur 46 ont échoué (0 attendu). Voir le résumé détaillé ci-dessous pour l''identification.', v_failed;
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────
-- 11. RÉSUMÉ — affiché AVANT le ROLLBACK.
--     NOMBRE D'ASSERTIONS ATTENDU (recompté mécaniquement, script Python
--     regex + Counter, même discipline que tests/04/tests/07) : 46 —
--     14 prévalidations (A1-A14) + 32 tests comportementaux (B1-B32), tous
--     labels distincts, aucun doublon.
-- ────────────────────────────────────────────────────────────

SELECT
    (SELECT count(*) FROM public._carbon_migration_test_results) AS total_assertions,
    (SELECT count(*) FILTER (WHERE NOT passed) FROM public._carbon_migration_test_results) AS failed_assertions;

SELECT section, assertion, passed, detail
FROM public._carbon_migration_test_results
ORDER BY id;

ROLLBACK;
