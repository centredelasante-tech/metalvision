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
-- CORRECTIF VINGTIÈME REVUE STATIQUE (20 juillet 2026) — six points bloquants
-- corrigés avant toute exécution :
--   1. policy verification_sessions_assigned_verifier_update SUPPRIMÉE — une
--      policy RLS UPDATE ne filtre que les LIGNES, jamais les COLONNES : un
--      vérificateur assigné pouvait donc modifier project_id, la période, le
--      vérificateur assigné lui-même, ou status, y compris après création
--      d'un résultat. Remplacée par une RPC étroite,
--      plan_verification_session() (section 4bis), réservée à
--      is_project_admin()/is_platform_superadmin() (autorité MRV), PLUS un
--      trigger de garde structurel (section 3bis) gelant project_id/
--      reporting_period_start/reporting_period_end/verifier_user_id dès
--      qu'un résultat existe pour la session OU que status = 'completed' —
--      une policy seule ne suffisait pas, la policy administrative
--      (admin_manage_verification_sessions, FOR ALL, inchangée) permettant
--      toujours des écritures directes.
--   2. can_view_verification_outcome() : is_project_client() (rôle générique,
--      aucune portée par projet) donnait accès à TOUS les résultats à
--      n'importe quel utilisateur portant ce rôle. Remplacé par la relation
--      réelle projects.client_id = auth.uid() (jointure
--      verification_sessions -> projects), la même relation que la policy
--      client_read_own_projects déjà en place sur projects (migration MRV
--      appliquée, `client_id = auth.uid() OR is_project_client()` —
--      confirmé par lecture directe de 20260710999100_reapply_mrv_and_aggregators.sql).
--      is_project_admin() reste utilisé tel quel pour l'audience admin :
--      portée globale INTENTIONNELLE, cohérente avec
--      admin_manage_verification_sessions (déjà FOR ALL, sans filtre par
--      projet) — ce n'est PAS le même défaut que is_project_client().
--   3. Seuil de 1% : la condition v_calculated_reduction_tco2e > 0 laissait
--      passer SANS adjustment_reason tout résultat vérifié positif quand la
--      valeur calculée suggérée valait exactement 0 (S4, aucune activité
--      journalisée). Trois cas explicites désormais (section 5) :
--      supersession -> toujours obligatoire ; calculé = 0 et vérifié <> 0 ->
--      obligatoire ; calculé <> 0 -> obligatoire si
--      abs(vérifié - calculé) > abs(calculé) x 1%.
--   4. complete_verification_session() : la dérogation
--      `OR is_platform_superadmin()` permettait à un super-administrateur de
--      plateforme de devenir lui-même verified_by, mélangeant administration
--      de plateforme et attestation indépendante du vérificateur (VVB).
--      SUPPRIMÉE — seul verification_sessions.verifier_user_id peut
--      désormais appeler avec succès cette RPC. Le super-administrateur
--      conserve la capacité de planifier/réassigner/corriger la session AVANT
--      sa clôture via plan_verification_session(), mais ne peut plus produire
--      l'attestation lui-même.
--   5. verification_report_document_id : NULLABLE jusqu'ici — un résultat
--      pouvait devenir source d'émission sans aucune preuve documentaire.
--      Désormais NOT NULL (section 2) et validé par la RPC (section 5) :
--      document existant + category = 'verification_report'. LIMITE
--      STRUCTURELLE ASSUMÉE ET DOCUMENTÉE (pas silencieusement ignorée) :
--      l'appartenance au MÊME projet MRV n'est PAS structurellement
--      vérifiable ici — documents.object_type (catalogue CHECK de la
--      migration CCF-006) ne comporte aujourd'hui aucune valeur pour les
--      projets MRV (object_type='project' y désigne exclusivement
--      ccf_projects, voir 20260710006000_ccf_006_documents.sql lignes
--      139-147). Cette extension viendra avec la modélisation du VVB, hors
--      périmètre de cette migration.
--   6. Chaîne de supersession : rien n'empêchait structurellement une
--      écriture privilégiée de créer une auto-référence, une supersession
--      inter-session, un fork (deux résultats prétendant remplacer le même
--      ancien), ou une nouvelle racine alors qu'un historique existe déjà.
--      Ajout (section 2) d'un CHECK anti-auto-référence, d'un index unique
--      partiel anti-fork sur supersedes_outcome_id, d'une contrainte UNIQUE
--      (id, verification_session_id) + FK composite forçant la même session,
--      et d'un index unique partiel garantissant au plus UNE racine
--      (supersedes_outcome_id IS NULL) par session.
--
-- Durcissements complémentaires (mêmes revue) : prévalidation explicite
-- rejetant la migration si une session 'completed' préexistante viole le
-- nouveau CHECK (section 0, plutôt qu'un commentaire « à reconfirmer ») ;
-- SUM(ghg_reduction_kgco2e::numeric) plutôt qu'une somme FLOAT8 convertie
-- après coup (section 5).
--
-- CORRECTIF VINGT-ET-UNIÈME REVUE STATIQUE (cinq blocages, voir commentaires
-- inline aux sections concernées) : verrou+autorisation fusionnés dans
-- complete_verification_session() (message générique anti-énumération) ;
-- policies SELECT verifier_read_.../client_read_verification_sessions
-- scopées (section 4quater) ; transition completed sans outcome rejetée
-- (section 3bis) ; trigger BEFORE INSERT structurel sur verification_outcomes
-- (section 3ter) ; verification_report_document_id référence désormais
-- evidence_files (scopé par projet MRV) plutôt que documents.
--
-- CORRECTIF VINGT-DEUXIÈME REVUE STATIQUE (six points, voir commentaires
-- inline aux sections concernées) :
--   1. (tests uniquement, aucun changement SQL de migration) B19/B20
--      atteignaient en réalité le trigger de garde de session (blocage 3,
--      21e revue) avant le CHECK/EXCLUDE visés — tests redessinés.
--   2. plan_verification_session() : p_verifier_user_id doit désormais
--      référencer une identité ACCRÉDITÉE (nouvelle table
--      accredited_verifiers + is_authorized_verifier_identity(), section
--      4bis) — l'existence d'un profil ne suffisait pas.
--   3. Invariant DIFFÉRÉ (section 3quater) : status='completed' <=>
--      exactement un résultat actif ; tout résultat implique
--      status='completed'. CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED
--      sur les deux tables — les index existants ne garantissaient qu'« au
--      plus un » actif, pas exactement un pour une session completed.
--   4. carbon_guard_verification_outcome_insert() (section 3ter) : capture
--      de clock_timestamp() déplacée APRÈS le verrou et les validations de
--      la session (auparavant à la déclaration, potentiellement avant une
--      attente sur le verrou).
--   5. evidence_files (section 2bis) : colonne file_hash ajoutée ; trigger
--      gelant project_id/type/file_url/file_hash dès qu'une ligne est
--      référencée par un verification_outcomes.
--   6. Policies verifier_read_projects/verifier_read_activity_logs/
--      verifier_read_evidence_files (section 4quinquies) : is_verifier()
--      générique remplacé par une relation scopée à une affectation réelle
--      (verification_sessions.verifier_user_id = auth.uid()) pour le projet
--      concerné.
--
-- CORRECTIF VINGT-TROISIÈME REVUE STATIQUE (quatre blocages + un gel
-- supplémentaire + un durcissement non bloquant) :
--   1. Cycle RLS mutuel projects<->verification_sessions (et
--      activity_logs/evidence_files) : EXISTS inline remplacés par
--      can_assigned_verifier_view_mrv_project()/can_client_view_verification_session()
--      (SECURITY DEFINER, section 4quater).
--   2. Accréditation contournable hors RPC : nouveau trigger BEFORE INSERT
--      OR UPDATE sur verification_sessions (section 4bis-bis) — tout
--      verifier_user_id non NULL doit être accrédité actif, quel que soit
--      le chemin d'écriture.
--   3. Révocation après assignation : complete_verification_session()
--      revalide l'accréditation ACTIVE à la clôture (FOR SHARE) ;
--      is_assigned_verifier() exige aussi une accréditation active.
--   4. file_hash incomplet : NOT NULL/non vide exigé avant qu'une
--      evidence_files serve de verification_report (RPC + trigger, qui
--      verrouille aussi la preuve FOR SHARE avant validation).
--   Gel supplémentaire (carbon_guard_verification_session_update) :
--      verifier_org/verifier_contact/scope/report_url gelés au même titre
--      que project_id/période/verifier_user_id.
--   Durcissement non bloquant : prévalidation confirmant que
--      is_project_admin() ne référence pas raw_user_meta_data (section 0).
--   Explicitement DIFFÉRÉS (non bloquants, hors périmètre de cette passe) :
--      historisation d'accredited_verifiers (VVB, valid_from/revoked_at/
--      référence d'accréditation) ; émission de deux événements distincts
--      (superseded sur l'ancien + recorded sur le nouveau) lors d'une
--      supersession — le comportement actuel (un seul événement, typé selon
--      le cas) est conservé tel quel.
--
-- CORRECTIF VINGT-QUATRIÈME REVUE STATIQUE (deux blocages + un ajustement) :
--   1. Révocation VVB incomplète sur la RLS projet :
--      can_assigned_verifier_view_mrv_project() (section 4quater) vérifiait
--      seulement verification_sessions.verifier_user_id = auth.uid(), sans
--      revalider l'accréditation active — un vérificateur révoqué perdait
--      sessions/outcomes/events (is_assigned_verifier(), 23e revue point 3)
--      mais conservait projects/project_activity_logs/evidence_files.
--      is_authorized_verifier_identity(vs.verifier_user_id) ajouté au EXISTS.
--   2. Bypass direct sur verification_outcomes :
--      complete_verification_session() revalide bien l'accréditation active
--      (FOR SHARE, 23e revue point 3), mais carbon_guard_verification_outcome_
--      insert() (section 3ter) ne la vérifiait pas — un INSERT privilégié
--      direct avec verified_by = verifier_user_id restait accepté après
--      révocation. Verrou FOR SHARE de accredited_verifiers pour
--      v_verifier_user_id AND active ajouté juste après la validation
--      verified_by (étape 3bis), même patron que le verrou de la preuve.
--   Ajustement du trigger verification_sessions_guard_verifier_accreditation
--      (section 4bis-bis) : ne revalide désormais l'accréditation que sur
--      INSERT, ou sur UPDATE lorsque verifier_user_id change réellement
--      (IS DISTINCT FROM OLD) — dans sa forme précédente, une révocation
--      ultérieure bloquait même un UPDATE de comments sur une session
--      historique déjà attestée, alors que l'accréditation ne doit être
--      valide qu'au moment de l'assignation/attestation, pas éternellement.
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
--      résultat actif par session — index unique partiel,
--      verification_report_document_id NOT NULL, protection structurelle de
--      la chaîne de supersession — correctif vingtième revue statique).
--   3. Immutabilité — trigger de garde (seule transition permise :
--      status active -> superseded) + réutilisation de
--      carbon_reject_update_delete() (migration 01) pour interdire DELETE.
--   3bis. Trigger de garde structurel sur verification_sessions —
--      project_id/reporting_period_start/reporting_period_end/
--      verifier_user_id immuables dès qu'un résultat existe pour la session
--      ou que status = 'completed' ; status = 'completed' terminal
--      (correctif vingtième revue statique).
--   4. is_assigned_verifier(uuid) — remplace is_verifier() dans
--      l'autorisation interne de complete_verification_session() (§10).
--   4bis. plan_verification_session(uuid,date,date,uuid) — RPC de
--      planification/assignation réservée à l'autorité MRV
--      (is_project_admin()/is_platform_superadmin()), remplace la policy RLS
--      UPDATE générale supprimée (correctif vingtième revue statique).
--   5. STUB carbon_capacity_consumed_for_session(uuid) (retourne 0
--      inconditionnellement — contrat exact §12, à remplacer par 07 via
--      CREATE OR REPLACE, jamais par cette migration elle-même une fois 07
--      appliquée) + complete_verification_session() (§3, séquence de
--      supersession révisée §12, dérogation superadmin retirée, seuil de 1%
--      corrigé pour le cas calculé=0, preuve documentaire obligatoire et
--      validée — correctif vingtième revue statique).
--   6. can_view_carbon_event() — CREATE OR REPLACE, MÊME signature à 4
--      paramètres posée par la migration 01, ajoute la branche vérificateur
--      assigné (§10bis). Malgré le commentaire de la migration 01 disant
--      « MIGRATION 04 AJOUTERA ICI » (rédigé avant le gel de numérotation du
--      14 juillet 2026, jamais mis à jour car 01 est appliquée/figée) —
--      c'est bien CETTE migration (05, verification_outcomes/is_assigned_verifier())
--      qui l'honore, pas 04 (ccf_mrv_project_links, sans rapport avec la
--      vérification).
--   7. RLS verification_outcomes (can_view_verification_outcome(), corrigée
--      pour scoper l'audience client à la relation réelle projects.client_id
--      — correctif vingtième revue statique).
--   8. Révocations de privilèges par défaut.
--   9. Section de rollback/désactivation, commentée, hors transaction.
--
-- Sections ajoutées par les 21e/22e revues statiques (voir correctifs
-- ci-dessus pour le détail) : 2bis (evidence_files.file_hash + gel),
-- 3ter (garde structurelle BEFORE INSERT verification_outcomes), 3quater
-- (invariant différé session/outcome), 4bis (accredited_verifiers +
-- is_authorized_verifier_identity()), 4quater (policies SELECT
-- verification_sessions scopées), 4quinquies (policies verifier_read_*
-- scopées sur projects/project_activity_logs/evidence_files).
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
    -- Correctif vingt-deuxième revue statique (point 2).
    IF to_regclass('public.accredited_verifiers') IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.accredited_verifiers existe déjà — cette migration ne doit être appliquée qu''une seule fois.';
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
    -- Correctif vingtième revue statique (durcissement) : rejet EXPLICITE,
    -- pas seulement un commentaire « à reconfirmer » — une session déjà
    -- 'completed' préexistante violerait immédiatement le CHECK
    -- verification_sessions_completed_requires_period_and_verifier ajouté en
    -- section 1 (reporting_period_start/end/verifier_user_id NULL sur une
    -- ligne existante déjà 'completed').
    IF EXISTS (
        SELECT 1 FROM public.verification_sessions
        WHERE status = 'completed'::public.verification_status
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : au moins une ligne verification_sessions a déjà le statut ''completed'' — le CHECK verification_sessions_completed_requires_period_and_verifier (section 1) serait immédiatement violé (reporting_period_start/end/verifier_user_id NULL sur cette ligne). Cette migration ne peut être appliquée qu''en l''absence de session ''completed'' préexistante, ou après un backfill manuel validé séparément.';
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

    IF to_regclass('public.profiles') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.profiles introuvable.';
    END IF;
    -- Correctif vingt-et-unième revue statique (blocage 5) : la preuve de
    -- vérification (verification_report_document_id) référence désormais
    -- evidence_files (déjà scopée par project_id, chantier MRV, voir
    -- 20260710999100_reapply_mrv_and_aggregators.sql), PAS documents (table
    -- CCF sans aucune notion de projet MRV — la vingtième revue statique
    -- avait retenu documents.category faute d'alternative structurellement
    -- scopée, corrigé ici). type sert d'équivalent à category.
    IF to_regclass('public.evidence_files') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.evidence_files introuvable (chantier MRV antérieur) — requise pour verification_report_document_id (correctif vingt-et-unième revue statique).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'evidence_files' AND column_name = 'project_id'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'evidence_files' AND column_name = 'type'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.evidence_files.project_id/type introuvable(s) — requis par la validation de verification_report_document_id (correctif vingt-et-unième revue statique).';
    END IF;
    -- Correctif vingt-deuxième revue statique (point 5).
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'evidence_files' AND column_name = 'file_hash'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.evidence_files.file_hash existe déjà — cette migration ne doit être appliquée qu''une seule fois.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
        WHERE t.relname = 'evidence_files' AND tg.tgname = 'evidence_files_guard_update'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : trigger evidence_files_guard_update existe déjà — cette migration ne doit être appliquée qu''une seule fois.';
    END IF;
    -- Correctif vingt-deuxième revue statique (point 3).
    IF EXISTS (
        SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
        WHERE t.relname = 'verification_outcomes' AND tg.tgname = 'verification_outcomes_check_session_invariant'
    ) OR EXISTS (
        SELECT 1 FROM pg_trigger tg JOIN pg_class t ON t.oid = tg.tgrelid
        WHERE t.relname = 'verification_sessions' AND tg.tgname = 'verification_sessions_check_outcome_invariant'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : au moins un des CONSTRAINT TRIGGER de l''invariant différé session/outcome existe déjà — cette migration ne doit être appliquée qu''une seule fois.';
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
    IF to_regprocedure('public.is_project_admin()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : is_project_admin() introuvable (chantier MRV antérieur) — réutilisée par can_view_verification_outcome() et plan_verification_session() pour rester cohérente avec admin_manage_verification_sessions.';
    END IF;
    -- Correctif vingtième revue statique (blocage 2) : requise par
    -- can_view_verification_outcome() — remplace is_project_client()
    -- (générique, sans portée par projet) par la relation réelle
    -- projects.client_id = auth.uid().
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'projects' AND column_name = 'client_id'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.projects.client_id introuvable — requis par can_view_verification_outcome() (correctif vingtième revue statique).';
    END IF;
    -- Correctif vingt-et-unième revue statique (blocage 2) : les policies
    -- SELECT PRÉEXISTANTES de verification_sessions (verifier_read_.../
    -- client_read_..., chantier MRV) portent encore les branches génériques
    -- is_verifier()/is_project_client() — prévalidées ICI via pg_policies
    -- (introspection du schéma RÉEL, pas une hypothèse) avant d'être
    -- remplacées (section 4ter) par des relations scopées à la session/au
    -- projet.
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'verification_sessions'
          AND policyname = 'verifier_read_verification_sessions'
          AND qual ILIKE '%is_verifier()%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : policy verifier_read_verification_sessions absente ou définition inattendue (attendu : is_verifier()) sur public.verification_sessions — schéma réel différent de l''hypothèse (correctif vingt-et-unième revue statique).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'verification_sessions'
          AND policyname = 'client_read_verification_sessions'
          AND qual ILIKE '%is_project_client()%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : policy client_read_verification_sessions absente ou définition inattendue (attendu : is_project_client()) sur public.verification_sessions — schéma réel différent de l''hypothèse (correctif vingt-et-unième revue statique).';
    END IF;
    -- Correctif vingt-deuxième revue statique (point 6) : mêmes policies
    -- verifier_read_* génériques (is_verifier()) sur projects/
    -- project_activity_logs/evidence_files — prévalidées ICI avant d'être
    -- remplacées (section 4quinquies) par une relation scopée à une
    -- affectation réelle dans verification_sessions.
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'projects'
          AND policyname = 'verifier_read_projects' AND qual ILIKE '%is_verifier()%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : policy verifier_read_projects absente ou définition inattendue (attendu : is_verifier()) sur public.projects (correctif vingt-deuxième revue statique).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'project_activity_logs'
          AND policyname = 'verifier_read_activity_logs' AND qual ILIKE '%is_verifier()%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : policy verifier_read_activity_logs absente ou définition inattendue (attendu : is_verifier()) sur public.project_activity_logs (correctif vingt-deuxième revue statique).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'evidence_files'
          AND policyname = 'verifier_read_evidence_files' AND qual ILIKE '%is_verifier()%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : policy verifier_read_evidence_files absente ou définition inattendue (attendu : is_verifier()) sur public.evidence_files (correctif vingt-deuxième revue statique).';
    END IF;
    IF to_regprocedure('public.carbon_reject_update_delete()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_reject_update_delete() introuvable — la migration 01 a-t-elle été appliquée ?';
    END IF;
    -- Correctif vingt-troisième revue statique (non bloquant, durcissement
    -- explicitement demandé) : is_project_admin() ne doit JAMAIS lire
    -- raw_user_meta_data (éditable par l'utilisateur lui-même, contrairement
    -- à app_metadata) — vérification défensive contre une régression future,
    -- pas une hypothèse sur l'état actuel (déjà confirmé app_metadata-only
    -- par lecture directe du code réel).
    IF pg_get_functiondef('public.is_project_admin()'::regprocedure) ILIKE '%raw_user_meta_data%' THEN
        RAISE EXCEPTION 'Prévalidation échouée : is_project_admin() référence raw_user_meta_data (éditable par l''utilisateur) — élévation de privilège potentielle, à corriger avant application.';
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
    -- Correctif vingtième revue statique (blocage 5) : NOT NULL — un résultat
    -- qui déclenchera ensuite l'admissibilité et l'émission de crédits ne
    -- doit jamais pouvoir exister sans aucune preuve. Correctif vingt-et-unième
    -- revue statique (même blocage, poussé plus loin) : référence désormais
    -- evidence_files (PAS documents — table CCF sans notion de projet MRV,
    -- structurellement incapable d'exprimer « appartient au même projet »).
    -- evidence_files.project_id permet la validation réelle d'appartenance,
    -- appliquée par le trigger BEFORE INSERT (section 3ter) ET par
    -- complete_verification_session() (section 5) : preuve existante, type =
    -- 'verification_report', ET project_id = celui de la session.
    verification_report_document_id  UUID NOT NULL REFERENCES public.evidence_files(id),
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

-- Correctif vingtième revue statique (blocage 6) : protection STRUCTURELLE de
-- la chaîne de supersession, indépendante des pré-vérifications de
-- complete_verification_session() — une écriture privilégiée (ou un futur
-- bug applicatif) ne doit pas pouvoir créer une auto-référence, une
-- supersession inter-session, un fork (deux résultats prétendant remplacer
-- le même ancien), ou une nouvelle racine alors qu'un historique existe déjà.

-- (a) Pas d'auto-référence.
ALTER TABLE public.verification_outcomes
    ADD CONSTRAINT verification_outcomes_no_self_supersede
    CHECK (supersedes_outcome_id IS NULL OR supersedes_outcome_id <> id);

-- (b) Au plus UN résultat peut prétendre remplacer un ancien résultat donné
--     (pas de fork de la chaîne).
CREATE UNIQUE INDEX idx_verification_outcomes_supersedes_once
    ON public.verification_outcomes (supersedes_outcome_id)
    WHERE supersedes_outcome_id IS NOT NULL;

-- (c) Au plus UNE racine (supersedes_outcome_id IS NULL) par session — le
--     tout premier résultat jamais créé pour cette session, jamais un
--     second après coup.
CREATE UNIQUE INDEX idx_verification_outcomes_one_root_per_session
    ON public.verification_outcomes (verification_session_id)
    WHERE supersedes_outcome_id IS NULL;

-- (d) FK composite forçant supersedes_outcome_id à appartenir à la MÊME
--     session (empêche une supersession inter-session) — MATCH SIMPLE
--     (défaut PostgreSQL) : la contrainte n'est PAS vérifiée quand
--     supersedes_outcome_id est NULL (résultat racine), comme voulu.
ALTER TABLE public.verification_outcomes
    ADD CONSTRAINT verification_outcomes_id_session_unique
    UNIQUE (id, verification_session_id);

ALTER TABLE public.verification_outcomes
    ADD CONSTRAINT verification_outcomes_supersedes_same_session
    FOREIGN KEY (supersedes_outcome_id, verification_session_id)
    REFERENCES public.verification_outcomes (id, verification_session_id);

-- ────────────────────────────────────────────────────────────
-- 2bis. GEL DES PROPRIÉTÉS CRITIQUES D'evidence_files RÉFÉRENCÉES —
--    correctif vingt-deuxième revue statique (point 5). Une fois une preuve
--    validée et référencée par un verification_outcomes
--    (verification_report_document_id), rien n'empêchait jusqu'ici de
--    modifier ensuite son project_id/type/file_url — invalidant
--    silencieusement, a posteriori, une validation déjà effectuée
--    (project_id/type sont précisément les deux colonnes vérifiées par
--    complete_verification_session() et le trigger BEFORE INSERT, section
--    3ter). Ajout d'une colonne file_hash (intégrité, non calculée ni
--    validée par cette migration — alimentation par le pipeline
--    d'upload/application, hors périmètre SQL) ET d'un trigger gelant les
--    quatre colonnes critiques (project_id/type/file_url/file_hash) dès
--    qu'AU MOINS UN verification_outcomes référence la ligne. evidence_files
--    est une table PRÉEXISTANTE (chantier MRV, ccf indépendant) — cette
--    migration l'ALTER/lui ajoute un trigger sans en être propriétaire
--    d'origine, même patron que l'ALTER TABLE verification_sessions
--    (section 1) ci-dessus.
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.evidence_files
    ADD COLUMN IF NOT EXISTS file_hash TEXT NULL;

COMMENT ON COLUMN public.evidence_files.file_hash IS
  'Hash d''intégrité du fichier (algorithme et alimentation laissés au pipeline '
  'd''upload applicatif — non calculé/validé par SQL). Gelé, comme project_id/type/'
  'file_url, dès que la ligne est référencée par un verification_outcomes '
  '(correctif vingt-deuxième revue statique, point 5).';

CREATE OR REPLACE FUNCTION public.carbon_guard_evidence_file_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.verification_outcomes
        WHERE verification_report_document_id = OLD.id
    ) THEN
        IF NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.type IS DISTINCT FROM OLD.type
           OR NEW.file_url IS DISTINCT FROM OLD.file_url
           OR NEW.file_hash IS DISTINCT FROM OLD.file_hash
        THEN
            RAISE EXCEPTION 'evidence_files : project_id/type/file_url/file_hash sont immuables dès que cette preuve est référencée par au moins un verification_outcomes.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_evidence_file_update() IS
  'Gèle project_id/type/file_url/file_hash sur evidence_files dès qu''une ligne est '
  'référencée par au moins un verification_outcomes.verification_report_document_id '
  '— correctif vingt-deuxième revue statique (point 5). Les autres colonnes '
  '(gps/timestamp/actor_id/related_activity_log_id) restent librement modifiables.';

CREATE TRIGGER evidence_files_guard_update
    BEFORE UPDATE ON public.evidence_files
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_evidence_file_update();

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
-- 3ter. GARDE STRUCTURELLE BEFORE INSERT sur verification_outcomes —
--    correctif vingt-et-unième revue statique (blocage 4). complete_verification_session()
--    applique déjà toutes ces vérifications (section 5), mais un INSERT
--    DIRECT (hors RPC — écriture privilégiée, bug applicatif futur) les
--    contournait entièrement. Ce trigger les applique structurellement à
--    TOUT chemin d'insertion, indépendamment de l'appelant. Regroupe :
--      1. Verrou de la session (FOR UPDATE) — sérialise les insertions
--         concurrentes ciblant la même session ; ré-acquérir un verrou déjà
--         détenu dans la même transaction (cas normal via la RPC) est un
--         no-op, pas un blocage.
--      2. Statut/période/assignation valides (mêmes règles que la RPC).
--      3. verified_by DOIT être exactement le vérificateur assigné à la
--         session — ferme la possibilité qu'un INSERT direct attribue le
--         résultat à n'importe qui.
--      4. status ne peut être inséré qu'''active'' — jamais directement
--         ''superseded'' (un résultat ne naît jamais déjà remplacé).
--      5. Preuve valide (evidence_files : existe, type=''verification_report'',
--         project_id = celui de la session — même règle que la RPC).
--      6. Timestamps DB — verified_at/created_at forcés à un seul
--         clock_timestamp(), jamais une valeur fournie par l'appelant (même
--         patron que la migration 04, correctif vingtième revue statique).
--      7. Auto-référence explicitement rejetée (message dédié, plus clair
--         que le CHECK verification_outcomes_no_self_supersede seul, qui
--         reste néanmoins en place comme filet redondant).
--      8. Racine (supersedes_outcome_id NULL) : n'est permise QUE si AUCUN
--         résultat n'existe encore pour cette session — plus stricte que
--         l'index idx_verification_outcomes_one_root_per_session seul
--         (celui-ci reste en place comme filet redondant pour tout chemin
--         qui contournerait le trigger).
--      9. Supersession (supersedes_outcome_id NOT NULL) : le résultat
--         référencé doit exister ET être DÉJÀ ''superseded'' — reflète
--         l'ordre réel des opérations de complete_verification_session()
--         (l'ancien est marqué superseded AVANT l'INSERT du nouveau) ; ET
--         adjustment_reason obligatoire (plancher structurel — la RPC
--         applique en plus sa logique de seuil plus fine pour le premier
--         résultat, non dupliquée ici, qui nécessite project_activity_logs).
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_guard_verification_outcome_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    -- Correctif vingt-deuxième revue statique (point 4) : v_now n'est PLUS
    -- capturé à la déclaration (donc potentiellement AVANT l'attente sur le
    -- verrou FOR UPDATE en cas de contention) — voir l'affectation explicite
    -- plus bas, après le verrou et les validations de la session.
    v_now              TIMESTAMPTZ;
    v_session_found    BOOLEAN;
    v_session_status   public.verification_status;
    v_period_start     DATE;
    v_period_end       DATE;
    v_verifier_user_id UUID;
    v_parent_status    TEXT;
BEGIN
    -- 1. Verrou de la session.
    SELECT true, status, reporting_period_start, reporting_period_end, verifier_user_id
    INTO v_session_found, v_session_status, v_period_start, v_period_end, v_verifier_user_id
    FROM public.verification_sessions
    WHERE id = NEW.verification_session_id
    FOR UPDATE;

    IF NOT COALESCE(v_session_found, false) THEN
        RAISE EXCEPTION 'verification_outcomes : verification_session_id ne correspond à aucune session existante.';
    END IF;

    -- 2. Statut/période/assignation valides.
    IF v_session_status = 'planned'::public.verification_status THEN
        RAISE EXCEPTION 'verification_outcomes : la session doit être in_progress ou completed (planned rencontré).';
    END IF;
    IF v_period_start IS NULL OR v_period_end IS NULL THEN
        RAISE EXCEPTION 'verification_outcomes : la session doit avoir une période renseignée (reporting_period_start/reporting_period_end).';
    END IF;
    IF v_verifier_user_id IS NULL THEN
        RAISE EXCEPTION 'verification_outcomes : la session doit avoir un vérificateur assigné (verifier_user_id).';
    END IF;

    -- 3. verified_by doit être EXACTEMENT le vérificateur assigné.
    IF NEW.verified_by IS DISTINCT FROM v_verifier_user_id THEN
        RAISE EXCEPTION 'verification_outcomes : verified_by doit être le vérificateur assigné à la session (verifier_user_id).';
    END IF;

    -- 4. Insertion uniquement en 'active'.
    IF NEW.status <> 'active' THEN
        RAISE EXCEPTION 'verification_outcomes : seule l''insertion en status=''active'' est permise — un résultat ne peut jamais être inséré déjà superseded.';
    END IF;

    -- Correctif vingt-deuxième revue statique (point 4) : capture de
    -- l'horodatage APRÈS le verrou (FOR UPDATE, point 1) et les validations
    -- de la session (points 2-4) — jamais avant une éventuelle attente sur
    -- le verrou, pour que verified_at/created_at reflètent le moment où
    -- l'insertion est réellement en cours de validation, pas celui où la
    -- fonction a commencé à s'exécuter.
    v_now := clock_timestamp();

    -- 5. Preuve valide, scopée au même projet MRV, intégrité renseignée.
    IF NEW.verification_report_document_id IS NULL THEN
        RAISE EXCEPTION 'verification_outcomes : verification_report_document_id est obligatoire.';
    END IF;
    -- Correctif vingt-troisième revue statique (point 4) : verrou FOR SHARE
    -- de la preuve AVANT de la valider — ferme la course concurrente
    -- preuve<->outcome (une modification concurrente de evidence_files,
    -- elle-même bloquée une fois référencée par evidence_files_guard_update,
    -- attend désormais que CETTE transaction se termine avant de pouvoir
    -- s'exécuter, et inversement). No-op silencieux si la ligne n'existe
    -- pas encore — l'EXISTS ci-dessous échoue alors normalement.
    PERFORM 1 FROM public.evidence_files WHERE id = NEW.verification_report_document_id FOR SHARE;
    IF NOT EXISTS (
        SELECT 1 FROM public.evidence_files ef
        JOIN public.verification_sessions vs ON vs.id = NEW.verification_session_id
        WHERE ef.id = NEW.verification_report_document_id
          AND ef.type = 'verification_report'
          AND ef.project_id = vs.project_id
          AND ef.file_hash IS NOT NULL AND btrim(ef.file_hash) <> ''
    ) THEN
        RAISE EXCEPTION 'verification_outcomes : verification_report_document_id doit référencer une preuve (evidence_files) existante, de type ''verification_report'', appartenant au même projet MRV que la session, avec file_hash renseigné.';
    END IF;

    -- 6. Timestamps DB — un seul clock_timestamp(), jamais une valeur fournie.
    NEW.verified_at := v_now;
    NEW.created_at := v_now;

    IF NEW.supersedes_outcome_id IS NOT NULL THEN
        -- 7. Auto-référence.
        IF NEW.supersedes_outcome_id = NEW.id THEN
            RAISE EXCEPTION 'verification_outcomes : supersedes_outcome_id ne peut pas référencer le résultat lui-même.';
        END IF;

        -- 9. Le résultat référencé doit exister et être DÉJÀ superseded.
        SELECT status INTO v_parent_status FROM public.verification_outcomes WHERE id = NEW.supersedes_outcome_id;
        IF v_parent_status IS NULL THEN
            RAISE EXCEPTION 'verification_outcomes : supersedes_outcome_id ne correspond à aucun résultat existant.';
        END IF;
        IF v_parent_status <> 'superseded' THEN
            RAISE EXCEPTION 'verification_outcomes : le résultat référencé par supersedes_outcome_id doit déjà être superseded (marquer l''ancien résultat AVANT d''insérer le nouveau).';
        END IF;

        IF NEW.adjustment_reason IS NULL OR btrim(NEW.adjustment_reason) = '' THEN
            RAISE EXCEPTION 'verification_outcomes : adjustment_reason est obligatoire pour toute supersession.';
        END IF;
    ELSE
        -- 8. Racine : uniquement si AUCUN résultat n'existe encore pour cette session.
        IF EXISTS (SELECT 1 FROM public.verification_outcomes WHERE verification_session_id = NEW.verification_session_id) THEN
            RAISE EXCEPTION 'verification_outcomes : un résultat racine (supersedes_outcome_id NULL) ne peut être inséré que si aucun résultat n''existe encore pour cette session.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_verification_outcome_insert() IS
  'Garde structurelle BEFORE INSERT sur verification_outcomes (correctif '
  'vingt-et-unième revue statique, blocage 4) : verrouille la session, valide '
  'statut/période/assignation, force verified_by = vérificateur assigné, n''autorise '
  'l''insertion qu''en status=''active'', valide la preuve (evidence_files, type + '
  'project_id + file_hash, verrou FOR SHARE), force les timestamps via '
  'clock_timestamp(), et protège la chaîne de supersession (auto-référence, racine '
  'unique, parent déjà superseded, raison obligatoire) — indépendamment de '
  'complete_verification_session(), pour tout chemin d''insertion. Redéfinie plus loin '
  '(après section 4bis) pour ajouter la revalidation de l''accréditation active — '
  'accredited_verifiers n''existe pas encore à ce point du script.';

CREATE TRIGGER verification_outcomes_guard_insert
    BEFORE INSERT ON public.verification_outcomes
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_verification_outcome_insert();

-- ────────────────────────────────────────────────────────────
-- 3bis. GARDE STRUCTURELLE sur verification_sessions — correctif vingtième
--    revue statique (blocage 1). project_id/reporting_period_start/
--    reporting_period_end/verifier_user_id deviennent immuables dès qu'un
--    résultat de vérification existe pour la session OU que status =
--    'completed' ; status = 'completed' est terminal. Nécessaire car la
--    policy RLS UPDATE générale supprimée (admin_manage_verification_sessions,
--    FOR ALL, is_project_admin(), INCHANGÉE) permet toujours des écritures
--    directes par un admin MRV — une policy seule ne peut pas empêcher un
--    admin de modifier la période/le vérificateur d'une session déjà
--    attestée ; seul un trigger structurel le peut.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_guard_verification_session_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_has_outcome BOOLEAN;
BEGIN
    IF OLD.status = 'completed'::public.verification_status
       AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'verification_sessions : une session completed est terminale, le statut ne peut plus changer.';
    END IF;

    v_has_outcome := EXISTS (
        SELECT 1 FROM public.verification_outcomes WHERE verification_session_id = OLD.id
    );

    -- Correctif vingt-et-unième revue statique (blocage 3) : la RPC légitime
    -- (complete_verification_session()) insère toujours le verification_outcome
    -- AVANT cette UPDATE de statut — v_has_outcome est donc déjà VRAI au
    -- moment où cette UPDATE atteint le trigger pour un passage légitime.
    -- Une écriture directe (admin_manage_verification_sessions, FOR ALL,
    -- is_project_admin(), toujours en place) qui tenterait de marquer
    -- 'completed' SANS être passée par la RPC — donc sans qu'aucun résultat
    -- n'existe encore — est désormais rejetée structurellement ici.
    IF NEW.status = 'completed'::public.verification_status
       AND OLD.status IS DISTINCT FROM NEW.status
       AND NOT v_has_outcome THEN
        RAISE EXCEPTION 'verification_sessions : transition vers completed refusée — aucun verification_outcome n''existe encore pour cette session (utiliser complete_verification_session()).';
    END IF;

    IF OLD.status = 'completed'::public.verification_status OR v_has_outcome THEN
        IF NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.reporting_period_start IS DISTINCT FROM OLD.reporting_period_start
           OR NEW.reporting_period_end IS DISTINCT FROM OLD.reporting_period_end
           OR NEW.verifier_user_id IS DISTINCT FROM OLD.verifier_user_id
           -- Correctif vingt-troisième revue statique (gel supplémentaire) :
           -- verifier_org/verifier_contact/scope/report_url font partie du
           -- dossier officiel d'une vérification attestée au même titre que
           -- project_id/période/verifier_user_id — rien ne justifie qu'ils
           -- restent modifiables après coup alors que le reste est gelé.
           OR NEW.verifier_org IS DISTINCT FROM OLD.verifier_org
           OR NEW.verifier_contact IS DISTINCT FROM OLD.verifier_contact
           OR NEW.scope IS DISTINCT FROM OLD.scope
           OR NEW.report_url IS DISTINCT FROM OLD.report_url
        THEN
            RAISE EXCEPTION 'verification_sessions : project_id/reporting_period_start/reporting_period_end/verifier_user_id/verifier_org/verifier_contact/scope/report_url sont immuables dès qu''un résultat de vérification existe pour cette session ou que son statut est completed.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_verification_session_update() IS
  'Gèle project_id/reporting_period_start/reporting_period_end/verifier_user_id/'
  'verifier_org/verifier_contact/scope/report_url dès qu''un verification_outcomes '
  'existe pour la session ou que status = ''completed'' (également terminal pour '
  'status lui-même) — correctif vingtième revue statique, étendu vingt-troisième '
  'revue statique (gel supplémentaire du dossier officiel), indépendant de toute '
  'policy RLS. Correctif vingt-et-unième revue statique (blocage 3) : rejette aussi '
  'toute transition directe vers ''completed'' tant qu''aucun verification_outcome '
  'n''existe encore pour la session (seule complete_verification_session() peut '
  'légitimement compléter une session, car elle insère toujours l''outcome avant '
  'cette UPDATE).';

CREATE TRIGGER verification_sessions_guard_update
    BEFORE UPDATE ON public.verification_sessions
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_verification_session_update();

-- ────────────────────────────────────────────────────────────
-- 3quater. INVARIANT DIFFÉRÉ session <-> outcome — correctif vingt-deuxième
--    revue statique (point 3). Les index/triggers existants garantissent
--    seulement « AU PLUS un résultat actif par session » (idx_verification_
--    outcomes_one_active_per_session) — rien n'empêchait structurellement
--    qu'une session 'completed' se retrouve avec ZÉRO résultat actif (la
--    démotion directe active -> superseded, transition légitime du trigger
--    d'immutabilité section 3, suffit à créer ce trou — démontré par les
--    tests de la vingt-et-unième revue statique) ni qu'une session encore
--    'in_progress' accumule un résultat (le trigger BEFORE INSERT, section
--    3ter, n'exige pas status='completed', seulement status<>'planned').
--
--    Invariant voulu, valable pour toute session UNE FOIS la transaction
--    stabilisée : status='completed' <=> exactement UN résultat actif ;
--    et plus généralement, AU MOINS un résultat (actif ou superseded)
--    implique status='completed'.
--
--    Impossible à exprimer en CHECK (porte sur DEUX tables). Impossible à
--    vérifier de façon IMMÉDIATE sans casser des séquences légitimes en
--    plusieurs étapes dans la MÊME transaction (ex. complete_verification_session()
--    insère l'outcome AVANT de faire passer la session à 'completed' —
--    l'état intermédiaire, entre les deux instructions, viole
--    transitoirement l'invariant). D'où un CONSTRAINT TRIGGER DEFERRABLE
--    INITIALLY DEFERRED (vérifié à la validation de la transaction, ou plus
--    tôt sur demande explicite via SET CONSTRAINTS ... IMMEDIATE) sur
--    CHACUNE des deux tables concernées, partageant la même fonction de
--    vérification (qui relit l'état COURANT plutôt que OLD/NEW — peu importe
--    combien d'événements sont en attente pour une même session, seul l'état
--    au moment du contrôle compte).
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_check_verification_session_outcome_invariant()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_id   UUID;
    v_status       public.verification_status;
    v_active_count INT;
    v_any_count    INT;
BEGIN
    IF TG_TABLE_NAME = 'verification_outcomes' THEN
        v_session_id := COALESCE(NEW.verification_session_id, OLD.verification_session_id);
    ELSE
        v_session_id := COALESCE(NEW.id, OLD.id);
    END IF;

    SELECT status INTO v_status FROM public.verification_sessions WHERE id = v_session_id;
    IF v_status IS NULL THEN
        -- Session absente (ne devrait pas se produire : ON DELETE RESTRICT
        -- depuis verification_outcomes.verification_session_id empêche sa
        -- suppression tant qu'un résultat existe) — rien à vérifier.
        RETURN NULL;
    END IF;

    SELECT count(*) FILTER (WHERE status = 'active'), count(*)
    INTO v_active_count, v_any_count
    FROM public.verification_outcomes
    WHERE verification_session_id = v_session_id;

    IF v_status = 'completed'::public.verification_status THEN
        IF v_active_count <> 1 THEN
            RAISE EXCEPTION 'Invariant différé violé : la session % est completed mais compte % résultat(s) actif(s) (exactement 1 attendu).', v_session_id, v_active_count;
        END IF;
    ELSE
        IF v_any_count > 0 THEN
            RAISE EXCEPTION 'Invariant différé violé : la session % possède % résultat(s) alors que son statut n''est pas completed.', v_session_id, v_any_count;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.carbon_check_verification_session_outcome_invariant() IS
  'Invariant différé (correctif vingt-deuxième revue statique, point 3) : status=''completed'' '
  '<=> exactement un verification_outcomes actif ; tout résultat implique status=''completed''. '
  'Relit l''état courant (pas OLD/NEW) — indépendant du nombre d''événements en attente pour '
  'une même session. Attaché via CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED sur les deux '
  'tables (voir ci-dessous) : les transitions multi-instructions légitimes (complete_verification_session()) '
  'restent possibles, seul l''état final de la transaction est contraint.';

-- DELETE volontairement absent ici : verification_outcomes_reject_delete
-- (section 3) rejette déjà INCONDITIONNELLEMENT tout DELETE — la branche
-- DELETE de ce trigger ne serait jamais atteignable (append-only).
CREATE CONSTRAINT TRIGGER verification_outcomes_check_session_invariant
    AFTER INSERT OR UPDATE ON public.verification_outcomes
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.carbon_check_verification_session_outcome_invariant();

CREATE CONSTRAINT TRIGGER verification_sessions_check_outcome_invariant
    AFTER INSERT OR UPDATE OF status ON public.verification_sessions
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.carbon_check_verification_session_outcome_invariant();

-- ────────────────────────────────────────────────────────────
-- 4. is_assigned_verifier(uuid) — §10, remplace is_verifier() dans
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

-- ────────────────────────────────────────────────────────────
-- 4bis. TABLE accredited_verifiers + is_authorized_verifier_identity() —
--    correctif vingt-deuxième revue statique (point 2). plan_verification_session()
--    ne validait jusqu'ici que l'EXISTENCE d'un profil pour p_verifier_user_id
--    (public.profiles), jamais qu'il s'agisse réellement d'une identité de
--    vérificateur autorisée — n'importe quel profil (client, admin, ou
--    même l'appelant super-admin lui-même) pouvait donc être assigné.
--
--    Deux options envisagées : (a) vérifier app_metadata.role='verifier'
--    de la CIBLE (p_verifier_user_id) — REJETÉE : aucune fonction
--    existante ne lit le app_metadata d'un utilisateur AUTRE que
--    l'appelant courant (is_verifier()/is_project_admin()/
--    is_platform_superadmin() sont toutes strictement auto-référentielles,
--    auth.jwt() ne reflétant que la session de l'appelant), et une telle
--    lecture nécessiterait d'interroger auth.users pour un tiers — fragile
--    et non structurellement vérifiable en SQL ordinaire pour un profil
--    arbitraire ; (b) une table persistante — RETENUE, recommandée par la
--    revue elle-même (« mieux ») : relation réelle, vérifiable par une
--    requête SQL ordinaire, sans dépendre du contenu d'un JWT.
--
--    Gestion (accréditation/révocation) volontairement HORS périmètre de
--    cette migration — aucune RPC ni policy INSERT/UPDATE exposée ici,
--    écriture réservée à un accès privilégié direct (cohérent avec
--    documents_owner_admin_insert absent pour DELETE sur documents,
--    MVP-DA-006) ; à raccorder à un futur flux d'accréditation VVB.
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.accredited_verifiers (
    user_id       UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    accredited_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    accredited_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    active        BOOLEAN NOT NULL DEFAULT true
);

COMMENT ON TABLE public.accredited_verifiers IS
  'Registre structurel des identités autorisées à être assignées comme vérificateur '
  '(VVB) via plan_verification_session() — correctif vingt-deuxième revue statique '
  '(point 2). Remplace un contrôle app_metadata (non lisible pour un tiers) par une '
  'relation réelle. Gestion (accréditation/révocation) hors périmètre de cette migration.';

ALTER TABLE public.accredited_verifiers ENABLE ROW LEVEL SECURITY;

CREATE POLICY accredited_verifiers_admin_select ON public.accredited_verifiers
    FOR SELECT
    USING (public.is_platform_superadmin() OR public.is_project_admin());

REVOKE ALL ON public.accredited_verifiers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.accredited_verifiers TO authenticated;

CREATE OR REPLACE FUNCTION public.is_authorized_verifier_identity(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.accredited_verifiers
        WHERE user_id = p_user_id AND active
    )
$$;

COMMENT ON FUNCTION public.is_authorized_verifier_identity(UUID) IS
  'Vérifie que p_user_id est une identité de vérificateur accréditée (accredited_verifiers, '
  'active=true) — utilisée par plan_verification_session() pour valider p_verifier_user_id '
  '(correctif vingt-deuxième revue statique, point 2). Fonction interne : aucun EXECUTE '
  'accordé à authenticated/anon (appelée uniquement depuis un contexte SECURITY DEFINER '
  'déjà privilégié).';

REVOKE ALL ON FUNCTION public.is_authorized_verifier_identity(UUID) FROM PUBLIC, anon, authenticated;

-- Correctif vingt-troisième revue statique (point 3, recommandation
-- explicite) : is_assigned_verifier() (section 4 ci-dessus) exige désormais
-- AUSSI une accréditation active — un vérificateur dont l'accréditation est
-- révoquée perd immédiatement l'accès applicatif (RLS sur
-- verification_sessions/verification_outcomes, can_view_carbon_event()),
-- pas seulement la capacité d'attester via complete_verification_session()
-- (revalidée séparément à la clôture, voir section 5 plus bas).
-- CREATE OR REPLACE ICI (et non dans la définition d'origine, section 4) :
-- is_authorized_verifier_identity() n'existe qu'à partir de cette section.
CREATE OR REPLACE FUNCTION public.is_assigned_verifier(p_verification_session_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.verification_sessions vs
        WHERE vs.id = p_verification_session_id
          AND vs.verifier_user_id = auth.uid()
          AND public.is_authorized_verifier_identity(vs.verifier_user_id)
    )
$$;

COMMENT ON FUNCTION public.is_assigned_verifier(UUID) IS
  'Vérifie que l''appelant courant est le vérificateur assigné à CETTE session précise '
  '(verification_sessions.verifier_user_id = auth.uid()) ET que cette identité est '
  'toujours accréditée active (accredited_verifiers) — correctif vingt-troisième revue '
  'statique (point 3) : une révocation d''accréditation retire immédiatement l''accès '
  'applicatif, pas seulement la capacité d''attester.';

-- Correctif vingt-quatrième revue statique (blocage 2) : complete_verification_
-- session() revalide déjà l'accréditation active à la clôture (verrou FOR
-- SHARE, vingt-troisième revue, point 3) — mais un INSERT privilégié DIRECT
-- sur verification_outcomes (hors RPC) contournait ce contrôle tant que
-- verified_by concordait formellement avec verifier_user_id, même après
-- révocation. CREATE OR REPLACE ICI (et non dans la définition d'origine,
-- section 3ter) : accredited_verifiers n'existe qu'à partir de cette
-- section (même patron que is_assigned_verifier() ci-dessus) — le corps est
-- IDENTIQUE à la définition d'origine, seule l'étape 3bis est ajoutée.
CREATE OR REPLACE FUNCTION public.carbon_guard_verification_outcome_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now              TIMESTAMPTZ;
    v_session_found    BOOLEAN;
    v_session_status   public.verification_status;
    v_period_start     DATE;
    v_period_end       DATE;
    v_verifier_user_id UUID;
    v_parent_status    TEXT;
BEGIN
    -- 1. Verrou de la session.
    SELECT true, status, reporting_period_start, reporting_period_end, verifier_user_id
    INTO v_session_found, v_session_status, v_period_start, v_period_end, v_verifier_user_id
    FROM public.verification_sessions
    WHERE id = NEW.verification_session_id
    FOR UPDATE;

    IF NOT COALESCE(v_session_found, false) THEN
        RAISE EXCEPTION 'verification_outcomes : verification_session_id ne correspond à aucune session existante.';
    END IF;

    -- 2. Statut/période/assignation valides.
    IF v_session_status = 'planned'::public.verification_status THEN
        RAISE EXCEPTION 'verification_outcomes : la session doit être in_progress ou completed (planned rencontré).';
    END IF;
    IF v_period_start IS NULL OR v_period_end IS NULL THEN
        RAISE EXCEPTION 'verification_outcomes : la session doit avoir une période renseignée (reporting_period_start/reporting_period_end).';
    END IF;
    IF v_verifier_user_id IS NULL THEN
        RAISE EXCEPTION 'verification_outcomes : la session doit avoir un vérificateur assigné (verifier_user_id).';
    END IF;

    -- 3. verified_by doit être EXACTEMENT le vérificateur assigné.
    IF NEW.verified_by IS DISTINCT FROM v_verifier_user_id THEN
        RAISE EXCEPTION 'verification_outcomes : verified_by doit être le vérificateur assigné à la session (verifier_user_id).';
    END IF;

    -- 3bis. Correctif vingt-quatrième revue statique (blocage 2) : verrou
    -- FOR SHARE de la ligne accredited_verifiers pour sérialiser une
    -- révocation concurrente, même patron que le verrou de la preuve
    -- (point 5 ci-dessous) — ferme le bypass par INSERT direct après
    -- révocation.
    PERFORM 1 FROM public.accredited_verifiers WHERE user_id = v_verifier_user_id AND active FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'verification_outcomes : le vérificateur assigné à la session (verifier_user_id) n''a plus d''accréditation active (accredited_verifiers) — impossible d''enregistrer un résultat de vérification.';
    END IF;

    -- 4. Insertion uniquement en 'active'.
    IF NEW.status <> 'active' THEN
        RAISE EXCEPTION 'verification_outcomes : seule l''insertion en status=''active'' est permise — un résultat ne peut jamais être inséré déjà superseded.';
    END IF;

    -- 5. Preuve valide, scopée au même projet MRV, intégrité renseignée.
    IF NEW.verification_report_document_id IS NULL THEN
        RAISE EXCEPTION 'verification_outcomes : verification_report_document_id est obligatoire.';
    END IF;
    PERFORM 1 FROM public.evidence_files WHERE id = NEW.verification_report_document_id FOR SHARE;
    IF NOT EXISTS (
        SELECT 1 FROM public.evidence_files ef
        JOIN public.verification_sessions vs ON vs.id = NEW.verification_session_id
        WHERE ef.id = NEW.verification_report_document_id
          AND ef.type = 'verification_report'
          AND ef.project_id = vs.project_id
          AND ef.file_hash IS NOT NULL AND btrim(ef.file_hash) <> ''
    ) THEN
        RAISE EXCEPTION 'verification_outcomes : verification_report_document_id doit référencer une preuve (evidence_files) existante, de type ''verification_report'', appartenant au même projet MRV que la session, avec file_hash renseigné.';
    END IF;

    IF NEW.supersedes_outcome_id IS NOT NULL THEN
        -- 7. Auto-référence.
        IF NEW.supersedes_outcome_id = NEW.id THEN
            RAISE EXCEPTION 'verification_outcomes : supersedes_outcome_id ne peut pas référencer le résultat lui-même.';
        END IF;

        -- 9. Le résultat référencé doit exister et être DÉJÀ superseded.
        SELECT status INTO v_parent_status FROM public.verification_outcomes WHERE id = NEW.supersedes_outcome_id;
        IF v_parent_status IS NULL THEN
            RAISE EXCEPTION 'verification_outcomes : supersedes_outcome_id ne correspond à aucun résultat existant.';
        END IF;
        IF v_parent_status <> 'superseded' THEN
            RAISE EXCEPTION 'verification_outcomes : le résultat référencé par supersedes_outcome_id doit déjà être superseded (marquer l''ancien résultat AVANT d''insérer le nouveau).';
        END IF;

        IF NEW.adjustment_reason IS NULL OR btrim(NEW.adjustment_reason) = '' THEN
            RAISE EXCEPTION 'verification_outcomes : adjustment_reason est obligatoire pour toute supersession.';
        END IF;
    ELSE
        -- 8. Racine : uniquement si AUCUN résultat n'existe encore pour cette session.
        IF EXISTS (SELECT 1 FROM public.verification_outcomes WHERE verification_session_id = NEW.verification_session_id) THEN
            RAISE EXCEPTION 'verification_outcomes : un résultat racine (supersedes_outcome_id NULL) ne peut être inséré que si aucun résultat n''existe encore pour cette session.';
        END IF;
    END IF;

    -- 6. Timestamps DB — un seul clock_timestamp(), jamais une valeur fournie.
    -- Correctif vingt-cinquième revue statique (blocage 2) : capturé ICI, en
    -- toute dernière étape avant RETURN NEW — après le verrou/validation de
    -- la preuve (point 5) et les contrôles de supersession (points 7-9), pas
    -- seulement après le verrou d'accréditation (point 3bis). En cas
    -- d'attente sur le verrou FOR SHARE de la preuve (contention), verified_
    -- at/created_at reflétaient auparavant un instant potentiellement
    -- antérieur de plusieurs secondes/minutes à la version de preuve
    -- effectivement validée.
    v_now := clock_timestamp();
    NEW.verified_at := v_now;
    NEW.created_at := v_now;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_verification_outcome_insert() IS
  'Garde structurelle BEFORE INSERT sur verification_outcomes (correctif '
  'vingt-et-unième revue statique, blocage 4) : verrouille la session, valide '
  'statut/période/assignation, force verified_by = vérificateur assigné, revalide '
  'l''accréditation active du vérificateur (accredited_verifiers, verrou FOR SHARE, '
  'correctif vingt-quatrième revue statique, blocage 2 — ferme le bypass par INSERT '
  'direct après révocation), n''autorise l''insertion qu''en status=''active'', valide la '
  'preuve (evidence_files, type + project_id + file_hash, verrou FOR SHARE), protège la '
  'chaîne de supersession (auto-référence, racine unique, parent déjà superseded, '
  'raison obligatoire), PUIS force en tout dernier lieu les timestamps via un seul '
  'clock_timestamp() (correctif vingt-cinquième revue statique, blocage 2 — capturé '
  'après TOUS les verrous/validations, y compris la preuve, pas seulement '
  'l''accréditation, pour qu''il reflète fidèlement l''instant où l''insertion est '
  'effectivement validée) — indépendamment de complete_verification_session(), pour '
  'tout chemin d''insertion.';

-- ────────────────────────────────────────────────────────────
-- 4bis-bis. GARDE D'ACCRÉDITATION sur verification_sessions.verifier_user_id
--    — correctif vingt-troisième revue statique (point 2). plan_verification_session()
--    (section 4ter ci-dessous) valide correctement is_authorized_verifier_identity(),
--    mais rien n'empêchait un INSERT/UPDATE DIRECT
--    (admin_manage_verification_sessions, FOR ALL, is_project_admin(),
--    toujours en place) d'assigner un verifier_user_id NON accrédité —
--    démontré par les fixtures elles-mêmes (assignation directe AVANT toute
--    accréditation, chantier de test, corrigé section tests). Placée ICI
--    (après accredited_verifiers/is_authorized_verifier_identity(), et non
--    juste après le trigger d'immutabilité section 3bis) pour ne jamais
--    référencer une fonction pas encore définie dans le script. BEFORE
--    INSERT OR UPDATE (pas seulement UPDATE, contrairement à
--    carbon_guard_verification_session_update()) : une session peut en
--    théorie être créée directement avec verifier_user_id déjà renseigné.
--    NULL reste toujours autorisé (session pas encore assignée).
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_guard_verification_session_verifier_accreditation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Correctif vingt-quatrième revue statique (ajustement) : ne revalider
    -- l'accréditation QUE lorsque verifier_user_id est effectivement
    -- (ré)assigné — à l'INSERT, ou à l'UPDATE seulement si sa valeur change
    -- réellement (IS DISTINCT FROM OLD). Dans sa forme précédente
    -- (vingt-troisième revue), la garde revalidait sur CHAQUE UPDATE, quelle
    -- que soit la colonne modifiée : une révocation ultérieure de
    -- verifier_assigned bloquait alors même une UPDATE anodine (ex.
    -- comments) sur une session historique déjà attestée avec ce
    -- vérificateur — alors que l'accréditation doit être valide au moment
    -- de l'assignation/attestation, pas nécessairement éternellement (voir
    -- is_assigned_verifier()/complete_verification_session()/
    -- carbon_guard_verification_outcome_insert() pour la revalidation
    -- continue côté lecture/attestation, qui reste, elle, systématique).
    IF NEW.verifier_user_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.verifier_user_id IS DISTINCT FROM OLD.verifier_user_id) THEN
        -- Correctif vingt-cinquième revue statique (blocage 1) : verrou
        -- FOR SHARE DIRECT de la ligne accredited_verifiers — même ordre
        -- transactionnel que complete_verification_session()/carbon_guard_
        -- verification_outcome_insert(), pour sérialiser une révocation
        -- CONCURRENTE pendant l'affectation (sans ce verrou, une révocation
        -- committée pendant cette même fenêtre pouvait laisser une session
        -- nouvellement assignée à un vérificateur déjà inactif).
        --
        -- Correctif vingt-sixième revue statique : cette fonction est
        -- désormais SECURITY DEFINER (et non plus SECURITY INVOKER comme en
        -- vingt-cinquième revue). SELECT ... FOR SHARE exige le privilège
        -- UPDATE (pas seulement SELECT) sur la table verrouillée, ET est
        -- soumis aux policies RLS de type UPDATE (pas seulement SELECT) —
        -- accredited_verifiers ne porte qu'une policy SELECT
        -- (accredited_verifiers_admin_select, section 4bis) et authenticated
        -- n'a jamais reçu UPDATE sur cette table (intentionnel : elle ne
        -- doit être modifiable que par le propriétaire/une future RPC
        -- d'administration, jamais en écriture applicative directe). Un
        -- SECURITY INVOKER (vingt-cinquième revue) aurait donc échoué sous
        -- authenticated dès ce PERFORM ... FOR SHARE, AVANT même d'atteindre
        -- le IF NOT FOUND — B24nonies (contre-épreuve sous SET LOCAL ROLE
        -- authenticated) l'aurait révélé à l'exécution réelle. SECURITY
        -- DEFINER fait courir ce verrou avec le privilège du PROPRIÉTAIRE de
        -- la fonction (bypass RLS + UPDATE implicite), même patron que
        -- is_authorized_verifier_identity()/can_assigned_verifier_view_
        -- mrv_project() — sans qu'il soit nécessaire d'accorder UPDATE sur
        -- accredited_verifiers à authenticated, ce qui aurait ouvert la
        -- table à l'écriture applicative directe pour tout autre usage.
        PERFORM 1 FROM public.accredited_verifiers WHERE user_id = NEW.verifier_user_id AND active FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'verification_sessions : verifier_user_id doit référencer une identité de vérificateur accréditée (accredited_verifiers), quel que soit le chemin d''écriture (RPC ou direct).';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_verification_session_verifier_accreditation() IS
  'Garde structurelle (correctif vingt-troisième revue statique, point 2 ; ajustement '
  'vingt-quatrième revue statique ; correctif vingt-cinquième revue statique, blocage 1 ; '
  'correctif vingt-sixième revue statique — SECURITY DEFINER) : tout verifier_user_id '
  'non NULL doit référencer une identité accréditée active (accredited_verifiers, '
  'verrou FOR SHARE — sérialise une révocation concurrente) au moment de son '
  'AFFECTATION (INSERT, ou UPDATE changeant réellement sa valeur) — indépendamment du '
  'chemin d''écriture — ferme le contournement possible via '
  'admin_manage_verification_sessions (FOR ALL) ou tout INSERT/UPDATE direct, que '
  'plan_verification_session() seule ne pouvait pas fermer. SECURITY DEFINER (et non '
  'INVOKER) : SELECT ... FOR SHARE exige le privilège UPDATE et est soumis aux policies '
  'UPDATE, pas seulement SELECT — accredited_verifiers ne porte qu''une policy SELECT et '
  'authenticated n''a jamais reçu UPDATE dessus (intentionnel). Ne revalide PAS à chaque '
  'UPDATE sans rapport (ex. comments) sur une session déjà assignée — la revalidation '
  'continue relève de is_assigned_verifier()/complete_verification_session()/'
  'carbon_guard_verification_outcome_insert().';

CREATE TRIGGER verification_sessions_guard_verifier_accreditation
    BEFORE INSERT OR UPDATE ON public.verification_sessions
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_verification_session_verifier_accreditation();

-- ────────────────────────────────────────────────────────────
-- 4ter. plan_verification_session() — correctif vingtième revue statique
--    (blocage 1). RPC étroite de planification/assignation, remplace la
--    policy RLS UPDATE générale précédemment envisagée (dont la portée
--    colonne par colonne n'est pas contrôlable par une simple policy).
--    Réservée à l'autorité MRV (is_project_admin(), même rôle que
--    admin_manage_verification_sessions déjà en place, PLUS
--    is_platform_superadmin() par cohérence avec le patron déjà établi pour
--    les autres RPC de portée équivalente dans ce chantier). Un vérificateur
--    assigné NE PEUT PAS s'auto-planifier ni se réassigner — seule
--    complete_verification_session() (section 5) lui est réservée, et
--    seulement pour ENREGISTRER un résultat, jamais pour modifier la
--    planification. Bloquée par le trigger de garde structurel (section
--    3bis) dès qu'un résultat existe déjà ou que la session est completed.
--    p_verifier_user_id doit désormais référencer une identité de
--    vérificateur ACCRÉDITÉE (is_authorized_verifier_identity(), correctif
--    vingt-deuxième revue statique, point 2) — plus seulement un profil
--    existant.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.plan_verification_session(
    p_verification_session_id UUID,
    p_reporting_period_start DATE,
    p_reporting_period_end DATE,
    p_verifier_user_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    IF NOT (public.is_project_admin() OR public.is_platform_superadmin()) THEN
        RAISE EXCEPTION 'Accès refusé : seule l''autorité MRV (admin de projet ou super-administrateur) peut planifier une session de vérification.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.verification_sessions WHERE id = p_verification_session_id) THEN
        RAISE EXCEPTION 'Session de vérification introuvable.';
    END IF;

    IF p_reporting_period_start IS NOT NULL AND p_reporting_period_end IS NOT NULL
       AND p_reporting_period_end < p_reporting_period_start THEN
        RAISE EXCEPTION 'reporting_period_end ne peut pas être antérieure à reporting_period_start.';
    END IF;

    IF p_verifier_user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_verifier_user_id) THEN
        RAISE EXCEPTION 'p_verifier_user_id ne correspond à aucun profil existant.';
    END IF;

    -- Correctif vingt-deuxième revue statique (point 2) : l'existence d'un
    -- profil ne suffit pas — p_verifier_user_id doit être une identité de
    -- vérificateur ACCRÉDITÉE (accredited_verifiers). Rejette aussi bien un
    -- profil ordinaire (client/outsider) que l'auto-assignation d'un
    -- super-administrateur (qui n'est pas lui-même accrédité comme
    -- vérificateur, sauf inscription explicite au registre).
    IF p_verifier_user_id IS NOT NULL AND NOT public.is_authorized_verifier_identity(p_verifier_user_id) THEN
        RAISE EXCEPTION 'p_verifier_user_id ne correspond à aucune identité de vérificateur accréditée (accredited_verifiers).';
    END IF;

    -- Le trigger de garde structurel (verification_sessions_guard_update,
    -- section 3bis) rejette lui-même cette UPDATE si un résultat existe déjà
    -- pour cette session ou si status = 'completed' — pas de vérification
    -- redondante ici, le filet structurel fait foi.
    UPDATE public.verification_sessions
    SET reporting_period_start = p_reporting_period_start,
        reporting_period_end = p_reporting_period_end,
        verifier_user_id = p_verifier_user_id
    WHERE id = p_verification_session_id;

    RETURN p_verification_session_id;
END;
$$;

COMMENT ON FUNCTION public.plan_verification_session(UUID, DATE, DATE, UUID) IS
  'Planifie/assigne une session de vérification (période, vérificateur) — '
  'réservée à is_project_admin() OU is_platform_superadmin() (correctif '
  'vingtième revue statique, remplace la policy RLS UPDATE générale '
  'supprimée). Bloquée par le trigger de garde structurel dès qu''un résultat '
  'existe ou que la session est completed. p_verifier_user_id doit référencer '
  'une identité accréditée (accredited_verifiers, correctif vingt-deuxième '
  'revue statique).';

REVOKE ALL ON FUNCTION public.plan_verification_session(UUID, DATE, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plan_verification_session(UUID, DATE, DATE, UUID) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 4quater. HELPERS SECURITY DEFINER anti-cycle RLS — correctif
--    vingt-troisième revue statique (point 1). verifier_read_projects (sur
--    projects) interroge verification_sessions, TANDIS QUE
--    client_read_verification_sessions (sur verification_sessions)
--    interroge projects — un EXISTS(...) INLINE dans le USING d'une policy
--    déclenche l'évaluation RLS complète de la table interrogée (sauf
--    bypass), créant un cycle projects -> verification_sessions -> projects
--    (et même risque pour project_activity_logs/evidence_files, dont les
--    policies verifier_read_* interrogent elles aussi verification_sessions,
--    qui elle-même interroge projects via client_read_verification_sessions).
--    Fonctions SECURITY DEFINER : leurs requêtes internes s'exécutent avec
--    le privilège du PROPRIÉTAIRE de la fonction (le rôle appliquant cette
--    migration, propriétaire des tables), qui bypasse RLS par défaut — même
--    patron que TOUTES les autres fonctions d'autorisation de ce chantier
--    (is_assigned_verifier(), is_project_client(), etc.), jamais un EXISTS
--    inline référençant directement une autre table protégée par RLS dans
--    un USING.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.can_assigned_verifier_view_mrv_project(p_project_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.verification_sessions vs
        WHERE vs.project_id = p_project_id AND vs.verifier_user_id = auth.uid()
          -- Correctif vingt-quatrième revue statique (blocage 1) :
          -- is_assigned_verifier() exige déjà une accréditation active
          -- (vingt-troisième revue, point 3) — ce helper devait suivre la
          -- même règle, sinon un vérificateur révoqué perd sessions/
          -- outcomes/events mais conserve projects/activity_logs/
          -- evidence_files.
          AND public.is_authorized_verifier_identity(vs.verifier_user_id)
    )
$$;

COMMENT ON FUNCTION public.can_assigned_verifier_view_mrv_project(UUID) IS
  'Vérifie qu''un vérificateur est affecté à AU MOINS UNE session du projet donné '
  '(verification_sessions.verifier_user_id = auth.uid()) ET reste ACCRÉDITÉ ACTIF '
  '(is_authorized_verifier_identity(), correctif vingt-quatrième revue statique, point 1) '
  '— SECURITY DEFINER pour éviter tout cycle RLS avec verification_sessions/projects '
  '(correctif vingt-troisième revue statique, point 1). Utilisée par '
  'verifier_read_projects/verifier_read_activity_logs/verifier_read_evidence_files.';

REVOKE ALL ON FUNCTION public.can_assigned_verifier_view_mrv_project(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_assigned_verifier_view_mrv_project(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_client_view_verification_session(p_verification_session_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.verification_sessions vs
        JOIN public.projects p ON p.id = vs.project_id
        WHERE vs.id = p_verification_session_id AND p.client_id = auth.uid()
    )
$$;

COMMENT ON FUNCTION public.can_client_view_verification_session(UUID) IS
  'Vérifie que le client courant est propriétaire (projects.client_id = auth.uid()) du '
  'projet lié à cette session — SECURITY DEFINER pour éviter tout cycle RLS avec '
  'projects/verification_sessions (correctif vingt-troisième revue statique, point 1). '
  'Utilisée par client_read_verification_sessions.';

REVOKE ALL ON FUNCTION public.can_client_view_verification_session(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_client_view_verification_session(UUID) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 4quinquies. DURCISSEMENT DES POLICIES SELECT PRÉEXISTANTES de verification_sessions
--    — correctif vingt-et-unième revue statique (blocage 2). Prévalidées
--    section 0 via pg_policies (schéma réel, pas une hypothèse).
--    verifier_read_verification_sessions (is_verifier(), générique — tout
--    utilisateur au rôle verifier voyait TOUTES les sessions) et
--    client_read_verification_sessions (is_project_client(), même défaut)
--    remplacées par des relations scopées à la session/au projet, cohérent
--    avec le correctif déjà appliqué à can_view_verification_outcome()
--    (vingtième revue statique, blocage 2). is_project_admin() n'est PAS
--    touché : portée globale intentionnelle, cohérente avec
--    admin_manage_verification_sessions (déjà FOR ALL, inchangée).
--    client_read_verification_sessions passe par can_client_view_verification_session()
--    (correctif vingt-troisième revue statique, point 1) plutôt qu'un
--    EXISTS inline — voir section 4quater.
-- ────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS verifier_read_verification_sessions ON public.verification_sessions;
CREATE POLICY verifier_read_verification_sessions ON public.verification_sessions
    FOR SELECT
    USING (public.is_assigned_verifier(id));

DROP POLICY IF EXISTS client_read_verification_sessions ON public.verification_sessions;
CREATE POLICY client_read_verification_sessions ON public.verification_sessions
    FOR SELECT
    USING (public.can_client_view_verification_session(id));

-- ────────────────────────────────────────────────────────────
-- 4sexies. DURCISSEMENT DES POLICIES verifier_read_* de projects/
--    project_activity_logs/evidence_files — correctif vingt-deuxième revue
--    statique (point 6), revu vingt-troisième revue statique (point 1) pour
--    passer par can_assigned_verifier_view_mrv_project() (voir section
--    4quater) plutôt qu'un EXISTS inline. Même défaut initial (avant
--    correction vingt-deuxième revue) : ces trois policies préexistantes
--    n'utilisaient QUE is_verifier() (rôle JWT générique), donnant à TOUT
--    utilisateur portant ce rôle un accès SELECT à TOUS les projets/
--    journaux d'activité/preuves, sans aucune portée par affectation réelle.
-- ────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS verifier_read_projects ON public.projects;
CREATE POLICY verifier_read_projects ON public.projects
    FOR SELECT TO authenticated
    USING (public.can_assigned_verifier_view_mrv_project(id));

DROP POLICY IF EXISTS verifier_read_activity_logs ON public.project_activity_logs;
CREATE POLICY verifier_read_activity_logs ON public.project_activity_logs
    FOR SELECT TO authenticated
    USING (public.can_assigned_verifier_view_mrv_project(project_id));

DROP POLICY IF EXISTS verifier_read_evidence_files ON public.evidence_files;
CREATE POLICY verifier_read_evidence_files ON public.evidence_files
    FOR SELECT TO authenticated
    USING (public.can_assigned_verifier_view_mrv_project(project_id));

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
    -- (§10, correctif vingt-et-unième revue statique blocage 1) Recherche,
    -- autorisation et verrouillage FUSIONNÉS en un seul SELECT : la version
    -- précédente verrouillait la ligne (FOR UPDATE) AVANT de vérifier que
    -- l'appelant en était le vérificateur assigné — un appelant NON autorisé
    -- pouvait donc acquérir un verrou sur une session à laquelle il n'a
    -- aucun droit, et les deux échecs (session inexistante / accès refusé)
    -- étaient distinguables par message, permettant l'énumération des
    -- identifiants de session réels. Le filtre `verifier_user_id = auth.uid()`
    -- fait maintenant partie du WHERE lui-même : aucune ligne trouvée
    -- signifie indifféremment « session introuvable » OU « appelant non
    -- autorisé » — message unique, générique, dans les deux cas. Remplace
    -- l'ancien appel séparé à is_assigned_verifier() (devenu redondant : la
    -- correspondance est désormais garantie par le WHERE lui-même).
    SELECT project_id, reporting_period_start, reporting_period_end, verifier_user_id, status
    INTO v_project_id, v_reporting_start, v_reporting_end, v_verifier_user_id, v_session_status
    FROM public.verification_sessions
    WHERE id = p_verification_session_id
      AND verifier_user_id = auth.uid()
    FOR UPDATE;

    IF v_project_id IS NULL THEN
        RAISE EXCEPTION 'Session introuvable ou accès refusé.';
    END IF;

    -- Correctif vingt-troisième revue statique (point 3) : revalider
    -- l'accréditation ACTIVE à la CLÔTURE, pas seulement au moment de
    -- l'assignation (plan_verification_session()/le trigger d'accréditation
    -- ne valident qu'à l'écriture de verifier_user_id — un vérificateur
    -- assigné puis révoqué ENTRE-TEMPS pouvait donc encore attester tant que
    -- verifier_user_id = auth.uid() restait vrai). FOR SHARE sur la ligne
    -- accredited_verifiers : sérialise une révocation CONCURRENTE (si un
    -- admin révoque dans une transaction concurrente, notre FOR SHARE
    -- attend son COMMIT/ROLLBACK avant de lire, jamais un état à moitié
    -- appliqué). L'appelant est ici déjà authentifié et déjà reconnu comme
    -- le vérificateur assigné (WHERE ci-dessus) — un message explicite ne
    -- crée aucune nouvelle surface d'énumération (contrairement au message
    -- générique de la recherche/autorisation initiale).
    PERFORM 1 FROM public.accredited_verifiers WHERE user_id = v_actor AND active FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Accréditation de vérificateur révoquée ou introuvable : impossible d''enregistrer un résultat de vérification.';
    END IF;

    IF v_session_status = 'planned' THEN
        RAISE EXCEPTION 'Session non prête : le statut doit être in_progress ou completed (planned rencontré) — la vérification de terrain doit avoir débuté.';
    END IF;

    IF v_reporting_start IS NULL OR v_reporting_end IS NULL THEN
        RAISE EXCEPTION 'Session non prête : reporting_period_start/reporting_period_end doivent être renseignés avant d''enregistrer un résultat.';
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
    -- présume pas d'un comportement différent). Correctif vingtième revue
    -- statique (durcissement) : SUM(...::numeric) — ghg_reduction_kgco2e est
    -- FLOAT8 en base ; sommer en numeric dès l'agrégation évite de propager
    -- l'imprécision binaire d'une somme FLOAT8 avant la conversion finale,
    -- pour une quantité qui sera auditée.
    SELECT COALESCE(SUM(ghg_reduction_kgco2e::numeric), 0) INTO v_calculated_kg
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

    -- (§12, blocage 5, correctif vingt-et-unième revue statique) Preuve de
    -- vérification obligatoire (colonne NOT NULL, section 2), désormais
    -- scopée au projet MRV réel via evidence_files.project_id (PAS documents
    -- — voir en-tête). Revalidée ICI pour un message d'erreur clair AVANT
    -- tentative d'INSERT ; le trigger BEFORE INSERT (section 3ter) revalide
    -- structurellement les mêmes trois conditions pour tout chemin
    -- d'insertion, y compris un INSERT direct hors RPC.
    IF p_verification_report_document_id IS NULL THEN
        RAISE EXCEPTION 'verification_report_document_id est obligatoire : un résultat de vérification sans preuve ne peut pas être enregistré.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.evidence_files WHERE id = p_verification_report_document_id) THEN
        RAISE EXCEPTION 'p_verification_report_document_id ne correspond à aucune preuve (evidence_files) existante.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.evidence_files WHERE id = p_verification_report_document_id AND type = 'verification_report') THEN
        RAISE EXCEPTION 'La preuve référencée doit porter le type ''verification_report''.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.evidence_files WHERE id = p_verification_report_document_id AND project_id = v_project_id) THEN
        RAISE EXCEPTION 'La preuve référencée doit appartenir au même projet MRV que la session (project_id).';
    END IF;
    -- Correctif vingt-troisième revue statique (point 4) : file_hash NOT
    -- NULL/non vide — sans ce garde-fou, une evidence_files pouvait servir
    -- de preuve avec file_hash resté NULL depuis sa création, puis le
    -- trigger de gel (evidence_files_guard_update) interdisait ENSUITE de
    -- jamais le renseigner une fois référencée : le mécanisme d'intégrité
    -- devenait alors définitivement vide pour cette preuve.
    IF NOT EXISTS (SELECT 1 FROM public.evidence_files WHERE id = p_verification_report_document_id AND file_hash IS NOT NULL AND btrim(file_hash) <> '') THEN
        RAISE EXCEPTION 'La preuve référencée doit porter un file_hash renseigné (intégrité) avant de pouvoir servir de verification_report.';
    END IF;

    -- (§3 point 2/3, §12, correctif vingtième revue statique blocage 3)
    -- adjustment_reason : TOUJOURS obligatoire en cas de supersession
    -- (résultat actif déjà existant) ; sinon obligatoire au premier résultat
    -- selon deux cas distincts, pour couvrir le cas calculé = 0 (aucune
    -- activité journalisée sur la période) qui échappait entièrement au seuil
    -- avant correction : (a) calculé = 0 et vérifié <> 0 — toute valeur
    -- vérifiée non nulle sans aucune activité calculée exige une
    -- justification ; (b) calculé <> 0 — divergence de plus de 1 % de
    -- abs(calculé) (seuil documenté ici, cf. §3 « seuil à définir, ex. 1% »
    -- — 1% retenu comme valeur par défaut explicite de cette migration, à
    -- reconfirmer en revue si un autre seuil est souhaité ; abs() protège
    -- contre une somme calculée négative, cas non exclu par le schéma de
    -- project_activity_logs).
    IF v_active_outcome_id IS NOT NULL THEN
        IF p_adjustment_reason IS NULL OR btrim(p_adjustment_reason) = '' THEN
            RAISE EXCEPTION 'adjustment_reason est obligatoire pour corriger un résultat déjà actif (supersession).';
        END IF;
    ELSIF v_calculated_reduction_tco2e = 0 AND p_verified_reduction_tco2e <> 0 THEN
        IF p_adjustment_reason IS NULL OR btrim(p_adjustment_reason) = '' THEN
            RAISE EXCEPTION 'adjustment_reason est obligatoire : aucune activité calculée (0 tCO2e) sur la période alors que verified_reduction_tco2e est non nul (%).', p_verified_reduction_tco2e;
        END IF;
    ELSIF v_calculated_reduction_tco2e <> 0
          AND abs(p_verified_reduction_tco2e - v_calculated_reduction_tco2e) > (abs(v_calculated_reduction_tco2e) * 0.01) THEN
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
        verification_report_document_id, verified_by, adjustment_reason
    ) VALUES (
        p_verification_session_id, 'active', v_active_outcome_id,
        v_calculated_reduction_tco2e, p_verified_reduction_tco2e, p_eligible_tco2e,
        p_verification_report_document_id, v_actor, p_adjustment_reason
    ) RETURNING id INTO v_new_outcome_id;

    -- Transition de la session vers 'completed', la première fois seulement
    -- (idempotent pour une supersession ultérieure, où le statut est déjà
    -- 'completed') — c'est cette RPC-ci qui referme effectivement le statut
    -- de la session, cohérent avec son nom ; plan_verification_session()
    -- (section 4bis) ne fait que planifier/assigner, jamais compléter.
    -- Cette UPDATE ne touche QUE status : le trigger de garde structurel
    -- (verification_sessions_guard_update, section 3bis) l'autorise car
    -- OLD.status n'est pas déjà 'completed' à cet instant, et
    -- project_id/période/vérificateur restent inchangés par cette UPDATE.
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
  'Réservée à is_assigned_verifier(p_verification_session_id) SEUL (dérogation superadmin '
  'retirée, correctif vingtième revue statique) — le super-administrateur peut planifier via '
  'plan_verification_session() mais ne peut plus attester lui-même. Transitionne la session '
  'vers ''completed'' au premier appel. verification_report_document_id obligatoire, validé '
  '(evidence_files, type=''verification_report'', project_id = celui de la session). '
  'adjustment_reason obligatoire pour toute supersession, ou au premier résultat si calculé=0 '
  'et vérifié<>0, ou si divergence > 1% de abs(calculé). Recherche+autorisation+verrou '
  'fusionnés en un seul SELECT (correctif vingt-et-unième revue statique, blocage 1).';

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

-- Correctif vingtième revue statique (blocage 2) : is_project_client() est un
-- prédicat de RÔLE générique (auth.jwt()->'app_metadata'->>'role', voir
-- 20260710999100_reapply_mrv_and_aggregators.sql) SANS aucune portée par
-- projet — utilisé seul, il donnait accès à TOUS les verification_outcomes à
-- n'importe quel utilisateur portant ce rôle, quel que soit le projet
-- réellement associé à son compte. Remplacé par la relation RÉELLE
-- projects.client_id = auth.uid() (jointure verification_sessions ->
-- projects) — LA MÊME relation que la policy client_read_own_projects déjà
-- en place sur projects (`client_id = auth.uid() OR is_project_client()`,
-- confirmée par lecture directe du fichier ci-dessus ; NOTE : cette policy
-- préexistante conserve elle-même le OR is_project_client() générique — un
-- défaut identique mais PRÉEXISTANT, hors périmètre de cette migration, sur
-- une table que 05 ne modifie pas). is_project_admin() reste utilisé SEUL :
-- portée globale INTENTIONNELLE et cohérente avec
-- admin_manage_verification_sessions (déjà FOR ALL, sans filtre par projet,
-- inchangée) — l'audience admin est structurellement globale par convention
-- déjà établie dans le chantier MRV, PAS le même défaut que
-- is_project_client().
CREATE OR REPLACE FUNCTION public.can_view_verification_outcome(p_verification_session_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT public.is_platform_superadmin()
        OR public.is_project_admin()
        OR public.is_assigned_verifier(p_verification_session_id)
        OR EXISTS (
            SELECT 1
            FROM public.verification_sessions vs
            JOIN public.projects p ON p.id = vs.project_id
            WHERE vs.id = p_verification_session_id
              AND p.client_id = auth.uid()
        )
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
-- -- Correctif vingt-deuxième revue statique — objets à défaire EN PREMIER
-- -- (dépendances : les policies/triggers/fonctions ci-dessous référencent
-- -- des tables/fonctions supprimées plus bas).
-- DROP POLICY IF EXISTS verifier_read_evidence_files ON public.evidence_files;
-- CREATE POLICY verifier_read_evidence_files ON public.evidence_files
--     FOR SELECT TO authenticated USING (public.is_verifier());
-- DROP POLICY IF EXISTS verifier_read_activity_logs ON public.project_activity_logs;
-- CREATE POLICY verifier_read_activity_logs ON public.project_activity_logs
--     FOR SELECT TO authenticated USING (public.is_verifier());
-- DROP POLICY IF EXISTS verifier_read_projects ON public.projects;
-- CREATE POLICY verifier_read_projects ON public.projects
--     FOR SELECT TO authenticated USING (public.is_verifier());
-- DROP TRIGGER IF EXISTS evidence_files_guard_update ON public.evidence_files;
-- DROP FUNCTION IF EXISTS public.carbon_guard_evidence_file_update();
-- ALTER TABLE public.evidence_files DROP COLUMN IF EXISTS file_hash;
-- DROP TRIGGER IF EXISTS verification_outcomes_check_session_invariant ON public.verification_outcomes;
-- DROP TRIGGER IF EXISTS verification_sessions_check_outcome_invariant ON public.verification_sessions;
-- DROP FUNCTION IF EXISTS public.carbon_check_verification_session_outcome_invariant();
-- -- Correctif vingt-troisième revue statique.
-- DROP TRIGGER IF EXISTS verification_sessions_guard_verifier_accreditation ON public.verification_sessions;
-- DROP FUNCTION IF EXISTS public.carbon_guard_verification_session_verifier_accreditation();
-- DROP FUNCTION IF EXISTS public.can_assigned_verifier_view_mrv_project(UUID);
-- DROP FUNCTION IF EXISTS public.can_client_view_verification_session(UUID);
-- DROP FUNCTION IF EXISTS public.is_authorized_verifier_identity(UUID);
-- DROP TABLE IF EXISTS public.accredited_verifiers;
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
-- -- verifier_read_verification_sessions/client_read_verification_sessions :
-- -- restaurer les définitions génériques d'origine (chantier MRV) — correctif
-- -- vingt-et-unième revue statique, blocage 2.
-- DROP POLICY IF EXISTS client_read_verification_sessions ON public.verification_sessions;
-- CREATE POLICY client_read_verification_sessions ON public.verification_sessions
--     FOR SELECT TO authenticated USING (public.is_project_client());
-- DROP POLICY IF EXISTS verifier_read_verification_sessions ON public.verification_sessions;
-- CREATE POLICY verifier_read_verification_sessions ON public.verification_sessions
--     FOR SELECT TO authenticated USING (public.is_verifier());
-- DROP FUNCTION IF EXISTS public.plan_verification_session(UUID, DATE, DATE, UUID);
-- DROP FUNCTION IF EXISTS public.is_assigned_verifier(UUID);
-- DROP TRIGGER IF EXISTS verification_sessions_guard_update ON public.verification_sessions;
-- DROP FUNCTION IF EXISTS public.carbon_guard_verification_session_update();
-- DROP TRIGGER IF EXISTS verification_outcomes_reject_delete ON public.verification_outcomes;
-- DROP TRIGGER IF EXISTS verification_outcomes_guard_update ON public.verification_outcomes;
-- DROP FUNCTION IF EXISTS public.carbon_guard_verification_outcome_update();
-- DROP TRIGGER IF EXISTS verification_outcomes_guard_insert ON public.verification_outcomes;
-- DROP FUNCTION IF EXISTS public.carbon_guard_verification_outcome_insert();
-- ALTER TABLE public.verification_outcomes DROP CONSTRAINT IF EXISTS verification_outcomes_supersedes_same_session;
-- ALTER TABLE public.verification_outcomes DROP CONSTRAINT IF EXISTS verification_outcomes_id_session_unique;
-- ALTER TABLE public.verification_outcomes DROP CONSTRAINT IF EXISTS verification_outcomes_no_self_supersede;
-- DROP TABLE IF EXISTS public.verification_outcomes;
-- ALTER TABLE public.verification_sessions DROP CONSTRAINT IF EXISTS verification_sessions_no_overlapping_completed_periods;
-- ALTER TABLE public.verification_sessions DROP CONSTRAINT IF EXISTS verification_sessions_completed_requires_period_and_verifier;
-- ALTER TABLE public.verification_sessions DROP COLUMN IF EXISTS verifier_user_id;
-- ALTER TABLE public.verification_sessions DROP COLUMN IF EXISTS reporting_period_end;
-- ALTER TABLE public.verification_sessions DROP COLUMN IF EXISTS reporting_period_start;
-- ============================================================
