// Shared helpers for the Health Data tests (PR #263 review).
//
// Medicare envelopes are built from the backend's own fixture bundles
// (backend/core/src/main/resources/fixtures/medicare/), in the shape
// MedicareController returns: { source, mode, synthetic, total, resources }.
// `flutter test` runs with frontend/ as the working directory.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = '../backend/core/src/main/resources/fixtures/medicare';

/// Every resource in a fixture bundle, ungated (the backend gate is not
/// applied, so the frontend's own status filter is exercised too).
List<Map<String, dynamic>> fixtureResources(String bundle) {
  final json = jsonDecode(File('$_fixtures/$bundle').readAsStringSync())
      as Map<String, dynamic>;
  return [
    for (final e in json['entry'] as List)
      (e as Map<String, dynamic>)['resource'] as Map<String, dynamic>,
  ];
}

String envelope(List<Map<String, dynamic>> resources, {bool synthetic = true}) =>
    jsonEncode({
      'source': 'MEDICARE',
      'mode': synthetic ? 'mock' : 'live',
      'synthetic': synthetic,
      'total': resources.length,
      'resources': resources,
    });

/// Dio adapter answering by path suffix. A missing route is a connection
/// error; a route can also return a status code or wait on a completer.
class RouteAdapter implements HttpClientAdapter {
  RouteAdapter(this.routes, {this.status = const {}, this.gate});

  final Map<String, String> routes;
  final Map<String, int> status;
  final Completer<void>? gate;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    if (gate != null) await gate!.future;
    for (final e in status.entries) {
      if (options.path.endsWith(e.key)) {
        return ResponseBody.fromString('{"error":"medicare_unavailable"}', e.value,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
      }
    }
    for (final e in routes.entries) {
      if (options.path.endsWith(e.key)) {
        return ResponseBody.fromString(e.value, 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
      }
    }
    throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'no route for ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

// ---- WCAG 2.1 contrast (SC 1.4.3) ----

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrastRatio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The colour actually behind [e]: every coloured DecoratedBox / Material
/// between it and the root, composited from the outside in over white.
Color backgroundOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is DecoratedBox && w.decoration is BoxDecoration) {
      final c = (w.decoration as BoxDecoration).color;
      if (c != null) layers.add(c);
    } else if (w is Material && w.color != null && w.type != MaterialType.transparency) {
      layers.add(w.color!);
    } else if (w is RawChip) {
      // A chip paints its fill itself (no DecoratedBox/Material in the tree),
      // so read the colour it was given for its current state.
      final c = w.selected ? w.selectedColor : w.backgroundColor;
      if (c != null) layers.add(c);
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

/// Every text run under [scope] whose contrast against its rendered
/// background is below 4.5:1, as "text: ratio (fg on bg)".
List<String> lowContrastText(WidgetTester t, Finder scope) {
  final failures = <String>[];
  void check(Element e, String text, Color? fg) {
    if (fg == null || text.trim().isEmpty) return;
    final bg = backgroundOf(e);
    final shown = Color.alphaBlend(fg, bg);
    final r = contrastRatio(shown, bg);
    if (r < 4.5) {
      failures.add('"${text.trim()}": ${r.toStringAsFixed(2)} '
          '(${_hex(shown)} on ${_hex(bg)})');
    }
  }

  for (final e in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final w = e.widget as Text;
    final style = DefaultTextStyle.of(e).style.merge(w.style);
    check(e, w.data ?? w.textSpan?.toPlainText() ?? '', style.color);
  }
  for (final e
      in find.descendant(of: scope, matching: find.byType(RichText)).evaluate()) {
    // Text widgets build a RichText too, and an Icon draws its glyph with
    // one (non-text, SC 1.4.11): only check RichTexts written directly.
    var skip = false;
    var depth = 0;
    e.visitAncestorElements((a) {
      if (a.widget is Text || a.widget is Icon) skip = true;
      return !skip && ++depth < 6;
    });
    if (skip) continue;
    final root = (e.widget as RichText).text;
    root.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        final color = span.style?.color ?? root.style?.color;
        check(e, span.text!, color);
      }
      return true;
    });
  }
  return failures;
}
