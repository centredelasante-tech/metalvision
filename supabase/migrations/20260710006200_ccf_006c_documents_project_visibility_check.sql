-- ============================================================
-- CCF-006c — Documents : contrainte CHECK visibility/object_type
-- ============================================================
--
-- MVP-RA-028 : Garantit que tout document avec visibility = 'project'
-- référence bien un objet de type 'project'.
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
