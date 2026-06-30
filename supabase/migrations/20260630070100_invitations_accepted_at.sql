-- Migration: add accepted_at column to invitations
-- Adds the accepted_at timestamp column used when an invitation is accepted

ALTER TABLE public.invitations
ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
