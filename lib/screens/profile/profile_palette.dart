part of 'profile_screen.dart';

// Profile-surface palette + month labels. Shared by every profile part.

// Dark palette for the profile surface — brought in line with the rest of
// the (dark) app per the 2026-09-13 "dark, minimal, editorial" redesign pass.
// This used to be a deliberately bright/light "dashboard" look; that call
// was reversed wholesale, so every name below now points at a dark-surface
// value instead. Consumers (every other profile part file, via `part of`)
// didn't need to change at all — that's the point of centralizing these.
const _kPage = Color(0xFF0A0A0A);
const _kCard = Color(0xFF171717);
const _kBorder = Color(0xFF2A2A2A);
const _kInk = Color(0xFFF2F2F2);
const _kMute = Color(0xFF9A9A9A);
const _kTeal = Color(0xFF12A594);
// Dark-navy fill for the My Trip day map panel (item 10 of the 2026-09-13
// redesign) — the map's own base tone before/around tiles and callouts,
// distinct from the flat-neutral `_kCard` every other surface uses.
const _kNavy = Color(0xFF0B1220);
const _kGreen = Color(0xFF3C9A5F);
// Muted blue used for the "Member" identity pill (replaces the old
// orange-tinted badge — orange is now reserved for primary CTAs only).
const _kBlue = Color(0xFF5B8DEF);
// Severity accents for alerts + pace (and the scheduled My Trip tab / booking
// pills). Named here because a second consumer is already on the roadmap — an
// unnamed Colors.red would diverge across surfaces. _kWarn == the existing
// _StoryRow "pending" goldenrod, promoted for symmetry. _kCritical/_kWarn are
// left as-is: both already read fine against a dark card surface.
const _kCritical = Color(0xFFEF5350);
const _kWarn = Color(0xFFD4A017);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
