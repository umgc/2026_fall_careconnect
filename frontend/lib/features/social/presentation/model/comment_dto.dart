class CommentDto {
  final int id;
  final int userId;
  final int postId;
  final String content;
  final String username;
  final DateTime timestamp;

  CommentDto({
    required this.id,
    required this.userId,
    required this.postId,
    required this.content,
    required this.username,
    required this.timestamp,
  });

  factory CommentDto.fromJson(Map<String, dynamic> json) {
    print('DEBUG — Raw comment JSON: $json');

    return CommentDto(
      id: json['id'],
      userId: json['userId'],
      postId: json['postId'],
      content: json['content'],
      username: json['username'] ?? 'Unknown User',
      timestamp: DateTime.parse(json['createdAt']),
    );
  }
}
