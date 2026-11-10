import 'package:flutter/material.dart';

/// Native (iOS/Android/desktop) Home hero background: the static poster
/// still, bundled as a normal Flutter asset. See hero_media_background.dart's
/// doc comment for why mobile doesn't get the looping video.
class HeroMediaBackground extends StatelessWidget {
  const HeroMediaBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/hero-poster-web.jpg',
      fit: BoxFit.cover,
    );
  }
}
