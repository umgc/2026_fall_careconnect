import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart';

class ReviewPhotosScreen extends StatefulWidget {
  final List<XFile> initialPhotos;
  const ReviewPhotosScreen({super.key, required this.initialPhotos});

  @override
  State<ReviewPhotosScreen> createState() => _ReviewPhotosScreenState();
}

class _ReviewPhotosScreenState extends State<ReviewPhotosScreen> {
  final ImagePicker _picker = ImagePicker();
  late List<XFile> _photos;

  @override
  void initState() {
    super.initState();
    _photos = List<XFile>.from(widget.initialPhotos);
  }

  void _addIfNew(XFile x) {
    if (_photos.any((p) => p.path == x.path && p.path.isNotEmpty)) return;
    if (mounted) {
      setState(() => _photos.add(x));
    }
  }

  Future<void> _addFromCamera() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 92,
    );
    if (x == null) return;
    _addIfNew(x);
  }

  Future<void> _addFromGallery() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf'],
      type: FileType.custom,
      withData: kIsWeb,
    );
    if (picked == null) return;

    for (final f in picked.files) {
      if (kIsWeb) {
        if (f.bytes != null) {
          _addIfNew(XFile.fromData(f.bytes!, name: f.name));
        }
      } else {
        if (f.path != null) {
          _addIfNew(XFile(f.path!));
        }
      }
    }
  }

  void _removeAt(int index) {
    setState(() => _photos.removeAt(index));
  }

  void _finish() {
    Navigator.of(context).pop<List<XFile>>(_photos);
  }

  Future<Widget> _buildImageWidget(XFile xfile) async {
    if (kIsWeb) {
      try {
        final Uint8List bytes = await xfile.readAsBytes();
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            );
          },
        );
      } catch (e) {
        return Container(
          color: Colors.grey.shade300,
          child: const Icon(Icons.error, color: Colors.red),
        );
      }
    } else {
      final file = File(xfile.path);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey.shade300,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          );
        },
      );
    }
  }

  Widget _buildPdfWidget(XFile xfile) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700, width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf_rounded,
              color: Colors.red.shade400, size: 50),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              xfile.name,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Files'),
        actions: [
          TextButton(
            onPressed: _photos.isEmpty ? null : _finish,
            child: Text(
              'Done',
              style: TextStyle(
                color: _photos.isEmpty
                    ? cs.onSurface.withOpacity(0.38)
                    : cs.onPrimary,
              ),
            ),
          ),
        ],
      ),
      body: _photos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined, size: 64),
                  const SizedBox(height: 12),
                  const Text('No files yet'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _addFromCamera,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Take photo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('From gallery'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _addFromCamera,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Add'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _addFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                      ),
                      const Spacer(),
                      Text('${_photos.length} selected'),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _photos.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      final file = _photos[index];
                      final isPdf = file.name.toLowerCase().endsWith('.pdf');

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (isPdf) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        _FullScreenPdfViewer(file: file),
                                    fullscreenDialog: true,
                                  ),
                                );
                              } else {
                                // TODO: Add full-screen image preview?
                              }
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: isPdf
                                  ? _buildPdfWidget(file)
                                  : FutureBuilder<Widget>(
                                      future: _buildImageWidget(file),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasData) {
                                          return snapshot.data!;
                                        } else if (snapshot.hasError) {
                                          return Container(
                                            color: Colors.grey.shade300,
                                            child: const Icon(Icons.error,
                                                color: Colors.red),
                                          );
                                        } else {
                                          return Container(
                                            color: Colors.grey.shade300,
                                            child: const Center(
                                                child:
                                                    CircularProgressIndicator()),
                                          );
                                        }
                                      },
                                    ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: InkWell(
                              onTap: () => _removeAt(index),
                              customBorder: const CircleBorder(),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _photos.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _finish,
                    child: Text('Done (${_photos.length})'),
                  ),
                ),
              ),
            ),
      floatingActionButton: _photos.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addFromGallery,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add'),
            ),
    );
  }
}

// --- THIS IS THE MODIFIED WIDGET ---
class _FullScreenPdfViewer extends StatefulWidget {
  final XFile file;
  const _FullScreenPdfViewer({required this.file});

  @override
  State<_FullScreenPdfViewer> createState() => _FullScreenPdfViewerState();
}

// --- Replace the entire _FullScreenPdfViewerState widget with this ---
class _FullScreenPdfViewerState extends State<_FullScreenPdfViewer> {
  // Use PdfControllerPinch instead
  late final PdfControllerPinch pdfControllerPinch;

  @override
  void initState() {
    super.initState();
    // Initialize the controller based on platform
    if (kIsWeb) {
      // On web, read the bytes first, then use openData.
      pdfControllerPinch = PdfControllerPinch(
        // <-- Use PdfControllerPinch
        document: PdfDocument.openData(widget.file.readAsBytes()),
      );
    } else {
      // On mobile, file.path is a file path, so use .openFile
      pdfControllerPinch = PdfControllerPinch(
        // <-- Use PdfControllerPinch
        document: PdfDocument.openFile(widget.file.path),
      );
    }
  }

  // Remember to dispose the controller
  @override
  void dispose() {
    pdfControllerPinch.dispose(); // <-- Dispose the pinch controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
      ),
      // Use the PdfViewPinch widget from the pdfx package
      body: PdfViewPinch(
        // <-- Use PdfViewPinch
        controller: pdfControllerPinch, // <-- Pass the pinch controller
        // Optional: Add builders for loading/error states
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          // <-- Use PdfViewPinchBuilders
          options: const DefaultBuilderOptions(
              // You might experiment with these options for initial fit
              // fitPolicy: FitPolicy.WIDTH,
              ),
          documentLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          pageLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) =>
              Center(child: Text('Error loading PDF: ${error.toString()}')),
        ),
      ),
    );
  }
}
