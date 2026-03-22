import 'expense_model.dart';

class CategorySpending {
  final String category;
  final double amount;
  final double percentage;
  final int count;

  CategorySpending({
    required this.category,
    required this.amount,
    required this.percentage,
    required this.count,
  });
}

class MonthlySpending {
  final int year;
  final int month;
  final double amount;
  final int expenseCount;

  MonthlySpending({
    required this.year,
    required this.month,
    required this.amount,
    required this.expenseCount,
  });

  String get monthName {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  String get label => '$monthName $year';
}

class UserSpending {
  final String userId;
  final String userName;
  final double totalPaid;
  final double totalOwed;
  final int expenseCount;

  UserSpending({
    required this.userId,
    required this.userName,
    required this.totalPaid,
    required this.totalOwed,
    required this.expenseCount,
  });

  double get netBalance => totalPaid - totalOwed;
}

class GroupAnalytics {
  final double totalExpenses;
  final int expenseCount;
  final double averageExpense;
  final List<CategorySpending> categoryBreakdown;
  final List<MonthlySpending> monthlySpending;
  final List<UserSpending> userSpending;
  final String? topCategory;
  final String? topSpender;
  final List<ExpenseModel> rawExpenses;
  final Map<String, String> userNames;

  GroupAnalytics({
    required this.totalExpenses,
    required this.expenseCount,
    required this.averageExpense,
    required this.categoryBreakdown,
    required this.monthlySpending,
    required this.userSpending,
    this.topCategory,
    this.topSpender,
    this.rawExpenses = const [],
    this.userNames = const {},
  });
}