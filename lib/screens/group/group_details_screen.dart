import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_text_field.dart';

/// GroupDetailsScreen shows detailed information about a group.
///
/// Features:
/// - Group info (name, description, code, created date)
/// - Member list with names and profile initials
/// - Owner actions: edit, remove members, delete group
/// - Member actions: leave group
/// - Real-time updates via Firestore stream
///
/// Architecture:
/// - Uses selectGroup() to subscribe to real-time updates
/// - Fetches member details separately (user names)
/// - Clears subscription when leaving screen
class GroupDetailsScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailsScreen({super.key, required this.groupId});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  /// Cache of member user data.
  ///
  /// Why cache?
  /// - Avoid re-fetching on every rebuild
  /// - Map for O(1) lookup by userId
  /// - Updated when members change
  Map<String, UserModel> _memberCache = {};

  /// Loading state for member data.
  bool _isLoadingMembers = true;

  @override
  void initState() {
    super.initState();
    // Start listening to group updates
    // This sets up real-time stream in GroupProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GroupProvider>().selectGroup(widget.groupId);
    });
  }

  @override
  void dispose() {
    // Clear the selected group stream when leaving
    // Prevents memory leaks and unnecessary Firestore reads
    context.read<GroupProvider>().clearSelectedGroup();
    super.dispose();
  }

  /// Fetches user data for all group members.
  ///
  /// Called when:
  /// - Screen first loads
  /// - Members list changes (new member joins, member leaves)
  ///
  /// Why separate fetch (not in Provider)?
  /// - Member details are UI concern, not group state
  /// - Keeps GroupProvider focused on group data
  /// - Could move to separate UserService later
  Future<void> _fetchMemberDetails(List<String> memberIds) async {
    if (memberIds.isEmpty) {
      setState(() {
        _isLoadingMembers = false;
      });
      return;
    }

    try {
      // Fetch all members in one query using 'whereIn'
      // Note: 'whereIn' limited to 10 items per query
      // Future upgrade: Batch queries for groups > 10 members
      final firestore = FirebaseFirestore.instance;

      // For groups with <= 10 members (most cases)
      if (memberIds.length <= 10) {
        final snapshot = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: memberIds)
            .get();

        final Map<String, UserModel> newCache = {};
        for (final doc in snapshot.docs) {
          newCache[doc.id] = UserModel.fromFirestore(doc);
        }

        if (mounted) {
          setState(() {
            _memberCache = newCache;
            _isLoadingMembers = false;
          });
        }
      } else {
        // For larger groups: batch into chunks of 10
        // Firestore 'whereIn' limit is 10 items
        final Map<String, UserModel> newCache = {};

        for (int i = 0; i < memberIds.length; i += 10) {
          final chunk = memberIds.sublist(
            i,
            (i + 10 > memberIds.length) ? memberIds.length : i + 10,
          );

          final snapshot = await firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (final doc in snapshot.docs) {
            newCache[doc.id] = UserModel.fromFirestore(doc);
          }
        }

        if (mounted) {
          setState(() {
            _memberCache = newCache;
            _isLoadingMembers = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMembers = false;
        });
      }
    }
  }

  /// Copies group code to clipboard.
  void _copyGroupCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Group code copied!'),
        backgroundColor: AppConstants.successColor,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Shows edit group dialog.
  void _showEditGroupDialog(GroupModel group) {
    final nameController = TextEditingController(text: group.groupName);
    final descController = TextEditingController(text: group.description ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        title: const Text('Edit Group'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTextField(
                controller: nameController,
                label: 'Group Name',
                prefixIcon: Icons.group,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: descController,
                label: 'Description (Optional)',
                prefixIcon: Icons.description_outlined,
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Group name cannot be empty'),
                    backgroundColor: AppConstants.errorColor,
                  ),
                );
                return;
              }

              Navigator.pop(context); // Close dialog first

              final success = await context.read<GroupProvider>().updateGroup(
                groupId: group.groupId,
                groupName: newName,
                description: descController.text.trim(),
              );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Group updated!' : 'Failed to update group',
                    ),
                    backgroundColor: success
                        ? AppConstants.successColor
                        : AppConstants.errorColor,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Shows leave group confirmation dialog.
  void _showLeaveGroupDialog(GroupModel group, String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        title: const Text('Leave Group'),
        content: Text(
          'Are you sure you want to leave "${group.groupName}"?\n\n'
          'You will need the group code to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog

              final success = await context.read<GroupProvider>().leaveGroup(
                groupId: group.groupId,
                userId: userId,
              );

              if (mounted) {
                if (success) {
                  Navigator.pop(context); // Go back to home
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You have left the group'),
                      backgroundColor: AppConstants.successColor,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.read<GroupProvider>().errorMessage ??
                            'Failed to leave group',
                      ),
                      backgroundColor: AppConstants.errorColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Leave',
              style: TextStyle(color: AppConstants.errorColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows delete group confirmation dialog (owner only).
  void _showDeleteGroupDialog(GroupModel group, String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        title: const Text('Delete Group'),
        content: Text(
          'Are you sure you want to delete "${group.groupName}"?\n\n'
          'This action cannot be undone. All group data will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog

              final success = await context.read<GroupProvider>().deleteGroup(
                groupId: group.groupId,
                userId: userId,
              );

              if (mounted) {
                if (success) {
                  Navigator.pop(context); // Go back to home
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Group deleted'),
                      backgroundColor: AppConstants.successColor,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.read<GroupProvider>().errorMessage ??
                            'Failed to delete group',
                      ),
                      backgroundColor: AppConstants.errorColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppConstants.errorColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows remove member confirmation dialog (owner only).
  void _showRemoveMemberDialog(
    GroupModel group,
    String memberId,
    String memberName,
  ) {
    final currentUserId = context.read<AuthProvider>().firebaseUser?.uid;
    if (currentUserId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        title: const Text('Remove Member'),
        content: Text('Remove $memberName from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              final success = await context.read<GroupProvider>().removeMember(
                groupId: group.groupId,
                memberId: memberId,
                requestingUserId: currentUserId,
              );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? '$memberName removed from group'
                          : 'Failed to remove member',
                    ),
                    backgroundColor: success
                        ? AppConstants.successColor
                        : AppConstants.errorColor,
                  ),
                );
              }
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: AppConstants.errorColor),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().firebaseUser?.uid;

    return Consumer<GroupProvider>(
      builder: (context, groupProvider, child) {
        final group = groupProvider.selectedGroup;

        // Loading state
        if (group == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Group Details'),
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
            ),
            body: const Center(
              child: CircularProgressIndicator(
                color: AppConstants.primaryColor,
              ),
            ),
          );
        }

        // Check if current user is owner
        final isOwner = group.isOwner(currentUserId ?? '');

        // Fetch member details when members list changes
        // Using addPostFrameCallback to avoid calling setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_memberCache.length != group.members.length ||
              !group.members.every((id) => _memberCache.containsKey(id))) {
            _fetchMemberDetails(group.members);
          }
        });

        return Scaffold(
          backgroundColor: AppConstants.backgroundColor,
          appBar: AppBar(
            title: Text(group.groupName),
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: Colors.white,
            actions: [
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showEditGroupDialog(group),
                  tooltip: 'Edit Group',
                ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'leave':
                      _showLeaveGroupDialog(group, currentUserId!);
                      break;
                    case 'delete':
                      _showDeleteGroupDialog(group, currentUserId!);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (!isOwner)
                    const PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          Icon(
                            Icons.exit_to_app,
                            color: AppConstants.errorColor,
                          ),
                          SizedBox(width: 12),
                          Text('Leave Group'),
                        ],
                      ),
                    ),
                  if (isOwner)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: AppConstants.errorColor),
                          SizedBox(width: 12),
                          Text('Delete Group'),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Group Info Card
                _buildGroupInfoCard(group),
                const SizedBox(height: 16),

                // Group Code Card
                _buildGroupCodeCard(group),
                const SizedBox(height: 16),

                // Members Card
                _buildMembersCard(group, isOwner, currentUserId ?? ''),
                const SizedBox(height: 24),

                // Placeholder for future: Expenses summary, balances, etc.
                Container(
                  padding: const EdgeInsets.all(AppConstants.largePadding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                      AppConstants.borderRadius,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Expenses Coming Soon!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Track shared expenses in Sprint 3',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds the group info card.
  Widget _buildGroupInfoCard(GroupModel group) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.largePadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.group,
                  color: AppConstants.primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.groupName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.memberCount} member${group.memberCount != 1 ? 's' : ''}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (group.description != null && group.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              group.description!,
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 8),
              Text(
                'Created ${_formatDate(group.createdAt)}',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the group code card.
  Widget _buildGroupCodeCard(GroupModel group) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.largePadding),
      decoration: BoxDecoration(
        color: AppConstants.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        border: Border.all(color: AppConstants.primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'Group Code',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                group.groupCode,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                  color: AppConstants.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _copyGroupCode(group.groupCode),
                icon: const Icon(Icons.copy, color: AppConstants.primaryColor),
                tooltip: 'Copy code',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Share this code to invite others',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// Builds the members list card.
  Widget _buildMembersCard(
    GroupModel group,
    bool isOwner,
    String currentUserId,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.largePadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: AppConstants.primaryColor),
              const SizedBox(width: 12),
              const Text(
                'Members',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${group.memberCount}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Member list
          if (_isLoadingMembers)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  color: AppConstants.primaryColor,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true, // Important inside SingleChildScrollView
              physics:
                  const NeverScrollableScrollPhysics(), // Disable inner scroll
              itemCount: group.members.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final memberId = group.members[index];
                final member = _memberCache[memberId];
                final isGroupOwner = group.createdBy == memberId;
                final isCurrentUser = memberId == currentUserId;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isGroupOwner
                        ? AppConstants.primaryColor
                        : Colors.grey[300],
                    child: Text(
                      member?.name.isNotEmpty == true
                          ? member!.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: isGroupOwner ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        member?.name ?? 'Unknown User',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (isCurrentUser)
                        const Text(
                          ' (You)',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                  subtitle: isGroupOwner
                      ? const Text(
                          'Owner',
                          style: TextStyle(
                            color: AppConstants.primaryColor,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  trailing: isOwner && !isGroupOwner
                      ? IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: AppConstants.errorColor,
                          ),
                          onPressed: () => _showRemoveMemberDialog(
                            group,
                            memberId,
                            member?.name ?? 'this member',
                          ),
                          tooltip: 'Remove member',
                        )
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }

  /// Formats date for display.
  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
