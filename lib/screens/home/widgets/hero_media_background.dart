/// Home hero background. On Flutter Web this is a real looping `<video>`
/// element (see hero_media_background_web.dart); on every other platform
/// (iOS/Android/desktop) it's just the static poster image.
///
/// Mobile deliberately does NOT get video: Flutter's video-playback stack has
/// real CPU/battery cost that a plain `Image` doesn't, and this feature was
/// scoped web-only rather than silently defaulting one way — see the doc
/// comment on `HeroMediaBackground` in hero_media_background_web.dart for the
/// full reasoning and the data-saver/cellular/reduced-motion fallback policy.
///
/// Follows the same conditional-export split already used for the Mapbox
/// globe view (lib/screens/explore/map_engine.dart): `dart.library.io` is
/// present on iOS/Android/desktop and absent on web, so native builds never
/// pull in `dart:js_interop`/`package:web`.
export 'hero_media_background_web.dart'
    if (dart.library.io) 'hero_media_background_native.dart';
