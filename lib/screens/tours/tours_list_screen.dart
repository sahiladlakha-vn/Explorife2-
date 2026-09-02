import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/tour.dart';
import '../../providers/tour_provider.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/state_views.dart';

/// Search results list for Trail/Tour — bookable, priced experiences,
/// deliberately a separate surface from ListingsScreen's Gems feed (Gems are
/// free, crowdsourced spots; Tours are priced, curated experiences). No
/// rating/review count on the card — see Tour's own doc comment for why
/// there's no rating data to show yet.
class ToursListScreen extends StatelessWidget {
  const ToursListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tourProv = context.watch<TourProvider>();

    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.lightSurface,
        foregroundColor: AppTheme.lightInk,
        elevation: 0,
        title: Text('Tours & Experiences',
            style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 0.5)),
      ),
      body: Builder(builder: (context) {
        if (tourProv.loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TrailListSkeleton(count: 4),
          );
        }
        if (tourProv.hasError) {
          return ErrorStateView(onRetry: tourProv.refresh, message: tourProv.error);
        }
        final tours = tourProv.tours;
        if (tours.isEmpty) {
          return const EmptyStateView(
            text: 'No tours available yet.',
            icon: Icons.explore_outlined,
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 230,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: tours.length,
          itemBuilder: (ctx, i) => TourCard(tour: tours[i]),
        );
      }),
    );
  }
}

/// One tour result card — photo, name, duration/pickup meta line, price
/// "From {currency} {amount}". "TOP PICK" only on [Tour.isCurated], never
/// derived from anything else.
class TourCard extends StatelessWidget {
  const TourCard({super.key, required this.tour});

  final Tour tour;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tour.name,
      child: GestureDetector(
        onTap: () => context.push('/tours/${tour.id}'),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(16)),
                        child: tour.coverPhoto != null
                            ? AppNetworkImage(url: tour.coverPhoto!)
                            : Container(
                                color: AppTheme.lightBorder.withValues(alpha: 0.4),
                                alignment: Alignment.center,
                                child: Text(tour.emoji,
                                    style: const TextStyle(fontSize: 36)),
                              ),
                      ),
                    ),
                    if (tour.isCurated)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('TOP PICK',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tour.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.lightInk),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      if (tour.durationLabel != null) ...[
                        const Icon(Icons.schedule,
                            size: 12, color: AppTheme.lightMute),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(tour.durationLabel!,
                              style: const TextStyle(
                                  color: AppTheme.lightMute, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      if (tour.pickupIncluded) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.directions_car_filled_outlined,
                            size: 12, color: AppTheme.lightMute),
                      ],
                    ]),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: 'From ',
                            style: GoogleFonts.fredoka(
                                fontSize: 10.5, color: AppTheme.lightMute)),
                        TextSpan(
                            text: '${tour.currency} ${tour.priceFrom}',
                            style: GoogleFonts.fredoka(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary)),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
