-- Lets the Google Sheets gem-sync script (anon key only, no user session —
-- see docs/integrations/gem-sheet-sync.gs) upload photos into the same
-- `gem-photos` bucket the app's own Drop-a-Gem flow uses, WITHOUT opening up
-- anon writes to the whole bucket. Scoped to the `sheet-sync/` path only —
-- same narrowing philosophy as the anon-callable upsert_gem_from_sheet RPC
-- (grant just the one capability the script needs, nothing broader).
--
-- Read is already public for this bucket (confirmed: existing gem photo_urls
-- resolve via the /object/public/ path, which bypasses RLS for public
-- buckets entirely) — this migration only adds INSERT.
create policy "anon can upload sheet-sync photos"
  on storage.objects
  for insert
  to anon
  with check (
    bucket_id = 'gem-photos'
    and (storage.foldername(name))[1] = 'sheet-sync'
  );
