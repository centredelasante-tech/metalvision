# Tranche 0 — Architecture du chantier carbone (v2)

**Statut : proposition de conception révisée. Aucun code, aucune migration réelle exécutée — l'écriture des migrations reste explicitement non validée par l'utilisateur.** Version 2, intégrant 12 corrections demandées après revue de la v1. Rédigé après le gel de la version démo CCF (`ADR-MVP.md` §9septricies, commit `366caec`/`a081433`).

**Principe directeur ajouté dans cette révision, appliqué de façon cohérente aux points 1 et 2 :** partout où une relation évolue dans le temps (adhésion à un regroupement, rattachement à un projet MRV), le MVP utilise une **table d'association historisée avec un index unique partiel garantissant au plus une ligne active à la fois**, plutôt qu'une colonne FK nue. Ce patron unique évite d'avoir à choisir entre « historique perdu » et « modèle complexe dès le départ ».

---

## 1. Le modèle d'adhésion aux regroupements

**Correction demandée : remplacer `organizations.aggregator_id` par une table historisée, une seule adhésion active à la fois.**

**Décision : remplacer, pas compléter.** `organizations.aggregator_id` a 0 ligne renseignée en production (confirmé §9tertricies) — aucune donnée à migrer, un remplacement complet est sans risque. Garder les deux (colonne + table) créerait une dénormalisation à synchroniser sans bénéfice réel à l'échelle de données attendue pour ce MVP.

**Table cible :**
```
aggregator_memberships
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid()
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE
  aggregator_id   UUID NOT NULL REFERENCES aggregators(id) ON DELETE CASCADE
  started_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  ended_at        TIMESTAMPTZ NULL
  ended_reason    TEXT NULL
  created_by      UUID REFERENCES profiles(id)
  ended_by        UUID REFERENCES profiles(id)
```
**Invariant garanti par la base** : `UNIQUE INDEX idx_one_active_membership ON aggregator_memberships (organization_id) WHERE ended_at IS NULL` — une seule adhésion active par organisation, l'historique complet reste consultable.

**Écriture réservée à une RPC** (voir §11) — pas d'`INSERT`/`UPDATE` direct autorisé par RLS, pour garantir que « quitter » un regroupement (renseigner `ended_at`) et « rejoindre » le suivant se fasse de façon atomique et traçable plutôt que par une écriture applicative libre.

---

## 2. La relation entre `ccf_projects` et les projets MRV

**Correction demandée : réévaluer le lien 1-1 face aux périodes/cycles MRV successifs.**

**Constat qui invalide le choix initial** : `verification_sessions.project_id` autorise déjà plusieurs sessions par projet MRV (aucune contrainte d'unicité) — un projet MRV existant peut donc traverser plusieurs cycles de vérification dans le temps. Un simple `ccf_projects.mrv_project_id` figerait le lien à un instant donné sans capacité de représenter un changement de projet MRV associé (ex. re-scoping après un changement majeur de périmètre) ni son historique.

**Décision : table d'association historisée `ccf_mrv_project_links`, pas une colonne FK nue.**
```
ccf_mrv_project_links
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid()
  ccf_project_id UUID NOT NULL REFERENCES ccf_projects(id) ON DELETE CASCADE
  mrv_project_id UUID NOT NULL REFERENCES projects(id) ON DELETE RESTRICT
  period_start   DATE NOT NULL DEFAULT CURRENT_DATE
  period_end     DATE NULL
  created_by     UUID REFERENCES profiles(id)
```
**Cardinalité tranchée explicitement pour le MVP : 1 actif — 1 actif.** Deux index uniques partiels :
- `UNIQUE (ccf_project_id) WHERE period_end IS NULL` — un projet CCF n'a qu'un seul projet MRV actif à la fois (mais peut en changer dans le temps, historique conservé).
- `UNIQUE (mrv_project_id) WHERE period_end IS NULL` — symétriquement, un projet MRV n'est activement rattaché qu'à un seul projet CCF à la fois.

**Ce qui est délibérément exclu du MVP, à trancher plus tard si le besoin se matérialise** : un projet MRV agrégeant la mesure de plusieurs projets CCF simultanément (scénario plausible si un regroupement veut mesurer les émissions au niveau du regroupement plutôt que projet par projet) — cette extension casserait la deuxième contrainte d'unicité ci-dessus ; elle est explicitement hors périmètre de cette tranche, pas oubliée par erreur.

---

## 3. `NUMERIC` plutôt que `FLOAT8` pour les quantités carbone officielles

**Décision : appliquée à toutes les colonnes de quantité tCO2e et, par cohérence du même principe, aux montants financiers associés** (`FLOAT8` introduit une imprécision d'arrondi binaire inacceptable pour des quantités qui deviennent la base d'un crédit vendu et audité) :

| Colonne | Type révisé |
|---|---|
| `verification_sessions.verified_reduction_tco2e` | `NUMERIC(14,4)` |
| `verification_sessions.eligible_tco2e` | `NUMERIC(14,4)` |
| `credit_lots.quantity_tco2e` | `NUMERIC(14,4)` |
| `credit_lot_sources.contributed_tco2e` | `NUMERIC(14,4)` |
| `credit_sale_lots.quantity_tco2e` | `NUMERIC(14,4)` |
| `credit_sales.total_tco2e` | `NUMERIC(14,4)` |
| `credit_sale_allocations.allocated_tco2e` | `NUMERIC(14,4)` |
| `credit_sales.price_per_tco2e`, `gross_amount`, `platform_fee_amount`, `net_distributable_amount` | `NUMERIC(14,2)` (montants monétaires) |
| `credit_sale_allocations.allocated_amount` | `NUMERIC(14,2)` |

`(14,4)` pour les quantités (permet des fractions de tCO2e précises), `(14,2)` pour les montants (cents). Ces précisions sont indicatives, à confirmer avec un besoin métier réel avant migration — mais `NUMERIC` lui-même n'est pas négociable pour ces colonnes.

---

## 4. Vérification complétée avec réduction nulle autorisée

**Correction demandée : seule la création d'un lot doit exiger une quantité positive, pas la complétion d'une vérification.**

**Décision révisée** : le trigger d'immutabilité sur `verification_sessions` (§4 v1) exige désormais seulement `verified_reduction_tco2e IS NOT NULL AND >= 0` (et `eligible_tco2e IS NOT NULL AND >= 0`) pour autoriser `status = 'completed'` — **zéro est une valeur légitime** (un cycle de vérification peut conclure qu'aucune réduction admissible n'a été démontrée, ce qui est une information utile en soi, pas une erreur de saisie).

**La positivité stricte ne s'applique qu'à la création d'un lot** — déjà garantie élégamment par la combinaison de deux mécanismes existants sans ajouter de nouvelle contrainte : `credit_lots.quantity_tco2e` conserve son `CHECK (quantity_tco2e > 0)`, et le trigger anti-surémission (§6) compare contre `eligible_tco2e` — si `eligible_tco2e = 0`, aucun lot ne pourra jamais être créé pour cette session (0 moins n'importe quelle quantité positive dépasse toujours 0), sans qu'il soit nécessaire d'écrire une contrainte séparée pour ce cas.

---

## 5. Correction du contrôle de surémission — `retired` continue de consommer

**Correction demandée, bug identifié dans la v1 : les lots `retired` avaient été exclus par erreur du calcul de consommation.**

**Décision corrigée** : `retired` signifie que le crédit a été utilisé/retiré du marché après une vente légitime — la quantité **reste engagée** contre la session de vérification source, définitivement. Seul un statut distinct `voided` (§8), résultant d'une procédure d'annulation contrôlée, libère la quantité.

**Formule révisée du trigger anti-surémission** :
```
SUM(quantity_tco2e) FILTER (WHERE status != 'voided')
  <= eligible_tco2e
  (pour un même verification_session_id)
```
Seule la valeur `'voided'` est exclue du calcul — `available`, `reserved`, `sold` et `retired` comptent tous contre la quantité admissible.

---

## 6. Verrouillage transactionnel contre la surémission concurrente

**Correction demandée, angle mort réel de la v1 : un trigger seul ne suffit pas contre la concurrence.**

**Explication du problème** : en isolation `READ COMMITTED` (défaut Postgres), deux transactions concurrentes créant chacune un lot pour la même session de vérification peuvent chacune calculer la somme existante **avant** de voir l'insertion de l'autre (ni l'une ni l'autre n'est encore validée/committée) — un trigger `BEFORE INSERT` qui se contente de sommer les lignes existantes peut laisser passer les deux insertions alors que leur total combiné dépasse `eligible_tco2e`. C'est un problème classique de « check-then-act » sous concurrence, qu'aucune contrainte déclarative ne peut résoudre seule.

**Décision : verrou de ligne explicite dans une RPC dédiée, pas seulement un trigger.** La création d'un lot ne doit jamais se faire par un `INSERT` direct — uniquement via une RPC `issue_credit_lot(...)` (`SECURITY DEFINER`) qui, dans l'ordre :
1. `SELECT 1 FROM verification_sessions WHERE id = p_verification_session_id FOR UPDATE` — verrouille la ligne de la session, forçant toute transaction concurrente visant la même session à attendre.
2. Recalcule la somme déjà engagée (maintenant garantie à jour, la transaction concurrente étant bloquée).
3. Rejette si `somme + p_quantity_tco2e > eligible_tco2e`.
4. Insère le lot (le trigger du point 5 reste en place comme filet de sécurité en profondeur — défense en profondeur, pas redondance inutile : il protège aussi contre un futur `UPDATE` direct qui contournerait la RPC).

Le trigger seul reste responsable de l'intégrité en écriture unique ; le verrou dans la RPC est responsable de l'intégrité sous concurrence. Les deux sont nécessaires, aucun des deux ne remplace l'autre.

---

## 7. Lot mono-organisation ou multi-organisation — tranché : multi-organisation

**Correction demandée : trancher explicitement, proposer `credit_lot_sources` si multi-organisation.**

**Décision : multi-organisation, `credit_lot_sources` retenue.** Justification : la prémisse même du domaine CCF est la consolidation entre **plusieurs** organisations (coordonnateur + manufacturier(s) + recycleur dans le seed de démo) — une réduction d'émissions issue d'un transport consolidé est une réalisation **partagée**, pas attribuable à une seule organisation. Un modèle mono-organisation contredirait la logique métier centrale du produit.

**Table cible :**
```
credit_lot_sources
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid()
  credit_lot_id      UUID NOT NULL REFERENCES credit_lots(id) ON DELETE CASCADE
  organization_id    UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT
  contributed_tco2e  NUMERIC(14,4) NOT NULL CHECK (contributed_tco2e > 0)
  UNIQUE (credit_lot_id, organization_id)
```
**Invariant garanti par la base (trigger, agrégat)** : `SUM(contributed_tco2e) FILTER (WHERE credit_lot_id = X) = credit_lots.quantity_tco2e` pour tout lot X — la somme des contributions doit égaler exactement la quantité totale du lot, ni plus ni moins.

**Conséquence positive sur le point 9 (modèle financier)** : la répartition proportionnelle d'une vente peut désormais se calculer directement à partir de `credit_lot_sources.contributed_tco2e`, sans passer par la chaîne indirecte `projet → unité opérationnelle → organisation` proposée en v1 — plus simple et plus explicite. La chaîne `credit_lot → mrv_project_id → operational_unit_id → organization` reste utile comme **traçabilité administrative** (quel projet MRV a produit ce lot) mais n'est plus le mécanisme de calcul financier.

---

## 8. Séparation explicite de `retired` et `voided`

**Décision : `credit_lots.status` devient `CHECK (status IN ('available','reserved','sold','retired','voided'))`.**

Sémantique distincte :
- **`retired`** : fin de vie normale après usage légitime (généralement après `sold`) — quantité engagée définitivement, jamais libérée (§5).
- **`voided`** : annulation administrative d'un lot émis à tort (ex. erreur de vérification découverte après coup) — quantité libérée, réintégrée à l'admissible disponible pour la session.

**Machine à états révisée :**
```
available → reserved     (négociation en cours)
reserved  → available    (négociation annulée)
reserved  → sold          (vente confirmée)
sold      → retired       (fin de vie normale après usage)
available → voided        (annulation directe avant toute vente)
reserved  → voided        (annulation d'une réservation erronée)
```
**Transition volontairement non tranchée ici, hors périmètre Tranche 0** : `sold → voided` (annuler un lot déjà vendu) exigerait de définir d'abord une procédure de réversion de vente (remboursement, avis à l'acheteur, etc.) — ce n'est pas une simple transition de statut, c'est un processus métier à concevoir séparément avant la Tranche 6. Interdit pour l'instant (`sold` ne peut aller qu'à `retired`).

---

## 9. Modèle minimal d'émission externe

**Colonnes ajoutées à `credit_lots`** (métadonnées de registre externe, toutes nullables — un lot MVP peut exister sans jamais être inscrit à un registre externe formel) :
```
registry_program              TEXT NULL   -- ex. "Verra VCS", "Alberta TIER", registre régional volontaire
external_registry_id          TEXT NULL   -- identifiant du projet/compte dans ce registre
external_serial_number_start  TEXT NULL
external_serial_number_end    TEXT NULL
issuance_date                 DATE NULL   -- date d'émission officielle par le registre externe (≠ created_at, notre horodatage interne)
```
`vintage_year` (millésime) existe déjà sur `credit_lots` — satisfait sans modification.

---

## 10. Modèle de vente complété

**`credit_sales` révisée :**
```
gross_amount               NUMERIC(14,2)               -- montant brut de la vente
platform_fee_pct           NUMERIC(5,4) NULL            -- ex. 0.0500 = 5 %
platform_fee_amount        NUMERIC(14,2) NULL
net_distributable_amount   NUMERIC(14,2)
  GENERATED ALWAYS AS (gross_amount - COALESCE(platform_fee_amount, 0)) STORED
```
`currency` existe déjà (`TEXT DEFAULT 'CAD'`) — conservée.

**Versionnement de la règle de répartition** : `distribution_rules` reçoit `rule_version INT NOT NULL DEFAULT 1`, incrémenté à chaque modification substantielle. `credit_sale_allocations` reçoit `distribution_rule_id UUID REFERENCES distribution_rules(id)` et `rule_version_applied INT` — chaque allocation garde la trace figée de la règle exacte utilisée au moment du calcul, pour qu'une modification ultérieure de la règle ne réinterprète jamais silencieusement une répartition déjà calculée.

**Statuts d'approbation et de paiement** : `credit_sale_allocations.status` devient `CHECK (status IN ('pending','approved','paid','disputed','cancelled'))` — ajout de `approved` comme étape intermédiaire explicite entre le calcul (`pending`) et le paiement (`paid`). **Question ouverte, non tranchée ici** : qui a l'autorité d'approuver (`pending → approved`) — l'admin du regroupement seul, ou une double validation avec l'organisation bénéficiaire ? Aucun rôle « finance » n'existe aujourd'hui dans le modèle de permissions — à trancher explicitement en Tranche 6, pas dans cette tranche de conception.

---

## 11. Audit RLS des nouvelles colonnes/tables et RPC transactionnelles nécessaires

**Principe RLS général appliqué aux 3 nouvelles tables** : lecture élargie aux parties légitimement concernées, écriture **jamais directe** — uniquement via RPC `SECURITY DEFINER`, cohérent avec le patron déjà établi pour `accept_project_invitation()` (`MVP-DA-018`).

| Table | Lecture (SELECT) | Écriture |
|---|---|---|
| `aggregator_memberships` | `is_organization_member(organization_id)` OR `is_aggregator_admin(aggregator_id)` OR `is_platform_superadmin()` | Aucune policy INSERT/UPDATE pour les rôles applicatifs — uniquement via RPC |
| `ccf_mrv_project_links` | `is_ccf_project_coordinator(ccf_project_id)` OR `is_ccf_project_participant(ccf_project_id)` OR `is_project_admin()`/`is_verifier()` (côté MRV) OR `is_platform_superadmin()` | Idem, RPC uniquement |
| `credit_lot_sources` | `is_organization_member(organization_id)` (une organisation source voit sa propre part) OR `is_aggregator_admin()` du regroupement propriétaire du lot OR `is_verifier()` | Idem, RPC uniquement (`issue_credit_lot`) |

**Colonnes ajoutées à des tables existantes — recommandations de durcissement** :
- `verification_sessions.verified_reduction_tco2e`/`eligible_tco2e` : recommandé de restreindre leur `UPDATE` à `is_verifier()` spécifiquement (pas `is_project_admin()` en général) — un admin de projet ne devrait pas pouvoir modifier un résultat de vérification après coup sans être lui-même le vérificateur désigné. Point de durcissement RLS à écrire en même temps que la migration du point 4.
- `credit_lots.issuance_date`/`external_*` : une fois `issuance_date` renseignée, ces colonnes devraient devenir immuables (trigger `BEFORE UPDATE`, pas une policy RLS — cohérent avec le traitement de `verified_reduction_tco2e` en §4 v1).

**RPC transactionnelles nécessaires (liste, pas d'implémentation) :**
1. `join_aggregator(p_organization_id, p_aggregator_id)` — clôture l'adhésion active existante (s'il y en a une) et en ouvre une nouvelle, atomiquement.
2. `leave_aggregator(p_organization_id, p_reason)` — clôture l'adhésion active sans en ouvrir de nouvelle.
3. `link_ccf_project_to_mrv(p_ccf_project_id, p_mrv_project_id)` / `unlink_ccf_project_from_mrv(...)` — même logique de bascule que 1/2, pour `ccf_mrv_project_links`.
4. `issue_credit_lot(p_verification_session_id, p_quantity_tco2e, p_sources jsonb, ...)` — verrou + vérification + insertion du lot + insertion des lignes `credit_lot_sources` + événement d'audit, en une seule transaction (§6, §7).
5. `void_credit_lot(p_credit_lot_id, p_reason)` — restreint à `is_aggregator_admin()`/`is_platform_superadmin()`, transition vers `voided`, libère la quantité, exige un motif (non nul), log d'audit obligatoire.
6. `finalize_credit_sale_allocations(p_credit_sale_id)` — valide que `SUM(allocated_tco2e) = credit_sales.total_tco2e` avant d'autoriser la transition `credit_sales.status → 'confirmed'` ; recommandé comme porte de validation plutôt qu'un trigger par ligne, pour ne pas rejeter des états intermédiaires légitimes pendant la saisie progressive d'une répartition.

---

## 12. Cohérence du choix `carbon_event_type` avec les décisions ADR existantes

**Correction demandée : vérifier la cohérence avec `TEXT + CHECK` déjà privilégié.**

**Vérifié dans `ADR-MVP.md`** : `MVP-DA-015` tranche explicitement **contre** un ENUM générique pour `status`/`phase`, au profit de `TEXT + CHECK` par table — avec une exception explicitement documentée pour « des types à vocation unique et stable » (`mandate_scope`, `document_visibility`, `logistics_step_type`, **`ccf_event_type`**). `ccf_event_type` est donc actuellement listé comme exception légitime à ENUM.

**Mais l'expérience réelle contredit cette exception pour un catalogue d'événements** : `ccf_event_type` a nécessité **7 migrations `ALTER TYPE ... ADD VALUE`** après sa création initiale (documenté dans le gel, §9septricies/§10) — la prémisse « vocation unique et stable » ne s'est pas vérifiée en pratique pour un catalogue d'événements, qui grandit naturellement à mesure que de nouvelles fonctionnalités sont livrées.

**Décision révisée : `carbon_event_type` en `TEXT + CHECK`, pas en ENUM.** Le chantier carbone est explicitement prévu pour être livré **par tranches successives** (`MVP-Carbone-Regroupements.md`), chaque tranche ajoutant vraisemblablement de nouveaux types d'événements — c'est exactement le scénario évolutif que `MVP-DA-015` cherche à éviter avec ENUM, indépendamment de l'exception qui y est listée pour `ccf_event_type`. Recommandation : traiter cette exception comme un choix qui ne se répète pas ici, et documenter formellement dans l'ADR (à la prochaine mise à jour) que l'exception `ccf_event_type` est elle-même reconsidérée à la lumière de l'expérience — sans la modifier rétroactivement (changement d'ENUM vers TEXT sur une table déjà en production serait une migration séparée, hors périmètre de cette tranche).

**Schéma révisé de `carbon_business_events` :**
```
carbon_business_events
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid()
  event_type      TEXT NOT NULL CHECK (event_type IN (
                    'verification_session_started','verification_session_completed',
                    'credit_lot_issued','credit_lot_reserved','credit_lot_sold',
                    'credit_lot_retired','credit_lot_voided',
                    'credit_sale_created','credit_sale_confirmed','credit_sale_settled',
                    'credit_sale_allocated','credit_sale_allocation_approved','credit_sale_allocation_paid'
                  ))
  object_type     TEXT NOT NULL CHECK (object_type IN (
                    'verification_session','credit_lot','credit_sale','credit_sale_allocation',
                    'aggregator_membership','ccf_mrv_project_link'
                  ))
  object_id       UUID NOT NULL
  organization_id UUID REFERENCES organizations(id)
  actor_id        UUID REFERENCES profiles(id)
  payload         JSONB
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
```
Ajout des valeurs `credit_lot_voided`, `credit_sale_allocation_approved`, `credit_sale_allocation_paid` par rapport à la v1, cohérent avec §5, §8, §10.

---

## Diagramme relationnel cible

```
organizations ──< aggregator_memberships >── aggregators
     │                                            │
     │                                     aggregator_admins
     │
     ├──< ccf_projects >── ccf_mrv_project_links ──< projects (MRV) >── operational_units
     │        │                                          │
     │   project_participants                    verification_sessions
     │                                                    │
     │                                            credit_lots ──< credit_lot_sources >── organizations
     │                                                    │              (multi-org, §7)
     │                                            credit_sale_lots
     │                                                    │
     │                                            credit_sales ──< distribution_rules (versionnée)
     │                                                    │
     └──────────────────────────────────< credit_sale_allocations
                                                    │
                                          carbon_business_events (audit, TEXT+CHECK, §12)
```
Lecture : `organizations` est le point d'ancrage double — via `aggregator_memberships` (gouvernance du regroupement) et via `ccf_projects`/`credit_lot_sources` (participation opérationnelle et contribution aux réductions). Les deux chemins sont indépendants — une organisation peut contribuer à un lot sans que son regroupement en soit propriétaire administratif exclusif (cas d'un regroupement multi-organisations où chaque contributeur reste rattaché individuellement).

---

## Invariants garantis par la base (constraints/triggers) vs garantis par RPC uniquement

**Garantis par la base, vrais à tout instant sur les données committées, quel que soit le chemin d'écriture (y compris le SQL Editor) :**
- `credit_lots.quantity_tco2e > 0` (`CHECK`)
- Au plus une adhésion active par organisation (`aggregator_memberships`, index unique partiel)
- Au plus un lien actif par `ccf_project_id` et par `mrv_project_id` (`ccf_mrv_project_links`, deux index uniques partiels)
- `SUM(credit_lot_sources.contributed_tco2e)` = `credit_lots.quantity_tco2e` par lot (trigger)
- `SUM(quantity_tco2e) FILTER (WHERE status != 'voided') <= eligible_tco2e` par session (trigger — **correct pour l'intégrité en écriture séquentielle, insuffisant seul sous concurrence, voir ci-dessous**)
- Transitions de statut de lot restreintes à la machine à états du §8 (trigger)
- `verified_reduction_tco2e`/`eligible_tco2e` non nuls et `>= 0` avant `status = 'completed'` (trigger), puis immuables après (trigger)

**Garantis uniquement par la discipline procédurale des RPC (pas exprimables en contrainte déclarative pure) :**
- L'absence de surémission **sous concurrence réelle** — le trigger seul est nécessaire mais pas suffisant (§6) ; la garantie complète dépend du verrou `SELECT ... FOR UPDATE` pris par `issue_credit_lot()`.
- L'autorisation (qui a le droit d'annuler un lot, d'approuver une allocation) — appliquée par RLS sur les RPC/tables, mais la **logique de workflow** (motif obligatoire, séquence d'approbation) est portée par le code des RPC, pas par des contraintes SQL.
- L'égalité `SUM(allocated_tco2e) = credit_sales.total_tco2e` — volontairement **pas** un trigger par ligne (rejetterait les états intermédiaires légitimes), vérifiée seulement au moment de `finalize_credit_sale_allocations()`.
- L'atomicité « clôturer l'ancienne adhésion + ouvrir la nouvelle » ou « clôturer l'ancien lien MRV + ouvrir le nouveau » — repose sur le fait que la RPC fait les deux opérations dans une seule transaction, pas sur une contrainte qui l'imposerait indépendamment du chemin d'écriture.

---

## Cas de concurrence à tester (avant toute mise en production de ces mécanismes)

1. **Deux `issue_credit_lot()` concurrents sur la même session de vérification**, dont la somme des quantités demandées dépasse `eligible_tco2e` alors qu'aucune des deux prise individuellement ne le dépasse — attendu : exactement une des deux transactions réussit, l'autre attend puis échoue proprement après avoir vu la première committée.
2. **`issue_credit_lot()` concurrent à `void_credit_lot()` sur la même session** — la quantité libérée par l'annulation ne doit être visible à la création d'un nouveau lot qu'une fois le `void` committé, jamais avant (pas de lecture de données non validées).
3. **Deux `join_aggregator()` concurrents pour la même organisation**, vers deux regroupements différents — attendu : un seul succès, l'autre rejeté par l'index unique partiel (même si la RPC tente de clôturer une adhésion « active » qui n'existe pas encore au moment de sa propre lecture).
4. **Deux `link_ccf_project_to_mrv()` concurrents** liant le même `ccf_project_id` à deux `mrv_project_id` différents — attendu : un seul succès (index unique partiel sur `ccf_project_id`).
5. **Deux `link_ccf_project_to_mrv()` concurrents** liant deux `ccf_project_id` différents au même `mrv_project_id` — attendu : un seul succès (index unique partiel sur `mrv_project_id`, symétrique au cas 4).
6. **Deux `finalize_credit_sale_allocations()` concurrents** sur la même vente, après une modification concurrente d'une ligne d'allocation — attendu : la validation du total doit voir un état cohérent, pas une lecture partielle entre deux écritures concurrentes sur les lignes d'allocation.

---

## Synthèse des migrations envisagées (toujours non écrites, ordre logique indicatif)

1. `CREATE TABLE aggregator_memberships (...)` + index unique partiel + RPC `join_aggregator`/`leave_aggregator` ; dépréciation puis suppression de `organizations.aggregator_id`.
2. `CREATE TABLE ccf_mrv_project_links (...)` + deux index uniques partiels + RPC `link_ccf_project_to_mrv`/`unlink_ccf_project_from_mrv`.
3. Conversion `FLOAT8 → NUMERIC` sur toutes les colonnes du tableau §3 (migration de type de colonne, `credit_lots`/`credit_sales`/etc. ayant 0 ligne en production — sans risque de perte de précision sur des données existantes).
4. `ALTER TABLE verification_sessions ADD COLUMN verified_reduction_tco2e NUMERIC(14,4), ADD COLUMN eligible_tco2e NUMERIC(14,4), ADD COLUMN verification_method TEXT;` + trigger de validation `>= 0` + immutabilité post-`completed` + durcissement RLS (`is_verifier()` sur l'`UPDATE` de ces colonnes).
5. `ALTER TABLE credit_lots ADD COLUMN verification_session_id UUID NOT NULL REFERENCES verification_sessions(id) ON DELETE RESTRICT, ADD COLUMN registry_program TEXT, ADD COLUMN external_registry_id TEXT, ADD COLUMN external_serial_number_start TEXT, ADD COLUMN external_serial_number_end TEXT, ADD COLUMN issuance_date DATE;` + `status` étendu à 5 valeurs + trigger anti-surémission corrigé (§5) + trigger de machine à états (§8) + trigger d'immutabilité post-émission.
6. `CREATE TABLE credit_lot_sources (...)` + trigger d'égalité de somme + RPC `issue_credit_lot()`/`void_credit_lot()` avec verrou explicite (§6, §7).
7. `ALTER TABLE credit_sale_lots ADD CONSTRAINT uq_credit_sale_lots UNIQUE (credit_sale_id, credit_lot_id); ALTER TABLE credit_sales ADD COLUMN gross_amount NUMERIC(14,2), ADD COLUMN platform_fee_pct NUMERIC(5,4), ADD COLUMN platform_fee_amount NUMERIC(14,2), ADD COLUMN net_distributable_amount NUMERIC(14,2) GENERATED ALWAYS AS (...) STORED; ALTER TABLE distribution_rules ADD COLUMN rule_version INT NOT NULL DEFAULT 1; ALTER TABLE credit_sale_allocations ADD CONSTRAINT uq_credit_sale_allocations UNIQUE (credit_sale_id, organization_id), ADD COLUMN distribution_rule_id UUID REFERENCES distribution_rules(id), ADD COLUMN rule_version_applied INT, status étendu à 5 valeurs;` + RPC `finalize_credit_sale_allocations()`.
8. `CREATE TABLE carbon_business_events (event_type TEXT + CHECK, pas ENUM)` + policies RLS dédiées.

**Toujours hors périmètre de cette tranche, à trancher séparément :** la procédure de réversion d'une vente déjà confirmée (§8), le rôle d'approbation financière (§10), la méthodologie de décote/buffer sur `eligible_tco2e` (héritée de la v1, toujours ouverte), et les écrans eux-mêmes (Tranches 1-6).
