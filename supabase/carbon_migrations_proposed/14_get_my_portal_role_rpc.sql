-- =============================================================================
-- Migration 14 — RPC public.get_my_portal_role()
--                Rôle de PORTAIL (routage frontend) pour l'utilisateur courant
--
-- STATUT AU 2026-08-06 :
-- - appliquée définitivement sur METALVISION-DEMO (msgesgemaasyzycielzf) le
--   2026-08-02, migration distante "20260802032220_get_my_portal_role_rpc",
--   après GATE transactionnel (BEGIN...ROLLBACK) 15/15 puis rejeu réel 15/15
--   sur l'état permanent (comptes, ACL, STABLE, SECURITY DEFINER, search_path
--   vide, zéro paramètre). Empreinte des données/policies public identique
--   avant/après (n_users=6, n_accredited_verifiers=1, n_org_members=3,
--   n_organizations=3, n_policies_public=152,
--   policies_fingerprint=ad90a6f4d01c3a7402d0d24beaeae8c3) : aucune donnée ni
--   policy modifiée par cette application.
-- - appliquée définitivement sur METALVISION production (dlbewgsoboaycbpypcus)
--   le 2026-08-06 à 12:04:15 UTC, exécutée directement en base (SQL brut, hors
--   outil de migration Supabase — voir supabase/MIGRATIONS_TIMELINE.md pour le
--   statut réel dans schema_migrations, constaté en direct, jamais supposé) ;
-- - validation production : prérequis conformes (is_platform_superadmin(),
--   is_authorized_verifier_identity(uuid) déjà présents), SECURITY DEFINER
--   confirmé, search_path vide confirmé, ACL minimales confirmées
--   (anon=false, authenticated=true, public=false) et matrice admin/verifier/
--   client validée sur 3 identités RÉELLES de production sous le rôle
--   authenticated (pas superuser) ;
-- - aucune donnée, table ou policy modifiée par cette application (empreinte
--   données/policies identique avant/après : n_users=9,
--   n_accredited_verifiers=1, n_org_members=3, n_organizations=4,
--   n_policies_public=147, policies_fingerprint=c83662a2129b4d9e5720b88a4fcad721
--   — seul n_functions_public passe de 356 à 357, exactement cette fonction).
--
-- Cette fonction reste, comme avant son application, UNIQUEMENT un helper de
-- ROUTAGE FRONTEND (quel portail afficher après connexion) : elle NE
-- CONSTITUE JAMAIS UNE AUTORISATION. Toute vérification d'accès réelle
-- continue de passer par les policies RLS et par is_platform_superadmin() /
-- is_organization_owner() / is_aggregator_primary_admin() /
-- is_authorized_verifier_identity() / is_assigned_verifier() évaluées côté
-- serveur sur chaque requête protégée — inchangé par cette application.
--
-- Le ROLLBACK (voir bandeau en fin de fichier) reste couplé au retour
-- préalable du frontend vers une version n'appelant pas cette RPC — ce
-- couplage était déjà documenté avant cette mise à jour de statut et demeure
-- exact.
-- =============================================================================
--
-- CHANGEMENTS PAR RAPPORT À LA v1 (revue utilisateur du 2026-08-01) :
--   1. Le bucket 'admin' n'inclut plus is_project_admin(). PRÉCISION
--      IMPORTANTE (v3, deuxième revue) : is_project_admin() et
--      is_platform_superadmin() ne sont PAS structurellement identiques —
--      is_project_admin() reconnaît EN PLUS le rôle théorique JWT
--      'project_admin' (`IN ('project_admin', 'admin')`), qu'
--      is_platform_superadmin() (`= 'admin'`) ne reconnaît pas. Elles sont
--      seulement ÉQUIVALENTES EN PRATIQUE POUR TOUS LES COMPTES RÉELS
--      OBSERVÉS LE 2026-08-01 (démo ET production), car AUCUN compte —
--      démo ou production, vérifié live — n'a jamais 'project_admin' dans
--      son app_metadata ; ce rôle semble n'avoir jamais été assigné à ce
--      jour dans ce système. C'est une équivalence empirique et temporelle,
--      pas une garantie structurelle valable pour tout futur compte. Si un
--      compte 'project_admin' était créé un jour, le garder dans le bucket
--      admin de cette RPC l'aurait routé vers /admin, page dont le SEUL gate
--      réel (src/app/admin/page.tsx, probe RLS sur audit_logs) est
--      is_platform_superadmin() SEULE — cette personne se serait vue
--      afficher "Accès refusé" juste après avoir été routée là par cette
--      RPC. Bucket admin réduit à is_platform_superadmin() SEULE, qui
--      reproduit exactement le gate réel actuel de /admin (et restera
--      correct même si un compte 'project_admin' apparaît un jour, tant que
--      /admin lui-même n'est pas aussi ouvert à ce rôle).
--   2. search_path passé de 'public, pg_temp' à '' (vide) — tous les objets
--      référencés dans le corps étaient déjà qualifiés (public.xxx, auth.xxx),
--      donc un search_path vide est strictement plus strict sans rien casser
--      (pg_catalog reste implicitement résolu par Postgres même avec
--      search_path='').
--   3. Prérequis STEP 1 allégé en conséquence (is_project_admin() retiré).
--
-- PREUVE LIVE — définitions exactes interrogées le 2026-08-01 sur
-- METALVISION-DEMO (identiques caractère pour caractère sur production,
-- vérifié également) :
--
--   CREATE OR REPLACE FUNCTION public.is_platform_superadmin()
--   RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
--   AS $$ SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin' $$;
--   -- (aucun SET search_path sur cette fonction préexistante — non modifiée
--   -- ici, hors périmètre de cette migration ; sa seule référence non-locale,
--   -- auth.jwt(), est déjà qualifiée par le schéma auth, donc pas de risque
--   -- d'injection par search_path malgré l'absence de SET.)
--
--   CREATE OR REPLACE FUNCTION public.is_project_admin()
--   RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
--   SET search_path TO 'public'
--   AS $$ SELECT (auth.jwt() -> 'app_metadata' ->> 'role') IN ('project_admin', 'admin') $$;
--
--   CREATE OR REPLACE FUNCTION public.is_authorized_verifier_identity(p_user_id uuid)
--   RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
--   SET search_path TO 'public', 'pg_temp'
--   AS $$ SELECT EXISTS (SELECT 1 FROM public.accredited_verifiers
--                         WHERE user_id = p_user_id AND active) $$;
--
-- MATRICE LIVE DES 6 COMPTES DÉMO (interrogée sur METALVISION-DEMO le
-- 2026-08-01 — raw_app_meta_data réel de auth.users + tables réelles, PAS une
-- supposition) :
--
--   Compte          | app_metadata.role | is_platform_superadmin() | is_project_admin() | is_authorized_verifier_identity() | organization_members (org_role=admin) | aggregator_admins (primary_admin)
--   superadmin@...   | 'admin'           | TRUE                      | TRUE                | false                              | —                                       | —
--   operateur@...    | NULL              | NULL (≡ false)            | NULL (≡ false)      | false                              | Opérateur MetalTrace (Démo), active     | —
--   aggregateur@...  | NULL              | NULL (≡ false)            | NULL (≡ false)      | false                              | —                                       | Regroupement Sidérurgique Laurentides
--   producteur@...   | NULL              | NULL (≡ false)            | NULL (≡ false)      | false                              | Aciérie Boréale Inc. (Démo), active     | —
--   recycleur@...    | NULL              | NULL (≡ false)            | NULL (≡ false)      | false                              | RecyclMétal Estrie (Démo), active       | —
--   verificateur@... | NULL              | NULL (≡ false)            | NULL (≡ false)      | TRUE                                | —                                       | —
--
--   (NULL dans une expression booléenne PL/pgSQL `IF ... THEN` est traité
--   comme false — la branche n'est jamais prise ; confirmé par la doc
--   PostgreSQL, pas une supposition.)
--
-- DÉCISION PRODUIT CONFIRMÉE PAR CETTE MATRICE (cf. Script-Demo-METALVISION-
-- DEMO.md, tableau des comptes + trame narrative + section "Pièges à
-- éviter") : operateur/aggregateur/producteur/recycleur sont des admins
-- SCOPÉS à une organisation ou un regroupement précis (is_organization_owner
-- (p_org_id) / is_aggregator_primary_admin(p_aggregator_id) — toutes deux
-- exigent un identifiant cible, par construction non globalisables en un
-- statut "portail" unique). Le script de démo les fait naviguer directement
-- vers des écrans scopés (/admin/carbon-inventory, /admin/carbon-sales,
-- /admin/regroupements/[id]/distribution, écrans CCF généraux) — jamais vers
-- /admin lui-même, qui leur afficherait "Accès refusé" (superadmin uniquement).
-- Leur portail de ROUTAGE post-connexion reste donc 'client' (atterrissage
-- sur /), exactement comme le comportement actuel (fortuit, mais correct)
-- avant ce correctif. Seul superadmin@... doit résoudre 'admin'.
--
-- CONTEXTE INITIAL (bug réel diagnostiqué le 2026-08-01, inchangé) : le
-- compte verificateur@demo.metaltrace.ca (et tous les comptes démo SAUF
-- superadmin) n'a AUCUNE clé "role" dans son raw_app_meta_data — cf.
-- supabase/seeds/demo/01_users_and_roles.sql, lignes 68-102. Son statut de
-- vérificateur accrédité vit EXCLUSIVEMENT dans public.accredited_verifiers
-- (migration carbone 05), table RLS-verrouillée à
-- is_platform_superadmin() OR is_project_admin() en SELECT direct, et sa
-- fonction de vérification is_authorized_verifier_identity(p_user_id UUID)
-- est volontairement REVOKE ALL FROM PUBLIC, anon, authenticated (anti-oracle
-- : elle accepte un user_id ARBITRAIRE). src/middleware.ts n'est PAS en
-- cause et N'EST PAS modifié par cette migration.
--
-- =============================================================================
-- CORRECTIF — nouvelle RPC public.get_my_portal_role() :
--
--   - SANS PARAMÈTRE : n'utilise que auth.uid(). Ne peut donc JAMAIS servir à
--     sonder le statut d'un tiers.
--   - STABLE, SECURITY DEFINER, search_path verrouillé à '' (vide — tous les
--     objets qualifiés par leur schéma : public.xxx, auth.xxx).
--   - Priorité de résolution EXPLICITE, dans cet ordre :
--       1. admin    — is_platform_superadmin() UNIQUEMENT (reproduit
--                      exactement le gate réel de /admin, cf. preuve live
--                      ci-dessus — is_project_admin() délibérément exclu)
--       2. verifier — is_authorized_verifier_identity(auth.uid())
--                      (accredited_verifiers.active = true)
--       3. client   — défaut (couvre aussi, à dessein, les admins
--                      d'organisation/regroupement — cf. décision produit
--                      ci-dessus)
--   - N'ACCORDE AUCUNE AUTORISATION : pur helper de ROUTAGE FRONTEND. Toute
--     vérification d'accès réelle continue de passer par les policies RLS et
--     par is_platform_superadmin() / is_organization_owner(p_org_id) /
--     is_aggregator_primary_admin(p_aggregator_id) /
--     is_authorized_verifier_identity() / is_assigned_verifier() évaluées
--     côté serveur sur CHAQUE requête protégée.
--   - REVOKE ALL FROM PUBLIC, anon, authenticated puis GRANT EXECUTE à
--     authenticated uniquement.
--   - Helpers canoniques préexistants uniquement — AUCUNE table, policy RLS
--     ou fonction existante modifiée, AUCUN droit RLS élargi.
--
-- DÉPENDANCES (doivent déjà exister sur la cible avant application) :
--   - public.is_platform_superadmin()             (base — 20260707110100 /
--                                                    20260707120000)
--   - public.is_authorized_verifier_identity(uuid) (carbone — migration 05)
--
-- Aucune donnée touchée : uniquement un objet de catalogue (fonction) + ses
-- privilèges. Aucun INSERT/UPDATE/DELETE/TRUNCATE. Idempotent.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP 1 — Prérequis
-- ---------------------------------------------------------------------------

DO $$
BEGIN
    IF to_regprocedure('public.is_platform_superadmin()') IS NULL THEN
        RAISE EXCEPTION
            'Prérequis manquant : public.is_platform_superadmin() n''existe pas sur cette base.';
    END IF;
    IF to_regprocedure('public.is_authorized_verifier_identity(uuid)') IS NULL THEN
        RAISE EXCEPTION
            'Prérequis manquant : public.is_authorized_verifier_identity(uuid) n''existe pas '
            'sur cette base (migration carbone 05 non appliquée ?).';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- STEP 2 — Fonction : public.get_my_portal_role()
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_my_portal_role()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION
            'get_my_portal_role() requiert une session authentifiée (auth.uid() IS NULL).'
            USING ERRCODE = '28000'; -- invalid_authorization_specification
    END IF;

    -- Priorité 1 : superadmin plateforme UNIQUEMENT — reproduit exactement
    -- le gate réel de /admin (src/app/admin/page.tsx, probe RLS sur
    -- audit_logs, is_platform_superadmin() seule). is_project_admin() a été
    -- délibérément exclu : équivalente à is_platform_superadmin() pour tous
    -- les comptes réels observés le 2026-08-01 (aucun 'project_admin' à ce
    -- jour), mais PAS structurellement identique (elle reconnaît en plus le
    -- rôle théorique 'project_admin') — l'inclure aurait pu, pour un futur
    -- compte 'project_admin', router vers une page qui le rejetterait.
    IF public.is_platform_superadmin() THEN
        RETURN 'admin';
    END IF;

    -- Priorité 2 : identité vérificateur accréditée ACTIVE
    -- (public.accredited_verifiers via public.is_authorized_verifier_identity,
    -- jamais interrogée directement — appel exclusivement avec v_uid =
    -- auth.uid(), jamais un identifiant fourni par l'appelant).
    IF public.is_authorized_verifier_identity(v_uid) THEN
        RETURN 'verifier';
    END IF;

    -- Défaut : client. Couvre À DESSEIN les admins d'organisation membre
    -- (organization_members.org_role='admin') et le primary_admin d'un
    -- regroupement (aggregator_admins.role='primary_admin') — ces statuts
    -- sont scopés à une entité précise (is_organization_owner(p_org_id),
    -- is_aggregator_primary_admin(p_aggregator_id)), pas un rôle de portail
    -- global. Ils naviguent depuis / vers leurs écrans scopés ; RLS décide de
    -- ce qu'ils y voient. Cf. décision produit documentée en en-tête.
    RETURN 'client';
END;
$function$;

COMMENT ON FUNCTION public.get_my_portal_role() IS
    'Rôle de PORTAIL (''admin''|''verifier''|''client'') de l''utilisateur courant, '
    'déterminé exclusivement à partir de auth.uid() — aucun paramètre, donc aucune '
    'capacité de sonder le statut d''un tiers. Destinée UNIQUEMENT au routage '
    'frontend post-connexion (quel portail afficher). NE CONSTITUE JAMAIS UNE '
    'AUTORISATION : toute vérification d''accès réelle doit continuer de passer par '
    'les policies RLS et par is_platform_superadmin() / is_organization_owner() / '
    'is_aggregator_primary_admin() / is_authorized_verifier_identity() / '
    'is_assigned_verifier() évaluées côté serveur sur chaque requête protégée. '
    'Priorité de résolution explicite : admin (is_platform_superadmin() SEULE — '
    'is_project_admin() délibérément exclu : équivalente en pratique pour tous '
    'les comptes réels observés le 2026-08-01, mais pas structurellement '
    'identique, elle reconnaît en plus le rôle théorique JWT ''project_admin'', '
    'jamais assigné à ce jour) > verifier '
    '(accredited_verifiers.active via is_authorized_verifier_identity(auth.uid())) '
    '> client (défaut — inclut à dessein les admins d''organisation/regroupement, '
    'rôles scopés à une entité précise, jamais un rôle de portail global).';

-- ---------------------------------------------------------------------------
-- STEP 3 — Privilèges : verrouillage total puis octroi minimal
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.get_my_portal_role() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_portal_role() TO authenticated;

-- =============================================================================
-- VÉRIFICATION POST-APPLICATION (à lancer manuellement, lecture seule) :
--
--   SELECT proname, prosecdef, proconfig
--   FROM pg_proc
--   WHERE proname = 'get_my_portal_role';
--   -- prosecdef doit être true ; proconfig doit contenir {search_path=""}
--
--   SELECT has_function_privilege('anon', 'public.get_my_portal_role()', 'EXECUTE');
--   -- doit retourner false
--   SELECT has_function_privilege('authenticated', 'public.get_my_portal_role()', 'EXECUTE');
--   -- doit retourner true
--
--   -- Re-vérification de la matrice (doit reproduire EXACTEMENT la table
--   -- ci-dessus — si un écart apparaît, NE PAS déployer le frontend qui en
--   -- dépend avant d'avoir compris pourquoi) :
--   SELECT u.email,
--          CASE WHEN public.is_platform_superadmin() THEN 'admin' -- (nécessite SET ROLE / test applicatif réel, pas superuser)
--          END
--   FROM auth.users u WHERE u.email LIKE '%@demo.metaltrace.ca';
--   -- NOTE : is_platform_superadmin()/is_authorized_verifier_identity()
--   -- lisent auth.jwt()/auth.uid() du RÔLE APPELANT, pas un paramètre — cette
--   -- requête ne peut donc PAS être exécutée telle quelle depuis le SQL
--   -- Editor (contexte postgres/service_role, pas une session utilisateur).
--   -- La vérification réelle doit se faire par connexion applicative (test
--   -- des 6 comptes, cf. plan de test) ou via SET ROLE authenticated +
--   -- set_config('request.jwt.claims', ...) par utilisateur, comme fait dans
--   -- supabase/seeds/demo/02_organizations.sql.
--
-- =============================================================================
-- ROLLBACK (à exécuter manuellement si besoin de revenir en arrière) :
--
--   DROP FUNCTION IF EXISTS public.get_my_portal_role();
--
-- Aucune donnée créée par cette migration ; le rollback est sans risque et
-- immédiat. IMPORTANT côté déploiement : le frontend corrigé (qui appelle
-- cette RPC) doit être redéployé vers la version PRÉCÉDENTE AVANT ou EN MÊME
-- TEMPS que ce rollback SQL — sinon login/page.tsx et AppLayout.tsx
-- échoueront leur appel RPC (fonction inexistante -> erreur 42883) sans
-- dégrader silencieusement vers 'client'.
-- =============================================================================
