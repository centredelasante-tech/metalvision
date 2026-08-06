# Chronologie réelle des migrations RLS provisoires (recursion project_participants / opportunities)

Ce document existe parce que 4 fichiers de migration dans `supabase/migrations/` ont un nom
(donc un timestamp de préfixe) qui NE correspond PAS à leur date réelle d'écriture/commit, ni
à la version enregistrée côté Supabase. Il sert de table de correspondance unique, référencée
depuis le bandeau en tête de chacun des 2 fichiers concernés par cette anomalie.

Aucun fichier n'a été renommé ni supprimé : décision explicite de conserver les noms tels
quels pour ne pas réécrire l'historique git déjà poussé.

## Table de correspondance

| Fichier (nom réel, timestamp de préfixe trompeur) | Commit | Date de commit réelle | Nom distant Supabase (METALVISION-DEMO) | Version distante | Statut |
|---|---|---|---|---|---|
| `20260713020000_fix_rls_recursion_project_participants_ccf_projects.sql` | `4f84023` | 2026-08-01 18:26:30 -0400 | `fix_rls_recursion_project_participants_ccf_projects` | `20260801222141` | SUPERSEDÉE par `20260801010000` |
| `20260713030000_fix_rls_recursion_opportunities_opp_cap.sql` | `4f84023` | 2026-08-01 18:26:30 -0400 | `fix_rls_recursion_opportunities_opp_cap` | `20260801222508` | SUPERSEDÉE par `20260801020000` |
| `20260801010000_reconcile_project_participants_ccf_projects_with_production.sql` | `2a80e75` (originale) puis corrigée le 2026-08-06 (voir §Divergence ci-dessous) | 2026-08-01 18:57:47 -0400 (originale) | — (brouillon, jamais appliquée en production) | — | **CORRIGÉE 2026-08-06** — non applicable en production dans sa forme originale |
| `20260801020000_reconcile_opportunities_opp_cap_with_production.sql` | `2a80e75` | 2026-08-01 18:57:47 -0400 | — (brouillon, jamais appliquée) | — | BROUILLON — NON APPLIQUÉE, no-op confirmé (aucune correction requise) |

## Empreintes SHA-256 (contenu au moment de la rédaction de ce document)

```
fbefef07eca496830b4608d3669f0882570a083b98a19454c92ce5974b344fb  20260713020000_fix_rls_recursion_project_participants_ccf_projects.sql
e06e409783d47a04119b4e7554cc6b632f74ac5ecdd36dd6f76aba292f5e048  20260713030000_fix_rls_recursion_opportunities_opp_cap.sql
d7ea635b9742c482b78a7d30a06d2e008f31f2d2d941367ad1c9fd46ba15d310  20260801010000_reconcile_project_participants_ccf_projects_with_production.sql  (version CORRIGÉE, 2026-08-06 — voir §Divergence)
e9af6d51350349b1c2c2628ede516b4c20e01dca31ee82257475cf9ee1e3157  20260801020000_reconcile_opportunities_opp_cap_with_production.sql
```

Recalcul (à exécuter depuis la racine du dépôt) :

```bash
sha256sum supabase/migrations/20260713020000_fix_rls_recursion_project_participants_ccf_projects.sql \
          supabase/migrations/20260713030000_fix_rls_recursion_opportunities_opp_cap.sql \
          supabase/migrations/20260801010000_reconcile_project_participants_ccf_projects_with_production.sql \
          supabase/migrations/20260801020000_reconcile_opportunities_opp_cap_with_production.sql
```

## Divergence — `20260801010000` : version appliquée à DEMO vs version corrigée du dépôt

**Contexte** : lors du GATE de préparation du déploiement production (2026-08-06, lecture seule),
une vérification live directe contre `dlbewgsoboaycbpypcus` a établi que l'affirmation de
l'en-tête original de `20260801010000` — « `ccf_projects_via_user_project_ids` ABSENTE en
production » — était **fausse**. Cette policy est présente et active en production. Le STEP 3
original de ce fichier (`DROP POLICY IF EXISTS "ccf_projects_via_user_project_ids"`) aurait donc
réellement supprimé une policy RLS active si le fichier avait été appliqué tel quel à la
production, contrairement à sa présentation en simple formalité documentaire.

**Décision** (utilisateur, 2026-08-06) : corriger le fichier dans le dépôt en retirant ce STEP 3,
et documenter ici l'écart qui en résulte avec ce qui a déjà été appliqué à DEMO.

| | Version ORIGINALE (celle appliquée à DEMO) | Version CORRIGÉE (dans le dépôt depuis 2026-08-06) |
|---|---|---|
| Commit | `2a80e75` | commit de correction, voir `git log` sur ce fichier |
| SHA-256 | `215d40e131e75675c46a93fb5654daecf42e0b70a079c33dd2bb8b9bef09c20` | `d7ea635b9742c482b78a7d30a06d2e008f31f2d2d941367ad1c9fd46ba15d310` |
| Contient le STEP 3 (`DROP POLICY ccf_projects_via_user_project_ids`) | **Oui** | **Non — retiré** |
| Appliquée sur METALVISION-DEMO (`msgesgemaasyzycielzf`) | **Oui**, définitivement (voir ADR-MVP.md, tâche de réconciliation RLS) | Non applicable — DEMO conserve l'effet de la version originale |
| Appliquée sur METALVISION production (`dlbewgsoboaycbpypcus`) | Non | Non (toujours non appliquée à ce stade) |
| `ccf_projects_via_user_project_ids` — état résultant | Supprimée sur DEMO | N/A — jamais touchée par cette version, reste présente et active là où elle existe déjà (production) |

**Conséquence directe** : DEMO et production divergent aujourd'hui sur cette policy précise —
DEMO ne l'a plus (supprimée par la version originale, jamais annulée depuis), production l'a
toujours. Ce n'est pas un défaut à corriger dans l'immédiat : DEMO reste un environnement de
démonstration isolé, et la version corrigée du dépôt est désormais celle qui reflète fidèlement
l'état réel de production sur ce point — c'est elle, et uniquement elle, qui pourra être
proposée pour une éventuelle application future en production, une fois qu'une décision séparée
et explicite aura été prise sur le sort de `ccf_projects_via_user_project_ids` (redondance
non encore validée par un test comportemental, voir bandeau en tête du fichier de migration).

**Ce document ne constitue pas une autorisation d'appliquer la version corrigée à la
production** — cette migration reste, à ce stade, non appliquée en production.

## Statut production — `carbon_migrations_proposed/14_get_my_portal_role_rpc.sql`

**Appliquée définitivement en production (`dlbewgsoboaycbpypcus`) le 2026-08-06 à
12:04:15 UTC.**

| | |
|---|---|
| Mode d'application | SQL brut exécuté directement en base (transaction unique, `BEGIN...COMMIT`), **hors de l'outil de migration Supabase** — pas un `supabase db push` |
| Empreinte SHA-256 du fichier `14_get_my_portal_role_rpc.sql` (après mise à jour du bandeau de statut, 2026-08-06) | `8a1ed1f139bd9348f59cf6e555ae6a56cb9b520900a200a1cec178d5617493ec` — le contenu fonctionnel de la fonction (STEP 1/2/3) est strictement identique à celui exécuté en production ; seul l'en-tête documentaire a été corrigé après application |
| Empreinte données/policies avant/après (production) | Identique : `n_users=9, n_accredited_verifiers=1, n_org_members=3, n_organizations=4, n_policies_public=147, policies_fingerprint=c83662a2129b4d9e5720b88a4fcad721` ; seul `n_functions_public` passe de 356 à 357 (exactement la fonction créée) |
| **Statut dans `supabase_migrations.schema_migrations` (production)** — constaté en direct, jamais supposé | **Non inscrite.** La dernière version enregistrée dans cette table sur production est `20260722134537` (« 08_carbon_lots_commercial_cycle ») — confirmé par requête directe le 2026-08-06, après l'application de `get_my_portal_role()`. Cohérent avec le mode d'application (SQL brut, hors outil de migration) : cette table ne reflète que les migrations appliquées via l'outil CLI/dashboard Supabase, pas les `execute_sql` directs. |
| Statut dans `schema_migrations` de METALVISION-DEMO | Inscrite : `20260802032220_get_my_portal_role_rpc` (application du 2026-08-02, via l'outil de migration) |
| Détail complet des contrôles (catalogue + comportemental, 3 identités réelles) | Voir `RAPPORT-REGRESSION-DEMO-FINAL.md`, section 12.2-12.3 |

## Pourquoi le décalage de nom

Les 2 fichiers `20260713*` documentent une investigation et un correctif RLS réellement menés
et appliqués sur METALVISION-DEMO le 2026-08-01, mais rédigés a posteriori en reprenant le
timestamp logique de la série de migrations `20260713*` (pour rester à leur place chronologique
dans la séquence fonctionnelle) plutôt que le timestamp d'écriture réel. L'outil d'application
Supabase, lui, horodate la version distante au moment réel de l'exécution (`202608012221xx`),
d'où l'écart entre nom de fichier et version distante — ce n'est pas une erreur de ces fichiers,
c'est le comportement normal de l'outil.

## Portée et état actif

- Les 2 fichiers `20260713*` n'ont jamais été appliqués qu'sur METALVISION-DEMO
  (`msgesgemaasyzycielzf`) — jamais en production.
- Leur effet a été entièrement défait sur METALVISION-DEMO le 2026-08-01 par les 2 migrations
  de réconciliation `20260801010000` et `20260801020000`, qui reproduisent fidèlement l'état RLS
  réellement observé en production (`dlbewgsoboaycbpypcus`) sur les mêmes tables.
- L'état RLS actif sur METALVISION-DEMO correspond donc aujourd'hui au contenu de
  `20260801010000` + `20260801020000`, pas à celui des 2 fichiers `20260713*`.
- Les 2 fichiers `20260801*` sont des BROUILLONS rédigés pour verser dans git un état déjà en
  vigueur en base (fonctions/policies appliquées directement, jamais capturées par une
  migration versionnée) — ils n'ont pas de version distante propre associée.
