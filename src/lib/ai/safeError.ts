import 'server-only';
import { LLMConfigurationError, LLMUpstreamError } from './llmClient.server';

/**
 * Traduit une erreur interne en réponse HTTP sûre : jamais de clé API, de
 * stack trace, ni de corps brut renvoyé par un fournisseur tiers dans la
 * réponse au client. Le détail complet reste uniquement dans les logs
 * serveur (console.error), jamais dans le corps de réponse.
 */
export interface SafeErrorResponse {
  status: number;
  body: { error: string; code: string };
}

export function toSafeErrorResponse(error: unknown, context: string): SafeErrorResponse {
  // Toujours journaliser le détail complet côté serveur uniquement.
  console.error(`[${context}]`, error);

  if (error instanceof LLMConfigurationError) {
    return { status: 503, body: { error: 'Assistant indisponible pour le moment.', code: 'llm_not_configured' } };
  }
  if (error instanceof LLMUpstreamError) {
    return { status: 502, body: { error: 'Le service IA est momentanément indisponible.', code: 'llm_upstream_error' } };
  }
  if (error instanceof ValidationError) {
    return { status: 400, body: { error: error.message, code: 'validation_error' } };
  }
  if (error instanceof UnauthorizedError) {
    return { status: 401, body: { error: 'Authentification requise.', code: 'unauthorized' } };
  }
  if (error instanceof RateLimitedError) {
    return { status: 429, body: { error: 'Trop de requêtes. Veuillez réessayer dans un instant.', code: 'rate_limited' } };
  }

  return { status: 500, body: { error: 'Une erreur interne est survenue.', code: 'internal_error' } };
}

export class ValidationError extends Error {}
export class UnauthorizedError extends Error {}
export class RateLimitedError extends Error {
  constructor(public readonly retryAfterMs: number) {
    super('rate_limited');
  }
}
