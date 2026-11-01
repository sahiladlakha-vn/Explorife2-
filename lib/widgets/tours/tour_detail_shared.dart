import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../models/tour.dart';

/// Shared dark-theme building blocks for anything showing a [Tour]'s detail
/// content — originally all private to TourDetailScreen, extracted so
/// TourExperienceCard (the Home rail's own mini detail view) renders the
/// exact same widgets instead of a second, drifting copy. Matches the Home
/// rail's own dark card shell (_IdeaStyleCard in home_screen.dart, #111827 +
/// white text at descending alpha) — both screens now share one dark theme
/// rather than TourDetailScreen living in the app's separate light theme.
const darkBg = Color(0xFF111827);
final darkMute = Colors.white.withValues(alpha: 0.65);
final darkFaint = Colors.white.withValues(alpha: 0.5);
final darkFill = Colors.white.withValues(alpha: 0.08);
final darkBorder = Colors.white.withValues(alpha: 0.14);
final darkDivider = Colors.white.withValues(alpha: 0.12);

/// Floating circular icon button over the hero photo — back on the left,
/// save/heart on the right. Same 36px black-scrim-circle treatment as
/// GemDetailScreen's own header icon, so every detail-style hero overlay
/// looks identical.
class HeaderIcon extends StatelessWidget {
  const HeaderIcon(
      {super.key, required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Duration / group size / pickup — always exactly three cells in one row
/// (never a variable-count grid), so the row looks the same whether or not
/// every field has data. Missing free-text fields render an honest "Not
/// specified" rather than being hidden or fabricated; [Tour.pickupIncluded]
/// always has a real answer, so that cell never falls back.
class QuickFactsRow extends StatelessWidget {
  const QuickFactsRow({super.key, required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final duration = (tour.durationLabel != null && tour.durationLabel!.isNotEmpty)
        ? tour.durationLabel!
        : 'Not specified';
    final groupSize =
        (tour.groupSizeLabel != null && tour.groupSizeLabel!.isNotEmpty)
            ? tour.groupSizeLabel!
            : 'Not specified';
    final pickup = tour.pickupIncluded
        ? ((tour.pickupDetail?.isNotEmpty ?? false)
            ? tour.pickupDetail!
            : 'Included')
        : 'Not included';

    return Row(children: [
      Expanded(
        child: QuickFactCell(
            icon: Icons.schedule, label: 'Duration', value: duration),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: QuickFactCell(
            icon: Icons.groups_outlined, label: 'Group size', value: groupSize),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: QuickFactCell(
            icon: Icons.directions_car_filled_outlined,
            label: 'Pickup',
            value: pickup),
      ),
    ]);
  }
}

class QuickFactCell extends StatelessWidget {
  const QuickFactCell(
      {super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: darkFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.jetBrainsMono(fontSize: 9, color: darkFaint)),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.fredoka(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}

/// Shared pill shell for the booking-control row above the sticky footer.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: darkFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: darkBorder),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: content,
      ),
    );
  }
}

class DatePill extends StatelessWidget {
  const DatePill({super.key, required this.selectedDate, required this.onTap});
  final DateTime? selectedDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = selectedDate;
    return Semantics(
      button: true,
      label: date != null
          ? 'Selected date ${date.day}/${date.month}/${date.year}'
          : 'Select a date',
      child: Pill(
        onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today_outlined,
              size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            date != null
                ? '${date.day}/${date.month}/${date.year}'
                : 'Select date',
            style: GoogleFonts.fredoka(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ]),
      ),
    );
  }
}

/// Guest-count pill — the +/- stepper lives inline in the pill itself
/// (rather than opening a separate sheet) so a one-tap adjustment doesn't
/// need a modal round-trip.
class GuestPill extends StatelessWidget {
  const GuestPill({super.key, required this.participants, required this.onChanged});
  final int participants;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Pill(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.people_outline, size: 14, color: AppTheme.primary),
        const SizedBox(width: 6),
        PillStepButton(
          icon: Icons.remove,
          onTap: participants > 1 ? () => onChanged(participants - 1) : null,
        ),
        SizedBox(
          width: 22,
          child: Text('$participants',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        PillStepButton(icon: Icons.add, onTap: () => onChanged(participants + 1)),
      ]),
    );
  }
}

class PillStepButton extends StatelessWidget {
  const PillStepButton({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon,
              size: 14,
              color: disabled
                  ? Colors.white.withValues(alpha: 0.3)
                  : AppTheme.primary),
        ),
      ),
    );
  }
}

class LanguagePill extends StatelessWidget {
  const LanguagePill({super.key, required this.language, required this.onTap});
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pill(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.language, size: 14, color: AppTheme.primary),
        const SizedBox(width: 6),
        Text(language,
            style: GoogleFonts.fredoka(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
      ]),
    );
  }
}

/// Shared "this tab has nothing yet" state for all 4 tabs. Top-aligned
/// (not vertically centered) deliberately — see call sites for why a
/// dead-centered empty state can end up looking hidden in a short box.
class EmptyTabState extends StatelessWidget {
  const EmptyTabState(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Text(text, style: GoogleFonts.fredoka(color: darkMute)),
      ),
    );
  }
}

/// Overview tab — the listing's description, plus an honest "N stops on
/// this tour" line when an itinerary exists. There was never a second,
/// different field for a duplicate "full description" tab: both used to
/// show [Tour.fullDescription], so this is the single merged view.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final description = tour.fullDescription;
    if ((description == null || description.isEmpty) && tour.itinerary.isEmpty) {
      return const EmptyTabState('No description yet.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (description != null && description.isNotEmpty)
          Text(description,
              style: GoogleFonts.fredoka(fontSize: 14, color: darkMute, height: 1.6)),
        if (tour.itinerary.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.map_outlined, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('${tour.itinerary.length} stops on this tour',
                style: GoogleFonts.fredoka(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ],
      ],
    );
  }
}

class ItineraryTab extends StatelessWidget {
  const ItineraryTab({super.key, required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    if (tour.itinerary.isEmpty) {
      return const EmptyTabState('No itinerary listed yet.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: tour.itinerary.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (ctx, i) {
        final step = tour.itinerary[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration:
                  const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(step.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: Colors.white)),
                    ),
                    if (step.time != null && step.time!.isNotEmpty)
                      Text(step.time!,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, color: AppTheme.primary)),
                  ]),
                  if (step.description != null && step.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(step.description!,
                        style: GoogleFonts.fredoka(
                            fontSize: 12.5, color: darkMute, height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shared bullet-list renderer for Highlights — the source list and
/// empty-state copy differ per caller.
class BulletTab extends StatelessWidget {
  const BulletTab({super.key, required this.items, required this.emptyText});
  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyTabState(emptyText);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(items[i],
                style: GoogleFonts.fredoka(fontSize: 13.5, color: darkMute, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// Includes tab — two independent lists (what's included, what's not),
/// each with its own empty state so an empty [Tour.excludes] doesn't read
/// as "everything is included" by omission.
class IncludesTab extends StatelessWidget {
  const IncludesTab({super.key, required this.tour});
  final Tour tour;

  @override
  Widget build(BuildContext context) {
    if (tour.includes.isEmpty && tour.excludes.isEmpty) {
      return const EmptyTabState('No inclusions listed yet.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        IncludesSection(
          title: "What's included",
          items: tour.includes,
          icon: Icons.check_circle_outline,
          iconColor: AppTheme.primary,
          emptyText: 'Nothing listed yet.',
        ),
        const SizedBox(height: 22),
        IncludesSection(
          title: "What's not included",
          items: tour.excludes,
          icon: Icons.cancel_outlined,
          iconColor: darkFaint,
          emptyText: 'Nothing listed yet.',
        ),
      ],
    );
  }
}

class IncludesSection extends StatelessWidget {
  const IncludesSection({
    super.key,
    required this.title,
    required this.items,
    required this.icon,
    required this.iconColor,
    required this.emptyText,
  });

  final String title;
  final List<String> items;
  final IconData icon;
  final Color iconColor;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.bebasNeue(
                fontSize: 16, letterSpacing: 0.5, color: Colors.white)),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text(emptyText, style: GoogleFonts.fredoka(fontSize: 13, color: darkMute))
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item,
                        style: GoogleFonts.fredoka(
                            fontSize: 13.5, color: darkMute, height: 1.5)),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
