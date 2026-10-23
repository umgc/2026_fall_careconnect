// lib/mock/usps_digest_mock.dart
import 'dart:convert';

/// Builds a USPS Informed Delivery mock response Map that matches your real API.
Map<String, dynamic> buildMockUspsDigestMap({DateTime? now}) {
  final DateTime t = now ?? DateTime.now();

  String svgBanner(String fill, String label) {
    final raw = """
<svg xmlns='http://www.w3.org/2000/svg' width='240' height='160'>
  <rect width='240' height='160' fill='$fill'/>
  <text x='50%' y='50%' dominant-baseline='middle' text-anchor='middle'
        font-family='Arial' font-size='22' fill='#ffffff'>$label</text>
</svg>""";
    final b64 = base64Encode(utf8.encode(raw));
    return 'data:image/svg+xml;base64,$b64';
  }

  return {
    'digestDate': t.toIso8601String(),
    'mailpieces': [
      {
        'id': 'm-1001',
        'sender': 'ACME Bank',
        'summary': 'Monthly statement',
        'imageDataUrl': svgBanner('#6b7280', 'ACME Statement'),
        'dateIso': t.toIso8601String(),
        'actions': {
          'track': null,
          'redelivery': 'https://tools.usps.com/redelivery.htm',
          'dashboard': 'https://informeddelivery.usps.com/',
        },
      },
      {
        'id': 'm-1002',
        'sender': 'Electric Co',
        'summary': 'Bill due notice',
        'imageDataUrl': svgBanner('#2563eb', 'Electric Bill'),
        'dateIso': t.subtract(const Duration(days: 1)).toIso8601String(),
        'actions': {
          'track': null,
          'redelivery': 'https://tools.usps.com/redelivery.htm',
          'dashboard': 'https://informeddelivery.usps.com/',
        },
      },
      {
        'id': 'm-1003',
        'sender': 'City Water',
        'summary': 'Service reminder',
        'imageDataUrl': svgBanner('#16a34a', 'Water Notice'),
        'dateIso': t.subtract(const Duration(days: 2)).toIso8601String(),
        'actions': {
          'track': null,
          'redelivery': 'https://tools.usps.com/redelivery.htm',
          'dashboard': 'https://informeddelivery.usps.com/',
        },
      },
      {
        'id': 'm-1004',
        'sender': 'USA Bank',
        'summary': 'Monthly statement',
        'imageDataUrl': svgBanner('#c41230', 'USA Statement'),
        'dateIso': t.toIso8601String(),
        'actions': {
          'track': null,
          'redelivery': 'https://tools.usps.com/redelivery.htm',
          'dashboard': 'https://informeddelivery.usps.com/',
        },
      },
      {
        'id': 'm-1005',
        'sender': 'City Gas',
        'summary': 'Service reminder',
        'imageDataUrl': svgBanner('#16a34a', 'Gas Notice'),
        'dateIso': t.subtract(const Duration(days: 2)).toIso8601String(),
        'actions': {
          'track': null,
          'redelivery': 'https://tools.usps.com/redelivery.htm',
          'dashboard': 'https://informeddelivery.usps.com/',
        },
      },
    ],
    'packages': [
      {
        'trackingNumber': '9400100000000000000000',
        'expectedDateIso': t.add(const Duration(days: 1)).toIso8601String(),
        'actions': {
          'track':
              'https://tools.usps.com/go/TrackConfirmAction?qtc_tLabels1=9400100000000000000000',
          'redelivery': 'https://tools.usps.com/redelivery.htm',
          'dashboard': 'https://informeddelivery.usps.com/',
        },
      },
    ],
  };
}
