-- ============================================================
-- Migration carbone 05/09 — Résultats de vérification (verification_outcomes)
-- ============================================================
--
-- PROPOSITION NON APPLIQUÉE. Ce fichier vit délibérément hors de
-- supabase/migrations/ pour qu'aucun `supabase db push` ne puisse
-- l'appliquer par inadvertance. À lire, réviser et approuver avant toute
-- exécution manuelle dans le SQL Editor Supabase.
--
-- Réfère à : Tranche0-Carbone-Architecture.md §3 (invariants du résultat de
-- vérification, complete_verification_session()), §10 (is_assigned_verifier(),
-- §10bis — extension de can_view_carbon_event()), §12 (schéma
-- verification_outcomes, séquence de supersession, interdiction structurelle
-- de NaN, contrat du stub carbon_capacity_consumed_for_session()), §14 (plan
-- figé — cette migration occupe le numéro 05).
--
-- GEL DE LA MIGRATION 07 (dix-neuvième revue statique, 20 juillet 2026) :
-- 07_carbon_issuances.sql et ses tests sont validés et gelés — AUCUNE
-- modification n'est apportée à 07 par ce fichier. 07 dépend structurellement
-- de cette migration (sa prévalidation section 0 vérifie déjà l'existence de
-- verification_sessions/verification_outcomes,
-- complete_verification_session(uuid,numeric,numeric,uuid,text),
-- carbon_capacity_consumed_for_session(uuid), is_assigned_verifier(uuid) avec
-- les signatures exactes ci-dessous) mais son propre code n'est PAS touché
-- ici. Réconciliation finale de 07 prévue dans un seul passage ultérieur,
-- après validation de 04 ET 05 (déjà en cours — 04 rédigée avant ce fichier).
--
-- PRÉREQUIS : migrations 01 (carbon_business_events — catalogue event_type
-- contient déjà 'verification_session_started'/'verification_session_completed'/
-- 'verification_outcome_recorded'/'verification_outcome_superseded', catalogue
-- object_type contient déjà 'verification_session'/'verification_outcome',
-- extension btree_gist déjà installée — voir 01_carbon_foundations_events_and_failures.sql
-- lignes 78/98-101/135-136) et 06 (is_platform_superadmin(), is_org_admin(),
-- is_organization_member()) déjà appliquées en production. 04
-- (ccf_mrv_project_links) rédigée mais NON dépendance directe de ce fichier —
-- aucune référence à ccf_mrv_project_links ici.
--
-- ÉTAT RÉEL DU SCHÉMA VÉRIFIÉ AVANT ÉCRITURE (lecture directe des fichiers de
-- migration réellement appliqués, pas supposé) :
--   - verification_sessions(id, project_id, verifier_org, verifier_contact,
--     scope, status public.verification_status DEFAULT 'planned' (ENUM
--     'planned'/'in_progress'/'completed'), report_url, comments, created_at)
--     — AUCUNE colonne reporting_period_start/end ni verifier_user_id
--     aujourd'hui : cette migration les AJOUTE (section 1). Policies RLS
--     EXISTANTES et INCHANGÉES par ce fichier : admin_manage_verification_sessions
--     (is_project_admin(), FOR ALL — couvre donc déjà l'UPDATE direct des deux
--     nouvelles colonnes par un admin MRV, aucune RPC de planification/
--     assignation n'est nécessaire pour les renseigner, voir « POINT OUVERT »
--     ci-dessous), verifier_read_verification_sessions (is_verifier(), FOR
--     SELECT, lecture large — NON resserrée par cette migration, hors
--     périmètre explicite), client_read_verification_sessions (is_project_client()).
--   - project_activity_logs(id, project_id, activity_type, ...,
--     ghg_reduction_kgco2e FLOAT8, "timestamp" TIMESTAMPTZ, ...) — colonne
--     réellement nommée `"timestamp"` (mot réservé, à quoter), PAS `created_at`.
--   - documents(id, owner_org_id, object_type, object_id, title, ...) —
--     réutilisée uniquement pour la FK verification_report_document_id (§12),
--     aucune validation sémantique d'appartenance ici (contrairement à 07 qui
--     valide owner_org_id pour ses propres documents de preuve — hors
--     périmètre de cette migration, non demandé par §12).
--   - profiles(id, created_at, ...) — réutilisée pour verified_by/verifier_user_id.
--
-- POINT OUVERT, SIGNALÉ EXPLICITEMENT (pas un blocage, une limite de portée
-- assumée) : aucune RPC d'assignation de vérificateur / planification de
-- période n'est créée par cette migration — la seule mention de ce
-- mécanisme dans Tranche0-Carbone-Architecture.md est le nom des deux
-- nouvelles colonnes (§3), sans RPC nommée. reporting_period_start/end et
-- verifier_user_id sont donc, pour l'instant, renseignables UNIQUEMENT par un
-- admin MRV via la policy admin_manage_verification_sessions déjà en place
-- (is_project_admin(), FOR ALL, INCHANGÉE) — un UPDATE direct de ces trois
-- colonnes, hors toute RPC dédiée. L'événement 'verification_session_started'
-- (déjà réservé au catalogue, migration 01) reste NON JOURNALISÉ par cette
-- migration pour cette même raison : rien ici ne déclenche formellement le
-- démarrage d'une session. Seul 'verification_session_completed' est
-- journalisé, par complete_verification_session() (section 5), la première
-- fois qu'une session atteint effectivement le statut 'completed'. À
-- reconsidérer explicitement si une RPC de planification est jugée
-- nécessaire pour une tranche future — non ajoutée ici par discipline de
-- portée (ne construire que ce que Tranche0-Carbone-Architecture.md nomme).
--
-- CONTENU :
--   0. PRÉVALIDATION DU SCHÉMA RÉEL.
--   1. ALTER TABLE verification_sessions — reporting_period_start/end
--      (DATE, NULL), verifier_user_id (UUID, NULL, RESTRICT) ; CHECK exigeant
--      les trois renseignées dès que status = 'completed' ; EXCLUDE USING
--      gist empêchant deux sessions 'completed' du MÊME projet d'avoir des
--      périodes qui se chevauchent (§3).
--   2. TABLE verification_outcomes (§12, schéma exact, interdiction
--      structurelle de NaN sur les trois colonnes numériques, un seul
--      résultat actif par session — index unique partiel).
--   3. Immutabilité — trigger de garde (seule transition permise :
--      status active -> superseded) + réutilisation de
--      carbon_reject_update_delete() (migration 01) pour interdire DELETE.
--   4. is_assigned_verifier(uuid) — remplace is_verifier() dans la nouvelle
--      policy RLS UPDATE de verification_sessions et dans l'autorisation
--      interne de complete_verification_session() (§10).
--   5. STUB carbon_capacity_consumed_for_session(uuid) (retourne 0
--      inconditionnellement — contrat exact §12, à remplacer par 07 via
--      CREATE OR REPLACE, jamais par cette migration elle-même une fois 07
--      appliquée) + complete_verification_session() (§3, séquence de
--      supersession révisée §12).
--   6. can_view_carbon_event() — CREATE OR REPLACE, MÊME signature à 4
--      paramètres posée par la migration 01, ajoute la branche vérificateur
--      assigné (§10bis). Malgré le commentaire de la migration 01 disant
--      « MIGRATION 04 AJOUTERA ICI » (rédigé avant le gel de numérotation du
--      14 juillet 2026, jamais mis à jour car 01 est appliquée/figée) —
--      c'est bien CETTE migration (05, verification_outcomes/is_assigned_verifier())
--      qui l'honore, pas 04 (ccf_mrv_project_links, sans rapport avec la
--      vérification).
--   7. RLS verification_outcomes (can_view_verification_outcome(), même
--      audience que les policies SELECT déjà en place sur verification_sessions
--      + vérificateur assigné).
--   8. Révocations de privilèges par défaut.
--   9. Section de rollback/désactivation, commentée, hors transaction.
--
-- Aucune donnée réelle à migrer pour verification_outcomes (table nouvelle,
-- 0 ligne). verification_sessions gagne trois colonnes NULLABLES — aucun
-- backfill nécessaire, les lignes existantes (semées par
-- 20260710999100_reapply_mrv_and_aggregators.sql, statut 'planned'/'in_progress'
-- selon la ligne) ne sont jamais 'completed' à ce jour (à reconfirmer en
-- direct avant application, même discipline qu'ailleurs dans ce chantier),
-- donc jamais concernées par le CHECK ajouté en section 1.
--
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION DU SCHÉMA RÉEL — introspection catalogue, PAS hypothèse
--    tirée de l'historique versionné.
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regclass('public.verification_outcomes') IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.verification_outcomes existe déjà — cette migration ne doit être appliquée qu''une seule fois.';
    END IF;

    IF to_regclass('public.verification_sessions') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.verification_sessions introuvable (chantier MRV antérieur).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'verification_sessions' AND column_name = 'project_id'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.verification_sessions.project_id introuvable.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'verification_sessions' AND column_name = 'status'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.verification_sessions.status introuvable.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'verification_sessions'
          AND column_name IN ('reporting_period_start', 'reporting_period_end', 'verifier_user_id')
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : une colonne reporting_period_start/reporting_period_end/verifier_user_id existe déjà sur verification_sessions — cette migration ne doit être appliquée qu''une seule fois.';
    END IF;
    -- Valeurs exactes de l'ENUM verification_status — le CHECK/EXCLUDE de la
    -- section 1 et la logique de complete_verification_session() supposent
    -- précisément 'planned'/'in_progress'/'completed'.
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'verification_status' AND e.enumlabel = 'planned'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'verification_status' AND e.enumlabel = 'in_progress'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'verification_status' AND e.enumlabel = 'completed'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.verification_status ne contient pas exactement les valeurs attendues (planned/in_progress/completed).';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gist') THEN
        RAISE EXCEPTION 'Prévalidation échouée : extension btree_gist introuvable — requise par l''EXCLUDE USING gist de la section 1 (la migration 01 a-t-elle été appliquée ?).';
    END IF;

    IF to_regclass('public.project_activity_logs') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.project_activity_logs introuvable (chantier MRV antérieur).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'project_activity_logs' AND column_name = 'project_id'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'project_activity_logs' AND column_name = 'ghg_reduction_kgco2e'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'project_activity_logs' AND column_name = 'timestamp'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.project_activity_logs.project_id/ghg_reduction_kgco2e/"timestamp" introuvable(s).';
    END IF;

    IF to_regclass('public.documents') IS NULL OR to_regclass('public.profiles') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.documents/public.profiles introuvable(s).';
    END IF;

    IF to_regclass('public.carbon_business_events') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_business_events introuvable — la migration 01 a-t-elle été appliquée ?';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
        WHERE t.relname = 'carbon_business_events' AND c.contype = 'c'
          AND pg_get_constraintdef(c.oid) ILIKE '%event_type%'
          AND pg_get_constraintdef(c.oid) ILIKE '%''verification_session_completed''%'
          AND pg_get_constraintdef(c.oid) ILIKE '%''verification_outcome_recorded''%'
          AND pg_get_constraintdef(c.oid) ILIKE '%''verification_outcome_superseded''%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : event_type ''verification_session_completed''/''verification_outcome_recorded''/''verification_outcome_superseded'' absents du catalogue carbon_business_events — attendus depuis la migration 01.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
        WHERE t.relname = 'carbon_business_events' AND c.contype = 'c'
          AND pg_get_constraintdef(c.oid) ILIKE '%object_type%'
          AND pg_get_constraintdef(c.oid) ILIKE '%''verification_session''%'
          AND pg_get_constraintdef(c.oid) ILIKE '%''verification_outcome''%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : object_type ''verification_session''/''verification_outcome'' absents du catalogue carbon_business_events — attendus depuis la migration 01.';
    END IF;

    IF to_regprocedure('public.can_view_carbon_event(uuid,uuid,uuid,uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.can_view_carbon_event(uuid,uuid,uuid,uuid) introuvable — la migration 01 a-t-elle été appliquée ?';
    END IF;
    IF to_regprocedure('public.is_platform_superadmin()') IS NULL
       OR to_regprocedure('public.is_organization_member(uuid)') IS NULL
       OR to_regprocedure('public.is_org_admin(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : une des fonctions d''autorisation transverses (is_platform_superadmin/is_organization_member/is_org_admin) est introuvable — la migration 06 a-t-elle été appliquée ?';
    END IF;
    IF to_regprocedure('public.is_project_admin()') IS NULL OR to_regprocedure('public.is_project_client()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : is_project_admin()/is_project_client() introuvables (chantier MRV antérieur) — réutilisées par can_view_verification_outcome() pour rester cohérente avec les policies existantes de verification_sessions.';
    END IF;
    IF to_regprocedure('public.carbon_reject_update_delete()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_reject_update_delete() introuvable — la migration 01 a-t-elle été appliquée ?';
    END IF;

    RAISE NOTICE 'Prévalidation réussie : toutes les dépendances structurelles sont présentes.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. ALTER TABLE verification_sessions — trois colonnes nouvelles, CHECK,
--    EXCLUDE (§3).
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.verification_sessions
    ADD COLUMN reporting_period_start DATE NULL,
    ADD COLUMN reporting_period_end   DATE NULL,
    ADD COLUMN verifier_user_id       UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT;

COMMENT ON COLUMN public.verification_sessions.reporting_period_start IS
  'Début de la période couverte par cette vérification — NULL tant que non planifiée. Requise (avec reporting_period_end et verifier_user_id) dès que status = ''completed'' (CHECK ci-dessous).';
COMMENT ON COLUMN public.verification_sessions.reporting_period_end IS
  'Fin de la période couverte (bornes incluses, voir EXCLUDE ci-dessous). Requise dès que status = ''completed''.';
COMMENT ON COLUMN public.verification_sessions.verifier_user_id IS
  'Vérificateur assigné à cette session précise — remplace is_verifier() (générique, tout utilisateur au rôle verifier) comme autorité pour cette session (§10, is_assigned_verifier()). RESTRICT : un profil ne peut être supprimé tant qu''il reste assigné à une session.';

-- (§3) Une session 'completed' doit obligatoirement porter une période
-- valide et un vérificateur assigné — invariant structurel, pas seulement
-- applicatif : un UPDATE direct (admin_manage_verification_sessions, déjà en
-- place) qui tenterait de marquer 'completed' sans ces trois valeurs est
-- rejeté ici, indépendamment de complete_verification_session().
ALTER TABLE public.verification_sessions
    ADD CONSTRAINT verification_sessions_completed_requires_period_and_verifier
    CHECK (
        status <> 'completed'::public.verification_status
        OR (
            reporting_period_start IS NOT NULL
            AND reporting_period_end IS NOT NULL
            AND reporting_period_end >= reporting_period_start
            AND verifier_user_id IS NOT NULL
        )
    );

-- (§3) Deux sessions 'completed' du MÊME projet ne peuvent pas couvrir des
-- périodes qui se chevauchent — restreint aux sessions 'completed'
-- uniquement (une session encore 'planned'/'in_progress' n'a pas
-- nécessairement de période définitive). btree_gist fournit l'opérateur
-- d'égalité nécessaire sur project_id (uuid) pour coexister avec && (overlap)
-- sur le daterange dans une même contrainte GiST.
ALTER TABLE public.verification_sessions
    ADD CONSTRAINT verification_sessions_no_overlapping_completed_periods
    EXCLUDE USING gist (
        project_id WITH =,
        daterange(reporting_period_start, reporting_period_end, '[]') WITH &&
    ) WHERE (status = 'completed'::public.verification_status);

-- ────────────────────────────────────────────────────────────
-- 2. TABLE verification_outcomes (§12, schéma exact)
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.verification_outcomes (
    id                               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    verification_session_id         UUID NOT NULL REFERENCES public.verification_sessions(id) ON DELETE RESTRICT,
    status                           TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','superseded')),
    supersedes_outcome_id            UUID NULL REFERENCES public.verification_outcomes(id) ON DELETE RESTRICT,
    -- Interdiction structurelle de NaN (§12, durcissement réconcilié avec la
    -- quinzième revue statique de la migration 07 — même défaut de fait que
    -- credit_issuances.quantity_tco2e/credit_issuance_sources.contributed_tco2e :
    -- NUMERIC accepte NaN indépendamment de la précision déclarée, et
    -- PostgreSQL le traite comme supérieur à toute valeur ordinaire ET égal à
    -- lui-même — un CHECK `>= 0` seul ne l'exclut pas, et la comparaison
    -- croisée eligible_tco2e <= verified_reduction_tco2e ne suffit pas non
    -- plus si les DEUX valent NaN simultanément (NaN <= NaN est TRUE en
    -- PostgreSQL). Chaque colonne porte donc sa PROPRE exclusion explicite.
    calculated_reduction_tco2e       NUMERIC(14,4) NOT NULL CHECK (calculated_reduction_tco2e <> 'NaN'::numeric),
    verified_reduction_tco2e         NUMERIC(14,4) NOT NULL CHECK (verified_reduction_tco2e >= 0 AND verified_reduction_tco2e <> 'NaN'::numeric),
    eligible_tco2e                   NUMERIC(14,4) NOT NULL CHECK (eligible_tco2e >= 0 AND eligible_tco2e <= verified_reduction_tco2e AND eligible_tco2e <> 'NaN'::numeric),
    verification_report_document_id  UUID NULL REFERENCES public.documents(id),
    verified_by                      UUID NOT NULL REFERENCES public.profiles(id),
    -- (durcissement proactif, appliquant la leçon de la seizième/dix-septième
    -- revue statique de la migration 07 avant même qu'un défaut concret ne
    -- soit identifié ici) : clock_timestamp() plutôt que now() — now() reste
    -- figée à l'heure de DÉBUT de la transaction ; complete_verification_session()
    -- (section 5) verrouille verification_sessions puis effectue plusieurs
    -- lectures/calculs avant l'INSERT final, dans la même transaction que
    -- l'appelant. Aucun défaut concret identifié à ce jour pour cette table
    -- précise (contrairement à credit_issuances.created_at, dont l'incohérence
    -- était démontrée), mais clock_timestamp() n'est jamais moins correct que
    -- now() pour un horodatage de création — appliqué par cohérence et
    -- prévention, pas en réaction à un bug trouvé ici.
    verified_at                      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    adjustment_reason                TEXT NULL,
    created_at                       TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

COMMENT ON TABLE public.verification_outcomes IS
  'Résultat historisé d''une vérification — supersession par status (''active''/''superseded'') '
  'et supersedes_outcome_id pointant VERS L''ARRIÈRE (le nouveau référence l''ancien qu''il '
  'remplace, jamais l''inverse — élimine la dépendance circulaire d''un éventuel '
  'superseded_by_outcome_id, voir §12). Un seul résultat actif à la fois par session — voir '
  'index unique partiel ci-dessous. Immuable sauf la transition status active -> superseded, '
  'terminale — voir trigger carbon_guard_verification_outcome_update. Aucun DELETE possible '
  '(append-only, réutilise carbon_reject_update_delete() de la migration 01).';

CREATE UNIQUE INDEX idx_verification_outcomes_one_active_per_session
    ON public.verification_outcomes (verification_session_id)
    WHERE status = 'active';

CREATE INDEX idx_verification_outcomes_session ON public.verification_outcomes (verification_session_id);
CREATE INDEX idx_verification_outcomes_supersedes ON public.verification_outcomes (supersedes_outcome_id);

-- ────────────────────────────────────────────────────────────
-- 3. IMMUTABILITÉ — trigger de garde (UPDATE) + réutilisation du rejet
--    générique (DELETE) introduit par la migration 01.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_guard_verification_outcome_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.status = 'superseded' THEN
        RAISE EXCEPTION 'verification_outcomes : un résultat déjà superseded est immuable (terminal), aucune modification supplémentaire n''est permise.';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status AND NOT (OLD.status = 'active' AND NEW.status = 'superseded') THEN
        RAISE EXCEPTION 'verification_outcomes : seule la transition de status active -> superseded est permise.';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.verification_session_id IS DISTINCT FROM OLD.verification_session_id
       OR NEW.supersedes_outcome_id IS DISTINCT FROM OLD.supersedes_outcome_id
       OR NEW.calculated_reduction_tco2e IS DISTINCT FROM OLD.calculated_reduction_tco2e
       OR NEW.verified_reduction_tco2e IS DISTINCT FROM OLD.verified_reduction_tco2e
       OR NEW.eligible_tco2e IS DISTINCT FROM OLD.eligible_tco2e
       OR NEW.verification_report_document_id IS DISTINCT FROM OLD.verification_report_document_id
       OR NEW.verified_by IS DISTINCT FROM OLD.verified_by
       OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
       OR NEW.adjustment_reason IS DISTINCT FROM OLD.adjustment_reason
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION 'verification_outcomes : seule la colonne status peut changer (active -> superseded) — aucune autre colonne modifiable.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_verification_outcome_update() IS
  'Autorise une seule transition sur verification_outcomes : status de ''active'' vers '
  '''superseded'', jamais l''inverse, jamais deux fois (superseded terminal), et aucune '
  'autre colonne modifiable.';

CREATE TRIGGER verification_outcomes_guard_update
    BEFORE UPDATE ON public.verification_outcomes
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_verification_outcome_update();

CREATE TRIGGER verification_outcomes_reject_delete
    BEFORE DELETE ON public.verification_outcomes
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 4. is_assigned_verifier(uuid) — §10, remplace is_verifier() dans la
--    nouvelle policy RLS UPDATE de verification_sessions et dans
--    l'autorisation interne de complete_verification_session() (section 5).
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_assigned_verifier(p_verification_session_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.verification_sessions
        WHERE id = p_verification_session_id AND verifier_user_id = auth.uid()
    )
$$;

COMMENT ON FUNCTION public.is_assigned_verifier(UUID) IS
  'Vérifie que l''appelant courant est le vérificateur assigné à CETTE session précise '
  '(verification_sessions.verifier_user_id = auth.uid()) — remplace is_verifier() '
  '(générique, tout utilisateur au rôle verifier, sans distinction de session) partout '
  'où l''autorité doit être scopée à une session précise (§10).';

REVOKE ALL ON FUNCTION public.is_assigned_verifier(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_assigned_verifier(UUID) TO authenticated;

-- Nouvelle policy UPDATE réservée au vérificateur assigné — n'existait pas
-- jusqu'ici sous ce nom (aucune policy UPDATE portée par is_verifier() dans
-- le chantier MRV appliqué ; §10 décrit l'intention cible, réalisée ici pour
-- la première fois, pas littéralement un remplacement d'une policy
-- préexistante). Complète (n'écrase pas) admin_manage_verification_sessions
-- (FOR ALL, is_project_admin(), inchangée) : un vérificateur assigné peut
-- désormais aussi mettre à jour SA session (ex. reporting_period_start/end
-- avant d'appeler complete_verification_session()), sans devoir passer par
-- un admin MRV pour chaque champ.
CREATE POLICY verification_sessions_assigned_verifier_update ON public.verification_sessions
    FOR UPDATE
    USING (public.is_assigned_verifier(id))
    WITH CHECK (public.is_assigned_verifier(id));

-- ────────────────────────────────────────────────────────────
-- 5. STUB carbon_capacity_consumed_for_session(uuid) + complete_verification_session()
--    (§3, §12 — séquence de supersession révisée)
-- ────────────────────────────────────────────────────────────

-- CONTRAT EXACT (§12, réconcilié treizième revue statique de la migration
-- 07) : STUB retournant INCONDITIONNELLEMENT 0 — aucune ligne credit_issuances
-- ne peut exister avant que 07 soit appliquée, le stub est donc trivialement
-- correct à ce stade. 07 (déjà écrite, gelée) fait un CREATE OR REPLACE de
-- CETTE fonction, même signature, pour y substituer le calcul réel — cette
-- migration 05 ne doit JAMAIS être modifiée après coup pour « corriger » ce
-- stub une fois 07 appliquée : le remplacement est structurellement la
-- responsabilité de 07, pas de 05.
CREATE OR REPLACE FUNCTION public.carbon_capacity_consumed_for_session(p_verification_session_id UUID)
RETURNS NUMERIC
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT 0::NUMERIC
$$;

COMMENT ON FUNCTION public.carbon_capacity_consumed_for_session(UUID) IS
  'STUB (migration 05) — retourne inconditionnellement 0. Remplacée par son implémentation '
  'réelle via CREATE OR REPLACE dans la migration 07 (même signature), qui somme '
  'credit_issuances.quantity_tco2e sur toute la chaîne de supersession de cette session. '
  'Ne JAMAIS réimplémenter ce calcul ailleurs — point d''extension unique (§12).';

REVOKE ALL ON FUNCTION public.carbon_capacity_consumed_for_session(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.complete_verification_session(
    p_verification_session_id UUID,
    p_verified_reduction_tco2e NUMERIC,
    p_eligible_tco2e NUMERIC,
    p_verification_report_document_id UUID,
    p_adjustment_reason TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                      UUID;
    v_project_id                 UUID;
    v_reporting_start             DATE;
    v_reporting_end               DATE;
    v_verifier_user_id            UUID;
    v_session_status               public.verification_status;
    v_calculated_kg                NUMERIC;
    v_calculated_reduction_tco2e   NUMERIC(14,4);
    v_active_outcome_id            UUID;
    v_consumed_tco2e                NUMERIC;
    v_new_outcome_id                 UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- (§12 point 1) Verrou PAR id sur verification_sessions — MÊME ligne que
    -- create_credit_issuance() (migration 07, déjà écrite/gelée) verrouille
    -- pour la même session : c'est ce partage exact qui sérialise
    -- correctement une supersession concurrente à une création d'émission,
    -- dans les deux sens (dépendance déjà câblée dans 07, honorée ici).
    SELECT project_id, reporting_period_start, reporting_period_end, verifier_user_id, status
    INTO v_project_id, v_reporting_start, v_reporting_end, v_verifier_user_id, v_session_status
    FROM public.verification_sessions
    WHERE id = p_verification_session_id
    FOR UPDATE;

    IF v_project_id IS NULL THEN
        RAISE EXCEPTION 'Session de vérification introuvable.';
    END IF;

    -- (§10) is_assigned_verifier() remplace is_verifier() pour l'autorisation interne.
    IF NOT (public.is_assigned_verifier(p_verification_session_id) OR public.is_platform_superadmin()) THEN
        RAISE EXCEPTION 'Accès refusé : seul le vérificateur assigné à cette session (ou un super-administrateur) peut enregistrer un résultat.';
    END IF;

    IF v_session_status = 'planned' THEN
        RAISE EXCEPTION 'Session non prête : le statut doit être in_progress ou completed (planned rencontré) — la vérification de terrain doit avoir débuté.';
    END IF;

    IF v_reporting_start IS NULL OR v_reporting_end IS NULL THEN
        RAISE EXCEPTION 'Session non prête : reporting_period_start/reporting_period_end doivent être renseignés avant d''enregistrer un résultat.';
    END IF;

    IF v_verifier_user_id IS NULL THEN
        RAISE EXCEPTION 'Session non prête : aucun vérificateur assigné (verifier_user_id NULL).';
    END IF;

    -- (§12 point 2) Lecture (verrouillée) du résultat actif existant, le cas échéant.
    SELECT id INTO v_active_outcome_id
    FROM public.verification_outcomes
    WHERE verification_session_id = p_verification_session_id AND status = 'active'
    FOR UPDATE;

    -- (§3 point 1) Conversion d'unité explicite : somme kg -> tCO2e, arrondi
    -- arithmétique standard (ROUND(numeric,int) — « round half away from
    -- zero », PAS l'arrondi bancaire, comportement réel de PostgreSQL sur
    -- numeric, documenté explicitement pour qu'une implémentation future ne
    -- présume pas d'un comportement différent).
    SELECT COALESCE(SUM(ghg_reduction_kgco2e), 0) INTO v_calculated_kg
    FROM public.project_activity_logs
    WHERE project_id = v_project_id
      AND "timestamp" >= v_reporting_start
      AND "timestamp" < (v_reporting_end + 1);
    v_calculated_reduction_tco2e := ROUND((v_calculated_kg / 1000)::numeric, 4);

    -- Interdiction structurelle de NaN (même motif que §12 pour la table) —
    -- appliquée ICI, en plus des CHECK de table, avant toute autre logique
    -- métier qui présumerait un ordre total ordinaire.
    IF p_verified_reduction_tco2e IS NULL OR p_verified_reduction_tco2e < 0 OR p_verified_reduction_tco2e = 'NaN'::numeric THEN
        RAISE EXCEPTION 'verified_reduction_tco2e doit être positif ou nul et fini (NaN interdit).';
    END IF;
    IF p_eligible_tco2e IS NULL OR p_eligible_tco2e < 0 OR p_eligible_tco2e = 'NaN'::numeric THEN
        RAISE EXCEPTION 'eligible_tco2e doit être positif ou nul et fini (NaN interdit).';
    END IF;
    IF p_eligible_tco2e > p_verified_reduction_tco2e THEN
        RAISE EXCEPTION 'eligible_tco2e ne peut pas dépasser verified_reduction_tco2e.';
    END IF;

    -- (§3 point 2/3, §12) adjustment_reason : TOUJOURS obligatoire en cas de
    -- supersession (résultat actif déjà existant) ; obligatoire au premier
    -- résultat SEULEMENT si verified_reduction_tco2e diverge de plus de 1 %
    -- de la valeur calculée suggérée (seuil documenté ici, cf. §3 « seuil à
    -- définir, ex. 1% » — 1% retenu comme valeur par défaut explicite de
    -- cette migration, à reconfirmer en revue si un autre seuil est souhaité).
    IF v_active_outcome_id IS NOT NULL THEN
        IF p_adjustment_reason IS NULL OR btrim(p_adjustment_reason) = '' THEN
            RAISE EXCEPTION 'adjustment_reason est obligatoire pour corriger un résultat déjà actif (supersession).';
        END IF;
    ELSIF v_calculated_reduction_tco2e > 0
          AND abs(p_verified_reduction_tco2e - v_calculated_reduction_tco2e) > (v_calculated_reduction_tco2e * 0.01) THEN
        IF p_adjustment_reason IS NULL OR btrim(p_adjustment_reason) = '' THEN
            RAISE EXCEPTION 'adjustment_reason est obligatoire : verified_reduction_tco2e diverge de plus de 1%% de la valeur calculée suggérée (%).', v_calculated_reduction_tco2e;
        END IF;
    END IF;

    -- (§12 point 3, invariant bidirectionnel obligatoire) Capacité déjà
    -- consommée sur TOUTE la chaîne de supersession de cette session — stub
    -- ci-dessus tant que 07 n'est pas appliquée (retourne 0, donc cette
    -- vérification ne peut jamais échouer avant que credit_issuances existe).
    v_consumed_tco2e := public.carbon_capacity_consumed_for_session(p_verification_session_id);
    IF p_eligible_tco2e < v_consumed_tco2e THEN
        RAISE EXCEPTION 'Invariant bidirectionnel violé : eligible_tco2e (%) < capacité déjà consommée (%) — la supersession échoue, le résultat actif reste inchangé.', p_eligible_tco2e, v_consumed_tco2e;
    END IF;

    -- (§12 point 4) Transition de l'ancien résultat actif, s'il existe —
    -- libère l'index unique partiel AVANT l'INSERT ci-dessous.
    IF v_active_outcome_id IS NOT NULL THEN
        UPDATE public.verification_outcomes SET status = 'superseded' WHERE id = v_active_outcome_id;
    END IF;

    -- (§12 point 5) Nouveau résultat actif — supersedes_outcome_id pointe
    -- VERS L'ARRIÈRE (vers l'ancien qu'il remplace), NULL au premier résultat.
    INSERT INTO public.verification_outcomes (
        verification_session_id, status, supersedes_outcome_id,
        calculated_reduction_tco2e, verified_reduction_tco2e, eligible_tco2e,
        verification_report_document_id, verified_by
    ) VALUES (
        p_verification_session_id, 'active', v_active_outcome_id,
        v_calculated_reduction_tco2e, p_verified_reduction_tco2e, p_eligible_tco2e,
        p_verification_report_document_id, v_actor
    ) RETURNING id INTO v_new_outcome_id;

    -- Transition de la session vers 'completed', la première fois seulement
    -- (idempotent pour une supersession ultérieure, où le statut est déjà
    -- 'completed') — voir « POINT OUVERT » en en-tête sur l'absence de RPC
    -- de planification distincte : c'est cette RPC-ci qui referme
    -- effectivement le statut de la session, cohérent avec son nom.
    IF v_session_status = 'in_progress' THEN
        UPDATE public.verification_sessions SET status = 'completed' WHERE id = p_verification_session_id;
        INSERT INTO public.carbon_business_events (event_type, object_type, object_id, verification_session_id, actor_id, payload)
        VALUES ('verification_session_completed', 'verification_session', p_verification_session_id, p_verification_session_id, v_actor, NULL);
    END IF;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, verification_session_id, actor_id, payload)
    VALUES (
        CASE WHEN v_active_outcome_id IS NOT NULL THEN 'verification_outcome_superseded' ELSE 'verification_outcome_recorded' END,
        'verification_outcome', v_new_outcome_id, p_verification_session_id, v_actor,
        jsonb_build_object(
            'calculated_reduction_tco2e', v_calculated_reduction_tco2e,
            'verified_reduction_tco2e', p_verified_reduction_tco2e,
            'eligible_tco2e', p_eligible_tco2e,
            'supersedes_outcome_id', v_active_outcome_id
        )
    );

    RETURN v_new_outcome_id;
END;
$$;

COMMENT ON FUNCTION public.complete_verification_session(UUID, NUMERIC, NUMERIC, UUID, TEXT) IS
  'Enregistre le résultat d''une vérification (§3/§12) — jamais un UPDATE en place, toujours '
  'un nouveau verification_outcomes avec supersession de l''éventuel résultat actif existant. '
  'Réservée à is_assigned_verifier(p_verification_session_id) OU is_platform_superadmin() '
  '(§10). Transitionne la session vers ''completed'' au premier appel. adjustment_reason '
  'obligatoire pour toute supersession, ou au premier résultat si divergence > 1% de la '
  'valeur calculée suggérée.';

REVOKE ALL ON FUNCTION public.complete_verification_session(UUID, NUMERIC, NUMERIC, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_verification_session(UUID, NUMERIC, NUMERIC, UUID, TEXT) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 6. can_view_carbon_event() — CREATE OR REPLACE, MÊME signature (§10bis)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.can_view_carbon_event(
    p_actor_id UUID,
    p_organization_id UUID,
    p_aggregator_id UUID,
    p_verification_session_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
    SELECT
        public.is_platform_superadmin()
        OR p_actor_id = auth.uid()
        OR (p_organization_id IS NOT NULL AND public.is_organization_member(p_organization_id))
        OR (p_aggregator_id IS NOT NULL AND public.is_aggregator_admin(p_aggregator_id))
        OR (p_verification_session_id IS NOT NULL AND public.is_assigned_verifier(p_verification_session_id));
$$;

COMMENT ON FUNCTION public.can_view_carbon_event(UUID, UUID, UUID, UUID) IS
  'Point unique d''autorisation en lecture pour carbon_business_events. Reçoit les colonnes '
  'nécessaires en paramètres plutôt que de relire la table (évite toute récursion RLS, '
  'cette fonction étant appelée depuis la policy SELECT de carbon_business_events '
  'elle-même). Étendue par la migration 05 (CREATE OR REPLACE, même signature posée par '
  'la migration 01) pour couvrir le vérificateur assigné via p_verification_session_id — '
  'voir Tranche0-Carbone-Architecture.md §10bis. Le commentaire de la migration 01 ("MIGRATION '
  '04 AJOUTERA ICI") est antérieur au gel de numérotation du 14 juillet 2026 et n''a jamais '
  'été mis à jour (migration figée/appliquée) — c''est bien 05 qui honore cette extension.';

-- ────────────────────────────────────────────────────────────
-- 7. RLS verification_outcomes
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.verification_outcomes ENABLE ROW LEVEL SECURITY;

-- Même audience que les policies SELECT déjà en place sur verification_sessions
-- (admin_manage_verification_sessions/verifier_read_verification_sessions/
-- client_read_verification_sessions, is_project_admin()/is_verifier()/
-- is_project_client() — inchangées par cette migration) PLUS le vérificateur
-- assigné à CETTE session précise (is_assigned_verifier(), §10bis) et le
-- super-admin plateforme — un résultat de vérification ne doit jamais être
-- visible à une audience plus large que la session dont il découle.
CREATE OR REPLACE FUNCTION public.can_view_verification_outcome(p_verification_session_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT public.is_platform_superadmin()
        OR public.is_project_admin()
        OR public.is_project_client()
        OR public.is_assigned_verifier(p_verification_session_id)
$$;

REVOKE ALL ON FUNCTION public.can_view_verification_outcome(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_verification_outcome(UUID) TO authenticated;

CREATE POLICY verification_outcomes_select ON public.verification_outcomes
    FOR SELECT
    USING (public.can_view_verification_outcome(verification_session_id));

-- Aucune policy INSERT/UPDATE/DELETE : l'écriture se fait exclusivement via
-- complete_verification_session() (SECURITY DEFINER).

-- ────────────────────────────────────────────────────────────
-- 8. RÉVOCATIONS DE PRIVILÈGES
-- ────────────────────────────────────────────────────────────

REVOKE ALL ON public.verification_outcomes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.verification_outcomes TO authenticated;
-- Aucun GRANT INSERT/UPDATE/DELETE à `authenticated` — écriture exclusive par
-- complete_verification_session() (SECURITY DEFINER).

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
-- verification_outcomes/complete_verification_session()/
-- carbon_capacity_consumed_for_session()/is_assigned_verifier() sont
-- absents) — ne jamais exécuter ce rollback après application de 07. Si 07 a
-- REMPLACÉ carbon_capacity_consumed_for_session() (CREATE OR REPLACE, même
-- signature), ce rollback ne restaure PAS le stub — DROP FUNCTION la
-- supprime entièrement, cohérent avec le DROP TABLE credit_issuances que le
-- rollback de 07 effectuerait par ailleurs dans ce scénario (rollback total
-- 07 puis 05, jamais 05 seule après 07).
--
-- DROP POLICY IF EXISTS verification_outcomes_select ON public.verification_outcomes;
-- DROP FUNCTION IF EXISTS public.can_view_verification_outcome(UUID);
-- -- can_view_carbon_event() : restaurer la version de base (migration 01,
-- -- sans la branche vérificateur assigné) plutôt que la supprimer — la
-- -- policy carbon_business_events_select (migration 01) en dépend toujours.
-- CREATE OR REPLACE FUNCTION public.can_view_carbon_event(
--     p_actor_id UUID, p_organization_id UUID, p_aggregator_id UUID, p_verification_session_id UUID
-- ) RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
--     SELECT public.is_platform_superadmin()
--         OR p_actor_id = auth.uid()
--         OR (p_organization_id IS NOT NULL AND public.is_organization_member(p_organization_id))
--         OR (p_aggregator_id IS NOT NULL AND public.is_aggregator_admin(p_aggregator_id));
-- $$;
-- DROP FUNCTION IF EXISTS public.complete_verification_session(UUID, NUMERIC, NUMERIC, UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.carbon_capacity_consumed_for_session(UUID);
-- DROP POLICY IF EXISTS verification_sessions_assigned_verifier_update ON public.verification_sessions;
-- DROP FUNCTION IF EXISTS public.is_assigned_verifier(UUID);
-- DROP TRIGGER IF EXISTS verification_outcomes_reject_delete ON public.verification_outcomes;
-- DROP TRIGGER IF EXISTS verification_outcomes_guard_update ON public.verification_outcomes;
-- DROP FUNCTION IF EXISTS public.carbon_guard_verification_outcome_update();
-- DROP TABLE IF EXISTS public.verification_outcomes;
-- ALTER TABLE public.verification_sessions DROP CONSTRAINT IF EXISTS verification_sessions_no_overlapping_completed_periods;
-- ALTER TABLE public.verification_sessions DROP CONSTRAINT IF EXISTS verification_sessions_completed_requires_period_and_verifier;
-- ALTER TABLE public.verification_sessions DROP COLUMN IF EXISTS verifier_user_id;
-- ALTER TABLE public.verification_sessions DROP COLUMN IF EXISTS reporting_period_end;
-- ALTER TABLE public.verification_sessions DROP COLUMN IF EXISTS reporting_period_start;
-- ============================================================
