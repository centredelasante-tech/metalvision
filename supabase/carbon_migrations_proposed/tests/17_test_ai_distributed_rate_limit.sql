-- ============================================================
-- Tests — Migration carbone 17 (ai_rate_limit_counters + check_ai_rate_limit)
-- GATE IA-3, point 10 : couvre 8 des 9 scénarios requis (le 9e, la
-- concurrence RÉELLE à deux connexions physiques, vit dans le fichier
-- séparé 17_test_ai_distributed_rate_limit_concurrency_DEMO.sql — un test
-- transactionnel classique ne peut pas prouver un verrou entre deux
-- sessions distinctes).
-- ============================================================
--
-- Script de validation SÉPARÉ de la migration elle-même, même convention
-- que 01/02/06/etc. Ne modifie jamais 01-16. À exécuter APRÈS avoir
-- appliqué 17_ai_distributed_rate_limit.sql, jamais avant.
--
-- PROPOSITION — à exécuter manuellement dans le SQL Editor Supabase,
-- uniquement contre METALVISION-DEMO (GATE IA-3, point 11).
--
-- CORRESPONDANCE AVEC LES 9 SCÉNARIOS DEMANDÉS (GATE IA-3, point 10) :
--   1. sous le seuil -> autorisé ......................... B2
--   2. seuil exact ........................................ B5
--   3. dépassement -> 429 (allowed=false, retry_after) .... B6
--   4. utilisateur A n'affecte pas B ...................... B7
--   5. scope assistant n'affecte pas analyze_photo ........ B8
--   6. concurrence réelle .................................. voir fichier _concurrency_DEMO.sql
--   7. utilisateur non authentifié ......................... B1
--   8. tentative de falsifier un user_id ................... B3 + B4
--   9. fenêtre suivante -> accès rétabli ................... B9
--
-- SIMULATION D'AUTHENTIFICATION : même technique standard que les scripts
-- précédents (02/04/05/06/08) — `set_config('request.jwt.claims', ..., true)`
-- + `SET LOCAL ROLE authenticated` pour que auth.uid() ET le contrôle
-- EXECUTE réel sur la fonction soient tous deux exercés. Deux profils
-- réels distincts de public.profiles (FK réelle vers auth.users) servent
-- de sujets A et B — aucune ligne profiles fabriquée ici.
--
-- STRUCTURE EN DEUX PARTIES (retenue depuis la migration 06, correctif
-- structurel) : Supabase SQL Editor exécute tout le texte collé en UNE
-- SEULE transaction implicite. Aucun RAISE EXCEPTION inconditionnel dans
-- la PARTIE 1 — elle se termine donc toujours normalement (COMMIT), que
-- les assertions soient réussies ou non, et la table de résultats persiste
-- pour inspection. La PARTIE 2 (porte de sortie + nettoyage de la table de
-- résultats) est un bloc séparé, à exécuter dans une NOUVELLE requête
-- uniquement après confirmation du résumé.
--
-- NETTOYAGE DES FIXTURES : contrairement aux tables carbone historiques
-- (append-only), ai_rate_limit_counters est une table de compteurs
-- ordinaire — DELETE explicite en fin de PARTIE 1, aucune table métier
-- réelle touchée (aucune organisation/aggregateur/mandat créé par ce
-- fichier). Les deux profils réels réutilisés (A, B) ne sont eux-mêmes
-- jamais modifiés, seuls leurs compteurs de rate limit de test sont
-- purgés.
--
-- RÉSULTAT ATTENDU : 11 assertions Partie A (structurelle) + 10 assertions
-- Partie B (comportementale, B1-B9 + B10 nettoyage) = 21 assertions au
-- total, succès attendu 21/21.
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- PARTIE 1 — FIXTURES, ASSERTIONS, NETTOYAGE, RÉSUMÉ
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public._carbon_migration_test_results_17 (
    id        SERIAL PRIMARY KEY,
    section   TEXT NOT NULL,
    assertion TEXT NOT NULL,
    passed    BOOLEAN NOT NULL,
    detail    TEXT,
    run_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

REVOKE ALL ON public._carbon_migration_test_results_17
FROM PUBLIC, anon, authenticated;

TRUNCATE public._carbon_migration_test_results_17;

-- ════════════════════════════════════════════════════════════
-- PARTIE A — STRUCTURELLE
-- ════════════════════════════════════════════════════════════

INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
SELECT 'A1', 'table ai_rate_limit_counters existe',
       EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='ai_rate_limit_counters'), NULL
UNION ALL
SELECT 'A2', 'RLS activé sur ai_rate_limit_counters',
       COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname='ai_rate_limit_counters' AND relnamespace='public'::regnamespace), false), NULL
UNION ALL
SELECT 'A3', 'PRIMARY KEY (user_id, scope, window_kind, window_start), dans cet ordre',
       COALESCE((
         SELECT array_agg(a.attname::text ORDER BY a.attnum)
           FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
          WHERE i.indrelid = 'public.ai_rate_limit_counters'::regclass AND i.indisprimary
       ) = ARRAY['user_id','scope','window_kind','window_start'], false), NULL
UNION ALL
SELECT 'A4', 'CHECK scope IN (assistant, analyze_photo) présent',
       EXISTS (
         SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.ai_rate_limit_counters'::regclass AND contype = 'c'
           AND pg_get_constraintdef(oid) ILIKE '%scope%' AND pg_get_constraintdef(oid) ILIKE '%assistant%'
           AND pg_get_constraintdef(oid) ILIKE '%analyze_photo%'
       ), NULL
UNION ALL
SELECT 'A5', 'CHECK window_kind IN (minute, day) présent',
       EXISTS (
         SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.ai_rate_limit_counters'::regclass AND contype = 'c'
           AND pg_get_constraintdef(oid) ILIKE '%window_kind%' AND pg_get_constraintdef(oid) ILIKE '%minute%'
           AND pg_get_constraintdef(oid) ILIKE '%day%'
       ), NULL
UNION ALL
SELECT 'A6', 'index idx_ai_rate_limit_counters_window_start existe',
       EXISTS (
         SELECT 1 FROM pg_indexes
         WHERE schemaname='public' AND tablename='ai_rate_limit_counters' AND indexname='idx_ai_rate_limit_counters_window_start'
       ), NULL
UNION ALL
SELECT 'A7', 'aucun privilège table-level pour PUBLIC/anon/authenticated sur ai_rate_limit_counters',
       NOT has_table_privilege('public', 'public.ai_rate_limit_counters', 'SELECT')
       AND NOT has_table_privilege('anon', 'public.ai_rate_limit_counters', 'SELECT')
       AND NOT has_table_privilege('anon', 'public.ai_rate_limit_counters', 'INSERT')
       AND NOT has_table_privilege('authenticated', 'public.ai_rate_limit_counters', 'SELECT')
       AND NOT has_table_privilege('authenticated', 'public.ai_rate_limit_counters', 'INSERT')
       AND NOT has_table_privilege('authenticated', 'public.ai_rate_limit_counters', 'UPDATE')
       AND NOT has_table_privilege('authenticated', 'public.ai_rate_limit_counters', 'DELETE'), NULL
UNION ALL
SELECT 'A8', 'fonction check_ai_rate_limit(text) existe, SECURITY DEFINER, search_path durci',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='check_ai_rate_limit' AND p.pronargs=1
           AND p.prosecdef
           AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg ILIKE 'search_path=%public%pg_temp%')
       ), NULL
UNION ALL
SELECT 'A9', 'EXECUTE check_ai_rate_limit accordé à authenticated seulement (jamais anon/PUBLIC)',
       COALESCE((
         SELECT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
                AND NOT has_function_privilege('public', p.oid, 'EXECUTE')
         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='check_ai_rate_limit' AND p.pronargs=1
       ), false), NULL
UNION ALL
SELECT 'A10', 'fonction purge_ai_rate_limit_counters() existe, EXECUTE accordé à personne (authenticated/anon/PUBLIC)',
       COALESCE((
         SELECT NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
                AND NOT has_function_privilege('public', p.oid, 'EXECUTE')
         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='purge_ai_rate_limit_counters' AND p.pronargs=0
       ), false), NULL
UNION ALL
SELECT 'A11', 'type ai_rate_limit_result possède exactement les 6 attributs attendus, dans l''ordre',
       COALESCE((
         SELECT array_agg(attname::text ORDER BY attnum)
           FROM pg_attribute
          WHERE attrelid = (SELECT typrelid FROM pg_type WHERE typname = 'ai_rate_limit_result' AND typnamespace = 'public'::regnamespace)
            AND attnum > 0 AND NOT attisdropped
       ) = ARRAY['allowed','scope','limit_kind','retry_after_seconds','remaining_minute','remaining_day'], false), NULL;

-- ════════════════════════════════════════════════════════════
-- PARTIE B — COMPORTEMENTALE
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_user_a   UUID;
    v_user_b   UUID;
    v_ok       BOOLEAN;
    v_row      public.ai_rate_limit_result;
    v_i        INT;
    v_detail   TEXT;
BEGIN
    PERFORM set_config('request.jwt.claims', '{}', true);

    IF (SELECT count(*) FROM public.profiles) < 2 THEN
        RAISE EXCEPTION 'Précondition de test non satisfaite : au moins 2 profils réels distincts sont requis dans public.profiles.';
    END IF;

    -- ⚠ correctif : plusieurs profils de démo partagent le même created_at
    -- exact (seed en lot) -- ORDER BY created_at seul ne départage pas les
    -- égalités de façon déterministe entre deux SELECT séparés (deux profils
    -- « aléatoirement » identiques était le bug réel observé ici : B7 a
    -- d'abord échoué parce que v_user_a = v_user_b). id est ajouté comme
    -- discriminant stable.
    SELECT id INTO v_user_a FROM public.profiles ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_user_b FROM public.profiles ORDER BY created_at, id OFFSET 1 LIMIT 1;

    IF v_user_a = v_user_b THEN
        RAISE EXCEPTION 'Précondition de test non satisfaite : v_user_a et v_user_b sont identiques (%) — au moins 2 identifiants distincts sont requis.', v_user_a;
    END IF;

    -- ⚠ PRÉCONDITION DE PROPRETÉ : aucun compteur de rate limit résiduel
    -- pour A ou B avant de commencer (sinon B2/B5/B6/B7/B9 partiraient d'un
    -- état pollué par une exécution précédente non nettoyée).
    IF EXISTS (SELECT 1 FROM public.ai_rate_limit_counters WHERE user_id IN (v_user_a, v_user_b)) THEN
        RAISE EXCEPTION 'Précondition de propreté non satisfaite : ai_rate_limit_counters contient déjà des lignes pour les profils de test A (%) ou B (%). Nettoyer manuellement avant de relancer (une exécution précédente de ce script a probablement échoué avant sa propre PARTIE 1, DELETE final).', v_user_a, v_user_b;
    END IF;

    -- ────────────────────────────────────────────────────────
    -- B1 (point 7 — utilisateur non authentifié)
    -- ────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claims', '{}', true);
    v_ok := false;
    v_detail := NULL;
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM public.check_ai_rate_limit('assistant');
        RESET ROLE;
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        v_ok := (SQLSTATE = '28000' AND SQLERRM = 'check_ai_rate_limit: authentification requise');
        v_detail := SQLERRM;
    END;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B1', 'utilisateur non authentifié (auth.uid() NULL) -> exception 28000 explicite', v_ok, v_detail);

    -- ────────────────────────────────────────────────────────
    -- B2 (point 1 — sous le seuil -> autorisé), scope assistant, user A
    -- ────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_a::text, 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    SELECT * INTO v_row FROM public.check_ai_rate_limit('assistant');
    RESET ROLE;
    v_ok := v_row.allowed IS TRUE AND v_row.limit_kind IS NULL AND v_row.retry_after_seconds IS NULL
            AND v_row.remaining_minute = 19 AND v_row.remaining_day = 199;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B2', '1re requête assistant de A, largement sous le seuil (20/min, 200/jour) -> autorisée, remaining_minute=19, remaining_day=199', v_ok, format('allowed=%s remaining_minute=%s remaining_day=%s', v_row.allowed, v_row.remaining_minute, v_row.remaining_day));

    -- ────────────────────────────────────────────────────────
    -- B3 (point 8a — falsification par paramètre nommé inexistant)
    -- ────────────────────────────────────────────────────────
    v_ok := false;
    v_detail := NULL;
    BEGIN
        EXECUTE format('SELECT public.check_ai_rate_limit(p_scope := %L, p_user_id := %L)', 'assistant', v_user_b);
    EXCEPTION WHEN undefined_function THEN
        v_ok := true;
    WHEN OTHERS THEN
        v_ok := false;
        v_detail := SQLERRM;
    END;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B3', 'aucun paramètre p_user_id n''existe sur la fonction -> falsification via un identifiant fourni par l''appelant structurellement impossible (undefined_function)', v_ok, v_detail);

    -- ────────────────────────────────────────────────────────
    -- B4 (point 8b — falsification par écriture directe de la table)
    -- ────────────────────────────────────────────────────────
    v_ok := false;
    v_detail := NULL;
    BEGIN
        SET LOCAL ROLE authenticated;
        INSERT INTO public.ai_rate_limit_counters (user_id, scope, window_kind, window_start, request_count)
        VALUES (v_user_b, 'assistant', 'minute', date_trunc('minute', clock_timestamp()), 999);
        RESET ROLE;
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        v_ok := true;
    WHEN OTHERS THEN
        RESET ROLE;
        v_detail := SQLERRM;
    END;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B4', 'écriture directe du compteur d''un autre utilisateur (bypass de la fonction) rejetée : aucun privilège table-level (insufficient_privilege)', v_ok, v_detail);

    -- ────────────────────────────────────────────────────────
    -- B5 (point 2 — seuil exact), scope analyze_photo (5/min), user A
    -- ────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_a::text, 'role', 'authenticated')::text, true);
    FOR v_i IN 1..5 LOOP
        SET LOCAL ROLE authenticated;
        SELECT * INTO v_row FROM public.check_ai_rate_limit('analyze_photo');
        RESET ROLE;
        IF v_i < 5 AND v_row.allowed IS NOT TRUE THEN
            RAISE EXCEPTION 'Précondition B5 rompue : la requête analyze_photo #% de A a été refusée avant le seuil (allowed=%).', v_i, v_row.allowed;
        END IF;
    END LOOP;
    v_ok := v_row.allowed IS TRUE AND v_row.remaining_minute = 0;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B5', '5e requête analyze_photo de A (exactement au seuil minute=5) -> encore autorisée, remaining_minute=0', v_ok, format('allowed=%s remaining_minute=%s', v_row.allowed, v_row.remaining_minute));

    -- ────────────────────────────────────────────────────────
    -- B6 (point 3 — dépassement -> refusé), 6e requête analyze_photo, user A
    -- ────────────────────────────────────────────────────────
    SET LOCAL ROLE authenticated;
    SELECT * INTO v_row FROM public.check_ai_rate_limit('analyze_photo');
    RESET ROLE;
    v_ok := v_row.allowed IS FALSE AND v_row.limit_kind = 'minute' AND v_row.retry_after_seconds > 0
            AND v_row.retry_after_seconds <= 60 AND v_row.remaining_minute = 0 AND v_row.remaining_day = 45;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B6', '6e requête analyze_photo de A (dépassement) -> refusée, limit_kind=minute, retry_after_seconds>0, ET remaining_day=45 (le refus ne consomme aucun quota jour réel : 50-5, pas 50-6)', v_ok, format('allowed=%s limit_kind=%s retry_after_seconds=%s remaining_day=%s', v_row.allowed, v_row.limit_kind, v_row.retry_after_seconds, v_row.remaining_day));

    -- ────────────────────────────────────────────────────────
    -- B7 (point 4 — utilisateur A n'affecte pas B), scope analyze_photo, user B
    -- ────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_b::text, 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    SELECT * INTO v_row FROM public.check_ai_rate_limit('analyze_photo');
    RESET ROLE;
    v_ok := v_row.allowed IS TRUE AND v_row.remaining_minute = 4;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B7', 'B, totalement indépendant, appelle analyze_photo alors que A est épuisé sur ce scope -> autorisé, remaining_minute=4 (isolation par utilisateur, auth.uid() exclusivement)', v_ok, format('allowed=%s remaining_minute=%s', v_row.allowed, v_row.remaining_minute));

    -- ────────────────────────────────────────────────────────
    -- B8 (point 5 — scope assistant n'affecte pas analyze_photo), user A
    -- ────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_a::text, 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    SELECT * INTO v_row FROM public.check_ai_rate_limit('assistant');
    RESET ROLE;
    v_ok := v_row.allowed IS TRUE AND v_row.remaining_minute = 18;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B8', 'A, épuisé sur analyze_photo/minute, appelle assistant (2e requête assistant de A) -> autorisé, remaining_minute=18 (isolation par scope)', v_ok, format('allowed=%s remaining_minute=%s', v_row.allowed, v_row.remaining_minute));

    -- ────────────────────────────────────────────────────────
    -- B9 (point 9 — fenêtre suivante -> accès rétabli), scope analyze_photo, user A
    -- ────────────────────────────────────────────────────────
    -- A est actuellement à 5/5 sur analyze_photo pour la fenêtre minute
    -- courante (B5/B6). On simule le passage à la fenêtre suivante en
    -- décalant directement en base l'unique ligne minute existante de 2
    -- minutes dans le passé (accès direct au rôle propriétaire de la table
    -- — jamais possible pour authenticated, voir B4) : check_ai_rate_limit()
    -- recalcule sa propre fenêtre à partir de clock_timestamp() à chaque
    -- appel, donc la fenêtre courante réelle n'a alors plus aucune ligne.
    UPDATE public.ai_rate_limit_counters
       SET window_start = window_start - interval '2 minutes'
     WHERE user_id = v_user_a AND scope = 'analyze_photo' AND window_kind = 'minute';

    SET LOCAL ROLE authenticated;
    SELECT * INTO v_row FROM public.check_ai_rate_limit('analyze_photo');
    RESET ROLE;
    v_ok := v_row.allowed IS TRUE AND v_row.remaining_minute = 4;
    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B9', 'fenêtre minute suivante (simulée) -> accès rétabli pour A sur analyze_photo, remaining_minute=4', v_ok, format('allowed=%s remaining_minute=%s', v_row.allowed, v_row.remaining_minute));

    -- ────────────────────────────────────────────────────────
    -- Nettoyage : table ordinaire (pas append-only) -> DELETE direct,
    -- aucune donnée métier réelle touchée par ce fichier.
    -- ────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claims', '{}', true);
    DELETE FROM public.ai_rate_limit_counters WHERE user_id IN (v_user_a, v_user_b);

    INSERT INTO public._carbon_migration_test_results_17 (section, assertion, passed, detail)
    VALUES ('B10', 'nettoyage final : plus aucune ligne ai_rate_limit_counters pour A ou B après le script',
            NOT EXISTS (SELECT 1 FROM public.ai_rate_limit_counters WHERE user_id IN (v_user_a, v_user_b)), NULL);
END $$;

SELECT count(*) AS total, count(*) FILTER (WHERE passed) AS reussies, count(*) FILTER (WHERE NOT passed) AS echouees
FROM public._carbon_migration_test_results_17;

SELECT section, assertion, passed, detail
FROM public._carbon_migration_test_results_17
ORDER BY section;

-- ════════════════════════════════════════════════════════════
-- FIN DE LA PARTIE 1 — NE RIEN COLLER APRÈS CE POINT DANS LA MÊME EXÉCUTION.
-- Inspecter le résumé ci-dessus. Si total_echouees > 0, NE PAS exécuter la
-- PARTIE 2 (elle supprime la table de résultats) — diagnostiquer d'abord
-- via : SELECT section, assertion, detail FROM public._carbon_migration_test_results_17 WHERE NOT passed ORDER BY section;
-- ════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════
-- PARTIE 2 — PORTE DE SORTIE + NETTOYAGE DE LA TABLE DE RÉSULTATS
-- À COPIER-COLLER ET EXÉCUTER SÉPARÉMENT, UNIQUEMENT APRÈS CONFIRMATION DE
-- 21/21 (10 assertions Partie B, dont B10 = nettoyage) DANS LE RÉSUMÉ CI-DESSUS.
-- ════════════════════════════════════════════════════════════
--
-- DO $$
-- BEGIN
--   IF EXISTS (SELECT 1 FROM public._carbon_migration_test_results_17 WHERE NOT passed) THEN
--     RAISE EXCEPTION 'Validation migration carbone 17 échouée';
--   END IF;
-- END;
-- $$;
--
-- DROP TABLE IF EXISTS public._carbon_migration_test_results_17;
