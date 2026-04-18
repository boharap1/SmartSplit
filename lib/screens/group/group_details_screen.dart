import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../services/settlement_service.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_text_field.dart';
import '../../providers/settings_provider.dart';

class GroupDetailsScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailsScreen({super.key, required this.groupId});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  Map<String, UserModel> _memberCache = {};
  Set<String> _knownMemberIds = {};
  bool _isLoadingMembers = true;

  // Countdown timer for active invite code
  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  String? _trackedInviteCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GroupProvider>().selectGroup(widget.groupId);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    context.read<GroupProvider>().clearSelectedGroup();
    super.dispose();
  }

  Future<void> _fetchMemberDetails(List<String> memberIds) async {
    if (memberIds.isEmpty) {
      setState(() => _isLoadingMembers = false);
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
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
    } catch (e) {
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  void _startCountdown(DateTime expiry) {
    _countdownTimer?.cancel();
    final remaining = expiry.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      setState(() => _secondsRemaining = 0);
      return;
    }
    setState(() => _secondsRemaining = remaining);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final secs = expiry.difference(DateTime.now()).inSeconds;
      if (secs <= 0) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining = secs);
      }
    });
  }

  String _formatCountdown(int seconds) {
    if (seconds <= 0) return 'Expired';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')} left';
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite code copied!'),
        backgroundColor: AppConstants.successColor,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _generateInviteCode(GroupModel group) async {
    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null) return;

    final result = await context.read<GroupProvider>().generateInviteCode(
      groupId: group.groupId,
      userId: userId,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.code != null
                ? 'Invite code generated! Valid for 10 minutes.'
                : result.error ?? 'Failed to generate invite code',
          ),
          backgroundColor: result.code != null
              ? AppConstants.successColor
              : AppConstants.errorColor,
        ),
      );
    }
  }

  void _showEditGroupDialog(GroupModel group) {
    final requestingUserId =
        context.read<AuthProvider>().firebaseUser?.uid ?? '';
    final nameController = TextEditingController(text: group.groupName);
    final descController =
        TextEditingController(text: group.description ?? '');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  const SnackBar(
                    content: Text('Group name cannot be empty'),
                    backgroundColor: AppConstants.errorColor,
                  ),
                );
                return;
              }
              Navigator.pop(dialogCtx);

              final groupProvider = context.read<GroupProvider>();
              final success = await groupProvider.updateGroup(
                groupId: group.groupId,
                requestingUserId: requestingUserId,
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

  // Shows a dialog explaining which members have outstanding balances
  // blocking a group action (delete / leave).
  void _showBlockedDialog({
    required String title,
    required String action,
    required List<MapEntry<String, double>> unsettled,
  }) {
    final cs = context.read<SettingsProvider>().currencySymbol;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following members have outstanding balances. '
              'All balances must reach ${cs}0.00 before you can $action this group:',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 16),
            ...unsettled.map((e) {
              final memberId = e.key;
              final amount = e.value;
              final name =
                  _memberCache[memberId]?.name ?? 'Member …${memberId.substring(memberId.length - 4)}';
              final isOwed = amount > 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      isOwed ? Icons.arrow_circle_up : Icons.arrow_circle_down,
                      size: 18,
                      color: isOwed
                          ? AppConstants.successColor
                          : AppConstants.errorColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    Text(
                      isOwed
                          ? '+$cs${amount.toStringAsFixed(2)}'
                          : '−$cs${amount.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isOwed
                            ? AppConstants.successColor
                            : AppConstants.errorColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius:
                    BorderRadius.circular(AppConstants.borderRadius),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Go to the Settle Up tab to record payments and clear all balances.',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLeaveGroupDialog(
    GroupModel group,
    String userId,
  ) async {
    final balances =
        await SettlementService().calculateBalances(group.groupId);
    final userBalance = balances[userId] ?? 0;

    if (userBalance.abs() > 0.01) {
      if (!mounted) return;
      _showBlockedDialog(
        title: 'Cannot Leave Group',
        action: 'leave',
        unsettled: [MapEntry(userId, userBalance)],
      );
      return;
    }

    if (!mounted) return;
    final groupProvider = context.read<GroupProvider>();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        title: const Text('Leave Group'),
        content: Text(
          'Are you sure you want to leave "${group.groupName}"?\n\n'
          'You will need a new invite code to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final success = await groupProvider.leaveGroup(
                groupId: group.groupId,
                userId: userId,
              );
              if (mounted) {
                if (success) {
                  Navigator.pop(context);
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
                        groupProvider.errorMessage ?? 'Failed to leave group',
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

  Future<void> _showDeleteGroupDialog(
    GroupModel group,
    String userId,
  ) async {
    final balances =
        await SettlementService().calculateBalances(group.groupId);
    final unsettled =
        balances.entries.where((e) => e.value.abs() > 0.01).toList();

    if (unsettled.isNotEmpty) {
      if (!mounted) return;
      _showBlockedDialog(
        title: 'Cannot Delete Group',
        action: 'delete',
        unsettled: unsettled,
      );
      return;
    }

    if (!mounted) return;
    final groupProvider = context.read<GroupProvider>();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final success = await groupProvider.deleteGroup(
                groupId: group.groupId,
                userId: userId,
              );
              if (mounted) {
                if (success) {
                  Navigator.pop(context);
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
                        groupProvider.errorMessage ?? 'Failed to delete group',
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

  Future<void> _showRemoveMemberDialog(
    GroupModel group,
    String memberId,
    String memberName,
  ) async {
    final currentUserId = context.read<AuthProvider>().firebaseUser?.uid;
    if (currentUserId == null) return;

    final balances =
        await SettlementService().calculateBalances(group.groupId);
    final memberBalance = balances[memberId] ?? 0;
    if (memberBalance.abs() > 0.01) {
      if (!mounted) return;
      final cs = context.read<SettingsProvider>().currencySymbol;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$memberName has an outstanding balance of '
            '$cs${memberBalance.abs().toStringAsFixed(2)}. Settle up first.',
          ),
          backgroundColor: AppConstants.errorColor,
        ),
      );
      return;
    }

    if (!mounted) return;
    final groupProvider = context.read<GroupProvider>();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        title: const Text('Remove Member'),
        content: Text('Remove $memberName from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final success = await groupProvider.removeMember(
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

  Future<void> _assignAdmin(
    GroupModel group,
    String memberId,
    String memberName,
  ) async {
    final currentUserId = context.read<AuthProvider>().firebaseUser?.uid;
    if (currentUserId == null) return;
    final groupProvider = context.read<GroupProvider>();

    final success = await groupProvider.assignAdmin(
      groupId: group.groupId,
      targetUserId: memberId,
      requestingUserId: currentUserId,
    );
    final errorMsg = groupProvider.errorMessage;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '$memberName is now an admin'
                : errorMsg ?? 'Failed to assign admin',
          ),
          backgroundColor:
              success ? AppConstants.successColor : AppConstants.errorColor,
        ),
      );
    }
  }

  Future<void> _removeAdminRole(
    GroupModel group,
    String memberId,
    String memberName,
  ) async {
    final currentUserId = context.read<AuthProvider>().firebaseUser?.uid;
    if (currentUserId == null) return;
    final groupProvider = context.read<GroupProvider>();

    final success = await groupProvider.removeAdmin(
      groupId: group.groupId,
      targetUserId: memberId,
      requestingUserId: currentUserId,
    );
    final errorMsg = groupProvider.errorMessage;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '$memberName is no longer an admin'
                : errorMsg ?? 'Failed to remove admin',
          ),
          backgroundColor:
              success ? AppConstants.successColor : AppConstants.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().firebaseUser?.uid;

    return Consumer<GroupProvider>(
      builder: (context, groupProvider, child) {
        final group = groupProvider.selectedGroup;

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

        final isOwner = group.isOwner(currentUserId ?? '');
        final isAdmin = group.isAdmin(currentUserId ?? '');

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          // Refresh member list when members change
          final currentIds = group.members.toSet();
          if (currentIds.length != _knownMemberIds.length ||
              !currentIds.every(_knownMemberIds.contains)) {
            _knownMemberIds = currentIds;
            _fetchMemberDetails(group.members);
          }

          // Start/stop invite countdown when invite changes
          final newCode =
              group.hasActiveInvite ? group.activeInviteCode : null;
          if (newCode != _trackedInviteCode) {
            _trackedInviteCode = newCode;
            if (newCode != null && group.activeInviteExpiry != null) {
              _startCountdown(group.activeInviteExpiry!);
            } else {
              _countdownTimer?.cancel();
              _countdownTimer = null;
            }
          }
        });

        return Scaffold(
          backgroundColor: AppConstants.backgroundColor,
          appBar: AppBar(
            title: Text(group.groupName),
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: Colors.white,
            actions: [
              if (isAdmin)
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
                          Icon(Icons.exit_to_app,
                              color: AppConstants.errorColor),
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
                _buildGroupInfoCard(group),
                const SizedBox(height: 16),
                _buildInviteCodeCard(group, isAdmin),
                const SizedBox(height: 16),
                _buildMembersCard(group, isOwner, isAdmin, currentUserId ?? ''),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupInfoCard(GroupModel group) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.largePadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  color: AppConstants.primaryColor.withValues(alpha: 0.1),
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
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (group.description != null &&
              group.description!.isNotEmpty) ...[
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

  Widget _buildInviteCodeCard(GroupModel group, bool isAdmin) {
    final hasActive = group.hasActiveInvite;

    return Container(
      padding: const EdgeInsets.all(AppConstants.largePadding),
      decoration: BoxDecoration(
        color: hasActive
            ? AppConstants.primaryColor.withValues(alpha: 0.08)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        border: Border.all(
          color: hasActive
              ? AppConstants.primaryColor.withValues(alpha: 0.3)
              : Colors.grey[300]!,
        ),
      ),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Icon(
                Icons.link,
                size: 18,
                color:
                    hasActive ? AppConstants.primaryColor : Colors.grey[500],
              ),
              const SizedBox(width: 8),
              Text(
                'Invite Code',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: hasActive ? Colors.black87 : Colors.grey[600],
                ),
              ),
              if (hasActive) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppConstants.successColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 12, color: AppConstants.successColor),
                      const SizedBox(width: 4),
                      Text(
                        _formatCountdown(_secondsRemaining),
                        style: const TextStyle(
                          color: AppConstants.successColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          if (hasActive) ...[
            // Tap-to-copy code display
            GestureDetector(
              onTap: () => _copyCode(group.activeInviteCode!),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(AppConstants.borderRadius),
                  border: Border.all(
                    color:
                        AppConstants.primaryColor.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.activeInviteCode!,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                        color: AppConstants.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.copy,
                        color: AppConstants.primaryColor, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to copy  •  Valid for 10 minutes from generation',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _generateInviteCode(group),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Generate New Code'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.primaryColor,
                  side: const BorderSide(color: AppConstants.primaryColor),
                ),
              ),
            ],
          ] else ...[
            if (isAdmin)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _generateInviteCode(group),
                  icon: const Icon(Icons.add_link),
                  label: const Text('Generate Invite Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              )
            else
              Text(
                'No active invite code.\nAsk an admin to generate one.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersCard(
    GroupModel group,
    bool isOwner,
    bool isAdmin,
    String currentUserId,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.largePadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.1),
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
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: group.members.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final memberId = group.members[index];
                final member = _memberCache[memberId];
                final isGroupOwner = group.createdBy == memberId;
                final isMemberAdmin = group.adminIds.contains(memberId);
                final isCurrentUser = memberId == currentUserId;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isGroupOwner
                        ? AppConstants.primaryColor
                        : isMemberAdmin
                            ? Colors.orange.shade600
                            : Colors.grey[300],
                    child: Text(
                      member?.name.isNotEmpty == true
                          ? member!.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: isGroupOwner || isMemberAdmin
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        member?.name ?? 'Unknown User',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
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
                      : isMemberAdmin
                          ? const Text(
                              'Admin',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                              ),
                            )
                          : null,
                  trailing: _buildMemberTrailing(
                    group,
                    memberId,
                    member,
                    isGroupOwner,
                    isMemberAdmin,
                    isCurrentUser,
                    isOwner,
                    isAdmin,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget? _buildMemberTrailing(
    GroupModel group,
    String memberId,
    UserModel? member,
    bool isGroupOwner,
    bool isMemberAdmin,
    bool isCurrentUser,
    bool isOwner,
    bool isAdmin,
  ) {
    if (isCurrentUser || isGroupOwner) return null;
    final memberName = member?.name ?? 'this member';

    if (isOwner) {
      return PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
        tooltip: 'Member options',
        onSelected: (value) async {
          switch (value) {
            case 'make_admin':
              await _assignAdmin(group, memberId, memberName);
              break;
            case 'remove_admin':
              await _removeAdminRole(group, memberId, memberName);
              break;
            case 'remove':
              await _showRemoveMemberDialog(group, memberId, memberName);
              break;
          }
        },
        itemBuilder: (_) {
          return <PopupMenuEntry<String>>[
            if (!isMemberAdmin)
              PopupMenuItem<String>(
                value: 'make_admin',
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined,
                        color: Colors.orange),
                    const SizedBox(width: 12),
                    const Text('Make Admin'),
                  ],
                ),
              ),
            if (isMemberAdmin)
              PopupMenuItem<String>(
                value: 'remove_admin',
                child: Row(
                  children: [
                    const Icon(Icons.remove_moderator,
                        color: Colors.orange),
                    const SizedBox(width: 12),
                    const Text('Remove Admin'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'remove',
              child: Row(
                children: [
                  const Icon(Icons.remove_circle_outline,
                      color: AppConstants.errorColor),
                  const SizedBox(width: 12),
                  const Text(
                    'Remove from Group',
                    style: TextStyle(color: AppConstants.errorColor),
                  ),
                ],
              ),
            ),
          ];
        },
      );
    }

    // Non-owner admin can only remove regular members
    if (isAdmin && !isMemberAdmin) {
      return IconButton(
        icon: const Icon(Icons.remove_circle_outline,
            color: AppConstants.errorColor),
        onPressed: () =>
            _showRemoveMemberDialog(group, memberId, memberName),
        tooltip: 'Remove member',
      );
    }

    return null;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
