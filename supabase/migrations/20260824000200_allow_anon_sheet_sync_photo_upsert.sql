-- Fixes "new row violates row-level security policy" on re-syncing a photo
-- that was already uploaded once. Supabase Storage's overwrite path
-- (`x-upsert: true`, used by uploadToSupabaseStorage_ in
-- docs/integrations/gem-sheet-sync.gs so re-syncing the same Drive file
-- doesn't error on a duplicate key) requires UPDATE on storage.objects for
-- an existing path, not just INSERT for a new one — confirmed directly: the
-- FIRST upload to a path succeeds under the INSERT-only policy from
-- 20260823000000, a SECOND upload to that same path 403s.
--
-- Scoped identically to the existing insert policy — anon can only
-- overwrite objects already confined to `sheet-sync/`, nothing broader.
create policy "anon can update sheet-sync photos"
  on storage.objects
  for update
  to anon
  using (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'sheet-sync'
  )
  with check (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'sheet-sync'
  );
