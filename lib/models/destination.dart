class Destination {
  final String id;
  final String name;
  final String country;
  final String description;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final double rating;
  final int reviewCount;
  final String category;
  final List<String> tags;
  final double pricePerNight;
  bool isSaved;

  Destination({
    required this.id,
    required this.name,
    required this.country,
    required this.description,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.reviewCount,
    required this.category,
    required this.tags,
    required this.pricePerNight,
    this.isSaved = false,
  });

  String get location => '$name, $country';
}

class Review {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final double rating;
  final String comment;
  final DateTime date;

  const Review({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.rating,
    required this.comment,
    required this.date,
  });
}
