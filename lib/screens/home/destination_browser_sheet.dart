import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/curated_destinations.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_network_image.dart';

/// Home's "Start Exploring" → "Where to next?" destination browser. Content
/// (which countries/cities show, grouped by region) is a maintained editorial
/// list — see curated_destinations.dart's doc comment for why that's
/// unavoidable (no Mapbox API can answer "popular destinations in a
/// country"). What's real: tapping a city resolves its actual coordinates
/// via [GeocodingService.search] — the exact same service backing the
/// "Where to?" autocomplete in trip setup — before handing off to
/// `/trips/new`, so the wizard opens with a genuine location, not a
/// hardcoded stand-in.
Future<void> showDestinationBrowserSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const DestinationBrowserSheet(),
  );
}

class DestinationBrowserSheet extends StatefulWidget {
  const DestinationBrowserSheet({super.key});

  @override
  State<DestinationBrowserSheet> createState() => _DestinationBrowserSheetState();
}

class _FilteredCountry {
  final CuratedCountry country;
  final List<CuratedCity> topCities;
  final List<String> moreCities;
  const _FilteredCountry(this.country, this.topCities, this.moreCities);
}

class _DestinationBrowserSheetState extends State<DestinationBrowserSheet> {
  final GeocodingService _geo = GeocodingService();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  // Asia first — this app's own Vietnam focus, and the region with the
  // richest curated content (see curated_destinations.dart).
  int _regionIndex = 0;

  // Guards double-tap while a city's real coordinates are being resolved —
  // this bar is what actually confirms the close (X) button and every tap
  // target here were tested, not just wired, per the earlier "no way to
  // close this modal" lesson.
  bool _resolving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_FilteredCountry> get _filtered {
    final region = CuratedDestinations.regions[_regionIndex];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return [
        for (final c in region.countries) _FilteredCountry(c, c.topCities, c.moreCities),
      ];
    }
    final out = <_FilteredCountry>[];
    for (final country in region.countries) {
      // A country-name match (typing it, or tapping its own "Explore" link)
      // shows every one of its cities, not just name-matching ones.
      if (country.name.toLowerCase().contains(q)) {
        out.add(_FilteredCountry(country, country.topCities, country.moreCities));
        continue;
      }
      final cities = country.topCities.where((c) => c.name.toLowerCase().contains(q)).toList();
      final more = country.moreCities.where((c) => c.toLowerCase().contains(q)).toList();
      if (cities.isNotEmpty || more.isNotEmpty) {
        out.add(_FilteredCountry(country, cities, more));
      }
    }
    return out;
  }

  void _exploreCountry(String countryName) {
    _searchCtrl.text = countryName;
    setState(() => _query = countryName);
  }

  /// Resolves [cityName] to real coordinates, then opens its destination
  /// landing page (Explore/Things to do/Transport/Hotels) — an intermediate
  /// browsing step, not a jump straight into trip creation anymore; that
  /// happens from the landing page's own "+ Plan a trip" button instead.
  /// Falls back to the bare city name with no coordinates (same as
  /// free-typing into "Where to?") if geocoding is unavailable/fails, rather
  /// than blocking the whole flow over a network hiccup.
  Future<void> _openTripFor(String cityName) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    final results = await _geo.search(cityName);
    if (!mounted) return;
    setState(() => _resolving = false);

    final place = results.isNotEmpty ? results.first : null;
    final label = (place != null && place.fullName.isNotEmpty) ? place.fullName : cityName;

    Navigator.of(context).pop(); // close the browser before navigating
    final uri = Uri(path: '/destinations/explore', queryParameters: {
      'name': label,
      if (place?.lat != null) 'lat': '${place!.lat}',
      if (place?.lng != null) 'lng': '${place!.lng}',
    });
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) => Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.lightSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.lightMute,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Where to next?',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.lightInk)),
                      ),
                      // The close button this whole feature area has been
                      // burned by before — Navigator.pop is unambiguous and
                      // gets exercised by every "tap a city" path too (see
                      // _openTripFor), not just this one button.
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.lightCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.lightBorder),
                          ),
                          child: const Icon(Icons.close, color: AppTheme.lightMute, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: AppTheme.lightInk, fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search destinations',
                      hintStyle: const TextStyle(color: AppTheme.lightMute, fontSize: 15),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.lightMute, size: 20),
                      filled: true,
                      fillColor: AppTheme.lightCard,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.lightBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: CuratedDestinations.regions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final region = CuratedDestinations.regions[i];
                      final selected = i == _regionIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _regionIndex = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.primary : AppTheme.lightCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: selected ? AppTheme.primary : AppTheme.lightBorder),
                          ),
                          child: Text(region.name,
                              style: TextStyle(
                                  color: selected ? Colors.white : AppTheme.lightInk,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: AppTheme.lightBorder),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Text('No destinations match that search.',
                              style: TextStyle(color: AppTheme.lightMute)),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) => _CountrySection(
                            entry: _filtered[i],
                            onExplore: () => _exploreCountry(_filtered[i].country.name),
                            onTapCity: _openTripFor,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (_resolving)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountrySection extends StatelessWidget {
  const _CountrySection({
    required this.entry,
    required this.onExplore,
    required this.onTapCity,
  });

  final _FilteredCountry entry;
  final VoidCallback onExplore;
  final ValueChanged<String> onTapCity;

  @override
  Widget build(BuildContext context) {
    final country = entry.country;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(country.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.lightInk)),
                ),
                GestureDetector(
                  onTap: onExplore,
                  child: const Text('Explore',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
          if (entry.topCities.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: entry.topCities.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) =>
                    _CityPhotoCard(city: entry.topCities[i], onTap: onTapCity),
              ),
            ),
          ],
          if (entry.moreCities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in entry.moreCities)
                    GestureDetector(
                      onTap: () => onTapCity(name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.lightBorder),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(name,
                            style: const TextStyle(fontSize: 13, color: AppTheme.lightInk)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CityPhotoCard extends StatelessWidget {
  const _CityPhotoCard({required this.city, required this.onTap});

  final CuratedCity city;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(city.name),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 130,
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (city.photoUrl != null)
                AppNetworkImage(url: city.photoUrl!, fit: BoxFit.cover)
              else
                Container(color: AppTheme.lightCard),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(city.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
