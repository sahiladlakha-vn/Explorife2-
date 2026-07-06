/// The payload a discovery [AssetCard] carries while being dragged onto the
/// itinerary. Deliberately minimal: the trip stop persists only [gemId], and
/// budget bucketing derives category via TripProvider.gemCategoryLookup at read
/// time — so category is NOT stashed here (that would be a second, driftable
/// source). [displayName] rides along purely so a drop preview can label itself
/// without a lookup round-trip mid-drag. Gems are free, so [defaultPriceVnd] is
/// 0 today; the user sets price at drop via the itinerary's inline price pill.
///
/// Lives in its own file so the canvas's `DragTarget<AssetData>` can import the
/// payload type without pulling in the whole discovery panel (avoids a cycle).
class AssetData {
  const AssetData({
    required this.gemId,
    required this.displayName,
    this.defaultPriceVnd = 0,
  });

  final String gemId;
  final String displayName;
  final int defaultPriceVnd;
}
