-- ============================================================
-- CCF-006f — Bucket Supabase Storage 'documents' + policies
-- ============================================================
--
-- CONSTAT (revue backend S07 — /documents, 12 juillet 2026) :
--   E09-T02 du backlog technique (« Configurer Supabase Storage et
--   lien storage_path ») n'a jamais été réalisé — confirmé par
--   `SELECT * FROM storage.buckets` en production : 0 ligne.
--   Le frontend construit par Rocket (src/app/documents/page.tsx)
--   appelle `supabase.storage.from('documents').upload(...)`, qui
--   échouerait systématiquement sans ce bucket.
--
-- CONVENTION DE CHEMIN (fixée par le frontend, à ne pas changer
-- sans mettre à jour les policies ci-dessous) :
--   documents/<owner_org_id>/<timestamp>_<filename>
--   → storage.foldername(name) = {'documents', '<owner_org_id>'}
--
-- CONCEPTION :
--   INSERT : gardé par is_organization_owner() sur l'org_id extrait
--     du chemin — au moment de l'upload, aucune ligne n'existe
--     encore dans public.documents, donc impossible de déléguer à
--     sa RLS ; on réplique la même condition que la policy
--     documents_owner_admin_insert (ccf_006).
--   SELECT : déléguée à la RLS déjà existante sur public.documents,
--     via une fonction SECURITY INVOKER (pas DEFINER) qui interroge
--     public.documents en tant qu'utilisateur courant — RLS
--     s'applique donc normalement, sans dupliquer les 3 branches
--     de visibilité (organization_private/project/confidential)
--     une deuxième fois ici.
--   UPDATE/DELETE : aucune policy — deny-all, cohérent avec
--     MVP-DA-006 (aucune suppression physique, cycle de vie via
--     documents.status uniquement).
-- ============================================================

-- ── 1. Bucket ──────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', false)
ON CONFLICT (id) DO NOTHING;

-- ── 2. Fonction de délégation SELECT vers la RLS de public.documents ──
CREATE OR REPLACE FUNCTION public.can_access_document_storage_path(p_path text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    -- SECURITY INVOKER (pas DEFINER) : cette requête s'exécute avec les
    -- privilèges de l'appelant, donc la RLS de public.documents
    -- (org_private/project/confidential/superadmin) s'applique normalement.
    SELECT EXISTS (
        SELECT 1 FROM public.documents d WHERE d.storage_path = p_path
    );
$$;

-- ── 3. Policies storage.objects ─────────────────────────────────

DROP POLICY IF EXISTS "documents_bucket_insert_owner_admin" ON storage.objects;
CREATE POLICY "documents_bucket_insert_owner_admin"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'documents'
        AND array_length(storage.foldername(name), 1) >= 2
        AND public.is_organization_owner(((storage.foldername(name))[2])::uuid)
    );

DROP POLICY IF EXISTS "documents_bucket_select_via_table_rls" ON storage.objects;
CREATE POLICY "documents_bucket_select_via_table_rls"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'documents'
        AND public.can_access_document_storage_path(name)
    );

DROP POLICY IF EXISTS "documents_bucket_superadmin_select" ON storage.objects;
CREATE POLICY "documents_bucket_superadmin_select"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'documents'
        AND public.is_platform_superadmin()
    );

-- Aucune policy UPDATE/DELETE — deny-all (MVP-DA-006).
