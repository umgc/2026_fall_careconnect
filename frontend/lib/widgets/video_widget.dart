import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class VideoWidget extends StatefulWidget {
  ///TODO: Figure out what a key is in this context and add it.
  const VideoWidget({super.key});
  @override
  State<VideoWidget> createState() => VideoWidgetState();
}

class VideoWidgetState extends State<VideoWidget> {
  CameraController? controller;
  Future<void>? controllerFuture;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // Get available cameras
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return;
      }

      // Initialize the camera controller
      controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
      );

      controllerFuture = controller!.initialize();
      setState(() {});
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || controllerFuture == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return FutureBuilder<void>(
      future: controllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return AspectRatio(
            aspectRatio: controller!.value.aspectRatio,
            child: CameraPreview(controller!),
          );
        } else {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
      },
    );
  }
}
