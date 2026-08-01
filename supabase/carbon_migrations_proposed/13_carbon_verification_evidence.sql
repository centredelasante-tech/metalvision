-- ============================================================================
-- Migration 13 — Preuve de vérification (evidence_files) : combler le trou
-- structurel qui empêche toute clôture de vérification
-- ============================================================================
--
-- CONTEXTE / BUG RÉEL TROUVÉ EN PRODUCTION (Lot 4, régression transverse) :
--
-- complete_verification_session() (migration 05) exige un
-- verification_report_document_id référençant une ligne evidence_files avec
-- type='verification_report', project_id correspondant et file_hash non vide.
-- Or, en pratique :
--   1. Aucun chemin du frontend n'écrit jamais evidence_files.file_hash
--      (les deux seuls INSERT existants, api/transport/internal-create et
--      api/projects/[id]/log-activity, l'omettent tous les deux).
--   2. La seule policy RLS d'écriture sur evidence_files est
--      admin_manage_evidence_files (ALL, is_project_admin()) — le
--      vérificateur assigné n'a que verifier_read_evidence_files (SELECT
--      seul). Un INSERT direct depuis /verifier-mrv échouerait de toute
--      façon.
--   3. Aucun bucket Supabase Storage n'existe pour accueillir ce type de
--      preuve (seul le bucket 'documents', dédié au domaine CCF, existe).
--
-- Résultat : dans l'état antérieur à cette migration, aucune vérification
-- ne pouvait JAMAIS être complétée par le vérificateur assigné, quel que
-- soit le chemin emprunté — trou plus profond que le simple bouton
-- « Démarrer » corrigé en migration 12.
--
-- FIX : un nouveau bucket Storage dédié ('verification-evidence'), suivant
-- exactement le patron déjà validé pour le bucket 'documents'
-- (20260712110000_ccf_006f_documents_storage_bucket.sql) — INSERT gardé par
-- une autorisation directe sur le chemin (ici : is_assigned_verifier() sur
-- le segment session_id), SELECT délégué à la RLS réelle de evidence_files
-- via une fonction SECURITY INVOKER, aucune policy UPDATE/DELETE
-- (deny-all, append-only). Plus une RPC record_verification_report_evidence()
-- qui insère la ligne evidence_files pour le compte du vérificateur assigné
-- (SECURITY DEFINER, même patron que start_verification_session()).
--
-- CONVENTION DE CHEMIN (fixée ici, à ne pas changer sans mettre à jour les
-- policies) :
--   verification-evidence/<verification_session_id>/<timestamp>_<filename>
--   → storage.foldername(name) = {'<verification_session_id>'}
--
-- AUCUNE migration existante (01 à 12) n'est modifiée. Ce fichier est
-- strictement additif.
-- ============================================================================

-- ── 1. Bucket ────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('verification-evidence', 'verification-evidence', false)
ON CONFLICT (id) DO NOTHING;

-- ── 2. RPC d'insertion evidence_files pour le vérificateur assigné ────────
CREATE OR REPLACE FUNCTION public.record_verification_report_evidence(
    p_verification_session_id uuid,
    p_file_url text,
    p_file_hash text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actor       UUID;
    v_project_id  UUID;
    v_evidence_id UUID;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    SELECT project_id INTO v_project_id
    FROM public.verification_sessions
    WHERE id = p_verification_session_id
      AND verifier_user_id = v_actor
    FOR SHARE;

    IF v_project_id IS NULL THEN
        RAISE EXCEPTION 'Session introuvable ou accès refusé.';
    END IF;

    PERFORM 1 FROM public.accredited_verifiers WHERE user_id = v_actor AND active FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Accréditation de vérificateur révoquée ou introuvable : impossible d''enregistrer une preuve.';
    END IF;

    IF p_file_url IS NULL OR btrim(p_file_url) = '' THEN
        RAISE EXCEPTION 'file_url est obligatoire.';
    END IF;
    IF p_file_hash IS NULL OR btrim(p_file_hash) = '' THEN
        RAISE EXCEPTION 'file_hash est obligatoire (intégrité du document de preuve).';
    END IF;

    INSERT INTO public.evidence_files (project_id, file_url, type, file_hash, actor_id, "timestamp")
    VALUES (v_project_id, p_file_url, 'verification_report', p_file_hash, v_actor, clock_timestamp())
    RETURNING id INTO v_evidence_id;

    RETURN v_evidence_id;
END;
$function$;

COMMENT ON FUNCTION public.record_verification_report_evidence(uuid, text, text) IS
'Insère une ligne evidence_files (type=verification_report) pour le compte du vérificateur assigné à la session. Comble le trou structurel qui empêchait toute complétion de vérification (aucune policy RLS écriture sur evidence_files pour le vérificateur, aucun chemin frontend ne renseignait file_hash). Migration 13, Lot 4.';

GRANT EXECUTE ON FUNCTION public.record_verification_report_evidence(uuid, text, text) TO authenticated;

-- ── 3. Fonction de délégation SELECT vers la RLS de public.evidence_files ──
CREATE OR REPLACE FUNCTION public.can_access_verification_evidence_storage_path(p_path text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
    -- SECURITY INVOKER (pas DEFINER) : cette requête s'exécute avec les
    -- privilèges de l'appelant, donc la RLS de public.evidence_files
    -- (admin_manage_evidence_files / client_read_evidence_files /
    -- verifier_read_evidence_files) s'applique normalement — même patron
    -- que can_access_document_storage_path() pour le bucket 'documents'.
    SELECT EXISTS (
        SELECT 1 FROM public.evidence_files e WHERE e.file_url = p_path
    );
$$;

-- ── 4. Policies storage.objects ────────────────────────────────────────────

DROP POLICY IF EXISTS "verification_evidence_bucket_insert_assigned_verifier" ON storage.objects;
CREATE POLICY "verification_evidence_bucket_insert_assigned_verifier"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'verification-evidence'
        AND array_length(storage.foldername(name), 1) >= 1
        AND public.is_assigned_verifier(((storage.foldername(name))[1])::uuid)
    );

DROP POLICY IF EXISTS "verification_evidence_bucket_select_via_table_rls" ON storage.objects;
CREATE POLICY "verification_evidence_bucket_select_via_table_rls"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'verification-evidence'
        AND public.can_access_verification_evidence_storage_path(name)
    );

DROP POLICY IF EXISTS "verification_evidence_bucket_superadmin_select" ON storage.objects;
CREATE POLICY "verification_evidence_bucket_superadmin_select"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'verification-evidence'
        AND public.is_platform_superadmin()
    );

-- Aucune policy UPDATE/DELETE — deny-all (append-only, cohérent avec
-- MVP-DA-006 et le patron du bucket 'documents').
