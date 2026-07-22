/**
 * POST /api/aggregator/calculate-sale
 * ============================================================================
 * NEUTRALISÉE — préalable applicatif à la migration 08 (Tranche 0 carbone,
 * voir Tranche0-Carbone-Architecture.md §16 point 0bis).
 *
 * Cette route interrogeait jusqu'ici `credit_sale_lots -> credit_lots ->
 * projects -> companies(client_id)`, c'est-à-dire `credit_lots.project_id`
 * sur le schéma legacy pré-Tranche 0. La table `credit_lots` réelle en
 * production va être intégralement reconstruite (renommée, recréée sous
 * le même nom canonique, ancienne supprimée) par la migration 08, sous un
 * schéma qui ne porte plus `project_id` du tout. Le reste de la chaîne
 * interrogée ici (`credit_sales.aggregator_id`, `credit_sale_allocations.
 * company_id`) appartient également au schéma commercial legacy que la
 * migration 09 doit encore redéfinir (voir Tranche0-Carbone-Architecture.md
 * §13/§14) — cette route n'a donc aucune base stable à laquelle s'accrocher
 * avant que 09 ne soit conçue et appliquée.
 *
 * Décision (utilisateur, 22 juillet 2026) : neutraliser entièrement cette
 * route plutôt que de la corriger partiellement contre un schéma encore
 * amené à changer. Le calcul de répartition des ventes reste explicitement
 * indisponible jusqu'à la migration 09, qui la réécrira contre le nouveau
 * modèle commercial. Aucun appel UI ne référence cette route (recherche
 * `calculate-sale` dans tout `src/`, aucun résultat en dehors de ce
 * fichier) — rien à désactiver côté interface.
 *
 * Ne pas réintroduire de requête Supabase ici avant que 09 soit conçue.
 */

import { NextRequest, NextResponse } from 'next/server';

export async function POST(_request: NextRequest) {
  return NextResponse.json(
    {
      error:
        'Le calcul de répartition des ventes de crédits carbone est temporairement ' +
        'indisponible. Cette fonctionnalité sera réintroduite lors de la migration 09 ' +
        '(modèle financier commercial), contre un schéma révisé.',
    },
    { status: 503 }
  );
}
