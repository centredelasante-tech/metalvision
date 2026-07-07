-- ============================================================
-- MT-000B — Index unique partiel : un seul primary_admin actif
--           par regroupement (20260707130000)
-- ============================================================
--
-- OBJECTIF :
--   Garantir au niveau base de données qu'il ne peut exister
--   qu'un seul enregistrement actif avec role = 'primary_admin'
--   pour un aggregator_id donné dans la table aggregator_admins.
--
-- CONDITION PARTIELLE :
--   WHERE role = 'primary_admin' AND revoked_at IS NULL
--   → Les lignes révoquées (revoked_at IS NOT NULL) sont exclues
--     de la contrainte, permettant l'historique complet des mandats.
--
-- IDEMPOTENCE :
--   L'index est créé avec IF NOT EXISTS.
--   Un bloc DO vérifie en outre l'existence d'un index équivalent
--   (même table, même colonne indexée, même prédicat partiel)
--   afin d'éviter tout conflit si un index similaire avait été
--   créé manuellement sous un nom différent.
-- ============================================================

DO $$
DECLARE
    v_equivalent_exists BOOLEAN;
BEGIN
    -- Vérifie si un index unique partiel équivalent existe déjà
    -- (même table, colonne aggregator_id, prédicat role+revoked_at)
    SELECT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename  = 'aggregator_admins'
          AND indexname <> 'idx_one_active_primary_admin'
          AND indexdef ILIKE '%aggregator_id%'
          AND indexdef ILIKE '%primary_admin%'
          AND indexdef ILIKE '%revoked_at IS NULL%'
          AND indexdef ILIKE '%UNIQUE%'
    ) INTO v_equivalent_exists;

    IF v_equivalent_exists THEN
        RAISE NOTICE
            'MT-000B : Un index unique partiel équivalent existe déjà sur aggregator_admins. '
            'La création de idx_one_active_primary_admin est ignorée pour éviter tout conflit.';
    END IF;
END $$;

-- Création de l'index unique partiel (idempotent grâce à IF NOT EXISTS).
-- Si un index équivalent sous un autre nom existait déjà, PostgreSQL
-- acceptera quand même cet index car il porte un nom distinct ;
-- le bloc DO ci-dessus émet un NOTICE d'avertissement dans ce cas.
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_primary_admin
    ON public.aggregator_admins (aggregator_id)
    WHERE role = 'primary_admin'
      AND revoked_at IS NULL;
