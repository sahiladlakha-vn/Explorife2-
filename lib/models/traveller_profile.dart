enum Gender {
  male,
  female,
  other,
  preferNotToSay;

  String get wire => switch (this) {
        Gender.male => 'male',
        Gender.female => 'female',
        Gender.other => 'other',
        Gender.preferNotToSay => 'prefer_not_to_say',
      };

  static Gender? fromWire(String? value) => switch (value) {
        'male' => Gender.male,
        'female' => Gender.female,
        'other' => Gender.other,
        'prefer_not_to_say' => Gender.preferNotToSay,
        _ => null,
      };
}

/// Reflects the real, currently-supported OAuth providers only (Google,
/// GitHub) — NOT the source schema's Email/Google/Facebook/Apple list.
/// This app has no email/password sign-in and no Facebook/Apple OAuth
/// today (confirmed against AuthProvider — only signInWithGoogle/
/// signInWithGitHub exist); a field listing methods with no working
/// sign-in behind them would be exactly the "looks like it works" trap
/// this app's own conventions (2FA, payment tokenization) already avoid
/// elsewhere. Revisit this list if/when a new provider is actually wired
/// up in AuthProvider.
enum LoginMethod {
  google,
  github;

  String get wire => name;

  static LoginMethod? fromWire(String? value) => switch (value) {
        'google' => LoginMethod.google,
        'github' => LoginMethod.github,
        _ => null,
      };

  /// Derives the method from Supabase's own `auth.users.app_metadata.provider`
  /// string (same field AuthProvider already reads as `AuthUser.provider`) —
  /// never hand-picked by the user, since it just records how they actually
  /// signed in.
  static LoginMethod? fromAuthProvider(String? provider) => fromWire(provider);
}

enum TravelStyle {
  solo,
  couple,
  family,
  group,
  business;

  String get wire => name;

  static TravelStyle? fromWire(String? value) => switch (value) {
        'solo' => TravelStyle.solo,
        'couple' => TravelStyle.couple,
        'family' => TravelStyle.family,
        'group' => TravelStyle.group,
        'business' => TravelStyle.business,
        _ => null,
      };
}

enum BudgetRange {
  low('\$'),
  medium('\$\$'),
  high('\$\$\$'),
  luxury('\$\$\$\$');

  final String wire;
  const BudgetRange(this.wire);

  static BudgetRange? fromWire(String? value) =>
      BudgetRange.values.where((b) => b.wire == value).firstOrNull;
}

enum VerificationStatus {
  unverified,
  emailVerified,
  idVerified;

  String get wire => switch (this) {
        VerificationStatus.unverified => 'unverified',
        VerificationStatus.emailVerified => 'email_verified',
        VerificationStatus.idVerified => 'id_verified',
      };

  static VerificationStatus fromWire(String? value) => switch (value) {
        'email_verified' => VerificationStatus.emailVerified,
        'id_verified' => VerificationStatus.idVerified,
        _ => VerificationStatus.unverified,
      };
}

enum TravellerAccountStatus {
  active,
  suspended,
  deactivated;

  String get wire => name;

  static TravellerAccountStatus fromWire(String? value) => switch (value) {
        'suspended' => TravellerAccountStatus.suspended,
        'deactivated' => TravellerAccountStatus.deactivated,
        _ => TravellerAccountStatus.active,
      };
}

/// The 7 fixed interest tags the source schema's Interests multi-select
/// defines — validated against this list at the app layer (no DB check
/// constraint on array elements), same convention as Tour's
/// guideLanguages/highlights.
enum TravelInterest {
  adventure,
  culture,
  food,
  nature,
  nightlife,
  relaxation,
  shopping;

  String get wire => name;

  static TravelInterest? fromWire(String value) =>
      TravelInterest.values.where((i) => i.wire == value).firstOrNull;
}

/// Backs `public.traveller_profiles`. See that migration's doc comment for
/// which schema fields were deliberately omitted this phase (loyaltyPoints,
/// paymentMethods) and which are computed rather than stored
/// (bookingsHistory, reviewsWritten, wishlist — see
/// TravellerProfileRepository).
class TravellerProfile {
  final String userId;
  final DateTime? dateOfBirth;
  final Gender? gender;
  final String? nationality;

  final String? phone;
  final LoginMethod? loginMethod;
  final String? preferredLanguage;
  final TravellerAccountStatus accountStatus;

  final List<TravelInterest> interests;
  final TravelStyle? travelStyle;
  final BudgetRange? budgetRange;
  final String? homeLocation;

  final VerificationStatus verificationStatus;
  final String? emergencyContact;

  const TravellerProfile({
    required this.userId,
    this.dateOfBirth,
    this.gender,
    this.nationality,
    this.phone,
    this.loginMethod,
    this.preferredLanguage,
    this.accountStatus = TravellerAccountStatus.active,
    this.interests = const [],
    this.travelStyle,
    this.budgetRange,
    this.homeLocation,
    this.verificationStatus = VerificationStatus.unverified,
    this.emergencyContact,
  });

  factory TravellerProfile.fromJson(Map<String, dynamic> json) => TravellerProfile(
        userId: json['user_id'] as String,
        dateOfBirth: json['date_of_birth'] != null
            ? DateTime.tryParse(json['date_of_birth'] as String)
            : null,
        gender: Gender.fromWire(json['gender'] as String?),
        nationality: json['nationality'] as String?,
        phone: json['phone'] as String?,
        loginMethod: LoginMethod.fromWire(json['login_method'] as String?),
        preferredLanguage: json['preferred_language'] as String?,
        accountStatus: TravellerAccountStatus.fromWire(json['account_status'] as String?),
        interests: ((json['interests'] as List?) ?? const [])
            .map((e) => TravelInterest.fromWire(e as String))
            .whereType<TravelInterest>()
            .toList(),
        travelStyle: TravelStyle.fromWire(json['travel_style'] as String?),
        budgetRange: BudgetRange.fromWire(json['budget_range'] as String?),
        homeLocation: json['home_location'] as String?,
        verificationStatus:
            VerificationStatus.fromWire(json['verification_status'] as String?),
        emergencyContact: json['emergency_contact'] as String?,
      );

  Map<String, dynamic> toUpsert() => {
        'user_id': userId,
        if (dateOfBirth != null)
          'date_of_birth': dateOfBirth!.toIso8601String().split('T').first,
        if (gender != null) 'gender': gender!.wire,
        if (nationality != null) 'nationality': nationality,
        if (phone != null) 'phone': phone,
        if (loginMethod != null) 'login_method': loginMethod!.wire,
        if (preferredLanguage != null) 'preferred_language': preferredLanguage,
        'account_status': accountStatus.wire,
        'interests': interests.map((i) => i.wire).toList(),
        if (travelStyle != null) 'travel_style': travelStyle!.wire,
        if (budgetRange != null) 'budget_range': budgetRange!.wire,
        if (homeLocation != null) 'home_location': homeLocation,
        'verification_status': verificationStatus.wire,
        if (emergencyContact != null) 'emergency_contact': emergencyContact,
      };
}
