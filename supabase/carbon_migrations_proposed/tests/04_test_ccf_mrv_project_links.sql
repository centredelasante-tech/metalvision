-- ============================================================
-- Tests — Migration 04 (ccf_mrv_project_links)
-- ============================================================
--
-- STATUT : PROPOSITION SOUMISE POUR REVUE — NON EXÉCUTÉE.
-- À exécuter APRÈS avoir appliqué 04_carbon_ccf_mrv_project_links.sql,
-- jamais avant. Même discipline que les tests 02/07 : script de validation
-- SÉPARÉ de la migration elle-même, jamais mélangé.
--
-- STRUCTURE : script encapsulé dans un unique BEGIN; ... ROLLBACK; explicite
-- (même patron que tests/07). Le résumé (section 5) est affiché AVANT le
-- ROLLBACK. Aucune donnée créée par ce script ne persiste après son
-- exécution.
--
-- FIXTURES — deux groupes délibérément isolés, préfixes distincts pour éviter
-- toute confusion de portée :
--   • '22222222-...-...480x'/'...490x'/'...500x' (« lifecycle ») — utilisées
--     pour les tests structurels/comportementaux du cycle de vie du lien
--     (création, doublon, contournement direct, garde UPDATE, rupture,
--     re-création). Coordinateur A (org '...4101') / unité opérationnelle 1
--     (org '...4102') pour le lien principal ; coordinateur B (org '...4103')
--     / unité opérationnelle 2 (org '...4104') pour les tentatives de doublon
--     côté opposé.
--   • '...4111'-'...4115'/'...4903'/'...5003'/'...4803' (« RLS ») — cinq
--     organisations aux relations distinctes (coordinatrice, unité
--     opérationnelle, participante active, participante invitée seulement,
--     externe sans relation) autour d'un SEUL lien dédié, pour isoler
--     proprement chaque branche de can_view_ccf_mrv_project_link().
--
-- Profils : RÉUTILISATION de 6 profils réels existants (même motif que
-- tests/07 — profiles.id référence réellement auth.users(id), fabriquer des
-- lignes profiles avec des UUID arbitraires violerait cette FK). Fixture
-- MANDATORY, échoue immédiatement si moins de 6 profils réels distincts sont
-- disponibles.
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. Table de résultats + helpers d'assertion et de simulation d'acteur
--    (même patron exact que tests/07_test_carbon_issuances.sql section 0)
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

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_clear_actor() RETURNS VOID
LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims', '{}', true);
$$;

-- ────────────────────────────────────────────────────────────
-- 1. PRÉVALIDATION — structure attendue de la migration 04
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert('A1', 'table ccf_mrv_project_links existe',
        to_regclass('public.ccf_mrv_project_links') IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('A2', 'RLS activé sur ccf_mrv_project_links',
        COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname = 'ccf_mrv_project_links' AND relnamespace = 'public'::regnamespace), false));
    PERFORM pg_temp.carbon_test_assert('A3', 'index unique partiel (ccf_project_id, ended_at IS NULL) présent avec la définition attendue',
        EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = 'public' AND tablename = 'ccf_mrv_project_links'
              AND indexname = 'idx_ccf_mrv_project_links_one_active_per_ccf'
              AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%ccf_project_id%' AND indexdef ILIKE '%ended_at IS NULL%'
        ));
    PERFORM pg_temp.carbon_test_assert('A4', 'index unique partiel (mrv_project_id, ended_at IS NULL) présent avec la définition attendue',
        EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = 'public' AND tablename = 'ccf_mrv_project_links'
              AND indexname = 'idx_ccf_mrv_project_links_one_active_per_mrv'
              AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%mrv_project_id%' AND indexdef ILIKE '%ended_at IS NULL%'
        ));
    PERFORM pg_temp.carbon_test_assert('A5', 'CHECK ended_at >= started_at présent',
        EXISTS (
            SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
            WHERE t.relname = 'ccf_mrv_project_links' AND c.contype = 'c'
              AND pg_get_constraintdef(c.oid) ILIKE '%ended_at%started_at%'
        ));
    PERFORM pg_temp.carbon_test_assert('A6', 'RPC link_ccf_project_to_mrv(uuid,uuid)/unlink_ccf_project_from_mrv(uuid,text) existent',
        to_regprocedure('public.link_ccf_project_to_mrv(uuid,uuid)') IS NOT NULL
        AND to_regprocedure('public.unlink_ccf_project_from_mrv(uuid,text)') IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('A7', 'privilèges : authenticated=EXECUTE, anon=aucun sur les deux RPC',
        (SELECT bool_and(
            has_function_privilege('authenticated', p.oid, 'EXECUTE')
            AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
         )
         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN ('link_ccf_project_to_mrv', 'unlink_ccf_project_from_mrv')));
    PERFORM pg_temp.carbon_test_assert('A8', 'helper RLS can_view_ccf_mrv_project_link(uuid,uuid) existe, EXECUTE authenticated',
        to_regprocedure('public.can_view_ccf_mrv_project_link(uuid,uuid)') IS NOT NULL
        AND has_function_privilege('authenticated', 'public.can_view_ccf_mrv_project_link(uuid,uuid)'::regprocedure, 'EXECUTE'));
    PERFORM pg_temp.carbon_test_assert('A9', 'triggers guard_update/reject_delete existent',
        EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'ccf_mrv_project_links' AND tg.tgname = 'ccf_mrv_project_links_guard_update')
        AND EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'ccf_mrv_project_links' AND tg.tgname = 'ccf_mrv_project_links_reject_delete'));
    PERFORM pg_temp.carbon_test_assert('A10', 'privilèges de table : authenticated a SELECT seulement (aucun INSERT/UPDATE/DELETE)',
        has_table_privilege('authenticated', 'public.ccf_mrv_project_links', 'SELECT')
        AND NOT has_table_privilege('authenticated', 'public.ccf_mrv_project_links', 'INSERT')
        AND NOT has_table_privilege('authenticated', 'public.ccf_mrv_project_links', 'UPDATE')
        AND NOT has_table_privilege('authenticated', 'public.ccf_mrv_project_links', 'DELETE'));
    PERFORM pg_temp.carbon_test_assert('A11', 'unlink_ccf_project_from_mrv() verrouille la ligne (FOR UPDATE) avant transition',
        pg_get_functiondef('public.unlink_ccf_project_from_mrv(uuid,text)'::regprocedure) ILIKE '%FOR UPDATE%');
END $$;

-- ────────────────────────────────────────────────────────────
-- 2. FIXTURES
-- ────────────────────────────────────────────────────────────

-- Groupe « lifecycle » — lien principal (A/1) + côté opposé pour les
-- tentatives de doublon (B/2).
INSERT INTO public.organizations (id, name, status)
VALUES
    ('22222222-2222-2222-2222-222222224101', 'TEST-04 Coordinatrice A', 'active'),
    ('22222222-2222-2222-2222-222222224102', 'TEST-04 Unite Operationnelle 1', 'active'),
    ('22222222-2222-2222-2222-222222224103', 'TEST-04 Coordinatrice B', 'active'),
    ('22222222-2222-2222-2222-222222224104', 'TEST-04 Unite Operationnelle 2', 'active');

INSERT INTO public.opportunities (id, title, coordinator_org_id)
VALUES
    ('22222222-2222-2222-2222-222222224700', 'TEST-04 Opportunite A', '22222222-2222-2222-2222-222222224101'),
    ('22222222-2222-2222-2222-222222224701', 'TEST-04 Opportunite B', '22222222-2222-2222-2222-222222224103');

INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id)
VALUES
    ('22222222-2222-2222-2222-222222224801', '22222222-2222-2222-2222-222222224700', 'TEST-04 Projet CCF A', '22222222-2222-2222-2222-222222224101'),
    ('22222222-2222-2222-2222-222222224802', '22222222-2222-2222-2222-222222224701', 'TEST-04 Projet CCF B', '22222222-2222-2222-2222-222222224103');

INSERT INTO public.operational_units (id, organization_id)
VALUES
    ('22222222-2222-2222-2222-222222224901', '22222222-2222-2222-2222-222222224102'),
    ('22222222-2222-2222-2222-222222224902', '22222222-2222-2222-2222-222222224104');

INSERT INTO public.projects (id, operational_unit_id, name)
VALUES
    ('22222222-2222-2222-2222-222222225001', '22222222-2222-2222-2222-222222224901', 'TEST-04 Projet MRV 1'),
    ('22222222-2222-2222-2222-222222225002', '22222222-2222-2222-2222-222222224902', 'TEST-04 Projet MRV 2');

-- Groupe « RLS » — un seul lien, cinq relations organisationnelles distinctes.
INSERT INTO public.organizations (id, name, status)
VALUES
    ('22222222-2222-2222-2222-222222224111', 'TEST-04 Coordinatrice RLS', 'active'),
    ('22222222-2222-2222-2222-222222224112', 'TEST-04 Unite Operationnelle RLS', 'active'),
    ('22222222-2222-2222-2222-222222224113', 'TEST-04 Participante active RLS', 'active'),
    ('22222222-2222-2222-2222-222222224114', 'TEST-04 Participante invitee RLS', 'active'),
    ('22222222-2222-2222-2222-222222224115', 'TEST-04 Externe RLS', 'active');

INSERT INTO public.opportunities (id, title, coordinator_org_id)
VALUES ('22222222-2222-2222-2222-222222224702', 'TEST-04 Opportunite RLS', '22222222-2222-2222-2222-222222224111');

INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id)
VALUES ('22222222-2222-2222-2222-222222224803', '22222222-2222-2222-2222-222222224702', 'TEST-04 Projet CCF RLS', '22222222-2222-2222-2222-222222224111');

INSERT INTO public.project_participants (id, project_id, organization_id, status)
VALUES
    ('22222222-2222-2222-2222-222222224821', '22222222-2222-2222-2222-222222224803', '22222222-2222-2222-2222-222222224113', 'active'),
    ('22222222-2222-2222-2222-222222224822', '22222222-2222-2222-2222-222222224803', '22222222-2222-2222-2222-222222224114', 'invited');

INSERT INTO public.operational_units (id, organization_id)
VALUES ('22222222-2222-2222-2222-222222224903', '22222222-2222-2222-2222-222222224112');

INSERT INTO public.projects (id, operational_unit_id, name)
VALUES ('22222222-2222-2222-2222-222222225003', '22222222-2222-2222-2222-222222224903', 'TEST-04 Projet MRV RLS');

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

    PERFORM set_config('carbon_test.profile_superadmin',           v_profile_ids[1]::text, false);
    PERFORM set_config('carbon_test.profile_coord_rls',             v_profile_ids[2]::text, false);
    PERFORM set_config('carbon_test.profile_mrv_rls',               v_profile_ids[3]::text, false);
    PERFORM set_config('carbon_test.profile_participant_active',    v_profile_ids[4]::text, false);
    PERFORM set_config('carbon_test.profile_participant_invited',   v_profile_ids[5]::text, false);
    PERFORM set_config('carbon_test.profile_outsider',              v_profile_ids[6]::text, false);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_profile(p_key TEXT) RETURNS UUID
LANGUAGE sql AS $$ SELECT current_setting('carbon_test.profile_' || p_key)::UUID $$;

INSERT INTO public.organization_members (id, organization_id, user_id, org_role, status, activated_at)
VALUES
    ('22222222-2222-2222-2222-222222224a01', '22222222-2222-2222-2222-222222224111', pg_temp.carbon_test_profile('coord_rls'),           'admin', 'active', clock_timestamp() - interval '10 days'),
    ('22222222-2222-2222-2222-222222224a02', '22222222-2222-2222-2222-222222224112', pg_temp.carbon_test_profile('mrv_rls'),              'admin', 'active', clock_timestamp() - interval '10 days'),
    ('22222222-2222-2222-2222-222222224a03', '22222222-2222-2222-2222-222222224113', pg_temp.carbon_test_profile('participant_active'),   'admin', 'active', clock_timestamp() - interval '10 days'),
    ('22222222-2222-2222-2222-222222224a04', '22222222-2222-2222-2222-222222224114', pg_temp.carbon_test_profile('participant_invited'),  'admin', 'active', clock_timestamp() - interval '10 days'),
    ('22222222-2222-2222-2222-222222224a05', '22222222-2222-2222-2222-222222224115', pg_temp.carbon_test_profile('outsider'),             'admin', 'active', clock_timestamp() - interval '10 days');

-- ────────────────────────────────────────────────────────────
-- 3. TESTS COMPORTEMENTAUX — porte d'authentification et d'autorisation
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert_raises('B1', 'link_ccf_project_to_mrv() rejette un appelant non authentifié',
        format($sql$SELECT public.link_ccf_project_to_mrv(%L, %L)$sql$,
               '22222222-2222-2222-2222-222222224801', '22222222-2222-2222-2222-222222225001'),
        'Authentification requise');
    PERFORM pg_temp.carbon_test_assert_raises('B2', 'unlink_ccf_project_from_mrv() rejette un appelant non authentifié',
        format($sql$SELECT public.unlink_ccf_project_from_mrv(%L, NULL)$sql$,
               '22222222-2222-2222-2222-222222224801'),
        'Authentification requise');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B3', 'link_ccf_project_to_mrv() rejette un appelant authentifié non super-admin',
        format($sql$SELECT public.link_ccf_project_to_mrv(%L, %L)$sql$,
               '22222222-2222-2222-2222-222222224801', '22222222-2222-2222-2222-222222225001'),
        'super-administrateur');
    PERFORM pg_temp.carbon_test_assert_raises('B4', 'unlink_ccf_project_from_mrv() rejette un appelant authentifié non super-admin',
        format($sql$SELECT public.unlink_ccf_project_from_mrv(%L, NULL)$sql$,
               '22222222-2222-2222-2222-222222224801'),
        'super-administrateur');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B5', 'link_ccf_project_to_mrv() rejette un ccf_project_id inexistant',
        format($sql$SELECT public.link_ccf_project_to_mrv(gen_random_uuid(), %L)$sql$,
               '22222222-2222-2222-2222-222222225001'),
        'aucun projet CCF existant');
    PERFORM pg_temp.carbon_test_assert_raises('B6', 'link_ccf_project_to_mrv() rejette un mrv_project_id inexistant',
        format($sql$SELECT public.link_ccf_project_to_mrv(%L, gen_random_uuid())$sql$,
               '22222222-2222-2222-2222-222222224801'),
        'aucun projet MRV existant');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 4. CHEMIN DE SUCCÈS — création, événement, doublons rejetés
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_link_id UUID;
    v_ended_at TIMESTAMPTZ;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    v_link_id := public.link_ccf_project_to_mrv('22222222-2222-2222-2222-222222224801', '22222222-2222-2222-2222-222222225001');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM set_config('carbon_test.link_a', v_link_id::text, false);

    SELECT ended_at INTO v_ended_at FROM public.ccf_mrv_project_links WHERE id = v_link_id;

    PERFORM pg_temp.carbon_test_assert('B7', 'lien créé avec succès, ended_at NULL',
        v_link_id IS NOT NULL AND v_ended_at IS NULL);

    PERFORM pg_temp.carbon_test_assert('B8', 'événement ccf_mrv_link_started journalisé avec object_type/payload corrects',
        EXISTS (
            SELECT 1 FROM public.carbon_business_events
            WHERE event_type = 'ccf_mrv_link_started'
              AND object_type = 'ccf_mrv_project_link'
              AND object_id = v_link_id
              AND (payload->>'ccf_project_id')::UUID = '22222222-2222-2222-2222-222222224801'
              AND (payload->>'mrv_project_id')::UUID = '22222222-2222-2222-2222-222222225001'
        ));
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B9', 'link_ccf_project_to_mrv() rejette un second lien pour un ccf_project_id déjà effectif',
        format($sql$SELECT public.link_ccf_project_to_mrv(%L, %L)$sql$,
               '22222222-2222-2222-2222-222222224801', '22222222-2222-2222-2222-222222225002'),
        'déjà un lien MRV effectif');
    PERFORM pg_temp.carbon_test_assert_raises('B10', 'link_ccf_project_to_mrv() rejette un second lien pour un mrv_project_id déjà effectif',
        format($sql$SELECT public.link_ccf_project_to_mrv(%L, %L)$sql$,
               '22222222-2222-2222-2222-222222224802', '22222222-2222-2222-2222-222222225001'),
        'déjà un lien CCF effectif');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 5. CONTOURNEMENT DIRECT — filet structurel des deux index uniques
--    partiels, indépendant des pré-vérifications de la RPC.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B11', 'INSERT direct : second lien effectif pour le même ccf_project_id rejeté (index unique partiel)',
        format($sql$INSERT INTO public.ccf_mrv_project_links (ccf_project_id, mrv_project_id) VALUES (%L, %L)$sql$,
               '22222222-2222-2222-2222-222222224801', '22222222-2222-2222-2222-222222225002'),
        'idx_ccf_mrv_project_links_one_active_per_ccf');
    PERFORM pg_temp.carbon_test_assert_raises('B12', 'INSERT direct : second lien effectif pour le même mrv_project_id rejeté (index unique partiel)',
        format($sql$INSERT INTO public.ccf_mrv_project_links (ccf_project_id, mrv_project_id) VALUES (%L, %L)$sql$,
               '22222222-2222-2222-2222-222222224802', '22222222-2222-2222-2222-222222225001'),
        'idx_ccf_mrv_project_links_one_active_per_mrv');
END $$;

-- ────────────────────────────────────────────────────────────
-- 6. GARDE UPDATE — seule transition permise : ended_at NULL -> valeur,
--    aucune autre colonne modifiable. Même patron que
--    carbon_guard_aggregator_membership_update (migration 02, tests B6/B7).
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B13', 'UPDATE direct : ended_at renseigné SIMULTANÉMENT à un changement de ccf_project_id rejeté',
        format($sql$UPDATE public.ccf_mrv_project_links SET ccf_project_id = %L, ended_at = clock_timestamp() WHERE id = %L$sql$,
               '22222222-2222-2222-2222-222222224802', current_setting('carbon_test.link_a', true)),
        'seules les colonnes ended_at');
    PERFORM pg_temp.carbon_test_assert_raises('B14', 'UPDATE direct : changement de mrv_project_id SANS toucher ended_at rejeté',
        format($sql$UPDATE public.ccf_mrv_project_links SET mrv_project_id = %L WHERE id = %L$sql$,
               '22222222-2222-2222-2222-222222225002', current_setting('carbon_test.link_a', true)),
        'seule la transition de ended_at');
END $$;

-- ────────────────────────────────────────────────────────────
-- 7. RUPTURE DU LIEN — chemin de succès, événement, contre-épreuves
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_returned_id UUID;
    v_ended_at    TIMESTAMPTZ;
    v_ended_by    UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    v_returned_id := public.unlink_ccf_project_from_mrv('22222222-2222-2222-2222-222222224801', 'Fin de test B15');
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT ended_at, ended_by INTO v_ended_at, v_ended_by
    FROM public.ccf_mrv_project_links WHERE id = v_returned_id;

    PERFORM pg_temp.carbon_test_assert('B15', 'unlink_ccf_project_from_mrv() réussit : ended_at/ended_by renseignés, id du lien retourné',
        v_returned_id::text = current_setting('carbon_test.link_a', true)
        AND v_ended_at IS NOT NULL AND v_ended_by = pg_temp.carbon_test_profile('superadmin'));

    PERFORM pg_temp.carbon_test_assert('B16', 'événement ccf_mrv_link_ended journalisé avec end_reason',
        EXISTS (
            SELECT 1 FROM public.carbon_business_events
            WHERE event_type = 'ccf_mrv_link_ended'
              AND object_type = 'ccf_mrv_project_link'
              AND object_id = v_returned_id
              AND payload->>'end_reason' = 'Fin de test B15'
        ));
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B17', 'unlink_ccf_project_from_mrv() rejette un second appel (déjà rompu)',
        format($sql$SELECT public.unlink_ccf_project_from_mrv(%L, NULL)$sql$,
               '22222222-2222-2222-2222-222222224801'),
        'Aucun lien MRV effectif');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B18', 'UPDATE direct : deuxième transition de ended_at sur un lien déjà terminé rejetée',
        format($sql$UPDATE public.ccf_mrv_project_links SET ended_at = clock_timestamp() WHERE id = %L$sql$,
               current_setting('carbon_test.link_a', true)),
        'déjà terminé');
    PERFORM pg_temp.carbon_test_assert_raises('B19', 'DELETE direct rejeté (append-only)',
        format($sql$DELETE FROM public.ccf_mrv_project_links WHERE id = %L$sql$,
               current_setting('carbon_test.link_a', true)));
END $$;

DO $$
DECLARE
    v_relink_id UUID;
BEGIN
    -- Le ccf_project_id A est désormais libre (index partiel exclut les
    -- lignes ended_at NON NULL) — un nouveau lien vers un AUTRE projet MRV
    -- doit pouvoir être établi sans heurter l'index unique partiel.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    v_relink_id := public.link_ccf_project_to_mrv('22222222-2222-2222-2222-222222224801', '22222222-2222-2222-2222-222222225002');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B20', 'un nouveau lien effectif peut être établi pour le même ccf_project_id après rupture du précédent',
        v_relink_id IS NOT NULL AND v_relink_id::text <> current_setting('carbon_test.link_a', true));
END $$;

-- ────────────────────────────────────────────────────────────
-- 8. RLS — cinq branches de can_view_ccf_mrv_project_link(), sous le rôle
--    réel `authenticated` (SET LOCAL ROLE), même discipline que tests/07.
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_rls_link_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    v_rls_link_id := public.link_ccf_project_to_mrv('22222222-2222-2222-2222-222222224803', '22222222-2222-2222-2222-222222225003');
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.link_rls', v_rls_link_id::text, false);
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('coord_rls'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.ccf_mrv_project_links WHERE id = NULLIF(current_setting('carbon_test.link_rls', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B21', 'RLS : membre de l''organisation coordinatrice du projet CCF voit le lien',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('mrv_rls'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.ccf_mrv_project_links WHERE id = NULLIF(current_setting('carbon_test.link_rls', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B22', 'RLS : membre de l''organisation de l''unité opérationnelle MRV voit le lien',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('participant_active'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.ccf_mrv_project_links WHERE id = NULLIF(current_setting('carbon_test.link_rls', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B23', 'RLS : participante ACTIVE du projet CCF (pas la coordinatrice) voit le lien',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('participant_invited'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.ccf_mrv_project_links WHERE id = NULLIF(current_setting('carbon_test.link_rls', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B24', 'RLS : participante INVITÉE seulement (status != active) NE voit PAS le lien',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.ccf_mrv_project_links WHERE id = NULLIF(current_setting('carbon_test.link_rls', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B25', 'RLS : organisation externe SANS relation NE voit PAS le lien',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), true);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.ccf_mrv_project_links WHERE id = NULLIF(current_setting('carbon_test.link_rls', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B26', 'RLS : super-admin plateforme voit le lien indépendamment de toute relation organisationnelle',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 9. PRIVILÈGES DE TABLE SOUS LE RÔLE RÉEL — écriture directe impossible
--    même pour un appelant authentifié quelconque (pas seulement l'absence
--    de policy, le GRANT lui-même).
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.carbon_test_assert_raises('B27', 'INSERT direct sous authenticated rejeté (privilège de table, pas seulement RLS)',
        format($sql$INSERT INTO public.ccf_mrv_project_links (ccf_project_id, mrv_project_id) VALUES (%L, %L)$sql$,
               '22222222-2222-2222-2222-222222224802', '22222222-2222-2222-2222-222222225002'),
        'permission denied');
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 10. GATE FINAL — count(*) ET count(DISTINCT section), aucun échec.
--     Même discipline que tests/07 (durcissement treizième revue statique).
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

    IF v_total <> 38 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertions exécutées, 38 attendues (test manquant, label dupliqué, ou bloc non exécuté).', v_total;
    END IF;

    IF v_distinct <> 38 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % labels DISTINCTS sur % lignes totales (38 attendus pour les deux) — un label a été exécuté plus d''une fois, masquant potentiellement un test jamais atteint.', v_distinct, v_total;
    END IF;

    IF v_failed <> 0 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertion(s) sur 38 ont échoué (0 attendu). Voir le résumé détaillé ci-dessous pour l''identification.', v_failed;
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────
-- 11. RÉSUMÉ — affiché AVANT le ROLLBACK.
--     NOMBRE D'ASSERTIONS ATTENDU (recompté mécaniquement, script Python
--     regex + Counter, même discipline que tests/07) : 38 — 11 prévalidations
--     (A1-A11) + 27 tests comportementaux (B1-B27), tous labels distincts,
--     aucun doublon.
-- ────────────────────────────────────────────────────────────

SELECT
    (SELECT count(*) FROM public._carbon_migration_test_results) AS total_assertions,
    (SELECT count(*) FILTER (WHERE NOT passed) FROM public._carbon_migration_test_results) AS failed_assertions;

SELECT section, assertion, passed, detail
FROM public._carbon_migration_test_results
ORDER BY id;

ROLLBACK;
