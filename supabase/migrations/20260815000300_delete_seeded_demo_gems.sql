-- Removes the placeholder demo gems that were seeded into saved_gems before
-- real usage began — confirmed via the live table (fetched read-only via the
-- REST API) as: owned by the placeholder account
-- aaaaaaaa-0001-0001-0001-000000000001, dated April 2024 (predates any real
-- account activity, which starts ~May 2026), using stock Unsplash photos —
-- My Son at Midnight, Hang En Cave Campsite, Mu Cang Chai at Harvest, Draa
-- Valley at Dawn, Abandoned Douro Train Line, Sagano Bamboo at 5am. Each was
-- duplicated (2 rows apiece), and "Sagano Bamboo at 5am" was additionally
-- re-saved 3 more times under a real test account
-- (82e0d0ff-1653-44e7-9565-3939f7cef8ed) while testing — those copies are
-- included since they trace back to the same seeded gem, not a real spot.
--
-- Targeted by exact id rather than a name/user match, so this can't
-- accidentally catch a real gem that happens to share a name or owner.
-- Safe to run: gem_saves cascades on delete, trip_stops.gem_id sets null.
delete from public.saved_gems
where id in (
  '31750214-2486-4ed9-9729-9b4d7e7dcee9', -- My Son at Midnight
  '25861078-d5f4-4e4a-add3-78efcb5fb30d', -- My Son at Midnight (dup)
  'e1a977bc-6706-49e8-ba9a-0d41cc637d54', -- Hang En Cave Campsite
  '7154ec3e-762d-472a-a71e-38283ffcd38b', -- Hang En Cave Campsite (dup)
  '2fbe44f4-763d-4f11-a4f2-a06b007333e9', -- Mu Cang Chai at Harvest
  'd5694df5-a287-478e-a908-4cbf85fbaa49', -- Mu Cang Chai at Harvest (dup)
  '57e8f026-99f1-420c-b6a8-da9010f8a164', -- Draa Valley at Dawn
  '7b003721-77ed-4873-b7be-b1394c4752e9', -- Draa Valley at Dawn (dup)
  'a54a0849-6cff-4b32-ad17-0d83c606b581', -- Abandoned Douro Train Line
  'b5a05999-badf-4a98-b9c7-87f6e8890e9e', -- Abandoned Douro Train Line (dup)
  '2da1fa66-b607-48ee-91b8-86f51adcfeb3', -- Sagano Bamboo at 5am
  '9c49b627-aeca-44ae-bc62-dc1c2bc43350', -- Sagano Bamboo at 5am (dup)
  '574100ad-4c76-44da-b112-d3c5f47e92c1', -- Sagano Bamboo at 5am (re-saved copy)
  '7604738f-e493-4060-9d91-737a5edfd28d', -- Sagano Bamboo at 5am (re-saved copy)
  '444e4392-3e9e-466d-b3c2-f08aa1708547'  -- Sagano Bamboo at 5am (re-saved copy)
);
