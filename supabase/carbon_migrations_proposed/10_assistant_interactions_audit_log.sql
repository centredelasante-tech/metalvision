-- ============================================================
-- PROPOSÉ — NON APPLIQUÉ (GATE IA-1, Agent d'aide MetalTrace V1)
-- ============================================================
-- Schéma de journalisation pour /api/assistant/ask.
-- Minimisation des données : ni la question ni la réponse complètes du
-- modèle ne sont stockées, uniquement leur longueur et un résumé borné du
-- contexte (clés/tailles). Objectif : pouvoir répondre à « qui a demandé
-- de l'aide, sur quel écran, quand, avec quel résultat technique »
-- sans dupliquer des données métier potentiellement sensibles.
--
-- Statut : PROPOSÉ SEUL. À appliquer sur DEMO puis production uniquement
-- après autorisation explicite distincte (même protocole que les
-- migrations carbone 01-09 précédentes).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.assistant_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    portal_role TEXT,
    screen TEXT NOT NULL,
    object_id_provided BOOLEAN NOT NULL DEFAULT false,
    question_length INTEGER NOT NULL,
    context_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
    answer_length INTEGER NOT NULL,
    model TEXT NOT NULL,
    latency_ms INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
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
  'Ne contient jamais la question ni la réponse complètes — uniquement métadonnées et longueurs.';
