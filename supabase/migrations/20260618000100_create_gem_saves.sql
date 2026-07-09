-- gem_saves: per-user "saved" relationship for gems.
--
-- UNWIRED for v1. The app currently tracks saves in memory (GemProvider +
-- GemRepository.saveGem/unsaveGem), so nothing reads or writes this table yet.
-- It is delivered now so the schema is ready when we swap the in-memory seam
-- for real persistence: at that point GemRepository.saveGem/unsaveGem upsert /
-- delete rows here and fetchGems can left-join saved state per user.
--
-- One row per (user, gem). The composite primary key makes saves idempotent
-- and lets a delete unsave without needing a surrogate id.

create table if not exists public.gem_saves (
  user_id uuid not null references auth.users (id) on delete cascade,
  gem_id uuid not null references public.saved_gems (id) on delete cascade,
  saved_at timestamptz not null default now(),
  primary key (user_id, gem_id)
);

-- Look up "all gems this user saved" cheaply.
create index if not exists gem_saves_user_id_idx on public.gem_saves (user_id);

alter table public.gem_saves enable row level security;

-- A user may only see and manage their own saves.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'gem_saves'
      and policyname = 'gem_saves_select_own'
  ) then
    create policy gem_saves_select_own on public.gem_saves
      for select using (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'gem_saves'
      and policyname = 'gem_saves_insert_own'
  ) then
    create policy gem_saves_insert_own on public.gem_saves
      for insert with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'gem_saves'
      and policyname = 'gem_saves_delete_own'
  ) then
    create policy gem_saves_delete_own on public.gem_saves
      for delete using (auth.uid() = user_id);
  end if;
end $$;
