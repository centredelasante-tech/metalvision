# Brief Rocket — Écran S07 (`/documents`)

**Contexte :** le backend de S07 est terminé, corrigé et validé en production sur METALVISION (voir `ADR-MVP.md` §9septies). Ce brief décrit ce qu'il reste à construire côté frontend — la table, les contraintes et les RPC existent déjà, ne rien recréer côté base de données.

---

## 1. Objectif de l'écran

Route `/documents` (S01-S10, S07). Dépôt documentaire gouverné : upload, visibilité, version, statut, rattachement à un objet métier. Référence : backlog technique v1.0, E09 (« Documents gouvernés et visibilité »), tâches E09-T01 à T04.

## 2. Schéma existant — `public.documents` (ne pas modifier)

| Colonne | Type | Détail |
|---|---|---|
| `id` | UUID | PK |
| `owner_org_id` | UUID | Organisation propriétaire/déposante |
| `object_type` | text | `organization`, `capability`, `opportunity`, `project`, `mandate`, `value_report` |
| `object_id` | UUID | Référence polymorphique vers l'objet ci-dessus |
| `title` | text | Obligatoire |
| `category` | text | Libre |
| `version` | text | Défaut `'1.0'` |
| `visibility` | ENUM `document_visibility` | `organization_private`, `project`, `confidential` |
| `storage_path` | text | Chemin Supabase Storage |
| `status` | text | `draft`, `submitted`, `approved`, `rejected`, `archived` |

**Contrainte à respecter dans l'UI (MVP-RA-026)** : si `visibility = 'project'`, alors `object_type` doit être `'project'` — sinon l'`INSERT`/`UPDATE` est rejeté par la base. Désactiver ou masquer l'option "Visibilité : Projet" dans le formulaire tant que l'objet rattaché n'est pas de type `project`, pour éviter une erreur DB en pleine face à l'utilisateur.

## 3. Machine à états — à respecter strictement

```
draft ──(dépôt/soumission)──► submitted
submitted ──(approbation)───► approved
submitted ──(refus)─────────► rejected
approved | rejected ──(archivage)──► archived
```

**Trois façons différentes d'écrire ces transitions — ne pas les confondre :**

| Transition | Mécanisme | `business_events` |
|---|---|---|
| `draft → submitted` | `UPDATE` direct sur `documents` (policy `documents_owner_admin_update`, réservée à l'admin de `owner_org_id`) | **Insertion manuelle obligatoire** côté frontend (`event_type: 'document_submitted'`) — aucune RPC ne le fait à votre place. |
| `submitted → approved` / `submitted → rejected` | **RPC `public.approve_document(p_document_id uuid, p_decision text)`** — `p_decision` = `'approved'` ou `'rejected'` uniquement | **Ne jamais insérer manuellement** — la RPC insère déjà l'événement (`document_approved`/`document_rejected`) elle-même, côté serveur. Un insert manuel en plus créerait un doublon (voir `INC-S06-06`, `ADR-MVP.md` §9quinquies). |
| `approved`/`rejected` → `archived` | `UPDATE` direct sur `documents` (même policy que ci-dessus) | **Insertion manuelle obligatoire** côté frontend (`event_type: 'document_archived'`) — aucune RPC ne le fait à votre place. |

### Pourquoi passer par `approve_document()` pour l'approbation, spécifiquement

Cette RPC (`SECURITY DEFINER`) gère **deux cas d'autorisation** que l'UI n'a pas à distinguer elle-même :

1. L'admin de l'organisation propriétaire du document (`owner_org_id`) — accès déjà permis par la policy `UPDATE` existante, la RPC le centralise simplement.
2. **Un mandataire tiers** : un utilisateur membre actif d'une organisation détenant un mandat `active`, lié au projet propriétaire du document via `project_participants.mandate_id`, et dont `permissions.actions` contient `approve_documents`. C'est un cas que la policy `UPDATE` seule ne couvre **pas** — uniquement la RPC le permet.

Appel côté frontend, simple :
```ts
const { data, error } = await supabase.rpc('approve_document', {
  p_document_id: document.id,
  p_decision: 'approved', // ou 'rejected'
});
```
Si l'utilisateur n'est ni l'un ni l'autre, la RPC lève une exception explicite (`Non autorisé : ...`) — à afficher telle quelle ou traduire proprement, mais ne pas la masquer silencieusement.

## 4. Visibilité — comportement déjà géré par les RLS (rien à coder côté sécurité)

- `organization_private` : visible aux membres de `owner_org_id` uniquement.
- `project` : visible aux membres de `owner_org_id` **et** aux participants actifs du projet (`project_participants`).
- `confidential` : visible au déposant + selon le type d'objet, au coordonnateur (opportunité/projet/rapport de valeur via son projet) ou aux parties du mandat (émetteur/récepteur), si `object_type = 'mandate'`.

L'UI n'a pas à filtrer manuellement les documents visibles — une simple `SELECT * FROM documents` retourne déjà exactement ce que l'utilisateur a le droit de voir. Ne pas ajouter de filtre client redondant qui pourrait masquer des documents que RLS autoriserait à tort (ou l'inverse).

## 5. Suppression — volontairement absente

Aucun bouton "Supprimer" un document. La suppression physique est interdite par conception (MVP-DA-006) ; le cycle de vie passe uniquement par `status → archived`. Toute tentative de `DELETE` sera rejetée par la base (aucune policy `DELETE` définie).

## 6. Composants attendus (backlog technique)

- `DocumentUploader` : dépôt avec sélection `object_type`/`object_id`, `visibility`, `category`, upload vers Supabase Storage → `storage_path`.
- Liste/filtre des documents par statut et par objet rattaché.
- Panneau de détail avec actions contextuelles : "Soumettre" (draft→submitted), "Approuver"/"Refuser" (submitted→approved/rejected, **via la RPC**), "Archiver" (approved/rejected→archived).

## 7. Avant de livrer — rappel

Une fois le PR ouvert, il sera revu selon `ROCKET_REVIEW_CHECKLIST.md` avant toute fusion sur `main` — en particulier la section 3 (doublons `business_events`) et la section 1 (permissions déclarées mais non appliquées). Le point le plus probable d'erreur ici : insérer manuellement `document_approved`/`document_rejected` en plus de l'appel à `approve_document()`, ou l'inverse (appeler la RPC en pensant qu'elle gère aussi `draft→submitted`, ce qu'elle ne fait pas).
