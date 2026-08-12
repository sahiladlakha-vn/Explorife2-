// A traveler on a trip, for the Trip segment's Travelers card. Unlike
// TripDocument/PackingItem, this doesn't mirror one table row — it's a join
// of public.trip_collaborators against public.profiles for the display name.
// The owner has a real trip_collaborators row too (TripProvider.createTrip
// inserts one; the backfill migration 20260806000400 did the same for
// pre-existing trips), labeled Organizer rather than Member — see
// TripSetupProvider.loadSetup for the one edge case where that row is
// missing and a fallback gets synthesized instead. Read-only: no
// fromJson/toJson/copyWith — this is a view model assembled by
// TripSetupProvider.loadSetup, not a table it writes back to.

enum TravelerRole { organizer, member }

/// Wire values match trip_collaborators' `status` CHECK constraint
/// ('confirmed', 'invited').
enum TravelerStatus {
  confirmed,
  invited;

  static TravelerStatus fromWire(String? v) =>
      v == 'invited' ? TravelerStatus.invited : TravelerStatus.confirmed;
}

class TripTraveler {
  /// trip_collaborators.id — real for both roles in the common case (see
  /// class doc). Only falls back to the owner's raw user id for a trip
  /// missing its owner row; in that one case this can't be used as an
  /// assignee/document-owner FK target, only as a widget key.
  final String id;

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final TravelerRole role;
  final TravelerStatus status;

  const TripTraveler({
    required this.id,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    required this.status,
  });
}
