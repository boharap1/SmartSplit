import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense_model.dart';
import '../models/analytics_model.dart';
import '../models/user_model.dart';

class AnalyticsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _expensesCollection(String groupId) {
    return _firestore.collection('groups').doc(groupId).collection('expenses');
  }

  Future<GroupAnalytics> getGroupAnalytics(String groupId, List<String> memberIds) async {
    try {
      // Fetch all expenses
      final snapshot = await _expensesCollection(groupId).get();
      final expenses = snapshot.docs
          .map((doc) => ExpenseModel.fromFirestore(doc))
          .toList();

      // Fetch user names
      final Map<String, String> userNames = {};
      if (memberIds.isNotEmpty && memberIds.length <= 10) {
        final usersSnapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: memberIds)
            .get();
        for (final doc in usersSnapshot.docs) {
          final user = UserModel.fromFirestore(doc);
          userNames[doc.id] = user.name;
        }
      }

      if (expenses.isEmpty) {
        return GroupAnalytics(
          totalExpenses: 0,
          expenseCount: 0,
          averageExpense: 0,
          categoryBreakdown: [],
          monthlySpending: [],
          userSpending: [],
          rawExpenses: [],
          userNames: userNames,
        );
      }

      // Calculate full analytics
      return _calculateAnalytics(expenses, userNames);
    } catch (e) {
      debugPrint('Error getting analytics: $e');
      return GroupAnalytics(
        totalExpenses: 0,
        expenseCount: 0,
        averageExpense: 0,
        categoryBreakdown: [],
        monthlySpending: [],
        userSpending: [],
      );
    }
  }

  /// Filter expenses by date range and recalculate ALL analytics
  GroupAnalytics filterAnalyticsByDate(
    GroupAnalytics fullAnalytics,
    DateTime startDate,
    DateTime endDate,
  ) {
    // Filter expenses by actual date
    final filteredExpenses = fullAnalytics.rawExpenses.where((expense) {
      final expenseDate = expense.date;
      return expenseDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
          expenseDate.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();

    if (filteredExpenses.isEmpty) {
      return GroupAnalytics(
        totalExpenses: 0,
        expenseCount: 0,
        averageExpense: 0,
        categoryBreakdown: [],
        monthlySpending: [],
        userSpending: [],
        rawExpenses: filteredExpenses,
        userNames: fullAnalytics.userNames,
      );
    }

    // Recalculate everything from filtered expenses
    return _calculateAnalytics(filteredExpenses, fullAnalytics.userNames);
  }

  /// Core calculation method - used for both full and filtered data
  GroupAnalytics _calculateAnalytics(
    List<ExpenseModel> expenses,
    Map<String, String> userNames,
  ) {
    // Calculate totals
    final totalExpenses = expenses.fold(0.0, (acc, e) => acc + e.totalAmount);
    final expenseCount = expenses.length;
    final averageExpense = expenseCount > 0 ? totalExpenses / expenseCount : 0.0;

    // Category breakdown
    final categoryBreakdown = _calculateCategoryBreakdown(expenses, totalExpenses);

    // Monthly spending
    final monthlySpending = _calculateMonthlySpending(expenses);

    // User spending
    final userSpending = _calculateUserSpending(expenses, userNames);

    // Top category
    String? topCategory;
    if (categoryBreakdown.isNotEmpty) {
      topCategory = categoryBreakdown.first.category;
    }

    // Top spender
    String? topSpender;
    if (userSpending.isNotEmpty) {
      final sorted = List<UserSpending>.from(userSpending)
        ..sort((a, b) => b.totalPaid.compareTo(a.totalPaid));
      topSpender = sorted.first.userName;
    }

    return GroupAnalytics(
      totalExpenses: totalExpenses,
      expenseCount: expenseCount,
      averageExpense: averageExpense,
      categoryBreakdown: categoryBreakdown,
      monthlySpending: monthlySpending,
      userSpending: userSpending,
      topCategory: topCategory,
      topSpender: topSpender,
      rawExpenses: expenses,
      userNames: userNames,
    );
  }

  List<CategorySpending> _calculateCategoryBreakdown(
    List<ExpenseModel> expenses,
    double totalExpenses,
  ) {
    final Map<String, double> categoryTotals = {};
    final Map<String, int> categoryCounts = {};

    for (final expense in expenses) {
      final category = expense.category ?? 'Other';
      categoryTotals[category] = (categoryTotals[category] ?? 0) + expense.totalAmount;
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }

    final List<CategorySpending> breakdown = [];
    categoryTotals.forEach((category, amount) {
      final percentage = totalExpenses > 0 ? (amount / totalExpenses) * 100 : 0.0;
      breakdown.add(CategorySpending(
        category: category,
        amount: amount,
        percentage: percentage,
        count: categoryCounts[category] ?? 0,
      ));
    });

    // Sort by amount descending
    breakdown.sort((a, b) => b.amount.compareTo(a.amount));
    return breakdown;
  }

  List<MonthlySpending> _calculateMonthlySpending(List<ExpenseModel> expenses) {
    final Map<String, double> monthlyTotals = {};
    final Map<String, int> monthlyCounts = {};

    for (final expense in expenses) {
      final key = '${expense.date.year}-${expense.date.month.toString().padLeft(2, '0')}';
      monthlyTotals[key] = (monthlyTotals[key] ?? 0) + expense.totalAmount;
      monthlyCounts[key] = (monthlyCounts[key] ?? 0) + 1;
    }

    final List<MonthlySpending> monthly = [];
    monthlyTotals.forEach((key, amount) {
      final parts = key.split('-');
      monthly.add(MonthlySpending(
        year: int.parse(parts[0]),
        month: int.parse(parts[1]),
        amount: amount,
        expenseCount: monthlyCounts[key] ?? 0,
      ));
    });

    // Sort by date
    monthly.sort((a, b) {
      final dateA = DateTime(a.year, a.month);
      final dateB = DateTime(b.year, b.month);
      return dateA.compareTo(dateB);
    });

    // Return last 12 months
    if (monthly.length > 12) {
      return monthly.sublist(monthly.length - 12);
    }
    return monthly;
  }

  List<UserSpending> _calculateUserSpending(
    List<ExpenseModel> expenses,
    Map<String, String> userNames,
  ) {
    final Map<String, double> userPaid = {};
    final Map<String, int> userCounts = {};

    // Calculate total group spending for percentage
    final totalGroupSpending = expenses.fold(0.0, (acc, e) => acc + e.totalAmount);

    for (final expense in expenses) {
      // Track what each user paid
      userPaid[expense.paidBy] = (userPaid[expense.paidBy] ?? 0) + expense.totalAmount;
      userCounts[expense.paidBy] = (userCounts[expense.paidBy] ?? 0) + 1;
    }

    final List<UserSpending> spending = [];
    userPaid.forEach((userId, totalPaid) {
      spending.add(UserSpending(
        userId: userId,
        userName: userNames[userId] ?? 'Unknown',
        totalPaid: totalPaid,
        totalOwed: totalGroupSpending > 0 ? (totalPaid / totalGroupSpending) * 100 : 0,
        expenseCount: userCounts[userId] ?? 0,
      ));
    });

    // Sort by total paid descending
    spending.sort((a, b) => b.totalPaid.compareTo(a.totalPaid));
    return spending;
  }
}