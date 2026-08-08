import 'server-only';
import { completion, type Message } from '@rocketnew/llm-sdk';

/**
 * Client LLM interne, exécuté exclusivement côté serveur.
 *
 * Contrairement à l'ancien `/api/ai/chat-completion` (supprimé — voir
 * GATE IA-1), ce module :
 *  - n'est jamais exposé comme route HTTP publique ;
 *  - ne laisse jamais l'appelant choisir le provider/modèle/clé API ;
 *  - est marqué `server-only` : toute tentative d'import depuis un
 *    composant client fait échouer le build.
 *
 * Chaque appelant interne (ex. /api/ai/analyze-photo, /api/assistant/ask)
 * doit passer un provider et un modèle fixes, définis dans son propre
 * code serveur — jamais depuis une valeur fournie par le client HTTP.
 */

export type LLMProvider = 'OPEN_AI' | 'ANTHROPIC' | 'GEMINI' | 'PERPLEXITY';

const API_KEYS: Record<LLMProvider, string | undefined> = {
  OPEN_AI: process.env.OPENAI_API_KEY,
  ANTHROPIC: process.env.ANTHROPIC_API_KEY,
  GEMINI: process.env.GEMINI_API_KEY,
  PERPLEXITY: process.env.PERPLEXITY_API_KEY,
};

export class LLMConfigurationError extends Error {
  constructor(provider: LLMProvider) {
    super(`Provider LLM non configuré : ${provider}`);
    this.name = 'LLMConfigurationError';
  }
}

/** Erreur générique, sûre à journaliser sans fuite de secret (jamais de clé API dans le message). */
export class LLMUpstreamError extends Error {
  constructor(public readonly provider: LLMProvider, public readonly cause: unknown) {
    super(`Erreur du fournisseur ${provider}`);
    this.name = 'LLMUpstreamError';
  }
}

export type MessageContentPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: { url: string } };

export interface ServerCompletionParams {
  provider: LLMProvider;
  model: string;
  messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string | MessageContentPart[] }>;
  maxTokens: number;
  temperature?: number;
}

export function isProviderConfigured(provider: LLMProvider): boolean {
  return Boolean(API_KEYS[provider]);
}

/**
 * Appelle le SDK LLM directement (aucun aller-retour HTTP interne).
 * Ne journalise et ne renvoie jamais la clé API ni le corps brut d'erreur
 * du fournisseur — voir LLMUpstreamError.
 */
export async function getServerCompletion(params: ServerCompletionParams) {
  const apiKey = API_KEYS[params.provider];
  if (!apiKey) {
    throw new LLMConfigurationError(params.provider);
  }

  try {
    // Le SDK expose un modèle de types très large (tool calls, thinking blocks,
    // multi-provider…) ; nos messages (system/user, texte ou texte+image) en sont
    // un sous-ensemble structurellement compatible. Cast localisé, unique point
    // d'intégration avec le SDK externe.
    const response = await completion({
      model: params.model,
      messages: params.messages as unknown as Message[],
      stream: false,
      api_key: apiKey,
      temperature: params.temperature ?? 0.2,
      max_tokens: params.maxTokens,
    });
    return response;
  } catch (error) {
    // On ne relaie jamais l'erreur brute (peut contenir des en-têtes/URL avec la clé) —
    // seul le type d'erreur et le provider sont conservés pour la journalisation serveur.
    throw new LLMUpstreamError(params.provider, error);
  }
}
