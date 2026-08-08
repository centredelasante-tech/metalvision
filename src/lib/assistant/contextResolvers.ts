import 'server-only';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CarbonScreen } from './screens';

/**
 * Résolveurs de contexte — allowlist fixe, une fonction par écran (GATE IA-1).
 *
 * Règles strictes :
 *  - chaque résolveur exécute UNIQUEMENT des `.select()` prédéfinis, jamais de
 *    SQL construit dynamiquement ni de RPC d'écriture ;
 *  - `supabase` est toujours le client authentifié de la requête (cookies de
 *    session) — jamais un client service role. Les policies RLS déjà
 *    validées (82/82) s'appliquent donc automatiquement, y compris pour un
 *    `objectId` arbitraire fourni par le client (une ligne hors RLS revient
 *    simplement vide, jamais une erreur qui confirmerait son existence) ;
 *  - la sortie est bornée (LIMIT explicite, colonnes choisies) — jamais un
 *    dump de table.
 *
 * Ceci est une V1 volontairement minimale : chaque résolveur donne un aperçu
 * factuel borné de l'écran, pas une réplique exhaustive de sa logique
 * métier. Le modèle doit se limiter à ce contexte, jamais l'inventer.
 */

export type ContextResolver = (
  supabase: SupabaseClient,
  opts: { objectId?: string }
) => Promise<Record<string, unknown>>;

async function resolveVerificationSessions(supabase: SupabaseClient): Promise<Record<string, unknown>> {
  const { data, error } = await supabase
    .from('verification_sessions')
    .select('id, status, verifier_org, created_at')
    .order('created_at', { ascending: false })
    .limit(5);
  return { recent_sessions: error ? [] : data };
}

async function resolveVerifierMrv(supabase: SupabaseClient): Promise<Record<string, unknown>> {
  // RLS scope déjà les lignes au vérificateur assigné (is_assigned_verifier()).
  const { data, error } = await supabase
    .from('verification_sessions')
    .select('id, status, scope, created_at')
    .order('created_at', { ascending: false })
    .limit(5);
  return { assigned_sessions: error ? [] : data };
}

async function resolveCarbonInventory(supabase: SupabaseClient): Promise<Record<string, unknown>> {
  const [issuances, lots] = await Promise.all([
    supabase.from('credit_issuances').select('id, status, created_at').order('created_at', { ascending: false }).limit(5),
    supabase.from('credit_lots').select('id, quantity_tco2e, commercial_status, vintage_year').order('created_at', { ascending: false }).limit(5),
  ]);
  return {
    recent_issuances: issuances.error ? [] : issuances.data,
    recent_lots: lots.error ? [] : lots.data,
  };
}

async function resolveRegroupementDistribution(
  supabase: SupabaseClient,
  opts: { objectId?: string }
): Promise<Record<string, unknown>> {
  if (!opts.objectId) {
    return { active_rule: null, note: 'Aucun regroupement précisé.' };
  }
  const [activeRule, proposals] = await Promise.all([
    supabase
      .from('distribution_rules')
      .select('id, platform_fee_pct, reserve_pct, effective_from, effective_to')
      .eq('aggregator_id', opts.objectId)
      .is('effective_to', null)
      .maybeSingle(),
    supabase
      .from('distribution_rule_proposals')
      .select('id, status, created_at')
      .eq('aggregator_id', opts.objectId)
      .order('created_at', { ascending: false })
      .limit(3),
  ]);
  return {
    active_rule: activeRule.error ? null : activeRule.data,
    recent_proposals: proposals.error ? [] : proposals.data,
  };
}

async function resolveCarbonSales(
  supabase: SupabaseClient,
  opts: { objectId?: string }
): Promise<Record<string, unknown>> {
  if (opts.objectId) {
    const { data, error } = await supabase
      .from('credit_sales')
      .select('id, status, total_tco2e, gross_amount, net_distributable_amount, buyer_reference')
      .eq('id', opts.objectId)
      .maybeSingle();
    return { sale: error ? null : data };
  }
  const { data, error } = await supabase
    .from('credit_sales')
    .select('id, status, total_tco2e, created_at')
    .order('created_at', { ascending: false })
    .limit(5);
  return { recent_sales: error ? [] : data };
}

async function resolveCarbonProjects(supabase: SupabaseClient): Promise<Record<string, unknown>> {
  const { data, error } = await supabase
    .from('projects')
    .select('id, name, status')
    .order('created_at', { ascending: false })
    .limit(5);
  return { recent_projects: error ? [] : data };
}

async function resolveMrvProject(
  supabase: SupabaseClient,
  opts: { objectId?: string }
): Promise<Record<string, unknown>> {
  if (!opts.objectId) {
    return { project: null, note: 'Aucun projet précisé.' };
  }
  const [project, logs] = await Promise.all([
    supabase.from('projects').select('id, name, status').eq('id', opts.objectId).maybeSingle(),
    supabase
      .from('project_activity_logs')
      .select('id, activity_type, "timestamp"')
      .eq('project_id', opts.objectId)
      .order('timestamp', { ascending: false })
      .limit(5),
  ]);
  return {
    project: project.error ? null : project.data,
    recent_activity: logs.error ? [] : logs.data,
  };
}

async function resolveCarbonImpact(supabase: SupabaseClient): Promise<Record<string, unknown>> {
  const { data, error } = await supabase
    .from('credit_lots')
    .select('quantity_tco2e, commercial_status')
    .limit(20);
  return { visible_lots_sample: error ? [] : data };
}

export const CONTEXT_RESOLVERS: Record<CarbonScreen, ContextResolver> = {
  'admin-verification-sessions': resolveVerificationSessions,
  'verifier-mrv': resolveVerifierMrv,
  'admin-carbon-inventory': resolveCarbonInventory,
  'admin-regroupement-distribution': resolveRegroupementDistribution,
  'admin-carbon-sales': resolveCarbonSales,
  'admin-carbon-projects': resolveCarbonProjects,
  'admin-mrv-project': resolveMrvProject,
  'carbon-impact': resolveCarbonImpact,
};
