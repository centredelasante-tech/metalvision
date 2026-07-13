# Brief Rocket — Création d'étape logistique (`/projets/:id`, onglet Logistique)

**Contexte :** en poursuivant le test end-to-end du parcours CCF complet (après la conversion opportunité → projet et l'invitation d'organisation, toutes deux validées en production), on a découvert que l'onglet **Logistique** de `/projets/:id` sait déjà **lire** et **modifier le statut** d'une étape logistique existante (`LogisticsStepCard`, boutons Modifier/Enregistrer), mais **rien ne permet de créer une étape** — aucun bouton, aucun formulaire, aucun `INSERT` nulle part dans le dépôt.

**Bonne nouvelle : le backend est déjà entièrement prêt, aucune migration n'est nécessaire.** Vérifié en lisant `20260710999000_reset_and_reapply_ccf_full.sql` (lignes 1148-1157) :
- `logistics_steps_coordinator_insert` : `WITH CHECK (EXISTS (SELECT 1 FROM ccf_projects p WHERE p.id = project_id AND is_organization_owner(p.coordinator_org_id)))` — un admin de l'organisation coordonnatrice du projet peut insérer n'importe quelle étape pour ce projet, y compris pour une autre organisation responsable.

**Avant de commencer : `git pull`/`git reset --hard origin/main`.** Comme pour chaque écran précédent, la revue de ce PR fera un diff fichier par fichier de la branche complète contre `origin/main` — tout fichier périmé réintroduit sera rejeté sans y toucher.

---

## 1. Où et quand afficher le bouton

Sur `/projets/:id`, onglet **Logistique** (`activeTab === 'logistics'`), ajouter un bouton **« Ajouter une étape »** dans l'en-tête de section (à côté du titre « Étapes logistiques (N) », même emplacement que les boutons équivalents des autres onglets — Participants a « Inviter une organisation », Documents a « Déposer un document »). Visible uniquement si `isCoordinatorAdmin` (variable déjà présente dans le composant, calculée comme `myAdminOrgIds.includes(project.coordinator_org_id)`).

## 2. Formulaire (modale)

- **Type d'étape** (`step_type`, obligatoire) — sélecteur avec les 6 valeurs exactes de l'ENUM `logistics_step_type` (déjà définies dans le fichier, `LOGISTICS_STEP_TYPE_LABELS`) : `ramassage`, `chargement`, `expedition`, `transit`, `livraison`, `preuve_finale`. Réutiliser ce mapping existant pour les libellés, ne pas le redéfinir.
- **Organisation responsable** (`responsible_org_id`, obligatoire) — liste déroulante des organisations **participantes actives** du projet (`participants.filter(p => p.status === 'active').map(p => p.organization)`), pas la liste de toutes les organisations de la plateforme. Le coordonnateur lui-même doit pouvoir y figurer (il est un participant actif dès la création du projet).
- **Date planifiée** (`planned_date`, optionnelle).
- Pas de champ `status` dans le formulaire — toujours `'planned'` par défaut (valeur par défaut de la colonne, ne pas l'envoyer explicitement ou l'envoyer explicitement à `'planned'`, les deux sont équivalents).

## 3. À la soumission

Une seule étape, pas de séquence multi-étapes :

```
INSERT INTO logistics_steps (project_id, step_type, responsible_org_id, planned_date, status)
VALUES (project.id, <step_type choisi>, <responsible_org_id choisi>, <planned_date ou null>, 'planned')
```

**Aucun `business_events` manuel à insérer à la création.** Contrairement aux autres écrans (mandats, projets, opportunités), `ccf_event_type` ne contient **pas** de valeur `logistics_step_created` — seulement `logistics_step_updated` (déjà utilisé par le code existant de mise à jour de statut, à ne pas toucher). La création est de toute façon déjà tracée automatiquement par le trigger `audit_logistics_steps` dans `audit_logs`, indépendamment de `business_events`. N'introduisez pas de nouvelle valeur d'ENUM ni de nouvelle migration pour ce ticket — ce n'est pas nécessaire.

**Gestion d'erreur :** surfacer `(err as {message?:string}).message` (pas `e instanceof Error` seul — une `PostgrestError` n'en est pas une, leçon déjà appliquée ailleurs dans ce fichier et dans `documents/page.tsx`).

Après succès : fermer la modale, rafraîchir la liste des étapes (`loadData()` ou équivalent déjà utilisé par les autres modales de ce fichier).

## 4. Ce qu'il ne faut pas faire

- Ne créez aucune migration, aucune nouvelle policy RLS — `logistics_steps_coordinator_insert` suffit déjà, vérifié ci-dessus.
- N'ajoutez pas de valeur `logistics_step_created` à l'ENUM `ccf_event_type` — non nécessaire (voir §3).
- Ne touchez pas à `LogisticsStepCard`, `canEditStep`, ni au reste de l'onglet Logistique — seule la création manque, pas l'édition existante.
- Ne touchez à aucun autre fichier de l'écran S05 (`projets/[id]/page.tsx`) au-delà de l'ajout de ce bouton/modale/état — en particulier ne touchez pas à `InviteOrganizationModal` (§9septvicies/§9octovicies), `handleVRSave`/`INC-S05-02`, ni au calcul `risks`.

## 5. Avant de livrer

PR revue selon `ROCKET_REVIEW_CHECKLIST.md` avant fusion, comme pour chaque écran précédent.
