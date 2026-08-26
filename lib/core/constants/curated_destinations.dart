/// Editorial "popular destinations" content for the Home screen's "Where to
/// next?" browser (destination_browser_sheet.dart). Deliberately NOT dynamic
/// data: Mapbox's Search Box / Tilequery / Geocoding APIs are all
/// query-or-coordinate-triggered with no "top destinations in a country"
/// browse mode (confirmed before building this — see the investigation this
/// shipped alongside), so a country→city grouping like this has no dynamic
/// source and has to be a maintained list. What's NOT faked: when a user
/// taps a city here, its coordinates are resolved for real via
/// GeocodingService.search() (the exact same service backing the "Where to?"
/// autocomplete in trip setup) — nothing here is a stand-in coordinate.
///
/// [CuratedCity.photoUrl] entries are a best-effort real photo per city, not
/// verified by loading them (this environment can't browse to confirm), so
/// spot-check these and swap any that don't load or don't match before
/// relying on them — that's genuine ongoing maintenance, same as any
/// editorial content set. [moreCities] (the secondary chip list) carries no
/// photo at all, matching the reference design's own chips-only treatment
/// for a country's lesser-known spots.
class CuratedCity {
  final String name;
  final String? photoUrl;
  const CuratedCity({required this.name, this.photoUrl});
}

class CuratedCountry {
  final String name;
  final List<CuratedCity> topCities;
  final List<String> moreCities;
  const CuratedCountry({
    required this.name,
    required this.topCities,
    this.moreCities = const [],
  });
}

class CuratedRegion {
  final String name;
  final List<CuratedCountry> countries;
  const CuratedRegion({required this.name, required this.countries});
}

class CuratedDestinations {
  static const List<CuratedRegion> regions = [
    CuratedRegion(name: 'Asia', countries: [
      CuratedCountry(
        name: 'Vietnam',
        topCities: [
          CuratedCity(
            name: 'Hanoi',
            photoUrl: 'https://images.unsplash.com/photo-1509030450996-dd1a26dda07a?w=800&q=80',
          ),
          CuratedCity(
            name: 'Ho Chi Minh City',
            photoUrl: 'https://images.unsplash.com/photo-1583417319070-4a69db38a482?w=800&q=80',
          ),
          CuratedCity(
            name: 'Da Nang',
            photoUrl: 'https://images.unsplash.com/photo-1552465011-b4e21bf6e79a?w=800&q=80',
          ),
        ],
        moreCities: [
          'Phu Quoc', 'Sapa', 'Hoi An', 'Nha Trang', 'Ninh Binh',
          'Da Lat', 'Ha Long', 'Hue', 'Vung Tau',
        ],
      ),
      CuratedCountry(
        name: 'Thailand',
        topCities: [
          CuratedCity(
            name: 'Bangkok',
            photoUrl: 'https://images.unsplash.com/photo-1508009603885-50cf7c579365?w=800&q=80',
          ),
          CuratedCity(
            name: 'Chiang Mai',
            photoUrl: 'https://images.unsplash.com/photo-1598935888738-cd2622bfe437?w=800&q=80',
          ),
          CuratedCity(
            name: 'Phuket',
            photoUrl: 'https://images.unsplash.com/photo-1589394815804-964ed0be2eb5?w=800&q=80',
          ),
        ],
        moreCities: ['Krabi', 'Pattaya', 'Ayutthaya', 'Koh Samui'],
      ),
      CuratedCountry(
        name: 'South Korea',
        topCities: [
          CuratedCity(
            name: 'Seoul',
            photoUrl: 'https://images.unsplash.com/photo-1538485399081-7191377e8241?w=800&q=80',
          ),
          CuratedCity(
            name: 'Busan',
            photoUrl: 'https://images.unsplash.com/photo-1517154421773-0529f29ea451?w=800&q=80',
          ),
          CuratedCity(name: 'Jeju Island'),
        ],
        moreCities: ['Incheon', 'Gyeongju', 'Jeonju'],
      ),
      CuratedCountry(
        name: 'Philippines',
        topCities: [
          CuratedCity(
            name: 'Manila',
            photoUrl: 'https://images.unsplash.com/photo-1518509562904-e7ef99cdcc86?w=800&q=80',
          ),
          CuratedCity(
            name: 'Palawan',
            photoUrl: 'https://images.unsplash.com/photo-1518877593221-1f28583780b4?w=800&q=80',
          ),
          CuratedCity(name: 'Cebu'),
        ],
        moreCities: ['Boracay', 'Bohol', 'Siargao'],
      ),
    ]),
    CuratedRegion(name: 'Europe', countries: [
      CuratedCountry(
        name: 'France',
        topCities: [
          CuratedCity(
            name: 'Paris',
            photoUrl: 'https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800&q=80',
          ),
          CuratedCity(name: 'Nice'),
          CuratedCity(name: 'Lyon'),
        ],
        moreCities: ['Marseille', 'Bordeaux', 'Strasbourg'],
      ),
      CuratedCountry(
        name: 'Italy',
        topCities: [
          CuratedCity(
            name: 'Rome',
            photoUrl: 'https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=800&q=80',
          ),
          CuratedCity(
            name: 'Venice',
            photoUrl: 'https://images.unsplash.com/photo-1523906834658-6e24ef2386f9?w=800&q=80',
          ),
          CuratedCity(name: 'Florence'),
        ],
        moreCities: ['Milan', 'Naples', 'Amalfi Coast'],
      ),
      CuratedCountry(
        name: 'Spain',
        topCities: [
          CuratedCity(
            name: 'Barcelona',
            photoUrl: 'https://images.unsplash.com/photo-1583422409516-2895a77efded?w=800&q=80',
          ),
          CuratedCity(name: 'Madrid'),
          CuratedCity(name: 'Seville'),
        ],
        moreCities: ['Valencia', 'Granada', 'Ibiza'],
      ),
    ]),
    CuratedRegion(name: 'Oceania', countries: [
      CuratedCountry(
        name: 'Australia',
        topCities: [
          CuratedCity(
            name: 'Sydney',
            photoUrl: 'https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?w=800&q=80',
          ),
          CuratedCity(name: 'Melbourne'),
          CuratedCity(name: 'Gold Coast'),
        ],
        moreCities: ['Brisbane', 'Perth', 'Cairns'],
      ),
      CuratedCountry(
        name: 'New Zealand',
        topCities: [
          CuratedCity(
            name: 'Auckland',
            photoUrl: 'https://images.unsplash.com/photo-1507699622108-4be3abd695ad?w=800&q=80',
          ),
          CuratedCity(name: 'Queenstown'),
          CuratedCity(name: 'Wellington'),
        ],
        moreCities: ['Rotorua', 'Christchurch'],
      ),
    ]),
    CuratedRegion(name: 'North America', countries: [
      CuratedCountry(
        name: 'United States',
        topCities: [
          CuratedCity(
            name: 'New York',
            photoUrl: 'https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=800&q=80',
          ),
          CuratedCity(
            name: 'Los Angeles',
            photoUrl: 'https://images.unsplash.com/photo-1444723121867-7a241cacace9?w=800&q=80',
          ),
          CuratedCity(name: 'San Francisco'),
        ],
        moreCities: ['Miami', 'Las Vegas', 'Chicago'],
      ),
      CuratedCountry(
        name: 'Canada',
        topCities: [
          CuratedCity(
            name: 'Vancouver',
            photoUrl: 'https://images.unsplash.com/photo-1560814304-4f05b62af116?w=800&q=80',
          ),
          CuratedCity(name: 'Toronto'),
          CuratedCity(name: 'Banff'),
        ],
        moreCities: ['Montreal', 'Quebec City'],
      ),
    ]),
  ];
}
