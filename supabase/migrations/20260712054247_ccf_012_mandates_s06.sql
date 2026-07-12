-- ============================================================
-- S06 -- Mandats (complement a CCF-003)
-- VERSION FINALE -- revue et testee le 12 juillet 2026
-- Fusionne le script original de Rocket avec le patch corrigeant
-- 4 bugs trouves a la revue (voir ADR-MVP.md, INC-S06-01 a 04).
-- PREREQUIS : public.is_org_admin(uuid) doit deja exister
-- (creee via 20260712053146_fix_is_org_admin_missing.sql).
-- ============================================================

BEGIN;

-- 0. Garde-fou : verifier que is_org_admin() existe deja
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_org_admin'
  ) THEN
    RAISE EXCEPTION 'public.is_org_admin(uuid) est introuvable. Migration arretee.';
  END IF;
END;
$$;

-- 1. ENUM mandate_scope (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mandate_scope') THEN
    CREATE TYPE public.mandate_scope AS ENUM (
      'gouvernance', 'operationnel', 'financier', 'technique', 'verification', 'ia'
    );
  END IF;
END;
$$;

-- 2. TABLE mandates -- s'assurer que mandate_scope est bien ENUM
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'mandates'
      AND column_name = 'mandate_scope' AND data_type = 'text'
  ) THEN
    ALTER TABLE public.mandates
      ALTER COLUMN mandate_scope TYPE public.mandate_scope
      USING mandate_scope::public.mandate_scope;
  END IF;
END;
$$;

-- 3. TRIGGER MVP-RA-029 : gel des champs structurants (corrige INC-S06-02)
CREATE OR REPLACE FUNCTION public.enforce_mandate_active_freeze()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status = 'active' OR NEW.status = 'active' THEN
    IF NEW.mandate_scope IS DISTINCT FROM OLD.mandate_scope
       OR NEW.permissions IS DISTINCT FROM OLD.permissions
       OR NEW.issuer_org_id IS DISTINCT FROM OLD.issuer_org_id
       OR NEW.receiver_org_id IS DISTINCT FROM OLD.receiver_org_id THEN
      RAISE EXCEPTION
        'mandate_scope, permissions, issuer_org_id et receiver_org_id sont geles une fois le mandat actif ou lors de son activation (MVP-RA-029).';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS mandates_enforce_active_freeze ON public.mandates;
CREATE TRIGGER mandates_enforce_active_freeze
  BEFORE UPDATE ON public.mandates
  FOR EACH ROW EXECUTE FUNCTION public.enforce_mandate_active_freeze();

-- 4. Expiration a la volee (MVP-DA-017)
CREATE OR REPLACE FUNCTION public.is_mandate_effective(p_mandate_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT status = 'active' AND (end_date IS NULL OR end_date::date >= current_date)
  FROM public.mandates
  WHERE id = p_mandate_id;
$$;

DROP VIEW IF EXISTS public.active_effective_mandates;
CREATE OR REPLACE VIEW public.active_effective_mandates AS
  SELECT * FROM public.mandates
  WHERE status = 'active'
    AND (end_date IS NULL OR end_date::date >= current_date);

-- 5. Contrainte UNIQUE sur project_participants (MVP-DA-018)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'project_participants_project_org_unique'
      AND conrelid = 'public.project_participants'::regclass
  ) THEN
    ALTER TABLE public.project_participants
      ADD CONSTRAINT project_participants_project_org_unique
      UNIQUE (project_id, organization_id);
  END IF;
EXCEPTION WHEN undefined_table THEN
  NULL;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'project_participants')
  AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'project_participants'
      AND column_name = 'mandate_id'
  ) THEN
    ALTER TABLE public.project_participants
      ADD COLUMN mandate_id uuid REFERENCES public.mandates(id) ON DELETE SET NULL;
  END IF;
EXCEPTION WHEN undefined_table THEN
  NULL;
END;
$$;

-- 6. Fonctions utilitaires RLS
CREATE OR REPLACE FUNCTION public.user_org_ids()
RETURNS SETOF uuid
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT organization_id FROM public.organization_members
  WHERE user_id = auth.uid() AND status = 'active';
$$;

CREATE OR REPLACE FUNCTION public.user_project_ids()
RETURNS SETOF uuid
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pp.project_id FROM public.project_participants pp
  WHERE pp.organization_id IN (SELECT public.user_org_ids())
    AND pp.status = 'active';
$$;

-- 7. RLS policies mandates (corrigees INC-S06-01 et INC-S06-03)
DROP POLICY IF EXISTS "mandates_org_select" ON public.mandates;
DROP POLICY IF EXISTS "mandates_issuer_admin_insert" ON public.mandates;
DROP POLICY IF EXISTS "mandates_org_admin_update" ON public.mandates;
DROP POLICY IF EXISTS "mandates_superadmin_select" ON public.mandates;
DROP POLICY IF EXISTS "mandates_select_involved" ON public.mandates;
DROP POLICY IF EXISTS "mandates_insert_issuer_admin" ON public.mandates;
DROP POLICY IF EXISTS "mandates_update_issuance_by_issuer" ON public.mandates;
DROP POLICY IF EXISTS "mandates_update_acceptance_by_receiver" ON public.mandates;
DROP POLICY IF EXISTS "mandates_update_revocation_by_issuer" ON public.mandates;

CREATE POLICY mandates_select_involved
  ON public.mandates FOR SELECT
  TO authenticated
  USING (
    issuer_org_id IN (SELECT public.user_org_ids())
    OR receiver_org_id IN (SELECT public.user_org_ids())
    OR public.is_platform_superadmin()
  );

CREATE POLICY mandates_insert_issuer_admin
  ON public.mandates FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_org_admin(issuer_org_id)
    AND status = 'draft'
  );

CREATE POLICY mandates_update_issuance_by_issuer
  ON public.mandates FOR UPDATE
  TO authenticated
  USING (public.is_org_admin(issuer_org_id) AND status = 'draft')
  WITH CHECK (status = 'pending_acceptance');

CREATE POLICY mandates_update_acceptance_by_receiver
  ON public.mandates FOR UPDATE
  TO authenticated
  USING (
    public.is_org_admin(receiver_org_id)
    AND status = 'pending_acceptance'
  )
  WITH CHECK (status IN ('active', 'revoked'));

CREATE POLICY mandates_update_revocation_by_issuer
  ON public.mandates FOR UPDATE
  TO authenticated
  USING (
    public.is_org_admin(issuer_org_id)
    AND status IN ('draft', 'pending_acceptance', 'active')
  )
  WITH CHECK (status = 'revoked');

-- 8. RPC accept_project_invitation (corrigee INC-S06-03)
CREATE OR REPLACE FUNCTION public.accept_project_invitation(
  p_mandate_id uuid,
  p_project_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mandate   public.mandates%ROWTYPE;
  v_actor_id  uuid;
  v_result    jsonb;
BEGIN
  v_actor_id := auth.uid();
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_actor_id) THEN
    RAISE EXCEPTION 'Profil introuvable pour l''utilisateur courant';
  END IF;

  SELECT * INTO v_mandate FROM public.mandates WHERE id = p_mandate_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mandat introuvable';
  END IF;

  IF v_mandate.status != 'pending_acceptance' THEN
    RAISE EXCEPTION 'Mandat non en attente d''acceptation (statut actuel: %)', v_mandate.status;
  END IF;

  IF NOT public.is_org_admin(v_mandate.receiver_org_id) THEN
    RAISE EXCEPTION 'Seul un admin de l''organisation receptrice peut accepter ce mandat';
  END IF;

  UPDATE public.mandates
  SET status = 'active', updated_at = now()
  WHERE id = p_mandate_id;

  INSERT INTO public.project_participants (project_id, organization_id, mandate_id, status, project_role)
  VALUES (p_project_id, v_mandate.receiver_org_id, p_mandate_id, 'active', 'contributeur')
  ON CONFLICT (project_id, organization_id)
  DO UPDATE SET status = 'active', mandate_id = p_mandate_id;

  INSERT INTO public.business_events (event_type, object_type, object_id, actor_id, organization_id, payload)
  VALUES (
    'mandate_accepted', 'mandate', p_mandate_id, v_actor_id,
    v_mandate.receiver_org_id, jsonb_build_object('mandate_id', p_mandate_id, 'project_id', p_project_id)
  );

  v_result := jsonb_build_object('mandate_id', p_mandate_id, 'status', 'active');
  RETURN v_result;
END;
$$;

-- 9. RPC decline_project_invitation (corrigee INC-S06-03)
CREATE OR REPLACE FUNCTION public.decline_project_invitation(
  p_mandate_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mandate   public.mandates%ROWTYPE;
  v_actor_id  uuid;
BEGIN
  v_actor_id := auth.uid();
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_actor_id) THEN
    RAISE EXCEPTION 'Profil introuvable pour l''utilisateur courant';
  END IF;

  SELECT * INTO v_mandate FROM public.mandates WHERE id = p_mandate_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mandat introuvable';
  END IF;

  IF v_mandate.status != 'pending_acceptance' THEN
    RAISE EXCEPTION 'Mandat non en attente d''acceptation (statut actuel: %)', v_mandate.status;
  END IF;

  IF NOT public.is_org_admin(v_mandate.receiver_org_id) THEN
    RAISE EXCEPTION 'Seul un admin de l''organisation receptrice peut refuser ce mandat';
  END IF;

  UPDATE public.mandates
  SET status = 'revoked', updated_at = now()
  WHERE id = p_mandate_id;

  INSERT INTO public.business_events (event_type, object_type, object_id, actor_id, organization_id, payload)
  VALUES (
    'mandate_revoked', 'mandate', p_mandate_id, v_actor_id,
    v_mandate.receiver_org_id, jsonb_build_object('mandate_id', p_mandate_id, 'reason', 'declined_by_receiver')
  );

  RETURN jsonb_build_object('mandate_id', p_mandate_id, 'status', 'revoked');
END;
$$;

-- 10. Index supplementaire sur mandate_id dans project_participants
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'project_participants')
  AND EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'project_participants'
                AND column_name = 'mandate_id')
  THEN
    CREATE INDEX IF NOT EXISTS idx_project_participants_mandate_id
      ON public.project_participants (mandate_id);
  END IF;
END;
$$;

COMMIT;
