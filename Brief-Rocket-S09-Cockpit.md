# Brief Rocket — Écran S09 (`/cockpit`)

**Contexte :** le backend a été revu et ne nécessite **aucune correction, aucune nouvelle table, aucune nouvelle migration** (`ADR-MVP.md` §9quaterdecies) — cet écran est une synthèse en lecture seule construite entièrement à partir de données déjà en place et déjà protégées par RLS (`ccf_projects`, `project_participants`, `logistics_steps`, `value_reports`).

**Avant de commencer : `git pull`/`git reset --hard origin/main` avant de créer votre branche.** Ce n'est plus une simple recommandation : les 5 dernières livraisons consécutives (S06, S07, S08, et deux fois sur S05) contenaient chacune, en plus du travail demandé, la réintroduction accidentelle et identique de bugs déjà corrigés (`ADR-MVP.md` §9octies/§9decies/§9terdecies) — toujours le même contenu périmé, jamais nettoyé entre les livraisons. La revue de ce PR fera, comme les 5 précédentes, un diff fichier par fichier de la branche complète, pas seulement des fichiers annoncés dans la description — donc toute régression sera de toute façon détectée et rejetée avant fusion. Un `git pull` avant de démarrer vous évite ce travail de nettoyage inutile.

---

## 1. Objectif de l'écran

Route `/cockpit`. Référence : backlog technique v1.0, E12-T03 (`S09 / US-014`) ; cahier fonctionnel v1.2, M10. User story : « Comme coordonnateur, je peux consulter le cockpit exécutif d'un projet : volumes, risques et avancement. »

C'est une **vue direction** — présentation synthétique et lisible pour un public non technique, pas un nouvel outil de gestion opérationnelle (ça, c'est déjà `/projets/:id`, construit en S05). Priorité SHOULD (M3, jours 61-90) : pas de logique métier nouvelle, uniquement de la présentation agrégée.

## 2. Sélection du projet

Le backlog liste la route comme `/cockpit` sans paramètre (contrairement à `/projets/:id`), mais la user story cible explicitement *un* projet. Décision retenue : la page affiche un **sélecteur** limité aux projets où l'utilisateur est **admin de l'organisation coordinatrice** (même filtre que `isCoordinatorAdmin` dans S05 — cohérent avec le « Comme coordonnateur » de US-014). Si l'utilisateur n'est coordonnateur d'aucun projet, afficher un état vide explicite plutôt qu'un cockpit vide trompeur.

Ne créez pas de route paramétrée (`/cockpit/:id`) — le sélecteur suffit pour le MVP et respecte le backlog tel qu'écrit.

## 3. Indicateurs à afficher

Tous calculés côté frontend, aucune nouvelle colonne ni table :

### Avancement
Basé sur `ccf_projects.phase`, mappé sur 5 paliers fixes :

| Phase | % |
|---|---|
| `draft` | 0 % |
| `active` | 25 % |
| `execution` | 50 % |
| `review` | 75 % |
| `closed` | 100 % |

Affichage suggéré : barre de progression + libellé de phase (réutilisez `PhaseBadge`/`PHASE_CONFIG` de `src/app/projets/[id]/page.tsx` si pratique).

### Volumes / Valeur
Tirés de la ligne `value_reports` **la plus récente** du projet (`created_at` DESC — même ordre que la liste de S05). **Pas d'agrégation ni de somme entre plusieurs rapports** : ce n'est pas spécifié par le backlog et introduirait une logique métier non demandée. Si aucun rapport n'existe pour le projet : état vide clair (« Aucun rapport de valeur disponible »), pas une erreur ni un `0` trompeur.

### Risques
**Réutilisez exactement la logique déjà écrite dans le panneau "Risques" de `src/app/projets/[id]/page.tsx`** (étapes logistiques `blocked`, `target_end_date` dépassée avec `phase !== 'closed'`, participants `declined`). N'écrivez pas une seconde implémentation qui pourrait diverger dans le temps — si une extraction en fonction/hook partagé (ex. `src/lib/projectRisks.ts`) est plus propre pour éviter la duplication entre S05 et S09, c'est bienvenu, mais le *résultat* du calcul doit rester identique dans les deux écrans.

### Synthèse direction
Présentation uniquement (cartes, indicateurs formatés, éventuellement un court texte descriptif généré côté frontend à partir des chiffres — ex. « Projet en exécution à 50 %, aucun risque détecté, 1 200 t traitées »). **Aucune génération IA** : l'agent IA (`M11`, `ai_assistance_logs`) est un module distinct, hors périmètre de ce ticket.

## 4. Ce qu'il ne faut pas faire

- Pas de nouvelle table, pas de nouvelle migration, pas de nouvelle policy RLS — tout ce dont vous avez besoin est déjà lisible via les policies SELECT existantes de `ccf_projects`, `project_participants`, `logistics_steps`, `value_reports`.
- Pas de nouvel `event_type` ni d'insertion `business_events` — cet écran est en lecture seule, aucune action utilisateur n'y a lieu.
- Pas de route paramétrée `/cockpit/:id` (voir §2).
- Ne dupliquez pas le calcul des risques (voir §3) — un écart entre S05 et S09 sur la définition d'un « risque » serait une régression fonctionnelle silencieuse.

## 5. Avant de livrer

PR revue selon `ROCKET_REVIEW_CHECKLIST.md` avant fusion, comme pour chaque écran précédent. Point d'attention spécifique à cet écran : vérifier que le calcul des risques produit exactement les mêmes résultats que le panneau "Risques" de S05 pour un même projet.
