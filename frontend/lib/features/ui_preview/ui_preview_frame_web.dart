// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Full-size iframe hosting the React Care Circle preview.
class UiPreviewFrame extends StatefulWidget {
  const UiPreviewFrame({super.key});

  @override
  State<UiPreviewFrame> createState() => _UiPreviewFrameState();
}

class _UiPreviewFrameState extends State<UiPreviewFrame> {
  static const String _viewType = 'careconnect-ui-preview-iframe';
  static bool _registered = false;

  @override
  void initState() {
    super.initState();
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final iframe = html.IFrameElement()
          ..src = '/ui-preview/index.html'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'clipboard-read; clipboard-write';
        return iframe;
      });
      _registered = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HtmlElementView(viewType: _viewType);
  }
}
