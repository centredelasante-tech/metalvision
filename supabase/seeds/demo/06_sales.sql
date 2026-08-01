-- ============================================================
-- SEED DÉMO METALVISION — 06. Vente de crédits carbone (Lot 3)
-- ============================================================
-- Prérequis : 01, 02, 04, 05 déjà appliqués (lot de 400 tCO2e disponible,
-- règle de distribution active pour le regroupement).
--
-- Contenu :
--   Une vente confirmée (400 tCO2e à 45 $CAD/tCO2e, coûts registre + vérification
--   déduits) menée jusqu'au statut 'confirmed' via les vraies RPC
--   (create_credit_sale -> add_credit_sale_lot -> add_credit_sale_cost x2 ->
--   confirm_credit_sale), ce qui déclenche compute_credit_sale_allocations()
--   et répartit le montant net entre les deux organisations contributrices
--   selon la règle de distribution active.
--
--   Volontairement laissée au statut 'confirmed' (pas 'settled') : l'étape
--   « Régler la vente » (settle_credit_sale) est laissée disponible comme
--   action à dérouler en direct pendant une démonstration (cf. livrable
--   « scénario pas à pas »). De même, le second lot de 200 tCO2e (créé en
--   04_issuances_and_lots.sql) reste 'available' — inventaire non vendu
--   pour illustrer l'état du marché.
-- ============================================================

DO $$
DECLARE
    v_operateur    UUID := 'a0000000-0000-4000-a000-000000000002';
    v_o_operateur  UUID := 'b0000000-0000-4000-a000-000000000001';
    v_lot_a_id     UUID;
    v_sale_id      UUID;
    v_buyer_ref    TEXT := 'Fonderie ABC — Acheteur externe (Démo)';
BEGIN
    SELECT cl.id INTO v_lot_a_id FROM public.credit_lots cl WHERE cl.quantity_tco2e = 400 AND cl.commercial_status = 'available' LIMIT 1;

    IF v_lot_a_id IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.credit_sales WHERE buyer_reference = v_buyer_ref) THEN
            RAISE NOTICE 'ℹ️  06_sales : vente démo déjà appliquée (lot de 400 tCO2e déjà réservé/vendu). Rien à faire.';
            RETURN;
        ELSE
            RAISE EXCEPTION 'Aucun lot disponible de 400 tCO2e — appliquer 04_issuances_and_lots.sql d''abord.';
        END IF;
    END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_operateur::text, 'role', 'authenticated')::text, false);

    SELECT public.create_credit_sale(v_o_operateur, 45.00, v_buyer_ref) INTO v_sale_id;

    PERFORM public.add_credit_sale_lot(v_sale_id, v_lot_a_id);
    PERFORM public.add_credit_sale_cost(v_sale_id, 'registry_fee', 200.00, 'Frais d''enregistrement au registre carbone (démo)', 'Registre Carbone Démo Québec');
    PERFORM public.add_credit_sale_cost(v_sale_id, 'verification_fee', 300.00, 'Frais de vérification MRV (démo)', 'Vérificateur Accrédité Démo');

    PERFORM public.confirm_credit_sale(v_sale_id);

    RAISE NOTICE '✅ 06_sales appliqué : vente % confirmée (400 tCO2e, 45 $/tCO2e, allocations calculées).', v_sale_id;
END $$;
