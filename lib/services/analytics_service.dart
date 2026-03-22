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
      // Fetch expenses
      final snapshot = await _expensesCollection(groupId).get();
      final expenses = snapshot.docs
          .map((doc) => ExpenseModel.fromFirestore(doc))
          .toList();

      if (expenses.isEmpty) {
        return GroupAnalytics(
          totalExpenses: 0,
          expenseCount: 0,
          averageExpense: 0,
          categoryBreakdown: [],
          monthlySpending: [],
          userSpending: [],
        );
      }

      // Fetch user names
      final Map<String, String> userNames = {};
      if (memberIds.length <= 10) {
        final usersSnapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: memberIds)
            .get();
        for (final doc in usersSnapshot.docs) {
          final user = UserModel.fromFirestore(doc);
          userNames[doc.id] = user.name;
        }
      }

      // Calculate totals
      final totalExpenses = expenses.fold(0.0, (sum, e) => sum + e.totalAmount);
      final expenseCount = expenses.length;
      final averageExpense = totalExpenses / expenseCount;

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
        userSpending.sort((a, b) => b.totalPaid.compareTo(a.totalPaid));
        topSpender = userSpending.first.userName;
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
      );
    } catch (e) {
      print('Error getting analytics: $e');
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
      breakdown.add(CategorySpending(
        category: category,
        amount: amount,
        percentage: totalExpenses > 0 ? (amount / totalExpenses) * 100 : 0,
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
      final key = '${expense.date.year}-${expense.date.month}';
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

    // Return last 6 months
    if (monthly.length > 6) {
      return monthly.sublist(monthly.length - 6);
    }
    return monthly;
  }

  List<UserSpending> _calculateUserSpending(
    List<ExpenseModel> expenses,
    Map<String, String> userNames,
  ) {
    final Map<String, double> userPaid = {};
    final Map<String, double> userOwed = {};
    final Map<String, int> userCounts = {};

    for (final expense in expenses) {
      // Track what each user paid
      userPaid[expense.paidBy] = (userPaid[expense.paidBy] ?? 0) + expense.totalAmount;
      userCounts[expense.paidBy] = (userCounts[expense.paidBy] ?? 0) + 1;

      // Track what each user owes
      for (final split in expense.splits) {
        userOwed[split.userId] = (userOwed[split.userId] ?? 0) + split.amount;
      }
    }

    // Combine all unique users
    final allUsers = <String>{...userPaid.keys, ...userOwed.keys};

    final List<UserSpending> spending = [];
    for (final userId in allUsers) {
      spending.add(UserSpending(
        userId: userId,
        userName: userNames[userId] ?? 'Unknown',
        totalPaid: userPaid[userId] ?? 0,
        totalOwed: userOwed[userId] ?? 0,
        expenseCount: userCounts[userId] ?? 0,
      ));
    }

    return spending;
  }
}