-- Migration: add pg_advisory_xact_lock to compute_scan_event_hash
-- Timestamp: 20260630090200
-- Fix race condition: lock on container_id before reading previous_hash

CREATE OR REPLACE FUNCTION public.compute_scan_event_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
DECLARE
    v_previous_hash TEXT;
BEGIN
    -- Acquire a transaction-level advisory lock on this container_id
    -- to prevent concurrent inserts for the same container from forking the chain.
    PERFORM pg_advisory_xact_lock(hashtext(NEW.container_id::TEXT));

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
