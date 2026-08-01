-- ============================================================
-- SEED DÉMO METALVISION — 03. Projets CCF + cycle de vérification MRV
-- ============================================================
-- Prérequis : 01_users_and_roles.sql et 02_organizations.sql déjà appliqués.
--
-- Contenu :
--   Lot 1 (CCF) : opportunity, ccf_project, capabilities, project_participants,
--     mandate CCF générique (Aciérie Boréale coordinateur -> RecyclMétal Estrie)
--   Lot 3 (MRV -> carbone) : companies/projects legacy, project_activity_logs,
--     verification_sessions (planned -> in_progress -> completed via RPC),
--     evidence_files (preuve de vérification), verification_outcomes,
--     ccf_mrv_project_links (rattachement du projet CCF au projet MRV legacy)
--
-- Le cycle de vérification est déroulé via les vraies RPC
-- (plan_verification_session / start_verification_session /
-- record_verification_report_evidence / complete_verification_session) en
-- impersonnant successivement le superadmin puis le vérificateur assigné,
-- afin de produire un verification_outcomes cohérent et un historique
-- carbon_business_events réaliste, exploitable par 04_issuances_and_lots.sql.
-- ============================================================

DO $$
DECLARE
    v_superadmin    UUID := 'a0000000-0000-4000-a000-000000000001';
    v_producteur    UUID := 'a0000000-0000-4000-a000-000000000004';
    v_recycleur     UUID := 'a0000000-0000-4000-a000-000000000005';
    v_verificateur  UUID := 'a0000000-0000-4000-a000-000000000006';

    v_o_aciérie     UUID := 'b0000000-0000-4000-a000-000000000002';
    v_o_recycleur   UUID := 'b0000000-0000-4000-a000-000000000003';

    -- Lot 1 — CCF
    v_opportunity   UUID := 'f0000000-0000-4000-a000-000000000001';
    v_ccf_project   UUID := 'f0000000-0000-4000-a000-000000000002';
    v_cap_acier     UUID := 'f0000000-0000-4000-a000-000000000003';
    v_cap_cuivre    UUID := 'f0000000-0000-4000-a000-000000000004';
    v_part_aciérie  UUID := 'f0000000-0000-4000-a000-000000000005';
    v_part_recycleur UUID := 'f0000000-0000-4000-a000-000000000006';
    v_ccf_mandate   UUID := 'f0000000-0000-4000-a000-000000000007';

    -- Lot 3 — MRV legacy + vérification
    v_company       UUID := 'e0000000-0000-4000-a000-000000000001';
    v_legacy_project UUID := 'e0000000-0000-4000-a000-000000000003';
    v_verif_session UUID := 'e0000000-0000-4000-a000-000000000007';
    v_link          UUID := 'e0000000-0000-4000-a000-000000000008';
    v_evidence_id   UUID;
    v_outcome_id    UUID;

    v_period_start  DATE := (CURRENT_DATE - INTERVAL '6 months')::date;
    v_period_end    DATE := (CURRENT_DATE - INTERVAL '1 month')::date;
BEGIN
    -- ════════════════════════════════════════════════════════
    -- LOT 1 — CCF
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.opportunities (id, title, description, coordinator_org_id, region, target_volume, priority, status)
    VALUES (
        v_opportunity,
        'Consolidation ferroviaire — Métaux ferreux et non-ferreux (Démo)',
        'Opportunité de démonstration : consolidation de chargements de métaux ferreux et non-ferreux '
        'pour expédition ferroviaire vers les fonderies régionales. Volume cible : 60 tonnes métriques.',
        v_o_aciérie, 'Laurentides-Estrie', 60.0, 'haute', 'converted'
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id, phase, status, start_date, target_end_date)
    VALUES (
        v_ccf_project, v_opportunity,
        'Projet CCF Démo — Consolidation ferroviaire Laurentides-Estrie',
        v_o_aciérie, 'execution', 'active',
        now() - INTERVAL '90 days', now() + INTERVAL '30 days'
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.capabilities (id, organization_id, material_type, monthly_volume, location, availability, maturity, status)
    VALUES
        (v_cap_acier, v_o_aciérie, 'acier_ferreux', 45.0, 'Saint-Jérôme, QC', 'mensuelle', 'qualifié', 'qualified'),
        (v_cap_cuivre, v_o_recycleur, 'cuivre', 8.0, 'Sherbrooke, QC', 'mensuelle', 'qualifié', 'qualified')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.mandates (id, issuer_org_id, receiver_org_id, mandate_scope, permissions, status, start_date)
    VALUES (
        v_ccf_mandate, v_o_aciérie, v_o_recycleur, 'operationnel',
        '{"actions": ["read_capabilities", "accept_project_invitation", "submit_logistics_proof", "update_logistics_step"]}'::jsonb,
        'active', now() - INTERVAL '90 days'
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.project_participants (id, project_id, organization_id, project_role, mandate_id, status)
    VALUES
        (v_part_aciérie, v_ccf_project, v_o_aciérie, 'coordonnateur', NULL, 'active'),
        (v_part_recycleur, v_ccf_project, v_o_recycleur, 'contributeur', v_ccf_mandate, 'active')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- LOT 3 — Cycle MRV : entreprise/projet legacy + journaux d'activité
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.companies (id, name, created_at)
    VALUES (v_company, 'Aciérie Boréale Inc. (Démo)', now() - INTERVAL '90 days')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.projects (id, client_id, name, description, baseline_description,
                                  project_scenario_description, start_date, end_date, status, created_at)
    VALUES (
        v_legacy_project, v_company,
        'Projet MRV Démo — Réduction GES Aciérie Boréale',
        'Suivi MRV de démonstration des réductions d''émissions liées à la substitution de ferraille '
        'recyclée dans le procédé de fabrication d''acier.',
        'Scénario de référence : approvisionnement 100% minerai vierge.',
        'Scénario projet : substitution progressive par ferraille recyclée régionale (consolidation CCF).',
        (CURRENT_DATE - INTERVAL '6 months')::date, (CURRENT_DATE - INTERVAL '1 month')::date,
        'verified', now() - INTERVAL '90 days'
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.project_activity_logs (
        id, project_id, activity_type, ghg_emissions_baseline_kgco2e, ghg_emissions_project_kgco2e,
        ghg_reduction_kgco2e, uncertainty_percent, "timestamp", actor_id
    ) VALUES
        ('e0000000-0000-4000-a000-000000000004', v_legacy_project, 'consolidation_ferroviaire',
         820000, 420000, 400000, 5.0, (v_period_start + INTERVAL '30 days'), v_producteur),
        ('e0000000-0000-4000-a000-000000000005', v_legacy_project, 'consolidation_ferroviaire',
         410000, 190000, 220000, 5.0, (v_period_start + INTERVAL '90 days'), v_producteur)
    ON CONFLICT (id) DO NOTHING;
    -- Somme ghg_reduction_kgco2e = 620 000 kg = 620 tCO2e sur la période.

    INSERT INTO public.ccf_mrv_project_links (id, ccf_project_id, mrv_project_id, started_at, started_by)
    VALUES (v_link, v_ccf_project, v_legacy_project, now() - INTERVAL '90 days', v_superadmin)
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- Cycle de vérification (session -> évidence -> clôture)
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.verification_sessions (id, project_id, verifier_org, verifier_contact, scope, status, created_at)
    VALUES (
        v_verif_session, v_legacy_project, 'Vérificateur Accrédité Démo', 'verificateur@demo.metaltrace.ca',
        '{"norme": "ISO 14064-3 (démonstration)", "portee": "Réductions GES — consolidation ferroviaire"}'::jsonb,
        'planned', now() - INTERVAL '85 days'
    ) ON CONFLICT (id) DO NOTHING;

    IF NOT EXISTS (SELECT 1 FROM public.verification_outcomes WHERE verification_session_id = v_verif_session) THEN
        -- Planification (acteur : superadmin plateforme, couvre is_project_admin()/is_platform_superadmin())
        PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_superadmin::text, 'role', 'authenticated',
                               'app_metadata', json_build_object('role','admin'))::text,
            false);
        PERFORM public.plan_verification_session(v_verif_session, v_period_start, v_period_end, v_verificateur);

        -- Démarrage + preuve + clôture (acteur : vérificateur accrédité assigné)
        PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_verificateur::text, 'role', 'authenticated')::text, false);
        PERFORM public.start_verification_session(v_verif_session);

        SELECT public.record_verification_report_evidence(
            v_verif_session,
            'https://storage.demo.metaltrace.ca/verification-evidence/rapport-verification-demo.pdf',
            'sha256:demo0000000000000000000000000000000000000000000000000000000001'
        ) INTO v_evidence_id;

        PERFORM public.complete_verification_session(
            v_verif_session,
            620.0,   -- p_verified_reduction_tco2e (= somme des journaux d'activité, aucun écart)
            600.0,   -- p_eligible_tco2e (marge de prudence de 20 tCO2e sur le vérifié)
            v_evidence_id,
            'Réserve de prudence de 20 tCO2e appliquée par le vérificateur (incertitude méthodologique, démonstration).'
        );
    END IF;

    SELECT id INTO v_outcome_id FROM public.verification_outcomes WHERE verification_session_id = v_verif_session AND status = 'active';

    RAISE NOTICE '✅ 03_projects_and_verification appliqué : projet CCF %, session de vérification %, résultat %.',
        v_ccf_project, v_verif_session, v_outcome_id;
END $$;
