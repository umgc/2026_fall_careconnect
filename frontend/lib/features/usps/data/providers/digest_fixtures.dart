import 'dart:typed_data';
import 'package:care_connect_app/features/usps/domain/models/digest_raw.dart';

DigestRaw buildSimpleDigest({
  String? title,
  DateTime? receivedAt,
  int imageCount = 1,
}) {
  final t = title ?? 'Your USPS Informed Delivery Daily Digest';
  final imgs = List<String>.generate(imageCount, (i) => 'piece${i + 1}');
  final imgTags =
      imgs.map((id) => '<img src="cid:$id" alt="$id" />').join('\n');

  final html = '''
<!doctype html>
<html>
  <body>
    <h1>$t</h1>
    <p>Here are today's mail pieces:</p>
    $imgTags
  </body>
</html>
''';

  final cids = <String, List<int>>{
    for (final id in imgs) id: Uint8List.fromList([0, 1, 2, 3, 4, 5]).toList(),
  };

  return DigestRaw(
    html: html,
    cids: cids,
    receivedAt: receivedAt ?? DateTime.now(),
  );
}
