-- Multi-photo support for gems, for the gem detail screen's photo gallery
-- (hero + counter + thumbnail strip). `photo_url` stays as-is (the cover
-- photo, unchanged for every existing row and every reader that only knows
-- about a single photo); `photo_urls` is the full ordered set, empty for
-- every gem dropped before this migration. Readers should fall back to
-- `[photo_url]` when `photo_urls` is empty.
alter table public.saved_gems
  add column if not exists photo_urls text[] not null default '{}';
