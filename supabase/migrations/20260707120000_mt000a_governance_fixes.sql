-- ============================================================
-- MT-000A — Correctifs finaux de gouvernance (20260707120000)
-- ============================================================
--
-- CHANGEMENTS :
--   0. is_platform_superadmin() : redéfinie ici pour garantir l'existence
--      de la fonction avant toute utilisation dans ce fichier
--   1. aggregator_admins_superadmin_all : FOR ALL → SELECT + INSERT + UPDATE
--      (DELETE physique interdit pour le super-admin plateforme)
--   2. is_aggregator_primary_admin(UUID) : nouvelle fonction helper
--      (vérifie role = 'primary_admin' AND revoked_at IS NULL)
--   3. aggregator_admins_admin_insert / _admin_update : utilise désormais
--      is_aggregator_primary_admin() au lieu de is_aggregator_admin()
--   4. transfer_aggregator_primary_admin() : transfert atomique et auditable
--      du rôle primary_admin (révocation + insertion dans une transaction)
--   5. operational_units_aggregator_admin_select : SELECT uniquement pour
--      l'admin de regroupement sur les unités opérationnelles de ses membres
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 0. PRÉREQUIS : is_platform_superadmin()
--    Redéfinie ici pour garantir l'existence de la fonction
--    même si la migration 20260707110100 n'a pas encore été appliquée.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_platform_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
$$;

-- ════════════════════════════════════════════════════════════
-- 1. FONCTION : is_aggregator_primary_admin(UUID)
-- ════════════════════════════════════════════════════════════
-- Vérifie que l'utilisateur courant est le primary_admin ACTIF
-- du regroupement donné (role = 'primary_admin' AND revoked_at IS NULL).
-- Utilisée pour restreindre la gouvernance de aggregator_admins.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_aggregator_primary_admin(p_aggregator_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.aggregator_admins aa
        WHERE aa.aggregator_id = p_aggregator_id
          AND aa.user_id       = auth.uid()
          AND aa.role          = 'primary_admin'
          AND aa.revoked_at    IS NULL
    )
$$;

-- ════════════════════════════════════════════════════════════
-- 2. CORRECTION : aggregator_admins_superadmin_all
--    FOR ALL → SELECT + INSERT + UPDATE (jamais DELETE)
-- ════════════════════════════════════════════════════════════
-- Principe : la suppression physique d'un administrateur est INTERDITE.
-- Toute fin de mandat passe par revoked_at (révocation logique).
-- Le super-admin plateforme n'a donc pas le droit DELETE sur cette table.
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "aggregator_admins_superadmin_all" ON public.aggregator_admins;

CREATE POLICY "aggregator_admins_superadmin_select"
    ON public.aggregator_admins
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());

CREATE POLICY "aggregator_admins_superadmin_insert"
    ON public.aggregator_admins
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_platform_superadmin());

CREATE POLICY "aggregator_admins_superadmin_update"
    ON public.aggregator_admins
    FOR UPDATE
    TO authenticated
    USING (public.is_platform_superadmin())
    WITH CHECK (public.is_platform_superadmin());

-- ════════════════════════════════════════════════════════════
-- 3. CORRECTION : policies INSERT et UPDATE de aggregator_admins
--    is_aggregator_admin() → is_aggregator_primary_admin()
-- ════════════════════════════════════════════════════════════
-- Seul le primary_admin peut nommer ou révoquer un administrateur.
-- Le co_admin conserve ses droits opérationnels (is_aggregator_admin())
-- mais ne peut jamais modifier la table aggregator_admins.
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "aggregator_admins_admin_insert" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_insert"
    ON public.aggregator_admins
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_aggregator_primary_admin(aggregator_id));

DROP POLICY IF EXISTS "aggregator_admins_admin_update" ON public.aggregator_admins;
CREATE POLICY "aggregator_admins_admin_update"
    ON public.aggregator_admins
    FOR UPDATE
    TO authenticated
    USING  (public.is_aggregator_primary_admin(aggregator_id))
    WITH CHECK (public.is_aggregator_primary_admin(aggregator_id));

-- ════════════════════════════════════════════════════════════
-- 4. FONCTION : transfer_aggregator_primary_admin(UUID, UUID)
-- ════════════════════════════════════════════════════════════
--
-- Transfert ATOMIQUE et AUDITABLE du rôle primary_admin.
--
-- Algorithme (transaction unique) :
--   a) Vérifie que l'appelant est le primary_admin actif OU le super-admin.
--   b) Révoque logiquement l'ancien primary_admin
--      (revoked_at = now(), revoked_by = auth.uid(),
--       revocation_reason = 'transfert de rôle').
--   c) Si le nouveau titulaire avait un rôle co_admin actif, le révoque
--      également (même principe — jamais de modification en place).
--   d) Insère une nouvelle ligne primary_admin pour le nouveau titulaire.
--
-- Garantie : il n'existe jamais un instant sans primary_admin actif
-- (les étapes b-d s'exécutent dans la même transaction).
--
-- Sécurité : SECURITY DEFINER pour contourner les RLS lors des
-- opérations internes, mais la vérification d'autorisation est
-- effectuée explicitement en début de fonction.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.transfer_aggregator_primary_admin(
    p_aggregator_id     UUID,
    p_new_primary_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
    v_caller_id         UUID := auth.uid();
    v_old_primary_id    UUID;
    v_old_primary_row   UUID;
    v_co_admin_row      UUID;
BEGIN
    -- ── a. Vérification d'autorisation ───────────────────────
    -- L'appelant doit être le primary_admin actif du regroupement
    -- OU le super-admin plateforme (déblocage en cas de blocage).
    IF NOT (
        public.is_aggregator_primary_admin(p_aggregator_id)
        OR public.is_platform_superadmin()
    ) THEN
        RAISE EXCEPTION
            'Autorisation refusée : seul le primary_admin actif ou le super-admin plateforme peut transférer le rôle primary_admin (aggregator_id = %)',
            p_aggregator_id;
    END IF;

    -- ── Récupération de l'ancien primary_admin actif ─────────
    SELECT id, user_id
    INTO v_old_primary_row, v_old_primary_id
    FROM public.aggregator_admins
    WHERE aggregator_id = p_aggregator_id
      AND role          = 'primary_admin'
      AND revoked_at    IS NULL
    LIMIT 1;

    IF v_old_primary_id IS NULL THEN
        RAISE EXCEPTION
            'Aucun primary_admin actif trouvé pour le regroupement %',
            p_aggregator_id;
    END IF;

    IF v_old_primary_id = p_new_primary_user_id THEN
        RAISE EXCEPTION
            'Le nouveau primary_admin est déjà le primary_admin actif (user_id = %)',
            p_new_primary_user_id;
    END IF;

    -- ── b. Révocation logique de l'ancien primary_admin ──────
    UPDATE public.aggregator_admins
    SET revoked_at        = now(),
        revoked_by        = v_caller_id,
        revocation_reason = 'transfert de rôle'
    WHERE id = v_old_primary_row;

    -- ── c. Révocation logique du co_admin actif du nouveau
    --       titulaire (s'il en avait un) ──────────────────────
    SELECT id
    INTO v_co_admin_row
    FROM public.aggregator_admins
    WHERE aggregator_id = p_aggregator_id
      AND user_id       = p_new_primary_user_id
      AND revoked_at    IS NULL
    LIMIT 1;

    IF v_co_admin_row IS NOT NULL THEN
        UPDATE public.aggregator_admins
        SET revoked_at        = now(),
            revoked_by        = v_caller_id,
            revocation_reason = 'transfert de rôle — promotion primary_admin'
        WHERE id = v_co_admin_row;
    END IF;

    -- ── d. Insertion du nouveau primary_admin ─────────────────
    INSERT INTO public.aggregator_admins (
        aggregator_id,
        user_id,
        role,
        nominated_by,
        nominated_at
    ) VALUES (
        p_aggregator_id,
        p_new_primary_user_id,
        'primary_admin',
        v_caller_id,
        now()
    );

END;
$func$;

-- ════════════════════════════════════════════════════════════
-- 5. POLICY : operational_units_aggregator_admin_select
--    SELECT uniquement — aucun droit d'écriture pour l'admin de regroupement
-- ════════════════════════════════════════════════════════════
-- L'admin de regroupement (primary_admin ou co_admin actif) peut lire
-- les unités opérationnelles des compagnies membres de son regroupement,
-- pour la gestion des projets, audits et répartitions.
-- Aucune policy INSERT, UPDATE ou DELETE n'est ajoutée pour ce rôle :
-- les unités restent la propriété exclusive de la compagnie membre,
-- gérées uniquement par is_company_owner().
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "operational_units_aggregator_admin_select" ON public.operational_units;
CREATE POLICY "operational_units_aggregator_admin_select"
    ON public.operational_units
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.companies c
            WHERE c.id            = operational_units.company_id
              AND public.is_aggregator_admin(c.aggregator_id)
        )
    );
