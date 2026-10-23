import 'package:care_connect_app/features/usps/domain/repositories/usps_digest_repository.dart';
import '../domain/models/usps_digest.dart';
import 'providers/gmail_service.dart';
import 'parsers/gmail_parser.dart';

class UspsDigestRepositoryImpl implements UspsDigestRepository {
  final GmailService gmail;

  final GmailParser gParser;

  UspsDigestRepositoryImpl({required this.gmail, required this.gParser});

  @override
  Future<USPSDigest?> fromGmail() async {
    final raw = await gmail.fetchRaw(); // html + cid map + date
    return raw == null ? null : gParser.toDomain(raw);
  }

  @override
  Future<USPSDigest?> latestDigest() async =>
      (await fromGmail()) ?? (await fromGmail());
}
