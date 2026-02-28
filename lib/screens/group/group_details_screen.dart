import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../models/expense_model.dart';
import '../../services/expense_service.dart';
import '../../utils/constants.dart';
import 'add_expense_screen.dart';

class GroupDetailsScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailsScreen({super.key, required this.groupId});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ExpenseService _expenseService = ExpenseService();
  
  Map<String, UserModel> _memberCache = {};
  bool _isLoadingMembers = true;
  bool _initialized = false;

  List<ExpenseModel> _expenses = [];
  Map<String, double> _balances = {};
  bool _isLoadingExpenses = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      context.read<GroupProvider>().selectGroup(widget.groupId);
      _loadExpenses();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    _expenseService.getGroupExpenses(widget.groupId).listen((expenses) {
      if (mounted) {
        setState(() {
          _expenses = expenses;
          _isLoadingExpenses = false;
        });
        _calculateBalances();
      }
    });
  }

  Future<void> _calculateBalances() async {
    final balances = await _expenseService.calculateBalances(widget.groupId);
    if (mounted) {
      setState(() {
        _balances = balances;
      });
    }
  }

  double get _totalGroupExpenses =>
      _expenses.fold(0.0, (sum, e) => sum + e.totalAmount);

  Future<void> _fetchMemberDetails(List<String> memberIds) async {
    if (memberIds.isEmpty) {
      setState(() => _isLoadingMembers = false);
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;

      if (memberIds.length <= 10) {
        final snapshot = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: memberIds)
            .get();

        final Map<String, UserModel> cache = {};
        for (final doc in snapshot.docs) {
          cache[doc.id] = UserModel.fromFirestore(doc);
        }

        if (mounted) {
          setState(() {
            _memberCache = cache;
            _isLoadingMembers = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  String _getMemberName(String userId) {
    return _memberCache[userId]?.name ?? 'Unknown';
  }

  void _copyGroupCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Group code copied!'),
        backgroundColor: AppConstants.successColor,
      ),
    );
  }

  Future<void> _deleteExpense(ExpenseModel expense) async {
    final result = await _expenseService.deleteExpense(
      groupId: expense.groupId,
      expenseId: expense.expenseId,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? 'Expense deleted' : 'Failed to delete'),
          backgroundColor:
              result.success ? AppConstants.successColor : AppConstants.errorColor,
        ),
      );
    }
  }

  void _showDeleteExpenseDialog(ExpenseModel expense) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense'),
        content: Text('Delete "${expense.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteExpense(expense);
            },
            child: const Text('Delete',
                style: TextStyle(color: AppConstants.errorColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().firebaseUser?.uid;
    final groupProvider = context.watch<GroupProvider>();
    final group = groupProvider.selectedGroup;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Group Details'),
          backgroundColor: AppConstants.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppConstants.primaryColor),
        ),
      );
    }

    if (_memberCache.isEmpty && _isLoadingMembers) {
      _fetchMemberDetails(group.members);
    }

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: Text(group.groupName),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'Balances'),
            Tab(text: 'Members'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildExpensesTab(),
          _buildBalancesTab(group, currentUserId ?? ''),
          _buildMembersTab(group),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => AddExpenseScreen(
                group: group,
                currentUserId: currentUserId ?? '',
              ),
            ),
          );
          if (result == true) {
            _calculateBalances();
          }
        },
        backgroundColor: AppConstants.primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
    );
  }

  Widget _buildExpensesTab() {
    if (_isLoadingExpenses) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryColor),
      );
    }

    if (_expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No expenses yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Tap "Add Expense" to get started',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      itemCount: _expenses.length,
      itemBuilder: (context, index) {
        final expense = _expenses[index];
        return _buildExpenseCard(expense);
      },
    );
  }

  Widget _buildExpenseCard(ExpenseModel expense) {
    final payerName = _getMemberName(expense.paidBy);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onLongPress: () => _showDeleteExpenseDialog(expense),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt, color: AppConstants.primaryColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(expense.description,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('$payerName paid',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
              Text(
                '£${expense.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primaryColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalancesTab(GroupModel group, String currentUserId) {
    if (_isLoadingExpenses) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryColor),
      );
    }

    if (_balances.isEmpty && _expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No balances yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      children: [
        Container(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppConstants.primaryColor, AppConstants.secondaryColor],
            ),
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
          child: Column(
            children: [
              const Text('Total Expenses', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text(
                '£${_totalGroupExpenses.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Member Balances',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...group.members.map((memberId) {
          final balance = _balances[memberId] ?? 0;
          final isPositive = balance >= 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isPositive
                    ? AppConstants.successColor.withOpacity(0.2)
                    : AppConstants.errorColor.withOpacity(0.2),
                child: Text(
                  _getMemberName(memberId).isNotEmpty
                      ? _getMemberName(memberId)[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: isPositive
                          ? AppConstants.successColor
                          : AppConstants.errorColor),
                ),
              ),
              title: Text(_getMemberName(memberId)),
              subtitle: Text(isPositive ? 'gets back' : 'owes',
                  style: TextStyle(
                      color: isPositive
                          ? AppConstants.successColor
                          : AppConstants.errorColor)),
              trailing: Text(
                '£${balance.abs().toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isPositive
                        ? AppConstants.successColor
                        : AppConstants.errorColor),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMembersTab(GroupModel group) {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      children: [
        Container(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          decoration: BoxDecoration(
            color: AppConstants.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
          child: Column(
            children: [
              const Text('Group Code'),
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
                        color: AppConstants.primaryColor),
                  ),
                  IconButton(
                    onPressed: () => _copyGroupCode(group.groupCode),
                    icon: const Icon(Icons.copy, color: AppConstants.primaryColor),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Members (${group.memberCount})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...group.members.map((memberId) {
          final isGroupOwner = group.createdBy == memberId;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    isGroupOwner ? AppConstants.primaryColor : Colors.grey[300],
                child: Text(
                  _getMemberName(memberId).isNotEmpty
                      ? _getMemberName(memberId)[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: isGroupOwner ? Colors.white : Colors.black87),
                ),
              ),
              title: Text(_getMemberName(memberId)),
              subtitle: isGroupOwner
                  ? const Text('Owner',
                      style: TextStyle(color: AppConstants.primaryColor))
                  : null,
            ),
          );
        }),
      ],
    );
  }
}