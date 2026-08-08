-- ============================================================
-- PROPOSÉE — 17_ai_distributed_rate_limit.sql
-- GATE IA-3 : rate limiting distribué, persistant et atomique
-- ============================================================
-- Contexte : le rate limiter actuel (src/lib/ai/rateLimit.server.ts) vit en
-- mémoire du process Node — inefficace sur Vercel serverless multi-instance
-- (chaque lambda a son propre compteur, remis à zéro à chaque cold start ;
-- voir l'avertissement documenté dans ce fichier depuis GATE IA-1). Cette
-- migration additive introduit un compteur PARTAGÉ dans Postgres, borné par
-- utilisateur (auth.uid() côté DB, jamais un identifiant fourni par le
-- client) et par "scope" (assistant / analyze_photo), avec deux fenêtres
-- par scope (minute + jour).
--
-- Atomicité / concurrence (GATE IA-3, point 9) : l'incrémentation ET la
-- vérification du seuil sont combinées en UNE seule instruction SQL par
-- fenêtre :
--   INSERT ... ON CONFLICT (clé) DO UPDATE SET count = count + 1
--     WHERE count < seuil
--   RETURNING count
-- Si la clause WHERE exclut la ligne (seuil déjà atteint), aucune ligne
-- n'est ni insérée ni mise à jour et RETURNING ne renvoie rien — c'est le
-- comportement standard documenté de Postgres pour ON CONFLICT DO UPDATE
-- avec clause WHERE. Deux requêtes concurrentes au seuil exact se
-- sérialisent sur le verrou de ligne acquis par cette même instruction
-- (upsert atomique standard Postgres) : il ne peut structurellement pas y
-- avoir deux acceptations pour un seul slot restant. Aucun verrou explicite
-- supplémentaire n'est nécessaire.
--
-- Identité (GATE IA-3, point 4) : la fonction ci-dessous ne prend AUCUN
-- paramètre user_id. Le sujet est exclusivement auth.uid(), résolu côté
-- Postgres à partir du JWT de la session — rien de fourni par le navigateur
-- ne peut jamais désigner un autre compteur que celui de l'appelant.
--
-- Service role (GATE IA-3, point 8) : aucun. La fonction est appelée par le
-- client Supabase authentifié de la requête (mêmes cookies de session que
-- le reste de /api/assistant/ask et /api/ai/analyze-photo). Elle est
-- SECURITY DEFINER uniquement pour pouvoir écrire dans la table de
-- compteurs SANS accorder de privilège table-level direct à authenticated
-- (REVOKE explicite plus bas, même schéma de durcissement que la migration
-- 16) — pas pour contourner l'authentification, qui reste vérifiée par
-- auth.uid() IS NULL en tout premier dans le corps de la fonction.
--
-- Dimension IP (GATE IA-3, point 7) : NON ajoutée dans cette passe. Les
-- deux endpoints concernés exigent déjà une authentification stricte
-- (aucun accès anonyme) ; auth.uid() est jugé suffisant comme identité de
-- rate limiting. Ajouter une dimension IP impliquerait de choisir une
-- finalité et une durée de conservation précises pour un hachage HMAC
-- (jamais l'IP en clair) — non fait faute de besoin anti-abus démontré
-- (ex. contournement par multi-comptes). Décision à réévaluer séparément
-- si un tel besoin apparaît ; ne bloque pas ce GATE.
--
-- Aucune migration 01-16 n'est modifiée. Statut : PROPOSÉE, à appliquer sur
-- METALVISION-DEMO uniquement dans le cadre de GATE IA-3. Production hors
-- périmètre — non appliquée.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Table de compteurs
-- ------------------------------------------------------------
CREATE TABLE public.ai_rate_limit_counters (
  user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope         text        NOT NULL CHECK (scope IN ('assistant', 'analyze_photo')),
  window_kind   text        NOT NULL CHECK (window_kind IN ('minute', 'day')),
  window_start  timestamptz NOT NULL,
  request_count integer     NOT NULL DEFAULT 0 CHECK (request_count >= 0),
  updated_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, scope, window_kind, window_start)
);

COMMENT ON TABLE public.ai_rate_limit_counters IS
  'Compteurs de rate limiting distribués pour les endpoints IA (GATE IA-3). '
  'Une ligne par (utilisateur, scope, type de fenêtre, début de fenêtre). '
  'Écriture exclusivement via la fonction SECURITY DEFINER check_ai_rate_limit() '
  '— aucun privilège table-level accordé à authenticated/anon/PUBLIC (voir plus bas). '
  'Purge : voir fonction purge_ai_rate_limit_counters() (fenêtres expirées).';

-- Index pour la purge périodique par ancienneté (voir fonction de purge).
CREATE INDEX idx_ai_rate_limit_counters_window_start
  ON public.ai_rate_limit_counters (window_start);

-- RLS activée par défaut-deny (aucune policy créée) : même en cas d'erreur
-- de GRANT future, personne ne peut lire/écrire cette table par une requête
-- PostgREST/anon normale. Le seul point d'accès prévu est la fonction
-- SECURITY DEFINER ci-dessous (elle contourne RLS car elle s'exécute avec
-- les privilèges du propriétaire de la table).
ALTER TABLE public.ai_rate_limit_counters ENABLE ROW LEVEL SECURITY;

-- Aucun privilège table-level pour PUBLIC/anon/authenticated : la seule
-- porte d'entrée est la fonction check_ai_rate_limit() ci-dessous.
REVOKE ALL PRIVILEGES ON public.ai_rate_limit_counters FROM PUBLIC;
REVOKE ALL PRIVILEGES ON public.ai_rate_limit_counters FROM anon;
REVOKE ALL PRIVILEGES ON public.ai_rate_limit_counters FROM authenticated;

-- ------------------------------------------------------------
-- 2. Type de retour de la fonction de vérification
-- ------------------------------------------------------------
CREATE TYPE public.ai_rate_limit_result AS (
  allowed              boolean,
  scope                text,
  limit_kind           text,     -- 'minute' | 'day' | NULL si allowed = true
  retry_after_seconds  integer,  -- NULL si allowed = true
  remaining_minute     integer,
  remaining_day        integer
);

-- ------------------------------------------------------------
-- 3. Fonction atomique de vérification + incrémentation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_ai_rate_limit(p_scope text)
RETURNS public.ai_rate_limit_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id       uuid := auth.uid();
  v_minute_limit  integer;
  v_day_limit     integer;
  v_now           timestamptz := clock_timestamp();
  v_minute_bucket timestamptz := date_trunc('minute', v_now);
  v_day_bucket    timestamptz := (date_trunc('day', v_now AT TIME ZONE 'UTC')) AT TIME ZONE 'UTC';
  v_minute_count  integer;
  v_day_count     integer;
  v_result        public.ai_rate_limit_result;
BEGIN
  -- Identité obligatoire, dérivée exclusivement côté serveur (point 4).
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'check_ai_rate_limit: authentification requise' USING ERRCODE = '28000';
  END IF;

  IF p_scope NOT IN ('assistant', 'analyze_photo') THEN
    RAISE EXCEPTION 'check_ai_rate_limit: scope invalide: %', p_scope USING ERRCODE = '22023';
  END IF;

  -- Seuils fixes (GATE IA-3, point 6). analyze_photo/jour fixé à 50 :
  -- proportionnel au ratio minute/jour de assistant (x10), en tenant compte
  -- du coût plus élevé d'un appel vision par rapport à un appel texte.
  -- Ajustable par une future migration si le besoin métier diverge —
  -- documenté ici plutôt que dans une table de config pour éviter une
  -- nouvelle surface RLS/GRANT pour un besoin encore non démontré.
  IF p_scope = 'assistant' THEN
    v_minute_limit := 20;
    v_day_limit := 200;
  ELSE
    v_minute_limit := 5;
    v_day_limit := 50;
  END IF;

  -- --- Fenêtre minute : incrément conditionnel atomique -------------------
  INSERT INTO public.ai_rate_limit_counters (user_id, scope, window_kind, window_start, request_count, updated_at)
  VALUES (v_user_id, p_scope, 'minute', v_minute_bucket, 1, v_now)
  ON CONFLICT (user_id, scope, window_kind, window_start) DO UPDATE
    SET request_count = public.ai_rate_limit_counters.request_count + 1,
        updated_at = v_now
    WHERE public.ai_rate_limit_counters.request_count < v_minute_limit
  RETURNING request_count INTO v_minute_count;

  IF NOT FOUND THEN
    -- Seuil minute atteint : rien n'a été incrémenté pour cette requête.
    SELECT request_count INTO v_minute_count
      FROM public.ai_rate_limit_counters
     WHERE user_id = v_user_id AND scope = p_scope AND window_kind = 'minute' AND window_start = v_minute_bucket;

    SELECT request_count INTO v_day_count
      FROM public.ai_rate_limit_counters
     WHERE user_id = v_user_id AND scope = p_scope AND window_kind = 'day' AND window_start = v_day_bucket;

    v_result.allowed := false;
    v_result.scope := p_scope;
    v_result.limit_kind := 'minute';
    v_result.retry_after_seconds := GREATEST(1, ceil(extract(epoch FROM (v_minute_bucket + interval '1 minute' - v_now)))::integer);
    v_result.remaining_minute := 0;
    v_result.remaining_day := GREATEST(0, v_day_limit - COALESCE(v_day_count, 0));
    RETURN v_result;
  END IF;

  -- --- Fenêtre jour : incrément conditionnel atomique ----------------------
  INSERT INTO public.ai_rate_limit_counters (user_id, scope, window_kind, window_start, request_count, updated_at)
  VALUES (v_user_id, p_scope, 'day', v_day_bucket, 1, v_now)
  ON CONFLICT (user_id, scope, window_kind, window_start) DO UPDATE
    SET request_count = public.ai_rate_limit_counters.request_count + 1,
        updated_at = v_now
    WHERE public.ai_rate_limit_counters.request_count < v_day_limit
  RETURNING request_count INTO v_day_count;

  IF NOT FOUND THEN
    -- Seuil jour atteint : annuler l'incrément minute déjà effectué juste
    -- au-dessus — une requête refusée ne doit consommer aucun quota réel,
    -- ni minute ni jour. La ligne minute reste verrouillée par notre propre
    -- transaction depuis l'UPSERT précédent : ce correctif est donc lui
    -- aussi atomique vis-à-vis de toute requête concurrente.
    UPDATE public.ai_rate_limit_counters
       SET request_count = GREATEST(request_count - 1, 0),
           updated_at = v_now
     WHERE user_id = v_user_id AND scope = p_scope AND window_kind = 'minute' AND window_start = v_minute_bucket
    RETURNING request_count INTO v_minute_count;

    SELECT request_count INTO v_day_count
      FROM public.ai_rate_limit_counters
     WHERE user_id = v_user_id AND scope = p_scope AND window_kind = 'day' AND window_start = v_day_bucket;

    v_result.allowed := false;
    v_result.scope := p_scope;
    v_result.limit_kind := 'day';
    v_result.retry_after_seconds := GREATEST(1, ceil(extract(epoch FROM (v_day_bucket + interval '1 day' - v_now)))::integer);
    v_result.remaining_minute := GREATEST(0, v_minute_limit - v_minute_count);
    v_result.remaining_day := 0;
    RETURN v_result;
  END IF;

  v_result.allowed := true;
  v_result.scope := p_scope;
  v_result.limit_kind := NULL;
  v_result.retry_after_seconds := NULL;
  v_result.remaining_minute := GREATEST(0, v_minute_limit - v_minute_count);
  v_result.remaining_day := GREATEST(0, v_day_limit - v_day_count);
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.check_ai_rate_limit(text) IS
  'Vérifie et incrémente atomiquement le compteur de rate limit (fenêtres '
  'minute + jour) pour l''utilisateur authentifié courant (auth.uid()) et le '
  'scope demandé (''assistant'' ou ''analyze_photo''). SECURITY DEFINER : '
  'seul point d''écriture autorisé sur ai_rate_limit_counters. Ne prend '
  'aucun paramètre user_id — l''identité est toujours dérivée côté serveur, '
  'jamais fournie par l''appelant (GATE IA-3, point 4).';

REVOKE ALL ON FUNCTION public.check_ai_rate_limit(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_ai_rate_limit(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_ai_rate_limit(text) TO authenticated;

-- ------------------------------------------------------------
-- 4. Purge des fenêtres expirées (hygiène, pas de croissance illimitée)
-- ------------------------------------------------------------
-- Fonction utilitaire, appelable manuellement ou par une tâche planifiée
-- (aucune tâche cron créée dans cette migration — hors périmètre GATE
-- IA-3). Supprime les fenêtres minute de plus d'1 heure et les fenêtres
-- jour de plus de 8 jours. Ne pas l'appeler ne casse rien fonctionnellement
-- (check_ai_rate_limit ne relit jamais une fenêtre passée) — seule la
-- taille de la table croît sans purge.
CREATE OR REPLACE FUNCTION public.purge_ai_rate_limit_counters()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM public.ai_rate_limit_counters
   WHERE (window_kind = 'minute' AND window_start < clock_timestamp() - interval '1 hour')
      OR (window_kind = 'day' AND window_start < clock_timestamp() - interval '8 days');
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.purge_ai_rate_limit_counters() IS
  'Purge les fenêtres de rate limit expirées (hygiène). Aucune tâche '
  'planifiée créée par cette migration — à brancher séparément (ex. '
  'pg_cron ou appel périodique applicatif) si la croissance de la table le '
  'justifie.';

-- Purge = opération d'administration, pas un besoin utilisateur : aucun
-- GRANT à authenticated/anon/PUBLIC. Appel prévu via un rôle privilégié
-- (dashboard SQL, service de maintenance) ou une future tâche planifiée.
REVOKE ALL ON FUNCTION public.purge_ai_rate_limit_counters() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_ai_rate_limit_counters() FROM anon;
REVOKE ALL ON FUNCTION public.purge_ai_rate_limit_counters() FROM authenticated;
