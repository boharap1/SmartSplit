import 'package:flutter_test/flutter_test.dart';
import 'package:smartsplit/services/settlement_algorithm.dart';

void main() {
  group('SettlementAlgorithm', () {
    test('two users - simple debt', () {
      final balances = {'alice': 15.0, 'bob': -15.0};
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.isFullySettleable, true);
      expect(result.settlements.length, 1);
      expect(result.settlements[0].fromUserId, 'bob');
      expect(result.settlements[0].toUserId, 'alice');
      expect(result.settlements[0].amount, 15.0);
    });

    test('three users - optimises to minimum transactions', () {
      final balances = {'alice': 20.0, 'bob': -12.0, 'charlie': -8.0};
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.isFullySettleable, true);
      expect(result.settlements.length, 2);
      final totalPaidToAlice = result.settlements
          .where((s) => s.toUserId == 'alice')
          .fold(0.0, (sum, s) => sum + s.amount);
      expect(totalPaidToAlice, 20.0);
    });

    test('all settled - no transactions needed', () {
      final balances = {'alice': 0.0, 'bob': 0.0, 'charlie': 0.0};
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.isFullySettleable, true);
      expect(result.settlements.isEmpty, true);
      expect(result.totalDebt, 0.0);
    });

    test('near-zero balances treated as settled', () {
      final balances = {'alice': 0.005, 'bob': -0.005};
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.settlements.isEmpty, true);
    });

    test('rounding to two decimal places', () {
      final balances = {'alice': 6.67, 'bob': -3.33, 'charlie': -3.34};
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.isFullySettleable, true);
      for (final s in result.settlements) {
        final decimals = s.amount.toString().split('.');
        if (decimals.length > 1) {
          expect(decimals[1].length, lessThanOrEqualTo(2));
        }
      }
    });

    test('multiple creditors and debtors', () {
      final balances = {
        'alice': 30.0,
        'bob': 10.0,
        'charlie': -25.0,
        'dave': -15.0,
      };
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.isFullySettleable, true);
      expect(result.totalDebt, 40.0);
      final debtorPayments = <String, double>{};
      final creditorReceipts = <String, double>{};
      for (final s in result.settlements) {
        debtorPayments[s.fromUserId] =
            (debtorPayments[s.fromUserId] ?? 0) + s.amount;
        creditorReceipts[s.toUserId] =
            (creditorReceipts[s.toUserId] ?? 0) + s.amount;
      }
      expect(debtorPayments['charlie'], 25.0);
      expect(debtorPayments['dave'], 15.0);
      expect(creditorReceipts['alice'], 30.0);
      expect(creditorReceipts['bob'], 10.0);
    });

    test('single user - no settlements needed', () {
      final balances = {'alice': 0.0};
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.isFullySettleable, true);
      expect(result.settlements.isEmpty, true);
    });

    test('unbalanced totals returns error', () {
      final balances = {'alice': 50.0, 'bob': -20.0};
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.isFullySettleable, false);
      expect(result.error, isNotNull);
    });

    test('transaction reduction is calculated correctly', () {
      final balances = {
        'alice': 30.0,
        'bob': 10.0,
        'charlie': -25.0,
        'dave': -15.0,
      };
      final result = SettlementAlgorithm.calculateSettlements(balances);
      expect(result.originalTransactionCount, 4);
      expect(result.optimizedTransactionCount, result.settlements.length);
      expect(
        result.optimizedTransactionCount,
        lessThanOrEqualTo(result.originalTransactionCount),
      );
    });
  });
}
