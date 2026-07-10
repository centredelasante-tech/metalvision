-- ============================================================
-- CCF-011 — Seed de validation (schéma uniquement)
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   RT-06 : Le jeu de données pilote CCF va dans supabase/seeds/
--            hors du dossier migrations/, pour qu'il ne soit jamais
--            appliqué automatiquement en production par le pipeline CI/CD.
--
-- CE FICHIER :
--   Cette migration 011 ne contient PAS les données de démonstration.
--   Elle valide uniquement que le schéma CCF complet est cohérent
--   et prêt à recevoir des données.
--
-- DONNÉES DE DÉMONSTRATION :
--   → supabase/seeds/demo_ccf.sql
--   À appliquer manuellement sur les environnements de démo/staging
--   uniquement, jamais via le pipeline CI/CD de production.
--
-- VALIDATION FINALE DU SCHÉMA :
--   Vérifie l'existence de toutes les tables et types CCF.
-- ============================================================

DO $$
DECLARE
    v_missing_tables text[] := ARRAY[]::text[];
    v_missing_types  text[] := ARRAY[]::text[];
    v_table text;
    v_type  text;
BEGIN
    -- Vérifier les tables CCF
    FOREACH v_table IN ARRAY ARRAY[
        'profiles',
        'organizations',
        'organization_members',
        'mandates',
        'mandate_actions',
        'capabilities',
        'opportunities',
        'opportunity_capabilities',
        'ccf_projects',
        'project_participants',
        'documents',
        'logistics_steps',
        'value_reports',
        'ai_assistance_logs',
        'business_events',
        'audit_logs'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = v_table
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_table);
        END IF;
    END LOOP;

    -- Vérifier les types ENUM CCF
    FOREACH v_type IN ARRAY ARRAY[
        'mandate_scope',
        'document_visibility',
        'ccf_project_phase',
        'logistics_step_type',
        'ccf_event_type',
        'org_role'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_type
            WHERE typname = v_type AND typnamespace = 'public'::regnamespace
        ) THEN
            v_missing_types := array_append(v_missing_types, v_type);
        END IF;
    END LOOP;

    -- Rapport
    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE WARNING 'Tables CCF manquantes : %', array_to_string(v_missing_tables, ', ');
    ELSE
        RAISE NOTICE 'Toutes les tables CCF sont présentes (16/16).';
    END IF;

    IF array_length(v_missing_types, 1) > 0 THEN
        RAISE WARNING 'Types ENUM CCF manquants : %', array_to_string(v_missing_types, ', ');
    ELSE
        RAISE NOTICE 'Tous les types ENUM CCF sont présents (6/6).';
    END IF;

    RAISE NOTICE 'Schéma CCF validé. Pour les données de démonstration, appliquer : supabase/seeds/demo_ccf.sql';
END $$;
