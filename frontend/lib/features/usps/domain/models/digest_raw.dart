class DigestRaw {
  final String html; // full HTML of the email
  final Map<String, List<int>> cids; // content-id -> bytes for inline images
  final DateTime receivedAt;

  const DigestRaw({
    required this.html,
    required this.cids,
    required this.receivedAt,
  });
}
