-- Migration: get_invitation_by_token RPC
-- Creates a SECURITY DEFINER function callable by anon role
-- Returns invitation details (company_id, company_name, email, role, status, expires_at)
-- for a given token. Returns nothing if token doesn't exist or is expired/not pending.

-- ============================================================
-- RPC FUNCTION: get_invitation_by_token
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_invitation_by_token(p_token TEXT)
RETURNS TABLE(
    invitation_id   UUID,
    company_id      UUID,
    company_name    TEXT,
    email           TEXT,
    role            TEXT,
    status          TEXT,
    expires_at      TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.id            AS invitation_id,
        i.company_id    AS company_id,
        c.name          AS company_name,
        i.email         AS email,
        i.role::TEXT    AS role,
        i.status::TEXT  AS status,
        i.expires_at    AS expires_at
    FROM public.invitations i
    JOIN public.companies c ON c.id = i.company_id
    WHERE i.token = p_token
      AND i.status = 'pending'
      AND i.expires_at > now();
END;
$$;

-- Grant execute to anon so unauthenticated users can preview the invitation
GRANT EXECUTE ON FUNCTION public.get_invitation_by_token(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_invitation_by_token(TEXT) TO authenticated;
