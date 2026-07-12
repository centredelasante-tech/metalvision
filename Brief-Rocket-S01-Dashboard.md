# Brief Rocket — Écran S01 (`/`, Dashboard complet)

**Contexte :** le backend a été revu et ne nécessite **aucune correction, aucune nouvelle table, aucune nouvelle migration** (`ADR-MVP.md` §9septdecies) — toutes les données nécessaires (`ccf_projects`, `documents`, `mandates`, `business_events`) existent déjà et sont déjà protégées par RLS.

**Avant de commencer : `git pull`/`git reset --hard origin/main` avant de créer votre branche.** 6 livraisons consécutives (S06, S07, S08, deux fois S05, S09) ont chacune contenu la réintroduction accidentelle de bugs déjà corrigés — toujours le même contenu périmé. La revue de ce PR fera, comme les précédentes, un diff fichier par fichier de la branche complète.

---

## 1. Clarification de portée essentielle — lisez avant de commencer

**La route `/` existe déjà** (`src/app/page.tsx` → `ClientDashboardContent`) mais elle est **entièrement dédiée au domaine MRV/lots préexistant** (`ClientKPIGrid`, `RecentLotsTable`, `ContainerGrid`, `ClientQuickActions` — lots, conteneurs, factures). C'est un domaine métier distinct, sans rapport avec MetalTrace CCF.

**Ne touchez à aucun de ces composants existants.** Votre tâche : ajouter une **nouvelle section CCF** à `ClientDashboardContent`, insérée **après** les sections MRV existantes (après `RecentLotsTable`/`ContainerGrid`), sans les retirer, les modifier ou les réorganiser.

Référence backlog : S01, « Cartes KPI, alertes, projets actifs, documents incomplets, événements récents » (M3 complet).

## 2. Cartes KPI (4 cartes)

Réutilisez le style de `MetricCard` déjà utilisé par `ClientKPIGrid` pour la cohérence visuelle.

| Carte | Source |
|---|---|
| Projets actifs | `count(ccf_projects)` où `phase != 'closed'`, visibles selon la RLS déjà en place (coordinateur ou participant actif) |
| Documents en attente | `count(documents)` où `status IN ('draft', 'submitted')`, visibles selon la RLS documents |
| Mandats en attente | `count(mandates)` où `status = 'pending_acceptance'`, où l'organisation de l'utilisateur est `issuer_org_id` **ou** `receiver_org_id` |
| Événements (7 derniers jours) | `count(business_events)` où `created_at >= now() - interval '7 days'`, visibles selon la RLS déjà en place |

## 3. Alertes

Liste combinée de signaux **déjà définis ailleurs dans le MVP** — ne réinventez aucune nouvelle notion de risque :

- Étapes logistiques `blocked` (tous projets visibles, pas un seul — donc **n'utilisez pas** `computeProjectRisks` tel quel, qui est scopé à un projet ; interrogez `logistics_steps` directement sans filtre `project_id`).
- Projets avec `target_end_date` dépassée et `phase != 'closed'`.
- Documents `rejected` des 7 derniers jours.
- Mandats `active` dont `end_date` est à moins de 14 jours (échéance proche).

Chaque alerte doit permettre de naviguer vers l'objet concerné (`/projets/:id`, `/documents`, `/mandats`).

## 4. Projets actifs (liste)

`ccf_projects` où `phase != 'closed'`, triés par `target_end_date` (les plus proches d'abord), badge de phase, lien vers `/projets/:id`.

## 5. Documents incomplets (liste)

`documents` où `status IN ('draft', 'submitted')`, triés par `created_at` DESC, limité à ~10, lien vers `/documents`.

## 6. Événements récents (liste)

Derniers `business_events`, **tous types d'objets confondus** (pas un seul projet/document) — donc **n'utilisez pas `ObjectTimeline`** tel quel (il est conçu pour un objet unique via `object_type`/`object_id`). Vous pouvez vous inspirer de sa présentation (`EventTypeBadge` de `src/components/ObjectTimeline.tsx`, déjà exporté et réutilisable) mais la requête ne doit filtrer que par organisation/visibilité RLS, pas par objet. Limité à ~10, lien vers `/evenements` pour le journal complet.

## 7. Ce qu'il ne faut pas faire

- Ne modifiez pas `ClientKPIGrid`, `RecentLotsTable`, `ContainerGrid`, `ClientQuickActions` — domaine MRV hors périmètre.
- Pas de nouvelle table, migration, ou policy RLS.
- Pas d'écriture — écran en lecture seule, aucune insertion `business_events`.
- N'utilisez pas `computeProjectRisks`/`ObjectTimeline` tels quels — ils sont scopés à un seul projet/objet, ce dashboard doit agréger à travers tous les projets/objets visibles.

## 8. Avant de livrer

PR revue selon `ROCKET_REVIEW_CHECKLIST.md` avant fusion, comme pour chaque écran précédent.
