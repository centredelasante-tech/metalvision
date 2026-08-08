/**
 * Allowlist fixe des écrans couverts par l'Agent d'aide V1 (GATE IA-1).
 *
 * Volontairement limité aux 8 écrans carbone — voir
 * Agent-Aide-MetalTrace-V1-Architecture.md §2.1 et §6. Aucun écran CCF ni
 * legacy logistique dans cette passe. Toute valeur de `screen` hors de
 * cette liste est rejetée par l'endpoint (400).
 */
export const CARBON_SCREENS = [
  'admin-verification-sessions',
  'verifier-mrv',
  'admin-carbon-inventory',
  'admin-regroupement-distribution',
  'admin-carbon-sales',
  'admin-carbon-projects',
  'admin-mrv-project',
  'carbon-impact',
] as const;

export type CarbonScreen = (typeof CARBON_SCREENS)[number];

export function isCarbonScreen(value: unknown): value is CarbonScreen {
  return typeof value === 'string' && (CARBON_SCREENS as readonly string[]).includes(value);
}

export const SCREEN_LABELS: Record<CarbonScreen, string> = {
  'admin-verification-sessions': 'Sessions de vérification',
  'verifier-mrv': 'Vérification MRV',
  'admin-carbon-inventory': 'Inventaire carbone',
  'admin-regroupement-distribution': 'Gouvernance de distribution',
  'admin-carbon-sales': 'Cockpit de ventes',
  'admin-carbon-projects': 'Projets Carbone MRV',
  'admin-mrv-project': 'Détail projet MRV',
  'carbon-impact': 'Impact carbone',
};

/** UUID v4-ish, format libre — validation défensive d'un identifiant fourni par le client. */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isValidObjectId(value: unknown): value is string {
  return typeof value === 'string' && UUID_RE.test(value);
}
