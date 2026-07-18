-- ============================================================
-- Tests — Migration carbone 06/09 (platform_operators + carbon_commercialization_mandates)
-- ============================================================
--
-- Script de validation SÉPARÉ de la migration elle-même, même convention que
-- 01/02 : jamais mélanger DDL de migration et code de test. À exécuter APRÈS
-- avoir appliqué 06_carbon_operator_and_mandates.sql, jamais avant.
--
-- PROPOSITION NON APPLIQUÉE — à exécuter manuellement dans le SQL Editor
-- Supabase seulement après approbation, comme la migration elle-même.
--
-- Couvre spécifiquement, comme demandé en revue (14 juillet 2026) : RLS,
-- RPC, historique (platform_operators comme succession de désignations, pas
-- un booléen), réadhésion (un ancien mandat ne s'applique jamais à une
-- nouvelle adhésion), faux opérateur (operator_organization_id qui n'est pas
-- l'opérateur actif rejeté), doublons (deux opérateurs actifs simultanés,
-- deux mandats actifs pour la même adhésion), immutabilité (scope et toute
-- autre colonne figées après création, sauf la transition de révocation).
--
-- PRINCIPE (repris des migrations précédentes) : toute erreur INATTENDUE
-- doit faire échouer visiblement ce script. Seules les erreurs explicitement
-- ANTICIPÉES par un test précis sont capturées localement — aucun bloc
-- EXCEPTION WHEN OTHERS généralisé.
--
-- DONNÉES DE TEST : trois organisations et un regroupement jetables créés
-- directement (bypass RLS, rôle propriétaire des tables), plus une adhésion
-- (aggregator_memberships) insérée directement pour servir de socle aux
-- tests de mandat. Nettoyage explicite en fin de script — les tables
-- append-only (carbon_business_events, aggregator_memberships,
-- platform_operators, carbon_commercialization_mandates) nécessitent la
-- technique de désactivation temporaire du trigger de rejet DELETE.
--
-- SIMULATION D'AUTHENTIFICATION : même technique standard que les scripts
-- précédents — `set_config('request.jwt.claims', ..., true)`, dont
-- `auth.uid()`/`auth.jwt()` dérivent. Un seul profil réel est réutilisé
-- séquentiellement pour toutes les identités testées (super-admin, admin
-- d'organisation, appelant non autorisé), en faisant varier le contenu du
-- JWT simulé et les lignes organization_members entre chaque test. Le cas
-- « utilisateur externe » utilise un sub JWT aléatoire (gen_random_uuid())
-- qui ne correspond à aucune ligne nulle part.
--
-- PRÉCONDITION : au moins un profil doit exister dans public.profiles.
--
-- ⚠ PRÉCONDITION DE SÉCURITÉ SUPPLÉMENTAIRE, BLOQUANTE (revue du 14 juillet
-- 2026, point 2) : public.platform_operators DOIT être ENTIÈREMENT VIDE
-- avant le début de la Partie B — vérifié explicitement, arrêt immédiat
-- sinon. designate_platform_operator() révoque AUTOMATIQUEMENT l'opérateur
-- actif courant, quel qu'il soit, pour en désigner un nouveau (transfert
-- atomique, voir migration). Si un véritable opérateur METALTRACE avait
-- déjà été désigné avant ce script, B4/B6 le révoqueraient IRRÉVERSIBLEMENT
-- pour le remplacer par une organisation fictive de test. ORDRE OBLIGATOIRE :
-- migration 06 → CE SCRIPT → succès complet confirmé → SEULEMENT ENSUITE,
-- séparément, désignation réelle de METALTRACE via designate_platform_operator().
-- Ne jamais réexécuter ce script après cette désignation réelle sur le même
-- environnement.
--
-- RÉVISIONS DE LA REVUE DU 14 JUILLET 2026 (avant toute exécution) :
--   1. RLS mandats corrigée en amont (migration : is_active_platform_operator_member(),
--      pas is_platform_operator() seule) — B33/B34/B35 reformulés pour la couvrir.
--   2. Précondition dure platform_operators vide (ci-dessus).
--   3. D9 révisée : grant_commercialization_mandate() n'accepte plus le
--      super-admin seul — B14bis ajouté pour le confirmer explicitement.
--   4. Doublon dans scope désormais rejeté — B16bis ajouté.
--   5. p_mandate_document_id validé sémantiquement (D12) — B18bis ajouté
--      (document appartenant à une autre organisation rejeté) et B19/B19bis
--      mis à jour (chemin positif avec document valide, stockage vérifié).
--
-- RÉVISIONS DE LA REVUE PRÉCÉDENTE (14 juillet 2026, deux corrections
-- bloquantes sur l'isolation RLS) :
--   6. B32 utilisait encore un JWT app_metadata.role = 'admin' : un succès
--      pouvait donc s'expliquer par is_platform_superadmin() plutôt que par
--      l'appartenance organisationnelle réelle. Corrigé : JWT sans
--      super-admin, seule l'appartenance réelle à l'organisation titulaire
--      (déjà en place depuis avant B15) explique le résultat.
--   7. B34 n'isolait pas la branche is_active_platform_operator_member() :
--      le profil fixture restait membre/admin de l'organisation titulaire du
--      mandat, donc is_organization_member(organization_id) suffisait déjà à
--      elle seule. Corrigé : appartenance à l'organisation titulaire retirée
--      AVANT B34, seule l'appartenance à l'organisation opératrice
--      (v_operator_org_id_2) est active durant B34, JWT sans super-admin —
--      B34 ne peut plus réussir que via la branche opérateur. Les deux
--      appartenances sont ensuite rétablies dans leur état d'origine avant
--      B35 (retrait opérateur, restauration titulaire), pour rester cohérent
--      avec le reste du script et le nettoyage final.
--
-- RÉVISIONS DE LA DERNIÈRE REVUE (14 juillet 2026, fuite d'existence dans
-- les RPC SECURITY DEFINER d'écriture) :
--   8. grant_commercialization_mandate() (D13, migration) : recherche de
--      l'adhésion et vérification d'autorisation FUSIONNÉES dans la même
--      requête — message générique unique 'Adhésion introuvable ou accès
--      refusé.' pour un UUID inexistant ET pour une adhésion existante mais
--      inaccessible. B14/B14bis/B18 mis à jour pour vérifier ce message
--      identique dans les trois cas.
--   9. revoke_commercialization_mandate() (D13, migration) : même principe
--      dans le SELECT ... FOR UPDATE — message générique unique 'Mandat
--      introuvable ou accès refusé.' B24 mis à jour, B24bis ajouté pour
--      prouver qu'un UUID inexistant et un mandat existant mais inaccessible
--      sont indistinguables.
--  10. is_active_platform_operator_member() durcie avec
--      COALESCE(is_organization_member(...), false) (D14, migration) — aucun
--      test comportemental supplémentaire requis, is_organization_member()
--      ne renvoyait déjà jamais NULL dans les scénarios couverts par
--      B32/B34/B35, mais la garantie est désormais structurelle plutôt
--      qu'accidentelle.
--
-- RÉSULTAT ATTENDU : 22 assertions Partie A + 40 assertions Partie B = 62
-- assertions au total, succès attendu 62/62. (Ne pas confondre avec la
-- référence historique 56/56 de la migration 02 / aggregator_memberships,
-- non modifiée.)
-- ============================================================

CREATE TABLE IF NOT EXISTS public._carbon_migration_test_results (
    id        SERIAL PRIMARY KEY,
    section   TEXT NOT NULL,
    assertion TEXT NOT NULL,
    passed    BOOLEAN NOT NULL,
    detail    TEXT,
    run_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

REVOKE ALL ON public._carbon_migration_test_results
FROM PUBLIC, anon, authenticated;

TRUNCATE public._carbon_migration_test_results;

-- ════════════════════════════════════════════════════════════
-- PARTIE A — STRUCTURELLE
-- ════════════════════════════════════════════════════════════

INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
SELECT 'A1', 'table platform_operators existe',
       EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='platform_operators'), NULL
UNION ALL
SELECT 'A2', 'RLS activé sur platform_operators',
       COALESCE((SELECT relrowsecurity FROM pg_class WHERE relname='platform_operators' AND relnamespace='public'::regnamespace), false), NULL
UNION ALL
SELECT 'A3', 'index unique sur expression constante (au plus un actif) idx_one_active_platform_operator existe, filtré sur revoked_at IS NULL',
       EXISTS (
         SELECT 1 FROM pg_indexes
         WHERE schemaname='public' AND tablename='platform_operators' AND indexname='idx_one_active_platform_operator'
           AND indexdef ILIKE '%UNIQUE%'
           AND indexdef ILIKE '%revoked_at IS NULL%'
       ), NULL
UNION ALL
SELECT 'A4', 'trigger de garde UPDATE (platform_operators_guard_update) existe',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='platform_operators_guard_update' AND NOT tgisinternal), NULL
UNION ALL
SELECT 'A5', 'trigger de rejet DELETE (platform_operators_reject_delete) existe et réutilise carbon_reject_update_delete()',
       EXISTS (
         SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
         WHERE t.tgname = 'platform_operators_reject_delete' AND NOT t.tgisinternal
           AND p.proname = 'carbon_reject_update_delete'
       ), NULL
UNION ALL
SELECT 'A6', 'fonction is_platform_operator(uuid) existe, SECURITY DEFINER, STABLE, search_path durci',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='is_platform_operator' AND p.pronargs=1
           AND p.prosecdef AND p.provolatile = 's'
           AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg ILIKE 'search_path=%public%pg_temp%')
       ), NULL
UNION ALL
SELECT 'A7', 'fonction designate_platform_operator(uuid) existe, SECURITY DEFINER, search_path durci',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='designate_platform_operator' AND p.pronargs=1
           AND p.prosecdef
           AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg ILIKE 'search_path=%public%pg_temp%')
       ), NULL
UNION ALL
SELECT 'A8', 'fonction revoke_platform_operator(uuid,text) existe, SECURITY DEFINER, search_path durci',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='revoke_platform_operator' AND p.pronargs=2
           AND p.prosecdef
           AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg ILIKE 'search_path=%public%pg_temp%')
       ), NULL
UNION ALL
SELECT 'A9', 'table carbon_commercialization_mandates existe',
       EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='carbon_commercialization_mandates'), NULL
UNION ALL
SELECT 'A10', 'colonnes organization_id, aggregator_id, aggregator_membership_id, operator_organization_id toutes présentes',
       (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='public' AND table_name='carbon_commercialization_mandates'
          AND column_name IN ('organization_id','aggregator_id','aggregator_membership_id','operator_organization_id')) = 4, NULL
UNION ALL
SELECT 'A11', 'index unique UNIQUE(aggregator_membership_id) WHERE revoked_at IS NULL existe (un seul mandat actif par adhésion précise)',
       EXISTS (
         SELECT 1 FROM pg_indexes
         WHERE schemaname='public' AND tablename='carbon_commercialization_mandates'
           AND indexname='idx_carbon_commercialization_mandates_one_active_per_membership'
           AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%aggregator_membership_id%' AND indexdef ILIKE '%revoked_at IS NULL%'
       ), NULL
UNION ALL
SELECT 'A12', 'trigger de validation BEFORE INSERT (carbon_commercialization_mandates_validate) existe',
       EXISTS (
         SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
         WHERE t.tgname='carbon_commercialization_mandates_validate' AND NOT t.tgisinternal
           AND p.proname = 'carbon_validate_commercialization_mandate'
           AND pg_get_triggerdef(t.oid) ILIKE '%BEFORE INSERT%'
       ), NULL
UNION ALL
SELECT 'A13', 'trigger de garde UPDATE (carbon_commercialization_mandates_guard_update) existe',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='carbon_commercialization_mandates_guard_update' AND NOT tgisinternal), NULL
UNION ALL
SELECT 'A14', 'trigger de rejet DELETE (carbon_commercialization_mandates_reject_delete) existe et réutilise carbon_reject_update_delete()',
       EXISTS (
         SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
         WHERE t.tgname = 'carbon_commercialization_mandates_reject_delete' AND NOT t.tgisinternal
           AND p.proname = 'carbon_reject_update_delete'
       ), NULL
UNION ALL
SELECT 'A15', 'contrainte CHECK scope : catalogue fermé à 8 valeurs, non vide (COALESCE array_length)',
       (SELECT pg_get_constraintdef(oid) FROM pg_constraint
        WHERE conrelid = 'public.carbon_commercialization_mandates'::regclass AND conname ILIKE '%scope%check%'
        LIMIT 1) ILIKE '%COALESCE%' , NULL
UNION ALL
SELECT 'A16', 'fonctions grant_commercialization_mandate(uuid,uuid,text[],uuid) et revoke_commercialization_mandate(uuid,text) existent, SECURITY DEFINER, search_path durci',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='grant_commercialization_mandate' AND p.pronargs=4
           AND p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg ILIKE 'search_path=%public%pg_temp%')
       )
       AND EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='revoke_commercialization_mandate' AND p.pronargs=2
           AND p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg ILIKE 'search_path=%public%pg_temp%')
       ), NULL
UNION ALL
-- Renforcement : count exact du catalogue event_type (35, pas seulement présence des 4 nouvelles).
SELECT 'A17', 'catalogue event_type étendu à exactement 35 valeurs (31 + 4), incluant les 4 nouvelles',
       (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
        WHERE c.conrelid = 'public.carbon_business_events'::regclass AND c.conname = 'carbon_business_events_event_type_check'
       ) ILIKE '%platform_operator_designated%'
       AND (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
            WHERE c.conrelid = 'public.carbon_business_events'::regclass AND c.conname = 'carbon_business_events_event_type_check'
           ) ILIKE '%carbon_commercialization_mandate_revoked%'
       AND (SELECT array_length(regexp_split_to_array(pg_get_constraintdef(c.oid), ','), 1) FROM pg_constraint c
            WHERE c.conrelid = 'public.carbon_business_events'::regclass AND c.conname = 'carbon_business_events_event_type_check'
           ) = 35, NULL
UNION ALL
SELECT 'A18', 'catalogue object_type étendu à exactement 14 valeurs (12 + 2), incluant platform_operator et carbon_commercialization_mandate',
       (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
        WHERE c.conrelid = 'public.carbon_business_events'::regclass AND c.conname = 'carbon_business_events_object_type_check'
       ) ILIKE '%platform_operator%'
       AND (SELECT array_length(regexp_split_to_array(pg_get_constraintdef(c.oid), ','), 1) FROM pg_constraint c
            WHERE c.conrelid = 'public.carbon_business_events'::regclass AND c.conname = 'carbon_business_events_object_type_check'
           ) = 14, NULL
UNION ALL
SELECT 'A19', 'authenticated a SELECT mais aucun privilège d''écriture direct sur platform_operators et carbon_commercialization_mandates',
       has_table_privilege('authenticated', 'public.platform_operators', 'SELECT')
       AND NOT has_table_privilege('authenticated', 'public.platform_operators', 'INSERT')
       AND NOT has_table_privilege('authenticated', 'public.platform_operators', 'UPDATE')
       AND NOT has_table_privilege('authenticated', 'public.platform_operators', 'DELETE')
       AND has_table_privilege('authenticated', 'public.carbon_commercialization_mandates', 'SELECT')
       AND NOT has_table_privilege('authenticated', 'public.carbon_commercialization_mandates', 'INSERT')
       AND NOT has_table_privilege('authenticated', 'public.carbon_commercialization_mandates', 'UPDATE')
       AND NOT has_table_privilege('authenticated', 'public.carbon_commercialization_mandates', 'DELETE'), NULL
UNION ALL
SELECT 'A20', 'anon n''a aucun privilège sur les deux nouvelles tables',
       NOT has_table_privilege('anon', 'public.platform_operators', 'SELECT')
       AND NOT has_table_privilege('anon', 'public.carbon_commercialization_mandates', 'SELECT'), NULL
UNION ALL
SELECT 'A21', 'privilège EXECUTE réel : accordé à authenticated, absent de anon, pour les 6 nouvelles fonctions',
       COALESCE((SELECT bool_and(
           has_function_privilege('authenticated', p.oid, 'EXECUTE')
           AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
        )
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public'
          AND ((p.proname='is_platform_operator' AND p.pronargs=1)
            OR (p.proname='is_active_platform_operator_member' AND p.pronargs=1)
            OR (p.proname='designate_platform_operator' AND p.pronargs=1)
            OR (p.proname='revoke_platform_operator' AND p.pronargs=2)
            OR (p.proname='grant_commercialization_mandate' AND p.pronargs=4)
            OR (p.proname='revoke_commercialization_mandate' AND p.pronargs=2))), false), NULL
UNION ALL
-- D11 (correctif bloquant) : le nouveau helper existe, SECURITY DEFINER,
-- STABLE, search_path durci — même patron structurel que is_platform_operator().
SELECT 'A22', 'fonction is_active_platform_operator_member(uuid) existe, SECURITY DEFINER, STABLE, search_path durci',
       EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='is_active_platform_operator_member' AND p.pronargs=1
           AND p.prosecdef AND p.provolatile = 's'
           AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg ILIKE 'search_path=%public%pg_temp%')
       ), NULL;

-- ════════════════════════════════════════════════════════════
-- PARTIE B — COMPORTEMENTALE
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_ok                     BOOLEAN;
    v_fixture_profile_id     UUID;
    v_operator_org_id        UUID;
    v_operator_org_id_2      UUID;
    v_member_org_id          UUID;
    v_test_aggregator_id     UUID;
    v_membership_id          UUID;
    v_membership_id_2        UUID;
    v_platform_operator_id   UUID;
    v_platform_operator_id_2 UUID;
    v_mandate_id             UUID;
    v_mandate_id_2           UUID;
    v_outsider_uid           UUID;
    v_rls_count              INTEGER;
    v_wrong_org_document_id  UUID;
    v_member_org_document_id UUID;
BEGIN
    PERFORM set_config('request.jwt.claims', '{}', true);

    SELECT id INTO v_fixture_profile_id FROM public.profiles ORDER BY created_at LIMIT 1;
    IF v_fixture_profile_id IS NULL THEN
        RAISE EXCEPTION 'Précondition de test non satisfaite : aucun profil dans public.profiles pour simuler un contexte authentifié.';
    END IF;

    -- ⚠ PRÉCONDITION DE SÉCURITÉ BLOQUANTE (revue du 14 juillet 2026, point 2) :
    -- platform_operators DOIT être entièrement vide. designate_platform_operator()
    -- révoque automatiquement l'opérateur actif courant quel qu'il soit — si un
    -- véritable opérateur METALTRACE existait déjà, B4/B6 le révoqueraient
    -- IRRÉVERSIBLEMENT. Arrêt immédiat et explicite plutôt qu'un risque silencieux.
    IF EXISTS (SELECT 1 FROM public.platform_operators) THEN
        RAISE EXCEPTION 'Précondition de sécurité non satisfaite : public.platform_operators contient déjà des lignes. Ce script ne doit être exécuté qu''immédiatement après la migration 06, AVANT toute désignation réelle de l''opérateur METALTRACE — une exécution ultérieure révoquerait irréversiblement un opérateur réel. Arrêt sans aucune modification.';
    END IF;

    INSERT INTO public.organizations (name) VALUES ('__test_migration_06_operator__') RETURNING id INTO v_operator_org_id;
    INSERT INTO public.organizations (name) VALUES ('__test_migration_06_operator_2__') RETURNING id INTO v_operator_org_id_2;
    INSERT INTO public.organizations (name) VALUES ('__test_migration_06_member__') RETURNING id INTO v_member_org_id;
    INSERT INTO public.aggregators (name) VALUES ('__test_migration_06_aggregator__') RETURNING id INTO v_test_aggregator_id;

    INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by)
    VALUES (v_member_org_id, v_test_aggregator_id, v_fixture_profile_id)
    RETURNING id INTO v_membership_id;

    -- ────────────────────────────────────────────────────────
    -- B1-B12 : platform_operators — historique, garde-fous, RLS.
    -- ────────────────────────────────────────────────────────

    -- B1. is_platform_operator() renvoie strictement FALSE (jamais NULL) pour
    -- une organisation qui n'est opérateur de rien (D3, EXISTS-based).
    v_ok := (public.is_platform_operator(v_operator_org_id) IS FALSE);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B1', 'is_platform_operator() renvoie strictement false (jamais NULL) pour une organisation non désignée', v_ok, NULL);

    -- B2. designate_platform_operator() sans contexte authentifié.
    v_ok := false;
    BEGIN
        PERFORM public.designate_platform_operator(v_operator_org_id);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Authentification requise.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B2', 'designate_platform_operator() sans contexte authentifié lève "Authentification requise."', v_ok, NULL);

    -- Contexte authentifié SANS super-admin.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text, true);

    -- B3. designate_platform_operator() rejetée pour un appelant non super-admin (D4).
    v_ok := false;
    BEGIN
        PERFORM public.designate_platform_operator(v_operator_org_id);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Seul un super-administrateur de la plateforme peut désigner l''opérateur METALTRACE.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B3', 'designate_platform_operator() rejetée pour un appelant non super-admin (D4)', v_ok, NULL);

    -- Contexte super-admin simulé.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object('role', 'admin'))::text, true);

    -- B4. designate_platform_operator() réussit pour un super-admin.
    v_platform_operator_id := public.designate_platform_operator(v_operator_org_id);
    v_ok := v_platform_operator_id IS NOT NULL AND (public.is_platform_operator(v_operator_org_id) IS TRUE);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B4', 'designate_platform_operator() réussit pour un super-admin, is_platform_operator() devient true', v_ok, v_platform_operator_id::text);

    -- B5 (doublon). Désigner la MÊME organisation déjà active est rejeté explicitement.
    v_ok := false;
    BEGIN
        PERFORM public.designate_platform_operator(v_operator_org_id);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Cette organisation est déjà l''opérateur METALTRACE actif.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B5', 'designate_platform_operator() rejette une organisation déjà opérateur actif (doublon)', v_ok, NULL);

    -- B6 (historique + doublon). Désigner une DEUXIÈME organisation révoque
    -- automatiquement la première — jamais deux actifs simultanés (D2).
    v_platform_operator_id_2 := public.designate_platform_operator(v_operator_org_id_2);
    v_ok := (public.is_platform_operator(v_operator_org_id) IS FALSE) AND (public.is_platform_operator(v_operator_org_id_2) IS TRUE);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B6', 'désigner un deuxième opérateur révoque automatiquement le premier — jamais deux actifs simultanés (D2)', v_ok, v_platform_operator_id_2::text);

    -- B7 (renforcé, D15, dernière revue — pas de nouvelle assertion, le
    -- résultat attendu reste 62/62). L'ancienne ligne platform_operators
    -- garde une trace historique exacte de la révocation (D1 — historique,
    -- pas un booléen), ET — c'est l'ajout de cette revue — l'horodatage de
    -- cette révocation est EXACTEMENT identique (=, pas seulement >=) à
    -- designated_at de la nouvelle ligne : les deux écritures partagent
    -- désormais la même capture v_transition_at := clock_timestamp() dans
    -- designate_platform_operator(), plutôt que clock_timestamp() d'un côté
    -- et le DEFAULT now() (figé au début de la transaction) de l'autre, ce
    -- qui pouvait auparavant faire apparaître la nouvelle désignation comme
    -- antérieure à la révocation de l'ancienne.
    v_ok := EXISTS (
        SELECT 1 FROM public.platform_operators old_row
        JOIN public.platform_operators new_row ON new_row.id = v_platform_operator_id_2
        WHERE old_row.id = v_platform_operator_id
          AND old_row.revoked_at IS NOT NULL
          AND old_row.revoke_reason = 'Remplacé par la désignation d''un nouvel opérateur.'
          AND old_row.revoked_at = new_row.designated_at
    );
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B7', 'l''ancienne désignation reste historisée avec revoked_at et revoke_reason renseignés (D1), ET ancien.revoked_at = nouveau.designated_at exactement — transition temporelle cohérente (D15)', v_ok, NULL);

    -- Contexte authentifié SANS super-admin, pour B8.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text, true);

    -- B8. revoke_platform_operator() rejetée pour un appelant non super-admin.
    v_ok := false;
    BEGIN
        PERFORM public.revoke_platform_operator(v_operator_org_id_2, 'tentative non autorisée');
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Seul un super-administrateur de la plateforme peut révoquer l''opérateur METALTRACE.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B8', 'revoke_platform_operator() rejetée pour un appelant non super-admin (D4)', v_ok, NULL);

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object('role', 'admin'))::text, true);

    -- B9. revoke_platform_operator() rejetée si l'organisation ciblée n'est
    -- PAS l'opérateur actuellement actif (v_operator_org_id a déjà été révoquée en B6).
    v_ok := false;
    BEGIN
        PERFORM public.revoke_platform_operator(v_operator_org_id, 'cible incorrecte');
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Cette organisation n''est pas l''opérateur METALTRACE actuellement actif.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B9', 'revoke_platform_operator() rejette une organisation qui n''est pas l''opérateur actif', v_ok, NULL);

    -- B10 (immutabilité). UPDATE direct d'une colonne autre que revoked_at/revoked_by/revoke_reason rejeté.
    v_ok := false;
    BEGIN
        UPDATE public.platform_operators SET organization_id = v_operator_org_id WHERE id = v_platform_operator_id_2;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B10', 'UPDATE direct de organization_id sur platform_operators rejeté (immutabilité)', v_ok, NULL);

    -- B11. DELETE rejeté (append-only).
    v_ok := false;
    BEGIN
        DELETE FROM public.platform_operators WHERE id = v_platform_operator_id_2;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B11', 'DELETE sur platform_operators rejeté (append-only)', v_ok, NULL);

    -- B12 (RLS). N'importe quel utilisateur authentifié peut lire platform_operators.
    v_outsider_uid := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_outsider_uid, 'app_metadata', json_build_object())::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO v_rls_count FROM public.platform_operators WHERE id = v_platform_operator_id_2;
    EXECUTE 'RESET ROLE';
    v_ok := (v_rls_count = 1);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B12', 'RLS (rôle authenticated réel) : tout utilisateur authentifié peut lire platform_operators', v_ok, NULL);

    -- ────────────────────────────────────────────────────────
    -- B13-B33 : carbon_commercialization_mandates — cohérence, faux
    -- opérateur, doublons, immutabilité, réadhésion, RLS.
    -- ────────────────────────────────────────────────────────

    PERFORM set_config('request.jwt.claims', '{}', true);

    -- B13. grant_commercialization_mandate() sans contexte authentifié.
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY['sell_credits']);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Authentification requise.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B13', 'grant_commercialization_mandate() sans contexte authentifié lève "Authentification requise."', v_ok, NULL);

    -- Contexte authentifié, ni admin d'organisation, ni super-admin.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text, true);

    -- B14 (D9 révisée + D13, fuite d'existence corrigée en dernière revue).
    -- Rejetée : appelant authentifié mais PAS admin de l'organisation
    -- titulaire. Message générique — la recherche de l'adhésion et
    -- l'autorisation sont désormais fusionnées dans la même requête, donc ce
    -- cas produit EXACTEMENT le même message qu'un UUID d'adhésion
    -- inexistant (voir B18) : impossible de distinguer "cette adhésion
    -- n'existe pas" de "cette adhésion existe mais vous n'y avez pas droit".
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY['sell_credits']);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Adhésion introuvable ou accès refusé.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B14', 'grant_commercialization_mandate() rejetée pour un appelant qui n''est pas admin de l''organisation titulaire, message générique indistinguable d''un UUID inexistant (D9 révisée, D13)', v_ok, NULL);

    -- Contexte SUPER-ADMIN, mais TOUJOURS pas admin de l'organisation titulaire.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object('role', 'admin'))::text, true);

    -- B14bis (D9 révisée, bloquant — cœur de la correction demandée). Le
    -- super-admin SEUL ne peut PLUS accorder un mandat au nom d'un membre —
    -- l'octroi exige le consentement explicite de l'organisation elle-même
    -- (is_org_admin), la dérogation super-admin a été retirée sans
    -- ambiguïté. Si ce test échoue, la régression la plus probable est un
    -- retour accidentel de la dérogation dans la RPC. Même message générique
    -- que B14/B18 (D13) : un super-admin non-membre de l'organisation
    -- titulaire ne reçoit aucune information distinguant son absence de
    -- droits d'une adhésion inexistante.
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY['sell_credits']);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Adhésion introuvable ou accès refusé.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B14bis', 'grant_commercialization_mandate() rejetée pour un super-admin qui n''est PAS admin de l''organisation titulaire — aucune dérogation, message générique indistinguable (D9 révisée, D13, bloquant)', v_ok, NULL);

    -- Retour à un contexte authentifié normal (pas super-admin) pour la suite.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text, true);

    -- Le profil devient admin de l'organisation titulaire de l'adhésion.
    INSERT INTO public.organization_members (organization_id, user_id, org_role, status, activated_at)
    VALUES (v_member_org_id, v_fixture_profile_id, 'admin'::public.org_role, 'active', now());

    -- B15. Scope contenant une valeur hors catalogue fermé rejeté (D8).
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY['not_a_valid_scope_value']);
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B15', 'scope contenant une valeur hors catalogue fermé rejeté par CHECK (D8)', v_ok, NULL);

    -- B16 (bug NULL-in-CHECK corrigé). Scope vide '{}' rejeté grâce au
    -- COALESCE(array_length(...), 0) — sans ce correctif, array_length('{}',1)
    -- renvoie NULL et un CHECK NULL est traité comme satisfait par PostgreSQL.
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY[]::TEXT[]);
    EXCEPTION WHEN check_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B16', 'scope vide (tableau vide) rejeté par CHECK — COALESCE(array_length(...),0) > 0, pas un NULL qui passerait silencieusement', v_ok, NULL);

    -- B16bis (doublon dans scope, correction demandée en revue). Un scope
    -- contenant deux fois la même valeur (toutes deux valides individuellement)
    -- est rejeté par le trigger de validation (impossible à exprimer en CHECK
    -- déclaratif, voir D8).
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY['sell_credits', 'sell_credits']);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'carbon_commercialization_mandates : scope ne peut contenir de valeurs dupliquées.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B16bis', 'scope contenant une valeur dupliquée rejeté par le trigger de validation (D8)', v_ok, NULL);

    -- B17 (faux opérateur). operator_organization_id = v_operator_org_id, qui
    -- N'EST PLUS l'opérateur actif (révoquée en B6) — rejeté par le trigger de validation.
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id, ARRAY['sell_credits']);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'carbon_commercialization_mandates : operator_organization_id ne correspond pas à l''opérateur METALTRACE actuellement actif.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B17', 'grant_commercialization_mandate() rejette un operator_organization_id qui n''est pas l''opérateur actif (faux opérateur, D7)', v_ok, NULL);

    -- B18 (D13). aggregator_membership_id inexistant rejeté avec EXACTEMENT
    -- le même message générique que B14/B14bis (appelant authentifié mais
    -- non autorisé, adhésion pourtant existante) — un UUID qui n'existe pas
    -- du tout et un UUID d'adhésion réel mais inaccessible sont désormais
    -- rigoureusement indistinguables du point de vue de l'appelant. Exécuté
    -- ici alors que le profil fixture EST admin de l'organisation titulaire
    -- de v_membership_id (depuis avant B15) : seul l'UUID aléatoire, qui ne
    -- correspond à aucune ligne, explique l'échec — pas un défaut
    -- d'autorisation.
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(gen_random_uuid(), v_operator_org_id_2, ARRAY['sell_credits']);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Adhésion introuvable ou accès refusé.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B18', 'grant_commercialization_mandate() rejette un aggregator_membership_id inexistant, message générique indistinguable de B14/B14bis (D13)', v_ok, NULL);

    -- Fixtures pour la validation sémantique de p_mandate_document_id (D12).
    -- Colonnes NOT NULL réelles de public.documents (vérifiées contre le
    -- schéma live, renforcement demandé en dernière revue) : owner_org_id,
    -- object_type, object_id, title — toutes fournies explicitement
    -- ci-dessous. category et storage_path sont NULLABLE ; version,
    -- visibility, status, created_at, updated_at ont toutes une valeur
    -- DEFAULT non NULL — aucune autre colonne NOT NULL sans défaut n'existe.
    INSERT INTO public.documents (owner_org_id, object_type, object_id, title)
    VALUES (v_operator_org_id, 'mandate', gen_random_uuid(), '__test_migration_06_wrong_org_document__')
    RETURNING id INTO v_wrong_org_document_id;

    INSERT INTO public.documents (owner_org_id, object_type, object_id, title)
    VALUES (v_member_org_id, 'mandate', gen_random_uuid(), '__test_migration_06_member_org_document__')
    RETURNING id INTO v_member_org_document_id;

    -- B18bis (D12, correction demandée en revue). Un document existant mais
    -- appartenant à une AUTRE organisation (pas la titulaire de l'adhésion)
    -- est rejeté — la seule contrainte FK l'aurait accepté puisque le
    -- document existe réellement quelque part.
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY['sell_credits'], v_wrong_org_document_id);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'p_mandate_document_id doit référencer un document appartenant à l''organisation titulaire de l''adhésion.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B18bis', 'grant_commercialization_mandate() rejette un mandate_document_id appartenant à une autre organisation (validation sémantique, D12)', v_ok, NULL);

    -- B19 (chemin positif). Admin d'organisation, opérateur réellement actif,
    -- adhésion active, scope valide, document appartenant à la bonne
    -- organisation — succès.
    v_mandate_id := public.grant_commercialization_mandate(
        v_membership_id, v_operator_org_id_2, ARRAY['aggregate_reductions','sell_credits','distribute_net_proceeds'], v_member_org_document_id
    );
    v_ok := v_mandate_id IS NOT NULL;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B19', 'grant_commercialization_mandate() réussit pour un admin d''organisation, opérateur actif réel, adhésion active, document valide', v_ok, v_mandate_id::text);

    -- B19bis. mandate_document_id correctement stocké (D12, validé positivement).
    v_ok := EXISTS (SELECT 1 FROM public.carbon_commercialization_mandates WHERE id = v_mandate_id AND mandate_document_id = v_member_org_document_id);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B19bis', 'mandate_document_id correctement stocké lorsqu''il appartient à la bonne organisation', v_ok, NULL);

    -- B20 (cohérence D6). organization_id/aggregator_id stockés correspondent
    -- EXACTEMENT à l'adhésion référencée — dérivés par la RPC, jamais fournis.
    v_ok := EXISTS (
        SELECT 1 FROM public.carbon_commercialization_mandates
        WHERE id = v_mandate_id AND organization_id = v_member_org_id AND aggregator_id = v_test_aggregator_id
    );
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B20', 'organization_id/aggregator_id stockés correspondent exactement à l''adhésion référencée (D6)', v_ok, NULL);

    -- B21 (doublon). Un deuxième mandat actif pour la MÊME adhésion est rejeté
    -- par l'index unique partiel (D5).
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY['sell_credits']);
    EXCEPTION WHEN unique_violation THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B21', 'un deuxième mandat actif pour la même adhésion est rejeté par l''index unique partiel (doublon, D5)', v_ok, NULL);

    -- B22 (immutabilité, D8). UPDATE direct de scope rejeté.
    v_ok := false;
    BEGIN
        UPDATE public.carbon_commercialization_mandates SET scope = ARRAY['sell_credits'] WHERE id = v_mandate_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B22', 'UPDATE direct de scope sur un mandat existant rejeté — immuable après création (D8)', v_ok, NULL);

    -- B23. DELETE rejeté (append-only).
    v_ok := false;
    BEGIN
        DELETE FROM public.carbon_commercialization_mandates WHERE id = v_mandate_id;
    EXCEPTION WHEN raise_exception THEN
        v_ok := true;
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B23', 'DELETE sur carbon_commercialization_mandates rejeté (append-only)', v_ok, NULL);

    -- Utilisateur externe, sans aucune relation.
    v_outsider_uid := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_outsider_uid, 'app_metadata', json_build_object())::text, true);

    -- B24 (D13, fuite d'existence corrigée). revoke_commercialization_mandate()
    -- rejetée pour un appelant non autorisé, sur un p_mandate_id EXISTANT
    -- (v_mandate_id) — message générique, la recherche du mandat et
    -- l'autorisation sont désormais fusionnées dans le même
    -- SELECT ... FOR UPDATE.
    v_ok := false;
    BEGIN
        PERFORM public.revoke_commercialization_mandate(v_mandate_id, 'tentative non autorisée');
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Mandat introuvable ou accès refusé.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B24', 'revoke_commercialization_mandate() rejetée pour un appelant ni admin d''organisation ni super-admin, message générique (D13)', v_ok, NULL);

    -- B24bis (D13, bloquant — cœur de la correction demandée). MÊME contexte
    -- outsider non autorisé que B24, mais cette fois avec un p_mandate_id
    -- ALÉATOIRE qui ne correspond à AUCUNE ligne existante. Le message doit
    -- être RIGOUREUSEMENT IDENTIQUE à celui de B24 — sinon un appelant non
    -- autorisé pourrait distinguer par essais successifs "ce mandat existe
    -- mais je n'y ai pas droit" de "ce mandat n'existe pas du tout", ce qui
    -- constitue précisément la fuite d'existence signalée en dernière revue.
    v_ok := false;
    BEGIN
        PERFORM public.revoke_commercialization_mandate(gen_random_uuid(), 'uuid inexistant');
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Mandat introuvable ou accès refusé.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B24bis', 'revoke_commercialization_mandate() rejette un p_mandate_id inexistant avec EXACTEMENT le même message générique qu''un mandat existant mais inaccessible (B24) — indistinguables (D13, bloquant)', v_ok, NULL);

    -- Restaure le profil admin d'organisation.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text, true);

    -- B25. revoke_commercialization_mandate() réussit pour l'admin de l'organisation titulaire.
    PERFORM public.revoke_commercialization_mandate(v_mandate_id, 'fin test migration 06 (B25)');
    v_ok := EXISTS (SELECT 1 FROM public.carbon_commercialization_mandates WHERE id = v_mandate_id AND revoked_at IS NOT NULL);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B25', 'revoke_commercialization_mandate() réussit pour l''admin de l''organisation titulaire', v_ok, NULL);

    -- B26. Une deuxième révocation du même mandat est rejetée.
    v_ok := false;
    BEGIN
        PERFORM public.revoke_commercialization_mandate(v_mandate_id, 'double révocation');
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'Ce mandat est déjà révoqué.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B26', 'revoke_commercialization_mandate() rejette un mandat déjà révoqué', v_ok, NULL);

    -- B27 (D5). La révocation du mandat ne met PAS fin à l'adhésion sous-jacente.
    v_ok := (SELECT ended_at FROM public.aggregator_memberships WHERE id = v_membership_id) IS NULL;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B27', 'la révocation du mandat ne met pas fin à aggregator_memberships (objets distincts, D5)', v_ok, NULL);

    -- ────────────────────────────────────────────────────────
    -- B28-B31 : scénario de réadhésion — un ancien mandat ne s'applique
    -- jamais à une nouvelle adhésion (D5, cœur de la correction demandée).
    -- ────────────────────────────────────────────────────────

    -- Termine l'adhésion (départ du regroupement).
    UPDATE public.aggregator_memberships
    SET ended_at = clock_timestamp(), ended_by = v_fixture_profile_id, end_reason = 'fin test migration 06 (réadhésion, B28+)'
    WHERE id = v_membership_id;

    -- B28. Un nouveau mandat sur l'adhésion désormais TERMINÉE est rejeté.
    v_ok := false;
    BEGIN
        PERFORM public.grant_commercialization_mandate(v_membership_id, v_operator_org_id_2, ARRAY['sell_credits']);
    EXCEPTION WHEN raise_exception THEN
        v_ok := (SQLERRM = 'carbon_commercialization_mandates : l''adhésion référencée par aggregator_membership_id est déjà terminée (ended_at renseigné) — aucun nouveau mandat ne peut lui être rattaché.');
    END;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B28', 'grant_commercialization_mandate() rejette une adhésion déjà terminée', v_ok, NULL);

    -- Réadhésion : nouvelle ligne aggregator_memberships, nouvel identifiant.
    INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by)
    VALUES (v_member_org_id, v_test_aggregator_id, v_fixture_profile_id)
    RETURNING id INTO v_membership_id_2;

    -- B29. Aucun mandat n'existe automatiquement pour la NOUVELLE adhésion —
    -- l'ancien mandat (rattaché à l'ancienne adhésion) ne se propage jamais.
    v_ok := NOT EXISTS (SELECT 1 FROM public.carbon_commercialization_mandates WHERE aggregator_membership_id = v_membership_id_2);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B29', 'aucun mandat n''existe automatiquement pour une nouvelle adhésion après réadhésion (D5)', v_ok, NULL);

    -- B30. Un NOUVEAU mandat explicite est requis et réussit pour la nouvelle adhésion.
    v_mandate_id_2 := public.grant_commercialization_mandate(v_membership_id_2, v_operator_org_id_2, ARRAY['sell_credits']);
    v_ok := v_mandate_id_2 IS NOT NULL AND v_mandate_id_2 IS DISTINCT FROM v_mandate_id;
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B30', 'un nouveau mandat explicite est requis et réussit pour la nouvelle adhésion (D5)', v_ok, v_mandate_id_2::text);

    -- B31. L'ancien mandat, rattaché à l'ancienne adhésion, reste inchangé
    -- (toujours révoqué depuis B25) — aucune propagation, aucune réactivation.
    v_ok := EXISTS (
        SELECT 1 FROM public.carbon_commercialization_mandates
        WHERE id = v_mandate_id AND aggregator_membership_id = v_membership_id AND revoked_at IS NOT NULL
    );
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B31', 'l''ancien mandat (ancienne adhésion) reste inchangé après la réadhésion — pas de réactivation accidentelle', v_ok, NULL);

    -- ────────────────────────────────────────────────────────
    -- B32-B35 : RLS (rôle authenticated réel) sur carbon_commercialization_mandates.
    -- Reformulé en revue du 14 juillet 2026, puis DURCI en dernière revue
    -- (14 juillet 2026, deux corrections bloquantes) : chaque test doit
    -- isoler UNE SEULE branche de la policy à la fois (is_platform_superadmin()
    -- OR is_organization_member(organization_id) OR is_aggregator_admin(aggregator_id)
    -- OR is_active_platform_operator_member(operator_organization_id)) —
    -- sinon un succès ne prouve rien de la branche visée :
    --   B32 : JWT sans super-admin, appartenance réelle à l'organisation
    --         titulaire (organization_id) seule active.
    --   B33 : précondition de preuve — l'opérateur référencé est bien actif.
    --   B34 : appartenance à l'organisation titulaire RETIRÉE au préalable,
    --         seule l'appartenance à l'organisation opératrice METALTRACE
    --         est active, JWT sans super-admin — succès possible UNIQUEMENT
    --         via is_active_platform_operator_member().
    --   B35 : aucune appartenance, aucune relation — sub JWT aléatoire.
    -- (is_aggregator_admin() ne peut jamais s'activer par accident ici : elle
    -- dépend de la table dédiée aggregator_admins, dans laquelle le profil
    -- fixture n'est jamais inséré par ce script.)
    -- ────────────────────────────────────────────────────────

    -- B32. JWT SANS super-admin (app_metadata vide) — seule l'appartenance
    -- réelle du profil fixture à v_member_org_id (organisation titulaire de
    -- v_mandate_id_2, insérée avant B15) explique un succès ici.
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO v_rls_count FROM public.carbon_commercialization_mandates WHERE id = v_mandate_id_2;
    EXECUTE 'RESET ROLE';
    v_ok := (v_rls_count = 1);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B32', 'RLS (rôle authenticated réel, JWT sans super-admin) : membre réel de l''organisation titulaire voit son mandat (is_organization_member seule)', v_ok, NULL);

    -- B33 (renforcé). Avant de tester quiconque, on prouve explicitement
    -- que l'opérateur référencé par le mandat (v_operator_org_id_2) est
    -- réellement l'opérateur plateforme actif au moment du test — sinon un
    -- résultat "0 ligne" pour l'externe ne prouverait rien de la politique.
    v_ok := public.is_platform_operator(v_operator_org_id_2);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B33', 'précondition de preuve : operator_organization_id du mandat testé (v_operator_org_id_2) est bien l''opérateur plateforme actif', v_ok, NULL);

    -- B34 (isolation stricte, correction bloquante de la dernière revue).
    -- Retrait PRÉALABLE de l'appartenance à l'organisation titulaire
    -- (v_member_org_id), sans quoi is_organization_member(organization_id)
    -- suffirait à elle seule à expliquer un succès, sans jamais exercer
    -- is_active_platform_operator_member(). Seule l'appartenance à
    -- l'organisation opératrice METALTRACE (v_operator_org_id_2) est ensuite
    -- active, avec un JWT sans super-admin.
    DELETE FROM public.organization_members WHERE organization_id = v_member_org_id AND user_id = v_fixture_profile_id;

    INSERT INTO public.organization_members (organization_id, user_id, org_role, status, activated_at)
    VALUES (v_operator_org_id_2, v_fixture_profile_id, 'membre'::public.org_role, 'active', now());

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object())::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO v_rls_count FROM public.carbon_commercialization_mandates WHERE id = v_mandate_id_2;
    EXECUTE 'RESET ROLE';
    v_ok := (v_rls_count = 1);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B34', 'RLS (rôle authenticated réel, JWT sans super-admin, appartenance à l''organisation titulaire retirée) : un membre autorisé de l''organisation opératrice METALTRACE voit le mandat UNIQUEMENT via is_active_platform_operator_member()', v_ok, NULL);

    -- Retrait de l'appartenance à l'organisation opératrice (isolation pour
    -- B35), puis restauration de l'appartenance à l'organisation titulaire
    -- retirée avant B34, pour laisser l'état des fixtures cohérent avec le
    -- reste du script et le nettoyage final.
    DELETE FROM public.organization_members WHERE organization_id = v_operator_org_id_2 AND user_id = v_fixture_profile_id;

    INSERT INTO public.organization_members (organization_id, user_id, org_role, status, activated_at)
    VALUES (v_member_org_id, v_fixture_profile_id, 'admin'::public.org_role, 'active', now());

    -- B35. Un utilisateur externe, sans aucune relation (ni membre de
    -- l'organisation titulaire, ni admin de l'agrégateur, ni membre de
    -- l'organisation opératrice, ni super-admin), ne voit rien — alors même
    -- que B33 vient de prouver que l'opérateur référencé est bien actif.
    v_outsider_uid := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_outsider_uid, 'app_metadata', json_build_object())::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO v_rls_count FROM public.carbon_commercialization_mandates WHERE id = v_mandate_id_2;
    EXECUTE 'RESET ROLE';
    v_ok := (v_rls_count = 0);
    INSERT INTO public._carbon_migration_test_results (section, assertion, passed, detail)
    VALUES ('B35', 'RLS (rôle authenticated réel) : un utilisateur externe (aucune relation) ne voit rien, malgré B33/opérateur actif', v_ok, NULL);

    -- Restaure un contexte neutre pour le nettoyage (rôle propriétaire des tables).
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fixture_profile_id, 'app_metadata', json_build_object('role', 'admin'))::text, true);

    -- ────────────────────────────────────────────────────────
    -- NETTOYAGE — toujours exécuté, indépendamment du résultat des
    -- assertions ci-dessus. Ordre imposé par les FK RESTRICT :
    -- carbon_business_events avant carbon_commercialization_mandates avant
    -- platform_operators avant aggregator_memberships avant documents avant
    -- organization_members avant aggregators/organizations.
    --
    -- Note : la ligne organization_members créée pour B34
    -- (v_operator_org_id_2 / v_fixture_profile_id) a déjà été retirée
    -- immédiatement après ce test, par précaution — elle n'a donc pas
    -- besoin d'être reprise ici.
    -- ────────────────────────────────────────────────────────

    ALTER TABLE public.carbon_business_events DISABLE TRIGGER carbon_business_events_no_update_delete;
    DELETE FROM public.carbon_business_events
    WHERE organization_id IN (v_operator_org_id, v_operator_org_id_2, v_member_org_id)
       OR aggregator_id = v_test_aggregator_id;
    ALTER TABLE public.carbon_business_events ENABLE TRIGGER carbon_business_events_no_update_delete;

    ALTER TABLE public.carbon_commercialization_mandates DISABLE TRIGGER carbon_commercialization_mandates_reject_delete;
    DELETE FROM public.carbon_commercialization_mandates
    WHERE aggregator_membership_id IN (v_membership_id, v_membership_id_2);
    ALTER TABLE public.carbon_commercialization_mandates ENABLE TRIGGER carbon_commercialization_mandates_reject_delete;

    ALTER TABLE public.platform_operators DISABLE TRIGGER platform_operators_reject_delete;
    DELETE FROM public.platform_operators
    WHERE organization_id IN (v_operator_org_id, v_operator_org_id_2);
    ALTER TABLE public.platform_operators ENABLE TRIGGER platform_operators_reject_delete;

    -- CORRECTIF (échec constaté à l'exécution réelle, avant le DELETE brut
    -- ci-dessous) : v_membership_id_2 (réadhésion, B28-B35) reste
    -- délibérément ACTIVE jusqu'ici (ended_at IS NULL), car les tests RLS
    -- B32-B35 en dépendent. Migration 02 (D5/D7) maintient
    -- organizations.aggregator_id (colonne dépréciée) synchronisée avec
    -- aggregator_memberships via un trigger AFTER INSERT OR UPDATE — mais
    -- PAS AFTER DELETE. Un DELETE brut de aggregator_memberships (ci-dessous)
    -- ne déclenche donc JAMAIS la resynchronisation à NULL, laissant
    -- organizations.aggregator_id pointer vers v_test_aggregator_id après
    -- coup. Le DELETE FROM aggregators qui suit plus bas déclenche alors une
    -- action référentielle ON DELETE SET NULL sur cette colonne — rejetée
    -- par organizations_guard_aggregator_id_direct_write() (migration 02),
    -- qui refuse toute écriture de cette colonne ne provenant PAS du
    -- mécanisme de compatibilité légitime (marqueur transactionnel +
    -- pg_trigger_depth() >= 2 + propriétaire de fonction). Corrigé en
    -- terminant PROPREMENT toute adhésion encore active de nos organisations
    -- de test via une UPDATE ... SET ended_at (la SEULE transition permise
    -- par aggregator_memberships_guard_update, migration 02) AVANT le DELETE
    -- brut — cette UPDATE emprunte le chemin légitime et resynchronise
    -- organizations.aggregator_id à NULL correctement, sans qu'aucun DELETE
    -- ultérieur n'ait plus rien à annuler par action référentielle.
    UPDATE public.aggregator_memberships
    SET ended_at = clock_timestamp()
    WHERE (organization_id = v_member_org_id OR aggregator_id = v_test_aggregator_id)
      AND ended_at IS NULL;

    ALTER TABLE public.aggregator_memberships DISABLE TRIGGER aggregator_memberships_reject_delete;
    DELETE FROM public.aggregator_memberships
    WHERE organization_id = v_member_org_id OR aggregator_id = v_test_aggregator_id;
    ALTER TABLE public.aggregator_memberships ENABLE TRIGGER aggregator_memberships_reject_delete;

    -- Vérification défensive (pas une assertion comptée — n'affecte pas le
    -- total 62/62) : confirme que la resynchronisation a bien eu lieu avant
    -- de poursuivre vers le DELETE FROM aggregators plus bas, pour échouer
    -- ici avec un message clair plutôt que de retomber sur l'erreur opaque
    -- du garde-fou si un cas non anticipé subsistait.
    IF EXISTS (
        SELECT 1 FROM public.organizations
        WHERE id = v_member_org_id AND aggregator_id IS DISTINCT FROM NULL
    ) THEN
        RAISE EXCEPTION 'Nettoyage incohérent : organizations.aggregator_id (colonne dépréciée) de v_member_org_id n''a pas été resynchronisé à NULL avant le DELETE de l''agrégateur de test.';
    END IF;

    DELETE FROM public.documents WHERE id IN (v_wrong_org_document_id, v_member_org_document_id);

    DELETE FROM public.organization_members WHERE organization_id = v_member_org_id AND user_id = v_fixture_profile_id;

    DELETE FROM public.aggregators WHERE id = v_test_aggregator_id;
    DELETE FROM public.organizations WHERE id IN (v_operator_org_id, v_operator_org_id_2, v_member_org_id);

    -- Note : aucun bloc EXCEPTION WHEN OTHERS n'enveloppe ce DO block dans son
    -- ensemble. Une erreur véritablement inattendue remonte telle quelle et
    -- fait échouer visiblement ce script.
END $$;

-- ════════════════════════════════════════════════════════════
-- RÉSUMÉ — visible dans l'onglet Results
-- ════════════════════════════════════════════════════════════

SELECT section, assertion, passed, detail
FROM public._carbon_migration_test_results
ORDER BY id;

SELECT
    count(*) AS total_assertions,
    count(*) FILTER (WHERE passed) AS total_reussies,
    count(*) FILTER (WHERE NOT passed) AS total_echouees
FROM public._carbon_migration_test_results;

-- ════════════════════════════════════════════════════════════
-- FIN DE LA PARTIE 1 — NE RIEN COLLER APRÈS CE POINT DANS LA MÊME EXÉCUTION.
--
-- CORRECTIF STRUCTUREL (constaté à l'exécution réelle) : Supabase SQL
-- Editor exécute tout le texte collé en UNE SEULE transaction implicite.
-- Si la "porte de sortie bruyante" (ancien bloc DO ci-dessous) faisait
-- partie de CETTE MÊME exécution et levait une exception (cas d'échec),
-- TOUTE la transaction — y compris le CREATE TABLE et les lignes déjà
-- insérées dans _carbon_migration_test_results — était annulée, rendant le
-- diagnostic impossible : la table de résultats disparaissait avec
-- l'erreur qui aurait dû justement permettre de la consulter.
--
-- Corrigé en séparant l'exécution en deux étapes distinctes :
--   PARTIE 1 (ci-dessus, ce script) : fixtures, tests, nettoyage des
--   données de test, résumé. Ne contient plus aucun RAISE EXCEPTION
--   inconditionnel — se termine donc toujours normalement (COMMIT), que
--   les assertions soient toutes réussies ou non, et la table
--   _carbon_migration_test_results persiste dans les deux cas pour
--   inspection.
--   PARTIE 2 (bloc séparé ci-dessous, à copier-coller et exécuter DANS UNE
--   NOUVELLE REQUÊTE, séparée de la Partie 1) : vérifie le résultat et
--   nettoie — peut échouer sans affecter les données déjà commitées par la
--   Partie 1.
--
-- Avant d'exécuter la Partie 2 : inspecte le résumé ci-dessus (deux SELECT
-- qui précèdent ce commentaire). Si total_echouees > 0, NE PAS exécuter la
-- Partie 2 telle quelle — la table serait supprimée par son propre
-- diagnostic manqué. Exécute plutôt une requête de diagnostic ciblée,
-- par exemple :
--   SELECT section, assertion, detail FROM public._carbon_migration_test_results
--   WHERE NOT passed ORDER BY id;
-- et ne passe à la Partie 2 (qui supprime la table) qu'une fois le
-- correctif nécessaire identifié et appliqué, ou si tu choisis
-- explicitement d'abandonner ce cycle de test (la table sera de toute
-- façon écrasée par TRUNCATE au prochain lancement de la Partie 1).
-- ════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════
-- PARTIE 2 — PORTE DE SORTIE + NETTOYAGE FINAL
-- À COPIER-COLLER ET EXÉCUTER SÉPARÉMENT, DANS UNE NOUVELLE REQUÊTE,
-- UNIQUEMENT APRÈS AVOIR CONFIRMÉ 62/62 DANS LE RÉSUMÉ DE LA PARTIE 1
-- CI-DESSUS.
-- ════════════════════════════════════════════════════════════
--
-- DO $$
-- BEGIN
--   IF EXISTS (
--     SELECT 1
--     FROM public._carbon_migration_test_results
--     WHERE NOT passed
--   ) THEN
--     RAISE EXCEPTION 'Validation migration carbone 06 échouée';
--   END IF;
-- END;
-- $$;
--
-- DROP TABLE IF EXISTS public._carbon_migration_test_results;
