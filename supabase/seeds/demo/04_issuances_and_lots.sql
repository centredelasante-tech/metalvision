-- ============================================================
-- SEED DÉMO METALVISION — 04. Émission et lots de crédits carbone
-- ============================================================
-- Prérequis : 01, 02, 03 déjà appliqués (résultat de vérification actif requis).
--
-- Contenu (Lot 3) :
--   - 1 credit_issuance (600 tCO2e, sources Aciérie Boréale 450 + RecyclMétal
--     Estrie 150), menée jusqu'au statut 'issued' (chaîne complète du cycle
--     de vie via les RPC : create -> mark_eligible -> submit -> record_registry_issuance)
--   - 2 credit_lots issus de cette émission : un lot de 400 tCO2e (destiné à
--     la vente dans 06_sales.sql) et un lot de 200 tCO2e laissé 'available'
--     (stock non vendu, pour démontrer l'inventaire disponible en démo)
--
-- Acteur pour toutes les étapes : operateur@demo.metaltrace.ca (admin de
-- l'organisation opératrice METALTRACE désignée).
-- ============================================================

DO $$
DECLARE
    v_operateur     UUID := 'a0000000-0000-4000-a000-000000000002';
    v_o_aciérie     UUID := 'b0000000-0000-4000-a000-000000000002';
    v_o_recycleur   UUID := 'b0000000-0000-4000-a000-000000000003';
    v_verif_session UUID := 'e0000000-0000-4000-a000-000000000007';

    v_membership_aciérie   UUID;
    v_membership_recycleur UUID;
    v_mandate_aciérie      UUID;
    v_mandate_recycleur    UUID;
    v_outcome_id    UUID;
    v_issuance_id   UUID;
    v_lot_a_id      UUID;
    v_lot_b_id      UUID;
BEGIN
    SELECT id INTO v_outcome_id FROM public.verification_outcomes
    WHERE verification_session_id = v_verif_session AND status = 'active';

    IF v_outcome_id IS NULL THEN
        RAISE EXCEPTION 'Aucun verification_outcomes actif trouvé — appliquer 03_projects_and_verification.sql d''abord.';
    END IF;

    SELECT id INTO v_membership_aciérie FROM public.aggregator_memberships WHERE organization_id = v_o_aciérie AND ended_at IS NULL;
    SELECT id INTO v_membership_recycleur FROM public.aggregator_memberships WHERE organization_id = v_o_recycleur AND ended_at IS NULL;
    SELECT id INTO v_mandate_aciérie FROM public.carbon_commercialization_mandates WHERE organization_id = v_o_aciérie AND revoked_at IS NULL;
    SELECT id INTO v_mandate_recycleur FROM public.carbon_commercialization_mandates WHERE organization_id = v_o_recycleur AND revoked_at IS NULL;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_operateur::text, 'role', 'authenticated')::text, false);

    IF NOT EXISTS (SELECT 1 FROM public.credit_issuances WHERE verification_outcome_id = v_outcome_id) THEN
        SELECT public.create_credit_issuance(
            v_outcome_id,
            jsonb_build_array(
                jsonb_build_object(
                    'organization_id', v_o_aciérie,
                    'aggregator_membership_id', v_membership_aciérie,
                    'commercialization_mandate_id', v_mandate_aciérie,
                    'contributed_tco2e', 450
                ),
                jsonb_build_object(
                    'organization_id', v_o_recycleur,
                    'aggregator_membership_id', v_membership_recycleur,
                    'commercialization_mandate_id', v_mandate_recycleur,
                    'contributed_tco2e', 150
                )
            )
        ) INTO v_issuance_id;

        PERFORM public.mark_credit_issuance_eligible(v_issuance_id);
        PERFORM public.submit_credit_issuance(v_issuance_id, 'Registre Carbone Démo Québec');
        PERFORM public.record_registry_issuance(v_issuance_id, 'DEMO-REG-2026-0001', now());
    ELSE
        SELECT id INTO v_issuance_id FROM public.credit_issuances WHERE verification_outcome_id = v_outcome_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.credit_lots WHERE credit_issuance_id = v_issuance_id) THEN
        SELECT public.issue_credit_lot(v_issuance_id, 400, EXTRACT(YEAR FROM CURRENT_DATE)::int) INTO v_lot_a_id;
        SELECT public.issue_credit_lot(v_issuance_id, 200, EXTRACT(YEAR FROM CURRENT_DATE)::int) INTO v_lot_b_id;
    END IF;

    RAISE NOTICE '✅ 04_issuances_and_lots appliqué : émission %, lots créés (400 + 200 tCO2e).', v_issuance_id;
END $$;
