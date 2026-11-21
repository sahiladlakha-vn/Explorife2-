const DESTINATION_ALIASES: Record<string, string> = {
  "halong bay": "ha long bay",
  saigon: "ho chi minh city",
  "sai gon": "ho chi minh city",
  hcmc: "ho chi minh city",
  hcm: "ho chi minh city",
  "ho chi minh": "ho chi minh city",
  // "Hà Nội" is two words once the diacritics are gone; the featured
  // destination (and most typed spellings) is the one-word "Hanoi".
  "ha noi": "hanoi",
};

/**
 * Lowercases, strips Vietnamese diacritics, and collapses hyphens/periods/
 * whitespace. `đ` doesn't decompose under Unicode NFD like the other
 * diacritics do, so it needs an explicit replace before the NFD pass.
 */
function clean(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replace(/đ/g, "d")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[-.\s]+/g, " ")
    .trim();
}

/**
 * Key for a single place name: `clean`, then a leading "tp"/"thanh pho"
 * ("thành phố" = "city") is stripped generically — covers "TP.HCM", "TPHCM",
 * and "TP Ho Chi Minh" alike — before the alias map runs, so the map only
 * needs to know the city's own name ("hcm", "ho chi minh"), not every
 * prefixed variant of it.
 *
 * The alias map itself catches spellings cleaning alone can't unify —
 * different words entirely, not just different separators (e.g. "Halong"
 * fused vs "Ha Long" split, or "Saigon"/"HCM(C)" for "Ho Chi Minh City").
 */
function placeKey(rawPlace: string): string {
  const withoutCityPrefix = clean(rawPlace)
    .replace(/^(tp|thanh pho)\s*/, "")
    .trim();
  return DESTINATION_ALIASES[withoutCityPrefix] ?? withoutCityPrefix;
}

/** The non-empty, trimmed comma-separated parts of a location string. */
function segments(raw: string): string[] {
  return raw
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

const isVietnam = (segment: string): boolean => {
  const country = clean(segment);
  return country === "vietnam" || country === "viet nam";
};

/**
 * The key two location strings must share to count as the same destination.
 *
 * Trip locations are a mix of geocoder strings ("Da Nang, Vietnam", "Hội An,
 * An Giang, Vietnam") and typed text ("da nang", "hoi an"), so the whole
 * string is the wrong thing to compare. The key is the **place name** — the
 * part before the first comma — cleaned as per `placeKey`, so the province
 * and country that a geocoder appends don't keep "Da Nang, Vietnam" and "da
 * nang" apart.
 *
 * **Country guard:** with two or more parts, the last one is the country. A
 * Vietnamese one ("Vietnam"/"Viet Nam"/"Việt Nam") is dropped, as above; any
 * other country stays in the key ("hamburg, germany") and the Vietnam alias
 * map is not applied, so "Saigon, …, Indonesia" never folds into Ho Chi Minh
 * City. A string with no country (typed text) is compared on its place name
 * alone, i.e. treated as Vietnamese, which is what this app is about.
 *
 * Known safe misses (they stay apart rather than merging wrongly): typed
 * text whose second part isn't a country ("Hội An, Quảng Nam" vs "hoi an"),
 * and a typed foreign place without its country ("hamburg" vs "Hamburg,
 * Germany").
 */
export function normalizeDestination(raw: string): string {
  const parts = segments(raw);
  if (parts.length === 0) return "";

  const place = parts[0]!;
  if (parts.length === 1) return placeKey(place);

  const country = parts[parts.length - 1]!;
  if (isVietnam(country)) return placeKey(place);
  return `${clean(place)}, ${clean(country)}`;
}

/**
 * How a destination is shown: its place name, plus ", Country" unless it is
 * Vietnam — "Da Nang" for "Da Nang, Vietnam", but "Hamburg, Germany". The
 * original spelling (case, diacritics) is kept; only the geocoder's province
 * and region parts are dropped. Always agrees with `normalizeDestination`:
 * `normalizeDestination(destinationLabel(x)) === normalizeDestination(x)`.
 */
export function destinationLabel(raw: string): string {
  const parts = segments(raw);
  if (parts.length === 0) return raw.trim();

  const place = parts[0]!;
  if (parts.length === 1) return place;

  const country = parts[parts.length - 1]!;
  return isVietnam(country) ? place : `${place}, ${country}`;
}
