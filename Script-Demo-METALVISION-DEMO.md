# Script de démonstration — METALVISION-DEMO (CCF + Marché carbone, Lots 1-3)

**Projet Supabase** : METALVISION-DEMO (ref `msgesgemaasyzycielzf`) — schéma canonique identique à production (66 migrations de base + 13 migrations carbone), **aucune donnée réelle**, jamais un `supabase db reset` naïf ni une copie de dump production (cf. `ADR-MVP.md`).

**Données** : 100 % issues de `supabase/seeds/demo/01_users_and_roles.sql` → `06_sales.sql`, appliqués dans l'ordre. Les scripts sont idempotents (réexécutables sans erreur) et pilotent les vraies RPC métier (pas des INSERT bruts pour la logique complexe) — le jeu de données a donc été produit exactement comme l'application réelle l'aurait fait, y compris l'historique d'événements (`carbon_business_events`).

---

## Comptes de démonstration

Mot de passe partagé pour les 6 comptes : **communiqué séparément hors dépôt** (canal sécurisé — jamais en clair dans Git). Voir procédure de rotation dans `ADR-MVP.md`. Le script `01_users_and_roles.sql` exige que ce mot de passe lui soit fourni via la variable psql `demo_password` au moment de l'exécution ; aucune valeur n'est stockée dans les fichiers versionnés.

| Compte | Rôle | Organisation / portée |
|---|---|---|
| `superadmin@demo.metaltrace.ca` | Superadmin plateforme | Aucune organisation — rôle JWT (`app_metadata.role=admin`), voit tout |
| `operateur@demo.metaltrace.ca` | Admin de l'organisation opératrice désignée | Opérateur MetalTrace (Démo) — administre émissions, registre, ventes |
| `aggregateur@demo.metaltrace.ca` | Admin principal (primary_admin) du regroupement | Regroupement Sidérurgique Laurentides (Démo) — gouvernance, règles de distribution |
| `producteur@demo.metaltrace.ca` | Admin d'organisation membre, coordinateur CCF | Aciérie Boréale Inc. (Démo) — plus gros contributeur (450/600 tCO2e) |
| `recycleur@demo.metaltrace.ca` | Admin d'organisation membre | RecyclMétal Estrie (Démo) — second contributeur (150/600 tCO2e) |
| `verificateur@demo.metaltrace.ca` | Vérificateur accrédité MRV/carbone | Assigné à la session de vérification du projet démo |

Les 3 organisations sont déjà membres actives du même regroupement, avec mandats de commercialisation carbone accordés à l'opérateur — aucune étape d'onboarding à rejouer avant la démo.

---

## État des données au moment du seed (point de départ de la démo)

- **Lot 1 (CCF)** : 1 opportunité (« Consolidation ferroviaire — Métaux ferreux et non-ferreux »), 1 projet CCF en phase Exécution, 2 capacités qualifiées, 2 participants (Aciérie Boréale coordonnateur, RecyclMétal Estrie contributeur), 1 mandat CCF actif entre les deux.
- **Vérification MRV** : 1 session **complétée** — 620 tCO2e calculés/vérifiés, 600 tCO2e éligibles (réserve de prudence de 20 t appliquée par le vérificateur).
- **Lot 3 (crédits)** : 1 émission de 600 tCO2e au statut **issued** (registre : `DEMO-REG-2026-0001`), scindée en 2 lots — un de 400 tCO2e **vendu**, un de 200 tCO2e **disponible** (stock non vendu, volontairement laissé pour montrer l'inventaire).
- **Lot 2 (gouvernance)** : 1 règle de distribution active pour le regroupement (frais plateforme 10 %, réserve 5 %).
- **Vente** : 1 vente de 400 tCO2e à 45 $/tCO2e (brut 18 000 $, coûts 500 $ [registre + vérification], net distribuable 17 500 $), statut **confirmed** (pas encore réglée) — les 6 lignes d'allocation (revenu carbone, réserve, frais plateforme × 2 organisations) sont déjà calculées et s'additionnent exactement au montant net distribuable.

---

## Trame narrative suggérée (≈ 20-25 minutes, Lots 1 à 3)

### 1. Mise en contexte (1-2 min)

Le même problème que la démo CCF (`Script-Demo-CCF.md`) : des organisations de métaux qui coordonnent leur logistique via un regroupement. Ici on ajoute la couche suivante : ce regroupement génère des réductions d'émissions vérifiables, transformées en crédits carbone vendables sur un registre.

### 2. Lot 1 — Rappel du parcours CCF (3-4 min)

Connecté comme `producteur@demo.metaltrace.ca` (coordonnateur du projet CCF) : mêmes écrans que la démo CCF existante — Organisations, Capacités, Opportunité, Projet en exécution. Peut être raccourci si l'audience a déjà vu la démo CCF.

### 3. Lot 2 — Regroupement et gouvernance (4-5 min)

Connecté comme `aggregateur@demo.metaltrace.ca` :

- Écran **Regroupement** : montrer les 2 organisations membres actives (Aciérie Boréale, RecyclMétal Estrie) et leur adhésion.
- Écran **Distribution** (`/admin/regroupements/[aggregatorId]/distribution`) : montrer la règle active (10 % plateforme, 5 % réserve, poids 1.0) — expliquer que cette règle a été proposée par l'admin du regroupement puis approuvée en double signature (regroupement + opérateur) avant d'entrer en vigueur.
- Point de discours : c'est cette même règle qui a servi à calculer automatiquement la répartition de la vente montrée à l'étape 5.

### 4. Vérification MRV et émission de crédits (5-6 min, cœur technique)

Connecté comme `verificateur@demo.metaltrace.ca` (`/verifier-mrv`) : montrer la session complétée — 620 tCO2e calculés à partir des journaux d'activité, réserve de prudence de 20 t, rapport de vérification en preuve.

Connecté comme `operateur@demo.metaltrace.ca` (`/admin/carbon-inventory`) : montrer l'émission de 600 tCO2e (statut *issued*, référence registre `DEMO-REG-2026-0001`), sourcée à 75 % par Aciérie Boréale et 25 % par RecyclMétal Estrie — bonne illustration de l'attribution multi-organisation. Montrer les 2 lots : un vendu (400 t), un disponible (200 t) — inventaire vivant, pas figé.

### 5. Lot 3 — Vente et répartition des revenus (5-6 min)

Toujours comme `operateur@demo.metaltrace.ca` (`/admin/carbon-sales`) : ouvrir la vente confirmée vers « Fonderie ABC (Acheteur externe démo) ».

- Montrer le calcul : 400 tCO2e × 45 $ = 18 000 $ brut, moins 500 $ de coûts (frais registre + vérification) = 17 500 $ net distribuable.
- Montrer les 6 lignes d'allocation (revenu carbone, réserve, frais plateforme pour chacune des 2 organisations) et que leur somme reconstitue exactement 17 500 $ — moment fort pour démontrer la rigueur comptable du système (aucun écart d'arrondi toléré, contrainte vérifiée en base).
- **Action possible en direct** : cliquer sur « Régler la vente » (`settle_credit_sale`) — transition volontairement laissée disponible pour ce moment interactif. Prévoir un plan de retour si la démo doit être rejouée (voir procédure de reset ci-dessous).

### 6. Clôture (1-2 min)

Résumer la chaîne complète : capacité → projet CCF → vérification MRV → émission de crédits → gouvernance de la répartition → vente → allocation automatique des revenus. Mentionner que le pilote commercial fermé (Lot 4 étape 5) est l'étape suivante, hors périmètre de cette démonstration technique.

---

## Pièges à éviter

- Si « Régler la vente » est cliqué en direct, la vente passe définitivement à `settled` (les tables carbone sont **append-only** — aucune suppression ni annulation possible par l'API). Pour repartir d'un état identique avant la prochaine démo, utiliser la procédure de reset ci-dessous plutôt que d'essayer de « défaire » l'action.
- `recycleur@demo.metaltrace.ca` n'a pas de visibilité sur les écrans réservés à l'opérateur (`/admin/carbon-sales`, `/admin/carbon-inventory`) — comportement attendu (RLS), pas un bug.
- Le lot de 200 tCO2e reste volontairement invendu — ne pas le vendre par erreur pendant une démo si on veut pouvoir répéter le scénario de vente identique la fois suivante.

---

## Procédure de reset

Le domaine carbone est conçu **append-only** (aucune suppression physique via l'API, convention MVP-DA-006) — un `DELETE` naïf échoue avec « Table X est append-only ». Le script `supabase/seeds/demo/reset_demo.sql` gère cela correctement : il désactive individuellement, par leur nom exact, les triggers de garde append-only (jamais `DISABLE TRIGGER ALL`, qui casserait les contraintes FK système), supprime toutes les données de démonstration dans le bon ordre de dépendance, puis les réactive.

**Étapes pour rejouer la démo depuis un état propre :**

1. Dans le SQL Editor du projet METALVISION-DEMO (ou `psql`), exécuter `supabase/seeds/demo/reset_demo.sql`.
2. Vérifier que les tables clés sont vides (`SELECT count(*) FROM auth.users WHERE email LIKE '%@demo.metaltrace.ca'` doit retourner 0).
3. Réexécuter dans l'ordre : `01_users_and_roles.sql` → `02_organizations.sql` → `03_projects_and_verification.sql` → `04_issuances_and_lots.sql` → `05_governance.sql` → `06_sales.sql`.
4. Le résultat est identique bit pour bit au jeu de données décrit dans ce document (UUID fixes, montants déterministes).

Le reset ne touche que les entités de démonstration (préfixe d'e-mail `@demo.metaltrace.ca`, UUID fixes du seed, ou entités liées par nom/organisation) — sans risque pour d'autres données si jamais le projet en contenait.
