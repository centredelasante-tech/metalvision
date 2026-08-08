-- ============================================================
-- PROPOSÉ — NON APPLIQUÉ (GATE IA-1, Agent d'aide MetalTrace V1)
-- ============================================================
-- Renuméroté 10 -> 15 : les migrations carbone 10 à 14 existent déjà
-- (10_carbon_organizations_governance_visibility.sql,
-- 11_carbon_sales_compute_allocations_safeupdate_fix.sql,
-- 12_carbon_start_verification_session.sql,
-- 13_carbon_verification_evidence.sql, 14_get_my_portal_role_rpc.sql).
-- Aucune migration historique n'est modifiée par ce renommage.
--
-- Schéma de journalisation pour /api/assistant/ask.
--
-- Minimisation des données — ce qui N'EST JAMAIS stocké : la question
-- complète de l'utilisateur, la réponse complète du modèle, le contexte
-- métier complet (contenu des lignes lues par les résolveurs), ni aucun
-- document/preuve. Ce qui EST stocké : des métadonnées d'audit bornées —
-- utilisateur, rôle de portail, écran, identifiant technique (UUID) de
-- l'objet consulté s'il y en a un, modèle utilisé, statut, durée,
-- longueurs et compteurs de tokens quand le SDK les fournit, horodatage,
-- et un résumé de FORME du contexte (clés + tailles, jamais les valeurs).
-- Un UUID n'est pas une donnée métier sensible en soi (aucun contenu),
-- mais reste utile pour corréler une interaction à un objet précis en cas
-- d'investigation — RLS continue de s'appliquer à quiconque consulterait
-- l'objet référencé.
--
-- Objectif : pouvoir répondre à « qui a demandé de l'aide, sur quel écran,
-- quand, avec quel résultat technique (succès/erreur, modèle, latence,
-- tokens) » sans dupliquer de données métier potentiellement sensibles
-- dans une table supplémentaire.
--
-- Statut : PROPOSÉE SEULE. À appliquer sur DEMO puis production uniquement
-- après autorisation explicite distincte (même protocole que les
-- migrations carbone 01-09 précédentes).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.assistant_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    portal_role TEXT,
    screen TEXT NOT NULL,
    -- Identifiant technique (UUID) de l'objet consulté, si l'écran en a un.
    -- Jamais le contenu de l'objet — uniquement le pointeur.
    object_id UUID,
    question_length INTEGER NOT NULL,
    context_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
    answer_length INTEGER NOT NULL,
    model TEXT NOT NULL,
    -- Compteurs de tokens rapportés par le SDK LLM, quand disponibles.
    prompt_tokens INTEGER,
    completion_tokens INTEGER,
    latency_ms INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'success',
    -- Code d'erreur sûr (ex. 'llm_upstream_error') — jamais le message brut
    -- ni une stack trace. Null si status='success'.
    error_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT assistant_interactions_status_check CHECK (status IN ('success', 'error')),
    CONSTRAINT assistant_interactions_error_code_consistency CHECK (
        (status = 'success' AND error_code IS NULL) OR
        (status = 'error' AND error_code IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_assistant_interactions_user_id ON public.assistant_interactions(user_id);
CREATE INDEX IF NOT EXISTS idx_assistant_interactions_created_at ON public.assistant_interactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_assistant_interactions_screen ON public.assistant_interactions(screen);

ALTER TABLE public.assistant_interactions ENABLE ROW LEVEL SECURITY;

-- Chaque utilisateur ne voit que ses propres interactions.
DROP POLICY IF EXISTS "users_select_own_assistant_interactions" ON public.assistant_interactions;
CREATE POLICY "users_select_own_assistant_interactions"
ON public.assistant_interactions
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Insertion : uniquement pour son propre user_id (l'endpoint écrit avec le
-- client authentifié de la requête, jamais avec une clé service role).
DROP POLICY IF EXISTS "users_insert_own_assistant_interactions" ON public.assistant_interactions;
CREATE POLICY "users_insert_own_assistant_interactions"
ON public.assistant_interactions
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Lecture superadmin (audit global), cohérent avec le traitement déjà
-- appliqué à carbon_business_events.
DROP POLICY IF EXISTS "superadmin_select_assistant_interactions" ON public.assistant_interactions;
CREATE POLICY "superadmin_select_assistant_interactions"
ON public.assistant_interactions
FOR SELECT
TO authenticated
USING (public.is_platform_superadmin());

-- Append-only : ni update ni delete (cohérent avec la convention MVP-DA-006
-- déjà appliquée aux tables du domaine carbone). Aucune policy UPDATE/DELETE
-- n'est créée — RLS refuse par défaut en l'absence de policy permissive.

COMMENT ON TABLE public.assistant_interactions IS
  'Journal d''audit des interactions avec l''Agent d''aide MetalTrace V1 (GATE IA-1). '
  'Ne contient jamais la question ni la réponse complètes, ni le contenu du contexte métier — '
  'uniquement métadonnées bornées (utilisateur, rôle, écran, identifiant technique, modèle, '
  'statut, durée, longueurs, tokens si disponibles, résumé de forme du contexte).';
