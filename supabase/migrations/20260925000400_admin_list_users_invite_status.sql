-- Adds invited_at/email_confirmed_at so the Users page can compute
-- "Pending invite" itself instead of guessing from last_sign_in_at alone.
-- The return type is changing (2 new columns), so this has to be a
-- drop+create rather than create-or-replace; both statements plus the
-- grant-restoration below run as one migration file, i.e. one transaction,
-- so there's no window where admin_list_users doesn't exist.
begin;

drop function public.admin_list_users(text, integer, integer, boolean, user_role);

create function public.admin_list_users(
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_include_anonymous boolean default false,
  p_role user_role default null
)
returns table(
  id uuid, display_name text, username text, avatar_url text, email text,
  provider text, is_anonymous boolean, role user_role, created_at timestamptz,
  trip_count bigint, total_count bigint,
  invited_at timestamptz, email_confirmed_at timestamptz
)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = any (array[
        'content_moderator', 'regional_admin', 'super_admin', 'finance_admin'
      ]::user_role[])
  ) then
    return;
  end if;

  return query
  select
    pr.id,
    pr.display_name,
    pr.username,
    pr.avatar_url,
    au.email::text,
    au.raw_app_meta_data->>'provider' as provider,
    coalesce(au.is_anonymous, false) as is_anonymous,
    pr.role,
    pr.created_at,
    coalesce(tc.trip_count, 0) as trip_count,
    count(*) over() as total_count,
    au.invited_at,
    au.email_confirmed_at
  from public.profiles pr
  join auth.users au on au.id = pr.id
    and (p_include_anonymous or coalesce(au.is_anonymous, false) = false)
  left join (
    select owner_id, count(*) as trip_count
    from public.trips
    group by owner_id
  ) tc on tc.owner_id = pr.id
  where (p_role is null or pr.role = p_role)
    and (
      p_search is null or btrim(p_search) = '' or
      pr.display_name ilike '%' || p_search || '%' or
      pr.username ilike '%' || p_search || '%' or
      au.email ilike '%' || p_search || '%'
    )
  order by coalesce(au.is_anonymous, false) asc, pr.created_at desc
  limit greatest(p_limit, 0)
  offset greatest(p_offset, 0);
end;
$function$;

-- Restore the pre-existing grants exactly (authenticated + service_role),
-- minus the anon access the live function had (confirmed via pg_proc.proacl
-- before this migration: anon had an explicit direct EXECUTE grant, a
-- no-op for a non-admin caller since the function returns zero rows, but
-- removed anyway per "explicit revoke from anon on every touched
-- function"). A drop+create resets ACLs to Postgres/Supabase defaults, so
-- this restoration is required, not optional.
revoke execute on function public.admin_list_users(text, integer, integer, boolean, user_role) from public;
revoke execute on function public.admin_list_users(text, integer, integer, boolean, user_role) from anon;
grant execute on function public.admin_list_users(text, integer, integer, boolean, user_role) to authenticated, service_role;

commit;
