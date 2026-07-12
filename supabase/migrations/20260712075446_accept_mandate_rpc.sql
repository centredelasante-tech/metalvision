CREATE OR REPLACE FUNCTION public.accept_mandate(p_mandate_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mandate  public.mandates%ROWTYPE;
  v_actor_id uuid;
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

  IF EXISTS (SELECT 1 FROM public.project_participants WHERE mandate_id = p_mandate_id) THEN
    RAISE EXCEPTION 'Ce mandat est lie a un projet -- utiliser accept_project_invitation() a la place';
  END IF;

  UPDATE public.mandates SET status = 'active', updated_at = now() WHERE id = p_mandate_id;

  INSERT INTO public.business_events (event_type, object_type, object_id, actor_id, organization_id, payload)
  VALUES ('mandate_accepted', 'mandate', p_mandate_id, v_actor_id, v_mandate.receiver_org_id,
          jsonb_build_object('mandate_id', p_mandate_id));

  RETURN jsonb_build_object('mandate_id', p_mandate_id, 'status', 'active');
END;
$$;
