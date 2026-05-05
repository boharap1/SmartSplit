import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  File?   _pickedImage;
  bool    _removePhoto = false;
  bool    _isSaving    = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameController  = TextEditingController(text: user?.name        ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ── Image picking ─────────────────────────────────────────────────────────

  void _showImagePicker() {
    final hasPhoto = _pickedImage != null ||
        (!_removePhoto &&
            (context.read<AuthProvider>().user?.hasProfilePicture == true));

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: AppConstants.primaryColor),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: AppConstants.primaryColor),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: AppConstants.errorColor),
                  title: const Text('Remove Photo',
                      style: TextStyle(color: AppConstants.errorColor)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _pickedImage  = null;
                      _removePhoto  = true;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source:       source,
        maxWidth:     800,
        maxHeight:    800,
        imageQuality: 80,
      );
      if (picked != null && mounted) {
        setState(() {
          _pickedImage = File(picked.path);
          _removePhoto = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access camera or gallery.'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final uid          = authProvider.firebaseUser!.uid;
      String? newPhotoUrl;

      // Upload new image
      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('profile_pictures/$uid.jpg');
        final task = await ref.putFile(
          _pickedImage!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        newPhotoUrl = await task.ref.getDownloadURL();
      } else if (_removePhoto) {
        newPhotoUrl = ''; // empty string signals "cleared"
      }

      final success = await authProvider.updateProfile(
        name:           _nameController.text.trim(),
        phoneNumber:    _phoneController.text.trim(),
        profilePicture: newPhotoUrl,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: AppConstants.successColor,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                authProvider.errorMessage ?? 'Failed to update profile.'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text(
                    'Save',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.largePadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),

              // ── Avatar ───────────────────────────────────────────────
              GestureDetector(
                onTap: _isSaving ? null : _showImagePicker,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildAvatar(user),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to change photo',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),

              const SizedBox(height: 32),

              // ── Full Name ─────────────────────────────────────────────
              _field(
                controller:    _nameController,
                label:         'Full Name',
                icon:          Icons.person_outline_rounded,
                keyboardType:  TextInputType.name,
                capitalization: TextCapitalization.words,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Name is required';
                  }
                  if (v.trim().length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  if (v.trim().length > 50) return 'Name is too long';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Phone ─────────────────────────────────────────────────
              _field(
                controller:   _phoneController,
                label:        'Phone Number (optional)',
                icon:         Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[\d\+\-\(\)\s]')),
                ],
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    final digits = v.replaceAll(RegExp(r'\D'), '');
                    if (digits.length < 7 || digits.length > 15) {
                      return 'Enter a valid phone number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Used for contact and identification.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),

              const SizedBox(height: 32),

              // ── Save button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.borderRadius),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Save Changes',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _buildAvatar(UserModel? user) {
    final showPicked  = _pickedImage != null;
    final showNetwork = !_removePhoto && !showPicked && user!.hasProfilePicture;
    final initials    = _initials(user?.name ?? '');

    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppConstants.primaryColor.withValues(alpha: 0.3),
          width: 3,
        ),
      ),
      child: ClipOval(
        child: showPicked
            ? Image.file(_pickedImage!, fit: BoxFit.cover)
            : showNetwork
                ? Image.network(
                    user.profilePicture!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _initialsWidget(initials),
                  )
                : _initialsWidget(initials),
      ),
    );
  }

  Widget _initialsWidget(String initials) => Container(
        color: AppConstants.primaryColor.withValues(alpha: 0.12),
        child: Center(
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: AppConstants.primaryColor,
            ),
          ),
        ),
      );

  String _initials(String name) {
    final words = name.trim().split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'U';
    return words.length >= 2
        ? '${words[0][0]}${words[1][0]}'.toUpperCase()
        : words[0][0].toUpperCase();
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller:          controller,
      keyboardType:        keyboardType,
      textCapitalization:  capitalization,
      inputFormatters:     inputFormatters,
      validator:           validator,
      enabled:             !_isSaving,
      decoration: InputDecoration(
        labelText:   label,
        prefixIcon:  Icon(icon, color: AppConstants.primaryColor, size: 20),
        filled:      true,
        fillColor:   Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide:
              const BorderSide(color: AppConstants.primaryColor, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
      ),
    );
  }
}
