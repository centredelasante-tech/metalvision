# Tranche 0 — Architecture du chantier carbone (v4 + corrections finales)

**Statut : validée comme architecture cible par l'utilisateur, sous réserve des 7 corrections techniques finales ci-dessous.** Les migrations sont préparées comme fichiers séparés, numérotés, révisables (voir `supabase/carbon_migrations_proposed/`), sans exécution ni fusion automatique. **État réel actualisé (dix-huitième revue statique, 20 juillet 2026)** : `01_carbon_foundations_events_and_failures.sql`, `02_carbon_aggregator_memberships.sql`, `03_fix_null_bypass_authorization.sql` et `06_carbon_operator_and_mandates.sql` (+ correctif `06a`) **appliquées** en production (détail complet dans ADR-MVP.md, source canonique de ce statut d'exécution) ; `04_carbon_ccf_mrv_project_links.sql`, `05_carbon_verification_outcomes.sql`, `07_carbon_issuances.sql`, `08_carbon_lots_commercial_cycle.sql` et `09_carbon_sales_financial_model.sql` **non appliquées** — `07` est rédigée et en revue statique itérative (§15), `04`/`05`/`08`/`09` restent à rédiger.

---

## Corrections finales (avant préparation des migrations)

**1. Règle d'arrondi PostgreSQL — erreur de fait corrigée.** Le document affirmait que `ROUND(numeric, int)` utilise l'arrondi bancaire (« round half to even ») par défaut en PostgreSQL — **c'est faux**. Le comportement réel de `ROUND()` sur le type `numeric` est l'arrondi arithmétique standard (« round half away from zero » : 0,5 arrondit toujours vers le haut en valeur absolue). `complete_verification_session()` (§3/§4 migration) documente désormais explicitement ce comportement réel plutôt que le comportement erroné précédemment cité — aucun changement de fonction nécessaire, seulement une correction de la documentation pour qu'une future implémentation ne présume pas d'un comportement inexistant.

**2. Interdiction stricte des ventes avant émission officielle, sans ambiguïté produit.** La v4 laissait ouverte la possibilité future de vendre une « réduction admissible non encore émise » comme un second produit commercial distinct — supprimé. **Décision MVP, sans exception** : `credit_sale_lots` ne peut référencer un `credit_lot` que si l'émission parente a `issuance_status = 'issued'`, vérifié par un trigger dédié sur `credit_sale_lots` **en plus** (défense en profondeur, pas en remplacement) du verrou déjà existant sur `commercial_status` (§1 v4, un lot ne quitte `unavailable` que si `issued`). Toute vente d'une réduction pré-émission est explicitement hors périmètre de ce MVP, pas simplement non implémentée.

**3. Mécanique de supersession de `verification_outcomes`, précisée.** Modèle officiel (voir §12) : `status TEXT CHECK (status IN ('active','superseded'))` + `supersedes_outcome_id` référençant **vers l'arrière** (le nouveau résultat référence l'ancien qu'il remplace, jamais l'inverse). Quand `complete_verification_session()` est appelée pour une session ayant déjà un résultat actif : `p_adjustment_reason` devient **obligatoire** (pas seulement au-delà d'un seuil, comme c'était le cas pour un premier résultat) ; la RPC verrouille l'ancien résultat (`SELECT ... FOR UPDATE`), le transitionne à `status = 'superseded'`, puis insère le nouveau résultat avec `status = 'active'` et `supersedes_outcome_id` pointant vers l'ancien — le tout dans une seule transaction. Le trigger d'immutabilité est donc précisé : il rejette tout changement sauf la transition de `status` de `'active'` vers `'superseded'` (jamais l'inverse, jamais une deuxième fois, `'superseded'` terminal).

**4. Validation explicite qu'une émission a au moins une source.** Le contrôle différé (§4 v4) rejette déjà indirectement une émission sans source cohérente (la somme ne peut égaler `quantity_tco2e > 0` si aucune ligne n'existe — colonne renommée depuis `issued_quantity_tco2e`, voir §15 point 1), mais `create_credit_issuance()` ajoute désormais une vérification amont explicite — rejet immédiat et lisible si `p_sources` est vide ou nul, avant toute tentative d'insertion, en plus de (pas à la place de) la contrainte différée qui reste le filet de sécurité structurel.

**5. Séparation des journaux d'échec et des événements métier.** `carbon_business_events` ne contient désormais **que** des événements métier réussis. Les refus d'autorisation et échecs de validation des RPC sont consignés dans une table distincte, `carbon_rpc_failures` — audience et politique de rétention différentes (revue de sécurité vs audit métier), ne polluent jamais le fil d'événements métier.

**6. Cohérence des devises.** Aucune conversion automatique dans ce MVP — un trigger sur `credit_sale_costs` et `credit_sale_allocations` rejette toute ligne dont `currency` diffère de `credit_sales.currency` pour la même vente.

**7. Catalogue d'événements complété.** Voir le catalogue exhaustif dans la migration 01 (§ fondations transverses) — couvre désormais chaque entité/transition introduite en v2-v4 (regroupements, liens CCF-MRV, sessions/résultats de vérification avec supersession, émissions avec leurs 5 statuts, lots commerciaux, ventes/coûts/ajustements/allocations).

---

## 1. Séparer réellement le cycle d'émission du cycle commercial (deux champs de statut, pas une table qui les mélange encore)

**Ce que la v3 n'avait pas résolu** : scinder en deux tables (`credit_issuances`/`credit_lots`) ne suffit pas si `credit_issuances` n'a qu'un booléen `is_voided` — il manque une vraie machine à états réglementaire, et rien n'empêchait un lot commercial de devenir `available`/`sold` alors que son émission sous-jacente n'a jamais été confirmée par un registre externe.

**Décision : deux champs de statut explicites, sur les deux tables respectives.**

```
credit_issuances.issuance_status TEXT NOT NULL DEFAULT 'internal'
  CHECK (issuance_status IN ('internal','eligible','submitted','issued','externally_cancelled','externally_rejected','voided'))

credit_lots.commercial_status TEXT NOT NULL DEFAULT 'unavailable'
  CHECK (commercial_status IN ('unavailable','available','reserved','sold','retired','voided'))
```
(`commercial_status` remplace `status` — renommage pour lever toute ambiguïté avec `issuance_status`. **Révisé après une troisième revue (§15 point 10)** : `issuance_status` porte désormais **trois** terminaux distincts et non ambigus, pas deux : `'voided'` = annulation **strictement interne**, jamais transmise à un registre externe, accessible uniquement depuis `{'internal','eligible'}`, libère la quantité sans preuve requise ; `'externally_rejected'` = le registre externe a **refusé** une demande déjà `'submitted'` (jamais atteint `'issued'`), accessible uniquement depuis `'submitted'`, preuve obligatoire, libère la quantité ; `'externally_cancelled'` = le registre externe a annulé une émission déjà officiellement `'issued'`, accessible uniquement depuis `'issued'`, preuve obligatoire, ne libère jamais la quantité. **`submitted → voided` n'existe plus** — une demande déjà transmise au registre ne peut plus être annulée unilatéralement côté METALTRACE avec réutilisation immédiate des tonnes ; seul le registre externe, via `'externally_rejected'`, peut mettre fin à une demande `submitted`.)

**Règle d'invariant, trigger sur `credit_lots`** : `commercial_status` ne peut quitter `'unavailable'` que si `credit_issuances.issuance_status = 'issued'` pour l'émission parente. Un lot reste `unavailable` par défaut tant que son émission n'est pas confirmée par le registre — impossible de le vendre en tant que crédit officiellement émis avant ce moment.

**Garde structurelle empêchant une émission sans sources de progresser (correction ajoutée après revue)** : un trigger `BEFORE UPDATE ON credit_issuances` rejette toute tentative de faire passer `issuance_status` de `'internal'` vers `'eligible'`, `'submitted'` ou `'issued'` si aucune ligne `credit_issuance_sources` n'existe pour cette émission, ou si leur somme ne correspond pas encore à `quantity_tco2e`. Redondant par conception avec la contrainte différée du §4 et la vérification amont de `create_credit_issuance()` (§4, correction 4) — trois mécanismes indépendants pour le même invariant, à des moments différents (création de source, changement de statut, appel RPC), cohérent avec le principe de défense en profondeur déjà appliqué ailleurs dans ce document.

**Interdiction stricte des ventes avant émission officielle, sans ambiguïté produit (corrigé après revue — remplace une formulation ambiguë antérieure)** : `credit_sale_lots` ne peut référencer un `credit_lot` que si `issuance_status = 'issued'` pour l'émission parente — vérifié par un trigger dédié sur `credit_sale_lots` (migration 07), **en plus** du verrou déjà existant sur `commercial_status` ci-dessus (défense en profondeur, pas redondance inutile). Aucune vente d'une réduction pré-émission n'est permise dans ce MVP — exclusion de portée assumée, pas une limitation temporaire à lever plus tard sans decision explicite.

---

## 2. `voided`/`externally_rejected` ne libèrent pas la quantité dans tous les cas de la même façon — trois régimes distincts, pas deux

**Erreur de condition trouvée après revue et corrigée** : la règle précédente testait `issuance_status != 'issued'` pour décider si une preuve externe était requise — mais `'externally_cancelled' != 'issued'` est vrai littéralement, alors que `'externally_cancelled'` représente précisément le cas où le registre **a** confirmé l'annulation après une émission officielle — c'est exactement le cas qui doit exiger une preuve, pas celui qui doit en être dispensé.

**Révisé une seconde fois après la troisième revue (§15 point 10)** : un deuxième bug de conception potentiel a été identifié entre-temps — autoriser `submitted → voided` reviendrait à permettre à METALTRACE d'annuler unilatéralement, sans preuve, une demande déjà transmise à un registre externe, avec réutilisation immédiate de la capacité. Une demande transmise n'est plus un fait purement interne : seul le registre externe peut y mettre fin (refus, matérialisé par `'externally_rejected'`, preuve obligatoire). `'voided'` est donc désormais **strictement limité** à `{'internal','eligible'}` — avant toute transmission externe.

**Décision corrigée, trois régimes explicites, plus une négation ambiguë à deux :**
```
issuance_status IN ('internal','eligible')
  → 'voided' : annulation interne possible sans preuve externe (l'émission n'a jamais été transmise à un registre). Libère la capacité.

issuance_status = 'submitted'
  → 'externally_rejected' : preuve de refus externe obligatoire (le registre a refusé la demande transmise). Libère la capacité.

issuance_status = 'issued'
  → 'externally_cancelled' : preuve d'annulation externe obligatoire (le registre a annulé une émission déjà confirmée). Ne libère jamais la capacité.
```

**Les champs de preuve appartiennent à `credit_issuances`, pas à `credit_lots`** (correction de placement après revue) — puisque `externally_cancelled`/`externally_rejected` sont des états de l'émission réglementaire elle-même (§1), la preuve de leur transition est une donnée de l'émission, pas de chacune de ses subdivisions commerciales :
```
credit_issuances
  external_cancellation_date        DATE NULL
  external_cancellation_reference   TEXT NULL
  external_cancellation_document_id UUID NULL REFERENCES documents(id)
  external_rejection_date           DATE NULL
  external_rejection_reference      TEXT NULL
  external_rejection_document_id    UUID NULL REFERENCES documents(id)
```

**Conséquence sur le cycle commercial des lots** : un `credit_lot` individuel ne peut plus être `voided` unilatéralement une fois son émission parente `issued` — sa mise à `voided` devient une **conséquence** du passage de `credit_issuances.issuance_status` à `'externally_cancelled'` (avec preuve), jamais une action indépendante au niveau du lot. Tant que l'émission reste `issued` sans annulation externe confirmée, ses lots commerciaux ne peuvent transiter que selon la machine à états normale (`available/reserved/sold/retired`) — pas vers `voided`.

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
1. Calcule `calculated_reduction_tco2e` en sommant `project_activity_logs.ghg_reduction_kgco2e` pour les activités du projet dans `[reporting_period_start, reporting_period_end]`, puis applique **`calculated_reduction_tco2e := ROUND(somme_kg / 1000, 4)`** — division explicite par 1000, arrondi à 4 décimales. **Comportement réel de `ROUND(numeric, int)` en PostgreSQL, à ne pas confondre avec l'arrondi bancaire** : arrondi arithmétique standard (« round half away from zero » — 0,5 arrondit toujours vers le haut en valeur absolue, jamais vers la valeur paire la plus proche). Documenté ici explicitement pour qu'aucune implémentation future ne présume d'un comportement différent (ex. arrondi bancaire) sans le remarquer.
2. Présente `calculated_reduction_tco2e` comme **valeur suggérée**, jamais imposée — le vérificateur saisit `verified_reduction_tco2e` explicitement ; si elle diverge de plus d'un seuil à définir (ex. 1 %) de la valeur calculée, `p_adjustment_reason` devient obligatoire (validé par la RPC, pas par une contrainte statique).
3. Insère un nouveau `verification_outcomes` (§12), jamais un `UPDATE` en place. **Si la session a déjà un résultat actif** (correction de supersession) : `p_adjustment_reason` devient **obligatoire dans tous les cas** (pas seulement au-delà du seuil de divergence — corriger un résultat déjà officiel exige toujours une justification), puis la RPC verrouille l'ancien résultat (`SELECT ... FOR UPDATE`), exécute l'unique `UPDATE` permis sur celui-ci (`status` de `'active'` vers `'superseded'`, jamais l'inverse, jamais une deuxième fois), puis insère le nouveau résultat avec `status = 'active'` et `supersedes_outcome_id` pointant vers l'ancien.

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
Le trigger ne s'exécute qu'au moment du `COMMIT` de la transaction — toutes les lignes insérées par `create_credit_issuance()` (qui insère l'émission puis ses trois sources dans la même transaction) sont visibles au moment de la vérification, l'état intermédiaire (40 seulement) n'est jamais évalué. La fonction de validation compare alors `SUM(contributed_tco2e) = credit_issuances.quantity_tco2e` pour l'émission concernée et lève une exception si l'égalité n'est pas respectée — auquel cas **toute la transaction est annulée**, y compris l'émission elle-même (cohérent : une émission sans sources cohérentes ne doit jamais exister, même transitoirement en dehors d'une transaction).

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

**10bis. Portée MRV manquante dans la RLS de `carbon_business_events` — corrigée après revue.** La policy `carbon_business_events_select` initiale (§ci-dessous, migration 01) ne couvre que : super-admin plateforme, acteur de l'événement, membre de l'organisation, admin du regroupement. Elle omet un cas réel : **un vérificateur assigné à une session, qui n'est ni l'acteur de l'événement ni membre de l'organisation concernée**, doit néanmoins pouvoir consulter les événements liés à cette session (ex. `verification_outcome_recorded`, `verification_outcome_superseded`).

Correction retenue : ajouter une colonne `verification_session_id UUID NULL REFERENCES verification_sessions(id) ON DELETE RESTRICT` à `carbon_business_events`, renseignée par toute RPC émettant un événement du domaine vérification, et centraliser la logique de lecture dans une fonction unique plutôt que de faire grossir indéfiniment le `USING` inline de la policy.

**Récursion RLS potentielle, corrigée après revue.** Une première version de cette fonction prenait `p_event_id UUID` en unique paramètre et relisait elle-même la ligne (`SELECT ... FROM carbon_business_events WHERE id = p_event_id`) pour en extraire `actor_id`/`organization_id`/`aggregator_id`. Or cette lecture, exécutée par une fonction `SECURITY INVOKER` appelée depuis la policy `SELECT` de **cette même table**, est elle-même soumise à cette policy — qui rappelle la fonction. Risque réel de récursion RLS. Corrigé en supprimant toute lecture de table à l'intérieur de la fonction : la signature retenue est **`can_view_carbon_event(p_actor_id UUID, p_organization_id UUID, p_aggregator_id UUID, p_verification_session_id UUID) RETURNS BOOLEAN`**, appelée par la policy avec les colonnes de la ligne déjà en cours d'évaluation (`actor_id`, `organization_id`, `aggregator_id`, `verification_session_id`) — aucun accès à `carbon_business_events` depuis l'intérieur de la fonction, donc aucune récursion possible.

**Séquencement délibéré entre migrations 01 et 05** — `is_assigned_verifier()` et `verification_sessions.verifier_user_id` n'existent qu'à partir de la migration 05 (§14 : 04 = `ccf_mrv_project_links`, 05 = `verification_outcomes` + `is_assigned_verifier()`) ; la migration 01 ne peut donc pas y référer sans créer une dépendance en avant. Solution : `can_view_carbon_event()` est créée dès la migration 01 dans une **version de base** (super-admin, acteur, organisation, regroupement — strictement équivalente à la policy inline qu'elle remplace, aucun comportement nouveau à ce stade), avec `p_verification_session_id` déjà présent dans la signature mais inutilisé, explicitement commentée comme *« à étendre par la migration 05 »*. La migration 05 fait un `CREATE OR REPLACE FUNCTION public.can_view_carbon_event(...)` (même signature) qui ajoute la branche `p_verification_session_id IS NOT NULL AND public.is_assigned_verifier(p_verification_session_id)`, sans toucher à la policy elle-même (qui appelle déjà la fonction avec les 4 paramètres depuis la migration 01) ni à sa signature. Ce découpage évite toute référence à un objet pas encore créé tout en gardant un seul point d'autorisation à maintenir, sans relecture de table.

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
- Journalisation obligatoire, mais **jamais dans la même table** : `carbon_business_events` reçoit uniquement les actions métier réussies et committées ; les échecs de validation et refus d'autorisation vont dans `carbon_rpc_failures` (ou les journaux serveur pour les erreurs qui doivent réellement remonter une exception au client — voir §11bis ci-dessous) — correction d'une contradiction relevée après revue, cette section affirmait auparavant l'inverse (« y compris les échecs d'autorisation » dans `carbon_business_events`).
- Gestion des erreurs sans fuite d'information sensible au client (messages génériques exposés, détail complet uniquement dans les logs serveur).

**11bis. Garantie réelle (et limitée) de `carbon_rpc_failures` — précision ajoutée après revue.** Une ligne insérée dans `carbon_rpc_failures` **depuis le bloc `EXCEPTION` d'une RPC ne survit que si cette RPC capture l'erreur, insère la ligne, puis retourne normalement un résultat structuré d'échec (ex. `{success: false, reason: '...'}`) sans relancer l'exception.** Si la RPC relance l'exception vers l'appelant (`RAISE`), ou si la transaction englobante est annulée pour une autre raison, l'insertion dans `carbon_rpc_failures` est annulée avec le reste — une sous-transaction (savepoint PL/pgSQL) protège seulement contre le rollback d'un bloc imbriqué, jamais contre l'annulation de la transaction qui l'englobe. **Conséquence pour l'implémentation (migrations 02-07)** : `carbon_rpc_failures` ne doit être utilisée que pour les échecs de validation/autorisation attendus, où la RPC choisit délibérément de capturer, journaliser, puis retourner un échec structuré plutôt que de lever une exception. Pour les erreurs réellement exceptionnelles qui doivent remonter une exception au client, s'appuyer sur les journaux serveur/applicatifs Postgres, pas sur cette table.

---

## 12. `verification_sessions` — option robuste retenue : `verification_outcomes`

**Décision, tranchée plutôt que laissée ouverte** : au vu de la direction prise sur l'ensemble de cette révision (historisation immuable systématique — adhésions, liens MRV, règles de distribution, coûts de vente), la cohérence architecturale impose la même logique ici plutôt qu'une simplification MVP qui serait immédiatement en contradiction avec le reste du modèle.

**Bug de conception trouvé après revue et corrigé ici** : une version antérieure proposait que l'ancien résultat référence le nouveau via un champ `superseded_by_outcome_id` (référence **vers l'avant**) — modèle **impossible à exécuter** : l'index unique partiel exigerait que l'ancien résultat soit déjà marqué comme remplacé *avant* que le nouveau résultat (qu'il doit référencer) n'existe. Un blocage circulaire pur. Corrigé en remplaçant ce champ par le modèle officiel `status` (`'active'`/`'superseded'`) + `supersedes_outcome_id` — référence **vers l'arrière** (le nouveau résultat référence l'ancien qu'il remplace) :

```
verification_outcomes
  id                             UUID PRIMARY KEY DEFAULT gen_random_uuid()
  verification_session_id        UUID NOT NULL REFERENCES verification_sessions(id) ON DELETE RESTRICT
  status                          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','superseded'))
  supersedes_outcome_id            UUID NULL REFERENCES verification_outcomes(id) ON DELETE RESTRICT
  calculated_reduction_tco2e       NUMERIC(14,4) NOT NULL CHECK (calculated_reduction_tco2e <> 'NaN'::numeric)
  verified_reduction_tco2e         NUMERIC(14,4) NOT NULL CHECK (verified_reduction_tco2e >= 0 AND verified_reduction_tco2e <> 'NaN'::numeric)
  eligible_tco2e                   NUMERIC(14,4) NOT NULL CHECK (eligible_tco2e >= 0 AND eligible_tco2e <= verified_reduction_tco2e AND eligible_tco2e <> 'NaN'::numeric)
  verification_report_document_id  UUID REFERENCES documents(id)
  verified_by                      UUID NOT NULL REFERENCES profiles(id)
  verified_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
  adjustment_reason                TEXT NULL
  created_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
```

`supersedes_outcome_id` pointe **vers l'arrière** (le nouveau résultat référence l'ancien qu'il remplace), jamais vers l'avant — ce qui élimine la dépendance circulaire. `UNIQUE (verification_session_id) WHERE status = 'active'` — un seul résultat actif à la fois par session.

**Interdiction structurelle de `NaN`, contrat obligatoire pour la migration 05 (durcissement, quinzième revue statique de la migration 07 — même défaut de fait que celui corrigé sur `credit_issuances.quantity_tco2e`/`credit_issuance_sources.contributed_tco2e`).** `NUMERIC` accepte la valeur spéciale `NaN` indépendamment de la précision/échelle déclarée (`14,4` ici ne l'exclut pas), et PostgreSQL la traite comme **supérieure à toute valeur numérique ordinaire** pour les opérateurs de comparaison, et **égale à elle-même**. Conséquence concrète pour ce schéma précis : un simple `CHECK (verified_reduction_tco2e >= 0)` ne suffit **pas** (`'NaN'::numeric >= 0` est `TRUE`) ; et s'appuyer uniquement sur la comparaison croisée `eligible_tco2e <= verified_reduction_tco2e` ne suffit pas non plus — si les **deux** colonnes valent `NaN` simultanément, `NaN <= NaN` est également `TRUE` en PostgreSQL (contrairement à IEEE 754), donc les deux valeurs invalides se laissent mutuellement passer. Chaque colonne numérique de `verification_outcomes` doit donc porter sa **propre** exclusion explicite `<> 'NaN'::numeric`, comme reflété dans le schéma ci-dessus (`calculated_reduction_tco2e`, `verified_reduction_tco2e`, `eligible_tco2e`) — à appliquer telle quelle à l'écriture réelle de la migration 05, pas seulement documentée ici.

**Séquence corrigée de `complete_verification_session()` en cas de supersession, dans une seule transaction — révisée après la troisième revue de §15 (verrouillage et invariant bidirectionnel, migration 07 dépend de cette révision) :**
1. **`SELECT ... FOR UPDATE` sur `verification_sessions` par `id`** (pas sur le résultat actif lui-même comme le décrivait une version antérieure de ce document) — même verrou, sur le même identifiant, que celui posé par `create_credit_issuance()` (migration 07, §15 point 4) ; c'est ce partage exact qui sérialise correctement une supersession concurrente à une création d'émission, dans les deux sens.
2. Une fois le verrou obtenu, lecture du résultat actif existant de cette session (`SELECT ... FOR UPDATE` sur `verification_outcomes`, redondant avec le verrou de session mais conservé par défense en profondeur).
3. **Calcul de la capacité déjà consommée** sur l'ensemble de la chaîne de supersession de cette session (§15 point 4 : `SUM(credit_issuances.quantity_tco2e) WHERE issuance_status NOT IN ('voided','externally_rejected')`, à travers tous les `verification_outcomes` de cette session). **Invariant bidirectionnel obligatoire : si `p_eligible_tco2e < capacité déjà consommée`, la RPC rejette explicitement — la supersession échoue, l'ancien résultat reste actif, rien n'est inséré.**
4. `UPDATE verification_outcomes SET status = 'superseded' WHERE id = <ancien>` — libère l'index unique partiel.
5. `INSERT INTO verification_outcomes (..., status, supersedes_outcome_id) VALUES (..., 'active', <ancien>.id)` — peut maintenant s'insérer sans conflit, puisque l'ancien n'est plus `'active'`.

Si l'étape 3 (invariant bidirectionnel) ou l'étape 5 échoue pour une raison quelconque (contrainte violée, erreur), toute la transaction s'annule automatiquement — l'étape 4 (passage de l'ancien à `'superseded'`), si déjà exécutée, est annulée avec elle, l'ancien résultat redevient actif comme si de rien n'était. Aucun état intermédiaire incohérent ne peut être committé.

**Conséquence pour la conception de la migration 05, contrat tranché (réconcilié avec l'implémentation réelle de 07, treizième revue statique)** : `complete_verification_session()` ne peut pas être conçue indépendamment du calcul de capacité consommée du §15 point 4, alors même que la table `credit_issuances` n'existe pas encore au moment où 05 serait appliquée seule (07 dépend de 05, jamais l'inverse). **Contrat retenu, définitif — un seul point d'extension, jamais la RPC elle-même** : la migration 05 crée un **helper dédié** `carbon_capacity_consumed_for_session(p_verification_session_id UUID) RETURNS NUMERIC`, sous forme de **stub** qui retourne inconditionnellement `0` (aucune émission ne peut exister avant que 07 soit appliquée), et `complete_verification_session()` appelle ce helper plutôt que d'inliner le calcul. La migration 07 fait ensuite un `CREATE OR REPLACE FUNCTION public.carbon_capacity_consumed_for_session(...)` (même signature) pour y ajouter le calcul réel une fois `credit_issuances`/`credit_issuance_sources` créées — **`complete_verification_session()` elle-même n'est jamais touchée par la migration 07**, ni sa signature ni son corps. L'ancienne alternative envisagée ici (une garde `to_regclass('public.credit_issuances') IS NULL` inlinée directement dans `complete_verification_session()`, ou une variante où 07 `CREATE OR REPLACE` la RPC elle-même) est **abandonnée** : elle aurait dupliqué le point d'autorisation/calcul et forcé 07 à toucher une RPC de 05 qu'elle n'a par ailleurs aucune raison de modifier.

**Immuable après création, sauf `status`** (trigger) — `status` ne peut transitionner que de `'active'` vers `'superseded'`, jamais l'inverse, jamais une deuxième fois (`'superseded'` est terminal).

`verification_sessions` garde uniquement : `project_id`, `status`, `reporting_period_start`/`end`, `verifier_user_id`, `verifier_org`/`verifier_contact` — le **résultat** de la vérification vit entièrement dans `verification_outcomes`.

**`credit_issuances.verification_session_id` devient `credit_issuances.verification_outcome_id`** (référence au résultat précis utilisé, pas seulement à la session — cohérent avec le fait qu'une session peut avoir plusieurs résultats successifs si une correction a eu lieu).

---

## 13. METALTRACE, vendeur/opérateur carbone central — `credit_sales` sans `aggregator_id` structurant (décision du 14 juillet 2026, après gel de la démo CCF)

**Contexte du changement.** L'application est née comme un outil de traçabilité et de crédit carbone, vérifié par un spécialiste externe disposant de sa propre plateforme vérificateur, avant l'ajout des fonctionnalités réseau (CCF, puis regroupements/agrégateurs). En reconsidérant le positionnement, une question est restée non tranchée jusqu'ici dans ce document : **qui est le vendeur juridique des crédits — l'organisation, le regroupement, ou la plateforme elle-même ?** Le schéma actuellement déployé (`20260710999100_reapply_mrv_and_aggregators.sql`, antérieur à ce chantier v4) répond implicitement « le regroupement » : `credit_sales.aggregator_id UUID NOT NULL REFERENCES aggregators(id)`. Cette décision corrige explicitement ce choix implicite avant d'écrire les migrations 05-07.

**Décision : METALTRACE (l'entité juridique qui exploite la plateforme) est le vendeur/opérateur carbone central — jamais un `aggregator` individuellement.** Les `aggregators` demeurent des **regroupements opérationnels et économiques** (portefeuilles de traçabilité et de répartition), **pas des vendeurs juridiques autonomes**.

```
METALTRACE = vendeur / opérateur carbone central
    │
    └── credit_sales
          seller_organization_id = entité juridique METALTRACE
          aucun aggregator_id structurant obligatoire
                │
                └── credit_sale_lots
                      │
                      ├── credit_lot A → aggregator X
                      ├── credit_lot B → aggregator Y
                      └── credit_lot C → aggregator Z
```

**Conséquences précises, qui prévalent sur toute mention contraire ailleurs dans ce document :**

1. **`aggregator_memberships` (migration 02, déjà appliquée en production, 56/56) reste entièrement valide.** Aucune reprise de cette migration n'est requise — elle modélise l'appartenance organisation↔regroupement, question orthogonale à celle du vendeur juridique.

2. **`credit_sales.aggregator_id` cesse d'être la relation structurante du vendeur.** Une vente METALTRACE doit pouvoir contenir des lots provenant de **plusieurs** regroupements différents, via `credit_sale_lots` — pas une vente = un regroupement.

3. **`credit_sales` gagne une identité explicite de vendeur/opérateur** : `seller_organization_id UUID NOT NULL REFERENCES organizations(id)`, référençant l'organisation représentant l'entité juridique METALTRACE (une organisation créée à cet effet, comme n'importe quelle autre organisation du système — pas un type spécial).

4. **Invariant retenu pour le MVP** (précise et referme la portée de §7 ci-dessus, ne le contredit pas — §7 continue de s'appliquer tel quel à `credit_issuances`/`credit_lots`) : un `credit_lot` appartient à **un seul** `aggregator` (`credit_lots.aggregator_id`, figé, §7). Une `credit_sale`, en revanche, **peut** contenir plusieurs lots de plusieurs `aggregator` distincts.

5. **`credit_issuances`/`credit_issuance_sources` respectent la même règle** — une émission reste rattachée à un seul `aggregator_id` (§7, inchangé : sources validées par participation + adhésion active au moment de l'émission, `aggregator_id` déterminé par l'aggregator commun aux sources, jamais fourni librement). Pour le MVP, **une émission reste homogène par regroupement** (toutes ses sources appartiennent au même `aggregator`) — mélanger plusieurs regroupements au sein d'une même émission est explicitement hors périmètre, sauf justification métier contraire documentée séparément.

6. **`credit_sale_allocations` continue de redescendre jusqu'à l'organisation contributrice** (`organization_id`, déjà le cas), indépendamment de son regroupement d'origine — aucun changement de logique, seule la couche vendeur (point 2-3) change.

7. **Autorisation contractuelle explicite et historisée — `carbon_commercialization_mandates`, distincte de l'adhésion.** Décision précisée le 14 juillet 2026, après une première proposition corrigée sur cinq points par l'utilisateur :

   - **Objet distinct de `aggregator_memberships`** : une organisation peut être membre d'un regroupement sans avoir encore autorisé METALTRACE à commercialiser ses crédits. La révocation du mandat ne met pas fin à l'adhésion, et réciproquement.
   - **Rattaché à une adhésion précise (`aggregator_membership_id`), pas au couple `(organization_id, aggregator_id)`** — pour qu'un ancien mandat ne puisse jamais redevenir accidentellement valide après un départ puis une nouvelle adhésion au même regroupement (nouvelle ligne `aggregator_memberships` = nouvel identifiant = aucun mandat existant ne s'y applique tant qu'un nouveau n'est pas explicitement accordé).
   - **Bénéficiaire explicite** : `operator_organization_id`, l'entité juridique METALTRACE désignée — pas l'`aggregator` lui-même (le mandat est donné À METALTRACE, PAR l'organisation, DANS LE CONTEXTE d'une adhésion à un regroupement).
   - **`scope` fermé et validé**, jamais du texte libre : `TEXT[]` avec `CHECK` contre un catalogue fixe d'actions précises, immuable après création (toute modification exige révocation + nouveau mandat, jamais un `UPDATE` du scope).

   ```
   carbon_commercialization_mandates
     id                            UUID PRIMARY KEY DEFAULT gen_random_uuid()
     aggregator_membership_id      UUID NOT NULL REFERENCES aggregator_memberships(id) ON DELETE RESTRICT
     operator_organization_id      UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT
     scope                         TEXT[] NOT NULL CHECK (
                                      array_length(scope, 1) > 0
                                      AND scope <@ ARRAY[
                                        'aggregate_reductions','submit_for_verification','request_issuance',
                                        'administer_credits','sell_credits','collect_sale_proceeds',
                                        'deduct_approved_costs','distribute_net_proceeds'
                                      ]::TEXT[]
                                    )
     granted_by                    UUID NOT NULL REFERENCES profiles(id)
     granted_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
     mandate_document_id           UUID NULL REFERENCES documents(id)
     revoked_at                    TIMESTAMPTZ NULL
     revoked_by                    UUID NULL REFERENCES profiles(id)
     revoke_reason                 TEXT NULL
     created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
   ```
   `UNIQUE (aggregator_membership_id) WHERE revoked_at IS NULL` — un seul mandat actif par adhésion précise. Trigger de garde n'autorisant que la transition `revoked_at` NULL → valeur (`revoked_by`/`revoke_reason` renseignés au même moment) — toute autre colonne, y compris `scope`, immuable après création ; `DELETE` interdit (réutilise `carbon_reject_update_delete()`), même patron que `aggregator_memberships` (migration 02). `operator_organization_id` doit satisfaire la règle fonctionnelle `is_platform_operator(operator_organization_id)` (voir point 8/point 9 — signature valide indépendamment de l'implémentation réelle sur `platform_operators`, pas un booléen `organizations.is_platform_operator`, réconcilié seizième revue statique) — validé par trigger, pas seulement par convention applicative.

8. **Corrections de schéma complémentaires, actées le 14 juillet 2026 avant toute migration :**

   - `credit_sales.total_tco2e` : `NUMERIC(14,4)`, pas `FLOAT8` — cohérence avec la précision déjà retenue partout ailleurs dans ce domaine (`credit_issuances`, `credit_issuance_sources`, `verification_outcomes`), jamais de type flottant sur une quantité auditable.
   - `credit_sale_allocations` : contrainte `UNIQUE (credit_sale_id, organization_id, aggregator_id, allocation_type)` (ajout de `aggregator_id`, colonne déjà requise par le point 6 ci-dessous) — remplace la contrainte à 3 colonnes des « Points secondaires » ci-dessous, désormais obsolète.
   - `credit_sale_allocations.allocated_tco2e` devient conditionnel selon `allocation_type` plutôt que systématiquement obligatoire :
     ```
     CHECK (
       (allocation_type IN ('carbon_revenue','reserve') AND allocated_tco2e IS NOT NULL AND allocated_tco2e > 0)
       OR
       (allocation_type IN ('expense_reimbursement','bonus','adjustment') AND allocated_tco2e IS NULL)
     )
     ```
     Une composante purement financière (remboursement de frais, bonus, ajustement) n'a pas de quantité de crédit associée — la forcer à une valeur factice serait trompeur pour l'audit.
   - `credit_issuance_sources` gagne deux colonnes pour figer la provenance historique exacte, jamais recalculée :
     ```
     aggregator_membership_id      UUID NOT NULL REFERENCES aggregator_memberships(id) ON DELETE RESTRICT
     commercialization_mandate_id  UUID NOT NULL REFERENCES carbon_commercialization_mandates(id) ON DELETE RESTRICT
     ```
     `create_credit_issuance()` valide que `aggregator_membership_id` était active au moment précis de l'émission (mécanique déjà décrite au point 5/§7) **et** que `commercialization_mandate_id` référence un mandat actif (`revoked_at IS NULL`) rattaché à cette **même** `aggregator_membership_id` — sans mandat actif rattaché à l'adhésion précise, aucune source ne peut être acceptée dans une émission.
   - `credit_issuances` gagne `registry_issued_at TIMESTAMPTZ NULL`, renseignée exactement au moment où `issuance_status` passe à `'issued'` : `CHECK (issuance_status NOT IN ('issued','externally_cancelled') OR registry_issued_at IS NOT NULL)` (reste renseignée après un passage ultérieur à `'externally_cancelled'` — fait historique, jamais effacé).
   - **Validation que `credit_sales.seller_organization_id` correspond bien à l'entité juridique METALTRACE désignée** — spécification formelle complète en point 9 ci-dessous (précisée le 14 juillet 2026, après revue : ne doit reposer sur aucune donnée de session, uniquement sur une donnée persistante gouvernée).

9. **`is_platform_operator(p_organization_id UUID)` — spécification formelle.**

   **⚠️ SOUS-MODÈLE ENTIER OBSOLÈTE — ESQUISSE HISTORIQUE, REMPLACÉE PAR LA MIGRATION 06 RÉELLEMENT APPLIQUÉE (marqué explicitement, seizième revue statique).** Tout ce point 9, y compris le bloc de code ci-dessous (colonne `organizations.is_platform_operator`, index `idx_one_platform_operator`, corps de `is_platform_operator()` basé sur cette colonne, gouvernance par `designate_platform_operator()` décrite ici), décrit la **proposition initiale**, écrite avant la rédaction réelle de la migration 06. La migration 06 réellement appliquée a retenu un modèle différent : `platform_operators`, table d'historique séparée (une ligne par désignation/révocation, jamais un booléen sur `organizations`) — voir la réconciliation déjà actée en §14 point 4/point 5 et en §15 point 0.1. La **signature** de `is_platform_operator(p_organization_id UUID) RETURNS BOOLEAN` reste correcte et inchangée (`EXISTS`-based, jamais `NULL`) ; seule son **implémentation interne** (le bloc de code ci-dessous) est remplacée. **Ne jamais reprendre le bloc de code ci-dessous tel quel dans une migration future (09 ou autre)** — il est conservé uniquement pour la valeur historique de la réflexion qui a mené au modèle réel.

   Cette fonction répond à une question sur une **organisation**, jamais sur l'utilisateur courant : *« cette `organization_id` est-elle l'entité juridique autorisée à agir comme opérateur/vendeur central METALTRACE ? »* — à ne jamais confondre avec « l'appelant est-il administrateur de la plateforme » (`is_platform_superadmin()`, qui répond à une question différente sur l'utilisateur). Repose exclusivement sur une donnée persistante et gouvernée en base, jamais sur `raw_user_meta_data` ni sur le rôle JWT de l'appelant.

   ```
   organizations
     is_platform_operator BOOLEAN NOT NULL DEFAULT false

   CREATE UNIQUE INDEX idx_one_platform_operator
     ON organizations ((true)) WHERE is_platform_operator = true
     -- au plus une organisation désignée à la fois, même patron que idx_one_active_primary_admin

   CREATE OR REPLACE FUNCTION public.is_platform_operator(p_organization_id UUID)
   RETURNS BOOLEAN
   LANGUAGE sql
   STABLE
   SECURITY DEFINER
   SET search_path = public, pg_temp
   AS $$
     SELECT EXISTS (
       SELECT 1 FROM public.organizations
       WHERE id = p_organization_id AND is_platform_operator = true
     )
   $$;
   ```
   Construite avec `EXISTS(...)`, donc **jamais `NULL`** — toujours strictement `true`/`false`, par construction plutôt que par convention. Rappel du bug corrigé en migration 03 (`join_aggregator()`/`create_aggregator_with_primary_admin()`, `is_platform_superadmin()` pouvant renvoyer `NULL`) : toute fonction destinée à un garde `IF NOT (...)` doit être structurellement non-`NULL`, pas seulement `NULL`-safe par un `COALESCE` ajouté après coup. `is_platform_operator()` respecte cette exigence dès sa conception.

   **Gouvernance de `is_platform_operator`** : jamais un `UPDATE` direct exposé à un rôle applicatif. Nouvelle RPC réservée à `is_platform_superadmin()` :
   ```
   designate_platform_operator(p_organization_id UUID)
   ```
   Dans une seule transaction : vérifie que l'organisation existe, retire `is_platform_operator = true` de toute organisation qui le portait actuellement (0 ou 1, garanti par l'index unique), puis le pose sur `p_organization_id` — jamais un état intermédiaire à zéro opérateur désigné une fois le premier bootstrap effectué. Journalise un événement `carbon_business_events` (`platform_operator_designated`).

   **— fin du sous-modèle obsolète —** La migration 06 réelle a conservé l'esprit de cette gouvernance (une seule transaction, désignation exclusive, événement journalisé) mais l'a implémentée sur `platform_operators` (table d'historique) plutôt que sur un booléen `organizations.is_platform_operator`. Les invariants ci-dessous, en revanche, restent valides tels quels : ils portent sur la fonction `is_platform_operator(...)` par sa **signature**, pas sur son implémentation.

   **Trois invariants à faire respecter avant migration 07 (précisés le 14 juillet 2026) :**
   ```
   carbon_commercialization_mandates.operator_organization_id
       → doit satisfaire is_platform_operator(operator_organization_id)
       → figé définitivement à la création du mandat (déjà couvert par le trigger de garde du point 7 —
         aucune colonne hors revoked_at/revoked_by/revoke_reason n'est modifiable après INSERT)

   credit_sales.seller_organization_id
       → doit satisfaire is_platform_operator(seller_organization_id)
       → figé AU PLUS TARD à la confirmation de la vente (status → 'confirmed') : modifiable tant que
         status = 'draft' (revalidé à chaque changement), puis verrouillé par le même trigger
         d'immutabilité post-confirmation que le reste de credit_sales (§6) — jamais un vendeur
         historique qui change juridiquement par simple modification d'une relation courante

   credit_sales.seller_organization_id
       → doit correspondre à l'opérateur des mandats des sources/lots inclus dans la vente : pour
         chaque credit_sale_lots de cette vente, en remontant credit_lot → credit_issuance →
         credit_issuance_sources → commercialization_mandate_id → operator_organization_id, cette
         valeur doit être identique à credit_sales.seller_organization_id — vérifié à l'ajout de
         chaque credit_sale_lots (retour immédiat) ET réaffirmé par confirm_credit_sale() comme
         verrou final avant gel (défense en profondeur, même principe qu'ailleurs dans ce document,
         §4/§7bis)
   ```

**Justification produit** (inchangée depuis la décision initiale, reformulée ici pour mémoire) : c'est la mutualisation qui donne sa valeur à METALTRACE, en particulier pour les PME et petits recycleurs qui n'auraient pas, seuls, un accès économiquement viable au marché carbone — ils n'ont pas à ouvrir leur propre compte de registre, gérer eux-mêmes un vérificateur, négocier individuellement leurs ventes, gérer des lots, ou gérer une répartition financière.

**Impact sur le plan des migrations — passage historique, obsolète (marqué dix-septième revue statique).** Ce paragraphe, écrit avant le gel de numérotation du 14 juillet 2026, employait encore l'ancienne numérotation (`05` pour les émissions, `07` pour la vente) et le modèle booléen abandonné `organizations.is_platform_operator`. Le plan réel, figé et détaillé en §14 ci-dessous, est : `07_carbon_issuances.sql` (émissions, `credit_issuance_sources`) et `09_carbon_sales_financial_model.sql` (`credit_sales.seller_organization_id`, sans `credit_sales.aggregator_id`, `carbon_commercialization_mandates` déjà porté par la migration 06 appliquée). Se reporter uniquement au tableau §14 pour le contenu par fichier — ce paragraphe est conservé pour mémoire, ne doit plus être suivi.

**Ce document (`Tranche0-Carbone-Architecture.md`) reste la source canonique** ; `MVP-Carbone-Regroupements.md` (portée par tranches commercialisables) référence cette même décision sans la dupliquer différemment.

---

## 14. Plan de migration détaillé — volet commercial (§13 appliqué) — PLAN SEUL, aucun SQL exécutable ici

**Collision de numérotation — FIGÉE le 14 juillet 2026, définitive.** Le tableau « Plan des migrations proposées » plus haut réservait `03` à `03_carbon_ccf_mrv_project_links.sql` (non écrite) — mais `03` a depuis été utilisé, définitivement, pour le correctif de sécurité `03_fix_null_bypass_authorization.sql` (appliqué en production, voir ADR-MVP.md §13). `03` reste ce correctif pour toujours ; la suite est renumérotée 04-09 ci-dessous, verrouillée avant toute rédaction :

| # (révisé) | Fichier | Contenu |
|---|---|---|
| 04 | `04_carbon_ccf_mrv_project_links.sql` | (anciennement 03, inchangé) `ccf_mrv_project_links`. |
| 05 | `05_carbon_verification_outcomes.sql` | (anciennement 04, inchangé) `verification_outcomes`, `is_assigned_verifier()`. |
| 06 | `06_carbon_operator_and_mandates.sql` | **Nouvelle migration, pas dans le plan original.** Réellement appliquée (18 juillet 2026) avec `platform_operators` — table d'historique séparée (une ligne par désignation/révocation), **pas** un booléen `organizations.is_platform_operator` comme l'esquissait la version initiale de ce plan — plus `is_platform_operator()`, `designate_platform_operator()`, `carbon_commercialization_mandates` (réconcilié avec §15 point 0.1, quatorzième revue statique). Isolée dans son propre fichier plutôt que fusionnée avec les émissions (07) : ces objets sont un préalable transverse, testables indépendamment, et réutilisés par plusieurs migrations suivantes. |
| 07 | `07_carbon_issuances.sql` | (anciennement 05) `credit_issuances`, `credit_issuance_sources` (avec `aggregator_membership_id`/`commercialization_mandate_id`, point 8). Rédigée, en revue statique (§15) — contrat à 7 RPC : `create_credit_issuance()`, `mark_credit_issuance_eligible()`, `submit_credit_issuance()`, `record_registry_issuance()`, `record_externally_rejected()`, `void_credit_issuance()`, `record_external_cancellation()` (matrice complète §15 point c, réconcilié quatorzième revue statique). Dépend de 04, 05 et 06. |
| 08 | `08_carbon_lots_commercial_cycle.sql` | (anciennement 06) `credit_lots` modifiée (`commercial_status`, `aggregator_id` ajouté), `issue_credit_lot()`, `void_credit_lot()`. Dépend de 07. |
| 09 | `09_carbon_sales_financial_model.sql` | (anciennement 07) `credit_sales` modifiée (`seller_organization_id`, sans `aggregator_id`), `credit_sale_lots`, `credit_sale_costs`, `credit_sale_adjustments`, `distribution_rules`, `credit_sale_allocations` modifiée (`aggregator_id`, `UNIQUE` à 4 colonnes, `allocated_tco2e` conditionnel), `confirm_credit_sale()`. Dépend de 06 et 08. |

**1. Tables existantes à modifier**

- `credit_lots` : ajoute `credit_issuance_id` (FK, `RESTRICT`), `aggregator_id` (FK, `RESTRICT`, figé), renomme `status` → `commercial_status` avec le nouveau catalogue à 6 valeurs (§1). Table actuellement vide en production (à reconfirmer en direct avant migration 08, pas supposé depuis l'audit précédent) — aucune donnée à transformer, seulement la forme.
- `credit_sales` : supprime `aggregator_id`/sa FK (voir point 3 ci-dessous), ajoute `seller_organization_id` (FK `organizations`, `RESTRICT`, validée par `is_platform_operator()`), convertit `total_tco2e` en `NUMERIC(14,4)`, ajoute `gross_amount`/`net_distributable_amount` (§6, déjà prévu), `status` gagne le verrou d'immutabilité post-`'confirmed'` étendu à `seller_organization_id`.
- `credit_sale_allocations` : ajoute `aggregator_id` (FK `RESTRICT`), remplace `UNIQUE (credit_sale_id, organization_id, allocation_type)` par `UNIQUE (credit_sale_id, organization_id, aggregator_id, allocation_type)`, rend `allocated_tco2e` conditionnel (point 8), ajoute `allocation_type`/`distribution_rule_id`/`rule_snapshot` s'ils ne sont pas déjà portés par une migration antérieure à ce chantier v4.
- `credit_sale_lots` : pas de changement de colonnes, mais gagne le trigger de validation d'opérateur (point 9, troisième invariant) et le trigger d'interdiction pré-émission (correction 2, déjà prévu).
- `organizations` : **obsolète — ne pas appliquer.** Le §13 point 9 esquissait l'ajout d'une colonne booléenne `is_platform_operator` sur `organizations` ; la migration 06 réellement écrite et appliquée a retenu un modèle différent, `platform_operators` (table d'historique séparée, une ligne par désignation/révocation), sans toucher `organizations` (réconcilié §15 point 0.1 et §14 point 4 ci-dessous, quinzième revue statique). Aucune migration future ne doit ajouter cette colonne.

**2. Nouvelles tables**

`credit_issuances`, `credit_issuance_sources`, `carbon_commercialization_mandates` — spécifications complètes déjà figées en §13 points 7-8 et §1/§2/§7/§12, aucune reprise nécessaire ici. Aucune n'existe aujourd'hui en production (confirmé par l'audit initial, 0 ligne sur les 9 tables Agrégateurs) — création pure, aucune donnée préexistante à réconcilier.

**3. Traitement de `credit_sales.aggregator_id` existant**

Colonne actuellement `NOT NULL REFERENCES aggregators(id)` dans le schéma déployé (`20260710999100_reapply_mrv_and_aggregators.sql`). **Avant d'écrire la migration 09** : requête de vérification en direct (`SELECT count(*) FROM credit_sales`) — l'audit initial de ce chantier l'a trouvée vide, mais conformément à la discipline établie depuis INC-DATA-01, ne jamais réutiliser un audit antérieur sans reconfirmation immédiatement avant l'écriture de la migration qui en dépend. Si confirmée vide : `ALTER TABLE credit_sales DROP COLUMN aggregator_id` direct, aucun backfill. Si des lignes existaient contre toute attente : la migration devrait être bloquée et une stratégie de reprise de données distincte serait nécessaire avant de continuer — scénario non couvert par ce plan, à traiter séparément si rencontré.

**4. Invariants et triggers (consolidé, tous déjà spécifiés individuellement plus haut)**

- `credit_issuance_sources` : contrainte différée `SUM(contributed_tco2e) = credit_issuances.quantity_tco2e` (§4) ; validation amont participation + adhésion active au moment de l'émission + mandat actif rattaché à cette même adhésion (§7, point 8).
- `credit_issuances` : émission homogène par `aggregator_id` (un seul aggregator commun aux sources, point 5) ; `registry_issued_at` obligatoire dès `'issued'`/`'externally_cancelled'` (point 8) ; garde contre progression sans sources cohérentes (§1).
- `credit_lots` : `commercial_status` ne quitte `'unavailable'` que si l'émission parente est `'issued'` (§1) ; `voided` uniquement en conséquence d'une annulation externe de l'émission (§2).
- `credit_sale_lots` : lot référençable seulement si émission `'issued'` (correction 2) ; validation opérateur (point 9, troisième invariant) — comparaison immédiate à l'ajout de chaque ligne.
- `credit_sales` : `seller_organization_id` doit satisfaire `is_platform_operator()` à l'écriture ; verrouillage complet (y compris `seller_organization_id`) au passage à `'confirmed'` (§6 étendu).
- `carbon_commercialization_mandates` : `operator_organization_id` doit satisfaire `is_platform_operator()` à l'écriture, immuable après création ; `scope` fermé et immuable ; une seule ligne active par `aggregator_membership_id`.
- `organizations` : réellement appliquée sans colonne `is_platform_operator` — l'unicité « au plus un opérateur actif à la fois » est portée par `platform_operators` (index unique partiel sur `revoked_at IS NULL`), pas par `organizations` (réconcilié avec §15 point 0.1, quatorzième revue statique).

**5. RPC (par migration)**

- 06 : `designate_platform_operator(p_organization_id UUID)` — réservée `is_platform_superadmin()`.
- 06 : `grant_commercialization_mandate(p_aggregator_membership_id UUID, p_operator_organization_id UUID, p_scope TEXT[], p_mandate_document_id UUID DEFAULT NULL)` — **autorisation tranchée, plus un point ouvert (décision D9 de la migration 06 réellement appliquée, réconcilié seizième revue statique)** : réservée **strictement** à `is_org_admin()` de l'organisation titulaire de l'adhésion, **sans dérogation super-admin** — l'octroi d'un mandat est un acte de volonté de l'organisation elle-même (consentement à ce que METALTRACE commercialise en son nom), qu'un super-admin ne doit jamais pouvoir créer au nom d'un membre sans preuve. `revoke_commercialization_mandate(p_mandate_id UUID, p_reason TEXT)` **conserve**, à l'inverse, la dérogation super-admin (intervention opérationnelle légitime, ex. réponse à un abus, sans dépendre du consentement en temps réel de l'organisation).
- 07 (contrat à 7 RPC, réconcilié avec §15 point c, quatorzième revue statique) : `create_credit_issuance(p_verification_outcome_id UUID, p_sources JSONB)`, `mark_credit_issuance_eligible(p_credit_issuance_id UUID)`, `submit_credit_issuance(p_credit_issuance_id UUID, p_registry_name TEXT)`, `record_registry_issuance(p_credit_issuance_id UUID, p_registry_reference TEXT, p_registry_issued_at TIMESTAMPTZ)`, `record_externally_rejected(p_credit_issuance_id UUID, p_date DATE, p_reference TEXT, p_document_id UUID)`, `void_credit_issuance(p_credit_issuance_id UUID, p_reason TEXT)`, `record_external_cancellation(p_credit_issuance_id UUID, p_date DATE, p_reference TEXT, p_document_id UUID)`.
- 08 : `issue_credit_lot(p_credit_issuance_id UUID, p_quantity_tco2e NUMERIC, p_vintage_year INT)`, `void_credit_lot(p_credit_lot_id UUID, p_reason TEXT)`.
- 09 : `confirm_credit_sale(p_credit_sale_id UUID)` (calcule `net_distributable_amount`, verrouille, vérifie le troisième invariant du point 9 comme verrou final), RPC de saisie de vente/lots/coûts/allocations (signatures à détailler au moment de l'écriture de cette migration précise, hors périmètre de ce plan).

Chaque RPC respecte la checklist de durcissement déjà actée (§11) — `SET search_path`, `auth.uid()` vérifié en première ligne, validation de chaque identifiant, `REVOKE`/`GRANT` explicites, aucune confiance dans un paramètre `jsonb` brut.

**6. RLS**

Nouvelle fonction de portée à envisager : `is_mandate_operator(p_credit_sale_id UUID)` ou équivalent, pour les policies `SELECT` de `credit_sales`/`credit_issuances`/`credit_lots` — accès a minima : `is_platform_operator()` de l'organisation appelante (si elle représente METALTRACE), `is_platform_superadmin()`, et l'organisation source (via `credit_issuance_sources.organization_id`) pour la visibilité de ses propres contributions. Aucune policy d'écriture directe sur aucune des tables de ce chantier — écriture exclusivement par les RPC `SECURITY DEFINER` listées ci-dessus (même principe que migration 02, §6 de ce document).

**7. Stratégie de migration des données existantes**

Aucune donnée réelle à migrer — toutes les tables concernées (`credit_lots`, `credit_sales`, `credit_sale_lots`, `credit_sale_allocations`) sont vides en production (à reconfirmer en direct immédiatement avant chaque migration, jamais supposé depuis un audit antérieur, cf. point 3). Ce chantier est donc une suite de `CREATE TABLE`/`ALTER TABLE` sans backfill — contrairement à la migration 02 (`aggregator_memberships`), qui avait dû réconcilier des données réelles depuis `organizations.aggregator_id`.

**8. Protocole de validation (par migration, même patron que 01/02)**

Un fichier de test séparé sous `supabase/carbon_migrations_proposed/tests/`, jamais mélangé au DDL, structuré en assertions structurelles (Partie A — existence des tables/colonnes/contraintes/index, signatures de fonctions, privilèges réels via `has_table_privilege`/`has_function_privilege`) et comportementales (Partie B — chemins de succès et de rejet pour chaque invariant du point 4 ci-dessus, avec simulation de contexte `authenticated` réel via `request.jwt.claims`, jamais testé uniquement sous le rôle `postgres` qui contourne RLS). Cas spécifiques à couvrir en priorité pour ce volet, au-delà du patron habituel : `is_platform_operator()` renvoie bien `false` (jamais `NULL`) pour une organisation quelconque ; `designate_platform_operator()` ne laisse jamais deux organisations désignées simultanément (test de transition, pas seulement de l'état initial) ; une vente mélangeant des lots de deux `aggregator_id` différents est acceptée si l'opérateur concorde, rejetée si un des lots provient d'un mandat à un opérateur différent (troisième invariant du point 9) ; un mandat révoqué puis une nouvelle adhésion au même regroupement ne permet pas de réutiliser l'ancien mandat.

**Prochaine étape (obsolète, conservée pour l'historique) :** cette ligne recommandait de rédiger `06_carbon_operator_and_mandates.sql` en premier — fait, appliqué avec succès le 18 juillet 2026 (62/62, voir ADR-MVP.md §14). L'étape suivante réelle, au moment de la rédaction du §15 ci-dessous, est la conception détaillée de la migration 07 (`credit_issuances`/`credit_issuance_sources`), qui dépend structurellement des migrations 04 et 05 (non encore rédigées) pour la validation de participation projet et la référence à `verification_outcomes`.

---

## 15. Conception détaillée — migration 07 (`credit_issuances` + `credit_issuance_sources`), réconciliée avec §13/§14 — PLAN SEUL, aucun SQL exécutable ici

**Statut (actualisé, quinzième revue statique) : conception approuvée, `07_carbon_issuances.sql` et son fichier de tests compagnon sont rédigés depuis la quatrième revue statique et en sont désormais à la quinzième — non exécutés, non intégrés aux migrations appliquées. Ce paragraphe d'origine (« ne pas rédiger avant approbation explicite ») ne reflète plus l'état réel ; voir le statut détaillé en fin de section (point c) plus bas et le statut global en tête de document.**

**Note de réconciliation, demandée explicitement avant toute rédaction.** Deux points où le §13 (rédigé avant l'écriture réelle de la migration 06) diverge de ce qui a été effectivement implémenté et appliqué :

1. **`is_platform_operator(uuid)` ne repose plus sur une colonne booléenne `organizations.is_platform_operator`** comme l'esquissait le §13 point 9 — la migration 06 réellement appliquée utilise une table d'historique séparée, `platform_operators` (une ligne par désignation/révocation, jamais un simple booléen — décision D1 du fichier de migration, documentée dans ADR-MVP.md §14). La **signature** de la fonction est inchangée (`is_platform_operator(p_organization_id UUID) RETURNS BOOLEAN`, `EXISTS`-based, jamais `NULL`), donc tous les invariants du §13 point 9 qui s'appuient sur `is_platform_operator(...)` restent valides tels quels — seule son implémentation interne a changé. Aucune référence à `organizations.is_platform_operator` (colonne) ne doit apparaître dans la migration 07 ou ses invariants.
2. **`carbon_commercialization_mandates` porte deux colonnes de plus que l'esquisse du §13 point 7** : `organization_id` et `aggregator_id`, dénormalisées mais dérivées de `aggregator_membership_id` (jamais acceptées comme paramètres séparés dans `grant_commercialization_mandate()`) — décision D6 de la migration 06 réellement appliquée. La conception ci-dessous s'appuie sur le schéma réel à 12 colonnes tel qu'appliqué, pas sur l'esquisse à 10 colonnes du §13.

Tout le reste du §13 (catalogue `scope` à 8 valeurs, `UNIQUE (aggregator_membership_id) WHERE revoked_at IS NULL`, immutabilité, `operator_organization_id` figé à la création) correspond exactement à ce qui est appliqué en production — aucune autre divergence trouvée.

### 1. `credit_issuances` — colonnes exactes

**Révisé le 18 juillet 2026, après revue.** `issued_quantity_tco2e` renommée `quantity_tco2e` (décision 5 de la revue) — la quantité existe et est figée dès `'internal'`, avant toute émission officielle ; le nom antérieur suggérait à tort qu'elle n'existait qu'à partir de `'issued'`.

```
credit_issuances
  id                             UUID PRIMARY KEY DEFAULT gen_random_uuid()
  verification_outcome_id        UUID NOT NULL REFERENCES verification_outcomes(id) ON DELETE RESTRICT
  aggregator_id                  UUID NOT NULL REFERENCES aggregators(id) ON DELETE RESTRICT
  operator_organization_id       UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT
  quantity_tco2e                 NUMERIC(14,4) NOT NULL CHECK (quantity_tco2e > 0 AND quantity_tco2e <> 'NaN'::numeric)
  issuance_status                TEXT NOT NULL DEFAULT 'internal'
                                    CHECK (issuance_status IN ('internal','eligible','submitted','issued','externally_cancelled','externally_rejected','voided'))
  registry_name                  TEXT NULL
  registry_reference             TEXT NULL
  registry_issued_at             TIMESTAMPTZ NULL
  external_cancellation_date        DATE NULL
  external_cancellation_reference   TEXT NULL
  external_cancellation_document_id UUID NULL REFERENCES documents(id) ON DELETE RESTRICT
  external_rejection_date           DATE NULL
  external_rejection_reference      TEXT NULL
  external_rejection_document_id    UUID NULL REFERENCES documents(id) ON DELETE RESTRICT
  void_reason                    TEXT NULL
  created_by                     UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
```

**`created_at` — `DEFAULT clock_timestamp()`, pas `now()` (durcissement, seizième revue statique, mécanisme précisé dix-septième revue statique).** `now()` reste figée à l'heure de **début de la transaction**, alors que les contrôles temporels d'adhésion/mandat évaluent l'activité avec `clock_timestamp()` (heure réelle du contrôle) — dans une transaction longue, `now()` pourrait dater l'émission avant même que l'autorité l'ayant permise ne soit devenue valide, même famille d'incohérence temporelle que celle déjà corrigée en migration 06 (D15). Ce `DEFAULT` est un filet pour un `INSERT` direct hors RPC, mais n'est **pas** le mécanisme qui fait réellement autorité : une première version (seizième revue) faisait capturer `v_created_at := clock_timestamp()` **une seule fois, tôt**, dans `create_credit_issuance()`, avant les verrous et les contrôles temporels des adhésions/mandats — bug corrigé dix-septième revue statique, cette capture précoce pouvant précéder l'activation réelle d'une adhésion validée pendant une attente de verrou. Le mécanisme réel, actuel : le trigger `BEFORE INSERT` sur `credit_issuances` (`carbon_credit_issuances_before_insert()`) fixe lui-même, inconditionnellement, `NEW.created_at := clock_timestamp()` **au moment de l'INSERT**, structurellement après tous les verrous/contrôles séquentiels qui le précèdent dans `create_credit_issuance()` ; la RPC récupère cette valeur par `RETURNING id, created_at` et la transmet à chaque source, mais le trigger `BEFORE INSERT` sur `credit_issuance_sources` (`carbon_validate_credit_issuance_source()`) **force** de toute façon `NEW.created_at` à la valeur exacte du parent (lue en base, pas recalculée), quelle que soit la valeur fournie à l'INSERT — élimine toute dérive par construction, y compris pour un `INSERT` privilégié direct hors RPC. Ce même trigger source valide aussi l'activité de l'adhésion et l'antériorité du mandat (`granted_at`) relativement à cet instant du parent, jamais un `clock_timestamp()` propre à l'insertion de la ligne source.

`registry_name`/`registry_reference` sont des colonnes **nouvelles**, absentes du §13 point 8 (qui ne fixait que `registry_issued_at`) — nécessaires pour identifier concrètement quel registre externe et quelle référence d'émission, sinon `registry_issued_at` seul ne documente qu'une date sans preuve d'identité du registre. `void_reason` est également nouvelle, absente du §13 — ajoutée par cohérence avec `revoke_reason` déjà présent partout ailleurs dans ce domaine (`platform_operators`, `carbon_commercialization_mandates`) ; une annulation interne sans motif consigné serait une régression par rapport au reste du modèle. **`external_rejection_*` (nouvelle, décision 1 de la troisième revue)** : trio de colonnes miroir d'`external_cancellation_*`, portant la preuve du refus d'une demande `'submitted'` par le registre externe — `external_rejection_document_id` est `NOT NULL` **au moment de la transition** `submitted → externally_rejected` (imposé par la RPC `record_externally_rejected()`, §7, jamais par une contrainte statique puisque la colonne doit rester `NULL` avant cette transition).

**`verification_outcome_id`** : renommé depuis `verification_session_id` par le §12, inchangé ici — référence le résultat précis utilisé (pas la session), `RESTRICT`.

**`aggregator_id` figé** : confirmé §7/§13 point 5 — déterminé par l'aggregator commun aux sources, jamais fourni par l'appelant, jamais recalculé après création.

**`operator_organization_id` figé — confirmé et précisé (décision 1 de la revue).** Non seulement figé, mais **dérivé exclusivement de l'opérateur METALTRACE actif au moment de la création** (`SELECT organization_id FROM platform_operators WHERE revoked_at IS NULL`, la même source que `is_platform_operator()`), **jamais accepté comme UUID libre fourni par l'appelant** — `create_credit_issuance()` n'a pas de paramètre `p_operator_organization_id`. Une fois cet opérateur actif identifié, **toutes** les sources proposées dans `p_sources` doivent référencer des mandats accordés à **ce même** opérateur, **et** appartenir au **même** `aggregator_id` — les deux homogénéités (regroupement et opérateur) sont vérifiées indépendamment, une source qui satisferait l'une sans l'autre est rejetée. Cas réel motivant cette double exigence : deux organisations membres du même regroupement peuvent avoir obtenu leur mandat à des moments différents, alors que l'opérateur METALTRACE actif avait changé entre-temps (transfert via `designate_platform_operator()`, migration 06) — sans cette double vérification, une émission pourrait mélanger des mandats désignant deux opérateurs différents tout en semblant homogène par regroupement. Ferme l'angle mort avant la migration 09 (`credit_sales`), où le troisième invariant du §13 point 9 exige déjà que tous les lots d'une vente partagent le même opérateur.

**`quantity_tco2e`** : `NUMERIC(14,4)`, existe dès `'internal'`. `create_credit_issuance()` la **calcule** comme `SUM(contributed_tco2e)` sur `p_sources` avant insertion — jamais un paramètre distinct fourni par l'appelant, élimine par construction tout désaccord entre la quantité déclarée et la somme des sources. **Pas de couple requested/issued pour ce MVP (décision 5 de la revue)** : une seule colonne, une seule valeur, figée à la création — `record_registry_issuance()` (§7) n'accepte aucun paramètre de quantité et ne modifie jamais `quantity_tco2e` ; la quantité officiellement enregistrée par le registre externe **doit correspondre exactement** à cette valeur, déjà figée depuis la création. Introduire une réallocation de sources entre quantité demandée et quantité réellement émise est explicitement hors périmètre — si le registre émet une quantité différente de celle demandée, cela relève d'un désaccord à résoudre hors système (correction, nouvelle émission) avant d'appeler `record_registry_issuance()`, jamais d'un ajustement silencieux de `quantity_tco2e` après coup (colonne immuable, voir ci-dessous).

**Immutabilité** : `verification_outcome_id`, `aggregator_id`, `operator_organization_id`, `quantity_tco2e`, `created_by`, `created_at` — jamais modifiables après création. Seules colonnes modifiables après création, et seulement selon la machine à états (§10) : `issuance_status`, `registry_name`, `registry_reference`, `registry_issued_at`, `external_cancellation_*`, `external_rejection_*`, `void_reason`.

### 2. `credit_issuance_sources` — colonnes exactes

```
credit_issuance_sources
  id                             UUID PRIMARY KEY DEFAULT gen_random_uuid()
  credit_issuance_id             UUID NOT NULL REFERENCES credit_issuances(id) ON DELETE RESTRICT
  organization_id                UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT
  aggregator_membership_id       UUID NOT NULL REFERENCES aggregator_memberships(id) ON DELETE RESTRICT
  commercialization_mandate_id   UUID NOT NULL REFERENCES carbon_commercialization_mandates(id) ON DELETE RESTRICT
  contributed_tco2e              NUMERIC(14,4) NOT NULL CHECK (contributed_tco2e > 0 AND contributed_tco2e <> 'NaN'::numeric)
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()

  UNIQUE (credit_issuance_id, organization_id)
```

`aggregator_membership_id`/`commercialization_mandate_id` : confirmées §13 point 8, inchangées.

**Unicité d'une organisation par émission** : `UNIQUE (credit_issuance_id, organization_id)` — une organisation ne peut apparaître que dans une seule ligne source par émission (empêche une contribution scindée artificiellement en plusieurs lignes pour la même organisation, garde la logique de somme simple et auditable).

**Cohérence stricte, imposée par un trigger `BEFORE INSERT` sur `credit_issuance_sources`** (même patron défensif que `carbon_validate_commercialization_mandate()`, migration 06) :

1. `aggregator_membership_id.organization_id = NEW.organization_id` — l'adhésion référencée appartient bien à l'organisation source déclarée.
2. `aggregator_membership_id.aggregator_id = credit_issuances.aggregator_id` (de l'émission parente) — la source appartient au même regroupement que l'émission.
3. `commercialization_mandate_id.aggregator_membership_id = NEW.aggregator_membership_id` — le mandat est rattaché à **cette adhésion précise**, pas seulement à la bonne organisation (cohérent avec la conception D5 du §13 point 7 : un mandat ne s'applique jamais à une autre adhésion, même de la même organisation au même regroupement).
4. `commercialization_mandate_id.operator_organization_id = credit_issuances.operator_organization_id` (de l'émission parente, elle-même dérivée de l'opérateur actif — point 1 ci-dessus) — impose l'homogénéité d'opérateur.
5. `commercialization_mandate_id.revoked_at IS NULL` **au moment de cet `INSERT`** — mandat actif à l'instant précis de la création de l'émission (voir invariants temporels, §3).
6. **`'request_issuance' = ANY(commercialization_mandate_id.scope)`** (ajouté après revue, décision 3) — le mandat doit explicitement autoriser cette action précise parmi les 8 valeurs du catalogue fermé (§13 point 7) ; un mandat valide mais dont le `scope` ne couvre pas `request_issuance` (ex. limité à `sell_credits` seul) ne peut pas servir de fondement à une émission.
7. `aggregator_membership_id` active au moment précis de la création (`started_at <= now() AND (ended_at IS NULL OR ended_at > now())`), déjà décrit §7 point 2 — inchangé.
8. `organization_id` est un participant réel du projet CCF/MRV concerné (`verification_outcome_id → verification_session_id → project_id`, puis jointure `project_participants`/`ccf_mrv_project_links`/`operational_units.organization_id`) — §7 point 1, inchangé dans son principe. **Dépendance structurelle explicite** : cette vérification ne peut être écrite ni testée avant que la migration 04 (`ccf_mrv_project_links`) soit appliquée — raison pour laquelle 07 dépend de 04 **et** 05 dans le plan figé (§14), pas seulement de 06.

Les vérifications 1-8 ci-dessus sont le filet de sécurité structurel (défense en profondeur) ; `create_credit_issuance()` (§7) effectue la **même** validation en amont, avant toute tentative d'`INSERT`, pour produire un message d'erreur clair au lieu de laisser le trigger la découvrir tardivement.

### 3. Invariants temporels — deux points de contrôle, révisé après revue (décision 3)

**Révision par rapport à la version précédente de ce document (qui ne validait qu'une seule fois, à la création) : deux points de contrôle explicites, `internal` et `submitted` — pas un seul.**

**À `internal` (création, `create_credit_issuance()`)**, pour chaque source proposée :
1. `aggregator_membership_id` active à cet instant.
2. `commercialization_mandate_id.revoked_at IS NULL` à cet instant.
3. `'request_issuance' = ANY(commercialization_mandate_id.scope)`.
4. `verification_outcomes.status = 'active'` pour le résultat référencé.
5. `operator_organization_id` (dérivé, §1) est bien l'opérateur METALTRACE actif à cet instant (`is_platform_operator(operator_organization_id) = true`).

**À `submitted` (`submit_credit_issuance()`), ces cinq mêmes vérifications sont intégralement REJOUÉES pour chaque source déjà rattachée à l'émission** — pas seulement héritées de la création. Si l'une d'elles ne tient plus (adhésion terminée entre-temps, mandat révoqué, scope insuffisant, résultat désormais `superseded`, ou l'opérateur figé n'est plus l'opérateur actif), **la transition `eligible → submitted` est bloquée** avec une exception explicite — l'émission reste à `'eligible'`, inchangée, jusqu'à ce que l'opérateur décide (attendre une régularisation, ou `void_credit_issuance()`). **Une révocation survenue entre la création et la soumission bloque donc la soumission, sans ambiguïté.**

**Après `submitted` (donc pour les transitions `submitted → issued`, `submitted → externally_rejected` et `issued → externally_cancelled`), les références deviennent purement historiques — aucune revalidation.** `record_registry_issuance()`, `record_externally_rejected()` et `record_external_cancellation()` ne relisent ni `aggregator_memberships` ni `carbon_commercialization_mandates` ni `verification_outcomes.status` ni `is_platform_operator()` — une révocation de mandat, une fin d'adhésion ou même un changement de l'opérateur actif survenant après `submitted` **ne bloque jamais** l'enregistrement de `issued`, `externally_rejected` ou `externally_cancelled`. Justification : au-delà de `submitted`, l'émission a été transmise à un tiers externe (le registre) — la traiter comme un fait en cours de constitution plutôt que comme un fait déjà engagé produirait des situations absurdes (un registre confirme ou refuse une demande, mais le système refuserait de l'enregistrer à cause d'un événement purement interne survenu après coup). La barrière de contrôle se ferme définitivement à `submitted`, jamais après. **Nuance ajoutée par la troisième revue (§15 point 10) : « aucune revalidation » porte ici sur les invariants métier (adhésion, mandat, résultat, opérateur actif) — pas sur l'autorisation de l'appelant, qui obéit à une règle distincte au-delà de `submitted` (§6, révisé).**

**`mark_credit_issuance_eligible()` (`internal → eligible`) n'effectue aucune revalidation propre** — la transition `internal → eligible` est une étape de préparation interne pure, les cinq vérifications ne sont rejouées qu'au passage suivant (`submit_credit_issuance()`), pas à chaque étape intermédiaire.

**Les références historiques déjà utilisées restent figées** (immutabilité, §1) — aucune colonne de `credit_issuances` référençant l'adhésion/le mandat/l'opérateur/le regroupement n'est jamais recalculée, quel que soit l'état ultérieur des objets référencés ; seule la **validité** de ces références est revérifiée aux deux points de contrôle ci-dessus, jamais leur **valeur**.

### 4. Prévention du double comptage — invariant obligatoire, étendu à la chaîne de supersession (décision 2 de la revue)

**Confirmé : un même `verification_outcome` peut alimenter plusieurs émissions partielles.** Une organisation peut émettre et commercialiser ses réductions par tranches plutôt que d'attendre une émission unique et complète.

**Révisé une seconde fois après la troisième revue (décision 1) : trois régimes, pas deux.** `'voided'` est désormais **strictement pré-transmission** — la machine à états (§10) n'autorise `voided` que depuis `{'internal','eligible'}`, jamais depuis `'submitted'` ni `'issued'`. `'externally_rejected'` (nouvel état terminal) n'est accessible **que** depuis `'submitted'` et **libère** la capacité — une demande déjà transmise, puis refusée par le registre, n'a jamais réellement consommé de crédits externes ; la préserver comme non-libératrice pénaliserait sans raison une organisation dont la demande a échoué pour une cause externe. `'externally_cancelled'` reste accessible **que** depuis `'issued'` et ne libère **jamais** la capacité (crédits réellement émis puis annulés). Toutes les émissions dans un statut autre que `'voided'`/`'externally_rejected'` — donc `'internal'`, `'eligible'`, `'submitted'`, `'issued'`, **et** `'externally_cancelled'` — consomment la capacité de façon permanente.

```
COMPTE dans la somme (permanent)   : 'internal', 'eligible', 'submitted', 'issued', 'externally_cancelled'
NE COMPTE PAS (libère la capacité) : 'voided', 'externally_rejected'
```

**Correction majeure par rapport à la version précédente de cette conception : le contrôle de capacité ne porte PAS sur un `verification_outcome_id` isolé — il porte sur l'ensemble de la chaîne de supersession, via `verification_session_id`.** Motif : lorsqu'un résultat de vérification est corrigé (`complete_verification_session()`, §12), l'ancien résultat passe à `'superseded'` et un nouveau résultat `'active'` est inséré — mais les émissions déjà créées contre l'ancien résultat restent des faits historiques valides et continuent de consommer une capacité réelle. Si le contrôle de capacité ne portait que sur le nouveau `verification_outcome_id` (dont la somme des émissions rattachées serait alors nulle, puisque toutes les émissions existantes référencent encore l'ancien), un opérateur pourrait immédiatement réémettre jusqu'à la totalité du nouveau `eligible_tco2e`, en plus de ce qui a déjà été émis sous l'ancien résultat — double comptage réel via la supersession, exactement le trou que ce contrôle doit fermer.

**Mécanisme corrigé :**

```
capacité consommée (session) := SUM(credit_issuances.quantity_tco2e)
  À TRAVERS TOUS les verification_outcomes de la MÊME verification_session_id
  (actif ou superseded, peu importe lequel des deux chaque émission référence précisément),
  WHERE credit_issuances.issuance_status NOT IN ('voided', 'externally_rejected')

plafond courant := verification_outcomes.eligible_tco2e
  DU résultat 'active' de cette même verification_session_id (un seul actif à la fois, §12)

INVARIANT (émission) : capacité consommée (session) <= plafond courant
  — imposé par create_credit_issuance() et par la contrainte différée sur credit_issuances (§4).

INVARIANT (supersession, bidirectionnel — décision 2 de la troisième revue) :
  lors de complete_verification_session() (§12) pour une session ayant déjà un résultat actif,
  le NOUVEAU p_eligible_tco2e ne peut jamais être < capacité consommée (session) au moment
  de la supersession — sinon la correction elle-même créerait rétroactivement un dépassement,
  sans qu'aucune nouvelle émission n'ait été créée. Rejet explicite si violé ; la supersession
  échoue, l'ancien résultat reste actif.
```

Concrètement : un résultat `v1` (`eligible_tco2e = 100`) avec 60 tCO2e déjà émis (non `voided`/`externally_rejected`), puis corrigé en `v2` (`eligible_tco2e = 90`, `supersedes_outcome_id = v1`) — capacité restante pour toute **nouvelle** émission contre `v2` : `90 − 60 = 30`, pas `90`. Si la correction avait plutôt relevé `eligible_tco2e` à `120`, la capacité restante serait `120 − 60 = 60`. Les 60 déjà émis sous `v1` ne sont ni annulés ni recalculés — seul le plafond disponible pour de nouvelles émissions tient compte du cumul déjà engagé sur l'ensemble de la chaîne. **Contre-exemple désormais rejeté (invariant bidirectionnel, décision 2)** : si 60 tCO2e sont déjà consommés sous `v1` et que la correction proposait `v2.eligible_tco2e = 50` (< 60 déjà consommés) — `complete_verification_session()` **refuse** cette supersession explicitement ; `v1` reste actif, aucun `v2` n'est inséré. Une correction à la baisse en-dessous du déjà-consommé est un désaccord à résoudre hors système (ex. par l'annulation externe des émissions déjà transmises), jamais une correction silencieusement acceptée qui laisserait la base dans un état rétroactivement incohérent.

Implémentation : le `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` (même patron que celui du §4 pour `credit_issuance_sources`) est posé sur `credit_issuances` (`AFTER INSERT OR UPDATE`), mais calcule sa somme en joignant `verification_outcomes` pour résoudre `verification_session_id` — jamais en comparant directement des `verification_outcome_id`. Recalculée au `COMMIT`, après que toutes les lignes de la transaction sont visibles. **L'invariant bidirectionnel (décision 2) est vérifié de façon immédiate dans `complete_verification_session()` elle-même** (migration 05), pas seulement via ce trigger différé de la migration 07 — les deux mécanismes sont complémentaires : le trigger différé protège contre un contournement direct de la table, `complete_verification_session()` donne un message d'erreur immédiat et clair au moment de la supersession.

**`'externally_cancelled'` continue de ne jamais libérer la capacité — confirmé, décision volontairement conservatrice pour ce MVP.** Ces crédits ont réellement existé (émis par un registre externe) avant d'être annulés ; une réémission légitime après annulation externe devrait passer par un nouveau `verification_outcome` (supersession), jamais par une réouverture silencieuse de capacité sur l'ancien.

**Verrouillage transactionnel — exigence commune aux migrations 05 et 07 (précisée, décision 2 de la troisième revue) : toute opération qui lit ou modifie la capacité consommée d'une session doit verrouiller exactement la même ligne `verification_sessions` (`SELECT ... FOR UPDATE` par `id`), jamais un `verification_outcome` précis.** S'applique à :
- `create_credit_issuance()` (migration 07) — verrouille `verification_sessions` avant de calculer la capacité consommée sur l'ensemble de la chaîne et de vérifier `capacité consommée <= plafond courant`.
- `complete_verification_session()` (migration 05) — verrouille la **même** ligne `verification_sessions` (pas seulement l'ancien `verification_outcome` comme le décrivait §12 avant cette revue) avant de calculer la capacité déjà consommée et de vérifier l'invariant bidirectionnel ci-dessus.

La session est l'ancre stable de toute la chaîne de supersession (elle ne change jamais d'identité, contrairement aux résultats qui se succèdent) ; verrouiller un résultat précis serait insuffisant dans les deux sens : une supersession concurrente changerait le résultat actif pendant qu'une émission calcule sa capacité, et une création d'émission concurrente changerait la capacité consommée pendant qu'une supersession vérifie l'invariant bidirectionnel. **Un seul et même verrou, sur un seul et même identifiant (`verification_sessions.id`), sérialise les deux directions.**

**Cas de concurrence, les deux sens désormais couverts explicitement (§12 mis à jour en conséquence) :**
1. Supersession (`complete_verification_session()`) concurrente à une création d'émission (`create_credit_issuance()`) sur la **même** session — attendu : le verrou commun sérialise les deux opérations, quel que soit l'ordre d'arrivée ; si la création passe en premier, la supersession voit la capacité déjà augmentée et applique l'invariant bidirectionnel contre cette valeur à jour ; si la supersession passe en premier, la création voit le nouveau plafond à jour.
2. Deux créations d'émissions concurrentes sur la même session (cas déjà couvert avant cette revue) — inchangé, sérialisé par le même verrou.

**Blocage des nouvelles émissions contre un résultat `superseded`** : inchangé — `create_credit_issuance()` exige `verification_outcomes.status = 'active'` pour le résultat référencé, rejet explicite sinon. Les émissions déjà créées contre un résultat depuis remplacé restent valides et continuent de consommer la capacité (voir mécanisme ci-dessus) ; seule la création de **nouvelles** émissions contre un résultat obsolète est bloquée.

### 5. Invariant des sources

- **Au moins une source** : vérification amont explicite dans `create_credit_issuance()` (rejet immédiat si `p_sources` vide ou nul), **en plus de** (pas à la place de) la contrainte différée ci-dessous — même double mécanisme que la correction 4 des « Corrections finales » (haut de ce document), déjà retenu pour ce domaine.
- **`SUM(contributed_tco2e) = credit_issuances.quantity_tco2e`** : contrainte différée (`CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED`, §4, mécanisme inchangé) — reste le filet de sécurité structurel même si `quantity_tco2e` est désormais calculée par la RPC (§1) plutôt que fournie séparément : une voie d'insertion hypothétique future qui contournerait la RPC resterait bloquée par cette contrainte.
- **Garde avant progression de statut** : le trigger `BEFORE UPDATE ON credit_issuances` du §1 (rejette toute progression hors de `'internal'` si aucune source n'existe ou si la somme ne correspond pas encore) reste inchangé et s'applique tel quel.
- **Chaque organisation source réellement reliée au projet concerné** : point 7 de la section 2 ci-dessus — dépendance structurelle sur la migration 04.

### 6. Autorisations — METALTRACE comme opérateur central, pas un `aggregator_admin` (révisé une seconde fois, décision 3 de la troisième revue : opérateur figé vs opérateur actif)

**Ne plus supposer qu'un `aggregator_admin` émet juridiquement les crédits** — confirmé, cohérent avec le pivot §13. `is_aggregator_admin()` reste pertinent pour la **lecture** (l'admin du regroupement voit les émissions de son regroupement) mais n'autorise plus aucune **écriture** sur `credit_issuances`/`credit_issuance_sources`.

**Distinction nouvelle, imposée par la troisième revue** : les fonctions `is_platform_operator_actor()`/`is_platform_operator_admin()`, telles que définies dans la version précédente de cette section (sans paramètre, résolvant en interne l'opérateur **actuellement actif**), sont correctes pour les actions **avant** `submitted`, mais **incorrectes** pour les actions **après** `submitted` — un transfert de l'opérateur METALTRACE (`designate_platform_operator()`, migration 06) entre la soumission d'une émission et son enregistrement au registre ne doit **jamais** transférer implicitement la responsabilité de cette émission déjà soumise au nouvel opérateur. L'autorisation après `submitted` doit porter sur `credit_issuances.operator_organization_id` **figé à la création**, pas sur l'opérateur actif au moment de l'appel.

**Fonctions révisées — paramétrées par `organization_id`, plutôt que de résoudre elles-mêmes l'opérateur actif :**

```
CREATE OR REPLACE FUNCTION public.is_platform_operator_actor(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.platform_operators po
    WHERE po.organization_id = p_organization_id
      AND po.revoked_at IS NULL
      AND public.is_organization_member(p_organization_id)
  )
$$;

CREATE OR REPLACE FUNCTION public.is_platform_operator_admin(p_organization_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.platform_operators po
    WHERE po.organization_id = p_organization_id
      AND po.revoked_at IS NULL
      AND public.is_org_admin(p_organization_id)
  )
$$;
```

**Changement de forme, pas seulement de signature** : la clause `po.organization_id = p_organization_id AND po.revoked_at IS NULL` vérifie **à la fois** que l'organisation fournie est bien membre/admin **et** qu'elle est bien l'opérateur **actuellement actif** — un seul appel encode donc les deux conditions exigées par la décision 3 pour les actions pré-`submitted` (« l'opérateur figé de l'émission doit encore être l'opérateur actif » + « l'acteur doit être autorisé pour cet opérateur »). Si `p_organization_id` (dérivé de `credit_issuances.operator_organization_id`) n'est plus l'opérateur actif, `po.revoked_at IS NULL` échoue pour cette ligne et la fonction renvoie `false`, quel que soit le rôle de l'acteur — un opérateur remplacé ne peut plus agir sur les émissions encore `internal`/`eligible`, même les siennes, avant `submitted`. `EXISTS(...)` — structurellement non-`NULL` dans les deux cas, inchangé.

**Pour les actions après `submitted` : `is_org_admin(operator_organization_id) OR is_platform_superadmin()` directement — jamais `is_platform_operator_admin()`.** `is_org_admin()` (fonction déjà existante, migration 02/06) vérifie l'administration de l'organisation **telle que fournie**, sans condition sur son statut d'opérateur actif — exactement le comportement requis : l'admin de l'organisation qui était l'opérateur au moment de la soumission reste autorisé à finaliser cette émission précise, même après un transfert d'opérateur, tant qu'il reste administrateur de son organisation d'origine. Aucune nouvelle fonction requise pour ce cas — `is_org_admin()` suffit, appliquée à la valeur figée de la colonne.

**Droits d'écriture révisés, par action — répartis en trois régimes d'autorisation (pas un seul) :**

| Action | RPC | Autorisation | Régime |
|---|---|---|---|
| Créer (brouillon interne) | `create_credit_issuance()` | `is_platform_operator_actor(v_operator_org_id)` où `v_operator_org_id` est l'opérateur actif résolu en interne | Opérateur actif (avant `submitted`) |
| `internal → eligible` | `mark_credit_issuance_eligible()` | `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` | Opérateur actif (avant `submitted`) |
| `eligible → submitted` | `submit_credit_issuance()` | `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` | Opérateur actif (avant `submitted`) |
| `submitted → issued` (émission officielle) | `record_registry_issuance()` | `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` | **Opérateur figé (après `submitted`)** |
| `submitted → externally_rejected` (refus registre) | `record_externally_rejected()` (nouvelle RPC) | `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` | **Opérateur figé (après `submitted`)** |
| `{internal,eligible} → voided` | `void_credit_issuance()` | `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` | Opérateur actif (avant `submitted`) |
| `issued → externally_cancelled` | `record_external_cancellation()` | `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` | **Opérateur figé (après `submitted`)** |

**Portée de `void_credit_issuance()` réduite (conséquence de la décision 1)** : `{internal,eligible} → voided` seulement — `submitted` n'y figure plus, cohérent avec la machine à états révisée (§1/§10) : une émission `submitted` ne peut plus être annulée en interne, seul `record_externally_rejected()` peut y mettre fin.

Justification de l'asymétrie, révisée une seconde fois : seule la création d'un brouillon interne (`create_credit_issuance()`, statut `'internal'`, purement préparatoire et toujours annulable) reste ouverte à tout membre actif de l'organisation opératrice. Les transitions `eligible`/`submitted`/`voided` restent gouvernées par l'opérateur **actif**, puisqu'elles précèdent ou constituent la transmission externe elle-même. Les trois transitions **postérieures** à `submitted` (`issued`, `externally_rejected`, `externally_cancelled`) basculent vers une autorisation fondée sur l'opérateur **figé** de l'émission — cohérent avec le principe déjà établi qu'au-delà de `submitted`, l'émission est un fait historique engagé, dont la responsabilité (y compris administrative) ne doit plus dériver au gré des changements d'opérateur actif.

**Droits de lecture (RLS `SELECT`)** — révisé (décision retenue à la douzième revue statique de `07_carbon_issuances.sql` ; remplace la formulation précédente de ce paragraphe, incohérente avec le SQL réellement implémenté) :

`credit_issuances` (table parente, `can_view_credit_issuance(id)`) : `is_platform_superadmin()` ; **`is_organization_member(operator_organization_id)`** appliquée à la valeur **figée** de la ligne — PAS `is_platform_operator_actor()`. Différence délibérée entre lecture et écriture pré-`submitted` : une simple appartenance à l'organisation opératrice figée suffit, SANS exiger que cette organisation soit encore l'opérateur *actuellement* actif. Conséquence assumée : **l'opérateur figé historique conserve la visibilité de toutes les émissions dont il était responsable, même après un transfert de l'opérateur METALTRACE actif** (`designate_platform_operator()`, migration 06) — cohérent avec le régime post-`submitted` déjà établi ci-dessus (`is_org_admin(operator_organization_id) OR is_platform_superadmin()`, lui aussi indépendant de l'opérateur actif) : la visibilité en lecture ne doit jamais être strictement plus étroite que les droits d'action déjà accordés sur la même ligne. **Le nouvel opérateur actif n'hérite PAS automatiquement de cette visibilité historique** — seule l'organisation réellement figée sur `operator_organization_id` la conserve, jamais celle qui devient l'opérateur actif ensuite. `is_aggregator_admin(aggregator_id)` (l'admin du regroupement voit les émissions de son regroupement) ; `is_assigned_verifier(...)` pour le vérificateur assigné à la session sous-jacente (réutilisation directe du mécanisme §10bis).

`credit_issuance_sources` (table enfant, **helper dédié** `can_view_credit_issuance_source(credit_issuance_id, organization_id)`, distinct de `can_view_credit_issuance()`) : les quatre branches privilégiées ci-dessus (super-admin, opérateur figé, aggregator admin, vérificateur assigné) voient **toutes** les lignes source d'une émission qu'elles peuvent consulter ; une organisation contributrice **ordinaire** (`is_organization_member` appliquée à la `organization_id` de la ligne évaluée, pas à l'émission dans son ensemble) ne voit que **sa propre ligne** — jamais les lignes des autres organisations sources de la même émission. Cette distinction entre les deux tables est structurelle, pas cosmétique : un helper unique appliqué identiquement aux deux tables (rendre `credit_issuance_sources` visible dès que l'émission parente l'est) romprait la règle « une organisation voit ses propres contributions » dès qu'une émission a plusieurs sources — exactement la fuite corrigée à la douzième revue statique.

Données sensibles, **pas** lisibles par un utilisateur authentifié quelconque sans lien avec l'une des catégories ci-dessus.

**Aucune écriture directe normale par `authenticated`** : aucune policy `INSERT`/`UPDATE`/`DELETE` exposée sur les deux tables — écriture exclusivement par les RPC `SECURITY DEFINER` listées ci-dessous, même principe que migrations 02/06.

### 7. RPC — responsabilités séparées, jamais un setter générique de statut

Conformément à la mise en garde explicite reçue en revue (« éviter une RPC unique permettant arbitrairement de modifier `issuance_status` »), chaque transition a sa propre RPC nommée, avec son statut de départ exact codé en dur — aucune RPC n'accepte un statut cible arbitraire en paramètre. Autorisations : voir tableau §6 (révisé).

1. **`create_credit_issuance(p_verification_outcome_id UUID, p_sources JSONB)`** — `is_platform_operator_actor(v_operator_org_id)`, `v_operator_org_id` résolu en interne depuis l'opérateur actif. Verrouille `verification_sessions` (§4), dérive `operator_organization_id` depuis l'opérateur actif (§1, jamais un paramètre), calcule et valide tout pour chaque source (les cinq vérifications du point de contrôle `internal`, §3 : adhésion active, mandat actif, scope `request_issuance`, résultat `active`, opérateur actif), calcule `quantity_tco2e := SUM(contributed_tco2e)` sur `p_sources`, vérifie la capacité restante sur l'ensemble de la chaîne de supersession (§4), insère `credit_issuances` (`issuance_status = 'internal'`) puis ses `credit_issuance_sources`, dans une seule transaction.
2. **`mark_credit_issuance_eligible(p_credit_issuance_id UUID)`** — `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` (opérateur **actif**, §6 révisé). `'internal' → 'eligible'` uniquement, rejette tout autre statut de départ. Aucune revalidation propre (§3).
3. **`submit_credit_issuance(p_credit_issuance_id UUID, p_registry_name TEXT)`** — `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` (opérateur **actif**, §6 révisé). `'eligible' → 'submitted'` uniquement. **Rejoue intégralement les cinq vérifications du point de contrôle `submitted` (§3) pour chaque source rattachée à l'émission** — rejet explicite si l'une d'elles ne tient plus, l'émission reste `'eligible'`, inchangée. Renseigne `registry_name` (devient `NOT NULL` à partir de ce statut) seulement si la revalidation réussit intégralement. **Dernier point de contrôle de l'opérateur actif** — au-delà de cette transition, l'autorisation bascule sur l'opérateur figé (§6).
4. **`record_registry_issuance(p_credit_issuance_id UUID, p_registry_reference TEXT, p_registry_issued_at TIMESTAMPTZ)`** — `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` (opérateur **figé**, §6 révisé — pas l'opérateur actif). `'submitted' → 'issued'` uniquement, **aucune revalidation métier** (§3, purement historique au-delà de `submitted`). Renseigne `registry_reference` et `registry_issued_at` (réconcilié avec le SQL réel, quatorzième revue statique : `p_registry_issued_at` est le timestamp **officiel fourni par le registre externe**, jamais `clock_timestamp()` — `clock_timestamp()` daterait l'enregistrement dans METALTRACE, pas l'émission réelle par le registre, ce qui serait sémantiquement faux pour un fait historique externe). **N'accepte aucun paramètre de quantité** — `quantity_tco2e`, figée depuis la création, doit correspondre exactement à ce que le registre a réellement émis (§1, pas de couple requested/issued pour ce MVP) ; documenté explicitement dans le commentaire de la fonction comme rappel à l'opérateur au moment d'appeler cette RPC.
5. **`record_externally_rejected(p_credit_issuance_id UUID, p_date DATE, p_reference TEXT, p_document_id UUID)`** — nouvelle RPC (décision 1 de la troisième revue). `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` (opérateur **figé**, §6 révisé). `'submitted' → 'externally_rejected'` uniquement, `p_document_id` **obligatoire** (`NOT NULL`, preuve du refus externe). Renseigne `external_rejection_date`/`external_rejection_reference`/`external_rejection_document_id`. Aucune revalidation métier (§3). Libère la capacité consommée (§4) — seule transition post-`submitted` à le faire.
6. **`void_credit_issuance(p_credit_issuance_id UUID, p_reason TEXT)`** — `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` (opérateur **actif**, §6 révisé). **`{'internal','eligible'} → 'voided'` uniquement (portée réduite, décision 1)** ; rejette explicitement depuis `'submitted'` (utiliser `record_externally_rejected()` à la place, qui exige une preuve du registre), depuis `'issued'` (utiliser `record_external_cancellation()`), et depuis tout statut déjà terminal. Aucune revalidation d'adhésion/mandat requise pour annuler (une annulation reste toujours possible, quel que soit l'état des objets référencés, tant que l'émission n'a pas encore été transmise).
7. **`record_external_cancellation(p_credit_issuance_id UUID, p_date DATE, p_reference TEXT, p_document_id UUID)`** — `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` (opérateur **figé**, §6 révisé). `'issued' → 'externally_cancelled'` uniquement, `p_document_id` **obligatoire** (`NOT NULL`, contrairement à `void_credit_issuance()` qui n'exige aucune preuve). Aucune revalidation (§3). Ne libère jamais la capacité (§4).

**Machine à états complète, révisée (décision 1 de la troisième revue), transitions autorisées (uniquement celles-ci) et toutes les autres implicitement interdites :**

```
internal        → eligible              (mark_credit_issuance_eligible)
eligible        → submitted             (submit_credit_issuance)
submitted       → issued                (record_registry_issuance)
submitted       → externally_rejected   (record_externally_rejected, preuve obligatoire)   [NOUVEAU]
issued          → externally_cancelled  (record_external_cancellation, preuve obligatoire)
internal        → voided                (void_credit_issuance, aucune preuve)
eligible        → voided                (void_credit_issuance, aucune preuve)

voided               = terminal, aucune transition sortante
externally_rejected  = terminal, aucune transition sortante   [NOUVEAU]
externally_cancelled = terminal, aucune transition sortante
```

**`submitted → voided` retirée (n'existe plus)** : une demande déjà transmise au registre externe ne peut plus être annulée unilatéralement par METALTRACE avec réutilisation immédiate de la capacité — seul le registre, via `record_externally_rejected()`, peut mettre fin à une demande `submitted`, avec preuve obligatoire.

Un trigger `BEFORE UPDATE OF issuance_status ON credit_issuances` fait respecter exactement cette table (rejet explicite de toute paire `(OLD.issuance_status, NEW.issuance_status)` non listée ci-dessus — notamment `submitted → voided`, désormais explicitement rejetée par ce trigger et non plus seulement absente de la liste), en plus de — pas à la place de — chaque RPC qui ne référence déjà que le statut de départ exact qu'elle attend.

### 8. Sécurité

Checklist §11 intégralement applicable, sans exception, aux 7 RPC ci-dessus (6 après la création, révisé — décision 1 de la troisième revue ajoute `record_externally_rejected()`) : `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `auth.uid() IS NULL` vérifié en première ligne, `REVOKE EXECUTE FROM PUBLIC` (et explicitement `anon`/`authenticated` avant regrant, leçon du correctif 06a — ne jamais se fier à `PUBLIC` seul dans ce projet), aucune confiance dans `p_sources jsonb` brut (validation stricte de structure avant toute utilisation, jamais de `jsonb_populate_recordset` non gardé).

**Validation sémantique de chaque UUID reçu** : `p_verification_outcome_id` doit exister et être `'active'` ; chaque `organization_id` dans `p_sources` doit être un participant réel du projet (point 2.8 ci-dessus) ; chaque `aggregator_membership_id`/`commercialization_mandate_id` dérivé doit satisfaire les huit cohérences du point 2 (dont le scope `request_issuance`, ajouté après revue) — jamais une confiance implicite qu'un UUID fourni ou dérivé désigne un objet valide.

**Aucune fuite d'existence** : leçon directe de D13 (migration 06) — **les six RPC de transition** (`mark_credit_issuance_eligible()`, `submit_credit_issuance()`, `record_registry_issuance()`, `record_externally_rejected()`, `void_credit_issuance()`, `record_external_cancellation()`) doivent **fusionner** la recherche de `credit_issuances` par `p_credit_issuance_id` et la vérification d'autorisation dans la **même** requête, avec un message générique unique (`'Émission introuvable ou accès refusé.'`) pour un UUID inexistant et pour une émission existante mais inaccessible — même patron exact que `grant_commercialization_mandate()`/`revoke_commercialization_mandate()`. **S'applique identiquement aux deux régimes d'autorisation du §6 révisé** : que la RPC vérifie `is_platform_operator_admin(operator_organization_id)` (opérateur actif, pré-`submitted`) ou `is_org_admin(operator_organization_id)` (opérateur figé, post-`submitted`), la fusion recherche+autorisation dans une seule requête `SELECT ... WHERE id = p_credit_issuance_id AND (<condition d'autorisation>) FOR UPDATE` reste obligatoire dans les deux cas — le régime d'autorisation change, pas le patron anti-fuite.

**Événements métier uniquement après succès** : chaque RPC insère dans `carbon_business_events` seulement après que sa transition a réellement eu lieu (jamais avant une validation qui pourrait encore échouer) ; tout refus d'autorisation ou échec de validation va dans `carbon_rpc_failures` (ou remonte une exception au client sans journalisation dans `carbon_business_events`, conformément à §11/§11bis).

### 9. Matrice de tests prévue (structure, pas encore le SQL) — enrichie après la troisième revue

**Partie A (structurelle)** : existence des deux tables et de leurs colonnes exactes, dont `quantity_tco2e` (renommée), `registry_name`/`registry_reference`/`void_reason`/`external_rejection_*` (nouvelles) ; les deux `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` (somme des sources §5, capacité par `verification_session_id` sur la chaîne de supersession §4, y compris l'invariant bidirectionnel côté `complete_verification_session()`, migration 05) ; le trigger de machine à états et sa table de transitions complète, y compris le rejet explicite de `submitted → voided` (§10 ci-dessous) ; le trigger de cohérence `BEFORE INSERT` sur `credit_issuance_sources` (huit vérifications, dont le scope `request_issuance`) ; les 7 RPC (6 après la création) avec signature/`SECURITY DEFINER`/`search_path` exacts, dont la nouvelle `record_externally_rejected()` ; existence des deux fonctions paramétrées `is_platform_operator_actor(uuid)`/`is_platform_operator_admin(uuid)` (signature à un argument, revue) ; privilèges réels (`has_function_privilege`/`has_table_privilege`, `authenticated` oui, `anon` non, pour les 7 RPC et les 2 fonctions — vérifier explicitement après la leçon 06a).

**Partie B (comportementale)**, cas minimaux à couvrir :

- Double émission / dépassement d'`eligible_tco2e` sur un seul résultat (pas de supersession) : deux émissions successives, la seconde dépassant la capacité restante — rejetée. Variante concurrente (deux appels simultanés sous verrou `verification_sessions`) — un seul des deux réussit si leur somme dépasse la capacité.
- Émission dans les limites (partielle) réussit, une seconde émission partielle complémentaire dans la capacité restante réussit également — confirme que le partiel est bien permis.
- **Supersession et capacité cumulée** : émission de 60 tCO2e contre un résultat `v1` (`eligible_tco2e = 100`) ; `v1` corrigé en `v2` (`eligible_tco2e = 90`, supersession) ; une nouvelle émission de 35 tCO2e contre `v2` est **rejetée** (60 déjà consommés + 35 > 90) ; une nouvelle émission de 25 tCO2e contre `v2` **réussit** (60 + 25 = 85 ≤ 90). Variante : correction à la hausse (`v2.eligible_tco2e = 120`) — une nouvelle émission de 55 tCO2e contre `v2` réussit (60 + 55 = 115 ≤ 120).
- **Invariant bidirectionnel de supersession (nouveau, décision 2 de la troisième revue, à tester explicitement)** : émission de 60 tCO2e `'internal'` contre `v1` (`eligible_tco2e = 100`) ; `complete_verification_session()` tente de corriger en `v2` avec `eligible_tco2e = 50` (< 60 déjà consommés) — **rejetée explicitement**, `v1` reste actif, aucun `v2` n'est inséré. Variante limite : `v2.eligible_tco2e = 60` exactement (= déjà consommé) — **réussit** (capacité restante nulle, mais invariant non violé). Variante concurrente : `complete_verification_session()` et `create_credit_issuance()` appelées simultanément sur la même session — un seul verrou `verification_sessions` partagé (§4/§12) sérialise, résultat déterministe quel que soit l'ordre.
- `voided` libère la capacité : une émission `'internal'` de 40 tCO2e annulée (`void_credit_issuance()`), une nouvelle émission de 40 tCO2e contre le même résultat réussit ensuite.
- **`externally_rejected` libère la capacité (nouveau, décision 1 de la troisième revue)** : une émission `'submitted'` de 40 tCO2e refusée par le registre (`record_externally_rejected()`, avec `p_document_id`), une nouvelle émission de 40 tCO2e contre le même résultat réussit ensuite.
- `externally_cancelled` NE libère PAS la capacité : une émission `'issued'` de 40 tCO2e annulée en externe (`record_external_cancellation()`), une nouvelle émission tentant de consommer ces 40 tCO2e contre le même résultat (ou sa chaîne) est rejetée.
- Source sans mandat actif — rejetée.
- Source dont le mandat ne couvre pas `request_issuance` dans son scope (mandat valide mais limité à d'autres actions) — rejetée (cohérence point 2.6).
- Mandat révoqué **avant** la création de l'émission — rejetée à la création (point de contrôle `internal`, §3).
- Mandat révoqué **après** la création, émission encore `'internal'`/`'eligible'` — **la transition suivante vers `'submitted'` est bloquée** (point de contrôle `submitted`, §3, revalidation) ; message explicite, émission inchangée à `'eligible'`.
- Mandat révoqué **après** `'submitted'`, émission déjà `submitted`/`issued` — `record_registry_issuance()`/`record_externally_rejected()`/`record_external_cancellation()` réussissent normalement malgré la révocation (confirme l'absence de revalidation métier au-delà de `submitted`, §3).
- Mauvaise adhésion (mandat rattaché à une autre adhésion que celle fournie) — rejetée.
- Mauvais regroupement (source d'un `aggregator_id` différent de celui déterminé par les autres sources) — rejetée, homogénéité §13 point 5.
- Faux opérateur (mandat désignant une organisation qui n'est plus l'opérateur actif au moment de la création) — rejetée.
- Sources avec opérateurs différents pourtant même regroupement (deux mandats créés avant/après un transfert d'opérateur) — rejetée explicitement à la création, confirme la fermeture de l'angle mort (§1).
- Résultat de vérification `superseded` — création rejetée contre lui directement ; émission déjà créée contre un résultat depuis `superseded` continue de progresser normalement à travers ses points de contrôle (§3).
- Somme des sources incorrecte (`SUM(contributed_tco2e) ≠ quantity_tco2e`, y compris via une tentative de contournement direct de la RPC) — rejetée par la contrainte différée.
- Chaque transition interdite de la table du §10 testée explicitement au moins une fois — notamment **`submitted → voided`** (nouveau cas explicite, décision 1 : doit être rejetée, `void_credit_issuance()` refuse tout appel sur une émission `'submitted'`), `voided → issued`, `externally_rejected → issued`, `issued → internal`, `eligible → issued` (saut d'étape), et une seconde tentative sur un statut déjà terminal (y compris `externally_rejected → externally_rejected`).
- `void_credit_issuance()` rejetée depuis `'submitted'` (nouveau, doit utiliser `record_externally_rejected()`) et depuis `'issued'` (doit utiliser `record_external_cancellation()`).
- `record_externally_rejected()` rejetée sans `p_document_id`, et rejetée si l'émission n'est pas `'submitted'` (ex. tentative depuis `'issued'`).
- `record_external_cancellation()` rejetée sans `p_document_id`.
- **Autorisation, cas d'isolation pré-`submitted`** : un simple membre (non admin) de l'organisation opératrice réussit `create_credit_issuance()` mais échoue sur `mark_credit_issuance_eligible()`/`submit_credit_issuance()`/`void_credit_issuance()` — confirme la séparation stricte actrice/admin du §6.
- **Autorisation, opérateur figé vs opérateur actif (nouveau, décision 3 de la troisième revue, cas central à tester explicitement)** : émission créée et soumise (`'submitted'`) sous l'opérateur `Org A` ; `designate_platform_operator()` transfère l'opérateur actif vers `Org B` ; l'admin d'`Org A` (devenu un opérateur non actif) réussit toujours `record_registry_issuance()`/`record_externally_rejected()`/`record_external_cancellation()` sur cette émission précise (autorisation sur l'opérateur figé) ; l'admin d'`Org B` (nouvel opérateur actif) **échoue** sur ces mêmes appels tant qu'il n'est pas également super-admin (aucune reprise implicite de responsabilité). Variante inverse, avant `submitted` : une émission encore `'internal'`/`'eligible'` sous `Org A` après le même transfert — l'admin d'`Org A` **échoue** désormais (`is_platform_operator_admin(operator_organization_id)` renvoie `false`, `Org A` n'est plus l'opérateur actif) ; confirme que la bascule de régime se produit exactement à `submitted`, dans les deux sens.
- RLS multi-acteurs (rôle `authenticated` réel, jamais testé uniquement sous `postgres`) : organisation source voit sa propre contribution, admin de regroupement voit les émissions de son regroupement, membre de l'organisation opératrice voit l'ensemble, vérificateur assigné voit les émissions liées à sa session, tiers sans relation ne voit rien.
- Absence de fuite d'existence : message identique pour `p_credit_issuance_id` inexistant et pour une émission existante mais inaccessible, sur **chacune des 6** RPC de transition (périmètre élargi, §8), dans les deux régimes d'autorisation.

### 10. Synthèse finale — machine à états, invariants de double comptage/supersession, matrice des 7 RPC (révisée après la troisième revue)

Synthèse demandée avant toute rédaction SQL. Reprend et consolide §1, §2, §3, §4, §6, §7 et §12 ci-dessus, révisés par les trois corrections de la troisième revue ; n'introduit aucune règle nouvelle par rapport à ces sections.

**a) Machine à états complète (`credit_issuances.issuance_status`)**

```
internal        → eligible              (mark_credit_issuance_eligible)
eligible        → submitted             (submit_credit_issuance)      [revalidation §3 point 2, dernier contrôle "opérateur actif"]
submitted       → issued                (record_registry_issuance)                        [autorisation : opérateur figé]
submitted       → externally_rejected   (record_externally_rejected, preuve obligatoire)   [autorisation : opérateur figé — NOUVEAU]
issued          → externally_cancelled  (record_external_cancellation, preuve obligatoire) [autorisation : opérateur figé]
internal        → voided                (void_credit_issuance, aucune preuve)
eligible        → voided                (void_credit_issuance, aucune preuve)

voided               = terminal, aucune transition sortante
externally_rejected  = terminal, aucune transition sortante   [NOUVEAU]
externally_cancelled = terminal, aucune transition sortante
```

**`submitted → voided` n'existe plus (décision 1)** : une demande déjà transmise ne peut plus être annulée en interne ; seul le registre, via `externally_rejected`, met fin à une demande `submitted`. Toute autre paire `(OLD.issuance_status, NEW.issuance_status)` — y compris `submitted → voided`, `voided → issued`, `externally_rejected → issued`, `issued → internal`, saut d'étape `eligible → issued`, ou toute transition depuis un statut déjà terminal — est rejetée par un trigger `BEFORE UPDATE OF issuance_status`, indépendamment de ce que chaque RPC impose déjà par son propre statut de départ codé en dur.

Deux points de contrôle temporels métier (§3) sont ancrés sur cette machine : à `'internal'` (création) et à `'eligible' → 'submitted'` (revalidation complète, bloquante). Rien n'est revalidé **métier** après `'submitted'` — mais l'**autorisation**, elle, change de régime exactement à ce point (voir c) ci-dessous).

**b) Invariants de double comptage et de supersession**

1. La capacité n'est jamais bornée par un `verification_outcome_id` isolé, mais par la somme de `quantity_tco2e` de **toutes** les `credit_issuances` non `'voided'`/non `'externally_rejected'` rattachées à **n'importe quel** `verification_outcome_id` partageant le même `verification_session_id` — c'est-à-dire toute la chaîne de supersession d'une session donnée.
2. Cette somme doit rester `≤ eligible_tco2e` de l'outcome actuellement `status = 'active'` dans cette chaîne (jamais celui d'un outcome `'superseded'`).
3. `'voided'` et `'externally_rejected'` libèrent la capacité qu'ils occupaient ; `'externally_cancelled'` ne la libère jamais (l'unité a réellement quitté le registre externe, elle reste comptée contre le plafond).
4. **Invariant bidirectionnel (NOUVEAU, décision 2)** : lors d'une supersession (`complete_verification_session()`, migration 05), le nouveau `p_eligible_tco2e` ne peut jamais être inférieur à la capacité déjà consommée par la session au moment de la supersession — sinon la correction elle-même créerait rétroactivement un dépassement. Violation → supersession rejetée explicitement, l'ancien résultat reste actif.
5. **Un seul et même verrou, sur `verification_sessions.id` (`SELECT ... FOR UPDATE`), partagé par les migrations 05 et 07 (NOUVEAU, précisé décision 2)** : `create_credit_issuance()` (07) et `complete_verification_session()` (05) verrouillent la **même** ligne avant de lire/écrire la capacité consommée — jamais un `verification_outcome` précis. C'est ce partage exact qui sérialise correctement une supersession concurrente à une création d'émission, dans les deux sens.
6. `create_credit_issuance()` refuse toute nouvelle émission contre un outcome dont `status ≠ 'active'` ; une émission déjà créée contre un outcome depuis remplacé continue normalement (elle reste comptée dans la somme de la chaîne, elle n'est pas invalidée rétroactivement).
7. Contrainte structurelle de secours : `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` sur `credit_issuances`, revalidant l'invariant 2 en fin de transaction — filet de sécurité si une future RPC contournait le contrôle applicatif ; l'invariant bidirectionnel (4) est vérifié directement et immédiatement dans `complete_verification_session()`.

**c) Matrice des 7 RPC — deux régimes d'autorisation, bascule exacte à `submitted` (NOUVEAU, décision 3)**

| # | RPC | Transition | Autorisation | Régime | Revalidation métier (§3) |
|---|-----|-----------|---------------|--------|---------------------------|
| 1 | `create_credit_issuance(p_verification_outcome_id, p_sources)` | (aucune) → `internal` | `is_platform_operator_actor(v_operator_org_id)` | Opérateur **actif** | Point de contrôle `internal` (5 vérifications) |
| 2 | `mark_credit_issuance_eligible(p_credit_issuance_id)` | `internal → eligible` | `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` | Opérateur **actif** | Aucune |
| 3 | `submit_credit_issuance(p_credit_issuance_id, p_registry_name)` | `eligible → submitted` | `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` | Opérateur **actif** | Point de contrôle `submitted` (mêmes 5 vérifications, bloquant) |
| 4 | `record_registry_issuance(p_credit_issuance_id, p_registry_reference, p_registry_issued_at)` | `submitted → issued` | `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` | **Opérateur figé** | Aucune (aucun paramètre de quantité) — `p_registry_issued_at TIMESTAMPTZ` est le timestamp officiel fourni par le registre externe, jamais `clock_timestamp()` (réconcilié avec le SQL réel, quatorzième revue statique) |
| 5 | `record_externally_rejected(p_credit_issuance_id, p_date, p_reference, p_document_id)` | `submitted → externally_rejected` | `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` | **Opérateur figé** | Aucune ; `p_document_id` obligatoire |
| 6 | `void_credit_issuance(p_credit_issuance_id, p_reason)` | `{internal,eligible} → voided` | `is_platform_operator_admin(operator_organization_id)` OU `is_platform_superadmin()` | Opérateur **actif** | Aucune |
| 7 | `record_external_cancellation(p_credit_issuance_id, p_date, p_reference, p_document_id)` | `issued → externally_cancelled` | `is_org_admin(operator_organization_id)` OU `is_platform_superadmin()` | **Opérateur figé** | Aucune ; `p_document_id` obligatoire |

Seule la RPC de création (#1) reste ouverte à tout membre de l'organisation opératrice active. Les transitions #2, #3, #6 (avant/à `submitted`) restent gouvernées par l'opérateur **actif**, via les fonctions paramétrées `is_platform_operator_actor(uuid)`/`is_platform_operator_admin(uuid)` — un opérateur remplacé perd immédiatement ce droit. Les transitions #4, #5, #7 (après `submitted`) basculent sur l'opérateur **figé** (`operator_organization_id` de la ligne, via `is_org_admin()` directement, sans passer par `platform_operators`) — un transfert d'opérateur METALTRACE après soumission ne transfère jamais implicitement la responsabilité d'une émission déjà transmise. Les 6 RPC de transition fusionnent toutes recherche + autorisation dans une seule requête (absence de fuite d'existence, §8), quel que soit leur régime.

**Statut (actualisé, quatorzième revue statique) : migration 07 et son script de validation compagnon (`07_carbon_issuances.sql` + `tests/07_test_carbon_issuances.sql`) sont rédigés, en revue statique itérative depuis la quatrième revue, actuellement à la quatorzième — non exécutés, non intégrés aux migrations appliquées (`supabase/carbon_migrations_proposed/`, délibérément hors de `supabase/migrations/`). Autorisation d'exécution non encore donnée : conditionnée à la réconciliation effective avec les migrations 04 et 05 (non encore rédigées) et à l'ajout des deux tests RLS du vérificateur assigné/non assigné — la conception de la migration 05 (`complete_verification_session()`) devra intégrer explicitement l'invariant bidirectionnel et le verrou partagé b)4-5 ci-dessus au moment de sa rédaction.**

**d) Invariant de transfert d'opérateur — interdiction si des émissions pré-soumission subsistent (AJOUT, dixième revue statique de `07_carbon_issuances.sql`, 19 juillet 2026)**

Corrige un cul-de-sac identifié lors de la revue statique du fichier SQL effectivement rédigé (postérieur à cette synthèse) : le régime « opérateur actif » retenu en c) pour les transitions #1/#2/#3/#6 (avant `submitted`) a pour conséquence qu'un transfert de l'opérateur METALTRACE actif (`designate_platform_operator()`, migration 06) rend **immédiatement et définitivement inaccessibles** toutes les émissions encore `internal`/`eligible` rattachées à l'ancien opérateur — y compris pour un super-administrateur, puisque `is_platform_operator_admin()`/`is_platform_operator_actor()` exigent structurellement que l'organisation fournie soit encore l'opérateur actif (b) ci-dessus, décision revue). Une telle émission ne peut alors plus ni progresser (`mark_credit_issuance_eligible()`/`submit_credit_issuance()`), ni être annulée (`void_credit_issuance()`, même régime) — tout en continuant indéfiniment à consommer la capacité du résultat de vérification concerné (b)1 ci-dessus), sans qu'aucune action ne puisse jamais la libérer.

**Décision : le transfert ou la révocation de l'opérateur actif (`designate_platform_operator()`) est désormais REFUSÉ tant qu'il existe au moins une `credit_issuances` à statut `internal` ou `eligible` rattachée à cet opérateur.** Avant tout transfert, ces émissions doivent obligatoirement être amenées à `submitted` (basculement vers le régime opérateur figé, qui survit au transfert par construction — voir c) ci-dessus) ou à `voided`. Les émissions déjà `submitted`/`issued`/etc. ne bloquent jamais un transfert : elles relèvent déjà du régime opérateur figé et n'ont besoin d'aucune action de l'opérateur actif.

Implémentation : un trigger `BEFORE UPDATE` sur `platform_operators` (posé par `07_carbon_issuances.sql`, puisque `platform_operators` — table de la migration 06, déjà appliquée en production — ne peut structurellement pas référencer `credit_issuances`, table de 07, au moment de sa propre création) se déclenche uniquement sur la transition `OLD.revoked_at IS NULL → NEW.revoked_at IS NOT NULL` et vérifie l'absence de ligne `credit_issuances.operator_organization_id = OLD.organization_id AND issuance_status IN ('internal','eligible')`. Ce trigger s'applique à **toute** cause d'une telle transition — y compris un futur mécanisme de révocation qui ne passerait pas par `designate_platform_operator()` — puisqu'il est posé au niveau de la table, pas de la RPC.

---

## Points secondaires

**Allocations à composantes multiples** : `credit_sale_allocations` reçoit `allocation_type TEXT NOT NULL DEFAULT 'carbon_revenue' CHECK (allocation_type IN ('carbon_revenue','expense_reimbursement','reserve','bonus','adjustment'))` — permet plusieurs lignes par organisation si plusieurs composantes distinctes doivent être distinguées, sans perdre la protection contre le doublon accidentel d'une même composante. **Contrainte `UNIQUE` et caractère obligatoire d'`allocated_tco2e` : voir §13 point 8 (mis à jour le 14 juillet 2026 — `UNIQUE` à 4 colonnes incluant `aggregator_id`, `allocated_tco2e` conditionnel selon `allocation_type`), ce paragraphe-ci ne fait plus foi sur ces deux points.**

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

**Garantis par la base** : tout ce qui était listé en v2/v3, plus — `commercial_status` ne quitte `'unavailable'` que si `issuance_status = 'issued'` (trigger) ; `SUM(credit_issuance_sources.contributed_tco2e) = credit_issuances.quantity_tco2e` via **contrainte différée** (§15 point 5, mécanisme maintenant précisé) ; capacité cumulée par chaîne de supersession `≤ eligible_tco2e` de l'outcome actif (§15 point 4, contrainte différée sur `credit_issuances`) ; un seul résultat de vérification actif par session (index unique partiel) ; `distribution_rules`/`verification_outcomes`/`credit_sales` (post-confirmation) immuables par trigger ; `RESTRICT` sur toutes les FK historiques (§8) ; `carbon_business_events` sans `UPDATE`/`DELETE` possible.

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

## Plan des migrations proposées — OBSOLÈTE, NE PAS UTILISER (voir §14)

**Section entière marquée obsolète, treizième revue statique — y compris les statuts d'exécution décrits plus bas pour les migrations `01` et `02` (précision dix-huitième revue statique).** La numérotation `01-07` ci-dessous (en particulier les lignes `03` à `07`) contredit directement le plan `04-09` figé le 14 juillet 2026 en §14 (« Collision de numérotation — FIGÉE... définitive »), qui reste la **seule** source autoritative pour la correspondance numéro de migration / fichier / contenu. Conservée uniquement pour l'historique de la réflexion ; ne jamais s'y référer pour déterminer un numéro de migration réel, **ni pour déterminer un statut d'exécution réel** — y compris pour `01` et `02`, dont la numérotation n'a certes pas changé mais dont les statuts décrits plus bas (ligne 978 : migration 01 ; ligne 980/982 : migration 02 « NON appliquée, en attente de revue ») sont désormais **périmés** : les deux sont appliquées en production depuis (voir l'en-tête de statut en tête de document et ADR-MVP.md, seules sources canoniques du statut d'exécution réel, qui évoluent alors que ce paragraphe historique ne l'a pas suivi). En particulier : `03` désigne ici encore `ccf_mrv_project_links` (jamais appliqué sous ce numéro — `03` a depuis été verrouillé définitivement sur `03_fix_null_bypass_authorization.sql`, appliqué en production, voir ADR-MVP.md) ; ce qui est nommé `05_carbon_issuances.sql` ci-dessous correspond en réalité au fichier `07_carbon_issuances.sql` actuellement en revue (§15) ; ce qui est nommé `04_carbon_verification_outcomes.sql` correspond à l'actuel `05_carbon_verification_outcomes.sql`.

**Emplacement : `supabase/carbon_migrations_proposed/` — délibérément hors de `supabase/migrations/`**, pour qu'aucun `supabase db push` ne puisse jamais les appliquer par inadvertance ; chaque fichier reste un brouillon à lire et approuver individuellement. Numérotation logique de dépendance, pas nécessairement l'ordre d'exécution final (à reconfirmer au moment de l'application) :

| # (obsolète, voir §14 pour le # réel) | Fichier (nom obsolète) | Contenu |
|---|---|---|
| 01 | `01_carbon_foundations_events_and_failures.sql` | Extension `btree_gist`, `carbon_business_events` (append-only, catalogue complet à 31 valeurs, colonne `verification_session_id` pour la portée MRV §10bis), `carbon_rpc_failures` (journal séparé, garantie limitée précisée en §11bis), `can_view_carbon_event(p_actor_id, p_organization_id, p_aggregator_id, p_verification_session_id)` (version de base sans lecture de table — récursion RLS évitée, étendue en migration 05), RLS des deux tables, révocations de privilèges par défaut, fonction `carbon_reject_update_delete()` (renommée avec préfixe de domaine pour éviter toute collision). |
| 02 | `02_carbon_aggregator_memberships.sql` | `aggregator_memberships` historisée, `RESTRICT`, index unique partiel, RLS, `create_aggregator_with_primary_admin()`, `join_aggregator()`, `leave_aggregator()`, dépréciation de `organizations.aggregator_id`. |
| ~~03~~ | ~~`03_carbon_ccf_mrv_project_links.sql`~~ | ~~`ccf_mrv_project_links`, deux index uniques partiels, `RESTRICT`, RLS, `link_ccf_project_to_mrv()`, `unlink_ccf_project_from_mrv()`.~~ **Réel : migration 04, voir §14.** |
| ~~04~~ | ~~`04_carbon_verification_outcomes.sql`~~ | ~~Altérations `verification_sessions` (périodes, `verifier_user_id`, `EXCLUDE ... USING gist`), `is_assigned_verifier()`, `verification_outcomes` (`status`/`supersedes_outcome_id`, modèle de supersession corrigé en §12 — référence arrière, plus de blocage circulaire), `complete_verification_session()` (conversion kg→tCO2e, arrondi réel documenté par la correction 1, séquence verrou→supersession→insertion), `CREATE OR REPLACE` de `can_view_carbon_event()` (même signature à 4 paramètres) pour activer la branche vérificateur assigné via `p_verification_session_id` (§10bis).~~ **Réel : migration 05, voir §14.** |
| ~~05~~ | ~~`05_carbon_issuances.sql`~~ | ~~`credit_issuances` (`issuance_status` incluant `'voided'`, `aggregator_id`, registre externe, colonnes de preuve d'annulation externe `external_cancellation_date`/`reference`/`document_id` — portées par l'émission et non par le lot, §2 corrigé), `credit_issuance_sources` (contrainte différée + vérification amont de la correction 4), `create_credit_issuance()`, `void_credit_issuance()` (annulation interne sans preuve tant que `issuance_status NOT IN ('issued','externally_cancelled')`, preuve obligatoire sinon).~~ **Réel : migration 07 (`07_carbon_issuances.sql`, actuellement en revue §15), voir §14 — dépend aussi de la nouvelle migration 06 (`operator_and_mandates`, non prévue dans ce tableau obsolète).** |
| ~~06~~ | ~~`06_carbon_lots_commercial_cycle.sql`~~ | ~~Conversion `NUMERIC`, `credit_lots` (`commercial_status`, annulation externe désormais dépendante de `credit_issuances.issuance_status = 'externally_cancelled'` plutôt que portée localement), trigger de machine à états + verrou d'émission, `issue_credit_lot()` (verrou `FOR UPDATE`), `void_credit_lot()`.~~ **Réel : migration 08, voir §14.** |
| ~~07~~ | ~~`07_carbon_sales_financial_model.sql`~~ | ~~`credit_sales`, `credit_sale_lots` (`UNIQUE` + interdiction stricte pré-émission, correction 2), `credit_sale_costs`, `credit_sale_adjustments`, cohérence des devises (correction 6), `distribution_rules` (append-only), `credit_sale_allocations` (`allocation_type`, `rule_snapshot`), `confirm_credit_sale()`.~~ **Réel : migration 09, voir §14.** |

Chaque migration est un fichier DDL autonome (contraintes, policies RLS, RPC, révocations de privilèges, section de rollback/désactivation en commentaire) — **les tests structurels et comportementaux vivent dans un fichier séparé**, sous `supabase/carbon_migrations_proposed/tests/`, un par migration (correction reçue après revue de la migration 01 : ne jamais mélanger DDL de migration et code de test dans le même fichier). **Aucun fichier n'est exécuté automatiquement — chacun attend une lecture et une approbation explicite avant toute application manuelle**, migration puis son test associé, dans cet ordre.

**Statuts d'exécution ci-dessous : figés à leur état constaté lors de la rédaction initiale de cette section (avant la treizième revue statique), non maintenus depuis — historique uniquement, ne jamais s'y fier.** Le statut réel et actuel des migrations 01 et 02 (toutes deux **appliquées en production**) est donné en tête de document et dans ADR-MVP.md, seules sources canoniques.

**Migration 01 (révision 4) : appliquée et validée avec succès (22/22) le 14 juillet 2026, commit `4d77cda`** — voir ADR-MVP.md §12 pour le détail complet.

**Migration 02 (`02_carbon_aggregator_memberships.sql` + `tests/02_test_aggregator_memberships.sql`) — décrite ici au moment de sa rédaction, alors non appliquée ; appliquée en production depuis (voir en-tête de document et ADR-MVP.md).** Contenu : table `aggregator_memberships` historisée (`RESTRICT`, `CHECK ended_at > started_at`, index unique partiel une seule adhésion active par organisation) ; backfill depuis `organizations.aggregator_id` (approximation documentée : `started_at = organizations.created_at`, date réelle d'adhésion inconnue) ; trigger de garde n'autorisant que la transition `ended_at` NULL → valeur (`carbon_guard_aggregator_membership_update`) ; réutilisation de `carbon_reject_update_delete()` (migration 01) pour interdire tout `DELETE` ; trigger de compatibilité **transitoire** synchronisant `organizations.aggregator_id` (colonne dépréciée par `COMMENT`, conservée, non supprimée) ; RLS lecture seule ; RPC `create_aggregator_with_primary_admin()` (§9), `join_aggregator()`, `leave_aggregator()`. **Quatre décisions de conception soumises à revue** (documentées en tête du fichier de migration, préfixées D1-D4) : autorisation de `join_aggregator()` limitée à l'admin d'organisation ou au super-admin (pas d'invitation initiée par le regroupement — hors périmètre Tranche 0) ; autorisation de `leave_aggregator()` élargie à l'admin du regroupement concerné ; gestion des erreurs par `RAISE EXCEPTION` plutôt que `carbon_rpc_failures` pour ces trois RPC (cohérent avec §11bis, pas une obligation universelle) ; journalisation de `aggregator_admin_appointed` dès le bootstrap. Tests : 15 assertions structurelles, 18 comportementales, dont l'isolement réel de la branche `is_org_admin()` (pas seulement le raccourci super-admin) via une simulation de contexte JWT à deux niveaux distincts (technique standard Supabase `request.jwt.claims`).
