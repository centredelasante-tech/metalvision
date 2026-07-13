-- ============================================================
-- Test manuel — approve_document() (INC-S07-01) — REMPLI
-- Coller ce bloc complet dans le SQL Editor Supabase (METALVISION)
-- ============================================================
-- Organisation coordonnatrice / propriétaire du document : Centre de
--   Consolidation Ferroviaire Québec (49672bec)
-- Organisation mandataire (approuve via mandat)          : Test no 2
--   (ee84f866)
-- Utilisateur approbateur (membre actif de Test no 2)    :
--   claudefairplay@hotmail.com (770c67c1)
-- Opportunité existante référencée (non modifiée)         : 5fff231b
--
-- Toutes les lignes créées (projet, mandat, project_participants,
-- document) sont supprimées à la fin — aucune donnée résiduelle,
-- l'opportunité existante n'est jamais modifiée.
-- ============================================================

DO $$
DECLARE
    v_coordinator_org_id UUID := '49672bec-bf1c-4e37-a753-60a4b8346ebe';
    v_mandataire_org_id  UUID := 'ee84f866-ba4d-4bc9-a7f0-78b8d7360d5f';
    v_opportunity_id     UUID := '5fff231b-0a78-4ab9-8269-f571f7fd691a';
    v_approver_user_id   UUID := '770c67c1-3be6-4ebe-b7b4-bd2c06258951';

    v_project_id  UUID;
    v_mandate_id  UUID;
    v_document_id UUID;
    v_result      jsonb;
BEGIN
    -- 1. Créer un projet de test (référence l'opportunité existante, sans la modifier)
    INSERT INTO public.ccf_projects (opportunity_id, title, coordinator_org_id, phase, status)
    VALUES (v_opportunity_id, '[TEST S07] Projet de test approve_document', v_coordinator_org_id, 'draft', 'draft')
    RETURNING id INTO v_project_id;

    -- 2. Créer un mandat actif, receiver = Test no 2, permissions = approve_documents
    INSERT INTO public.mandates (issuer_org_id, receiver_org_id, mandate_scope, permissions, status, start_date)
    VALUES (
        v_coordinator_org_id, v_mandataire_org_id, 'verification',
        jsonb_build_object('actions', jsonb_build_array('approve_documents')),
        'active', now()
    )
    RETURNING id INTO v_mandate_id;

    -- 3. Lier ce mandat au projet via project_participants
    INSERT INTO public.project_participants (project_id, organization_id, mandate_id, status, project_role)
    VALUES (v_project_id, v_mandataire_org_id, v_mandate_id, 'active', 'contributeur');

    -- 4. Créer un document de test, statut 'submitted', déposé par l'org coordonnatrice
    INSERT INTO public.documents (owner_org_id, object_type, object_id, title, visibility, status)
    VALUES (v_coordinator_org_id, 'project', v_project_id, '[TEST S07] Document de test approve_document', 'project', 'submitted')
    RETURNING id INTO v_document_id;

    RAISE NOTICE 'Projet créé : %, Mandat créé : %, Document créé : %', v_project_id, v_mandate_id, v_document_id;

    -- 5. Simuler l'utilisateur mandataire (mock auth.uid() le temps de la transaction)
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_approver_user_id, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);

    -- 6. Appeler la RPC comme le ferait le frontend
    SELECT public.approve_document(v_document_id, 'approved') INTO v_result;
    RAISE NOTICE 'Résultat approve_document() : %', v_result;

    -- 7. Vérifications
    IF (SELECT status FROM public.documents WHERE id = v_document_id) != 'approved' THEN
        RAISE EXCEPTION 'ÉCHEC : le document n''a pas transité vers approved';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.business_events
        WHERE object_id = v_document_id AND event_type = 'document_approved' AND actor_id = v_approver_user_id
    ) THEN
        RAISE EXCEPTION 'ÉCHEC : aucun business_event document_approved trouvé pour cet acteur';
    END IF;

    RAISE NOTICE 'SUCCÈS : document approuvé, business_event confirmé.';

    -- 8. Nettoyage — supprime uniquement les données créées par ce test
    DELETE FROM public.business_events WHERE object_id = v_document_id;
    DELETE FROM public.documents WHERE id = v_document_id;
    DELETE FROM public.project_participants WHERE mandate_id = v_mandate_id;
    DELETE FROM public.mandates WHERE id = v_mandate_id;
    DELETE FROM public.ccf_projects WHERE id = v_project_id;

    RAISE NOTICE 'Nettoyage terminé — aucune donnée résiduelle (opportunité existante non touchée).';
END;
$$;
