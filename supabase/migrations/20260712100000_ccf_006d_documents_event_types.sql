-- ============================================================
-- CCF-006d — Complément ENUM ccf_event_type pour les documents
-- ============================================================
--
-- CONSTAT (revue backend S07 — /documents, 12 juillet 2026) :
--   L'ENUM public.ccf_event_type (20260710001000_ccf_001_enums.sql)
--   ne contient que 'document_submitted' et 'document_approved'.
--   Or public.documents.status autorise aussi 'rejected' et 'archived'
--   (CHECK dans 20260710006000_ccf_006_documents.sql).
--
--   Toute tentative future d'écrire un business_event pour un refus
--   ou un archivage de document (frontend S07, RPC d'approbation)
--   échouerait à l'exécution avec :
--     ERROR: invalid input value for enum ccf_event_type
--   — même patron que INC-S06-08 (S06), détecté ici de façon
--   proactive avant l'écriture du frontend par Rocket.
--
-- CORRECTION :
--   Ajout de 'document_rejected' et 'document_archived' à l'ENUM.
--   ALTER TYPE ... ADD VALUE IF NOT EXISTS est utilisé (idempotent,
--   PostgreSQL 12+) plutôt que DROP TYPE CASCADE, pour ne pas
--   recréer un type déjà référencé par la table business_events.
-- ============================================================

ALTER TYPE public.ccf_event_type ADD VALUE IF NOT EXISTS 'document_rejected';
ALTER TYPE public.ccf_event_type ADD VALUE IF NOT EXISTS 'document_archived';
