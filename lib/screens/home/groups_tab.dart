import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/group_model.dart';
import '../../services/settlement_service.dart';
import '../../utils/constants.dart';
import '../../providers/settings_provider.dart';
import '../group/create_group_screen.dart';
import '../group/join_group_screen.dart';
import '../group/group_details_screen.dart';

class GroupsTab extends StatelessWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Groups',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Consumer<GroupProvider>(
        builder: (context, groupProvider, _) {
          if (groupProvider.isLoading && groupProvider.groups.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppConstants.primaryColor,
              ),
            );
          }
          if (groupProvider.groups.isEmpty) return _buildEmptyState(context);
          return _buildGroupsList(context, groupProvider.groups);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGroupOptions(context),
        backgroundColor: AppConstants.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.group_outlined,
                size: 56,
                color: AppConstants.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Groups Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or join a group to start.',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateGroupScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JoinGroupScreen()),
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text('Join'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupsList(BuildContext context, List<GroupModel> groups) {
    final currentUserId = context.watch<AuthProvider>().firebaseUser?.uid;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final isOwner = group.createdBy == currentUserId;
        final colors = [
          const Color(0xFF5C6BC0),
          const Color(0xFFFF7043),
          const Color(0xFF26A69A),
          const Color(0xFFAB47BC),
          const Color(0xFF42A5F5),
        ];
        final c = colors[group.groupName.hashCode.abs() % colors.length];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupDetailsScreen(groupId: group.groupId),
                ),
              ),
              onLongPress: () => _showGroupActions(
                context,
                group,
                isOwner,
                currentUserId ?? '',
              ),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          group.groupName[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: c,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.groupName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 14,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${group.memberCount} member${group.memberCount != 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                              if (isOwner) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppConstants.primaryColor.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Owner',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppConstants.primaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Action menu
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (action) => _handleGroupAction(
                        context,
                        action,
                        group,
                        isOwner,
                        currentUserId ?? '',
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Edit Group'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'invite',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Invite / Share Code'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        if (!isOwner)
                          const PopupMenuItem(
                            value: 'leave',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.exit_to_app,
                                  size: 18,
                                  color: Colors.orange,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Leave Group',
                                  style: TextStyle(color: Colors.orange),
                                ),
                              ],
                            ),
                          ),
                        if (isOwner)
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: AppConstants.errorColor,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Delete Group',
                                  style: TextStyle(
                                    color: AppConstants.errorColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleGroupAction(
    BuildContext context,
    String action,
    GroupModel group,
    bool isOwner,
    String userId,
  ) {
    switch (action) {
      case 'edit':
        _showEditDialog(context, group);
      case 'invite':
        _showInviteSheet(context, group);
      case 'leave':
        _confirmLeaveGroup(context, group, userId);
      case 'delete':
        _confirmDeleteGroup(context, group, userId);
    }
  }

  void _showGroupActions(
    BuildContext context,
    GroupModel group,
    bool isOwner,
    String userId,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                group.groupName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Group'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(context, group);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Invite / Share Code'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showInviteSheet(context, group);
                },
              ),
              const Divider(),
              if (!isOwner)
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.orange),
                  title: const Text(
                    'Leave Group',
                    style: TextStyle(color: Colors.orange),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmLeaveGroup(context, group, userId);
                  },
                ),
              if (isOwner)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppConstants.errorColor,
                  ),
                  title: const Text(
                    'Delete Group',
                    style: TextStyle(color: AppConstants.errorColor),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteGroup(context, group, userId);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, GroupModel group) {
    final nameCtrl = TextEditingController(text: group.groupName);
    final descCtrl = TextEditingController(text: group.description ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Group Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final userId =
                  context.read<AuthProvider>().firebaseUser?.uid ?? '';
              await context.read<GroupProvider>().updateGroup(
                groupId: group.groupId,
                requestingUserId: userId,
                groupName: nameCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty
                    ? null
                    : descCtrl.text.trim(),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Group updated'),
                    backgroundColor: AppConstants.successColor,
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

  void _showInviteSheet(BuildContext context, GroupModel group) {
    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null) return;
    final isAdmin = group.isAdmin(userId);

    // Local mutable state for the sheet (updated when code is generated)
    var sheetCode = group.hasActiveInvite ? group.activeInviteCode : null;
    var sheetExpiry = group.hasActiveInvite ? group.activeInviteExpiry : null;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Invite Members',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.groupName,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  if (sheetCode != null) ...[
                    // Active invite code display
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.timer_outlined,
                                  size: 14,
                                  color: AppConstants.successColor),
                              const SizedBox(width: 4),
                              Text(
                                'Expires at ${_formatExpiryTime(sheetExpiry!)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppConstants.successColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            sheetCode!,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                              color: AppConstants.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: sheetCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Code copied!'),
                                  backgroundColor: AppConstants.successColor,
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Copy Code'),
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final result = await context
                                    .read<GroupProvider>()
                                    .generateInviteCode(
                                      groupId: group.groupId,
                                      userId: userId,
                                    );
                                if (result.code != null) {
                                  setSheetState(() {
                                    sheetCode = result.code;
                                    sheetExpiry = DateTime.now()
                                        .add(const Duration(minutes: 10));
                                  });
                                }
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('New Code'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ] else ...[
                    // No active code
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        isAdmin
                            ? 'Generate a temporary invite code (valid 10 min).'
                            : 'No active invite code.\nAsk a group admin to generate one.',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await context
                                .read<GroupProvider>()
                                .generateInviteCode(
                                  groupId: group.groupId,
                                  userId: userId,
                                );
                            if (result.code != null) {
                              setSheetState(() {
                                sheetCode = result.code;
                                sheetExpiry = DateTime.now()
                                    .add(const Duration(minutes: 10));
                              });
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result.error ??
                                      'Failed to generate code'),
                                  backgroundColor: AppConstants.errorColor,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.add_link),
                          label: const Text('Generate Invite Code'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatExpiryTime(DateTime expiry) {
    final h = expiry.hour.toString().padLeft(2, '0');
    final m = expiry.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _confirmLeaveGroup(
    BuildContext context,
    GroupModel group,
    String userId,
  ) async {
    // Check if settlements are clear
    final settlementService = SettlementService();
    final balances = await settlementService.calculateBalances(group.groupId);
    final userBalance = balances[userId] ?? 0;

    if (userBalance.abs() > 0.01 && context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Cannot Leave Group', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have an outstanding balance in "${group.groupName}" '
                'that must be settled before you can leave.',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: userBalance > 0
                      ? AppConstants.successColor.withValues(alpha: 0.08)
                      : AppConstants.errorColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: userBalance > 0
                        ? AppConstants.successColor.withValues(alpha: 0.3)
                        : AppConstants.errorColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      userBalance > 0
                          ? Icons.arrow_circle_up
                          : Icons.arrow_circle_down,
                      color: userBalance > 0
                          ? AppConstants.successColor
                          : AppConstants.errorColor,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      userBalance > 0
                          ? 'You are owed ${context.read<SettingsProvider>().currencySymbol}${userBalance.toStringAsFixed(2)}'
                          : 'You owe ${context.read<SettingsProvider>().currencySymbol}${userBalance.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: userBalance > 0
                            ? AppConstants.successColor
                            : AppConstants.errorColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 14, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Go to the Settle Up tab to clear your balance first.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Group'),
        content: Text('Are you sure you want to leave "${group.groupName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final success = await context.read<GroupProvider>().leaveGroup(
      groupId: group.groupId,
      userId: userId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Left group' : 'Failed to leave'),
          backgroundColor: success
              ? AppConstants.successColor
              : AppConstants.errorColor,
        ),
      );
    }
  }

  Future<void> _confirmDeleteGroup(
    BuildContext context,
    GroupModel group,
    String userId,
  ) async {
    final settlementService = SettlementService();
    final balances = await settlementService.calculateBalances(group.groupId);
    final unsettled =
        balances.entries.where((e) => e.value.abs() > 0.01).toList();

    if (unsettled.isNotEmpty && context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text('Cannot Delete Group',
                    style: TextStyle(fontSize: 17)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All balances must be ${context.read<SettingsProvider>().currencySymbol}0.00 before deleting "${group.groupName}". '
                '${unsettled.length} member${unsettled.length > 1 ? 's have' : ' has'} outstanding balances:',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...unsettled.map((e) {
                final amount = e.value;
                final isOwed = amount > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isOwed
                            ? Icons.arrow_circle_up
                            : Icons.arrow_circle_down,
                        size: 16,
                        color: isOwed
                            ? AppConstants.successColor
                            : AppConstants.errorColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '…${e.key.substring(e.key.length > 6 ? e.key.length - 6 : 0)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ),
                      Text(
                        isOwed
                            ? '+${context.read<SettingsProvider>().currencySymbol}${amount.toStringAsFixed(2)}'
                            : '−${context.read<SettingsProvider>().currencySymbol}${amount.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 14, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Open the group → Settle Up tab to clear all balances.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Group'),
        content: Text(
          'Permanently delete "${group.groupName}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppConstants.errorColor),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final success = await context.read<GroupProvider>().deleteGroup(
      groupId: group.groupId,
      userId: userId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Group deleted' : 'Failed to delete'),
          backgroundColor: success
              ? AppConstants.successColor
              : AppConstants.errorColor,
        ),
      );
    }
  }

  void _showGroupOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: AppConstants.primaryColor,
                  ),
                ),
                title: const Text('Create Group'),
                subtitle: const Text('Start a new expense group'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateGroupScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.login, color: Colors.orange),
                ),
                title: const Text('Join Group'),
                subtitle: const Text('Enter 6-digit code to join'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JoinGroupScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
