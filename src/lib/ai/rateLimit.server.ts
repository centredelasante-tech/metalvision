import 'server-only';

/**
 * Limiteur de débit en mémoire (fenêtre glissante simple).
 *
 * Limitation connue et assumée pour cette passe (GATE IA-1) : l'état vit en
 * mémoire du process Node. Sur un déploiement serverless multi-instance
 * (Vercel), chaque instance a son propre compteur — la limite réelle
 * observée peut donc être un multiple de `limit` selon le nombre
 * d'instances actives. C'est une protection de premier niveau contre un
 * abus grossier (script en boucle, clé exposée), pas une garantie stricte.
 * Un limiteur centralisé (table Postgres ou Redis) est recommandé avant
 * une mise à l'échelle réelle — non fait ici (aucune migration appliquée
 * dans cette passe).
 */

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  retryAfterMs: number;
}

type Store = Map<string, number[]>;

export function createRateLimitStore(): Store {
  return new Map();
}

/**
 * Fonction pure (testable) : `now` est injecté plutôt que lu via Date.now()
 * directement, pour permettre des tests déterministes.
 */
export function checkRateLimit(
  store: Store,
  key: string,
  limit: number,
  windowMs: number,
  now: number
): RateLimitResult {
  const timestamps = (store.get(key) ?? []).filter((t) => now - t < windowMs);

  if (timestamps.length >= limit) {
    const oldest = timestamps[0];
    store.set(key, timestamps);
    return { allowed: false, remaining: 0, retryAfterMs: Math.max(0, windowMs - (now - oldest)) };
  }

  timestamps.push(now);
  store.set(key, timestamps);
  return { allowed: true, remaining: limit - timestamps.length, retryAfterMs: 0 };
}

// Store partagé au niveau du module pour les routes réelles (Node conserve
// l'instance du module tant que le process/lambda vit).
export const assistantAskRateLimitStore = createRateLimitStore();
export const analyzePhotoRateLimitStore = createRateLimitStore();
