-- Migration: add status column to raw_measurements
-- Timestamp: 20260630090400
--
-- Changes:
--   1. Add status TEXT NOT NULL DEFAULT 'submitted' with CHECK constraint
--   Existing RLS policies (company_members_select/insert/update_raw_measurements)
--   already cover this column — no policy changes needed.

ALTER TABLE public.raw_measurements
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'submitted'
        CHECK (status IN ('submitted', 'processed', 'invoiced'));
