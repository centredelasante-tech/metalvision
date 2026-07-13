# Brief Rocket — E08-T01/T02 (Création de projet + invitation d'organisation)

**Contexte :** en testant le parcours CCF complet de bout en bout, on a découvert que **E08-T01** (backlog technique v1.0, priorité **MUST/P0**, US-007 : « Créer projet à partir d'une opportunité qualifiée ») **n'existe nulle part dans le code livré** — ni bouton, ni formulaire, ni RPC. Le seul projet existant en production (« Projet CCF-2026-Q3 ») a été inséré directement en SQL comme donnée de démonstration, jamais créé via l'application. Idem pour l'invitation d'une organisation à un projet (E08-T02) : `/projets/:id` sait déjà **accepter/refuser** une invitation existante (`accept_project_invitation`/`decline_project_invitation`, voir S06), mais rien ne peut **créer** cette invitation en premier lieu.

**Bonne nouvelle : le backend est déjà entièrement prêt, aucune migration n'est nécessaire.** Les policies RLS suivantes existent déjà et couvrent exactement ce dont ce ticket a besoin (vérifié en lisant `20260710999000_reset_and_reapply_ccf_full.sql`) :
- `ccf_projects_coordinator_admin_insert` : `is_organization_owner(coordinator_org_id)` — un admin peut créer un projet dont son organisation est coordonnatrice.
- `project_participants_coordinator_insert` : le coordonnateur du projet peut insérer des lignes `project_participants` (y compris pour d'autres organisations).
- `mandates_issuer_admin_insert` : `is_organization_owner(issuer_org_id)` — déjà utilisée par `/mandats`, réutilisable telle quelle.

**Avant de commencer : `git pull`/`git reset --hard origin/main`.** Comme pour chaque écran précédent, la revue de ce PR fera un diff fichier par fichier de la branche complète.

---

## 1. Partie A — Créer un projet depuis une opportunité qualifiée (E08-T01)

**Où :** sur `/opportunities`, dans le panneau de détail d'une opportunité (celui qui affiche « Capacités candidates »), ajouter un bouton **« Convertir en projet »**, visible seulement quand :
- `opportunity.status === 'qualified'`
- l'utilisateur courant est admin de l'organisation coordinatrice (`coordinator_org_id`)
- au moins une ligne `opportunity_capabilities` avec `status = 'active'` existe pour cette opportunité (sinon, afficher un message « Associez au moins une capacité candidate avant de convertir »)

**Formulaire (modale)** : titre du projet (pré-rempli avec `opportunity.title`, modifiable), `start_date` optionnelle, `target_end_date` optionnelle.

**À la soumission, dans cet ordre (transitions manuelles, pas de RPC — même convention que `documents/page.tsx` pour `draft→submitted` ou `mandats/page.tsx` pour l'envoi d'un mandat) :**
1. `INSERT ccf_projects` : `opportunity_id`, `title`, `coordinator_org_id` (= l'organisation coordinatrice de l'opportunité), `phase` et `status` omis (défaut `'draft'` des deux côtés).
2. `INSERT project_participants` pour l'organisation coordinatrice elle-même : `project_id` (nouveau), `organization_id = coordinator_org_id`, `project_role = 'coordonnateur'`, `status = 'active'` (le coordonnateur n'a pas besoin d'« accepter » sa propre participation), `mandate_id` laissé `NULL`.
3. `UPDATE opportunities SET status = 'converted' WHERE id = opportunity_id`.
4. `INSERT business_events` manuel : `event_type: 'project_created'`, `object_type: 'project'`, `object_id: <nouveau project.id>`, `actor_id`, `organization_id: coordinator_org_id`, `payload: { title, opportunity_id }`.
5. Rediriger vers `/projets/<nouveau id>`.

**Gestion d'erreur :** si une étape échoue après la création du projet (étape 1 réussie mais 2/3/4 échouent), ne pas laisser un projet orphelin sans participant coordonnateur silencieusement — afficher l'erreur réelle (voir le correctif récent sur `/documents` : ne pas se fier à `e instanceof Error` seul, une `PostgrestError` n'en est pas une).

## 2. Partie B — Inviter une organisation à un projet existant (E08-T02, compagnon indispensable de la partie A)

**Où :** sur `/projets/:id`, section participants, ajouter un bouton **« Inviter une organisation »**, visible seulement si l'utilisateur courant est admin de `project.coordinator_org_id`.

**Formulaire (modale)** :
- Organisation à inviter (liste déroulante — toutes les organisations sauf celle du coordonnateur ; si le temps le permet, prioriser dans la liste les organisations dont une capacité est associée à l'opportunité source du projet, via `opportunity_capabilities` → `capabilities.organization_id`, mais ce n'est pas bloquant si non fait).
- Portée du mandat (`mandate_scope`) — réutiliser le même sélecteur que `/mandats` (`gouvernance, operationnel, financier, technique, verification, ia`), défaut `operationnel`.
- Actions autorisées (`permissions.actions[]`) — réutiliser le même multi-select que `/mandats` (catalogue `mandate_actions`, déjà 4 fois construit dans ce projet, ne pas le reconstruire différemment). **`accept_project_invitation` doit être pré-coché et non désélectionnable** — un mandat de ce type sans cette action n'aurait aucun sens (l'organisation invitée ne pourrait jamais accepter).
- Dates optionnelles (`start_date`/`end_date`).

**À la soumission, dans cet ordre :**
1. `INSERT mandates` : `issuer_org_id = project.coordinator_org_id`, `receiver_org_id` (organisation choisie), `mandate_scope`, `permissions: { actions: [...] }`, `status: 'pending_acceptance'` **envoyé explicitement dès la création** (contrairement à `/mandats` où un mandat générique naît `draft` et nécessite un « Envoyer » séparé — ici, l'action « Inviter » doit être un geste unique et direct, pas un mandat brouillon qu'il faudrait encore envoyer manuellement). `start_date`/`end_date` si fournis.
2. `INSERT project_participants` : `project_id`, `organization_id` (organisation choisie), `project_role: 'contributeur'`, `status: 'invited'`, `mandate_id: <id du mandat créé à l'étape 1>`.
3. `INSERT business_events` manuel : `event_type: 'mandate_issued'`, `object_type: 'mandate'`, `object_id: <mandate.id>`, `actor_id`, `organization_id: project.coordinator_org_id`, `payload: { receiver_org_id, project_id, scope }` — même structure que `handleSend` dans `mandats/page.tsx`, ne pas la dupliquer différemment.

**Important — ne pas casser l'existant :** `/projets/:id` sait déjà lire un `project_participants.mandate_id` et afficher les boutons Accepter/Refuser (`handleAcceptInvitation`/`handleDeclineInvitation`, RPCs `accept_project_invitation`/`decline_project_invitation`). Ne touchez à aucune de ces deux fonctions ni à leur RLS — seule la création de l'invitation manque, pas sa réception.

## 3. Ce qu'il ne faut pas faire

- Ne créez aucune migration, aucune nouvelle table, aucune nouvelle policy RLS — tout est déjà en place et vérifié (voir contexte ci-dessus).
- N'introduisez pas de nouveau statut `opportunities`/`ccf_projects`/`mandates` — les ENUM/CHECK existants (`draft/qualified/converted/closed/archived` pour opportunités, `draft/active/paused/closed/archived` pour projets) couvrent déjà ce ticket.
- Ne dupliquez pas la logique d'acceptation/refus déjà existante dans `/projets/:id` ou `/mandats`.
- Ne créez pas de mandat avec un tableau `actions` vide — le trigger `validate_mandate_permissions` le refusera de toute façon (message d'erreur à afficher clairement, pas en brut).

## 4. Avant de livrer

PR revue selon `ROCKET_REVIEW_CHECKLIST.md` avant fusion, comme pour chaque écran précédent.
