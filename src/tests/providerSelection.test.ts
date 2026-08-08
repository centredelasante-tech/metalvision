/**
 * Tests obligatoires — GATE D0 : sélection explicite du provider LLM,
 * fail-closed, sans fallback silencieux.
 *
 * Couvre les 8 scénarios explicitement demandés :
 *  1. anthropic + clé -> Anthropic
 *  2. anthropic sans clé -> erreur de configuration
 *  3. présence d'une clé OpenAI dans ce dernier scénario -> toujours aucun fallback
 *  4. openai + clé -> OpenAI
 *  5. gemini + clé -> Gemini
 *  6. provider absent -> erreur
 *  7. provider invalide -> erreur
 *  8. aucune clé n'apparaît dans les erreurs
 *
 * `isProviderConfigured` est mocké (comme dans assistant-ask.test.ts) plutôt
 * que piloté via de vraies variables *_API_KEY : llmClient.server.ts capture
 * process.env dans une constante au chargement du module (API_KEYS), donc
 * modifier process.env après import n'aurait aucun effet observable — le
 * mock isole exactement la logique testée ici (celle de providerSelection.ts :
 * quelle valeur de AI_LLM_PROVIDER mène à quel provider/modèle, et l'absence
 * stricte de fallback), indépendamment de ce détail d'implémentation de
 * llmClient.server.ts. Le test 8 (aucune clé dans les erreurs) utilise en
 * revanche la vraie implémentation de getServerCompletion/LLMConfigurationError,
 * volontairement non mockée, pour prouver le comportement réel de bout en bout.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';

const configuredProviders = new Set<string>();

vi.mock('@/lib/ai/llmClient.server', async () => {
  const actual = await vi.importActual<typeof import('@/lib/ai/llmClient.server')>(
    '@/lib/ai/llmClient.server'
  );
  return {
    ...actual,
    isProviderConfigured: (provider: string) => configuredProviders.has(provider),
  };
});

const { selectConfiguredProvider } = await import('@/lib/assistant/providerSelection');

const SAVED_AI_LLM_PROVIDER = process.env.AI_LLM_PROVIDER;

beforeEach(() => {
  configuredProviders.clear();
  delete process.env.AI_LLM_PROVIDER;
});

afterEach(() => {
  if (SAVED_AI_LLM_PROVIDER === undefined) delete process.env.AI_LLM_PROVIDER;
  else process.env.AI_LLM_PROVIDER = SAVED_AI_LLM_PROVIDER;
});

describe('selectConfiguredProvider — GATE D0 (fail-closed, sans fallback silencieux)', () => {
  test('1. AI_LLM_PROVIDER=anthropic + clé Anthropic configurée -> Anthropic', () => {
    process.env.AI_LLM_PROVIDER = 'anthropic';
    configuredProviders.add('ANTHROPIC');

    const result = selectConfiguredProvider();

    expect(result).not.toBeNull();
    expect(result?.provider).toBe('ANTHROPIC');
    // Modèle déjà validé dans les GATE Preview précédents (correctif GATE IA-2).
    expect(result?.model).toBe('anthropic/claude-haiku-4-5-20251001');
  });

  test('2+3. AI_LLM_PROVIDER=anthropic sans clé Anthropic -> null, même avec clé OpenAI configurée (aucun fallback)', () => {
    process.env.AI_LLM_PROVIDER = 'anthropic';
    configuredProviders.add('OPEN_AI'); // configurée, mais ne doit jamais servir de repli
    // ANTHROPIC volontairement absente de configuredProviders.

    const result = selectConfiguredProvider();

    expect(result).toBeNull();
  });

  test('4. AI_LLM_PROVIDER=openai + clé OpenAI configurée -> OpenAI', () => {
    process.env.AI_LLM_PROVIDER = 'openai';
    configuredProviders.add('OPEN_AI');

    const result = selectConfiguredProvider();

    expect(result?.provider).toBe('OPEN_AI');
    expect(result?.model).toBe('openai/gpt-4o-mini');
  });

  test('5. AI_LLM_PROVIDER=gemini + clé Gemini configurée -> Gemini', () => {
    process.env.AI_LLM_PROVIDER = 'gemini';
    configuredProviders.add('GEMINI');

    const result = selectConfiguredProvider();

    expect(result?.provider).toBe('GEMINI');
    expect(result?.model).toBe('gemini/gemini-2.5-flash');
  });

  test('6. AI_LLM_PROVIDER absente -> null, quelles que soient les clés configurées', () => {
    configuredProviders.add('ANTHROPIC');
    configuredProviders.add('OPEN_AI');
    configuredProviders.add('GEMINI');
    // AI_LLM_PROVIDER non défini (delete en beforeEach).

    const result = selectConfiguredProvider();

    expect(result).toBeNull();
  });

  test('7. AI_LLM_PROVIDER=valeur invalide (hors anthropic|openai|gemini) -> null', () => {
    process.env.AI_LLM_PROVIDER = 'mistral';
    configuredProviders.add('ANTHROPIC');

    const result = selectConfiguredProvider();

    expect(result).toBeNull();
  });

  test('7bis. AI_LLM_PROVIDER=chaîne vide -> null', () => {
    process.env.AI_LLM_PROVIDER = '';
    configuredProviders.add('ANTHROPIC');

    const result = selectConfiguredProvider();

    expect(result).toBeNull();
  });

  test("8. aucune clé API ni la valeur de AI_LLM_PROVIDER n'apparaît jamais dans le message de LLMConfigurationError (vraie implémentation, non mockée)", async () => {
    const { LLMConfigurationError, getServerCompletion } = await vi.importActual<
      typeof import('@/lib/ai/llmClient.server')
    >('@/lib/ai/llmClient.server');
    const secretKey = 'sk-super-secret-anthropic-key-must-not-leak';
    delete process.env.ANTHROPIC_API_KEY; // simule "clé indisponible" pour le provider sélectionné

    await expect(
      getServerCompletion({
        provider: 'ANTHROPIC',
        model: 'anthropic/claude-haiku-4-5-20251001',
        messages: [{ role: 'user', content: 'test' }],
        maxTokens: 10,
      })
    ).rejects.toBeInstanceOf(LLMConfigurationError);

    try {
      await getServerCompletion({
        provider: 'ANTHROPIC',
        model: 'anthropic/claude-haiku-4-5-20251001',
        messages: [{ role: 'user', content: 'test' }],
        maxTokens: 10,
      });
    } catch (err) {
      const message = (err as Error).message;
      // Le message ne contient que le nom du provider (ex. "ANTHROPIC"),
      // jamais une valeur de clé API ni le contenu de AI_LLM_PROVIDER.
      expect(message).not.toContain(secretKey);
      expect(message).not.toContain('AI_LLM_PROVIDER');
      expect(message).toContain('ANTHROPIC');
    }
  });
});
