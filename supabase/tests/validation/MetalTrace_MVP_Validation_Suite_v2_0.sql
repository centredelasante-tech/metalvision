-- ============================================================
-- MetalTrace CCF — Suite de validation v2
-- ============================================================
--
-- Remplace MetalTrace_MVP_Validation_Suite_v1_0.sql, mentionnée dans
-- ADR-MVP.md §10 (63/63 assertions) mais jamais committée dans le dépôt —
-- reconstruite ici pour le gel de la version démo (voir ADR-MVP.md,
-- section gel).
--
-- À exécuter dans le SQL Editor Supabase (rôle postgres).
--
-- STRUCTURE :
--   - Une table de résultats PERMANENTE (public._ccf_validation_results),
--     pas une TEMP TABLE : le SQL Editor Supabase peut envoyer un script
--     multi-instructions sur des connexions différentes, ce qui ferait
--     disparaître une TEMP TABLE (session-scoped) entre deux instructions.
--     Une table permanente reste visible quelle que soit la connexion.
--     Ce n'est pas une table métier — c'est un support de test, vidé
--     (TRUNCATE) au début de chaque exécution. Elle peut être supprimée
--     sans conséquence (DROP TABLE public._ccf_validation_results;).
--
--   Partie A — Structurelle : lecture seule, introspection du schéma.
--   Partie B — Comportementale : insère des données de test (organisations
--              et objets liés, avec des UUID fixes et reconnaissables),
--              exécute réellement triggers et contraintes, puis les
--              supprime explicitement via des DELETE à la fin (et avant,
--              par sécurité, au cas où une exécution précédente aurait
--              échoué avant son propre nettoyage).
--
-- RÉSULTATS : de vrais SELECT, affichés dans l'onglet "Results" du SQL
-- Editor (pas de RAISE NOTICE — non visible dans ce Dashboard).
--
-- LIMITE CONNUE, À NE PAS OUBLIER EN LISANT LES RÉSULTATS :
--   Ce script s'exécute avec le rôle "postgres" (propriétaire des tables),
--   qui CONTOURNE la RLS par défaut dans PostgreSQL. La Partie B valide donc
--   la logique métier encodée dans les triggers et les contraintes CHECK/
--   UNIQUE (qui s'appliquent quel que soit le rôle), PAS l'application des
--   policies RLS elles-mêmes. La validation RLS réelle (quel rôle peut faire
--   quoi) a été faite manuellement en direct avec de vrais comptes
--   authentifiés (voir ADR-MVP.md, tests end-to-end) — ce script ne la
--   remplace pas.
-- ============================================================

CREATE TABLE IF NOT EXISTS public._ccf_validation_results (
    id        SERIAL PRIMARY KEY,
    section   TEXT NOT NULL,
    assertion TEXT NOT NULL,
    passed    BOOLEAN NOT NULL,
    detail    TEXT,
    run_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

TRUNCATE public._ccf_validation_results;

-- Nettoyage préventif (au cas où une exécution précédente aurait échoué
-- avant son propre nettoyage) — UUID fixes et reconnaissables, réservés
-- à ce script de test.
DELETE FROM public.logistics_steps WHERE project_id = '00000000-0000-0000-0000-000000000a04';
DELETE FROM public.project_participants WHERE project_id = '00000000-0000-0000-0000-000000000a04';
DELETE FROM public.mandates WHERE issuer_org_id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02')
                                 OR receiver_org_id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02');
DELETE FROM public.ccf_projects WHERE id = '00000000-0000-0000-0000-000000000a04';
DELETE FROM public.opportunities WHERE id = '00000000-0000-0000-0000-000000000a03';
DELETE FROM public.capabilities WHERE organization_id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02');
DELETE FROM public.organization_members WHERE organization_id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02');
DELETE FROM public.organizations WHERE id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02');

-- ════════════════════════════════════════════════════════════
-- PARTIE A — STRUCTURELLE (lecture seule)
-- ════════════════════════════════════════════════════════════

-- A1. Existence des 16 tables du domaine CCF
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A1-Tables', 'table ' || t || ' existe', EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = t
), t
FROM unnest(ARRAY[
    'profiles','organizations','organization_members','mandates','mandate_actions',
    'capabilities','opportunities','opportunity_capabilities','ccf_projects',
    'project_participants','documents','logistics_steps','value_reports',
    'business_events','audit_logs','ai_assistance_logs'
]) AS t;

-- A2. RLS activé sur les 16 tables
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A2-RLS-active', 'RLS activé sur ' || t, COALESCE((
    SELECT relrowsecurity FROM pg_class
    WHERE relname = t AND relnamespace = 'public'::regnamespace
), false), t
FROM unnest(ARRAY[
    'profiles','organizations','organization_members','mandates','mandate_actions',
    'capabilities','opportunities','opportunity_capabilities','ccf_projects',
    'project_participants','documents','logistics_steps','value_reports',
    'business_events','audit_logs','ai_assistance_logs'
]) AS t;

-- A3. Fonctions utilitaires RLS existent
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A3-Fonctions', 'fonction ' || f || ' existe', EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = f
), f
FROM unnest(ARRAY[
    'is_organization_member','is_organization_owner','is_org_admin',
    'is_platform_superadmin','user_org_ids','user_project_ids',
    'is_ccf_project_coordinator','is_ccf_project_participant',
    'validate_mandate_permissions','enforce_opp_cap_update_scope',
    'handle_new_organization_admin','audit_log_trigger_fn'
]) AS f;

-- A4. Catalogue mandate_actions = exactement 10 entrées (cahier §4.2)
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A4-Catalogue', 'mandate_actions contient exactement 10 actions',
       (SELECT count(*) FROM public.mandate_actions) = 10,
       'compte réel : ' || (SELECT count(*) FROM public.mandate_actions)::text;

-- A5. ccf_event_type contient les valeurs critiques attendues
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A5-EventType', 'ccf_event_type contient ' || v,
       v = ANY (enum_range(NULL::public.ccf_event_type)::text[]), v
FROM unnest(ARRAY[
    'organization_created','mandate_issued','mandate_accepted','mandate_revoked',
    'capability_qualified','opportunity_qualified','project_created',
    'project_phase_changed','document_submitted','document_approved',
    'document_rejected','document_archived','logistics_step_updated',
    'value_report_generated'
]) AS v;

-- A6. logistics_step_type contient les 6 valeurs attendues
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A6-LogisticsType', 'logistics_step_type contient ' || v,
       v = ANY (enum_range(NULL::public.logistics_step_type)::text[]), v
FROM unnest(ARRAY['ramassage','chargement','expedition','transit','livraison','preuve_finale']) AS v;

-- A7. org_role contient exactement admin/membre
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A7-OrgRole', 'org_role = {admin, membre} exactement',
       (SELECT array_agg(enumlabel::text ORDER BY enumlabel) FROM pg_enum
        WHERE enumtypid = 'public.org_role'::regtype) = ARRAY['admin','membre'],
       'valeurs réelles : ' || (SELECT string_agg(enumlabel::text, ', ' ORDER BY enumlabel) FROM pg_enum
        WHERE enumtypid = 'public.org_role'::regtype);

-- A8. Contrainte mandates_different_orgs présente
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A8-Contraintes', 'contrainte mandates_different_orgs existe',
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'mandates_different_orgs'), NULL;

-- A9. Contrainte UNIQUE(project_id, organization_id) sur project_participants
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A9-Contraintes', 'UNIQUE(project_id, organization_id) sur project_participants',
       EXISTS (
           SELECT 1 FROM pg_constraint c
           JOIN pg_class t ON t.oid = c.conrelid
           WHERE t.relname = 'project_participants' AND c.contype = 'u'
       ), NULL;

-- A10. Triggers critiques présents
INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
SELECT 'A10-Triggers', 'trigger ' || tg || ' existe', EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = tg AND NOT tgisinternal
), tg
FROM unnest(ARRAY[
    'validate_mandate_permissions_trigger','enforce_opp_cap_update_scope',
    'on_organization_created','audit_mandates'
]) AS tg;

-- ════════════════════════════════════════════════════════════
-- PARTIE B — COMPORTEMENTALE
-- Données de test avec UUID fixes, nettoyées explicitement à la fin
-- (et déjà nettoyées par précaution avant, plus haut).
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_org_a UUID := '00000000-0000-0000-0000-000000000a01';
    v_org_b UUID := '00000000-0000-0000-0000-000000000a02';
    v_opp   UUID := '00000000-0000-0000-0000-000000000a03';
    v_proj  UUID := '00000000-0000-0000-0000-000000000a04';
    v_ok    BOOLEAN;
    v_err   TEXT;
BEGIN
    INSERT INTO public.organizations (id, name, type, status)
    VALUES
        (v_org_a, 'Test Validation A', 'coordinateur', 'active'),
        (v_org_b, 'Test Validation B', 'manufacturier', 'active');

    -- B1. Auto-mandat interdit (mandates_different_orgs)
    v_ok := false;
    BEGIN
        INSERT INTO public.mandates (issuer_org_id, receiver_org_id, mandate_scope, permissions, status)
        VALUES (v_org_a, v_org_a, 'operationnel', '{"actions":["read_capabilities"]}'::jsonb, 'draft');
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B1-AutoMandat', 'un mandat issuer=receiver est rejeté', v_ok, NULL);

    -- B2. Mandat valide accepté (draft, actions valides)
    v_ok := false;
    BEGIN
        INSERT INTO public.mandates (issuer_org_id, receiver_org_id, mandate_scope, permissions, status)
        VALUES (v_org_a, v_org_b, 'operationnel', '{"actions":["read_capabilities","invite_project_org"]}'::jsonb, 'draft');
        v_ok := true;
    EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B2-MandatValide', 'un mandat draft avec actions valides est accepté', v_ok, v_err);

    -- B3. validate_mandate_permissions rejette une action inconnue
    v_ok := false;
    BEGIN
        INSERT INTO public.mandates (issuer_org_id, receiver_org_id, mandate_scope, permissions, status)
        VALUES (v_org_a, v_org_b, 'operationnel', '{"actions":["action_inexistante"]}'::jsonb, 'draft');
    EXCEPTION WHEN OTHERS THEN
        v_ok := true;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B3-ActionInvalide', 'un mandat avec une action inconnue est rejeté', v_ok, NULL);

    -- B4. validate_mandate_permissions rejette un tableau d'actions vide
    v_ok := false;
    BEGIN
        INSERT INTO public.mandates (issuer_org_id, receiver_org_id, mandate_scope, permissions, status)
        VALUES (v_org_a, v_org_b, 'operationnel', '{"actions":[]}'::jsonb, 'draft');
    EXCEPTION WHEN OTHERS THEN
        v_ok := true;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B4-ActionsVide', 'un mandat avec actions[] vide est rejeté', v_ok, NULL);

    -- Préparer une opportunité + projet pour les tests suivants
    INSERT INTO public.opportunities (id, title, coordinator_org_id, status)
    VALUES (v_opp, 'Opportunité de test validation', v_org_a, 'qualified');

    INSERT INTO public.ccf_projects (id, opportunity_id, title, coordinator_org_id, phase, status)
    VALUES (v_proj, v_opp, 'Projet de test validation', v_org_a, 'active', 'active');

    -- B5. project_participants : UNIQUE(project_id, organization_id)
    INSERT INTO public.project_participants (project_id, organization_id, project_role, status)
    VALUES (v_proj, v_org_b, 'contributeur', 'active');

    v_ok := false;
    BEGIN
        INSERT INTO public.project_participants (project_id, organization_id, project_role, status)
        VALUES (v_proj, v_org_b, 'contributeur', 'active');
    EXCEPTION WHEN unique_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B5-ParticipantUnique', 'une organisation ne peut participer 2 fois au même projet', v_ok, NULL);

    -- B6. ccf_projects.phase : CHECK fermé, valeur invalide rejetée
    v_ok := false;
    BEGIN
        UPDATE public.ccf_projects SET phase = 'phase_inexistante' WHERE id = v_proj;
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B6-PhaseInvalide', 'une phase de projet invalide est rejetée', v_ok, NULL);

    -- B7. logistics_steps : step_type ENUM rejette une valeur invalide
    v_ok := false;
    BEGIN
        INSERT INTO public.logistics_steps (project_id, step_type, responsible_org_id, status)
        VALUES (v_proj, 'type_inexistant', v_org_b, 'planned');
    EXCEPTION WHEN invalid_text_representation THEN
        v_ok := true;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B7-StepTypeInvalide', 'un type d''étape logistique invalide est rejeté', v_ok, NULL);

    -- B8. logistics_steps : type valide accepté
    v_ok := false;
    BEGIN
        INSERT INTO public.logistics_steps (project_id, step_type, responsible_org_id, status)
        VALUES (v_proj, 'ramassage', v_org_b, 'planned');
        v_ok := true;
    EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B8-StepTypeValide', 'un type d''étape logistique valide est accepté', v_ok, v_err);

    -- B9. capabilities : status CHECK fermé
    v_ok := false;
    BEGIN
        INSERT INTO public.capabilities (organization_id, material_type, status)
        VALUES (v_org_b, 'acier_ferreux', 'statut_inexistant');
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B9-CapabilityStatusInvalide', 'un statut de capacité invalide est rejeté', v_ok, NULL);

    -- B10. organization_members : operational_profile CHECK fermé (bureau/terrain)
    v_ok := false;
    BEGIN
        INSERT INTO public.organization_members (organization_id, user_id, operational_profile)
        VALUES (v_org_a, gen_random_uuid(), 'profil_inexistant');
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B10-ProfilInvalide', 'un operational_profile invalide est rejeté', v_ok, NULL);

EXCEPTION WHEN OTHERS THEN
    INSERT INTO public._ccf_validation_results (section, assertion, passed, detail)
    VALUES ('B-ERREUR-BLOQUANTE', 'le bloc de tests comportementaux s''est arrêté prématurément', false, SQLERRM);
END $$;

-- Nettoyage final des données de test (dans l'ordre des dépendances).
DELETE FROM public.logistics_steps WHERE project_id = '00000000-0000-0000-0000-000000000a04';
DELETE FROM public.project_participants WHERE project_id = '00000000-0000-0000-0000-000000000a04';
DELETE FROM public.mandates WHERE issuer_org_id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02')
                                 OR receiver_org_id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02');
DELETE FROM public.ccf_projects WHERE id = '00000000-0000-0000-0000-000000000a04';
DELETE FROM public.opportunities WHERE id = '00000000-0000-0000-0000-000000000a03';
DELETE FROM public.capabilities WHERE organization_id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02');
DELETE FROM public.organization_members WHERE organization_id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02');
DELETE FROM public.organizations WHERE id IN ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000a02');

-- ════════════════════════════════════════════════════════════
-- RÉSUMÉ FINAL — ces 3 SELECT s'affichent dans l'onglet "Results"
-- ════════════════════════════════════════════════════════════

SELECT
    section,
    count(*) AS total,
    count(*) FILTER (WHERE passed) AS reussies,
    count(*) FILTER (WHERE NOT passed) AS echouees
FROM public._ccf_validation_results
GROUP BY section
ORDER BY section;

SELECT assertion, detail
FROM public._ccf_validation_results
WHERE NOT passed
ORDER BY id;

SELECT
    count(*) AS total_assertions,
    count(*) FILTER (WHERE passed) AS total_reussies,
    count(*) FILTER (WHERE NOT passed) AS total_echouees
FROM public._ccf_validation_results;
