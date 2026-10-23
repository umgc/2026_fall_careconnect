import 'package:care_connect_app/features/usps/domain/models/mail_piece.dart';
import 'package:care_connect_app/features/usps/domain/models/package_item.dart';

class USPSDigest {
  final String? digestDateIso;
  final List<MailPiece> mailpieces;
  final List<PackageItem> packages;
  const USPSDigest(
      {this.digestDateIso, required this.mailpieces, required this.packages});
}
