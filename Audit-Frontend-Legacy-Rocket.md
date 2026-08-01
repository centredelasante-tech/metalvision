# Audit et suppression contrôlée du frontend legacy Rocket — Phase 1 : Inventaire

**Statut** : inventaire initial (tâche #484). Aucune suppression effectuée. Conformément à la consigne, aucun fichier classé `LEGACY CONFIRMÉ` ci-dessous ne doit être supprimé avant que la tâche #485 (démonstration du remplacement/non-usage) ne l'ait confirmé élément par élément.

**Méthodologie** : pour chaque route/composant/hook/route API, trois signaux ont été croisés :
1. **Rattachement à la navigation réelle** — présence dans `src/components/Sidebar.tsx` (deux jeux de liens : nav « employé » et nav « admin ») ou dans les liens du hub `/admin` (`src/app/admin/page.tsx`).
2. **Références croisées dans le code** — `grep` des chemins d'import et des chaînes d'URL (`fetch('/api/...')`, `href=`) à travers `src/app` et `src/lib`.
3. **Historique du projet** — connaissance directe de ce qui a été construit/durci pendant les sprints Rocket S01-S10 (CCF) et les Lots 1-3 (marché carbone, migrations 01-13), versus ce qui appartient à la version antérieure du produit (logistique physique conteneurs/QR/transport, module MRV ISO 14064-2 par projet individuel).

Ce croisement suffit à trancher la majorité des cas, mais **pas tous** — certains éléments légitimement ambigus sont classés `À INVESTIGUER` plutôt que tranchés par optimisme.

---

## 1. Pages (`src/app/**/page.tsx`) — 33 routes

### CANONIQUE (produit CCF + marché carbone actuel, construit/durci S01-S10 + Lots 1-3)

| Route | Rattachement nav | Note |
|---|---|---|
| `/` | Sidebar (employé + admin) | Dashboard complet, S01 |
| `/organizations`, `/organizations/[id]`, `/organizations/new` | Sidebar (admin) | Module organisations CCF |
| `/capacites` | Sidebar (les deux) | |
| `/opportunities` | Sidebar (les deux) | |
| `/mandats` | Sidebar (les deux) | |
| `/projets`, `/projets/[id]` | Sidebar (les deux) | S05 |
| `/documents` | Sidebar (les deux) | S07 |
| `/evenements` | Sidebar (les deux) | S08 |
| `/cockpit` | Sidebar (les deux) | S09 |
| `/admin` | Sidebar (admin) | Hub S10 |
| `/admin-verification-sessions` | Sidebar (admin, groupe « mrv ») | Coordinateur MRV — durci Lot 1 |
| `/verifier-mrv` | Sidebar (groupe « vérification ») | Vue vérificateur accrédité |
| `/admin/carbon-inventory` | Lien direct depuis `/admin` | Lot 1 (résultats → émissions → lots) |
| `/admin/carbon-sales` | Lien direct depuis `/admin` | Lot 3 (cockpit de ventes) |
| `/admin/regroupements/[aggregatorId]/distribution` | Lien direct depuis `/admin` (actuellement codé en dur vers un regroupement de test) | Lot 2 (gouvernance distribution) |
| `/login`, `/inscription` | Points d'entrée auth, hors nav principale par nature | |
| `/invitation/[token]` | Accédé via lien d'invitation e-mail, hors nav par nature | |

**Point d'attention non-bloquant** : le lien vers `/admin/regroupements/.../distribution` dans `/admin/page.tsx` pointe vers un UUID de regroupement de test codé en dur (`11111111-...`), avec le libellé « (test) ». Ce n'est pas un problème de legacy, mais un point à corriger avant la démonstration ministérielle si le hub `/admin` doit lister dynamiquement les vrais regroupements.

### LEGACY CONFIRMÉ (produit antérieur — logistique physique conteneurs/QR/transport)

| Route | Rattachement nav | Justification |
|---|---|---|
| `/qr-code-scanner` | Sidebar (employé) | Scanner de conteneurs — produit pré-CCF |
| `/new-lot` | Sidebar (employé) | Assistant de création de lot avec analyse IA photo — produit pré-CCF |
| `/lot-management` | Sidebar (employé + admin, 2 entrées) | Gestion de lots/conteneurs — produit pré-CCF |
| `/transport-tracking` | Sidebar (employé) | Suivi transport — produit pré-CCF |
| `/container-detail`, `/container-detail/[id]` | Reachable depuis lot-management/QR scanner (non vérifié en détail, mais même famille) | |
| `/admin-dashboard` | Sidebar (admin) | Dashboard admin de l'ancien produit, distinct de `/` (S01) |
| `/admin-transport` | Sidebar (admin) | Administration transport pré-CCF |

Ces 7 routes forment un ensemble cohérent et toujours branché à la navigation (donc pas du code mort au sens strict), mais appartiennent à une génération de produit antérieure à CCF/carbone. La question de savoir si elles doivent être conservées (produit encore vendu ?), simplifiées, ou retirées de la navigation en attendant suppression est une décision produit, pas seulement technique — à trancher avant la phase #486.

### À INVESTIGUER (module MRV legacy — ISO 14064-2 par projet individuel)

| Route | Rattachement nav | Pourquoi ambigu |
|---|---|---|
| `/admin-carbon-projects` | Sidebar (admin, groupe « mrv ») + lien direct `/admin` | Liste de projets MRV individuels (ISO 14064-2), distincte du nouveau modèle carbone par regroupement (Lots 1-3) |
| `/admin-emission-factors` | Sidebar (admin, groupe « mrv ») | Gestion de facteurs d'émission — utilité pour le nouveau module non confirmée |
| `/admin-mrv-project` (accédée via `?id=`, pas de dossier `[id]`) | Reachable depuis `/admin-carbon-projects` | Détail d'un projet MRV individuel |
| `/carbon-impact` | Sidebar (employé, groupe « carbone ») | Vue impact carbone — chevauchement potentiel avec `/admin/carbon-inventory` |

**Pourquoi ne pas classer directement en LEGACY CONFIRMÉ** : les tables MRV sous-jacentes (`projects`, `project_activity_logs`, `evidence_files`, `verification_sessions` — le module « MRV legacy ») ont dû être **reconstruites** en cours de session (tâches #41/#42, incident INC-DATA-01) précisément parce qu'elles étaient « encore utilisées par le code ». Le nouveau module carbone (migrations 01-13, Lots 1-3) **s'appuie lui-même sur ces mêmes tables** (`verification_sessions`, `project_activity_logs`) comme fondation de la chaîne de vérification — voir `ccf_mrv_project_links`, qui existe justement pour relier un projet CCF à un projet MRV legacy. Autrement dit, le module MRV n'est pas mort : il est le socle sur lequel le nouveau module carbone est bâti. La question réelle n'est donc pas « ce module est-il utilisé ? » (oui) mais « ces 4 pages exposent-elles une fonctionnalité redondante avec `/admin-verification-sessions` + `/verifier-mrv` + `/admin/carbon-inventory`, ou une granularité complémentaire (suivi ISO 14064-2 projet par projet) qui n'a pas d'équivalent dans le nouveau module ? » — nécessite une comparaison fonctionnelle écran par écran, hors périmètre d'un simple grep.

---

## 2. Routes API (`src/app/api/**/route.ts`) — 19 routes

### CANONIQUE

| Route | Appelée par |
|---|---|
| `api/projects/[id]/iso-report` | `/admin-mrv-project`, `/carbon-impact` (classées À INVESTIGUER ci-dessus — donc ce statut est transitivement lié) |
| `api/projects/[id]/log-activity` | `api/transport/internal-create`, `api/measurements/confirm` (server-to-server) |
| `api/ghg/calculate` | `api/measurements/confirm`, `api/transport/internal-create` |

### LEGACY CONFIRMÉ (chaîne logistique physique)

| Route | Appelée par |
|---|---|
| `api/transport/create`, `api/transport/internal-create`, `api/transport/complete`, `api/transport/calculate-distance`, `api/transport/update-status`, `api/transport/poll-status`, `api/transport/[id]/status` | `/admin-transport`, `/transport-tracking` |
| `api/external/grouperobert/create-shipment`, `api/external/grouperobert/shipment-status` | Intégration transporteur externe, chaîne transport legacy |
| `api/measurements/confirm` | Chaîne conteneurs/lots legacy |
| `api/stats/update` | Non retracée à un appelant frontend direct — probablement déclenchée server-to-server par la chaîne transport/mesures ; à confirmer en #485 |
| `api/metals-price` | `/admin-dashboard` (legacy) |
| `api/ai/analyze-photo` | `/new-lot` (analyse photo IA du lot, legacy) |

### LEGACY CONFIRMÉ — code mort probable (aucun appelant trouvé)

| Route | Constat |
|---|---|
| `api/aggregator/calculate-sale` | **Aucune référence** dans `src/app` (ni `fetch`, ni import). Calcule vraisemblablement une répartition de vente — fonction aujourd'hui assurée par la RPC Postgres `compute_credit_sale_allocations()` (migration 09/11, durcie sur des dizaines de revues cette session). Candidat fort à un doublon abandonné antérieur à la RPC réelle. **À confirmer par grep du nom de fichier/fonction dans l'historique git avant suppression**, mais aucun signal d'usage actuel. |
| `api/ai/chat-completion` | **Aucune référence** dans `src/app`. Seul `src/lib/ai/chatCompletion.ts` l'implémente, et ce fichier n'est lui-même importé nulle part dans `src/app`. Chaîne complète orpheline (route + lib). |
| `api/predict` | **Aucune référence** `fetch('/api/predict')` trouvée dans `src/app`. À confirmer. |

---

## 3. Composants

### CANONIQUE — layout et UI génériques (utilisés par toutes les pages, legacy comme CCF)

`src/components/AppLayout.tsx`, `MobileBottomNav.tsx`, `Sidebar.tsx`, `Topbar.tsx`, `ObjectTimeline.tsx`, et tout `src/components/ui/*` (AppIcon, AppImage, AppLogo, EmptyState, LoadingSkeleton, MetalBadge, MetricCard, QRCodeModal, StatusBadge). Ne pas toucher — même après suppression de pages legacy, ce sont des primitives partagées. `MetalBadge` et `QRCodeModal` en particulier ne seront à réévaluer qu'**après** confirmation du sort des pages legacy qui les utilisent.

### CANONIQUE — spécifiques au Dashboard CCF (S01)

`src/app/components/CCFDashboardSection.tsx`, `ClientDashboardContent.tsx`, `ClientKPIGrid.tsx`, `ClientQuickActions.tsx`

### À INVESTIGUER — `src/app/components/ContainerGrid.tsx`, `RecentLotsTable.tsx`

Dans le même dossier que les composants CCF canoniques ci-dessus, mais leurs noms suggèrent un usage pour le Dashboard legacy (conteneurs/lots) plutôt que CCF — à vérifier quel(s) fichier(s) les importent avant classification définitive.

### LEGACY CONFIRMÉ — composants scoping une page legacy

Tous les composants sous `src/app/admin-dashboard/components/`, `src/app/container-detail/components/`, `src/app/lot-management/components/`, `src/app/new-lot/components/`, `src/app/qr-code-scanner/components/` (30 fichiers au total) — chacun n'est importé que par sa page parente (vérifié par grep), donc hérite directement du statut de cette page.

---

## 4. Hooks et libs

| Élément | Statut | Note |
|---|---|---|
| `src/lib/hooks/useChat.ts` | LEGACY CONFIRMÉ — code mort probable | Aucun composant ne l'importe (grep négatif) |
| `src/lib/ai/chatCompletion.ts` | LEGACY CONFIRMÉ — code mort probable | Utilisé uniquement par `api/ai/chat-completion` (lui-même orphelin) |
| `src/lib/ai/aiClient.ts` | À INVESTIGUER | Utilisé par `api/ai/analyze-photo` (legacy actif) — à confirmer s'il sert autre chose |
| `src/lib/supabase/client.tsx`, `server.tsx` | CANONIQUE | Fondation Supabase utilisée partout, CCF comme legacy |

**Contexts** : aucun fichier de contexte React n'existe dans le projet (`AuthContext` mentionné uniquement dans des commentaires historiques, cf. tâche #50 — la dette technique a été résolue en n'utilisant PAS de contexte). Rien à inventorier dans cette catégorie.

---

## Résumé chiffré

| Classification | Pages | Routes API | Composants (hors UI générique) |
|---|---|---|---|
| CANONIQUE | 17 | 3 | 4 |
| LEGACY CONFIRMÉ | 7 | 12 | 30 |
| À INVESTIGUER | 4 | 1 (`stats/update`) | 2 (`ContainerGrid`, `RecentLotsTable`) |
| LEGACY CONFIRMÉ — code mort probable | — | 3 (`aggregator/calculate-sale`, `ai/chat-completion`, `predict`) + 2 libs (`useChat.ts`, `chatCompletion.ts`) | — |

---

## Prochaine étape (tâche #485)

Pour chaque ligne `LEGACY CONFIRMÉ` et `À INVESTIGUER` ci-dessus, produire la preuve formelle avant toute suppression :
1. **Code mort probable** (`aggregator/calculate-sale`, `ai/chat-completion`, `predict`, `useChat.ts`) : confirmer par recherche exhaustive (y compris chaînes dynamiques, config Next.js, tests) qu'aucun appel n'existe nulle part dans le dépôt — pas seulement `src/app`.
2. **Module MRV legacy** (`/admin-carbon-projects`, `/admin-emission-factors`, `/admin-mrv-project`, `/carbon-impact`) : comparaison fonctionnelle écran par écran avec le nouveau module carbone pour déterminer redondance réelle vs. complémentarité légitime.
3. **Chaîne logistique physique** (7 pages + 12 routes API + 30 composants) : décision produit à obtenir (ce volet est-il encore commercialisé / utilisé par de vrais clients ?) avant tout arbitrage technique — un grep ne peut pas répondre à cette question.

Aucune suppression ne doit être exécutée avant que ces trois points soient tranchés.
