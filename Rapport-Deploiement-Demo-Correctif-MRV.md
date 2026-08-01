# Rapport — Déploiement DEMO et correction de la gouvernance MRV

**Branche :** `cleanup/legacy-frontend-audit` (non fusionnée, non poussée vers `main`)
**Périmètre :** METALVISION-DEMO exclusivement. Production non touchée.
**Statut global :** partiel — voir §7 pour ce qui reste bloqué et pourquoi.

---

## 1. Build

**Statut : ⚠️ Compilation applicative validée conditionnellement ; build Vercel réel encore requis.**

*(Correction apportée à la suite de la revue utilisateur du 2026-08-01 — la formulation initiale « ✅ Réussi » était trop forte. Voir ci-dessous la qualification exacte.)*

`npm run build` (Next.js 15.5.18) a été exécuté sur une copie locale de la branche `cleanup/legacy-frontend-audit`, dans le bac à sable d'exécution de cette session. Le build de la branche exacte, sans modification, a buté sur un blocage réseau : la police `next/font/google` (`DM Sans`) nécessite un accès à `fonts.googleapis.com` à la construction, et ce bac à sable bloque ce domaine par liste blanche (`403 Forbidden`, `X-Proxy-Error: blocked-by-allowlist`). Le build complet (45 routes, zéro erreur webpack) n'a été obtenu qu'après un remplacement **temporaire et non committé** de cet import de police dans la copie de travail locale — jamais dans le dépôt réel (confirmé par `git diff --stat` sur `layout.tsx`, inchangé).

Cela établit que le code compile sans erreur webpack/runtime dans ces conditions contrôlées, mais **ne constitue pas une preuve que le build Vercel réel, avec l'accès réseau complet et les vraies variables DEMO, réussira à l'identique** — c'est précisément ce que le déploiement Vercel doit confirmer. Vercel devrait normalement récupérer la police sans difficulté, mais cela reste à vérifier en conditions réelles (§8, étape « Build réel »).

`next.config.mjs` neutralise `typescript.ignoreBuildErrors` et `eslint.ignoreDuringBuilds` — aucune des 24 erreurs TypeScript préexistantes ne peut donc faire échouer `next build`, sur le bac à sable comme sur Vercel. Voir §10 pour le chantier de stabilisation TypeScript identifié pour la suite (hors périmètre de la preview DEMO).

## 2. Typecheck

**Statut : ✅ Aucune régression introduite**

`npx tsc --noEmit` exécuté sur l'intégralité du projet. Le jeu d'erreurs préexistantes (24 erreurs, dont celle de `StepAIResult.tsx` explicitement mentionnée dans la demande) est strictement identique avant et après les modifications de cette phase — aucune n'est bloquante pour le build (cf. §1), et aucune nouvelle erreur n'a été introduite par le correctif de gouvernance MRV (`admin-mrv-project/page.tsx`) ni par le feature flag de navigation.

## 3. Navigation (masquage logistique DEMO)

**Statut : ⏳ Bloqué — nécessite un déploiement live (voir §8)**

Le code du feature flag `NEXT_PUBLIC_DEMO_HIDE_LEGACY_LOGISTICS_NAV` est en place dans `Sidebar.tsx` et `MobileBottomNav.tsx` (commit `e18e83b`) et validé statiquement (typecheck + build), mais son comportement réel dans le navigateur ne peut être vérifié qu'une fois la variable activée sur un déploiement DEMO effectif. Non testé dans cette session faute d'URL déployée.

## 4. Six rôles / comptes de démonstration

**Statut : ⏳ Bloqué — nécessite un déploiement live (voir §8)**

Aucun test de connexion ou de garde d'accès par rôle n'a pu être rejoué dans un navigateur réel dans cette phase, pour la même raison qu'au §3.

## 5. Parcours CCF et Lots carbone 1 à 3

**Statut : ⏳ Bloqué — nécessite un déploiement live (voir §8)**

Le parcours CCF et les Lots 1-3 avaient déjà été validés end-to-end lors de phases antérieures (tâches #483, #458). Ils n'ont pas été rejoués dans cette phase spécifiquement sur le déploiement `cleanup/legacy-frontend-audit`, faute d'URL déployée. Aucune régression n'est attendue : les suppressions du Volet A (`api/predict`, `api/aggregator/calculate-sale`, `useChat.ts`) et le feature flag de navigation sont sans lien de dépendance avec le code CCF/Lots carbone (voir Volets A/B du rapport précédent), mais cela reste à confirmer en conditions réelles.

## 6. Cycle reset_demo → reseed

**Statut : ⏳ Reporté après le parcours navigateur (par choix, conforme à la séquence demandée)**

Non exécuté en tant que cycle complet dans cette phase, puisque l'instruction le place après le parcours navigateur CCF/Lots (§5), lui-même bloqué. Voir §9 pour une note sur des données de test SQL transitoires créées puis retirées dans le cadre du §6bis ci-dessous.

## 6bis. Note — nettoyage des artefacts de test SQL

Pour rejouer et prouver la chaîne RPC de vérification (§6 ci-dessous), une session de vérification, une preuve d'activité et un résultat de vérification synthétiques ont été créés directement en SQL (impersonation JWT) sur METALVISION-DEMO. Une fois la preuve établie, **ces trois enregistrements ont été explicitement retirés** (par la même méthode contrôlée de désactivation temporaire des triggers append-only qu'utilise `reset_demo.sql`, jamais par un contournement générique). METALVISION-DEMO a été vérifié revenu à son état canonique exact (session #007 et ses deux activités d'origine intacts, aucun résidu). Aucune donnée réelle ou de production n'a été touchée.

## 7. Correction de la gouvernance MRV — `/admin-mrv-project` et `/admin-carbon-projects`

**Statut : ✅ Corrigé, committé (`7121daf`), et prouvé par une exécution RPC réelle**

### Constat
`admin-mrv-project/page.tsx` permettait à un administrateur de placer directement un projet au statut `verified` via un simple `UPDATE projects.status`, sans aucun lien avec la RPC canonique `complete_verification_session()`. Lecture complète de cette RPC (via `pg_get_functiondef`) : elle n'écrit **jamais** `projects.status` — elle ne touche que `verification_outcomes` et `verification_sessions.status`. Il n'existait donc aucune voie légitime vers `verified` pour ce champ.

`admin-carbon-projects/page.tsx` a été réaudité intégralement (grep ciblé après restauration propre du fichier) : son unique écriture de statut est la valeur fixe `'draft'` à la création d'un projet. **Aucun contournement — aucune modification nécessaire sur ce fichier.**

### Correctif appliqué (`admin-mrv-project/page.tsx`)
- Retrait de l'option `verified` du `<select>` de statut (seuls `draft`/`active` restent modifiables directement).
- Garde défensive dans `updateStatus()` : toute valeur hors `draft`/`active` est rejetée, même en cas de contournement de l'UI.
- Ajout d'un badge « Vérifié » en lecture seule, calculé depuis `verification_outcomes` (`status='active'`), donnée produite exclusivement par `complete_verification_session()`.
- Aucune fonction existante retirée : création de projet, activités, preuves et export ISO restent intacts.

### Preuve — cycle réel `planned → in_progress → completed` après correctif
Une session de vérification a été rejouée de bout en bout sur METALVISION-DEMO via impersonation JWT (admin puis vérificateur accrédité), en respectant scrupuleusement les mêmes contraintes de gouvernance que l'interface (accréditation active, preuve `verification_report` avec `file_hash`, période non chevauchante, etc.) :

| Étape | RPC / action | Résultat |
|---|---|---|
| 1 | `INSERT verification_sessions` (statut `planned`) par l'admin | ✅ |
| 2 | `plan_verification_session()` (période + vérificateur accrédité) | ✅ |
| 3 | `start_verification_session()` par le vérificateur | ✅ statut → `in_progress` |
| 4 | `complete_verification_session()` avec preuve valide (150,0000 tCO2e calculé = vérifié, 145,0000 éligible) | ✅ statut session → `completed`, résultat `verification_outcomes.status='active'` inséré |

Confirmation post-exécution : `public.projects.status` du projet concerné **n'a subi aucune écriture** par cette RPC (valeur inchangée avant/après) — la preuve empirique rejoint la lecture statique du code de la RPC. Le badge « Vérifié » de la page corrigée se serait affiché correctement à partir de ce seul résultat actif, sans dépendre du champ mutable.

Les artefacts SQL synthétiques de ce test ont ensuite été retirés (§6bis) — aucune trace résiduelle dans METALVISION-DEMO.

---

## 8. Débloquer les sections §3, §4, §5 — action requise de votre part

Je n'ai pas d'accès `git push` ni d'identifiants Vercel dans cet environnement d'exécution — cette étape doit être exécutée par vous. Séquence retenue (validée en revue) :

**Avant le `git push`, vérifier l'isolation des environnements :**
1. Vérifier le projet Vercel actuel de production : confirmer que ses variables **Preview** ne pointent pas vers le Supabase de production.
2. Si c'est le cas, désactiver le déploiement automatique de preview pour cette branche, ou définir des variables spécifiques à la branche.
3. Créer de préférence un projet Vercel distinct dédié : **METALVISION-DEMO-WEB**.

**Pousser uniquement la branche (jamais `main`) :**
```
git checkout cleanup/legacy-frontend-audit
git status
git log --oneline -8
git push -u origin cleanup/legacy-frontend-audit
```

**Configuration du projet Vercel DEMO — variables minimales :**
```
NEXT_PUBLIC_SUPABASE_URL=<URL_METALVISION_DEMO>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<ANON_KEY_METALVISION_DEMO>
NEXT_PUBLIC_DEMO_HIDE_LEGACY_LOGISTICS_NAV=true
```
Si utilisées par l'application, également en valeurs DEMO : `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_APP_URL`. Courriels, webhooks, transporteurs, paiements et autres intégrations externes : désactivés ou dirigés vers des destinations de test. Ne pas rattacher `demo.metaltrace.ca` à ce stade — utiliser l'URL Preview Vercel jusqu'à la fin des tests.

**Donnez-moi l'URL Preview obtenue** — je pourrai alors reprendre la régression dans l'ordre : build réel, séparation des environnements (données DEMO uniquement, aucun appel vers la production, flag de navigation actif, logistique masquée du menu mais toujours joignable par URL directe), six comptes, gouvernance MRV en conditions réelles (aucune option `verified` au sélecteur, badge « Vérifié » dérivé d'un `verification_outcome` actif, tentative manuelle rejetée), parcours fonctionnels complets (organisation → capacité → opportunité → projet CCF → activité MRV → vérification → émission → lots → règle de distribution → vente → allocations → règlement), 404 sur `/api/predict` et `/api/aggregator/calculate-sale`, puis le cycle final `reset_demo.sql → 01…06` avec vérification de l'état canonique exact (6 comptes, 600 tCO2e émises, 2 lots, 1 règle active, 1 vente confirmée, 6 allocations).

## 9. Rappel — arrêt avant fusion

Aucun merge ni push vers `main` n'a été effectué ni ne sera effectué sans votre autorisation explicite. La fusion, le redéploiement DEMO depuis `main`, le rattachement de `demo.metaltrace.ca` et le gel de version n'interviendront qu'après un rapport final confirmant la réussite de tous les contrôles ci-dessus et votre autorisation explicite.

## 10. Chantier différé — stabilisation TypeScript (avant pilote commercial)

Point relevé en revue, hors périmètre de la preview DEMO (la branche n'introduit aucune nouvelle erreur — voir §2) mais à traiter avant le pilote commercial fermé (tâche #465) :

- Corriger les 24 erreurs TypeScript préexistantes du projet.
- Réactiver `typescript.ignoreBuildErrors: false` dans `next.config.mjs` une fois corrigées, pour que le build échoue réellement en cas de régression de typage.
- Exiger un `tsc --noEmit` propre en CI.

Non commencé — consigné ici pour suivi, à planifier après validation complète de la preview DEMO.
