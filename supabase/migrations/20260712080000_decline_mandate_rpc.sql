-- ============================================================
-- S06 -- RPC decline_mandate (mandat autonome)
-- ============================================================
-- Symetrique a accept_mandate() pour le cas autonome, resout
-- l'asymetrie accept/decline signalee a la revue de code
-- (ADR-MVP.md §9quinquies) : decline_project_invitation etait
-- appelee pour les deux cas, alors qu'accept respectait deja
-- la separation MVP-DA-019.
--
-- Reecrite depuis zero (pas la version de Rocket sur la branche
-- rocket-update, qui contenait deux bugs -- voir ADR-MVP.md) :
--   1. Verification par is_org_admin(), pas user_org_ids() --
--      meme regression que INC-S06-03 sinon (n'importe quel
--      membre actif, pas seulement un admin, pourrait refuser).
--   2. event_type = 'mandate_revoked', pas 'mandate_declined' --
--      'mandate_declined' n'existe pas dans l'ENUM ccf_event_type
--      (voir 20260710001000_ccf_001_enums.sql) ; l'insertion
--      aurait echoue a l'execution avec la version de Rocket.
--
-- Comportement : identique a decline_project_invitation, mais
-- sans reference a un projet -- reservee aux mandats autonomes
-- (non lies a project_participants). Le frontend est responsable
-- d'appeler la bonne RPC selon mandateProjectMap.
-- ============================================================

CREATE OR REPLACE FUNCTION public.decline_mandate(
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

  IF EXISTS (SELECT 1 FROM public.project_participants WHERE mandate_id = p_mandate_id) THEN
    RAISE EXCEPTION 'Ce mandat est lie a un projet -- utiliser decline_project_invitation() a la place';
  END IF;

  UPDATE public.mandates
  SET status = 'revoked', updated_at = now()
  WHERE id = p_mandate_id;

  INSERT INTO public.business_events (event_type, object_type, object_id, actor_id, organization_id, payload)
  VALUES (
    'mandate_revoked',
    'mandate',
    p_mandate_id,
    v_actor_id,
    v_mandate.receiver_org_id,
    jsonb_build_object('mandate_id', p_mandate_id, 'reason', 'declined_by_receiver')
  );

  RETURN jsonb_build_object('mandate_id', p_mandate_id, 'status', 'revoked');
END;
$$;
