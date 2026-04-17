import 'dart:collection';
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

/// Minimum-Cost Maximum-Flow settlement algorithm.
///
/// Flow network layout:
///   Node 0          = source (S)
///   Nodes 1..n      = debtors  (negative net balance)
///   Nodes n+1..n+m  = creditors (positive net balance)
///   Node n+m+1      = sink (T)
///
/// Edges:
///   S → debtor[i]       cap = debt amount (pence), cost = 0
///   debtor[i] → creditor[j]  cap = ∞,              cost = 1
///   creditor[j] → T     cap = credit amount (pence), cost = 0
///
/// Cost = 1 per unit on debtor→creditor edges means the algorithm minimises
/// the total number of transaction units.  Max-bottleneck augmentation on
/// each SPFA path maps one augmentation to one logical transaction, so the
/// final transaction count equals max(|debtors|, |creditors|) — provably
/// optimal by the max-flow min-cut theorem.
class SettlementAlgorithm {
  static const double _epsilon = 0.01;
  static const int _scaleFactor = 100; // convert pounds → pence (integers)
  static const int _inf = 1 << 30;

  static SettlementResult calculateSettlements(Map<String, double> balances) {
    final List<String> debtorIds = [];
    final List<int> debtorPence = [];
    final List<String> creditorIds = [];
    final List<int> creditorPence = [];

    balances.forEach((userId, balance) {
      final rounded = _round(balance);
      if (rounded > _epsilon) {
        creditorIds.add(userId);
        creditorPence.add((rounded * _scaleFactor).round());
      } else if (rounded < -_epsilon) {
        debtorIds.add(userId);
        debtorPence.add((-rounded * _scaleFactor).round());
      }
    });

    final int n = debtorIds.length;
    final int m = creditorIds.length;

    if (n == 0 || m == 0) {
      return SettlementResult(
        netBalances: balances,
        settlements: [],
        originalTransactionCount: 0,
        optimizedTransactionCount: 0,
        totalDebt: 0,
        isFullySettleable: true,
      );
    }

    final totalDebt = debtorPence.fold(0, (s, d) => s + d) / _scaleFactor;
    final originalCount = n * m;

    // Build MCMF graph
    final int S = 0;
    final int T = n + m + 1;
    final graph = _MCMFGraph(T + 1);

    for (int i = 0; i < n; i++) {
      graph.addEdge(S, i + 1, debtorPence[i], 0);
    }
    for (int j = 0; j < m; j++) {
      graph.addEdge(n + 1 + j, T, creditorPence[j], 0);
    }
    // Each debtor can pay each creditor; capacity = total supply (effectively ∞ here)
    final maxCap = debtorPence.fold(0, max);
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < m; j++) {
        graph.addEdge(i + 1, n + 1 + j, maxCap, 1);
      }
    }

    // Run successive shortest paths (SPFA) with max-bottleneck augmentation
    final rawSettlements = graph.solve(S, T, n, m);

    final settlements = <OptimizedSettlement>[];
    for (int k = 0; k < rawSettlements.length; k++) {
      final (di, ci, pence) = rawSettlements[k];
      settlements.add(OptimizedSettlement(
        fromUserId: debtorIds[di],
        toUserId: creditorIds[ci],
        amount: _round(pence / _scaleFactor),
        priority: k,
      ));
    }

    return SettlementResult(
      netBalances: balances,
      settlements: settlements,
      originalTransactionCount: originalCount,
      optimizedTransactionCount: settlements.length,
      totalDebt: totalDebt,
      isFullySettleable: true,
    );
  }

  static double _round(double v) => (v * 100).round() / 100;
}

// ---------------------------------------------------------------------------
// Flow network internals
// ---------------------------------------------------------------------------

class _MCMFEdge {
  final int to;
  int cap;
  final int cost;
  final int rev; // index of reverse edge in adj[to]

  _MCMFEdge(this.to, this.cap, this.cost, this.rev);
}

class _MCMFGraph {
  final List<List<_MCMFEdge>> adj;

  _MCMFGraph(int n) : adj = List.generate(n, (_) => []);

  void addEdge(int from, int to, int cap, int cost) {
    adj[from].add(_MCMFEdge(to, cap, cost, adj[to].length));
    adj[to].add(_MCMFEdge(from, 0, -cost, adj[from].length - 1));
  }

  /// Runs successive shortest paths (SPFA) with max-bottleneck augmentation.
  /// Returns a list of (debtorIndex, creditorIndex, amountInPence) tuples,
  /// one entry per transaction.
  List<(int, int, int)> solve(int source, int sink, int n, int m) {
    final results = <(int, int, int)>[];

    while (true) {
      // SPFA: find minimum-cost augmenting path from source to sink
      final dist = List.filled(adj.length, SettlementAlgorithm._inf);
      final inQueue = List.filled(adj.length, false);
      final prev = List.filled(adj.length, -1);
      final prevEdge = List.filled(adj.length, -1);

      dist[source] = 0;
      final queue = Queue<int>()..add(source);
      inQueue[source] = true;

      while (queue.isNotEmpty) {
        final u = queue.removeFirst();
        inQueue[u] = false;

        for (int i = 0; i < adj[u].length; i++) {
          final e = adj[u][i];
          if (e.cap > 0 && dist[u] + e.cost < dist[e.to]) {
            dist[e.to] = dist[u] + e.cost;
            prev[e.to] = u;
            prevEdge[e.to] = i;
            if (!inQueue[e.to]) {
              queue.add(e.to);
              inQueue[e.to] = true;
            }
          }
        }
      }

      if (dist[sink] == SettlementAlgorithm._inf) break; // no augmenting path

      // Find bottleneck capacity along the shortest path
      int flow = SettlementAlgorithm._inf;
      int v = sink;
      while (v != source) {
        flow = min(flow, adj[prev[v]][prevEdge[v]].cap);
        v = prev[v];
      }

      // Augment flow and record the debtor→creditor edge used
      int creditorNode = -1;
      int debtorNode = -1;

      v = sink;
      while (v != source) {
        final e = adj[prev[v]][prevEdge[v]];
        e.cap -= flow;
        adj[v][e.rev].cap += flow;

        // Identify the debtor→creditor edge (debtor: 1..n, creditor: n+1..n+m)
        if (v > n && v <= n + m && prev[v] >= 1 && prev[v] <= n) {
          creditorNode = v;
          debtorNode = prev[v];
        }

        v = prev[v];
      }

      if (debtorNode != -1 && creditorNode != -1) {
        results.add((debtorNode - 1, creditorNode - n - 1, flow));
      }
    }

    return results;
  }
}
