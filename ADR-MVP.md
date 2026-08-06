# ADR-MVP — MetalTrace MVP CCF
## Registre des décisions d'architecture

**Portée :** Centre de Consolidation Ferroviaire (CCF) — domaine collaboratif MetalTrace, coexistant sur la même base Supabase que les domaines préexistants MRV/ISO 14064 et Regroupements/Agrégateurs.

**Statut de la base au moment de la rédaction :** environnement Supabase unique validé — 82/82 assertions MVP réussies (voir §9septricies/§10). **Tranche 0 carbone — état courant complet (mis à jour au 1er août 2026, voir §12-§26) :** migration 01 (fondations transverses) 22/22 (§12) ; migrations 02+03 (`aggregator_memberships` + correctif d'autorisation) 56/56 (§13) ; migrations 06+06a (`platform_operators`/mandats de commercialisation + correctif de privilèges, désignation réelle de METALTRACE) 62/62 (§14) ; migration 04 (`ccf_mrv_project_links`) 44/44 (§15) ; migration 05 (`verification_outcomes`, un bug réel corrigé) 128/128 (§15) ; migration 07 (`credit_issuances`, réconciliation unique autorisée avec 04) 110/110 (§15) ; migration 08 (`credit_lots`, cycle commercial — reconstruction transactionnelle depuis un objet legacy, deux blocages réels résolus dont la suppression de 5 tables legacy vides via `pre08_drop_legacy_empty_credit_sale_tables`, exécutée directement par l'agent via le connecteur MCP Supabase) 87/87 (§16) ; migration 09 (`credit_sales`, modèle commercial et financier des ventes de crédits carbone) **appliquée en production (GATE 1), contrôles post-migration read-only conformes (GATE 2), harnais transactionnel validé 196/196 assertions via `psql --file` en transaction unique BEGIN/ROLLBACK (GATE 3, 23 juillet 2026 — voir §18)**. **État courant au 1er août 2026 : la Tranche 0 carbone est techniquement close.** Toutes les migrations — 01, 02, 03, 04, 05, 06, 06a, 07, 08 et 09 — sont appliquées en production. La validation transactionnelle de 09 (196/196, GATE 3) et sa validation de concurrence réelle (72/72, environnement jetable R9, connexions physiquement distinctes) sont toutes deux closes (voir §18-§20) ; **aucun R10 n'est requis**. Le travail est passé aux workflows produit/interface : **Lot 1** — vérification, émissions et inventaire carbone (`/admin/carbon-inventory`, `/admin-verification-sessions`) — est validé fonctionnellement en production sur six scénarios (§21). **Lot 2** — gouvernance des règles de distribution et des overrides membres (`/admin/regroupements/[aggregatorId]/distribution`) — est livré et validé en production sur huit scénarios couvrant l'intégralité de la matrice d'actions (double/triple approbation, rejet et retrait sur les deux workflows), plus une migration additive `10_carbon_organizations_governance_visibility.sql` corrigeant un défaut RLS réel trouvé pendant le test (§22). **Lot 3** — cockpit de ventes (`/admin/carbon-sales`) — est livré et validé en production sur l'intégralité de sa matrice d'actions (cycle principal, annulation brouillon, libération de lot), plus une migration additive corrective `11_carbon_sales_compute_allocations_safeupdate_fix.sql` (rejet réel de `confirm_credit_sale` par pg-safeupdate côté PostgREST, trouvé pendant le test) (§23). Les trois lots verticaux du MVP carbone commercial sont désormais tous livrés et testés en production, sans réserve de couverture connue restante. **Lot 4** — stabilisation opérationnelle et régression transverse — est en cours : deux bugs réels consécutifs ont été trouvés et corrigés pendant la régression du domaine vérification/MRV — `12_carbon_start_verification_session.sql` (RPC `start_verification_session`, transition `planned`→`in_progress` par le vérificateur assigné, absente de toute policy RLS écriture — §24) puis `13_carbon_verification_evidence.sql` (bucket Storage `verification-evidence` + RPC `record_verification_report_evidence`, comblant l'absence totale de chemin produisant une preuve `evidence_files` valide — aucune vérification ne pouvait jamais être complétée — §25). La chaîne de vérification MRV complète (`planned`→`in_progress`→`completed`, résultat actif avec preuve intègre) est désormais validée en production de bout en bout. `supabase/carbon_migrations_proposed/` demeure hors de `supabase/migrations/` et de l'historique automatisé `schema_migrations`. Ce placement ne signifie pas que ces migrations sont non appliquées : 01 à 07 ont été appliquées manuellement via l'éditeur SQL Supabase, 08 via le connecteur MCP Supabase et 09 au GATE 1 selon la procédure documentée au §18. Le harnais transactionnel de 09 a ensuite été exécuté séparément via `psql --file` au GATE 3 (voir §12-§16, §18). Mise à jour du 12 juillet 2026 (section MVP CCF ci-dessous) : voir §7 pour l'incident de test end-to-end S02, §8 pour l'incident de test end-to-end S03, §9 pour le test end-to-end S04 (aucun bug trouvé), §9bis à §9sexies pour l'écran S06 (Mandats) — backend et frontend, **complet et validé** — §9septies/§9octies pour S07 (Documents), **complet, corrigé et validé de bout en bout en production** — §9novies/§9decies pour S08 (Événements), **frontend accepté partiellement, 4ᵉ occurrence du patron `INC-S07-04`** — §9undecies pour la fermeture des trous de test S06/S08 — §9duodecies pour la revue backend de S05 (Projet CCF), 1 bug corrigé (`INC-S05-01`) — §9terdecies pour S05 (Projet CCF) frontend, **complet, corrigé (`INC-S05-02`) et validé de bout en bout en production, 5ᵉ occurrence du patron de régression récurrente** — §9quaterdecies pour la revue backend de S09 (Cockpit exécutif), conforme, aucune correction nécessaire — §9quindecies-§9sexdecies pour S09 frontend, **complet, corrigé (`INC-S09-01`) et validé de bout en bout en production, 6ᵉ occurrence du patron de régression récurrente** — §9septdecies pour la revue backend de S01 (Dashboard complet), conforme — §9octodecies pour S01 frontend, **complet et intégré, 7ᵉ occurrence du patron de régression récurrente (avec réintroduction simultanée d'`INC-S05-02` et `INC-S09-01` hors périmètre du brief, non retenue)** — §9novodecies pour `INC-DATA-01` : **10 tables MRV effacées par un reset marqué « staging uniquement » exécuté en production le 10 juillet (incident antérieur à cette session, sans lien avec S01/S05/S09), résolu et validé en production (8/8 tables restaurées)** — §9vicies pour `INC-S01-01` : **`CCFDashboardSection` bloquée indéfiniment sur « … » à cause d'un `AuthProvider` jamais monté dans l'application (`useAuth()` toujours `undefined`), corrigée dans 3 fichiers et validée en production. Écran S01 (Dashboard complet) entièrement terminé.** — §9unvicies pour la revue backend de S10 (Administration), 1 trou RLS trouvé et corrigé (`profiles` sans policy superadmin) — §9duovicies pour la revue de la PR Rocket S10 : 3 défauts corrigés dans `admin/page.tsx` (conflit `AppLayout`, catalogue `mandate_actions` fictif, jointure `profiles` manquante sur l'audit), `Sidebar.tsx` reconcilié manuellement, 8ᵉ occurrence du patron de régression récurrente (7 fichiers périmés rejetés), **poussé en production** — §9tervicies pour la clôture de la dette technique `AuthContext.tsx`/`useAuth()` (§9vicies) : contexte supprimé, 3 fichiers corrigés, dont `INC-QR-01` (bug réel découvert au passage : `scan_events.user_id` toujours `NULL` + noms de table périmés `company_members`/`company_id` dans le scanner QR) — §9quatervicies pour le **test live S10, validé de bout en bout en production sur les 4 onglets. Écran S10 (Administration) entièrement terminé.** — §9quinvicies pour un correctif mineur `/documents` (validation UUID + messages d'erreur Postgres non masqués), issu du test live §9octies — §9sexvicies pour un **trou de portée trouvé pendant le test end-to-end : E08-T01/T02 (création de projet + invitation d'organisation, MUST/P0 du backlog) jamais livré**, backend confirmé prêt sans migration, brief Rocket rédigé (`Brief-Rocket-E08-Creation-Projet.md`) — §9septvicies pour la revue de la PR Rocket correspondante : **9ᵉ occurrence du patron de régression récurrente (17 fichiers périmés rejetés), `opportunities/page.tsx` accepté tel quel (aucun défaut), `InviteOrganizationModal` sur `projets/[id]/page.tsx` corrigé avant intégration (filtre des organisations déjà participantes manquant, même classe de bug qu'observé en direct en §9sexvicies), les deux fichiers écrits sur `main`** — §9octovicies pour `INC-E08-01`, trouvé au test live juste après le push : **insertion directe d'un mandat en `pending_acceptance` bloquée par une policy RLS plus stricte que ce que le brief avait vérifié (`mandates_insert_issuer_admin`, migration S06, exige `status='draft'` à l'insertion), corrigée en scindant l'insertion en deux étapes (`draft` puis `UPDATE` vers `pending_acceptance`, même schéma que `/mandats`), aucune migration nécessaire, validé en direct en production** — §9novovicies pour un **nouveau trou de portée trouvé pendant le test end-to-end : aucune façon de créer une étape logistique** (`logistics_steps`), backend confirmé prêt sans migration (`logistics_steps_coordinator_insert` déjà en place), brief Rocket à rédiger — §9tricies pour la revue de la PR Rocket correspondante : **10ᵉ occurrence du patron de régression récurrente (15 fichiers périmés rejetés), `AddLogisticsStepModal` accepté, reverts d'`INC-S05-02`/`INC-E08-01`/filtre `InviteOrganizationModal` rejetés, restylage non demandé des onglets Documents/Rapport de valeur rejeté, et `INC-S05-03` (crash React de l'onglet Risques, `RiskItem` rendu comme chaîne) trouvé au passage et corrigé minimalement, validé en direct en production** — §9unatricies pour la **clôture du test end-to-end du parcours CCF complet : organisation → capacité → opportunité → invitation → mandat → projet → documents → logistique → rapport, chaque étape validée de bout en bout en production** — et §9duotricies pour le **changement de priorité vers stabilisation/démo-pilote/verrouillage du processus Rocket, avec un premier outil concret livré (`scripts/rocket_pr_audit.sh`, détection automatique de stale reverts par comparaison d'historique git, testé contre la vraie PR E08bis).**

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

**Mise à jour du 13 juillet 2026 — projet de durcissement démarré, à la demande explicite de l'utilisateur.** Chaque point vérifié en direct contre la production avant d'écrire quoi que ce soit (même discipline qu'`INC-DATA-01`, §9novodecies — l'historique des migrations ne suffit pas) :

| Code | Résultat de la vérification live | Action |
|---|---|---|
| DT-01 | **Caduc.** La colonne `member_distribution_overrides.created_by` n'existe plus du tout (disparue lors de la reconstruction du schéma, incident §6) — le constat original ne s'applique plus, rien à corriger. | Aucune |
| DT-02 | Confirmé réel : `actor_id` (uuid, nullable) sans FK. 2 lignes, 0 orpheline vs `profiles(id)`. | FK ajoutée, `ON DELETE SET NULL` |
| DT-03 | Confirmé réel : `actor_id` (uuid, nullable) sans FK. 2 lignes, 0 orpheline vs `profiles(id)`. | FK ajoutée, `ON DELETE SET NULL` |
| DT-04 | Confirmé réel : `user_id` (uuid, **NOT NULL**) sans FK. Table vide (0 ligne). | FK ajoutée, `ON DELETE CASCADE` (`SET NULL` impossible sur une colonne `NOT NULL`) |
| DT-05 | Confirmé réel, mais **constat à nuancer** : le passage ENUM→`TEXT` est une décision délibérée et documentée (`20260628150000_internal_transport.sql`), pas un oubli — deux vocabulaires de statut coexistent selon le provider (interne : `scheduled/in_transit/arrived/delivered/cancelled` ; externe Groupe Robert, encore présent dans le code derrière `app_settings.external_transport_enabled = false` : `pending/assigned/en_route/picked_up/delivered/cancelled`). Table vide en production. | `CHECK` ajouté sur l'union des deux vocabulaires (+ `pending`, valeur `DEFAULT` de la colonne) — cohérent avec `MVP-DA-015` (TEXT + CHECK, pas d'ENUM partagé), sans fermer la porte à l'un ou l'autre provider |
| DT-06 | Confirmé réel : les 4 fonctions ont `proconfig = null`. **Piège de signature évité** : `is_aggregator_admin()` prend en fait un paramètre (`p_aggregator_id UUID`), pas zéro argument — `ALTER FUNCTION` aurait échoué avec la mauvaise signature. | `SET search_path = public` sur les 4 fonctions |
| DT-07 | Confirmé déjà résolu : la version en base est bien la version sécurisée (`app_metadata`, pas `raw_user_meta_data`). | Reçoit le même correctif `search_path` que DT-06 (listée dans les deux points) |

**Migration** : `20260713010000_dt_hardening_02_03_04_05_06.sql`. Additive uniquement — aucune donnée supprimée, aucune policy RLS existante modifiée.

**État après cette session : DT-01 (caduc, sans action), DT-02, DT-03, DT-04, DT-05, DT-06 et DT-07 tous traités ou confirmés déjà résolus. Migration `20260713010000_dt_hardening_02_03_04_05_06.sql` appliquée en production, vérifiée (4 contraintes + 4 fonctions avec `search_path=public` confirmées par requête directe). Projet de durcissement post-MVP clos.**

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

## 9quinvicies. Correctif mineur — `/documents`, validation UUID et messages d'erreur masqués (bug relevé au test live §9octies)

Bug non bloquant relevé lors du test live du 12 juillet (§9octies), corrigé aujourd'hui dans `src/app/documents/page.tsx` :

1. **Champ « ID de l'objet » sans validation de format** : texte libre, aucune vérification qu'il s'agit bien d'un UUID avant l'insertion. Ajout d'une regex `UUID_RE` : validation côté JS avant soumission (message clair si le format est invalide) et attribut HTML `pattern` sur le champ lui-même (validation navigateur immédiate). **Portée délibérément limitée** : pas de sélecteur en direct par type d'objet (aurait exigé une requête différente par table pour 6 types d'objets — organisation, capacité, opportunité, projet, mandat, rapport de valeur — hors périmètre d'un correctif mineur ; à envisager comme amélioration séparée si le besoin se confirme).
2. **Messages d'erreur Postgres/PostgREST masqués** : les 6 blocs `catch` du fichier utilisaient `e instanceof Error ? e.message : '<message générique>'` — or une erreur renvoyée par `supabase.from(...).insert()`/`.update()`/`.rpc()` (`PostgrestError`) est un objet simple, pas une instance d'`Error` ; `instanceof Error` est donc systématiquement faux pour ces erreurs, et le message réel (contrainte violée, RLS refusée, etc.) était toujours remplacé par un texte générique inutile pour le diagnostic. Corrigé par une fonction partagée `getErrorMessage(e, fallback)` qui reconnaît aussi tout objet portant un champ `message` de type chaîne (couvre `Error` et `PostgrestError`), appliquée aux 6 emplacements (dépôt, chargement, soumission, décision, archivage, téléchargement).

Aucune migration, aucun changement de comportement RLS — correctif frontend pur, aucun nouveau test live requis (couvert par le test déjà fait en §9octies pour le reste du cycle de vie).

**État après cette session : bug mineur du §9octies corrigé et documenté.**

---

## 9sexvicies. Trou de portée trouvé pendant le test end-to-end — E08-T01/T02 : aucune façon de créer un projet ou d'inviter une organisation

**Contexte :** premier test end-to-end du parcours CCF complet (organisation → capacité → opportunité → invitation → mandat → projet → documents → logistique → rapport), avec deux comptes distincts : `centredelasante@gmail.com` (admin, « Test Organisation », coordonnateur) et `claudefairplay@hotmail.com` (membre, « Test no 2 », candidat).

**Déroulement validé jusqu'à l'opportunité :** organisation ✓ (existantes), capacité ✓ (Fer, qualifiée, déjà présente pour Test no 2), opportunité ✓ (créée en direct dans `/opportunities`, qualifiée), association capacité-opportunité ✓ (bouton « Associer », visible uniquement pour un coordonnateur sur n'importe quelle capacité éligible — confirmé dans `capacites/page.tsx`, `canAssociate = isCoordinator && (declared|qualified)` — comportement correct, ce n'est pas le candidat qui postule lui-même).

**Blocage trouvé :** aucune façon de convertir cette opportunité qualifiée en projet CCF. Recherche exhaustive dans tout le dépôt (`src/` et toutes les migrations) : **aucun** `INSERT INTO ccf_projects`, **aucune** fonction RPC de type `convert_opportunity_to_project`, **aucun** bouton/formulaire sur `/opportunities` ou `/projets`. Le seul projet existant en production (« Projet CCF-2026-Q3 ») a été inséré directement en SQL comme donnée de démonstration (`supabase/migrations/20260710999000_reset_and_reapply_ccf_full.sql`, bloc de seed), jamais créé via l'application.

**Vérifié contre le backlog technique v1.0 (agent dédié, lecture complète du `.docx`)** : ce n'est pas un aléa de portée, c'est un ticket documenté et non livré — **E08-T01 / US-007, épopée E08 priorité MUST, ticket priorité P0** : *« Créer projet à partir d'une opportunité qualifiée »*, critère d'acceptation *« Projet lié à opportunity_id »*. Le même vide s'étend à l'invitation d'une organisation à un projet (E08-T02, *« Créer project_participants avec project_role et mandate_id »*) : `/projets/:id` sait déjà **accepter/refuser** une invitation existante (`accept_project_invitation`/`decline_project_invitation`, RPCs S06 fonctionnelles) mais rien ne peut créer cette invitation — ni sur `/projets/:id`, ni sur `/mandats` (qui crée des mandats génériques mais ne les relie jamais à `project_participants`).

**Bonne nouvelle, confirmée en lisant le RLS existant :** le backend est déjà entièrement prêt, sans exception — `ccf_projects_coordinator_admin_insert`, `project_participants_coordinator_insert` et `mandates_issuer_admin_insert` (déjà utilisée par `/mandats`) couvrent exactement ce dont ce ticket a besoin. **Aucune migration nécessaire** — uniquement un trou frontend.

**Décision, à la demande explicite de l'utilisateur :** construire la fonctionnalité manquante plutôt que la contourner. Brief rédigé : `Brief-Rocket-E08-Creation-Projet.md` — Partie A (bouton « Convertir en projet » sur `/opportunities`, transitions manuelles côté client sans RPC, même convention que `documents/page.tsx`/`mandats/page.tsx` pour les transitions d'état) ; Partie B (bouton « Inviter une organisation » sur `/projets/:id`, création directe d'un mandat `pending_acceptance` + `project_participants` liée, réutilisant le multi-select d'actions déjà construit dans `/mandats` plutôt que de le reconstruire).

**État après cette session : trou de portée documenté, backend confirmé prêt sans migration, brief Rocket rédigé. Frontend à livrer.**

---

## 9septvicies. Revue de la PR Rocket E08-T01/T02 — 9ᵉ occurrence du patron de régression, un défaut réel trouvé et corrigé

**Contexte :** Rocket a livré la fonctionnalité demandée en §9sexvicies (`Brief-Rocket-E08-Creation-Projet.md`) : `ConvertToProjectModal` sur `/opportunities` et `InviteOrganizationModal` sur `/projets/:id`. Revue selon la discipline habituelle — `git fetch origin rocket-update`, diff fichier par fichier contre `origin/main`, aucune fusion directe de la branche.

**Diffstat : 19 fichiers changés.** 17 sont la **9ᵉ occurrence** du patron déjà documenté (Rocket rebranche depuis une copie locale périmée, réintroduisant des bugs déjà corrigés en même temps que le nouveau travail) — confirmés périmés par diff/md5 et **rejetés sans y toucher**, `main` détenant déjà la version correcte :

- `ADR-MVP.md` — reverti de ~687 lignes vers une version bien plus ancienne.
- `Brief-Rocket-E08-Creation-Projet.md` — supprimé (le brief lui-même).
- `src/app/admin/page.tsx` — revert des 3 correctifs de §9duovicies.
- `src/app/cockpit/page.tsx` — revert d'`INC-S09-01`.
- `src/app/components/CCFDashboardSection.tsx` / `ClientDashboardContent.tsx` — revert d'`INC-S01-01`.
- `src/app/documents/page.tsx` — revert du correctif §9quinvicies (validation UUID + `getErrorMessage`).
- `src/app/mandats/page.tsx` — revert d'`INC-S06-06` (doublon d'insertion `business_events`).
- `src/app/new-lot/components/StepContainer.tsx` — réintroduction du `useAuth()` mort.
- `src/app/qr-code-scanner/components/ManualEntry.tsx` / `QRScannerViewfinder.tsx` — revert d'`INC-QR-01`.
- `src/components/Sidebar.tsx` — revert de `ROLE_LABELS`/`company_members`.
- `src/contexts/AuthContext.tsx` — résurrection intégrale du fichier supprimé en §9tervicies.
- `supabase/migrations/..._ccf_006c_documents_project_visibility_check.sql` — revert du commentaire `MVP-RA-026`→`MVP-RA-028` (9ᵉ occurrence de ce revert précis).
- `supabase/migrations/20260712020000_s06_mandates_complete.sql` et `20260712030000_s06_decline_mandate_rpc.sql` — les deux migrations « fantômes », confirmées octet-identiques (md5) aux 8 occurrences précédentes.
- `supabase/migrations/20260713010000_dt_hardening_02_03_04_05_06.sql` — supprimée (la migration de durcissement DT-01–DT-07 du §5, déjà appliquée en production).

**2 fichiers sont du travail neuf légitime**, examinés en détail :

- **`src/app/opportunities/page.tsx`** (233 lignes, 100 % ajout, 0 suppression) : `ConvertToProjectModal`, visible seulement si `isCoordinator && opportunity.status === 'qualified' && !loadingCaps`, bouton désactivé tant qu'aucune `opportunity_capabilities.status = 'active'` n'existe (`hasActiveCapability`), avec message d'avertissement explicite. Séquence de soumission conforme au brief (INSERT `ccf_projects` → INSERT `project_participants` coordonnateur/actif → UPDATE `opportunities` converted → INSERT `business_events` project_created → redirection), chaque étape surface `(err as {message?:string}).message` plutôt que `e instanceof Error` seul (leçon de §9quinvicies appliquée correctement). **Verdict : aucun défaut, écrit tel quel sur `main`.**

- **`src/app/projets/[id]/page.tsx`** (364 lignes, mixte) : contient à la fois `InviteOrganizationModal` (neuf, légitime) **et** un revert périmé d'`INC-S05-02` (perte de la capture `valueReportId`, `object_id` redevenant `project.id` au lieu de l'id du rapport de valeur dans l'événement `value_report_generated`) plus un reformatage cosmétique sans effet du calcul `risks`. Le revert d'`INC-S05-02` est **rejeté**, le reformatage ignoré.

  **Défaut réel trouvé dans le code neuf :** le filtre `invitableOrgs` de `InviteOrganizationModal` (`allOrganizations.filter(o => o.id !== project.coordinator_org_id)`) n'excluait pas les organisations **déjà présentes** dans `project_participants` pour ce projet — une réinvitation aurait déclenché une erreur Postgres brute `duplicate key value violates unique constraint project_participants_..._key`, exactement la même classe d'échec observée en direct pendant le test end-to-end (§9sexvicies, association capacité-opportunité en double sur `opportunity_capabilities`). **Corrigé avant intégration** : nouvelle prop `existingParticipantOrgIds: string[]` (passée depuis la page parente via `participants.map(p => p.organization_id)`), filtre devenu `o.id !== project.coordinator_org_id && !existingParticipantOrgIds.includes(o.id)`, message d'état vide amélioré.

  Le fichier final — `InviteOrganizationModal` corrigé inséré sur la version `main` actuelle, `INC-S05-02` et le format d'origine du `useMemo` préservés intacts — a été relu en entier après assemblage pour confirmer l'absence de régression avant d'être écrit.

**État après cette session : les deux fichiers corrigés écrits sur `main`, commités et poussés (`804a12c`). Reste : reprise du test end-to-end (§54) à partir du bouton « Convertir en projet ».** *(Correction : la RLS s'est révélée insuffisante pour un des deux flux — voir §9octovicies, trouvé au test live immédiatement après.)*

---

## 9octovicies. `INC-E08-01` — INSERT direct de mandat en `pending_acceptance` bloqué par RLS, trouvé au test live

**Contexte :** premier test live du parcours E08 juste après le push de §9septvicies. « Convertir en projet » a fonctionné parfaitement (projet créé, `Test Organisation` ajoutée comme participant coordonnateur actif, redirection correcte vers `/projets/:id`). En cliquant « Inviter » dans `InviteOrganizationModal` (organisation « Test no 2 » sélectionnée), erreur Postgres brute affichée par l'UI : **`new row violates row-level security policy for table "mandates"`**.

**Cause racine :** le brief §9sexvicies affirmait la policy RLS d'insertion des mandats déjà suffisante en citant `mandates_issuer_admin_insert` (`WITH CHECK (is_organization_owner(issuer_org_id))`, créée dans `ccf_003`). Cette policy **a été supprimée et remplacée** par la migration S06 `20260712054247_ccf_012_mandates_s06.sql` (ligne 153 : `DROP POLICY IF EXISTS "mandates_issuer_admin_insert"`), qui crée à la place `mandates_insert_issuer_admin` avec une contrainte plus stricte : `WITH CHECK (is_org_admin(issuer_org_id) AND status = 'draft')`. Un `INSERT` direct avec `status = 'pending_acceptance'` — exactement ce que demandait le brief (« geste unique et direct ») et ce qu'implémentait Rocket — viole cette contrainte. Le brief a vérifié la RLS via une migration antérieure (`ccf_003`/`reset_and_reapply`) sans confirmer qu'une migration plus récente (`ccf_012`) l'avait remplacée entre-temps — erreur de vérification, pas un défaut de code.

**Bonne nouvelle :** la transition `draft → pending_acceptance` est déjà couverte par une policy dédiée, `mandates_update_issuance_by_issuer` (`USING (is_org_admin(issuer_org_id) AND status = 'draft')`, `WITH CHECK (status = 'pending_acceptance')`) — c'est exactement le schéma en deux temps déjà utilisé par `handleSend` dans `/mandats/page.tsx` (`UPDATE mandates SET status = 'pending_acceptance'` sur un mandat déjà en `draft`).

**Corrigé (frontend uniquement, aucune migration) :** `InviteOrganizationModal.handleSubmit` dans `src/app/projets/[id]/page.tsx` — étape 1 scindée en 1a (`INSERT mandates` avec `status: 'draft'`) et 1b (`UPDATE mandates SET status = 'pending_acceptance'` immédiatement après, sur le même `mandateId`), avant l'étape 2 (`INSERT project_participants`) inchangée. Toujours un seul clic « Inviter » côté utilisateur — deux appels DB en coulisses, comme `/mandats`.

**État après cette session : correctif poussé (`23bf202`) et validé en direct en production** — invitation de « Test no 2 » créée sans erreur RLS (statut `Invité`), puis acceptée avec succès par le compte `claudefairplay@hotmail.com` via `accept_project_invitation` (statut passé à `Actif`). **E08-T01 et E08-T02 entièrement fonctionnels de bout en bout en production.**

---

## 9novovicies. Trou de portée trouvé pendant le test end-to-end — aucune façon de créer une étape logistique

**Contexte :** poursuite du test end-to-end sur le projet « consolider Acton Vale » — dépôt de document validé sans problème (onglet Documents, document « Soumission » créé en `draft`, v1.0). Passage à l'onglet Logistique : **0 étape affichée, aucun moyen de la créer**.

**Recherche dans le code :** `src/app/projets/[id]/page.tsx` ne fait que `SELECT` et `UPDATE` sur `logistics_steps` (`LogisticsStepCard` permet de modifier le statut et la date réelle d'une étape existante) — aucun `INSERT`, aucun bouton « Ajouter une étape », nulle part dans le dépôt.

**Backend déjà prêt, vérifié en lisant la migration `20260710999000_reset_and_reapply_ccf_full.sql` (lignes 1148-1157) :** la policy `logistics_steps_coordinator_insert` existe déjà — `WITH CHECK (EXISTS (SELECT 1 FROM ccf_projects p WHERE p.id = project_id AND is_organization_owner(p.coordinator_org_id)))` — un admin de l'organisation coordonnatrice du projet peut insérer n'importe quelle étape pour ce projet. **Aucune migration nécessaire.** Note additionnelle : `ccf_event_type` ne contient que `logistics_step_updated`, pas de variante `_created` — la création est déjà tracée automatiquement par le trigger `audit_logistics_steps` (`audit_log_trigger_fn`, INSERT/UPDATE/DELETE) dans `audit_logs`, indépendamment de `business_events` ; aucun événement métier manuel n'est donc nécessaire à la création (cohérent avec le fait que `documents` n'émet pas non plus d'événement à la création, seulement au dépôt/approbation).

**Décision, à la demande explicite de l'utilisateur :** construire la fonctionnalité manquante plutôt que la contourner en SQL. Brief à rédiger pour Rocket : bouton « Ajouter une étape » sur l'onglet Logistique de `/projets/:id`, visible uniquement pour le coordonnateur admin (`isCoordinatorAdmin`), formulaire avec `step_type` (les 6 valeurs de l'ENUM `logistics_step_type` : ramassage, chargement, expedition, transit, livraison, preuve_finale), `responsible_org_id` (liste des organisations participantes du projet), `planned_date` optionnelle — `status` par défaut `'planned'`, pas d'événement métier manuel à l'insertion.

**État après cette session : trou de portée documenté, backend confirmé prêt sans migration. Brief Rocket à rédiger et frontend à livrer.**

---

## 9tricies. Revue de la PR Rocket E08bis (étape logistique) — 10ᵉ occurrence du patron de régression, scope creep non demandé, `INC-S05-03` trouvé et corrigé au passage

**Contexte :** Rocket a livré la fonctionnalité du brief `Brief-Rocket-E08bis-Etape-Logistique.md` : `AddLogisticsStepModal` sur `/projets/:id`. Revue habituelle — `git fetch origin rocket-update`, diff fichier par fichier contre `origin/main`.

**Diffstat : 16 fichiers changés.** 15 sont la **10ᵉ occurrence** du patron déjà documenté (même liste qu'en §9septvicies, moins `Brief-Rocket-E08-Creation-Projet.md` et la migration DT-hardening — non représentées cette fois — mais avec les mêmes reverts sur `admin/page.tsx`, `cockpit/page.tsx`, `CCFDashboardSection.tsx`/`ClientDashboardContent.tsx`, `documents/page.tsx`, `mandats/page.tsx`, `StepContainer.tsx`, `ManualEntry.tsx`/`QRScannerViewfinder.tsx`, `Sidebar.tsx`, `AuthContext.tsx` résurrecté, `ADR-MVP.md` reverti de ~750 lignes, commentaire `ccf_006c` et les deux migrations « fantômes » — confirmées octet-identiques (md5) aux 9 occurrences précédentes) — **rejetés sans y toucher.**

**1 fichier légitime, mais mélangé à plus que ce qui était demandé :** `src/app/projets/[id]/page.tsx` (529 lignes changées, 182 suppressions / 349 ajouts).

- **Accepté tel quel :** `AddLogisticsStepModal` — formulaire conforme au brief (`step_type` via `LOGISTICS_STEP_TYPE_LABELS`, `responsible_org_id` restreint aux participants actifs, `planned_date` optionnelle, `INSERT` unique avec `status='planned'`, aucun `business_events` à la création, erreurs surfacées via `(err as {message?:string}).message`). Bouton « Ajouter une étape » gated `isCoordinatorAdmin`, état et invocation du modal corrects.

- **Rejeté — reverts de correctifs de cette session même :** (1) le filtre `existingParticipantOrgIds` d'`InviteOrganizationModal` (§9septvicies) et (2) le correctif RLS `draft`→`pending_acceptance` (`INC-E08-01`, §9octovicies), tous deux redevenus les versions cassées ; (3) `INC-S05-02` (`object_id: project.id` au lieu de `valueReportId`) à nouveau reverti ; (4) reformatage cosmétique du `useMemo` des risques.

- **Rejeté — réécriture non demandée, hors périmètre du brief :** restylage complet des onglets Documents et Rapport de valeur, y compris un changement de comportement (bouton « Déposer un document » passant de `isCoordinatorAdmin` à `myAdminOrgIds.length > 0` — élargissement de permission non revu ni demandé) et une refonte du formulaire de rapport de valeur (perte du pattern « modifier le dernier rapport en un clic », remplacé par un bouton « Modifier » par carte). Décision utilisateur : **rejeté en bloc**, comportement actuel conservé sans modification.

**`INC-S05-03` — bug de production réel, découvert incidemment via le scope creep de Rocket, indépendant de cette PR :** l'onglet Risques de `/projets/:id` faisait `<p>{risk}</p>` où `risk` est en réalité un objet `RiskItem` (`{label, severity, icon}`, type partagé avec `/cockpit` via `src/lib/projectRisks.ts`), pas une chaîne — React lève *"Objects are not valid as a React child"* dès que `risks.length > 0` (étape bloquée, projet en retard, ou invitation refusée). Confirmé en comparant avec le rendu correct déjà utilisé dans `/cockpit/page.tsx` (`risk.label`, `risk.icon`, `risk.severity`). Jamais détecté car jamais testé en direct avec une condition de risque active. **Corrigé minimalement** (rendu correct des 3 champs, badges de sévérité simples) — sans adopter le reste du restylage proposé par Rocket pour cet onglet, à la demande explicite de l'utilisateur.

**État après cette session : correctif poussé (`c475e59`) et validé en direct en production.** Étape logistique « Ramassage » créée (Test Organisation, prévue le 22 juillet), passée à « Bloqué » pour déclencher volontairement un risque — l'onglet Risques affiche correctement « 1 étape logistique bloquée » sans planter, confirmant `INC-S05-03` résolu. Étape remise à « Planifié » ensuite. Invitation d'une 3ᵉ organisation (« Centre de Consolidation Ferroviaire Québec ») testée avec succès dans la foulée, revalidant au passage les correctifs de §9septvicies (filtre anti-doublon) et §9octovicies (RLS mandats). **E08bis entièrement fonctionnel et validé de bout en bout en production.**

---

## 9unatricies. Clôture du test end-to-end du parcours CCF complet

**Contexte :** dernière étape du parcours démarré en §9sexvicies — le rapport de valeur du projet « consolider Acton Vale ». Formulaire rempli (volume 2 t, valeur de coordination 450 $, note « Par vos camions »), enregistré avec succès, statut Brouillon, affiché correctement dans l'onglet Rapport de valeur.

**Bilan complet du parcours end-to-end, organisation → capacité → opportunité → invitation → mandat → projet → documents → logistique → rapport, chaque étape validée en direct en production avec deux comptes réels (`centredelasante@gmail.com` / Test Organisation, coordonnateur ; `claudefairplay@hotmail.com` / Test no 2, candidat) :**

- Organisation et capacité déjà existantes, vérifiées (§55).
- Opportunité créée, qualifiée, capacité candidate associée (§9sexvicies).
- **Trou de portée MUST/P0 découvert** (création de projet + invitation d'organisation, jamais livré) → construit (§9septvicies), un défaut RLS trouvé et corrigé au test live (`INC-E08-01`, §9octovicies).
- Projet créé, participant coordonnateur actif, organisation invitée et acceptée (2 fois, avec 2 organisations différentes).
- Document déposé (§9novovicies, en amont du test logistique).
- **Deuxième trou de portée découvert** (création d'étape logistique, jamais livré) → construit (§9novovicies → §9tricies), un bug de production indépendant trouvé et corrigé au passage (`INC-S05-03`, crash de l'onglet Risques).
- Rapport de valeur créé.

**10 occurrences confirmées du patron de régression récurrente de Rocket sur l'ensemble du projet** (branche depuis une copie locale périmée, reverts systématiques de correctifs déjà appliqués) — standing mitigation maintenue : diff systématique contre `origin/main`, aucune fusion directe de branche, reconstruction manuelle du contenu légitime.

**État après cette session : parcours CCF complet validé de bout en bout en production, aucune étape bloquante restante. Écran S05 (`/projets/:id`) et les fonctionnalités E08/E08bis considérés terminés.**

---

## 9duotricies. Changement de priorité — stabilisation, préparation démo/pilote, verrouillage du processus Rocket

**Contexte :** décision explicite de l'utilisateur, le parcours CCF complet étant validé (§9unatricies) : la priorité n'est plus de construire de nouvelles fonctionnalités, mais de (1) stabiliser l'existant, (2) préparer une démonstration/pilote, (3) verrouiller le processus de revue des livraisons Rocket pour limiter le coût de la 11ᵉ occurrence (et suivantes) du patron de régression récurrente, confirmé 10 fois au 13 juillet 2026.

**Premier chantier entamé — outillage de revue :** `scripts/rocket_pr_audit.sh`, un script d'audit automatique qui fetch `origin/main` et une branche Rocket donnée, puis pour chaque fichier modifié vérifie si son contenu est octet-identique à une version antérieure de ce même fichier n'importe où dans l'historique de `main` (pas seulement la version actuelle). Un match signale un **stale revert suspecté**, avec le commit et la date d'origine — automatisant le travail de comparaison manuelle (`git show <ref>:<path> | md5sum`) fait à la main depuis 10 PR.

**Testé contre la vraie branche `rocket-update` (PR E08bis, toujours ouverte sur GitHub, PR #108) :** sur 16 fichiers modifiés, le script a correctement signalé 9 stale reverts automatiquement (`ADR-MVP.md`, `cockpit/page.tsx`, `CCFDashboardSection.tsx`/`ClientDashboardContent.tsx`, `documents/page.tsx`, `StepContainer.tsx`, `ManualEntry.tsx`, `QRScannerViewfinder.tsx`, commentaire `ccf_006c`) et a correctement détecté que la branche ne partait *pas* du commit actuel de main (`merge-base` divergent).

**Limite identifiée et documentée, pas corrigée :** 7 fichiers n'ont pas été détectés automatiquement (`admin/page.tsx`, `mandats/page.tsx`, `projets/[id]/page.tsx`, `Sidebar.tsx`, `AuthContext.tsx`, les deux migrations « fantômes »), car leur contenu corrigé a été écrit directement dans sa version finale sans jamais committer la version cassée d'origine sur `main` — il n'existe donc aucun blob historique à retrouver. Le script ne remplace pas la revue humaine du contenu marqué « nouveau/modifié » ; il élimine seulement une partie du travail répétitif.

**`ROCKET_REVIEW_CHECKLIST.md` mis à jour** : 10ᵉ occurrence consignée comme acquise et permanente (§6), nouvelle section §7 documentant l'outil et sa limite.

**État après cette session : outil d'audit écrit, testé, documenté. Reste : committer/pousser, puis démarrer la stabilisation (recherche d'autres bugs latents du type `INC-S05-03`) et la préparation démo/pilote.**

---

## 9tertricies. Audit factuel du domaine Regroupements/Agrégateurs — état réel confirmé, décision de réutilisation

**Contexte :** décision explicite de l'utilisateur de mener en parallèle de la stabilisation CCF un audit du volet carbone (« Regroupement pour accumuler des crédits carbone et procéder à la vérification officielle »), sans rien développer avant d'avoir un état des lieux complet. Audit mené par lecture exhaustive des migrations, du code applicatif et confirmation live des données — jamais par archéologie seule (leçon `INC-DATA-01`).

**Trois sous-domaines distincts identifiés, pas un seul module « carbone » :**

1. **MRV / ISO 14064-2** (`projects`, `emission_factors`, `project_activity_logs`, `evidence_files`, `verification_sessions`) — c'est la brique « vérification officielle ». Déjà construite avec écrans fonctionnels (`admin-carbon-projects`, `admin-mrv-project`, `admin-emission-factors`, `admin-verification-sessions`, `carbon-impact`, `verifier-mrv`) et API (`/api/ghg/calculate`, `/api/projects/[id]/log-activity`, `/api/projects/[id]/iso-report`). RLS à 3 rôles (`is_project_admin`, `is_verifier`, `is_project_client`).
2. **Regroupements / Agrégateurs** (`aggregators`, `aggregator_admins`, `operational_units`, `credit_lots`, `credit_sales`, `credit_sale_lots`, `distribution_rules`, `member_distribution_overrides`, `credit_sale_allocations`) — socle de données et de gouvernance soigné (historisation des admins, `primary_admin` unique, transfert de rôle via RPC), mais **zéro écran** confirmé par grep exhaustif sur tout `src/app/**/page.tsx`. Le seul code applicatif existant, `/api/aggregator/calculate-sale` + `distribution-calculator.ts`, interroge des colonnes qui n'existent nulle part dans le schéma réel (`platform_fee_pct`/`reserve_pct`/`default_weight` sur `distribution_rules` ; `company_id`/`override_type`/`override_value`/`effective_until` sur `member_distribution_overrides` ; `company_id`/`contributed_tco2e`/`gross_amount`/etc. sur `credit_sale_allocations`) — cette route échouerait immédiatement si invoquée.
3. **Rattachement organisationnel** — `organizations.aggregator_id`, structurellement présent mais jamais écrit par aucune UI.

**Origine du domaine Agrégateurs, déjà notée en §9novodecies :** un résidu d'une application antérieure développée sur le même projet Supabase avant le pivot vers MetalTrace/CCF — pas construit spécifiquement pour la vision carbone actuelle, mais réutilisable.

**Deux trous structurels confirmés (pas de supposition) pour le parcours cible « Projet CCF → calcul MRV → preuves → vérification complétée → quantité admissible validée → regroupement → lot de crédits → vente → frais de plateforme → allocation » :**

- `ccf_projects` et `projects` (MRV) sont deux tables totalement étanches — aucune FK, aucune colonne de correspondance (cohérent avec `MVP-DA-013`, mais ça veut dire que rien ne relie aujourd'hui un projet CCF à un projet carbone).
- Rien ne relie une vérification complétée (`verification_sessions.status = 'completed'`) à une quantité admissible : la table n'a aucun champ numérique, et `credit_lots.quantity_tco2e` est saisi indépendamment — aucune contrainte n'empêche un lot d'exister sur un projet jamais vérifié.

**Fait accessoire relevé :** le seed de démonstration MRV (2 projets, logs, preuves, 1 session de vérification) est inséré directement dans une migration de production (`20260710999100_reapply_mrv_and_aggregators.sql`, section 1), ce qui contredit `MVP-DA-016` (seed isolé hors `migrations/`). Non corrigé pour l'instant, consigné pour visibilité.

**État réel des données, confirmé en direct le 13 juillet 2026 (requête `count(*)` sur les 9 tables + `organizations.aggregator_id`) :** `aggregators` = 0, `operational_units` = 0, `credit_lots` = 0, `credit_sales` = 0, `credit_sale_lots` = 0, `distribution_rules` = 0, `member_distribution_overrides` = 0, `credit_sale_allocations` = 0, `verification_sessions` = 1 (la session de démo du seed ci-dessus), `organizations.aggregator_id IS NOT NULL` = 0. **Le domaine Agrégateurs est entièrement vide en production — aucune donnée réelle à préserver ou migrer.**

**Décision de l'utilisateur, fondée sur le schéma et les parcours réels — réutiliser en l'adaptant, ni tout jeter ni tout garder tel quel :**

- **Conservé tel quel** : `aggregators`, `aggregator_admins` (gouvernance déjà mûre), `operational_units`, `credit_sales`, `credit_sale_lots`, `distribution_rules`, `member_distribution_overrides` — structure saine, cohérente avec `organizations`/`is_organization_member` (pas l'ancien `companies`).
- **À adapter** : `credit_lots` (lier explicitement à une vérification complétée), `credit_sale_allocations` (ajouter une contrainte `UNIQUE(credit_sale_id, organization_id)` pour supporter un upsert propre), `verification_sessions` (ajouter un champ de quantité admissible validée).
- **À abandonner intégralement** : `/api/aggregator/calculate-sale/route.ts` et `src/lib/distribution-calculator.ts` — modèle de données sans rapport avec le schéma réel, à réécrire contre `distribution_rules.rule_type`/`parameters` (JSONB), pas contre des colonnes fixes inexistantes.
- **À créer** : tous les écrans (0 aujourd'hui pour le domaine Agrégateurs), la colonne/mécanisme de correspondance `ccf_projects` ↔ `projects` (MRV), et la contrainte reliant vérification complétée → génération de lot.

**Catalogue d'événements métier carbone — décision de conception, pas encore de migration :** `business_events.event_type` est typé directement en ENUM `ccf_event_type` (pas du texte libre) et `business_events.object_type` est verrouillé par un `CHECK` fermé sur 8 valeurs ne couvrant aucun objet carbone. Intégrer des événements carbone (`carbon_project_created`, `verification_completed`, `credit_lot_created`, etc.) dans ce catalogue exigerait une extension d'ENUM (irréversible) et du `CHECK`. Recommandation retenue : **catalogue distinct** (`carbon_event_type` + table `carbon_business_events` séparée, même structure que `business_events`) — cohérent avec la séparation déjà actée entre `ccf_projects` et `projects` (`MVP-DA-013`), et avec l'intention d'origine documentée dans `ccf_001_enums.sql` (« nommé `ccf_event_type` pour éviter tout conflit avec le domaine MRV/scan existant »).

**État après cette session : audit complet, aucun développement entamé. Le MVP carbone minimal reste à construire après le gel de la version démo CCF, par tranches (Regroupements d'abord, puis rattachement, calcul/consolidation, vérification, lots, vente, répartition), conformément à la décision de l'utilisateur.**

---

## 9quatertricies. Stabilisation CCF — généralisation du correctif `getErrorMessage`, confirmation de l'absence de doublons `business_events`

**Contexte :** l'utilisateur a réaffirmé que la stabilisation du parcours CCF et la préparation d'une démo fiable restent la priorité immédiate (non mise en pause par le chantier carbone, mené en parallèle). Reprise du travail annoncé en §9duotricies : recherche systématique de bugs latents du type `INC-S05-03`, avant qu'ils ne soient découverts en direct devant un public.

**Régression systémique trouvée, confirmée sur 4 écrans en plus de `documents/page.tsx` :** le correctif `getErrorMessage()` (`e instanceof Error` est faux pour une `PostgrestError`, masquant le message réel de Postgres/RLS derrière un texte générique — bug d'origine trouvé et corrigé uniquement dans `documents/page.tsx`, §9quinvicies) n'avait jamais été généralisé. Grep exhaustif sur tout `src/app/**/page.tsx` : le pattern non corrigé `e instanceof Error ? e.message : '<fallback>'` était toujours présent dans `mandats/page.tsx` (6 occurrences), `projets/[id]/page.tsx` (7 occurrences), `projets/page.tsx` (1 occurrence) et `cockpit/page.tsx` (2 occurrences) — soit **16 emplacements** où une erreur RLS ou de contrainte réelle aurait affiché un message générique inutile au diagnostic, exactement le risque qu'on veut éliminer avant une démo.

**Corrigé :** fonction extraite dans `src/lib/getErrorMessage.ts` (partagée, plus de duplication locale), importée et appliquée aux 16 emplacements des 4 écrans plus haut, et `documents/page.tsx` mis à jour pour importer la version partagée au lieu de sa définition locale d'origine. Aucun changement de comportement RLS/backend, correctif frontend pur. `admin-transport/page.tsx` présente le même pattern non corrigé (3 emplacements) mais appartient au domaine Transport, hors périmètre CCF — laissé tel quel, consigné pour visibilité si la stabilisation s'étend plus tard à ce domaine.

**Vérifications complémentaires, aucun autre défaut trouvé :**
- Doublons `business_events`/RPC (règle §3 du `ROCKET_REVIEW_CHECKLIST.md`) : `mandats/page.tsx` (le fichier d'origine d'`INC-S06-06`) confirme toujours l'absence de doublon, commentaire explicite en place ; `documents/page.tsx` (`approve_document`) et `projets/[id]/page.tsx` (mandats/étapes logistiques/phase/rapport de valeur) suivent tous correctement la règle « RPC insère déjà l'événement → jamais d'insertion manuelle », vérifié ligne par ligne.
- Rendu d'objet comme enfant React (classe `INC-S05-03`) : pas d'autre occurrence trouvée dans les écrans examinés.

**État après cette session : correctif de stabilisation appliqué et vérifié statiquement sur 4 écrans (16 emplacements) + 1 fichier partagé créé. Reste à tester en direct (déclencher une erreur RLS volontaire sur un des 4 écrans pour confirmer que le vrai message Postgres s'affiche désormais) puis committer.**

**Addendum (13 juillet 2026) :** correctif committé et poussé (`0ee181f`, 9 fichiers, 274+/29-). Validation live du correctif volontairement différée à la demande de l'utilisateur — sera confirmée naturellement à la prochaine erreur rencontrée pendant la préparation de la démo, sans test artificiel forcé.

---

## 9quinquatricies. Reset complet des données de démonstration — repartir à zéro plutôt que trier

**Contexte :** en préparant la démo (§9duotricies, priorité « stabiliser + préparer la démo »), inventaire des données réelles a révélé un mélange de deux origines : (1) le seed pilote `Projet CCF-2026-Q3` (3 organisations réalistes — coordonnateur/manufacturier/recycleur — dupliqué à la fois dans `supabase/seeds/demo_ccf.sql`, isolé conformément à `MVP-DA-016`, et directement dans la migration `20260710999000_reset_and_reapply_ccf_full.sql`, qui a réellement été appliquée en production — violation de `MVP-DA-016` non corrigée, consignée pour visibilité) ; (2) les artefacts de test QA accumulés pendant le test end-to-end de cette session (« Test Organisation », « Test no 2 », projet « consolider Acton Vale », mandats/documents/étapes/rapport associés). L'utilisateur a demandé s'il valait mieux repartir à zéro plutôt que trier ce mélange.

**Décision, après clarification de la portée exacte pour éviter de répéter `INC-DATA-01` :** vider les tables métier CCF (`TRUNCATE`, schéma intact, aucune migration) puis réappliquer uniquement le seed pilote propre, et rattacher les deux vrais comptes de test (`centredelasante@gmail.com`, `claudefairplay@hotmail.com`) aux organisations du seed pour pouvoir piloter la démo avec ces comptes réels plutôt qu'en simple consultation.

**Risque identifié et écarté avant exécution :** `organizations` n'est pas une table exclusivement CCF — elle est aussi référencée par le domaine Transport (`raw_measurements`, `containers`, `scan_events`, confirmé fonctionnel en production, §9novodecies), par `invitations`, et par le domaine Agrégateurs. Un `TRUNCATE ... CASCADE` sur `organizations` aurait risqué de détruire de vraies données de suivi de conteneurs si elles existaient. **Vérifié en direct avant toute exécution** : les 5 organisations réelles (3 du seed + 2 de test QA) ont toutes 0 ligne dans `raw_measurements`/`containers`/`scan_events` — CASCADE confirmé sans risque. `profiles` (identité liée à `auth.users`) n'a aucune FK entrante depuis les tables truiquées — jamais affectée par le CASCADE, vérifié explicitement dans les migrations avant d'agir.

**Exécuté et vérifié en trois étapes, chacune confirmée en direct dans le SQL Editor Supabase avant de passer à la suivante :**
1. `TRUNCATE TABLE ai_assistance_logs, audit_logs, business_events, value_reports, logistics_steps, documents, project_participants, mandates, opportunity_capabilities, opportunities, ccf_projects, capabilities, organization_members, organizations CASCADE` — succès.
2. Réapplication de `supabase/seeds/demo_ccf.sql` — succès confirmé par comptage (3 organisations, 1 projet, 2 mandats, 3 étapes, 1 rapport, exactement les chiffres attendus).
3. Rattachement des 2 comptes réels — `centredelasante@gmail.com` admin de « Centre de Consolidation Ferroviaire Québec » (coordonnateur), `claudefairplay@hotmail.com` membre d'« Acier Laurentien Inc. » (manufacturier participant) — confirmé par requête de vérification.

**Note non résolue :** `documents.storage_path` référençait des fichiers dans le bucket Storage — le `TRUNCATE` a vidé les lignes mais pas les fichiers eux-mêmes, qui restent orphelins dans Storage (inoffensifs mais inutilisés). Nettoyage séparé possible si souhaité, non fait ici.

**État après cette session : reset complet exécuté et vérifié au niveau base de données, puis validé en direct dans le navigateur** — connexion avec `centredelasante@gmail.com`, `/projets` affiche correctement « 1 projet accessible », le projet du seed (coordonné par Centre de Consolidation Ferroviaire Québec, statut Exécution). **Préparation des données de démo terminée.** Reste : rédiger le script de démonstration pas à pas.

**Addendum** : script de démonstration rédigé (`Script-Demo-CCF.md`) — trame de 12-15 minutes, comptes réels identifiés par organisation/rôle, piège signalé (onglet Documents actuellement vide suite au reset, à traiter avant ou pendant la démo).

---

## 9sextricies. Constat d'architecture — le catalogue `mandate_actions` n'est exploité que pour une seule action sur dix

**Contexte :** poursuite de l'audit de stabilisation (suite à §9quatertricies), cette fois sur le volet RLS/permissions plutôt que le frontend. Vérification systématique, pour chacune des 10 actions du catalogue fermé `mandate_actions` (`read_capabilities`, `propose_participation`, `invite_project_org`, `accept_project_invitation`, `manage_project_participants`, `approve_documents`, `submit_logistics_proof`, `update_logistics_step`, `generate_value_report`, `request_ai_summary`), qu'au moins une policy RLS ou une RPC consulte réellement `mandates.permissions->actions` pour cette action — règle §1 point 6 du `ROCKET_REVIEW_CHECKLIST.md`, déjà à l'origine d'`INC-S07-01` (`approve_documents`, trouvé absent puis corrigé, voir §7bis/tâches 11-12).

**Constat, confirmé par grep exhaustif sur toutes les migrations :** en dehors d'`approve_documents` (corrigé), **aucune des 9 autres actions n'apparaît nulle part ailleurs que dans le `INSERT` du catalogue lui-même.** Vérifié précisément sur les 3 policies d'insertion les plus susceptibles de s'y référer : `project_participants_coordinator_insert`, `logistics_steps_coordinator_insert` et `value_reports_coordinator_insert` sont **toutes les trois** conditionnées uniquement par `is_organization_owner(p.coordinator_org_id)` — aucune ne lit `mandates.permissions` pour vérifier si le mandat de l'organisation invitante/participante autorise spécifiquement `invite_project_org`, `manage_project_participants`, `submit_logistics_proof`, `update_logistics_step` ou `generate_value_report`. Cohérent avec le message d'erreur déjà observé sur la mise à jour d'étape logistique (« vous devez être admin ou avoir un profil terrain dans l'organisation responsable ») — la vérification réelle passe par le rôle/profil au sein de l'organisation responsable, jamais par le contenu du mandat.

**Ce que ça implique concrètement :** le trigger `validate_mandate_permissions()` (RT-07) garantit que le tableau `permissions.actions[]` d'un mandat ne contient que des codes valides et non vide — une garantie d'intégrité référentielle, pas d'application fonctionnelle. Choisir les 5 actions du mandat manufacturier dans le seed de démo (`read_capabilities`, `invite_project_org`, `manage_project_participants`, `submit_logistics_proof`, `update_logistics_step`) n'a aujourd'hui d'autre effet que d'être stocké et affiché — ces cases à cocher ne débloquent techniquement rien de plus que ce que le rôle d'organisation (coordonnateur vs participant) permet déjà par ailleurs.

**Direction du risque, à préciser :** ce n'est pas une brèche de sécurité — rien n'est accordé en trop par cette lacune, c'est l'inverse : des permissions affichées comme accordées par un mandat n'ont en réalité aucun effet, et l'accès réel reste plus restrictif (coordonnateur seul) que ce que le mandat laisse croire à l'utilisateur. Risque fonctionnel/UX (attentes non tenues), pas risque de sécurité.

**Décision, en attente de l'utilisateur :** ne rien modifier dans l'immédiat — implémenter une vérification RLS pour 8 actions supplémentaires est un changement structurant, pas un correctif ponctuel, et le faire juste avant une démo comporte un risque de casser un parcours déjà validé. Consigné ici comme constat d'architecture à trancher délibérément : soit accepter que le catalogue reste déclaratif/documentaire pour le MVP (mettre à jour la documentation utilisateur en conséquence), soit planifier l'implémentation RLS complète comme un chantier distinct, hors période de démo.

**Décision de l'utilisateur : laisser tel quel pour l'instant.** Aucune modification de policy avant la démo — le catalogue reste déclaratif/documentaire pour le MVP. Consigné comme dette technique documentée, à planifier comme chantier séparé après la démo si souhaité, pas comme urgence.

**État après cette session : constat documenté, décision prise, aucune modification de policy.**

---

## 9septricies. Gel formel de la version démo CCF

**Contexte :** l'utilisateur a demandé de considérer la stabilisation et la préparation de la démonstration comme terminées, et d'officialiser un gel de cette version avant d'ouvrir le chantier carbone (Tranche 0). Sept points à confirmer et documenter : commit exact, migrations appliquées, résultat des tests automatisés, checklist opérationnelle, données de démonstration et procédure de réinitialisation, script narratif dans l'ordre exact, limitations/risques connus.

**1. Commit exact de la version démo :** `366caeccb8665bb81ee30be05b01cbc4dd2c23bd` (court : `366caec`), confirmé via `git log -1 --oneline` et `git rev-parse HEAD` — `HEAD -> main, origin/main, origin/HEAD` tous alignés. Message : « Versionner les briefs Rocket S05/S07/S08 et le test S07 restes locaux + ignorer supabase/.temp ».

**2. Migrations Supabase appliquées :** confirmé via `supabase migration list` — Local = Remote pour la totalité des migrations, la plus récente étant `20260713010000` (durcissement DT). Aucun écart entre l'état local et l'état distant au moment du gel.

**3. Résultat des tests automatisés :** la suite référencée en §10 (`MetalTrace_MVP_Validation_Suite_v1_0.sql`, « 63/63 assertions passées ») s'est révélée **absente du dépôt** au moment de vérifier son existence (`Glob` exhaustif, aucune trace) — manifestement exécutée ad hoc dans une session antérieure sans jamais avoir été committée. Reconstruite intégralement pour ce gel : `supabase/tests/validation/MetalTrace_MVP_Validation_Suite_v2_0.sql` (committé, volontairement hors `supabase/migrations/`, ce n'est pas une migration de schéma).

Trois itérations ont été nécessaires avant un résultat exploitable, chacune due à un comportement du SQL Editor Supabase et non à une erreur de logique métier :
- Première version : `array_agg(enumlabel)` (type `name[]`) comparé à `ARRAY['admin','membre']` (`text[]`) — incompatibilité de type, corrigée par un cast explicite `::text`.
- Deuxième version : `CREATE TEMP TABLE` suivie d'un `SELECT` final échouant avec `relation "validation_results" does not exist` — le SQL Editor Supabase peut exécuter un script multi-instructions sur des connexions différentes, et une table temporaire (portée session) ne survit pas à ce découpage.
- Troisième tentative (bloc `DO $$ ... $$` unique avec `RAISE NOTICE`) : exécution réussie mais résultats invisibles — le Dashboard Supabase utilisé ne présente qu'un onglet « Results »/« Chart », aucun panneau Messages/Logs pour les notices Postgres.
- **Version finale retenue :** table de résultats **permanente** (`public._ccf_validation_results`, utilitaire de test, pas une table métier, vidée par `TRUNCATE` à chaque exécution), Partie A en `INSERT ... SELECT` directs, Partie B en bloc `DO` avec données de test à UUID fixes et reconnaissables, nettoyées par des `DELETE` explicites (avant et après, par sécurité) plutôt que par un `ROLLBACK` global peu fiable dans ce contexte multi-connexions. Les résultats s'affichent comme de vrais `SELECT` dans l'onglet Results.

**Résultat obtenu, exécuté le 13 juillet 2026 (soirée, Québec) contre l'unique environnement Supabase du projet (pas de staging séparé — confirmé par l'utilisateur), à l'état du commit `366caec` :**

```
total_assertions | total_reussies | total_echouees
82                | 82              | 0
```

Détail : 72 assertions structurelles (Partie A — 16 tables existantes, 16 RLS activées, 12 fonctions utilitaires présentes, catalogue `mandate_actions` = 10, 14 valeurs critiques de `ccf_event_type`, 6 valeurs de `logistics_step_type`, `org_role` = {admin, membre}, contrainte `mandates_different_orgs`, contrainte `UNIQUE` sur `project_participants`, 4 triggers critiques) + 10 assertions comportementales (Partie B — rejet auto-mandat, mandat valide accepté, rejet action inconnue, rejet actions vide, unicité participant/projet, rejet phase invalide, rejet type d'étape invalide, acceptation type valide, rejet statut de capacité invalide, rejet profil opérationnel invalide). **Aucun échec.**

**Limite à ne jamais perdre de vue en lisant ce résultat :** le script s'exécute avec le rôle `postgres` (propriétaire des tables), qui **contourne la RLS par défaut dans PostgreSQL**. Il valide la logique métier encodée dans les triggers et contraintes CHECK/UNIQUE (laquelle s'applique quel que soit le rôle), **pas** l'application réelle des policies RLS (quel rôle/utilisateur peut faire quoi). Cette validation-là a été faite séparément, manuellement, avec de vrais comptes authentifiés dans l'application (tests end-to-end documentés au fil des sections précédentes) — le script ne la remplace pas et ne prétend pas le faire.

**4. Checklist opérationnelle complète de la démo :** `Script-Demo-CCF.md` — parcours pas à pas (~12-15 min), tableau des comptes de connexion, checklist pré-démo (onglet Documents vide après le reset — 2 options : pré-déposer un document ou le faire en direct), section « Pièges à éviter ».

**5. Données de démonstration et procédure de réinitialisation :** documenté intégralement en §9quinquatricies — reset complet exécuté (`TRUNCATE` des tables métier CCF, réapplication de `supabase/seeds/demo_ccf.sql`, rattachement de `centredelasante@gmail.com` et `claudefairplay@hotmail.com` aux organisations du seed), validé en direct dans le navigateur. Procédure reproductible si un nouveau reset est nécessaire avant une démonstration future.

**6. Script narratif, dans l'ordre exact des écrans et actions :** deux documents distincts, chacun avec un usage différent — `Script-Demo-CCF.md` (trame de clic-par-clic pour piloter soi-même la démo en direct) et `Script-Narration-Demo-CCF-Ministere-Partenaire.md` (texte de narration/voix off pour une vidéo générée par IA, même ordre d'écrans, ton factuel et chiffré, volet carbone explicitement présenté comme feuille de route et non comme fonctionnalité existante).

**7. Limitations et risques connus, à ne pas déclencher pendant la démo :**
- Le catalogue `mandate_actions` reste déclaratif — 9 des 10 actions ne sont vérifiées par aucune policy RLS (§9sextricies, décision : laisser tel quel). Ne pas présenter les mandats comme un contrôle d'accès granulaire fonctionnel : c'est un cadre de gouvernance/traçabilité, pas encore une autorisation technique fine.
- L'onglet Documents est vide immédiatement après le reset de données (§9quinquatricies) — prévoir un pré-dépôt ou un dépôt en direct.
- Le test RLS multi-comptes n'a jamais été étendu au-delà de `/mandats` (S06) — éviter de tester en direct, devant public, des scénarios RLS non déjà validés (changement de compte à un autre rôle non répété récemment).
- La branche GitHub `rocket-update` (7 fichiers périmés rejetés en §9duovicies) reste ouverte sur GitHub sans avoir été fermée (item 15, §11) — sans impact sur la démo elle-même, mais à fermer pour l'hygiène du dépôt.
- Fichiers Storage orphelins : le reset a vidé les lignes `documents` mais pas les fichiers déjà déposés dans le bucket Storage (§9quinquatricies) — inoffensif, mais à savoir si un nettoyage Storage est fait séparément plus tard.

**Contrainte explicite de l'utilisateur, à respecter tant qu'aucune décision contraire n'est prise : Rocket demeure verrouillé — aucune migration, correction ou nouvelle fonctionnalité ne doit être intégrée à cette version sans décision explicite.**

**État après cette session : gel formalisé sur les 7 points demandés. Le chantier carbone (Tranche 0 — conception/architecture uniquement) peut maintenant s'ouvrir, conformément à la séquence demandée par l'utilisateur.**

---

## 10. Suite de validation automatisée

**Mise à jour du 13-14 juillet 2026 (voir §9septricies pour le détail complet) :** le fichier `MetalTrace_MVP_Validation_Suite_v1_0.sql` mentionné ci-dessous n'a jamais existé dans le dépôt — reconstruit sous un nouveau nom et chemin, `supabase/tests/validation/MetalTrace_MVP_Validation_Suite_v2_0.sql`, exécuté avec un résultat de **82/82 assertions passées, 0 échec**, à l'état du commit `366caec`.

Un script de validation (`supabase/tests/validation/MetalTrace_MVP_Validation_Suite_v2_0.sql`) encode les décisions ci-dessus comme des assertions exécutables :

- **Partie A (structurelle)** — introspection du schéma (tables, RLS, contraintes, fonctions, triggers, catalogues ENUM), lecture seule.
- **Partie B (comportementale)** — crée des données de test (UUID fixes et reconnaissables) et exécute réellement les transitions de la machine à états (§4), le rejet de mandat vide/invalide, le blocage de l'auto-candidature, l'unicité participant/projet — nettoyées par des `DELETE` explicites en fin de script (voir §9septricies pour les raisons de ce choix plutôt qu'un `ROLLBACK` global).

**État actuel : 82/82 assertions passées, 0 échec** (exécution du 13-14 juillet 2026, détail en §9septricies).

Limite connue du script : la Partie B valide la logique métier encodée dans les triggers, pas l'application des policies RLS elles-mêmes (le rôle propriétaire des tables contourne RLS par défaut) — un test RLS en tant que rôle `authenticated` réel reste à faire séparément si une validation plus stricte est requise avant une mise en production. Cette validation manuelle a déjà été faite au fil des sections précédentes (tests end-to-end avec de vrais comptes).

---

## 11. Prochaines étapes recommandées

1. ~~Écran S07 (`/documents`)~~ — **résolu, terminé** (§9septies, §9octies). ~~Écran S08 (`/evenements`)~~ — **résolu, terminé** (§9novies, §9decies). ~~Écran S05 (`/projets/:id`)~~ — **résolu, terminé** (§9duodecies, §9terdecies). ~~Écran S09 (`/cockpit`)~~ — **résolu, terminé** (§9quaterdecies, §9quindecies, §9sexdecies). ~~Dashboard complet (S01)~~ — **backend et frontend revus et intégrés (§9septdecies, §9octodecies)** ; reste à pousser, fermer/supprimer la PR/branche Rocket, et valider en direct. Prochain selon la feuille de route 30-60-90 : S10 (`/admin`) complet.
2. ~~Déployer sur METALVISION les 3 fichiers correctifs S07 et tester `approve_document()`~~ — **résolu** : déployé et validé en production (voir §9septies, addendum validation).
3. ~~Déployer `20260712110000_ccf_006f_documents_storage_bucket.sql` sur METALVISION (`supabase db push`), puis tester un dépôt de document réel dans l'écran `/documents` (upload, lecture, transition complète du cycle de vie) avant démonstration externe.~~ — **résolu** : déployé et testé de bout en bout en production le 12 juillet (voir §9octies, addendum validation). ~~Bug mineur non bloquant relevé : champ "ID de l'objet" en texte libre sans validation, messages d'erreur Postgres non affichés~~ — **résolu** : validation UUID + `getErrorMessage()` partagé sur les 6 emplacements (§9quinvicies).
4. Tests end-to-end du parcours CCF complet (organisation → capacité → opportunité → invitation → mandat → projet → documents → logistique → rapport) — validé jusqu'à **projet + invitation + acceptation + documents** inclus : trou de portée E08-T01/T02 trouvé (§9sexvicies), PR corrigée (§9septvicies), `INC-E08-01` trouvé et corrigé au test live (§9octovicies). Projet « consolider Acton Vale » créé, Test no 2 invitée et active, document déposé. Trou de portée logistique trouvé (§9novovicies), PR corrigée et validée en direct en production (§9tricies, 10ᵉ occurrence, `INC-S05-03` trouvé et corrigé au passage). Rapport de valeur créé et validé (§9unatricies). **Parcours CCF complet entièrement validé de bout en bout en production, aucune étape bloquante restante.**
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
16. Selon la feuille de route 30-60-90 : les 10 écrans (S01, S05-S10) et le tableau de bord sont désormais tous complets, corrigés et validés en production. ~~Reste, avant démonstration externe : item 3 (bucket Storage documents à tester en réel)~~ — résolu. ~~item 5 (dette technique DT-01 à DT-07)~~ — résolu (§5, mise à jour du 13 juillet). Reste : item 4 (test end-to-end du parcours CCF complet).
17. ~~Committer `Tranche0-Carbone-Architecture.md` et `supabase/carbon_migrations_proposed/`~~ — **résolu** : commit `4d77cda` poussé sur `main` (§12).
18. Validation séparée explicite requise avant de commencer la migration 02 (`aggregator_memberships`), conformément à la consigne de l'utilisateur (§12).

---

## 12. Tranche 0 carbone — Migration 01 (fondations transverses) exécutée avec succès, 14 juillet 2026

**Contexte :** après validation de l'architecture cible (v4 + 7 corrections finales, `Tranche0-Carbone-Architecture.md`) et du plan des sept migrations proposées (`supabase/carbon_migrations_proposed/`), la migration 01 (révision 4 — récursion RLS de `can_view_carbon_event()` corrigée, table de test non exposée durablement) a été appliquée manuellement sur l'unique environnement Supabase du projet (pas de staging séparé, comme déjà établi en §9septricies), suivie immédiatement de son script de validation séparé.

**Commit de référence :** au moment de l'exécution (14 juillet 2026), les fichiers testés n'étaient pas encore committés (`bc77b13` était alors le dernier commit poussé, `Tranche0-Carbone-Architecture.md` modifié et `supabase/carbon_migrations_proposed/` entièrement non suivi par git). **Commité et poussé après coup, une fois le succès confirmé :** `4d77cda` (« Tranche 0 carbone: architecture v4+7 corrections, migration 01 (revision 4) validee 22/22 sur environnement unique »), `bc77b13..4d77cda` sur `main`, 4 fichiers modifiés (899 insertions, 29 suppressions), incluant la création de `supabase/carbon_migrations_proposed/01_carbon_foundations_events_and_failures.sql` et `supabase/carbon_migrations_proposed/tests/01_test_foundations_events_and_failures.sql`. Ce commit correspond exactement au contenu qui a produit le résultat 22/22 ci-dessous (aucune modification entre l'exécution et le commit).

**Résultat obtenu, exécuté le 14 juillet 2026 contre l'unique environnement Supabase du projet :**

```
total_assertions | total_reussies | total_echouees
22                | 22              | 0
```

Détail : 16 assertions structurelles (Partie A — extension `btree_gist`, tables `carbon_business_events`/`carbon_rpc_failures`, colonnes `aggregator_id`/`verification_session_id`, RLS activée sur les deux tables, 2 triggers append-only, catalogue `event_type` = 31 valeurs exactement, `credit_issuance_voided`/`credit_issuance_externally_cancelled` distincts, 2 policies SELECT, fonction `can_view_carbon_event(...)` à 4 paramètres sans lecture de table, fonction `carbon_reject_update_delete()` utilisée par les deux triggers, `object_type` contient `aggregator_admin`) + 6 assertions comportementales (Partie B — rejet `event_type` invalide, rejet `object_type` invalide, `UPDATE`/`DELETE` rejetés sur `carbon_business_events` (append-only), survie ciblée d'une ligne `carbon_rpc_failures` au rollback-to-savepoint d'un bloc `EXCEPTION` non relancé, `DELETE` rejeté sur `carbon_rpc_failures`). **Aucun échec.**

**Aucune donnée de test résiduelle :** la porte de sortie bruyante du script (`RAISE EXCEPTION` si une ligne `NOT passed` existe) ne s'est pas déclenchée — les 3 nettoyages ciblés (B1/B2 conditionnels, nettoyage final B3-B6) se sont exécutés normalement, et le `DROP TABLE IF EXISTS public._carbon_migration_test_results` en toute fin de script s'est exécuté à son tour. **`_carbon_migration_test_results` a bien disparu après ce succès**, conformément au critère attendu.

**Objets créés par la migration 01 :**
- Extension `btree_gist` (prérequise par la migration 04).
- Table `carbon_business_events` (append-only, catalogue `event_type` TEXT+CHECK à 31 valeurs, colonne `verification_session_id` pour la portée RLS MRV future) + 4 index.
- Table `carbon_rpc_failures` (journal des échecs, séparé, garantie de persistance réelle et limitée documentée) + 2 index.
- Fonction `carbon_reject_update_delete()` + 2 triggers append-only (`carbon_business_events_no_update_delete`, `carbon_rpc_failures_no_update_delete`).
- Fonction `can_view_carbon_event(p_actor_id, p_organization_id, p_aggregator_id, p_verification_session_id)` — version de base sans lecture de table (`SECURITY INVOKER`, récursion RLS évitée), destinée à être étendue par la migration 05 (`CREATE OR REPLACE`, même signature) — correction : ce n'est pas 04, qui n'a pas de raison de toucher cette fonction (voir §15).
- Policy `carbon_business_events_select` (déléguée entièrement à `can_view_carbon_event()`) et policy `carbon_rpc_failures_select` (super-admin uniquement).
- Révocations et privilèges par défaut (`REVOKE ALL ... FROM PUBLIC, anon`, `GRANT SELECT ... TO authenticated`, `GRANT EXECUTE` sur `can_view_carbon_event`).

**Confirmation explicite : aucune migration suivante (02 à 07) n'a été appliquée.** Le répertoire `supabase/carbon_migrations_proposed/` reste entièrement hors de `supabase/migrations/`, aucun `supabase db push` n'a été exécuté, et aucun fichier n'a été déplacé. Conformément à l'instruction de l'utilisateur, la migration 02 ne débutera qu'après une validation séparée explicite.

---

## 13. Tranche 0 carbone — Migration 02 (`aggregator_memberships`) exécutée avec succès, 14 juillet 2026 — incluant une faille d'autorisation découverte et corrigée le jour même (migration 03)

**Contexte :** `02_carbon_aggregator_memberships.sql` (historisation des adhésions organisation↔regroupement, remplaçant `organizations.aggregator_id` comme source de vérité tout en le maintenant synchronisé à titre transitoire) a fait l'objet de six revues statiques successives par l'utilisateur le 14 juillet 2026, chacune ayant identifié des défauts précis (garde-fou contournable par `set_config`, bug de logique à trois valeurs `NULL` dans un `IF NOT (...)`, incohérence temporelle `now()`/`clock_timestamp()`, requêtes catalogue non scopées, faux échecs de test possibles, etc.), tous corrigés et confirmés avant approbation finale explicite : *« La révision statique finale de la migration 02 et de ses 56 tests est approuvée. Aucun autre changement fonctionnel SQL n'est demandé. »* Onze requêtes de vérification en direct du schéma réel (`02_verification_schema_reel.sql`) ont également été exécutées et confirmées conformes aux hypothèses de la migration avant toute exécution (principe établi en INC-DATA-01, §9novodecies : ne jamais se fier à l'historique versionné seul).

**Incident découvert pendant l'exécution des tests, corrigé le jour même :** le premier passage du script de tests a échoué à l'assertion B16 (chemin de succès attendu de `join_aggregator()`) avec l'erreur métier *« Cette organisation a déjà une adhésion active... »*, alors qu'aucune adhésion n'aurait dû exister à ce stade. Diagnostic : `is_platform_superadmin()` (`SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'`) renvoie **`NULL`**, pas `false`, dès que `app_metadata` n'a pas de clé `role` — le cas de tout utilisateur authentifié normal. Deux gardes d'autorisation de la migration 02, écrits en forme `IF NOT (...) THEN RAISE EXCEPTION`, échouaient alors **ouvert** au lieu de fermé (`NOT NULL` = `NULL`, et `IF NULL THEN` ne s'exécute jamais en PL/pgSQL) :
- `create_aggregator_with_primary_admin()` : `IF NOT public.is_platform_superadmin() THEN` — n'importe quel utilisateur authentifié normal pouvait créer un regroupement et s'auto-nommer administrateur.
- `join_aggregator()` : `IF NOT (is_aggregator_admin(...) OR is_platform_superadmin()) THEN` — n'importe quel utilisateur authentifié normal pouvait rattacher n'importe quelle organisation à n'importe quel regroupement.

**Ce bug était réellement exploitable en production** entre l'application de la migration 02 et celle du correctif (quelques minutes le même jour) — pas un simple artefact de test. `leave_aggregator()` et la policy RLS `aggregator_memberships_select` utilisent le même `OR` à l'intérieur d'une clause `WHERE`/`USING` : sémantiquement sûres (une ligne n'est retenue que si la condition vaut exactement `true`, donc `NULL` y échoue fermé) — non concernées.

**Correctif :** `03_fix_null_bypass_authorization.sql` — `CREATE OR REPLACE FUNCTION` ciblé sur ces deux fonctions uniquement (aucun changement de schéma ni de données), ajoutant `COALESCE(..., false)` sur `is_platform_superadmin()` (et, par défense en profondeur, sur `is_aggregator_admin()`). Prévalidation (signatures exactes via `to_regprocedure`) et post-validation (présence du `COALESCE` dans `pg_get_functiondef`) intégrées, transaction `BEGIN`/`COMMIT` explicite. Appliqué avec succès (« Success. No rows returned »).

**Résultat obtenu après correctif, script de tests complet rejoué :**

```
total_assertions | total_reussies | total_echouees
56                | 56              | 0
```

Détail : 24 assertions structurelles (Partie A — table `aggregator_memberships` et contraintes, index unique partiel une-adhésion-active-par-organisation, `SECURITY DEFINER`/`search_path` sur les 3 RPC, privilèges `EXECUTE`/table réels via `has_function_privilege`/`has_table_privilege`, garde-fou `organizations.aggregator_id` avec trigger `BEFORE UPDATE OF` vérifié via `pg_get_triggerdef`, fonction de compatibilité `SECURITY DEFINER` avec `EXECUTE` révoqué, backfill vérifié ligne à ligne — pas seulement en total global — et traçabilité complète des événements de backfill) + 32 assertions comportementales (Partie B — porte d'authentification des 3 RPC, contraintes/triggers directs sur la table (doublon, `CHECK ended_at`, transitions interdites, `DELETE` rejeté), bootstrap super-admin, isolation stricte de l'autorisation D1 (admin d'un autre regroupement rejeté, admin d'organisation seul rejeté, admin du regroupement cible accepté), RLS sous rôle `authenticated` réel avec trois identités isolées (membre, admin cible, tiers), `leave_aggregator()` avec autorisation repliée dans la clause `WHERE` (pas de fuite d'information), garde-fou anti-écriture-directe sur `organizations.aggregator_id` avec message exact vérifié et preuve définitive en profondeur de trigger, marqueur transactionnel testé comme absent/réinitialisé/inactif plutôt que strictement `NULL`). **Aucun échec.**

**Objets créés par la migration 02 :** table `aggregator_memberships` (historisée, append-only après clôture, index unique partiel), triggers de garde (`carbon_guard_aggregator_membership_update`, rejet `DELETE`), fonction de compatibilité transitoire `carbon_sync_organizations_aggregator_id_compat()` (`SECURITY DEFINER`, verrouillée), garde-fou `carbon_guard_organizations_aggregator_id_direct_write()` sur `organizations.aggregator_id`, policy RLS `aggregator_memberships_select`, RPC `create_aggregator_with_primary_admin()`/`join_aggregator()`/`leave_aggregator()` (ces deux premières corrigées par la migration 03 le jour même), backfill des adhésions préexistantes avec événements `aggregator_membership_started` synthétiques traçables (`source = migration_02_backfill`).

**Aucune donnée de test résiduelle** : le premier passage (échec B16) a été annulé intégralement par PostgreSQL (transaction implicite unique, aucune donnée de test n'a persisté) ; le second passage (post-correctif) a atteint sa porte de sortie normale, 56/56, et `_carbon_migration_test_results` a bien disparu.

**Confirmation explicite (au moment de la migration 02, 14 juillet 2026) : les migrations 04 à 07 n'avaient pas encore été appliquées.** `supabase/carbon_migrations_proposed/` reste hors de `supabase/migrations/`. Cette confirmation ne vaut que pour l'état constaté ce jour-là — voir §14 (18 juillet 2026, 06 appliquée) puis §15 (21 juillet 2026, 04/05/07 appliquées) pour l'évolution ultérieure ; seules 08 et 09 restent non appliquées à la date de rédaction la plus récente (§15).

---

## 14. Tranche 0 carbone — Migration 06 (`platform_operators` + `carbon_commercialization_mandates`) exécutée avec succès, 18 juillet 2026 — désignation réelle de METALTRACE comme opérateur/vendeur carbone central

**Contexte :** `06_carbon_operator_and_mandates.sql` (Tranche0-Carbone-Architecture.md §13/§14) formalise le pivot architectural décidé le 14 juillet 2026 : METALTRACE devient l'opérateur/vendeur carbone central, les regroupements (agrégateurs) restant des entités économiques/opérationnelles jamais vendeuses juridiques elles-mêmes. Le fichier a fait l'objet de plusieurs revues statiques successives par l'utilisateur avant toute exécution, dont trois corrections bloquantes majeures : D13 (fuite d'existence dans `grant_commercialization_mandate()` et `revoke_commercialization_mandate()` — recherche et autorisation désormais fusionnées dans la même requête, message générique unique `'Adhésion introuvable ou accès refusé.'` / `'Mandat introuvable ou accès refusé.'` indistinguable qu'il s'agisse d'un UUID inexistant ou d'un enregistrement inaccessible), D14 (`is_active_platform_operator_member()` durcie avec `COALESCE(..., false)`) et D15 (incohérence temporelle dans `designate_platform_operator()` — `clock_timestamp()` pour la révocation de l'ancien opérateur vs `DEFAULT now()` figé au début de transaction pour la désignation du nouveau, pouvant faire apparaître une nouvelle désignation comme antérieure à la révocation qu'elle remplace ; corrigée par une capture unique `v_transition_at` réutilisée pour les deux écritures). Validation finale accordée le 18 juillet 2026 avec un ordre d'exécution strict en six étapes (migration → tests → 62/62 → absence de résidus → désignation réelle → documentation ADR).

**Étape 1 (migration) :** appliquée avec succès du premier coup.

**Étape 2 (tests), deux incidents découverts et corrigés en cours d'exécution réelle — aucun des deux n'avait été détecté en revue statique :**

1. *Échec de nettoyage (garde-fou de dépréciation `organizations.aggregator_id`).* Le premier passage du script de tests a échoué avec `P0001 : organizations.aggregator_id est dépréciée et ne peut être modifiée directement`. Diagnostic : la migration 02 ne synchronise `organizations.aggregator_id` (colonne dépréciée) qu'à l'`INSERT`/`UPDATE` de `aggregator_memberships`, jamais au `DELETE`. Le scénario de réadhésion du script de tests (B28-B35) laisse délibérément une adhésion active jusqu'aux tests RLS finaux ; le nettoyage supprimait cette ligne par un `DELETE` brut, jamais vu par le trigger de synchronisation, laissant `organizations.aggregator_id` pointer vers l'agrégateur de test — dont la suppression, juste après, déclenchait une action référentielle `ON DELETE SET NULL` rejetée par le garde-fou de dépréciation (lui-même correct : il rejette toute écriture ne provenant pas du mécanisme de compatibilité légitime). Corrigé dans `tests/06_test_operator_and_mandates.sql` en terminant proprement (`UPDATE ... SET ended_at`) toute adhésion de test encore active avant le `DELETE` brut. La transaction ayant échoué s'est annulée intégralement (aucune donnée résiduelle, y compris la table `_carbon_migration_test_results` elle-même) — confirmé par requête avant nouvelle tentative.

2. *Fuite de privilège `EXECUTE` vers `anon` (assertion A21).* Deuxième passage : script complet jusqu'à la porte de sortie, résultat 61/62 — seule A21 en échec (« privilège EXECUTE réel : accordé à authenticated, absent de anon, pour les 6 nouvelles fonctions »). Diagnostic : la section « Privilèges » de la migration 06 traite les deux nouvelles tables correctement (`REVOKE ALL ... FROM PUBLIC, anon, authenticated`) mais les 6 nouvelles fonctions `SECURITY DEFINER` seulement à moitié (`REVOKE ALL ... FROM PUBLIC`, sans `anon` ni `authenticated`) — incohérence interne au même fichier. Ce projet Supabase accorde apparemment `EXECUTE` à `anon` directement à la création d'une fonction, indépendamment de `PUBLIC`, laissant ce privilège en place malgré le `REVOKE` incomplet. Impact réel limité (chaque fonction rejette `auth.uid() IS NULL` en tout premier), mais défaut de défense en profondeur corrigé par prudence. Correctif : `06a_fix_function_privileges_anon_leak.sql` (privilèges uniquement, aucun changement de corps de fonction ni de schéma), avec prévalidation/post-validation via `has_function_privilege()`.

À cette occasion, un défaut structurel du script de tests lui-même a également été corrigé : Supabase SQL Editor exécute tout le texte collé en une seule transaction implicite, si bien que la « porte de sortie bruyante » d'origine (qui lève une exception en cas d'échec) annulait la transaction entière — y compris la table de diagnostic censée permettre l'investigation. Le script est désormais scindé en Partie 1 (fixtures, tests, nettoyage, résumé — se termine toujours normalement, sans `RAISE EXCEPTION` inconditionnel) et Partie 2 (porte de sortie + `DROP TABLE`, à exécuter séparément une fois le résumé de la Partie 1 inspecté).

**Résultat final, troisième passage (après application de 06a) :**

```
total_assertions | total_reussies | total_echouees
62                | 62              | 0
```

Détail : 22 assertions structurelles (Partie A) + 40 assertions comportementales (Partie B), couvrant notamment l'historique de `platform_operators` (jamais un booléen), l'invariant au-plus-un-opérateur-actif, la RLS des mandats via `is_active_platform_operator_member()` avec isolation stricte de chaque branche testée séparément (membre de l'organisation titulaire seul, membre de l'organisation opératrice seul avec appartenance titulaire explicitement retirée au préalable, externe sans aucune relation), le scénario de réadhésion (un ancien mandat ne s'applique jamais à une nouvelle adhésion), la validation sémantique de `mandate_document_id` (D12), le rejet des doublons dans `scope`, et les deux corrections D13 (messages génériques indistinguables) et D15 (cohérence temporelle exacte `ancien.revoked_at = nouveau.designated_at`) vérifiées explicitement. **Aucun échec.**

**Absence de données résiduelles confirmée explicitement** (requête post-nettoyage : organisations/agrégateurs/documents de test = 0, `organizations.aggregator_id` correctement resynchronisé à `NULL`, table `_carbon_migration_test_results` supprimée).

**Étape 5 — désignation réelle de l'opérateur METALTRACE :** l'entité juridique METALTRACE n'existait pas encore comme organisation dans la base. Créée : **MINOVIA création d'application web Inc.** (`organizations.id = 8fb58059-3758-4972-9d27-6f732e94f6c7`). Désignée opérateur/vendeur carbone central via `designate_platform_operator()`, appelée en contexte super-admin authentifié réel (profil `09973654-e6ca-4e12-8691-edf09b57a7fa`, `centredelasante@gmail.com`). Confirmé : `is_platform_operator('8fb58059-3758-4972-9d27-6f732e94f6c7') = true`.

**Objets créés par la migration 06 :** table `platform_operators` (historisée, append-only, index unique sur expression constante `idx_one_active_platform_operator` garantissant au plus un actif), table `carbon_commercialization_mandates` (historisée, append-only, scope catalogue fermé et sans doublon, immuable après création, un seul mandat actif par `aggregator_membership_id` précis) ; fonctions `is_platform_operator()`, `is_active_platform_operator_member()`, `designate_platform_operator()`, `revoke_platform_operator()`, `grant_commercialization_mandate()`, `revoke_commercialization_mandate()` (toutes `SECURITY DEFINER`, `search_path` durci) ; policies RLS correspondantes ; catalogue `carbon_business_events` étendu de 31 à 35 valeurs `event_type` et de 12 à 14 valeurs `object_type`. Correctif `06a` : privilèges `EXECUTE` des 6 fonctions ci-dessus corrigés (`anon` explicitement exclu).

**Commit :** `c6d3c3e` — *« Migration 06 : operateur METALTRACE central + mandats de commercialisation (62/62) »* — `supabase/carbon_migrations_proposed/06_carbon_operator_and_mandates.sql`, `06a_fix_function_privileges_anon_leak.sql`, `tests/06_test_operator_and_mandates.sql`, poussé sur `origin/main`.

**Confirmation explicite (valable au 18 juillet 2026, avant leur exécution documentée au §15 ci-dessous) : les migrations 04, 05, 07, 08, 09 n'avaient pas été appliquées à cette date.** `supabase/carbon_migrations_proposed/` restait alors entièrement hors de `supabase/migrations/`. Voir §15 : 04, 05 et 07 sont depuis appliquées avec succès (21 juillet 2026) ; seules 08 et 09 restent non appliquées.

---

## 15. Tranche 0 carbone — Migrations 04, 05 et 07 exécutées avec succès en réel, 21 juillet 2026 — réouverture unique et contrôlée de 07 pour la réconciliation CCF↔MRV

**Contexte :** `04_carbon_ccf_mrv_project_links.sql` et `05_carbon_verification_outcomes.sql` avaient été rédigées et gelées après revue statique approfondie (voir §12-§14 pour la méthode). `07_carbon_issuances.sql` et ses tests, gelés depuis la dix-neuvième revue statique (bien avant que 04/05 n'existent), n'avaient eux jamais été exécutés contre une base réelle. Les trois migrations ont été appliquées et testées dans l'ordre strict 04 → 05 → 07, chacune via l'éditeur SQL Supabase (exécution manuelle par l'utilisateur, diagnostic des échecs par itérations successives), sans jamais élargir la portée d'une migration au-delà de son autorisation.

**Migration 04 (`ccf_mrv_project_links`) — appliquée avec succès du premier coup.**

```
total_assertions | total_reussies | total_echouees
44                | 44              | 0
```

Un seul incident, dans les fixtures du test (pas la migration) : deux `INSERT` directs de contournement (B20bis/B20ter) omettaient `ended_by`, désormais requis conjointement avec `ended_at` par la contrainte `ccf_mrv_project_links_ended_at_by_coherent` — corrigé dans le fichier de test.

**Migration 05 (`verification_outcomes`) — appliquée avec succès, un bug réel de la migration trouvé et corrigé en cours de test.**

```
total_assertions | total_reussies | total_echouees
128               | 128             | 0
```

Bug de migration trouvé et corrigé : `complete_verification_session()` validait longuement `adjustment_reason` (obligatoire pour toute supersession) mais omettait la colonne de la liste de l'`INSERT` dans `verification_outcomes` — la valeur validée n'était donc jamais persistée, et le trigger `carbon_guard_verification_outcome_insert()` (qui revalide structurellement la même règle) rejetait alors systématiquement toute supersession légitime. Corrigé dans le fichier de migration lui-même, et appliqué à la base déjà migrée via un correctif ponctuel `CREATE OR REPLACE FUNCTION` (`05_correctif_complete_verification_session.sql`, idempotent, sans rejouer la migration entière). **Statut de ce fichier correctif : artefact historique, non versionné dans `supabase/carbon_migrations_proposed/` ni committé.** Il a servi une seule fois, en direct sur l'éditeur SQL Supabase, pour appliquer immédiatement le correctif sans rejouer toute la migration 05 (dont les gardes de prévalidation de section 0 auraient échoué sur « existe déjà »). **`05_carbon_verification_outcomes.sql` (la migration canonique, committée) contient déjà la version corrigée de `complete_verification_session()`** avec la colonne `adjustment_reason` présente dans l'`INSERT` — un rebuild propre à partir de ce seul fichier canonique (sur un environnement neuf) produit directement le comportement correct, sans avoir besoin du correctif ponctuel. Quatre bugs de test (pas de la migration) trouvés et corrigés au passage : bitmask de trigger erroné (`& 8` au lieu de `& 16` pour vérifier « INSERT OR UPDATE »), ordre d'un bloc de démotion inversé par rapport au test qui en dépendait, mauvais acteur passé à une assertion, et une valeur JSON invalide (chaîne non guillemetée) dans un `SET scope`.

**Migration 07 (`credit_issuances`) — réconciliation unique autorisée, puis appliquée et testée avec succès en réel pour la toute première fois.**

Conformément au « CONTRAT OUVERT VERS 07 » documenté en tête de 04, exactement une réconciliation a été appliquée à `07_carbon_issuances.sql` : ajout de `AND link.ended_at IS NULL` à la jointure `ccf_mrv_project_links` dans `carbon_is_source_organization_valid()` et `carbon_lock_and_validate_source_organization()`, pour exploiter les liens CCF↔MRV désormais disponibles via 04. Aucune autre modification de la logique de production de 07 n'a été autorisée ni effectuée.

```
total_assertions | total_reussies | total_echouees
110               | 110             | 0
```

**Tous les incidents rencontrés lors de l'exécution de 07 relevaient des fixtures/tests, jamais de sa logique de production** — attendu pour un fichier n'ayant jamais tourné en réel avant ce jour, et gelé avant même l'existence de 04/05 :
- Cap de répétition regex PostgreSQL (`DUPMAX=255`) dépassé par `[^;]{0,400}` dans un utilitaire de test — remplacé par `[^;]*` (équivalent, non plafonné).
- Fixtures `verification_sessions` omettant `verifier_user_id`, désormais requis par la `CHECK` de 05 pour `status='completed'` — ajouté, avec une ligne `accredited_verifiers` correspondante.
- Découverte plus profonde : `verification_sessions.project_id` porte une FK réelle vers `public.projects` (MRV), jamais directement vers `ccf_projects` — les fixtures utilisaient l'id CCF directement. Corrigé en créant un projet MRV dédié relié au projet CCF de test via un vrai `ccf_mrv_project_links`, exerçant enfin le chemin CCF↔MRV réellement prévu par la réconciliation ci-dessus.
- `verification_outcomes.verification_report_document_id`, désormais `NOT NULL` et validé par 05, manquant dans les fixtures — ajouté (`evidence_files` de test correctement séquencées après la création de leur projet).
- Un `INSERT` multi-lignes créant directement un résultat `superseded` — désormais rejeté par le trigger de 05 (une ligne ne peut être insérée qu'`active`) — restructuré en insertion active → démotion → réinsertion avec `supersedes_outcome_id`.
- Trois appels à `complete_verification_session()` passant `NULL` pour la preuve désormais obligatoire, et utilisant un acteur super-admin alors que cette fonction est réservée au vérificateur assigné à la session depuis une revue antérieure de 05 — corrigés.
- Bug d'ordonnancement des fixtures : deux émissions de test étaient soumises (`submit_credit_issuance()`) bien après que leur résultat de vérification d'origine ait été légitimement supersédé par le scénario de test lui-même — or `submit_credit_issuance()` exige que le résultat référencé soit encore actif au moment de la soumission (invariant natif de 07, indépendant de 05). Corrigé en avançant la soumission juste après la création de chaque émission, pendant que son résultat était encore actif.
- Artefact du harnais de test (pas un bug de 07) : `trg_carbon_validate_issuance_capacity` est une contrainte différée (`DEFERRABLE INITIALLY DEFERRED`) qui ne se valide qu'au `COMMIT` ou à un `SET CONSTRAINTS ... IMMEDIATE` explicite. En production chaque appel RPC committe dans sa propre transaction, donc ce contrôle se décharge bien avant toute supersession future. Ce script de test s'exécutant entièrement dans une seule transaction (`BEGIN...ROLLBACK`), deux paires `SET CONSTRAINTS ... IMMEDIATE`/`DEFERRED` explicites ont été ajoutées juste après les créations d'émissions concernées, pendant que leur résultat de vérification était encore actif, pour reproduire fidèlement la sémantique de production.

**Aucune donnée de test résiduelle** pour les trois migrations : chaque script s'est terminé sur son résumé normal (aucune porte de sortie bruyante déclenchée par un échec), suivi du `ROLLBACK` explicite de fin de script.

**Commit :** `7145ec7` — *« Tranche 0 carbone : 04/05/07 executees avec succes en reel (44/44, 128/128, 110/110) »* — 7 fichiers modifiés (3521 insertions, 289 suppressions) : `supabase/carbon_migrations_proposed/04_carbon_ccf_mrv_project_links.sql`, `05_carbon_verification_outcomes.sql`, `07_carbon_issuances.sql`, `tests/04_test_ccf_mrv_project_links.sql`, `tests/05_test_verification_outcomes.sql`, `tests/07_test_carbon_issuances.sql`, et `ADR-MVP.md` (ce présent §15 ainsi que les corrections apportées au bandeau global et aux §12/§13/§14). Committé localement sur `main`, puis suivi du commit documentaire `c19ead5` (ajout de la référence de ce hash dans le présent paragraphe). **Les deux commits sont poussés et confirmés présents sur `origin/main`** (`adc37de..c19ead5 main -> main`, push exécuté depuis le poste de l'utilisateur le 21 juillet 2026, environnement d'exécution de cette session sans accès en écriture au dépôt distant). Le correctif ponctuel `05_correctif_complete_verification_session.sql` n'est délibérément pas inclus dans ces commits (voir sa note de statut dans le paragraphe sur la migration 05 ci-dessus).

**Important — nature de l'application de 04, 05 et 07 :** ces trois migrations ont été appliquées **manuellement** à l'unique environnement Supabase du projet, via l'éditeur SQL (même méthode que 01, 02+03 et 06+06a — voir §12-§14). Elles **ne sont pas passées par `supabase db push`**, restent **hors de `supabase/migrations/`**, et **n'apparaissent donc pas dans l'historique automatisé `schema_migrations`** de Supabase. La base de production est réellement dans l'état décrit ci-dessus (objets créés, fonctions corrigées, 44/128/110 assertions au vert), mais un outil qui n'inspecterait que `schema_migrations` ou le dossier `supabase/migrations/` ne le verrait pas — seul ce document (et une lecture directe du schéma réel) en fait foi, exactement comme pour 01/02+03/06+06a.

**Confirmation explicite (valable au 21 juillet 2026, avant l'exécution documentée aux §16 et §18 ci-dessous) : seules les migrations 08 et 09 restaient alors non appliquées.** `supabase/carbon_migrations_proposed/` reste hors de `supabase/migrations/` dans son ensemble (04 à 09 compris, pour la raison ci-dessus) — voir §16 (08 appliquée, 22 juillet 2026) et §18 (09 appliquée et validée, 24 juillet 2026) pour l'état courant.

---

## 16. Tranche 0 carbone — Migration 08 (`credit_lots`, cycle commercial) exécutée avec succès en réel, 22 juillet 2026 — reconstruction transactionnelle depuis un objet legacy, deux blocages réels résolus, 87/87 en test

**Contexte :** `08_carbon_lots_commercial_cycle.sql` et ses tests avaient été gelés après cinq revues statiques successives (voir la conception §16 de `Tranche0-Carbone-Architecture.md`). Contrairement aux migrations 01 à 07 (appliquées manuellement via l'éditeur SQL Supabase), 08 a été exécutée **directement par l'agent, via le connecteur MCP Supabase** (`apply_migration`/`execute_sql`), après connexion explicitement autorisée par l'utilisateur pour cette étape.

**Deux blocages réels rencontrés lors de l'exécution de la migration elle-même (avant tout COMMIT), tous deux diagnostiqués, résolus et revérifiés avant relance :**

1. **Faux positif de prévalidation (0.f, privilèges).** Premier essai rejeté : la comparaison symétrique des privilèges sur `credit_lots` (legacy) ne tenait pas compte des privilèges implicites du propriétaire réel de la table, exposés par `information_schema.role_table_grants` au même titre que les GRANT applicatifs. Corrigé en excluant dynamiquement `pg_tables.tableowner` de la comparaison (pas un `grantee <> 'postgres'` codé en dur, par exigence explicite), avec un contrôle séparé figeant l'identité du propriétaire. Rollback automatique confirmé sans effet de bord avant correction.
2. **Découverte structurelle réelle (0.h, FK externe).** Second essai rejeté pour une raison différente et légitime : une contrainte FK non documentée, `credit_sale_lots.credit_lot_id → credit_lots.id`, provenant de 5 tables vides et non commentées pré-existantes (`credit_sales`, `credit_sale_lots`, `distribution_rules`, `member_distribution_overrides`, `credit_sale_allocations`) — vraisemblablement antérieures à la réécriture Tranche 0, relevant du domaine que la migration 09 doit couvrir. Présenté à l'utilisateur avec 3 options ; **choix retenu : supprimer les 5 tables vides** (vérifiées vides immédiatement avant, absence et zéro FK résiduelle vérifiées immédiatement après), appliqué comme migration séparée et explicite (`pre08_drop_legacy_empty_credit_sale_tables`). Rollback automatique de 08 confirmé sans effet de bord avant cette résolution.

**Migration 08 — appliquée avec succès (troisième essai, après résolution des deux blocages ci-dessus).** Reconstruction transactionnelle de `credit_lots` (renommage de l'objet legacy en `credit_lots_legacy_pre08`, recréation canonique à 12 colonnes avec cycle commercial à 5 statuts, 4 triggers, RLS, RPC `issue_credit_lot()`/`void_credit_lot()`), `COMMIT` réel confirmé, `credit_lots_legacy_pre08` supprimée en fin de transaction.

**Tests (`08_test_carbon_lots.sql`) — 87/87 assertions, 0 échec, 0 doublon, confirmé mécaniquement par le gate du fichier lui-même.** Quatre incidents rencontrés, **tous des bugs de harnais de test propres à cet environnement d'exécution réel (jamais la logique de production de 08)** :
- Cast `::regprocedure` redondant au call-site de `carbon_test_has_scoped_lock()` (A23/A24) : la fonction caste déjà `TEXT -> regprocedure` en interne ; le cast supplémentaire au call-site empêchait la résolution de surcharge (`regprocedure -> text` n'est qu'un cast d'assignation, pas implicite). Corrigé en retirant le cast redondant.
- `GRANT INSERT` manquant sur la `TEMP TABLE` de résultats pour le rôle `authenticated` (une table temporaire n'accorde par défaut aucun privilège à un autre rôle que son propriétaire, contrairement aux fonctions) — et de même pour la séquence `SERIAL` sous-jacente. Les deux correctifs par `GRANT` ponctuels ont été remplacés par une solution plus robuste : `carbon_test_assert()` rendue `SECURITY DEFINER`, insensible au rôle actif au moment de l'appel.
- Découverte la plus notable : **cet environnement d'exécution (outil MCP `execute_sql`) englobe tout script soumis dans sa propre transaction externe.** Le `ROLLBACK` explicite du fichier (conçu pour annuler les fixtures tout en gardant la table de résultats temporaire vivante) annule donc aussi la `CREATE TEMP TABLE` elle-même, rendant le `DROP TABLE` final du fichier invalide (table déjà inexistante). Diagnostiqué par isolation successive (scripts minimaux reproduisant puis excluant chaque hypothèse), confirmé, puis corrigé en retirant ce `DROP TABLE` final, redondant de toute façon (une `TEMP TABLE` disparaît automatiquement à la fin de la session, avec ou sans `DROP` explicite).

**Aucune donnée de test résiduelle** : le script s'est terminé sur son résumé normal (gate 87/87 franchi, aucune `RAISE EXCEPTION` de porte de sortie), suivi du `ROLLBACK` explicite de fin de script. Vérifié après chaque tentative échouée de la migration elle-même (comptages `TEST-08*` et `credit_lots` à zéro).

**Confirmation explicite (valable au 22 juillet 2026, jour même de l'application de 08, avant l'exécution de 09 documentée au §18 ci-dessous) : seule la migration 09 restait alors non appliquée.** `supabase/carbon_migrations_proposed/` reste hors de `supabase/migrations/` dans son ensemble (08 et 09, pour la même raison de méthode d'application que 01-07 : historique `schema_migrations` non renseigné pour ce dossier) — voir §18 pour l'application et la validation réelles de 09, un jour plus tard.

**Phrase suivante marquée HISTORIQUE/SUPERSÉDÉE (état du 22 juillet 2026, jour même de l'application de 08) — corrigée après la HUITIÈME revue statique de 09 (23 juillet 2026), qui a constaté que cette phrase ne reflète plus l'état réel depuis plusieurs revues et ne doit plus être lue comme le statut courant, et réactualisée après la NEUVIÈME revue statique de 09 (même jour) : « Migration 09 reste fermée — aucun travail entamé. »** Cette affirmation était exacte le 22 juillet 2026 mais est devenue fausse dès la rédaction du SQL de 09 et de ses tests, le jour suivant : le fichier `09_carbon_sales_financial_model.sql`, ses deux fichiers de test et le protocole de concurrence STAGING_ONLY sont rédigés, ont traversé neuf revues statiques correctives successives, et restent **non exécutés** dans l'attente d'une autorisation explicite — un statut très différent de « aucun travail entamé ». Voir `Tranche0-Carbone-Architecture.md` §17 (statut courant, en tête de section) pour l'état exact et à jour, et §17 point 20 pour l'historique complet des revues statiques.

---

## 17. Réconciliation — Cahier fonctionnel MVP CCF v1.2 et Tranche 0 carbone (ajoutée après la SEPTIÈME revue statique de 09, 23 juillet 2026)

**Motif de cette note :** le Cahier fonctionnel MVP v1.2 (Annexe B, `MVP-DA-001` à `008`) et le backlog original du MVP CCF définissent un périmètre v1 qui **exclut explicitement** le registre carbone complet et l'émission de crédits (renvoyés à une version ultérieure), et où le Regroupement pérenne est explicitement une notion de V2. `MVP-DA-002` y établit par ailleurs que MetalTrace ne devient jamais acheteur, vendeur ou transporteur dans le modèle CCF (marché physique des métaux). L'architecture de la Tranche 0 carbone (`Tranche0-Carbone-Architecture.md`, §1-§20) fait ensuite de METALTRACE le **vendeur/opérateur juridique des crédits carbone** (`credit_sales.seller_organization_id` figé sur l'organisation opératrice, §17 point 10 de ce document architecture) — une lecture rapide pourrait laisser croire à une contradiction avec `MVP-DA-002`, ou à une extension rétroactive du périmètre v1 original. **Aucune modification n'est apportée ici ni au cahier fonctionnel PDF ni au backlog original** — les deux restent la source de vérité de leur propre périmètre historique. Cette note élimine l'ambiguïté sans réécrire l'historique :

1. Le Cahier fonctionnel v1.2 décrit le **périmètre historique du MVP CCF initial** (Centre de Consolidation Ferroviaire) — registre carbone complet/émission de crédits explicitement hors périmètre v1, Regroupement pérenne explicitement renvoyé à la V2. Ce périmètre reste tel quel, non réécrit.
2. La **Tranche 0 carbone est une extension ultérieure, séparément décidée et autorisée** par l'utilisateur (voir `Tranche0-Carbone-Architecture.md`, en-tête et §17 point 20 pour l'historique complet des décisions), qui **coexiste** avec le MVP CCF sur la même base Supabase, sans le remplacer ni le modifier rétroactivement (aucune migration de la Tranche 0 ne touche une table ou une RPC du domaine CCF).
3. `MVP-DA-002` **continue de s'appliquer intégralement au marché physique des métaux** dans le domaine CCF : METALTRACE ne devient ni acheteur, ni vendeur, ni transporteur des **métaux**, et ne prend jamais possession physique des métaux. Rien dans la Tranche 0 carbone ne modifie cette décision — les deux domaines portent sur des objets économiques distincts (métaux physiques vs crédits carbone).
4. Le rôle de `seller_organization_id` dans `credit_sales` (Tranche 0 carbone) concerne **exclusivement** la commercialisation juridique des **crédits carbone**, sous `carbon_commercialization_mandates` explicites accordés par les organisations membres d'un regroupement (§17 points 1/10 de l'architecture carbone) — jamais une extension du rôle de METALTRACE dans le marché physique des métaux régi par `MVP-DA-002`.
5. Cette extension **n'a jamais fait partie du périmètre MVP v1 original** et ne doit jamais être présentée comme telle — elle est documentée, tracée et autorisée séparément (voir `Tranche0-Carbone-Architecture.md` pour la conception complète, et §12-§16 et §18 de ce document pour l'historique d'exécution réel des migrations 01 à 09 — toutes appliquées en production ; seule la validation de concurrence STAGING_ONLY de 09 reste distincte et non exécutée, voir §18).

---

## 18. Tranche 0 carbone — Migration 09 (`credit_sales`, modèle commercial et financier des ventes de crédits carbone) exécutée avec succès en réel, 24 juillet 2026 — GATE 1/GATE 2/GATE 3, huit causes racines de défaut du harnais de test identifiées et corrigées, aucune anomalie de production

**Contexte :** `09_carbon_sales_financial_model.sql` et ses deux fichiers de test (`09_test_carbon_sales_financial_model.sql` transactionnel, et `09_test_carbon_sales_financial_model_concurrency_STAGING_ONLY.sql` distinct) avaient été gelés après quinze revues statiques successives (voir la conception §17 de `Tranche0-Carbone-Architecture.md`). Application en trois portes (« GATE ») séquentielles et strictement disjointes, chacune autorisée séparément par l'utilisateur :

**GATE 1 — application de la migration seule : ✅.** `09_carbon_sales_financial_model.sql` appliquée en production sans le harnais de test (tables `credit_sales`, `credit_sale_lots`, `credit_sale_costs`, `credit_sale_adjustments`, `credit_sale_allocations`, `distribution_rules`, `distribution_rule_proposals`, `member_distribution_overrides`, `member_distribution_override_proposals` (9/9, confirmées par GATE 2) ; RPC `create_credit_sale()`/`add_credit_sale_lot()`/`confirm_credit_sale()`/`propose_distribution_rule()`/`propose_member_distribution_override()` et fonctions d'approbation associées ; triggers de gouvernance et d'intégrité différée).

**GATE 2 — contrôles read-only post-migration : ✅ conformes.** Vérification structurelle en lecture seule uniquement (aucune écriture), confirmant la présence et la forme attendue des objets créés par GATE 1.

**GATE 3 — harnais transactionnel exécuté contre la production et validé 196/196, avec `ROLLBACK` final ; aucune donnée de test persistée.** Exécution via `psql --file` depuis le poste de l'utilisateur (jamais via l'outil `execute_sql`, abandonné après trois échecs de troncature du fichier lors d'une tentative antérieure), dans une transaction unique `BEGIN ... ROLLBACK`. **Distinction importante pour la lecture de cet audit :** GATE 1 est une migration réellement appliquée (état persistant) ; GATE 2 est un contrôle read-only de cet état persistant ; GATE 3 est un comportement testé contre le schéma de production réellement en place, mais au moyen de fixtures entièrement annulées par le `ROLLBACK` final — aucune ligne de test n'a jamais été committée.

**Discipline d'exécution :** chaque tentative précédée d'un préflight obligatoire (MD5, longueur en octets, nombre de sauts de ligne du fichier réellement transmis à `psql`, comparés à la version explicitement autorisée) ; tout échec d'exécution entraînait un arrêt immédiat, une vérification read-only de l'absence de donnée résiduelle et de transaction ouverte, puis un rapport exact de l'erreur — aucune correction sans diagnostic explicite de l'utilisateur, aucune nouvelle tentative sans nouvelle autorisation explicite.

**Huit causes racines de défaut du harnais identifiées au total, sur six tentatives d'exécution successives — toutes des défauts du harnais de test (fixtures ou attentes d'assertion), jamais de la logique de production de 09. Aucune n'a nécessité de modifier la migration 09 ni la logique de production ; toutes ont été résolues dans le harnais transactionnel.** Plusieurs ont, au contraire, démontré que les invariants et garde-fous des migrations 07/08/09 rejetaient correctement des fixtures ou transitions incohérentes (les quatre premières causes, bloquantes, notamment) ; les autres relevaient d'attentes de test devenues périmées ou d'une contamination d'état entre scénarios, sans mettre en cause un garde-fou de production. Décompte exact : 4 blocages successifs (une exécution interrompue par tentative, sur les quatre premières tentatives) + 8 échecs d'assertion découverts en une seule tentative complète (la cinquième), regroupés en 4 causes racines supplémentaires = 8 causes racines au total, sur 6 tentatives d'exécution.

*Quatre premières causes racines, bloquantes (chacune a interrompu l'exécution du script, une par tentative, corrigées successivement) :*
1. **Isolation de capacité manquante (`issuance_bis`/`lot_bypass`).** Un bloc de fixture tentait d'émettre 3 t depuis une émission ne disposant que de 2 t de capacité réelle — rejeté par `issue_credit_lot()`. Corrigé en isolant la fixture concernée dans sa propre émission dédiée, avec sa propre capacité.
2. **Mauvais acteur d'approbation (`orga` au lieu d'`orgb`).** Un test réutilisait l'acteur `orga` pour approuver une opération sur une adhésion appartenant en réalité à ORG_B — rejeté par `propose_member_distribution_override()`. Corrigé en utilisant l'acteur `orgb`, propriétaire réel de l'adhésion concernée.
3. **Réutilisation d'une chaîne/session de vérification dont la capacité active était déjà entièrement consommée.** Un bloc de fixture référençait un `verification_outcome` appartenant à une `verification_session` dont la capacité admissible était déjà entièrement consommée par une émission antérieure — rejet correct par `create_credit_issuance()`. La capacité est suivie cumulativement au niveau de la chaîne/session de vérification, conformément à la migration 07, et non indépendamment par émission. Corrigé en créant une `verification_session` dédiée ainsi qu'un `verification_outcome` dédié pour ce scénario.
4. **Override extrême non révoqué, contaminant un scénario ultérieur.** Un override délibérément invalide (`reserve_pct=95`, destiné à tester le rejet d'un dépassement de borne) restait actif après son propre test et faisait échouer un scénario positif plus tardif réutilisant la même organisation — rejeté par `compute_credit_sale_allocations()`. Corrigé en ajoutant la révocation explicite (flux à triple approbation) de cet override immédiatement après son test.

*Huit échecs d'assertion découverts lors d'une seule tentative complète (la cinquième — le script s'est exécuté jusqu'au bout, mais le bloc de synthèse final a compté 8 échecs sur 196), regroupés en quatre causes racines supplémentaires (points 5 à 8), toutes corrigées ensemble avant la sixième et dernière tentative :*
5. Cinq attentes de message d'erreur devenues périmées (`B100`, `B102`, `B103`, `B113`, `B116`) — le texte exact du message levé par les triggers de gouvernance avait évolué au fil des revues statiques successives sans que les fragments attendus dans le harnais soient mis à jour en conséquence ; les rejets eux-mêmes étaient corrects. Corrigé en alignant chaque fragment attendu sur le message réellement levé.
6. **`B128`** utilisait une valeur de test (`platform_fee_pct=99,00`) qui violait la contrainte économique ordinaire `fee+reserve<=100` dès l'`INSERT`, avant même d'atteindre le contrôle différé réellement visé (concordance proposition/règle activée). Corrigé avec une valeur divergente (`21,00`) respectant les bornes ordinaires, isolant l'invariant réellement testé.
7. **`B129`** : le vrai défaut se trouvait dans un test antérieur (`B_9e_1`), qui forçait un contrôle différé (`SET CONSTRAINTS ... IMMEDIATE`) sans jamais le réinitialiser en `DEFERRED` ensuite — seule occurrence du fichier à violer ce patron, pourtant systématiquement respecté ailleurs. Le mode `IMMEDIATE` restait actif pour le reste de la transaction, faisant échouer le contrôle différé de `B129` dès l'`INSERT` de sa fixture (avant l'activation de la proposition), plutôt qu'au moment volontairement testé. Corrigé en réinitialisant `DEFERRED` immédiatement après le test qui force `IMMEDIATE`.
8. **`B62` et commentaire `B64`.** `B58` remplace légitimement la règle générale du regroupement de 10 %/5 % à 9 %/4 %. `B62` attendait encore `fee_applied_pct=10,00` et a été corrigé à `9,00`. `B64`, qui n'était pas une assertion en échec, contenait encore le commentaire explicatif « 10 + 95 = 105 » ; il a été réconcilié avec l'état réel « 9 + 95 = 104 ». Aucun scénario métier n'a été modifié.

**Aucune ligne de `09_carbon_sales_financial_model.sql` n'a été modifiée à aucun moment de GATE 3** — toutes les corrections ci-dessus sont strictement internes à `09_test_carbon_sales_financial_model.sql`. Chaque correction a été prouvée mécaniquement avant toute nouvelle tentative (diff exact, MD5/lignes/octets avant et après, recomptage des assertions A/B/B assert_raises et du total contre `v_expected`, absence de libellé dupliqué, validation `pglast` de la syntaxe SQL et de chaque bloc PL/pgSQL, structure transactionnelle à 1 `BEGIN`/1 `ROLLBACK`/0 `COMMIT`).

**Version finale validée et exécutée du harnais :** `09_test_carbon_sales_financial_model.sql`, MD5 `3c56a33b60f21df07fadca3ddfecac54`, 3081 lignes, 235716 octets — 196 assertions (37 A directes + 98 B directes + 61 B assert_raises), `v_expected=196`, 0 doublon de libellé, `parse_sql` 87 instructions top-niveau, `parse_plpgsql` 56/56 blocs `DO` valides.

**Empreinte de la migration elle-même :** `09_carbon_sales_financial_model.sql`, MD5 `c78dea31a7d1ac977ebf071aba9dab12`, 4224 lignes, 278430 octets — calculée mécaniquement sur le fichier présent dans l'arbre de travail et destiné à être committé dans ce même lot, identique à celui appliqué au GATE 1. **Le fichier de migration est demeuré inchangé entre GATE 1 et la validation finale GATE 3** : aucun outil d'édition n'a été utilisé sur `09_carbon_sales_financial_model.sql` à aucun moment durant GATE 3 (confirmé par l'historique des opérations de cette session, le fichier n'ayant par ailleurs jamais été commité auparavant — premier commit du fichier de migration lui-même) ; seules les fixtures et attentes du harnais transactionnel (`09_test_carbon_sales_financial_model.sql`) ont été corrigées.

**Sur le placement hors de `supabase/migrations/` :** `supabase/carbon_migrations_proposed/` demeure hors de `supabase/migrations/` et de l'historique automatisé `schema_migrations`. Ce placement ne signifie pas que 09 est non appliquée : 09 a été appliquée manuellement en production et validée selon les GATES documentés ci-dessus. Un outil qui n'inspecterait que `schema_migrations` ou le dossier `supabase/migrations/` ne le verrait pas — seul ce document (et une lecture directe du schéma réel) en fait foi, exactement comme pour 01/02+03/06+06a/04/05/07/08 (voir §12-§16).

**Résultat GATE 3 : 196 assertions exécutées, 196 réussies, 0 échec, 0 doublon, `ROLLBACK` final exécuté.** Vérification read-only post-exécution : 0 ligne résiduelle sur les tables de test (préfixes `TEST-09`/UUID de test), 0 transaction active ou `idle in transaction` résiduelle sur `pg_stat_activity`.

**Ce que GATE 3 valide, et ce qu'il ne valide pas :**
- ✅ Modèle financier fonctionnel (attribution, répartition, frais/réserve, TRUNC non négatif).
- ✅ Sécurité/RLS et gouvernance des approbations (triple/double approbation, atomicité, immuabilité, provenance).
- ✅ Workflow transactionnel à connexion unique (invariants différés, garde-fous de capacité, bornes économiques).
- ⏳ **Concurrence réelle à connexions multiples : non validée.** Le protocole séparé `09_test_carbon_sales_financial_model_concurrency_STAGING_ONLY.sql` (marqué `STAGING_ONLY` / `NEVER_PRODUCTION`) reste un gate distinct, non exécuté, et **ne doit jamais être exécuté contre la base de production**. Sa validation nécessite un environnement Supabase dédié reproduisant suffisamment la structure de production, encore à mettre en place — décision séparée, hors périmètre de la validation fonctionnelle actuelle.

**État après GATE 3 : les migrations 01, 02, 03, 04, 05, 06, 06a, 07, 08 et 09 de la Tranche 0 carbone sont toutes appliquées en production et ont franchi leurs validations fonctionnelles documentées.** Pour 09, la validation transactionnelle GATE 3 est clôturée à 196/196 ; la validation de concurrence `STAGING_ONLY` reste distincte, non exécutée et hors du périmètre de cette validation production. La validation de concurrence `STAGING_ONLY` demeure la seule validation technique séparée encore ouverte avant clôture complète de la Tranche 0 carbone.

---

## 19. Validation de concurrence STAGING — clone R4 contaminé après diagnostic dblink, décision de passer à un clone R5 vierge (27 juillet 2026)

**Contexte :** après la clôture de GATE 3 (§18), la validation de concurrence réelle du harnais `09_test_carbon_sales_financial_model_concurrency_STAGING_ONLY.sql` a été poursuivie sur une série de clones Supabase jetables dédiés (R2, R3, R4 — R2 et R3 abandonnés/gelés comme artefacts forensiques antérieurs, jamais nettoyés ni réutilisés). Sur R4, les 66 migrations base + les 9 migrations carbone (01-09, y compris 07 et 09 via `psql --file` utilisateur, jamais via les outils MCP) ont été appliquées avec succès, `dblink` 1.2 activé, et 4 identités synthétiques `t09-a/b/c/d` créées en ordre chronologique strict — checkpoint final confirmé conforme avant tout GO sur le harnais.

**Diagnostic d'authentification `dblink` (résumé) :** la première exécution réelle du harnais sur R4 a révélé que les 14 `dblink_connect()` du fichier original (connexion locale implicite, `dbname=current_database()` sans `host=`) échouaient systématiquement avec `password or GSSAPI delegated credentials required`. Diagnostic mené par une série de probes ciblés, sans fixture ni mutation métier :
- **Probe A/B** (persistance de session, aucun secret) : `pg_backend_pid()` identique sur 3 instructions séparées, `set_config()`/`current_setting()` persistants — écarte l'hypothèse d'un pooling en mode transaction.
- **Probe D** (`host=127.0.0.1` explicite) : échec identique — écarte l'hypothèse d'un socket local mal ciblé.
- **Probe E** (`password_required=false`) : rejeté silencieusement — confirme que le rôle `postgres` de Supabase n'est pas un vrai superuser Postgres et ne peut pas invoquer cette échappatoire de `dblink_security_check()`.
- **Probe F** (`dblink` ciblant le pooler externe Supavisor, `host=aws-0-ca-central-1.pooler.supabase.com port=5432 user=postgres.<ref> sslmode=require` — le même chemin que la session `psql` elle-même) : **succès complet**, authentification SCRAM réelle confirmée.

**Correctif retenu (copie de travail v3, fichier original figé jamais modifié) :** les 14 `dblink_connect()` ciblent désormais le pooler externe (mécanisme validé par le Probe F), les identifiants sont injectés une seule fois en top-level via `\getenv`/`set_config()` (jamais à l'intérieur d'un bloc `DO $$...$$`, où l'interpolation psql ne s'applique pas — cause de l'abandon d'une première tentative de correctif, v1, jamais exécutée), et le retour de `set_config()` est explicitement transformé en booléen (`... IS NOT NULL AS dblink_password_loaded`) pour ne jamais faire apparaître le secret dans la sortie `psql` — correction apportée après qu'une fuite réelle du mot de passe R4 dans la sortie `psql`/le chat a effectivement eu lieu lors du diagnostic (mot de passe aussitôt tourné par l'utilisateur dans les Database Settings Supabase). Version finale : `09_test_carbon_sales_financial_model_concurrency_STAGING_ONLY_R4_dblinkauth_v3.sql`, MD5 `62fa5c29b36284c1e79681aaa855ed3a`, 2615 lignes, 177341 octets, 26/26 blocs `DO`, `v_expected=72`, `parse_sql` 81 instructions top-niveau valides (pglast, substitution psql simulée).

**Échec de la première exécution réelle de la v3 sur R4 :** `ERROR: duplicate key value violates unique constraint "organizations_pkey"` — `DÉTAIL: Key (id)=(33333333-3333-3333-3333-c00000000001) already exists.` (ligne 331, premier `INSERT INTO organizations` des fixtures du harnais). **Diagnostic : ce n'est pas un défaut du harnais ni de la migration 09.** Les tentatives précédentes (v1 jamais exécutée ; v2 exécutée réellement mais interrompue par l'échec `dblink_connect` après avoir déjà committé ses fixtures initiales, le harnais étant explicitement non auto-nettoyant par conception) ont laissé R4 dans un état non vierge — les fixtures des tentatives antérieures sont restées committées, entrant en conflit avec les nouveaux `INSERT` de la v3. **La v3 ne constitue donc pas une exécution réelle des 72 assertions de concurrence** — l'échec se produit avant même d'atteindre le premier scénario testé.

**Décision :** ne pas nettoyer R4 en place (un nettoyage manuel de fixtures métier + événements append-only + identités Auth ne pourrait pas démontrer une équivalence fiable à un clone neuf — contraire à l'objectif même du test de concurrence). R4 est gelé tel quel, non modifié davantage, comme artefact forensique de ce diagnostic — même discipline que R2/R3. La copie v3 du harnais (MD5 `62fa5c29b36284c1e79681aaa855ed3a`) est figée sans autre modification. Un nouveau clone **R5** (`METALVISION-STAGING-CONCURRENCY-09-R5`) est construit en rejouant strictement le même manifest déjà maîtrisé (01-22 APPLY / 23-45 SKIP / 46-47 APPLY / 48 SKIP / 49-66 APPLY, carbone 01-06/06a, 07, pré-08, 08, 09, `dblink` 1.2, 4 identités `t09-a/b/c/d`), avec un checkpoint court avant tout lancement (absence de fixtures du harnais, 4 profils synthétiques seulement, migrations conformes, `dblink` actif, MD5 v3 inchangé), et **sans aucun essai intermédiaire du harnais** — la première exécution du fichier sur R5 doit être directement la v3 finale, après un nouveau GO explicite.

---

## 20. Clôture technique — Migration 09 et validation de concurrence réelle (30 juillet 2026)

**Contexte :** suite à §19 (clone R4 contaminé), la validation de concurrence réelle du harnais `09_test_carbon_sales_financial_model_concurrency_STAGING_ONLY_R4_dblinkauth_v3.sql` s'est poursuivie sur une série de clones jetables supplémentaires (R5 à R8), chacun ayant révélé puis fait corriger un défaut structurel du harnais lui-même (auto-interblocages locaux des scénarios L et M ; puis, sur R8, une fixture de preuve documentaire mal ciblée pour le scénario F et un second auto-interblocage sur le scénario N) — jamais un défaut de la logique de production des migrations 07, 08 ou 09. Chaque clone a été gelé après usage, jamais nettoyé ni réexécuté, conformément à la discipline déjà établie en §19. R9 est le neuvième et dernier de cette série, explicitement désigné comme la dernière reconstruction complète autorisée avant cette clôture.

**1. Environnement de validation final**
Projet staging jetable : `METALVISION-STAGING-CONCURRENCY-09-R9`
Supabase project ref : `btnpimklwvrgtofognfu`
Aucune donnée de production copiée. Aucune exécution du harnais sur production.

**2. État des migrations**
Manifest base (42 fichiers, 01-22 APPLY / 23-45 SKIP / 46-47 APPLY / 48 SKIP / 49-66 APPLY) et carbone 01-09 reconstruit conformément au parcours déjà validé sur les environnements précédents (R5 à R8). Migration 09 inchangée depuis son application production (§18) :
`09_carbon_sales_financial_model.sql` — MD5 `c78dea31a7d1ac977ebf071aba9dab12`, 4224 lignes, 278430 octets.
La validation de concurrence n'a nécessité aucune modification de la migration 09 ni des migrations 07/08 — seul le harnais de test lui-même (fichier `..._concurrency_STAGING_ONLY_R4_dblinkauth_v3.sql`) a été corrigé, au fil de R6 (scénario L), R7 (scénario M) et R8 (scénarios F et N).

**3. Harnais final validé**
Fichier : `09_test_carbon_sales_financial_model_concurrency_STAGING_ONLY_R4_dblinkauth_v3.sql`
MD5 : `7f1f0e07f458eb6968f81f025989e114`
Caractéristiques : 2909 lignes, 195738 octets, 34 blocs `DO` top-level, 89 statements top-level, `parse_plpgsql` 38/38, `v_expected=72`, 15 connexions `dblink`. Connexions `dblink` vers le pooler externe Supabase (Supavisor) en mode session, authentification SCRAM réelle, identifiants injectés au lancement via variables d'environnement, jamais stockés en clair dans le SQL ni affichés dans la sortie `psql`.

**4. Résultat final R9**
Exécution unique via `psql` en autocommit réel (aucun `BEGIN` externe ajouté, `ON_ERROR_STOP` actif) : **72/72 assertions, 0 échec, 0 doublon, code de sortie psql 0.** Toutes les sections B à N validées. Les scénarios L, M et N démontrent les comportements sous contention réelle au moyen de connexions PostgreSQL physiquement distinctes (locale + `dblink` vers le pooler externe). `M6bis` confirme explicitement que le blocage observé est un véritable conflit de verrou (message de verrouillage/timeout) et non un contournement d'autorisation préalable — la preuve que l'admin réel de l'opérateur candidat franchit bien l'autorisation avant de se heurter au verrou `platform_operators`.

**5. Contrôle post-exécution**
Sur R9 uniquement (requête read-only ciblée sur `pg_stat_activity`, filtrée sur toute trace `dblink`/`carbon_test09c`/`confirm_credit_sale`/état `idle in transaction`) : 0 connexion `dblink` résiduelle, 0 session `idle in transaction` liée au harnais, aucune autre base touchée, production jamais touchée. Les fixtures du harnais demeurent dans R9 par conception, jusqu'à la suppression de cet environnement jetable.

**6. Conclusion de décision**
La migration 09 et la Tranche 0 carbone sont techniquement closes. Sont validés par l'ensemble GATE 1/GATE 2/GATE 3 (§18, connexion unique) et R2-R9 (§19-§20, connexions multiples réelles) :
- modèle financier des ventes ;
- réservation et consommation concurrentes des lots ;
- gouvernance des règles de distribution ;
- gouvernance des overrides membres ;
- confirmation concurrente des ventes ;
- ajout concurrent des coûts ;
- changement d'opérateur sous contention ;
- verrouillage cohérent entre `join_aggregator()`, `confirm_credit_sale()` et `designate_platform_operator()` ;
- absence de contournement des autorisations lors des conflits.

**Aucun R10 n'est requis.** La prochaine phase n'est plus une phase de fondation SQL : le travail doit passer aux workflows produit, API et interfaces utilisateur.

**7. Traçabilité**
Nouveau commit de clôture concurrence créé séparément. Le commit historique `6b3956d` n'est pas amendé. La migration `09_carbon_sales_financial_model.sql` n'est pas modifiée.

---

## 21. Clôture fonctionnelle Lot 1 — Cockpit inventaire carbone (31 juillet 2026)

**Contexte :** suite à la clôture technique de la Tranche 0 carbone (§18-§20), le travail est passé aux workflows produit/interface. Le Lot 1 (« plus petite tranche verticale ») couvre l'enchaînement `verification_outcomes → credit_issuances → credit_issuance_sources → credit_lots` côté opérateur, plus l'audit et la correction de `/admin-verification-sessions` côté MRV — préalable explicitement exigé avant tout test de bout en bout. Aucune migration existante n'a été modifiée pour ce lot ; toute la logique métier (transitions FSM, calculs, autorisations) reste portée par les RPC PostgreSQL des migrations 05/07/08 déjà closes.

**1. Interfaces livrées**
- `/admin/carbon-inventory` (nouvelle page) : cockpit opérateur — résultats de vérification admissibles, création/progression d'émission, enregistrement registre, création de lots, statuts de cycle de vie, annulation/rejet externes avec sélection de document de preuve.
- `/admin-verification-sessions` (réécriture complète) : élimination des écritures directes bypassant les RPC de la migration 05 ; planification (`plan_verification_session`) avec assignation d'un vérificateur accrédité et période de rapport ; complétion (`complete_verification_session`) avec sélection de la preuve `evidence_files` et gestion explicite de la supersession.

Quatre rondes de revue statique ont précédé le test réel (matrice d'actions FSM-exacte, gestion d'erreur SELECT explicite, filtrage adhésion/mandat exact, remplacement de la saisie manuelle de `document_id` par un sélecteur, correction de fuseau horaire sur les champs date/datetime-local dupliquée deux fois — `registry_issued_at` puis `reporting_period_start/end` affichés via `fmtDate()`).

**2. Compte rendu du test de bout en bout (31 juillet 2026, production METALVISION, ref `dlbewgsoboaycbpypcus`)**
Comptes/rôles utilisés :
- `centredelasante@gmail.com` (superadmin plateforme) : création de session, planification, rôle opérateur carbone (ajouté comme membre `admin` de l'organisation opératrice MINOVIA — prérequis découvert en cours de test, `organization_members` était vide pour cette organisation).
- `verifier@metaltrace.ca` (vérificateur accrédité, ajouté à `accredited_verifiers`) : complétion et supersession de la vérification, restreint par `auth.uid() = verifier_user_id` côté serveur.

Prérequis de données absents de toute interface existante et créés directement en base pour permettre le test (aucun UI ne couvre encore ce domaine) : `accredited_verifiers`, `aggregators`, `aggregator_memberships`, `carbon_commercialization_mandates`, un `operational_units` rattaché au projet de test (voie MRV de `carbon_is_source_organization_valid()`), `organization_members` pour l'opérateur, une ligne `evidence_files` de type `verification_report`. Un profil `profiles` manquant pour `verifier@metaltrace.ca` a également été réparé (le trigger `on_auth_user_created_profile` avait été ajouté après la création de ce compte).

Six scénarios validés en conditions réelles :
1. **Cycle principal** — session de vérification planifiée → en cours → complétée (résultat actif, 90 tCO2e admissible) → émission créée → admissible → soumise au registre → émise (registre, 50 tCO2e) → lot créé (disponible, 50 tCO2e, reliquat 0).
2. **Annulation externe avec cascade** — `record_external_cancellation` sur l'émission émise (registre) fait passer l'émission à `externally_cancelled` **et** voide automatiquement le lot associé (`voided`, cause `external_cancellation`) via le trigger de cascade, sans action manuelle sur le lot.
3. **Annulation interne d'une émission admissible** — `void_credit_issuance` depuis le statut `internal`, motif conservé et affiché.
4. **Rejet externe d'une émission soumise** — `record_externally_rejected` depuis `submitted`, bloqué correctement à ce stade (aucun lot, aucune émission registre).
5. **Supersession contrôlée d'un résultat de vérification** — `complete_verification_session` réappelée sur une session déjà complétée : l'ancien résultat passe à `superseded`, le nouveau devient `active` et référence son prédécesseur via `supersedes_outcome_id`, motif d'ajustement obligatoire respecté.
6. **Annulation directe d'un lot disponible** — `void_credit_lot` (cause `internal_correction`) : seul le lot passe à `voided`, l'émission parente reste `issued`, confirmant la distinction avec le scénario 2 (cascade externe, qui transitionne les deux).

Un bug réel a été détecté et corrigé pendant le test (hors du périmètre des revues statiques précédentes) : embed PostgREST ambigu sur `accredited_verifiers.select('user_id, profiles(...)')` — deux FK vers `profiles` (`user_id` et `accredited_by`) empêchaient PostgREST de résoudre la relation implicite. Corrigé par un hint de contrainte explicite (`profiles!accredited_verifiers_user_id_fkey(...)`).

**3. Identifiants des objets de test**
Aucun nettoyage effectué — les IDs sont documentés ici pour suppression ultérieure si souhaité (l'organisation opératrice MINOVIA et son adhésion `organization_members` restent probablement nécessaires aux tests du Lot 2) :
- Projet MRV : `projects.id = cae4ca66-af0f-4545-b7cf-2773357cb26a` (« Projet Test E2E »)
- Session de vérification : `verification_sessions.id = e5d5f6e2-eee2-4540-865a-eae676b6b6c3`
- Résultats de vérification : `3394d2f3-5961-4dc6-bfe8-ae90d7443b3a` (superseded, 90 tCO2e) → `56af5bdc-799a-4d10-8eb8-a91cc06563a0` (active, 85 tCO2e)
- Émissions : `cdc1a6b5-821c-4d55-a9e0-c74dd9b12c42` (externally_cancelled, 50 tCO2e), `05c03b2b-49fe-4b98-83fb-2236bf784001` (voided, 10 tCO2e), `bdf539ea-a2f1-4367-b08c-8ca702c35923` (externally_rejected, 10 tCO2e), `13f2de13-588f-4bdd-a1f0-f1ddf70f33e6` (issued, 10 tCO2e)
- Lots : `e0fdb575-0ea2-49dd-9f96-2404a642a8ab` (voided/external_cancellation), `4a63de04-c339-427a-a74e-62c9cdca92b2` (voided/internal_correction)
- Regroupement/adhésion/mandat de test : `aggregators.id = 11111111-1111-1111-1111-111111111111`, `aggregator_memberships.id = 22222222-2222-2222-2222-222222222222` (Acier Laurentien Inc.)
- `operational_units.id = 33333333-3333-3333-3333-333333333333` (rattaché au projet de test)
- Document de preuve : `documents.id = 091e40d4-9b77-4d5d-abf9-4e8041f41c5f`

**4. Migrations**
**Aucune migration existante n'a été modifiée.** Toutes les transitions d'état, validations de capacité et calculs sont restés portés par les RPC des migrations 05/07/08, appelées telles quelles depuis le frontend.

**5. Commits frontend**
- `e6e8223` — Lot 1 : cockpit inventaire carbone + correctifs `/admin-verification-sessions`
- `7077c5c` — Fix hint FK explicite `profiles!accredited_verifiers_user_id_fkey` (embed ambigu, détecté pendant le test)
- `fc0ef12` — Fix décalage UTC/local d'un jour sur `fmtDate()` pour les champs date (période de rapport)

**6. Conclusion**
Le vertical slice du Lot 1 est validé en production sur les six parcours ci-dessus. Backend (migrations 05/07/08), interface sessions de vérification, interface inventaire carbone, RPC et garde-fous FSM, et parcours multi-rôles sont tous confirmés en conditions réelles. Aucun blocage fonctionnel restant. Prochaine tranche logique : Lot 2 — gouvernance des règles de distribution et des overrides, livré depuis à `/admin/regroupements/[aggregatorId]/distribution` (voir §22) — le cockpit de ventes devient Lot 3 (`/admin/carbon-sales`).

---

## 22. Clôture fonctionnelle Lot 2 — Gouvernance distribution et overrides (31 juillet 2026)

**Contexte :** suite à la clôture du Lot 1 (§21), le Lot 2 couvre les deux workflows de gouvernance économique de migration 09 restés jusqu'ici non exposés en interface : `distribution_rules`/`distribution_rule_proposals` (double approbation) et `member_distribution_overrides`/`member_distribution_override_proposals` (triple approbation, trois types de proposition `create`/`replace`/`revoke`). Décision explicite de l'utilisateur en amont de la construction : route `/admin/regroupements/[aggregatorId]/distribution` (plutôt qu'un onglet du futur cockpit de ventes), et désignation préalable d'un vrai `primary_admin` de test avant tout code, la présence de cette identité conditionnant directement la visibilité des actions testables.

**1. Interface livrée**
- `/admin/regroupements/[aggregatorId]/distribution` (nouvelle page) : section « Règle de distribution » (règle active, proposition en attente avec statut des deux approbations, actions Approuver/Rejeter/Retirer selon rôle réel, historique) et section « Overrides membres » (par adhésion : overrides actifs, proposition en attente avec statut des trois approbations, mêmes actions, historique). Détection de rôle côté client à des fins d'affichage uniquement (`aggregator_admins`, `organization_members`, `app_metadata.role`) — le serveur RPC revalide systématiquement, aucune autorisation métier n'est dupliquée côté React.
- Lien ajouté au hub `/admin`, pointant directement sur le regroupement de test (pas de sélecteur global d'agrégateur, conformément à la décision utilisateur).

**2. Bug RLS réel trouvé et corrigé pendant le test**
La table `organizations` n'avait que deux policies SELECT (`organizations_project_participant_select`, issue du domaine CCF, et `organizations_superadmin_all`) — aucune ne couvrait le cas « je suis admin d'un regroupement carbone / operator_admin et je dois lire le nom des organisations membres de mon regroupement ». RLS filtrait silencieusement (aucune erreur PostgREST), le nom retombait sur l'UUID brut côté frontend. Corrigé par une migration additive dédiée, sans toucher aux deux policies existantes :
`supabase/carbon_migrations_proposed/10_carbon_organizations_governance_visibility.sql` — nouvelle policy `organizations_aggregator_governance_select`, portée à `is_aggregator_admin(am.aggregator_id) OR is_platform_operator_admin(operateur actif)` via jointure `aggregator_memberships`, sans filtre `ended_at` (cohérent avec `aggregator_memberships_admin_select` de la migration 02). Appliquée directement en production après confirmation explicite de l'utilisateur.

**3. Compte rendu du test de bout en bout (31 juillet 2026, production METALVISION, ref `dlbewgsoboaycbpypcus`)**
Comptes/rôles utilisés :
- `jean@hotmail.com` — `primary_admin` de « Regroupement Test E2E » (`aggregator_admins.id = d35a3324-b1bd-48a9-8dbc-d1cec7517d4f`, désigné par le superadmin le 31 juillet 2026, rôle de test **temporaire**). Mot de passe réinitialisé pour les besoins du test (compte existant depuis le 21 juillet 2026, jamais utilisé) ; non consigné ici.
- `claudefairplay@hotmail.com` — promu `org_role='admin'` d'Acier Laurentien Inc. (`organization_members.id = 9461a20e-fc9c-4721-ba2a-b8f7b6b38fca`, précédemment `membre`) pour couvrir le rôle `organization_admin` des overrides.
- `centredelasante@gmail.com` — superadmin plateforme, déjà admin actif de l'organisation opératrice METALTRACE (`organization_members.id = 2d98c7bd-112e-49d7-b3e0-1efc999c9e4d`) : couvre à la fois `operator_admin` et la dérogation superadmin.

Huit scénarios validés en conditions réelles, chacun revérifié par requête SQL directe après action UI (jamais la capture d'écran seule) :
1. **Règle de distribution — proposition et double approbation** — `propose_distribution_rule` (frais 10 %, réserve 5 %, pondération 1) → `distribution_rule_proposals.id = 69860101-...` (`pending`, deux approbations `null`) → approbation regroupement (jean) → toujours `pending` → approbation opérateur (centredelasante) → `activated`, `distribution_rules.id = deae125d-...` créée avec `effective_from` généré serveur à l'instant exact de la 2ᵉ approbation, lien bidirectionnel `activated_distribution_rule_id` ↔ `proposal_id` confirmé.
2. **Override membre — création (triple approbation)** — `propose_member_distribution_override('create', ...)` (fee_pct 8 %) → `member_distribution_override_proposals.id = d892452b-...` → approbations org. membre (claudefairplay) + opérateur (centredelasante) + regroupement (jean, dernière) → `activated`, `member_distribution_overrides.id = 1b47696d-...` créé ; `created_by` de l'override = `proposed_by` de la proposition (provenance conforme au point 2 de la huitième revue statique de migration 09, §17 9bis).
3. **Rejet d'une proposition de règle** — nouvelle proposition (12 %/6 %/1) rejetée par l'opérateur (centredelasante) **avant toute approbation**, motif obligatoire fourni (« Test de rejet E2E ») → `distribution_rule_proposals.id = 8237eb9f-...`, `status='rejected'`, `rejected_by`/`rejected_at`/`reject_reason` renseignés, `activated_distribution_rule_id` reste `null`, règle active inchangée.
4. **Retrait par l'auteur** — nouvelle proposition (6 %/9 %/1) retirée immédiatement par son auteur (jean) → `distribution_rule_proposals.id = 04171e27-...`, `status='withdrawn'`, aucune approbation, aucun rejet, aucune activation.
5. **Override membre — remplacement** — `propose_member_distribution_override('replace', target_override_id=1b47696d-..., fee_pct=6%, ...)` → `member_distribution_override_proposals.id = 55657262-...` → triple approbation → `activated`. Vérification de l'alignement `tstzrange` exact conçu en migration 09 : `1b47696d-...revoked_at` = `f8e1b1c6-...created_at` = `2026-08-01 00:11:02.491002+00` **au microseconde près**, aucun chevauchement ni trou de couverture.
6. **Override membre — révocation pure** — `propose_member_distribution_override('revoke', target_override_id=f8e1b1c6-..., revoke_reason=...)` → `member_distribution_override_proposals.id = 1bec6e02-...` → triple approbation → `activated`, `activated_override_id` pointe vers l'override ciblé lui-même (aucune nouvelle ligne, cohérent avec un `revoke` pur) ; `f8e1b1c6-...` porte désormais `revoked_at`/`revoked_by`/`revocation_proposal_id` renseignés. Plus aucun override actif pour Acier Laurentien Inc. à l'issue du test.
7. **Override membre — rejet d'une proposition** (`reject_member_distribution_override_proposal`, chemin override distinct du chemin règle testé au scénario 3) — nouvelle proposition `create` (reserve_pct 4 %, jean) rejetée par l'opérateur (centredelasante) **avant toute approbation**, motif obligatoire fourni (« Test rejet override E2E ») → `member_distribution_override_proposals.id = 87e4d5a9-ac28-46f5-9890-d88a9d569e87`, `status='rejected'`, `rejected_by`/`rejected_at`/`reject_reason` renseignés, `activated_override_id` reste `null`.
8. **Override membre — retrait par l'auteur** (`withdraw_member_distribution_override_proposal`, chemin override distinct du chemin règle testé au scénario 4) — nouvelle proposition `create` (fee_pct 7 %, centredelasante) retirée immédiatement par son auteur → `member_distribution_override_proposals.id = cd992900-9e53-4af9-980a-e86dc51db728`, `status='withdrawn'`, aucune approbation, aucun rejet, aucune activation.

**4. Identifiants des objets de test**
Aucun nettoyage effectué (les comptes/adhésions restent probablement nécessaires au Lot 3) :
- Désignation primary_admin : `aggregator_admins.id = d35a3324-b1bd-48a9-8dbc-d1cec7517d4f`
- Promotion organization_admin : `organization_members.id = 9461a20e-fc9c-4721-ba2a-b8f7b6b38fca`
- Propositions de règle : `69860101-7bf8-4226-8d63-64653fd9b4cb` (activated), `8237eb9f-f836-4db0-8b3f-7ef9129684a8` (rejected), `04171e27-1dc6-4fe0-b378-6c9ec80fba94` (withdrawn)
- Règle active : `distribution_rules.id = deae125d-d241-439b-9b88-d368f97604f7` (10 %/5 %/1)
- Propositions d'override : `d892452b-ebd9-45e3-9519-d883bb035bac` (create, activated), `55657262-57e0-4407-8a9c-f22baca51d54` (replace, activated), `1bec6e02-b3a8-40c2-8c0d-f14c52024ed0` (revoke, activated), `87e4d5a9-ac28-46f5-9890-d88a9d569e87` (create, rejected), `cd992900-9e53-4af9-980a-e86dc51db728` (create, withdrawn)
- Overrides : `1b47696d-6c25-476a-816a-b161098d75a9` (créé puis révoqué via replace), `f8e1b1c6-7683-4b12-ab68-cd030eeee50b` (créé via replace, révoqué via revoke)

**5. Migrations**
**Aucune migration existante (01-09) n'a été modifiée.** Une seule migration additive a été rédigée et appliquée : `10_carbon_organizations_governance_visibility.sql` (nouvelle policy RLS SELECT sur `organizations`, cf. point 2). Toutes les transitions d'état, calculs et autorisations métier restent portés par les RPC de la migration 09, appelées telles quelles depuis le frontend.

**6. Commit frontend**
- `b6d7b36` — Lot 2 : gouvernance distribution_rules + member_distribution_overrides (page + lien hub `/admin`)

**7. Conclusion**
Le vertical slice du Lot 2 est validé en production sur les huit scénarios ci-dessus, couvrant l'intégralité de la matrice d'actions des deux workflows de migration 09 : pour les règles de distribution, double approbation, rejet et retrait ; pour les overrides membres, triple approbation sur les trois types de proposition (`create`/`replace`/`revoke`), **plus** rejet et retrait testés spécifiquement sur le chemin override (`reject_member_distribution_override_proposal`, `withdraw_member_distribution_override_proposal` — RPC distinctes de leurs équivalents règle, scénarios 7-8). Un bug RLS réel (visibilité `organizations`) a été détecté et corrigé pendant le test, hors du périmètre des revues statiques de migration 09 — confirmant à nouveau la valeur du test de bout en bout en conditions réelles. Aucun blocage fonctionnel restant. Prochaine tranche logique : Lot 3 — cockpit de ventes (`/admin/carbon-sales`), qui pourra afficher la gouvernance applicable à une vente sans jamais devenir le lieu d'administration de cette gouvernance.

---

## 23. Clôture fonctionnelle Lot 3 — Cockpit de ventes (31 juillet 2026)

**Contexte :** suite à la clôture du Lot 2 (§22), le Lot 3 couvre le cycle de vie complet d'une vente de crédits carbone (`credit_sales`/`credit_sale_lots`/`credit_sale_costs`/`credit_sale_allocations`, migration 09) : `create_credit_sale` → `add_credit_sale_lot`/`release_credit_sale_lot` → `add_credit_sale_cost`/`add_credit_sale_adjustment` → `confirm_credit_sale` (déclenche `compute_credit_sale_allocations`) → `settle_credit_sale`/`cancel_credit_sale`. Décision d'architecture confirmée par lecture directe des RPC avant construction (jamais supposée) : `seller_organization_id` doit obligatoirement être l'organisation opératrice METALTRACE active — `add_credit_sale_lot`, `add_credit_sale_cost`, `confirm_credit_sale`, `release_credit_sale_lot` et `cancel_credit_sale` vérifient tous explicitement `is_platform_operator(seller_organization_id)`. Un membre individuel (ex. Acier Laurentien Inc., vendeur envisagé initialement) échouerait dès le premier `add_credit_sale_lot`.

**1. Interface livrée**
- `/admin/carbon-sales` (nouvelle page) : liste des ventes filtrable par statut, création de vente (vendeur = opérateur actif, fixé, non modifiable en UI), panneau détail par vente avec ajout/libération de lot, ajout de coûts typés, confirmation, règlement, annulation, et affichage en lecture seule de la répartition calculée serveur (`credit_sale_allocations`).
- Lien ajouté au hub `/admin`.

**2. Bug réel trouvé et corrigé pendant le test (migration 11)**
`compute_credit_sale_allocations()` (migration 09) contient une instruction `UPDATE _c09_pairs SET gross_amount = ... ;` volontairement sans clause `WHERE` (doit toucher toutes les lignes de la table temporaire de travail). Cette instruction est sémantiquement correcte et s'exécute sans erreur via une connexion directe (confirmé par exécution diagnostique en transaction annulée via le connecteur MCP Supabase), mais échoue systématiquement via tout appel RPC réel (PostgREST, donc depuis le navigateur) avec l'erreur « UPDATE requires a WHERE clause ». Cause racine identifiée : le rôle `authenticator` (celui que PostgREST utilise pour toute requête HTTP réelle) charge `session_preload_libraries=supautils, safeupdate` (confirmé via `pg_db_role_setting`) — l'extension pg-safeupdate, activée par défaut sur les projets Supabase, interdit tout `UPDATE`/`DELETE` sans `WHERE`, y compris à l'intérieur d'une fonction `SECURITY DEFINER`, y compris sur une table temporaire locale à l'appel. Ni le harnais transactionnel de 09 (GATE 3, `psql --file`, §18) ni les 72 scénarios de concurrence réelle (R9, via `dblink`) ne passent par le rôle `authenticator` — seul un test de bout en bout via l'interface web pouvait révéler ce comportement.
Corrigé par `supabase/carbon_migrations_proposed/11_carbon_sales_compute_allocations_safeupdate_fix.sql` : `CREATE OR REPLACE FUNCTION compute_credit_sale_allocations(...)`, copie exacte de la version de production à une seule ligne près (`WHERE true` ajouté à l'unique `UPDATE` sans clause). Diff mécanique (Python `difflib`, lignes de code hors commentaires/blancs) confirmé avant application : 219/219 lignes identiques sauf celle-ci. Audit complémentaire : c'est la seule instruction `UPDATE` sans `WHERE` dans l'ensemble des fonctions du domaine ventes (`add_credit_sale_lot`, `confirm_credit_sale`, `cancel_credit_sale`, `release_credit_sale_lot`, `settle_credit_sale`, `add_credit_sale_cost`, `add_credit_sale_adjustment`, `create_credit_sale` portent toutes des `WHERE` explicites). Appliquée directement en production après confirmation explicite de l'utilisateur.

**3. Compte rendu du test de bout en bout (31 juillet-1 août 2026, production METALVISION, ref `dlbewgsoboaycbpypcus`)**
Compte utilisé : `centredelasante@gmail.com` — superadmin plateforme, déjà admin actif de l'organisation opératrice MINOVIA (rôle `operator_admin`/vendeur).
Prérequis de données : un lot commercial disponible a été régénéré via `/admin/carbon-inventory` (`issue_credit_lot` sur l'émission `13f2de13-...`, dont l'unique lot précédent avait été annulé par correction interne au Lot 1 — la capacité non lotée redevient disponible, cf. §21 scénario 6).

Trois scénarios validés en conditions réelles, chacun revérifié par requête SQL directe après action UI :
1. **Cycle principal complet** — `create_credit_sale` (MINOVIA, 25,00 $/tCO2e, acheteur IBM) → `credit_sales.id = 8dd71ab8-...` (`draft`) → `add_credit_sale_lot` (lot `04e859d4-...`, 10 tCO2e) → `add_credit_sale_cost` (`platform_fee`, 15,00 $, `credit_sale_costs.id = 3c3c0fa6-...`) → `confirm_credit_sale` → `confirmed` (`gross_amount=250,00 $`, `net_distributable_amount=235,00 $`, lot `04e859d4-...` passé à `sold`) → `compute_credit_sale_allocations` a généré 3 lignes pour Acier Laurentien Inc. (`carbon_revenue` net 199,75 $, `reserve` net 11,75 $, `platform_fee` net 23,50 $ — somme exacte 235,00 $, égalité comptable vérifiée) → `settle_credit_sale` (référence `VIR-2026-001`) → `settled`.
2. **Annulation d'une vente brouillon** — `create_credit_sale` (10,00 $/tCO2e, aucun lot ajouté) → `credit_sales.id = 91540d11-...` → `cancel_credit_sale` (motif « Test annulation E2E ») → `status='cancelled'`, `cancelled_by`/`cancelled_at`/`cancel_reason` renseignés, `total_tco2e=0`.
3. **Libération d'un lot d'une vente brouillon** (`release_credit_sale_lot`, Lot 4 étape 1, 1er août 2026) — nouvelle capacité d'émission créée sur le résultat de vérification actif (`56af5bdc-...`, 65 tCO2e restants) : `create_credit_issuance` (5 tCO2e) → admissible → soumise → registre → `issue_credit_lot` → lot `e52f7a1c-...` (`available`). `create_credit_sale` (20,00 $/tCO2e) → `credit_sales.id = bcaf3ba4-...` → `add_credit_sale_lot` (lot `e52f7a1c-...`) → `release_credit_sale_lot` (motif « Test libération E2E ») → `credit_sale_lots.id = f427f3bf-...` avec `released_at`/`released_by`/`release_reason` renseignés, lot `e52f7a1c-...` revenu à `available`, vente restée `draft` (`total_tco2e=0`), **0 ligne** dans `credit_sale_allocations` pour cette vente — aucune réservation ni allocation résiduelle.

**4. Identifiants des objets de test**
- Lot vendu : `credit_lots.id = 04e859d4-c7cf-49d8-9146-a629f0e6e5f6` (10 tCO2e, millésime 2026, émission `13f2de13-...`)
- Vente principale : `credit_sales.id = 8dd71ab8-485f-4a29-9279-3d16228d7ef5` (settled)
- Coût : `credit_sale_costs.id = 3c3c0fa6-0f87-4517-adf8-c30b2bdadcbe` (platform_fee, 15,00 $)
- Vente annulée : `credit_sales.id = 91540d11-d072-4cae-933c-80faa7fb274b` (cancelled)
- Lot libéré : `credit_lots.id = e52f7a1c-1078-4e39-b547-b061f886182e` (5 tCO2e, émission `93aa9508-...`, à nouveau `available`)
- Vente avec libération : `credit_sales.id = bcaf3ba4-ce7c-4d29-89eb-09e5fb49d1d9` (draft, total_tco2e=0)
- Ligne `credit_sale_lots` libérée : `f427f3bf-1c0b-4818-8973-704c52637b62`

**5. Migrations**
**Aucune migration existante (01-09) n'a été modifiée.** Une migration additive corrective a été rédigée et appliquée : `11_carbon_sales_compute_allocations_safeupdate_fix.sql` (`CREATE OR REPLACE FUNCTION compute_credit_sale_allocations`, correctif pg-safeupdate, cf. point 2). Toutes les transitions d'état, calculs et autorisations métier restent portés par les RPC de la migration 09 (et ce correctif), appelées telles quelles depuis le frontend.

**6. Commits**
- `e6b39ea` — Lot 3 : cockpit de ventes carbone (`/admin/carbon-sales`, page + lien hub `/admin`)
- `7835f9d` — migration additive corrective `11_carbon_sales_compute_allocations_safeupdate_fix.sql` + documentation du présent §23 dans ADR-MVP.md

**7. Conclusion**
Le vertical slice du Lot 3 est validé en production sur l'intégralité de sa matrice d'actions : cycle principal complet (draft → lot → coût → confirmation → répartition calculée → règlement), annulation d'une vente brouillon, et libération d'un lot d'une vente brouillon (scénario 3, ajouté le 1er août 2026 — Lot 4 étape 1). Un bug réel de production (rejet systématique de `confirm_credit_sale` par pg-safeupdate côté PostgREST, invisible à toute validation hors du chemin HTTP réel) a été détecté et corrigé pendant ce test — troisième bug réel consécutif trouvé uniquement par test de bout en bout en conditions réelles (après le bug RLS du Lot 2 et l'embed PostgREST ambigu du Lot 1), confirmant que cette étape n'est pas optionnelle pour ce projet. Les trois lots verticaux du MVP carbone commercial (inventaire, gouvernance, ventes) sont maintenant tous livrés et testés en production, sans réserve de couverture connue restante.

---

## 24. Lot 4 — Régression transverse : bug réel trouvé sur le démarrage de vérification (1er août 2026)

**Contexte :** conformément au plan de stabilisation Lot 4 (5 étapes : régression transverse Lots 1-3, jeu de données pilote, manuel opératoire, pilote commercial fermé — décision utilisateur du 31 juillet 2026), l'étape 2 (régression intégrale) a commencé par le début de chaîne : planification d'une session de vérification (`/admin-verification-sessions`, RPC `plan_verification_session`) puis démarrage par le vérificateur assigné lui-même (`/verifier-mrv`, bouton « Démarrer la vérification »).

**1. Bug réel trouvé**
`/verifier-mrv/page.tsx` (page distincte de `/admin-verification-sessions`, utilisée par le vérificateur accrédité assigné pour ses propres sessions) exécutait pour ce bouton un `UPDATE` direct : `supabase.from('verification_sessions').update({status:'in_progress'}).eq('id', sessionId)`. Or les policies RLS réelles sur `verification_sessions` sont : `admin_manage_verification_sessions` (`ALL`, `is_project_admin()` — coordinateur MRV uniquement), `verifier_read_verification_sessions` et `client_read_verification_sessions` (`SELECT` seulement). **Aucune policy `UPDATE` n'existe pour le vérificateur assigné lui-même.** L'`UPDATE` ne levait aucune erreur (RLS filtre silencieusement la ligne hors du `WHERE` effectif → 0 ligne affectée, succès HTTP, aucune alerte déclenchée) : confirmé par lecture SQL directe, le statut restait `planned` après clic (« rien ne se passe », signalé par l'utilisateur).

Ce trou est structurel, pas cosmétique : `complete_verification_session()` refuse explicitement toute clôture tant que `status='planned'` (« Session non prête... »). Sans cette transition, aucune vérification ne pouvait jamais être complétée par le vérificateur assigné lui-même — bloquant de fait la suite de la régression transverse (étape 2).

Point notable : la valeur `'verification_session_started'` est autorisée dans le `CHECK` de `carbon_business_events` depuis la migration 05, mais aucune ligne ne l'utilisait en production avant ce correctif (`count=0` vérifié) — cette RPC était prévue dans la conception d'origine mais n'avait jamais été écrite ; le frontend avait improvisé un `UPDATE` direct à la place, sans RPC ni policy.

**2. Correctif**
`supabase/carbon_migrations_proposed/12_carbon_start_verification_session.sql` (additive, aucune migration existante 01-11 modifiée) : nouvelle RPC `start_verification_session(p_verification_session_id uuid)`, même patron que `plan_verification_session()`/`complete_verification_session()` (`SECURITY DEFINER`, verrou `FOR UPDATE` scopé au vérificateur assigné, revalidation d'accréditation active `FOR SHARE`, garde de transition explicite `status <> 'planned'` rejetée, insertion d'un événement d'audit `verification_session_started`). `GRANT EXECUTE ... TO authenticated` (même privilège que les deux RPC comparables, vérifié par requête sur `information_schema.routine_privileges` avant écriture). `handleStart()` dans `/verifier-mrv/page.tsx` modifié pour appeler cette RPC au lieu de l'`UPDATE` direct. Validé par `pglast.parse_sql()` (3 instructions) et par transpilation TypeScript (0 diagnostic) avant application.

**3. Validation en production**
Session `verification_sessions.id = ff1e97a0-b1d5-4b9f-96a7-73ec43e079f7` (vérificateur `f205e686-...` = `verifier@metaltrace.ca`, projet « Projet Test E2E »). Avant correctif : clic sur « Démarrer » → `status` resté `planned` (confirmé SQL). Après application de la migration 12 et déploiement du correctif frontend (commit `f18b1c8`) : nouveau clic → confirmé par requête SQL directe, `status='in_progress'`, ligne `carbon_business_events` présente (`event_type='verification_session_started'`, `actor_id=f205e686-...`, horodatée `2026-08-01 02:04:56`).

**4. Migrations**
Aucune migration existante (01-11) n'a été modifiée. `12_carbon_start_verification_session.sql` est strictement additive (`CREATE FUNCTION` + `COMMENT` + `GRANT`).

**5. Commit**
- `f18b1c8` — RPC `start_verification_session` (migration 12) + correctif `/verifier-mrv/page.tsx`

**6. Conclusion**
Quatrième bug réel consécutif trouvé uniquement par test de bout en bout en conditions réelles (après le bug RLS du Lot 2, l'embed PostgREST ambigu du Lot 1, et le rejet pg-safeupdate du Lot 3) — confirme la même leçon appliquée à chaque lot : aucune couverture statique ou transactionnelle ne remplace un test réel via l'interface, en conditions RLS/PostgREST réelles. La chaîne de vérification (`planned` → `in_progress` → `completed`) est maintenant fonctionnelle de bout en bout pour le vérificateur assigné. La régression transverse Lot 4 étape 2 se poursuit : compléter cette session de vérification (`complete_verification_session`), puis enchaîner émission → registre → lot → gouvernance → vente → règlement, avec vérification SQL à chaque étape.

---

## 25. Lot 4 — Régression transverse : trou structurel sur la preuve de vérification (1er août 2026)

**Contexte :** en poursuivant l'étape 2 (compléter la session de vérification débloquée en §24 via « Soumettre le rapport »), l'ancien `SubmitReportModal` de `/verifier-mrv` s'est révélé, à l'inspection, bien plus cassé que le bouton « Démarrer » : il faisait un `UPDATE` direct (`status:'completed'`, `comments`, `report_url`) sur `verification_sessions`, bloqué par la même absence de policy RLS, et de toute façon rejeté par le trigger structurel `carbon_guard_verification_session_update()` qui interdit `completed` sans `verification_outcome` existant.

**1. Trou plus profond trouvé avant tout test live**
`complete_verification_session()` (migration 05) exige un `verification_report_document_id` référençant une ligne `evidence_files` avec `type='verification_report'`, `project_id` correspondant et `file_hash` non vide. Audit du code frontend (grep exhaustif de `evidence_files` sur `src/`) : **aucun chemin de l'application n'écrit jamais `file_hash`** — les deux seuls `INSERT` existants (`api/transport/internal-create`, `api/projects/[id]/log-activity`) l'omettent tous les deux. Le sélecteur de preuve du `CompleteModal` de `/admin-verification-sessions` filtre déjà sur `file_hash IS NOT NULL`, mais est donc toujours vide en pratique. De plus, la seule policy RLS d'écriture sur `evidence_files` est `admin_manage_evidence_files` (`ALL`, `is_project_admin()`) — le vérificateur assigné n'a que `verifier_read_evidence_files` (`SELECT` seul), donc même un `INSERT` direct depuis `/verifier-mrv` aurait échoué. Enfin, `complete_verification_session()` exige `verifier_user_id = auth.uid()` : seul le vérificateur assigné peut l'appeler, ce qui rend le `CompleteModal` de `/admin-verification-sessions` (coordinateur) structurellement incapable de compléter une vraie vérification pour un vérificateur assigné distinct. **Conclusion : dans l'état antérieur à cette migration, aucune vérification ne pouvait jamais être complétée, quel que soit le chemin emprunté** — trou plus large que celui de §24.

**2. Correctif backend — migration 13**
`supabase/carbon_migrations_proposed/13_carbon_verification_evidence.sql` (additive, aucune migration 01-12 modifiée) :
- Nouveau bucket Storage privé `verification-evidence`, suivant exactement le patron déjà validé pour le bucket `documents` (`20260712110000_ccf_006f_documents_storage_bucket.sql`) : convention de chemin `<verification_session_id>/<timestamp>_<filename>`, policy `INSERT` gardée par `is_assigned_verifier()` sur le segment session_id (réutilise la fonction existante de la migration 05), policy `SELECT` déléguée à la RLS réelle de `evidence_files` via une fonction `SECURITY INVOKER` (`can_access_verification_evidence_storage_path`), `SELECT` superadmin, aucune policy `UPDATE`/`DELETE` (deny-all, append-only).
- Nouvelle RPC `record_verification_report_evidence(p_verification_session_id, p_file_url, p_file_hash)` (`SECURITY DEFINER`, même patron que `start_verification_session()`) : verrou + portée au vérificateur assigné, revalidation d'accréditation active `FOR SHARE`, validations `file_url`/`file_hash` non vides, insère la ligne `evidence_files` (`type='verification_report'`) pour son compte.

**3. Correctif frontend**
`SubmitReportModal` (`/verifier-mrv/page.tsx`) entièrement reconstruit : sélection d'un fichier de preuve, calcul du hash SHA-256 côté client (`crypto.subtle.digest`, Web Crypto native), téléversement dans `verification-evidence`, appel de `record_verification_report_evidence()` puis de `complete_verification_session()` avec `verified_reduction_tco2e`/`eligible_tco2e`/motif d'ajustement saisis. **Bug secondaire trouvé au premier test live** : Supabase Storage rejette les clés d'objet contenant accents/espaces (« Invalid key » sur `État de compte - Service de garde.pdf`) — corrigé en assainissant le nom de fichier (`normalize('NFD')` + suppression des diacritiques + remplacement de tout caractère hors `[a-zA-Z0-9._-]`) avant construction du chemin de stockage.

**4. Validation en production**
Session `verification_sessions.id = ff1e97a0-b1d5-4b9f-96a7-73ec43e079f7` (vérificateur `f205e686-...`, projet `cae4ca66-...`). Après correctifs et déploiement, « Soumettre le rapport » (fichier PDF réel, 5,00 tCO2e vérifiés/éligibles, motif « Manque de précision ») confirmé par requête SQL directe :
- `verification_sessions.status = 'completed'`.
- `verification_outcomes` : ligne active, `id = dafc00aa-06ec-4d0b-8f00-d3af783515a2`, `calculated_reduction_tco2e = 0.0000` (aucune activité GES sur la période), `verified_reduction_tco2e = 5.0000`, `eligible_tco2e = 5.0000`, `adjustment_reason` renseigné (obligatoire ici : calculé=0 ≠ vérifié≠0), `verified_by = f205e686-...`.
- `evidence_files.id = 21d85ef6-1ad9-4888-a868-a98ba76f31d9` : `type='verification_report'`, `file_hash` = chaîne hexadécimale de 64 caractères (SHA-256 valide), `file_url` assaini correctement.
- `carbon_business_events` : 3 lignes dans l'ordre attendu — `verification_session_started` (§24), puis `verification_session_completed` et `verification_outcome_recorded` (même horodatage, insérées par `complete_verification_session()`), toutes avec `actor_id = f205e686-...`.

**5. Migrations**
Aucune migration existante (01-12) n'a été modifiée. `13_carbon_verification_evidence.sql` est strictement additive (bucket + RPC + fonction de délégation SELECT + 3 policies storage.objects).

**6. Conclusion**
Cinquième bug réel consécutif trouvé uniquement par test de bout en bout en conditions réelles, et le plus profond de la série : une fonctionnalité entière (compléter une vérification) était structurellement inatteignable depuis toujours, sur trois axes indépendants (aucune écriture de `file_hash`, aucune policy RLS d'écriture `evidence_files` pour le vérificateur, aucun bucket Storage dédié). La chaîne de vérification MRV (`planned` → `in_progress` → `completed`, résultat actif avec preuve intègre) est maintenant fonctionnelle de bout en bout pour le vérificateur assigné, sans intervention SQL. La régression transverse Lot 4 étape 2 se poursuit côté opérateur carbone : émission → registre → lot → gouvernance → vente → règlement, avec vérification SQL à chaque étape.

---

## 26. Lot 4 étape 2 — Clôture de la régression transverse (1er août 2026)

**Contexte :** suite des §24-§25, la chaîne complète a été rejouée sur une seule et même nouvelle vérification (« Projet Test E2E »), à travers les trois lots verticaux déjà livrés (Lot 1, Lot 2, Lot 3), sans détour SQL — chaque étape exécutée dans l'interface réelle, vérifiée par requête SQL directe après coup.

**1. Chaîne rejouée**
`plan_verification_session` → `start_verification_session` (§24) → `complete_verification_session` avec preuve intègre (§25) → `create_credit_issuance` (Lot 1, `/admin/carbon-inventory`) → admissible → soumise → registre (Verra/CIM2) → `issue_credit_lot` → règle de distribution active du regroupement (10 % plateforme / 5 % réserve, déjà validée au Lot 2, réutilisée sans reproposition) → `add_credit_sale_lot` sur une vente brouillon existante (Lot 3, `/admin/carbon-sales`) → `confirm_credit_sale` → `settle_credit_sale`.

**2. Identifiants des objets**
- Résultat de vérification : `verification_outcomes.id = dafc00aa-06ec-4d0b-8f00-d3af783515a2` (5,00 tCO2e vérifiés/éligibles).
- Émission : `credit_issuances.id = 7d0b8131-ca3b-4d2c-8987-666160123ac8` (source unique Acier Laurentien Inc., 5,00 tCO2e, `issued`, Verra/CIM2).
- Lot : `credit_lots.id = 08abca4f-610f-49c6-8fb4-de0db5cc0d51` (5,00 tCO2e, millésime 2026).
- Règle de distribution réutilisée : `distribution_rules.id = deae125d-d241-439b-9b88-d368f97604f7` (10 %/5 %, activée le 31 juillet, Lot 2).
- Vente : `credit_sales.id = bcaf3ba4-ce7c-4d29-89eb-09e5fb49d1d9` (même vente brouillon que le scénario 3 du Lot 3, §23 — un lot y a été ajouté puis la vente confirmée/réglée ; prix 20,00 $/tCO2e, aucun coût ajouté, `gross_amount = net_distributable_amount = 100,00 $`, référence de règlement « Test vente2 »).

**3. Vérifications**
- Allocations exactes : `carbon_revenue` (Acier Laurentien Inc.) net 85,00 $, `platform_fee` net 10,00 $, `reserve` net 5,00 $ — somme 100,00 $, égalité comptable avec `net_distributable_amount` confirmée.
- 11 événements d'audit dans l'ordre attendu sur l'ensemble de la chaîne (`verification_session_started`, `verification_session_completed`, `verification_outcome_recorded`, `credit_issuance_created`, `credit_issuance_marked_eligible`, `credit_issuance_submitted`, `credit_issuance_issued`, `credit_lot_issued`, `credit_sale_confirmed`, 3× `credit_sale_allocation_recorded`, `credit_sale_settled`).
- Aucun résidu : aucune ligne orpheline, aucune double allocation, capacité de l'émission strictement consommée (5,00/5,00 tCO2e éligibles).

**4. Conclusion**
Aucun bug supplémentaire trouvé sur cette portion de la chaîne : les composants déjà livrés et corrigés des Lots 1, 2 et 3 se comportent correctement une fois enchaînés bout en bout dans un scénario neuf, ce qui est la valeur propre d'une régression transverse (confirmer la tenue ensemble de correctifs validés isolément). **Lot 4 étape 2 est close** : la chaîne complète vérification → émission → registre → lot → gouvernance → vente → règlement est validée en production, sans intervention SQL, avec deux bugs réels trouvés et corrigés en cours de route (§24, §25) et aucun autre. Prochaine étape : Lot 4 étape 3 (jeu de données pilote de démonstration).

---

## 27. Routage post-connexion par rôle réel (`get_my_portal_role()`) — deux bugs d'accès trouvés et corrigés via les tests preview DEMO (2 août 2026)

**Contexte :** `login/page.tsx` et `AppLayout.tsx` déterminaient le portail post-connexion à partir de `app_metadata.role`/`user_metadata.role` du JWT. 5 des 6 comptes démo (tous sauf `superadmin@demo.metaltrace.ca`) n'ont aucune clé `role` dans leur JWT — le statut réel de plusieurs d'entre eux (ex. vérificateur accrédité) vit dans des tables dédiées (`accredited_verifiers`), sans lien avec le JWT.

**1. Correctif central : `public.get_my_portal_role()`**
Nouvelle RPC (`supabase/carbon_migrations_proposed/14_get_my_portal_role_rpc.sql`) : `STABLE`, `SECURITY DEFINER`, `search_path=''`, zéro paramètre (`auth.uid()` uniquement — ne peut jamais sonder le statut d'un tiers), `REVOKE ALL` puis `GRANT EXECUTE` à `authenticated` seul. Priorité de résolution : `admin` (`is_platform_superadmin()` seule) > `verifier` (`is_authorized_verifier_identity(auth.uid())`, c.-à-d. `accredited_verifiers.active`) > `client` (défaut — couvre à dessein les admins d'organisation/regroupement, rôles scopés à une entité précise, jamais un rôle de portail global).

Appliquée définitivement sur METALVISION-DEMO (`msgesgemaasyzycielzf`), migration distante `20260802032220_get_my_portal_role_rpc`, après un GATE transactionnel (`BEGIN...ROLLBACK`) 15/15 puis un rejeu réel 15/15 sur l'état permanent (6 comptes, appel anonyme rejeté, ACL, `STABLE`, `SECURITY DEFINER`, `search_path` vide, zéro paramètre). Empreinte des données/policies `public` identique avant/après (152 policies, hash `ad90a6f4d01c3a7402d0d24beaeae8c3`) : aucune donnée ni policy modifiée. Non appliquée en production (`dlbewgsoboaycbpypcus`).

`src/lib/auth/getPortalRole.ts` centralise l'appel (point unique) ; `login/page.tsx` et `AppLayout.tsx` l'utilisent exclusivement, avec état de chargement, aucun flash du portail client, garde-fou anti-boucle de redirection, et déconnexion locale explicite sur échec RPC (jamais de repli silencieux vers `'client'`).

**2. Bug réel n°1 — `/admin` accessible à tout compte authentifié**
Trouvé en testant `operateur@demo.metaltrace.ca` sur la preview Vercel : navigation directe vers `/admin` affichait le contenu complet (stats plateforme, données réelles). Cause : le gate d'accès ne vérifiait que l'absence d'erreur sur `supabase.from('audit_logs').select(..., {count:'exact', head:true})` — or RLS ne lève jamais d'erreur quand elle filtre toutes les lignes, elle retourne simplement 0 ligne. Confirmé en base avec un JWT simulé opérateur : `had_error=false, row_count=0`. Résultat : `isSuperAdmin` passait à `true` pour n'importe quel utilisateur authentifié. Corrigé (`src/app/admin/page.tsx`, commit `9894f72`) en gate sur `getPortalRole() === 'admin'`, avec échec fermé sur toute erreur de résolution.

**3. Bug réel n°2 — `/verifier-mrv` bloquait le vrai vérificateur accrédité**
Trouvé en testant `verificateur@demo.metaltrace.ca` : connexion et redirection correctes, mais la page affichait « Accès refusé ». Cause : un gate d'accès indépendant et antérieur à ce correctif, lisant d'abord `user_metadata.role` (absent du JWT, même cause racine), puis repliant sur une table `company_members` sans rapport avec le modèle d'accréditation réel (`accredited_verifiers`, migration carbone 05) — 0 ligne pour ce compte, `.single()` renvoyait 406 PostgREST, interprété comme « pas vérificateur ». Corrigé (`src/app/verifier-mrv/page.tsx`, commit `0897de2`) en gate sur `getPortalRole() === 'verifier'`, même source de vérité que `/admin` et le routage.

**4. Correctif cosmétique — badge Topbar**
`ROLE_BADGE.client` (`src/components/Topbar.tsx`, commit `518c569`) renommé « Client » → « Utilisateur » (initiales `CL` → `UT`) : ce bucket couvre aussi les admins d'organisation/regroupement (opérateur, agrégateur, producteur, recycleur), que « Client » présentait à tort comme de simples clients. Aucun changement de logique de routage.

**5. Validation — 6 comptes sur la preview Vercel DEMO**
Preview du projet Vercel `metalvision-demo-web` (déploiement « Production » de ce projet, dédié exclusivement à la démo — sans rapport avec la production réelle METALTRACE ; confirmé par lecture directe du bundle client livré : `NEXT_PUBLIC_SUPABASE_URL` = `msgesgemaasyzycielzf.supabase.co`, aucune `SUPABASE_SERVICE_ROLE_KEY` exposée). Après les trois commits ci-dessus, les 6 comptes ont été retestés avec succès sur 8 critères (destination, absence de flash, pas de rebond `/login`, RPC sans repli silencieux, badge, accès métier RLS, navigation legacy masquée, 404 sur `/api/predict` et `/api/aggregator/calculate-sale`) : superadmin → `/admin` ; vérificateur → `/verifier-mrv` ; opérateur, agrégateur, producteur, recycleur → `/`, avec `/admin` refusant l'accès à chacun d'eux. Branche `cleanup/legacy-frontend-audit`, poussée par l'utilisateur (identifiants Git absents du bac à sable agent) ; `main` et la production n'ont pas été touchés.

**6. Rotation du mot de passe démo (post-tests)**
Le mot de passe temporaire posé sur les 6 comptes pour permettre ces tests ayant transité en clair dans la conversation, il a été rotationné une nouvelle fois sur METALVISION-DEMO (`UPDATE auth.users SET encrypted_password = crypt(...)`, vérifié par comparaison bcrypt post-application sur les 6 comptes). Le nouveau mot de passe est communiqué hors dépôt, comme lors de la rotation précédente — jamais commité en clair.

**État :** les trois correctifs frontend + la RPC sont validés en conditions réelles sur METALVISION-DEMO et sa preview Vercel dédiée. Reste, si autorisé séparément : parcours CCF + Lots carbone 1-3 en navigateur et cycle `reset_demo` → reseed.

---

## 28. `get_my_portal_role()` appliquée et validée en production — backend prêt pour le déploiement de `main` (6 août 2026)

**Contexte :** suite au GATE de préparation du déploiement production (lecture seule, voir `RAPPORT-REGRESSION-DEMO-FINAL.md` section 11), deux décisions restaient en attente avant toute reconnexion Vercel : corriger la migration `20260801010000` (retirer un `DROP POLICY` reposant sur une affirmation fausse — la policy `ccf_projects_via_user_project_ids` est en réalité présente et active en production) et statuer sur l'application de `get_my_portal_role()` (§27) en production. L'utilisateur a tranché les deux.

**1. Correctif `20260801010000`**
Le `STEP 3` (`DROP POLICY ccf_projects_via_user_project_ids`) est retiré de `supabase/migrations/20260801010000_reconcile_project_participants_ccf_projects_with_production.sql` — cette migration corrigée ne touche plus du tout cette policy. Sa suppression éventuelle redevient une décision strictement séparée, non prise. Divergence entre la version historiquement appliquée à DEMO (avec l'ancien `STEP 3`) et la version corrigée du dépôt documentée dans `supabase/MIGRATIONS_TIMELINE.md` (empreintes SHA-256 des deux versions). Commit `ba271bb`, poussé sur `main`. Aucun fichier frontend touché (`git diff 869827d ba271bb -- src/` vide). Cette migration corrigée reste **non appliquée en production**.

**2. Application de `get_my_portal_role()` en production**
Exécutée directement sur `dlbewgsoboaycbpypcus` dans une transaction unique (`BEGIN...COMMIT`), conditionnée à la réussite de tous les contrôles catalogue et comportementaux — tout échec aurait provoqué un `ROLLBACK` automatique. Une première tentative a effectivement échoué sur une assertion de test trop stricte (bug du test, pas de la fonction) : `ROLLBACK` automatique confirmé, absence de la fonction reconfirmée en lecture seule avant de relancer intégralement depuis `BEGIN` — aucune trace laissée, pas un incident production.

Transaction finale : prérequis vérifiés (`is_platform_superadmin()`, `is_authorized_verifier_identity(uuid)`, déjà présents), création de la fonction (texte strictement identique à `carbon_migrations_proposed/14_get_my_portal_role_rpc.sql`), `REVOKE ALL` puis `GRANT EXECUTE` à `authenticated` seul, gate catalogue (`prosecdef=true`, `proconfig={search_path=""}`, ACL `anon=false/authenticated=true/public=false`), gate comportemental sous le rôle `authenticated` (pas superuser) sur **3 identités réelles de production** : admin → `'admin'`, vérificateur accrédité actif → `'verifier'`, client → `'client'`. `COMMIT` exécuté à 12:04:15 UTC le 2026-08-06.

Post-COMMIT : empreinte données/policies strictement identique avant/après (`n_users=9, n_accredited_verifiers=1, n_org_members=3, n_organizations=4, n_policies_public=147`, même `policies_fingerprint=c83662a2129b4d9e5720b88a4fcad721`) ; seul `n_functions_public` passe de 356 à 357 — exactement la fonction créée, rien d'autre touché. Re-vérification indépendante post-COMMIT : `anon` correctement rejeté (`insufficient_privilege`) avant même d'atteindre le corps de la fonction. Non inscrite dans `supabase_migrations.schema_migrations` (production s'arrête toujours à `20260722134537`) — cohérent avec un mode d'application SQL brut, constaté en direct plutôt que supposé, conformément à l'instruction du projet de toujours comparer les objets live. Détail complet : `RAPPORT-REGRESSION-DEMO-FINAL.md` section 12.

**3. Statut du fichier de migration 14**
L'en-tête de `carbon_migrations_proposed/14_get_my_portal_role_rpc.sql` (qui affirmait « NON appliquée en production — décision séparée en attente ») est corrigé pour refléter l'application réelle sur DEMO et sur production, avec la date, l'heure, le mode d'application et l'empreinte données/policies. Le contenu fonctionnel de la fonction (STEP 1/2/3) est inchangé.

**4. Portée inchangée — ce qui n'a PAS été fait**
Aucune reconnexion de l'intégration Git Vercel du projet `metalvision`, aucun build, aucun déploiement sur `metaltrace.ca`, aucune autre migration, aucun `migration repair`, aucune modification des variables de production. Le prochain GATE (distinct) portera exclusivement sur la reconnexion contrôlée de Vercel, le build de `main` et les smoke tests de production, avec possibilité de réassigner immédiatement le déploiement antérieur (`1dd9d39`) en cas d'échec.

**5. Conclusion**
Le backend requis par le frontend de `main` (commit `869827d`, fusionné en section 10 du rapport de régression) est désormais prêt côté production : `get_my_portal_role()`, seule dépendance backend réellement requise par ce frontend et absente jusqu'ici, est appliquée, validée par 3 identités réelles, et n'a modifié aucune donnée ni policy existante. **Verdict : BACKEND PRÊT POUR DÉPLOIEMENT.**

---
