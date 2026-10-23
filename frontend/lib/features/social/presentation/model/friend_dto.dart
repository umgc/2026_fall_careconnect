class FriendDto {
  final int id;
  final String name;
  final String email;

  FriendDto({
    required this.id,
    required this.name,
    required this.email,
  });

  factory FriendDto.fromJson(Map<String, dynamic> json) {
    return FriendDto(
      id: json['id'],
      name: json['name'],
      email: json['email'],
    );
  }
}
