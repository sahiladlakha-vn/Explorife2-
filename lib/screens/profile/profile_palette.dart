part of 'profile_screen.dart';

// Profile-surface palette + month labels. Shared by every profile part.

// Light palette for the profile surface (the rest of the app is dark, but this
// page intentionally uses a bright "dashboard" look per the redesign).
const _kPage = Color(0xFFFFFFFF);
const _kStripe = Color(0xFFF1ECE4);
const _kCard = Color(0xFFF5F3EF);
const _kBorder = Color(0xFFE7E2D9);
const _kInk = Color(0xFF1A1A1A);
const _kMute = Color(0xFF8A8A8A);
const _kTeal = Color(0xFF12A594);
const _kGreen = Color(0xFF3C9A5F);
// Severity accents for alerts + pace (and the scheduled My Trip tab / booking
// pills). Named here because a second consumer is already on the roadmap — an
// unnamed Colors.red would diverge across surfaces. _kWarn == the existing
// _StoryRow "pending" goldenrod, promoted for symmetry; _kCritical is tuned for
// the light profile surface (the header's 0xFFFF6B6B is dark-surface-only).
const _kCritical = Color(0xFFD32F2F);
const _kWarn = Color(0xFFB8860B);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
