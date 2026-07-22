-- ============================================================
-- ⚠️⚠️⚠️  STAGING / CLONE JETABLE UNIQUEMENT — INTERDIT SUR PRODUCTION  ⚠️⚠️⚠️
-- ============================================================
-- Migration 08 (credit_lots) — protocole de concurrence RÉEL à deux
-- connexions (dblink).
--
-- CE FICHIER NE DOIT JAMAIS ÊTRE EXÉCUTÉ CONTRE LA BASE DE PRODUCTION.
-- Il ne doit être exécuté QUE contre un clone jetable ou un environnement
-- de staging entièrement dédié, destiné à être détruit après usage.
--
-- Ce protocole a été retiré de tests/08_test_carbon_lots.sql (quatrième
-- revue statique) précisément parce qu'il est structurellement incompatible
-- avec un script destiné à la production, pour TROIS raisons distinctes,
-- chacune suffisante à elle seule pour l'interdire :
--
--   1. Il COMMIT réellement des lignes dans public.credit_lots (nécessaire
--      pour qu'une connexion dblink séparée — une session physiquement
--      distincte — puisse les voir ; une transaction non committée est
--      invisible à toute autre connexion, y compris dblink, par isolation
--      MVCC standard). Or credit_lots interdit désormais STRUCTURELLEMENT
--      tout DELETE (trigger trg_carbon_credit_lots_forbid_delete, installé
--      par CETTE migration elle-même) : un DELETE compensatoire de
--      nettoyage sur credit_lots serait rejeté par sa propre cible. Il n'y
--      a donc AUCUN moyen de nettoyer proprement les lignes credit_lots
--      committées par ce protocole sur une base qui a déjà reçu la
--      migration 08.
--   2. Il appelle public.designate_platform_operator() en autocommit pour
--      désigner un opérateur de TEST. Sur une base de production, cela
--      RÉVOQUE RÉELLEMENT l'opérateur actif véritable (à ce jour :
--      METALTRACE) — un DELETE ultérieur de la ligne platform_operators de
--      test ne restaure PAS l'opérateur précédent (aucune trace de l'état
--      antérieur n'est conservée par un simple DELETE). C'est une
--      perturbation réelle et potentiellement durable de l'état commercial
--      de production.
--   3. Il exécute CREATE EXTENSION IF NOT EXISTS dblink, qui est elle-même
--      une modification PERSISTANTE du schéma de la base — inappropriée
--      pour un script qualifié de "test".
--
-- Sur un clone/staging jetable, aucune de ces trois raisons ne s'applique
-- (l'environnement est détruit après usage), et le protocole peut s'exécuter
-- sans risque pour obtenir une preuve réelle, à deux connexions physiques
-- séparées, que issue_credit_lot() sérialise correctement l'accès concurrent
-- au plafond d'une émission (verrou FOR UPDATE sur credit_issuances) sans
-- perte de mise à jour lors d'un commit concurrent.
--
-- PRÉREQUIS : 04/05/06/07 et 08 (08_carbon_lots_commercial_cycle.sql,
-- cinquième revue) déjà appliqués sur l'environnement CIBLE (clone/staging).
-- Réutilise >= 2 profils réels distincts de public.profiles (FK réelle vers
-- auth.users — aucune ligne profiles fabriquée ici).
--
-- SCÉNARIO : deux issue_credit_lot() concurrents proches du plafond d'une
-- émission de 100 tCO2e (60+60) : connexion 2 émet 60 SANS committer ;
-- connexion 1 tente 60 -> doit bloquer réellement (lock_timeout court,
-- lock_not_available observé) ; connexion 2 committe ; connexion 1 retente
-- 60 -> désormais correctement REJETÉE pour dépassement de plafond
-- (60+60>100, plus un blocage — preuve que la somme post-commit est bien
-- recalculée sous verrou, donc pas de perte de mise à jour) ; connexion 1
-- tente 40 (plafond réel restant) -> réussit.
--
-- ⚠️ POINT À RECONFIRMER EN DIRECT AVANT TOUTE EXÉCUTION, MÊME EN STAGING :
-- suppose dblink disponible et qu'une connexion vers dbname=current_database()
-- aboutit depuis une session SQL Supabase. Si l'environnement ne le permet
-- pas, C0 échoue bruyamment (détail = message de connexion), AUCUNE
-- dégradation silencieuse.
--
-- NETTOYAGE (cinquième revue statique, correction 6) : ce fichier NE
-- NETTOIE PLUS RIEN lui-même — voir le commentaire en fin de script pour le
-- raisonnement. Il committe ses fixtures dédiées (namespace UUID
-- '22222222-2222-2222-2222-c0000000000X') et le protocole de concurrence
-- lui-même, PUIS s'arrête : l'environnement clone/staging cible DOIT être
-- détruit ou réinitialisé intégralement après exécution. Ne prétend PAS à
-- un nettoyage partiel.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 0. Harnais minimal — table de résultats + fonctions utilitaires
--    nécessaires à ce fichier (copie autonome, ce fichier ne dépend pas de
--    tests/08_test_carbon_lots.sql).
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public._carbon_migration_test_results_staging_concurrency (
    id         SERIAL PRIMARY KEY,
    section    TEXT NOT NULL,
    assertion  TEXT NOT NULL,
    detail     TEXT NULL,
    passed     BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_assert(
    p_section TEXT, p_assertion TEXT, p_condition BOOLEAN, p_detail TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public._carbon_migration_test_results_staging_concurrency(section, assertion, detail, passed)
    VALUES (p_section, p_assertion, p_detail, COALESCE(p_condition, false));
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

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_profile(p_key TEXT) RETURNS UUID
LANGUAGE sql AS $$ SELECT current_setting('carbon_test08c.profile_' || p_key)::UUID $$;

-- Fait progresser une émission jusqu'à 'issued' via la séquence réelle des
-- 4 RPC de 07 (même patron validé que tests/07 et tests/08).
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
    PERFORM public.mark_credit_issuance_eligible(v_id);
    PERFORM public.submit_credit_issuance(v_id, 'TEST-08C Registre');
    PERFORM public.record_registry_issuance(v_id, p_registry_ref, clock_timestamp());
    PERFORM pg_temp.carbon_test_clear_actor();
    RETURN v_id;
END;
$$;

DO $$
DECLARE
    v_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_ids FROM (SELECT id FROM public.profiles ORDER BY created_at LIMIT 2) sub;
    IF COALESCE(array_length(v_ids, 1), 0) < 2 THEN
        RAISE EXCEPTION 'Fixtures impossibles : au moins 2 profils réels distincts sont requis dans public.profiles (trouvés : %).', COALESCE(array_length(v_ids, 1), 0);
    END IF;
    PERFORM set_config('carbon_test08c.profile_admin',    v_ids[1]::text, false);
    PERFORM set_config('carbon_test08c.profile_verifier', v_ids[2]::text, false);
END $$;

-- ============================================================
-- FIXTURES DÉDIÉES, COMMITTÉES (autocommit — aucun BEGIN de script) —
-- namespace UUID '22222222-2222-2222-2222-c0000000000X'.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS dblink;

INSERT INTO public.organizations (id, name, status) VALUES
    ('22222222-2222-2222-2222-c00000000001', 'TEST-08C Source', 'active'),
    ('22222222-2222-2222-2222-c00000000002', 'TEST-08C Operateur', 'active'),
    ('22222222-2222-2222-2222-c00000000003', 'TEST-08C MRV (contrepartie)', 'active');

INSERT INTO public.aggregators (id, name) VALUES ('22222222-2222-2222-2222-c00000000004', 'TEST-08C Regroupement');

INSERT INTO public.opportunities (id, title, coordinator_org_id)
VALUES ('22222222-2222-2222-2222-c00000000005', 'TEST-08C Opportunité', '22222222-2222-2222-2222-c00000000001');
INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id)
VALUES ('22222222-2222-2222-2222-c00000000006', '22222222-2222-2222-2222-c00000000005', 'TEST-08C Projet CCF', '22222222-2222-2222-2222-c00000000001');

INSERT INTO public.operational_units (id, organization_id, name)
VALUES ('22222222-2222-2222-2222-c00000000007', '22222222-2222-2222-2222-c00000000003', 'TEST-08C Unité MRV');
INSERT INTO public.projects (id, operational_unit_id, name)
VALUES ('22222222-2222-2222-2222-c00000000008', '22222222-2222-2222-2222-c00000000007', 'TEST-08C Projet MRV');

INSERT INTO public.ccf_mrv_project_links (ccf_project_id, mrv_project_id, started_by)
SELECT '22222222-2222-2222-2222-c00000000006', '22222222-2222-2222-2222-c00000000008', pg_temp.carbon_test_profile('admin');

INSERT INTO public.project_participants (project_id, organization_id, status)
VALUES ('22222222-2222-2222-2222-c00000000006', '22222222-2222-2222-2222-c00000000001', 'active');

INSERT INTO public.accredited_verifiers (user_id, accredited_by)
SELECT pg_temp.carbon_test_profile('verifier'), pg_temp.carbon_test_profile('admin');

INSERT INTO public.evidence_files (id, project_id, file_url, type, file_hash)
VALUES ('22222222-2222-2222-2222-c00000000009', '22222222-2222-2222-2222-c00000000008', '/evidence/test-08c.pdf', 'verification_report', 'sha256:test-08c');

INSERT INTO public.aggregator_memberships (id, organization_id, aggregator_id, started_at)
VALUES ('22222222-2222-2222-2222-c0000000000a', '22222222-2222-2222-2222-c00000000001', '22222222-2222-2222-2222-c00000000004', clock_timestamp() - interval '30 days');

-- ⚠️ Révoque réellement l'opérateur actif si exécuté contre une base qui en
-- a déjà un — c'est PRÉCISÉMENT pourquoi ce fichier est INTERDIT sur
-- production (raison 2 de l'en-tête).
--
-- Cinquième revue statique, correction 3 : set_config(..., true) est
-- LOCAL À LA TRANSACTION courante. En autocommit, chaque instruction
-- top-level EST sa propre transaction implicite — appeler set_actor(),
-- designate_platform_operator() et clear_actor() comme TROIS instructions
-- SELECT séparées (version précédente) faisait donc disparaître le JWT
-- entre la première et la deuxième instruction : designate_platform_operator()
-- s'exécutait alors SANS l'acteur superadmin attendu. Les trois appels sont
-- désormais groupés dans un SEUL bloc DO (une seule transaction implicite),
-- pour que le JWT posé par set_actor() soit encore actif lors de l'appel à
-- designate_platform_operator().
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin'), true);
    PERFORM public.designate_platform_operator('22222222-2222-2222-2222-c00000000002');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Cinquième revue statique, correction 4 : l'acteur 'admin' doit RÉELLEMENT
-- être admin de l'organisation opératrice TEST pour que is_org_admin()
-- l'autorise dans issue_credit_lot()/void_credit_lot() lorsqu'il agit SANS
-- le drapeau JWT superadmin (p_superadmin=false, cas de C2/C3/C4 — la
-- connexion 1/session courante). Sans cette ligne, ces appels échouaient
-- sur l'autorisation elle-même plutôt que de tester le verrou visé.
INSERT INTO public.organization_members (id, organization_id, user_id, org_role, status, activated_at)
VALUES ('22222222-2222-2222-2222-c0000000000e', '22222222-2222-2222-2222-c00000000002',
        pg_temp.carbon_test_profile('admin'), 'admin', 'active', clock_timestamp() - interval '10 days');

INSERT INTO public.carbon_commercialization_mandates (
    id, aggregator_membership_id, organization_id, aggregator_id, operator_organization_id, scope, granted_by
)
SELECT '22222222-2222-2222-2222-c0000000000b', '22222222-2222-2222-2222-c0000000000a',
       '22222222-2222-2222-2222-c00000000001', '22222222-2222-2222-2222-c00000000004',
       '22222222-2222-2222-2222-c00000000002', ARRAY['request_issuance'], pg_temp.carbon_test_profile('admin');

INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end, verifier_user_id)
SELECT '22222222-2222-2222-2222-c0000000000c', '22222222-2222-2222-2222-c00000000008', 'completed', current_date - 14, current_date - 8,
       pg_temp.carbon_test_profile('verifier');

INSERT INTO public.verification_outcomes (id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
SELECT '22222222-2222-2222-2222-c0000000000d', '22222222-2222-2222-2222-c0000000000c', 'active', 100, 100, 100,
       '22222222-2222-2222-2222-c00000000009', pg_temp.carbon_test_profile('verifier');

SELECT pg_temp.carbon_test_make_issued_credit_issuance(
    '22222222-2222-2222-2222-c0000000000d', '22222222-2222-2222-2222-c00000000001',
    '22222222-2222-2222-2222-c0000000000a', '22222222-2222-2222-2222-c0000000000b',
    100, pg_temp.carbon_test_profile('admin'), 'TEST08C-REG-CONCUR');

-- L'id de l'émission est déterministe (créée seule contre cet outcome).
DO $$
BEGIN
    PERFORM set_config('carbon_test08c.issuance',
        (SELECT id::text FROM public.credit_issuances WHERE aggregator_id = '22222222-2222-2222-2222-c00000000004' LIMIT 1), false);
END $$;

-- ============================================================
-- LE PROTOCOLE DE CONCURRENCE LUI-MÊME (deux connexions physiques réelles).
-- ============================================================
DO $$
DECLARE
    v_admin      UUID := pg_temp.carbon_test_profile('admin');
    v_issuance_x UUID := current_setting('carbon_test08c.issuance')::uuid;
    v_conn_ok    BOOLEAN := false;
    v_lot_conn2  UUID;
BEGIN
    BEGIN
        PERFORM dblink_connect('t08c_conn', format('dbname=%s', current_database()));
        v_conn_ok := true;
        PERFORM pg_temp.carbon_test_assert('C', 'C0 connexion dblink secondaire établie (dbname=current_database())', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('C', 'C0 connexion dblink secondaire établie (dbname=current_database())', false, SQLERRM);
    END;

    IF v_conn_ok THEN
        -- Propage le JWT de l'acteur + le rôle applicatif sur la connexion 2
        -- (SET CONFIG renvoie sa valeur -> dblink(), jamais dblink_exec()).
        PERFORM t.cfg FROM dblink('t08c_conn', format(
            'SELECT set_config(''request.jwt.claims'', %L, false)',
            jsonb_build_object('sub', v_admin::text, 'role', 'authenticated', 'app_metadata', jsonb_build_object('role', 'admin'))::text
        )) AS t(cfg text);
        PERFORM dblink_exec('t08c_conn', 'SET ROLE authenticated');
        PERFORM dblink_exec('t08c_conn', 'BEGIN');

        -- Connexion 2 : issue_credit_lot() RÉELLE pour 60 tCO2e (sur 100 de
        -- plafond), SANS committer.
        BEGIN
            SELECT t.id INTO v_lot_conn2 FROM dblink('t08c_conn',
                format('SELECT public.issue_credit_lot(%L::uuid, 60, 2020)', v_issuance_x)) AS t(id uuid);
            PERFORM pg_temp.carbon_test_assert('C', 'C1 connexion 2 : issue_credit_lot() 60 tCO2e réussit (non committé)', v_lot_conn2 IS NOT NULL);
        EXCEPTION WHEN OTHERS THEN
            PERFORM pg_temp.carbon_test_assert('C', 'C1 connexion 2 : issue_credit_lot() 60 tCO2e réussit (non committé)', false, SQLERRM);
        END;

        -- Connexion 1 (session courante) : tente 60 tCO2e sur la MÊME
        -- émission -> doit se heurter réellement au verrou credit_issuances
        -- tenu (non committé) par la connexion 2. lock_timeout court
        -- transforme le blocage en échec observable.
        PERFORM pg_temp.carbon_test_set_actor(v_admin, false);
        SET LOCAL lock_timeout = '2s';
        BEGIN
            SET LOCAL ROLE authenticated;
            PERFORM public.issue_credit_lot(v_issuance_x, 60, 2020);
            RESET ROLE;
            PERFORM pg_temp.carbon_test_assert('C', 'C2 issue_credit_lot() concurrent bloque réellement (verrou credit_issuances tenu par connexion 2)', false, 'aucun blocage détecté');
        EXCEPTION WHEN lock_not_available OR query_canceled THEN
            RESET ROLE;
            PERFORM pg_temp.carbon_test_assert('C', 'C2 issue_credit_lot() concurrent bloque réellement (verrou credit_issuances tenu par connexion 2)', true, SQLERRM);
        END;
        RESET lock_timeout;
        PERFORM pg_temp.carbon_test_clear_actor();

        -- Connexion 2 committe ses 60 tCO2e, puis se déconnecte.
        PERFORM dblink_exec('t08c_conn', 'COMMIT');
        PERFORM dblink_disconnect('t08c_conn');

        -- Connexion 1 : 60 supplémentaires (60+60=120>100) — désormais
        -- REJETÉE pour dépassement de plafond (pas un blocage) : preuve que
        -- le recalcul de la somme sous verrou tient compte du commit
        -- concurrent, sans perte de mise à jour.
        PERFORM pg_temp.carbon_test_set_actor(v_admin, false);
        BEGIN
            SET LOCAL ROLE authenticated;
            PERFORM public.issue_credit_lot(v_issuance_x, 60, 2020);
            RESET ROLE;
            PERFORM pg_temp.carbon_test_assert('C', 'C3 plafond correctement recalculé après commit concurrent (60+60>100 rejeté, pas un blocage)', false, 'aucune exception');
        EXCEPTION WHEN OTHERS THEN
            RESET ROLE;
            PERFORM pg_temp.carbon_test_assert('C', 'C3 plafond correctement recalculé après commit concurrent (60+60>100 rejeté, pas un blocage)', SQLERRM ILIKE '%Plafond dépassé%', SQLERRM);
        END;
        PERFORM pg_temp.carbon_test_clear_actor();

        -- Contre-épreuve positive : le plafond réel restant (100-60=40) est
        -- correctement accepté.
        PERFORM pg_temp.carbon_test_set_actor(v_admin, false);
        SET LOCAL ROLE authenticated;
        PERFORM public.issue_credit_lot(v_issuance_x, 40, 2020);
        RESET ROLE;
        PERFORM pg_temp.carbon_test_assert('C', 'C4 quantité respectant le plafond réel restant (40) réussit après recalcul', true);
        PERFORM pg_temp.carbon_test_clear_actor();
    END IF;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    BEGIN PERFORM dblink_disconnect('t08c_conn'); EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM pg_temp.carbon_test_assert('C', 'C protocole de concurrence réel (dblink) — échec inattendu, voir détail', false, SQLERRM);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

SELECT count(*) AS total, count(*) FILTER (WHERE passed) AS reussies, count(*) FILTER (WHERE NOT passed) AS echouees
FROM public._carbon_migration_test_results_staging_concurrency;

SELECT section, assertion, passed, detail
FROM public._carbon_migration_test_results_staging_concurrency
ORDER BY assertion;

-- ────────────────────────────────────────────────────────────
-- GATE C0-C4 (correction 5, cinquième revue statique) — véritable porte :
-- exactement 5 assertions (C0 à C4), zéro échec. Si dblink échoue à se
-- connecter (C0 en échec), la boucle IF v_conn_ok s'interrompt et seule C0
-- est enregistrée : le gate échoue alors avec un total de 1 au lieu de 5,
-- ce qui est le comportement VOULU (signale l'écart d'environnement au lieu
-- de le masquer).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_total    INT;
    v_failed   INT;
    v_expected INT := 5;
    r RECORD;
BEGIN
    SELECT count(*) INTO v_total FROM public._carbon_migration_test_results_staging_concurrency;
    SELECT count(*) INTO v_failed FROM public._carbon_migration_test_results_staging_concurrency WHERE NOT passed;

    IF v_failed > 0 THEN
        FOR r IN SELECT section, assertion, detail FROM public._carbon_migration_test_results_staging_concurrency WHERE NOT passed ORDER BY assertion LOOP
            RAISE NOTICE 'ÉCHEC [%] % — %', r.section, r.assertion, r.detail;
        END LOOP;
    END IF;

    RAISE NOTICE '=== Concurrence STAGING — % assertions (% attendues), % échouées ===', v_total, v_expected, v_failed;

    IF v_total <> v_expected THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertions enregistrées, % attendues exactement (C0-C4).', v_total, v_expected;
    END IF;
    IF v_failed <> 0 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertion(s) en échec sur %.', v_failed, v_total;
    END IF;

    RAISE NOTICE 'GATE RÉUSSI : %/% assertions, 0 échec.', v_total, v_expected;
END $$;

-- ============================================================
-- AUCUN NETTOYAGE COMPENSATOIRE (correction 6, cinquième revue statique).
-- ============================================================
-- La version précédente tentait un nettoyage COMMITTÉ partiel par DELETE,
-- en omettant explicitement credit_lots (append-only, DELETE
-- structurellement interdit). Ce n'était pas seulement incomplet : d'autres
-- objets historiques touchés par ce protocole peuvent eux aussi refuser
-- DELETE ou laisser des dépendances (carbon_business_events référencé par
-- FK depuis d'autres tables selon l'état de la base cible, platform_operators
-- historisé, etc.) — prétendre à un nettoyage partiel entretient l'illusion
-- d'un script auto-nettoyant qu'il n'est pas.
--
-- Le protocole ne nettoie donc PLUS RIEN lui-même. L'environnement
-- clone/staging sur lequel ce fichier a été exécuté doit être DÉTRUIT ou
-- RÉINITIALISÉ intégralement après usage (snapshot restore, destruction du
-- clone, etc.) — c'est la SEULE garantie de propreté, cohérente avec le
-- statut JETABLE de cet environnement rappelé dans l'en-tête. Ne JAMAIS
-- réutiliser un environnement ayant exécuté ce fichier sans une telle
-- réinitialisation complète, et ne JAMAIS exécuter ce fichier contre un
-- environnement qui ne peut pas être détruit/réinitialisé ainsi (donc
-- jamais contre la production).
