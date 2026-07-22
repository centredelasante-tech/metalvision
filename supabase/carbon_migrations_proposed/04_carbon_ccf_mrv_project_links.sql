-- ============================================================
-- Migration carbone 04/09 — Rattachement CCF <-> MRV (ccf_mrv_project_links)
-- ============================================================
--
-- PROPOSITION NON APPLIQUÉE. Ce fichier vit délibérément hors de
-- supabase/migrations/ pour qu'aucun `supabase db push` ne puisse
-- l'appliquer par inadvertance. À lire, réviser et approuver avant toute
-- exécution manuelle dans le SQL Editor Supabase — comme les migrations 01,
-- 02 et 06, jamais avant une décision explicite de l'utilisateur.
--
-- Réfère à : Tranche0-Carbone-Architecture.md §8 (RESTRICT sur
-- ccf_mrv_project_links.ccf_project_id/mrv_project_id), §14 (plan figé —
-- cette migration occupe le numéro 04), §15 point 3/section « Diagramme
-- relationnel cible » (ccf_projects >── ccf_mrv_project_links (historisée,
-- RESTRICT) ──< projects (MRV)), et l'obsolète « Plan des migrations
-- proposées » (conservé pour mémoire, §14 fait foi) qui nommait déjà cette
-- table avec « deux index uniques partiels, RESTRICT, RLS,
-- link_ccf_project_to_mrv(), unlink_ccf_project_from_mrv() ».
--
-- GEL DE LA MIGRATION 07 (dix-neuvième revue statique, 20 juillet 2026) :
-- 07_carbon_issuances.sql et ses tests sont validés et gelés — AUCUNE
-- modification n'est apportée à 07 par ce fichier. 07 dépend structurellement
-- de cette migration (voir son bloc de prévalidation, section 0, et le
-- commentaire de dépendances en tête de son fichier) mais son propre code
-- n'est PAS touché ici. Une réconciliation finale de 07 est prévue dans un
-- SEUL passage ultérieur, après validation de 04 ET 05 (voir « CONTRAT
-- OUVERT VERS 07 » ci-dessous — c'est précisément ce passage qui devra
-- l'honorer).
--
-- PRÉREQUIS : migrations 01 (carbon_business_events — catalogue event_type
-- contient déjà 'ccf_mrv_link_started'/'ccf_mrv_link_ended', catalogue
-- object_type contient déjà 'ccf_mrv_project_link', voir
-- 01_carbon_foundations_events_and_failures.sql lignes 95-96/134) et 06
-- (is_platform_superadmin(), is_organization_member()) déjà appliquées en
-- production. Chantiers CCF et MRV antérieurs déjà appliqués
-- (20260710999000_reset_and_reapply_ccf_full.sql pour ccf_projects/
-- project_participants ; 20260710999100_reapply_mrv_and_aggregators.sql pour
-- projects (MRV)/operational_units).
--
-- ÉTAT RÉEL DU SCHÉMA VÉRIFIÉ AVANT ÉCRITURE (lecture directe des fichiers de
-- migration réellement appliqués, pas supposé) :
--   - ccf_projects(id, opportunity_id, title, coordinator_org_id, phase,
--     status, start_date, target_end_date, created_at, updated_at) —
--     coordinator_org_id UUID NOT NULL REFERENCES organizations(id).
--   - project_participants(id, project_id, organization_id, project_role,
--     mandate_id, status, created_at) — project_id référence ccf_projects(id),
--     status TEXT CHECK (status IN ('invited','active','declined','removed')).
--   - projects (MRV — même nom de table que le domaine MRV, PAS ccf_projects) :
--     (id, client_id, operational_unit_id, name, ..., status, created_at) —
--     operational_unit_id UUID NULLABLE, aucune FK déclarée en base vers
--     operational_units dans le fichier source, mais c'est la seule colonne de
--     lien disponible (même hypothèse déjà confirmée et exploitée par
--     07_carbon_issuances.sql, carbon_is_source_organization_valid()).
--   - operational_units(id, organization_id, ...) — AUCUNE colonne de lien
--     direct vers un projet (ni mrv_project_id, ni équivalent) : le lien passe
--     uniquement par projects.operational_unit_id, jamais l'inverse.
--
-- CONTENU :
--   0. PRÉVALIDATION DU SCHÉMA RÉEL — introspection catalogue
--      (information_schema/pg_catalog/to_regprocedure()), échoue AVANT tout
--      DDL si une hypothèse ci-dessus est fausse. Vérifie aussi que
--      ccf_mrv_project_links n'existe pas déjà (idempotence — cette migration
--      ne doit être appliquée qu'une seule fois, même patron que 07 section 0).
--   1. Table ccf_mrv_project_links (historisée : started_at/ended_at, même
--      patron que aggregator_memberships — migration 02 —, RESTRICT sur les
--      deux FK conformément à §8, DEUX index uniques partiels garantissant
--      qu'au plus UN lien effectif existe à la fois par ccf_project_id ET par
--      mrv_project_id — voir « CONTRAT OUVERT VERS 07 » ci-dessous, c'est
--      précisément la garantie que 07 attend).
--   1bis. Trigger BEFORE INSERT forçant started_at/created_at à un seul
--      clock_timestamp() (correctif vingtième revue statique, voir en-tête).
--   1ter. Deux contraintes EXCLUDE USING gist protégeant l'ABSENCE de
--      chevauchement historique, pas seulement l'état courant (correctif
--      vingtième revue statique, voir en-tête).
--   2. Trigger de garde sur UPDATE (seule transition permise : ended_at de
--      NULL vers une valeur, aucune autre colonne modifiable) + réutilisation
--      de carbon_reject_update_delete() (migration 01) pour interdire tout
--      DELETE — même patron exact que aggregator_memberships (migration 02).
--   3. RLS : fonction can_view_ccf_mrv_project_link() nommée (§10, « RLS objet
--      par objet »), policy SELECT unique, aucune policy d'écriture (RPC
--      SECURITY DEFINER exclusivement).
--   4. RPC link_ccf_project_to_mrv(), unlink_ccf_project_from_mrv()
--      (décision D1 ci-dessous).
--   5. Révocations de privilèges par défaut.
--   6. Section de rollback/désactivation, commentée, hors transaction.
--
-- DÉCISIONS PRISES DANS CE FICHIER (nouvelles — aucune n'était déjà tranchée
-- par Tranche0-Carbone-Architecture.md, qui nomme les deux RPC et fixe le
-- schéma de la table mais ne fixe pas leur autorisation) :
--   D1. link_ccf_project_to_mrv()/unlink_ccf_project_from_mrv() réservées à
--       is_platform_superadmin() SEULEMENT — ni l'admin de l'organisation
--       coordinatrice du projet CCF, ni l'admin de l'organisation de l'unité
--       opérationnelle MRV, ne peuvent établir ou rompre ce lien seuls. Motif :
--       ce lien détermine directement quelles organisations comptent comme
--       source valide d'une émission de crédits carbone
--       (carbon_is_source_organization_valid(), 07_carbon_issuances.sql,
--       déjà écrite et gelée) — une décision d'éligibilité financière, pas une
--       simple opération de gestion de projet. Cohérent avec le patron déjà
--       établi pour les autres décisions de portée équivalente
--       (create_aggregator_with_primary_admin() en migration 02,
--       designate_platform_operator() en migration 06) : toutes réservées au
--       super-admin plateforme. Aucune organisation ne peut donc, unilatéra-
--       lement, s'auto-qualifier comme source de crédits carbone en liant son
--       propre projet CCF à un projet MRV de son choix. Point ouvert à
--       trancher en revue si un flux moins centralisé est souhaité pour une
--       tranche future — non retenu ici par défaut de prudence.
--   D2. unlink_ccf_project_from_mrv() ne prend que p_ccf_project_id (pas
--       p_mrv_project_id) — même simplification que leave_aggregator()
--       (migration 02) : l'index unique partiel garantit qu'au plus un lien
--       effectif existe pour ce ccf_project_id, donc p_ccf_project_id seul
--       l'identifie sans ambiguïté.
--   D3. started_at/ended_at (pas linked_at/unlinked_at) — vocabulaire choisi
--       pour rester cohérent avec aggregator_memberships (migration 02, même
--       patron de table historisée) ET avec les deux event_type déjà réservés
--       par la migration 01 (ccf_mrv_link_started/ccf_mrv_link_ended, mêmes
--       racines lexicales).
--   D4. CHECK ended_at IS NULL OR ended_at >= started_at (pas >) — même motif
--       que la décision D8 de la migration 02 : now() est stable pendant toute
--       la transaction PostgreSQL, un lien créé puis rompu dans le même bloc
--       (script de test, ou séquence applicative rapide) doit rester valide.
--       unlink_ccf_project_from_mrv() utilise clock_timestamp() pour
--       ended_at, comme leave_aggregator().
--
-- CORRECTIF VINGTIÈME REVUE STATIQUE (20 juillet 2026) — BLOCAGE TEMPOREL
-- CORRIGÉ : les deux index uniques partiels garantissent bien qu'au plus UN
-- lien effectif (ended_at IS NULL) existe à la fois par ccf_project_id ET par
-- mrv_project_id, mais ne garantissaient PAS l'absence de chevauchement
-- HISTORIQUE — un lien créé avec started_at = now() (figé au DÉBUT de la
-- transaction), puis rompu avec ended_at = clock_timestamp() (l'horloge
-- réelle), puis un nouveau lien recréé dans la MÊME transaction recevait de
-- nouveau started_at = now(), donc rétroactivement AVANT la fin réelle de
-- l'ancien lien — chevauchement démontré par le test B20 lui-même (voir
-- tests/04). Corrigé par :
--   (a) un trigger BEFORE INSERT (carbon_force_ccf_mrv_project_link_timestamps,
--       section 1bis) qui fixe started_at ET created_at à un SEUL et même
--       clock_timestamp() lu une fois, sans jamais faire confiance à une
--       valeur fournie par l'appelant (même patron que le forçage de
--       created_at sur credit_issuances, migration 07, seizième revue
--       statique) ;
--   (b) deux contraintes EXCLUDE USING gist (section 1ter) sur
--       tstzrange(started_at, ended_at, '[)'), une par ccf_project_id et une
--       par mrv_project_id, qui protègent TOUTE l'histoire (pas seulement le
--       lien courant) — btree_gist (déjà installée par la migration 01)
--       fournit l'opérateur d'égalité UUID nécessaire pour coexister avec
--       l'opérateur && (chevauchement) de range dans une même contrainte
--       GiST, même patron que verification_sessions_no_overlapping_completed_periods
--       (migration 05). Les deux index uniques partiels sont CONSERVÉS : ils
--       restent le filet de recherche/pré-vérification rapide du lien
--       courant et continuent de satisfaire le contrat réclamé par 07 ; les
--       contraintes GiST sont un durcissement supplémentaire, pas un
--       remplacement.
--
-- CONTRAT OUVERT VERS 07 (à honorer explicitement lors du passage unique de
-- réconciliation prévu après validation de 04 ET 05, PAS dans ce fichier) :
-- carbon_is_source_organization_valid() et carbon_lock_and_validate_source_organization()
-- (07_carbon_issuances.sql, déjà écrites et gelées) joignent aujourd'hui
-- ccf_mrv_project_links SANS filtrer sur son cycle de vie (`LEFT JOIN
-- public.ccf_mrv_project_links link ON link.ccf_project_id = vs.project_id OR
-- link.mrv_project_id = vs.project_id`, sans condition supplémentaire) — cette
-- migration introduit pourtant un cycle de vie réel (started_at/ended_at) : un
-- lien ROMPU (ended_at renseigné) resterait donc accepté par cette jointure
-- telle qu'elle existe aujourd'hui dans 07, exactement le défaut déjà identifié
-- et corrigé pour project_participants.status (huitième revue statique de 07,
-- correction 1) mais PAS encore corrigé pour ccf_mrv_project_links (07 avait
-- explicitement laissé ce point ouvert jusqu'à la rédaction de cette
-- migration — voir 07_carbon_issuances.sql lignes 140-153/742-754). Le
-- correctif attendu lors du passage de réconciliation : ajouter
-- `AND link.ended_at IS NULL` à la condition de jointure aux deux endroits
-- (carbon_is_source_organization_valid() et
-- carbon_lock_and_validate_source_organization()). Cette migration 04 satisfait
-- de son côté la garantie structurelle que 07 réclamait explicitement (« 04
-- devra garantir SOIT (a) un seul lien effectif possible par projet à tout
-- instant » — 07_carbon_issuances.sql ligne 750) via les deux index uniques
-- partiels de la section 1 ci-dessous : l'option (a) est celle retenue,
-- symétriquement sur ccf_project_id ET mrv_project_id.
--
-- Aucune donnée réelle à migrer (table nouvelle, création pure — 0 ligne
-- existante, aucune table ccf_mrv_project_links n'a jamais existé sous ce nom
-- dans supabase/migrations/).
--
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION DU SCHÉMA RÉEL — introspection catalogue, PAS hypothèse
--    tirée de l'historique versionné.
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regclass('public.ccf_mrv_project_links') IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.ccf_mrv_project_links existe déjà — cette migration ne doit être appliquée qu''une seule fois.';
    END IF;

    IF to_regclass('public.carbon_business_events') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_business_events introuvable — la migration 01 a-t-elle été appliquée ?';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
        WHERE t.relname = 'carbon_business_events' AND c.contype = 'c'
          AND pg_get_constraintdef(c.oid) ILIKE '%event_type%'
          AND pg_get_constraintdef(c.oid) ILIKE '%''ccf_mrv_link_started''%'
          AND pg_get_constraintdef(c.oid) ILIKE '%''ccf_mrv_link_ended''%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : event_type ''ccf_mrv_link_started''/''ccf_mrv_link_ended'' absents du catalogue carbon_business_events — attendus depuis la migration 01.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
        WHERE t.relname = 'carbon_business_events' AND c.contype = 'c'
          AND pg_get_constraintdef(c.oid) ILIKE '%object_type%'
          AND pg_get_constraintdef(c.oid) ILIKE '%''ccf_mrv_project_link''%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : object_type ''ccf_mrv_project_link'' absent du catalogue carbon_business_events — attendu depuis la migration 01.';
    END IF;

    IF to_regprocedure('public.is_platform_superadmin()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_platform_superadmin() introuvable — la migration 06 a-t-elle été appliquée ?';
    END IF;
    IF to_regprocedure('public.is_organization_member(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_organization_member(uuid) introuvable — la migration 06 a-t-elle été appliquée ?';
    END IF;
    IF to_regprocedure('public.carbon_reject_update_delete()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_reject_update_delete() introuvable — la migration 01 a-t-elle été appliquée ?';
    END IF;

    -- Correctif vingtième revue statique (voir en-tête) : requise par les
    -- deux contraintes EXCLUDE USING gist de la section 1ter.
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist') THEN
        RAISE EXCEPTION 'Prévalidation échouée : extension btree_gist introuvable — requise par les EXCLUDE USING gist de la section 1ter (la migration 01 a-t-elle été appliquée ?).';
    END IF;

    IF to_regclass('public.ccf_projects') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.ccf_projects introuvable (chantier CCF antérieur).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'ccf_projects'
          AND column_name = 'coordinator_org_id' AND data_type = 'uuid' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.ccf_projects.coordinator_org_id (uuid, NOT NULL) introuvable.';
    END IF;

    IF to_regclass('public.project_participants') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.project_participants introuvable (chantier CCF antérieur).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'project_participants'
          AND column_name = 'project_id' AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.project_participants.project_id (uuid) introuvable.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'project_participants'
          AND column_name = 'status' AND data_type = 'text'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.project_participants.status (text) introuvable.';
    END IF;

    IF to_regclass('public.projects') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.projects (MRV) introuvable (chantier MRV antérieur).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'projects'
          AND column_name = 'operational_unit_id' AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.projects.operational_unit_id (uuid) introuvable.';
    END IF;

    IF to_regclass('public.operational_units') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.operational_units introuvable (chantier MRV antérieur).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'operational_units'
          AND column_name = 'organization_id' AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.operational_units.organization_id (uuid) introuvable.';
    END IF;

    IF to_regclass('public.profiles') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.profiles introuvable.';
    END IF;

    RAISE NOTICE 'Prévalidation réussie : toutes les dépendances structurelles sont présentes.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. TABLE ccf_mrv_project_links — historisée, RESTRICT (§8), deux index
--    uniques partiels (satisfait le contrat ouvert par 07, voir en-tête).
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.ccf_mrv_project_links (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ccf_project_id UUID NOT NULL REFERENCES public.ccf_projects(id) ON DELETE RESTRICT,
    mrv_project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE RESTRICT,
    started_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at       TIMESTAMPTZ NULL,
    -- Durcissement non bloquant (vingt-et-unième revue statique) : NOT NULL —
    -- link_ccf_project_to_mrv() fournit toujours auth.uid() (vérifié non NULL
    -- plus haut dans la RPC), aucun lien ne devrait jamais exister sans son
    -- auteur.
    started_by     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    ended_by       UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    end_reason     TEXT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Décision D4 (voir en-tête) : >= et non >, même motif que la décision D8
    -- de la migration 02 (now() stable pendant toute la transaction).
    CONSTRAINT ccf_mrv_project_links_ended_after_started
        CHECK (ended_at IS NULL OR ended_at >= started_at),
    -- Durcissement non bloquant (vingt-et-unième revue statique) : ended_at et
    -- ended_by transitionnent toujours ENSEMBLE (unlink_ccf_project_from_mrv()
    -- les renseigne dans la même UPDATE) — jamais l'un sans l'autre.
    CONSTRAINT ccf_mrv_project_links_ended_at_by_coherent
        CHECK ((ended_at IS NULL AND ended_by IS NULL) OR (ended_at IS NOT NULL AND ended_by IS NOT NULL))
);

COMMENT ON TABLE public.ccf_mrv_project_links IS
  'Rattachement historisé entre un projet CCF (ccf_projects) et un projet MRV '
  '(projects) — détermine les organisations sources valides d''une émission de '
  'crédits carbone (07_carbon_issuances.sql, carbon_is_source_organization_valid()). '
  'Au plus UN lien effectif (ended_at IS NULL) à la fois par ccf_project_id ET par '
  'mrv_project_id — voir les deux index uniques partiels ci-dessous. Immuable sauf '
  'la transition ended_at NULL -> valeur — voir trigger '
  'ccf_mrv_project_links_guard_update. Aucun DELETE possible (append-only, réutilise '
  'carbon_reject_update_delete() de la migration 01).';

-- Garantie structurelle réclamée par 07 (voir « CONTRAT OUVERT VERS 07» en
-- en-tête) : au plus un lien effectif à la fois, symétriquement des deux côtés.
CREATE UNIQUE INDEX idx_ccf_mrv_project_links_one_active_per_ccf
    ON public.ccf_mrv_project_links (ccf_project_id)
    WHERE ended_at IS NULL;

CREATE UNIQUE INDEX idx_ccf_mrv_project_links_one_active_per_mrv
    ON public.ccf_mrv_project_links (mrv_project_id)
    WHERE ended_at IS NULL;

CREATE INDEX idx_ccf_mrv_project_links_ccf ON public.ccf_mrv_project_links (ccf_project_id);
CREATE INDEX idx_ccf_mrv_project_links_mrv ON public.ccf_mrv_project_links (mrv_project_id);

-- ────────────────────────────────────────────────────────────
-- 1bis. FORÇAGE TEMPOREL (BEFORE INSERT) — correctif vingtième revue statique
--    (voir en-tête). started_at/created_at ne doivent JAMAIS provenir d'une
--    valeur fournie par l'appelant (colonne DEFAULT now() seulement comme
--    filet si le trigger était un jour désactivé) — un seul clock_timestamp()
--    lu UNE fois, appliqué identiquement aux deux colonnes. Même patron que
--    le forçage de created_at sur credit_issuances (migration 07).
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_force_ccf_mrv_project_link_timestamps()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
    NEW.started_at := v_now;
    NEW.created_at := v_now;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_force_ccf_mrv_project_link_timestamps() IS
  'Force started_at ET created_at à un seul et même clock_timestamp() lu une '
  'fois à l''INSERT, indépendamment de toute valeur fournie par l''appelant — '
  'corrige le chevauchement historique possible quand started_at restait figé '
  'à now() (début de transaction) pendant qu''ended_at (unlink) utilisait '
  'clock_timestamp() (horloge réelle) dans la même transaction (vingtième '
  'revue statique, voir en-tête).';

CREATE TRIGGER ccf_mrv_project_links_force_insert_timestamps
    BEFORE INSERT ON public.ccf_mrv_project_links
    FOR EACH ROW EXECUTE FUNCTION public.carbon_force_ccf_mrv_project_link_timestamps();

-- ────────────────────────────────────────────────────────────
-- 1ter. EXCLUSION ANTI-CHEVAUCHEMENT HISTORIQUE (EXCLUDE USING gist) —
--    correctif vingtième revue statique (voir en-tête). Les index uniques
--    partiels ci-dessus ne couvrent QUE les lignes ended_at IS NULL (le lien
--    courant) ; un INSERT direct portant un ended_at déjà renseigné (lien
--    « historique » construit directement, hors RPC) pouvait donc chevaucher
--    un lien encore actif sans violer aucun index — ces deux contraintes
--    protègent TOUTE l'histoire, pas seulement l'état courant. btree_gist
--    (prévalidée section 0) fournit l'opérateur d'égalité UUID nécessaire
--    pour coexister avec && (chevauchement) dans une contrainte GiST unique —
--    même patron que verification_sessions_no_overlapping_completed_periods
--    (migration 05). ended_at NULL représente un intervalle non borné
--    ([started_at, +infini[) : tstzrange(started_at, ended_at, '[)') gère ce
--    cas nativement (borne supérieure NULL = illimitée).
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.ccf_mrv_project_links
    ADD CONSTRAINT ccf_mrv_project_links_no_overlapping_ccf
    EXCLUDE USING gist (
        ccf_project_id WITH =,
        tstzrange(started_at, ended_at, '[)') WITH &&
    );

ALTER TABLE public.ccf_mrv_project_links
    ADD CONSTRAINT ccf_mrv_project_links_no_overlapping_mrv
    EXCLUDE USING gist (
        mrv_project_id WITH =,
        tstzrange(started_at, ended_at, '[)') WITH &&
    );

-- ────────────────────────────────────────────────────────────
-- 2. IMMUTABILITÉ — trigger de garde (UPDATE) + réutilisation du rejet
--    générique (DELETE) introduit par la migration 01. Même patron exact que
--    aggregator_memberships (migration 02, section 3).
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_guard_ccf_mrv_project_link_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.ended_at IS NOT NULL THEN
        RAISE EXCEPTION 'ccf_mrv_project_links : un lien déjà terminé (ended_at renseigné) est immuable, aucune modification supplémentaire n''est permise.';
    END IF;

    IF NEW.ended_at IS NULL THEN
        RAISE EXCEPTION 'ccf_mrv_project_links : seule la transition de ended_at de NULL vers une valeur (fin de lien) est permise — aucune autre modification.';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.ccf_project_id IS DISTINCT FROM OLD.ccf_project_id
       OR NEW.mrv_project_id IS DISTINCT FROM OLD.mrv_project_id
       OR NEW.started_at IS DISTINCT FROM OLD.started_at
       OR NEW.started_by IS DISTINCT FROM OLD.started_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION 'ccf_mrv_project_links : seules les colonnes ended_at, ended_by et end_reason peuvent être renseignées à la fin d''un lien — aucune autre colonne ne peut changer.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_ccf_mrv_project_link_update() IS
  'Autorise une seule transition sur ccf_mrv_project_links : ended_at de NULL '
  'vers une valeur (avec ended_by/end_reason), jamais l''inverse, jamais deux '
  'fois, et aucune autre colonne modifiable.';

CREATE TRIGGER ccf_mrv_project_links_guard_update
    BEFORE UPDATE ON public.ccf_mrv_project_links
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_ccf_mrv_project_link_update();

CREATE TRIGGER ccf_mrv_project_links_reject_delete
    BEFORE DELETE ON public.ccf_mrv_project_links
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 3. RLS — fonction d'autorisation nommée (§10), policy SELECT unique.
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.ccf_mrv_project_links ENABLE ROW LEVEL SECURITY;

-- Visibilité : super-admin plateforme, membre de l'organisation coordinatrice
-- du projet CCF, membre d'une organisation participante ACTIVE du projet CCF,
-- ou membre de l'organisation de l'unité opérationnelle du projet MRV. Aucune
-- lecture de ccf_mrv_project_links par la fonction elle-même (jamais une
-- sous-requête sur sa propre table) — pas de risque de récursion RLS,
-- contrairement au défaut corrigé en migration 01 pour can_view_carbon_event().
CREATE OR REPLACE FUNCTION public.can_view_ccf_mrv_project_link(
    p_ccf_project_id UUID,
    p_mrv_project_id UUID
) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT public.is_platform_superadmin()
        OR EXISTS (
            SELECT 1 FROM public.ccf_projects cp
            WHERE cp.id = p_ccf_project_id
              AND public.is_organization_member(cp.coordinator_org_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.project_participants pp
            WHERE pp.project_id = p_ccf_project_id
              AND pp.status = 'active'
              AND public.is_organization_member(pp.organization_id)
        )
        OR EXISTS (
            SELECT 1 FROM public.projects mp
            JOIN public.operational_units ou ON ou.id = mp.operational_unit_id
            WHERE mp.id = p_mrv_project_id
              AND public.is_organization_member(ou.organization_id)
        )
$$;

REVOKE ALL ON FUNCTION public.can_view_ccf_mrv_project_link(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_ccf_mrv_project_link(UUID, UUID) TO authenticated;

CREATE POLICY ccf_mrv_project_links_select ON public.ccf_mrv_project_links
    FOR SELECT
    USING (public.can_view_ccf_mrv_project_link(ccf_project_id, mrv_project_id));

-- Aucune policy INSERT/UPDATE/DELETE : l'écriture se fait exclusivement via
-- les RPC SECURITY DEFINER ci-dessous.

-- ────────────────────────────────────────────────────────────
-- 4. RPC — établir/rompre le lien (décision D1/D2, voir en-tête)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.link_ccf_project_to_mrv(
    p_ccf_project_id UUID,
    p_mrv_project_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_link_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- Décision D1 (voir en-tête) : réservé au super-admin plateforme —
    -- décision d'éligibilité aux crédits carbone, pas une opération de
    -- gestion de projet ordinaire.
    IF NOT public.is_platform_superadmin() THEN
        RAISE EXCEPTION 'Seul un super-administrateur de la plateforme peut établir un lien CCF <-> MRV.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.ccf_projects WHERE id = p_ccf_project_id) THEN
        RAISE EXCEPTION 'p_ccf_project_id ne correspond à aucun projet CCF existant.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_mrv_project_id) THEN
        RAISE EXCEPTION 'p_mrv_project_id ne correspond à aucun projet MRV existant.';
    END IF;

    -- Pré-vérifications explicites et lisibles avant de tenter l'insertion —
    -- les deux index uniques partiels restent le filet de sécurité structurel
    -- en cas de course concurrente.
    IF EXISTS (
        SELECT 1 FROM public.ccf_mrv_project_links
        WHERE ccf_project_id = p_ccf_project_id AND ended_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Ce projet CCF a déjà un lien MRV effectif — utilisez unlink_ccf_project_from_mrv() avant d''en établir un autre.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.ccf_mrv_project_links
        WHERE mrv_project_id = p_mrv_project_id AND ended_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Ce projet MRV a déjà un lien CCF effectif — utilisez unlink_ccf_project_from_mrv() avant d''en établir un autre.';
    END IF;

    INSERT INTO public.ccf_mrv_project_links (ccf_project_id, mrv_project_id, started_by)
    VALUES (p_ccf_project_id, p_mrv_project_id, auth.uid())
    RETURNING id INTO v_link_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, actor_id, payload)
    VALUES ('ccf_mrv_link_started', 'ccf_mrv_project_link', v_link_id, auth.uid(),
            jsonb_build_object('ccf_project_id', p_ccf_project_id, 'mrv_project_id', p_mrv_project_id));

    RETURN v_link_id;
END;
$$;

COMMENT ON FUNCTION public.link_ccf_project_to_mrv(UUID, UUID) IS
  'Établit un lien effectif entre un projet CCF et un projet MRV. Réservée à '
  'is_platform_superadmin() (décision D1) — détermine directement l''éligibilité '
  'des organisations participantes comme source de crédits carbone. Rejette si '
  'l''un des deux projets a déjà un lien effectif (index uniques partiels, filet '
  'structurel).';

CREATE OR REPLACE FUNCTION public.unlink_ccf_project_from_mrv(
    p_ccf_project_id UUID,
    p_reason TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_link_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    IF NOT public.is_platform_superadmin() THEN
        RAISE EXCEPTION 'Seul un super-administrateur de la plateforme peut rompre un lien CCF <-> MRV.';
    END IF;

    -- Décision D2 (voir en-tête) : p_ccf_project_id seul suffit à identifier
    -- sans ambiguïté le lien effectif (index unique partiel, au plus un par
    -- ccf_project_id) — même simplification que leave_aggregator() (migration 02).
    SELECT id INTO v_link_id
    FROM public.ccf_mrv_project_links
    WHERE ccf_project_id = p_ccf_project_id AND ended_at IS NULL
    FOR UPDATE;

    IF v_link_id IS NULL THEN
        RAISE EXCEPTION 'Aucun lien MRV effectif trouvé pour ce projet CCF.';
    END IF;

    -- Décision D4 (voir en-tête) : clock_timestamp(), pas now() — cohérent
    -- avec leave_aggregator() (migration 02, décision D8).
    UPDATE public.ccf_mrv_project_links
    SET ended_at = clock_timestamp(), ended_by = auth.uid(), end_reason = p_reason
    WHERE id = v_link_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, actor_id, payload)
    VALUES ('ccf_mrv_link_ended', 'ccf_mrv_project_link', v_link_id, auth.uid(),
            CASE WHEN p_reason IS NOT NULL THEN jsonb_build_object('end_reason', p_reason) ELSE NULL END);

    RETURN v_link_id;
END;
$$;

COMMENT ON FUNCTION public.unlink_ccf_project_from_mrv(UUID, TEXT) IS
  'Termine le lien effectif d''un projet CCF (décision D2 : p_ccf_project_id '
  'seul, même simplification que leave_aggregator()). Réservée à '
  'is_platform_superadmin() (décision D1).';

-- ────────────────────────────────────────────────────────────
-- 5. RÉVOCATIONS DE PRIVILÈGES
-- ────────────────────────────────────────────────────────────

REVOKE ALL ON public.ccf_mrv_project_links FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ccf_mrv_project_links TO authenticated;
-- Aucun GRANT INSERT/UPDATE/DELETE à `authenticated` — écriture exclusive par
-- les RPC SECURITY DEFINER ci-dessus.

REVOKE ALL ON FUNCTION public.link_ccf_project_to_mrv(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_ccf_project_to_mrv(UUID, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.unlink_ccf_project_from_mrv(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unlink_ccf_project_from_mrv(UUID, TEXT) TO authenticated;

COMMIT;

-- ════════════════════════════════════════════════════════════
-- ROLLBACK / DÉSACTIVATION (commenté — à exécuter manuellement si besoin de
-- revenir en arrière après application de cette migration ; DÉLIBÉRÉMENT HORS
-- de la transaction BEGIN/COMMIT ci-dessus, exécuté séparément et
-- explicitement par un opérateur humain, jamais automatiquement)
-- ════════════════════════════════════════════════════════════
--
-- ATTENTION : 07_carbon_issuances.sql dépend structurellement de cette
-- migration (sa prévalidation section 0 échoue explicitement si
-- ccf_mrv_project_links est absente) — ne jamais exécuter ce rollback après
-- application de 07, sous peine de casser sa propre prévalidation à la
-- prochaine tentative d'application.
--
-- DROP FUNCTION IF EXISTS public.unlink_ccf_project_from_mrv(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.link_ccf_project_to_mrv(UUID, UUID);
-- DROP POLICY IF EXISTS ccf_mrv_project_links_select ON public.ccf_mrv_project_links;
-- DROP FUNCTION IF EXISTS public.can_view_ccf_mrv_project_link(UUID, UUID);
-- DROP TRIGGER IF EXISTS ccf_mrv_project_links_reject_delete ON public.ccf_mrv_project_links;
-- DROP TRIGGER IF EXISTS ccf_mrv_project_links_guard_update ON public.ccf_mrv_project_links;
-- DROP FUNCTION IF EXISTS public.carbon_guard_ccf_mrv_project_link_update();
-- ALTER TABLE public.ccf_mrv_project_links DROP CONSTRAINT IF EXISTS ccf_mrv_project_links_no_overlapping_mrv;
-- ALTER TABLE public.ccf_mrv_project_links DROP CONSTRAINT IF EXISTS ccf_mrv_project_links_no_overlapping_ccf;
-- DROP TRIGGER IF EXISTS ccf_mrv_project_links_force_insert_timestamps ON public.ccf_mrv_project_links;
-- DROP FUNCTION IF EXISTS public.carbon_force_ccf_mrv_project_link_timestamps();
-- DROP TABLE IF EXISTS public.ccf_mrv_project_links;
-- ============================================================
