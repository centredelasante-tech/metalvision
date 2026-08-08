import 'server-only';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CarbonScreen } from './screens';

export interface AssistantInteractionLog {
  portalRole: string | null;
  screen: CarbonScreen;
  objectIdProvided: boolean;
  questionLength: number;
  contextSummary: Record<string, unknown>;
  answerLength: number;
  model: string;
  latencyMs: number;
}

/**
 * Journalise une interaction dans `assistant_interactions` (schéma proposé
 * dans supabase/carbon_migrations_proposed/10_assistant_interactions_audit_log.sql
 * — migration NON appliquée dans cette passe, voir rapport GATE IA-1).
 *
 * Minimisation des données : ni la question ni la réponse complètes ne sont
 * stockées — uniquement leur longueur et un résumé borné du contexte
 * (clés + tailles, jamais les valeurs métier complètes). Objectif :
 * auditabilité (qui a posé une question sur quel écran, quand, avec quel
 * résultat technique) sans dupliquer des données métier potentiellement
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
      object_id_provided: entry.objectIdProvided,
      question_length: entry.questionLength,
      context_summary: summarizeContext(entry.contextSummary),
      answer_length: entry.answerLength,
      model: entry.model,
      latency_ms: entry.latencyMs,
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
