class PostWithCommentCountDto {
  final int id;
  final int userId;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;
  final int commentCount;
  final String username;

  PostWithCommentCountDto({
    required this.id,
    required this.userId,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    required this.commentCount,
    required this.username,
  });

  factory PostWithCommentCountDto.fromJson(Map<String, dynamic> json) {
    return PostWithCommentCountDto(
      id: json['id'],
      userId: json['userId'],
      content: json['content'],
      imageUrl: json['imageUrl'],
      createdAt: DateTime.parse(json['createdAt']),
      commentCount: json['commentCount'],
      username: json['username'] ?? 'Unknown User',
    );
  }
}
