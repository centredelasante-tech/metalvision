-- ============================================================
-- CCF-006e — Approbation de documents par mandat (approve_documents)
-- ============================================================
--
-- CONSTAT (revue backend S07 — /documents, 12 juillet 2026) :
--   'approve_documents' est une action canonique du catalogue fermé
--   public.mandate_actions (voir ccf_003), et le Cahier fonctionnel
--   v1.2 / Backlog technique v1.0 la documentent comme du scope MVP
--   réel : un mandat peut légitimement porter cette permission.
--
--   Or aucune policy RLS, RPC ou fonction n'existe nulle part dans
--   le schéma pour vérifier mandates.permissions.actions contre une
--   action sur public.documents. La seule policy UPDATE existante,
--   "documents_owner_admin_update" (ccf_006), ne laisse que l'admin
--   de l'organisation propriétaire du document modifier son statut.
--   Un mandataire tiers (ex. coordonnateur de projet détenant un
--   mandat 'approve_documents') n'a donc aujourd'hui AUCUN moyen
--   d'approuver ou de refuser un document déposé par une autre
--   organisation dans son projet — la permission existe dans le
--   modèle de données mais n'a jamais été appliquée.
--
-- PORTÉE DE LA CORRECTION :
--   Le lien entre un mandat et "quel projet il couvre" passe par
--   public.project_participants.mandate_id (ajouté dans ccf_012).
--   On restreint donc cette correction aux documents de portée
--   projet (object_type = 'project'), conformément au libellé de
--   l'action dans le catalogue : "Valider un document déposé dans
--   le projet".
--
--   Suivant le patron déjà en place pour les transitions de statut
--   sensibles (accept_mandate, decline_mandate, accept_project_invitation,
--   decline_project_invitation — voir ADR-MVP.md §9), l'approbation
--   passe par une RPC SECURITY DEFINER plutôt que par une policy RLS
--   UPDATE ouverte : une policy RLS ne peut pas restreindre l'UPDATE
--   à la seule colonne "status", alors qu'une RPC le peut nativement.
--   La policy "documents_owner_admin_update" existante n'est PAS
--   modifiée : l'admin de l'organisation propriétaire garde son accès
--   direct actuel (dépôt, corrections avant soumission, etc.).
--
-- ATTENTION FRONTEND (S07) :
--   Toute transition de statut d'un document (submitted → approved /
--   rejected) DOIT passer par public.approve_document() — jamais par
--   un UPDATE direct sur public.documents depuis le frontend — pour
--   garantir un business_event unique et cohérent (cf. INC-S06-06 :
--   ne jamais dupliquer un business_event déjà inséré par une RPC).
-- ============================================================

CREATE OR REPLACE FUNCTION public.approve_document(
    p_document_id UUID,
    p_decision    text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doc         public.documents%ROWTYPE;
    v_actor_id    UUID;
    v_mandate     public.mandates%ROWTYPE;
    v_actor_org   UUID;
    v_event_type  public.ccf_event_type;
BEGIN
    v_actor_id := auth.uid();
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_actor_id) THEN
        RAISE EXCEPTION 'Profil introuvable pour l''utilisateur courant';
    END IF;

    IF p_decision NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'Décision invalide : "%" (attendu : approved ou rejected)', p_decision;
    END IF;

    SELECT * INTO v_doc FROM public.documents WHERE id = p_document_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Document introuvable';
    END IF;

    IF v_doc.status != 'submitted' THEN
        RAISE EXCEPTION 'Document non soumis (statut actuel: %)', v_doc.status;
    END IF;

    -- Autorisation : mandataire actif, détenteur de 'approve_documents',
    -- lié au projet propriétaire du document via project_participants.mandate_id.
    IF v_doc.object_type = 'project' THEN
        SELECT m.* INTO v_mandate
        FROM public.mandates m
        JOIN public.project_participants pp ON pp.mandate_id = m.id
        WHERE pp.project_id = v_doc.object_id
          AND pp.status = 'active'
          AND m.status = 'active'
          AND (m.end_date IS NULL OR m.end_date::date >= current_date)
          AND m.permissions -> 'actions' ? 'approve_documents'
          AND public.is_organization_member(m.receiver_org_id)
        LIMIT 1;
    END IF;

    IF v_mandate.id IS NOT NULL THEN
        v_actor_org := v_mandate.receiver_org_id;
    ELSIF public.is_organization_owner(v_doc.owner_org_id) THEN
        -- Repli : l'admin de l'organisation propriétaire garde la capacité
        -- d'approuver/refuser son propre document (déjà permis via
        -- documents_owner_admin_update ; centralisé ici pour garantir
        -- un business_event unique quel que soit le chemin emprunté).
        v_actor_org := v_doc.owner_org_id;
    ELSE
        RAISE EXCEPTION
            'Non autorisé : ni mandataire actif avec approve_documents pour ce projet, '
            'ni admin de l''organisation propriétaire du document';
    END IF;

    UPDATE public.documents
    SET status = p_decision, updated_at = now()
    WHERE id = p_document_id;

    v_event_type := CASE p_decision
        WHEN 'approved' THEN 'document_approved'
        ELSE 'document_rejected'
    END;

    INSERT INTO public.business_events (event_type, object_type, object_id, actor_id, organization_id, payload)
    VALUES (
        v_event_type, 'document', p_document_id, v_actor_id, v_actor_org,
        jsonb_build_object(
            'document_id', p_document_id,
            'decision', p_decision,
            'via_mandate_id', v_mandate.id
        )
    );

    RETURN jsonb_build_object('document_id', p_document_id, 'status', p_decision);
END;
$$;
