-- Migration: company_members_rls_bugfixes
-- Fix 1: Allow the very first authenticated user to insert themselves as 'owner'
--         into company_members when no member exists yet for that company_id.
-- Fix 2: Allow an invited user to read their own invitation by matching
--         auth.jwt() ->> 'email' against the invitation email column.

-- ============================================================
-- FIX 1 — Bootstrap first owner in company_members
-- ============================================================
-- The existing "owners_insert_members" policy requires the inserter to already
-- be an owner (via is_company_owner), which makes it impossible to add the very
-- first member. This new policy allows an authenticated user to insert themselves
-- as 'owner' ONLY when the company has zero existing members.

DROP POLICY IF EXISTS "bootstrap_first_owner" ON public.company_members;
CREATE POLICY "bootstrap_first_owner"
ON public.company_members
FOR INSERT
TO authenticated
WITH CHECK (
    -- The row being inserted must belong to the current user
    user_id = auth.uid()
    -- The role being claimed must be 'owner'
    AND role = 'owner'
    -- No member must exist yet for this company (first-member bootstrap only)
    AND NOT EXISTS (
        SELECT 1
        FROM public.company_members existing
        WHERE existing.company_id = company_members.company_id
    )
);

-- ============================================================
-- FIX 2 — Invited user can read their own invitation
-- ============================================================
-- The existing "members_select_invitations" policy requires the reader to already
-- be a company member, which excludes the invited person who is not yet a member.
-- This additional SELECT policy allows reading when the invitation email matches
-- the email stored in the authenticated user's JWT.

DROP POLICY IF EXISTS "invitee_select_own_invitation" ON public.invitations;
CREATE POLICY "invitee_select_own_invitation"
ON public.invitations
FOR SELECT
TO authenticated
USING (
    email = (auth.jwt() ->> 'email')
);
