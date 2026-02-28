import 'dart:async';
import 'package:flutter/material.dart';
import '../models/expense_model.dart';
import '../services/expense_service.dart';

enum ExpenseStatus { initial, loading, loaded, error }

class ExpenseProvider extends ChangeNotifier {
  final ExpenseService _expenseService = ExpenseService();

  ExpenseStatus _status = ExpenseStatus.initial;
  List<ExpenseModel> _expenses = [];
  Map<String, double> _balances = {};
  String? _errorMessage;
  String? _currentGroupId;

  StreamSubscription<List<ExpenseModel>>? _expensesSubscription;

  ExpenseStatus get status => _status;
  List<ExpenseModel> get expenses => _expenses;
  Map<String, double> get balances => _balances;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == ExpenseStatus.loading;
  bool get hasExpenses => _expenses.isNotEmpty;

  double get totalGroupExpenses =>
      _expenses.fold(0.0, (sum, e) => sum + e.totalAmount);

  void startListeningToExpenses(String groupId) {
    if (_currentGroupId != groupId) {
      _expensesSubscription?.cancel();
      _currentGroupId = groupId;
    }

    _status = ExpenseStatus.loading;
    notifyListeners();

    _expensesSubscription = _expenseService.getGroupExpenses(groupId).listen(
      (expenses) {
        _expenses = expenses;
        _status = ExpenseStatus.loaded;
        _errorMessage = null;
        notifyListeners();
        _updateBalances(groupId);
      },
      onError: (error) {
        _status = ExpenseStatus.error;
        _errorMessage = 'Failed to load expenses.';
        notifyListeners();
      },
    );
  }

  void stopListeningToExpenses() {
    _expensesSubscription?.cancel();
    _expensesSubscription = null;
    _expenses = [];
    _balances = {};
    _currentGroupId = null;
    _status = ExpenseStatus.initial;
    notifyListeners();
  }

  Future<void> _updateBalances(String groupId) async {
    _balances = await _expenseService.calculateBalances(groupId);
    notifyListeners();
  }

  Future<({ExpenseModel? expense, String? error})> createEqualSplitExpense({
    required String groupId,
    required String description,
    required double totalAmount,
    required String paidBy,
    required List<String> participantIds,
    String? category,
    required DateTime date,
    required String createdBy,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final splitAmount = totalAmount / participantIds.length;
    final splits = participantIds
        .map((userId) => ExpenseSplit(
              userId: userId,
              amount: double.parse(splitAmount.toStringAsFixed(2)),
            ))
        .toList();

    final result = await _expenseService.createExpense(
      groupId: groupId,
      description: description,
      totalAmount: totalAmount,
      paidBy: paidBy,
      splits: splits,
      splitType: SplitType.equal,
      category: category,
      date: date,
      createdBy: createdBy,
    );

    if (result.error != null) {
      _errorMessage = result.error;
      notifyListeners();
    }

    return result;
  }

  Future<bool> deleteExpense({
    required String groupId,
    required String expenseId,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final result = await _expenseService.deleteExpense(
      groupId: groupId,
      expenseId: expenseId,
    );

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }

    return result.success;
  }

  double getBalanceForUser(String userId) {
    return _balances[userId] ?? 0;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _expensesSubscription?.cancel();
    super.dispose();
  }
}