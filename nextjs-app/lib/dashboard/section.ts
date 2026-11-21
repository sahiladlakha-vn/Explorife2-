/**
 * One dashboard card's data, or the fact that loading it failed. The page
 * settles every query independently into one of these, so a failing query
 * blanks only its own card instead of throwing the whole page into the root
 * error boundary.
 */
export type Section<T> = { status: "ok"; data: T } | { status: "error" };

export const ok = <T>(data: T): Section<T> => ({ status: "ok", data });
export const failed = <T = never>(): Section<T> => ({ status: "error" });
