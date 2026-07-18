-- ============================================================
-- Migration corrective 06a — Fuite de privilège EXECUTE vers anon sur les
-- 6 fonctions SECURITY DEFINER de la migration 06 (platform_operators /
-- carbon_commercialization_mandates)
-- ============================================================
--
-- CONTEXTE (découvert le 18 juillet 2026 pendant l'exécution réelle du
-- script de tests de la migration 06, assertion A21, après application
-- réussie de la migration 06 elle-même) : A21 vérifie que les 6 nouvelles
-- fonctions ont EXECUTE accordé à `authenticated` ET ABSENT de `anon`. Ce
-- test a échoué (61/62, A21 seule en échec) — anon a effectivement EXECUTE
-- sur au moins une de ces fonctions.
--
-- ROOT CAUSE : la section 8 (« PRIVILÈGES ») de
-- 06_carbon_operator_and_mandates.sql traite différemment les tables et les
-- fonctions qu'elle vient de créer :
--
--   REVOKE ALL ON public.platform_operators FROM PUBLIC, anon, authenticated;   -- correct
--   REVOKE ALL ON FUNCTION public.is_platform_operator(UUID) FROM PUBLIC;       -- INCOMPLET
--
-- Ce projet Supabase applique des privilèges par défaut qui accordent EXECUTE
-- directement à `anon` (et `authenticated`) au moment de la création d'une
-- fonction — INDÉPENDAMMENT de PUBLIC (probablement via
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO
-- anon, authenticated, configuré au niveau du projet). `REVOKE ALL ... FROM
-- PUBLIC` ne touche donc PAS ce grant direct à `anon` : il fallait, comme
-- pour les tables juste au-dessus dans le même fichier, révoquer
-- explicitement `PUBLIC, anon, authenticated` avant de regrant `authenticated`
-- seul. C'est exactement le même type de piège que celui déjà rencontré et
-- corrigé dans la migration 02 (décision D6 de ce fichier) pour
-- aggregator_memberships — sauf qu'ici, l'incohérence était interne à la
-- migration 06 elle-même : le bon pattern existait déjà 6 lignes plus haut
-- dans le même fichier pour les tables, mais n'a pas été repris pour les
-- fonctions.
--
-- IMPACT : `anon` (rôle non authentifié, utilisé par les clients publics/
-- non connectés) pouvait potentiellement appeler ces 6 fonctions
-- SECURITY DEFINER. En pratique, chacune vérifie déjà `auth.uid() IS NULL`
-- en tout premier et lève `'Authentification requise.'` — un appel anonyme
-- échouerait donc immédiatement sur le plan fonctionnel. Il ne s'agit donc
-- pas d'un contournement d'autorisation exploitable comme le correctif 03,
-- mais d'un défaut de défense en profondeur (privilège plus large que
-- nécessaire) que A21 est précisément conçue pour détecter avant qu'il ne
-- devienne un problème si le corps d'une de ces fonctions évoluait un jour
-- sans reproduire ce garde en premier. Corrigé par prudence et par
-- cohérence avec le reste du schéma avant toute désignation de l'opérateur
-- réel.
--
-- CORRECTIF : REVOKE ALL ... FROM PUBLIC, anon, authenticated (au lieu de
-- PUBLIC seul) puis GRANT EXECUTE ... TO authenticated, pour chacune des 6
-- fonctions. Aucun changement de corps de fonction, aucun changement de
-- schéma, aucune donnée touchée — uniquement des privilèges.
--
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION — confirme que les 6 fonctions existent avec la
--    signature exacte attendue avant de modifier leurs privilèges.
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regprocedure('public.is_platform_operator(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_platform_operator(uuid) introuvable — la migration 06 a-t-elle bien été appliquée ?';
    END IF;
    IF to_regprocedure('public.is_active_platform_operator_member(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_active_platform_operator_member(uuid) introuvable — la migration 06 a-t-elle bien été appliquée ?';
    END IF;
    IF to_regprocedure('public.designate_platform_operator(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.designate_platform_operator(uuid) introuvable — la migration 06 a-t-elle bien été appliquée ?';
    END IF;
    IF to_regprocedure('public.revoke_platform_operator(uuid,text)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.revoke_platform_operator(uuid,text) introuvable — la migration 06 a-t-elle bien été appliquée ?';
    END IF;
    IF to_regprocedure('public.grant_commercialization_mandate(uuid,uuid,text[],uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.grant_commercialization_mandate(uuid,uuid,text[],uuid) introuvable — la migration 06 a-t-elle bien été appliquée ?';
    END IF;
    IF to_regprocedure('public.revoke_commercialization_mandate(uuid,text)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.revoke_commercialization_mandate(uuid,text) introuvable — la migration 06 a-t-elle bien été appliquée ?';
    END IF;
    RAISE NOTICE 'Prévalidation réussie : les 6 fonctions existent avec la signature attendue.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. CORRECTIF — REVOKE explicite PUBLIC, anon, authenticated puis
--    GRANT EXECUTE à authenticated seul, pour chacune des 6 fonctions.
-- ────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.is_platform_operator(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_operator(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.is_active_platform_operator_member(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_platform_operator_member(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.designate_platform_operator(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.designate_platform_operator(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.revoke_platform_operator(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_platform_operator(UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.grant_commercialization_mandate(UUID, UUID, TEXT[], UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_commercialization_mandate(UUID, UUID, TEXT[], UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.revoke_commercialization_mandate(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_commercialization_mandate(UUID, TEXT) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 2. POST-VALIDATION — confirme, via has_function_privilege() (même
--    mécanique exacte que A21 dans le script de tests), que anon n'a plus
--    EXECUTE et que authenticated l'a toujours, pour les 6 fonctions.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_ok BOOLEAN;
BEGIN
    SELECT bool_and(
        has_function_privilege('authenticated', p.oid, 'EXECUTE')
        AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
    )
    INTO v_ok
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND ((p.proname = 'is_platform_operator' AND p.pronargs = 1)
        OR (p.proname = 'is_active_platform_operator_member' AND p.pronargs = 1)
        OR (p.proname = 'designate_platform_operator' AND p.pronargs = 1)
        OR (p.proname = 'revoke_platform_operator' AND p.pronargs = 2)
        OR (p.proname = 'grant_commercialization_mandate' AND p.pronargs = 4)
        OR (p.proname = 'revoke_commercialization_mandate' AND p.pronargs = 2));

    IF NOT COALESCE(v_ok, false) THEN
        RAISE EXCEPTION 'Post-validation échouée : au moins une des 6 fonctions n''a pas le privilège attendu (authenticated=EXECUTE, anon=aucun).';
    END IF;

    RAISE NOTICE 'Post-validation réussie : anon n''a EXECUTE sur aucune des 6 fonctions, authenticated l''a sur les 6.';
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK (à exécuter séparément, jamais collé avec ce qui précède) :
-- il n'existe PAS de rollback significatif pour ce correctif — l'état
-- antérieur était un défaut de privilège (anon avec EXECUTE inutilement),
-- jamais un comportement à restaurer volontairement. Si un rollback complet
-- de la migration 06 est nécessaire, utiliser la section ROLLBACK de
-- 06_carbon_operator_and_mandates.sql (qui supprime les fonctions et
-- tables elles-mêmes, rendant ce correctif de privilèges sans objet).
-- ============================================================
