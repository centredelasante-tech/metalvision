# ADR-MVP — MetalTrace MVP CCF
## Registre des décisions d'architecture

**Portée :** Centre de Consolidation Ferroviaire (CCF) — domaine collaboratif MetalTrace, coexistant sur la même base Supabase que les domaines préexistants MRV/ISO 14064 et Regroupements/Agrégateurs.

**Statut de la base au moment de la rédaction :** staging validé — 63/63 assertions automatisées passées (voir §9). Mise à jour du 11 juillet 2026 : voir §7 pour l'incident de test end-to-end S02, et §8 pour l'incident de test end-to-end S03.

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

Premier test manuel dans le navigateur de l'écran S02 (Organisations), couvrant la création d'organisation, l'invitation d'un membre et l'acceptation d'invitation. Objectif : valider en conditions réelles ce que la lecture de code seule ne peut pas garantir — RLS, triggers, RPC et policies ne se comportent pas toujours comme prévu une fois exécutés avec le rôle `authenticated` réel (voir limite connue du script de validation, §8).

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

## 9. Suite de validation automatisée

Un script de validation (`MetalTrace_MVP_Validation_Suite_v1_0.sql`) encode les décisions ci-dessus comme des assertions exécutables :

- **Partie A (structurelle)** — introspection du schéma (tables, contraintes, fonctions, triggers), lecture seule.
- **Partie B (comportementale)** — crée des données de test temporaires et exécute réellement les transitions de la machine à états (§4), le rejet de mandat vide/invalide, le blocage de l'auto-candidature — le tout dans une transaction annulée (`ROLLBACK`) en fin de script.

**État au moment de la rédaction : 63/63 assertions passées.**

Limite connue du script : la Partie B valide la logique métier encodée dans les triggers, pas l'application des policies RLS elles-mêmes (le rôle propriétaire des tables contourne RLS par défaut) — un test RLS en tant que rôle `authenticated` réel reste à faire séparément si une validation plus stricte est requise avant une mise en production.

---

## 10. Prochaines étapes recommandées

1. Écrans S01–S10 selon le mapping 30-60-90 du backlog technique.
2. Tests end-to-end du parcours CCF complet (organisation → capacité → opportunité → invitation → mandat → projet → documents → logistique → rapport).
3. Projet de durcissement séparé pour la dette technique du §5 (DT-01 à DT-07), hors périmètre du MVP CCF.
