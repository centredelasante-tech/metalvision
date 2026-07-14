# MVP Carbone / Regroupements — proposition de portée par tranches

**Statut** : proposition de planification, aucune migration ni code écrit. À valider/ajuster avant de démarrer la tranche 1.

**Fondation** : basé sur l'audit complet du domaine (`ADR-MVP.md` §9tertricies), confirmé vide en production (0 ligne sur les 9 tables Agrégateurs) — aucune contrainte de migration de données réelles, liberté complète pour adapter le schéma.

**Rappel du parcours cible :** Projet CCF → calcul MRV → preuves → vérification complétée → quantité admissible validée → regroupement → lot de crédits → vente → frais de plateforme → allocation aux membres.

**Rappel des deux trous structurels confirmés (voir audit) :**
1. `ccf_projects` et `projects` (MRV) sont deux tables étanches — aucun lien.
2. Rien ne relie une vérification complétée à une quantité de crédits admissible.

---

## Tranche 1 — Regroupements (fondation)

**Ce qui existe déjà, à réutiliser tel quel :** tables `aggregators`, `aggregator_admins`, fonctions `is_aggregator_admin()`, `is_aggregator_primary_admin()`, RPC `transfer_aggregator_primary_admin()` — gouvernance déjà plus mûre que la moyenne du reste du projet.

**À construire (écrans seulement, pas de migration) :**
- Écran de création d'un regroupement (nom, description) — réservé au super-admin plateforme.
- Écran de gestion des admins du regroupement (nomination, révocation, transfert de rôle primary_admin) — réutilise les RPC existantes.
- Vue liste des regroupements avec leurs organisations membres.

**Minimal pour un premier pilote :** un seul regroupement créé manuellement (via le super-admin), un seul primary_admin nommé. Pas besoin d'un écran de création en libre-service dès le départ — un formulaire simple suffit.

---

## Tranche 2 — Rattachement des organisations et projets CCF

**À construire :**
- Écran (ou action admin) pour rattacher une organisation existante à un regroupement (écrire `organizations.aggregator_id`) — actuellement aucune UI ne le fait.
- Écran de gestion des unités opérationnelles (`operational_units`) par organisation.
- **Le vrai chantier de cette tranche — combler le trou structurel n°1 :** créer le lien entre `ccf_projects` et `projects` (MRV). Deux options à trancher :
  - **Option A (recommandée pour le MVP)** : ajouter une colonne `ccf_projects.mrv_project_id` (nullable, FK vers `projects`) — un projet CCF peut optionnellement être associé à un projet de mesure carbone. Simple, réversible, n'affecte aucun projet CCF existant qui n'a pas de volet carbone.
  - Option B : fusionner conceptuellement les deux modèles — **non recommandée**, contredit `MVP-DA-013` (décision déjà prise de les garder distincts) et casserait potentiellement le parcours CCF déjà stabilisé.

**Première migration réelle de ce chantier** (petite, additive, sans risque pour les données existantes — confirmé 0 ligne partout) : ajout de la colonne de liaison.

---

## Tranche 3 — Calcul et consolidation des réductions d'émissions

**Ce qui existe déjà, à réutiliser :** `/api/ghg/calculate` (calcul baseline vs projet), `project_activity_logs` (journal des activités MRV), agrégation déjà démontrée dans `/api/projects/[id]/iso-report` (sommes des réductions).

**À construire :** un mécanisme de consolidation qui persiste un total (pas seulement calculé à la volée) — par exemple une colonne `projects.total_reduction_verified_tco2e`, mise à jour uniquement quand une vérification est complétée (voir tranche 4). Sans ça, il n'y a rien de stable à référencer pour émettre un lot de crédits.

---

## Tranche 4 — Vérification

**Ce qui existe déjà, à réutiliser tel quel :** `verification_sessions`, écrans `admin-verification-sessions`/`verifier-mrv`, RLS à 3 rôles déjà fonctionnelle.

**Le vrai chantier de cette tranche — combler le trou structurel n°2 :** aujourd'hui rien ne relie `verification_sessions.status = 'completed'` à une quantité admissible. Ajouter une colonne `verification_sessions.verified_reduction_tco2e` (rempli par le vérificateur à la complétion), et une contrainte/trigger qui empêche un `credit_lot` d'être créé pour un projet sans au moins une session de vérification complétée avec une quantité renseignée.

**Minimal pour un premier pilote :** la quantité peut être saisie manuellement par le vérificateur à la complétion (pas besoin d'automatiser le calcul exact tout de suite) — l'important est que ce soit **une donnée officiellement validée et tracée**, pas que le calcul soit sophistiqué dès le jour un.

---

## Tranche 5 — Création des lots de crédits

**Ce qui existe déjà, à réutiliser tel quel :** table `credit_lots`, RLS déjà fonctionnelle.

**À construire :** écran de génération d'un lot de crédits à partir d'un projet MRV vérifié (visible seulement si la tranche 4 confirme une quantité admissible), avec la contrainte de la tranche 4 appliquée.

---

## Tranche 6 — Vente et répartition des revenus

**Ce qui existe déjà, à réutiliser tel quel :** `credit_sales`, `credit_sale_lots`, `distribution_rules` (modèle `rule_type` + `parameters` JSONB, flexible), `member_distribution_overrides`, `credit_sale_allocations` — toutes structurellement saines.

**À abandonner intégralement et réécrire :** `/api/aggregator/calculate-sale/route.ts` et `src/lib/distribution-calculator.ts` — leur modèle de données ne correspond à rien de réel (déjà documenté dans l'audit). Réécriture nécessaire contre le vrai schéma (`rule_type`/`parameters`, pas des colonnes fixes inexistantes).

**À construire :** écran de saisie d'une vente (association des lots, prix), calcul de répartition basé sur les vraies colonnes, écran de consultation des allocations par organisation membre.

**Ajout d'une contrainte manquante identifiée dans l'audit :** `UNIQUE(credit_sale_id, organization_id)` sur `credit_sale_allocations`, pour que l'upsert de la nouvelle route fonctionne proprement.

---

## Événements métier

Décision déjà prise (§9tertricies) : catalogue distinct `carbon_event_type` + table `carbon_business_events`, pas d'extension de `ccf_event_type`. Événements minimaux identifiés : `carbon_project_created`, `verification_started`, `verification_completed`, `credit_lot_created`, `credit_lot_issued`, `credit_sale_recorded`, `credit_sale_allocated`. À créer en même temps que la tranche correspondante, pas tout d'un coup au départ.

---

## Ce qui rend chaque tranche « minimale mais commercialisable »

Le principe directeur : à la fin de chaque tranche, quelque chose de réel et démontrable existe — pas une fondation invisible. Après la tranche 2, on peut montrer « une organisation appartient à un regroupement et son projet CCF a un volet carbone associé ». Après la tranche 4, on peut montrer « une réduction d'émissions a été officiellement vérifiée ». Après la tranche 6, on peut montrer un cycle complet : vérification → crédit → vente → argent réparti — ce qui est probablement le jalon qui justifie de parler de « monétisation » à un partenaire ou au Ministère.

## Prochaine étape suggérée

Valider ou ajuster cette portée tranche par tranche (surtout les deux points de migration réelle : lien `ccf_projects`↔`projects`, et quantité vérifiée sur `verification_sessions`), puis commencer par la tranche 1 — la moins risquée, aucune migration requise, uniquement des écrans sur un socle déjà solide.
