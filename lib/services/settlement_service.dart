import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/settlement_model.dart';
import '../models/expense_model.dart';
import '../models/bank_details_model.dart';
import 'settlement_algorithm.dart';

class SettlementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _settlementsCollection(String groupId) {
    return _firestore.collection('groups').doc(groupId).collection('settlements');
  }

  CollectionReference<Map<String, dynamic>> _expensesCollection(String groupId) {
    return _firestore.collection('groups').doc(groupId).collection('expenses');
  }

  /// Calculate balances - EXACT same logic as ExpenseService
  Future<Map<String, double>> calculateBalances(String groupId) async {
    try {
      final snapshot = await _expensesCollection(groupId).get();
      final expenses = snapshot.docs.map((doc) => ExpenseModel.fromFirestore(doc)).toList();
      
      print('DEBUG: Found ${expenses.length} expenses');
      
      final Map<String, double> balances = {};
      
      for (final expense in expenses) {
        // Payer gets credited (positive balance = owed money)
        balances[expense.paidBy] = (balances[expense.paidBy] ?? 0) + expense.totalAmount;
        
        // Each participant gets debited (negative balance = owes money)
        for (final split in expense.splits) {
          balances[split.userId] = (balances[split.userId] ?? 0) - split.amount;
        }
      }
      
      // Adjust for completed settlements
      final settlementsSnapshot = await _settlementsCollection(groupId).get();
      print('DEBUG: Found ${settlementsSnapshot.docs.length} settlements');
      
      for (final doc in settlementsSnapshot.docs) {
        final data = doc.data();
        if (data['status'] == 'completed') {
          final fromUserId = data['fromUserId'] as String?;
          final toUserId = data['toUserId'] as String?;
          final amount = (data['amount'] as num?)?.toDouble() ?? 0;
          
          if (fromUserId != null && toUserId != null && amount > 0) {
            balances[fromUserId] = (balances[fromUserId] ?? 0) + amount;
            balances[toUserId] = (balances[toUserId] ?? 0) - amount;
          }
        }
      }
      
      print('DEBUG: Final balances: $balances');
      return balances;
    } catch (e) {
      print('DEBUG ERROR: calculateBalances failed: $e');
      return {};
    }
  }

  Future<SettlementResult> calculateOptimizedSettlements(String groupId) async {
    print('DEBUG: Starting calculateOptimizedSettlements for group: $groupId');
    
    try {
      final balances = await calculateBalances(groupId);
      
      print('DEBUG: Balances received: $balances');
      
      if (balances.isEmpty) {
        print('DEBUG: Balances are empty, returning empty result');
        return SettlementResult(
          netBalances: {},
          settlements: [],
          originalTransactionCount: 0,
          optimizedTransactionCount: 0,
          totalDebt: 0,
          isFullySettleable: true,
          error: null,
        );
      }
      
      // Check if there are actual imbalances
      final hasImbalances = balances.values.any((b) => b.abs() > 0.01);
      print('DEBUG: Has imbalances: $hasImbalances');
      
      if (!hasImbalances) {
        print('DEBUG: No imbalances found, everyone is settled');
        return SettlementResult(
          netBalances: balances,
          settlements: [],
          originalTransactionCount: 0,
          optimizedTransactionCount: 0,
          totalDebt: 0,
          isFullySettleable: true,
          error: null,
        );
      }
      
      final result = SettlementAlgorithm.calculateSettlements(balances);
      print('DEBUG: Algorithm returned ${result.settlements.length} settlements');
      
      return result;
    } catch (e) {
      print('DEBUG ERROR: calculateOptimizedSettlements failed: $e');
      return SettlementResult(
        netBalances: {},
        settlements: [],
        originalTransactionCount: 0,
        optimizedTransactionCount: 0,
        totalDebt: 0,
        isFullySettleable: false,
        error: 'Error: ${e.toString()}',
      );
    }
  }

  Future<({SettlementRecord? settlement, String? error})> recordSettlement({
    required String groupId,
    required String fromUserId,
    required String toUserId,
    required double amount,
    String? paymentMethod,
    String? paymentReference,
    String? note,
  }) async {
    try {
      if (amount <= 0) {
        return (settlement: null, error: 'Amount must be positive');
      }

      final docRef = _settlementsCollection(groupId).doc();

      final settlement = SettlementRecord(
        settlementId: docRef.id,
        groupId: groupId,
        fromUserId: fromUserId,
        toUserId: toUserId,
        amount: (amount * 100).round() / 100,
        status: SettlementStatus.completed,
        createdAt: DateTime.now(),
        confirmedAt: DateTime.now(),
        paymentMethod: paymentMethod,
        paymentReference: paymentReference,
        note: note,
      );

      await docRef.set(settlement.toFirestore());

      return (settlement: settlement, error: null);
    } catch (e) {
      return (settlement: null, error: 'Failed to record: ${e.toString()}');
    }
  }

  Stream<List<SettlementRecord>> getSettlementHistory(String groupId) {
    return _settlementsCollection(groupId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SettlementRecord.fromFirestore(doc))
            .toList());
  }

  Future<({bool success, String? error})> deleteSettlement({
    required String groupId,
    required String settlementId,
  }) async {
    try {
      await _settlementsCollection(groupId).doc(settlementId).delete();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to delete: ${e.toString()}');
    }
  }

  Future<({bool success, String? error})> saveBankDetails({
    required String userId,
    required BankDetails bankDetails,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'bankDetails': bankDetails.toMap(),
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to save: ${e.toString()}');
    }
  }

  Future<BankDetails?> getBankDetails(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      if (data != null && data['bankDetails'] != null) {
        return BankDetails.fromMap(data['bankDetails']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}