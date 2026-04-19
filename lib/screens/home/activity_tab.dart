import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/expense_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../providers/settings_provider.dart';
import '../group/settlements_screen.dart';

class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key});

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<_ActivityItem> _expenses = [];
  List<_SettlementItem> _settlements = [];
  Map<String, double> _groupBalances = {};
  final Map<String, String> _userNames = {};
  final Map<String, String> _groupNames = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final groupProvider = context.read<GroupProvider>();
      if (groupProvider.groups.isNotEmpty) {
        _loadData();
      } else {
        groupProvider.addListener(_onGroupsChanged);
      }
    });
  }

  void _onGroupsChanged() {
    final groupProvider = context.read<GroupProvider>();
    if (groupProvider.groups.isNotEmpty && _isLoading) {
      groupProvider.removeListener(_onGroupsChanged);
      _loadData();
    }
  }

  @override
  void dispose() {
    context.read<GroupProvider>().removeListener(_onGroupsChanged);
    _tabController.dispose();
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
    final List<_ActivityItem> expenses = [];
    final List<_SettlementItem> settlements = [];
    final Map<String, double> balances = {};
    final Set<String> userIds = {};

    for (final group in groups) {
      _groupNames[group.groupId] = group.groupName;

      try {
        // Expenses
        final expSnap = await firestore
            .collection('groups')
            .doc(group.groupId)
            .collection('expenses')
            .orderBy('createdAt', descending: true)
            .limit(20)
            .get();
        for (final doc in expSnap.docs) {
          final e = ExpenseModel.fromFirestore(doc);
          expenses.add(
            _ActivityItem(
              e.description,
              e.totalAmount,
              group.groupId,
              e.paidBy,
              e.createdAt,
              e.category,
            ),
          );
          userIds.add(e.paidBy);
        }

        // Settlements
        final setSnap = await firestore
            .collection('groups')
            .doc(group.groupId)
            .collection('settlements')
            .orderBy('createdAt', descending: true)
            .limit(20)
            .get();
        for (final doc in setSnap.docs) {
          final d = doc.data();
          final from = d['fromUserId'] as String? ?? '';
          final to = d['toUserId'] as String? ?? '';
          settlements.add(
            _SettlementItem(
              from,
              to,
              (d['amount'] as num?)?.toDouble() ?? 0,
              group.groupId,
              (d['createdAt'] as Timestamp).toDate(),
              d['status'] as String? ?? 'completed',
            ),
          );
          userIds.addAll([from, to]);
        }

        // Balances
        double bal = 0;
        for (final doc in expSnap.docs) {
          final e = ExpenseModel.fromFirestore(doc);
          if (e.paidBy == userId) bal += e.totalAmount;
          for (final s in e.splits) {
            if (s.userId == userId) bal -= s.amount;
          }
        }
        balances[group.groupId] = bal;
      } catch (_) {}
    }

    // Fetch user names
    final idList = userIds.toList();
    for (var i = 0; i < idList.length; i += 10) {
      final batch = idList.sublist(
        i,
        i + 10 > idList.length ? idList.length : i + 10,
      );
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

    expenses.sort((a, b) => b.date.compareTo(a.date));
    settlements.sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _expenses = expenses;
        _settlements = settlements;
        _groupBalances = balances;
        _isLoading = false;
      });
    }
  }

  String _name(String uid) {
    if (uid == context.read<AuthProvider>().firebaseUser?.uid) return 'You';
    return _userNames[uid] ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Activity',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'History'),
            Tab(text: 'Settle Up'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppConstants.primaryColor,
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildExpensesTab(),
                _buildHistoryTab(),
                _buildSettleUpTab(),
              ],
            ),
    );
  }

  Widget _buildExpensesTab() {
    if (_expenses.isEmpty) {
      return _emptyState(
        Icons.receipt_long_outlined,
        'No expenses yet',
        'Add expenses to see them here',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppConstants.primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _expenses.length,
        itemBuilder: (_, i) {
          final e = _expenses[i];
          final showHeader = i == 0 || !_sameDay(e.date, _expenses[i - 1].date);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                if (i != 0) const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _dateHeader(e.date),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
              _expenseCard(e),
            ],
          );
        },
      ),
    );
  }

  Widget _expenseCard(_ActivityItem e) {
    final gn = _groupNames[e.groupId] ?? '';
    final cs = context.read<SettingsProvider>().currencySymbol;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _catIcon(e.category),
              color: AppConstants.primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.description,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${_name(e.paidBy)} paid  ·  $gn',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$cs${e.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                DateFormat('HH:mm').format(e.date),
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_settlements.isEmpty) {
      return _emptyState(
        Icons.history,
        'No settlement history',
        'Completed settlements appear here',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _settlements.length,
      itemBuilder: (_, i) {
        final s = _settlements[i];
        final gn = _groupNames[s.groupId] ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppConstants.successColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.handshake_outlined,
                  color: AppConstants.successColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_name(s.fromUserId)} paid ${_name(s.toUserId)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$gn  ·  ${DateFormat('d MMM, HH:mm').format(s.date)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Text(
                '${context.read<SettingsProvider>().currencySymbol}${s.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.successColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettleUpTab() {
    final groups = context.watch<GroupProvider>().groups;
    final unsettled = groups.where((g) {
      final bal = _groupBalances[g.groupId] ?? 0;
      return bal.abs() > 0.01;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00796B), AppConstants.primaryColor],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Icon(Icons.handshake_rounded, color: Colors.white, size: 40),
              SizedBox(height: 12),
              Text(
                'Settle Up',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Select a group to view optimised\nsettlements and record payments.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (unsettled.isEmpty)
          _emptyInline(Icons.check_circle_outline, 'All groups are settled!')
        else ...[
          Text(
            'Groups with outstanding balances',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          ...unsettled.map((group) {
            final bal = _groupBalances[group.groupId] ?? 0;
            final userId = context.read<AuthProvider>().firebaseUser?.uid ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
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
                      builder: (_) => SettlementsScreen(
                        group: group,
                        currentUserId: userId,
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
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
                              Text(
                                bal > 0
                                    ? 'You\'re owed ${context.read<SettingsProvider>().currencySymbol}${bal.toStringAsFixed(2)}'
                                    : 'You owe ${context.read<SettingsProvider>().currencySymbol}${bal.abs().toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: bal > 0
                                      ? AppConstants.successColor
                                      : AppConstants.errorColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettlementsScreen(
                                group: group,
                                currentUserId: userId,
                              ),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          child: const Text(
                            'Settle',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _emptyInline(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppConstants.successColor),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

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
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEEE, d MMM').format(d);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ActivityItem {
  final String description;
  final double amount;
  final String groupId;
  final String paidBy;
  final DateTime date;
  final String? category;
  _ActivityItem(
    this.description,
    this.amount,
    this.groupId,
    this.paidBy,
    this.date,
    this.category,
  );
}

class _SettlementItem {
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String groupId;
  final DateTime date;
  final String status;
  _SettlementItem(
    this.fromUserId,
    this.toUserId,
    this.amount,
    this.groupId,
    this.date,
    this.status,
  );
}
