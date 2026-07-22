-- ============================================================
-- Migration 08 — credit_lots (cycle commercial, reconstruction transactionnelle)
-- ============================================================
--
-- STATUT : PROPOSITION SOUMISE POUR REVUE — NON EXÉCUTÉE.
-- Conception validée : Tranche0-Carbone-Architecture.md §16 (sixième version,
-- après quatre revues statiques et exécution réelle de la prévalidation live
-- en lecture seule du point 0). Autorisation explicite de rédaction du SQL
-- donnée par l'utilisateur le 22 juillet 2026, après confirmation du
-- correctif applicatif préalable (neutralisation de
-- src/app/api/aggregator/calculate-sale/route.ts, commit 12cf5d6, poussé sur
-- main, testé en direct : 503 conforme).
--
-- DÉCOUVERTE STRUCTURANTE (prévalidation live, §16 point 0) : la table
-- `credit_lots` réelle en production N'EST PAS un objet à créer ou à
-- modifier par simple ALTER — c'est une table héritée, antérieure à toute la
-- Tranche 0, structurellement étrangère au schéma conçu ici (colonnes
-- id/project_id(NOT NULL, FK CASCADE)/quantity_tco2e(double precision)/
-- vintage_year/status(4 valeurs, sans voided)/created_at/updated_at, sans
-- aucun lien vers credit_issuances). Décision retenue (§16 point 0bis/13.8) :
-- RECONSTRUCTION TRANSACTIONNELLE — renommer l'existant en
-- credit_lots_legacy_pre08, créer la table canonique credit_lots sous ce
-- même nom, créer triggers/RPC/RLS/policies/privilèges, s'auto-valider, puis
-- supprimer credit_lots_legacy_pre08 — le tout dans l'unique transaction
-- BEGIN...COMMIT de ce fichier. Aucune seconde table permanente, aucun
-- remodelage massif par ALTER TABLE de la structure legacy (les deux
-- alternatives explicitement écartées par l'utilisateur, §16 point 13.8).
--
-- DÉPENDANCES STRUCTURELLES (§16 point 0) :
--   01 (carbon_business_events à 37 valeurs — après extension par 07 —,
--       carbon_reject_update_delete())
--   05/06 (is_platform_operator/is_org_admin/is_organization_member/
--       is_platform_superadmin/is_aggregator_admin/is_assigned_verifier)
--   07 (credit_issuances, APPLIQUÉE ET VALIDÉE EN RÉEL le 21 juillet 2026,
--       110/110, voir ADR-MVP.md §15) — lue telle quelle, AUCUNE modification
--       de 07_carbon_issuances.sql, de ses 7 RPC, de leur signature ou de
--       leur corps. La seule interaction structurelle avec l'état de
--       credit_issuances est un trigger AFTER UPDATE posé PAR 08 sur cette
--       table — même patron déjà validé par 07 elle-même sur
--       platform_operators (table de 06, sans modifier 06_carbon_operator_and_mandates.sql).
--
-- PRÉALABLE APPLICATIF BLOQUANT (§16 point 0bis étape 1, DÉJÀ SATISFAIT) :
--   src/app/api/aggregator/calculate-sale/route.ts neutralisée en production
--   (commit 12cf5d6, testé 503 en direct le 22 juillet 2026) — elle ne lit
--   plus credit_lots.project_id. La vente reste explicitement indisponible
--   jusqu'à la migration 09.
--
-- 08 N'A AUCUNE DÉPENDANCE SQL VERS 09 (§16 point 11) : aucune référence à
-- credit_sales/credit_sale_lots ou tout autre objet de 09 dans ce fichier.
--
-- Aucune donnée réelle à migrer : la table legacy est vide (count(*) = 0,
-- confirmé par la prévalidation live du 22 juillet 2026, REVÉRIFIÉ ci-dessous
-- au moment de l'exécution — jamais supposé depuis un audit antérieur,
-- discipline INC-DATA-01).
--
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION — dépendances structurelles + audit EXACT de la table
--    legacy (§16 point 0bis étape 2 : préconditions bloquantes, revérifiées
--    au moment de l'exécution, jamais supposées depuis la prévalidation
--    antérieure qui peut être devenue périmée).
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_constraint_count   INT;
    v_index_count        INT;
    v_trigger_count      INT;
    v_policy_count       INT;
    v_dependent_count    INT;
    v_row_count          BIGINT;
    v_quantity_check_def TEXT;
    v_quantity_check_bin TEXT;
    v_quantity_normalized TEXT;
    v_status_check_def   TEXT;
    v_status_literals    TEXT[];
    v_status_sorted      TEXT[];
    v_table_owner        TEXT;
BEGIN
    -- 0.a Dépendances transverses (01/05/06/07 appliquées).
    IF to_regclass('public.carbon_business_events') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_business_events introuvable — la migration 01 a-t-elle été appliquée ?';
    END IF;
    IF to_regprocedure('public.carbon_reject_update_delete()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_reject_update_delete() introuvable (migration 01).';
    END IF;
    IF to_regprocedure('public.is_platform_superadmin()') IS NULL
       OR to_regprocedure('public.is_org_admin(uuid)') IS NULL
       OR to_regprocedure('public.is_organization_member(uuid)') IS NULL
       OR to_regprocedure('public.is_aggregator_admin(uuid)') IS NULL
       OR to_regprocedure('public.is_assigned_verifier(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : une fonction d''autorisation transverse (is_platform_superadmin/is_org_admin/is_organization_member/is_aggregator_admin/is_assigned_verifier) est introuvable.';
    END IF;
    IF to_regclass('public.aggregators') IS NULL OR to_regclass('public.profiles') IS NULL
       OR to_regclass('public.organizations') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : une table transverse de base (aggregators/profiles/organizations) est introuvable.';
    END IF;
    IF to_regclass('public.credit_issuances') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.credit_issuances introuvable — la migration 07 a-t-elle été appliquée ?';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'credit_issuances'
          AND column_name IN ('issuance_status','aggregator_id','operator_organization_id','quantity_tco2e','verification_outcome_id')
        GROUP BY table_name HAVING count(*) = 5
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_issuances n''a pas la forme attendue (issuance_status/aggregator_id/operator_organization_id/quantity_tco2e/verification_outcome_id) — la migration 07 a-t-elle été appliquée avec le schéma documenté au §15 ?';
    END IF;
    IF to_regclass('public.verification_outcomes') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.verification_outcomes introuvable — la migration 05 a-t-elle été appliquée ?';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'verification_outcomes'
          AND column_name = 'verification_session_id'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.verification_outcomes.verification_session_id introuvable.';
    END IF;
    IF to_regclass('public.credit_issuance_sources') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.credit_issuance_sources introuvable — la migration 07 a-t-elle été appliquée ?';
    END IF;

    -- 0.b Idempotence — cette migration ne doit être appliquée qu'une seule
    -- fois. Si credit_lots porte déjà aggregator_id/credit_issuance_id, le
    -- schéma canonique existe déjà (ré-exécution accidentelle). Si
    -- credit_lots_legacy_pre08 existe déjà, une exécution précédente a été
    -- interrompue après le RENAME mais avant un COMMIT réussi (ne devrait
    -- structurellement pas arriver — un ROLLBACK aurait dû tout annuler —
    -- mais vérifié explicitement, défense en profondeur).
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'credit_lots'
          AND column_name IN ('aggregator_id', 'credit_issuance_id')
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.credit_lots porte déjà aggregator_id/credit_issuance_id — cette migration a-t-elle déjà été appliquée ?';
    END IF;
    IF to_regclass('public.credit_lots_legacy_pre08') IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.credit_lots_legacy_pre08 existe déjà — reliquat d''une exécution précédente interrompue, réconciliation manuelle requise avant de continuer.';
    END IF;
    IF to_regclass('public.credit_lots') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.credit_lots (legacy) introuvable — cette migration attend l''objet hérité audité le 22 juillet 2026, pas une base vierge.';
    END IF;

    -- 0.c Audit EXACT de la structure legacy — colonnes (7, exactement
    -- celles auditées le 22 juillet 2026, §16 point 0). Un écart quelconque
    -- doit bloquer la migration plutôt que de continuer sur une hypothèse
    -- fausse.
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'credit_lots') <> 7 THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.credit_lots (legacy) n''a pas exactement 7 colonnes — structure différente de l''audit du 22 juillet 2026.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='id' AND data_type='uuid' AND is_nullable='NO') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.id (legacy) ne correspond pas à l''audit.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='project_id' AND data_type='uuid' AND is_nullable='NO') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.project_id (legacy) ne correspond pas à l''audit (attendu UUID NOT NULL).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='quantity_tco2e' AND data_type='double precision' AND is_nullable='NO') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.quantity_tco2e (legacy) ne correspond pas à l''audit (attendu double precision NOT NULL).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='vintage_year' AND data_type='integer' AND is_nullable='NO') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.vintage_year (legacy) ne correspond pas à l''audit (attendu integer NOT NULL).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='status' AND data_type='text' AND is_nullable='NO' AND column_default = '''available''::text') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.status (legacy) ne correspond pas à l''audit (attendu text NOT NULL DEFAULT ''available'').';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='created_at' AND data_type='timestamp with time zone' AND is_nullable='NO') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.created_at (legacy) ne correspond pas à l''audit.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='updated_at' AND data_type='timestamp with time zone' AND is_nullable='NO') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.updated_at (legacy) ne correspond pas à l''audit.';
    END IF;

    -- Contraintes — exactement 4 (pkey, fk CASCADE, 2 CHECK), noms et
    -- définitions exacts audités.
    SELECT count(*) INTO v_constraint_count FROM pg_constraint WHERE conrelid = 'public.credit_lots'::regclass;
    IF v_constraint_count <> 4 THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots (legacy) n''a pas exactement 4 contraintes (trouvé %) — structure différente de l''audit.', v_constraint_count;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.credit_lots'::regclass AND conname = 'credit_lots_pkey' AND contype = 'p') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_pkey (legacy) introuvable.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.credit_lots'::regclass AND conname = 'credit_lots_project_id_fkey'
          AND contype = 'f' AND confdeltype = 'c'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_project_id_fkey (legacy) introuvable ou ne porte pas ON DELETE CASCADE, contrairement à l''audit.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.credit_lots'::regclass AND conname = 'credit_lots_quantity_tco2e_check' AND contype = 'c'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_quantity_tco2e_check (legacy) introuvable.';
    END IF;
    -- (troisième revue statique, correction 4) : ENSEMBLE EXACT des valeurs
    -- littérales du CHECK, extrait par regexp_matches et comparé comme
    -- ensemble trié — même mécanisme que l'extraction du catalogue
    -- event_type en section 0bis. Remplace l'ancienne combinaison de 5
    -- ILIKE (présence des 4 valeurs attendues + absence de 'voided'), qui
    -- ne détectait ni une valeur EXTRA inattendue (ex. 'archived') ni une
    -- valeur mal orthographiée dont le nom contiendrait accidentellement un
    -- des 4 littéraux attendus comme sous-chaîne.
    SELECT pg_get_constraintdef(oid) INTO v_status_check_def
    FROM pg_constraint WHERE conrelid = 'public.credit_lots'::regclass AND conname = 'credit_lots_status_check' AND contype = 'c';
    IF v_status_check_def IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_status_check (legacy) introuvable.';
    END IF;
    SELECT array_agg(m[1]) INTO v_status_literals
    FROM regexp_matches(v_status_check_def, '''((?:[^'']|'''''')*)''', 'g') AS m;
    SELECT array_agg(x ORDER BY x) INTO v_status_sorted FROM unnest(v_status_literals) x;
    IF v_status_sorted IS DISTINCT FROM ARRAY['available','reserved','retired','sold']::text[] THEN
        RAISE EXCEPTION 'Prévalidation échouée : ensemble EXACT des valeurs de credit_lots_status_check (legacy) différent de l''audit (attendu exactement {available,reserved,retired,sold}, ''voided'' exclu) — trouvé : %.', v_status_literals;
    END IF;

    -- Index — exactement 3.
    SELECT count(*) INTO v_index_count FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'credit_lots';
    IF v_index_count <> 3 THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots (legacy) n''a pas exactement 3 index (trouvé %) — structure différente de l''audit.', v_index_count;
    END IF;

    -- Triggers — aucun attendu.
    SELECT count(*) INTO v_trigger_count FROM pg_trigger WHERE tgrelid = 'public.credit_lots'::regclass AND NOT tgisinternal;
    IF v_trigger_count <> 0 THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots (legacy) porte % trigger(s) — l''audit du 22 juillet 2026 n''en attendait aucun.', v_trigger_count;
    END IF;

    -- RLS — activée, exactement 3 policies (noms audités).
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.credit_lots'::regclass AND relrowsecurity = true) THEN
        RAISE EXCEPTION 'Prévalidation échouée : RLS n''est pas activée sur credit_lots (legacy), contrairement à l''audit.';
    END IF;
    SELECT count(*) INTO v_policy_count FROM pg_policy WHERE polrelid = 'public.credit_lots'::regclass;
    IF v_policy_count <> 3
       OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.credit_lots'::regclass AND polname = 'credit_lots_superadmin_all')
       OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.credit_lots'::regclass AND polname = 'credit_lots_admin_all')
       OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.credit_lots'::regclass AND polname = 'credit_lots_member_select')
    THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots (legacy) ne porte pas exactement les 3 policies auditées (credit_lots_superadmin_all/credit_lots_admin_all/credit_lots_member_select).';
    END IF;

    -- Aucune dépendance SQL externe (vue/règle référençant credit_lots).
    SELECT count(*) INTO v_dependent_count
    FROM pg_depend
    JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid
    JOIN pg_class AS dependent_view ON pg_rewrite.ev_class = dependent_view.oid
    JOIN pg_class AS source_table ON pg_depend.refobjid = source_table.oid
    WHERE source_table.relname = 'credit_lots'
      AND dependent_view.relname <> 'credit_lots';
    IF v_dependent_count <> 0 THEN
        RAISE EXCEPTION 'Prévalidation échouée : % objet(s) SQL dépendent de credit_lots (legacy) — l''audit n''en attendait aucun. Réconciliation manuelle requise avant reconstruction.', v_dependent_count;
    END IF;

    -- Table vide — aucune donnée à préserver.
    EXECUTE 'SELECT count(*) FROM public.credit_lots' INTO v_row_count;
    IF v_row_count <> 0 THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots (legacy) contient % ligne(s) — cette migration suppose une table vide (audit du 22 juillet 2026) et ne prévoit aucune reprise de données. Migration bloquée, stratégie de reprise distincte requise.', v_row_count;
    END IF;

    -- 0.d Defaults exacts (id/created_at/updated_at) — au-delà du seul
    -- default de status déjà vérifié en 0.c (deuxième revue statique,
    -- correction 2).
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='id' AND column_default ILIKE '%gen_random_uuid%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.id (legacy) n''a pas le default attendu (gen_random_uuid()).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='created_at' AND column_default ILIKE '%now()%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.created_at (legacy) n''a pas le default attendu (now()).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='updated_at' AND column_default ILIKE '%now()%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots.updated_at (legacy) n''a pas le default attendu (now()).';
    END IF;

    -- (troisième revue statique, correction 4, PUIS correction 5 — confirmée
    -- en direct, voir ci-dessous) : comparaison EXACTE normalisée, pas une
    -- sous-chaîne ILIKE — une correspondance ILIKE '%quantity_tco2e > 0%'
    -- aurait aussi accepté à tort une définition élargie comme
    -- "quantity_tco2e > 0 AND quantity_tco2e < 999999999", qui contient la
    -- même sous-chaîne sans être la même contrainte.
    --
    -- CONFIRMÉ EN DIRECT (quatrième revue statique, correction 5) :
    -- credit_lots.quantity_tco2e (legacy) est de type DOUBLE PRECISION —
    -- requête en lecture seule exécutée par l'utilisateur le 22 juillet
    -- 2026 : pg_get_constraintdef(oid) = "CHECK ((quantity_tco2e >
    -- (0)::double precision))" ; pg_get_expr(conbin, conrelid) =
    -- "(quantity_tco2e > (0)::double precision)" — confirme exactement
    -- l'hypothèse de rendu du cast anticipée lors de la troisième revue.
    -- La normalisation ci-dessous (cast ::double precision retiré après
    -- suppression des espaces) est donc l'exigence EXACTE, plus une
    -- simple tolérance défensive.
    SELECT pg_get_constraintdef(oid), pg_get_expr(conbin, conrelid) INTO v_quantity_check_def, v_quantity_check_bin
    FROM pg_constraint WHERE conrelid = 'public.credit_lots'::regclass AND conname = 'credit_lots_quantity_tco2e_check';
    IF v_quantity_check_def IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_quantity_tco2e_check (legacy) introuvable.';
    END IF;

    v_quantity_normalized := regexp_replace(v_quantity_check_def, '\s+', '', 'g');
    v_quantity_normalized := replace(v_quantity_normalized, '(0)::doubleprecision', '0');

    IF v_quantity_normalized <> 'CHECK((quantity_tco2e>0))' THEN
        RAISE EXCEPTION 'Prévalidation échouée : définition normalisée de credit_lots_quantity_tco2e_check (legacy) différente de l''audit (attendu "CHECK((quantity_tco2e>0))", cast ::double precision toléré) — trouvé pg_get_constraintdef=% / pg_get_expr=%.', v_quantity_check_def, v_quantity_check_bin;
    END IF;

    -- 0.e Index — noms ET définitions exactes (pas seulement leur nombre).
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credit_lots' AND indexname='credit_lots_pkey' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%(id)%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_pkey (legacy) absent ou différent de l''audit.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credit_lots' AND indexname='idx_credit_lots_project_id' AND indexdef ILIKE '%(project_id)%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : idx_credit_lots_project_id (legacy) absent ou différent de l''audit.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credit_lots' AND indexname='idx_credit_lots_status' AND indexdef ILIKE '%(status)%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : idx_credit_lots_status (legacy) absent ou différent de l''audit.';
    END IF;

    -- 0.f Privilèges EXACTS — différence symétrique (ni excès, ni manque)
    -- par rapport à l'audit du 22 juillet 2026, pas seulement une présence
    -- partielle vérifiée au cas par cas.
    --
    -- Cinquième revue statique, correctif faux positif : information_schema.
    -- role_table_grants expose aussi les privilèges IMPLICITES du
    -- PROPRIÉTAIRE de la table (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/
    -- REFERENCES/TRIGGER), en plus des GRANT explicites anon/authenticated.
    -- Une première exécution réelle (22 juillet 2026) a révélé que l'ensemble
    -- figé précédent ne les excluait pas, faisant échouer la prévalidation à
    -- tort (rollback automatique, aucun effet de bord — le garde-fou a
    -- fonctionné, mais sur un diagnostic incomplet). Le propriétaire réel est
    -- désormais récupéré DYNAMIQUEMENT depuis pg_tables.tableowner (jamais
    -- codé en dur 'postgres' à cet endroit précis) et exclu de la
    -- comparaison symétrique des DEUX côtés — seuls les 5 privilèges
    -- applicatifs (anon:SELECT, authenticated:SELECT/INSERT/UPDATE/DELETE)
    -- restent exigés EXACTEMENT ; tout autre grantee ou privilège, propriétaire
    -- excepté, continue de faire échouer 0.f.
    SELECT tableowner INTO v_table_owner FROM pg_tables WHERE schemaname = 'public' AND tablename = 'credit_lots';
    IF v_table_owner IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : impossible de déterminer le propriétaire réel de credit_lots (legacy) via pg_tables.';
    END IF;

    -- Élément de structure legacy également figé (audit du 22 juillet 2026) :
    -- le propriétaire attendu est 'postgres'. Vérifié séparément de
    -- l'exclusion dynamique ci-dessus, qui reste correcte même si cette
    -- valeur devait un jour différer.
    IF v_table_owner <> 'postgres' THEN
        RAISE EXCEPTION 'Prévalidation échouée : propriétaire réel de credit_lots (legacy) différent de l''audit (attendu ''postgres'', trouvé ''%'').', v_table_owner;
    END IF;

    IF EXISTS (
        SELECT grantee, privilege_type FROM information_schema.role_table_grants
        WHERE table_schema = 'public' AND table_name = 'credit_lots' AND grantee <> v_table_owner
        EXCEPT
        SELECT * FROM (VALUES ('anon','SELECT'), ('authenticated','DELETE'), ('authenticated','INSERT'),
                               ('authenticated','SELECT'), ('authenticated','UPDATE')) AS expected(grantee, privilege_type)
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots (legacy) porte au moins un privilège inattendu par rapport à l''audit (hors propriétaire réel %).', v_table_owner;
    END IF;
    IF EXISTS (
        SELECT * FROM (VALUES ('anon','SELECT'), ('authenticated','DELETE'), ('authenticated','INSERT'),
                               ('authenticated','SELECT'), ('authenticated','UPDATE')) AS expected(grantee, privilege_type)
        EXCEPT
        SELECT grantee, privilege_type FROM information_schema.role_table_grants
        WHERE table_schema = 'public' AND table_name = 'credit_lots' AND grantee <> v_table_owner
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : un privilège attendu par l''audit sur credit_lots (legacy) est manquant (hors propriétaire réel %).', v_table_owner;
    END IF;

    -- 0.g Policies — commande/rôles/expression exacts (via pg_policies),
    -- pas seulement leur nom.
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='credit_lots' AND policyname='credit_lots_superadmin_all'
          AND cmd = 'ALL' AND roles = ARRAY['authenticated']::name[]
          AND qual ILIKE '%is_platform_superadmin%' AND with_check ILIKE '%is_platform_superadmin%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_superadmin_all (legacy) commande/rôles/expression différents de l''audit.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='credit_lots' AND policyname='credit_lots_admin_all'
          AND cmd = 'ALL' AND roles = ARRAY['authenticated']::name[]
          AND qual ILIKE '%aggregators%' AND qual ILIKE '%projects%' AND with_check ILIKE '%aggregators%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_admin_all (legacy) commande/rôles/expression différents de l''audit.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='credit_lots' AND policyname='credit_lots_member_select'
          AND cmd = 'SELECT' AND roles = ARRAY['authenticated']::name[]
          AND qual ILIKE '%organization%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_lots_member_select (legacy) commande/rôles/expression différents de l''audit.';
    END IF;

    -- 0.h Absence de FK EXTERNE référençant credit_lots (aucune autre table
    -- ne pointe vers elle) — distinct de la vérification de dépendances SQL
    -- (vues/règles) déjà faite plus haut, qui ne couvrait pas les FK.
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE confrelid = 'public.credit_lots'::regclass AND contype = 'f') THEN
        RAISE EXCEPTION 'Prévalidation échouée : au moins une contrainte FK externe référence credit_lots (legacy) — l''audit n''en attendait aucune.';
    END IF;

    RAISE NOTICE 'Prévalidation réussie : dépendances structurelles présentes, structure legacy de credit_lots conforme EXACTEMENT à l''audit du 22 juillet 2026 (colonnes, contraintes, index, defaults, privilèges, policies, absence de FK externe), table vide.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 0bis. CATALOGUE D'ÉVÉNEMENTS — 37 → 38 valeurs (§16 point 9)
-- ────────────────────────────────────────────────────────────
-- credit_lot_issued/reserved/sold/retired/voided existent déjà dans le
-- catalogue depuis la migration 01 (object_type='credit_lot' déjà prévu) —
-- 08 les PRÉVALIDE, elle ne les ajoute pas. Seule credit_lot_underlying_issuance_cancelled
-- est réellement nouvelle. Même mécanisme de reconstruction sûre déjà
-- utilisé par 07 (35→37) : comparaison PAR ENSEMBLE, reconstruction
-- explicite depuis l'ensemble canonique cible (jamais depuis les littéraux
-- extraits), post-vérification stricte.
DO $$
DECLARE
    v_constraint_name TEXT;
    v_old_def         TEXT;
    v_literals        TEXT[];
    v_canonical_37    TEXT[] := ARRAY[
        -- Gouvernance des regroupements (6).
        'aggregator_created', 'aggregator_membership_started', 'aggregator_membership_ended',
        'aggregator_admin_appointed', 'aggregator_admin_revoked', 'aggregator_primary_admin_transferred',
        -- Rattachement CCF<->MRV (2).
        'ccf_mrv_link_started', 'ccf_mrv_link_ended',
        -- Vérification (4).
        'verification_session_started', 'verification_session_completed',
        'verification_outcome_recorded', 'verification_outcome_superseded',
        -- Émission réglementaire (7, après extension 07 : +marked_eligible/+externally_rejected).
        'credit_issuance_created', 'credit_issuance_submitted', 'credit_issuance_issued',
        'credit_issuance_externally_cancelled', 'credit_issuance_voided',
        'credit_issuance_marked_eligible', 'credit_issuance_externally_rejected',
        -- Cycle commercial des lots (5).
        'credit_lot_issued', 'credit_lot_reserved', 'credit_lot_sold', 'credit_lot_retired', 'credit_lot_voided',
        -- Vente / modèle financier (9).
        'credit_sale_created', 'credit_sale_cost_recorded', 'credit_sale_confirmed', 'credit_sale_cancelled',
        'credit_sale_settled', 'credit_sale_adjustment_recorded', 'credit_sale_allocation_recorded',
        'credit_sale_allocation_approved', 'credit_sale_allocation_paid',
        -- Opérateur/mandats (4, migration 06).
        'platform_operator_designated', 'platform_operator_revoked',
        'carbon_commercialization_mandate_granted', 'carbon_commercialization_mandate_revoked'
    ];
    v_canonical_38    TEXT[];
    v_sorted_literals TEXT[];
    v_sorted_37       TEXT[];
    v_sorted_38       TEXT[];
    v_new_def         TEXT;
    v_new_body        TEXT;
    v_check_def       TEXT;
BEGIN
    IF array_length(v_canonical_37, 1) <> 37 THEN
        RAISE EXCEPTION 'Erreur interne de la migration : le tableau canonique codé en dur ne contient pas exactement 37 valeurs (%) — vérifier le corps de cette migration.', array_length(v_canonical_37, 1);
    END IF;
    v_canonical_38 := v_canonical_37 || ARRAY['credit_lot_underlying_issuance_cancelled'];

    SELECT c.conname, pg_get_constraintdef(c.oid)
    INTO v_constraint_name, v_old_def
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    WHERE t.relname = 'carbon_business_events'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%event_type%';

    IF v_constraint_name IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : contrainte CHECK sur carbon_business_events.event_type introuvable — le catalogue d''événements (migration 01) est-il en place ?';
    END IF;

    SELECT array_agg(m[1]) INTO v_literals
    FROM regexp_matches(v_old_def, '''((?:[^'']|'''''')*)''', 'g') AS m;

    SELECT array_agg(x ORDER BY x) INTO v_sorted_literals FROM unnest(v_literals) x;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_37 FROM unnest(v_canonical_37) x;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_38 FROM unnest(v_canonical_38) x;

    IF v_sorted_literals = v_sorted_38 THEN
        RAISE NOTICE 'Catalogue event_type déjà à jour : composition IDENTIQUE à l''ensemble canonique des 38 valeurs attendues — aucune modification.';
    ELSIF v_sorted_literals = v_sorted_37 THEN
        SELECT string_agg(quote_literal(lit) || '::text', ', ')
        INTO v_new_body
        FROM unnest(v_canonical_38) AS lit;

        v_new_def := format('CHECK (event_type = ANY (ARRAY[%s]))', v_new_body);

        EXECUTE format('ALTER TABLE public.carbon_business_events DROP CONSTRAINT %I', v_constraint_name);
        EXECUTE format('ALTER TABLE public.carbon_business_events ADD CONSTRAINT %I %s', v_constraint_name, v_new_def);

        SELECT pg_get_constraintdef(c.oid) INTO v_check_def
        FROM pg_constraint c
        WHERE c.conname = v_constraint_name AND c.conrelid = 'public.carbon_business_events'::regclass;

        SELECT array_agg(m[1]) INTO v_literals
        FROM regexp_matches(v_check_def, '''((?:[^'']|'''''')*)''', 'g') AS m;
        SELECT array_agg(x ORDER BY x) INTO v_sorted_literals FROM unnest(v_literals) x;

        IF v_sorted_literals IS DISTINCT FROM v_sorted_38 THEN
            RAISE EXCEPTION 'Post-vérification échouée : la contrainte % reconstruite ne correspond pas EXACTEMENT à l''ensemble canonique des 38 valeurs attendues — reconciliation manuelle requise.', v_constraint_name;
        END IF;

        RAISE NOTICE 'Contrainte % reconstruite explicitement (37→38), composition vérifiée EXACTEMENT contre l''ensemble canonique (+credit_lot_underlying_issuance_cancelled).', v_constraint_name;
    ELSE
        RAISE EXCEPTION 'Prévalidation échouée : le catalogue event_type ne correspond EXACTEMENT ni à l''ensemble canonique des 37 valeurs attendues, ni à celui des 38 (avec la nouvelle) — composition actuelle différente de l''hypothèse documentée, reconciliation manuelle requise. Littéraux actuels : %', v_literals;
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. RECONSTRUCTION TRANSACTIONNELLE — renommer l'existant, créer le
--    canonique (§16 point 0bis étape 3 / point 1)
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.credit_lots RENAME TO credit_lots_legacy_pre08;

-- Renommer IMMÉDIATEMENT la contrainte PK (troisième revue statique,
-- correction 6 — commentaire corrigé, la version précédente se contredisait
-- elle-même) : ALTER TABLE ... RENAME CONSTRAINT sur une contrainte
-- PRIMARY KEY/UNIQUE renomme DÉJÀ, de façon native, l'index sous-jacent qui
-- la soutient (comportement Postgres documenté — pas seulement l'entrée
-- pg_constraint.conname). Un second ALTER INDEX ... RENAME ciblant l'ancien
-- nom credit_lots_pkey échouerait donc à l'exécution réelle (l'index ne
-- s'appelle déjà plus ainsi à ce stade) — c'était le bug bloquant corrigé en
-- deuxième revue statique, jamais détectable par pglast (valide
-- syntaxiquement, échoue seulement à l'exécution réelle). Sans CE
-- renommage de la contrainte (donc de son index), le CREATE TABLE
-- credit_lots (...PRIMARY KEY...) ci-dessous tenterait de créer un index
-- nommé credit_lots_pkey qui collisionnerait avec l'index legacy resté
-- sous ce nom malgré le RENAME TABLE ci-dessus — les noms d'index
-- partagent l'espace de noms du schéma (comme les tables, vues et
-- séquences), indépendamment du nom de la table qui les porte.
ALTER TABLE public.credit_lots_legacy_pre08 RENAME CONSTRAINT credit_lots_pkey TO credit_lots_legacy_pre08_pkey;

-- Les deux autres index legacy ne collisionnent avec aucun nom du nouveau
-- schéma (idx_credit_lots_credit_issuance/aggregator/commercial_status),
-- mais sont renommés par clarté (deuxième revue statique, correction 1) —
-- éviter toute ambiguïté pendant la fenêtre où les deux tables coexistent
-- au sein de cette même transaction.
ALTER INDEX public.idx_credit_lots_project_id RENAME TO idx_credit_lots_legacy_pre08_project_id;
ALTER INDEX public.idx_credit_lots_status RENAME TO idx_credit_lots_legacy_pre08_status;

CREATE TABLE public.credit_lots (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_issuance_id UUID NOT NULL REFERENCES public.credit_issuances(id) ON DELETE RESTRICT,
    aggregator_id      UUID NOT NULL REFERENCES public.aggregators(id) ON DELETE RESTRICT,
    -- forcé depuis credit_issuances.aggregator_id par le trigger BEFORE
    -- INSERT (section 2 ci-dessous), jamais une valeur simplement copiée/
    -- validée côté RPC — DB-owned, ignore toute valeur fournie par l'appelant.
    -- Pas de project_id : absente du nouveau schéma canonique (§16 points
    -- 0bis/1/13.5/13.8) — la route applicative qui la lisait est neutralisée
    -- en amont de cette migration (préalable bloquant, déjà satisfait).
    quantity_tco2e     NUMERIC(14,4) NOT NULL CHECK (quantity_tco2e > 0 AND quantity_tco2e <> 'NaN'::numeric),
    vintage_year       INT NOT NULL,
    -- validé contre les bornes fixes (>= 2015, <= année courante, §16 point
    -- 13.6) par issue_credit_lot() ET le trigger structurel — pas de CHECK
    -- de table ici (la borne supérieure dépend de clock_timestamp(), non
    -- immutable, donc non éligible à un CHECK statique).
    commercial_status  TEXT NOT NULL DEFAULT 'available'
                         CHECK (commercial_status IN ('available','reserved','sold','retired','voided')),
    void_cause         TEXT NULL CHECK (void_cause IN ('internal_correction','external_cancellation')),
    void_reason        TEXT NULL,
    voided_at          TIMESTAMPTZ NULL,
    voided_by          UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_by         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX idx_credit_lots_credit_issuance ON public.credit_lots(credit_issuance_id);
CREATE INDEX idx_credit_lots_aggregator ON public.credit_lots(aggregator_id);
CREATE INDEX idx_credit_lots_commercial_status ON public.credit_lots(commercial_status);

COMMENT ON TABLE public.credit_lots IS
  'Cycle commercial des lots de crédits carbone — reconstruite depuis un objet legacy pré-Tranche 0 (§16 Tranche0-Carbone-Architecture.md point 0bis, migration 08). commercial_status à 5 valeurs, machine à états définie intégralement ici (09 réutilise le même trigger). Colonnes figées (credit_issuance_id, aggregator_id, quantity_tco2e, vintage_year, created_by, created_at) immuables après création, imposé par trigger.';

-- ────────────────────────────────────────────────────────────
-- 2. TRIGGERS (§16 points 3/3bis/4/4bis/6)
-- ────────────────────────────────────────────────────────────

-- BEFORE INSERT : champs DB-owned, jamais une simple validation (§16 point
-- 3bis, 12 étapes — l'ancienne étape 8bis de forçage de project_id a disparu
-- avec la colonne elle-même).
CREATE OR REPLACE FUNCTION public.carbon_guard_credit_lot_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor           UUID;
    v_issuance_status TEXT;
    v_aggregator_id   UUID;
    v_parent_quantity NUMERIC(14,4);
    v_consumed        NUMERIC(14,4);
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    IF NEW.void_cause IS NOT NULL OR NEW.void_reason IS NOT NULL OR NEW.voided_at IS NOT NULL OR NEW.voided_by IS NOT NULL THEN
        RAISE EXCEPTION 'Un lot ne peut être créé déjà voided : void_cause/void_reason/voided_at/voided_by doivent être NULL à l''INSERT.';
    END IF;

    SELECT issuance_status, aggregator_id, quantity_tco2e
    INTO v_issuance_status, v_aggregator_id, v_parent_quantity
    FROM public.credit_issuances
    WHERE id = NEW.credit_issuance_id
    FOR UPDATE;

    IF v_issuance_status IS NULL THEN
        RAISE EXCEPTION 'Émission introuvable (credit_issuance_id %).', NEW.credit_issuance_id;
    END IF;
    IF v_issuance_status <> 'issued' THEN
        RAISE EXCEPTION 'Un lot ne peut être créé que contre une émission au statut issued (statut réel : %).', v_issuance_status;
    END IF;

    -- DB-owned : forcé, jamais simplement validé contre la valeur fournie.
    NEW.aggregator_id := v_aggregator_id;
    NEW.commercial_status := 'available';
    NEW.created_by := v_actor;

    IF NEW.quantity_tco2e IS NULL OR NEW.quantity_tco2e <= 0 OR NEW.quantity_tco2e = 'NaN'::numeric THEN
        RAISE EXCEPTION 'quantity_tco2e doit être strictement positif et non NaN.';
    END IF;

    IF NEW.vintage_year IS NULL OR NEW.vintage_year < 2015 OR NEW.vintage_year > EXTRACT(YEAR FROM clock_timestamp())::INT THEN
        RAISE EXCEPTION 'vintage_year hors bornes (>= 2015, <= année courante) : %.', NEW.vintage_year;
    END IF;

    SELECT COALESCE(SUM(quantity_tco2e), 0) INTO v_consumed
    FROM public.credit_lots
    WHERE credit_issuance_id = NEW.credit_issuance_id AND commercial_status <> 'voided';

    IF v_consumed + NEW.quantity_tco2e > v_parent_quantity THEN
        RAISE EXCEPTION 'Plafond dépassé : % déjà lotis + % demandés > % émis (émission %).',
            v_consumed, NEW.quantity_tco2e, v_parent_quantity, NEW.credit_issuance_id;
    END IF;

    -- FORCÉ EN DERNIER, une fois tous les verrous/contrôles passés.
    NEW.created_at := clock_timestamp();

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_guard_credit_lot_insert
    BEFORE INSERT ON public.credit_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_credit_lot_insert();

-- BEFORE UPDATE : provenance figée + machine à états (5 statuts, y compris
-- reserved -> available, hors périmètre déclencheur de 08 mais dont la
-- validité structurelle est posée ici pour que 09 la réutilise telle quelle
-- — §16 points 3/4) + cohérence void_cause/statut parent (§16 point 4,
-- ferme le bypass direct).
CREATE OR REPLACE FUNCTION public.carbon_credit_lots_before_update()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_issuance_status TEXT;
    v_actor           UUID;
BEGIN
    IF NEW.credit_issuance_id IS DISTINCT FROM OLD.credit_issuance_id THEN
        RAISE EXCEPTION 'credit_issuance_id est figé : modification interdite.';
    END IF;
    IF NEW.aggregator_id IS DISTINCT FROM OLD.aggregator_id THEN
        RAISE EXCEPTION 'aggregator_id est figé : modification interdite.';
    END IF;
    IF NEW.quantity_tco2e IS DISTINCT FROM OLD.quantity_tco2e THEN
        RAISE EXCEPTION 'quantity_tco2e est figé : modification interdite.';
    END IF;
    IF NEW.vintage_year IS DISTINCT FROM OLD.vintage_year THEN
        RAISE EXCEPTION 'vintage_year est figé : modification interdite.';
    END IF;
    IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
        RAISE EXCEPTION 'created_by est figé : modification interdite.';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'created_at est figé : modification interdite.';
    END IF;

    IF NEW.commercial_status IS DISTINCT FROM OLD.commercial_status THEN
        IF NOT (
            (OLD.commercial_status = 'available' AND NEW.commercial_status = 'reserved') OR
            (OLD.commercial_status = 'reserved'  AND NEW.commercial_status = 'sold') OR
            (OLD.commercial_status = 'sold'      AND NEW.commercial_status = 'retired') OR
            (OLD.commercial_status = 'reserved'  AND NEW.commercial_status = 'available') OR
            (OLD.commercial_status = 'available' AND NEW.commercial_status = 'voided') OR
            (OLD.commercial_status = 'reserved'  AND NEW.commercial_status = 'voided')
        ) THEN
            RAISE EXCEPTION 'Transition de commercial_status refusée : % -> % n''est pas une transition valide.', OLD.commercial_status, NEW.commercial_status;
        END IF;

        IF NEW.commercial_status = 'voided' THEN
            IF OLD.void_cause IS NOT NULL OR OLD.void_reason IS NOT NULL OR OLD.voided_at IS NOT NULL OR OLD.voided_by IS NOT NULL THEN
                RAISE EXCEPTION 'Incohérence void_* : les colonnes void_cause/void_reason/voided_at/voided_by doivent être NULL avant le passage à voided.';
            END IF;

            -- (troisième revue statique, correction 3) : auth.uid() requis,
            -- voided_by/voided_at DÉSORMAIS DB-OWNED (forcés, jamais
            -- simplement validés contre la valeur fournie par l'appelant —
            -- même discipline que created_by/created_at à l'INSERT), et
            -- void_reason rejeté s'il est vide après btrim (pas seulement
            -- NULL).
            v_actor := auth.uid();
            IF v_actor IS NULL THEN
                RAISE EXCEPTION 'Authentification requise pour voider un lot.';
            END IF;
            IF NEW.void_cause IS NULL THEN
                RAISE EXCEPTION 'void_cause est requis lors du passage à voided.';
            END IF;
            IF NEW.void_reason IS NULL OR btrim(NEW.void_reason) = '' THEN
                RAISE EXCEPTION 'void_reason est requis (non vide) lors du passage à voided.';
            END IF;

            NEW.voided_by := v_actor;
            NEW.voided_at := clock_timestamp();

            -- (troisième revue statique, correction 2) : la validité de la
            -- transition dépend désormais du COUPLE (OLD.commercial_status,
            -- NEW.void_cause), pas seulement de OLD.commercial_status seul —
            -- le tableau de transitions ci-dessus autorise voided depuis
            -- available OU reserved (nécessaire), mais ne suffit pas à lui
            -- seul : internal_correction n'est valide QUE depuis available
            -- (void_credit_lot() ne s'applique jamais à un lot reserved),
            -- external_cancellation (cascade automatique) QUE depuis
            -- available OU reserved. Un lot reserved voidé avec
            -- internal_correction — ou tout autre couple hors de cette
            -- matrice — est structurellement rejeté ici, indépendamment de
            -- la RPC ou du trigger de cascade à l'origine de cet UPDATE.
            IF NEW.void_cause = 'internal_correction' THEN
                IF OLD.commercial_status <> 'available' THEN
                    RAISE EXCEPTION 'Incohérence structurelle : void_cause=internal_correction n''est valide que depuis available (statut réel avant transition : %).', OLD.commercial_status;
                END IF;

                SELECT issuance_status INTO v_issuance_status
                FROM public.credit_issuances WHERE id = NEW.credit_issuance_id FOR UPDATE;

                IF v_issuance_status <> 'issued' THEN
                    RAISE EXCEPTION 'Incohérence structurelle : void_cause=internal_correction exige que l''émission parente soit encore issued (statut réel : %).', v_issuance_status;
                END IF;
            ELSIF NEW.void_cause = 'external_cancellation' THEN
                IF OLD.commercial_status NOT IN ('available', 'reserved') THEN
                    RAISE EXCEPTION 'Incohérence structurelle : void_cause=external_cancellation n''est valide que depuis available ou reserved (statut réel avant transition : %).', OLD.commercial_status;
                END IF;

                SELECT issuance_status INTO v_issuance_status
                FROM public.credit_issuances WHERE id = NEW.credit_issuance_id FOR UPDATE;

                IF v_issuance_status <> 'externally_cancelled' THEN
                    RAISE EXCEPTION 'Incohérence structurelle : void_cause=external_cancellation exige que l''émission parente soit externally_cancelled (statut réel : %).', v_issuance_status;
                END IF;
            END IF;
        ELSE
            IF NEW.void_cause IS NOT NULL OR NEW.void_reason IS NOT NULL OR NEW.voided_at IS NOT NULL OR NEW.voided_by IS NOT NULL THEN
                RAISE EXCEPTION 'void_cause/void_reason/voided_at/voided_by ne peuvent être renseignées que lors du passage à voided.';
            END IF;
        END IF;
    ELSE
        IF NEW.void_cause IS DISTINCT FROM OLD.void_cause
           OR NEW.void_reason IS DISTINCT FROM OLD.void_reason
           OR NEW.voided_at IS DISTINCT FROM OLD.voided_at
           OR NEW.voided_by IS DISTINCT FROM OLD.voided_by THEN
            RAISE EXCEPTION 'void_cause/void_reason/voided_at/voided_by ne peuvent être modifiées qu''au moment du passage de commercial_status à voided.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_credit_lots_before_update
    BEFORE UPDATE ON public.credit_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_credit_lots_before_update();

-- BEFORE DELETE : interdiction structurelle (§16 point 4bis) — réutilise
-- carbon_reject_update_delete() (migration 01), même patron que
-- credit_issuances (07) et aggregator_memberships (02).
CREATE TRIGGER trg_carbon_credit_lots_forbid_delete
    BEFORE DELETE ON public.credit_lots
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- AFTER UPDATE OF issuance_status ON credit_issuances : cascade d'annulation
-- externe (§16 point 6) — posé PAR 08 SUR une table de 07, sans modifier
-- 07_carbon_issuances.sql (même patron déjà validé par 07 elle-même sur
-- platform_operators, table de 06).
CREATE OR REPLACE FUNCTION public.carbon_cascade_void_credit_lots_on_external_cancellation()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID;
    r       RECORD;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentification requise (cascade d''annulation externe).';
    END IF;

    -- La ligne credit_issuances (NEW.id) est déjà verrouillée : c'est
    -- l'UPDATE de record_external_cancellation() (07) elle-même qui
    -- déclenche ce trigger AFTER UPDATE. Verrouille ensuite les lots, même
    -- ordre émission-puis-lots que void_credit_lot().
    FOR r IN
        SELECT id, commercial_status FROM public.credit_lots
        WHERE credit_issuance_id = NEW.id
        FOR UPDATE
    LOOP
        IF r.commercial_status IN ('available', 'reserved') THEN
            -- voided_by/voided_at ne sont plus fournis ici : DB-owned,
            -- forcés par le trigger BEFORE UPDATE lui-même (troisième revue
            -- statique, correction 3) depuis auth.uid() de CET acteur
            -- (v_actor, capturé en tête de fonction) — jamais une valeur
            -- simplement recopiée.
            UPDATE public.credit_lots
            SET commercial_status = 'voided',
                void_cause = 'external_cancellation',
                void_reason = NEW.external_cancellation_reference
            WHERE id = r.id;

            INSERT INTO public.carbon_business_events
                (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
            SELECT 'credit_lot', r.id, 'credit_lot_voided', v_actor,
                   NEW.operator_organization_id, cl.aggregator_id, vo.verification_session_id,
                   jsonb_build_object('void_cause', 'external_cancellation', 'credit_issuance_id', NEW.id)
            FROM public.credit_lots cl
            JOIN public.verification_outcomes vo ON vo.id = NEW.verification_outcome_id
            WHERE cl.id = r.id;
        ELSIF r.commercial_status IN ('sold', 'retired') THEN
            -- Faits commerciaux historiques inchangés (§16 point 3) — aucune
            -- mutation, mais événement dédié pour tracer l'annulation
            -- réglementaire du sous-jacent.
            INSERT INTO public.carbon_business_events
                (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
            SELECT 'credit_lot', r.id, 'credit_lot_underlying_issuance_cancelled', v_actor,
                   NEW.operator_organization_id, cl.aggregator_id, vo.verification_session_id,
                   jsonb_build_object('credit_issuance_id', NEW.id)
            FROM public.credit_lots cl
            JOIN public.verification_outcomes vo ON vo.id = NEW.verification_outcome_id
            WHERE cl.id = r.id;
        END IF;
        -- 'voided' : déjà voided, aucune action (ne devrait pas se produire
        -- tant que l'émission était 'issued', robustesse uniquement).
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_cascade_void_credit_lots
    AFTER UPDATE OF issuance_status ON public.credit_issuances
    FOR EACH ROW
    WHEN (OLD.issuance_status IS DISTINCT FROM 'externally_cancelled' AND NEW.issuance_status = 'externally_cancelled')
    EXECUTE FUNCTION public.carbon_cascade_void_credit_lots_on_external_cancellation();

-- ────────────────────────────────────────────────────────────
-- 3. RPC (§16 points 6/7)
-- ────────────────────────────────────────────────────────────

-- issue_credit_lot() — émet un nouveau lot contre une émission issued
-- (§16 point 6/7).
CREATE OR REPLACE FUNCTION public.issue_credit_lot(
    p_credit_issuance_id UUID, p_quantity_tco2e NUMERIC, p_vintage_year INT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                    UUID;
    v_issuance_status          TEXT;
    v_operator_org_id          UUID;
    v_aggregator_id            UUID;
    v_outcome_id               UUID;
    v_parent_quantity          NUMERIC(14,4);
    v_consumed                 NUMERIC(14,4);
    v_new_id                   UUID;
    v_verification_session_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- Verrou + autorisation fusionnés en une seule requête (patron D13,
    -- §11/§15 point c) — jamais de fuite d'existence. Régime opérateur figé
    -- (is_org_admin(operator_organization_id) OU is_platform_superadmin()),
    -- cohérent avec 07 pour toute transition postérieure à submitted (§16
    -- point 6, réconciliation avec le régime figé de 07).
    SELECT issuance_status, operator_organization_id, aggregator_id, verification_outcome_id, quantity_tco2e
    INTO v_issuance_status, v_operator_org_id, v_aggregator_id, v_outcome_id, v_parent_quantity
    FROM public.credit_issuances
    WHERE id = p_credit_issuance_id
      AND (COALESCE(public.is_org_admin(operator_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;

    IF v_issuance_status IS NULL THEN
        RAISE EXCEPTION 'Émission introuvable ou accès refusé.';
    END IF;

    IF v_issuance_status <> 'issued' THEN
        RAISE EXCEPTION 'Émission au statut % : seule une émission issued peut produire des lots.', v_issuance_status;
    END IF;

    IF p_quantity_tco2e IS NULL OR p_quantity_tco2e <= 0 OR p_quantity_tco2e = 'NaN'::numeric THEN
        RAISE EXCEPTION 'p_quantity_tco2e doit être strictement positif et non NaN.';
    END IF;

    IF p_vintage_year IS NULL OR p_vintage_year < 2015 OR p_vintage_year > EXTRACT(YEAR FROM clock_timestamp())::INT THEN
        RAISE EXCEPTION 'p_vintage_year hors bornes (>= 2015, <= année courante) : %.', p_vintage_year;
    END IF;

    SELECT COALESCE(SUM(quantity_tco2e), 0) INTO v_consumed
    FROM public.credit_lots
    WHERE credit_issuance_id = p_credit_issuance_id AND commercial_status <> 'voided';

    IF v_consumed + p_quantity_tco2e > v_parent_quantity THEN
        RAISE EXCEPTION 'Plafond dépassé : % déjà lotis + % demandés > % émis.', v_consumed, p_quantity_tco2e, v_parent_quantity;
    END IF;

    -- commercial_status/aggregator_id/created_by/created_at fournis ici sont
    -- de toute façon écrasés par le trigger BEFORE INSERT (DB-owned) —
    -- omis pour que ce soit explicite.
    INSERT INTO public.credit_lots (credit_issuance_id, quantity_tco2e, vintage_year)
    VALUES (p_credit_issuance_id, p_quantity_tco2e, p_vintage_year)
    RETURNING id INTO v_new_id;

    SELECT verification_session_id INTO v_verification_session_id
    FROM public.verification_outcomes WHERE id = v_outcome_id;

    INSERT INTO public.carbon_business_events
        (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_lot', v_new_id, 'credit_lot_issued', v_actor, v_operator_org_id, v_aggregator_id, v_verification_session_id,
            jsonb_build_object('credit_issuance_id', p_credit_issuance_id, 'quantity_tco2e', p_quantity_tco2e, 'vintage_year', p_vintage_year));

    RETURN v_new_id;
END;
$$;

-- void_credit_lot() — correction interne, strictement bornée à un lot
-- encore available dont l'émission parente est encore issued (§16 points
-- 6/7, verrouillage émission-puis-lot).
CREATE OR REPLACE FUNCTION public.void_credit_lot(p_credit_lot_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                    UUID;
    v_credit_issuance_id       UUID;
    v_issuance_status          TEXT;
    v_operator_org_id          UUID;
    v_aggregator_id            UUID;
    v_outcome_id               UUID;
    v_commercial_status        TEXT;
    v_verification_session_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'p_reason est requis.';
    END IF;

    -- D13 (correction 3, deuxième revue statique) : lookup + autorisation
    -- FUSIONNÉS en une seule requête, JOIGNANT credit_lots à son émission
    -- parente. La version précédente séparait un premier SELECT non scopé
    -- sur credit_lots seul (message "Lot introuvable.") d'un second contrôle
    -- d'autorisation sur credit_issuances (message "Émission introuvable ou
    -- accès refusé.") — les deux messages distincts permettaient à un
    -- appelant de distinguer "le lot n'existe pas" de "le lot existe mais je
    -- n'y ai pas accès", fuite d'existence classique. Un seul message
    -- générique désormais, que le lot soit absent, que son émission parente
    -- soit absente, ou que l'acteur ne soit pas autorisé. SANS verrou à ce
    -- stade (le verrou vient ensuite, dans l'ordre prescrit par le §16
    -- point 6 : credit_issuances d'abord, puis credit_lots) — la fusion
    -- lookup+autorisation ne dépend pas de la prise de verrou elle-même.
    SELECT cl.credit_issuance_id, ci.operator_organization_id, ci.aggregator_id, ci.verification_outcome_id
    INTO v_credit_issuance_id, v_operator_org_id, v_aggregator_id, v_outcome_id
    FROM public.credit_lots cl
    JOIN public.credit_issuances ci ON ci.id = cl.credit_issuance_id
    WHERE cl.id = p_credit_lot_id
      AND (COALESCE(public.is_org_admin(ci.operator_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false));

    IF v_credit_issuance_id IS NULL THEN
        RAISE EXCEPTION 'Lot introuvable ou accès refusé.';
    END IF;

    -- Verrouille D'ABORD l'émission parente (échelle de verrous §16 point 6 :
    -- verification_sessions -> credit_issuances -> credit_lots) — relecture
    -- SOUS verrou de issuance_status (peut avoir changé entre le lookup non
    -- verrouillé ci-dessus et cette prise de verrou).
    --
    -- TOCTOU (quatrième revue statique, correction 1) : le premier lookup
    -- (D13 ci-dessus) confirme lot+autorisation à CET instant, mais rien
    -- n'empêche une révocation des droits admin de l'acteur entre ce lookup
    -- et la prise de verrou ci-dessous — sans revalidation, un acteur dont
    -- les droits viennent d'être révoqués pourrait encore agir sur la seule
    -- foi d'une autorisation déjà périmée. La condition d'autorisation
    -- (is_org_admin(operator_organization_id) OU is_platform_superadmin())
    -- est donc réévaluée ICI, dans le MÊME SELECT ... FOR UPDATE, contre la
    -- ligne fraîchement verrouillée. Absence de ligne -> même message
    -- générique que le lookup D13 (indiscernable d'un lot/émission
    -- inexistant depuis l'extérieur).
    SELECT ci.issuance_status INTO v_issuance_status
    FROM public.credit_issuances ci
    WHERE ci.id = v_credit_issuance_id
      AND (COALESCE(public.is_org_admin(ci.operator_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;

    IF v_issuance_status IS NULL THEN
        RAISE EXCEPTION 'Lot introuvable ou accès refusé.';
    END IF;

    IF v_issuance_status <> 'issued' THEN
        RAISE EXCEPTION 'Correction interne refusée : l''émission parente n''est plus issued (statut réel : %).', v_issuance_status;
    END IF;

    -- Verrouille ENSUITE le lot lui-même.
    SELECT commercial_status INTO v_commercial_status
    FROM public.credit_lots WHERE id = p_credit_lot_id FOR UPDATE;

    IF v_commercial_status <> 'available' THEN
        RAISE EXCEPTION 'Correction interne refusée : le lot doit être available (statut réel : %).', v_commercial_status;
    END IF;

    -- voided_by/voided_at ne sont plus fournis ici : DB-owned, forcés par le
    -- trigger BEFORE UPDATE lui-même (troisième revue statique, correction
    -- 3) depuis auth.uid(), jamais une valeur simplement recopiée depuis
    -- v_actor.
    UPDATE public.credit_lots
    SET commercial_status = 'voided',
        void_cause = 'internal_correction',
        void_reason = p_reason
    WHERE id = p_credit_lot_id;

    SELECT verification_session_id INTO v_verification_session_id
    FROM public.verification_outcomes WHERE id = v_outcome_id;

    INSERT INTO public.carbon_business_events
        (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_lot', p_credit_lot_id, 'credit_lot_voided', v_actor, v_operator_org_id, v_aggregator_id, v_verification_session_id,
            jsonb_build_object('void_cause', 'internal_correction', 'reason', p_reason));
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4. RLS (§16 point 8)
-- ────────────────────────────────────────────────────────────

-- Visibilité historique/figée (pas l'opérateur encore actif), même
-- architecture que can_view_credit_issuance() (07), corrigée pour ne jamais
-- perdre la visibilité d'un opérateur après un transfert.
CREATE OR REPLACE FUNCTION public.can_view_credit_lot(p_credit_lot_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.credit_lots cl
        JOIN public.credit_issuances ci ON ci.id = cl.credit_issuance_id
        WHERE cl.id = p_credit_lot_id
          AND (
               COALESCE(public.is_platform_superadmin(), false)
               OR COALESCE(public.is_organization_member(ci.operator_organization_id), false)
               OR COALESCE(public.is_aggregator_admin(cl.aggregator_id), false)
               OR COALESCE(public.is_assigned_verifier(
                    (SELECT vo.verification_session_id FROM public.verification_outcomes vo WHERE vo.id = ci.verification_outcome_id)
                  ), false)
               OR EXISTS (
                    SELECT 1 FROM public.credit_issuance_sources cis
                    WHERE cis.credit_issuance_id = ci.id
                      AND COALESCE(public.is_organization_member(cis.organization_id), false)
                  )
          )
    )
$$;

ALTER TABLE public.credit_lots ENABLE ROW LEVEL SECURITY;

CREATE POLICY credit_lots_select ON public.credit_lots
    FOR SELECT TO authenticated
    USING (public.can_view_credit_lot(id));

-- ────────────────────────────────────────────────────────────
-- 5. PRIVILÈGES — jamais PUBLIC seul (leçon 06a), explicite anon/authenticated.
-- ────────────────────────────────────────────────────────────
REVOKE ALL ON TABLE public.credit_lots FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.credit_lots TO authenticated;

REVOKE ALL ON FUNCTION public.can_view_credit_lot(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_credit_lot(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.issue_credit_lot(UUID, NUMERIC, INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_credit_lot(UUID, NUMERIC, INT) TO authenticated;

REVOKE ALL ON FUNCTION public.void_credit_lot(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_credit_lot(UUID, TEXT) TO authenticated;

-- Fonctions de trigger — usage interne uniquement, jamais appelées
-- directement (hygiène défensive, même patron que 07).
REVOKE ALL ON FUNCTION public.carbon_guard_credit_lot_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.carbon_credit_lots_before_update() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.carbon_cascade_void_credit_lots_on_external_cancellation() FROM PUBLIC, anon, authenticated;

-- ────────────────────────────────────────────────────────────
-- 6. AUTO-VALIDATION + SUPPRESSION DE LA TABLE LEGACY (§16 point 0bis étape
--    3 — la suppression fait partie de la MÊME transaction que la création
--    de remplacement, jamais une étape séparée ultérieure).
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regclass('public.credit_lots') IS NULL THEN
        RAISE EXCEPTION 'Auto-validation échouée : public.credit_lots (canonique) introuvable après création.';
    END IF;
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'credit_lots'
          AND column_name IN ('id','credit_issuance_id','aggregator_id','quantity_tco2e','vintage_year',
                               'commercial_status','void_cause','void_reason','voided_at','voided_by',
                               'created_by','created_at')) <> 12 THEN
        RAISE EXCEPTION 'Auto-validation échouée : credit_lots (canonique) n''a pas exactement les 12 colonnes attendues.';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='credit_lots' AND column_name='project_id') THEN
        RAISE EXCEPTION 'Auto-validation échouée : credit_lots (canonique) porte encore project_id — ne devrait structurellement jamais arriver.';
    END IF;
    IF to_regprocedure('public.issue_credit_lot(uuid,numeric,int)') IS NULL
       OR to_regprocedure('public.void_credit_lot(uuid,text)') IS NULL THEN
        RAISE EXCEPTION 'Auto-validation échouée : issue_credit_lot()/void_credit_lot() introuvables avec la signature attendue.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_lots'::regclass AND tgname = 'trg_carbon_guard_credit_lot_insert') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger BEFORE INSERT introuvable sur credit_lots.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_lots'::regclass AND tgname = 'trg_carbon_credit_lots_before_update') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger BEFORE UPDATE introuvable sur credit_lots.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_lots'::regclass AND tgname = 'trg_carbon_credit_lots_forbid_delete') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger BEFORE DELETE introuvable sur credit_lots.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.credit_issuances'::regclass AND tgname = 'trg_carbon_cascade_void_credit_lots') THEN
        RAISE EXCEPTION 'Auto-validation échouée : trigger de cascade introuvable sur credit_issuances.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.credit_lots'::regclass AND relrowsecurity = true) THEN
        RAISE EXCEPTION 'Auto-validation échouée : RLS non activée sur credit_lots (canonique).';
    END IF;
    IF NOT has_table_privilege('anon', 'public.credit_lots', 'SELECT') IS FALSE THEN
        RAISE EXCEPTION 'Auto-validation échouée : anon ne devrait avoir aucun privilège SELECT sur credit_lots (canonique).';
    END IF;

    RAISE NOTICE 'Auto-validation réussie : table canonique credit_lots conforme (12 colonnes, sans project_id, 4 triggers, RLS activée, RPC présentes). Suppression de credit_lots_legacy_pre08.';
END $$;

DROP TABLE public.credit_lots_legacy_pre08;

COMMIT;

-- Rechargement du cache de schéma PostgREST — nécessaire après un
-- RENAME/CREATE de cette nature (§16 point 0bis étape 4). Émis APRÈS le
-- COMMIT, séparément.
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- ROLLBACK (à exécuter séparément, jamais collé avec ce qui précède) —
-- ATTENTION : contrairement aux rollbacks des migrations 01-07, celui-ci ne
-- peut pas simplement DROP TABLE credit_lots pour revenir à l'état
-- antérieur, puisque la table legacy a été PHYSIQUEMENT SUPPRIMÉE par le
-- DROP TABLE de la section 6 (dans la même transaction que sa création de
-- remplacement, par construction). Un rollback après COMMIT reconstruit
-- donc la table legacy depuis son DDL exact, tel qu'audité le 22 juillet
-- 2026 (§16 point 0) — reconstruction fidèle, PAS une restauration depuis
-- une sauvegarde. Sans risque de perte de données : la table était vide
-- (count(*) = 0) au moment de la migration, revérifié structurellement en
-- section 0 ci-dessus avant toute opération destructive.
--
-- BEGIN;
--
-- -- 1) RPC (2).
-- DROP FUNCTION IF EXISTS public.void_credit_lot(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.issue_credit_lot(UUID, NUMERIC, INT);
--
-- -- 2) Policy — retirée explicitement AVANT le DROP de can_view_credit_lot(),
-- --    dont sa clause USING dépend (même leçon que 07, douzième revue statique).
-- DROP POLICY IF EXISTS credit_lots_select ON public.credit_lots;
-- DROP FUNCTION IF EXISTS public.can_view_credit_lot(UUID);
--
-- -- 3) Trigger de cascade posé PAR 08 sur credit_issuances (table de 07,
-- --    DÉJÀ APPLIQUÉE EN PRODUCTION — jamais supprimée elle-même, seul le
-- --    trigger et sa fonction, ajoutés par CE fichier, sont retirés ici).
-- DROP TRIGGER IF EXISTS trg_carbon_cascade_void_credit_lots ON public.credit_issuances;
-- DROP FUNCTION IF EXISTS public.carbon_cascade_void_credit_lots_on_external_cancellation();
--
-- -- 4) Table canonique credit_lots — entraîne la suppression de SES
-- --    triggers/policies (déjà retirées explicitement ci-dessus, mais le
-- --    DROP TABLE les aurait de toute façon emportées).
-- --
-- -- ⚠️ GARDE-FOU OBLIGATOIRE (amélioration documentaire, cinquième revue
-- -- statique) : ce DROP TABLE n'est SANS RISQUE que tant qu'AUCUN vrai lot
-- -- commercial n'a encore été créé via issue_credit_lot() depuis le COMMIT
-- -- de cette migration — le raisonnement "sans risque de perte de données"
-- -- au début de ce bloc ne vaut que pour la table LEGACY (credit_lots_legacy_pre08,
-- -- vide, revérifié en section 0), PAS pour la table CANONIQUE credit_lots
-- -- elle-même, qui accumule de vraies données commerciales dès le premier
-- -- appel réel à issue_credit_lot() en production. Avant d'exécuter CE
-- -- rollback, vérifier explicitement :
-- --     SELECT count(*) FROM public.credit_lots;
-- -- Si ce compte est > 0, NE JAMAIS exécuter ce DROP TABLE : il détruirait
-- -- des lots commerciaux réels, irréversiblement (credit_lots est
-- -- append-only, aucune sauvegarde applicative n'est prise ici). Dans ce
-- -- cas, ce rollback complet n'est plus une option — seule une migration
-- -- corrective ciblée, écrite au cas par cas, serait envisageable.
-- DROP TABLE IF EXISTS public.credit_lots;
--
-- -- 5) Fonctions de trigger laissées orphelines par le DROP TABLE ci-dessus.
-- DROP FUNCTION IF EXISTS public.carbon_guard_credit_lot_insert();
-- DROP FUNCTION IF EXISTS public.carbon_credit_lots_before_update();
--
-- -- 6) Reconstruction de la table legacy exactement telle qu'auditée le 22
-- --    juillet 2026 (§16 point 0) — DDL reconstruit à l'identique, pas une
-- --    restauration depuis une sauvegarde. Table nécessairement vide au
-- --    moment du rollback (elle l'était déjà avant cette migration, revérifié
-- --    en section 0, et 08 n'écrit jamais dans credit_lots_legacy_pre08).
-- CREATE TABLE public.credit_lots (
--     id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--     project_id     UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
--     quantity_tco2e DOUBLE PRECISION NOT NULL CHECK (quantity_tco2e > 0),
--     vintage_year   INTEGER NOT NULL,
--     status         TEXT NOT NULL DEFAULT 'available'
--                       CHECK (status = ANY (ARRAY['available'::text, 'reserved'::text, 'sold'::text, 'retired'::text])),
--     created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
--     updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
-- );
-- CREATE INDEX idx_credit_lots_project_id ON public.credit_lots(project_id);
-- CREATE INDEX idx_credit_lots_status ON public.credit_lots(status);
-- ALTER TABLE public.credit_lots ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY credit_lots_superadmin_all ON public.credit_lots
--     FOR ALL TO authenticated
--     USING (public.is_platform_superadmin())
--     WITH CHECK (public.is_platform_superadmin());
-- CREATE POLICY credit_lots_admin_all ON public.credit_lots
--     FOR ALL TO authenticated
--     USING (EXISTS (
--         SELECT 1 FROM public.projects p
--         JOIN public.operational_units ou ON ou.id = p.operational_unit_id
--         JOIN public.organizations org ON org.id = ou.organization_id
--         JOIN public.aggregators agg ON agg.id = org.aggregator_id
--         WHERE p.id = credit_lots.project_id AND public.is_aggregator_admin(agg.id)
--     ))
--     WITH CHECK (EXISTS (
--         SELECT 1 FROM public.projects p
--         JOIN public.operational_units ou ON ou.id = p.operational_unit_id
--         JOIN public.organizations org ON org.id = ou.organization_id
--         JOIN public.aggregators agg ON agg.id = org.aggregator_id
--         WHERE p.id = credit_lots.project_id AND public.is_aggregator_admin(agg.id)
--     ));
-- CREATE POLICY credit_lots_member_select ON public.credit_lots
--     FOR SELECT TO authenticated
--     USING (EXISTS (
--         SELECT 1 FROM public.projects p
--         JOIN public.operational_units ou ON ou.id = p.operational_unit_id
--         WHERE p.id = credit_lots.project_id AND public.is_organization_member(ou.organization_id)
--     ));
-- REVOKE ALL ON TABLE public.credit_lots FROM PUBLIC, authenticated;
-- GRANT SELECT ON TABLE public.credit_lots TO anon;
-- GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.credit_lots TO authenticated;
--
-- -- 7) Catalogue event_type (section 0bis) : CHOIX DOCUMENTÉ — PAS de
-- --    rollback automatique, même raisonnement que 07 (35->37). Laisser
-- --    credit_lot_underlying_issuance_cancelled au catalogue après ce
-- --    rollback est sans danger.
--
-- COMMIT;
--
-- NOTIFY pgrst, 'reload schema';
-- ============================================================
