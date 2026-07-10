/// A single pre-trip checklist item. Backs `public.trip_checklist_items`.
/// Plain Dart, no codegen — mirrors the [Trip]/[TripStop] convention.
///
/// Sections are a small fixed set (mirrored in the DB check constraint); the
/// human labels and render order live here so the Summary screen has one source
/// of truth for "how do we group and order checklist items".
class TripChecklistItem {
  final String id;
  final String tripId;
  final String section;
  final String title;
  final bool isChecked;
  final int sortOrder;

  /// Days before departure this item is due (0 = departure day). Null when the
  /// item isn't date-anchored (miscellaneous). Reserved for the countdown
  /// surface; not rendered in v1.
  final int? dueDateOffsetDays;
  final DateTime createdAt;

  /// Server-owned: set by the `moddatetime` trigger on every UPDATE, null until
  /// the row is first updated. The client never writes this — it reads the
  /// trigger's value back rather than predicting a timestamp locally.
  final DateTime? updatedAt;

  const TripChecklistItem({
    required this.id,
    required this.tripId,
    required this.section,
    required this.title,
    required this.isChecked,
    required this.sortOrder,
    this.dueDateOffsetDays,
    required this.createdAt,
    this.updatedAt,
  });

  // Section keys — must match the DB check constraint verbatim.
  static const String section7dBefore = '7d_before';
  static const String section1dBefore = '1d_before';
  static const String sectionDepartureDay = 'departure_day';
  static const String sectionMiscellaneous = 'miscellaneous';

  /// Render order for sections. `TripProvider.checklistFor` sorts by this index,
  /// then by [sortOrder] within a section.
  static const List<String> sectionOrder = [
    section7dBefore,
    section1dBefore,
    sectionDepartureDay,
    sectionMiscellaneous,
  ];

  /// Human heading for a section key. Falls back to the raw key so an unknown
  /// value (e.g. from a future migration) renders something rather than crashing.
  static String sectionLabel(String section) {
    switch (section) {
      case section7dBefore:
        return '7 days before';
      case section1dBefore:
        return '1 day before';
      case sectionDepartureDay:
        return 'Departure day';
      case sectionMiscellaneous:
        return 'Miscellaneous';
      default:
        return section;
    }
  }

  factory TripChecklistItem.fromJson(Map<String, dynamic> j) =>
      TripChecklistItem(
        id: j['id'] as String,
        tripId: j['trip_id'] as String,
        section: j['section'] as String,
        title: j['title'] as String,
        isChecked: j['is_checked'] as bool? ?? false,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        dueDateOffsetDays: (j['due_date_offset_days'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: j['updated_at'] != null
            ? DateTime.parse(j['updated_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_id': tripId,
        'section': section,
        'title': title,
        'is_checked': isChecked,
        'sort_order': sortOrder,
        'due_date_offset_days': dueDateOffsetDays,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  /// Mutable fields only. id/tripId/section/createdAt are identity, not state.
  TripChecklistItem copyWith({bool? isChecked, int? sortOrder, String? title}) =>
      TripChecklistItem(
        id: id,
        tripId: tripId,
        section: section,
        title: title ?? this.title,
        isChecked: isChecked ?? this.isChecked,
        sortOrder: sortOrder ?? this.sortOrder,
        dueDateOffsetDays: dueDateOffsetDays,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
