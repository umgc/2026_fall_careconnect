/// A topic identified independently of its display title.
class HelpCategory {
  const HelpCategory({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;
}
