class Story {
  final String id;
  final String title;
  final String? excerpt;
  final String? content;
  final String? storyContent;
  final String? imageUrl;
  final String? coverImage;
  final String? location;
  final String? authorName;
  final String? email;
  final String status;
  final bool featured;
  final String? adventureType;
  final List<String> tags;
  final String? difficulty;
  final int? lonelinessLevel;
  final String? safetyLevel;
  final String? connectivity;
  final String? aftermath;
  final DateTime createdAt;

  const Story({
    required this.id,
    required this.title,
    this.excerpt,
    this.content,
    this.storyContent,
    this.imageUrl,
    this.coverImage,
    this.location,
    this.authorName,
    this.email,
    required this.status,
    required this.featured,
    this.adventureType,
    this.tags = const [],
    this.difficulty,
    this.lonelinessLevel,
    this.safetyLevel,
    this.connectivity,
    this.aftermath,
    required this.createdAt,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    List<String> parseTags(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    return Story(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      excerpt: json['excerpt'] as String?,
      content: json['content'] as String?,
      storyContent: json['story_content'] as String?,
      imageUrl: json['image_url'] as String?,
      coverImage: json['cover_image'] as String?,
      location: json['location'] as String?,
      authorName: json['author_name'] as String?,
      email: json['email'] as String?,
      status: json['status'] as String? ?? 'pending',
      featured: json['featured'] as bool? ?? false,
      adventureType: json['adventure_type'] as String?,
      tags: parseTags(json['tags']),
      difficulty: json['difficulty'] as String?,
      lonelinessLevel: json['loneliness_level'] as int?,
      safetyLevel: json['safety_level'] as String?,
      connectivity: json['connectivity'] as String?,
      aftermath: json['aftermath'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  String get displayAuthor => authorName?.isNotEmpty == true ? authorName! : 'Anonymous Explorer';
  String get photo => imageUrl ?? coverImage ?? '';
  bool get hasPhoto => photo.isNotEmpty;
  String get body => storyContent ?? content ?? '';

  static const List<String> adventureTypes = [
    'Solo Adventure', 'Trail Running', 'Road Trip', 'Backpacking',
    'Camping', 'Climbing', 'Cycling', 'Other',
  ];

  static const Map<String, String> typeEmoji = {
    'Solo Adventure': '🧗',
    'Trail Running': '🏃',
    'Road Trip': '🚗',
    'Backpacking': '🎒',
    'Camping': '⛺',
    'Climbing': '⛰️',
    'Cycling': '🚴',
    'Other': '🌍',
  };

  String get typeEmoji_ => typeEmoji[adventureType] ?? '📖';
}
