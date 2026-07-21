-- ============================================================
-- Migration 07 — credit_issuances + credit_issuance_sources
-- ============================================================
--
-- STATUT : PROPOSITION SOUMISE POUR REVUE — NON EXÉCUTÉE.
-- Conception validée : Tranche0-Carbone-Architecture.md §15 (proposition
-- initiale + trois revues successives). Ce fichier intègre la quatrième
-- revue statique (8 corrections bloquantes), la cinquième (6 corrections +
-- 1 recommandation), la sixième (7 corrections — schémas project_participants/
-- operational_units/projects/documents désormais confirmés, invariant
-- « au moins une source » garanti structurellement, machine à états
-- verrouillée à l'INSERT et sur les premiers renseignements de champs
-- réglementaires, régime opérateur actif aligné pour mark_credit_issuance_eligible()/
-- void_credit_issuance() y compris pour le super-admin), la septième (4
-- corrections + 3 durcissements — registry_issued_at officiel du registre,
-- invariants de complétude par état cible, RLS opérateur historique,
-- catalogue event_type comparé en ensemble exact), la huitième (3
-- corrections — participation CCF effective (status='active') exigée,
-- verrous partagés sur les lignes d'autorité (opérateur actif, adhésion,
-- mandat) pour éliminer les fenêtres de course de create/submit/mark_eligible/
-- void, verrou FOR UPDATE sur verification_sessions dans le trigger de
-- capacité concurrente) et la neuvième (3 corrections — submit_credit_issuance()
-- revalide désormais check 8 (participation projet) par source, sous un
-- verrou sur la ligne project_participants effective ; carbon_validate_credit_issuance_source()
-- prend les mêmes verrous FOR SHARE que create_credit_issuance(), garantie
-- structurelle indépendante du chemin RPC ; le constraint trigger de
-- capacité rejette l'absence d'outcome actif pour une session et, à
-- l'INSERT uniquement, exige que l'outcome référencé soit précisément
-- l'outcome actif de sa session — plus deux durcissements,
-- credit_issuances.id ajouté aux colonnes immuables et A16 rendu ciblé
-- table par table) et la dixième (4 corrections — carbon_credit_issuances_before_insert()
-- exige désormais que operator_organization_id soit l'opérateur METALTRACE
-- actif (verrou FOR SHARE) ; nouveau trigger sur platform_operators
-- interdisant la révocation/transfert de l'opérateur actif tant qu'il
-- détient une émission internal/eligible (décision d'architecture, voir
-- Tranche0-Carbone-Architecture.md §15.10.d) ; verrouillage + validation de
-- l'autorité « organisation source » centralisés dans le nouveau helper
-- carbon_lock_and_validate_source_organization() (branches CCF ET MRV),
-- utilisé identiquement par create_credit_issuance(), submit_credit_issuance()
-- et carbon_validate_credit_issuance_source() ; rollback documenté corrigé
-- pour ne plus supprimer carbon_capacity_consumed_for_session() — restaurée
-- au stub contractuel de la migration 05 — et pour nettoyer explicitement
-- les fonctions de trigger laissées orphelines par le DROP TABLE) et la
-- onzième (1 correction bloquante côté migration — les 7 RPC d'émission
-- renseignent désormais organization_id (= operator_organization_id figé,
-- décision retenue), aggregator_id et verification_session_id sur leur
-- INSERT carbon_business_events, dimensions d'autorisation exploitées par
-- can_view_carbon_event() [§10bis] pour la visibilité des admins de
-- regroupement et, à partir de la migration 05, du vérificateur assigné ;
-- les deux autres corrections de cette revue — ordre/résorption des
-- fixtures de test avant le scénario de transfert d'opérateur, et périodes
-- non chevauchantes des verification_sessions de test — sont uniquement
-- côté script de tests) et la douzième (2 corrections bloquantes côté
-- migration — fuite RLS corrigée : credit_issuance_sources_select
-- réutilisait can_view_credit_issuance(id), qui rend TRUE dès qu'un
-- appelant est membre de N'IMPORTE QUELLE organisation source d'une
-- émission, laissant lire TOUTES les lignes credit_issuance_sources de
-- cette émission plutôt que les seules siennes ; corrigé par le nouveau
-- helper ligne-par-ligne can_view_credit_issuance_source(credit_issuance_id,
-- organization_id), qui restreint une organisation source ordinaire à sa
-- propre ligne tout en conservant la visibilité complète pour les rôles
-- privilégiés (super-admin, opérateur figé, aggregator admin, vérificateur
-- assigné) ; rollback réordonné — les policies dépendant de
-- can_view_credit_issuance()/can_view_credit_issuance_source() sont
-- désormais retirées explicitement AVANT le DROP de ces fonctions, évitant
-- l'échec « cannot drop function ... because other objects depend on it »
-- de l'ordre précédent. §15 (Tranche0-Carbone-Architecture.md, PAS
-- ADR-MVP.md) réconcilié avec le SQL réel sur la visibilité historique de
-- l'opérateur figé : is_organization_member(operator_organization_id),
-- pas is_platform_operator_actor()), la treizième (1 correction bloquante
-- côté migration — can_view_credit_issuance_source() restait un oracle
-- d'existence en appel direct hors policy RLS : la branche « organisation
-- ordinaire » exige désormais une vraie ligne credit_issuance_sources
-- reliant les deux paramètres, plus seulement is_organization_member() ;
-- côté script de tests, A16 corrigé (`\b` -> `\y`, frontière de mot réelle
-- en regex PostgreSQL ARE) et gate final durci avec count(DISTINCT
-- section) = N en plus de count(*) = N) et la quatorzième (1 correction
-- bloquante côté migration — carbon_credit_issuances_before_update()
-- vérifie désormais lui-même que external_rejection_document_id/
-- external_cancellation_document_id appartient à l'organisation opératrice
-- figée de l'émission, défense structurelle jusqu'ici garantie seulement
-- par record_externally_rejected()/record_external_cancellation(), jamais
-- par le trigger BEFORE UPDATE qu'un chemin privilégié direct peut
-- atteindre en contournant ces deux RPC ; côté script de tests, remise en
-- état de fixture du mandat Source A après B12bis (aucun nouveau mandat
-- n'était accordé après sa révocation, faisant échouer tous les tests
-- suivants dépendant de l'adhésion ...1401) et ajout de B27bis/B28bis), la
-- quinzième (interdiction structurelle de NaN sur quantity_tco2e/
-- contributed_tco2e — NUMERIC accepte NaN indépendamment de la précision
-- déclarée, traité par PostgreSQL comme supérieur à toute valeur ordinaire,
-- donc un CHECK `> 0` seul ne l'exclut pas ; CHECK de table durcis, rejets
-- explicites ajoutés dans create_credit_issuance() et le constraint trigger
-- de capacité, tests B22ter/B22quater) et la seizième (canonicalisation de
-- l'unicité (registry_name, registry_reference) — index refait sur
-- lower(btrim(registry_name))/btrim(registry_reference), RPC durcies pour
-- stocker la valeur normalisée, test B12terbis ; created_at daté via
-- v_created_at := clock_timestamp() capturé explicitement dans
-- create_credit_issuance() plutôt que le DEFAULT now() des tables, qui
-- pouvait dater une émission avant même que l'autorité l'ayant permise ne
-- soit devenue valide dans une transaction longue — DEFAULT des deux tables
-- également changé vers clock_timestamp() comme filet pour un INSERT direct).
-- Détail de chaque correction documenté au fil du fichier, marqué par son
-- numéro de revue.
-- Changelog complet de la quatrième revue (base) :
--   1. RLS : suppression des sous-requêtes croisées credit_issuances ↔
--      credit_issuance_sources (récursion RLS) — centralisées dans un
--      helper unique can_view_credit_issuance(uuid) (section 8).
--   2. carbon_business_events : colonne réelle `payload` (pas `event_data`,
--      corrigé dans les 7 RPC) ; catalogue event_type augmenté de 35 à 37
--      valeurs (section 0bis) — ajoute uniquement credit_issuance_marked_eligible
--      et credit_issuance_externally_rejected, les autres événements
--      d'émission et verification_outcome_recorded/superseded existent déjà.
--   3. Concurrence : create_credit_issuance() et submit_credit_issuance()
--      verrouillent désormais verification_sessions AVANT de lire/valider
--      outcome.status et eligible_tco2e (élimine la fenêtre de course).
--   4. Dépendance 05→07 : cette migration NE remplace PLUS
--      complete_verification_session() (qui n'existe pas encore, 05 non
--      rédigée) — voir section 7 (note, aucun SQL) pour l'exigence
--      correspondante à porter dans la conception de la migration 05.
--   5. Sécurité : EXECUTE retiré à authenticated sur les deux helpers
--      internes carbon_capacity_consumed_for_session()/
--      carbon_is_source_organization_valid() ; validation d'existence des
--      documents de preuve (rejet/annulation) ; unicité de
--      (registry_name, registry_reference) une fois renseignés.
--
-- DÉPENDANCES STRUCTURELLES (§14 du document d'architecture) :
--   01 (fondations transverses : carbon_business_events à 35 événements,
--       carbon_rpc_failures)
--   02 (aggregator_memberships)
--   chantier CCF/MRV antérieur (schémas CONFIRMÉS, sixième revue statique,
--       correction 2, contre les migrations réellement appliquées) :
--       project_participants(project_id, organization_id, ...)
--       (20260710005000_ccf_005_ccf_projects_participants.sql — la colonne
--       s'appelle project_id, PAS ccf_project_id comme précédemment
--       supposé) ; operational_units(id, organization_id, ...) SANS aucune
--       colonne de lien direct vers un projet ; projects(id,
--       operational_unit_id, ...) (MRV) qui porte ce lien
--       (20260710999100_reapply_mrv_and_aggregators.sql, même schéma de
--       jointure que credit_lots dans ce même fichier, réutilisé ici).
--   04 (ccf_mrv_project_links) — NON ENCORE RÉDIGÉE, seule table de ce
--       groupe qui reste réellement hypothétique. Bloc de prévalidation
--       ci-dessous empêche l'application tant que 04 ne l'est pas.
--       EXIGENCE EXPLICITE POUR LA CONCEPTION DE 04 (huitième revue
--       statique, condition différée #2) : à sa rédaction, réconcilier le
--       cycle de vie RÉEL de ccf_mrv_project_links avec la jointure faite
--       ici (carbon_is_source_organization_valid(), section 3) — par
--       cohérence directe avec la correction 1 de cette même revue
--       (project_participants.status='active' exigé), la jointure
--       `LEFT JOIN public.ccf_mrv_project_links link ON ...` devra IGNORER
--       tout lien non effectif (annulé, expiré, en brouillon, ou tout
--       équivalent que 04 introduira) — pas seulement son existence brute —
--       sous peine de reproduire exactement le même défaut que celui
--       corrigé ici pour project_participants.
--   05 (verification_outcomes, verification_sessions, is_assigned_verifier(),
--       complete_verification_session()) — NON ENCORE RÉDIGÉE.
--       EXIGENCE EXPLICITE POUR LA CONCEPTION DE 05, ORDRE CHRONOLOGIQUE
--       CORRIGÉ (revue statique 07, point 1 de la cinquième revue) :
--         a. 05 doit D'ABORD créer un STUB
--            public.carbon_capacity_consumed_for_session(uuid) RETURNS NUMERIC
--            renvoyant 0 sans condition (aucune ligne credit_issuances ne
--            peut exister avant que 07 soit appliquée — le stub est donc
--            trivialement correct à ce stade). Cet ordre est une nécessité
--            technique, pas une préférence : PostgreSQL valide l'existence
--            des objets référencés au moment du CREATE FUNCTION
--            (check_function_bodies) — si complete_verification_session()
--            appelle ce helper, le helper doit déjà exister.
--         b. 05 crée ENSUITE complete_verification_session(), qui (i)
--            verrouille verification_sessions FOR UPDATE avant toute
--            lecture/écriture liée à la capacité consommée — même ligne que
--            create_credit_issuance()/submit_credit_issuance() ci-dessous —
--            et (ii) appelle le stub ci-dessus pour l'invariant
--            bidirectionnel eligible_tco2e >= capacité déjà consommée,
--            plutôt que de calculer cette somme en dur dans son propre corps.
--         c. Plus tard, CETTE migration (07) prévalide que le stub existe
--            déjà (section 0 ci-dessous — échoue explicitement si 05 ne l'a
--            pas créé), puis le remplace par son implémentation RÉELLE
--            (CREATE OR REPLACE, section 3, même nom/signature) — SANS
--            jamais toucher au corps de complete_verification_session()
--            lui-même, qui reste entièrement la responsabilité de 05. Le
--            remplacement prend effet immédiatement pour tout appel futur
--            de complete_verification_session(), sans qu'elle ait besoin
--            d'être elle-même modifiée.
--   06 (platform_operators, carbon_commercialization_mandates, is_platform_operator(),
--       is_org_admin(), is_organization_member(), is_platform_superadmin(),
--       is_aggregator_admin()) — APPLIQUÉE EN PRODUCTION le 18 juillet 2026
--       (62/62, voir ADR-MVP.md §14).
--
-- ⚠️ POINT OUVERT, RÉDUIT (sixième revue statique, correction 2) : la
-- fonction carbon_is_source_organization_valid() (section 3) joint
-- project_participants / operational_units / projects (MRV) —
-- SCHÉMAS DÉSORMAIS CONFIRMÉS contre les migrations réellement appliquées
-- (voir liste de dépendances ci-dessus) — et ccf_mrv_project_links, seule
-- table encore hypothétique (migration 04 non rédigée). Le bloc de
-- prévalidation (section 0) vérifie désormais les colonnes exactes de
-- CHACUNE de ces quatre tables, pas seulement leur existence.
--
-- ⚠️ POINT OUVERT #2, RÉSOLU (sixième revue statique, correction 3) :
-- record_externally_rejected()/record_external_cancellation() valident
-- l'appartenance sémantique du document — documents.owner_org_id =
-- operator_organization_id figé de l'émission, PAS seulement son
-- existence — et exécutent cette validation APRÈS la recherche+autorisation
-- de l'émission (jamais avant, pour ne pas créer d'asymétrie d'information
-- vis-à-vis de la discipline D13). Le schéma réel de `documents` est
-- désormais CONFIRMÉ (20260710006000_ccf_006_documents.sql) :
-- owner_org_id UUID NOT NULL est bien la colonne de propriété — ce n'est
-- plus une hypothèse. La prévalidation (section 0) vérifie explicitement
-- owner_org_id/object_type/title par cohérence et défense en profondeur.
--
-- Aucune donnée réelle à migrer (tables nouvelles, création pure).
--
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION — bloque l'exécution si une dépendance manque.
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regclass('public.carbon_business_events') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_business_events introuvable — la migration 01 a-t-elle été appliquée ?';
    END IF;
    IF to_regclass('public.aggregator_memberships') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.aggregator_memberships introuvable — la migration 02 a-t-elle été appliquée ?';
    END IF;
    IF to_regclass('public.carbon_commercialization_mandates') IS NULL
       OR to_regclass('public.platform_operators') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : platform_operators/carbon_commercialization_mandates introuvables — la migration 06 a-t-elle été appliquée ?';
    END IF;
    IF to_regprocedure('public.is_platform_operator(uuid)') IS NULL
       OR to_regprocedure('public.is_org_admin(uuid)') IS NULL
       OR to_regprocedure('public.is_organization_member(uuid)') IS NULL
       OR to_regprocedure('public.is_platform_superadmin()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : une des fonctions d''autorisation transverses (is_platform_operator/is_org_admin/is_organization_member/is_platform_superadmin) est introuvable.';
    END IF;
    IF to_regprocedure('public.is_aggregator_admin(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_aggregator_admin(uuid) introuvable.';
    END IF;
    IF to_regclass('public.ccf_mrv_project_links') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.ccf_mrv_project_links introuvable — la migration 04 a-t-elle été appliquée ?';
    END IF;
    -- (correction 2, sixième revue statique) : ccf_mrv_project_links reste
    -- NON CONFIRMÉ (migration 04 non rédigée) — vérifie les deux colonnes
    -- supposées maintenant que la table existe (échoue avec un message ciblé
    -- si 04 a été rédigée avec un schéma différent de l'hypothèse documentée
    -- dans carbon_is_source_organization_valid()).
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'ccf_mrv_project_links'
          AND column_name = 'ccf_project_id' AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.ccf_mrv_project_links.ccf_project_id (uuid) introuvable — schéma de la migration 04 différent de l''hypothèse documentée dans carbon_is_source_organization_valid().';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'ccf_mrv_project_links'
          AND column_name = 'mrv_project_id' AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.ccf_mrv_project_links.mrv_project_id (uuid) introuvable — schéma de la migration 04 différent de l''hypothèse documentée dans carbon_is_source_organization_valid().';
    END IF;

    IF to_regclass('public.project_participants') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.project_participants introuvable (chantier CCF antérieur).';
    END IF;
    -- (correction 2, sixième revue statique) : colonnes réelles confirmées
    -- (20260710005000_ccf_005_ccf_projects_participants.sql) — la colonne
    -- s'appelle project_id, PAS ccf_project_id (bug corrigé dans la fonction
    -- carbon_is_source_organization_valid() ci-dessous, section 3).
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
          AND column_name = 'organization_id' AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.project_participants.organization_id (uuid) introuvable.';
    END IF;
    -- (correction 1, huitième revue statique) : status est désormais exploité
    -- par carbon_is_source_organization_valid() (exige 'active') — schéma
    -- réel confirmé (20260710005000_ccf_005_ccf_projects_participants.sql) :
    -- colonne text, CHECK invited/active/declined/removed, défaut 'invited'.
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'project_participants'
          AND column_name = 'status' AND data_type = 'text'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.project_participants.status (text) introuvable.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
        WHERE t.relname = 'project_participants' AND c.contype = 'c'
          AND pg_get_constraintdef(c.oid) ILIKE '%''active''%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : aucune contrainte CHECK sur public.project_participants n''admet la valeur ''active'' — hypothèse de statut invalidée.';
    END IF;

    -- operational_units + projects (MRV) — schéma réel confirmé
    -- (20260710999100_reapply_mrv_and_aggregators.sql) : operational_units
    -- N'A PAS de colonne de lien direct vers un projet (ancienne hypothèse
    -- `mrv_project_id` fausse, retirée) — le lien passe par
    -- projects.operational_unit_id.
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
    IF to_regclass('public.projects') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.projects (MRV) introuvable — requis pour la branche MRV de carbon_is_source_organization_valid() (projects.operational_unit_id -> operational_units.organization_id).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'projects'
          AND column_name = 'operational_unit_id' AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.projects.operational_unit_id (uuid) introuvable.';
    END IF;
    IF to_regclass('public.verification_sessions') IS NULL OR to_regclass('public.verification_outcomes') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : verification_sessions/verification_outcomes introuvables — la migration 05 a-t-elle été appliquée ?';
    END IF;
    IF to_regprocedure('public.complete_verification_session(uuid,numeric,numeric,uuid,text)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.complete_verification_session(uuid,numeric,numeric,uuid,text) introuvable avec la signature attendue — la migration 05 a-t-elle été appliquée avec cette signature exacte ?';
    END IF;
    -- (correction 1, cinquième revue statique) : 07 ne CREATE OR REPLACE le
    -- helper de capacité que si 05 en a déjà posé le STUB — jamais en
    -- création ex nihilo. Si ce stub n'existe pas, complete_verification_session()
    -- n'a structurellement pas pu être créée non plus (check_function_bodies
    -- l'aurait empêché), donc ce test est redondant avec le précédent mais
    -- rendu explicite pour documenter l'ordre attendu et échouer avec un
    -- message ciblé si jamais 05 a été appliquée dans une version incomplète.
    IF to_regprocedure('public.carbon_capacity_consumed_for_session(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_capacity_consumed_for_session(uuid) introuvable — la migration 05 doit avoir créé le STUB de ce helper (retournant 0) avant de créer complete_verification_session(), et avant que 07 ne le remplace par son implémentation réelle.';
    END IF;
    IF to_regprocedure('public.is_assigned_verifier(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_assigned_verifier(uuid) introuvable.';
    END IF;
    IF to_regclass('public.documents') IS NULL OR to_regclass('public.profiles') IS NULL
       OR to_regclass('public.organizations') IS NULL OR to_regclass('public.aggregators') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : une table transverse de base (documents/profiles/organizations/aggregators) est introuvable.';
    END IF;
    -- (correction 3, sixième revue statique) : schéma documents CONFIRMÉ
    -- (20260710006000_ccf_006_documents.sql) — owner_org_id est la colonne
    -- réelle de propriété (utilisée par record_externally_rejected()/
    -- record_external_cancellation() ci-dessous, section 6). Vérifié
    -- explicitement malgré la confirmation, par cohérence avec le reste de
    -- cette section (et défense en profondeur si le schéma dérive).
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'documents'
          AND column_name = 'owner_org_id' AND data_type = 'uuid' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.documents.owner_org_id (uuid, NOT NULL) introuvable.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'documents'
          AND column_name = 'object_type' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.documents.object_type (NOT NULL) introuvable.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'documents'
          AND column_name = 'title' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.documents.title (NOT NULL) introuvable.';
    END IF;
    IF to_regclass('public.credit_issuances') IS NOT NULL OR to_regclass('public.credit_issuance_sources') IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : credit_issuances/credit_issuance_sources existent déjà — cette migration ne doit être appliquée qu''une seule fois.';
    END IF;
    RAISE NOTICE 'Prévalidation réussie : toutes les dépendances structurelles sont présentes.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 0bis. CATALOGUE D'ÉVÉNEMENTS — 35 → 37 valeurs (revue statique 07, point 2)
-- ────────────────────────────────────────────────────────────
-- Le catalogue de la migration 01 contient déjà les événements historiques
-- d'émission (credit_issuance_created/submitted/issued/voided/
-- externally_cancelled) et verification_outcome_recorded/superseded.
-- SEULES deux valeurs manquent, ajoutées ici :
-- credit_issuance_marked_eligible, credit_issuance_externally_rejected.
-- Aucun nouvel object_type requis. Idempotent (ne modifie rien si déjà présent).
--
-- (correction 5, septième revue statique) : comparaison à l'ENSEMBLE
-- CANONIQUE EXACT des 35 valeurs attendues (migration 01 : 31 valeurs +
-- migration 06 : 4 valeurs), reconstitué littéralement ci-dessous à partir
-- du texte réel de ces deux fichiers de proposition — pas seulement un
-- comptage ni une vérification de présence des 2 nouvelles valeurs. Une
-- composition différente (une seule valeur manquante, substituée ou en
-- trop) est désormais détectée, alors qu'un simple comptage à 35 ne
-- l'aurait pas révélée.
DO $$
DECLARE
    v_constraint_name TEXT;
    v_old_def         TEXT;
    v_literals        TEXT[];
    v_canonical_35    TEXT[] := ARRAY[
        -- Gouvernance des regroupements (6) — 01_carbon_foundations_events_and_failures.sql lignes 88-93.
        'aggregator_created', 'aggregator_membership_started', 'aggregator_membership_ended',
        'aggregator_admin_appointed', 'aggregator_admin_revoked', 'aggregator_primary_admin_transferred',
        -- Rattachement CCF<->MRV (2) — lignes 95-96.
        'ccf_mrv_link_started', 'ccf_mrv_link_ended',
        -- Vérification (4) — lignes 98-101.
        'verification_session_started', 'verification_session_completed',
        'verification_outcome_recorded', 'verification_outcome_superseded',
        -- Émission réglementaire (5) — lignes 105-109.
        'credit_issuance_created', 'credit_issuance_submitted', 'credit_issuance_issued',
        'credit_issuance_externally_cancelled', 'credit_issuance_voided',
        -- Cycle commercial des lots (5) — lignes 111-115.
        'credit_lot_issued', 'credit_lot_reserved', 'credit_lot_sold', 'credit_lot_retired', 'credit_lot_voided',
        -- Vente / modèle financier (9) — lignes 117-125.
        'credit_sale_created', 'credit_sale_cost_recorded', 'credit_sale_confirmed', 'credit_sale_cancelled',
        'credit_sale_settled', 'credit_sale_adjustment_recorded', 'credit_sale_allocation_recorded',
        'credit_sale_allocation_approved', 'credit_sale_allocation_paid',
        -- Ajoutées par 06_carbon_operator_and_mandates.sql lignes 394-397 (31 -> 35).
        'platform_operator_designated', 'platform_operator_revoked',
        'carbon_commercialization_mandate_granted', 'carbon_commercialization_mandate_revoked'
    ];
    v_canonical_37    TEXT[];
    v_sorted_literals TEXT[];
    v_sorted_35       TEXT[];
    v_sorted_37       TEXT[];
    v_new_def         TEXT;
    v_new_body        TEXT;
    v_check_def       TEXT;
BEGIN
    IF array_length(v_canonical_35, 1) <> 35 THEN
        RAISE EXCEPTION 'Erreur interne de la migration : le tableau canonique codé en dur ne contient pas exactement 35 valeurs (%) — vérifier le corps de cette migration.', array_length(v_canonical_35, 1);
    END IF;
    v_canonical_37 := v_canonical_35 || ARRAY['credit_issuance_marked_eligible', 'credit_issuance_externally_rejected'];

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

    -- extraction EXACTE de chaque littéral TEXT présent dans la définition
    -- existante (aucune supposition sur le format global du tableau —
    -- uniquement sur la syntaxe standard d'un littéral TEXT quoté).
    SELECT array_agg(m[1]) INTO v_literals
    FROM regexp_matches(v_old_def, '''((?:[^'']|'''''')*)''', 'g') AS m;

    -- comparaison par ENSEMBLE (tri, ordre indifférent — la contrainte
    -- réelle peut lister les valeurs dans un ordre différent du fichier
    -- source) mais composition strictement identique, pas seulement le
    -- cardinal.
    SELECT array_agg(x ORDER BY x) INTO v_sorted_literals FROM unnest(v_literals) x;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_35 FROM unnest(v_canonical_35) x;
    SELECT array_agg(x ORDER BY x) INTO v_sorted_37 FROM unnest(v_canonical_37) x;

    IF v_sorted_literals = v_sorted_37 THEN
        RAISE NOTICE 'Catalogue event_type déjà à jour : composition IDENTIQUE à l''ensemble canonique des 37 valeurs attendues — aucune modification.';
    ELSIF v_sorted_literals = v_sorted_35 THEN
        -- reconstruction EXPLICITE à partir du seul ensemble canonique
        -- (v_canonical_37), pas des littéraux extraits — élimine tout
        -- risque de propager une valeur mal orthographiée qui aurait
        -- accidentellement le même cardinal.
        SELECT string_agg(quote_literal(lit) || '::text', ', ')
        INTO v_new_body
        FROM unnest(v_canonical_37) AS lit;

        v_new_def := format('CHECK (event_type = ANY (ARRAY[%s]))', v_new_body);

        EXECUTE format('ALTER TABLE public.carbon_business_events DROP CONSTRAINT %I', v_constraint_name);
        EXECUTE format('ALTER TABLE public.carbon_business_events ADD CONSTRAINT %I %s', v_constraint_name, v_new_def);

        SELECT pg_get_constraintdef(c.oid) INTO v_check_def
        FROM pg_constraint c
        WHERE c.conname = v_constraint_name AND c.conrelid = 'public.carbon_business_events'::regclass;

        SELECT array_agg(m[1]) INTO v_literals
        FROM regexp_matches(v_check_def, '''((?:[^'']|'''''')*)''', 'g') AS m;
        SELECT array_agg(x ORDER BY x) INTO v_sorted_literals FROM unnest(v_literals) x;

        IF v_sorted_literals IS DISTINCT FROM v_sorted_37 THEN
            RAISE EXCEPTION 'Post-vérification échouée : la contrainte % reconstruite ne correspond pas EXACTEMENT à l''ensemble canonique des 37 valeurs attendues — reconciliation manuelle requise.', v_constraint_name;
        END IF;

        RAISE NOTICE 'Contrainte % reconstruite explicitement (35→37), composition vérifiée EXACTEMENT contre l''ensemble canonique (migrations 01+06+2 nouvelles).', v_constraint_name;
    ELSE
        RAISE EXCEPTION 'Prévalidation échouée : le catalogue event_type ne correspond EXACTEMENT ni à l''ensemble canonique des 35 valeurs attendues (migrations 01+06), ni à celui des 37 (avec les 2 nouvelles) — composition actuelle différente de l''hypothèse documentée, reconciliation manuelle requise. Littéraux actuels : %', v_literals;
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. TABLE credit_issuances (§15 point 1)
-- ────────────────────────────────────────────────────────────
CREATE TABLE public.credit_issuances (
    id                                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    verification_outcome_id             UUID NOT NULL REFERENCES public.verification_outcomes(id) ON DELETE RESTRICT,
    aggregator_id                       UUID NOT NULL REFERENCES public.aggregators(id) ON DELETE RESTRICT,
    operator_organization_id            UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    -- (durcissement, quinzième revue statique) : NUMERIC accepte la valeur
    -- spéciale NaN indépendamment de la précision/échelle déclarée (14,4) —
    -- NaN n'est jamais soumis à l'arrondi/troncature de précision, et
    -- PostgreSQL le traite comme supérieur à toute valeur numérique
    -- ordinaire (donc `NaN > 0` est TRUE), ce qui rend le CHECK `> 0` seul
    -- insuffisant pour l'exclure. Exclusion explicite ajoutée.
    quantity_tco2e                      NUMERIC(14,4) NOT NULL CHECK (quantity_tco2e > 0 AND quantity_tco2e <> 'NaN'::numeric),
    issuance_status                     TEXT NOT NULL DEFAULT 'internal'
        CHECK (issuance_status IN ('internal','eligible','submitted','issued','externally_cancelled','externally_rejected','voided')),
    registry_name                       TEXT NULL,
    registry_reference                  TEXT NULL,
    registry_issued_at                  TIMESTAMPTZ NULL,
    external_cancellation_date          DATE NULL,
    external_cancellation_reference     TEXT NULL,
    external_cancellation_document_id   UUID NULL REFERENCES public.documents(id) ON DELETE RESTRICT,
    external_rejection_date             DATE NULL,
    external_rejection_reference        TEXT NULL,
    external_rejection_document_id      UUID NULL REFERENCES public.documents(id) ON DELETE RESTRICT,
    void_reason                         TEXT NULL,
    created_by                          UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    -- (durcissement, seizième revue statique) : DEFAULT clock_timestamp()
    -- plutôt que now() — now() est figée à l'heure de DÉBUT de la
    -- transaction, alors que create_credit_issuance() évalue l'activité des
    -- adhésions/mandats avec clock_timestamp() (heure réelle du contrôle).
    -- Dans une transaction longue, now() pourrait dater l'émission avant
    -- même que l'adhésion/le mandat ayant autorisé sa création ne soit
    -- devenu valide — incohérence historique du même type que celle déjà
    -- corrigée en migration 06 (D15). Ce DEFAULT n'est qu'un filet pour un
    -- INSERT direct hors RPC ; create_credit_issuance() fixe explicitement
    -- v_created_at := clock_timestamp() et l'assigne lui-même (voir plus bas).
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX idx_credit_issuances_verification_outcome ON public.credit_issuances(verification_outcome_id);
CREATE INDEX idx_credit_issuances_aggregator ON public.credit_issuances(aggregator_id);
CREATE INDEX idx_credit_issuances_operator_org ON public.credit_issuances(operator_organization_id);
CREATE INDEX idx_credit_issuances_status ON public.credit_issuances(issuance_status);

-- Unicité de la référence officielle une fois renseignée (correction 8,
-- revue statique 07) — empêche d'enregistrer deux fois la même paire
-- (registry_name, registry_reference), quelle que soit l'émission.
-- (durcissement, seizième revue statique) : index normalisé sur
-- lower(btrim(registry_name)) — les RPC ne faisaient auparavant que
-- valider btrim(...) <> '' sans normaliser la valeur STOCKÉE, laissant
-- 'Verra'/'VERRA'/' Verra ' coexister comme des clés d'index distinctes pour
-- le même registre réel, donc contourner l'unicité recherchée. La casse de
-- registry_reference, elle, est conservée (btrim uniquement) : on ne peut
-- pas présumer que tous les registres externes traitent leurs propres
-- références comme insensibles à la casse. submit_credit_issuance()/
-- record_registry_issuance() normalisent désormais aussi les valeurs
-- stockées (même btrim/lower), pour que la valeur affichée corresponde à ce
-- que l'index compare réellement.
CREATE UNIQUE INDEX idx_credit_issuances_registry_ref_unique
    ON public.credit_issuances (lower(btrim(registry_name)), btrim(registry_reference))
    WHERE registry_reference IS NOT NULL;

COMMENT ON TABLE public.credit_issuances IS
  'Émission réglementaire de crédits carbone — machine à états à 7 statuts (§15 Tranche0-Carbone-Architecture.md). Colonnes figées (verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, created_by, created_at) immuables après création, imposé par trigger.';

-- ────────────────────────────────────────────────────────────
-- 2. TABLE credit_issuance_sources (§15 point 2)
-- ────────────────────────────────────────────────────────────
CREATE TABLE public.credit_issuance_sources (
    id                             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_issuance_id             UUID NOT NULL REFERENCES public.credit_issuances(id) ON DELETE RESTRICT,
    organization_id                UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    aggregator_membership_id       UUID NOT NULL REFERENCES public.aggregator_memberships(id) ON DELETE RESTRICT,
    commercialization_mandate_id   UUID NOT NULL REFERENCES public.carbon_commercialization_mandates(id) ON DELETE RESTRICT,
    -- (durcissement, quinzième revue statique) : même motif que
    -- credit_issuances.quantity_tco2e ci-dessus — NaN satisfait `> 0` en
    -- PostgreSQL, exclusion explicite nécessaire.
    contributed_tco2e              NUMERIC(14,4) NOT NULL CHECK (contributed_tco2e > 0 AND contributed_tco2e <> 'NaN'::numeric),
    -- (durcissement, seizième revue statique) : même motif que
    -- credit_issuances.created_at ci-dessus — filet DEFAULT pour un INSERT
    -- direct ; create_credit_issuance() fixe explicitement v_created_at
    -- pour le parent ET chacune de ses sources, dans la même transaction.
    created_at                     TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    UNIQUE (credit_issuance_id, organization_id)
);

CREATE INDEX idx_credit_issuance_sources_issuance ON public.credit_issuance_sources(credit_issuance_id);
CREATE INDEX idx_credit_issuance_sources_org ON public.credit_issuance_sources(organization_id);
CREATE INDEX idx_credit_issuance_sources_membership ON public.credit_issuance_sources(aggregator_membership_id);
CREATE INDEX idx_credit_issuance_sources_mandate ON public.credit_issuance_sources(commercialization_mandate_id);

COMMENT ON TABLE public.credit_issuance_sources IS
  'Provenance organisationnelle figée d''une émission — une ligne par organisation contributrice, jamais scindée (§15 point 2 Tranche0-Carbone-Architecture.md).';

-- ────────────────────────────────────────────────────────────
-- 3. FONCTIONS D'AUTORISATION ET DE CALCUL (§15 points 4/6)
-- ────────────────────────────────────────────────────────────

-- Opérateur ACTIF, paramétrée par organization_id : encode à la fois
-- « p_organization_id est bien membre/admin » ET « p_organization_id est
-- bien l'opérateur actuellement actif ».
CREATE OR REPLACE FUNCTION public.is_platform_operator_actor(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.platform_operators po
        WHERE po.organization_id = p_organization_id
          AND po.revoked_at IS NULL
          AND public.is_organization_member(p_organization_id)
    )
$$;

-- (correction 7, sixième revue statique) : le statut « opérateur actif » de
-- p_organization_id est désormais un AND obligatoire, y compris pour le
-- super-admin — auparavant les RPC appelantes ajoutaient
-- `OR is_platform_superadmin()` à CÔTÉ de cet appel, ce qui permettait à un
-- super-admin de contourner entièrement l'exigence d'opérateur actif avant
-- `submitted` (mark_credit_issuance_eligible()/void_credit_issuance()). Le
-- super-admin dispose maintenant des mêmes pouvoirs qu'un admin de
-- l'organisation SEULEMENT si p_organization_id est encore l'opérateur
-- METALTRACE actif — jamais pour une émission dont l'opérateur figé a été
-- remplacé entre-temps.
CREATE OR REPLACE FUNCTION public.is_platform_operator_admin(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.platform_operators po
        WHERE po.organization_id = p_organization_id
          AND po.revoked_at IS NULL
          AND (public.is_org_admin(p_organization_id) OR public.is_platform_superadmin())
    )
$$;

-- Capacité déjà consommée pour une session, à travers TOUTE sa chaîne de
-- supersession (§15 point 4) — exclut 'voided' et 'externally_rejected'.
--
-- HELPER REMPLAÇABLE (résolution de la dépendance 05→07, corrigée en
-- cinquième revue statique, point 1) : ce CREATE OR REPLACE suppose que la
-- migration 05 a DÉJÀ posé un STUB de cette fonction (retournant 0
-- inconditionnellement) avant de créer complete_verification_session() —
-- la prévalidation en section 0 ci-dessus échoue explicitement si ce n'est
-- pas le cas. 07 se contente de remplacer le corps par l'implémentation
-- réelle ci-dessous, sans jamais toucher à complete_verification_session()
-- elle-même. Une fois ce remplacement effectué, TOUT appelant existant
-- (create_credit_issuance()/submit_credit_issuance() ci-dessous, ET
-- complete_verification_session() définie par 05) bénéficie immédiatement
-- de l'implémentation réelle, sans modification de son propre corps. Les
-- appelants DOIVENT avoir déjà verrouillé la ligne verification_sessions
-- concernée (FOR UPDATE) avant d'appeler cette fonction ; le verrou n'est
-- jamais pris ici.
CREATE OR REPLACE FUNCTION public.carbon_capacity_consumed_for_session(p_verification_session_id UUID)
RETURNS NUMERIC
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(SUM(ci.quantity_tco2e), 0)
    FROM public.credit_issuances ci
    JOIN public.verification_outcomes vo ON vo.id = ci.verification_outcome_id
    WHERE vo.verification_session_id = p_verification_session_id
      AND ci.issuance_status NOT IN ('voided', 'externally_rejected')
$$;

-- Vérifie qu'une organisation est un participant réel du projet CCF ou MRV
-- rattaché (par la session de vérification) au résultat référencé (§7 point
-- 1 / §15 point 2.8).
--
-- SCHÉMA CONFIRMÉ (sixième revue statique, correction 2) — colonnes réelles
-- vérifiées dans les migrations réellement appliquées :
--   • public.project_participants(project_id, organization_id, ...) — la
--     colonne s'appelle `project_id`, PAS `ccf_project_id` (bug corrigé ici ;
--     20260710005000_ccf_005_ccf_projects_participants.sql).
--   • public.operational_units(id, organization_id, ...) — AUCUNE colonne de
--     lien direct vers un projet (ni `mrv_project_id`, ni autre). L'ancienne
--     hypothèse d'un tel lien direct était fausse et a été retirée.
--   • public.projects(id, operational_unit_id, ...) (MRV) — c'est LA table
--     qui porte le lien vers operational_units, via `operational_unit_id`
--     (FK confirmée, 20260710999100_reapply_mrv_and_aggregators.sql).
--     Le même schéma de jointure (projects → operational_units → organizations)
--     est déjà utilisé ailleurs dans ce fichier de migration pour les
--     policies RLS de credit_lots — repris ici à l'identique.
--   • public.ccf_mrv_project_links reste NON CONFIRMÉ (migration 04 non
--     rédigée) — colonnes ccf_project_id/mrv_project_id toujours
--     hypothétiques, gate de prévalidation section 0 inchangé.
-- Ambiguïté restante, propre à l'absence de la migration 05 : on ne sait pas
-- encore si verification_sessions.project_id référencera ccf_projects.id ou
-- projects.id (MRV) directement, ou les deux selon le type de session — les
-- deux branches ci-dessous restent donc actives en parallèle (LEFT JOIN),
-- avec repli sur ccf_mrv_project_links quand disponible pour traduire d'un
-- espace vers l'autre.
CREATE OR REPLACE FUNCTION public.carbon_is_source_organization_valid(
    p_organization_id UUID,
    p_verification_outcome_id UUID
) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.verification_outcomes vo
        JOIN public.verification_sessions vs ON vs.id = vo.verification_session_id
        LEFT JOIN public.ccf_mrv_project_links link
               ON link.ccf_project_id = vs.project_id OR link.mrv_project_id = vs.project_id
        -- Branche CCF : project_participants.project_id (schéma confirmé).
        -- (correction 1, huitième revue statique) : status='active' exigé —
        -- une ligne 'invited' (pas encore acceptée), 'declined' ou 'removed'
        -- ne constitue PAS une participation effective au projet, et ne doit
        -- donc jamais suffire à valider une organisation source.
        LEFT JOIN public.project_participants pp
               ON pp.project_id = COALESCE(link.ccf_project_id, vs.project_id)
              AND pp.organization_id = p_organization_id
              AND pp.status = 'active'
        -- Branche MRV : projects.operational_unit_id -> operational_units.organization_id
        -- (schéma confirmé, même jointure que credit_lots ailleurs dans ce fichier).
        LEFT JOIN public.projects mp
               ON mp.id = COALESCE(link.mrv_project_id, vs.project_id)
        LEFT JOIN public.operational_units ou
               ON ou.id = mp.operational_unit_id
              AND ou.organization_id = p_organization_id
        WHERE vo.id = p_verification_outcome_id
          AND (pp.organization_id IS NOT NULL OR ou.organization_id IS NOT NULL)
    )
$$;

-- (correction 3, dixième revue statique) : CENTRALISE verrouillage +
-- validation de l'autorité « organisation source » — évite que la logique
-- de VERROUILLAGE et la logique de VALIDATION divergent à nouveau entre les
-- trois points d'appel (create_credit_issuance(), submit_credit_issuance(),
-- carbon_validate_credit_issuance_source()). Principe : toute relation qui
-- rend carbon_is_source_organization_valid() vraie doit rester stable
-- jusqu'à la fin de la transaction — verrouille donc la branche CCF
-- (project_participants) ET la branche MRV (projects PUIS
-- operational_units), puis délègue la décision booléenne à
-- carbon_is_source_organization_valid() elle-même, seule source de vérité
-- de la logique de validité (jamais dupliquée ici). PLpgSQL, pas SQL pur —
-- nécessaire pour les PERFORM ... FOR SHARE ; volontairement PAS marquée
-- STABLE malgré son usage en lecture, cohérent avec les autres fonctions de
-- ce fichier qui verrouillent (le verrou est un effet observable par les
-- autres transactions, à rapprocher d'une opération VOLATILE).
-- ccf_mrv_project_links (lien effectif, branche via 04) : PAS verrouillé
-- ici — cycle de vie inconnu tant que 04 n'est pas rédigée. CONTRAT
-- EXPLICITE 04→07 (neuvième revue statique, toujours ouvert ; précisé
-- onzième revue statique) : le SELECT INTO ci-dessous prend la PREMIÈRE
-- ligne trouvée par le LEFT JOIN si plusieurs liens existent pour le même
-- projet — si 04 autorise plusieurs liens historiques simultanés pour un
-- même ccf_project_id/mrv_project_id, ce SELECT INTO pourrait verrouiller
-- un lien tandis qu'une validation EXISTS ailleurs serait satisfaite par un
-- AUTRE lien, incohérence de verrouillage. 04 devra donc garantir SOIT (a)
-- un seul lien effectif possible par projet à tout instant, SOIT (b)
-- exposer explicitement CE lien effectif pour que 07 l'identifie et le
-- verrouille sans ambiguïté — pas un nouveau blocage autonome aujourd'hui
-- (04 n'existe pas), mais un point obligatoire de la réconciliation 04→07.
CREATE OR REPLACE FUNCTION public.carbon_lock_and_validate_source_organization(
    p_organization_id UUID,
    p_verification_outcome_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_ccf_project_id      UUID;
    v_mrv_project_id      UUID;
    v_operational_unit_id UUID;
BEGIN
    SELECT COALESCE(link.ccf_project_id, vs.project_id), COALESCE(link.mrv_project_id, vs.project_id)
    INTO v_ccf_project_id, v_mrv_project_id
    FROM public.verification_outcomes vo
    JOIN public.verification_sessions vs ON vs.id = vo.verification_session_id
    LEFT JOIN public.ccf_mrv_project_links link
           ON link.ccf_project_id = vs.project_id OR link.mrv_project_id = vs.project_id
    WHERE vo.id = p_verification_outcome_id;

    IF v_ccf_project_id IS NULL AND v_mrv_project_id IS NULL THEN
        RETURN false;
    END IF;

    -- Branche CCF : verrouille la ligne project_participants effective, si
    -- une existe — son absence n'est pas une erreur ici, la branche MRV
    -- peut être celle qui s'applique réellement pour cette organisation.
    IF v_ccf_project_id IS NOT NULL THEN
        PERFORM 1 FROM public.project_participants
        WHERE project_id = v_ccf_project_id AND organization_id = p_organization_id
        FOR SHARE;
    END IF;

    -- Branche MRV : verrouille projects (le lien lui-même, pour qu'une
    -- réaffectation d'operational_unit_id ne puisse pas committer entre ce
    -- contrôle et le COMMIT de l'appelant), PUIS operational_units
    -- (l'autorité organisationnelle réelle).
    IF v_mrv_project_id IS NOT NULL THEN
        SELECT operational_unit_id INTO v_operational_unit_id
        FROM public.projects WHERE id = v_mrv_project_id
        FOR SHARE;

        IF v_operational_unit_id IS NOT NULL THEN
            PERFORM 1 FROM public.operational_units
            WHERE id = v_operational_unit_id AND organization_id = p_organization_id
            FOR SHARE;
        END IF;
    END IF;

    RETURN COALESCE(public.carbon_is_source_organization_valid(p_organization_id, p_verification_outcome_id), false);
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4. TRIGGERS DE COHÉRENCE — credit_issuance_sources (§15 point 2)
-- ────────────────────────────────────────────────────────────

-- BEFORE INSERT : huit vérifications structurelles, défense en profondeur
-- par rapport à la validation déjà faite en amont par create_credit_issuance().
CREATE OR REPLACE FUNCTION public.carbon_validate_credit_issuance_source()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_membership_org_id        UUID;
    v_membership_aggregator_id UUID;
    v_membership_active        BOOLEAN;
    v_issuance_aggregator_id   UUID;
    v_issuance_operator_id     UUID;
    v_issuance_outcome_id      UUID;
    v_issuance_created_at      TIMESTAMPTZ;
    v_mandate_membership_id    UUID;
    v_mandate_operator_id      UUID;
    v_mandate_scope            TEXT[];
    v_mandate_revoked          BOOLEAN;
    v_mandate_granted_at       TIMESTAMPTZ;
BEGIN
    SELECT aggregator_id, operator_organization_id, verification_outcome_id, created_at
    INTO v_issuance_aggregator_id, v_issuance_operator_id, v_issuance_outcome_id, v_issuance_created_at
    FROM public.credit_issuances
    WHERE id = NEW.credit_issuance_id;

    IF v_issuance_aggregator_id IS NULL THEN
        RAISE EXCEPTION 'Cohérence violée : émission parente introuvable pour cette source.';
    END IF;

    -- (durcissement, dix-septième revue statique) : la source DOIT porter
    -- exactement le même created_at que son émission parente — jamais un
    -- clock_timestamp() propre à l'instant d'insertion de CETTE ligne
    -- source précise (qui, insérée dans une boucle après le parent, avance
    -- légèrement à chaque itération). Forcé plutôt que simplement validé :
    -- élimine par construction toute dérive entre sources d'une même
    -- émission, quel que soit le chemin d'écriture (RPC ou INSERT direct).
    NEW.created_at := v_issuance_created_at;

    -- (correction 2, neuvième revue statique) : FOR SHARE — même ligne que
    -- leave_aggregator() (FOR UPDATE, migration 02). Le chemin RPC normal
    -- (create_credit_issuance()) verrouille déjà cette ligne, mais ce
    -- trigger est présenté comme la garantie STRUCTURELLE indépendante du
    -- chemin d'écriture — une insertion privilégiée directe (service_role,
    -- ou tout futur code contournant la RPC) doit bénéficier de la même
    -- protection contre une fin d'adhésion concurrente.
    -- (durcissement, dix-septième revue statique) : l'activité de
    -- l'adhésion est désormais évaluée relativement à v_issuance_created_at
    -- (l'instant de constitution RÉEL de l'émission parente, fixé par son
    -- propre trigger BEFORE INSERT) — PAS un nouveau clock_timestamp() pris
    -- à l'instant de CET INSERT précis. Bug corrigé : selon l'ancien calcul,
    -- une adhésion pouvait être jugée active « maintenant » (à l'insertion
    -- de la source) tout en ayant démarré APRÈS l'instant réel de création
    -- de l'émission, ce qui aurait validé une source dont l'autorité n'avait
    -- pas encore commencé au moment prétendu de la constitution de
    -- l'émission.
    SELECT organization_id, aggregator_id,
           (started_at <= v_issuance_created_at AND (ended_at IS NULL OR ended_at > v_issuance_created_at))
    INTO v_membership_org_id, v_membership_aggregator_id, v_membership_active
    FROM public.aggregator_memberships
    WHERE id = NEW.aggregator_membership_id
    FOR SHARE;

    IF v_membership_org_id IS NULL OR v_membership_org_id <> NEW.organization_id THEN
        RAISE EXCEPTION 'Cohérence violée : aggregator_membership_id ne correspond pas à organization_id (check 1).';
    END IF;

    IF v_membership_aggregator_id <> v_issuance_aggregator_id THEN
        RAISE EXCEPTION 'Cohérence violée : la source appartient à un regroupement différent de l''émission parente (check 2).';
    END IF;

    IF NOT COALESCE(v_membership_active, false) THEN
        RAISE EXCEPTION 'Cohérence violée : adhésion inactive à l''instant de constitution de l''émission (check 7).';
    END IF;

    -- même motif — même ligne que revoke_commercialization_mandate() (FOR
    -- UPDATE, migration 06).
    SELECT aggregator_membership_id, operator_organization_id, scope, (revoked_at IS NOT NULL), granted_at
    INTO v_mandate_membership_id, v_mandate_operator_id, v_mandate_scope, v_mandate_revoked, v_mandate_granted_at
    FROM public.carbon_commercialization_mandates
    WHERE id = NEW.commercialization_mandate_id
    FOR SHARE;

    IF v_mandate_membership_id IS NULL OR v_mandate_membership_id <> NEW.aggregator_membership_id THEN
        RAISE EXCEPTION 'Cohérence violée : commercialization_mandate_id non rattaché à cette adhésion précise (check 3).';
    END IF;

    IF v_mandate_operator_id <> v_issuance_operator_id THEN
        RAISE EXCEPTION 'Cohérence violée : le mandat désigne un opérateur différent de l''émission parente (check 4).';
    END IF;

    IF v_mandate_revoked THEN
        RAISE EXCEPTION 'Cohérence violée : mandat révoqué (check 5).';
    END IF;

    IF NOT ('request_issuance' = ANY(v_mandate_scope)) THEN
        RAISE EXCEPTION 'Cohérence violée : le mandat n''autorise pas request_issuance dans son scope (check 6).';
    END IF;

    -- (correction 3A, dixième revue statique) : carbon_lock_and_validate_source_organization()
    -- remplace l'appel direct à carbon_is_source_organization_valid() —
    -- verrouille désormais aussi la participation projet (CCF et MRV)
    -- depuis ce trigger structurel, qui ne le faisait pas jusqu'ici (seule
    -- la RPC create_credit_issuance() le faisait).
    IF NOT COALESCE(public.carbon_lock_and_validate_source_organization(NEW.organization_id, v_issuance_outcome_id), false) THEN
        RAISE EXCEPTION 'Cohérence violée : organisation non participante réelle du projet concerné (check 8).';
    END IF;

    -- (durcissement, dix-septième revue statique, check 9 — recommandation
    -- « idéalement » de la dix-septième revue) : le mandat ne peut pas avoir
    -- été accordé APRÈS l'instant de constitution de l'émission qu'il
    -- prétend autoriser — défense de bon sens temporel, en plus des checks
    -- 3/4/5/6 qui valident déjà la cohérence structurelle du mandat.
    IF v_mandate_granted_at > v_issuance_created_at THEN
        RAISE EXCEPTION 'Cohérence violée : le mandat a été accordé après l''instant de constitution de l''émission (check 9).';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_validate_credit_issuance_source
    BEFORE INSERT ON public.credit_issuance_sources
    FOR EACH ROW EXECUTE FUNCTION public.carbon_validate_credit_issuance_source();

-- BEFORE UPDATE/DELETE : credit_issuance_sources est append-only — aucune
-- modification ni suppression, quel que soit le rôle appelant (correction
-- 4, cinquième revue statique). Une provenance figée à la création ne doit
-- jamais être réécrite après coup.
CREATE OR REPLACE FUNCTION public.carbon_credit_issuance_sources_forbid_write()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'credit_issuance_sources est append-only : UPDATE/DELETE interdits.';
END;
$$;

CREATE TRIGGER trg_carbon_credit_issuance_sources_forbid_update
    BEFORE UPDATE ON public.credit_issuance_sources
    FOR EACH ROW EXECUTE FUNCTION public.carbon_credit_issuance_sources_forbid_write();

CREATE TRIGGER trg_carbon_credit_issuance_sources_forbid_delete
    BEFORE DELETE ON public.credit_issuance_sources
    FOR EACH ROW EXECUTE FUNCTION public.carbon_credit_issuance_sources_forbid_write();

-- CONSTRAINT TRIGGER différé : SUM(contributed_tco2e) = credit_issuances.quantity_tco2e (§15 point 5).
-- NOTE : les branches UPDATE/DELETE de ce déclencheur différé sont
-- désormais inatteignables en pratique (les triggers BEFORE ci-dessus
-- bloquent toute UPDATE/DELETE avant qu'elles n'atteignent ce niveau) —
-- conservées telles quelles par défense en profondeur, sans coût
-- fonctionnel.
CREATE OR REPLACE FUNCTION public.carbon_validate_credit_issuance_sources_sum()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_credit_issuance_id UUID;
    v_expected            NUMERIC(14,4);
    v_actual              NUMERIC(14,4);
BEGIN
    v_credit_issuance_id := COALESCE(NEW.credit_issuance_id, OLD.credit_issuance_id);

    SELECT quantity_tco2e INTO v_expected
    FROM public.credit_issuances WHERE id = v_credit_issuance_id;

    SELECT COALESCE(SUM(contributed_tco2e), 0) INTO v_actual
    FROM public.credit_issuance_sources WHERE credit_issuance_id = v_credit_issuance_id;

    IF v_expected IS NOT NULL AND v_actual <> v_expected THEN
        RAISE EXCEPTION 'Somme des sources (%) différente de quantity_tco2e (%) pour l''émission %.', v_actual, v_expected, v_credit_issuance_id;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_carbon_validate_sources_sum
    AFTER INSERT OR UPDATE OR DELETE ON public.credit_issuance_sources
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.carbon_validate_credit_issuance_sources_sum();

-- ────────────────────────────────────────────────────────────
-- 5. TRIGGERS — credit_issuances (§15 points 1/4/10)
-- ────────────────────────────────────────────────────────────

-- BEFORE INSERT : verrouille l'état initial d'une émission — issuance_status
-- doit être 'internal' et tous les champs réglementaires produits par une
-- transition ultérieure doivent être NULL à la création. Ferme le
-- contournement direct de la machine à états qui permettait un INSERT brut
-- avec un statut ou des champs réglementaires déjà renseignés, sans jamais
-- passer par les RPC de transition (correction 6, sixième revue statique).
CREATE OR REPLACE FUNCTION public.carbon_credit_issuances_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.issuance_status IS DISTINCT FROM 'internal' THEN
        RAISE EXCEPTION 'Une émission doit être créée au statut internal (machine à états §15/§10) — statut fourni : %.', NEW.issuance_status;
    END IF;

    IF NEW.registry_name IS NOT NULL OR NEW.registry_reference IS NOT NULL OR NEW.registry_issued_at IS NOT NULL
       OR NEW.external_rejection_date IS NOT NULL OR NEW.external_rejection_reference IS NOT NULL OR NEW.external_rejection_document_id IS NOT NULL
       OR NEW.external_cancellation_date IS NOT NULL OR NEW.external_cancellation_reference IS NOT NULL OR NEW.external_cancellation_document_id IS NOT NULL
       OR NEW.void_reason IS NOT NULL THEN
        RAISE EXCEPTION 'Une émission doit être créée sans aucun champ réglementaire renseigné (registry_*/external_rejection_*/external_cancellation_*/void_reason) — ces champs ne peuvent être initialisés que par leur transition légitime respective, jamais à l''INSERT.';
    END IF;

    -- (correction 1, dixième revue statique) : create_credit_issuance()
    -- garantit déjà que NEW.operator_organization_id est l'opérateur actif
    -- (elle le résout elle-même en interne), mais ce trigger est la garantie
    -- STRUCTURELLE indépendante du chemin RPC — sans ce contrôle, un INSERT
    -- privilégié direct pouvait créer une émission sous operator_organization_id
    -- = un ANCIEN opérateur (OP_A), tant qu'un mandat historique non révoqué
    -- désignant OP_A existait encore : le trigger des sources
    -- (carbon_validate_credit_issuance_source()) ne vérifie que la cohérence
    -- INTERNE mandat↔émission, jamais que cet opérateur est réellement
    -- actif. FOR SHARE — même ligne que designate_platform_operator() (FOR
    -- UPDATE, migration 06), pour la même raison de sérialisation que les
    -- autres verrous de ce fichier.
    PERFORM 1 FROM public.platform_operators
    WHERE organization_id = NEW.operator_organization_id AND revoked_at IS NULL
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Création refusée : operator_organization_id doit être l''opérateur METALTRACE actif.';
    END IF;

    -- (durcissement, dix-septième revue statique) : NEW.created_at est
    -- FORCÉ à clock_timestamp() ici, inconditionnellement — sans ce
    -- verrouillage, un INSERT privilégié direct pourrait fournir n'importe
    -- quelle valeur (y compris antidatée) pour created_at. Ce trigger
    -- s'exécute à l'instant réel de l'INSERT, structurellement APRÈS tous
    -- les verrous et contrôles temporels (adhésions/mandats/opérateur actif)
    -- déjà exécutés séquentiellement par create_credit_issuance() avant
    -- d'atteindre cette instruction — ce qui garantit transitivement que
    -- created_at est postérieur ou égal à l'instant où chacune de ces
    -- autorités a été constatée valide, jamais antérieur (cf. bug corrigé
    -- ce tour : created_at capturé trop tôt, avant les verrous, pouvait
    -- précéder l'activation réelle d'une adhésion validée pendant une
    -- attente de verrou). create_credit_issuance() récupère cette valeur
    -- via RETURNING et la propage identiquement à chaque source.
    NEW.created_at := clock_timestamp();

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_credit_issuances_before_insert
    BEFORE INSERT ON public.credit_issuances
    FOR EACH ROW EXECUTE FUNCTION public.carbon_credit_issuances_before_insert();

-- BEFORE UPDATE : immutabilité des colonnes figées, machine à états stricte,
-- garde contre la progression sans sources cohérentes.
CREATE OR REPLACE FUNCTION public.carbon_credit_issuances_before_update()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_source_count INT;
    v_source_sum   NUMERIC(14,4);
BEGIN
    -- (durcissement, neuvième revue statique) : NEW.id ajouté — non couvert
    -- jusqu'ici. Le chemin normal (FK depuis credit_issuance_sources) rend
    -- une modification d'id difficile en pratique, mais une transaction
    -- privilégiée pourrait en théorie : INSERT une émission sans source,
    -- UPDATE son id, PUIS insérer les sources sous le nouvel id — précédant
    -- ainsi le déclenchement du trigger différé « au moins une source »
    -- (trg_carbon_validate_credit_issuance_has_sources), qui ne surveille
    -- que l'existence de sources, jamais la stabilité de l'id lui-même.
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.verification_outcome_id  IS DISTINCT FROM OLD.verification_outcome_id
       OR NEW.aggregator_id         IS DISTINCT FROM OLD.aggregator_id
       OR NEW.operator_organization_id IS DISTINCT FROM OLD.operator_organization_id
       OR NEW.quantity_tco2e        IS DISTINCT FROM OLD.quantity_tco2e
       OR NEW.created_by            IS DISTINCT FROM OLD.created_by
       OR NEW.created_at            IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'Colonne immuable modifiée sur credit_issuances.';
    END IF;

    -- (correction 4, cinquième revue statique) : les champs réglementaires
    -- produits par une transition (registry_*, rejet externe, annulation
    -- externe, void_reason) sont figés dès qu'ils ont été renseignés une
    -- première fois — NULL → valeur reste autorisé (c'est ainsi que les RPC
    -- de transition les renseignent), mais valeur → valeur différente est
    -- interdit, y compris pour un appel direct hors RPC.
    IF (OLD.registry_name IS NOT NULL AND NEW.registry_name IS DISTINCT FROM OLD.registry_name)
       OR (OLD.registry_reference IS NOT NULL AND NEW.registry_reference IS DISTINCT FROM OLD.registry_reference)
       OR (OLD.registry_issued_at IS NOT NULL AND NEW.registry_issued_at IS DISTINCT FROM OLD.registry_issued_at)
       OR (OLD.external_rejection_date IS NOT NULL AND NEW.external_rejection_date IS DISTINCT FROM OLD.external_rejection_date)
       OR (OLD.external_rejection_reference IS NOT NULL AND NEW.external_rejection_reference IS DISTINCT FROM OLD.external_rejection_reference)
       OR (OLD.external_rejection_document_id IS NOT NULL AND NEW.external_rejection_document_id IS DISTINCT FROM OLD.external_rejection_document_id)
       OR (OLD.external_cancellation_date IS NOT NULL AND NEW.external_cancellation_date IS DISTINCT FROM OLD.external_cancellation_date)
       OR (OLD.external_cancellation_reference IS NOT NULL AND NEW.external_cancellation_reference IS DISTINCT FROM OLD.external_cancellation_reference)
       OR (OLD.external_cancellation_document_id IS NOT NULL AND NEW.external_cancellation_document_id IS DISTINCT FROM OLD.external_cancellation_document_id)
       OR (OLD.void_reason IS NOT NULL AND NEW.void_reason IS DISTINCT FROM OLD.void_reason) THEN
        RAISE EXCEPTION 'Champ réglementaire figé sur credit_issuances : déjà renseigné lors d''une transition antérieure, non modifiable.';
    END IF;

    -- (correction 6, sixième revue statique) : le PREMIER renseignement
    -- (NULL -> valeur) de chaque champ réglementaire n'est autorisé QUE
    -- lors de la transition de statut qui lui est légitimement associée.
    -- Contrairement au bloc de légalité de transition ci-dessous, ce
    -- contrôle s'applique INCONDITIONNELLEMENT (pas seulement quand le
    -- statut change) : un contournement direct peut laisser
    -- NEW.issuance_status = OLD.issuance_status tout en essayant
    -- d'initialiser un champ réglementaire — un UPDATE à statut inchangé ne
    -- doit jamais pouvoir le faire.
    IF OLD.registry_name IS NULL AND NEW.registry_name IS NOT NULL
       AND NOT (OLD.issuance_status = 'eligible' AND NEW.issuance_status = 'submitted') THEN
        RAISE EXCEPTION 'registry_name ne peut être renseigné que lors de la transition eligible -> submitted.';
    END IF;
    IF OLD.registry_reference IS NULL AND NEW.registry_reference IS NOT NULL
       AND NOT (OLD.issuance_status = 'submitted' AND NEW.issuance_status = 'issued') THEN
        RAISE EXCEPTION 'registry_reference ne peut être renseigné que lors de la transition submitted -> issued.';
    END IF;
    IF OLD.registry_issued_at IS NULL AND NEW.registry_issued_at IS NOT NULL
       AND NOT (OLD.issuance_status = 'submitted' AND NEW.issuance_status = 'issued') THEN
        RAISE EXCEPTION 'registry_issued_at ne peut être renseigné que lors de la transition submitted -> issued.';
    END IF;
    IF OLD.external_rejection_date IS NULL AND NEW.external_rejection_date IS NOT NULL
       AND NOT (OLD.issuance_status = 'submitted' AND NEW.issuance_status = 'externally_rejected') THEN
        RAISE EXCEPTION 'external_rejection_date ne peut être renseigné que lors de la transition submitted -> externally_rejected.';
    END IF;
    IF OLD.external_rejection_reference IS NULL AND NEW.external_rejection_reference IS NOT NULL
       AND NOT (OLD.issuance_status = 'submitted' AND NEW.issuance_status = 'externally_rejected') THEN
        RAISE EXCEPTION 'external_rejection_reference ne peut être renseigné que lors de la transition submitted -> externally_rejected.';
    END IF;
    IF OLD.external_rejection_document_id IS NULL AND NEW.external_rejection_document_id IS NOT NULL
       AND NOT (OLD.issuance_status = 'submitted' AND NEW.issuance_status = 'externally_rejected') THEN
        RAISE EXCEPTION 'external_rejection_document_id ne peut être renseigné que lors de la transition submitted -> externally_rejected.';
    END IF;
    IF OLD.external_cancellation_date IS NULL AND NEW.external_cancellation_date IS NOT NULL
       AND NOT (OLD.issuance_status = 'issued' AND NEW.issuance_status = 'externally_cancelled') THEN
        RAISE EXCEPTION 'external_cancellation_date ne peut être renseigné que lors de la transition issued -> externally_cancelled.';
    END IF;
    IF OLD.external_cancellation_reference IS NULL AND NEW.external_cancellation_reference IS NOT NULL
       AND NOT (OLD.issuance_status = 'issued' AND NEW.issuance_status = 'externally_cancelled') THEN
        RAISE EXCEPTION 'external_cancellation_reference ne peut être renseigné que lors de la transition issued -> externally_cancelled.';
    END IF;
    IF OLD.external_cancellation_document_id IS NULL AND NEW.external_cancellation_document_id IS NOT NULL
       AND NOT (OLD.issuance_status = 'issued' AND NEW.issuance_status = 'externally_cancelled') THEN
        RAISE EXCEPTION 'external_cancellation_document_id ne peut être renseigné que lors de la transition issued -> externally_cancelled.';
    END IF;
    IF OLD.void_reason IS NULL AND NEW.void_reason IS NOT NULL
       AND NOT (OLD.issuance_status IN ('internal','eligible') AND NEW.issuance_status = 'voided') THEN
        RAISE EXCEPTION 'void_reason ne peut être renseigné que lors d''une transition vers voided (depuis internal ou eligible).';
    END IF;

    IF NEW.issuance_status IS DISTINCT FROM OLD.issuance_status THEN
        IF NOT (
            (OLD.issuance_status = 'internal'  AND NEW.issuance_status = 'eligible') OR
            (OLD.issuance_status = 'eligible'  AND NEW.issuance_status = 'submitted') OR
            (OLD.issuance_status = 'submitted' AND NEW.issuance_status = 'issued') OR
            (OLD.issuance_status = 'submitted' AND NEW.issuance_status = 'externally_rejected') OR
            (OLD.issuance_status = 'issued'    AND NEW.issuance_status = 'externally_cancelled') OR
            (OLD.issuance_status = 'internal'  AND NEW.issuance_status = 'voided') OR
            (OLD.issuance_status = 'eligible'  AND NEW.issuance_status = 'voided')
        ) THEN
            RAISE EXCEPTION 'Transition de statut interdite : % → % (machine à états §15/§10).', OLD.issuance_status, NEW.issuance_status;
        END IF;

        -- (correction 3, septième revue statique) : invariants de
        -- COMPLÉTUDE par état cible. Le contrôle de « premier
        -- renseignement » ci-dessus (plus haut dans cette fonction)
        -- garantit qu'un champ ne peut être renseigné QUE pendant sa
        -- transition légitime, mais ne garantissait PAS l'inverse : rien
        -- n'empêchait jusqu'ici une transition légitime de statut de se
        -- produire SANS renseigner le(s) champ(s) associé(s), laissant un
        -- état terminal (ou intermédiaire) définitivement incomplet — les
        -- champs concernés étant ensuite figés (irréparable). Chaque
        -- transition vers un état qui exige une preuve/référence doit
        -- désormais fournir cette preuve/référence DANS LA MÊME UPDATE.
        IF NEW.issuance_status = 'submitted' AND (NEW.registry_name IS NULL OR btrim(NEW.registry_name) = '') THEN
            RAISE EXCEPTION 'Transition eligible -> submitted refusée : registry_name doit être renseigné dans la même transition.';
        END IF;

        IF NEW.issuance_status = 'issued' AND (
            NEW.registry_reference IS NULL OR btrim(NEW.registry_reference) = '' OR NEW.registry_issued_at IS NULL
        ) THEN
            RAISE EXCEPTION 'Transition submitted -> issued refusée : registry_reference et registry_issued_at doivent être renseignés dans la même transition.';
        END IF;

        IF NEW.issuance_status = 'externally_rejected' AND (
            NEW.external_rejection_date IS NULL
            OR NEW.external_rejection_reference IS NULL OR btrim(NEW.external_rejection_reference) = ''
            OR NEW.external_rejection_document_id IS NULL
        ) THEN
            RAISE EXCEPTION 'Transition submitted -> externally_rejected refusée : external_rejection_date/reference/document_id doivent tous être renseignés dans la même transition.';
        END IF;

        -- (durcissement, quatorzième revue statique) : la validation
        -- documents.owner_org_id = opérateur figé n'était garantie que par
        -- record_externally_rejected()/record_external_cancellation() —
        -- une écriture privilégiée directe, contournant ces RPC mais
        -- passant par ce même trigger BEFORE UPDATE, pouvait jusqu'ici
        -- rattacher un document de preuve appartenant à une AUTRE
        -- organisation, la complétude structurelle ci-dessus ne vérifiant
        -- que la présence du document_id, jamais sa provenance. Toute la
        -- migration 07 reposant sur une défense structurelle indépendante
        -- des RPC (machine à états, complétude, capacité, immutabilité),
        -- il serait incohérent que la sémantique de la preuve documentaire
        -- reste le seul invariant contournable par écriture privilégiée.
        IF NEW.issuance_status = 'externally_rejected' AND NOT EXISTS (
            SELECT 1 FROM public.documents
            WHERE id = NEW.external_rejection_document_id AND owner_org_id = NEW.operator_organization_id
        ) THEN
            RAISE EXCEPTION 'Transition submitted -> externally_rejected refusée : external_rejection_document_id doit désigner un document appartenant à l''organisation opératrice figée de cette émission.';
        END IF;

        IF NEW.issuance_status = 'externally_cancelled' AND (
            NEW.external_cancellation_date IS NULL
            OR NEW.external_cancellation_reference IS NULL OR btrim(NEW.external_cancellation_reference) = ''
            OR NEW.external_cancellation_document_id IS NULL
        ) THEN
            RAISE EXCEPTION 'Transition issued -> externally_cancelled refusée : external_cancellation_date/reference/document_id doivent tous être renseignés dans la même transition.';
        END IF;

        IF NEW.issuance_status = 'externally_cancelled' AND NOT EXISTS (
            SELECT 1 FROM public.documents
            WHERE id = NEW.external_cancellation_document_id AND owner_org_id = NEW.operator_organization_id
        ) THEN
            RAISE EXCEPTION 'Transition issued -> externally_cancelled refusée : external_cancellation_document_id doit désigner un document appartenant à l''organisation opératrice figée de cette émission.';
        END IF;

        IF NEW.issuance_status = 'voided' AND (NEW.void_reason IS NULL OR btrim(NEW.void_reason) = '') THEN
            RAISE EXCEPTION 'Transition vers voided refusée : void_reason doit être renseigné (non vide) dans la même transition.';
        END IF;

        IF OLD.issuance_status = 'internal' AND NEW.issuance_status IN ('eligible','submitted','issued') THEN
            SELECT count(*), COALESCE(SUM(contributed_tco2e), 0)
            INTO v_source_count, v_source_sum
            FROM public.credit_issuance_sources WHERE credit_issuance_id = NEW.id;

            IF v_source_count = 0 OR v_source_sum <> NEW.quantity_tco2e THEN
                RAISE EXCEPTION 'Progression de statut refusée : sources absentes ou incohérentes (somme=% attendu=%).', v_source_sum, NEW.quantity_tco2e;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_carbon_credit_issuances_before_update
    BEFORE UPDATE ON public.credit_issuances
    FOR EACH ROW EXECUTE FUNCTION public.carbon_credit_issuances_before_update();

-- BEFORE DELETE : credit_issuances est historisée — aucune suppression,
-- quel que soit le rôle appelant (correction 4, cinquième revue statique).
-- Clore une émission passe exclusivement par void_credit_issuance()/
-- record_externally_rejected()/record_external_cancellation().
CREATE OR REPLACE FUNCTION public.carbon_credit_issuances_forbid_delete()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'credit_issuances est historisée : DELETE interdit (utiliser void_credit_issuance()/record_externally_rejected()/record_external_cancellation() pour clore une émission).';
END;
$$;

CREATE TRIGGER trg_carbon_credit_issuances_forbid_delete
    BEFORE DELETE ON public.credit_issuances
    FOR EACH ROW EXECUTE FUNCTION public.carbon_credit_issuances_forbid_delete();

-- CONSTRAINT TRIGGER différé : capacité <= plafond de l'outcome actif, sur
-- l'ensemble de la chaîne de supersession (§15 point 4).
CREATE OR REPLACE FUNCTION public.carbon_validate_credit_issuance_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_id        UUID;
    v_active_outcome_id UUID;
    v_active_eligible   NUMERIC(14,4);
    v_consumed          NUMERIC(14,4);
BEGIN
    SELECT verification_session_id INTO v_session_id
    FROM public.verification_outcomes WHERE id = NEW.verification_outcome_id;

    -- (correction 3, huitième revue statique) : verrou partagé avec
    -- create_credit_issuance()/submit_credit_issuance() (et, plus tard,
    -- complete_verification_session() de la migration 05 — voir exigence en
    -- tête de fichier) sur la MÊME ligne verification_sessions, pris AVANT
    -- toute lecture de eligible_tco2e/calcul de consumed. Sans ce verrou, ce
    -- constraint trigger différé (qui s'exécute au COMMIT, potentiellement
    -- bien après les verrous FOR UPDATE pris — et relâchés en fin de leur
    -- propre transaction — par des écritures concurrentes) ne garantit pas
    -- structurellement l'anti-double-comptage : deux transactions
    -- concurrentes pourraient chacune calculer un `consumed` cohérent avec
    -- l'état qu'elles ont vu, mais incohérent l'une avec l'autre au moment
    -- où elles committent toutes les deux.
    PERFORM 1 FROM public.verification_sessions WHERE id = v_session_id FOR UPDATE;

    SELECT id, eligible_tco2e INTO v_active_outcome_id, v_active_eligible
    FROM public.verification_outcomes
    WHERE verification_session_id = v_session_id AND status = 'active';

    -- (correction 3a, neuvième revue statique) : l'ABSENCE d'outcome actif
    -- pour la session ne doit JAMAIS être acceptée silencieusement.
    -- Auparavant, v_active_eligible NULL désarmait entièrement le contrôle
    -- (IF v_active_eligible IS NOT NULL AND ...) — une garantie STRUCTURELLE
    -- ne peut logiquement pas valider une capacité consommée sans plafond de
    -- référence : l'absence de plafond doit être un rejet, pas une
    -- absence de contrôle.
    IF v_active_outcome_id IS NULL THEN
        RAISE EXCEPTION 'Aucun outcome actif pour la session % : impossible de valider une capacité consommée.', v_session_id;
    END IF;

    -- (correction 3b, neuvième revue statique) : à l'INSERT UNIQUEMENT,
    -- l'outcome référencé par la nouvelle ligne doit être PRÉCISÉMENT
    -- l'outcome actif de sa session — pas seulement UN outcome quelconque de
    -- la session. create_credit_issuance() applique déjà cette contrainte
    -- (elle ne lit que l'outcome actif, verrouillé, dès le départ), mais ce
    -- trigger est la garantie STRUCTURELLE indépendante : sans ce contrôle,
    -- une écriture privilégiée directe pouvait insérer une émission
    -- rattachée à un outcome DÉJÀ superseded tout en passant le contrôle de
    -- capacité (celui-ci ne regarde que le plafond de l'outcome ACTIF de la
    -- session, jamais l'identité de l'outcome réellement référencé par
    -- NEW). Spécifique à l'INSERT : après soumission (submitted), une
    -- supersession ultérieure de l'outcome ne doit PAS bloquer issued/
    -- externally_cancelled — le comportement historique pour les UPDATE
    -- reste inchangé (voir aussi carbon_credit_issuances_before_update(),
    -- qui interdit déjà toute modification de verification_outcome_id après
    -- création).
    IF TG_OP = 'INSERT' AND NEW.verification_outcome_id IS DISTINCT FROM v_active_outcome_id THEN
        RAISE EXCEPTION 'INSERT refusé : verification_outcome_id (%) n''est pas l''outcome actif (%) de la session % au moment de la création.',
            NEW.verification_outcome_id, v_active_outcome_id, v_session_id;
    END IF;

    -- (durcissement, quinzième revue statique) : eligible_tco2e appartient à
    -- verification_outcomes, propriété de la migration 05 (pas encore
    -- écrite) — 07 ne peut pas y poser de CHECK de table. Défense en
    -- profondeur symétrique néanmoins : `v_consumed > v_active_eligible`
    -- seul ne détecte PAS un plafond NaN, puisque PostgreSQL traite NaN
    -- comme supérieur à toute valeur numérique ordinaire pour les
    -- opérateurs de comparaison — `v_consumed > NaN` est FALSE quelle que
    -- soit la valeur de v_consumed, désarmant silencieusement tout le
    -- contrôle de capacité. Rejet explicite ajouté.
    IF v_active_eligible = 'NaN'::numeric THEN
        RAISE EXCEPTION 'Plafond de capacité invalide (NaN) pour la session % : contrôle de capacité impossible.', v_session_id;
    END IF;

    v_consumed := public.carbon_capacity_consumed_for_session(v_session_id);

    IF v_consumed > v_active_eligible THEN
        RAISE EXCEPTION 'Capacité dépassée pour la session % : % consommés > % plafond.', v_session_id, v_consumed, v_active_eligible;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_carbon_validate_issuance_capacity
    AFTER INSERT OR UPDATE ON public.credit_issuances
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.carbon_validate_credit_issuance_capacity();

-- CONSTRAINT TRIGGER différé : garantit STRUCTURELLEMENT qu'une émission ne
-- reste jamais sans AUCUNE source contributive (correction 5, sixième
-- revue statique). Le contrôle existant (trg_carbon_validate_sources_sum,
-- section 4) ne se déclenche QUE sur un événement credit_issuance_sources
-- (INSERT/UPDATE/DELETE) — une émission créée avec zéro source ne
-- déclenche jamais un tel événement et échappait donc entièrement à toute
-- vérification. DEFERRABLE INITIALLY DEFERRED est nécessaire :
-- create_credit_issuance() insère d'abord la ligne credit_issuances, PUIS
-- boucle sur l'insertion des sources (section 6 ci-dessous) — un
-- déclenchement immédiat échouerait systématiquement même pour un usage
-- parfaitement légitime.
CREATE OR REPLACE FUNCTION public.carbon_validate_credit_issuance_has_sources()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_source_count INT;
    v_source_sum   NUMERIC(14,4);
BEGIN
    SELECT count(*), COALESCE(SUM(contributed_tco2e), 0)
    INTO v_source_count, v_source_sum
    FROM public.credit_issuance_sources WHERE credit_issuance_id = NEW.id;

    IF v_source_count = 0 THEN
        RAISE EXCEPTION 'Émission % créée sans aucune source contributive — invariant violé : au moins une source est requise (§15 point 2).', NEW.id;
    END IF;

    IF v_source_sum <> NEW.quantity_tco2e THEN
        RAISE EXCEPTION 'Somme des sources (%) différente de quantity_tco2e (%) pour l''émission % (vérification déclenchée par son INSERT).', v_source_sum, NEW.quantity_tco2e, NEW.id;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_carbon_validate_credit_issuance_has_sources
    AFTER INSERT ON public.credit_issuances
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.carbon_validate_credit_issuance_has_sources();

-- ────────────────────────────────────────────────────────────
-- 5bis. TRIGGER — platform_operators (correction 2, dixième revue statique ;
-- décision d'architecture consignée dans Tranche0-Carbone-Architecture.md
-- §15.10.d) : interdit la révocation/transfert de l'opérateur actif tant
-- qu'il détient au moins une émission 'internal' ou 'eligible'.
--
-- platform_operators est une table de la migration 06 (déjà APPLIQUÉE EN
-- PRODUCTION le 18 juillet 2026, voir dépendances en tête de fichier) — ce
-- trigger est posé ICI, par 07, et non dans 06, car il référence
-- credit_issuances, une table qui n'existe pas au moment où 06 a été écrite
-- ni appliquée. Ajouter un trigger à une table déjà existante depuis une
-- migration postérieure est standard ; 07 dépend déjà structurellement de
-- 06 (voir section 0, dépendances).
--
-- CUL-DE-SAC CORRIGÉ : sans ce trigger, un transfert d'opérateur
-- (designate_platform_operator(), migration 06) alors qu'une émission
-- 'internal'/'eligible' existe encore sous l'ancien opérateur la rend
-- IMMÉDIATEMENT et DÉFINITIVEMENT inaccessible — ni progression
-- (mark_credit_issuance_eligible()/submit_credit_issuance()), ni annulation
-- (void_credit_issuance()) ne sont plus possibles (même régime opérateur
-- actif pour les trois, y compris pour le super-admin, voir
-- is_platform_operator_admin()), alors qu'elle continue indéfiniment à
-- consommer la capacité du résultat de vérification concerné. Les
-- émissions déjà 'submitted' (et au-delà) ne sont PAS concernées : elles
-- relèvent déjà du régime opérateur figé (survit structurellement au
-- transfert, voir can_view_credit_issuance()/record_registry_issuance() et
-- consorts) et n'ont besoin d'aucune action de l'opérateur actif.
--
-- Se déclenche sur TOUTE transition revoked_at NULL -> NOT NULL, quelle que
-- soit sa cause — posé au niveau de la table, pas de la RPC
-- designate_platform_operator() elle-même, donc valable aussi pour tout
-- futur mécanisme de révocation qui ne passerait pas par elle.
CREATE OR REPLACE FUNCTION public.carbon_platform_operators_before_revoke()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM public.credit_issuances
            WHERE operator_organization_id = OLD.organization_id
              AND issuance_status IN ('internal', 'eligible')
        ) THEN
            RAISE EXCEPTION 'Révocation/transfert refusé : l''opérateur % détient encore au moins une émission internal/eligible — la faire progresser vers submitted ou l''annuler (voided) avant tout transfert (Tranche0-Carbone-Architecture.md §15.10.d).', OLD.organization_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_carbon_platform_operators_before_revoke ON public.platform_operators;
CREATE TRIGGER trg_carbon_platform_operators_before_revoke
    BEFORE UPDATE ON public.platform_operators
    FOR EACH ROW EXECUTE FUNCTION public.carbon_platform_operators_before_revoke();

-- ────────────────────────────────────────────────────────────
-- 6. RPC — credit_issuances (§15 point 7/10, sept fonctions)
-- ────────────────────────────────────────────────────────────

-- 1/7 : création — is_platform_operator_actor(opérateur actif résolu en interne).
CREATE OR REPLACE FUNCTION public.create_credit_issuance(
    p_verification_outcome_id UUID,
    p_sources JSONB
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                UUID;
    v_operator_org_id      UUID;
    v_verification_session_id UUID;
    v_outcome_status       TEXT;
    v_eligible_tco2e       NUMERIC(14,4);
    v_aggregator_id        UUID;
    v_quantity_tco2e       NUMERIC(14,4) := 0;
    v_consumed_tco2e       NUMERIC(14,4);
    v_credit_issuance_id   UUID;
    v_source               JSONB;
    v_org_id                UUID;
    v_membership_id          UUID;
    v_mandate_id             UUID;
    v_contributed            NUMERIC(14,4);
    v_membership_org_id      UUID;
    v_membership_aggregator_id UUID;
    v_mandate_operator_id    UUID;
    v_mandate_scope          TEXT[];
    v_created_at             TIMESTAMPTZ;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- (durcissement, dix-septième revue statique — remplace la capture
    -- précédente, seizième revue statique) : v_created_at N'EST PLUS
    -- capturé ici. La capturer tôt, avant les verrous et les contrôles
    -- temporels des adhésions/mandats ci-dessous, était le bug corrigé ce
    -- tour : une adhésion dont started_at était postérieur à cette capture
    -- précoce pouvait devenir active PENDANT une attente de verrou et être
    -- acceptée par les contrôles (qui, eux, appellent clock_timestamp() à
    -- nouveau, plus tard), tout en laissant l'émission persistée avec un
    -- created_at antérieur à sa propre autorité. v_created_at est
    -- désormais récupéré par RETURNING après l'INSERT ci-dessous, où
    -- carbon_credit_issuances_before_insert() (trigger BEFORE INSERT) fixe
    -- lui-même NEW.created_at := clock_timestamp() — structurellement APRÈS
    -- tous les contrôles de cette fonction, qui s'exécutent séquentiellement
    -- avant d'atteindre l'INSERT. Chaque contrôle temporel ci-dessous
    -- continue d'utiliser clock_timestamp() à SON propre instant d'exécution
    -- (pas encore de v_created_at à ce stade) — la garantie « created_at
    -- postérieur ou égal à l'instant de chaque contrôle » découle de l'ordre
    -- séquentiel d'exécution, pas d'une valeur partagée à l'avance.
    IF p_sources IS NULL OR jsonb_typeof(p_sources) <> 'array' OR jsonb_array_length(p_sources) = 0 THEN
        RAISE EXCEPTION 'Au moins une source est requise (p_sources doit être un tableau JSON non vide).';
    END IF;

    -- (correction 2, huitième revue statique) : FOR SHARE — verrou partagé
    -- sur la MÊME ligne que designate_platform_operator() (FOR UPDATE,
    -- migration 06). Sans ce verrou, un transfert d'opérateur concurrent
    -- peut committer entre cette lecture et le COMMIT de cette fonction,
    -- laissant une émission créée sous un operator_organization_id qui n'est
    -- déjà plus réellement cohérent avec l'état final de platform_operators —
    -- fenêtre de course fermée structurellement par la prise de verrou, pas
    -- seulement par la vitesse d'exécution.
    SELECT organization_id INTO v_operator_org_id
    FROM public.platform_operators WHERE revoked_at IS NULL
    FOR SHARE;

    IF v_operator_org_id IS NULL THEN
        RAISE EXCEPTION 'Aucun opérateur METALTRACE actif désigné — impossible de créer une émission.';
    END IF;

    IF NOT COALESCE(public.is_platform_operator_actor(v_operator_org_id), false) THEN
        RAISE EXCEPTION 'Accès refusé : vous n''êtes pas membre de l''organisation opératrice active.';
    END IF;

    -- lecture NON verrouillée de la seule référence immuable de l'outcome
    -- (verification_session_id ne change jamais après création d'une ligne
    -- verification_outcomes) — juste assez pour savoir quelle ligne
    -- verification_sessions verrouiller (correction concurrence, revue
    -- statique 07 point 3).
    SELECT vo.verification_session_id INTO v_verification_session_id
    FROM public.verification_outcomes vo
    WHERE vo.id = p_verification_outcome_id;

    IF v_verification_session_id IS NULL THEN
        RAISE EXCEPTION 'Résultat de vérification introuvable.';
    END IF;

    -- verrou partagé avec complete_verification_session() (migration 05,
    -- voir exigence en tête de fichier) — sur verification_sessions, jamais
    -- sur un verification_outcome précis — pris AVANT toute lecture de
    -- status/eligible_tco2e, pour éliminer la fenêtre de course où une
    -- supersession concurrente rendrait cette lecture obsolète.
    PERFORM 1 FROM public.verification_sessions WHERE id = v_verification_session_id FOR UPDATE;

    -- relecture, désormais SOUS verrou : vue garantie cohérente avec toute
    -- supersession concurrente déjà validée par le verrou ci-dessus.
    SELECT vo.status, vo.eligible_tco2e INTO v_outcome_status, v_eligible_tco2e
    FROM public.verification_outcomes vo
    WHERE vo.id = p_verification_outcome_id;

    IF v_outcome_status <> 'active' THEN
        RAISE EXCEPTION 'Le résultat de vérification référencé n''est pas actif (superseded).';
    END IF;

    FOR v_source IN SELECT * FROM jsonb_array_elements(p_sources)
    LOOP
        IF NOT (v_source ? 'organization_id' AND v_source ? 'aggregator_membership_id'
                AND v_source ? 'commercialization_mandate_id' AND v_source ? 'contributed_tco2e') THEN
            RAISE EXCEPTION 'Chaque source doit fournir organization_id, aggregator_membership_id, commercialization_mandate_id, contributed_tco2e.';
        END IF;

        BEGIN
            v_org_id := (v_source->>'organization_id')::UUID;
            v_membership_id := (v_source->>'aggregator_membership_id')::UUID;
            v_mandate_id := (v_source->>'commercialization_mandate_id')::UUID;
            v_contributed := (v_source->>'contributed_tco2e')::NUMERIC(14,4);
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Format de source invalide (UUID ou nombre attendu).';
        END;

        -- (durcissement, quinzième revue statique) : `v_contributed <= 0`
        -- seul ne rejette PAS NaN — PostgreSQL traite NaN comme supérieur à
        -- toute valeur numérique ordinaire pour les opérateurs de
        -- comparaison (`NaN <= 0` est FALSE, `NaN > 0` est TRUE), donc un
        -- contributed_tco2e = 'NaN' franchirait ce contrôle avant même
        -- d'atteindre le CHECK de table (lui aussi durci ce tour).
        -- Rejet explicite ajouté, indépendant du CHECK de table.
        IF v_contributed IS NULL OR v_contributed <= 0 OR v_contributed = 'NaN'::numeric THEN
            RAISE EXCEPTION 'contributed_tco2e doit être strictement positif et fini (NaN interdit) pour chaque source.';
        END IF;

        -- point de contrôle "internal" (§3), checks 1/7 : adhésion active + organisation.
        -- (correction 2, huitième revue statique) : FOR SHARE — même ligne
        -- que leave_aggregator() (FOR UPDATE, migration 02) — empêche une
        -- fin d'adhésion concurrente de committer entre ce contrôle et le
        -- COMMIT de cette fonction.
        SELECT am.organization_id, am.aggregator_id
        INTO v_membership_org_id, v_membership_aggregator_id
        FROM public.aggregator_memberships am
        WHERE am.id = v_membership_id
          AND am.organization_id = v_org_id
          AND am.started_at <= clock_timestamp()
          AND (am.ended_at IS NULL OR am.ended_at > clock_timestamp())
        FOR SHARE;

        IF v_membership_org_id IS NULL THEN
            RAISE EXCEPTION 'Adhésion introuvable, inactive, ou ne correspond pas à l''organisation source déclarée (organization_id=%).', v_org_id;
        END IF;

        -- checks 2/3/5/6 : mandat rattaché à cette adhésion, actif, scope.
        -- (correction 2, huitième revue statique) : FOR SHARE — même ligne
        -- que revoke_commercialization_mandate() (FOR UPDATE, migration 06)
        -- — empêche une révocation concurrente de committer entre ce
        -- contrôle et le COMMIT de cette fonction.
        SELECT cm.operator_organization_id, cm.scope
        INTO v_mandate_operator_id, v_mandate_scope
        FROM public.carbon_commercialization_mandates cm
        WHERE cm.id = v_mandate_id
          AND cm.aggregator_membership_id = v_membership_id
          AND cm.revoked_at IS NULL
        FOR SHARE;

        IF v_mandate_operator_id IS NULL THEN
            RAISE EXCEPTION 'Mandat introuvable, révoqué, ou non rattaché à cette adhésion précise (aggregator_membership_id=%).', v_membership_id;
        END IF;

        IF NOT ('request_issuance' = ANY(v_mandate_scope)) THEN
            RAISE EXCEPTION 'Le mandat rattaché à l''organisation % n''autorise pas request_issuance dans son scope.', v_org_id;
        END IF;

        -- check 4 : homogénéité d'opérateur (§1 §15 point 1, angle mort fermé).
        IF v_mandate_operator_id <> v_operator_org_id THEN
            RAISE EXCEPTION 'Le mandat de l''organisation % désigne un opérateur différent de l''opérateur METALTRACE actuellement actif.', v_org_id;
        END IF;

        -- homogénéité de regroupement.
        IF v_aggregator_id IS NULL THEN
            v_aggregator_id := v_membership_aggregator_id;
        ELSIF v_aggregator_id <> v_membership_aggregator_id THEN
            RAISE EXCEPTION 'Les sources ne partagent pas le même regroupement (aggregator_id).';
        END IF;

        -- check 8 : participation réelle au projet (dépendance migration 04).
        -- (correction 3, dixième revue statique) : carbon_lock_and_validate_source_organization()
        -- remplace le verrou inline + l'appel direct à
        -- carbon_is_source_organization_valid() — verrouille désormais AUSSI
        -- la branche MRV (projects/operational_units), pas seulement
        -- project_participants (CCF).
        IF NOT COALESCE(public.carbon_lock_and_validate_source_organization(v_org_id, p_verification_outcome_id), false) THEN
            RAISE EXCEPTION 'L''organisation % n''est pas un participant réel du projet associé à ce résultat de vérification.', v_org_id;
        END IF;

        -- check 9 (mandat accordé avant l'instant de constitution de
        -- l'émission) n'est PAS dupliqué ici : v_created_at n'existe pas
        -- encore à ce stade (récupéré seulement après l'INSERT ci-dessous,
        -- cf. commentaire en tête de fonction). Il est appliqué de façon
        -- structurelle et faisant autorité par carbon_validate_credit_issuance_source()
        -- (trigger BEFORE INSERT sur credit_issuance_sources, exécuté juste
        -- après pour chaque source), qui, lui, connaît déjà l'instant exact.

        v_quantity_tco2e := v_quantity_tco2e + v_contributed;
    END LOOP;

    -- capacité restante sur l'ensemble de la chaîne de supersession (§15 point 4).
    v_consumed_tco2e := public.carbon_capacity_consumed_for_session(v_verification_session_id);
    IF v_consumed_tco2e + v_quantity_tco2e > v_eligible_tco2e THEN
        RAISE EXCEPTION 'Capacité insuffisante : % déjà consommés + % demandés > % (plafond du résultat actif).', v_consumed_tco2e, v_quantity_tco2e, v_eligible_tco2e;
    END IF;

    -- (durcissement, dix-septième revue statique) : created_at n'est PLUS
    -- fourni ici — carbon_credit_issuances_before_insert() (trigger BEFORE
    -- INSERT) le fixe lui-même, inconditionnellement, à clock_timestamp() au
    -- moment réel de cet INSERT (structurellement après tous les contrôles
    -- ci-dessus). RETURNING id, created_at récupère la valeur exacte
    -- réellement appliquée, pour la propager identiquement à chaque source.
    INSERT INTO public.credit_issuances (
        verification_outcome_id, aggregator_id, operator_organization_id, quantity_tco2e, issuance_status, created_by
    ) VALUES (
        p_verification_outcome_id, v_aggregator_id, v_operator_org_id, v_quantity_tco2e, 'internal', v_actor
    ) RETURNING id, created_at INTO v_credit_issuance_id, v_created_at;

    FOR v_source IN SELECT * FROM jsonb_array_elements(p_sources)
    LOOP
        -- v_created_at (récupéré par RETURNING ci-dessus) transmis pour
        -- documentation/clarté ; carbon_validate_credit_issuance_source()
        -- (trigger BEFORE INSERT sur credit_issuance_sources) le FORCE de
        -- toute façon à la valeur exacte de l'émission parente, quelle que
        -- soit la valeur fournie ici — élimine par construction toute
        -- dérive entre sources d'une même émission.
        INSERT INTO public.credit_issuance_sources (
            credit_issuance_id, organization_id, aggregator_membership_id, commercialization_mandate_id, contributed_tco2e, created_at
        ) VALUES (
            v_credit_issuance_id,
            (v_source->>'organization_id')::UUID,
            (v_source->>'aggregator_membership_id')::UUID,
            (v_source->>'commercialization_mandate_id')::UUID,
            (v_source->>'contributed_tco2e')::NUMERIC(14,4),
            v_created_at
        );
    END LOOP;

    -- (correction 3, onzième revue statique) : organization_id/aggregator_id/
    -- verification_session_id désormais systématiquement renseignés — dimensions
    -- d'autorisation de can_view_carbon_event() (§10bis, migration 01/05).
    -- organization_id = operator_organization_id figé (décision retenue :
    -- fil d'événements de l'organisation opératrice responsable ; la
    -- visibilité des organisations sources reste couverte par la RLS propre
    -- aux émissions elles-mêmes, décision distincte non traitée ici).
    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_issuance', v_credit_issuance_id, 'credit_issuance_created', v_actor,
            v_operator_org_id, v_aggregator_id, v_verification_session_id,
            jsonb_build_object('quantity_tco2e', v_quantity_tco2e, 'aggregator_id', v_aggregator_id, 'operator_organization_id', v_operator_org_id));

    RETURN v_credit_issuance_id;
END;
$$;

-- 2/7 : internal → eligible — opérateur actif, aucune revalidation.
CREATE OR REPLACE FUNCTION public.mark_credit_issuance_eligible(p_credit_issuance_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                    UUID;
    v_status                   TEXT;
    v_aggregator_id            UUID;
    v_operator_org_id          UUID;
    v_outcome_id               UUID;
    v_verification_session_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- (correction 2, huitième revue statique) : FOR SHARE — même ligne que
    -- designate_platform_operator() (FOR UPDATE, migration 06), pris AVANT
    -- le contrôle d'autorisation ci-dessous. is_platform_operator_admin()
    -- lit platform_operators SANS verrou (fonction STABLE) : sans cette
    -- prise de verrou explicite, un transfert d'opérateur concurrent peut
    -- committer entre le contrôle d'autorisation et le COMMIT de cette
    -- fonction — sérialise désormais avec designate_platform_operator() sur
    -- toute la durée de la transaction, pas seulement au moment du contrôle.
    PERFORM 1 FROM public.platform_operators WHERE revoked_at IS NULL FOR SHARE;

    -- (correction 7, sixième revue statique) : plus de `OR is_platform_superadmin()`
    -- séparé ici — is_platform_operator_admin() exige désormais l'opérateur
    -- actif pour TOUT appelant, super-admin compris (voir sa définition).
    -- (correction 3, onzième revue statique) : aggregator_id/operator_organization_id/
    -- verification_outcome_id également chargés, uniquement pour contextualiser
    -- l'événement métier ci-dessous (aucun contrôle d'autorisation supplémentaire).
    SELECT issuance_status, aggregator_id, operator_organization_id, verification_outcome_id
    INTO v_status, v_aggregator_id, v_operator_org_id, v_outcome_id
    FROM public.credit_issuances
    WHERE id = p_credit_issuance_id
      AND COALESCE(public.is_platform_operator_admin(operator_organization_id), false)
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Émission introuvable ou accès refusé.';
    END IF;

    IF v_status <> 'internal' THEN
        RAISE EXCEPTION 'Transition refusée : statut actuel %, attendu internal.', v_status;
    END IF;

    UPDATE public.credit_issuances SET issuance_status = 'eligible' WHERE id = p_credit_issuance_id;

    SELECT verification_session_id INTO v_verification_session_id
    FROM public.verification_outcomes WHERE id = v_outcome_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_issuance', p_credit_issuance_id, 'credit_issuance_marked_eligible', v_actor,
            v_operator_org_id, v_aggregator_id, v_verification_session_id, '{}'::jsonb);
END;
$$;

-- 3/7 : eligible → submitted — opérateur actif, REJOUE le point de contrôle
-- "submitted" (5 vérifications par source, §3), bloquant.
CREATE OR REPLACE FUNCTION public.submit_credit_issuance(p_credit_issuance_id UUID, p_registry_name TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor           UUID;
    v_status          TEXT;
    v_operator_org_id UUID;
    v_outcome_id      UUID;
    v_outcome_status  TEXT;
    v_src             RECORD;
    v_active_operator UUID;
    v_session_id_lock UUID;
    v_aggregator_id   UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    IF p_registry_name IS NULL OR btrim(p_registry_name) = '' THEN
        RAISE EXCEPTION 'p_registry_name est requis.';
    END IF;

    -- (durcissement, seizième revue statique) : normalise la valeur
    -- effectivement STOCKÉE, pas seulement validée — sans ce btrim, une
    -- valeur comme ' Verra ' passait la validation (non vide après btrim)
    -- mais était enregistrée avec ses espaces, désynchronisée de l'index
    -- d'unicité normalisé (lower(btrim(registry_name))) ci-dessus.
    p_registry_name := btrim(p_registry_name);

    -- (correction 3, onzième revue statique) : aggregator_id également chargé
    -- ici, uniquement pour contextualiser l'événement métier plus bas.
    SELECT issuance_status, operator_organization_id, verification_outcome_id, aggregator_id
    INTO v_status, v_operator_org_id, v_outcome_id, v_aggregator_id
    FROM public.credit_issuances
    WHERE id = p_credit_issuance_id
      AND (COALESCE(public.is_platform_operator_admin(operator_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Émission introuvable ou accès refusé.';
    END IF;

    IF v_status <> 'eligible' THEN
        RAISE EXCEPTION 'Transition refusée : statut actuel %, attendu eligible.', v_status;
    END IF;

    -- point de contrôle "submitted" (§3), check 5 : opérateur toujours actif.
    -- (correction 2, huitième revue statique) : FOR SHARE — même ligne que
    -- designate_platform_operator() (FOR UPDATE, migration 06). C'est ICI,
    -- juste avant l'UPDATE de transition plus bas, que la décision finale
    -- est prise : le verrou doit couvrir ce contrôle jusqu'au COMMIT pour
    -- fermer structurellement la fenêtre de course avec un transfert
    -- d'opérateur concurrent (peu importe que l'autorisation initiale
    -- is_platform_operator_admin() ci-dessus ait été lue sans verrou : si un
    -- transfert committe avant ce point, v_active_operator reflète déjà le
    -- nouvel état et le contrôle suivant rejette correctement ; si un
    -- transfert est en cours, ce FOR SHARE le bloque jusqu'à son COMMIT ou
    -- ROLLBACK).
    SELECT organization_id INTO v_active_operator
    FROM public.platform_operators WHERE revoked_at IS NULL
    FOR SHARE;
    IF v_active_operator IS DISTINCT FROM v_operator_org_id THEN
        RAISE EXCEPTION 'Soumission refusée : l''opérateur figé de cette émission n''est plus l''opérateur METALTRACE actif.';
    END IF;

    -- verrou partagé avec create_credit_issuance()/complete_verification_session()
    -- (correction concurrence, revue statique 07 point 3) — pris AVANT la
    -- lecture de outcome.status ci-dessous, sur la session résolue depuis
    -- v_outcome_id (référence immuable, lecture non verrouillée sûre).
    SELECT vo.verification_session_id INTO v_session_id_lock
    FROM public.verification_outcomes vo WHERE vo.id = v_outcome_id;

    PERFORM 1 FROM public.verification_sessions WHERE id = v_session_id_lock FOR UPDATE;

    -- check 4 : résultat de vérification toujours actif — lu SOUS verrou.
    SELECT status INTO v_outcome_status FROM public.verification_outcomes WHERE id = v_outcome_id;
    IF v_outcome_status <> 'active' THEN
        RAISE EXCEPTION 'Soumission refusée : le résultat de vérification référencé n''est plus actif.';
    END IF;

    -- checks 1/2/3 par source : adhésion active, mandat actif, scope.
    FOR v_src IN
        SELECT cis.organization_id, cis.aggregator_membership_id, cis.commercialization_mandate_id
        FROM public.credit_issuance_sources cis
        WHERE cis.credit_issuance_id = p_credit_issuance_id
    LOOP
        -- (correction 2, huitième revue statique) : converti d'EXISTS(...)
        -- vers SELECT ... FOR SHARE explicite + IF NOT FOUND, pour le même
        -- motif que ci-dessus — même ligne que leave_aggregator() (FOR
        -- UPDATE, migration 02) — empêche une fin d'adhésion concurrente de
        -- committer entre ce contrôle et le COMMIT de cette fonction.
        PERFORM 1 FROM public.aggregator_memberships am
        WHERE am.id = v_src.aggregator_membership_id
          AND am.organization_id = v_src.organization_id
          AND am.started_at <= clock_timestamp()
          AND (am.ended_at IS NULL OR am.ended_at > clock_timestamp())
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Soumission refusée : adhésion inactive pour l''organisation %.', v_src.organization_id;
        END IF;

        -- même motif — même ligne que revoke_commercialization_mandate()
        -- (FOR UPDATE, migration 06).
        PERFORM 1 FROM public.carbon_commercialization_mandates cm
        WHERE cm.id = v_src.commercialization_mandate_id
          AND cm.aggregator_membership_id = v_src.aggregator_membership_id
          AND cm.revoked_at IS NULL
          AND 'request_issuance' = ANY(cm.scope)
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Soumission refusée : mandat révoqué ou scope insuffisant pour l''organisation %.', v_src.organization_id;
        END IF;

        -- check 8 (correction 1, neuvième revue statique) : REVALIDATION de
        -- la participation réelle au projet, absente jusqu'ici de
        -- submit_credit_issuance() — cette RPC prétendait « rejouer le point
        -- de contrôle submitted » (voir commentaire au-dessus de la
        -- fonction) sans jamais revérifier check 8, alors que create_credit_issuance()
        -- le vérifie bien à la création. Une organisation retirée du projet
        -- entre la création (internal) et la soumission (eligible ->
        -- submitted) pouvait donc franchir submit_credit_issuance() sans
        -- blocage.
        -- (correction 3, dixième revue statique) : carbon_lock_and_validate_source_organization()
        -- remplace le verrou inline (project_participants seul) + l'appel
        -- direct à carbon_is_source_organization_valid() — verrouille
        -- désormais AUSSI la branche MRV. ccf_mrv_project_links reste hors
        -- périmètre (contrat 04→07, toujours ouvert).
        IF NOT COALESCE(public.carbon_lock_and_validate_source_organization(v_src.organization_id, v_outcome_id), false) THEN
            RAISE EXCEPTION 'Soumission refusée : l''organisation % n''est plus un participant effectif du projet.', v_src.organization_id;
        END IF;
    END LOOP;

    UPDATE public.credit_issuances
    SET issuance_status = 'submitted', registry_name = p_registry_name
    WHERE id = p_credit_issuance_id;

    -- (correction 3, onzième revue statique) : v_session_id_lock (déjà
    -- résolue et verrouillée plus haut) réutilisée directement comme
    -- verification_session_id de l'événement — aucune requête supplémentaire.
    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_issuance', p_credit_issuance_id, 'credit_issuance_submitted', v_actor,
            v_operator_org_id, v_aggregator_id, v_session_id_lock, jsonb_build_object('registry_name', p_registry_name));
END;
$$;

-- 4/7 : submitted → issued — opérateur FIGÉ, aucune revalidation métier.
-- (correction 2, septième revue statique) : registry_issued_at est
-- désormais un paramètre OBLIGATOIRE (p_registry_issued_at), et non plus
-- clock_timestamp() au moment de la saisie — ce champ doit représenter le
-- timestamp OFFICIEL communiqué par le registre externe (potentiellement
-- très différent du moment où l'opérateur saisit l'information dans
-- METALTRACE), jamais un horodatage applicatif interne.
CREATE OR REPLACE FUNCTION public.record_registry_issuance(
    p_credit_issuance_id UUID, p_registry_reference TEXT, p_registry_issued_at TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                    UUID;
    v_status                   TEXT;
    v_registry_name            TEXT;
    v_aggregator_id            UUID;
    v_operator_org_id          UUID;
    v_outcome_id               UUID;
    v_verification_session_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    IF p_registry_reference IS NULL OR btrim(p_registry_reference) = '' THEN
        RAISE EXCEPTION 'p_registry_reference est requis.';
    END IF;
    IF p_registry_issued_at IS NULL THEN
        RAISE EXCEPTION 'p_registry_issued_at est requis (timestamp officiel du registre, pas la date de saisie).';
    END IF;

    -- (durcissement, seizième revue statique) : normalise la valeur
    -- effectivement STOCKÉE (btrim uniquement — la CASSE de la référence
    -- elle-même est conservée, cf. commentaire de l'index d'unicité
    -- ci-dessus : on ne peut pas présumer qu'un registre externe donné
    -- traite ses propres références comme insensibles à la casse).
    p_registry_reference := btrim(p_registry_reference);

    -- (correction 2, cinquième revue statique) : registry_name est chargé
    -- ici, dans une variable correctement déclarée, pour être disponible
    -- dans le message d'erreur ci-dessous sans référencer un identifiant
    -- de colonne hors de portée.
    -- (correction 3, onzième revue statique) : aggregator_id/operator_organization_id/
    -- verification_outcome_id également chargés, uniquement pour contextualiser
    -- l'événement métier plus bas.
    SELECT issuance_status, registry_name, aggregator_id, operator_organization_id, verification_outcome_id
    INTO v_status, v_registry_name, v_aggregator_id, v_operator_org_id, v_outcome_id
    FROM public.credit_issuances
    WHERE id = p_credit_issuance_id
      AND (COALESCE(public.is_org_admin(operator_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Émission introuvable ou accès refusé.';
    END IF;

    IF v_status <> 'submitted' THEN
        RAISE EXCEPTION 'Transition refusée : statut actuel %, attendu submitted.', v_status;
    END IF;

    -- l'unicité de (registry_name, registry_reference) est imposée par
    -- idx_credit_issuances_registry_ref_unique (section 1) ; message clair
    -- en cas de violation plutôt que l'erreur brute de contrainte.
    BEGIN
        UPDATE public.credit_issuances
        SET issuance_status = 'issued', registry_reference = p_registry_reference, registry_issued_at = p_registry_issued_at
        WHERE id = p_credit_issuance_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'Cette référence de registre (%, %) a déjà été enregistrée pour une autre émission.', v_registry_name, p_registry_reference;
    END;

    SELECT verification_session_id INTO v_verification_session_id
    FROM public.verification_outcomes WHERE id = v_outcome_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_issuance', p_credit_issuance_id, 'credit_issuance_issued', v_actor,
            v_operator_org_id, v_aggregator_id, v_verification_session_id,
            jsonb_build_object('registry_reference', p_registry_reference, 'registry_issued_at', p_registry_issued_at));
END;
$$;

-- 5/7 : submitted → externally_rejected (NOUVEAU) — opérateur FIGÉ, preuve
-- obligatoire et sémantiquement validée, libère la capacité.
CREATE OR REPLACE FUNCTION public.record_externally_rejected(
    p_credit_issuance_id UUID, p_date DATE, p_reference TEXT, p_document_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                    UUID;
    v_status                   TEXT;
    v_operator                 UUID;
    v_aggregator_id            UUID;
    v_outcome_id               UUID;
    v_verification_session_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- (correction 3, cinquième revue statique) : date/référence/document
    -- sont TOUS les trois désormais obligatoires pour un rejet externe —
    -- validation de forme uniquement (ne révèle rien sur l'émission ciblée,
    -- donc sans risque D13 à exécuter avant la recherche+autorisation).
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'p_date est obligatoire (date du refus externe).';
    END IF;
    IF p_reference IS NULL OR btrim(p_reference) = '' THEN
        RAISE EXCEPTION 'p_reference est obligatoire (référence du refus externe).';
    END IF;
    IF p_document_id IS NULL THEN
        RAISE EXCEPTION 'p_document_id est obligatoire (preuve du refus externe).';
    END IF;

    -- D13 : recherche+autorisation de l'émission AVANT toute validation liée
    -- au document (correction 3, cinquième revue statique — la validation du
    -- document doit se faire APRÈS, jamais avant, pour ne pas créer une
    -- asymétrie d'information distincte du chemin normal "introuvable ou
    -- accès refusé").
    -- (correction 3, onzième revue statique) : aggregator_id/verification_outcome_id
    -- également chargés, uniquement pour contextualiser l'événement métier
    -- plus bas.
    SELECT issuance_status, operator_organization_id, aggregator_id, verification_outcome_id
    INTO v_status, v_operator, v_aggregator_id, v_outcome_id
    FROM public.credit_issuances
    WHERE id = p_credit_issuance_id
      AND (COALESCE(public.is_org_admin(operator_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Émission introuvable ou accès refusé.';
    END IF;

    IF v_status <> 'submitted' THEN
        RAISE EXCEPTION 'Transition refusée : statut actuel %, attendu submitted.', v_status;
    END IF;

    -- validation sémantique du document (correction 3, cinquième revue
    -- statique) : le document doit exister ET appartenir à l'organisation
    -- opératrice FIGÉE de cette émission — pas seulement exister dans
    -- l'absolu. Voir ⚠️ POINT OUVERT #2 en tête de fichier pour le nom de
    -- colonne owner_org_id, à reconfirmer en direct.
    IF NOT EXISTS (
        SELECT 1 FROM public.documents
        WHERE id = p_document_id AND owner_org_id = v_operator
    ) THEN
        RAISE EXCEPTION 'Document de preuve introuvable ou n''appartient pas à l''organisation opératrice de cette émission (p_document_id=%).', p_document_id;
    END IF;

    UPDATE public.credit_issuances
    SET issuance_status = 'externally_rejected',
        external_rejection_date = p_date,
        external_rejection_reference = p_reference,
        external_rejection_document_id = p_document_id
    WHERE id = p_credit_issuance_id;

    SELECT verification_session_id INTO v_verification_session_id
    FROM public.verification_outcomes WHERE id = v_outcome_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_issuance', p_credit_issuance_id, 'credit_issuance_externally_rejected', v_actor,
            v_operator, v_aggregator_id, v_verification_session_id,
            jsonb_build_object('date', p_date, 'reference', p_reference, 'document_id', p_document_id));
END;
$$;

-- 6/7 : {internal,eligible} → voided (portée réduite, décision 1) — opérateur actif, aucune preuve.
CREATE OR REPLACE FUNCTION public.void_credit_issuance(p_credit_issuance_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                    UUID;
    v_status                   TEXT;
    v_aggregator_id            UUID;
    v_operator_org_id          UUID;
    v_outcome_id               UUID;
    v_verification_session_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- (correction 2, huitième revue statique) : idem mark_credit_issuance_eligible()
    -- — FOR SHARE sur la même ligne que designate_platform_operator(),
    -- pris AVANT le contrôle d'autorisation, pour la même raison.
    PERFORM 1 FROM public.platform_operators WHERE revoked_at IS NULL FOR SHARE;

    -- (correction 7, sixième revue statique) : idem mark_credit_issuance_eligible().
    -- (correction 3, onzième revue statique) : aggregator_id/operator_organization_id/
    -- verification_outcome_id également chargés, uniquement pour contextualiser
    -- l'événement métier plus bas.
    SELECT issuance_status, aggregator_id, operator_organization_id, verification_outcome_id
    INTO v_status, v_aggregator_id, v_operator_org_id, v_outcome_id
    FROM public.credit_issuances
    WHERE id = p_credit_issuance_id
      AND COALESCE(public.is_platform_operator_admin(operator_organization_id), false)
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Émission introuvable ou accès refusé.';
    END IF;

    IF v_status NOT IN ('internal', 'eligible') THEN
        RAISE EXCEPTION 'Annulation interne refusée depuis le statut % — utiliser record_externally_rejected() depuis submitted, ou record_external_cancellation() depuis issued.', v_status;
    END IF;

    UPDATE public.credit_issuances
    SET issuance_status = 'voided', void_reason = p_reason
    WHERE id = p_credit_issuance_id;

    SELECT verification_session_id INTO v_verification_session_id
    FROM public.verification_outcomes WHERE id = v_outcome_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_issuance', p_credit_issuance_id, 'credit_issuance_voided', v_actor,
            v_operator_org_id, v_aggregator_id, v_verification_session_id, jsonb_build_object('reason', p_reason));
END;
$$;

-- 7/7 : issued → externally_cancelled — opérateur FIGÉ, preuve obligatoire
-- et sémantiquement validée, ne libère jamais la capacité.
CREATE OR REPLACE FUNCTION public.record_external_cancellation(
    p_credit_issuance_id UUID, p_date DATE, p_reference TEXT, p_document_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor                    UUID;
    v_status                   TEXT;
    v_operator                 UUID;
    v_aggregator_id            UUID;
    v_outcome_id               UUID;
    v_verification_session_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentification requise.'; END IF;

    -- (correction 3, cinquième revue statique) : date/référence/document
    -- sont TOUS les trois désormais obligatoires pour une annulation
    -- externe — validation de forme uniquement, sans risque D13.
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'p_date est obligatoire (date de l''annulation externe).';
    END IF;
    IF p_reference IS NULL OR btrim(p_reference) = '' THEN
        RAISE EXCEPTION 'p_reference est obligatoire (référence de l''annulation externe).';
    END IF;
    IF p_document_id IS NULL THEN
        RAISE EXCEPTION 'p_document_id est obligatoire (preuve d''annulation externe).';
    END IF;

    -- D13 : recherche+autorisation de l'émission AVANT toute validation liée
    -- au document (correction 3, cinquième revue statique).
    -- (correction 3, onzième revue statique) : aggregator_id/verification_outcome_id
    -- également chargés, uniquement pour contextualiser l'événement métier
    -- plus bas.
    SELECT issuance_status, operator_organization_id, aggregator_id, verification_outcome_id
    INTO v_status, v_operator, v_aggregator_id, v_outcome_id
    FROM public.credit_issuances
    WHERE id = p_credit_issuance_id
      AND (COALESCE(public.is_org_admin(operator_organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Émission introuvable ou accès refusé.';
    END IF;

    IF v_status <> 'issued' THEN
        RAISE EXCEPTION 'Transition refusée : statut actuel %, attendu issued.', v_status;
    END IF;

    -- validation sémantique du document (correction 3, cinquième revue
    -- statique) : appartenance à l'organisation opératrice FIGÉE, pas
    -- seulement existence. Voir ⚠️ POINT OUVERT #2 en tête de fichier.
    IF NOT EXISTS (
        SELECT 1 FROM public.documents
        WHERE id = p_document_id AND owner_org_id = v_operator
    ) THEN
        RAISE EXCEPTION 'Document de preuve introuvable ou n''appartient pas à l''organisation opératrice de cette émission (p_document_id=%).', p_document_id;
    END IF;

    UPDATE public.credit_issuances
    SET issuance_status = 'externally_cancelled',
        external_cancellation_date = p_date,
        external_cancellation_reference = p_reference,
        external_cancellation_document_id = p_document_id
    WHERE id = p_credit_issuance_id;

    SELECT verification_session_id INTO v_verification_session_id
    FROM public.verification_outcomes WHERE id = v_outcome_id;

    INSERT INTO public.carbon_business_events (object_type, object_id, event_type, actor_id, organization_id, aggregator_id, verification_session_id, payload)
    VALUES ('credit_issuance', p_credit_issuance_id, 'credit_issuance_externally_cancelled', v_actor,
            v_operator, v_aggregator_id, v_verification_session_id,
            jsonb_build_object('date', p_date, 'reference', p_reference, 'document_id', p_document_id));
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 7. MIGRATION 05 — EXIGENCE DOCUMENTÉE, AUCUN SQL ICI
-- ────────────────────────────────────────────────────────────
-- Résolution de la dépendance 05→07, ORDRE CHRONOLOGIQUE (cinquième revue
-- statique, point 1 — corrige un ordre précédemment inversé dans ce
-- commentaire) : cette migration (07) NE contient PAS de CREATE OR REPLACE
-- de complete_verification_session() ni de trigger sur
-- verification_outcomes — ces deux responsabilités appartiennent
-- entièrement à la migration 05, qui n'est pas encore rédigée. L'ordre
-- attendu, dans 05 elle-même, est :
--   1. 05 crée D'ABORD le STUB de
--      public.carbon_capacity_consumed_for_session(uuid) RETURNS NUMERIC,
--      renvoyant 0 sans condition. Nécessaire car check_function_bodies
--      exige que toute fonction référencée par complete_verification_session()
--      existe déjà au moment où celle-ci est définie.
--   2. 05 crée ENSUITE complete_verification_session(), qui :
--      a. verrouille verification_sessions FOR UPDATE (par id) AVANT toute
--         lecture/écriture liée à la capacité consommée — exactement la
--         même ligne que create_credit_issuance()/submit_credit_issuance()
--         ci-dessus (section 6) ;
--      b. appelle public.carbon_capacity_consumed_for_session(p_verification_session_id)
--         (stub à ce stade, section 3 ci-dessus — 07 le remplacera plus
--         tard par l'implémentation réelle) pour obtenir la capacité déjà
--         consommée, et applique l'invariant bidirectionnel : REJETER si
--         p_eligible_tco2e < capacité déjà consommée, lors d'une
--         supersession (résultat actif déjà existant pour cette session) ;
--      c. garantit (trigger ou vérification directe) que supersedes_outcome_id,
--         s'il est renseigné, référence une ligne de LA MÊME
--         verification_session_id — jamais une supersession inter-session.
--   3. Seulement PLUS TARD, quand 07 est appliquée : la prévalidation en
--      section 0 ci-dessus exige que ce stub existe déjà (échec explicite
--      sinon), puis 07 le remplace par son implémentation réelle (section 3)
--      — sans jamais toucher au corps de complete_verification_session().
-- Tant que 05 n'existe pas, ce fichier 07 ne peut pas être appliqué du
-- tout (la prévalidation de section 0 s'y oppose), donc il n'y a aucun
-- état intermédiaire où carbon_capacity_consumed_for_session() serait
-- appelée par autre chose que le stub lui-même.

-- ────────────────────────────────────────────────────────────
-- 8. RLS (§15 point 6) — helper central can_view_credit_issuance() pour
--    éliminer la récursion RLS credit_issuances ↔ credit_issuance_sources
--    (revue statique 07, point 1).
-- ────────────────────────────────────────────────────────────

-- SECURITY DEFINER, exécuté avec les privilèges du propriétaire de la
-- fonction (qui ne subit pas RLS sur les tables qu'il possède) — centralise
-- TOUTE la logique de visibilité en un seul endroit, appelé identiquement
-- par les deux policies ci-dessous. Élimine les sous-requêtes croisées
-- directement dans les clauses USING (qui recréaient une récursion RLS,
-- même leçon que la correction de migration 01).
CREATE OR REPLACE FUNCTION public.can_view_credit_issuance(p_credit_issuance_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.credit_issuances ci
        WHERE ci.id = p_credit_issuance_id
          AND (
               COALESCE(public.is_platform_superadmin(), false)
               -- (correction 4, septième revue statique) : visibilité basée
               -- sur la simple appartenance à l'organisation opératrice
               -- FIGÉE (is_organization_member), PAS sur is_platform_operator_actor()
               -- qui exige en plus que cette organisation soit ENCORE
               -- l'opérateur ACTIF. Avant ce correctif, un transfert
               -- d'opérateur faisait perdre à l'ancien opérateur (OP_A) la
               -- visibilité de ses propres émissions historiques — alors
               -- même que ses admins conservent leurs droits RPC dessus en
               -- régime post-submission (is_org_admin(operator_organization_id)
               -- OR is_platform_superadmin(), indépendant de l'opérateur
               -- actif, cf. record_registry_issuance()/record_externally_rejected()/
               -- record_external_cancellation()). La visibilité doit être au
               -- moins aussi large que les droits d'action : n'importe quel
               -- membre (admin ou non) de l'opérateur figé voit l'émission,
               -- que cette organisation soit encore l'opérateur actif ou
               -- non — et le nouvel opérateur actif n'hérite PAS
               -- automatiquement de cette visibilité pour des émissions
               -- dont l'operator_organization_id figé reste l'ancien
               -- opérateur (is_organization_member ne matche que
               -- l'organisation réellement figée sur la ligne).
               OR COALESCE(public.is_organization_member(ci.operator_organization_id), false)
               OR COALESCE(public.is_aggregator_admin(ci.aggregator_id), false)
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

-- (correction 1, douzième revue statique) : FUITE RLS corrigée —
-- credit_issuance_sources_select réutilisait can_view_credit_issuance(),
-- qui rend TRUE dès qu'un appelant est membre de N'IMPORTE LAQUELLE des
-- organisations sources d'une émission (branche EXISTS ci-dessus, ligne
-- 2083). Appliqué comme USING de credit_issuance_sources_select, ce même
-- helper autorisait donc une organisation source A à lire TOUTES les
-- lignes credit_issuance_sources de l'émission — y compris celles d'une
-- organisation source B distincte (organization_id, contributed_tco2e,
-- aggregator_membership_id, commercialization_mandate_id de B) — alors que
-- l'architecture exige qu'une organisation source ne voie que sa PROPRE
-- contribution. Nouveau helper LIGNE PAR LIGNE : reçoit explicitement
-- l'organization_id de la ligne évaluée (fournie par la policy depuis la
-- ligne en cours, jamais relue — même discipline anti-récursion RLS que
-- can_view_carbon_event(), migration 01) et n'autorise un simple membre
-- d'organisation source qu'à voir SA PROPRE ligne. Les rôles privilégiés
-- (super-admin, opérateur figé, aggregator admin, vérificateur assigné)
-- continuent de voir toutes les sources d'une émission qu'ils peuvent
-- consulter, cohérent avec can_view_credit_issuance() ci-dessus pour la
-- table parent (logique dupliquée intentionnellement ici pour les 4
-- branches privilégiées — pas de dépendance croisée entre les deux
-- helpers, chacun reste autonome et lisible).
-- (correction 1, treizième revue statique) : la branche « organisation
-- contributrice ordinaire » testait UNIQUEMENT is_organization_member(p_source_organization_id),
-- sans jamais vérifier que p_source_organization_id est réellement une
-- source de p_credit_issuance_id. Appelée depuis la policy RLS
-- (credit_issuance_sources_select, qui fournit toujours la VRAIE
-- organization_id de la ligne évaluée), cette omission était invisible.
-- Mais la fonction est SECURITY DEFINER + GRANT EXECUTE à authenticated —
-- appelable DIRECTEMENT, hors de toute policy, avec des arguments
-- arbitraires. Un membre de l'organisation A, sans AUCUN lien avec
-- l'émission X, pouvait donc appeler can_view_credit_issuance_source(X, A)
-- et obtenir true dès lors que X existe (et A est bien son organisation
-- d'appartenance) — un pur ORACLE D'EXISTENCE sur credit_issuances,
-- indépendant de toute relation réelle. Corrigé en exigeant désormais une
-- vraie ligne credit_issuance_sources reliant les deux paramètres — la
-- fonction reste SECURITY DEFINER, cette lecture interne ne recrée donc
-- aucune récursion RLS (même principe que can_view_credit_issuance()
-- ci-dessus, qui lit déjà credit_issuance_sources en interne).
CREATE OR REPLACE FUNCTION public.can_view_credit_issuance_source(
    p_credit_issuance_id UUID,
    p_source_organization_id UUID
) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.credit_issuances ci
        WHERE ci.id = p_credit_issuance_id
          AND (
               COALESCE(public.is_platform_superadmin(), false)
               -- opérateur figé historique — même règle que can_view_credit_issuance().
               OR COALESCE(public.is_organization_member(ci.operator_organization_id), false)
               OR COALESCE(public.is_aggregator_admin(ci.aggregator_id), false)
               OR COALESCE(public.is_assigned_verifier(
                    (SELECT vo.verification_session_id FROM public.verification_outcomes vo WHERE vo.id = ci.verification_outcome_id)
                  ), false)
               -- Organisation contributrice ORDINAIRE : voit UNIQUEMENT sa
               -- propre ligne, et seulement si p_source_organization_id est
               -- RÉELLEMENT une source de CETTE émission précise (jamais un
               -- simple test d'appartenance organisationnelle déconnecté de
               -- toute relation avec p_credit_issuance_id).
               OR EXISTS (
                    SELECT 1 FROM public.credit_issuance_sources cis
                    WHERE cis.credit_issuance_id = ci.id
                      AND cis.organization_id = p_source_organization_id
                      AND COALESCE(public.is_organization_member(cis.organization_id), false)
                  )
          )
    )
$$;

ALTER TABLE public.credit_issuances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_issuance_sources ENABLE ROW LEVEL SECURITY;

CREATE POLICY credit_issuances_select ON public.credit_issuances
    FOR SELECT TO authenticated
    USING (public.can_view_credit_issuance(id));

CREATE POLICY credit_issuance_sources_select ON public.credit_issuance_sources
    FOR SELECT TO authenticated
    USING (public.can_view_credit_issuance_source(credit_issuance_id, organization_id));

-- ────────────────────────────────────────────────────────────
-- 9. PRIVILÈGES — jamais PUBLIC seul (leçon 06a), explicite anon/authenticated.
-- ────────────────────────────────────────────────────────────

REVOKE ALL ON TABLE public.credit_issuances FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.credit_issuances TO authenticated;

REVOKE ALL ON TABLE public.credit_issuance_sources FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.credit_issuance_sources TO authenticated;

-- Fonctions RPC exposées, authenticated seul.
REVOKE ALL ON FUNCTION public.is_platform_operator_actor(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_operator_actor(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.is_platform_operator_admin(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_operator_admin(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.create_credit_issuance(UUID, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_credit_issuance(UUID, JSONB) TO authenticated;

REVOKE ALL ON FUNCTION public.mark_credit_issuance_eligible(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_credit_issuance_eligible(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.submit_credit_issuance(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_credit_issuance(UUID, TEXT) TO authenticated;

-- (correction 2, septième revue statique) : signature étendue avec
-- p_registry_issued_at TIMESTAMPTZ (paramètre obligatoire).
REVOKE ALL ON FUNCTION public.record_registry_issuance(UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_registry_issuance(UUID, TEXT, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.record_externally_rejected(UUID, DATE, TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_externally_rejected(UUID, DATE, TEXT, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.void_credit_issuance(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.void_credit_issuance(UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.record_external_cancellation(UUID, DATE, TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_external_cancellation(UUID, DATE, TEXT, UUID) TO authenticated;

-- Helper RLS central : EXECUTE requis pour authenticated (invoqué depuis
-- les clauses USING des policies, évaluées en tant que l'appelant réel).
REVOKE ALL ON FUNCTION public.can_view_credit_issuance(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_credit_issuance(UUID) TO authenticated;

-- (correction 1, douzième revue statique) : même motif que ci-dessus —
-- invoqué depuis la clause USING de credit_issuance_sources_select.
REVOKE ALL ON FUNCTION public.can_view_credit_issuance_source(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_credit_issuance_source(UUID, UUID) TO authenticated;

-- Fonctions purement internes — AUCUN GRANT EXECUTE à authenticated
-- (correction 8, revue statique 07) : carbon_capacity_consumed_for_session()
-- et carbon_is_source_organization_valid() ne sont appelées que depuis
-- d'autres fonctions SECURITY DEFINER de ce même fichier (create_credit_issuance(),
-- les triggers de cohérence/capacité) — leur propriétaire dispose déjà
-- implicitement d'EXECUTE sur ses propres objets, aucun GRANT explicite à
-- authenticated n'est nécessaire ni souhaitable (surface d'appel direct
-- minimale, defense in depth).
REVOKE ALL ON FUNCTION public.carbon_capacity_consumed_for_session(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.carbon_is_source_organization_valid(UUID, UUID) FROM PUBLIC, anon, authenticated;
-- (correction 3, dixième revue statique) : nouveau helper centralisé.
REVOKE ALL ON FUNCTION public.carbon_lock_and_validate_source_organization(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- Fonctions purement internes (triggers) : aucun GRANT EXECUTE — invoquées
-- uniquement par le mécanisme de trigger, jamais destinées à un appel RPC direct.
REVOKE ALL ON FUNCTION public.carbon_validate_credit_issuance_source() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.carbon_validate_credit_issuance_sources_sum() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.carbon_credit_issuances_before_update() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.carbon_validate_credit_issuance_capacity() FROM PUBLIC, anon, authenticated;
-- (correction 4, cinquième revue statique) : nouveaux triggers d'historisation.
REVOKE ALL ON FUNCTION public.carbon_credit_issuances_forbid_delete() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.carbon_credit_issuance_sources_forbid_write() FROM PUBLIC, anon, authenticated;
-- (corrections 5/6, sixième revue statique) : nouveaux triggers.
REVOKE ALL ON FUNCTION public.carbon_credit_issuances_before_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.carbon_validate_credit_issuance_has_sources() FROM PUBLIC, anon, authenticated;
-- (correction 2, dixième revue statique) : nouveau trigger platform_operators.
REVOKE ALL ON FUNCTION public.carbon_platform_operators_before_revoke() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ============================================================
-- ROLLBACK (à exécuter séparément, jamais collé avec ce qui précède) —
-- RÉÉCRIT INTÉGRALEMENT (correction 4, dixième revue statique) : la version
-- précédente (a) DROPpait carbon_capacity_consumed_for_session(UUID) sans
-- condition, cassant contractuellement la migration 05 (qui en dépend via
-- complete_verification_session() — voir section 7 ci-dessus, contrat
-- 05→07→05) ; (b) omettait le DROP explicite des fonctions de TRIGGER,
-- laissées orphelines après le DROP TABLE (une table entraîne la
-- suppression de SES triggers, jamais des fonctions qu'ils invoquent — ce
-- sont des objets distincts) ; (c) ne mentionnait pas le nouveau trigger sur
-- platform_operators (table de la migration 06, qui SURVIT à ce rollback —
-- seul son trigger 07 doit être retiré, explicitement, jamais la table).
--
-- RÉORDONNÉ (correction 3, douzième revue statique) : l'ordre précédent
-- DROPpait can_view_credit_issuance() (étape « Helper RLS ») AVANT le DROP
-- des tables — mais les policies credit_issuances_select/
-- credit_issuance_sources_select, posées SUR ces tables encore existantes à
-- ce stade, référencent encore cette fonction dans leur clause USING.
-- PostgreSQL enregistre une dépendance (pg_depend) entre une policy et les
-- fonctions qu'elle appelle, exactement comme pour une vue : DROP FUNCTION
-- sans CASCADE aurait donc échoué ici avec « cannot drop function ... because
-- other objects depend on it ». Nouvel ordre : policies retirées
-- explicitement en premier (avant tout DROP FUNCTION), tables seulement
-- ensuite — plus aucune dépendance résiduelle à aucune étape.
--
-- BEGIN;
--
-- -- 1) RPC (7).
-- DROP FUNCTION IF EXISTS public.record_external_cancellation(UUID, DATE, TEXT, UUID);
-- DROP FUNCTION IF EXISTS public.void_credit_issuance(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.record_externally_rejected(UUID, DATE, TEXT, UUID);
-- DROP FUNCTION IF EXISTS public.record_registry_issuance(UUID, TEXT, TIMESTAMPTZ);
-- DROP FUNCTION IF EXISTS public.submit_credit_issuance(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.mark_credit_issuance_eligible(UUID);
-- DROP FUNCTION IF EXISTS public.create_credit_issuance(UUID, JSONB);
--
-- -- 2) Policies — retirées EXPLICITEMENT ici, avant tout DROP FUNCTION,
-- --    pour lever leur dépendance sur les helpers RLS (voir note ci-dessus).
-- --    credit_issuance_sources_select d'abord (table enfant), puis
-- --    credit_issuances_select (table parent) — ordre sans portée
-- --    fonctionnelle ici (deux tables distinctes, aucune dépendance entre
-- --    les deux policies elles-mêmes), conservé par symétrie avec l'ordre
-- --    de DROP TABLE plus bas.
-- DROP POLICY IF EXISTS credit_issuance_sources_select ON public.credit_issuance_sources;
-- DROP POLICY IF EXISTS credit_issuances_select ON public.credit_issuances;
--
-- -- 3) carbon_capacity_consumed_for_session(UUID) — JAMAIS DROPpée : elle
-- --    appartient contractuellement au modèle 05→07 (section 7 ci-dessus) :
-- --    05 crée D'ABORD le stub (renvoie 0 sans condition), complete_verification_session()
-- --    (05) en dépend structurellement, PUIS 07 le remplace par son
-- --    implémentation réelle (CREATE OR REPLACE, section 3). Un rollback de
-- --    07 qui la supprimerait laisserait complete_verification_session()
-- --    (05, restée en place) dépendre d'une fonction inexistante — cassant
-- --    la migration PRÉCÉDENTE, jamais acceptable pour le rollback d'une
-- --    migration ultérieure. Restaurée ici à sa version STUB, telle que
-- --    documentée section 7 (signature/langage identiques à
-- --    l'implémentation réelle qu'elle remplace, corps réduit à 0) —
-- --    privilèges internes, aucun GRANT EXECUTE à authenticated, cohérent
-- --    avec le reste des helpers internes de ce fichier. Placée ici plutôt
-- --    qu'en toute fin (correction 3, douzième revue statique) : ce stub
-- --    est indépendant des tables/policies de 07, sa position exacte dans
-- --    le rollback n'a pas d'importance fonctionnelle, mais la regrouper
-- --    avec les autres restaurations/nettoyages plutôt que de la laisser
-- --    isolée après les DROP TABLE améliore la lisibilité de l'ordre global.
-- CREATE OR REPLACE FUNCTION public.carbon_capacity_consumed_for_session(p_verification_session_id UUID)
-- RETURNS NUMERIC
-- LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
-- AS $stub$ SELECT 0::NUMERIC $stub$;
-- REVOKE ALL ON FUNCTION public.carbon_capacity_consumed_for_session(UUID) FROM PUBLIC, anon, authenticated;
--
-- -- 4) Helpers RLS référençant credit_issuances/credit_issuance_sources —
-- --    les policies qui les invoquaient sont déjà retirées (étape 2),
-- --    aucune dépendance résiduelle : DROP FUNCTION direct, sans CASCADE.
-- --    can_view_credit_issuance_source() (correction 1, douzième revue
-- --    statique) retirée ici au même endroit que can_view_credit_issuance().
-- DROP FUNCTION IF EXISTS public.can_view_credit_issuance_source(UUID, UUID);
-- DROP FUNCTION IF EXISTS public.can_view_credit_issuance(UUID);
--
-- -- 5) Tables — entraîne la suppression de LEURS triggers (pas des
-- --    fonctions invoquées par ces triggers, voir 6 ci-dessous) ni de leurs
-- --    policies (déjà retirées explicitement à l'étape 2, mais la
-- --    suppression de la table les aurait de toute façon emportées
-- --    automatiquement — l'ordre choisi ici sert uniquement à lever la
-- --    dépendance des fonctions RLS AVANT leur propre DROP, étape 4).
-- DROP TABLE IF EXISTS public.credit_issuance_sources;
-- DROP TABLE IF EXISTS public.credit_issuances;
--
-- -- 6) Fonctions de TRIGGER laissées orphelines par le DROP TABLE ci-dessus
-- --    — propres à credit_issuances/credit_issuance_sources, sans usage en
-- --    dehors de ce fichier, DROP sans condition.
-- DROP FUNCTION IF EXISTS public.carbon_validate_credit_issuance_source();
-- DROP FUNCTION IF EXISTS public.carbon_credit_issuance_sources_forbid_write();
-- DROP FUNCTION IF EXISTS public.carbon_validate_credit_issuance_sources_sum();
-- DROP FUNCTION IF EXISTS public.carbon_credit_issuances_before_insert();
-- DROP FUNCTION IF EXISTS public.carbon_credit_issuances_before_update();
-- DROP FUNCTION IF EXISTS public.carbon_credit_issuances_forbid_delete();
-- DROP FUNCTION IF EXISTS public.carbon_validate_credit_issuance_capacity();
-- DROP FUNCTION IF EXISTS public.carbon_validate_credit_issuance_has_sources();
--
-- -- 7) Helpers internes propres à 07 (sans usage en dehors) — DROP sans condition.
-- DROP FUNCTION IF EXISTS public.carbon_lock_and_validate_source_organization(UUID, UUID);
-- DROP FUNCTION IF EXISTS public.carbon_is_source_organization_valid(UUID, UUID);
-- DROP FUNCTION IF EXISTS public.is_platform_operator_admin(UUID);
-- DROP FUNCTION IF EXISTS public.is_platform_operator_actor(UUID);
--
-- -- 8) Trigger sur platform_operators (correction 2, dixième revue
-- --    statique) — platform_operators appartient à la migration 06, DÉJÀ
-- --    APPLIQUÉE EN PRODUCTION : seul le TRIGGER posé par 07 est retiré ici,
-- --    JAMAIS la table elle-même (absente de ce rollback, volontairement).
-- DROP TRIGGER IF EXISTS trg_carbon_platform_operators_before_revoke ON public.platform_operators;
-- DROP FUNCTION IF EXISTS public.carbon_platform_operators_before_revoke();
--
-- -- 9) Catalogue event_type (section 0bis) : CHOIX DOCUMENTÉ — PAS de
-- --    rollback automatique. Retirer credit_issuance_marked_eligible/
-- --    credit_issuance_externally_rejected (ajoutées 35→37) de la contrainte
-- --    exigerait de reconstruire tout son texte à la main (DROP CONSTRAINT +
-- --    CHECK réécrit avec les 35 valeurs d'origine). Laisser ces deux
-- --    valeurs au catalogue après ce rollback est SANS DANGER : colonne
-- --    applicative d'un CHECK, aucune ligne ne les référencera après le DROP
-- --    TABLE ci-dessus (credit_issuances/credit_issuance_sources, seules
-- --    tables qui auraient pu écrire ces event_type, sont déjà supprimées).
-- --    Restaurer strictement 37→35 resterait possible manuellement si
-- --    exigé, mais n'est délibérément PAS automatisé ici.
--
-- COMMIT;
-- ============================================================
