-- ============================================================
-- CCF-008 — Événements métier et Logs d'audit
-- ============================================================
--
-- DÉCISIONS D'ARCHITECTURE APPLIQUÉES :
--   Ordre inversé (RT — décision 7) : cette migration (anciennement 007)
--   est exécutée APRÈS logistics_steps et value_reports (migration 007),
--   car business_events.object_type référence ces tables comme cibles.
--
-- CONTENU :
--   1. Table business_events
--   2. Table audit_logs
--   3. Fonction trigger d'audit automatique
--   4. Triggers d'audit sur les tables gouvernées
--   5. Indexes
--   6. RLS
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. TABLE : business_events
-- ════════════════════════════════════════════════════════════
-- Journal des événements métier significatifs (applicatifs).
-- Alimenté par le code applicatif pour les transitions importantes.
-- Distinct de audit_logs (technique, alimenté par triggers DB).
-- actor_id référence profiles.id (MVP-DA-010 — jamais auth.users).
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.business_events (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type   public.ccf_event_type NOT NULL,
    object_type  text NOT NULL
        CHECK (object_type IN (
            'organization',
            'capability',
            'opportunity',
            'project',
            'mandate',
            'document',
            'logistics_step',
            'value_report'
        )),
    object_id     UUID NOT NULL,
    actor_id      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
    payload       jsonb,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ════════════════════════════════════════════════════════════
-- 2. TABLE : audit_logs
-- ════════════════════════════════════════════════════════════
-- Journal technique d'audit (CRUD brut, avant/après).
-- Alimenté automatiquement par triggers PostgreSQL.
-- actor_id référence profiles.id (MVP-DA-010 — jamais auth.users).
-- Distinct de business_events (applicatifs, événements métier seulement).
-- Un fait ne doit jamais figurer dans les deux journaux.
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action      text NOT NULL
        CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    table_name  text NOT NULL,
    record_id   UUID,
    before      jsonb,
    after       jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ════════════════════════════════════════════════════════════
-- 3. FONCTION TRIGGER : audit automatique
-- ════════════════════════════════════════════════════════════
-- Enregistre automatiquement les opérations CRUD sur les tables
-- gouvernées dans audit_logs.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.audit_log_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor_id UUID;
    v_record_id UUID;
    v_before jsonb;
    v_after jsonb;
BEGIN
    -- Résoudre l'actor_id depuis profiles (via auth.uid())
    SELECT id INTO v_actor_id
    FROM public.profiles
    WHERE id = auth.uid()
    LIMIT 1;

    IF TG_OP = 'DELETE' THEN
        v_record_id := OLD.id;
        v_before    := to_jsonb(OLD);
        v_after     := NULL;
    ELSIF TG_OP = 'INSERT' THEN
        v_record_id := NEW.id;
        v_before    := NULL;
        v_after     := to_jsonb(NEW);
    ELSE -- UPDATE
        v_record_id := NEW.id;
        v_before    := to_jsonb(OLD);
        v_after     := to_jsonb(NEW);
    END IF;

    INSERT INTO public.audit_logs (actor_id, action, table_name, record_id, before, after)
    VALUES (v_actor_id, TG_OP, TG_TABLE_NAME, v_record_id, v_before, v_after);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 4. TRIGGERS D'AUDIT sur les tables gouvernées CCF
-- ════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS audit_organizations ON public.organizations;
CREATE TRIGGER audit_organizations
    AFTER INSERT OR UPDATE OR DELETE ON public.organizations
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_organization_members ON public.organization_members;
CREATE TRIGGER audit_organization_members
    AFTER INSERT OR UPDATE OR DELETE ON public.organization_members
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_mandates ON public.mandates;
CREATE TRIGGER audit_mandates
    AFTER INSERT OR UPDATE OR DELETE ON public.mandates
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_ccf_projects ON public.ccf_projects;
CREATE TRIGGER audit_ccf_projects
    AFTER INSERT OR UPDATE OR DELETE ON public.ccf_projects
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_project_participants ON public.project_participants;
CREATE TRIGGER audit_project_participants
    AFTER INSERT OR UPDATE OR DELETE ON public.project_participants
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_documents ON public.documents;
CREATE TRIGGER audit_documents
    AFTER INSERT OR UPDATE OR DELETE ON public.documents
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_logistics_steps ON public.logistics_steps;
CREATE TRIGGER audit_logistics_steps
    AFTER INSERT OR UPDATE OR DELETE ON public.logistics_steps
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

DROP TRIGGER IF EXISTS audit_value_reports ON public.value_reports;
CREATE TRIGGER audit_value_reports
    AFTER INSERT OR UPDATE OR DELETE ON public.value_reports
    FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger_fn();

-- ════════════════════════════════════════════════════════════
-- 5. INDEXES
-- ════════════════════════════════════════════════════════════

-- business_events
CREATE INDEX IF NOT EXISTS idx_business_events_type       ON public.business_events (event_type);
CREATE INDEX IF NOT EXISTS idx_business_events_object     ON public.business_events (object_type, object_id);
CREATE INDEX IF NOT EXISTS idx_business_events_actor      ON public.business_events (actor_id);
CREATE INDEX IF NOT EXISTS idx_business_events_org        ON public.business_events (organization_id);
CREATE INDEX IF NOT EXISTS idx_business_events_created_at ON public.business_events (created_at DESC);

-- audit_logs
CREATE INDEX IF NOT EXISTS idx_audit_logs_table_name  ON public.audit_logs (table_name);
CREATE INDEX IF NOT EXISTS idx_audit_logs_record_id   ON public.audit_logs (record_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor       ON public.audit_logs (actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at  ON public.audit_logs (created_at DESC);

-- ════════════════════════════════════════════════════════════
-- 6. RLS
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.business_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs      ENABLE ROW LEVEL SECURITY;

-- ── business_events ───────────────────────────────────────────

-- SELECT : visible dans le contexte autorisé de l'utilisateur
-- (membre d'une organisation liée à l'événement)
DROP POLICY IF EXISTS "business_events_org_select" ON public.business_events;
CREATE POLICY "business_events_org_select"
    ON public.business_events
    FOR SELECT
    TO authenticated
    USING (
        public.is_organization_member(organization_id)
        OR actor_id = auth.uid()
    );

-- INSERT : le code applicatif insère sous le contexte JWT de l'utilisateur
DROP POLICY IF EXISTS "business_events_authenticated_insert" ON public.business_events;
CREATE POLICY "business_events_authenticated_insert"
    ON public.business_events
    FOR INSERT
    TO authenticated
    WITH CHECK (actor_id = auth.uid());

-- Super-admin : lecture complète
DROP POLICY IF EXISTS "business_events_superadmin_select" ON public.business_events;
CREATE POLICY "business_events_superadmin_select"
    ON public.business_events
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());

-- ── audit_logs ────────────────────────────────────────────────

-- SELECT : super-admin plateforme uniquement dans le MVP
-- Aucun droit d'écriture pour les utilisateurs (alimenté par triggers)
DROP POLICY IF EXISTS "audit_logs_superadmin_select" ON public.audit_logs;
CREATE POLICY "audit_logs_superadmin_select"
    ON public.audit_logs
    FOR SELECT
    TO authenticated
    USING (public.is_platform_superadmin());
