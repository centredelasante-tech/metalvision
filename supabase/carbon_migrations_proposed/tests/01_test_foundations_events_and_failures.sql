-- ============================================================
-- Tests — Migration carbone 01/07 (Fondations transverses)
-- ============================================================
--
-- Script de validation SÉPARÉ de la migration elle-même (correction reçue
-- après revue : ne jamais mélanger DDL de migration et code de test dans
-- le même fichier). À exécuter APRÈS avoir appliqué
-- 01_carbon_foundations_events_and_failures.sql, jamais avant.
--
-- PROPOSITION NON APPLIQUÉE — à exécuter manuellement dans le SQL Editor
-- Supabase seulement après approbation, comme la migration elle-même.
--
-- PRINCIPE (correction reçue, point 6) : toute erreur INATTENDUE doit faire
-- échouer visiblement ce script (remonter comme une vraie erreur Postgres
-- dans l'interface), pas être avalée silencieusement. Seules les erreurs
-- explicitement ANTICIPÉES par un test précis sont capturées localement.
-- Aucun bloc EXCEPTION WHEN OTHERS généralisé n'encapsule l'ensemble du
-- script — un bug réel doit se voir.
--
-- Les résultats sont écrits dans une table PERMANENTE (pas TEMP — leçon
-- déjà tirée de MetalTrace_MVP_Validation_Suite_v2_0.sql : une TEMP TABLE
-- ne survit pas nécessairement à un découpage multi-connexions du SQL
-- Editor Supabase), affichée à la fin via un SELECT visible dans l'onglet
-- Results.
--
-- CHANGEMENTS DEPUIS LA RÉVISION PRÉCÉDENTE (3 nouvelles corrections ciblées) :
--   - B1/B2 : nettoyage ajouté. Si le CHECK testé ne rejetait pas la ligne
--     invalide (assertion échouée), la ligne existait réellement, ne serait
--     jamais nettoyée par ce script (la seule section de nettoyage existante
--     ciblait les id de B3/B4/B5 connus à l'avance) et resterait dans
--     carbon_business_events. Chaque test capture désormais l'id éventuel via
--     RETURNING et le supprime (technique de désactivation temporaire du
--     trigger append-only, déjà utilisée ailleurs) si l'insertion a réussi.
--   - REVOKE ALL ajouté juste après la création de
--     _carbon_migration_test_results : si le script échoue et que la table
--     est laissée en place pour inspection (voir porte de sortie bruyante en
--     fin de script), elle ne doit pas rester accessible aux rôles
--     applicatifs (PUBLIC, anon, authenticated) dans l'intervalle.
--   - A15 assoupli : vérifie l'existence de carbon_reject_update_delete() ET
--     que les deux triggers append-only l'utilisent bien, mais n'exige plus
--     l'absence globale d'une fonction reject_update_delete() qui pourrait
--     légitimement appartenir à un autre domaine du schéma partagé.
--
-- CHANGEMENTS DEPUIS LA RÉVISION PRÉCÉDENTE (2 corrections ciblées reçues) :
--   - A14 mis à jour : vérifie désormais que can_view_carbon_event(...) a
--     exactement 4 paramètres ET que son corps ne contient plus aucune
--     lecture de carbon_business_events (recherche littérale dans
--     pg_proc.prosrc) — preuve structurelle que la récursion RLS corrigée
--     dans la migration (révision 4) est bien celle exécutée.
--   - Ajout, en toute fin de script (après la porte de sortie bruyante), du
--     DROP TABLE de _carbon_migration_test_results — cette table utilitaire
--     ne doit pas rester exposée durablement dans public (2e correction
--     ciblée reçue).
--
-- CHANGEMENTS DEPUIS LA VERSION PRÉCÉDENTE (revue à 8 points reçue) :
--   - A9 : compte réel du catalogue event_type porté de 25 à 31.
--   - A13-A16 (nouveaux) : colonne verification_session_id, existence de
--     can_view_carbon_event(), renommage effectif de la fonction trigger en
--     carbon_reject_update_delete() (et absence de l'ancien nom générique),
--     présence du nouvel object_type 'aggregator_admin'.
--   - B5 renommé et reformulé (point 2 de la revue) : ce test démontre
--     UNIQUEMENT la survie d'une insertion au rollback-to-savepoint d'un
--     bloc EXCEPTION imbriqué — PAS une garantie générale de persistance de
--     carbon_rpc_failures face à une RPC qui relancerait l'exception ou face
--     à l'annulation de la transaction englobante. Voir la note avant B5
--     ci-dessous et Tranche0-Carbone-Architecture.md §11bis.
--   - Ajout, en toute fin de script, d'un bloc DO qui fait échouer bruyamment
--     ce script (RAISE EXCEPTION) si une seule assertion comportementale a
--     été enregistrée avec passed = false (point 8 de la revue) — jusqu'ici,
--     une assertion B1..B6 à false était simplement consignée sans arrêter
--     le script ni garantir le nettoyage de la ligne invalide créée.
--
-- Note sur la suggestion « idéalement, dans une transaction terminée par
-- ROLLBACK » : non retenue ici. La leçon déjà tirée sur
-- MetalTrace_MVP_Validation_Suite_v2_0.sql est qu'un script multi-instructions
-- peut être exécuté par le SQL Editor Supabase à travers plusieurs connexions
-- sous-jacentes, ce qui rend un BEGIN/ROLLBACK explicite entourant tout le
-- script non fiable (état déjà observé : une TEMP TABLE créée en début de
-- script pouvait ne plus exister à la fin). La technique de désactivation
-- temporaire du trigger append-only, ciblée et documentée comme test-only,
-- est conservée par prudence — elle ne dépend d'aucune hypothèse sur la
-- continuité de connexion entre les instructions du script.
-- ============================================================

CREATE TABLE IF NOT EXISTS public._carbon_migration_test_results (
    id        SERIAL PRIMARY KEY,
    section   TEXT NOT NULL,
    assertion TEXT NOT NULL,
    passed    BOOLEAN NOT NULL,
    detail    TEXT,
    run_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Correction ciblée reçue après revue : si ce script échoue et laisse la
-- table en place pour inspection (voir la porte de sortie bruyante en fin de
-- script), elle ne doit pas rester exposée aux rôles applicatifs entre-temps.
-- Table de test uniquement, jamais lue ni écrite par une RPC métier.
REVOKE ALL ON public._carbon_migration_test_results
FROM PUBLIC, anon, authenticated;

TRUNCATE public._carbon_migration_test_results;

-- ════════════════════════════════════════════════════════════
-- PARTIE A — STRUCTURELLE
-- ════════════════════════════════════════════════════════════

INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
SELECT 'A1', 'extension btree_gist installée',
       EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist'), NULL
UNION ALL
SELECT 'A2', 'table carbon_business_events existe',
       EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='carbon_business_events'), NULL
UNION ALL
SELECT 'A3', 'table carbon_rpc_failures existe',
       EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='carbon_rpc_failures'), NULL
UNION ALL
SELECT 'A4', 'colonne aggregator_id présente sur carbon_business_events (correction 4)',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='carbon_business_events' AND column_name='aggregator_id'), NULL
UNION ALL
SELECT 'A5', 'RLS activé sur carbon_business_events',
       COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname='carbon_business_events' AND relnamespace='public'::regnamespace), false), NULL
UNION ALL
SELECT 'A6', 'RLS activé sur carbon_rpc_failures',
       COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname='carbon_rpc_failures' AND relnamespace='public'::regnamespace), false), NULL
UNION ALL
SELECT 'A7', 'trigger append-only sur carbon_business_events existe',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='carbon_business_events_no_update_delete' AND NOT tgisinternal), NULL
UNION ALL
SELECT 'A8', 'trigger append-only sur carbon_rpc_failures existe',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='carbon_rpc_failures_no_update_delete' AND NOT tgisinternal), NULL
UNION ALL
-- Correction 5 (revue migration 01) puis correction 6 (revue à 8 points) :
-- compte RÉEL des valeurs du CHECK event_type, pas une assertion de façade —
-- parse la définition réelle de la contrainte stockée par Postgres et compte
-- les littéraux entre guillemets simples. Catalogue porté de 25 à 31 valeurs
-- (ajout des 3 événements de gouvernance, de verification_session_completed,
-- et de credit_sale_cancelled/credit_sale_settled).
SELECT 'A9', 'catalogue event_type contient exactement 31 valeurs',
       (
         SELECT count(*)
         FROM pg_constraint c
         CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''[a-z_]+''', 'g')
         WHERE c.conname = 'carbon_business_events_event_type_check'
       ) = 31,
       'compte réel : ' || (
         SELECT count(*)::text
         FROM pg_constraint c
         CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''[a-z_]+''', 'g')
         WHERE c.conname = 'carbon_business_events_event_type_check'
       )
UNION ALL
SELECT 'A10', 'credit_issuance_voided et credit_issuance_externally_cancelled sont deux valeurs distinctes du catalogue',
       (
         SELECT count(*) FROM unnest(ARRAY['credit_issuance_voided','credit_issuance_externally_cancelled']) v
         WHERE pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname='carbon_business_events_event_type_check')) LIKE '%''' || v || '''%'
       ) = 2, NULL
UNION ALL
SELECT 'A11', 'policy SELECT carbon_business_events existe',
       EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='carbon_business_events' AND policyname='carbon_business_events_select'), NULL
UNION ALL
SELECT 'A12', 'policy SELECT carbon_rpc_failures existe',
       EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='carbon_rpc_failures' AND policyname='carbon_rpc_failures_select'), NULL
UNION ALL
-- A13-A16 : ajouts de la revue à 8 points.
SELECT 'A13', 'colonne verification_session_id présente sur carbon_business_events (correction 5, portée RLS MRV)',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='carbon_business_events' AND column_name='verification_session_id'), NULL
UNION ALL
SELECT 'A14', 'fonction can_view_carbon_event(...) existe avec 4 paramètres scalaires, sans lecture de carbon_business_events (récursion RLS évitée)',
       EXISTS (
         SELECT 1 FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'can_view_carbon_event' AND p.pronargs = 4
       )
       AND (
         SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'can_view_carbon_event' AND p.pronargs = 4
       ) NOT ILIKE '%FROM%carbon_business_events%', NULL
UNION ALL
-- Assoupli (correction ciblée reçue après revue) : vérifie que
-- carbon_reject_update_delete() existe ET que les deux triggers append-only
-- l'utilisent effectivement, SANS exiger l'absence globale d'une fonction
-- reject_update_delete() générique — celle-ci pourrait légitimement
-- appartenir à un autre domaine du schéma partagé, sans lien avec le
-- renommage effectué ici (correction 7).
SELECT 'A15', 'fonction carbon_reject_update_delete() existe ET les deux triggers append-only l''utilisent (renommage, correction 7)',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'carbon_reject_update_delete'
       )
       AND (
         SELECT count(*)
         FROM pg_trigger t
         JOIN pg_proc p ON p.oid = t.tgfoid
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE t.tgname IN ('carbon_business_events_no_update_delete', 'carbon_rpc_failures_no_update_delete')
           AND NOT t.tgisinternal
           AND n.nspname = 'public'
           AND p.proname = 'carbon_reject_update_delete'
       ) = 2, NULL
UNION ALL
SELECT 'A16', 'object_type contient aggregator_admin (requis par les 3 nouveaux événements de gouvernance, correction 6)',
       pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname='carbon_business_events_object_type_check')) LIKE '%''aggregator_admin''%', NULL;

-- ════════════════════════════════════════════════════════════
-- PARTIE B — COMPORTEMENTALE
-- Toute erreur non anticipée n'est PAS interceptée ici : elle remonte et
-- fait échouer visiblement le script (correction 6).
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_ok           BOOLEAN;
    v_event_id     UUID;
    v_failure_id   UUID;
    v_found        BOOLEAN;
    v_b1_id        UUID;
    v_b2_id        UUID;
BEGIN
    -- B1. event_type invalide rejeté par le CHECK — erreur ANTICIPÉE,
    -- interceptée précisément (check_violation), rien d'autre.
    v_ok := false;
    v_b1_id := NULL;
    BEGIN
        INSERT INTO public.carbon_business_events (event_type, object_type, object_id)
        VALUES ('type_volontairement_invalide', 'aggregator', gen_random_uuid())
        RETURNING id INTO v_b1_id;
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B1', 'event_type invalide rejeté', v_ok, NULL);

    -- Nettoyage (correction ciblée reçue après revue) : si le CHECK n'a PAS
    -- rejeté l'insertion (assertion échouée, v_ok resté false), la ligne
    -- invalide existe réellement dans une table append-only — RETURNING a
    -- capturé son id avant que le bloc EXCEPTION ne s'exécute (ou non). Une
    -- assertion échouée ne doit jamais laisser de donnée de test dans
    -- carbon_business_events : on la retire via la même technique de
    -- désactivation temporaire du trigger que le nettoyage final ci-dessous.
    IF NOT v_ok AND v_b1_id IS NOT NULL THEN
        ALTER TABLE public.carbon_business_events DISABLE TRIGGER carbon_business_events_no_update_delete;
        DELETE FROM public.carbon_business_events WHERE id = v_b1_id;
        ALTER TABLE public.carbon_business_events ENABLE TRIGGER carbon_business_events_no_update_delete;
    END IF;

    -- B2. object_type invalide rejeté par le CHECK
    v_ok := false;
    v_b2_id := NULL;
    BEGIN
        INSERT INTO public.carbon_business_events (event_type, object_type, object_id)
        VALUES ('aggregator_created', 'type_objet_inexistant', gen_random_uuid())
        RETURNING id INTO v_b2_id;
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B2', 'object_type invalide rejeté', v_ok, NULL);

    -- Même nettoyage que B1, pour la même raison (correction ciblée reçue).
    IF NOT v_ok AND v_b2_id IS NOT NULL THEN
        ALTER TABLE public.carbon_business_events DISABLE TRIGGER carbon_business_events_no_update_delete;
        DELETE FROM public.carbon_business_events WHERE id = v_b2_id;
        ALTER TABLE public.carbon_business_events ENABLE TRIGGER carbon_business_events_no_update_delete;
    END IF;

    -- Insertion valide de référence pour B3/B4 (nécessaire pour tester
    -- l'UPDATE/DELETE sur une ligne réelle)
    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, payload)
    VALUES ('aggregator_created', 'aggregator', gen_random_uuid(), '{"test": true}'::jsonb)
    RETURNING id INTO v_event_id;

    -- B3. UPDATE rejeté (append-only) — erreur ANTICIPÉE (levée par
    -- carbon_reject_update_delete(), capturée génériquement ICI seulement parce
    -- que RAISE EXCEPTION sans code SQLSTATE précis lève 'P0001' (raise_exception),
    -- un code Postgres standard et prévisible pour cette fonction précise.
    v_ok := false;
    BEGIN
        UPDATE public.carbon_business_events SET payload = '{"modifie": true}'::jsonb WHERE id = v_event_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B3', 'UPDATE sur carbon_business_events rejeté (append-only)', v_ok, NULL);

    -- B4. DELETE rejeté (append-only)
    v_ok := false;
    BEGIN
        DELETE FROM public.carbon_business_events WHERE id = v_event_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B4', 'DELETE sur carbon_business_events rejeté (append-only)', v_ok, NULL);

    -- B5. PORTÉE VOLONTAIREMENT LIMITÉE (renommé et reformulé, point 2 de la
    -- revue à 8 points — ce test surclamait auparavant sa propre portée).
    -- Ce test démontre UNIQUEMENT qu'une insertion dans carbon_rpc_failures
    -- survit au rollback-to-savepoint implicite d'un bloc EXCEPTION imbriqué,
    -- SI ET SEULEMENT SI la ligne d'échec est insérée DEPUIS ce bloc EXCEPTION
    -- (jamais avant). Il ne démontre PAS, et ne peut pas démontrer dans un
    -- script SQL isolé, la garantie plus large et fausse qu'on pourrait lui
    -- prêter : si la RPC appelante relance ensuite l'exception vers le client
    -- (RAISE), ou si la transaction englobante est annulée pour toute autre
    -- raison, cette même ligne serait annulée avec le reste — un savepoint
    -- PL/pgSQL protège uniquement contre le rollback du bloc imbriqué, jamais
    -- contre l'annulation de la transaction qui l'englobe. Voir
    -- Tranche0-Carbone-Architecture.md §11bis pour la garantie réelle et
    -- limitée, et sa conséquence pour l'implémentation des RPC (migrations
    -- 02-07) : carbon_rpc_failures ne doit être utilisée que pour les échecs
    -- où la RPC capture, journalise, PUIS retourne normalement un résultat
    -- structuré d'échec sans relancer l'exception.
    BEGIN
        -- Tentative de "RPC" simulée qui échoue (event_type invalide).
        INSERT INTO public.carbon_business_events (event_type, object_type, object_id)
        VALUES ('type_volontairement_invalide_2', 'aggregator', gen_random_uuid());
    EXCEPTION WHEN check_violation THEN
        -- Ce point d'exécution est APRÈS le rollback-to-savepoint implicite
        -- de la tentative ci-dessus : cette insertion n'est PAS annulée par
        -- ce même rollback, contrairement à la tentative qui a échoué. Notez
        -- l'absence de tout RAISE après cet INSERT : ce bloc EXCEPTION capture
        -- l'erreur et s'arrête là, exactement le cas où la garantie tient.
        INSERT INTO public.carbon_rpc_failures (rpc_name, failure_reason, attempted_object_type, detail)
        VALUES ('test_simulated_rpc', 'event_type invalide (test correction 3)', 'aggregator',
                jsonb_build_object('sqlstate', SQLSTATE))
        RETURNING id INTO v_failure_id;
    END;

    SELECT EXISTS (SELECT 1 FROM public.carbon_rpc_failures WHERE id = v_failure_id) INTO v_found;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B5', 'carbon_rpc_failures survit au rollback-to-savepoint d''un bloc EXCEPTION imbriqué QUI NE RELANCE PAS l''exception (portée limitée, ne couvre pas le cas d''une exception relancée ou d''une transaction englobante annulée — voir §11bis)', v_found, v_failure_id::text);

    -- B6. carbon_rpc_failures est également append-only
    v_ok := false;
    BEGIN
        DELETE FROM public.carbon_rpc_failures WHERE id = v_failure_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B6', 'DELETE sur carbon_rpc_failures rejeté (append-only)', v_ok, NULL);

    -- Nettoyage RÉSERVÉ AUX TESTS : désactivation temporaire et explicite du
    -- trigger append-only, uniquement pour retirer les lignes de test créées
    -- ci-dessus. NE JAMAIS reproduire cette technique dans du code applicatif
    -- ou une RPC — elle contourne délibérément une garantie d'intégrité,
    -- acceptable uniquement dans un script de test contrôlé et à usage unique.
    ALTER TABLE public.carbon_business_events DISABLE TRIGGER carbon_business_events_no_update_delete;
    DELETE FROM public.carbon_business_events WHERE id = v_event_id;
    ALTER TABLE public.carbon_business_events ENABLE TRIGGER carbon_business_events_no_update_delete;

    ALTER TABLE public.carbon_rpc_failures DISABLE TRIGGER carbon_rpc_failures_no_update_delete;
    DELETE FROM public.carbon_rpc_failures WHERE id = v_failure_id;
    ALTER TABLE public.carbon_rpc_failures ENABLE TRIGGER carbon_rpc_failures_no_update_delete;

    -- Note : aucun bloc EXCEPTION WHEN OTHERS n'enveloppe ce DO block dans son
    -- ensemble. Si une erreur véritablement inattendue survient n'importe où
    -- ci-dessus (bug réel, pas un des 6 cas anticipés), elle remonte telle
    -- quelle et fait échouer visiblement ce script dans l'interface Supabase
    -- — conformément à la correction 6.
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
-- PORTE DE SORTIE BRUYANTE (ajout, point 8 de la revue à 8 points) — sans ce
-- bloc, une assertion comportementale enregistrée avec passed = false était
-- simplement consignée dans le tableau ci-dessus sans jamais arrêter le
-- script ni faire échouer visiblement l'exécution dans l'interface Supabase
-- (seul RAISE EXCEPTION y est visible, pas une simple ligne « false » dans
-- les résultats). Ce bloc fait échouer le script dès qu'une seule ligne de
-- _carbon_migration_test_results a passed = false, quelle que soit la
-- section (A ou B).
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public._carbon_migration_test_results
    WHERE NOT passed
  ) THEN
    RAISE EXCEPTION 'Validation migration carbone 01 échouée';
  END IF;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- NETTOYAGE DE LA TABLE DE TEST (2e correction ciblée reçue après revue) —
-- _carbon_migration_test_results est un utilitaire de validation, pas une
-- table métier : elle ne doit pas rester exposée durablement dans public
-- (pas de RLS, pas de politique de rétention, accessible à quiconque a accès
-- au schéma). Supprimée ici, APRÈS la porte de sortie bruyante ci-dessus :
-- si une assertion a échoué, le RAISE EXCEPTION arrête le script avant
-- d'atteindre ce DROP, ce qui laisse volontairement la table en place pour
-- inspection des résultats. En cas de succès complet (aucune assertion
-- false), le script continue jusqu'ici et supprime la table — rien ne
-- subsiste au terme d'une validation réussie.
--
-- Si les résultats doivent au contraire être conservés d'une exécution à
-- l'autre (ex. historique de validations), ne pas utiliser ce DROP : activer
-- RLS sur cette table, révoquer tout accès applicatif, et définir une
-- politique de rétention explicite à la place.
-- ════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS public._carbon_migration_test_results;
