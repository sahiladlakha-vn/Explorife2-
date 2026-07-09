-- Add a first-class, nullable `tagline` column to saved_gems.
--
-- Why: the Drop a Gem form collects a short one-line tagline used as the hook on
-- the Gen Z browse card. Until now it was lossily folded into `description`.
-- Making it a real column lets the UI render it independently. It stays NULLable
-- and optional in the form, so existing rows and future submits never break.
--
-- Safe to run more than once (IF NOT EXISTS).

alter table public.saved_gems
  add column if not exists tagline text;

comment on column public.saved_gems.tagline is
  'Optional one-line hook shown on the gem browse card. Nullable; max ~80 chars enforced in the app.';
