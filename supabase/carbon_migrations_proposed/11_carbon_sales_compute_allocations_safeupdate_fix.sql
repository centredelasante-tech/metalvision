-- ============================================================
-- Migration 11 — correctif compute_credit_sale_allocations() (pg-safeupdate)
-- ============================================================
--
-- STATUT : bug réel trouvé en test E2E live du Lot 3 (page
-- /admin/carbon-sales), 31 juillet 2026, connecté en tant que
-- centredelasante@gmail.com (opérateur MINOVIA actif) — clic sur
-- « Confirmer la vente » échoue systématiquement avec l'erreur
-- « UPDATE requires a WHERE clause ».
--
-- CAUSE RACINE : compute_credit_sale_allocations() (migration 09) contient
-- une instruction UPDATE _c09_pairs SANS clause WHERE, volontaire (elle doit
-- toucher TOUTES les lignes de la table temporaire _c09_pairs — répartir
-- gross_amount sur chaque paire organisation/regroupement). Cette
-- instruction est syntaxiquement valide et fonctionne parfaitement lorsqu'
-- elle est exécutée via une connexion directe (confirmé par exécution
-- diagnostique en transaction annulée via le connecteur MCP Supabase, qui se
-- connecte hors du rôle `authenticator`). Mais toute requête PostgREST réelle
-- (donc tout appel RPC déclenché depuis le navigateur) passe par le rôle
-- `authenticator`, dont la configuration en base (pg_db_role_setting) charge
-- `session_preload_libraries=supautils, safeupdate` — l'extension
-- pg-safeupdate (https://github.com/eradman/pg-safeupdate), activée par
-- défaut sur les projets Supabase pour empêcher les UPDATE/DELETE de masse
-- accidentels via l'API. safeupdate s'applique à TOUTE instruction UPDATE
-- exécutée dans la session, y compris à l'intérieur d'une fonction
-- SECURITY DEFINER, sans distinction entre table permanente et table
-- temporaire — ce qui n'avait jamais été détecté auparavant : le harnais
-- transactionnel de la migration 09 (GATE 3, §18, 196/196) s'exécute via
-- `psql --file` sous un rôle qui ne charge pas safeupdate, et les 72
-- scénarios de concurrence réelle (R9) simulaient les appels via dblink,
-- également hors du rôle `authenticator`. Seul un test de bout en bout via
-- l'API HTTP réelle (PostgREST, donc l'interface web) pouvait révéler ce
-- comportement.
--
-- CORRECTIF : ajout de `WHERE true` à l'unique UPDATE sans clause WHERE de
-- la fonction — satisfait pg-safeupdate sans changer la sémantique (la
-- fonction doit toujours toucher toutes les lignes de _c09_pairs, table
-- temporaire locale à l'appel, aucune ligne d'aucune autre vente n'y figure
-- jamais). Audité par ailleurs : c'est la SEULE instruction UPDATE sans
-- WHERE dans l'ensemble des fonctions du domaine credit_sales/credit_sale_lots/
-- credit_sale_costs/credit_sale_allocations (add_credit_sale_lot,
-- confirm_credit_sale, cancel_credit_sale, release_credit_sale_lot,
-- settle_credit_sale, add_credit_sale_cost, add_credit_sale_adjustment,
-- create_credit_sale — toutes leurs instructions UPDATE portent déjà une
-- clause WHERE explicite sur une clé primaire ou équivalent).
--
-- CREATE OR REPLACE FUNCTION sur une fonction de la migration 09 déjà
-- appliquée — aucun fichier existant n'est modifié (09_carbon_sales_
-- financial_model.sql reste inchangé sur disque) ; le corps ci-dessous est
-- une copie exacte de la version actuellement en production, à la seule
-- exception de la clause WHERE ajoutée (repérable au commentaire
-- « CORRECTIF MIGRATION 11 » inline, juste avant l'instruction concernée).
-- Aucune autre ligne n'a été modifiée.

CREATE OR REPLACE FUNCTION public.compute_credit_sale_allocations(p_credit_sale_id uuid, p_actor_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
            -- TRUNC, jamais ROUND (bloqueur 3, quatrième revue statique de 09) — voir migration 09
            -- pour le raisonnement complet, inchangé ici.
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

    -- CORRECTIF MIGRATION 11 : ajout de `WHERE true` — seule ligne modifiée par rapport à la version
    -- actuellement en production (migration 09). Cette instruction doit toucher TOUTES les lignes de
    -- la table temporaire _c09_pairs (répartition de gross_amount sur chaque paire de la vente en
    -- cours) ; elle a toujours été correcte fonctionnellement, mais syntaxiquement rejetée par
    -- l'extension pg-safeupdate (chargée pour le rôle `authenticator` utilisé par PostgREST, donc par
    -- tout appel RPC réel depuis l'application) qui exige une clause WHERE sur tout UPDATE/DELETE.
    -- `WHERE true` est le correctif idiomatique reconnu pour ce garde-fou : satisfait la contrainte
    -- syntaxique sans changer la sémantique (aucune ligne d'aucune autre vente ne peut jamais figurer
    -- dans cette table temporaire locale à l'appel).
    UPDATE _c09_pairs SET gross_amount = TRUNC((allocated_tco2e * weight_applied / v_total_weighted) * v_sale.net_distributable_amount, 2) WHERE true;

    SELECT sum(gross_amount) INTO v_sum_gross FROM _c09_pairs;
    v_remainder := v_sale.net_distributable_amount - v_sum_gross;

    SELECT organization_id, aggregator_id INTO v_max_gross_org, v_max_gross_agg FROM _c09_pairs
    ORDER BY allocated_tco2e DESC, organization_id ASC, aggregator_id ASC LIMIT 1;
    UPDATE _c09_pairs SET gross_amount = gross_amount + v_remainder
    WHERE organization_id = v_max_gross_org AND aggregator_id = v_max_gross_agg;

    -- ─── Étape B, seconde passe : fee/reserve/net exacts + INSERT.
    FOR v_pair IN SELECT * FROM _c09_pairs LOOP
        v_fee_amount := TRUNC(v_pair.gross_amount * v_pair.fee_pct / 100, 2);
        v_reserve_amount := TRUNC(v_pair.gross_amount * v_pair.reserve_pct / 100, 2);
        v_net_amount := v_pair.gross_amount - v_fee_amount - v_reserve_amount;

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

        INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, payload)
        VALUES
            ('credit_sale_allocation', v_alloc_revenue_id, 'credit_sale_allocation_recorded', p_actor_id, v_pair.organization_id, v_pair.aggregator_id,
             jsonb_build_object('credit_sale_id', p_credit_sale_id, 'allocation_type', 'carbon_revenue', 'gross_amount', v_pair.gross_amount, 'net_amount', v_net_amount)),
            ('credit_sale_allocation', v_alloc_reserve_id, 'credit_sale_allocation_recorded', p_actor_id, v_pair.organization_id, v_pair.aggregator_id,
             jsonb_build_object('credit_sale_id', p_credit_sale_id, 'allocation_type', 'reserve', 'net_amount', v_reserve_amount)),
            ('credit_sale_allocation', v_alloc_fee_id, 'credit_sale_allocation_recorded', p_actor_id, v_pair.organization_id, v_pair.aggregator_id,
             jsonb_build_object('credit_sale_id', p_credit_sale_id, 'allocation_type', 'platform_fee', 'net_amount', v_fee_amount));
    END LOOP;

    -- Vérification post-insertion de l'égalité comptable exacte (§17 point 9).
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
$function$;

COMMENT ON FUNCTION public.compute_credit_sale_allocations(uuid, uuid) IS
  'Migration 11 (carbone) — corrige un rejet réel par pg-safeupdate (rôle authenticator/PostgREST) sur l''UPDATE _c09_pairs sans WHERE (ajout de WHERE true, sémantique inchangée). Trouvé en test E2E live du Lot 3 (/admin/carbon-sales), 31 juillet 2026. Sinon identique à la version de la migration 09.';
