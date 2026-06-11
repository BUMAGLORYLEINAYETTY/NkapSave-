class AppNotification {
  final String id;
  final String title;
  final String body;
  final String category;
  final String? deepLink;
  final bool read;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.deepLink,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        category: j['category'] as String? ?? 'general',
        deepLink: j['deep_link'] as String?,
        read: j['read'] as bool? ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
