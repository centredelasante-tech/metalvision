-- ============================================================
-- Migration 09 — credit_sales et dépendances (modèle commercial et financier)
-- ============================================================
--
-- STATUT : PROPOSITION SOUMISE POUR REVUE — NON EXÉCUTÉE.
-- Conception validée : Tranche0-Carbone-Architecture.md §17 (fermée après
-- trois passes de revue décisionnelle le 22 juillet 2026, cf. §17 point 20).
-- Autorisation explicite de rédaction du SQL donnée par l'utilisateur le
-- 22 juillet 2026 : « Le §17 est considéré comme entièrement stabilisé et
-- cohérent après revue finale. Autorisation explicite accordée pour
-- rédiger uniquement : 09_carbon_sales_financial_model.sql /
-- 09_test_carbon_sales_financial_model.sql. »
--
-- MIGRATION DE CRÉATION PURE (§17 point 0bis/18) : 9 CREATE TABLE, aucun
-- traitement legacy, aucune transformation d'ancienne table commerciale.
-- L'audit live du 22 juillet 2026 a confirmé que les 7 tables initialement
-- attendues sont absentes du schéma public (5 supprimées pendant la
-- remédiation de 08, 2 n'ayant jamais existé) — terrain structurellement
-- vide, contrairement à 08 qui avait dû reconstruire un objet hérité.
--
-- DÉPENDANCES STRUCTURELLES :
--   01 (carbon_business_events à 38 valeurs event_type après extension par
--       06/07/08, 14 valeurs object_type après extension par 06,
--       carbon_reject_update_delete())
--   02 (aggregator_memberships)
--   05 (is_assigned_verifier — non utilisée directement ici, dépendance
--       transitive via credit_issuances/verification_outcomes)
--   06 (platform_operators, carbon_commercialization_mandates,
--       is_platform_operator(), is_platform_operator_actor(),
--       is_platform_operator_admin(), is_org_admin(), is_organization_member(),
--       is_aggregator_admin(), is_aggregator_primary_admin(), is_platform_superadmin())
--   07 (credit_issuances, credit_issuance_sources — APPLIQUÉE ET VALIDÉE EN
--       RÉEL, lue telle quelle, AUCUNE modification)
--   08 (credit_lots, son trigger de machine à états commercial_status déjà
--       posé, APPLIQUÉE ET VALIDÉE EN RÉEL 87/87 — lue telle quelle, AUCUNE
--       modification de 08_carbon_lots_commercial_cycle.sql ni de son test
--       compagnon ; CORRIGÉ à la DOUZIÈME revue statique — périmé depuis la
--       HUITIÈME revue statique (bloqueur 15) : 09 ajoute désormais DEUX
--       triggers ciblés sur credit_lots, jamais un seul :
--       (1) trg_carbon_release_credit_sale_lot_on_external_void (coordination
--           du cascade externe, AFTER UPDATE OF commercial_status) ;
--       (2) trg_carbon_guard_credit_lots_sale_consistency (cohérence croisée
--           credit_sale_lots <-> commercial_status, BEFORE UPDATE OF
--           commercial_status) ;
--       — ni l'un ni l'autre ne recrée, ne remplace ou ne modifie jamais le
--       trigger FSM de validité de transition trg_carbon_credit_lots_before_update
--       de la migration 08, qui reste inchangé et s'exécute en premier)
--
-- REPRÉSENTATION platform_fee / reserve — CORRIGÉE APRÈS LA PREMIÈRE REVUE
-- STATIQUE DE 09 (22 juillet 2026, point 1), décision d'architecture actée
-- dans Tranche0-Carbone-Architecture.md §6 : la version précédente de ce
-- fichier fusionnait le frais de plateforme dans reserve_amount de la ligne
-- 'reserve' — rejeté, un frais retenu par METALTRACE et une réserve
-- provisionnée pour le regroupement sont deux faits économiques distincts,
-- et les nommer tous deux « réserve » aurait empêché toute lecture
-- comptable honnête (et risqué une confusion avec credit_sale_costs.
-- cost_type='platform_fee', qui est un COÛT DE LA VENTE ENTIÈRE prélevé en
-- amont de la répartition, §3 — jamais le même montant que le nouvel
-- allocation_type='platform_fee' ci-dessous, qui porte LA PART DU FRAIS
-- IMPUTABLE À CHAQUE PAIRE (organization_id, aggregator_id), après
-- répartition). credit_sale_allocations.allocation_type porte
-- TROIS valeurs (§6 de l'architecture) : 'carbon_revenue', 'reserve'
-- (réserve véritable UNIQUEMENT, jamais le frais), 'platform_fee' (le
-- frais effectivement retenu, ligne distincte, allocated_tco2e NULL).
-- Conservation à trois composantes, exactement :
--     SUM(net_amount) WHERE allocation_type IN ('carbon_revenue','reserve','platform_fee') = net_distributable_amount
-- jamais une fusion du frais dans la réserve, jamais un double comptage.
--
-- ALLOCATIONS MANUELLES HORS PÉRIMÈTRE — DÉCISION EXPLICITE APRÈS LA
-- DEUXIÈME REVUE STATIQUE (22 juillet 2026, point 6) : la version
-- précédente prévoyait aussi 'expense_reimbursement'/'bonus'/'adjustment'
-- comme « insertions manuelles hors RPC » — retirées, décision
-- d'architecture actée : aucune RPC de ce MVP ne les crée, aucune écriture
-- directe n'est exposée (§15), et credit_sale_allocations_unique (4
-- colonnes) ne peut de toute façon pas représenter proprement plusieurs
-- ajustements par paire (organization_id, aggregator_id). Toute correction
-- financière post-confirmation passe exclusivement par
-- credit_sale_adjustments (ledger append-only au niveau de la vente
-- entière, point 3) — reporté hors MVP 09, pas improvisé silencieusement.
--
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION — dépendances structurelles + idempotence (discipline
--    INC-DATA-01 : revérifiée ici, jamais supposée depuis l'audit du 22
--    juillet 2026 ou depuis §17, qui peuvent être devenus périmés).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_dummy INT;
BEGIN
    -- 0.a Dépendances transverses (01/02/06/07/08 appliquées).
    IF to_regclass('public.carbon_business_events') IS NULL
       OR to_regprocedure('public.carbon_reject_update_delete()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : carbon_business_events/carbon_reject_update_delete() introuvables (migration 01).';
    END IF;
    IF to_regclass('public.aggregator_memberships') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.aggregator_memberships introuvable (migration 02).';
    END IF;
    IF to_regclass('public.aggregators') IS NULL OR to_regclass('public.organizations') IS NULL
       OR to_regclass('public.profiles') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : une table transverse de base (aggregators/organizations/profiles) est introuvable.';
    END IF;
    IF to_regclass('public.platform_operators') IS NULL
       OR to_regclass('public.carbon_commercialization_mandates') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : platform_operators/carbon_commercialization_mandates introuvables (migration 06).';
    END IF;
    IF to_regprocedure('public.is_org_admin(uuid)') IS NULL
       OR to_regprocedure('public.is_organization_member(uuid)') IS NULL
       OR to_regprocedure('public.is_aggregator_admin(uuid)') IS NULL
       OR to_regprocedure('public.is_aggregator_primary_admin(uuid)') IS NULL
       OR to_regprocedure('public.is_platform_superadmin()') IS NULL
       OR to_regprocedure('public.is_platform_operator(uuid)') IS NULL
       OR to_regprocedure('public.is_platform_operator_actor(uuid)') IS NULL
       OR to_regprocedure('public.is_platform_operator_admin(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : une fonction d''autorisation transverse (is_org_admin/is_organization_member/is_aggregator_admin/is_aggregator_primary_admin/is_platform_superadmin/is_platform_operator/is_platform_operator_actor/is_platform_operator_admin) est introuvable — is_aggregator_primary_admin() ajoutée après la première revue statique (point 3), définie dans 20260707120000_mt000a_governance_fixes.sql.';
    END IF;
    IF to_regclass('public.credit_issuances') IS NULL OR to_regclass('public.credit_issuance_sources') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_issuances/credit_issuance_sources introuvables — migration 07 appliquée ?';
    END IF;
    IF to_regclass('public.credit_lots') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.credit_lots introuvable — migration 08 appliquée ?';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'credit_lots'
          AND column_name IN ('id','credit_issuance_id','aggregator_id','quantity_tco2e','commercial_status')
        GROUP BY table_name HAVING count(*) = 5
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots (canonique, migration 08) n''a pas la forme attendue.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_lots'::regclass AND tgname = 'trg_carbon_credit_lots_before_update') THEN
        RAISE EXCEPTION 'Prévalidation échouée : le trigger de machine à états de credit_lots (migration 08) est introuvable — 09 en dépend structurellement sans le recréer.';
    END IF;

    -- 0.b Idempotence — aucune des 9 tables de cette migration ne doit déjà exister.
    IF to_regclass('public.credit_sales') IS NOT NULL OR to_regclass('public.credit_sale_lots') IS NOT NULL
       OR to_regclass('public.credit_sale_costs') IS NOT NULL OR to_regclass('public.credit_sale_adjustments') IS NOT NULL
       OR to_regclass('public.distribution_rules') IS NOT NULL OR to_regclass('public.distribution_rule_proposals') IS NOT NULL
       OR to_regclass('public.member_distribution_overrides') IS NOT NULL
       OR to_regclass('public.member_distribution_override_proposals') IS NOT NULL
       OR to_regclass('public.credit_sale_allocations') IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : au moins une des 9 tables de la migration 09 existe déjà — cette migration a-t-elle déjà été appliquée ?';
    END IF;

    RAISE NOTICE 'Prévalidation réussie : dépendances 01/02/06/07/08 présentes, terrain des 9 tables de 09 structurellement vide.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 0bis. CATALOGUE D'ÉVÉNEMENTS — event_type 38 → 48, object_type 14 → 19
--    (reconstruction sûre, même patron que 07/08 : comparaison par ENSEMBLE
--    canonique exact, jamais un simple ALTER naïf ni une présomption depuis
--    §17, discipline INC-DATA-01).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_constraint_name  TEXT;
    v_old_def          TEXT;
    v_literals         TEXT[];
    v_canonical_38     TEXT[] := ARRAY[
        -- Gouvernance des regroupements (6) — migration 01.
        'aggregator_created', 'aggregator_membership_started', 'aggregator_membership_ended',
        'aggregator_admin_appointed', 'aggregator_admin_revoked', 'aggregator_primary_admin_transferred',
        -- Rattachement CCF<->MRV (2) — migration 01.
        'ccf_mrv_link_started', 'ccf_mrv_link_ended',
        -- Vérification (4) — migration 01.
        'verification_session_started', 'verification_session_completed',
        'verification_outcome_recorded', 'verification_outcome_superseded',
        -- Émission réglementaire (5) — migration 01.
        'credit_issuance_created', 'credit_issuance_submitted', 'credit_issuance_issued',
        'credit_issuance_externally_cancelled', 'credit_issuance_voided',
        -- Cycle commercial des lots (5) — migration 01.
        'credit_lot_issued', 'credit_lot_reserved', 'credit_lot_sold', 'credit_lot_retired', 'credit_lot_voided',
        -- Vente / modèle financier (9) — migration 01, déjà prévalidées pour 09 (§17 point 17).
        'credit_sale_created', 'credit_sale_cost_recorded', 'credit_sale_confirmed', 'credit_sale_cancelled',
        'credit_sale_settled', 'credit_sale_adjustment_recorded', 'credit_sale_allocation_recorded',
        'credit_sale_allocation_approved', 'credit_sale_allocation_paid',
        -- Opérateur/mandats (4) — migration 06 (31 -> 35).
        'platform_operator_designated', 'platform_operator_revoked',
        'carbon_commercialization_mandate_granted', 'carbon_commercialization_mandate_revoked',
        -- Émission, complément (2) — migration 07 (35 -> 37).
        'credit_issuance_marked_eligible', 'credit_issuance_externally_rejected',
        -- Lots, complément (1) — migration 08 (37 -> 38).
        'credit_lot_underlying_issuance_cancelled'
    ];
    v_canonical_48     TEXT[];
    v_sorted_literals  TEXT[];
    v_sorted_38        TEXT[];
    v_sorted_48        TEXT[];
    v_new_def          TEXT;
    v_new_body         TEXT;
    v_check_def        TEXT;
BEGIN
    IF array_length(v_canonical_38, 1) <> 38 THEN
        RAISE EXCEPTION 'Erreur interne de la migration : le tableau canonique codé en dur ne contient pas exactement 38 valeurs (%) — vérifier le corps de cette migration.', array_length(v_canonical_38, 1);
    END IF;
    -- 10 nouvelles valeurs de cette migration (§17 point 8/17) : le retrait
    -- interne d'un lot avant confirmation ('credit_sale_lot_released'),
    -- le retrait forcé par le cascade d'annulation externe de 08
    -- ('credit_sale_lot_released_by_external_cancellation'), et les 8
    -- événements de gouvernance à approbation multiple (points 4/5,
    -- identifiés comme une lacune à la revue finale de cohérence).
    v_canonical_48 := v_canonical_38 || ARRAY[
        'credit_sale_lot_released',
        'credit_sale_lot_released_by_external_cancellation',
        'distribution_rule_proposed', 'distribution_rule_activated',
        'distribution_rule_rejected', 'distribution_rule_withdrawn',
        'member_distribution_override_proposed', 'member_distribution_override_activated',
        'member_distribution_override_rejected', 'member_distribution_override_withdrawn'
    ];
    IF array_length(v_canonical_48, 1) <> 48 THEN
        RAISE EXCEPTION 'Erreur interne de la migration : le tableau canonique étendu ne contient pas exactement 48 valeurs (%).', array_length(v_canonical_48, 1);
    END IF;

    SELECT c.conname, pg_get_constraintdef(c.oid) INTO v_constraint_name, v_old_def
    FROM pg_constraint c
    WHERE c.conrelid = 'public.carbon_business_events'::regclass AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%event_type%';
    IF v_constraint_name IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : contrainte CHECK sur carbon_business_events.event_type introuvable.';
    END IF;

    SELECT array_agg(m[1]) INTO v_literals FROM regexp_matches(v_old_def, '''((?:[^'']|'''''')*)''', 'g') AS m;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_literals FROM unnest(v_literals) x;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_38 FROM unnest(v_canonical_38) x;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_48 FROM unnest(v_canonical_48) x;

    IF v_sorted_literals = v_sorted_48 THEN
        RAISE NOTICE 'Catalogue event_type déjà à jour : composition IDENTIQUE à l''ensemble canonique des 48 valeurs attendues — aucune modification.';
    ELSIF v_sorted_literals = v_sorted_38 THEN
        SELECT string_agg(quote_literal(lit) || '::text', ', ') INTO v_new_body FROM unnest(v_canonical_48) AS lit;
        v_new_def := format('CHECK (event_type = ANY (ARRAY[%s]))', v_new_body);
        EXECUTE format('ALTER TABLE public.carbon_business_events DROP CONSTRAINT %I', v_constraint_name);
        EXECUTE format('ALTER TABLE public.carbon_business_events ADD CONSTRAINT %I %s', v_constraint_name, v_new_def);

        SELECT pg_get_constraintdef(c.oid) INTO v_check_def FROM pg_constraint c
        WHERE c.conname = v_constraint_name AND c.conrelid = 'public.carbon_business_events'::regclass;
        SELECT array_agg(m[1]) INTO v_literals FROM regexp_matches(v_check_def, '''((?:[^'']|'''''')*)''', 'g') AS m;
        SELECT array_agg(x ORDER BY x) INTO v_sorted_literals FROM unnest(v_literals) x;
        IF v_sorted_literals IS DISTINCT FROM v_sorted_48 THEN
            RAISE EXCEPTION 'Post-vérification échouée : la contrainte % reconstruite (event_type) ne correspond pas EXACTEMENT à l''ensemble canonique des 48 valeurs attendues.', v_constraint_name;
        END IF;
        RAISE NOTICE 'Contrainte % (event_type) reconstruite explicitement (38→48), composition vérifiée EXACTEMENT.', v_constraint_name;
    ELSE
        RAISE EXCEPTION 'Prévalidation échouée : le catalogue event_type ne correspond EXACTEMENT ni à l''ensemble canonique des 38 valeurs attendues, ni à celui des 48 — composition actuelle différente de l''hypothèse documentée. Littéraux actuels : %', v_literals;
    END IF;
END $$;

DO $$
DECLARE
    v_constraint_name  TEXT;
    v_old_def          TEXT;
    v_literals         TEXT[];
    v_canonical_14     TEXT[] := ARRAY[
        'aggregator', 'aggregator_membership', 'aggregator_admin', 'ccf_mrv_project_link',
        'verification_session', 'verification_outcome', 'credit_issuance', 'credit_lot',
        'credit_sale', 'credit_sale_cost', 'credit_sale_adjustment', 'credit_sale_allocation',
        'platform_operator', 'carbon_commercialization_mandate'
    ];
    v_canonical_19     TEXT[];
    v_sorted_literals  TEXT[];
    v_sorted_14        TEXT[];
    v_sorted_19        TEXT[];
    v_new_def          TEXT;
    v_new_body         TEXT;
    v_check_def        TEXT;
BEGIN
    IF array_length(v_canonical_14, 1) <> 14 THEN
        RAISE EXCEPTION 'Erreur interne de la migration : le tableau canonique object_type codé en dur ne contient pas exactement 14 valeurs (%).', array_length(v_canonical_14, 1);
    END IF;
    -- 5 nouvelles valeurs (cette migration) : credit_sale_lot (libération
    -- interne/externe, point 8), et les 4 objets de gouvernance à
    -- approbation multiple (points 4/5).
    v_canonical_19 := v_canonical_14 || ARRAY[
        'credit_sale_lot', 'distribution_rule', 'distribution_rule_proposal',
        'member_distribution_override', 'member_distribution_override_proposal'
    ];
    IF array_length(v_canonical_19, 1) <> 19 THEN
        RAISE EXCEPTION 'Erreur interne de la migration : le tableau canonique object_type étendu ne contient pas exactement 19 valeurs (%).', array_length(v_canonical_19, 1);
    END IF;

    SELECT c.conname, pg_get_constraintdef(c.oid) INTO v_constraint_name, v_old_def
    FROM pg_constraint c
    WHERE c.conrelid = 'public.carbon_business_events'::regclass AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%object_type%';
    IF v_constraint_name IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : contrainte CHECK sur carbon_business_events.object_type introuvable.';
    END IF;

    SELECT array_agg(m[1]) INTO v_literals FROM regexp_matches(v_old_def, '''((?:[^'']|'''''')*)''', 'g') AS m;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_literals FROM unnest(v_literals) x;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_14 FROM unnest(v_canonical_14) x;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_19 FROM unnest(v_canonical_19) x;

    IF v_sorted_literals = v_sorted_19 THEN
        RAISE NOTICE 'Catalogue object_type déjà à jour : composition IDENTIQUE à l''ensemble canonique des 19 valeurs attendues — aucune modification.';
    ELSIF v_sorted_literals = v_sorted_14 THEN
        SELECT string_agg(quote_literal(lit) || '::text', ', ') INTO v_new_body FROM unnest(v_canonical_19) AS lit;
        v_new_def := format('CHECK (object_type = ANY (ARRAY[%s]))', v_new_body);
        EXECUTE format('ALTER TABLE public.carbon_business_events DROP CONSTRAINT %I', v_constraint_name);
        EXECUTE format('ALTER TABLE public.carbon_business_events ADD CONSTRAINT %I %s', v_constraint_name, v_new_def);

        SELECT pg_get_constraintdef(c.oid) INTO v_check_def FROM pg_constraint c
        WHERE c.conname = v_constraint_name AND c.conrelid = 'public.carbon_business_events'::regclass;
        SELECT array_agg(m[1]) INTO v_literals FROM regexp_matches(v_check_def, '''((?:[^'']|'''''')*)''', 'g') AS m;
        SELECT array_agg(x ORDER BY x) INTO v_sorted_literals FROM unnest(v_literals) x;
        IF v_sorted_literals IS DISTINCT FROM v_sorted_19 THEN
            RAISE EXCEPTION 'Post-vérification échouée : la contrainte % reconstruite (object_type) ne correspond pas EXACTEMENT à l''ensemble canonique des 19 valeurs attendues.', v_constraint_name;
        END IF;
        RAISE NOTICE 'Contrainte % (object_type) reconstruite explicitement (14→19), composition vérifiée EXACTEMENT.', v_constraint_name;
    ELSE
        RAISE EXCEPTION 'Prévalidation échouée : le catalogue object_type ne correspond EXACTEMENT ni à l''ensemble canonique des 14 valeurs attendues, ni à celui des 19 — composition actuelle différente de l''hypothèse documentée. Littéraux actuels : %', v_literals;
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. TABLE credit_sales (§17 point 1)
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.credit_sales (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_organization_id    UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    status                    TEXT NOT NULL DEFAULT 'draft'
                                CHECK (status IN ('draft','confirmed','settled','cancelled')),
    currency                  TEXT NOT NULL CHECK (currency = 'CAD'),
    price_per_tco2e           NUMERIC(14,4) NOT NULL
                                CHECK (price_per_tco2e > 0 AND price_per_tco2e <> 'NaN'::numeric),
    total_tco2e               NUMERIC(14,4) NOT NULL DEFAULT 0
                                CHECK (total_tco2e >= 0 AND total_tco2e <> 'NaN'::numeric),
    gross_amount              NUMERIC(14,2) NULL
                                CHECK (gross_amount IS NULL OR (gross_amount >= 0 AND gross_amount <> 'NaN'::numeric)),
    net_distributable_amount  NUMERIC(14,2) NULL
                                -- Durcissement économique après la deuxième revue statique (point 10) :
                                -- >= 0 imposé structurellement, en plus du rejet explicite dans
                                -- confirm_credit_sale() si SUM(costs) > gross_amount (défense en profondeur).
                                CHECK (net_distributable_amount IS NULL OR (net_distributable_amount >= 0 AND net_distributable_amount <> 'NaN'::numeric)),
    buyer_reference           TEXT NULL,
    sale_date                 DATE NOT NULL DEFAULT CURRENT_DATE,
    confirmed_at              TIMESTAMPTZ NULL,
    confirmed_by              UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    settled_at                TIMESTAMPTZ NULL,
    settled_by                UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    settlement_reference      TEXT NULL,
    cancelled_at              TIMESTAMPTZ NULL,
    cancelled_by              UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    cancel_reason             TEXT NULL,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    created_by                UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,

    -- Cohérence structurelle de la machine à états (§17 point 7) — défense
    -- en profondeur, en plus du trigger BEFORE UPDATE ci-dessous.
    -- Corrigé à la DOUZIÈME revue statique (bloqueur critique 1) : l'ancienne forme biconditionnelle
    -- ((status IN (...)) = (champ IS NOT NULL AND ...)) souffrait exactement du même défaut logique que
    -- les anciens CHECK de rejet des propositions (déjà corrigés à la NEUVIÈME revue) — un statut='draft'
    -- avec UNIQUEMENT confirmed_at renseigné (confirmed_by/gross/net restant NULL) validait
    -- FALSE = FALSE et était donc accepté. La forme ci-dessous impose explicitement, dans les DEUX sens,
    -- que TOUS les champs concernés soient renseignés ensemble ou tous NULL ensemble — aucun dépôt
    -- partiel toléré, dans aucun statut.
    CONSTRAINT credit_sales_confirmed_fields_check CHECK (
        (
            status IN ('confirmed','settled')
            AND confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL
            AND gross_amount IS NOT NULL AND net_distributable_amount IS NOT NULL
        )
        OR
        (
            status NOT IN ('confirmed','settled')
            AND confirmed_at IS NULL AND confirmed_by IS NULL
            AND gross_amount IS NULL AND net_distributable_amount IS NULL
        )
    ),
    CONSTRAINT credit_sales_settled_fields_check CHECK (
        (
            status = 'settled'
            AND settled_at IS NOT NULL AND settled_by IS NOT NULL
            AND settlement_reference IS NOT NULL AND btrim(settlement_reference) <> ''
        )
        OR
        (
            status <> 'settled'
            AND settled_at IS NULL AND settled_by IS NULL AND settlement_reference IS NULL
        )
    ),
    CONSTRAINT credit_sales_cancelled_fields_check CHECK (
        (
            status = 'cancelled'
            AND cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL
            AND cancel_reason IS NOT NULL AND btrim(cancel_reason) <> ''
        )
        OR
        (
            status <> 'cancelled'
            AND cancelled_at IS NULL AND cancelled_by IS NULL AND cancel_reason IS NULL
        )
    ),
    -- Les deux CHECK *_not_blank ci-dessous sont désormais redondants avec les btrim() intégrés
    -- ci-dessus (défense en profondeur historique, conservés tels quels sans affaiblir la forme
    -- all-or-none — jamais l'inverse).
    CONSTRAINT credit_sales_cancel_reason_not_blank CHECK (cancel_reason IS NULL OR btrim(cancel_reason) <> ''),
    CONSTRAINT credit_sales_settlement_reference_not_blank CHECK (settlement_reference IS NULL OR btrim(settlement_reference) <> '')
);

COMMENT ON TABLE public.credit_sales IS
  'Vente de crédits carbone consolidée — vendeur METALTRACE figé (§17 point 10). '
  'Machine à états draft/confirmed/settled/cancelled (§17 point 7), gross_amount/'
  'net_distributable_amount figés une seule fois par confirm_credit_sale(), jamais recalculés.';

-- BEFORE INSERT : force created_by/created_at (DB-owned), valide le
-- vendeur figé (§17 point 10 — is_platform_operator()).
CREATE OR REPLACE FUNCTION public.carbon_guard_credit_sale_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    IF NOT COALESCE(public.is_platform_operator(NEW.seller_organization_id), false) THEN
        RAISE EXCEPTION 'seller_organization_id (%) n''est pas l''opérateur METALTRACE actuellement actif.', NEW.seller_organization_id;
    END IF;

    NEW.status := 'draft';
    NEW.total_tco2e := 0;
    NEW.gross_amount := NULL;
    NEW.net_distributable_amount := NULL;
    NEW.confirmed_at := NULL; NEW.confirmed_by := NULL;
    NEW.settled_at := NULL; NEW.settled_by := NULL; NEW.settlement_reference := NULL;
    NEW.cancelled_at := NULL; NEW.cancelled_by := NULL; NEW.cancel_reason := NULL;
    NEW.created_by := v_actor;
    NEW.created_at := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_credit_sale_insert
    BEFORE INSERT ON public.credit_sales
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_credit_sale_insert();

-- BEFORE UPDATE : machine à états stricte (§17 point 7) + vendeur figé
-- révalidé tant que draft (§17 point 1) + total_tco2e DB-owned (point 1).
CREATE OR REPLACE FUNCTION public.carbon_credit_sales_before_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    -- Champs strictement immuables en toutes circonstances.
    IF NEW.id <> OLD.id OR NEW.currency <> OLD.currency OR NEW.price_per_tco2e <> OLD.price_per_tco2e
       OR NEW.sale_date <> OLD.sale_date OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at
       OR NEW.buyer_reference IS DISTINCT FROM OLD.buyer_reference THEN
        RAISE EXCEPTION 'Modification refusée : id/currency/price_per_tco2e/sale_date/buyer_reference/created_by/created_at sont immuables après création.';
    END IF;

    -- Ajouté à la DOUZIÈME revue statique (bloqueur critique 1) : confirmed_at, une fois posé, est
    -- IMMUABLE À VIE — ancre temporelle du rule_snapshot/distribution_rule_id déjà calculé par
    -- confirm_credit_sale(). Cette garde s'applique AVANT tout branchement sur NEW.status = OLD.status ou
    -- sur une transition, fermant le bypass qui laissait auparavant passer un UPDATE modifiant
    -- confirmed_at/confirmed_by (ou injectant settled_at/cancelled_at seul) tant que le CHECK biconditionnel
    -- ne le détectait pas explicitement. Seule la transition légitime draft->confirmed (ci-dessous) est
    -- autorisée à faire passer ces colonnes de NULL à une valeur ; toute autre modification est rejetée ici.
    IF OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at THEN
        RAISE EXCEPTION 'Modification refusée : confirmed_at est immuable à vie une fois posé (ancre temporelle du rule_snapshot déjà calculé).';
    END IF;
    IF OLD.confirmed_by IS NOT NULL AND NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by THEN
        RAISE EXCEPTION 'Modification refusée : confirmed_by est immuable à vie une fois posé.';
    END IF;
    IF OLD.settled_at IS NOT NULL AND NEW.settled_at IS DISTINCT FROM OLD.settled_at THEN
        RAISE EXCEPTION 'Modification refusée : settled_at est immuable à vie une fois posé.';
    END IF;
    IF OLD.settled_by IS NOT NULL AND NEW.settled_by IS DISTINCT FROM OLD.settled_by THEN
        RAISE EXCEPTION 'Modification refusée : settled_by est immuable à vie une fois posé.';
    END IF;
    IF OLD.settlement_reference IS NOT NULL AND NEW.settlement_reference IS DISTINCT FROM OLD.settlement_reference THEN
        RAISE EXCEPTION 'Modification refusée : settlement_reference est immuable à vie une fois posé.';
    END IF;
    IF OLD.cancelled_at IS NOT NULL AND NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at THEN
        RAISE EXCEPTION 'Modification refusée : cancelled_at est immuable à vie une fois posé.';
    END IF;
    IF OLD.cancelled_by IS NOT NULL AND NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by THEN
        RAISE EXCEPTION 'Modification refusée : cancelled_by est immuable à vie une fois posé.';
    END IF;
    IF OLD.cancel_reason IS NOT NULL AND NEW.cancel_reason IS DISTINCT FROM OLD.cancel_reason THEN
        RAISE EXCEPTION 'Modification refusée : cancel_reason est immuable à vie une fois posé.';
    END IF;

    IF NEW.status = OLD.status THEN
        -- Pas de transition : seul total_tco2e (DB-owned, maintenu par le
        -- trigger sur credit_sale_lots) peut changer, et uniquement tant
        -- que draft. Vendeur révalidé à chaque UPDATE tant que draft (point 1).
        -- Ajouté à la DOUZIÈME revue statique : quand OLD.confirmed_at/settled_at/cancelled_at/etc.
        -- étaient encore NULL (bypass historique), les gardes d'immutabilité ci-dessus ne s'appliquaient
        -- pas (OLD IS NOT NULL = false) — cette branche ferme explicitement ce cas : hors transition
        -- légitime (traitée plus bas), aucune de ces colonnes ne peut passer de NULL à une valeur.
        IF NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at OR NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by THEN
            RAISE EXCEPTION 'Modification refusée : confirmed_at/confirmed_by ne peuvent être posés que par la transition draft->confirmed.';
        END IF;
        IF NEW.settled_at IS DISTINCT FROM OLD.settled_at OR NEW.settled_by IS DISTINCT FROM OLD.settled_by
           OR NEW.settlement_reference IS DISTINCT FROM OLD.settlement_reference THEN
            RAISE EXCEPTION 'Modification refusée : settled_at/settled_by/settlement_reference ne peuvent être posés que par la transition confirmed->settled.';
        END IF;
        IF NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
           OR NEW.cancel_reason IS DISTINCT FROM OLD.cancel_reason THEN
            RAISE EXCEPTION 'Modification refusée : cancelled_at/cancelled_by/cancel_reason ne peuvent être posés que par la transition draft->cancelled.';
        END IF;
        IF OLD.status <> 'draft' AND NEW.total_tco2e <> OLD.total_tco2e THEN
            RAISE EXCEPTION 'Modification refusée : total_tco2e est figé une fois la vente sortie de draft.';
        END IF;
        IF NEW.seller_organization_id <> OLD.seller_organization_id THEN
            IF OLD.status <> 'draft' THEN
                RAISE EXCEPTION 'Modification refusée : seller_organization_id est figé une fois la vente sortie de draft.';
            END IF;
            IF NOT COALESCE(public.is_platform_operator(NEW.seller_organization_id), false) THEN
                RAISE EXCEPTION 'seller_organization_id (%) n''est pas l''opérateur METALTRACE actuellement actif.', NEW.seller_organization_id;
            END IF;
        END IF;
        IF NEW.gross_amount IS DISTINCT FROM OLD.gross_amount
           OR NEW.net_distributable_amount IS DISTINCT FROM OLD.net_distributable_amount THEN
            RAISE EXCEPTION 'Modification refusée : gross_amount/net_distributable_amount ne se modifient que par une transition de statut valide.';
        END IF;
        RETURN NEW;
    END IF;

    -- Transitions valides (§17 point 7) : draft->confirmed, draft->cancelled, confirmed->settled.
    IF OLD.status = 'draft' AND NEW.status = 'confirmed' THEN
        IF NEW.confirmed_at IS NULL OR NEW.confirmed_by IS NULL
           OR NEW.gross_amount IS NULL OR NEW.net_distributable_amount IS NULL THEN
            RAISE EXCEPTION 'Transition draft->confirmed refusée : confirmed_at/confirmed_by/gross_amount/net_distributable_amount doivent tous être renseignés.';
        END IF;
        -- Ajouté à la DOUZIÈME revue statique : les anciennes valeurs doivent être NULL (cette
        -- transition ne peut être empruntée qu'une seule fois par ligne, jamais pour "re-confirmer").
        IF OLD.confirmed_at IS NOT NULL OR OLD.confirmed_by IS NOT NULL
           OR OLD.gross_amount IS NOT NULL OR OLD.net_distributable_amount IS NOT NULL THEN
            RAISE EXCEPTION 'Transition draft->confirmed refusée : confirmed_at/confirmed_by/gross_amount/net_distributable_amount doivent tous être NULL avant cette transition.';
        END IF;
        IF NEW.total_tco2e <> OLD.total_tco2e OR NEW.seller_organization_id <> OLD.seller_organization_id THEN
            RAISE EXCEPTION 'Transition draft->confirmed refusée : total_tco2e/seller_organization_id ne doivent pas changer à cette transition.';
        END IF;
        IF NEW.settled_at IS NOT NULL OR NEW.settled_by IS NOT NULL OR NEW.settlement_reference IS NOT NULL
           OR NEW.cancelled_at IS NOT NULL OR NEW.cancelled_by IS NOT NULL OR NEW.cancel_reason IS NOT NULL THEN
            RAISE EXCEPTION 'Transition draft->confirmed refusée : aucune donnée settled/cancelled ne doit être présente.';
        END IF;
    ELSIF OLD.status = 'draft' AND NEW.status = 'cancelled' THEN
        IF NEW.cancelled_at IS NULL OR NEW.cancelled_by IS NULL OR NEW.cancel_reason IS NULL OR btrim(NEW.cancel_reason) = '' THEN
            RAISE EXCEPTION 'Transition draft->cancelled refusée : cancelled_at/cancelled_by/cancel_reason (non vide) doivent être renseignés.';
        END IF;
        IF NEW.gross_amount IS NOT NULL OR NEW.net_distributable_amount IS NOT NULL
           OR NEW.confirmed_at IS NOT NULL OR NEW.confirmed_by IS NOT NULL
           OR NEW.settled_at IS NOT NULL OR NEW.settled_by IS NOT NULL OR NEW.settlement_reference IS NOT NULL THEN
            RAISE EXCEPTION 'Transition draft->cancelled refusée : une vente jamais confirmée ne peut porter gross_amount/net_distributable_amount/confirmed_at/confirmed_by/settled_at/settled_by/settlement_reference.';
        END IF;
        -- Ajouté à la TREIZIÈME revue statique : bypass réel identifié — cette branche ne vérifiait pas
        -- que total_tco2e/seller_organization_id restent identiques à OLD, permettant un UPDATE
        -- privilégié combinant status='cancelled' avec un changement simultané de quantité et/ou de
        -- vendeur figé. total_tco2e et seller_organization_id ne peuvent changer QUE tant que draft
        -- (déjà le cas ici puisque OLD.status = 'draft'), mais cette transition elle-même ne doit jamais
        -- laisser passer un changement concomitant à l'annulation.
        IF NEW.total_tco2e <> OLD.total_tco2e OR NEW.seller_organization_id <> OLD.seller_organization_id THEN
            RAISE EXCEPTION 'Transition draft->cancelled refusée : total_tco2e/seller_organization_id ne doivent pas changer à cette transition.';
        END IF;
    ELSIF OLD.status = 'confirmed' AND NEW.status = 'settled' THEN
        IF NEW.settled_at IS NULL OR NEW.settled_by IS NULL OR NEW.settlement_reference IS NULL OR btrim(NEW.settlement_reference) = '' THEN
            RAISE EXCEPTION 'Transition confirmed->settled refusée : settled_at/settled_by/settlement_reference (non vide) doivent être renseignés.';
        END IF;
        -- Ajouté à la DOUZIÈME revue statique : confirmed_at/confirmed_by doivent rester STRICTEMENT
        -- identiques à OLD à cette transition (déjà couvert par la garde d'immutabilité générale
        -- ci-dessus, revérifié explicitement ici pour un message d'erreur spécifique à la transition) ;
        -- aucune donnée cancelled ne doit apparaître (une vente confirmed ne peut jamais devenir
        -- cancelled — seul draft->cancelled existe, §17 point 7).
        IF NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at OR NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by THEN
            RAISE EXCEPTION 'Transition confirmed->settled refusée : confirmed_at/confirmed_by doivent rester strictement identiques à leur valeur déjà figée.';
        END IF;
        IF NEW.cancelled_at IS NOT NULL OR NEW.cancelled_by IS NOT NULL OR NEW.cancel_reason IS NOT NULL THEN
            RAISE EXCEPTION 'Transition confirmed->settled refusée : aucune donnée cancelled ne doit être présente.';
        END IF;
        IF NEW.total_tco2e <> OLD.total_tco2e OR NEW.gross_amount IS DISTINCT FROM OLD.gross_amount
           OR NEW.net_distributable_amount IS DISTINCT FROM OLD.net_distributable_amount THEN
            RAISE EXCEPTION 'Transition confirmed->settled refusée : total_tco2e/gross_amount/net_distributable_amount ne doivent pas changer.';
        END IF;
        -- Ajouté à la TREIZIÈME revue statique : bypass réel identifié — seller_organization_id n'était
        -- pas revérifié à cette transition (contrairement à total_tco2e/gross_amount/net_distributable_
        -- amount juste au-dessus). Un UPDATE privilégié pouvait donc changer le vendeur figé au moment
        -- même du règlement, ce qui est incompatible avec l'invariant central de 09 (seller_organization_id
        -- figé dès la confirmation, §17 point 10).
        IF NEW.seller_organization_id <> OLD.seller_organization_id THEN
            RAISE EXCEPTION 'Transition confirmed->settled refusée : seller_organization_id est figé depuis la confirmation et ne doit jamais changer.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Transition de statut refusée : % -> % n''est pas une transition valide (§17 point 7).', OLD.status, NEW.status;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_credit_sales_before_update
    BEFORE UPDATE ON public.credit_sales
    FOR EACH ROW EXECUTE FUNCTION public.carbon_credit_sales_before_update();

CREATE TRIGGER trg_carbon_credit_sales_forbid_delete
    BEFORE DELETE ON public.credit_sales
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

CREATE INDEX idx_credit_sales_seller ON public.credit_sales(seller_organization_id);
CREATE INDEX idx_credit_sales_status ON public.credit_sales(status);

-- ────────────────────────────────────────────────────────────
-- 2. TABLE credit_sale_lots (§17 point 2)
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.credit_sale_lots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_sale_id  UUID NOT NULL REFERENCES public.credit_sales(id) ON DELETE RESTRICT,
    credit_lot_id   UUID NOT NULL REFERENCES public.credit_lots(id) ON DELETE RESTRICT,
    quantity_tco2e  NUMERIC(14,4) NOT NULL CHECK (quantity_tco2e > 0 AND quantity_tco2e <> 'NaN'::numeric),
    released_at     TIMESTAMPTZ NULL,
    released_by     UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    release_reason  TEXT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    created_by      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,

    -- Corrigé après la première revue statique (point 2) puis à nouveau après la deuxième (point 5) :
    -- released_by est TOUJOURS requis dès que released_at est renseigné, y compris pour le cas système
    -- 'external_cancellation_cascade' — carbon_release_credit_sale_lot_on_external_void() propage
    -- désormais l'acteur réel (auth.uid(), depuis record_external_cancellation()) au lieu de poser
    -- released_by=NULL ; l'ancienne tolérance NULL pour ce seul cas est retirée. release_reason =
    -- 'external_cancellation_cascade' reste réservée par convention de code à ce cascade (jamais un RPC
    -- applicatif ne l'utilise), mais ne se distingue plus des autres libérations sur released_by.
    CONSTRAINT credit_sale_lots_released_fields_check CHECK (
        (released_at IS NULL AND released_by IS NULL AND release_reason IS NULL)
        OR (released_at IS NOT NULL AND released_by IS NOT NULL AND release_reason IS NOT NULL AND btrim(release_reason) <> '')
    )
);

CREATE UNIQUE INDEX idx_credit_sale_lots_active_lot ON public.credit_sale_lots(credit_lot_id) WHERE released_at IS NULL;
CREATE INDEX idx_credit_sale_lots_sale ON public.credit_sale_lots(credit_sale_id);

COMMENT ON TABLE public.credit_sale_lots IS
  'Rattachement indivisible d''un credit_lot à une vente (§17 point 2) — quantity_tco2e '
  'DB-owned (= quantité intégrale du lot référencé), jamais de réservation partielle. '
  'UNIQUE (credit_lot_id) WHERE released_at IS NULL : un lot n''est actif que dans une seule vente à la fois.';

-- BEFORE INSERT : force quantity_tco2e/created_by/created_at (DB-owned),
-- valide available/issued/seller-match/draft-status (§17 point 2 verbatim).
CREATE OR REPLACE FUNCTION public.carbon_guard_credit_sale_lot_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor              UUID;
    v_lot_status         TEXT;
    v_lot_quantity       NUMERIC(14,4);
    v_issuance_id        UUID;
    v_issuance_status    TEXT;
    v_sale_status        TEXT;
    v_seller_org         UUID;
    v_mismatched_sources INT;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    SELECT commercial_status, quantity_tco2e, credit_issuance_id
    INTO v_lot_status, v_lot_quantity, v_issuance_id
    FROM public.credit_lots WHERE id = NEW.credit_lot_id;

    IF v_lot_status IS NULL THEN
        RAISE EXCEPTION 'credit_lot_id (%) introuvable.', NEW.credit_lot_id;
    END IF;
    IF v_lot_status <> 'available' THEN
        RAISE EXCEPTION 'Ajout refusé : le lot % n''est pas available (statut réel : %).', NEW.credit_lot_id, v_lot_status;
    END IF;

    SELECT issuance_status INTO v_issuance_status FROM public.credit_issuances WHERE id = v_issuance_id;
    IF v_issuance_status <> 'issued' THEN
        RAISE EXCEPTION 'Ajout refusé : l''émission parente du lot % n''est pas issued (statut réel : %) — défense en profondeur.', NEW.credit_lot_id, v_issuance_status;
    END IF;

    SELECT status, seller_organization_id INTO v_sale_status, v_seller_org
    FROM public.credit_sales WHERE id = NEW.credit_sale_id;
    IF v_sale_status IS NULL THEN
        RAISE EXCEPTION 'credit_sale_id (%) introuvable.', NEW.credit_sale_id;
    END IF;
    IF v_sale_status <> 'draft' THEN
        RAISE EXCEPTION 'Ajout refusé : la vente % n''est pas draft (statut réel : %).', NEW.credit_sale_id, v_sale_status;
    END IF;

    -- Invariant du vendeur figé (§13 point 9, réaffirmé §17 point 2) :
    -- l'opérateur du mandat de CHAQUE source de l'émission parente doit
    -- correspondre au vendeur de la vente.
    SELECT count(*) INTO v_mismatched_sources
    FROM public.credit_issuance_sources cis
    JOIN public.carbon_commercialization_mandates m ON m.id = cis.commercialization_mandate_id
    WHERE cis.credit_issuance_id = v_issuance_id AND m.operator_organization_id <> v_seller_org;
    IF v_mismatched_sources > 0 THEN
        RAISE EXCEPTION 'Ajout refusé : au moins une source de l''émission parente du lot % a un opérateur de mandat différent du vendeur figé de la vente.', NEW.credit_lot_id;
    END IF;

    NEW.quantity_tco2e := v_lot_quantity;
    NEW.released_at := NULL; NEW.released_by := NULL; NEW.release_reason := NULL;
    NEW.created_by := v_actor;
    NEW.created_at := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_credit_sale_lot_insert
    BEFORE INSERT ON public.credit_sale_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_credit_sale_lot_insert();

-- BEFORE UPDATE : seule transition permise = libération (released_at
-- NULL -> valeur, une seule fois), tout le reste immuable.
CREATE OR REPLACE FUNCTION public.carbon_credit_sale_lots_before_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.credit_sale_id <> OLD.credit_sale_id OR NEW.credit_lot_id <> OLD.credit_lot_id
       OR NEW.quantity_tco2e <> OLD.quantity_tco2e OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'Modification refusée : credit_sale_id/credit_lot_id/quantity_tco2e/created_by/created_at sont immuables.';
    END IF;
    IF OLD.released_at IS NOT NULL THEN
        RAISE EXCEPTION 'Modification refusée : une ligne credit_sale_lots déjà libérée est immuable.';
    END IF;
    IF NEW.released_at IS NULL THEN
        RAISE EXCEPTION 'Modification refusée : aucune autre modification que la libération n''est permise sur credit_sale_lots.';
    END IF;
    IF NEW.release_reason IS NULL OR btrim(NEW.release_reason) = '' THEN
        RAISE EXCEPTION 'Libération refusée : release_reason (non vide) doit être renseigné.';
    END IF;
    -- AJOUTÉ après la troisième revue statique (point 3) : release_reason='external_cancellation_cascade'
    -- est réservé par convention au cascade système (carbon_release_credit_sale_lot_on_external_void()),
    -- mais rien n'empêchait structurellement un appel direct (UPDATE privilégié, ou même
    -- release_credit_sale_lot() si p_reason était laissé libre) de poser cette valeur sur un lot
    -- simplement 'reserved' — le trigger de synchronisation structurelle
    -- (trg_carbon_sync_credit_lot_status_on_sale_lot_release, point 2) traite spécialement cette
    -- chaîne (ne remet JAMAIS le lot 'available'), ce qui aurait figé à tort une réservation légitime
    -- en libération « système » sans que le lot n'ait jamais été réellement annulé. Vérifié ici, au
    -- moment même de la libération : cette valeur n'est acceptée QUE si le lot référencé est déjà
    -- 'voided' avec void_cause='external_cancellation' (c'est-à-dire déjà traité par le cascade de 08
    -- AVANT que ce trigger ne s'exécute — ordre garanti par la chaîne de verrous du point 3/§16).
    IF NEW.release_reason = 'external_cancellation_cascade' THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.credit_lots
            WHERE id = NEW.credit_lot_id AND commercial_status = 'voided' AND void_cause = 'external_cancellation'
        ) THEN
            RAISE EXCEPTION 'Libération refusée : release_reason=''external_cancellation_cascade'' n''est valide que si le lot référencé (%) est déjà voided avec void_cause=''external_cancellation''.', NEW.credit_lot_id;
        END IF;
    END IF;
    -- Corrigé après la première revue statique (point 2) puis retiré après la deuxième (point 5) :
    -- released_by est désormais TOUJOURS requis, y compris pour le cascade d'annulation externe, qui
    -- propage maintenant l'acteur réel au lieu de NULL (voir CHECK ci-dessus et
    -- carbon_release_credit_sale_lot_on_external_void()).
    IF NEW.released_by IS NULL THEN
        RAISE EXCEPTION 'Libération refusée : released_by requis.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_credit_sale_lots_before_update
    BEFORE UPDATE ON public.credit_sale_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_credit_sale_lots_before_update();

CREATE TRIGGER trg_carbon_credit_sale_lots_forbid_delete
    BEFORE DELETE ON public.credit_sale_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- AFTER INSERT/UPDATE : maintient credit_sales.total_tco2e = SOMME des lots
-- actifs (§17 point 1/8) — jamais saisi directement.
CREATE OR REPLACE FUNCTION public.carbon_sync_credit_sale_total_tco2e()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_sale_id UUID;
    v_total   NUMERIC(14,4);
BEGIN
    v_sale_id := COALESCE(NEW.credit_sale_id, OLD.credit_sale_id);
    SELECT COALESCE(SUM(quantity_tco2e), 0) INTO v_total
    FROM public.credit_sale_lots WHERE credit_sale_id = v_sale_id AND released_at IS NULL;
    UPDATE public.credit_sales SET total_tco2e = v_total WHERE id = v_sale_id;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_carbon_sync_credit_sale_total_tco2e
    AFTER INSERT OR UPDATE ON public.credit_sale_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_sync_credit_sale_total_tco2e();

-- AJOUTÉS après la deuxième revue statique (point 2) : credit_sale_lots devient l'unique PROPRIÉTAIRE
-- STRUCTUREL de la synchronisation vers credit_lots.commercial_status — auparavant, add_credit_sale_lot()/
-- release_credit_sale_lot()/cancel_credit_sale() posaient chacune un UPDATE credit_lots manuel après avoir
-- écrit credit_sale_lots, ce qui laissait un chemin d'écriture privilégié direct dans credit_sale_lots
-- (par exemple un INSERT superutilisateur contournant la RPC) capable de créer une ligne active SANS
-- jamais faire passer le lot à 'reserved' (invariant à sens unique, faille signalée en revue). Ces deux
-- triggers ferment cette faille : QUELLE QUE SOIT L'ORIGINE de l'écriture sur credit_sale_lots (RPC ou
-- accès direct), le lot référencé suit désormais automatiquement.
CREATE OR REPLACE FUNCTION public.carbon_sync_credit_lot_status_on_sale_lot_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.credit_lots SET commercial_status = 'reserved' WHERE id = NEW.credit_lot_id;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.carbon_sync_credit_lot_status_on_sale_lot_insert() IS
  'Point 2 (deuxième revue statique) : seul propriétaire structurel de la transition available -> reserved '
  '— déclenché par TOUT INSERT dans credit_sale_lots, RPC ou accès direct privilégié. Validé par le trigger '
  'de transition de 08 déjà en place (aucun second contrôle de validité nécessaire ici).';

CREATE TRIGGER trg_carbon_sync_credit_lot_status_on_sale_lot_insert
    AFTER INSERT ON public.credit_sale_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_sync_credit_lot_status_on_sale_lot_insert();

CREATE OR REPLACE FUNCTION public.carbon_sync_credit_lot_status_on_sale_lot_release()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.release_reason = 'external_cancellation_cascade' THEN
        -- Le lot est déjà 'voided' par le cascade de 08 (point 8) — ne JAMAIS le remettre 'available'
        -- ici, ce serait à la fois faux (le lot n'est plus disponible, l'émission parente a été annulée)
        -- et rejeté de toute façon par le trigger de transition de 08 (voided n'a pas de retour en arrière).
        RETURN NULL;
    END IF;
    UPDATE public.credit_lots SET commercial_status = 'available' WHERE id = NEW.credit_lot_id;
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.carbon_sync_credit_lot_status_on_sale_lot_release() IS
  'Point 2 (deuxième revue statique) : seul propriétaire structurel de la transition reserved -> available '
  'à la libération — déclenché par TOUT UPDATE de released_at dans credit_sale_lots, RPC ou accès direct '
  'privilégié. Exclusion explicite du cas release_reason=''external_cancellation_cascade'' (le lot est '
  'déjà voided par 08, jamais remis available).';

CREATE TRIGGER trg_carbon_sync_credit_lot_status_on_sale_lot_release
    AFTER UPDATE OF released_at ON public.credit_sale_lots
    FOR EACH ROW
    WHEN (OLD.released_at IS NULL AND NEW.released_at IS NOT NULL)
    EXECUTE FUNCTION public.carbon_sync_credit_lot_status_on_sale_lot_release();

-- ────────────────────────────────────────────────────────────
-- 3. TABLES credit_sale_costs et credit_sale_adjustments (§17 point 3)
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.credit_sale_costs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_sale_id  UUID NOT NULL REFERENCES public.credit_sales(id) ON DELETE RESTRICT,
    cost_type       TEXT NOT NULL CHECK (cost_type IN (
                        'platform_fee','registry_fee','verification_fee','brokerage',
                        'legal_fee','risk_reserve','administrative_fee','tax','other'
                    )),
    description     TEXT NULL,
    amount          NUMERIC(14,2) NOT NULL CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    currency        TEXT NOT NULL CHECK (currency = 'CAD'),
    beneficiary     TEXT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    created_by      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT
);

CREATE INDEX idx_credit_sale_costs_sale ON public.credit_sale_costs(credit_sale_id);

CREATE TABLE public.credit_sale_adjustments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_sale_id  UUID NOT NULL REFERENCES public.credit_sales(id) ON DELETE RESTRICT,
    amount          NUMERIC(14,2) NOT NULL CHECK (amount <> 0 AND amount <> 'NaN'::numeric),
    reason          TEXT NOT NULL CHECK (btrim(reason) <> ''),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    created_by      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT
);

CREATE INDEX idx_credit_sale_adjustments_sale ON public.credit_sale_adjustments(credit_sale_id);

COMMENT ON TABLE public.credit_sale_costs IS
  'Coûts déduits du montant brut — insérables uniquement tant que la vente parente est draft (§17 point 3). Append-only.';
COMMENT ON TABLE public.credit_sale_adjustments IS
  'Corrections post-confirmation, signées — insérables uniquement une fois la vente confirmed/settled (§17 point 3). Append-only.';

-- BEFORE INSERT credit_sale_costs : fenêtre draft uniquement, devise = celle
-- de la vente (§17 point 3/11), force created_by/created_at.
CREATE OR REPLACE FUNCTION public.carbon_guard_credit_sale_cost_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        UUID;
    v_sale_status  TEXT;
    v_sale_currency TEXT;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Ajouté à la TREIZIÈME revue statique (bloqueur réel) : FOR UPDATE sur la même ligne credit_sales
    -- que confirm_credit_sale() (même verrou parent), acquis AVANT tout contrôle de statut. Sans ce
    -- verrou, un INSERT direct dans credit_sale_costs pouvait lire status='draft' (lecture non verrouillée,
    -- STABLE) alors qu'une transaction confirm_credit_sale() concurrente était en train de figer
    -- gross_amount/net_distributable_amount à partir de la SOMME des coûts déjà présents — l'INSERT et la
    -- confirmation pouvaient alors s'entrelacer sans qu'aucune des deux ne voie l'état final réel de
    -- l'autre. Désormais, les deux opérations se sérialisent strictement sur la ligne credit_sales :
    -- quel que soit l'ordre d'arrivée, la seconde attend le COMMIT de la première puis relit un état
    -- cohérent (soit le coût est visible et inclus dans net_distributable_amount, soit la vente n'est
    -- plus draft et l'INSERT est rejeté — jamais un état intermédiaire silencieusement incohérent).
    SELECT status, currency INTO v_sale_status, v_sale_currency
    FROM public.credit_sales
    WHERE id = NEW.credit_sale_id
    FOR UPDATE;
    IF v_sale_status IS NULL THEN RAISE EXCEPTION 'credit_sale_id (%) introuvable.', NEW.credit_sale_id; END IF;
    IF v_sale_status <> 'draft' THEN
        RAISE EXCEPTION 'Ajout de coût refusé : la vente % n''est pas draft (statut réel : %).', NEW.credit_sale_id, v_sale_status;
    END IF;
    IF NEW.currency <> v_sale_currency THEN
        RAISE EXCEPTION 'Ajout de coût refusé : devise (%) différente de celle de la vente (%).', NEW.currency, v_sale_currency;
    END IF;

    NEW.created_by := v_actor;
    NEW.created_at := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_credit_sale_cost_insert
    BEFORE INSERT ON public.credit_sale_costs
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_credit_sale_cost_insert();

CREATE TRIGGER trg_carbon_credit_sale_costs_forbid_update
    BEFORE UPDATE ON public.credit_sale_costs
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();
CREATE TRIGGER trg_carbon_credit_sale_costs_forbid_delete
    BEFORE DELETE ON public.credit_sale_costs
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- BEFORE INSERT credit_sale_adjustments : fenêtre confirmed/settled
-- uniquement (§17 point 3), force created_by/created_at.
CREATE OR REPLACE FUNCTION public.carbon_guard_credit_sale_adjustment_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       UUID;
    v_sale_status TEXT;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    SELECT status INTO v_sale_status FROM public.credit_sales WHERE id = NEW.credit_sale_id;
    IF v_sale_status IS NULL THEN RAISE EXCEPTION 'credit_sale_id (%) introuvable.', NEW.credit_sale_id; END IF;
    IF v_sale_status NOT IN ('confirmed','settled') THEN
        RAISE EXCEPTION 'Ajout d''ajustement refusé : la vente % doit être confirmed ou settled (statut réel : %).', NEW.credit_sale_id, v_sale_status;
    END IF;

    NEW.created_by := v_actor;
    NEW.created_at := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_credit_sale_adjustment_insert
    BEFORE INSERT ON public.credit_sale_adjustments
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_credit_sale_adjustment_insert();

CREATE TRIGGER trg_carbon_credit_sale_adjustments_forbid_update
    BEFORE UPDATE ON public.credit_sale_adjustments
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();
CREATE TRIGGER trg_carbon_credit_sale_adjustments_forbid_delete
    BEFORE DELETE ON public.credit_sale_adjustments
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 4. TABLES distribution_rules et distribution_rule_proposals (§17 point 4)
--    Dépendance circulaire de FK résolue par construction : CREATE des deux
--    tables sans la contrainte croisée, ALTER différé en section 7.
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.distribution_rules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_id   UUID NOT NULL REFERENCES public.aggregators(id) ON DELETE RESTRICT,
    platform_fee_pct NUMERIC(5,2) NOT NULL CHECK (platform_fee_pct BETWEEN 0 AND 100 AND platform_fee_pct <> 'NaN'::numeric),
    reserve_pct     NUMERIC(5,2) NOT NULL CHECK (reserve_pct BETWEEN 0 AND 100 AND reserve_pct <> 'NaN'::numeric),
    default_weight  NUMERIC(8,4) NOT NULL DEFAULT 1.0 CHECK (default_weight > 0 AND default_weight <> 'NaN'::numeric),
    effective_from  TIMESTAMPTZ NOT NULL,
    effective_to    TIMESTAMPTZ NULL,
    proposal_id     UUID NOT NULL,   -- FK ajoutée en section 7 (dépendance circulaire)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    created_by      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,

    CONSTRAINT distribution_rules_period_check CHECK (effective_to IS NULL OR effective_to > effective_from),
    -- Durcissement économique ajouté après la deuxième revue statique (point 10) : une règle où
    -- fee+reserve dépasse 100 laisserait un net_distributable_amount négatif par construction pour
    -- TOUTE vente future de ce regroupement, jamais détecté avant confirm_credit_sale() sans ce CHECK.
    CONSTRAINT distribution_rules_fee_reserve_bounds_check CHECK (platform_fee_pct + reserve_pct <= 100),
    CONSTRAINT distribution_rules_no_overlap EXCLUDE USING gist (
        aggregator_id WITH =, tstzrange(effective_from, effective_to) WITH &&
    )
);

CREATE INDEX idx_distribution_rules_aggregator ON public.distribution_rules(aggregator_id);

COMMENT ON TABLE public.distribution_rules IS
  'Versionnement temporel immuable de la règle de répartition d''un regroupement (§17 point 4). '
  'Nouvelle version = nouvelle ligne ; l''ancienne est fermée (effective_to), jamais modifiée. '
  'La règle applicable à une vente est celle active à credit_sales.confirmed_at exactement.';

CREATE TABLE public.distribution_rule_proposals (
    id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_id                 UUID NOT NULL REFERENCES public.aggregators(id) ON DELETE RESTRICT,
    platform_fee_pct              NUMERIC(5,2) NOT NULL CHECK (platform_fee_pct BETWEEN 0 AND 100 AND platform_fee_pct <> 'NaN'::numeric),
    reserve_pct                   NUMERIC(5,2) NOT NULL CHECK (reserve_pct BETWEEN 0 AND 100 AND reserve_pct <> 'NaN'::numeric),
    default_weight                NUMERIC(8,4) NOT NULL DEFAULT 1.0 CHECK (default_weight > 0 AND default_weight <> 'NaN'::numeric),
    status                        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','activated','rejected','withdrawn')),
    proposed_by                   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    proposed_at                   TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    aggregator_admin_approved_by  UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    aggregator_admin_approved_at  TIMESTAMPTZ NULL,
    operator_admin_approved_by    UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    operator_admin_approved_at    TIMESTAMPTZ NULL,
    activated_distribution_rule_id UUID NULL REFERENCES public.distribution_rules(id) ON DELETE RESTRICT,
    rejected_by                   UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    rejected_at                   TIMESTAMPTZ NULL,
    reject_reason                 TEXT NULL,
    created_at                    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT distribution_rule_proposals_activated_check CHECK ((status = 'activated') = (activated_distribution_rule_id IS NOT NULL)),
    -- Corrigé après la NEUVIÈME revue statique (bloqueur 3) : l'ancienne forme biconditionnelle
    -- « (status = 'rejected') = (tous NOT NULL) » n'interdisait que la combinaison « status='rejected'
    -- ET pas tous renseignés » et « status<>'rejected' ET tous renseignés » — mais laissait passer un
    -- statut non-rejected avec des métadonnées de rejet PARTIELLEMENT renseignées (ex. status='pending',
    -- rejected_at=clock_timestamp(), rejected_by/reject_reason NULL : le membre droit de l'égalité
    -- valait déjà FALSE puisque tous les champs n'étaient pas renseignés, donc FALSE=FALSE validait la
    -- ligne). La forme ci-dessous impose désormais explicitement, dans la branche status<>'rejected',
    -- que LES TROIS champs soient NULL (aucun dépôt partiel toléré), all-or-none dans les deux sens.
    CONSTRAINT distribution_rule_proposals_rejected_check CHECK (
        (status = 'rejected' AND rejected_by IS NOT NULL AND rejected_at IS NOT NULL AND reject_reason IS NOT NULL AND btrim(reject_reason) <> '')
        OR
        (status <> 'rejected' AND rejected_by IS NULL AND rejected_at IS NULL AND reject_reason IS NULL)
    ),
    -- Durcissement économique ajouté après la deuxième revue statique (point 10) : même borne que
    -- distribution_rules_fee_reserve_bounds_check, appliquée dès la proposition (pas seulement à la
    -- règle activée) pour rejeter une proposition intenable avant même la double approbation.
    CONSTRAINT distribution_rule_proposals_fee_reserve_bounds_check CHECK (platform_fee_pct + reserve_pct <= 100),
    -- Ajoutés après la SIXIÈME revue statique (correction 2) : chaque couple approved_by/approved_at
    -- est indissociable (jamais l'un renseigné sans l'autre), et l'activation exige structurellement
    -- les DEUX approbations complètes — défense en profondeur contre un UPDATE privilégié direct qui
    -- contournerait les RPC d'approbation et produirait un état économiquement impossible (une règle
    -- « activated » sans double approbation réelle).
    CONSTRAINT distribution_rule_proposals_aggregator_admin_pair_check
        CHECK ((aggregator_admin_approved_by IS NULL) = (aggregator_admin_approved_at IS NULL)),
    CONSTRAINT distribution_rule_proposals_operator_admin_pair_check
        CHECK ((operator_admin_approved_by IS NULL) = (operator_admin_approved_at IS NULL)),
    CONSTRAINT distribution_rule_proposals_activated_requires_both_approvals_check
        CHECK (status <> 'activated' OR (aggregator_admin_approved_by IS NOT NULL AND operator_admin_approved_by IS NOT NULL))
);

CREATE INDEX idx_distribution_rule_proposals_aggregator ON public.distribution_rule_proposals(aggregator_id);
CREATE INDEX idx_distribution_rule_proposals_status ON public.distribution_rule_proposals(status);

COMMENT ON TABLE public.distribution_rule_proposals IS
  'Gouvernance à double approbation de distribution_rules (§17 point 4) : primary_admin du '
  'regroupement + admin opérateur METALTRACE (substitution super-admin limitée à ce second rôle). '
  'Pas de proposal_type/''revoke'' — un regroupement a toujours exactement une règle active (§17 point 4, asymétrie assumée avec member_distribution_overrides).';

-- BEFORE INSERT : force proposed_by/proposed_at, status='pending'.
CREATE OR REPLACE FUNCTION public.carbon_guard_distribution_rule_proposal_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_actor UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    NEW.status := 'pending';
    NEW.proposed_by := v_actor;
    NEW.proposed_at := clock_timestamp();
    NEW.aggregator_admin_approved_by := NULL; NEW.aggregator_admin_approved_at := NULL;
    NEW.operator_admin_approved_by := NULL; NEW.operator_admin_approved_at := NULL;
    NEW.activated_distribution_rule_id := NULL;
    NEW.rejected_by := NULL; NEW.rejected_at := NULL; NEW.reject_reason := NULL;
    NEW.created_at := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_distribution_rule_proposal_insert
    BEFORE INSERT ON public.distribution_rule_proposals
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_distribution_rule_proposal_insert();

-- BEFORE UPDATE : garde structurelle des deltas permis (défense en
-- profondeur — la logique métier vit dans les RPC d'approbation).
CREATE OR REPLACE FUNCTION public.carbon_distribution_rule_proposal_before_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_new_approvals INT;
BEGIN
    IF NEW.id <> OLD.id OR NEW.aggregator_id <> OLD.aggregator_id OR NEW.platform_fee_pct <> OLD.platform_fee_pct
       OR NEW.reserve_pct <> OLD.reserve_pct OR NEW.default_weight <> OLD.default_weight
       OR NEW.proposed_by <> OLD.proposed_by OR NEW.proposed_at <> OLD.proposed_at OR NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'Modification refusée : les champs de proposition d''origine sont immuables.';
    END IF;
    IF OLD.status <> 'pending' THEN
        RAISE EXCEPTION 'Modification refusée : une proposition % n''est plus modifiable.', OLD.status;
    END IF;

    -- Corrigé après la HUITIÈME revue statique (bloqueur 1) : ces trois invariants d'approbation
    -- s'appliquaient auparavant UNIQUEMENT sous IF NEW.status = 'pending' — un DML privilégié pouvait
    -- donc, en une seule UPDATE, faire passer status de 'pending' à 'activated' TOUT EN injectant
    -- simultanément les deux approbations (et activated_distribution_rule_id), contournant entièrement
    -- l'atomicité/immutabilité voulues puisque NEW.status n'était plus 'pending' au moment du contrôle.
    -- Ces invariants s'appliquent désormais à TOUT UPDATE dont OLD.status = 'pending' (déjà garanti à ce
    -- point par le rejet ci-dessus), AVANT tout branchement sur NEW.status — aucune transition, y
    -- compris vers 'activated'/'rejected'/'withdrawn', ne peut donc jamais faire passer, modifier ou
    -- désynchroniser une approbation en dehors du chemin normal (RPC d'approbation dédiée, qui laisse
    -- toujours status = 'pending').

    -- (A/C) immutabilité intégrale d'une approbation déjà posée dans OLD (les deux colonnes de la paire).
    IF OLD.aggregator_admin_approved_by IS NOT NULL AND (
           NEW.aggregator_admin_approved_by IS DISTINCT FROM OLD.aggregator_admin_approved_by
        OR NEW.aggregator_admin_approved_at IS DISTINCT FROM OLD.aggregator_admin_approved_at
    ) THEN
        RAISE EXCEPTION 'Modification refusée : une approbation déjà posée est immuable.';
    END IF;
    IF OLD.operator_admin_approved_by IS NOT NULL AND (
           NEW.operator_admin_approved_by IS DISTINCT FROM OLD.operator_admin_approved_by
        OR NEW.operator_admin_approved_at IS DISTINCT FROM OLD.operator_admin_approved_at
    ) THEN
        RAISE EXCEPTION 'Modification refusée : une approbation déjà posée est immuable.';
    END IF;
    -- (B) atomicité pending -> pending : au plus UNE transition NULL -> NOT NULL par UPDATE.
    -- (G, NEUVIÈME revue statique, bloqueur 2) : toute transition HORS de 'pending' (activated/
    -- rejected/withdrawn) doit désormais porter EXACTEMENT ZÉRO nouvelle approbation — jamais une
    -- seule non plus. Avant ce correctif, seule la borne « au plus une » était vérifiée quel que soit
    -- NEW.status, ce qui laissait passer, par exemple, pending -> rejected accompagné d'une injection
    -- simultanée de l'unique approbation encore NULL (une seule transition, donc <= 1, mais jamais
    -- légitime hors de 'pending' : une issue finale ne doit jamais aussi modifier l'état d'approbation).
    v_new_approvals :=
        (CASE WHEN OLD.aggregator_admin_approved_by IS NULL AND NEW.aggregator_admin_approved_by IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN OLD.operator_admin_approved_by IS NULL AND NEW.operator_admin_approved_by IS NOT NULL THEN 1 ELSE 0 END);

    IF NEW.status = 'pending' THEN
        IF v_new_approvals > 1 THEN
            RAISE EXCEPTION 'Modification refusée : une seule approbation peut être posée par opération, jamais les deux simultanément.';
        END IF;
    ELSE
        IF v_new_approvals <> 0 THEN
            RAISE EXCEPTION 'Modification refusée : aucune nouvelle approbation ne peut être posée lors d''une transition hors de ''pending'' (activated/rejected/withdrawn) — une approbation ne peut être posée que par sa propre opération dédiée, jamais combinée à un changement de statut.';
        END IF;
    END IF;

    IF NEW.status = 'pending' THEN
        IF NEW.rejected_by IS NOT NULL OR NEW.activated_distribution_rule_id IS NOT NULL THEN
            RAISE EXCEPTION 'Modification refusée : incohérence — statut reste pending mais des champs d''issue sont renseignés.';
        END IF;
    ELSIF NEW.status = 'activated' THEN
        -- (D/E/F) la transition d'activation ne doit JAMAIS être l'opération qui pose la dernière
        -- approbation : OLD doit déjà contenir les 2/2 approbations complètes AVANT cette UPDATE (les
        -- invariants A/B ci-dessus, désormais inconditionnels, garantissent en plus qu'aucune des deux
        -- paires ne change pendant cette même UPDATE).
        IF OLD.aggregator_admin_approved_by IS NULL OR OLD.operator_admin_approved_by IS NULL THEN
            RAISE EXCEPTION 'Activation refusée : les 2/2 approbations doivent déjà être complètes dans la ligne existante avant cette transition — jamais posées par la même opération que l''activation.';
        END IF;
        IF NEW.activated_distribution_rule_id IS NULL THEN
            RAISE EXCEPTION 'Activation refusée : activated_distribution_rule_id doit être renseigné.';
        END IF;
        -- Ajouté après la HUITIÈME revue statique (bloqueur 2) : la FK garantit seulement que
        -- activated_distribution_rule_id désigne une distribution_rule EXISTANTE, jamais qu'elle est
        -- réellement le résultat de CETTE proposition — insuffisant pour la traçabilité économique. Le
        -- flux légitime (carbon_try_activate_distribution_rule_proposal()) crée toujours la
        -- distribution_rule AVANT cette UPDATE, avec proposal_id = OLD.id et aggregator_id =
        -- OLD.aggregator_id — cette garde accepte donc le flux normal sans y ajouter de contrainte.
        IF NOT EXISTS (
            SELECT 1 FROM public.distribution_rules dr
            WHERE dr.id = NEW.activated_distribution_rule_id
              AND dr.proposal_id = OLD.id
              AND dr.aggregator_id = OLD.aggregator_id
        ) THEN
            RAISE EXCEPTION 'Activation refusée : activated_distribution_rule_id ne correspond pas à une distribution_rule réellement produite par CETTE proposition (proposal_id/aggregator_id attendus non satisfaits).';
        END IF;
    ELSIF NEW.status = 'rejected' THEN
        IF NEW.rejected_by IS NULL OR NEW.rejected_at IS NULL OR NEW.reject_reason IS NULL OR btrim(NEW.reject_reason) = '' THEN
            RAISE EXCEPTION 'Rejet refusé : rejected_by/rejected_at/reject_reason (non vide) doivent être renseignés.';
        END IF;
    ELSIF NEW.status = 'withdrawn' THEN
        NULL; -- aucun champ supplémentaire requis, retrait par le proposant (vérifié par la RPC)
    ELSE
        RAISE EXCEPTION 'Transition de statut refusée : pending -> % n''est pas valide.', NEW.status;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_distribution_rule_proposal_before_update
    BEFORE UPDATE ON public.distribution_rule_proposals
    FOR EACH ROW EXECUTE FUNCTION public.carbon_distribution_rule_proposal_before_update();

CREATE TRIGGER trg_carbon_distribution_rule_proposals_forbid_delete
    BEFORE DELETE ON public.distribution_rule_proposals
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- BEFORE UPDATE distribution_rules : seule mutation permise = fermeture
-- effective_to (NULL -> valeur, une seule fois).
CREATE OR REPLACE FUNCTION public.carbon_distribution_rule_before_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.id <> OLD.id OR NEW.aggregator_id <> OLD.aggregator_id OR NEW.platform_fee_pct <> OLD.platform_fee_pct
       OR NEW.reserve_pct <> OLD.reserve_pct OR NEW.default_weight <> OLD.default_weight
       OR NEW.effective_from <> OLD.effective_from OR NEW.proposal_id <> OLD.proposal_id
       OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'Modification refusée : distribution_rules est immuable hors fermeture de effective_to.';
    END IF;
    IF OLD.effective_to IS NOT NULL THEN
        RAISE EXCEPTION 'Modification refusée : effective_to déjà fermé, immuable.';
    END IF;
    IF NEW.effective_to IS NULL THEN
        RAISE EXCEPTION 'Modification refusée : seule la fermeture de effective_to (NULL -> valeur) est permise.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_distribution_rule_before_update
    BEFORE UPDATE ON public.distribution_rules
    FOR EACH ROW EXECUTE FUNCTION public.carbon_distribution_rule_before_update();

CREATE TRIGGER trg_carbon_distribution_rules_forbid_delete
    BEFORE DELETE ON public.distribution_rules
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- AJOUTÉ à la DIXIÈME revue statique (bloqueur 3B) : une nouvelle version doit TOUJOURS naître active
-- (effective_to IS NULL) — sans cette garde, un INSERT privilégié direct pouvait fournir un
-- effective_to déjà renseigné dès la création, contournant la seule fermeture légitime prévue
-- (trg_carbon_distribution_rule_before_update ci-dessus, qui ne s'applique qu'aux UPDATE). La fermeture
-- NULL -> valeur reste permise UNIQUEMENT par ce trigger BEFORE UPDATE existant, jamais dès l'INSERT.
CREATE OR REPLACE FUNCTION public.carbon_guard_distribution_rule_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.effective_to IS NOT NULL THEN
        RAISE EXCEPTION 'Insertion refusée : une nouvelle distribution_rule doit toujours naître active (effective_to NULL) — sa fermeture éventuelle ne peut se faire que par UPDATE ultérieur.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_distribution_rule_insert
    BEFORE INSERT ON public.distribution_rules
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_distribution_rule_insert();

-- ────────────────────────────────────────────────────────────
-- 5. TABLES member_distribution_overrides et
--    member_distribution_override_proposals (§17 point 5)
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.member_distribution_overrides (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregator_membership_id  UUID NOT NULL REFERENCES public.aggregator_memberships(id) ON DELETE RESTRICT,
    override_type             TEXT NOT NULL CHECK (override_type IN ('fee_pct','reserve_pct','weight_multiplier')),
    override_value            NUMERIC(8,4) NOT NULL,
    effective_from            DATE NOT NULL,
    effective_until           DATE NOT NULL CHECK (effective_until >= effective_from),
    proposal_id               UUID NOT NULL,   -- FK ajoutée en section 7 (dépendance circulaire)
    created_at                TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    created_by                UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    revoked_at                TIMESTAMPTZ NULL,
    revoked_by                UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    revocation_proposal_id    UUID NULL,       -- FK ajoutée en section 7

    -- RENFORCÉ à la DIXIÈME revue statique (bloqueur 3A) : l'ancienne forme ((revoked_at IS NULL) =
    -- (revoked_by IS NULL)) ne couvrait pas revocation_proposal_id, laissant représentable un état
    -- où revoked_at/revoked_by seraient tous deux NULL mais revocation_proposal_id renseigné (ou
    -- l'inverse). Désormais all-or-none strict sur les TROIS colonnes ensemble : soit aucune des trois
    -- n'est renseignée (état initial, seul atteignable à l'INSERT — voir garde BEFORE INSERT ci-dessous),
    -- soit les trois le sont simultanément (état révoqué, atteignable UNIQUEMENT par UPDATE ultérieur,
    -- validé par le constraint trigger différé trg_carbon_check_member_distribution_override_revocation_integrity).
    CONSTRAINT member_distribution_overrides_revoked_check CHECK (
        (revoked_at IS NULL AND revoked_by IS NULL AND revocation_proposal_id IS NULL)
        OR
        (revoked_at IS NOT NULL AND revoked_by IS NOT NULL AND revocation_proposal_id IS NOT NULL)
    ),
    -- Bornes durcies après la première revue statique (point 9) : fee_pct/reserve_pct plafonnés à 100,
    -- weight_multiplier strictement positif (jamais 0 — un poids nul exclurait silencieusement un membre
    -- de la répartition sans passer par un mécanisme explicite prévu à cet effet).
    CONSTRAINT member_distribution_overrides_value_bounds_check CHECK (
        (override_type IN ('fee_pct','reserve_pct') AND override_value >= 0 AND override_value <= 100 AND override_value <> 'NaN'::numeric)
        OR
        (override_type = 'weight_multiplier' AND override_value > 0 AND override_value <> 'NaN'::numeric)
    )
);

CREATE INDEX idx_member_distribution_overrides_membership ON public.member_distribution_overrides(aggregator_membership_id);

-- EXCLUDE — REVU après la première revue statique (point 6) : la version précédente n'excluait le
-- chevauchement qu'entre lignes ACTUELLEMENT non révoquées (WHERE revoked_at IS NULL), ce qui reposait
-- implicitement sur l'atomicité du mécanisme 'replace' (created_at de la nouvelle ligne = revoked_at de
-- l'ancienne, exactement) pour garantir qu'aucune requête historique ne puisse jamais voir deux lignes
-- actives simultanément à un instant confirmed_at donné. Remplacée par une exclusion à DEUX dimensions,
-- correcte par construction plutôt que par un invariant supposé ailleurs : le chevauchement des fenêtres
-- de PUBLICATION (tstzrange(created_at, revoked_at), borne supérieure NULL = toujours ouverte) est
-- désormais requis EN PLUS du chevauchement des fenêtres d'EFFET (daterange(effective_from,
-- effective_until)) pour qu'un conflit soit détecté — deux lignes aux fenêtres d'effet identiques mais
-- dont l'une a été révoquée avant la création de l'autre (publication non concurrente) ne se chevauchent
-- plus au sens de cette contrainte, ce qui est correct : à tout instant confirmed_at donné, au plus une
-- ligne peut satisfaire la sélection temporelle de compute_credit_sale_allocations() (point 6/13).
ALTER TABLE public.member_distribution_overrides
    ADD CONSTRAINT member_distribution_overrides_no_overlap
    EXCLUDE USING gist (
        aggregator_membership_id WITH =, override_type WITH =,
        daterange(effective_from, effective_until, '[]') WITH &&,
        tstzrange(created_at, revoked_at) WITH &&
    );

COMMENT ON TABLE public.member_distribution_overrides IS
  'Exception temporaire et facultative à la règle générale du regroupement pour une adhésion précise (§17 point 5). '
  'revoked_at DB-owned, forcé à l''instant de la dernière approbation de révocation — jamais rétroactif.';

-- AJOUTÉ à la DIXIÈME revue statique (bloqueur 3A) : toute nouvelle ligne doit naître STRICTEMENT non
-- révoquée. Le CHECK all-or-none ci-dessus permet déjà, en théorie, un INSERT direct fournissant les
-- trois colonnes revoked_at/revoked_by/revocation_proposal_id simultanément (un override qui naîtrait
-- « déjà révoqué », sans jamais être passé par le flux légitime create -> UPDATE de révocation) — cette
-- garde BEFORE INSERT ferme structurellement cette possibilité : le second état (révoqué) n'est
-- atteignable qu'ULTÉRIEUREMENT via UPDATE, jamais dès la création, et reste alors validé par le
-- constraint trigger différé de révocation.
CREATE OR REPLACE FUNCTION public.carbon_guard_member_distribution_override_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.revoked_at IS NOT NULL OR NEW.revoked_by IS NOT NULL OR NEW.revocation_proposal_id IS NOT NULL THEN
        RAISE EXCEPTION 'Insertion refusée : un nouveau member_distribution_overrides doit toujours naître strictement non révoqué (revoked_at/revoked_by/revocation_proposal_id tous NULL) — la révocation ne peut se faire que par UPDATE ultérieur.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_member_distribution_override_insert
    BEFORE INSERT ON public.member_distribution_overrides
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_member_distribution_override_insert();

CREATE TABLE public.member_distribution_override_proposals (
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_type                   TEXT NOT NULL CHECK (proposal_type IN ('create','replace','revoke')),
    aggregator_membership_id        UUID NOT NULL REFERENCES public.aggregator_memberships(id) ON DELETE RESTRICT,
    target_override_id              UUID NULL REFERENCES public.member_distribution_overrides(id) ON DELETE RESTRICT,
    override_type                   TEXT NULL CHECK (override_type IN ('fee_pct','reserve_pct','weight_multiplier')),
    override_value                  NUMERIC(8,4) NULL,
    proposed_effective_from         DATE NULL,
    proposed_effective_until        DATE NULL CHECK (proposed_effective_until IS NULL OR proposed_effective_from IS NULL OR proposed_effective_until >= proposed_effective_from),
    revoke_reason                   TEXT NULL,
    status                          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','activated','rejected','withdrawn')),
    proposed_by                     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    proposed_at                     TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    organization_admin_approved_by  UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    organization_admin_approved_at  TIMESTAMPTZ NULL,
    aggregator_admin_approved_by    UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    aggregator_admin_approved_at    TIMESTAMPTZ NULL,
    operator_admin_approved_by      UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    operator_admin_approved_at      TIMESTAMPTZ NULL,
    activated_override_id           UUID NULL REFERENCES public.member_distribution_overrides(id) ON DELETE RESTRICT,
    rejected_by                     UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    rejected_at                     TIMESTAMPTZ NULL,
    reject_reason                   TEXT NULL,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT member_distribution_override_proposals_type_check CHECK (
        (proposal_type = 'create' AND target_override_id IS NULL
          AND override_type IS NOT NULL AND override_value IS NOT NULL
          AND proposed_effective_from IS NOT NULL AND proposed_effective_until IS NOT NULL AND revoke_reason IS NULL)
        OR
        (proposal_type = 'replace' AND target_override_id IS NOT NULL
          AND override_type IS NOT NULL AND override_value IS NOT NULL
          AND proposed_effective_from IS NOT NULL AND proposed_effective_until IS NOT NULL AND revoke_reason IS NULL)
        OR
        (proposal_type = 'revoke' AND target_override_id IS NOT NULL
          AND override_type IS NULL AND override_value IS NULL
          AND proposed_effective_from IS NULL AND proposed_effective_until IS NULL
          AND revoke_reason IS NOT NULL AND btrim(revoke_reason) <> '')
    ),
    CONSTRAINT member_distribution_override_proposals_activated_check CHECK ((status = 'activated') = (activated_override_id IS NOT NULL)),
    -- Corrigé après la NEUVIÈME revue statique (bloqueur 3), symétrique à distribution_rule_proposals
    -- ci-dessus : all-or-none imposé explicitement dans les DEUX sens, aucune métadonnée de rejet
    -- partiellement renseignée tolérée hors de status='rejected'.
    CONSTRAINT member_distribution_override_proposals_rejected_check CHECK (
        (status = 'rejected' AND rejected_by IS NOT NULL AND rejected_at IS NOT NULL AND reject_reason IS NOT NULL AND btrim(reject_reason) <> '')
        OR
        (status <> 'rejected' AND rejected_by IS NULL AND rejected_at IS NULL AND reject_reason IS NULL)
    ),
    -- Mêmes bornes que member_distribution_overrides (point 9), tolérant NULL pour proposal_type='revoke'.
    CONSTRAINT member_distribution_override_proposals_value_bounds_check CHECK (
        override_value IS NULL
        OR (override_type IN ('fee_pct','reserve_pct') AND override_value >= 0 AND override_value <= 100 AND override_value <> 'NaN'::numeric)
        OR (override_type = 'weight_multiplier' AND override_value > 0 AND override_value <> 'NaN'::numeric)
    ),
    -- Ajoutés après la SIXIÈME revue statique (correction 2), symétriques à distribution_rule_proposals
    -- ci-dessus : chaque couple approved_by/approved_at est indissociable, et l'activation exige
    -- structurellement les TROIS approbations complètes — défense en profondeur contre un UPDATE
    -- privilégié direct contournant les RPC d'approbation.
    CONSTRAINT member_distribution_override_proposals_organization_admin_pair_check
        CHECK ((organization_admin_approved_by IS NULL) = (organization_admin_approved_at IS NULL)),
    CONSTRAINT member_distribution_override_proposals_aggregator_admin_pair_check
        CHECK ((aggregator_admin_approved_by IS NULL) = (aggregator_admin_approved_at IS NULL)),
    CONSTRAINT member_distribution_override_proposals_operator_admin_pair_check
        CHECK ((operator_admin_approved_by IS NULL) = (operator_admin_approved_at IS NULL)),
    CONSTRAINT member_distribution_override_proposals_activated_requires_all_approvals_check
        CHECK (status <> 'activated' OR (organization_admin_approved_by IS NOT NULL AND aggregator_admin_approved_by IS NOT NULL AND operator_admin_approved_by IS NOT NULL))
);

CREATE INDEX idx_member_distribution_override_proposals_membership ON public.member_distribution_override_proposals(aggregator_membership_id);
CREATE INDEX idx_member_distribution_override_proposals_status ON public.member_distribution_override_proposals(status);
CREATE INDEX idx_member_distribution_override_proposals_target ON public.member_distribution_override_proposals(target_override_id);

COMMENT ON TABLE public.member_distribution_override_proposals IS
  'Gouvernance à triple approbation de member_distribution_overrides (§17 point 5) : admin organisation '
  '(jamais substituable) + primary_admin du regroupement + admin opérateur METALTRACE (substitution super-admin '
  'limitée à ce dernier rôle). create/replace/revoke via le même mécanisme audité — révocation = même triple approbation.';

CREATE OR REPLACE FUNCTION public.carbon_guard_member_distribution_override_proposal_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_actor UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    NEW.status := 'pending';
    NEW.proposed_by := v_actor;
    NEW.proposed_at := clock_timestamp();
    NEW.organization_admin_approved_by := NULL; NEW.organization_admin_approved_at := NULL;
    NEW.aggregator_admin_approved_by := NULL; NEW.aggregator_admin_approved_at := NULL;
    NEW.operator_admin_approved_by := NULL; NEW.operator_admin_approved_at := NULL;
    NEW.activated_override_id := NULL;
    NEW.rejected_by := NULL; NEW.rejected_at := NULL; NEW.reject_reason := NULL;
    NEW.created_at := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_member_distribution_override_proposal_insert
    BEFORE INSERT ON public.member_distribution_override_proposals
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_member_distribution_override_proposal_insert();

CREATE OR REPLACE FUNCTION public.carbon_member_distribution_override_proposal_before_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_new_approvals INT;
BEGIN
    IF NEW.id <> OLD.id OR NEW.proposal_type <> OLD.proposal_type OR NEW.aggregator_membership_id <> OLD.aggregator_membership_id
       OR NEW.target_override_id IS DISTINCT FROM OLD.target_override_id
       OR NEW.override_type IS DISTINCT FROM OLD.override_type OR NEW.override_value IS DISTINCT FROM OLD.override_value
       OR NEW.proposed_effective_from IS DISTINCT FROM OLD.proposed_effective_from
       OR NEW.proposed_effective_until IS DISTINCT FROM OLD.proposed_effective_until
       OR NEW.revoke_reason IS DISTINCT FROM OLD.revoke_reason
       OR NEW.proposed_by <> OLD.proposed_by OR NEW.proposed_at <> OLD.proposed_at OR NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'Modification refusée : les champs de proposition d''origine sont immuables.';
    END IF;
    IF OLD.status <> 'pending' THEN
        RAISE EXCEPTION 'Modification refusée : une proposition % n''est plus modifiable.', OLD.status;
    END IF;

    -- Corrigé après la HUITIÈME revue statique (bloqueur 1), même défaut que
    -- distribution_rule_proposals : ces invariants d'approbation s'appliquaient auparavant UNIQUEMENT
    -- sous IF NEW.status = 'pending' — un DML privilégié pouvait donc, en une seule UPDATE, faire
    -- passer status de 'pending' à 'activated' TOUT EN injectant simultanément les trois approbations
    -- (et activated_override_id), contournant l'atomicité/immutabilité voulues. Ces invariants
    -- s'appliquent désormais à TOUT UPDATE dont OLD.status = 'pending', AVANT tout branchement sur
    -- NEW.status.

    -- (A/C) immutabilité intégrale d'une approbation déjà posée dans OLD.
    IF OLD.organization_admin_approved_by IS NOT NULL AND (
           NEW.organization_admin_approved_by IS DISTINCT FROM OLD.organization_admin_approved_by
        OR NEW.organization_admin_approved_at IS DISTINCT FROM OLD.organization_admin_approved_at
    ) THEN
        RAISE EXCEPTION 'Modification refusée : une approbation déjà posée est immuable.';
    END IF;
    IF OLD.aggregator_admin_approved_by IS NOT NULL AND (
           NEW.aggregator_admin_approved_by IS DISTINCT FROM OLD.aggregator_admin_approved_by
        OR NEW.aggregator_admin_approved_at IS DISTINCT FROM OLD.aggregator_admin_approved_at
    ) THEN
        RAISE EXCEPTION 'Modification refusée : une approbation déjà posée est immuable.';
    END IF;
    IF OLD.operator_admin_approved_by IS NOT NULL AND (
           NEW.operator_admin_approved_by IS DISTINCT FROM OLD.operator_admin_approved_by
        OR NEW.operator_admin_approved_at IS DISTINCT FROM OLD.operator_admin_approved_at
    ) THEN
        RAISE EXCEPTION 'Modification refusée : une approbation déjà posée est immuable.';
    END IF;
    -- (B) atomicité pending -> pending : au plus UNE transition NULL -> NOT NULL par UPDATE.
    -- (G, NEUVIÈME revue statique, bloqueur 2), symétrique à distribution_rule_proposals ci-dessus :
    -- toute transition HORS de 'pending' (activated/rejected/withdrawn) doit désormais porter
    -- EXACTEMENT ZÉRO nouvelle approbation — jamais une seule non plus.
    v_new_approvals :=
        (CASE WHEN OLD.organization_admin_approved_by IS NULL AND NEW.organization_admin_approved_by IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN OLD.aggregator_admin_approved_by IS NULL AND NEW.aggregator_admin_approved_by IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN OLD.operator_admin_approved_by IS NULL AND NEW.operator_admin_approved_by IS NOT NULL THEN 1 ELSE 0 END);

    IF NEW.status = 'pending' THEN
        IF v_new_approvals > 1 THEN
            RAISE EXCEPTION 'Modification refusée : une seule approbation peut être posée par opération, jamais deux ou trois simultanément.';
        END IF;
    ELSE
        IF v_new_approvals <> 0 THEN
            RAISE EXCEPTION 'Modification refusée : aucune nouvelle approbation ne peut être posée lors d''une transition hors de ''pending'' (activated/rejected/withdrawn) — une approbation ne peut être posée que par sa propre opération dédiée, jamais combinée à un changement de statut.';
        END IF;
    END IF;

    IF NEW.status = 'pending' THEN
        IF NEW.rejected_by IS NOT NULL OR NEW.activated_override_id IS NOT NULL THEN
            RAISE EXCEPTION 'Modification refusée : incohérence — statut reste pending mais des champs d''issue sont renseignés.';
        END IF;
    ELSIF NEW.status = 'activated' THEN
        -- (D/E/F) OLD doit déjà contenir les 3/3 approbations complètes AVANT cette transition — jamais
        -- posées par la même opération que l'activation (A/B ci-dessus le garantissent désormais).
        IF OLD.organization_admin_approved_by IS NULL OR OLD.aggregator_admin_approved_by IS NULL OR OLD.operator_admin_approved_by IS NULL THEN
            RAISE EXCEPTION 'Activation refusée : les 3/3 approbations doivent déjà être complètes dans la ligne existante avant cette transition — jamais posées par la même opération que l''activation.';
        END IF;
        IF NEW.activated_override_id IS NULL THEN
            RAISE EXCEPTION 'Activation refusée : activated_override_id doit être renseigné.';
        END IF;
        -- Ajouté après la HUITIÈME revue statique (bloqueur 2) : la FK garantit seulement l'existence de
        -- la ligne, jamais qu'elle est réellement le résultat de CETTE proposition. Trois cas exacts
        -- correspondant au flux légitime de carbon_try_activate_member_distribution_override_proposal() :
        --   'create'/'replace' : la nouvelle ligne member_distribution_overrides est créée AVANT cette
        --     UPDATE, avec proposal_id = OLD.id et aggregator_membership_id = OLD.aggregator_membership_id.
        --   'revoke' : NEW.activated_override_id doit être EXACTEMENT OLD.target_override_id (aucune
        --     nouvelle ligne n'est créée — l'override CIBLE est révoqué en place), et cette cible doit
        --     déjà porter revocation_proposal_id = OLD.id, revoked_at IS NOT NULL et la même adhésion.
        IF OLD.proposal_type IN ('create', 'replace') THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.member_distribution_overrides mdo
                WHERE mdo.id = NEW.activated_override_id
                  AND mdo.proposal_id = OLD.id
                  AND mdo.aggregator_membership_id = OLD.aggregator_membership_id
            ) THEN
                RAISE EXCEPTION 'Activation refusée : activated_override_id ne correspond pas à un member_distribution_override réellement produit par CETTE proposition (proposal_id/aggregator_membership_id attendus non satisfaits).';
            END IF;
        ELSIF OLD.proposal_type = 'revoke' THEN
            IF NEW.activated_override_id IS DISTINCT FROM OLD.target_override_id THEN
                RAISE EXCEPTION 'Activation refusée : pour une révocation, activated_override_id doit désigner exactement l''override ciblé par la proposition (target_override_id), jamais une autre ligne.';
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM public.member_distribution_overrides mdo
                WHERE mdo.id = OLD.target_override_id
                  AND mdo.aggregator_membership_id = OLD.aggregator_membership_id
                  AND mdo.revocation_proposal_id = OLD.id
                  AND mdo.revoked_at IS NOT NULL
            ) THEN
                RAISE EXCEPTION 'Activation refusée : pour une révocation, l''override ciblé doit déjà être révoqué avec revocation_proposal_id pointant vers CETTE proposition.';
            END IF;
        END IF;
    ELSIF NEW.status = 'rejected' THEN
        IF NEW.rejected_by IS NULL OR NEW.rejected_at IS NULL OR NEW.reject_reason IS NULL OR btrim(NEW.reject_reason) = '' THEN
            RAISE EXCEPTION 'Rejet refusé : rejected_by/rejected_at/reject_reason (non vide) doivent être renseignés.';
        END IF;
    ELSIF NEW.status = 'withdrawn' THEN
        NULL;
    ELSE
        RAISE EXCEPTION 'Transition de statut refusée : pending -> % n''est pas valide.', NEW.status;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_member_distribution_override_proposal_before_update
    BEFORE UPDATE ON public.member_distribution_override_proposals
    FOR EACH ROW EXECUTE FUNCTION public.carbon_member_distribution_override_proposal_before_update();

CREATE TRIGGER trg_carbon_member_distribution_override_proposals_forbid_delete
    BEFORE DELETE ON public.member_distribution_override_proposals
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- BEFORE UPDATE member_distribution_overrides : seule mutation permise =
-- révocation (revoked_at/revoked_by/revocation_proposal_id NULL -> valeur,
-- une seule fois) — jamais rétroactive sur effective_from/effective_until.
CREATE OR REPLACE FUNCTION public.carbon_member_distribution_override_before_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.id <> OLD.id OR NEW.aggregator_membership_id <> OLD.aggregator_membership_id
       OR NEW.override_type <> OLD.override_type OR NEW.override_value <> OLD.override_value
       OR NEW.effective_from <> OLD.effective_from OR NEW.effective_until <> OLD.effective_until
       OR NEW.proposal_id <> OLD.proposal_id OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at THEN
        RAISE EXCEPTION 'Modification refusée : member_distribution_overrides est immuable hors révocation.';
    END IF;
    IF OLD.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'Modification refusée : override déjà révoqué, immuable.';
    END IF;
    IF NEW.revoked_at IS NULL THEN
        RAISE EXCEPTION 'Modification refusée : seule la révocation (NULL -> valeur) est permise.';
    END IF;
    IF NEW.revoked_by IS NULL OR NEW.revocation_proposal_id IS NULL THEN
        RAISE EXCEPTION 'Révocation refusée : revoked_by/revocation_proposal_id doivent être renseignés.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_member_distribution_override_before_update
    BEFORE UPDATE ON public.member_distribution_overrides
    FOR EACH ROW EXECUTE FUNCTION public.carbon_member_distribution_override_before_update();

CREATE TRIGGER trg_carbon_member_distribution_overrides_forbid_delete
    BEFORE DELETE ON public.member_distribution_overrides
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 6. TABLE credit_sale_allocations (§17 point 6)
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.credit_sale_allocations (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_sale_id          UUID NOT NULL REFERENCES public.credit_sales(id) ON DELETE RESTRICT,
    organization_id         UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    aggregator_id           UUID NOT NULL REFERENCES public.aggregators(id) ON DELETE RESTRICT,
    allocation_type         TEXT NOT NULL DEFAULT 'carbon_revenue'
                              CHECK (allocation_type IN ('carbon_revenue','reserve','platform_fee')),
                              -- 'platform_fee' AJOUTÉ après la première revue statique (point 1) : porte le
                              -- frais de plateforme retenu, distinct de 'reserve' (réserve véritable) et de
                              -- credit_sale_costs.cost_type='platform_fee' (coût de la vente entière, §3).
                              -- RÉDUIT à 3 valeurs après la deuxième revue statique (point 6) :
                              -- 'expense_reimbursement'/'bonus'/'adjustment' retirées — aucune RPC de ce MVP
                              -- ne les crée, aucune écriture directe n'est exposée, et credit_sale_allocations_unique
                              -- (4 colonnes) ne peut pas représenter proprement plusieurs ajustements par paire.
                              -- Toute correction financière post-confirmation passe par credit_sale_adjustments
                              -- (§17 point 3/13 item 6, décision explicite, jamais improvisée en silence).
    allocated_tco2e         NUMERIC(14,4) NULL,
    tco2e_rounding_adjustment NUMERIC(14,4) NOT NULL DEFAULT 0,
    gross_amount            NUMERIC(14,2) NOT NULL CHECK (gross_amount >= 0 AND gross_amount <> 'NaN'::numeric),
    fee_applied_pct         NUMERIC(5,2) NOT NULL,
    reserve_applied_pct     NUMERIC(5,2) NOT NULL,
    weight_applied          NUMERIC(8,4) NOT NULL,
    fee_amount              NUMERIC(14,2) NOT NULL,
    reserve_amount          NUMERIC(14,2) NOT NULL,
    net_amount              NUMERIC(14,2) NOT NULL,
    amount_rounding_adjustment NUMERIC(14,2) NOT NULL DEFAULT 0,
    distribution_rule_id    UUID NULL REFERENCES public.distribution_rules(id) ON DELETE RESTRICT,
    rule_snapshot           JSONB NOT NULL,
    calculation_snapshot    JSONB NOT NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    -- Corrigé après la troisième revue statique (points 8 et 9) :
    --   Point 8 — allocated_tco2e ne porte plus QUE 'carbon_revenue' (l'attribution carbone elle-même,
    --   §17 point 20 décision 1) ; 'reserve' ET 'platform_fee' sont désormais TOUS DEUX purement
    --   financiers (allocated_tco2e NULL), jamais une répétition de la même attribution carbone sur
    --   trois lignes. Conséquence directe et RECHERCHÉE : SUM(allocated_tco2e) sur TOUTES les lignes
    --   d'une vente (sans filtre allocation_type) égale STRUCTURELLEMENT total_tco2e — SUM ignore les
    --   NULL par construction SQL, donc un rapport qui ne filtre pas obtient déjà la bonne somme.
    --   Point 9 — borne durcie de > 0 à >= 0 : une source historiquement positive (contributed_tco2e >
    --   0 dans credit_issuance_sources) mais dont la part attribuée à ce lot précis se tronque à
    --   0.0000 (TRUNC(sale_lot_quantity_tco2e * ratio, 4) — corrigé en TRUNC après la CINQUIÈME revue
    --   statique, bloqueur 3, ce commentaire disait encore ROUND avant la SIXIÈME revue statique) est
    --   une attribution LÉGITIME, jamais une erreur — la version précédente (> 0 strict) aurait fait
    --   échouer confirm_credit_sale() en
    --   entier dans ce cas réel, pourtant arithmétiquement correct. La provenance de ce zéro (le
    --   contributed_tco2e réel et le ratio exact ayant produit l'arrondi) reste intégralement tracée
    --   dans calculation_snapshot (v_elem, compute_credit_sale_allocations()), jamais perdue.
    CONSTRAINT credit_sale_allocations_tco2e_check CHECK (
        (allocation_type = 'carbon_revenue' AND allocated_tco2e IS NOT NULL
          AND allocated_tco2e >= 0 AND allocated_tco2e <> 'NaN'::numeric)
        OR
        (allocation_type IN ('reserve','platform_fee') AND allocated_tco2e IS NULL)
    ),
    CONSTRAINT credit_sale_allocations_unique UNIQUE (credit_sale_id, organization_id, aggregator_id, allocation_type)
);

CREATE INDEX idx_credit_sale_allocations_sale ON public.credit_sale_allocations(credit_sale_id);
CREATE INDEX idx_credit_sale_allocations_org ON public.credit_sale_allocations(organization_id);
CREATE INDEX idx_credit_sale_allocations_aggregator ON public.credit_sale_allocations(aggregator_id);

COMMENT ON TABLE public.credit_sale_allocations IS
  'Attribution carbone (allocated_tco2e, dérivée de credit_issuance_sources) ET répartition financière '
  '(gross_amount/fee/reserve/net, dérivée de distribution_rules/overrides) — structurellement séparées, '
  'jamais fusionnées (§17 point 6/13). Append-only. Depuis la première revue statique (point 1) : '
  'reserve_amount porte la réserve véritable UNIQUEMENT (jamais le frais) ; le frais de plateforme retenu '
  'est une ligne distincte (allocation_type=''platform_fee''), jamais fusionnée avec ''reserve'' ni avec '
  'credit_sale_costs.cost_type=''platform_fee'' (coût de la vente entière, §3, prélevé en amont). '
  'Depuis la deuxième revue statique (point 6) : allocation_type limité à 3 valeurs réelles '
  '(''carbon_revenue'',''reserve'',''platform_fee'') — les corrections manuelles hors MVP passent par '
  'credit_sale_adjustments, jamais par une ligne allocation_type=''expense_reimbursement''/''bonus''/''adjustment''. '
  'Depuis la troisième revue statique (point 8) : allocated_tco2e porte l''attribution carbone '
  'UNIQUEMENT sur la ligne ''carbon_revenue'' (jamais répétée sur ''reserve''/''platform_fee'', '
  'purement financières, allocated_tco2e NULL) — SUM(allocated_tco2e) sur TOUTES les lignes d''une '
  'vente égale ainsi structurellement total_tco2e, sans filtre allocation_type. Borne >= 0 (point 9) : '
  'une attribution arrondie à 0.0000 pour une source historiquement positive est légitime, jamais '
  'rejetée — sa provenance reste tracée dans calculation_snapshot.';

CREATE TRIGGER trg_carbon_credit_sale_allocations_forbid_update
    BEFORE UPDATE ON public.credit_sale_allocations
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();
CREATE TRIGGER trg_carbon_credit_sale_allocations_forbid_delete
    BEFORE DELETE ON public.credit_sale_allocations
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 7. ALTER TABLE différés — résolution des TROIS dépendances circulaires de
--    FK (§17 point 4/5/18, corrigé après la première revue statique de 09,
--    point 14 : §17 en comptait deux par erreur — member_distribution_overrides
--    a DEUX colonnes distinctes référençant member_distribution_override_proposals,
--    proposal_id (création) ET revocation_proposal_id (révocation), chacune
--    nécessitant son propre ALTER différé), sur des objets TOUS créés par
--    cette migration.
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.distribution_rules
    ADD CONSTRAINT distribution_rules_proposal_id_fkey
    FOREIGN KEY (proposal_id) REFERENCES public.distribution_rule_proposals(id) ON DELETE RESTRICT;

ALTER TABLE public.member_distribution_overrides
    ADD CONSTRAINT member_distribution_overrides_proposal_id_fkey
    FOREIGN KEY (proposal_id) REFERENCES public.member_distribution_override_proposals(id) ON DELETE RESTRICT;

ALTER TABLE public.member_distribution_overrides
    ADD CONSTRAINT member_distribution_overrides_revocation_proposal_id_fkey
    FOREIGN KEY (revocation_proposal_id) REFERENCES public.member_distribution_override_proposals(id) ON DELETE RESTRICT;

-- Ajoutés après la NEUVIÈME revue statique (bloqueur 4, intégrité bidirectionnelle proposition <->
-- objet économique) : chaque proposition ne peut jamais produire/révoquer PLUS D'UNE ligne — une
-- proposal_id (ou revocation_proposal_id) réutilisée sur une deuxième ligne signalerait un doublon
-- structurellement impossible dans le flux légitime (chaque RPC d'activation crée exactement une
-- ligne par proposition). UNIQUE tolère nativement plusieurs NULL (PostgreSQL), donc
-- revocation_proposal_id (NULL tant qu'un override n'est pas révoqué) n'est jamais bloqué par cette
-- contrainte pour les lignes encore actives.
ALTER TABLE public.distribution_rules
    ADD CONSTRAINT distribution_rules_proposal_id_unique UNIQUE (proposal_id);

ALTER TABLE public.member_distribution_overrides
    ADD CONSTRAINT member_distribution_overrides_proposal_id_unique UNIQUE (proposal_id);

ALTER TABLE public.member_distribution_overrides
    ADD CONSTRAINT member_distribution_overrides_revocation_proposal_id_unique UNIQUE (revocation_proposal_id);

-- ────────────────────────────────────────────────────────────
-- 7bis. Intégrité bidirectionnelle proposition <-> objet économique (§17,
--       ajouté après la NEUVIÈME revue statique, bloqueur 4).
--
-- Les gardes des triggers BEFORE UPDATE des propositions (section 4bis/5bis) vérifient déjà, au
-- moment où une PROPOSITION passe à 'activated', que activated_distribution_rule_id/
-- activated_override_id désigne une ligne réellement produite par CETTE proposition (proposal_id/
-- aggregator_id ou aggregator_membership_id). Cela ne suffit PAS à fermer le trou : rien n'empêchait
-- structurellement (a) qu'un INSERT privilégié isolé de distribution_rules/member_distribution_
-- overrides référence un proposal_id dont la proposition reste 'pending' (jamais activée), (b) que
-- l'objet économique porte des valeurs différentes de celles réellement approuvées par la
-- proposition (platform_fee_pct/reserve_pct/default_weight, ou override_type/override_value/dates),
-- ou (c) qu'une révocation privilégiée renseigne revocation_proposal_id sans que la proposition
-- 'revoke' correspondante ait réellement été activée avec ses 3/3 approbations.
--
-- Ces trois CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED ferment ce trou dans le sens INVERSE
-- (objet -> proposition), en complément des gardes déjà existantes (proposition -> objet). Le
-- caractère DEFERRED est OBLIGATOIRE : le flux légitime InsERT toujours l'objet économique AVANT de
-- faire passer sa proposition à 'activated', dans la MÊME transaction — un contrôle IMMEDIATE
-- échouerait donc systématiquement sur le flux normal, entre les deux instructions. Un CONSTRAINT
-- TRIGGER ne peut être que AFTER ROW (restriction PostgreSQL) ; différé, il ne s'évalue qu'au COMMIT
-- (ou sur SET CONSTRAINTS ALL IMMEDIATE explicite), donc uniquement une fois les DEUX écritures de la
-- transaction terminées — voit ainsi l'état final réel, jamais un état intermédiaire incomplet.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_check_distribution_rule_proposal_integrity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_prop RECORD;
BEGIN
    SELECT status, activated_distribution_rule_id, aggregator_id,
           aggregator_admin_approved_by, operator_admin_approved_by,
           platform_fee_pct, reserve_pct, default_weight
    INTO v_prop
    FROM public.distribution_rule_proposals
    WHERE id = NEW.proposal_id;

    IF v_prop IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : distribution_rules.proposal_id (%) ne référence aucune distribution_rule_proposals existante.', NEW.proposal_id;
    END IF;
    IF v_prop.status <> 'activated' THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) référencée par cette distribution_rule doit être ''activated'' au COMMIT (statut réel : %).', NEW.proposal_id, v_prop.status;
    END IF;
    IF v_prop.activated_distribution_rule_id IS DISTINCT FROM NEW.id THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) doit référencer EXACTEMENT cette distribution_rule (%) via activated_distribution_rule_id.', NEW.proposal_id, NEW.id;
    END IF;
    IF v_prop.aggregator_id IS DISTINCT FROM NEW.aggregator_id THEN
        RAISE EXCEPTION 'Intégrité violée : aggregator_id de la proposition (%) et de la distribution_rule (%) doivent être identiques.', NEW.proposal_id, NEW.id;
    END IF;
    IF v_prop.aggregator_admin_approved_by IS NULL OR v_prop.operator_admin_approved_by IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) doit porter les 2/2 approbations complètes au COMMIT.', NEW.proposal_id;
    END IF;
    IF v_prop.platform_fee_pct IS DISTINCT FROM NEW.platform_fee_pct
       OR v_prop.reserve_pct IS DISTINCT FROM NEW.reserve_pct
       OR v_prop.default_weight IS DISTINCT FROM NEW.default_weight THEN
        RAISE EXCEPTION 'Intégrité violée : platform_fee_pct/reserve_pct/default_weight de la distribution_rule (%) doivent être identiques à ceux approuvés par la proposition (%).', NEW.id, NEW.proposal_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_carbon_check_distribution_rule_proposal_integrity
    AFTER INSERT ON public.distribution_rules
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.carbon_check_distribution_rule_proposal_integrity();

-- Ajoutée à la DOUZIÈME revue statique (bloqueur 2) : le modèle canonique ne possède AUCUNE révocation
-- autonome d'une distribution_rule — la fermeture d'une règle active (effective_to NULL -> valeur) n'est
-- QUE l'effet de l'activation d'une NOUVELLE règle doublement approuvée (carbon_try_activate_
-- distribution_rule_proposal(), même v_now pour la fermeture ET effective_from du successeur). Avant
-- cette correction, un UPDATE privilégié direct (SET effective_to = ...) pouvait fermer une règle active
-- SANS successeur, laissant le regroupement sans règle active — jamais un artefact SQL cassé, donc
-- jamais détecté sans ce contrôle dédié. Ce constraint trigger ferme ce trou : il exige, au COMMIT (ou
-- SET CONSTRAINTS ... IMMEDIATE explicite), l'existence d'un successeur exact référençant une
-- proposition activated 2/2 — jamais une simple fermeture isolée.
CREATE OR REPLACE FUNCTION public.carbon_check_distribution_rule_closure_integrity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_successor RECORD;
    v_prop      RECORD;
BEGIN
    SELECT id, aggregator_id, effective_from, effective_to, proposal_id
    INTO v_successor
    FROM public.distribution_rules
    WHERE aggregator_id = NEW.aggregator_id
      AND id <> NEW.id
      AND effective_from = NEW.effective_to;

    IF v_successor IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : la fermeture de la distribution_rule % (effective_to=%) exige un successeur exact (même aggregator_id, effective_from = effective_to EXACTEMENT) — aucune fermeture orpheline (révocation autonome) n''est permise dans ce modèle.', NEW.id, NEW.effective_to;
    END IF;

    -- Le successeur doit lui-même être actif (effective_to IS NULL), SAUF si plusieurs remplacements
    -- légitimes sont volontairement enchaînés dans la même transaction — auquel cas il doit lui-même
    -- posséder un successeur exact (vérifié récursivement par sa PROPRE occurrence de ce même trigger,
    -- revérifié ici pour ne jamais dépendre implicitement de l'ordre d'évaluation des lignes différées).
    IF v_successor.effective_to IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.distribution_rules s2
            WHERE s2.aggregator_id = v_successor.aggregator_id
              AND s2.id <> v_successor.id
              AND s2.effective_from = v_successor.effective_to
        ) THEN
            RAISE EXCEPTION 'Intégrité violée : le successeur (%) de la distribution_rule fermée (%) est lui-même déjà fermé (effective_to=%) sans posséder son propre successeur exact.', v_successor.id, NEW.id, v_successor.effective_to;
        END IF;
    END IF;

    IF v_successor.proposal_id IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : le successeur (%) doit référencer une distribution_rule_proposals via proposal_id.', v_successor.id;
    END IF;

    SELECT status, activated_distribution_rule_id, aggregator_id,
           aggregator_admin_approved_by, operator_admin_approved_by
    INTO v_prop
    FROM public.distribution_rule_proposals
    WHERE id = v_successor.proposal_id;

    IF v_prop IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : proposal_id (%) du successeur (%) ne référence aucune distribution_rule_proposals existante.', v_successor.proposal_id, v_successor.id;
    END IF;
    IF v_prop.status <> 'activated' THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) du successeur doit être ''activated'' au COMMIT (statut réel : %).', v_successor.proposal_id, v_prop.status;
    END IF;
    IF v_prop.activated_distribution_rule_id IS DISTINCT FROM v_successor.id THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) doit référencer EXACTEMENT le successeur (%) via activated_distribution_rule_id.', v_successor.proposal_id, v_successor.id;
    END IF;
    IF v_prop.aggregator_id IS DISTINCT FROM v_successor.aggregator_id THEN
        RAISE EXCEPTION 'Intégrité violée : aggregator_id de la proposition (%) et du successeur (%) doivent être identiques.', v_successor.proposal_id, v_successor.id;
    END IF;
    IF v_prop.aggregator_admin_approved_by IS NULL OR v_prop.operator_admin_approved_by IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) du successeur doit porter les 2/2 approbations complètes au COMMIT.', v_successor.proposal_id;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_carbon_check_distribution_rule_closure_integrity
    AFTER UPDATE OF effective_to ON public.distribution_rules
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    WHEN (OLD.effective_to IS NULL AND NEW.effective_to IS NOT NULL)
    EXECUTE FUNCTION public.carbon_check_distribution_rule_closure_integrity();

CREATE OR REPLACE FUNCTION public.carbon_check_member_distribution_override_creation_integrity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_prop RECORD;
BEGIN
    SELECT proposal_type, status, activated_override_id, aggregator_membership_id,
           override_type, override_value, proposed_effective_from, proposed_effective_until,
           organization_admin_approved_by, aggregator_admin_approved_by, operator_admin_approved_by
    INTO v_prop
    FROM public.member_distribution_override_proposals
    WHERE id = NEW.proposal_id;

    IF v_prop IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : member_distribution_overrides.proposal_id (%) ne référence aucune member_distribution_override_proposals existante.', NEW.proposal_id;
    END IF;
    IF v_prop.proposal_type NOT IN ('create', 'replace') THEN
        RAISE EXCEPTION 'Intégrité violée : proposal_id (%) référencé par cette création doit être de type create ou replace (type réel : %).', NEW.proposal_id, v_prop.proposal_type;
    END IF;
    IF v_prop.status <> 'activated' THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) doit être ''activated'' au COMMIT (statut réel : %).', NEW.proposal_id, v_prop.status;
    END IF;
    IF v_prop.activated_override_id IS DISTINCT FROM NEW.id THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) doit référencer EXACTEMENT cet override (%) via activated_override_id.', NEW.proposal_id, NEW.id;
    END IF;
    IF v_prop.aggregator_membership_id IS DISTINCT FROM NEW.aggregator_membership_id THEN
        RAISE EXCEPTION 'Intégrité violée : aggregator_membership_id de la proposition (%) et de l''override (%) doivent être identiques.', NEW.proposal_id, NEW.id;
    END IF;
    IF v_prop.organization_admin_approved_by IS NULL OR v_prop.aggregator_admin_approved_by IS NULL OR v_prop.operator_admin_approved_by IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) doit porter les 3/3 approbations complètes au COMMIT.', NEW.proposal_id;
    END IF;
    IF v_prop.override_type IS DISTINCT FROM NEW.override_type
       OR v_prop.override_value IS DISTINCT FROM NEW.override_value
       OR v_prop.proposed_effective_from IS DISTINCT FROM NEW.effective_from
       OR v_prop.proposed_effective_until IS DISTINCT FROM NEW.effective_until THEN
        RAISE EXCEPTION 'Intégrité violée : override_type/override_value/effective_from/effective_until de l''override (%) doivent être identiques à ceux approuvés par la proposition (%).', NEW.id, NEW.proposal_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_carbon_check_member_distribution_override_creation_integrity
    AFTER INSERT ON public.member_distribution_overrides
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.carbon_check_member_distribution_override_creation_integrity();

-- CORRIGÉ à la DIXIÈME revue statique (bloqueur 2) : la version précédente exigeait
-- proposal_type = 'revoke' STRICTEMENT, ce qui cassait le flux LÉGITIME 'replace' — un remplacement
-- révoque l'ANCIEN override (revoked_at/revoked_by/revocation_proposal_id posés dessus) tout en créant
-- un NOUVEL override (proposal_id = LA MÊME proposition replace, activated_override_id de la
-- proposition pointant vers ce NOUVEL override, jamais vers l'ancien qu'elle révoque). Les deux cas
-- (revoke pur et replace) partagent des règles communes, mais divergent sur ce que doit valoir
-- activated_override_id relativement à l'override en cours de révocation (NEW.id) :
--   - revoke : activated_override_id = NEW.id (l'override révoqué EST l'objet que la proposition active).
--   - replace : activated_override_id <> NEW.id, et doit référencer un AUTRE override réel, existant,
--     dont le proposal_id est CETTE MÊME proposition replace et dont l'aggregator_membership_id est
--     identique à celui de l'override révoqué — le nouvel override, jamais l'ancien.
-- La contrainte de création différée (trg_carbon_check_member_distribution_override_creation_integrity,
-- ci-dessus) continue, indépendamment et sans changement, à vérifier que CE nouvel override (créé via
-- INSERT, proposal_type IN ('create','replace')) correspond exactement à sa proposition — les deux
-- contraintes différées se complètent, jamais redondantes : celle-ci vérifie le lien révocation ->
-- proposition -> nouvel override ; l'autre vérifie le lien nouvel override -> proposition -> valeurs
-- économiques approuvées.
CREATE OR REPLACE FUNCTION public.carbon_check_member_distribution_override_revocation_integrity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_prop RECORD;
    v_new_override_ok BOOLEAN;
BEGIN
    SELECT proposal_type, status, target_override_id, activated_override_id, aggregator_membership_id,
           organization_admin_approved_by, aggregator_admin_approved_by, operator_admin_approved_by
    INTO v_prop
    FROM public.member_distribution_override_proposals
    WHERE id = NEW.revocation_proposal_id;

    IF v_prop IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : revocation_proposal_id (%) ne référence aucune member_distribution_override_proposals existante.', NEW.revocation_proposal_id;
    END IF;

    -- Règles communes aux deux branches (revoke et replace).
    IF v_prop.proposal_type NOT IN ('replace', 'revoke') THEN
        RAISE EXCEPTION 'Intégrité violée : revocation_proposal_id (%) doit référencer une proposition de type replace ou revoke (type réel : %).', NEW.revocation_proposal_id, v_prop.proposal_type;
    END IF;
    IF v_prop.status <> 'activated' THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition de révocation/remplacement (%) doit être ''activated'' au COMMIT (statut réel : %).', NEW.revocation_proposal_id, v_prop.status;
    END IF;
    IF v_prop.target_override_id IS DISTINCT FROM NEW.id THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) doit cibler EXACTEMENT l''override révoqué (%) via target_override_id.', NEW.revocation_proposal_id, NEW.id;
    END IF;
    IF v_prop.aggregator_membership_id IS DISTINCT FROM NEW.aggregator_membership_id THEN
        RAISE EXCEPTION 'Intégrité violée : aggregator_membership_id de la proposition (%) et de l''override révoqué (%) doivent être identiques.', NEW.revocation_proposal_id, NEW.id;
    END IF;
    IF v_prop.organization_admin_approved_by IS NULL OR v_prop.aggregator_admin_approved_by IS NULL OR v_prop.operator_admin_approved_by IS NULL THEN
        RAISE EXCEPTION 'Intégrité violée : la proposition (%) doit porter les 3/3 approbations complètes au COMMIT.', NEW.revocation_proposal_id;
    END IF;

    -- Branche revoke : l'override révoqué EST l'objet activé par sa propre proposition.
    IF v_prop.proposal_type = 'revoke' THEN
        IF v_prop.activated_override_id IS DISTINCT FROM NEW.id THEN
            RAISE EXCEPTION 'Intégrité violée : la proposition de révocation (%) doit activer EXACTEMENT l''override qu''elle révoque (%).', NEW.revocation_proposal_id, NEW.id;
        END IF;
    END IF;

    -- Branche replace : la proposition doit activer un AUTRE override réel — le nouvel override créé
    -- par le même flux, jamais l'ancien qu'elle révoque, jamais un override étranger à cette proposition.
    IF v_prop.proposal_type = 'replace' THEN
        IF v_prop.activated_override_id IS NULL THEN
            RAISE EXCEPTION 'Intégrité violée : la proposition de remplacement (%) doit référencer un nouvel override via activated_override_id.', NEW.revocation_proposal_id;
        END IF;
        IF v_prop.activated_override_id = NEW.id THEN
            RAISE EXCEPTION 'Intégrité violée : la proposition de remplacement (%) ne peut pas activer l''override qu''elle révoque elle-même (%) — un remplacement doit produire un NOUVEL override distinct.', NEW.revocation_proposal_id, NEW.id;
        END IF;
        SELECT EXISTS (
            SELECT 1 FROM public.member_distribution_overrides mdo
            WHERE mdo.id = v_prop.activated_override_id
              AND mdo.proposal_id = NEW.revocation_proposal_id
              AND mdo.aggregator_membership_id = NEW.aggregator_membership_id
        ) INTO v_new_override_ok;
        IF NOT v_new_override_ok THEN
            RAISE EXCEPTION 'Intégrité violée : la proposition de remplacement (%) doit référencer, via activated_override_id, un member_distribution_overrides réel (%) dont le proposal_id est CETTE MÊME proposition et dont aggregator_membership_id est identique à celui de l''override révoqué.', NEW.revocation_proposal_id, v_prop.activated_override_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_carbon_check_member_distribution_override_revocation_integrity
    AFTER UPDATE OF revoked_at ON public.member_distribution_overrides
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    WHEN (NEW.revoked_at IS NOT NULL)
    EXECUTE FUNCTION public.carbon_check_member_distribution_override_revocation_integrity();

-- ────────────────────────────────────────────────────────────
-- 8. Trigger de coordination reserved -> voided sur credit_lots (§17 point 8)
--    Posé PAR 09 sur une table DE 08, sans modifier 08_carbon_lots_commercial_cycle.sql
--    ni recréer son trigger de machine à états.
-- ────────────────────────────────────────────────────────────

-- AJOUTÉ après la deuxième revue statique (point 3) : corrige un deadlock réel et démontrable entre
-- confirm_credit_sale()/add_credit_sale_lot() (verrouillent credit_sales PUIS credit_lots) et le cascade
-- d'annulation externe (qui, via credit_lots -> credit_sale_lots -> la synchronisation total_tco2e,
-- atteint réellement credit_sales — §17 point 16, corrigé, la version précédente affirmait à tort le
-- contraire). Ce trigger BEFORE, posé sur credit_issuances (table de 07, sans la modifier — même patron
-- que le trigger de coordination ci-dessous, posé sur credit_lots sans modifier 08), verrouille TOUTES
-- les ventes touchées par cette annulation, en ordre croissant d'id, AVANT que le trigger AFTER de 08
-- (déclenché par ce même UPDATE) ne verrouille le moindre lot — les triggers BEFORE ROW s'exécutent
-- systématiquement avant les triggers AFTER ROW du même événement, garantie native de PostgreSQL,
-- indépendante du nom des triggers. L'ordre global devient ainsi, sur TOUS les chemins, sans exception :
-- credit_issuances -> credit_sales (croissant) -> credit_lots -> credit_sale_lots, jamais l'inverse.
CREATE OR REPLACE FUNCTION public.carbon_lock_affected_credit_sales_before_external_cancellation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT DISTINCT cs.id
        FROM public.credit_sale_lots csl
        JOIN public.credit_lots cl ON cl.id = csl.credit_lot_id
        JOIN public.credit_sales cs ON cs.id = csl.credit_sale_id
        WHERE cl.credit_issuance_id = NEW.id AND csl.released_at IS NULL
        ORDER BY cs.id
    LOOP
        PERFORM 1 FROM public.credit_sales WHERE id = r.id FOR UPDATE;
    END LOOP;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_lock_affected_credit_sales_before_external_cancellation() IS
  'Point 3 (deuxième revue statique) : verrouille en ordre croissant d''id toutes les ventes draft ayant '
  'un lot actif rattaché à l''émission en cours d''annulation externe, AVANT que le cascade de 08 (trigger '
  'AFTER sur la même transition) ne verrouille les lots — ferme le cycle de verrous auparavant possible '
  'avec confirm_credit_sale()/add_credit_sale_lot() (sale -> lot).';

CREATE TRIGGER trg_carbon_lock_affected_credit_sales_before_external_cancellation
    BEFORE UPDATE OF issuance_status ON public.credit_issuances
    FOR EACH ROW
    WHEN (OLD.issuance_status IS DISTINCT FROM 'externally_cancelled' AND NEW.issuance_status = 'externally_cancelled')
    EXECUTE FUNCTION public.carbon_lock_affected_credit_sales_before_external_cancellation();

CREATE OR REPLACE FUNCTION public.carbon_release_credit_sale_lot_on_external_void()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_csl_id  UUID;
    v_sale_id UUID;
    v_actor   UUID;
BEGIN
    -- Corrigé après la deuxième revue statique (point 5) : v_actor = auth.uid(), tel que propagé par
    -- record_external_cancellation() (07) qui a déclenché cet UPDATE via le cascade de 08 — jamais NULL.
    -- 08 elle-même conserve l'acteur réel dans son propre cascade équivalent ; ce trigger fait désormais
    -- de même, au lieu de poser released_by/actor_id=NULL sur un raisonnement « acteur système » erroné.
    v_actor := auth.uid();

    SELECT id, credit_sale_id INTO v_csl_id, v_sale_id
    FROM public.credit_sale_lots WHERE credit_lot_id = NEW.id AND released_at IS NULL
    FOR UPDATE;

    IF v_csl_id IS NULL THEN
        RETURN NULL;  -- ce lot n'était rattaché à aucune vente active, rien à coordonner
    END IF;

    UPDATE public.credit_sale_lots
    SET released_at = clock_timestamp(), released_by = v_actor,
        release_reason = 'external_cancellation_cascade'
    WHERE id = v_csl_id;

    INSERT INTO public.carbon_business_events
        (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
    SELECT 'credit_sale_lot', v_csl_id, 'credit_sale_lot_released_by_external_cancellation', v_actor,
           cs.seller_organization_id, NEW.aggregator_id,
           jsonb_build_object('credit_sale_id', v_sale_id, 'credit_lot_id', NEW.id)
    FROM public.credit_sales cs WHERE cs.id = v_sale_id;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.carbon_release_credit_sale_lot_on_external_void() IS
  'Coordination §17 point 8 : quand le cascade de 08 (annulation externe de l''émission parente) fait '
  'passer un lot reserved -> voided, libère la ligne credit_sale_lots correspondante sans jamais annuler '
  'la vente elle-même (draft, jamais un cancelled implicite). Corrigé après la deuxième revue statique '
  '(point 5) : released_by/actor_id portent désormais l''acteur réel (auth.uid(), propagé depuis '
  'record_external_cancellation()), jamais NULL — cohérent avec le cascade équivalent de 08.';

CREATE TRIGGER trg_carbon_release_credit_sale_lot_on_external_void
    AFTER UPDATE OF commercial_status ON public.credit_lots
    FOR EACH ROW
    WHEN (OLD.commercial_status = 'reserved' AND NEW.commercial_status = 'voided')
    EXECUTE FUNCTION public.carbon_release_credit_sale_lot_on_external_void();

-- Cohérence structurelle credit_sale_lots actif <-> credit_lots.commercial_status — AJOUTÉE après la
-- première revue statique (point 15) : rien n'empêchait auparavant un chemin privilégié direct (par
-- exemple un UPDATE manuel sur credit_lots.commercial_status hors des RPC ci-dessous) de faire passer
-- un lot à 'reserved'/'sold' SANS ligne credit_sale_lots active correspondante (réservation orpheline),
-- ou de le faire revenir à 'available' alors qu'une ligne credit_sale_lots active le référence encore
-- (RPC de libération contournées). Cette garde BEFORE UPDATE, posée PAR 09 sur credit_lots (table de
-- 08, sans modifier 08_carbon_lots_commercial_cycle.sql ni son trigger de validité de transition —
-- même patron que le trigger de coordination ci-dessus), impose cette cohérence STRUCTURELLEMENT,
-- y compris contre ce chemin privilégié direct. Ordre d'exécution avec le trigger FSM de 08
-- (trg_carbon_credit_lots_before_update, alphabétiquement antérieur) : la validité de la transition
-- est vérifiée d'abord, la cohérence croisée ensuite — les deux doivent passer.
CREATE OR REPLACE FUNCTION public.carbon_guard_credit_lots_sale_consistency()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.commercial_status IN ('reserved', 'sold') AND OLD.commercial_status <> NEW.commercial_status THEN
        IF NOT EXISTS (SELECT 1 FROM public.credit_sale_lots WHERE credit_lot_id = NEW.id AND released_at IS NULL) THEN
            RAISE EXCEPTION 'Transition vers % refusée pour le lot % : aucune ligne credit_sale_lots active ne référence ce lot (cohérence structurelle §17 point 8/15, corrigée après la première revue statique — utiliser add_credit_sale_lot()).', NEW.commercial_status, NEW.id;
        END IF;
    ELSIF NEW.commercial_status = 'available' AND OLD.commercial_status = 'reserved' THEN
        IF EXISTS (SELECT 1 FROM public.credit_sale_lots WHERE credit_lot_id = NEW.id AND released_at IS NULL) THEN
            RAISE EXCEPTION 'Transition vers available refusée pour le lot % : une ligne credit_sale_lots active référence encore ce lot (utiliser release_credit_sale_lot()/cancel_credit_sale() pour la clore d''abord).', NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_credit_lots_sale_consistency() IS
  'Cohérence structurelle §17 point 15 (ajoutée après la première revue statique) : un lot ne peut '
  'entrer reserved/sold que si une ligne credit_sale_lots active le référence déjà (insérée par '
  'add_credit_sale_lot() avant cet UPDATE), et ne peut revenir available que si aucune ligne active ne '
  'le référence plus (release_credit_sale_lot()/cancel_credit_sale() doivent l''avoir close en premier) '
  '— bloque tout contournement direct des RPC, y compris un UPDATE privilégié.';

CREATE TRIGGER trg_carbon_guard_credit_lots_sale_consistency
    BEFORE UPDATE OF commercial_status ON public.credit_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_credit_lots_sale_consistency();

-- ────────────────────────────────────────────────────────────
-- 9. RPC — cycle de vie de la vente (§17 points 7bis/8/9/14)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_credit_sale(
    p_seller_organization_id UUID, p_price_per_tco2e NUMERIC, p_buyer_reference TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID;
    v_id    UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    IF NOT (COALESCE(public.is_org_admin(p_seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false)) THEN
        RAISE EXCEPTION 'Organisation introuvable ou accès refusé.';
    END IF;

    INSERT INTO public.credit_sales (seller_organization_id, currency, price_per_tco2e, buyer_reference)
    VALUES (p_seller_organization_id, 'CAD', p_price_per_tco2e, p_buyer_reference)
    RETURNING id INTO v_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, payload)
    VALUES ('credit_sale', v_id, 'credit_sale_created', v_actor, p_seller_organization_id,
            jsonb_build_object('price_per_tco2e', p_price_per_tco2e, 'buyer_reference', p_buyer_reference));

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_credit_sale_lot(p_credit_sale_id UUID, p_credit_lot_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        UUID;
    v_issuance_id  UUID;
    v_sale_status  TEXT;
    v_seller_org   UUID;
    v_lot_status   TEXT;
    v_aggregator   UUID;
    v_new_id       UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Ordre de verrous — REVU après la deuxième revue statique (point 3) : credit_issuances (parent du
    -- lot) d'abord, puis credit_sales, puis credit_lots — symétrique à l'ordre désormais retenu côté
    -- cascade externe (trg_carbon_lock_affected_credit_sales_before_external_cancellation, ci-dessous,
    -- verrouille les ventes concernées avant que le cascade de 08 ne verrouille les lots) : ferme le
    -- cycle de verrous auparavant possible entre confirm_credit_sale()/add_credit_sale_lot() (sale->lot)
    -- et le cascade externe (qui atteint réellement credit_sales via la synchronisation total_tco2e,
    -- §17 point 16, corrigé). Verrouiller l'émission ici, avant même credit_sales, ferme aussi la
    -- fenêtre TOCTOU entre la vérification du statut de l'émission (trigger BEFORE INSERT de
    -- credit_sale_lots, point 2) et la réservation effective du lot.
    -- Corrigé après la troisième revue statique (point 6, fuite D13) : ce premier lookup RESTE bare
    -- (aucun message levé ici) — il sert UNIQUEMENT à connaître l'émission parente pour la verrouiller
    -- tôt (ordre de verrous ci-dessus), jamais à distinguer « introuvable » de la suite. v_issuance_id
    -- restant NULL si le lot n'existe pas, le verrou suivant est simplement sauté (rien à verrouiller) ;
    -- le VRAI message d'erreur, unique, n'est levé que plus bas, une fois v_seller_org connu, en même
    -- temps que la vérification de pertinence — jamais avant.
    SELECT credit_issuance_id INTO v_issuance_id FROM public.credit_lots WHERE id = p_credit_lot_id;
    IF v_issuance_id IS NOT NULL THEN
        PERFORM 1 FROM public.credit_issuances WHERE id = v_issuance_id FOR UPDATE;
    END IF;

    SELECT status, seller_organization_id INTO v_sale_status, v_seller_org
    FROM public.credit_sales
    WHERE id = p_credit_sale_id
      AND (COALESCE(public.is_org_admin(seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;
    IF v_sale_status IS NULL THEN RAISE EXCEPTION 'Vente introuvable ou accès refusé.'; END IF;
    IF v_sale_status <> 'draft' THEN RAISE EXCEPTION 'Vente % non draft (statut réel : %).', p_credit_sale_id, v_sale_status; END IF;
    -- Revalidation de l'opérateur actif tant que draft (point 10, défense en profondeur — verrou final à confirm_credit_sale()).
    IF NOT COALESCE(public.is_platform_operator(v_seller_org), false) THEN
        RAISE EXCEPTION 'Opération refusée : seller_organization_id (%) n''est plus l''opérateur METALTRACE actif.', v_seller_org;
    END IF;

    -- Corrigé après la troisième revue statique (point 6, fuite D13) : la version précédente
    -- distinguait « credit_lot_id introuvable » (lookup bare, ci-dessus) d'un lot RÉEL mais dont
    -- aucune source de l'émission parente n'a un mandat dont l'opérateur correspond au vendeur figé de
    -- la vente (mismatched sources, alors détecté seulement par le trigger BEFORE INSERT, point 2, une
    -- fois l'INSERT tenté) — deux messages distincts permettaient à un admin autorisé sur SA PROPRE
    -- vente de sonder n'importe quel UUID de lot appartenant à une organisation totalement étrangère et
    -- d'apprendre s'il existe. Fusionné en une seule requête (existence + pertinence pour CE vendeur
    -- dans le même WHERE), message générique unique. Le statut 'available'/'reserved' etc. reste une
    -- information distincte et légitime (le lot est déjà pertinent pour ce vendeur), levée plus bas par
    -- le trigger BEFORE INSERT sans changement.
    SELECT cl.commercial_status, cl.aggregator_id INTO v_lot_status, v_aggregator
    FROM public.credit_lots cl
    WHERE cl.id = p_credit_lot_id
      AND EXISTS (
          SELECT 1 FROM public.credit_issuance_sources cis
          JOIN public.carbon_commercialization_mandates m ON m.id = cis.commercialization_mandate_id
          WHERE cis.credit_issuance_id = cl.credit_issuance_id AND m.operator_organization_id = v_seller_org
      )
    FOR UPDATE;
    IF v_lot_status IS NULL THEN RAISE EXCEPTION 'credit_lot_id (%) introuvable ou accès refusé.', p_credit_lot_id; END IF;

    -- L'INSERT (trigger BEFORE INSERT) revalide available/issued/seller-match/draft ;
    -- ce SELECT ... FOR UPDATE ci-dessus sérialise déjà les appels concurrents sur ce lot.
    INSERT INTO public.credit_sale_lots (credit_sale_id, credit_lot_id)
    VALUES (p_credit_sale_id, p_credit_lot_id)
    RETURNING id INTO v_new_id;

    -- credit_lots.commercial_status -> 'reserved' désormais posé STRUCTURELLEMENT par le trigger
    -- trg_carbon_sync_credit_lot_status_on_sale_lot_insert (point 2) — plus d'UPDATE manuel ici.

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
    VALUES ('credit_lot', p_credit_lot_id, 'credit_lot_reserved', v_actor, v_seller_org, v_aggregator,
            jsonb_build_object('credit_sale_id', p_credit_sale_id, 'credit_sale_lot_id', v_new_id));

    RETURN v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_credit_sale_lot(p_credit_sale_lot_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       UUID;
    v_sale_id     UUID;
    v_lot_id      UUID;
    v_sale_status TEXT;
    v_seller_org  UUID;
    v_aggregator  UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'p_reason est requis.'; END IF;

    -- Corrigé après la deuxième revue statique (point 9, fuite de type D13) : la version précédente
    -- cherchait d'abord la ligne credit_sale_lots par id SEUL (sans vérifier l'autorisation), puis
    -- l'autorisation sur la vente séparément — un outsider recevait un message DIFFÉRENT selon que l'UUID
    -- fourni existe (« Vente introuvable ou accès refusé ») ou non (« Ligne credit_sale_lots introuvable
    -- ou déjà libérée »), révélant l'existence d'un UUID auquel il n'a pas accès. Fusionné en une seule
    -- requête (jointure + autorisation dans le WHERE), message générique unique quelle que soit la cause.
    SELECT csl.credit_sale_id, csl.credit_lot_id, cs.status, cs.seller_organization_id
    INTO v_sale_id, v_lot_id, v_sale_status, v_seller_org
    FROM public.credit_sale_lots csl
    JOIN public.credit_sales cs ON cs.id = csl.credit_sale_id
    WHERE csl.id = p_credit_sale_lot_id AND csl.released_at IS NULL
      AND (COALESCE(public.is_org_admin(cs.seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE OF cs;
    IF v_sale_id IS NULL THEN RAISE EXCEPTION 'Ligne credit_sale_lots introuvable, déjà libérée, ou accès refusé.'; END IF;
    IF v_sale_status <> 'draft' THEN RAISE EXCEPTION 'Libération refusée : la vente % n''est pas draft.', v_sale_id; END IF;
    -- Revalidation de l'opérateur actif tant que draft (point 10, défense en profondeur).
    IF NOT COALESCE(public.is_platform_operator(v_seller_org), false) THEN
        RAISE EXCEPTION 'Opération refusée : seller_organization_id (%) n''est plus l''opérateur METALTRACE actif.', v_seller_org;
    END IF;

    SELECT aggregator_id INTO v_aggregator FROM public.credit_lots WHERE id = v_lot_id FOR UPDATE;

    UPDATE public.credit_sale_lots
    SET released_at = clock_timestamp(), released_by = v_actor, release_reason = p_reason
    WHERE id = p_credit_sale_lot_id;

    -- credit_lots.commercial_status -> 'available' désormais posé STRUCTURELLEMENT par le trigger
    -- trg_carbon_sync_credit_lot_status_on_sale_lot_release (point 2) — plus d'UPDATE manuel ici.

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
    VALUES ('credit_sale_lot', p_credit_sale_lot_id, 'credit_sale_lot_released', v_actor, v_seller_org, v_aggregator,
            jsonb_build_object('credit_sale_id', v_sale_id, 'credit_lot_id', v_lot_id, 'reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION public.add_credit_sale_cost(
    p_credit_sale_id UUID, p_cost_type TEXT, p_amount NUMERIC, p_description TEXT DEFAULT NULL, p_beneficiary TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor      UUID;
    v_seller_org UUID;
    v_new_id     UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    SELECT seller_organization_id INTO v_seller_org
    FROM public.credit_sales
    WHERE id = p_credit_sale_id
      AND (COALESCE(public.is_org_admin(seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;
    IF v_seller_org IS NULL THEN RAISE EXCEPTION 'Vente introuvable ou accès refusé.'; END IF;
    -- Revalidation de l'opérateur actif tant que draft (point 10) : add_credit_sale_cost() n'opère que
    -- sur des ventes draft (fenêtre d'écriture de credit_sale_costs, §17 point 3) — même défense en profondeur.
    IF NOT COALESCE(public.is_platform_operator(v_seller_org), false) THEN
        RAISE EXCEPTION 'Opération refusée : seller_organization_id (%) n''est plus l''opérateur METALTRACE actif.', v_seller_org;
    END IF;

    INSERT INTO public.credit_sale_costs (credit_sale_id, cost_type, description, amount, currency, beneficiary)
    VALUES (p_credit_sale_id, p_cost_type, p_description, p_amount, 'CAD', p_beneficiary)
    RETURNING id INTO v_new_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, payload)
    VALUES ('credit_sale_cost', v_new_id, 'credit_sale_cost_recorded', v_actor, v_seller_org,
            jsonb_build_object('credit_sale_id', p_credit_sale_id, 'cost_type', p_cost_type, 'amount', p_amount));

    RETURN v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_credit_sale(p_credit_sale_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       UUID;
    v_sale_status TEXT;
    v_seller_org  UUID;
    r             RECORD;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'p_reason est requis.'; END IF;

    SELECT status, seller_organization_id INTO v_sale_status, v_seller_org
    FROM public.credit_sales
    WHERE id = p_credit_sale_id
      AND (COALESCE(public.is_org_admin(seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;
    IF v_sale_status IS NULL THEN RAISE EXCEPTION 'Vente introuvable ou accès refusé.'; END IF;
    IF v_sale_status <> 'draft' THEN RAISE EXCEPTION 'Annulation refusée : la vente % n''est pas draft (statut réel : %).', p_credit_sale_id, v_sale_status; END IF;
    -- Revalidation de l'opérateur actif tant que draft (point 10, défense en profondeur).
    IF NOT COALESCE(public.is_platform_operator(v_seller_org), false) THEN
        RAISE EXCEPTION 'Opération refusée : seller_organization_id (%) n''est plus l''opérateur METALTRACE actif.', v_seller_org;
    END IF;

    -- credit_lots.commercial_status -> 'available' désormais posé STRUCTURELLEMENT par le trigger
    -- trg_carbon_sync_credit_lot_status_on_sale_lot_release (point 2) pour chaque ligne libérée ici —
    -- plus d'UPDATE manuel dans cette boucle.
    FOR r IN SELECT id, credit_lot_id FROM public.credit_sale_lots WHERE credit_sale_id = p_credit_sale_id AND released_at IS NULL ORDER BY credit_lot_id LOOP
        UPDATE public.credit_sale_lots SET released_at = clock_timestamp(), released_by = v_actor, release_reason = 'sale_cancelled' WHERE id = r.id;
    END LOOP;

    UPDATE public.credit_sales
    SET status = 'cancelled', cancelled_at = clock_timestamp(), cancelled_by = v_actor, cancel_reason = p_reason
    WHERE id = p_credit_sale_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, payload)
    VALUES ('credit_sale', p_credit_sale_id, 'credit_sale_cancelled', v_actor, v_seller_org, jsonb_build_object('reason', p_reason));
END;
$$;

-- compute_credit_sale_allocations() — interne, appelée uniquement par
-- confirm_credit_sale() (§17 point 13), jamais exposée directement (REVOKE
-- ALL en section 11, même patron que les fonctions de trigger).
CREATE OR REPLACE FUNCTION public.compute_credit_sale_allocations(p_credit_sale_id UUID, p_actor_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_sale             RECORD;
    v_pair             RECORD;
    v_total_weighted   NUMERIC(24,8) := 0;
    v_sum_gross        NUMERIC(14,2) := 0;
    v_sum_tco2e        NUMERIC(14,4) := 0;
    v_max_tco2e_org    UUID;
    v_max_tco2e_agg    UUID;
    v_max_gross_org    UUID;
    v_max_gross_agg    UUID;
    v_remainder        NUMERIC(14,2);
    v_tco2e_remainder  NUMERIC(14,4);
    v_rule             RECORD;
    v_membership_id    UUID;
    v_fee_override     RECORD;
    v_reserve_override RECORD;
    v_weight_override  RECORD;
    v_fee_amount       NUMERIC(14,2);
    v_reserve_amount   NUMERIC(14,2);
    v_net_amount       NUMERIC(14,2);
    v_rule_snapshot    JSONB;
    v_alloc_revenue_id UUID;
    v_alloc_reserve_id UUID;
    v_alloc_fee_id     UUID;
BEGIN
    SELECT * INTO v_sale FROM public.credit_sales WHERE id = p_credit_sale_id;

    -- ─── Étape A : attribution carbone au prorata (§17 point 13 étape A) ───
    -- Table de travail portant, par paire (organization_id, aggregator_id) :
    -- l'attribution carbone (Étape A), puis le taux/poids effectif et le
    -- gross_amount résolus une seule fois (Étape B, PREMIÈRE passe), avant
    -- toute imputation de reliquat — élimine le bug d'un reliquat calculé
    -- contre une somme partielle en cours d'accumulation (revue interne
    -- avant transmission).
    CREATE TEMP TABLE _c09_pairs (
        organization_id UUID, aggregator_id UUID,
        allocated_tco2e NUMERIC(14,4) NOT NULL DEFAULT 0,
        calc_snapshot   JSONB NOT NULL DEFAULT '[]'::jsonb,
        distribution_rule_id UUID,
        membership_id   UUID,
        fee_pct         NUMERIC(5,2),
        reserve_pct     NUMERIC(5,2),
        weight_applied  NUMERIC(8,4),
        gross_amount    NUMERIC(14,2),
        fee_override_id     UUID,
        reserve_override_id UUID,
        weight_override_id  UUID,
        PRIMARY KEY (organization_id, aggregator_id)
    ) ON COMMIT DROP;

    FOR v_pair IN
        SELECT cis.organization_id, cl.aggregator_id, csl.credit_lot_id, cl.credit_issuance_id,
               cis.id AS issuance_source_id, cis.contributed_tco2e, ci.quantity_tco2e AS issuance_quantity_tco2e,
               csl.quantity_tco2e AS sale_lot_quantity_tco2e
        FROM public.credit_sale_lots csl
        JOIN public.credit_lots cl ON cl.id = csl.credit_lot_id
        JOIN public.credit_issuances ci ON ci.id = cl.credit_issuance_id
        JOIN public.credit_issuance_sources cis ON cis.credit_issuance_id = ci.id
        WHERE csl.credit_sale_id = p_credit_sale_id AND csl.released_at IS NULL
        ORDER BY cis.organization_id, cl.aggregator_id, csl.credit_lot_id
    LOOP
        DECLARE
            v_ratio      NUMERIC(24,10);
            v_attributed NUMERIC(14,4);
            v_elem       JSONB;
        BEGIN
            v_ratio := v_pair.contributed_tco2e / v_pair.issuance_quantity_tco2e;
            -- Corrigé après la QUATRIÈME revue statique (bloqueur 3) : TRUNC, jamais ROUND. ROUND peut
            -- arrondir CHAQUE part À LA HAUSSE, faisant dépasser leur somme le total réel avant même
            -- l'imputation du reliquat — le reliquat (calculé plus bas comme total - somme) devient alors
            -- NÉGATIF, et l'imputer à la paire porteuse peut produire un allocated_tco2e négatif pour
            -- cette paire (démontré : émission 0,0010, 10 sources de 0,0001 chacune, lot 0,0005 -> chaque
            -- prorata 0,00005 ROUND-arrondi à 0,0001 -> somme 0,0010 = total, mais dès qu'un seul terme
            -- arrondit à la hausse au-delà de la part exacte, la somme peut dépasser le total ; reliquat
            -- négatif observé sur ce cas exact en revue). TRUNC(...,4) tronque CHAQUE part VERS ZÉRO
            -- (jamais au-delà de sa valeur exacte), donc SUM(parts tronquées) <= total TOUJOURS, et le
            -- reliquat (total - somme tronquée) est structurellement >= 0 avant imputation — jamais négatif.
            v_attributed := TRUNC(v_pair.sale_lot_quantity_tco2e * v_ratio, 4);
            v_elem := jsonb_build_object(
                'credit_lot_id', v_pair.credit_lot_id, 'credit_issuance_id', v_pair.credit_issuance_id,
                'issuance_source_id', v_pair.issuance_source_id, 'source_contributed_tco2e', v_pair.contributed_tco2e,
                'issuance_quantity_tco2e', v_pair.issuance_quantity_tco2e, 'source_ratio', v_ratio,
                'sale_lot_quantity_tco2e', v_pair.sale_lot_quantity_tco2e, 'attributed_tco2e', v_attributed
            );
            INSERT INTO _c09_pairs (organization_id, aggregator_id, allocated_tco2e, calc_snapshot)
            VALUES (v_pair.organization_id, v_pair.aggregator_id, v_attributed, jsonb_build_array(v_elem))
            ON CONFLICT (organization_id, aggregator_id) DO UPDATE
                SET allocated_tco2e = _c09_pairs.allocated_tco2e + EXCLUDED.allocated_tco2e,
                    calc_snapshot = _c09_pairs.calc_snapshot || EXCLUDED.calc_snapshot;
        END;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM _c09_pairs) THEN
        RAISE EXCEPTION 'Aucune paire organisation/regroupement contributrice — vente % sans attribution possible.', p_credit_sale_id;
    END IF;

    -- Reliquat d'arrondi tCO2e (§17 point 12) : plus grande contribution, tie-break UUID croissant.
    -- CORRIGÉ après la première revue statique (point 7) : le porteur du reliquat est désigné par la
    -- PAIRE (organization_id, aggregator_id), jamais par organization_id seul — une même organisation
    -- membre de DEUX regroupements dans la même vente a deux lignes distinctes dans _c09_pairs ; sans
    -- ce correctif, l'UPDATE ci-dessous aurait touché les DEUX lignes (même organization_id), imputant
    -- le reliquat deux fois.
    -- Corrigé après la troisième revue statique (point 5) : aggregator_id ASC ajouté comme TROISIÈME
    -- niveau de tri, ici ET pour le reliquat financier plus bas (même ORDER BY exactement) — sans lui,
    -- deux paires PARTAGEANT la même organization_id (même organisation, deux regroupements
    -- différents) avec un allocated_tco2e ex aequo au sommet n'étaient pas départagées de façon
    -- déterministe (organization_id ASC seul ne les distingue pas), laissant Postgres choisir une ligne
    -- arbitraire — jamais reproductible, contrairement à l'exigence du point 12/§17 (« déterministe,
    -- reproductible »).
    SELECT sum(allocated_tco2e) INTO v_sum_tco2e FROM _c09_pairs;
    SELECT organization_id, aggregator_id INTO v_max_tco2e_org, v_max_tco2e_agg FROM _c09_pairs
    ORDER BY allocated_tco2e DESC, organization_id ASC, aggregator_id ASC LIMIT 1;
    v_tco2e_remainder := v_sale.total_tco2e - v_sum_tco2e;
    UPDATE _c09_pairs SET allocated_tco2e = allocated_tco2e + v_tco2e_remainder
    WHERE organization_id = v_max_tco2e_org AND aggregator_id = v_max_tco2e_agg;

    -- ─── Étape B, première passe : résout la règle/override effectif de
    -- chaque paire et calcule un gross_amount brut (non encore corrigé du
    -- reliquat) — accumule le total pondéré ET la somme brute des gross.
    FOR v_pair IN SELECT * FROM _c09_pairs LOOP
        SELECT id, platform_fee_pct, reserve_pct, default_weight INTO v_rule
        FROM public.distribution_rules
        WHERE aggregator_id = v_pair.aggregator_id
          AND effective_from <= v_sale.confirmed_at AND (effective_to IS NULL OR effective_to > v_sale.confirmed_at);
        IF v_rule.id IS NULL THEN
            RAISE EXCEPTION 'Aucune distribution_rule active pour le regroupement % à l''instant de confirmation.', v_pair.aggregator_id;
        END IF;

        SELECT am.id INTO v_membership_id FROM public.aggregator_memberships am
        WHERE am.organization_id = v_pair.organization_id AND am.aggregator_id = v_pair.aggregator_id
          AND am.started_at <= v_sale.confirmed_at AND (am.ended_at IS NULL OR am.ended_at > v_sale.confirmed_at)
        LIMIT 1;

        -- Sélection temporelle des overrides — CORRIGÉE après la première revue statique (point 6) :
        -- l'état HISTORIQUE à confirmed_at, pas seulement « non révoqué maintenant » (revoked_at IS
        -- NULL seul aurait exclu à tort un override actif à confirmed_at mais révoqué depuis, cassant
        -- la reproductibilité d'un calcul historique). created_at <= confirmed_at (publié avant/à
        -- l'instant de confirmation) ET (revoked_at IS NULL OR revoked_at > confirmed_at) (pas encore
        -- révoqué à cet instant précis).
        -- Corrigé après la troisième revue statique (point 7) : effective_from/effective_until sont des
        -- colonnes DATE (jour calendaire de gouvernance, jamais un instant) ; confirmed_at::date seul
        -- dépendait implicitement du TimeZone GUC de la session/connexion courante (UTC par défaut sur
        -- Supabase, mais jamais garanti ni documenté) — deux connexions avec des TimeZone différents
        -- auraient pu résoudre un jour calendaire DIFFÉRENT pour la même vente près de minuit, cassant
        -- la reproductibilité du calcul. Fuseau contractuel figé au §17 : America/Toronto (marché visé
        -- par ce MVP) — converti EXPLICITEMENT via AT TIME ZONE, jamais un cast implicite dépendant de
        -- la session.
        v_fee_override := NULL;
        SELECT id, override_value INTO v_fee_override
        FROM public.member_distribution_overrides
        WHERE aggregator_membership_id = v_membership_id AND override_type = 'fee_pct'
          AND effective_from <= (v_sale.confirmed_at AT TIME ZONE 'America/Toronto')::date
          AND effective_until >= (v_sale.confirmed_at AT TIME ZONE 'America/Toronto')::date
          AND created_at <= v_sale.confirmed_at AND (revoked_at IS NULL OR revoked_at > v_sale.confirmed_at)
        ORDER BY created_at DESC LIMIT 1;

        v_reserve_override := NULL;
        SELECT id, override_value INTO v_reserve_override
        FROM public.member_distribution_overrides
        WHERE aggregator_membership_id = v_membership_id AND override_type = 'reserve_pct'
          AND effective_from <= (v_sale.confirmed_at AT TIME ZONE 'America/Toronto')::date
          AND effective_until >= (v_sale.confirmed_at AT TIME ZONE 'America/Toronto')::date
          AND created_at <= v_sale.confirmed_at AND (revoked_at IS NULL OR revoked_at > v_sale.confirmed_at)
        ORDER BY created_at DESC LIMIT 1;

        v_weight_override := NULL;
        SELECT id, override_value INTO v_weight_override
        FROM public.member_distribution_overrides
        WHERE aggregator_membership_id = v_membership_id AND override_type = 'weight_multiplier'
          AND effective_from <= (v_sale.confirmed_at AT TIME ZONE 'America/Toronto')::date
          AND effective_until >= (v_sale.confirmed_at AT TIME ZONE 'America/Toronto')::date
          AND created_at <= v_sale.confirmed_at AND (revoked_at IS NULL OR revoked_at > v_sale.confirmed_at)
        ORDER BY created_at DESC LIMIT 1;

        -- Durcissement des bornes après résolution des overrides (point 9) : fee+reserve effectifs <= 100.
        IF COALESCE(v_fee_override.override_value, v_rule.platform_fee_pct)
           + COALESCE(v_reserve_override.override_value, v_rule.reserve_pct) > 100 THEN
            RAISE EXCEPTION 'Bornes violées pour la paire (%, %) : fee_pct + reserve_pct effectifs dépassent 100 après résolution des overrides.',
                v_pair.organization_id, v_pair.aggregator_id;
        END IF;

        UPDATE _c09_pairs SET
            distribution_rule_id = v_rule.id,
            membership_id = v_membership_id,
            fee_pct = COALESCE(v_fee_override.override_value, v_rule.platform_fee_pct),
            reserve_pct = COALESCE(v_reserve_override.override_value, v_rule.reserve_pct),
            weight_applied = COALESCE(v_weight_override.override_value, v_rule.default_weight),
            fee_override_id = v_fee_override.id,
            reserve_override_id = v_reserve_override.id,
            weight_override_id = v_weight_override.id
        WHERE organization_id = v_pair.organization_id AND aggregator_id = v_pair.aggregator_id;
    END LOOP;

    SELECT sum(allocated_tco2e * weight_applied) INTO v_total_weighted FROM _c09_pairs;
    IF v_total_weighted IS NULL OR v_total_weighted <= 0 THEN
        RAISE EXCEPTION 'Total pondéré nul ou négatif pour la vente % — vérifier les poids appliqués.', p_credit_sale_id;
    END IF;

    -- Corrigé après la QUATRIÈME revue statique (bloqueur 3) : TRUNC, jamais ROUND — même raisonnement
    -- que l'attribution carbone ci-dessus (ROUND peut faire dépasser la somme des gross_amount le
    -- montant net réel, produisant un reliquat financier négatif ; démontré : 0,05 $ réparti à parts
    -- égales sur 10 paires -> chacune ROUND-arrondie à 0,01 $ -> somme 0,10 $ > 0,05 $ réel dans certains
    -- découpages, reliquat négatif observé en revue). TRUNC(...,2) garantit SUM(gross_amount tronqués)
    -- <= net_distributable_amount, donc le reliquat financier (calculé plus bas) est structurellement
    -- >= 0 avant imputation.
    UPDATE _c09_pairs SET gross_amount = TRUNC((allocated_tco2e * weight_applied / v_total_weighted) * v_sale.net_distributable_amount, 2);

    SELECT sum(gross_amount) INTO v_sum_gross FROM _c09_pairs;
    v_remainder := v_sale.net_distributable_amount - v_sum_gross;

    -- Détermine la paire porteuse du reliquat financier (plus grande allocated_tco2e, tie-break UUID) — §17 point 12.
    -- Corrigé après la troisième revue statique (point 5) : MÊME ORDER BY à trois niveaux exactement
    -- que le reliquat tCO2e ci-dessus (allocated_tco2e DESC, organization_id ASC, aggregator_id ASC) —
    -- les deux reliquats (tCO2e et argent) doivent désigner la MÊME paire porteuse par construction
    -- quand une seule paire domine, jamais un tri divergent qui les ferait accidentellement diverger.
    SELECT organization_id, aggregator_id INTO v_max_gross_org, v_max_gross_agg FROM _c09_pairs
    ORDER BY allocated_tco2e DESC, organization_id ASC, aggregator_id ASC LIMIT 1;
    UPDATE _c09_pairs SET gross_amount = gross_amount + v_remainder
    WHERE organization_id = v_max_gross_org AND aggregator_id = v_max_gross_agg;

    -- ─── Étape B, seconde passe : fee/reserve/net exacts + INSERT.
    -- CORRIGÉ après la première revue statique (point 1, décision d'architecture actée en §6) :
    -- reserve_amount porte désormais la RÉSERVE VÉRITABLE UNIQUEMENT (jamais le frais, qui n'y est plus
    -- fusionné) ; le frais de plateforme retenu devient une TROISIÈME ligne distincte
    -- (allocation_type='platform_fee'), jamais confondue avec 'reserve' ni avec
    -- credit_sale_costs.cost_type='platform_fee' (coût de la vente entière, prélevé en amont, §3).
    -- net_amount('carbon_revenue') = gross - fee - reserve (cascade de référence,
    -- distribution-calculator.ts, jamais modifiée) ; net_amount('reserve') = reserve véritable ;
    -- net_amount('platform_fee') = frais retenu. Conservation à trois composantes, exactement :
    --     SUM(net_amount) WHERE allocation_type IN ('carbon_revenue','reserve','platform_fee') = net_distributable_amount
    FOR v_pair IN SELECT * FROM _c09_pairs LOOP
        -- Corrigé après la QUATRIÈME revue statique (bloqueur 3) : TRUNC, jamais ROUND — un gross_amount
        -- minuscule avec fee_pct/reserve_pct proches de leur somme bornée à 100 pouvait, avec ROUND,
        -- produire fee_amount + reserve_amount > gross_amount (démontré : gross=0,01 $, fee=50 %,
        -- reserve=50 % -> ROUND(0,005,2)=0,01 $ pour CHACUN -> fee+reserve=0,02 $ > 0,01 $ -> net=-0,01 $,
        -- un montant net NÉGATIF, structurellement impossible à justifier). TRUNC(...,2) tronque CHAQUE
        -- composante VERS ZÉRO (jamais au-delà de sa valeur exacte) : fee_amount + reserve_amount <=
        -- gross_amount * (fee_pct + reserve_pct) / 100 <= gross_amount (borne fee_pct+reserve_pct <= 100
        -- déjà imposée plus haut), donc net_amount = gross - fee - reserve est structurellement >= 0.
        v_fee_amount := TRUNC(v_pair.gross_amount * v_pair.fee_pct / 100, 2);
        v_reserve_amount := TRUNC(v_pair.gross_amount * v_pair.reserve_pct / 100, 2);
        v_net_amount := v_pair.gross_amount - v_fee_amount - v_reserve_amount;

        -- rule_snapshot complet après la première revue statique (point 12) : les IDs exacts des
        -- overrides fee/reserve/weight effectivement appliqués (NULL si aucun override, règle générale
        -- du regroupement utilisée telle quelle), en plus des valeurs numériques résolues.
        v_rule_snapshot := jsonb_build_object(
            'rule_type', CASE WHEN v_pair.membership_id IS NOT NULL THEN 'aggregator_rule_with_possible_override' ELSE 'aggregator_rule' END,
            'parameters', jsonb_build_object(
                'distribution_rule_id', v_pair.distribution_rule_id, 'fee_applied_pct', v_pair.fee_pct,
                'reserve_applied_pct', v_pair.reserve_pct, 'weight_applied', v_pair.weight_applied,
                'aggregator_membership_id', v_pair.membership_id,
                'fee_override_id', v_pair.fee_override_id,
                'reserve_override_id', v_pair.reserve_override_id,
                'weight_override_id', v_pair.weight_override_id
            )
        );

        -- Colonnes d'audit du reliquat (§17 point 12) : non nulles
        -- UNIQUEMENT sur la ligne 'carbon_revenue' de la paire désignée
        -- porteuse (tco2e et/ou argent, indépendamment) — 0 partout ailleurs.
        -- Point 8 (troisième revue statique) : allocated_tco2e n'est plus renseigné QUE sur cette ligne
        -- 'carbon_revenue' — 'reserve' (ci-dessous) et 'platform_fee' (plus bas) sont désormais toutes
        -- deux purement financières (allocated_tco2e NULL, colonne absente de leur liste d'INSERT,
        -- alignée sur le CHECK credit_sale_allocations_tco2e_check). SUM(allocated_tco2e) sur les 3*N
        -- lignes d'une vente égale ainsi total_tco2e sans filtre allocation_type.
        INSERT INTO public.credit_sale_allocations (
            credit_sale_id, organization_id, aggregator_id, allocation_type, allocated_tco2e,
            tco2e_rounding_adjustment, gross_amount, fee_applied_pct, reserve_applied_pct, weight_applied,
            fee_amount, reserve_amount, net_amount, amount_rounding_adjustment,
            distribution_rule_id, rule_snapshot, calculation_snapshot
        ) VALUES (
            p_credit_sale_id, v_pair.organization_id, v_pair.aggregator_id, 'carbon_revenue', v_pair.allocated_tco2e,
            CASE WHEN v_pair.organization_id = v_max_tco2e_org AND v_pair.aggregator_id = v_max_tco2e_agg THEN v_tco2e_remainder ELSE 0 END,
            v_pair.gross_amount, v_pair.fee_pct, v_pair.reserve_pct, v_pair.weight_applied, v_fee_amount, v_reserve_amount,
            v_net_amount,
            CASE WHEN v_pair.organization_id = v_max_gross_org AND v_pair.aggregator_id = v_max_gross_agg THEN v_remainder ELSE 0 END,
            v_pair.distribution_rule_id, v_rule_snapshot, v_pair.calc_snapshot
        ) RETURNING id INTO v_alloc_revenue_id;

        INSERT INTO public.credit_sale_allocations (
            credit_sale_id, organization_id, aggregator_id, allocation_type, allocated_tco2e,
            gross_amount, fee_applied_pct, reserve_applied_pct, weight_applied, fee_amount, reserve_amount,
            net_amount, distribution_rule_id, rule_snapshot, calculation_snapshot
        ) VALUES (
            p_credit_sale_id, v_pair.organization_id, v_pair.aggregator_id, 'reserve', NULL,
            v_pair.gross_amount, v_pair.fee_pct, v_pair.reserve_pct, v_pair.weight_applied, 0, v_reserve_amount,
            v_reserve_amount, v_pair.distribution_rule_id, v_rule_snapshot, v_pair.calc_snapshot
        ) RETURNING id INTO v_alloc_reserve_id;

        INSERT INTO public.credit_sale_allocations (
            credit_sale_id, organization_id, aggregator_id, allocation_type, allocated_tco2e,
            gross_amount, fee_applied_pct, reserve_applied_pct, weight_applied, fee_amount, reserve_amount,
            net_amount, distribution_rule_id, rule_snapshot, calculation_snapshot
        ) VALUES (
            p_credit_sale_id, v_pair.organization_id, v_pair.aggregator_id, 'platform_fee', NULL,
            v_pair.gross_amount, v_pair.fee_pct, v_pair.reserve_pct, v_pair.weight_applied, v_fee_amount, 0,
            v_fee_amount, v_pair.distribution_rule_id, v_rule_snapshot, v_pair.calc_snapshot
        ) RETURNING id INTO v_alloc_fee_id;

        -- Événements corrigés après la première revue statique (point 11) : object_id = le VRAI id de
        -- CHAQUE ligne credit_sale_allocations insérée (jamais credit_sale_id, qui n'est pas l'objet
        -- décrit par object_type='credit_sale_allocation'), un événement par ligne, acteur et contexte
        -- complets (p_actor_id = l'acteur ayant déclenché confirm_credit_sale(), jamais NULL ici).
        INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
        VALUES
            ('credit_sale_allocation', v_alloc_revenue_id, 'credit_sale_allocation_recorded', p_actor_id, v_pair.organization_id, v_pair.aggregator_id,
             jsonb_build_object('credit_sale_id', p_credit_sale_id, 'allocation_type', 'carbon_revenue', 'gross_amount', v_pair.gross_amount, 'net_amount', v_net_amount)),
            ('credit_sale_allocation', v_alloc_reserve_id, 'credit_sale_allocation_recorded', p_actor_id, v_pair.organization_id, v_pair.aggregator_id,
             jsonb_build_object('credit_sale_id', p_credit_sale_id, 'allocation_type', 'reserve', 'net_amount', v_reserve_amount)),
            ('credit_sale_allocation', v_alloc_fee_id, 'credit_sale_allocation_recorded', p_actor_id, v_pair.organization_id, v_pair.aggregator_id,
             jsonb_build_object('credit_sale_id', p_credit_sale_id, 'allocation_type', 'platform_fee', 'net_amount', v_fee_amount));
    END LOOP;

    -- Vérification post-insertion de l'égalité comptable exacte (§17 point 9, révisée après la première
    -- revue statique, point 1) : SUM(gross_amount) = net_distributable_amount <=> SUM(net_amount) WHERE
    -- allocation_type IN ('carbon_revenue','reserve','platform_fee') = net_distributable_amount.
    PERFORM 1 FROM (SELECT sum(gross_amount) AS s FROM _c09_pairs) x WHERE x.s = v_sale.net_distributable_amount;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Égalité comptable rompue pour la vente % : SUM(gross_amount) après imputation du reliquat ne correspond pas exactement à net_distributable_amount.', p_credit_sale_id;
    END IF;
    PERFORM 1 FROM (
        SELECT sum(net_amount) AS s FROM public.credit_sale_allocations
        WHERE credit_sale_id = p_credit_sale_id AND allocation_type IN ('carbon_revenue','reserve','platform_fee')
    ) x WHERE x.s = v_sale.net_distributable_amount;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Égalité comptable rompue pour la vente % : SUM(net_amount) sur les trois composantes ne correspond pas exactement à net_distributable_amount.', p_credit_sale_id;
    END IF;

    DROP TABLE _c09_pairs;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_credit_sale(p_credit_sale_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor         UUID;
    v_sale          RECORD;
    v_total_costs   NUMERIC(14,2);
    v_gross         NUMERIC(14,2);
    v_net           NUMERIC(14,2);
    v_now           TIMESTAMPTZ;
    v_mismatched    INT;
    r               RECORD;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    SELECT * INTO v_sale FROM public.credit_sales
    WHERE id = p_credit_sale_id
      AND (COALESCE(public.is_org_admin(seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;
    IF v_sale.id IS NULL THEN RAISE EXCEPTION 'Vente introuvable ou accès refusé.'; END IF;
    IF v_sale.status <> 'draft' THEN RAISE EXCEPTION 'Confirmation refusée : la vente % n''est pas draft (statut réel : %).', p_credit_sale_id, v_sale.status; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.credit_sale_lots WHERE credit_sale_id = p_credit_sale_id AND released_at IS NULL) THEN
        RAISE EXCEPTION 'Confirmation refusée : la vente % n''a aucun lot actif.', p_credit_sale_id;
    END IF;

    -- Revalidation de l'opérateur actif — AJOUTÉE après la première revue statique (point 10) : le
    -- vendeur ne devient historique/figé qu'APRÈS confirmation (§17 point 10) ; tant que draft, un
    -- changement de désignation d'opérateur METALTRACE survenu depuis la création de la vente doit être
    -- détecté ici, verrou final avant le gel définitif — is_org_admin() seul (vérifié ci-dessus pour
    -- l'autorisation de l'acteur) ne garantit PAS que l'organisation soit toujours l'opérateur actif.
    IF NOT COALESCE(public.is_platform_operator(v_sale.seller_organization_id), false) THEN
        RAISE EXCEPTION 'Confirmation refusée : seller_organization_id (%) n''est plus l''opérateur METALTRACE actif.', v_sale.seller_organization_id;
    END IF;

    -- Réaffirmation de l'invariant vendeur figé pour chaque lot actif (défense en profondeur, §17 point 9 étape 4).
    SELECT count(*) INTO v_mismatched
    FROM public.credit_sale_lots csl
    JOIN public.credit_lots cl ON cl.id = csl.credit_lot_id
    JOIN public.credit_issuance_sources cis ON cis.credit_issuance_id = cl.credit_issuance_id
    JOIN public.carbon_commercialization_mandates m ON m.id = cis.commercialization_mandate_id
    WHERE csl.credit_sale_id = p_credit_sale_id AND csl.released_at IS NULL
      AND (m.operator_organization_id <> v_sale.seller_organization_id OR cl.commercial_status <> 'reserved');
    IF v_mismatched > 0 THEN
        RAISE EXCEPTION 'Confirmation refusée : au moins un lot de la vente % a perdu son invariant vendeur ou son statut reserved (concurrence avec un cascade externe ?).', p_credit_sale_id;
    END IF;

    -- Ajouté après la HUITIÈME revue statique (bloqueur 4) : verrou partagé sur la ligne
    -- platform_operators ACTIVE du seller — même ligne, même patron que designate_platform_operator()
    -- (FOR UPDATE, migration 06, inchangée) et que les nombreux FOR SHARE déjà posés en migration 07
    -- (huitième revue statique de 07). Sans ce verrou, is_platform_operator() ci-dessus (lecture SANS
    -- verrou, STABLE) pouvait laisser passer une désignation qu'une transaction
    -- designate_platform_operator() concurrente révoquerait et remplacerait ENTRE ce contrôle et la
    -- capture de confirmed_at plus bas, gelant définitivement seller_organization_id sur un opérateur
    -- qui ne serait plus, historiquement, l'opérateur actif à l'instant réel de confirmation. Le verrou
    -- est tenu jusqu'au COMMIT de cette fonction (FOR SHARE, compatible avec d'autres FOR SHARE
    -- concurrents mais incompatible avec le FOR UPDATE de designate_platform_operator()) — la défense
    -- en profondeur is_platform_operator() ci-dessus reste en place, elle ne remplace pas ce verrou.
    PERFORM 1 FROM public.platform_operators
    WHERE organization_id = v_sale.seller_organization_id AND revoked_at IS NULL
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Confirmation refusée : seller_organization_id (%) n''est plus l''opérateur METALTRACE actif (détecté sous verrou, transfert concurrent).', v_sale.seller_organization_id;
    END IF;

    -- Ajouté après la SIXIÈME revue statique (correction 1, bloqueur) : sérialisation explicite avec
    -- (a) l'activation d'une distribution_rule ou d'un member_distribution_override pour le(s) même(s)
    -- regroupement(s) (carbon_try_activate_distribution_rule_proposal() /
    -- carbon_try_activate_member_distribution_override_proposal(), verrouillent désormais le même
    -- aggregators.id AVANT de prendre leur propre timestamp d'activation) et (b) une fin d'adhésion
    -- concurrente (leave_aggregator(), migration 02 déjà appliquée — non modifiée ici — verrouille déjà
    -- la ligne aggregator_memberships via FOR UPDATE) et (c) une désignation d'opérateur concurrente
    -- (designate_platform_operator(), migration 06 déjà appliquée — non modifiée ici — verrouillée
    -- ci-dessus). Sans cette sérialisation, confirmed_at pouvait être fixé alors qu'une activation, une
    -- fin d'adhésion ou un transfert d'opérateur committé APRÈS coup, mais logiquement effectif AVANT
    -- confirmed_at, n'avait pas encore été pris en compte par compute_credit_sale_allocations()
    -- (appelée plus bas) ni par le seller_organization_id déjà gelé, produisant un rule_snapshot/
    -- calculation_snapshot/seller incohérent avec l'historique final une fois toutes les transactions
    -- committées. ORDRE GLOBAL DES VERROUS COMPLET (documenté au §17, points 9bis/9ter) : (1)
    -- credit_sales (déjà verrouillée plus haut, FOR UPDATE) ; (2) platform_operators actif du seller,
    -- FOR SHARE (ci-dessus) ; (3) aggregators.id, tri ASCENDANT ; (4) aggregator_memberships.id, tri
    -- ASCENDANT — JAMAIS l'inverse, et cette fonction n'acquiert JAMAIS de verrou sur
    -- distribution_rule_proposals/member_distribution_override_proposals (acquis uniquement par les
    -- fonctions d'activation, jamais par confirm_credit_sale()). designate_platform_operator() n'acquiert
    -- jamais credit_sales/aggregators/aggregator_memberships — aucun cycle croisé n'est donc possible
    -- entre confirm_credit_sale() et designate_platform_operator(), ni avec les fonctions d'activation
    -- (preuve statique complète, §17 point 9ter).
    --
    -- (3) aggregators.id représentés par les lots actifs de la vente, verrouillés dans l'ordre croissant.
    FOR r IN
        SELECT DISTINCT cl.aggregator_id AS id
        FROM public.credit_sale_lots csl
        JOIN public.credit_lots cl ON cl.id = csl.credit_lot_id
        WHERE csl.credit_sale_id = p_credit_sale_id AND csl.released_at IS NULL
        ORDER BY cl.aggregator_id
    LOOP
        PERFORM 1 FROM public.aggregators WHERE id = r.id FOR UPDATE;
    END LOOP;

    -- (4) aggregator_memberships ACTIVES (ended_at IS NULL) couvrant chaque paire (organisation
    -- contributrice, regroupement) de la vente, verrouillées dans l'ordre croissant de leur id — seule
    -- une ligne ACTIVE peut encore être modifiée par un leave_aggregator() concurrent (une ligne déjà
    -- historique/ended_at est immuable, migration 02, aucun verrou nécessaire sur celle-ci). C'est
    -- aussi CETTE boucle que join_aggregator() (CREATE OR REPLACE par 09, §17 point 9bis) ne peut
    -- jamais faire concurrence directement (il n'existe pas encore de ligne à verrouiller pour une
    -- NOUVELLE adhésion) — sa coordination passe entièrement par le verrou (3) aggregators.id, partagé
    -- avec cette fonction.
    FOR r IN
        SELECT DISTINCT am.id
        FROM public.credit_sale_lots csl
        JOIN public.credit_lots cl ON cl.id = csl.credit_lot_id
        JOIN public.credit_issuances ci ON ci.id = cl.credit_issuance_id
        JOIN public.credit_issuance_sources cis ON cis.credit_issuance_id = ci.id
        JOIN public.aggregator_memberships am
          ON am.organization_id = cis.organization_id AND am.aggregator_id = cl.aggregator_id AND am.ended_at IS NULL
        WHERE csl.credit_sale_id = p_credit_sale_id AND csl.released_at IS NULL
        ORDER BY am.id
    LOOP
        PERFORM 1 FROM public.aggregator_memberships WHERE id = r.id FOR UPDATE;
    END LOOP;

    v_now := clock_timestamp();
    SELECT COALESCE(SUM(amount), 0) INTO v_total_costs FROM public.credit_sale_costs WHERE credit_sale_id = p_credit_sale_id;
    v_gross := v_sale.total_tco2e * v_sale.price_per_tco2e;

    -- Durcissement économique ajouté après la deuxième revue statique (point 10) : rejet explicite AVANT
    -- le calcul si les coûts déclarés dépassent le montant brut — sans ce garde-fou,
    -- net_distributable_amount serait négatif dès la confirmation, un état que le CHECK de table
    -- (net_distributable_amount >= 0) empêcherait de toute façon, mais avec un message générique de
    -- contrainte plutôt qu'une explication actionnable pour l'opérateur.
    IF v_total_costs > v_gross THEN
        RAISE EXCEPTION 'Confirmation refusée : la somme des coûts déclarés (%) dépasse le montant brut (%) pour la vente %.', v_total_costs, v_gross, p_credit_sale_id;
    END IF;

    v_net := v_gross - v_total_costs;

    UPDATE public.credit_sales
    SET status = 'confirmed', confirmed_at = v_now, confirmed_by = v_actor, gross_amount = v_gross, net_distributable_amount = v_net
    WHERE id = p_credit_sale_id;

    PERFORM public.compute_credit_sale_allocations(p_credit_sale_id, v_actor);

    FOR r IN SELECT credit_lot_id FROM public.credit_sale_lots WHERE credit_sale_id = p_credit_sale_id AND released_at IS NULL ORDER BY credit_lot_id LOOP
        UPDATE public.credit_lots SET commercial_status = 'sold' WHERE id = r.credit_lot_id;
        INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
        SELECT 'credit_lot', r.credit_lot_id, 'credit_lot_sold', v_actor, v_sale.seller_organization_id, cl.aggregator_id,
               jsonb_build_object('credit_sale_id', p_credit_sale_id)
        FROM public.credit_lots cl WHERE cl.id = r.credit_lot_id;
    END LOOP;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, payload)
    VALUES ('credit_sale', p_credit_sale_id, 'credit_sale_confirmed', v_actor, v_sale.seller_organization_id,
            jsonb_build_object('gross_amount', v_gross, 'net_distributable_amount', v_net));
END;
$$;

CREATE OR REPLACE FUNCTION public.settle_credit_sale(p_credit_sale_id UUID, p_settlement_reference TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       UUID;
    v_sale_status TEXT;
    v_seller_org  UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    IF p_settlement_reference IS NULL OR btrim(p_settlement_reference) = '' THEN RAISE EXCEPTION 'p_settlement_reference est requis.'; END IF;

    SELECT status, seller_organization_id INTO v_sale_status, v_seller_org
    FROM public.credit_sales
    WHERE id = p_credit_sale_id
      AND (COALESCE(public.is_org_admin(seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;
    IF v_sale_status IS NULL THEN RAISE EXCEPTION 'Vente introuvable ou accès refusé.'; END IF;
    IF v_sale_status <> 'confirmed' THEN RAISE EXCEPTION 'Règlement refusé : la vente % n''est pas confirmed (statut réel : %).', p_credit_sale_id, v_sale_status; END IF;

    UPDATE public.credit_sales
    SET status = 'settled', settled_at = clock_timestamp(), settled_by = v_actor, settlement_reference = p_settlement_reference
    WHERE id = p_credit_sale_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, payload)
    VALUES ('credit_sale', p_credit_sale_id, 'credit_sale_settled', v_actor, v_seller_org,
            jsonb_build_object('settlement_reference', p_settlement_reference));
END;
$$;

CREATE OR REPLACE FUNCTION public.retire_credit_lot(p_credit_lot_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor      UUID;
    v_status     TEXT;
    v_aggregator UUID;
    v_seller_org UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'p_reason est requis.'; END IF;

    SELECT cl.commercial_status, cl.aggregator_id, cs.seller_organization_id
    INTO v_status, v_aggregator, v_seller_org
    FROM public.credit_lots cl
    JOIN public.credit_sale_lots csl ON csl.credit_lot_id = cl.id AND csl.released_at IS NULL
    JOIN public.credit_sales cs ON cs.id = csl.credit_sale_id
       AND (COALESCE(public.is_org_admin(cs.seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    WHERE cl.id = p_credit_lot_id
    FOR UPDATE OF cl;

    IF v_status IS NULL THEN RAISE EXCEPTION 'Lot introuvable ou accès refusé.'; END IF;
    IF v_status <> 'sold' THEN RAISE EXCEPTION 'Retrait refusé : le lot % n''est pas sold (statut réel : %).', p_credit_lot_id, v_status; END IF;

    UPDATE public.credit_lots SET commercial_status = 'retired' WHERE id = p_credit_lot_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
    VALUES ('credit_lot', p_credit_lot_id, 'credit_lot_retired', v_actor, v_seller_org, v_aggregator, jsonb_build_object('reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION public.add_credit_sale_adjustment(p_credit_sale_id UUID, p_amount NUMERIC, p_reason TEXT)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor      UUID;
    v_seller_org UUID;
    v_new_id     UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    SELECT seller_organization_id INTO v_seller_org
    FROM public.credit_sales
    WHERE id = p_credit_sale_id
      AND (COALESCE(public.is_org_admin(seller_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;
    IF v_seller_org IS NULL THEN RAISE EXCEPTION 'Vente introuvable ou accès refusé.'; END IF;

    INSERT INTO public.credit_sale_adjustments (credit_sale_id, amount, reason)
    VALUES (p_credit_sale_id, p_amount, p_reason)
    RETURNING id INTO v_new_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, payload)
    VALUES ('credit_sale_adjustment', v_new_id, 'credit_sale_adjustment_recorded', v_actor, v_seller_org,
            jsonb_build_object('credit_sale_id', p_credit_sale_id, 'amount', p_amount, 'reason', p_reason));

    RETURN v_new_id;
END;
$$;

-- Montant net effectif — jamais figé, toujours dérivé (§17 point 9).
-- SÉCURISÉ après la première revue statique (point 8) : cette fonction est SECURITY DEFINER et lit
-- credit_sales/credit_sale_adjustments en contournant la RLS de ces deux tables — sans un contrôle
-- explicite can_view_credit_sale() dans le corps de la fonction elle-même, tout utilisateur authentifié
-- disposant de l'EXECUTE (accordé à authenticated, section 13) pouvait obtenir les montants financiers
-- de N'IMPORTE QUELLE vente, y compris hors de son organisation/regroupement — fuite RLS réelle.
-- Reconvertie en plpgsql pour porter ce contrôle avant toute lecture.
CREATE OR REPLACE FUNCTION public.effective_net_distributable_amount(p_credit_sale_id UUID)
RETURNS NUMERIC(14,2)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_result NUMERIC(14,2);
BEGIN
    IF NOT COALESCE(public.can_view_credit_sale(p_credit_sale_id), false) THEN
        RAISE EXCEPTION 'Vente introuvable ou accès refusé.';
    END IF;
    SELECT cs.net_distributable_amount + COALESCE((SELECT SUM(amount) FROM public.credit_sale_adjustments WHERE credit_sale_id = p_credit_sale_id), 0)
    INTO v_result
    FROM public.credit_sales cs WHERE cs.id = p_credit_sale_id;
    RETURN v_result;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 9bis. CREATE OR REPLACE public.join_aggregator() — sérialisation temporelle
-- (§17 point 9bis, HUITIÈME revue statique, bloqueur 3). Migration 02 NON MODIFIÉE : ce fichier
-- (09) recopie la définition RÉELLE actuelle (signature, autorisations, protections, événements,
-- SECURITY DEFINER/search_path, compatibilité avec le trigger organizations.aggregator_id — tous
-- inchangés) et lui ajoute UNIQUEMENT la coordination nécessaire, via CREATE OR REPLACE FUNCTION —
-- jamais en réécrivant 02_carbon_aggregator_memberships.sql. Même patron déjà appliqué ailleurs dans
-- ce document (une migration ultérieure pose un trigger ou remplace une RPC d'une migration
-- antérieure, sans toucher au fichier historique de cette migration).
--
-- DÉFAUT CORRIGÉ : aggregator_memberships.started_at/created_at portent DEFAULT now() (migration 02,
-- ligne inchangée) — now() est le timestamp de DÉBUT DE TRANSACTION, jamais l'instant réel
-- post-verrou. Course possible sans cette correction : (T1) une transaction JOIN démarre — now()
-- figé à T1 ; (T2) une confirmation démarre et verrouille aggregators.id ; (T3) la confirmation ne
-- voit pas le JOIN encore non committé, fixe confirmed_at ; (T4) JOIN obtient enfin son verrou et
-- committe avec started_at = T1 (antérieur à T3/confirmed_at, alors que l'adhésion n'était PAS
-- visible au calcul effectué à confirmed_at) — l'historique final affirmerait à tort que l'adhésion
-- était déjà active à confirmed_at.
--
-- CORRECTION : le MÊME verrou FOR UPDATE sur aggregators.id que confirm_credit_sale()/
-- carbon_try_activate_distribution_rule_proposal()/carbon_try_activate_member_distribution_
-- override_proposal() (§17 point 9bis) est acquis ICI AVANT toute capture de clock_timestamp() —
-- started_at/created_at sont désormais fournis EXPLICITEMENT à l'INSERT (jamais laissés au DEFAULT
-- now() de la colonne, qui resterait sinon figé à l'instant de début de transaction, AVANT
-- l'acquisition du verrou). L'index unique partiel (idx_aggregator_memberships_one_active_per_org,
-- migration 02, inchangé) reste la protection structurelle contre deux adhésions actives
-- concurrentes pour la même organisation — cette correction ne le remplace pas, elle coordonne
-- seulement started_at avec les autres opérations qui déterminent l'état économique effectif à un
-- confirmed_at donné.
--
-- CRITIQUE (DIXIÈME revue statique, ne jamais régresser le correctif de sécurité de
-- migration 03) : la définition RÉELLEMENT déployée de join_aggregator() n'est PAS celle de la
-- migration 02 d'origine (HISTORIQUE, VULNÉRABLE — `IF NOT (is_aggregator_admin(...) OR
-- is_platform_superadmin())`, sans COALESCE) mais celle CORRIGÉE par 03_fix_null_bypass_authorization.sql
-- (`IF NOT (COALESCE(is_aggregator_admin(p_aggregator_id), false) OR COALESCE(is_platform_superadmin(),
-- false))`) — is_platform_superadmin() renvoie NULL (jamais false) pour tout utilisateur authentifié
-- normal dont le JWT ne porte aucune clé app_metadata.role, et `IF NOT NULL` ne s'exécute jamais en
-- PL/pgSQL : sans les deux COALESCE, n'importe quel utilisateur authentifié aurait pu rejoindre
-- n'importe quel regroupement. Ce CREATE OR REPLACE recopie donc la définition POST-03 dans son
-- intégralité et n'y change QUE ce qui est strictement nécessaire à 09 (verrou aggregators.id FOR
-- UPDATE, clock_timestamp() après ce verrou, started_at/created_at explicites) — aucune autre
-- autorisation ni protection de 03 n'est retirée ou affaiblie.
--
-- PRÉVALIDATION (avant le CREATE OR REPLACE) : refuse de continuer si l'environnement réel ne
-- correspond pas à l'hypothèse ci-dessus (fonction existante, définition post-03 déjà en place) —
-- même patron que la prévalidation de 03 elle-même (section 0 de ce fichier).
DO $$
DECLARE
    v_def TEXT;
BEGIN
    IF to_regprocedure('public.join_aggregator(uuid,uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée (09, join_aggregator) : public.join_aggregator(uuid,uuid) introuvable — les migrations 02/03 ont-elles bien été appliquées ?';
    END IF;

    SELECT pg_get_functiondef('public.join_aggregator(uuid,uuid)'::regprocedure) INTO v_def;
    IF v_def NOT ILIKE '%COALESCE(public.is_aggregator_admin(p_aggregator_id), false)%'
       OR v_def NOT ILIKE '%COALESCE(public.is_platform_superadmin(), false)%' THEN
        RAISE EXCEPTION 'Prévalidation échouée (09, join_aggregator) : la définition actuellement déployée de public.join_aggregator(uuid,uuid) ne contient pas le correctif COALESCE de la migration 03 — la migration 03 a-t-elle bien été appliquée avant 09 ? 09 refuse de remplacer une définition dont elle ne peut pas confirmer qu''elle part de l''état sécurisé post-03.';
    END IF;

    RAISE NOTICE 'Prévalidation réussie (09, join_aggregator) : la définition actuellement déployée contient le correctif COALESCE de la migration 03.';
END $$;

CREATE OR REPLACE FUNCTION public.join_aggregator(
    p_organization_id UUID,
    p_aggregator_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_membership_id UUID;
    v_started_at    TIMESTAMPTZ;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- CONSERVÉ tel quel de la migration 03 (jamais la forme historique vulnérable de migration 02,
    -- sans COALESCE) : is_platform_superadmin() renvoie NULL, pas false, pour tout utilisateur
    -- authentifié dont le JWT ne porte aucune clé app_metadata.role — sans COALESCE(..., false),
    -- `IF NOT NULL` ne s'exécute jamais en PL/pgSQL.
    IF NOT (COALESCE(public.is_aggregator_admin(p_aggregator_id), false)
            OR COALESCE(public.is_platform_superadmin(), false)) THEN
        RAISE EXCEPTION 'Seul un administrateur du regroupement cible ou un super-administrateur peut ajouter une organisation à ce regroupement.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
        RAISE EXCEPTION 'p_organization_id ne correspond à aucune organisation existante.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.aggregators WHERE id = p_aggregator_id) THEN
        RAISE EXCEPTION 'p_aggregator_id ne correspond à aucun regroupement existant.';
    END IF;

    -- Pré-vérification explicite et lisible avant de tenter l'insertion —
    -- l'index unique partiel (idx_aggregator_memberships_one_active_per_org)
    -- reste le filet de sécurité structurel en cas de course concurrente.
    IF EXISTS (
        SELECT 1 FROM public.aggregator_memberships
        WHERE organization_id = p_organization_id AND ended_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Cette organisation a déjà une adhésion active à un regroupement — utilisez leave_aggregator() avant d''en rejoindre un autre.';
    END IF;

    -- Ajouté après la HUITIÈME revue statique (bloqueur 3) : verrou de coordination temporelle, AVANT
    -- toute capture d'instant — même ressource et même ordre global que confirm_credit_sale()/les deux
    -- fonctions carbon_try_activate_*() (§17 point 9bis). Cette fonction n'acquiert jamais de verrou
    -- sur aggregator_memberships elle-même (pure INSERT, aucune ligne pré-existante à verrouiller pour
    -- cette organisation puisque la pré-vérification ci-dessus vient de confirmer l'absence d'adhésion
    -- active).
    PERFORM 1 FROM public.aggregators WHERE id = p_aggregator_id FOR UPDATE;

    v_started_at := clock_timestamp();

    INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by, started_at, created_at)
    VALUES (p_organization_id, p_aggregator_id, auth.uid(), v_started_at, v_started_at)
    RETURNING id INTO v_membership_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
    VALUES ('aggregator_membership_started', 'aggregator_membership', v_membership_id, p_organization_id, p_aggregator_id, auth.uid(), NULL);

    RETURN v_membership_id;
END;
$$;

COMMENT ON FUNCTION public.join_aggregator(UUID, UUID) IS
  'Crée une adhésion active d''une organisation à un regroupement. Autorisée à '
  'COALESCE(is_aggregator_admin(p_aggregator_id), false) OR COALESCE(is_platform_superadmin(), false) '
  '(décision D1, migration 02, COALESCE ajouté par la migration 03 — bypass NULL corrigé, CONSERVÉ '
  'intégralement ici, jamais régressé vers la forme historique sans COALESCE). CREATE OR REPLACE par 09 '
  '(HUITIÈME revue statique, §17 point 9bis ; prévalidation/post-validation du maintien du correctif 03 '
  'ajoutées à la DIXIÈME revue statique) : started_at/created_at désormais capturés explicitement APRÈS '
  'acquisition du verrou aggregators.id, jamais le DEFAULT now() de la colonne — coordination temporelle '
  'avec confirm_credit_sale() et les activations de distribution_rule/member_distribution_override. '
  'Signature, autorisations (post-03) et événements identiques à la définition sécurisée actuellement '
  'déployée ; seuls le verrou aggregators.id et la capture explicite de started_at/created_at sont '
  'ajoutés par ce CREATE OR REPLACE.';

-- POST-VALIDATION (après le CREATE OR REPLACE) : confirme que le correctif COALESCE de la migration 03
-- est TOUJOURS présent dans la définition tout juste posée par 09 — même patron que la post-validation
-- de 03 elle-même. Si cette vérification échoue, la migration entière échoue (DO $$ ... RAISE EXCEPTION
-- $$ dans le corps d'une transaction de migration standard), avant tout COMMIT.
DO $$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef('public.join_aggregator(uuid,uuid)'::regprocedure) INTO v_def;
    IF v_def NOT ILIKE '%COALESCE(public.is_aggregator_admin(p_aggregator_id), false)%'
       OR v_def NOT ILIKE '%COALESCE(public.is_platform_superadmin(), false)%' THEN
        RAISE EXCEPTION 'Post-validation échouée (09, join_aggregator) : le CREATE OR REPLACE tout juste posé ne contient plus le correctif COALESCE de la migration 03 — régression de sécurité, migration refusée.';
    END IF;
    RAISE NOTICE 'Post-validation réussie (09, join_aggregator) : le correctif COALESCE de la migration 03 est toujours présent après le CREATE OR REPLACE de 09.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 10. RPC — gouvernance distribution_rules, double approbation (§17 points 4/14)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.propose_distribution_rule(
    p_aggregator_id UUID, p_platform_fee_pct NUMERIC, p_reserve_pct NUMERIC, p_default_weight NUMERIC DEFAULT 1.0
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  UUID;
    v_new_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    -- Corrigé après la première revue statique (point 3) : is_aggregator_primary_admin() remplace
    -- is_aggregator_admin() pour l'autorité économique du regroupement — is_aggregator_admin() matche
    -- n'importe quel admin actif (primary_admin OU co_admin), alors que §17 réserve cette autorité au
    -- seul primary_admin. Opérateur : substitution superadmin explicite (point 4).
    IF NOT (COALESCE(public.is_aggregator_primary_admin(p_aggregator_id), false)
            OR COALESCE(public.is_platform_operator_admin((SELECT organization_id FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1)), false)
            OR COALESCE(public.is_platform_superadmin(), false)) THEN
        RAISE EXCEPTION 'Regroupement introuvable ou accès refusé.';
    END IF;

    INSERT INTO public.distribution_rule_proposals (aggregator_id, platform_fee_pct, reserve_pct, default_weight)
    VALUES (p_aggregator_id, p_platform_fee_pct, p_reserve_pct, p_default_weight)
    RETURNING id INTO v_new_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, aggregator_id, payload)
    VALUES ('distribution_rule_proposal', v_new_id, 'distribution_rule_proposed', v_actor, p_aggregator_id,
            jsonb_build_object('platform_fee_pct', p_platform_fee_pct, 'reserve_pct', p_reserve_pct, 'default_weight', p_default_weight));

    RETURN v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_distribution_rule_as_aggregator_admin(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  UUID;
    v_prop   RECORD;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Corrigé après la première revue statique (point 3) : is_aggregator_primary_admin() — seul le
    -- primary_admin porte l'autorité économique d'approbation, jamais un co_admin (jamais substituable
    -- par le superadmin non plus, point 4 : la substitution superadmin ne vaut que pour l'opérateur).
    SELECT * INTO v_prop FROM public.distribution_rule_proposals
    WHERE id = p_proposal_id AND COALESCE(public.is_aggregator_primary_admin(aggregator_id), false)
    FOR UPDATE;
    IF v_prop.id IS NULL THEN RAISE EXCEPTION 'Proposition introuvable ou accès refusé.'; END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;
    IF v_prop.aggregator_admin_approved_by IS NOT NULL THEN RAISE EXCEPTION 'Approbation déjà posée par un admin du regroupement.'; END IF;

    UPDATE public.distribution_rule_proposals
    SET aggregator_admin_approved_by = v_actor, aggregator_admin_approved_at = clock_timestamp()
    WHERE id = p_proposal_id;

    PERFORM public.carbon_try_activate_distribution_rule_proposal(p_proposal_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_distribution_rule_as_operator_admin(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor      UUID;
    v_prop       RECORD;
    v_operator   UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Corrigé après la première revue statique (point 4) : is_platform_operator_admin(active_operator)
    -- OR is_platform_superadmin() explicite — l'ancienne rédaction ne s'appuyait que sur
    -- is_platform_operator_admin() (qui contient déjà, en interne, un OR is_platform_superadmin(), mais
    -- STRICTEMENT gaté sur l'existence d'un opérateur actif) ; l'OR explicite ci-dessous garantit qu'un
    -- superadmin authentique conserve une voie d'action même dans le cas limite où v_operator serait
    -- NULL (aucun opérateur actif désigné). Ceci ne réintroduit PAS le contournement corrigé en migration
    -- 07 (correction 7) : v_operator est ici relu à l'instant présent (jamais une référence figée d'un
    -- opérateur passé), donc aucun risque qu'un superadmin agisse sur un opérateur désormais périmé.
    SELECT organization_id INTO v_operator FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1;
    SELECT * INTO v_prop FROM public.distribution_rule_proposals WHERE id = p_proposal_id FOR UPDATE;
    IF v_prop.id IS NULL
       OR NOT (COALESCE(public.is_platform_operator_admin(v_operator), false) OR COALESCE(public.is_platform_superadmin(), false)) THEN
        RAISE EXCEPTION 'Proposition introuvable ou accès refusé.';
    END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;
    IF v_prop.operator_admin_approved_by IS NOT NULL THEN RAISE EXCEPTION 'Approbation déjà posée par un admin opérateur.'; END IF;

    UPDATE public.distribution_rule_proposals
    SET operator_admin_approved_by = v_actor, operator_admin_approved_at = clock_timestamp()
    WHERE id = p_proposal_id;

    PERFORM public.carbon_try_activate_distribution_rule_proposal(p_proposal_id);
END;
$$;

-- Interne : active la proposition si les deux approbations sont posées
-- (dans quelque ordre) — ferme la version active existante, insère la
-- nouvelle version (§17 point 4).
CREATE OR REPLACE FUNCTION public.carbon_try_activate_distribution_rule_proposal(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_prop   RECORD;
    v_now    TIMESTAMPTZ;
    v_new_id UUID;
BEGIN
    SELECT * INTO v_prop FROM public.distribution_rule_proposals WHERE id = p_proposal_id FOR UPDATE;
    -- Ajouté après la SIXIÈME revue statique (correction 2) : vérifie explicitement les timestamps
    -- approved_at EN PLUS des approved_by (redondant avec le CHECK de pairage
    -- distribution_rule_proposals_*_pair_check ci-dessus, mais défense en profondeur — cette fonction
    -- ne doit jamais dépendre implicitement d'une contrainte de table pour rester correcte par elle-même).
    IF v_prop.status <> 'pending'
       OR v_prop.aggregator_admin_approved_by IS NULL OR v_prop.aggregator_admin_approved_at IS NULL
       OR v_prop.operator_admin_approved_by IS NULL OR v_prop.operator_admin_approved_at IS NULL THEN
        RETURN;  -- pas encore les deux approbations complètes, rien à activer
    END IF;

    -- Ajouté après la SIXIÈME revue statique (correction 1, bloqueur) : verrouille aggregators.id
    -- AVANT de prendre le timestamp d'activation — même resource que confirm_credit_sale() (ordre
    -- global documenté au §17, point 9bis). Le verrou sur la proposition (FOR UPDATE ci-dessus) est
    -- déjà tenu et est TOUJOURS acquis avant celui-ci dans cette fonction (ordre interne fixe, jamais
    -- l'inverse) ; confirm_credit_sale() n'acquiert jamais de verrou sur une ligne de proposition, donc
    -- aucun cycle croisé n'est possible entre les deux familles de fonctions.
    PERFORM 1 FROM public.aggregators WHERE id = v_prop.aggregator_id FOR UPDATE;

    v_now := clock_timestamp();
    UPDATE public.distribution_rules SET effective_to = v_now WHERE aggregator_id = v_prop.aggregator_id AND effective_to IS NULL;

    INSERT INTO public.distribution_rules (aggregator_id, platform_fee_pct, reserve_pct, default_weight, effective_from, proposal_id, created_by)
    VALUES (v_prop.aggregator_id, v_prop.platform_fee_pct, v_prop.reserve_pct, v_prop.default_weight, v_now, p_proposal_id, v_prop.proposed_by)
    RETURNING id INTO v_new_id;

    UPDATE public.distribution_rule_proposals SET status = 'activated', activated_distribution_rule_id = v_new_id WHERE id = p_proposal_id;

    -- Corrigé après la deuxième revue statique (point 4) : actor_id (l'approbateur dont l'approbation a
    -- déclenché cette activation, auth.uid() dans cette même transaction) désormais obligatoire —
    -- auparavant absent de cet événement.
    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, aggregator_id, payload)
    VALUES ('distribution_rule', v_new_id, 'distribution_rule_activated', auth.uid(), v_prop.aggregator_id,
            jsonb_build_object('proposal_id', p_proposal_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_distribution_rule_proposal(p_proposal_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor    UUID;
    v_prop     RECORD;
    v_operator UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'p_reason est requis.'; END IF;

    -- Corrigé après la première revue statique (points 3/4) : is_aggregator_primary_admin() (jamais
    -- co_admin) + is_platform_operator_admin(active_operator) OR is_platform_superadmin() explicite.
    SELECT organization_id INTO v_operator FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1;
    SELECT * INTO v_prop FROM public.distribution_rule_proposals WHERE id = p_proposal_id FOR UPDATE;
    IF v_prop.id IS NULL
       OR NOT (COALESCE(public.is_aggregator_primary_admin(v_prop.aggregator_id), false)
               OR COALESCE(public.is_platform_operator_admin(v_operator), false)
               OR COALESCE(public.is_platform_superadmin(), false)) THEN
        RAISE EXCEPTION 'Proposition introuvable ou accès refusé.';
    END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;

    UPDATE public.distribution_rule_proposals SET status = 'rejected', rejected_by = v_actor, rejected_at = clock_timestamp(), reject_reason = p_reason
    WHERE id = p_proposal_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, aggregator_id, payload)
    VALUES ('distribution_rule_proposal', p_proposal_id, 'distribution_rule_rejected', v_actor, v_prop.aggregator_id, jsonb_build_object('reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION public.withdraw_distribution_rule_proposal(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID;
    v_prop  RECORD;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    SELECT * INTO v_prop FROM public.distribution_rule_proposals WHERE id = p_proposal_id AND proposed_by = v_actor FOR UPDATE;
    IF v_prop.id IS NULL THEN RAISE EXCEPTION 'Proposition introuvable ou vous n''en êtes pas l''auteur.'; END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;

    UPDATE public.distribution_rule_proposals SET status = 'withdrawn' WHERE id = p_proposal_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, aggregator_id, payload)
    VALUES ('distribution_rule_proposal', p_proposal_id, 'distribution_rule_withdrawn', v_actor, v_prop.aggregator_id, '{}'::jsonb);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 11. RPC — gouvernance member_distribution_overrides, triple approbation
--     (§17 points 5/14) — create/replace/revoke, même mécanisme audité.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.propose_member_distribution_override(
    p_proposal_type TEXT, p_aggregator_membership_id UUID, p_target_override_id UUID DEFAULT NULL,
    p_override_type TEXT DEFAULT NULL, p_override_value NUMERIC DEFAULT NULL,
    p_effective_from DATE DEFAULT NULL, p_effective_until DATE DEFAULT NULL, p_revoke_reason TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor         UUID;
    v_org_id        UUID;
    v_aggregator_id UUID;
    v_new_id        UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Corrigé après la deuxième revue statique (point 9, fuite de type D13) : la version précédente
    -- cherchait d'abord l'adhésion par id SEUL (message « introuvable » si absente), puis vérifiait
    -- l'autorisation séparément (message « accès refusé » si présente mais non autorisée) — un outsider
    -- distinguait ainsi un UUID d'adhésion réel d'un UUID inventé. Fusionné en une seule requête (lookup +
    -- autorisation dans le même WHERE, première revue statique points 3/4 pour le détail des rôles),
    -- message générique unique.
    SELECT organization_id, aggregator_id INTO v_org_id, v_aggregator_id
    FROM public.aggregator_memberships
    WHERE id = p_aggregator_membership_id
      AND (COALESCE(public.is_org_admin(organization_id), false) OR COALESCE(public.is_aggregator_primary_admin(aggregator_id), false)
           OR COALESCE(public.is_platform_operator_admin((SELECT organization_id FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1)), false)
           OR COALESCE(public.is_platform_superadmin(), false));
    IF v_org_id IS NULL THEN RAISE EXCEPTION 'Adhésion introuvable ou accès refusé.'; END IF;

    -- Fermeture du trou cross-scope (point 5) : pour 'replace'/'revoke', target_override_id doit
    -- appartenir à CETTE MÊME aggregator_membership_id et être non révoqué — vérifié ici au dépôt de la
    -- proposition (best-effort ; revalidé sous verrou à l'activation, carbon_try_activate_member_
    -- distribution_override_proposal(), car l'état a pu changer entre le dépôt et la dernière approbation).
    IF p_proposal_type IN ('replace', 'revoke') THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.member_distribution_overrides
            WHERE id = p_target_override_id AND aggregator_membership_id = p_aggregator_membership_id AND revoked_at IS NULL
        ) THEN
            RAISE EXCEPTION 'target_override_id (%) introuvable, déjà révoqué, ou n''appartient pas à cette adhésion.', p_target_override_id;
        END IF;
    END IF;

    INSERT INTO public.member_distribution_override_proposals (
        proposal_type, aggregator_membership_id, target_override_id, override_type, override_value,
        proposed_effective_from, proposed_effective_until, revoke_reason
    ) VALUES (
        p_proposal_type, p_aggregator_membership_id, p_target_override_id, p_override_type, p_override_value,
        p_effective_from, p_effective_until, p_revoke_reason
    ) RETURNING id INTO v_new_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
    VALUES ('member_distribution_override_proposal', v_new_id, 'member_distribution_override_proposed', v_actor, v_org_id, v_aggregator_id,
            jsonb_build_object('proposal_type', p_proposal_type, 'aggregator_membership_id', p_aggregator_membership_id));

    RETURN v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_member_distribution_override_as_organization_admin(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  UUID;
    v_prop   RECORD;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Corrigé après la première revue statique (point 13) : SELECT p.*, autre_colonne INTO
    -- record_var, scalar_var mélangeait un RECORD complet (p.*) avec une colonne scalaire supplémentaire
    -- (am.organization_id) dans la même liste cible PL/pgSQL — pattern invalide/fragile. Corrigé en
    -- capturant TOUTES les colonnes nécessaires (y compris celle de la jointure) dans le seul RECORD v_prop,
    -- via un alias explicite, sans mélanger p.* avec une cible scalaire distincte.
    SELECT p.*, am.organization_id AS m_organization_id INTO v_prop
    FROM public.member_distribution_override_proposals p
    JOIN public.aggregator_memberships am ON am.id = p.aggregator_membership_id
    WHERE p.id = p_proposal_id AND COALESCE(public.is_org_admin(am.organization_id), false)
    FOR UPDATE OF p;
    IF v_prop.id IS NULL THEN RAISE EXCEPTION 'Proposition introuvable ou accès refusé.'; END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;
    IF v_prop.organization_admin_approved_by IS NOT NULL THEN RAISE EXCEPTION 'Approbation déjà posée par l''admin de l''organisation.'; END IF;

    UPDATE public.member_distribution_override_proposals
    SET organization_admin_approved_by = v_actor, organization_admin_approved_at = clock_timestamp()
    WHERE id = p_proposal_id;

    PERFORM public.carbon_try_activate_member_distribution_override_proposal(p_proposal_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_member_distribution_override_as_aggregator_admin(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID;
    v_prop  RECORD;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Corrigé après la première revue statique (point 3) : is_aggregator_primary_admin(), jamais co_admin.
    SELECT p.* INTO v_prop
    FROM public.member_distribution_override_proposals p
    JOIN public.aggregator_memberships am ON am.id = p.aggregator_membership_id
    WHERE p.id = p_proposal_id AND COALESCE(public.is_aggregator_primary_admin(am.aggregator_id), false)
    FOR UPDATE OF p;
    IF v_prop.id IS NULL THEN RAISE EXCEPTION 'Proposition introuvable ou accès refusé.'; END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;
    IF v_prop.aggregator_admin_approved_by IS NOT NULL THEN RAISE EXCEPTION 'Approbation déjà posée par l''admin du regroupement.'; END IF;

    UPDATE public.member_distribution_override_proposals
    SET aggregator_admin_approved_by = v_actor, aggregator_admin_approved_at = clock_timestamp()
    WHERE id = p_proposal_id;

    PERFORM public.carbon_try_activate_member_distribution_override_proposal(p_proposal_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_member_distribution_override_as_operator_admin(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor    UUID;
    v_prop     RECORD;
    v_operator UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Corrigé après la première revue statique (point 4) : OR is_platform_superadmin() explicite
    -- (même raisonnement que approve_distribution_rule_as_operator_admin ci-dessus).
    SELECT organization_id INTO v_operator FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1;
    SELECT * INTO v_prop FROM public.member_distribution_override_proposals WHERE id = p_proposal_id FOR UPDATE;
    IF v_prop.id IS NULL
       OR NOT (COALESCE(public.is_platform_operator_admin(v_operator), false) OR COALESCE(public.is_platform_superadmin(), false)) THEN
        RAISE EXCEPTION 'Proposition introuvable ou accès refusé.';
    END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;
    IF v_prop.operator_admin_approved_by IS NOT NULL THEN RAISE EXCEPTION 'Approbation déjà posée par un admin opérateur.'; END IF;

    UPDATE public.member_distribution_override_proposals
    SET operator_admin_approved_by = v_actor, operator_admin_approved_at = clock_timestamp()
    WHERE id = p_proposal_id;

    PERFORM public.carbon_try_activate_member_distribution_override_proposal(p_proposal_id);
END;
$$;

-- Interne : active dès que les 3 approbations sont posées (§17 point 5).
CREATE OR REPLACE FUNCTION public.carbon_try_activate_member_distribution_override_proposal(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_prop   RECORD;
    v_now    TIMESTAMPTZ;
    v_new_id UUID;
BEGIN
    SELECT * INTO v_prop FROM public.member_distribution_override_proposals WHERE id = p_proposal_id FOR UPDATE;
    -- Ajouté après la SIXIÈME revue statique (correction 2), symétrique à la fonction distribution_rule
    -- ci-dessus : vérifie explicitement les timestamps approved_at EN PLUS des approved_by (redondant
    -- avec le CHECK de pairage member_distribution_override_proposals_*_pair_check, mais défense en
    -- profondeur).
    IF v_prop.status <> 'pending'
       OR v_prop.organization_admin_approved_by IS NULL OR v_prop.organization_admin_approved_at IS NULL
       OR v_prop.aggregator_admin_approved_by IS NULL OR v_prop.aggregator_admin_approved_at IS NULL
       OR v_prop.operator_admin_approved_by IS NULL OR v_prop.operator_admin_approved_at IS NULL THEN
        RETURN;  -- pas encore les trois approbations complètes
    END IF;

    -- Ajouté après la SIXIÈME revue statique (correction 1, bloqueur) : verrouille aggregators.id
    -- (résolu via aggregator_membership_id) AVANT de prendre le timestamp d'activation/révocation —
    -- même resource et même ordre global que confirm_credit_sale() et
    -- carbon_try_activate_distribution_rule_proposal() (§17, point 9bis). Le verrou sur la proposition
    -- (FOR UPDATE ci-dessus) est déjà tenu et toujours acquis en premier dans cette fonction ; cette
    -- fonction n'acquiert jamais de verrou sur aggregator_memberships elle-même (seule sa FK
    -- aggregator_id, stable et non réécrite par leave_aggregator()/join_aggregator(), est lue ici).
    PERFORM 1 FROM public.aggregators WHERE id = (
        SELECT aggregator_id FROM public.aggregator_memberships WHERE id = v_prop.aggregator_membership_id
    ) FOR UPDATE;

    v_now := clock_timestamp();

    IF v_prop.proposal_type IN ('replace','revoke') THEN
        -- Revalidation sous verrou (point 5) : l'état a pu changer entre le dépôt de la proposition et
        -- la pose de la dernière approbation (TOCTOU) — target_override_id doit encore appartenir à
        -- cette même aggregator_membership_id et être encore non révoqué à cet instant précis.
        PERFORM 1 FROM public.member_distribution_overrides
        WHERE id = v_prop.target_override_id AND aggregator_membership_id = v_prop.aggregator_membership_id
          AND revoked_at IS NULL
        FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Activation refusée : target_override_id (%) n''appartient plus à cette adhésion ou a déjà été révoqué (conflit concurrent).', v_prop.target_override_id;
        END IF;

        -- Corrigé après la deuxième revue statique (point 4) : revoked_by doit être l'acteur de la
        -- DERNIÈRE approbation (celle qui déclenche cette activation, auth.uid() dans cette même
        -- transaction), jamais v_prop.proposed_by (l'auteur de la PROPOSITION de révocation, pas
        -- forcément celui qui l'a fait aboutir) — revoked_at=v_now représente l'instant de l'activation
        -- finale, revoked_by doit en refléter l'acteur réel.
        UPDATE public.member_distribution_overrides
        SET revoked_at = v_now, revoked_by = auth.uid(), revocation_proposal_id = p_proposal_id
        WHERE id = v_prop.target_override_id;
    END IF;

    IF v_prop.proposal_type IN ('create','replace') THEN
        -- Corrigé après la deuxième revue statique (point 12) : created_at forcé explicitement à v_now
        -- (le MÊME instant que revoked_at ci-dessus pour un 'replace'), jamais laissé au DEFAULT
        -- clock_timestamp() de la colonne, qui s'évaluerait quelques microsecondes plus tard — sans
        -- cette égalité exacte, tstzrange(created_at, revoked_at) de l'ancienne et de la nouvelle ligne
        -- pourrait laisser un micro-écart ou un micro-chevauchement selon l'EXCLUDE à deux dimensions
        -- retenue (point 6/§17 §5).
        INSERT INTO public.member_distribution_overrides (
            aggregator_membership_id, override_type, override_value, effective_from, effective_until,
            proposal_id, created_by, created_at
        ) VALUES (
            v_prop.aggregator_membership_id, v_prop.override_type, v_prop.override_value,
            v_prop.proposed_effective_from, v_prop.proposed_effective_until, p_proposal_id, v_prop.proposed_by, v_now
        ) RETURNING id INTO v_new_id;
    ELSE
        v_new_id := v_prop.target_override_id;  -- 'revoke' : uniformité de lecture (§17 point 5)
    END IF;

    UPDATE public.member_distribution_override_proposals SET status = 'activated', activated_override_id = v_new_id WHERE id = p_proposal_id;

    -- Corrigé après la deuxième revue statique (point 4) : actor_id (l'approbateur dont l'approbation a
    -- déclenché cette activation) et organization_id (l'organisation membre concernée, via l'adhésion)
    -- désormais tous deux obligatoires — auparavant ni l'un ni l'autre n'étaient renseignés.
    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
    SELECT 'member_distribution_override', v_new_id, 'member_distribution_override_activated', auth.uid(), am.organization_id, am.aggregator_id,
           jsonb_build_object('proposal_id', p_proposal_id, 'proposal_type', v_prop.proposal_type)
    FROM public.aggregator_memberships am WHERE am.id = v_prop.aggregator_membership_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_member_distribution_override_proposal(p_proposal_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor    UUID;
    v_prop     RECORD;
    v_operator UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'p_reason est requis.'; END IF;

    -- Corrigé après la première revue statique : point 13 (RECORD/scalar mixing — organization_id/
    -- aggregator_id capturés comme colonnes du même RECORD v_prop, sous alias, jamais des cibles
    -- scalaires séparées dans la même liste INTO) ; point 3 (is_aggregator_primary_admin(), jamais
    -- co_admin) ; point 4 (OR is_platform_superadmin() explicite pour la branche opérateur).
    SELECT organization_id INTO v_operator FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1;
    SELECT p.*, am.organization_id AS m_organization_id, am.aggregator_id AS m_aggregator_id INTO v_prop
    FROM public.member_distribution_override_proposals p
    JOIN public.aggregator_memberships am ON am.id = p.aggregator_membership_id
    WHERE p.id = p_proposal_id
      AND (COALESCE(public.is_org_admin(am.organization_id), false) OR COALESCE(public.is_aggregator_primary_admin(am.aggregator_id), false)
           OR COALESCE(public.is_platform_operator_admin(v_operator), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE OF p;
    IF v_prop.id IS NULL THEN RAISE EXCEPTION 'Proposition introuvable ou accès refusé.'; END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;

    UPDATE public.member_distribution_override_proposals
    SET status = 'rejected', rejected_by = v_actor, rejected_at = clock_timestamp(), reject_reason = p_reason
    WHERE id = p_proposal_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
    VALUES ('member_distribution_override_proposal', p_proposal_id, 'member_distribution_override_rejected', v_actor, v_prop.m_organization_id, v_prop.m_aggregator_id, jsonb_build_object('reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION public.withdraw_member_distribution_override_proposal(p_proposal_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  UUID;
    v_prop   RECORD;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Corrigé après la première revue statique (point 13) : organization_id/aggregator_id capturés
    -- comme colonnes aliasées du RECORD v_prop, jamais des cibles scalaires séparées mélangées avec p.*.
    SELECT p.*, am.organization_id AS m_organization_id, am.aggregator_id AS m_aggregator_id INTO v_prop
    FROM public.member_distribution_override_proposals p
    JOIN public.aggregator_memberships am ON am.id = p.aggregator_membership_id
    WHERE p.id = p_proposal_id AND p.proposed_by = v_actor
    FOR UPDATE OF p;
    IF v_prop.id IS NULL THEN RAISE EXCEPTION 'Proposition introuvable ou vous n''en êtes pas l''auteur.'; END IF;
    IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposition % non pending (statut réel : %).', p_proposal_id, v_prop.status; END IF;

    UPDATE public.member_distribution_override_proposals SET status = 'withdrawn' WHERE id = p_proposal_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
    VALUES ('member_distribution_override_proposal', p_proposal_id, 'member_distribution_override_withdrawn', v_actor, v_prop.m_organization_id, v_prop.m_aggregator_id, '{}'::jsonb);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 12. RLS (§17 point 15)
-- ────────────────────────────────────────────────────────────

-- Corrigé après la troisième revue statique (point 1) : cette fonction donnait auparavant la VENTE
-- ENTIÈRE (et, via les policies credit_sale_lots_select/credit_sale_costs_select/
-- credit_sale_adjustments_select/credit_sale_allocations_select, qui réutilisaient TOUTES
-- can_view_credit_sale(), les lots/coûts/ajustements/allocations D'AUTRES ORGANISATIONS) à toute
-- organisation membre d'une source contributrice OU bénéficiaire d'une seule ligne
-- credit_sale_allocations — contredisant §17 point 15 : « organisation contributrice — visibilité
-- de ses propres lignes credit_sale_allocations, jamais de la vente entière ni des allocations des
-- autres organisations ». Les deux branches is_organization_member(...) ci-dessous (source ET
-- bénéficiaire d'allocation) sont retirées ; seul is_aggregator_admin() est conservé pour le
-- regroupement (lecture large déjà explicitement voulue par §17, lecture seule, primary_admin OU
-- co_admin). La visibilité par organisation contributrice est désormais portée par une fonction
-- dédiée, can_view_credit_sale_allocation() ci-dessous, utilisée UNIQUEMENT par la policy de
-- credit_sale_allocations (jamais par credit_sales/credit_sale_lots/credit_sale_costs/
-- credit_sale_adjustments), et scopée ligne par ligne (organization_id de la ligne consultée).
CREATE OR REPLACE FUNCTION public.can_view_credit_sale(p_credit_sale_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.credit_sales cs
        WHERE cs.id = p_credit_sale_id
          AND (
               COALESCE(public.is_platform_superadmin(), false)
               OR COALESCE(public.is_organization_member(cs.seller_organization_id), false)
               OR EXISTS (
                    SELECT 1 FROM public.credit_sale_lots csl
                    JOIN public.credit_lots cl ON cl.id = csl.credit_lot_id
                    WHERE csl.credit_sale_id = cs.id
                      AND COALESCE(public.is_aggregator_admin(cl.aggregator_id), false)
                  )
          )
    )
$$;

-- Point 1 : visibilité D'UNE LIGNE credit_sale_allocations précise pour l'organisation
-- contributrice concernée (p_organization_id = la colonne organization_id DE CETTE LIGNE, jamais un
-- paramètre libre — la policy RLS l'alimente avec la valeur réelle de la ligne évaluée). N'étend
-- JAMAIS la visibilité à la vente entière ni aux lignes des AUTRES organisations de la même vente :
-- can_view_credit_sale() (seller/superadmin/aggregator admin) reste la première branche, la seconde
-- (is_organization_member) n'est vraie QUE pour la ligne dont organization_id correspond à
-- l'organisation de l'appelant.
CREATE OR REPLACE FUNCTION public.can_view_credit_sale_allocation(p_credit_sale_id UUID, p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(public.can_view_credit_sale(p_credit_sale_id), false)
        OR COALESCE(public.is_organization_member(p_organization_id), false)
$$;

CREATE OR REPLACE FUNCTION public.can_view_distribution_rule(p_distribution_rule_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    -- Corrigé après la SIXIÈME revue statique (correction 3) : la branche « simple membre d'une
    -- organisation adhérente » exige désormais am.ended_at IS NULL (adhésion ACTIVE). aggregator_memberships
    -- est historisée (§7/§8 de ce document) — sans cette condition, une organisation ayant QUITTÉ le
    -- regroupement (leave_aggregator(), migration 02) conservait sa ligne d'adhésion passée, et un
    -- simple membre ACTUEL de cette organisation pouvait continuer à voir les FUTURES distribution_rules
    -- de ce regroupement après le départ de son organisation — non conforme au §17 (« membre d'une
    -- organisation adhérente », « membre y participant », toujours au présent). La visibilité HISTORIQUE
    -- d'autres objets n'est pas modifiée par ce correctif (aucune décision explicite ne le demande).
    SELECT EXISTS (
        SELECT 1 FROM public.distribution_rules dr
        WHERE dr.id = p_distribution_rule_id
          AND (
               COALESCE(public.is_platform_superadmin(), false)
               OR COALESCE(public.is_aggregator_admin(dr.aggregator_id), false)
               OR EXISTS (SELECT 1 FROM public.aggregator_memberships am WHERE am.aggregator_id = dr.aggregator_id AND am.ended_at IS NULL AND COALESCE(public.is_organization_member(am.organization_id), false))
               OR COALESCE(public.is_platform_operator_admin((SELECT organization_id FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1)), false)
          )
    )
$$;

-- Corrigé après la troisième revue statique (point 1) : is_aggregator_admin() remplacé par
-- is_aggregator_primary_admin() — une proposition en attente d'approbation n'est visible qu'aux
-- approbateurs RÉELLEMENT requis (primary_admin du regroupement + admin opérateur, §17 point 15),
-- au proposant, et à is_platform_superadmin() ; un co_admin (autorisé à CONSULTER une
-- distribution_rule déjà activée, can_view_distribution_rule() ci-dessus, volontairement plus
-- large) n'a aucun rôle dans l'approbation et ne doit pas voir une négociation en cours.
CREATE OR REPLACE FUNCTION public.can_view_distribution_rule_proposal(p_proposal_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.distribution_rule_proposals p
        WHERE p.id = p_proposal_id
          AND (
               COALESCE(public.is_platform_superadmin(), false)
               OR p.proposed_by = auth.uid()
               OR COALESCE(public.is_aggregator_primary_admin(p.aggregator_id), false)
               OR COALESCE(public.is_platform_operator_admin((SELECT organization_id FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1)), false)
          )
    )
$$;

CREATE OR REPLACE FUNCTION public.can_view_member_distribution_override(p_override_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.member_distribution_overrides o
        JOIN public.aggregator_memberships am ON am.id = o.aggregator_membership_id
        WHERE o.id = p_override_id
          AND (
               COALESCE(public.is_platform_superadmin(), false)
               OR COALESCE(public.is_organization_member(am.organization_id), false)
               OR COALESCE(public.is_aggregator_admin(am.aggregator_id), false)
               OR COALESCE(public.is_platform_operator_admin((SELECT organization_id FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1)), false)
          )
    )
$$;

-- Corrigé après la troisième revue statique (point 1) : is_organization_member()/is_aggregator_admin()
-- remplacés respectivement par is_org_admin()/is_aggregator_primary_admin() — seuls les TROIS
-- approbateurs réellement requis (admin de l'organisation membre concernée, primary_admin du
-- regroupement, admin opérateur, §17 point 15) voient une proposition en attente, plus le
-- proposant et is_platform_superadmin(). Un simple membre de l'organisation ou un co_admin du
-- regroupement n'a aucun rôle dans cette approbation et ne doit pas voir une négociation en cours
-- (can_view_member_distribution_override() ci-dessus, pour l'override déjà ACTIVÉ, reste
-- volontairement plus large — seule la PROPOSITION est restreinte ici).
CREATE OR REPLACE FUNCTION public.can_view_member_distribution_override_proposal(p_proposal_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.member_distribution_override_proposals p
        JOIN public.aggregator_memberships am ON am.id = p.aggregator_membership_id
        WHERE p.id = p_proposal_id
          AND (
               COALESCE(public.is_platform_superadmin(), false)
               OR p.proposed_by = auth.uid()
               OR COALESCE(public.is_org_admin(am.organization_id), false)
               OR COALESCE(public.is_aggregator_primary_admin(am.aggregator_id), false)
               OR COALESCE(public.is_platform_operator_admin((SELECT organization_id FROM public.platform_operators WHERE revoked_at IS NULL LIMIT 1)), false)
          )
    )
$$;

ALTER TABLE public.credit_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_sale_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_sale_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_sale_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.distribution_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.distribution_rule_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_distribution_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_distribution_override_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_sale_allocations ENABLE ROW LEVEL SECURITY;

CREATE POLICY credit_sales_select ON public.credit_sales FOR SELECT TO authenticated USING (public.can_view_credit_sale(id));
CREATE POLICY credit_sale_lots_select ON public.credit_sale_lots FOR SELECT TO authenticated USING (public.can_view_credit_sale(credit_sale_id));
CREATE POLICY credit_sale_costs_select ON public.credit_sale_costs FOR SELECT TO authenticated USING (public.can_view_credit_sale(credit_sale_id));
CREATE POLICY credit_sale_adjustments_select ON public.credit_sale_adjustments FOR SELECT TO authenticated USING (public.can_view_credit_sale(credit_sale_id));
-- Corrigé après la troisième revue statique (point 1) : can_view_credit_sale_allocation() (jamais
-- can_view_credit_sale() seul) — scope la visibilité de CHAQUE ligne à sa PROPRE organization_id
-- pour l'organisation contributrice, jamais à la vente entière ni aux lignes des autres organisations.
CREATE POLICY credit_sale_allocations_select ON public.credit_sale_allocations FOR SELECT TO authenticated USING (public.can_view_credit_sale_allocation(credit_sale_id, organization_id));
CREATE POLICY distribution_rules_select ON public.distribution_rules FOR SELECT TO authenticated USING (public.can_view_distribution_rule(id));
CREATE POLICY distribution_rule_proposals_select ON public.distribution_rule_proposals FOR SELECT TO authenticated USING (public.can_view_distribution_rule_proposal(id));
CREATE POLICY member_distribution_overrides_select ON public.member_distribution_overrides FOR SELECT TO authenticated USING (public.can_view_member_distribution_override(id));
CREATE POLICY member_distribution_override_proposals_select ON public.member_distribution_override_proposals FOR SELECT TO authenticated USING (public.can_view_member_distribution_override_proposal(id));

-- ────────────────────────────────────────────────────────────
-- 13. PRIVILÈGES — jamais PUBLIC seul (leçon 06a), explicite anon/authenticated.
-- ────────────────────────────────────────────────────────────

REVOKE ALL ON TABLE public.credit_sales, public.credit_sale_lots, public.credit_sale_costs,
  public.credit_sale_adjustments, public.distribution_rules, public.distribution_rule_proposals,
  public.member_distribution_overrides, public.member_distribution_override_proposals,
  public.credit_sale_allocations FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.credit_sales, public.credit_sale_lots, public.credit_sale_costs,
  public.credit_sale_adjustments, public.distribution_rules, public.distribution_rule_proposals,
  public.member_distribution_overrides, public.member_distribution_override_proposals,
  public.credit_sale_allocations TO authenticated;

REVOKE ALL ON FUNCTION public.can_view_credit_sale(UUID), public.can_view_credit_sale_allocation(UUID, UUID),
  public.can_view_distribution_rule(UUID),
  public.can_view_distribution_rule_proposal(UUID), public.can_view_member_distribution_override(UUID),
  public.can_view_member_distribution_override_proposal(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_credit_sale(UUID), public.can_view_credit_sale_allocation(UUID, UUID),
  public.can_view_distribution_rule(UUID),
  public.can_view_distribution_rule_proposal(UUID), public.can_view_member_distribution_override(UUID),
  public.can_view_member_distribution_override_proposal(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.effective_net_distributable_amount(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.effective_net_distributable_amount(UUID) TO authenticated;

REVOKE ALL ON FUNCTION
  public.create_credit_sale(UUID, NUMERIC, TEXT),
  public.add_credit_sale_lot(UUID, UUID),
  public.release_credit_sale_lot(UUID, TEXT),
  public.add_credit_sale_cost(UUID, TEXT, NUMERIC, TEXT, TEXT),
  public.cancel_credit_sale(UUID, TEXT),
  public.confirm_credit_sale(UUID),
  public.settle_credit_sale(UUID, TEXT),
  public.retire_credit_lot(UUID, TEXT),
  public.add_credit_sale_adjustment(UUID, NUMERIC, TEXT),
  public.propose_distribution_rule(UUID, NUMERIC, NUMERIC, NUMERIC),
  public.approve_distribution_rule_as_aggregator_admin(UUID),
  public.approve_distribution_rule_as_operator_admin(UUID),
  public.reject_distribution_rule_proposal(UUID, TEXT),
  public.withdraw_distribution_rule_proposal(UUID),
  public.propose_member_distribution_override(TEXT, UUID, UUID, TEXT, NUMERIC, DATE, DATE, TEXT),
  public.approve_member_distribution_override_as_organization_admin(UUID),
  public.approve_member_distribution_override_as_aggregator_admin(UUID),
  public.approve_member_distribution_override_as_operator_admin(UUID),
  public.reject_member_distribution_override_proposal(UUID, TEXT),
  public.withdraw_member_distribution_override_proposal(UUID)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.create_credit_sale(UUID, NUMERIC, TEXT),
  public.add_credit_sale_lot(UUID, UUID),
  public.release_credit_sale_lot(UUID, TEXT),
  public.add_credit_sale_cost(UUID, TEXT, NUMERIC, TEXT, TEXT),
  public.cancel_credit_sale(UUID, TEXT),
  public.confirm_credit_sale(UUID),
  public.settle_credit_sale(UUID, TEXT),
  public.retire_credit_lot(UUID, TEXT),
  public.add_credit_sale_adjustment(UUID, NUMERIC, TEXT),
  public.propose_distribution_rule(UUID, NUMERIC, NUMERIC, NUMERIC),
  public.approve_distribution_rule_as_aggregator_admin(UUID),
  public.approve_distribution_rule_as_operator_admin(UUID),
  public.reject_distribution_rule_proposal(UUID, TEXT),
  public.withdraw_distribution_rule_proposal(UUID),
  public.propose_member_distribution_override(TEXT, UUID, UUID, TEXT, NUMERIC, DATE, DATE, TEXT),
  public.approve_member_distribution_override_as_organization_admin(UUID),
  public.approve_member_distribution_override_as_aggregator_admin(UUID),
  public.approve_member_distribution_override_as_operator_admin(UUID),
  public.reject_member_distribution_override_proposal(UUID, TEXT),
  public.withdraw_member_distribution_override_proposal(UUID)
TO authenticated;

-- Fonctions internes/de trigger — usage interne uniquement, jamais appelées directement.
REVOKE ALL ON FUNCTION
  public.compute_credit_sale_allocations(UUID, UUID),
  public.carbon_try_activate_distribution_rule_proposal(UUID),
  public.carbon_try_activate_member_distribution_override_proposal(UUID),
  public.carbon_guard_credit_sale_insert(), public.carbon_credit_sales_before_update(),
  public.carbon_guard_credit_sale_lot_insert(), public.carbon_credit_sale_lots_before_update(),
  public.carbon_sync_credit_sale_total_tco2e(),
  public.carbon_sync_credit_lot_status_on_sale_lot_insert(), public.carbon_sync_credit_lot_status_on_sale_lot_release(),
  public.carbon_guard_credit_sale_cost_insert(), public.carbon_guard_credit_sale_adjustment_insert(),
  public.carbon_guard_distribution_rule_proposal_insert(), public.carbon_distribution_rule_proposal_before_update(),
  public.carbon_distribution_rule_before_update(),
  public.carbon_guard_member_distribution_override_proposal_insert(), public.carbon_member_distribution_override_proposal_before_update(),
  public.carbon_member_distribution_override_before_update(),
  public.carbon_lock_affected_credit_sales_before_external_cancellation(),
  public.carbon_release_credit_sale_lot_on_external_void(),
  public.carbon_guard_credit_lots_sale_consistency(),
  -- Ajoutées à la ONZIÈME revue statique (bloqueur 1) : ces cinq fonctions sont SECURITY DEFINER,
  -- exclusivement invoquées par des triggers BEFORE INSERT / constraint triggers AFTER UPDATE — jamais
  -- appelées directement par un rôle applicatif — et avaient été omises de ce bloc lors de leur ajout
  -- (bloqueur 2/3 de la NEUVIÈME/DIXIÈME revue statique). Aucun GRANT EXECUTE ne suit, pour aucune des
  -- cinq : cohérent avec toutes les autres fonctions de ce bloc.
  public.carbon_guard_distribution_rule_insert(),
  public.carbon_guard_member_distribution_override_insert(),
  public.carbon_check_distribution_rule_proposal_integrity(),
  public.carbon_check_member_distribution_override_creation_integrity(),
  public.carbon_check_member_distribution_override_revocation_integrity(),
  -- Ajoutée à la DOUZIÈME revue statique (bloqueur 2) : même patron que les cinq fonctions ci-dessus —
  -- SECURITY DEFINER, exclusivement invoquée par le nouveau constraint trigger de fermeture
  -- (trg_carbon_check_distribution_rule_closure_integrity), jamais un GRANT EXECUTE.
  public.carbon_check_distribution_rule_closure_integrity()
FROM PUBLIC, anon, authenticated;

-- ────────────────────────────────────────────────────────────
-- 14. AUTO-VALIDATION (§16 point 0bis étape 3, même discipline que 07/08)
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regclass('public.credit_sales') IS NULL OR to_regclass('public.credit_sale_lots') IS NULL
       OR to_regclass('public.credit_sale_costs') IS NULL OR to_regclass('public.credit_sale_adjustments') IS NULL
       OR to_regclass('public.distribution_rules') IS NULL OR to_regclass('public.distribution_rule_proposals') IS NULL
       OR to_regclass('public.member_distribution_overrides') IS NULL
       OR to_regclass('public.member_distribution_override_proposals') IS NULL
       OR to_regclass('public.credit_sale_allocations') IS NULL THEN
        RAISE EXCEPTION 'Auto-validation échouée : au moins une des 9 tables de la migration 09 est introuvable après création.';
    END IF;
    -- Trois ALTER TABLE différés (corrigé après la première revue statique, point 14 — §17 en comptait
    -- deux par erreur ; member_distribution_overrides a deux colonnes distinctes référençant
    -- member_distribution_override_proposals, proposal_id ET revocation_proposal_id).
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'distribution_rules_proposal_id_fkey') THEN
        RAISE EXCEPTION 'Auto-validation échouée : ALTER TABLE différé distribution_rules.proposal_id introuvable.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'member_distribution_overrides_proposal_id_fkey') THEN
        RAISE EXCEPTION 'Auto-validation échouée : ALTER TABLE différé member_distribution_overrides.proposal_id introuvable.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'member_distribution_overrides_revocation_proposal_id_fkey') THEN
        RAISE EXCEPTION 'Auto-validation échouée : ALTER TABLE différé member_distribution_overrides.revocation_proposal_id introuvable.';
    END IF;
    IF to_regprocedure('public.confirm_credit_sale(uuid)') IS NULL
       OR to_regprocedure('public.compute_credit_sale_allocations(uuid,uuid)') IS NULL
       OR to_regprocedure('public.propose_distribution_rule(uuid,numeric,numeric,numeric)') IS NULL
       OR to_regprocedure('public.propose_member_distribution_override(text,uuid,uuid,text,numeric,date,date,text)') IS NULL THEN
        RAISE EXCEPTION 'Auto-validation échouée : au moins une RPC clé de la migration 09 est introuvable avec la signature attendue.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_lots'::regclass AND tgname = 'trg_carbon_release_credit_sale_lot_on_external_void') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger de coordination reserved->voided introuvable sur credit_lots.';
    END IF;
    -- Point 15 (ajouté après la première revue statique) : garde de cohérence structurelle credit_sale_lots <-> credit_lots.
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_lots'::regclass AND tgname = 'trg_carbon_guard_credit_lots_sale_consistency') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger de cohérence structurelle (point 15) introuvable sur credit_lots.';
    END IF;
    -- Point 2 (ajouté après la deuxième revue statique) : credit_sale_lots devient l'unique propriétaire
    -- structurel de la synchronisation vers credit_lots.commercial_status (insert -> reserved, libération -> available).
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_sale_lots'::regclass AND tgname = 'trg_carbon_sync_credit_lot_status_on_sale_lot_insert') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger de synchronisation credit_lots (point 2, insertion) introuvable sur credit_sale_lots.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_sale_lots'::regclass AND tgname = 'trg_carbon_sync_credit_lot_status_on_sale_lot_release') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger de synchronisation credit_lots (point 2, libération) introuvable sur credit_sale_lots.';
    END IF;
    -- Point 3 (ajouté après la deuxième revue statique) : verrou d'ordre credit_sales avant credit_lots
    -- lors d'une annulation externe, ferme le deadlock possible avec confirm_credit_sale()/add_credit_sale_lot().
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_issuances'::regclass AND tgname = 'trg_carbon_lock_affected_credit_sales_before_external_cancellation') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger de verrouillage anti-deadlock (point 3) introuvable sur credit_issuances.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'member_distribution_overrides_no_overlap' AND conrelid = 'public.member_distribution_overrides'::regclass) THEN
        RAISE EXCEPTION 'Auto-validation échouée : EXCLUDE member_distribution_overrides_no_overlap (point 6, à deux dimensions) introuvable.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.credit_sales'::regclass AND relrowsecurity = true) THEN
        RAISE EXCEPTION 'Auto-validation échouée : RLS non activée sur credit_sales.';
    END IF;
    IF has_table_privilege('anon', 'public.credit_sales', 'SELECT') THEN
        RAISE EXCEPTION 'Auto-validation échouée : anon ne devrait avoir aucun privilège SELECT sur credit_sales.';
    END IF;

    RAISE NOTICE 'Auto-validation réussie : 9 tables créées, 3 ALTER différés en place, RPC clés présentes, triggers de coordination/cohérence posés, RLS activée.';
END $$;

COMMIT;

-- Rechargement du cache de schéma PostgREST (§16 point 0bis étape 4, même
-- discipline que 07/08) — émis APRÈS le COMMIT, séparément.
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- ROLLBACK (à exécuter séparément, jamais collé avec ce qui précède) —
-- migration de création pure : un ROLLBACK complet peut simplement DROP les
-- 9 tables et les objets posés, aucune table legacy à reconstruire
-- (contrairement à 08). ATTENTION : sans risque de perte de données
-- UNIQUEMENT si aucune vraie vente n'a encore été créée depuis le COMMIT de
-- cette migration — vérifier explicitement SELECT count(*) FROM
-- public.credit_sales avant d'exécuter ce rollback ; si > 0, ne pas
-- exécuter, une migration corrective ciblée serait requise à la place.
--
-- ATTENTION (HUITIÈME revue statique, bloqueur 3 ; CORRIGÉ à la DIXIÈME revue statique — le texte
-- précédent de ce paragraphe, qui prescrivait de restaurer la définition de MIGRATION 02, est
-- INTERDIT et ne doit plus jamais être suivi) : public.join_aggregator(UUID, UUID) N'EST PAS créée par
-- 09 — elle appartient à la migration 02 (déjà appliquée), et 09 la remplace UNIQUEMENT via CREATE OR
-- REPLACE FUNCTION (§17 point 9bis), jamais DROP. Un rollback de 09 ne doit donc JAMAIS DROP cette
-- fonction (elle disparaîtrait entièrement, cassant 02) : il doit la RESTAURER à sa définition
-- SÉCURISÉE POST-MIGRATION 03 (celle réellement déployée juste avant l'application de 09 — COALESCE(
-- is_aggregator_admin(p_aggregator_id), false) OR COALESCE(is_platform_superadmin(), false) CONSERVÉS
-- intégralement, started_at/created_at redevenant DEFAULT now(), sans le verrou aggregators.id ajouté
-- par 09), JAMAIS la définition brute de migration 02 (HISTORIQUE, VULNÉRABLE — sans COALESCE, bypass
-- NULL exploitable par tout utilisateur authentifié normal). Source fonctionnelle exacte de ce
-- rollback = le CREATE OR REPLACE FUNCTION public.join_aggregator(...) tel qu'il apparaît dans
-- 03_fix_null_bypass_authorization.sql (fichier inchangé, source de vérité — jamais
-- 02_carbon_aggregator_memberships.sql, dont la définition d'origine a été sciemment corrigée et rendue
-- obsolète par 03). Même principe pour toute autre RPC préexistante que 09 redéfinirait par CREATE OR
-- REPLACE (voir §17 point 9bis/9ter pour la liste complète) : jamais un DROP FUNCTION, et toujours
-- restaurer le dernier état sécurisé réellement déployé, jamais un état antérieur non corrigé.
--
-- CORRIGÉ à la DOUZIÈME revue statique (bloqueur opérationnel 4) : le paragraphe ci-dessus restait
-- conceptuellement correct mais n'était accompagné d'AUCUN SQL réel — ce rollback n'aurait, tel quel,
-- jamais restauré quoi que ce soit. Le corps COMPLET ci-dessous, copié verbatim depuis
-- 03_fix_null_bypass_authorization.sql (lignes 148-203, fichier historique inchangé), est désormais
-- inclus explicitement dans ce bloc commenté — RESTAURATION EFFECTIVE join_aggregator post-03.
--
-- BEGIN;
--
-- -- ────────────────────────────────────────────────────────────
-- -- RESTAURATION EFFECTIVE join_aggregator post-03 (jamais un DROP FUNCTION — cette fonction appartient
-- -- à la migration 02, corrigée par la migration 03 ; ce rollback annule UNIQUEMENT le CREATE OR REPLACE
-- -- posé par 09 en remettant EXACTEMENT la définition sécurisée post-migration-03/pré-09 : auth.uid()
-- -- requis, double COALESCE conservé intégralement, AUCUNE régression vers la forme brute de migration
-- -- 02, et SANS le verrou aggregators.id FOR UPDATE ajouté par 09 — started_at/created_at redeviennent
-- -- le DEFAULT now() de la colonne, comportement temporel exactement pré-09/post-03).
-- -- ────────────────────────────────────────────────────────────
-- CREATE OR REPLACE FUNCTION public.join_aggregator(
--     p_organization_id UUID,
--     p_aggregator_id UUID
-- )
-- RETURNS UUID
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path = public, pg_temp
-- AS $$
-- DECLARE
--     v_membership_id UUID;
-- BEGIN
--     IF auth.uid() IS NULL THEN
--         RAISE EXCEPTION 'Authentification requise.';
--     END IF;
--
--     -- CORRECTIF (migration 03), CONSERVÉ intégralement par cette restauration : COALESCE(..., false)
--     -- sur les deux membres du OR. is_aggregator_admin() est structurellement toujours true/false
--     -- (construite avec EXISTS), mais is_platform_superadmin() peut valoir NULL. false OR NULL = NULL,
--     -- et IF NOT NULL ne s'exécute jamais en PL/pgSQL : sans ce correctif, n'importe quel utilisateur
--     -- authentifié normal pouvait rattacher n'importe quelle organisation à n'importe quel regroupement
--     -- (JAMAIS la forme historique vulnérable de migration 02, sans COALESCE).
--     IF NOT (COALESCE(public.is_aggregator_admin(p_aggregator_id), false)
--             OR COALESCE(public.is_platform_superadmin(), false)) THEN
--         RAISE EXCEPTION 'Seul un administrateur du regroupement cible ou un super-administrateur peut ajouter une organisation à ce regroupement.';
--     END IF;
--
--     IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
--         RAISE EXCEPTION 'p_organization_id ne correspond à aucune organisation existante.';
--     END IF;
--
--     IF NOT EXISTS (SELECT 1 FROM public.aggregators WHERE id = p_aggregator_id) THEN
--         RAISE EXCEPTION 'p_aggregator_id ne correspond à aucun regroupement existant.';
--     END IF;
--
--     -- Pré-vérification explicite et lisible avant de tenter l'insertion — l'index unique partiel
--     -- (idx_aggregator_memberships_one_active_per_org) reste le filet de sécurité structurel en cas de
--     -- course concurrente.
--     IF EXISTS (
--         SELECT 1 FROM public.aggregator_memberships
--         WHERE organization_id = p_organization_id AND ended_at IS NULL
--     ) THEN
--         RAISE EXCEPTION 'Cette organisation a déjà une adhésion active à un regroupement — utilisez leave_aggregator() avant d''en rejoindre un autre.';
--     END IF;
--
--     -- SANS le verrou aggregators.id FOR UPDATE ajouté par 09, SANS capture explicite v_started_at :
--     -- started_at/created_at reprennent le DEFAULT now() de la colonne, comportement pré-09/post-03.
--     INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by)
--     VALUES (p_organization_id, p_aggregator_id, auth.uid())
--     RETURNING id INTO v_membership_id;
--
--     INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
--     VALUES ('aggregator_membership_started', 'aggregator_membership', v_membership_id, p_organization_id, p_aggregator_id, auth.uid(), NULL);
--
--     RETURN v_membership_id;
-- END;
-- $$;
--
-- COMMENT ON FUNCTION public.join_aggregator(UUID, UUID) IS
--   'Crée une adhésion active d''une organisation à un regroupement. Autorisée à '
--   'COALESCE(is_aggregator_admin(p_aggregator_id), false) OR COALESCE(is_platform_superadmin(), false) '
--   '(décision D1, migration 02, COALESCE ajouté par la migration 03 — bypass NULL corrigé). RESTAURÉE '
--   'ici par le rollback de 09 à l''état exact post-migration-03/pré-09 (verrou aggregators.id et capture '
--   'explicite de started_at/created_at, ajoutés par 09, annulés par cette restauration).';
--
-- DROP TRIGGER IF EXISTS trg_carbon_release_credit_sale_lot_on_external_void ON public.credit_lots;
-- DROP FUNCTION IF EXISTS public.carbon_release_credit_sale_lot_on_external_void();
--
-- DROP TRIGGER IF EXISTS trg_carbon_lock_affected_credit_sales_before_external_cancellation ON public.credit_issuances;
-- DROP FUNCTION IF EXISTS public.carbon_lock_affected_credit_sales_before_external_cancellation();
--
-- DROP TRIGGER IF EXISTS trg_carbon_sync_credit_lot_status_on_sale_lot_release ON public.credit_sale_lots;
-- DROP FUNCTION IF EXISTS public.carbon_sync_credit_lot_status_on_sale_lot_release();
-- DROP TRIGGER IF EXISTS trg_carbon_sync_credit_lot_status_on_sale_lot_insert ON public.credit_sale_lots;
-- DROP FUNCTION IF EXISTS public.carbon_sync_credit_lot_status_on_sale_lot_insert();
--
-- DROP POLICY IF EXISTS credit_sales_select ON public.credit_sales;
-- DROP POLICY IF EXISTS credit_sale_lots_select ON public.credit_sale_lots;
-- DROP POLICY IF EXISTS credit_sale_costs_select ON public.credit_sale_costs;
-- DROP POLICY IF EXISTS credit_sale_adjustments_select ON public.credit_sale_adjustments;
-- DROP POLICY IF EXISTS credit_sale_allocations_select ON public.credit_sale_allocations;
-- DROP POLICY IF EXISTS distribution_rules_select ON public.distribution_rules;
-- DROP POLICY IF EXISTS distribution_rule_proposals_select ON public.distribution_rule_proposals;
-- DROP POLICY IF EXISTS member_distribution_overrides_select ON public.member_distribution_overrides;
-- DROP POLICY IF EXISTS member_distribution_override_proposals_select ON public.member_distribution_override_proposals;
--
-- DROP FUNCTION IF EXISTS public.withdraw_member_distribution_override_proposal(UUID);
-- DROP FUNCTION IF EXISTS public.reject_member_distribution_override_proposal(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.carbon_try_activate_member_distribution_override_proposal(UUID);
-- DROP FUNCTION IF EXISTS public.approve_member_distribution_override_as_operator_admin(UUID);
-- DROP FUNCTION IF EXISTS public.approve_member_distribution_override_as_aggregator_admin(UUID);
-- DROP FUNCTION IF EXISTS public.approve_member_distribution_override_as_organization_admin(UUID);
-- DROP FUNCTION IF EXISTS public.propose_member_distribution_override(TEXT, UUID, UUID, TEXT, NUMERIC, DATE, DATE, TEXT);
-- DROP FUNCTION IF EXISTS public.withdraw_distribution_rule_proposal(UUID);
-- DROP FUNCTION IF EXISTS public.reject_distribution_rule_proposal(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.carbon_try_activate_distribution_rule_proposal(UUID);
-- DROP FUNCTION IF EXISTS public.approve_distribution_rule_as_operator_admin(UUID);
-- DROP FUNCTION IF EXISTS public.approve_distribution_rule_as_aggregator_admin(UUID);
-- DROP FUNCTION IF EXISTS public.propose_distribution_rule(UUID, NUMERIC, NUMERIC, NUMERIC);
-- DROP FUNCTION IF EXISTS public.effective_net_distributable_amount(UUID);
-- DROP FUNCTION IF EXISTS public.add_credit_sale_adjustment(UUID, NUMERIC, TEXT);
-- DROP FUNCTION IF EXISTS public.retire_credit_lot(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.settle_credit_sale(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.confirm_credit_sale(UUID);
-- DROP FUNCTION IF EXISTS public.compute_credit_sale_allocations(UUID, UUID);
-- DROP TRIGGER IF EXISTS trg_carbon_guard_credit_lots_sale_consistency ON public.credit_lots;
-- DROP FUNCTION IF EXISTS public.carbon_guard_credit_lots_sale_consistency();
-- DROP FUNCTION IF EXISTS public.cancel_credit_sale(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.add_credit_sale_cost(UUID, TEXT, NUMERIC, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS public.release_credit_sale_lot(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.add_credit_sale_lot(UUID, UUID);
-- DROP FUNCTION IF EXISTS public.create_credit_sale(UUID, NUMERIC, TEXT);
--
-- DROP FUNCTION IF EXISTS public.can_view_member_distribution_override_proposal(UUID);
-- DROP FUNCTION IF EXISTS public.can_view_member_distribution_override(UUID);
-- DROP FUNCTION IF EXISTS public.can_view_distribution_rule_proposal(UUID);
-- DROP FUNCTION IF EXISTS public.can_view_distribution_rule(UUID);
-- -- Ajouté après la CINQUIÈME revue statique (correction complémentaire) : oubliée du rollback
-- -- initial (point 1, quatrième revue statique — nouveau helper par ligne, jamais couvert depuis).
-- DROP FUNCTION IF EXISTS public.can_view_credit_sale_allocation(UUID, UUID);
-- DROP FUNCTION IF EXISTS public.can_view_credit_sale(UUID);
--
-- DROP TABLE IF EXISTS public.credit_sale_allocations;
-- -- Ajoutés après la NEUVIÈME revue statique (bloqueur 4, intégrité bidirectionnelle) : les trois
-- -- CONSTRAINT TRIGGER DEFERRABLE et leurs fonctions disparaissent avec la table via DROP TABLE
-- -- ci-dessous (les triggers ne survivent jamais à leur table), mais les FONCTIONS restent orphelines
-- -- sans DROP FUNCTION explicite (comportement standard PostgreSQL : DROP TABLE ne supprime jamais les
-- -- fonctions qu'un trigger appelait).
-- DROP FUNCTION IF EXISTS public.carbon_check_member_distribution_override_revocation_integrity();
-- DROP FUNCTION IF EXISTS public.carbon_check_member_distribution_override_creation_integrity();
-- DROP FUNCTION IF EXISTS public.carbon_check_distribution_rule_proposal_integrity();
-- DROP FUNCTION IF EXISTS public.carbon_check_distribution_rule_closure_integrity();
-- -- Ajoutée à la DOUZIÈME revue statique (bloqueur 2) : même principe -- le constraint trigger AFTER
-- -- UPDATE OF effective_to disparaît avec sa table, sa fonction reste orpheline sans DROP explicite.
-- -- Ajoutées à la DIXIÈME revue statique (bloqueur 3) : mêmes principe -- les deux triggers BEFORE
-- -- INSERT disparaissent avec leur table, leurs fonctions restent orphelines sans DROP explicite.
-- DROP FUNCTION IF EXISTS public.carbon_guard_member_distribution_override_insert();
-- DROP FUNCTION IF EXISTS public.carbon_guard_distribution_rule_insert();
-- ALTER TABLE IF EXISTS public.member_distribution_overrides DROP CONSTRAINT IF EXISTS member_distribution_overrides_revocation_proposal_id_unique;
-- ALTER TABLE IF EXISTS public.member_distribution_overrides DROP CONSTRAINT IF EXISTS member_distribution_overrides_proposal_id_unique;
-- ALTER TABLE IF EXISTS public.distribution_rules DROP CONSTRAINT IF EXISTS distribution_rules_proposal_id_unique;
-- ALTER TABLE IF EXISTS public.member_distribution_overrides DROP CONSTRAINT IF EXISTS member_distribution_overrides_revocation_proposal_id_fkey;
-- ALTER TABLE IF EXISTS public.member_distribution_overrides DROP CONSTRAINT IF EXISTS member_distribution_overrides_proposal_id_fkey;
-- DROP TABLE IF EXISTS public.member_distribution_override_proposals;
-- DROP TABLE IF EXISTS public.member_distribution_overrides;
-- ALTER TABLE IF EXISTS public.distribution_rules DROP CONSTRAINT IF EXISTS distribution_rules_proposal_id_fkey;
-- DROP TABLE IF EXISTS public.distribution_rule_proposals;
-- DROP TABLE IF EXISTS public.distribution_rules;
-- DROP TABLE IF EXISTS public.credit_sale_adjustments;
-- DROP TABLE IF EXISTS public.credit_sale_costs;
-- DROP TABLE IF EXISTS public.credit_sale_lots;
-- DROP TABLE IF EXISTS public.credit_sales;
--
-- -- Catalogues event_type/object_type (section 0bis) : CHOIX DOCUMENTÉ — pas
-- -- de rollback automatique, même raisonnement que 07/08 (35->37, 37->38).
-- -- Laisser les 10/5 valeurs au catalogue après ce rollback est sans danger.
--
-- COMMIT;
--
-- NOTIFY pgrst, 'reload schema';
-- ============================================================
