# Brief Rocket — Écran S05 (`/projets/:id`)

**Contexte :** le backend est complet et corrigé (`ADR-MVP.md` §9duodecies, `INC-S05-01` déployé sur METALVISION). C'est l'écran le plus dense du MVP : participants, phases, documents, logistique, risques, rapport de valeur, tous dans une seule vue.

**Avant de commencer : resynchronisez votre environnement local (`git pull`/`git reset --hard origin/main`) avant de créer votre branche.** Les 2 dernières livraisons (S07, S08) contenaient chacune, en plus du travail demandé, une réintroduction accidentelle et identique de bugs déjà corrigés (`ADR-MVP.md` §9octies/§9decies) — toujours le même contenu périmé, jamais nettoyé entre les livraisons. Un `git pull` avant de démarrer évite ce problème.

---

## 1. Objectif de l'écran

Route `/projets/:id`. Vue détaillée d'un projet CCF regroupant tout ce qui lui est rattaché. Référence : backlog technique v1.0, E08 (Projets et participants), E11 (Suivi logistique), E12 (Rapport de valeur — partiel, le cockpit exécutif complet est S09, pas cet écran).

## 2. Schéma existant (ne pas modifier, tout est déjà en place)

### `public.ccf_projects`
| Colonne | Détail |
|---|---|
| `opportunity_id` | Opportunité d'origine (obligatoire) |
| `coordinator_org_id` | Organisation coordinatrice |
| `phase` | `draft`, `active`, `execution`, `review`, `closed` |
| `status` | `draft`, `active`, `paused`, `closed`, `archived` |
| `start_date`, `target_end_date` | |

Pas de machine à états stricte sur `phase`/`status` — l'admin coordinateur peut passer d'une valeur à l'autre librement (contrairement aux mandats). Émettre un `business_event` `project_phase_changed` à chaque changement de `phase` (insertion manuelle, aucune RPC ne le fait).

### `public.project_participants`
| Colonne | Détail |
|---|---|
| `project_role` | `coordonnateur`, `contributeur`, `lecteur` — **purement informatif, aucune policy RLS ne s'appuie dessus**, ne pas construire de logique de permission autour de ce champ côté frontend non plus |
| `mandate_id` | Lien vers le mandat ayant permis la participation (peut être `NULL` pour une participation créée directement par le coordinateur) |
| `status` | `invited`, `active`, `declined`, `removed` |

**Invitation d'une organisation** (US-013) : ne réinventez pas ce flux. `accept_project_invitation(p_mandate_id, p_project_id)` et `decline_project_invitation(p_mandate_id)` existent déjà et sont testées (session S06) — à réutiliser tel quel, simplement exposées dans le contexte de cet écran plutôt que seulement depuis `/mandats`.

### `public.logistics_steps`
| Colonne | Détail |
|---|---|
| `step_type` | ENUM : `ramassage`, `chargement`, `expedition`, `transit`, `livraison`, `preuve_finale` |
| `responsible_org_id` | Organisation responsable de l'étape |
| `planned_date`, `actual_date` | |
| `proof_document_id` | Lien optionnel vers un document (table `documents`, déjà construite en S07) |
| `status` | `planned`, `in_progress`, `completed`, `blocked`, `cancelled` |

Composant attendu par le backlog : `LogisticsStepCard` (« étape logistique avec responsable, dates, statut et preuve »).

**Permissions** (déjà en RLS, pas à recoder côté client) : modification réservée à l'admin de l'organisation coordinatrice, **ou** un membre de l'organisation responsable dont `org_role = 'admin'` **ou** `operational_profile = 'terrain'` — un membre "bureau" sans profil terrain ne peut pas modifier une étape même s'il appartient à l'organisation responsable. Prévoir un message clair si la mise à jour échoue pour cette raison plutôt qu'une erreur brute.

Aucune RPC pour les transitions de statut — `UPDATE` direct + insertion manuelle `business_event` `logistics_step_updated`.

### `public.value_reports`
| Colonne | Détail |
|---|---|
| `volume`, `coordination_value` | numériques |
| `notes` | texte libre |
| `status` | `draft`, `generated`, `validated`, `shared`, `archived` |

**Écriture réservée exclusivement à l'admin de l'organisation coordinatrice** (aucun participant ne peut créer/modifier un rapport, RLS déjà en place). `UPDATE`/`INSERT` direct + insertion manuelle `business_event` `value_report_generated`.

## 3. « Risques » — clarification de portée importante

**Il n'existe aucune table `risks` dans le schéma.** Le backlog mentionne « risques » dans la description de l'écran sans jamais la détailler ailleurs. Pour cette itération, construisez ce panneau comme un **indicateur calculé côté frontend**, pas une nouvelle donnée en base — par exemple :
- Étapes logistiques en statut `blocked`.
- `target_end_date` dépassée alors que `phase` n'est pas `closed`.
- Participants en statut `declined` sur une invitation.

Ne créez pas de table `risks` ni de RPC associée — ce serait hors scope et non demandé.

## 4. Documents du projet

Réutilisez l'infrastructure déjà construite en S07 : les documents rattachés à ce projet sont ceux où `object_type = 'project'` et `object_id = <id du projet>`. Le composant `DocumentUploader` (`src/app/documents/page.tsx`) peut être adapté/extrait pour permettre un dépôt direct depuis cet écran avec `object_type`/`object_id` pré-remplis — évite à l'utilisateur de ressaisir ces valeurs manuellement.

## 5. Historique du projet

Le composant `ObjectTimeline` (`src/components/ObjectTimeline.tsx`, construit en S08) est fait pour ça : `<ObjectTimeline object_type="project" object_id={projectId} />` affiche directement l'historique `business_events` du projet. Ne pas dupliquer cette logique.

## 6. Ce qu'il faut retenir sur les `business_events` (pour éviter un nouveau `INC-S06-06`)

Aucune RPC n'existe pour les actions de cet écran (phase, étapes logistiques, rapport de valeur) — donc pour **chacune** de ces trois actions, l'insertion manuelle du `business_event` correspondant est **obligatoire et légitime** (pas de RPC qui le ferait à votre place, donc pas de risque de doublon ici). Seul le flux d'invitation (`accept_project_invitation`/`decline_project_invitation`) insère déjà son propre événement côté serveur — ne rien insérer manuellement pour celui-là.

## 7. Avant de livrer

PR revu selon `ROCKET_REVIEW_CHECKLIST.md` avant fusion. Points d'attention spécifiques à cet écran : vérifier qu'aucun code n'essaie d'utiliser `project_role` pour des décisions de permission (ça n'a aucun effet réel), et que le panneau "risques" n'introduit pas de nouvelle table ou migration.
