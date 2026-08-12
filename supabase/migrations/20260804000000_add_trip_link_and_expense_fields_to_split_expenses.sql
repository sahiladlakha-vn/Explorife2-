-- Extends the existing (already-live) split_expenses table with trip-awareness
-- and richer expense metadata, rather than introducing a second, overlapping
-- expenses table. split_expenses currently has: id, group_id, paid_by,
-- description, amount, currency, created_at (confirmed against the live
-- SplitExpense/SplitGroup models in lib/models/hike.dart — this table has no
-- migration file on record, so that Dart model is the source of truth for its
-- current shape). Everything below is additive and nullable; existing rows and
-- the existing app code that only writes the original columns are unaffected.
--
-- RLS is deliberately NOT touched here. Whatever RLS state split_expenses
-- currently has (enabled or not, and under what policy) is unknown from this
-- repo — there is no prior migration to check it against. Changing RLS blind
-- risks locking out reads/writes on a live, shipped feature. Verify the
-- current policy in Supabase Studio (Authentication > Policies) before adding
-- any RLS statements for this table.

alter table public.split_expenses
  add column if not exists trip_id uuid references public.trips(id) on delete set null;

-- Category vocabulary matches trip_category_budgets exactly (stay/food/
-- activity/transit/shopping/insurance/misc/flights) rather than inventing a
-- second taxonomy — an expense's category and a trip's planned-budget category
-- are the same concept, and the Summary "planned vs. actual" chart will want
-- to compare them directly.
alter table public.split_expenses
  add column if not exists category text check (
    category in (
      'stay', 'food', 'activity', 'transit',
      'shopping', 'insurance', 'misc', 'flights'
    )
  );

alter table public.split_expenses
  add column if not exists expense_date timestamptz not null default now();

-- 'equal' | 'exact' | 'percentage' — the three common bill-split modes. Not
-- specified in the original ask beyond the 'equal' default; narrow this check
-- if the actual split UI ends up wanting a different vocabulary.
alter table public.split_expenses
  add column if not exists split_type text not null default 'equal' check (
    split_type in ('equal', 'exact', 'percentage')
  );

alter table public.split_expenses
  add column if not exists receipt_url text;

-- A settlement is a balancing payment between members (not a real purchase),
-- so it's excluded from spend totals like fetchSpendSummary — that filter
-- still needs to be added on the read side, this column just makes it possible.
alter table public.split_expenses
  add column if not exists is_settlement boolean not null default false;

alter table public.split_expenses
  add column if not exists updated_at timestamptz;

-- moddatetime is idempotent to (re-)enable; already on if the checklist/
-- category-budgets migrations ran first, no-ops otherwise.
create extension if not exists moddatetime schema extensions;

drop trigger if exists set_split_expenses_updated_at on public.split_expenses;
create trigger set_split_expenses_updated_at
  before update on public.split_expenses
  for each row execute function extensions.moddatetime(updated_at);

-- New access path: "all expenses for this trip" (the natural query once
-- trip_id exists) runs alongside the existing group_id-scoped queries.
create index if not exists split_expenses_trip_id_idx
  on public.split_expenses (trip_id);
