# Tranche 0 — Architecture du chantier carbone (v4)

**Statut : proposition de conception révisée, quatrième passe.** Aucune migration exécutée. Cette version intègre 12 blocages majeurs plus 2 points secondaires identifiés après revue externe de la v3 — la revue la plus détaillée reçue jusqu'ici, avec une évaluation explicite « pas encore prêt pour les migrations » que cette version cherche à résoudre point par point, sans rien esquiver.

---

## 1. Séparer réellement le cycle d'émission du cycle commercial (deux champs de statut, pas une table qui les mélange encore)

**Ce que la v3 n'avait pas résolu** : scinder en deux tables (`credit_issuances`/`credit_lots`) ne suffit pas si `credit_issuances` n'a qu'un booléen `is_voided` — il manque une vraie machine à états réglementaire, et rien n'empêchait un lot commercial de devenir `available`/`sold` alors que son émission sous-jacente n'a jamais été confirmée par un registre externe.

**Décision : deux champs de statut explicites, sur les deux tables respectives.**

```
credit_issuances.issuance_status TEXT NOT NULL DEFAULT 'internal'
  CHECK (issuance_status IN ('internal','eligible','submitted','issued','externally_cancelled'))

credit_lots.commercial_status TEXT NOT NULL DEFAULT 'unavailable'
  CHECK (commercial_status IN ('unavailable','available','reserved','sold','retired','voided'))
```
(`commercial_status` remplace `status` — renommage pour lever toute ambiguïté avec `issuance_status`.)

**Règle d'invariant, trigger sur `credit_lots`** : `commercial_status` ne peut quitter `'unavailable'` que si `credit_issuances.issuance_status = 'issued'` pour l'émission parente. Un lot reste `unavailable` par défaut tant que son émission n'est pas confirmée par le registre — impossible de le vendre en tant que crédit officiellement émis avant ce moment.

**Distinction commerciale explicite, conforme à la remarque juridique** : une vente ne peut être présentée comme « vente de crédits officiellement émis » que si `issuance_status = 'issued'` pour tous les lots vendus. Vendre une réduction admissible non encore émise (`issuance_status` à `'eligible'`/`'submitted'`) resterait possible commercialement dans un marché volontaire préalable, mais devrait être étiqueté différemment côté produit — hors périmètre de cette tranche de trancher la mécanique commerciale exacte de ce second produit, mais le schéma ne l'interdit pas et ne le confond pas non plus avec un crédit émis.

---

## 2. `voided` ne libère pas automatiquement la quantité si le lot a déjà été émis extérieurement

**Décision : la libération de quantité dépend de `issuance_status` de l'émission parente, avec preuve obligatoire au-delà du seuil `issued`.**

Colonnes ajoutées à `credit_lots` :
```
external_cancellation_date       DATE NULL
external_cancellation_reference  TEXT NULL
external_cancellation_document_id UUID NULL REFERENCES documents(id)
```

**Règle, appliquée par la RPC `void_credit_lot()` (workflow, pas une contrainte déclarative pure — mais la contrainte suivante empêche un contournement direct) :**
- Si l'émission parente a `issuance_status != 'issued'` (jamais confirmée par un registre) → `voided` libère la quantité immédiatement, aucune preuve requise.
- Si `issuance_status = 'issued'` → `voided` **exige** `external_cancellation_date IS NOT NULL AND external_cancellation_reference IS NOT NULL` **avant** la transition, sinon rejet. Contrainte réelle : `CHECK (commercial_status != 'voided' OR NOT EXISTS (émission parente avec issuance_status = 'issued' sans preuve))` — implémentée en trigger, une contrainte `CHECK` seule ne peut pas interroger une autre table.

---

## 3. Invariants du résultat de vérification — période, conversion d'unité, arrondi

**`eligible_tco2e <= verified_reduction_tco2e`** : conservé (déjà ajouté v3), maintenant porté par `verification_outcomes` (voir §12) plutôt que `verification_sessions` directement.

**Renommage pour clarté** : `period_start`/`period_end` (v3) deviennent `reporting_period_start`/`reporting_period_end`, sur `verification_sessions`, avec la contrainte d'exclusion déjà décrite en v3 inchangée dans son mécanisme (`EXCLUDE USING gist`, restreinte aux sessions `completed`).

**Conversion d'unité, désormais explicite dans une RPC nommée, avec politique d'arrondi précisée** :
```
complete_verification_session(
  p_verification_session_id UUID,
  p_verified_reduction_tco2e NUMERIC,
  p_eligible_tco2e NUMERIC,
  p_verification_report_document_id UUID,
  p_adjustment_reason TEXT DEFAULT NULL
)
```
Cette RPC :
1. Calcule `calculated_reduction_tco2e` en sommant `project_activity_logs.ghg_reduction_kgco2e` pour les activités du projet dans `[reporting_period_start, reporting_period_end]`, puis applique **`calculated_reduction_tco2e := ROUND(somme_kg / 1000, 4)`** — division explicite par 1000, arrondi à 4 décimales par arrondi standard (`round half to even` de Postgres, comportement par défaut de `ROUND(numeric, int)`, documenté explicitement ici pour qu'aucune implémentation future ne choisisse un arrondi différent sans le remarquer).
2. Présente `calculated_reduction_tco2e` comme **valeur suggérée**, jamais imposée — le vérificateur saisit `verified_reduction_tco2e` explicitement ; si elle diverge de plus d'un seuil à définir (ex. 1 %) de la valeur calculée, `p_adjustment_reason` devient obligatoire (validé par la RPC, pas par une contrainte statique).
3. Insère un nouveau `verification_outcomes` (§12), jamais un `UPDATE` en place.

---

## 4. Mécanique précise pour l'égalité `SUM(sources) = quantité du lot` sous transaction

**Le problème identifié est réel** : un trigger `AFTER INSERT` immédiat par ligne rejetterait un lot de 100 tCO2e partagé 40/35/25 dès la première ligne (40 ≠ 100).

**Décision : `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED`** — mécanisme Postgres standard, conçu exactement pour ce cas :
```
CREATE CONSTRAINT TRIGGER check_issuance_sources_sum
  AFTER INSERT OR UPDATE OR DELETE ON credit_issuance_sources
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION validate_issuance_sources_sum();
```
Le trigger ne s'exécute qu'au moment du `COMMIT` de la transaction — toutes les lignes insérées par `create_credit_issuance()` (qui insère l'émission puis ses trois sources dans la même transaction) sont visibles au moment de la vérification, l'état intermédiaire (40 seulement) n'est jamais évalué. La fonction de validation compare alors `SUM(contributed_tco2e) = credit_issuances.issued_quantity_tco2e` pour l'émission concernée et lève une exception si l'égalité n'est pas respectée — auquel cas **toute la transaction est annulée**, y compris l'émission elle-même (cohérent : une émission sans sources cohérentes ne doit jamais exister, même transitoirement en dehors d'une transaction).

---

## 5. Versionnement des règles — historisation garantie, pas seulement une table immuable

**Ce que la v3 avait déjà bien fait** : `distribution_rules` append-only avec trigger d'immutabilité. **Ce qui restait fragile, signalé à juste titre** : une immutabilité appliquée uniquement par trigger reste, en théorie, contournable par une migration future ou une action super-admin qui désactiverait temporairement le trigger — un vrai audit ne devrait pas dépendre uniquement d'un mécanisme qui peut être désactivé.

**Décision, approche ceinture-et-bretelles : conserver `distribution_rules` immuable ET ajouter un instantané figé directement dans l'allocation.**
```
credit_sale_allocations
  distribution_rule_id UUID REFERENCES distribution_rules(id)
  rule_snapshot         JSONB NOT NULL   -- copie littérale de {rule_type, parameters} au moment du calcul
```
`rule_snapshot` est rempli par la RPC de calcul d'allocation (pas par une valeur par défaut liée à la table `distribution_rules`) — même si `distribution_rules` était un jour altérée malgré son trigger d'immutabilité, l'enregistrement historique exact reste dans l'allocation elle-même, immuable par le même principe que le reste du domaine financier (§6).

---

## 6. Modèle financier complet — coûts multiples, montant net figé, corrections auditées

**Décision : nouvelle table `credit_sale_costs`, le net n'est plus une simple colonne générée.**
```
credit_sale_costs
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid()
  credit_sale_id  UUID NOT NULL REFERENCES credit_sales(id) ON DELETE RESTRICT
  cost_type       TEXT NOT NULL CHECK (cost_type IN (
                    'platform_fee','registry_fee','verification_fee','brokerage',
                    'legal_fee','risk_reserve','administrative_fee','tax','other'
                  ))
  description     TEXT NULL
  amount          NUMERIC(14,2) NOT NULL CHECK (amount >= 0)
  currency        TEXT NOT NULL DEFAULT 'CAD'
  beneficiary     TEXT NULL   -- à qui va ce coût (plateforme, registre, vérificateur, tiers)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
```

**`net_distributable_amount` n'est plus générée depuis une seule colonne de frais de plateforme** — elle dépend maintenant d'un agrégat sur `credit_sale_costs` (impossible en colonne générée, même contrainte technique que §2a de la v3). Elle devient un champ figé par la RPC de confirmation :
```
confirm_credit_sale(p_credit_sale_id UUID)
```
qui calcule `net_distributable_amount := gross_amount - SUM(credit_sale_costs.amount WHERE credit_sale_id = p_credit_sale_id)`, l'écrit une seule fois, puis **verrouille `credit_sales` et `credit_sale_costs` liés à cette vente en écriture** (trigger d'immutabilité déclenché par le passage à `status = 'confirmed'`).

**Corrections post-confirmation, table dédiée plutôt qu'un `UPDATE` déguisé :**
```
credit_sale_adjustments
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid()
  credit_sale_id  UUID NOT NULL REFERENCES credit_sales(id) ON DELETE RESTRICT
  amount          NUMERIC(14,2) NOT NULL   -- signé, positif ou négatif
  reason          TEXT NOT NULL
  created_by      UUID REFERENCES profiles(id)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
```
Le montant net réellement distribuable après correction = `net_distributable_amount + SUM(credit_sale_adjustments.amount)` — jamais une modification rétroactive du montant figé initial.

---

## 7. Lien explicite regroupement ↔ lot ↔ organisations contributrices, figé dans le temps

**Décision : `credit_lots.aggregator_id` et `credit_issuances.aggregator_id`, tous deux figés à la création, jamais recalculés depuis l'adhésion courante.**
```
credit_issuances.aggregator_id UUID NOT NULL REFERENCES aggregators(id) ON DELETE RESTRICT
credit_lots.aggregator_id      UUID NOT NULL REFERENCES aggregators(id) ON DELETE RESTRICT
  -- copié depuis credit_issuances.aggregator_id au moment de issue_credit_lot(), jamais recalculé ensuite
```

**Validations obligatoires dans `create_credit_issuance()` avant d'accepter les sources proposées (`p_sources jsonb`), aucune confiance dans le contenu brut du JSON :**
1. Chaque organisation listée dans `p_sources` doit être un participant réel du projet CCF ou MRV concerné — vérifié par jointure explicite (`project_participants` via `ccf_mrv_project_links`, ou `operational_units.organization_id`), **jamais** acceptée simplement parce qu'elle apparaît dans le JSON.
2. Chaque organisation source doit avoir eu une adhésion **active au moment précis de l'émission** au regroupement désigné — vérifié par une requête **temporelle** sur `aggregator_memberships` (`started_at <= now() AND (ended_at IS NULL OR ended_at > now())`), jamais par un simple test « est membre actuellement » qui se tromperait rétroactivement si l'organisation quitte le regroupement plus tard.
3. `aggregator_id` de l'émission est déterminé par cette vérification (l'aggregator commun aux sources), pas fourni librement par l'appelant — si les sources n'ont pas d'aggregator commun, rejet explicite.

**Conséquence** : le départ ultérieur d'une organisation d'un regroupement (`aggregator_memberships.ended_at` renseigné) ne modifie jamais rétroactivement `credit_issuances.aggregator_id`/`credit_lots.aggregator_id` déjà émis — l'historique du lot reste figé à l'état d'adhésion du moment de l'émission, jamais dépendant de l'état courant.

---

## 8. `ON DELETE RESTRICT` plutôt que `CASCADE` sur les relations historiques

**Décision : remplacer `CASCADE` par `RESTRICT` sur toutes les tables listées, y compris celles déjà proposées en v2/v3 :**

| Table.colonne | v3 | v4 |
|---|---|---|
| `aggregator_memberships.organization_id` | `CASCADE` | **`RESTRICT`** |
| `aggregator_memberships.aggregator_id` | `CASCADE` | **`RESTRICT`** |
| `ccf_mrv_project_links.ccf_project_id` | `CASCADE` | **`RESTRICT`** |
| `ccf_mrv_project_links.mrv_project_id` | (implicite) | **`RESTRICT`** |
| `credit_issuance_sources.credit_issuance_id` | `CASCADE` | **`RESTRICT`** |

**Justification** : dans un domaine auditable, la suppression d'une organisation ou d'un regroupement ne doit **jamais** effacer silencieusement une adhésion passée, un rattachement historique ou la provenance d'un lot — même si aucune policy `DELETE` n'est exposée aujourd'hui à un rôle applicatif, un super-administrateur ou une migration future pourrait déclencher une suppression physique. `RESTRICT` force une décision explicite (archiver plutôt que supprimer) à chaque fois qu'une suppression serait tentée. Le mécanisme de fermeture déjà en place (`ended_at`/`effective_to`/statuts `voided`/`retired`) reste la seule façon prévue de « désactiver » une ligne — jamais une suppression physique.

---

## 9. RPC de bootstrap — création d'un regroupement avec son premier administrateur

**Manque confirmé** : `transfer_aggregator_primary_admin()` (existante) suppose qu'un `primary_admin` existe déjà — rien ne couvre la création initiale.

**Décision : nouvelle RPC réservée à `is_platform_superadmin()`.**
```
create_aggregator_with_primary_admin(
  p_name TEXT,
  p_description TEXT,
  p_primary_admin_user_id UUID
)
```
Effectue atomiquement, dans une seule transaction :
1. `INSERT INTO aggregators (...)`.
2. `INSERT INTO aggregator_admins (aggregator_id, user_id, role) VALUES (..., p_primary_admin_user_id, 'primary_admin')` — protégé par l'index unique partiel déjà existant (`idx_one_active_primary_admin`), garantissant qu'aucun second `primary_admin` actif ne peut coexister dès la création.
3. Insertion d'un événement `carbon_business_events` (`object_type = 'aggregator'`, création).

---

## 10. RLS objet par objet — fonctions d'autorisation nommément précises

**Décision : nouvelle fonction `is_assigned_verifier(p_verification_session_id UUID) RETURNS BOOLEAN`**, remplaçant tout usage de `is_verifier()` générique dans ce domaine :
```sql
-- signature, pas d'implémentation ici
is_assigned_verifier(p_verification_session_id UUID) RETURNS BOOLEAN
  -- vérifie verification_sessions.verifier_user_id = auth.uid() pour CETTE session précise
```
Remplace `is_verifier()` dans : la policy RLS `UPDATE` sur `verification_sessions`, et l'autorisation interne de `complete_verification_session()` (§3).

**Même principe déjà appliqué en v3 pour les RPC liées aux regroupements, reconfirmé ici** : chaque RPC reçoit ou dérive l'`aggregator_id` exact de l'objet concerné (jamais « administre un regroupement quelconque ») — `issue_credit_lot()`, `void_credit_lot()`, `confirm_credit_sale()` vérifient toutes `is_aggregator_admin(objet.aggregator_id)`, où `aggregator_id` est lu depuis l'objet manipulé (§7), pas fourni librement par l'appelant.

---

## 11. Exigences de durcissement des fonctions `SECURITY DEFINER` (checklist Tranche 0, à respecter à l'implémentation)

Ce n'est pas un détail d'implémentation reporté — puisque ces RPC deviennent la frontière de sécurité principale du domaine carbone (RLS contournée par nécessité), la Tranche 0 fixe ces exigences comme critères d'acceptation obligatoires pour toute RPC de ce domaine, avant fusion de toute PR qui les implémente :

- `SET search_path = public, pg_temp` (ou plus restrictif) sur chaque fonction — cohérent avec `MVP-RA-021` déjà en vigueur pour le domaine CCF.
- Vérification explicite de `auth.uid()` en première ligne de chaque fonction — rejet immédiat si `NULL`.
- Validation de **chaque** identifiant reçu en paramètre (existence, appartenance au bon type d'objet) avant toute écriture — jamais une confiance implicite qu'un UUID reçu désigne un objet valide.
- Aucun recours à `raw_user_meta_data` pour une décision d'autorisation (donnée modifiable par l'utilisateur lui-même côté client).
- `REVOKE EXECUTE ... FROM PUBLIC` par défaut sur chaque fonction, `GRANT EXECUTE` explicitement accordé uniquement au(x) rôle(s) applicatif(s) requis (`authenticated`, jamais `anon` pour ces RPC).
- Qualification complète des références de table (`public.nom_table`), jamais de dépendance implicite au `search_path` de la session appelante.
- Aucune confiance dans le contenu de tout paramètre `jsonb` (ex. `p_sources`) — validation stricte de structure et de valeurs avant utilisation, jamais un `INSERT ... SELECT * FROM jsonb_populate_recordset(...)` non gardé.
- Journalisation obligatoire (`carbon_business_events`) pour toute action de ce domaine, y compris les échecs d'autorisation significatifs (tentative refusée), pas seulement les succès.
- Gestion des erreurs sans fuite d'information sensible au client (messages génériques exposés, détail complet uniquement dans les logs serveur).

---

## 12. `verification_sessions` — option robuste retenue : `verification_outcomes`

**Décision, tranchée plutôt que laissée ouverte** : au vu de la direction prise sur l'ensemble de cette révision (historisation immuable systématique — adhésions, liens MRV, règles de distribution, coûts de vente), la cohérence architecturale impose la même logique ici plutôt qu'une simplification MVP qui serait immédiatement en contradiction avec le reste du modèle.

```
verification_outcomes
  id                             UUID PRIMARY KEY DEFAULT gen_random_uuid()
  verification_session_id        UUID NOT NULL REFERENCES verification_sessions(id) ON DELETE RESTRICT
  calculated_reduction_tco2e     NUMERIC(14,4) NOT NULL
  verified_reduction_tco2e        NUMERIC(14,4) NOT NULL CHECK (verified_reduction_tco2e >= 0)
  eligible_tco2e                  NUMERIC(14,4) NOT NULL CHECK (eligible_tco2e >= 0 AND eligible_tco2e <= verified_reduction_tco2e)
  verification_report_document_id UUID REFERENCES documents(id)
  verified_by                     UUID NOT NULL REFERENCES profiles(id)
  verified_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
  adjustment_reason               TEXT NULL
  superseded_by_outcome_id        UUID NULL REFERENCES verification_outcomes(id)
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
```
**Immuable après création** (trigger, sauf `superseded_by_outcome_id` qui ne peut être renseigné qu'une seule fois, jamais réécrit). `UNIQUE (verification_session_id) WHERE superseded_by_outcome_id IS NULL` — un seul résultat actif à la fois par session, même patron d'index unique partiel que tout le reste du document. Corriger un résultat erroné = insérer un nouveau `verification_outcomes` et marquer l'ancien comme remplacé, jamais un `UPDATE`.

`verification_sessions` garde uniquement : `project_id`, `status`, `reporting_period_start`/`end`, `verifier_user_id`, `verifier_org`/`verifier_contact` — le **résultat** de la vérification vit entièrement dans `verification_outcomes`.

**`credit_issuances.verification_session_id` devient `credit_issuances.verification_outcome_id`** (référence au résultat précis utilisé, pas seulement à la session — cohérent avec le fait qu'une session peut avoir plusieurs résultats successifs si une correction a eu lieu).

---

## Points secondaires

**Allocations à composantes multiples** : `credit_sale_allocations` reçoit `allocation_type TEXT NOT NULL DEFAULT 'carbon_revenue' CHECK (allocation_type IN ('carbon_revenue','expense_reimbursement','reserve','bonus','adjustment'))`, et la contrainte devient `UNIQUE (credit_sale_id, organization_id, allocation_type)` — permet plusieurs lignes par organisation si plusieurs composantes distinctes doivent être distinguées, sans perdre la protection contre le doublon accidentel d'une même composante.

**`carbon_business_events` strictement append-only** : trigger rejetant explicitement tout `UPDATE`/`DELETE` sur cette table, quel que soit le rôle (y compris `postgres` en usage normal — seule une intervention manuelle explicite en dehors du chemin applicatif pourrait le faire). Insertion réservée aux RPC métier (`SECURITY DEFINER`), aucune policy `INSERT` directe pour un rôle applicatif. Chaînage/hash d'intégrité (type « append-only ledger ») noté comme extension future possible si un niveau de preuve supérieur devient nécessaire — pas requis pour ce MVP.

---

## Diagramme relationnel cible (v4)

```
organizations ──< aggregator_memberships (historisée, RESTRICT) >── aggregators ──< aggregator_admins
     │                                                                    │
     │                                                    create_aggregator_with_primary_admin()
     │
     ├──< ccf_projects >── ccf_mrv_project_links (historisée, RESTRICT) ──< projects (MRV) >── operational_units
     │        │                                                                  │
     │   project_participants                                          verification_sessions
     │                                                                   (period, verifier_user_id)
     │                                                                          │
     │                                                                  verification_outcomes
     │                                                                   (immuable, versionné, §12)
     │                                                                          │
     │                                                          credit_issuances (aggregator_id figé,
     │                                                           issuance_status, registre externe)
     │                                                                          │
     │                                                          credit_issuance_sources >── organizations
     │                                                           (validées : participation + adhésion
     │                                                            active au moment de l'émission, §7)
     │                                                                          │
     │                                                          credit_lots (aggregator_id figé,
     │                                                           commercial_status, annulation externe)
     │                                                                          │
     │                                                          credit_sale_lots
     │                                                                          │
     │                                                          credit_sales ──< credit_sale_costs
     │                                                                  │   └──< credit_sale_adjustments
     │                                                          distribution_rules (append-only)
     │                                                                          │
     └──────────────────────────────────< credit_sale_allocations (rule_snapshot, allocation_type)
                                                                          │
                                                          carbon_business_events (append-only, TEXT+CHECK)
```

---

## Invariants garantis par la base vs par RPC (mise à jour v4)

**Garantis par la base** : tout ce qui était listé en v2/v3, plus — `commercial_status` ne quitte `'unavailable'` que si `issuance_status = 'issued'` (trigger) ; `SUM(credit_issuance_sources.contributed_tco2e) = issued_quantity_tco2e` via **contrainte différée** (§4, mécanisme maintenant précisé) ; `eligible_tco2e <= verified_reduction_tco2e` porté par `verification_outcomes` ; un seul résultat de vérification actif par session (index unique partiel) ; `distribution_rules`/`verification_outcomes`/`credit_sales` (post-confirmation) immuables par trigger ; `RESTRICT` sur toutes les FK historiques (§8) ; `carbon_business_events` sans `UPDATE`/`DELETE` possible.

**Garantis uniquement par RPC** : toute la validation objet-par-objet (§7, §10) ; le calcul et gel du montant financier net (§6) ; la conversion d'unité avec arrondi documenté (§3) ; le bootstrap d'un regroupement (§9) ; le verrouillage transactionnel contre la surémission concurrente (v2 §6, toujours valable aux deux niveaux session→émission et émission→lots) ; la checklist de durcissement (§11) qui ne peut pas être exprimée en SQL déclaratif par nature.

---

## Cas de concurrence à tester (mise à jour v4)

Les 8 cas des versions précédentes restent valides. **Deux cas supplémentaires liés aux nouvelles mécaniques :**

9. **Insertion concurrente de sources pour la même émission par deux appels partiels** (ex. un bug appelant `create_credit_issuance()` deux fois pour la même émission) — attendu : la contrainte différée (§4) rejette à la validation si la somme ne correspond pas, quel que soit l'ordre d'arrivée des lignes.
10. **`confirm_credit_sale()` concurrent à un `INSERT` sur `credit_sale_costs` pour la même vente** — attendu : le montant net figé ne doit jamais être calculé sur un état partiel des coûts ; verrou explicite sur `credit_sales` requis dans `confirm_credit_sale()`, sur le même principe que §6 v2.

---

## Réponse à l'évaluation reçue

Chaque dimension signalée « encore insuffisante » ou « manquante » est adressée dans cette version : traçabilité carbone (§7, §12), prévention du double comptage (§4 précisé), gouvernance des regroupements (§9), sécurité RLS/RPC (§10, §11), modèle financier (§6), séparation émission/commercial (§1, §2). Les points restés volontairement hors périmètre sont explicitement nommés à chaque section correspondante (ex. mécanique commerciale exacte d'une vente de réduction non-émise, §1 ; seuil précis de tolérance pour `adjustment_reason`, §3) — pas oubliés, mais reconnus comme des décisions produit distinctes de l'architecture de schéma.

---

## Prochaine étape

Sur ta confirmation que cette version constitue l'architecture cible : préparation des migrations comme propositions numérotées et révisables (fichiers `.sql` séparés, un par sous-domaine cohérent — émission/commercial, vérification/outcomes, financier, gouvernance/RPC, événements), chacune soumise à ta lecture et ton approbation explicite avant tout `supabase db push`, conformément au gel toujours en vigueur (`ADR-MVP.md` §9septricies).
