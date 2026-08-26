import 'package:flutter/widgets.dart';
import 'breakpoints.dart';

/// Caps [child] at a comfortable content width and centers it, but only at
/// desktop widths — below [Breakpoints.desktop] this is a no-op passthrough,
/// since mobile screens already fit their content to the phone width.
///
/// For the single-column card-list screens Phase 2 covers (Overview, My
/// Trip's read path, Stories, etc.): without this, handing a ListView the
/// ~1200px+ width SideNav's `Expanded` slot provides stretches every card
/// edge-to-edge with sparse, hard-to-read content. This is presentation
/// only — same widgets, same data, just bounded and centered instead of
/// stretched full-bleed.
class MaxWidthCenter extends StatelessWidget {
  const MaxWidthCenter({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!Breakpoints.isDesktop(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
