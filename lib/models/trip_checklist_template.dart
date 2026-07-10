import 'trip_checklist_item.dart';

/// One templated checklist row, resolved into an insert payload by
/// `TripProvider.seedChecklistForTrip`.
///
/// [sortOrder] is 1-based within each section on purpose: the DB trigger
/// `set_trip_checklist_sort_order` only auto-assigns when `sort_order = 0`, so
/// seeded rows carrying an explicit 1..n are left untouched and keep template
/// order. (A 0-based template would collide — the trigger would rewrite the
/// first row's 0 into a value tying the explicit-1 second row.)
class ChecklistSeed {
  final String section;
  final String title;
  final int sortOrder;
  final int? dueDateOffsetDays;
  const ChecklistSeed(
    this.section,
    this.title,
    this.sortOrder, {
    this.dueDateOffsetDays,
  });
}

/// Place-name fragments that mean "home country → no passport/visa/forex items".
/// Matched by substring against the trip location, lowercased.
///
/// Deliberately a whitelist, NOT `location.contains('vietnam')`: real domestic
/// trips are named by city ("Hanoi", "Hoi An") and never contain the word
/// "vietnam", so a country-name check would misroute every domestic trip to the
/// international template. Bare 'hue' is omitted on purpose — it substring-
/// matches 'Huelva' (Spain), and misrouting an international trip to the
/// domestic template would hide passport/visa items (the more dangerous
/// direction to get wrong).
/// TODO(home-locale): make the home country configurable instead of hardcoding VN.
const Set<String> _domesticPlaces = {
  'vietnam', 'hanoi', 'ha noi', 'ho chi minh', 'saigon', 'da nang', 'danang',
  'hoi an', 'nha trang', 'da lat', 'dalat', 'sapa', 'sa pa', 'ha long',
  'halong', 'phu quoc', 'can tho', 'ninh binh', 'phong nha', 'mui ne',
  'con dao',
};

/// True when [location] names a place inside the home country (Vietnam for now).
bool isDomestic(String location) {
  final l = location.toLowerCase();
  return _domesticPlaces.any(l.contains);
}

/// The checklist template for a trip location. Domestic and international differ
/// mainly in the 7-days-before section (passport / visa / insurance / forex).
List<ChecklistSeed> checklistTemplateFor(String location) =>
    isDomestic(location) ? _domestic : _international;

const List<ChecklistSeed> _domestic = [
  ChecklistSeed(TripChecklistItem.section7dBefore,
      'Confirm accommodation booking', 1, dueDateOffsetDays: 7),
  ChecklistSeed(TripChecklistItem.section7dBefore, 'Check weather forecast', 2,
      dueDateOffsetDays: 7),
  ChecklistSeed(TripChecklistItem.section7dBefore,
      'Arrange transport to destination', 3, dueDateOffsetDays: 7),
  ChecklistSeed(TripChecklistItem.section1dBefore, 'Pack essentials', 1,
      dueDateOffsetDays: 1),
  ChecklistSeed(TripChecklistItem.section1dBefore,
      'Charge devices and power bank', 2, dueDateOffsetDays: 1),
  ChecklistSeed(TripChecklistItem.section1dBefore, 'Download offline maps', 3,
      dueDateOffsetDays: 1),
  ChecklistSeed(TripChecklistItem.sectionDepartureDay,
      "Check ID / driver's license", 1, dueDateOffsetDays: 0),
  ChecklistSeed(TripChecklistItem.sectionDepartureDay, 'Confirm departure time',
      2, dueDateOffsetDays: 0),
  ChecklistSeed(TripChecklistItem.sectionMiscellaneous,
      'Notify someone of your itinerary', 1),
];

const List<ChecklistSeed> _international = [
  ChecklistSeed(TripChecklistItem.section7dBefore,
      'Check passport validity (6+ months)', 1, dueDateOffsetDays: 7),
  ChecklistSeed(TripChecklistItem.section7dBefore,
      'Confirm visa / entry requirements', 2, dueDateOffsetDays: 7),
  ChecklistSeed(TripChecklistItem.section7dBefore, 'Buy travel insurance', 3,
      dueDateOffsetDays: 7),
  ChecklistSeed(TripChecklistItem.section7dBefore,
      'Exchange currency / notify bank', 4, dueDateOffsetDays: 7),
  ChecklistSeed(TripChecklistItem.section1dBefore, 'Pack essentials and adapters',
      1, dueDateOffsetDays: 1),
  ChecklistSeed(TripChecklistItem.section1dBefore,
      'Print / save boarding passes', 2, dueDateOffsetDays: 1),
  ChecklistSeed(TripChecklistItem.section1dBefore,
      'Set up international roaming / eSIM', 3, dueDateOffsetDays: 1),
  ChecklistSeed(TripChecklistItem.sectionDepartureDay,
      'Bring passport and visa documents', 1, dueDateOffsetDays: 0),
  ChecklistSeed(TripChecklistItem.sectionDepartureDay,
      'Arrive at airport 3 hours early', 2, dueDateOffsetDays: 0),
  ChecklistSeed(TripChecklistItem.sectionMiscellaneous,
      'Share itinerary and copies of documents', 1),
];
