-- ============================================================
-- Vérification en direct du schéma réel — À EXÉCUTER AVANT
-- d'appliquer 02_carbon_aggregator_memberships.sql
-- ============================================================
--
-- Objectif (point 2 de la revue du 14 juillet 2026, complété par le point 7
-- de la deuxième revue du même jour) : la migration 02 suppose certains noms
-- de colonnes et objets sur la base d'une recherche dans supabase/migrations/,
-- jugée insuffisante par précédent (INC-DATA-01, ADR-MVP.md §9novodecies —
-- l'historique versionné ne reflète pas toujours l'état réel de la base). Ce
-- script est PUREMENT EN LECTURE, ne modifie rien, et peut être exécuté sans
-- risque à tout moment.
--
-- CE FICHIER CONTIENT 11 REQUÊTES INDÉPENDANTES, DONC 11 JEUX DE RÉSULTATS
-- DISTINCTS (et non 6 — une version antérieure de ce fichier annonçait 6
-- résultats alors que sa section 5 contenait déjà deux requêtes séparées ;
-- corrigé ici). Exécutez-les UNE PAR UNE dans le SQL Editor Supabase (le
-- SQL Editor n'affiche que le résultat de la dernière requête lancée quand
-- plusieurs sont soumises ensemble).
--
-- DÉJÀ CONFIRMÉES le 14 juillet 2026 (requêtes 1, 2, 3, 4, 5, 6, 11) — pas
-- besoin de les relancer sauf si vous voulez re-vérifier : tout correspond
-- exactement à ce que la migration suppose (aggregators : id/name/description/
-- created_at/updated_at ; aggregator_admins : nominated_by CONFIRMÉ réel ;
-- idx_one_active_primary_admin : UNIQUE(aggregator_id) WHERE role='primary_admin'
-- AND revoked_at IS NULL ; les 4 fonctions helper avec signatures exactes ;
-- organizations.aggregator_id : uuid nullable, FK fk_organizations_aggregator_id
-- -> aggregators ON DELETE SET NULL ; catalogue event_type : 31/31 valeurs).
--
-- RESTE À EXÉCUTER (requêtes 7, 8, 9, 10 — ajoutées après la deuxième revue) :
-- la 9 est la plus importante (valeurs réelles de l'ENUM org_role, pour
-- confirmer si le script de tests doit utiliser 'membre' ou 'member').
--
-- ────────────────────────────────────────────────────────────
-- 1. Colonnes réelles de public.aggregators [DÉJÀ CONFIRMÉ]
-- ────────────────────────────────────────────────────────────
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'aggregators'
ORDER BY ordinal_position;

-- ────────────────────────────────────────────────────────────
-- 2. Colonnes réelles de public.aggregator_admins [DÉJÀ CONFIRMÉ —
--    nominated_by existe réellement]
-- ────────────────────────────────────────────────────────────
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'aggregator_admins'
ORDER BY ordinal_position;

-- ────────────────────────────────────────────────────────────
-- 3. Définition réelle de l'index idx_one_active_primary_admin [DÉJÀ CONFIRMÉ]
-- ────────────────────────────────────────────────────────────
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND indexname = 'idx_one_active_primary_admin';

-- ────────────────────────────────────────────────────────────
-- 4. Signatures réelles des quatre fonctions helper réutilisées [DÉJÀ CONFIRMÉ]
-- ────────────────────────────────────────────────────────────
SELECT
    p.proname AS fonction,
    pg_get_function_identity_arguments(p.oid) AS arguments,
    pg_get_function_result(p.oid) AS retour,
    p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('is_aggregator_admin', 'is_org_admin', 'is_organization_member', 'is_platform_superadmin')
ORDER BY p.proname;

-- ────────────────────────────────────────────────────────────
-- 5. Colonne organizations.aggregator_id — type réel [DÉJÀ CONFIRMÉ]
-- ────────────────────────────────────────────────────────────
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'organizations' AND column_name = 'aggregator_id';

-- ────────────────────────────────────────────────────────────
-- 6. FK associée à organizations.aggregator_id [DÉJÀ CONFIRMÉ —
--    fk_organizations_aggregator_id -> aggregators, ON DELETE SET NULL]
-- ────────────────────────────────────────────────────────────
SELECT
    tc.constraint_name,
    ccu.table_name AS references_table,
    rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
JOIN information_schema.referential_constraints rc
    ON rc.constraint_name = tc.constraint_name AND rc.constraint_schema = tc.table_schema
WHERE tc.table_schema = 'public'
  AND tc.table_name = 'organizations'
  AND tc.constraint_type = 'FOREIGN KEY'
  AND EXISTS (
      SELECT 1 FROM information_schema.key_column_usage kcu
      WHERE kcu.constraint_name = tc.constraint_name
        AND kcu.table_schema = tc.table_schema
        AND kcu.column_name = 'aggregator_id'
  );

-- ────────────────────────────────────────────────────────────
-- 7. organizations.created_at — existence et type [NOUVEAU, deuxième revue]
--    Requis par le backfill de la migration (section 2 : started_at =
--    organizations.created_at).
-- ────────────────────────────────────────────────────────────
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'organizations' AND column_name = 'created_at';

-- ────────────────────────────────────────────────────────────
-- 8. organizations.updated_at — existence et type [NOUVEAU, deuxième revue]
--    Requis par le trigger de compatibilité (section 4 : SET updated_at = now()
--    à chaque synchronisation de aggregator_id).
-- ────────────────────────────────────────────────────────────
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'organizations' AND column_name = 'updated_at';

-- ────────────────────────────────────────────────────────────
-- 9. Valeurs réelles de l'ENUM org_role [NOUVEAU, deuxième revue — LE PLUS
--    IMPORTANT DE CES 4 NOUVELLES REQUÊTES] : le script de tests utilise
--    'admin'::public.org_role et doit utiliser soit 'member' soit 'membre'
--    pour un rôle non-admin — à confirmer ici plutôt que de supposer.
-- ────────────────────────────────────────────────────────────
SELECT e.enumlabel, e.enumsortorder
FROM pg_enum e
JOIN pg_type t ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public' AND t.typname = 'org_role'
ORDER BY e.enumsortorder;

-- ────────────────────────────────────────────────────────────
-- 10. Triggers existants sur public.aggregator_admins [NOUVEAU, deuxième
--     revue, RESTREINT après cinquième revue] : informatif — cette migration
--     ne touche pas aggregator_admins, mais un trigger existant et inattendu
--     sur cette table pourrait interagir avec les INSERT faits par
--     create_aggregator_with_primary_admin(). Limité explicitement au schéma
--     public (renforcement après cinquième revue) — filtrer sur relname seul
--     aurait pu matcher une table de même nom dans un autre schéma.
-- ────────────────────────────────────────────────────────────
SELECT t.tgname, p.proname AS fonction_appelee, pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE n.nspname = 'public' AND c.relname = 'aggregator_admins' AND NOT t.tgisinternal;

-- ────────────────────────────────────────────────────────────
-- 11. Catalogue réel des event_type autorisés dans carbon_business_events
--     [DÉJÀ CONFIRMÉ — exactement 31 valeurs, incluant les 4 utilisées par
--     cette migration : aggregator_created, aggregator_admin_appointed,
--     aggregator_membership_started, aggregator_membership_ended]
-- ────────────────────────────────────────────────────────────
SELECT
    conname,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.carbon_business_events'::regclass
  AND conname = 'carbon_business_events_event_type_check';

-- ============================================================
-- Fin. Merci de rapporter au minimum les résultats des requêtes 7, 8, 9 et 10
-- (les 7 autres sont déjà confirmées) avant la prochaine révision.
-- ============================================================
