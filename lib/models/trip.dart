import 'trip_vibe.dart';

/// A planned trip. Backs `public.trips`. Plain Dart, no codegen — mirrors the
/// [Gem]/[TripStop] convention.
///
/// Money is always whole VND ([budgetVnd]); the app is single-currency for now
/// ([currency] defaults to 'VND' and is treated as identity, not state).
class Trip {
  final String id;
  final String ownerId;
  final String name;
  final String location;
  final DateTime startDate;
  final DateTime endDate;
  final int budgetVnd;
  final String currency;
  final TripVibe? vibe;
  final String? templateId;
  final DateTime createdAt;

  const Trip({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.location,
    required this.startDate,
    required this.endDate,
    required this.budgetVnd,
    this.currency = 'VND',
    this.vibe,
    this.templateId,
    required this.createdAt,
  });

  /// Number of nights. Jul 12 → Jul 18 == 6. Intentionally not clamped when
  /// endDate < startDate — that's form validation, not a model concern.
  int get nights => endDate.difference(startDate).inDays;

  /// Whole days from now until the trip starts (negative once it has begun).
  int get daysUntilStart => startDate.difference(DateTime.now()).inDays;

  /// The predicate `TripProvider.activeTrip` uses: starts within the next 30 days.
  bool get isUpcoming => daysUntilStart >= 0 && daysUntilStart <= 30;

  /// Falls back to "<location> escape" so blueprint-seeded trips that were
  /// never renamed don't surface an empty title in the UI.
  String get displayName => name.isNotEmpty ? name : '$location escape';

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        ownerId: j['owner_id'] as String,
        name: j['name'] as String,
        location: j['location'] as String,
        startDate: DateTime.parse(j['start_date'] as String),
        endDate: DateTime.parse(j['end_date'] as String),
        budgetVnd: (j['budget_vnd'] as num).toInt(),
        currency: (j['currency'] as String?) ?? 'VND',
        vibe: TripVibe.fromKey(j['vibe'] as String?),
        templateId: j['template_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  // start/end are date-only columns → first 10 chars of the ISO string;
  // created_at is timestamptz → full ISO. DateTime.parse reads both back.
  Map<String, dynamic> toJson() => {
        'id': id,
        'owner_id': ownerId,
        'name': name,
        'location': location,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate.toIso8601String().substring(0, 10),
        'budget_vnd': budgetVnd,
        'currency': currency,
        'vibe': vibe?.key,
        'template_id': templateId,
        'created_at': createdAt.toIso8601String(),
      };

  /// Mutable fields only. id/ownerId/currency/createdAt are identity, not state:
  /// migrating those is a service-level operation, never a copyWith.
  Trip copyWith({
    String? name,
    String? location,
    DateTime? startDate,
    DateTime? endDate,
    int? budgetVnd,
    TripVibe? vibe,
    String? templateId,
  }) =>
      Trip(
        id: id,
        ownerId: ownerId,
        name: name ?? this.name,
        location: location ?? this.location,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        budgetVnd: budgetVnd ?? this.budgetVnd,
        currency: currency,
        vibe: vibe ?? this.vibe,
        templateId: templateId ?? this.templateId,
        createdAt: createdAt,
      );

  // ---- Display formatters ----
  // Single implementation, many consumers (header chip/pill, setup sheet, cards).
  // These live on the model so the "how do we render money/dates" answer is in
  // exactly one place. Neither prepends the ₫ glyph — callers own the currency
  // affordance so they can style it (two-tone, muted suffix, etc.).

  static const List<String> _mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Compact human date span. Collapses shared month/year:
  ///   same month → 'Jul 12 – 18'
  ///   cross month → 'Jul 28 – Aug 3'
  ///   cross year  → 'Dec 28, 2026 – Jan 3, 2027'
  /// Nights are the caller's job (they vary per surface), so they're not baked in.
  static String formatDateRange(DateTime start, DateTime end) {
    final sM = _mon[start.month - 1], eM = _mon[end.month - 1];
    if (start.year != end.year) {
      return '$sM ${start.day}, ${start.year} – $eM ${end.day}, ${end.year}';
    }
    if (start.month != end.month) {
      return '$sM ${start.day} – $eM ${end.day}';
    }
    return '$sM ${start.day} – ${end.day}';
  }

  /// Whole-VND formatter. [short] yields '1.2M' / '50K' for tight chips/pills;
  /// the default long form groups thousands ('1,200,000'). Never includes ₫.
  static String formatVnd(int n, {bool short = false}) {
    if (short) {
      if (n.abs() >= 1000000) {
        final m = n / 1000000;
        return m.truncateToDouble() == m
            ? '${m.toStringAsFixed(0)}M'
            : '${m.toStringAsFixed(1)}M';
      }
      if (n.abs() >= 1000) {
        final k = n / 1000;
        return k.truncateToDouble() == k
            ? '${k.toStringAsFixed(0)}K'
            : '${k.toStringAsFixed(1)}K';
      }
      return n.toString();
    }
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$b';
  }
}
