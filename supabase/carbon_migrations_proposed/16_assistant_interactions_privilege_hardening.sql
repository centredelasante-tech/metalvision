-- ============================================================
-- PROPOSÉ — durcissement des privilèges GRANT sur assistant_interactions
-- (GATE IA-2, suite de la migration 15)
-- ============================================================
-- Contexte : la migration 15 (15_assistant_interactions_audit_log.sql)
-- crée la table avec RLS activée et seulement 3 policies permissives
-- (SELECT propre ligne, INSERT propre ligne, SELECT superadmin global) —
-- aucune policy UPDATE/DELETE, donc RLS refuse déjà ces commandes par
-- défaut pour tout rôle non-owner. Vérification post-application de la
-- migration 15 sur METALVISION-DEMO a cependant montré que les privilèges
-- GRANT bruts au niveau table restent ceux hérités par défaut du schéma
-- public Supabase : anon:SELECT, authenticated:SELECT/INSERT/UPDATE/DELETE
-- (identique à carbon_business_events et aux autres tables du domaine
-- carbone — ce n'est pas une régression introduite par la 15).
--
-- Cette migration ne touche AUCUN comportement fonctionnel observable
-- (RLS bloquait déjà UPDATE/DELETE et l'accès anon) — elle retire la
-- capacité GRANT elle-même, en défense en profondeur : même en cas de
-- policy RLS mal configurée dans une évolution future de cette table
-- précise, PUBLIC/anon n'auraient plus aucun privilège table-level, et
-- authenticated ne pourrait techniquement plus émettre UPDATE/DELETE
-- (erreur de privilège, avant même l'évaluation RLS).
--
-- Aucune modification de 15_assistant_interactions_audit_log.sql. Aucune
-- donnée métier touchée (uniquement REVOKE/GRANT, pas de DML).
--
-- Statut : PROPOSÉE. À appliquer sur METALVISION-DEMO uniquement dans le
-- cadre de GATE IA-2. Production hors périmètre — non appliquée.
-- ============================================================

REVOKE ALL PRIVILEGES ON public.assistant_interactions FROM PUBLIC;
REVOKE ALL PRIVILEGES ON public.assistant_interactions FROM anon;
REVOKE ALL PRIVILEGES ON public.assistant_interactions FROM authenticated;

-- L'application (POST /api/assistant/ask) n'a besoin que de :
--  - INSERT (logAssistantInteraction, avec le client authentifié de la
--    requête — jamais service role) ;
--  - SELECT (lecture de ses propres interactions / lecture superadmin,
--    déjà bornées par les policies RLS de la migration 15).
-- Aucun UPDATE ni DELETE n'est jamais émis par le code applicatif.
GRANT SELECT, INSERT ON public.assistant_interactions TO authenticated;

COMMENT ON TABLE public.assistant_interactions IS
  'Journal d''audit des interactions avec l''Agent d''aide MetalTrace V1 (GATE IA-1/IA-2). '
  'Ne contient jamais la question ni la réponse complètes, ni le contenu du contexte métier — '
  'uniquement métadonnées bornées. Append-only : RLS (migration 15) + privilèges GRANT restreints '
  'à SELECT/INSERT pour authenticated (migration 16) ; aucun privilège pour anon/PUBLIC.';
