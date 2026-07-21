-- ============================================================
-- Tests — Migration 07 (credit_issuances + credit_issuance_sources)
-- ============================================================
--
-- STATUT : PROPOSITION SOUMISE POUR REVUE — NON EXÉCUTÉE.
-- Ne peut pas être exécuté avant que 04 et 05 soient rédigées et
-- appliquées (07_carbon_issuances.sql en dépend structurellement — voir
-- son bloc de prévalidation).
--
-- STRUCTURE — révisée après la quatrième revue statique (correction 4) :
-- l'intégralité du script (fixtures, tests, résumé) est encapsulée dans un
-- unique `BEGIN; ... ROLLBACK;` explicite. Le résumé (section 5) est
-- affiché AVANT le ROLLBACK — le client SQL reçoit les résultats des deux
-- `SELECT` immédiatement, indépendamment du ROLLBACK qui suit. Aucune
-- donnée, aucun transfert d'opérateur, aucun mandat, aucun événement créé
-- par ce script ne persiste après son exécution : l'état réel de
-- `platform_operators` et son historique reviennent exactement à ce qu'ils
-- étaient avant.
--
-- FIXTURES — révisées après la cinquième revue statique (correction 5) et
-- reconciliées avec le schéma réel confirmé en sixième revue (correction
-- 1/2/3) :
--   • profils : plus aucune ligne fabriquée directement dans public.profiles
--     (violerait la FK réelle vers auth.users). Le script RÉUTILISE 6
--     profils réels distincts déjà présents en base (requête + set_config,
--     section 2) ; échoue immédiatement et bruyamment si moins de 6 sont
--     disponibles — fixture MANDATORY, aucune dégradation silencieuse.
--   • organization_members : schéma réel CONFIRMÉ (org_role — ENUM
--     public.org_role à valeurs 'admin'/'membre', PAS 'member' en anglais —,
--     status, activated_at). Confirmé contre 20260710002000_ccf_002_profiles_organisations.sql.
--   • project_participants : schéma réel CONFIRMÉ — colonne `project_id`
--     (PAS `ccf_project_id`), `organization_id`, `project_role` (CHECK
--     coordonnateur/contributeur/lecteur, défaut 'contributeur'), `status`
--     (CHECK invited/active/declined/removed, défaut 'invited'). Confirmé
--     contre 20260710005000_ccf_005_ccf_projects_participants.sql.
--   • documents : schéma réel CONFIRMÉ — `owner_org_id` (uuid, NOT NULL,
--     FK organizations), `object_type` (CHECK organization/capability/
--     opportunity/project/mandate/value_report, NOT NULL), `object_id`
--     (uuid, NOT NULL), `title` (NOT NULL) — AUCUNE colonne `name` ni
--     `uploaded_by` (hypothèses précédentes, invalidées). Confirmé contre
--     20260710006000_ccf_006_documents.sql. `object_type='organization'`
--     utilisé ici comme valeur de test la plus neutre (le catalogue actuel
--     n'a pas de valeur dédiée « preuve d'émission carbone » — hors
--     périmètre de 07, qui ne fait que LIRE owner_org_id).
--   • Fixtures MANDATORY, sans EXCEPTION WHEN OTHERS -> RAISE WARNING —
--     échec immédiat et bruyant en cas de dérive de schéma.
--
-- ⚠️ POINT RESTANT À RECONFIRMER EN DIRECT AVANT EXÉCUTION RÉELLE (même
-- discipline que le reste de ce chantier, cf. INC-DATA-01) :
--   1. public.profiles contient au moins 6 lignes réelles distinctes au
--      moment de l'exécution — sinon la fixture échoue explicitement avec
--      un message clair (section 2).
--   2. Schéma de `ccf_mrv_project_links` — SEULE table encore hypothétique
--      (migration 04 non rédigée) ; `operational_units`/`projects` (MRV)
--      sont désormais confirmés (20260710999100_reapply_mrv_and_aggregators.sql)
--      et ne sont plus mentionnés dans les fixtures de ce script (aucune
--      donnée MRV n'est nécessaire pour les tests actuels, qui passent tous
--      par la branche CCF/project_participants).
--   3. `is_platform_superadmin()` est simulée via `app_metadata.role='admin'`
--      dans `request.jwt.claims` — le rôle « superadmin » de test réutilise
--      l'un des 6 profils réels réutilisés (voir section 2) : aucune
--      dépendance à un compte réellement marqué superadmin dans `profiles`,
--      is_platform_superadmin() ne dépendant que du JWT.
--   4. B18/B18bis (RLS) exécutent désormais leurs SELECT sous
--      `SET LOCAL ROLE authenticated` (correction 4, sixième revue statique)
--      — suppose que le rôle `authenticated` existe et détient les GRANT
--      SELECT posés par 07_carbon_issuances.sql section 9 ; standard sur un
--      projet Supabase, à reconfirmer si l'environnement diffère.
--
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

-- Assertion « doit lever une exception contenant p_expected_fragment » —
-- exécute p_sql dynamiquement, capture succès/échec sans jamais propager.
-- NOTE (correction 6, cinquième revue statique) : quand p_sql contient
-- plusieurs instructions (ex. un INSERT suivi d'un SET CONSTRAINTS ...
-- IMMEDIATE), l'EXECUTE ci-dessous s'exécute DANS ce même bloc
-- BEGIN/EXCEPTION — si une exception est levée, PL/pgSQL annule
-- automatiquement TOUTES les écritures faites depuis l'entrée dans ce bloc
-- (portée implicite de sous-transaction), pas seulement l'instruction qui a
-- échoué. C'est ce mécanisme qui permet aux tests B15/B19 de contourner
-- directement une RPC sans laisser de ligne résiduelle incohérente.
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

-- Simulation d'acteur — p_superadmin=true simule app_metadata.role='admin'
-- (is_platform_superadmin() ne dépend PAS de profiles.role, uniquement du JWT).
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

-- (durcissement A16, neuvième revue statique) : retire les commentaires
-- `-- ...` du texte source d'une fonction AVANT de chercher un motif
-- FOR SHARE/FOR UPDATE — sans cela, les commentaires explicatifs du corps
-- lui-même (qui mentionnent eux-mêmes littéralement « FOR SHARE » en prose,
-- par ex. « même ligne que leave_aggregator() (FOR UPDATE...) ») produiraient
-- de faux positifs et videraient le test de sa valeur.
CREATE OR REPLACE FUNCTION pg_temp.carbon_test_strip_comments(p_src TEXT) RETURNS TEXT
LANGUAGE sql AS $$
    SELECT regexp_replace(p_src, '--[^\n]*', '', 'g')
$$;

-- Vérifie qu'un motif FOR SHARE/FOR UPDATE apparaît dans la MÊME instruction
-- (bornée par ';') qu'une référence à la table donnée — plus ciblé qu'une
-- simple recherche « au moins un FOR SHARE existe quelque part » (durcissement
-- A16, neuvième revue statique : l'ancienne version ne prouvait pas QUELLE
-- autorité était verrouillée, seulement qu'au moins une l'était).
-- (correction 2, treizième revue statique) : `\b`, en expression régulière
-- PostgreSQL (ARE), N'EST PAS une frontière de mot — c'est l'échappement
-- « caractère d'entrée » pour le caractère backspace (0x08, cf. doc
-- PostgreSQL §9.7.3.4, table des « character-entry escapes »). Le motif
-- cherchait donc en pratique des caractères backspace littéraux, absents du
-- texte source de pg_get_functiondef() — la recherche échouait
-- silencieusement (aucune erreur SQL, `pglast` ne peut pas détecter une
-- regex sémantiquement fausse mais syntaxiquement valide). La véritable
-- frontière de mot PostgreSQL est `\y` (§9.7.3.5, « constraint escapes »).
CREATE OR REPLACE FUNCTION pg_temp.carbon_test_has_scoped_lock(
    p_regprocedure TEXT, p_table TEXT, p_lock_mode TEXT
) RETURNS BOOLEAN
LANGUAGE sql AS $$
    SELECT pg_temp.carbon_test_strip_comments(pg_get_functiondef(p_regprocedure::regprocedure))
           ~* ('public\.' || p_table || '\y[^;]{0,400}\y' || p_lock_mode || '\y')
$$;

-- ────────────────────────────────────────────────────────────
-- 1. PRÉVALIDATION — structure attendue de la migration 07
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert('A1', 'table credit_issuances existe',
        to_regclass('public.credit_issuances') IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('A2', 'table credit_issuance_sources existe',
        to_regclass('public.credit_issuance_sources') IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('A3', 'CHECK issuance_status inclut externally_rejected',
        EXISTS (
            SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
            WHERE t.relname = 'credit_issuances' AND c.contype = 'c'
              AND pg_get_constraintdef(c.oid) ILIKE '%externally_rejected%'
        ));
    PERFORM pg_temp.carbon_test_assert('A4', '7 RPC existent avec la signature attendue',
        to_regprocedure('public.create_credit_issuance(uuid,jsonb)') IS NOT NULL
        AND to_regprocedure('public.mark_credit_issuance_eligible(uuid)') IS NOT NULL
        AND to_regprocedure('public.submit_credit_issuance(uuid,text)') IS NOT NULL
        AND to_regprocedure('public.record_registry_issuance(uuid,text,timestamptz)') IS NOT NULL
        AND to_regprocedure('public.record_externally_rejected(uuid,date,text,uuid)') IS NOT NULL
        AND to_regprocedure('public.void_credit_issuance(uuid,text)') IS NOT NULL
        AND to_regprocedure('public.record_external_cancellation(uuid,date,text,uuid)') IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('A5', 'fonctions paramétrées is_platform_operator_actor(uuid)/is_platform_operator_admin(uuid) existent',
        to_regprocedure('public.is_platform_operator_actor(uuid)') IS NOT NULL
        AND to_regprocedure('public.is_platform_operator_admin(uuid)') IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('A6', 'privilèges : authenticated=EXECUTE, anon=aucun sur les 7 RPC',
        (SELECT bool_and(
            has_function_privilege('authenticated', p.oid, 'EXECUTE')
            AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
         )
         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN ('create_credit_issuance','mark_credit_issuance_eligible','submit_credit_issuance',
                              'record_registry_issuance','record_externally_rejected','void_credit_issuance',
                              'record_external_cancellation')));
    PERFORM pg_temp.carbon_test_assert('A7', 'helper RLS can_view_credit_issuance(uuid) existe, EXECUTE authenticated',
        to_regprocedure('public.can_view_credit_issuance(uuid)') IS NOT NULL
        AND has_function_privilege('authenticated', 'public.can_view_credit_issuance(uuid)'::regprocedure, 'EXECUTE'));
    PERFORM pg_temp.carbon_test_assert('A8', 'helpers internes SANS EXECUTE à authenticated',
        NOT has_function_privilege('authenticated', 'public.carbon_capacity_consumed_for_session(uuid)'::regprocedure, 'EXECUTE')
        AND NOT has_function_privilege('authenticated', 'public.carbon_is_source_organization_valid(uuid,uuid)'::regprocedure, 'EXECUTE'));
    PERFORM pg_temp.carbon_test_assert('A9', 'unicité (registry_name, registry_reference) présente',
        EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'credit_issuances' AND indexname = 'idx_credit_issuances_registry_ref_unique'));
    PERFORM pg_temp.carbon_test_assert('A10', 'catalogue event_type accepte credit_issuance_marked_eligible et credit_issuance_externally_rejected',
        (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
         WHERE t.relname = 'carbon_business_events' AND c.contype = 'c' AND pg_get_constraintdef(c.oid) ILIKE '%event_type%')
         ILIKE '%credit_issuance_marked_eligible%'
        AND (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
         WHERE t.relname = 'carbon_business_events' AND c.contype = 'c' AND pg_get_constraintdef(c.oid) ILIKE '%event_type%')
         ILIKE '%credit_issuance_externally_rejected%');
    -- (correction 4, cinquième revue statique) : historisation.
    PERFORM pg_temp.carbon_test_assert('A11', 'trigger BEFORE DELETE sur credit_issuances existe',
        EXISTS (
            SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
            WHERE t.relname = 'credit_issuances' AND tg.tgname = 'trg_carbon_credit_issuances_forbid_delete'
        ));
    PERFORM pg_temp.carbon_test_assert('A12', 'triggers BEFORE UPDATE/DELETE sur credit_issuance_sources existent',
        EXISTS (
            SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
            WHERE t.relname = 'credit_issuance_sources' AND tg.tgname = 'trg_carbon_credit_issuance_sources_forbid_update'
        )
        AND EXISTS (
            SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
            WHERE t.relname = 'credit_issuance_sources' AND tg.tgname = 'trg_carbon_credit_issuance_sources_forbid_delete'
        ));
    -- (corrections 5/6, sixième revue statique) : verrouillage machine à
    -- états à l'INSERT + invariant « au moins une source ».
    PERFORM pg_temp.carbon_test_assert('A13', 'trigger BEFORE INSERT sur credit_issuances (verrouillage machine à états) existe',
        EXISTS (
            SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
            WHERE t.relname = 'credit_issuances' AND tg.tgname = 'trg_carbon_credit_issuances_before_insert'
        ));
    PERFORM pg_temp.carbon_test_assert('A14', 'trigger différé « au moins une source » sur credit_issuances existe',
        EXISTS (
            SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
            WHERE t.relname = 'credit_issuances' AND tg.tgname = 'trg_carbon_validate_credit_issuance_has_sources'
        ));
    -- (correction 1, huitième revue statique) : mirroir de la prévalidation
    -- ajoutée à 07_carbon_issuances.sql section 0 — project_participants.status
    -- est désormais exploité par carbon_is_source_organization_valid()
    -- (exige 'active'), donc vérifié également côté script de tests.
    PERFORM pg_temp.carbon_test_assert('A15', 'project_participants.status (text) existe et une contrainte CHECK admet ''active''',
        EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'project_participants'
              AND column_name = 'status' AND data_type = 'text'
        )
        AND EXISTS (
            SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
            WHERE t.relname = 'project_participants' AND c.contype = 'c'
              AND pg_get_constraintdef(c.oid) ILIKE '%''active''%'
        ));
    -- (corrections 2/3, huitième revue statique) : vérification STRUCTURELLE
    -- (présence des clauses de verrouillage dans le corps compilé des
    -- fonctions, via pg_get_functiondef) que les verrous de concurrence
    -- existent. Une véritable épreuve de concurrence (deux transactions
    -- simultanées, l'une bloquant l'autre) est HORS DE PORTÉE d'un script
    -- SQL à transaction unique comme celui-ci — elle nécessiterait deux
    -- connexions distinctes (dblink/pg_background, ou un harnais de test
    -- hors SQL). Ce test structurel est un filet minimal, pas une preuve
    -- de correction comportementale sous charge concurrente réelle.
    -- (durcissement A16, neuvième revue statique) : REMPLACE la version
    -- précédente (« au moins un FOR SHARE existe quelque part dans le
    -- fichier source ») par une vérification CIBLÉE table par table, via
    -- pg_temp.carbon_test_has_scoped_lock() (commentaires exclus, motif
    -- borné à la même instruction que la référence de table). Ne prouve
    -- toujours pas la correction sous charge concurrente réelle (hors de
    -- portée d'un script à transaction unique) — reste un filet structurel.
    -- (durcissement A16, dixième revue statique) : les verrous sur
    -- project_participants/projects/operational_units ont été DÉPLACÉS hors
    -- de create_credit_issuance()/submit_credit_issuance()/
    -- carbon_validate_credit_issuance_source() vers le nouvel helper
    -- centralisé carbon_lock_and_validate_source_organization() (correction
    -- 3, dixième revue statique) — les anciens contrôles ciblant
    -- project_participants directement sur ces trois fonctions sont retirés
    -- (ils échoueraient désormais à tort) et remplacés par : (a) la preuve
    -- structurelle que l'helper lui-même verrouille les trois tables
    -- concernées, et (b) la preuve textuelle que les trois points d'appel
    -- délèguent bien à cet helper (jamais à nouveau dupliqué). Ajout
    -- également du verrou platform_operators FOR SHARE de
    -- carbon_credit_issuances_before_insert() (correction 1, dixième revue
    -- statique).
    PERFORM pg_temp.carbon_test_assert('A16', 'verrous de concurrence CIBLÉS (table par table, commentaires exclus) présents dans chaque fonction concernée',
        pg_temp.carbon_test_has_scoped_lock('public.create_credit_issuance(uuid,jsonb)', 'platform_operators', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.create_credit_issuance(uuid,jsonb)', 'aggregator_memberships', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.create_credit_issuance(uuid,jsonb)', 'carbon_commercialization_mandates', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.submit_credit_issuance(uuid,text)', 'platform_operators', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.submit_credit_issuance(uuid,text)', 'aggregator_memberships', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.submit_credit_issuance(uuid,text)', 'carbon_commercialization_mandates', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.mark_credit_issuance_eligible(uuid)', 'platform_operators', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.void_credit_issuance(uuid,text)', 'platform_operators', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.carbon_validate_credit_issuance_capacity()', 'verification_sessions', 'FOR UPDATE')
        AND pg_temp.carbon_test_has_scoped_lock('public.carbon_validate_credit_issuance_source()', 'aggregator_memberships', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.carbon_validate_credit_issuance_source()', 'carbon_commercialization_mandates', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.carbon_credit_issuances_before_insert()', 'platform_operators', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.carbon_lock_and_validate_source_organization(uuid,uuid)', 'project_participants', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.carbon_lock_and_validate_source_organization(uuid,uuid)', 'projects', 'FOR SHARE')
        AND pg_temp.carbon_test_has_scoped_lock('public.carbon_lock_and_validate_source_organization(uuid,uuid)', 'operational_units', 'FOR SHARE')
        AND pg_temp.carbon_test_strip_comments(pg_get_functiondef('public.create_credit_issuance(uuid,jsonb)'::regprocedure)) ILIKE '%carbon_lock_and_validate_source_organization(%'
        AND pg_temp.carbon_test_strip_comments(pg_get_functiondef('public.submit_credit_issuance(uuid,text)'::regprocedure)) ILIKE '%carbon_lock_and_validate_source_organization(%'
        AND pg_temp.carbon_test_strip_comments(pg_get_functiondef('public.carbon_validate_credit_issuance_source()'::regprocedure)) ILIKE '%carbon_lock_and_validate_source_organization(%');

    -- A17 (correction 3, dixième revue statique) : l'helper centralisé
    -- existe avec la signature attendue et n'est PAS exécutable directement
    -- par authenticated (usage interne uniquement, mirroir du motif A8).
    PERFORM pg_temp.carbon_test_assert('A17', 'carbon_lock_and_validate_source_organization(uuid,uuid) existe, SANS EXECUTE à authenticated',
        to_regprocedure('public.carbon_lock_and_validate_source_organization(uuid,uuid)') IS NOT NULL
        AND NOT has_function_privilege('authenticated', 'public.carbon_lock_and_validate_source_organization(uuid,uuid)'::regprocedure, 'EXECUTE'));

    -- A18 (correction 2, dixième revue statique) : le trigger structurel sur
    -- platform_operators (table de la migration 06 déjà appliquée) existe —
    -- mirroir du motif A11-A14 pour les triggers posés par 07.
    PERFORM pg_temp.carbon_test_assert('A18', 'trigger BEFORE UPDATE sur platform_operators (interdiction de transfert cul-de-sac, §15.10.d) existe',
        EXISTS (
            SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
            WHERE t.relname = 'platform_operators' AND tg.tgname = 'trg_carbon_platform_operators_before_revoke'
        ));

    -- A19 (correction 1, douzième revue statique) : helper RLS LIGNE PAR
    -- LIGNE dédié à credit_issuance_sources existe, EXECUTE authenticated —
    -- mirroir du motif A7 pour can_view_credit_issuance(). Sa présence (et
    -- non plus l'usage de can_view_credit_issuance() par
    -- credit_issuance_sources_select) est la correction structurelle de la
    -- fuite RLS multi-source.
    PERFORM pg_temp.carbon_test_assert('A19', 'helper RLS can_view_credit_issuance_source(uuid,uuid) existe, EXECUTE authenticated',
        to_regprocedure('public.can_view_credit_issuance_source(uuid,uuid)') IS NOT NULL
        AND has_function_privilege('authenticated', 'public.can_view_credit_issuance_source(uuid,uuid)'::regprocedure, 'EXECUTE'));
END $$;

-- ────────────────────────────────────────────────────────────
-- 2. FIXTURES
-- ────────────────────────────────────────────────────────────

-- Organisations de test : deux organisations sources (contributrices),
-- deux organisations « opérateur » synthétiques OP_A / OP_B pour le test
-- de transfert d'opérateur (section B13).
INSERT INTO public.organizations (id, name, status)
VALUES
    ('11111111-1111-1111-1111-111111111101', 'TEST-07 Source A', 'active'),
    ('11111111-1111-1111-1111-111111111102', 'TEST-07 Source B', 'active'),
    ('11111111-1111-1111-1111-111111111103', 'TEST-07 Operateur OP_A', 'active'),
    ('11111111-1111-1111-1111-111111111104', 'TEST-07 Operateur OP_B', 'active');

INSERT INTO public.aggregators (id, name)
VALUES ('11111111-1111-1111-1111-111111111201', 'TEST-07 Regroupement');

-- Projet CCF réel (correction 1, septième revue statique) — NÉCESSAIRE :
-- project_participants.project_id porte une vraie FK vers ccf_projects(id)
-- ON DELETE CASCADE (schéma confirmé,
-- 20260710005000_ccf_005_ccf_projects_participants.sql). L'identifiant
-- synthétique '...1701' utilisé jusqu'ici ne correspondait à AUCUNE ligne
-- réelle : l'INSERT project_participants aurait échoué avec une violation
-- de clé étrangère. ccf_projects.opportunity_id est elle-même NOT NULL (FK
-- vers opportunities(id), schéma confirmé
-- 20260710004000_ccf_004_capabilities_opportunities.sql) — une opportunité
-- de test minimale est donc également nécessaire, avant le projet.
-- RÉCONCILIATION DU CHEMIN PROJET (migrations 04/05, toujours non
-- rédigées) : verification_sessions.project_id (fixtures ci-dessous)
-- référence désormais ce MÊME id de ccf_projects réel, garantissant que
-- project_participants (branche CCF) et verification_sessions (branche
-- consommée par carbon_is_source_organization_valid()) pointent vers UNE
-- SEULE source de vérité cohérente — reste néanmoins une hypothèse tant que
-- 05 ne confirme pas explicitement le type de vs.project_id (ccf_projects
-- directement, ou via ccf_mrv_project_links comme la fonction le permet
-- déjà par ses deux branches LEFT JOIN).
INSERT INTO public.opportunities (id, title, coordinator_org_id)
VALUES ('11111111-1111-1111-1111-111111111700', 'TEST-07 Opportunité', '11111111-1111-1111-1111-111111111101');

INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id)
VALUES ('11111111-1111-1111-1111-111111111701', '11111111-1111-1111-1111-111111111700',
        'TEST-07 Projet CCF', '11111111-1111-1111-1111-111111111101');

-- Profils — RÉUTILISATION de profils réels existants (correction 5,
-- cinquième revue statique) : profiles.id référence réellement
-- auth.users(id) ; fabriquer de nouvelles lignes profiles avec des UUID
-- arbitraires violerait cette FK. 6 profils réels distincts sont donc
-- requis en base pour exécuter ce script — fixture MANDATORY, échoue
-- immédiatement si indisponible (aucune dégradation silencieuse). Le rôle
-- « superadmin » réutilise le premier profil : is_platform_superadmin()
-- dépend uniquement du JWT simulé (app_metadata.role='admin'), pas d'un
-- attribut du profil lui-même — aucun conflit à réutiliser le même id sous
-- des JWT différents selon le test.
DO $$
DECLARE
    v_profile_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_profile_ids
    FROM (SELECT id FROM public.profiles ORDER BY created_at LIMIT 6) sub;

    IF COALESCE(array_length(v_profile_ids, 1), 0) < 6 THEN
        RAISE EXCEPTION 'Fixtures impossibles : au moins 6 profils réels distincts sont requis dans public.profiles pour exécuter ce script (trouvés : %). Provisionner des comptes de test via l''API Auth de Supabase avant de relancer — aucune ligne profiles fabriquée directement ici (violerait la FK vers auth.users).', COALESCE(array_length(v_profile_ids, 1), 0);
    END IF;

    PERFORM set_config('carbon_test.profile_admin_a',    v_profile_ids[1]::text, false);
    PERFORM set_config('carbon_test.profile_admin_b',    v_profile_ids[2]::text, false);
    PERFORM set_config('carbon_test.profile_admin_opa',  v_profile_ids[3]::text, false);
    PERFORM set_config('carbon_test.profile_admin_opb',  v_profile_ids[4]::text, false);
    PERFORM set_config('carbon_test.profile_verifier',   v_profile_ids[5]::text, false);
    PERFORM set_config('carbon_test.profile_member_opa', v_profile_ids[6]::text, false);
    -- superadmin : réutilise le profil 1 (autorisation purement JWT, cf. commentaire ci-dessus).
    PERFORM set_config('carbon_test.profile_superadmin', v_profile_ids[1]::text, false);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_profile(p_key TEXT) RETURNS UUID
LANGUAGE sql AS $$ SELECT current_setting('carbon_test.profile_' || p_key)::UUID $$;

-- Adhésions organisationnelles réelles — schéma réel CONFIRMÉ
-- (20260710002000_ccf_002_profiles_organisations.sql) : org_role est un
-- ENUM public.org_role à valeurs 'admin'/'membre' — PAS 'member' en anglais
-- (bug corrigé, sixième revue statique, correction 1).
INSERT INTO public.organization_members (id, organization_id, user_id, org_role, status, activated_at)
VALUES
    ('11111111-1111-1111-1111-111111112001', '11111111-1111-1111-1111-111111111101', pg_temp.carbon_test_profile('admin_a'),    'admin',  'active', clock_timestamp() - interval '10 days'),
    ('11111111-1111-1111-1111-111111112002', '11111111-1111-1111-1111-111111111102', pg_temp.carbon_test_profile('admin_b'),    'admin',  'active', clock_timestamp() - interval '10 days'),
    ('11111111-1111-1111-1111-111111112003', '11111111-1111-1111-1111-111111111103', pg_temp.carbon_test_profile('admin_opa'),  'admin',  'active', clock_timestamp() - interval '10 days'),
    ('11111111-1111-1111-1111-111111112004', '11111111-1111-1111-1111-111111111103', pg_temp.carbon_test_profile('member_opa'), 'membre', 'active', clock_timestamp() - interval '10 days'),
    ('11111111-1111-1111-1111-111111112005', '11111111-1111-1111-1111-111111111104', pg_temp.carbon_test_profile('admin_opb'),  'admin',  'active', clock_timestamp() - interval '10 days');

-- Document de preuve — utilisé par B10/B11/B17 (rejet/annulation). Schéma
-- réel CONFIRMÉ (20260710006000_ccf_006_documents.sql, sixième revue
-- statique, correction 3) : owner_org_id (appartenance de l'organisation
-- opératrice, validée sémantiquement par record_externally_rejected()/
-- record_external_cancellation() dans 07_carbon_issuances.sql), object_type
-- (CHECK fermé, 'organization' utilisé ici comme valeur neutre — 07 ne LIT
-- que owner_org_id, ne dépend pas de object_type/object_id), object_id,
-- title — AUCUNE colonne `name` ni `uploaded_by` (hypothèses précédentes,
-- invalidées par le schéma réel). Fixture MANDATORY : pas de
-- EXCEPTION WHEN OTHERS -> RAISE WARNING, échec immédiat et bruyant sinon.
INSERT INTO public.documents (id, owner_org_id, object_type, object_id, title, status)
VALUES ('11111111-1111-1111-1111-111111112101',
        '11111111-1111-1111-1111-111111111103', 'organization',
        '11111111-1111-1111-1111-111111111103', 'TEST-07 document de preuve', 'approved');

-- Document de preuve appartenant à une AUTRE organisation qu'OP_A (...111103)
-- — utilisé par B27bis/B28bis (quatorzième revue statique) pour vérifier que
-- carbon_credit_issuances_before_update() rejette désormais, lui aussi (pas
-- seulement les RPC record_externally_rejected()/record_external_cancellation()),
-- un document de preuve dont owner_org_id ne correspond pas à l'organisation
-- opératrice figée de l'émission (défense structurelle indépendante des RPC).
INSERT INTO public.documents (id, owner_org_id, object_type, object_id, title, status)
VALUES ('11111111-1111-1111-1111-111111112102',
        '11111111-1111-1111-1111-111111111104', 'organization',
        '11111111-1111-1111-1111-111111111104', 'TEST-07 document autre organisation (OP_B)', 'approved');

-- Admin de regroupement — schéma réel CONFIRMÉ
-- (20260707110200_aggregator_admins_table.sql), utilisé pour tester la
-- branche « aggregator-admin » de can_view_credit_issuance() (B18,
-- correction 4, sixième revue statique). Réutilise le profil `verifier`
-- (autrement utilisé uniquement comme valeur de colonne verified_by,
-- jamais comme membre d'organisation ni opérateur) pour isoler proprement
-- cette branche des branches source/opérateur.
INSERT INTO public.aggregator_admins (id, aggregator_id, user_id, role)
VALUES ('11111111-1111-1111-1111-111111112201', '11111111-1111-1111-1111-111111111201',
        pg_temp.carbon_test_profile('verifier'), 'co_admin');

-- Adhésions actives au regroupement de test.
INSERT INTO public.aggregator_memberships (id, organization_id, aggregator_id, started_at)
VALUES
    ('11111111-1111-1111-1111-111111111401', '11111111-1111-1111-1111-111111111101', '11111111-1111-1111-1111-111111111201', clock_timestamp() - interval '30 days'),
    ('11111111-1111-1111-1111-111111111402', '11111111-1111-1111-1111-111111111102', '11111111-1111-1111-1111-111111111201', clock_timestamp() - interval '30 days');

-- Désignation temporaire de OP_A comme opérateur actif (superadmin requis).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.designate_platform_operator('11111111-1111-1111-1111-111111111103');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Mandats de commercialisation, scope incluant request_issuance, rattachés à OP_A.
INSERT INTO public.carbon_commercialization_mandates (
    id, aggregator_membership_id, organization_id, aggregator_id, operator_organization_id, scope, granted_by
)
VALUES
    ('11111111-1111-1111-1111-111111111501', '11111111-1111-1111-1111-111111111401',
     '11111111-1111-1111-1111-111111111101', '11111111-1111-1111-1111-111111111201',
     '11111111-1111-1111-1111-111111111103', ARRAY['request_issuance'], pg_temp.carbon_test_profile('superadmin')),
    ('11111111-1111-1111-1111-111111111502', '11111111-1111-1111-1111-111111111402',
     '11111111-1111-1111-1111-111111111102', '11111111-1111-1111-1111-111111111201',
     '11111111-1111-1111-1111-111111111103', ARRAY['request_issuance'], pg_temp.carbon_test_profile('superadmin'));

-- Session + résultat de vérification (v1), eligible_tco2e = 100, session S1.
-- ⚠️ dépend du schéma réel de verification_sessions/verification_outcomes (migration 05).
-- (correction 2, onzième revue statique) : périodes S1-S6 REDESSINÉES pour
-- être STRICTEMENT NON CHEVAUCHANTES (fenêtres successives séparées d'au
-- moins un jour), sur le même projet CCF '...1701' — anticipe la contrainte
-- `EXCLUDE USING gist` prévue par la conception de la migration 05 sur les
-- périodes des sessions 'completed'. Les dates elles-mêmes n'ont aucune
-- importance pour les tests 07 ; seule l'absence de chevauchement compte.
-- Ordre chronologique arbitraire, non significatif. À adapter au DDL exact
-- de 05 une fois rédigée (type de colonne période, bornes inclusives/exclusives).
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111601', '11111111-1111-1111-1111-111111111701', 'completed', current_date - 44, current_date - 38);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES ('11111111-1111-1111-1111-111111111801', '11111111-1111-1111-1111-111111111601', 'active', 100, 100, 100,
        pg_temp.carbon_test_profile('verifier'));

-- Session S2 indépendante, pour un contexte de capacité distinct.
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111602', '11111111-1111-1111-1111-111111111701', 'completed', current_date - 52, current_date - 46);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES ('11111111-1111-1111-1111-111111111802', '11111111-1111-1111-1111-111111111602', 'active', 50, 50, 50,
        pg_temp.carbon_test_profile('verifier'));

-- Session S3 dédiée au test direct de la contrainte différée de capacité
-- (B19, correction 6, cinquième revue statique) — plafond volontairement
-- petit et isolé des autres sessions pour un calcul sans ambiguïté.
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111603', '11111111-1111-1111-1111-111111111701', 'completed', current_date - 60, current_date - 54);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES ('11111111-1111-1111-1111-111111111803', '11111111-1111-1111-1111-111111111603', 'active', 10, 10, 10,
        pg_temp.carbon_test_profile('verifier'));

-- S4 : session/outcome dédiés aux 5 tests de complétude par état cible
-- (correction 3, septième revue statique) — capacité large (100) et
-- entièrement isolée des autres sessions pour ne jamais interférer avec
-- leur comptabilité de capacité déjà établie dans les rounds précédents.
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111604', '11111111-1111-1111-1111-111111111701', 'completed', current_date - 36, current_date - 30);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES ('11111111-1111-1111-1111-111111111804', '11111111-1111-1111-1111-111111111604', 'active', 100, 100, 100,
        pg_temp.carbon_test_profile('verifier'));

-- Participation projet minimale. Schéma réel CONFIRMÉ (sixième revue
-- statique, correction 2) : colonne `project_id`, PAS `ccf_project_id`
-- (bug corrigé) ; `status='active'` explicite (défaut réel 'invited', qui
-- ne représenterait pas une participation effective pour ces tests).
INSERT INTO public.project_participants (project_id, organization_id, status)
VALUES ('11111111-1111-1111-1111-111111111701', '11111111-1111-1111-1111-111111111101', 'active'),
       ('11111111-1111-1111-1111-111111111701', '11111111-1111-1111-1111-111111111102', 'active');

-- Source C (correction 1, huitième revue statique) : organisation dont la
-- SEULE ligne project_participants est 'invited' (jamais acceptée) — sert
-- de contre-épreuve négative pour carbon_is_source_organization_valid().
-- AUCUNE adhésion/mandat n'est créée pour cette organisation : elle ne sert
-- qu'à isoler le contrôle de participation (check 8), pas les checks 1-7.
INSERT INTO public.organizations (id, name, status)
VALUES ('11111111-1111-1111-1111-111111111105', 'TEST-07 Source C (invitée, jamais acceptée)', 'active');

INSERT INTO public.project_participants (project_id, organization_id, status)
VALUES ('11111111-1111-1111-1111-111111111701', '11111111-1111-1111-1111-111111111105', 'invited');

-- Source D (correction 1, neuvième revue statique) : organisation ACTIVE au
-- moment de la création d'une émission, mais RETIRÉE (status -> 'removed')
-- avant sa soumission — scénario T0/T1/T2 exact du point 1 de la revue.
-- Adhésion/mandat dédiés (memberships/mandates '...406'/'...506'), pour ne
-- perturber aucun autre test.
INSERT INTO public.organizations (id, name, status)
VALUES ('11111111-1111-1111-1111-111111111106', 'TEST-07 Source D (retirée avant soumission)', 'active');

INSERT INTO public.project_participants (project_id, organization_id, status)
VALUES ('11111111-1111-1111-1111-111111111701', '11111111-1111-1111-1111-111111111106', 'active');

INSERT INTO public.aggregator_memberships (id, organization_id, aggregator_id, started_at)
VALUES ('11111111-1111-1111-1111-111111111406', '11111111-1111-1111-1111-111111111106', '11111111-1111-1111-1111-111111111201', clock_timestamp() - interval '30 days');

INSERT INTO public.carbon_commercialization_mandates (
    id, aggregator_membership_id, organization_id, aggregator_id, operator_organization_id, scope, granted_by
)
VALUES ('11111111-1111-1111-1111-111111111506', '11111111-1111-1111-1111-111111111406',
        '11111111-1111-1111-1111-111111111106', '11111111-1111-1111-1111-111111111201',
        '11111111-1111-1111-1111-111111111103', ARRAY['request_issuance'], pg_temp.carbon_test_profile('superadmin'));

-- S5/O5 (correction 3a, neuvième revue statique) : session/outcome dédiés,
-- isolés, pour le test « aucun outcome actif pour la session ».
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111605', '11111111-1111-1111-1111-111111111701', 'completed', current_date - 28, current_date - 22);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES ('11111111-1111-1111-1111-111111111805', '11111111-1111-1111-1111-111111111605', 'active', 20, 20, 20,
        pg_temp.carbon_test_profile('verifier'));

-- S6/O6a(historique)+O6b(actif) (correction 3b, neuvième revue statique) :
-- une session avec DEUX outcomes — O6a marqué superseded, O6b actif — pour
-- le test « INSERT direct rattaché à un outcome non-actif de sa session,
-- alors qu'un AUTRE outcome de cette même session est bien actif ».
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111606', '11111111-1111-1111-1111-111111111701', 'completed', current_date - 20, current_date - 14);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES
    ('11111111-1111-1111-1111-111111111806', '11111111-1111-1111-1111-111111111606', 'superseded', 20, 20, 20,
     pg_temp.carbon_test_profile('verifier')),
    ('11111111-1111-1111-1111-111111111816', '11111111-1111-1111-1111-111111111606', 'active', 20, 20, 20,
     pg_temp.carbon_test_profile('verifier'));

-- Source E / branche MRV (correction 3, dixième revue statique) — schéma
-- réel CONFIRMÉ (20260710999100_reapply_mrv_and_aggregators.sql, cf.
-- prévalidation section 0) : operational_units(id, organization_id NOT NULL,
-- name NOT NULL), projects(id, operational_unit_id, name NOT NULL). Aucun
-- ccf_mrv_project_links n'est créé ici (table hypothétique, migration 04 non
-- rédigée) : verification_sessions.project_id référence donc DIRECTEMENT
-- l'id du projet MRV — le LEFT JOIN ccf_mrv_project_links de
-- carbon_is_source_organization_valid()/carbon_lock_and_validate_source_organization()
-- ne trouve alors aucune ligne, et COALESCE(link.mrv_project_id, vs.project_id)
-- retombe correctement sur vs.project_id lui-même (branche MRV directe,
-- sans lien CCF↔MRV explicite).
INSERT INTO public.organizations (id, name, status)
VALUES ('11111111-1111-1111-1111-111111111107', 'TEST-07 Source E (organisation MRV)', 'active');

INSERT INTO public.operational_units (id, organization_id, name)
VALUES ('11111111-1111-1111-1111-111111111901', '11111111-1111-1111-1111-111111111107', 'TEST-07 Unité opérationnelle MRV');

INSERT INTO public.projects (id, operational_unit_id, name)
VALUES ('11111111-1111-1111-1111-111111111902', '11111111-1111-1111-1111-111111111901', 'TEST-07 Projet MRV');

INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111607', '11111111-1111-1111-1111-111111111902', 'completed', current_date - 15, current_date);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES ('11111111-1111-1111-1111-111111111807', '11111111-1111-1111-1111-111111111607', 'active', 20, 20, 20,
        pg_temp.carbon_test_profile('verifier'));

-- S9/O9 (correction 4, douzième revue statique) : session/outcome dédiés,
-- isolés, cap large (100), pour l'émission multi-source M (B39 ci-dessous)
-- — évite toute interférence de capacité avec les fixtures S1-S6/S4 déjà
-- utilisées par d'autres tests. Période disjointe des autres sessions du
-- même projet '...701' (correction 2, onzième revue statique toujours
-- respectée).
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111608', '11111111-1111-1111-1111-111111111701', 'completed', current_date - 12, current_date - 6);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES ('11111111-1111-1111-1111-111111111808', '11111111-1111-1111-1111-111111111608', 'active', 100, 100, 100,
        pg_temp.carbon_test_profile('verifier'));

-- S10/O10 (correction 1, treizième revue statique) : session/outcome
-- dédiés, isolés, pour l'émission mono-source N (B40 ci-dessous) — M
-- (ci-dessus) consomme déjà exactement 100/100 sur O9, aucune marge pour
-- une émission supplémentaire sur cet outcome. Cap modeste (20), période
-- disjointe des autres sessions du même projet '...701'.
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end)
VALUES ('11111111-1111-1111-1111-111111111609', '11111111-1111-1111-1111-111111111701', 'completed', current_date - 4, current_date);

INSERT INTO public.verification_outcomes (
    id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e,
    eligible_tco2e, verified_by
)
VALUES ('11111111-1111-1111-1111-111111111809', '11111111-1111-1111-1111-111111111609', 'active', 20, 20, 20,
        pg_temp.carbon_test_profile('verifier'));

-- ────────────────────────────────────────────────────────────
-- 3. TESTS COMPORTEMENTAUX
-- ────────────────────────────────────────────────────────────

-- B1 : émissions partielles cumulatives réussissent.
DO $$
DECLARE
    v_id1 UUID; v_id2 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa')); -- admin OP_A, membre
    BEGIN
        v_id1 := public.create_credit_issuance('11111111-1111-1111-1111-111111111801',
            jsonb_build_array(jsonb_build_object(
                'organization_id', '11111111-1111-1111-1111-111111111101',
                'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
                'commercialization_mandate_id', '11111111-1111-1111-1111-111111111501',
                'contributed_tco2e', 40)));
        v_id2 := public.create_credit_issuance('11111111-1111-1111-1111-111111111801',
            jsonb_build_array(jsonb_build_object(
                'organization_id', '11111111-1111-1111-1111-111111111102',
                'aggregator_membership_id', '11111111-1111-1111-1111-111111111402',
                'commercialization_mandate_id', '11111111-1111-1111-1111-111111111502',
                'contributed_tco2e', 35)));
        PERFORM pg_temp.carbon_test_assert('B1', 'deux émissions partielles cumulatives (40+35=75<=100) réussissent',
            v_id1 IS NOT NULL AND v_id2 IS NOT NULL);
        PERFORM set_config('carbon_test.issuance_1', v_id1::text, false);
        PERFORM set_config('carbon_test.issuance_2', v_id2::text, false);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B1', 'deux émissions partielles cumulatives (40+35=75<=100) réussissent', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B2 : dépassement direct de capacité (40+35 déjà émis ; 30 de plus dépasse 100).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM pg_temp.carbon_test_assert_raises('B2', 'dépassement direct de capacité rejeté (75+30>100)',
        $sql$SELECT public.create_credit_issuance('11111111-1111-1111-1111-111111111801',
            jsonb_build_array(jsonb_build_object(
                'organization_id', '11111111-1111-1111-1111-111111111101',
                'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
                'commercialization_mandate_id', '11111111-1111-1111-1111-111111111501',
                'contributed_tco2e', 30)))$sql$,
        'Capacité insuffisante');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B3 : supersession v1(100)→v2(90) avec 75 déjà consommés — nouvelle émission
-- de 20 rejetée (75+20>90), de 15 réussit (75+15=90<=90).
-- NOTE : ce test vérifie le CONTRAT entre 07 (carbon_capacity_consumed_for_session())
-- et 05 (complete_verification_session()) — il suppose que 05, une fois
-- rédigée, appelle bien ce helper et verrouille verification_sessions comme
-- documenté en tête de 07_carbon_issuances.sql section 7. Un échec ici peut
-- révéler soit un bug de 07, soit un écart de 05 par rapport à cette
-- exigence documentée.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    BEGIN
        PERFORM public.complete_verification_session(
            '11111111-1111-1111-1111-111111111601', 90, 90, NULL, 'Correction de test B3 (baisse à 90, > 75 déjà consommés)');
        PERFORM pg_temp.carbon_test_assert('B3', 'supersession v1(100)->v2(90), 90>=75 déjà consommés : acceptée', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B3', 'supersession v1(100)->v2(90), 90>=75 déjà consommés : acceptée', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_active_outcome_id UUID;
BEGIN
    SELECT id INTO v_active_outcome_id FROM public.verification_outcomes
    WHERE verification_session_id = '11111111-1111-1111-1111-111111111601' AND status = 'active';
    PERFORM set_config('carbon_test.outcome_v2', v_active_outcome_id::text, false);
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM pg_temp.carbon_test_assert_raises('B4', 'dépassement à travers un outcome superseded rejeté (75+20>90 sur v2)',
        format($sql$SELECT public.create_credit_issuance(%L,
            jsonb_build_array(jsonb_build_object(
                'organization_id', '11111111-1111-1111-1111-111111111101',
                'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
                'commercialization_mandate_id', '11111111-1111-1111-1111-111111111501',
                'contributed_tco2e', 20)))$sql$, current_setting('carbon_test.outcome_v2', true)),
        'Capacité insuffisante');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_id4 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    BEGIN
        v_id4 := public.create_credit_issuance(NULLIF(current_setting('carbon_test.outcome_v2', true), '')::UUID,
            jsonb_build_array(jsonb_build_object(
                'organization_id', '11111111-1111-1111-1111-111111111101',
                'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
                'commercialization_mandate_id', '11111111-1111-1111-1111-111111111501',
                'contributed_tco2e', 15)));
        PERFORM pg_temp.carbon_test_assert('B4bis', 'émission de 15 contre v2 réussit (75+15=90<=90)', v_id4 IS NOT NULL);
        PERFORM set_config('carbon_test.issuance_4', v_id4::text, false);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B4bis', 'émission de 15 contre v2 réussit (75+15=90<=90)', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B5 : tentative de supersession vers un eligible_tco2e inférieur à la
-- capacité déjà consommée (90 consommés) rejetée. Voir note B3.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B5', 'supersession vers eligible_tco2e(50) < consommé(90) rejetée',
        $sql$SELECT public.complete_verification_session(
            '11111111-1111-1111-1111-111111111601', 50, 50, NULL, 'Test B5 : correction sous le déjà-consommé, doit échouer')$sql$,
        'Supersession refusée');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B6 : supersession vers exactement 90 (= consommé) réussit (limite). Voir note B3.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    BEGIN
        PERFORM public.complete_verification_session(
            '11111111-1111-1111-1111-111111111601', 90, 90, NULL, 'Test B6 : correction à exactement 90, limite acceptée');
        PERFORM pg_temp.carbon_test_assert('B6', 'supersession vers eligible_tco2e = consommé exactement (90) réussit', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B6', 'supersession vers eligible_tco2e = consommé exactement (90) réussit', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- (Ancien B7 : supersession inter-session — RETIRÉ. Le trigger qui l'imposait
-- (carbon_validate_outcome_supersession_same_session) n'appartient plus à
-- 07 : cette invariante devient la responsabilité de la migration 05
-- elle-même, voir 07_carbon_issuances.sql section 7. Couverture à rédiger
-- dans le futur script de tests de la migration 05, pas ici.)

-- B8 : voided libère la capacité.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa')); -- admin OP_A
    BEGIN
        PERFORM public.void_credit_issuance(NULLIF(current_setting('carbon_test.issuance_1', true), '')::UUID, 'Test B8 : libération de capacité');
        PERFORM pg_temp.carbon_test_assert('B8', 'void_credit_issuance() sur issuance_1 (internal) réussit', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B8', 'void_credit_issuance() sur issuance_1 (internal) réussit', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_consumed NUMERIC;
BEGIN
    v_consumed := public.carbon_capacity_consumed_for_session('11111111-1111-1111-1111-111111111601');
    -- 90 consommés avant void (issuance_1=40 + issuance_2=35 + issuance_4=15 = 90) ; après void de issuance_1 (40) -> 50.
    PERFORM pg_temp.carbon_test_assert('B8bis', 'capacité consommée après void = 50 (90-40)', v_consumed = 50, v_consumed::text);
END $$;

-- B9 : submitted → voided impossible (décision 1, machine à états).
DO $$
DECLARE
    v_id_sub UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id_sub := NULLIF(current_setting('carbon_test.issuance_2', true), '')::UUID;
    BEGIN
        PERFORM public.mark_credit_issuance_eligible(v_id_sub);
        PERFORM public.submit_credit_issuance(v_id_sub, 'Registre de test');
        PERFORM pg_temp.carbon_test_assert('B9-setup', 'issuance_2 amenée à submitted', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B9-setup', 'issuance_2 amenée à submitted', false, SQLERRM);
    END;
    PERFORM set_config('carbon_test.issuance_submitted', v_id_sub::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM pg_temp.carbon_test_assert_raises('B9', 'submitted -> voided impossible (void_credit_issuance rejeté)',
        format($sql$SELECT public.void_credit_issuance(%L, 'tentative interdite')$sql$,
               current_setting('carbon_test.issuance_submitted', true)),
        'Annulation interne refusée');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B10 : externally_rejected libère la capacité (preuve = document réel,
-- date + référence + document tous obligatoires — correction 3, cinquième revue statique).
DO $$
DECLARE
    v_consumed_before NUMERIC;
    v_consumed_after  NUMERIC;
BEGIN
    v_consumed_before := public.carbon_capacity_consumed_for_session('11111111-1111-1111-1111-111111111601');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    BEGIN
        PERFORM public.record_externally_rejected(
            NULLIF(current_setting('carbon_test.issuance_submitted', true), '')::UUID,
            current_date, 'REJ-TEST-001', '11111111-1111-1111-1111-111111112101');
        PERFORM pg_temp.carbon_test_assert('B10', 'record_externally_rejected() réussit avec preuve complète', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B10', 'record_externally_rejected() réussit avec preuve complète', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();

    v_consumed_after := public.carbon_capacity_consumed_for_session('11111111-1111-1111-1111-111111111601');
    PERFORM pg_temp.carbon_test_assert('B10bis', 'capacité libérée après externally_rejected (diminution de 35)',
        v_consumed_after = v_consumed_before - 35, format('avant=%s après=%s', v_consumed_before, v_consumed_after));
END $$;

-- Émission dédiée, minime, amenée à 'submitted' spécifiquement pour tester
-- la validation du document et les contrôles NOT NULL de
-- record_externally_rejected() (B10ter/quater/quinquies) — évite de
-- réutiliser '...1801', qui est un id de verification_outcome et non de
-- credit_issuance, et qui ne peut donc plus servir depuis que la validation
-- du document a été déplacée après la recherche+autorisation de l'émission
-- (correction 3, cinquième revue statique : avec l'ancien ordre, l'erreur de
-- document masquait ce problème d'id ; ce n'est plus le cas).
DO $$
DECLARE
    v_id_doctest UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id_doctest := public.create_credit_issuance('11111111-1111-1111-1111-111111111802',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', '11111111-1111-1111-1111-111111111501',
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id_doctest);
    PERFORM public.submit_credit_issuance(v_id_doctest, 'Registre de test');
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.issuance_doctest', v_id_doctest::text, false);
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);

    PERFORM pg_temp.carbon_test_assert_raises('B10ter', 'record_externally_rejected() rejette un document inexistant/non lié à l''opérateur',
        format($sql$SELECT public.record_externally_rejected(%L, current_date, 'REJ-FAKE-DOC', gen_random_uuid())$sql$,
               current_setting('carbon_test.issuance_doctest', true)),
        'Document de preuve introuvable');

    -- (correction 3, cinquième revue statique) : p_date/p_reference désormais obligatoires.
    PERFORM pg_temp.carbon_test_assert_raises('B10quater', 'record_externally_rejected() rejette p_date NULL',
        format($sql$SELECT public.record_externally_rejected(%L, NULL, 'REJ-NODATE', '11111111-1111-1111-1111-111111112101')$sql$,
               current_setting('carbon_test.issuance_doctest', true)),
        'p_date est obligatoire');
    PERFORM pg_temp.carbon_test_assert_raises('B10quinquies', 'record_externally_rejected() rejette p_reference NULL',
        format($sql$SELECT public.record_externally_rejected(%L, current_date, NULL, '11111111-1111-1111-1111-111111112101')$sql$,
               current_setting('carbon_test.issuance_doctest', true)),
        'p_reference est obligatoire');

    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B11 : externally_cancelled NE libère PAS la capacité — via issuance_4 (v2, 15 tCO2e) amenée jusqu'à issued.
DO $$
DECLARE
    v_id4 UUID;
    v_consumed_before NUMERIC;
    v_consumed_after  NUMERIC;
BEGIN
    v_id4 := NULLIF(current_setting('carbon_test.issuance_4', true), '')::UUID;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM public.mark_credit_issuance_eligible(v_id4);
    PERFORM public.submit_credit_issuance(v_id4, 'Registre de test');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.record_registry_issuance(v_id4, 'REG-TEST-004', '2026-01-15 10:00:00+00'::timestamptz);
    PERFORM pg_temp.carbon_test_clear_actor();

    v_consumed_before := public.carbon_capacity_consumed_for_session('11111111-1111-1111-1111-111111111601');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    BEGIN
        PERFORM public.record_external_cancellation(v_id4, current_date, 'CANCEL-TEST-004', '11111111-1111-1111-1111-111111112101');
        PERFORM pg_temp.carbon_test_assert('B11', 'record_external_cancellation() depuis issued réussit', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B11', 'record_external_cancellation() depuis issued réussit', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();

    v_consumed_after := public.carbon_capacity_consumed_for_session('11111111-1111-1111-1111-111111111601');
    PERFORM pg_temp.carbon_test_assert('B11bis', 'capacité inchangée après externally_cancelled (ne libère jamais)',
        v_consumed_after = v_consumed_before, format('avant=%s après=%s', v_consumed_before, v_consumed_after));
END $$;

-- B12 : révocation du mandat avant soumission bloque submit ; révocation
-- après soumission ne bloque pas issued ; unicité (registry_name, registry_reference).
DO $$
DECLARE
    v_id5 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id5 := public.create_credit_issuance('11111111-1111-1111-1111-111111111802', -- session S2, 50 de plafond, encore vierge
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', '11111111-1111-1111-1111-111111111501',
            'contributed_tco2e', 10)));
    PERFORM public.mark_credit_issuance_eligible(v_id5);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.issuance_5', v_id5::text, false);
END $$;

DO $$
BEGIN
    -- révoque le mandat de Source A AVANT la soumission de issuance_5
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.revoke_commercialization_mandate('11111111-1111-1111-1111-111111111501', 'Test B12 : révocation avant soumission');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM pg_temp.carbon_test_assert_raises('B12', 'révocation du mandat avant soumission bloque submit_credit_issuance()',
        format($sql$SELECT public.submit_credit_issuance(%L, 'Registre de test')$sql$,
               current_setting('carbon_test.issuance_5', true)),
        'Soumission refusée');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Ré-octroi d'un mandat équivalent pour poursuivre le scénario (adhésion toujours active).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.grant_commercialization_mandate(
        '11111111-1111-1111-1111-111111111401', '11111111-1111-1111-1111-111111111103',
        ARRAY['request_issuance'], NULL);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Nouvelle émission propre pour tester "révocation après soumission ne bloque pas issued".
DO $$
DECLARE
    v_id6 UUID;
    v_new_mandate_id UUID;
BEGIN
    SELECT id INTO v_new_mandate_id FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id6 := public.create_credit_issuance('11111111-1111-1111-1111-111111111802',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_new_mandate_id,
            'contributed_tco2e', 5)));
    PERFORM public.mark_credit_issuance_eligible(v_id6);
    PERFORM public.submit_credit_issuance(v_id6, 'Registre de test');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- révoque APRÈS soumission
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.revoke_commercialization_mandate(v_new_mandate_id, 'Test B12bis : révocation après soumission');

    BEGIN
        PERFORM public.record_registry_issuance(v_id6, 'REG-TEST-006', '2026-01-16 09:00:00+00'::timestamptz);
        PERFORM pg_temp.carbon_test_assert('B12bis', 'révocation après soumission ne bloque pas record_registry_issuance()', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B12bis', 'révocation après soumission ne bloque pas record_registry_issuance()', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.issuance_6', v_id6::text, false);
END $$;

-- Remise en état de fixture (quatorzième revue statique) : B12bis révoque le seul mandat actif
-- restant pour l'adhésion ...1401 (Source A) sans qu'aucun nouveau mandat ne soit octroyé ensuite.
-- Tous les scénarios suivants qui dépendent de create_credit_issuance() avec cette adhésion
-- (via SELECT id ... WHERE aggregator_membership_id = '...1401' AND revoked_at IS NULL) échoueraient
-- sinon avant même d'atteindre les invariants qu'ils visent réellement à tester. Ce bloc ne
-- constitue pas une assertion — remise en état de fixture uniquement, N inchangé.
DO $$
DECLARE
    v_active_mandate_401 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.grant_commercialization_mandate(
        '11111111-1111-1111-1111-111111111401', '11111111-1111-1111-1111-111111111103',
        ARRAY['request_issuance'], NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT id INTO v_active_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM set_config('carbon_test.active_mandate_401', v_active_mandate_401::text, false);
END $$;

-- B12ter : unicité (registry_name, registry_reference).
DO $$
DECLARE
    v_id6b UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id6b := public.create_credit_issuance('11111111-1111-1111-1111-111111111802',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111102',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111402',
            'commercialization_mandate_id', '11111111-1111-1111-1111-111111111502',
            'contributed_tco2e', 2)));
    PERFORM public.mark_credit_issuance_eligible(v_id6b);
    PERFORM public.submit_credit_issuance(v_id6b, 'Registre de test');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    -- REG-TEST-006 a déjà été enregistrée sous 'Registre de test' pour issuance_6 (B12bis) : réutiliser
    -- exactement la même paire (registry_name, registry_reference) doit être rejeté.
    PERFORM pg_temp.carbon_test_assert_raises('B12ter', 'unicité (registry_name, registry_reference) : doublon rejeté',
        format($sql$SELECT public.record_registry_issuance(%L, 'REG-TEST-006', '2026-01-16 09:00:00+00'::timestamptz)$sql$, v_id6b::text),
        'déjà été enregistrée');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B12terbis (durcissement, seizième revue statique) : la même paire, mais
-- variée par la CASSE de registry_name (' Registre de test' vs 'REGISTRE DE
-- TEST') et par des ESPACES superflus sur registry_reference (' REG-TEST-006 '
-- vs 'REG-TEST-006'), doit être détectée comme le même doublon par l'index
-- normalisé (lower(btrim(registry_name)), btrim(registry_reference)) —
-- avant ce durcissement, ces deux paires étaient distinctes pour
-- PostgreSQL et pouvaient donc coexister, contournant l'unicité recherchée.
-- registry_reference garde sa casse propre (seul btrim s'applique) : la
-- valeur testée ici a volontairement la MÊME casse que l'originale
-- ('REG-TEST-006'), seuls les espaces varient.
DO $$
DECLARE
    v_id6c UUID;
    v_mandate_401 UUID;
BEGIN
    v_mandate_401 := NULLIF(current_setting('carbon_test.active_mandate_401', true), '')::UUID;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id6c := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id6c);
    PERFORM public.submit_credit_issuance(v_id6c, 'REGISTRE DE TEST');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B12terbis', 'unicité (registry_name, registry_reference) normalisée : doublon par variation casse/espaces rejeté',
        format($sql$SELECT public.record_registry_issuance(%L, ' REG-TEST-006 ', '2026-01-16 09:05:00+00'::timestamptz)$sql$, v_id6c::text),
        'déjà été enregistrée');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B12quater (correction 2, septième revue statique) : p_registry_issued_at
-- est désormais un paramètre obligatoire — NULL doit être rejeté AVANT
-- toute recherche de l'émission (aucune fuite d'existence, cf. B17).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM pg_temp.carbon_test_assert_raises('B12quater', 'record_registry_issuance() : p_registry_issued_at NULL est rejeté',
        format($sql$SELECT public.record_registry_issuance(%L, 'REG-TEST-NULLTS', NULL)$sql$, gen_random_uuid()::text),
        'p_registry_issued_at est requis');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B25-B29 (correction 3, septième revue statique) : invariants de
-- COMPLÉTUDE par état cible ajoutés à carbon_credit_issuances_before_update().
-- Chaque test amène une émission DÉDIÉE (session/outcome S4, isolée, cap 100)
-- à l'état OLD légitime via les RPC réels, puis tente un CONTOURNEMENT
-- DIRECT hors RPC — un UPDATE brut sur credit_issuances — vers l'état cible
-- SANS le(s) champ(s) requis. Placés AVANT le transfert d'opérateur OP_A ->
-- OP_B (B13 ci-dessous) pour réutiliser le mandat actif d'OP_A sans
-- complication. Le rôle exécutant ce script contourne RLS (pas de
-- SET LOCAL ROLE authenticated ici) : ces UPDATE atteignent bien le trigger,
-- ce qui est précisément ce qui doit être testé — le trigger est la DERNIÈRE
-- ligne de défense, indépendante de la couche RPC.

-- B25 : eligible -> submitted SANS registry_name.
DO $$
DECLARE
    v_id25 UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id25 := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id25);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B25', 'trigger refuse eligible -> submitted sans registry_name (contournement direct hors RPC)',
        format($sql$UPDATE public.credit_issuances SET issuance_status = 'submitted' WHERE id = %L$sql$, v_id25::text),
        'registry_name doit être renseigné');

    -- Résorption locale (correction 1, onzième revue statique) : la tentative
    -- de contournement ci-dessus a échoué (rollback implicite de ce seul
    -- UPDATE), v_id25 reste donc 'eligible' — sans ce nettoyage, cette
    -- émission bloquerait le transfert d'opérateur OP_A -> OP_B testé plus
    -- bas (B13, trigger carbon_platform_operators_before_revoke()). Chaque
    -- fixture de ce type doit désormais laisser un état métier neutre
    -- (aucune émission internal/eligible résiduelle) pour les tests suivants.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM public.void_credit_issuance(v_id25, 'Résorption B25 : nettoyage post-test (onzième revue statique)');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B26 : submitted -> issued SANS registry_reference/registry_issued_at.
DO $$
DECLARE
    v_id26 UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id26 := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id26);
    PERFORM public.submit_credit_issuance(v_id26, 'Registre de test B26');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B26', 'trigger refuse submitted -> issued sans registry_reference/registry_issued_at (contournement direct hors RPC)',
        format($sql$UPDATE public.credit_issuances SET issuance_status = 'issued' WHERE id = %L$sql$, v_id26::text),
        'registry_reference et registry_issued_at');
END $$;

-- B27 : submitted -> externally_rejected SANS date/référence/document.
DO $$
DECLARE
    v_id27 UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id27 := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id27);
    PERFORM public.submit_credit_issuance(v_id27, 'Registre de test B27');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B27', 'trigger refuse submitted -> externally_rejected sans preuve complète (contournement direct hors RPC)',
        format($sql$UPDATE public.credit_issuances SET issuance_status = 'externally_rejected' WHERE id = %L$sql$, v_id27::text),
        'external_rejection_date/reference/document_id');
END $$;

-- B27bis (durcissement, quatorzième revue statique) : submitted -> externally_rejected
-- avec preuve COMPLÈTE (date/référence/document_id tous renseignés) mais dont le
-- document appartient à une AUTRE organisation qu'OP_A — contournement direct hors
-- RPC, doit être rejeté par carbon_credit_issuances_before_update() lui-même,
-- symétriquement à la validation déjà faite par record_externally_rejected().
DO $$
DECLARE
    v_id27bis UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id27bis := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id27bis);
    PERFORM public.submit_credit_issuance(v_id27bis, 'Registre de test B27bis');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B27bis', 'trigger refuse submitted -> externally_rejected avec document d''une autre organisation, preuve par ailleurs complète (contournement direct hors RPC, quatorzième revue statique)',
        format($sql$UPDATE public.credit_issuances SET issuance_status = 'externally_rejected', external_rejection_date = current_date, external_rejection_reference = 'REJ-FOREIGN-DOC', external_rejection_document_id = '11111111-1111-1111-1111-111111112102' WHERE id = %L$sql$, v_id27bis::text),
        'organisation opératrice figée');
END $$;

-- B28 : issued -> externally_cancelled SANS date/référence/document.
DO $$
DECLARE
    v_id28 UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id28 := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id28);
    PERFORM public.submit_credit_issuance(v_id28, 'Registre de test B28');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.record_registry_issuance(v_id28, 'REG-TEST-B28', '2026-01-19 08:00:00+00'::timestamptz);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B28', 'trigger refuse issued -> externally_cancelled sans preuve complète (contournement direct hors RPC)',
        format($sql$UPDATE public.credit_issuances SET issuance_status = 'externally_cancelled' WHERE id = %L$sql$, v_id28::text),
        'external_cancellation_date/reference/document_id');
END $$;

-- B28bis (durcissement, quatorzième revue statique) : issued -> externally_cancelled
-- avec preuve COMPLÈTE mais document appartenant à une AUTRE organisation qu'OP_A —
-- contournement direct hors RPC, doit être rejeté par
-- carbon_credit_issuances_before_update() lui-même, symétriquement à B27bis.
DO $$
DECLARE
    v_id28bis UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id28bis := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id28bis);
    PERFORM public.submit_credit_issuance(v_id28bis, 'Registre de test B28bis');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.record_registry_issuance(v_id28bis, 'REG-TEST-B28bis', '2026-01-19 08:05:00+00'::timestamptz);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B28bis', 'trigger refuse issued -> externally_cancelled avec document d''une autre organisation, preuve par ailleurs complète (contournement direct hors RPC, quatorzième revue statique)',
        format($sql$UPDATE public.credit_issuances SET issuance_status = 'externally_cancelled', external_cancellation_date = current_date, external_cancellation_reference = 'CANCEL-FOREIGN-DOC', external_cancellation_document_id = '11111111-1111-1111-1111-111111112102' WHERE id = %L$sql$, v_id28bis::text),
        'organisation opératrice figée');
END $$;

-- B29 : internal -> voided SANS void_reason.
DO $$
DECLARE
    v_id29 UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id29 := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B29', 'trigger refuse internal -> voided sans void_reason (contournement direct hors RPC)',
        format($sql$UPDATE public.credit_issuances SET issuance_status = 'voided' WHERE id = %L$sql$, v_id29::text),
        'void_reason doit être renseigné');

    -- Résorption locale (correction 1, onzième revue statique) : v_id29 reste
    -- 'internal' après l'échec du contournement ci-dessus — même motif que
    -- B25 ci-dessus.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM public.void_credit_issuance(v_id29, 'Résorption B29 : nettoyage post-test (onzième revue statique)');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B30/B31 (correction 1, huitième revue statique) : carbon_is_source_organization_valid()
-- exige désormais project_participants.status='active'. B30 est la
-- contre-épreuve positive (participation active, déjà implicitement
-- exercée par B1 et consorts, mais rendue explicite ici) ; B31 est le test
-- NÉGATIF explicitement demandé — Source C (fixture ci-dessus), dont
-- l'unique ligne project_participants est 'invited', ne doit PLUS être
-- acceptée comme organisation source valide.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert('B30', 'carbon_is_source_organization_valid() accepte une participation active',
        COALESCE(public.carbon_is_source_organization_valid(
            '11111111-1111-1111-1111-111111111102', '11111111-1111-1111-1111-111111111801'), false));

    PERFORM pg_temp.carbon_test_assert('B31', 'carbon_is_source_organization_valid() REJETTE une participation ''invited'' (jamais acceptée)',
        NOT COALESCE(public.carbon_is_source_organization_valid(
            '11111111-1111-1111-1111-111111111105', '11111111-1111-1111-1111-111111111801'), true));

    -- B36/B37 (correction 3, dixième revue statique) : branche MRV, via
    -- l'helper centralisé carbon_lock_and_validate_source_organization()
    -- (verrouille projects/operational_units PUIS délègue à
    -- carbon_is_source_organization_valid(), seule source de vérité —
    -- confirme au passage que le verrouillage n'altère jamais la décision).
    -- O7 (session S7/outcome '...807') référence directement le projet MRV
    -- '...902' (operational_unit_id -> '...901' -> organization_id Source E).
    PERFORM pg_temp.carbon_test_assert('B36', 'carbon_lock_and_validate_source_organization() accepte Source E via la branche MRV (projects -> operational_units)',
        COALESCE(public.carbon_lock_and_validate_source_organization(
            '11111111-1111-1111-1111-111111111107', '11111111-1111-1111-1111-111111111807'), false));

    PERFORM pg_temp.carbon_test_assert('B37', 'carbon_lock_and_validate_source_organization() REJETTE une organisation sans lien MRV ni CCF pour cet outcome',
        NOT COALESCE(public.carbon_lock_and_validate_source_organization(
            '11111111-1111-1111-1111-111111111101', '11111111-1111-1111-1111-111111111807'), true));
END $$;

-- Note : une contre-épreuve par le chemin RPC complet (create_credit_issuance()
-- avec Source C comme unique source) exercerait check 1 (adhésion, absente
-- pour Source C) avant d'atteindre check 8 (participation) — elle ne
-- testerait donc PAS spécifiquement l'invariant de la correction 1, et
-- nécessiterait une adhésion/mandat dédiés rien que pour l'isoler. B31
-- ci-dessus, test direct du helper, couvre déjà exactement l'invariant
-- demandé sans cette complexité de fixture supplémentaire.

-- B32 (correction 1, neuvième revue statique) : contre-épreuve PAR LE CHEMIN
-- RPC COMPLET, cette fois — scénario T0/T1/T2 exact du point 1 de la revue.
-- Source D est ACTIVE au moment de create_credit_issuance() (check 8 passe),
-- puis retirée (status -> 'removed', contournement direct : aucune fonction
-- de retrait n'existe encore dans le dépôt réel, confirmé par recherche)
-- AVANT submit_credit_issuance(). Avant cette correction, submit_credit_issuance()
-- ne rejouait jamais check 8 et acceptait cette soumission à tort.
DO $$
DECLARE
    v_id32 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id32 := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111106',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111406',
            'commercialization_mandate_id', '11111111-1111-1111-1111-111111111506',
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_id32);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- T1 : Source D retirée du projet.
    UPDATE public.project_participants SET status = 'removed'
    WHERE project_id = '11111111-1111-1111-1111-111111111701'
      AND organization_id = '11111111-1111-1111-1111-111111111106';

    -- T2 : la soumission doit désormais être refusée.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM pg_temp.carbon_test_assert_raises('B32', 'submit_credit_issuance() revalide check 8 : rejette une source retirée du projet entre la création et la soumission',
        format($sql$SELECT public.submit_credit_issuance(%L, 'Registre de test B32')$sql$, v_id32::text),
        'n''est plus un participant effectif');

    -- Résorption locale (correction 1, onzième revue statique) : la
    -- soumission a échoué, v_id32 reste 'eligible' — void_credit_issuance()
    -- ne dépend pas de la participation projet (Source D retirée à T1
    -- n'empêche pas cette résorption), seulement de l'autorité opérateur
    -- actif, encore valide ici (toujours avant le transfert OP_A -> OP_B).
    PERFORM public.void_credit_issuance(v_id32, 'Résorption B32 : nettoyage post-test (onzième revue statique)');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B33 (correction 3a, neuvième revue statique) : contournement direct de
-- trg_carbon_validate_issuance_capacity — INSERT rattaché à O5 (actif au
-- moment de l'INSERT), puis O5 lui-même basculé en superseded (AUCUN
-- outcome actif ne reste pour S5) AVANT le déclenchement forcé du contrôle
-- différé. Même construction que B15/B19/B20 : INSERT + UPDATE + SET
-- CONSTRAINTS IMMEDIATE dans le MÊME bloc d'exception (via
-- carbon_test_assert_raises) — annulation automatique et complète.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B33', 'trg_carbon_validate_issuance_capacity rejette une session SANS AUCUN outcome actif (SET CONSTRAINTS IMMEDIATE)',
        format($sql$
            INSERT INTO public.credit_issuances (id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by)
            VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111805', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111103', 5, 'internal', %L);
            UPDATE public.verification_outcomes SET status = 'superseded' WHERE id = '11111111-1111-1111-1111-111111111805';
            SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
        $sql$, pg_temp.carbon_test_profile('admin_opa')),
        'Aucun outcome actif');

    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
END $$;

-- B34 (correction 3b, neuvième revue statique) : contournement direct —
-- INSERT rattaché à O6a (superseded) alors que O6b, un AUTRE outcome de la
-- MÊME session S6, est bien actif — doit être rejeté précisément parce que
-- NEW.verification_outcome_id n'est pas l'outcome actif de sa session,
-- distinct du cas B33 (aucun outcome actif du tout).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B34', 'trg_carbon_validate_issuance_capacity rejette un INSERT rattaché à un outcome non-actif alors qu''un AUTRE outcome de la même session est actif (SET CONSTRAINTS IMMEDIATE)',
        format($sql$
            INSERT INTO public.credit_issuances (id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by)
            VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111806', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111103', 5, 'internal', %L);
            SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
        $sql$, pg_temp.carbon_test_profile('admin_opa')),
        'n''est pas l''outcome actif');

    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
END $$;

-- B35 (durcissement, neuvième revue statique) : UPDATE direct de
-- credit_issuances.id (colonne désormais immuable) rejeté.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B35', 'UPDATE direct de credit_issuances.id (colonne désormais immuable) rejeté',
        format($sql$UPDATE public.credit_issuances SET id = gen_random_uuid() WHERE id = %L$sql$,
               current_setting('carbon_test.issuance_1', true)),
        'Colonne immuable');
END $$;

-- B13 : transfert d'opérateur après soumission — l'opérateur actuel (OP_B)
-- n'acquiert pas automatiquement les droits sur l'émission historique
-- (rattachée à OP_A), mais l'admin d'OP_A garde ses droits.
DO $$
DECLARE
    v_id7 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa')); -- admin OP_A
    v_id7 := public.create_credit_issuance('11111111-1111-1111-1111-111111111802',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111102',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111402',
            'commercialization_mandate_id', '11111111-1111-1111-1111-111111111502',
            'contributed_tco2e', 5)));
    PERFORM public.mark_credit_issuance_eligible(v_id7);
    PERFORM public.submit_credit_issuance(v_id7, 'Registre de test');
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.issuance_7', v_id7::text, false);
END $$;

-- B13ter (RÉÉCRIT, décision §15.10.d, dixième revue statique) : la
-- transition revoked_at NULL -> NOT NULL de platform_operators (portée par
-- designate_platform_operator()) est désormais REFUSÉE tant qu'il existe au
-- moins une credit_issuances 'internal'/'eligible' rattachée à l'opérateur
-- révoqué. issuance_5 (créée en B12, toujours 'eligible' à ce point du
-- script, jamais transitionnée depuis) bloque donc le transfert OP_A -> OP_B
-- tant qu'elle n'a pas été amenée à submitted ou voided. Remplace l'ancien
-- B13ter (qui testait un mark_credit_issuance_eligible() en échec APRÈS un
-- transfert désormais structurellement impossible dans cet état).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B13ter', 'transfert d''opérateur REFUSÉ tant qu''une émission ''eligible'' (issuance_5) reste rattachée à l''opérateur actif (cul-de-sac §15.10.d)',
        $sql$SELECT public.designate_platform_operator('11111111-1111-1111-1111-111111111104')$sql$,
        'internal/eligible');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B13quater (RÉÉCRIT) : même invariant, pour le statut 'internal' cette
-- fois (distinct d'''eligible'', testé ci-dessus) — émission dédiée, minime,
-- délibérément laissée 'internal' (jamais mark_credit_issuance_eligible()).
DO $$
DECLARE
    v_id_block_internal UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id_block_internal := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.issuance_block_internal', v_id_block_internal::text, false);

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B13quater', 'transfert d''opérateur REFUSÉ tant qu''une émission ''internal'' reste rattachée à l''opérateur actif (cul-de-sac §15.10.d)',
        $sql$SELECT public.designate_platform_operator('11111111-1111-1111-1111-111111111104')$sql$,
        'internal/eligible');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Résorption des deux blocages (superadmin, OP_A toujours actif) : ramène
-- l'état à zéro émission internal/eligible sous OP_A, condition nécessaire
-- au transfert testé positivement par B13quinquies ci-dessous.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.void_credit_issuance(NULLIF(current_setting('carbon_test.issuance_5', true), '')::UUID, 'Résorption B13quinquies : lever le blocage de transfert (eligible)');
    PERFORM public.void_credit_issuance(NULLIF(current_setting('carbon_test.issuance_block_internal', true), '')::UUID, 'Résorption B13quinquies : lever le blocage de transfert (internal)');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B13quinquies (RÉÉCRIT, contre-épreuve positive) : une fois OP_A ramené à
-- zéro émission internal/eligible, le transfert OP_A -> OP_B RÉUSSIT — c'est
-- désormais le transfert réel dont dépendent B13/B13bis/B13sexies/B13septies
-- ci-dessous (opérateur figé vs nouvel opérateur actif sur issuance_7,
-- déjà 'submitted', donc jamais concernée par ce nouveau blocage).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    BEGIN
        PERFORM public.designate_platform_operator('11111111-1111-1111-1111-111111111104'); -- OP_B devient actif
        PERFORM pg_temp.carbon_test_assert('B13quinquies', 'transfert d''opérateur RÉUSSIT une fois toutes les émissions internal/eligible résorbées (submitted/voided)', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B13quinquies', 'transfert d''opérateur RÉUSSIT une fois toutes les émissions internal/eligible résorbées (submitted/voided)', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- L'admin d'OP_B (nouvel opérateur actif) ne peut PAS agir sur issuance_7 (opérateur figé = OP_A).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opb')); -- admin OP_B
    PERFORM pg_temp.carbon_test_assert_raises('B13', 'admin du nouvel opérateur actif (OP_B) n''acquiert PAS les droits sur l''émission historique (OP_A)',
        format($sql$SELECT public.record_registry_issuance(%L, 'REG-TEST-007-refuse', '2026-01-17 08:00:00+00'::timestamptz)$sql$,
               current_setting('carbon_test.issuance_7', true)),
        'Émission introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- L'admin de l'opérateur figé d'origine (OP_A) garde ses droits malgré le transfert.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa')); -- admin OP_A (plus l'opérateur actif)
    BEGIN
        PERFORM public.record_registry_issuance(NULLIF(current_setting('carbon_test.issuance_7', true), '')::UUID, 'REG-TEST-007-ok', '2026-01-17 08:00:00+00'::timestamptz);
        PERFORM pg_temp.carbon_test_assert('B13bis', 'admin de l''opérateur figé (OP_A) conserve ses droits post-transfert', true);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B13bis', 'admin de l''opérateur figé (OP_A) conserve ses droits post-transfert', false, SQLERRM);
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B13sexies/septies (correction 4, septième revue statique) : RLS SELECT
-- RÉELLE (SET LOCAL ROLE authenticated) sur l'émission historique issuance_7
-- pendant la fenêtre où OP_A est figé et OP_B est l'opérateur actif.
-- can_view_credit_issuance() branche opérateur utilise désormais
-- is_organization_member() (adhésion, sans exigence d'activité) plutôt que
-- is_platform_operator_actor() (exige l'opérateur actif) — un membre simple
-- (pas même admin) de l'opérateur figé d'origine doit conserver la
-- visibilité de son émission historique, cohérence avec les droits RPC déjà
-- vérifiés en B13bis (admin d'OP_A). Le nouvel opérateur actif (OP_B) ne
-- doit PAS hériter automatiquement de cette visibilité : seule son
-- appartenance à OP_B, sans lien avec l'émission rattachée à OP_A, est en
-- jeu, donc aucune visibilité attendue.
DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('member_opa')); -- membre simple (PAS admin) d'OP_A, opérateur figé/historique
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_issuances
    WHERE id = NULLIF(current_setting('carbon_test.issuance_7', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B13sexies', 'membre simple (non-admin) de l''opérateur figé (OP_A) garde la visibilité RLS de son émission historique post-transfert',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opb')); -- admin du nouvel opérateur actif OP_B, sans lien avec OP_A/issuance_7
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_issuances
    WHERE id = NULLIF(current_setting('carbon_test.issuance_7', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B13septies', 'admin du nouvel opérateur actif (OP_B) n''hérite PAS automatiquement de la visibilité de l''émission historique d''OP_A',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Variante inverse (décision 3, §15) — OBSOLÈTE, RETIRÉE (décision §15.10.d,
-- dixième revue statique) : cette variante testait qu'une émission
-- 'internal'/'eligible' pouvait rester rattachée à un opérateur devenu
-- non-actif après transfert (« opérateur figé »), et vérifiait l'accès de
-- l'admin d'OP_A puis du super-admin sur cet état (anciens B13ter/B13quater).
-- Ce scénario est désormais STRUCTURELLEMENT INATTEIGNABLE : le nouveau
-- trigger carbon_platform_operators_before_revoke() interdit tout transfert
-- tant qu'une telle émission existe sous l'opérateur en cours de révocation
-- (voir B13ter/B13quater RÉÉCRITS ci-dessus, qui testent désormais
-- précisément ce refus). Par construction, aucune ligne credit_issuances ne
-- peut donc jamais se trouver à 'internal'/'eligible' avec un
-- operator_organization_id qui n'est plus l'opérateur actif — tester
-- l'autorisation sur un tel état serait un test vide (état inatteignable),
-- retiré plutôt que conservé sous une forme artificielle.
--
-- Restaure OP_A comme actif pour le reste des tests (RLS, B16/B17) qui en
-- dépendent — reste entièrement DANS la transaction globale du script,
-- annulé par le ROLLBACK final. Ce transfert retour (OP_B -> OP_A) n'est lui
-- non plus jamais bloqué : OP_B n'a créé aucune émission internal/eligible
-- depuis qu'il est devenu actif (aucun call site entre les deux transferts
-- n'en crée sous OP_B).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.designate_platform_operator('11111111-1111-1111-1111-111111111103');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B14 : somme exacte des sources et provenance historique figée.
DO $$
DECLARE
    v_qty NUMERIC;
    v_sum NUMERIC;
BEGIN
    SELECT quantity_tco2e INTO v_qty FROM public.credit_issuances
    WHERE id = NULLIF(current_setting('carbon_test.issuance_7', true), '')::UUID;
    SELECT SUM(contributed_tco2e) INTO v_sum FROM public.credit_issuance_sources
    WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_7', true), '')::UUID;
    PERFORM pg_temp.carbon_test_assert('B14', 'SUM(contributed_tco2e) = quantity_tco2e pour issuance_7', v_qty = v_sum, format('qty=%s sum=%s', v_qty, v_sum));
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B14bis', 'UPDATE direct de quantity_tco2e (colonne figée) rejeté',
        format($sql$UPDATE public.credit_issuances SET quantity_tco2e = 999 WHERE id = %L$sql$,
               current_setting('carbon_test.issuance_7', true)),
        'immuable');

    PERFORM pg_temp.carbon_test_assert_raises('B14ter', 'UPDATE direct d''operator_organization_id (provenance figée) rejeté',
        format($sql$UPDATE public.credit_issuances SET operator_organization_id = '11111111-1111-1111-1111-111111111104' WHERE id = %L$sql$,
               current_setting('carbon_test.issuance_7', true)),
        'immuable');
END $$;

-- B15 : somme incorrecte des sources rejetée par la contrainte différée
-- (contournement direct hypothétique de credit_issuance_sources).
DO $$
DECLARE
    v_id9 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id9 := public.create_credit_issuance('11111111-1111-1111-1111-111111111802',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id',
            (SELECT id FROM public.carbon_commercialization_mandates WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL),
            'contributed_tco2e', 3)));
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.issuance_9', v_id9::text, false);
END $$;

DO $$
BEGIN
    -- contournement direct : insère une source additionnelle sans repasser par la RPC
    -- (somme casserait 3 -> 3+2=5 != quantity_tco2e=3). SET CONSTRAINTS ... IMMEDIATE
    -- force le déclenchement du CONSTRAINT TRIGGER différé sans COMMIT (transaction
    -- control interdit dans un EXECUTE plpgsql) — même transaction, même effet observable.
    -- L'INSERT et le SET CONSTRAINTS sont dans le MÊME bloc d'exception (via
    -- carbon_test_assert_raises) : leur annulation est donc automatique et
    -- complète dès que l'exception est interceptée, aucune ligne résiduelle
    -- ne subsiste (voir commentaire sur carbon_test_assert_raises, section 0).
    PERFORM pg_temp.carbon_test_assert_raises('B15', 'contrainte différée (sources) rejette une somme incohérente (SET CONSTRAINTS IMMEDIATE)',
        format($sql$
            INSERT INTO public.credit_issuance_sources (credit_issuance_id, organization_id, aggregator_membership_id, commercialization_mandate_id, contributed_tco2e)
            VALUES (%L, '11111111-1111-1111-1111-111111111102', '11111111-1111-1111-1111-111111111402', '11111111-1111-1111-1111-111111111502', 2);
            SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE;
        $sql$, current_setting('carbon_test.issuance_9', true)),
        NULL);

    -- remet les contraintes différées à leur mode par défaut pour le reste du script.
    SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
END $$;

-- B15bis-B15sexies (correction 4, cinquième revue statique) : historisation
-- stricte — DELETE interdit sur credit_issuances, UPDATE/DELETE interdits
-- sur credit_issuance_sources, champs réglementaires figés après transition.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B15bis', 'DELETE direct sur credit_issuances rejeté (historisation)',
        format($sql$DELETE FROM public.credit_issuances WHERE id = %L$sql$,
               current_setting('carbon_test.issuance_1', true)),
        'historisée');
END $$;

DO $$
DECLARE
    v_source_id UUID;
BEGIN
    SELECT id INTO v_source_id FROM public.credit_issuance_sources
    WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_1', true), '')::UUID
    LIMIT 1;

    PERFORM pg_temp.carbon_test_assert_raises('B15ter', 'UPDATE direct sur credit_issuance_sources rejeté (append-only)',
        format($sql$UPDATE public.credit_issuance_sources SET contributed_tco2e = 999 WHERE id = %L$sql$, v_source_id),
        'append-only');

    PERFORM pg_temp.carbon_test_assert_raises('B15quater', 'DELETE direct sur credit_issuance_sources rejeté (append-only)',
        format($sql$DELETE FROM public.credit_issuance_sources WHERE id = %L$sql$, v_source_id),
        'append-only');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B15quinquies', 'UPDATE direct de registry_reference (déjà renseigné) rejeté (champ réglementaire figé)',
        format($sql$UPDATE public.credit_issuances SET registry_reference = 'REG-TEST-004-ALTERED' WHERE id = %L$sql$,
               current_setting('carbon_test.issuance_4', true)),
        'figé');

    PERFORM pg_temp.carbon_test_assert_raises('B15sexies', 'UPDATE direct de void_reason (déjà renseigné) rejeté (champ réglementaire figé)',
        format($sql$UPDATE public.credit_issuances SET void_reason = 'raison modifiée après coup' WHERE id = %L$sql$,
               current_setting('carbon_test.issuance_1', true)),
        'figé');
END $$;

-- B19 : test direct de trg_carbon_validate_issuance_capacity (contrainte
-- différée sur credit_issuances, correction 6, cinquième revue statique) —
-- contournement direct de create_credit_issuance() par un INSERT brut
-- dépassant le plafond de la session S3 (10 tCO2e), forcé en immédiat.
-- L'INSERT et le SET CONSTRAINTS IMMEDIATE sont exécutés dans le MÊME bloc
-- d'exception (via carbon_test_assert_raises) — même raisonnement que B15 :
-- l'annulation est automatique et complète, aucune ligne résiduelle ne
-- subsiste pour le SET CONSTRAINTS ALL IMMEDIATE final ci-dessous.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B19', 'trg_carbon_validate_issuance_capacity rejette un INSERT direct dépassant le plafond de S3 (SET CONSTRAINTS IMMEDIATE)',
        format($sql$
            INSERT INTO public.credit_issuances (id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by)
            VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111803', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111103', 15, 'internal', %L);
            SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
        $sql$, pg_temp.carbon_test_profile('admin_opa')),
        'Capacité');

    -- remet la contrainte différée à son mode par défaut (défensif : le
    -- rollback implicite de l'exception ci-dessus le fait déjà).
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
END $$;

-- B20 : test direct de trg_carbon_validate_credit_issuance_has_sources
-- (invariant « au moins une source », correction 5, sixième revue statique)
-- — contournement direct de create_credit_issuance() par un INSERT brut
-- SANS aucune ligne credit_issuance_sources correspondante. Quantité (5)
-- volontairement sous le plafond de S3 (10) pour isoler ce test de
-- trg_carbon_validate_issuance_capacity (B19 ci-dessus) — seul l'invariant
-- « au moins une source » doit se déclencher ici. Même construction que
-- B15/B19 : INSERT + SET CONSTRAINTS IMMEDIATE dans le même bloc
-- d'exception, annulation automatique et complète.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B20', 'trg_carbon_validate_credit_issuance_has_sources rejette une émission créée sans aucune source (SET CONSTRAINTS IMMEDIATE)',
        format($sql$
            INSERT INTO public.credit_issuances (id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by)
            VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111803', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111103', 5, 'internal', %L);
            SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE;
        $sql$, pg_temp.carbon_test_profile('admin_opa')),
        'sans aucune source');

    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
END $$;

-- B21/B22 (correction 6, sixième revue statique) : la machine à états est
-- désormais verrouillée dès l'INSERT — un INSERT brut ne peut plus fixer un
-- statut initial autre que 'internal', ni pré-renseigner un champ
-- réglementaire (registry_*/external_rejection_*/external_cancellation_*/
-- void_reason).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B21', 'INSERT direct avec issuance_status != internal rejeté (verrouillage machine à états à l''INSERT)',
        format($sql$INSERT INTO public.credit_issuances (id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by)
            VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111803', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111103', 1, 'issued', %L)$sql$,
               pg_temp.carbon_test_profile('admin_opa')),
        'doit être créée au statut internal');

    PERFORM pg_temp.carbon_test_assert_raises('B22', 'INSERT direct avec un champ réglementaire pré-renseigné rejeté (verrouillage machine à états à l''INSERT)',
        format($sql$INSERT INTO public.credit_issuances (id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by, void_reason)
            VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111803', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111103', 1, 'internal', %L, 'tentative de contournement')$sql$,
               pg_temp.carbon_test_profile('admin_opa')),
        'sans aucun champ réglementaire');

    -- B22bis (correction 1, dixième revue statique) : INSERT direct avec
    -- operator_organization_id = OP_B — OP_A est l'opérateur actif à ce
    -- stade du script (restauré juste avant, section B13) et OP_B n'a
    -- jamais été désigné actif entre-temps sans être aussitôt retransféré ;
    -- aucune ligne platform_operators avec organization_id=OP_B et
    -- revoked_at IS NULL n'existe donc. Preuve comportementale (et non plus
    -- seulement structurelle, cf. A16) que carbon_credit_issuances_before_insert()
    -- verrouille platform_operators FOR SHARE et rejette toute création
    -- rattachée à un opérateur non-actif — y compris un contournement direct
    -- hors RPC (create_credit_issuance() ne l'aurait de toute façon jamais
    -- laissé passer, faisant de ce test un filet indépendant du chemin RPC).
    PERFORM pg_temp.carbon_test_assert_raises('B22bis', 'INSERT direct avec operator_organization_id = opérateur NON-actif (OP_B) rejeté (invariant structurel opérateur actif, §15.10)',
        format($sql$INSERT INTO public.credit_issuances (id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by)
            VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111803', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111104', 1, 'internal', %L)$sql$,
               pg_temp.carbon_test_profile('admin_opa')),
        'opérateur METALTRACE actif');
END $$;

-- B22ter/B22quater (durcissement, quinzième revue statique) : NUMERIC accepte
-- la valeur spéciale NaN indépendamment de la précision/échelle déclarée, et
-- PostgreSQL la traite comme supérieure à toute valeur numérique ordinaire
-- pour les opérateurs de comparaison — un CHECK `> 0` seul ne l'exclut donc
-- PAS (`'NaN'::numeric > 0` est TRUE). Les CHECK de table ont été durcis ce
-- tour pour exclure NaN explicitement ; ces deux tests le vérifient par
-- contournement direct hors RPC, même patron que B21/B22/B22bis (CHECK non
-- différé : l'INSERT échoue immédiatement, pas besoin de SET CONSTRAINTS).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B22ter', 'INSERT direct avec quantity_tco2e = NaN rejeté (CHECK de table durci)',
        format($sql$INSERT INTO public.credit_issuances (id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by)
            VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111803', '11111111-1111-1111-1111-111111111201', '11111111-1111-1111-1111-111111111103', 'NaN'::numeric, 'internal', %L)$sql$,
               pg_temp.carbon_test_profile('admin_opa')),
        'violates check constraint');
END $$;

-- B22quater : émission de base valide (Source A, 1 tCO2e) créée via
-- create_credit_issuance(), puis contournement direct hors RPC — INSERT
-- supplémentaire d'une deuxième ligne source (Source B, autre organisation,
-- évite l'UNIQUE (credit_issuance_id, organization_id)) avec
-- contributed_tco2e = NaN. La ligne source additionnelle est par ailleurs
-- entièrement valide (adhésion/mandat/aggregator/opérateur cohérents,
-- identiques au patron déjà exercé par B12ter) : seul le CHECK durci sur
-- contributed_tco2e doit intercepter le NaN, pas le trigger BEFORE INSERT de
-- cohérence source (qui ne connaît pas cet invariant).
DO $$
DECLARE
    v_id_nanbase   UUID;
    v_mandate_401  UUID;
BEGIN
    v_mandate_401 := NULLIF(current_setting('carbon_test.active_mandate_401', true), '')::UUID;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_id_nanbase := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B22quater', 'INSERT direct d''une ligne credit_issuance_sources avec contributed_tco2e = NaN rejeté (CHECK de table durci)',
        format($sql$INSERT INTO public.credit_issuance_sources (id, credit_issuance_id, organization_id, aggregator_membership_id, commercialization_mandate_id, contributed_tco2e)
            VALUES (gen_random_uuid(), %L, '11111111-1111-1111-1111-111111111102', '11111111-1111-1111-1111-111111111402', '11111111-1111-1111-1111-111111111502', 'NaN'::numeric)$sql$,
               v_id_nanbase::text),
        'violates check constraint');
END $$;

-- B38 (correction 3, onzième revue statique) : les 7 RPC d'émission
-- renseignent désormais organization_id (= operator_organization_id figé,
-- décision retenue), aggregator_id et verification_session_id sur leur
-- INSERT carbon_business_events — dimensions d'autorisation exploitées par
-- can_view_carbon_event() (§10bis, migration 01/05). Test COMPOSITE (accord
-- explicite de la revue : pas d'assertion indépendante par RPC) couvrant les
-- 7 transitions via trois émissions dédiées, plus une contre-épreuve
-- négative (RPC rejetée ne produit aucun événement de succès).
DO $$
DECLARE
    v_idA    UUID;   -- internal -> eligible -> submitted -> issued -> externally_cancelled
    v_idB    UUID;   -- internal -> voided
    v_idC    UUID;   -- internal -> eligible -> submitted -> externally_rejected
    v_mandate_401 UUID;
    v_org    UUID;
    v_agg    UUID;
    v_vs     UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));

    v_idA := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));

    SELECT organization_id, aggregator_id, verification_session_id
    INTO v_org, v_agg, v_vs
    FROM public.carbon_business_events
    WHERE object_type = 'credit_issuance' AND object_id = v_idA AND event_type = 'credit_issuance_created';

    PERFORM pg_temp.carbon_test_assert('B38-1', 'credit_issuance_created : exactement 1 événement, contexte complet (organization_id=opérateur figé, aggregator_id, verification_session_id)',
        v_org = '11111111-1111-1111-1111-111111111103'
        AND v_agg = '11111111-1111-1111-1111-111111111201'
        AND v_vs = '11111111-1111-1111-1111-111111111604'
        AND (SELECT count(*) FROM public.carbon_business_events
             WHERE object_type = 'credit_issuance' AND object_id = v_idA AND event_type = 'credit_issuance_created') = 1);

    -- (durcissement, douzième revue statique) : B38-2/3/4/5/7/8 comptaient
    -- via EXISTS(...), qui reste VRAI même si un doublon d'événement était
    -- silencieusement inséré (deux lignes identiques passeraient encore le
    -- test). Remplacé par count(*) = 1, cohérent avec B38-1/B38-6 qui
    -- imposaient déjà cette règle — « une transition réussie produit
    -- EXACTEMENT un événement », pas seulement « au moins un ».
    PERFORM public.mark_credit_issuance_eligible(v_idA);
    PERFORM pg_temp.carbon_test_assert('B38-2', 'credit_issuance_marked_eligible : exactement 1 événement, contexte complet',
        (SELECT count(*) FROM public.carbon_business_events
         WHERE object_type = 'credit_issuance' AND object_id = v_idA AND event_type = 'credit_issuance_marked_eligible'
           AND organization_id = '11111111-1111-1111-1111-111111111103'
           AND aggregator_id = '11111111-1111-1111-1111-111111111201'
           AND verification_session_id = '11111111-1111-1111-1111-111111111604') = 1);

    PERFORM public.submit_credit_issuance(v_idA, 'Registre B38');
    PERFORM pg_temp.carbon_test_assert('B38-3', 'credit_issuance_submitted : exactement 1 événement, contexte complet',
        (SELECT count(*) FROM public.carbon_business_events
         WHERE object_type = 'credit_issuance' AND object_id = v_idA AND event_type = 'credit_issuance_submitted'
           AND organization_id = '11111111-1111-1111-1111-111111111103'
           AND aggregator_id = '11111111-1111-1111-1111-111111111201'
           AND verification_session_id = '11111111-1111-1111-1111-111111111604') = 1);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);

    PERFORM public.record_registry_issuance(v_idA, 'REG-B38', clock_timestamp());
    PERFORM pg_temp.carbon_test_assert('B38-4', 'credit_issuance_issued : exactement 1 événement, contexte complet',
        (SELECT count(*) FROM public.carbon_business_events
         WHERE object_type = 'credit_issuance' AND object_id = v_idA AND event_type = 'credit_issuance_issued'
           AND organization_id = '11111111-1111-1111-1111-111111111103'
           AND aggregator_id = '11111111-1111-1111-1111-111111111201'
           AND verification_session_id = '11111111-1111-1111-1111-111111111604') = 1);

    PERFORM public.record_external_cancellation(v_idA, current_date, 'CANCEL-B38', '11111111-1111-1111-1111-111111112101');
    PERFORM pg_temp.carbon_test_assert('B38-5', 'credit_issuance_externally_cancelled : exactement 1 événement, contexte complet',
        (SELECT count(*) FROM public.carbon_business_events
         WHERE object_type = 'credit_issuance' AND object_id = v_idA AND event_type = 'credit_issuance_externally_cancelled'
           AND organization_id = '11111111-1111-1111-1111-111111111103'
           AND aggregator_id = '11111111-1111-1111-1111-111111111201'
           AND verification_session_id = '11111111-1111-1111-1111-111111111604') = 1);

    -- Négatif : record_registry_issuance() rejeté (v_idA déjà externally_cancelled,
    -- transition refusée) ne doit produire AUCUN événement 'credit_issuance_issued'
    -- supplémentaire au-delà de celui déjà vérifié en B38-4.
    BEGIN
        PERFORM public.record_registry_issuance(v_idA, 'REG-B38-BIS', clock_timestamp());
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM pg_temp.carbon_test_assert('B38-6', 'RPC rejetée (record_registry_issuance() sur émission déjà externally_cancelled) ne produit aucun événement de succès supplémentaire',
        (SELECT count(*) FROM public.carbon_business_events
         WHERE object_type = 'credit_issuance' AND object_id = v_idA AND event_type = 'credit_issuance_issued') = 1);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Issuance B : internal -> voided (6e RPC).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_idB := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.void_credit_issuance(v_idB, 'Test B38 : contexte événement voided');
    PERFORM pg_temp.carbon_test_assert('B38-7', 'credit_issuance_voided : exactement 1 événement, contexte complet',
        (SELECT count(*) FROM public.carbon_business_events
         WHERE object_type = 'credit_issuance' AND object_id = v_idB AND event_type = 'credit_issuance_voided'
           AND organization_id = '11111111-1111-1111-1111-111111111103'
           AND aggregator_id = '11111111-1111-1111-1111-111111111201'
           AND verification_session_id = '11111111-1111-1111-1111-111111111604') = 1);

    -- Issuance C : internal -> eligible -> submitted -> externally_rejected (7e RPC).
    v_idC := public.create_credit_issuance('11111111-1111-1111-1111-111111111804',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111101',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
            'commercialization_mandate_id', v_mandate_401,
            'contributed_tco2e', 1)));
    PERFORM public.mark_credit_issuance_eligible(v_idC);
    PERFORM public.submit_credit_issuance(v_idC, 'Registre B38-C');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM public.record_externally_rejected(v_idC, current_date, 'REJ-B38', '11111111-1111-1111-1111-111111112101');
    PERFORM pg_temp.carbon_test_assert('B38-8', 'credit_issuance_externally_rejected : exactement 1 événement, contexte complet',
        (SELECT count(*) FROM public.carbon_business_events
         WHERE object_type = 'credit_issuance' AND object_id = v_idC AND event_type = 'credit_issuance_externally_rejected'
           AND organization_id = '11111111-1111-1111-1111-111111111103'
           AND aggregator_id = '11111111-1111-1111-1111-111111111201'
           AND verification_session_id = '11111111-1111-1111-1111-111111111604') = 1);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B23/B24 (correction 6, sixième revue statique) : un UPDATE à statut
-- INCHANGÉ ne peut jamais initialiser un champ réglementaire — seule la
-- transition légitime associée à ce champ le peut. Cible issuance_9
-- (statut 'internal', créée en B15, jamais transitionnée depuis).
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B23', 'UPDATE à statut inchangé ne peut pas initialiser registry_reference (contournement machine à états fermé)',
        format($sql$UPDATE public.credit_issuances SET registry_reference = 'FAKE-BYPASS' WHERE id = %L$sql$,
               current_setting('carbon_test.issuance_9', true)),
        'ne peut être renseigné que lors de la transition');

    PERFORM pg_temp.carbon_test_assert_raises('B24', 'UPDATE à statut inchangé ne peut pas initialiser void_reason (contournement machine à états fermé)',
        format($sql$UPDATE public.credit_issuances SET void_reason = 'FAKE-BYPASS' WHERE id = %L$sql$,
               current_setting('carbon_test.issuance_9', true)),
        'ne peut être renseigné que lors d''une transition vers voided');
END $$;

-- ────────────────────────────────────────────────────────────
-- 4. AUTORISATION, RLS ET ABSENCE DE FUITE D'EXISTENCE
-- ────────────────────────────────────────────────────────────

-- B16 : membre SIMPLE (non admin) de OP_A réussit create_credit_issuance()
-- mais échoue sur les transitions réservées à l'admin — test réel.
DO $$
DECLARE
    v_id10 UUID;
    v_active_mandate UUID;
BEGIN
    SELECT id INTO v_active_mandate FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('member_opa')); -- membre simple OP_A
    BEGIN
        v_id10 := public.create_credit_issuance('11111111-1111-1111-1111-111111111802',
            jsonb_build_array(jsonb_build_object(
                'organization_id', '11111111-1111-1111-1111-111111111101',
                'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
                'commercialization_mandate_id', v_active_mandate,
                'contributed_tco2e', 1)));
        PERFORM pg_temp.carbon_test_assert('B16', 'membre simple OP_A réussit create_credit_issuance()', v_id10 IS NOT NULL);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.carbon_test_assert('B16', 'membre simple OP_A réussit create_credit_issuance()', false, SQLERRM);
    END;
    PERFORM set_config('carbon_test.issuance_10', v_id10::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('member_opa')); -- toujours membre simple, pas admin
    PERFORM pg_temp.carbon_test_assert_raises('B16bis', 'membre simple OP_A échoue sur mark_credit_issuance_eligible() (admin requis)',
        format($sql$SELECT public.mark_credit_issuance_eligible(%L)$sql$, current_setting('carbon_test.issuance_10', true)),
        'Émission introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_assert_raises('B16ter', 'membre simple OP_A échoue sur void_credit_issuance() (admin requis)',
        format($sql$SELECT public.void_credit_issuance(%L, 'tentative membre simple')$sql$, current_setting('carbon_test.issuance_10', true)),
        'Émission introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B17 : absence de fuite d'existence sur les SIX RPC de transition — message
-- identique pour UUID inexistant vs émission existante mais inaccessible.
DO $$
DECLARE
    v_fake_id UUID := gen_random_uuid();
    v_real_id UUID := NULLIF(current_setting('carbon_test.issuance_9', true), '')::UUID; -- appartient à OP_A, statut 'internal'
    v_doc_id  UUID := '11111111-1111-1111-1111-111111112101';
    v_msg_a   TEXT;
    v_msg_b   TEXT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opb')); -- admin OP_B, sans lien avec OP_A

    v_msg_a := NULL; v_msg_b := NULL;
    BEGIN PERFORM public.mark_credit_issuance_eligible(v_fake_id); EXCEPTION WHEN OTHERS THEN v_msg_a := SQLERRM; END;
    BEGIN PERFORM public.mark_credit_issuance_eligible(v_real_id); EXCEPTION WHEN OTHERS THEN v_msg_b := SQLERRM; END;
    PERFORM pg_temp.carbon_test_assert('B17-1', 'mark_credit_issuance_eligible() : message identique inexistant/inaccessible',
        v_msg_a = v_msg_b, format('[%s] vs [%s]', v_msg_a, v_msg_b));

    v_msg_a := NULL; v_msg_b := NULL;
    BEGIN PERFORM public.submit_credit_issuance(v_fake_id, 'Registre'); EXCEPTION WHEN OTHERS THEN v_msg_a := SQLERRM; END;
    BEGIN PERFORM public.submit_credit_issuance(v_real_id, 'Registre'); EXCEPTION WHEN OTHERS THEN v_msg_b := SQLERRM; END;
    PERFORM pg_temp.carbon_test_assert('B17-2', 'submit_credit_issuance() : message identique inexistant/inaccessible',
        v_msg_a = v_msg_b, format('[%s] vs [%s]', v_msg_a, v_msg_b));

    v_msg_a := NULL; v_msg_b := NULL;
    BEGIN PERFORM public.record_registry_issuance(v_fake_id, 'REG-LEAK', '2026-01-18 08:00:00+00'::timestamptz); EXCEPTION WHEN OTHERS THEN v_msg_a := SQLERRM; END;
    BEGIN PERFORM public.record_registry_issuance(v_real_id, 'REG-LEAK', '2026-01-18 08:00:00+00'::timestamptz); EXCEPTION WHEN OTHERS THEN v_msg_b := SQLERRM; END;
    PERFORM pg_temp.carbon_test_assert('B17-3', 'record_registry_issuance() : message identique inexistant/inaccessible',
        v_msg_a = v_msg_b, format('[%s] vs [%s]', v_msg_a, v_msg_b));

    v_msg_a := NULL; v_msg_b := NULL;
    BEGIN PERFORM public.record_externally_rejected(v_fake_id, current_date, 'REJ-LEAK', v_doc_id); EXCEPTION WHEN OTHERS THEN v_msg_a := SQLERRM; END;
    BEGIN PERFORM public.record_externally_rejected(v_real_id, current_date, 'REJ-LEAK', v_doc_id); EXCEPTION WHEN OTHERS THEN v_msg_b := SQLERRM; END;
    PERFORM pg_temp.carbon_test_assert('B17-4', 'record_externally_rejected() : message identique inexistant/inaccessible',
        v_msg_a = v_msg_b, format('[%s] vs [%s]', v_msg_a, v_msg_b));

    v_msg_a := NULL; v_msg_b := NULL;
    BEGIN PERFORM public.void_credit_issuance(v_fake_id, 'leak test'); EXCEPTION WHEN OTHERS THEN v_msg_a := SQLERRM; END;
    BEGIN PERFORM public.void_credit_issuance(v_real_id, 'leak test'); EXCEPTION WHEN OTHERS THEN v_msg_b := SQLERRM; END;
    PERFORM pg_temp.carbon_test_assert('B17-5', 'void_credit_issuance() : message identique inexistant/inaccessible',
        v_msg_a = v_msg_b, format('[%s] vs [%s]', v_msg_a, v_msg_b));

    v_msg_a := NULL; v_msg_b := NULL;
    BEGIN PERFORM public.record_external_cancellation(v_fake_id, current_date, 'CANCEL-LEAK', v_doc_id); EXCEPTION WHEN OTHERS THEN v_msg_a := SQLERRM; END;
    BEGIN PERFORM public.record_external_cancellation(v_real_id, current_date, 'CANCEL-LEAK', v_doc_id); EXCEPTION WHEN OTHERS THEN v_msg_b := SQLERRM; END;
    PERFORM pg_temp.carbon_test_assert('B17-6', 'record_external_cancellation() : message identique inexistant/inaccessible',
        v_msg_a = v_msg_b, format('[%s] vs [%s]', v_msg_a, v_msg_b));

    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B18 : RLS SELECT RÉELLE — exécutée sous SET LOCAL ROLE authenticated
-- (correction 4, sixième revue statique). Auparavant ces SELECT
-- s'exécutaient sous le rôle propriétaire des tables (celui qui applique la
-- migration), qui contourne RLS entièrement — le test ne vérifiait donc
-- RIEN de la RLS réelle, malgré son nom. SET LOCAL est borné à la
-- transaction (annulé de toute façon par le ROLLBACK final) mais RESET ROLE
-- est appelé explicitement après chaque bloc, par prudence, pour ne pas
-- laisser d'opérations ultérieures du script s'exécuter sous authenticated
-- par erreur — en particulier les futurs appels à
-- pg_temp.carbon_test_assert(), qui écrit dans une table appartenant au
-- rôle propriétaire.
--
-- Couverture étendue à quatre branches de can_view_credit_issuance() (§15
-- point 6, section 8 de 07_carbon_issuances.sql) : source, membre de
-- l'opérateur (is_organization_member(), SANS exigence d'activité depuis la
-- correction 4 de la septième revue statique — voir aussi B13sexies/septies
-- ci-dessus pour le cas spécifiquement historique/figé), aggregator-admin,
-- tiers (outsider).
--
-- La cinquième branche « vérificateur assigné » (is_assigned_verifier())
-- n'est PAS couverte ici. CONFIRMÉ PAR RECHERCHE (septième revue statique,
-- point 6) : ni `is_assigned_verifier()`, ni aucune table/fonction de la
-- migration 05 (verification_outcomes côté vérificateur assigné,
-- assignment, etc.) n'existent dans `supabase/migrations/` — recherche
-- exhaustive du dépôt réel, aucune trace, même partielle. Il ne s'agit donc
-- pas d'une simple omission de fixture mais de l'absence totale du
-- mécanisme sous-jacent : fabriquer une fixture sur une hypothèse non
-- vérifiée serait contraire à la discipline « schéma réel d'abord » de ce
-- chantier (cf. INC-DATA-01). Reste bloqué/différé jusqu'à la rédaction
-- réelle de la migration 05 ; à couvrir dans son propre script de tests,
-- avec sa contre-épreuve non assignée, à ce moment-là.
DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_a')); -- admin de Source A, organization_members réel
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_issuance_sources WHERE organization_id = '11111111-1111-1111-1111-111111111101';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B18-source', 'organisation source voit ses propres lignes (RLS réelle, rôle authenticated)', v_count > 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa')); -- admin de OP_A, opérateur actif à ce stade du script
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_issuances WHERE operator_organization_id = '11111111-1111-1111-1111-111111111103';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B18-operateur', 'admin de l''opérateur actif voit les émissions de son opérateur (RLS réelle, branche is_organization_member depuis correction 4/7e revue)', v_count > 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier')); -- admin du regroupement de test (aggregator_admins), sans lien source/opérateur
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_issuances WHERE aggregator_id = '11111111-1111-1111-1111-111111111201';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B18-aggregateur', 'admin du regroupement voit les émissions de son regroupement (RLS réelle, branche is_aggregator_admin)', v_count > 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count_stranger INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(gen_random_uuid()); -- tiers totalement étranger, sans aucune ligne organization_members/aggregator_admins/platform_operators
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count_stranger FROM public.credit_issuances;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B18-outsider', 'tiers sans relation ne voit aucune émission (RLS réelle, rôle authenticated)', v_count_stranger = 0, v_count_stranger::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B39 (correction 1/4, douzième revue statique) : émission RÉELLEMENT
-- multi-source (Source A 40 tCO2e + Source B 60 tCO2e, session/outcome S9
-- dédiés), scénario qu'aucun test existant n'exerçait — B1 crée deux
-- émissions à une seule source chacune, jamais une émission unique à
-- plusieurs sources. C'est précisément le scénario qui révélait la fuite
-- RLS corrigée au point 1 : avant le correctif, credit_issuance_sources_select
-- réutilisait can_view_credit_issuance(id), qui rend TRUE dès qu'un
-- utilisateur est membre de N'IMPORTE QUELLE organisation source de
-- l'émission — Source A aurait alors vu la ligne de Source B (organization_id,
-- contributed_tco2e, aggregator_membership_id, commercialization_mandate_id)
-- en plus de la sienne.
DO $$
DECLARE
    v_idM         UUID;
    v_mandate_401 UUID;
BEGIN
    SELECT id INTO v_mandate_401 FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id = '11111111-1111-1111-1111-111111111401' AND revoked_at IS NULL;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_idM := public.create_credit_issuance('11111111-1111-1111-1111-111111111808',
        jsonb_build_array(
            jsonb_build_object(
                'organization_id', '11111111-1111-1111-1111-111111111101',
                'aggregator_membership_id', '11111111-1111-1111-1111-111111111401',
                'commercialization_mandate_id', v_mandate_401,
                'contributed_tco2e', 40),
            jsonb_build_object(
                'organization_id', '11111111-1111-1111-1111-111111111102',
                'aggregator_membership_id', '11111111-1111-1111-1111-111111111402',
                'commercialization_mandate_id', '11111111-1111-1111-1111-111111111502',
                'contributed_tco2e', 60)));
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.issuance_M', v_idM::text, false);
END $$;

-- B41 (durcissement, dix-septième revue statique) : le parent et TOUTES ses
-- sources doivent partager exactement le même created_at — invariant
-- introduit par le redesign de la capture de l'instant de constitution
-- (carbon_credit_issuances_before_insert() fixe NEW.created_at, propagé via
-- RETURNING et forcé identiquement sur chaque source par
-- carbon_validate_credit_issuance_source()). Émission M (créée juste
-- au-dessus, deux sources) est un cas réel déjà multi-source, pas une
-- fixture ad hoc.
DO $$
DECLARE
    v_parent_created_at  TIMESTAMPTZ;
    v_matching_sources   INT;
    v_total_sources      INT;
BEGIN
    SELECT created_at INTO v_parent_created_at FROM public.credit_issuances
    WHERE id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID;

    SELECT count(*), count(*) FILTER (WHERE created_at = v_parent_created_at)
    INTO v_total_sources, v_matching_sources
    FROM public.credit_issuance_sources
    WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID;

    PERFORM pg_temp.carbon_test_assert('B41', 'toutes les sources de l''émission M partagent exactement le created_at du parent',
        v_total_sources = 2 AND v_matching_sources = v_total_sources,
        format('total=%s correspondantes=%s parent=%s', v_total_sources, v_matching_sources, v_parent_created_at));
END $$;

-- B41bis : contre-épreuve — contournement direct hors RPC, sur une émission
-- DÉDIÉE créée elle-même par INSERT direct (pas via create_credit_issuance()),
-- avec Source A ET Source B insérées directement. quantity_tco2e=2 est fixé
-- cohérent avec la somme des deux sources (1+1=2) dès la construction —
-- correction dix-huitième revue statique : la version précédente créait le
-- parent via la RPC avec la seule Source A (quantity_tco2e=1 déduit de
-- cette unique source), puis ajoutait directement une Source B non comptée
-- dans ce total, laissant SUM(sources)=2 pour quantity_tco2e=1 — écart que
-- trg_carbon_validate_sources_sum (contrainte différée) aurait détecté au
-- SET CONSTRAINTS ALL IMMEDIATE final, interrompant tout le script avant le
-- gate 110/110. La Source B porte un created_at explicitement antidaté de
-- 10 jours ; carbon_validate_credit_issuance_source() doit FORCER (pas
-- seulement valider/rejeter) NEW.created_at à la valeur réelle du parent —
-- la ligne insérée doit porter le created_at du parent, jamais la valeur
-- antidatée fournie, preuve que le contournement est structurellement
-- impossible, pas seulement détecté après coup. L'émission est voidée en
-- fin de bloc pour neutraliser son impact sur la capacité de la session
-- liée à l'outcome 1804 (plafond 100), consommée par de nombreux autres
-- tests de ce fichier.
DO $$
DECLARE
    v_id41bis           UUID := gen_random_uuid();
    v_parent_created_at TIMESTAMPTZ;
    v_stored_created_at TIMESTAMPTZ;
    v_mandate_401       UUID;
BEGIN
    v_mandate_401 := NULLIF(current_setting('carbon_test.active_mandate_401', true), '')::UUID;

    -- Émission dédiée, directe (hors RPC) : quantity_tco2e=2 fixé d'emblée,
    -- cohérent avec la somme des deux sources insérées ci-dessous.
    INSERT INTO public.credit_issuances (
        id, verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by
    ) VALUES (
        v_id41bis, '11111111-1111-1111-1111-111111111804', '11111111-1111-1111-1111-111111111201',
        '11111111-1111-1111-1111-111111111103', 2, 'internal', pg_temp.carbon_test_profile('admin_opa')
    );

    SELECT created_at INTO v_parent_created_at FROM public.credit_issuances WHERE id = v_id41bis;

    -- Source A, directe, valide par ailleurs (adhésion/mandat réels) —
    -- created_at non fourni (DEFAULT clock_timestamp() de toute façon
    -- écrasé par le trigger, comme pour toute source).
    INSERT INTO public.credit_issuance_sources (
        credit_issuance_id, organization_id, aggregator_membership_id, commercialization_mandate_id, contributed_tco2e
    ) VALUES (
        v_id41bis, '11111111-1111-1111-1111-111111111101',
        '11111111-1111-1111-1111-111111111401', v_mandate_401, 1
    );

    -- Source B, directe, valide par ailleurs (adhésion/mandat réels) — seul
    -- created_at diverge délibérément : antidaté de 10 jours.
    INSERT INTO public.credit_issuance_sources (
        id, credit_issuance_id, organization_id, aggregator_membership_id, commercialization_mandate_id, contributed_tco2e, created_at
    ) VALUES (
        gen_random_uuid(), v_id41bis, '11111111-1111-1111-1111-111111111102',
        '11111111-1111-1111-1111-111111111402', '11111111-1111-1111-1111-111111111502', 1,
        clock_timestamp() - interval '10 days'
    );

    SELECT created_at INTO v_stored_created_at FROM public.credit_issuance_sources
    WHERE credit_issuance_id = v_id41bis AND organization_id = '11111111-1111-1111-1111-111111111102';

    PERFORM pg_temp.carbon_test_assert('B41bis', 'contournement direct avec created_at de source antidaté : trigger force la valeur réelle du parent, la valeur antidatée fournie est ignorée',
        v_stored_created_at = v_parent_created_at AND v_stored_created_at <> clock_timestamp() - interval '10 days',
        format('parent=%s stocké=%s', v_parent_created_at, v_stored_created_at));

    -- Neutralise l'impact sur la capacité (issuance_status voided exclu par
    -- carbon_capacity_consumed_for_session(), §15 point 4).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    PERFORM public.void_credit_issuance(v_id41bis, 'Neutralisation post-test B41bis (dix-huitième revue statique)');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count_issuance INT;
    v_count_sources  INT;
    v_count_own      INT;
BEGIN
    -- Source A (admin_a, membre de l'organisation '...101' seulement).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_a'));
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count_issuance FROM public.credit_issuances
        WHERE id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID;
    SELECT count(*) INTO v_count_sources FROM public.credit_issuance_sources
        WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID;
    SELECT count(*) INTO v_count_own FROM public.credit_issuance_sources
        WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID
          AND organization_id = '11111111-1111-1111-1111-111111111101';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B39-A', 'Source A voit l''émission M et EXACTEMENT sa propre ligne source (pas celle de Source B) — RLS réelle',
        v_count_issuance = 1 AND v_count_sources = 1 AND v_count_own = 1,
        format('issuance=%s sources_visibles=%s dont_propre=%s', v_count_issuance, v_count_sources, v_count_own));
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count_issuance INT;
    v_count_sources  INT;
    v_count_own      INT;
BEGIN
    -- Source B (admin_b, membre de l'organisation '...102' seulement).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_b'));
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count_issuance FROM public.credit_issuances
        WHERE id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID;
    SELECT count(*) INTO v_count_sources FROM public.credit_issuance_sources
        WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID;
    SELECT count(*) INTO v_count_own FROM public.credit_issuance_sources
        WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID
          AND organization_id = '11111111-1111-1111-1111-111111111102';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B39-B', 'Source B voit l''émission M et EXACTEMENT sa propre ligne source (pas celle de Source A) — RLS réelle',
        v_count_issuance = 1 AND v_count_sources = 1 AND v_count_own = 1,
        format('issuance=%s sources_visibles=%s dont_propre=%s', v_count_issuance, v_count_sources, v_count_own));
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count_sources INT;
BEGIN
    -- Opérateur figé (admin_opa) : voit les DEUX lignes source (branche
    -- privilégiée du nouveau helper can_view_credit_issuance_source()).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count_sources FROM public.credit_issuance_sources
        WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B39-operateur', 'opérateur figé voit les DEUX lignes source de l''émission M (branche privilégiée) — RLS réelle',
        v_count_sources = 2, v_count_sources::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count_sources INT;
BEGIN
    -- Admin du regroupement (verifier, aggregator_admins réel) : voit les
    -- DEUX lignes source (branche privilégiée is_aggregator_admin()).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier'));
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count_sources FROM public.credit_issuance_sources
        WHERE credit_issuance_id = NULLIF(current_setting('carbon_test.issuance_M', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B39-aggregateur', 'admin du regroupement voit les DEUX lignes source de l''émission M (branche privilégiée) — RLS réelle',
        v_count_sources = 2, v_count_sources::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Vérificateur assigné/non assigné sur l'émission M : DIFFÉRÉ, même motif
-- que documenté ci-dessus pour B18 (is_assigned_verifier() et le mécanisme
-- d'assignation appartiennent entièrement à la migration 05, non rédigée —
-- à couvrir avec sa contre-épreuve non assignée à ce moment-là).

-- B40 (correction 1, treizième revue statique) : can_view_credit_issuance_source()
-- appelée DIRECTEMENT (hors policy RLS, SECURITY DEFINER + EXECUTE
-- authenticated, donc appelable avec des arguments arbitraires) ne doit
-- plus servir d'oracle d'existence sur credit_issuances. Émission N,
-- mono-source, dont l'UNIQUE source est Source B (org '...102') — Source A
-- (org '...101') n'y a AUCUN lien (ni adhésion partagée, ni ligne
-- credit_issuance_sources).
DO $$
DECLARE
    v_idN UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_opa'));
    v_idN := public.create_credit_issuance('11111111-1111-1111-1111-111111111809',
        jsonb_build_array(jsonb_build_object(
            'organization_id', '11111111-1111-1111-1111-111111111102',
            'aggregator_membership_id', '11111111-1111-1111-1111-111111111402',
            'commercialization_mandate_id', '11111111-1111-1111-1111-111111111502',
            'contributed_tco2e', 1)));
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM set_config('carbon_test.issuance_N', v_idN::text, false);
END $$;

DO $$
DECLARE
    v_result_real        BOOLEAN;
    v_result_nonexistent BOOLEAN;
BEGIN
    -- Source A (admin_a) appelle DIRECTEMENT le helper sur l'émission N
    -- (dont elle n'est PAS une source) : doit renvoyer false — AVANT le
    -- correctif, is_organization_member('...101') seul suffisait à rendre
    -- true dès que N existait, sans aucun lien avec N.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('admin_a'));
    v_result_real := COALESCE(public.can_view_credit_issuance_source(
        NULLIF(current_setting('carbon_test.issuance_N', true), '')::UUID,
        '11111111-1111-1111-1111-111111111101'), false);
    -- Même appel, mais avec un UUID d'émission INEXISTANT — les deux
    -- résultats doivent être INDISTINGUABLES (aucun oracle d'existence :
    -- « émission réelle mais sans lien » et « émission inexistante »
    -- doivent produire exactement la même réponse false).
    v_result_nonexistent := COALESCE(public.can_view_credit_issuance_source(
        gen_random_uuid(), '11111111-1111-1111-1111-111111111101'), false);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B40', 'can_view_credit_issuance_source() en appel direct : Source A sans lien avec l''émission N obtient false, indistinguable d''une émission inexistante (aucun oracle d''existence)',
        v_result_real = false AND v_result_nonexistent = false AND v_result_real = v_result_nonexistent,
        format('réelle_sans_lien=%s inexistante=%s', v_result_real, v_result_nonexistent));
END $$;

-- ────────────────────────────────────────────────────────────
-- GATE FINALE (correction 6, cinquième revue statique) : force la
-- vérification IMMÉDIATE de TOUTES les contraintes différées en attente,
-- toutes tables confondues, juste avant le résumé. Si un test précédent a
-- laissé un état réellement incohérent (et pas seulement une écriture déjà
-- annulée par un bloc d'exception, comme B15/B19 ci-dessus), cette
-- instruction lève une exception ICI, au niveau supérieur — non interceptée
-- — ce qui interrompt le script AVANT le résumé et annule tout via
-- l'abandon de transaction implicite. C'est le comportement voulu : mieux
-- vaut un script qui s'arrête bruyamment avec un message d'erreur clair
-- qu'un résumé silencieux masquant une incohérence réelle.
SET CONSTRAINTS ALL IMMEDIATE;

-- ────────────────────────────────────────────────────────────
-- GATE FINALE N/N (correction 7, septième revue statique ; recomptée,
-- huitième revue statique ; recomptée, neuvième revue statique ; recomptée,
-- dixième revue statique ; recomptée, onzième revue statique ; recomptée,
-- douzième revue statique ; recomptée, treizième revue statique ; recomptée,
-- quatorzième revue statique ; recomptée, quinzième revue statique ; recomptée,
-- seizième revue statique ; recomptée, dix-septième revue statique) : impose
-- EXACTEMENT 110 assertions au total et ZÉRO échec avant de passer au
-- résumé. Complète le SET CONSTRAINTS ALL IMMEDIATE ci-dessus (qui vérifie
-- la cohérence des DONNÉES) par une vérification de la cohérence des
-- RÉSULTATS DE TEST eux-mêmes : un total inattendu masquerait un test
-- jamais exécuté (label dupliqué écrasant un autre, bloc DO silencieusement
-- sauté, etc.), et un échec non détecté ici passerait inaperçu si le résumé
-- n'est pas lu attentivement. RAISE EXCEPTION non intercepté interrompt le
-- script avant le résumé.
--
-- Dixième revue statique : 84 -> 89 (+5). Ajouts : A17 (existence/absence
-- d'EXECUTE de l'helper carbon_lock_and_validate_source_organization()),
-- A18 (existence du trigger trg_carbon_platform_operators_before_revoke sur
-- platform_operators), B22bis (INSERT direct rejeté pour un
-- operator_organization_id non-actif), B36/B37 (branche MRV, positif/négatif,
-- via l'helper centralisé). A16 a été REVU (verrous project_participants
-- déplacés vers l'helper, checks correspondants adaptés) sans changer son
-- décompte (reste 1 assertion composite). B13ter/B13quater/B13quinquies ont
-- été RÉÉCRITS sur le nouvel invariant de transfert (§15.10.d) — mêmes
-- labels, même décompte (3), sémantique différente ; les anciens tests
-- qu'ils remplaçaient (autorisation sur une émission figée sous un
-- opérateur non-actif) sont retirés car l'état qu'ils exerçaient est
-- désormais structurellement inatteignable.
--
-- Onzième revue statique : 89 -> 97 (+8). Aucun nouveau label A/B hors B38 :
-- B25/B29/B32 résorbent désormais localement (void_credit_issuance()) leur
-- émission de test, sans ajouter d'assertion — condition nécessaire à la
-- réussite réelle de B13quinquies (le nouveau trigger platform_operators
-- aurait sinon rejeté le transfert, ces trois émissions restant
-- internal/eligible sous OP_A). Périodes de verification_sessions S1-S6
-- rendues strictement non chevauchantes (anticipe l'EXCLUDE USING gist prévu
-- par la conception de la migration 05) — aucun impact sur le décompte.
-- Ajout de B38-1 à B38-8 (composite, 8 assertions) : les 7 RPC d'émission
-- renseignent désormais organization_id (= operator_organization_id figé),
-- aggregator_id et verification_session_id sur leur événement
-- carbon_business_events — vérifié pour chacune des 7 transitions (create/
-- mark_eligible/submit/record_registry_issuance/record_external_cancellation/
-- void/record_externally_rejected) plus une contre-épreuve négative (RPC
-- rejetée ne produit aucun événement de succès supplémentaire).
--
-- Douzième revue statique : 97 -> 102 (+5). A19 (existence du nouveau helper
-- RLS ligne-par-ligne can_view_credit_issuance_source(), EXECUTE
-- authenticated, mirroir A7). B39-A/B39-B/B39-operateur/B39-aggregateur
-- (correction 1/4, douzième revue statique) : émission RÉELLEMENT
-- multi-source (session/outcome S9 dédiés) — Source A voit l'émission et
-- EXACTEMENT sa propre ligne (pas celle de Source B), Source B
-- symétriquement, opérateur figé et aggregator admin voient les DEUX
-- lignes. Scénario qu'aucun test existant n'exerçait (B1 crée deux
-- émissions à une source chacune, jamais une émission à plusieurs sources)
-- — c'est précisément le scénario qui aurait révélé la fuite RLS corrigée
-- ce tour (credit_issuance_sources_select réutilisait can_view_credit_issuance(),
-- qui rend TRUE dès qu'un appelant est membre de N'IMPORTE QUELLE
-- organisation source, laissant lire TOUTES les lignes source d'une
-- émission dès qu'on est membre d'une seule d'entre elles). B38-2/3/4/5/7/8
-- durcis de EXISTS(...) vers count(*) = 1 (même label, même décompte) :
-- EXISTS reste vrai même si un doublon d'événement était inséré ; la règle
-- demandée est « exactement un événement » pour une transition réussie,
-- pas « au moins un » — cohérent avec B38-1/B38-6 qui l'imposaient déjà.
--
-- ⚠️ CE TOTAL EST INTERMÉDIAIRE (rappel explicite, points différés) : il ne
-- couvre PAS encore la visibilité RLS du vérificateur assigné et sa
-- contre-épreuve non assignée (bloqué jusqu'à la rédaction réelle de la
-- migration 05, cf. commentaire détaillé section B18 plus bas), ni la
-- réconciliation du cycle de vie de ccf_mrv_project_links / son
-- verrouillage cohérent par 07 (contrat explicite 04→07, bloqué jusqu'à la
-- rédaction réelle de la migration 04, cf. section 0 en tête de fichier de
-- la migration et commentaires check 8 de create_credit_issuance()/
-- submit_credit_issuance()/carbon_lock_and_validate_source_organization()).
-- Condition supplémentaire notée en onzième revue (non bloquante
-- aujourd'hui, 04 n'existe pas encore) : si 04 autorise plusieurs liens
-- historiques ccf_mrv_project_links pour un même projet, 04 devra garantir
-- soit l'unicité du lien effectif, soit que 07 identifie et verrouille
-- explicitement CE lien précis. 102/102 signifie « tout ce qui est
-- actuellement testable passe », pas « couverture complète et définitive ».
-- (correction 3, treizième revue statique) : count(*) = N seul ne prouve PAS
-- qu'il y a N assertions DISTINCTES — un label exécuté deux fois (écrasant
-- silencieusement un autre test jamais atteint) produirait toujours N
-- lignes au total. `section` est en réalité l'identifiant de test (label
-- 'A1'..'B40' passé en premier argument à carbon_test_assert()/
-- carbon_test_assert_raises(), cf. leur définition ci-dessus) — le gate
-- exige donc désormais ÉGALEMENT count(DISTINCT section) = N, en plus de
-- count(*) = N, pour détecter ce cas précis.
--
-- Quatorzième revue statique : 103 -> 105 (+2). B27bis/B28bis (durcissement,
-- défense structurelle des documents de preuve) : carbon_credit_issuances_before_update()
-- vérifie désormais lui-même que external_rejection_document_id/
-- external_cancellation_document_id appartient à l'organisation opératrice
-- figée de l'émission (owner_org_id = NEW.operator_organization_id), pas
-- seulement les RPC record_externally_rejected()/record_external_cancellation() —
-- un contournement direct hors RPC avec une preuve par ailleurs complète mais
-- un document d'une autre organisation est désormais rejeté par le trigger
-- lui-même, symétriquement à B27/B28 qui couvraient déjà l'absence de preuve.
--
-- Quinzième revue statique : 105 -> 107 (+2). B22ter/B22quater (durcissement,
-- interdiction structurelle de NaN) : NUMERIC accepte NaN indépendamment de
-- la précision/échelle déclarée, et PostgreSQL le traite comme supérieur à
-- toute valeur numérique ordinaire pour les opérateurs de comparaison — les
-- CHECK `> 0` seuls sur quantity_tco2e/contributed_tco2e ne l'excluaient donc
-- pas. CHECK de table durcis (`<> 'NaN'::numeric` ajouté), plus rejet
-- explicite dans create_credit_issuance() (v_contributed) et dans le
-- constraint trigger de capacité (v_active_eligible, défense en profondeur
-- pour une colonne dont 07 ne possède pas encore le CHECK, propriété de la
-- migration 05) — ces deux derniers durcissements n'ajoutent pas
-- d'assertion indépendante (déjà couverts par B22ter/B22quater côté CHECK
-- de table, premier rempart atteint avant tout code applicatif).
--
-- Seizième revue statique : 107 -> 108 (+1). B12terbis (durcissement,
-- canonicalisation de l'unicité registre) : l'index unique portait sur
-- (registry_name, registry_reference) bruts alors que les RPC ne
-- validaient que btrim(...) <> '' sans normaliser la valeur stockée —
-- 'Verra'/' VERRA '/'ABC-123'/' ABC-123 ' pouvaient coexister comme des
-- clés distinctes pour la même référence externe réelle. Index refait sur
-- (lower(btrim(registry_name)), btrim(registry_reference)) — casse de
-- registry_reference conservée (aucune présomption qu'un registre externe
-- la traite comme insensible), casse de registry_name normalisée. RPC
-- durcies pour stocker la valeur normalisée (btrim), cohérente avec ce que
-- l'index compare réellement. La correction temporelle created_at
-- (v_created_at := clock_timestamp() au lieu de now(), même tour) n'ajoute
-- aucune assertion indépendante — aucun test n'a été demandé pour ce point,
-- purement structurel.
--
-- Dix-septième revue statique : 108 -> 110 (+2). B41/B41bis (correction
-- bloquante, redesign de la capture de created_at) : v_created_at était
-- capturé TROP TÔT dans create_credit_issuance() (avant les verrous et les
-- contrôles temporels des adhésions), qui, eux, réévaluaient l'activité
-- avec de nouveaux appels à clock_timestamp() — une adhésion pouvait donc
-- devenir active PENDANT une attente de verrou et être acceptée par le
-- contrôle, tout en laissant l'émission persistée avec un created_at
-- antérieur à sa propre autorité. Corrigé : carbon_credit_issuances_before_insert()
-- fixe désormais lui-même NEW.created_at := clock_timestamp(),
-- structurellement APRÈS tous les contrôles (ordre séquentiel d'exécution) ;
-- create_credit_issuance() récupère cette valeur par RETURNING et la
-- propage aux sources ; carbon_validate_credit_issuance_source() valide
-- désormais l'activité de l'adhésion relativement à CET instant (pas un
-- nouveau clock_timestamp() propre à chaque source insérée), FORCE
-- NEW.created_at à cette même valeur sur chaque source (élimine toute
-- dérive par construction), et ajoute un check 9 (mandat non accordé après
-- l'instant de constitution). B41 vérifie que toutes les sources de
-- l'émission M (réelle, multi-source) partagent exactement le created_at
-- du parent ; B41bis est la contre-épreuve structurelle — un contournement
-- direct avec un created_at de source explicitement antidaté de 10 jours
-- voit sa valeur ignorée, la ligne stockée portant malgré tout le
-- created_at réel du parent.
--
-- Dix-huitième revue statique : N inchangé (110), correction non additive
-- de B41bis. La version dix-septième créait le parent via create_credit_issuance()
-- avec la seule Source A (quantity_tco2e=1, déduit de cette unique source),
-- puis ajoutait directement une Source B non comptée dans ce total —
-- SUM(sources)=2 pour quantity_tco2e=1, incohérence que
-- trg_carbon_validate_sources_sum (contrainte différée) aurait détectée au
-- SET CONSTRAINTS ALL IMMEDIATE final ci-dessous, interrompant tout le
-- script avant d'atteindre ce gate. Corrigé : B41bis construit désormais
-- une émission dédiée, entièrement par INSERT direct (parent ET les deux
-- sources), avec quantity_tco2e=2 fixé cohérent avec la somme des deux
-- sources dès la construction — la contre-épreuve du created_at antidaté
-- reste inchangée sur la Source B. L'émission est voidée en fin de bloc
-- pour neutraliser son impact sur la capacité de la session partagée.
DO $$
DECLARE
    v_total    INT;
    v_distinct INT;
    v_failed   INT;
BEGIN
    SELECT count(*), count(DISTINCT section), count(*) FILTER (WHERE NOT passed)
    INTO v_total, v_distinct, v_failed
    FROM public._carbon_migration_test_results;

    IF v_total <> 110 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertions exécutées, 110 attendues (test manquant, label dupliqué, ou bloc non exécuté).', v_total;
    END IF;

    IF v_distinct <> 110 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % labels DISTINCTS sur % lignes totales (110 attendus pour les deux) — un label a été exécuté plus d''une fois, masquant potentiellement un test jamais atteint.', v_distinct, v_total;
    END IF;

    IF v_failed <> 0 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertion(s) sur 110 ont échoué (0 attendu). Voir le résumé détaillé ci-dessous pour l''identification.', v_failed;
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────
-- 5. RÉSUMÉ — affiché AVANT le ROLLBACK.
--    Le client SQL reçoit ces deux résultats immédiatement ; le ROLLBACK
--    qui suit n'efface que l'état persisté, pas ce qui a déjà été renvoyé.
--    NOMBRE D'ASSERTIONS ATTENDU (recalculé, dix-septième revue statique) : 110,
--    TOTAL INTERMÉDIAIRE (voir avertissement au-dessus du gate) — 19
--    prévalidations (A1-A19) + 91 tests comportementaux (B-series, labels
--    distincts B1 à B41 y compris leurs variantes bis/ter/quater/quinquies/
--    sexies/septies, B17-1 à B17-6, B18-source/operateur/aggregateur/
--    outsider, B12terbis, B22ter, B22quater, B27bis, B28bis, B38-1 à B38-8,
--    B39-A/B/operateur/aggregateur, B40, B41, B41bis). +2 vs la seizième
--    revue (108) : B41/B41bis (correction bloquante, redesign de la capture
--    de created_at — voir commentaire détaillé au-dessus du gate).
--    +1 vs la quinzième revue (107) :
--    B12terbis (durcissement, seizième revue statique — unicité
--    (registry_name, registry_reference) désormais canonisée via
--    lower(btrim(registry_name))/btrim(registry_reference), une variation
--    de casse/espaces ne permet plus de contourner l'unicité recherchée).
--    +2 vs la quatorzième revue (105) :
--    B22ter/B22quater (durcissement, quinzième revue statique — interdiction
--    structurelle de NaN sur quantity_tco2e/contributed_tco2e, CHECK de
--    table durci en plus des CHECK `> 0` existants, NaN étant traité par
--    PostgreSQL comme supérieur à toute valeur numérique ordinaire).
--    +2 vs la treizième revue (103) : B27bis/B28bis (durcissement,
--    quatorzième revue statique — carbon_credit_issuances_before_update()
--    vérifie désormais que le document de preuve appartient à l'organisation
--    opératrice figée lors d'un contournement direct hors RPC, preuve par
--    ailleurs complète — symétrique à la validation déjà faite par
--    record_externally_rejected()/record_external_cancellation(), et à B27/
--    B28 qui couvraient déjà l'absence de preuve mais pas sa provenance).
--    +1 vs la douzième revue (102) : B40 (correction 1, treizième revue statique —
--    can_view_credit_issuance_source() appelée directement, hors policy
--    RLS, avec des arguments arbitraires ne doit plus servir d'oracle
--    d'existence sur credit_issuances : Source A sans aucun lien avec une
--    émission N mono-source-B obtient false, indistinguable d'un appel sur
--    un UUID d'émission inexistant). La branche « organisation ordinaire »
--    du helper exige désormais une vraie ligne credit_issuance_sources
--    reliant les deux paramètres, plus seulement is_organization_member().
--    A16 corrigé (durcissement, treizième revue statique) : `\b` en regex
--    PostgreSQL (ARE) est l'échappement du caractère backspace, PAS une
--    frontière de mot — remplacé par `\y` (la vraie frontière de mot
--    PostgreSQL). Le gate final vérifie désormais ÉGALEMENT
--    count(DISTINCT section) = N, en plus de count(*) = N (durcissement,
--    treizième revue statique — count(*) seul ne détecterait pas un label
--    dupliqué masquant un test jamais atteint).
--    +5 vs la onzième revue (97) : A19 (existence du nouveau helper RLS
--    ligne-par-ligne can_view_credit_issuance_source(), EXECUTE
--    authenticated, mirroir A7), B39-A/B39-B/B39-operateur/B39-aggregateur
--    (correction 1/4, douzième revue statique — émission RÉELLEMENT
--    multi-source, session/outcome S9 dédiés : Source A voit l'émission et
--    EXACTEMENT sa propre ligne source, jamais celle de Source B, et
--    symétriquement pour B ; opérateur figé et aggregator admin voient les
--    DEUX lignes). Ce scénario révélait la fuite RLS corrigée ce tour :
--    credit_issuance_sources_select réutilisait can_view_credit_issuance(id),
--    qui rend TRUE dès qu'un appelant est membre de N'IMPORTE QUELLE
--    organisation source d'une émission — appliqué comme USING de la
--    policy sur credit_issuance_sources, cela laissait une organisation
--    source lire TOUTES les lignes source de l'émission, pas seulement la
--    sienne. Corrigé par un helper dédié, ligne par ligne, recevant
--    explicitement l'organization_id de la ligne évaluée. B38-2/3/4/5/7/8
--    durcis de EXISTS(...) vers count(*) = 1 (mêmes labels, même décompte) :
--    EXISTS restait vrai même en cas de doublon d'événement inséré.
--    +8 vs la dixième revue (89) : B38-1 à B38-8
--    (correction 3, onzième revue statique — test composite couvrant les 7
--    RPC d'émission : chacune renseigne désormais organization_id (=
--    operator_organization_id figé), aggregator_id et
--    verification_session_id sur son événement carbon_business_events,
--    dimensions d'autorisation de can_view_carbon_event() [§10bis] ; plus
--    une contre-épreuve négative, RPC rejetée ne produit aucun événement de
--    succès). B25/B29/B32 résorbent désormais localement leur émission de
--    test (void_credit_issuance()) — aucun nouveau label, mais condition
--    NÉCESSAIRE à la réussite de B13quinquies (sans cette résorption, le
--    trigger carbon_platform_operators_before_revoke() aurait rejeté le
--    transfert OP_A -> OP_B, ces trois émissions restant internal/eligible
--    sous OP_A). Périodes des verification_sessions S1-S6 rendues
--    strictement non chevauchantes (anticipe l'EXCLUDE USING gist prévu par
--    la conception de la migration 05) — aucun impact sur le décompte.
--    +5 vs la neuvième revue (84) : A17 (existence de l'helper
--    carbon_lock_and_validate_source_organization(), sans EXECUTE à
--    authenticated), A18 (existence du trigger
--    trg_carbon_platform_operators_before_revoke sur platform_operators),
--    B22bis (correction 1, INSERT direct rejeté pour un
--    operator_organization_id non-actif), B36/B37 (correction 3, branche
--    MRV positif/négatif via l'helper centralisé). A16 a été REVU
--    (dixième revue statique) : les verrous project_participants portés
--    directement par create_credit_issuance()/submit_credit_issuance() ont
--    été retirés du test (déplacés vers l'helper, cf. migration), remplacés
--    par la preuve que l'helper lui-même verrouille
--    project_participants/projects/operational_units et que les trois
--    points d'appel délèguent bien à cet helper — même label, même total (1
--    assertion composite). B13ter/B13quater/B13quinquies ont été RÉÉCRITS
--    sur le nouvel invariant de transfert d'opérateur (§15.10.d, décision
--    architecturale documentée dans Tranche0-Carbone-Architecture.md, PAS
--    dans ADR-MVP.md) : ils testent désormais le REJET du transfert tant
--    qu'une émission internal/eligible existe, puis sa réussite une fois
--    résorbée — mêmes labels, même total (3), sémantique différente. Les
--    anciens tests qu'ils remplaçaient (autorisation sur une émission figée
--    sous un opérateur devenu non-actif) sont retirés : cet état est
--    désormais structurellement inatteignable par construction. Recompté
--    mécaniquement (labels distincts effectivement passés à
--    pg_temp.carbon_test_assert()/carbon_test_assert_raises()) — ne PAS
--    compter les occurrences textuelles brutes de ces deux noms de fonction
--    dans le fichier : plusieurs tests appellent le même label UNE FOIS
--    chacun dans deux branches mutuellement exclusives (BEGIN...réussite /
--    EXCEPTION...échec), donc une seule ligne est effectivement insérée par
--    label au moment de l'exécution. Le gate ci-dessus applique désormais
--    ce compte, mécaniquement, avant même d'afficher ce résumé.
-- ────────────────────────────────────────────────────────────
SELECT
    count(*) AS total_assertions,
    count(*) FILTER (WHERE passed) AS total_reussies,
    count(*) FILTER (WHERE NOT passed) AS total_echouees
FROM public._carbon_migration_test_results;

SELECT section, assertion, detail
FROM public._carbon_migration_test_results
WHERE NOT passed
ORDER BY id;

-- ────────────────────────────────────────────────────────────
-- 6. ROLLBACK INCONDITIONNEL — annule TOUTES les écritures de ce script :
--    fixtures, désignations d'opérateur (OP_A puis OP_B puis OP_A), mandats,
--    événements, table diagnostique. L'état réel de platform_operators (et
--    son historique), les mandats réels, et carbon_business_events
--    reviennent exactement à ce qu'ils étaient avant l'exécution de ce script.
-- ────────────────────────────────────────────────────────────
ROLLBACK;
-- ============================================================
