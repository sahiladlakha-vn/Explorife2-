-- admin_action_log.actor_id has cascaded on the acting admin's auth.users
-- row being deleted ever since the table was created
-- (20260903000300_create_admin_action_log.sql) — wrong for an audit log:
-- deleting an account (including, as of this feature, the ephemeral QA
-- accounts its own test harnesses create and delete) silently wipes every
-- row where that account was ever the *actor*, destroying history for
-- actions that really happened just because the actor's account later
-- went away.
--
-- Switched to ON DELETE SET NULL: the row survives, actor_id just goes
-- null. That requires dropping the NOT NULL constraint first (SET NULL
-- can't satisfy a non-nullable column) — AdminActionLogEntry.actorId is
-- updated to String? in the same commit as this migration to match.
--
-- target_profile_id was never FK-constrained in the first place (see its
-- own doc comment in the original migration — it deliberately has no
-- single target table, since a future listing-moderation action's target
-- won't always be a profiles/auth.users row). It was never at risk of
-- cascading a row away and needs no change here.
alter table public.admin_action_log
  alter column actor_id drop not null;

alter table public.admin_action_log
  drop constraint admin_action_log_actor_id_fkey;

alter table public.admin_action_log
  add constraint admin_action_log_actor_id_fkey
  foreign key (actor_id) references auth.users (id) on delete set null;
