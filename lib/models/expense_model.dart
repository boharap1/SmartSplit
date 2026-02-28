import 'package:cloud_firestore/cloud_firestore.dart';

enum SplitType { equal, percentage, exact }

class ExpenseSplit {
  final String userId;
  final double amount;
  final double? percentage;

  ExpenseSplit({
    required this.userId,
    required this.amount,
    this.percentage,
  });

  factory ExpenseSplit.fromMap(Map<String, dynamic> map) {
    return ExpenseSplit(
      userId: map['userId'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      percentage: map['percentage']?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'amount': amount,
      if (percentage != null) 'percentage': percentage,
    };
  }
}

class ExpenseModel {
  final String expenseId;
  final String groupId;
  final String description;
  final double totalAmount;
  final String paidBy;
  final List<ExpenseSplit> splits;
  final SplitType splitType;
  final String? category;
  final String? receiptUrl;
  final DateTime date;
  final DateTime createdAt;
  final String createdBy;

  ExpenseModel({
    required this.expenseId,
    required this.groupId,
    required this.description,
    required this.totalAmount,
    required this.paidBy,
    required this.splits,
    required this.splitType,
    this.category,
    this.receiptUrl,
    required this.date,
    required this.createdAt,
    required this.createdBy,
  });

  factory ExpenseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final splitsList = (data['splits'] as List<dynamic>?)
            ?.map((s) => ExpenseSplit.fromMap(s as Map<String, dynamic>))
            .toList() ??
        [];

    SplitType type = SplitType.equal;
    if (data['splitType'] == 'percentage') {
      type = SplitType.percentage;
    } else if (data['splitType'] == 'exact') {
      type = SplitType.exact;
    }

    return ExpenseModel(
      expenseId: doc.id,
      groupId: data['groupId'] ?? '',
      description: data['description'] ?? '',
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      paidBy: data['paidBy'] ?? '',
      splits: splitsList,
      splitType: type,
      category: data['category'],
      receiptUrl: data['receiptUrl'],
      date: (data['date'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    String typeString = 'equal';
    if (splitType == SplitType.percentage) {
      typeString = 'percentage';
    } else if (splitType == SplitType.exact) {
      typeString = 'exact';
    }

    return {
      'groupId': groupId,
      'description': description,
      'totalAmount': totalAmount,
      'paidBy': paidBy,
      'splits': splits.map((s) => s.toMap()).toList(),
      'splitType': typeString,
      'category': category,
      'receiptUrl': receiptUrl,
      'date': Timestamp.fromDate(date),
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };
  }

  double getAmountForUser(String userId) {
    final split = splits.firstWhere(
      (s) => s.userId == userId,
      orElse: () => ExpenseSplit(userId: userId, amount: 0),
    );
    return split.amount;
  }

  bool isPayer(String userId) => paidBy == userId;

  bool involvesUser(String userId) {
    return paidBy == userId || splits.any((s) => s.userId == userId);
  }
}