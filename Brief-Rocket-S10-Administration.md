# Brief Rocket — Écran S10 (`/admin`, Administration)

**Contexte :** le backend a été revu (`ADR-MVP.md` §9unvicies). Une seule correction a été nécessaire — une policy RLS manquante sur `profiles` (`profiles_superadmin_select`, déjà déployée en production) — tout le reste des besoins de cet écran est déjà couvert par des policies existantes ou ne nécessite aucune nouvelle table.

**Avant de commencer : `git pull`/`git reset --hard origin/main` avant de créer votre branche.** 7 livraisons consécutives ont chacune contenu la réintroduction accidentelle de bugs déjà corrigés, toujours le même contenu périmé (`ADR-MVP.md` §9octodecies). La revue de ce PR fera, comme les précédentes, un diff fichier par fichier de la branche complète.

---

## 1. Clarification de portée essentielle — lisez avant de commencer

**`/admin` (cet écran) est entièrement distinct de `/admin-dashboard`** (domaine MRV préexistant, sans rapport avec MetalTrace CCF — voir S01, `ADR-MVP.md` §9septdecies). Ne touchez à aucun fichier du dossier `src/app/admin-dashboard/` ni à ses composants.

**Gate d'accès — point critique :** cet écran doit être réservé aux **admins plateforme**, une notion différente du rôle `admin` générique (`app_metadata.role`) utilisé ailleurs (celui qui redirige vers `/admin-dashboard` dans `AppLayout.tsx`). L'accès à `/admin` doit être vérifié via une requête qui dépend de la policy RLS `is_platform_superadmin()` déjà en place côté base — **la façon la plus simple et la plus sûre de vérifier l'accès côté frontend est de tenter une requête sur une table gardée par cette fonction (ex. `audit_logs`, `SELECT count(*)`) et de vérifier qu'elle ne retourne pas une erreur de permission**, plutôt que de lire un champ `role` du JWT dont le nom/l'emplacement exact côté client n'est pas garanti. Si la requête échoue silencieusement (RLS bloque, retourne un tableau vide au lieu d'une erreur), affichez un état « Accès réservé aux administrateurs plateforme » plutôt qu'un écran vide trompeur.

Référence backlog : S10, « Utilisateurs, catalogues, logs, connecteurs prévus » (M1 partiel / M3 complet).

## 2. Utilisateurs (cross-organisation)

Liste de tous les membres, toutes organisations confondues (accès superadmin) :
- Requête `organization_members` (aucun filtre `organization_id`, la policy superadmin donne accès à tout) jointe à `organizations(name)` et `profiles(full_name, email)` (ou les colonnes équivalentes déjà utilisées ailleurs dans le code, ex. `Sidebar.tsx`).
- Colonnes attendues : nom/email utilisateur, organisation, `org_role` (`admin`/`membre`), `status`.
- Pas de pagination sophistiquée requise pour le MVP — une liste simple avec tri par organisation suffit.
- **Lecture seule.** Aucune action de modification de rôle ou de suppression de membre dans ce ticket (hors périmètre MVP).

## 3. Catalogues (référentiels)

**Aucune nouvelle table, aucune requête base de données pour cette section.** Affichage statique, codé directement dans le composant frontend, des valeurs de référence déjà fixées au niveau du schéma :
- `mandate_scope` : gouvernance, opérationnel, financier, technique, vérification, ia
- `document_visibility` : organization_private, project, confidential
- `org_role` : admin, membre
- Statuts `mandates` : draft, pending_acceptance, active, expired, revoked
- Statuts `documents` : draft, submitted, approved, rejected, archived
- Phases `ccf_projects` : draft, active, execution, review, closed

Présentez-les en lecture seule (ex. cartes ou tableau par catégorie) — ce sont des valeurs figées du MVP, pas un catalogue éditable.

## 4. Logs d'audit (US-012)

`audit_logs`, déjà protégée par `audit_logs_superadmin_select` :
- Colonnes disponibles : `actor_id` (FK `profiles`), `action` (INSERT/UPDATE/DELETE), `table_name`, `record_id`, `before`/`after` (jsonb), `created_at`.
- Liste triée par `created_at` DESC, limitée à un nombre raisonnable (ex. 50, avec pagination simple si le temps le permet).
- Jointure `profiles` sur `actor_id` pour afficher le nom de l'acteur plutôt qu'un UUID brut (fonctionne maintenant grâce à `profiles_superadmin_select`).
- Affichage simple de `table_name`/`action`/`record_id`/date ; `before`/`after` peuvent être affichés en JSON brut replié (pas besoin d'un diff visuel élaboré pour le MVP).

## 5. Connecteurs prévus (US-016, COULD — priorité basse)

**Aucune table, aucune activation possible.** Liste statique codée dans le frontend présentant les connecteurs prévus sur la feuille de route (ex. "Groupe Robert (transport)", "Metals.Dev (prix des métaux)", etc. — ou une liste générique si le contenu exact n'est pas connu). Chaque entrée doit être visuellement marquée comme non active (ex. badge « Prévu », grisé, sans bouton d'action).

Si le temps est limité, cette section a la priorité la plus basse de l'écran (COULD dans le backlog) — les sections 2 à 4 sont prioritaires.

## 6. Ce qu'il ne faut pas faire

- Ne touchez à aucun fichier de `src/app/admin-dashboard/` (domaine MRV, hors périmètre).
- N'utilisez pas `app_metadata.role === 'admin'` comme gate d'accès à cet écran — voir §1.
- Pas de nouvelle table, migration, ou policy RLS — tout est déjà en place.
- Pas de CRUD sur les utilisateurs (changement de rôle, suppression) — lecture seule uniquement pour le MVP.
- Pas d'activation réelle de connecteur — affichage statique seulement.

## 7. Avant de livrer

PR revue selon `ROCKET_REVIEW_CHECKLIST.md` avant fusion, comme pour chaque écran précédent.
