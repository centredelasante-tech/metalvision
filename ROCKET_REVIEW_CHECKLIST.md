# Checklist de revue — livrables de Rocket

**Objectif :** revue systématique de tout PR ou script généré par Rocket avant fusion sur `main`. Aucune exception, même quand Rocket indique que c'est « testé ».

**Origine :** cette checklist consolide les patrons de bugs récurrents trouvés lors de la revue de l'écran S06 (Mandats) — 4 bugs dans le script SQL original (`INC-S06-01` à `04`, voir `ADR-MVP.md` §7bis) et 1 bug dans le frontend (`INC-S06-06`). Elle sera mise à jour à chaque nouveau patron identifié.

---

## 1. RLS (policies SQL)

- [ ] Chaque transition de statut attendue a une policy `UPDATE` qui la couvre explicitement (`USING`/`WITH CHECK`). Reproduire chaque transition métier une par une — un workflow bloqué dès la première étape est facile à manquer en lecture (`INC-S06-01`).
- [ ] Toute vérification de rôle utilise les fonctions utilitaires existantes (`is_org_admin()`, etc.) — jamais une re-implémentation locale (`user_org_ids()` seul, sans filtre de rôle) qui laisserait n'importe quel membre agir à la place d'un admin (`INC-S06-03`, **réapparu identique dans une nouvelle RPC à `INC-S06-07`** — un patron déjà corrigé une fois n'est pas immunisé contre une réapparition ailleurs dans le même domaine).
- [ ] Toute nouvelle valeur `event_type` insérée dans `business_events` existe réellement dans l'ENUM `ccf_event_type` (`20260710001000_ccf_001_enums.sql`) — sinon l'`INSERT` échoue à l'exécution, pas à la revue de code (`INC-S06-08`). Grep la définition de l'ENUM avant d'accepter toute nouvelle valeur mentionnée dans un commit.
- [ ] Vérifier les **combinaisons** de policies `UPDATE` permissives sur une même table : Postgres combine tous les `WITH CHECK` par OR, pas seulement celui dont le `USING` a sélectionné la ligne. Une policy A peut autoriser une modification qu'aucune policy individuelle ne voulait permettre (`INC-S06-04`).
- [ ] Tester avec un utilisateur `membre` (non-admin), pas seulement avec un compte admin/owner — un accès trop large ne se voit qu'en testant le rôle le plus faible.
- [ ] Pour toute action listée dans un catalogue fermé de permissions (ex. `mandate_actions`) : vérifier qu'au moins une policy RLS ou une RPC vérifie réellement cette permission quelque part dans le code. Une action peut être validée par un trigger (existence dans le catalogue) sans jamais être *appliquée* nulle part — une permission déclarée mais non exploitée (`INC-S07-01`, `approve_documents`) est aussi dangereuse qu'une policy trop permissive, dans l'autre sens : une fonctionnalité promise par le modèle de données mais absente du backend.

## 2. Triggers

- [ ] Un trigger de gel de champs (`freeze`) sur transition doit couvrir **les deux sens** de la condition (`OLD.status = 'x' OR NEW.status = 'x'`), pas seulement l'état déjà atteint — sinon la transition elle-même reste un angle mort (`INC-S06-02`).
- [ ] Vérifier qu'aucun trigger n'écrit dans `business_events` (réservé au code applicatif) — seul `audit_log_trigger_fn()` doit écrire dans `audit_logs`. Les deux journaux ne doivent jamais contenir le même fait.

## 3. `business_events` — doublons

- [ ] Pour chaque RPC appelée depuis le frontend : si la RPC insère déjà un `business_events` (`INSERT INTO public.business_events` dans le `.sql`), le frontend ne doit **jamais** insérer le même événement manuellement après l'appel. Grep systématique : chercher tous les `.rpc(` et tous les `.from('business_events').insert(` dans le même fichier, croiser les deux listes (`INC-S06-06`).
- [ ] Les actions qui font un simple `UPDATE`/`INSERT` direct sur la table (sans passer par une RPC) sont les seules où une insertion manuelle de `business_events` côté frontend est légitime.

## 4. Symétrie des RPC (paires accept/decline, create/cancel, etc.)

- [ ] Quand une action a deux branches (ex. mandat autonome vs lié à un projet), vérifier que **chaque** RPC de la paire respecte la même séparation — pas seulement celle qui a été corrigée en premier. Le cas `decline_project_invitation` utilisé indifféremment pour les deux branches, alors que l'acceptation est strictement séparée (`accept_mandate` / `accept_project_invitation`), est un nommage trompeur à clarifier même s'il ne cause pas de bug fonctionnel.

## 5. Migrations SQL

- [ ] Idempotence : blocs `DO $$ ... IF NOT EXISTS ... $$` pour toute création de type/colonne/contrainte, `DROP ... IF EXISTS` avant chaque `CREATE TRIGGER`/`CREATE POLICY` — cohérent avec le style déjà en place dans le repo.
- [ ] Aucune régression sur les fonctions utilitaires partagées (`is_org_admin()`, etc.) : vérifier qu'elles existent déjà avant d'être réutilisées, ou les recréer explicitement dans la migration (garde-fou `RAISE EXCEPTION` si absente, pas d'échec silencieux).

## 6. Git / process

- [ ] Ne jamais fusionner un PR de Rocket directement — toujours revue + fix avant `main`.
- [ ] Après tout `git pull`/rebase impliquant une branche de Rocket, vérifier qu'aucun contenu déjà retiré n'a été réintroduit silencieusement (`git diff` contre le dernier état connu-bon avant de pousser).
- [ ] Une fois un PR buggé fermé sans fusion, supprimer la branche distante si son contenu est un ancêtre de `main` (`git merge-base --is-ancestor origin/<branche> origin/main`) — sinon la garder identifiée comme non fusionnée tant qu'elle n'a pas été traitée.
- [ ] Avant toute revue de contenu, `git diff origin/main origin/<branche>` sur l'**ensemble** des fichiers, pas seulement celui que Rocket dit avoir modifié — une branche peut être techniquement construite sur `main` à jour (`main` ancêtre du commit) tout en réintroduisant des fichiers périmés si l'agent a travaillé depuis une copie locale non synchronisée (`ADR-MVP.md` et l'ancien script S06 buggé réapparus à `INC-S06-07`/`08`).
- [ ] **Patron récurrent — 7 occurrences confirmées (`INC-S06-07/08`, `INC-S07-04`, `INC-S08-01`, PR S05/Projets, PR S09/Cockpit, PR S01/Dashboard) : un commit avec un parent Git à jour peut quand même committer du contenu périmé. Ne jamais se contenter de vérifier que le PR "part de main à jour" ; toujours diffuser fichier par fichier, y compris ceux non mentionnés dans la description du PR.** Traiter comme acquis et permanent.
- [ ] **Variante aggravée, confirmée sur 2 PR consécutives (S09 puis S01) : des fichiers *entièrement hors du périmètre du brief courant* apparaissent dans le diff et annulent des corrections déjà faites.** Sur la PR S01 (dont le brief ne mentionnait ni `cockpit/page.tsx` ni `projets/[id]/page.tsx`), les deux fichiers sont quand même apparus dans le diff, chacun annulant exactement le correctif de la session précédente (`INC-S09-01`, `INC-S05-02`). Ce n'est plus une question de "vieille branche jamais nettoyée" : l'agent Rocket semble retoucher/régénérer des fichiers sans rapport avec la tâche demandée à chaque nouvelle livraison, à partir d'un instantané périmé qui englobe tout le dépôt. **Conséquence pour la revue, à partir de maintenant : traiter TOUT fichier présent dans le diff comme suspect, y compris — surtout — ceux qui semblent sans rapport avec le brief courant. Pour tout fichier existant modifié dont le brief ne demandait pas la modification, vérifier explicitement s'il correspond à un incident déjà corrigé avant de décider d'un cherry-pick partiel ou d'un rejet total du fichier.**
- [ ] **Recommandation formelle à faire à Rocket, au-delà de la revue :** ce patron n'est plus traitable uniquement en aval par la revue humaine — le risque d'un correctif silencieusement perdu sans qu'il apparaisse dans le brief suivant augmente à chaque nouvelle livraison. Il devrait être demandé explicitement à Rocket de confirmer, avant chaque PR, la liste exacte des fichiers modifiés et pourquoi — pas seulement de suivre une consigne de `git pull`.
- [ ] **10 occurrences confirmées au 13 juillet 2026** (S06 ×2, S07, S08, S05, S09, S01, S10, E08, E08bis). Le patron est désormais traité comme **acquis et permanent** pour toute future livraison Rocket, pas comme une anomalie à espérer résolue — la revue systématique fichier par fichier reste obligatoire à chaque PR, sans exception, même après plusieurs livraisons "propres" consécutives.

## 7. Outil d'audit automatique

- [ ] **`scripts/rocket_pr_audit.sh <nom-de-branche>`** — à lancer en premier, avant toute lecture manuelle du diff, dès qu'une branche Rocket est poussée. Il fetch `origin/main` et la branche, puis pour chaque fichier modifié, vérifie si son contenu est **octet-identique à une version antérieure de ce même fichier n'importe où dans l'historique de `main`** (pas seulement le commit courant). Un match = **stale revert suspecté**, signalé automatiquement avec le commit et la date d'origine.
- [ ] **Limite connue et acceptée du script :** il ne peut détecter que les reverts vers un contenu qui a existé un jour comme commit réel sur `main`. Si un correctif a été écrit directement dans sa version finale sans jamais committer la version cassée que Rocket avait livrée à l'origine (fréquent : le contenu corrigé remplace l'original avant le premier commit), un revert vers cette version cassée apparaîtra comme "nouveau/modifié" et exige une revue manuelle du contenu contre les patrons déjà connus ci-dessus (catalogues fictifs, `useAuth()` mort, noms de table périmés, etc.). Le script réduit le travail répétitif de comparaison ; il ne dispense jamais de la revue humaine du contenu marqué "nouveau/modifié".
- [ ] Le script rapporte aussi si la branche part bien du commit actuel de `main` (`merge-base`) — une branche peut très bien partir d'un commit à jour et quand même réintroduire du contenu périmé (voir §6 ci-dessus) : ce signal seul ne suffit jamais à conclure qu'une PR est saine.

---

*Dernière mise à jour : 13 juillet 2026, suite à la revue du PR E08bis (10ᵉ occurrence du patron, scope creep non demandé sur Documents/Rapport de valeur, `INC-S05-03` trouvé au passage) — voir ADR-MVP.md §9tricies. Ajout de l'outil d'audit automatique `scripts/rocket_pr_audit.sh`.*
