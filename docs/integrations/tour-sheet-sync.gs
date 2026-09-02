/**
 * Google Sheets -> Supabase (tours) auto-sync for Explorife.
 *
 * Structurally a straight mirror of gem-sheet-sync.gs — same one-way
 * (Sheet -> Supabase) direction, same installable onEdit trigger + manual
 * menu items, same anon-key-only auth against a security-definer RPC, same
 * per-row in-sheet Sync Status error reporting, same "resync = re-upsert",
 * not a diff-based incremental sync. See that file's own header for the
 * full rationale behind each of those choices — this one only calls out
 * where Tours genuinely differ and why (search "DIFFERS FROM GEM SYNC"
 * below for all of them).
 *
 * Bind this to its own Tours tracking sheet (a separate spreadsheet from
 * the Gems one — Apps Script projects are container-bound to one
 * spreadsheet, same as gem-sheet-sync.gs is bound to the Gems sheet).
 *
 * WHAT IT DOES
 * Every time you edit a row (via the sheet UI), this upserts that row into
 * `public.tours` via the `upsert_tour_from_sheet` Postgres RPC (see
 * supabase/migrations/20260902000000_create_upsert_tour_from_sheet_fn.sql).
 * The tour id Supabase returns is cached back into the Tour ID column, so
 * the NEXT edit of that row updates the same tour instead of creating a
 * new one.
 *
 * SHEET COLUMNS (row 1 = header, data starts row 2)
 *   A Name                 (required)
 *   B Category             (optional — one of: hiking, camping, viewpoint,
 *                            food, temple, cave, coastal, nature, heritage,
 *                            landmark, or blank for uncategorized; anything
 *                            else is rejected. Same taxonomy as the Gems
 *                            sheet's Category column — Trails reuse it
 *                            rather than a second list, confirmed with
 *                            product; see lib/models/tour.dart.)
 *   C Price From           (numeric, e.g. 1200000. Non-negative. Blank = 0.)
 *   D Currency             (one of VND, USD — blank defaults to VND)
 *   E Duration Label       (free text, e.g. "Full day (10 hours)")
 *   F Cancellation Policy  (free text, e.g. "Free cancellation up to 24
 *                            hours before departure")
 *   G Pickup Included      (checkbox)
 *   H Pickup Detail        (free text, e.g. "Hotel pickup in Old Quarter")
 *   I Guide Languages      (comma-separated, e.g. "English, Vietnamese")
 *   J Highlights           (comma-separated, e.g. "UNESCO site, Sunset view")
 *   K Itinerary            (ORDER MATTERS — one step per line within the
 *                            cell, "Title | Description" per line;
 *                            description is optional (a line with no "|"
 *                            is title-only). Example, three steps in one
 *                            cell:
 *                              Pickup | From your hotel
 *                              Board the cruise
 *                              Kayaking | Free kayaking around the karsts
 *                            See "DIFFERS FROM GEM SYNC" below for why
 *                            this isn't comma-separated like the other
 *                            list columns.)
 *   L Includes             (comma-separated, e.g. "Lunch, Kayaking, Guide")
 *   M Full Description     (free text)
 *   N Is Curated           (checkbox — the ONLY thing that drives the "Top
 *                            pick" badge; see Tour.isCurated's own doc
 *                            comment. Never set this from a formula or
 *                            derived value — it's a deliberate editorial
 *                            call, same rule as the Trail spec requires.)
 *   O Photo URL            (one or more real public URLs, comma-separated —
 *                            same convention as the Gems sheet's Photo URL
 *                            column: combines with column P into one
 *                            final list, script-rewritten after each sync.)
 *   P Photo Filename       (one or more filenames in your Photo Folder,
 *                            comma-separated — same Drive-upload mechanism
 *                            as the Gems sheet's Photo Filename column.)
 *   Q Tour ID              (script-managed — leave blank, it fills itself in)
 *   R Sync Status          (script-managed — shows "Synced <time>" or the error)
 *
 * DIFFERS FROM GEM SYNC (and why)
 *   1. Category is validated the SAME way (optional, but rejected if
 *      present and not in the list) — the Trail spec asked to "confirm
 *      whether Trails reuse the taxonomy," and whether to require it. The
 *      real Gem sync does NOT require category (only Name is required —
 *      a missing category silently syncs as uncategorized); Tour.category
 *      is also nullable in the app model (lib/models/tour.dart). Matching
 *      that existing behavior — rather than introducing a stricter
 *      "category is required" rule that exists nowhere else in this
 *      app — is the deliberate choice here, not an oversight.
 *   2. Price/Currency validation is new — the Gem sync has no price
 *      concept at all, so there was nothing to mirror. Kept as simple a
 *      check as the category one: a fixed allow-list for currency, a
 *      non-negative check for price, both enforced client-side (fast
 *      fail) AND server-side in the RPC (the actual enforcement point,
 *      same philosophy as the category check).
 *   3. No geocoding step — Tours have no Location/Lat/Lng columns; there's
 *      nothing analogous to Address -> coordinates for a priced
 *      experience in this app yet, so that whole step (and its Mapbox
 *      dependency) is simply absent, not replaced with anything.
 *   4. Itinerary's "Title | Description" per-line format is new — the
 *      Gems sheet's only real array-column precedent is comma-separated
 *      (Photo URL/Filename); nothing in the actual Gem sync handles an
 *      ORDERED list of {title, description} pairs (goodToKnow isn't
 *      synced from the Gems sheet at all — it's not one of that sheet's
 *      columns). Comma-separated can't preserve title+description
 *      structure without a delimiter collision risk, and a linked
 *      sub-sheet keyed by id is a bigger structural deviation with no
 *      precedent in the real script either. One-line-per-step in a
 *      single cell was chosen as the smallest deviation from the
 *      established convention that still preserves order and structure.
 *      Guide Languages/Highlights/Includes stay comma-separated,
 *      matching the real precedent exactly.
 *
 * PHOTOS — identical mechanism to the Gems sheet (see that file's own
 * header for the full explanation of why Drive share-links aren't used
 * directly): Photo URL + Photo Filename combine into one list, filenames
 * are resolved from the Drive folder set via Tour Sync -> "Set photo
 * folder..." and re-hosted into this app's `gem-photos` Supabase Storage
 * bucket (same bucket as Gems, different prefix: `tours-sheet-sync/` — see
 * supabase/migrations/20260902000100_allow_anon_tour_sheet_sync_photo_uploads.sql).
 *
 * ONE-TIME SETUP
 *   1. Open the Tours sheet -> Extensions -> Apps Script.
 *   2. Delete whatever's in Code.gs, paste this whole file in, save.
 *   3. Run the `setup` function once (select it in the toolbar dropdown,
 *      click Run). It'll ask you to authorize — approve it. This stores
 *      the Supabase credentials in THIS script's own Script Properties
 *      (Project Settings) — a separate copy from the Gems script's, since
 *      each Apps Script project (one per bound spreadsheet) has isolated
 *      properties. Same anon-tier, non-secret values either way.
 *   4. Reload the spreadsheet tab. A "Tour Sync" menu appears next to
 *      Help. If you're using column P for photos: Tour Sync -> "Set
 *      photo folder..." and paste the Drive folder's URL. Skip this if
 *      you'll always paste ready-made URLs straight into column O instead.
 *   5. Triggers -> Add Trigger: choose function `onEditInstallable`, event
 *      source "From spreadsheet", event type "On edit". Save, authorize
 *      again if asked.
 *   6. For rows already in the sheet before this was set up, use
 *      Tour Sync -> "Sync all rows" once to backfill them.
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
    SpreadsheetApp.getUi().alert('Tour Sync credentials saved. You can close this.');
  } catch (err) {
    Logger.log('Credentials saved (confirmation dialog unavailable in this context).');
  }
}

// ── column layout — edit these if you reorder the sheet ──────────────────
const COL = {
  NAME: 1, CATEGORY: 2, PRICE_FROM: 3, CURRENCY: 4, DURATION_LABEL: 5,
  CANCELLATION_POLICY: 6, PICKUP_INCLUDED: 7, PICKUP_DETAIL: 8,
  GUIDE_LANGUAGES: 9, HIGHLIGHTS: 10, ITINERARY: 11, INCLUDES: 12,
  FULL_DESCRIPTION: 13, IS_CURATED: 14, PHOTO_URL: 15, PHOTO_FILENAME: 16,
  TOUR_ID: 17, STATUS: 18,
};
const HEADER_ROW = 1;
// Must stay in sync with Gem.categories (lib/models/gem.dart),
// gem-sheet-sync.gs's own VALID_CATEGORIES, and
// upsert_tour_from_sheet's hardcoded check — all four move together.
const VALID_CATEGORIES = [
  'hiking', 'camping', 'viewpoint', 'food', 'temple', 'cave', 'coastal', 'nature',
  'heritage', 'landmark',
];
// Must stay in sync with upsert_tour_from_sheet's own currency check.
const VALID_CURRENCIES = ['VND', 'USD'];

// ── menu (manual sync entry points) ───────────────────────────────────────
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Tour Sync')
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
    'Paste the Google Drive folder URL (or just its ID) that your tour photos live in:',
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
// Same reason as gem-sheet-sync.gs: a SIMPLE onEdit(e) can't call
// UrlFetchApp, so this must be added by hand once as an installable trigger.
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
  const name = String(get(COL.NAME) || '').trim();
  if (!name) return; // blank row someone clicked into — same silent skip as the Gem sync

  const category = String(get(COL.CATEGORY) || '').trim().toLowerCase();
  if (category && VALID_CATEGORIES.indexOf(category) === -1) {
    setStatus_(sheet, row, 'Error: category must be one of ' + VALID_CATEGORIES.join(', '));
    return;
  }

  const priceRaw = get(COL.PRICE_FROM);
  const priceFrom = priceRaw === '' || priceRaw === null ? 0 : Number(priceRaw);
  if (isNaN(priceFrom) || priceFrom < 0) {
    setStatus_(sheet, row, 'Error: Price From must be a non-negative number');
    return;
  }

  const currency = String(get(COL.CURRENCY) || '').trim().toUpperCase();
  if (currency && VALID_CURRENCIES.indexOf(currency) === -1) {
    setStatus_(sheet, row, 'Error: Currency must be one of ' + VALID_CURRENCIES.join(', '));
    return;
  }

  // Same dual-column combine as the Gem sync's photos.
  const photoUrls = splitList_(get(COL.PHOTO_URL));
  const photoFilenames = splitList_(get(COL.PHOTO_FILENAME));
  const allPhotoUrls = photoUrls.slice();
  for (const filename of photoFilenames) {
    try {
      allPhotoUrls.push(resolvePhotoUrl_(filename));
    } catch (err) {
      setStatus_(sheet, row, 'Error: ' + err.message);
      return;
    }
  }
  if (allPhotoUrls.length) {
    sheet.getRange(row, COL.PHOTO_URL).setValue(allPhotoUrls.join(', '));
  }

  const payload = {
    p_tour_id: get(COL.TOUR_ID) || null,
    p_name: name,
    p_category: category || null,
    p_price_from: priceFrom,
    p_currency: currency || null,
    p_duration_label: String(get(COL.DURATION_LABEL) || '').trim() || null,
    p_cancellation_policy: String(get(COL.CANCELLATION_POLICY) || '').trim() || null,
    p_pickup_included: get(COL.PICKUP_INCLUDED) === true,
    p_pickup_detail: String(get(COL.PICKUP_DETAIL) || '').trim() || null,
    p_guide_languages: splitList_(get(COL.GUIDE_LANGUAGES)),
    p_includes: splitList_(get(COL.INCLUDES)),
    p_itinerary: parseItinerary_(get(COL.ITINERARY)),
    p_highlights: splitList_(get(COL.HIGHLIGHTS)),
    p_full_description: String(get(COL.FULL_DESCRIPTION) || '').trim() || null,
    p_is_curated: get(COL.IS_CURATED) === true,
    p_photos: allPhotoUrls,
  };

  try {
    const tourId = callUpsertRpc_(payload);
    sheet.getRange(row, COL.TOUR_ID).setValue(tourId);
    setStatus_(sheet, row, 'Synced ' + new Date().toLocaleString());
  } catch (err) {
    setStatus_(sheet, row, 'Error: ' + err.message);
  }
}

function setStatus_(sheet, row, text) {
  sheet.getRange(row, COL.STATUS).setValue(text);
}

// Splits a cell's comma-separated value into trimmed, non-empty entries —
// identical to gem-sheet-sync.gs's splitList_, used here for Guide
// Languages/Highlights/Includes/Photo URL/Photo Filename.
function splitList_(cellValue) {
  return String(cellValue || '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

// Parses the Itinerary cell into an ordered array of {title, description}
// objects — one step per line, "Title | Description" (description
// optional). See the "DIFFERS FROM GEM SYNC" note at the top of this file
// for why this isn't comma-separated like the other list columns.
function parseItinerary_(cellValue) {
  const lines = String(cellValue || '')
    .split('\n')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  return lines.map((line) => {
    const idx = line.indexOf('|');
    if (idx === -1) return { title: line };
    const title = line.slice(0, idx).trim();
    const description = line.slice(idx + 1).trim();
    return description ? { title: title, description: description } : { title: title };
  });
}

// ── Drive photo lookup + Supabase Storage upload ──────────────────────────
// Identical to gem-sheet-sync.gs's resolvePhotoUrl_, except the uploaded
// path uses the `tours-sheet-sync/` prefix (see
// supabase/migrations/20260902000100_allow_anon_tour_sheet_sync_photo_uploads.sql)
// instead of `sheet-sync/`, so Tour and Gem photo uploads never collide
// even though they share the same `gem-photos` bucket.
function resolvePhotoUrl_(filename) {
  const folderId = PropertiesService.getScriptProperties().getProperty('PHOTO_FOLDER_ID');
  if (!folderId) {
    throw new Error('No photo folder set — run Tour Sync -> "Set photo folder..." first');
  }
  const files = DriveApp.getFolderById(folderId).getFilesByName(filename);
  if (!files.hasNext()) {
    throw new Error('No file named "' + filename + '" in the photo folder');
  }
  const file = files.next();
  const blob = file.getBlob();
  const safeName = filename.replace(/[^\w.-]/g, '-');
  const path = 'tours-sheet-sync/' + file.getId() + '-' + safeName;
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
  const url = props.getProperty('SUPABASE_URL') + '/rest/v1/rpc/upsert_tour_from_sheet';
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
