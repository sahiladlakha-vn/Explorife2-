-- Backfills group_size_label/excludes on the 2 verification seed tours
-- (20260901000100_seed_test_tours.sql) added by the prior migration in this
-- pair — an UPDATE rather than editing that already-applied insert, matched
-- by name since the rows' ids are server-generated. Same "draft content,
-- not production-ready" caveat as the original seed.
update public.tours
set group_size_label = 'Up to 12 people',
    excludes = array['Alcoholic drinks', 'Personal expenses', 'Gratuities']
where name = 'Ha Long Bay Day Cruise';

update public.tours
set group_size_label = 'Up to 8 people',
    excludes = array['Alcoholic drinks', 'Additional food purchases']
where name = 'Hanoi Street Food Walking Tour';
