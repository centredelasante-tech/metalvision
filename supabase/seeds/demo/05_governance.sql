-- ============================================================
-- SEED DÉMO METALVISION — 05. Gouvernance : règle de distribution (Lot 2)
-- ============================================================
-- Prérequis : 01, 02 déjà appliqués (regroupement + opérateur désignés).
--
-- Contenu :
--   Une proposition de règle de distribution pour le regroupement
--   (frais plateforme 10 %, réserve 5 %, poids par défaut 1.0), approuvée
--   par le double circuit exigé (admin du regroupement + admin de
--   l'opérateur), ce qui déclenche son activation automatique
--   (carbon_try_activate_distribution_rule_proposal). Cette règle active
--   est un préalable obligatoire à confirm_credit_sale() dans
--   06_sales.sql (compute_credit_sale_allocations() échoue sans règle
--   active pour le regroupement à la date de confirmation).
-- ============================================================

DO $$
DECLARE
    v_operateur    UUID := 'a0000000-0000-4000-a000-000000000002';
    v_aggregateur  UUID := 'a0000000-0000-4000-a000-000000000003';
    v_agg_id       UUID;
    v_proposal_id  UUID;
BEGIN
    SELECT id INTO v_agg_id FROM public.aggregators WHERE name = 'Regroupement Sidérurgique Laurentides (Démo)';
    IF v_agg_id IS NULL THEN
        RAISE EXCEPTION 'Regroupement démo introuvable — appliquer 02_organizations.sql d''abord.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.distribution_rules WHERE aggregator_id = v_agg_id AND effective_to IS NULL) THEN
        PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_aggregateur::text, 'role', 'authenticated')::text, false);

        SELECT public.propose_distribution_rule(v_agg_id, 10.0, 5.0, 1.0) INTO v_proposal_id;

        PERFORM public.approve_distribution_rule_as_aggregator_admin(v_proposal_id);

        PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_operateur::text, 'role', 'authenticated')::text, false);
        PERFORM public.approve_distribution_rule_as_operator_admin(v_proposal_id);
    END IF;

    RAISE NOTICE '✅ 05_governance appliqué : règle de distribution active pour le regroupement % (frais 10%%, réserve 5%%).', v_agg_id;
END $$;
