import 'server-only';
import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Client applicatif du rate limiter distribué (GATE IA-3).
 *
 * Remplace l'ancien mécanisme en mémoire (src/lib/ai/rateLimit.server.ts,
 * retiré — voir migration 17 pour le détail de la limitation qu'il avait :
 * un compteur par instance/lambda Vercel, remis à zéro à chaque cold start,
 * donc sans garantie réelle en production serverless).
 *
 * Le compteur vit désormais dans Postgres (table `ai_rate_limit_counters`,
 * fonction SECURITY DEFINER `check_ai_rate_limit`) — partagé entre toutes
 * les instances, persistant, et atomique sous concurrence (voir la
 * migration pour la preuve du mécanisme d'upsert conditionnel).
 *
 * Appel : toujours via le client Supabase AUTHENTIFIÉ de la requête (celui
 * construit par `createClient()` côté serveur, lié aux cookies de session)
 * — jamais un client service-role. L'identité du sujet est déterminée
 * exclusivement par `auth.uid()` côté Postgres ; cette fonction ne transmet
 * et ne peut transmettre aucun identifiant utilisateur.
 */

export type AiRateLimitScope = 'assistant' | 'analyze_photo';

export interface DistributedRateLimitResult {
  allowed: boolean;
  scope: AiRateLimitScope;
  limitKind: 'minute' | 'day' | null;
  /** 0 si allowed = true. */
  retryAfterMs: number;
  remainingMinute: number;
  remainingDay: number;
}

/**
 * Erreur de vérification du rate limit (RPC en échec — table absente,
 * fonction absente, erreur réseau/DB, etc.). Volontairement distincte de
 * "rate limité" : ici on ne sait pas si la requête aurait dû être autorisée
 * ou non.
 *
 * Choix explicite : FAIL CLOSED. Un mécanisme anti-abus qui échoue en
 * laissant passer silencieusement (fail open) en cas d'erreur DB perdrait
 * sa garantie précisément quand elle compte le plus (une panne/erreur peut
 * elle-même être le symptôme d'un abus en cours). L'appelant doit donc
 * traiter cette erreur comme un refus (429 ou 503 selon le contexte),
 * jamais comme une autorisation implicite.
 */
export class RateLimitCheckError extends Error {}

interface CheckAiRateLimitRpcRow {
  allowed: boolean;
  scope: AiRateLimitScope;
  limit_kind: 'minute' | 'day' | null;
  retry_after_seconds: number | null;
  remaining_minute: number;
  remaining_day: number;
}

export async function checkDistributedRateLimit(
  supabase: SupabaseClient,
  scope: AiRateLimitScope
): Promise<DistributedRateLimitResult> {
  const { data, error } = await supabase.rpc('check_ai_rate_limit', { p_scope: scope });

  if (error || !data) {
    throw new RateLimitCheckError(error?.message ?? 'check_ai_rate_limit: réponse vide');
  }

  const row = data as CheckAiRateLimitRpcRow;
  return {
    allowed: row.allowed,
    scope: row.scope,
    limitKind: row.limit_kind,
    retryAfterMs: row.retry_after_seconds != null ? row.retry_after_seconds * 1000 : 0,
    remainingMinute: row.remaining_minute,
    remainingDay: row.remaining_day,
  };
}
