import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bank_details_model.dart';
import '../models/expense_model.dart';
import '../models/notification_model.dart';
import '../models/settlement_model.dart';
import '../utils/app_logger.dart';
import '../utils/bank_details_encryption.dart';
import 'notification_service.dart';
import 'settlement_algorithm.dart';

class SettlementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _settlementsCollection(String groupId) {
    return _firestore.collection('groups').doc(groupId).collection('settlements');
  }

  CollectionReference<Map<String, dynamic>> _expensesCollection(String groupId) {
    return _firestore.collection('groups').doc(groupId).collection('expenses');
  }

  /// Calculates net balances for each member, adjusted for completed settlements.
  Future<Map<String, double>> calculateBalances(String groupId) async {
    try {
      final snapshot = await _expensesCollection(groupId).get();
      final expenses = snapshot.docs.map((doc) => ExpenseModel.fromFirestore(doc)).toList();

      final Map<String, double> balances = {};

      for (final expense in expenses) {
        balances[expense.paidBy] = (balances[expense.paidBy] ?? 0) + expense.totalAmount;
        for (final split in expense.splits) {
          balances[split.userId] = (balances[split.userId] ?? 0) - split.amount;
        }
      }

      final settlementsSnapshot = await _settlementsCollection(groupId).get();

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

      return balances;
    } catch (e, s) {
      AppLogger.error('calculateBalances', e, s);
      return {};
    }
  }

  Future<SettlementResult> calculateOptimizedSettlements(String groupId) async {
    try {
      final balances = await calculateBalances(groupId);

      if (balances.isEmpty) {
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

      final hasImbalances = balances.values.any((b) => b.abs() > 0.01);

      if (!hasImbalances) {
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

      return SettlementAlgorithm.calculateSettlements(balances);
    } catch (e, s) {
      AppLogger.error('calculateOptimizedSettlements', e, s);
      return SettlementResult(
        netBalances: {},
        settlements: [],
        originalTransactionCount: 0,
        optimizedTransactionCount: 0,
        totalDebt: 0,
        isFullySettleable: false,
        error: 'Failed to calculate settlements.',
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
    // Optional – used to build the payment-received notification.
    String? fromUserName,
    String? groupName,
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

      // Notify the recipient that they received a payment.
      final payer = fromUserName ?? 'Someone';
      final inGroup = groupName != null ? ' in $groupName' : '';
      NotificationService.dispatch(
        toUserIds: [toUserId],
        type: NotificationType.paymentReceived,
        title: 'Payment received$inGroup',
        body: '$payer paid you £${settlement.amount.toStringAsFixed(2)}',
        groupId: groupId,
        relatedId: docRef.id,
        fromUserName: fromUserName,
      );

      return (settlement: settlement, error: null);
    } catch (e, s) {
      AppLogger.error('recordSettlement', e, s);
      return (settlement: null, error: 'Failed to record settlement.');
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
    } catch (e, s) {
      AppLogger.error('deleteSettlement', e, s);
      return (success: false, error: 'Failed to delete settlement.');
    }
  }

  Future<({bool success, String? error})> saveBankDetails({
    required String userId,
    required BankDetails bankDetails,
  }) async {
    try {
      final encrypted =
          BankDetailsEncryption.encrypt(bankDetails.toMap(), userId);
      await _firestore.collection('users').doc(userId).update({
        'bankDetails': encrypted,
      });
      return (success: true, error: null);
    } catch (e, s) {
      AppLogger.error('saveBankDetails', e, s);
      return (success: false, error: 'Failed to save bank details.');
    }
  }

  Future<BankDetails?> getBankDetails(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      if (data != null && data['bankDetails'] != null) {
        final decrypted = BankDetailsEncryption.decrypt(
            Map<String, dynamic>.from(data['bankDetails'] as Map), userId);
        return BankDetails.fromMap(decrypted);
      }
      return null;
    } catch (e, s) {
      AppLogger.error('getBankDetails', e, s);
      return null;
    }
  }
}