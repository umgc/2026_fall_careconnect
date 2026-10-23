import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../services/enhanced_file_service.dart';
import '../config/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ProfilePictureWidget extends StatefulWidget {
  final double size;
  final bool canEdit;
  final String? existingImageUrl;
  final Function(UserFileDTO)? onImageUpdated;
  final String placeholderText;

  const ProfilePictureWidget({
    super.key,
    this.size = 100,
    this.canEdit = true,
    this.existingImageUrl,
    this.onImageUpdated,
    this.placeholderText = 'Add Photo',
  });

  @override
  State<ProfilePictureWidget> createState() => _ProfilePictureWidgetState();
}

class _ProfilePictureWidgetState extends State<ProfilePictureWidget> {
  UserFileDTO? _profileImage;
  Uint8List? _imageBytes;
  bool _isLoading = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final profileImage = await EnhancedFileService.getProfileImage();
      if (profileImage != null) {
        setState(() {
          _profileImage = profileImage;
        });
        await _loadImageBytes();
      }
    } catch (e) {
      print('Error loading profile image: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadImageBytes() async {
    if (_profileImage != null) {
      try {
        final bytes = await EnhancedFileService.downloadFile(_profileImage!.id);
        if (bytes != null && mounted) {
          setState(() {
            _imageBytes = bytes;
          });
        }
      } catch (e) {
        print('Error loading image bytes: $e');
      }
    }
  }

  Future<void> _uploadProfileImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null) {
      final file = result.files.first;

      // Validate file size (max 5MB)
      if (file.size > 5 * 1024 * 1024) {
        _showErrorSnackBar('Image size must be less than 5MB');
        return;
      }

      setState(() {
        _isUploading = true;
      });

      try {
        File fileToUpload;
        if (kIsWeb) {
          // Handle web file upload
          final bytes = file.bytes!;
          final tempDir = Directory.systemTemp;
          fileToUpload = File('${tempDir.path}/${file.name}');
          await fileToUpload.writeAsBytes(bytes);
        } else {
          fileToUpload = File(file.path!);
        }

        final response = await EnhancedFileService.uploadProfileImage(
          fileToUpload,
        );

        if (response != null) {
          _showSuccessSnackBar('Profile picture updated successfully');
          await _loadProfileImage(); // Reload the image

          // Notify parent widget
          if (widget.onImageUpdated != null && _profileImage != null) {
            widget.onImageUpdated!(_profileImage!);
          }
        } else {
          _showErrorSnackBar('Failed to upload profile picture');
        }
      } catch (e) {
        _showErrorSnackBar('Error uploading image: $e');
      } finally {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _deleteProfileImage() async {
    if (_profileImage == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Profile Picture'),
        content: const Text(
          'Are you sure you want to remove your profile picture?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.errorDarkTheme
                  : AppTheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await EnhancedFileService.deleteFile(_profileImage!.id);
        if (success) {
          setState(() {
            _profileImage = null;
            _imageBytes = null;
          });
          _showSuccessSnackBar('Profile picture removed successfully');

          // Notify parent widget
          if (widget.onImageUpdated != null) {
            // Create a dummy UserFileDTO to indicate deletion
            widget.onImageUpdated!(
              UserFileDTO(
                  id: -1,
                  originalFilename: '',
                  contentType: '',
                  fileSize: 0,
                  fileCategory: 'PROFILE_PICTURE',
                  ownerId: 0,
                  ownerType: '',
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                  fileName: ''),
            );
          }
        } else {
          _showErrorSnackBar('Failed to remove profile picture');
        }
      } catch (e) {
        _showErrorSnackBar('Error removing profile picture: $e');
      }
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.canEdit)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Upload New Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _uploadProfileImage();
                },
              ),
            if (_profileImage != null)
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('View Full Size'),
                onTap: () {
                  Navigator.pop(context);
                  _showFullSizeImage();
                },
              ),
            if (_profileImage != null && widget.canEdit)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteProfileImage();
                },
              ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullSizeImage() {
    if (_imageBytes == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Profile Picture'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.memory(_imageBytes!, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.canEdit
          ? _showImageOptions
          : (_imageBytes != null ? _showFullSizeImage : null),
      child: Stack(
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[200],
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: _isLoading
                ? const CircularProgressIndicator()
                : _imageBytes != null
                    ? ClipOval(
                        child: Image.memory(
                          _imageBytes!,
                          width: widget.size,
                          height: widget.size,
                          fit: BoxFit.cover,
                        ),
                      )
                    : widget.existingImageUrl != null
                        ? ClipOval(
                            child: Image.network(
                              widget.existingImageUrl!,
                              width: widget.size,
                              height: widget.size,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildPlaceholder();
                              },
                            ),
                          )
                        : _buildPlaceholder(),
          ),

          // Upload indicator
          if (_isUploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.5),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),

          // Edit icon
          if (widget.canEdit && !_isUploading)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.person, size: widget.size * 0.4, color: Colors.grey[400]),
        if (widget.size > 80)
          Text(
            widget.placeholderText,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: widget.size * 0.08,
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}

/// Compact profile picture widget for lists and smaller displays
class CompactProfilePicture extends StatelessWidget {
  final double size;
  final String? imageUrl;
  final UserFileDTO? profileImage;
  final String initials;

  const CompactProfilePicture({
    super.key,
    this.size = 40,
    this.imageUrl,
    this.profileImage,
    this.initials = '??',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: profileImage != null
          ? FutureBuilder<Uint8List?>(
              future: EnhancedFileService.downloadFile(profileImage!.id),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return ClipOval(
                    child: Image.memory(
                      snapshot.data!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                    ),
                  );
                }
                return _buildInitialsPlaceholder(context);
              },
            )
          : imageUrl != null
              ? ClipOval(
                  child: Image.network(
                    imageUrl!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildInitialsPlaceholder(context);
                    },
                  ),
                )
              : _buildInitialsPlaceholder(context),
    );
  }

  Widget _buildInitialsPlaceholder(BuildContext context) {
    return Center(
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
