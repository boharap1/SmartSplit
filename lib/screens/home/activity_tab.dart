import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../providers/settings_provider.dart';
import '../../services/settlement_service.dart';
import '../group/create_group_screen.dart';
import '../group/join_group_screen.dart';
import '../group/group_details_screen.dart';

class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key});

  @override
  State<ActivityTab> createState() => ActivityTabState();
}

class ActivityTabState extends State<ActivityTab> {
  Map<String, double> _groupBalances = {};
  final Map<String, String> _userNames = {};
  List<_FeedItem> _feedItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gp = context.read<GroupProvider>();
      if (gp.groups.isNotEmpty) {
        _loadData();
      } else {
        gp.addListener(_onGroupsChanged);
      }
    });
  }

  void _onGroupsChanged() {
    final gp = context.read<GroupProvider>();
    if (gp.groups.isNotEmpty && _isLoading) {
      gp.removeListener(_onGroupsChanged);
      _loadData();
    }
  }

  @override
  void dispose() {
    context.read<GroupProvider>().removeListener(_onGroupsChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final groups = context.read<GroupProvider>().groups;
    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null || groups.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final Map<String, double> balances = {};
    final Set<String> userIds = {};
    final List<_FeedItem> items = [];

    for (final group in groups) {
      try {
        // Expenses
        final expSnap = await firestore
            .collection('groups')
            .doc(group.groupId)
            .collection('expenses')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        double bal = 0;
        for (final doc in expSnap.docs) {
          final e = ExpenseModel.fromFirestore(doc);
          userIds.add(e.paidBy);
          if (e.paidBy == userId) bal += e.totalAmount;
          for (final s in e.splits) {
            if (s.userId == userId) bal -= s.amount;
          }
          items.add(_FeedItem(
            type: _FeedType.expense,
            groupId: group.groupId,
            groupName: group.groupName,
            date: e.createdAt,
            amount: e.totalAmount,
            description: e.description,
            actorId: e.paidBy,
            category: e.category,
          ));
        }
        balances[group.groupId] = bal;

        // Group events (join / leave / created)
        final eventSnap = await firestore
            .collection('groups')
            .doc(group.groupId)
            .collection('events')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        bool hasCreatedEvent = false;
        for (final doc in eventSnap.docs) {
          final d = doc.data();
          final type = d['type'] as String? ?? '';
          final uid = d['userId'] as String? ?? '';
          final name = d['userName'] as String? ?? 'Someone';
          final ts = d['createdAt'];
          if (ts == null) continue;
          final date = (ts as Timestamp).toDate();
          if (uid.isNotEmpty) userIds.add(uid);

          _FeedType? feedType;
          if (type == 'member_joined') {
            feedType = _FeedType.memberJoined;
          } else if (type == 'member_left') {
            feedType = _FeedType.memberLeft;
          } else if (type == 'group_created') {
            feedType = _FeedType.groupCreated;
            hasCreatedEvent = true;
          }
          if (feedType == null) continue;

          items.add(_FeedItem(
            type: feedType,
            groupId: group.groupId,
            groupName: group.groupName,
            date: date,
            actorId: uid,
            actorName: name,
          ));
        }

        // Synthetic group_created event derived from the group model when none
        // exists in the events subcollection (covers groups created before event
        // logging was introduced).
        if (!hasCreatedEvent) {
          items.add(_FeedItem(
            type: _FeedType.groupCreated,
            groupId: group.groupId,
            groupName: group.groupName,
            date: group.createdAt,
          ));
        }
      } catch (_) {}
    }

    // Resolve user names in batches of 10 (Firestore whereIn limit)
    final idList = userIds.toList();
    for (var i = 0; i < idList.length; i += 10) {
      final batch = idList.sublist(i, (i + 10).clamp(0, idList.length));
      try {
        final snap = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snap.docs) {
          _userNames[doc.id] = UserModel.fromFirestore(doc).name;
        }
      } catch (_) {}
    }

    items.sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _groupBalances = balances;
        _feedItems = items;
        _isLoading = false;
      });
    }
  }

  String _resolveActor(_FeedItem item) {
    final currentId = context.read<AuthProvider>().firebaseUser?.uid;
    if (item.actorId != null && item.actorId!.isNotEmpty) {
      if (item.actorId == currentId) return 'You';
      return _userNames[item.actorId!] ?? item.actorName ?? 'Someone';
    }
    return item.actorName ?? 'Someone';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupProvider>().groups;
    final currentUserId =
        context.watch<AuthProvider>().firebaseUser?.uid ?? '';

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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppConstants.primaryColor,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppConstants.primaryColor,
              child: groups.isEmpty
                  ? _buildEmptyState()
                  : CustomScrollView(
                      slivers: [
                        _buildGroupsSliver(groups, currentUserId),
                        _buildActivityHeader(),
                        _feedItems.isEmpty
                            ? _buildEmptyActivity()
                            : _buildActivitySliver(),
                        const SliverToBoxAdapter(
                            child: SizedBox(height: 80)),
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showGroupOptions,
        backgroundColor: AppConstants.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ── Groups section ─────────────────────────────────────────────────────────

  Widget _buildGroupsSliver(List<GroupModel> groups, String currentUserId) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Your Groups',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${groups.length} group${groups.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppConstants.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return _groupCard(groups[i - 1], currentUserId);
          },
          childCount: groups.length + 1,
        ),
      ),
    );
  }

  Widget _groupCard(GroupModel group, String currentUserId) {
    final isOwner = group.createdBy == currentUserId;
    final bal = _groupBalances[group.groupId] ?? 0;
    final cs = context.read<SettingsProvider>().currencySymbol;
    const colors = [
      Color(0xFF5C6BC0),
      Color(0xFFFF7043),
      Color(0xFF26A69A),
      Color(0xFFAB47BC),
      Color(0xFF42A5F5),
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
              builder: (_) =>
                  GroupDetailsScreen(groupId: group.groupId),
            ),
          ),
          onLongPress: () =>
              _showGroupActions(group, isOwner, currentUserId),
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
                          Icon(Icons.people_outline,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${group.memberCount} member${group.memberCount != 1 ? 's' : ''}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isOwner) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppConstants.primaryColor
                                    .withValues(alpha: 0.1),
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${bal > 0 ? '+' : ''}$cs${bal.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: bal == 0
                            ? Colors.grey[400]
                            : bal > 0
                                ? AppConstants.successColor
                                : AppConstants.errorColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      bal == 0
                          ? 'settled'
                          : bal > 0
                              ? 'owed to you'
                              : 'you owe',
                      style: TextStyle(
                        fontSize: 11,
                        color: bal == 0
                            ? Colors.grey[400]
                            : bal > 0
                                ? AppConstants.successColor
                                : AppConstants.errorColor,
                      ),
                    ),
                  ],
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      color: Colors.grey[400], size: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onSelected: (action) => _handleGroupAction(
                      action, group, isOwner, currentUserId),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Edit Group'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'invite',
                      child: Row(children: [
                        Icon(Icons.share_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Invite / Share Code'),
                      ]),
                    ),
                    const PopupMenuDivider(),
                    if (!isOwner)
                      const PopupMenuItem(
                        value: 'leave',
                        child: Row(children: [
                          Icon(Icons.exit_to_app,
                              size: 18, color: Colors.orange),
                          SizedBox(width: 10),
                          Text('Leave Group',
                              style: TextStyle(color: Colors.orange)),
                        ]),
                      ),
                    if (isOwner)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 18,
                              color: AppConstants.errorColor),
                          SizedBox(width: 10),
                          Text('Delete Group',
                              style:
                                  TextStyle(color: AppConstants.errorColor)),
                        ]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Activity section ───────────────────────────────────────────────────────

  Widget _buildActivityHeader() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          const SizedBox(height: 4),
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 17, color: Colors.grey[500]),
                const SizedBox(width: 8),
                Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[600],
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _loadData,
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 15, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        'Refresh',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildActivitySliver() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final item = _feedItems[i];
            final showHeader =
                i == 0 || !_sameDay(item.date, _feedItems[i - 1].date);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader) ...[
                  if (i != 0) const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _dateHeader(item.date),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
                _feedCard(item),
              ],
            );
          },
          childCount: _feedItems.length,
        ),
      ),
    );
  }

  Widget _feedCard(_FeedItem item) {
    final config = _itemConfig(item);
    final cs = context.read<SettingsProvider>().currencySymbol;
    final actor = _resolveActor(item);

    final String mainTitle;
    final String subtitle;
    switch (item.type) {
      case _FeedType.expense:
        mainTitle = item.description ?? 'Expense';
        subtitle = 'Paid by $actor · ${item.groupName}';
      case _FeedType.memberJoined:
        mainTitle = '$actor joined';
        subtitle = item.groupName;
      case _FeedType.memberLeft:
        mainTitle = '$actor left';
        subtitle = item.groupName;
      case _FeedType.groupCreated:
        mainTitle = '"${item.groupName}" created';
        subtitle = item.groupName;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: config.color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(config.icon, color: config.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mainTitle,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '$subtitle · ${DateFormat('HH:mm').format(item.date)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (item.type == _FeedType.expense && item.amount != null) ...[
            const SizedBox(width: 8),
            Text(
              '$cs${item.amount!.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }



  _ItemConfig _itemConfig(_FeedItem item) {
    switch (item.type) {
      case _FeedType.expense:
        return _ItemConfig(_catIcon(item.category), AppConstants.primaryColor);
      case _FeedType.memberJoined:
        return _ItemConfig(
            Icons.person_add_outlined, AppConstants.successColor);
      case _FeedType.memberLeft:
        return _ItemConfig(Icons.person_remove_outlined, Colors.orange);
      case _FeedType.groupCreated:
        return _ItemConfig(
            Icons.group_add_outlined, const Color(0xFF5C6BC0));
    }
  }

  // ── Group action handlers ──────────────────────────────────────────────────

  void _handleGroupAction(
      String action, GroupModel group, bool isOwner, String userId) {
    switch (action) {
      case 'edit':
        _showEditDialog(group);
      case 'invite':
        _showInviteSheet(group);
      case 'leave':
        _confirmLeaveGroup(group, userId);
      case 'delete':
        _confirmDeleteGroup(group, userId);
    }
  }

  void _showGroupActions(
      GroupModel group, bool isOwner, String userId) {
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
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text(group.groupName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Group'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(group);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Invite / Share Code'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showInviteSheet(group);
                },
              ),
              const Divider(),
              if (!isOwner)
                ListTile(
                  leading: const Icon(Icons.exit_to_app,
                      color: Colors.orange),
                  title: const Text('Leave Group',
                      style: TextStyle(color: Colors.orange)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmLeaveGroup(group, userId);
                  },
                ),
              if (isOwner)
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: AppConstants.errorColor),
                  title: const Text('Delete Group',
                      style: TextStyle(color: AppConstants.errorColor)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteGroup(group, userId);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(GroupModel group) {
    final nameCtrl = TextEditingController(text: group.groupName);
    final descCtrl =
        TextEditingController(text: group.description ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Group Name',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uid =
                  context.read<AuthProvider>().firebaseUser?.uid ?? '';
              final messenger = ScaffoldMessenger.of(context);
              await context.read<GroupProvider>().updateGroup(
                    groupId: group.groupId,
                    requestingUserId: uid,
                    groupName: nameCtrl.text.trim(),
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                  );
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Group updated'),
                  backgroundColor: AppConstants.successColor,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showInviteSheet(GroupModel group) {
    final userId =
        context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null) return;
    final isAdmin = group.isAdmin(userId);
    var sheetCode =
        group.hasActiveInvite ? group.activeInviteCode : null;
    var sheetExpiry =
        group.hasActiveInvite ? group.activeInviteExpiry : null;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSS) => SafeArea(
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
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 20),
                const Text('Invite Members',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(group.groupName,
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 14)),
                const SizedBox(height: 20),
                if (sheetCode != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor
                          .withValues(alpha: 0.08),
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
                              'Expires at ${_fmtExpiry(sheetExpiry!)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppConstants.successColor),
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
                                backgroundColor:
                                    AppConstants.successColor,
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
                                setSS(() {
                                  sheetCode = result.code;
                                  sheetExpiry = DateTime.now().add(
                                      const Duration(minutes: 10));
                                });
                              }
                            },
                            icon:
                                const Icon(Icons.refresh, size: 18),
                            label: const Text('New Code'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      isAdmin
                          ? 'Generate a temporary invite code (valid 10 min).'
                          : 'No active invite code.\nAsk a group admin to generate one.',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final messenger =
                              ScaffoldMessenger.of(context);
                          final result = await context
                              .read<GroupProvider>()
                              .generateInviteCode(
                                groupId: group.groupId,
                                userId: userId,
                              );
                          if (result.code != null) {
                            setSS(() {
                              sheetCode = result.code;
                              sheetExpiry = DateTime.now().add(
                                  const Duration(minutes: 10));
                            });
                          } else if (mounted) {
                            messenger.showSnackBar(SnackBar(
                              content: Text(result.error ??
                                  'Failed to generate code'),
                              backgroundColor:
                                  AppConstants.errorColor,
                            ));
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
        ),
      ),
    );
  }

  String _fmtExpiry(DateTime expiry) {
    return '${expiry.hour.toString().padLeft(2, '0')}:'
        '${expiry.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmLeaveGroup(
      GroupModel group, String userId) async {
    final settlementService = SettlementService();
    final balances =
        await settlementService.calculateBalances(group.groupId);
    final userBalance = balances[userId] ?? 0;

    if (!mounted) return;
    if (userBalance.abs() > 0.01) {
      final cs = context.read<SettingsProvider>().currencySymbol;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Cannot Leave Group',
                style: TextStyle(fontSize: 17)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have an outstanding balance in "${group.groupName}" that must be settled before you can leave.',
                style:
                    TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (userBalance > 0
                          ? AppConstants.successColor
                          : AppConstants.errorColor)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (userBalance > 0
                            ? AppConstants.successColor
                            : AppConstants.errorColor)
                        .withValues(alpha: 0.3),
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
                          ? 'You are owed $cs${userBalance.toStringAsFixed(2)}'
                          : 'You owe $cs${userBalance.abs().toStringAsFixed(2)}',
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
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Group'),
        content: Text(
            'Are you sure you want to leave "${group.groupName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final userName = context.read<AuthProvider>().user?.name;
    final groupProvider = context.read<GroupProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await groupProvider.leaveGroup(
      groupId: group.groupId,
      userId: userId,
      userName: userName,
    );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(success ? 'Left group' : 'Failed to leave'),
      backgroundColor:
          success ? AppConstants.successColor : AppConstants.errorColor,
    ));
    if (success) _loadData();
  }

  Future<void> _confirmDeleteGroup(
      GroupModel group, String userId) async {
    final settlementService = SettlementService();
    final balances =
        await settlementService.calculateBalances(group.groupId);
    final unsettled =
        balances.entries.where((e) => e.value.abs() > 0.01).toList();

    if (!mounted) return;
    if (unsettled.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
                child: Text('Cannot Delete Group',
                    style: TextStyle(fontSize: 17))),
          ]),
          content: Text(
            '${unsettled.length} member${unsettled.length > 1 ? 's have' : ' has'} outstanding balances in "${group.groupName}". Settle all balances before deleting.',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Group'),
        content: Text(
            'Permanently delete "${group.groupName}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppConstants.errorColor)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final groupProvider = context.read<GroupProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await groupProvider.deleteGroup(
      groupId: group.groupId,
      userId: userId,
    );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content:
          Text(success ? 'Group deleted' : 'Failed to delete'),
      backgroundColor:
          success ? AppConstants.successColor : AppConstants.errorColor,
    ));
  }

  void _showGroupOptions() {
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
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add,
                      color: AppConstants.primaryColor),
                ),
                title: const Text('Create Group'),
                subtitle: const Text('Start a new expense group'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CreateGroupScreen()),
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
                  child: const Icon(Icons.login,
                      color: Colors.orange),
                ),
                title: const Text('Join Group'),
                subtitle: const Text('Enter 6-digit code to join'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const JoinGroupScreen()),
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

  // ── Empty states ───────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color:
                    AppConstants.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_outlined,
                  size: 56, color: AppConstants.primaryColor),
            ),
            const SizedBox(height: 24),
            const Text('No Groups Yet',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Create or join a group to start.',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CreateGroupScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const JoinGroupScreen()),
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text('Join'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.primaryColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildEmptyActivity() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(Icons.history, size: 40, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                'No recent activity',
                style:
                    TextStyle(fontSize: 15, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  IconData _catIcon(String? cat) {
    switch (cat) {
      case 'Food & Drinks':
        return Icons.restaurant_rounded;
      case 'Transport':
        return Icons.directions_car_rounded;
      case 'Accommodation':
        return Icons.hotel_rounded;
      case 'Entertainment':
        return Icons.movie_rounded;
      case 'Shopping':
        return Icons.shopping_bag_rounded;
      case 'Utilities':
        return Icons.bolt_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }

  String _dateHeader(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    if (date == today) return 'Today';
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return DateFormat('EEEE, d MMM').format(d);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Data models ────────────────────────────────────────────────────────────────

enum _FeedType { expense, memberJoined, memberLeft, groupCreated }

class _FeedItem {
  final _FeedType type;
  final String groupId;
  final String groupName;
  final DateTime date;
  final String? actorId;
  final String? actorName;
  final double? amount;
  final String? description;
  final String? category;

  const _FeedItem({
    required this.type,
    required this.groupId,
    required this.groupName,
    required this.date,
    this.actorId,
    this.actorName,
    this.amount,
    this.description,
    this.category,
  });
}

class _ItemConfig {
  final IconData icon;
  final Color color;
  const _ItemConfig(this.icon, this.color);
}
