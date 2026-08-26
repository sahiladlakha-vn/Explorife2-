-- Second cleanup pass on saved_gems (after 20260815000300 removed the
-- app-seeded demo content) — this one removes leftover throwaway test
-- entries created while testing Drop-a-Gem: gibberish names with no photo
-- ("ydyud", "vvv", "btest", "pp", "aaa", "yh", "hh", "jjjjjjkkk"), a
-- photo-less low-effort duplicate ("night view"), and redundant duplicate
-- copies of gems that ARE kept (one copy each of "evening view", "saigon",
-- "Banh mi Madam" survives; the extra 2/2/6 copies here don't).
--
-- Confirmed against the live table (read-only via REST API) before writing
-- this. Targeted by exact id, not a name/user match, so nothing else is at
-- risk. What's left afterward: Bánh căn Cô Hiếu, Cafe, Café, Thi cafe,
-- Rooftop cafe, one "saigon night view", one "evening view", one "saigon",
-- one "Banh mi Madam" — all real addresses and/or real uploaded photos.
delete from public.saved_gems
where id in (
  '74dbd23c-6f64-4521-8cde-5161e999c320', -- ydyud
  '6bc2154b-f7c6-443e-bfb4-23f13468b90a', -- vvv
  'c5659248-448d-4415-922f-bf7f97ec80bf', -- vvv (dup)
  'fe38622d-c885-4473-9eed-76fc622c2f8b', -- ydyud (dup)
  '4bca93d1-2204-437c-8e32-9574c7f4818b', -- Banh mi Madam (dup)
  'be6b4584-4885-4f49-9156-c84f6d193d72', -- Banh mi Madam (dup)
  '54ca65ce-1f5e-4e00-bfa4-41e470bfcdc1', -- Banh mi Madam (dup)
  'a038ac18-b425-44da-81a7-fc97f33c037a', -- Banh mi Madam (dup)
  'c114f13e-fc18-47df-9357-77b650d81c71', -- Banh mi Madam (dup)
  'fd355104-7ab4-4acf-b380-4081127a1597', -- Banh mi Madam (dup)
  '0d2723ce-df1f-4f55-bc0f-bab07d80112f', -- btest
  '9e32a979-c346-40b2-a9c6-1a77c2bf7d20', -- pp
  'e7690200-ff7c-4d5d-adae-3ffde66887d3', -- pp (dup)
  '26c038db-45f6-44a1-af9b-d8f19f4baec4', -- aaa
  'b0724409-6de2-43fb-8505-6bf578af28aa', -- night view (photo-less)
  '16c9c44b-431b-4edb-b7ae-cee7226ba5b0', -- btest (dup)
  '3e9b4f7f-2bbc-40c4-940d-7bcc91e1a82e', -- saigon (dup)
  '353b64e5-75fa-4132-b4b1-7407cb6a2f74', -- evening view (dup)
  'a65613fa-cf90-4214-808f-06316744f0b8', -- evening view (dup)
  'ec37c9b4-c2e3-4915-a067-8d75db7c090a', -- Banh mi Madam (dup)
  '657d916a-6059-4760-82e8-00df8767a665', -- saigon (dup)
  '90d3a37b-505d-4d38-95e5-5dec826a55d9', -- yh
  '8017f3f9-6daf-4a9e-b46f-f06c791d1d40', -- hh
  '56039317-32ea-420d-9b7a-0262437ad606'  -- jjjjjjkkk
);
