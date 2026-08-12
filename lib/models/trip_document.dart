// A travel document (passport/visa/ticket/reservation/insurance) attached to
// a trip, optionally scoped to one traveler. Backs `public.trip_documents`.
// Plain Dart, no codegen — mirrors the TripBooking/TripStop convention.

/// The five document kinds. Wire values match the `type` CHECK constraint
/// exactly; each enum [name] already equals its DB value, so [wire] just
/// returns it (same shape as `BookingType`).
enum DocumentType {
  passport,
  visa,
  ticket,
  reservation,
  insurance;

  String get wire => name;

  static DocumentType fromWire(String? v) => DocumentType.values.firstWhere(
        (t) => t.name == v,
        // Deliberate silent fallback, same reasoning as BookingType.fromWire:
        // the CHECK constraint guarantees the domain today, so this only
        // fires on a genuinely unknown value from a future migration.
        orElse: () => DocumentType.reservation,
      );
}

class TripDocument {
  final String id;
  final String tripId;

  /// References `trip_collaborators.id`. Null = shared (belongs to the whole
  /// trip, not one traveler — e.g. a group reservation). DB FK is ON DELETE
  /// SET NULL: removing a traveler must not delete the document.
  final String? ownerCollaboratorId;

  final DocumentType type;
  final String title;
  final String? fileUrl;

  /// Date only (no time-of-day) — matches the `date` column type.
  final DateTime? expiresOn;

  final DateTime createdAt;

  const TripDocument({
    required this.id,
    required this.tripId,
    this.ownerCollaboratorId,
    required this.type,
    required this.title,
    this.fileUrl,
    this.expiresOn,
    required this.createdAt,
  });

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);

  static DateTime? _parseTs(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  factory TripDocument.fromJson(Map<String, dynamic> j) => TripDocument(
        id: j['id'] as String,
        tripId: j['trip_id'] as String,
        ownerCollaboratorId: j['owner_collaborator_id'] as String?,
        type: DocumentType.fromWire(j['type'] as String?),
        title: j['title'] as String,
        fileUrl: j['file_url'] as String?,
        expiresOn: _parseDate(j['expires_on']),
        createdAt: _parseTs(j['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_id': tripId,
        'owner_collaborator_id': ownerCollaboratorId,
        'type': type.wire,
        'title': title,
        'file_url': fileUrl,
        'expires_on': expiresOn?.toIso8601String().substring(0, 10),
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  // Sentinel so copyWith can distinguish "not provided" from "set to null"
  // for the three genuinely-clearable fields — same convention as
  // TripStop.copyWith. ownerCollaboratorId: reassign a document to "shared".
  // fileUrl: remove an attached file. expiresOn: a document that never had
  // (or no longer has) a known expiry.
  static const Object _unset = Object();

  TripDocument copyWith({
    Object? ownerCollaboratorId = _unset,
    DocumentType? type,
    String? title,
    Object? fileUrl = _unset,
    Object? expiresOn = _unset,
  }) =>
      TripDocument(
        id: id,
        tripId: tripId,
        ownerCollaboratorId: identical(ownerCollaboratorId, _unset)
            ? this.ownerCollaboratorId
            : ownerCollaboratorId as String?,
        type: type ?? this.type,
        title: title ?? this.title,
        fileUrl: identical(fileUrl, _unset) ? this.fileUrl : fileUrl as String?,
        expiresOn:
            identical(expiresOn, _unset) ? this.expiresOn : expiresOn as DateTime?,
        createdAt: createdAt,
      );
}
