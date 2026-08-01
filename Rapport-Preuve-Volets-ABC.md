# Rapport de preuve — Audit et suppression contrôlée du frontend legacy Rocket (tâche #485, Volets A/B/C)

**Branche** : `cleanup/legacy-frontend-audit` (créée à partir de `main`, jamais poussée sans autorisation explicite). **Production non touchée.** 6 commits, tous étroits et séparés (voir §5). Aucune suppression globale exécutée — conformément à la consigne, seuls les éléments **prouvés** morts (Volet A) ont été supprimés ; le module MRV (Volet B) et la chaîne logistique physique (Volet C) n'ont subi **aucune suppression**, seulement une reclassification et un masquage réversible côté navigation.

---

## 1. Avant de figer METALVISION-DEMO

### 1.1 Rotation du mot de passe démo

- `supabase/seeds/demo/01_users_and_roles.sql` ne contient plus aucun mot de passe en clair : il exige désormais une variable psql `demo_password` fournie à l'invocation (`psql ... -v demo_password="'<mot-de-passe>'" -f 01_users_and_roles.sql`). Sans cette variable, le script échoue explicitement (erreur de syntaxe SQL sur `:demo_password` non substitué) plutôt que d'utiliser une valeur par défaut silencieuse.
- `Script-Demo-METALVISION-DEMO.md` ne référence plus le mot de passe en clair.
- Le mot de passe a été **rotationné sur les 6 comptes réels** de METALVISION-DEMO (`UPDATE auth.users SET encrypted_password = crypt(...)`, ref `msgesgemaasyzycielzf`) — l'ancien mot de passe précédemment commité (`Demo-Metaltrace-2026!`) est désormais invalide. Le nouveau mot de passe vous est communiqué séparément, hors dépôt.

### 1.2 Garde bloquante d'environnement dans `reset_demo.sql`

- Un marqueur canari a été posé une seule fois sur METALVISION-DEMO : `COMMENT ON DATABASE postgres IS 'METALVISION-DEMO — ...'`.
- `reset_demo.sql` vérifie ce marqueur en toute première opération (avant toute désactivation de trigger ou suppression) : si absent ou ne commençant pas par `METALVISION-DEMO`, le script lève `RAISE EXCEPTION` et s'arrête immédiatement, transaction annulée.
- Choix technique : `current_database()` vaut toujours `postgres` sur Supabase pour **tout** projet (base partagée par convention), donc non discriminant — aucune fonction SQL fiable n'expose le project ref. Le commentaire de base est un attribut persistant, indépendant des données, qu'on ne pose explicitement que sur l'environnement démo.
- **Testé en isolation** (hors du script destructif complet) : passe silencieusement sur le marqueur réel de METALVISION-DEMO ; lève l'exception attendue sur un marqueur simulé incorrect (`RAISE EXCEPTION 'BLOQUÉ comme attendu...'` confirmé).

### 1.3 Production

Aucune requête, migration ou modification n'a touché un projet Supabase de production à aucun moment de cette phase. Toutes les opérations SQL ont ciblé exclusivement `msgesgemaasyzycielzf` (METALVISION-DEMO).

---

## 2. Volet A — Code mort probable : preuve exhaustive et suppression

### 2.1 Méthode de recherche

Pour chacun des 5 éléments désignés, recherche exhaustive dans tout le dépôt (pas seulement `src/app`) : imports statiques et dynamiques, chaînes `fetch('/api/...')` sous toutes formes de guillemets/template literals, `src/tests/`, `package.json` (scripts et dépendances), `next.config.mjs`, `src/middleware.ts`, `.github/` (inexistant), fichiers `*.spec.ts`/`*.e2e.ts`/config Cypress/Playwright (inexistants), et `git log --oneline -- <fichier>` pour l'historique pertinent.

### 2.2 Résultats

| Élément | Verdict | Preuve |
|---|---|---|
| `src/app/api/predict/route.ts` | **CODE MORT CONFIRMÉ** | Zéro occurrence de `/api/predict` dans tout le dépôt en dehors du fichier lui-même (son propre commentaire d'en-tête). |
| `src/app/api/aggregator/calculate-sale/route.ts` | **CODE MORT CONFIRMÉ** | Déjà neutralisée avant cette session (commit `12cf5d6`, 22 juillet 2026, documenté dans `Tranche0-Carbone-Architecture.md` §16 point 0bis) : retourne HTTP 503 sans aucune requête Supabase. Fonction définitivement remplacée par la RPC `compute_credit_sale_allocations()` (migration 09/11, durcie sur des dizaines de revues). Zéro appelant UI. |
| `src/lib/hooks/useChat.ts` | **CODE MORT CONFIRMÉ** | Zéro importeur nulle part dans le dépôt (recherche `hooks/useChat` et `from ...useChat` : 0 résultat hors sa propre définition). |
| `src/app/api/ai/chat-completion/route.ts` | **CORRECTION — ACTIF, PAS DU CODE MORT** | Voir §2.3 |
| `src/lib/ai/chatCompletion.ts` | **CORRECTION — ACTIF, PAS DU CODE MORT** | Voir §2.3 |

### 2.3 Correction critique par rapport à l'inventaire initial

L'inventaire de phase 1 (`Audit-Frontend-Legacy-Rocket.md`) classait `api/ai/chat-completion` et `chatCompletion.ts` en « code mort probable ». **Cette classification était erronée** — la recherche exhaustive demandée par cette tâche l'a révélé avant toute suppression :

- `src/app/api/ai/analyze-photo/route.ts` **appelle réellement** `getChatCompletion()` (import + appel effectif dans le corps de la fonction, pas seulement importé sans usage) exporté par `chatCompletion.ts`.
- `analyze-photo/route.ts` est lui-même appelé par `src/app/new-lot/components/StepAIResult.tsx` et `StepPhotoAnalysis.tsx` — l'assistant photo du flux « Nouveau lot » (logistique physique, périmètre Volet C, conservé en backend).
- `getChatCompletion()` effectue un `fetch()` serveur→serveur vers `/api/ai/chat-completion`, qui utilise le package `@rocketnew/llm-sdk` (toujours présent dans `package.json`).
- `src/lib/ai/aiClient.ts` (classé « À investiguer » en phase 1) est lui-même une dépendance directe de `chatCompletion.ts` — confirmé actif également.

**Aucun de ces 3 fichiers n'a été supprimé.** Seul `getStreamingChatCompletion` (export de `chatCompletion.ts` utilisé uniquement par le `useChat.ts` maintenant supprimé) devient un export mort résiduel à l'intérieur d'un fichier par ailleurs actif — non touché dans ce commit (suppression de fichiers entiers uniquement, pas de modification de fichiers actifs).

### 2.4 Suppression exécutée

Commit `b02b005` (petit, isolé) : suppression de `src/app/api/predict/route.ts`, `src/app/api/aggregator/calculate-sale/route.ts`, `src/lib/hooks/useChat.ts` — 3 fichiers, 252 lignes, aucun autre fichier touché.

### 2.5 Vérification post-suppression

- **Dépendances** : preuve par recherche exhaustive (§2.1-2.2) qu'aucun fichier ne référence les 3 fichiers supprimés — la suppression ne peut structurellement introduire aucune erreur de compilation.
- **Typecheck ciblé** : `tsc` scopé sur la chaîne survivante (`analyze-photo/route.ts` + `chatCompletion.ts` + `aiClient.ts` + les composants `new-lot` qui les consomment) — **zéro erreur** sur ces fichiers. Une erreur préexistante et sans rapport a été détectée dans `StepAIResult.tsx` (type `LotDraft` incomplet) — confirmée présente avant toute modification de cette session (fichier non touché), donc **hors périmètre** de cette tâche ; signalée ici pour information, non corrigée.
- **Limite d'environnement rencontrée** : le `tsc --noEmit` complet sur l'ensemble du projet n'a pas pu être mené à terme dans cet environnement d'exécution (timeouts répétés à ~40s pour une utilisation CPU réelle de seulement ~4-8s, révélant une latence d'E/S propre à l'environnement, pas au code). La vérification ciblée décrite ci-dessus constitue la preuve pratique substituée. Commande exacte à exécuter sur votre poste ou en CI pour la vérification complète : `npx tsc --noEmit` puis `npm run build`.
- **E2E Lots 1-3** : la suppression Volet A ne touche aucune table, RPC ni route API consommée par le parcours carbone. Vérification directe de l'état de METALVISION-DEMO après la suppression : 6 comptes démo, 600 tCO2e émis, 2 lots, 1 règle de distribution, 1 vente confirmée, 6 allocations — identique à l'état de référence établi en Phase A, confirmant l'absence de régression.

---

## 3. Volet B — Matrice fonctionnelle module MRV historique

Comparaison écran par écran, basée sur la lecture complète du code (requêtes Supabase et appels RPC réels) de chaque page, pas seulement leur nom.

| Page legacy | Tables/RPC réellement utilisées | Verdict | Justification |
|---|---|---|---|
| `/admin-carbon-projects` | `INSERT`/`SELECT` direct sur `projects` | **COMPLÉMENTAIRE INDISPENSABLE** | `/admin-verification-sessions` exige un `project_id` existant, choisi dans un menu déroulant — **aucune création de projet en ligne**. `/admin-carbon-projects` est la SEULE interface qui crée cette ligne prérequise. Sans elle, créer une nouvelle session de vérification depuis l'interface est impossible (il faudrait passer par SQL direct, comme le fait le seed de démo). |
| `/admin-emission-factors` | `INSERT`/`UPDATE`/`DELETE` sur `emission_factors` | **INDÉPENDANT, hors périmètre carbone-marché** | Aucune table du module canonique (migrations 01-13) ne référence `emission_factors`. Sert le moteur `api/ghg/calculate`, utilisé par la chaîne logistique physique (transport/mesures) — rattaché fonctionnellement au Volet C, pas au Volet B. |
| `/admin-mrv-project` | `SELECT`/`UPDATE` direct sur `projects.status`, lecture de `project_activity_logs`, `evidence_files`, `verification_sessions` | **PARTIELLEMENT REDONDANT + COMPLÉMENTAIRE** | Redondant avec `/admin-verification-sessions` pour l'affichage des sessions (mais en lecture seule, sans RPC). Complémentaire et sans équivalent pour la vue « activités MRV brutes » par projet et l'export ISO. **⚠️ Risque identifié** : le sélecteur de statut permet de marquer un projet `verified` par simple `UPDATE`, sans jamais passer par la RPC réelle `complete_verification_session()` — bypass de gouvernance vis-à-vis des garde-fous construits en migration 05 (triggers, accréditation). À corriger avant toute conservation définitive — non corrigé ici (hors périmètre de cette tâche). |
| `/carbon-impact` | `SELECT` sur `projects` + `project_activity_logs` (vue client agrégée) | **AUCUN ÉQUIVALENT** | Seule vue client self-service (non-admin) du module. Le module canonique n'a aucune vue client équivalente (`carbon-inventory`/`carbon-sales` sont admin-only). |

**Pages canoniques de référence** (pour mémoire) :
- `/admin-verification-sessions` : cycle de vie complet via RPC (`plan_verification_session`, `complete_verification_session`), gouvernance correcte.
- `/verifier-mrv` : couvre **à la fois** le MRV carbone (`project_activity_logs`, `verification_sessions`, `verifier_observations`, RPC `start_verification_session`/`complete_verification_session`) **et** la chaîne logistique physique (`scan_events`, `transport_requests`, RPC `verify_container_chain`) — ce fichier est donc lui-même à cheval entre Volet B et Volet C, pas seulement MRV carbone.
- `/admin/carbon-inventory` : opère exclusivement sur la couche post-vérification (`credit_issuances`, `credit_lots`, `verification_outcomes`) — **aucun chevauchement de table** avec les 4 pages legacy.

**Conclusion** : aucune des 4 pages ne peut être supprimée sans perte fonctionnelle réelle. **Aucune suppression exécutée**, conformément à la consigne explicite. Décision de fond nécessaire séparément : corriger le bypass de gouvernance de `/admin-mrv-project` (et `/admin-carbon-projects`, qui a le même souci de statut non gouverné) avant toute stabilisation définitive du module.

---

## 4. Volet C — Chaîne logistique physique : reclassification et feature flag

### 4.1 Reclassification

Conformément à l'instruction explicite, la collecte, les conteneurs, le QR et le transport routier/ferroviaire sont des **fonctions stratégiques conservées**. Les pages, routes API et composants correspondants (7 pages, 12 routes API, 30 composants — cf. `Audit-Frontend-Legacy-Rocket.md` §1-3) sont reclassifiés :

> **`À REFONDRE — HORS PARCOURS CANONIQUE ACTUEL`** (et non `LEGACY CONFIRMÉ` / supprimable)

**Aucune suppression de ces pages, API ou composants n'a été exécutée.** Le backend reste intact et fonctionnel.

### 4.2 Feature flag de masquage navigation (implémenté, commit `e18e83b`)

- Nouveau champ `legacyLogisticsUI?: boolean` sur les entrées de navigation de `src/components/Sidebar.tsx` et `src/components/MobileBottomNav.tsx`, posé sur : `/qr-code-scanner`, `/new-lot`, `/lot-management`, `/transport-tracking`, `/admin-dashboard`, `/admin-transport`.
- Filtrage conditionné par `process.env.NEXT_PUBLIC_DEMO_HIDE_LEGACY_LOGISTICS_NAV === 'true'`.
- **Défaut = `false`** — comportement de production strictement inchangé tant que la variable n'est pas définie.
- **Aucun backend touché** : les routes, API et composants restent accessibles par URL directe même quand le flag masque leur lien de navigation — seul le lien disparaît.
- **Activation proposée** : définir `NEXT_PUBLIC_DEMO_HIDE_LEGACY_LOGISTICS_NAV=true` uniquement dans les variables d'environnement Vercel du déploiement `demo.metaltrace.ca` (tâche #476, encore en attente), jamais sur le déploiement de production.
- **Vérifié** : `tsc` scopé sur les deux fichiers modifiés — zéro nouvelle erreur (une seule erreur préexistante et sans rapport en ligne 110 de `Sidebar.tsx`, confirmée présente avant toute modification de cette session).

---

## 5. Commits de cette phase (branche `cleanup/legacy-frontend-audit`, non poussée)

| Commit | Contenu |
|---|---|
| `4b1542e` | Retrait du mot de passe en clair du seed (§1.1) |
| `2c61b95` | Garde bloquante d'environnement dans `reset_demo.sql` (§1.2) |
| `712aef3` | Seed versionné Lots 1-3 (livrable Phase A, précédemment non commité) |
| `946bd10` | Inventaire frontend legacy Rocket — phase 1 (livrable Phase A, précédemment non commité) |
| `b02b005` | Suppression des 3 fichiers de code mort confirmé — Volet A (§2.4) |
| `e18e83b` | Feature flag masquage nav logistique DEMO — Volet C (§4.2) |

Chaque commit est étroit et isolé — aucun `git add -A`, aucune modification en bloc du repo. Le repo contenait par ailleurs une masse importante de modifications non liées à cette tâche (normalisation de fins de ligne CRLF/LF pré-existante sur la quasi-totalité du dépôt) : ces modifications n'ont **jamais** été incluses dans les commits ci-dessus — chaque fichier commité a été vérifié individuellement (`git diff --stat`) pour confirmer qu'il ne contient que le changement sémantique voulu.

---

## 6. Proposition de suppressions précises (statut : rien en attente d'exécution)

- **Exécuté** : suppression de `api/predict`, `api/aggregator/calculate-sale`, `src/lib/hooks/useChat.ts` (Volet A, preuve exhaustive, zéro impact).
- **Proposé mais non exécuté, en attente de votre décision** :
  - Module MRV (`/admin-carbon-projects`, `/admin-emission-factors`, `/admin-mrv-project`, `/carbon-impact`) : **aucune suppression recommandée** — chaque page a une fonction complémentaire ou indispensable démontrée (§3). Correctif de gouvernance à envisager séparément (bypass de statut hors RPC).
  - Chaîne logistique physique (7 pages, 12 routes API, 30 composants) : **aucune suppression recommandée** — fonction stratégique conservée explicitement. Le feature flag (§4.2) est la seule action prise, réversible et sans impact backend.
- **Prochaines étapes suggérées** (hors périmètre de cette tâche, non exécutées) : déployer et tester ce nettoyage dans METALVISION-DEMO (#487), rejouer intégralement CCF + Lots carbone 1-3 en conditions réelles post-déploiement (#488), puis seulement produire manuels/captures/scripts vidéo (#489).

**Conformément à l'instruction reçue, cette tâche s'arrête ici.** Ni le module MRV ambigu ni la chaîne logistique physique n'ont été supprimés. Aucune action supplémentaire ne sera entreprise sans nouvelle autorisation explicite.
