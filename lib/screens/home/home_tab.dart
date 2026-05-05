import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import '../../utils/constants.dart';
import '../group/group_details_screen.dart';
import '../group/create_group_screen.dart';
import '../group/join_group_screen.dart';
import '../group/scan_receipt_screen.dart';
import '../group/add_expense_screen.dart';
import 'app_menu.dart';
import '../../providers/notification_provider.dart';
import '../../providers/settings_provider.dart';
import '../notifications/notification_center_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, double> _groupBalances = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllBalances());
  }

  Future<void> _loadAllBalances() async {
    final groups = context.read<GroupProvider>().groups;
    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null || groups.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    final Map<String, double> balances = {};

    for (final group in groups) {
      try {
        final snapshot = await firestore
            .collection('groups')
            .doc(group.groupId)
            .collection('expenses')
            .get();
        double balance = 0;
        for (final doc in snapshot.docs) {
          final expense = ExpenseModel.fromFirestore(doc);
          if (expense.paidBy == userId) balance += expense.totalAmount;
          for (final split in expense.splits) {
            if (split.userId == userId) balance -= split.amount;
          }
        }
        balances[group.groupId] = balance;
      } catch (_) {
        balances[group.groupId] = 0;
      }
    }
    if (mounted) setState(() => _groupBalances = balances);
  }

  double get _totalOwed => _groupBalances.values
      .where((b) => b < 0)
      .fold(0.0, (acc, b) => acc + b.abs());
  double get _totalOwedToYou =>
      _groupBalances.values.where((b) => b > 0).fold(0.0, (acc, b) => acc + b);

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final groups = context.watch<GroupProvider>().groups;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadAllBalances,
        color: AppConstants.primaryColor,
        child: CustomScrollView(
          slivers: [
            _buildHeader(user?.name ?? 'User'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildBalanceSummary(),
                    const SizedBox(height: 24),
                    _buildQuickActions(),
                    const SizedBox(height: 24),
                    const Text(
                      'Your Groups',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            _buildGroupsList(groups),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String userName) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: AppConstants.primaryColor,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00796B), AppConstants.primaryColor],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  // App menu (left)
                  IconButton(
                    onPressed: () => showAppMenu(context),
                    icon: const Icon(
                      Icons.menu_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  // Greeting (center)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Good ${_getGreeting()}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Notification bell with unread badge
                  _NotificationBell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationCenterScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceSummary() {
    final net = _totalOwedToYou - _totalOwed;
    final cs = context.read<SettingsProvider>().currencySymbol;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _balanceItem(
                  'You owe',
                  _totalOwed,
                  AppConstants.errorColor,
                  Icons.arrow_upward_rounded,
                ),
              ),
              Container(width: 1, height: 50, color: Colors.grey[200]),
              Expanded(
                child: _balanceItem(
                  'You\'re owed',
                  _totalOwedToYou,
                  AppConstants.successColor,
                  Icons.arrow_downward_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color:
                  (net >= 0
                          ? AppConstants.successColor
                          : AppConstants.errorColor)
                      .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  net >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: net >= 0
                      ? AppConstants.successColor
                      : AppConstants.errorColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Net: ${net >= 0 ? '+' : '-'}$cs${net.abs().toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: net >= 0
                        ? AppConstants.successColor
                        : AppConstants.errorColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceItem(String label, double amount, Color color, IconData icon) {
    final cs = context.read<SettingsProvider>().currencySymbol;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$cs${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _actionCard(
                Icons.document_scanner_rounded,
                'Scan\nReceipt',
                const Color(0xFF5C6BC0),
                _handleScanReceipt,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                Icons.add_circle_outline_rounded,
                'Add\nExpense',
                AppConstants.primaryColor,
                _handleAddExpense,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                Icons.group_add_rounded,
                'Create\nGroup',
                const Color(0xFFFF7043),
                _handleCreateGroup,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                Icons.link_rounded,
                'Join\nGroup',
                const Color(0xFF42A5F5),
                _handleJoinGroup,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionCard(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<ImageSource?> _pickScanSource() {
    final completer = Completer<ImageSource?>();
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
              const Text(
                'Select Image Source',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppConstants.primaryColor,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Camera'),
                subtitle: const Text('Take a photo of the receipt'),
                onTap: () {
                  Navigator.pop(ctx);
                  completer.complete(ImageSource.camera);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[600],
                  child: const Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('Gallery'),
                subtitle: const Text('Choose from your photos'),
                onTap: () {
                  Navigator.pop(ctx);
                  completer.complete(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  Future<void> _handleScanReceipt() async {
    final groups = context.read<GroupProvider>().groups;
    final userId = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (groups.isEmpty) {
      _noGroups();
      return;
    }

    Future<void> launchScan(GroupModel g) async {
      final source = await _pickScanSource();
      if (source == null || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final groupName = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => ScanReceiptScreen(
            group: g,
            currentUserId: userId,
            initialSource: source,
          ),
        ),
      );
      if (groupName != null && mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Expense added to "$groupName" successfully!'),
          backgroundColor: AppConstants.successColor,
        ));
      }
    }

    if (groups.length == 1) {
      await launchScan(groups.first);
      return;
    }
    _pickGroup('Scan receipt for which group?', launchScan);
  }

  void _handleAddExpense() {
    final groups = context.read<GroupProvider>().groups;
    final userId = context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (groups.isEmpty) {
      _noGroups();
      return;
    }
    if (groups.length == 1) {
      _expenseChoice(groups.first, userId);
      return;
    }
    _pickGroup('Add expense to which group?', (g) => _expenseChoice(g, userId));
  }

  void _expenseChoice(GroupModel group, String userId) {
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
                'Add expense to ${group.groupName}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppConstants.primaryColor,
                  child: Icon(Icons.document_scanner, color: Colors.white),
                ),
                title: const Text('Scan Receipt'),
                subtitle: const Text('Use OCR to extract data'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  final source = await _pickScanSource();
                  if (source == null || !mounted) return;
                  final groupName = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScanReceiptScreen(
                        group: group,
                        currentUserId: userId,
                        initialSource: source,
                      ),
                    ),
                  );
                  if (groupName != null && mounted) {
                    messenger.showSnackBar(SnackBar(
                      content: Text('Expense added to "$groupName" successfully!'),
                      backgroundColor: AppConstants.successColor,
                    ));
                  }
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[600],
                  child: const Icon(Icons.edit, color: Colors.white),
                ),
                title: const Text('Manual Entry'),
                subtitle: const Text('Enter details manually'),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  final groupName = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddExpenseScreen(group: group, currentUserId: userId),
                    ),
                  );
                  if (groupName != null && mounted) {
                    messenger.showSnackBar(SnackBar(
                      content: Text('Expense added to "$groupName" successfully!'),
                      backgroundColor: AppConstants.successColor,
                    ));
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCreateGroup() async {
    final messenger = ScaffoldMessenger.of(context);
    final groupName = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    if (groupName != null && mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('Group "$groupName" created successfully!'),
        backgroundColor: AppConstants.successColor,
      ));
    }
  }

  Future<void> _handleJoinGroup() async {
    final messenger = ScaffoldMessenger.of(context);
    final groupName = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const JoinGroupScreen()),
    );
    if (groupName != null && mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('Joined "$groupName" successfully!'),
        backgroundColor: AppConstants.successColor,
      ));
    }
  }

  void _noGroups() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Create a group first'),
      backgroundColor: AppConstants.errorColor,
    ),
  );

  void _pickGroup(String title, void Function(GroupModel) onPick) {
    final groups = context.read<GroupProvider>().groups;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.6;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SafeArea(
            child: SingleChildScrollView(
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
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...groups.map(
                      (g) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppConstants.primaryColor.withValues(
                            alpha: 0.1,
                          ),
                          child: Text(
                            g.groupName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppConstants.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(g.groupName),
                        subtitle: Text('${g.memberCount} members'),
                        onTap: () {
                          Navigator.pop(ctx);
                          onPick(g);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupsList(List<GroupModel> groups) {
    if (groups.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(Icons.group_outlined, size: 56, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text(
                'No groups yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _groupCard(groups[i]),
          childCount: groups.length,
        ),
      ),
    );
  }

  Widget _groupCard(GroupModel group) {
    final balance = _groupBalances[group.groupId] ?? 0;
    final pos = balance >= 0;
    final cs = context.read<SettingsProvider>().currencySymbol;
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
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      group.groupName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 20,
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
                          fontSize: 15,
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
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${pos && balance != 0 ? '+' : ''}$cs${balance.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: balance == 0
                            ? Colors.grey[500]
                            : pos
                            ? AppConstants.successColor
                            : AppConstants.errorColor,
                      ),
                    ),
                    Text(
                      balance == 0
                          ? 'settled'
                          : pos
                          ? 'owed to you'
                          : 'you owe',
                      style: TextStyle(
                        fontSize: 11,
                        color: balance == 0
                            ? Colors.grey[400]
                            : pos
                            ? AppConstants.successColor
                            : AppConstants.errorColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

// ── Notification bell with unread-count badge ─────────────────────────────

class _NotificationBell extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<NotificationProvider>().unreadCount;

    return IconButton(
      onPressed: onTap,
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_outlined,
            color: Colors.white,
            size: 26,
          ),
          if (count > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
