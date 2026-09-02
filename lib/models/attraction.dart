/// Free or paid entry — mirrors Tour's own money contract (amount is
/// genuinely absent for 'free', never a stand-in zero).
enum EntryFeeType {
  free,
  paid;

  String get wire => name;

  static EntryFeeType fromWire(String value) =>
      value == 'paid' ? EntryFeeType.paid : EntryFeeType.free;
}

enum AttractionVerificationStatus {
  pending,
  verified,
  rejected;

  String get wire => name;

  static AttractionVerificationStatus fromWire(String value) => switch (value) {
        'verified' => AttractionVerificationStatus.verified,
        'rejected' => AttractionVerificationStatus.rejected,
        _ => AttractionVerificationStatus.pending,
      };
}

/// A business-owned Attraction listing — the first of 8 business profile
/// types. See docs/audits/attraction-business-profile-2026-09-04.md for the
/// full written decision on its relationship to [Gem] and its category
/// taxonomy; summary:
///
/// - [gemId] is an OPTIONAL link to an existing curated Gem for the same
///   physical place (matched by name+proximity at creation — see
///   attraction_form_screen.dart's `findLikelyGemMatch` — confirmed by an
///   Admin during verification). A Gem's own curated content is never
///   replaced/merged when linked; Gem Detail surfaces this listing as an
///   ADDITIONAL section, not a takeover. Null means a genuinely new place
///   with no prior curated entry.
/// - [category] reuses Gem's own 10-value taxonomy exactly (NOT the source
///   schema's Museum/Park/Historical Site/Adventure Activity/Theme Park
///   list) — one shared taxonomy across Gem and Attraction was judged more
///   important than schema literalism, since a linked pair would otherwise
///   carry two different category values for the same place.
class Attraction {
  final String id;
  final String ownerId;
  final String? gemId;

  final String name;
  final String category;
  final List<String> gallery;

  final String address;
  final double latitude;
  final double longitude;
  final String openingHours;

  final EntryFeeType entryFeeType;
  final int? entryFeeAmount;
  final String currency;

  final String description;
  final List<String> certificationUrls;
  final String? recommendedDuration;

  final AttractionVerificationStatus verificationStatus;
  final String? verifiedBy;
  final DateTime? verifiedAt;

  /// Soft-delete marker — see
  /// supabase/migrations/20260904000100_add_attraction_soft_delete.sql for
  /// why this is a timestamp rather than a hard DELETE: the owner (any
  /// time) or an admin-tier account (moderation power) can retract a
  /// listing via the `retract_attraction` RPC, which sets this instead of
  /// removing the row — a retracted listing stops showing in the public
  /// feed but stays visible to its owner/admins, and keeps a real row
  /// admin_action_log can reference.
  final DateTime? deletedAt;

  final DateTime createdAt;

  const Attraction({
    required this.id,
    required this.ownerId,
    this.gemId,
    required this.name,
    required this.category,
    this.gallery = const [],
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.openingHours,
    required this.entryFeeType,
    this.entryFeeAmount,
    this.currency = 'VND',
    required this.description,
    this.certificationUrls = const [],
    this.recommendedDuration,
    this.verificationStatus = AttractionVerificationStatus.pending,
    this.verifiedBy,
    this.verifiedAt,
    this.deletedAt,
    required this.createdAt,
  });

  bool get isFree => entryFeeType == EntryFeeType.free;
  bool get isRetracted => deletedAt != null;
  String? get coverPhoto => gallery.isNotEmpty ? gallery.first : null;

  factory Attraction.fromJson(Map<String, dynamic> json) => Attraction(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        gemId: json['gem_id'] as String?,
        name: json['name'] as String? ?? 'Unnamed attraction',
        category: json['category'] as String? ?? '',
        gallery: ((json['gallery'] as List?) ?? const []).cast<String>(),
        address: json['address'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        openingHours: json['opening_hours'] as String? ?? '',
        entryFeeType: EntryFeeType.fromWire(json['entry_fee_type'] as String? ?? 'free'),
        entryFeeAmount: (json['entry_fee_amount'] as num?)?.toInt(),
        currency: json['currency'] as String? ?? 'VND',
        description: json['description'] as String? ?? '',
        certificationUrls:
            ((json['certification_urls'] as List?) ?? const []).cast<String>(),
        recommendedDuration: json['recommended_duration'] as String?,
        verificationStatus:
            AttractionVerificationStatus.fromWire(json['verification_status'] as String? ?? 'pending'),
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
        'category': category,
        'gallery': gallery,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'opening_hours': openingHours,
        'entry_fee_type': entryFeeType.wire,
        if (entryFeeAmount != null) 'entry_fee_amount': entryFeeAmount,
        'currency': currency,
        'description': description,
        'certification_urls': certificationUrls,
        if (recommendedDuration != null) 'recommended_duration': recommendedDuration,
      };
}
