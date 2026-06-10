class AppUser {
  final String id;
  final String name;
  final String email;
  final String avatarUrl;
  final String bio;
  final int tripsCount;
  final int savedCount;
  final List<String> visitedDestinationIds;
  final List<String> savedDestinationIds;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.bio,
    required this.tripsCount,
    required this.savedCount,
    required this.visitedDestinationIds,
    required this.savedDestinationIds,
  });
}
