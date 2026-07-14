# Tranche 0 — Architecture du chantier carbone (v3)

**Statut : proposition de conception révisée, dernière passe avant validation comme architecture cible.** Aucune migration exécutée. Version 3, intégrant les 4 derniers blocages non négociables identifiés après revue de la v2 : séparation émission/commercial, correction du modèle financier et du versionnement, précision des invariants de vérification/unités/périodes, durcissement de la frontière de sécurité des RPC.

---

## 0. Convention d'unités (nouvelle section, requise par le point 3)

**Toute colonne suffixée `_tco2e` dans ce document est en tonnes métriques de CO2 équivalent.** Point de vigilance explicite : `project_activity_logs` (domaine MRV existant) exprime ses colonnes en **kilogrammes** (`ghg_emissions_baseline_kgco2e`, `ghg_emissions_project_kgco2e`, `ghg_reduction_kgco2e`) — un facteur **÷ 1000** est obligatoire à toute frontière où une donnée de `project_activity_logs` alimente une colonne `_tco2e` (ex. si `verified_reduction_tco2e` est un jour pré-rempli automatiquement à partir d'une somme d'`activity_logs`, §4 v1). Aucune conversion automatique n'est proposée dans cette tranche — la saisie de `verified_reduction_tco2e` reste manuelle (décision v1 §4), donc le risque de confusion d'unité est aujourd'hui un risque humain (vérificateur) plutôt qu'un risque de calcul, mais il doit être documenté explicitement dans l'écran de saisie (Tranche 4) : afficher la somme brute en kg à titre indicatif, jamais comme une valeur pré-remplie silencieuse en tCO2e sans conversion visible.

---

## 1. Séparer l'émission réglementaire du cycle commercial

**Problème identifié dans la v2** : `credit_lots` portait à la fois des données d'**émission officielle** (immuables par nature : quantité certifiée, registre externe, numéros de série, date d'émission) et un **statut commercial mutable** (`available/reserved/sold/retired/voided`). Mélanger un fait réglementaire figé et un cycle de vie commercial changeant sur la même ligne empêche de représenter un cas pourtant réaliste : une émission officielle unique subdivisée en **plusieurs lots commerciaux** vendus séparément (pratique courante des registres volontaires — un lot certifié peut être fractionné en unités plus petites pour la vente).

**Décision : deux tables distinctes.**

```
credit_issuances                              -- l'émission réglementaire (immuable)
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid()
  verification_session_id      UUID NOT NULL REFERENCES verification_sessions(id) ON DELETE RESTRICT
  issued_quantity_tco2e         NUMERIC(14,4) NOT NULL CHECK (issued_quantity_tco2e > 0)
  vintage_year                  INT NOT NULL
  registry_program              TEXT NULL
  external_registry_id          TEXT NULL
  external_serial_number_start  TEXT NULL
  external_serial_number_end    TEXT NULL
  issuance_date                 DATE NULL
  issued_by                     UUID REFERENCES profiles(id)
  is_voided                     BOOLEAN NOT NULL DEFAULT false
  voided_at                     TIMESTAMPTZ NULL
  voided_reason                 TEXT NULL
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
```
**Immuable par trigger** : toute colonne autre que `is_voided`/`voided_at`/`voided_reason` est rejetée en `UPDATE` — une émission ne se corrige jamais, elle se remplace (nouvelle ligne) ou s'annule (`is_voided`).

`credit_lot_sources` (v2 §7) est renommée `credit_issuance_sources` et rattachée à `credit_issuances` — la contribution de chaque organisation est un fait lié à la certification, pas à la subdivision commerciale ultérieure. Invariant inchangé (trigger) : `SUM(contributed_tco2e) = issued_quantity_tco2e`.

```
credit_lots                                   -- la subdivision commerciale (mutable)
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid()
  credit_issuance_id  UUID NOT NULL REFERENCES credit_issuances(id) ON DELETE RESTRICT
  quantity_tco2e      NUMERIC(14,4) NOT NULL CHECK (quantity_tco2e > 0)
  status              TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available','reserved','sold','retired','voided'))
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
```

**Deux niveaux de contrôle anti-surémission, plus fins qu'en v2 (qui n'en avait qu'un) :**
- **Niveau session → émission** : `SUM(issued_quantity_tco2e) FILTER (WHERE NOT is_voided) <= verification_sessions.eligible_tco2e` par `verification_session_id`.
- **Niveau émission → lots** : `SUM(quantity_tco2e) FILTER (WHERE status != 'voided') <= credit_issuances.issued_quantity_tco2e` par `credit_issuance_id`.

**Deux RPC distinctes (séparation aussi au niveau des responsabilités d'autorisation, voir §4) :**
- `create_credit_issuance(...)` — acte réglementaire, réservé au vérificateur de la session.
- `issue_credit_lot(...)` — acte commercial de subdivision, réservé à l'admin du regroupement propriétaire.
- `void_credit_issuance(p_credit_issuance_id, p_reason)` — n'est permise que si **aucun** lot enfant n'a le statut `sold`/`retired` (sinon la procédure de réversion de vente, toujours hors périmètre, doit être suivie en premier) — condition vérifiée par la RPC, pas par une contrainte déclarative (c'est une règle de workflow, pas une contrainte d'intégrité pure).

---

## 2. Correction du modèle financier et du versionnement des règles

### 2a. Modèle financier — erreur technique corrigée

**Erreur trouvée dans la v2** : `net_distributable_amount` était proposée comme colonne `GENERATED ALWAYS AS (...) STORED`, mais si `gross_amount` avait dû dépendre d'une agrégation de `credit_sale_lots` (table liée), ce ne serait **pas possible** — Postgres n'autorise une colonne générée qu'à partir de colonnes de la **même ligne**, jamais d'une agrégation inter-tables.

**Décision — prix unique par vente (limitation MVP assumée, pas cachée)** : `credit_sales.total_tco2e` et `price_per_tco2e` restent des champs saisis directement (pas de prix différencié par lot pour ce MVP — limitation explicite, à lever plus tard si un besoin de tarification par lot apparaît). Cela permet à `gross_amount` de rester une colonne générée légitime, car dépendant uniquement de colonnes de la même ligne :
```
credit_sales
  total_tco2e             NUMERIC(14,4) NOT NULL
  price_per_tco2e         NUMERIC(14,2) NOT NULL
  gross_amount            NUMERIC(14,2) GENERATED ALWAYS AS (total_tco2e * price_per_tco2e) STORED
  platform_fee_pct        NUMERIC(5,4) NOT NULL DEFAULT 0
  platform_fee_amount     NUMERIC(14,2) GENERATED ALWAYS AS (ROUND(total_tco2e * price_per_tco2e * platform_fee_pct, 2)) STORED
  net_distributable_amount NUMERIC(14,2) GENERATED ALWAYS AS (ROUND(total_tco2e * price_per_tco2e * (1 - platform_fee_pct), 2)) STORED
  currency                TEXT NOT NULL DEFAULT 'CAD'
```
`platform_fee_amount` n'est plus un champ saisi séparément (source d'incohérence en v2 si `pct` et `amount` divergeaient) — **`platform_fee_pct` est l'unique source de vérité**, le montant est toujours dérivé.

**Invariant de cohérence quantité/lots, désormais explicitement en trigger (pas en colonne générée, puisqu'il agrège `credit_sale_lots`)** : `SUM(credit_sale_lots.quantity_tco2e) = credit_sales.total_tco2e` pour une vente donnée — vérifié à la porte `finalize_credit_sale_allocations()` (v2 §11), pas à chaque `INSERT` individuel sur `credit_sale_lots` (pour ne pas rejeter un panier de vente en cours de constitution).

### 2b. Versionnement des règles — mécanisme corrigé

**Erreur de conception trouvée en v2** : un compteur `rule_version INT` sur une ligne par ailleurs modifiable par `UPDATE` ne préserve **aucun historique réel** — incrémenter le compteur sans empêcher la modification des `parameters` JSONB en place ferait perdre la trace exacte de ce qui a été appliqué à une allocation passée. Un numéro de version qui pointe vers des paramètres qui ont changé sous ses pieds n'est pas un audit trail, c'est une illusion d'audit trail.

**Décision : `distribution_rules` devient une table strictement append-only**, sur le même patron que `aggregator_memberships`/`ccf_mrv_project_links` (déjà établi en v2) :
```
distribution_rules
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid()
  aggregator_id  UUID NOT NULL REFERENCES aggregators(id) ON DELETE CASCADE
  rule_type      TEXT NOT NULL CHECK (rule_type IN ('proportional','equal','custom'))
  parameters     JSONB
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE
  effective_to   DATE NULL
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
```
- **Immuable après création** (trigger `BEFORE UPDATE` n'autorisant que la fermeture de `effective_to`, rien d'autre) — pour « changer la règle », on **insère une nouvelle ligne** et on ferme l'ancienne (`effective_to = CURRENT_DATE`), jamais un `UPDATE` des `parameters` en place.
- `UNIQUE (aggregator_id) WHERE effective_to IS NULL` — une seule règle active à la fois (même patron d'index unique partiel que partout ailleurs dans ce document).
- **`rule_version` supprimée** — redondante une fois les lignes immuables : `credit_sale_allocations.distribution_rule_id` référence directement l'`id` de la ligne exacte utilisée, qui ne changera plus jamais. Pas besoin d'un numéro de version parallèle à maintenir en cohérence.

**Statuts d'approbation/paiement** (v2 §10) inchangés dans leur principe : `credit_sale_allocations.status IN ('pending','approved','paid','disputed','cancelled')`.

---

## 3. Précision des invariants de vérification, unités et périodes

**Unités** : traitées en §0 ci-dessus.

**Invariant manquant en v2, corrigé** : `verification_sessions` reçoit `CHECK (eligible_tco2e <= verified_reduction_tco2e)` — la v2 mentionnait cette relation en prose (« un facteur de décote peut être appliqué ») sans jamais l'exprimer comme une contrainte réelle. Corrigé.

**Périodes — angle mort réel de la v1 et de la v2, maintenant corrigé** : `verification_sessions` n'avait aucune notion de **période couverte**. Sans ça, deux sessions de vérification pour le **même projet MRV** pourraient couvrir des plages de temps qui se chevauchent, chacune revendiquant une réduction sur les mêmes activités sous-jacentes — un double comptage **interne à un seul projet**, plus insidieux que le double comptage inter-projets déjà discuté en v1 (§6), et non couvert par les contrôles déjà proposés.

**Décision : ajouter les colonnes de période, obligatoires dès la création (pas seulement à la complétion, car le périmètre temporel d'une vérification est connu avant son résultat) :**
```
verification_sessions
  period_start DATE NOT NULL
  period_end   DATE NOT NULL CHECK (period_end >= period_start)
```

**Contrainte d'exclusion empêchant le chevauchement, pour les sessions complétées d'un même projet** (nécessite l'extension `btree_gist`) :
```
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE verification_sessions
  ADD CONSTRAINT no_overlapping_completed_periods
  EXCLUDE USING gist (
    project_id WITH =,
    daterange(period_start, period_end, '[]') WITH &&
  ) WHERE (status = 'completed');
```
Restreinte aux sessions `completed` : deux sessions `planned`/`in_progress` peuvent librement se chevaucher pendant la phase exploratoire (aucun risque tant qu'aucune n'a produit de résultat officiel) — seule la coexistence de deux résultats **officiels** sur des périodes qui se recoupent est structurellement empêchée.

**Ce que cette contrainte ne couvre pas, à garder en tête (déjà noté en v1 §6, toujours vrai)** : le chevauchement de périmètre (`system_boundaries`) entre **deux projets MRV différents** portant sur les mêmes activités physiques reste un risque méthodologique, pas un risque de schéma — hors de portée d'une contrainte SQL, à gérer par la revue humaine du vérificateur.

---

## 4. Frontière de sécurité des RPC et autorisation objet par objet

**Principe explicite, à respecter pour chaque RPC listée ci-dessous** : une fonction `SECURITY DEFINER` contourne entièrement la RLS — toute l'autorisation doit donc être **recalculée explicitement dans le corps de la fonction, pour l'objet précis visé**, jamais déduite d'un simple rôle global (« est vérificateur » ne suffit pas, il faut « est LE vérificateur DE CETTE session »).

**Faille structurelle trouvée en vérifiant ce principe concrètement** : `verification_sessions.verifier_org`/`verifier_contact` sont du **texte libre**, sans FK vers `profiles`/`auth.users` — il est aujourd'hui **impossible** de vérifier objet par objet qu'un utilisateur connecté est bien LE vérificateur assigné à une session précise. Le seul contrôle disponible serait un rôle générique `is_verifier()` (n'importe quel vérificateur, sur n'importe quelle session) — **insuffisant pour l'exigence d'autorisation objet par objet.**

**Décision corrective, nouvelle colonne requise** : `verification_sessions.verifier_user_id UUID NULL REFERENCES profiles(id)` — renseignée quand le vérificateur est un utilisateur de la plateforme (permet l'autorisation objet par objet) ; `verifier_org`/`verifier_contact` restent utiles tels quels pour un vérificateur externe sans compte (auquel cas l'action de complétion devrait être effectuée par un admin de projet pour son compte, avec `actor_id` distinct consigné dans l'événement d'audit — cas explicitement dégradé, pas silencieux).

**Autorisation exacte requise par RPC :**

| RPC | Autorisation objet par objet |
|---|---|
| `join_aggregator(p_organization_id, p_aggregator_id)` / `leave_aggregator(...)` | `is_aggregator_admin(p_aggregator_id)` OR `is_platform_superadmin()` — **pas** l'admin de l'organisation elle-même : l'adhésion à un regroupement est une décision du regroupement, pas une auto-inscription unilatérale. |
| `link_ccf_project_to_mrv(p_ccf_project_id, p_mrv_project_id)` | `is_ccf_project_coordinator(p_ccf_project_id)` (coordonnateur de **ce** projet précis) OR `is_platform_superadmin()`. |
| `create_credit_issuance(p_verification_session_id, ...)` | `verification_sessions.verifier_user_id = auth.uid()` **pour cette session précise** OR `is_platform_superadmin()`. Si `verifier_user_id IS NULL` (vérificateur externe sans compte), réservé à `is_platform_superadmin()` avec `actor_id` consigné explicitement dans l'événement d'audit comme agissant pour le compte d'un tiers externe. |
| `issue_credit_lot(p_credit_issuance_id, ...)` | Reconstruire la chaîne `credit_issuance → verification_session → project → operational_unit → organization → aggregator_memberships (actif)` pour déterminer l'`aggregator_id` propriétaire, puis exiger `is_aggregator_admin(cet_aggregator_id)` OR `is_platform_superadmin()`. Si la chaîne est incomplète (`operational_unit_id IS NULL`, ou aucune adhésion active), **rejeter explicitement** plutôt que de laisser passer par défaut — absence de propriétaire clair = refus, jamais une autorisation implicite. |
| `void_credit_issuance(...)` / `void_credit_lot(...)` | Même chaîne d'autorisation qu'`issue_credit_lot` ; `void_credit_issuance` interdit en plus si un lot enfant est `sold`/`retired` (§1). |
| `finalize_credit_sale_allocations(p_credit_sale_id)` | `is_aggregator_admin(credit_sales.aggregator_id)` **pour cette vente précise** OR `is_platform_superadmin()`. |

**Règle générale ajoutée pour toute future RPC de ce domaine** : si la chaîne de propriété (organisation → regroupement → objet) ne peut pas être résolue sans ambiguïté au moment de l'appel, la RPC doit refuser plutôt que d'autoriser par défaut — la charge de la preuve d'autorisation est toujours sur l'appelant, jamais sur l'absence de contre-indication.

---

## Diagramme relationnel cible (v3)

```
organizations ──< aggregator_memberships >── aggregators
     │                                            │
     │                                    aggregator_admins
     │
     ├──< ccf_projects >── ccf_mrv_project_links ──< projects (MRV) >── operational_units
     │        │                                          │
     │   project_participants                    verification_sessions
     │                                             (period_start/end,
     │                                              verifier_user_id,
     │                                              verified/eligible_tco2e)
     │                                                    │
     │                                            credit_issuances ──< credit_issuance_sources >── organizations
     │                                             (immuable, registre externe)   (multi-org, §1 v2)
     │                                                    │
     │                                            credit_lots (commercial, mutable)
     │                                                    │
     │                                            credit_sale_lots
     │                                                    │
     │                                            credit_sales (gross/fee/net générés)
     │                                                    │
     │                                            distribution_rules (append-only, versionnage par ligne)
     │                                                    │
     └──────────────────────────────────< credit_sale_allocations
                                                    │
                                          carbon_business_events (TEXT+CHECK, audit)
```

---

## Invariants garantis par la base vs garantis par RPC (mise à jour v3)

**Garantis par la base :**
- Toutes les contraintes déjà listées en v2 (adhésion/lien actifs uniques, quantités positives, machine à états des lots).
- **Nouveau (§1)** : `credit_issuances` immuable sauf champs de void (trigger) ; deux niveaux de plafond (session→émission, émission→lots).
- **Nouveau (§2)** : `distribution_rules` immuable sauf `effective_to` (trigger) ; une seule règle active par regroupement (index unique partiel) ; `gross_amount`/`platform_fee_amount`/`net_distributable_amount` toujours cohérents entre eux (colonnes générées, mêmes lignes).
- **Nouveau (§3)** : `eligible_tco2e <= verified_reduction_tco2e` (`CHECK`) ; aucun chevauchement de périodes entre deux sessions `completed` du même projet (`EXCLUDE USING gist`).

**Garantis uniquement par les RPC :**
- Toute l'autorisation objet par objet du §4 — **aucune** de ces vérifications n'est exprimable en RLS pur puisque les RPC sont `SECURITY DEFINER` par nécessité (verrouillage transactionnel, §6 v2) ; la RLS des tables sous-jacentes reste un filet pour les lectures, pas pour ces écritures.
- `SUM(credit_sale_lots.quantity_tco2e) = credit_sales.total_tco2e` — vérifié à `finalize_credit_sale_allocations()`, pas en trigger par ligne (§2a).
- L'interdiction de `void_credit_issuance` si un lot enfant est `sold`/`retired` — règle de workflow, pas une contrainte déclarative.
- Le verrouillage `SELECT ... FOR UPDATE` empêchant la surémission concurrente (v2 §6), maintenant nécessaire à **deux** niveaux (verrou sur `verification_sessions` pour `create_credit_issuance`, verrou sur `credit_issuances` pour `issue_credit_lot`).

---

## Cas de concurrence à tester (mise à jour v3 — 2 cas ajoutés aux 6 de la v2)

Les 6 cas de la v2 restent valides, reformulés pour la nouvelle séparation émission/commercial (le verrou se prend maintenant sur `verification_sessions` OU `credit_issuances` selon le niveau concerné). **Deux cas supplémentaires :**

7. **Deux `create_credit_issuance()` concurrents sur la même session**, dont la somme dépasse `eligible_tco2e` — attendu : un seul succès (verrou sur `verification_sessions`).
8. **Deux appels concurrents créant chacun une `verification_sessions` avec des périodes qui se chevauchent** pour le même projet, toutes deux visant `status = 'completed'` — attendu : la contrainte `EXCLUDE USING gist` rejette la seconde transaction à la validation, indépendamment de tout verrou applicatif (garantie déclarative, pas procédurale — bon exemple d'un invariant que la base garantit nativement sans RPC).

---

## Synthèse des migrations envisagées (v3, toujours non écrites)

Reprend la synthèse v2 avec les correctifs : `credit_lots` scindée en `credit_issuances`/`credit_lots` (une migration de plus, avec le trigger d'immuabilité et les deux niveaux de plafond) ; `distribution_rules` rendue append-only (trigger d'immuabilité + suppression de la colonne `rule_version` par rapport à la v2) ; `verification_sessions` enrichie de `period_start`/`period_end`/`verifier_user_id` + contrainte d'exclusion + `CHECK (eligible_tco2e <= verified_reduction_tco2e)` ; `credit_sales` simplifiée à un prix unique par vente avec colonnes générées cohérentes ; RPC `create_credit_issuance`/`issue_credit_lot`/`void_credit_issuance`/`void_credit_lot`/`finalize_credit_sale_allocations`/`join_aggregator`/`leave_aggregator`/`link_ccf_project_to_mrv` toutes avec l'autorisation objet par objet du §4.

**Prochaine étape, sur ta confirmation** : préparer ces migrations comme des propositions numérotées et révisables (fichiers `.sql` à lire et approuver un par un), sans exécution automatique — chaque migration restera soumise à ton approbation explicite avant tout `supabase db push`, conformément à la contrainte de gel toujours en vigueur (`ADR-MVP.md` §9septricies).
