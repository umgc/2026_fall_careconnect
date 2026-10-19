import 'dart:io';
import 'package:care_connect_app/features/invoices/services/ocr_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class OcrReviewScreen extends StatefulWidget {
  final List<XFile> images;

  const OcrReviewScreen({super.key, required this.images});

  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  late List<XFile> _images;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, OcrRichResult> _richByPath = {};
  bool _busy = true;
  String? _error;
  bool _showBoxes = true;

  @override
  void initState() {
    super.initState();
    _images = List<XFile>.from(widget.images);
    _runOcr();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _runOcr() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final results = await OcrService.analyzeImages(_images);
      _richByPath
        ..clear()
        ..addEntries(results.map((r) => MapEntry(r.path, r)));

      for (final img in _images) {
        final path = img.path;
        final text = _richByPath[path]?.text ?? '';
        _controllers[path]?.dispose();
        _controllers[path] = TextEditingController(text: text);
      }

      setState(() => _busy = false);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'OCR failed. Tap Retry.';
      });
    }
  }

  Future<void> _rerunSingle(int index) async {
    final img = _images[index];
    setState(() => _busy = true);
    try {
      final r = await OcrService.analyzeImages([img]);
      if (r.isNotEmpty) {
        _richByPath[img.path] = r.first;
        _controllers[img.path]?.dispose();
        _controllers[img.path] = TextEditingController(text: r.first.text);
      }
    } catch (_) {
      // leave as-is on error
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _removeAt(int index) {
    final path = _images[index].path;
    _controllers[path]?.dispose();
    _controllers.remove(path);
    _richByPath.remove(path);
    setState(() => _images.removeAt(index));
  }

  void _finish() {
    final payload = <Map<String, String>>[];
    for (final img in _images) {
      final text = _controllers[img.path]?.text ?? '';
      payload.add({'path': img.path, 'text': text});
    }
    Navigator.of(context).pop<List<Map<String, String>>>(payload);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & OCR'),
        actions: [
          IconButton(
            tooltip: _showBoxes ? 'Hide boxes' : 'Show boxes',
            onPressed: _busy || _images.isEmpty
                ? null
                : () => setState(() => _showBoxes = !_showBoxes),
            icon: Icon(
                _showBoxes ? Icons.crop_square : Icons.crop_square_outlined),
          ),
          TextButton(
            onPressed: (_busy || _images.isEmpty) ? null : _finish,
            child: Text(
              'Done',
              style: TextStyle(
                color: (_busy || _images.isEmpty)
                    ? cs.onSurface.withOpacity(0.38)
                    : cs.onPrimary,
              ),
            ),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? const Center(child: Text('No images'))
              : Column(
                  children: [
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: cs.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: cs.onErrorContainer),
                              ),
                            ),
                            TextButton(
                              onPressed: _runOcr,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _images.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, i) {
                          final img = _images[i];
                          final path = img.path;
                          final controller =
                              _controllers[path] ?? TextEditingController();
                          _controllers[path] = controller;

                          final rich = _richByPath[path];
                          final boxes =
                              rich?.lines.map((e) => e.box).toList() ??
                                  const <BBox>[];
                          final qrs = rich?.qrcodes ?? const <OcrQr>[];

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Stack(
                                    children: [
                                      AspectRatio(
                                        aspectRatio: 4 / 3,
                                        child: Image.file(File(path),
                                            fit: BoxFit.cover),
                                      ),
                                      if (_showBoxes && boxes.isNotEmpty)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                                painter: BoxesPainter(boxes)),
                                          ),
                                        ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Re-run OCR',
                                              onPressed: _busy
                                                  ? null
                                                  : () => _rerunSingle(i),
                                              icon: const Icon(Icons.refresh),
                                            ),
                                            IconButton(
                                              tooltip: 'Remove',
                                              onPressed: _busy
                                                  ? null
                                                  : () => _removeAt(i),
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (qrs.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: qrs
                                          .map(
                                            (q) => InputChip(
                                              label: Text(q.value.isEmpty
                                                  ? '(empty)'
                                                  : q.value),
                                              onPressed: () {
                                                // optionally copy or open URLs here
                                              },
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: controller,
                                    minLines: 3,
                                    maxLines: 12,
                                    decoration: const InputDecoration(
                                      labelText: 'Extracted text',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _busy || _images.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _runOcr,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry OCR'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _finish,
                        child: Text('Done (${_images.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Overlay painter for normalized boxes [0..1] relative to the displayed image.
class BoxesPainter extends CustomPainter {
  final List<BBox> boxes;
  BoxesPainter(this.boxes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final b in boxes) {
      final rect = Rect.fromLTWH(
        b.l * size.width,
        b.t * size.height,
        b.w * size.width,
        b.h * size.height,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant BoxesPainter old) => old.boxes != boxes;
}
