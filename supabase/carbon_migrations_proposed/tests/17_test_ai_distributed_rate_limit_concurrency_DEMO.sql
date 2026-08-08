-- ============================================================
-- Migration 17 (ai_rate_limit_counters) — concurrence RÉELLE à deux
-- connexions (dblink), GATE IA-3 points 9 et 10 (scénario "concurrence
-- réelle").
-- ============================================================
--
-- ⚠ DIFFÉRENCE IMPORTANTE avec les protocoles dblink précédents de ce
-- dépôt (ex. tests/08_test_carbon_lots_concurrency_STAGING_ONLY.sql,
-- tests/09_test_carbon_sales_financial_model_concurrency_STAGING_ONLY*.sql) :
-- ceux-là étaient réservés à un clone/staging JETABLE, pour trois raisons
-- documentées dans leur en-tête (DELETE structurellement impossible sur des
-- tables append-only, désignation d'opérateur réelle perturbée de façon
-- durable, CREATE EXTENSION persistant). AUCUNE de ces trois raisons ne
-- s'applique ici :
--   1. ai_rate_limit_counters n'est PAS append-only (table de compteurs
--      ordinaire) -> DELETE de nettoyage réel et complet possible.
--   2. Ce fichier ne touche à AUCUNE donnée métier (pas d'organisation,
--      d'opérateur, de mandat, de lot) — uniquement des lignes de compteur
--      pour un seul profil de test réel.
--   3. dblink est activé puis DÉSACTIVÉ explicitement en fin de script
--      s'il ne préexistait pas (vérifié avant activation) — aucune
--      modification persistante du schéma.
-- GATE IA-3, point 11, exige explicitement d'appliquer/tester UNIQUEMENT
-- sur METALVISION-DEMO (pas de clone séparé pour ce GATE) — ce fichier est
-- conçu pour être exécuté directement sur DEMO, en autocommit, avec un
-- nettoyage complet garanti en fin de script, y compris en cas d'échec
-- (bloc EXCEPTION couvrant tout le protocole).
--
-- PRÉREQUIS : 17_ai_distributed_rate_limit.sql déjà appliquée. Idéalement
-- exécuté juste après tests/17_test_ai_distributed_rate_limit.sql (celui-ci
-- réutilise le même profil A que ce script pourrait réutiliser, mais nettoie
-- intégralement derrière lui — aucune dépendance d'ordre stricte).
--
-- SCÉNARIO (dernier slot de la fenêtre minute analyze_photo, limite 5) :
--   - Pré-remplissage direct (rôle propriétaire) du compteur minute du
--     profil de test à request_count=4 (4 des 5 requêtes déjà "consommées"
--     par ailleurs) — 1 seul slot restant.
--   - Connexion 2 (dblink) : check_ai_rate_limit('analyze_photo') pour la
--     5e requête (le dernier slot) -> DOIT réussir, SANS committer.
--   - Connexion 1 (session courante) : tente la même chose en concurrence
--     -> DOIT se heurter réellement au verrou de ligne tenu par la
--     connexion 2 (lock_timeout court, lock_not_available observé) —
--     preuve directe que les deux requêtes ne peuvent PAS être acceptées
--     toutes les deux par erreur (GATE IA-3, point 9).
--   - Connexion 2 committe.
--   - Connexion 1 retente -> désormais REJETÉE (allowed=false, seuil déjà
--     atteint par le commit de la connexion 2) — jamais un 6e acquéreur
--     pour 5 slots.
--
-- NETTOYAGE : DELETE complet des lignes ai_rate_limit_counters du profil de
-- test en fin de script (succès ou échec, via bloc EXCEPTION), et DROP
-- EXTENSION dblink si ce script l'a lui-même créée.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 0. Harnais minimal — table de résultats + utilitaires (autonome, ne
--    dépend pas de tests/17_test_ai_distributed_rate_limit.sql).
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public._carbon_migration_test_results_17_concurrency (
    id         SERIAL PRIMARY KEY,
    section    TEXT NOT NULL,
    assertion  TEXT NOT NULL,
    detail     TEXT NULL,
    passed     BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

REVOKE ALL ON public._carbon_migration_test_results_17_concurrency
FROM PUBLIC, anon, authenticated;

TRUNCATE public._carbon_migration_test_results_17_concurrency;

CREATE OR REPLACE FUNCTION pg_temp.rl17_assert(
    p_section TEXT, p_assertion TEXT, p_condition BOOLEAN, p_detail TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public._carbon_migration_test_results_17_concurrency(section, assertion, detail, passed)
    VALUES (p_section, p_assertion, p_detail, COALESCE(p_condition, false));
END;
$$;

-- Détermine si dblink existait déjà, et choisit le profil de test.
DO $$
DECLARE
    v_had_dblink BOOLEAN;
    v_user       UUID;
BEGIN
    SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'dblink') INTO v_had_dblink;
    PERFORM set_config('rl17c.had_dblink', v_had_dblink::text, false);

    SELECT id INTO v_user FROM public.profiles ORDER BY created_at LIMIT 1;
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Précondition non satisfaite : aucun profil dans public.profiles.';
    END IF;
    PERFORM set_config('rl17c.user', v_user::text, false);

    IF EXISTS (SELECT 1 FROM public.ai_rate_limit_counters WHERE user_id = v_user) THEN
        RAISE EXCEPTION 'Précondition de propreté non satisfaite : ai_rate_limit_counters contient déjà des lignes pour le profil de test (%). Nettoyer manuellement avant de relancer.', v_user;
    END IF;
END $$;

CREATE EXTENSION IF NOT EXISTS dblink;

-- Pré-remplissage direct : 4/5 déjà consommés sur la fenêtre minute
-- courante, scope analyze_photo -- il ne reste qu'un seul slot.
INSERT INTO public.ai_rate_limit_counters (user_id, scope, window_kind, window_start, request_count)
SELECT current_setting('rl17c.user')::uuid, 'analyze_photo', 'minute', date_trunc('minute', clock_timestamp()), 4;

-- ============================================================
-- LE PROTOCOLE DE CONCURRENCE LUI-MÊME (deux connexions physiques réelles).
-- ============================================================
DO $$
DECLARE
    v_user      UUID := current_setting('rl17c.user')::uuid;
    v_conn_ok   BOOLEAN := false;
    v_allowed2  BOOLEAN;
    v_remaining2 INT;
    v_row       public.ai_rate_limit_result;
BEGIN
    BEGIN
        PERFORM dblink_connect('rl17c_conn', format('dbname=%s', current_database()));
        v_conn_ok := true;
        PERFORM pg_temp.rl17_assert('D', 'D0 connexion dblink secondaire établie (dbname=current_database())', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.rl17_assert('D', 'D0 connexion dblink secondaire établie (dbname=current_database())', false, SQLERRM);
    END;

    IF v_conn_ok THEN
        -- Propage le JWT du profil de test + le rôle applicatif sur la
        -- connexion 2 (SET CONFIG renvoie sa valeur -> dblink(), jamais
        -- dblink_exec() — même technique que 08/09).
        PERFORM t.cfg FROM dblink('rl17c_conn', format(
            'SELECT set_config(''request.jwt.claims'', %L, false)',
            jsonb_build_object('sub', v_user::text, 'role', 'authenticated')::text
        )) AS t(cfg text);
        PERFORM dblink_exec('rl17c_conn', 'SET ROLE authenticated');
        PERFORM dblink_exec('rl17c_conn', 'BEGIN');

        -- Connexion 2 : réclame le dernier slot (5e requête) -- SANS
        -- committer.
        BEGIN
            SELECT t.allowed, t.remaining_minute INTO v_allowed2, v_remaining2 FROM dblink('rl17c_conn',
                'SELECT allowed, remaining_minute FROM public.check_ai_rate_limit(''analyze_photo'')'
            ) AS t(allowed boolean, remaining_minute int);
            PERFORM pg_temp.rl17_assert('D', 'D1 connexion 2 : 5e requête (dernier slot) autorisée, remaining_minute=0 (non committé)', v_allowed2 IS TRUE AND v_remaining2 = 0, format('allowed=%s remaining_minute=%s', v_allowed2, v_remaining2));
        EXCEPTION WHEN OTHERS THEN
            PERFORM pg_temp.rl17_assert('D', 'D1 connexion 2 : 5e requête (dernier slot) autorisée, remaining_minute=0 (non committé)', false, SQLERRM);
        END;

        -- Connexion 1 (session courante) : tente EN CONCURRENCE la même
        -- fenêtre -> doit se heurter réellement au verrou de ligne tenu
        -- (non committé) par la connexion 2. lock_timeout court transforme
        -- le blocage en échec observable, plutôt que d'attendre.
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);
        SET LOCAL lock_timeout = '2s';
        BEGIN
            SET LOCAL ROLE authenticated;
            SELECT * INTO v_row FROM public.check_ai_rate_limit('analyze_photo');
            RESET ROLE;
            PERFORM pg_temp.rl17_assert('D', 'D2 requête concurrente de la connexion 1 bloque réellement (verrou de ligne tenu par la connexion 2) — jamais deux acceptations pour un seul slot', false, 'aucun blocage détecté : la connexion 1 a obtenu une réponse sans attendre');
        EXCEPTION WHEN lock_not_available OR query_canceled THEN
            RESET ROLE;
            PERFORM pg_temp.rl17_assert('D', 'D2 requête concurrente de la connexion 1 bloque réellement (verrou de ligne tenu par la connexion 2) — jamais deux acceptations pour un seul slot', true, SQLERRM);
        END;
        RESET lock_timeout;
        PERFORM set_config('request.jwt.claims', '{}', true);

        -- Connexion 2 committe son acceptation (5/5 désormais réellement
        -- consommé), puis se déconnecte.
        PERFORM dblink_exec('rl17c_conn', 'COMMIT');
        PERFORM dblink_disconnect('rl17c_conn');

        -- Connexion 1 retente, maintenant que la connexion 2 a committé —
        -- doit être REJETÉE (seuil réellement à 5/5), jamais un 6e
        -- acquéreur pour 5 slots.
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);
        SET LOCAL ROLE authenticated;
        SELECT * INTO v_row FROM public.check_ai_rate_limit('analyze_photo');
        RESET ROLE;
        PERFORM pg_temp.rl17_assert('D', 'D3 après commit réel de la connexion 2, la connexion 1 est rejetée (allowed=false) — total accepté strictement 5, jamais 6', v_row.allowed IS FALSE AND v_row.remaining_minute = 0, format('allowed=%s remaining_minute=%s', v_row.allowed, v_row.remaining_minute));
        PERFORM set_config('request.jwt.claims', '{}', true);
    END IF;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RESET lock_timeout;
    PERFORM set_config('request.jwt.claims', '{}', true);
    BEGIN PERFORM dblink_disconnect('rl17c_conn'); EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM pg_temp.rl17_assert('D', 'protocole de concurrence réel (dblink) — échec inattendu, voir détail', false, SQLERRM);
END $$;

SELECT count(*) AS total, count(*) FILTER (WHERE passed) AS reussies, count(*) FILTER (WHERE NOT passed) AS echouees
FROM public._carbon_migration_test_results_17_concurrency;

SELECT section, assertion, passed, detail
FROM public._carbon_migration_test_results_17_concurrency
ORDER BY id;

-- ────────────────────────────────────────────────────────────
-- GATE D0-D3 : exactement 4 assertions, zéro échec. Si dblink échoue à se
-- connecter (D0 en échec), le bloc IF v_conn_ok s'interrompt et seule D0
-- est enregistrée : le gate échoue alors avec un total de 1 au lieu de 4,
-- signalant l'écart d'environnement au lieu de le masquer (même principe
-- que le gate C0-C4 de 08_..._concurrency_STAGING_ONLY.sql).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_total    INT;
    v_failed   INT;
    v_expected INT := 4;
    r RECORD;
BEGIN
    SELECT count(*) INTO v_total FROM public._carbon_migration_test_results_17_concurrency;
    SELECT count(*) INTO v_failed FROM public._carbon_migration_test_results_17_concurrency WHERE NOT passed;

    IF v_failed > 0 THEN
        FOR r IN SELECT section, assertion, detail FROM public._carbon_migration_test_results_17_concurrency WHERE NOT passed ORDER BY id LOOP
            RAISE NOTICE 'ÉCHEC [%] % — %', r.section, r.assertion, r.detail;
        END LOOP;
    END IF;

    RAISE NOTICE '=== Concurrence réelle migration 17 (DEMO) — % assertions (% attendues), % échouées ===', v_total, v_expected, v_failed;
END $$;

-- ════════════════════════════════════════════════════════════
-- NETTOYAGE COMPLET (contrairement aux protocoles STAGING_ONLY précédents
-- de ce dépôt, celui-ci nettoie réellement tout ce qu'il a créé — aucune
-- des trois raisons qui empêchaient le nettoyage sur 08/09 ne s'applique
-- ici, voir en-tête).
-- ════════════════════════════════════════════════════════════
DELETE FROM public.ai_rate_limit_counters WHERE user_id = current_setting('rl17c.user')::uuid;

DO $$
BEGIN
    IF current_setting('rl17c.had_dblink', true) IS DISTINCT FROM 'true' THEN
        DROP EXTENSION IF EXISTS dblink;
    END IF;
END $$;

DROP FUNCTION IF EXISTS pg_temp.rl17_assert(TEXT, TEXT, BOOLEAN, TEXT);

-- Ne PAS DROP la table de résultats ici : inspecter le résumé ci-dessus
-- d'abord. Une fois confirmé, exécuter séparément :
--   DROP TABLE IF EXISTS public._carbon_migration_test_results_17_concurrency;
