-- Real trip cover photos (upload, not just the map-thumbnail/picsum fallback
-- Trip._heroImageUrl already used). Nullable — every trip created before this
-- field existed, and any trip where the user skips it, has none and keeps
-- falling back the same way it always did.
alter table public.trips
  add column if not exists cover_image_url text;

-- Storage bucket for uploaded cover photos, mirroring the existing
-- 'gem-photos' bucket (lib/repositories/gem_repository.dart) — public read
-- (the app calls getPublicUrl with no signed-URL step), user-scoped upload
-- path ('<user_id>/<filename>') enforced by the insert/update/delete
-- policies below via storage.foldername.
insert into storage.buckets (id, name, public)
values ('trip-covers', 'trip-covers', true)
on conflict (id) do nothing;

create policy "trip covers public read"
on storage.objects for select
using (bucket_id = 'trip-covers');

create policy "trip covers owner insert"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'trip-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "trip covers owner update"
on storage.objects for update
to authenticated
using (
  bucket_id = 'trip-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "trip covers owner delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'trip-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);
