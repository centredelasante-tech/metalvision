-- ============================================================
-- CCF-001 — Extensions & ENUMs du domaine collaboratif
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   RT-05 : Pas d'ENUM générique "status". Chaque table gouvernée
--            utilise une colonne TEXT + CHECK (status IN (...)).
--            Seuls les types stables et non conflictuels sont des ENUMs.
--   RT-01/RT-02 : La table "projects" (domaine MRV ISO 14064) et son
--            ENUM "project_status" existants ne sont PAS touchés.
--            Le domaine collaboratif utilise la table "ccf_projects".
--
-- CONVENTIONS :
--   - gen_random_uuid() pour toutes les PK
--   - TIMESTAMPTZ NOT NULL DEFAULT now() pour les timestamps
--   - SECURITY DEFINER sur toutes les fonctions helper
--   - IF NOT EXISTS sur CREATE TABLE/INDEX
--   - DROP TYPE IF EXISTS ... CASCADE avant CREATE TYPE
--   - DROP POLICY IF EXISTS avant CREATE POLICY
-- ============================================================

-- ── 1. mandate_scope ─────────────────────────────────────────
-- Portée fonctionnelle d'un mandat inter-organisation.
-- Valeurs stables, fermées, sans conflit avec le schéma existant.
DROP TYPE IF EXISTS public.mandate_scope CASCADE;
CREATE TYPE public.mandate_scope AS ENUM (
    'gouvernance',
    'operationnel',
    'financier',
    'technique',
    'verification',
    'ia'
);

-- ── 2. document_visibility ───────────────────────────────────
-- Niveau de visibilité d'un document gouverné.
DROP TYPE IF EXISTS public.document_visibility CASCADE;
CREATE TYPE public.document_visibility AS ENUM (
    'organization_private',
    'project',
    'confidential'
);

-- ── 3. ccf_project_phase ─────────────────────────────────────
-- Phase opérationnelle d'un projet collaboratif CCF.
-- Nommé "ccf_project_phase" pour éviter tout conflit avec
-- un éventuel "project_phase" futur dans le domaine MRV.
DROP TYPE IF EXISTS public.ccf_project_phase CASCADE;
CREATE TYPE public.ccf_project_phase AS ENUM (
    'draft',
    'active',
    'execution',
    'review',
    'closed'
);

-- ── 4. logistics_step_type ───────────────────────────────────
-- Type d'étape logistique dans un projet CCF.
DROP TYPE IF EXISTS public.logistics_step_type CASCADE;
CREATE TYPE public.logistics_step_type AS ENUM (
    'ramassage',
    'chargement',
    'expedition',
    'transit',
    'livraison',
    'preuve_finale'
);

-- ── 5. ccf_event_type ────────────────────────────────────────
-- Catalogue fermé des 17 types d'événements métier CCF.
-- Nommé "ccf_event_type" pour éviter tout conflit avec
-- le domaine MRV/scan existant.
DROP TYPE IF EXISTS public.ccf_event_type CASCADE;
CREATE TYPE public.ccf_event_type AS ENUM (
    'organization_created',
    'organization_suspended',
    'member_invited',
    'member_activated',
    'mandate_issued',
    'mandate_accepted',
    'mandate_revoked',
    'capability_declared',
    'capability_qualified',
    'opportunity_created',
    'opportunity_qualified',
    'project_created',
    'project_phase_changed',
    'document_submitted',
    'document_approved',
    'logistics_step_updated',
    'value_report_generated'
);

-- ── NOTE : Statuts fermés ─────────────────────────────────────
-- Les statuts des tables gouvernées sont implémentés comme
-- TEXT + CHECK (status IN (...)) dans chaque migration de table,
-- conformément à la décision RT-05.
-- Aucun ENUM générique "status" n'est créé ici.
--
-- Valeurs par table (référence §6.2 du Cahier fonctionnel v1.2) :
--   organizations        : draft, active, suspended, archived
--   organization_members : invited, active, suspended, revoked
--   mandates             : draft, pending_acceptance, active, expired, revoked
--   capabilities         : draft, declared, qualified, suspended, archived
--   opportunities        : draft, qualified, converted, closed, archived
--   ccf_projects.status  : draft, active, paused, closed, archived
--   project_participants : invited, active, declined, removed
--   documents            : draft, submitted, approved, rejected, archived
--   logistics_steps      : planned, in_progress, completed, blocked, cancelled
--   value_reports        : draft, generated, validated, shared, archived
