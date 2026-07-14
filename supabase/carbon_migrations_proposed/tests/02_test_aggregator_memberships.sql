-- ============================================================
-- Tests — Migration carbone 02/07 (Adhésions aux regroupements)
-- ============================================================
--
-- Script de validation SÉPARÉ de la migration elle-même, même convention que
-- 01_test_foundations_events_and_failures.sql : jamais mélanger DDL de
-- migration et code de test. À exécuter APRÈS avoir appliqué
-- 02_carbon_aggregator_memberships.sql, jamais avant.
--
-- PROPOSITION NON APPLIQUÉE — à exécuter manuellement dans le SQL Editor
-- Supabase seulement après approbation, comme la migration elle-même.
--
-- RÉVISÉ après la revue du 14 juillet 2026 (renforcements demandés, en plus
-- des 6 corrections apportées à la migration elle-même) :
--   1. A15 ne compare plus deux totaux globaux mais vérifie une correspondance
--      EXACTE, ligne par ligne, entre organizations.aggregator_id et
--      l'adhésion active de chaque organisation.
--   2. RLS testée sous le RÔLE RÉEL `authenticated` (SET LOCAL ROLE), pas
--      seulement en tant que propriétaire des tables qui contourne RLS
--      structurellement — trois identités : membre d'organisation, admin du
--      regroupement concerné, utilisateur externe.
--   3. Privilèges réels vérifiés via has_table_privilege()/has_function_privilege(),
--      pas seulement l'absence de policy d'écriture.
--   4. Un admin d'organisation ne peut plus s'auto-adhérer à un regroupement
--      (régression décision D1) — testé explicitement.
--   5. L'admin DU REGROUPEMENT CIBLE peut créer l'adhésion (chemin positif D1).
--   6. L'admin d'un AUTRE regroupement ne peut ni créer ni terminer cette
--      adhésion — testé explicitement pour join_aggregator() ET leave_aggregator().
--   7. SECURITY DEFINER, search_path et privilèges d'exécution des trois RPC
--      vérifiés structurellement (Partie A).
--   8. Modification DIRECTE de organizations.aggregator_id testée comme
--      rejetée (décision D5).
--   9. request.jwt.claims explicitement réinitialisé avant B1, pour que les
--      tests de porte d'authentification ne dépendent pas d'un état de
--      session résiduel du SQL Editor.
--
-- PRINCIPE (repris de la migration 01) : toute erreur INATTENDUE doit faire
-- échouer visiblement ce script. Seules les erreurs explicitement ANTICIPÉES
-- par un test précis sont capturées localement — aucun bloc EXCEPTION WHEN
-- OTHERS généralisé.
--
-- DONNÉES DE TEST : une organisation et deux regroupements jetables créés
-- directement (bypass RLS, rôle propriétaire des tables) pour les tests
-- structurels B4-B8, PLUS deux regroupements supplémentaires créés via la
-- RPC create_aggregator_with_primary_admin() elle-même (pour que
-- aggregator_admins soit peuplée par le code réel de la migration, pas par
-- une hypothèse de test sur le nom de sa colonne d'audit — voir l'avertissement
-- ⚠ en tête de la migration au sujet de nominated_by). Nettoyage explicite en
-- fin de script — jamais par DELETE naïf sur les tables append-only
-- (aggregator_memberships, carbon_business_events), qui nécessitent la
-- technique de désactivation temporaire du trigger, comme dans la migration 01.
--
-- SIMULATION D'AUTHENTIFICATION : les RPC de cette migration vérifient
-- auth.uid() et is_platform_superadmin() (lecture de auth.jwt()). Le SQL
-- Editor Supabase exécute les requêtes comme le rôle propriétaire des
-- tables, SANS contexte JWT (auth.uid() y est naturellement NULL) — ce qui
-- permet de tester directement le rejet "Authentification requise." (B1-B3)
-- sans aucune simulation. Pour tester les chemins de succès des RPC et les
-- policies RLS, ce script utilise la technique standard Supabase de
-- simulation de session : `set_config('request.jwt.claims', ..., true)`,
-- dont `auth.uid()` et `auth.jwt()` dérivent. Cette simulation ne modifie
-- aucun compte réel et est réinitialisée explicitement avant la fin du bloc.
--
-- UN SEUL PROFIL RÉEL DISPONIBLE, GARANTI PAR PRÉCONDITION : toutes les
-- identités testées (super-admin, admin d'organisation, admin du
-- regroupement cible, admin d'un AUTRE regroupement) réutilisent
-- SÉQUENTIELLEMENT le même profil réel, en faisant varier les lignes
-- organization_members / aggregator_admins et le contenu du JWT simulé entre
-- chaque test — jamais deux conditions à la fois quand le test prétend en
-- isoler une seule. Le cas « utilisateur externe » utilise un sub JWT
-- aléatoire (gen_random_uuid()) qui ne correspond à AUCUNE ligne nulle part,
-- sans avoir besoin d'un second profil réel.
--
-- RLS SOUS LE RÔLE RÉEL `authenticated` : le rôle propriétaire des tables
-- (celui du SQL Editor) contourne RLS structurellement, quelle que soit la
-- policy. `SET LOCAL ROLE authenticated` (portée : la transaction courante)
-- force la véritable évaluation des policies et des GRANTs de table pour les
-- requêtes qui suivent — `RESET ROLE` restaure le rôle propriétaire
-- immédiatement après chaque vérification, avant toute autre opération de
-- fixture (qui a besoin des privilèges élevés du propriétaire).
--
-- PRÉCONDITION : au moins un profil doit exister dans public.profiles pour
-- servir de "super-admin simulé" (p_primary_admin_user_id doit référencer un
-- profil réel, contrainte FK). Si aucun profil n'existe, le script échoue
-- explicitement avec un message clair plutôt que d'ignorer silencieusement
-- les tests concernés.
--
-- Constat hors périmètre relevé en préparant ce script (non corrigé ici,
-- signalé pour information) : organization_members n'a, dans l'état actuel
-- du schéma, AUCUNE contrainte d'unicité sur (organization_id, user_id) —
-- l'index unique partiel prévu par une migration antérieure (ccf_002) n'a
-- pas survécu au reset complet du schéma public. Sans incidence sur ce
-- script (qui supprime explicitement la ligne avant toute réinsertion), mais
-- à garder en tête si une dette technique CCF est traitée séparément.
-- ============================================================

CREATE TABLE IF NOT EXISTS public._carbon_migration_test_results (
    id        SERIAL PRIMARY KEY,
    section   TEXT NOT NULL,
    assertion TEXT NOT NULL,
    passed    BOOLEAN NOT NULL,
    detail    TEXT,
    run_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

REVOKE ALL ON public._carbon_migration_test_results
FROM PUBLIC, anon, authenticated;

TRUNCATE public._carbon_migration_test_results;

-- ════════════════════════════════════════════════════════════
-- PARTIE A — STRUCTURELLE
-- ════════════════════════════════════════════════════════════

INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
SELECT 'A1', 'table aggregator_memberships existe',
       EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='aggregator_memberships'), NULL
UNION ALL
SELECT 'A2', 'RLS activé sur aggregator_memberships',
       COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname='aggregator_memberships' AND relnamespace='public'::regnamespace), false), NULL
UNION ALL
-- Renforcé après deuxième revue : vérifie la DÉFINITION de l'index, pas
-- seulement son nom — UNIQUE, portant sur organization_id, filtré sur
-- ended_at IS NULL (pas n'importe quelle colonne/condition).
SELECT 'A3', 'index unique partiel UNIQUE(organization_id) WHERE ended_at IS NULL existe (pas seulement son nom)',
       EXISTS (
         SELECT 1 FROM pg_indexes
         WHERE schemaname='public' AND tablename='aggregator_memberships' AND indexname='idx_aggregator_memberships_one_active_per_org'
           AND indexdef ILIKE '%UNIQUE%'
           AND indexdef ILIKE '%organization_id%'
           AND indexdef ILIKE '%ended_at IS NULL%'
       ), NULL
UNION ALL
-- Renforcé après deuxième revue (décision D8) : ended_at >= started_at (pas
-- > strict) — now() est stable pendant toute la transaction PostgreSQL.
SELECT 'A4', 'contrainte CHECK ended_at IS NULL OR ended_at >= started_at existe (décision D8)',
       EXISTS (
         SELECT 1 FROM pg_constraint
         WHERE conname='aggregator_memberships_ended_after_started'
           AND pg_get_constraintdef(oid) ILIKE '%>=%'
       ), NULL
UNION ALL
SELECT 'A5', 'trigger de garde UPDATE (aggregator_memberships_guard_update) existe',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='aggregator_memberships_guard_update' AND NOT tgisinternal), NULL
UNION ALL
SELECT 'A6', 'trigger de rejet DELETE (aggregator_memberships_reject_delete) existe et réutilise carbon_reject_update_delete()',
       EXISTS (
         SELECT 1 FROM pg_trigger t
         JOIN pg_proc p ON p.oid = t.tgfoid
         WHERE t.tgname = 'aggregator_memberships_reject_delete' AND NOT t.tgisinternal
           AND p.proname = 'carbon_reject_update_delete'
       ), NULL
UNION ALL
SELECT 'A7', 'trigger de compatibilité (sync organizations.aggregator_id) existe',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='aggregator_memberships_sync_organizations_compat' AND NOT tgisinternal), NULL
UNION ALL
SELECT 'A8', 'fonction create_aggregator_with_primary_admin(text,text,uuid) existe',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='create_aggregator_with_primary_admin' AND p.pronargs = 3
       ), NULL
UNION ALL
SELECT 'A9', 'fonction join_aggregator(uuid,uuid) existe',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='join_aggregator' AND p.pronargs = 2
       ), NULL
UNION ALL
SELECT 'A10', 'fonction leave_aggregator(uuid,text) existe',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='leave_aggregator' AND p.pronargs = 2
       ), NULL
UNION ALL
SELECT 'A11', 'policy SELECT aggregator_memberships_select existe',
       EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='aggregator_memberships' AND policyname='aggregator_memberships_select'), NULL
UNION ALL
SELECT 'A12', 'organizations.aggregator_id porte un commentaire de dépréciation (migration carbone 02)',
       COALESCE(col_description('public.organizations'::regclass, (
           SELECT attnum FROM pg_attribute WHERE attrelid='public.organizations'::regclass AND attname='aggregator_id'
       )), '') ILIKE '%migration carbone 02%', NULL
UNION ALL
SELECT 'A13', 'fonction carbon_guard_aggregator_membership_update() existe',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='carbon_guard_aggregator_membership_update'
       ), NULL
UNION ALL
SELECT 'A14', 'fonction carbon_sync_organizations_aggregator_id_compat() existe',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='carbon_sync_organizations_aggregator_id_compat'
       ), NULL
UNION ALL
-- Renforcé après revue : ne compare plus deux totaux globaux (qui peuvent
-- masquer des lignes croisées incorrectement) mais vérifie, organisation par
-- organisation, que organizations.aggregator_id correspond EXACTEMENT à
-- l'aggregator_id de son adhésion active (ou NULL des deux côtés).
SELECT 'A15', 'backfill cohérent : correspondance EXACTE ligne à ligne entre organizations.aggregator_id et l''adhésion active (pas seulement un total global)',
       NOT EXISTS (
           SELECT 1
           FROM public.organizations o
           LEFT JOIN public.aggregator_memberships m
             ON m.organization_id = o.id AND m.ended_at IS NULL
           WHERE o.aggregator_id IS DISTINCT FROM m.aggregator_id
       ),
       (SELECT string_agg(
           o.id::text || ' (organizations.aggregator_id=' || COALESCE(o.aggregator_id::text, 'NULL')
                       || ', adhésion active=' || COALESCE(m.aggregator_id::text, 'NULL') || ')',
           '; '
       )
       FROM public.organizations o
       LEFT JOIN public.aggregator_memberships m
         ON m.organization_id = o.id AND m.ended_at IS NULL
       WHERE o.aggregator_id IS DISTINCT FROM m.aggregator_id)
UNION ALL
-- Renforcement (revue, point 7) : SECURITY DEFINER sur les trois RPC.
SELECT 'A16', 'les trois RPC (create_aggregator_with_primary_admin, join_aggregator, leave_aggregator) sont SECURITY DEFINER',
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.prosecdef
          AND ((p.proname='create_aggregator_with_primary_admin' AND p.pronargs=3)
            OR (p.proname='join_aggregator' AND p.pronargs=2)
            OR (p.proname='leave_aggregator' AND p.pronargs=2))) = 3,
       NULL
UNION ALL
-- Renforcement (revue, point 7) : durcissement search_path sur les trois RPC.
-- Comparaison volontairement souple (ILIKE) plutôt qu'une égalité stricte
-- sur le format exact de proconfig, non garanti stable — ne pas sur-fitter
-- sur une sérialisation Postgres non contractuelle.
SELECT 'A17', 'les trois RPC portent SET search_path = public, pg_temp (durcissement)',
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public'
          AND ((p.proname='create_aggregator_with_primary_admin' AND p.pronargs=3)
            OR (p.proname='join_aggregator' AND p.pronargs=2)
            OR (p.proname='leave_aggregator' AND p.pronargs=2))
          AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg ILIKE 'search_path=%public%pg_temp%')) = 3,
       NULL
UNION ALL
-- Renforcement (revue, point 7) : privilège EXECUTE réel — accordé à
-- authenticated, absent de anon — pour les trois RPC.
-- COALESCE(..., false) (renforcement deuxième revue) : bool_and() renvoie
-- NULL sur un ensemble vide (aucune fonction trouvée) — incompatible avec la
-- colonne passed BOOLEAN NOT NULL, et masquerait silencieusement l'absence
-- des fonctions comme un succès si non corrigé.
SELECT 'A18', 'privilège EXECUTE réel : accordé à authenticated, absent de anon, pour les trois RPC',
       COALESCE((SELECT bool_and(
           has_function_privilege('authenticated', p.oid, 'EXECUTE')
           AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
        )
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public'
          AND ((p.proname='create_aggregator_with_primary_admin' AND p.pronargs=3)
            OR (p.proname='join_aggregator' AND p.pronargs=2)
            OR (p.proname='leave_aggregator' AND p.pronargs=2))), false),
       NULL
UNION ALL
-- Renforcement (revue, points 3-4) : privilèges réels sur aggregator_memberships
-- via has_table_privilege(), pas seulement l'absence de policy d'écriture.
SELECT 'A19', 'authenticated a SELECT mais aucun privilège d''écriture direct sur aggregator_memberships (décision D6)',
       has_table_privilege('authenticated', 'public.aggregator_memberships', 'SELECT')
       AND NOT has_table_privilege('authenticated', 'public.aggregator_memberships', 'INSERT')
       AND NOT has_table_privilege('authenticated', 'public.aggregator_memberships', 'UPDATE')
       AND NOT has_table_privilege('authenticated', 'public.aggregator_memberships', 'DELETE'),
       NULL
UNION ALL
SELECT 'A20', 'anon n''a aucun privilège (ni lecture ni écriture) sur aggregator_memberships (décision D6)',
       NOT has_table_privilege('anon', 'public.aggregator_memberships', 'SELECT')
       AND NOT has_table_privilege('anon', 'public.aggregator_memberships', 'INSERT')
       AND NOT has_table_privilege('anon', 'public.aggregator_memberships', 'UPDATE')
       AND NOT has_table_privilege('anon', 'public.aggregator_memberships', 'DELETE'),
       NULL
UNION ALL
-- Renforcement (revue, point 3, décision D5) : garde-fou contre l'écriture
-- directe de organizations.aggregator_id.
SELECT 'A21', 'fonction carbon_guard_organizations_aggregator_id_direct_write() existe (décision D5)',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='carbon_guard_organizations_aggregator_id_direct_write'), NULL
UNION ALL
-- Renforcé après deuxième revue : vérifie que le trigger appelle bien la
-- fonction attendue (via tgfoid), pas seulement que son NOM existe.
-- Renforcé ENCORE après troisième revue (point 1) : vérifie aussi, via
-- pg_get_triggerdef(), que le trigger est réellement BEFORE (pas AFTER) et
-- porte spécifiquement sur UPDATE OF aggregator_id (pas un UPDATE générique
-- sur toutes les colonnes, qui déclencherait le garde-fou bien plus souvent
-- que nécessaire, ou un mauvais moment de déclenchement qui le rendrait inopérant).
SELECT 'A22', 'trigger organizations_guard_aggregator_id_direct_write est réellement BEFORE UPDATE OF aggregator_id sur organizations ET appelle carbon_guard_organizations_aggregator_id_direct_write() (décision D5)',
       EXISTS (
         SELECT 1 FROM pg_trigger t
         JOIN pg_class c ON c.oid = t.tgrelid
         JOIN pg_proc p ON p.oid = t.tgfoid
         WHERE c.relname = 'organizations' AND t.tgname = 'organizations_guard_aggregator_id_direct_write'
           AND NOT t.tgisinternal
           AND p.proname = 'carbon_guard_organizations_aggregator_id_direct_write'
           AND pg_get_triggerdef(t.oid) ILIKE '%BEFORE UPDATE OF%'
           AND pg_get_triggerdef(t.oid) ILIKE '%aggregator_id%'
       ), NULL
UNION ALL
-- Renforcement (deuxième revue, décision D7) : la fonction de synchronisation
-- est bien SECURITY DEFINER et son EXECUTE est révoqué à PUBLIC/anon/authenticated
-- — les deux conditions dont dépend le garde-fou durci.
SELECT 'A23', 'carbon_sync_organizations_aggregator_id_compat() est SECURITY DEFINER, EXECUTE révoqué à PUBLIC/anon/authenticated (décision D7)',
       COALESCE((
         SELECT p.prosecdef
                AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'carbon_sync_organizations_aggregator_id_compat'
       ), false), NULL
UNION ALL
-- Renforcement (troisième revue, point 3) : chaque adhésion issue du
-- backfill (décision D9) possède réellement son événement
-- aggregator_membership_started, avec le payload exact attendu — pas
-- seulement « un événement existe », mais source = migration_02_backfill ET
-- started_at_approximate = true. Les adhésions issues du backfill sont
-- identifiables sans ambiguïté par started_by IS NULL : join_aggregator()
-- exige toujours auth.uid() (jamais NULL), alors que le backfill insère
-- explicitement started_by = NULL.
SELECT 'A24', 'chaque adhésion issue du backfill (started_by IS NULL) a son événement aggregator_membership_started avec source=migration_02_backfill et started_at_approximate=true (décision D9)',
       NOT EXISTS (
           SELECT 1 FROM public.aggregator_memberships m
           WHERE m.started_by IS NULL
             AND NOT EXISTS (
                 SELECT 1 FROM public.carbon_business_events e
                 WHERE e.event_type = 'aggregator_membership_started'
                   AND e.object_id = m.id
                   AND (e.payload->>'source') = 'migration_02_backfill'
                   AND (e.payload->>'started_at_approximate')::boolean IS TRUE
             )
       ),
       (SELECT string_agg(m.id::text, ', ')
        FROM public.aggregator_memberships m
        WHERE m.started_by IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM public.carbon_business_events e
              WHERE e.event_type = 'aggregator_membership_started'
                AND e.object_id = m.id
                AND (e.payload->>'source') = 'migration_02_backfill'
                AND (e.payload->>'started_at_approximate')::boolean IS TRUE
          ));

-- ════════════════════════════════════════════════════════════
-- PARTIE B — COMPORTEMENTALE
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_ok                      BOOLEAN;
    v_test_org_id             UUID;
    v_test_aggregator_id      UUID;
    v_test_aggregator_id_2    UUID;
    v_created_aggregator_id   UUID;
    v_created_aggregator_id_2 UUID;
    v_fixture_profile_id      UUID;
    v_outsider_uid            UUID;
    v_membership_id           UUID;
    v_join_membership_id      UUID;
    v_left_id                 UUID;
    v_b5_id                   UUID;
    v_rls_count               INTEGER;
    v_aggregator_id_before    UUID;
    v_b30_sync_owner          name;
BEGIN
    -- ────────────────────────────────────────────────────────
    -- Renforcement (revue, point 9) : réinitialise explicitement
    -- request.jwt.claims à un JSON vide AVANT B1, pour que les tests de
    -- porte d'authentification ne dépendent pas d'un état de session
    -- résiduel du SQL Editor (une exécution précédente pourrait avoir
    -- laissé une valeur simulée active dans la même connexion).
    -- ────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claims', '{}', true);

    -- ────────────────────────────────────────────────────────
    -- B1-B3 : porte d'authentification, AUCUNE simulation au-delà de la
    -- réinitialisation ci-dessus — état ambiant réel du SQL Editor
    -- (auth.uid() est NULL, pas de contexte JWT).
    -- ────────────────────────────────────────────────────────

    v_ok := false;
    BEGIN
        PERFORM public.join_aggregator(gen_random_uuid(), gen_random_uuid());
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Authentification requise.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B1', 'join_aggregator() sans contexte authentifié lève "Authentification requise."', v_ok, NULL);

    v_ok := false;
    BEGIN
        PERFORM public.create_aggregator_with_primary_admin('x', 'x', gen_random_uuid());
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Authentification requise.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B2', 'create_aggregator_with_primary_admin() sans contexte authentifié lève "Authentification requise."', v_ok, NULL);

    v_ok := false;
    BEGIN
        PERFORM public.leave_aggregator(gen_random_uuid(), NULL);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Authentification requise.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B3', 'leave_aggregator() sans contexte authentifié lève "Authentification requise."', v_ok, NULL);

    -- ────────────────────────────────────────────────────────
    -- Fixtures de test (organisation + 2 regroupements jetables, création
    -- directe, bypass RLS en tant que propriétaire des tables)
    -- ────────────────────────────────────────────────────────

    INSERT INTO public.organizations (name) VALUES ('__test_migration_02_org__') RETURNING id INTO v_test_org_id;
    INSERT INTO public.aggregators (name) VALUES ('__test_migration_02_aggregator__') RETURNING id INTO v_test_aggregator_id;
    INSERT INTO public.aggregators (name) VALUES ('__test_migration_02_aggregator_2__') RETURNING id INTO v_test_aggregator_id_2;

    SELECT id INTO v_fixture_profile_id FROM public.profiles ORDER BY created_at LIMIT 1;
    IF v_fixture_profile_id IS NULL THEN
        RAISE EXCEPTION 'Précondition de test non satisfaite : aucun profil dans public.profiles pour simuler un contexte authentifié (nécessaire aux RPC testées ci-dessous).';
    END IF;

    -- ────────────────────────────────────────────────────────
    -- B4-B8 : tests directs sur la table (bypass RPC), aucune simulation
    -- d'authentification nécessaire — vérifient les contraintes/triggers
    -- eux-mêmes, pas la couche d'autorisation des RPC.
    -- ────────────────────────────────────────────────────────

    -- Adhésion de référence, nécessaire pour B4, B6, B7, B8.
    INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by)
    VALUES (v_test_org_id, v_test_aggregator_id, v_fixture_profile_id)
    RETURNING id INTO v_membership_id;

    -- B4. Doublon d'adhésion active pour la même organisation rejeté par
    -- l'index unique partiel.
    v_ok := false;
    BEGIN
        INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by)
        VALUES (v_test_org_id, v_test_aggregator_id_2, v_fixture_profile_id);
    EXCEPTION WHEN unique_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B4', 'doublon d''adhésion active rejeté par l''index unique partiel', v_ok, NULL);

    -- B5. CHECK ended_at > started_at rejette une valeur antérieure —
    -- nettoyage conditionnel si l'insertion réussissait à tort (ended_at
    -- NOT NULL ici, donc hors de portée de l'index unique partiel : le seul
    -- filet de sécurité testé est bien le CHECK).
    v_ok := false;
    v_b5_id := NULL;
    BEGIN
        INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by, started_at, ended_at)
        VALUES (v_test_org_id, v_test_aggregator_id_2, v_fixture_profile_id, now(), now() - interval '1 day')
        RETURNING id INTO v_b5_id;
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B5', 'CHECK ended_at > started_at rejette une valeur antérieure', v_ok, NULL);
    IF NOT v_ok AND v_b5_id IS NOT NULL THEN
        ALTER TABLE public.aggregator_memberships DISABLE TRIGGER aggregator_memberships_reject_delete;
        DELETE FROM public.aggregator_memberships WHERE id = v_b5_id;
        ALTER TABLE public.aggregator_memberships ENABLE TRIGGER aggregator_memberships_reject_delete;
    END IF;

    -- B6. Le trigger de garde rejette un changement d'aggregator_id combiné
    -- à une fin d'adhésion (seules ended_at/ended_by/end_reason sont permises).
    v_ok := false;
    BEGIN
        UPDATE public.aggregator_memberships
        SET aggregator_id = v_test_aggregator_id_2, ended_at = now()
        WHERE id = v_membership_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B6', 'trigger de garde rejette un changement d''aggregator_id lors de la fin d''adhésion', v_ok, NULL);

    -- Fin d'adhésion valide (seule transition permise) — nécessaire pour B7.
    -- Termine aussi, via le trigger de compatibilité, la seule référence de
    -- organizations.aggregator_id posée jusqu'ici pour v_test_org_id : les
    -- tests B13 et suivants repartent donc d'une organisation SANS adhésion
    -- active, comme attendu.
    UPDATE public.aggregator_memberships
    SET ended_at = now(), ended_by = v_fixture_profile_id, end_reason = 'fin test migration 02 (B7 setup)'
    WHERE id = v_membership_id;

    -- B7. Le trigger de garde rejette une DEUXIÈME transition de ended_at
    -- sur une adhésion déjà terminée.
    v_ok := false;
    BEGIN
        UPDATE public.aggregator_memberships SET ended_at = now() WHERE id = v_membership_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B7', 'trigger de garde rejette une deuxième transition de ended_at', v_ok, NULL);

    -- B8. DELETE rejeté (append-only, réutilise carbon_reject_update_delete()).
    v_ok := false;
    BEGIN
        DELETE FROM public.aggregator_memberships WHERE id = v_membership_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B8', 'DELETE sur aggregator_memberships rejeté (append-only)', v_ok, NULL);

    -- ────────────────────────────────────────────────────────
    -- B9-B12 : chemins de succès de create_aggregator_with_primary_admin(),
    -- contexte authentifié simulé (super-admin), technique standard Supabase
    -- request.jwt.claims.
    -- ────────────────────────────────────────────────────────

    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object('role', 'admin'))::text,
        true
    );

    -- B9. create_aggregator_with_primary_admin() réussit pour un super-admin
    -- simulé. Aucun EXCEPTION WHEN ici : ceci est le chemin de succès attendu,
    -- une erreur ici serait un vrai bug et doit remonter telle quelle.
    v_created_aggregator_id := public.create_aggregator_with_primary_admin(
        '__test_migration_02_bootstrap__', 'test bootstrap migration 02', v_fixture_profile_id
    );
    v_ok := v_created_aggregator_id IS NOT NULL;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B9', 'create_aggregator_with_primary_admin() crée le regroupement (super-admin simulé)', v_ok, v_created_aggregator_id::text);

    -- B10. Le primary_admin est correctement inséré dans aggregator_admins.
    v_ok := EXISTS (
        SELECT 1 FROM public.aggregator_admins
        WHERE aggregator_id = v_created_aggregator_id
          AND user_id = v_fixture_profile_id
          AND role = 'primary_admin'
          AND revoked_at IS NULL
    );
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B10', 'primary_admin inséré dans aggregator_admins par create_aggregator_with_primary_admin()', v_ok, NULL);

    -- B11. Événement aggregator_created journalisé.
    v_ok := EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type = 'aggregator_created' AND object_id = v_created_aggregator_id);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B11', 'événement aggregator_created journalisé', v_ok, NULL);

    -- B12. Événement aggregator_admin_appointed journalisé (décision D4).
    v_ok := EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type = 'aggregator_admin_appointed' AND aggregator_id = v_created_aggregator_id);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B12', 'événement aggregator_admin_appointed journalisé (décision D4)', v_ok, NULL);

    -- ────────────────────────────────────────────────────────
    -- B13 : bootstrap d'un DEUXIÈME regroupement, toujours sous contexte
    -- super-admin — permet de disposer de deux regroupements dont le MÊME
    -- profil réel est administrateur, pour isoler ensuite précisément
    -- « admin du regroupement CIBLE » de « admin d'un AUTRE regroupement »
    -- (décision D1) sans avoir besoin d'un second profil réel. Créé via la
    -- RPC elle-même (pas par INSERT direct dans aggregator_admins), pour ne
    -- pas dépendre d'une hypothèse de test sur le nom réel de sa colonne
    -- d'audit (nominated_by, non confirmée en direct — voir migration).
    -- ────────────────────────────────────────────────────────

    v_created_aggregator_id_2 := public.create_aggregator_with_primary_admin(
        '__test_migration_02_bootstrap_2__', 'test bootstrap migration 02 (regroupement cible)', v_fixture_profile_id
    );
    v_ok := v_created_aggregator_id_2 IS NOT NULL;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B13', 'création d''un deuxième regroupement (super-admin simulé), nécessaire pour isoler admin-du-regroupement-cible vs admin-d''un-autre-regroupement', v_ok, v_created_aggregator_id_2::text);

    -- Révoque immédiatement l'admin du profil sur le regroupement CIBLE
    -- (v_created_aggregator_id_2) : à ce stade, le profil ne doit être admin
    -- QUE du regroupement v_created_aggregator_id (« l'AUTRE » regroupement
    -- pour les tests qui suivent), pas encore de la cible.
    UPDATE public.aggregator_admins
    SET revoked_at = now()
    WHERE aggregator_id = v_created_aggregator_id_2 AND user_id = v_fixture_profile_id AND revoked_at IS NULL;

    -- Fin du contexte super-admin : bascule vers un contexte authentifié SANS
    -- app_metadata.role = 'admin' pour tout ce qui suit — is_platform_superadmin()
    -- doit désormais être FALSE, isolant réellement les branches testées.
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text,
        true
    );

    -- B14 (renforcement revue) : le profil est admin d'un AUTRE regroupement
    -- (v_created_aggregator_id), PAS de la cible (v_created_aggregator_id_2),
    -- et n'est PAS ENCORE admin d'organisation ni super-admin. join_aggregator()
    -- vers la cible doit être rejetée — être admin d'un regroupement
    -- QUELCONQUE ne suffit pas, il faut celui ciblé (décision D1).
    v_ok := false;
    BEGIN
        PERFORM public.join_aggregator(v_test_org_id, v_created_aggregator_id_2);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Seul un administrateur du regroupement cible ou un super-administrateur peut ajouter une organisation à ce regroupement.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B14', 'join_aggregator() rejette l''admin d''un AUTRE regroupement (pas celui ciblé) — décision D1', v_ok, NULL);

    -- Le profil devient AUSSI admin d'ORGANISATION (mais toujours pas admin
    -- du regroupement cible). Isole spécifiquement la régression du modèle
    -- initial refusé en revue (auto-adhésion libre par l'admin d'organisation).
    INSERT INTO public.organization_members (organization_id, user_id, org_role, status, activated_at)
    VALUES (v_test_org_id, v_fixture_profile_id, 'admin'::public.org_role, 'active', now());

    -- B15 (renforcement revue — cœur de la correction D1) : admin
    -- d'ORGANISATION seul (toujours pas admin du regroupement cible) —
    -- join_aggregator() doit rester rejetée. Confirme qu'être admin de
    -- l'ORGANISATION n'ouvre plus, à lui seul, l'auto-adhésion à n'importe
    -- quel regroupement.
    v_ok := false;
    BEGIN
        PERFORM public.join_aggregator(v_test_org_id, v_created_aggregator_id_2);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Seul un administrateur du regroupement cible ou un super-administrateur peut ajouter une organisation à ce regroupement.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B15', 'join_aggregator() rejette l''admin d''organisation seul (auto-adhésion) — régression décision D1', v_ok, NULL);

    -- Réactive l'admin du profil sur le regroupement CIBLE : le profil est
    -- maintenant admin d'organisation ET admin du regroupement cible ET admin
    -- d'un autre regroupement (situation réaliste, pas artificiellement isolée).
    UPDATE public.aggregator_admins
    SET revoked_at = NULL
    WHERE aggregator_id = v_created_aggregator_id_2 AND user_id = v_fixture_profile_id;

    -- B16 (chemin positif D1) : join_aggregator() réussit pour l'admin DU
    -- REGROUPEMENT CIBLE.
    v_join_membership_id := public.join_aggregator(v_test_org_id, v_created_aggregator_id_2);
    v_ok := v_join_membership_id IS NOT NULL;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B16', 'join_aggregator() réussit pour l''admin DU REGROUPEMENT CIBLE (décision D1 corrigée)', v_ok, v_join_membership_id::text);

    -- B17. Le trigger de compatibilité synchronise organizations.aggregator_id.
    v_ok := (SELECT aggregator_id FROM public.organizations WHERE id = v_test_org_id) = v_created_aggregator_id_2;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B17', 'trigger de compatibilité synchronise organizations.aggregator_id après join_aggregator()', v_ok, NULL);

    -- B18. Une deuxième tentative de join_aggregator() par un appelant
    -- AUTORISÉ (toujours admin du regroupement cible) est rejetée par la
    -- pré-vérification métier explicite de la RPC (déjà une adhésion active),
    -- pas seulement par l'index unique en dernier recours.
    v_ok := false;
    BEGIN
        PERFORM public.join_aggregator(v_test_org_id, v_created_aggregator_id_2);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Cette organisation a déjà une adhésion active à un regroupement — utilisez leave_aggregator() avant d''en rejoindre un autre.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B18', 'join_aggregator() rejette une deuxième adhésion active avec le message métier attendu (appelant pourtant autorisé)', v_ok, NULL);

    -- ────────────────────────────────────────────────────────
    -- B19-B21 (renforcement revue) : RLS SOUS LE RÔLE RÉEL `authenticated`.
    -- Le rôle propriétaire des tables (SQL Editor) contourne RLS
    -- structurellement — SET LOCAL ROLE force la véritable évaluation des
    -- policies. Chaque identité isolée : une seule condition vraie à la fois.
    -- ────────────────────────────────────────────────────────

    -- 1) Membre d'organisation SANS rôle admin, ET PAS admin du regroupement.
    UPDATE public.organization_members SET org_role = 'membre'::public.org_role
    WHERE organization_id = v_test_org_id AND user_id = v_fixture_profile_id;

    UPDATE public.aggregator_admins
    SET revoked_at = now()
    WHERE aggregator_id = v_created_aggregator_id_2 AND user_id = v_fixture_profile_id AND revoked_at IS NULL;

    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO v_rls_count FROM public.aggregator_memberships
    WHERE organization_id = v_test_org_id AND aggregator_id = v_created_aggregator_id_2 AND ended_at IS NULL;
    EXECUTE 'RESET ROLE';
    v_ok := (v_rls_count = 1);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B19', 'RLS (rôle authenticated réel) : un membre d''organisation SANS rôle admin, PAS admin du regroupement, voit l''adhésion active de son organisation', v_ok, NULL);

    -- 2) Admin DU REGROUPEMENT CONCERNÉ, ET PAS membre de l'organisation.
    DELETE FROM public.organization_members
    WHERE organization_id = v_test_org_id AND user_id = v_fixture_profile_id;

    UPDATE public.aggregator_admins
    SET revoked_at = NULL
    WHERE aggregator_id = v_created_aggregator_id_2 AND user_id = v_fixture_profile_id;

    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO v_rls_count FROM public.aggregator_memberships
    WHERE organization_id = v_test_org_id AND aggregator_id = v_created_aggregator_id_2 AND ended_at IS NULL;
    EXECUTE 'RESET ROLE';
    v_ok := (v_rls_count = 1);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B20', 'RLS (rôle authenticated réel) : l''admin du regroupement concerné, PAS membre de l''organisation, voit l''adhésion', v_ok, NULL);

    -- 3) Utilisateur externe : sub JWT aléatoire, aucune ligne nulle part.
    v_outsider_uid := gen_random_uuid();
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_outsider_uid, 'app_metadata', json_build_object())::text,
        true
    );
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO v_rls_count FROM public.aggregator_memberships
    WHERE organization_id = v_test_org_id AND aggregator_id = v_created_aggregator_id_2 AND ended_at IS NULL;
    EXECUTE 'RESET ROLE';
    v_ok := (v_rls_count = 0);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B21', 'RLS (rôle authenticated réel) : un utilisateur externe (aucune relation) ne voit rien', v_ok, NULL);

    -- Restaure le contexte JWT du profil réel pour la suite.
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text,
        true
    );

    -- ────────────────────────────────────────────────────────
    -- B22-B23 (renforcement revue) : leave_aggregator() — isole « admin d'un
    -- AUTRE regroupement » (rejeté) de « admin du regroupement CONCERNÉ »
    -- (accepté), décision D2bis.
    -- ────────────────────────────────────────────────────────

    -- Ne garde QUE l'admin sur l'AUTRE regroupement (v_created_aggregator_id) :
    -- pas d'admin d'organisation, pas d'admin du regroupement cible.
    UPDATE public.aggregator_admins
    SET revoked_at = now()
    WHERE aggregator_id = v_created_aggregator_id_2 AND user_id = v_fixture_profile_id AND revoked_at IS NULL;

    -- B22. leave_aggregator() rejette l'admin d'un AUTRE regroupement, avec
    -- le message générique attendu (décision D2bis — ne distingue pas
    -- « adhésion introuvable » de « accès refusé »).
    v_ok := false;
    BEGIN
        PERFORM public.leave_aggregator(v_test_org_id, 'tentative refusée (B22)');
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Adhésion active introuvable ou accès refusé.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B22', 'leave_aggregator() rejette l''admin d''un AUTRE regroupement avec le message générique (décision D2bis)', v_ok, NULL);

    -- Réactive l'admin sur le regroupement CIBLE (celui concerné par l'adhésion).
    UPDATE public.aggregator_admins
    SET revoked_at = NULL
    WHERE aggregator_id = v_created_aggregator_id_2 AND user_id = v_fixture_profile_id;

    -- B23. leave_aggregator() réussit pour l'admin du regroupement CONCERNÉ
    -- (et lui seul ici — pas d'admin d'organisation à ce stade).
    v_left_id := public.leave_aggregator(v_test_org_id, 'fin test migration 02 (B23)');
    v_ok := v_left_id = v_join_membership_id;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B23', 'leave_aggregator() termine l''adhésion pour l''admin du regroupement CONCERNÉ (décision D2)', v_ok, NULL);

    -- B24. Le trigger de compatibilité remet organizations.aggregator_id à NULL.
    v_ok := (SELECT aggregator_id FROM public.organizations WHERE id = v_test_org_id) IS NULL;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B24', 'trigger de compatibilité remet organizations.aggregator_id à NULL après leave_aggregator()', v_ok, NULL);

    -- B25. Les deux événements start/end de ce cycle d'adhésion sont journalisés.
    v_ok := EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type = 'aggregator_membership_started' AND object_id = v_join_membership_id)
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type = 'aggregator_membership_ended' AND object_id = v_join_membership_id);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B25', 'événements aggregator_membership_started et aggregator_membership_ended journalisés', v_ok, NULL);

    -- B26 (renforcement revue, décision D5) : modification DIRECTE de
    -- organizations.aggregator_id (sans passer par le mécanisme de
    -- compatibilité, donc sans le marqueur transactionnel) doit être
    -- rejetée par organizations_guard_aggregator_id_direct_write.
    v_ok := false;
    BEGIN
        UPDATE public.organizations SET aggregator_id = v_test_aggregator_id WHERE id = v_test_org_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B26', 'modification directe de organizations.aggregator_id rejetée (décision D5)', v_ok, NULL);

    -- B27 (renforcement deuxième revue, RECONÇU après cinquième revue point 2) :
    -- falsifier SEUL le marqueur transactionnel, sous le rôle réel
    -- `authenticated` (pas le propriétaire des tables), ne doit jamais
    -- aboutir à une écriture RÉELLE de organizations.aggregator_id. Ce test ne
    -- prétend PAS isoler LAQUELLE des deux couches a bloqué l'écriture — RLS/
    -- un défaut de GRANT avant même d'atteindre le trigger, OU le garde-fou
    -- lui-même — les deux sont également acceptables ici, et exiger l'un en
    -- particulier aurait produit un FAUX ÉCHEC si authenticated n'a tout
    -- simplement pas le GRANT UPDATE de base sur organizations (un état par
    -- ailleurs parfaitement légitime, pas un défaut). La vérification se fait
    -- uniquement sur le résultat observable : la valeur n'a pas changé. B28
    -- et B30 isolent spécifiquement le garde-fou lui-même, indépendamment de
    -- tout privilège de GRANT, en opérant comme propriétaire des tables.
    v_aggregator_id_before := (SELECT aggregator_id FROM public.organizations WHERE id = v_test_org_id);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
        PERFORM set_config('metaltrace.carbon_membership_sync', 'on', true);
        UPDATE public.organizations SET aggregator_id = v_test_aggregator_id_2 WHERE id = v_test_org_id;
    EXCEPTION
        WHEN raise_exception OR insufficient_privilege THEN
            NULL; -- rejet anticipé, peu importe la couche — la preuve se fait ci-dessous sur la valeur réelle
    END;
    EXECUTE 'RESET ROLE';
    v_ok := ((SELECT aggregator_id FROM public.organizations WHERE id = v_test_org_id) IS NOT DISTINCT FROM v_aggregator_id_before);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B27', 'sous authenticated, falsifier le marqueur n''aboutit à AUCUNE écriture réelle de organizations.aggregator_id (RLS/GRANT ou garde-fou, peu importe lequel — B28/B30 isolent le garde-fou spécifiquement)', v_ok, NULL);

    -- B28 (ajouté après troisième revue, point 2) : preuve DÉFINITIVE et
    -- indépendante de tout privilège de GRANT que le garde-fou LUI-MÊME
    -- rejette une écriture non imbriquée. Exécuté en tant que PROPRIÉTAIRE
    -- des tables (qui a nécessairement le privilège UPDATE sur organizations
    -- — élimine toute ambiguïté avec un rejet de type insufficient_privilege).
    -- Le marqueur est positionné manuellement à 'on' au PREMIER niveau, hors
    -- de tout contexte de trigger imbriqué : pg_trigger_depth() vaudra 1 au
    -- moment où le garde-fou s'exécute, jamais 2 — la condition qui échoue
    -- ici est nécessairement celle de la profondeur d'imbrication (même si
    -- current_user correspond, par ailleurs, au propriétaire de la fonction
    -- de synchronisation, puisque le propriétaire des tables l'est souvent
    -- aussi).
    v_ok := false;
    BEGIN
        PERFORM set_config('metaltrace.carbon_membership_sync', 'on', true);
        UPDATE public.organizations SET aggregator_id = v_test_aggregator_id WHERE id = v_test_org_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'organizations.aggregator_id est dépréciée et ne peut être modifiée directement — utilisez join_aggregator()/leave_aggregator() (aggregator_memberships).');
    END;
    PERFORM set_config('metaltrace.carbon_membership_sync', 'off', true);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B28', 'marqueur positionné manuellement au premier niveau (hors trigger imbriqué) reste rejeté par le garde-fou lui-même — preuve indépendante des privilèges (décision D7)', v_ok, NULL);

    -- B29 (renforcement deuxième revue, décision D7) : une UPDATE ciblant
    -- aggregator_id mais SANS changer sa valeur réelle reste permise, même
    -- hors du mécanisme de compatibilité — ne casse pas un ancien formulaire
    -- qui renverrait la ligne complète, y compris un aggregator_id inchangé.
    -- v_test_org_id n'a aucune adhésion active à ce stade (NULL depuis B24),
    -- donc NULL = NULL (IS NOT DISTINCT FROM) doit être accepté.
    v_ok := false;
    BEGIN
        UPDATE public.organizations SET aggregator_id = aggregator_id WHERE id = v_test_org_id;
        v_ok := true;
    EXCEPTION WHEN raise_exception THEN
        v_ok := false;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B29', 'UPDATE de organizations.aggregator_id avec valeur INCHANGÉE reste permise (décision D7)', v_ok, NULL);

    -- B30 (ajouté après quatrième revue, REFORMULÉ après cinquième revue) :
    -- teste un appel imbriqué à la bonne profondeur (pg_trigger_depth() >= 2)
    -- avec le bon propriétaire (current_user = propriétaire de
    -- carbon_sync_organizations_aggregator_id_compat()), mais avec un
    -- marqueur ABSENT, RÉINITIALISÉ OU NON ACTIF (c'est-à-dire, dans tous les
    -- cas, IS DISTINCT FROM 'on') — pas spécifiquement un NULL littéral.
    -- set_config(clé, NULL, true) NE GARANTIT PAS un retour à NULL : selon la
    -- documentation Postgres, cela revient à un RESET, qui peut réappliquer
    -- une valeur de session déjà positionnée plutôt qu'un état vraiment
    -- indéfini — d'autant plus fragile que cette même clé a déjà été
    -- manipulée plusieurs fois plus tôt dans ce script (par le trigger de
    -- compatibilité à chaque join_aggregator()/leave_aggregator(), et
    -- directement par B27 et B28 ci-dessus).
    -- Le garde-fou corrigé traite de toute façon NULL, 'off' ou toute autre
    -- valeur non-'on' de façon strictement identique (IS DISTINCT FROM 'on'),
    -- donc positionner explicitement 'off' — une valeur certaine, sans
    -- dépendre d'une sémantique de reset non garantie — teste exactement la
    -- même branche du garde-fou sans reposer sur une hypothèse fragile.
    -- Un trigger temporaire, test-only, simule l'appel imbriqué : un
    -- déclencheur AFTER UPDATE OF name sur organizations (profondeur 1)
    -- exécute lui-même une UPDATE ciblant aggregator_id (le garde-fou
    -- s'exécute donc à la profondeur 2), sans jamais toucher au marqueur.
    -- Comme ce trigger n'est PAS SECURITY DEFINER, current_user y reste celui
    -- de la session ambiante (le propriétaire des tables dans ce script, qui
    -- est aussi le propriétaire de la fonction de synchronisation dans cet
    -- environnement).
    PERFORM set_config('metaltrace.carbon_membership_sync', 'off', true);

    -- Préconditions EXPLICITES (ajoutées après cinquième revue, point 3) :
    -- sans cette vérification, B30 pourrait réussir pour une tout autre
    -- raison que celle qu'il prétend isoler (par exemple si current_user ne
    -- correspond pas au propriétaire attendu dans cet environnement) — un
    -- succès dans ce cas ne prouverait rien sur le défaut corrigé. Échec loud
    -- (RAISE EXCEPTION non capturée, arrête tout le script) si l'une des deux
    -- ne tient pas, plutôt qu'un B30 silencieusement non concluant.
    IF current_setting('metaltrace.carbon_membership_sync', true) = 'on' THEN
        RAISE EXCEPTION 'Précondition B30 non satisfaite : le marqueur vaut ''on'', B30 ne peut pas tester le cas où il est absent/réinitialisé/non actif.';
    END IF;

    SELECT r.rolname INTO v_b30_sync_owner
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE p.oid = to_regprocedure('public.carbon_sync_organizations_aggregator_id_compat()');

    IF v_b30_sync_owner IS NULL THEN
        RAISE EXCEPTION 'Précondition B30 non satisfaite : impossible de résoudre le propriétaire de carbon_sync_organizations_aggregator_id_compat() via to_regprocedure().';
    END IF;

    IF current_user::name IS DISTINCT FROM v_b30_sync_owner THEN
        RAISE EXCEPTION 'Précondition B30 non satisfaite : current_user (%) ne correspond pas au propriétaire attendu (%) dans cet environnement — B30 ne peut pas isoler correctement la condition « bon propriétaire, marqueur non actif » qu''il prétend tester.', current_user, v_b30_sync_owner;
    END IF;

    CREATE OR REPLACE FUNCTION public._test_b30_nested_write_no_marker()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $_b30_func$
    BEGIN
        UPDATE public.organizations
        SET aggregator_id = (SELECT id FROM public.aggregators WHERE name = '__test_migration_02_aggregator__')
        WHERE id = NEW.id;
        RETURN NEW;
    END;
    $_b30_func$;

    CREATE TRIGGER _test_b30_trigger
        AFTER UPDATE OF name ON public.organizations
        FOR EACH ROW EXECUTE FUNCTION public._test_b30_nested_write_no_marker();

    -- Vérifie le message EXACT du garde-fou (renforcement après cinquième
    -- revue, point 3) — pas seulement qu'une exception quelconque a été
    -- levée, pour écarter qu'une autre erreur inattendue soit confondue avec
    -- le rejet attendu du garde-fou.
    v_ok := false;
    BEGIN
        UPDATE public.organizations SET name = name || ' (test b30)' WHERE id = v_test_org_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'organizations.aggregator_id est dépréciée et ne peut être modifiée directement — utilisez join_aggregator()/leave_aggregator() (aggregator_memberships).');
    END;

    DROP TRIGGER _test_b30_trigger ON public.organizations;
    DROP FUNCTION public._test_b30_nested_write_no_marker();

    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B30', 'appel imbriqué (depth>=2, bon propriétaire) avec marqueur absent/réinitialisé/non actif (IS DISTINCT FROM ''on'') reste rejeté avec le message exact du garde-fou (décision D7, corrigée en cinquième revue)', v_ok, NULL);

    -- ────────────────────────────────────────────────────────
    -- Fixture pour B31-B32 (couverture positive complémentaire, D2
    -- INCHANGÉE) : l'admin d'ORGANISATION seul (sans être admin d'aucun
    -- regroupement) doit toujours pouvoir terminer l'adhésion active de SA
    -- PROPRE organisation — ce chemin de D2 n'a pas été modifié par la
    -- correction D1 (qui ne concerne que join_aggregator()) et reste testé
    -- explicitement ici, pour ne pas perdre cette couverture en corrigeant
    -- B13-B18. Cette section n'est que la mise
    -- en place des fixtures pour B31 et B32 ci-dessous.
    -- ────────────────────────────────────────────────────────

    -- Ré-établit une adhésion active via le raccourci super-admin (simple
    -- fixture ici — ne re-teste pas D1, déjà couvert par B14-B18).
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object('role', 'admin'))::text,
        true
    );
    v_join_membership_id := public.join_aggregator(v_test_org_id, v_created_aggregator_id_2);

    -- Contexte : admin d'ORGANISATION seul — aucun rôle actif dans aggregator_admins.
    -- CORRECTION (deuxième revue, point 4) : la révocation ci-dessous est
    -- STRICTEMENT limitée aux deux regroupements créés par CE script
    -- (v_created_aggregator_id, v_created_aggregator_id_2). Une version
    -- antérieure de ce test ne filtrait que sur user_id, ce qui aurait révoqué
    -- N'IMPORTE QUELLE attribution aggregator_admins réelle et préexistante du
    -- profil sélectionné, sans les restaurer au nettoyage — un DELETE de
    -- données réelles hors du périmètre du test. Aucune instruction de ce
    -- script ne doit jamais modifier une ligne en dehors des objets
    -- __test_migration_02_*.
    INSERT INTO public.organization_members (organization_id, user_id, org_role, status, activated_at)
    VALUES (v_test_org_id, v_fixture_profile_id, 'admin'::public.org_role, 'active', now());
    UPDATE public.aggregator_admins SET revoked_at = now()
    WHERE user_id = v_fixture_profile_id
      AND aggregator_id IN (v_created_aggregator_id, v_created_aggregator_id_2)
      AND revoked_at IS NULL;

    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text,
        true
    );

    -- B31. leave_aggregator() réussit pour l'admin d'ORGANISATION seul
    -- (branche D2 inchangée, non affectée par la correction D1).
    v_left_id := public.leave_aggregator(v_test_org_id, 'fin test migration 02 (B31, admin organisation seul)');
    v_ok := v_left_id = v_join_membership_id;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B31', 'leave_aggregator() réussit pour l''admin d''ORGANISATION seul (décision D2, inchangée par D1)', v_ok, NULL);

    -- B32. Événements du second cycle d'adhésion journalisés.
    v_ok := EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type = 'aggregator_membership_started' AND object_id = v_join_membership_id)
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type = 'aggregator_membership_ended' AND object_id = v_join_membership_id);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B32', 'événements journalisés pour le deuxième cycle d''adhésion (B31)', v_ok, NULL);

    -- Fin de la simulation d'authentification — restaure l'état ambiant NULL.
    PERFORM set_config('request.jwt.claims', '{}', true);

    -- ────────────────────────────────────────────────────────
    -- NETTOYAGE — toujours exécuté, indépendamment du résultat des
    -- assertions ci-dessus. Ordre imposé par les FK RESTRICT :
    -- carbon_business_events (append-only) avant aggregator_memberships
    -- (append-only) avant aggregator_admins avant aggregators/organization_members
    -- avant organizations.
    -- ────────────────────────────────────────────────────────

    ALTER TABLE public.carbon_business_events DISABLE TRIGGER carbon_business_events_no_update_delete;
    DELETE FROM public.carbon_business_events
    WHERE aggregator_id IN (v_test_aggregator_id, v_test_aggregator_id_2, v_created_aggregator_id, v_created_aggregator_id_2)
       OR organization_id = v_test_org_id;
    ALTER TABLE public.carbon_business_events ENABLE TRIGGER carbon_business_events_no_update_delete;

    ALTER TABLE public.aggregator_memberships DISABLE TRIGGER aggregator_memberships_reject_delete;
    DELETE FROM public.aggregator_memberships
    WHERE organization_id = v_test_org_id
       OR aggregator_id IN (v_test_aggregator_id, v_test_aggregator_id_2, v_created_aggregator_id, v_created_aggregator_id_2);
    ALTER TABLE public.aggregator_memberships ENABLE TRIGGER aggregator_memberships_reject_delete;

    -- aggregator_admins n'est pas append-only (table pré-existante, hors
    -- périmètre de cette migration) : DELETE direct suffit, et la CASCADE
    -- de aggregators -> aggregator_admins couvrirait de toute façon les lignes
    -- restantes si elles n'étaient pas déjà retirées ici.
    DELETE FROM public.aggregator_admins WHERE aggregator_id IN (v_created_aggregator_id, v_created_aggregator_id_2);

    -- organization_members n'est pas append-only non plus (table CCF
    -- pré-existante) ; sa FK organization_id est de toute façon ON DELETE
    -- CASCADE depuis organizations, mais explicite ici par hygiène de test.
    -- Idempotent : la ligne a déjà été supprimée à l'étape B20 ci-dessus dans
    -- le cas nominal, ce DELETE ne fait alors rien.
    DELETE FROM public.organization_members WHERE organization_id = v_test_org_id AND user_id = v_fixture_profile_id;

    DELETE FROM public.aggregators WHERE id IN (v_test_aggregator_id, v_test_aggregator_id_2, v_created_aggregator_id, v_created_aggregator_id_2);
    DELETE FROM public.organizations WHERE id = v_test_org_id;

    -- Note : aucun bloc EXCEPTION WHEN OTHERS n'enveloppe ce DO block dans son
    -- ensemble. Une erreur véritablement inattendue remonte telle quelle et
    -- fait échouer visiblement ce script.
END $$;

-- ════════════════════════════════════════════════════════════
-- RÉSUMÉ — visible dans l'onglet Results
-- ════════════════════════════════════════════════════════════

SELECT section, assertion, passed, detail
FROM public._carbon_migration_test_results
ORDER BY id;

SELECT
    count(*) AS total_assertions,
    count(*) FILTER (WHERE passed) AS total_reussies,
    count(*) FILTER (WHERE NOT passed) AS total_echouees
FROM public._carbon_migration_test_results;

-- ════════════════════════════════════════════════════════════
-- PORTE DE SORTIE BRUYANTE — même mécanique que la migration 01 : fait
-- échouer le script dès qu'une seule assertion vaut false.
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public._carbon_migration_test_results
    WHERE NOT passed
  ) THEN
    RAISE EXCEPTION 'Validation migration carbone 02 échouée';
  END IF;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- NETTOYAGE DE LA TABLE DE TEST — même logique que la migration 01 : si une
-- assertion a échoué, le RAISE EXCEPTION ci-dessus arrête le script avant ce
-- DROP (table conservée pour diagnostic). En cas de succès complet, elle est
-- supprimée ici.
-- ════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS public._carbon_migration_test_results;
