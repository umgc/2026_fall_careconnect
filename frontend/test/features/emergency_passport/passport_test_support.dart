// Shared test data for the CC-12 scan tests: a passport with every section
// shared, and a WCAG 2.1 contrast check (SC 1.4.3) for the scan page.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const fullPassport = {
  'name': 'Jordan Miller',
  'age': 41,
  'bloodType': 'O_POSITIVE',
  'allergies': [
    {'allergen': 'Penicillin', 'severity': 'LIFE_THREATENING', 'reaction': 'Anaphylaxis'},
    {'allergen': 'Peanuts', 'severity': 'MODERATE', 'reaction': 'Hives, swelling'},
    {'allergen': 'Latex', 'severity': null, 'reaction': null},
  ],
  'medications': [
    {'name': 'Lisinopril', 'dosage': '10 mg', 'frequency': 'Once daily'},
  ],
  'chronicConditions': 'Type 2 diabetes',
  'emergencyContact': {
    'name': 'Taylor Miller',
    'relationship': 'Spouse',
    'phone': '(415) 555-0184',
  },
  'lastUpdated': '2026-10-13T15:00:00Z',
};

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrastRatio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The colour behind [e]: every filled ColoredBox, DecoratedBox and Material
/// between it and the root, composited from the outside in over white. The
/// scan page paints its header with `Container(color:)`, which builds a
/// ColoredBox, so that counts here too.
Color backgroundOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is ColoredBox) {
      layers.add(w.color);
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      final c = (w.decoration as BoxDecoration).color;
      if (c != null) layers.add(c);
    } else if (w is Material &&
        w.color != null &&
        w.type != MaterialType.transparency) {
      layers.add(w.color!);
    }
    return true;
  });
  var bg = Colors.white;
  for (final c in layers.reversed) {
    bg = Color.alphaBlend(c, bg);
  }
  return bg;
}

String _hex(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

/// Every Text on screen whose colour is below 4.5:1 against what is behind
/// it, as '"text": ratio (fg on bg)'.
List<String> lowContrastText(WidgetTester t) {
  final failures = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final text = w.data ?? w.textSpan?.toPlainText() ?? '';
    final fg = DefaultTextStyle.of(e).style.merge(w.style).color;
    if (fg == null || text.trim().isEmpty) continue;
    final bg = backgroundOf(e);
    final shown = Color.alphaBlend(fg, bg);
    final r = contrastRatio(shown, bg);
    if (r < 4.5) {
      failures.add('"${text.trim()}": ${r.toStringAsFixed(2)} '
          '(${_hex(shown)} on ${_hex(bg)})');
    }
  }
  return failures;
}

/// The signed-in patient's own passport, as GET /v1/api/passport returns it.
const passportJson = {
  'name': 'Mary Johnson',
  'age': 68,
  'bloodType': 'O_POSITIVE',
  'allergies': [
    {'allergen': 'Penicillin', 'severity': 'MODERATE', 'reaction': 'Rash'},
  ],
  'medications': [],
  'sharing': {
    'ALLERGIES': true,
    'MEDICATIONS': false,
    'CHRONIC_CONDITIONS': false,
    'BLOOD_TYPE': true,
    'EMERGENCY_CONTACT': false,
  },
  'token': {
    'active': true,
    'createdAt': '2026-10-15T17:11:34.932728Z',
    'lastScannedAt': null,
  },
  'ready': true,
  'lastUpdated': '2026-10-15T17:11:12Z',
  'lastUpdatedBySection': {},
};
