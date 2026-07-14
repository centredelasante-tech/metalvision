# Tranche 0 — Architecture du chantier carbone

**Statut : proposition de conception. Aucun code, aucune migration réelle dans ce document.** Rédigé après le gel de la version démo CCF (`ADR-MVP.md` §9septricies, commit `366caec`/`a081433`), conformément à la demande explicite de l'utilisateur : trancher les 10 points structurants avant tout développement, sur la base du schéma SQL réel (vérifié migration par migration, pas de supposition).

**Fondation factuelle** : ce document s'appuie sur l'audit complet du domaine carbone/agrégateurs (`ADR-MVP.md` §9tertricies) et sur une relecture exhaustive des migrations `supabase/migrations/` pour les 14 tables concernées, résumée point par point ci-dessous avant chaque décision.

---

## 1. Le modèle d'adhésion aux regroupements

**État réel du schéma** : `organizations.aggregator_id` (UUID, nullable, `ON DELETE SET NULL`, ajoutée par `20260710999100_reapply_mrv_and_aggregators.sql`) est l'unique mécanisme d'adhésion. Il n'existe **aucune table de jonction** `organization_aggregators` — l'adhésion est portée directement par une colonne sur `organizations`.

**Décision recommandée : conserver ce modèle simple pour le MVP.** Une organisation appartient à zéro ou un regroupement à la fois, jamais plusieurs simultanément. C'est cohérent avec la réalité métier visée (un regroupement = un consortium régional/sectoriel de valorisation carbone, pas une adhésion multiple) et évite la complexité d'une table de jonction avec historique tant qu'aucun besoin réel de multi-adhésion n'est démontré.

**Ce qui manque et doit être construit (pas une migration de schéma, un écran)** : aujourd'hui, rien n'écrit `organizations.aggregator_id` — ni écran, ni RPC. Tranche 1 (déjà proposée dans `MVP-Carbone-Regroupements.md`) doit fournir un écran d'admin plateforme pour rattacher une organisation à un regroupement.

**Question ouverte, à trancher avant la Tranche 1, pas ici** : que devient une organisation qui change de regroupement (perte d'historique des lots déjà émis sous l'ancien regroupement) ? Recommandation : ne pas bloquer le changement, mais garder `credit_lots`/`credit_sales` liés à l'`aggregator_id` de la vente au moment de la transaction (déjà le cas, `credit_sales.aggregator_id` est indépendant de l'état courant de `organizations.aggregator_id`), donc aucun risque de perte de traçabilité historique.

---

## 2. La cardinalité entre organisations et regroupements

Découle directement du point 1 : **cardinalité 1-N (un regroupement a plusieurs organisations membres ; une organisation appartient à au plus un regroupement à la fois)**. Confirmé par le type de la colonne (`aggregator_id` scalaire, pas un tableau ni une table de jonction) et l'absence de toute contrainte d'unicité qui suggérerait un modèle différent.

**Décision : conserver telle quelle.** Aucune migration nécessaire pour ce point — c'est déjà l'état du schéma, il s'agit seulement de le documenter comme un choix assumé plutôt qu'un oubli.

---

## 3. La relation entre `ccf_projects` et les projets MRV

**État réel confirmé (recherche exhaustive, aucune occurrence trouvée)** : `ccf_projects` ne référence que `opportunities` et `organizations` ; `projects` (MRV) ne référence que `operational_units` (nullable). **Aucun lien structurel entre les deux tables.**

**Décision recommandée : ajouter une colonne `ccf_projects.mrv_project_id UUID NULL REFERENCES public.projects(id) ON DELETE SET NULL`.**

Justification du choix (nullable, `SET NULL`, sur `ccf_projects` plutôt que l'inverse) :
- **Nullable** : un projet CCF (consolidation ferroviaire) n'a pas obligatoirement de volet carbone — la majorité des projets CCF actuels et futurs n'en auront probablement pas.
- **`ON DELETE SET NULL` plutôt que `CASCADE`** : la suppression d'un projet MRV ne doit jamais supprimer silencieusement un projet CCF actif (le projet CCF est l'entité commerciale/logistique primaire, le volet carbone est une extension).
- **Sur `ccf_projects` plutôt que l'inverse** (`projects.ccf_project_id`) : un projet CCF est l'entité qui existe en premier dans le parcours (opportunité → projet → [optionnellement] volet carbone) ; c'est plus intuitif que le FK pointe dans le sens de la dépendance fonctionnelle. Recommandation confirmée cohérente avec `MVP-DA-013` (garder les deux modèles distincts, ne pas fusionner).

**Cardinalité du lien : 1-1 optionnelle** (un projet CCF a au plus un projet MRV associé). Pas de cas d'usage identifié pour qu'un projet CCF ait plusieurs volets carbone — si un besoin futur apparaît (ex. deux phases de mesure distinctes), ce serait une évolution ultérieure, pas une raison de complexifier le MVP maintenant.

---

## 4. Le modèle unique de résultat de vérification

**État réel** : `verification_sessions.status` est un ENUM à 3 valeurs (`planned`, `in_progress`, `completed`), sans aucun champ de quantité. Le calcul de réduction GES vit ailleurs, dans `project_activity_logs` (une ligne par activité, avec `ghg_emissions_baseline_kgco2e`, `ghg_emissions_project_kgco2e`, `ghg_reduction_kgco2e` par ligne) — **il n'existe aucune agrégation au niveau projet ni au niveau session de vérification.**

**Problème de conception identifié** : sans un résultat unique et persistant au niveau de la session de vérification, deux vérificateurs (ou le même, à deux moments) pourraient produire des totaux différents selon les activités qu'ils choisissent d'inclure dans leur calcul — aucune donnée ne fige « ce qui a été officiellement vérifié » à un instant donné.

**Décision recommandée : ajouter deux colonnes à `verification_sessions`** :
- `verified_reduction_tco2e FLOAT8 NULL` — renseignée uniquement au moment où `status` passe à `completed`, par le vérificateur.
- `verification_method TEXT NULL` (ou `JSONB` si on veut capturer plusieurs paramètres) — note libre sur la méthode utilisée pour ce calcul (ex. « somme des activity_logs du 2026-01-01 au 2026-06-30 »), pour la traçabilité/audit, sans imposer un calcul automatique dès le MVP.

**Pourquoi une saisie assistée plutôt qu'un calcul 100% automatique dès le MVP** : `project_activity_logs.ghg_reduction_kgco2e` existe déjà et pourrait être sommé automatiquement, mais rien ne garantit aujourd'hui qu'un vérificateur ait revu/validé chaque ligne d'activité avant la clôture de la session. Imposer une saisie manuelle validée par le vérificateur au moment de `completed` est plus sûr pour un MVP destiné à un usage réel (le calcul automatique peut venir plus tard comme une **suggestion pré-remplie**, pas une vérité imposée).

**Contrainte recommandée** : un trigger ou un `CHECK` (le `CHECK` seul ne suffit pas car il doit vérifier une cohérence entre deux colonnes selon leur valeur — donc trigger) empêchant `status = 'completed'` sans `verified_reduction_tco2e IS NOT NULL` et `> 0`.

---

## 5. La distinction entre réduction calculée, réduction vérifiée, quantité admissible et crédit officiellement émis

Quatre notions distinctes à ne jamais confondre dans le schéma, avec leur porteur de données respectif :

| Notion | Porteur de donnée | État actuel | Décision |
|---|---|---|---|
| **Réduction calculée** | Somme de `project_activity_logs.ghg_reduction_kgco2e` pour un projet | Déjà calculable (agrégation), aucune colonne dédiée nécessaire | Rester une vue/requête, ne pas persister — c'est une estimation continue, pas un fait figé |
| **Réduction vérifiée** | `verification_sessions.verified_reduction_tco2e` (nouvelle colonne, point 4) | À créer | Figée au moment de `completed`, ne change plus ensuite (immutabilité recommandée par trigger `BEFORE UPDATE`) |
| **Quantité admissible** | Nouvelle colonne, ex. `verification_sessions.eligible_tco2e` | À créer | `eligible_tco2e <= verified_reduction_tco2e` — un facteur de décote (buffer/incertitude/risque de non-permanence) peut être appliqué ; pour le MVP, recommandation : **`eligible_tco2e = verified_reduction_tco2e` par défaut** (pas de décote automatique tant qu'aucune méthodologie de buffer n'est choisie), mais garder les deux colonnes séparées dès maintenant pour ne pas avoir à migrer une troisième fois si une politique de décote est adoptée plus tard |
| **Crédit officiellement émis** | `credit_lots.quantity_tco2e` | Existe déjà | Doit être **contraint** à ne jamais dépasser la quantité admissible restante non encore émise pour la session de vérification source (point 6) |

**Migration envisagée** : ajouter `verification_sessions.eligible_tco2e FLOAT8 NULL` en plus de `verified_reduction_tco2e` (voir point 4).

---

## 6. La prévention du double comptage

**Faille actuelle confirmée** : `credit_lots` a une FK vers `projects(id)` mais **aucune FK vers `verification_sessions`**. Rien n'empêche aujourd'hui de créer plusieurs lots de crédits pour le même projet totalisant plus que ce qui a été vérifié — ou même de créer un lot pour un projet dont **aucune** session de vérification n'a jamais atteint `completed`.

**Décision recommandée, en deux parties :**

1. **Ajouter `credit_lots.verification_session_id UUID NOT NULL REFERENCES public.verification_sessions(id) ON DELETE RESTRICT`** — chaque lot doit être rattaché à la session de vérification précise qui justifie son existence, pas seulement au projet en général. `NOT NULL` dès la création du lot (pas de lot sans preuve de vérification).

2. **Contrainte d'intégrité empêchant la sur-émission** — impossible à exprimer en `CHECK` simple (agrégat sur plusieurs lignes), donc un **trigger `BEFORE INSERT OR UPDATE ON credit_lots`** qui calcule `SUM(quantity_tco2e) FILTER (WHERE verification_session_id = NEW.verification_session_id AND status != 'retired')` et rejette l'insertion si le total dépasserait `verification_sessions.eligible_tco2e` pour cette session.

**Double comptage inter-projets** : puisque chaque `verification_session_id` est unique à un `project_id` (via la FK existante `verification_sessions.project_id`), et que le nouveau trigger limite les émissions par session, le double comptage entre deux projets MRV différents est déjà structurellement impossible (un lot ne peut être émis qu'à partir d'une session qui appartient à un seul projet). Le risque résiduel non couvert par le schéma — une même réduction physique comptée dans deux projets MRV différents parce que leurs périmètres (`system_boundaries`) se chevauchent — est un risque **méthodologique**, pas un risque de schéma ; il reste hors de portée d'une contrainte SQL et doit être géré par la revue humaine du vérificateur au moment de définir `system_boundaries`.

---

## 7. La provenance quantitative des lots

**Chaîne de traçabilité complète, du crédit à l'organisation contributrice, telle qu'elle existera après les ajouts ci-dessus :**

```
credit_lot
  → verification_session_id → verification_sessions (quantité admissible source)
  → project_id → projects (projet MRV)
      → operational_unit_id → operational_units
          → organization_id → organizations (organisation contributrice réelle)
```

**Faille actuelle confirmée** : `projects.operational_unit_id` est **nullable**. Si elle n'est pas renseignée, la chaîne de provenance se rompt — un lot de crédit existerait sans qu'on puisse remonter à quelle organisation a réellement généré la réduction.

**Décision recommandée** : imposer `operational_unit_id NOT NULL` **au moment de la création d'un lot** (pas sur `projects` globalement, pour ne pas casser un projet MRV en cours de saisie qui n'a pas encore choisi son unité opérationnelle) — via le même trigger de garde du point 6, en ajoutant une vérification que `projects.operational_unit_id IS NOT NULL` avant d'autoriser l'insertion d'un `credit_lot` pour ce projet.

**Pas de colonne de provenance supplémentaire nécessaire sur `credit_lots` lui-même** — la chaîne via `project_id`/`verification_session_id` suffit, éviter de dupliquer `organization_id` directement sur `credit_lots` (risque d'incohérence si l'organisation change après coup).

---

## 8. Le cycle de vie des lots

**État actuel** : `credit_lots.status` — `CHECK (status IN ('available','reserved','sold','retired'))`, sans machine à états formalisée (n'importe quelle transition est possible aujourd'hui, y compris `retired → available`).

**Décision recommandée — machine à états explicite (à documenter, implémentable par un trigger `BEFORE UPDATE` en Tranche 5, pas ici) :**

```
available → reserved   (une vente en cours de négociation réserve le lot)
reserved  → available  (négociation annulée)
reserved  → sold        (vente confirmée, credit_sale_lots créé)
sold      → retired     (le crédit est retiré/annulé après usage — irréversible)
available → retired     (retrait direct sans vente, ex. erreur de vérification découverte a posteriori)
```

Transitions explicitement interdites : `sold → available`, `sold → reserved`, `retired → *` (toute transition, `retired` est un état terminal).

**Lien avec `credit_sale_lots`** : la transition `reserved → sold` devrait coïncider avec la création de la ligne `credit_sale_lots` correspondante — recommandé comme un trigger conjoint plutôt que deux opérations indépendantes pouvant diverger (risque qu'un lot soit marqué `sold` sans ligne `credit_sale_lots`, ou l'inverse).

---

## 9. Le modèle financier de vente et d'allocation

**État réel confirmé :**
- `credit_sales` : vente globale (acheteur, `total_tco2e`, `price_per_tco2e`, statut `draft/confirmed/settled/cancelled`).
- `credit_sale_lots` : jonction vente↔lots, **sans contrainte UNIQUE** sur `(credit_sale_id, credit_lot_id)` — un même lot pourrait apparaître deux fois dans la même vente par erreur de saisie.
- `distribution_rules` : `rule_type` (`proportional`/`equal`/`custom`) + `parameters` JSONB **sans validation de structure**.
- `credit_sale_allocations` : répartition par organisation, **sans contrainte UNIQUE** sur `(credit_sale_id, organization_id)` (déjà identifié dans l'audit précédent, §9tertricies).

**Décisions recommandées :**

1. **`UNIQUE (credit_sale_id, credit_lot_id)` sur `credit_sale_lots`** — empêche la double inclusion accidentelle d'un même lot dans une vente.
2. **`UNIQUE (credit_sale_id, organization_id)` sur `credit_sale_allocations`** — déjà recommandée, réaffirmée ici ; nécessaire pour permettre un upsert propre lors du recalcul d'une répartition.
3. **Modèle de calcul de `proportional`, à documenter (pas en schéma) avant l'implémentation** : proportionnel à quoi ? Recommandation — proportionnel à la contribution de chaque organisation aux lots inclus dans la vente, mesurée via la chaîne de provenance du point 7 (`credit_lot → project → operational_unit → organization`), pondérée par `quantity_tco2e` de chaque lot attribuable à chaque organisation. C'est calculable avec le schéma existant (une fois la chaîne de provenance garantie non-nulle par le point 7) — **aucune nouvelle colonne requise pour `proportional` et `equal`**. Pour `custom`, `parameters` JSONB reste la bonne approche (ratios explicites par organisation), toujours sans validation de structure imposée en base — la validation de forme du JSON reviendra à la couche applicative (Tranche 6), pas à une contrainte SQL, pour rester flexible.
4. **Le total des `credit_sale_allocations.allocated_tco2e` pour une vente donnée devrait égaler `credit_sales.total_tco2e`** — encore un cas d'agrégat, donc un trigger de garde en Tranche 6, pas une contrainte déclarative.

---

## 10. Les événements métier carbone et leur piste d'audit

**Décision déjà prise et réaffirmée (§9tertricies)** : catalogue distinct, pas d'extension de `ccf_event_type`/`business_events` (`event_type` est un ENUM fermé, `object_type` un `CHECK` fermé sur 8 valeurs, aucune des deux ne peut absorber des objets carbone sans rupture).

**Schéma cible recommandé pour ce catalogue distinct :**

```
carbon_event_type (ENUM) :
  verification_session_started
  verification_session_completed
  credit_lot_issued
  credit_lot_reserved
  credit_lot_sold
  credit_lot_retired
  credit_sale_created
  credit_sale_confirmed
  credit_sale_settled
  credit_sale_allocated

carbon_business_events (table, même structure que business_events) :
  id UUID PRIMARY KEY
  event_type carbon_event_type NOT NULL
  object_type TEXT NOT NULL CHECK (object_type IN ('verification_session','credit_lot','credit_sale','credit_sale_allocation'))
  object_id UUID NOT NULL
  organization_id UUID REFERENCES organizations(id)   -- organisation contributrice ou partie prenante, nullable si non applicable
  actor_id UUID REFERENCES profiles(id)
  payload JSONB
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
```

**RLS recommandée pour cette table** : lecture conditionnée à l'appartenance au regroupement concerné (via la chaîne de provenance du point 7) ou à un rôle de vérificateur/admin plateforme — même philosophie que `business_events` actuel (`is_organization_member`), pas un nouveau modèle de permission à inventer.

**Pas de trigger unique centralisé recommandé pour insérer ces événements** — cohérent avec le patron déjà utilisé pour `business_events` : chaque RPC/action applicative insère explicitement son événement (jamais de trigger automatique dupliquant une insertion applicative, la règle qui a précisément évité `INC-S06-06`/`INC-S07-01` dans le domaine CCF s'applique identiquement ici).

---

## Synthèse — schéma cible (migrations envisagées, aucune écrite ici)

Six migrations distinctes envisagées, dans l'ordre logique de dépendance (à re-séquencer selon les tranches de `MVP-Carbone-Regroupements.md`, pas nécessairement dans cet ordre d'exécution) :

1. `ALTER TABLE ccf_projects ADD COLUMN mrv_project_id UUID NULL REFERENCES projects(id) ON DELETE SET NULL;` (point 3)
2. `ALTER TABLE verification_sessions ADD COLUMN verified_reduction_tco2e FLOAT8 NULL, ADD COLUMN eligible_tco2e FLOAT8 NULL, ADD COLUMN verification_method TEXT NULL;` + trigger d'immutabilité post-`completed` (points 4, 5)
3. `ALTER TABLE credit_lots ADD COLUMN verification_session_id UUID NOT NULL REFERENCES verification_sessions(id) ON DELETE RESTRICT;` + trigger anti-sur-émission (points 6, 7) — **nécessite une valeur par défaut ou un backfill si des lignes existent déjà** ; confirmé sans risque, `credit_lots` a 0 ligne en production au moment de la rédaction (voir audit §9tertricies).
4. Trigger de machine à états sur `credit_lots.status` (point 8) — pas de migration de schéma, seulement un trigger.
5. `ALTER TABLE credit_sale_lots ADD CONSTRAINT uq_credit_sale_lots UNIQUE (credit_sale_id, credit_lot_id); ALTER TABLE credit_sale_allocations ADD CONSTRAINT uq_credit_sale_allocations UNIQUE (credit_sale_id, organization_id);` + trigger de cohérence de totaux (point 9)
6. `CREATE TYPE carbon_event_type AS ENUM (...); CREATE TABLE carbon_business_events (...);` + policies RLS dédiées (point 10)

**Impacts RLS résumés :**
- Migrations 1-5 : aucun changement de policy RLS nécessaire sur les tables existantes — ce sont des contraintes/colonnes internes, les policies actuelles (`is_project_admin`, `is_verifier`, `is_aggregator_admin`, etc.) continuent de s'appliquer sans modification.
- Migration 6 : nouvelles policies RLS à écrire pour `carbon_business_events`, sur le modèle de `business_events` existant — pas de nouveau paradigme de permission.

**Ce que cette tranche ne tranche pas, volontairement (hors périmètre demandé) :** la méthodologie de décote/buffer pour la quantité admissible, la validation de structure du JSON `distribution_rules.parameters`, et les écrans eux-mêmes (Tranches 1 à 6 de `MVP-Carbone-Regroupements.md`) — cette Tranche 0 fournit les fondations de schéma sur lesquelles ces tranches s'appuieront.
