/**
 * POST /api/aggregator/calculate-sale
 * ============================================================================
 * Calcule la répartition des revenus d'une vente de crédits carbone entre
 * les membres contributeurs, puis enregistre le résultat dans
 * `credit_sale_allocations`.
 *
 * Corps de la requête attendu : { "saleId": "<uuid de credit_sales>" }
 *
 * Sécurité : toutes les requêtes Supabase utilisent le client authentifié
 * de l'utilisateur (pas le service role), donc les RLS policies déjà en
 * place sur `credit_sales`, `distribution_rules`, `member_distribution_
 * overrides` et `credit_sale_allocations` s'appliquent naturellement. * Un utilisateur qui n'est pas admin de l'agrégateur concerné (ni admin
 * plateforme) recevra simplement des résultats vides des requêtes SELECT,
 * et l'insertion finale échouera si la policy `sale_allocations_manage` * ne l'autorise pas — pas besoin de dupliquer la vérification de rôle ici.
 *
 * NOTE POUR ROCKET : cette route suppose l'existence d'un client Supabase * côté serveur à l'import `@/lib/supabase/server` (convention standard
 * @supabase/ssr, distincte du client utilisé côté navigateur dans
 * Topbar.tsx). Si le projet utilise un chemin différent pour le client
 * serveur, ajuster l'import ci-dessous en conséquence.
 */

import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import {
  calculateDistribution,
  type DistributionRule,
  type MemberOverride,
  type MemberContribution,
  type OverrideType,
} from '@/lib/distribution-calculator';

export async function POST(request: NextRequest) {
  const supabase = await createClient();

  // ── 1. Authentification ──────────────────────────────────────────────
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: 'Non authentifié.' }, { status: 401 });
  }

  // ── 2. Lecture du corps de la requête ────────────────────────────────
  let saleId: string;
  try {
    const body = await request.json();
    saleId = body.saleId;
    if (!saleId || typeof saleId !== 'string') {
      throw new Error('saleId manquant ou invalide.');
    }
  } catch {
    return NextResponse.json(
      { error: 'Corps de requête invalide — attendu: { "saleId": "<uuid>" }' },
      { status: 400 }
    );
  }

  // ── 3. Charger la vente ──────────────────────────────────────────────
  // La RLS "credit_sales_select" limite déjà ce SELECT aux admins de
  // l'agrégateur concerné (ou admin plateforme).
  const { data: sale, error: saleError } = await supabase
    .from('credit_sales')
    .select('id, aggregator_id, price_per_tco2e, sale_date, status')
    .eq('id', saleId)
    .single();

  if (saleError || !sale) {
    return NextResponse.json(
      { error: 'Vente introuvable ou accès non autorisé.' },
      { status: 404 }
    );
  }

  if (sale.status !== 'draft' && sale.status !== 'confirmed') {
    return NextResponse.json(
      { error: `Impossible de calculer une vente au statut "${sale.status}".` },
      { status: 409 }
    );
  }

  // ── 4. Charger les contributions par membre pour cette vente ─────────
  // credit_sale_lots -> credit_lots -> projects -> companies (client_id)
  const { data: saleLots, error: lotsError } = await supabase
    .from('credit_sale_lots')
    .select(
      `
      quantity_tco2e,
      credit_lots (
        project_id,
        projects ( client_id )
      )
    `
    )
    .eq('credit_sale_id', saleId);

  if (lotsError) {
    return NextResponse.json(
      { error: `Erreur lors du chargement des lots: ${lotsError.message}` },
      { status: 500 }
    );
  }

  if (!saleLots || saleLots.length === 0) {
    return NextResponse.json(
      { error: 'Aucun lot associé à cette vente — rien à répartir.' },
      { status: 422 }
    );
  }

  // Agrégation des tCO2e par company_id (un membre peut contribuer plusieurs lots)
  const contributionsByCompany = new Map<string, number>();
  for (const row of saleLots as unknown as Array<{
    quantity_tco2e: number;
    credit_lots: { project_id: string; projects: { client_id: string } | null } | null;
  }>) {
    const companyId = row.credit_lots?.projects?.client_id;
    if (!companyId) continue; // lot orphelin ou projet supprimé — ignoré, à surveiller si ça arrive
    contributionsByCompany.set(
      companyId,
      (contributionsByCompany.get(companyId) ?? 0) + row.quantity_tco2e
    );
  }

  const contributions: MemberContribution[] = Array.from(
    contributionsByCompany.entries()
  ).map(([companyId, contributedTco2e]) => ({ companyId, contributedTco2e }));

  if (contributions.length === 0) {
    return NextResponse.json(
      { error: 'Impossible de déterminer les membres contributeurs pour cette vente.' },
      { status: 422 }
    );
  }

  // ── 5. Charger la règle générale de l'agrégateur ──────────────────────
  // La plus récente dont effective_from <= sale_date.
  const { data: ruleRow, error: ruleError } = await supabase
    .from('distribution_rules')
    .select('aggregator_id, platform_fee_pct, reserve_pct, default_weight, effective_from')
    .eq('aggregator_id', sale.aggregator_id)
    .lte('effective_from', sale.sale_date)
    .order('effective_from', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (ruleError) {
    return NextResponse.json(
      { error: `Erreur lors du chargement de la règle de distribution: ${ruleError.message}` },
      { status: 500 }
    );
  }

  if (!ruleRow) {
    return NextResponse.json(
      {
        error:
          'Aucune règle de distribution active pour cet agrégateur à la date de la vente. Créer une entrée dans distribution_rules avant de calculer une répartition.',
      },
      { status: 422 }
    );
  }

  const rule: DistributionRule = {
    aggregatorId: ruleRow.aggregator_id,
    platformFeePct: ruleRow.platform_fee_pct,
    reservePct: ruleRow.reserve_pct,
    defaultWeight: ruleRow.default_weight,
  };

  // ── 6. Charger les overrides du regroupement ─────────────────────────
  // On charge tous les overrides du regroupement ; le filtrage par date
  // et par membre se fait dans calculateDistribution() elle-même.
  const { data: overrideRows, error: overrideError } = await supabase
    .from('member_distribution_overrides')
    .select('company_id, override_type, override_value, effective_from, effective_until')
    .eq('aggregator_id', sale.aggregator_id);

  if (overrideError) {
    return NextResponse.json(
      { error: `Erreur lors du chargement des overrides: ${overrideError.message}` },
      { status: 500 }
    );
  }

  const overrides: MemberOverride[] = (overrideRows ?? []).map((o) => ({
    companyId: o.company_id,
    overrideType: o.override_type as OverrideType,
    overrideValue: o.override_value,
    effectiveFrom: o.effective_from,
    effectiveUntil: o.effective_until,
  }));

  // ── 7. Calcul ─────────────────────────────────────────────────────────
  let result;
  try {
    result = calculateDistribution({
      saleDate: sale.sale_date,
      pricePerTco2e: sale.price_per_tco2e,
      contributions,
      rule,
      overrides,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Erreur de calcul inconnue.';
    return NextResponse.json({ error: message }, { status: 422 });
  }

  // ── 8. Enregistrement des allocations ────────────────────────────────
  // Upsert : si ce calcul est relancé (ex: correction d'un override),
  // les allocations précédentes pour cette vente sont remplacées.
  const rowsToInsert = result.allocations.map((a) => ({
    credit_sale_id: saleId,
    company_id: a.companyId,
    contributed_tco2e: a.contributedTco2e,
    gross_amount: a.grossAmount,
    fee_applied_pct: a.feeAppliedPct,
    reserve_applied_pct: a.reserveAppliedPct,
    weight_applied: a.weightApplied,
    net_amount: a.netAmount,
  }));

  const { error: insertError } = await supabase
    .from('credit_sale_allocations')
    .upsert(rowsToInsert, { onConflict: 'credit_sale_id,company_id' });

  if (insertError) {
    return NextResponse.json(
      {
        error: `Le calcul a réussi mais l'enregistrement a échoué: ${insertError.message}`,
        computedResult: result, // renvoyé quand même pour inspection/debug
      },
      { status: 500 }
    );
  }

  // ── 9. Réponse ────────────────────────────────────────────────────────
  return NextResponse.json({
    saleId,
    totalRevenue: result.totalRevenue,
    totalContributedTco2e: result.totalContributedTco2e,
    roundingRemainder: result.roundingRemainder,
    allocations: result.allocations,
  });
}
