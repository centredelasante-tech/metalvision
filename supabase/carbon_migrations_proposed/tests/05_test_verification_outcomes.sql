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
-- Profils : RÉUTILISATION de 7 profils réels existants (même motif que
-- tests/07/tests/04 — porté de 6 à 7, correctif vingtième revue statique,
-- pour disposer d'un second client distinct, voir « client_b » ci-dessous).
-- pg_temp.carbon_test_set_actor_role() simule un rôle JWT ARBITRAIRE (pas
-- seulement superadmin/rien) — nécessaire pour is_project_admin(), qui
-- dépend de auth.jwt()->'app_metadata'->>'role' IN (...) et non d'une simple
-- adhésion organisationnelle.
--
-- CORRECTIF VINGTIÈME REVUE STATIQUE — changements de fixtures :
--   • Un second projet MRV '...6002' (« Projet B »), client_id =
--     profile_client_b, et une session S7 ('...7007') avec un résultat
--     inséré DIRECTEMENT (hors RPC — seule la visibilité RLS est testée,
--     pas complete_verification_session() une seconde fois) — nécessaires
--     pour distinguer Client A (projet A, '...6001', client_id =
--     profile_project_client) de Client B (projet B) dans
--     can_view_verification_outcome() (blocage 2 : is_project_client()
--     seul donnait accès à TOUS les résultats, remplacé par la relation
--     réelle projects.client_id = auth.uid()).
--   • Une session S8 ('...7008'), jamais touchée avant la section 9,
--     dédiée aux tests de plan_verification_session().
--   • S6 gagne un verifier_user_id assigné directement (bypass) dès les
--     fixtures — nécessaire pour tester B3 (« planned rencontré ») avec un
--     appelant réellement autorisé, la dérogation superadmin ayant été
--     retirée de complete_verification_session() (blocage 4).
--
-- CORRECTIF VINGT-ET-UNIÈME REVUE STATIQUE — changements de fixtures :
--   • Documents/organisation remplacés par TROIS evidence_files réels,
--     scopés par project_id (blocage 5) : '...339001' (type=
--     'verification_report', project A), '...339002' (type='other', projet
--     A, invalide), '...339003' (type='verification_report', projet B —
--     nécessaire pour S7, qui appartient au projet B et échouerait
--     désormais la validation d'appartenance si on lui fournissait la
--     preuve du projet A).
--   • S7 REFAITE : transition explicite vers in_progress avec période et
--     vérificateur assignés AVANT l'INSERT direct du résultat — le nouveau
--     trigger BEFORE INSERT (blocage 4) rejette toute insertion tant que la
--     session est encore 'planned' ou n'a ni période ni vérificateur.
--   • Deux nouvelles sessions dédiées aux tests structurels du trigger
--     BEFORE INSERT et du trigger de garde de session, chacune jamais
--     touchée avant sa section dédiée pour rester réutilisable par
--     plusieurs tests négatifs indépendants (chaque échec est annulé par le
--     savepoint implicite de carbon_test_assert_raises) :
--       S9  ('...7009') — in_progress, période juillet 2026, vérificateur
--           assigné, JAMAIS dotée d'un résultat — sert au test blocage 3
--           (transition completed refusée sans résultat), au test
--           verified_by non concordant, et au test composite FK
--           inter-session (section 7bis).
--       S10 ('...7010') — in_progress, vérificateur assigné, période NULL
--           — sert au test « période manquante » du trigger BEFORE INSERT.
--
-- ⚠️ LIMITE RÉSIDUELLE ASSUMÉE : B25 (admin voit, via is_project_admin())
-- reste fondé sur un JWT synthétique (rôle générique, sans portée par
-- projet) — is_project_admin() lui-même n'est PAS modifié par cette
-- migration (portée globale intentionnelle, cohérente avec
-- admin_manage_verification_sessions déjà FOR ALL). Contrairement à B26 (qui
-- teste désormais la relation RÉELLE projects.client_id = auth.uid(), un
-- champ JWT standard — 'sub' — déjà simulé de façon réaliste par
-- carbon_test_set_actor()), B25 ne peut pas être rendu plus réaliste sans
-- redessiner is_project_admin() lui-même, hors périmètre de cette migration.
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

-- Correctif exécution réelle (identique à tests/04) : plusieurs tests
-- basculent délibérément SET LOCAL ROLE authenticated pour exercer le
-- chemin RLS réel. La table ET sa séquence SERIAL sous-jacente ne sont pas
-- automatiquement accessibles à authenticated — sans ce GRANT, tout test
-- exécuté sous authenticated échoue sur "permission denied for sequence
-- ..._id_seq" au moment d'ENREGISTRER le résultat, pas sur le test
-- lui-même. Portée strictement locale : annulé par le ROLLBACK final.
GRANT SELECT, INSERT ON public._carbon_migration_test_results TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public._carbon_migration_test_results_id_seq TO authenticated;

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

-- Correctif exécution réelle (identique à tests/04, découvert en exécutant
-- ce dernier) : is_platform_superadmin()/is_project_admin() (migrations
-- 06/antérieures, déjà en production) évaluent
-- `(auth.jwt()->'app_metadata'->>'role') = 'admin'` (ou IN (...)) SANS
-- COALESCE — app_metadata VIDE ({}) donne NULL, pas FALSE, et `IF NOT
-- is_platform_superadmin() THEN RAISE EXCEPTION` échoue alors OUVERT
-- (NOT NULL = NULL). Affecte potentiellement B32 (plan_verification_
-- session() rejette un appelant ni admin de projet ni super-admin, gate
-- `is_project_admin() OR is_platform_superadmin()`) si jamais exécuté avec
-- l'ancienne branche app_metadata={}. 'role' explicitement renseigné
-- (jamais 'admin'/'project_admin') pour garantir un résultat booléen
-- défini.
CREATE OR REPLACE FUNCTION pg_temp.carbon_test_set_actor(p_user_id UUID, p_superadmin BOOLEAN DEFAULT false) RETURNS VOID
LANGUAGE sql AS $$
    SELECT set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', p_user_id::text,
            'role', 'authenticated',
            'app_metadata', CASE WHEN p_superadmin THEN jsonb_build_object('role', 'admin') ELSE jsonb_build_object('role', 'user') END
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
    -- Correctif vingtième revue statique (blocage 1) : la policy générale a
    -- été SUPPRIMÉE (une policy RLS UPDATE ne filtre pas les colonnes) —
    -- A13 vérifie désormais son ABSENCE, remplacée par plan_verification_session()
    -- (A15) + le trigger de garde structurel (A16).
    PERFORM pg_temp.carbon_test_assert('A13', 'policy verification_sessions_assigned_verifier_update N''existe PLUS (supprimée, correctif vingtième revue statique)',
        NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='verification_sessions' AND policyname='verification_sessions_assigned_verifier_update'));
    PERFORM pg_temp.carbon_test_assert('A14', 'privilèges de table : authenticated a SELECT seulement sur verification_outcomes',
        has_table_privilege('authenticated', 'public.verification_outcomes', 'SELECT')
        AND NOT has_table_privilege('authenticated', 'public.verification_outcomes', 'INSERT')
        AND NOT has_table_privilege('authenticated', 'public.verification_outcomes', 'UPDATE')
        AND NOT has_table_privilege('authenticated', 'public.verification_outcomes', 'DELETE'));
    PERFORM pg_temp.carbon_test_assert('A15', 'plan_verification_session(uuid,date,date,uuid) existe, EXECUTE authenticated/anon révoqué',
        to_regprocedure('public.plan_verification_session(uuid,date,date,uuid)') IS NOT NULL
        AND has_function_privilege('authenticated', 'public.plan_verification_session(uuid,date,date,uuid)'::regprocedure, 'EXECUTE')
        AND NOT has_function_privilege('anon', 'public.plan_verification_session(uuid,date,date,uuid)'::regprocedure, 'EXECUTE'));
    PERFORM pg_temp.carbon_test_assert('A16', 'trigger de garde structurel verification_sessions_guard_update existe',
        EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'verification_sessions' AND tg.tgname = 'verification_sessions_guard_update'));
    PERFORM pg_temp.carbon_test_assert('A17', 'verification_report_document_id est NOT NULL',
        EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='verification_outcomes'
                  AND column_name='verification_report_document_id' AND is_nullable='NO'));
    PERFORM pg_temp.carbon_test_assert('A18', 'CHECK anti-auto-référence supersedes_outcome_id présent',
        EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                WHERE t.relname = 'verification_outcomes' AND c.contype = 'c'
                  AND c.conname = 'verification_outcomes_no_self_supersede'));
    PERFORM pg_temp.carbon_test_assert('A19', 'index unique partiel anti-fork (supersedes_outcome_id) présent',
        EXISTS (SELECT 1 FROM pg_indexes
                WHERE schemaname='public' AND tablename='verification_outcomes'
                  AND indexname = 'idx_verification_outcomes_supersedes_once'));
    PERFORM pg_temp.carbon_test_assert('A20', 'index unique partiel une seule racine par session présent',
        EXISTS (SELECT 1 FROM pg_indexes
                WHERE schemaname='public' AND tablename='verification_outcomes'
                  AND indexname = 'idx_verification_outcomes_one_root_per_session'));
    PERFORM pg_temp.carbon_test_assert('A21', 'FK composite (id, verification_session_id) forçant la même session présente',
        EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                WHERE t.relname = 'verification_outcomes' AND c.contype = 'f'
                  AND c.conname = 'verification_outcomes_supersedes_same_session'));
    -- Correctif vingt-et-unième revue statique.
    PERFORM pg_temp.carbon_test_assert('A22', 'trigger de garde structurel BEFORE INSERT (verification_outcomes_guard_insert) présent',
        EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'verification_outcomes' AND tg.tgname = 'verification_outcomes_guard_insert'));
    PERFORM pg_temp.carbon_test_assert('A23', 'policies verifier_read_.../client_read_verification_sessions scopées (is_assigned_verifier()/can_client_view_verification_session()), plus is_verifier()/is_project_client() génériques',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='verification_sessions'
                  AND policyname='verifier_read_verification_sessions' AND qual ILIKE '%is_assigned_verifier(%')
        AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='verification_sessions'
                  AND policyname='client_read_verification_sessions' AND qual ILIKE '%can_client_view_verification_session(%' AND qual NOT ILIKE '%is_project_client()%'));
    PERFORM pg_temp.carbon_test_assert('A24', 'verification_report_document_id référence evidence_files (pas documents)',
        EXISTS (SELECT 1 FROM information_schema.constraint_column_usage ccu
                JOIN information_schema.table_constraints tc ON tc.constraint_name = ccu.constraint_name AND tc.constraint_schema = ccu.constraint_schema
                WHERE tc.table_name = 'verification_outcomes' AND tc.constraint_type = 'FOREIGN KEY'
                  AND ccu.table_name = 'evidence_files'));
    -- Correctif vingt-deuxième revue statique.
    PERFORM pg_temp.carbon_test_assert('A25', 'table accredited_verifiers + is_authorized_verifier_identity(uuid) présents (point 2)',
        to_regclass('public.accredited_verifiers') IS NOT NULL
        AND to_regprocedure('public.is_authorized_verifier_identity(uuid)') IS NOT NULL
        AND NOT has_function_privilege('authenticated', 'public.is_authorized_verifier_identity(uuid)'::regprocedure, 'EXECUTE'));
    PERFORM pg_temp.carbon_test_assert('A26', 'CONSTRAINT TRIGGER différés de l''invariant session/outcome présents sur les deux tables (point 3)',
        EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'verification_outcomes' AND tg.tgname = 'verification_outcomes_check_session_invariant'
                  AND tg.tgdeferrable AND tg.tginitdeferred)
        AND EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'verification_sessions' AND tg.tgname = 'verification_sessions_check_outcome_invariant'
                  AND tg.tgdeferrable AND tg.tginitdeferred));
    PERFORM pg_temp.carbon_test_assert('A27', 'evidence_files.file_hash + trigger de gel evidence_files_guard_update présents (point 5)',
        EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='evidence_files' AND column_name='file_hash')
        AND EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'evidence_files' AND tg.tgname = 'evidence_files_guard_update'));
    PERFORM pg_temp.carbon_test_assert('A28', 'policies verifier_read_projects/activity_logs/evidence_files scopées via can_assigned_verifier_view_mrv_project() (point 6)',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='projects'
                  AND policyname='verifier_read_projects' AND qual ILIKE '%can_assigned_verifier_view_mrv_project(%' AND qual NOT ILIKE '%is_verifier()%')
        AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='project_activity_logs'
                  AND policyname='verifier_read_activity_logs' AND qual ILIKE '%can_assigned_verifier_view_mrv_project(%' AND qual NOT ILIKE '%is_verifier()%')
        AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='evidence_files'
                  AND policyname='verifier_read_evidence_files' AND qual ILIKE '%can_assigned_verifier_view_mrv_project(%' AND qual NOT ILIKE '%is_verifier()%'));
    -- Correctif vingt-troisième revue statique.
    PERFORM pg_temp.carbon_test_assert('A29', 'helpers anti-cycle RLS SECURITY DEFINER présents (point 1)',
        to_regprocedure('public.can_assigned_verifier_view_mrv_project(uuid)') IS NOT NULL
        AND to_regprocedure('public.can_client_view_verification_session(uuid)') IS NOT NULL);
    PERFORM pg_temp.carbon_test_assert('A30', 'trigger d''accréditation BEFORE INSERT OR UPDATE sur verification_sessions présent (point 2)',
        EXISTS (SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
                WHERE t.relname = 'verification_sessions' AND tg.tgname = 'verification_sessions_guard_verifier_accreditation'
                  -- Correctif exécution réelle : bug de test — bits pg_trigger.tgtype
                  -- (trigger.h) : TRIGGER_TYPE_INSERT=4, TRIGGER_TYPE_DELETE=8,
                  -- TRIGGER_TYPE_UPDATE=16. Le test vérifiait à tort le bit DELETE (8)
                  -- au lieu du bit UPDATE (16) pour un trigger BEFORE INSERT OR UPDATE.
                  AND tg.tgtype & 4 <> 0 AND tg.tgtype & 16 <> 0));
    PERFORM pg_temp.carbon_test_assert('A31', 'is_assigned_verifier() référence désormais is_authorized_verifier_identity() (point 3)',
        pg_get_functiondef('public.is_assigned_verifier(uuid)'::regprocedure) ILIKE '%is_authorized_verifier_identity(%');
    PERFORM pg_temp.carbon_test_assert('A32', 'complete_verification_session() revalide accredited_verifiers.active à la clôture (point 3)',
        pg_get_functiondef('public.complete_verification_session(uuid,numeric,numeric,uuid,text)'::regprocedure) ILIKE '%accredited_verifiers%'
        AND pg_get_functiondef('public.complete_verification_session(uuid,numeric,numeric,uuid,text)'::regprocedure) ILIKE '%FOR SHARE%');
    PERFORM pg_temp.carbon_test_assert('A33', 'trigger BEFORE INSERT verification_outcomes et RPC exigent file_hash (point 4)',
        pg_get_functiondef('public.carbon_guard_verification_outcome_insert()'::regprocedure) ILIKE '%file_hash%'
        AND pg_get_functiondef('public.complete_verification_session(uuid,numeric,numeric,uuid,text)'::regprocedure) ILIKE '%file_hash%');
    PERFORM pg_temp.carbon_test_assert('A34', 'gel supplémentaire verifier_org/verifier_contact/scope/report_url présent',
        pg_get_functiondef('public.carbon_guard_verification_session_update()'::regprocedure) ILIKE '%verifier_org%'
        AND pg_get_functiondef('public.carbon_guard_verification_session_update()'::regprocedure) ILIKE '%report_url%');
    PERFORM pg_temp.carbon_test_assert('A35', 'can_assigned_verifier_view_mrv_project() revalide l''accréditation active (correctif vingt-quatrième revue statique, point 1)',
        pg_get_functiondef('public.can_assigned_verifier_view_mrv_project(uuid)'::regprocedure) ILIKE '%is_authorized_verifier_identity(%');
    PERFORM pg_temp.carbon_test_assert('A36', 'carbon_guard_verification_outcome_insert() revalide l''accréditation active via FOR SHARE (correctif vingt-quatrième revue statique, point 2)',
        pg_get_functiondef('public.carbon_guard_verification_outcome_insert()'::regprocedure) ILIKE '%accredited_verifiers%'
        AND pg_get_functiondef('public.carbon_guard_verification_outcome_insert()'::regprocedure) ILIKE '%FOR SHARE%');
    PERFORM pg_temp.carbon_test_assert('A37', 'trigger d''accréditation limité à INSERT ou changement effectif de verifier_user_id (ajustement vingt-quatrième revue statique)',
        pg_get_functiondef('public.carbon_guard_verification_session_verifier_accreditation()'::regprocedure) ILIKE '%IS DISTINCT FROM OLD.verifier_user_id%');
    -- NOT ILIKE ciblé sur le motif d'APPEL réel ('...identity(NEW'), pas sur
    -- le simple nom de la fonction — les commentaires du trigger l'évoquent
    -- volontairement (justification du choix), un NOT ILIKE générique sur le
    -- nom seul aurait donc donné un faux échec.
    PERFORM pg_temp.carbon_test_assert('A38', 'garde d''accréditation verrouille directement accredited_verifiers (FOR SHARE) et n''appelle plus is_authorized_verifier_identity() (correctif vingt-cinquième revue statique, blocage 1)',
        pg_get_functiondef('public.carbon_guard_verification_session_verifier_accreditation()'::regprocedure) ILIKE '%accredited_verifiers%'
        AND pg_get_functiondef('public.carbon_guard_verification_session_verifier_accreditation()'::regprocedure) ILIKE '%FOR SHARE%'
        AND pg_get_functiondef('public.carbon_guard_verification_session_verifier_accreditation()'::regprocedure) NOT ILIKE '%is_authorized_verifier_identity(NEW%');
    -- Correctif vingt-cinquième revue statique (blocage 2) : clock_timestamp()
    -- doit apparaître TEXTUELLEMENT après le contrôle de racine ('un résultat
    -- racine', dernier contrôle substantiel avant l'affectation des
    -- timestamps, quelle que soit la branche IF/ELSE réellement empruntée à
    -- l'exécution) — position() sur le texte de pg_get_functiondef(), pas une
    -- exécution.
    PERFORM pg_temp.carbon_test_assert('A39', 'timestamps de verification_outcomes capturés en tout dernier lieu, après verrou preuve et contrôles de supersession (correctif vingt-cinquième revue statique, blocage 2)',
        position('clock_timestamp()' IN pg_get_functiondef('public.carbon_guard_verification_outcome_insert()'::regprocedure))
        > position('un résultat racine' IN pg_get_functiondef('public.carbon_guard_verification_outcome_insert()'::regprocedure)));
    -- Correctif vingt-sixième revue statique : SELECT/PERFORM ... FOR SHARE
    -- exige le privilège UPDATE et est soumis aux policies UPDATE (pas
    -- seulement SELECT) — accredited_verifiers ne porte qu'une policy
    -- SELECT et authenticated n'a pas UPDATE dessus. La garde
    -- d'accréditation DOIT donc être SECURITY DEFINER (prosecdef=true) pour
    -- que son verrou FOR SHARE fonctionne sous authenticated (B24nonies).
    PERFORM pg_temp.carbon_test_assert('A40', 'carbon_guard_verification_session_verifier_accreditation() est SECURITY DEFINER (correctif vingt-sixième revue statique — requis pour FOR SHARE sous authenticated)',
        (SELECT prosecdef FROM pg_proc WHERE oid = 'public.carbon_guard_verification_session_verifier_accreditation()'::regprocedure));
END $$;

-- ────────────────────────────────────────────────────────────
-- 2. FIXTURES
-- ────────────────────────────────────────────────────────────

-- Profils — RÉUTILISATION de 7 profils réels existants (voir en-tête ;
-- correctif vingtième revue statique : 6 -> 7, pour un second client
-- distinct). Créés AVANT les projets/sessions car client_id des projets en
-- dépend.
DO $$
DECLARE
    v_profile_ids UUID[];
BEGIN
    SELECT array_agg(id) INTO v_profile_ids
    FROM (SELECT id FROM public.profiles ORDER BY created_at LIMIT 7) sub;

    IF COALESCE(array_length(v_profile_ids, 1), 0) < 7 THEN
        RAISE EXCEPTION 'Fixtures impossibles : au moins 7 profils réels distincts sont requis dans public.profiles pour exécuter ce script (trouvés : %). Provisionner des comptes de test via l''API Auth de Supabase avant de relancer.', COALESCE(array_length(v_profile_ids, 1), 0);
    END IF;

    PERFORM set_config('carbon_test.profile_superadmin',       v_profile_ids[1]::text, false);
    PERFORM set_config('carbon_test.profile_verifier_assigned', v_profile_ids[2]::text, false);
    PERFORM set_config('carbon_test.profile_verifier_other',    v_profile_ids[3]::text, false);
    PERFORM set_config('carbon_test.profile_project_admin',     v_profile_ids[4]::text, false);
    PERFORM set_config('carbon_test.profile_project_client',    v_profile_ids[5]::text, false);
    PERFORM set_config('carbon_test.profile_outsider',          v_profile_ids[6]::text, false);
    PERFORM set_config('carbon_test.profile_client_b',          v_profile_ids[7]::text, false);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_profile(p_key TEXT) RETURNS UUID
LANGUAGE sql AS $$ SELECT current_setting('carbon_test.profile_' || p_key)::UUID $$;

-- Registre VVB — correctif vingt-deuxième revue statique (point 2), déplacé
-- ICI (avant TOUTE assignation de verifier_user_id, y compris directe) par
-- le correctif vingt-troisième revue statique (point 2) : le nouveau
-- trigger BEFORE INSERT OR UPDATE sur verification_sessions exige
-- désormais une accréditation active pour TOUT verifier_user_id non NULL,
-- quel que soit le chemin d'écriture — assigner verifier_assigned AVANT
-- cette accréditation (comme le faisait la version précédente de ce
-- fichier) échouerait désormais structurellement. SEUL verifier_assigned
-- est accrédité : profile_outsider (profil ordinaire) et profile_superadmin
-- (autoassignation) restent délibérément ABSENTS de ce registre, nécessaires
-- pour les tests négatifs B32bis/B32ter (section 9).
INSERT INTO public.accredited_verifiers (user_id, accredited_by)
VALUES (pg_temp.carbon_test_profile('verifier_assigned'), pg_temp.carbon_test_profile('superadmin'));

-- Projet A (client_id = profile_project_client) et projet B (client_id =
-- profile_client_b) — correctif vingtième revue statique (blocage 2), requis
-- pour distinguer les deux clients dans can_view_verification_outcome().
INSERT INTO public.projects (id, name, status, client_id)
VALUES
    ('33333333-3333-3333-3333-333333336001', 'TEST-05 Projet MRV A', 'active', pg_temp.carbon_test_profile('project_client')),
    ('33333333-3333-3333-3333-333333336002', 'TEST-05 Projet MRV B', 'active', pg_temp.carbon_test_profile('client_b'));

INSERT INTO public.verification_sessions (id, project_id, verifier_org, verifier_contact, status)
VALUES
    ('33333333-3333-3333-3333-333333337001', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337002', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337003', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337004', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    ('33333333-3333-3333-3333-333333337005', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    -- S6 : verifier_user_id assigné DIRECTEMENT dès les fixtures (bypass) —
    -- nécessaire pour tester B3 (« planned rencontré ») avec un appelant
    -- réellement autorisé, la dérogation superadmin ayant été retirée.
    ('33333333-3333-3333-3333-333333337006', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    -- S7 : session du projet B, utilisée UNIQUEMENT pour la RLS croisée
    -- Client A / Client B (section 8) — son résultat est inséré DIRECTEMENT
    -- ci-dessous, hors RPC, APRÈS transition explicite vers in_progress
    -- (correctif vingt-et-unième revue statique : le trigger BEFORE INSERT
    -- rejetterait sinon l'insertion, la session étant encore 'planned').
    ('33333333-3333-3333-3333-333333337007', '33333333-3333-3333-3333-333333336002', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    -- S8 : jamais touchée avant la section 9 — dédiée aux tests de
    -- plan_verification_session().
    ('33333333-3333-3333-3333-333333337008', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned'),
    -- S9 : correctif vingt-et-unième revue statique — in_progress, période
    -- juillet 2026, vérificateur assigné, JAMAIS dotée d'un résultat.
    -- Réutilisée par plusieurs tests négatifs indépendants (section 7bis) :
    -- chaque tentative échoue et est annulée par le savepoint implicite de
    -- carbon_test_assert_raises, donc son état (aucun résultat) reste
    -- constant tout au long du script.
    ('33333333-3333-3333-3333-333333337009', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'in_progress'),
    -- S10 : correctif vingt-et-unième revue statique — in_progress,
    -- vérificateur assigné, période NULL (délibérément absente).
    ('33333333-3333-3333-3333-333333337010', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'in_progress'),
    -- S11 : correctif vingt-cinquième revue statique (blocage 1) — dédiée à
    -- la démonstration du chemin POSITIF de la garde d'accréditation sous
    -- SET LOCAL ROLE authenticated (project_admin, RLS réelle) : jamais
    -- touchée ailleurs.
    ('33333333-3333-3333-3333-333333337011', '33333333-3333-3333-3333-333333336001', 'TEST-05 Cabinet', 'contact@test', 'planned');

UPDATE public.verification_sessions
SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned')
WHERE id = '33333333-3333-3333-3333-333333337006';

UPDATE public.verification_sessions
SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned'),
    reporting_period_start = '2026-07-01', reporting_period_end = '2026-07-31'
WHERE id = '33333333-3333-3333-3333-333333337009';

UPDATE public.verification_sessions
SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned')
WHERE id = '33333333-3333-3333-3333-333333337010';

-- Preuves de vérification — correctif vingt-et-unième revue statique
-- (blocage 5) : evidence_files (déjà scopée par project_id, chantier MRV),
-- PAS documents (aucune notion de projet MRV). Trois lignes : valide pour
-- le projet A, type incorrect pour le projet A, valide pour le projet B
-- (nécessaire pour S7, qui appartient au projet B).
-- Correctif vingt-troisième revue statique (point 4) : file_hash renseigné
-- DÈS LA CRÉATION pour doc_valid/doc_valid_b — le trigger de gel
-- (evidence_files_guard_update) interdit de le renseigner APRÈS coup une
-- fois la ligne référencée par un verification_outcomes ; sans hash dès le
-- départ, le mécanisme d'intégrité resterait définitivement vide.
-- doc_wrong_type reçoit également un hash (réalisme, jamais référencée par
-- un outcome de toute façon — rejetée pour son type).
INSERT INTO public.evidence_files (id, project_id, file_url, type, file_hash)
VALUES
    ('33333333-3333-3333-3333-333333339001', '33333333-3333-3333-3333-333333336001', '/evidence/test-05-rapport-valide-a.pdf', 'verification_report', 'sha256:test-05-a-0001'),
    ('33333333-3333-3333-3333-333333339002', '33333333-3333-3333-3333-333333336001', '/evidence/test-05-type-incorrect-a.pdf', 'other', 'sha256:test-05-a-0002'),
    ('33333333-3333-3333-3333-333333339003', '33333333-3333-3333-3333-333333336002', '/evidence/test-05-rapport-valide-b.pdf', 'verification_report', 'sha256:test-05-b-0003'),
    -- Correctif vingt-troisième revue statique (point 4) : type/projet
    -- corrects, mais file_hash NULL — dédiée au test Bdoc6 (RPC) et Btrig7
    -- (trigger), isolant précisément la nouvelle validation d'intégrité.
    ('33333333-3333-3333-3333-333333339004', '33333333-3333-3333-3333-333333336001', '/evidence/test-05-hash-manquant-a.pdf', 'verification_report', NULL);

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_doc(p_key TEXT) RETURNS UUID
LANGUAGE sql AS $$ SELECT current_setting('carbon_test.doc_' || p_key)::UUID $$;

DO $$
BEGIN
    PERFORM set_config('carbon_test.doc_valid', '33333333-3333-3333-3333-333333339001', false);
    PERFORM set_config('carbon_test.doc_wrong_type', '33333333-3333-3333-3333-333333339002', false);
    PERFORM set_config('carbon_test.doc_valid_b', '33333333-3333-3333-3333-333333339003', false);
    PERFORM set_config('carbon_test.doc_no_hash', '33333333-3333-3333-3333-333333339004', false);
END $$;

-- S7 : transition explicite vers in_progress (période + vérificateur)
-- AVANT l'insertion directe du résultat — correctif vingt-et-unième revue
-- statique, condition désormais imposée par le trigger BEFORE INSERT.
UPDATE public.verification_sessions
SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned'),
    reporting_period_start = '2026-07-01', reporting_period_end = '2026-07-31',
    status = 'in_progress'
WHERE id = '33333333-3333-3333-3333-333333337007';

-- Résultat du projet B (S7) — inséré DIRECTEMENT (pas via
-- complete_verification_session(), pour ne pas dupliquer sa logique déjà
-- testée par ailleurs) : sert uniquement à la RLS croisée Client A/Client B
-- (section 8). Preuve du PROJET B (doc_valid_b) — correctif vingt-et-unième
-- revue statique : la preuve du projet A aurait désormais été rejetée par
-- le trigger BEFORE INSERT (project_id ne correspondrait pas).
INSERT INTO public.verification_outcomes (id, verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
VALUES ('33333333-3333-3333-3333-333333339500', '33333333-3333-3333-3333-333333337007', 1, 1, 1, pg_temp.carbon_test_doc('valid_b'), pg_temp.carbon_test_profile('verifier_assigned'));

-- Correctif vingt-deuxième revue statique (point 3) : S7 doit être
-- 'completed' pour satisfaire l'invariant différé (« toute session ayant
-- des outcomes doit être completed avec exactement un actif ») — omis par
-- erreur lors de la refonte de la vingt-et-unième revue statique (S7 était
-- restée 'in_progress' malgré son résultat actif).
UPDATE public.verification_sessions SET status = 'completed'
WHERE id = '33333333-3333-3333-3333-333333337007';

DO $$
BEGIN
    PERFORM set_config('carbon_test.outcome_s7', '33333333-3333-3333-3333-333333339500', false);
END $$;

-- S1 (période janvier 2026) : assignation directe du vérificateur (bypass
-- RLS/trigger de garde, rôle propriétaire des tables — fixture de test, pas
-- un appel à plan_verification_session()) puis passage à in_progress.
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
    -- Correctif vingt-et-unième revue statique (blocage 1) : recherche,
    -- autorisation et verrou désormais fusionnés dans un seul SELECT — le
    -- message est devenu générique (« Session introuvable ou accès
    -- refusé. ») pour ne plus distinguer un appelant non autorisé d'une
    -- session inexistante (voir B2ter ci-dessous pour la démonstration
    -- directe anti-énumération).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B2', 'complete_verification_session() rejette un appelant authentifié ni vérificateur assigné ni super-admin (message générique)',
        format($sql$SELECT public.complete_verification_session(%L, 4, 4, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337001'),
        'Session introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_msg_real TEXT;
    v_msg_fake TEXT;
BEGIN
    -- Correctif vingt-et-unième revue statique (blocage 1, demande
    -- explicite) : démonstration DIRECTE que le message est rigoureusement
    -- IDENTIQUE entre une session réelle mais inaccessible (S1, existe,
    -- outsider non autorisé) et un UUID totalement inexistant — élimine
    -- toute possibilité d'énumération des identifiants de session réels par
    -- observation du message d'erreur.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    BEGIN
        PERFORM public.complete_verification_session('33333333-3333-3333-3333-333333337001', 1, 1, pg_temp.carbon_test_doc('valid'), NULL);
        v_msg_real := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg_real := SQLERRM;
    END;
    BEGIN
        PERFORM public.complete_verification_session(gen_random_uuid(), 1, 1, pg_temp.carbon_test_doc('valid'), NULL);
        v_msg_fake := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg_fake := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B2ter', 'complete_verification_session() : message rigoureusement identique entre session réelle-mais-inaccessible et UUID inexistant (anti-énumération)',
        v_msg_real IS NOT NULL AND v_msg_real = v_msg_fake AND v_msg_real = 'Session introuvable ou accès refusé.',
        format('réel=%s ; inexistant=%s', v_msg_real, v_msg_fake));
END $$;

DO $$
BEGIN
    -- S6 : status encore 'planned' à ce stade, MAIS verifier_user_id déjà
    -- assigné directement dans les fixtures (correctif vingtième revue
    -- statique : la dérogation superadmin ayant été retirée, seul
    -- l'appelant réellement autorisé — le vérificateur assigné — peut
    -- désormais atteindre le check « planned rencontré »).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B3', 'complete_verification_session() rejette une session encore planned (appelant autorisé : vérificateur assigné)',
        format($sql$SELECT public.complete_verification_session(%L, 4, 4, %L, NULL)$sql$, '33333333-3333-3333-3333-333333337006', current_setting('carbon_test.doc_valid', true)),
        'planned rencontré');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    -- S2 : in_progress, période renseignée, verifier_user_id NULL —
    -- correctif vingtième revue statique (blocage 4, dérogation superadmin
    -- retirée) : is_assigned_verifier() ne peut être vraie pour AUCUN
    -- appelant, y compris le super-admin, tant que verifier_user_id est
    -- NULL — le rejet se produit désormais TOUJOURS à l'autorisation
    -- (« Accès refusé »), le check interne « aucun vérificateur assigné »
    -- étant devenu structurellement inatteignable et retiré de la RPC.
    -- Correctif vingt-et-unième revue statique : verifier_user_id NULL ne
    -- peut JAMAIS égaler auth.uid() (même celui du super-admin) — le SELECT
    -- fusionné ne trouve donc aucune ligne, message générique désormais
    -- (plus « Accès refusé » distinct).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B4', 'complete_verification_session() rejette même le super-admin sur une session sans vérificateur assigné (message générique, pas de dérogation)',
        format($sql$SELECT public.complete_verification_session(%L, 4, 4, NULL, NULL)$sql$, '33333333-3333-3333-3333-333333337002'),
        'Session introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    -- Correctif vingtième revue statique (blocage 4) — régression directe :
    -- S3 a déjà un vérificateur assigné (verifier_assigned, réel) et est
    -- in_progress avec période renseignée (prête à être complétée en
    -- section 6) — un super-admin ne doit PLUS pouvoir se substituer à lui.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B4bis', 'complete_verification_session() rejette le super-admin même quand un vérificateur EST assigné (dérogation retirée, message générique)',
        format($sql$SELECT public.complete_verification_session(%L, 2, 2, %L, 'tentative superadmin')$sql$,
               '33333333-3333-3333-3333-333333337003', current_setting('carbon_test.doc_valid', true)),
        'Session introuvable ou accès refusé');
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
    v_outcome_id := public.complete_verification_session('33333333-3333-3333-3333-333333337001', 4, 4, pg_temp.carbon_test_doc('valid'), NULL);
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
        format($sql$SELECT public.complete_verification_session(%L, 5, 5, %L, NULL)$sql$, '33333333-3333-3333-3333-333333337001', current_setting('carbon_test.doc_valid', true)),
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
    v_outcome_id := public.complete_verification_session('33333333-3333-3333-3333-333333337001', 5, 5, pg_temp.carbon_test_doc('valid'), 'Correction test B11');
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
        format($sql$SELECT public.complete_verification_session(%L, 2, 2, %L, NULL)$sql$, '33333333-3333-3333-3333-333333337003', current_setting('carbon_test.doc_valid', true)),
        'diverge de plus de 1%');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_outcome_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    v_outcome_id := public.complete_verification_session('33333333-3333-3333-3333-333333337003', 2, 2, pg_temp.carbon_test_doc('valid'), 'Écart justifié test B15');
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
-- 6bis. SEUIL 1%% — CAS CALCULÉ = 0 (S4) — correctif vingtième revue statique
--    (blocage 3). S4 n'a AUCUNE activité journalisée (calculated = 0) ;
--    avant correction, un verified_reduction_tco2e non nul passait sans
--    adjustment_reason dans ce cas précis.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B18bis', 'calculé=0 et vérifié<>0 SANS adjustment_reason rejeté (correctif vingtième revue statique)',
        format($sql$SELECT public.complete_verification_session(%L, 5, 5, %L, NULL)$sql$, '33333333-3333-3333-3333-333333337004', current_setting('carbon_test.doc_valid', true)),
        'aucune activité calculée');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_outcome_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    v_outcome_id := public.complete_verification_session('33333333-3333-3333-3333-333333337004', 5, 5, pg_temp.carbon_test_doc('valid'), 'Ajustement test zéro B18ter');
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B18ter', 'calculé=0 et vérifié<>0 AVEC adjustment_reason réussit',
        v_outcome_id IS NOT NULL);
END $$;

-- ────────────────────────────────────────────────────────────
-- 6ter. PREUVE DE VÉRIFICATION OBLIGATOIRE (§12, correctif vingtième revue
--    statique, blocage 5 — poussé plus loin en vingt-et-unième revue
--    statique : evidence_files scopée par projet, PAS documents) — S4 a
--    désormais un résultat actif (B18ter) : ces tests exercent la
--    supersession, la validation de la preuve se produisant AVANT le check
--    adjustment_reason (peu importe donc que la raison soit fournie ou non
--    pour isoler la validation de la preuve).
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('Bdoc1', 'verification_report_document_id NULL rejeté (obligatoire)',
        format($sql$SELECT public.complete_verification_session(%L, 5, 5, NULL, 'peu importe')$sql$, '33333333-3333-3333-3333-333333337004'),
        'obligatoire');
    PERFORM pg_temp.carbon_test_assert_raises('Bdoc2', 'verification_report_document_id inexistant rejeté (evidence_files)',
        format($sql$SELECT public.complete_verification_session(%L, 5, 5, gen_random_uuid(), 'peu importe')$sql$, '33333333-3333-3333-3333-333333337004'),
        'aucune preuve');
    PERFORM pg_temp.carbon_test_assert_raises('Bdoc3', 'verification_report_document_id de type incorrect rejeté (evidence_files.type)',
        format($sql$SELECT public.complete_verification_session(%L, 5, 5, %L, 'peu importe')$sql$, '33333333-3333-3333-3333-333333337004', current_setting('carbon_test.doc_wrong_type', true)),
        'porter le type');
    -- Correctif vingt-et-unième revue statique (blocage 5, demande
    -- explicite) : la preuve doit appartenir au MÊME projet MRV que la
    -- session — doc_valid_b (evidence_files.project_id = projet B) utilisée
    -- ici sur S4 (session du projet A) doit être rejetée.
    PERFORM pg_temp.carbon_test_assert_raises('Bdoc5', 'preuve valide mais appartenant à un AUTRE projet MRV rejetée (blocage 5)',
        format($sql$SELECT public.complete_verification_session(%L, 5, 5, %L, 'peu importe')$sql$, '33333333-3333-3333-3333-333333337004', current_setting('carbon_test.doc_valid_b', true)),
        'même projet MRV');
    -- Correctif vingt-troisième revue statique (point 4) : type et projet
    -- corrects, mais file_hash NULL — le mécanisme d'intégrité doit
    -- bloquer AVANT que la preuve puisse servir, pas seulement une fois
    -- référencée (où elle deviendrait gelée, donc définitivement vide).
    PERFORM pg_temp.carbon_test_assert_raises('Bdoc6', 'preuve valide (type/projet corrects) mais file_hash NULL rejetée (point 4)',
        format($sql$SELECT public.complete_verification_session(%L, 5, 5, %L, 'peu importe')$sql$, '33333333-3333-3333-3333-333333337004', current_setting('carbon_test.doc_no_hash', true)),
        'file_hash renseigné');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_outcome_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    v_outcome_id := public.complete_verification_session('33333333-3333-3333-3333-333333337004', 6, 6, pg_temp.carbon_test_doc('valid'), 'Correction test Bdoc4');
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('Bdoc4', 'supersession avec preuve valide (type correct, même projet) réussit',
        v_outcome_id IS NOT NULL);
END $$;

-- ────────────────────────────────────────────────────────────
-- 6quater. GEL DES PROPRIÉTÉS CRITIQUES D'evidence_files RÉFÉRENCÉE —
--    correctif vingt-deuxième revue statique (point 5). doc_valid (evidence
--    '...339001') est à ce stade référencée par plusieurs verification_outcomes
--    (S1 et S4) — cible réelle pour isoler le trigger evidence_files_guard_update.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('Bevi1', 'UPDATE direct : type d''une preuve déjà référencée par un verification_outcomes rejeté (gel)',
        format($sql$UPDATE public.evidence_files SET type = 'other' WHERE id = %L$sql$, current_setting('carbon_test.doc_valid', true)),
        'sont immuables dès que cette preuve est référencée');
    PERFORM pg_temp.carbon_test_assert_raises('Bevi2', 'UPDATE direct : project_id d''une preuve déjà référencée rejeté (gel)',
        format($sql$UPDATE public.evidence_files SET project_id = %L WHERE id = %L$sql$,
               '33333333-3333-3333-3333-333333336002', current_setting('carbon_test.doc_valid', true)),
        'sont immuables dès que cette preuve est référencée');
    PERFORM pg_temp.carbon_test_assert_raises('Bevi3', 'UPDATE direct : file_hash d''une preuve déjà référencée rejeté (gel)',
        format($sql$UPDATE public.evidence_files SET file_hash = 'deadbeef' WHERE id = %L$sql$, current_setting('carbon_test.doc_valid', true)),
        'sont immuables dès que cette preuve est référencée');
END $$;

DO $$
DECLARE
    v_updated_count INT;
BEGIN
    -- Colonne NON critique (gps) : librement modifiable malgré la
    -- référence — démontre la précision du gel (pas un blocage total de la
    -- ligne).
    UPDATE public.evidence_files SET gps = jsonb_build_object('lat', 45.5, 'lng', -73.6)
    WHERE id = current_setting('carbon_test.doc_valid', true)::UUID;
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    PERFORM pg_temp.carbon_test_assert('Bevi4', 'UPDATE direct : colonne non critique (gps) reste modifiable malgré la référence',
        v_updated_count = 1, v_updated_count::text);
END $$;

-- ────────────────────────────────────────────────────────────
-- 7. STRUCTUREL — CHECK completed, EXCLUDE périodes, garde UPDATE, DELETE,
--    doublon actif par INSERT direct, protection de la chaîne de
--    supersession (correctif vingtième revue statique, blocage 6).
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    -- Correctif vingt-deuxième revue statique (point 1) : l'ancien B19
    -- (UPDATE direct de S6 vers completed) atteint désormais D'ABORD le
    -- trigger de garde de session (verification_sessions_guard_update,
    -- blocage 3, 21e revue statique — S6 n'a aucun outcome), AVANT même que
    -- le CHECK visé ne soit évalué. Le CHECK
    -- verification_sessions_completed_requires_period_and_verifier
    -- s'applique aussi bien à l'INSERT qu'à l'UPDATE (contrainte de table
    -- ordinaire) — un INSERT dédié d'une session TOUTE NEUVE en
    -- status='completed' l'atteint directement, sans jamais passer par le
    -- trigger BEFORE UPDATE (qui ne fire que sur UPDATE).
    PERFORM pg_temp.carbon_test_assert_raises('B19', 'INSERT direct : nouvelle session status=completed sans période/vérificateur rejetée (CHECK, sans passer par le trigger de garde UPDATE)',
        format($sql$INSERT INTO public.verification_sessions (project_id, verifier_org, verifier_contact, status) VALUES (%L, 'TEST-05 Cabinet', 'contact@test', 'completed')$sql$,
               '33333333-3333-3333-3333-333333336001'),
        'verification_sessions_completed_requires_period_and_verifier');
END $$;

DO $$
BEGIN
    -- Correctif vingt-deuxième revue statique (point 1) : l'ancien B20
    -- (UPDATE direct vers completed sans résultat) échouait D'ABORD au
    -- trigger de garde (blocage 3), jamais à l'EXCLUDE visé. Fix : S5
    -- transitionne à in_progress (période 15-20 janvier, chevauchant S1,
    -- déjà completed) puis complete_verification_session() est appelée
    -- directement — elle insère l'outcome PUIS tente elle-même l'UPDATE
    -- vers completed (même séquence que le chemin légitime), qui échoue à
    -- l'EXCLUDE. Toute la préparation (l'INSERT de l'outcome) est annulée
    -- avec l'échec par le savepoint implicite de carbon_test_assert_raises
    -- — S5 ne conserve aucun résultat après ce test.
    UPDATE public.verification_sessions
    SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned'),
        reporting_period_start = '2026-01-15', reporting_period_end = '2026-01-20',
        status = 'in_progress'
    WHERE id = '33333333-3333-3333-3333-333333337005';

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B20', 'complete_verification_session() : complétion chevauchant une autre session completed du même projet rejetée (EXCLUDE, préparation entièrement annulée)',
        format($sql$SELECT public.complete_verification_session(%L, 1, 1, %L, 'Divergence test B20')$sql$,
               '33333333-3333-3333-3333-333333337005', current_setting('carbon_test.doc_valid', true)),
        'verification_sessions_no_overlapping_completed_periods');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    -- Correctif vingt-et-unième revue statique (blocage 4) — B21 redessiné :
    -- le trigger BEFORE INSERT (verification_outcomes_guard_insert)
    -- interdit désormais toute insertion explicite en status<>'active' AVANT
    -- même d'atteindre les index uniques partiels sous-jacents (toujours en
    -- place comme filet redondant, voir A3/A19/A20) — un résultat ne peut
    -- jamais naître déjà superseded, quel que soit le chemin d'écriture.
    PERFORM pg_temp.carbon_test_assert_raises('B21', 'INSERT direct : status=''superseded'' explicite à l''insertion rejeté (trigger, insertion uniquement active)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 'superseded', 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337001', current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'jamais être inséré déjà superseded');
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
-- 7bis. GARDE STRUCTURELLE BEFORE INSERT (verification_outcomes_guard_insert)
--    — correctif vingt-et-unième revue statique (blocage 4). Six tests
--    directs isolant chacun EXACTEMENT une des validations structurelles du
--    trigger, indépendamment de complete_verification_session(). S9/S10/S6/S2
--    sont réutilisées ici sans jamais recevoir de résultat persistant :
--    chaque INSERT échoue et est annulé par le savepoint implicite de
--    carbon_test_assert_raises.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('Btrig1', 'INSERT direct : verification_session_id inexistant rejeté (trigger)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               gen_random_uuid(), current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'ne correspond à aucune session existante');

    -- S6 : encore 'planned' (jamais transitionnée, B3/B19 échouent tous deux).
    PERFORM pg_temp.carbon_test_assert_raises('Btrig2', 'INSERT direct : session encore planned rejetée (trigger)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337006', current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'planned rencontré');

    -- S10 : in_progress, vérificateur assigné, période NULL.
    PERFORM pg_temp.carbon_test_assert_raises('Btrig3', 'INSERT direct : période manquante sur la session rejetée (trigger)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337010', current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'doit avoir une période renseignée');

    -- S2 : in_progress, période renseignée, verifier_user_id NULL.
    PERFORM pg_temp.carbon_test_assert_raises('Btrig4', 'INSERT direct : vérificateur non assigné sur la session rejeté (trigger)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337002', current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'doit avoir un vérificateur assigné');

    -- S9 : in_progress, période/vérificateur renseignés — verified_by fourni
    -- NE correspond PAS au vérificateur assigné (verifier_other au lieu de
    -- verifier_assigned).
    PERFORM pg_temp.carbon_test_assert_raises('Btrig5', 'INSERT direct : verified_by ne correspondant pas au vérificateur assigné rejeté (trigger)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337009', current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_other')),
        'verified_by doit être le vérificateur assigné');

    -- S9 : mêmes fixtures, verified_by correct cette fois, mais preuve de
    -- type incorrect — démontre que le trigger revalide structurellement la
    -- preuve indépendamment de complete_verification_session() (déjà
    -- démontré côté RPC par Bdoc1-Bdoc5).
    PERFORM pg_temp.carbon_test_assert_raises('Btrig6', 'INSERT direct : preuve de type incorrect rejetée (trigger, indépendant de la RPC)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337009', current_setting('carbon_test.doc_wrong_type', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'appartenant au même projet MRV');

    -- Correctif vingt-troisième revue statique (point 4) : preuve valide
    -- (type/projet corrects) mais file_hash NULL — le trigger la revalide
    -- structurellement, indépendamment de la RPC (déjà démontré côté RPC
    -- par Bdoc6).
    PERFORM pg_temp.carbon_test_assert_raises('Btrig7', 'INSERT direct : preuve avec file_hash NULL rejetée (trigger, point 4)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337009', current_setting('carbon_test.doc_no_hash', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'appartenant au même projet MRV');
END $$;

-- ────────────────────────────────────────────────────────────
-- 7ter. PROTECTION STRUCTURELLE DE LA CHAÎNE DE SUPERSESSION — correctif
--    vingtième revue statique (blocage 6), redessiné en vingt-et-unième
--    revue statique (blocage 4) : le trigger BEFORE INSERT interdisant
--    désormais toute insertion en status<>'active', l'ancien procédé
--    (status='superseded' explicite pour éviter idx_verification_outcomes_
--    one_active_per_session) n'est plus applicable — chaque test cible
--    désormais un scénario RÉEL où status='active' (valeur par défaut)
--    n'entre en conflit avec AUCUN autre invariant que celui visé :
--      • B24bis (auto-référence) : le trigger rejette AVANT même de
--        tenter l'INSERT — aucun conflit possible avec l'index actif.
--      • B24ter (inter-session) : cible S9, qui n'a encore AUCUN résultat
--        — l'index actif ne peut donc pas interférer.
--      • B24quater (fork) et B24quinquies (racine dupliquée) : ciblent S1,
--        dont le résultat actif (outcome_s1_v2) est d'abord DÉMOTÉ en
--        superseded par une transition légitime (active -> superseded,
--        déjà autorisée par le trigger de garde UPDATE) — libère
--        idx_verification_outcomes_one_active_per_session pour isoler
--        précisément l'index/le check visé par chacun des deux tests.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B24bis', 'INSERT direct : auto-référence (supersedes_outcome_id = id) rejetée (trigger, avant même le CHECK)',
        format($sql$
            WITH new_id AS (SELECT gen_random_uuid() AS id)
            INSERT INTO public.verification_outcomes (id, verification_session_id, supersedes_outcome_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
            SELECT id, %L, id, 1, 1, 1, %L, %L FROM new_id
        $sql$, '33333333-3333-3333-3333-333333337001', current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'ne peut pas référencer le résultat lui-même');
END $$;

-- Démotion légitime du résultat actif de S1 (active -> superseded, seule
-- transition permise par le trigger de garde UPDATE) — libère l'index actif
-- pour isoler précisément fork/racine-dupliquée ci-dessous. B22/B23/B24
-- (section 7) ont déjà exercé outcome_s1_v2 à l'état 'active' avant cette
-- démotion — aucune régression sur ces tests, déjà exécutés plus haut.
-- Correctif exécution réelle : ce bloc DOIT précéder B24ter (déplacé —
-- auparavant après), pas seulement B24quater/quinquies. outcome_s1_v1 est
-- déjà consommé par outcome_s1_v2 (idx_verification_outcomes_supersedes_once)
-- depuis la supersession B11 : cibler outcome_s1_v1 dans B24ter heurtait cet
-- index anti-fork AVANT même d'atteindre la contrainte FK composite
-- (verification_outcomes_supersedes_same_session) réellement visée par ce
-- test. outcome_s1_v2, tout juste démoté ici et pas encore consommé par
-- quiconque, isole correctement la contrainte FK.
UPDATE public.verification_outcomes SET status = 'superseded'
WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;

DO $$
BEGIN
    -- S9 : in_progress, période/vérificateur renseignés, AUCUN résultat
    -- encore — cible réelle et cohérente (même projet A que S1), le
    -- trigger valide donc tout jusqu'à la contrainte visée : le résultat
    -- référencé (outcome_s1_v2, réel, tout juste démoté en superseded
    -- ci-dessus, pas encore consommé par idx_verification_outcomes_supersedes_once)
    -- appartient à S1, pas à S9.
    PERFORM pg_temp.carbon_test_assert_raises('B24ter', 'INSERT direct : supersession INTER-SESSION (supersedes_outcome_id d''une autre session) rejetée (FK composite)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, supersedes_outcome_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by, adjustment_reason) VALUES (%L, %L, 1, 1, 1, %L, %L, 'test B24ter')$sql$,
               '33333333-3333-3333-3333-333333337009', current_setting('carbon_test.outcome_s1_v2', true),
               current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'verification_outcomes_supersedes_same_session');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B24quater', 'INSERT direct : fork (deux résultats prétendant remplacer le même ancien) rejeté (index unique partiel)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, supersedes_outcome_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by, adjustment_reason) VALUES (%L, %L, 1, 1, 1, %L, %L, 'test B24quater')$sql$,
               '33333333-3333-3333-3333-333333337001', current_setting('carbon_test.outcome_s1_v1', true),
               current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'idx_verification_outcomes_supersedes_once');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B24quinquies', 'INSERT direct : seconde racine (supersedes_outcome_id NULL) pour une session qui a déjà un historique rejetée (trigger, avant même l''index unique partiel)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337001',
               current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'ne peut être inséré que si aucun résultat');
END $$;

-- Restauration légitime de S1 (INSERT direct, supersède outcome_s1_v2 —
-- désormais superseded depuis la démotion précédant B24quater) — correctif
-- vingt-deuxième revue statique (point 3) : NÉCESSAIRE pour que S1 (status
-- completed) redevienne conforme à l'invariant différé (« exactement un
-- résultat actif ») avant toute évaluation forcée ultérieure (SET
-- CONSTRAINTS ... IMMEDIATE, section 7quinquies) — sans cette restauration,
-- l'événement différé encore en attente pour la démotion de outcome_s1_v2
-- (jamais explicitement vérifié depuis) referait surface au premier
-- contrôle forcé du même nom de contrainte, même pour une session sans
-- rapport. La fonction de contrôle relit l'état COURANT (pas OLD/NEW) : dès
-- que S1 redevient valide, tout événement en attente pour S1 (ancien ou
-- nouveau) passera silencieusement.
DO $$
DECLARE
    v_outcome_id UUID;
BEGIN
    INSERT INTO public.verification_outcomes (verification_session_id, supersedes_outcome_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by, adjustment_reason)
    VALUES ('33333333-3333-3333-3333-333333337001', current_setting('carbon_test.outcome_s1_v2', true)::UUID, 1, 1, 1, current_setting('carbon_test.doc_valid', true)::UUID, pg_temp.carbon_test_profile('verifier_assigned'), 'Restauration fixture après démotion (point 3)')
    RETURNING id INTO v_outcome_id;
    PERFORM set_config('carbon_test.outcome_s1_v3', v_outcome_id::text, false);
END $$;

-- ────────────────────────────────────────────────────────────
-- 7quater. TRANSITION completed SANS verification_outcome — correctif
--    vingt-et-unième revue statique (blocage 3). S9 (in_progress, période/
--    vérificateur renseignés) n'a reçu AUCUN résultat persistant à ce stade
--    (tous les INSERT tentés ci-dessus ont échoué et été annulés) — le
--    chemin légitime (complete_verification_session()) insère toujours
--    l'outcome AVANT cette UPDATE de statut ; une UPDATE directe qui
--    tenterait de court-circuiter cet ordre est désormais rejetée
--    structurellement, indépendamment de toute policy RLS.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B24sexies', 'UPDATE direct : transition vers completed refusée tant qu''aucun verification_outcome n''existe (blocage 3)',
        format($sql$UPDATE public.verification_sessions SET status = 'completed' WHERE id = %L$sql$,
               '33333333-3333-3333-3333-333333337009'),
        'aucun verification_outcome');
END $$;

-- ────────────────────────────────────────────────────────────
-- 7quater-bis. GARDE D'ACCRÉDITATION SUR verification_sessions — correctif
--    vingt-troisième revue statique (point 2). Démontre que le trigger
--    BEFORE INSERT OR UPDATE (verification_sessions_guard_verifier_
--    accreditation) ferme le contournement à la fois pour un INSERT direct
--    d'une session TOUTE NEUVE, et pour un UPDATE direct sur S10 (déjà
--    dotée d'un vérificateur accrédité) — indépendamment de
--    plan_verification_session(), déjà testée séparément côté RPC par
--    B32bis/B32ter. Les deux tentatives échouent et sont annulées par le
--    savepoint implicite de carbon_test_assert_raises : S10 reste inchangée
--    (verifier_user_id = verifier_assigned, période NULL) pour la suite.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B24septies', 'INSERT direct : nouvelle session avec verifier_user_id non accrédité rejetée (trigger, point 2)',
        format($sql$INSERT INTO public.verification_sessions (id, project_id, verifier_org, verifier_contact, status, verifier_user_id) VALUES (%L, %L, 'TEST-05 Cabinet', 'contact@test', 'planned', %L)$sql$,
               '33333333-3333-3333-3333-333333337011', '33333333-3333-3333-3333-333333336001', pg_temp.carbon_test_profile('outsider')),
        'identité de vérificateur accréditée');
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B24octies', 'UPDATE direct : réassignation de verifier_user_id vers un profil non accrédité rejetée (trigger, point 2)',
        format($sql$UPDATE public.verification_sessions SET verifier_user_id = %L WHERE id = %L$sql$,
               pg_temp.carbon_test_profile('outsider'), '33333333-3333-3333-3333-333333337010'),
        'identité de vérificateur accréditée');
END $$;

-- Correctif vingt-cinquième revue statique (blocage 1, contre-épreuve
-- POSITIVE) : la garde d'accréditation appelait auparavant
-- is_authorized_verifier_identity(), dont l'EXECUTE est volontairement
-- révoqué à authenticated — invisible avec les tests précédents (B24septies/
-- octies, B36/B37…), tous exécutés comme PROPRIÉTAIRE de la migration (donc
-- non soumis aux GRANT/REVOKE), jamais sous SET LOCAL ROLE authenticated.
-- Ce test reproduit le chemin RÉEL (project_admin, RLS authentique) : un
-- admin MRV légitime assignant un vérificateur ACCRÉDITÉ devait échouer
-- avec "permission denied for function is_authorized_verifier_identity"
-- AVANT le correctif — désormais la garde verrouille directement
-- accredited_verifiers (lisible par authenticated), sans dépendance à cette
-- fonction interne. S11 : jamais touchée ailleurs.
DO $$
DECLARE
    v_verifier_after UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('project_admin'), 'project_admin');
    SET LOCAL ROLE authenticated;
    UPDATE public.verification_sessions SET verifier_user_id = pg_temp.carbon_test_profile('verifier_assigned')
    WHERE id = '33333333-3333-3333-3333-333333337011';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT verifier_user_id INTO v_verifier_after FROM public.verification_sessions WHERE id = '33333333-3333-3333-3333-333333337011';
    PERFORM pg_temp.carbon_test_assert('B24nonies', 'UPDATE direct sous RLS authentique (authenticated, project_admin) : vérificateur ACCRÉDITÉ accepté, sans "permission denied" (blocage 1, contre-épreuve positive)',
        v_verifier_after = pg_temp.carbon_test_profile('verifier_assigned'), v_verifier_after::text);
END $$;

-- ────────────────────────────────────────────────────────────
-- 7quinquies. INVARIANT DIFFÉRÉ session <-> outcome — correctif
--    vingt-deuxième revue statique (point 3). Les deux CONSTRAINT TRIGGER
--    DEFERRABLE INITIALLY DEFERRED (voir A26) ne sont vérifiés qu'à la
--    validation de la transaction, ou plus tôt sur demande explicite via
--    SET CONSTRAINTS ... IMMEDIATE — technique employée ici pour forcer
--    l'évaluation SANS jamais valider (COMMIT) la transaction globale du
--    script. Chaque test viole l'invariant PUIS force le contrôle DANS un
--    bloc BEGIN/EXCEPTION imbriqué : le savepoint implicite de PL/pgSQL
--    annule automatiquement la violation (et l'événement différé qu'elle a
--    mis en file) dès que l'exception est interceptée — aucune restauration
--    manuelle n'est nécessaire après ces deux tests, contrairement à la
--    démotion persistante de outcome_s1_v2 plus haut (dont l'usage exigeait
--    au contraire que l'état survive à PLUSIEURS instructions).
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_msg TEXT;
BEGIN
    -- S1 (completed, invariant actuellement satisfait par outcome_s1_v3,
    -- restauré ci-dessus) : démotion temporaire de l'actif courant — plus
    -- AUCUN résultat actif pour une session completed, violation directe de
    -- « completed => exactement un actif ».
    BEGIN
        UPDATE public.verification_outcomes SET status = 'superseded'
        WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v3', true), '')::UUID;
        SET CONSTRAINTS verification_outcomes_check_session_invariant, verification_sessions_check_outcome_invariant IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('Binv1', 'invariant différé : session completed sans aucun résultat actif rejetée au contrôle forcé (SET CONSTRAINTS IMMEDIATE)',
        v_msg IS NOT NULL AND v_msg ILIKE '%completed%' AND v_msg ILIKE '%actif%', v_msg);
END $$;

DO $$
DECLARE
    v_msg TEXT;
BEGIN
    -- S9 (in_progress, période/vérificateur renseignés, toujours SANS aucun
    -- résultat à ce stade — voir commentaire section 7bis) : INSERT direct
    -- d'un résultat valide (passe le trigger BEFORE INSERT, qui n'exige que
    -- status<>'planned', PAS status='completed') alors que la session reste
    -- 'in_progress' — violation directe de « un résultat implique
    -- completed ».
    BEGIN
        INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
        VALUES ('33333333-3333-3333-3333-333333337009', 1, 1, 1, current_setting('carbon_test.doc_valid', true)::UUID, pg_temp.carbon_test_profile('verifier_assigned'));
        SET CONSTRAINTS verification_outcomes_check_session_invariant, verification_sessions_check_outcome_invariant IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('Binv2', 'invariant différé : résultat inséré pour une session encore in_progress rejeté au contrôle forcé (SET CONSTRAINTS IMMEDIATE)',
        v_msg IS NOT NULL AND v_msg ILIKE '%n''est pas completed%', v_msg);
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

-- Correctif vingtième revue statique (blocage 2) : is_project_client() seul
-- donnait accès à TOUS les résultats à quiconque porte ce rôle générique.
-- B26/B26bis/B26ter/B26quater démontrent désormais la relation RÉELLE
-- projects.client_id = auth.uid() — Client A (project_client) ne voit QUE le
-- projet A, Client B (client_b) ne voit QUE le projet B. carbon_test_set_actor()
-- (pas _set_actor_role()) suffit ici : seul le claim standard 'sub' est
-- nécessaire, plus aucune dépendance à un rôle JWT synthétique pour ce test.
DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('project_client'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B26', 'RLS : Client A (projects.client_id = auth.uid()) voit le résultat de SON projet (A)',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('project_client'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s7', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B26bis', 'RLS : Client A NE voit PAS le résultat du projet B (autre client)',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('client_b'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s7', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B26ter', 'RLS : Client B (projects.client_id = auth.uid()) voit le résultat de SON projet (B)',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('client_b'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B26quater', 'RLS : Client B NE voit PAS le résultat du projet A (autre client)',
        v_count = 0, v_count::text);
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
-- 8bis. RLS verifier_read_projects/activity_logs/evidence_files — correctif
--    vingt-deuxième revue statique (point 6). verifier_assigned est affecté
--    à S1 (projet A, verification_sessions.verifier_user_id = auth.uid()) ;
--    verifier_other n'est affecté à AUCUNE session — démontre le scoping
--    réel (plus is_verifier() générique) sur les trois tables.
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.projects WHERE id = '33333333-3333-3333-3333-333333336001';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B40', 'RLS projects : vérificateur affecté (via verification_sessions) voit le projet A',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('verifier_other'), 'verifier');
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.projects WHERE id = '33333333-3333-3333-3333-333333336001';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B41', 'RLS projects : vérificateur NON affecté (rôle générique verifier) NE voit PAS le projet A',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.project_activity_logs WHERE id = '33333333-3333-3333-3333-333333338001';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B42', 'RLS project_activity_logs : vérificateur affecté voit le journal du projet A',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('verifier_other'), 'verifier');
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.project_activity_logs WHERE id = '33333333-3333-3333-3333-333333338001';
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B43', 'RLS project_activity_logs : vérificateur NON affecté NE voit PAS le journal du projet A',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.evidence_files WHERE id = current_setting('carbon_test.doc_valid', true)::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B44', 'RLS evidence_files : vérificateur affecté voit la preuve du projet A',
        v_count = 1, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('verifier_other'), 'verifier');
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.evidence_files WHERE id = current_setting('carbon_test.doc_valid', true)::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B45', 'RLS evidence_files : vérificateur NON affecté NE voit PAS la preuve du projet A',
        v_count = 0, v_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 8ter. RÉVOCATION APRÈS ASSIGNATION — correctif vingt-troisième revue
--    statique (point 3). verifier_assigned est déjà accrédité (fixtures) et
--    assigné à S9 (in_progress, période renseignée, toujours AUCUN résultat
--    persistant à ce stade — voir section 7bis/7quinquies). La révocation
--    (accredited_verifiers.active -> false) est appliquée puis restaurée
--    IMMÉDIATEMENT dans le même bloc, par des instructions UPDATE distinctes
--    de l'appel testé lui-même (donc PAS annulées par le savepoint implicite
--    de carbon_test_assert_raises, qui ne protège que l'instruction évaluée)
--    — nécessaire car verifier_assigned reste utilisé par de nombreux tests
--    ultérieurs (section 9 et au-delà).
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    UPDATE public.accredited_verifiers SET active = false
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B45bis', 'complete_verification_session() : accréditation révoquée après assignation rejetée à la clôture (point 3)',
        format($sql$SELECT public.complete_verification_session(%L, 1, 1, %L, 'test révocation B45bis')$sql$,
               '33333333-3333-3333-3333-333333337009', current_setting('carbon_test.doc_valid', true)),
        'Accréditation de vérificateur révoquée');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Restauration immédiate — verifier_assigned reste requis, actif, pour
    -- le reste du script (section 9 et RLS déjà exercée ci-dessus).
    UPDATE public.accredited_verifiers SET active = true
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');
END $$;

DO $$
DECLARE
    v_count INT;
BEGIN
    -- Contre-épreuve : is_assigned_verifier() doit lui-même refléter la
    -- révocation — un vérificateur révoqué perd aussi l'accès applicatif
    -- (RLS), pas seulement la capacité d'attester (recommandation point 3).
    UPDATE public.accredited_verifiers SET active = false
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.verification_outcomes WHERE id = NULLIF(current_setting('carbon_test.outcome_s1_v2', true), '')::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();

    UPDATE public.accredited_verifiers SET active = true
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');

    PERFORM pg_temp.carbon_test_assert('B45ter', 'RLS : vérificateur révoqué (accredited_verifiers.active=false) perd aussi l''accès applicatif (is_assigned_verifier(), point 3)',
        v_count = 0, v_count::text);
END $$;

-- Correctif vingt-quatrième revue statique (blocage 1) : can_assigned_verifier_
-- view_mrv_project() revalide désormais lui aussi l'accréditation active — la
-- révocation doit donc ÉGALEMENT retirer l'accès à projects/
-- project_activity_logs/evidence_files (via ce helper), pas seulement à
-- verification_sessions/verification_outcomes (déjà démontré par B45ter).
DO $$
DECLARE
    v_count_project INT;
    v_count_log     INT;
    v_count_evi     INT;
BEGIN
    UPDATE public.accredited_verifiers SET active = false
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count_project FROM public.projects WHERE id = '33333333-3333-3333-3333-333333336001';
    SELECT count(*) INTO v_count_log FROM public.project_activity_logs WHERE id = '33333333-3333-3333-3333-333333338001';
    SELECT count(*) INTO v_count_evi FROM public.evidence_files WHERE id = current_setting('carbon_test.doc_valid', true)::UUID;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_clear_actor();

    UPDATE public.accredited_verifiers SET active = true
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');

    PERFORM pg_temp.carbon_test_assert('B45quater', 'RLS projects : vérificateur révoqué NE voit PLUS le projet A (point 1, can_assigned_verifier_view_mrv_project())',
        v_count_project = 0, v_count_project::text);
    PERFORM pg_temp.carbon_test_assert('B45quinquies', 'RLS project_activity_logs : vérificateur révoqué NE voit PLUS le journal du projet A (point 1)',
        v_count_log = 0, v_count_log::text);
    PERFORM pg_temp.carbon_test_assert('B45sexies', 'RLS evidence_files : vérificateur révoqué NE voit PLUS la preuve du projet A (point 1)',
        v_count_evi = 0, v_count_evi::text);
END $$;

-- Correctif vingt-quatrième revue statique (blocage 2) : INSERT privilégié
-- DIRECT sur verification_outcomes (verified_by = vérificateur assigné,
-- structurellement valide sinon) après révocation de son accréditation —
-- désormais rejeté par le verrou FOR SHARE ajouté dans
-- carbon_guard_verification_outcome_insert(), indépendamment de
-- complete_verification_session() (déjà démontré par B45bis). S9 : toujours
-- AUCUN résultat persistant à ce stade.
DO $$
BEGIN
    UPDATE public.accredited_verifiers SET active = false
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');

    PERFORM pg_temp.carbon_test_assert_raises('B45septies', 'INSERT direct : accréditation révoquée après assignation rejetée par le trigger (bypass RPC fermé, point 2)',
        format($sql$INSERT INTO public.verification_outcomes (verification_session_id, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by) VALUES (%L, 1, 1, 1, %L, %L)$sql$,
               '33333333-3333-3333-3333-333333337009', current_setting('carbon_test.doc_valid', true), pg_temp.carbon_test_profile('verifier_assigned')),
        'n''a plus d''accréditation active');

    UPDATE public.accredited_verifiers SET active = true
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');
END $$;

-- Ajustement du trigger verification_sessions_guard_verifier_accreditation
-- (vingt-quatrième revue statique) : une révocation ne doit PLUS bloquer une
-- UPDATE anodine (comments) sur une session dont verifier_user_id reste
-- INCHANGÉ — seule une (RE)AFFECTATION (INSERT, ou UPDATE changeant
-- réellement verifier_user_id, déjà démontré par B24octies) revalide
-- l'accréditation. S9 : verifier_user_id reste identique (verifier_assigned)
-- avant/après cette UPDATE.
DO $$
DECLARE
    v_comments TEXT;
BEGIN
    UPDATE public.accredited_verifiers SET active = false
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');

    UPDATE public.verification_sessions SET comments = 'ajustement test B45octies'
    WHERE id = '33333333-3333-3333-3333-333333337009';

    UPDATE public.accredited_verifiers SET active = true
    WHERE user_id = pg_temp.carbon_test_profile('verifier_assigned');

    SELECT comments INTO v_comments FROM public.verification_sessions WHERE id = '33333333-3333-3333-3333-333333337009';
    PERFORM pg_temp.carbon_test_assert('B45octies', 'UPDATE direct : comments modifiable sur une session déjà assignée MÊME pendant une révocation temporaire, verifier_user_id inchangé (ajustement trigger)',
        v_comments = 'ajustement test B45octies', v_comments);
END $$;

-- ────────────────────────────────────────────────────────────
-- 9. plan_verification_session() + garde structurelle sur verification_sessions
--    (§10, section 4bis/3bis de la migration, correctif vingtième revue
--    statique — remplace la policy RLS UPDATE générale supprimée). S8
--    ('...7008') n'a jamais été touchée avant cette section.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert_raises('B31', 'plan_verification_session() rejette un appelant non authentifié',
        format($sql$SELECT public.plan_verification_session(%L, '2026-05-01'::date, '2026-05-31'::date, %L)$sql$,
               '33333333-3333-3333-3333-333333337008', pg_temp.carbon_test_profile('verifier_assigned')),
        'Authentification requise');
END $$;

DO $$
BEGIN
    -- verifier_assigned n'est ni admin de projet ni super-admin — il ne peut
    -- pas s'auto-planifier (seule complete_verification_session() lui est
    -- réservée, uniquement pour enregistrer un résultat).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B32', 'plan_verification_session() rejette un appelant ni admin de projet ni super-admin',
        format($sql$SELECT public.plan_verification_session(%L, '2026-05-01'::date, '2026-05-31'::date, %L)$sql$,
               '33333333-3333-3333-3333-333333337008', pg_temp.carbon_test_profile('verifier_assigned')),
        'Accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Correctif vingt-deuxième revue statique (point 2) : p_verifier_user_id
-- doit désormais être une identité ACCRÉDITÉE (accredited_verifiers), pas
-- seulement un profil existant. Ces deux tests ciblent S8 (planifiée par
-- B33 juste après, jamais dotée d'un vérificateur avant ce point) — chaque
-- tentative échoue et est annulée par le savepoint implicite de
-- carbon_test_assert_raises, S8 reste donc vierge pour B33.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('project_admin'), 'project_admin');
    PERFORM pg_temp.carbon_test_assert_raises('B32bis', 'plan_verification_session() rejette un profil ordinaire (non accrédité) comme vérificateur',
        format($sql$SELECT public.plan_verification_session(%L, '2026-05-01'::date, '2026-05-31'::date, %L)$sql$,
               '33333333-3333-3333-3333-333333337008', pg_temp.carbon_test_profile('outsider')),
        'aucune identité de vérificateur accréditée');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    -- Le super-admin PEUT appeler plan_verification_session() (is_platform_superadmin())
    -- mais ne peut pas s'AUTO-ASSIGNER comme vérificateur (non accrédité).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('superadmin'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B32ter', 'plan_verification_session() rejette l''auto-assignation du super-administrateur comme vérificateur (non accrédité)',
        format($sql$SELECT public.plan_verification_session(%L, '2026-05-01'::date, '2026-05-31'::date, %L)$sql$,
               '33333333-3333-3333-3333-333333337008', pg_temp.carbon_test_profile('superadmin')),
        'aucune identité de vérificateur accréditée');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_returned_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('project_admin'), 'project_admin');
    v_returned_id := public.plan_verification_session('33333333-3333-3333-3333-333333337008', '2026-05-01'::date, '2026-05-31'::date, pg_temp.carbon_test_profile('verifier_assigned'));
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B33', 'plan_verification_session() réussit pour l''admin de projet : période/vérificateur renseignés',
        v_returned_id::text = '33333333-3333-3333-3333-333333337008'
        AND (SELECT reporting_period_start FROM public.verification_sessions WHERE id = '33333333-3333-3333-3333-333333337008') = '2026-05-01'::date
        AND (SELECT verifier_user_id FROM public.verification_sessions WHERE id = '33333333-3333-3333-3333-333333337008') = pg_temp.carbon_test_profile('verifier_assigned'));
END $$;

DO $$
BEGIN
    -- S1 : déjà completed, un résultat existe (outcome_s1_v2, actif) — le
    -- trigger de garde structurel (section 3bis) rejette même un admin de
    -- projet légitime tentant de replanifier via la RPC.
    -- Correctif exécution réelle : verifier_other n'est PAS accrédité
    -- (registre accredited_verifiers, seul verifier_assigned l'est) —
    -- plan_verification_session() rejetait donc dès son propre contrôle
    -- d'accréditation (ligne ~1554), avant même d'atteindre le trigger de
    -- garde structurel visé par CE test. verifier_assigned (accrédité) est
    -- utilisé à la place ; la période (juin vs janvier réel de S1) diffère
    -- toujours réellement, donc le trigger de gel se déclenche pour la
    -- bonne raison (IS DISTINCT FROM sur reporting_period_start/end).
    PERFORM pg_temp.carbon_test_set_actor_role(pg_temp.carbon_test_profile('project_admin'), 'project_admin');
    PERFORM pg_temp.carbon_test_assert_raises('B34', 'plan_verification_session() bloquée par le trigger de garde structurel une fois un résultat créé (même pour un admin autorisé)',
        format($sql$SELECT public.plan_verification_session(%L, '2026-06-01'::date, '2026-06-30'::date, %L)$sql$,
               '33333333-3333-3333-3333-333333337001', pg_temp.carbon_test_profile('verifier_assigned')),
        'immuables');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_updated_count INT;
BEGIN
    -- S8 (planifiée par B33) : correctif vingtième revue statique — la
    -- policy RLS UPDATE générale ayant été supprimée, un vérificateur (même
    -- assigné à SA propre session) n'a plus AUCUN moyen d'UPDATE direct sur
    -- verification_sessions — seule admin_manage_verification_sessions
    -- (is_project_admin(), FOR ALL) subsiste. Filtrage RLS silencieux (0
    -- ligne), pas une erreur.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('verifier_assigned'), false);
    SET LOCAL ROLE authenticated;
    UPDATE public.verification_sessions SET comments = 'contournement B35' WHERE id = '33333333-3333-3333-3333-333333337008';
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B35', 'UPDATE direct : un vérificateur (même assigné) NE peut PLUS modifier sa session — policy générale supprimée (0 ligne affectée)',
        v_updated_count = 0, v_updated_count::text);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
BEGIN
    -- S1 : status='completed' — terminal, le trigger de garde structurel le
    -- rejette même en écriture directe (hors RLS, hors RPC).
    PERFORM pg_temp.carbon_test_assert_raises('B36', 'UPDATE direct : changer status hors de completed rejeté (terminal, trigger de garde structurel)',
        format($sql$UPDATE public.verification_sessions SET status = 'in_progress' WHERE id = %L$sql$,
               '33333333-3333-3333-3333-333333337001'),
        'terminale');
END $$;

DO $$
BEGIN
    -- S1 : un résultat existe déjà — verifier_user_id devient immuable,
    -- démontré ici par une écriture DIRECTE (hors RPC, hors RLS) : le
    -- trigger de garde structurel protège indépendamment de tout chemin
    -- d'accès.
    PERFORM pg_temp.carbon_test_assert_raises('B37', 'UPDATE direct : changer verifier_user_id une fois un résultat créé rejeté (trigger de garde structurel, indépendant de la RPC)',
        format($sql$UPDATE public.verification_sessions SET verifier_user_id = %L WHERE id = %L$sql$,
               pg_temp.carbon_test_profile('verifier_other'), '33333333-3333-3333-3333-333333337001'),
        'immuables');
END $$;

-- Correctif vingt-troisième revue statique (gel supplémentaire) : S1 (un
-- résultat existe déjà) — verifier_org/verifier_contact/scope/report_url
-- deviennent eux aussi immuables, pas seulement project_id/période/
-- verifier_user_id.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B37bis', 'UPDATE direct : changer verifier_org une fois un résultat créé rejeté (gel supplémentaire, point du dossier officiel)',
        format($sql$UPDATE public.verification_sessions SET verifier_org = 'Autre Cabinet' WHERE id = %L$sql$,
               '33333333-3333-3333-3333-333333337001'),
        'immuables');
END $$;

DO $$
BEGIN
    -- Correctif exécution réelle : verification_sessions.scope est en
    -- réalité JSONB en production (pas TEXT comme supposé — voir
    -- 20260710999100_reapply_mrv_and_aggregators.sql ligne 106) —
    -- 'Autre périmètre' n'est pas un JSON valide et échouait sur
    -- "invalid input syntax for type json" avant même d'atteindre le
    -- trigger de gel visé par ce test. '"Autre périmètre"' est une chaîne
    -- JSON valide (guillemets internes).
    PERFORM pg_temp.carbon_test_assert_raises('B37ter', 'UPDATE direct : changer scope une fois un résultat créé rejeté (gel supplémentaire, point du dossier officiel)',
        format($sql$UPDATE public.verification_sessions SET scope = '"Autre périmètre"' WHERE id = %L$sql$,
               '33333333-3333-3333-3333-333333337001'),
        'immuables');
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

    IF v_total <> 128 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertions exécutées, 128 attendues (test manquant, label dupliqué, ou bloc non exécuté).', v_total;
    END IF;

    IF v_distinct <> 128 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % labels DISTINCTS sur % lignes totales (128 attendus pour les deux) — un label a été exécuté plus d''une fois, masquant potentiellement un test jamais atteint.', v_distinct, v_total;
    END IF;

    IF v_failed <> 0 THEN
        RAISE EXCEPTION 'GATE ÉCHOUÉ : % assertion(s) sur 128 ont échoué (0 attendu). Voir le résumé détaillé ci-dessous pour l''identification.', v_failed;
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────
-- 11. RÉSUMÉ — affiché AVANT le ROLLBACK.
--     NOMBRE D'ASSERTIONS ATTENDU (recompté mécaniquement, script Python
--     regex + Counter, même discipline que tests/04/tests/07) : 128 —
--     40 prévalidations (A1-A40) + 88 tests comportementaux, tous labels
--     distincts, aucun doublon.
--     Correctif vingtième revue statique : +7 prévalidations (A15-A21 :
--     plan_verification_session(), trigger de garde structurel, document
--     NOT NULL, protection de la chaîne de supersession), A13 inversée
--     (absence de la policy supprimée) ; +1 test (B4bis, régression
--     dérogation superadmin) ; +2 tests seuil calculé=0 (B18bis/B18ter) ;
--     +4 tests preuve documentaire obligatoire (Bdoc1-Bdoc4) ; +4 tests
--     protection chaîne de supersession (B24bis/ter/quater/quinquies) ;
--     +3 tests RLS client scopé par projet (B26bis/ter/quater) ; section 9
--     entièrement remplacée (B31-B37, policy RLS UPDATE générale supprimée
--     -> plan_verification_session() + trigger de garde structurel).
--     Correctif vingt-et-unième revue statique (cinq blocages) : +3
--     prévalidations (A22-A24 : trigger BEFORE INSERT, policies SELECT
--     scopées, FK evidence_files) ; +1 test (B2ter, démonstration directe
--     anti-énumération — message identique session réelle-inaccessible vs
--     UUID inexistant) ; B2/B4/B4bis reformulés (message générique, plus
--     "Accès refusé" distinct) ; +1 test (Bdoc5, preuve d'un autre projet
--     MRV rejetée) ; B21 redessiné (insertion status=''superseded''
--     explicite rejetée par le trigger, plus par l'index seul) ; +6 tests
--     (Btrig1-Btrig6, chaque validation structurelle du trigger BEFORE
--     INSERT isolée : session inexistante, planned, période manquante,
--     vérificateur manquant, verified_by non concordant, preuve invalide) ;
--     B24bis/ter/quater/quinquies entièrement redessinés autour de
--     scénarios réels (status=''active'' par défaut, démotion légitime du
--     résultat actif de S1 pour libérer l''index actif avant fork/racine
--     dupliquée) ; +1 test (B24sexies, blocage 3 : transition completed
--     refusée sans verification_outcome). Fixtures : documents/organizations
--     remplacés par evidence_files (trois lignes, scopées par projet) ; S7
--     refaite (transition in_progress explicite avant l''INSERT direct,
--     preuve du projet B) ; +2 sessions (S9, S10) dédiées aux tests
--     structurels, jamais dotées d''un résultat persistant.
--     Correctif vingt-deuxième revue statique (six points) : B19/B20
--     redessinés (INSERT dédié pour B19 ; RPC complète sur S5 pour B20,
--     préparation entièrement annulée avec l''échec EXCLUDE) ; +4
--     prévalidations (A25-A28 : accredited_verifiers/is_authorized_verifier_identity,
--     CONSTRAINT TRIGGER différés, evidence_files.file_hash + trigger de
--     gel, policies verifier_read_* scopées) ; +2 tests (B32bis/B32ter,
--     plan_verification_session() rejette un profil ordinaire et
--     l''autoassignation du super-admin comme vérificateur — registre
--     accredited_verifiers) ; +2 tests (Binv1/Binv2, invariant différé
--     session/outcome forcé via SET CONSTRAINTS ... IMMEDIATE dans un bloc
--     BEGIN/EXCEPTION imbriqué — savepoint annule automatiquement la
--     violation testée, aucune restauration manuelle requise) ; +4 tests
--     (Bevi1-Bevi4, gel evidence_files référencée : project_id/type/
--     file_hash immuables, gps librement modifiable) ; +6 tests (B40-B45,
--     RLS scopée sur projects/project_activity_logs/evidence_files —
--     vérificateur affecté voit, vérificateur non affecté ne voit pas).
--     Fixtures : registre accredited_verifiers (verifier_assigned accrédité
--     SEUL — outsider/superadmin volontairement absents) ; S7 transitionne
--     désormais à completed après son résultat direct (trou révélé par le
--     nouvel invariant différé) ; restauration légitime de S1
--     (outcome_s1_v3, supersède outcome_s1_v2) après B24quater/quinquies
--     pour rester conforme à l''invariant avant tout contrôle forcé
--     ultérieur.
--     Correctif vingt-troisième revue statique (quatre blocages + gel
--     supplémentaire) : +6 prévalidations (A29-A34 : helpers anti-cycle RLS
--     SECURITY DEFINER, trigger d''accréditation BEFORE INSERT OR UPDATE,
--     is_assigned_verifier() référence is_authorized_verifier_identity(),
--     complete_verification_session() revalide accredited_verifiers + FOR
--     SHARE, file_hash exigé trigger+RPC, gel supplémentaire
--     verifier_org/report_url). Point 1 (cycle RLS projects<->
--     verification_sessions<->activity_logs/evidence_files) : policies
--     client_read_verification_sessions et verifier_read_projects/
--     activity_logs/evidence_files réécrites autour de deux nouveaux
--     helpers SECURITY DEFINER (can_client_view_verification_session(),
--     can_assigned_verifier_view_mrv_project()) — B40-B45 conservés
--     inchangés (comportement identique, chemin d''évaluation non
--     circulaire). Point 2 (accréditation contournable hors RPC) : nouveau
--     trigger BEFORE INSERT OR UPDATE verification_sessions_guard_verifier_
--     accreditation ; +2 tests (B24septies/B24octies, INSERT et UPDATE
--     directs avec profil non accrédité rejetés indépendamment de
--     plan_verification_session()) ; fixture accredited_verifiers avancée
--     avant toute assignation de verifier_user_id (la fixture elle-même
--     démontrait le trou avant correction). Point 3 (révocation après
--     assignation) : complete_verification_session() revalide désormais
--     accredited_verifiers.active (verrou FOR SHARE, sérialise une
--     révocation concurrente) ; is_assigned_verifier() exige lui aussi une
--     accréditation active (perte d''accès applicatif pour un vérificateur
--     révoqué) ; +2 tests (B45bis/B45ter, révocation temporaire
--     restaurée immédiatement dans le même bloc — pas de savepoint ici, les
--     UPDATE de restauration sont des instructions distinctes de l''appel
--     testé). Point 4 (file_hash incomplet) : trigger BEFORE INSERT
--     verification_outcomes et complete_verification_session() exigent tous
--     deux file_hash non NULL/non vide, avec verrou FOR SHARE de la preuve
--     avant validation (course preuve<->outcome fermée) ; +1 fixture
--     evidence_files (file_hash NULL) ; +2 tests (Bdoc6 côté RPC, Btrig7
--     côté trigger). Gel supplémentaire : verifier_org/verifier_contact/
--     scope/report_url gelés au même titre que project_id/période/
--     verifier_user_id dès qu''un résultat existe ou que status=completed ;
--     +2 tests (B37bis/B37ter). Durcissement non bloquant : prévalidation
--     confirmant que is_project_admin() ne référence pas raw_user_meta_data
--     (élévation de privilège potentielle). Durcissements explicitement
--     DIFFÉRÉS (non bloquants, hors périmètre de cette passe) :
--     historisation d''accredited_verifiers (VVB, valid_from/revoked_at/
--     référence d''accréditation) ; émission d''un événement dédié sur
--     l''ancien outcome superseded en plus du recorded sur le nouveau, lors
--     d''une supersession.
--     Correctif vingt-quatrième revue statique (deux blocages + un
--     ajustement) : +3 prévalidations (A35-A37 : can_assigned_verifier_view_
--     mrv_project() référence is_authorized_verifier_identity(),
--     carbon_guard_verification_outcome_insert() référence
--     accredited_verifiers + FOR SHARE, trigger d''accréditation limité à
--     INSERT/changement effectif). Point 1 (révocation VVB incomplète sur la
--     RLS projet) : can_assigned_verifier_view_mrv_project() revalide
--     désormais is_authorized_verifier_identity(vs.verifier_user_id), pas
--     seulement l''affectation brute ; +3 tests (B45quater/quinquies/sexies,
--     perte d''accès à projects/project_activity_logs/evidence_files après
--     révocation). Point 2 (bypass direct sur verification_outcomes) :
--     carbon_guard_verification_outcome_insert() verrouille désormais
--     accredited_verifiers FOR SHARE pour le vérificateur assigné avant
--     d''autoriser l''insertion, même patron que le verrou de la preuve ; +1
--     test (B45septies, INSERT privilégié direct rejeté après révocation).
--     Ajustement du trigger verification_sessions_guard_verifier_
--     accreditation : ne revalide plus l''accréditation QUE sur INSERT ou
--     UPDATE changeant réellement verifier_user_id (IS DISTINCT FROM OLD) —
--     une révocation ne bloque plus une UPDATE anodine (comments) sur une
--     session déjà assignée ; +1 test (B45octies, contre-épreuve positive).
--     Les points file_hash, cycle RLS (hors ce complément) et gel
--     verifier_org/verifier_contact/scope/report_url restent validés tels
--     quels depuis la vingt-troisième revue, sans nouveau changement.
--     Correctif vingt-cinquième revue statique (deux blocages) : +2
--     prévalidations (A38-A39 : garde d''accréditation verrouille
--     directement accredited_verifiers sans appeler is_authorized_verifier_
--     identity(), timestamps outcome capturés en tout dernier lieu). Point 1
--     (affectation/révocation non sérialisée + incohérence de privilège) :
--     carbon_guard_verification_session_verifier_accreditation() verrouille
--     désormais DIRECTEMENT accredited_verifiers (FOR SHARE) au lieu
--     d''appeler is_authorized_verifier_identity() — cette dernière a son
--     EXECUTE volontairement révoqué à authenticated (fonction interne,
--     contextes SECURITY DEFINER uniquement), ce que ce trigger SECURITY
--     INVOKER ne peut pas satisfaire ; un admin MRV légitime (authenticated)
--     assignant un vérificateur pourtant accrédité recevait donc "permission
--     denied for function is_authorized_verifier_identity". Le verrou direct
--     corrige les deux défauts à la fois (sérialisation ET privilège) ; +1
--     nouvelle session fixture S11 (jamais touchée ailleurs) ; +1 test
--     (B24nonies, contre-épreuve POSITIVE sous SET LOCAL ROLE authenticated
--     avec project_admin + vérificateur accrédité — invisible aux tests
--     précédents, tous exécutés comme propriétaire de la migration, non
--     soumis aux GRANT/REVOKE). Point 2 (horodatage outcome encore trop
--     tôt) : dans carbon_guard_verification_outcome_insert(), v_now :=
--     clock_timestamp() et NEW.verified_at/created_at déplacés en TOUTE
--     dernière étape avant RETURN NEW, après le verrou/validation de la
--     preuve (evidence_files FOR SHARE) et les contrôles de supersession —
--     plus seulement après le verrou d''accréditation (3bis) ; une attente
--     sur le verrou de la preuve ne peut plus faire dériver verified_at/
--     created_at de la version de preuve effectivement validée.
--     Correctif vingt-sixième revue statique (un blocage) : +1 prévalidation
--     (A40 : prosecdef=true pour la garde d''accréditation). Affectation/
--     révocation non sérialisée (suite) : carbon_guard_verification_session_
--     verifier_accreditation() (verrou FOR SHARE ajouté en vingt-cinquième
--     revue) est désormais SECURITY DEFINER, alors qu''elle était restée
--     SECURITY INVOKER — SELECT/PERFORM ... FOR SHARE exige le privilège
--     UPDATE (pas seulement SELECT) sur la table verrouillée ET est soumis
--     aux policies RLS de type UPDATE (pas seulement SELECT) ;
--     accredited_verifiers ne porte qu''une policy SELECT et authenticated
--     n''a jamais reçu UPDATE dessus (intentionnel — la table ne doit être
--     modifiable que par le propriétaire). Le trigger SECURITY INVOKER
--     précédent aurait donc échoué sous authenticated dès le PERFORM ... FOR
--     SHARE, avant même d''atteindre le IF NOT FOUND — B24nonies (contre-
--     épreuve sous SET LOCAL ROLE authenticated, ajoutée en vingt-cinquième
--     revue) est CONSERVÉ tel quel et sert désormais de test de non-
--     régression réel pour ce correctif, sans qu''aucun GRANT UPDATE
--     supplémentaire n''ait été accordé sur accredited_verifiers.
-- ────────────────────────────────────────────────────────────

SELECT
    (SELECT count(*) FROM public._carbon_migration_test_results) AS total_assertions,
    (SELECT count(*) FILTER (WHERE NOT passed) FROM public._carbon_migration_test_results) AS failed_assertions;

SELECT section, assertion, passed, detail
FROM public._carbon_migration_test_results
ORDER BY id;

ROLLBACK;
