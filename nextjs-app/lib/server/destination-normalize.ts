const DESTINATION_ALIASES: Record<string, string> = {
  "halong bay": "ha long bay",
  saigon: "ho chi minh city",
  "sai gon": "ho chi minh city",
  hcmc: "ho chi minh city",
  hcm: "ho chi minh city",
  "ho chi minh": "ho chi minh city",
};

/**
 * Lowercases, strips Vietnamese diacritics, and collapses hyphens/periods/
 * whitespace so e.g. "Đà Nẵng", "da-nang", and "DA NANG" all normalize
 * identically. `đ` doesn't decompose under Unicode NFD like the other
 * diacritics do, so it needs an explicit replace before the NFD pass.
 *
 * A leading "tp"/"thanh pho" ("thành phố" = "city") is then stripped
 * generically — covers "TP.HCM", "TPHCM", and "TP Ho Chi Minh" alike — before
 * the alias map runs, so the map only needs to know the city's own name
 * ("hcm", "ho chi minh"), not every prefixed variant of it.
 *
 * The alias map itself catches spellings normalization alone can't unify —
 * different words entirely, not just different separators (e.g. "Halong"
 * fused vs "Ha Long" split, or "Saigon"/"HCM(C)" for "Ho Chi Minh City").
 */
export function normalizeDestination(raw: string): string {
  const collapsed = raw
    .trim()
    .toLowerCase()
    .replace(/đ/g, "d")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[-.\s]+/g, " ")
    .trim();
  const withoutCityPrefix = collapsed.replace(/^(tp|thanh pho)\s*/, "").trim();
  return DESTINATION_ALIASES[withoutCityPrefix] ?? withoutCityPrefix;
}
