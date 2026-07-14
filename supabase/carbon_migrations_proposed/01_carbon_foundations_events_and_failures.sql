-- ============================================================
-- Migration carbone 01/07 — Fondations transverses (révision 4)
-- ============================================================
--
-- PROPOSITION NON APPLIQUÉE. Ce fichier vit délibérément hors de
-- supabase/migrations/ pour qu'aucun `supabase db push` ne puisse
-- l'appliquer par inadvertance. À lire, réviser et approuver avant
-- toute exécution manuelle dans le SQL Editor Supabase.
--
-- Réfère à : Tranche0-Carbone-Architecture.md (v4 + 7 corrections finales,
-- §10bis, §11bis, §12 révisés).
--
-- CHANGEMENTS DEPUIS LA RÉVISION 3 (2 corrections ciblées reçues) :
--   - RÉCURSION RLS POTENTIELLE CORRIGÉE : can_view_carbon_event() faisait
--     un SELECT sur carbon_business_events depuis une fonction SECURITY
--     INVOKER appelée par la policy SELECT de cette même table — cette
--     lecture interne était donc elle-même soumise à la policy, qui rappelle
--     la fonction, risque réel de récursion RLS. Corrigé en ne faisant plus
--     relire la table par la fonction : la policy passe désormais directement
--     les colonnes nécessaires (actor_id, organization_id, aggregator_id,
--     verification_session_id) en paramètres, la fonction ne fait plus aucun
--     accès à carbon_business_events.
--   - Table de test _carbon_migration_test_results : plus de changement ici
--     (elle n'est pas créée par ce fichier de migration, seulement par le
--     script de test séparé) — le nettoyage en fin de script est traité dans
--     tests/01_test_foundations_events_and_failures.sql.
--
-- CHANGEMENTS DEPUIS LA RÉVISION 2 (revue à 8 points reçue) :
--   - Renommage de reject_update_delete() -> carbon_reject_update_delete()
--     (nom trop générique, risque réel de collision avec une fonction de même
--     nom dans un autre domaine du schéma) — point 7 de la revue.
--   - Ajout de la colonne carbon_business_events.verification_session_id,
--     nécessaire pour que la RLS puisse un jour reconnaître un vérificateur
--     assigné qui n'est ni l'acteur ni membre de l'organisation — point 5.
--   - Nouvelle fonction can_view_carbon_event(...), point unique
--     d'autorisation utilisé par la policy SELECT à la place d'un USING
--     inline. Version DE BASE ici (strictement équivalente au comportement
--     précédent : superadmin, acteur, organisation, regroupement) — SANS
--     référence à is_assigned_verifier()/verifier_user_id, qui n'existent pas
--     encore à ce stade (créés en migration 04). La migration 04 fera un
--     CREATE OR REPLACE de cette même fonction pour ajouter la branche
--     vérificateur assigné, sans toucher à la policy — point 5.
--   - Catalogue event_type porté de 25 à 31 valeurs : ajout de
--     aggregator_admin_appointed, aggregator_admin_revoked,
--     aggregator_primary_admin_transferred (gouvernance),
--     verification_session_completed (vérification), credit_sale_cancelled,
--     credit_sale_settled (vente) — catalogue désormais aligné sur toutes les
--     machines à états et RPC prévues, pas seulement les tables — point 6.
--     Ajout corrélatif de 'aggregator_admin' à object_type (requis par les
--     3 nouveaux événements de gouvernance).
--   - Aucun changement fonctionnel sur carbon_rpc_failures dans ce fichier :
--     sa garantie réelle et limitée de persistance (elle ne tient que si la
--     RPC appelante capture l'erreur, journalise, puis retourne normalement
--     sans relancer l'exception) est documentée en détail dans
--     Tranche0-Carbone-Architecture.md §11bis et reflétée dans le commentaire
--     de table ci-dessous — la correction concrète du test (renommage de
--     l'assertion B5) vit dans le script de test séparé, jamais ici.
--
-- CONTENU :
--   1. Extension btree_gist (prérequise par la migration 04).
--   2. Table carbon_business_events — événements métier RÉUSSIS uniquement,
--      append-only, catalogue TEXT+CHECK complet (31 valeurs), colonne
--      verification_session_id pour la portée MRV future.
--   3. Table carbon_rpc_failures — journal des échecs, séparé.
--   4. carbon_reject_update_delete() + triggers append-only.
--   5. can_view_carbon_event() (version de base, sans lecture de table,
--      SECURITY INVOKER) + RLS + révocations.
--   6. Section de rollback/désactivation, commentée, à la fin.
--
-- Les tests vivent dans le fichier séparé référencé ci-dessus — à exécuter
-- APRÈS cette migration, jamais mélangés dans le même script.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. EXTENSION PRÉREQUISE
-- ────────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ────────────────────────────────────────────────────────────
-- 2. CARBON_BUSINESS_EVENTS — événements métier réussis, append-only
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.carbon_business_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type      TEXT NOT NULL CHECK (event_type IN (
        -- Gouvernance des regroupements (6)
        'aggregator_created',
        'aggregator_membership_started',
        'aggregator_membership_ended',
        'aggregator_admin_appointed',
        'aggregator_admin_revoked',
        'aggregator_primary_admin_transferred',
        -- Rattachement CCF <-> MRV (2)
        'ccf_mrv_link_started',
        'ccf_mrv_link_ended',
        -- Vérification (4)
        'verification_session_started',
        'verification_session_completed',
        'verification_outcome_recorded',
        'verification_outcome_superseded',
        -- Émission réglementaire (5) — 'voided' (annulation interne) et
        -- 'externally_cancelled' (annulation confirmée par le registre après
        -- émission) sont deux événements distincts et non ambigus.
        'credit_issuance_created',
        'credit_issuance_submitted',
        'credit_issuance_issued',
        'credit_issuance_externally_cancelled',
        'credit_issuance_voided',
        -- Cycle commercial des lots (5)
        'credit_lot_issued',
        'credit_lot_reserved',
        'credit_lot_sold',
        'credit_lot_retired',
        'credit_lot_voided',
        -- Vente et modèle financier (9)
        'credit_sale_created',
        'credit_sale_cost_recorded',
        'credit_sale_confirmed',
        'credit_sale_cancelled',
        'credit_sale_settled',
        'credit_sale_adjustment_recorded',
        'credit_sale_allocation_recorded',
        'credit_sale_allocation_approved',
        'credit_sale_allocation_paid'
        -- Total : 6+2+4+5+5+9 = 31 valeurs exactement. Catalogue aligné sur
        -- toutes les machines à états et RPC prévues (pas seulement sur les
        -- tables) — correction reçue après revue, point 6.
    )),
    object_type     TEXT NOT NULL CHECK (object_type IN (
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
        'credit_sale_allocation'
    )),
    object_id       UUID NOT NULL,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE RESTRICT,
    aggregator_id   UUID REFERENCES public.aggregators(id) ON DELETE RESTRICT,
    actor_id        UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    -- Colonne prérequise par la portée MRV de la RLS (§10bis) : permet à
    -- can_view_carbon_event() de reconnaître, à partir de la migration 04,
    -- un vérificateur assigné à CETTE session précise, même s'il n'est ni
    -- l'acteur de l'événement ni membre de l'organisation concernée. NULL
    -- pour tout événement non lié à une session de vérification.
    verification_session_id UUID REFERENCES public.verification_sessions(id) ON DELETE RESTRICT,
    payload         JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.carbon_business_events IS
  'Événements métier RÉUSSIS du domaine carbone uniquement. Les échecs '
  'd''autorisation/validation vivent dans carbon_rpc_failures, jamais ici. '
  'Append-only : voir trigger carbon_business_events_no_update_delete ci-dessous.';

CREATE INDEX idx_carbon_business_events_object ON public.carbon_business_events (object_type, object_id);
CREATE INDEX idx_carbon_business_events_org ON public.carbon_business_events (organization_id);
CREATE INDEX idx_carbon_business_events_aggregator ON public.carbon_business_events (aggregator_id);
CREATE INDEX idx_carbon_business_events_verification_session ON public.carbon_business_events (verification_session_id);
CREATE INDEX idx_carbon_business_events_created_at ON public.carbon_business_events (created_at);

-- ────────────────────────────────────────────────────────────
-- 3. CARBON_RPC_FAILURES — journal des échecs, séparé
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.carbon_rpc_failures (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rpc_name              TEXT NOT NULL,
    failure_reason        TEXT NOT NULL,
    attempted_object_type TEXT,
    attempted_object_id   UUID,
    attempted_by          UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    detail                JSONB,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.carbon_rpc_failures IS
  'Journal des refus d''autorisation et échecs de validation des RPC du domaine '
  'carbone. Audience et politique de rétention distinctes de carbon_business_events '
  '— ne jamais fusionner les deux. Append-only, comme carbon_business_events. '
  'GARANTIE RÉELLE ET LIMITÉE (précisée après revue, voir '
  'Tranche0-Carbone-Architecture.md §11bis) : une ligne insérée ici DEPUIS le '
  'bloc EXCEPTION d''une RPC ne survit que si cette RPC capture l''erreur, '
  'insère la ligne, PUIS retourne normalement un résultat structuré d''échec '
  'sans relancer l''exception (pas de RAISE vers l''appelant). Si la RPC '
  'relance l''exception, ou si la transaction englobante est annulée pour '
  'toute autre raison, cette insertion est annulée avec le reste — un '
  'savepoint PL/pgSQL protège uniquement contre le rollback d''un bloc '
  'imbriqué, jamais contre l''annulation de la transaction qui l''englobe. '
  'À réserver aux échecs de validation/autorisation ATTENDUS où la RPC choisit '
  'délibérément de journaliser puis de retourner un échec structuré ; pour les '
  'erreurs réellement exceptionnelles qui doivent remonter au client, '
  's''appuyer sur les journaux serveur/applicatifs Postgres, pas sur cette table.';

CREATE INDEX idx_carbon_rpc_failures_rpc_name ON public.carbon_rpc_failures (rpc_name);
CREATE INDEX idx_carbon_rpc_failures_created_at ON public.carbon_rpc_failures (created_at);

-- ────────────────────────────────────────────────────────────
-- 4. APPEND-ONLY — aucun UPDATE ni DELETE possible sur les deux tables
-- ────────────────────────────────────────────────────────────
--
-- Renommée avec un préfixe de domaine (correction 7 de la revue) :
-- reject_update_delete() était un nom trop générique, avec un risque réel de
-- collision avec une fonction homonyme d'un autre domaine du schéma partagé.

CREATE OR REPLACE FUNCTION public.carbon_reject_update_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'Table % est append-only : UPDATE et DELETE sont interdits.', TG_TABLE_NAME;
END;
$$;

CREATE TRIGGER carbon_business_events_no_update_delete
    BEFORE UPDATE OR DELETE ON public.carbon_business_events
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

CREATE TRIGGER carbon_rpc_failures_no_update_delete
    BEFORE UPDATE OR DELETE ON public.carbon_rpc_failures
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 5. RLS — can_view_carbon_event() + policies (corrections 4 et 5 de la revue)
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.carbon_business_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carbon_rpc_failures ENABLE ROW LEVEL SECURITY;

-- Point unique d'autorisation en lecture pour carbon_business_events, plutôt
-- qu'un USING inline appelé à grossir indéfiniment (correction 5 de la
-- revue à 8 points — portée RLS MRV encore incomplète). VERSION DE BASE ici :
-- strictement équivalente à la policy précédente (superadmin, acteur,
-- organisation, regroupement), AUCUN comportement nouveau à ce stade. La
-- migration 04 fera un CREATE OR REPLACE de cette même fonction pour ajouter
-- le paramètre de vérification « vérificateur assigné », une fois
-- is_assigned_verifier() et verification_sessions.verifier_user_id créés —
-- voir Tranche0-Carbone-Architecture.md §10bis pour le séquencement complet.
--
-- RÉCURSION RLS ÉVITÉE (correction reçue après revue de la révision 3) :
-- cette fonction NE FAIT PLUS aucun SELECT sur carbon_business_events. Une
-- version antérieure prenait p_event_id en paramètre et relisait la ligne
-- elle-même (`SELECT ... FROM carbon_business_events WHERE id = p_event_id`)
-- — or cette lecture, exécutée par une fonction SECURITY INVOKER appelée
-- depuis la policy SELECT de CETTE MÊME table, est elle-même soumise à
-- cette policy, qui rappelle la fonction : risque réel de récursion RLS.
-- Corrigé en recevant directement les colonnes nécessaires en paramètres —
-- la policy les fournit depuis la ligne déjà en cours d'évaluation, sans
-- jamais relire la table depuis l'intérieur de la fonction.
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
        OR (p_aggregator_id IS NOT NULL AND public.is_aggregator_admin(p_aggregator_id));
        -- MIGRATION 04 AJOUTERA ICI (CREATE OR REPLACE, même signature) :
        -- OR (p_verification_session_id IS NOT NULL
        --     AND public.is_assigned_verifier(p_verification_session_id))
        -- p_verification_session_id est déjà reçu en paramètre ici pour que
        -- la signature n'ait pas besoin de changer en migration 04 — seul
        -- le corps de la fonction sera remplacé.
$$;

COMMENT ON FUNCTION public.can_view_carbon_event(UUID, UUID, UUID, UUID) IS
  'Point unique d''autorisation en lecture pour carbon_business_events. Reçoit '
  'les colonnes nécessaires en paramètres plutôt que de relire la table '
  '(évite toute récursion RLS, cette fonction étant appelée depuis la policy '
  'SELECT de carbon_business_events elle-même). Version de base (migration '
  '01) : superadmin, acteur, organisation, regroupement. Étendue par la '
  'migration 04 (CREATE OR REPLACE, même signature) pour couvrir le '
  'vérificateur assigné via p_verification_session_id — voir '
  'Tranche0-Carbone-Architecture.md §10bis.';

-- Lecture des événements métier : entièrement déléguée à can_view_carbon_event(),
-- appelée avec les colonnes de la ligne évaluée (aucune relecture de table).
CREATE POLICY carbon_business_events_select ON public.carbon_business_events
    FOR SELECT
    USING (
        public.can_view_carbon_event(
            actor_id,
            organization_id,
            aggregator_id,
            verification_session_id
        )
    );

-- Aucune policy INSERT/UPDATE/DELETE : l'écriture se fait exclusivement via
-- les RPC SECURITY DEFINER des migrations 02-07, qui contournent la RLS par
-- nature (voir §6 pour les privilèges de table sous-jacents).

-- Lecture des échecs : réservée au super-admin plateforme (journal de
-- sécurité, accès volontairement plus restrictif que les événements métier).
CREATE POLICY carbon_rpc_failures_select ON public.carbon_rpc_failures
    FOR SELECT
    USING (public.is_platform_superadmin());

-- ────────────────────────────────────────────────────────────
-- 6. RÉVOCATIONS DE PRIVILÈGES
-- ────────────────────────────────────────────────────────────

REVOKE ALL ON public.carbon_business_events FROM PUBLIC, anon;
REVOKE ALL ON public.carbon_rpc_failures FROM PUBLIC, anon;

GRANT SELECT ON public.carbon_business_events TO authenticated;
GRANT SELECT ON public.carbon_rpc_failures TO authenticated;
-- Aucun GRANT INSERT/UPDATE/DELETE à `authenticated` — les RPC futures
-- (SECURITY DEFINER, propriété d'un rôle privilégié) écrivent sans avoir
-- besoin de privilège de table direct côté appelant.

REVOKE ALL ON FUNCTION public.can_view_carbon_event(UUID, UUID, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_carbon_event(UUID, UUID, UUID, UUID) TO authenticated;
-- SECURITY INVOKER (pas DEFINER) : cette fonction ne fait qu'agréger des
-- vérifications déjà elles-mêmes soumises aux règles d'appel habituelles
-- (is_organization_member, is_aggregator_admin, is_platform_superadmin) sur
-- des paramètres scalaires reçus — aucune élévation de privilège, aucune
-- lecture de table (donc aucune récursion RLS), seulement une centralisation
-- de logique.

-- ════════════════════════════════════════════════════════════
-- ROLLBACK / DÉSACTIVATION (commenté — à exécuter manuellement si besoin
-- de revenir en arrière après application de cette migration)
-- ════════════════════════════════════════════════════════════

-- DROP TRIGGER IF EXISTS carbon_business_events_no_update_delete ON public.carbon_business_events;
-- DROP TRIGGER IF EXISTS carbon_rpc_failures_no_update_delete ON public.carbon_rpc_failures;
-- DROP FUNCTION IF EXISTS public.carbon_reject_update_delete();
-- DROP POLICY IF EXISTS carbon_business_events_select ON public.carbon_business_events;
-- DROP POLICY IF EXISTS carbon_rpc_failures_select ON public.carbon_rpc_failures;
-- DROP FUNCTION IF EXISTS public.can_view_carbon_event(UUID, UUID, UUID, UUID);
-- DROP TABLE IF EXISTS public.carbon_business_events;
-- DROP TABLE IF EXISTS public.carbon_rpc_failures;
-- -- L'extension btree_gist n'est PAS retirée ici : elle est un prérequis
-- -- partagé par la migration 04 (contrainte EXCLUDE sur verification_sessions).
-- -- Ne la retirer que si aucune autre migration de ce domaine n'est appliquée.
-- -- DROP EXTENSION IF EXISTS btree_gist;
