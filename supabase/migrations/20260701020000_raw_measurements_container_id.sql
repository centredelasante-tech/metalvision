-- Migration: add container_id to raw_measurements
-- Synchronizes Rocket migration history with the column already added via SQL Editor

ALTER TABLE public.raw_measurements
    ADD COLUMN IF NOT EXISTS container_id UUID
        REFERENCES public.containers(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_raw_measurements_container_id
    ON public.raw_measurements (container_id);
