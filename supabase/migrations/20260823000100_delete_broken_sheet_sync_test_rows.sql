-- Two throwaway rows created while debugging the Sheets photo-sync feature
-- (docs/integrations/gem-sheet-sync.gs) before it uploaded to Supabase
-- Storage: one with photo_url literally set to the string "Nha hang.png"
-- (the pre-fix bug), one with a Google Drive share link (the
-- doesn't-reliably-load-as-an-image approach, superseded by the Storage
-- upload). Both are duplicates of the same real gem, re-created correctly
-- once the sheet row is re-synced with the fixed script.
delete from public.saved_gems
where id in (
  '9061e62e-82b1-4da7-91c7-029a1088b202',
  'c26fe1bc-4518-4b2d-8c14-8d3a867927fa'
);
