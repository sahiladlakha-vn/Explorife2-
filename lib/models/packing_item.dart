// One packing-list item on a trip, optionally assigned to a traveler.
// Backs `public.trip_packing_items`. Plain Dart, no codegen — mirrors the
// TripBooking/TripStop convention.

class PackingItem {
  final String id;
  final String tripId;

  /// References `trip_collaborators.id`. Null = unassigned/shared (e.g. a
  /// group item like "first aid kit"). DB FK is ON DELETE SET NULL: removing
  /// a traveler must not delete the item, just unassign it.
  final String? assigneeCollaboratorId;

  final String label;
  final String? category;
  final int quantity;
  final bool isPacked;
  final int sortOrder;
  final DateTime createdAt;

  const PackingItem({
    required this.id,
    required this.tripId,
    this.assigneeCollaboratorId,
    required this.label,
    this.category,
    this.quantity = 1,
    this.isPacked = false,
    this.sortOrder = 0,
    required this.createdAt,
  });

  static DateTime? _parseTs(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  factory PackingItem.fromJson(Map<String, dynamic> j) => PackingItem(
        id: j['id'] as String,
        tripId: j['trip_id'] as String,
        assigneeCollaboratorId: j['assignee_collaborator_id'] as String?,
        label: j['label'] as String,
        category: j['category'] as String?,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        isPacked: j['is_packed'] as bool? ?? false,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: _parseTs(j['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_id': tripId,
        'assignee_collaborator_id': assigneeCollaboratorId,
        'label': label,
        'category': category,
        'quantity': quantity,
        'is_packed': isPacked,
        'sort_order': sortOrder,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  // Sentinel so copyWith can distinguish "not provided" from "set to null"
  // for the two clearable fields — same convention as TripStop.copyWith.
  // assigneeCollaboratorId: unassign back to shared. category: clear a
  // miscategorized item back to uncategorized.
  static const Object _unset = Object();

  PackingItem copyWith({
    Object? assigneeCollaboratorId = _unset,
    String? label,
    Object? category = _unset,
    int? quantity,
    bool? isPacked,
    int? sortOrder,
  }) =>
      PackingItem(
        id: id,
        tripId: tripId,
        assigneeCollaboratorId: identical(assigneeCollaboratorId, _unset)
            ? this.assigneeCollaboratorId
            : assigneeCollaboratorId as String?,
        label: label ?? this.label,
        category:
            identical(category, _unset) ? this.category : category as String?,
        quantity: quantity ?? this.quantity,
        isPacked: isPacked ?? this.isPacked,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );
}
