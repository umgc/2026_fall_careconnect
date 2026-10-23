import 'package:care_connect_app/features/usps/data/parsers/gmail_parser.dart';

abstract class GmailService {
  /// Returns the latest USPS Informed Delivery email as raw HTML, CID map, and received time.
  /// Returns null if nothing found.
  Future<GmailRaw?> fetchRaw();
}
