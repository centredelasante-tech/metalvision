-- ============================================================
-- SEED DE DÉMONSTRATION CCF — Pilote Centre de Consolidation Ferroviaire
-- ============================================================
--
-- ⚠️  ENVIRONNEMENT DE DÉMO / STAGING UNIQUEMENT ⚠️
--
-- Ce fichier NE DOIT PAS être appliqué en production.
-- Il est placé dans supabase/seeds/ (hors migrations/) pour
-- qu'il ne soit jamais exécuté automatiquement par le pipeline
-- CI/CD standard (RT-06).
--
-- APPLICATION MANUELLE :
--   psql $DATABASE_URL -f supabase/seeds/demo_ccf.sql
--   ou via le dashboard Supabase → SQL Editor
--
-- CONTENU :
--   3 organisations pilotes CCF
--   3 capacités (une par organisation)
--   1 opportunité de consolidation ferroviaire
--   1 projet CCF actif
--   Mandats inter-organisations
--   Participants au projet
--   Étapes logistiques
--   1 rapport de valeur
--   Événements métier de démonstration
--
-- PRÉREQUIS :
--   Migrations CCF-001 à CCF-011 appliquées.
--   Au moins 3 utilisateurs auth.users existants (ou créer via Supabase Auth).
-- ============================================================

DO $$
DECLARE
    -- UUIDs des organisations
    v_org_coordinateur  UUID := gen_random_uuid();
    v_org_manufacturier UUID := gen_random_uuid();
    v_org_recycleur     UUID := gen_random_uuid();

    -- UUIDs des capacités
    v_cap_acier         UUID := gen_random_uuid();
    v_cap_aluminium     UUID := gen_random_uuid();
    v_cap_cuivre        UUID := gen_random_uuid();

    -- UUIDs de l'opportunité et du projet
    v_opportunite       UUID := gen_random_uuid();
    v_projet            UUID := gen_random_uuid();

    -- UUIDs des mandats
    v_mandat_coord_manuf UUID := gen_random_uuid();
    v_mandat_coord_recyp UUID := gen_random_uuid();

    -- UUIDs des participants
    v_participant_manuf UUID := gen_random_uuid();
    v_participant_recyp UUID := gen_random_uuid();

    -- UUIDs des étapes logistiques
    v_etape_ramassage   UUID := gen_random_uuid();
    v_etape_chargement  UUID := gen_random_uuid();
    v_etape_livraison   UUID := gen_random_uuid();

    -- UUID du rapport de valeur
    v_rapport           UUID := gen_random_uuid();

    -- UUID du lien opportunité-capacité
    v_opp_cap_acier     UUID := gen_random_uuid();
    v_opp_cap_aluminium UUID := gen_random_uuid();

BEGIN

    -- ════════════════════════════════════════════════════════
    -- 1. ORGANISATIONS
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.organizations (id, name, type, status, region, maturity_level, primary_contact_email)
    VALUES
        (v_org_coordinateur,
         'Centre de Consolidation Ferroviaire Québec',
         'coordinateur',
         'active',
         'Montréal-Métropolitain',
         'avancé',
         'coordination@ccf-quebec.ca'),

        (v_org_manufacturier,
         'Acier Laurentien Inc.',
         'manufacturier',
         'active',
         'Laurentides',
         'intermédiaire',
         'operations@acier-laurentien.ca'),

        (v_org_recycleur,
         'RecyclMétal Estrie',
         'recycleur',
         'active',
         'Estrie',
         'débutant',
         'info@recyclmetal-estrie.ca')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- 2. CAPACITÉS
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.capabilities (id, organization_id, material_type, monthly_volume, location, availability, maturity, status)
    VALUES
        (v_cap_acier,
         v_org_manufacturier,
         'acier_ferreux',
         45.0,
         'Saint-Jérôme, QC',
         'mensuelle',
         'qualifié',
         'qualified'),

        (v_cap_aluminium,
         v_org_manufacturier,
         'aluminium',
         12.5,
         'Saint-Jérôme, QC',
         'trimestrielle',
         'déclaré',
         'declared'),

        (v_cap_cuivre,
         v_org_recycleur,
         'cuivre',
         8.0,
         'Sherbrooke, QC',
         'mensuelle',
         'qualifié',
         'qualified')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- 3. OPPORTUNITÉ
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.opportunities (id, title, description, coordinator_org_id, region, target_volume, priority, status)
    VALUES
        (v_opportunite,
         'Consolidation ferroviaire — Métaux ferreux et non-ferreux Q3 2026',
         'Opportunité de consolidation de chargements de métaux ferreux et non-ferreux '
         'pour expédition ferroviaire vers les fonderies de la région de Québec. '
         'Volume cible : 65 tonnes métriques. Corridor : Laurentides → Estrie → Québec.',
         v_org_coordinateur,
         'Québec',
         65.0,
         'haute',
         'qualified')
    ON CONFLICT (id) DO NOTHING;

    -- Liens opportunité-capacités
    INSERT INTO public.opportunity_capabilities (id, opportunity_id, capability_id, fit_score, status)
    VALUES
        (v_opp_cap_acier,     v_opportunite, v_cap_acier,     92.0, 'active'),
        (v_opp_cap_aluminium, v_opportunite, v_cap_aluminium, 78.0, 'active')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- 4. MANDATS
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.mandates (id, issuer_org_id, receiver_org_id, mandate_scope, permissions, status)
    VALUES
        (v_mandat_coord_manuf,
         v_org_coordinateur,
         v_org_manufacturier,
         'operationnel',
         '{"actions": ["read_capabilities", "invite_project_org", "manage_project_participants", "submit_logistics_proof", "update_logistics_step"]}'::jsonb,
         'active'),

        (v_mandat_coord_recyp,
         v_org_coordinateur,
         v_org_recycleur,
         'operationnel',
         '{"actions": ["read_capabilities", "accept_project_invitation", "submit_logistics_proof", "update_logistics_step"]}'::jsonb,
         'active')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- 5. PROJET CCF
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id, phase, status, start_date, target_end_date)
    VALUES
        (v_projet,
         v_opportunite,
         'Projet CCF-2026-Q3 — Consolidation ferroviaire Laurentides-Estrie',
         v_org_coordinateur,
         'execution',
         'active',
         now() - INTERVAL '15 days',
         now() + INTERVAL '45 days')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- 6. PARTICIPANTS AU PROJET
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.project_participants (id, project_id, organization_id, project_role, mandate_id, status)
    VALUES
        (v_participant_manuf,
         v_projet,
         v_org_manufacturier,
         'contributeur',
         v_mandat_coord_manuf,
         'active'),

        (v_participant_recyp,
         v_projet,
         v_org_recycleur,
         'contributeur',
         v_mandat_coord_recyp,
         'active')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- 7. ÉTAPES LOGISTIQUES
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.logistics_steps (id, project_id, step_type, responsible_org_id, planned_date, status)
    VALUES
        (v_etape_ramassage,
         v_projet,
         'ramassage',
         v_org_manufacturier,
         now() - INTERVAL '10 days',
         'completed'),

        (v_etape_chargement,
         v_projet,
         'chargement',
         v_org_coordinateur,
         now() - INTERVAL '5 days',
         'completed'),

        (v_etape_livraison,
         v_projet,
         'livraison',
         v_org_recycleur,
         now() + INTERVAL '10 days',
         'planned')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- 8. RAPPORT DE VALEUR
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.value_reports (id, project_id, volume, coordination_value, notes, status)
    VALUES
        (v_rapport,
         v_projet,
         57.5,
         12800.00,
         'Rapport préliminaire de valeur créée. Volume consolidé : 57,5 t. '
         'Économies logistiques estimées : 12 800 $. '
         'Réduction GES estimée : 4,2 tCO2e vs transport routier individuel.',
         'draft')
    ON CONFLICT (id) DO NOTHING;

    -- ════════════════════════════════════════════════════════
    -- 9. ÉVÉNEMENTS MÉTIER DE DÉMONSTRATION
    -- ════════════════════════════════════════════════════════

    INSERT INTO public.business_events (event_type, object_type, object_id, organization_id, payload)
    VALUES
        ('organization_created', 'organization', v_org_coordinateur, v_org_coordinateur,
         jsonb_build_object('name', 'Centre de Consolidation Ferroviaire Québec', 'source', 'demo_seed')),

        ('organization_created', 'organization', v_org_manufacturier, v_org_manufacturier,
         jsonb_build_object('name', 'Acier Laurentien Inc.', 'source', 'demo_seed')),

        ('organization_created', 'organization', v_org_recycleur, v_org_recycleur,
         jsonb_build_object('name', 'RecyclMétal Estrie', 'source', 'demo_seed')),

        ('capability_qualified', 'capability', v_cap_acier, v_org_manufacturier,
         jsonb_build_object('material_type', 'acier_ferreux', 'monthly_volume', 45.0, 'source', 'demo_seed')),

        ('opportunity_qualified', 'opportunity', v_opportunite, v_org_coordinateur,
         jsonb_build_object('title', 'Consolidation ferroviaire Q3 2026', 'source', 'demo_seed')),

        ('project_created', 'project', v_projet, v_org_coordinateur,
         jsonb_build_object('title', 'Projet CCF-2026-Q3', 'source', 'demo_seed')),

        ('project_phase_changed', 'project', v_projet, v_org_coordinateur,
         jsonb_build_object('from', 'active', 'to', 'execution', 'source', 'demo_seed')),

        ('mandate_issued', 'mandate', v_mandat_coord_manuf, v_org_coordinateur,
         jsonb_build_object('receiver', 'Acier Laurentien Inc.', 'source', 'demo_seed')),

        ('mandate_accepted', 'mandate', v_mandat_coord_manuf, v_org_manufacturier,
         jsonb_build_object('source', 'demo_seed')),

        ('logistics_step_updated', 'logistics_step', v_etape_ramassage, v_org_manufacturier,
         jsonb_build_object('step_type', 'ramassage', 'new_status', 'completed', 'source', 'demo_seed')),

        ('value_report_generated', 'value_report', v_rapport, v_org_coordinateur,
         jsonb_build_object('volume', 57.5, 'coordination_value', 12800.00, 'source', 'demo_seed'))
    ON CONFLICT DO NOTHING;

    RAISE NOTICE '✅ Seed CCF appliqué avec succès.';
    RAISE NOTICE '   Organisations : 3 (coordinateur, manufacturier, recycleur)';
    RAISE NOTICE '   Capacités     : 3 (acier, aluminium, cuivre)';
    RAISE NOTICE '   Opportunité   : 1 (consolidation ferroviaire Q3 2026)';
    RAISE NOTICE '   Projet CCF    : 1 (CCF-2026-Q3, phase execution)';
    RAISE NOTICE '   Mandats       : 2 (coordinateur → manufacturier, coordinateur → recycleur)';
    RAISE NOTICE '   Étapes log.   : 3 (ramassage ✓, chargement ✓, livraison planifiée)';
    RAISE NOTICE '   Rapport valeur: 1 (draft, 57.5t, 12 800$)';
    RAISE NOTICE '   Événements    : 11 événements métier de démonstration';

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Erreur lors de l''application du seed CCF : %', SQLERRM;
        RAISE WARNING 'Vérifiez que les migrations CCF-001 à CCF-011 ont été appliquées.';
END $$;
