-- ============================================================
-- Migration corrective 03 — Faille d'autorisation par NULL (fail-open)
-- dans join_aggregator() et create_aggregator_with_primary_admin()
-- ============================================================
--
-- CONTEXTE (découvert le 14 juillet 2026 pendant l'exécution du script de
-- tests de la migration 02, test B16) : is_platform_superadmin() est définie
-- ainsi (migration 20260710999100_reapply_mrv_and_aggregators.sql, ligne 850) :
--
--   SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
--
-- Quand app_metadata n'a PAS de clé 'role' (le cas de N'IMPORTE QUEL
-- utilisateur authentifié normal, pas seulement les super-admins), cette
-- expression vaut NULL = 'admin' → NULL, PAS false.
--
-- Deux fonctions de la migration 02 utilisent cette valeur dans un garde de
-- la forme IF NOT (...) THEN RAISE EXCEPTION — exactement le même piège de
-- logique à trois valeurs déjà identifié et corrigé ailleurs dans la
-- migration 02 (carbon_guard_organizations_aggregator_id_direct_write, D5),
-- mais qui avait échappé à la revue sur ces deux RPC précises :
--
--   - create_aggregator_with_primary_admin() : IF NOT public.is_platform_superadmin() THEN
--     false OR NULL n'entre pas en jeu ici, mais NOT NULL = NULL directement
--     → IF NULL THEN ne s'exécute jamais en PL/pgSQL → l'exception n'est
--     JAMAIS levée pour un appelant sans app_metadata.role='admin' explicite
--     ET explicitement absent (NULL, pas false) → N'IMPORTE QUEL utilisateur
--     authentifié normal peut créer un regroupement et s'auto-nommer admin.
--
--   - join_aggregator() : IF NOT (public.is_aggregator_admin(p_aggregator_id)
--     OR public.is_platform_superadmin()) THEN
--     is_aggregator_admin() est toujours true/false (construite avec EXISTS,
--     jamais NULL), mais is_platform_superadmin() peut valoir NULL. Si
--     is_aggregator_admin() = false ET is_platform_superadmin() = NULL :
--     false OR NULL = NULL (logique à trois valeurs) → NOT NULL = NULL →
--     IF NULL THEN ne s'exécute jamais → N'IMPORTE QUEL utilisateur
--     authentifié normal peut rattacher N'IMPORTE QUELLE organisation à
--     N'IMPORTE QUEL regroupement, sans être admin de rien.
--
-- CE BUG EST ACTUELLEMENT EN PRODUCTION (migration 02 déjà appliquée le 14
-- juillet 2026) — ce n'est pas un artefact de test, c'est un contournement
-- d'autorisation réellement exploitable dès maintenant. Correction
-- prioritaire.
--
-- leave_aggregator() et la policy RLS aggregator_memberships_select
-- utilisent ce même OR à l'intérieur d'une clause WHERE / USING —
-- sémantiquement sûres : une ligne n'est retenue que si la condition vaut
-- EXACTEMENT true, donc NULL y échoue FERMÉ (comportement correct), pas
-- ouvert. Elles ne sont PAS concernées par cette migration corrective.
--
-- CORRECTIF : COALESCE(..., false) sur is_platform_superadmin() (et, par
-- défense en profondeur sans changement de comportement, sur
-- is_aggregator_admin() aussi, bien qu'elle ne puisse structurellement pas
-- être NULL) dans les deux gardes IF NOT concernés. Aucun autre changement :
-- même signature, même corps sinon, aucun changement de schéma, aucune
-- donnée touchée. CREATE OR REPLACE FUNCTION uniquement.
--
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION — confirme que les deux fonctions existent avec la
--    signature exacte attendue avant de les remplacer.
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regprocedure('public.create_aggregator_with_primary_admin(text,text,uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.create_aggregator_with_primary_admin(text,text,uuid) introuvable — la migration 02 a-t-elle bien été appliquée ?';
    END IF;
    IF to_regprocedure('public.join_aggregator(uuid,uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.join_aggregator(uuid,uuid) introuvable — la migration 02 a-t-elle bien été appliquée ?';
    END IF;
    RAISE NOTICE 'Prévalidation réussie : les deux fonctions à corriger existent.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. create_aggregator_with_primary_admin() — corrigée
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_aggregator_with_primary_admin(
    p_name TEXT,
    p_description TEXT,
    p_primary_admin_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_aggregator_id UUID;
    v_admin_id      UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- CORRECTIF (migration 03) : COALESCE(..., false) — is_platform_superadmin()
    -- renvoie NULL (pas false) quand app_metadata n'a pas de clé 'role', ce
    -- qui est le cas de tout utilisateur authentifié normal. Sans ce
    -- correctif, IF NOT NULL ne s'exécute jamais en PL/pgSQL et n'importe
    -- quel utilisateur authentifié pouvait créer un regroupement.
    IF NOT COALESCE(public.is_platform_superadmin(), false) THEN
        RAISE EXCEPTION 'Seul un super-administrateur de la plateforme peut créer un regroupement.';
    END IF;

    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'Le nom du regroupement est obligatoire.';
    END IF;

    IF p_primary_admin_user_id IS NULL THEN
        RAISE EXCEPTION 'Un administrateur principal est obligatoire à la création.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_primary_admin_user_id) THEN
        RAISE EXCEPTION 'p_primary_admin_user_id ne correspond à aucun profil existant.';
    END IF;

    INSERT INTO public.aggregators (name, description)
    VALUES (btrim(p_name), p_description)
    RETURNING id INTO v_aggregator_id;

    INSERT INTO public.aggregator_admins (aggregator_id, user_id, role, nominated_by)
    VALUES (v_aggregator_id, p_primary_admin_user_id, 'primary_admin', auth.uid())
    RETURNING id INTO v_admin_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, aggregator_id, actor_id, payload)
    VALUES ('aggregator_created', 'aggregator', v_aggregator_id, v_aggregator_id, auth.uid(),
            jsonb_build_object('name', p_name));

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, aggregator_id, actor_id, payload)
    VALUES ('aggregator_admin_appointed', 'aggregator_admin', v_admin_id, v_aggregator_id, auth.uid(),
            jsonb_build_object('user_id', p_primary_admin_user_id, 'role', 'primary_admin'));

    RETURN v_aggregator_id;
END;
$$;

COMMENT ON FUNCTION public.create_aggregator_with_primary_admin(TEXT, TEXT, UUID) IS
  'Bootstrap atomique d''un regroupement avec son premier administrateur (§9). '
  'Réservée à is_platform_superadmin(). Journalise aggregator_created et '
  'aggregator_admin_appointed dans carbon_business_events (décision D4, revue). '
  'CORRIGÉE (migration 03) : COALESCE(is_platform_superadmin(), false) — '
  'contournement d''autorisation par NULL corrigé.';

-- ────────────────────────────────────────────────────────────
-- 2. join_aggregator() — corrigée
-- ────────────────────────────────────────────────────────────
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
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- CORRECTIF (migration 03) : COALESCE(..., false) sur les deux membres du
    -- OR. is_aggregator_admin() est structurellement toujours true/false
    -- (construite avec EXISTS), mais is_platform_superadmin() peut valoir
    -- NULL — voir en-tête de ce fichier. false OR NULL = NULL, et
    -- IF NOT NULL ne s'exécute jamais en PL/pgSQL : sans ce correctif,
    -- n'importe quel utilisateur authentifié normal pouvait rattacher
    -- n'importe quelle organisation à n'importe quel regroupement.
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

    INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by)
    VALUES (p_organization_id, p_aggregator_id, auth.uid())
    RETURNING id INTO v_membership_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
    VALUES ('aggregator_membership_started', 'aggregator_membership', v_membership_id, p_organization_id, p_aggregator_id, auth.uid(), NULL);

    RETURN v_membership_id;
END;
$$;

COMMENT ON FUNCTION public.join_aggregator(UUID, UUID) IS
  'Crée une adhésion active d''une organisation à un regroupement. Autorisée à '
  'is_aggregator_admin(p_aggregator_id) ou is_platform_superadmin() SEULEMENT '
  '(décision D1, corrigée après revue — une organisation ne peut plus activer '
  'elle-même son adhésion ; pas de flux d''invitation bilatéral dans cette migration). '
  'CORRIGÉE (migration 03) : COALESCE(..., false) sur les deux conditions — '
  'contournement d''autorisation par NULL corrigé.';

-- ────────────────────────────────────────────────────────────
-- 3. POST-VALIDATION — confirme que les deux corps contiennent bien le
--    correctif (COALESCE) avant de valider la transaction.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef('public.create_aggregator_with_primary_admin(text,text,uuid)'::regprocedure) INTO v_def;
    IF v_def NOT ILIKE '%COALESCE(public.is_platform_superadmin(), false)%' THEN
        RAISE EXCEPTION 'Post-validation échouée : create_aggregator_with_primary_admin() ne contient pas le correctif attendu.';
    END IF;

    SELECT pg_get_functiondef('public.join_aggregator(uuid,uuid)'::regprocedure) INTO v_def;
    IF v_def NOT ILIKE '%COALESCE(public.is_aggregator_admin(p_aggregator_id), false)%'
       OR v_def NOT ILIKE '%COALESCE(public.is_platform_superadmin(), false)%' THEN
        RAISE EXCEPTION 'Post-validation échouée : join_aggregator() ne contient pas le correctif attendu.';
    END IF;

    RAISE NOTICE 'Post-validation réussie : les deux fonctions contiennent le correctif COALESCE.';
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK (à exécuter séparément, jamais collé avec ce qui précède) :
-- restaure les corps originaux (avec le bug) tels qu'ils existaient dans
-- 02_carbon_aggregator_memberships.sql — à n'utiliser qu'en cas de problème
-- inattendu avec ce correctif lui-même, jamais autrement.
-- ============================================================
-- BEGIN;
--
-- CREATE OR REPLACE FUNCTION public.create_aggregator_with_primary_admin(
--     p_name TEXT, p_description TEXT, p_primary_admin_user_id UUID
-- )
-- RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
-- AS $$
-- DECLARE
--     v_aggregator_id UUID;
--     v_admin_id      UUID;
-- BEGIN
--     IF auth.uid() IS NULL THEN
--         RAISE EXCEPTION 'Authentification requise.';
--     END IF;
--     IF NOT public.is_platform_superadmin() THEN
--         RAISE EXCEPTION 'Seul un super-administrateur de la plateforme peut créer un regroupement.';
--     END IF;
--     IF p_name IS NULL OR btrim(p_name) = '' THEN
--         RAISE EXCEPTION 'Le nom du regroupement est obligatoire.';
--     END IF;
--     IF p_primary_admin_user_id IS NULL THEN
--         RAISE EXCEPTION 'Un administrateur principal est obligatoire à la création.';
--     END IF;
--     IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_primary_admin_user_id) THEN
--         RAISE EXCEPTION 'p_primary_admin_user_id ne correspond à aucun profil existant.';
--     END IF;
--     INSERT INTO public.aggregators (name, description)
--     VALUES (btrim(p_name), p_description) RETURNING id INTO v_aggregator_id;
--     INSERT INTO public.aggregator_admins (aggregator_id, user_id, role, nominated_by)
--     VALUES (v_aggregator_id, p_primary_admin_user_id, 'primary_admin', auth.uid())
--     RETURNING id INTO v_admin_id;
--     INSERT INTO public.carbon_business_events (event_type, object_type, object_id, aggregator_id, actor_id, payload)
--     VALUES ('aggregator_created', 'aggregator', v_aggregator_id, v_aggregator_id, auth.uid(), jsonb_build_object('name', p_name));
--     INSERT INTO public.carbon_business_events (event_type, object_type, object_id, aggregator_id, actor_id, payload)
--     VALUES ('aggregator_admin_appointed', 'aggregator_admin', v_admin_id, v_aggregator_id, auth.uid(), jsonb_build_object('user_id', p_primary_admin_user_id, 'role', 'primary_admin'));
--     RETURN v_aggregator_id;
-- END;
-- $$;
--
-- CREATE OR REPLACE FUNCTION public.join_aggregator(
--     p_organization_id UUID, p_aggregator_id UUID
-- )
-- RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
-- AS $$
-- DECLARE
--     v_membership_id UUID;
-- BEGIN
--     IF auth.uid() IS NULL THEN
--         RAISE EXCEPTION 'Authentification requise.';
--     END IF;
--     IF NOT (public.is_aggregator_admin(p_aggregator_id) OR public.is_platform_superadmin()) THEN
--         RAISE EXCEPTION 'Seul un administrateur du regroupement cible ou un super-administrateur peut ajouter une organisation à ce regroupement.';
--     END IF;
--     IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
--         RAISE EXCEPTION 'p_organization_id ne correspond à aucune organisation existante.';
--     END IF;
--     IF NOT EXISTS (SELECT 1 FROM public.aggregators WHERE id = p_aggregator_id) THEN
--         RAISE EXCEPTION 'p_aggregator_id ne correspond à aucun regroupement existant.';
--     END IF;
--     IF EXISTS (
--         SELECT 1 FROM public.aggregator_memberships
--         WHERE organization_id = p_organization_id AND ended_at IS NULL
--     ) THEN
--         RAISE EXCEPTION 'Cette organisation a déjà une adhésion active à un regroupement — utilisez leave_aggregator() avant d''en rejoindre un autre.';
--     END IF;
--     INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by)
--     VALUES (p_organization_id, p_aggregator_id, auth.uid()) RETURNING id INTO v_membership_id;
--     INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
--     VALUES ('aggregator_membership_started', 'aggregator_membership', v_membership_id, p_organization_id, p_aggregator_id, auth.uid(), NULL);
--     RETURN v_membership_id;
-- END;
-- $$;
--
-- COMMIT;
-- ============================================================
