-- ============================================================
-- Migration carbone 06/09 — Opérateur METALTRACE central (platform_operators)
-- et mandats de commercialisation (carbon_commercialization_mandates)
-- ============================================================
--
-- PROPOSITION NON APPLIQUÉE. Ce fichier vit délibérément hors de
-- supabase/migrations/ pour qu'aucun `supabase db push` ne puisse
-- l'appliquer par inadvertance. À lire, réviser et approuver avant
-- toute exécution manuelle dans le SQL Editor Supabase.
--
-- Réfère à : Tranche0-Carbone-Architecture.md §13 (décision METALTRACE
-- vendeur/opérateur central) et §14 (plan de migration détaillé, qui fige
-- la renumérotation 04-09 — `03` reste définitivement le correctif de
-- sécurité `03_fix_null_bypass_authorization.sql`, déjà appliqué).
--
-- PRÉREQUIS : migrations 01 (fondations) et 02 (aggregator_memberships)
-- déjà appliquées avec succès (22/22 puis 56/56, voir ADR-MVP.md §12-§13).
-- Le correctif 03 également appliqué. Les migrations 04/05 (liens CCF-MRV,
-- vérification) ne sont PAS un prérequis de celle-ci — cette migration ne
-- dépend que de 01/02, conformément à §14 (« aucune dépendance amont autre
-- que 01/02 »).
--
-- ⚠ ORDRE OBLIGATOIRE, SANS EXCEPTION (revue du 14 juillet 2026, point 2) :
-- 1. Appliquer cette migration.
-- 2. Exécuter tests/06_test_operator_and_mandates.sql — CE SCRIPT EXIGE ET
--    VÉRIFIE que public.platform_operators est ENTIÈREMENT VIDE avant de
--    commencer (précondition dure, arrêt immédiat sinon). Les tests
--    désignent puis révoquent des opérateurs FICTIFS via
--    designate_platform_operator()/revoke_platform_operator() — si un
--    véritable opérateur METALTRACE avait déjà été désigné avant ce script,
--    ces appels le révoqueraient IRRÉVERSIBLEMENT (la RPC révoque
--    automatiquement l'opérateur actif courant, quel qu'il soit, pour en
--    désigner un nouveau).
-- 3. Confirmer le succès complet (62/62, voir en-tête du fichier de test).
-- 4. SEULEMENT APRÈS confirmation : désigner le véritable opérateur
--    METALTRACE via un appel séparé à designate_platform_operator(), en
--    dehors de tout script de test.
-- Ne jamais réexécuter le script de test après l'étape 4 sur le même
-- environnement — il échouerait à sa précondition (par construction), ce
-- qui est le comportement voulu, pas un bug à contourner.
--
-- ────────────────────────────────────────────────────────────
-- DÉCISIONS DE CONCEPTION SOUMISES À REVUE (préfixées D, comme les
-- migrations précédentes) :
--
-- D1. `platform_operators` est un HISTORIQUE de désignation/révocation
--     (table append-only avec transition unique, même patron que
--     `aggregator_memberships`), PAS un booléen simple sur `organizations`
--     — corrigé après une première proposition (§13 initial) qui avait
--     suggéré `organizations.is_platform_operator BOOLEAN`, jugée
--     insuffisante : un booléen sur `organizations` n'aurait gardé aucune
--     trace de qui a désigné/révoqué, quand, ni pourquoi, et n'aurait pas
--     pu supporter une future exigence d'audit sur les transitions
--     d'opérateur (rare mais réglementairement sensible).
--
-- D2. Invariant MVP : AU PLUS un opérateur actif à la fois (pas
--     nécessairement exactement un — la plateforme peut transitoirement
--     n'avoir aucun opérateur désigné, ce qui bloque simplement la
--     création de nouveaux mandats/ventes jusqu'à la prochaine désignation,
--     sans que ce soit une erreur de schéma). Appliqué par un index unique
--     partiel sur une expression constante (`(true)`), pattern standard
--     PostgreSQL pour « au plus une ligne qualifiante », puisqu'il n'existe
--     ici aucune colonne de regroupement naturelle (contrairement à
--     `idx_one_active_primary_admin`, qui est unique PAR aggregator_id).
--
-- D3. `is_platform_operator(p_organization_id UUID)` répond à une question
--     sur une ORGANISATION, jamais sur l'utilisateur courant — à ne pas
--     confondre avec `is_platform_superadmin()` (question sur l'appelant).
--     Construite avec `EXISTS(...)`, donc structurellement non-`NULL` —
--     leçon tirée du correctif 03 (`is_platform_superadmin()` pouvait
--     renvoyer `NULL` et contourner un garde `IF NOT (...)`) : ne pas se
--     contenter d'un `COALESCE` ajouté après coup, construire la fonction
--     pour qu'elle ne PUISSE PAS renvoyer `NULL`.
--
-- D4. `designate_platform_operator()`/`revoke_platform_operator()` réservées
--     à `is_platform_superadmin()` — aucune autre voie de désignation.
--     `designate_platform_operator()` effectue le transfert complet en une
--     transaction (révoque l'actif courant s'il existe, puis désigne le
--     nouveau) plutôt que d'exiger deux appels séparés — élimine tout état
--     intermédiaire à zéro opérateur lors d'un simple remplacement.
--
-- D5. `carbon_commercialization_mandates` reste un objet DISTINCT de
--     `aggregator_memberships` (une organisation peut être membre d'un
--     regroupement sans avoir encore mandaté METALTRACE) mais rattaché à
--     une ADHÉSION PRÉCISE (`aggregator_membership_id`), pas au couple
--     `(organization_id, aggregator_id)` — pour qu'un ancien mandat ne
--     puisse jamais s'appliquer silencieusement à une nouvelle adhésion
--     après un départ puis un retour dans le même regroupement (nouvelle
--     ligne `aggregator_memberships` = nouvel identifiant = aucun mandat
--     existant ne s'y rattache tant qu'un nouveau n'est pas accordé
--     explicitement). La révocation du mandat ne met pas fin à l'adhésion,
--     et réciproquement.
--
-- D6. `organization_id`/`aggregator_id` sont dénormalisées sur
--     `carbon_commercialization_mandates` (dérivables de
--     `aggregator_membership_id`, mais stockées explicitement pour la
--     lisibilité des requêtes/RLS) — leur cohérence EXACTE avec l'adhésion
--     référencée est imposée par un trigger `BEFORE INSERT`, jamais
--     acceptée telle que fournie par l'appelant. La RPC
--     `grant_commercialization_mandate()` ne les accepte d'ailleurs PAS en
--     paramètres séparés : elle les DÉRIVE de `p_aggregator_membership_id`
--     — élimine par construction toute possibilité d'incohérence fournie
--     par l'appelant, le trigger restant une seconde ligne de défense pour
--     toute autre voie d'insertion hypothétique.
--
-- D7. L'opérateur (`operator_organization_id`) doit être l'opérateur
--     ACTIF au moment précis de la création du mandat (validé par le même
--     trigger, via `is_platform_operator()`), mais son identité reste
--     ensuite FIGÉE indéfiniment sur le mandat — y compris si cet
--     opérateur est révoqué/remplacé plus tard. Un mandat existant ne
--     change jamais rétroactivement de bénéficiaire.
--
-- D8. `scope` : catalogue FERMÉ (`CHECK ... <@ ARRAY[...]`), jamais de
--     texte libre, SANS DOUBLON (revue du 14 juillet 2026, point 4 —
--     vérifié dans le trigger de validation, pas dans un `CHECK` déclaratif :
--     détecter des doublons dans un tableau exige `unnest()`/`count()`, qui
--     nécessitent une sous-requête, interdite dans un `CHECK` PostgreSQL —
--     PL/pgSQL n'a pas cette restriction). IMMUABLE après création — toute
--     évolution du périmètre du mandat exige une révocation suivie d'un
--     nouveau mandat, jamais un `UPDATE` du scope existant (même garde-fou
--     de transition unique que `aggregator_memberships`/migration 02 :
--     seule `revoked_at` NULL → valeur est permise, `DELETE` interdit via
--     `carbon_reject_update_delete()`).
--
-- D9. RÉVISÉE après revue du 14 juillet 2026 (point 3, bloquant) —
--     `grant_commercialization_mandate()` est désormais réservée
--     STRICTEMENT à `is_org_admin()` de l'organisation titulaire de
--     l'adhésion, SANS dérogation super-admin. L'octroi d'un mandat est un
--     acte de volonté de l'organisation elle-même (consentement à ce que
--     METALTRACE commercialise en son nom) — un super-admin ne doit
--     jamais pouvoir créer ce consentement au nom d'un membre sans preuve.
--     `revoke_commercialization_mandate()` CONSERVE la dérogation
--     super-admin (intervention opérationnelle légitime, ex. réponse à un
--     abus, sans dépendre du consentement en temps réel de l'organisation).
--     Une future RPC distincte (hors périmètre de cette migration) pourra
--     enregistrer un mandat signé hors plateforme, réservée au super-admin,
--     avec `mandate_document_id` rendu OBLIGATOIRE dans ce cas précis (preuve
--     documentaire compensant l'absence de consentement en direct).
--
-- D10. Catalogue `carbon_business_events` étendu de 31 à 35 valeurs
--      (`platform_operator_designated`, `platform_operator_revoked`,
--      `carbon_commercialization_mandate_granted`,
--      `carbon_commercialization_mandate_revoked`) et `object_type` de 12
--      à 14 (`platform_operator`, `carbon_commercialization_mandate`) —
--      `DROP CONSTRAINT`/`ADD CONSTRAINT` explicite après vérification en
--      direct du contenu actuel (section 0), jamais une hypothèse tirée de
--      la migration 01 seule.
--
-- D11. CORRECTIF BLOQUANT (revue du 14 juillet 2026, point 1) — la policy
--      RLS `SELECT` de `carbon_commercialization_mandates` utilisait
--      `is_platform_operator(operator_organization_id)`, qui vérifie
--      seulement que l'ORGANISATION référencée est l'opérateur actif — PAS
--      que l'utilisateur courant en fait partie. Conséquence réelle :
--      puisque `operator_organization_id` est TOUJOURS l'opérateur actif au
--      moment de la création d'un mandat (validé par le trigger, D7), cette
--      condition était vraie pour PRESQUE CHAQUE ligne, indépendamment de
--      l'identité de l'appelant — ouvrant de facto la lecture de tous les
--      mandats à tout utilisateur `authenticated`. Corrigé par un nouveau
--      helper dédié, `is_active_platform_operator_member(p_organization_id)`,
--      qui vérifie CONJOINTEMENT que l'organisation est l'opérateur actif
--      ET que l'appelant en est membre (`is_organization_member()`).
--
-- D12. `p_mandate_document_id` validé SÉMANTIQUEMENT dans
--      `grant_commercialization_mandate()` (revue du 14 juillet 2026, point
--      5), pas seulement par la FK vers `documents(id)` (qui garantit
--      seulement qu'UN document existe quelque part, pas qu'il appartient à
--      la bonne organisation) : si fourni, doit référencer un document dont
--      `owner_org_id` correspond à l'organisation titulaire de l'adhésion —
--      rejeté explicitement sinon.
--
-- D13. CORRECTIF BLOQUANT (dernière revue, 14 juillet 2026, points 1-2) —
--      fuite d'existence dans les deux RPC SECURITY DEFINER d'écriture.
--      Avant correctif, `grant_commercialization_mandate()` recherchait
--      l'adhésion PUIS vérifiait l'autorisation séparément (deux messages
--      distincts : « adhésion introuvable » vs « accès refusé ») — un
--      appelant non autorisé pouvait donc distinguer par essais successifs
--      quels `p_aggregator_membership_id` existent réellement en base, sans
--      jamais y avoir droit. Même défaut dans `revoke_commercialization_mandate()`
--      pour `p_mandate_id`. Corrigé en FUSIONNANT la recherche et
--      l'autorisation dans la même clause `WHERE` (respectivement
--      `... AND COALESCE(is_org_admin(organization_id), false)` et
--      `... AND (COALESCE(is_org_admin(organization_id), false) OR
--      COALESCE(is_platform_superadmin(), false))`), avec un message
--      d'erreur unique dans chaque cas : `'Adhésion introuvable ou accès
--      refusé.'` et `'Mandat introuvable ou accès refusé.'` — indistinguable
--      qu'il s'agisse d'un UUID inexistant ou d'un enregistrement existant
--      mais inaccessible.
--
-- D14. `is_active_platform_operator_member()` durcie avec
--      `COALESCE(is_organization_member(...), false)` (dernière revue, point
--      3) : `is_platform_operator()` est déjà structurellement non-NULL
--      (EXISTS-based, D3), mais `is_organization_member()` est un helper
--      externe préexistant dont la garantie de non-nullité n'est pas sous le
--      contrôle direct de cette migration — le `COALESCE` élimine toute
--      dépendance implicite à son comportement NULL.
--
-- D15. CORRECTIF BLOQUANT (dernière revue, 14 juillet 2026, point unique) —
--      incohérence temporelle dans `designate_platform_operator()`. Le
--      transfert utilisait `clock_timestamp()` pour `revoked_at` de
--      l'ancien opérateur (réévalué à chaque appel) mais laissait
--      `designated_at`/`created_at` du nouveau retomber sur le `DEFAULT
--      now()` de la table — `now()` est figé au DÉBUT DE LA TRANSACTION,
--      jamais réévalué, donc potentiellement ANTÉRIEUR au
--      `clock_timestamp()` utilisé pour la révocation dans la même
--      transaction. Un transfert pouvait ainsi produire un historique
--      chronologiquement incohérent (le nouvel opérateur apparaissant
--      désigné avant la révocation de l'ancien). Corrigé par une variable
--      unique `v_transition_at := clock_timestamp()`, capturée UNE SEULE
--      FOIS immédiatement après le verrouillage (`FOR UPDATE`) de
--      l'opérateur courant, et réutilisée identiquement pour
--      `OLD.revoked_at`, `NEW.designated_at` et `NEW.created_at` — plus
--      aucune dérive possible entre les deux écritures.
--
-- Résultat final attendu du script de test associé : voir en-tête du
-- fichier de test séparé.
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION DU SCHÉMA RÉEL — introspection catalogue, pas hypothèse
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_constraint_def TEXT;
BEGIN
    -- Tables prérequises.
    IF to_regclass('public.organizations') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.organizations introuvable.';
    END IF;
    IF to_regclass('public.profiles') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.profiles introuvable.';
    END IF;
    IF to_regclass('public.aggregators') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.aggregators introuvable.';
    END IF;
    IF to_regclass('public.documents') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.documents introuvable.';
    END IF;
    IF to_regclass('public.aggregator_memberships') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.aggregator_memberships introuvable — migration 02 appliquée ?';
    END IF;
    IF to_regclass('public.carbon_business_events') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_business_events introuvable — migration 01 appliquée ?';
    END IF;

    -- aggregator_memberships : colonnes exactes attendues (migration 02).
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'aggregator_memberships' AND column_name = 'organization_id'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'aggregator_memberships' AND column_name = 'aggregator_id'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'aggregator_memberships' AND column_name = 'ended_at'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : aggregator_memberships n''a pas les colonnes organization_id/aggregator_id/ended_at attendues.';
    END IF;

    -- documents.id : existence de la colonne (type non revérifié ici, la FK suffira à le garantir).
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'documents' AND column_name = 'id'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : documents.id introuvable.';
    END IF;

    -- documents.owner_org_id : existence ET type UUID revérifiés explicitement
    -- (renforcement demandé en dernière revue) — grant_commercialization_mandate()
    -- s'appuie désormais dessus pour la validation sémantique de
    -- p_mandate_document_id (D12 : EXISTS(... WHERE id = p_mandate_document_id
    -- AND owner_org_id = v_organization_id)). Une colonne absente ou d'un
    -- type différent d'UUID ferait échouer cette comparaison silencieusement
    -- ou avec une erreur de type opaque au moment de l'exécution de la RPC,
    -- plutôt qu'un message de prévalidation clair.
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'documents'
          AND column_name = 'owner_org_id' AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : documents.owner_org_id introuvable ou n''est pas de type UUID — requis par grant_commercialization_mandate() (D12).';
    END IF;

    -- Fonctions helper exactes.
    IF to_regprocedure('public.is_platform_superadmin()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_platform_superadmin() introuvable avec la signature exacte attendue.';
    END IF;
    IF to_regprocedure('public.is_org_admin(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_org_admin(uuid) introuvable avec la signature exacte attendue.';
    END IF;
    IF to_regprocedure('public.is_organization_member(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_organization_member(uuid) introuvable avec la signature exacte attendue.';
    END IF;
    IF to_regprocedure('public.is_aggregator_admin(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_aggregator_admin(uuid) introuvable avec la signature exacte attendue.';
    END IF;
    IF to_regprocedure('public.carbon_reject_update_delete()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_reject_update_delete() introuvable — migration 01 appliquée ?';
    END IF;

    -- Aucune collision de nom avec les nouveaux objets.
    IF to_regclass('public.platform_operators') IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.platform_operators existe déjà — cette migration a-t-elle déjà été appliquée ?';
    END IF;
    IF to_regclass('public.carbon_commercialization_mandates') IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.carbon_commercialization_mandates existe déjà — cette migration a-t-elle déjà été appliquée ?';
    END IF;

    -- Contrainte event_type de carbon_business_events : exactement 31 valeurs
    -- connues aujourd'hui (migration 01), AUCUNE des 4 nouvelles valeurs déjà
    -- présente (sans quoi cette migration aurait déjà partiellement tourné).
    SELECT pg_get_constraintdef(c.oid) INTO v_constraint_def
    FROM pg_constraint c
    WHERE c.conrelid = 'public.carbon_business_events'::regclass
      AND c.conname = 'carbon_business_events_event_type_check';

    IF v_constraint_def IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : contrainte carbon_business_events_event_type_check introuvable.';
    END IF;
    IF v_constraint_def NOT LIKE '%aggregator_created%'
       OR v_constraint_def NOT LIKE '%credit_sale_allocation_paid%' THEN
        RAISE EXCEPTION 'Prévalidation échouée : carbon_business_events_event_type_check ne correspond pas au catalogue à 31 valeurs attendu de la migration 01.';
    END IF;
    IF v_constraint_def LIKE '%platform_operator_designated%'
       OR v_constraint_def LIKE '%carbon_commercialization_mandate_granted%' THEN
        RAISE EXCEPTION 'Prévalidation échouée : le catalogue event_type contient déjà les valeurs de cette migration — déjà appliquée ?';
    END IF;

    -- Contrainte object_type : idem, 12 valeurs connues, aucune des 2 nouvelles.
    SELECT pg_get_constraintdef(c.oid) INTO v_constraint_def
    FROM pg_constraint c
    WHERE c.conrelid = 'public.carbon_business_events'::regclass
      AND c.conname = 'carbon_business_events_object_type_check';

    IF v_constraint_def IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : contrainte carbon_business_events_object_type_check introuvable.';
    END IF;
    IF v_constraint_def NOT LIKE '%aggregator_admin%'
       OR v_constraint_def NOT LIKE '%credit_sale_allocation%' THEN
        RAISE EXCEPTION 'Prévalidation échouée : carbon_business_events_object_type_check ne correspond pas au catalogue à 12 valeurs attendu de la migration 01.';
    END IF;
    IF v_constraint_def LIKE '%platform_operator%' THEN
        RAISE EXCEPTION 'Prévalidation échouée : le catalogue object_type contient déjà des valeurs de cette migration — déjà appliquée ?';
    END IF;

    RAISE NOTICE 'Prévalidation réussie : schéma réel conforme aux hypothèses de cette migration.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. EXTENSION DES CATALOGUES carbon_business_events (D10)
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.carbon_business_events
    DROP CONSTRAINT carbon_business_events_event_type_check;

ALTER TABLE public.carbon_business_events
    ADD CONSTRAINT carbon_business_events_event_type_check
    CHECK (event_type IN (
        -- 31 valeurs existantes (migration 01), inchangées.
        'aggregator_created',
        'aggregator_membership_started',
        'aggregator_membership_ended',
        'aggregator_admin_appointed',
        'aggregator_admin_revoked',
        'aggregator_primary_admin_transferred',
        'ccf_mrv_link_started',
        'ccf_mrv_link_ended',
        'verification_session_started',
        'verification_session_completed',
        'verification_outcome_recorded',
        'verification_outcome_superseded',
        'credit_issuance_created',
        'credit_issuance_submitted',
        'credit_issuance_issued',
        'credit_issuance_externally_cancelled',
        'credit_issuance_voided',
        'credit_lot_issued',
        'credit_lot_reserved',
        'credit_lot_sold',
        'credit_lot_retired',
        'credit_lot_voided',
        'credit_sale_created',
        'credit_sale_cost_recorded',
        'credit_sale_confirmed',
        'credit_sale_cancelled',
        'credit_sale_settled',
        'credit_sale_adjustment_recorded',
        'credit_sale_allocation_recorded',
        'credit_sale_allocation_approved',
        'credit_sale_allocation_paid',
        -- 4 nouvelles valeurs (cette migration, D10).
        'platform_operator_designated',
        'platform_operator_revoked',
        'carbon_commercialization_mandate_granted',
        'carbon_commercialization_mandate_revoked'
        -- Total : 31 + 4 = 35 valeurs exactement.
    ));

ALTER TABLE public.carbon_business_events
    DROP CONSTRAINT carbon_business_events_object_type_check;

ALTER TABLE public.carbon_business_events
    ADD CONSTRAINT carbon_business_events_object_type_check
    CHECK (object_type IN (
        -- 12 valeurs existantes (migration 01), inchangées.
        'aggregator',
        'aggregator_membership',
        'aggregator_admin',
        'ccf_mrv_project_link',
        'verification_session',
        'verification_outcome',
        'credit_issuance',
        'credit_lot',
        'credit_sale',
        'credit_sale_cost',
        'credit_sale_adjustment',
        'credit_sale_allocation',
        -- 2 nouvelles valeurs (cette migration, D10).
        'platform_operator',
        'carbon_commercialization_mandate'
        -- Total : 12 + 2 = 14 valeurs exactement.
    ));

-- ────────────────────────────────────────────────────────────
-- 2. TABLE platform_operators — historique de désignation (D1, D2)
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.platform_operators (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    designated_by   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    designated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at      TIMESTAMPTZ NULL,
    revoked_by      UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    revoke_reason   TEXT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT platform_operators_revoked_after_designated
        CHECK (revoked_at IS NULL OR revoked_at >= designated_at)
);

COMMENT ON TABLE public.platform_operators IS
  'Historique des désignations/révocations de l''entité juridique autorisée à '
  'agir comme opérateur/vendeur carbone central METALTRACE (Tranche0-Carbone-'
  'Architecture.md §13/§14, D1). Jamais un simple booléen sur organizations — '
  'chaque transition est tracée (qui, quand, pourquoi). Append-only, une seule '
  'transition permise (revoked_at NULL -> valeur), voir triggers ci-dessous.';

-- D2 : au plus un opérateur ACTIF à la fois. Index sur une expression
-- constante — pattern standard PostgreSQL pour « au plus une ligne
-- qualifiante » quand aucune colonne de regroupement naturelle n'existe
-- (contrairement à idx_one_active_primary_admin, unique PAR aggregator_id).
CREATE UNIQUE INDEX idx_one_active_platform_operator
    ON public.platform_operators ((true))
    WHERE revoked_at IS NULL;

CREATE INDEX idx_platform_operators_organization_id ON public.platform_operators (organization_id);

-- Garde de transition unique — même patron que carbon_guard_aggregator_membership_update() (migration 02).
CREATE OR REPLACE FUNCTION public.carbon_guard_platform_operator_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'platform_operators : une désignation déjà révoquée (revoked_at renseigné) est immuable, aucune modification supplémentaire n''est permise.';
    END IF;

    IF NEW.revoked_at IS NULL THEN
        RAISE EXCEPTION 'platform_operators : seule la transition de revoked_at de NULL vers une valeur (révocation) est permise.';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.designated_by IS DISTINCT FROM OLD.designated_by
       OR NEW.designated_at IS DISTINCT FROM OLD.designated_at
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION 'platform_operators : seules revoked_at, revoked_by et revoke_reason peuvent être renseignées à la révocation — aucune autre colonne ne peut changer.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER platform_operators_guard_update
    BEFORE UPDATE ON public.platform_operators
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_platform_operator_update();

CREATE TRIGGER platform_operators_reject_delete
    BEFORE DELETE ON public.platform_operators
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 3. is_platform_operator(uuid) — EXISTS-based, jamais NULL (D3)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_platform_operator(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.platform_operators
        WHERE organization_id = p_organization_id AND revoked_at IS NULL
    )
$$;

COMMENT ON FUNCTION public.is_platform_operator(UUID) IS
  'Répond à : cette organization_id est-elle l''entité juridique actuellement '
  'désignée comme opérateur METALTRACE ? Question sur une ORGANISATION, '
  'jamais sur l''utilisateur courant (ne pas confondre avec '
  'is_platform_superadmin()). Construite avec EXISTS(...) : ne peut '
  'structurellement pas renvoyer NULL (D3, leçon du correctif 03).';

-- D11 (correctif bloquant) : is_platform_operator() seule ne vérifie QUE
-- l'organisation, jamais l'appelant — insuffisant pour une policy RLS qui
-- doit répondre à « CET utilisateur peut-il voir CETTE ligne ». Ce nouveau
-- helper combine les deux : l'organisation est l'opérateur actif ET
-- l'appelant en est membre. EXISTS/AND de deux fonctions elles-mêmes
-- non-NULL par construction : structurellement non-NULL également.
CREATE OR REPLACE FUNCTION public.is_active_platform_operator_member(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    -- Durcissement (dernière revue, 14 juillet 2026) : is_platform_operator()
    -- est déjà structurellement non-NULL (EXISTS-based, D3), mais
    -- is_organization_member() est un helper externe préexistant dont la
    -- garantie de non-nullité n'est pas sous notre contrôle direct — un
    -- COALESCE explicite élimine toute dépendance implicite à son
    -- comportement NULL et garantit un booléen strict par construction ici,
    -- pas seulement par convention chez l'appelé.
    SELECT public.is_platform_operator(p_organization_id)
           AND COALESCE(public.is_organization_member(p_organization_id), false)
$$;

COMMENT ON FUNCTION public.is_active_platform_operator_member(UUID) IS
  'Répond à : l''utilisateur courant est-il membre de l''organisation '
  'actuellement désignée comme opérateur METALTRACE ? Combine '
  'is_platform_operator() (question sur l''organisation) et '
  'is_organization_member() (question sur l''appelant) — D11, correctif '
  'd''une faille RLS où is_platform_operator() seule aurait ouvert la '
  'lecture des mandats à tout utilisateur authentifié, puisque '
  'operator_organization_id est presque toujours l''opérateur actif par '
  'construction (D7), indépendamment de qui interroge.';

-- ────────────────────────────────────────────────────────────
-- 4. RPC — désignation/révocation de l'opérateur, réservées au super-admin (D4)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.designate_platform_operator(p_organization_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_current_id      UUID;
    v_current_org_id  UUID;
    v_new_id          UUID;
    v_transition_at   TIMESTAMPTZ;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    IF NOT COALESCE(public.is_platform_superadmin(), false) THEN
        RAISE EXCEPTION 'Seul un super-administrateur de la plateforme peut désigner l''opérateur METALTRACE.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
        RAISE EXCEPTION 'p_organization_id ne correspond à aucune organisation existante.';
    END IF;

    IF public.is_platform_operator(p_organization_id) THEN
        RAISE EXCEPTION 'Cette organisation est déjà l''opérateur METALTRACE actif.';
    END IF;

    -- Transfert atomique (D4) : révoque l'actif courant s'il existe, avant
    -- d'insérer le nouveau — jamais deux lignes revoked_at IS NULL
    -- simultanément (protégé structurellement par idx_one_active_platform_operator
    -- de toute façon, mais l'ordre ici évite l'exception d'index inutile).
    SELECT id INTO v_current_id
    FROM public.platform_operators
    WHERE revoked_at IS NULL
    FOR UPDATE;

    -- Correctif temporel (dernière revue, 14 juillet 2026, bloquant, D15) :
    -- un SEUL clock_timestamp(), capturé ICI, immédiatement après le
    -- verrouillage de l'opérateur courant, et réutilisé tel quel pour
    -- OLD.revoked_at ET NEW.designated_at/created_at. Avant ce correctif,
    -- revoked_at utilisait clock_timestamp() (horloge murale, avance à
    -- chaque appel) tandis que designated_at/created_at utilisaient le
    -- DEFAULT now() de la table (figé au début de la TRANSACTION, jamais
    -- réévalué) — dans une transition, la nouvelle désignation pouvait donc
    -- apparaître avec une date antérieure à la révocation de l'ancienne,
    -- ce qui est chronologiquement incohérent pour un historique. Une seule
    -- capture d'horodatage, partagée par les deux écritures, élimine toute
    -- dérive entre elles.
    v_transition_at := clock_timestamp();

    IF v_current_id IS NOT NULL THEN
        UPDATE public.platform_operators
        SET revoked_at = v_transition_at,
            revoked_by = auth.uid(),
            revoke_reason = 'Remplacé par la désignation d''un nouvel opérateur.'
        WHERE id = v_current_id
        RETURNING organization_id INTO v_current_org_id;

        INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, actor_id, payload)
        VALUES ('platform_operator_revoked', 'platform_operator', v_current_id, v_current_org_id, auth.uid(),
                jsonb_build_object('reason', 'replaced', 'replaced_by_organization_id', p_organization_id));
    END IF;

    INSERT INTO public.platform_operators (organization_id, designated_by, designated_at, created_at)
    VALUES (p_organization_id, auth.uid(), v_transition_at, v_transition_at)
    RETURNING id INTO v_new_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, actor_id, payload)
    VALUES ('platform_operator_designated', 'platform_operator', v_new_id, p_organization_id, auth.uid(),
            jsonb_build_object('previous_platform_operator_id', v_current_id));

    RETURN v_new_id;
END;
$$;

COMMENT ON FUNCTION public.designate_platform_operator(UUID) IS
  'Désigne p_organization_id comme opérateur/vendeur METALTRACE central. '
  'Réservée à is_platform_superadmin() (D4). Révoque atomiquement l''opérateur '
  'actif courant s''il existe (transfert, pas un état intermédiaire à zéro). '
  'Un seul clock_timestamp() (v_transition_at) capturé après verrouillage de '
  'l''opérateur courant, réutilisé identiquement pour l''ancien.revoked_at et '
  'le nouveau.designated_at/created_at (D15) — élimine toute dérive entre '
  'clock_timestamp() et le DEFAULT now() figé au début de la transaction, '
  'qui pouvait faire apparaître la nouvelle désignation comme antérieure à '
  'la révocation de l''ancienne.';

CREATE OR REPLACE FUNCTION public.revoke_platform_operator(p_organization_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    IF NOT COALESCE(public.is_platform_superadmin(), false) THEN
        RAISE EXCEPTION 'Seul un super-administrateur de la plateforme peut révoquer l''opérateur METALTRACE.';
    END IF;

    SELECT id INTO v_id
    FROM public.platform_operators
    WHERE organization_id = p_organization_id AND revoked_at IS NULL
    FOR UPDATE;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'Cette organisation n''est pas l''opérateur METALTRACE actuellement actif.';
    END IF;

    UPDATE public.platform_operators
    SET revoked_at = clock_timestamp(), revoked_by = auth.uid(), revoke_reason = p_reason
    WHERE id = v_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, actor_id, payload)
    VALUES ('platform_operator_revoked', 'platform_operator', v_id, p_organization_id, auth.uid(),
            CASE WHEN p_reason IS NOT NULL THEN jsonb_build_object('reason', p_reason) ELSE NULL END);

    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.revoke_platform_operator(UUID, TEXT) IS
  'Révoque p_organization_id comme opérateur METALTRACE actif — exige que ce '
  'soit bien l''opérateur actuellement actif (rejet explicite sinon). '
  'Réservée à is_platform_superadmin() (D4). Peut laisser zéro opérateur '
  'désigné (D2) : bloque simplement les nouveaux mandats/ventes jusqu''à la '
  'prochaine désignation, ce n''est pas un état invalide.';

-- ────────────────────────────────────────────────────────────
-- 5. TABLE carbon_commercialization_mandates (D5, D6, D7, D8)
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.carbon_commercialization_mandates (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id           UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    aggregator_id             UUID NOT NULL REFERENCES public.aggregators(id) ON DELETE RESTRICT,
    aggregator_membership_id  UUID NOT NULL REFERENCES public.aggregator_memberships(id) ON DELETE RESTRICT,
    operator_organization_id  UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    -- D8 : catalogue fermé, jamais de texte libre. COALESCE(..., 0) — leçon
    -- NULL déjà appliquée ailleurs dans ce domaine : array_length('{}',1)
    -- renvoie NULL (pas 0) pour un tableau vide, et un CHECK dont le résultat
    -- est NULL est traité comme SATISFAIT par PostgreSQL (pas violé) — un
    -- scope vide '{}' passerait silencieusement sans ce COALESCE.
    scope                     TEXT[] NOT NULL CHECK (
                                  COALESCE(array_length(scope, 1), 0) > 0
                                  AND scope <@ ARRAY[
                                    'aggregate_reductions','submit_for_verification','request_issuance',
                                    'administer_credits','sell_credits','collect_sale_proceeds',
                                    'deduct_approved_costs','distribute_net_proceeds'
                                  ]::TEXT[]
                                ),
    granted_by                UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    granted_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    mandate_document_id       UUID NULL REFERENCES public.documents(id) ON DELETE RESTRICT,
    revoked_at                TIMESTAMPTZ NULL,
    revoked_by                UUID NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    revoke_reason             TEXT NULL,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT carbon_commercialization_mandates_revoked_after_granted
        CHECK (revoked_at IS NULL OR revoked_at >= granted_at)
);

COMMENT ON TABLE public.carbon_commercialization_mandates IS
  'Autorisation contractuelle explicite et historisée, donnée par une '
  'organisation à METALTRACE, rattachée à une adhésion précise '
  '(aggregator_membership_id, D5) — distincte de l''adhésion elle-même. '
  'Tranche0-Carbone-Architecture.md §13 point 7, §14. Append-only, scope '
  'immuable après création (D8), voir triggers ci-dessous.';

-- D5 : un seul mandat actif par adhésion précise, pas par (organization_id, aggregator_id).
CREATE UNIQUE INDEX idx_carbon_commercialization_mandates_one_active_per_membership
    ON public.carbon_commercialization_mandates (aggregator_membership_id)
    WHERE revoked_at IS NULL;

CREATE INDEX idx_carbon_commercialization_mandates_organization_id ON public.carbon_commercialization_mandates (organization_id);
CREATE INDEX idx_carbon_commercialization_mandates_aggregator_id ON public.carbon_commercialization_mandates (aggregator_id);
CREATE INDEX idx_carbon_commercialization_mandates_operator_organization_id ON public.carbon_commercialization_mandates (operator_organization_id);

-- Validation à l'insertion (D6, D7) : cohérence adhésion/organisation/regroupement,
-- adhésion active, opérateur actif. Défense en profondeur — la RPC ci-dessous
-- dérive déjà organization_id/aggregator_id de l'adhésion (ne les accepte pas
-- en paramètres), mais ce trigger reste le filet de sécurité structurel.
CREATE OR REPLACE FUNCTION public.carbon_validate_commercialization_mandate()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_membership_org_id UUID;
    v_membership_agg_id UUID;
    v_membership_ended  TIMESTAMPTZ;
BEGIN
    SELECT organization_id, aggregator_id, ended_at
    INTO v_membership_org_id, v_membership_agg_id, v_membership_ended
    FROM public.aggregator_memberships
    WHERE id = NEW.aggregator_membership_id;

    IF v_membership_org_id IS NULL THEN
        RAISE EXCEPTION 'carbon_commercialization_mandates : aggregator_membership_id ne correspond à aucune adhésion existante.';
    END IF;

    IF v_membership_org_id IS DISTINCT FROM NEW.organization_id
       OR v_membership_agg_id IS DISTINCT FROM NEW.aggregator_id
    THEN
        RAISE EXCEPTION 'carbon_commercialization_mandates : organization_id/aggregator_id ne correspondent pas exactement à l''adhésion référencée par aggregator_membership_id.';
    END IF;

    IF v_membership_ended IS NOT NULL THEN
        RAISE EXCEPTION 'carbon_commercialization_mandates : l''adhésion référencée par aggregator_membership_id est déjà terminée (ended_at renseigné) — aucun nouveau mandat ne peut lui être rattaché.';
    END IF;

    IF NOT public.is_platform_operator(NEW.operator_organization_id) THEN
        RAISE EXCEPTION 'carbon_commercialization_mandates : operator_organization_id ne correspond pas à l''opérateur METALTRACE actuellement actif.';
    END IF;

    -- D8 : scope sans doublon — impossible à exprimer en CHECK déclaratif
    -- (nécessite unnest()/count(), donc une sous-requête, interdite dans un
    -- CHECK PostgreSQL), donc vérifié ici. count(*) sur unnest() vs
    -- count(DISTINCT ...) : une différence signale au moins un doublon.
    IF (SELECT count(*) FROM unnest(NEW.scope)) <> (SELECT count(DISTINCT s) FROM unnest(NEW.scope) AS s) THEN
        RAISE EXCEPTION 'carbon_commercialization_mandates : scope ne peut contenir de valeurs dupliquées.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER carbon_commercialization_mandates_validate
    BEFORE INSERT ON public.carbon_commercialization_mandates
    FOR EACH ROW EXECUTE FUNCTION public.carbon_validate_commercialization_mandate();

-- Garde de transition unique (D8) — scope et toute autre colonne immuables,
-- seule revoked_at NULL -> valeur est permise. Même patron que
-- carbon_guard_aggregator_membership_update() (migration 02).
CREATE OR REPLACE FUNCTION public.carbon_guard_commercialization_mandate_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'carbon_commercialization_mandates : un mandat déjà révoqué (revoked_at renseigné) est immuable, aucune modification supplémentaire n''est permise.';
    END IF;

    IF NEW.revoked_at IS NULL THEN
        RAISE EXCEPTION 'carbon_commercialization_mandates : seule la transition de revoked_at de NULL vers une valeur (révocation) est permise.';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.aggregator_id IS DISTINCT FROM OLD.aggregator_id
       OR NEW.aggregator_membership_id IS DISTINCT FROM OLD.aggregator_membership_id
       OR NEW.operator_organization_id IS DISTINCT FROM OLD.operator_organization_id
       OR NEW.scope IS DISTINCT FROM OLD.scope
       OR NEW.granted_by IS DISTINCT FROM OLD.granted_by
       OR NEW.granted_at IS DISTINCT FROM OLD.granted_at
       OR NEW.mandate_document_id IS DISTINCT FROM OLD.mandate_document_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION 'carbon_commercialization_mandates : seules revoked_at, revoked_by et revoke_reason peuvent être renseignées à la révocation — aucune autre colonne, y compris scope, ne peut changer (D8).';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER carbon_commercialization_mandates_guard_update
    BEFORE UPDATE ON public.carbon_commercialization_mandates
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_commercialization_mandate_update();

CREATE TRIGGER carbon_commercialization_mandates_reject_delete
    BEFORE DELETE ON public.carbon_commercialization_mandates
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 6. RPC — octroi/révocation du mandat (D9)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.grant_commercialization_mandate(
    p_aggregator_membership_id UUID,
    p_operator_organization_id UUID,
    p_scope TEXT[],
    p_mandate_document_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_organization_id UUID;
    v_aggregator_id   UUID;
    v_mandate_id      UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- D6 : organization_id/aggregator_id DÉRIVÉS de l'adhésion, jamais acceptés
    -- comme paramètres séparés — élimine par construction toute incohérence
    -- fournie par l'appelant. Le trigger de validation reste le filet de
    -- sécurité structurel pour toute autre voie d'insertion hypothétique.
    --
    -- Durcissement (dernière revue, 14 juillet 2026, correction bloquante) :
    -- la recherche de l'adhésion et la vérification d'autorisation
    -- (is_org_admin) sont FUSIONNÉES dans la même clause WHERE, avec un
    -- message d'erreur STRICTEMENT IDENTIQUE dans les deux cas d'échec. Avant
    -- ce correctif, un p_aggregator_membership_id inexistant et un
    -- p_aggregator_membership_id existant mais appartenant à une autre
    -- organisation produisaient deux messages distincts — une fuite
    -- d'existence permettant à un appelant non autorisé de distinguer par
    -- essais successifs quels UUID d'adhésion existent réellement en base.
    -- D9 révisée (PLUS de dérogation super-admin ici, voir plus bas) et cette
    -- fusion s'appliquent ensemble : l'octroi du mandat reste un acte de
    -- consentement de l'organisation elle-même.
    SELECT organization_id, aggregator_id
    INTO v_organization_id, v_aggregator_id
    FROM public.aggregator_memberships
    WHERE id = p_aggregator_membership_id
      AND COALESCE(public.is_org_admin(organization_id), false);

    IF v_organization_id IS NULL THEN
        RAISE EXCEPTION 'Adhésion introuvable ou accès refusé.';
    END IF;

    -- D12 : validation SÉMANTIQUE de p_mandate_document_id, pas seulement la
    -- FK — un document existant mais appartenant à une autre organisation
    -- serait accepté par la seule contrainte FK.
    IF p_mandate_document_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.documents
            WHERE id = p_mandate_document_id AND owner_org_id = v_organization_id
        ) THEN
            RAISE EXCEPTION 'p_mandate_document_id doit référencer un document appartenant à l''organisation titulaire de l''adhésion.';
        END IF;
    END IF;

    INSERT INTO public.carbon_commercialization_mandates
        (organization_id, aggregator_id, aggregator_membership_id, operator_organization_id, scope, granted_by, mandate_document_id)
    VALUES
        (v_organization_id, v_aggregator_id, p_aggregator_membership_id, p_operator_organization_id, p_scope, auth.uid(), p_mandate_document_id)
    RETURNING id INTO v_mandate_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
    VALUES ('carbon_commercialization_mandate_granted', 'carbon_commercialization_mandate', v_mandate_id, v_organization_id, v_aggregator_id, auth.uid(),
            jsonb_build_object('operator_organization_id', p_operator_organization_id, 'scope', to_jsonb(p_scope)));

    RETURN v_mandate_id;
END;
$$;

COMMENT ON FUNCTION public.grant_commercialization_mandate(UUID, UUID, TEXT[], UUID) IS
  'Accorde un mandat de commercialisation à p_operator_organization_id pour '
  'l''adhésion p_aggregator_membership_id. Réservée STRICTEMENT à '
  'is_org_admin() de l''organisation titulaire, SANS dérogation super-admin '
  '(D9 révisée) — l''octroi est un acte de consentement de l''organisation '
  'elle-même. Recherche de l''adhésion et vérification d''autorisation '
  'FUSIONNÉES dans la même requête, message d''erreur unique "Adhésion '
  'introuvable ou accès refusé." pour un UUID inexistant ET pour une '
  'adhésion existante mais non autorisée — élimine la fuite d''existence '
  '(durcissement, dernière revue). organization_id/aggregator_id dérivés de '
  'l''adhésion, jamais fournis par l''appelant (D6). p_mandate_document_id '
  'validé sémantiquement (owner_org_id de l''organisation titulaire), pas '
  'seulement par la FK (D12). Validation complémentaire (cohérence, adhésion '
  'active, opérateur actif, absence de doublon dans scope) déléguée au '
  'trigger carbon_commercialization_mandates_validate.';

CREATE OR REPLACE FUNCTION public.revoke_commercialization_mandate(p_mandate_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_organization_id UUID;
    v_aggregator_id   UUID;
    v_revoked_at      TIMESTAMPTZ;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- Durcissement (dernière revue, 14 juillet 2026, correction bloquante) :
    -- même principe que grant_commercialization_mandate() ci-dessus —
    -- l'autorisation (is_org_admin OU is_platform_superadmin) est intégrée
    -- directement dans le SELECT ... FOR UPDATE, avec un message d'erreur
    -- STRICTEMENT IDENTIQUE pour un p_mandate_id inexistant et pour un
    -- mandat existant mais inaccessible à l'appelant courant — élimine la
    -- fuite d'existence.
    SELECT organization_id, aggregator_id, revoked_at
    INTO v_organization_id, v_aggregator_id, v_revoked_at
    FROM public.carbon_commercialization_mandates
    WHERE id = p_mandate_id
      AND (COALESCE(public.is_org_admin(organization_id), false) OR COALESCE(public.is_platform_superadmin(), false))
    FOR UPDATE;

    IF v_organization_id IS NULL THEN
        RAISE EXCEPTION 'Mandat introuvable ou accès refusé.';
    END IF;

    IF v_revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'Ce mandat est déjà révoqué.';
    END IF;

    UPDATE public.carbon_commercialization_mandates
    SET revoked_at = clock_timestamp(), revoked_by = auth.uid(), revoke_reason = p_reason
    WHERE id = p_mandate_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
    VALUES ('carbon_commercialization_mandate_revoked', 'carbon_commercialization_mandate', p_mandate_id, v_organization_id, v_aggregator_id, auth.uid(),
            CASE WHEN p_reason IS NOT NULL THEN jsonb_build_object('reason', p_reason) ELSE NULL END);

    RETURN p_mandate_id;
END;
$$;

COMMENT ON FUNCTION public.revoke_commercialization_mandate(UUID, TEXT) IS
  'Révoque un mandat de commercialisation existant. Réservée à is_org_admin() '
  'de l''organisation titulaire ou is_platform_superadmin() (D9). Recherche '
  'du mandat et vérification d''autorisation FUSIONNÉES dans le même '
  'SELECT ... FOR UPDATE, message d''erreur unique "Mandat introuvable ou '
  'accès refusé." pour un UUID inexistant ET pour un mandat existant mais '
  'inaccessible — élimine la fuite d''existence (durcissement, dernière '
  'revue). Ne met jamais fin à aggregator_memberships (D5) — objets '
  'indépendants.';

-- ────────────────────────────────────────────────────────────
-- 7. RLS — lecture seule via policies, écriture exclusivement par RPC
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.platform_operators ENABLE ROW LEVEL SECURITY;

-- Information de gouvernance, non sensible en lecture (identité de
-- l'opérateur METALTRACE et historique de désignation) — lisible par tout
-- utilisateur authentifié, nécessaire à plusieurs validations transverses
-- du domaine commercial (migrations suivantes).
CREATE POLICY platform_operators_select ON public.platform_operators
    FOR SELECT
    USING (auth.uid() IS NOT NULL);

ALTER TABLE public.carbon_commercialization_mandates ENABLE ROW LEVEL SECURITY;

-- D11 (correctif bloquant) : is_active_platform_operator_member(), pas
-- is_platform_operator() seule — voir en-tête du fichier pour le mécanisme
-- exact de la faille corrigée ici.
CREATE POLICY carbon_commercialization_mandates_select ON public.carbon_commercialization_mandates
    FOR SELECT
    USING (
        public.is_platform_superadmin()
        OR public.is_organization_member(organization_id)
        OR public.is_aggregator_admin(aggregator_id)
        OR public.is_active_platform_operator_member(operator_organization_id)
    );

-- Aucune policy INSERT/UPDATE/DELETE sur aucune des deux tables : écriture
-- exclusivement via les RPC SECURITY DEFINER ci-dessus (même principe que
-- migration 02, §6 de Tranche0-Carbone-Architecture.md).

-- ────────────────────────────────────────────────────────────
-- 8. PRIVILÈGES
-- ────────────────────────────────────────────────────────────

REVOKE ALL ON public.platform_operators FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.platform_operators TO authenticated;

REVOKE ALL ON public.carbon_commercialization_mandates FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.carbon_commercialization_mandates TO authenticated;

REVOKE ALL ON FUNCTION public.is_platform_operator(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_platform_operator(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.is_active_platform_operator_member(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_platform_operator_member(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.designate_platform_operator(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.designate_platform_operator(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.revoke_platform_operator(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_platform_operator(UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.grant_commercialization_mandate(UUID, UUID, TEXT[], UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.grant_commercialization_mandate(UUID, UUID, TEXT[], UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.revoke_commercialization_mandate(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_commercialization_mandate(UUID, TEXT) TO authenticated;

COMMIT;

-- ============================================================
-- ROLLBACK (à exécuter séparément, jamais collé avec ce qui précède) :
-- annule intégralement cette migration, restaure les catalogues à 31/12.
-- ============================================================
-- BEGIN;
--
-- DROP FUNCTION IF EXISTS public.revoke_commercialization_mandate(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.grant_commercialization_mandate(UUID, UUID, TEXT[], UUID);
-- DROP TABLE IF EXISTS public.carbon_commercialization_mandates CASCADE;
-- DROP FUNCTION IF EXISTS public.carbon_validate_commercialization_mandate();
-- DROP FUNCTION IF EXISTS public.carbon_guard_commercialization_mandate_update();
--
-- DROP FUNCTION IF EXISTS public.revoke_platform_operator(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.designate_platform_operator(UUID);
-- DROP FUNCTION IF EXISTS public.is_active_platform_operator_member(UUID);
-- DROP FUNCTION IF EXISTS public.is_platform_operator(UUID);
-- DROP TABLE IF EXISTS public.platform_operators CASCADE;
-- DROP FUNCTION IF EXISTS public.carbon_guard_platform_operator_update();
--
-- ALTER TABLE public.carbon_business_events DROP CONSTRAINT carbon_business_events_event_type_check;
-- ALTER TABLE public.carbon_business_events ADD CONSTRAINT carbon_business_events_event_type_check
--     CHECK (event_type IN (
--         'aggregator_created','aggregator_membership_started','aggregator_membership_ended',
--         'aggregator_admin_appointed','aggregator_admin_revoked','aggregator_primary_admin_transferred',
--         'ccf_mrv_link_started','ccf_mrv_link_ended',
--         'verification_session_started','verification_session_completed',
--         'verification_outcome_recorded','verification_outcome_superseded',
--         'credit_issuance_created','credit_issuance_submitted','credit_issuance_issued',
--         'credit_issuance_externally_cancelled','credit_issuance_voided',
--         'credit_lot_issued','credit_lot_reserved','credit_lot_sold','credit_lot_retired','credit_lot_voided',
--         'credit_sale_created','credit_sale_cost_recorded','credit_sale_confirmed','credit_sale_cancelled',
--         'credit_sale_settled','credit_sale_adjustment_recorded','credit_sale_allocation_recorded',
--         'credit_sale_allocation_approved','credit_sale_allocation_paid'
--     ));
--
-- ALTER TABLE public.carbon_business_events DROP CONSTRAINT carbon_business_events_object_type_check;
-- ALTER TABLE public.carbon_business_events ADD CONSTRAINT carbon_business_events_object_type_check
--     CHECK (object_type IN (
--         'aggregator','aggregator_membership','aggregator_admin','ccf_mrv_project_link',
--         'verification_session','verification_outcome','credit_issuance','credit_lot',
--         'credit_sale','credit_sale_cost','credit_sale_adjustment','credit_sale_allocation'
--     ));
--
-- COMMIT;
-- ============================================================
