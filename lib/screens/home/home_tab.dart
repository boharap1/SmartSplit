import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import '../../models/user_model.dart';
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
import '../profile/profile_screen.dart';
import 'settle_up_screen.dart';

class HomeTab extends StatefulWidget {
  final VoidCallback? onSettleUp;
  const HomeTab({super.key, this.onSettleUp});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const _heroGreen = Color(0xFF0C2B22);
  static const double _cardH = 118;
  static const double _overlapPx = 60; // cards bisect hero by this many px

  Map<String, double> _groupBalances = {};

  final Map<String, StreamSubscription<QuerySnapshot>> _expenseSubs = {};
  final Map<String, List<ExpenseModel>> _expensesByGroup = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final gp = context.read<GroupProvider>();
      _syncWithGroups(gp.groups);
      gp.addListener(_onGroupsChanged);
    });
  }

  void _onGroupsChanged() {
    _syncWithGroups(context.read<GroupProvider>().groups);
  }

  void _syncWithGroups(List<GroupModel> groups) {
    final currentIds = groups.map((g) => g.groupId).toSet();

    for (final gId in _expenseSubs.keys.toList()) {
      if (!currentIds.contains(gId)) {
        _expenseSubs.remove(gId)?.cancel();
        _expensesByGroup.remove(gId);
      }
    }

    for (final group in groups) {
      if (!_expenseSubs.containsKey(group.groupId)) {
        _subscribeGroupExpenses(group.groupId);
      }
    }

    _recomputeBalances();
  }

  void _subscribeGroupExpenses(String groupId) {
    _expenseSubs[groupId] = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .snapshots()
        .listen(
      (snap) {
        _expensesByGroup[groupId] =
            snap.docs.map(ExpenseModel.fromFirestore).toList();
        _recomputeBalances();
      },
      onError: (_) {},
    );
  }

  void _recomputeBalances() {
    if (!mounted) return;

    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null) return;

    final balances = <String, double>{};

    for (final entry in _expensesByGroup.entries) {
      double balance = 0;

      for (final expense in entry.value) {
        if (expense.paidBy == userId) {
          balance += expense.totalAmount;
        }

        for (final split in expense.splits) {
          if (split.userId == userId) {
            balance -= split.amount;
          }
        }
      }

      balances[entry.key] = balance;
    }

    setState(() => _groupBalances = balances);
  }

  Future<void> _loadAllBalances() async {
    final oldSubscriptions = _expenseSubs.values.toList();
    _expenseSubs.clear();
    _expensesByGroup.clear();

    await Future.wait(oldSubscriptions.map((s) => s.cancel()));

    if (!mounted) return;

    _syncWithGroups(context.read<GroupProvider>().groups);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    context.read<GroupProvider>().removeListener(_onGroupsChanged);

    for (final subscription in _expenseSubs.values) {
      subscription.cancel();
    }

    super.dispose();
  }

  double get _totalOwed => _groupBalances.values
      .where((b) => b < 0)
      .fold(0.0, (acc, b) => acc + b.abs());

  double get _totalOwedToYou => _groupBalances.values
      .where((b) => b > 0)
      .fold(0.0, (acc, b) => acc + b);
  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final groups = context.watch<GroupProvider>().groups;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: RefreshIndicator(
        onRefresh: _loadAllBalances,
        color: AppConstants.primaryColor,
        displacement: 160,
        child: CustomScrollView(
          slivers: [
            // Hero + top 2 cards bisecting the hero bottom
            SliverToBoxAdapter(child: _buildHeroWithBisect(user, groups)),
            // Bottom 2 action cards
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _buildBottomActionRow(groups),
              ),
            ),
            // Groups header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                child: _buildGroupsHeader(groups),
              ),
            ),
            // Groups horizontal scroll
            SliverToBoxAdapter(child: _buildGroupsRow(groups)),
            // Account section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: _buildAccountSection(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  // ── Hero + bisect Stack ───────────────────────────────────────────────────

  Widget _buildHeroWithBisect(UserModel? user, List<GroupModel> groups) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Column: hero + extra space so Stack is tall enough for card overlap
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHero(user, groups),
            const SizedBox(height: _overlapPx),
          ],
        ),
        // Top 2 cards — bottom edge at Stack bottom, top edge bisects hero
        Positioned(
          bottom: 0,
          left: 16,
          right: 16,
          height: _cardH,
          child: _buildTopActionRow(groups),
        ),
      ],
    );
  }

  Widget _buildHero(UserModel? user, List<GroupModel> groups) {
    final userName = user?.name ?? 'User';
    final initials = _getInitials(userName);
    final hasPhoto = user?.hasProfilePicture ?? false;
    final cs = context.read<SettingsProvider>().currencySymbol;
    final net = _totalOwedToYou - _totalOwed;
    final isNeg = net < 0;
    final absNet = net.abs();
    final whole = absNet.truncate();
    final cents =
        ((absNet - whole) * 100).round().toString().padLeft(2, '0');
    final wholeStr = whole.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(32),
        bottomRight: Radius.circular(32),
      ),
      child: Container(
        color: _heroGreen,
        child: Stack(
          children: [
            // ── Premium glassmorphism glow blobs ──────────────────────────
            // Top-right teal glow
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0.9, -0.85),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF26A69A).withValues(alpha: 0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Bottom-left emerald glow
            Positioned.fill(
              child: Align(
                alignment: const Alignment(-0.85, 0.6),
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF1B5E20).withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Center warm ambient fill
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0.1, 0.1),
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF00695C).withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Content ───────────────────────────────────────────────────
            SafeArea(
              bottom: false,
              child: Padding(
                // bottom: 68 ensures YOU OWE section clears the bisecting cards
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 68),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top bar ─────────────────────────────────────────────
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => showAppMenu(context),
                          child: CircleAvatar(
                            radius: 21,
                            backgroundColor: const Color(0xFFE8927C),
                            backgroundImage: hasPhoto
                                ? NetworkImage(user!.profilePicture!)
                                : null,
                            child: hasPhoto
                                ? null
                                : Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Good ${_getGreeting()},',
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                userName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // QR — glass pill button
                        _GlassIconButton(
                          icon: Icons.qr_code_scanner_rounded,
                          onTap: _handleQrCode,
                        ),
                        const SizedBox(width: 6),
                        // Bell — glass pill button
                        _GlassBellButton(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const NotificationCenterScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── Net balance label ──────────────────────────────────
                    Text(
                      'NET BALANCE  ·  ALL GROUPS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // ── Big balance ────────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isNeg ? '-' : ''}$cs$wholeStr',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 46,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            '.$cents',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── Group chip ─────────────────────────────────────────
                    if (groups.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.arrow_downward_rounded,
                              size: 11,
                              color: Color(0xFF4CAF50),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              groups.first.groupName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '  ·  ${groups.length} group${groups.length != 1 ? 's' : ''}',
                              style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── Proportional owe / owed bar ────────────────────────
                    _buildOwedBar(),

                    const SizedBox(height: 14),

                    // ── You owe / You're owed ──────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'YOU OWE',
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$cs${_totalOwed.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(0xFFEF9A9A),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "YOU'RE OWED",
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$cs${_totalOwedToYou.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(0xFF80CBC4),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
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
          ],
        ),
      ),
    );
  }

  Widget _buildOwedBar() {
    final total = _totalOwed + _totalOwedToYou;
    final oweRatio =
        total > 0 ? (_totalOwed / total).clamp(0.05, 0.95) : 0.5;
    final owedRatio = 1.0 - oweRatio;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5,
              child: Row(
                children: [
                  Flexible(
                    flex: (oweRatio * 1000).round(),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFE53935), Color(0xFFEF9A9A)],
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    flex: (owedRatio * 1000).round(),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF80CBC4), Color(0xFF4CAF50)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Quick action rows ─────────────────────────────────────────────────────

  Widget _buildTopActionRow(List<GroupModel> groups) {
    return Row(
      children: [
        // Add expense — premium dark emerald card
        Expanded(
          child: _QuickActionCard(
            onTap: _handleAddExpense,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E4835), Color(0xFF0A2318)],
            ),
            icon: Icons.add_rounded,
            iconBg: Colors.white.withValues(alpha: 0.2),
            iconGlow: Colors.white,
            haloColor: Colors.white,
            title: 'Add expense',
            subtitle: 'Split with anyone',
            titleColor: Colors.white,
            subtitleColor: Colors.white,
            subtitleOpacity: 0.55,
            chevronBg: Colors.white.withValues(alpha: 0.15),
            chevronIconColor: Colors.white,
            isDark: true,
          ),
        ),
        const SizedBox(width: 12),
        // Scan receipt — indigo tint with AI badge
        Expanded(
          child: _QuickActionCard(
            onTap: _handleScanReceipt,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEDE7FF), Color(0xFFF5F0FF), Colors.white],
            ),
            icon: Icons.receipt_long_rounded,
            iconBg: const Color(0xFF7B61FF),
            iconGlow: const Color(0xFF7B61FF),
            haloColor: const Color(0xFF7B61FF),
            title: 'Scan receipt',
            subtitle: 'All line items',
            titleColor: Colors.black87,
            subtitleColor: Color(0xFF7B61FF),
            subtitleOpacity: 0.7,
            chevronBg: const Color(0xFF7B61FF),
            chevronIconColor: Colors.white,
            showAiBadge: true,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionRow(List<GroupModel> groups) {
    final settleCount = _groupBalances.values.where((b) => b < 0).length;
    return SizedBox(
      height: _cardH,
      child: Row(
        children: [
          // Join group — coral tint
          Expanded(
            child: _QuickActionCard(
              onTap: _handleJoinGroup,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFBE9E7), Color(0xFFFFF3EE), Colors.white],
              ),
              icon: Icons.group_add_rounded,
              iconBg: const Color(0xFFFF7043),
              iconGlow: const Color(0xFFFF7043),
              haloColor: const Color(0xFFFF7043),
              title: 'Join group',
              subtitle: 'QR or link',
              titleColor: Colors.black87,
              subtitleColor: Color(0xFFFF7043),
              subtitleOpacity: 0.75,
              chevronBg: const Color(0xFFFF7043),
              chevronIconColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          // Settle up — teal/emerald tint
          Expanded(
            child: _QuickActionCard(
              onTap: _handleSettleUp,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE0F2F1), Color(0xFFEFF8F7), Colors.white],
              ),
              icon: Icons.currency_exchange_rounded,
              iconBg: AppConstants.primaryColor,
              iconGlow: AppConstants.primaryColor,
              haloColor: AppConstants.primaryColor,
              title: 'Settle up',
              subtitle: settleCount > 0
                  ? '$settleCount ready to clear'
                  : 'All settled',
              titleColor: Colors.black87,
              subtitleColor: AppConstants.primaryColor,
              subtitleOpacity: 0.75,
              chevronBg: AppConstants.primaryColor,
              chevronIconColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Groups section ────────────────────────────────────────────────────────

  Widget _buildGroupsHeader(List<GroupModel> groups) {
    return Row(
      children: [
        const Text(
          'Your groups',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        if (groups.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${groups.length} active',
              style: const TextStyle(
                color: AppConstants.primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGroupsRow(List<GroupModel> groups) {
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_outlined,
                    size: 40, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('No groups yet',
                    style: TextStyle(color: Colors.grey[500])),
              ],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _buildGroupCard(groups[i]),
      ),
    );
  }

  Widget _buildGroupCard(GroupModel group) {
    final balance = _groupBalances[group.groupId] ?? 0;
    final userId =
        context.read<AuthProvider>().firebaseUser?.uid ?? '';
    final isOwner = group.createdBy == userId;
    final isOwed = balance > 0;
    final isSettled = balance == 0;

    final palette = [
      const Color(0xFF4CAF50),
      const Color(0xFFFF7043),
      const Color(0xFF42A5F5),
      const Color(0xFFAB47BC),
      const Color(0xFF26A69A),
    ];
    final c = palette[group.groupName.hashCode.abs() % palette.length];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              GroupDetailsScreen(groupId: group.groupId),
        ),
      ),
      child: Container(
        width: 158,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    child: Text(
                      group.groupName[0].toUpperCase(),
                      style: TextStyle(
                        color: c,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (isOwner)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'OWNER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              group.groupName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${group.memberCount} member${group.memberCount != 1 ? 's' : ''}',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            const Spacer(),
            SizedBox(
              height: 28,
              child: CustomPaint(
                size: const Size(double.infinity, 28),
                painter: _SparklinePainter(
                  color: isOwed
                      ? const Color(0xFF4CAF50)
                      : Colors.grey.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isSettled
                  ? 'SETTLED UP'
                  : isOwed
                  ? 'OWED TO YOU'
                  : 'YOU OWE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: isSettled
                    ? Colors.grey[400]
                    : isOwed
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFE57373),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Account section ───────────────────────────────────────────────────────

  Widget _buildAccountSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Account',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ProfileScreen()),
                ),
                child: Row(
                  children: [
                    Text(
                      'Manage',
                      style: TextStyle(
                        color: AppConstants.primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppConstants.primaryColor,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _AccountTile(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                color: const Color(0xFF42A5F5),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ProfileScreen()),
                ),
              ),
              const SizedBox(width: 10),
              _AccountTile(
                icon: Icons.notifications_outlined,
                label: 'Alerts',
                color: const Color(0xFFFF7043),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const NotificationCenterScreen()),
                ),
              ),
              const SizedBox(width: 10),
              _AccountTile(
                icon: Icons.shield_outlined,
                label: 'Security',
                color: const Color(0xFF7B61FF),
                onTap: () => _showComingSoon('Security settings'),
              ),
              const SizedBox(width: 10),
              _AccountTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                color: AppConstants.primaryColor,
                onTap: () => showAppMenu(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Action handlers ───────────────────────────────────────────────────────

  void _handleQrCode() => _handleJoinGroup();

  void _handleSettleUp() {
    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null) return;
    final groups = context.read<GroupProvider>().groups;
    if (groups.isEmpty) {
      _showNoGroupsPrompt('settle up');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettleUpScreen(
          groupBalances: _groupBalances,
          groups: groups,
          currentUserId: userId,
        ),
      ),
    );
  }

  void _handleAddExpense() {
    final groups = context.read<GroupProvider>().groups;
    final userId =
        context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (groups.isEmpty) {
      _showNoGroupsPrompt('add expenses');
      return;
    }
    if (groups.length == 1) {
      _expenseChoice(groups.first, userId);
      return;
    }
    _pickGroup(
        'Add expense to which group?', (g) => _expenseChoice(g, userId));
  }

  void _handleScanReceipt() {
    final groups = context.read<GroupProvider>().groups;
    final userId =
        context.read<AuthProvider>().firebaseUser?.uid ?? '';
    if (groups.isEmpty) {
      _showNoGroupsPrompt('scan a receipt');
      return;
    }
    if (groups.length == 1) {
      _launchScanReceipt(groups.first, userId);
      return;
    }
    _pickGroup(
        'Scan receipt for which group?',
        (g) => _launchScanReceipt(g, userId));
  }

  Future<void> _launchScanReceipt(
      GroupModel group, String userId) async {
    final source = await _pickScanSource();
    if (source == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
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
        content:
            Text('Expense added to "$groupName" successfully!'),
        backgroundColor: AppConstants.successColor,
      ));
    }
  }

  void _expenseChoice(GroupModel group, String userId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 16),
              Text(
                'Add expense to ${group.groupName}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppConstants.primaryColor,
                  child: Icon(Icons.document_scanner,
                      color: Colors.white),
                ),
                title: const Text('Scan Receipt'),
                subtitle: const Text('Use OCR to extract data'),
                onTap: () async {
                  final messenger =
                      ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  final source = await _pickScanSource();
                  if (source == null || !mounted) return;
                  final groupName =
                      await Navigator.push<String>(
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
                      content: Text(
                          'Expense added to "$groupName" successfully!'),
                      backgroundColor:
                          AppConstants.successColor,
                    ));
                  }
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[600],
                  child: const Icon(Icons.edit,
                      color: Colors.white),
                ),
                title: const Text('Manual Entry'),
                subtitle:
                    const Text('Enter details manually'),
                onTap: () async {
                  final messenger =
                      ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  final groupName =
                      await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddExpenseScreen(
                          group: group,
                          currentUserId: userId),
                    ),
                  );
                  if (groupName != null && mounted) {
                    messenger.showSnackBar(SnackBar(
                      content: Text(
                          'Expense added to "$groupName" successfully!'),
                      backgroundColor:
                          AppConstants.successColor,
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

  Future<ImageSource?> _pickScanSource() {
    final completer = Completer<ImageSource?>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 16),
              const Text(
                'Select Image Source',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppConstants.primaryColor,
                  child: Icon(Icons.camera_alt,
                      color: Colors.white),
                ),
                title: const Text('Camera'),
                subtitle:
                    const Text('Take a photo of the receipt'),
                onTap: () {
                  Navigator.pop(ctx);
                  completer.complete(ImageSource.camera);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[600],
                  child: const Icon(Icons.photo_library,
                      color: Colors.white),
                ),
                title: const Text('Gallery'),
                subtitle:
                    const Text('Choose from your photos'),
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

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature — coming soon'),
      backgroundColor: AppConstants.primaryColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showNoGroupsPrompt(String featureName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group_outlined,
                    color: AppConstants.primaryColor, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('No Groups Yet',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'You need to be part of a group to $featureName.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Join Group'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            AppConstants.primaryColor,
                        side: const BorderSide(
                            color: AppConstants.primaryColor),
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final messenger =
                            ScaffoldMessenger.of(context);
                        final name =
                            await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const JoinGroupScreen()),
                        );
                        if (name != null && mounted) {
                          messenger.showSnackBar(SnackBar(
                            content: Text(
                                'Joined "$name" successfully!'),
                            backgroundColor:
                                AppConstants.successColor,
                          ));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.group_add_rounded),
                      label: const Text('Create Group'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _handleCreateGroup();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickGroup(
    String title,
    void Function(GroupModel) onPick, {
    List<GroupModel>? groups,
  }) {
    groups ??= context.read<GroupProvider>().groups;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
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
                    _sheetHandle(),
                    const SizedBox(height: 16),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...groups!.map(
                      (g) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppConstants
                              .primaryColor
                              .withValues(alpha: 0.1),
                          child: Text(
                            g.groupName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppConstants.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(g.groupName),
                        subtitle:
                            Text('${g.memberCount} members'),
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sheetHandle() => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      );

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}

// ── Quick Action Card ─────────────────────────────────────────────────────

class _QuickActionCard extends StatelessWidget {
  final VoidCallback onTap;
  final LinearGradient gradient;
  final IconData icon;
  final Color iconBg;
  final Color iconGlow;
  final Color haloColor;
  final String title;
  final String subtitle;
  final Color titleColor;
  final Color subtitleColor;
  final double subtitleOpacity;
  final Color chevronBg;
  final Color chevronIconColor;
  final bool showAiBadge;
  final bool isDark;

  const _QuickActionCard({
    required this.onTap,
    required this.gradient,
    required this.icon,
    required this.iconBg,
    required this.iconGlow,
    required this.haloColor,
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.subtitleColor,
    this.subtitleOpacity = 1.0,
    required this.chevronBg,
    required this.chevronIconColor,
    this.showAiBadge = false,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : haloColor)
                  .withValues(alpha: isDark ? 0.4 : 0.22),
              blurRadius: 18,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // ── Decorative corner halo (radial fade — soft) ─────────
              Positioned(
                top: -28,
                right: -28,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        haloColor.withValues(
                            alpha: isDark ? 0.18 : 0.22),
                        haloColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Small offset secondary blob ──────────────────────────
              Positioned(
                top: 22,
                right: 28,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        haloColor.withValues(
                            alpha: isDark ? 0.09 : 0.13),
                        haloColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Glassy inset highlight (dark card only) ─────────────
              if (isDark)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.13),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              // ── Main content ────────────────────────────────────────
              Positioned.fill(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon + optional AI badge
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius:
                                  BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: iconGlow
                                      .withValues(alpha: 0.45),
                                  blurRadius: 14,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(icon,
                                color: Colors.white, size: 20),
                          ),
                          const Spacer(),
                          if (showAiBadge)
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF7B61FF)
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                      Icons
                                          .auto_awesome_rounded,
                                      size: 9,
                                      color:
                                          Color(0xFF7B61FF)),
                                  SizedBox(width: 2),
                                  Text(
                                    'AI',
                                    style: TextStyle(
                                      color: Color(0xFF7B61FF),
                                      fontSize: 9,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      // Title + subtitle + chevron pill
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: titleColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: subtitleColor
                                        .withValues(
                                            alpha:
                                                subtitleOpacity),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Chevron pill affordance cue
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 5),
                            decoration: BoxDecoration(
                              color: chevronBg,
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 13,
                              color: chevronIconColor,
                            ),
                          ),
                        ],
                      ),
                    ],
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

// ── Account tile ──────────────────────────────────────────────────────────

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AccountTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sparkline painter ─────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final Color color;
  const _SparklinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(0, size.height * 0.65)
      ..cubicTo(
        size.width * 0.2, size.height * 0.85,
        size.width * 0.3, size.height * 0.2,
        size.width * 0.5, size.height * 0.45,
      )
      ..cubicTo(
        size.width * 0.65, size.height * 0.65,
        size.width * 0.78, size.height * 0.1,
        size.width, size.height * 0.28,
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.color != color;
}

// ── Glass icon button (QR / generic) ─────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Icon(icon,
            color: Colors.white.withValues(alpha: 0.88), size: 20),
      ),
    );
  }
}

// ── Glass bell button (with unread badge) ─────────────────────────────────

class _GlassBellButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBellButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<NotificationProvider>().unreadCount;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(Icons.notifications_outlined,
                color: Colors.white.withValues(alpha: 0.88), size: 20),
            if (count > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
