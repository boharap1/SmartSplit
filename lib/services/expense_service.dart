import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense_model.dart';

class ExpenseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _expensesCollection(String groupId) {
    return _firestore.collection('groups').doc(groupId).collection('expenses');
  }

  Future<({ExpenseModel? expense, String? error})> createExpense({
    required String groupId,
    required String description,
    required double totalAmount,
    required String paidBy,
    required List<ExpenseSplit> splits,
    required SplitType splitType,
    String? category,
    required DateTime date,
    required String createdBy,
  }) async {
    try {
      final docRef = _expensesCollection(groupId).doc();

      final expense = ExpenseModel(
        expenseId: docRef.id,
        groupId: groupId,
        description: description.trim(),
        totalAmount: totalAmount,
        paidBy: paidBy,
        splits: splits,
        splitType: splitType,
        category: category,
        date: date,
        createdAt: DateTime.now(),
        createdBy: createdBy,
      );

      await docRef.set(expense.toFirestore());
      return (expense: expense, error: null);
    } catch (e) {
      return (expense: null, error: 'Error: ${e.toString()}');
    }
  }

  Stream<List<ExpenseModel>> getGroupExpenses(String groupId) {
    return _expensesCollection(groupId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ExpenseModel.fromFirestore(doc)).toList());
  }

  Future<({bool success, String? error})> deleteExpense({
    required String groupId,
    required String expenseId,
  }) async {
    try {
      await _expensesCollection(groupId).doc(expenseId).delete();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Error: ${e.toString()}');
    }
  }

  Future<Map<String, double>> calculateBalances(String groupId) async {
    try {
      final snapshot = await _expensesCollection(groupId).get();
      final expenses =
          snapshot.docs.map((doc) => ExpenseModel.fromFirestore(doc)).toList();

      final Map<String, double> balances = {};

      for (final expense in expenses) {
        balances[expense.paidBy] =
            (balances[expense.paidBy] ?? 0) + expense.totalAmount;

        for (final split in expense.splits) {
          balances[split.userId] = (balances[split.userId] ?? 0) - split.amount;
        }
      }

      return balances;
    } catch (e) {
      return {};
    }
  }
}