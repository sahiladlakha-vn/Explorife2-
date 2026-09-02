-- Same narrowing as 20260823000000/20260824000200 for the Gem sheet sync,
-- extended to Tours: lets tour-sheet-sync.gs (anon key only, no user
-- session) upload photos into the SAME `gem-photos` bucket the app already
-- uses, scoped to its own `tours-sheet-sync/` path prefix rather than
-- opening up the whole bucket or creating a second bucket for what's really
-- the same capability (upload a photo, get back a stable public URL).
--
-- Two policies, same as the Gem sync needed: INSERT for a brand new photo
-- path, UPDATE for re-syncing (x-upsert: true) an already-uploaded one —
-- Storage's overwrite path requires UPDATE on storage.objects, not just
-- INSERT, confirmed the hard way during the Gem sync's own setup.
create policy "anon can upload tours-sheet-sync photos"
  on storage.objects
  for insert
  to anon
  with check (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'tours-sheet-sync'
  );

create policy "anon can update tours-sheet-sync photos"
  on storage.objects
  for update
  to anon
  using (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'tours-sheet-sync'
  )
  with check (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'tours-sheet-sync'
  );
