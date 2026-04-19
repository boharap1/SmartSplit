import 'dart:async';
import 'package:flutter/material.dart';
import '../models/expense_model.dart';
import '../models/notification_model.dart';
import '../services/expense_service.dart';
import '../services/notification_service.dart';

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
    // Optional – used to build notification messages.
    String? groupName,
    String? paidByName,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final int totalPence = (totalAmount * 100).round();
    final int count = participantIds.length;
    final int basePence = totalPence ~/ count;
    final int extraPence = totalPence - basePence * count;

    final splits = <ExpenseSplit>[];
    for (int i = 0; i < count; i++) {
      final int pence = i < extraPence ? basePence + 1 : basePence;
      splits.add(ExpenseSplit(userId: participantIds[i], amount: pence / 100.0));
    }

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

    // Notify other participants about the new expense.
    if (result.expense != null && participantIds.length > 1) {
      final actor = paidByName ?? 'Someone';
      final inGroup = groupName != null ? ' in $groupName' : '';
      NotificationService.dispatch(
        toUserIds: participantIds,
        excludeUserId: createdBy,
        type: NotificationType.expenseAdded,
        title: 'New expense$inGroup',
        body: '$actor added "$description" (£${totalAmount.toStringAsFixed(2)})',
        groupId: groupId,
        relatedId: result.expense!.expenseId,
        fromUserName: paidByName,
      );
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