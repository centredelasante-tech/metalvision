-- ─────────────────────────────────────────────────────────────────────────────
-- Migration : opportunity_capabilities — BEFORE INSERT trigger
-- Ticket    : E06 / §8 cahier fonctionnel
-- Rule      : A capability must be in 'declared' or 'qualified' status
--             before it can be associated with an opportunity.
--             'draft' capabilities are NOT eligible.
--
-- CHOICE: BEFORE INSERT TRIGGER (not CHECK constraint with subquery)
-- Rationale: PostgreSQL CHECK constraints CANNOT contain subqueries
--            (per SQL standard and Supabase/Postgres enforcement).
--            A BEFORE INSERT trigger is the correct, idiomatic approach:
--            - Executes before the row is written
--            - Can query other tables (capabilities) freely
--            - Raises a clear, descriptive exception visible to the client
--            - Is idempotent (DROP TRIGGER IF EXISTS before CREATE TRIGGER)
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Trigger function
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_capability_status_before_opp_cap_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    v_cap_status text;
BEGIN
    -- Fetch the current status of the referenced capability
    SELECT status
      INTO v_cap_status
      FROM public.capabilities
     WHERE id = NEW.capability_id;

    -- Capability must exist and be in an eligible status
    IF v_cap_status IS NULL THEN
        RAISE EXCEPTION
            'capability_not_found: capability % does not exist.',
            NEW.capability_id;
    END IF;

    IF v_cap_status NOT IN ('declared', 'qualified') THEN
        RAISE EXCEPTION
            'capability_not_eligible: capability % has status ''%'' — only ''declared'' or ''qualified'' capabilities may be associated with an opportunity.',
            NEW.capability_id,
            v_cap_status;
    END IF;

    RETURN NEW;
END;
$func$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Attach trigger to opportunity_capabilities
-- ─────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_check_capability_status_before_opp_cap_insert
    ON public.opportunity_capabilities;

CREATE TRIGGER trg_check_capability_status_before_opp_cap_insert
    BEFORE INSERT
    ON public.opportunity_capabilities
    FOR EACH ROW
    EXECUTE FUNCTION public.check_capability_status_before_opp_cap_insert();
