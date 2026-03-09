import 'dart:math';

class OptimizedSettlement {
  final String fromUserId;
  final String toUserId;
  final double amount;
  final int priority;

  OptimizedSettlement({
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.priority,
  });
}

class SettlementResult {
  final Map<String, double> netBalances;
  final List<OptimizedSettlement> settlements;
  final int originalTransactionCount;
  final int optimizedTransactionCount;
  final double totalDebt;
  final bool isFullySettleable;
  final String? error;

  SettlementResult({
    required this.netBalances,
    required this.settlements,
    required this.originalTransactionCount,
    required this.optimizedTransactionCount,
    required this.totalDebt,
    required this.isFullySettleable,
    this.error,
  });

  double get transactionReduction {
    if (originalTransactionCount == 0) return 0;
    return ((originalTransactionCount - optimizedTransactionCount) /
            originalTransactionCount) *
        100;
  }
}

class SettlementAlgorithm {
  static const double _epsilon = 0.01;

  static SettlementResult calculateSettlements(Map<String, double> balances) {
    final totalSum = balances.values.fold(0.0, (sum, val) => sum + val);
    if (totalSum.abs() > _epsilon * balances.length) {
      return SettlementResult(
        netBalances: balances,
        settlements: [],
        originalTransactionCount: 0,
        optimizedTransactionCount: 0,
        totalDebt: 0,
        isFullySettleable: false,
        error: 'Balance mismatch: £${totalSum.toStringAsFixed(2)}',
      );
    }

    final List<_UserBalance> creditors = [];
    final List<_UserBalance> debtors = [];

    balances.forEach((userId, balance) {
      final roundedBalance = _roundToTwoDecimals(balance);
      if (roundedBalance > _epsilon) {
        creditors.add(_UserBalance(userId, roundedBalance));
      } else if (roundedBalance < -_epsilon) {
        debtors.add(_UserBalance(userId, -roundedBalance));
      }
    });

    final totalDebt = debtors.fold(0.0, (sum, d) => sum + d.amount);
    final originalCount = creditors.length * debtors.length;

    creditors.sort((a, b) => b.amount.compareTo(a.amount));
    debtors.sort((a, b) => b.amount.compareTo(a.amount));

    final settlements = _generateOptimalSettlements(creditors, debtors);

    return SettlementResult(
      netBalances: balances,
      settlements: settlements,
      originalTransactionCount: originalCount,
      optimizedTransactionCount: settlements.length,
      totalDebt: totalDebt,
      isFullySettleable: true,
    );
  }

  static List<OptimizedSettlement> _generateOptimalSettlements(
    List<_UserBalance> creditors,
    List<_UserBalance> debtors,
  ) {
    final List<OptimizedSettlement> settlements = [];
    int priority = 0;

    final creditorsWork = creditors.map((c) => _UserBalance(c.userId, c.amount)).toList();
    final debtorsWork = debtors.map((d) => _UserBalance(d.userId, d.amount)).toList();

    int i = 0;
    int j = 0;

    while (i < creditorsWork.length && j < debtorsWork.length) {
      final creditor = creditorsWork[i];
      final debtor = debtorsWork[j];

      final settlementAmount = min(creditor.amount, debtor.amount);

      if (settlementAmount > _epsilon) {
        settlements.add(OptimizedSettlement(
          fromUserId: debtor.userId,
          toUserId: creditor.userId,
          amount: _roundToTwoDecimals(settlementAmount),
          priority: priority++,
        ));
      }

      creditor.amount -= settlementAmount;
      debtor.amount -= settlementAmount;

      if (creditor.amount < _epsilon) i++;
      if (debtor.amount < _epsilon) j++;
    }

    return settlements;
  }

  static double _roundToTwoDecimals(double value) {
    return (value * 100).round() / 100;
  }
}

class _UserBalance {
  final String userId;
  double amount;

  _UserBalance(this.userId, this.amount);
}