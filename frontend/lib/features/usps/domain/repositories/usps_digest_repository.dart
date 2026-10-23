import '../models/usps_digest.dart';

abstract class UspsDigestRepository {
  Future<USPSDigest?> latestDigest(); // chooses best source & merge
  Future<USPSDigest?> fromGmail();
}
