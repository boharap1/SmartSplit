import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../models/settlement_model.dart';
import '../../models/bank_details_model.dart';
import '../../services/settlement_service.dart';
import '../../services/settlement_algorithm.dart';
import '../../utils/constants.dart';
import '../../models/notification_model.dart';
import '../../providers/settings_provider.dart';
import '../../services/notification_dispatcher.dart';
import '../profile/bank_details_screen.dart';

class SettlementsScreen extends StatefulWidget {
  final GroupModel group;
  final String currentUserId;

  const SettlementsScreen({
    super.key,
    required this.group,
    required this.currentUserId,
  });

  @override
  State<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends State<SettlementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SettlementService _settlementService = SettlementService();

  SettlementResult? _settlementResult;
  List<SettlementRecord> _settlementHistory = [];
  Map<String, UserModel> _memberCache = {};
  final Map<String, BankDetails?> _bankDetailsCache = {};
  bool _isLoading = true;
  bool _isSettling = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    await _fetchMemberDetails();
    await _loadBankDetails();
    await _loadSettlementResult();
    _loadSettlementHistory();

    setState(() => _isLoading = false);
  }

  Future<void> _fetchMemberDetails() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final memberIds = widget.group.members;

      if (memberIds.length <= 10) {
        final snapshot = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: memberIds)
            .get();

        final Map<String, UserModel> cache = {};
        for (final doc in snapshot.docs) {
          cache[doc.id] = UserModel.fromFirestore(doc);
        }

        setState(() => _memberCache = cache);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadBankDetails() async {
    for (final memberId in widget.group.members) {
      final details = await _settlementService.getBankDetails(memberId);
      _bankDetailsCache[memberId] = details;
    }
  }

  Future<void> _loadSettlementResult() async {
    try {
      final result = await _settlementService.calculateOptimizedSettlements(
        widget.group.groupId,
      );
      setState(() => _settlementResult = result);
    } catch (e) {
      setState(() {
        _settlementResult = SettlementResult(
          netBalances: {},
          settlements: [],
          originalTransactionCount: 0,
          optimizedTransactionCount: 0,
          totalDebt: 0,
          isFullySettleable: false,
          error: 'Failed to load settlements.',
        );
      });
    }
  }

  void _loadSettlementHistory() {
    _settlementService.getSettlementHistory(widget.group.groupId).listen((
      history,
    ) {
      if (mounted) {
        setState(() => _settlementHistory = history);
      }
    });
  }

  String _getMemberName(String userId) {
    return _memberCache[userId]?.name ?? 'Unknown';
  }

  Future<void> _showPaymentRequestSheet(OptimizedSettlement settlement) async {
    final payerName      = _getMemberName(settlement.fromUserId);
    final myName         = _getMemberName(widget.currentUserId);
    final myBankDetails  = _bankDetailsCache[widget.currentUserId];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _PaymentRequestSheet(
        settlement:      settlement,
        payerName:       payerName,
        myName:          myName,
        groupId:         widget.group.groupId,
        myBankDetails:   myBankDetails,
        onAddBankDetails: () {
          Navigator.pop(context);
          _navigateToBankDetails();
        },
      ),
    );
  }

  Future<void> _showSettlementConfirmation(
    OptimizedSettlement settlement,
  ) async {
    final toUserBankDetails = _bankDetailsCache[settlement.toUserId];

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SettlementConfirmationSheet(
        settlement: settlement,
        fromName: _getMemberName(settlement.fromUserId),
        toName: _getMemberName(settlement.toUserId),
        bankDetails: toUserBankDetails,
        isCurrentUserPayer: settlement.fromUserId == widget.currentUserId,
      ),
    );

    if (result != null && result['confirmed'] == true) {
      await _recordSettlement(
        settlement,
        paymentMethod: result['paymentMethod'],
        paymentReference: result['paymentReference'],
        note: result['note'],
      );
    }
  }

  Future<void> _recordSettlement(
    OptimizedSettlement settlement, {
    String? paymentMethod,
    String? paymentReference,
    String? note,
  }) async {
    setState(() => _isSettling = true);

    final result = await _settlementService.recordSettlement(
      groupId: widget.group.groupId,
      fromUserId: settlement.fromUserId,
      toUserId: settlement.toUserId,
      amount: settlement.amount,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
      note: note,
      fromUserName: _getMemberName(settlement.fromUserId),
      groupName: widget.group.groupName,
    );

    if (mounted) {
      if (result.settlement != null) {
        setState(() {
          _isSettling = false;
          if (_settlementResult != null) {
            final updated = _settlementResult!.settlements
                .where((s) => !(s.fromUserId == settlement.fromUserId &&
                    s.toUserId == settlement.toUserId))
                .toList();
            _settlementResult = SettlementResult(
              netBalances: _settlementResult!.netBalances,
              settlements: updated,
              originalTransactionCount:
                  _settlementResult!.originalTransactionCount,
              optimizedTransactionCount: updated.length,
              totalDebt: _settlementResult!.totalDebt,
              isFullySettleable: _settlementResult!.isFullySettleable,
            );
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Payment recorded successfully!'),
              ],
            ),
            backgroundColor: AppConstants.successColor,
            duration: Duration(seconds: 3),
          ),
        );
        _loadSettlementResult(); // background reload for accurate balances
      } else {
        setState(() => _isSettling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to record settlement'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteSettlement(SettlementRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Settlement'),
        content: const Text(
          'This will undo this settlement and recalculate balances. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppConstants.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await _settlementService.deleteSettlement(
      groupId: widget.group.groupId,
      settlementId: record.settlementId,
    );

    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settlement deleted'),
            backgroundColor: AppConstants.successColor,
          ),
        );
        _loadSettlementResult();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to delete'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  void _navigateToBankDetails() async {
    final existingDetails = _bankDetailsCache[widget.currentUserId];
    final result = await Navigator.push<BankDetails>(
      context,
      MaterialPageRoute(
        builder: (context) => BankDetailsScreen(
          userId: widget.currentUserId,
          existingDetails: existingDetails,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _bankDetailsCache[widget.currentUserId] = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settle Up'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance),
            tooltip: 'My Bank Details',
            onPressed: _navigateToBankDetails,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'Pay'),
            Tab(text: 'History'),
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
                _buildSummaryTab(),
                _buildPayTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildSummaryTab() {
    final cs = context.read<SettingsProvider>().currencySymbol;
    if (_settlementResult == null) {
      return const Center(child: Text('Unable to calculate settlements'));
    }

    final result = _settlementResult!;

    if (result.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppConstants.errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Calculation Error',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(result.error!, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    if (result.settlements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 80,
              color: AppConstants.successColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'All Settled Up!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Everyone is square',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    final myBalance = result.netBalances[widget.currentUserId] ?? 0.0;

    return ListView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      children: [
        // Personal balance cards
        Row(
          children: [
            Expanded(
              child: _buildPersonalCard(
                'You Owe',
                myBalance < -0.01 ? myBalance.abs() : 0.0,
                AppConstants.errorColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPersonalCard(
                'You\'re Owed',
                myBalance > 0.01 ? myBalance : 0.0,
                AppConstants.successColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Algorithm stats card
        Container(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppConstants.primaryColor, AppConstants.secondaryColor],
            ),
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
          child: Column(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              const Text(
                'MCMF Optimization',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Total Debt',
                    '$cs${result.totalDebt.toStringAsFixed(2)}',
                  ),
                  _buildStatItem(
                    'Transactions',
                    '${result.optimizedTransactionCount}',
                  ),
                  _buildStatItem(
                    'Saved',
                    '${result.transactionReduction.toStringAsFixed(0)}%',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Net balances
        const Text(
          'Net Balances',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        ...result.netBalances.entries.where((e) => e.value.abs() > 0.01).map((
          entry,
        ) {
          final balance = entry.value;
          final isPositive = balance > 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isPositive
                    ? AppConstants.successColor.withOpacity(0.2)
                    : AppConstants.errorColor.withOpacity(0.2),
                child: Icon(
                  isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isPositive
                      ? AppConstants.successColor
                      : AppConstants.errorColor,
                ),
              ),
              title: Text(_getMemberName(entry.key)),
              subtitle: Text(
                isPositive ? 'is owed' : 'owes',
                style: TextStyle(
                  color: isPositive
                      ? AppConstants.successColor
                      : AppConstants.errorColor,
                ),
              ),
              trailing: Text(
                '$cs${balance.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isPositive
                      ? AppConstants.successColor
                      : AppConstants.errorColor,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPersonalCard(String label, double amount, Color color) {
    final cs = context.read<SettingsProvider>().currencySymbol;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: color)),
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
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPayTab() {
    if (_settlementResult == null || _settlementResult!.settlements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 80,
              color: AppConstants.successColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'No Payments Needed',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Everyone is settled up!',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final settlements = _settlementResult!.settlements;

    // Check if current user has bank details
    final myBankDetails = _bankDetailsCache[widget.currentUserId];

    return ListView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      children: [
        // Bank details reminder
        if (myBankDetails == null)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add your bank details',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      Text(
                        'So others can pay you easily',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _navigateToBankDetails,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

        const Text(
          'Payments to Make',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Your payments are highlighted in blue',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        const SizedBox(height: 16),

        ...settlements.map((settlement) => _buildPaymentCard(settlement)),
      ],
    );
  }

  Widget _buildPaymentCard(OptimizedSettlement settlement) {
    final fromName = _getMemberName(settlement.fromUserId);
    final toName = _getMemberName(settlement.toUserId);
    final isCurrentUserPayer = settlement.fromUserId == widget.currentUserId;
    final isCurrentUserReceiver = settlement.toUserId == widget.currentUserId;
    final toUserBankDetails = _bankDetailsCache[settlement.toUserId];

    VoidCallback? cardTap;
    if (isCurrentUserPayer && !_isSettling) {
      cardTap = () => _showSettlementConfirmation(settlement);
    } else if (isCurrentUserReceiver) {
      cardTap = () => _showPaymentRequestSheet(settlement);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: isCurrentUserPayer
            ? const BorderSide(color: AppConstants.primaryColor, width: 2)
            : isCurrentUserReceiver
            ? const BorderSide(color: AppConstants.successColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: cardTap,
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            children: [
              Row(
                children: [
                  // From user
                  Expanded(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppConstants.errorColor.withOpacity(
                            0.2,
                          ),
                          child: Text(
                            fromName.isNotEmpty
                                ? fromName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppConstants.errorColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fromName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isCurrentUserPayer)
                          const Text(
                            '(You)',
                            style: TextStyle(
                              color: AppConstants.primaryColor,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Arrow and amount
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Text(
                          '${context.read<SettingsProvider>().currencySymbol}${settlement.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryColor,
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward,
                          color: AppConstants.primaryColor,
                          size: 32,
                        ),
                      ],
                    ),
                  ),

                  // To user
                  Expanded(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppConstants.successColor
                              .withOpacity(0.2),
                          child: Text(
                            toName.isNotEmpty ? toName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: AppConstants.successColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          toName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isCurrentUserReceiver)
                          const Text(
                            '(You)',
                            style: TextStyle(
                              color: AppConstants.successColor,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // Bank details preview
              if (toUserBankDetails != null &&
                  toUserBankDetails.isComplete) ...[
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${toUserBankDetails.bankName} • ${toUserBankDetails.formattedSortCode} • ${toUserBankDetails.maskedAccountNumber}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],

              if (isCurrentUserPayer || isCurrentUserReceiver) ...[
                const SizedBox(height: 12),
                if (isCurrentUserPayer)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSettling
                          ? null
                          : () => _showSettlementConfirmation(settlement),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Pay Now'),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showPaymentRequestSheet(settlement),
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Request Payment'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConstants.successColor,
                        side: const BorderSide(color: AppConstants.successColor),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_settlementHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No settlement history',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Completed settlements will appear here',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      itemCount: _settlementHistory.length,
      itemBuilder: (context, index) {
        final record = _settlementHistory[index];
        return _buildHistoryCard(record);
      },
    );
  }

  Widget _buildHistoryCard(SettlementRecord record) {
    final fromName = _getMemberName(record.fromUserId);
    final toName = _getMemberName(record.toUserId);
    final canUndo = record.fromUserId == widget.currentUserId ||
        record.toUserId == widget.currentUserId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppConstants.successColor,
                  radius: 16,
                  child: Icon(Icons.check, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$fromName paid $toName',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${record.createdAt.day}/${record.createdAt.month}/${record.createdAt.year} at ${record.createdAt.hour}:${record.createdAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${context.read<SettingsProvider>().currencySymbol}${record.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.successColor,
                  ),
                ),
              ],
            ),
            if (record.paymentMethod != null || record.note != null) ...[
              const Divider(height: 16),
              if (record.paymentMethod != null)
                Text(
                  'Method: ${record.paymentMethod}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              if (record.note != null)
                Text(
                  'Note: ${record.note}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
            ],
            if (canUndo) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _deleteSettlement(record),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Undo'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for confirming a settlement
class _SettlementConfirmationSheet extends StatefulWidget {
  final OptimizedSettlement settlement;
  final String fromName;
  final String toName;
  final BankDetails? bankDetails;
  final bool isCurrentUserPayer;

  const _SettlementConfirmationSheet({
    required this.settlement,
    required this.fromName,
    required this.toName,
    this.bankDetails,
    required this.isCurrentUserPayer,
  });

  @override
  State<_SettlementConfirmationSheet> createState() =>
      _SettlementConfirmationSheetState();
}

class _SettlementConfirmationSheetState
    extends State<_SettlementConfirmationSheet> {
  String _paymentMethod = 'bank_transfer';
  final _referenceController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _copyBankDetails() {
    if (widget.bankDetails == null) return;

    final cs = context.read<SettingsProvider>().currencySymbol;
    final details =
        '''
Account Holder: ${widget.bankDetails!.accountHolderName}
Bank: ${widget.bankDetails!.bankName}
Sort Code: ${widget.bankDetails!.formattedSortCode}
Account Number: ${widget.bankDetails!.accountNumber}
Amount: $cs${widget.settlement.amount.toStringAsFixed(2)}
''';

    Clipboard.setData(ClipboardData(text: details));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bank details copied!'),
        backgroundColor: AppConstants.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Confirm Settlement',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Amount
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(
                    AppConstants.borderRadius,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '${widget.fromName} pays ${widget.toName}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${context.watch<SettingsProvider>().currencySymbol}${widget.settlement.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Bank details (if available)
              if (widget.bankDetails != null &&
                  widget.bankDetails!.isComplete) ...[
                const Text(
                  'Pay to:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(
                      AppConstants.borderRadius,
                    ),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBankDetailRow(
                        'Name',
                        widget.bankDetails!.accountHolderName,
                      ),
                      _buildBankDetailRow('Bank', widget.bankDetails!.bankName),
                      _buildBankDetailRow(
                        'Sort Code',
                        widget.bankDetails!.formattedSortCode,
                      ),
                      _buildBankDetailRow(
                        'Account',
                        widget.bankDetails!.accountNumber,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _copyBankDetails,
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy Details'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Payment method
              const Text(
                'Payment Method',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildPaymentMethodChip(
                    'Bank Transfer',
                    'bank_transfer',
                    Icons.account_balance,
                  ),
                  _buildPaymentMethodChip('Cash', 'cash', Icons.money),
                  _buildPaymentMethodChip('Other', 'other', Icons.more_horiz),
                ],
              ),
              const SizedBox(height: 16),

              // Reference (optional)
              TextField(
                controller: _referenceController,
                decoration: InputDecoration(
                  labelText: 'Payment Reference (optional)',
                  hintText: 'e.g., Bank transaction ID',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.borderRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Note (optional)
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g., Paid via Monzo',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.borderRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Confirm button
              ElevatedButton(
                onPressed: () {
                  if (_paymentMethod == 'cash') {
                    Navigator.pop(context, {
                      'confirmed': true,
                      'paymentMethod': _paymentMethod,
                      'paymentReference': _referenceController.text.isNotEmpty
                          ? _referenceController.text
                          : null,
                      'note': _noteController.text.isNotEmpty
                          ? _noteController.text
                          : null,
                    });
                  } else {
                    // Bank transfer / other — cannot be auto-confirmed in-app.
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please complete the transfer externally. '
                          'Only cash payments can be marked as settled here.',
                        ),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _paymentMethod == 'cash'
                      ? AppConstants.primaryColor
                      : Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _paymentMethod == 'cash'
                      ? 'Confirm Cash Payment'
                      : 'Got It — I\'ll Transfer Externally',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),

              // Cancel button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBankDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodChip(String label, String value, IconData icon) {
    final isSelected = _paymentMethod == value;

    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label)],
      ),
      selected: isSelected,
      selectedColor: AppConstants.primaryColor.withOpacity(0.2),
      onSelected: (selected) {
        if (selected) {
          setState(() => _paymentMethod = value);
        }
      },
    );
  }
}

/// Bottom sheet shown to the receiver of a payment so they can share their
/// bank details, copy a payment request message, or send a critical in-app
/// notification to the payer (bypasses the payer's notification preferences).
class _PaymentRequestSheet extends StatefulWidget {
  final OptimizedSettlement settlement;
  final String payerName;
  final String myName;
  final String groupId;
  final BankDetails? myBankDetails;
  final VoidCallback onAddBankDetails;

  const _PaymentRequestSheet({
    required this.settlement,
    required this.payerName,
    required this.myName,
    required this.groupId,
    required this.myBankDetails,
    required this.onAddBankDetails,
  });

  @override
  State<_PaymentRequestSheet> createState() => _PaymentRequestSheetState();
}

class _PaymentRequestSheetState extends State<_PaymentRequestSheet> {
  bool _isSending = false;
  bool _notified  = false;

  Future<void> _notifyPayer() async {
    if (_isSending || _notified) return;
    setState(() => _isSending = true);

    await NotificationDispatcher.instance.dispatchCritical(
      DispatchPayload(
        title:            'Payment reminder',
        body:             '${widget.myName} is requesting '
                          '£${widget.settlement.amount.toStringAsFixed(2)} from you.',
        recipientUserIds: [widget.settlement.fromUserId],
        type:             NotificationType.paymentReminder,
        priority:         NotificationPriority.critical,
        groupId:          widget.groupId,
        fromUserName:     widget.myName,
      ),
    );

    if (mounted) {
      setState(() { _isSending = false; _notified = true; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.payerName} has been notified.'),
          backgroundColor: AppConstants.successColor,
        ),
      );
    }
  }

  void _copyRequest(BuildContext context) {
    final bank = widget.myBankDetails;
    final cs   = context.read<SettingsProvider>().currencySymbol;
    final String message;

    if (bank != null && bank.isComplete) {
      message =
          'Hi ${widget.payerName}, could you please send me '
          '$cs${widget.settlement.amount.toStringAsFixed(2)}?\n\n'
          'Account holder: ${bank.accountHolderName}\n'
          'Bank: ${bank.bankName}\n'
          'Sort code: ${bank.formattedSortCode}\n'
          'Account number: ${bank.accountNumber}';
    } else {
      message =
          'Hi ${widget.payerName}, could you please send me '
          '$cs${widget.settlement.amount.toStringAsFixed(2)}? Thanks!';
    }

    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment request copied to clipboard'),
        backgroundColor: AppConstants.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bank = widget.myBankDetails;
    final cs   = context.watch<SettingsProvider>().currencySymbol;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Request Payment',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Summary
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppConstants.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                ),
                child: Column(
                  children: [
                    Text(
                      '${widget.payerName} owes you',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$cs${widget.settlement.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.successColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Bank details or prompt to add them
              if (bank != null && bank.isComplete) ...[
                const Text(
                  'Your payment details',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius:
                        BorderRadius.circular(AppConstants.borderRadius),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('Name', bank.accountHolderName),
                      _row('Bank', bank.bankName),
                      _row('Sort code', bank.formattedSortCode),
                      _row('Account', bank.accountNumber),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppConstants.borderRadius),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Add your bank details so ${widget.payerName} knows where to send the money.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: widget.onAddBankDetails,
                  child: const Text('Add Bank Details'),
                ),
                const SizedBox(height: 16),
              ],

              // Notify button — dispatches a critical notification to the payer,
              // bypassing their push/email preference settings.
              OutlinedButton.icon(
                onPressed: (_isSending || _notified) ? null : _notifyPayer,
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _notified
                            ? Icons.check_circle_outline
                            : Icons.notifications_active_outlined,
                        size: 18,
                      ),
                label: Text(
                  _notified
                      ? 'Notified ${widget.payerName}'
                      : 'Notify ${widget.payerName}',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _notified ? Colors.grey : AppConstants.primaryColor,
                  side: BorderSide(
                    color: _notified
                        ? Colors.grey.withValues(alpha: 0.4)
                        : AppConstants.primaryColor,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: () => _copyRequest(context),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy Payment Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.successColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
