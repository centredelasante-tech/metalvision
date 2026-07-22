-- ============================================================
-- Tests — Migration 08 (credit_lots, cycle commercial)
-- ============================================================
-- STATUT : PROPOSITION SOUMISE POUR REVUE — NON EXÉCUTÉE.
--
-- Ce fichier est intégralement transactionnel (BEGIN...ROLLBACK) : Parties
-- A, A bis, fixtures et B uniquement. Aucun dblink, aucun commit de
-- fixtures, aucun CREATE EXTENSION. Le protocole de concurrence réel à deux
-- connexions physiques (60+60 sur un plafond de 100) vit dans un fichier
-- SÉPARÉ, explicitement marqué STAGING/CLONE JETABLE UNIQUEMENT — INTERDIT
-- SUR PRODUCTION : voir 08_test_carbon_lots_concurrency_STAGING_ONLY.sql.
--
-- CINQUIÈME REVUE STATIQUE — dernier changement :
--   2. La table de résultats est désormais une TEMP TABLE (pg_temp), plus
--      une table public.* persistante — voir le commentaire au point 0
--      ci-dessous pour le raisonnement.
--
-- Changements de la quatrième revue statique (retrait de la Partie C, déjà
-- en place) : contexte complet des événements (actor_id/object_type/
-- object_id/payload) sur B2e/B9d/B18b, nouvelle assertion B11c (événement
-- credit_lot_voided produit par la cascade, distinct de celui de la RPC),
-- gate recalculé à 87 assertions exactes.
--
-- DÉPENDANCES : 04/05/06/07 et 08 (08_carbon_lots_commercial_cycle.sql,
-- cinquième revue) déjà appliqués. Réutilise >= 5 profils réels distincts
-- de public.profiles (FK réelle vers auth.users — aucune ligne profiles
-- fabriquée ici).
--
-- RÉSIDUALITÉ : l'intégralité du script (Parties A/Abis/fixtures/B) est
-- transactionnelle (BEGIN...ROLLBACK) — aucune donnée résiduelle. La table
-- de résultats (pg_temp._carbon_migration_test_results) est une TEMP TABLE :
-- si le gate final échoue et que le client SQL interrompt le script avant
-- le DROP final, elle reste inspectable pour le reste de la session, PUIS
-- disparaît automatiquement à la fin de la session (jamais un artefact
-- permanent, contrairement à une table public.* qui aurait dû être
-- explicitement supprimée).
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 0. Harnais + table de résultats — créés HORS TRANSACTION (autocommit),
--    AVANT le BEGIN, pour survivre au ROLLBACK du bloc principal et rester
--    inspectable si le gate final échoue.
-- ────────────────────────────────────────────────────────────
-- TEMP TABLE (correction 2, cinquième revue statique) : les lignes
-- d'assertion elles-mêmes sont de toute façon transactionnelles (insérées
-- dans la transaction principale, donc annulées par le ROLLBACK final) —
-- une table PUBLIQUE persistante ne servait qu'à rester inspectable si le
-- gate échouait ET que le client interrompait le script avant le DROP
-- final, mais au prix de laisser un artefact PERMANENT (table publique
-- vide) dans le cas nominal où tout se déroule normalement jusqu'au DROP.
-- Une TEMP TABLE offre la même inspectabilité en cas d'interruption (elle
-- survit à un ROLLBACK, comme toute table) SANS ce risque : elle est de
-- toute façon détruite automatiquement par Postgres à la fin de la session,
-- qu'elle ait ou non été explicitement DROP.
CREATE TEMP TABLE _carbon_migration_test_results (
    id         SERIAL PRIMARY KEY,
    section    TEXT NOT NULL,
    assertion  TEXT NOT NULL,
    detail     TEXT NULL,
    passed     BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- Correctif (exécution réelle) : une TEMP TABLE n'accorde par défaut AUCUN
-- privilège à un autre rôle que son propriétaire (contrairement aux
-- fonctions, exécutables par PUBLIC par défaut). Plusieurs assertions de la
-- Partie B appellent carbon_test_assert() alors que SET LOCAL ROLE
-- authenticated est actif (ex. B5) : sans ce GRANT explicite, l'INSERT dans
-- le harnais échoue avec "permission denied for table
-- _carbon_migration_test_results", indépendamment de la logique testée.
-- Correctif (exécution réelle, approche définitive) : plutôt que d'accorder
-- pièce par pièce les privilèges TABLE puis SEQUENCE au rôle authenticated
-- (une tentative de GRANT sur la séquence a échoué avec une erreur distincte
-- et inattendue de résolution du qualificatif "pg_temp"), carbon_test_assert()
-- est rendue SECURITY DEFINER : elle écrit alors TOUJOURS avec les privilèges
-- de son propriétaire (le rôle connecté créant la session), quel que soit le
-- rôle actif (authenticated, via SET LOCAL ROLE) au moment de l'appel.
CREATE OR REPLACE FUNCTION pg_temp.carbon_test_assert(
    p_section TEXT, p_assertion TEXT, p_condition BOOLEAN, p_detail TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    INSERT INTO pg_temp._carbon_migration_test_results(section, assertion, detail, passed)
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
LANGUAGE sql AS $$ SELECT set_config('request.jwt.claims', '{}', true); $$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_strip_comments(p_src TEXT) RETURNS TEXT
LANGUAGE sql AS $$ SELECT regexp_replace(p_src, '--[^\n]*', '', 'g') $$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_has_scoped_lock(
    p_regprocedure TEXT, p_table TEXT, p_lock_mode TEXT
) RETURNS BOOLEAN
LANGUAGE sql AS $$
    SELECT pg_temp.carbon_test_strip_comments(pg_get_functiondef(p_regprocedure::regprocedure))
           ~* ('public\.' || p_table || '\y[^;]*\y' || p_lock_mode || '\y')
$$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_profile(p_key TEXT) RETURNS UUID
LANGUAGE sql AS $$ SELECT current_setting('carbon_test08.profile_' || p_key)::UUID $$;

-- Fait progresser une émission jusqu'à 'issued' via la séquence réelle des
-- 4 RPC de 07, en déchargeant les contraintes différées de 07 nécessaires
-- uniquement parce que l'appelant peut se trouver dans une transaction
-- multi-instructions (bloc principal) ; sans effet indésirable en
-- autocommit (Partie C).
CREATE OR REPLACE FUNCTION pg_temp.carbon_test_make_issued_credit_issuance(
    p_outcome_id UUID, p_org_id UUID, p_membership_id UUID, p_mandate_id UUID,
    p_quantity NUMERIC, p_actor UUID, p_registry_ref TEXT
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(p_actor, true);
    v_id := public.create_credit_issuance(p_outcome_id, jsonb_build_array(jsonb_build_object(
        'organization_id', p_org_id, 'aggregator_membership_id', p_membership_id,
        'commercialization_mandate_id', p_mandate_id, 'contributed_tco2e', p_quantity)));
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_id);
    PERFORM public.submit_credit_issuance(v_id, 'TEST-08 Registre');
    PERFORM public.record_registry_issuance(v_id, p_registry_ref, clock_timestamp());
    PERFORM pg_temp.carbon_test_clear_actor();
    RETURN v_id;
END;
$$;

-- ============================================================
-- BLOC PRINCIPAL — PARTIES A / A BIS / FIXTURES / B, transactionnel
-- (aucune Partie C ici — voir le fichier STAGING séparé, quatrième revue)
-- ============================================================
BEGIN;

-- ────────────────────────────────────────────────────────────
-- 1. PARTIE A — structurelle
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert('A', 'A1 credit_lots existe', to_regclass('public.credit_lots') IS NOT NULL);

    PERFORM pg_temp.carbon_test_assert('A', 'A2 exactement 12 colonnes',
        (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots') = 12);

    PERFORM pg_temp.carbon_test_assert('A', 'A3 project_id absente',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='project_id'));

    PERFORM pg_temp.carbon_test_assert('A', 'A4 credit_issuance_id NOT NULL + FK RESTRICT',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_lots'::regclass AND contype='f' AND conname LIKE '%credit_issuance_id%' AND confdeltype='r'));

    PERFORM pg_temp.carbon_test_assert('A', 'A5 aggregator_id NOT NULL + FK RESTRICT',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_lots'::regclass AND contype='f' AND conname LIKE '%aggregator_id%' AND confdeltype='r'));

    PERFORM pg_temp.carbon_test_assert('A', 'A6 CHECK quantity_tco2e anti-NaN',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_lots'::regclass AND contype='c' AND pg_get_constraintdef(oid) ILIKE '%quantity_tco2e%' AND pg_get_constraintdef(oid) ILIKE '%NaN%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A7 CHECK commercial_status 5 valeurs',
        EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.credit_lots'::regclass AND c.contype='c'
            AND pg_get_constraintdef(c.oid) ILIKE '%available%' AND pg_get_constraintdef(c.oid) ILIKE '%reserved%'
            AND pg_get_constraintdef(c.oid) ILIKE '%sold%' AND pg_get_constraintdef(c.oid) ILIKE '%retired%'
            AND pg_get_constraintdef(c.oid) ILIKE '%voided%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A8 CHECK void_cause 2 valeurs',
        EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.credit_lots'::regclass AND c.contype='c'
            AND pg_get_constraintdef(c.oid) ILIKE '%internal_correction%' AND pg_get_constraintdef(c.oid) ILIKE '%external_cancellation%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A9 index sur credit_issuance_id',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credit_lots' AND indexdef ILIKE '%credit_issuance_id%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A10 index sur aggregator_id',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credit_lots' AND indexdef ILIKE '%aggregator_id%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A11 index sur commercial_status',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credit_lots' AND indexdef ILIKE '%commercial_status%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A12 trigger BEFORE INSERT présent',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_lots'::regclass AND tgname='trg_carbon_guard_credit_lot_insert'));

    PERFORM pg_temp.carbon_test_assert('A', 'A13 trigger BEFORE UPDATE présent',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_lots'::regclass AND tgname='trg_carbon_credit_lots_before_update'));

    PERFORM pg_temp.carbon_test_assert('A', 'A14 trigger BEFORE DELETE présent (interdiction)',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_lots'::regclass AND tgname='trg_carbon_credit_lots_forbid_delete'));

    PERFORM pg_temp.carbon_test_assert('A', 'A15 trigger de cascade sur credit_issuances présent',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_issuances'::regclass AND tgname='trg_carbon_cascade_void_credit_lots'));

    PERFORM pg_temp.carbon_test_assert('A', 'A16 RLS activée',
        (SELECT relrowsecurity FROM pg_class WHERE oid='public.credit_lots'::regclass) = true);

    PERFORM pg_temp.carbon_test_assert('A', 'A17 exactement 1 policy (credit_lots_select)',
        (SELECT count(*) FROM pg_policy WHERE polrelid='public.credit_lots'::regclass) = 1
        AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.credit_lots'::regclass AND polname='credit_lots_select'));

    PERFORM pg_temp.carbon_test_assert('A', 'A18 issue_credit_lot() existe avec la bonne signature',
        to_regprocedure('public.issue_credit_lot(uuid,numeric,int)') IS NOT NULL);

    PERFORM pg_temp.carbon_test_assert('A', 'A19 void_credit_lot() existe avec la bonne signature',
        to_regprocedure('public.void_credit_lot(uuid,text)') IS NOT NULL);

    PERFORM pg_temp.carbon_test_assert('A', 'A20 anon sans aucun privilège sur credit_lots',
        NOT has_table_privilege('anon', 'public.credit_lots', 'SELECT')
        AND NOT has_table_privilege('anon', 'public.credit_lots', 'INSERT'));

    PERFORM pg_temp.carbon_test_assert('A', 'A21 authenticated : SELECT seul, sans INSERT/UPDATE/DELETE direct',
        has_table_privilege('authenticated', 'public.credit_lots', 'SELECT')
        AND NOT has_table_privilege('authenticated', 'public.credit_lots', 'INSERT')
        AND NOT has_table_privilege('authenticated', 'public.credit_lots', 'UPDATE')
        AND NOT has_table_privilege('authenticated', 'public.credit_lots', 'DELETE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A22 event_type porte credit_lot_underlying_issuance_cancelled',
        EXISTS (
            SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
            WHERE t.relname='carbon_business_events' AND c.contype='c'
              AND pg_get_constraintdef(c.oid) ILIKE '%credit_lot_underlying_issuance_cancelled%'
        ));

    PERFORM pg_temp.carbon_test_assert('A', 'A23 issue_credit_lot() verrouille credit_issuances (FOR UPDATE, preuve textuelle)',
        pg_temp.carbon_test_has_scoped_lock('public.issue_credit_lot(uuid,numeric,int)', 'credit_issuances', 'FOR UPDATE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A24 void_credit_lot() verrouille credit_issuances PUIS credit_lots (FOR UPDATE, preuve textuelle)',
        pg_temp.carbon_test_has_scoped_lock('public.void_credit_lot(uuid,text)', 'credit_issuances', 'FOR UPDATE')
        AND pg_temp.carbon_test_has_scoped_lock('public.void_credit_lot(uuid,text)', 'credit_lots', 'FOR UPDATE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A25 SECURITY DEFINER + search_path durci (public, pg_temp) sur les 6 fonctions de 08',
        (SELECT bool_and(p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c ILIKE '%search_path=public, pg_temp%'))
         FROM pg_proc p
         WHERE p.oid IN (
            'public.issue_credit_lot(uuid,numeric,int)'::regprocedure,
            'public.void_credit_lot(uuid,text)'::regprocedure,
            'public.can_view_credit_lot(uuid)'::regprocedure,
            'public.carbon_guard_credit_lot_insert()'::regprocedure,
            'public.carbon_credit_lots_before_update()'::regprocedure,
            'public.carbon_cascade_void_credit_lots_on_external_cancellation()'::regprocedure
         )));

    PERFORM pg_temp.carbon_test_assert('A', 'A26 EXECUTE authenticated=oui, anon=non sur issue_credit_lot/void_credit_lot/can_view_credit_lot',
        has_function_privilege('authenticated','public.issue_credit_lot(uuid,numeric,int)'::regprocedure,'EXECUTE')
        AND has_function_privilege('authenticated','public.void_credit_lot(uuid,text)'::regprocedure,'EXECUTE')
        AND has_function_privilege('authenticated','public.can_view_credit_lot(uuid)'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('anon','public.issue_credit_lot(uuid,numeric,int)'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('anon','public.void_credit_lot(uuid,text)'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('anon','public.can_view_credit_lot(uuid)'::regprocedure,'EXECUTE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A27 EXECUTE absent (authenticated ET anon) sur les 3 fonctions de trigger internes',
        NOT has_function_privilege('authenticated','public.carbon_guard_credit_lot_insert()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_credit_lots_before_update()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_cascade_void_credit_lots_on_external_cancellation()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('anon','public.carbon_guard_credit_lot_insert()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('anon','public.carbon_credit_lots_before_update()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('anon','public.carbon_cascade_void_credit_lots_on_external_cancellation()'::regprocedure,'EXECUTE'));
END $$;

-- ────────────────────────────────────────────────────────────
-- 2. PARTIE A BIS — validation de la transaction de reconstruction
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert('Abis', 'Abis1 credit_lots_legacy_pre08 n''existe plus',
        to_regclass('public.credit_lots_legacy_pre08') IS NULL);

    PERFORM pg_temp.carbon_test_assert('Abis', 'Abis2 les 3 policies legacy ont disparu',
        NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname IN ('credit_lots_superadmin_all','credit_lots_admin_all','credit_lots_member_select')));

    PERFORM pg_temp.carbon_test_assert('Abis', 'Abis3 le GRANT SELECT anon mort n''a pas été reconduit',
        NOT has_table_privilege('anon', 'public.credit_lots', 'SELECT'));

    PERFORM pg_temp.carbon_test_assert('Abis', 'Abis4 credit_lots.id est bien un uuid (schéma canonique, pas legacy)',
        (SELECT data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='id') = 'uuid');
END $$;

-- ────────────────────────────────────────────────────────────
-- 3. FIXTURES — chaîne 05/06/07 réelle et validée
-- ────────────────────────────────────────────────────────────

-- 3.1 Profils réels — >= 5 requis (correction 7 : profil dédié admin du
-- regroupement, distinct du vérificateur).
DO $$
DECLARE
    v_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_ids FROM (SELECT id FROM public.profiles ORDER BY created_at LIMIT 5) sub;
    IF COALESCE(array_length(v_ids, 1), 0) < 5 THEN
        RAISE EXCEPTION 'Fixtures impossibles : au moins 5 profils réels distincts sont requis dans public.profiles (trouvés : %).', COALESCE(array_length(v_ids, 1), 0);
    END IF;
    PERFORM set_config('carbon_test08.profile_admin',     v_ids[1]::text, false); -- admin de l'organisation opératrice
    PERFORM set_config('carbon_test08.profile_source',    v_ids[2]::text, false); -- admin de l'organisation source
    PERFORM set_config('carbon_test08.profile_verifier',  v_ids[3]::text, false); -- vérificateur assigné + accrédité
    PERFORM set_config('carbon_test08.profile_aggadmin',  v_ids[4]::text, false); -- admin du regroupement (aggregator_admins), SANS autre relation
    PERFORM set_config('carbon_test08.profile_outsider',  v_ids[5]::text, false); -- aucune relation
    PERFORM set_config('carbon_test08.profile_superadmin', v_ids[1]::text, false); -- réutilise 'admin' (JWT-only)
END $$;

-- 3.2 Organisations, regroupement.
INSERT INTO public.organizations (id, name, status) VALUES
    ('22222222-2222-2222-2222-100000000001', 'TEST-08 Source', 'active'),
    ('22222222-2222-2222-2222-100000000002', 'TEST-08 Operateur', 'active'),
    ('22222222-2222-2222-2222-100000000003', 'TEST-08 MRV (contrepartie)', 'active');

INSERT INTO public.aggregators (id, name) VALUES ('22222222-2222-2222-2222-200000000001', 'TEST-08 Regroupement');

-- 3.3 Projet CCF + opportunité (project_participants.project_id -> ccf_projects).
INSERT INTO public.opportunities (id, title, coordinator_org_id)
VALUES ('22222222-2222-2222-2222-300000000001', 'TEST-08 Opportunité', '22222222-2222-2222-2222-100000000001');
INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id)
VALUES ('22222222-2222-2222-2222-300000000002', '22222222-2222-2222-2222-300000000001', 'TEST-08 Projet CCF', '22222222-2222-2222-2222-100000000001');

-- 3.4 Projet MRV lié (verification_sessions.project_id référence réellement
-- public.projects, pas ccf_projects — même réconciliation que tests/07).
INSERT INTO public.operational_units (id, organization_id, name)
VALUES ('22222222-2222-2222-2222-400000000001', '22222222-2222-2222-2222-100000000003', 'TEST-08 Unité opérationnelle MRV');
INSERT INTO public.projects (id, operational_unit_id, name)
VALUES ('22222222-2222-2222-2222-400000000002', '22222222-2222-2222-2222-400000000001', 'TEST-08 Projet MRV');

DO $$
BEGIN
    INSERT INTO public.ccf_mrv_project_links (ccf_project_id, mrv_project_id, started_by)
    VALUES ('22222222-2222-2222-2222-300000000002', '22222222-2222-2222-2222-400000000002', pg_temp.carbon_test_profile('admin'));
END $$;

-- 3.5 Participation projet (branche source) + accréditation vérificateur +
-- admin du regroupement (correction 7 : profil DÉDIÉ, distinct du
-- vérificateur, pour isoler proprement la branche is_aggregator_admin()).
INSERT INTO public.project_participants (project_id, organization_id, status)
VALUES ('22222222-2222-2222-2222-300000000002', '22222222-2222-2222-2222-100000000001', 'active');

DO $$
BEGIN
    INSERT INTO public.accredited_verifiers (user_id, accredited_by)
    VALUES (pg_temp.carbon_test_profile('verifier'), pg_temp.carbon_test_profile('admin'));

    INSERT INTO public.aggregator_admins (id, aggregator_id, user_id, role)
    VALUES ('22222222-2222-2222-2222-950000000001', '22222222-2222-2222-2222-200000000001', pg_temp.carbon_test_profile('aggadmin'), 'co_admin');
END $$;

-- 3.6 Preuve de vérification + document de preuve (émissions terminales).
INSERT INTO public.evidence_files (id, project_id, file_url, type, file_hash)
VALUES ('22222222-2222-2222-2222-800000000001', '22222222-2222-2222-2222-400000000002', '/evidence/test-08.pdf', 'verification_report', 'sha256:test-08');

INSERT INTO public.documents (id, owner_org_id, object_type, object_id, title, status)
VALUES ('22222222-2222-2222-2222-700000000001', '22222222-2222-2222-2222-100000000002', 'organization', '22222222-2222-2222-2222-100000000002', 'TEST-08 document de preuve', 'approved');

-- 3.7 Adhésion + désignation opérateur + mandat.
INSERT INTO public.aggregator_memberships (id, organization_id, aggregator_id, started_at)
VALUES ('22222222-2222-2222-2222-500000000001', '22222222-2222-2222-2222-100000000001', '22222222-2222-2222-2222-200000000001', clock_timestamp() - interval '30 days');

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.designate_platform_operator('22222222-2222-2222-2222-100000000002');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

INSERT INTO public.carbon_commercialization_mandates (
    id, aggregator_membership_id, organization_id, aggregator_id, operator_organization_id, scope, granted_by
)
SELECT '22222222-2222-2222-2222-600000000001', '22222222-2222-2222-2222-500000000001',
       '22222222-2222-2222-2222-100000000001', '22222222-2222-2222-2222-200000000001',
       '22222222-2222-2222-2222-100000000002', ARRAY['request_issuance'], pg_temp.carbon_test_profile('superadmin');

-- 3.8 Adhésions organisationnelles réelles (org_role ENUM 'admin'/'membre').
DO $$
BEGIN
    INSERT INTO public.organization_members (id, organization_id, user_id, org_role, status, activated_at) VALUES
        ('22222222-2222-2222-2222-900000000101', '22222222-2222-2222-2222-100000000002', pg_temp.carbon_test_profile('admin'),  'admin', 'active', clock_timestamp() - interval '10 days'),
        ('22222222-2222-2222-2222-900000000102', '22222222-2222-2222-2222-100000000001', pg_temp.carbon_test_profile('source'), 'admin', 'active', clock_timestamp() - interval '10 days');
END $$;

-- 3.9 Sessions + résultats de vérification (3, périodes non chevauchantes).
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end, verifier_user_id)
SELECT '22222222-2222-2222-2222-900000000001', '22222222-2222-2222-2222-400000000002', 'completed', current_date - 60, current_date - 54,
        pg_temp.carbon_test_profile('verifier');

INSERT INTO public.verification_outcomes (id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
SELECT '22222222-2222-2222-2222-910000000001', '22222222-2222-2222-2222-900000000001', 'active', 1000, 1000, 1000,
       '22222222-2222-2222-2222-800000000001', pg_temp.carbon_test_profile('verifier');

INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end, verifier_user_id)
SELECT '22222222-2222-2222-2222-900000000002', '22222222-2222-2222-2222-400000000002', 'completed', current_date - 44, current_date - 38, pg_temp.carbon_test_profile('verifier');

INSERT INTO public.verification_outcomes (id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
SELECT '22222222-2222-2222-2222-910000000002', '22222222-2222-2222-2222-900000000002', 'active', 600, 600, 600,
       '22222222-2222-2222-2222-800000000001', pg_temp.carbon_test_profile('verifier');

-- ────────────────────────────────────────────────────────────
-- 3.10 Émissions 'issued' (via la chaîne réelle des 4 RPC) — une par usage.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_admin UUID := pg_temp.carbon_test_profile('admin');
    v_org   UUID := '22222222-2222-2222-2222-100000000001';
    v_memb  UUID := '22222222-2222-2222-2222-500000000001';
    v_mand  UUID := '22222222-2222-2222-2222-600000000001';
BEGIN
    PERFORM set_config('carbon_test08.issuance_main',
        pg_temp.carbon_test_make_issued_credit_issuance('22222222-2222-2222-2222-910000000001', v_org, v_memb, v_mand, 500, v_admin, 'TEST08-REG-MAIN')::text, false);
    PERFORM set_config('carbon_test08.issuance_cascade',
        pg_temp.carbon_test_make_issued_credit_issuance('22222222-2222-2222-2222-910000000001', v_org, v_memb, v_mand, 100, v_admin, 'TEST08-REG-CASCADE')::text, false);
    PERFORM set_config('carbon_test08.issuance_bypass',
        pg_temp.carbon_test_make_issued_credit_issuance('22222222-2222-2222-2222-910000000001', v_org, v_memb, v_mand, 80, v_admin, 'TEST08-REG-BYPASS')::text, false);
    PERFORM set_config('carbon_test08.issuance_sold',
        pg_temp.carbon_test_make_issued_credit_issuance('22222222-2222-2222-2222-910000000001', v_org, v_memb, v_mand, 60, v_admin, 'TEST08-REG-SOLD')::text, false);
    PERFORM set_config('carbon_test08.issuance_recycle',
        pg_temp.carbon_test_make_issued_credit_issuance('22222222-2222-2222-2222-910000000001', v_org, v_memb, v_mand, 50, v_admin, 'TEST08-REG-RECYCLE')::text, false);
END $$;

-- 3.11 Les 6 statuts non-issued RÉELS du catalogue (correction 8 de la
-- deuxième revue) — outcome dédié '...910000000002' (600 de plafond).
DO $$
DECLARE
    v_admin  UUID := pg_temp.carbon_test_profile('admin');
    v_org    UUID := '22222222-2222-2222-2222-100000000001';
    v_memb   UUID := '22222222-2222-2222-2222-500000000001';
    v_mand   UUID := '22222222-2222-2222-2222-600000000001';
    v_outc   UUID := '22222222-2222-2222-2222-910000000002';
    v_doc    UUID := '22222222-2222-2222-2222-700000000001';
    v_id     UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);

    -- internal.
    v_id := public.create_credit_issuance(v_outc, jsonb_build_array(jsonb_build_object(
        'organization_id', v_org, 'aggregator_membership_id', v_memb, 'commercialization_mandate_id', v_mand, 'contributed_tco2e', 20)));
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM set_config('carbon_test08.issuance_internal', v_id::text, false);

    -- eligible.
    v_id := public.create_credit_issuance(v_outc, jsonb_build_array(jsonb_build_object(
        'organization_id', v_org, 'aggregator_membership_id', v_memb, 'commercialization_mandate_id', v_mand, 'contributed_tco2e', 20)));
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_id);
    PERFORM set_config('carbon_test08.issuance_eligible', v_id::text, false);

    -- submitted.
    v_id := public.create_credit_issuance(v_outc, jsonb_build_array(jsonb_build_object(
        'organization_id', v_org, 'aggregator_membership_id', v_memb, 'commercialization_mandate_id', v_mand, 'contributed_tco2e', 20)));
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_id);
    PERFORM public.submit_credit_issuance(v_id, 'TEST-08 Registre statuts');
    PERFORM set_config('carbon_test08.issuance_submitted', v_id::text, false);

    -- externally_cancelled (via issued).
    v_id := pg_temp.carbon_test_make_issued_credit_issuance(v_outc, v_org, v_memb, v_mand, 20, v_admin, 'TEST08-REG-STAT-CANCEL');
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    PERFORM public.record_external_cancellation(v_id, current_date, 'TEST08-CANCEL-REF', v_doc);
    PERFORM set_config('carbon_test08.issuance_externally_cancelled', v_id::text, false);

    -- externally_rejected (via submitted).
    v_id := public.create_credit_issuance(v_outc, jsonb_build_array(jsonb_build_object(
        'organization_id', v_org, 'aggregator_membership_id', v_memb, 'commercialization_mandate_id', v_mand, 'contributed_tco2e', 20)));
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_id);
    PERFORM public.submit_credit_issuance(v_id, 'TEST-08 Registre statuts 2');
    PERFORM public.record_externally_rejected(v_id, current_date, 'TEST08-REJECT-REF', v_doc);
    PERFORM set_config('carbon_test08.issuance_externally_rejected', v_id::text, false);

    -- voided (internal -> voided).
    v_id := public.create_credit_issuance(v_outc, jsonb_build_array(jsonb_build_object(
        'organization_id', v_org, 'aggregator_membership_id', v_memb, 'commercialization_mandate_id', v_mand, 'contributed_tco2e', 20)));
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE; SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.void_credit_issuance(v_id, 'TEST-08 annulation interne pour test de statut');
    PERFORM set_config('carbon_test08.issuance_voided', v_id::text, false);

    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;

-- ============================================================
-- PARTIE B — comportementale
-- ============================================================

-- B1 : auth.uid() NULL rejeté (applicatif, RPC).
SELECT pg_temp.carbon_test_clear_actor();
SELECT pg_temp.carbon_test_assert_raises('B', 'B1 issue_credit_lot() sans authentification',
    format('SELECT public.issue_credit_lot(%L::uuid, 10, 2020)', current_setting('carbon_test08.issuance_main')),
    'Authentification requise');

-- B2 : issue_credit_lot() chemin nominal — APPLICATIF, rôle authenticated réel.
DO $$
DECLARE
    v_admin  UUID := pg_temp.carbon_test_profile('admin');
    v_agg    UUID := '22222222-2222-2222-2222-200000000001';
    v_new_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, false);
    SET LOCAL ROLE authenticated;
    v_new_id := public.issue_credit_lot(current_setting('carbon_test08.issuance_main')::uuid, 200, 2020);
    RESET ROLE;
    PERFORM set_config('carbon_test08.lot_main', v_new_id::text, false);
    PERFORM pg_temp.carbon_test_assert('B', 'B2a issue_credit_lot() chemin nominal (rôle authenticated réel) réussit', v_new_id IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('B', 'B2b lot créé avec commercial_status=available',
        (SELECT commercial_status FROM public.credit_lots WHERE id = v_new_id) = 'available');
    PERFORM pg_temp.carbon_test_assert('B', 'B2c aggregator_id forcé depuis l''émission parente (DB-owned)',
        (SELECT aggregator_id FROM public.credit_lots WHERE id = v_new_id) = v_agg);
    PERFORM pg_temp.carbon_test_assert('B', 'B2d created_by forcé = acteur réel',
        (SELECT created_by FROM public.credit_lots WHERE id = v_new_id) = v_admin);
    PERFORM pg_temp.carbon_test_assert('B', 'B2e événement credit_lot_issued émis avec contexte complet (actor_id/object_type/object_id/organization_id/aggregator_id/verification_session_id/payload)',
        EXISTS (
            SELECT 1 FROM public.carbon_business_events e
            WHERE e.object_id = v_new_id AND e.event_type = 'credit_lot_issued'
              AND e.object_type = 'credit_lot'
              AND e.actor_id = v_admin
              AND e.organization_id = '22222222-2222-2222-2222-100000000002'
              AND e.aggregator_id = v_agg
              AND e.verification_session_id = '22222222-2222-2222-2222-900000000001'
              AND e.payload = jsonb_build_object(
                    'credit_issuance_id', current_setting('carbon_test08.issuance_main'),
                    'quantity_tco2e', 200, 'vintage_year', 2020)
        ));
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B2a issue_credit_lot() chemin nominal (rôle authenticated réel) réussit', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B3 : DB-owned override — BYPASS STRUCTUREL (INSERT direct), rôle par défaut.
DO $$
DECLARE
    v_admin    UUID := pg_temp.carbon_test_profile('admin');
    v_outsider UUID := pg_temp.carbon_test_profile('outsider');
    v_agg      UUID := '22222222-2222-2222-2222-200000000001';
    v_new_id   UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    INSERT INTO public.credit_lots (credit_issuance_id, quantity_tco2e, vintage_year, aggregator_id, commercial_status, created_by)
    VALUES (current_setting('carbon_test08.issuance_main')::uuid, 50, 2021,
            '00000000-0000-0000-0000-000000000099'::uuid, 'sold', v_outsider)
    RETURNING id INTO v_new_id;

    PERFORM pg_temp.carbon_test_assert('B', 'B3a aggregator_id écrasé (DB-owned, bypass structurel)',
        (SELECT aggregator_id FROM public.credit_lots WHERE id = v_new_id) = v_agg);
    PERFORM pg_temp.carbon_test_assert('B', 'B3b commercial_status écrasé à available (DB-owned, bypass structurel)',
        (SELECT commercial_status FROM public.credit_lots WHERE id = v_new_id) = 'available');
    PERFORM pg_temp.carbon_test_assert('B', 'B3c created_by écrasé à l''acteur réel (DB-owned, bypass structurel)',
        (SELECT created_by FROM public.credit_lots WHERE id = v_new_id) = v_admin);
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.carbon_test_assert('B', 'B3 DB-owned override sur INSERT direct (bypass structurel)', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B4 : void_* non-NULL à l'INSERT rejeté (bypass structurel).
SELECT pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), true);
SELECT pg_temp.carbon_test_assert_raises('B', 'B4 INSERT avec void_cause non NULL rejeté (bypass structurel)',
    format('INSERT INTO public.credit_lots (credit_issuance_id, quantity_tco2e, vintage_year, void_cause) VALUES (%L::uuid, 10, 2020, ''internal_correction'')', current_setting('carbon_test08.issuance_main')),
    'déjà voided');
SELECT pg_temp.carbon_test_clear_actor();

-- B5 : quantity_tco2e NaN/<=0 rejeté (applicatif, RPC).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), false);
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM public.issue_credit_lot(current_setting('carbon_test08.issuance_main')::uuid, 0, 2020);
        PERFORM pg_temp.carbon_test_assert('B', 'B5a quantity_tco2e = 0 rejeté', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B5a quantity_tco2e = 0 rejeté', SQLERRM ILIKE '%strictement positif%', SQLERRM);
    END;
    BEGIN
        PERFORM public.issue_credit_lot(current_setting('carbon_test08.issuance_main')::uuid, 'NaN'::numeric, 2020);
        PERFORM pg_temp.carbon_test_assert('B', 'B5b quantity_tco2e NaN rejeté', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B5b quantity_tco2e NaN rejeté', SQLERRM ILIKE '%strictement positif%', SQLERRM);
    END;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B6 : vintage_year hors bornes rejeté (applicatif, RPC).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), false);
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM public.issue_credit_lot(current_setting('carbon_test08.issuance_main')::uuid, 10, 2014);
        PERFORM pg_temp.carbon_test_assert('B', 'B6a vintage_year 2014 rejeté', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B6a vintage_year 2014 rejeté', SQLERRM ILIKE '%hors bornes%', SQLERRM);
    END;
    BEGIN
        PERFORM public.issue_credit_lot(current_setting('carbon_test08.issuance_main')::uuid, 10, (EXTRACT(YEAR FROM clock_timestamp())::INT + 1));
        PERFORM pg_temp.carbon_test_assert('B', 'B6b vintage_year année+1 rejeté', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B6b vintage_year année+1 rejeté', SQLERRM ILIKE '%hors bornes%', SQLERRM);
    END;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B7 : plafond dépassé rejeté (applicatif, RPC) — issuance_main=500, 200 déjà lotis (B2).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), false);
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM public.issue_credit_lot(current_setting('carbon_test08.issuance_main')::uuid, 400, 2020);
        PERFORM pg_temp.carbon_test_assert('B', 'B7 plafond dépassé rejeté', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B7 plafond dépassé rejeté', SQLERRM ILIKE '%Plafond dépassé%', SQLERRM);
    END;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B8 : issue_credit_lot() contre les 6 statuts non-issued RÉELS — applicatif, RPC.
DO $$
DECLARE
    v_statuses TEXT[] := ARRAY['internal','eligible','submitted','externally_cancelled','externally_rejected','voided'];
    v_status   TEXT;
    v_iss_id   UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), false);
    SET LOCAL ROLE authenticated;
    FOREACH v_status IN ARRAY v_statuses LOOP
        v_iss_id := current_setting('carbon_test08.issuance_' || v_status)::uuid;
        BEGIN
            PERFORM public.issue_credit_lot(v_iss_id, 5, 2020);
            PERFORM pg_temp.carbon_test_assert('B', 'B8-' || v_status || ' issue_credit_lot() rejeté contre une émission au statut ' || v_status, false, 'aucune exception');
        EXCEPTION WHEN OTHERS THEN
            PERFORM pg_temp.carbon_test_assert('B', 'B8-' || v_status || ' issue_credit_lot() rejeté contre une émission au statut ' || v_status,
                SQLERRM ILIKE '%issued%', SQLERRM);
        END;
    END LOOP;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B9 : void_credit_lot() correction interne réussie — applicatif, RPC.
DO $$
DECLARE
    v_admin  UUID := pg_temp.carbon_test_profile('admin');
    v_lot_id UUID := current_setting('carbon_test08.lot_main')::uuid;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, false);
    SET LOCAL ROLE authenticated;
    PERFORM public.void_credit_lot(v_lot_id, 'Erreur de saisie corrigée en interne');
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B9a void_credit_lot() chemin nominal (rôle authenticated réel) : commercial_status=voided',
        (SELECT commercial_status FROM public.credit_lots WHERE id = v_lot_id) = 'voided');
    PERFORM pg_temp.carbon_test_assert('B', 'B9b void_cause=internal_correction',
        (SELECT void_cause FROM public.credit_lots WHERE id = v_lot_id) = 'internal_correction');
    PERFORM pg_temp.carbon_test_assert('B', 'B9c voided_by=acteur réel (DB-owned)',
        (SELECT voided_by FROM public.credit_lots WHERE id = v_lot_id) = v_admin);
    PERFORM pg_temp.carbon_test_assert('B', 'B9d événement credit_lot_voided (RPC void_credit_lot) émis avec contexte complet (actor_id/object_type/object_id/organization_id/aggregator_id/verification_session_id/payload)',
        EXISTS (
            SELECT 1 FROM public.carbon_business_events e
            WHERE e.object_id = v_lot_id AND e.event_type = 'credit_lot_voided'
              AND e.object_type = 'credit_lot'
              AND e.actor_id = v_admin
              AND e.organization_id = '22222222-2222-2222-2222-100000000002'
              AND e.aggregator_id = '22222222-2222-2222-2222-200000000001'
              AND e.verification_session_id = '22222222-2222-2222-2222-900000000001'
              AND e.payload = jsonb_build_object('void_cause', 'internal_correction', 'reason', 'Erreur de saisie corrigée en interne')
        ));
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B9a void_credit_lot() chemin nominal (rôle authenticated réel)', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B10 : void_credit_lot() rejeté — lot déjà voided (B9).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), false);
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM public.void_credit_lot(current_setting('carbon_test08.lot_main')::uuid, 'nouvelle tentative');
        PERFORM pg_temp.carbon_test_assert('B', 'B10 void_credit_lot() rejeté : lot déjà voided (pas available)', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B10 void_credit_lot() rejeté : lot déjà voided (pas available)', SQLERRM ILIKE '%available%', SQLERRM);
    END;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B10bis (D13) : même message générique pour un lot totalement inexistant.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), false);
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM public.void_credit_lot(gen_random_uuid(), 'lot inexistant');
        PERFORM pg_temp.carbon_test_assert('B', 'B10bis void_credit_lot() rejeté : lot inexistant, message générique (D13)', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B10bis void_credit_lot() rejeté : lot inexistant, message générique (D13)', SQLERRM ILIKE '%Lot introuvable ou accès refusé%', SQLERRM);
    END;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B10ter (D13) : même message générique pour un lot existant mais acteur non
-- autorisé — les DEUX cas (absence/refus) sont indiscernables.
DO $$
DECLARE
    v_lot_bypass UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), false);
    SET LOCAL ROLE authenticated;
    v_lot_bypass := public.issue_credit_lot(current_setting('carbon_test08.issuance_bypass')::uuid, 15, 2020);
    RESET ROLE;
    PERFORM set_config('carbon_test08.lot_bypass', v_lot_bypass::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM public.void_credit_lot(v_lot_bypass, 'tentative non autorisée');
        PERFORM pg_temp.carbon_test_assert('B', 'B10ter void_credit_lot() rejeté : lot existant mais acteur non autorisé, MÊME message générique (D13)', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B10ter void_credit_lot() rejeté : lot existant mais acteur non autorisé, MÊME message générique (D13)', SQLERRM ILIKE '%Lot introuvable ou accès refusé%', SQLERRM);
    END;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B11 : cascade automatique sur DEUX lots (available ET reserved) + rejet
-- race condition — prouve que reserved->voided(external_cancellation)
-- réussit réellement (positif, complète B12ter).
DO $$
DECLARE
    v_admin       UUID := pg_temp.carbon_test_profile('admin');
    v_issuance_c  UUID := current_setting('carbon_test08.issuance_cascade')::uuid;
    v_doc         UUID := '22222222-2222-2222-2222-700000000001';
    v_lot_avail   UUID;
    v_lot_reserv  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, false);
    SET LOCAL ROLE authenticated;
    v_lot_avail := public.issue_credit_lot(v_issuance_c, 20, 2020);
    v_lot_reserv := public.issue_credit_lot(v_issuance_c, 20, 2020);
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();

    -- v_lot_reserv passe à reserved AVANT la cascade (bypass structurel —
    -- 09 n'est pas encore rédigée, aucune RPC pour cette transition).
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    UPDATE public.credit_lots SET commercial_status = 'reserved' WHERE id = v_lot_reserv;
    PERFORM pg_temp.carbon_test_clear_actor();

    -- record_external_cancellation() est la RPC réelle de 07 déclenchant la
    -- cascade — pas un UPDATE brut, ce qui exerce le chemin réellement
    -- emprunté en production.
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    PERFORM public.record_external_cancellation(v_issuance_c, current_date, 'TEST08-B11-CANCEL', v_doc);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B11a cascade : lot available passé à voided(external_cancellation)',
        (SELECT commercial_status = 'voided' AND void_cause = 'external_cancellation' FROM public.credit_lots WHERE id = v_lot_avail));
    PERFORM pg_temp.carbon_test_assert('B', 'B11a-bis cascade : lot reserved ÉGALEMENT passé à voided(external_cancellation)',
        (SELECT commercial_status = 'voided' AND void_cause = 'external_cancellation' FROM public.credit_lots WHERE id = v_lot_reserv));

    -- B11c (correction 4, quatrième revue statique) : événement
    -- credit_lot_voided produit par la CASCADE (trigger), DISTINCT de celui
    -- produit par la RPC void_credit_lot() (déjà vérifié en B9d) — payload
    -- propre à la cascade (void_cause=external_cancellation,
    -- credit_issuance_id), contexte complet.
    PERFORM pg_temp.carbon_test_assert('B', 'B11c événement credit_lot_voided produit par la CASCADE d''annulation externe, distinct de celui de la RPC void_credit_lot() (actor_id/object_type/object_id/organization_id/aggregator_id/verification_session_id/payload)',
        EXISTS (
            SELECT 1 FROM public.carbon_business_events e
            WHERE e.object_id = v_lot_avail AND e.event_type = 'credit_lot_voided'
              AND e.object_type = 'credit_lot'
              AND e.actor_id = v_admin
              AND e.organization_id = '22222222-2222-2222-2222-100000000002'
              AND e.aggregator_id = '22222222-2222-2222-2222-200000000001'
              AND e.verification_session_id = '22222222-2222-2222-2222-900000000001'
              AND e.payload = jsonb_build_object('void_cause', 'external_cancellation', 'credit_issuance_id', v_issuance_c)
        ));

    PERFORM pg_temp.carbon_test_set_actor(v_admin, false);
    SET LOCAL ROLE authenticated;
    BEGIN
        PERFORM public.void_credit_lot(v_lot_avail, 'tentative post-cascade');
        PERFORM pg_temp.carbon_test_assert('B', 'B11b void_credit_lot() rejeté après cascade : émission parente n''est plus issued', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B', 'B11b void_credit_lot() rejeté après cascade : émission parente n''est plus issued', SQLERRM ILIKE '%n''est plus issued%', SQLERRM);
    END;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B11 cascade double (available+reserved) + rejet race condition', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B12 : bypass structurel — void_cause=external_cancellation depuis
-- available, PARENT ENCORE issued -> rejeté pour la bonne raison (statut
-- parent, pas la transition elle-même : available EST une origine valide
-- pour cette cause).
DO $$
DECLARE
    v_admin   UUID := pg_temp.carbon_test_profile('admin');
    v_lot3_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    v_lot3_id := public.issue_credit_lot(current_setting('carbon_test08.issuance_bypass')::uuid, 10, 2020);

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B12 bypass : available->voided(external_cancellation) rejeté si parent encore issued (statut parent, pas transition)',
        format('UPDATE public.credit_lots SET commercial_status=''voided'', void_cause=''external_cancellation'', void_reason=''x'' WHERE id=%L::uuid', v_lot3_id),
        'exige que l''émission parente soit externally_cancelled');

    PERFORM set_config('carbon_test08.lot_c3', v_lot3_id::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.carbon_test_assert('B', 'B12 bypass void_cause=external_cancellation, parent pas encore cancelled', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B12bis (correction 6, troisième revue statique) : reserved -> voided avec
-- void_cause=internal_correction REJETÉ (internal_correction n'est valide
-- que depuis available — void_credit_lot() ne s'applique jamais à reserved).
DO $$
DECLARE
    v_admin   UUID := pg_temp.carbon_test_profile('admin');
    v_lot_r   UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    v_lot_r := public.issue_credit_lot(current_setting('carbon_test08.issuance_bypass')::uuid, 10, 2020);
    UPDATE public.credit_lots SET commercial_status = 'reserved' WHERE id = v_lot_r;

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B12bis bypass : reserved->voided(internal_correction) rejeté (valide uniquement depuis available)',
        format('UPDATE public.credit_lots SET commercial_status=''voided'', void_cause=''internal_correction'', void_reason=''x'' WHERE id=%L::uuid', v_lot_r),
        'internal_correction n''est valide que depuis available');

    PERFORM set_config('carbon_test08.lot_r', v_lot_r::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.carbon_test_assert('B', 'B12bis reserved->voided(internal_correction) rejeté', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B12ter (correction 6) : reserved -> voided(external_cancellation) avec
-- PARENT ENCORE issued -> rejeté pour la bonne raison (statut parent), PAS
-- pour la transition elle-même — prouve que reserved reste une origine
-- valide pour cette cause (contraste avec B11a-bis, où le parent est bien
-- externally_cancelled et la même transition réussit).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B12ter bypass : reserved->voided(external_cancellation) rejeté si parent encore issued (statut parent, pas transition)',
        format('UPDATE public.credit_lots SET commercial_status=''voided'', void_cause=''external_cancellation'', void_reason=''x'' WHERE id=%L::uuid', current_setting('carbon_test08.lot_r')),
        'exige que l''émission parente soit externally_cancelled');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B13 : transition reserved -> available autorisée (bypass structurel — FSM
-- hors périmètre RPC de 08, 09 non rédigée).
DO $$
DECLARE
    v_admin   UUID := pg_temp.carbon_test_profile('admin');
    v_lot3_id UUID := current_setting('carbon_test08.lot_c3')::uuid;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    UPDATE public.credit_lots SET commercial_status = 'reserved' WHERE id = v_lot3_id;
    UPDATE public.credit_lots SET commercial_status = 'available' WHERE id = v_lot3_id;
    PERFORM pg_temp.carbon_test_assert('B', 'B13 transition reserved->available autorisée (bypass structurel)',
        (SELECT commercial_status FROM public.credit_lots WHERE id = v_lot3_id) = 'available');
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.carbon_test_assert('B', 'B13 transition reserved->available', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B14 : transition invalide available->sold rejetée (bypass structurel).
SELECT pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), true);
SELECT pg_temp.carbon_test_assert_raises('B', 'B14 transition invalide available->sold rejetée (bypass structurel)',
    format('UPDATE public.credit_lots SET commercial_status=''sold'' WHERE id=%L::uuid', current_setting('carbon_test08.lot_c3')),
    'Transition de commercial_status refusée');
SELECT pg_temp.carbon_test_clear_actor();

-- B15 : colonnes figées immuables (bypass structurel).
SELECT pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), true);
SELECT pg_temp.carbon_test_assert_raises('B', 'B15a quantity_tco2e figé (bypass structurel)',
    format('UPDATE public.credit_lots SET quantity_tco2e = 999 WHERE id=%L::uuid', current_setting('carbon_test08.lot_c3')), 'figé');
SELECT pg_temp.carbon_test_assert_raises('B', 'B15b vintage_year figé (bypass structurel)',
    format('UPDATE public.credit_lots SET vintage_year = 2019 WHERE id=%L::uuid', current_setting('carbon_test08.lot_c3')), 'figé');
SELECT pg_temp.carbon_test_assert_raises('B', 'B15c credit_issuance_id figé (bypass structurel)',
    format('UPDATE public.credit_lots SET credit_issuance_id = gen_random_uuid() WHERE id=%L::uuid', current_setting('carbon_test08.lot_c3')), 'figé');
SELECT pg_temp.carbon_test_clear_actor();

-- B16 : colonne project_id n'existe plus.
SELECT pg_temp.carbon_test_assert_raises('B', 'B16 colonne project_id inexistante',
    'SELECT project_id FROM public.credit_lots LIMIT 1', 'does not exist');

-- B17 : DELETE structurellement interdit (bypass structurel).
SELECT pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), true);
SELECT pg_temp.carbon_test_assert_raises('B', 'B17 DELETE rejeté (append-only, bypass structurel)',
    format('DELETE FROM public.credit_lots WHERE id=%L::uuid', current_setting('carbon_test08.lot_c3')), 'append-only');
SELECT pg_temp.carbon_test_clear_actor();

-- B18 : cascade sans mutation sur un lot sold/retired (fait commercial
-- historique préservé), contexte complet de l'événement dédié.
DO $$
DECLARE
    v_admin      UUID := pg_temp.carbon_test_profile('admin');
    v_issuance_s UUID := current_setting('carbon_test08.issuance_sold')::uuid;
    v_doc        UUID := '22222222-2222-2222-2222-700000000001';
    v_lot4_id    UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    v_lot4_id := public.issue_credit_lot(v_issuance_s, 30, 2020);
    UPDATE public.credit_lots SET commercial_status = 'reserved' WHERE id = v_lot4_id;
    UPDATE public.credit_lots SET commercial_status = 'sold' WHERE id = v_lot4_id;

    PERFORM public.record_external_cancellation(v_issuance_s, current_date, 'TEST08-B18-CANCEL', v_doc);

    PERFORM pg_temp.carbon_test_assert('B', 'B18a lot sold NON muté par la cascade (fait commercial historique préservé)',
        (SELECT commercial_status FROM public.credit_lots WHERE id = v_lot4_id) = 'sold');
    PERFORM pg_temp.carbon_test_assert('B', 'B18b événement credit_lot_underlying_issuance_cancelled tracé avec contexte complet (actor_id/object_type/object_id/organization_id/aggregator_id/verification_session_id/payload)',
        EXISTS (
            SELECT 1 FROM public.carbon_business_events e
            WHERE e.object_id = v_lot4_id AND e.event_type = 'credit_lot_underlying_issuance_cancelled'
              AND e.object_type = 'credit_lot'
              AND e.actor_id = v_admin
              AND e.organization_id = '22222222-2222-2222-2222-100000000002'
              AND e.aggregator_id = '22222222-2222-2222-2222-200000000001'
              AND e.verification_session_id = '22222222-2222-2222-2222-900000000001'
              AND e.payload = jsonb_build_object('credit_issuance_id', v_issuance_s)
        ));
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.carbon_test_assert('B', 'B18 cascade sans mutation sur lot sold', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B19 : RLS — positive (opérateur, source, superadmin, regroupement,
-- vérificateur assigné) et négative (tiers) — rôle authenticated réel.
DO $$
DECLARE
    v_lot_ids UUID[] := ARRAY[
        current_setting('carbon_test08.lot_main')::uuid,
        current_setting('carbon_test08.lot_bypass')::uuid,
        current_setting('carbon_test08.lot_c3')::uuid
    ];
    v_count INT;
BEGIN
    -- Positif : admin de l'organisation opératrice.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_lots WHERE id = ANY(v_lot_ids);
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B19a RLS positive : admin de l''organisation opératrice voit ses lots (rôle authenticated réel)', v_count = 3, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Positif : admin de l'organisation SOURCE (via credit_issuance_sources).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('source'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_lots WHERE id = ANY(v_lot_ids);
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B19b RLS positive : admin de l''organisation source voit les lots via credit_issuance_sources (rôle authenticated réel)', v_count = 3, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Négatif : tiers sans relation ne voit rien.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_lots WHERE id = ANY(v_lot_ids);
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B19c RLS négative : tiers sans relation ne voit aucun lot (rôle authenticated réel)', v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Positif (correction 7) : superadmin — même acteur SANS aucune autre
    -- relation (outsider) + drapeau JWT superadmin=true, isolant proprement
    -- cette branche des autres.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), true);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_lots WHERE id = ANY(v_lot_ids);
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B19d RLS positive : superadmin voit les lots malgré l''absence de toute autre relation (rôle authenticated réel)', v_count = 3, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Positif (correction 7) : admin du regroupement (aggregator_admins),
    -- profil DÉDIÉ sans lien organisationnel ni accréditation.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_lots WHERE id = ANY(v_lot_ids);
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B19e RLS positive : admin du regroupement voit les lots (branche is_aggregator_admin, rôle authenticated réel)', v_count = 3, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Positif (correction 7) : vérificateur assigné à la session parente.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_lots WHERE id = ANY(v_lot_ids);
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B19f RLS positive : vérificateur assigné à la session parente voit les lots (rôle authenticated réel)', v_count = 3, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B19 RLS positive/négative (toutes branches)', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B20 : recyclage de capacité après void_credit_lot() (internal_correction).
DO $$
DECLARE
    v_admin      UUID := pg_temp.carbon_test_profile('admin');
    v_issuance_r UUID := current_setting('carbon_test08.issuance_recycle')::uuid;
    v_lot_a      UUID;
    v_lot_b      UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, false);
    SET LOCAL ROLE authenticated;
    v_lot_a := public.issue_credit_lot(v_issuance_r, 40, 2020);
    RESET ROLE;

    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM public.issue_credit_lot(v_issuance_r, 20, 2020);
        RESET ROLE;
        PERFORM pg_temp.carbon_test_assert('B', 'B20a issue_credit_lot() 20 refusé avant recyclage (40+20>50)', false, 'aucune exception');
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        PERFORM pg_temp.carbon_test_assert('B', 'B20a issue_credit_lot() 20 refusé avant recyclage (40+20>50)', SQLERRM ILIKE '%Plafond dépassé%', SQLERRM);
    END;

    SET LOCAL ROLE authenticated;
    PERFORM public.void_credit_lot(v_lot_a, 'libère la capacité pour le test de recyclage');
    RESET ROLE;

    SET LOCAL ROLE authenticated;
    v_lot_b := public.issue_credit_lot(v_issuance_r, 20, 2020);
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B20b issue_credit_lot() 20 réussit APRÈS recyclage (lot voided exclu de la somme)', v_lot_b IS NOT NULL);

    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B20 recyclage de capacité après correction interne', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B21 (correction 6) : auth.uid() NULL rejeté au passage à voided (bypass
-- structurel — acteur explicitement effacé avant l'UPDATE).
DO $$
DECLARE
    v_admin UUID := pg_temp.carbon_test_profile('admin');
    v_lot_e UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    v_lot_e := public.issue_credit_lot(current_setting('carbon_test08.issuance_bypass')::uuid, 5, 2020);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B21 bypass : passage à voided sans authentification (auth.uid() NULL) rejeté',
        format('UPDATE public.credit_lots SET commercial_status=''voided'', void_cause=''internal_correction'', void_reason=''x'' WHERE id=%L::uuid', v_lot_e),
        'Authentification requise pour voider un lot');

    PERFORM set_config('carbon_test08.lot_e', v_lot_e::text, false);
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.carbon_test_assert('B', 'B21 auth.uid() NULL rejeté au passage à voided', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B22 (correction 6) : voided_by/voided_at DB-owned — valeurs fournies
-- systématiquement écrasées par le trigger (bypass structurel).
DO $$
DECLARE
    v_admin     UUID := pg_temp.carbon_test_profile('admin');
    v_outsider  UUID := pg_temp.carbon_test_profile('outsider');
    v_lot_e     UUID := current_setting('carbon_test08.lot_e')::uuid;
    v_before    TIMESTAMPTZ := clock_timestamp();
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    UPDATE public.credit_lots
    SET commercial_status = 'voided', void_cause = 'internal_correction', void_reason = 'test DB-owned',
        voided_by = v_outsider, voided_at = '2000-01-01'::timestamptz
    WHERE id = v_lot_e;

    PERFORM pg_temp.carbon_test_assert('B', 'B22a voided_by écrasé à l''acteur réel (DB-owned), pas la valeur fournie',
        (SELECT voided_by FROM public.credit_lots WHERE id = v_lot_e) = v_admin);
    PERFORM pg_temp.carbon_test_assert('B', 'B22b voided_at écrasé à clock_timestamp() réel (DB-owned), pas la valeur fournie',
        (SELECT voided_at FROM public.credit_lots WHERE id = v_lot_e) >= v_before);
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.carbon_test_assert('B', 'B22 voided_by/voided_at DB-owned', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B23 (correction 6) : void_reason vide (espaces) rejeté (bypass structurel).
DO $$
DECLARE
    v_admin UUID := pg_temp.carbon_test_profile('admin');
    v_lot_f UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(v_admin, true);
    v_lot_f := public.issue_credit_lot(current_setting('carbon_test08.issuance_bypass')::uuid, 5, 2020);

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B23 bypass : void_reason vide (espaces) rejeté',
        format('UPDATE public.credit_lots SET commercial_status=''voided'', void_cause=''internal_correction'', void_reason=''   '' WHERE id=%L::uuid', v_lot_f),
        'void_reason est requis');
    PERFORM pg_temp.carbon_test_clear_actor();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.carbon_test_assert('B', 'B23 void_reason vide rejeté', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 4. GATE FINAL — véritable porte, pas un simple résumé (correction 9).
--    S'exécute AVANT le ROLLBACK, sur les Parties A/Abis/B uniquement
--    (plus de Partie C dans ce fichier — quatrième revue statique).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_total    INT;
    v_failed   INT;
    v_dupes    INT;
    -- Recompté mécaniquement après retrait de la Partie C et ajout de B11c
    -- (quatrième revue statique) : 87 = Partie A (27) + Partie A bis (4) +
    -- Partie B (56). Partie B = 43 assertions directes (B2:5, B3:3, B5:2,
    -- B6:2, B7:1, B8:6, B9:4, B10:1, B10bis:1, B10ter:1, B11:4 [inclut
    -- B11c, nouvelle], B13:1, B18:2, B19:6, B20:2, B22:2) + 13 assertions
    -- via carbon_test_assert_raises() (B1, B4, B12, B12bis, B12ter, B14,
    -- B15a, B15b, B15c, B16, B17, B21, B23). Les blocs à libellé de repli
    -- (catch-all) DIFFÉRENT du libellé du chemin de succès (B3, B9, B11,
    -- B12, B12bis, B13, B18, B19, B20, B21, B22, B23) ne contribuent PAS au
    -- décompte tant que le test réussit — seul un échec inattendu les
    -- déclencherait, ce qui ferait alors dévier v_total de 87 (détecté par
    -- ce gate, jamais masqué).
    v_expected INT := 87;
    r RECORD;
BEGIN
    SELECT count(*) INTO v_total FROM pg_temp._carbon_migration_test_results;
    SELECT count(*) INTO v_failed FROM pg_temp._carbon_migration_test_results WHERE NOT passed;
    SELECT count(*) INTO v_dupes FROM (
        SELECT assertion FROM pg_temp._carbon_migration_test_results GROUP BY assertion HAVING count(*) > 1
    ) d;

    IF v_failed > 0 THEN
        FOR r IN SELECT section, assertion, detail FROM pg_temp._carbon_migration_test_results WHERE NOT passed ORDER BY section, assertion LOOP
            RAISE NOTICE 'ÉCHEC [%] % — %', r.section, r.assertion, r.detail;
        END LOOP;
    END IF;
    IF v_dupes > 0 THEN
        FOR r IN SELECT assertion FROM pg_temp._carbon_migration_test_results GROUP BY assertion HAVING count(*) > 1 LOOP
            RAISE NOTICE 'LIBELLÉ DUPLIQUÉ : %', r.assertion;
        END LOOP;
    END IF;

    RAISE NOTICE '=== Migration 08 — % assertions (% attendues), % échouées, % libellés dupliqués ===', v_total, v_expected, v_failed, v_dupes;

    IF v_total <> v_expected THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertions enregistrées, % attendues exactement.', v_total, v_expected;
    END IF;
    IF v_failed <> 0 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertion(s) en échec sur %.', v_failed, v_total;
    END IF;
    IF v_dupes <> 0 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % libellé(s) d''assertion dupliqué(s).', v_dupes;
    END IF;

    RAISE NOTICE 'GATE RÉUSSI : %/% assertions, 0 échec, 0 doublon.', v_total, v_expected;
END $$;

SELECT count(*) AS total, count(*) FILTER (WHERE passed) AS reussies, count(*) FILTER (WHERE NOT passed) AS echouees
FROM pg_temp._carbon_migration_test_results;

SELECT section, assertion, passed, detail
FROM pg_temp._carbon_migration_test_results
ORDER BY section, assertion;

-- Aucune donnée résiduelle des Parties A/Abis/fixtures/B : ROLLBACK complet.
ROLLBACK;

-- Pas de DROP TABLE explicite ici (correctif exécution réelle) : selon
-- l'environnement d'exécution, le ROLLBACK ci-dessus peut déjà avoir annulé
-- la CREATE TEMP TABLE elle-même (certains exécuteurs SQL englobent tout le
-- script soumis dans leur propre transaction externe, auquel cas notre
-- ROLLBACK défait aussi la création de la table, et un DROP TABLE explicite
-- échouerait alors sur une table déjà inexistante). Dans tous les cas, une
-- TEMP TABLE disparaît automatiquement à la fin de la session — ce DROP
-- n'apportait qu'une inspectabilité facultative, jamais une garantie de
-- propreté supplémentaire.
