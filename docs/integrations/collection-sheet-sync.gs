/**
 * Google Sheets -> Supabase (curated collections) auto-sync for Explorife.
 *
 * Structurally a straight mirror of tour-sheet-sync.gs — same one-way
 * (Sheet -> Supabase) direction, same installable onEdit trigger + manual
 * menu items, same anon-key-only auth against a security-definer RPC, same
 * per-row in-sheet Sync Status error reporting, same "resync = re-upsert",
 * not a diff-based incremental sync. See that file's own header for the
 * full rationale behind each of those choices — this one only calls out
 * where Collections genuinely differ and why (search "DIFFERS FROM TOUR
 * SYNC" below).
 *
 * Bind this to its own Collections tracking sheet (a separate spreadsheet
 * from the Gems/Tours ones — Apps Script projects are container-bound to
 * one spreadsheet).
 *
 * WHAT IT DOES
 * Every time you edit a row (via the sheet UI), this upserts that row into
 * `public.curated_collections` via the `upsert_curated_collection_from_sheet`
 * Postgres RPC (see
 * supabase/migrations/20260918000400_create_upsert_curated_collection_from_sheet_fn.sql).
 * This table backs Home's "EXPLORE IDEAS" rail (lib/screens/home/home_screen.dart,
 * via CuratedCollectionProvider) — every row here is one card in that rail.
 * The collection id Supabase returns is cached back into the Collection ID
 * column, so the NEXT edit of that row updates the same collection instead
 * of creating a new one.
 *
 * SHEET COLUMNS (row 1 = header, data starts row 2)
 *   A Title            (required, e.g. "Explore Hanoi")
 *   B Subtitle         (free text, one line, e.g. "Vietnam's capital —
 *                        Old Quarter, lakes & street food")
 *   C Is Destination   (checkbox — TRUE = this card links to a city
 *                        (Destination Detail); FALSE = this card links to a
 *                        Gem category (Listings, pre-filtered). Drives
 *                        which validation rule column D gets, below.)
 *   D Scope Value      (checked (destination): a city name, e.g. "Hanoi" —
 *                        resolved to real coordinates on tap, not validated
 *                        against a fixed list. Unchecked (category): one
 *                        of hiking, camping, viewpoint, food, temple, cave,
 *                        coastal, nature, heritage, landmark, or "all" —
 *                        anything else is rejected. Same taxonomy as the
 *                        Gems/Tours sheets' Category column.)
 *   E Rating           (numeric 0–5, optional — curator-assigned, NOT a
 *                        real review score (this app has no review
 *                        backend). Only meaningful for destination cards;
 *                        leave blank for category cards, same as the two
 *                        "Trending"/"Hidden" example cards do.)
 *   F Best Time to Visit  (free text, e.g. "Oct–Dec" — destination cards
 *                           only by convention, not enforced.)
 *   G Sort Order       (numeric — controls left-to-right order in the
 *                        rail. Lower sorts first. Blank defaults to 0.)
 *   H Photo URL        (a real public URL — combines with column I into
 *                        one final value, script-rewritten after each
 *                        sync, same convention as the Gems/Tours sheets.
 *                        Unlike those sheets, this card shows exactly ONE
 *                        photo, not a gallery — so this is a single value,
 *                        not a comma-separated list. If both H and I have
 *                        values, I (the Drive-resolved one) wins.)
 *   I Photo Filename   (one filename in your Photo Folder — resolved via
 *                        Drive, same mechanism as the Gems/Tours sheets.)
 *   J Collection ID    (script-managed — leave blank, it fills itself in)
 *   K Sync Status      (script-managed — shows "Synced <time>" or the error)
 *
 * DIFFERS FROM TOUR SYNC (and why)
 *   1. No Currency/Price — collections aren't bookable/priced, so that
 *      whole validation concept from the Tour sync simply doesn't apply.
 *   2. Rating validation is new — a 0–5 numeric range check, since this is
 *      the first sheet-synced content type with a curator-assigned rating
 *      at all (neither Gems nor Tours have one — see both those models'
 *      own doc comments for why).
 *   3. Sort Order is new — Gems/Tours don't have a rail-position concept;
 *      this rail's card order used to just be Dart array order before this
 *      table existed, so an explicit column replaces that.
 *   4. Photo is a SINGLE value, not a combined comma-separated list — this
 *      card has no photo gallery/carousel, only one cover image, so there's
 *      no list to build. Photo URL/Filename still combine the same way
 *      (Filename wins if both are set, since it's the freshly-resolved
 *      one), just producing one string instead of joining several.
 *
 * PHOTOS — same mechanism as the Gems/Tours sheets (see gem-sheet-sync.gs's
 * own header for the full explanation of why Drive share-links aren't used
 * directly): a Photo Filename is resolved from the Drive folder set via
 * Collection Sync -> "Set photo folder..." and re-hosted into this app's
 * `gem-photos` Supabase Storage bucket (same bucket as Gems/Tours, own
 * prefix: `collections-sheet-sync/` — see
 * supabase/migrations/20260918000500_allow_anon_collection_sheet_sync_photo_uploads.sql).
 *
 * ONE-TIME SETUP
 *   1. Open the Collections sheet -> Extensions -> Apps Script.
 *   2. Delete whatever's in Code.gs, paste this whole file in, save.
 *   3. Run the `setup` function once (select it in the toolbar dropdown,
 *      click Run). It'll ask you to authorize — approve it. This stores
 *      the Supabase credentials in THIS script's own Script Properties.
 *   4. Reload the spreadsheet tab. A "Collection Sync" menu appears next
 *      to Help. If you're using column I for photos: Collection Sync ->
 *      "Set photo folder..." and paste the Drive folder's URL. Skip this
 *      if you'll always paste ready-made URLs straight into column H.
 *   5. Triggers -> Add Trigger: choose function `onEditInstallable`, event
 *      source "From spreadsheet", event type "On edit". Save, authorize
 *      again if asked.
 *   6. For rows already in the sheet before this was set up, use
 *      Collection Sync -> "Sync all rows" once to backfill them.
 */

// ── one-time credential setup ──────────────────────────────────────────
function setup() {
  const props = PropertiesService.getScriptProperties();
  props.setProperties({
    SUPABASE_URL: 'https://yshgjzmyapdepkapodno.supabase.co',
    SUPABASE_ANON_KEY:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlzaGdqem15YXBkZXBrYXBvZG5vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1Nzc0NDksImV4cCI6MjA4NzE1MzQ0OX0.rxKTnUxKbFQvRlDZlKfv5BtblR6kOS-WyeWcn4ZvDwY',
  });
  try {
    SpreadsheetApp.getUi().alert('Collection Sync credentials saved. You can close this.');
  } catch (err) {
    Logger.log('Credentials saved (confirmation dialog unavailable in this context).');
  }
}

// ── column layout — edit these if you reorder the sheet ──────────────────
const COL = {
  TITLE: 1, SUBTITLE: 2, IS_DESTINATION: 3, SCOPE_VALUE: 4, RATING: 5,
  BEST_TIME_TO_VISIT: 6, SORT_ORDER: 7, PHOTO_URL: 8, PHOTO_FILENAME: 9,
  COLLECTION_ID: 10, STATUS: 11,
};
const HEADER_ROW = 1;
// Must stay in sync with Gem.categories (lib/models/gem.dart),
// gem-sheet-sync.gs's / tour-sheet-sync.gs's own VALID_CATEGORIES, and
// upsert_curated_collection_from_sheet's hardcoded check.
const VALID_CATEGORIES = [
  'hiking', 'camping', 'viewpoint', 'food', 'temple', 'cave', 'coastal', 'nature',
  'heritage', 'landmark',
];

// ── menu (manual sync entry points) ───────────────────────────────────────
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Collection Sync')
    .addItem('Sync all rows', 'syncAllRows')
    .addItem('Sync current row', 'syncActiveRow')
    .addSeparator()
    .addItem('Set photo folder...', 'setPhotoFolder')
    .addToUi();
}

function setPhotoFolder() {
  const ui = SpreadsheetApp.getUi();
  const res = ui.prompt(
    'Photo folder',
    'Paste the Google Drive folder URL (or just its ID) that your collection cover photos live in:',
    ui.ButtonSet.OK_CANCEL
  );
  if (res.getSelectedButton() !== ui.Button.OK) return;
  const input = res.getResponseText().trim();
  const match = input.match(/[-\w]{25,}/);
  const folderId = match ? match[0] : input;
  try {
    const folder = DriveApp.getFolderById(folderId);
    PropertiesService.getScriptProperties().setProperty('PHOTO_FOLDER_ID', folderId);
    ui.alert('Photo folder set to "' + folder.getName() + '".');
  } catch (err) {
    ui.alert('Could not open that folder — check the URL and that you have access to it.');
  }
}

// ── installable "On edit" trigger target ──────────────────────────────────
// Same reason as gem-sheet-sync.gs/tour-sheet-sync.gs: a SIMPLE onEdit(e)
// can't call UrlFetchApp, so this must be added by hand once as an
// installable trigger.
function onEditInstallable(e) {
  const row = e.range.getRow();
  if (row <= HEADER_ROW) return;
  if (e.range.getColumn() > COL.PHOTO_FILENAME) return; // script-managed column edited — not a real content change
  syncRow_(e.range.getSheet(), row);
}

function syncActiveRow() {
  const sheet = SpreadsheetApp.getActiveSheet();
  const row = sheet.getActiveCell().getRow();
  if (row <= HEADER_ROW) {
    SpreadsheetApp.getUi().alert('Select a data row first (not the header).');
    return;
  }
  syncRow_(sheet, row);
}

function syncAllRows() {
  const sheet = SpreadsheetApp.getActiveSheet();
  const lastRow = sheet.getLastRow();
  for (let row = HEADER_ROW + 1; row <= lastRow; row++) {
    syncRow_(sheet, row);
  }
  SpreadsheetApp.getUi().alert('Synced rows 2-' + lastRow + '. Check the Sync Status column for any errors.');
}

// ── core sync for one row ─────────────────────────────────────────────────
function syncRow_(sheet, row) {
  const get = (col) => sheet.getRange(row, col).getValue();
  const title = String(get(COL.TITLE) || '').trim();
  if (!title) return; // blank row someone clicked into — same silent skip as the Gem/Tour sync

  const isDestination = get(COL.IS_DESTINATION) === true;
  const scopeValue = String(get(COL.SCOPE_VALUE) || '').trim();
  if (!scopeValue) {
    setStatus_(sheet, row, 'Error: Scope Value is required');
    return;
  }
  const scopeValueLower = scopeValue.toLowerCase();
  if (!isDestination && scopeValueLower !== 'all' && VALID_CATEGORIES.indexOf(scopeValueLower) === -1) {
    setStatus_(sheet, row, 'Error: for a category card, Scope Value must be one of ' + VALID_CATEGORIES.join(', ') + ', or "all"');
    return;
  }

  const ratingRaw = get(COL.RATING);
  let rating = null;
  if (ratingRaw !== '' && ratingRaw !== null) {
    rating = Number(ratingRaw);
    if (isNaN(rating) || rating < 0 || rating > 5) {
      setStatus_(sheet, row, 'Error: Rating must be a number between 0 and 5');
      return;
    }
  }

  const sortOrderRaw = get(COL.SORT_ORDER);
  const sortOrder = sortOrderRaw === '' || sortOrderRaw === null ? 0 : Number(sortOrderRaw);
  if (isNaN(sortOrder)) {
    setStatus_(sheet, row, 'Error: Sort Order must be a number');
    return;
  }

  // Single-value combine (not a comma-joined list — this card has only one
  // cover photo, unlike the Gems/Tours galleries): the Drive-resolved
  // filename wins over a plain URL if both are present, since it's the
  // freshly-resolved one.
  let coverPhotoUrl = String(get(COL.PHOTO_URL) || '').trim();
  const photoFilename = String(get(COL.PHOTO_FILENAME) || '').trim();
  if (photoFilename) {
    try {
      coverPhotoUrl = resolvePhotoUrl_(photoFilename);
    } catch (err) {
      setStatus_(sheet, row, 'Error: ' + err.message);
      return;
    }
    sheet.getRange(row, COL.PHOTO_URL).setValue(coverPhotoUrl);
  }

  const payload = {
    p_collection_id: get(COL.COLLECTION_ID) || null,
    p_title: title,
    p_subtitle: String(get(COL.SUBTITLE) || '').trim() || null,
    p_cover_image_url: coverPhotoUrl || null,
    p_is_destination: isDestination,
    p_scope_value: isDestination ? scopeValue : scopeValueLower,
    p_rating: rating,
    p_best_time_to_visit: String(get(COL.BEST_TIME_TO_VISIT) || '').trim() || null,
    p_sort_order: sortOrder,
  };

  try {
    const collectionId = callUpsertRpc_(payload);
    sheet.getRange(row, COL.COLLECTION_ID).setValue(collectionId);
    setStatus_(sheet, row, 'Synced ' + new Date().toLocaleString());
  } catch (err) {
    setStatus_(sheet, row, 'Error: ' + err.message);
  }
}

function setStatus_(sheet, row, text) {
  sheet.getRange(row, COL.STATUS).setValue(text);
}

// ── Drive photo lookup + Supabase Storage upload ──────────────────────────
// Identical to gem-sheet-sync.gs's/tour-sheet-sync.gs's resolvePhotoUrl_,
// except the uploaded path uses the `collections-sheet-sync/` prefix (see
// supabase/migrations/20260918000500_allow_anon_collection_sheet_sync_photo_uploads.sql)
// instead of `sheet-sync/`/`tours-sheet-sync/`, so uploads across all three
// content types never collide even though they share the `gem-photos` bucket.
function resolvePhotoUrl_(filename) {
  const folderId = PropertiesService.getScriptProperties().getProperty('PHOTO_FOLDER_ID');
  if (!folderId) {
    throw new Error('No photo folder set — run Collection Sync -> "Set photo folder..." first');
  }
  const files = DriveApp.getFolderById(folderId).getFilesByName(filename);
  if (!files.hasNext()) {
    throw new Error('No file named "' + filename + '" in the photo folder');
  }
  const file = files.next();
  const blob = file.getBlob();
  const safeName = filename.replace(/[^\w.-]/g, '-');
  const path = 'collections-sheet-sync/' + file.getId() + '-' + safeName;
  return uploadToSupabaseStorage_(path, blob);
}

function uploadToSupabaseStorage_(path, blob) {
  const props = PropertiesService.getScriptProperties();
  const url = props.getProperty('SUPABASE_URL') + '/storage/v1/object/gem-photos/' + path;
  const anonKey = props.getProperty('SUPABASE_ANON_KEY');
  const res = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: blob.getContentType() || 'application/octet-stream',
    headers: {
      apikey: anonKey,
      Authorization: 'Bearer ' + anonKey,
      'x-upsert': 'true',
    },
    payload: blob.getBytes(),
    muteHttpExceptions: true,
  });
  if (res.getResponseCode() >= 300) {
    let message = res.getContentText();
    try { message = JSON.parse(message).message || message; } catch (e) {}
    throw new Error('Photo upload failed: ' + message);
  }
  return props.getProperty('SUPABASE_URL') + '/storage/v1/object/public/gem-photos/' + path;
}

// ── Supabase RPC call ──────────────────────────────────────────────────────
function callUpsertRpc_(payload) {
  const props = PropertiesService.getScriptProperties();
  const url = props.getProperty('SUPABASE_URL') + '/rest/v1/rpc/upsert_curated_collection_from_sheet';
  const anonKey = props.getProperty('SUPABASE_ANON_KEY');
  const res = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: { apikey: anonKey, Authorization: 'Bearer ' + anonKey },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  });
  const body = res.getContentText();
  if (res.getResponseCode() >= 300) {
    let message = body;
    try { message = JSON.parse(body).message || body; } catch (e) {}
    throw new Error(message);
  }
  // PostgREST returns the bare uuid string (quoted) for a scalar-returning RPC.
  return JSON.parse(body);
}
