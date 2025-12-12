import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:image_cropper/image_cropper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';
import '../services/auth_service.dart';
import '../core/constants/app_constants.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isLoading = false;
  User? _user;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _nameController = TextEditingController(
      text: _user?.displayName ?? _user?.email?.split('@')[0] ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }



  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (pickedFile != null) {
        _cropImage(pickedFile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _cropImage(XFile pickedFile) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Theme.of(context).colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Image',
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
            ],
          ),
        ],
      );

      if (croppedFile != null) {
        setState(() {
          _imageFile = File(croppedFile.path);
        });
      }
    } catch (e) {
      print('Error cropping image: $e');
    }
  }

  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Library'),
                onTap: () {
                  _pickImage(ImageSource.gallery);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () {
                  _pickImage(ImageSource.camera);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null || _user == null) return null;

    try {
      print('Uploading image to backend...');
      
      // Get the ID token for authentication
      final String? token = await _user!.getIdToken();
      if (token == null) {
        print('Error: No ID token available');
        return null;
      }

      // Create multipart request
      final uri = Uri.parse('${AppConstants.apiBaseUrl}/api/upload/image');
      final request = http.MultipartRequest('POST', uri);
      
      // Add headers
      request.headers['Authorization'] = 'Bearer $token';
      
      // Add file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        _imageFile!.path,
      ));

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['status'] == 'success') {
          final String relativeUrl = data['url'];
          // Construct full URL
          // Remove /api from base URL if present to get root URL, or just append if base URL is root
          // AppConstants.apiBaseUrl usually ends with /api or similar, need to be careful
          // Assuming AppConstants.apiBaseUrl is like http://192.168.1.14:8000
          
          final String fullUrl = '${AppConstants.apiBaseUrl}$relativeUrl';
          print('Upload successful. URL: $fullUrl');
          return fullUrl;
        } else {
          print('Upload failed: ${data['message']}');
          return null;
        }
      } else {
        print('Upload failed with status: ${response.statusCode}');
        print('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String? photoUrl = _user?.photoURL;

      // Upload new image if selected
      if (_imageFile != null) {
        print('Uploading image...');
        final String? uploadedUrl = await _uploadImage();
        print('Uploaded URL: $uploadedUrl');
        if (uploadedUrl != null) {
          photoUrl = uploadedUrl;
        }
      }

      print('Updating profile with photoURL: $photoUrl');
      // Update Firebase Auth Profile
      await _user?.updateProfile(
        displayName: _nameController.text.trim(),
        photoURL: photoUrl,
      );
      
      // Update Firestore User Document
      if (_user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .set({
          'displayName': _nameController.text.trim(),
          'email': _user!.email,
          'photoURL': photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // Reload user to get updated info
      await _user?.reload();
      _user = FirebaseAuth.instance.currentUser;
      print('User reloaded. New photoURL: ${_user?.photoURL}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Clear selected image file as it's now uploaded
        // Force rebuild to show new image from URL
        setState(() {
          _imageFile = null;
          // This ensures the UI rebuilds with the new _user?.photoURL
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _isLoading = true;
    });
    
    // Use centralized AuthService
    await AuthService().signOut(context);
    
    // Note: If signOut succeeds, it navigates away. 
    // If it fails, execution continues here, so we might want to stop loading
    if (mounted) {
       setState(() {
         _isLoading = false;
       });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _user?.photoURL;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: AppConstants.pagePadding,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: AppConstants.spacingL),
              
              // Profile Picture
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: _imageFile != null
                          ? ClipOval(
                              child: Image.file(
                                _imageFile!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            )
                          : photoUrl != null
                              ? ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: photoUrl,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const CircularProgressIndicator(),
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.person,
                                      size: 60,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        onPressed: _showImagePickerModal,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: AppConstants.spacingXL),

              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: AppConstants.spacingM),

              // Email Field (Read-only)
              TextFormField(
                initialValue: _user?.email,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                ),
              ),

              const SizedBox(height: AppConstants.spacingXL),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: AppConstants.spacingL),

              // Sign Out Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(color: Theme.of(context).colorScheme.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
