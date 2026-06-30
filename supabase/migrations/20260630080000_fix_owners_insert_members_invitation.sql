-- Migration: Fix owners_insert_members RLS policy on company_members
-- Adds a third condition: a user can self-insert if a valid pending invitation exists
-- matching their email, company_id, and role.

-- Drop and recreate the policy with the additional invitation-based condition
DROP POLICY IF EXISTS "owners_insert_members" ON public.company_members;

CREATE POLICY "owners_insert_members"
ON public.company_members FOR INSERT TO authenticated
WITH CHECK (
  -- Condition 1: an existing owner of this company is inserting
  public.is_company_owner(company_id)

  OR

  -- Condition 2: first-member bootstrap — no members yet, user self-inserts as owner
  (
    public.company_has_no_members(company_id)
    AND user_id = auth.uid()
    AND role = 'owner'
  )

  OR

  -- Condition 3: invited user self-inserts — a valid pending invitation exists
  -- matching their email, this company_id, and the requested role
  (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.invitations inv
      WHERE inv.email       = (auth.jwt() ->> 'email')
        AND inv.company_id  = company_id
        AND inv.role        = role
        AND inv.status      = 'pending'
        AND inv.expires_at  > now()
    )
  )
);
