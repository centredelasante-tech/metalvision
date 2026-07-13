-- ============================================================
-- S06 — RPC decline_mandate (mandat autonome)
-- ============================================================
-- Symétrique à accept_mandate() pour le cas autonome.
-- Résout l'asymétrie accept/decline signalée à la revue de code
-- (ADR-MVP.md §9quinquies) : decline_project_invitation était
-- appelée pour les deux cas, alors qu'accept respectait déjà
-- la séparation MVP-DA-019.
--
-- Comportement : identique à decline_project_invitation, mais
-- sans référence à un projet — réservée aux mandats autonomes
-- (non liés à project_participants).
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

  IF v_mandate.receiver_org_id NOT IN (SELECT public.user_org_ids()) THEN
    RAISE EXCEPTION 'Utilisateur non autorisé à refuser ce mandat';
  END IF;

  UPDATE public.mandates
  SET status = 'revoked', updated_at = now()
  WHERE id = p_mandate_id;

  INSERT INTO public.business_events (event_type, object_type, object_id, actor_id, organization_id, payload)
  VALUES (
    'mandate_declined',
    'mandate',
    p_mandate_id,
    v_actor_id,
    v_mandate.receiver_org_id,
    jsonb_build_object('mandate_id', p_mandate_id, 'reason', 'declined_by_receiver')
  );

  RETURN jsonb_build_object('mandate_id', p_mandate_id, 'status', 'revoked');
END;
$$;
