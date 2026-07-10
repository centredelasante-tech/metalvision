# ADR-MVP — Décisions d'Architecture et Dette Technique Connue
## MetalTrace MVP — Domaine CCF (Centre de Consolidation Ferroviaire)

**Version** : 1.0  
**Date** : 2026-07-10  
**Auteur** : Architecture MetalTrace  
**Statut** : Actif

---

## Contexte

Ce document enregistre les décisions d'architecture prises lors de la génération des migrations CCF-001 à CCF-011, ainsi que la dette technique connue identifiée lors du rapport de validation d'architecture (rapport pré-migration du 2026-07-10).

---

## Décisions d'Architecture Appliquées

### DA-CCF-01 — Renommage companies → organizations (RT-03)

**Décision** : La table `companies` existante a été renommée en `organizations` et `company_members` en `organization_members`. L'ENUM `company_member_role` a été renommé en `org_role`.

**Ordre d'exécution non négociable** (migration CCF-002) :
1. **1a** — Renommer tables et type ENUM
2. **1b** — Ajouter nouvelles colonnes (AVANT de toucher aux valeurs d'enum)
3. **1c** — Recopier la notion "terrain" dans `operational_profile` (AVANT de renommer les valeurs d'enum)
4. **1d** — Renommer les valeurs d'enum (`owner` → `admin`, `terrain` → `membre`)

**Justification** : Si l'étape 1c est exécutée après 1d, l'information de qui était "terrain" est perdue — il n'y a plus de valeur 'terrain' dans `org_role` pour filtrer.

**Impact** : Les fonctions `is_company_member()`, `is_company_owner()`, `company_has_no_members()` ont été adaptées pour pointer vers les tables renommées, **sans changer leurs noms**, pour ne pas casser les policies existantes du domaine Regroupements/MRV.

---

### DA-CCF-02 — Table ccf_projects au lieu de projects (RT-01/RT-02)

**Décision** : La table `projects` existante (domaine MRV ISO 14064) et son ENUM `project_status` (`draft`, `active`, `verified`) ne sont pas touchés. Le domaine collaboratif utilise la table `ccf_projects` avec ses propres colonnes.

**Justification** : Ces deux tables sont des objets métier fondamentalement différents (MRV ISO vs. projet collaboratif CCF). Elles ne peuvent pas coexister sous le même nom.

---

### DA-CCF-03 — Fonctions RLS dans le schéma public (RT-04)

**Décision** : `public.user_org_ids()` et `public.user_project_ids()` sont créées dans le schéma `public`, pas `auth`.

**Justification** : Supabase peut restreindre les modifications du schéma `auth`. Toutes les fonctions helper existantes sont dans `public`. La cohérence est préférable.

**Référence** : Migration CCF-009.

---

### DA-CCF-04 — TEXT + CHECK par table, aucun ENUM partagé (RT-05)

**Décision** : Chaque table gouvernée a sa propre contrainte `CHECK (status IN (...))` sur une colonne `text`. Aucun ENUM `status` générique n'est créé.

**Justification** : En PostgreSQL, un ENUM est un type unique avec une liste fixe de valeurs. Il ne peut pas avoir des valeurs différentes par table. Un ENUM `status` unique ne peut pas couvrir simultanément `draft/active/suspended/archived` (organizations) ET `draft/pending_acceptance/active/expired/revoked` (mandates).

---

### DA-CCF-05 — Seed de démo isolé hors migrations (RT-06)

**Décision** : Le jeu de données pilote CCF est dans `supabase/seeds/demo_ccf.sql`, jamais dans `supabase/migrations/`.

**Justification** : Le pipeline CI/CD standard applique automatiquement les migrations. Un seed dans `migrations/` serait injecté en production.

**Application manuelle** :
```bash
psql $DATABASE_URL -f supabase/seeds/demo_ccf.sql
```

---

### DA-CCF-06 — Validation de mandates.permissions.actions[] par trigger (RT-07)

**Décision** : Un trigger `BEFORE INSERT OR UPDATE` sur `mandates` valide que chaque élément du tableau JSONB `permissions.actions` existe dans la table de référence `mandate_actions`.

**Justification** : La validation applicative seule est insuffisante pour un système gouverné. Le trigger garantit l'intégrité au niveau base de données.

**Référence** : Migration CCF-003, fonction `public.validate_mandate_permissions()`.

---

### DA-CCF-07 — Ordre inversé migrations 007 et 008 (décision 7)

**Décision** : `logistics_steps` et `value_reports` (migration CCF-007) sont créés AVANT `business_events` et `audit_logs` (migration CCF-008).

**Justification** : `business_events.object_type` référence `logistics_step` et `value_report` comme cibles valides. Ces tables doivent exister avant que la contrainte CHECK soit définie.

---

### DA-CCF-08 — Séparation explicite des domaines RLS

**Décision** : Les policies du domaine CCF n'appellent JAMAIS `is_company_member()` ni les fonctions du domaine Regroupements/MRV. Elles utilisent exclusivement :
- `public.is_organization_member(UUID)` — alias mince créé en CCF-002
- `public.is_organization_owner(UUID)` — alias mince créé en CCF-002
- `public.user_org_ids()` — créée en CCF-009
- `public.user_project_ids()` — créée en CCF-009

**Justification** : Une policy du domaine CCF qui appellerait accidentellement `is_company_member()` créerait une fuite de données inter-domaines.

---

### DA-CCF-09 — operational_profile : axe fonctionnel orthogonal à org_role

**Décision** : `operational_profile` (`bureau` | `terrain`) est un troisième axe orthogonal, distinct de `org_role` et de `project_role`. Il ne confère aucune autorité par lui-même.

**Usages autorisés** :
1. Filtre UX : interface terrain simplifiée vs interface bureau
2. Condition additionnelle dans la policy UPDATE de `logistics_steps` (un membre "bureau" sans mandat spécifique ne peut pas modifier une étape logistique même s'il appartient à l'organisation responsable)

**Usages interdits** :
- Source de permission autonome
- Substitut à `org_role` ou `project_role`
- Condition principale dans une policy RLS

---

## Dette Technique Connue (Hors Périmètre MVP)

Les éléments suivants appartiennent au domaine MRV/Regroupements existant, pas au MVP CCF. Ils sont documentés ici comme dette technique connue, **sans migration corrective dans cette vague**.

---

### DT-01 — FK directe vers auth.users dans member_distribution_overrides (RT-08)

**Table** : `public.member_distribution_overrides`  
**Colonne** : `created_by UUID REFERENCES auth.users(id)`

**Problème** : Cette FK directe vers `auth.users` contredit la règle MVP-DA-010 qui exige que tous les champs `created_by` référencent `profiles.id` — jamais `auth.users` directement.

**Impact** : Faible en production actuelle (0 lignes ou données de test). Risque de confusion lors de futures jointures avec `profiles`.

**Action future recommandée** :
```sql
-- À planifier dans une migration future (domaine Regroupements)
ALTER TABLE public.member_distribution_overrides
    DROP CONSTRAINT member_distribution_overrides_created_by_fkey;
ALTER TABLE public.member_distribution_overrides
    ADD CONSTRAINT member_distribution_overrides_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
```

**Priorité** : Basse — à traiter lors de la prochaine vague de migrations Regroupements.

---

### DT-02 — actor_id sans FK dans project_activity_logs (RT-09)

**Table** : `public.project_activity_logs`  
**Colonne** : `actor_id UUID` (nullable, sans FK)

**Problème** : `actor_id` est un UUID sans contrainte de clé étrangère. Il devrait référencer `profiles.id` selon MVP-DA-010.

**Impact** : Risque d'orphelins si un utilisateur est supprimé. Pas de garantie d'intégrité référentielle.

**Action future recommandée** :
```sql
-- À planifier dans une migration future (domaine MRV)
ALTER TABLE public.project_activity_logs
    ADD CONSTRAINT project_activity_logs_actor_id_fkey
    FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
```

**Priorité** : Basse — à traiter lors de la prochaine vague de migrations MRV.

---

### DT-03 — actor_id sans FK dans evidence_files (RT-09)

**Table** : `public.evidence_files`  
**Colonne** : `actor_id UUID` (nullable, sans FK)

**Problème** : Même problème que DT-02. `actor_id` sans FK vers `profiles.id`.

**Action future recommandée** :
```sql
-- À planifier dans une migration future (domaine MRV)
ALTER TABLE public.evidence_files
    ADD CONSTRAINT evidence_files_actor_id_fkey
    FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
```

**Priorité** : Basse — à traiter lors de la prochaine vague de migrations MRV.

---

### DT-04 — Séparation nomenclature RLS inter-domaines (RT-10)

**Problème** : Deux ensembles de fonctions RLS coexistent dans la même base Supabase pour des domaines différents :

| Fonction | Domaine | Table source |
|---|---|---|
| `is_company_member(UUID)` | Regroupements/MRV | `organization_members` (renommé) |
| `is_company_owner(UUID)` | Regroupements/MRV | `organization_members` (renommé) |
| `is_aggregator_admin(UUID)` | Regroupements | `aggregator_admins` |
| `is_organization_member(UUID)` | CCF | `organization_members`, status='active' |
| `is_organization_owner(UUID)` | CCF | `organization_members`, role='admin', status='active' |
| `user_org_ids()` | CCF | `organization_members`, status='active' |
| `user_project_ids()` | CCF | `project_participants` via `user_org_ids()` |

**Règle non négociable** : Les policies CCF n'appellent JAMAIS `is_company_member()` ni `is_company_owner()`. Les policies Regroupements/MRV n'appellent JAMAIS `user_org_ids()` ni `user_project_ids()`.

**Différence subtile** : `is_company_member()` ne filtre pas sur `status = 'active'` (comportement historique). `is_organization_member()` filtre sur `status = 'active'` (comportement CCF strict). Cette différence est intentionnelle.

**Action future recommandée** : Lors d'une refactorisation future, envisager d'aligner `is_company_member()` pour filtrer sur `status = 'active'` et documenter l'impact sur les policies Regroupements existantes.

**Priorité** : Documentation — à traiter lors d'une revue d'architecture globale.

---

### DT-05 — transport_status déclaré ENUM mais stocké en text

**Table** : `public.transport_requests`  
**Colonne** : `transport_status text` (déclaré comme ENUM dans la migration `20260613100000` mais stocké en text)

**Problème** : Anomalie de type — le `list_tables` confirme que le champ est `text` en base malgré la déclaration ENUM.

**Impact** : Faible — le domaine transport fonctionne. Risque de confusion lors de futures migrations.

**Action future recommandée** : Documenter l'anomalie dans la migration transport. Ne pas corriger sans analyse d'impact complète.

**Priorité** : Documentation uniquement.

---

## Catalogue des Migrations CCF (001–011)

| Migration | Fichier | Contenu | Statut |
|---|---|---|---|
| CCF-001 | `20260710001000_ccf_001_enums.sql` | ENUMs du domaine CCF | Proposé |
| CCF-002 | `20260710002000_ccf_002_profiles_organisations.sql` | Renommage + profiles | Proposé |
| CCF-003 | `20260710003000_ccf_003_mandates.sql` | Mandats + trigger validation | Proposé |
| CCF-004 | `20260710004000_ccf_004_capabilities_opportunities.sql` | Capacités + opportunités | Proposé |
| CCF-005 | `20260710005000_ccf_005_ccf_projects_participants.sql` | Projets CCF + participants | Proposé |
| CCF-006 | `20260710006000_ccf_006_documents.sql` | Documents | Proposé |
| CCF-007 | `20260710007000_ccf_007_logistics_value_ai.sql` | Logistique + valeur + IA | Proposé |
| CCF-008 | `20260710008000_ccf_008_business_events_audit.sql` | Événements + audit | Proposé |
| CCF-009 | `20260710009000_ccf_009_rls_functions.sql` | Fonctions RLS utilitaires | Proposé |
| CCF-010 | `20260710010000_ccf_010_rls_policies.sql` | Policies RLS consolidées | Proposé |
| CCF-011 | `20260710011000_ccf_011_schema_validation.sql` | Validation du schéma | Proposé |

**Seed de démo** : `supabase/seeds/demo_ccf.sql` — Application manuelle uniquement.

---

## Règle de Gouvernance des Migrations

> **Aucune migration ne doit être appliquée en production sans validation explicite et exécution manuelle dans Supabase Dashboard ou via `supabase db push` — à la discrétion du responsable technique.**

Cette règle est en vigueur depuis la session du 2026-07-07 et s'applique à toutes les migrations, sans exception de taille ou de complexité apparente.
