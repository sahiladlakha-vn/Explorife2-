-- Adds a real username concept to profiles (previously nonexistent — only
-- display_name/name were available, neither unique). Backs the new "find a
-- traveler by email or username" flow (trip-setup wizard + Trip tab's
-- "+ Add Traveler"), and gives every user a stable, unique handle to be found
-- by that doesn't require sharing their email.
--
-- Nullable: existing users have none until they set one via the new
-- Settings > Edit profile sheet, so this can't be NOT NULL without a value to
-- backfill first (handled below). Case-insensitive uniqueness is enforced via
-- a unique index on lower(username) rather than a plain UNIQUE constraint, so
-- 'Sahil' and 'sahil' can't both be taken — Postgres unique indexes already
-- treat multiple NULLs as non-conflicting, so untouched rows stay compatible.
alter table public.profiles
  add column if not exists username text;

alter table public.profiles
  add constraint profiles_username_format
  check (username is null or username ~ '^[a-z0-9_]{3,20}$');

create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));

-- One-time backfill: give every existing user without a username a
-- generated starting handle (from display_name/name, falling back to the
-- email local-part), lowercased and stripped to the allowed character set,
-- de-duplicated with a numeric suffix on collision. Users can change this
-- later from Settings — it's a starting point, not a permanent assignment.
do $$
declare
  r record;
  base text;
  candidate text;
  n int;
  suffix text;
begin
  for r in
    select p.id,
           coalesce(nullif(p.display_name, ''), nullif(p.name, ''), split_part(u.email, '@', 1)) as seed
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.username is null
  loop
    base := lower(regexp_replace(coalesce(r.seed, 'user'), '[^a-zA-Z0-9_]', '', 'g'));
    if length(base) = 0 then
      base := 'user';
    end if;
    if length(base) < 3 then
      base := rpad(base, 3, '0');
    end if;
    base := left(base, 20);

    candidate := base;
    n := 0;
    while exists (select 1 from public.profiles where lower(username) = candidate) loop
      n := n + 1;
      suffix := '_' || n::text;
      candidate := left(base, 20 - length(suffix)) || suffix;
    end loop;

    update public.profiles set username = candidate where id = r.id;
  end loop;
end $$;
