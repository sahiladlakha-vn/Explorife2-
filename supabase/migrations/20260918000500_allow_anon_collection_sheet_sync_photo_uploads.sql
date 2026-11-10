-- Same narrowing as the Gem/Tour sheet syncs, extended to curated
-- collections: lets collection-sheet-sync.gs (anon key only, no user
-- session) upload photos into the SAME `gem-photos` bucket, scoped to its
-- own `collections-sheet-sync/` path prefix.
create policy "anon can upload collections-sheet-sync photos"
  on storage.objects
  for insert
  to anon
  with check (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'collections-sheet-sync'
  );

create policy "anon can update collections-sheet-sync photos"
  on storage.objects
  for update
  to anon
  using (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'collections-sheet-sync'
  )
  with check (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'collections-sheet-sync'
  );
