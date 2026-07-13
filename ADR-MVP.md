# ADR-MVP — MetalTrace MVP CCF
## Registre des décisions d'architecture

**Portée :** Centre de Consolidation Ferroviaire (CCF) — domaine collaboratif MetalTrace, coexistant sur la même base Supabase que les domaines préexistants MRV/ISO 14064 et Regroupements/Agrégateurs.

**Statut de la base au moment de la rédaction :** staging validé — 63/63 assertions automatisées passées (voir §10). Mise à jour du 12 juillet 2026 : voir §7 pour l'incident de test end-to-end S02, §8 pour l'incident de test end-to-end S03, §9 pour le test end-to-end S04 (aucun bug trouvé), §9bis à §9sexies pour l'écran S06 (Mandats) — backend et frontend, **complet et validé** — §9septies/§9octies pour S07 (Documents), **complet, corrigé et validé de bout en bout en production** — §9novies/§9decies pour S08 (Événements), **frontend accepté partiellement, 4ᵉ occurrence du patron `INC-S07-04`** — §9undecies pour la fermeture des trous de test S06/S08 — §9duodecies pour la revue backend de S05 (Projet CCF), 1 bug corrigé (`INC-S05-01`) — §9terdecies pour S05 (Projet CCF) frontend, **complet, corrigé (`INC-S05-02`) et validé de bout en bout en production, 5ᵉ occurrence du patron de régression récurrente** — §9quaterdecies pour la revue backend de S09 (Cockpit exécutif), conforme, aucune correction nécessaire — §9quindecies-§9sexdecies pour S09 frontend, **complet, corrigé (`INC-S09-01`) et validé de bout en bout en production, 6ᵉ occurrence du patron de régression récurrente** — §9septdecies pour la revue backend de S01 (Dashboard complet), conforme — §9octodecies pour S01 frontend, **complet et intégré, 7ᵉ occurrence du patron de régression récurrente (avec réintroduction simultanée d'`INC-S05-02` et `INC-S09-01` hors périmètre du brief, non retenue)** — §9novodecies pour `INC-DATA-01` : **10 tables MRV effacées par un reset marqué « staging uniquement » exécuté en production le 10 juillet (incident antérieur à cette session, sans lien avec S01/S05/S09), résolu et validé en production (8/8 tables restaurées)** — §9vicies pour `INC-S01-01` : **`CCFDashboardSection` bloquée indéfiniment sur « … » à cause d'un `AuthProvider` jamais monté dans l'application (`useAuth()` toujours `undefined`), corrigée dans 3 fichiers et validée en production. Écran S01 (Dashboard complet) entièrement terminé.** — §9unvicies pour la revue backend de S10 (Administration), 1 trou RLS trouvé et corrigé (`profiles` sans policy superadmin) — §9duovicies pour la revue de la PR Rocket S10 : 3 défauts corrigés dans `admin/page.tsx` (conflit `AppLayout`, catalogue `mandate_actions` fictif, jointure `profiles` manquante sur l'audit), `Sidebar.tsx` reconcilié manuellement, 8ᵉ occurrence du patron de régression récurrente (7 fichiers périmés rejetés), **poussé en production** — §9tervicies pour la clôture de la dette technique `AuthContext.tsx`/`useAuth()` (§9vicies) : contexte supprimé, 3 fichiers corrigés, dont `INC-QR-01` (bug réel découvert au passage : `scan_events.user_id` toujours `NULL` + noms de table périmés `company_members`/`company_id` dans le scanner QR) — et §9quatervicies pour le **test live S10, validé de bout en bout en production sur les 4 onglets. Écran S10 (Administration) entièrement terminé.**

**Comment lire ce document :** chaque décision porte un code stable (`MVP-DA-xxx` pour une décision d'architecture, `MVP-RA-xxx` pour une règle d'affaires). Ces codes sont cités dans les migrations SQL et dans le cahier fonctionnel v1.2 — ne jamais les réutiliser pour une décision différente. Les sections normatives (cahier, backlog, migrations) restent la source de vérité du contenu ; ce registre sert d'index et de justification, pas de duplication.

---

## 1. Décisions d'architecture (MVP-DA)

| Code | Décision | Conséquence |
|---|---|---|
| MVP-DA-001 à 008 | *(voir cahier fonctionnel v1.2, Annexe B — inchangées)* | — |
| MVP-DA-009 | Le **Projet** sert de regroupement opérationnel pour le MVP. | Aucun objet Regroupement distinct en v1 ; WF-04 fusionné avec WF-05 ; réintroduction possible en V2. |
| MVP-DA-010 | Le profil utilisateur applicatif est isolé dans `profiles`, rattaché à `auth.users(id)` par FK explicite. | Aucun écran, mandat, log IA ou champ `actor_id`/`generated_by` ne doit utiliser l'e-mail ou `auth.users` directement comme clé de relation. |
| MVP-DA-011 | Aucun statut libre n'est permis sur un objet gouverné. | Chaque table gouvernée porte un `CHECK` fermé sur son propre `status`/`phase` ; transitions décrites dans les user stories et testées avant démonstration externe. |
| **MVP-DA-012** *(nouveau)* | **`organizations` remplace `companies` par renommage en place**, pas par recréation. | `ALTER TABLE companies RENAME TO organizations` (et `company_members`→`organization_members`, `company_member_role`→`org_role`) — préserve toutes les FK et données existantes. Domaines Regroupements/Agrégateurs et CCF partagent désormais une seule table d'identité organisationnelle. |
| **MVP-DA-013** *(nouveau)* | **`ccf_projects` est une table distincte de `projects` (MRV/ISO 14064)**. | Les deux domaines modélisent des objets métier différents (vérification carbone vs consolidation collaborative) ; aucun renommage de la table MRV existante, aucune fusion des deux modèles. |
| **MVP-DA-014** *(nouveau)* | **Fonctions RLS utilitaires (`user_org_ids()`, `user_project_ids()`) dans le schéma `public`**, jamais `auth`. | Cohérent avec toutes les fonctions helper préexistantes du projet (`is_platform_superadmin()`, `is_aggregator_admin()`, etc.), et évite les restrictions Supabase sur les écritures dans le schéma `auth`. |
| **MVP-DA-015** *(nouveau)* | **Aucun type ENUM Postgres partagé pour un `status`/`phase` générique** — `TEXT` + `CHECK` propre à chaque table. | Un ENUM Postgres est un type unique à liste de valeurs fixe ; il ne peut pas servir plusieurs tables avec des valeurs différentes. Cohérent avec le pattern déjà dominant dans le schéma existant (`raw_measurements.status`, `credit_lots.status`, etc., tous en texte/CHECK). Des ENUM restent légitimes pour des types à vocation unique et stable (`mandate_scope`, `document_visibility`, `logistics_step_type`, `ccf_event_type`). |
| **MVP-DA-016** *(nouveau)* | **Seed de démonstration isolé hors du dossier `migrations/`** (`supabase/seed.sql` ou `supabase/seeds/`). | Empêche l'injection automatique de données de démonstration en production par le pipeline CI/CD standard. |
| **MVP-DA-017** *(nouveau)* | **Expiration des mandats calculée à la volée, aucun job planifié en MVP.** `mandates.status` peut rester `active` même après `end_date` ; l'UI et les RLS doivent utiliser la notion de mandat *effectif*, pas seulement le statut physique. | Fonction `is_mandate_effective(p_mandate_id uuid)` et vue `active_effective_mandates`, toutes deux basées sur `status = 'active' AND (end_date IS NULL OR end_date >= current_date)`. Aucun événement `mandate_expired` ajouté au catalogue `event_type` pour le MVP. |
| **MVP-DA-018** *(nouveau)* | **Acceptation d'une invitation de projet via RPC transactionnelle unique**, pas via trigger de propagation entre `mandates` et `project_participants`. La RPC ne suppose jamais qu'une ligne `project_participants` existe déjà. | Fonction `accept_project_invitation(p_mandate_id uuid, p_project_id uuid)` (`SECURITY DEFINER`) : active le mandat, puis `INSERT ... ON CONFLICT (project_id, organization_id) DO UPDATE` sur `project_participants` (crée la ligne si absente, l'active sinon), rattache `mandate_id`, émet `mandate_accepted` — le tout dans une seule transaction. Un trigger cacherait trop de logique métier entre les deux tables ; la RPC explicite reste lisible, testable et auditée. |
| **MVP-DA-019** *(nouveau)* | **Séparation stricte entre mandat générique et invitation de projet.** Un mandat lié à une invitation de projet (`project_participants.mandate_id` existe) ne doit jamais être accepté sans contexte projet explicite — l'écran `/mandats` autonome ne doit pas appeler `accept_project_invitation()` en résolvant silencieusement le `project_id` par jointure. Un mandat générique (aucune ligne `project_participants`) s'accepte directement depuis `/mandats`. | `accept_mandate(p_mandate_id uuid)` créée pour le cas générique (statut → `active`, sans toucher `project_participants`). `accept_project_invitation(p_mandate_id, p_project_id)` reste réservée au contexte projet explicite (écran `/projets/:id`, S05). Dans `/mandats`, un mandat lié à un projet affiche « Voir le projet »/« Ouvrir l'invitation », pas un bouton d'acceptation direct. Le refus (`decline_project_invitation`), lui, n'est **pas** séparé par branche — point de vigilance noté en §9quinquies, pas un bug. |

---

## 2. Règles d'affaires (MVP-RA)

| Code | Règle | Conséquence |
|---|---|---|
| MVP-RA-001 à 020 | *(voir cahier fonctionnel v1.2, Annexe B — inchangées)* | — |
| MVP-RA-021 | Les fonctions utilitaires RLS doivent être créées avant les premières policies. | Auditabilité — chaque table réinventerait sa propre logique sinon. |
| MVP-RA-022 | Aucune policy RLS ne doit contourner les fonctions utilitaires par une logique locale divergente ; le service role ne doit jamais servir à un flux utilisateur normal ou une action d'agent IA. | Empêche les contournements silencieux de sécurité au niveau des lignes. |
| MVP-RA-023 | **Retrait autonome d'une candidature.** Une organisation propriétaire d'une capacité candidate peut retirer sa propre candidature d'une opportunité (`active → withdrawn`), sans suppression physique de l'association. Distinct d'un retrait à l'initiative du coordonnateur (`active → removed`). | `opportunity_capabilities.status` étendu à `active, removed, withdrawn` ; trigger `enforce_opp_cap_update_scope()` limite qui peut déclencher quelle transition. |
| MVP-RA-024 | **Relance d'une candidature retirée, sous consentement du candidat.** `withdrawn` est terminal pour le coordonnateur : il ne peut pas réactiver, requalifier ou reclasser directement. Il peut seulement initier une relance vers `pending_reacceptance` ; seule l'organisation candidate peut ensuite accepter (`→ active`) ou refuser (`→ withdrawn`). | `opportunity_capabilities.status` étendu à `pending_reacceptance` ; `fit_score` gelé dès que le statut quitte `active` (modifiable uniquement `active → active`). Machine à états complète : voir §4. |
| MVP-RA-025 | **Séparation coordonnateur / candidat.** Une organisation coordonnatrice d'une opportunité ne peut pas être candidate sur cette même opportunité. Limitation volontaire du MVP (neutralité du coordonnateur, confiance inter-organisations, simplicité RLS) ; à lever en V2 avec déclaration de conflit d'intérêts et gouvernance renforcée. | Trigger `enforce_no_self_candidacy()` (`BEFORE INSERT` sur `opportunity_capabilities`) rejette toute association où `opportunities.coordinator_org_id = capabilities.organization_id`. |
| MVP-RA-026 | **Cohérence `visibility`/`object_type` pour `project`.** `documents.visibility = 'project'` n'est autorisé que si `documents.object_type = 'project'` — un document rattaché à une capacité, une organisation, une opportunité ou un mandat ne devient jamais visible à tout un projet par héritage implicite. | Contrainte `documents_project_visibility_requires_project_object`. Pour partager un document lié à une capacité dans le contexte d'un projet, il doit être déposé explicitement comme document de projet (catégorie `capability_evidence`, `logistics_proof`, etc.). |
| MVP-RA-027 | **Confidentialité restrictive, applicable à tout `object_type`.** Un document `confidential` peut être rattaché à n'importe quel objet métier gouverné — la confidentialité n'est jamais une portée de partage, elle réduit toujours l'accès par rapport à la visibilité normale, jamais l'inverse. Pour `value_report` spécifiquement : confidentiel = coordonnateur du projet seulement, jamais les participants actifs (aucun mécanisme de destinataires nommés en MVP, reporté en V2). | Policy `documents_confidential_select` (organization/capability/mandate) + policy complémentaire `documents_confidential_value_report_select` (jointure `value_reports`/`ccf_projects`) — deux policies permissives combinées par OU logique. |
| **MVP-RA-028** *(nouveau)* | **Interdiction de l'auto-mandat.** Une organisation ne peut pas se mandater elle-même (`issuer_org_id ≠ receiver_org_id`). Un mandat encadre une relation entre deux organisations distinctes ; une autorisation interne (membre à membre) relève de `organization_members`/`org_role`/`project_role`, pas d'un mandat. Cohérent avec l'esprit de séparation déjà établi par MVP-RA-025 (coordonnateur/candidat). | Contrainte `mandates_different_orgs` (`CHECK (issuer_org_id != receiver_org_id)`) sur la table `mandates` — nom réel confirmé en base au test §9quater, différent du nom documenté initialement (`mandates_issuer_receiver_distinct`), écart cosmétique sans impact fonctionnel. |
| **MVP-RA-029** *(nouveau)* | **Gel des champs structurants d'un mandat actif.** Dès que `mandates.status = 'active'`, les colonnes `mandate_scope`, `permissions`, `issuer_org_id` et `receiver_org_id` deviennent immuables. Pour changer la portée ou les actions d'un mandat en cours, il faut le révoquer et créer un nouveau mandat, soumis à une nouvelle acceptation explicite du récepteur — évite qu'un mandat accepté pour une portée limitée s'élargisse silencieusement sans consentement. | Trigger `enforce_mandate_active_freeze()` (`BEFORE UPDATE` sur `mandates`) rejette toute modification de ces 4 colonnes lorsque `OLD.status = 'active' OR NEW.status = 'active'` (condition élargie suite à `INC-S06-02` — voir §9bis). |

---

## 3. Risques techniques identifiés et résolus (RT)

Ces points proviennent du rapport de validation d'architecture produit avant la première génération de migrations. Chacun a été tranché avant que le code SQL ne soit écrit.

| Code | Risque | Décision retenue |
|---|---|---|
| RT-01 / RT-02 | Collision de table et d'ENUM entre `projects` (MRV) et le domaine collaboratif. | Nouvelle table `ccf_projects` ; `projects` (MRV) et `project_status` intouchés. Voir MVP-DA-013. |
| RT-03 | `companies` (Regroupements/MRV) vs `organizations` (CCF) — même concept ou deux concepts ? | Même concept — renommage en place. Voir MVP-DA-012. Le concept « terrain » (`company_member_role`) est préservé comme axe orthogonal via `organization_members.operational_profile` (`bureau`/`terrain`), distinct de `org_role`. |
| RT-04 | Fonctions RLS dans le schéma `auth` — risque de restriction Supabase. | Schéma `public`. Voir MVP-DA-014. |
| RT-05 | ENUM `status` générique impossible en PostgreSQL (un type ne peut pas avoir des valeurs différentes par table). | TEXT + CHECK par table. Voir MVP-DA-015. |
| RT-06 | Seed de démo sans isolation d'environnement. | `supabase/seed.sql`, hors `migrations/`. Voir MVP-DA-016. |
| RT-07 | `mandates.permissions` (JSONB) sans stratégie de validation. | Trigger `validate_mandate_permissions()` — valide chaque élément de `permissions.actions[]` contre la table de référence `mandate_actions` ; rejette un tableau vide ; aucune valeur par défaut sur la colonne pour forcer une saisie explicite. |
| RT-08 | `member_distribution_overrides.created_by` — FK directe vers `auth.users`, pas `profiles`. | **Hors périmètre MVP CCF** — domaine Regroupements préexistant. Consigné comme dette technique (§5), non corrigé dans cette vague. |
| RT-09 | `project_activity_logs.actor_id`, `evidence_files.actor_id` — sans FK. | **Hors périmètre MVP CCF** — domaine MRV préexistant. Dette technique (§5). |
| RT-10 | Séparation de nomenclature RLS entre domaines (`is_company_member()` historique vs `is_organization_member()` du domaine CCF). | Les deux ensembles de fonctions coexistent ; `is_company_member()`/`is_company_owner()` conservent leur nom (pour ne pas casser les policies existantes) mais pointent désormais vers `organization_members` ; `is_organization_member()`/`is_organization_owner()` sont des alias pour le nouveau code CCF. Documenté explicitement pour éviter toute confusion inter-domaines future. |
| RT-11 | Seed `mandate_actions` dans la même migration que la table `mandates`. | Protégé par `ON CONFLICT (code) DO NOTHING` — accepté tel quel. |
| RT-12 | `transport_status` déclaré ENUM dans une migration historique mais stocké en `text` en pratique. | **Hors périmètre** — anomalie préexistante, documentée (§5), non corrigée. |

---

## 4. Machine à états — `opportunity_capabilities.status`

Résultat cumulatif de MVP-RA-023, 024 et 025. Aucune autre transition que celles listées n'est permise.

```
active ──(coordonnateur)──────────► removed
active ──(candidat)───────────────► withdrawn
withdrawn ──(coordonnateur, relance)──► pending_reacceptance
pending_reacceptance ──(candidat accepte)──► active
pending_reacceptance ──(candidat refuse)───► withdrawn
```

Règles complémentaires :
- `fit_score` modifiable **uniquement** quand `OLD.status = 'active' AND NEW.status = 'active'` — gelé dans tous les autres cas, pour les deux acteurs.
- `opportunity_id`, `capability_id`, `created_at` sont immuables après création.
- Une organisation ne peut jamais être à la fois coordonnatrice de l'opportunité et propriétaire de la capacité candidate (MVP-RA-025) — cas bloqué à l'`INSERT`, pas seulement documenté.
- Chaque transition émet un événement métier distinct dans `business_events` : `opportunity_capability_removed`, `opportunity_capability_withdrawn`, `opportunity_capability_reinvited`, `opportunity_capability_reaccepted`, `opportunity_capability_reinvitation_declined`.

---

## 5. Dette technique connue (hors périmètre MVP CCF)

Ces éléments appartiennent aux domaines MRV/ISO 14064 et Regroupements/Agrégateurs, préexistants au travail CCF. Ils ne sont **pas** corrigés dans cette vague de migrations — consignés ici pour visibilité, pas pour action immédiate.

| Code | Constat | Domaine |
|---|---|---|
| DT-01 (RT-08) | `member_distribution_overrides.created_by` référence `auth.users` directement, pas `profiles.id`. | Agrégateurs |
| DT-02 (RT-09) | `project_activity_logs.actor_id` sans FK. | MRV |
| DT-03 (RT-09) | `evidence_files.actor_id` sans FK. | MRV |
| DT-04 | `aggregator_admins.user_id` sans FK vers `profiles`. | Agrégateurs |
| DT-05 (RT-12) | `transport_status` déclaré ENUM historiquement mais stocké en `text`. | Transport |
| DT-06 | Les fonctions RLS du domaine Agrégateurs/MRV (`is_platform_admin()`, `is_aggregator_admin()`, `is_verifier()`, etc.) n'ont pas `SET search_path = public`, contrairement à la convention imposée aux fonctions du domaine CCF (MVP-RA-021). | Agrégateurs / MRV |
| DT-07 | `is_project_admin()` a historiquement existé en deux versions dans les migrations d'origine (une lisant `raw_user_meta_data`, modifiable par l'utilisateur — faille de sécurité ; une sécurisée lisant `auth.jwt() -> app_metadata`). Lors de la réapplication complète du schéma, la version non sécurisée a été temporairement réintroduite dans l'ordre du fichier avant d'être corrigée — voir incident §6. La version finale en base est la version sécurisée. | Plateforme |

**Recommandation :** traiter DT-01 à DT-04 et DT-06 dans un projet de durcissement dédié post-MVP, pas dans le cadre du CCF.

---

## 6. Incident notable — réinitialisation complète du schéma de staging

Au cours de la validation pré-migration, plusieurs migrations CCF (`ccf_003`, `ccf_005`, `ccf_007`, une partie de `ccf_008`) se sont révélées **jamais appliquées** sur la base de staging malgré une revue de code approfondie — `CREATE TABLE IF NOT EXISTS` ne réapplique aucun changement de structure sur une table déjà existante, même si le fichier de migration source, lui, a été corrigé depuis.

**Action prise :** réinitialisation complète du schéma `public` (`DROP SCHEMA public CASCADE`), suivie d'une réapplication intégrale et ordonnée des trois domaines (CCF, MRV, Agrégateurs).

**Conséquence :** toutes les tables des domaines MRV et Agrégateurs, absentes des migrations CCF, ont été supprimées puis reconstruites (schéma seul — aucune donnée n'existait à préserver sur cet environnement, confirmé avant exécution).

**Leçon retenue :** `CREATE TABLE IF NOT EXISTS` est un mécanisme d'idempotence pour la *création*, pas pour la *migration évolutive*. Toute modification de structure sur une table déjà créée doit passer par un `ALTER TABLE` explicite et versionné dans une migration ultérieure — jamais par une réédition silencieuse du `CREATE TABLE` d'origine en espérant qu'elle se répercute.

---

## 7. Incident — test end-to-end S02 (écran Organisations)

Premier test manuel dans le navigateur de l'écran S02 (Organisations), couvrant la création d'organisation, l'invitation d'un membre et l'acceptation d'invitation. Objectif : valider en conditions réelles ce que la lecture de code seule ne peut pas garantir — RLS, triggers, RPC et policies ne se comportent pas toujours comme prévu une fois exécutés avec le rôle `authenticated` réel (voir limite connue du script de validation, §10).

**Résultat : 9 bugs réels trouvés et corrigés, aucun détectable par simple lecture de code.**

| Code | Constat | Cause racine | Correction |
|---|---|---|---|
| INC-S02-01 | Récursion RLS infinie entre les policies de `ccf_projects` et `project_participants` (chacune interrogeait l'autre en sous-requête directe). | Sous-requête directe sur une table dont la policy dépend d'une autre table qui, elle-même, réévalue RLS de façon cyclique. | Fonctions `SECURITY DEFINER` (`get_ccf_project_coordinator_org()`, réutilisation de `is_ccf_project_participant()`) pour casser le cycle. |
| INC-S02-02 | Aucun `GRANT` pour `authenticated`/`anon` sur le schéma `public`. | Un `DROP SCHEMA public CASCADE` antérieur (voir incident §6) avait aussi effacé la configuration de privilèges par défaut ; les tests SQL passaient quand même car exécutés avec le rôle `postgres`. | `ALTER DEFAULT PRIVILEGES` (pour l'avenir) + `GRANT ... ON ALL TABLES/FUNCTIONS/SEQUENCES IN SCHEMA public` (rétroactif). |
| INC-S02-03 | `organization_members.user_id` référençait `auth.users(id)` au lieu de `profiles(id)` — violait MVP-DA-010, causait un échec PostgREST (`PGRST200`) sur toute jointure imbriquée `profiles(...)`. | FK héritée du renommage `company_members → organization_members` (MVP-DA-012), antérieure à l'introduction de `profiles` dans le projet — jamais migrée. | `DROP CONSTRAINT` puis `ADD CONSTRAINT` vers `profiles(id)`, suivi d'un `NOTIFY pgrst, 'reload schema'`. |
| INC-S02-04 | Des comptes `auth.users` existants n'avaient aucune ligne `profiles` correspondante. | `handle_new_user_profile()` ne s'applique qu'aux nouvelles inscriptions, pas rétroactivement. | `INSERT INTO profiles SELECT ... FROM auth.users LEFT JOIN profiles WHERE profiles.id IS NULL`. |
| INC-S02-05 | Créer une organisation via le formulaire n'ajoutait pas automatiquement le créateur comme membre admin dans `organization_members`. | Trou de logique applicative — jamais implémenté. | Trigger `AFTER INSERT ON organizations` → fonction `handle_new_organization_admin()` (`SECURITY DEFINER`, `SET search_path = public`), capture `auth.uid()`, ignore silencieusement si `NULL`. Contrainte `UNIQUE(organization_id, user_id)` ajoutée sur `organization_members` (absente jusque-là) pour que le `ON CONFLICT DO NOTHING` du trigger soit réellement effectif. |
| INC-S02-06 | RPC `get_invitation_by_token` totalement absente de la base, malgré l'ADR indiquant qu'elle avait été « vérifiée et corrigée ». | Régression silencieuse du même `DROP SCHEMA public CASCADE` (incident §6) — jamais réappliquée après coup. Une première tentative de correction par l'agent a réintroduit une référence à `public.companies`/`company_id`, table renommée depuis (MVP-DA-012) ; corrigée avant exécution. | Fonction recréée avec `organization_id`/`organization_name`, `SECURITY DEFINER`, `SET search_path = public`, `GRANT EXECUTE` à `anon` et `authenticated` (nécessaire pour un invité non encore authentifié). |
| INC-S02-07 | Récursion RLS infinie sur `organization_members` elle-même (policy `org_members_admin_insert`), déclenchée à l'acceptation d'une invitation. Une clause `NOT EXISTS` de la même policy comparait une colonne à elle-même (tautologie toujours vraie), rendant cette branche inutilisable. | Sous-requête directe sur `organization_members` dans sa propre policy — même anti-pattern qu'INC-S02-01, jamais appliqué à cette table. | Fonction `is_org_admin(p_organization_id)` (`SECURITY DEFINER`, `SET search_path = public`) ; policies `org_members_admin_insert`/`_update` réécrites pour l'appeler. Branche bootstrap tautologique supprimée — rendue obsolète par le trigger d'INC-S02-05. |
| INC-S02-08 | Après correction d'INC-S02-07, l'acceptation d'invitation échouait avec `permission denied for table users` — l'insertion dans `organization_members` se fait par un `INSERT` direct côté client (pas une RPC `SECURITY DEFINER`), et aucune policy n'autorisait un non-membre à s'insérer lui-même via une invitation valide. | Policy manquante ; première tentative de correction lisait `auth.users` directement dans la policy (`SELECT email FROM auth.users WHERE id = auth.uid()`), interdit pour le rôle `authenticated`. | Policy `org_members_invitation_insert` ajoutée : autorise l'auto-insertion si une invitation `pending`, non expirée, existe pour `auth.jwt() ->> 'email'` **et** que le rôle inséré correspond exactement au rôle proposé par l'invitation (empêche un candidat d'élever son propre rôle, ex. `membre` → `admin`, en modifiant la requête côté client). |
| INC-S02-09 | Dans l'écran de gestion des membres, un admin voyait un UUID brut au lieu du nom/email pour tout membre autre que lui-même. | `profiles` n'avait qu'une policy `SELECT` limitée à `id = auth.uid()` — aucune policy n'autorisait un utilisateur à lire le profil d'un autre membre de la même organisation ; la jointure frontend vers `profiles` échouait silencieusement pour les autres lignes. | Policy `profiles_select_org_members` ajoutée, réutilisant la fonction déjà existante `user_org_ids()` (`SECURITY DEFINER`) : autorise la lecture du profil de tout utilisateur partageant une organisation active avec l'utilisateur courant. Première version proposée utilisait `= ANY(user_org_ids())`, rejetée par Postgres (`set-returning functions are not allowed in WHERE`) ; corrigée en `IN (SELECT user_org_ids())`. |

**État du test S02 après correction : les 5 étapes prévues sont réussies**, incluant la création d'organisation (avec auto-insertion admin vérifiée en base), l'invitation d'un membre et l'acceptation complète de l'invitation (vérifiée en base sur `organization_members` et `invitations`).

**Leçons retenues :**
- L'anti-pattern « sous-requête directe sur la table protégée, à l'intérieur de sa propre policy RLS » s'est reproduit deux fois dans deux domaines différents (INC-S02-01, INC-S02-07) — à surveiller systématiquement sur toute nouvelle policy touchant une table qui référence elle-même dans sa condition d'appartenance.
- Le `DROP SCHEMA public CASCADE` de l'incident §6 continue de produire des régressions détectées tardivement (INC-S02-06) — une vérification exhaustive post-reset (fonctions, GRANTs, RPC) serait utile avant de considérer un reset de schéma comme totalement résorbé.
- Toute policy ou fonction lisant l'identité de l'utilisateur courant doit utiliser `auth.jwt() ->> 'email'` (ou `auth.uid()`), jamais une lecture directe de `auth.users`, qui n'est pas accessible au rôle `authenticated` (INC-S02-08).
- Une policy trop restrictive sur `profiles` (limitée à `id = auth.uid()`) échoue silencieusement côté jointure plutôt que de bloquer avec une erreur visible — à vérifier explicitement pour toute nouvelle table affichant des informations sur *d'autres* utilisateurs, pas seulement sur l'utilisateur courant (INC-S02-09).

---

## 8. Incident — test end-to-end S03 (écran Capacités)

Deuxième test manuel end-to-end, cette fois sur l'écran S03 (Capacités), qui n'existait pas du tout au démarrage de la session (404 sur `/capacites`). Couverture : construction complète de l'écran (liste, création, workflow de qualification, association à une opportunité), suivie d'un test manuel dans le navigateur avec deux comptes (admin et membre) et des vérifications SQL directes pour isoler chaque comportement.

**Résultat : 9 bugs réels trouvés et corrigés**, dont deux nouvelles récursions RLS s'ajoutant aux deux déjà documentées à la session S02 (§7) — l'anti-pattern « sous-requête directe sur une table dont la policy referme le cycle » continue de se propager à mesure que de nouvelles tables sont reliées entre elles.

| Code | Constat | Cause racine | Correction |
|---|---|---|---|
| INC-S03-01 | Policy `capabilities_owner_admin_insert` limitait la création d'une capacité à l'owner/admin de l'organisation, alors que la règle métier confirmée autorise tout membre actif à créer en statut non exploitable. | Policy trop restrictive, écrite avant la clarification de la règle métier (membre actif = création en `draft`/`proposed` ; admin seul = qualification). | Policy renommée `capabilities_member_insert`, ouverte à `is_organization_member()`, avec `WITH CHECK (status = 'draft')` pour empêcher un membre d'insérer directement un statut avancé. |
| INC-S03-02 | Colonne `capabilities.status` en `TEXT` libre, sans contrainte — aucune valeur n'était rejetée, y compris hors du workflow prévu. | Absence de contrainte CHECK/ENUM lors de la création initiale de la table. | `CHECK (status IN ('draft','declared','qualified','suspended','archived'))` ajoutée, conforme à MVP-DA-015 (TEXT + CHECK, pas d'ENUM partagé). Vérifié au préalable qu'aucune donnée existante (`declared`×1, `qualified`×2) ne violait la contrainte avant application. |
| INC-S03-03 | L'écran S03 (`/capacites`) renvoyait une 404 — l'écran n'avait jamais été construit, malgré la roadmap 30-60-90 qui le prévoyait dès les jours 1-30. Un premier message de l'agent affirmant que « tout est déjà en place » (PR #94 non fusionné) s'est révélé incorrect à la vérification. | Écran jamais livré ; confusion entre code poussé sur une branche (PR ouvert) et code réellement déployé (nécessite fusion). | Écran construit dans son ensemble (liste, création, qualification, association) via PR #94 ; vérifié dans l'aperçu Vercel avant fusion, conformément à la discipline de validation du code réel. |
| INC-S03-04 | Récursion RLS infinie (`infinite recursion detected in policy for relation "opportunity_capabilities"`) dès l'affichage de la liste des capacités. | Quatre policies créaient un cycle mutuel à deux tables : `capabilities_owner_select` et `capabilities_project_context_select` interrogeaient directement `opportunity_capabilities` ; `opp_cap_member_select` et `opp_cap_update_coordinator_or_candidate` interrogeaient directement `capabilities` en retour. Même anti-pattern qu'INC-S02-01/07, cette fois entre deux tables distinctes plutôt qu'une table sur elle-même. | 4 fonctions `SECURITY DEFINER` créées (`is_capability_candidate_org_member`, `is_capability_linked_to_user_coord_org`, `is_opportunity_capability_via_capability_member`, `is_opportunity_capability_via_capability_owner`), et les 4 policies réécrites pour les appeler au lieu des sous-requêtes directes. |
| INC-S03-05 | Trigger `check_capability_status_before_opp_cap_insert` manquant pour empêcher l'association d'une capacité `draft` à une opportunité — aucune règle ne l'empêchait avant. | Règle métier (« aucune capacité non `declared`/`qualified` ne peut être associée ») jamais implémentée techniquement. Une contrainte CHECK avec sous-requête étant impossible en PostgreSQL, un trigger `BEFORE INSERT` était la seule option idiomatique. | Trigger `SECURITY DEFINER` créé sur `opportunity_capabilities`, levant une exception explicite (`capability_not_eligible`) si le statut de la capacité référencée n'est pas `declared` ou `qualified`. Testé avec succès dans les deux sens (acceptation d'une capacité `qualified`, rejet d'une capacité `draft`). |
| INC-S03-06 | Le bouton « Associer à une opportunité » n'apparaissait jamais dans l'écran, même avec une opportunité valide en base. | Filtre de requête `.not('status', 'in', '("closed","archived")')` mal formé côté client — la syntaxe attendue par PostgREST pour un filtre `not...in` n'admet pas de guillemets doubles autour de chaque valeur. Sans gestion d'erreur explicite sur cette requête, l'échec était silencieux (`coordinatedOpportunities` restait vide sans message). | Syntaxe corrigée en `.not('status', 'in', '(closed,archived)')`. |
| INC-S03-07 | Après correction d'INC-S03-06, la requête `opportunities` échouait toujours avec une erreur 500 (confirmée dans les outils réseau du navigateur). | Nouvelle récursion RLS, cette fois à trois tables : la policy `opportunities_coordinator_select` interrogeait directement `opportunity_capabilities` jointe à `capabilities`, refermant un cycle avec les policies déjà corrigées à INC-S03-04. Jamais détectée avant, faute d'avoir testé ce chemin précis (lecture d'`opportunities` depuis l'écran Capacités). | Fonction `SECURITY DEFINER` `is_opportunity_visible_via_active_candidacy()` créée, policy `opportunities_coordinator_select` réécrite pour l'appeler. Vérifié par la même occasion que `opportunities_project_context_select` et les policies de `ccf_projects` ne referment aucun cycle supplémentaire. |
| INC-S03-08 | Confirmé, pas un bug : une capacité ne peut pas être associée à une opportunité coordonnée par sa propre organisation (règle MVP-RA-025, auto-candidature interdite). Le message d'erreur technique était correctement traduit en français dans l'interface. | N/A — comportement attendu, testé et confirmé fonctionnel des deux côtés (SQL direct et UI). | Aucune correction requise ; documenté ici pour mémoire, car il a d'abord été investigué comme un bug potentiel avant d'être identifié comme le comportement correct. |
| INC-S03-09 | Aucune donnée de test résiduelle après la session, mais nécessité de créer des enregistrements temporaires (opportunité, capacité isolée) en SQL direct pour contourner l'absence de compte utilisateur sur certaines organisations de démonstration. | Certaines organisations de données de démo (`99184461-...`, `49672bec-...`) n'ont aucun membre `organization_members` actif, empêchant tout test via l'interface avec un compte réel. | Pas une correction en soi — nettoyage systématique effectué après chaque test (vérifié par requêtes `SELECT` ciblées avant `DELETE`). Noté comme limitation de l'environnement de test actuel (absence de jeu de données pilote complet, mentionné aussi en Annexe C du cahier fonctionnel). |

**État du test S03 après correction : le workflow complet est validé** — création par un membre actif (forcée en `draft`), blocage confirmé pour un membre non-admin sur la qualification, progression complète `draft → declared → qualified` par un admin, et association à une opportunité testée avec succès en SQL direct (bloquée correctement dans l'UI par MVP-RA-025 faute d'un second compte utilisateur disponible pour un test de succès visuel complet — jugé redondant avec la validation SQL déjà faite).

**Leçons retenues (en plus de celles déjà notées à la session S02) :**
- L'anti-pattern de sous-requête RLS directe continue de se propager à mesure que de nouvelles tables sont reliées : il s'est maintenant manifesté sur 3 paires de tables distinctes (`ccf_projects`/`project_participants`, `capabilities`/`opportunity_capabilities`, `opportunities`/`opportunity_capabilities`+`capabilities`). Toute nouvelle policy touchant une table liée à une autre table elle-même sous RLS devrait systématiquement passer par une fonction `SECURITY DEFINER`, par défaut, plutôt que d'être corrigée après coup.
- Une affirmation de l'agent selon laquelle « le code est déjà en place » doit toujours être vérifiée par une action concrète (ouvrir l'URL, tester l'écran) avant d'être acceptée — un PR ouvert et non fusionné n'est pas un déploiement.
- Les requêtes Supabase/PostgREST sans gestion d'erreur explicite (`const { data } = await supabase...` sans capturer `error`) peuvent échouer silencieusement et masquer un vrai problème (INC-S03-06/07) derrière une simple absence de résultat.
- L'environnement de données de démonstration actuel contient des organisations sans membre actif, ce qui limite certains tests multi-organisations à des vérifications SQL directes plutôt qu'à des parcours utilisateur complets dans l'interface — à corriger avant d'inviter un partenaire pilote (cohérent avec l'action déjà notée de créer un vrai jeu de données pilote, Annexe C).

**Audit systématique des policies RLS (post-session, 11 juillet 2026)**

Suite à la répétition de l'anti-pattern sur 3 paires de tables distinctes en deux jours, l'ensemble des policies RLS du schéma `public` a été extrait et analysé manuellement (`SELECT * FROM pg_policies WHERE schemaname = 'public'`) pour détecter toute récursion supplémentaire non encore découverte par les tests.

**Conclusion : aucune récursion active supplémentaire trouvée**, au-delà des 4 déjà corrigées (`ccf_projects`/`project_participants`, `organization_members`, `capabilities`/`opportunity_capabilities`, `opportunities`). Toutes les autres sous-requêtes directes inter-tables observées (domaines Regroupements, MRV, Documents, Mandats, Logistique) sont à sens unique — la table référencée ne référence jamais la table source en retour.

**Point de vigilance non urgent identifié** : la policy `organizations_admin_update` utilise une sous-requête manuelle sur `organization_members` au lieu d'appeler la fonction `is_org_admin()` (créée à INC-S02-07). Aucune récursion actuelle (`organization_members` ne référence pas `organizations`), mais incohérence stylistique à corriger par précaution si une policy future venait à créer ce chemin retour.

**Règle de développement à retenir pour la suite** : toute nouvelle policy RLS référençant une autre table doit systématiquement passer par une fonction `SECURITY DEFINER` dédiée, jamais par une sous-requête directe — y compris quand la table cible ne semble présenter aucun risque de cycle au moment de l'écriture, puisque ce risque peut apparaître plus tard avec l'ajout d'une nouvelle policy sur cette même table.

---

## 9. Test end-to-end S04 (écran Opportunités) — 12 juillet 2026

Troisième test manuel end-to-end, portant cette fois sur l'écran S04 (Opportunités), en avance sur la roadmap 30-60-90 (S04 n'est officiellement prévu qu'en phase Jours 31-60, mais construit et testé dès maintenant par souci de continuité avec les Capacités déjà testées à la session S03).

**Résultat : aucun bug trouvé.** Contrairement aux sessions S02 et S03 (9 bugs chacune), l'écran S04 fonctionnait déjà correctement dès le premier test — signe que les corrections RLS appliquées la veille sur `opportunities` (INC-S03-07) ont tenu, et que l'écran avait été construit correctement en amont par l'agent.

**Point de méthode notable** : l'agent (Rocket) a affirmé d'entrée que l'écran S04 était « déjà entièrement implémenté — aucun changement nécessaire », avec des détails précis (nom de fichier, nombre de lignes). Cette affirmation n'a été acceptée qu'après vérification concrète (ouverture de l'URL, test réel dans le navigateur) — cohérent avec la leçon retenue à la session S03 (une affirmation de l'agent doit toujours être vérifiée par une action concrète). Cette fois, l'affirmation s'est révélée exacte, contrairement à celle faite pour S03 la veille.

**Étapes validées dans l'interface réelle, avec vérification en base à chaque étape :**

| Étape | Résultat |
|---|---|
| Route `/opportunities` et lien menu latéral | Existants, fonctionnels — filtres de statut (Brouillon, Qualifiée, Convertie, Fermée, Archivée) affichés correctement même à 0 |
| Création d'une opportunité (`title`, `description`, `region`, `target_volume`, `priority`) par le coordonnateur | Réussie ; statut initial `draft` confirmé en base |
| Émission de l'événement `opportunity_created` dans `business_events` | Confirmée ; `payload` contient `title`/`status` |
| Qualification (`draft → qualified`), réservée au coordonnateur/admin | Réussie dans l'UI, avec message explicite (« Réservée au coordonnateur ») |
| Émission de l'événement `opportunity_qualified` | Confirmée ; `payload` contient `previous_status`/`new_status`, utile pour un futur historique |
| Vue « Capacités candidates » (état vide) | Affichage propre, cohérent |
| Blocage `MVP-RA-025` (auto-candidature) sur une capacité de la même organisation | Reconfirmé, cohérent avec le comportement déjà validé à la session S03 |
| Association réussie d'une capacité `qualified` d'une **autre** organisation | Non retestée dans l'UI (organisation candidate sans compte utilisateur disponible, même limitation qu'à la session S03) — jugée suffisamment couverte par la validation SQL directe déjà faite la veille sur le même mécanisme |

**Nettoyage effectué** : opportunité de test et événements `business_events` associés supprimés après validation, aucune donnée résiduelle en production.

**Aucune action corrective requise** pour cette session. Documentée ici principalement pour la continuité de la couverture de test entre les sessions.

---

## 9bis. Revue de code S06 (Mandats) — backend, 12 juillet 2026

Contrairement aux sessions S02-S04 (test manuel dans le navigateur après déploiement), cette session porte sur la **revue et le test du script de migration produit par Rocket avant fusion** — le code n'a pas encore été déployé sur staging. Une base PostgreSQL 16 locale a été instanciée pour simuler l'environnement Supabase (schéma `auth`, rôles `authenticated`/`anon`/`service_role`, mock de `auth.uid()` pilotable par session), avec une baseline reproduisant l'état attendu de `CCF-003` avant application du script S06.

**Résultat : 4 bugs réels trouvés, tous reproduits par des requêtes SQL directes puis corrigés.** Contrairement aux sessions précédentes, aucun bug ne touchait l'UI (pas encore construite) — tous relevaient de la conception RLS/trigger.

| Code | Constat | Cause racine | Correction |
|---|---|---|---|
| INC-S06-01 | Aucune policy RLS ne permet la transition `draft → pending_acceptance` (émission du mandat). L'émetteur ne peut donc jamais faire sortir un mandat de l'état `draft` — le workflow est bloqué dès la première étape. | Policy manquante : les deux seules policies UPDATE couvrent l'acceptation (récepteur) et la révocation (émetteur vers `revoked` uniquement) ; personne ne peut faire `draft → pending_acceptance`. | Policy `mandates_update_issuance_by_issuer` ajoutée (`USING status='draft'`, `WITH CHECK status='pending_acceptance'`), réservée à l'admin de l'org émettrice (voir INC-S06-03). |
| INC-S06-02 | Le récepteur peut élargir `mandate_scope`/`permissions` **au moment même** où il accepte un mandat (`pending_acceptance → active`), contournant l'esprit de `MVP-RA-029`. Testé et reproduit : `UPDATE mandates SET status='active', mandate_scope='financier' WHERE ...` réussissait avant correction. | Le trigger `enforce_mandate_active_freeze()` ne bloquait que si `OLD.status = 'active'` — il ne couvrait pas la transition *entrante* vers `active`, seulement les mandats déjà actifs. | Condition du trigger élargie à `OLD.status = 'active' OR NEW.status = 'active'` — bloque désormais aussi bien la modification d'un mandat déjà actif que toute tentative de changer ces 4 champs pendant la transition qui l'active. |
| INC-S06-03 | N'importe quel membre actif d'une organisation (pas seulement l'admin) peut créer, accepter ou révoquer un mandat — au niveau des policies RLS **et** des deux RPC. Contraire à la matrice de permissions du cahier §7.2 (« Mandat : Admin org. → Créer/valider pour son org. »). Reproduit avec un membre `org_role='membre'` qui a pu créer, puis accepter, un mandat sans blocage. | Les policies et les RPC utilisaient `user_org_ids()` (tout membre actif) plutôt qu'une vérification d'admin. La fonction `is_org_admin()` existe pourtant déjà dans le projet (créée à `INC-S02-07`) et n'a pas été réutilisée ici. | Policies `mandates_insert_issuer_admin`, `mandates_update_issuance_by_issuer`, `mandates_update_acceptance_by_receiver`, `mandates_update_revocation_by_issuer` réécrites avec `is_org_admin(...)`. RPC `accept_project_invitation`/`decline_project_invitation` : ajout d'une vérification explicite `is_org_admin(receiver_org_id)` en plus de l'appartenance. La lecture (`SELECT`) reste ouverte à tout membre actif, conforme à la matrice (« Lecture si autorisé »). |
| INC-S06-04 | Observation structurelle (pas un bug isolé, un patron à surveiller) : PostgreSQL combine les clauses `WITH CHECK` de **toutes** les policies UPDATE permissives applicables par OR, pas seulement celle dont le `USING` a sélectionné la ligne. Conséquence démontrée : l'émetteur (dont le `USING` de la policy de révocation correspond) a pu modifier `end_date` sur un mandat `active` sans le révoquer, car le `WITH CHECK` de la policy d'acceptation (`status IN ('active','revoked')`) était satisfait par OR même si son propre `USING` (côté récepteur) ne correspondait pas à cette ligne. | Plusieurs policies UPDATE sur la même table, avec des `WITH CHECK` qui se chevauchent sur les mêmes valeurs de `status`, créent des combinaisons de droits non prévues individuellement par chaque policy. | Le trigger de gel (INC-S06-02) neutralise l'impact concret sur les 4 champs sensibles. Aucune correction supplémentaire appliquée pour `start_date`/`end_date` (hors du périmètre de `MVP-RA-029`, jugé acceptable que l'émetteur ajuste ces dates). **Point de vigilance à documenter pour toute nouvelle table à policies UPDATE multiples** : préférer une seule policy par table avec toute la logique de transition explicite, ou un trigger faisant autorité sur les champs sensibles plutôt que de compter sur des `WITH CHECK` mutuellement exclusifs. |

**Méthode de test** : environnement PostgreSQL 16 local, 6 organisations et 8 comptes utilisateurs simulés (admins et membres non-admins), 8 mandats de test couvrant tout le cycle de vie (`draft → pending_acceptance → active → revoked`, refus direct, expiration `end_date`, auto-mandat, accès inter-organisation). Script rejoué deux fois pour confirmer l'idempotence. `pg_policies` audité après correction, aucune récursion introduite.

**État après correction** : les 4 bugs sont corrigés et revalidés par re-test direct (nouvelles organisations, nouveaux mandats, pour éviter toute contamination par les données du premier passage). Aucune régression détectée sur les comportements déjà validés (RT-07, `MVP-DA-017`, isolation inter-organisations, révocation).

**Nettoyage** : base de test locale, aucune donnée n'a touché Supabase — cette revue a eu lieu **avant** toute fusion/déploiement, contrairement aux sessions S02-S04.

---

## 9ter. Dérive découverte — `is_org_admin()` absente des migrations versionnées — 12 juillet 2026

Le garde-fou ajouté à la migration S06 (§0 : vérification de l'existence de `public.is_org_admin(uuid)` avant d'exécuter le reste du script) a révélé que cette fonction — documentée dans ce registre comme créée à `INC-S02-07` — **n'existe dans aucun fichier de migration versionné du dépôt** (`supabase/migrations/`). Elle a donc soit été appliquée directement dans le SQL Editor Supabase hors migration, soit perdue lors du `DROP SCHEMA public CASCADE` de l'incident §6 et jamais réintégrée — exactement le type de régression tardive déjà anticipé dans les leçons retenues de la session S02 (*« une vérification exhaustive post-reset (fonctions, GRANTs, RPC) serait utile avant de considérer un reset de schéma comme totalement résorbé »*).

| Code | Constat | Cause probable | Correction |
|---|---|---|---|
| INC-S06-05 | `public.is_org_admin(p_organization_id)` absente de tous les fichiers `.sql` versionnés, alors que documentée comme livrée à `INC-S02-07` et réutilisée depuis (S06, et potentiellement `organizations_admin_update` — voir point de vigilance §7bis). | SQL Editor Supabase non versionné, ou perte lors du reset de schéma de l'incident §6. | Migration corrective `00_fix_is_org_admin.sql` créée : recrée uniquement la fonction (`SECURITY DEFINER`, `STABLE`, `SET search_path = public`), testée et confirmée fonctionnelle en environnement PostgreSQL 16 local, isolément puis enchaînée avec la migration S06 complète. |

**Portée volontairement limitée de la correction** : ce fichier ne touche **pas** aux policies `org_members_admin_insert`/`_update`, que l'ADR indique avoir été « réécrites pour appeler » `is_org_admin()` à `INC-S02-07`. Puisque la fonction elle-même était absente des migrations, ces deux policies pourraient être dans le même cas — jamais matérialisées en migration, ou encore sur l'ancienne logique tautologique de l'incident. Une requête de diagnostic (`SELECT ... FROM pg_policies WHERE tablename = 'organization_members'`) est fournie en commentaire dans le fichier correctif pour vérifier leur état réel avant toute intervention supplémentaire — les recréer à l'aveugle sans connaître la logique exacte du trigger d'`INC-S02-05` risquerait de réintroduire un bug plutôt que de le corriger.

**Diagnostic exécuté le 12 juillet 2026 — résultat : cas (a) confirmé.** Les 5 policies réelles de `organization_members` référencent bien `is_org_admin(organization_id)` (`org_members_admin_insert`, `org_members_admin_update`) exactement comme décrit dans ce registre — aucune trace de la logique tautologique d'origine. Elles n'étaient pas bogue mais **inertes** : `CREATE POLICY` référençant une fonction inexistante échoue à la création (reproduit expérimentalement), ce qui confirme qu'`is_org_admin()` existait bien en base au moment de leur création — cohérent avec l'hypothèse « appliquée hors migration ». Conséquence plus large que prévu : un rebuild complet du schéma depuis les migrations versionnées aurait échoué à *recréer* ces policies, pas seulement à les exécuter à l'exécution.

Revalidé en environnement PostgreSQL 16 local avec les 5 policies exactes : après application de `00_fix_is_org_admin.sql`, un admin insère correctement un nouveau membre, un non-admin est rejeté, et aucune récursion (requête `SELECT count(*)` sur `organization_members` : 0,9 ms). **Aucune correction supplémentaire requise** sur `organization_members` — la migration corrective de la fonction suffit à tout réparer.

**Réconciliation réelle du dépôt (12 juillet 2026, poursuite via CLI Supabase)** : `supabase migration list` sur le vrai dépôt (`metalvision`, 54 fichiers de migration) a confirmé que la colonne Remote était vide sur **toute la ligne** — pas seulement autour d'`is_org_admin`. La table de suivi `supabase_migrations.schema_migrations` n'avait jamais été renseignée pour ce projet (cohérent avec des changements historiquement appliqués hors CLI). Réparé via `supabase migration repair --status applied` sur les 54 timestamps (aucune exécution SQL, uniquement la table de suivi) — confirmé synchronisé par un second `migration list`.

**Précision (12 juillet 2026, post-découverte)** : le trou séparé sur `aggregators`/`aggregator_admins` révélé par `supabase db pull` (rejeu complet de l'historique en échec — `relation "public.aggregators" does not exist`) est un résidu d'une **application antérieure** développée sur ce même projet Supabase avant le pivot vers MetalTrace/CCF. Cohérent avec `DT-04` déjà consigné au §5 (domaine Agrégateurs, hors périmètre MVP CCF). Ce n'est pas un bug introduit par Rocket ni par S06 — traité comme dette technique pré-existante, pas comme priorité immédiate. Décision : ne pas tenter de réconcilier l'historique complet des 54 migrations pour l'instant ; capturer `is_org_admin` directement via un nouveau fichier de migration ciblé plutôt que via `db pull` (qui nécessite un rejeu complet et valide de tout l'historique, actuellement impossible à cause de ce trou antérieur).

**Déploiement final (12 juillet 2026)** : `20260712053146_fix_is_org_admin_missing.sql` (recréation idempotente de la fonction, marquée `applied` via `migration repair` puisque déjà présente sur le remote) puis `20260712054247_ccf_012_mandates_s06.sql` (migration S06 complète, version corrigée post-revue) tous deux committés sur `main` (dépôt `metalvision`) et appliqués avec succès via `supabase db push` sur le projet METALVISION. Aucune erreur — uniquement des `NOTICE ... does not exist, skipping` attendus (premiers `DROP ... IF EXISTS` sur des objets encore inexistants). **S06 est en production.** Reste à faire : exécuter le protocole de test complet (`Protocole-Test-S06-Mandats.md`) directement sur METALVISION pour validation fonctionnelle end-to-end.

**PR parallèle fermé sans fusion (12 juillet 2026)** : la branche `rocket-update` (fichier `supabase/migrations/20260712020000_s06_mandates_complete.sql`) contenait la toute première version du script S06, générée par Rocket avant la revue — les 4 bugs `INC-S06-01` à `04` y étaient tous encore présents (policies utilisant `user_org_ids()` au lieu d'`is_org_admin()`, policy d'émission `draft → pending_acceptance` toujours absente). Vérifié directement via `git show origin/rocket-update:...` avant toute décision. PR fermé sans fusion pour éviter d'écraser la version corrigée déjà déployée sur `main`. **Branche supprimée le 12 juillet 2026** (voir §9quinquies) après confirmation qu'elle était entièrement contenue dans l'historique de `main` (`git merge-base --is-ancestor origin/rocket-update origin/main` → vrai, 0 commit d'avance).

---

## 9quater. Test S06 en production (base de données seulement) — 12 juillet 2026

Premier test réel contre METALVISION (pas un environnement de simulation), exécuté via le SQL Editor Supabase avec de vraies organisations existantes (Acier Laurentien Inc., RecyclMétal Estrie). Couvre uniquement la partie base de données du protocole de test (§1-3 de `Protocole-Test-S06-Mandats.md`) — **l'écran `/mandats` n'existe pas encore**, donc les tests RLS multi-comptes et le parcours navigateur (§4-5) restent à faire une fois l'écran construit par Rocket. Le SQL Editor s'exécute en rôle `postgres` (superutilisateur), qui contourne RLS par nature — ces résultats valident la structure, les triggers et les transitions d'état, pas encore les policies RLS elles-mêmes avec de vrais comptes.

**Résultat : tout conforme, aucun bug trouvé.**

| Vérification | Résultat |
|---|---|
| Structure `mandates` (colonnes, types) | Conforme — `mandate_scope` bien en ENUM (`USER-DEFINED`) |
| Contrainte `status` (5 valeurs fermées) | Conforme |
| Contrainte auto-mandat interdit | Présente et fonctionnelle — **nom réel `mandates_different_orgs`**, différent du nom documenté (`mandates_issuer_receiver_distinct`) dans les instructions initiales à Rocket. Écart cosmétique sans impact fonctionnel, à corriger dans la documentation. |
| Catalogue `mandate_actions` | Exactement les 10 actions canoniques du cahier §4.2 |
| Trigger RT-07 | Présent (`validate_mandate_permissions_trigger`) et fonctionnel — action inconnue rejetée, action valide acceptée |
| Trigger MVP-RA-029 (`mandates_enforce_active_freeze`) | Présent et fonctionnel — modification de `mandate_scope` sur mandat `active` rejetée avec le message attendu |
| Transition `draft → pending_acceptance → active` | Réussie en base (non testée via RLS/policy à ce stade) |
| `is_mandate_effective()` (MVP-DA-017) | Retourne `true` pour un mandat actif sans `end_date`, conforme |

**Nettoyage effectué** : mandat de test supprimé après validation, aucune donnée résiduelle en production.

**Aucune action corrective requise.** Prochaine étape : compléter les tests RLS multi-comptes et le parcours navigateur une fois l'écran `/mandats` livré par Rocket — voir §9quinquies.

---

## 9quinquies. Revue de code S06 (Mandats) — écran frontend, 12 juillet 2026

Suite à §9quater, Rocket a construit l'écran `/mandats` (`src/app/mandats/page.tsx`, ~1000 lignes) — création de mandat, envoi, acceptation (branches autonome/projet selon MVP-DA-019), refus, révocation, filtres et panneau de détail. Revue de code complète effectuée avant de considérer l'écran validé, avec un focus particulier sur la duplication d'écritures `business_events` entre RPC (insertion server-side) et frontend (insertion manuelle) — patron de bug déjà rencontré ailleurs dans le projet et désormais consigné dans une checklist dédiée (voir plus bas).

**Résultat : 1 bug réel trouvé et corrigé.**

| Code | Constat | Cause racine | Correction |
|---|---|---|---|
| INC-S06-06 | `handleAcceptStandalone` (acceptation d'un mandat autonome) insérait manuellement un événement `business_events` (`mandate_accepted`) après l'appel à la RPC `accept_mandate()` — qui insère déjà cet événement elle-même côté serveur (voir `20260712075446_accept_mandate_rpc.sql`, ligne 35). Doublon confirmé en base à chaque acceptation. | Insertion manuelle laissée dans le frontend après l'introduction de la RPC `accept_mandate()` (créée pour séparer les branches MVP-DA-019) — la RPC a absorbé une responsabilité que le frontend assumait auparavant seul, sans que l'appel manuel correspondant soit retiré. | Insertion manuelle supprimée dans `handleAcceptStandalone`, remplacée par un commentaire renvoyant à la RPC comme source unique de vérité pour cet événement. Commit `957c1d7` sur `main`. |

**Vérifié sans bug** : `handleDecline`/`decline_project_invitation` — aucune insertion manuelle côté client, la RPC gère seule l'insertion server-side (`mandate_revoked`, `reason: declined_by_receiver`). Balayage complet du fichier confirmé : 3 insertions `business_events` au total (`handleSend`, `handleAcceptStandalone`, `handleRevoke`), 2 appels RPC (`accept_mandate`, `decline_project_invitation`) — seul le croisement RPC × insertion manuelle sur `accept_mandate` était fautif ; `handleSend`/`handleRevoke` ne passent par aucune RPC (simple `UPDATE` direct sur `mandates`), donc leur insertion manuelle est légitime. Confirmé également que le trigger `audit_mandates` (créé à CCF-008) écrit exclusivement dans `audit_logs`, jamais dans `business_events` — aucun risque de collision entre les deux journaux, cohérent avec la séparation documentée à CCF-008 (« un fait ne doit jamais figurer dans les deux journaux »).

**Point de conception à clarifier avec Rocket (pas un bug)** : le bouton « Refuser » appelle systématiquement `decline_project_invitation`, y compris pour un mandat autonome — alors que l'acceptation respecte la séparation stricte `accept_mandate`/`accept_project_invitation` de MVP-DA-019 (voir note ajoutée à MVP-DA-019, §1). Fonctionne correctement car la RPC ne dépend pas du `project_id`, mais le nommage est trompeur et casse la symétrie du modèle. À renommer ou à scinder en `decline_mandate`/`decline_project_invitation` par cohérence, dans une prochaine itération.

**Suites données à cette session :**
- Correctif `INC-S06-06` commité et poussé sur `main` (`957c1d7`).
- Branche distante `rocket-update` (PR fermé sans fusion, voir §9bis) supprimée — confirmée comme entièrement contenue dans l'historique de `main` (`git merge-base --is-ancestor`), donc aucune perte de contenu.
- Checklist de revue systématique créée (`ROCKET_REVIEW_CHECKLIST.md`, commit `1f0b8a7`), consolidant les patrons récurrents des incidents `INC-S06-01` à `06` (RLS, triggers de gel, doublons `business_events`, symétrie des RPC, idempotence des migrations, process git) — à appliquer à chaque futur livrable de Rocket, avant fusion sur `main`.

**État de S06 après cette session : complet.** Backend déployé et testé sur METALVISION (§9quater), frontend construit par Rocket et revu (cette section) — écran `/mandats` validé, un seul correctif nécessaire. Prêt à passer à l'écran suivant de la roadmap 30-60-90.

---

## 9sexies. PR de Rocket refusé — `decline_mandate` — 12 juillet 2026

En réponse au point de nommage soulevé en §9quinquies, Rocket a ouvert une nouvelle branche `rocket-update` (commit `f04e3fd`) proposant `decline_mandate()` (RPC symétrique à `accept_mandate()`) et la mise à jour de `handleDecline` dans `page.tsx` pour router selon `mandateProjectMap`. **PR revu avant fusion, comme prescrit par `ROCKET_REVIEW_CHECKLIST.md` — rien fusionné.**

| Code | Constat | Détail |
|---|---|---|
| INC-S06-07 | `decline_mandate()` vérifiait `v_mandate.receiver_org_id NOT IN (SELECT user_org_ids())` au lieu d'`is_org_admin()` — régression exacte du patron `INC-S06-03` (n'importe quel membre actif, pas seulement un admin, aurait pu refuser un mandat). | Repéré par lecture directe du commit sur `origin/rocket-update` (`git show`), pas seulement du snippet fourni par Rocket. |
| INC-S06-08 | `decline_mandate()` insérait `event_type: 'mandate_declined'` — valeur absente de l'ENUM `ccf_event_type` (`20260710001000_ccf_001_enums.sql` ne définit que `mandate_issued`/`mandate_accepted`/`mandate_revoked`). Le premier appel aurait levé `invalid input value for enum ccf_event_type`. | Confirmé par grep direct sur la définition de l'ENUM avant tout jugement. |
| — | La branche réintroduisait aussi `supabase/migrations/20260712020000_s06_mandates_complete.sql` (le tout premier script buggé de Rocket, `INC-S06-01` à `04`, déjà écarté au §9bis/§9ter) et faisait régresser `ADR-MVP.md` de 135 lignes vers une version antérieure à cette session. | Diagnostic : `git diff origin/main origin/rocket-update` — la branche a été construite depuis une copie locale périmée du dépôt (page.tsx et ADR-MVP.md d'avant les corrections de cette session), pas depuis `main` à jour, malgré que `main` soit techniquement un ancêtre du commit. |

**Décision : rien pris de cette branche.** Seule la logique de routage (`getAcceptType`/`mandateProjectMap` pour choisir la RPC) était correcte dans l'intention — réécrite indépendamment plutôt que copiée, avec `is_org_admin()`, `event_type = 'mandate_revoked'`, et un garde-fou supplémentaire (rejet si le mandat est lié à un `project_participants`, symétrique à `accept_mandate()`) qui manquait même dans la version de Rocket. Migration `20260712080000_decline_mandate_rpc.sql` créée et poussée directement sur `main`. `handleDecline` dans `page.tsx` mis à jour pour router via `getAcceptType(mandate.id)`.

**Leçon retenue, à ajouter à `ROCKET_REVIEW_CHECKLIST.md`** : un agent qui « corrige » un point signalé peut réintroduire un bug déjà résolu ailleurs dans le même fichier ou le même domaine (ici : le contrôle admin, déjà cassé une fois à `INC-S06-03`) — ne jamais faire confiance à un correctif isolé sans revérifier les patrons déjà documentés dans ce registre pour la même table/fonction. Vérifier aussi systématiquement que la branche a été construite depuis `main` à jour (`git diff origin/main origin/<branche>` sur l'ensemble des fichiers, pas seulement celui censé être modifié) avant toute revue de contenu.

---

## 9septies. Revue backend S07 (Documents) — avant construction du frontend, 12 juillet 2026

Suivant la même discipline que S06 (§9bis) : revue complète du backend documents (`ccf_006`, `ccf_006b`, `ccf_006c`, complété par `ccf_010`) **avant** de briefer Rocket sur la construction de l'écran `/documents`, plutôt qu'après. Migrations couvertes : `20260710006000_ccf_006_documents.sql` (table, contrainte, RLS de base), `20260710006100_ccf_006b_documents_project_policy.sql` (policy `documents_project_select`, isolée pour une raison d'ordre de dépendance au parsing), `20260710006200_ccf_006c_documents_project_visibility_check.sql` (ré-application de MVP-RA-026).

**Résultat : 2 problèmes réels trouvés (aucun bug actif — l'un latent, l'autre documentaire), tous deux corrigés avant tout travail frontend.**

| Code | Constat | Cause racine | Correction |
|---|---|---|---|
| INC-S07-01 | `approve_documents` est une action canonique du catalogue fermé `mandate_actions` (confirmée comme scope MVP réel par le cahier fonctionnel v1.2 et le backlog technique v1.0 — pas une hypothèse). Un mandat peut légitimement porter cette permission, validée par le trigger `validate_mandate_permissions_trigger`. Mais **aucune policy RLS, RPC ou fonction n'exploitait jamais cette permission** : la seule policy `UPDATE` sur `documents` (`documents_owner_admin_update`) ne laissait que l'admin de l'organisation propriétaire modifier un document. Un mandataire tiers (ex. coordonnateur de projet détenant un mandat `approve_documents`) n'avait donc aucun moyen d'approuver ou de refuser un document déposé par une autre organisation — permission présente dans le modèle de données, jamais appliquée. Confirmé par grep exhaustif du dépôt : aucune référence à `mandates.permissions` nulle part dans le code touchant `documents`. | Le backlog technique (tâches `E09-T01` à `T04`) ne liste aucune tâche d'implémentation pour l'approbation mandatée — seulement la table, le stockage, le dépôt et le versionnement. Scope oublié plutôt que report volontaire assumé. | RPC `public.approve_document(p_document_id, p_decision)` créée (`SECURITY DEFINER`), `20260712101000_ccf_006e_documents_mandate_approval.sql`. Vérifie qu'un mandat actif, lié au projet propriétaire du document via `project_participants.mandate_id`, porte `approve_documents` dans `permissions.actions`, et que l'utilisateur courant appartient à l'organisation réceptrice de ce mandat. Repli conservé : l'admin de l'organisation propriétaire du document garde son accès direct existant. La policy `documents_owner_admin_update` n'a **pas** été modifiée — correction additive, aucun comportement existant retiré. **Consigne frontend (S07)** : toute transition de statut (`submitted → approved/rejected`) doit passer exclusivement par cette RPC, jamais par un `UPDATE` direct depuis le client, pour garantir un `business_event` unique (cf. `INC-S06-06`). |
| INC-S07-02 | L'ENUM `ccf_event_type` ne contenait que `document_submitted`/`document_approved`. Or `documents.status` autorise aussi `rejected` et `archived` (CHECK dans `ccf_006`). Toute future écriture d'un `business_event` pour un refus ou un archivage aurait échoué à l'exécution (`invalid input value for enum ccf_event_type`) — même patron qu'`INC-S06-08`, détecté ici de façon proactive, avant que Rocket ne construise le frontend et ne heurte l'erreur en production. | Catalogue `event_type` du backlog technique limité à 17 valeurs, jamais étendu lors de l'ajout des statuts `rejected`/`archived` sur `documents.status`. | `ALTER TYPE public.ccf_event_type ADD VALUE IF NOT EXISTS` pour `document_rejected` et `document_archived` (`20260712100000_ccf_006d_documents_event_types.sql`), plutôt qu'un `DROP TYPE CASCADE` (éviterait de recréer un type déjà référencé par `business_events`). |

**Constats mineurs, sans impact fonctionnel :**
- `ccf_006c` : en-tête étiquetait la contrainte `documents_project_visibility_requires_project_object` comme "MVP-RA-028" (règle sans rapport, l'interdiction de l'auto-mandat) au lieu de MVP-RA-026 (la bonne règle, celle réellement appliquée par le code SQL). Commentaire corrigé directement dans le fichier source.
- `ccf_010` (`20260710010000_ccf_010_rls_policies.sql`) contient une policy `documents_via_project_ids`, fonctionnellement redondante avec `documents_project_select` (ccf_006b) — même effet obtenu par deux chemins différents (`user_project_ids()` vs `EXISTS` direct sur `project_participants`). Pas un risque de sécurité, simple dette à nettoyer lors d'un futur passage de consolidation RLS — non traité dans cette session pour ne pas toucher à du code fonctionnel sans nécessité.

**Conforme, vérifié sans écart :**
- MVP-RA-026 (contrainte `visibility='project' ⇒ object_type='project'`) — appliquée deux fois (ccf_006 et ccf_006c), redondance harmless (`DROP CONSTRAINT IF EXISTS` avant chaque `ADD CONSTRAINT`, donc idempotent).
- MVP-RA-027 (policy `documents_confidential_select`, 5 branches : déposant, opportunité, projet, value_report, mandat) — toutes les branches attendues sont présentes et correctement écrites.
- Absence de policy `DELETE` sur `documents` — conforme à MVP-DA-006 (suppression physique interdite par conception, cycle de vie géré par `status`).

**Aucune donnée n'a été touchée sur METALVISION pour cette session — revue de code statique uniquement, aucun déploiement encore effectué pour `ccf_006d`/`ccf_006e`.**

**Validation en production (12 juillet 2026, suite à cette session) :** `20260712100000_ccf_006d_documents_event_types.sql` et `20260712101000_ccf_006e_documents_mandate_approval.sql` déployés sur METALVISION (`supabase db push`, sans erreur). `approve_document()` testé directement via le SQL Editor Supabase avec des données réelles : projet de test référençant l'opportunité existante `5fff231b` (non modifiée), mandat actif `verification` avec `approve_documents` émis par Centre de Consolidation Ferroviaire Québec vers Test no 2, `auth.uid()` simulé pour un membre actif réel de Test no 2 (`claudefairplay@hotmail.com`). Résultat : document transitionné `submitted → approved`, `business_event` `document_approved` confirmé avec `actor_id`/`organization_id` corrects et `payload.via_mandate_id` prouvant que le chemin emprunté est bien celui du mandat (pas le repli admin propriétaire). **INC-S07-01 est corrigé et validé en production.** Toutes les données de test supprimées après validation (projet, mandat, participation, document, événement) — aucune donnée résiduelle.

**Limite notée pendant le test** : les organisations réelles du projet CCF (Centre de Consolidation Ferroviaire Québec, Acier Laurentien Inc., RecyclMétal Estrie) n'ont aucun compte utilisateur actif rattaché — même limitation déjà documentée en `INC-S03-09`. Le test a donc utilisé un projet isolé construit sur les organisations de démonstration (`Test Organisation`, `Test no 2`), qui ont de vrais comptes. Un jeu de données pilote complet (compte utilisateur réel par organisation du projet CCF) reste recommandé avant une démonstration externe — déjà noté à plusieurs reprises dans ce registre (§8, Annexe C du cahier fonctionnel).

**État de S07 après cette session : backend complet, corrigé et validé en production.** Reste à construire le frontend `/documents` (brief à donner à Rocket, avec consigne explicite d'utiliser `approve_document()` pour toute transition de statut).

---

## 9octies. PR Rocket — frontend S07 (Documents) : accepté partiellement — 12 juillet 2026

Rocket a ouvert une nouvelle branche `rocket-update` (commit `8a7b5bd`, un seul commit, parent = `main` à jour au moment du diff) livrant l'écran `/documents` en réponse au brief (`Brief-Rocket-S07-Documents.md`). **PR revu intégralement avant toute fusion — `git diff origin/main origin/rocket-update` sur l'ensemble des fichiers, conformément à `ROCKET_REVIEW_CHECKLIST.md`.**

**Résultat : le contenu réellement neuf est correct ; le reste du commit contient des régressions sérieuses. Rien fusionné tel quel — 2 fichiers cherry-pickés indépendamment, 1 vrai gap corrigé.**

### Contenu neuf — vérifié correct

| Fichier | Constat |
|---|---|
| `src/app/documents/page.tsx` (885 lignes) | Machine à états conforme au brief : `draft→submitted` et `approved/rejected→archived` en `UPDATE` direct + insertion manuelle `business_events` ; `submitted→approved/rejected` **exclusivement** via `approve_document()`, avec commentaire explicite renvoyant à `INC-S06-06` pour justifier l'absence d'insertion manuelle. Visibilité `'project'` masquée dans le formulaire tant que `object_type ≠ 'project'` (MVP-RA-026), avec garde-fou dupliqué à la soumission. Aucun bouton de suppression. Filtrage des documents laissé à la RLS (pas de filtre client redondant). |
| `src/components/Sidebar.tsx` | Ajout de l'entrée « Documents » à `clientNav` et `adminNav`, groupe `réseau` — diff minimal (2 lignes), rien d'autre touché. |

### INC-S07-03 — Bucket Supabase Storage `documents` jamais configuré

| Code | Constat | Cause racine | Correction |
|---|---|---|---|
| INC-S07-03 | `E09-T02` du backlog technique (« Configurer Supabase Storage et lien `storage_path` ») n'a jamais été réalisé, par personne — confirmé par `SELECT * FROM storage.buckets` en production (0 ligne). Le nouvel écran appelle `supabase.storage.from('documents').upload(...)`, qui aurait échoué systématiquement sans bucket ni policies. | Tâche du backlog jamais traitée dans les migrations `ccf_006`/`006b`/`006c` (qui ne couvrent que la table, pas le stockage). | Migration `20260712110000_ccf_006f_documents_storage_bucket.sql` : bucket privé `documents` ; policy `INSERT` gardée par `is_organization_owner()` sur l'org extraite du chemin (`documents/<owner_org_id>/<fichier>`, aucune ligne `documents` n'existe encore à l'upload, donc impossible de déléguer à sa RLS à ce stade) ; policy `SELECT` déléguée à la RLS déjà existante sur `public.documents` via une fonction `SECURITY INVOKER` (pas `DEFINER`) — évite de dupliquer les 3 branches de visibilité une deuxième fois dans `storage.objects`. Aucune policy `UPDATE`/`DELETE` (deny-all, cohérent avec MVP-DA-006). |

### INC-S07-04 — Troisième occurrence du patron « branche construite depuis une copie locale périmée »

| Code | Constat | Détail |
|---|---|---|
| INC-S07-04 | Le reste du commit `8a7b5bd` (au-delà des 2 fichiers neufs ci-dessus) régresse silencieusement du contenu déjà corrigé, malgré un parent Git techniquement à jour (`main` HEAD exact) : (1) `ADR-MVP.md` écrasé ~188 lignes en arrière, vers une version antérieure même à la session S06 (absence de `MVP-DA-017/018/019`, `MVP-RA-028/029`, §7bis à §9septies) ; (2) `src/app/mandats/page.tsx` réintroduit le doublon `business_events` d'`INC-S06-06` dans `handleAcceptStandalone`, **et** remplace le routage `decline_mandate`/`decline_project_invitation` (`getAcceptType`) par une logique différente jamais revue ; (3) le commentaire corrigé de `ccf_006c` repasse de `MVP-RA-026` à l'ancien `MVP-RA-028` erroné ; (4) deux anciens fichiers de migration déjà écartés reviennent dans l'arborescence : `20260712020000_s06_mandates_complete.sql` (le tout premier script S06 buggé, `INC-S06-01` à `04`) et `20260712030000_s06_decline_mandate_rpc.sql` (une version antérieure jamais déployée de `decline_mandate`). | **Troisième occurrence exacte du même patron** que `INC-S06-07`/`08` (§9sexies) : un parent de commit à jour n'implique pas que le contenu committé soit à jour — l'agent semble committer l'intégralité de son espace de travail local sans le resynchroniser (`git pull`) avant de partir d'une nouvelle branche. Un simple `git merge-base --is-ancestor` ou une vérification du seul fichier annoncé comme modifié n'aurait rien détecté ici non plus. |

**Décision : aucune fusion de la branche.** Les 2 fichiers vérifiés corrects (`documents/page.tsx`, `Sidebar.tsx`) ont été extraits directement de l'objet Git du commit `8a7b5bd` et appliqués indépendamment sur `main` à jour — jamais via `git merge`/`git pull` de la branche elle-même, pour garantir qu'aucun des 4 éléments régressés ne puisse être réintroduit par accident. **PR fermé sans fusion sur GitHub ; branche `rocket-update` supprimée (12 juillet 2026)** — non ancêtre de `main` cette fois (normal : rien construit par-dessus son contenu, seuls les 2 fichiers vérifiés en ont été extraits), aucune perte puisque tout le contenu à conserver était déjà appliqué indépendamment sur `main`.

**Validation end-to-end en production (12 juillet 2026, suite à cette session)** : `20260712110000_ccf_006f_documents_storage_bucket.sql` déployé sur METALVISION. Test complet réalisé directement dans l'interface `/documents` (pas seulement en SQL Editor, contrairement à `INC-S07-01`) : dépôt d'un fichier réel (upload Storage confirmé 200, `object_type = 'project'`, `visibility = 'organization_private'`) → `draft → submitted` (bouton "Soumettre") → `submitted → approved` (bouton "Approuver", via `approve_document()`). `business_events` vérifié : exactement 2 lignes (`document_submitted`, `document_approved`), aucun doublon. Un bug mineur relevé pendant le test (hors périmètre de correction immédiate) : le champ "ID de l'objet" du formulaire de dépôt est un texte libre sans validation de format ni sélecteur, et la gestion d'erreur du formulaire n'affiche pas le message Postgres réel (`e instanceof Error` est faux pour une `PostgrestError`, donc un message générique "Erreur lors du dépôt" masque la cause exacte) — à corriger dans une prochaine itération frontend, noté ici pour ne pas le perdre. Données de test supprimées après validation (document, business_events ; le fichier Storage résiduel n'a aucun impact, plus aucune ligne `documents` n'y fait référence).

**État de S07 après cette session : complet, corrigé, et validé de bout en bout en production — backend et frontend.**

**Action de fond recommandée, au-delà du correctif ponctuel** : ce patron s'est maintenant reproduit 3 fois avec les mêmes symptômes exacts. Une simple checklist de revue ne suffit plus à en réduire le risque côté livraison — la cause se trouve dans le processus de travail de Rocket lui-même (environnement local non resynchronisé avant chaque nouvelle branche), hors du contrôle de cette revue. À signaler explicitement à Rocket comme correctif de processus à faire de son côté, pas seulement comme un bug de plus à corriger après coup.

---

## 9novies. Revue backend S08 (Événements) — avant construction du frontend, 12 juillet 2026

Même discipline que S06/S07 : revue du backend événements (`ccf_008_business_events_audit.sql`) avant de briefer Rocket sur l'écran `/evenements`. Contrairement aux deux écrans précédents, **aucun bug ni gap bloquant trouvé** — comparable au résultat de la session S04 (§9).

**Vérifié conforme :**
- `business_events` : RLS `SELECT` = membre de l'organisation enregistrée sur l'événement OU acteur lui-même OU super-admin ; `INSERT` = acteur = utilisateur courant (`actor_id = auth.uid()`) — correspond exactement à la spécification du backlog technique (« Lecture contexte autorisé ; insertion par service applicatif sous contexte utilisateur »). L'absence de contrôle fin sur *quel* `event_type`/`object_id` un utilisateur peut publier est un choix de conception assumé dans le backlog, pas un oubli — le MVP fait confiance au code applicatif pour publier des événements cohérents avec l'action réellement effectuée, plutôt que de dupliquer cette logique dans les policies RLS.
- `audit_logs` : aucune policy d'écriture pour les utilisateurs authentifiés (seul `audit_log_trigger_fn()`, `SECURITY DEFINER`, y écrit) ; lecture réservée au super-admin plateforme — cohérent avec l'usage voulu (log technique, pas un écran utilisateur ; l'écran S08 n'affiche que `business_events`, jamais `audit_logs`, confirmé par le backlog technique).
- Séparation `business_events`/`audit_logs` : aucun trigger n'écrit dans `business_events`, seul le code applicatif le fait — cohérent avec la règle déjà documentée (« un fait ne doit jamais figurer dans les deux journaux »).
- Idempotence de la migration : `CREATE TABLE IF NOT EXISTS`, `DROP POLICY`/`DROP TRIGGER IF EXISTS` avant chaque recréation — conforme. Absence intentionnelle de bloc `DO $$ ... EXCEPTION`, documentée explicitement dans le fichier : une table cible absente doit faire échouer bruyamment la migration plutôt que de laisser silencieusement une table sans trigger d'audit.
- Catalogue `object_type` (`organization`, `capability`, `opportunity`, `project`, `mandate`, `document`, `logistics_step`, `value_report`) couvre bien les 8 types d'objets du domaine.

**Recommandation non bloquante notée pour plus tard** : `E10-T02` du backlog technique (« Créer service applicatif `publishBusinessEvent` ») n'a jamais été construit — chaque écran (`mandats`, `opportunities`, et maintenant `documents`) réimplémente son propre `supabase.from('business_events').insert(...)` en ligne. C'est directement le terrain sur lequel `INC-S06-06` (doublon d'événement) s'est produit : sans point d'entrée unique, chaque nouvel écran repart de zéro et peut réintroduire le même genre d'erreur. Ne bloque pas S08 (un journal en lecture seule n'a pas besoin de publier d'événements), mais vaut la peine d'être considéré lors d'un futur refactor frontend.

**Aucune donnée n'a été touchée sur METALVISION pour cette session — revue de code statique uniquement, aucune migration corrective nécessaire.**

**État de S08 après cette session : backend déjà complet et conforme, aucune correction requise. Prêt pour le brief Rocket sur le frontend (journal filtrable par objet/projet/organisation, composant `ObjectTimeline` réutilisable selon le backlog).**

---

## 9decies. PR Rocket — frontend S08 (Événements) : accepté partiellement — 12 juillet 2026, quatrième occurrence du même patron

Rocket a de nouveau ouvert `rocket-update` (commit `21e6659`, parent = `main` HEAD exact au moment du diff) livrant l'écran `/evenements` en réponse au brief (`Brief-Rocket-S08-Evenements.md`). Revu intégralement avant fusion.

**Contenu neuf — vérifié correct, identique en qualité aux livraisons précédentes :**

| Fichier | Constat |
|---|---|
| `src/app/evenements/page.tsx` (427 lignes) | Journal en lecture seule, filtres organisation/`object_type`/`object_id`, pagination 50/page, payload dépliable, clic sur un ID applique le filtre. Aucune écriture, aucune RPC — conforme au brief. |
| `src/components/ObjectTimeline.tsx` (201 lignes) | Composant autonome (`object_type`/`object_id` en props), exporte `EventTypeBadge`, `BusinessEvent`, `CcfEventType` pour réutilisation. Les 19 valeurs `ccf_event_type` mappées avec libellé français + repli générique pour toute valeur future inconnue. `evenements/page.tsx` importe correctement ces exports plutôt que de dupliquer la logique. |
| `src/components/Sidebar.tsx` | Diff minimal (2 lignes), construit correctement par-dessus l'entrée « Documents » déjà présente sur `main` — pas de régression ici. |

**Le reste du commit reproduit — au bit près, pas seulement dans l'esprit — les 4 régressions déjà documentées à `INC-S07-04`** : `ADR-MVP.md` écrasé (245 lignes de diff), `mandats/page.tsx` avec le même doublon `business_events` d'`INC-S06-06` réintroduit à l'identique, `ccf_006c` repassé à `MVP-RA-028`, et les 2 mêmes anciennes migrations S06 buguées (`20260712020000`, `20260712030000`) resurgissant mot pour mot. **Diff comparé ligne à ligne avec `INC-S07-04` : contenu strictement identique.**

| Code | Constat |
|---|---|
| INC-S08-01 | **Quatrième occurrence du patron `INC-S06-07/08` / `INC-S07-04`, avec une nuance significative : le contenu périmé réintroduit est byte-pour-byte identique à celui d'`INC-S07-04`, pas une nouvelle staleness indépendante.** Ceci indique que l'environnement de travail local de Rocket ne s'est *toujours* pas resynchronisé depuis au moins la session S06 — chaque nouvelle branche repart du même instantané figé (antérieur à la correction d'`INC-S06-06`), auquel seul le nouveau travail de la itération courante est ajouté par-dessus. Une resynchronisation ponctuelle après un signalement ne suffit pas : le problème est structurel côté Rocket, pas un oubli isolé. |

**Décision : identique à `INC-S07-04`.** Aucune fusion de la branche. Les 3 fichiers vérifiés corrects extraits directement de l'objet Git du commit `21e6659` et appliqués indépendamment sur `main` à jour. PR à fermer sans fusion ; branche à supprimer (sans besoin de vérifier l'ascendance cette fois — même raisonnement qu'à `INC-S07-04` : rien d'unique à préserver dans la branche au-delà de ce qui a déjà été extrait).

**Recommandation à ce stade** : ne plus se contenter de documenter chaque occurrence dans ce registre. Le correctif à ce patron ne peut pas venir de la revue — il faut communiquer directement à Rocket, en des termes explicites et non techniques si nécessaire, que son environnement de travail doit être réinitialisé depuis `origin/main` avant toute nouvelle branche, sans quoi ce même diagnostic se répétera indéfiniment à chaque nouvelle fonctionnalité livrée.

---

## 9undecies. Tests live complémentaires — S06 (multi-comptes) et S08 (UI) — 12 juillet 2026

Fermeture de deux trous de test identifiés en faisant le bilan de la couverture réelle de la session : la suite automatisée (63/63, §10) ne couvre que les opportunités/capacités, et plusieurs écrans n'avaient été validés qu'en lecture de code ou en base directe (rôle `postgres`, qui contourne RLS), jamais avec un vrai compte authentifié dans le navigateur.

### S06 (Mandats) — test RLS multi-comptes, jamais fait depuis §9quater

Noté comme « reste à faire » à la session §9quater (test DB-only sur METALVISION, rôle `postgres`) et toujours pas complété après la revue frontend de §9quinquies (qui a validé par lecture de code, pas par test live). Comblé maintenant avec deux comptes réels (`centredelasante@gmail.com`, admin de Test Organisation et Test no 2 ; `claudefairplay@hotmail.com`, membre non-admin de Test no 2 seulement) :

| Étape | Compte | Résultat |
|---|---|---|
| `draft → pending_acceptance` (émission) | `centredelasante` (admin Test Organisation) | Réussi — première transition d'état jamais déclenchée par un compte authentifié réel plutôt que par `postgres` ou un environnement simulé. |
| Tentative d'action sur le mandat reçu | `claudefairplay` (membre non-admin, Test no 2) | **Aucun bouton Accepter/Refuser affiché** — le frontend respecte la restriction admin-seulement (`INC-S06-03`) ; aucune tentative de contournement au niveau RPC n'a été nécessaire pour confirmer le comportement attendu côté UI. |
| `pending_acceptance → active` (acceptation) | `centredelasante` (admin Test no 2) | Réussi. |
| Vérification `business_events` | — | Exactement 2 lignes (`mandate_issued`, `mandate_accepted`), aucun doublon — confirme `INC-S06-06` avec un vrai compte, pas seulement en lecture de code. |

**S06 est maintenant testé de bout en bout avec de vrais comptes authentifiés, pas seulement en base directe ou en lecture de code.** Données de test supprimées après validation (mandat, y compris le brouillon créé dans le mauvais sens lors du premier essai, et ses `business_events`).

### S08 (Événements) — test live de l'écran, jamais fait

La revue de `INC-S08-01` (§9decies) n'avait porté que sur le code du PR, jamais sur l'écran réellement ouvert dans un navigateur. Test rapide effectué : `/evenements` affiche correctement le journal (11 événements au moment du test), badges de type colorés avec libellés français, IDs tronqués, et le filtre "Type d'objet" fonctionne (11 → 3 événements en sélectionnant "Organisation", chip actif affiché, bouton "Effacer les filtres" apparu). **Confirmé fonctionnel en direct**, pas seulement par lecture de code.

**État de la couverture de test après cette session : S02 à S08 ont tous été validés par un test réel (navigateur et/ou base directe avec de vrais comptes), au-delà de la seule lecture de code. La suite automatisée (§10, 63/63) reste datée d'avant S06 et ne couvre pas les mandats/documents/événements — à rejouer ou étendre si une validation automatisée complète est requise avant une démonstration externe.**

---

## 9duodecies. Revue backend S05 (Projet CCF) — avant construction du frontend, 12 juillet 2026

Même discipline que S06/S07/S08 : revue de `ccf_005` (`ccf_projects`, `project_participants`) et `ccf_007` (`logistics_steps`, `value_reports`, `ai_assistance_logs`) avant de briefer Rocket sur l'écran `/projets/:id` — l'écran le plus dense du MVP (participants, phases, documents, logistique, risques, rapport).

**Résultat : 1 bug réel trouvé et corrigé, 1 clarification de portée nécessaire (aucune table `risks` n'existe), le reste conforme.**

| Code | Constat | Cause racine | Correction |
|---|---|---|---|
| INC-S05-01 | La policy `project_participants_update` (ccf_005) autorise soit l'admin de l'organisation coordinatrice, soit l'admin de l'organisation participante elle-même, à modifier une ligne `project_participants` — sans restriction sur les colonnes modifiables. Un admin d'organisation participante pouvait donc réécrire sa propre colonne `mandate_id` vers **n'importe quel mandat existant dans la base**, sans validation que ce mandat concerne réellement ce projet ou cette organisation. Risque concret : `project_participants.mandate_id` est utilisé par `approve_document()` (`INC-S07-01`) pour vérifier l'éligibilité d'un mandataire — un admin aurait pu théoriquement pointer vers un mandat `approve_documents` obtenu ailleurs dans le système pour se rendre éligible à l'approbation de documents d'un projet sans rapport. | Aucune validation relationnelle entre `project_participants.mandate_id`, le projet et l'organisation participante — seule la policy RLS gardait l'accès en écriture, pas la cohérence des données. | Trigger `enforce_project_participants_mandate_consistency()` (`BEFORE INSERT OR UPDATE`) ajouté : rejette tout `mandate_id` dont le mandat n'est pas reçu par cette organisation (`receiver_org_id`) et émis par l'organisation coordinatrice du projet (`issuer_org_id`). N'affecte que les écritures futures. `project_participants.project_role`, en comparaison, n'est vérifié par aucune policy ni fonction RLS ailleurs dans le schéma (confirmé par grep) — une auto-élévation de ce champ reste cosmétique, aucune correction nécessaire sur ce point. |

**Clarification de portée (pas un bug)** : l'écran S05 est spécifié comme affichant « participants, phases, documents, logistique, **risques**, rapport » (backlog technique). Aucune table `risks` n'existe dans le schéma, et le cahier fonctionnel ne détaille jamais ce concept au-delà d'une mention générique. **Pour cette itération, "risques" devra être un indicateur calculé côté frontend** (ex. étapes logistiques `blocked`, dates `target_end_date` dépassées, participants `declined`) — pas une nouvelle table à faire construire par Rocket. À clarifier explicitement dans le brief pour éviter que Rocket n'invente une table ou ne bloque en attendant une clarification.

**Conforme, vérifié sans écart :**
- `ccf_projects` : SELECT (coordinateur + participants actifs), INSERT/UPDATE (admin coordinateur seul) — cohérent avec la matrice de permissions. Aucune machine à états stricte sur `phase`/`status` (contrairement aux mandats, `MVP-RA-029`) — flexibilité assumée, aucune règle métier documentée ne restreint les transitions de phase pour le MVP.
- `logistics_steps` : SELECT (coordinateur + org responsable), UPDATE restreinte à l'admin coordinateur OU un membre de l'org responsable avec `org_role = 'admin'` OU `operational_profile = 'terrain'` — conforme à `RLS-005` (« Seule `responsible_org_id` ou coordonnateur peut modifier l'étape »), avec une nuance additionnelle (profil terrain) déjà documentée dans le fichier source.
- `value_reports` : SELECT (coordinateur + participants actifs), INSERT/UPDATE réservés à l'admin coordinateur seul — cohérent avec US-010 (« Coordonnateur produit une synthèse »), aucun accès en écriture pour les participants.
- `ai_assistance_logs` : lecture/écriture strictement limitées à l'utilisateur lui-même (`user_id = auth.uid()`), super-admin en lecture complète — pas d'écran S05 dédié requis pour cette table dans l'immédiat (agent IA hors scope de cette itération).
- Catalogue `object_type`/`event_type` : `logistics_step`/`value_report` et `logistics_step_updated`/`value_report_generated` déjà présents — aucune extension d'ENUM nécessaire, contrairement à S07 (`INC-S07-02`).
- Flux d'invitation d'organisation à un projet (US-013) : déjà couvert par `accept_project_invitation()`/`decline_project_invitation()` (construites et testées à la session S06) — aucune nouvelle RPC à construire, seulement à exposer dans le contexte de l'écran S05 plutôt que seulement depuis `/mandats`.

**Aucune donnée n'a été touchée sur METALVISION pour cette session — revue de code statique uniquement. Migration `20260712120000_ccf_005b_project_participants_mandate_consistency.sql` créée, pas encore déployée.**

**État de S05 après cette session : backend revu et corrigé, prêt pour le brief Rocket sur le frontend.**

---

## 9terdecies. Revue PR Rocket S05 (`/projets`, `/projets/:id`) — 12 juillet 2026

PR reçue mais **non fusionnée** (branche `rocket-update` récupérée via `git fetch origin rocket-update` / `FETCH_HEAD`, jamais mergée directement — conformément à la règle établie depuis S06). Revue complète du diff (`git diff origin/main FETCH_HEAD --stat`), fichier par fichier, avant toute décision de fusion.

**Résultat : 5ᵉ occurrence confirmée du patron de régression récurrent (branche locale non resynchronisée) + 1 bug réel nouveau dans le code neuf (`INC-S05-02`). Les 3 fichiers neufs/légitimes ont été retenus et corrigés/cherry-pickés ; la branche n'a pas été fusionnée.**

### Régression récurrente — 5ᵉ occurrence

Comme pour `INC-S06-07/08`, `INC-S07-04` et `INC-S08-01`, le diff contient, en plus du travail demandé, la réintroduction du même contenu périmé déjà signalé quatre fois :
- `ADR-MVP.md` : 320 lignes de retrait, section historique écrasée par une version antérieure.
- `supabase/migrations/20260710006200_ccf_006c_documents_project_visibility_check.sql` : revert identique (5ᵉ fois) du commentaire `MVP-RA-028` → `MVP-RA-026`.
- `src/app/mandats/page.tsx` : réintroduction de l'insertion manuelle en double de `business_events` sur `handleAccept` (le doublon originel d'`INC-S06-06`, déjà retiré), et retour de `handleDecline` à son ancienne forme non symétrique (avant la correction `getAcceptType`/`mandateProjectMap`).
- Deux migrations fantômes réapparues telles quelles : `20260712020000_s06_mandates_complete.sql` et `20260712030000_s06_decline_mandate_rpc.sql` — copies des anciens fichiers déjà remplacés par `ccf_012_mandates_s06.sql`, `accept_mandate_rpc.sql` et `decline_mandate_rpc.sql` sur `main`.

Aucun de ces fichiers n'a été retenu. Le brief envoyé à Rocket pour cet écran incluait déjà, en tête, une consigne explicite de `git pull`/`git reset --hard origin/main` avant de démarrer — sans effet. Ce process reste donc non résolu côté Rocket.

### `INC-S05-02` — nouveau bug (pas une régression) : `object_id` erroné sur `value_report_generated`

Dans `src/app/projets/[id]/page.tsx`, `handleVRSave()` insérait manuellement l'événement `business_events` `value_report_generated` avec `object_type: 'value_report'` mais `object_id: project.id` — au lieu de l'identifiant de la ligne `value_reports` elle-même. Incohérent avec la convention établie en S07 (`ccf_006e` : `object_id` référence toujours l'objet visé par l'événement, jamais son parent). Conséquence : une requête `business_events` filtrée sur `object_type = 'value_report' AND object_id = <id réel du rapport>` ne retournerait jamais cet événement. Aggravé côté création : l'`INSERT` ne récupérait même pas l'`id` de la ligne nouvellement créée (`.insert(payload)` sans `.select()`), donc la valeur correcte n'était de toute façon pas disponible dans le code d'origine.

**Corrigé avant fusion** (dans le fichier cherry-pické, pas par Rocket) : ajout de `.select('id').single()` sur l'insertion, capture de `valueReportId` (= `editingVR.id` en mise à jour, = l'id retourné par l'insert en création), utilisé comme `object_id` de l'événement.

### Fichiers retenus (revus ligne par ligne contre `Brief-Rocket-S05-Projet.md`)

| Fichier | Verdict |
|---|---|
| `src/app/projets/page.tsx` (147 lignes) | Conforme — liste filtrable par phase, requête `ccf_projects` avec jointures `coordinator_org`/`opportunity`, aucun accès direct non filtré par RLS. |
| `src/app/projets/[id]/page.tsx` (1359 lignes après correction) | Conforme après correction d'`INC-S05-02`. Vérifié explicitement : `project_role` n'est utilisé nulle part pour une décision de permission (seuls `org_role`/`operational_profile` et `is_organization_owner` le sont) ; panneau "Risques" 100 % calculé côté frontend (étapes `blocked`, `target_end_date` dépassée, participants `declined`), aucune nouvelle table ni migration ; `ProjectDocumentUploader` réutilise correctement le pattern S07 avec `object_type`/`object_id` pré-remplis ; `LogisticsStepCard` affiche un message clair (pas une erreur brute) en cas de refus RLS (`code === '42501'`) ; `ObjectTimeline` réutilisé tel quel pour l'onglet Historique (`object_type="project"`) ; flux d'invitation (`accept_project_invitation`/`decline_project_invitation`) réutilisé sans aucune insertion manuelle de `business_events`, conforme à la consigne du brief. |
| `src/components/Sidebar.tsx` | Conforme — entrée "Projets" ajoutée avant "Documents" dans `clientNav` et `adminNav`, aucune régression, 5ᵉ diff Sidebar consécutif propre. |

**Ces 3 fichiers ont été cherry-pickés directement sur `main`** via `git hash-object`/`git update-index` (jamais de fusion de la branche `rocket-update`). Aucune nouvelle migration requise pour cet écran (toute l'infrastructure backend était déjà déployée en `INC-S05-01`, §9duodecies).

**Mise à jour post-déploiement (même session) :** le premier push (`d5c0e36`) a échoué en build Vercel (`BABEL_PARSER_SYNTAX_ERROR: Unterminated comment`, `src/app/projets/[id]/page.tsx:1359`). Cause : un incident de synchronisation côté agent de revue (pas Rocket) — le fichier corrigé (`INC-S05-02`) a été hashé et commité dans un état tronqué en raison d'un décalage du point de montage du bac à sable au moment du `git hash-object`. Corrigé par reconstruction intégrale du fichier (vérification des accolades/parenthèses équilibrées et de la fin de fichier avant re-commit) et repoussé (`b1d5109`) — déploiement Vercel "Prêt" confirmé.

**Test live confirmé** avec `centredelasante@gmail.com` sur le projet réel (Consolidation ferroviaire — Métaux ferreux et non-ferreux Q3 2026, coordonné par Centre de Consolidation Ferroviaire Québec) : `/projets` affiche la liste avec filtre par phase fonctionnel ; `/projets/:id` affiche correctement les badges Phase/Statut, l'onglet Logistique (3 étapes réelles avec statut/organisation/dates), l'onglet Historique (`project_created`, `project_phase_changed` via `ObjectTimeline`), et les onglets Participants/Risques/Rapport de valeur affichent correctement leur état vide (« Aucun participant/risque/rapport... ») — ce projet réel n'a simplement aucune ligne `project_participants` ni `value_reports`, cohérent avec la limite de données de démonstration déjà documentée (`INC-S03-09`). Aucun bug de rendu constaté.

**S05 est maintenant complet et validé de bout en bout en production**, au même niveau que S06/S07/S08.

**État de S05 après cette session : backend et frontend tous deux revus, corrigés, intégrés, déployés et validés en direct dans le navigateur. Écran terminé.**

---

## 9quaterdecies. Revue backend S09 (Cockpit exécutif) — avant construction du frontend, 12 juillet 2026

Référence : backlog technique v1.0, E12-T03 (« Créer cockpit exécutif projet : volumes, risques, avancement », livrable `S09 / US-014`), cahier fonctionnel v1.2, M10 (« Cockpit exécutif — indicateurs simples de valeur, avancement, risques, volumes et collaboration », priorité SHOULD). US-014 : « Comme coordonnateur, je peux consulter le cockpit exécutif d'un projet : volumes, risques et avancement. »

**Résultat : aucun bug, aucune nouvelle table, aucune nouvelle migration nécessaire — S09 est un écran de synthèse en lecture seule, entièrement calculé à partir de données déjà en place et déjà correctement protégées par RLS.**

Contrairement à E12-T01 (`value_reports`, une vraie migration) et E12-T02 (US-010, déjà couvert par l'écran S05), le ticket E12-T03 ne porte aucun livrable de migration — seulement `S09 / US-014`. Vérification faite : toutes les tables nécessaires (`ccf_projects`, `project_participants`, `logistics_steps`, `value_reports`) et leurs policies RLS ont déjà été revues et corrigées lors des sessions S05/S07/S08 (`INC-S05-01` notamment). Aucune policy dédiée au cockpit n'existe dans le catalogue `RLS-001` à `RLS-007` du backlog — confirmation que l'écran ne doit introduire aucune règle d'accès nouvelle, seulement agréger des lectures déjà autorisées.

**Décisions de portée à trancher avant le brief Rocket (aucune n'implique de changement backend) :**

| Point | Décision |
|---|---|
| Route | Le backlog liste `/cockpit` sans paramètre (contrairement à `/projets/:id`), alors que US-014 est explicitement scopée à *un* projet. Interprétation retenue : `/cockpit` affiche un sélecteur de projet (limité aux projets où l'utilisateur est admin de l'organisation coordinatrice — cohérent avec le « Comme coordonnateur » de US-014), puis la synthèse du projet sélectionné. Pas de nouvelle route paramétrée à créer. |
| Avancement | Aucune colonne `avancement`/`progress` en base. Calcul frontend à partir de `ccf_projects.phase` mappé sur 5 paliers (`draft`=0 %, `active`=25 %, `execution`=50 %, `review`=75 %, `closed`=100 %) — même principe que le panneau "Risques" de S05 (indicateur calculé, pas de nouvelle donnée). |
| Volumes / Valeur | Tirés de la ligne `value_reports` la plus récente du projet (`created_at` DESC, déjà l'ordre utilisé par l'écran S05) — pas d'agrégation/somme entre plusieurs rapports, pas spécifiée par le backlog. Si aucun rapport n'existe : afficher un état vide, pas une erreur. |
| Risques | **Réutiliser exactement la même logique que le panneau "Risques" de S05** (étapes `blocked`, `target_end_date` dépassée, participants `declined`) — ne pas la dupliquer ni la réécrire ; extraire en fonction partagée si Rocket le juge pertinent, mais le calcul lui-même ne doit pas diverger entre S05 et S09. |
| Synthèse direction | Présentation uniquement (cartes/indicateurs formatés) — aucune génération IA requise (`M11 Agent IA` est un module distinct, hors périmètre de ce ticket). |

**Aucune donnée n'a été touchée sur METALVISION pour cette session — revue de code/backlog uniquement, aucune migration créée.**

**État de S09 après cette session : backend confirmé conforme sans correction nécessaire, prêt pour le brief Rocket sur le frontend.**

---

## 9quindecies. Revue PR Rocket S09 (`/cockpit`) — 12 juillet 2026

PR reçue, **non fusionnée** (branche `rocket-update` récupérée via `FETCH_HEAD`, jamais mergée directement). Diff complet de la branche revu fichier par fichier avant toute décision.

**Résultat : 6ᵉ occurrence confirmée du patron de régression récurrent, plus une variante inédite de ce même patron qui a réintroduit `INC-S05-02` (déjà corrigé en §9terdecies) au milieu d'un changement par ailleurs légitime. Les fichiers neufs et légitimes ont été retenus, corrigés pour cette régression ponctuelle, et intégrés ; la branche n'a pas été fusionnée.**

### Régression récurrente — 6ᵉ occurrence (contenu périmé classique)

Comme pour les 5 occurrences précédentes : `ADR-MVP.md` (386 lignes écrasées par une version antérieure), `supabase/migrations/20260710006200_ccf_006c_documents_project_visibility_check.sql` (revert identique du commentaire `MVP-RA-028` → `MVP-RA-026`), `src/app/mandats/page.tsx` (doublon `business_events` d'`INC-S06-06` et `handleDecline` non symétrique, tous deux déjà corrigés), et les deux migrations fantômes `20260712020000_s06_mandates_complete.sql`/`20260712030000_s06_decline_mandate_rpc.sql` déjà remplacées sur `main`. Aucun de ces fichiers n'a été retenu.

### Variante inédite du patron — réintroduction ponctuelle d'`INC-S05-02` dans un diff par ailleurs légitime

Le diff sur `src/app/projets/[id]/page.tsx` (fichier existant, pas une copie intégrale périmée) partait pourtant du bon blob parent (`e1ae0a7`, la version corrigée d'`INC-S05-02` déployée en §9terdecies) — contrairement aux 6 occurrences précédentes où le fichier entier était périmé dès le départ. Mais le hunk touchant `handleVRSave()` a **annulé la correction `INC-S05-02`** en cours de route : suppression de la capture `valueReportId` (`.select('id').single()` sur l'insert), retour à `object_id: project.id` pour l'événement `value_report_generated`. Cause probable : régénération du bloc environnant à partir d'une représentation interne périmée du fichier plutôt qu'un patch ciblé sur le seul bloc "Risks" à modifier — la partie du diff qui *devait* changer (le calcul des risques, remplacé par `computeProjectRisks`) est correcte, mais elle a entraîné une réécriture non désirée d'un bloc voisin sans rapport avec la tâche demandée.

**Corrigé avant fusion** : le fichier intégré ne reprend de la branche Rocket que les deux changements réellement demandés — l'import de `computeProjectRisks` et le remplacement du calcul de risques inline par l'appel à la fonction partagée — appliqués manuellement sur la version `main` déjà correcte, en laissant `handleVRSave()` intact (`valueReportId`/`object_id: valueReportId` préservés). Vérifié explicitement après application : aucune autre différence avec la version corrigée précédente.

### Fichiers retenus (revus contre `Brief-Rocket-S09-Cockpit.md`)

| Fichier | Verdict |
|---|---|
| `src/lib/projectRisks.ts` (64 lignes, nouveau) | Conforme — extraction exacte de la logique déjà écrite en S05 (étapes `blocked`, `target_end_date` dépassée, participants `declined`), aucune divergence de résultat, exactement ce que demandait le brief. |
| `src/app/cockpit/page.tsx` (550 lignes, nouveau) | Conforme — sélecteur de projet filtré aux admins d'organisation coordinatrice (`org_role IN ('admin','owner')` sur `organization_members`, même filtre que `isCoordinatorAdmin`), pas de route paramétrée ; avancement calculé via un mapping `phase` → 0/25/50/75/100 % ; volume/valeur tirés du dernier `value_reports` (`created_at DESC`, `limit(1)`, `maybeSingle()`), pas d'agrégation, état vide explicite (« Aucun rapport de valeur disponible ») ; risques via `computeProjectRisks` partagé ; synthèse direction générée côté frontend (`buildSummaryText`), aucun appel IA ; **aucune écriture** — pas d'`insert`/`update`, pas de `business_events`, conforme à l'écran en lecture seule demandé. |
| `src/app/projets/[id]/page.tsx` (diff) | Conforme **après retrait de la réintroduction d'`INC-S05-02`** — voir ci-dessus. Le remplacement du calcul de risques par `computeProjectRisks` est correct et bienvenu (élimine le risque de divergence future entre S05 et S09, exactement la recommandation du brief). |
| `src/components/Sidebar.tsx` | Conforme — entrée "Cockpit" (`PresentationChartLineIcon`, `/cockpit`) ajoutée après "Événements" dans `clientNav` et `adminNav`, aucune régression, 6ᵉ diff Sidebar consécutif propre. |

**Ces 4 fichiers ont été cherry-pickés/corrigés directement sur `main`** via `git hash-object`/`git update-index` (jamais de fusion de la branche `rocket-update`). Aucune nouvelle migration requise pour cet écran, conformément à la revue backend (§9quaterdecies) — confirmé : le diff complet de la branche ne contient aucun fichier sous `supabase/migrations/` en dehors des deux fantômes déjà rejetés.

**État de S09 après cette session : backend et frontend tous deux revus, corrigés et intégrés à `main`. Reste à pousser, fermer/supprimer la PR/branche Rocket, et valider en direct dans le navigateur.**

---

## 9sexdecies. Test live S09 (`/cockpit`) — `INC-S09-01` trouvé et corrigé, 12 juillet 2026

Premier test avec `centredelasante@gmail.com` : « Aucun projet disponible » alors que ce compte n'est admin d'aucune organisation coordinatrice — comportement attendu, pas un bug. Pour valider le contenu réel du cockpit, ajout temporaire de ce compte comme `org_role = 'admin'` sur l'organisation coordinatrice du projet réel (Centre de Consolidation Ferroviaire Québec) via `INSERT` direct dans `organization_members` (nettoyage prévu après le test).

**Résultat inattendu : toujours « Aucun projet disponible » après l'ajout.** Diagnostic : `src/app/cockpit/page.tsx` filtrait avec `.in('org_role', ['admin', 'owner'])` — or `org_role` est un `ENUM` Postgres à seulement deux valeurs (`'admin'`, `'membre'`, voir `ccf_002`) ; il n'existe **aucune valeur `'owner'`** dans ce schéma. Le filtre échouait donc systématiquement en base (`22P02: invalid input value for enum org_role: "owner"`), confirmé en reproduisant la requête directement en SQL. Le code ne vérifiait pas `error` sur cette requête (`const { data: memberships } = await supabase...` sans destructurer `error`), donc l'échec était **silencieux** : `memberships` valait `null`, `adminOrgIds` devenait `[]`, et l'écran affichait un état vide propre plutôt qu'une erreur — un vrai coordinateur admin voyait donc « Aucun projet disponible » sans aucun indice qu'il s'agissait d'un bug plutôt que d'un fait.

**`INC-S09-01`.** Note : ce n'est pas une régression du patron récurrent Rocket habituel — c'est un bug neuf, dans du code neuf, non détecté à la revue de code statique (§9quindecies) car la logique semblait raisonnable par analogie avec `isCoordinatorAdmin` de S05 (qui compare `org_role === 'admin' || org_role === 'owner'` — comparaison JS inoffensive contre un type `string`, jamais vraie mais jamais une erreur non plus). Appliquée à un filtre PostgREST sur une colonne `ENUM`, la même logique devient une erreur de requête. Seul un test live avec un compte réellement admin coordinateur a permis de le détecter — confirmation supplémentaire que la revue de code seule ne suffit pas.

**Corrigé** : filtre remplacé par `.eq('org_role', 'admin')` (la seule valeur pertinente pour « administrateur coordinateur », `'membre'` n'y ayant jamais eu sa place) et l'erreur de la requête est maintenant vérifiée (`if (memErr) throw memErr;`), pour qu'une future erreur similaire remonte au lieu d'être masquée par un état vide trompeur.

**Correctif déployé et retesté en direct** avec le même compte temporairement promu admin coordinateur : sélecteur affichant le projet réel, barre d'avancement à 50 % correctement alignée sur "Exécution", carte Volume traité (57,5 t), carte Valeur de coordination (12 800 $), 0 risque détecté (cohérent avec le test S05 sur le même projet — confirme la parité de calcul via `computeProjectRisks`), détail des risques vide affiché correctement, synthèse direction générée par `buildSummaryText` (« Projet en phase exécution (50 % d'avancement) · 57,5 t traitées · valeur de coordination : 12 800 $ · aucun risque détecté. »), et notes du dernier rapport affichées. **Conforme au brief sur tous les points.**

La ligne `organization_members` ajoutée temporairement a été supprimée après validation (`DELETE` exécuté dans le SQL Editor Supabase, confirmé par l'utilisateur).

**État de S09 après cette session : complet, corrigé (`INC-S09-01`), et validé de bout en bout en production avec un vrai compte admin coordinateur. Écran terminé.**

---

## 9septdecies. Revue backend S01 (Dashboard complet) — avant construction du frontend, 12 juillet 2026

Référence : backlog technique v1.0, S01 (« Cartes KPI, alertes, projets actifs, documents incomplets, événements récents », M1 partiel / **M3 complet**) ; cahier fonctionnel v1.2, M01 (« Vue d'ensemble des organisations, opportunités, projets, alertes, documents incomplets et événements récents »).

**Clarification de portée majeure (constat, pas un bug) :** la route `/` (« Tableau de bord », `ClientDashboardContent`) existante est **entièrement dédiée au domaine MRV/lots préexistant** (`company_members`, `raw_measurements`, conteneurs, factures) — un domaine métier distinct de MetalTrace CCF construit avant cette mission. Elle ne contient aucune donnée du domaine collaboratif CCF (`ccf_projects`, `documents`, `mandates`, `business_events`). Le « M1 partiel » mentionné dans le backlog fait donc référence à ce dashboard MRV existant, pas à un début de travail CCF. **S01 « complet » signifie ajouter une nouvelle section CCF à cette page — pas remplacer ou modifier les cartes/tableaux MRV existants.**

**Résultat : aucune nouvelle table, aucune nouvelle migration, aucune nouvelle policy RLS nécessaire.** Toutes les données requises existent déjà et sont déjà protégées par des policies revues lors des sessions précédentes (`ccf_projects`/`project_participants` en §9duodecies-§9terdecies, `documents` en §9septies-§9octies, `mandates` en §9bis-§9sexies, `business_events` en §9novies-§9decies).

**Décisions de portée à trancher avant le brief Rocket :**

| Élément | Décision |
|---|---|
| Cartes KPI | 4 cartes : **Projets actifs** (`ccf_projects.phase != 'closed'`, visibles selon la RLS déjà en place — coordinateur ou participant actif) ; **Documents en attente** (`documents.status IN ('draft','submitted')`, visibles selon la RLS documents) ; **Mandats en attente** (`mandates.status = 'pending_acceptance'`, où l'organisation de l'utilisateur est `issuer_org_id` ou `receiver_org_id`) ; **Événements (7 derniers jours)** (`business_events.created_at >= now() - interval '7 days'`, visibles selon la RLS déjà en place). |
| Alertes | Liste combinée de signaux déjà définis ailleurs dans le MVP, **pas une nouvelle notion** : étapes logistiques `blocked` (même critère que le panneau Risques de S05/S09), projets avec `target_end_date` dépassée et `phase != 'closed'`, documents `rejected` récents (7 jours), mandats `active` dont `end_date` est à moins de 14 jours. Alertes multi-projets — nécessite d'interroger `logistics_steps`/`ccf_projects` sans filtrer sur un seul projet (contrairement à `computeProjectRisks`, qui reste utilisé tel quel pour S05/S09 et n'a pas besoin d'être modifié). |
| Projets actifs (liste) | `ccf_projects` où `phase != 'closed'`, triés par `target_end_date` (les plus proches d'abord), avec lien vers `/projets/:id`. Réutiliser `PHASE_CONFIG`/`PhaseBadge` du pattern déjà établi en S05/S09 si pratique (dupliquer le mapping est acceptable ici, ce n'est pas un calcul de risque partagé). |
| Documents incomplets (liste) | `documents` où `status IN ('draft','submitted')`, triés par `created_at` DESC, limité à un nombre raisonnable (ex. 10) avec lien vers `/documents`. |
| Événements récents (liste) | Derniers `business_events` (tous `object_type` confondus, pas un seul objet — donc **ne pas** réutiliser `ObjectTimeline` tel quel, qui est scopé à un objet unique ; s'inspirer de sa présentation (`EventTypeBadge`) mais interroger sans filtre `object_type`/`object_id`), limité à un nombre raisonnable (ex. 10), lien vers `/evenements` pour le journal complet. |
| Emplacement | Nouvelle section ajoutée à `ClientDashboardContent` (route `/`), **après** les sections MRV existantes (KPI Cards, RecentLotsTable/ContainerGrid) — ne pas les retirer ni les réorganiser. |

**Aucune écriture** sur cet écran — lecture seule, aucun nouvel `event_type`, aucune insertion `business_events`.

**Aucune donnée n'a été touchée sur METALVISION pour cette session — revue de code/backlog uniquement, aucune migration créée.**

**État de S01 après cette session : backend confirmé conforme sans correction nécessaire, prêt pour le brief Rocket sur le frontend.**

---

## 9octodecies. Revue PR Rocket S01 (Dashboard complet) — 12 juillet 2026

PR reçue, **non fusionnée** (branche `rocket-update` récupérée via `FETCH_HEAD`). Diff complet revu fichier par fichier.

**Résultat : 7ᵉ occurrence confirmée du patron de régression classique, PLUS réintroduction simultanée d'`INC-S05-02` ET `INC-S09-01` dans deux fichiers qui n'étaient même pas dans le périmètre du brief S01.** Les 2 fichiers neufs/légitimes ont été retenus ; les 2 fichiers déjà corrects sur `main` n'ont pas été touchés par le cherry-pick.

### 7ᵉ occurrence — patron classique

`ADR-MVP.md` (462 lignes écrasées), `supabase/migrations/20260710006200_ccf_006c_...sql` (revert identique du commentaire), `src/app/mandats/page.tsx` (doublon `business_events` d'`INC-S06-06` + `handleDecline` non symétrique), et les deux migrations fantômes `20260712020000_s06_mandates_complete.sql`/`20260712030000_s06_decline_mandate_rpc.sql`. Aucun retenu.

### Aggravation notable — réintroduction d'`INC-S05-02` et `INC-S09-01` hors périmètre

Le diff contenait aussi `src/app/cockpit/page.tsx` et `src/app/projets/[id]/page.tsx` — **deux fichiers que le brief S01 ne demandait pas de modifier** (le brief S01 est explicite : « ne modifiez pas… » ne mentionne même pas ces fichiers, la tâche portait uniquement sur `CCFDashboardSection.tsx`/`ClientDashboardContent.tsx`). Le diff sur `cockpit/page.tsx` annule exactement `INC-S09-01` (retour à `.in('org_role', ['admin', 'owner'])` et suppression de la vérification d'erreur). Le diff sur `projets/[id]/page.tsx` annule exactement `INC-S05-02` (retour à `object_id: project.id`).

Ceci confirme que l'environnement local de Rocket n'est pas seulement en retard sur un sous-ensemble de fichiers historiquement problématiques (`ADR-MVP.md`, `mandats/page.tsx`, `ccf_006c`) — il semble régénérer ou retoucher des fichiers **sans rapport avec la tâche demandée**, à partir d'un instantané périmé englobant tout le dépôt. **Aucun de ces deux fichiers n'a été touché lors du cherry-pick** : `main` conservait déjà les versions correctes (post-`INC-S09-01`, post-`INC-S05-02`), donc rien à corriger cette fois — seulement à ne pas les écraser par erreur.

### Fichiers retenus (revus contre `Brief-Rocket-S01-Dashboard.md`)

| Fichier | Verdict |
|---|---|
| `src/app/components/CCFDashboardSection.tsx` (457 lignes, nouveau) | Conforme — 4 cartes KPI, panneau d'alertes multi-projets (étapes bloquées **sans** réutiliser `computeProjectRisks`, scopé à un seul projet, exactement comme demandé), liste projets actifs triée par `target_end_date`, liste documents incomplets (limite 10), liste événements récents tous objets confondus réutilisant uniquement `EventTypeBadge` (pas `ObjectTimeline`, correctement pas réutilisé tel quel comme demandé) ; **aucune écriture**, lecture seule confirmée. |
| `src/app/components/ClientDashboardContent.tsx` (diff, 4 lignes) | Conforme — import + insertion de `<CCFDashboardSection />` après le bloc MRV existant, aucun composant MRV modifié. |

**Ces 2 fichiers ont été cherry-pickés directement sur `main`** ; `cockpit/page.tsx` et `projets/[id]/page.tsx` laissés intacts (déjà corrects).

**État de S01 après cette session : backend et frontend tous deux revus et intégrés à `main`. Reste à pousser, fermer/supprimer la PR/branche Rocket, et valider en direct dans le navigateur.**

---

## 9novodecies. Incident — INC-DATA-01 : reset marqué « staging uniquement » exécuté en production, 10 tables MRV effacées (constat lors du test live S01)

**Découvert pendant le test en direct de S01** (§9octodecies) : la nouvelle section CCF de `/` s'affichait correctement dans sa structure, mais les 4 cartes KPI restaient bloquées indéfiniment sur « … ». La console navigateur a révélé une erreur `PGRST205` sur `public.raw_measurements` (« Could not find the table... in the schema cache »). Une vérification directe (`SELECT to_regclass('public.raw_measurements')` en SQL Editor) a confirmé que la table **n'existe plus du tout** — pas un simple problème de cache PostgREST.

**Cause racine, confirmée par audit du dépôt :** `supabase/migrations/20260710999000_reset_and_reapply_ccf_full.sql` (commité le 10 juillet, avant le début visible de cette session) contient `DROP SCHEMA IF EXISTS public CASCADE;` et porte l'avertissement explicite en en-tête :

> ⚠️ STAGING UNIQUEMENT — NE PAS APPLIQUER EN PRODUCTION ⚠️

Ce fichier a pourtant été exécuté sur la base de production METALVISION. Les migrations de réapplication qui ont suivi (`20260710999100_reapply_mrv_and_aggregators.sql`, `20260711000000_reapply_invitations_five_files.sql`) n'ont recréé que : le domaine CCF complet, une partie du domaine MRV ISO 14064 (`projects`, `emission_factors`, `project_activity_logs`, `evidence_files`, `verification_sessions`), les 9 tables du domaine Agrégateurs, et 3 tables (`companies`, `company_members`, `invitations`).

**10 tables préexistantes n'ont jamais été recréées**, confirmé par comparaison exhaustive de tous les `CREATE TABLE` avant/après le 10 juillet : `raw_measurements`, `containers`, `transport_requests`, `scan_events`, `global_stats`, `object_profiles`, `app_settings`, `verifier_observations`, `clients`, `audit_learning_log`.

**Vérification de l'impact réel :** grep de chaque nom de table dans `src/` — 8 des 10 tables sont encore activement référencées par du code vivant (16 fichiers pour `raw_measurements` seul, dont les routes API `analyze-photo`, `measurements/confirm`, `stats/update`) ; `clients` et `audit_learning_log` n'ont plus aucune référence dans `src/` — mortes, non recréées.

**Sur la question des données perdues :** confirmé par l'utilisateur — la base ne contenait que des données de test/démo au moment du reset, aucune perte de donnée réelle. La correction porte donc uniquement sur la restructuration (schéma vide), pas sur une récupération de données (pas de recours au PITR Supabase nécessaire).

**Correction :** `supabase/migrations/20260712130000_incdata01_restore_mrv_tables.sql`, reconstruite fidèlement à partir de l'historique complet des 14 migrations pré-reset concernées (`20260609062345`, `20260609063000`, `20260613100000`, `20260628150000`, `20260630090000/090100/090200/090300/090400/150000`, `20260701010000/020000/030000`, `20260703200000`) : recrée les 8 tables vivantes avec leurs colonnes, index, triggers (`set_updated_at`, `set_transport_updated_at`, `compute_scan_event_hash` avec verrou consultatif, `verify_container_chain`) et policies RLS dans leur état final tel qu'il existait juste avant le reset. `clients` et `audit_learning_log` volontairement exclues (aucune référence dans le code vivant).

**Deux échecs de `supabase db push` avant application réussie, tous deux corrigés :**

1. **FK vers `public.companies`, table qui n'a en fait jamais été recréée.** La première version référençait `public.companies(id)` en supposant que `20260711000000_reapply_invitations_five_files.sql` (dont le nom laisse penser qu'elle a été appliquée) avait recréé cette table. Le push a échoué avec `relation "public.companies" does not exist`. Vérification par inventaire réel (`information_schema.tables`) plutôt que par relecture de l'historique git : `companies` n'existe pas, `organizations` existe (créée **directement** par le reset du 10 juillet, pas par renommage). Les 3 FK `company_id` corrigées vers `organizations(id)`.
2. **FK inline vers `public.containers` avant sa création dans le même fichier.** `raw_measurements.container_id` portait `REFERENCES public.containers(id)` en ligne, alors que `containers` n'est créée que ~150 lignes plus loin dans le même script — un `CREATE TABLE` ne peut pas référencer une table qui n'existe pas encore. Corrigé en déclarant `container_id UUID` sans contrainte inline ; la FK réelle est ajoutée après coup par un `ALTER TABLE ... ADD CONSTRAINT` une fois `containers` créée (section « 4bis » du fichier, pattern déjà utilisé pour `transport_request_id`).

**Leçon retenue (méthodologique) :** reconstruire un schéma à partir de l'historique des migrations git s'est révélé peu fiable ici — l'historique contient des migrations de « réapplication » qui n'ont en réalité jamais été exécutées (`companies`), et des renommages qui changent silencieusement les noms de tables réellement en place (`companies` → `organizations`). Une vérification par inventaire réel (`information_schema.tables`, `pg_get_functiondef`) **avant** d'écrire une migration corrective de ce type est plus fiable que la seule lecture du dépôt — appliqué à partir du 2ᵉ échec, devrait être la première étape par défaut pour toute reconstruction similaire à l'avenir.

**Leçon retenue (processus) :** un fichier de migration portant un avertissement explicite « ne pas appliquer en production » doit être physiquement isolé du dossier `supabase/migrations/` (ex. `supabase/migrations-staging-only/` ou suppression après usage), pas seulement commenté — un avertissement en commentaire SQL n'empêche aucune exécution accidentelle via `supabase db push`.

**Ceci est un incident distinct et sans lien avec le travail S01/S05/S09 de cette session** — la cause remonte au 10 juillet, avant toute revue visible dans cette session.

**Validé en production** : `supabase db push` terminé sans erreur, inventaire post-application confirmé (`app_settings`, `containers`, `global_stats`, `object_profiles`, `raw_measurements`, `scan_events`, `transport_requests`, `verifier_observations` — 8/8 présentes).

**État après cette session : `INC-DATA-01` résolu et validé en production.** Le blocage résiduel des 4 cartes KPI CCF sur `/` (indépendant — `CCFDashboardSection.tsx` n'interroge aucune des 8 tables ci-dessus) est traité séparément en §9vicies.

---

## 9vicies. Incident — `INC-S01-01` : `CCFDashboardSection` bloquée indéfiniment sur « … » — `useAuth()` sans `AuthProvider` monté

**Après résolution d'`INC-DATA-01`**, `raw_measurements` et le domaine MRV se sont remis à charger normalement, mais les 4 cartes KPI de la section « MetalTrace CCF » sur `/` restaient bloquées sur « … » indéfiniment, sans aucune erreur console liée à `ccf_projects`/`documents`/`mandates`/`business_events`.

**Diagnostic :** vérification de l'onglet Network (pas seulement Console — une requête réussie n'y apparaît jamais) : **aucune requête n'était émise du tout** vers `ccf_projects`, `documents`, `mandates`, `business_events` ou `logistics_steps`. Le code de `fetchAll` n'était donc jamais exécuté au-delà de sa toute première ligne.

**Cause racine :** `CCFDashboardSection.tsx` (et `ClientDashboardContent.tsx`) appellent `useAuth()` (`src/contexts/AuthContext.tsx`), qui lit un `AuthContext` React. Or **`<AuthProvider>` n'est monté nulle part dans l'arbre de l'application** (`git grep AuthProvider` ne retourne que sa propre définition, jamais un usage en JSX) — confirmé, pas supposé. `createContext<any>({})` retourne donc toujours sa valeur par défaut `{}` (un objet vide, donc truthy — le garde `if (!context) throw` de `useAuth()` ne se déclenche jamais), et `const { user } = useAuth()` vaut donc **toujours `undefined`**, pour tout composant qui l'utilise, dans toute la session. `fetchAll` commençait par `if (!user) return;` — sortie silencieuse, à chaque appel, pour toujours. Aucune exception, aucune requête, aucun indice en console.

**Pourquoi le reste du dashboard fonctionne quand même :** `ClientKPIGrid`, `RecentLotsTable`, `ContainerGrid` et `Sidebar.tsx` n'utilisent pas `useAuth()` — ils appellent `supabase.auth.getUser()` directement dans leur propre `useEffect`, contournant sans le savoir ce contexte cassé. Seuls les composants utilisant `useAuth()` (`CCFDashboardSection.tsx`, `ClientDashboardContent.tsx`) étaient affectés.

**Corrigé (patché directement, pas de nouveau brief Rocket — correctif chirurgical d'une ligne de cause) :**
- `CCFDashboardSection.tsx` : suppression de l'import et de l'appel `useAuth()` ; `fetchAll` récupère désormais l'utilisateur via `const { data: { user } } = await supabase.auth.getUser();` en interne, au même pattern que `Sidebar.tsx`. L'ensemble du corps de `fetchAll` est en plus enveloppé dans un `try/catch/finally` (`finally { setLoading(false); }`) — défaut déjà signalé comme facteur aggravant potentiel : sans ce filet, une seule requête en échec futur laisserait à nouveau la section bloquée indéfiniment sans aucun message.
- `ClientDashboardContent.tsx` : même correctif `useAuth()` → `supabase.auth.getUser()` sur son effet de récupération du nom d'organisation (affectait seulement le sous-titre « Dernière mise à jour », effet cosmétique, jamais bloquant pour le reste de la page).
- `Sidebar.tsx` : bug distinct mais découvert dans le même test live — l'effet de récupération nom/rôle interrogeait encore `company_members`/`companies` (renommées `organization_members`/`organizations` par `MVP-DA-012`) et la colonne `role` (renommée `org_role`), produisant l'erreur `PGRST205` vue dans la console (« Perhaps you meant the table 'public.organization_members' »). Corrigé vers les noms actuels ; `ROLE_LABELS` mis à jour de `owner`/`terrain` vers `admin`/`membre` (valeurs ENUM actuelles depuis `ccf_002`).

**Portée délibérément limitée :** `AuthContext.tsx`/`AuthProvider` n'a pas été touché ni monté dans `layout.tsx` — l'aurait été un changement structurel bien plus large, à effet de bord potentiellement large sur toute l'application, hors du périmètre de cet incident. Signalé ici comme dette technique à trancher délibérément : soit monter `AuthProvider` correctement à la racine si `useAuth()` doit rester une API supportée, soit retirer `AuthContext.tsx`/`useAuth` du code si le pattern `supabase.auth.getUser()` direct (déjà dominant dans le reste du code) est la convention retenue.

**Validé en direct après déploiement** : les 4 cartes KPI affichent des valeurs réelles (Projets actifs 0, Documents en attente 0, Mandats en attente 0, Événements 7j 1), les panneaux Projets actifs/Documents incomplets affichent leurs états vides corrects (« Aucun projet actif. »/« Aucun document en attente. »), et Événements récents affiche un événement réel (« Mandat révoqué », 12 juillet 2026 à 15h40).

**État après cette session : `INC-S01-01` corrigé (3 fichiers) et validé en production. Écran S01 (Dashboard complet) entièrement terminé.**

---

## 9unvicies. Revue backend S10 (Administration) — avant construction du frontend, 12 juillet 2026

Référence : backlog technique v1.0, E14-T01/T02/T03 ; cahier fonctionnel v1.2, S10 (« Paramètres, utilisateurs, rôles, catalogues, supervision »), US-012 (« Comme admin, je peux vérifier les logs d'audit et les exceptions de permission »), US-016 (« Comme admin plateforme, je peux consulter le catalogue de connecteurs prévus, sans activation »).

**Décision de portée essentielle — gate d'accès :** `/admin` (CCF) est un écran **plateforme**, distinct de `/admin-dashboard` (MRV, préexistant, S01 §9septdecies). Il doit être gardé par `is_platform_superadmin()` (flag booléen `app_metadata.is_platform_superadmin`, fonction déjà existante et déjà utilisée par les policies `organizations_superadmin_all`/`org_members_superadmin_all`/`audit_logs_superadmin_select`) — **pas** par `app_metadata.role = 'admin'`, le flag générique utilisé par `AppLayout.tsx` pour la redirection vers `/admin-dashboard` (voir S01 §9septdecies). Ce sont deux notions d'admin distinctes dans ce projet ; les confondre redirigerait soit tout le monde hors de `/admin`, soit un admin MRV sans droit plateforme dedans.

**Revue de l'existant, un domaine à la fois :**

| Besoin S10 | Table(s) | État RLS trouvé |
|---|---|---|
| Utilisateurs (cross-organisation) | `organization_members`, `organizations`, `profiles` | `organizations_superadmin_all` et `org_members_superadmin_all` existent déjà (`is_platform_superadmin()`). **`profiles` n'avait aucune policy superadmin** — seulement `profiles_select_org_members` (même organisation) et `profiles_own_select`/`_update`. Confirmé en production par `SELECT policyname, cmd, qual FROM pg_policies WHERE tablename = 'profiles'` (pas seulement supposé depuis l'historique des migrations, après la leçon d'`INC-DATA-01` §9novodecies). Une jointure `organization_members → profiles` pour une organisation dont l'admin plateforme n'est pas membre aurait échoué silencieusement — même anti-pattern qu'`INC-S02-09` (§7). |
| Logs d'audit (US-012) | `audit_logs` | Déjà correctement gardée (`audit_logs_superadmin_select`, `is_platform_superadmin()`). Aucune action requise. |
| Catalogues (référentiels) | *(aucune table dédiée)* | Conforme à `MVP-DA-015` (pas d'ENUM/catalogue partagé dynamique) — les valeurs de référence (`mandate_scope`, `document_visibility`, `logistics_step_type`, `ccf_event_type`, `org_role`, statuts `mandates`/`documents`/`ccf_projects`) sont fixées au niveau du schéma (ENUM ou `CHECK`), pas éditables via une table applicative dans ce MVP. Affichage en lecture seule uniquement, valeurs codées dans le frontend — pas de nouvelle table. |
| Connecteurs prévus (US-016, COULD) | *(aucune table)* | Aucun connecteur n'existe ni n'est actif dans ce MVP — liste statique/roadmap côté frontend, sans lien vers une table ni un état persistant, conforme à « sans activation ». |
| Seeds `event_types`/`mandate_actions`/`material_types`/`project_phases` (E14-T02, P0) | — | Déjà satisfait structurellement : ces notions sont des `CHECK`/ENUM déjà posés par les migrations CCF (`ccf_001`, `ccf_004b`, `ccf_004c`), pas des tables de seed séparées à remplir. Rien à faire de plus pour cette tâche. |

**Correction :** `supabase/migrations/20260712140000_ccf_013_s10_profiles_superadmin_select.sql` — ajoute `profiles_superadmin_select` (`FOR SELECT`, `is_platform_superadmin()`), additive aux 2 policies SELECT existantes (plusieurs policies permissives sur la même commande sont combinées par `OR` en RLS Postgres — aucune régression sur l'accès déjà en place).

**Aucune autre migration nécessaire** — tout le reste des besoins S10 est déjà couvert par des policies existantes ou ne nécessite aucune persistance (catalogues et connecteurs en lecture seule statique côté frontend).

**Point de vigilance pour le test live :** aucun compte de test actuel n'a été confirmé avec `app_metadata.is_platform_superadmin = true` — une élévation temporaire (même pattern que S09 §9sexdecies) sera nécessaire avant de pouvoir tester `/admin` en direct, à faire lors d'une session future.

**État de S10 après cette session : backend revu, 1 trou RLS trouvé et corrigé (`profiles_superadmin_select`), prêt pour le brief Rocket sur le frontend.**

---

## 9duovicies. Revue PR Rocket — S10 (Administration, `/admin`), 12 juillet 2026

Branche `rocket-update` (`FETCH_HEAD` à `061d09a2…`) diffée fichier par fichier contre `origin/main` (`246d02d…`), 11 fichiers modifiés.

**8ᵉ occurrence du patron de régression récurrente (§9octodecies et suivants) — 7 fichiers rejetés sans modification, contenu périmé confirmé identique à des occurrences antérieures :**
`ADR-MVP.md`, `supabase/migrations/20260712020000_s06_mandates_complete.sql` et `20260712030000_s06_decline_mandate_rpc.sql` (deux migrations fantômes, md5 identiques à toutes les occurrences précédentes), `supabase/migrations/20260710006200_ccf_006c_documents_project_visibility_check.sql` (revert du commentaire `MVP-RA-028`→`026`), `src/app/mandats/page.tsx`, `src/app/cockpit/page.tsx` (revert d'`INC-S09-01`, 3ᵉ occurrence), `src/app/projets/[id]/page.tsx` (revert d'`INC-S05-02`, 4ᵉ occurrence). **Nouveau et notable cette fois** : `CCFDashboardSection.tsx` et `ClientDashboardContent.tsx` — la branche réintroduit le bug `INC-S01-01` (`useAuth()` sans `AuthProvider`), corrigé le jour même, quelques heures avant l'arrivée de cette PR. Aucun de ces 7 fichiers n'a été retenu ; `main` détient déjà la version correcte de chacun.

**`Sidebar.tsx` — cas mixte, non repris tel quel :** la branche contient 1 hunk légitime (ajout de `{ label: 'Administration', href: '/admin', icon: 'ShieldCheckIcon', group: 'plateforme' }` à `adminNav`) mélangé à 2 hunks de revert périmés (`ROLE_LABELS` vers `owner`/`terrain`, requête vers `company_members`/`companies`/`role`). Le fichier n'a pas été cherry-pické depuis la branche ; l'entrée de navigation a été appliquée manuellement à la version actuelle correcte de `main`.

**`src/app/admin/page.tsx` — seul fichier réellement nouveau, revu en détail contre le brief et l'état réel du backend. 3 défauts trouvés et corrigés avant intégration :**

1. **Conflit de redirection `AppLayout`** : les 3 appels à `<AppLayout activeRoute="/admin" userRole="admin">` passaient un `userRole="admin"` en dur. Or `AppLayout.tsx` redirige tout utilisateur dont `app_metadata.role` (générique) ne correspond pas au `userRoleProp` fourni — un admin plateforme (`is_platform_superadmin`) dont le rôle générique n'est pas littéralement `'admin'` aurait été redirigé hors de `/admin` avant même que le garde d'accès de la page ne s'exécute. Toutes les autres pages CCF (`cockpit`, `mandats`, `projets/[id]`, `organizations`) appellent `<AppLayout>` sans aucune prop — corrigé à l'identique (prop retirée des 3 appels).
2. **Catalogue `mandate_actions` fictif** : la brief indiquait (à tort, erreur de portée relevée pendant cette revue — voir plus bas) que les 4 catalogues devaient être codés en dur sans requête base de données. Or `mandate_actions` est une vraie table seedée (`supabase/migrations/20260710003000_ccf_003_mandates.sql`, 10 lignes réelles : `read_capabilities`, `propose_participation`, `invite_project_org`, `accept_project_invitation`, `manage_project_participants`, `approve_documents`, `submit_logistics_proof`, `update_logistics_step`, `generate_value_report`, `request_ai_summary`), contrairement à `mandate_scope`/`logistics_step_type`/`ccf_event_type` qui sont bien des ENUM sans table associée. Rocket avait codé en dur 10 codes fictifs (`collect`, `sort`, `transport`, etc.) ne correspondant à aucune donnée réelle. Remplacé par une requête `supabase.from('mandate_actions').select('code, label, description').order('code')` (RLS déjà ouverte via `mandate_actions_authenticated_select`, confirmé — aucune migration requise), avec état de chargement/vide.
3. **Colonne « Acteur » du journal d'audit non résolue** : affichait l'UUID brut tronqué au lieu du nom, alors que le brief exigeait explicitement une jointure `profiles` sur `actor_id` (§4 du brief) — c'est précisément la raison d'être de la migration `profiles_superadmin_select` (§9unvicies). Corrigé : après récupération des logs, les `actor_id` distincts sont résolus en un second appel `profiles.select('id, full_name, email').in('id', actorIds)`, fusionnés dans chaque ligne (`full_name || email || null`), affichage du nom si disponible, repli sur l'UUID tronqué sinon.

**Erreur de portée du brief, auto-corrigée pendant la revue (pas signalée par l'utilisateur) :** `Brief-Rocket-S10-Administration.md` §3 disait « aucune nouvelle table, aucune requête base de données » pour l'ensemble des 4 catalogues — correct pour 3 d'entre eux, faux pour `mandate_actions`. Corrigé directement dans le code plutôt que par un nouveau cycle de brief, l'écart étant mineur et localisé.

**Le reste du fichier conforme au brief** : gate d'accès par sondage `audit_logs` (`is_platform_superadmin()`), 4 onglets, aucune requête sur les catalogues ENUM (statiques, corrects), liste connecteurs statique sans activation, aucun fichier `admin-dashboard/` touché.

**État de S10 après cette session : `admin/page.tsx` corrigé (3 défauts) et intégré, `Sidebar.tsx` reconcilié manuellement (1 ligne de nav ajoutée à la version correcte de `main`), 7 fichiers périmés rejetés (8ᵉ occurrence du patron). Reste à pousser, fermer la branche/PR Rocket sans fusion, puis tester en direct avec un compte temporairement élevé `is_platform_superadmin = true`.**

---

## 9tervicies. Dette technique résolue — suppression de `AuthContext.tsx`/`useAuth()`, et `INC-QR-01` (bug réel découvert au passage)

Dette technique signalée en §9vicies (`INC-S01-01`) : `<AuthProvider>` n'est monté nulle part dans l'application (`src/app/layout.tsx` confirmé, lu en entier — aucun provider d'aucune sorte n'y est monté), rendant `useAuth()` structurellement inopérant. Décision : **supprimer**, pas monter. `AuthContext.tsx` contient une implémentation par ailleurs correcte (`onAuthStateChange`, `signIn`/`signUp`/`signOut`, `getUserProfile`), mais le pattern déjà dominant et éprouvé dans tout le reste du code (`Sidebar.tsx`, `middleware.ts`, et désormais `CCFDashboardSection.tsx`/`ClientDashboardContent.tsx` depuis `INC-S01-01`) est l'appel direct à `supabase.auth.getUser()` — introduire un second mécanisme d'authentification concurrent aurait recréé le risque structurel qui a causé `INC-S01-01`, pas l'éliminé.

**Inventaire complet des références restantes** (`git grep useAuth`/`AuthProvider`, tout le dépôt) — 3 sites en plus des 2 déjà corrigés le jour même :

- `src/app/new-lot/components/StepContainer.tsx` — `const { user } = useAuth();`, variable jamais utilisée ensuite. **Mort, sans impact fonctionnel.** Import et appel retirés.
- `src/app/qr-code-scanner/components/ManualEntry.tsx` et `QRScannerViewfinder.tsx` — **`INC-QR-01` : bug réel, pas seulement dette morte.** `user?.id` toujours `undefined` (même cause qu'`INC-S01-01`) → `scan_events.user_id` était systématiquement inséré à `NULL` (trou de traçabilité sur chaque scan de conteneur), et le contrôle d'accès inter-organisation (comparaison `container.company_id` à l'organisation de l'utilisateur) était silencieusement contourné (`userCompanyId` toujours `null`).
  - **Deuxième bug empilé au même endroit, indépendant du premier** : la requête interrogeait `company_members`/`company_id`, noms pré-renommage (`MVP-DA-012` a renommé `company_members`→`organization_members` et sa colonne `company_id`→`organization_id`, voir `ccf_002` L46/L57). Même échec silencieux (`PGRST205` avalé par `.single()` sans vérification d'erreur) que celui trouvé dans `Sidebar.tsx` avant sa correction (§9vicies) — troisième occurrence du même anti-pattern de nommage périmé dans ce projet.
  - Corrigé dans les deux fichiers : suppression de `useAuth()`, ajout de `const { data: { user } } = await supabase.auth.getUser();` en tête de la fonction concernée (`handleSearch`/`lookupContainer`), requête `organization_members.select('organization_id')` au lieu de `company_members.select('company_id')`. Les colonnes `containers.company_id`/`scan_events.company_id` elles-mêmes ne sont **pas** renommées — ce sont des noms de colonnes propres à ces tables MRV, jamais touchés par `MVP-DA-012`, distincts de la table d'identité `organization_members`.

**Supprimé :** `src/contexts/AuthContext.tsx` (`git rm`).

**Portée non couverte par ce correctif** : le trou de traçabilité (`scan_events.user_id = NULL`) n'affecte que les scans effectués *avant* ce correctif — aucune tentative de rétro-remplissage, hors périmètre (données de test/démo selon la même logique que `INC-DATA-01`, à confirmer si nécessaire).

**État après cette session : dette technique du §9vicies soldée. 3 fichiers corrigés (`StepContainer.tsx`, `ManualEntry.tsx`, `QRScannerViewfinder.tsx`), `AuthContext.tsx` supprimé, `INC-QR-01` corrigé et documenté.**

---

## 9quatervicies. Test live S10 (`/admin`) en production, 13 juillet 2026

Élévation temporaire de `centredelasante@gmail.com` via `UPDATE auth.users SET raw_app_meta_data = raw_app_meta_data || '{"is_platform_superadmin": true}'::jsonb` (SQL Editor), reconnexion pour rafraîchir le JWT.

**Les 4 onglets validés en direct, conformes au brief sur tous les points :**
- **Vue d'ensemble** : gate d'accès (`is_platform_superadmin()` via sondage `audit_logs`) franchi correctement ; 6 cartes statistiques affichent des valeurs réelles (5 organisations, 3 membres, 1 projet CCF, 3 mandats, 12 événements métier, 65 entrées d'audit) ; 6 liens d'accès rapide fonctionnels.
- **Journal d'audit** : entrées réelles triées par date, colonne Acteur résolue correctement — noms d'e-mail réels (`centredelasante@gmail.com`) pour les actions utilisateur et « système » (italique) pour les triggers automatiques, confirmant que la jointure `profiles` ajoutée pendant la revue PR (§9duovicies) et la policy `profiles_superadmin_select` (§9unvicies) fonctionnent ensemble comme prévu.
- **Catalogues** : `mandate_actions` chargé en direct depuis la vraie table (10 codes réels : `accept_project_invitation`, `approve_documents`, `generate_value_report`, `invite_project_org`, `manage_project_participants`, `propose_participation`, etc.) — confirme le correctif de la revue PR (catalogue fictif remplacé par une requête réelle, §9duovicies).
- **Connecteurs** : liste statique correcte (Groupe Robert, OpenRouteService affichés « Actif »).

**Nettoyage effectué après validation** : `is_platform_superadmin` retiré du compte de test (retour à l'état normal), même discipline que pour l'élévation temporaire de S09 (§9sexdecies).

**État de S10 après cette session : complet, corrigé, intégré et validé de bout en bout en production. Écran terminé.**

---

## 10. Suite de validation automatisée

Un script de validation (`MetalTrace_MVP_Validation_Suite_v1_0.sql`) encode les décisions ci-dessus comme des assertions exécutables :

- **Partie A (structurelle)** — introspection du schéma (tables, contraintes, fonctions, triggers), lecture seule.
- **Partie B (comportementale)** — crée des données de test temporaires et exécute réellement les transitions de la machine à états (§4), le rejet de mandat vide/invalide, le blocage de l'auto-candidature — le tout dans une transaction annulée (`ROLLBACK`) en fin de script.

**État au moment de la rédaction : 63/63 assertions passées.**

Limite connue du script : la Partie B valide la logique métier encodée dans les triggers, pas l'application des policies RLS elles-mêmes (le rôle propriétaire des tables contourne RLS par défaut) — un test RLS en tant que rôle `authenticated` réel reste à faire séparément si une validation plus stricte est requise avant une mise en production.

---

## 11. Prochaines étapes recommandées

1. ~~Écran S07 (`/documents`)~~ — **résolu, terminé** (§9septies, §9octies). ~~Écran S08 (`/evenements`)~~ — **résolu, terminé** (§9novies, §9decies). ~~Écran S05 (`/projets/:id`)~~ — **résolu, terminé** (§9duodecies, §9terdecies). ~~Écran S09 (`/cockpit`)~~ — **résolu, terminé** (§9quaterdecies, §9quindecies, §9sexdecies). ~~Dashboard complet (S01)~~ — **backend et frontend revus et intégrés (§9septdecies, §9octodecies)** ; reste à pousser, fermer/supprimer la PR/branche Rocket, et valider en direct. Prochain selon la feuille de route 30-60-90 : S10 (`/admin`) complet.
2. ~~Déployer sur METALVISION les 3 fichiers correctifs S07 et tester `approve_document()`~~ — **résolu** : déployé et validé en production (voir §9septies, addendum validation).
3. Déployer `20260712110000_ccf_006f_documents_storage_bucket.sql` sur METALVISION (`supabase db push`), puis tester un dépôt de document réel dans l'écran `/documents` (upload, lecture, transition complète du cycle de vie) avant démonstration externe.
4. Tests end-to-end du parcours CCF complet (organisation → capacité → opportunité → invitation → mandat → projet → documents → logistique → rapport).
5. Projet de durcissement séparé pour la dette technique du §5 (DT-01 à DT-07), hors périmètre du MVP CCF.
6. Appliquer systématiquement `ROCKET_REVIEW_CHECKLIST.md` (introduite en §9quinquies) à chaque nouveau livrable de Rocket avant fusion — RLS, triggers de gel, doublons `business_events`, symétrie des RPC, idempotence des migrations, process git.
7. ~~Clarifier avec Rocket le point de nommage `decline_project_invitation`~~ — **résolu** : `decline_mandate()` créée et déployée directement (voir §9sexies), symétrie accept/decline désormais complète.
8. **Signaler explicitement à Rocket le patron `INC-S07-04`** (3ᵉ occurrence du même problème que `INC-S06-07/08`) comme correctif de processus à faire de son côté (resynchroniser son environnement local avant toute nouvelle branche) — au-delà de la revue systématique déjà en place, qui ne fait que limiter les dégâts après coup.
9. Nettoyage mineur reporté (§9septies) : redondance `documents_via_project_ids`/`documents_project_select` dans `ccf_010`, à traiter lors d'un futur passage de consolidation RLS — non bloquant.
10. ~~Pousser `20260712130000_incdata01_restore_mrv_tables.sql`~~ — **résolu** : appliqué en production après 2 corrections (voir §9novodecies), 8/8 tables confirmées par inventaire, domaine MRV (lots, conteneurs) confirmé fonctionnel en direct.
11. ~~Diagnostiquer le blocage résiduel des 4 cartes KPI de `CCFDashboardSection.tsx`~~ — **résolu** : `INC-S01-01`, cause réelle = `AuthProvider` jamais monté (voir §9vicies), corrigé et validé en production.
12. **Dette technique signalée en §9vicies, à trancher délibérément** : décider si `AuthContext.tsx`/`useAuth()` doit être correctement monté à la racine (`layout.tsx`) ou retiré du code, puisqu'il n'est actuellement fonctionnel nulle part dans l'application.
13. ~~Prochain écran selon la feuille de route 30-60-90 : S10 (`/admin`) complet.~~ — **résolu, terminé** : backend revu et corrigé (§9unvicies), PR Rocket revue et corrigée (§9duovicies), poussé en production, testé en direct sur les 4 onglets (§9quatervicies). Écran S10 entièrement terminé.
14. ~~Après clôture de S10 : trancher la dette technique signalée en §9vicies/§11-12 (`AuthContext.tsx`/`useAuth()` — monter `AuthProvider` correctement ou retirer le code mort)~~ — **résolu** : `AuthContext.tsx` supprimé, 3 fichiers corrigés dont `INC-QR-01` (bug réel de traçabilité découvert au passage, voir §9tervicies), poussé en production.
15. Fermer/supprimer la branche `rocket-update` sur GitHub sans fusion (contient les 7 fichiers périmés rejetés en §9duovicies).
16. Selon la feuille de route 30-60-90 : les 10 écrans (S01, S05-S10) et le tableau de bord sont désormais tous complets, corrigés et validés en production. Reste, avant démonstration externe : item 3 (bucket Storage documents à tester en réel), item 4 (test end-to-end du parcours CCF complet), item 5 (dette technique DT-01 à DT-07, hors périmètre MVP).
