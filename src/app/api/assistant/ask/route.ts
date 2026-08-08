import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { getServerCompletion, LLMUpstreamError } from '@/lib/ai/llmClient.server';
import { checkDistributedRateLimit } from '@/lib/ai/distributedRateLimit.server';
import { toSafeErrorResponse, ValidationError, UnauthorizedError, RateLimitedError } from '@/lib/ai/safeError';
import { isCarbonScreen, isValidObjectId, type CarbonScreen } from '@/lib/assistant/screens';
import { CONTEXT_RESOLVERS } from '@/lib/assistant/contextResolvers';
import { buildSystemPrompt, buildUserMessage, QuestionTooLongError } from '@/lib/assistant/systemPrompt';
import { selectConfiguredProvider } from '@/lib/assistant/providerSelection';
import { logAssistantInteraction } from '@/lib/assistant/auditLog';
import { getPortalRole, PortalRoleError } from '@/lib/auth/getPortalRole';

// GATE IA-1 — POST /api/assistant/ask
//
// Garde-fous structurels (voir Agent-Aide-MetalTrace-V1-Architecture.md) :
//  1. auth.getUser() obligatoire — 401 sinon, avant toute autre opération.
//  2. Rate limit par utilisateur — 429 si dépassé. Mécanisme distribué,
//     persistant et atomique en base Postgres (GATE IA-3 — voir
//     supabase/carbon_migrations_proposed/17_ai_distributed_rate_limit.sql
//     et src/lib/ai/distributedRateLimit.server.ts). Identité dérivée
//     exclusivement de auth.uid() côté DB, jamais d'un user_id fourni par
//     le client.
//  3. `screen` validé contre une allowlist fixe (8 écrans carbone) — 400 sinon.
//  4. Contexte résolu exclusivement via CONTEXT_RESOLVERS (lectures fixes,
//     client Supabase authentifié = RLS active) — jamais de SQL du modèle.
//  5. Aucun function-calling/tool exposé au modèle — aucune capacité d'écriture.
//  6. Prompt système figé, non modifiable par l'utilisateur (voir systemPrompt.ts).
//  7. Erreurs toujours sanitisées (toSafeErrorResponse) — jamais de fuite de secret.
//  8. Journalisation minimisant les données sensibles (voir auditLog.ts et
//     supabase/carbon_migrations_proposed/15_assistant_interactions_audit_log.sql —
//     migration PROPOSÉE, NON appliquée).

const MAX_ANSWER_TOKENS = 800;

interface AskRequestBody {
  screen?: unknown;
  question?: unknown;
  objectId?: unknown;
}

export async function POST(req: NextRequest) {
  const startedAt = Date.now();
  try {
    // 1. Authentification obligatoire.
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();
    if (authError || !user) {
      throw new UnauthorizedError();
    }

    // 2. Rate limiting distribué par utilisateur (Postgres, GATE IA-3).
    const rl = await checkDistributedRateLimit(supabase, 'assistant');
    if (!rl.allowed) {
      throw new RateLimitedError(rl.retryAfterMs);
    }

    // 3. Validation stricte de l'entrée.
    let body: AskRequestBody;
    try {
      body = await req.json();
    } catch {
      throw new ValidationError('Corps de requête JSON invalide.');
    }

    if (!isCarbonScreen(body.screen)) {
      throw new ValidationError('Écran non couvert par l\'Agent d\'aide V1.');
    }
    const screen: CarbonScreen = body.screen;

    if (typeof body.question !== 'string' || body.question.trim().length === 0) {
      throw new ValidationError('question est requis.');
    }
    const question = body.question.trim();

    let objectId: string | undefined;
    if (body.objectId !== undefined && body.objectId !== null) {
      if (!isValidObjectId(body.objectId)) {
        throw new ValidationError('objectId doit être un UUID valide.');
      }
      objectId = body.objectId;
    }

    // 4. Résolution du contexte — allowlist fixe, client authentifié (RLS active).
    //    Un objectId arbitraire hors de portée RLS de l'utilisateur revient
    //    simplement vide (voir contextResolvers.ts) — jamais une fuite.
    const resolver = CONTEXT_RESOLVERS[screen];
    const context = await resolver(supabase, { objectId });

    // Rôle de portail — même source de vérité canonique que login/admin/
    // verifier-mrv (getPortalRole() -> RPC get_my_portal_role()). Utilisé ici
    // uniquement pour la journalisation, jamais comme logique d'autorisation
    // additionnelle : RLS fait déjà le travail sur chaque résolveur.
    let portalRole: string | null = null;
    try {
      portalRole = await getPortalRole(supabase);
    } catch (e) {
      if (!(e instanceof PortalRoleError)) throw e;
      // Rôle non résolu : on journalise quand même l'interaction (portalRole=null),
      // on ne bloque jamais l'assistant pour un échec de résolution de rôle.
    }

    const provider = selectConfiguredProvider();
    if (!provider) {
      return NextResponse.json(
        { error: 'Assistant indisponible pour le moment.', code: 'llm_not_configured' },
        { status: 503 }
      );
    }

    // 5/6. Aucun tool/function-calling transmis — le modèle ne peut techniquement
    //      rien invoquer. Prompt système figé, question traitée comme donnée.
    const systemPrompt = buildSystemPrompt(screen);
    const userMessage = buildUserMessage(question, context);

    let completion;
    try {
      completion = await getServerCompletion({
        provider: provider.provider,
        model: provider.model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage },
        ],
        maxTokens: MAX_ANSWER_TOKENS,
        temperature: 0.2,
      });
    } catch (llmErr) {
      // Échec de l'appel LLM après authentification : journalisé comme
      // interaction en échec (statut='error', jamais le message brut), pour
      // que l'audit reste complet même quand la réponse finale est une erreur.
      const errorCode = llmErr instanceof LLMUpstreamError ? 'llm_upstream_error' : 'llm_configuration_error';
      await logAssistantInteraction(supabase, user.id, {
        portalRole,
        screen,
        objectId: objectId ?? null,
        questionLength: question.length,
        contextSummary: context,
        answerLength: 0,
        model: provider.model,
        promptTokens: null,
        completionTokens: null,
        latencyMs: Date.now() - startedAt,
        status: 'error',
        errorCode,
      });
      throw llmErr;
    }

    const answer = completion?.choices?.[0]?.message?.content ?? '';
    const answerText = typeof answer === 'string' ? answer : JSON.stringify(answer);

    // 8. Journalisation (best-effort, ne bloque jamais la réponse). Ne stocke
    //    jamais la question/réponse complètes ni le contenu du contexte —
    //    voir auditLog.ts pour le détail exact des champs conservés.
    await logAssistantInteraction(supabase, user.id, {
      portalRole,
      screen,
      objectId: objectId ?? null,
      questionLength: question.length,
      contextSummary: context,
      answerLength: answerText.length,
      model: provider.model,
      promptTokens: completion?.usage?.prompt_tokens ?? null,
      completionTokens: completion?.usage?.completion_tokens ?? null,
      latencyMs: Date.now() - startedAt,
      status: 'success',
      errorCode: null,
    });

    return NextResponse.json({ screen, answer: answerText });
  } catch (err: unknown) {
    if (err instanceof QuestionTooLongError) {
      return NextResponse.json({ error: err.message, code: 'validation_error' }, { status: 400 });
    }
    const { status, body } = toSafeErrorResponse(err, 'assistant/ask');
    if (err instanceof RateLimitedError) {
      return NextResponse.json(body, { status, headers: { 'Retry-After': String(Math.ceil(err.retryAfterMs / 1000)) } });
    }
    return NextResponse.json(body, { status });
  }
}
