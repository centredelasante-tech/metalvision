-- ============================================================
-- CCF-005b — Cohérence mandate_id sur project_participants
-- ============================================================
--
-- CONSTAT (revue backend S05 — /projets/:id, 12 juillet 2026) :
--   La policy "project_participants_update" (ccf_005) autorise soit
--   l'admin de l'organisation coordinatrice, soit l'admin de
--   l'organisation participante elle-même (is_organization_owner(organization_id))
--   à modifier une ligne project_participants — sans restriction sur
--   les colonnes modifiables. Un admin d'organisation participante
--   peut donc réécrire sa propre colonne mandate_id vers N'IMPORTE
--   QUEL mandat existant dans la base, sans aucune validation que ce
--   mandat concerne réellement ce projet ou cette organisation.
--
--   Risque concret : project_participants.mandate_id est utilisé par
--   approve_document() (ccf_006e, INC-S07-01) pour vérifier qu'un
--   mandataire détient bien un mandat actif avec 'approve_documents'
--   lié à ce projet. Sans validation relationnelle, un admin pourrait
--   théoriquement pointer mandate_id vers un mandat sans rapport avec
--   ce projet (ex. un mandat 'approve_documents' obtenu ailleurs dans
--   le système) pour se rendre éligible à l'approbation de documents
--   d'un projet auquel ce mandat n'a jamais été destiné.
--
--   Note : project_participants.project_role n'est vérifié par aucune
--   policy ni fonction RLS ailleurs dans le schéma (confirmé par grep) —
--   une auto-élévation de ce champ reste cosmétique, pas un risque de
--   sécurité. Seul mandate_id nécessite une correction.
--
-- CORRECTION :
--   Trigger BEFORE INSERT/UPDATE validant, quand mandate_id est
--   renseigné : le mandat doit être reçu par cette même organisation
--   (mandates.receiver_org_id = project_participants.organization_id)
--   et émis par l'organisation coordinatrice de ce projet
--   (mandates.issuer_org_id = ccf_projects.coordinator_org_id).
--   N'affecte que les écritures futures — aucune ligne existante
--   n'est modifiée ou revalidée rétroactivement.
-- ============================================================

CREATE OR REPLACE FUNCTION public.enforce_project_participants_mandate_consistency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mandate public.mandates%ROWTYPE;
    v_project public.ccf_projects%ROWTYPE;
BEGIN
    IF NEW.mandate_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_mandate FROM public.mandates WHERE id = NEW.mandate_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mandat introuvable pour project_participants.mandate_id (%).', NEW.mandate_id;
    END IF;

    SELECT * INTO v_project FROM public.ccf_projects WHERE id = NEW.project_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Projet introuvable pour project_participants.project_id (%).', NEW.project_id;
    END IF;

    IF v_mandate.receiver_org_id != NEW.organization_id THEN
        RAISE EXCEPTION
            'mandate_id (%) ne correspond pas a l''organisation participante (%) : '
            'ce mandat n''est pas recu par cette organisation.',
            NEW.mandate_id, NEW.organization_id;
    END IF;

    IF v_mandate.issuer_org_id != v_project.coordinator_org_id THEN
        RAISE EXCEPTION
            'mandate_id (%) n''a pas ete emis par l''organisation coordinatrice '
            'du projet (%).',
            NEW.mandate_id, v_project.coordinator_org_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_participants_enforce_mandate_consistency ON public.project_participants;
CREATE TRIGGER project_participants_enforce_mandate_consistency
    BEFORE INSERT OR UPDATE ON public.project_participants
    FOR EACH ROW EXECUTE FUNCTION public.enforce_project_participants_mandate_consistency();
