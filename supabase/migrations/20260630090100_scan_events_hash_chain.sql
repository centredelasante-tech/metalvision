-- Migration: hash chain for scan_events (pgcrypto)
-- Timestamp: 20260630090100

-- ============================================================
-- 1. Enable pgcrypto (idempotent)
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 2. Add hash columns to scan_events
-- ============================================================
ALTER TABLE public.scan_events
    ADD COLUMN IF NOT EXISTS previous_hash TEXT,
    ADD COLUMN IF NOT EXISTS event_hash    TEXT;

-- Make event_hash NOT NULL after adding (safe: existing rows get NULL first,
-- then we set a default so the constraint can be applied).
-- For a brand-new table this is straightforward.
-- We use a DO block to handle the case where rows already exist.
DO $$
BEGIN
    -- Back-fill any existing rows that have no event_hash yet
    UPDATE public.scan_events
    SET event_hash = encode(
            digest(
                COALESCE(previous_hash, '') ||
                container_id::TEXT ||
                company_id::TEXT ||
                user_id::TEXT ||
                action_type ||
                COALESCE(gps_lat::TEXT, '') ||
                COALESCE(gps_lng::TEXT, '') ||
                scanned_at::TEXT,
                'sha256'
            ),
            'hex'
        )
    WHERE event_hash IS NULL;
END $$;

-- Now enforce NOT NULL
ALTER TABLE public.scan_events
    ALTER COLUMN event_hash SET NOT NULL;

-- ============================================================
-- 3. Trigger function: compute_scan_event_hash (BEFORE INSERT)
-- ============================================================
CREATE OR REPLACE FUNCTION public.compute_scan_event_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
    v_previous_hash TEXT;
BEGIN
    -- Retrieve the event_hash of the most recent scan for this container
    SELECT event_hash
    INTO   v_previous_hash
    FROM   public.scan_events
    WHERE  container_id = NEW.container_id
    ORDER  BY scanned_at DESC
    LIMIT  1;

    -- Assign previous_hash (NULL if this is the first event for the container)
    NEW.previous_hash := v_previous_hash;

    -- Compute the hash for this new event
    NEW.event_hash := encode(
        digest(
            COALESCE(NEW.previous_hash, '') ||
            NEW.container_id::TEXT          ||
            NEW.company_id::TEXT            ||
            NEW.user_id::TEXT               ||
            NEW.action_type                 ||
            COALESCE(NEW.gps_lat::TEXT, '') ||
            COALESCE(NEW.gps_lng::TEXT, '') ||
            NEW.scanned_at::TEXT,
            'sha256'
        ),
        'hex'
    );

    RETURN NEW;
END;
$func$;

-- ============================================================
-- 4. Attach trigger to scan_events
-- ============================================================
DROP TRIGGER IF EXISTS trg_compute_scan_event_hash ON public.scan_events;
CREATE TRIGGER trg_compute_scan_event_hash
    BEFORE INSERT ON public.scan_events
    FOR EACH ROW
    EXECUTE FUNCTION public.compute_scan_event_hash();

-- ============================================================
-- 5. Public verification function: verify_container_chain
-- Returns (event_id, scanned_at, is_valid) for every event
-- of a given container, in chronological order.
-- is_valid = false if the recomputed hash differs from stored.
-- ============================================================
CREATE OR REPLACE FUNCTION public.verify_container_chain(p_container_id UUID)
RETURNS TABLE (
    event_id   UUID,
    scanned_at TIMESTAMPTZ,
    is_valid   BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
    r              RECORD;
    v_running_hash TEXT := NULL;
    v_expected     TEXT;
BEGIN
    FOR r IN
        SELECT
            se.id,
            se.container_id,
            se.company_id,
            se.user_id,
            se.action_type,
            se.gps_lat,
            se.gps_lng,
            se.scanned_at,
            se.previous_hash,
            se.event_hash
        FROM public.scan_events se
        WHERE se.container_id = p_container_id
        ORDER BY se.scanned_at ASC
    LOOP
        -- Recompute expected hash using the running previous hash
        v_expected := encode(
            digest(
                COALESCE(v_running_hash, '')   ||
                r.container_id::TEXT           ||
                r.company_id::TEXT             ||
                r.user_id::TEXT                ||
                r.action_type                  ||
                COALESCE(r.gps_lat::TEXT, '')  ||
                COALESCE(r.gps_lng::TEXT, '')  ||
                r.scanned_at::TEXT,
                'sha256'
            ),
            'hex'
        );

        event_id   := r.id;
        scanned_at := r.scanned_at;
        is_valid   := (r.event_hash = v_expected);

        RETURN NEXT;

        -- Advance the chain
        v_running_hash := r.event_hash;
    END LOOP;
END;
$func$;
