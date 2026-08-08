import type { LLMProvider } from '@/lib/ai/llmClient.server';
import { isProviderConfigured } from '@/lib/ai/llmClient.server';

/**
 * Sélection du provider LLM — GATE IA-PROD-1 / GATE D0.
 *
 * Avant GATE D0 : le premier provider "configuré" (clé API présente) dans un
 * ordre de priorité fixe (Anthropic -> OpenAI -> Gemini) était choisi
 * silencieusement. Ce comportement masquait une mauvaise configuration :
 * l'absence de la clé attendue en tête de liste faisait basculer, sans
 * signal, vers un autre fournisseur (modèle différent, coût différent,
 * comportement potentiellement différent) — jamais souhaitable en
 * Production, où le choix du fournisseur doit être un choix opérationnel
 * explicite et vérifiable, jamais une conséquence indirecte de la présence
 * ou de l'absence d'une variable d'environnement.
 *
 * GATE D0 supprime ce fallback silencieux : le provider est désormais choisi
 * exclusivement par la variable serveur `AI_LLM_PROVIDER` (jamais fournie ou
 * influençable par le client HTTP — lue uniquement côté serveur). Le modèle
 * associé à chaque valeur reste fixé côté serveur, jamais transmis par
 * l'appelant.
 *
 * Fail-closed strict : si `AI_LLM_PROVIDER` est absente, contient une valeur
 * hors de l'ensemble autorisé, ou si la clé API du provider ainsi désigné
 * est absente, cette fonction renvoie `null` — jamais un autre provider.
 * L'appelant (POST /api/assistant/ask) traite `null` comme "assistant non
 * configuré" -> 503 `llm_not_configured`, sans jamais tenter un autre
 * fournisseur (un seul appel à cette fonction par requête, pas de boucle).
 */

const MODEL_BY_PROVIDER = {
  anthropic: { provider: 'ANTHROPIC' as LLMProvider, model: 'anthropic/claude-haiku-4-5-20251001' },
  openai: { provider: 'OPEN_AI' as LLMProvider, model: 'openai/gpt-4o-mini' },
  gemini: { provider: 'GEMINI' as LLMProvider, model: 'gemini/gemini-2.5-flash' },
} as const;

type AllowedProviderValue = keyof typeof MODEL_BY_PROVIDER;

const ALLOWED_PROVIDER_VALUES: ReadonlySet<string> = new Set(Object.keys(MODEL_BY_PROVIDER));

function isAllowedProviderValue(value: string): value is AllowedProviderValue {
  return ALLOWED_PROVIDER_VALUES.has(value);
}

export function selectConfiguredProvider(): { provider: LLMProvider; model: string } | null {
  const raw = process.env.AI_LLM_PROVIDER;

  // Absente, ou valeur hors de l'ensemble autorisé (V1 : anthropic | openai |
  // gemini) -> échec de configuration. Jamais de valeur par défaut implicite.
  if (!raw || !isAllowedProviderValue(raw)) {
    return null;
  }

  const candidate = MODEL_BY_PROVIDER[raw];

  // Le provider explicitement désigné n'a pas sa clé API configurée -> échec
  // de configuration pour CE provider précisément. Aucune tentative vers un
  // autre fournisseur, même si sa clé à lui est présente.
  if (!isProviderConfigured(candidate.provider)) {
    return null;
  }

  return candidate;
}
