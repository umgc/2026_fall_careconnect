import 'dart:convert';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

class UploadAvatarScreen extends StatefulWidget {
  const UploadAvatarScreen({super.key});

  @override
  State<UploadAvatarScreen> createState() => _UploadAvatarScreenState();
}

class _UploadAvatarScreenState extends State<UploadAvatarScreen> {
  File? _selectedAvatar;
  bool isUploading = false;
  String?
      uploadedAvatarUrl; // this stores the relative path like `/uploads/avatar.png`

  Future<void> pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedAvatar = File(result.files.single.path!);
      });
    }
  }

  Future<void> uploadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    if (userId == null || _selectedAvatar == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Missing user ID or image')));
      return;
    }

    setState(() => isUploading = true);

    final uri = Uri.parse('${getBackendBaseUrl()}/v1/api/auth/avatar/$userId');

    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath('avatar', _selectedAvatar!.path),
    );

    final response = await request.send();

    setState(() => isUploading = false);

    if (response.statusCode == 200) {
      final responseBody = await http.Response.fromStream(response);
      if (responseBody.statusCode == 200) {
        final data = jsonDecode(responseBody.body);
        final serverPath =
            data['imageUrl']; // This should be '/uploads/filename.jpg'

        setState(() => uploadedAvatarUrl = serverPath);
        await prefs.setString('profileImageUrl', serverPath);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar uploaded successfully!')),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar uploaded successfully!')),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to upload avatar')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedImageUrl = uploadedAvatarUrl != null
        ? '${getBackendBaseUrl()}$uploadedAvatarUrl'
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Avatar'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (_selectedAvatar != null) ...[
              Image.file(_selectedAvatar!, height: 150),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => setState(() {
                  _selectedAvatar = null;
                  uploadedAvatarUrl = null;
                }),
                child: const Text('Remove Image'),
              ),
            ],
            ElevatedButton.icon(
              onPressed: pickAvatar,
              icon: const Icon(Icons.image),
              label: const Text('Pick Avatar'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isUploading ? null : uploadAvatar,
              child: isUploading
                  ? const CircularProgressIndicator()
                  : const Text('Upload'),
            ),
            const SizedBox(height: 20),
            if (resolvedImageUrl != null)
              Column(
                children: [
                  const Text('Preview:'),
                  const SizedBox(height: 10),
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: NetworkImage(resolvedImageUrl),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
