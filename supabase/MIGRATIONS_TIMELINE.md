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
| `20260801010000_reconcile_project_participants_ccf_projects_with_production.sql` | `2a80e75` | 2026-08-01 18:57:47 -0400 | — (brouillon, jamais appliquée) | — | BROUILLON — NON APPLIQUÉE |
| `20260801020000_reconcile_opportunities_opp_cap_with_production.sql` | `2a80e75` | 2026-08-01 18:57:47 -0400 | — (brouillon, jamais appliquée) | — | BROUILLON — NON APPLIQUÉE |

## Empreintes SHA-256 (contenu au moment de la rédaction de ce document)

```
fbefef07eca496830b4608d3669f0882570a083b98a19454c92ce5974b344fb  20260713020000_fix_rls_recursion_project_participants_ccf_projects.sql
e06e409783d47a04119b4e7554cc6b632f74ac5ecdd36dd6f76aba292f5e048  20260713030000_fix_rls_recursion_opportunities_opp_cap.sql
215d40e131e75675c46a93fb5654daecf42e0b70a079c33dd2bb8b9bef09c20  20260801010000_reconcile_project_participants_ccf_projects_with_production.sql
e9af6d51350349b1c2c2628ede516b4c20e01dca31ee82257475cf9ee1e3157  20260801020000_reconcile_opportunities_opp_cap_with_production.sql
```

Recalcul (à exécuter depuis la racine du dépôt) :

```bash
sha256sum supabase/migrations/20260713020000_fix_rls_recursion_project_participants_ccf_projects.sql \
          supabase/migrations/20260713030000_fix_rls_recursion_opportunities_opp_cap.sql \
          supabase/migrations/20260801010000_reconcile_project_participants_ccf_projects_with_production.sql \
          supabase/migrations/20260801020000_reconcile_opportunities_opp_cap_with_production.sql
```

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
