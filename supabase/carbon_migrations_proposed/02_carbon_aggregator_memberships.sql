-- ============================================================
-- Migration carbone 02/07 — Adhésions aux regroupements (aggregator_memberships)
-- ============================================================
--
-- PROPOSITION NON APPLIQUÉE. Ce fichier vit délibérément hors de
-- supabase/migrations/ pour qu'aucun `supabase db push` ne puisse
-- l'appliquer par inadvertance. À lire, réviser et approuver avant
-- toute exécution manuelle dans le SQL Editor Supabase — comme la
-- migration 01, jamais avant une décision explicite de l'utilisateur.
--
-- Réfère à : Tranche0-Carbone-Architecture.md (v4 + 7 corrections finales,
-- §7, §8, §9, §10, §11, §11bis).
--
-- PRÉREQUIS : migration 01 déjà appliquée (carbon_business_events,
-- carbon_rpc_failures, carbon_reject_update_delete(), can_view_carbon_event()).
-- Confirmé exécutée avec succès le 14 juillet 2026 (22/22, voir ADR-MVP.md §12).
--
-- ÉTAT RÉEL DU SCHÉMA VÉRIFIÉ AVANT ÉCRITURE (recherche dans
-- supabase/migrations/, pas supposé) :
--   - organizations.aggregator_id existe déjà : UUID NULLABLE, FK vers
--     aggregators(id) ON DELETE SET NULL — relation directe 1-N, PAS de
--     table de jonction, PAS d'historisation. C'est précisément ce que
--     cette migration remplace comme source de vérité (sans le supprimer).
--   - aggregators(id, name, description, created_at, updated_at) — pas de
--     colonne CHECK, pas de colonne "primary_admin" directe.
--   - aggregator_admins existe déjà (gouvernance : qui administre un
--     regroupement), avec un index unique partiel garantissant un seul
--     primary_admin actif (idx_one_active_primary_admin). Cette migration
--     ne touche PAS à aggregator_admins — aggregator_memberships est un
--     concept DIFFÉRENT (quelles ORGANISATIONS appartiennent à quel
--     regroupement, pas qui les administre).
--   - is_aggregator_admin(p_aggregator_id UUID), is_org_admin(p_organization_id UUID),
--     is_organization_member(p_org_id UUID), is_platform_superadmin() existent déjà,
--     réutilisées telles quelles.
--   - profiles.id REFERENCES auth.users(id) — aucune colonne "role" sur
--     profiles, le rôle plateforme vit dans le JWT (app_metadata), le rôle
--     dans une organisation vit dans organization_members.org_role.
--
-- ✓ POINT ANTÉRIEUREMENT SIGNALÉ COMME NON CONFIRMÉ, DÉSORMAIS RÉSOLU : le nom
-- exact de la colonne aggregator_admins portant l'auteur de la nomination
-- (`nominated_by`) avait d'abord été retrouvé seulement dans l'historique des
-- migrations versionnées (supabase/migrations/), jugé insuffisant par
-- précédent (INC-DATA-01, ADR-MVP.md §9novodecies). CONFIRMÉ depuis par
-- requête directe sur information_schema.columns le 14 juillet 2026 (voir
-- 02_verification_schema_reel.sql, requête 2) : nominated_by existe
-- réellement, avec la forme attendue. Le bloc de PRÉVALIDATION (section 0
-- ci-dessous) continue de vérifier cette hypothèse à l'exécution, comme
-- filet de sécurité permanent — pas seulement pour cette application ponctuelle.
--
-- CONTENU (BEGIN/COMMIT explicite entourant tout le fichier depuis la
-- deuxième revue — un seul environnement Supabase, atomicité requise) :
--   0. PRÉVALIDATION DU SCHÉMA RÉEL — vérifie par introspection catalogue
--      (information_schema/pg_catalog, signatures exactes via to_regprocedure()),
--      PAS par hypothèse tirée de l'historique des migrations versionnées,
--      que les objets dont ce fichier dépend existent réellement avec la
--      forme attendue (colonnes, index avec sa DÉFINITION exacte, les 4
--      event_type précis utilisés). Échoue bruyamment AVANT tout DDL si un
--      écart est détecté. Verrou LOCK TABLE organizations (SHARE ROW
--      EXCLUSIVE) posé juste avant le backfill, tenu jusqu'au COMMIT final.
--   1. Table aggregator_memberships (historisée, RESTRICT, CHECK ended_at
--      IS NULL OR ended_at >= started_at — décision D8 — , index unique
--      partiel garantissant une seule adhésion active par organisation).
--   2. Backfill depuis organizations.aggregator_id (approximation documentée :
--      started_at = organizations.created_at, date réelle d'adhésion inconnue),
--      avec émission d'un événement aggregator_membership_started synthétique
--      par ligne backfillée, identifié comme tel (décision D9).
--   3. Trigger de garde sur UPDATE (seule transition permise : ended_at de
--      NULL vers une valeur, aucune autre colonne modifiable) + réutilisation
--      de carbon_reject_update_delete() (migration 01) pour interdire tout DELETE.
--   4. Trigger de compatibilité TRANSITOIRE, SECURITY DEFINER (décision D7) :
--      synchronise organizations.aggregator_id à partir de aggregator_memberships,
--      pour ne pas casser le code applicatif existant qui lit encore cette
--      colonne directement — à retirer dans une migration future une fois le
--      frontend migré vers aggregator_memberships.
--   5. Dépréciation documentée (COMMENT) de organizations.aggregator_id — la
--      colonne n'est PAS supprimée dans cette migration. GARDE-FOU (décision
--      D5, durci en D7 après deuxième revue) : un trigger dédié rejette toute
--      écriture directe de cette colonne, sauf à trois conditions cumulatives
--      (marqueur transactionnel, pg_trigger_depth() imbriqué, current_user =
--      propriétaire de la fonction de synchronisation) — le marqueur seul
--      n'étant pas une frontière de sécurité (falsifiable par set_config()).
--   6. RLS (lecture seule via policy, écriture exclusivement par RPC).
--   7. RPC create_aggregator_with_primary_admin() (§9), join_aggregator(),
--      leave_aggregator() (clock_timestamp() pour ended_at — décision D8).
--   8. Révocations de privilèges par défaut — authenticated explicitement
--      révoqué AVANT d'être regranté en lecture seule (après revue), COMMIT
--      final de la transaction.
--   9. Section de rollback/désactivation, commentée, hors transaction, à
--      exécuter manuellement à la fin si besoin.
--
-- DÉCISIONS PRISES DANS CE FICHIER (D1 corrigée après revue reçue le 14
-- juillet 2026 ; D2-D4 acceptées telles quelles) :
--   D1. RÉVISÉE (refusée dans sa forme initiale, corrigée) : join_aggregator()
--       est autorisée à l'admin DU REGROUPEMENT CIBLE (is_aggregator_admin(p_aggregator_id))
--       OU au super-admin plateforme — PAS à l'admin de l'organisation seul.
--       Une organisation ne peut plus activer elle-même son adhésion à
--       n'importe quel regroupement : c'est le regroupement qui doit
--       l'accepter. L'admin de l'organisation conserve le droit de QUITTER
--       (leave_aggregator(), D2, inchangée). Version initiale (is_org_admin
--       OU super-admin) rejetée après revue : elle permettait à l'admin
--       d'une organisation de choisir librement n'importe quel aggregator_id
--       sans validation de l'administrateur du regroupement — risque
--       d'élévation d'accès via le trigger de compatibilité qui aurait
--       ensuite propagé ce choix unilatéral dans organizations.aggregator_id,
--       potentiellement lu par des policies historiques du domaine
--       Agrégateurs. Un futur flux bilatéral (request_membership() /
--       approve_membership() / reject_membership()) reste hors périmètre de
--       cette migration.
--   D2. leave_aggregator() : autorisé à l'admin de l'organisation, à
--       l'admin du regroupement CONCERNÉ (celui de l'adhésion active en
--       cours, pas un regroupement quelconque), ou au super-admin. Corrigée
--       après revue pour ne plus révéler à un appelant non autorisé
--       l'existence d'une adhésion active (voir D2bis ci-dessous).
--   D2bis. CORRECTION reçue après revue : la version initiale cherchait
--       l'adhésion active AVANT de vérifier l'autorisation, permettant à un
--       appelant authentifié mais non autorisé de distinguer « aucune
--       adhésion active » de « adhésion existante, accès refusé » (fuite
--       d'information par canal auxiliaire). Corrigée en intégrant
--       l'autorisation directement dans la clause WHERE du SELECT ... FOR
--       UPDATE : les deux cas produisent désormais exactement le même
--       message générique, « Adhésion active introuvable ou accès refusé. ».
--   D3. Gestion des erreurs : toutes les RPC de ce fichier utilisent
--       RAISE EXCEPTION avec un message descriptif (pas carbon_rpc_failures)
--       — cohérent avec §11bis : carbon_rpc_failures est réservée aux échecs
--       où la RPC choisit de capturer et retourner un résultat structuré
--       SANS relancer l'exception ; ce n'est pas une obligation pour
--       chaque RPC. Ici, un refus d'autorisation ou une violation de règle
--       métier remonte simplement comme une erreur Postgres standard,
--       provoquant un rollback automatique complet — le plus simple des
--       deux mécanismes documentés, suffisant pour ces trois RPC.
--   D4. aggregator_admin_appointed est journalisé dans carbon_business_events
--       dès create_aggregator_with_primary_admin() (en plus de
--       aggregator_created, déjà prévu par §9) — le catalogue prévoit cette
--       valeur et c'est le seul endroit où un premier admin est nommé à la
--       création ; ne pas la journaliser laisserait un trou d'audit.
--   D5. NOUVELLE (ajoutée après revue) : organizations.aggregator_id, bien
--       que dépréciée par simple COMMENT, restait modifiable directement par
--       n'importe quel appel PostgREST/ancien écran/policy existante — sans
--       créer de ligne d'historique, aucun événement, aucun contrôle
--       d'autorisation propre au regroupement. Corrigé par un garde-fou :
--       marqueur transactionnel privé (set_config('metaltrace.carbon_membership_sync', ...)),
--       positionné uniquement par carbon_sync_organizations_aggregator_id_compat()
--       juste avant son propre UPDATE, vérifié par un nouveau trigger
--       BEFORE UPDATE OF aggregator_id ON organizations qui rejette toute
--       écriture directe de cette colonne ne portant pas ce marqueur.
--   D6. NOUVELLE (ajoutée après revue) : REVOKE ALL sur aggregator_memberships
--       porte désormais explicitement sur authenticated (pas seulement
--       PUBLIC, anon), avant le GRANT SELECT — ne pas dépendre implicitement
--       de l'absence de policy INSERT/UPDATE/DELETE pour bloquer l'écriture ;
--       le garantir aussi au niveau des privilèges de table eux-mêmes.
--   D7. NOUVELLE (ajoutée après deuxième revue, 14 juillet 2026) : le marqueur
--       transactionnel seul (metaltrace.carbon_membership_sync) N'EST PAS une
--       frontière de sécurité — set_config() sur un GUC personnalisé est
--       appelable par n'importe quel rôle, y compris authenticated. Corrigé
--       par un garde-fou à conditions CUMULATIVES : (1) le marqueur est
--       positionné, (2) pg_trigger_depth() >= 2 (l'appel doit venir d'un
--       trigger déjà imbriqué — celui de aggregator_memberships), (3) current_user
--       correspond au PROPRIÉTAIRE réel de carbon_sync_organizations_aggregator_id_compat(),
--       désormais SECURITY DEFINER et dont l'EXECUTE est révoqué à PUBLIC,
--       anon, authenticated. Une écriture directe forgeant seulement le
--       marqueur (sans être dans ce contexte imbriqué précis) reste rejetée.
--       Le garde-fou autorise aussi explicitement toute UPDATE où
--       aggregator_id ne change pas réellement (IS NOT DISTINCT FROM),
--       pour ne pas casser un ancien formulaire renvoyant la ligne complète.
--       CORRIGÉ (défaut bloquant, quatrième revue) : la condition initiale
--       IF NOT (a AND b AND c AND d) pouvait valoir NULL — current_setting(...,
--       true) renvoie NULL si le paramètre n'a jamais été positionné dans la
--       transaction (pas seulement 'off') — et IF NULL ne déclenche jamais le
--       RAISE EXCEPTION en PL/pgSQL, laissant passer silencieusement une
--       écriture pourtant illégitime si depth et owner coïncidaient sans que
--       le marqueur n'ait jamais été positionné. Remplacé par des comparaisons
--       explicites IS DISTINCT FROM réunies par OR, garanties non-NULL. Le
--       propriétaire est en outre résolu par signature exacte via
--       to_regprocedure(), pas par nom seul. Testé par B30 (script de tests).
--   D8. NOUVELLE (ajoutée après deuxième revue) : now() est stable pendant
--       toute la transaction PostgreSQL — une adhésion créée puis terminée
--       dans le même bloc DO (comme dans le script de tests) obtiendrait
--       started_at = ended_at à l'identique, violant une contrainte stricte
--       ended_at > started_at. Corrigé : la contrainte devient
--       ended_at IS NULL OR ended_at >= started_at, et leave_aggregator()
--       utilise clock_timestamp() (horloge murale, avance à chaque appel dans
--       la transaction) au lieu de now() pour ended_at. Une adhésion créée
--       puis terminée immédiatement peut légitimement avoir une durée nulle.
--   D9. NOUVELLE (ajoutée après deuxième revue) : le backfill (section 2)
--       n'émettait auparavant aucun événement aggregator_membership_started
--       pour les adhésions préexistantes copiées depuis organizations.aggregator_id
--       — une fin ultérieure produirait un événement ended sans started
--       correspondant, un trou dans la chaîne d'audit carbone. Corrigé : un
--       événement de démarrage synthétique est désormais créé pour chaque
--       ligne de backfill, avec un payload {"source": "migration_02_backfill",
--       "started_at_approximate": true} le distinguant clairement d'une
--       adhésion créée via join_aggregator().
--
-- ATOMICITÉ (ajoutée après deuxième revue) : l'ensemble de ce fichier (de la
-- prévalidation aux révocations de privilèges) est désormais entouré d'une
-- transaction explicite BEGIN/COMMIT — un seul environnement Supabase existe
-- (pas de staging), une erreur tardive ne doit jamais pouvoir laisser une
-- migration partiellement appliquée. organizations est verrouillée
-- (SHARE ROW EXCLUSIVE) pendant le backfill et l'installation du garde-fou,
-- pour qu'une modification concurrente de organizations.aggregator_id ne
-- puisse pas créer de divergence dans l'intervalle.
--
-- Les tests vivent dans le fichier séparé référencé plus bas — à exécuter
-- APRÈS cette migration, jamais mélangés dans le même script.
-- ============================================================

-- ATOMICITÉ (D7/D8/D9, deuxième revue) : toute la migration — prévalidation,
-- DDL, backfill, RPC, privilèges — s'exécute dans une seule transaction
-- explicite. Un seul environnement Supabase existe ; une erreur tardive ne
-- doit jamais laisser une migration partiellement appliquée.
-- IMPORTANT : ce fichier doit être collé et exécuté EN UNE SEULE FOIS dans le
-- SQL Editor (du BEGIN; à la fin du COMMIT; avant la section ROLLBACK), pas
-- fragment par fragment — sans quoi le BEGIN/COMMIT explicite ci-dessous perd
-- son utilité et chaque instruction redevient sa propre transaction implicite.
BEGIN;

-- ────────────────────────────────────────────────────────────
-- 0. PRÉVALIDATION DU SCHÉMA RÉEL — introspection catalogue, PAS hypothèse
--    tirée de l'historique versionné (voir avertissement ⚠ ci-dessus).
--    Arrête la migration AVANT tout DDL si un écart est détecté.
-- ────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_missing TEXT;
    v_granted_by_exists BOOLEAN;
    v_event_count INT;
    v_constraint_def TEXT;
BEGIN
    -- aggregators : colonnes attendues.
    SELECT string_agg(col, ', ') INTO v_missing
    FROM unnest(ARRAY['id','name','description','created_at','updated_at']) AS col
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='aggregators' AND column_name=col
    );
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : colonne(s) manquante(s) sur public.aggregators : %. Le schéma réel diverge de ce que cette migration suppose — ne pas continuer.', v_missing;
    END IF;

    -- aggregator_admins : colonnes attendues, en particulier nominated_by
    -- (CONFIRMÉ en direct le 14 juillet 2026 par requête sur information_schema —
    -- voir 02_verification_schema_reel.sql — mais la prévalidation reste en
    -- place comme filet de sécurité permanent, pas seulement pour cette
    -- application ponctuelle).
    SELECT string_agg(col, ', ') INTO v_missing
    FROM unnest(ARRAY['id','aggregator_id','user_id','role','nominated_by','nominated_at','revoked_by','revoked_at']) AS col
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='aggregator_admins' AND column_name=col
    );
    IF v_missing IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='aggregator_admins' AND column_name='granted_by'
        ) INTO v_granted_by_exists;
        RAISE EXCEPTION 'Prévalidation échouée : colonne(s) manquante(s) sur public.aggregator_admins : %.%', v_missing,
            CASE WHEN v_granted_by_exists
                 THEN ' Une colonne granted_by existe en revanche — la RPC create_aggregator_with_primary_admin() de ce fichier suppose nominated_by et doit être corrigée avant application.'
                 ELSE '' END;
    END IF;

    -- Index unique partiel garantissant un seul primary_admin actif — pas
    -- seulement son NOM (renforcement après deuxième revue) : sa DÉFINITION
    -- exacte doit porter UNIQUE, sur aggregator_id, filtrée sur
    -- role = 'primary_admin' AND revoked_at IS NULL.
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname='public' AND tablename='aggregator_admins' AND indexname='idx_one_active_primary_admin'
          AND indexdef ILIKE '%UNIQUE%'
          AND indexdef ILIKE '%aggregator_id%'
          AND indexdef ILIKE '%primary_admin%'
          AND indexdef ILIKE '%revoked_at IS NULL%'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : idx_one_active_primary_admin introuvable ou sa définition ne correspond plus à ce qui est attendu (UNIQUE, aggregator_id, role=primary_admin, revoked_at IS NULL) — le bootstrap RPC dépend de cette garantie d''unicité.';
    END IF;

    -- Signatures EXACTES des 4 fonctions d'autorisation réutilisées, via
    -- to_regprocedure() (renforcement après deuxième revue : proname+pronargs
    -- seul pourrait matcher une surcharge inattendue de mêmes arité mais de
    -- types différents).
    IF to_regprocedure('public.is_aggregator_admin(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_aggregator_admin(uuid) introuvable avec la signature exacte attendue.';
    END IF;
    IF to_regprocedure('public.is_org_admin(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_org_admin(uuid) introuvable avec la signature exacte attendue.';
    END IF;
    IF to_regprocedure('public.is_organization_member(uuid)') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_organization_member(uuid) introuvable avec la signature exacte attendue.';
    END IF;
    IF to_regprocedure('public.is_platform_superadmin()') IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : public.is_platform_superadmin() introuvable avec la signature exacte attendue.';
    END IF;

    -- organizations : présence et type de aggregator_id, ET des colonnes
    -- created_at (utilisée par le backfill) et updated_at (utilisée par le
    -- trigger de compatibilité) — ajout après deuxième revue, ces deux
    -- colonnes étaient jusqu'ici supposées sans vérification explicite.
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='organizations' AND column_name='aggregator_id' AND data_type='uuid'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : organizations.aggregator_id introuvable ou de type inattendu (uuid attendu).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='organizations' AND column_name='created_at'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : organizations.created_at introuvable — requis par le backfill (section 2).';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='organizations' AND column_name='updated_at'
    ) THEN
        RAISE EXCEPTION 'Prévalidation échouée : organizations.updated_at introuvable — requis par le trigger de compatibilité (section 4).';
    END IF;

    -- Catalogue event_type de la migration 01 : les 31 valeurs attendues
    -- doivent déjà être en place (migration 01 confirmée appliquée, §12 ADR),
    -- ET (renforcement après deuxième revue) les 4 valeurs précises utilisées
    -- PAR CETTE migration doivent être présentes explicitement — un total de
    -- 31 ne prouve pas, à lui seul, que ce sont les bonnes 31 valeurs.
    -- Recherche RESTREINTE à public.carbon_business_events (renforcement
    -- après cinquième revue) — conname seul n'est pas garanti unique dans
    -- toute la base ; conrelid élimine toute ambiguïté avec une contrainte de
    -- même nom sur une autre table.
    SELECT pg_get_constraintdef(c.oid) INTO v_constraint_def
    FROM pg_constraint c
    WHERE c.conrelid = 'public.carbon_business_events'::regclass
      AND c.conname = 'carbon_business_events_event_type_check';

    IF v_constraint_def IS NULL THEN
        RAISE EXCEPTION 'Prévalidation échouée : contrainte carbon_business_events_event_type_check introuvable (migration 01 absente) — voir ADR-MVP.md §12.';
    END IF;

    SELECT count(*) INTO v_event_count
    FROM regexp_matches(v_constraint_def, '''[a-z_]+''', 'g');
    IF v_event_count <> 31 THEN
        RAISE EXCEPTION 'Prévalidation échouée : catalogue event_type de carbon_business_events attendu à 31 valeurs, trouvé % (migration 01 incomplète ou modifiée depuis) — voir ADR-MVP.md §12.', v_event_count;
    END IF;

    IF NOT (v_constraint_def ILIKE '%''aggregator_created''%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : event_type ''aggregator_created'' absent du catalogue, requis par create_aggregator_with_primary_admin().';
    END IF;
    IF NOT (v_constraint_def ILIKE '%''aggregator_admin_appointed''%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : event_type ''aggregator_admin_appointed'' absent du catalogue, requis par create_aggregator_with_primary_admin() (décision D4).';
    END IF;
    IF NOT (v_constraint_def ILIKE '%''aggregator_membership_started''%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : event_type ''aggregator_membership_started'' absent du catalogue, requis par join_aggregator() et le backfill (décision D9).';
    END IF;
    IF NOT (v_constraint_def ILIKE '%''aggregator_membership_ended''%') THEN
        RAISE EXCEPTION 'Prévalidation échouée : event_type ''aggregator_membership_ended'' absent du catalogue, requis par leave_aggregator().';
    END IF;

    RAISE NOTICE 'Prévalidation réussie : schéma réel conforme aux hypothèses de cette migration.';
END $$;

-- ────────────────────────────────────────────────────────────
-- 1. TABLE AGGREGATOR_MEMBERSHIPS — historisée, RESTRICT
-- ────────────────────────────────────────────────────────────

CREATE TABLE public.aggregator_memberships (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    aggregator_id   UUID NOT NULL REFERENCES public.aggregators(id) ON DELETE RESTRICT,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at        TIMESTAMPTZ NULL,
    started_by      UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    ended_by        UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    end_reason      TEXT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- D8 (deuxième revue) : >= et non > — now() est stable pendant toute la
    -- transaction PostgreSQL ; une adhésion créée puis terminée dans le même
    -- bloc DO (comme le script de tests, ou un cas réel exécuté très vite)
    -- peut légitimement produire started_at = ended_at si l'appelant utilise
    -- now() aux deux instants. leave_aggregator() utilise clock_timestamp()
    -- pour minimiser ce cas, mais la contrainte reste volontairement large.
    CONSTRAINT aggregator_memberships_ended_after_started
        CHECK (ended_at IS NULL OR ended_at >= started_at)
);

COMMENT ON TABLE public.aggregator_memberships IS
  'Historique des adhésions d''une organisation à un regroupement (aggregator). '
  'Remplace organizations.aggregator_id comme source de vérité — voir §7/§8 de '
  'Tranche0-Carbone-Architecture.md. Une organisation a au plus UNE adhésion '
  'active à la fois (ended_at IS NULL) — voir index unique partiel ci-dessous. '
  'Immuable sauf la transition ended_at NULL -> valeur (fin d''adhésion) — voir '
  'trigger aggregator_memberships_guard_update. Aucun DELETE possible (append-only, '
  'réutilise carbon_reject_update_delete() de la migration 01).';

-- Une seule adhésion active à la fois par organisation.
CREATE UNIQUE INDEX idx_aggregator_memberships_one_active_per_org
    ON public.aggregator_memberships (organization_id)
    WHERE ended_at IS NULL;

CREATE INDEX idx_aggregator_memberships_aggregator ON public.aggregator_memberships (aggregator_id);
CREATE INDEX idx_aggregator_memberships_organization ON public.aggregator_memberships (organization_id);

-- Verrou (D7/atomicité, deuxième revue) : bloque toute écriture concurrente
-- sur organizations (y compris une modification d'aggregator_id) pendant le
-- backfill et l'installation du garde-fou (section 5) — tenu jusqu'au COMMIT
-- de fin de fichier. Les lectures restent permises.
LOCK TABLE public.organizations IN SHARE ROW EXCLUSIVE MODE;

-- ────────────────────────────────────────────────────────────
-- 2. BACKFILL DEPUIS organizations.aggregator_id
-- ────────────────────────────────────────────────────────────
--
-- Approximation documentée et assumée : la date réelle d'adhésion n'est pas
-- connue (la colonne organizations.aggregator_id ne portait aucune date de
-- début) — started_at est donc approximé à organizations.created_at, qui est
-- nécessairement antérieure ou égale à la vraie date d'adhésion. Aucune
-- conséquence pratique attendue : aucune RPC carbone n'existe encore
-- (migrations 05+) qui dépendrait d'une adhésion active à une date
-- antérieure à aujourd'hui pour une organisation déjà membre avant cette
-- migration.
--
-- D9 (deuxième revue) : un événement aggregator_membership_started
-- synthétique est créé pour chaque ligne de backfill — sans cela, la fin
-- ultérieure d'une telle adhésion produirait un événement ended sans started
-- correspondant, un trou dans la chaîne d'audit carbone. Le payload identifie
-- explicitement ces événements comme issus du backfill, avec une date de
-- début approximative (voir paragraphe ci-dessus), pour ne jamais être
-- confondus avec une adhésion réellement initiée via join_aggregator().

WITH backfilled AS (
    INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_at, started_by, end_reason)
    SELECT o.id, o.aggregator_id, o.created_at, NULL, NULL
    FROM public.organizations o
    WHERE o.aggregator_id IS NOT NULL
    RETURNING id, organization_id, aggregator_id, started_at
)
INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
SELECT
    'aggregator_membership_started',
    'aggregator_membership',
    b.id,
    b.organization_id,
    b.aggregator_id,
    NULL,
    jsonb_build_object(
        'source', 'migration_02_backfill',
        'started_at_approximate', true,
        'started_at_used', b.started_at
    )
FROM backfilled b;

-- ────────────────────────────────────────────────────────────
-- 3. IMMUTABILITÉ — trigger de garde (UPDATE) + réutilisation du rejet
--    générique (DELETE) introduit par la migration 01
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.carbon_guard_aggregator_membership_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.ended_at IS NOT NULL THEN
        RAISE EXCEPTION 'aggregator_memberships : une adhésion déjà terminée (ended_at renseigné) est immuable, aucune modification supplémentaire n''est permise.';
    END IF;

    IF NEW.ended_at IS NULL THEN
        RAISE EXCEPTION 'aggregator_memberships : seule la transition de ended_at de NULL vers une valeur (fin d''adhésion) est permise — aucune autre modification.';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.aggregator_id IS DISTINCT FROM OLD.aggregator_id
       OR NEW.started_at IS DISTINCT FROM OLD.started_at
       OR NEW.started_by IS DISTINCT FROM OLD.started_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION 'aggregator_memberships : seules les colonnes ended_at, ended_by et end_reason peuvent être renseignées à la fin d''une adhésion — aucune autre colonne ne peut changer.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_aggregator_membership_update() IS
  'Autorise une seule transition sur aggregator_memberships : ended_at de NULL '
  'vers une valeur (avec ended_by/end_reason), jamais l''inverse, jamais deux fois, '
  'et aucune autre colonne modifiable. Spécifique à cette table (contrairement à '
  'carbon_reject_update_delete() qui rejette tout sans condition).';

CREATE TRIGGER aggregator_memberships_guard_update
    BEFORE UPDATE ON public.aggregator_memberships
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_aggregator_membership_update();

-- Réutilise la fonction générique de la migration 01 : elle rejette
-- inconditionnellement l'opération déclenchante, peu importe la table —
-- utilisée ici uniquement pour DELETE (l'UPDATE a sa propre garde ci-dessus).
CREATE TRIGGER aggregator_memberships_reject_delete
    BEFORE DELETE ON public.aggregator_memberships
    FOR EACH ROW EXECUTE FUNCTION public.carbon_reject_update_delete();

-- ────────────────────────────────────────────────────────────
-- 4. TRIGGER DE COMPATIBILITÉ TRANSITOIRE — synchronise organizations.aggregator_id
-- ────────────────────────────────────────────────────────────
--
-- TRANSITOIRE, À RETIRER DANS UNE MIGRATION FUTURE : tant que du code
-- applicatif existant lit organizations.aggregator_id directement, ce
-- trigger le maintient synchronisé avec aggregator_memberships (désormais
-- la source de vérité) pour éviter une divergence silencieuse entre les
-- deux. À supprimer (voir section rollback) une fois le frontend migré
-- pour lire aggregator_memberships directement.

-- D7 (deuxième revue) : SECURITY DEFINER — nécessaire pour que current_user,
-- pendant l'exécution de cette fonction ET des triggers qu'elle déclenche en
-- cascade (le garde-fou de la section 5), devienne le PROPRIÉTAIRE de cette
-- fonction plutôt que l'appelant réel. C'est l'une des trois conditions
-- cumulatives (avec le marqueur transactionnel et pg_trigger_depth()) que le
-- garde-fou vérifie — sans SECURITY DEFINER ici, current_user resterait
-- celui de la session appelante (potentiellement authenticated), rendant le
-- contrôle « current_user = propriétaire » inutile.
CREATE OR REPLACE FUNCTION public.carbon_sync_organizations_aggregator_id_compat()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Nouvelle ligne : par construction (partial unique index), elle ne
        -- peut être la seule adhésion active de cette organisation que si
        -- ended_at IS NULL au moment de l'insertion (backfill ou join_aggregator()).
        IF NEW.ended_at IS NULL THEN
            -- Marqueur transactionnel privé (décision D5, revue) : positionné
            -- juste avant l'UPDATE, vérifié par organizations_guard_aggregator_id_direct_write
            -- (section 5) qui rejette toute écriture ne le portant pas.
            PERFORM set_config('metaltrace.carbon_membership_sync', 'on', true);
            UPDATE public.organizations
            SET aggregator_id = NEW.aggregator_id, updated_at = now()
            WHERE id = NEW.organization_id
              AND aggregator_id IS DISTINCT FROM NEW.aggregator_id;
            PERFORM set_config('metaltrace.carbon_membership_sync', 'off', true);
        END IF;
    ELSIF TG_OP = 'UPDATE' AND OLD.ended_at IS NULL AND NEW.ended_at IS NOT NULL THEN
        -- Fin d'adhésion : la colonne dépréciée est remise à NULL.
        PERFORM set_config('metaltrace.carbon_membership_sync', 'on', true);
        UPDATE public.organizations
        SET aggregator_id = NULL, updated_at = now()
        WHERE id = NEW.organization_id
          AND aggregator_id IS DISTINCT FROM NULL;
        PERFORM set_config('metaltrace.carbon_membership_sync', 'off', true);
    END IF;
    RETURN NULL; -- trigger AFTER : valeur de retour ignorée par Postgres
END;
$$;

COMMENT ON FUNCTION public.carbon_sync_organizations_aggregator_id_compat() IS
  'TRANSITOIRE. Synchronise organizations.aggregator_id (colonne dépréciée) '
  'à partir de aggregator_memberships (source de vérité). SECURITY DEFINER '
  '(décision D7, deuxième revue) : établit le contexte de sécurité (current_user, '
  'pg_trigger_depth()) que organizations_guard_aggregator_id_direct_write '
  'vérifie pour distinguer un appel légitime d''une simple falsification du '
  'marqueur transactionnel. EXECUTE révoqué à PUBLIC/anon/authenticated — '
  'appelable uniquement par le mécanisme de trigger lui-même. À retirer, avec '
  'son trigger, dans une migration future une fois le code applicatif migré.';

-- D7 (deuxième revue) : révoque l'EXECUTE de cette fonction — bien que
-- Postgres refuse déjà nativement d'invoquer une fonction trigger hors
-- contexte de trigger (TG_OP/NEW/OLD non définis), cette révocation est un
-- filet de sécurité supplémentaire, sans coût, cohérent avec la défense en
-- profondeur du garde-fou D7.
REVOKE ALL ON FUNCTION public.carbon_sync_organizations_aggregator_id_compat() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER aggregator_memberships_sync_organizations_compat
    AFTER INSERT OR UPDATE ON public.aggregator_memberships
    FOR EACH ROW EXECUTE FUNCTION public.carbon_sync_organizations_aggregator_id_compat();

-- ────────────────────────────────────────────────────────────
-- 5. DÉPRÉCIATION DOCUMENTÉE DE organizations.aggregator_id (colonne conservée)
--    + GARDE-FOU (décision D5, ajoutée après revue) contre toute écriture
--    directe hors du mécanisme de compatibilité ci-dessus.
-- ────────────────────────────────────────────────────────────

COMMENT ON COLUMN public.organizations.aggregator_id IS
  'DÉPRÉCIÉE (migration carbone 02, 14 juillet 2026) : ne plus utiliser comme '
  'source de vérité pour l''adhésion à un regroupement — utiliser '
  'public.aggregator_memberships (historisée) à la place. Colonne conservée '
  'et synchronisée automatiquement (trigger de compatibilité transitoire) pour '
  'ne pas casser le code applicatif existant qui la lit encore directement. '
  'Toute écriture DIRECTE de cette colonne est rejetée par '
  'organizations_guard_aggregator_id_direct_write (décision D5) — seul le '
  'mécanisme de compatibilité peut la modifier. Suppression de la colonne '
  '(et de ce garde-fou) prévue dans une migration future, après migration du frontend.';

-- GARDE-FOU (décision D5, durci en D7 après deuxième revue) : sans ce
-- trigger, un ancien écran, une policy historique du domaine Agrégateurs, ou
-- un appel PostgREST direct pourrait encore modifier organizations.aggregator_id
-- sans créer de ligne d'historique, aucun événement, aucun contrôle
-- d'autorisation propre au regroupement.
--
-- D7 (deuxième revue) : le marqueur transactionnel SEUL n'est PAS une
-- frontière de sécurité — set_config() sur un GUC personnalisé
-- (metaltrace.carbon_membership_sync) est appelable par n'importe quel rôle,
-- y compris authenticated ; un appelant pourrait le positionner lui-même
-- avant un UPDATE direct. Trois conditions CUMULATIVES sont donc exigées :
--   1. le marqueur est positionné à 'on' ;
--   2. pg_trigger_depth() >= 2 : l'écriture doit provenir d'un contexte de
--      trigger DÉJÀ imbriqué — celui de aggregator_memberships_sync_organizations_compat,
--      lui-même un trigger. Un UPDATE direct émis au premier niveau (pas
--      depuis un autre trigger) a une profondeur de 1, jamais 2 ;
--   3. current_user correspond au PROPRIÉTAIRE réel de
--      carbon_sync_organizations_aggregator_id_compat(), qui est SECURITY
--      DEFINER (décision D7 ci-dessus) — current_user ne peut valoir cette
--      valeur QUE pendant l'exécution de cette fonction précise, jamais dans
--      une session authenticated ordinaire, même si elle a deviné le nom du
--      marqueur et falsifié pg_trigger_depth() par un autre moyen indirect.
-- Autorise en outre explicitement (avant toute vérification) les UPDATE où
-- aggregator_id ne change pas réellement, pour ne pas casser un ancien
-- formulaire qui renverrait la ligne complète, y compris un aggregator_id
-- inchangé.
CREATE OR REPLACE FUNCTION public.carbon_guard_organizations_aggregator_id_direct_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sync_owner name;
BEGIN
    IF NEW.aggregator_id IS NOT DISTINCT FROM OLD.aggregator_id THEN
        RETURN NEW;
    END IF;

    -- Résolution par SIGNATURE EXACTE via to_regprocedure() (renforcement
    -- après troisième revue) — évite de matcher une éventuelle surcharge de
    -- même nom mais de signature différente, cohérent avec le style déjà
    -- utilisé dans la prévalidation (section 0).
    SELECT r.rolname INTO v_sync_owner
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE p.oid = to_regprocedure('public.carbon_sync_organizations_aggregator_id_compat()');

    -- CORRECTIF (quatrième revue) — DÉFAUT BLOQUANT CORRIGÉ : l'ancienne
    -- condition `IF NOT (a AND b AND c AND d)` était unsafe en logique
    -- ternaire SQL. current_setting(..., true) renvoie NULL si le paramètre
    -- n'a jamais été positionné dans la transaction (pas seulement 'off').
    -- Si, par ailleurs, pg_trigger_depth() >= 2 et current_user = v_sync_owner
    -- étaient tous deux vrais (appel imbriqué au bon endroit, current_user
    -- coïncidant avec le propriétaire), l'expression complète valait
    -- NULL AND true AND true AND true = NULL — et `IF NOT (NULL)` = `IF NULL`,
    -- qui NE DÉCLENCHE JAMAIS le RAISE EXCEPTION en PL/pgSQL (NULL est traité
    -- comme faux par IF, silencieusement). Une écriture aurait donc pu passer
    -- sans que le marqueur n'ait jamais été explicitement positionné à 'on'.
    -- Corrigé par des comparaisons EXPLICITES (IS DISTINCT FROM, jamais NULL)
    -- réunies par OR — l'expression entière est garantie non-NULL, donc le
    -- test B30 (appel imbriqué, bon propriétaire, marqueur réellement NULL)
    -- est maintenant correctement rejeté.
    IF current_setting('metaltrace.carbon_membership_sync', true) IS DISTINCT FROM 'on'
       OR pg_trigger_depth() < 2
       OR v_sync_owner IS NULL
       OR current_user::name IS DISTINCT FROM v_sync_owner
    THEN
        RAISE EXCEPTION 'organizations.aggregator_id est dépréciée et ne peut être modifiée directement — utilisez join_aggregator()/leave_aggregator() (aggregator_memberships).';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.carbon_guard_organizations_aggregator_id_direct_write() IS
  'Rejette toute écriture de organizations.aggregator_id ne provenant pas '
  'STRICTEMENT du mécanisme de compatibilité : marqueur transactionnel '
  'metaltrace.carbon_membership_sync = ''on'' ET pg_trigger_depth() >= 2 ET '
  'current_user = propriétaire de carbon_sync_organizations_aggregator_id_compat() '
  '(SECURITY DEFINER) — trois conditions cumulatives (décision D7, durcies en '
  'comparaisons IS DISTINCT FROM après quatrième revue pour éliminer un défaut '
  'NULL bloquant : current_setting(..., true) peut renvoyer NULL, ce qu''un '
  'simple IF NOT (a AND b AND c) laissait passer silencieusement). Le marqueur '
  'seul n''est pas une frontière de sécurité car set_config() sur un GUC '
  'personnalisé est appelable par tout rôle. Autorise toujours une UPDATE où '
  'aggregator_id ne change pas réellement.';

CREATE TRIGGER organizations_guard_aggregator_id_direct_write
    BEFORE UPDATE OF aggregator_id ON public.organizations
    FOR EACH ROW EXECUTE FUNCTION public.carbon_guard_organizations_aggregator_id_direct_write();

-- ────────────────────────────────────────────────────────────
-- 6. RLS — lecture seule via policy, écriture exclusivement par RPC
-- ────────────────────────────────────────────────────────────

ALTER TABLE public.aggregator_memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY aggregator_memberships_select ON public.aggregator_memberships
    FOR SELECT
    USING (
        public.is_platform_superadmin()
        OR public.is_organization_member(organization_id)
        OR public.is_aggregator_admin(aggregator_id)
    );

-- Aucune policy INSERT/UPDATE/DELETE : l'écriture se fait exclusivement via
-- les RPC SECURITY DEFINER ci-dessous (join_aggregator, leave_aggregator),
-- qui contournent la RLS par nature (voir §8 pour les privilèges de table).

-- ────────────────────────────────────────────────────────────
-- 7. RPC — bootstrap, adhésion, départ
-- ────────────────────────────────────────────────────────────

-- 7.1. create_aggregator_with_primary_admin() — §9 de l'architecture.
-- Réservée au super-admin plateforme : crée le regroupement ET son premier
-- administrateur en une seule transaction atomique.
CREATE OR REPLACE FUNCTION public.create_aggregator_with_primary_admin(
    p_name TEXT,
    p_description TEXT,
    p_primary_admin_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_aggregator_id UUID;
    v_admin_id      UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    IF NOT public.is_platform_superadmin() THEN
        RAISE EXCEPTION 'Seul un super-administrateur de la plateforme peut créer un regroupement.';
    END IF;

    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'Le nom du regroupement est obligatoire.';
    END IF;

    IF p_primary_admin_user_id IS NULL THEN
        RAISE EXCEPTION 'Un administrateur principal est obligatoire à la création.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_primary_admin_user_id) THEN
        RAISE EXCEPTION 'p_primary_admin_user_id ne correspond à aucun profil existant.';
    END IF;

    INSERT INTO public.aggregators (name, description)
    VALUES (btrim(p_name), p_description)
    RETURNING id INTO v_aggregator_id;

    -- Protégé par l'index unique partiel déjà existant (idx_one_active_primary_admin,
    -- migration antérieure à ce chantier carbone) : aucun second primary_admin actif
    -- ne peut coexister, y compris pour cet agrégateur tout juste créé.
    INSERT INTO public.aggregator_admins (aggregator_id, user_id, role, nominated_by)
    VALUES (v_aggregator_id, p_primary_admin_user_id, 'primary_admin', auth.uid())
    RETURNING id INTO v_admin_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, aggregator_id, actor_id, payload)
    VALUES ('aggregator_created', 'aggregator', v_aggregator_id, v_aggregator_id, auth.uid(),
            jsonb_build_object('name', p_name));

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, aggregator_id, actor_id, payload)
    VALUES ('aggregator_admin_appointed', 'aggregator_admin', v_admin_id, v_aggregator_id, auth.uid(),
            jsonb_build_object('user_id', p_primary_admin_user_id, 'role', 'primary_admin'));

    RETURN v_aggregator_id;
END;
$$;

COMMENT ON FUNCTION public.create_aggregator_with_primary_admin(TEXT, TEXT, UUID) IS
  'Bootstrap atomique d''un regroupement avec son premier administrateur (§9). '
  'Réservée à is_platform_superadmin(). Journalise aggregator_created et '
  'aggregator_admin_appointed dans carbon_business_events (décision D4, revue).';

-- 7.2. join_aggregator() — décision D1 CORRIGÉE après revue : admin DU
-- REGROUPEMENT CIBLE (is_aggregator_admin(p_aggregator_id)) OU super-admin
-- plateforme. Une organisation ne peut plus activer elle-même son adhésion à
-- n'importe quel regroupement — c'est le regroupement qui accepte. L'admin
-- de l'organisation garde le droit de quitter (leave_aggregator(), D2). Pas
-- de flux d'invitation bilatéral dans cette migration (hors périmètre
-- Tranche 0 — request_membership()/approve_membership()/reject_membership()
-- resteraient à concevoir séparément si requis).
CREATE OR REPLACE FUNCTION public.join_aggregator(
    p_organization_id UUID,
    p_aggregator_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_membership_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    IF NOT (public.is_aggregator_admin(p_aggregator_id) OR public.is_platform_superadmin()) THEN
        RAISE EXCEPTION 'Seul un administrateur du regroupement cible ou un super-administrateur peut ajouter une organisation à ce regroupement.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
        RAISE EXCEPTION 'p_organization_id ne correspond à aucune organisation existante.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.aggregators WHERE id = p_aggregator_id) THEN
        RAISE EXCEPTION 'p_aggregator_id ne correspond à aucun regroupement existant.';
    END IF;

    -- Pré-vérification explicite et lisible avant de tenter l'insertion —
    -- l'index unique partiel (idx_aggregator_memberships_one_active_per_org)
    -- reste le filet de sécurité structurel en cas de course concurrente.
    IF EXISTS (
        SELECT 1 FROM public.aggregator_memberships
        WHERE organization_id = p_organization_id AND ended_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Cette organisation a déjà une adhésion active à un regroupement — utilisez leave_aggregator() avant d''en rejoindre un autre.';
    END IF;

    INSERT INTO public.aggregator_memberships (organization_id, aggregator_id, started_by)
    VALUES (p_organization_id, p_aggregator_id, auth.uid())
    RETURNING id INTO v_membership_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
    VALUES ('aggregator_membership_started', 'aggregator_membership', v_membership_id, p_organization_id, p_aggregator_id, auth.uid(), NULL);

    RETURN v_membership_id;
END;
$$;

COMMENT ON FUNCTION public.join_aggregator(UUID, UUID) IS
  'Crée une adhésion active d''une organisation à un regroupement. Autorisée à '
  'is_aggregator_admin(p_aggregator_id) ou is_platform_superadmin() SEULEMENT '
  '(décision D1, corrigée après revue — une organisation ne peut plus activer '
  'elle-même son adhésion ; pas de flux d''invitation bilatéral dans cette migration).';

-- 7.3. leave_aggregator() — décision D2 (revue) : admin de l'organisation,
-- admin du regroupement CONCERNÉ (celui de l'adhésion active en cours), ou
-- super-admin plateforme.
CREATE OR REPLACE FUNCTION public.leave_aggregator(
    p_organization_id UUID,
    p_end_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_membership_id UUID;
    v_aggregator_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- CORRECTION D2bis (revue) : l'autorisation est intégrée DIRECTEMENT dans
    -- la clause WHERE, pas vérifiée après coup — la version précédente
    -- cherchait l'adhésion active puis vérifiait l'autorisation dans un
    -- deuxième temps, ce qui permettait à un appelant authentifié mais non
    -- autorisé de distinguer « aucune adhésion active » (v_membership_id
    -- NULL immédiatement) de « adhésion existante, accès refusé » (trouvée
    -- puis rejetée) — une fuite d'information par canal auxiliaire. Les deux
    -- cas produisent désormais exactement la même absence de ligne, donc le
    -- même message générique ci-dessous. Verrou transactionnel (FOR UPDATE)
    -- conservé, pour éviter qu'un leave_aggregator() concurrent autorisé ne
    -- double-traite la même adhésion active.
    SELECT m.id, m.aggregator_id INTO v_membership_id, v_aggregator_id
    FROM public.aggregator_memberships m
    WHERE m.organization_id = p_organization_id
      AND m.ended_at IS NULL
      AND (
          public.is_org_admin(p_organization_id)
          OR public.is_platform_superadmin()
          OR public.is_aggregator_admin(m.aggregator_id)
      )
    FOR UPDATE;

    IF v_membership_id IS NULL THEN
        RAISE EXCEPTION 'Adhésion active introuvable ou accès refusé.';
    END IF;

    -- D8 (deuxième revue) : clock_timestamp() et non now() — now() est figée
    -- pour toute la transaction PostgreSQL ; si started_at avait aussi été
    -- posée avec now() dans la même transaction (cas du script de tests, ou
    -- d'un appel applicatif rapide join_aggregator()+leave_aggregator()),
    -- ended_at = now() produirait exactement started_at, ce qui est permis
    -- par la contrainte (>= depuis D8) mais clock_timestamp() reflète mieux
    -- l'instant réel de la fin d'adhésion.
    UPDATE public.aggregator_memberships
    SET ended_at = clock_timestamp(), ended_by = auth.uid(), end_reason = p_end_reason
    WHERE id = v_membership_id;

    INSERT INTO public.carbon_business_events (event_type, object_type, object_id, organization_id, aggregator_id, actor_id, payload)
    VALUES ('aggregator_membership_ended', 'aggregator_membership', v_membership_id, p_organization_id, v_aggregator_id, auth.uid(),
            CASE WHEN p_end_reason IS NOT NULL THEN jsonb_build_object('end_reason', p_end_reason) ELSE NULL END);

    RETURN v_membership_id;
END;
$$;

COMMENT ON FUNCTION public.leave_aggregator(UUID, TEXT) IS
  'Termine l''adhésion active d''une organisation à son regroupement (décision '
  'D2). Autorisation intégrée dans la clause WHERE du SELECT ... FOR UPDATE '
  '(décision D2bis, corrigée après revue) : ne distingue jamais « aucune '
  'adhésion active » de « accès refusé » — même message générique dans les '
  'deux cas, pour ne pas révéler l''existence d''une adhésion à un appelant '
  'non autorisé.';

-- ────────────────────────────────────────────────────────────
-- 8. RÉVOCATIONS DE PRIVILÈGES
-- ────────────────────────────────────────────────────────────

-- Décision D6 (ajoutée après revue) : révocation EXPLICITE de `authenticated`,
-- pas seulement de PUBLIC/anon — ne pas dépendre implicitement de l'absence
-- de GRANT par défaut sur une table nouvellement créée. Le script de tests
-- vérifie ces privilèges réels via has_table_privilege().
REVOKE ALL ON public.aggregator_memberships FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.aggregator_memberships TO authenticated;
-- Aucun GRANT INSERT/UPDATE/DELETE à `authenticated` — écriture exclusive
-- par les RPC SECURITY DEFINER ci-dessus.

REVOKE ALL ON FUNCTION public.create_aggregator_with_primary_admin(TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_aggregator_with_primary_admin(TEXT, TEXT, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.join_aggregator(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_aggregator(UUID, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.leave_aggregator(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_aggregator(UUID, TEXT) TO authenticated;

-- Atomicité (deuxième revue) : referme la transaction ouverte par le BEGIN;
-- de la section 0. Si une étape quelconque ci-dessus a levé une exception,
-- Postgres annule automatiquement toute la transaction — ce COMMIT n'est
-- jamais atteint et rien n'est appliqué partiellement.
COMMIT;

-- ════════════════════════════════════════════════════════════
-- ROLLBACK / DÉSACTIVATION (commenté — à exécuter manuellement si besoin
-- de revenir en arrière après application de cette migration ; DÉLIBÉRÉMENT
-- HORS de la transaction BEGIN/COMMIT ci-dessus, exécuté séparément et
-- explicitement par un opérateur humain, jamais automatiquement)
-- ════════════════════════════════════════════════════════════

-- Corrigé après revue (point 6) : le rollback DOIT retirer, dans l'ordre,
-- le garde-fou D5 (trigger + fonction) AVANT la colonne ne redevienne
-- directement inscriptible, et DOIT restaurer le commentaire de
-- organizations.aggregator_id à son état pré-migration — sinon ce
-- commentaire référence des objets (aggregator_memberships,
-- organizations_guard_aggregator_id_direct_write) qui n'existent plus,
-- ce qui est trompeur pour quiconque lit \d+ organizations après rollback.
--
-- DROP TRIGGER IF EXISTS organizations_guard_aggregator_id_direct_write ON public.organizations;
-- DROP FUNCTION IF EXISTS public.carbon_guard_organizations_aggregator_id_direct_write();
-- DROP TRIGGER IF EXISTS aggregator_memberships_sync_organizations_compat ON public.aggregator_memberships;
-- DROP FUNCTION IF EXISTS public.carbon_sync_organizations_aggregator_id_compat();
-- DROP TRIGGER IF EXISTS aggregator_memberships_guard_update ON public.aggregator_memberships;
-- DROP FUNCTION IF EXISTS public.carbon_guard_aggregator_membership_update();
-- DROP TRIGGER IF EXISTS aggregator_memberships_reject_delete ON public.aggregator_memberships;
-- DROP FUNCTION IF EXISTS public.leave_aggregator(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.join_aggregator(UUID, UUID);
-- DROP FUNCTION IF EXISTS public.create_aggregator_with_primary_admin(TEXT, TEXT, UUID);
-- DROP POLICY IF EXISTS aggregator_memberships_select ON public.aggregator_memberships;
-- DROP TABLE IF EXISTS public.aggregator_memberships;
-- -- Colonne organizations.aggregator_id conservée (redevient, en l'absence
-- -- du garde-fou et du trigger de compatibilité ci-dessus, directement
-- -- inscriptible comme avant cette migration). Restaurer son commentaire
-- -- pré-migration au lieu de laisser la mention de dépréciation pointer
-- -- vers des objets supprimés :
-- COMMENT ON COLUMN public.organizations.aggregator_id IS
--   'Regroupement (agrégateur) auquel cette organisation appartient, le cas échéant.';
-- -- Si une migration de suppression complète de la colonne est décidée
-- -- séparément, l'exécuter à part — ce rollback ne fait que désactiver
-- -- la migration 02, pas supprimer organizations.aggregator_id.
-- ============================================================
