# Tranche 0 — Architecture du chantier carbone (v4 + corrections finales)

**Statut : validée comme architecture cible par l'utilisateur, sous réserve des 7 corrections techniques finales ci-dessous.** Aucune migration exécutée — les migrations sont désormais préparées comme fichiers séparés, numérotés, révisables (voir `supabase/carbon_migrations_proposed/`), sans exécution ni fusion automatique.

---

## Corrections finales (avant préparation des migrations)

**1. Règle d'arrondi PostgreSQL — erreur de fait corrigée.** Le document affirmait que `ROUND(numeric, int)` utilise l'arrondi bancaire (« round half to even ») par défaut en PostgreSQL — **c'est faux**. Le comportement réel de `ROUND()` sur le type `numeric` est l'arrondi arithmétique standard (« round half away from zero » : 0,5 arrondit toujours vers le haut en valeur absolue). `complete_verification_session()` (§3/§4 migration) documente désormais explicitement ce comportement réel plutôt que le comportement erroné précédemment cité — aucun changement de fonction nécessaire, seulement une correction de la documentation pour qu'une future implémentation ne présume pas d'un comportement inexistant.

**2. Interdiction stricte des ventes avant émission officielle, sans ambiguïté produit.** La v4 laissait ouverte la possibilité future de vendre une « réduction admissible non encore émise » comme un second produit commercial distinct — supprimé. **Décision MVP, sans exception** : `credit_sale_lots` ne peut référencer un `credit_lot` que si l'émission parente a `issuance_status = 'issued'`, vérifié par un trigger dédié sur `credit_sale_lots` **en plus** (défense en profondeur, pas en remplacement) du verrou déjà existant sur `commercial_status` (§1 v4, un lot ne quitte `unavailable` que si `issued`). Toute vente d'une réduction pré-émission est explicitement hors périmètre de ce MVP, pas simplement non implémentée.

**3. Mécanique de supersession de `verification_outcomes`, précisée.** Modèle officiel (voir §12) : `status TEXT CHECK (status IN ('active','superseded'))` + `supersedes_outcome_id` référençant **vers l'arrière** (le nouveau résultat référence l'ancien qu'il remplace, jamais l'inverse). Quand `complete_verification_session()` est appelée pour une session ayant déjà un résultat actif : `p_adjustment_reason` devient **obligatoire** (pas seulement au-delà d'un seuil, comme c'était le cas pour un premier résultat) ; la RPC verrouille l'ancien résultat (`SELECT ... FOR UPDATE`), le transitionne à `status = 'superseded'`, puis insère le nouveau résultat avec `status = 'active'` et `supersedes_outcome_id` pointant vers l'ancien — le tout dans une seule transaction. Le trigger d'immutabilité est donc précisé : il rejette tout changement sauf la transition de `status` de `'active'` vers `'superseded'` (jamais l'inverse, jamais une deuxième fois, `'superseded'` terminal).

**4. Validation explicite qu'une émission a au moins une source.** Le contrôle différé (§4 v4) rejette déjà indirectement une émission sans source cohérente (la somme ne peut égaler `issued_quantity_tco2e > 0` si aucune ligne n'existe), mais `create_credit_issuance()` ajoute désormais une vérification amont explicite — rejet immédiat et lisible si `p_sources` est vide ou nul, avant toute tentative d'insertion, en plus de (pas à la place de) la contrainte différée qui reste le filet de sécurité structurel.

**5. Séparation des journaux d'échec et des événements métier.** `carbon_business_events` ne contient désormais **que** des événements métier réussis. Les refus d'autorisation et échecs de validation des RPC sont consignés dans une table distincte, `carbon_rpc_failures` — audience et politique de rétention différentes (revue de sécurité vs audit métier), ne polluent jamais le fil d'événements métier.

**6. Cohérence des devises.** Aucune conversion automatique dans ce MVP — un trigger sur `credit_sale_costs` et `credit_sale_allocations` rejette toute ligne dont `currency` diffère de `credit_sales.currency` pour la même vente.

**7. Catalogue d'événements complété.** Voir le catalogue exhaustif dans la migration 01 (§ fondations transverses) — couvre désormais chaque entité/transition introduite en v2-v4 (regroupements, liens CCF-MRV, sessions/résultats de vérification avec supersession, émissions avec leurs 5 statuts, lots commerciaux, ventes/coûts/ajustements/allocations).

---

## 1. Séparer réellement le cycle d'émission du cycle commercial (deux champs de statut, pas une table qui les mélange encore)

**Ce que la v3 n'avait pas résolu** : scinder en deux tables (`credit_issuances`/`credit_lots`) ne suffit pas si `credit_issuances` n'a qu'un booléen `is_voided` — il manque une vraie machine à états réglementaire, et rien n'empêchait un lot commercial de devenir `available`/`sold` alors que son émission sous-jacente n'a jamais été confirmée par un registre externe.

**Décision : deux champs de statut explicites, sur les deux tables respectives.**

```
credit_issuances.issuance_status TEXT NOT NULL DEFAULT 'internal'
  CHECK (issuance_status IN ('internal','eligible','submitted','issued','externally_cancelled','voided'))

credit_lots.commercial_status TEXT NOT NULL DEFAULT 'unavailable'
  CHECK (commercial_status IN ('unavailable','available','reserved','sold','retired','voided'))
```
(`commercial_status` remplace `status` — renommage pour lever toute ambiguïté avec `issuance_status`. `issuance_status` porte désormais deux terminaux distincts et non ambigus, corrigeant une incohérence relevée après revue : `'voided'` = annulation **interne**, avant toute confirmation par un registre externe, libère la quantité sans preuve requise ; `'externally_cancelled'` = le registre externe a lui-même annulé une émission déjà `'issued'`, traité au niveau du lot commercial via les champs `external_cancellation_*` du §2, preuve obligatoire.)

**Règle d'invariant, trigger sur `credit_lots`** : `commercial_status` ne peut quitter `'unavailable'` que si `credit_issuances.issuance_status = 'issued'` pour l'émission parente. Un lot reste `unavailable` par défaut tant que son émission n'est pas confirmée par le registre — impossible de le vendre en tant que crédit officiellement émis avant ce moment.

**Garde structurelle empêchant une émission sans sources de progresser (correction ajoutée après revue)** : un trigger `BEFORE UPDATE ON credit_issuances` rejette toute tentative de faire passer `issuance_status` de `'internal'` vers `'eligible'`, `'submitted'` ou `'issued'` si aucune ligne `credit_issuance_sources` n'existe pour cette émission, ou si leur somme ne correspond pas encore à `issued_quantity_tco2e`. Redondant par conception avec la contrainte différée du §4 et la vérification amont de `create_credit_issuance()` (§4, correction 4) — trois mécanismes indépendants pour le même invariant, à des moments différents (création de source, changement de statut, appel RPC), cohérent avec le principe de défense en profondeur déjà appliqué ailleurs dans ce document.

**Interdiction stricte des ventes avant émission officielle, sans ambiguïté produit (corrigé après revue — remplace une formulation ambiguë antérieure)** : `credit_sale_lots` ne peut référencer un `credit_lot` que si `issuance_status = 'issued'` pour l'émission parente — vérifié par un trigger dédié sur `credit_sale_lots` (migration 07), **en plus** du verrou déjà existant sur `commercial_status` ci-dessus (défense en profondeur, pas redondance inutile). Aucune vente d'une réduction pré-émission n'est permise dans ce MVP — exclusion de portée assumée, pas une limitation temporaire à lever plus tard sans decision explicite.

---

## 2. `voided` ne libère pas automatiquement la quantité si le lot a déjà été émis extérieurement

**Erreur de condition trouvée après revue et corrigée** : la règle précédente testait `issuance_status != 'issued'` pour décider si une preuve externe était requise — mais `'externally_cancelled' != 'issued'` est vrai littéralement, alors que `'externally_cancelled'` représente précisément le cas où le registre **a** confirmé l'annulation après une émission officielle — c'est exactement le cas qui doit exiger une preuve, pas celui qui doit en être dispensé.

**Décision corrigée, énumération explicite plutôt qu'une négation ambiguë :**
```
issuance_status IN ('internal','eligible','submitted','voided')
  → annulation interne possible sans preuve externe (l'émission n'a jamais été confirmée par un registre).

issuance_status IN ('issued','externally_cancelled')
  → preuve d'annulation externe obligatoire avant de libérer la quantité.
```

**Les champs de preuve appartiennent à `credit_issuances`, pas à `credit_lots`** (correction de placement après revue) — puisque `externally_cancelled` est un état de l'émission réglementaire elle-même (§1), la preuve de son annulation est une donnée de l'émission, pas de chacune de ses subdivisions commerciales :
```
credit_issuances
  external_cancellation_date        DATE NULL
  external_cancellation_reference   TEXT NULL
  external_cancellation_document_id UUID NULL REFERENCES documents(id)
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

**10bis. Portée MRV manquante dans la RLS de `carbon_business_events` — corrigée après revue.** La policy `carbon_business_events_select` initiale (§ci-dessous, migration 01) ne couvre que : super-admin plateforme, acteur de l'événement, membre de l'organisation, admin du regroupement. Elle omet un cas réel : **un vérificateur assigné à une session, qui n'est ni l'acteur de l'événement ni membre de l'organisation concernée**, doit néanmoins pouvoir consulter les événements liés à cette session (ex. `verification_outcome_recorded`, `verification_outcome_superseded`).

Correction retenue : ajouter une colonne `verification_session_id UUID NULL REFERENCES verification_sessions(id) ON DELETE RESTRICT` à `carbon_business_events`, renseignée par toute RPC émettant un événement du domaine vérification, et centraliser la logique de lecture dans une fonction unique plutôt que de faire grossir indéfiniment le `USING` inline de la policy.

**Récursion RLS potentielle, corrigée après revue.** Une première version de cette fonction prenait `p_event_id UUID` en unique paramètre et relisait elle-même la ligne (`SELECT ... FROM carbon_business_events WHERE id = p_event_id`) pour en extraire `actor_id`/`organization_id`/`aggregator_id`. Or cette lecture, exécutée par une fonction `SECURITY INVOKER` appelée depuis la policy `SELECT` de **cette même table**, est elle-même soumise à cette policy — qui rappelle la fonction. Risque réel de récursion RLS. Corrigé en supprimant toute lecture de table à l'intérieur de la fonction : la signature retenue est **`can_view_carbon_event(p_actor_id UUID, p_organization_id UUID, p_aggregator_id UUID, p_verification_session_id UUID) RETURNS BOOLEAN`**, appelée par la policy avec les colonnes de la ligne déjà en cours d'évaluation (`actor_id`, `organization_id`, `aggregator_id`, `verification_session_id`) — aucun accès à `carbon_business_events` depuis l'intérieur de la fonction, donc aucune récursion possible.

**Séquencement délibéré entre migrations 01 et 04** — `is_assigned_verifier()` et `verification_sessions.verifier_user_id` n'existent qu'à partir de la migration 04 ; la migration 01 ne peut donc pas y référer sans créer une dépendance en avant. Solution : `can_view_carbon_event()` est créée dès la migration 01 dans une **version de base** (super-admin, acteur, organisation, regroupement — strictement équivalente à la policy inline qu'elle remplace, aucun comportement nouveau à ce stade), avec `p_verification_session_id` déjà présent dans la signature mais inutilisé, explicitement commentée comme *« à étendre par la migration 04 »*. La migration 04 fait un `CREATE OR REPLACE FUNCTION public.can_view_carbon_event(...)` (même signature) qui ajoute la branche `p_verification_session_id IS NOT NULL AND public.is_assigned_verifier(p_verification_session_id)`, sans toucher à la policy elle-même (qui appelle déjà la fonction avec les 4 paramètres depuis la migration 01) ni à sa signature. Ce découpage évite toute référence à un objet pas encore créé tout en gardant un seul point d'autorisation à maintenir, sans relecture de table.

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
  calculated_reduction_tco2e       NUMERIC(14,4) NOT NULL
  verified_reduction_tco2e         NUMERIC(14,4) NOT NULL CHECK (verified_reduction_tco2e >= 0)
  eligible_tco2e                   NUMERIC(14,4) NOT NULL CHECK (eligible_tco2e >= 0 AND eligible_tco2e <= verified_reduction_tco2e)
  verification_report_document_id  UUID REFERENCES documents(id)
  verified_by                      UUID NOT NULL REFERENCES profiles(id)
  verified_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
  adjustment_reason                TEXT NULL
  created_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
```

`supersedes_outcome_id` pointe **vers l'arrière** (le nouveau résultat référence l'ancien qu'il remplace), jamais vers l'avant — ce qui élimine la dépendance circulaire. `UNIQUE (verification_session_id) WHERE status = 'active'` — un seul résultat actif à la fois par session.

**Séquence correcte de `complete_verification_session()` en cas de supersession, dans une seule transaction :**
1. `SELECT ... FOR UPDATE` sur le résultat actif existant de cette session (verrou, cohérent avec le principe de verrouillage déjà établi §6 v2).
2. `UPDATE verification_outcomes SET status = 'superseded' WHERE id = <ancien>` — libère l'index unique partiel.
3. `INSERT INTO verification_outcomes (..., status, supersedes_outcome_id) VALUES (..., 'active', <ancien>.id)` — peut maintenant s'insérer sans conflit, puisque l'ancien n'est plus `'active'`.

Si l'étape 3 échoue pour une raison quelconque (contrainte violée, erreur), toute la transaction s'annule automatiquement — l'étape 2 (passage de l'ancien à `'superseded'`) est annulée avec elle, l'ancien résultat redevient actif comme si de rien n'était. Aucun état intermédiaire incohérent ne peut être committé.

**Immuable après création, sauf `status`** (trigger) — `status` ne peut transitionner que de `'active'` vers `'superseded'`, jamais l'inverse, jamais une deuxième fois (`'superseded'` est terminal).

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

## Plan des migrations proposées

**Emplacement : `supabase/carbon_migrations_proposed/` — délibérément hors de `supabase/migrations/`**, pour qu'aucun `supabase db push` ne puisse jamais les appliquer par inadvertance ; chaque fichier reste un brouillon à lire et approuver individuellement. Numérotation logique de dépendance, pas nécessairement l'ordre d'exécution final (à reconfirmer au moment de l'application) :

| # | Fichier | Contenu |
|---|---|---|
| 01 | `01_carbon_foundations_events_and_failures.sql` | Extension `btree_gist`, `carbon_business_events` (append-only, catalogue complet à 31 valeurs, colonne `verification_session_id` pour la portée MRV §10bis), `carbon_rpc_failures` (journal séparé, garantie limitée précisée en §11bis), `can_view_carbon_event(p_actor_id, p_organization_id, p_aggregator_id, p_verification_session_id)` (version de base sans lecture de table — récursion RLS évitée, étendue en migration 04), RLS des deux tables, révocations de privilèges par défaut, fonction `carbon_reject_update_delete()` (renommée avec préfixe de domaine pour éviter toute collision). |
| 02 | `02_carbon_aggregator_memberships.sql` | `aggregator_memberships` historisée, `RESTRICT`, index unique partiel, RLS, `create_aggregator_with_primary_admin()`, `join_aggregator()`, `leave_aggregator()`, dépréciation de `organizations.aggregator_id`. |
| 03 | `03_carbon_ccf_mrv_project_links.sql` | `ccf_mrv_project_links`, deux index uniques partiels, `RESTRICT`, RLS, `link_ccf_project_to_mrv()`, `unlink_ccf_project_from_mrv()`. |
| 04 | `04_carbon_verification_outcomes.sql` | Altérations `verification_sessions` (périodes, `verifier_user_id`, `EXCLUDE ... USING gist`), `is_assigned_verifier()`, `verification_outcomes` (`status`/`supersedes_outcome_id`, modèle de supersession corrigé en §12 — référence arrière, plus de blocage circulaire), `complete_verification_session()` (conversion kg→tCO2e, arrondi réel documenté par la correction 1, séquence verrou→supersession→insertion), `CREATE OR REPLACE` de `can_view_carbon_event()` (même signature à 4 paramètres) pour activer la branche vérificateur assigné via `p_verification_session_id` (§10bis). |
| 05 | `05_carbon_issuances.sql` | `credit_issuances` (`issuance_status` incluant `'voided'`, `aggregator_id`, registre externe, colonnes de preuve d'annulation externe `external_cancellation_date`/`reference`/`document_id` — portées par l'émission et non par le lot, §2 corrigé), `credit_issuance_sources` (contrainte différée + vérification amont de la correction 4), `create_credit_issuance()`, `void_credit_issuance()` (annulation interne sans preuve tant que `issuance_status NOT IN ('issued','externally_cancelled')`, preuve obligatoire sinon). |
| 06 | `06_carbon_lots_commercial_cycle.sql` | Conversion `NUMERIC`, `credit_lots` (`commercial_status`, annulation externe désormais dépendante de `credit_issuances.issuance_status = 'externally_cancelled'` plutôt que portée localement), trigger de machine à états + verrou d'émission, `issue_credit_lot()` (verrou `FOR UPDATE`), `void_credit_lot()`. |
| 07 | `07_carbon_sales_financial_model.sql` | `credit_sales`, `credit_sale_lots` (`UNIQUE` + interdiction stricte pré-émission, correction 2), `credit_sale_costs`, `credit_sale_adjustments`, cohérence des devises (correction 6), `distribution_rules` (append-only), `credit_sale_allocations` (`allocation_type`, `rule_snapshot`), `confirm_credit_sale()`. |

Chaque migration est un fichier DDL autonome (contraintes, policies RLS, RPC, révocations de privilèges, section de rollback/désactivation en commentaire) — **les tests structurels et comportementaux vivent dans un fichier séparé**, sous `supabase/carbon_migrations_proposed/tests/`, un par migration (correction reçue après revue de la migration 01 : ne jamais mélanger DDL de migration et code de test dans le même fichier). **Aucun fichier n'est exécuté automatiquement — chacun attend une lecture et une approbation explicite avant toute application manuelle**, migration puis son test associé, dans cet ordre.

**Migration 01 (révision 4) : appliquée et validée avec succès (22/22) le 14 juillet 2026, commit `4d77cda`** — voir ADR-MVP.md §12 pour le détail complet (objets créés, résultat, confirmation qu'aucune migration suivante n'est appliquée).

**Migration 02 (`02_carbon_aggregator_memberships.sql` + `tests/02_test_aggregator_memberships.sql`) : rédigée, NON appliquée, en attente de revue.** Contenu : table `aggregator_memberships` historisée (`RESTRICT`, `CHECK ended_at > started_at`, index unique partiel une seule adhésion active par organisation) ; backfill depuis `organizations.aggregator_id` (approximation documentée : `started_at = organizations.created_at`, date réelle d'adhésion inconnue) ; trigger de garde n'autorisant que la transition `ended_at` NULL → valeur (`carbon_guard_aggregator_membership_update`) ; réutilisation de `carbon_reject_update_delete()` (migration 01) pour interdire tout `DELETE` ; trigger de compatibilité **transitoire** synchronisant `organizations.aggregator_id` (colonne dépréciée par `COMMENT`, conservée, non supprimée) ; RLS lecture seule ; RPC `create_aggregator_with_primary_admin()` (§9), `join_aggregator()`, `leave_aggregator()`. **Quatre décisions de conception soumises à revue** (documentées en tête du fichier de migration, préfixées D1-D4) : autorisation de `join_aggregator()` limitée à l'admin d'organisation ou au super-admin (pas d'invitation initiée par le regroupement — hors périmètre Tranche 0) ; autorisation de `leave_aggregator()` élargie à l'admin du regroupement concerné ; gestion des erreurs par `RAISE EXCEPTION` plutôt que `carbon_rpc_failures` pour ces trois RPC (cohérent avec §11bis, pas une obligation universelle) ; journalisation de `aggregator_admin_appointed` dès le bootstrap. Tests : 15 assertions structurelles, 18 comportementales, dont l'isolement réel de la branche `is_org_admin()` (pas seulement le raccourci super-admin) via une simulation de contexte JWT à deux niveaux distincts (technique standard Supabase `request.jwt.claims`).

Prêts pour lecture et approbation (`02_carbon_aggregator_memberships.sql` et `tests/02_test_aggregator_memberships.sql`) — **non exécutés, en attente de décision explicite.**
