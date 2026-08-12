-- Lets a client resolve "who is this?" from an email or username without
-- being able to read auth.users directly (clients never can) or scrape
-- profiles by pattern. Backs the traveler-invite search (trip-setup wizard +
-- Trip tab's "+ Add Traveler").
--
-- security definer so it can join auth.users for the email side; deliberately
-- exact-match only (no ilike/wildcard) so it can only confirm a *specific*
-- known email/username is registered, not enumerate the user base. search_path
-- pinned per standard security-definer hardening (prevents a caller-controlled
-- search_path from shadowing public.profiles/auth.users).
create or replace function public.find_user_by_identifier(p_identifier text)
returns table (id uuid, display_name text, avatar_url text, username text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.avatar_url, p.username
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(trim(p_identifier)) <> ''
    and (
      lower(p.username) = lower(trim(p_identifier))
      or lower(u.email) = lower(trim(p_identifier))
    )
  limit 1;
$$;

revoke all on function public.find_user_by_identifier(text) from public;
grant execute on function public.find_user_by_identifier(text) to authenticated;
