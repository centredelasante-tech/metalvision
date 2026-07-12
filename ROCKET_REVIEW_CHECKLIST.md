# Checklist de revue — livrables de Rocket

**Objectif :** revue systématique de tout PR ou script généré par Rocket avant fusion sur `main`. Aucune exception, même quand Rocket indique que c'est « testé ».

**Origine :** cette checklist consolide les patrons de bugs récurrents trouvés lors de la revue de l'écran S06 (Mandats) — 4 bugs dans le script SQL original (`INC-S06-01` à `04`, voir `ADR-MVP.md` §7bis) et 1 bug dans le frontend (`INC-S06-06`). Elle sera mise à jour à chaque nouveau patron identifié.

---

## 1. RLS (policies SQL)

- [ ] Chaque transition de statut attendue a une policy `UPDATE` qui la couvre explicitement (`USING`/`WITH CHECK`). Reproduire chaque transition métier une par une — un workflow bloqué dès la première étape est facile à manquer en lecture (`INC-S06-01`).
- [ ] Toute vérification de rôle utilise les fonctions utilitaires existantes (`is_org_admin()`, etc.) — jamais une re-implémentation locale (`user_org_ids()` seul, sans filtre de rôle) qui laisserait n'importe quel membre agir à la place d'un admin (`INC-S06-03`).
- [ ] Vérifier les **combinaisons** de policies `UPDATE` permissives sur une même table : Postgres combine tous les `WITH CHECK` par OR, pas seulement celui dont le `USING` a sélectionné la ligne. Une policy A peut autoriser une modification qu'aucune policy individuelle ne voulait permettre (`INC-S06-04`).
- [ ] Tester avec un utilisateur `membre` (non-admin), pas seulement avec un compte admin/owner — un accès trop large ne se voit qu'en testant le rôle le plus faible.

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

---

*Dernière mise à jour : 12 juillet 2026, suite à la revue de l'écran S06 (Mandats).*
