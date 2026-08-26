// A reservation logged against a trip — flight, stay, activity or transport,
// optionally pinned to the stopId it covers. Backs `public.trip_bookings`.
// Plain Dart, no codegen — mirrors the TripStop/Trip convention.
//
// MONEY CONTRACT — amountVnd is deliberately nullable:
//   • null → amount UNKNOWN (a not-yet-priced 'to_book' item). Render as "TBD".
//   • 0    → a genuinely FREE booking. A real value, counted in spend/pace.
// Never collapse null to 0 (`?? 0`): pace/actual math must EXCLUDE null and
// COUNT 0. Branch on hasKnownAmount instead of coalescing.

/// The four booking kinds. Wire values match the `booking_type` CHECK
/// constraint exactly ('flight','stay','activity','transport'); each enum
/// [name] already equals its DB value, so [wire] just returns it.
enum BookingType {
  flight,
  stay,
  activity,
  transport;

  String get wire => name;

  static BookingType fromWire(String? v) => BookingType.values.firstWhere(
        (t) => t.name == v,
        // Deliberate silent fallback: today the CHECK constraint guarantees the
        // domain, so this only fires on a genuinely unknown value. If a future
        // migration adds a type (e.g. 'train'), OLD app builds will mislabel it
        // as activity rather than throwing — an accepted trade-off for a
        // consumer app. Revisit here when the type set grows.
        orElse: () => BookingType.activity,
      );
}

/// Reservation progress. Wire values match the `status` CHECK constraint
/// exactly ('to_book','booked','paid'). Note `toBook ↔ 'to_book'` — the enum
/// name is camelCase and does NOT equal the snake_case wire value, so this
/// enum needs an explicit map (unlike [BookingType]).
enum BookingStatus {
  toBook,
  booked,
  paid;

  String get wire => switch (this) {
        BookingStatus.toBook => 'to_book',
        BookingStatus.booked => 'booked',
        BookingStatus.paid => 'paid',
      };

  static BookingStatus fromWire(String? v) => switch (v) {
        'booked' => BookingStatus.booked,
        'paid' => BookingStatus.paid,
        // Defaults to toBook — matches the column default 'to_book'.
        _ => BookingStatus.toBook,
      };
}

class TripBooking {
  final String id;
  final String tripId;

  /// References `trip_stops.id` when this booking covers a specific stop; null
  /// for trip-level bookings (e.g. a return flight). DB FK is ON DELETE SET NULL.
  final String? stopId;

  final BookingType bookingType;
  final String title;
  final String? confirmationRef;
  final String? provider;
  final DateTime? startAt;
  final DateTime? endAt;

  /// See the MONEY CONTRACT on the class doc: null = TBD, 0 = free.
  final int? amountVnd;

  final BookingStatus status;
  final String? createdBy;
  final DateTime createdAt;

  const TripBooking({
    required this.id,
    required this.tripId,
    this.stopId,
    required this.bookingType,
    required this.title,
    this.confirmationRef,
    this.provider,
    this.startAt,
    this.endAt,
    this.amountVnd,
    this.status = BookingStatus.toBook,
    this.createdBy,
    required this.createdAt,
  });

  /// True when [amountVnd] is a real figure (including 0 for free). False = TBD.
  /// Use this to guard spend/pace math and the "TBD" UI branch.
  bool get hasKnownAmount => amountVnd != null;

  static DateTime? _parseTs(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  factory TripBooking.fromJson(Map<String, dynamic> j) => TripBooking(
        id: j['id'] as String,
        tripId: j['trip_id'] as String,
        stopId: j['stop_id'] as String?,
        bookingType: BookingType.fromWire(j['booking_type'] as String?),
        title: j['title'] as String,
        confirmationRef: j['confirmation_ref'] as String?,
        provider: j['provider'] as String?,
        startAt: _parseTs(j['start_at']),
        endAt: _parseTs(j['end_at']),
        amountVnd: (j['amount_vnd'] as num?)?.toInt(),
        status: BookingStatus.fromWire(j['status'] as String?),
        createdBy: j['created_by'] as String?,
        createdAt: _parseTs(j['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_id': tripId,
        'stop_id': stopId,
        'booking_type': bookingType.wire,
        'title': title,
        'confirmation_ref': confirmationRef,
        'provider': provider,
        'start_at': startAt?.toUtc().toIso8601String(),
        'end_at': endAt?.toUtc().toIso8601String(),
        'amount_vnd': amountVnd,
        'status': status.wire,
        'created_by': createdBy,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  // Sentinel so copyWith can distinguish "not provided" from "set to null" —
  // needed for every nullable field here (stopId, confirmationRef, provider,
  // startAt, endAt, amountVnd), since each has a meaningful cleared-to-null
  // state (unpin from a stop, clear a confirmation number, etc.) that a plain
  // `param ?? this.field` can't express. Omitting an arg preserves the current
  // value; passing `field: null` explicitly clears it.
  static const Object _unset = Object();

  TripBooking copyWith({
    Object? stopId = _unset,
    BookingType? bookingType,
    String? title,
    Object? confirmationRef = _unset,
    Object? provider = _unset,
    Object? startAt = _unset,
    Object? endAt = _unset,
    Object? amountVnd = _unset,
    BookingStatus? status,
  }) =>
      TripBooking(
        id: id,
        tripId: tripId,
        stopId: identical(stopId, _unset) ? this.stopId : stopId as String?,
        bookingType: bookingType ?? this.bookingType,
        title: title ?? this.title,
        confirmationRef: identical(confirmationRef, _unset)
            ? this.confirmationRef
            : confirmationRef as String?,
        provider:
            identical(provider, _unset) ? this.provider : provider as String?,
        startAt:
            identical(startAt, _unset) ? this.startAt : startAt as DateTime?,
        endAt: identical(endAt, _unset) ? this.endAt : endAt as DateTime?,
        amountVnd:
            identical(amountVnd, _unset) ? this.amountVnd : amountVnd as int?,
        status: status ?? this.status,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
