import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';

import '../../domain/models/action_links.dart';
import '../../domain/models/mail_piece.dart';
import '../../domain/models/package_item.dart';
import '../../domain/models/usps_digest.dart';

class GmailRaw {
  final String html;
  final Map<String, String> cidMap; // cid → data URL
  final DateTime? receivedAtUtc;

  GmailRaw(this.html, this.cidMap, this.receivedAtUtc);
}

class GmailParser {
  static final _trackingRegex = RegExp(r'(\d{10,})');
  static final _fromRegex = RegExp(r'from[:\s]+(.+)', caseSensitive: false);
  static final _expectedRegex =
      RegExp(r'Expected Delivery(?: Day)?:\s*(.+)', caseSensitive: false);
  static final _digestHeadingRegex =
      RegExp(r'Daily Digest(?: for)?\s*(.*)', caseSensitive: false);
  static final _friendlyFormats = <DateFormat>[
    DateFormat("EEEE, MMMM d, yyyy", 'en_US'),
    DateFormat("MMMM d, yyyy", 'en_US'),
    DateFormat("M/d/yyyy", 'en_US'),
  ];

  USPSDigest toDomain(GmailRaw raw) {
    final doc = html_parser.parse(raw.html);
    _inlineCidImages(doc, raw.cidMap);

    final digestDate = _resolveDigestDate(doc, raw.receivedAtUtc);
    final packages = _extractPackages(doc, digestDate);
    final mailPieces = _extractMailPieces(doc, raw, digestDate);

    return USPSDigest(
      digestDateIso: digestDate?.toIso8601String(),
      mailpieces: mailPieces,
      packages: packages,
    );
  }

  void _inlineCidImages(Document doc, Map<String, String> cidMap) {
    if (cidMap.isEmpty) return;
    final lookup = <String, String>{};
    for (final entry in cidMap.entries) {
      lookup[_normalizeCid(entry.key)] = entry.value;
    }
    for (final img in doc.querySelectorAll('img[src^="cid:"]')) {
      final src = img.attributes['src'] ?? '';
      final cidKey = _normalizeCid(src.substring(src.indexOf(':') + 1));
      final dataUrl = lookup[cidKey];
      if (dataUrl != null) {
        img.attributes['src'] = dataUrl;
      }
    }
  }

  String _normalizeCid(String raw) =>
      raw.replaceAll('<', '').replaceAll('>', '').trim().toLowerCase();

  DateTime? _resolveDigestDate(Document doc, DateTime? fallback) {
    String? candidate;
    final timeNode = doc.querySelector('time[datetime]');
    if (timeNode != null) {
      candidate =
          _firstNonEmpty([timeNode.attributes['datetime'], timeNode.text]);
    }
    candidate ??= doc.querySelector('meta[name="date"]')?.attributes['content'];
    candidate ??= _extractDigestHeading(doc);

    final parsed = _parseDate(candidate);
    return parsed ?? fallback;
  }

  String? _extractDigestHeading(Document doc) {
    final heading = doc.querySelector('*:matchesOwn("Daily Digest")');
    if (heading == null) return null;
    final match = _digestHeadingRegex.firstMatch(heading.text);
    if (match == null) return null;
    final tail = match.group(1)?.trim();
    return (tail != null && tail.isNotEmpty) ? tail : null;
  }

  List<PackageItem> _extractPackages(Document doc, DateTime? digestDate) {
    final items = <PackageItem>[];
    final seen = <String>{};

    void addFromElement(Element element) {
      final tracking = _firstNonEmpty([
        element.querySelector('.tracking-number')?.text.trim(),
        _extractTrackingNumber(element.text),
      ]);
      if (tracking == null || !seen.add(tracking)) return;

      final expected = _parseDate(_extractExpectedText(element)) ?? digestDate;
      final trackUrl = element
          .querySelector('a[href*="TrackConfirmAction"]')
          ?.attributes['href'];
      final sender = _extractSenderFromElement(element);

      items.add(PackageItem(
        trackingNumber: tracking,
        sender: sender,
        expectedDateIso: expected?.toIso8601String(),
        actions:
            ActionLinks(track: trackUrl, redelivery: null, dashboard: null),
      ));
    }

    for (final el in doc.querySelectorAll(
        '.package, [data-package], article:has(.tracking-number)')) {
      addFromElement(el);
    }

    if (items.isEmpty) {
      for (final el
          in doc.querySelectorAll('*:matchesOwn("Tracking Number")')) {
        addFromElement(el);
      }
    }

    return items;
  }

  String? _extractExpectedText(Element? element) {
    if (element == null) return null;
    final label = element.querySelector('*:matchesOwn("Expected Delivery")');
    final text = label?.text ?? element.text;
    final match = _expectedRegex.firstMatch(text);
    return match?.group(1)?.trim();
  }

  List<MailPiece> _extractMailPieces(
      Document doc, GmailRaw raw, DateTime? digestDate) {
    final pieces = <MailPiece>[];
    var counter = 1;

    for (final block in doc.querySelectorAll(
        '#mailpieces .mailpiece, [data-mailpiece-id], .mailpiece')) {
      final piece = _mailPieceFromBlock(block, raw, digestDate, counter++);
      if (piece != null) pieces.add(piece);
    }

    if (pieces.isEmpty) {
      var idx = 1;
      for (final img
          in doc.querySelectorAll('#mailpieces img, img[alt*="mailpiece"]')) {
        final piece = _mailPieceFromImage(img, raw, digestDate, idx++);
        if (piece != null) pieces.add(piece);
      }
    }

    return pieces;
  }

  MailPiece? _mailPieceFromBlock(
      Element block, GmailRaw raw, DateTime? digestDate, int counter) {
    final img = block.querySelector('img');
    if (img == null) return null;

    final src = img.attributes['src'];
    if (src == null || src.trim().isEmpty) return null;

    final id = block.attributes['data-mailpiece-id'] ?? 'mailpiece-$counter';
    final sender = _firstNonEmpty([
      block.querySelector('.sender')?.text.trim(),
      _deriveSenderFromAlt(img.attributes['alt']),
      _senderFromContext(block),
    ]);
    final summary = _firstNonEmpty([
      block.querySelector('.summary')?.text.trim(),
      _deriveSummaryFromAlt(img.attributes['alt']),
    ]);

    final received = raw.receivedAtUtc ?? digestDate;

    return MailPiece(
      id: id,
      sender: sender,
      summary: summary,
      imageDataUrl: src,
      dateIso: received?.toIso8601String(),
      actions:
          const ActionLinks(track: null, redelivery: null, dashboard: null),
    );
  }

  MailPiece? _mailPieceFromImage(
      Element img, GmailRaw raw, DateTime? digestDate, int counter) {
    final src = img.attributes['src'];
    if (src == null || src.trim().isEmpty) return null;

    final received = raw.receivedAtUtc ?? digestDate;

    return MailPiece(
      id: 'mailpiece-$counter',
      sender: _deriveSenderFromAlt(img.attributes['alt']),
      summary: _deriveSummaryFromAlt(img.attributes['alt']),
      imageDataUrl: src,
      dateIso: received?.toIso8601String(),
      actions:
          const ActionLinks(track: null, redelivery: null, dashboard: null),
    );
  }

  String? _deriveSenderFromAlt(String? alt) {
    if (alt == null || alt.trim().isEmpty) return null;
    final match = _fromRegex.firstMatch(alt);
    return _sanitizeSender(match?.group(1));
  }

  String? _deriveSummaryFromAlt(String? alt) {
    if (alt == null || alt.trim().isEmpty) return null;
    return alt.replaceFirst(RegExp(r'(?i)image of\s*'), '').trim();
  }

  String? _senderFromContext(Element block) {
    final label = block.querySelector('strong:matchesOwn("from")');
    if (label == null) return null;
    return _sanitizeSender(label.text.replaceFirst(RegExp(r'(?i)from\s*'), ''));
  }

  String? _extractTrackingNumber(String text) {
    final match = _trackingRegex.firstMatch(text);
    return match?.group(1);
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    try {
      return DateTime.parse(trimmed).toUtc();
    } catch (_) {
      for (final format in _friendlyFormats) {
        try {
          return format.parse(trimmed, true).toUtc();
        } catch (_) {
          continue;
        }
      }
      try {
        return DateFormat("EEE, dd MMM yyyy HH:mm:ss xx", 'en_US')
            .parse(trimmed, true)
            .toUtc();
      } catch (_) {
        return null;
      }
    }
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _extractSenderFromElement(Element element) {
    final direct = _extractSenderFromText(element.text);
    if (direct != null) return direct;

    for (final child in element.querySelectorAll('*')) {
      final candidate = _extractSenderFromText(child.text);
      if (candidate != null) return candidate;
    }

    var sibling = element.previousElementSibling;
    var hops = 0;
    while (sibling != null && hops++ < 3) {
      final candidate = _extractSenderFromText(sibling.text);
      if (candidate != null) return candidate;
      sibling = sibling.previousElementSibling;
    }

    return null;
  }

  String? _extractSenderFromText(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = _fromRegex.firstMatch(text);
    return match == null ? null : _sanitizeSender(match.group(1));
  }

  String? _sanitizeSender(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceAll(RegExp(r'(?i)tracking number.*'), '')
        .replaceAll(RegExp(r'(?i)expected delivery.*'), '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
