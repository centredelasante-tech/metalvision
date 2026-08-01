-- ============================================================
-- SEED DÉMO METALVISION — reset_demo.sql
-- ============================================================
-- Supprime intégralement les données créées par 01_users_and_roles.sql à
-- 06_sales.sql, dans l'ordre inverse de dépendance, pour permettre une
-- réexécution propre du seed (ex: avant une nouvelle démonstration).
--
-- ⚠️ Ne touche QUE les entités de démonstration (identifiées par leurs UUID
-- fixes 'a0000000…'/'b0000000…'/etc., ou par nom/email @demo.metaltrace.ca
-- pour les entités générées par RPC avec un id aléatoire). N'affecte aucune
-- donnée réelle. Sûr à exécuter même si le seed n'a été appliqué que
-- partiellement (toutes les suppressions sont conditionnelles).
--
-- NOTE IMPORTANTE : plusieurs tables du domaine carbone (credit_sale_
-- allocations, credit_sales, credit_lots, credit_issuances, distribution_
-- rules, verification_outcomes, carbon_business_events, etc.) sont
-- volontairement append-only — une convention MVP-DA-006 appliquée dans
-- les migrations canoniques interdit tout UPDATE/DELETE via des triggers
-- dédiés (trg_..._forbid_delete / _reject_delete / _no_update_delete),
-- protection au niveau table, pas seulement RLS. `session_replication_role`
-- n'est PAS accessible (permission refusée même en SQL direct privilégié),
-- donc ce script désactive individuellement, par leur nom, les seuls
-- triggers non-système (NOT tgisinternal — les triggers internes de
-- contrainte FK restent actifs, donc l'ordre de suppression ci-dessous
-- reste important), puis les réactive explicitement à la fin. En cas
-- d'erreur en cours de script, toute la transaction (DDL de désactivation
-- compris) est annulée automatiquement — aucune fuite d'état possible.
--
-- Opération de maintenance privilégiée, valide UNIQUEMENT sur un
-- environnement de démonstration jetable — JAMAIS sur un projet contenant
-- des données réelles.
--
-- APPLICATION : `psql $DATABASE_URL -f reset_demo.sql` puis relancer
-- 01 → 06 pour reseeder.
--
-- GARDE D'ENVIRONNEMENT (bloquante) : ce script commence par vérifier que
-- la base cible porte bien le marqueur canari `METALVISION-DEMO`, posé une
-- fois pour toutes via :
--   COMMENT ON DATABASE postgres IS 'METALVISION-DEMO — ...';
-- Choix de `COMMENT ON DATABASE` plutôt que `current_database()` : sur
-- Supabase, `current_database()` vaut toujours `postgres` pour TOUT projet
-- (base partagée par convention), donc non discriminant — aucune fonction
-- SQL fiable n'expose le project ref. Le commentaire de base, lui, est un
-- attribut persistant et indépendant des données, qu'on ne pose
-- explicitement que sur METALVISION-DEMO. Si le marqueur est absent ou ne
-- commence pas par ce préfixe exact, le script lève une exception et
-- s'arrête immédiatement — aucune suppression n'est tentée.
-- ============================================================

DO $$
DECLARE
    v_env_marker   TEXT;
    v_o_operateur  UUID := 'b0000000-0000-4000-a000-000000000001';
    v_o_aciérie    UUID := 'b0000000-0000-4000-a000-000000000002';
    v_o_recycleur  UUID := 'b0000000-0000-4000-a000-000000000003';
    v_agg_id       UUID;
    v_ccf_project  UUID := 'f0000000-0000-4000-a000-000000000002';
    v_legacy_project UUID := 'e0000000-0000-4000-a000-000000000003';
    v_verif_session UUID := 'e0000000-0000-4000-a000-000000000007';

    -- Liste exhaustive obtenue par requête sur pg_trigger/pg_proc (fonctions
    -- carbon_reject_update_delete / carbon_credit_issuance_sources_forbid_write
    -- et équivalents nommés *_forbid_delete) — ne pas se fier à une liste
    -- devinée : plusieurs tables (aggregator_memberships,
    -- carbon_commercialization_mandates, ccf_mrv_project_links,
    -- platform_operators) sont append-only sans que leur nom le suggère.
    v_append_only_tables regclass[] := ARRAY[
        'public.aggregator_memberships','public.carbon_business_events',
        'public.carbon_commercialization_mandates','public.ccf_mrv_project_links',
        'public.credit_issuance_sources','public.credit_issuances','public.credit_lots',
        'public.credit_sale_adjustments','public.credit_sale_allocations','public.credit_sale_costs',
        'public.credit_sale_lots','public.credit_sales','public.distribution_rule_proposals',
        'public.distribution_rules','public.member_distribution_override_proposals',
        'public.member_distribution_overrides','public.platform_operators','public.verification_outcomes',
        -- organizations.aggregator_id est une colonne de compat synchronisée
        -- par trigger depuis aggregator_memberships et protégée en écriture
        -- directe (organizations_guard_aggregator_id_direct_write) — la
        -- suppression de l'aggregator déclenche un ON DELETE SET NULL sur
        -- cette colonne, qui est une UPDATE interne passant par ce même
        -- garde-fou : il faut le désactiver le temps du reset.
        'public.organizations'
    ]::regclass[];
    v_trg RECORD;
BEGIN
    -- ── GARDE BLOQUANTE D'ENVIRONNEMENT ─────────────────────────────────
    -- Doit être la toute première opération du script, avant toute
    -- désactivation de trigger ou suppression. Échec = abandon immédiat de
    -- la transaction (aucun DDL/DML exécuté).
    SELECT pg_catalog.shobj_description(d.oid, 'pg_database')
    INTO v_env_marker
    FROM pg_database d
    WHERE d.datname = current_database();

    IF v_env_marker IS NULL OR v_env_marker NOT LIKE 'METALVISION-DEMO%' THEN
        RAISE EXCEPTION 'reset_demo.sql BLOQUÉ : le marqueur d''environnement attendu (COMMENT ON DATABASE commençant par ''METALVISION-DEMO'') est absent ou ne correspond pas sur cette base (marqueur actuel : %). Ce script ne peut être exécuté que sur le projet METALVISION-DEMO — vérifiez la connexion avant de continuer.', COALESCE(v_env_marker, '<aucun>');
    END IF;

    SELECT id INTO v_agg_id FROM public.aggregators WHERE name = 'Regroupement Sidérurgique Laurentides (Démo)';

    -- ── Désactivation ciblée des triggers append-only/forbid_delete (par
    -- leur nom exact — jamais ALTER ... DISABLE TRIGGER ALL, qui échoue
    -- sur les triggers système FK sans privilège superuser) ──────────
    FOR v_trg IN
        SELECT tgname, tgrelid::regclass AS tbl FROM pg_trigger
        WHERE tgrelid = ANY(v_append_only_tables) AND NOT tgisinternal
    LOOP
        EXECUTE format('ALTER TABLE %s DISABLE TRIGGER %I', v_trg.tbl, v_trg.tgname);
    END LOOP;

    -- ── Événements métier (log pur, référencé par rien — à vider en
    -- premier pour lever toute FK entrante, notamment verification_
    -- session_id, avant de supprimer les tables qu'il référence) ──────
    DELETE FROM public.carbon_business_events
    WHERE organization_id IN (v_o_operateur, v_o_aciérie, v_o_recycleur)
       OR aggregator_id = v_agg_id
       OR verification_session_id = v_verif_session
       OR actor_id IN (SELECT id FROM auth.users WHERE email LIKE '%@demo.metaltrace.ca');

    -- ── Ventes et allocations ────────────────────────────────────────
    DELETE FROM public.credit_sale_allocations WHERE credit_sale_id IN (SELECT id FROM public.credit_sales WHERE seller_organization_id = v_o_operateur);
    DELETE FROM public.credit_sale_costs WHERE credit_sale_id IN (SELECT id FROM public.credit_sales WHERE seller_organization_id = v_o_operateur);
    DELETE FROM public.credit_sale_adjustments WHERE credit_sale_id IN (SELECT id FROM public.credit_sales WHERE seller_organization_id = v_o_operateur);
    DELETE FROM public.credit_sale_lots WHERE credit_sale_id IN (SELECT id FROM public.credit_sales WHERE seller_organization_id = v_o_operateur);
    DELETE FROM public.credit_sales WHERE seller_organization_id = v_o_operateur;

    -- ── Lots et émissions ────────────────────────────────────────────
    DELETE FROM public.credit_lots WHERE aggregator_id = v_agg_id;
    DELETE FROM public.credit_issuance_sources WHERE organization_id IN (v_o_aciérie, v_o_recycleur);
    DELETE FROM public.credit_issuances WHERE aggregator_id = v_agg_id;

    -- ── Gouvernance (règles de distribution + overrides éventuels) ───
    -- distribution_rules <-> distribution_rule_proposals (et l'équivalent
    -- pour les overrides membres) forment une paire de FK circulaires
    -- (rule.proposal_id -> proposal ; proposal.activated_*_id -> rule) —
    -- il faut casser le cycle en annulant le pointeur circulaire avant de
    -- pouvoir supprimer les deux tables.
    -- Un CHECK all-or-none (status='activated' <=> activated_*_id NOT NULL)
    -- interdit de nuller activated_*_id sans aussi repasser status hors
    -- 'activated' — on remet la proposition à l'état 'pending' d'origine
    -- (aucune métadonnée additionnelle requise pour ce statut) avant de
    -- pouvoir casser le cycle de FK.
    UPDATE public.member_distribution_override_proposals SET
        status = 'pending', activated_override_id = NULL,
        organization_admin_approved_by = NULL, organization_admin_approved_at = NULL,
        aggregator_admin_approved_by = NULL, aggregator_admin_approved_at = NULL,
        operator_admin_approved_by = NULL, operator_admin_approved_at = NULL
    WHERE aggregator_membership_id IN (SELECT id FROM public.aggregator_memberships WHERE aggregator_id = v_agg_id);
    DELETE FROM public.member_distribution_overrides WHERE aggregator_membership_id IN (
        SELECT id FROM public.aggregator_memberships WHERE aggregator_id = v_agg_id
    );
    DELETE FROM public.member_distribution_override_proposals WHERE aggregator_membership_id IN (
        SELECT id FROM public.aggregator_memberships WHERE aggregator_id = v_agg_id
    );

    UPDATE public.distribution_rule_proposals SET
        status = 'pending', activated_distribution_rule_id = NULL,
        aggregator_admin_approved_by = NULL, aggregator_admin_approved_at = NULL,
        operator_admin_approved_by = NULL, operator_admin_approved_at = NULL
    WHERE aggregator_id = v_agg_id;
    DELETE FROM public.distribution_rules WHERE aggregator_id = v_agg_id;
    DELETE FROM public.distribution_rule_proposals WHERE aggregator_id = v_agg_id;

    -- ── Vérification MRV ─────────────────────────────────────────────
    DELETE FROM public.verification_outcomes WHERE verification_session_id = v_verif_session;
    DELETE FROM public.evidence_files WHERE project_id = v_legacy_project;
    DELETE FROM public.verification_sessions WHERE id = v_verif_session;
    DELETE FROM public.ccf_mrv_project_links WHERE ccf_project_id = v_ccf_project;
    DELETE FROM public.project_activity_logs WHERE project_id = v_legacy_project;
    DELETE FROM public.projects WHERE id = v_legacy_project;
    DELETE FROM public.companies WHERE id = 'e0000000-0000-4000-a000-000000000001';

    -- ── CCF ──────────────────────────────────────────────────────────
    DELETE FROM public.project_participants WHERE project_id = v_ccf_project;
    DELETE FROM public.mandates WHERE id = 'f0000000-0000-4000-a000-000000000007';
    DELETE FROM public.capabilities WHERE organization_id IN (v_o_aciérie, v_o_recycleur);
    DELETE FROM public.ccf_projects WHERE id = v_ccf_project;
    DELETE FROM public.opportunities WHERE id = 'f0000000-0000-4000-a000-000000000001';

    -- ── Mandats de commercialisation ─────────────────────────────────
    DELETE FROM public.carbon_commercialization_mandates WHERE operator_organization_id = v_o_operateur;

    -- ── Regroupement / opérateur / adhésions ────────────────────────
    DELETE FROM public.aggregator_memberships WHERE aggregator_id = v_agg_id;
    DELETE FROM public.aggregator_admins WHERE aggregator_id = v_agg_id;
    DELETE FROM public.platform_operators WHERE organization_id = v_o_operateur;
    DELETE FROM public.aggregators WHERE id = v_agg_id;

    -- ── Réactivation des triggers ─────────────────────────────────────
    FOR v_trg IN
        SELECT tgname, tgrelid::regclass AS tbl FROM pg_trigger
        WHERE tgrelid = ANY(v_append_only_tables) AND NOT tgisinternal
    LOOP
        EXECUTE format('ALTER TABLE %s ENABLE TRIGGER %I', v_trg.tbl, v_trg.tgname);
    END LOOP;

    -- ── Organisations ────────────────────────────────────────────────
    DELETE FROM public.organization_members WHERE organization_id IN (v_o_operateur, v_o_aciérie, v_o_recycleur);
    DELETE FROM public.organizations WHERE id IN (v_o_operateur, v_o_aciérie, v_o_recycleur);

    -- ── Comptes ──────────────────────────────────────────────────────
    DELETE FROM public.accredited_verifiers WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@demo.metaltrace.ca');
    DELETE FROM auth.identities WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@demo.metaltrace.ca');
    DELETE FROM auth.users WHERE email LIKE '%@demo.metaltrace.ca'; -- cascade -> profiles

    RAISE NOTICE '✅ reset_demo appliqué : toutes les données de démonstration ont été supprimées.';
END $$;
