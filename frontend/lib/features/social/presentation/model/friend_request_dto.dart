class FriendRequestDto {
  final int id;
  final int fromUserId;
  final int toUserId;
  final String fromUsername;

  FriendRequestDto({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.fromUsername,
  });

  factory FriendRequestDto.fromJson(Map<String, dynamic> json) {
    return FriendRequestDto(
      id: json['id'],
      fromUserId: json['fromUserId'],
      toUserId: json['toUserId'],
      fromUsername:
          json['from_username'], // or json['fromUsername'] based on backend
    );
  }
}
