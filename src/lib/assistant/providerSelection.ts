import type { LLMProvider } from '@/lib/ai/llmClient.server';
import { isProviderConfigured } from '@/lib/ai/llmClient.server';

/**
 * Ordre de préférence FIXE, défini côté serveur — jamais choisi par le
 * client. Un seul provider est utilisé par requête (le premier configuré),
 * pour limiter la surface (pas de sélection dynamique exposée).
 */
const PROVIDER_PRIORITY: Array<{ provider: LLMProvider; model: string }> = [
  { provider: 'ANTHROPIC', model: 'anthropic/claude-3-5-haiku-20241022' },
  { provider: 'OPEN_AI', model: 'openai/gpt-4o-mini' },
  { provider: 'GEMINI', model: 'gemini/gemini-2.5-flash' },
];

export function selectConfiguredProvider(): { provider: LLMProvider; model: string } | null {
  for (const candidate of PROVIDER_PRIORITY) {
    if (isProviderConfigured(candidate.provider)) {
      return candidate;
    }
  }
  return null;
}
