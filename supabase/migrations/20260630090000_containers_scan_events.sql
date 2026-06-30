-- Migration: containers and scan_events tables
-- Timestamp: 20260630090000

-- ============================================================
-- 1. TABLE: containers
-- ============================================================
CREATE TABLE IF NOT EXISTS public.containers (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID        NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    qr_code     TEXT        NOT NULL,
    name        TEXT        NOT NULL,
    location    TEXT,
    status      TEXT        NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT containers_qr_code_unique UNIQUE (qr_code),
    CONSTRAINT containers_status_check CHECK (status IN ('active', 'inactive', 'maintenance'))
);

-- ============================================================
-- 2. TABLE: scan_events
-- ============================================================
CREATE TABLE IF NOT EXISTS public.scan_events (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    container_id    UUID        NOT NULL REFERENCES public.containers(id) ON DELETE CASCADE,
    company_id      UUID        NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id         UUID        NOT NULL,
    action_type     TEXT        NOT NULL,
    gps_lat         NUMERIC(10,7),
    gps_lng         NUMERIC(10,7),
    gps_accuracy_m  NUMERIC(6,2),
    scanned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT scan_events_action_type_check CHECK (action_type IN ('depot', 'collecte', 'verification'))
);

-- ============================================================
-- 3. INDEXES
-- ============================================================

-- containers
CREATE INDEX IF NOT EXISTS idx_containers_company_id
    ON public.containers (company_id);

CREATE INDEX IF NOT EXISTS idx_containers_qr_code
    ON public.containers (qr_code);

-- scan_events
CREATE INDEX IF NOT EXISTS idx_scan_events_company_id
    ON public.scan_events (company_id);

CREATE INDEX IF NOT EXISTS idx_scan_events_container_id
    ON public.scan_events (container_id);

CREATE INDEX IF NOT EXISTS idx_scan_events_scanned_at
    ON public.scan_events (scanned_at);

CREATE INDEX IF NOT EXISTS idx_scan_events_container_scanned
    ON public.scan_events (container_id, scanned_at);

-- ============================================================
-- 4. ENABLE RLS
-- ============================================================
ALTER TABLE public.containers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_events ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 5. RLS POLICIES — containers
-- (uses existing functions is_company_member / is_company_owner)
-- ============================================================

DROP POLICY IF EXISTS "containers_select_members"  ON public.containers;
CREATE POLICY "containers_select_members"
    ON public.containers
    FOR SELECT
    TO authenticated
    USING (public.is_company_member(company_id));

DROP POLICY IF EXISTS "containers_insert_owners"   ON public.containers;
CREATE POLICY "containers_insert_owners"
    ON public.containers
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_company_owner(company_id));

DROP POLICY IF EXISTS "containers_update_owners"   ON public.containers;
CREATE POLICY "containers_update_owners"
    ON public.containers
    FOR UPDATE
    TO authenticated
    USING (public.is_company_owner(company_id))
    WITH CHECK (public.is_company_owner(company_id));

DROP POLICY IF EXISTS "containers_delete_owners"   ON public.containers;
CREATE POLICY "containers_delete_owners"
    ON public.containers
    FOR DELETE
    TO authenticated
    USING (public.is_company_owner(company_id));

-- ============================================================
-- 6. RLS POLICIES — scan_events
-- Insert-only table (no UPDATE / DELETE policies)
-- ============================================================

DROP POLICY IF EXISTS "scan_events_select_members" ON public.scan_events;
CREATE POLICY "scan_events_select_members"
    ON public.scan_events
    FOR SELECT
    TO authenticated
    USING (public.is_company_member(company_id));

-- INSERT: member of the company AND user_id must equal auth.uid()
DROP POLICY IF EXISTS "scan_events_insert_members" ON public.scan_events;
CREATE POLICY "scan_events_insert_members"
    ON public.scan_events
    FOR INSERT
    TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        AND public.is_company_member(company_id)
    );
