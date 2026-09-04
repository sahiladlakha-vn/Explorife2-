enum PriceRange {
  low('\$'),
  medium('\$\$'),
  high('\$\$\$'),
  luxury('\$\$\$\$');

  const PriceRange(this.wire);
  final String wire;

  static PriceRange fromWire(String value) => switch (value) {
        '\$\$' => PriceRange.medium,
        '\$\$\$' => PriceRange.high,
        '\$\$\$\$' => PriceRange.luxury,
        _ => PriceRange.low,
      };
}

enum RestaurantVerificationStatus {
  pending,
  verified,
  rejected;

  String get wire => name;

  static RestaurantVerificationStatus fromWire(String value) => switch (value) {
        'verified' => RestaurantVerificationStatus.verified,
        'rejected' => RestaurantVerificationStatus.rejected,
        _ => RestaurantVerificationStatus.pending,
      };
}

/// One dish on a Restaurant's menu — see the Menu Highlights storage
/// decision in
/// docs/audits/restaurant-business-profile-2026-09-05.md: a linked table
/// (`restaurant_menu_items`, one row per dish) rather than a JSON column
/// on `restaurants`, so per-dish photos and a future "search by dish"
/// feature both stay possible without a schema rewrite.
class RestaurantMenuItem {
  final String id;
  final String restaurantId;
  final String dishName;
  final int priceAmount;
  final String currency;
  final String? photoUrl;
  final int displayOrder;

  const RestaurantMenuItem({
    required this.id,
    required this.restaurantId,
    required this.dishName,
    required this.priceAmount,
    this.currency = 'VND',
    this.photoUrl,
    this.displayOrder = 0,
  });

  factory RestaurantMenuItem.fromJson(Map<String, dynamic> json) =>
      RestaurantMenuItem(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        dishName: json['dish_name'] as String? ?? '',
        priceAmount: (json['price_amount'] as num?)?.toInt() ?? 0,
        currency: json['currency'] as String? ?? 'VND',
        photoUrl: json['photo_url'] as String?,
        displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toInsert(String restaurantId) => {
        'restaurant_id': restaurantId,
        'dish_name': dishName,
        'price_amount': priceAmount,
        'currency': currency,
        if (photoUrl != null) 'photo_url': photoUrl,
        'display_order': displayOrder,
      };
}

/// A business-owned Restaurant listing — the second of 8 business profile
/// types, built by directly reusing Attraction's proven pattern (Gem
/// linking, verification via RLS + trigger + RPC, soft-delete via
/// deleted_at + a retraction RPC — see
/// docs/audits/restaurant-business-profile-2026-09-05.md for what was
/// deliberately reused vs. what's genuinely different here).
///
/// [category] is always `'food'` — unlike Attraction, there's no taxonomy
/// mismatch to resolve here. [cuisineType] is a separate multi-select tag,
/// not the category. [reservationOption] is informational only ("Reservations
/// accepted" / "Walk-ins only") — never a booking action, since no real
/// reservation backend exists (same reasoning Tour deferred "Check
/// availability" for). There is deliberately no rating/review field — this
/// app has no reviews mechanism anywhere yet (Gems, Tour, and Attraction
/// all leave it out for the same reason).
class Restaurant {
  final String id;
  final String ownerId;
  final String? gemId;

  final String name;
  final String category;
  final List<String> cuisineType;
  final PriceRange priceRange;
  final List<String> gallery;

  final String address;
  final double latitude;
  final double longitude;
  final String phone;
  final String openingHours;

  final List<String> dietaryOptions;
  final bool reservationOption;

  final String? businessLicenseUrl;

  final RestaurantVerificationStatus verificationStatus;
  final String? verifiedBy;
  final DateTime? verifiedAt;

  /// Soft-delete marker — same convention as Attraction.deletedAt (see
  /// that model's own doc comment). Applied here from the start rather
  /// than retrofitted, since the Attraction deleted_at audit's findings
  /// are already known going into this phase.
  final DateTime? deletedAt;

  final DateTime createdAt;

  const Restaurant({
    required this.id,
    required this.ownerId,
    this.gemId,
    required this.name,
    this.category = 'food',
    this.cuisineType = const [],
    required this.priceRange,
    this.gallery = const [],
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.phone,
    required this.openingHours,
    this.dietaryOptions = const [],
    this.reservationOption = false,
    this.businessLicenseUrl,
    this.verificationStatus = RestaurantVerificationStatus.pending,
    this.verifiedBy,
    this.verifiedAt,
    this.deletedAt,
    required this.createdAt,
  });

  bool get isRetracted => deletedAt != null;
  String? get coverPhoto => gallery.isNotEmpty ? gallery.first : null;

  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        gemId: json['gem_id'] as String?,
        name: json['name'] as String? ?? 'Unnamed restaurant',
        category: json['category'] as String? ?? 'food',
        cuisineType: ((json['cuisine_type'] as List?) ?? const []).cast<String>(),
        priceRange: PriceRange.fromWire(json['price_range'] as String? ?? '\$'),
        gallery: ((json['gallery'] as List?) ?? const []).cast<String>(),
        address: json['address'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        phone: json['phone'] as String? ?? '',
        openingHours: json['opening_hours'] as String? ?? '',
        dietaryOptions:
            ((json['dietary_options'] as List?) ?? const []).cast<String>(),
        reservationOption: json['reservation_option'] as bool? ?? false,
        businessLicenseUrl: json['business_license_url'] as String?,
        verificationStatus: RestaurantVerificationStatus.fromWire(
            json['verification_status'] as String? ?? 'pending'),
        verifiedBy: json['verified_by'] as String?,
        verifiedAt: json['verified_at'] != null
            ? DateTime.tryParse(json['verified_at'] as String)
            : null,
        deletedAt: json['deleted_at'] != null
            ? DateTime.tryParse(json['deleted_at'] as String)
            : null,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toInsert() => {
        'owner_id': ownerId,
        if (gemId != null) 'gem_id': gemId,
        'name': name,
        'cuisine_type': cuisineType,
        'price_range': priceRange.wire,
        'gallery': gallery,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'phone': phone,
        'opening_hours': openingHours,
        'dietary_options': dietaryOptions,
        'reservation_option': reservationOption,
        if (businessLicenseUrl != null) 'business_license_url': businessLicenseUrl,
      };
}
