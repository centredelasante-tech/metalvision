-- ============================================================
-- CCF-006c — Documents : contrainte CHECK visibility/object_type
-- ============================================================
--
-- MVP-RA-026 : Garantit que tout document avec visibility = 'project'
-- référence bien un objet de type 'project'.
-- (Correction 12 juillet 2026 — revue backend S07 : ce fichier
--  ré-applique la même contrainte MVP-RA-026 déjà posée dans
--  ccf_006, l'en-tête indiquait à tort "MVP-RA-028", qui désigne
--  une règle distincte, sans lien avec ce fichier. Le code SQL
--  ci-dessous était et reste correct ; seule l'étiquette était fausse.
--
-- Contrainte : documents_project_visibility_requires_project_object
--   visibility <> 'project' OR object_type = 'project'
-- ============================================================

ALTER TABLE public.documents
    DROP CONSTRAINT IF EXISTS documents_project_visibility_requires_project_object;

ALTER TABLE public.documents
    ADD CONSTRAINT documents_project_visibility_requires_project_object
    CHECK (
        visibility <> 'project'
        OR object_type = 'project'
    );
