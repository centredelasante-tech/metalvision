-- Migration: Replace organizations_authenticated_insert with organizations_superadmin_insert
-- Goal: Restrict INSERT on organizations to platform superadmins only

-- Drop the old permissive policy
DROP POLICY IF EXISTS "organizations_authenticated_insert" ON public.organizations;

-- Create the new restrictive policy using is_platform_superadmin()
DROP POLICY IF EXISTS "organizations_superadmin_insert" ON public.organizations;
CREATE POLICY "organizations_superadmin_insert"
    ON public.organizations
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_platform_superadmin());
