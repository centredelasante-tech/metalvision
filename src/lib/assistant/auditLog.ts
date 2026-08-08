import 'server-only';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CarbonScreen } from './screens';

export interface AssistantInteractionLog {
  portalRole: string | null;
  screen: CarbonScreen;
  /** Identifiant technique (UUID) de l'objet consulté, ou null. Un UUID
   *  n'est pas une donnée métier sensible — c'est un pointeur, utile pour
   *  corréler une interaction à un objet précis en cas d'investigation.
   *  Ne stocke jamais le contenu de l'objet lui-même. */
  objectId: string | null;
  questionLength: number;
  contextSummary: Record<string, unknown>;
  answerLength: number;
  model: string;
  /** Tokens rapportés par le SDK LLM (Usage.prompt_tokens/completion_tokens),
   *  quand disponibles — sinon null. Jamais estimés ni recalculés ici. */
  promptTokens: number | null;
  completionTokens: number | null;
  latencyMs: number;
  status: 'success' | 'error';
  /** Code d'erreur sûr (ex. 'llm_upstream_error'), jamais le message brut ni
   *  la stack — voir src/lib/ai/safeError.ts. Null si status='success'. */
  errorCode: string | null;
}

/**
 * Journalise une interaction dans `assistant_interactions` (schéma proposé
 * dans supabase/carbon_migrations_proposed/15_assistant_interactions_audit_log.sql
 * — migration NON appliquée dans cette passe, voir rapport GATE IA-1).
 *
 * Minimisation des données — ce qui N'EST JAMAIS stocké : la question
 * complète, la réponse complète du modèle, le contexte métier complet
 * (contenu des lignes lues), ni aucun document/preuve. Ce qui est stocké :
 * des métadonnées d'audit bornées (utilisateur, rôle, écran, identifiant
 * technique de l'objet consulté, modèle, statut, durée, longueurs et
 * compteurs de tokens quand disponibles, horodatage, et un résumé de forme
 * du contexte — clés et tailles uniquement, jamais les valeurs). Objectif :
 * pouvoir répondre à « qui a demandé de l'aide, sur quel écran, quand, avec
 * quel résultat technique » sans dupliquer de données métier potentiellement
 * sensibles dans une table supplémentaire.
 *
 * Échoue silencieusement (log console uniquement) si la table n'existe pas
 * encore — la journalisation ne doit jamais faire échouer la réponse à
 * l'utilisateur.
 */
export async function logAssistantInteraction(
  supabase: SupabaseClient,
  userId: string,
  entry: AssistantInteractionLog
): Promise<void> {
  try {
    const { error } = await supabase.from('assistant_interactions').insert({
      user_id: userId,
      portal_role: entry.portalRole,
      screen: entry.screen,
      object_id: entry.objectId,
      question_length: entry.questionLength,
      context_summary: summarizeContext(entry.contextSummary),
      answer_length: entry.answerLength,
      model: entry.model,
      prompt_tokens: entry.promptTokens,
      completion_tokens: entry.completionTokens,
      latency_ms: entry.latencyMs,
      status: entry.status,
      error_code: entry.errorCode,
    });
    if (error) {
      console.error('[assistant_interactions] insert failed (table absente ou RLS) :', error.message);
    }
  } catch (err) {
    console.error('[assistant_interactions] insert exception :', err);
  }
}

/** Ne conserve que la forme du contexte (clés + longueur), jamais les valeurs. */
function summarizeContext(context: Record<string, unknown>): Record<string, unknown> {
  const summary: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(context)) {
    if (Array.isArray(value)) {
      summary[key] = { type: 'array', length: value.length };
    } else if (value === null) {
      summary[key] = null;
    } else if (typeof value === 'object') {
      summary[key] = { type: 'object', keys: Object.keys(value as object).length };
    } else {
      summary[key] = { type: typeof value };
    }
  }
  return summary;
}
