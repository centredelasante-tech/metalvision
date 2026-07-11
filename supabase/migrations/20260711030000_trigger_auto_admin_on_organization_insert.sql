-- Migration: MVP-RA-021/022 — Auto-insert creator as admin on organization creation
-- Trigger: handle_new_organization_admin()
-- Fires: AFTER INSERT ON public.organizations
-- Guard: skips silently if auth.uid() IS NULL (e.g. admin seed scripts)
-- No service_role bypass — runs in the authenticated user's security context via SECURITY DEFINER

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Trigger function
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_organization_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    v_user_id UUID;
BEGIN
    -- Capture the authenticated user at the moment of the INSERT
    v_user_id := auth.uid();

    -- Guard: if called outside an authenticated session (e.g. admin seed script),
    -- do nothing rather than raise an error.
    IF v_user_id IS NULL THEN
        RAISE NOTICE 'handle_new_organization_admin: auth.uid() is NULL — skipping auto-admin insert for organization %', NEW.id;
        RETURN NEW;
    END IF;

    -- Auto-insert the creator as admin of the new organization
    INSERT INTO public.organization_members (
        organization_id,
        user_id,
        org_role,
        status,
        activated_at
    )
    VALUES (
        NEW.id,
        v_user_id,
        'admin'::public.org_role,
        'active',
        now()
    )
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$func$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Trigger on public.organizations
-- ─────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS on_organization_created ON public.organizations;

CREATE TRIGGER on_organization_created
    AFTER INSERT ON public.organizations
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_organization_admin();
