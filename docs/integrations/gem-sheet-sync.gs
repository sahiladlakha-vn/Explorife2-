/**
 * Google Sheets -> Supabase (saved_gems) auto-sync for Explorife.
 *
 * Persisted here so it survives outside chat history (a prior attempt at
 * this was only ever pasted inline and never saved). Bind this to the gems
 * tracking sheet: https://docs.google.com/spreadsheets/d/1NMbA92zRJ134zaGCmzSJNT2Pyh7UlYP0lRtNhhbXIFk
 *
 * WHAT IT DOES
 * Every time you edit a row (via the sheet UI), this geocodes the Location
 * column through Mapbox (only if Lat/Lng are still empty — it won't
 * re-geocode a row you've already resolved), then upserts that row into
 * `saved_gems` via the `upsert_gem_from_sheet` Postgres RPC (already
 * deployed — see supabase/migrations/20260816000000_create_upsert_gem_from_sheet_fn.sql).
 * The gem id Supabase returns is cached back into the Gem ID column, so the
 * NEXT edit of that row updates the same gem instead of creating a new one.
 *
 * SHEET COLUMNS (row 1 = header, data starts row 2)
 *   A Gem Name          (required)
 *   B Location          (freeform, e.g. "Hanoi, Vietnam" or a street address)
 *   C Category          (one of: hiking, camping, viewpoint, food, temple,
 *                         cave, coastal, nature, heritage, landmark —
 *                         anything else is rejected)
 *   D Tagline
 *   E Description
 *   F Difficulty
 *   G Best Time to Visit
 *   H Photo URL         (one or more real public URLs, comma-separated for
 *                         multiple photos — the script fills in / rewrites
 *                         this with whatever it resolves, combining this
 *                         column with column I into one final list)
 *   I Photo Filename    (one or more filenames in your Photo Folder — see
 *                         setup step 4 — comma-separated for multiple, e.g.
 *                         "banh-can-1.jpg, banh-can-2.jpg". This is how
 *                         local photos become public URLs: put them in the
 *                         folder, list their names here.)
 *   J Lat               (script-managed — leave blank, it fills itself in)
 *   K Lng               (script-managed)
 *   L Gem ID            (script-managed — do not edit)
 *   M Sync Status       (script-managed — shows "Synced <time>" or the error)
 *
 * PHOTOS (any number per gem — the first ends up as the app's "cover" photo,
 * the rest fill the detail screen's photo gallery): put your photo files in
 * one Google Drive folder (any name), then list their filenames in column I
 * (comma-separated for more than one), or skip that and list real hosted
 * URLs straight in column H yourself (comma-separated too) if you already
 * have some (e.g. from Supabase Storage, Unsplash, or anywhere else) — the
 * two columns combine into one list, URLs first then resolved filenames.
 * The script reads each Drive file and uploads it into the app's own
 * `gem-photos` Supabase Storage bucket (under a `sheet-sync/` prefix), then
 * uses THAT public URL — a plain Drive "share link" was tried first but
 * doesn't reliably load as an embedded image outside a logged-in browser
 * tab, so this re-hosts the bytes instead of just sharing the Drive file.
 *
 * ONE-TIME SETUP
 *   1. Open the sheet -> Extensions -> Apps Script.
 *   2. Delete whatever's in Code.gs, paste this whole file in, save.
 *   3. Run the `setup` function once (select it in the toolbar dropdown,
 *      click Run). It'll ask you to authorize — approve it. This stores
 *      your Supabase/Mapbox credentials in this script's own Script
 *      Properties (Project Settings), not in the code itself.
 *   4. Reload the spreadsheet tab. A "Gem Sync" menu appears next to Help.
 *      If you're using column I for photos: Gem Sync -> "Set photo
 *      folder..." and paste the Drive folder's URL (create the folder in
 *      Drive first, drop your photos in it). Skip this if you'll always
 *      paste ready-made URLs straight into column H instead.
 *   5. Triggers -> Add Trigger (clock icon in the left sidebar, or
 *      Triggers -> Add Trigger from the menu): choose function
 *      `onEditInstallable`, event source "From spreadsheet", event type
 *      "On edit". Save, authorize again if asked.
 *   6. For rows already in the sheet before this was set up, use
 *      Gem Sync -> "Sync all rows" once to backfill them — the on-edit
 *      trigger only fires for edits made AFTER it's installed.
 */

// ── one-time credential setup ──────────────────────────────────────────
// Run this once from the Apps Script editor. Values are the SAME anon-tier
// credentials already shipped inside Explorife's own compiled web app
// (visible in any browser's network tab) — not secrets, just kept out of
// the code body as a matter of habit so rotating a key is a Properties edit,
// not a code edit.
function setup() {
  const props = PropertiesService.getScriptProperties();
  props.setProperties({
    SUPABASE_URL: 'https://yshgjzmyapdepkapodno.supabase.co',
    SUPABASE_ANON_KEY:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlzaGdqem15YXBkZXBrYXBvZG5vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1Nzc0NDksImV4cCI6MjA4NzE1MzQ0OX0.rxKTnUxKbFQvRlDZlKfv5BtblR6kOS-WyeWcn4ZvDwY',
    MAPBOX_TOKEN:
      'pk.eyJ1IjoiZXhwbG9yaWZlIiwiYSI6ImNtbDZyNmR4eTBoeGczbXByMGoyamxhNXYifQ.3WScoFX7CTyGLeWaenVyBw',
  });
  // The credentials are already saved by this point — this confirmation is
  // best-effort. getUi() can throw "Cannot call SpreadsheetApp.getUi() from
  // this context" when run via the editor's own Run button rather than a
  // menu click; that's a display-only failure, not a sign setup() failed.
  try {
    SpreadsheetApp.getUi().alert('Gem Sync credentials saved. You can close this.');
  } catch (err) {
    Logger.log('Credentials saved (confirmation dialog unavailable in this context).');
  }
}

// ── column layout — edit these if you reorder the sheet ──────────────────
const COL = {
  NAME: 1, LOCATION: 2, CATEGORY: 3, TAGLINE: 4, DESCRIPTION: 5,
  DIFFICULTY: 6, BEST_TIME: 7, PHOTO_URL: 8, PHOTO_FILENAME: 9,
  LAT: 10, LNG: 11, GEM_ID: 12, STATUS: 13,
};
const HEADER_ROW = 1;
// 10 categories as of the heritage/landmark addition — must stay in sync
// with Gem.categories (lib/models/gem.dart) on the app side. heritage
// covers old towns/museums/cultural sites; landmark covers iconic natural
// wonders/scenic must-see spots, distinct from the more generic `nature`.
const VALID_CATEGORIES = [
  'hiking', 'camping', 'viewpoint', 'food', 'temple', 'cave', 'coastal', 'nature',
  'heritage', 'landmark',
];

// ── menu (manual sync entry points) ───────────────────────────────────────
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Gem Sync')
    .addItem('Sync all rows', 'syncAllRows')
    .addItem('Sync current row', 'syncActiveRow')
    .addSeparator()
    .addItem('Set photo folder...', 'setPhotoFolder')
    .addToUi();
}

// Prompts for the Drive folder URL/ID that Photo Filename (column I) looks
// files up in. Only needed if you're using that column at all — skip this
// entirely if you always paste ready-made URLs straight into Photo URL.
function setPhotoFolder() {
  const ui = SpreadsheetApp.getUi();
  const res = ui.prompt(
    'Photo folder',
    'Paste the Google Drive folder URL (or just its ID) that your gem photos live in:',
    ui.ButtonSet.OK_CANCEL
  );
  if (res.getSelectedButton() !== ui.Button.OK) return;
  const input = res.getResponseText().trim();
  const match = input.match(/[-\w]{25,}/); // a Drive folder ID embedded in a URL, or a bare ID
  const folderId = match ? match[0] : input;
  try {
    const folder = DriveApp.getFolderById(folderId); // throws if not a real/accessible folder
    PropertiesService.getScriptProperties().setProperty('PHOTO_FOLDER_ID', folderId);
    ui.alert('Photo folder set to "' + folder.getName() + '".');
  } catch (err) {
    ui.alert('Could not open that folder — check the URL and that you have access to it.');
  }
}

// ── installable "On edit" trigger target (see step 5 above) ──────────────
// A SIMPLE onEdit(e) can't call UrlFetchApp (Apps Script sandboxes simple
// triggers out of any authorized external call) — that's the whole reason
// this needs to be an installable trigger someone adds by hand once,
// rather than firing automatically just from being named `onEdit`.
function onEditInstallable(e) {
  const row = e.range.getRow();
  if (row <= HEADER_ROW) return; // header edited, nothing to sync
  if (e.range.getColumn() > COL.PHOTO_FILENAME) return; // a script-managed column was edited (or manually touched) — not a real content change to sync
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
  if (!name) return; // nothing to sync yet — e.g. a blank row someone clicked into

  const category = String(get(COL.CATEGORY) || '').trim().toLowerCase();
  if (category && VALID_CATEGORIES.indexOf(category) === -1) {
    setStatus_(sheet, row, 'Error: category must be one of ' + VALID_CATEGORIES.join(', '));
    return;
  }

  let lat = get(COL.LAT);
  let lng = get(COL.LNG);
  const location = String(get(COL.LOCATION) || '').trim();
  if ((!lat || !lng) && location) {
    const geocoded = geocodeLocation_(location);
    if (geocoded) {
      lat = geocoded.lat;
      lng = geocoded.lng;
      sheet.getRange(row, COL.LAT).setValue(lat);
      sheet.getRange(row, COL.LNG).setValue(lng);
    }
    // A failed geocode isn't fatal — the gem still upserts with no
    // coordinates, same as leaving Location blank; fix it and re-sync later.
  }

  // Both columns accept a comma-separated list, so a gem can carry any
  // number of photos — feeds the app's multi-photo gallery (Gem.allPhotos).
  // URLs (already resolved) come first, then filenames (each looked up in
  // the photo folder and uploaded to Storage), in the order authored.
  const photoUrls = splitList_(get(COL.PHOTO_URL));
  const photoFilenames = splitList_(get(COL.PHOTO_FILENAME));
  const allPhotoUrls = photoUrls.slice();
  for (const filename of photoFilenames) {
    try {
      allPhotoUrls.push(resolvePhotoUrl_(filename));
    } catch (err) {
      setStatus_(sheet, row, 'Error: ' + err.message);
      return; // don't sync a gem with a photo reference that couldn't be resolved
    }
  }
  // Write the fully-resolved set back into Photo URL so what's in the sheet
  // always reflects what actually got synced, same as the old single-photo
  // behavior — replaces whatever mix of raw URLs/filenames was there before.
  if (allPhotoUrls.length) {
    sheet.getRange(row, COL.PHOTO_URL).setValue(allPhotoUrls.join(', '));
  }

  const payload = {
    p_gem_id: get(COL.GEM_ID) || null,
    p_gem_name: name,
    p_gem_location: location || null,
    p_category: category || null,
    p_lat: lat ? Number(lat) : null,
    p_lng: lng ? Number(lng) : null,
    p_tagline: String(get(COL.TAGLINE) || '').trim() || null,
    p_description: String(get(COL.DESCRIPTION) || '').trim() || null,
    p_difficulty: String(get(COL.DIFFICULTY) || '').trim() || null,
    p_best_time_to_visit: String(get(COL.BEST_TIME) || '').trim() || null,
    p_photo_url: allPhotoUrls.length ? allPhotoUrls[0] : null,
    p_photo_urls: allPhotoUrls,
  };

  try {
    const gemId = callUpsertRpc_(payload);
    sheet.getRange(row, COL.GEM_ID).setValue(gemId);
    setStatus_(sheet, row, 'Synced ' + new Date().toLocaleString());
  } catch (err) {
    setStatus_(sheet, row, 'Error: ' + err.message);
  }
}

function setStatus_(sheet, row, text) {
  sheet.getRange(row, COL.STATUS).setValue(text);
}

// Splits a cell's comma-separated value into trimmed, non-empty entries.
// Empty cell (or just whitespace/commas) returns an empty array, not [''].
function splitList_(cellValue) {
  return String(cellValue || '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

// ── Drive photo lookup + Supabase Storage upload ──────────────────────────
// Finds [filename] in the folder set via "Gem Sync -> Set photo folder...",
// then uploads its actual bytes into Supabase Storage and returns the real
// public URL. Throws (caller turns that into the row's Sync Status) if no
// photo folder is set yet, no file in it matches [filename] exactly, or the
// upload itself fails.
//
// NOT just a Drive "share link" (the earlier approach): Google's
// drive.google.com/uc?export=view links only resolve reliably from an
// actual logged-in browser tab — a plain HTTP fetch (which is all Flutter's
// Image.network does) can hang or fail against them. Confirmed directly:
// curl against that URL format either times out or takes many seconds to
// redirect through drive.usercontent.google.com. Real object storage with a
// stable public URL is the only reliable option for embedding.
//
// The upload targets the `sheet-sync/` prefix inside the app's own
// `gem-photos` bucket — the ONLY path the anon key is allowed to write to
// (see supabase/migrations/20260823000000_allow_anon_sheet_sync_photo_uploads.sql).
// The path includes the Drive file's id (globally unique, stable across
// re-syncs of the same file) so re-syncing an unchanged photo overwrites the
// same object instead of accumulating duplicates.
function resolvePhotoUrl_(filename) {
  const folderId = PropertiesService.getScriptProperties().getProperty('PHOTO_FOLDER_ID');
  if (!folderId) {
    throw new Error('No photo folder set — run Gem Sync -> "Set photo folder..." first');
  }
  const files = DriveApp.getFolderById(folderId).getFilesByName(filename);
  if (!files.hasNext()) {
    throw new Error('No file named "' + filename + '" in the photo folder');
  }
  const file = files.next();
  const blob = file.getBlob();
  const safeName = filename.replace(/[^\w.-]/g, '-');
  const path = 'sheet-sync/' + file.getId() + '-' + safeName;
  return uploadToSupabaseStorage_(path, blob);
}

// Uploads [blob] to the `gem-photos` bucket at [path] via the Storage REST
// API, using the same anon key everything else in this script uses. Throws
// with the server's own error message on failure. `x-upsert: true` lets a
// re-sync overwrite the same path instead of erroring on a duplicate key.
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

// ── Mapbox Geocoding v6 (forward search) ──────────────────────────────────
function geocodeLocation_(location) {
  const token = PropertiesService.getScriptProperties().getProperty('MAPBOX_TOKEN');
  const url = 'https://api.mapbox.com/search/geocode/v6/forward'
    + '?q=' + encodeURIComponent(location)
    + '&limit=1&access_token=' + token;
  const res = UrlFetchApp.fetch(url, { muteHttpExceptions: true });
  if (res.getResponseCode() !== 200) return null;
  const data = JSON.parse(res.getContentText());
  const feature = data.features && data.features[0];
  if (!feature) return null;
  const coords = feature.geometry.coordinates; // [lng, lat]
  return { lat: coords[1], lng: coords[0] };
}

// ── Supabase RPC call ──────────────────────────────────────────────────────
function callUpsertRpc_(payload) {
  const props = PropertiesService.getScriptProperties();
  const url = props.getProperty('SUPABASE_URL') + '/rest/v1/rpc/upsert_gem_from_sheet';
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
