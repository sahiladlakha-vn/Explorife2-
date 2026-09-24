// Web implementation of the Home hero background: a real HTML5 `<video>`
// (autoplay/muted, manually crossfade-looped) embedded via a platform view —
// same technique as the Mapbox globe in map_engine_web.dart, minus a bespoke
// JS bridge file; package:web's typed DOM bindings are enough for plain
// `<video>` elements.
import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

int _viewSeq = 0;

/// Home hero background on Flutter Web.
///
/// Renders a muted, autoplaying, manually-looped `<video>` (WebM/VP9
/// preferred, H.264 MP4 fallback source) under the hero's existing gradient
/// scrims and text overlay, UNLESS any of the following hold — in which case
/// it renders the plain static poster image instead, matching the ticket's
/// fallback requirements one-for-one:
///
///  - `prefers-reduced-motion: reduce` is set. This is an accessibility
///    requirement, not a nice-to-have: autoplaying motion backgrounds are a
///    documented trigger for vestibular disorders, and this media query
///    exists specifically so a user can opt out of that globally.
///  - `navigator.connection.saveData` is true — the user has explicitly told
///    their browser/OS to minimize data usage.
///  - `navigator.connection.effectiveType` reports a slow tier
///    (`slow-2g`/`2g`/`3g`). Product decision (documented here since the
///    original brief said not to default silently): the Network Information
///    API doesn't expose a clean, cross-browser "is this cellular" boolean
///    (Safari and Firefox don't implement the API at all, and even where it
///    exists, `connection.type` — the literal wifi/cellular/ethernet enum —
///    isn't part of the stable spec surface package:web binds). Treating
///    slow `effectiveType` tiers as "assume metered/constrained, show the
///    poster" is the closest reliable proxy for "don't force a ~2MB
///    download on a bad or possibly-cellular connection" available without
///    that field. `4g`/unknown/unsupported are treated as fine to autoplay —
///    i.e. this fails open (autoplay) on browsers that don't support the API
///    at all (Safari), rather than silently disabling video for every
///    non-Chromium visitor.
///  - either video element fires an `error` event (e.g. the asset request
///    fails) — swaps back to the poster live, no reload needed.
///
/// The poster is also set as the native `<video poster>` attribute, so it's
/// what's shown while the video is still buffering even in the autoplay
/// case.
///
/// ### Why two `<video>` elements instead of the native `loop` attribute
///
/// The native `loop` attribute restarts playback by jumping straight back to
/// frame 0 the instant the clip ends — an instantaneous cut with zero
/// blending, so *any* visual mismatch between the last and first frame
/// (lighting drift, grain, clouds, a subject that isn't in the exact same
/// position) reads as a visible jump. That held even for the checked-in clip,
/// whose endpoints are close but not pixel-identical (see the frame-diff
/// tooling in scripts/check_loop_seam.py).
///
/// Instead, two stacked `<video>` elements play the same source, and shortly
/// before the visible one reaches its end, the code starts the *other* one
/// from time zero and cross-dissolves between them via a plain CSS `opacity`
/// transition (see `_crossfadeMs`). The dissolve masks the seam far more
/// reliably than trying to make the source clip loop losslessly, and it's a
/// standard technique for ambient/background looping video for exactly this
/// reason.
class HeroMediaBackground extends StatefulWidget {
  const HeroMediaBackground({super.key});

  @override
  State<HeroMediaBackground> createState() => _HeroMediaBackgroundState();
}

class _HeroMediaBackgroundState extends State<HeroMediaBackground> {
  static const _posterAsset = 'assets/images/hero-poster-web.jpg';
  static const _mp4Asset = 'assets/video/hero-optimized.mp4';
  static const _webmAsset = 'assets/video/hero-optimized.webm';

  static const _slowConnectionTiers = {'slow-2g', '2g', '3g'};

  /// How long the crossfade dissolve between the two video layers takes.
  /// Long enough to hide the seam, short enough not to visibly "double
  /// expose" the two frames for long — well under half the ~4.9s clip.
  static const _crossfadeMs = 800;

  bool _useVideo = false;
  String? _viewType;

  @override
  void initState() {
    super.initState();
    _useVideo = _shouldAutoplayVideo();
    if (_useVideo) _registerVideoView();
  }

  bool _shouldAutoplayVideo() {
    try {
      if (web.window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
        return false;
      }
    } catch (_) {
      // matchMedia is universally supported; if this somehow throws, fail
      // toward the static image rather than risk autoplaying motion for a
      // user who asked to avoid it.
      return false;
    }

    try {
      final connection = web.window.navigator.connection;
      if (connection.saveData) return false;
      if (_slowConnectionTiers.contains(connection.effectiveType)) {
        return false;
      }
    } catch (_) {
      // Network Information API isn't implemented in Safari/Firefox — when
      // it's simply absent we can't tell metered/cellular apart from
      // ordinary broadband, so default to autoplay (see class doc).
    }
    return true;
  }

  /// Resolves a bundled Flutter asset key (e.g. 'assets/video/x.mp4') to the
  /// absolute URL Flutter Web actually serves it at, honoring whatever
  /// base-href the app is deployed under instead of hardcoding one.
  String _assetUrl(String key) => Uri.base.resolve('assets/$key').toString();

  web.HTMLVideoElement _buildVideoLayer() {
    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..muted = true
      ..loop = false // looping is driven manually via the crossfade below.
      ..controls = false
      ..poster = _assetUrl(_posterAsset)
      ..setAttribute('playsinline', '')
      ..setAttribute('webkit-playsinline', '')
      ..style.position = 'absolute'
      ..style.inset = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.opacity = '0'
      ..style.transition = 'opacity ${_crossfadeMs}ms linear';

    void addSource(String key, String type) {
      final source =
          web.document.createElement('source') as web.HTMLSourceElement
            ..src = _assetUrl(key)
            ..type = type;
      video.appendChild(source);
    }

    // WebM/VP9 first — the browser picks the first <source> it supports, and
    // VP9 is both smaller and the preferred format per the brief.
    addSource(_webmAsset, 'video/webm');
    addSource(_mp4Asset, 'video/mp4');

    video.addEventListener(
      'error',
      (web.Event _) {
        if (mounted) setState(() => _useVideo = false);
      }.toJS,
    );

    return video;
  }

  void _registerVideoView() {
    final viewType = 'explorife-hero-video-${_viewSeq++}';
    final host = web.document.createElement('div') as web.HTMLDivElement
      ..style.position = 'relative'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.overflow = 'hidden';

    final layers = [_buildVideoLayer(), _buildVideoLayer()];
    for (final layer in layers) {
      host.appendChild(layer);
    }

    var activeIndex = 0;
    var switching = false;
    layers[activeIndex].style.opacity = '1';

    void handleTimeUpdate(int index) {
      if (index != activeIndex || switching) return;
      final active = layers[activeIndex];
      final duration = active.duration;
      // NaN before metadata loads; guard so a stray early timeupdate can't
      // misfire the crossfade against a bogus (or zero/near-zero) duration.
      if (duration.isNaN || duration <= (_crossfadeMs / 1000) * 2) return;
      if (active.currentTime < duration - (_crossfadeMs / 1000)) return;

      switching = true;
      final nextIndex = 1 - activeIndex;
      final next = layers[nextIndex];
      next.currentTime = 0;
      next.play().toDart.ignore();

      // Cross-dissolve: fade the ending layer out, the restarted one in.
      active.style.opacity = '0';
      next.style.opacity = '1';

      Timer(const Duration(milliseconds: _crossfadeMs), () {
        active.pause();
        activeIndex = nextIndex;
        switching = false;
      });
    }

    for (var i = 0; i < layers.length; i++) {
      final index = i;
      layers[i].addEventListener(
        'timeupdate',
        ((web.Event _) => handleTimeUpdate(index)).toJS,
      );
    }

    // Kick off playback on the first (visible) layer only; the second layer
    // stays paused at time 0, hidden, until the first crossfade triggers.
    layers[activeIndex].play().toDart.ignore();

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) => host);
    _viewType = viewType;
  }

  @override
  Widget build(BuildContext context) {
    if (!_useVideo || _viewType == null) {
      return Image.asset(_posterAsset, fit: BoxFit.cover);
    }
    return HtmlElementView(viewType: _viewType!);
  }
}
