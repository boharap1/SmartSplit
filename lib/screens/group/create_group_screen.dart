import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/group_model.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_button.dart';

/// CreateGroupScreen allows users to create a new expense-sharing group.
/// 
/// User Flow:
/// 1. Enter group name (required)
/// 2. Enter description (optional)
/// 3. Tap "Create Group"
/// 4. See success bottom sheet with group code
/// 5. Copy/share code and close
/// 
/// Design Decisions:
/// - Minimal fields for quick group creation
/// - Bottom sheet for success (not new screen) - feels faster
/// - Large group code display for easy reading/sharing
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  /// Form key for validation.
  /// 
  /// Why GlobalKey?
  /// - Allows access to FormState from anywhere in widget
  /// - Can call _formKey.currentState!.validate()
  /// - Standard Flutter pattern for forms
  final _formKey = GlobalKey<FormState>();
  
  /// Controllers for text fields.
  /// 
  /// Why TextEditingController?
  /// - Access text value anytime: _nameController.text
  /// - Can set initial value
  /// - Can listen to changes
  /// - Must dispose to prevent memory leaks!
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  /// Track if user has attempted to submit.
  /// 
  /// Why track this?
  /// - Don't show errors before first submit attempt
  /// - Better UX: user isn't bombarded with red text immediately
  /// - After first attempt, show errors in real-time
  bool _hasAttemptedSubmit = false;

  @override
  void dispose() {
    // IMPORTANT: Always dispose controllers!
    // Prevents memory leaks
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Handles the create group button press.
  Future<void> _handleCreateGroup() async {
    // Mark that user has attempted to submit
    setState(() {
      _hasAttemptedSubmit = true;
    });

    // Validate form
    if (!_formKey.currentState!.validate()) {
      return;  // Stop if validation fails
    }

    // Get current user ID
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.firebaseUser?.uid;

    if (userId == null) {
      // Should never happen if auth is working correctly
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Not logged in'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
      return;
    }

    // Create the group
    final result = await context.read<GroupProvider>().createGroup(
      groupName: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty 
          ? null 
          : _descriptionController.text.trim(),
      createdBy: userId,
    );

    // Handle result
    if (result.group != null && mounted) {
      // Success! Show bottom sheet with group code
      _showSuccessBottomSheet(result.group!);
    } else if (mounted) {
      // Error - show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to create group'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  /// Shows success bottom sheet with group code.
  /// 
  /// Why bottom sheet instead of dialog?
  /// - More mobile-friendly
  /// - Can make it larger without feeling intrusive
  /// - Natural "slide down to dismiss" gesture
  /// - Looks more modern
  void _showSuccessBottomSheet(GroupModel group) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,  // Must tap button to close
      enableDrag: false,     // Prevent accidental dismiss
      backgroundColor: Colors.transparent,
      builder: (context) => _SuccessBottomSheet(
        group: group,
        onDone: () {
          Navigator.pop(context);  // Close bottom sheet
          Navigator.pop(context);  // Go back to home
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('Create Group'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          child: Form(
            key: _formKey,
            // AutovalidateMode explained:
            // - disabled: Never auto-validate
            // - always: Validate on every change (annoying!)
            // - onUserInteraction: Validate after user interacts
            // We use conditional: only after first submit attempt
            autovalidateMode: _hasAttemptedSubmit
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header illustration
                Container(
                  padding: const EdgeInsets.all(AppConstants.largePadding),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.group_add,
                        size: 64,
                        color: AppConstants.primaryColor,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Create a New Group',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start tracking shared expenses with friends, family, or roommates.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Group Name Field
                CustomTextField(
                  controller: _nameController,
                  label: 'Group Name',
                  hint: 'e.g., Apartment Bills, Trip to Paris',
                  prefixIcon: Icons.group,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a group name';
                    }
                    if (value.trim().length < 2) {
                      return 'Group name must be at least 2 characters';
                    }
                    if (value.trim().length > 50) {
                      return 'Group name must be less than 50 characters';
                    }
                    return null;  // Valid!
                  },
                ),
                const SizedBox(height: 20),

                // Description Field
                CustomTextField(
                  controller: _descriptionController,
                  label: 'Description (Optional)',
                  hint: 'What is this group for?',
                  prefixIcon: Icons.description_outlined,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    // Optional field - only validate if filled
                    if (value != null && value.trim().length > 200) {
                      return 'Description must be less than 200 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Info box about group code
                Container(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'A unique 6-digit code will be generated for others to join your group.',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Create Button
                Consumer<GroupProvider>(
                  builder: (context, groupProvider, child) {
                    return CustomButton(
                      text: 'Create Group',
                      onPressed: _handleCreateGroup,
                      isLoading: groupProvider.isLoading,
                      icon: Icons.add_circle_outline,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Cancel Button
                CustomButton(
                  text: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                  isOutlined: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Success bottom sheet showing the generated group code.
/// 
/// Why separate widget?
/// - Cleaner code organization
/// - Can be reused elsewhere if needed
/// - Easier to test independently
class _SuccessBottomSheet extends StatelessWidget {
  final GroupModel group;
  final VoidCallback onDone;

  const _SuccessBottomSheet({
    required this.group,
    required this.onDone,
  });

  /// Copies group code to clipboard.
  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: group.groupCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Group code copied to clipboard!'),
        backgroundColor: AppConstants.successColor,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.largePadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,  // Take minimum space needed
        children: [
          // Handle bar (visual affordance for bottom sheet)
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Success icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConstants.successColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: AppConstants.successColor,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),

          // Success message
          const Text(
            'Group Created!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.groupName,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),

          // Group code display
          const Text(
            'Share this code with others:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          
          // Large code display with copy button
          GestureDetector(
            onTap: () => _copyCode(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                border: Border.all(
                  color: AppConstants.primaryColor.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.groupCode,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,  // Space between digits
                      color: AppConstants.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.copy,
                    color: AppConstants.primaryColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to copy',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 32),

          // Done button
          SizedBox(
            width: double.infinity,
            child: CustomButton(
              text: 'Done',
              onPressed: onDone,
              icon: Icons.check,
            ),
          ),
          const SizedBox(height: 16),
          
          // Future: Share button
          // CustomButton(
          //   text: 'Share Code',
          //   onPressed: () => Share.share('Join my SmartSplit group: ${group.groupCode}'),
          //   isOutlined: true,
          //   icon: Icons.share,
          // ),
        ],
      ),
    );
  }
}
