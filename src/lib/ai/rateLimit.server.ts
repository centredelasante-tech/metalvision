import 'server-only';

/**
 * Limiteur de débit en mémoire (fenêtre glissante simple).
 *
 * ⚠️ STATUT : MÉCANISME PROVISOIRE DE DÉVELOPPEMENT / PREVIEW UNIQUEMENT.
 * NON SUFFISANT POUR LA PRODUCTION SERVERLESS. Ne pas présenter ce
 * mécanisme comme clôturant le risque d'abus en production.
 *
 * L'état vit en mémoire du process Node, propre à chaque instance. Sur un
 * déploiement serverless multi-instance (Vercel, et toute plateforme
 * équivalente en production), chaque instance/lambda a son propre compteur
 * indépendant, remis à zéro à chaque cold start — la limite RÉELLEMENT
 * observée en production peut donc être un multiple arbitraire, non borné,
 * de `limit` selon le nombre d'instances actives, et peut même être
 * totalement inefficace contre un abus distribué ou persistant. Ce n'est
 * PAS une garantie de protection contre les abus en production — seulement
 * un filet de premier niveau utile en développement/Preview (process Node
 * unique, généralement une seule instance) contre un abus grossier local
 * (script en boucle, clé exposée en environnement non critique).
 *
 * Avant tout déploiement en production avec du trafic réel, ce mécanisme
 * DOIT être remplacé par un limiteur centralisé et partagé entre instances
 * (ex. table Postgres avec verrou/compteur atomique, ou Redis/Upstash) —
 * non fait dans cette passe (GATE IA-1), aucune migration appliquée.
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
