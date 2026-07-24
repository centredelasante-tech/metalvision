-- ============================================================
-- Tests — Migration 09 (credit_sales, modèle commercial et financier)
-- ============================================================
-- STATUT : PROPOSITION SOUMISE POUR REVUE — NON EXÉCUTÉE.
--
-- Ce fichier est intégralement transactionnel (BEGIN...ROLLBACK) : Parties
-- A, fixtures et B uniquement. Aucun dblink, aucun commit de fixtures,
-- aucun CREATE EXTENSION. Le seul scénario de concurrence réelle à deux
-- connexions identifié après la première revue statique (point 5 :
-- revalidation sous verrou de carbon_try_activate_member_distribution_
-- override_proposal() contre une double activation concurrente conflictuelle
-- sur le même override) vit désormais, à part, dans
-- 09_test_carbon_sales_financial_model_concurrency_STAGING_ONLY.sql — jamais
-- ici, même discipline que 08_test_carbon_lots_concurrency_STAGING_ONLY.sql.
-- Les autres points de verrouillage introduits par la première revue (par
-- ex. le trigger de cohérence credit_lots ↔ credit_sale_lots, point 15)
-- restent des vérifications synchrones à connexion unique et sont couverts
-- ici même, sans protocole à deux connexions dédié.
--
-- DÉPENDANCES : 01/02/05/06/07/08 et 09
-- (09_carbon_sales_financial_model.sql, PROPOSITION) déjà appliquées.
-- Réutilise >= 5 profils réels distincts de public.profiles (FK réelle vers
-- auth.users — aucune ligne profiles fabriquée ici).
--
-- SCÉNARIO PRINCIPAL — vérifié à la main avant écriture (aucune exécution
-- réelle possible ici, cf. consigne « Ne rien exécuter dans Supabase ») :
-- une émission à 3 sources égales (A=1/B=1/C=1 tCO2e, 3 t au total), un lot
-- unique de 1 t vendu à 100,00 $/tCO2e, coût de 5,00 $ (registry_fee),
-- distribution_rule à 10 % frais / 5 % réserve / poids 1,0 pour les trois
-- organisations (même regroupement) :
--   Étape A (attribution, prorata 1/3 chacune, TRONQUÉ 4 décimales — corrigé
--   après la QUATRIÈME revue statique, bloqueur 3 : TRUNC, jamais ROUND, pour
--   garantir un reliquat structurellement non négatif, voir compute_credit_
--   sale_allocations() pour le raisonnement complet) :
--     A/B/C = TRUNC(1 * 1/3, 4) = 0,3333 chacune (inchangé par rapport à
--     ROUND ici : la 5e décimale, 3, tronque et arrondit identiquement) ;
--     somme = 0,9999 ; reliquat tCO2e = 1,0000 - 0,9999 = 0,0001, imputé à
--     ORG_A (plus petit organization_id à égalité de contribution) => A = 0,3334.
--   Étape B (répartition, gross_amount = TRUNC(allocated_tco2e/total pondéré *
--     net_distributable_amount, 2) = 95,00 $) :
--     A : TRUNC(0,3334/1,0000*95,00, 2) = TRUNC(31,673, 2) = 31,67 (inchangé
--     par rapport à ROUND : 3e décimale 3, tronque et arrondit identiquement) ;
--     B/C : TRUNC(0,3333/1,0000*95,00, 2) = TRUNC(31,6635, 2) = 31,66 chacune
--     (idem, 3e décimale 3) ; somme = 94,99 ; reliquat argent = 95,00 - 94,99
--     = 0,01, imputé à ORG_A (même paire désignée) => A gross = 31,68.
--     RECALCULÉ après la QUATRIÈME revue statique (bloqueur 3) :
--     fee_amount = TRUNC(gross*10 %,2) (ligne distincte 'platform_fee', jamais fusionnée) ;
--     reserve_amount = TRUNC(gross*5 %,2) (RÉSERVE VÉRITABLE UNIQUEMENT, ligne 'reserve') ;
--     net('carbon_revenue') = gross - fee - reserve (cascade de référence inchangée) :
--       A : TRUNC(31,68*10%,2)=TRUNC(3,168,2)=3,16 (3e décimale 8, TRUNC <> ROUND
--           ici — ROUND aurait donné 3,17, désormais FAUX) ; reserve=TRUNC(1,584,2)=1,58
--           (inchangé, 3e décimale 4) ; net=31,68-3,16-1,58=26,94
--       B : TRUNC(31,66*10%,2)=TRUNC(3,166,2)=3,16 (3e décimale 6, TRUNC <> ROUND
--           ici) ; reserve=TRUNC(1,583,2)=1,58 (inchangé) ; net=31,66-3,16-1,58=26,92
--       C : identique à B : fee=3,16, reserve=1,58, net=26,92
--     Trois lignes par organisation désormais ('carbon_revenue' net ci-dessus,
--     'reserve' net=reserve véritable, 'platform_fee' net=fee_amount) :
--       A : carbon_revenue=26,94 + reserve=1,58 + platform_fee=3,16 = 31,68
--       B : carbon_revenue=26,92 + reserve=1,58 + platform_fee=3,16 = 31,66
--       C : carbon_revenue=26,92 + reserve=1,58 + platform_fee=3,16 = 31,66
--     Vérification : SUM(net) WHERE type IN (carbon_revenue,reserve,platform_fee)
--     = 31,68+31,66+31,66 = 95,00 = net_distributable_amount. Égalité exacte
--     confirmée à la main (gross_amount et allocated_tco2e restent IDENTIQUES à
--     la version précédente du calcul dans ce scénario précis — seuls
--     fee_amount/net_amount changent, TRUNC divergeant de ROUND uniquement là
--     où la 3e décimale tronquée était >= 5).
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 0. Harnais + table de résultats (hors transaction, TEMP TABLE, même
--    patron que tests/08 — voir son commentaire pour le raisonnement).
-- ────────────────────────────────────────────────────────────
CREATE TEMP TABLE _carbon_migration_test_results (
    id         SERIAL PRIMARY KEY,
    section    TEXT NOT NULL,
    assertion  TEXT NOT NULL,
    detail     TEXT NULL,
    passed     BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

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
            'sub', p_user_id::text, 'role', 'authenticated',
            'app_metadata', CASE WHEN p_superadmin THEN jsonb_build_object('role', 'admin') ELSE jsonb_build_object() END
        )::text, true
    );
$$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_clear_actor() RETURNS VOID
LANGUAGE sql AS $$ SELECT set_config('request.jwt.claims', '{}', true); $$;

CREATE OR REPLACE FUNCTION pg_temp.carbon_test_profile(p_key TEXT) RETURNS UUID
LANGUAGE sql AS $$ SELECT current_setting('carbon_test09.profile_' || p_key)::UUID $$;

-- ============================================================
-- BLOC PRINCIPAL — PARTIES A / fixtures / B, transactionnel
-- ============================================================
BEGIN;

-- ────────────────────────────────────────────────────────────
-- 1. PARTIE A — structurelle
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert('A', 'A1 les 9 tables existent',
        to_regclass('public.credit_sales') IS NOT NULL AND to_regclass('public.credit_sale_lots') IS NOT NULL
        AND to_regclass('public.credit_sale_costs') IS NOT NULL AND to_regclass('public.credit_sale_adjustments') IS NOT NULL
        AND to_regclass('public.distribution_rules') IS NOT NULL AND to_regclass('public.distribution_rule_proposals') IS NOT NULL
        AND to_regclass('public.member_distribution_overrides') IS NOT NULL
        AND to_regclass('public.member_distribution_override_proposals') IS NOT NULL
        AND to_regclass('public.credit_sale_allocations') IS NOT NULL);

    PERFORM pg_temp.carbon_test_assert('A', 'A2 credit_sales : CHECK status 4 valeurs',
        EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.credit_sales'::regclass AND c.contype='c'
            AND pg_get_constraintdef(c.oid) ILIKE '%draft%' AND pg_get_constraintdef(c.oid) ILIKE '%confirmed%'
            AND pg_get_constraintdef(c.oid) ILIKE '%settled%' AND pg_get_constraintdef(c.oid) ILIKE '%cancelled%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A3 credit_sale_lots : UNIQUE partiel (credit_lot_id) WHERE released_at IS NULL',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credit_sale_lots'
            AND indexname='idx_credit_sale_lots_active_lot' AND indexdef ILIKE '%released_at IS NULL%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A4 credit_sale_costs : CHECK cost_type 9 valeurs',
        (SELECT pg_get_constraintdef(c.oid) ILIKE '%platform_fee%' AND pg_get_constraintdef(c.oid) ILIKE '%registry_fee%'
            AND pg_get_constraintdef(c.oid) ILIKE '%verification_fee%' AND pg_get_constraintdef(c.oid) ILIKE '%brokerage%'
            AND pg_get_constraintdef(c.oid) ILIKE '%legal_fee%' AND pg_get_constraintdef(c.oid) ILIKE '%risk_reserve%'
            AND pg_get_constraintdef(c.oid) ILIKE '%administrative_fee%' AND pg_get_constraintdef(c.oid) ILIKE '%tax%'
            AND pg_get_constraintdef(c.oid) ILIKE '%other%'
         FROM pg_constraint c WHERE c.conrelid='public.credit_sale_costs'::regclass AND c.contype='c'
            AND pg_get_constraintdef(c.oid) ILIKE '%cost_type%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A5 distribution_rules : EXCLUDE anti-chevauchement',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.distribution_rules'::regclass AND contype='x'
            AND conname='distribution_rules_no_overlap'));

    PERFORM pg_temp.carbon_test_assert('A', 'A6 distribution_rule_proposals : CHECK activated<=>activated_distribution_rule_id',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.distribution_rule_proposals'::regclass AND contype='c'
            AND conname='distribution_rule_proposals_activated_check'));

    -- A7 libellé corrigé après la deuxième revue statique (point 12) : l'EXCLUDE est désormais à DEUX
    -- dimensions (daterange effet && tstzrange publication), plus scopée par un simple WHERE revoked_at
    -- IS NULL — la composition exacte à deux dimensions est déjà revérifiée séparément par A27.
    PERFORM pg_temp.carbon_test_assert('A', 'A7 member_distribution_overrides : EXCLUDE anti-chevauchement 2D (effet && publication)',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.member_distribution_overrides'::regclass AND contype='x'
            AND conname='member_distribution_overrides_no_overlap'));

    PERFORM pg_temp.carbon_test_assert('A', 'A8 member_distribution_override_proposals : CHECK proposal_type croisé (create/replace/revoke)',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.member_distribution_override_proposals'::regclass AND contype='c'
            AND conname='member_distribution_override_proposals_type_check'));

    -- A9 recompté après la DEUXIÈME revue statique (point 6) : allocation_type RÉDUIT à 3 valeurs
    -- réelles ('expense_reimbursement'/'bonus'/'adjustment' retirées, décision explicite — aucune RPC ne
    -- les crée, credit_sale_allocations_unique ne peut pas les représenter proprement, corrections
    -- manuelles hors MVP passent par credit_sale_adjustments) — comparaison par ENSEMBLE EXACT sur la
    -- contrainte CHECK dédiée à allocation_type (nom auto-généré par Postgres, colonne seule, jamais
    -- pollué par le littéral 'NaN' présent dans credit_sale_allocations_tco2e_check).
    PERFORM pg_temp.carbon_test_assert('A', 'A9 credit_sale_allocations : CHECK allocation_type = exactement 3 valeurs (carbon_revenue/reserve/platform_fee)',
        (SELECT array(SELECT unnest(ARRAY['carbon_revenue','reserve','platform_fee']) ORDER BY 1))
        = (
            SELECT array_agg(m[1] ORDER BY m[1])
            FROM pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''((?:[^'']|'''''')*)''', 'g') AS m
            WHERE c.conrelid='public.credit_sale_allocations'::regclass AND c.contype='c'
              AND c.conname='credit_sale_allocations_allocation_type_check'
        ));
    -- Corrigé après la CINQUIÈME revue statique (correction complémentaire) : A9bis vérifiait
    -- auparavant que allocated_tco2e est NULL pour 'platform_fee' UNIQUEMENT, alors que le CHECK
    -- réel (credit_sale_allocations_tco2e_check, ci-dessus dans la migration) impose NULL pour
    -- 'reserve' ET 'platform_fee' ensemble — seule 'carbon_revenue' porte allocated_tco2e (NOT
    -- NULL). L'assertion comparait donc la mauvaise portée : elle exige désormais 'reserve' ET
    -- 'platform_fee' tous deux présents dans la branche NULL de la définition du CHECK.
    PERFORM pg_temp.carbon_test_assert('A', 'A9bis credit_sale_allocations : allocated_tco2e conditionnel (NULL pour reserve ET platform_fee, jamais seulement platform_fee)',
        EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.credit_sale_allocations'::regclass AND c.contype='c'
            AND c.conname='credit_sale_allocations_tco2e_check'
            AND pg_get_constraintdef(c.oid) ILIKE '%reserve%' AND pg_get_constraintdef(c.oid) ILIKE '%platform_fee%'
            AND pg_get_constraintdef(c.oid) ILIKE '%carbon_revenue%'
            AND pg_get_constraintdef(c.oid) NOT ILIKE '%expense_reimbursement%'
            AND pg_get_constraintdef(c.oid) NOT ILIKE '%bonus%'));

    PERFORM pg_temp.carbon_test_assert('A', 'A10 credit_sale_allocations : UNIQUE (credit_sale_id, organization_id, aggregator_id, allocation_type)',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.credit_sale_allocations'::regclass AND contype='u'
            AND conname='credit_sale_allocations_unique'));

    -- Recompté après la première revue statique (point 14) : 3 ALTER TABLE différés, pas 2.
    PERFORM pg_temp.carbon_test_assert('A', 'A11 les 3 ALTER TABLE différés (FK circulaires) sont en place',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='distribution_rules_proposal_id_fkey')
        AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='member_distribution_overrides_proposal_id_fkey')
        AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='member_distribution_overrides_revocation_proposal_id_fkey'));

    PERFORM pg_temp.carbon_test_assert('A', 'A12 trigger FSM credit_sales présent',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_sales'::regclass AND tgname='trg_carbon_credit_sales_before_update'));

    PERFORM pg_temp.carbon_test_assert('A', 'A13 trigger de synchronisation total_tco2e présent',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_sale_lots'::regclass AND tgname='trg_carbon_sync_credit_sale_total_tco2e'));

    PERFORM pg_temp.carbon_test_assert('A', 'A14 trigger de coordination reserved->voided posé sur credit_lots (par 09, sans modifier 08)',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_lots'::regclass AND tgname='trg_carbon_release_credit_sale_lot_on_external_void'));

    -- Nommée A14bis après la deuxième revue statique (point 1) : cette assertion n'était pas numérotée,
    -- ce qui rendait le comptage mécanique ambigu (gate annoncé à 99, réel à 100).
    PERFORM pg_temp.carbon_test_assert('A', 'A14bis 08 non modifiée : son propre trigger de machine à états existe toujours',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_lots'::regclass AND tgname='trg_carbon_credit_lots_before_update'));

    PERFORM pg_temp.carbon_test_assert('A', 'A15 append-only : triggers forbid_delete présents sur les 9 tables',
        (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'trg_carbon_%forbid_delete' AND tgrelid IN (
            'public.credit_sales'::regclass, 'public.credit_sale_lots'::regclass, 'public.credit_sale_costs'::regclass,
            'public.credit_sale_adjustments'::regclass, 'public.distribution_rules'::regclass,
            'public.distribution_rule_proposals'::regclass, 'public.member_distribution_overrides'::regclass,
            'public.member_distribution_override_proposals'::regclass, 'public.credit_sale_allocations'::regclass
        )) = 9);

    PERFORM pg_temp.carbon_test_assert('A', 'A16 RLS activée sur les 9 tables',
        (SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN (
            'public.credit_sales'::regclass, 'public.credit_sale_lots'::regclass, 'public.credit_sale_costs'::regclass,
            'public.credit_sale_adjustments'::regclass, 'public.distribution_rules'::regclass,
            'public.distribution_rule_proposals'::regclass, 'public.member_distribution_overrides'::regclass,
            'public.member_distribution_override_proposals'::regclass, 'public.credit_sale_allocations'::regclass
        )));

    PERFORM pg_temp.carbon_test_assert('A', 'A17 anon sans aucun privilège SELECT sur credit_sales/credit_sale_allocations',
        NOT has_table_privilege('anon', 'public.credit_sales', 'SELECT')
        AND NOT has_table_privilege('anon', 'public.credit_sale_allocations', 'SELECT'));

    PERFORM pg_temp.carbon_test_assert('A', 'A18 authenticated : SELECT seul sur credit_sales, sans INSERT/UPDATE/DELETE direct',
        has_table_privilege('authenticated', 'public.credit_sales', 'SELECT')
        AND NOT has_table_privilege('authenticated', 'public.credit_sales', 'INSERT')
        AND NOT has_table_privilege('authenticated', 'public.credit_sales', 'UPDATE')
        AND NOT has_table_privilege('authenticated', 'public.credit_sales', 'DELETE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A19 20 RPC métier existent avec la signature attendue',
        to_regprocedure('public.create_credit_sale(uuid,numeric,text)') IS NOT NULL
        AND to_regprocedure('public.add_credit_sale_lot(uuid,uuid)') IS NOT NULL
        AND to_regprocedure('public.release_credit_sale_lot(uuid,text)') IS NOT NULL
        AND to_regprocedure('public.add_credit_sale_cost(uuid,text,numeric,text,text)') IS NOT NULL
        AND to_regprocedure('public.cancel_credit_sale(uuid,text)') IS NOT NULL
        AND to_regprocedure('public.confirm_credit_sale(uuid)') IS NOT NULL
        AND to_regprocedure('public.settle_credit_sale(uuid,text)') IS NOT NULL
        AND to_regprocedure('public.retire_credit_lot(uuid,text)') IS NOT NULL
        AND to_regprocedure('public.add_credit_sale_adjustment(uuid,numeric,text)') IS NOT NULL
        AND to_regprocedure('public.propose_distribution_rule(uuid,numeric,numeric,numeric)') IS NOT NULL
        AND to_regprocedure('public.approve_distribution_rule_as_aggregator_admin(uuid)') IS NOT NULL
        AND to_regprocedure('public.approve_distribution_rule_as_operator_admin(uuid)') IS NOT NULL
        AND to_regprocedure('public.reject_distribution_rule_proposal(uuid,text)') IS NOT NULL
        AND to_regprocedure('public.withdraw_distribution_rule_proposal(uuid)') IS NOT NULL
        AND to_regprocedure('public.propose_member_distribution_override(text,uuid,uuid,text,numeric,date,date,text)') IS NOT NULL
        AND to_regprocedure('public.approve_member_distribution_override_as_organization_admin(uuid)') IS NOT NULL
        AND to_regprocedure('public.approve_member_distribution_override_as_aggregator_admin(uuid)') IS NOT NULL
        AND to_regprocedure('public.approve_member_distribution_override_as_operator_admin(uuid)') IS NOT NULL
        AND to_regprocedure('public.reject_member_distribution_override_proposal(uuid,text)') IS NOT NULL
        AND to_regprocedure('public.withdraw_member_distribution_override_proposal(uuid)') IS NOT NULL);

    -- A20/A21 corrigés après la première revue statique : comparaison par ENSEMBLE EXACT (jamais une
    -- simple présence par sous-chaîne ILIKE, qui ne détecterait ni un doublon ni une valeur en trop)
    -- contre l'ensemble canonique des 48 valeurs exactes codées dans 09_carbon_sales_financial_model.sql.
    PERFORM pg_temp.carbon_test_assert('A', 'A20 catalogue event_type = exactement l''ensemble canonique des 48 valeurs attendues',
        (SELECT array(SELECT unnest(ARRAY[
            'aggregator_created','aggregator_membership_started','aggregator_membership_ended',
            'aggregator_admin_appointed','aggregator_admin_revoked','aggregator_primary_admin_transferred',
            'ccf_mrv_link_started','ccf_mrv_link_ended',
            'verification_session_started','verification_session_completed',
            'verification_outcome_recorded','verification_outcome_superseded',
            'credit_issuance_created','credit_issuance_submitted','credit_issuance_issued',
            'credit_issuance_externally_cancelled','credit_issuance_voided',
            'credit_lot_issued','credit_lot_reserved','credit_lot_sold','credit_lot_retired','credit_lot_voided',
            'credit_sale_created','credit_sale_cost_recorded','credit_sale_confirmed','credit_sale_cancelled',
            'credit_sale_settled','credit_sale_adjustment_recorded','credit_sale_allocation_recorded',
            'credit_sale_allocation_approved','credit_sale_allocation_paid',
            'platform_operator_designated','platform_operator_revoked',
            'carbon_commercialization_mandate_granted','carbon_commercialization_mandate_revoked',
            'credit_issuance_marked_eligible','credit_issuance_externally_rejected',
            'credit_lot_underlying_issuance_cancelled',
            'credit_sale_lot_released','credit_sale_lot_released_by_external_cancellation',
            'distribution_rule_proposed','distribution_rule_activated',
            'distribution_rule_rejected','distribution_rule_withdrawn',
            'member_distribution_override_proposed','member_distribution_override_activated',
            'member_distribution_override_rejected','member_distribution_override_withdrawn'
        ]) ORDER BY 1))
        = (
            SELECT array_agg(m[1] ORDER BY m[1])
            FROM pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''((?:[^'']|'''''')*)''', 'g') AS m
            WHERE c.conrelid='public.carbon_business_events'::regclass AND c.contype='c' AND pg_get_constraintdef(c.oid) ILIKE '%event_type%'
        ));

    PERFORM pg_temp.carbon_test_assert('A', 'A21 catalogue event_type : exactement 48 valeurs distinctes (aucun doublon)',
        (SELECT array_length(array_agg(DISTINCT m[1]), 1)
         FROM pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''((?:[^'']|'''''')*)''', 'g') AS m
         WHERE c.conrelid='public.carbon_business_events'::regclass AND c.contype='c' AND pg_get_constraintdef(c.oid) ILIKE '%event_type%') = 48);

    -- A22 corrigé de même : ensemble exact des 19 valeurs object_type.
    PERFORM pg_temp.carbon_test_assert('A', 'A22 catalogue object_type = exactement l''ensemble canonique des 19 valeurs attendues',
        (SELECT array(SELECT unnest(ARRAY[
            'aggregator','aggregator_membership','aggregator_admin','ccf_mrv_project_link',
            'verification_session','verification_outcome','credit_issuance','credit_lot',
            'credit_sale','credit_sale_cost','credit_sale_adjustment','credit_sale_allocation',
            'platform_operator','carbon_commercialization_mandate',
            'credit_sale_lot','distribution_rule','distribution_rule_proposal',
            'member_distribution_override','member_distribution_override_proposal'
        ]) ORDER BY 1))
        = (
            SELECT array_agg(m[1] ORDER BY m[1])
            FROM pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''((?:[^'']|'''''')*)''', 'g') AS m
            WHERE c.conrelid='public.carbon_business_events'::regclass AND c.contype='c' AND pg_get_constraintdef(c.oid) ILIKE '%object_type%'
        ));

    PERFORM pg_temp.carbon_test_assert('A', 'A23 SECURITY DEFINER + search_path durci sur les RPC principales',
        (SELECT bool_and(p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c ILIKE '%search_path=public, pg_temp%'))
         FROM pg_proc p WHERE p.oid IN (
            'public.confirm_credit_sale(uuid)'::regprocedure, 'public.compute_credit_sale_allocations(uuid,uuid)'::regprocedure,
            'public.settle_credit_sale(uuid,text)'::regprocedure, 'public.propose_distribution_rule(uuid,numeric,numeric,numeric)'::regprocedure
         )));

    PERFORM pg_temp.carbon_test_assert('A', 'A24 fonctions internes/trigger sans EXECUTE pour authenticated/anon',
        NOT has_function_privilege('authenticated','public.compute_credit_sale_allocations(uuid,uuid)'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('anon','public.compute_credit_sale_allocations(uuid,uuid)'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_release_credit_sale_lot_on_external_void()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_guard_credit_lots_sale_consistency()'::regprocedure,'EXECUTE'));

    -- Ajoutées à la ONZIÈME revue statique (bloqueur 1) : une assertion PAR fonction (jamais regroupées
    -- dans une seule assertion opaque comme A24) pour les cinq fonctions internes SECURITY DEFINER
    -- ajoutées au REVOKE ALL par la NEUVIÈME/DIXIÈME revue mais omises jusqu'ici de toute preuve
    -- structurelle — chaque assertion isole sa propre fonction pour identifier immédiatement laquelle
    -- réintroduirait un privilège. Vérifie explicitement anon ET authenticated, pour détecter aussi un
    -- EXECUTE hérité de PUBLIC (has_function_privilege reflète PUBLIC + le rôle explicitement nommé).
    PERFORM pg_temp.carbon_test_assert('A', 'A_11e_1 carbon_guard_distribution_rule_insert() sans EXECUTE pour anon/authenticated',
        NOT has_function_privilege('anon','public.carbon_guard_distribution_rule_insert()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_guard_distribution_rule_insert()'::regprocedure,'EXECUTE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A_11e_2 carbon_guard_member_distribution_override_insert() sans EXECUTE pour anon/authenticated',
        NOT has_function_privilege('anon','public.carbon_guard_member_distribution_override_insert()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_guard_member_distribution_override_insert()'::regprocedure,'EXECUTE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A_11e_3 carbon_check_distribution_rule_proposal_integrity() sans EXECUTE pour anon/authenticated',
        NOT has_function_privilege('anon','public.carbon_check_distribution_rule_proposal_integrity()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_check_distribution_rule_proposal_integrity()'::regprocedure,'EXECUTE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A_11e_4 carbon_check_member_distribution_override_creation_integrity() sans EXECUTE pour anon/authenticated',
        NOT has_function_privilege('anon','public.carbon_check_member_distribution_override_creation_integrity()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_check_member_distribution_override_creation_integrity()'::regprocedure,'EXECUTE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A_11e_5 carbon_check_member_distribution_override_revocation_integrity() sans EXECUTE pour anon/authenticated',
        NOT has_function_privilege('anon','public.carbon_check_member_distribution_override_revocation_integrity()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_check_member_distribution_override_revocation_integrity()'::regprocedure,'EXECUTE'));

    -- Ajoutée à la DOUZIÈME revue statique (bloqueur 2) : même patron A_11e_1..A_11e_5, pour la nouvelle
    -- fonction interne de fermeture de distribution_rules.
    PERFORM pg_temp.carbon_test_assert('A', 'A_12e_1 carbon_check_distribution_rule_closure_integrity() sans EXECUTE pour anon/authenticated',
        NOT has_function_privilege('anon','public.carbon_check_distribution_rule_closure_integrity()'::regprocedure,'EXECUTE')
        AND NOT has_function_privilege('authenticated','public.carbon_check_distribution_rule_closure_integrity()'::regprocedure,'EXECUTE'));

    PERFORM pg_temp.carbon_test_assert('A', 'A26 trigger de cohérence structurelle credit_sale_lots<->credit_lots posé (point 15)',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.credit_lots'::regclass AND tgname='trg_carbon_guard_credit_lots_sale_consistency'));

    PERFORM pg_temp.carbon_test_assert('A', 'A27 EXCLUDE member_distribution_overrides_no_overlap à deux dimensions (point 6 : date range ET publication range)',
        (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.member_distribution_overrides'::regclass AND contype='x'
            AND conname='member_distribution_overrides_no_overlap') ILIKE '%tstzrange%');

    PERFORM pg_temp.carbon_test_assert('A', 'A28 bornes fee/reserve/weight durcies (point 9) sur member_distribution_overrides',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.member_distribution_overrides'::regclass AND contype='c'
            AND conname='member_distribution_overrides_value_bounds_check'));

    PERFORM pg_temp.carbon_test_assert('A', 'A25 EXECUTE authenticated=oui sur confirm_credit_sale/settle_credit_sale',
        has_function_privilege('authenticated','public.confirm_credit_sale(uuid)'::regprocedure,'EXECUTE')
        AND has_function_privilege('authenticated','public.settle_credit_sale(uuid,text)'::regprocedure,'EXECUTE'));
END $$;

-- ────────────────────────────────────────────────────────────
-- 2. FIXTURES — chaîne 02/05/06/07/08 réelle, 3 organisations contributrices
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_ids UUID[];
BEGIN
    -- GATE 3 tentative 2 : correction minimale du harnais transactionnel (autorisée explicitement) —
    -- l'environnement réel de production ne contient que 7 profils distincts, jamais 8. Aucun nouveau
    -- profil/utilisateur n'est créé en production pour satisfaire ce test : le scénario B105-B107
    -- (membre simple d'une organisation qui rejoint puis quitte le regroupement) réutilise
    -- délibérément l'identité 'outsider' comme 'exmember' (v_ids[5] pour les deux), au lieu d'exiger
    -- une 8e identité dédiée. Sûr car : (a) tous les usages 'outsider' antérieurs au scénario
    -- ex-member ont lieu AVANT que cette identité soit ajoutée à l'organisation partante ; (b) après
    -- ce scénario, le seul usage 'outsider' restant (B_10e_1, durcissement join_aggregator()) exige
    -- seulement l'absence d'autorité aggregator_admin/superadmin sur un regroupement CIBLE distinct
    -- (généré par gen_random_uuid()) — propriété qui reste vraie même après la fin de l'adhésion de
    -- son organisation à SON PROPRE regroupement (voir aussi le commentaire de B_10e_1 plus bas). Le
    -- profil 'orgamember' (7, cinquième revue) reste le membre simple d'ORG_A, qui NE QUITTE JAMAIS le
    -- regroupement dans ce fichier — sert de contrôle positif (membre TOUJOURS actif, doit continuer à
    -- voir les nouvelles règles).
    SELECT array_agg(id) INTO v_ids FROM (SELECT id FROM public.profiles ORDER BY created_at LIMIT 7) sub;
    IF COALESCE(array_length(v_ids, 1), 0) < 7 THEN
        RAISE EXCEPTION 'Fixtures impossibles : au moins 7 profils réels distincts sont requis dans public.profiles (trouvés : %).', COALESCE(array_length(v_ids, 1), 0);
    END IF;
    PERFORM set_config('carbon_test09.profile_op',      v_ids[1]::text, false); -- admin opérateur + superadmin (JWT) + vérificateur
    PERFORM set_config('carbon_test09.profile_orga',    v_ids[2]::text, false); -- admin ORG_A
    PERFORM set_config('carbon_test09.profile_orgb',    v_ids[3]::text, false); -- admin ORG_B (et ORG_C, réutilisé)
    PERFORM set_config('carbon_test09.profile_aggadmin', v_ids[4]::text, false); -- primary_admin du regroupement (corrigé, point 3 — était co_admin)
    PERFORM set_config('carbon_test09.profile_outsider', v_ids[5]::text, false); -- aucune autorité initiale sur le regroupement ; identité réutilisée plus tard comme 'exmember' après une adhésion organisationnelle terminée (GATE 3, correction minimale du harnais)
    PERFORM set_config('carbon_test09.profile_coadmin', v_ids[6]::text, false); -- co_admin du regroupement — AUCUNE autorité économique, doit toujours être rejeté (point 3)
    PERFORM set_config('carbon_test09.profile_orgamember', v_ids[7]::text, false); -- simple membre NON-admin d'ORG_A (org_role='membre'), AUCUNE autorité d'approbation
    -- GATE 3, correction minimale du harnais : identité VOLONTAIREMENT partagée avec 'outsider'
    -- (v_ids[5]) — jamais un 8e profil dédié (production limitée à 7 profils réels). Sûr : tout usage
    -- de 'outsider' précédant le scénario B105-B107 a lieu avant l'ajout de cette identité à
    -- l'organisation partante ; après B105-B107, son seul usage 'outsider' restant (B_10e_1) n'exige
    -- que l'absence d'autorité aggregator_admin/superadmin sur un regroupement cible distinct, jamais
    -- l'absence de toute relation.
    PERFORM set_config('carbon_test09.profile_exmember', v_ids[5]::text, false); -- simple membre NON-admin d'une organisation qui QUITTE le regroupement (sixième revue, correction 3) ; identité = 'outsider' (v_ids[5]), réutilisation volontaire (GATE 3)
END $$;

INSERT INTO public.organizations (id, name, status) VALUES
    ('66666666-6666-6666-6666-100000000001', 'TEST-09 Operateur', 'active'),
    ('66666666-6666-6666-6666-100000000002', 'TEST-09 MRV (contrepartie)', 'active'),
    ('66666666-6666-6666-6666-100000000003', 'TEST-09 Source A', 'active'),
    ('66666666-6666-6666-6666-100000000004', 'TEST-09 Source B', 'active'),
    ('66666666-6666-6666-6666-100000000005', 'TEST-09 Source C', 'active');

INSERT INTO public.aggregators (id, name) VALUES ('66666666-6666-6666-6666-200000000001', 'TEST-09 Regroupement');

INSERT INTO public.opportunities (id, title, coordinator_org_id)
VALUES ('66666666-6666-6666-6666-300000000001', 'TEST-09 Opportunité', '66666666-6666-6666-6666-100000000003');
INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id)
VALUES ('66666666-6666-6666-6666-300000000002', '66666666-6666-6666-6666-300000000001', 'TEST-09 Projet CCF', '66666666-6666-6666-6666-100000000003');

INSERT INTO public.operational_units (id, organization_id, name)
VALUES ('66666666-6666-6666-6666-400000000001', '66666666-6666-6666-6666-100000000002', 'TEST-09 Unité opérationnelle MRV');
INSERT INTO public.projects (id, operational_unit_id, name)
VALUES ('66666666-6666-6666-6666-400000000002', '66666666-6666-6666-6666-400000000001', 'TEST-09 Projet MRV');

DO $$
BEGIN
    INSERT INTO public.ccf_mrv_project_links (ccf_project_id, mrv_project_id, started_by)
    VALUES ('66666666-6666-6666-6666-300000000002', '66666666-6666-6666-6666-400000000002', pg_temp.carbon_test_profile('op'));
END $$;

-- 3 participants CCF (A/B/C) — chacun requis pour create_credit_issuance() (§4/§7).
INSERT INTO public.project_participants (project_id, organization_id, status) VALUES
    ('66666666-6666-6666-6666-300000000002', '66666666-6666-6666-6666-100000000003', 'active'),
    ('66666666-6666-6666-6666-300000000002', '66666666-6666-6666-6666-100000000004', 'active'),
    ('66666666-6666-6666-6666-300000000002', '66666666-6666-6666-6666-100000000005', 'active');

DO $$
BEGIN
    INSERT INTO public.accredited_verifiers (user_id, accredited_by)
    VALUES (pg_temp.carbon_test_profile('op'), pg_temp.carbon_test_profile('op'));

    -- Corrigé après la première revue statique (point 3) : 'aggadmin' est désormais primary_admin
    -- (autorité économique réelle, is_aggregator_primary_admin()) — 'coadmin' est un co_admin distinct,
    -- sans aucune autorité économique, utilisé pour tester explicitement son rejet.
    INSERT INTO public.aggregator_admins (id, aggregator_id, user_id, role)
    VALUES ('66666666-6666-6666-6666-950000000001', '66666666-6666-6666-6666-200000000001', pg_temp.carbon_test_profile('aggadmin'), 'primary_admin');
    INSERT INTO public.aggregator_admins (id, aggregator_id, user_id, role)
    VALUES ('66666666-6666-6666-6666-950000000002', '66666666-6666-6666-6666-200000000001', pg_temp.carbon_test_profile('coadmin'), 'co_admin');
END $$;

INSERT INTO public.evidence_files (id, project_id, file_url, type, file_hash)
VALUES ('66666666-6666-6666-6666-800000000001', '66666666-6666-6666-6666-400000000002', '/evidence/test-09.pdf', 'verification_report', 'sha256:test-09');
INSERT INTO public.documents (id, owner_org_id, object_type, object_id, title, status)
VALUES ('66666666-6666-6666-6666-700000000001', '66666666-6666-6666-6666-100000000001', 'organization', '66666666-6666-6666-6666-100000000001', 'TEST-09 document de preuve', 'approved');

INSERT INTO public.aggregator_memberships (id, organization_id, aggregator_id, started_at) VALUES
    ('66666666-6666-6666-6666-500000000001', '66666666-6666-6666-6666-100000000003', '66666666-6666-6666-6666-200000000001', clock_timestamp() - interval '30 days'),
    ('66666666-6666-6666-6666-500000000002', '66666666-6666-6666-6666-100000000004', '66666666-6666-6666-6666-200000000001', clock_timestamp() - interval '30 days'),
    ('66666666-6666-6666-6666-500000000003', '66666666-6666-6666-6666-100000000005', '66666666-6666-6666-6666-200000000001', clock_timestamp() - interval '30 days');

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.designate_platform_operator('66666666-6666-6666-6666-100000000001');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

INSERT INTO public.carbon_commercialization_mandates (
    id, aggregator_membership_id, organization_id, aggregator_id, operator_organization_id, scope, granted_by
) VALUES
    ('66666666-6666-6666-6666-600000000001', '66666666-6666-6666-6666-500000000001', '66666666-6666-6666-6666-100000000003',
     '66666666-6666-6666-6666-200000000001', '66666666-6666-6666-6666-100000000001', ARRAY['request_issuance'], pg_temp.carbon_test_profile('op')),
    ('66666666-6666-6666-6666-600000000002', '66666666-6666-6666-6666-500000000002', '66666666-6666-6666-6666-100000000004',
     '66666666-6666-6666-6666-200000000001', '66666666-6666-6666-6666-100000000001', ARRAY['request_issuance'], pg_temp.carbon_test_profile('op')),
    ('66666666-6666-6666-6666-600000000003', '66666666-6666-6666-6666-500000000003', '66666666-6666-6666-6666-100000000005',
     '66666666-6666-6666-6666-200000000001', '66666666-6666-6666-6666-100000000001', ARRAY['request_issuance'], pg_temp.carbon_test_profile('op'));

DO $$
BEGIN
    INSERT INTO public.organization_members (id, organization_id, user_id, org_role, status, activated_at) VALUES
        ('66666666-6666-6666-6666-900000000101', '66666666-6666-6666-6666-100000000001', pg_temp.carbon_test_profile('op'), 'admin', 'active', clock_timestamp() - interval '10 days'),
        ('66666666-6666-6666-6666-900000000102', '66666666-6666-6666-6666-100000000003', pg_temp.carbon_test_profile('orga'), 'admin', 'active', clock_timestamp() - interval '10 days'),
        ('66666666-6666-6666-6666-900000000103', '66666666-6666-6666-6666-100000000004', pg_temp.carbon_test_profile('orgb'), 'admin', 'active', clock_timestamp() - interval '10 days'),
        ('66666666-6666-6666-6666-900000000104', '66666666-6666-6666-6666-100000000005', pg_temp.carbon_test_profile('orgb'), 'admin', 'active', clock_timestamp() - interval '10 days'),
        -- Ajouté après la CINQUIÈME revue statique (correction complémentaire) : simple membre
        -- NON-admin d'ORG_A (org_role='membre'), utilisé par B88bis pour prouver qu'un membre
        -- ordinaire de l'organisation concernée elle-même ne voit pas non plus une proposition
        -- d'override pending, exactement comme un co_admin de regroupement sans lien (B88).
        ('66666666-6666-6666-6666-900000000105', '66666666-6666-6666-6666-100000000003', pg_temp.carbon_test_profile('orgamember'), 'membre', 'active', clock_timestamp() - interval '10 days');
END $$;

INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end, verifier_user_id)
SELECT '66666666-6666-6666-6666-900000000001', '66666666-6666-6666-6666-400000000002', 'completed', current_date - 30, current_date - 20,
       pg_temp.carbon_test_profile('op');

INSERT INTO public.verification_outcomes (id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
SELECT '66666666-6666-6666-6666-910000000001', '66666666-6666-6666-6666-900000000001', 'active', 3, 3, 3,
       '66666666-6666-6666-6666-800000000001', pg_temp.carbon_test_profile('op');

-- ────────────────────────────────────────────────────────────
-- 2bis. Gouvernance distribution_rules — propose + double approbation
--       (AVANT toute émission, indispensable à confirm_credit_sale()).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_prop UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop := public.propose_distribution_rule('66666666-6666-6666-6666-200000000001'::uuid, 10.00, 5.00, 1.0);
    PERFORM public.approve_distribution_rule_as_aggregator_admin(v_prop);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_distribution_rule_as_operator_admin(v_prop);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM set_config('carbon_test09.dr_proposal_main', v_prop::text, false);
END $$;

DO $$
BEGIN
    PERFORM pg_temp.carbon_test_assert('B', 'B1 distribution_rule_proposals : proposition principale activée',
        (SELECT status FROM public.distribution_rule_proposals WHERE id = current_setting('carbon_test09.dr_proposal_main')::uuid) = 'activated');
    PERFORM pg_temp.carbon_test_assert('B', 'B2 distribution_rules : version active créée (effective_to NULL)',
        EXISTS (SELECT 1 FROM public.distribution_rules WHERE aggregator_id = '66666666-6666-6666-6666-200000000001'
            AND effective_to IS NULL AND platform_fee_pct = 10.00 AND reserve_pct = 5.00 AND default_weight = 1.0000));
END $$;

-- ────────────────────────────────────────────────────────────
-- 2ter. Émission à 3 sources (A=1,B=1,C=1) -> issued -> 1 lot de 1 t
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_iss_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_iss_id := public.create_credit_issuance(
        '66666666-6666-6666-6666-910000000001'::uuid,
        jsonb_build_array(
            jsonb_build_object('organization_id','66666666-6666-6666-6666-100000000003','aggregator_membership_id','66666666-6666-6666-6666-500000000001','commercialization_mandate_id','66666666-6666-6666-6666-600000000001','contributed_tco2e',1),
            jsonb_build_object('organization_id','66666666-6666-6666-6666-100000000004','aggregator_membership_id','66666666-6666-6666-6666-500000000002','commercialization_mandate_id','66666666-6666-6666-6666-600000000002','contributed_tco2e',1),
            jsonb_build_object('organization_id','66666666-6666-6666-6666-100000000005','aggregator_membership_id','66666666-6666-6666-6666-500000000003','commercialization_mandate_id','66666666-6666-6666-6666-600000000003','contributed_tco2e',1)
        )
    );
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_iss_id);
    PERFORM public.submit_credit_issuance(v_iss_id, 'TEST-09 Registre');
    PERFORM public.record_registry_issuance(v_iss_id, 'TEST-09-REG-001', clock_timestamp());
    PERFORM set_config('carbon_test09.issuance_main', v_iss_id::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_lot UUID;
    v_lot2 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_lot := public.issue_credit_lot(current_setting('carbon_test09.issuance_main')::uuid, 1, 2024);
    v_lot2 := public.issue_credit_lot(current_setting('carbon_test09.issuance_main')::uuid, 2, 2024);
    PERFORM set_config('carbon_test09.lot_main', v_lot::text, false);
    PERFORM set_config('carbon_test09.lot_second', v_lot2::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 2quater. Émission DÉDIÉE, source unique (ORG_A), utilisée exclusivement par
--          les nouveaux tests de la première revue statique (bornes fee+reserve,
--          point 9 ; cascade externe, point 2) — isolée de l'émission
--          principale pour ne perturber aucune assertion existante.
-- ────────────────────────────────────────────────────────────
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end, verifier_user_id)
SELECT '66666666-6666-6666-6666-900000000002', '66666666-6666-6666-6666-400000000002', 'completed', current_date - 19, current_date - 10,
       pg_temp.carbon_test_profile('op');

INSERT INTO public.verification_outcomes (id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
SELECT '66666666-6666-6666-6666-910000000002', '66666666-6666-6666-6666-900000000002', 'active', 2, 2, 2,
       '66666666-6666-6666-6666-800000000001', pg_temp.carbon_test_profile('op');

DO $$
DECLARE
    v_iss_id UUID;
    v_lot_b UUID;
    v_lot_c UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_iss_id := public.create_credit_issuance(
        '66666666-6666-6666-6666-910000000002'::uuid,
        jsonb_build_array(
            jsonb_build_object('organization_id','66666666-6666-6666-6666-100000000003','aggregator_membership_id','66666666-6666-6666-6666-500000000001','commercialization_mandate_id','66666666-6666-6666-6666-600000000001','contributed_tco2e',2)
        )
    );
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_iss_id);
    PERFORM public.submit_credit_issuance(v_iss_id, 'TEST-09 Registre bis');
    PERFORM public.record_registry_issuance(v_iss_id, 'TEST-09-REG-002', clock_timestamp());
    PERFORM set_config('carbon_test09.issuance_bis', v_iss_id::text, false);

    -- Capacité de cette émission = 2 tCO2e (contributed_tco2e ci-dessus) : exactement 2 lots de
    -- 1 t chacun, ni plus. Corrigé après exécution réelle de GATE 3 (échec réel du garde-fou de
    -- capacité de migration 08, harnais fautif) : l'ancien troisième lot, lot_bypass, dépassait le
    -- plafond d'émission de cette émission. Il a été déplacé vers une émission dédiée et isolée,
    -- voir bloc 2quinquies ci-dessous — nécessaire aussi pour l'isoler de l'annulation externe de
    -- B66, qui cible spécifiquement issuance_bis.
    v_lot_b := public.issue_credit_lot(v_iss_id, 1, 2024);
    v_lot_c := public.issue_credit_lot(v_iss_id, 1, 2024);
    PERFORM set_config('carbon_test09.lot_bounds', v_lot_b::text, false);
    PERFORM set_config('carbon_test09.lot_cascade', v_lot_c::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 2quinquies. Émission DÉDIÉE, complètement indépendante de issuance_bis, pour lot_bypass.
--             Corrigé après exécution réelle de GATE 3 : lot_bypass doit rester utilisable
--             (B68/B69/B78/B91/B92) APRÈS que B66 annule extérieurement toute l'émission
--             issuance_bis (donc voide tous SES lots, lot_bounds et lot_cascade compris — voir
--             B66 plus bas). Isoler lot_bypass sur sa propre émission, sa propre
--             verification_session et son propre verification_outcome garantit structurellement
--             que le cascade externe de B66 ne peut pas l'affecter, sans dépendre d'un ordre
--             d'exécution implicite ni d'une capacité partagée avec issuance_bis.
-- ────────────────────────────────────────────────────────────
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end, verifier_user_id)
SELECT '66666666-6666-6666-6666-900000000004', '66666666-6666-6666-6666-400000000002', 'completed', current_date - 8, current_date - 5,
       pg_temp.carbon_test_profile('op');

INSERT INTO public.verification_outcomes (id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
SELECT '66666666-6666-6666-6666-910000000004', '66666666-6666-6666-6666-900000000004', 'active', 1, 1, 1,
       '66666666-6666-6666-6666-800000000001', pg_temp.carbon_test_profile('op');

DO $$
DECLARE
    v_iss_id UUID;
    v_lot_bp UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_iss_id := public.create_credit_issuance(
        '66666666-6666-6666-6666-910000000004'::uuid,
        jsonb_build_array(
            jsonb_build_object('organization_id','66666666-6666-6666-6666-100000000003','aggregator_membership_id','66666666-6666-6666-6666-500000000001','commercialization_mandate_id','66666666-6666-6666-6666-600000000001','contributed_tco2e',1)
        )
    );
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_iss_id);
    PERFORM public.submit_credit_issuance(v_iss_id, 'TEST-09 Registre bypass');
    PERFORM public.record_registry_issuance(v_iss_id, 'TEST-09-REG-004', clock_timestamp());
    PERFORM set_config('carbon_test09.issuance_bypass', v_iss_id::text, false);

    -- Lot dédié aux tests de bypass direct de la deuxième revue statique (point 2) : jamais
    -- consommé par add_credit_sale_lot()/release_credit_sale_lot(), pour rester libre pour un
    -- INSERT/UPDATE privilégié direct sur credit_sale_lots. Sur sa propre émission (voir
    -- commentaire du bloc 2quinquies) : structurellement à l'abri de toute annulation externe
    -- visant issuance_bis (B66).
    v_lot_bp := public.issue_credit_lot(v_iss_id, 1, 2024);
    PERFORM set_config('carbon_test09.lot_bypass', v_lot_bp::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 3. PARTIE B — comportementale
-- ────────────────────────────────────────────────────────────

-- B3-B8 : cycle de vente complet (create -> add lot -> add cost -> confirm).
DO $$
DECLARE
    v_sale UUID;
    v_csl  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);

    v_sale := public.create_credit_sale('66666666-6666-6666-6666-100000000001'::uuid, 100.00, 'TEST-09 Buyer');
    PERFORM pg_temp.carbon_test_assert('B', 'B3 create_credit_sale : vente draft créée',
        (SELECT status FROM public.credit_sales WHERE id = v_sale) = 'draft');

    v_csl := public.add_credit_sale_lot(v_sale, current_setting('carbon_test09.lot_main')::uuid);
    PERFORM pg_temp.carbon_test_assert('B', 'B4 add_credit_sale_lot : lot passé reserved',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_main')::uuid) = 'reserved');
    PERFORM pg_temp.carbon_test_assert('B', 'B5 add_credit_sale_lot : credit_sales.total_tco2e synchronisé à 1.0000',
        (SELECT total_tco2e FROM public.credit_sales WHERE id = v_sale) = 1.0000);
    PERFORM pg_temp.carbon_test_assert('B', 'B6 add_credit_sale_lot : quantity_tco2e DB-owned = quantité du lot',
        (SELECT quantity_tco2e FROM public.credit_sale_lots WHERE id = v_csl) = 1.0000);

    PERFORM public.add_credit_sale_cost(v_sale, 'registry_fee', 5.00, 'Frais de registre TEST-09', 'Registre XYZ');
    PERFORM pg_temp.carbon_test_assert('B', 'B7 add_credit_sale_cost : coût enregistré (draft)',
        (SELECT amount FROM public.credit_sale_costs WHERE credit_sale_id = v_sale AND cost_type = 'registry_fee') = 5.00);

    PERFORM public.confirm_credit_sale(v_sale);
    PERFORM pg_temp.carbon_test_assert('B', 'B8 confirm_credit_sale : statut confirmed, gross/net figés',
        (SELECT status = 'confirmed' AND gross_amount = 100.00 AND net_distributable_amount = 95.00 FROM public.credit_sales WHERE id = v_sale));
    PERFORM pg_temp.carbon_test_assert('B', 'B9 confirm_credit_sale : lot passé sold',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_main')::uuid) = 'sold');

    PERFORM set_config('carbon_test09.sale_main', v_sale::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B10-B17 : vérification exacte de l'attribution/répartition (calcul de référence en tête de fichier).
DO $$
DECLARE
    v_sale UUID := current_setting('carbon_test09.sale_main')::uuid;
    v_a UUID := '66666666-6666-6666-6666-100000000003';
    v_b UUID := '66666666-6666-6666-6666-100000000004';
    v_c UUID := '66666666-6666-6666-6666-100000000005';
BEGIN
    PERFORM pg_temp.carbon_test_assert('B', 'B10 attribution : A porte le reliquat tCO2e (0,3334)',
        (SELECT allocated_tco2e FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='carbon_revenue') = 0.3334);
    PERFORM pg_temp.carbon_test_assert('B', 'B11 attribution : B/C sans reliquat (0,3333 chacune)',
        (SELECT allocated_tco2e FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 0.3333
        AND (SELECT allocated_tco2e FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_c AND allocation_type='carbon_revenue') = 0.3333);
    PERFORM pg_temp.carbon_test_assert('B', 'B12 attribution : SUM(allocated_tco2e) = total_tco2e exactement (1,0000)',
        (SELECT sum(allocated_tco2e) FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND allocation_type='carbon_revenue') = 1.0000);
    PERFORM pg_temp.carbon_test_assert('B', 'B13 attribution : tco2e_rounding_adjustment non nul UNIQUEMENT sur A',
        (SELECT tco2e_rounding_adjustment FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='carbon_revenue') = 0.0001
        AND (SELECT tco2e_rounding_adjustment FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 0
        AND (SELECT tco2e_rounding_adjustment FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_c AND allocation_type='carbon_revenue') = 0);

    PERFORM pg_temp.carbon_test_assert('B', 'B14 répartition : gross_amount exacts (A=31,68 / B=C=31,66)',
        (SELECT gross_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='carbon_revenue') = 31.68
        AND (SELECT gross_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 31.66
        AND (SELECT gross_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_c AND allocation_type='carbon_revenue') = 31.66);
    PERFORM pg_temp.carbon_test_assert('B', 'B15 répartition : amount_rounding_adjustment non nul UNIQUEMENT sur A (0,01)',
        (SELECT amount_rounding_adjustment FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='carbon_revenue') = 0.01
        AND (SELECT amount_rounding_adjustment FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 0);
    -- B16 recalculé après la QUATRIÈME revue statique (bloqueur 3, TRUNC jamais ROUND pour fee/reserve) :
    -- reserve_amount porte la RÉSERVE VÉRITABLE UNIQUEMENT (1,58, inchangé — 3e décimale tronquée < 5
    -- dans ce scénario) ; net_amount('carbon_revenue') CHANGE (26,94/26,92/26,92, plus 26,93/26,91/26,91)
    -- car fee_amount passe de 3,17 (ROUND) à 3,16 (TRUNC, 3e décimale tronquée >= 5 dans ce scénario).
    PERFORM pg_temp.carbon_test_assert('B', 'B16 répartition : net_amount(carbon_revenue) exacts (A=26,94 / B=C=26,92), reserve_amount(véritable)=1,58 partout',
        (SELECT net_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='carbon_revenue') = 26.94
        AND (SELECT net_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 26.92
        AND (SELECT reserve_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='carbon_revenue') = 1.58
        AND (SELECT reserve_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_c AND allocation_type='carbon_revenue') = 1.58);

    PERFORM pg_temp.carbon_test_assert('B', 'B16bis ligne platform_fee distincte : net_amount=fee_amount (3,16 partout, TRUNC jamais ROUND, bloqueur 3), allocated_tco2e NULL, jamais fusionnée avec reserve',
        (SELECT net_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='platform_fee') = 3.16
        AND (SELECT net_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='platform_fee') = 3.16
        AND (SELECT allocated_tco2e FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='platform_fee') IS NULL
        AND (SELECT reserve_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='platform_fee') = 0);

    PERFORM pg_temp.carbon_test_assert('B', 'B16ter ligne reserve : net_amount=reserve_amount=1,58 (véritable, jamais le frais), fee_amount=0',
        (SELECT net_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='reserve') = 1.58
        AND (SELECT fee_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='reserve') = 0);

    -- B17 corrigé (point 1) : la conservation comptable porte désormais sur TROIS composantes.
    PERFORM pg_temp.carbon_test_assert('B', 'B17 égalité comptable exacte : SUM(net_amount) WHERE type IN (carbon_revenue,reserve,platform_fee) = net_distributable_amount (95,00)',
        (SELECT sum(net_amount) FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND allocation_type IN ('carbon_revenue','reserve','platform_fee')) = 95.00);
    PERFORM pg_temp.carbon_test_assert('B', 'B18 calculation_snapshot renseigné (non vide) sur les 3 lignes carbon_revenue',
        (SELECT count(*) FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND allocation_type='carbon_revenue' AND jsonb_array_length(calculation_snapshot) > 0) = 3);
    -- B19 recompté (point 1) : 3 organisations x 3 types (carbon_revenue/reserve/platform_fee) = 9 lignes.
    PERFORM pg_temp.carbon_test_assert('B', 'B19 rule_snapshot renseigné (non vide) sur les 9 lignes (3 orgs x 3 types)',
        (SELECT count(*) FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND rule_snapshot IS NOT NULL AND rule_snapshot <> '{}'::jsonb) = 9);
    -- B19bis (point 12) : rule_snapshot porte les clés d'ID d'override (NULL ici, aucun override actif à cette confirmation).
    PERFORM pg_temp.carbon_test_assert('B', 'B19bis rule_snapshot.parameters contient les clés fee_override_id/reserve_override_id/weight_override_id (point 12)',
        (SELECT rule_snapshot->'parameters' ? 'fee_override_id' AND rule_snapshot->'parameters' ? 'reserve_override_id' AND rule_snapshot->'parameters' ? 'weight_override_id'
         FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_a AND allocation_type='carbon_revenue'));
END $$;

-- B20-B24 : settle, adjustment, effective_net_distributable_amount, retire.
DO $$
DECLARE
    v_sale UUID := current_setting('carbon_test09.sale_main')::uuid;
    v_adj  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);

    PERFORM public.settle_credit_sale(v_sale, 'WIRE-TEST-09-001');
    PERFORM pg_temp.carbon_test_assert('B', 'B20 settle_credit_sale : statut settled',
        (SELECT status = 'settled' AND settlement_reference = 'WIRE-TEST-09-001' FROM public.credit_sales WHERE id = v_sale));

    v_adj := public.add_credit_sale_adjustment(v_sale, -2.00, 'Correction TEST-09 post-règlement');
    PERFORM pg_temp.carbon_test_assert('B', 'B21 add_credit_sale_adjustment : ajustement enregistré (settled)',
        (SELECT amount FROM public.credit_sale_adjustments WHERE id = v_adj) = -2.00);
    PERFORM pg_temp.carbon_test_assert('B', 'B22 effective_net_distributable_amount = 95,00 + (-2,00) = 93,00',
        public.effective_net_distributable_amount(v_sale) = 93.00);

    PERFORM public.retire_credit_lot(current_setting('carbon_test09.lot_main')::uuid, 'Retrait TEST-09 (compensation volontaire)');
    PERFORM pg_temp.carbon_test_assert('B', 'B23 retire_credit_lot : lot passé retired',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_main')::uuid) = 'retired');

    PERFORM pg_temp.carbon_test_assert('B', 'B24 net_distributable_amount jamais recalculé après settle/adjustment (reste 95,00)',
        (SELECT net_distributable_amount FROM public.credit_sales WHERE id = v_sale) = 95.00);

    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B25-B30 : deuxième vente (draft), lot2, cancel_credit_sale libère tout.
DO $$
DECLARE
    v_sale2 UUID;
    v_csl2  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);

    v_sale2 := public.create_credit_sale('66666666-6666-6666-6666-100000000001'::uuid, 50.00, 'TEST-09 Buyer 2');
    v_csl2 := public.add_credit_sale_lot(v_sale2, current_setting('carbon_test09.lot_second')::uuid);
    PERFORM pg_temp.carbon_test_assert('B', 'B25 vente 2 : lot second reserved',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_second')::uuid) = 'reserved');

    PERFORM public.cancel_credit_sale(v_sale2, 'Annulation TEST-09');
    PERFORM pg_temp.carbon_test_assert('B', 'B26 cancel_credit_sale : statut cancelled',
        (SELECT status = 'cancelled' AND cancel_reason = 'Annulation TEST-09' FROM public.credit_sales WHERE id = v_sale2));
    PERFORM pg_temp.carbon_test_assert('B', 'B27 cancel_credit_sale : lot second repassé available',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_second')::uuid) = 'available');
    PERFORM pg_temp.carbon_test_assert('B', 'B28 cancel_credit_sale : credit_sale_lots.released_at renseigné (reason=sale_cancelled)',
        (SELECT released_at IS NOT NULL AND release_reason = 'sale_cancelled' FROM public.credit_sale_lots WHERE id = v_csl2));

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B29 add_credit_sale_adjustment refusé sur vente cancelled (jamais confirmée)',
        format('SELECT public.add_credit_sale_adjustment(%L::uuid, 1.00, ''test'')', v_sale2),
        'confirmed ou settled');

    PERFORM set_config('carbon_test09.sale_second', v_sale2::text, false);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B30 : réserver de nouveau le lot second (available) sur une 3e vente
-- draft, puis le libérer explicitement (release_credit_sale_lot, distinct
-- du cancel en masse ci-dessus).
DO $$
DECLARE
    v_sale3 UUID;
    v_csl3  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_sale3 := public.create_credit_sale('66666666-6666-6666-6666-100000000001'::uuid, 75.00, 'TEST-09 Buyer 3');
    v_csl3 := public.add_credit_sale_lot(v_sale3, current_setting('carbon_test09.lot_second')::uuid);
    PERFORM public.release_credit_sale_lot(v_csl3, 'Libération explicite TEST-09');
    PERFORM pg_temp.carbon_test_assert('B', 'B30 release_credit_sale_lot : lot repassé available, ligne marquée (jamais supprimée)',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_second')::uuid) = 'available'
        AND (SELECT released_at IS NOT NULL AND release_reason = 'Libération explicite TEST-09' FROM public.credit_sale_lots WHERE id = v_csl3));

    -- confirm_credit_sale refusé : plus aucun lot actif (le seul lot a été libéré ci-dessus).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B31 confirm_credit_sale refusé : aucun lot actif',
        format('SELECT public.confirm_credit_sale(%L::uuid)', v_sale3), 'aucun lot actif');

    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B32-B36 : bypass structurels (append-only / immutabilité).
DO $$
DECLARE
    v_sale UUID := current_setting('carbon_test09.sale_main')::uuid;
    v_alloc_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    SELECT id INTO v_alloc_id FROM public.credit_sale_allocations WHERE credit_sale_id = v_sale LIMIT 1;

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B32 bypass : UPDATE direct sur credit_sale_allocations rejeté (append-only)',
        format('UPDATE public.credit_sale_allocations SET net_amount = 0 WHERE id = %L::uuid', v_alloc_id), 'append-only');
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B33 bypass : DELETE direct sur credit_sale_allocations rejeté',
        format('DELETE FROM public.credit_sale_allocations WHERE id = %L::uuid', v_alloc_id), 'append-only');
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B34 bypass : UPDATE price_per_tco2e sur credit_sales rejeté (immuable)',
        format('UPDATE public.credit_sales SET price_per_tco2e = 999 WHERE id = %L::uuid', v_sale), 'immuables');
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B35 bypass : DELETE direct sur credit_sales rejeté',
        format('DELETE FROM public.credit_sales WHERE id = %L::uuid', v_sale), 'append-only');
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B36 bypass : add_credit_sale_cost refusé sur vente confirmed/settled',
        format('SELECT public.add_credit_sale_cost(%L::uuid, ''other'', 1.00)', v_sale), 'draft');

    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B37-B43 : gouvernance member_distribution_overrides — create puis revoke, même triple approbation.
DO $$
DECLARE
    v_prop_create UUID;
    v_prop_revoke UUID;
    v_override_id UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_create := public.propose_member_distribution_override(
        'create', '66666666-6666-6666-6666-500000000001'::uuid, NULL, 'fee_pct', 7.00,
        '2020-01-01'::date, '2030-12-31'::date, NULL
    );
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_create);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B37 propose_member_distribution_override : proposition pending, 1/3 approbations posées',
        (SELECT status = 'pending' AND organization_admin_approved_by IS NOT NULL AND aggregator_admin_approved_by IS NULL
         FROM public.member_distribution_override_proposals WHERE id = v_prop_create));

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_create);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B38 2/3 approbations posées, toujours pending',
        (SELECT status = 'pending' FROM public.member_distribution_override_proposals WHERE id = v_prop_create));

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_create);
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT activated_override_id INTO v_override_id FROM public.member_distribution_override_proposals WHERE id = v_prop_create;
    PERFORM pg_temp.carbon_test_assert('B', 'B39 3/3 approbations : proposition activated, override créé (fee_pct=7,00, non révoqué)',
        v_override_id IS NOT NULL
        AND (SELECT override_type = 'fee_pct' AND override_value = 7.00 AND revoked_at IS NULL FROM public.member_distribution_overrides WHERE id = v_override_id));

    PERFORM pg_temp.carbon_test_assert('B', 'B40 la vente déjà confirmée n''est pas affectée (rule_snapshot figé, fee_applied_pct=10,00 pour A)',
        (SELECT fee_applied_pct FROM public.credit_sale_allocations WHERE credit_sale_id = current_setting('carbon_test09.sale_main')::uuid
            AND organization_id = '66666666-6666-6666-6666-100000000003' AND allocation_type = 'carbon_revenue') = 10.00);

    -- Révocation : même triple approbation, jamais un chemin à approbation unique (§17 point 5, résidu de clôture).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_revoke := public.propose_member_distribution_override(
        'revoke', '66666666-6666-6666-6666-500000000001'::uuid, v_override_id, NULL, NULL, NULL, NULL, 'Retrait TEST-09'
    );
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_revoke);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_revoke);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_revoke);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B41 révocation activée : revoked_at DB-owned renseigné, non rétroactif',
        (SELECT revoked_at IS NOT NULL AND revoked_by IS NOT NULL AND effective_from = '2020-01-01'::date AND effective_until = '2030-12-31'::date
         FROM public.member_distribution_overrides WHERE id = v_override_id));
    PERFORM pg_temp.carbon_test_assert('B', 'B42 proposition de révocation activated, activated_override_id = target (uniformité de lecture)',
        (SELECT status = 'activated' AND activated_override_id = v_override_id FROM public.member_distribution_override_proposals WHERE id = v_prop_revoke));

    -- Rejet et retrait sur des propositions fraîches, jamais activées.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    DECLARE v_prop_reject UUID; v_prop_withdraw UUID;
    BEGIN
        v_prop_reject := public.propose_member_distribution_override('create', '66666666-6666-6666-6666-500000000001'::uuid, NULL, 'reserve_pct', 3.00, '2026-01-01'::date, '2026-12-31'::date, NULL);
        v_prop_withdraw := public.propose_member_distribution_override('create', '66666666-6666-6666-6666-500000000001'::uuid, NULL, 'weight_multiplier', 1.20, '2026-01-01'::date, '2026-12-31'::date, NULL);
        PERFORM set_config('carbon_test09.mdo_prop_reject', v_prop_reject::text, false);
        PERFORM set_config('carbon_test09.mdo_prop_withdraw', v_prop_withdraw::text, false);
    END;
    PERFORM public.withdraw_member_distribution_override_proposal(current_setting('carbon_test09.mdo_prop_withdraw')::uuid);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B43 withdraw_member_distribution_override_proposal : statut withdrawn',
        (SELECT status FROM public.member_distribution_override_proposals WHERE id = current_setting('carbon_test09.mdo_prop_withdraw')::uuid) = 'withdrawn');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.reject_member_distribution_override_proposal(current_setting('carbon_test09.mdo_prop_reject')::uuid, 'Rejet TEST-09');
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B', 'B44 reject_member_distribution_override_proposal : statut rejected, reject_reason renseigné',
        (SELECT status = 'rejected' AND reject_reason = 'Rejet TEST-09' FROM public.member_distribution_override_proposals WHERE id = current_setting('carbon_test09.mdo_prop_reject')::uuid));
END $$;

-- B45-B47 : gouvernance distribution_rules — reject et withdraw sur des propositions fraîches.
DO $$
DECLARE
    v_prop_reject UUID;
    v_prop_withdraw UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_reject := public.propose_distribution_rule('66666666-6666-6666-6666-200000000001'::uuid, 12.00, 6.00, 1.0);
    v_prop_withdraw := public.propose_distribution_rule('66666666-6666-6666-6666-200000000001'::uuid, 15.00, 8.00, 1.0);
    PERFORM public.withdraw_distribution_rule_proposal(v_prop_withdraw);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B45 withdraw_distribution_rule_proposal : statut withdrawn',
        (SELECT status FROM public.distribution_rule_proposals WHERE id = v_prop_withdraw) = 'withdrawn');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.reject_distribution_rule_proposal(v_prop_reject, 'Rejet TEST-09 (frais trop élevés)');
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B', 'B46 reject_distribution_rule_proposal : statut rejected',
        (SELECT status = 'rejected' AND reject_reason = 'Rejet TEST-09 (frais trop élevés)' FROM public.distribution_rule_proposals WHERE id = v_prop_reject));
    PERFORM pg_temp.carbon_test_assert('B', 'B47 la version active de distribution_rules n''a pas changé (toujours 10,00/5,00)',
        (SELECT count(*) FROM public.distribution_rules WHERE aggregator_id = '66666666-6666-6666-6666-200000000001' AND effective_to IS NULL) = 1);
END $$;

-- B48-B52 : RLS et autorisation.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), false);
    PERFORM pg_temp.carbon_test_assert('B', 'B48 can_view_credit_sale : vrai pour l''opérateur (vendeur)',
        public.can_view_credit_sale(current_setting('carbon_test09.sale_main')::uuid));
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Corrigé après la QUATRIÈME revue statique (point 1) : can_view_credit_sale() ne donne plus la
    -- vente entière à une organisation simplement contributrice via credit_sale_allocations — cette
    -- branche a été retirée (fuite fermée, §17). ORG_A ne voit désormais sa relation à la vente QUE
    -- via can_view_credit_sale_allocation() sur sa PROPRE ligne (voir B79 et suivants, RLS réelle).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM pg_temp.carbon_test_assert('B', 'B49 can_view_credit_sale : désormais FAUX pour ORG_A (organisation simplement contributrice, fuite fermée, point 1)',
        NOT public.can_view_credit_sale(current_setting('carbon_test09.sale_main')::uuid));
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert('B', 'B50 can_view_credit_sale : faux pour un outsider sans aucune relation',
        NOT public.can_view_credit_sale(current_setting('carbon_test09.sale_main')::uuid));

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B51 bypass : outsider ne peut pas proposer une distribution_rule (accès refusé)',
        format('SELECT public.propose_distribution_rule(%L::uuid, 1.0, 1.0, 1.0)', '66666666-6666-6666-6666-200000000001'),
        'accès refusé');
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B52 bypass : outsider ne peut pas confirmer la vente d''autrui',
        format('SELECT public.confirm_credit_sale(%L::uuid)', current_setting('carbon_test09.sale_second')),
        'introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- B53-B55 : événements — présence des événements clés journalisés par ce scénario.
DO $$
DECLARE
    v_sale UUID := current_setting('carbon_test09.sale_main')::uuid;
BEGIN
    PERFORM pg_temp.carbon_test_assert('B', 'B53 événements du cycle de vente principal tous présents',
        EXISTS (SELECT 1 FROM public.carbon_business_events WHERE object_type='credit_sale' AND object_id=v_sale AND event_type='credit_sale_created')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE object_type='credit_sale' AND object_id=v_sale AND event_type='credit_sale_confirmed')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE object_type='credit_sale' AND object_id=v_sale AND event_type='credit_sale_settled')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE object_type='credit_sale_cost' AND event_type='credit_sale_cost_recorded')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE object_type='credit_sale_adjustment' AND event_type='credit_sale_adjustment_recorded')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE object_type='credit_lot' AND object_id=current_setting('carbon_test09.lot_main')::uuid AND event_type='credit_lot_retired'));

    PERFORM pg_temp.carbon_test_assert('B', 'B54 événements de gouvernance distribution_rule (proposed/activated/rejected/withdrawn) tous présents',
        EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type='distribution_rule_proposed')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type='distribution_rule_activated')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type='distribution_rule_rejected')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type='distribution_rule_withdrawn'));

    PERFORM pg_temp.carbon_test_assert('B', 'B55 événements de gouvernance member_distribution_override (proposed/activated/rejected/withdrawn) tous présents',
        EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type='member_distribution_override_proposed')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type='member_distribution_override_activated')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type='member_distribution_override_rejected')
        AND EXISTS (SELECT 1 FROM public.carbon_business_events WHERE event_type='member_distribution_override_withdrawn'));
END $$;

-- ────────────────────────────────────────────────────────────
-- 3bis. NOUVEAUX TESTS — première revue statique (B56-B67) : co_admin
--       rejeté, substitution superadmin (succès et deux refus), trou
--       cross-scope, temporalité après révocation, bornes fee+reserve,
--       weight_multiplier=0, fuite effective_net, cascade externe (point 2,
--       enfin exécutable sans exception), événement/contexte complets.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_prop_co       UUID;
    v_prop_co2      UUID;
    v_prop_super    UUID;
    v_prop_primary  UUID;
    v_prop_orgadmin UUID;
    v_membership1   UUID := '66666666-6666-6666-6666-500000000001';
    v_membership2   UUID := '66666666-6666-6666-6666-500000000002';
    v_prop_fresh    UUID;
    v_override_fresh UUID;
    v_prop_bounds   UUID;
    -- Ajoutées après exécution réelle de GATE 3 : révocation immédiate de l'override B64
    -- (reserve_pct=95, volontairement invalide) pour ne pas contaminer les scénarios positifs
    -- ultérieurs qui réutilisent v_membership1/ORG_A avec la règle générale.
    v_override_bounds      UUID;
    v_prop_bounds_revoke    UUID;
    v_sale4         UUID;
    v_sale5         UUID;
    v_sale6         UUID;
    v_csl6          UUID;
    v_sale_bypass   UUID;
    v_csl_bypass    UUID;
    v_prop_replace  UUID;
    v_sale_costs    UUID;
    v_org_a         UUID := '66666666-6666-6666-6666-100000000003';
    v_op_org        UUID := '66666666-6666-6666-6666-100000000001';
    -- Ajoutées à la DIXIÈME revue statique (bloqueur 2) : preuves positives forcées des constraint
    -- triggers de création/révocation pour le replace B70-B72 (v_msg_b72bis) et pour un chemin 'revoke'
    -- pur, dédié et distinct de B_9e_1 (v_prop_revoke_ok/v_override_revoke_ok/v_msg_revoke_ok).
    v_msg_b72bis      TEXT;
    v_prop_revoke_ok  UUID;
    v_override_revoke_ok UUID;
    v_msg_revoke_ok   TEXT;
    -- Ajoutées à la ONZIÈME revue statique (bloqueur 2) : le fichier annonçait B72ter dans son
    -- commentaire sans qu'aucune assertion réelle n'existe -- v_prop_create_ok isole désormais la
    -- proposition 'create' (jamais réutilisée/écrasée par la proposition 'revoke' qui suit, contrairement
    -- à l'ancien v_prop_revoke_ok partagé) pour permettre la preuve positive dédiée B72ter.
    v_prop_create_ok  UUID;
    v_msg_b72ter      TEXT;
BEGIN
    -- B56/B57 : co_admin (jamais l'autorité économique du regroupement) explicitement rejeté (point 3).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_co := public.propose_distribution_rule('66666666-6666-6666-6666-200000000001'::uuid, 11.00, 6.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('coadmin'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B56 co_admin rejeté pour approve_distribution_rule_as_aggregator_admin (jamais l''autorité économique, point 3)',
        format('SELECT public.approve_distribution_rule_as_aggregator_admin(%L::uuid)', v_prop_co),
        'introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_co2 := public.propose_member_distribution_override('create', v_membership1, NULL, 'reserve_pct', 4.00, '2028-01-01'::date, '2028-12-31'::date, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_co2);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('coadmin'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B57 co_admin rejeté pour approve_member_distribution_override_as_aggregator_admin (point 3)',
        format('SELECT public.approve_member_distribution_override_as_aggregator_admin(%L::uuid)', v_prop_co2),
        'introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B58 : substitution superadmin EXPLICITE et RÉUSSIE pour l'approbation opérateur (point 4) —
    -- 'outsider' n'est ni admin de l'opérateur ni membre d'aucune organisation liée, seul le flag
    -- superadmin du JWT permet l'approbation.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_super := public.propose_distribution_rule('66666666-6666-6666-6666-200000000001'::uuid, 9.00, 4.00, 1.0);
    PERFORM public.approve_distribution_rule_as_aggregator_admin(v_prop_super);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), true);
    PERFORM public.approve_distribution_rule_as_operator_admin(v_prop_super);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B', 'B58 substitution superadmin réussie pour l''approbation opérateur (point 4)',
        (SELECT status = 'activated' FROM public.distribution_rule_proposals WHERE id = v_prop_super));

    -- B59 : le superadmin ne remplace JAMAIS l'approbation primary_admin du regroupement (point 4).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_primary := public.propose_distribution_rule('66666666-6666-6666-6666-200000000001'::uuid, 13.00, 7.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B59 superadmin ne peut jamais se substituer au primary_admin du regroupement',
        format('SELECT public.approve_distribution_rule_as_aggregator_admin(%L::uuid)', v_prop_primary),
        'introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B60 : le superadmin ne remplace JAMAIS l'approbation de l'admin de l'organisation membre (point 4).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_orgadmin := public.propose_member_distribution_override('create', v_membership1, NULL, 'reserve_pct', 2.00, '2029-01-01'::date, '2029-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B60 superadmin ne peut jamais se substituer à l''admin de l''organisation membre',
        format('SELECT public.approve_member_distribution_override_as_organization_admin(%L::uuid)', v_prop_orgadmin),
        'introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B61 : trou cross-scope fermé (point 5) — override créé et maintenu ACTIF sur membership1 (ORG_A),
    -- une proposition 'replace' déposée sous membership2 (ORG_B) visant ce même override doit être rejetée.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_fresh := public.propose_member_distribution_override('create', v_membership1, NULL, 'weight_multiplier', 1.10, '2026-01-01'::date, '2026-12-31'::date, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_fresh);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_fresh);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_fresh);
    PERFORM pg_temp.carbon_test_clear_actor();
    SELECT activated_override_id INTO v_override_fresh FROM public.member_distribution_override_proposals WHERE id = v_prop_fresh;
    -- Conservé pour le nouveau bloc de tests de la deuxième revue statique (point 12), qui réutilise cet
    -- override encore actif pour un 'replace' légitime sous la BONNE adhésion.
    PERFORM set_config('carbon_test09.override_fresh', v_override_fresh::text, false);

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orgb'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B61 trou cross-scope fermé : target_override_id d''une autre adhésion rejeté (point 5)',
        format('SELECT public.propose_member_distribution_override(''replace'', %L::uuid, %L::uuid, ''weight_multiplier'', 1.20, ''2026-01-01''::date, ''2026-12-31''::date, NULL)', v_membership2, v_override_fresh),
        'n''appartient pas à cette adhésion');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B62 : sélection temporelle corrigée (point 6) — l'override fee_pct de ORG_A (B37-39) a été révoqué
    -- (B41) ; une NOUVELLE vente confirmée maintenant ne doit PAS le récupérer. Corrigé après exécution
    -- réelle de GATE 3 : B58 (plus haut) a entre-temps activé une NOUVELLE règle générale (9,00/4,00) pour
    -- ce même regroupement, remplaçant la règle d'origine (10,00/5,00) — la règle applicable est celle
    -- active au confirmed_at de CETTE vente (sans rétroactivité), donc désormais 9,00, jamais 10,00 (règle
    -- remplacée par B58) ni 7,00 (override révoqué).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_sale4 := public.create_credit_sale(v_op_org, 40.00, 'TEST-09 Buyer 4 (temporalite)');
    PERFORM public.add_credit_sale_lot(v_sale4, current_setting('carbon_test09.lot_second')::uuid);
    PERFORM public.confirm_credit_sale(v_sale4);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B', 'B62 temporalité après révocation : fee_applied_pct = 9,00 (règle générale active, remplacée par B58), jamais 7,00 (override révoqué) ni 10,00 (ancienne règle générale)',
        (SELECT fee_applied_pct FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale4 AND organization_id=v_org_a AND allocation_type='carbon_revenue') = 9.00);

    -- B63 : weight_multiplier=0 rejeté par les bornes durcies (point 9) — jamais >=0, strictement >0.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B63 weight_multiplier=0 rejeté (bornes durcies, point 9)',
        format('SELECT public.propose_member_distribution_override(''create'', %L::uuid, NULL, ''weight_multiplier'', 0, ''2027-01-01''::date, ''2027-12-31''::date, NULL)', v_membership1),
        'value_bounds_check');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B64 : fee+reserve>100 après résolution des overrides rejeté à la confirmation (point 9) —
    -- override reserve_pct=95 sur ORG_A (règle générale fee=9,00, remplacée par B58 avant ce point) =>
    -- 9+95=104>100 (corrigé après exécution réelle de GATE 3 ; commentaire seul, la borne reste violée
    -- quelle que soit la règle générale active).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_bounds := public.propose_member_distribution_override('create', v_membership1, NULL, 'reserve_pct', 95.00, '2020-01-01'::date, '2035-12-31'::date, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_bounds);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_bounds);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_bounds);

    v_sale5 := public.create_credit_sale(v_op_org, 10.00, 'TEST-09 Buyer 5 (bornes)');
    PERFORM public.add_credit_sale_lot(v_sale5, current_setting('carbon_test09.lot_bounds')::uuid);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B64 fee+reserve effectifs > 100 rejeté à confirm_credit_sale (bornes, point 9)',
        format('SELECT public.confirm_credit_sale(%L::uuid)', v_sale5),
        'Bornes violées');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Nettoyage fixture B64 (corrigé après exécution réelle de GATE 3) : l'override reserve_pct=95
    -- créé ci-dessus pour B64 reste actif sur v_membership1/ORG_A si on ne le révoque pas explicitement,
    -- et contamine alors tout scénario positif ultérieur réutilisant cette adhésion (ex. 3quindecies) --
    -- confirm_credit_sale() y échoue légitimement sur le même contrôle de bornes, mais hors contexte.
    -- Révocation via le même flux à triple approbation déjà utilisé ailleurs dans ce fichier.
    SELECT activated_override_id INTO v_override_bounds
    FROM public.member_distribution_override_proposals WHERE id = v_prop_bounds;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_bounds_revoke := public.propose_member_distribution_override('revoke', v_membership1, v_override_bounds, NULL, NULL, NULL, NULL, 'Nettoyage fixture B64 après test de borne > 100');
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_bounds_revoke);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_bounds_revoke);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_bounds_revoke);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B65 : fuite effective_net_distributable_amount fermée (point 8) — un outsider sans aucune
    -- relation avec la vente ne peut plus lire le montant net effectif.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B65 effective_net_distributable_amount refusé pour un outsider (fuite RLS fermée, point 8)',
        format('SELECT public.effective_net_distributable_amount(%L::uuid)', current_setting('carbon_test09.sale_main')),
        'accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B66 : cascade externe désormais exécutable sans exception (point 2) — corrigé après la DEUXIÈME
    -- revue statique (point 5) : released_by porte désormais l'acteur réel (auth.uid() propagé depuis
    -- record_external_cancellation(), ici le profil 'op'), plus jamais NULL pour ce cas système.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_sale6 := public.create_credit_sale(v_op_org, 20.00, 'TEST-09 Buyer 6 (cascade externe)');
    v_csl6 := public.add_credit_sale_lot(v_sale6, current_setting('carbon_test09.lot_cascade')::uuid);
    PERFORM public.record_external_cancellation(
        current_setting('carbon_test09.issuance_bis')::uuid, current_date, 'TEST-09-EXT-CANCEL',
        '66666666-6666-6666-6666-700000000001'::uuid
    );
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B', 'B66 cascade externe : credit_sale_lots libérée (released_by = acteur réel, jamais NULL, point 5), release_reason système, lot voided, vente restée draft',
        (SELECT released_at IS NOT NULL AND released_by = pg_temp.carbon_test_profile('op') AND release_reason = 'external_cancellation_cascade' FROM public.credit_sale_lots WHERE id = v_csl6)
        AND (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_cascade')::uuid) = 'voided'
        AND (SELECT status FROM public.credit_sales WHERE id = v_sale6) = 'draft');

    -- B67 : événement d'allocation corrigé (point 11) — object_id = le vrai id de la ligne
    -- credit_sale_allocations (jamais credit_sale_id), acteur renseigné (jamais NULL).
    PERFORM pg_temp.carbon_test_assert('B', 'B67 événement credit_sale_allocation_recorded : object_id = vraie ligne d''allocation, actor_id renseigné (point 11)',
        EXISTS (
            SELECT 1 FROM public.carbon_business_events e
            JOIN public.credit_sale_allocations a ON a.id = e.object_id
            WHERE e.object_type = 'credit_sale_allocation' AND e.event_type = 'credit_sale_allocation_recorded'
              AND a.credit_sale_id = current_setting('carbon_test09.sale_main')::uuid
              AND e.actor_id IS NOT NULL
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.carbon_business_events e
            WHERE e.object_type = 'credit_sale_allocation' AND e.event_type = 'credit_sale_allocation_recorded'
              AND e.object_id = current_setting('carbon_test09.sale_main')::uuid
        ));

    -- B68 (deuxième revue statique, point 2) : bypass direct — INSERT privilégié dans
    -- credit_sale_lots SANS passer par add_credit_sale_lot(). Les deux triggers ajoutés en
    -- réponse au point 2 (trg_carbon_sync_credit_lot_status_on_sale_lot_insert/_release) sont
    -- les propriétaires structurels de credit_lots.commercial_status : ils doivent réagir
    -- identiquement, que l'écriture vienne de la RPC ou d'un accès direct.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_sale_bypass := public.create_credit_sale(v_op_org, 5.00, 'TEST-09 Buyer bypass (point 2)');
    INSERT INTO public.credit_sale_lots (credit_sale_id, credit_lot_id)
    VALUES (v_sale_bypass, current_setting('carbon_test09.lot_bypass')::uuid)
    RETURNING id INTO v_csl_bypass;
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_assert('B', 'B68 bypass direct INSERT credit_sale_lots (hors RPC) : lot automatiquement reserved (propriétaire structurel, point 2)',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_bypass')::uuid) = 'reserved');

    -- B69 (point 2) : bypass direct — UPDATE privilégié (libération) SANS passer par
    -- release_credit_sale_lot(). Le lot doit repasser automatiquement à 'available'.
    UPDATE public.credit_sale_lots
    SET released_at = clock_timestamp(), released_by = pg_temp.carbon_test_profile('op'), release_reason = 'test_bypass_direct_point2'
    WHERE id = v_csl_bypass;
    PERFORM pg_temp.carbon_test_assert('B', 'B69 bypass direct UPDATE credit_sale_lots (hors RPC) : lot automatiquement available (propriétaire structurel, point 2)',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_bypass')::uuid) = 'available');

    -- B70/B71/B72 (deuxième revue statique, points 4 et 12) : scénario 'replace' LÉGITIME sous la
    -- BONNE adhésion (v_membership1/ORG_A), ciblant l'override encore actif v_override_fresh (créé
    -- en B61, conservé exprès via set_config pour ce bloc). Vérifie : (a) revoked_by = l'acteur de
    -- la DERNIÈRE approbation (operator admin, 'op'), jamais proposed_by (ici 'orga', point 4) ;
    -- (b) OLD.revoked_at = NEW.created_at strictement égaux (même v_now capturé une seule fois,
    -- point 12) ; (c) l'événement d'activation porte actor_id ('op') ET organization_id (ORG_A,
    -- point 4).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_replace := public.propose_member_distribution_override('replace', v_membership1, current_setting('carbon_test09.override_fresh')::uuid, 'weight_multiplier', 1.15, '2026-01-01'::date, '2026-12-31'::date, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_replace);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_replace);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_replace);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B70 replace légitime : revoked_by = dernière approbation (op), jamais proposed_by (orga) (point 4)',
        (SELECT revoked_by FROM public.member_distribution_overrides WHERE id = current_setting('carbon_test09.override_fresh')::uuid) = pg_temp.carbon_test_profile('op')
        AND (SELECT revoked_by FROM public.member_distribution_overrides WHERE id = current_setting('carbon_test09.override_fresh')::uuid) <> pg_temp.carbon_test_profile('orga'));

    PERFORM pg_temp.carbon_test_assert('B', 'B71 replace légitime : OLD.revoked_at = NEW.created_at, exactement égaux (même v_now, point 12)',
        (SELECT revoked_at FROM public.member_distribution_overrides WHERE id = current_setting('carbon_test09.override_fresh')::uuid)
        = (SELECT created_at FROM public.member_distribution_overrides WHERE proposal_id = v_prop_replace));

    PERFORM pg_temp.carbon_test_assert('B', 'B72 replace légitime : événement activated porte actor_id (op) et organization_id (ORG_A) (point 4)',
        EXISTS (
            SELECT 1 FROM public.carbon_business_events
            WHERE object_type = 'member_distribution_override'
              AND event_type = 'member_distribution_override_activated'
              AND object_id = (SELECT activated_override_id FROM public.member_distribution_override_proposals WHERE id = v_prop_replace)
              AND actor_id = pg_temp.carbon_test_profile('op')
              AND organization_id = v_org_a
        ));

    -- B72bis (DIXIÈME revue statique, bloqueur 2, TEST POSITIF OBLIGATOIRE) : le replace légitime
    -- B70-B72 ci-dessus doit forcer IMMÉDIATEMENT les DEUX constraint triggers concernés -- création du
    -- NOUVEL override (proposal_id = v_prop_replace) ET révocation de l'ANCIEN (v_override_fresh,
    -- OLD.revoked_at/revocation_proposal_id = v_prop_replace) -- et ne produire AUCUNE erreur. Sans
    -- cette preuve explicite, rien ne démontrait que le trigger de révocation CORRIGÉ (bloqueur 2 :
    -- branche proposal_type='replace' désormais acceptée) accepte réellement ce flux au COMMIT. Forcé
    -- ICI, immédiatement après B70-B72 -- avant même que B132 (bien plus bas) ne force le MÊME trigger
    -- de révocation pour un événement totalement différent -- afin de vider la file d'attente différée
    -- de CET événement maintenant : SET CONSTRAINTS ... IMMEDIATE force l'évaluation de TOUS les
    -- événements actuellement en attente pour ce trigger, jamais seulement le dernier posé -- sans ce
    -- nettoyage explicite ici, B132 aurait été le PREMIER à forcer ce trigger, et aurait donc capturé
    -- (et risqué de mal attribuer) ce contrôle différé resté en attente depuis B70, en plus du sien.
    BEGIN
        SET CONSTRAINTS trg_carbon_check_member_distribution_override_creation_integrity IMMEDIATE;
        SET CONSTRAINTS trg_carbon_check_member_distribution_override_revocation_integrity IMMEDIATE;
        v_msg_b72bis := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg_b72bis := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B72bis (dixième revue) : replace légitime B70-B72 force les DEUX constraint triggers (création + révocation) IMMEDIATE sans aucune erreur -- preuve positive que la branche replace du trigger de révocation corrigé (bloqueur 2) accepte réellement ce flux, et vide la file différée avant B132', v_msg_b72bis IS NULL, v_msg_b72bis);
    SET CONSTRAINTS trg_carbon_check_member_distribution_override_creation_integrity DEFERRED;
    SET CONSTRAINTS trg_carbon_check_member_distribution_override_revocation_integrity DEFERRED;

    -- B72ter/B72quater (ONZIÈME revue statique, bloqueur 2 -- B72ter enfin RÉELLEMENT codée, jamais
    -- seulement annoncée en commentaire) : chemin positif 'revoke' PUR, dédié et ENTIÈREMENT DISTINCT de
    -- l'override B_9e_1 (section 3duodecies, plus bas, réservé aux preuves négatives B132/B134) --
    -- création légitime (flux RPC réel, 3/3) PUIS révocation légitime (flux RPC réel, 3/3, jamais un
    -- bypass), chaque contrainte forcée IMMEDIATE juste après l'événement qui la concerne : DOIT passer
    -- sans aucune erreur, et chaque forçage vide sa PROPRE file différée avant que B131 (bien plus bas,
    -- trg_carbon_check_member_distribution_override_creation_integrity) et B132 (bien plus bas,
    -- trg_carbon_check_member_distribution_override_revocation_integrity) ne forcent les MÊMES triggers
    -- pour des événements totalement différents -- B130, plus bas également, force un trigger distinct
    -- (trg_carbon_check_distribution_rule_proposal_integrity, sur distribution_rules) et n'est donc
    -- jamais concerné par cette file d'attente-ci.
    -- v_membership2 appartient à ORG_B (...100000000004) : l'acteur légitime pour proposer/approuver
    -- côté organisation sur cette adhésion est 'orgb' (admin de ORG_B), jamais 'orga' (admin de ORG_A,
    -- ...100000000003) — même convention que B61 plus haut, qui utilise déjà 'orgb' pour v_membership2.
    -- Corrigé après exécution réelle de GATE 3 (échec réel du contrôle d'autorisation de production,
    -- harnais fautif : propose_member_distribution_override() a correctement rejeté 'orga' sur une
    -- adhésion de ORG_B).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orgb'), false);
    v_prop_create_ok := public.propose_member_distribution_override('create', v_membership2, NULL, 'reserve_pct', 3.50, '2029-01-01'::date, '2029-12-31'::date, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_create_ok);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_create_ok);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_create_ok);
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT activated_override_id INTO v_override_revoke_ok
    FROM public.member_distribution_override_proposals WHERE id = v_prop_create_ok;

    -- B72ter (ONZIÈME revue statique, bloqueur 2) : AVANT de déposer la proposition 'revoke', force
    -- IMMEDIATE le constraint trigger de CRÉATION pour l'override dédié v_override_revoke_ok tout juste
    -- activé -- preuve positive dédiée que cette création 3/3 passe le trigger de création corrigé, et
    -- purge sa propre file différée avant que B131 (bien plus bas) ne force le même trigger pour un
    -- événement totalement distinct.
    BEGIN
        SET CONSTRAINTS trg_carbon_check_member_distribution_override_creation_integrity IMMEDIATE;
        v_msg_b72ter := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg_b72ter := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B72ter (onzième revue) : création 3/3 de l''override dédié v_override_revoke_ok (proposition activated, activated_override_id correspondant exactement) force le constraint trigger de création IMMEDIATE sans aucune erreur',
        v_msg_b72ter IS NULL
        AND EXISTS (
            SELECT 1 FROM public.member_distribution_override_proposals
            WHERE id = v_prop_create_ok AND status = 'activated' AND activated_override_id = v_override_revoke_ok
        )
        AND EXISTS (SELECT 1 FROM public.member_distribution_overrides WHERE id = v_override_revoke_ok),
        v_msg_b72ter);
    SET CONSTRAINTS trg_carbon_check_member_distribution_override_creation_integrity DEFERRED;

    -- Même correction que pour v_prop_create_ok ci-dessus : v_membership2 appartient à ORG_B, acteur
    -- légitime = 'orgb'.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orgb'), false);
    v_prop_revoke_ok := public.propose_member_distribution_override('revoke', v_membership2, v_override_revoke_ok, NULL, NULL, NULL, NULL, 'TEST-09 dixième revue : chemin positif revoke pur');
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_revoke_ok);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_revoke_ok);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_revoke_ok);
    PERFORM pg_temp.carbon_test_clear_actor();

    BEGIN
        SET CONSTRAINTS trg_carbon_check_member_distribution_override_revocation_integrity IMMEDIATE;
        v_msg_revoke_ok := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg_revoke_ok := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B72quater (dixième revue) : chemin revoke PUR (3/3 approuvé, réellement activated, override dédié distinct de B_9e_1) force le constraint trigger de révocation IMMEDIATE sans aucune erreur', v_msg_revoke_ok IS NULL, v_msg_revoke_ok);
    SET CONSTRAINTS trg_carbon_check_member_distribution_override_revocation_integrity DEFERRED;

    -- B73/B74 (point 9, fuite D13) : release_credit_sale_lot() — un outsider reçoit EXACTEMENT le
    -- même message pour un UUID RÉEL existant (ligne active de v_sale4/lot_second) mais inaccessible
    -- que pour un UUID INVENTÉ — aucune fuite d'existence.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B73 release_credit_sale_lot() : outsider + UUID réel inaccessible -> message générique (point 9)',
        format('SELECT public.release_credit_sale_lot(%L::uuid, ''test'')',
            (SELECT id FROM public.credit_sale_lots WHERE credit_sale_id = v_sale4 AND released_at IS NULL)),
        'introuvable, déjà libérée, ou accès refusé');
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B74 release_credit_sale_lot() : outsider + UUID inventé -> message IDENTIQUE à B73 (point 9)',
        format('SELECT public.release_credit_sale_lot(%L::uuid, ''test'')', gen_random_uuid()),
        'introuvable, déjà libérée, ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B75/B76 (point 9, fuite D13) : propose_member_distribution_override() — même vérification,
    -- UUID d'adhésion réel (v_membership1) mais inaccessible vs UUID inventé, message identique.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B75 propose_member_distribution_override() : outsider + adhésion réelle inaccessible -> message générique (point 9)',
        format('SELECT public.propose_member_distribution_override(''create'', %L::uuid, NULL, ''weight_multiplier'', 1.05, ''2031-01-01''::date, ''2031-12-31''::date, NULL)', v_membership1),
        'introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B76 propose_member_distribution_override() : outsider + UUID inventé -> message IDENTIQUE à B75 (point 9)',
        format('SELECT public.propose_member_distribution_override(''create'', %L::uuid, NULL, ''weight_multiplier'', 1.05, ''2031-01-01''::date, ''2031-12-31''::date, NULL)', gen_random_uuid()),
        'introuvable ou accès refusé');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B77 (deuxième revue statique, point 10) : platform_fee_pct + reserve_pct > 100 rejeté DÈS
    -- propose_distribution_rule() par distribution_rule_proposals_fee_reserve_bounds_check — jamais
    -- seulement à l'activation (distribution_rules_fee_reserve_bounds_check, symétrique).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B77 fee+reserve > 100 rejeté à la proposition (bornes économiques, point 10)',
        format('SELECT public.propose_distribution_rule(%L::uuid, 60.00, 45.00, 1.0)', '66666666-6666-6666-6666-200000000001'::uuid),
        'distribution_rule_proposals_fee_reserve_bounds_check');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B78 (point 10) : confirm_credit_sale() rejette explicitement quand la somme des coûts déclarés
    -- dépasse le montant brut, AVANT le calcul de net_distributable_amount (lot_bypass réutilisé,
    -- redevenu available après B69).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_sale_costs := public.create_credit_sale(v_op_org, 1.00, 'TEST-09 Buyer costs (point 10)');
    PERFORM public.add_credit_sale_lot(v_sale_costs, current_setting('carbon_test09.lot_bypass')::uuid);
    PERFORM public.add_credit_sale_cost(v_sale_costs, 'registry_fee', 50.00);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B78 confirm_credit_sale() : SUM(costs) > gross_amount rejeté explicitement (point 10)',
        format('SELECT public.confirm_credit_sale(%L::uuid)', v_sale_costs),
        'la somme des coûts déclarés');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 3ter. NOUVEAUX TESTS — QUATRIÈME revue statique :
--   Point 1 — RLS par objet : can_view_credit_sale_allocation() (nouvelle,
--             une organisation voit sa PROPRE ligne, jamais la vente entière
--             via cette voie) ; visibilité des propositions limitée aux
--             approbateurs réellement requis (primary_admin du regroupement,
--             admin de l'organisation concernée selon le type, proposant,
--             superadmin) — jamais co_admin ni simple membre.
--   Point 2 — SET LOCAL ROLE authenticated + JWT réel : SELECT directs SOUS
--             POLICY RLS elle-même (jamais seulement les helpers can_view_*()
--             appelés en isolation, qui ne prouvent que la fonction, pas la
--             policy qui l'invoque réellement). SET LOCAL est annulé au
--             ROLLBACK final de ce fichier ; RESET ROLE explicite après
--             chaque requête, jamais laissé actif entre deux blocs.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_sale       UUID := current_setting('carbon_test09.sale_main')::uuid;
    v_org_a      UUID := '66666666-6666-6666-6666-100000000003';
    v_aggregator UUID := '66666666-6666-6666-6666-200000000001';
    v_prop_dr    UUID;
    v_prop_mdo   UUID;
    v_count      BIGINT;
BEGIN
    -- B79/B80 : can_view_credit_sale_allocation() — nouveau helper par ligne (point 1). ORG_A voit
    -- sa propre ligne d'allocation (branche organisation membre) ; un outsider ne la voit pas, même en
    -- ciblant explicitement l'organization_id d'ORG_A en argument (jamais un contournement par ID).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM pg_temp.carbon_test_assert('B', 'B79 can_view_credit_sale_allocation() : vrai pour ORG_A sur sa propre ligne (point 1)',
        public.can_view_credit_sale_allocation(v_sale, v_org_a));
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert('B', 'B80 can_view_credit_sale_allocation() : faux pour un outsider, même en visant l''organization_id d''ORG_A (point 1)',
        NOT public.can_view_credit_sale_allocation(v_sale, v_org_a));
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B81-B85 : RLS RÉELLE (point 2) — SET LOCAL ROLE authenticated + JWT, SELECT directs contre les
    -- policies elles-mêmes.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_sale_allocations WHERE credit_sale_id = v_sale AND organization_id = v_org_a;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B81 RLS réelle : ORG_A voit ses 3 lignes credit_sale_allocations (carbon_revenue/reserve/platform_fee) sous policy réelle (point 2)', v_count = 3);

    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_sales WHERE id = v_sale;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B82 RLS réelle : ORG_A ne voit PLUS la vente entière (credit_sales), fuite fermée (point 1, corrige l''ancien B49)', v_count = 0);

    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_sale_lots WHERE credit_sale_id = v_sale;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B83 RLS réelle : ORG_A ne voit pas credit_sale_lots de la vente (point 1)', v_count = 0);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_sales WHERE id = v_sale;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B84 RLS réelle : l''opérateur (vendeur) voit toujours la vente entière sous policy réelle (visibilité intacte)', v_count = 1);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.credit_sale_allocations WHERE credit_sale_id = v_sale;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B85 RLS réelle : un outsider ne voit AUCUNE ligne credit_sale_allocations de cette vente (0/9, toutes organisations confondues)', v_count = 0);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B86-B90 : visibilité des PROPOSITIONS en attente (point 1) — approbateurs réellement requis
    -- uniquement, jamais co_admin ni simple membre. Propositions FRAÎCHES dédiées, jamais approuvées
    -- dans ce bloc (retirées par leur propre proposant en fin de bloc, jamais laissées pending
    -- orphelines).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr := public.propose_distribution_rule(v_aggregator, 9.00, 4.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('coadmin'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.distribution_rule_proposals WHERE id = v_prop_dr;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B86 RLS réelle : co_admin (sans autorité économique) ne voit PAS la proposition distribution_rule pending (point 1)', v_count = 0);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.distribution_rule_proposals WHERE id = v_prop_dr;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B87 RLS réelle : le primary_admin du regroupement (approbateur réellement requis) voit la proposition (point 1)', v_count = 1);
    PERFORM public.withdraw_distribution_rule_proposal(v_prop_dr);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_mdo := public.propose_member_distribution_override(
        'create', '66666666-6666-6666-6666-500000000001'::uuid, NULL, 'reserve_pct', 2.50,
        '2032-01-01'::date, '2032-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('coadmin'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.member_distribution_override_proposals WHERE id = v_prop_mdo;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B88 RLS réelle : co_admin du regroupement ne voit PAS la proposition member_distribution_override pending (point 1)', v_count = 0);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B88bis (correction complémentaire, CINQUIÈME revue statique) : un simple membre NON-admin
    -- d'ORG_A elle-même (org_role='membre', aucune autorité d'approbation) ne voit pas non plus la
    -- proposition pending, alors même qu'elle cible sa propre organisation — distinct de B88 (qui
    -- prouve le même résultat pour un co_admin de regroupement sans lien avec ORG_A). Seul l'admin
    -- d'ORG_A (approbateur réellement requis, B89 ci-dessous) doit la voir.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orgamember'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.member_distribution_override_proposals WHERE id = v_prop_mdo;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B88bis RLS réelle : simple membre NON-admin d''ORG_A (organisation concernée elle-même, sans autorité d''approbation) ne voit PAS la proposition pending (correction complémentaire, cinquième revue)', v_count = 0);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.member_distribution_override_proposals WHERE id = v_prop_mdo;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B89 RLS réelle : l''admin de l''organisation concernée (ORG_A, approbateur réellement requis) voit la proposition (point 1)', v_count = 1);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.member_distribution_override_proposals WHERE id = v_prop_mdo;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B90 RLS réelle : le superadmin voit la proposition (voie de secours toujours disponible)', v_count = 1);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM public.withdraw_member_distribution_override_proposal(v_prop_mdo);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 3quater. NOUVEAUX TESTS — QUATRIÈME revue statique (points 3 et 9).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_csl_bp2    UUID;
    v_sale_zero  UUID;
    v_op_org     UUID := '66666666-6666-6666-6666-100000000001';
    v_aggregator UUID := '66666666-6666-6666-6666-200000000001';
    v_org_a      UUID := '66666666-6666-6666-6666-100000000003';
    v_insert_ok  BOOLEAN := false;
    v_insert_err TEXT := NULL;
BEGIN
    -- B91/B92 (point 3) : external_cancellation_cascade ne peut plus être utilisé directement pour
    -- libérer un lot simplement 'reserved' (jamais voided avec void_cause='external_cancellation') —
    -- le nouveau garde-fou BEFORE UPDATE de credit_sale_lots rejette ce contournement. lot_bypass est
    -- réservé via v_sale_costs (B78) et jamais libéré depuis : toujours 'reserved' à ce stade (B66
    -- reste le seul chemin légitime : le lot y est réellement voided AVANT la libération, via le
    -- cascade système record_external_cancellation()).
    SELECT id INTO v_csl_bp2 FROM public.credit_sale_lots
    WHERE credit_lot_id = current_setting('carbon_test09.lot_bypass')::uuid AND released_at IS NULL;

    PERFORM pg_temp.carbon_test_assert('B', 'B91 lot_bypass toujours reserved (jamais voided) à ce stade — précondition du test (point 3)',
        (SELECT commercial_status FROM public.credit_lots WHERE id = current_setting('carbon_test09.lot_bypass')::uuid) = 'reserved');

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B92 bypass direct : release_reason=''external_cancellation_cascade'' rejeté sur un lot simplement reserved (jamais voided/external_cancellation, point 3)',
        format('UPDATE public.credit_sale_lots SET released_at = clock_timestamp(), released_by = %L::uuid, release_reason = ''external_cancellation_cascade'' WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('op'), v_csl_bp2),
        'n''est valide que si le lot référencé');

    -- B93/B94 (point 9) : une attribution arrondie à 0,0000 pour une source historiquement positive
    -- est désormais ACCEPTÉE (CHECK relaxé de > 0 à >= 0, sur la ligne 'carbon_revenue' uniquement) —
    -- la provenance réelle (contribution/ratio non nuls) reste tracée dans calculation_snapshot,
    -- jamais perdue par l'arrondi d'affichage. Testé par INSERT direct (jamais bloqué structurellement,
    -- seuls UPDATE/DELETE le sont, même raisonnement que B32/B33) sur une vente draft fraîche dédiée
    -- (jamais confirmée dans ce bloc, pour ne créer aucune ligne concurrente sur la même paire
    -- organisation/type et ne pas violer credit_sale_allocations_unique).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    v_sale_zero := public.create_credit_sale(v_op_org, 1.00, 'TEST-09 Buyer zero-rounding (point 9)');
    -- Corrigé après la quatrième revue statique (bloqueur 1) : l'ancienne rédaction appelait
    -- carbon_test_assert('B93', ...) dans les DEUX branches mutuellement exclusives d'un même
    -- BEGIN/EXCEPTION — une seule s'exécute réellement à l'exécution, mais le texte source comptait
    -- deux occurrences du même libellé, faussant le comptage mécanique par grep (gate annoncé à 128,
    -- réel à 127). Le résultat (succès/échec + message) est désormais capturé dans des variables,
    -- PERFORM carbon_test_assert() n'est appelé qu'UNE SEULE fois, après le bloc.
    BEGIN
        INSERT INTO public.credit_sale_allocations (
            credit_sale_id, organization_id, aggregator_id, allocation_type, allocated_tco2e,
            gross_amount, fee_applied_pct, reserve_applied_pct, weight_applied, fee_amount, reserve_amount, net_amount,
            rule_snapshot, calculation_snapshot
        ) VALUES (
            v_sale_zero, v_org_a, v_aggregator, 'carbon_revenue', 0.0000,
            0.01, 10.00, 5.00, 1.0, 0.00, 0.00, 0.01,
            '{}'::jsonb,
            jsonb_build_object('contributed_tco2e', 0.00000001, 'source_ratio', 0.00000001, 'note', 'TEST-09 point 9 zero-rounding')
        );
        v_insert_ok := true;
    EXCEPTION WHEN OTHERS THEN
        v_insert_ok := false;
        v_insert_err := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B93 allocated_tco2e = 0,0000 sur une ligne carbon_revenue : ACCEPTÉ (CHECK relaxé à >= 0, point 9)', v_insert_ok, v_insert_err);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B94 la ligne allocated_tco2e=0,0000 est bien persistée, provenance (contribution réelle non nulle) conservée dans calculation_snapshot (point 9)',
        EXISTS (
            SELECT 1 FROM public.credit_sale_allocations
            WHERE credit_sale_id = v_sale_zero AND organization_id = v_org_a AND allocation_type = 'carbon_revenue'
              AND allocated_tco2e = 0.0000
              AND (calculation_snapshot->>'contributed_tco2e')::numeric > 0
        ));
END $$;

-- ────────────────────────────────────────────────────────────
-- 3quinquies. NOUVEAUX TESTS — CINQUIÈME revue statique (bloqueur 3) :
-- montants/quantités minuscules, preuve RÉELLE (via confirm_credit_sale(),
-- jamais un calcul isolé) que TRUNC (jamais ROUND) empêche structurellement
-- tout reliquat négatif et toute déduction fee+reserve > gross_amount.
--
-- Émission dédiée MINUSCULE : 2 sources égales (B=0,0001 t / C=0,0001 t,
-- 0,0002 t au total), un lot unique de 0,0001 t — reproduit l'exemple exact
-- du bloqueur 3 : chaque prorata exact = 0,0001 * 0,5 = 0,00005 t, qui
-- ROUND-arrondirait À LA HAUSSE pour LES DEUX sources SIMULTANÉMENT (0,0001
-- chacune, somme 0,0002 > 0,0001 réel), produisant un reliquat négatif
-- (-0,0001) imputé à la paire porteuse. TRUNC tronque les DEUX vers zéro
-- (0,0000 chacune), le reliquat (0,0001 - 0,0000 = 0,0001) est structurellement
-- non négatif AVANT imputation.
-- ────────────────────────────────────────────────────────────
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end, verifier_user_id)
SELECT '66666666-6666-6666-6666-900000000003', '66666666-6666-6666-6666-400000000002', 'completed', current_date - 4, current_date - 1,
       pg_temp.carbon_test_profile('op');

INSERT INTO public.verification_outcomes (id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
SELECT '66666666-6666-6666-6666-910000000003', '66666666-6666-6666-6666-900000000003', 'active', 0.0002, 0.0002, 0.0002,
       '66666666-6666-6666-6666-800000000001', pg_temp.carbon_test_profile('op');

DO $$
DECLARE
    v_op_org  UUID := '66666666-6666-6666-6666-100000000001';
    v_b       UUID := '66666666-6666-6666-6666-100000000004';
    v_c       UUID := '66666666-6666-6666-6666-100000000005';
    v_iss_id  UUID;
    v_lot     UUID;
    v_sale    UUID;
    v_prop_fee     UUID;
    v_prop_reserve UUID;
BEGIN
    -- Override fee_pct=50,00 / reserve_pct=50,00 sur ORG_B (membre du regroupement, jamais
    -- l'aggregator_rule globale — n'affecte aucune autre vente/test de ce fichier) : reproduit
    -- l'exemple exact du bloqueur 3 (gross=0,01 $, fee=50 %, reserve=50 % -> ROUND aurait produit
    -- fee=0,01 + reserve=0,01 > gross=0,01, net=-0,01 $, structurellement impossible).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orgb'), false);
    v_prop_fee := public.propose_member_distribution_override(
        'create', '66666666-6666-6666-6666-500000000002'::uuid, NULL, 'fee_pct', 50.00,
        current_date - 1, current_date + 30, NULL);
    v_prop_reserve := public.propose_member_distribution_override(
        'create', '66666666-6666-6666-6666-500000000002'::uuid, NULL, 'reserve_pct', 50.00,
        current_date - 1, current_date + 30, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_fee);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_reserve);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_fee);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_reserve);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_fee);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_reserve);

    -- Émission minuscule à 2 sources égales (B/C), 1 lot de 0,0001 t.
    v_iss_id := public.create_credit_issuance(
        '66666666-6666-6666-6666-910000000003'::uuid,
        jsonb_build_array(
            jsonb_build_object('organization_id', v_b::text, 'aggregator_membership_id', '66666666-6666-6666-6666-500000000002', 'commercialization_mandate_id', '66666666-6666-6666-6666-600000000002', 'contributed_tco2e', 0.0001),
            jsonb_build_object('organization_id', v_c::text, 'aggregator_membership_id', '66666666-6666-6666-6666-500000000003', 'commercialization_mandate_id', '66666666-6666-6666-6666-600000000003', 'contributed_tco2e', 0.0001)
        )
    );
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_iss_id);
    PERFORM public.submit_credit_issuance(v_iss_id, 'TEST-09 Registre minuscule');
    PERFORM public.record_registry_issuance(v_iss_id, 'TEST-09-REG-003', clock_timestamp());

    v_lot := public.issue_credit_lot(v_iss_id, 0.0001, EXTRACT(YEAR FROM clock_timestamp())::int);

    -- Prix 100,00 $/tCO2e * 0,0001 t = gross_amount(vente) = 0,01 $ exactement (aucun coût déclaré,
    -- net_distributable_amount = 0,01 $) — reproduit le montant exact de l'exemple du bloqueur 3.
    v_sale := public.create_credit_sale(v_op_org, 100.00, 'TEST-09 Buyer minuscule (bloqueur 3)');
    PERFORM public.add_credit_sale_lot(v_sale, v_lot);
    PERFORM public.confirm_credit_sale(v_sale);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B95 : attribution carbone — les DEUX sources tronquent à 0,0000 (jamais 0,0001 chacune comme
    -- l'aurait produit ROUND), aucune n'est négative, et la somme égale exactement total_tco2e
    -- (0,0001) après imputation du reliquat (structurellement non négatif, bloqueur 3).
    PERFORM pg_temp.carbon_test_assert('B', 'B95 émission minuscule : allocated_tco2e jamais négatif pour B/C, SUM = total_tco2e (0,0001) exactement (bloqueur 3, TRUNC)',
        (SELECT allocated_tco2e >= 0 FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue')
        AND (SELECT allocated_tco2e >= 0 FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_c AND allocation_type='carbon_revenue')
        AND (SELECT sum(allocated_tco2e) FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND allocation_type='carbon_revenue') = 0.0001);

    -- B96 : répartition financière — gross=0,01 $, fee_pct=reserve_pct=50 % (overrides ci-dessus) :
    -- TRUNC(0,01*50/100,2)=TRUNC(0,005,2)=0,00 $ pour fee ET reserve (jamais 0,01 $ chacun comme
    -- l'aurait produit ROUND), donc net_amount=0,01-0,00-0,00=0,01 $ — JAMAIS négatif (bloqueur 3 :
    -- avec ROUND, fee=0,01+reserve=0,01 > gross=0,01, net=-0,01 $, structurellement impossible).
    PERFORM pg_temp.carbon_test_assert('B', 'B96 émission minuscule : gross=0,01 $/fee=0,00 $/reserve=0,00 $/net=0,01 $ pour la paire porteuse — net JAMAIS négatif (bloqueur 3, TRUNC)',
        (SELECT gross_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 0.01
        AND (SELECT fee_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 0.00
        AND (SELECT reserve_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 0.00
        AND (SELECT net_amount FROM public.credit_sale_allocations WHERE credit_sale_id=v_sale AND organization_id=v_b AND allocation_type='carbon_revenue') = 0.01);

    -- B97 : contre-épreuve globale — AUCUNE ligne de cette vente, toutes organisations/types confondus,
    -- n'a de composante négative (allocated_tco2e/gross/fee/reserve/net) — preuve exhaustive, jamais
    -- seulement sur les deux lignes déjà vérifiées ci-dessus.
    PERFORM pg_temp.carbon_test_assert('B', 'B97 émission minuscule : AUCUNE composante négative sur AUCUNE ligne de cette vente (contre-épreuve exhaustive, bloqueur 3)',
        NOT EXISTS (
            SELECT 1 FROM public.credit_sale_allocations
            WHERE credit_sale_id = v_sale
              AND (COALESCE(allocated_tco2e, 0) < 0 OR gross_amount < 0 OR fee_amount < 0 OR reserve_amount < 0 OR net_amount < 0)
        ));
END $$;

-- ────────────────────────────────────────────────────────────
-- 3sexies. NOUVEAU TEST — CINQUIÈME revue statique (correction complémentaire) :
--   invariance de fuseau horaire. Le SQL utilise désormais explicitement
--   `AT TIME ZONE 'America/Toronto'` (quatrième revue, point 7) pour résoudre la date locale
--   contractuelle d'une vente confirmée, précisément pour éliminer toute dépendance au fuseau de la
--   SESSION SQL qui exécute confirm_credit_sale(). Ce test exécute l'EXPRESSION EXACTE utilisée dans
--   compute_credit_sale_allocations() (lignes 1871/1880/1889 de la migration :
--   `(confirmed_at AT TIME ZONE 'America/Toronto')::date`), pour un instant FIXE identique, sous deux
--   `SET LOCAL TIME ZONE` de session délibérément opposés et extrêmes (Pacific/Kiritimati, UTC+14 ;
--   Etc/GMT+12, UTC-12 — l'écart le plus large possible entre fuseaux IANA réels, pour maximiser la
--   sensibilité du test à toute régression qui réintroduirait une dépendance implicite au fuseau de
--   session). RESET TIME ZONE après chaque bloc, jamais laissé actif au-delà de son usage immédiat.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_fixed_ts TIMESTAMPTZ := '2026-07-22 02:30:00-04'::timestamptz; -- instant fixe unique, réutilisé sous les deux fuseaux de session
    v_date1    DATE;
    v_date2    DATE;
BEGIN
    SET LOCAL TIME ZONE 'Pacific/Kiritimati';
    v_date1 := (v_fixed_ts AT TIME ZONE 'America/Toronto')::date;
    RESET TIME ZONE;

    SET LOCAL TIME ZONE 'Etc/GMT+12';
    v_date2 := (v_fixed_ts AT TIME ZONE 'America/Toronto')::date;
    RESET TIME ZONE;

    PERFORM pg_temp.carbon_test_assert('B', 'B98 invariance fuseau horaire : (confirmed_at AT TIME ZONE ''America/Toronto'')::date identique sous deux SET LOCAL TIME ZONE opposés (Pacific/Kiritimati UTC+14 vs Etc/GMT+12 UTC-12), pour le même instant fixe (correction complémentaire, cinquième revue, point 7 confirmé)',
        v_date1 = v_date2 AND v_date1 = '2026-07-22'::date);
END $$;

-- ────────────────────────────────────────────────────────────
-- 3octies. NOUVEAUX TESTS — SIXIÈME revue statique :
--   Correction 2 — bypass direct de gouvernance : couples approved_by/approved_at indissociables,
--   activation directe incomplète (2/2 et 3/3) rejetée, impossible de poser plusieurs approbations
--   simultanément par UPDATE privilégié direct (défense en profondeur contre un DML qui
--   contournerait les RPC d'approbation dédiées).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_prop_dr    UUID;
    v_aggregator UUID := '66666666-6666-6666-6666-200000000001';
    v_some_rule  UUID;
BEGIN
    SELECT id INTO v_some_rule FROM public.distribution_rules WHERE aggregator_id = v_aggregator LIMIT 1;

    -- Nouvelle proposition dédiée, jamais approuvée dans ce bloc (retirée par le proposant en fin de bloc).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr := public.propose_distribution_rule(v_aggregator, 13.00, 2.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B99 : CHECK de pairage aggregator_admin_approved_by/at — UPDATE direct posant approved_by SEUL
    -- (approved_at laissé NULL) rejeté (correction 2).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B99 distribution_rule_proposals : CHECK pairage aggregator_admin_approved_by/at rejette approved_by seul sans approved_at (correction 2)',
        format('UPDATE public.distribution_rule_proposals SET aggregator_admin_approved_by = %L::uuid WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('aggadmin'), v_prop_dr),
        'distribution_rule_proposals_aggregator_admin_pair_check');

    -- B100 : activation directe 2/2 INCOMPLÈTE (0 approbation posée) rejetée par le CHECK d'activation
    -- (correction 2), même en forçant status/activated_distribution_rule_id directement avec un id réel.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B100 distribution_rule_proposals : activation directe 2/2 incomplète (0 approbation) rejetée par CHECK (correction 2)',
        format('UPDATE public.distribution_rule_proposals SET status = ''activated'', activated_distribution_rule_id = %L::uuid WHERE id = %L::uuid',
            v_some_rule, v_prop_dr),
        '2/2 approbations doivent déjà être complètes');

    -- B101 : impossible de poser les DEUX approbations en une seule opération (UPDATE direct) — rejeté
    -- par le trigger d'atomicité (correction 2), jamais par le CHECK de pairage (les deux couples sont
    -- ici complets simultanément, seule l'atomicité est en cause).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B101 distribution_rule_proposals : UPDATE direct posant les DEUX approbations simultanément rejeté (une seule à la fois, correction 2)',
        format('UPDATE public.distribution_rule_proposals SET aggregator_admin_approved_by = %L::uuid, aggregator_admin_approved_at = clock_timestamp(), operator_admin_approved_by = %L::uuid, operator_admin_approved_at = clock_timestamp() WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('aggadmin'), pg_temp.carbon_test_profile('op'), v_prop_dr),
        'une seule approbation');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.withdraw_distribution_rule_proposal(v_prop_dr);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_prop_mdo      UUID;
    v_membership    UUID := '66666666-6666-6666-6666-500000000001';
    v_some_override UUID;
BEGIN
    SELECT id INTO v_some_override FROM public.member_distribution_overrides LIMIT 1;

    -- Nouvelle proposition 'create' dédiée sur un type d'override ('weight_multiplier') distinct de
    -- ceux déjà exercés ailleurs sur cette adhésion, jamais activée dans ce bloc (retirée en fin de
    -- bloc) — aucun risque de chevauchement EXCLUDE puisque la ligne n'est jamais réellement insérée
    -- dans member_distribution_overrides (seule l'ACTIVATION insérerait, jamais atteinte ici).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_mdo := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'weight_multiplier', 1.50,
        '2033-01-01'::date, '2033-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B102 : CHECK de pairage organization_admin_approved_by/at rejeté (correction 2).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B102 member_distribution_override_proposals : CHECK pairage organization_admin_approved_by/at rejette approved_by seul sans approved_at (correction 2)',
        format('UPDATE public.member_distribution_override_proposals SET organization_admin_approved_by = %L::uuid WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('orga'), v_prop_mdo),
        'organization_admin_pair_');

    -- B103 : activation directe 3/3 INCOMPLÈTE (0 approbation) rejetée par CHECK (correction 2).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B103 member_distribution_override_proposals : activation directe 3/3 incomplète (0 approbation) rejetée par CHECK (correction 2)',
        format('UPDATE public.member_distribution_override_proposals SET status = ''activated'', activated_override_id = %L::uuid WHERE id = %L::uuid',
            v_some_override, v_prop_mdo),
        '3/3 approbations doivent déjà être complètes');

    -- B104 : impossible de poser DEUX (sur trois) approbations simultanément par UPDATE direct — rejeté
    -- par le trigger d'atomicité (correction 2).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B104 member_distribution_override_proposals : UPDATE direct posant DEUX approbations simultanément rejeté (une seule à la fois, correction 2)',
        format('UPDATE public.member_distribution_override_proposals SET organization_admin_approved_by = %L::uuid, organization_admin_approved_at = clock_timestamp(), aggregator_admin_approved_by = %L::uuid, aggregator_admin_approved_at = clock_timestamp() WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('orga'), pg_temp.carbon_test_profile('aggadmin'), v_prop_mdo),
        'une seule approbation');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM public.withdraw_member_distribution_override_proposal(v_prop_mdo);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 3nonies. NOUVEAU TEST — SIXIÈME revue statique (correction 3) : can_view_distribution_rule() exige
-- désormais une adhésion ACTIVE (ended_at IS NULL). Organisation dédiée qui REJOINT puis QUITTE le
-- regroupement (join_aggregator()/leave_aggregator(), migration 02 déjà appliquée, utilisée telle
-- quelle, jamais modifiée) ; un simple membre NON-admin de cette organisation ne doit plus voir une
-- NOUVELLE distribution_rule activée APRÈS ce départ, alors qu'un membre resté actif (orgamember,
-- ORG_A, jamais partie) continue de la voir — preuve que la correction cible bien spécifiquement les
-- adhésions terminées, sans sur-restreindre les adhésions actives.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_aggregator UUID := '66666666-6666-6666-6666-200000000001';
    v_ex_org     UUID := '66666666-6666-6666-6666-100000000009';
    v_prop_dr2   UUID;
    v_new_rule   UUID;
    v_count      BIGINT;
BEGIN
    INSERT INTO public.organizations (id, name, status) VALUES (v_ex_org, 'TEST-09 Organisation partante (sixième revue)', 'active');
    INSERT INTO public.organization_members (id, organization_id, user_id, org_role, status, activated_at)
    VALUES ('66666666-6666-6666-6666-900000000106', v_ex_org, pg_temp.carbon_test_profile('exmember'), 'membre', 'active', clock_timestamp() - interval '5 days');

    -- Rejoint le regroupement (voie superadmin, join_aggregator() migration 02) puis quitte
    -- IMMÉDIATEMENT (leave_aggregator(), même migration) — ended_at désormais non NULL pour cette
    -- adhésion, AVANT toute activation d'une nouvelle règle ci-dessous.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.join_aggregator(v_ex_org, v_aggregator);
    PERFORM public.leave_aggregator(v_ex_org, 'TEST-09 sixième revue : départ contrôlé avant activation d''une nouvelle règle (correction 3)');
    PERFORM pg_temp.carbon_test_clear_actor();

    -- Nouvelle version de distribution_rule pour le MÊME regroupement, activée APRÈS le départ
    -- ci-dessus (versionnement temporel normal, §17 point 2 — remplace la version active existante,
    -- sans effet rétroactif sur les ventes déjà confirmées plus haut dans ce fichier).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr2 := public.propose_distribution_rule(v_aggregator, 11.50, 4.50, 1.0);
    PERFORM public.approve_distribution_rule_as_aggregator_admin(v_prop_dr2);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_distribution_rule_as_operator_admin(v_prop_dr2);
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT activated_distribution_rule_id INTO v_new_rule FROM public.distribution_rule_proposals WHERE id = v_prop_dr2;
    PERFORM pg_temp.carbon_test_assert('B', 'B105 précondition : nouvelle distribution_rule activée après le départ de l''organisation ex-membre (correction 3)', v_new_rule IS NOT NULL);

    -- B106 : le simple membre de l'organisation PARTIE ne voit plus cette nouvelle règle sous policy réelle.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('exmember'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.distribution_rules WHERE id = v_new_rule;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B106 RLS réelle : simple membre d''une organisation qui a QUITTÉ le regroupement ne voit PLUS une distribution_rule activée après son départ (correction 3, ended_at IS NULL désormais requis)', v_count = 0);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B107 : contre-épreuve — un membre TOUJOURS actif du regroupement (orgamember, ORG_A, jamais
    -- parti) continue de voir la MÊME nouvelle règle : la correction ne restreint que les adhésions
    -- terminées, jamais les adhésions actives.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orgamember'), false);
    SET LOCAL ROLE authenticated;
    SELECT count(*) INTO v_count FROM public.distribution_rules WHERE id = v_new_rule;
    RESET ROLE;
    PERFORM pg_temp.carbon_test_assert('B', 'B107 RLS réelle : contre-épreuve — membre TOUJOURS actif (orgamember, ORG_A) voit la même nouvelle règle (correction 3 ne restreint que les adhésions terminées)', v_count = 1);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 3decies. NOUVEAUX TESTS — SEPTIÈME revue statique (bloqueur 1) : immutabilité INTÉGRALE d'une
-- approbation déjà posée. La garde ajoutée après la sixième revue (B99/B102) ne protégeait que la
-- colonne <role>_approved_by (OLD non NULL) — un DML privilégié pouvait donc modifier UNIQUEMENT
-- <role>_approved_at d'une approbation déjà enregistrée, en laissant approved_by inchangé, ce qui
-- désynchronisait une paire censée être intégralement immuable. Les deux triggers BEFORE UPDATE
-- protègent désormais les DEUX colonnes ensemble dès que OLD.<role>_approved_by IS NOT NULL.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_prop_dr3 UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr3 := public.propose_distribution_rule('66666666-6666-6666-6666-200000000001'::uuid, 14.00, 3.00, 1.0);
    PERFORM public.approve_distribution_rule_as_aggregator_admin(v_prop_dr3);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B108 : UPDATE direct modifiant UNIQUEMENT aggregator_admin_approved_at (approved_by inchangé)
    -- d'une approbation DÉJÀ posée -- doit être rejeté (bloqueur 1, septième revue).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B108 distribution_rule_proposals : UPDATE direct modifiant uniquement aggregator_admin_approved_at d''une approbation déjà posée rejeté (immutabilité intégrale, septième revue bloqueur 1)',
        format('UPDATE public.distribution_rule_proposals SET aggregator_admin_approved_at = clock_timestamp() WHERE id = %L::uuid', v_prop_dr3),
        'approbation déjà posée est immuable');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.withdraw_distribution_rule_proposal(v_prop_dr3);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

DO $$
DECLARE
    v_prop_mdo2  UUID;
    v_membership UUID := '66666666-6666-6666-6666-500000000001';
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_mdo2 := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'weight_multiplier', 1.75,
        '2034-01-01'::date, '2034-12-31'::date, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_mdo2);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B109 : UPDATE direct modifiant UNIQUEMENT organization_admin_approved_at (approved_by inchangé)
    -- d'une approbation DÉJÀ posée -- doit être rejeté (bloqueur 1, septième revue).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B109 member_distribution_override_proposals : UPDATE direct modifiant uniquement organization_admin_approved_at d''une approbation déjà posée rejeté (immutabilité intégrale, septième revue bloqueur 1)',
        format('UPDATE public.member_distribution_override_proposals SET organization_admin_approved_at = clock_timestamp() WHERE id = %L::uuid', v_prop_mdo2),
        'approbation déjà posée est immuable');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM public.withdraw_member_distribution_override_proposal(v_prop_mdo2);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 3undecies. NOUVEAUX TESTS — HUITIÈME revue statique :
--   Bloqueur 1 — les invariants d'approbation (immutabilité, atomicité) ne s'appliquaient auparavant
--   que sous NEW.status='pending' : un DML privilégié pouvait donc contourner l'atomicité en posant
--   toutes les approbations ET en activant dans la MÊME UPDATE (NEW.status='activated' au moment du
--   contrôle). Corrigé en rendant ces invariants inconditionnels (appliqués dès que OLD.status=
--   'pending', quel que soit NEW.status), plus une garde neuve exigeant qu'OLD contienne déjà les
--   approbations complètes avant toute transition vers 'activated'.
--   Bloqueur 2 — activated_distribution_rule_id/activated_override_id ne prouvaient que l'existence de
--   la ligne cible (FK), jamais qu'elle est réellement le résultat de CETTE proposition. Corrigé par
--   des gardes de provenance exactes (proposal_id/aggregator_id, ou proposal_id/aggregator_membership_id,
--   ou pour 'revoke' : égalité stricte avec target_override_id + revocation_proposal_id/revoked_at réels).
-- ────────────────────────────────────────────────────────────

-- Override frais dédié, créé et pleinement activé via le flux RÉEL (3/3 approbations réelles), pour
-- servir de cible LÉGITIME (jamais révoquée par la suite) à un scénario 'revoke' bypass ci-dessous.
DO $$
DECLARE
    v_membership         UUID := '66666666-6666-6666-6666-500000000001';
    v_prop_fresh_create   UUID;
    v_fresh_override_id  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_fresh_create := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'weight_multiplier', 1.35, '2035-01-01'::date, '2035-12-31'::date, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_fresh_create);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.approve_member_distribution_override_as_aggregator_admin(v_prop_fresh_create);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_member_distribution_override_as_operator_admin(v_prop_fresh_create);
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT activated_override_id INTO v_fresh_override_id FROM public.member_distribution_override_proposals WHERE id = v_prop_fresh_create;
    PERFORM pg_temp.carbon_test_assert('B', 'B110 précondition (huitième revue) : override frais dédié créé et activé (cible du scénario revoke bypass ci-dessous)', v_fresh_override_id IS NOT NULL);

    PERFORM set_config('carbon_test09.b8_fresh_override', v_fresh_override_id::text, false);
END $$;

-- distribution_rule_proposals : bypass "2/2 posées par UPDATE séparées, puis activation pointant vers
-- la MAUVAISE distribution_rule (mauvais proposal_id, même aggregator_id)" -- et bypass "les 2
-- approbations + l'activation en une SEULE UPDATE".
DO $$
DECLARE
    v_aggregator  UUID := '66666666-6666-6666-6666-200000000001';
    v_prop_dr4    UUID;
    v_prop_dr5    UUID;
    v_some_rule   UUID;
BEGIN
    SELECT id INTO v_some_rule FROM public.distribution_rules WHERE aggregator_id = v_aggregator LIMIT 1;

    -- v_prop_dr4 porté à 2/2 par DEUX UPDATE directes SÉPARÉES (chacune satisfait l'atomicité prise
    -- isolément), en contournant délibérément le chemin RPC normal -- reproduit exactement ce qu'un DML
    -- privilégié direct pourrait produire : la proposition reste 'pending', 2/2 complètes, JAMAIS
    -- activée par carbon_try_activate_distribution_rule_proposal() (jamais appelée ici).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr4 := public.propose_distribution_rule(v_aggregator, 15.00, 3.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();

    UPDATE public.distribution_rule_proposals
    SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp()
    WHERE id = v_prop_dr4;
    UPDATE public.distribution_rule_proposals
    SET operator_admin_approved_by = pg_temp.carbon_test_profile('op'), operator_admin_approved_at = clock_timestamp()
    WHERE id = v_prop_dr4;

    PERFORM pg_temp.carbon_test_assert('B', 'B111 précondition (huitième revue) : distribution_rule_proposal 2/2 approuvée par deux UPDATE séparées, toujours pending (jamais activée par le chemin RPC)',
        (SELECT status = 'pending' AND aggregator_admin_approved_by IS NOT NULL AND operator_admin_approved_by IS NOT NULL
         FROM public.distribution_rule_proposals WHERE id = v_prop_dr4));

    -- B112 (bloqueur 2) : activation directe pointant vers une distribution_rule RÉELLE et EXISTANTE du
    -- MÊME regroupement, mais produite par une AUTRE proposition (mauvais proposal_id) -- doit être
    -- rejetée : l'existence seule (FK) ne suffit jamais, la provenance exacte est désormais exigée.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B112 distribution_rule_proposals : activation directe pointant vers la distribution_rule d''une AUTRE proposition (même aggregator_id, mauvais proposal_id) rejetée (bloqueur 2, huitième revue)',
        format('UPDATE public.distribution_rule_proposals SET status = ''activated'', activated_distribution_rule_id = %L::uuid WHERE id = %L::uuid', v_some_rule, v_prop_dr4),
        'ne correspond pas à une distribution_rule réellement produite par CETTE proposition');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.withdraw_distribution_rule_proposal(v_prop_dr4);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- v_prop_dr5 : FRAÎCHE, 0/2 -- tente de poser les DEUX approbations ET l'activation en une SEULE
    -- UPDATE (exactement l'exploit décrit par l'utilisateur : profiter de NEW.status <> 'pending' pour
    -- contourner l'atomicité). Doit désormais être rejetée par l'invariant d'atomicité, devenu
    -- inconditionnel (bloqueur 1) -- AVANT même d'atteindre la garde de provenance (bloqueur 2).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr5 := public.propose_distribution_rule(v_aggregator, 16.00, 3.50, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B113 distribution_rule_proposals : UPDATE unique posant les 2 approbations ET activated_distribution_rule_id simultanément rejeté (bloqueur 1, huitième revue -- invariants désormais inconditionnels)',
        format('UPDATE public.distribution_rule_proposals SET status = ''activated'', aggregator_admin_approved_by = %L::uuid, aggregator_admin_approved_at = clock_timestamp(), operator_admin_approved_by = %L::uuid, operator_admin_approved_at = clock_timestamp(), activated_distribution_rule_id = %L::uuid WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('aggadmin'), pg_temp.carbon_test_profile('op'), v_some_rule, v_prop_dr5),
        'aucune nouvelle approbation ne peut être posée');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.withdraw_distribution_rule_proposal(v_prop_dr5);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- member_distribution_override_proposals : mêmes deux bypass, symétriques (3/3 par trois UPDATE
-- séparées puis mauvaise provenance ; 3/3 + activation en une seule UPDATE).
DO $$
DECLARE
    v_membership     UUID := '66666666-6666-6666-6666-500000000001';
    v_prop_mdo3      UUID;
    v_prop_mdo4      UUID;
    v_some_override  UUID;
BEGIN
    SELECT id INTO v_some_override FROM public.member_distribution_overrides WHERE id <> current_setting('carbon_test09.b8_fresh_override')::uuid LIMIT 1;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_mdo3 := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'weight_multiplier', 1.40, '2036-01-01'::date, '2036-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    UPDATE public.member_distribution_override_proposals
    SET organization_admin_approved_by = pg_temp.carbon_test_profile('orga'), organization_admin_approved_at = clock_timestamp()
    WHERE id = v_prop_mdo3;
    UPDATE public.member_distribution_override_proposals
    SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp()
    WHERE id = v_prop_mdo3;
    UPDATE public.member_distribution_override_proposals
    SET operator_admin_approved_by = pg_temp.carbon_test_profile('op'), operator_admin_approved_at = clock_timestamp()
    WHERE id = v_prop_mdo3;

    PERFORM pg_temp.carbon_test_assert('B', 'B114 précondition (huitième revue) : member_distribution_override_proposal 3/3 approuvée par trois UPDATE séparées, toujours pending (jamais activée par le chemin RPC)',
        (SELECT status = 'pending' AND organization_admin_approved_by IS NOT NULL AND aggregator_admin_approved_by IS NOT NULL AND operator_admin_approved_by IS NOT NULL
         FROM public.member_distribution_override_proposals WHERE id = v_prop_mdo3));

    -- B115 (bloqueur 2) : activation directe pointant vers un override RÉEL et EXISTANT, mais produit
    -- par une AUTRE proposition -- rejetée.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B115 member_distribution_override_proposals : activation directe pointant vers l''override d''une AUTRE proposition rejetée (bloqueur 2, huitième revue)',
        format('UPDATE public.member_distribution_override_proposals SET status = ''activated'', activated_override_id = %L::uuid WHERE id = %L::uuid', v_some_override, v_prop_mdo3),
        'ne correspond pas à un member_distribution_override réellement produit par CETTE proposition');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM public.withdraw_member_distribution_override_proposal(v_prop_mdo3);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- v_prop_mdo4 : FRAÎCHE, 0/3 -- pose les TROIS approbations ET l'activation en une SEULE UPDATE.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_mdo4 := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'weight_multiplier', 1.45, '2037-01-01'::date, '2037-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B116 member_distribution_override_proposals : UPDATE unique posant les 3 approbations ET activated_override_id simultanément rejeté (bloqueur 1, huitième revue)',
        format('UPDATE public.member_distribution_override_proposals SET status = ''activated'', organization_admin_approved_by = %L::uuid, organization_admin_approved_at = clock_timestamp(), aggregator_admin_approved_by = %L::uuid, aggregator_admin_approved_at = clock_timestamp(), operator_admin_approved_by = %L::uuid, operator_admin_approved_at = clock_timestamp(), activated_override_id = %L::uuid WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('orga'), pg_temp.carbon_test_profile('aggadmin'), pg_temp.carbon_test_profile('op'), v_some_override, v_prop_mdo4),
        'aucune nouvelle approbation ne peut être posée');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM public.withdraw_member_distribution_override_proposal(v_prop_mdo4);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- 'revoke' : provenance exacte -- activated_override_id doit être EXACTEMENT target_override_id, ET la
-- cible doit déjà porter revocation_proposal_id = OLD.id / revoked_at IS NOT NULL (jamais seulement
-- l'existence de la ligne).
DO $$
DECLARE
    v_membership        UUID := '66666666-6666-6666-6666-500000000001';
    v_fresh_override_id UUID := current_setting('carbon_test09.b8_fresh_override')::uuid;
    v_prop_revoke2      UUID;
    v_other_override    UUID;
BEGIN
    SELECT id INTO v_other_override FROM public.member_distribution_overrides WHERE id <> v_fresh_override_id LIMIT 1;

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_revoke2 := public.propose_member_distribution_override(
        'revoke', v_membership, v_fresh_override_id, NULL, NULL, NULL, NULL, 'TEST-09 huitième revue : bypass provenance revoke');
    PERFORM pg_temp.carbon_test_clear_actor();

    UPDATE public.member_distribution_override_proposals
    SET organization_admin_approved_by = pg_temp.carbon_test_profile('orga'), organization_admin_approved_at = clock_timestamp()
    WHERE id = v_prop_revoke2;
    UPDATE public.member_distribution_override_proposals
    SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp()
    WHERE id = v_prop_revoke2;
    UPDATE public.member_distribution_override_proposals
    SET operator_admin_approved_by = pg_temp.carbon_test_profile('op'), operator_admin_approved_at = clock_timestamp()
    WHERE id = v_prop_revoke2;

    PERFORM pg_temp.carbon_test_assert('B', 'B117 précondition (huitième revue) : proposition revoke 3/3 approuvée par UPDATE séparées, cible TOUJOURS non révoquée (jamais activée par le chemin RPC)',
        (SELECT status = 'pending' FROM public.member_distribution_override_proposals WHERE id = v_prop_revoke2)
        AND (SELECT revoked_at IS NULL FROM public.member_distribution_overrides WHERE id = v_fresh_override_id));

    -- B118 : activated_override_id = target_override_id (correct au sens de l'égalité), mais la cible
    -- n'a JAMAIS été réellement révoquée par cette proposition (revoked_at encore NULL, jamais
    -- révoquée par le chemin RPC réel) -- doit être rejetée.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B118 member_distribution_override_proposals (revoke) : activation pointant vers target_override_id jamais réellement révoqué par CETTE proposition rejetée (bloqueur 2, huitième revue)',
        format('UPDATE public.member_distribution_override_proposals SET status = ''activated'', activated_override_id = %L::uuid WHERE id = %L::uuid', v_fresh_override_id, v_prop_revoke2),
        'doit déjà être révoqué avec revocation_proposal_id pointant vers CETTE proposition');

    -- B119 : activated_override_id pointant vers un AUTRE override que target_override_id -- rejetée
    -- par la garde d'égalité stricte, avant même la vérification de révocation.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B119 member_distribution_override_proposals (revoke) : activation pointant vers un override DIFFÉRENT de target_override_id rejetée (bloqueur 2, huitième revue)',
        format('UPDATE public.member_distribution_override_proposals SET status = ''activated'', activated_override_id = %L::uuid WHERE id = %L::uuid', v_other_override, v_prop_revoke2),
        'doit désigner exactement l''override ciblé par la proposition');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    PERFORM public.withdraw_member_distribution_override_proposal(v_prop_revoke2);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Immutabilité intégrale pendant une transition vers 'rejected'/'withdrawn' (pas seulement 'activated')
-- -- les invariants A/B, désormais inconditionnels, doivent aussi protéger ces deux transitions.
DO $$
DECLARE
    v_aggregator UUID := '66666666-6666-6666-6666-200000000001';
    v_membership UUID := '66666666-6666-6666-6666-500000000001';
    v_prop_dr6   UUID;
    v_prop_mdo5  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr6 := public.propose_distribution_rule(v_aggregator, 17.00, 3.00, 1.0);
    PERFORM public.approve_distribution_rule_as_aggregator_admin(v_prop_dr6);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B120 : transition vers 'rejected' tentant DE PLUS de modifier aggregator_admin_approved_at (déjà
    -- posée) -- doit être rejetée par l'immutabilité, désormais vérifiée AVANT le branchement sur
    -- NEW.status (bloqueur 1), et non plus seulement sous NEW.status='pending'.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B120 distribution_rule_proposals : transition vers rejected modifiant EN PLUS une approbation déjà posée rejetée (immutabilité inconditionnelle, bloqueur 1, huitième revue)',
        format('UPDATE public.distribution_rule_proposals SET status = ''rejected'', rejected_by = %L::uuid, rejected_at = clock_timestamp(), reject_reason = ''test bloqueur 1'', aggregator_admin_approved_at = clock_timestamp() WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('op'), v_prop_dr6),
        'approbation déjà posée est immuable');
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.withdraw_distribution_rule_proposal(v_prop_dr6);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B121 : symétrique pour member_distribution_override_proposals -- transition vers 'withdrawn'
    -- tentant de modifier organization_admin_approved_at (déjà posée).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('orga'), false);
    v_prop_mdo5 := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'weight_multiplier', 1.55, '2038-01-01'::date, '2038-12-31'::date, NULL);
    PERFORM public.approve_member_distribution_override_as_organization_admin(v_prop_mdo5);

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B121 member_distribution_override_proposals : transition vers withdrawn modifiant EN PLUS une approbation déjà posée rejetée (immutabilité inconditionnelle, bloqueur 1, huitième revue)',
        format('UPDATE public.member_distribution_override_proposals SET status = ''withdrawn'', organization_admin_approved_at = clock_timestamp() WHERE id = %L::uuid', v_prop_mdo5),
        'approbation déjà posée est immuable');

    PERFORM public.withdraw_member_distribution_override_proposal(v_prop_mdo5);
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 3duodecies. NOUVEAUX TESTS — NEUVIÈME revue statique :
--   Bloqueur 2 — les triggers ne garantissaient qu'« au plus UNE nouvelle approbation par UPDATE »,
--   indépendamment de NEW.status : pending -> rejected/withdrawn pouvait donc encore injecter une
--   approbation restée NULL dans la MÊME opération. Corrigé en exigeant EXACTEMENT ZÉRO nouvelle
--   approbation dès que NEW.status <> 'pending'.
--   Bloqueur 3 — le CHECK all-or-none des métadonnées de rejet ne bloquait que les DEUX sens complets ;
--   un statut non-rejected pouvait porter une métadonnée PARTIELLE (ex. rejected_at seul). Corrigé par
--   un CHECK explicitement all-or-none dans les deux branches.
--   Bloqueur 4 — l'intégrité proposition -> objet économique existait déjà (huitième revue) ; l'inverse
--   (objet -> proposition : valeurs identiques, proposition réellement activée avec ses approbations
--   complètes, unicité de proposal_id/revocation_proposal_id) ne l'était pas. Fermé par trois CONSTRAINT
--   TRIGGER DEFERRABLE INITIALLY DEFERRED + trois contraintes UNIQUE.
-- ────────────────────────────────────────────────────────────

-- Regroupement/organisation/adhésion DÉDIÉS, entièrement isolés du reste du fichier (aucun risque de
-- collision avec les fixtures existantes — EXCLUDE de distribution_rules/member_distribution_overrides
-- scopé par aggregator_id/aggregator_membership_id).
DO $$
DECLARE
    v_fresh_agg        UUID := gen_random_uuid();
    v_fresh_org        UUID := gen_random_uuid();
    v_fresh_membership UUID;
BEGIN
    INSERT INTO public.aggregators (id, name) VALUES (v_fresh_agg, 'TEST-09 NEUVIÈME REVUE — Regroupement dédié bloqueurs 2/3/4');
    INSERT INTO public.aggregator_admins (aggregator_id, user_id, role) VALUES (v_fresh_agg, pg_temp.carbon_test_profile('aggadmin'), 'primary_admin');
    INSERT INTO public.organizations (id, name, status) VALUES (v_fresh_org, 'TEST-09 NEUVIÈME REVUE Org', 'active');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_fresh_membership := public.join_aggregator(v_fresh_org, v_fresh_agg);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert('B', 'B_9e_0 précondition (neuvième revue) : regroupement/organisation/adhésion dédiés créés pour isoler les tests des bloqueurs 2/3/4', v_fresh_membership IS NOT NULL);

    PERFORM set_config('carbon_test09.b9_fresh_aggregator', v_fresh_agg::text, false);
    PERFORM set_config('carbon_test09.b9_fresh_membership', v_fresh_membership::text, false);
END $$;

-- Bloqueur 2 : aucune nouvelle approbation pendant une transition finale (rejected/withdrawn).
DO $$
DECLARE
    v_agg       UUID := current_setting('carbon_test09.b9_fresh_aggregator')::uuid;
    v_membership UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_prop_dr9  UUID;
    v_prop_mdo6 UUID;
BEGIN
    -- B122 : distribution_rule_proposal 1/2 (aggregator_admin posée) -- transition directe vers
    -- 'rejected' injectant EN PLUS l'approbation operator_admin encore NULL dans la MÊME UPDATE.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr9 := public.propose_distribution_rule(v_agg, 18.00, 4.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();
    UPDATE public.distribution_rule_proposals SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp() WHERE id = v_prop_dr9;

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B122 distribution_rule_proposals : pending -> rejected injectant EN PLUS une nouvelle approbation (operator_admin encore NULL) rejeté (bloqueur 2, neuvième revue)',
        format('UPDATE public.distribution_rule_proposals SET status = ''rejected'', rejected_by = %L::uuid, rejected_at = clock_timestamp(), reject_reason = ''test bloqueur 2'', operator_admin_approved_by = %L::uuid, operator_admin_approved_at = clock_timestamp() WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('op'), pg_temp.carbon_test_profile('op'), v_prop_dr9),
        'aucune nouvelle approbation ne peut être posée');

    -- B123 : member_distribution_override_proposal 2/3 (organisation + regroupement posées) --
    -- transition directe vers 'withdrawn' injectant EN PLUS l'approbation opérateur encore NULL.
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_mdo6 := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'fee_pct', 9.00, '2051-01-01'::date, '2051-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();
    UPDATE public.member_distribution_override_proposals SET organization_admin_approved_by = pg_temp.carbon_test_profile('orga'), organization_admin_approved_at = clock_timestamp() WHERE id = v_prop_mdo6;
    UPDATE public.member_distribution_override_proposals SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp() WHERE id = v_prop_mdo6;

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B123 member_distribution_override_proposals : pending -> withdrawn injectant EN PLUS une nouvelle approbation (opérateur encore NULL) rejeté (bloqueur 2, neuvième revue)',
        format('UPDATE public.member_distribution_override_proposals SET status = ''withdrawn'', operator_admin_approved_by = %L::uuid, operator_admin_approved_at = clock_timestamp() WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('op'), v_prop_mdo6),
        'aucune nouvelle approbation ne peut être posée');
END $$;

-- Bloqueur 3 : CHECK all-or-none des métadonnées de rejet -- un statut non-rejected ne peut porter
-- aucune métadonnée de rejet PARTIELLE (rejected_at seul, reject_reason seul).
DO $$
DECLARE
    v_agg        UUID := current_setting('carbon_test09.b9_fresh_aggregator')::uuid;
    v_membership UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_prop_dr10  UUID;
    v_prop_mdo7  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dr10 := public.propose_distribution_rule(v_agg, 19.00, 4.50, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B124 : status reste 'pending', rejected_at SEUL renseigné -- rejeté par le CHECK all-or-none.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B124 distribution_rule_proposals : status pending avec rejected_at SEUL renseigné rejeté par le CHECK all-or-none (bloqueur 3, neuvième revue)',
        format('UPDATE public.distribution_rule_proposals SET rejected_at = clock_timestamp() WHERE id = %L::uuid', v_prop_dr10),
        'distribution_rule_proposals_rejected_check');

    -- B125 : status reste 'pending', reject_reason SEUL renseigné -- rejeté par le même CHECK.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B125 distribution_rule_proposals : status pending avec reject_reason SEUL renseigné rejeté par le CHECK all-or-none (bloqueur 3, neuvième revue)',
        format('UPDATE public.distribution_rule_proposals SET reject_reason = ''fuite partielle test'' WHERE id = %L::uuid', v_prop_dr10),
        'distribution_rule_proposals_rejected_check');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    PERFORM public.withdraw_distribution_rule_proposal(v_prop_dr10);
    v_prop_mdo7 := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'fee_pct', 9.50, '2052-01-01'::date, '2052-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    -- B126 : symétrique, member_distribution_override_proposals, rejected_at SEUL.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B126 member_distribution_override_proposals : status pending avec rejected_at SEUL renseigné rejeté par le CHECK all-or-none (bloqueur 3, neuvième revue)',
        format('UPDATE public.member_distribution_override_proposals SET rejected_at = clock_timestamp() WHERE id = %L::uuid', v_prop_mdo7),
        'member_distribution_override_proposals_rejected_check');

    -- B127 : symétrique, reject_reason SEUL.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B127 member_distribution_override_proposals : status pending avec reject_reason SEUL renseigné rejeté par le CHECK all-or-none (bloqueur 3, neuvième revue)',
        format('UPDATE public.member_distribution_override_proposals SET reject_reason = ''fuite partielle test'' WHERE id = %L::uuid', v_prop_mdo7),
        'member_distribution_override_proposals_rejected_check');
END $$;

-- Bloqueur 4, préparation : override VALIDE (valeurs concordantes, proposition réellement activée avec
-- ses 3/3 approbations) -- sert de cible légitime aux tests B132 (révocation orpheline) et B134
-- (doublon proposal_id). Construit par bypass (raw UPDATE des trois approbations, jamais les RPC
-- approve_*), exactement comme B114/B117 plus haut.
DO $$
DECLARE
    v_membership UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_prop_ok    UUID;
    v_override_ok UUID;
    v_msg        TEXT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_ok := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'fee_pct', 12.00, '2053-01-01'::date, '2053-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    UPDATE public.member_distribution_override_proposals SET organization_admin_approved_by = pg_temp.carbon_test_profile('orga'), organization_admin_approved_at = clock_timestamp() WHERE id = v_prop_ok;
    UPDATE public.member_distribution_override_proposals SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp() WHERE id = v_prop_ok;
    UPDATE public.member_distribution_override_proposals SET operator_admin_approved_by = pg_temp.carbon_test_profile('op'), operator_admin_approved_at = clock_timestamp() WHERE id = v_prop_ok;

    INSERT INTO public.member_distribution_overrides (aggregator_membership_id, override_type, override_value, effective_from, effective_until, proposal_id, created_by)
    VALUES (v_membership, 'fee_pct', 12.00, '2053-01-01'::date, '2053-12-31'::date, v_prop_ok, pg_temp.carbon_test_profile('aggadmin'))
    RETURNING id INTO v_override_ok;

    UPDATE public.member_distribution_override_proposals SET status = 'activated', activated_override_id = v_override_ok WHERE id = v_prop_ok;

    -- Contrôle différé forcé : DOIT passer sans erreur (valeurs et approbations concordent réellement).
    BEGIN
        SET CONSTRAINTS trg_carbon_check_member_distribution_override_creation_integrity IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B_9e_1 précondition (neuvième revue) : override valide (valeurs concordantes, 3/3 approbations réelles) passe le contrôle différé forcé sans erreur', v_msg IS NULL, v_msg);
    -- Corrigé après exécution réelle de GATE 3 : oubli du réinitialisation DEFERRED (seule occurrence du
    -- fichier à omettre ce réinitialisation après un forçage IMMEDIATE de ce trigger, contrairement à
    -- B72bis/B72ter/B131 -- voir leur commentaire d'isolation). Sans ce réinitialisation, le mode
    -- IMMEDIATE restait actif pour TOUTE la suite de la transaction : l'INSERT de B129 (plus bas) faisait
    -- alors firer le contrôle différé DÈS l'INSERT lui-même, AVANT l'UPDATE d'activation qui suit -- la
    -- proposition y était donc encore 'pending' à ce moment précis, jamais une véritable divergence de
    -- valeur. B129 ne pouvait alors jamais atteindre son invariant réellement visé.
    SET CONSTRAINTS trg_carbon_check_member_distribution_override_creation_integrity DEFERRED;

    PERFORM set_config('carbon_test09.b9_prop_ok', v_prop_ok::text, false);
    PERFORM set_config('carbon_test09.b9_override_ok', v_override_ok::text, false);
END $$;

-- B128 (bloqueur 4A) : distribution_rule référençant un proposal_id réel, 2/2 approuvé, mais dont
-- platform_fee_pct diffère de celui approuvé par la proposition -- rejeté au contrôle différé forcé.
DO $$
DECLARE
    v_agg      UUID := current_setting('carbon_test09.b9_fresh_aggregator')::uuid;
    v_prop     UUID;
    v_bad_rule UUID;
    v_msg      TEXT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop := public.propose_distribution_rule(v_agg, 20.00, 5.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();
    UPDATE public.distribution_rule_proposals SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp() WHERE id = v_prop;
    UPDATE public.distribution_rule_proposals SET operator_admin_approved_by = pg_temp.carbon_test_profile('op'), operator_admin_approved_at = clock_timestamp() WHERE id = v_prop;

    BEGIN
        -- Corrigé après exécution réelle de GATE 3 : 99,00 violait dès l'INSERT le CHECK immédiat
        -- distribution_rules_fee_reserve_bounds_check (99,00 + 5,00 = 104,00 > 100), avant même d'atteindre
        -- le contrôle différé visé ici. 21,00 diverge toujours de la valeur approuvée (20,00) tout en
        -- respectant 21,00 + 5,00 = 26,00 <= 100 : seul l'invariant de concordance proposition/règle est
        -- désormais exercé.
        INSERT INTO public.distribution_rules (aggregator_id, platform_fee_pct, reserve_pct, default_weight, effective_from, proposal_id, created_by)
        VALUES (v_agg, 21.00, 5.00, 1.0, clock_timestamp(), v_prop, pg_temp.carbon_test_profile('aggadmin'))
        RETURNING id INTO v_bad_rule;
        UPDATE public.distribution_rule_proposals SET status = 'activated', activated_distribution_rule_id = v_bad_rule WHERE id = v_prop;
        SET CONSTRAINTS trg_carbon_check_distribution_rule_proposal_integrity IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B128 distribution_rules : proposal_id réel référencé mais platform_fee_pct (21,00) différent de celui approuvé (20,00) rejeté au contrôle différé forcé (bloqueur 4, neuvième revue)',
        v_msg IS NOT NULL AND v_msg ILIKE '%identiques%', v_msg);
END $$;

-- B129 (bloqueur 4B) : member_distribution_override référençant un proposal_id réel, 3/3 approuvé,
-- mais dont override_value diffère de celui approuvé -- rejeté au contrôle différé forcé.
DO $$
DECLARE
    v_membership  UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_prop        UUID;
    v_bad_override UUID;
    v_msg         TEXT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'reserve_pct', 6.00, '2054-01-01'::date, '2054-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();
    UPDATE public.member_distribution_override_proposals SET organization_admin_approved_by = pg_temp.carbon_test_profile('orga'), organization_admin_approved_at = clock_timestamp() WHERE id = v_prop;
    UPDATE public.member_distribution_override_proposals SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp() WHERE id = v_prop;
    UPDATE public.member_distribution_override_proposals SET operator_admin_approved_by = pg_temp.carbon_test_profile('op'), operator_admin_approved_at = clock_timestamp() WHERE id = v_prop;

    BEGIN
        INSERT INTO public.member_distribution_overrides (aggregator_membership_id, override_type, override_value, effective_from, effective_until, proposal_id, created_by)
        VALUES (v_membership, 'reserve_pct', 77.00, '2054-01-01'::date, '2054-12-31'::date, v_prop, pg_temp.carbon_test_profile('aggadmin'))
        RETURNING id INTO v_bad_override;
        UPDATE public.member_distribution_override_proposals SET status = 'activated', activated_override_id = v_bad_override WHERE id = v_prop;
        SET CONSTRAINTS trg_carbon_check_member_distribution_override_creation_integrity IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B129 member_distribution_overrides : proposal_id réel référencé mais override_value (77,00) différente de celle approuvée (6,00) rejetée au contrôle différé forcé (bloqueur 4, neuvième revue)',
        v_msg IS NOT NULL AND v_msg ILIKE '%identiques%', v_msg);
END $$;

-- B130 (bloqueur 4C) : distribution_rule référençant un proposal_id dont la proposition reste 'pending'
-- (jamais activée) -- rejeté au contrôle différé forcé.
DO $$
DECLARE
    v_agg      UUID := current_setting('carbon_test09.b9_fresh_aggregator')::uuid;
    v_prop     UUID;
    v_bad_rule UUID;
    v_msg      TEXT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop := public.propose_distribution_rule(v_agg, 21.00, 4.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();
    -- v_prop reste 'pending', 0/2 -- aucune approbation, jamais activée.

    BEGIN
        INSERT INTO public.distribution_rules (aggregator_id, platform_fee_pct, reserve_pct, default_weight, effective_from, proposal_id, created_by)
        VALUES (v_agg, 21.00, 4.00, 1.0, clock_timestamp(), v_prop, pg_temp.carbon_test_profile('aggadmin'))
        RETURNING id INTO v_bad_rule;
        SET CONSTRAINTS trg_carbon_check_distribution_rule_proposal_integrity IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B130 distribution_rules : INSERT référençant une proposition encore pending (jamais activated) rejeté au contrôle différé forcé (bloqueur 4, neuvième revue)',
        v_msg IS NOT NULL AND v_msg ILIKE '%activated%' AND v_msg ILIKE '%COMMIT%', v_msg);
END $$;

-- B131 (bloqueur 4D) : member_distribution_override référençant un proposal_id dont la proposition
-- reste 'pending' -- rejeté au contrôle différé forcé.
-- ISOLATION (ONZIÈME revue statique, bloqueur 2) : B131 n'est PAS la première occurrence à forcer
-- trg_carbon_check_member_distribution_override_creation_integrity IMMEDIATE dans ce fichier -- B72bis
-- (le replace) puis B72ter (la création dédiée du chemin revoke) l'ont déjà fait, chacun purgeant sa
-- propre file d'attente différée et réinitialisant DEFERRED ensuite. L'exception levée ci-dessous est
-- donc bien attribuable au SEUL événement de B131 (l'INSERT sur une proposition encore pending),
-- jamais à un résidu de B72bis/B72ter.
DO $$
DECLARE
    v_membership   UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_prop         UUID;
    v_bad_override UUID;
    v_msg          TEXT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop := public.propose_member_distribution_override(
        'create', v_membership, NULL, 'reserve_pct', 7.00, '2055-01-01'::date, '2055-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();
    -- v_prop reste 'pending', 0/3 -- jamais activée.

    BEGIN
        INSERT INTO public.member_distribution_overrides (aggregator_membership_id, override_type, override_value, effective_from, effective_until, proposal_id, created_by)
        VALUES (v_membership, 'reserve_pct', 7.00, '2055-01-01'::date, '2055-12-31'::date, v_prop, pg_temp.carbon_test_profile('aggadmin'))
        RETURNING id INTO v_bad_override;
        SET CONSTRAINTS trg_carbon_check_member_distribution_override_creation_integrity IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B131 member_distribution_overrides : INSERT référençant une proposition encore pending (jamais activated) rejeté au contrôle différé forcé (bloqueur 4, neuvième revue)',
        v_msg IS NOT NULL AND v_msg ILIKE '%activated%' AND v_msg ILIKE '%COMMIT%', v_msg);
END $$;

-- B132 (bloqueur 4E) : révocation de l'override VALIDE (B_9e_1) référençant une proposition 'revoke'
-- réelle mais encore 'pending' (jamais activée, 0/3 approuvée) -- rejetée au contrôle différé forcé.
-- ISOLATION (DIXIÈME revue statique, bloqueur 2, point IMPORTANT explicitement demandé en revue) :
-- B132 n'est PLUS la première occurrence à forcer trg_carbon_check_member_distribution_override_
-- revocation_integrity IMMEDIATE dans ce fichier -- B72bis (bien plus haut, juste après le replace
-- légitime B70-B72) l'a déjà fait et a explicitement vidé la file d'attente différée de CET
-- événement-là (le replace), PUIS réinitialisé le mode à DEFERRED pour la suite. SET CONSTRAINTS ...
-- IMMEDIATE ci-dessous ne capture donc plus AUCUN événement résiduel de B70 -- seul l'événement propre
-- à B132 (la tentative de révocation orpheline juste en dessous) est en file d'attente à ce stade,
-- garantissant que l'exception levée ici est bien attribuable à CE test, jamais à un événement antérieur
-- mal isolé.
DO $$
DECLARE
    v_membership   UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_override_ok  UUID := current_setting('carbon_test09.b9_override_ok')::uuid;
    v_prop_revoke  UUID;
    v_msg          TEXT;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_revoke := public.propose_member_distribution_override(
        'revoke', v_membership, v_override_ok, NULL, NULL, NULL, NULL, 'TEST-09 neuvième revue : révocation orpheline');
    PERFORM pg_temp.carbon_test_clear_actor();
    -- v_prop_revoke reste 'pending', 0/3 -- jamais activée.

    BEGIN
        UPDATE public.member_distribution_overrides
        SET revoked_at = clock_timestamp(), revoked_by = pg_temp.carbon_test_profile('aggadmin'), revocation_proposal_id = v_prop_revoke
        WHERE id = v_override_ok;
        SET CONSTRAINTS trg_carbon_check_member_distribution_override_revocation_integrity IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B132 member_distribution_overrides : révocation référençant une proposition revoke encore pending (jamais activated, 0/3 approuvée) rejetée au contrôle différé forcé (bloqueur 4, neuvième revue)',
        v_msg IS NOT NULL AND v_msg ILIKE '%activated%' AND v_msg ILIKE '%COMMIT%', v_msg);

    -- L'override reste NON révoqué (la tentative ci-dessus a été annulée par le savepoint implicite) --
    -- reconfirmé explicitement pour garantir sa disponibilité au test B134 (doublon proposal_id) plus bas.
    PERFORM pg_temp.carbon_test_assert('B', 'B132bis contre-épreuve (neuvième revue) : override B_9e_1 toujours actif après la tentative de révocation orpheline annulée',
        (SELECT revoked_at IS NULL FROM public.member_distribution_overrides WHERE id = v_override_ok));
END $$;

-- B133 (bloqueur 4F, CORRIGÉE à la DOUZIÈME revue statique, bloqueur 2) : doublon de distribution_rule
-- pour LE MÊME proposal_id -- UNIQUE(proposal_id) rejette immédiatement (aucun besoin de contrôle
-- différé). L'ancienne version fermait artificiellement la première règle (UPDATE effective_to SANS
-- successeur) uniquement pour écarter l'EXCLUDE de chevauchement lors du deuxième INSERT -- exactement
-- la fermeture orpheline (révocation autonome) que le nouveau constraint trigger de fermeture
-- (trg_carbon_check_distribution_rule_closure_integrity) interdit désormais. La première règle reste
-- maintenant ACTIVE, jamais fermée : le doublon est tenté sur un SECOND aggregator, dédié, créé ici,
-- n'ayant jamais porté aucune distribution_rule -- aucun risque de chevauchement EXCLUDE, isolant
-- proprement la seule violation testée : UNIQUE(proposal_id) (proposal_id n'est pas scopé par
-- aggregator_id -- son unicité est globale, la table cible peut légitimement différer de celle de la
-- proposition, la violation UNIQUE survient avant même que le contrôle différé aggregator_id ne soit atteint).
DO $$
DECLARE
    v_agg      UUID := current_setting('carbon_test09.b9_fresh_aggregator')::uuid;
    v_agg_dup  UUID := gen_random_uuid();
    v_prop_dup UUID;
    v_rule1    UUID;
BEGIN
    INSERT INTO public.aggregators (id, name) VALUES (v_agg_dup, 'TEST-09 DOUZIÈME REVUE — Regroupement dédié B133 (jamais aucune distribution_rule)');

    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_dup := public.propose_distribution_rule(v_agg, 22.00, 3.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();
    UPDATE public.distribution_rule_proposals SET aggregator_admin_approved_by = pg_temp.carbon_test_profile('aggadmin'), aggregator_admin_approved_at = clock_timestamp() WHERE id = v_prop_dup;
    UPDATE public.distribution_rule_proposals SET operator_admin_approved_by = pg_temp.carbon_test_profile('op'), operator_admin_approved_at = clock_timestamp() WHERE id = v_prop_dup;

    INSERT INTO public.distribution_rules (aggregator_id, platform_fee_pct, reserve_pct, default_weight, effective_from, proposal_id, created_by)
    VALUES (v_agg, 22.00, 3.00, 1.0, clock_timestamp(), v_prop_dup, pg_temp.carbon_test_profile('aggadmin'))
    RETURNING id INTO v_rule1;
    UPDATE public.distribution_rule_proposals SET status = 'activated', activated_distribution_rule_id = v_rule1 WHERE id = v_prop_dup;
    -- v_rule1 reste ACTIVE (jamais fermée) -- ne prépare plus artificiellement ce test par une fermeture
    -- orpheline, désormais structurellement interdite.

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B133 distribution_rules : doublon (deuxième ligne, SECOND aggregator dédié jamais utilisé, aucun chevauchement EXCLUDE possible) pour LE MÊME proposal_id rejeté immédiatement par UNIQUE(proposal_id) (bloqueur 4, neuvième revue ; fixture corrigée à la douzième revue, bloqueur 2 -- v_rule1 reste active, jamais fermée orphelinement)',
        format('INSERT INTO public.distribution_rules (aggregator_id, platform_fee_pct, reserve_pct, default_weight, effective_from, proposal_id, created_by) VALUES (%L::uuid, 22.00, 3.00, 1.0, clock_timestamp(), %L::uuid, %L::uuid)',
            v_agg_dup, v_prop_dup, pg_temp.carbon_test_profile('aggadmin')),
        'distribution_rules_proposal_id_unique');
END $$;

-- ────────────────────────────────────────────────────────────
-- NOUVEAUX TESTS — DOUZIÈME revue statique (bloqueur 2) : preuve positive d'un remplacement légitime de
--   distribution_rule (fermeture + création dans la même activation, contraintes de création ET de
--   fermeture forcées IMMEDIATE, aucune erreur) et preuve négative d'une fermeture orpheline forcée
--   (rejetée). Regroupement DÉDIÉ, entièrement isolé (jamais utilisé ailleurs), pour ne jamais risquer de
--   collision EXCLUDE avec les fixtures existantes.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_agg_close UUID := gen_random_uuid();
    v_prop_a    UUID;
    v_prop_b    UUID;
    v_rule_a    UUID;
    v_rule_b    UUID;
    v_msg       TEXT;
BEGIN
    INSERT INTO public.aggregators (id, name) VALUES (v_agg_close, 'TEST-09 DOUZIÈME REVUE — Regroupement dédié fermeture distribution_rules');
    INSERT INTO public.aggregator_admins (aggregator_id, user_id, role) VALUES (v_agg_close, pg_temp.carbon_test_profile('aggadmin'), 'primary_admin');

    -- Première règle active (RULE_A), légitimement activée (2/2 réel, via les RPC réelles).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_a := public.propose_distribution_rule(v_agg_close, 10.00, 5.00, 1.0);
    PERFORM public.approve_distribution_rule_as_aggregator_admin(v_prop_a);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_distribution_rule_as_operator_admin(v_prop_a);
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT activated_distribution_rule_id INTO v_rule_a FROM public.distribution_rule_proposals WHERE id = v_prop_a;

    -- Remplacement légitime (RULE_B), 2/2 réel -- déclenche automatiquement la fermeture de RULE_A ET la
    -- création de RULE_B dans la MÊME activation (carbon_try_activate_distribution_rule_proposal, même v_now).
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop_b := public.propose_distribution_rule(v_agg_close, 11.00, 6.00, 1.0);
    PERFORM public.approve_distribution_rule_as_aggregator_admin(v_prop_b);
    PERFORM pg_temp.carbon_test_clear_actor();
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);
    PERFORM public.approve_distribution_rule_as_operator_admin(v_prop_b);
    PERFORM pg_temp.carbon_test_clear_actor();

    SELECT activated_distribution_rule_id INTO v_rule_b FROM public.distribution_rule_proposals WHERE id = v_prop_b;

    -- Preuve positive (DOUZIÈME revue, bloqueur 2) : force IMMEDIATE la création (RULE_B) ET la fermeture
    -- (RULE_A) -- aucune erreur, même patron déjà établi pour B72bis (override, DIXIÈME revue).
    BEGIN
        SET CONSTRAINTS trg_carbon_check_distribution_rule_proposal_integrity IMMEDIATE;
        SET CONSTRAINTS trg_carbon_check_distribution_rule_closure_integrity IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B_12e_7 (douzième revue) : remplacement légitime de distribution_rule (RULE_A fermée, RULE_B créée, même activation) force les DEUX constraint triggers (création + fermeture) IMMEDIATE sans aucune erreur ; old.effective_to = new.effective_from EXACTEMENT ; une seule règle active finale',
        v_msg IS NULL
        AND (SELECT effective_to FROM public.distribution_rules WHERE id = v_rule_a) = (SELECT effective_from FROM public.distribution_rules WHERE id = v_rule_b)
        AND (SELECT count(*) FROM public.distribution_rules WHERE aggregator_id = v_agg_close AND effective_to IS NULL) = 1,
        v_msg);
    SET CONSTRAINTS trg_carbon_check_distribution_rule_proposal_integrity DEFERRED;
    SET CONSTRAINTS trg_carbon_check_distribution_rule_closure_integrity DEFERRED;

    -- Preuve négative (DOUZIÈME revue, bloqueur 2) : UPDATE direct fermant RULE_B (actuellement active)
    -- SANS successeur -- rejeté par le constraint trigger de fermeture forcé IMMEDIATE (implicite savepoint
    -- PL/pgSQL : l'UPDATE ci-dessous est annulé avec l'exception, RULE_B reste active pour la suite).
    BEGIN
        UPDATE public.distribution_rules SET effective_to = clock_timestamp() WHERE id = v_rule_b;
        SET CONSTRAINTS trg_carbon_check_distribution_rule_closure_integrity IMMEDIATE;
        v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp.carbon_test_assert('B', 'B_12e_8 (douzième revue) : fermeture orpheline (UPDATE direct effective_to SANS successeur) sur une distribution_rule active rejetée par le constraint trigger de fermeture forcé IMMEDIATE',
        v_msg IS NOT NULL AND v_msg ILIKE '%successeur exact%', v_msg);
    SET CONSTRAINTS trg_carbon_check_distribution_rule_closure_integrity DEFERRED;
END $$;

-- B134 (bloqueur 4G) : doublon de member_distribution_override (création) pour LE MÊME proposal_id que
-- l'override VALIDE (B_9e_1) -- UNIQUE(proposal_id) rejette immédiatement. override_type différent
-- ('reserve_pct' au lieu de 'fee_pct') pour écarter l'EXCLUDE de chevauchement de l'analyse.
DO $$
DECLARE
    v_membership UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_prop_ok    UUID := current_setting('carbon_test09.b9_prop_ok')::uuid;
BEGIN
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B134 member_distribution_overrides : doublon (deuxième ligne) pour LE MÊME proposal_id que l''override B_9e_1 rejeté immédiatement par UNIQUE(proposal_id) (bloqueur 4, neuvième revue)',
        format('INSERT INTO public.member_distribution_overrides (aggregator_membership_id, override_type, override_value, effective_from, effective_until, proposal_id, created_by) VALUES (%L::uuid, ''reserve_pct'', 5.00, ''2053-01-01''::date, ''2053-12-31''::date, %L::uuid, %L::uuid)',
            v_membership, v_prop_ok, pg_temp.carbon_test_profile('aggadmin')),
        'member_distribution_overrides_proposal_id_unique');
END $$;

-- ────────────────────────────────────────────────────────────
-- 3tredecies. NOUVEAUX TESTS — DIXIÈME revue statique :
--   Bloqueur critique 1 — join_aggregator() ne doit JAMAIS régresser vers la forme historique
--   vulnérable de migration 02 (sans COALESCE) : preuve structurelle (test A, pg_get_functiondef) ET
--   comportementale (test B, JWT normal sans app_metadata.role, aucune autorité aggregator_admin =>
--   rejeté, reproduisant exactement le cas NULL qui avait exposé la faille de migration 02).
--   Bloqueur 3 — un nouvel objet économique (member_distribution_overrides / distribution_rules) doit
--   naître strictement dans son état initial neutre : 3 tests négatifs d'INSERT direct.
-- ────────────────────────────────────────────────────────────

-- Test A (bloqueur critique 1) : assertion structurelle — la définition RÉELLEMENT déployée de
-- join_aggregator() contient bien les deux COALESCE de la migration 03, le verrou FOR UPDATE sur
-- aggregators, et clock_timestamp() capturé (nécessairement après ce verrou dans le corps de la
-- fonction, revue statique du texte source faisant foi pour l'ordre — voir §17 point 9bis).
DO $$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef('public.join_aggregator(uuid,uuid)'::regprocedure) INTO v_def;
    PERFORM pg_temp.carbon_test_assert('A', 'A_10e_1 (dixième revue) : join_aggregator() contient les deux COALESCE de la migration 03 (is_aggregator_admin/is_platform_superadmin), le verrou FOR UPDATE sur aggregators et clock_timestamp() après ce verrou',
        v_def ILIKE '%COALESCE(public.is_aggregator_admin(p_aggregator_id), false)%'
        AND v_def ILIKE '%COALESCE(public.is_platform_superadmin(), false)%'
        AND v_def ILIKE '%FOR UPDATE%'
        AND v_def ILIKE '%clock_timestamp()%');
END $$;

-- Test B (bloqueur critique 1, TEST COMPORTEMENTAL OBLIGATOIRE) : utilisateur authenticated NORMAL —
-- auth.uid() réel ('outsider', aucune autorité aggregator_admin, aucun rôle superadmin, aucune
-- adhésion active donnant accès au regroupement cible — identité réutilisée comme 'exmember' plus
-- haut dans ce fichier, cf. GATE 3 correction minimale du harnais ; propriété inchangée puisque le
-- regroupement cible ici est distinct, généré par gen_random_uuid()), JWT SANS clé
-- app_metadata.role (carbon_test_set_actor(..., false)) — reproduit EXACTEMENT le cas NULL qui avait
-- exposé la faille de migration 02 : is_platform_superadmin() renvoie NULL (pas false) pour ce profil,
-- et is_aggregator_admin() renvoie false (jamais NULL, construite avec EXISTS) — sans les deux COALESCE,
-- `IF NOT (false OR NULL)` vaudrait `IF NOT NULL`, qui ne s'exécute jamais en PL/pgSQL.
DO $$
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('outsider'), false);
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_10e_1 (dixième revue) : join_aggregator() rejeté pour un utilisateur authenticated normal (aucune autorité aggregator_admin, JWT sans app_metadata.role) — reproduit le cas NULL de la faille migration 02',
        format('SELECT public.join_aggregator(%L::uuid, %L::uuid)', gen_random_uuid(), gen_random_uuid()),
        'Seul un administrateur du regroupement cible ou un super-administrateur');
    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- Bloqueur 3A, test 1 (dixième revue) : INSERT direct d'un override actif (non révoqué) avec
-- revocation_proposal_id SEUL renseigné (revoked_at/revoked_by NULL) — rejeté par la garde BEFORE
-- INSERT (trg_carbon_guard_member_distribution_override_insert), avant même le CHECK all-or-none.
DO $$
DECLARE
    v_membership UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_prop       UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop := public.propose_member_distribution_override('create', v_membership, NULL, 'reserve_pct', 8.00, '2060-01-01'::date, '2060-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_10e_2 (dixième revue) : INSERT direct d''un override actif avec revocation_proposal_id SEUL renseigné (revoked_at/revoked_by NULL) rejeté par la garde BEFORE INSERT (bloqueur 3A)',
        format('INSERT INTO public.member_distribution_overrides (aggregator_membership_id, override_type, override_value, effective_from, effective_until, proposal_id, created_by, revocation_proposal_id) VALUES (%L::uuid, ''reserve_pct'', 8.00, ''2060-01-01''::date, ''2060-12-31''::date, %L::uuid, %L::uuid, %L::uuid)',
            v_membership, v_prop, pg_temp.carbon_test_profile('aggadmin'), v_prop),
        'doit toujours naître strictement non révoqué');
END $$;

-- Bloqueur 3A, test 2 (dixième revue) : INSERT direct d'un override DÉJÀ révoqué (les trois colonnes
-- revoked_at/revoked_by/revocation_proposal_id toutes renseignées dès l'INSERT) — rejeté par la MÊME
-- garde BEFORE INSERT, jamais seulement par le CHECK all-or-none (qui, seul, aurait accepté cette ligne
-- puisque les trois colonnes y sont mutuellement cohérentes).
DO $$
DECLARE
    v_membership UUID := current_setting('carbon_test09.b9_fresh_membership')::uuid;
    v_prop       UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop := public.propose_member_distribution_override('create', v_membership, NULL, 'reserve_pct', 8.50, '2061-01-01'::date, '2061-12-31'::date, NULL);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_10e_3 (dixième revue) : INSERT direct d''un override DÉJÀ révoqué (les trois colonnes renseignées dès l''INSERT) rejeté par la garde BEFORE INSERT, jamais seulement par le CHECK all-or-none (bloqueur 3A)',
        format('INSERT INTO public.member_distribution_overrides (aggregator_membership_id, override_type, override_value, effective_from, effective_until, proposal_id, created_by, revoked_at, revoked_by, revocation_proposal_id) VALUES (%L::uuid, ''reserve_pct'', 8.50, ''2061-01-01''::date, ''2061-12-31''::date, %L::uuid, %L::uuid, clock_timestamp(), %L::uuid, %L::uuid)',
            v_membership, v_prop, pg_temp.carbon_test_profile('aggadmin'), pg_temp.carbon_test_profile('aggadmin'), v_prop),
        'doit toujours naître strictement non révoqué');
END $$;

-- Bloqueur 3B, test (dixième revue) : INSERT privilégié d'une NOUVELLE distribution_rule avec
-- effective_to déjà renseigné — rejeté par la garde BEFORE INSERT (trg_carbon_guard_distribution_rule_insert).
DO $$
DECLARE
    v_agg  UUID := '66666666-6666-6666-6666-200000000001';
    v_prop UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('aggadmin'), false);
    v_prop := public.propose_distribution_rule(v_agg, 12.00, 5.00, 1.0);
    PERFORM pg_temp.carbon_test_clear_actor();

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_10e_4 (dixième revue) : INSERT privilégié d''une nouvelle distribution_rule avec effective_to déjà renseigné rejeté par la garde BEFORE INSERT (bloqueur 3B)',
        format('INSERT INTO public.distribution_rules (aggregator_id, platform_fee_pct, reserve_pct, default_weight, effective_from, effective_to, proposal_id, created_by) VALUES (%L::uuid, 12.00, 5.00, 1.0, clock_timestamp(), clock_timestamp() + interval ''1 day'', %L::uuid, %L::uuid)',
            v_agg, v_prop, pg_temp.carbon_test_profile('aggadmin')),
        'doit toujours naître active');
END $$;

-- ────────────────────────────────────────────────────────────
-- 3quaterdecies-bis. Émission DÉDIÉE pour 3quindecies (ci-dessous), corrigée après exécution réelle de
--   GATE 3 : create_credit_issuance() vérifie la capacité cumulée au niveau de la verification_session /
--   chaîne de supersession des outcomes, pas seulement du verification_outcome_id isolé. Un nouvel
--   outcome sur la MÊME session que issuance_bis (...900000000002) resterait donc rattaché à une
--   capacité déjà consommée à 2/2 par issuance_bis -- il faut une verification_session ET un
--   verification_outcome entièrement neufs et indépendants, jamais seulement l'un des deux.
-- ────────────────────────────────────────────────────────────
INSERT INTO public.verification_sessions (id, project_id, status, reporting_period_start, reporting_period_end, verifier_user_id)
SELECT '66666666-6666-6666-6666-900000000005', '66666666-6666-6666-6666-400000000002', 'completed', current_date - 40, current_date - 31,
       pg_temp.carbon_test_profile('op');

INSERT INTO public.verification_outcomes (id, verification_session_id, status, calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e, verification_report_document_id, verified_by)
SELECT '66666666-6666-6666-6666-910000000005', '66666666-6666-6666-6666-900000000005', 'active', 1, 1, 1,
       '66666666-6666-6666-6666-800000000001', pg_temp.carbon_test_profile('op');

-- ────────────────────────────────────────────────────────────
-- 3quindecies. NOUVEAUX TESTS — DOUZIÈME revue statique (bloqueur critique 1) : immutabilité stricte du
--   cycle de vie de credit_sales. 6 tests négatifs minimaux prouvant que le bypass UPDATE (hors
--   transition légitime) est désormais rejeté, aussi bien pour les colonnes encore NULL (draft) que pour
--   les colonnes déjà figées (confirmed/settled) — confirmed_at/confirmed_by immuables À VIE une fois posés.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_iss_id     UUID;
    v_lot_life   UUID;
    v_sale_draft UUID;
    v_sale_conf  UUID;
BEGIN
    PERFORM pg_temp.carbon_test_set_actor(pg_temp.carbon_test_profile('op'), true);

    -- Vente DRAFT dédiée (jamais confirmée) -- tests 1 et 2 (draft).
    v_sale_draft := public.create_credit_sale('66666666-6666-6666-6666-100000000001'::uuid, 10.00, 'TEST-09 douzième revue (draft)');

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_12e_1 (douzième revue) : vente draft, UPDATE confirmed_at SEUL (sans transition de statut) rejeté',
        format('UPDATE public.credit_sales SET confirmed_at = clock_timestamp() WHERE id = %L::uuid', v_sale_draft),
        'ne peuvent être posés que par la transition draft->confirmed');

    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_12e_2 (douzième revue) : vente draft, injection de cancelled_at SEUL (sans transition de statut) rejetée',
        format('UPDATE public.credit_sales SET cancelled_at = clock_timestamp() WHERE id = %L::uuid', v_sale_draft),
        'ne peuvent être posés que par la transition draft->cancelled');

    -- Émission + lot dédiés, minimaux, pour une vente CONFIRMED dédiée -- tests 3, 4, 5, 6. Rattachée à
    -- une verification_session/outcome ENTIÈREMENT dédiés (voir bloc ci-dessus), jamais
    -- ...910000000002 (déjà consommé à 2/2 par issuance_bis).
    v_iss_id := public.create_credit_issuance(
        '66666666-6666-6666-6666-910000000005'::uuid,
        jsonb_build_array(
            jsonb_build_object('organization_id','66666666-6666-6666-6666-100000000003','aggregator_membership_id','66666666-6666-6666-6666-500000000001','commercialization_mandate_id','66666666-6666-6666-6666-600000000001','contributed_tco2e',1)
        )
    );
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_issuance_capacity DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_credit_issuance_has_sources DEFERRED;
    SET CONSTRAINTS trg_carbon_validate_sources_sum IMMEDIATE;
    SET CONSTRAINTS trg_carbon_validate_sources_sum DEFERRED;
    PERFORM public.mark_credit_issuance_eligible(v_iss_id);
    PERFORM public.submit_credit_issuance(v_iss_id, 'TEST-09 Registre douzième revue');
    PERFORM public.record_registry_issuance(v_iss_id, 'TEST-09-REG-012', clock_timestamp());
    v_lot_life := public.issue_credit_lot(v_iss_id, 1, 2024);

    v_sale_conf := public.create_credit_sale('66666666-6666-6666-6666-100000000001'::uuid, 20.00, 'TEST-09 douzième revue (confirmed)');
    PERFORM public.add_credit_sale_lot(v_sale_conf, v_lot_life);
    PERFORM public.confirm_credit_sale(v_sale_conf);

    -- Test 3 : réécriture de confirmed_at sur une vente déjà confirmed -- capturé par la garde
    -- d'immutabilité générale (en tête de fonction), avant même tout branchement sur le statut.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_12e_3 (douzième revue) : vente confirmed, réécriture de confirmed_at rejetée (immuable à vie)',
        format('UPDATE public.credit_sales SET confirmed_at = clock_timestamp() WHERE id = %L::uuid', v_sale_conf),
        'confirmed_at est immuable à vie');

    -- Test 4 : réécriture de confirmed_by, même mécanisme.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_12e_4 (douzième revue) : vente confirmed, réécriture de confirmed_by rejetée (immuable à vie)',
        format('UPDATE public.credit_sales SET confirmed_by = %L::uuid WHERE id = %L::uuid', pg_temp.carbon_test_profile('outsider'), v_sale_conf),
        'confirmed_by est immuable à vie');

    -- Test 5 : injection de settled_at SEUL, statut inchangé (toujours 'confirmed').
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_12e_5 (douzième revue) : vente confirmed, injection de settled_at SEUL (sans transition confirmed->settled) rejetée',
        format('UPDATE public.credit_sales SET settled_at = clock_timestamp() WHERE id = %L::uuid', v_sale_conf),
        'ne peuvent être posés que par la transition confirmed->settled');

    -- Test 6 : tentative de transition confirmed->settled RÉELLE, mais modifiant simultanément
    -- confirmed_at -- rejetée par la MÊME garde d'immutabilité générale que le test 3 (elle s'applique
    -- avant tout branchement sur la transition demandée, quelle qu'elle soit).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_12e_6 (douzième revue) : transition confirmed->settled avec modification simultanée de confirmed_at rejetée',
        format('UPDATE public.credit_sales SET status = ''settled'', settled_at = clock_timestamp(), settled_by = %L::uuid, settlement_reference = ''TEST-12e'', confirmed_at = clock_timestamp() WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('op'), v_sale_conf),
        'confirmed_at est immuable à vie');

    -- Test 7 (TREIZIÈME revue statique, bloqueur réel) : transition draft->cancelled RÉELLE, mais
    -- modifiant simultanément total_tco2e ET seller_organization_id -- doit être rejetée par les
    -- nouvelles gardes ajoutées dans la branche draft->cancelled (absentes avant cette revue).
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_13e_1 (treizième revue) : transition draft->cancelled avec modification simultanée de total_tco2e et seller_organization_id rejetée',
        format('UPDATE public.credit_sales SET status = ''cancelled'', cancelled_at = clock_timestamp(), cancelled_by = %L::uuid, cancel_reason = ''TEST-13e'', total_tco2e = 5, seller_organization_id = %L::uuid WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('op'), '66666666-6666-6666-6666-100000000002'::uuid, v_sale_draft),
        'total_tco2e/seller_organization_id ne doivent pas changer à cette transition');

    -- Test 8 (TREIZIÈME revue statique, bloqueur réel) : transition confirmed->settled RÉELLE, mais
    -- modifiant simultanément seller_organization_id -- doit être rejetée par la nouvelle garde ajoutée
    -- dans la branche confirmed->settled (absente avant cette revue) ; le vendeur figé à la confirmation
    -- (§17 point 10) ne doit jamais pouvoir changer au règlement.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_13e_2 (treizième revue) : transition confirmed->settled avec modification simultanée de seller_organization_id rejetée',
        format('UPDATE public.credit_sales SET status = ''settled'', settled_at = clock_timestamp(), settled_by = %L::uuid, settlement_reference = ''TEST-13e'', seller_organization_id = %L::uuid WHERE id = %L::uuid',
            pg_temp.carbon_test_profile('op'), '66666666-6666-6666-6666-100000000002'::uuid, v_sale_conf),
        'seller_organization_id est figé depuis la confirmation');

    -- Test 9 (TREIZIÈME revue statique, correction 1) : preuve statique minimale que
    -- carbon_guard_credit_sale_cost_insert() rejette toujours un INSERT sur une vente qui n'est plus
    -- draft, après l'ajout du FOR UPDATE sur credit_sales. Le FOR UPDATE ne change pas ce comportement en
    -- contexte non concurrent (une seule transaction) — seule la sérialisation réelle avec
    -- confirm_credit_sale() sous concurrence est prouvée par le scénario STAGING N, non exécutable ici.
    PERFORM pg_temp.carbon_test_assert_raises('B', 'B_13e_3 (treizième revue) : INSERT credit_sale_costs sur une vente confirmed (donc non-draft) rejeté après ajout du FOR UPDATE',
        format('INSERT INTO public.credit_sale_costs (credit_sale_id, cost_type, amount, currency) VALUES (%L::uuid, ''other'', 10.00, ''CAD'')', v_sale_conf),
        'n''est pas draft');

    PERFORM pg_temp.carbon_test_clear_actor();
END $$;

-- ────────────────────────────────────────────────────────────
-- 4. GATE FINAL — véritable porte, pas un simple résumé.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_total    INT;
    v_failed   INT;
    v_dupes    INT;
    -- Recompté mécaniquement après la DOUZIÈME revue statique — comptage mécanique via grep sur les
    -- appels PERFORM réels uniquement (jamais une simple somme mentale ; grep -c sur "assert('A'" seul
    -- se compterait lui-même dans ce commentaire, d'où le préfixe PERFORM ci-dessous pour ne matcher
    -- que le code, pas la documentation) :
    --   grep -c "PERFORM pg_temp.carbon_test_assert(''A''," => 37 (36 hérité des onze revues précédentes
    --                                                          [A1-A28 avec bis, y compris A9bis corrigée,
    --                                                          A14bis, A_10e_1 et A_11e_1..A_11e_5] +
    --                                                          A_12e_1 nouvelle de la DOUZIÈME revue
    --                                                          statique — bloqueur 2, prouvant qu'anon ET
    --                                                          authenticated n'ont EXECUTE sur la nouvelle
    --                                                          fonction interne carbon_check_distribution_
    --                                                          rule_closure_integrity())
    --   grep -c "PERFORM pg_temp.carbon_test_assert(''B''," => 98 (96 hérité des onze revues précédentes
    --                                                          [B1-B107 avec bis/ter/quater/quinquies/
    --                                                          septies, y compris B_9e_0/B_9e_1/
    --                                                          B128-B132/B132bis de la NEUVIÈME revue,
    --                                                          B72bis/B72quater de la DIXIÈME revue et
    --                                                          B72ter de la ONZIÈME revue] + B_12e_7 et
    --                                                          B_12e_8 nouvelles de la DOUZIÈME revue
    --                                                          statique — bloqueur 2, preuve positive
    --                                                          (remplacement légitime, contraintes forcées
    --                                                          IMMEDIATE, un seul rule actif) et preuve
    --                                                          négative (fermeture orpheline rejetée) du
    --                                                          nouveau constraint trigger de fermeture)
    --   grep -c "PERFORM pg_temp.carbon_test_assert_raises(''B''," => 60 (52 hérité des onze revues
    --                                                          précédentes, inchangé depuis la DIXIÈME
    --                                                          revue statique + B_12e_1..B_12e_6 de la
    --                                                          DOUZIÈME revue statique — bloqueur 1, les
    --                                                          6 tests négatifs de bypass du cycle de vie
    --                                                          credit_sales : draft/confirmed_at seul,
    --                                                          réécriture confirmed_at, réécriture
    --                                                          confirmed_by, injection settled_at seul,
    --                                                          injection cancelled_at/cancel_reason seul,
    --                                                          transition confirmed->settled avec
    --                                                          modification simultanée de confirmed_at +
    --                                                          B_13e_1/B_13e_2 de la TREIZIÈME revue
    --                                                          statique — bloqueur réel identifié :
    --                                                          seller_organization_id/total_tco2e n'étaient
    --                                                          pas revérifiés dans les branches de
    --                                                          transition draft->cancelled et
    --                                                          confirmed->settled elles-mêmes) + B_13e_3
    --                                                          nouvelle, TOUJOURS de la TREIZIÈME revue
    --                                                          statique (correction 1) : preuve statique
    --                                                          minimale que carbon_guard_credit_sale_cost_
    --                                                          insert() rejette toujours un INSERT hors
    --                                                          draft après l'ajout du FOR UPDATE sur
    --                                                          credit_sales.
    -- Total = 37 + 98 + 61 = 196.
    v_expected INT := 196;
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

    RAISE NOTICE '=== Migration 09 — % assertions (% attendues), % échouées, % libellés dupliqués ===', v_total, v_expected, v_failed, v_dupes;

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

-- Aucune donnée résiduelle des Parties A/fixtures/B : ROLLBACK complet.
ROLLBACK;

-- Pas de DROP TABLE explicite ici (même raisonnement que tests/08) : selon
-- l'environnement d'exécution, le ROLLBACK ci-dessus peut déjà avoir annulé
-- la CREATE TEMP TABLE elle-même. Une TEMP TABLE disparaît de toute façon
-- automatiquement à la fin de la session.
