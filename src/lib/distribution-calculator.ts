/**
 * Calculateur de répartition des revenus — vente de crédits carbone consolidée
 * ============================================================================
 *
 * Logique en cascade :
 *   1. Le "poids" (weight) de chaque membre détermine sa part du revenu BRUT
 *      total, proportionnellement à ses tCO2e contribuées × son poids.
 *   2. Les frais de plateforme et la réserve sont ensuite déduits
 *      individuellement de la part brute de chaque membre, selon le taux
 *      effectif qui lui est applicable (override actif, sinon règle générale
 *      de l'agrégateur).
 *
 * Chaque valeur effective (fee_pct, reserve_pct, weight) est déterminée par :
 *   - un override actif pour ce membre à la date de la vente, s'il existe *   - sinon, la valeur par défaut de la règle générale de l'agrégateur
 *
 * Cette fonction est pure (aucun accès base de données) : elle prend des
 * données déjà chargées en entrée et retourne le résultat calculé, prêt à
 * être inséré dans `credit_sale_allocations`. Le chargement des données
 * (règles, overrides actifs, contributions) se fait en amont, côté appelant.
 */

// ---------------------------------------------------------------------------
// Types — alignés sur le schéma SQL
// ---------------------------------------------------------------------------

export type OverrideType = 'fee_pct' | 'reserve_pct' | 'weight_multiplier';

export interface DistributionRule {
  aggregatorId: string;
  platformFeePct: number;   // ex: 10 pour 10%
  reservePct: number;       // ex: 5 pour 5%
  defaultWeight: number;    // ex: 1.0
}

export interface MemberOverride {
  companyId: string;
  overrideType: OverrideType;
  overrideValue: number;
  effectiveFrom: string;    // format ISO 'YYYY-MM-DD'
  effectiveUntil: string;   // format ISO 'YYYY-MM-DD' — toujours défini (contrainte SQL)
}

export interface MemberContribution {
  companyId: string;
  contributedTco2e: number;
}

export interface AllocationResult {
  companyId: string;
  contributedTco2e: number;
  grossAmount: number;
  feeAppliedPct: number;
  reserveAppliedPct: number;
  weightApplied: number;
  feeAmount: number;
  reserveAmount: number;
  netAmount: number;
}

export interface CalculateDistributionInput {
  saleDate: string;                 // format ISO 'YYYY-MM-DD'
  pricePerTco2e: number;
  contributions: MemberContribution[];
  rule: DistributionRule;
  overrides: MemberOverride[];      // tous les overrides du regroupement (actifs ou non — le filtrage se fait ici)
}

export interface CalculateDistributionResult {
  totalRevenue: number;
  totalContributedTco2e: number;
  allocations: AllocationResult[];
  /**
   * Écart d'arrondi entre la somme des netAmount calculés et le revenu
   * total attendu après frais/réserve. Généralement quelques centimes dus
   * aux arrondis à 2 décimales. À traiter manuellement (ex: ajusté sur la
   * plus grosse allocation, ou versé à la réserve) — décision de gestion,
   * pas automatisée ici pour rester auditable.
   */
  roundingRemainder: number;
}

// ---------------------------------------------------------------------------
// Utilitaires internes
// ---------------------------------------------------------------------------

/** Vérifie si une date (format ISO) tombe dans l'intervalle [from, until] inclus. */
function isDateWithinRange(date: string, from: string, until: string): boolean {
  return date >= from && date <= until;
}

/**
 * Trouve la valeur effective d'un paramètre (fee_pct, reserve_pct,
 * weight_multiplier) pour un membre donné à la date de la vente :
 * override actif s'il existe, sinon valeur par défaut de la règle générale.
 */
function getEffectiveValue(
  companyId: string,
  overrideType: OverrideType,
  saleDate: string,
  overrides: MemberOverride[],
  defaultValue: number
): number {
  const activeOverride = overrides.find(
    (o) =>
      o.companyId === companyId &&
      o.overrideType === overrideType &&
      isDateWithinRange(saleDate, o.effectiveFrom, o.effectiveUntil)
  );
  return activeOverride ? activeOverride.overrideValue : defaultValue;
}

/** Arrondit à 2 décimales (calculs monétaires). */
function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

// ---------------------------------------------------------------------------
// Fonction principale
// ---------------------------------------------------------------------------

/**
 * Calcule la répartition d'une vente de crédits carbone entre les membres
 * contributeurs, en appliquant la cascade : pondération -> part brute ->
 * frais -> réserve -> montant net.
 *
 * @throws Error si aucune contribution n'est fournie, ou si le total pondéré est nul.
 */
export function calculateDistribution(
  input: CalculateDistributionInput
): CalculateDistributionResult {
  const { saleDate, pricePerTco2e, contributions, rule, overrides } = input;

  if (contributions.length === 0) {
    throw new Error('Aucune contribution fournie pour cette vente.');
  }

  const totalContributedTco2e = contributions.reduce(
    (sum, c) => sum + c.contributedTco2e,
    0
  );
  const totalRevenue = round2(totalContributedTco2e * pricePerTco2e);

  // Étape 1 : déterminer le poids effectif de chaque membre et le total pondéré
  const weightedContributions = contributions.map((c) => {
    const weightApplied = getEffectiveValue(
      c.companyId,
      'weight_multiplier',
      saleDate,
      overrides,
      rule.defaultWeight
    );
    return {
      ...c,
      weightApplied,
      weightedTco2e: c.contributedTco2e * weightApplied,
    };
  });

  const totalWeightedTco2e = weightedContributions.reduce(
    (sum, c) => sum + c.weightedTco2e,
    0
  );

  if (totalWeightedTco2e <= 0) {
    throw new Error('Le total pondéré des contributions est nul ou négatif — vérifier les poids appliqués.');
  }

  // Étape 2 : part brute de chaque membre, proportionnelle à sa contribution pondérée
  const allocations: AllocationResult[] = weightedContributions.map((c) => {
    const grossAmount = round2(
      (c.weightedTco2e / totalWeightedTco2e) * totalRevenue
    );

    // Étape 3 : taux de frais et de réserve effectifs (override ou règle générale)
    const feeAppliedPct = getEffectiveValue(
      c.companyId,
      'fee_pct',
      saleDate,
      overrides,
      rule.platformFeePct
    );
    const reserveAppliedPct = getEffectiveValue(
      c.companyId,
      'reserve_pct',
      saleDate,
      overrides,
      rule.reservePct
    );

    // Étape 4 : déductions et montant net
    const feeAmount = round2((grossAmount * feeAppliedPct) / 100);
    const reserveAmount = round2((grossAmount * reserveAppliedPct) / 100);
    const netAmount = round2(grossAmount - feeAmount - reserveAmount);

    return {
      companyId: c.companyId,
      contributedTco2e: c.contributedTco2e,
      grossAmount,
      feeAppliedPct,
      reserveAppliedPct,
      weightApplied: c.weightApplied,
      feeAmount,
      reserveAmount,
      netAmount,
    };
  });

  // Écart d'arrondi : somme des grossAmount calculés vs totalRevenue attendu
  const sumGross = allocations.reduce((sum, a) => sum + a.grossAmount, 0);
  const roundingRemainder = round2(totalRevenue - sumGross);

  return {
    totalRevenue,
    totalContributedTco2e,
    allocations,
    roundingRemainder,
  };
}

// ---------------------------------------------------------------------------
// Exemple d'utilisation (à titre de documentation — non exécuté)
// ---------------------------------------------------------------------------
//
// const result = calculateDistribution({
//   saleDate: '2026-08-15',
//   pricePerTco2e: 45.00,
//   contributions: [
//     { companyId: 'membre-1-uuid', contributedTco2e: 120.5 },
//     { companyId: 'membre-2-uuid', contributedTco2e: 45.0 },
//   ],
//   rule: {
//     aggregatorId: 'agregateur-uuid',
//     platformFeePct: 10,
//     reservePct: 5,
//     defaultWeight: 1.0,
//   },
//   overrides: [
//     {
//       companyId: 'membre-1-uuid',
//       overrideType: 'fee_pct',
//       overrideValue: 7,              // membre-1 négocié à 7% au lieu de 10%
//       effectiveFrom: '2026-01-01',
//       effectiveUntil: '2026-12-31',  // revue annuelle obligatoire
//     },
//   ],
// });
//
// result.allocations -> prêt à insérer dans credit_sale_allocations
