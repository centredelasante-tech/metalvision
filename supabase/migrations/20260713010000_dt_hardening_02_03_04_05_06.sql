-- ============================================================
-- Projet de durcissement post-MVP — DT-02, DT-03, DT-04, DT-05, DT-06
-- Migration: 20260713010000_dt_hardening_02_03_04_05_06.sql
-- ============================================================
--
-- Contexte : dette technique consignée dans ADR-MVP.md §5, appartenant aux
-- domaines MRV/ISO 14064 et Regroupements/Agrégateurs (hors périmètre MVP
-- CCF), traitée ici comme projet de durcissement séparé, à la demande
-- explicite de l'utilisateur.
--
-- État vérifié en production le 13 juillet 2026 avant d'écrire cette
-- migration (jamais par archéologie de migrations — leçon d'INC-DATA-01,
-- ADR-MVP.md §9novodecies) :
--   DT-01 : CADUC, aucune action ici. La colonne
--           member_distribution_overrides.created_by n'existe plus du tout
--           (disparue lors de la reconstruction du schéma, incident §6) —
--           rien à corriger, le constat original ne s'applique plus.
--   DT-02 : confirmé réel. project_activity_logs.actor_id (uuid, nullable),
--           aucune FK. 2 lignes, 0 orpheline vs profiles(id).
--   DT-03 : confirmé réel. evidence_files.actor_id (uuid, nullable), aucune
--           FK. 2 lignes, 0 orpheline vs profiles(id).
--   DT-04 : confirmé réel. aggregator_admins.user_id (uuid, NOT NULL),
--           aucune FK vers profiles. Table vide (0 ligne) — aucun risque.
--   DT-05 : confirmé réel, mais constat à nuancer. transport_status est
--           bien en TEXT (pas ENUM) — décision DÉLIBÉRÉE et documentée
--           (20260628150000_internal_transport.sql), pas un oubli : deux
--           vocabulaires de statut coexistent sur la même colonne selon le
--           provider (transport interne : scheduled/in_transit/arrived/
--           delivered/cancelled ; transport externe Groupe Robert, encore
--           présent dans le code derrière le flag app_settings
--           'external_transport_enabled' = false par défaut : pending/
--           assigned/en_route/picked_up/delivered/cancelled). Conforme à
--           MVP-DA-015 (TEXT + CHECK, pas d'ENUM partagé) même si cette
--           convention a été posée pour le domaine CCF, pas MRV/Transport —
--           correctif choisi ici : CHECK au lieu de ENUM, pour ne fermer la
--           porte à aucun des deux providers. Table transport_requests vide
--           en production (0 ligne) — aucun risque de casser une valeur
--           existante.
--   DT-06 : confirmé réel. is_platform_admin(), is_aggregator_admin(),
--           is_verifier(), is_project_admin() ont toutes proconfig = null
--           (aucun SET search_path).
--   DT-07 : déjà résolu — is_project_admin() en base est bien la version
--           sécurisée (auth.jwt() -> app_metadata), pas raw_user_meta_data.
--           Reçoit ici le même correctif SET search_path que DT-06 (elle
--           était listée dans les deux points).
--
-- Additive uniquement : aucune table, aucune donnée supprimée, aucune
-- policy RLS existante modifiée.
-- ============================================================

-- ─── DT-02 ──────────────────────────────────────────────────────────────────
ALTER TABLE public.project_activity_logs
  DROP CONSTRAINT IF EXISTS project_activity_logs_actor_id_fkey;
ALTER TABLE public.project_activity_logs
  ADD CONSTRAINT project_activity_logs_actor_id_fkey
  FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ─── DT-03 ──────────────────────────────────────────────────────────────────
ALTER TABLE public.evidence_files
  DROP CONSTRAINT IF EXISTS evidence_files_actor_id_fkey;
ALTER TABLE public.evidence_files
  ADD CONSTRAINT evidence_files_actor_id_fkey
  FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ─── DT-04 ──────────────────────────────────────────────────────────────────
-- user_id est NOT NULL : ON DELETE SET NULL est impossible (violerait la
-- contrainte). Une ligne aggregator_admins sans utilisateur valide n'a pas
-- de sens métier — ON DELETE CASCADE supprime le droit d'admin avec le
-- profil, ce qui est le comportement attendu (cohérent avec le fait que
-- cette table n'existe que pour accorder un rôle à un utilisateur précis).
ALTER TABLE public.aggregator_admins
  DROP CONSTRAINT IF EXISTS aggregator_admins_user_id_fkey;
ALTER TABLE public.aggregator_admins
  ADD CONSTRAINT aggregator_admins_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- ─── DT-05 ──────────────────────────────────────────────────────────────────
-- Union des deux vocabulaires de statut réellement utilisés dans le code
-- (src/app/api/transport/*, src/app/api/external/grouperobert/*), plus
-- 'pending' conservé car c'est la valeur DEFAULT actuelle de la colonne.
ALTER TABLE public.transport_requests
  DROP CONSTRAINT IF EXISTS transport_requests_transport_status_check;
ALTER TABLE public.transport_requests
  ADD CONSTRAINT transport_requests_transport_status_check
  CHECK (transport_status IN (
    'pending', 'assigned', 'en_route', 'picked_up', 'delivered', 'cancelled',
    'scheduled', 'in_transit', 'arrived'
  ));

-- ─── DT-06 / DT-07 ──────────────────────────────────────────────────────────
-- SET search_path = public sur les fonctions SECURITY DEFINER du domaine
-- Agrégateurs/MRV, même convention que MVP-RA-021 pour le domaine CCF.
-- ALTER FUNCTION ... SET ne change ni le corps ni le comportement métier de
-- la fonction, seulement la résolution des noms non qualifiés à l'intérieur.
-- is_aggregator_admin() prend en fait un paramètre (p_aggregator_id UUID),
-- pas zéro argument (confirmé via 20260710999100_reapply_mrv_and_aggregators.sql
-- L555) — signature exacte requise par ALTER FUNCTION, sous peine d'erreur
-- "function does not exist".
ALTER FUNCTION public.is_platform_admin()          SET search_path = public;
ALTER FUNCTION public.is_aggregator_admin(uuid)    SET search_path = public;
ALTER FUNCTION public.is_verifier()                SET search_path = public;
ALTER FUNCTION public.is_project_admin()           SET search_path = public;

-- ============================================================
-- Vérification post-migration (à lancer manuellement) :
--   SELECT conname FROM pg_constraint WHERE conname IN (
--     'project_activity_logs_actor_id_fkey', 'evidence_files_actor_id_fkey',
--     'aggregator_admins_user_id_fkey', 'transport_requests_transport_status_check'
--   );  -- doit retourner 4 lignes
--   SELECT proname, proconfig FROM pg_proc WHERE proname IN (
--     'is_platform_admin','is_aggregator_admin','is_verifier','is_project_admin'
--   );  -- proconfig doit contenir {search_path=public} pour les 4
-- ============================================================
