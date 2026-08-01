-- ============================================================
-- SEED DÉMO METALVISION — 02. Organisations, regroupement, opérateur
-- ============================================================
-- Prérequis : 01_users_and_roles.sql déjà appliqué.
--
-- Contenu :
--   - 3 organisations (Opérateur METALTRACE, Aciérie Boréale, RecyclMétal Estrie)
--   - organization_members (admin de chacune)
--   - 1 regroupement carbone (aggregator) via create_aggregator_with_primary_admin()
--   - désignation de l'opérateur plateforme via designate_platform_operator()
--   - adhésions des 2 organisations membres au regroupement via join_aggregator()
--   - mandats de commercialisation carbone (organisation -> opérateur) via
--     grant_commercialization_mandate()
--
-- Ce fichier appelle les vraies RPC métier (pas des INSERT bruts) pour les
-- opérations à logique non triviale, en simulant l'identité de l'acteur via
-- `set_config('request.jwt.claims', ...)` — cela déclenche exactement le
-- même chemin de code que l'application réelle (mêmes triggers, mêmes
-- écritures dans carbon_business_events), contrairement à un simple INSERT.
-- Idempotent : réexécutable sans erreur (gardes IF NOT EXISTS avant chaque RPC).
-- ============================================================

DO $$
DECLARE
    v_superadmin   UUID := 'a0000000-0000-4000-a000-000000000001';
    v_operateur    UUID := 'a0000000-0000-4000-a000-000000000002';
    v_aggregateur  UUID := 'a0000000-0000-4000-a000-000000000003';
    v_producteur   UUID := 'a0000000-0000-4000-a000-000000000004';
    v_recycleur    UUID := 'a0000000-0000-4000-a000-000000000005';

    v_o_operateur  UUID := 'b0000000-0000-4000-a000-000000000001';
    v_o_aciérie    UUID := 'b0000000-0000-4000-a000-000000000002';
    v_o_recycleur  UUID := 'b0000000-0000-4000-a000-000000000003';

    v_agg_name     TEXT := 'Regroupement Sidérurgique Laurentides (Démo)';
    v_agg_id       UUID;
    v_membership_aciérie   UUID;
    v_membership_recycleur UUID;
    v_full_scope   TEXT[] := ARRAY[
        'aggregate_reductions','submit_for_verification','request_issuance',
        'administer_credits','sell_credits','collect_sale_proceeds',
        'deduct_approved_costs','distribute_net_proceeds'
    ];
BEGIN
    -- ── 1. Organisations ──────────────────────────────────────────────
    INSERT INTO public.organizations (id, name, type, status, region, maturity_level, primary_contact_email)
    VALUES
        (v_o_operateur, 'Opérateur MetalTrace (Démo)', 'operateur', 'active',
         'Québec (Provincial)', 'avancé', 'operateur@demo.metaltrace.ca'),
        (v_o_aciérie, 'Aciérie Boréale Inc. (Démo)', 'manufacturier', 'active',
         'Laurentides', 'avancé', 'producteur@demo.metaltrace.ca'),
        (v_o_recycleur, 'RecyclMétal Estrie (Démo)', 'recycleur', 'active',
         'Estrie', 'intermédiaire', 'recycleur@demo.metaltrace.ca')
    ON CONFLICT (id) DO NOTHING;

    -- ── 2. Rattachement admin (organization_members) ────────────────────
    -- handle_new_organization_admin() ne se déclenche qu'en présence d'un
    -- auth.uid() réel (contexte PostgREST) — en SQL direct il faut insérer
    -- ces lignes manuellement (cf. rapport d'exploration du schéma).
    INSERT INTO public.organization_members (id, organization_id, user_id, org_role, status, operational_profile, activated_at)
    VALUES
        ('c0000000-0000-4000-a000-000000000001', v_o_operateur, v_operateur, 'admin', 'active', 'bureau', now()),
        ('c0000000-0000-4000-a000-000000000002', v_o_aciérie, v_producteur, 'admin', 'active', 'bureau', now()),
        ('c0000000-0000-4000-a000-000000000003', v_o_recycleur, v_recycleur, 'admin', 'active', 'bureau', now())
    ON CONFLICT (id) DO NOTHING;

    -- ── 3. Regroupement + opérateur plateforme (acteur : superadmin) ────
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_superadmin::text, 'role', 'authenticated',
                           'app_metadata', json_build_object('role','admin'))::text,
        false);

    IF NOT EXISTS (SELECT 1 FROM public.aggregators WHERE name = v_agg_name) THEN
        PERFORM public.create_aggregator_with_primary_admin(
            v_agg_name,
            'Regroupement de démonstration réunissant des producteurs d''acier et de métaux recyclés des Laurentides et de l''Estrie.',
            v_aggregateur
        );
    END IF;
    SELECT id INTO v_agg_id FROM public.aggregators WHERE name = v_agg_name;

    IF NOT EXISTS (SELECT 1 FROM public.platform_operators WHERE organization_id = v_o_operateur AND revoked_at IS NULL) THEN
        PERFORM public.designate_platform_operator(v_o_operateur);
    END IF;

    -- ── 4. Adhésions au regroupement (acteur : admin du regroupement) ───
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_aggregateur::text, 'role', 'authenticated')::text, false);

    IF NOT EXISTS (SELECT 1 FROM public.aggregator_memberships WHERE organization_id = v_o_aciérie AND ended_at IS NULL) THEN
        SELECT public.join_aggregator(v_o_aciérie, v_agg_id) INTO v_membership_aciérie;
    ELSE
        SELECT id INTO v_membership_aciérie FROM public.aggregator_memberships WHERE organization_id = v_o_aciérie AND ended_at IS NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.aggregator_memberships WHERE organization_id = v_o_recycleur AND ended_at IS NULL) THEN
        SELECT public.join_aggregator(v_o_recycleur, v_agg_id) INTO v_membership_recycleur;
    ELSE
        SELECT id INTO v_membership_recycleur FROM public.aggregator_memberships WHERE organization_id = v_o_recycleur AND ended_at IS NULL;
    END IF;

    -- ── 5. Mandats de commercialisation carbone (acteur : admin de chaque
    -- organisation membre, portée complète — administration + vente +
    -- distribution) ───────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_producteur::text, 'role', 'authenticated')::text, false);

    IF NOT EXISTS (
        SELECT 1 FROM public.carbon_commercialization_mandates
        WHERE organization_id = v_o_aciérie AND operator_organization_id = v_o_operateur AND revoked_at IS NULL
    ) THEN
        PERFORM public.grant_commercialization_mandate(v_membership_aciérie, v_o_operateur, v_full_scope, NULL);
    END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_recycleur::text, 'role', 'authenticated')::text, false);

    IF NOT EXISTS (
        SELECT 1 FROM public.carbon_commercialization_mandates
        WHERE organization_id = v_o_recycleur AND operator_organization_id = v_o_operateur AND revoked_at IS NULL
    ) THEN
        PERFORM public.grant_commercialization_mandate(v_membership_recycleur, v_o_operateur, v_full_scope, NULL);
    END IF;

    RAISE NOTICE '✅ 02_organizations appliqué : regroupement %, opérateur désigné, 2 adhésions, 2 mandats.', v_agg_id;
END $$;
