part of '../profile_screen.dart';

// Cross-tab shared widgets: cards, story/gem rows, empty + sign-in states.

// ─────────────────────────────────────────
// SHARED PIECES
// ─────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _CardHeader(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _StoryRow extends StatelessWidget {
  final Story story;
  final bool divider;
  const _StoryRow({required this.story, required this.divider});

  @override
  Widget build(BuildContext context) {
    final approved = story.status.toLowerCase() == 'approved';
    final pending = story.status.toLowerCase() == 'pending';
    final pillColor = approved
        ? _kGreen
        : pending
            ? const Color(0xFFB8860B)
            : _kMute;
    return GestureDetector(
      onTap: () => context.go('/stories/${story.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: divider
              ? const Border(top: BorderSide(color: _kBorder))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                        fontSize: 16, fontWeight: FontWeight.w800, color: _kInk),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (story.location ?? 'UNKNOWN').toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: _kMute, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: pillColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: pillColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(approved ? Icons.check : Icons.schedule,
                      size: 12, color: pillColor),
                  const SizedBox(width: 4),
                  Text(
                    story.status.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: pillColor,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? cta;
  final VoidCallback? onTap;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.cta,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: _kBorder),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.bebasNeue(fontSize: 26, color: _kInk)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: _kMute, height: 1.5)),
            if (cta != null) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(cta!,
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🧗', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 20),
              Text('JOIN THE TRIBE',
                  style: GoogleFonts.bebasNeue(
                      fontSize: 32,
                      color: AppTheme.textPrimary,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Text(
                'Sign in to access your profile, save gems, track hikes, and connect with fellow adventurers.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppTheme.textSecondary, height: 1.6),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/auth?redirect=/profile'),
                  child: const Text('Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
