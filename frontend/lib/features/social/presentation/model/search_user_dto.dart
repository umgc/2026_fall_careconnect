class SearchUserDto {
  final int id;
  final String name;
  final String email;

  SearchUserDto({
    required this.id,
    required this.name,
    required this.email,
  });

  factory SearchUserDto.fromJson(Map<String, dynamic> json) {
    return SearchUserDto(
      id: json['id'],
      name: json['name'],
      email: json['email'],
    );
  }
}
