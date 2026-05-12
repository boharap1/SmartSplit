import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/group_model.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants.dart';
import '../group/settlements_screen.dart';

class SettleUpScreen extends StatelessWidget {
  final Map<String, double> groupBalances;
  final List<GroupModel> groups;
  final String currentUserId;

  const SettleUpScreen({
    super.key,
    required this.groupBalances,
    required this.groups,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.read<SettingsProvider>().currencySymbol;
    final outstanding = groups
        .where((g) => (groupBalances[g.groupId] ?? 0).abs() > 0.01)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settle Up'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (outstanding.isEmpty)
            _buildAllSettled()
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Groups with outstanding balances',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: outstanding.length,
                itemBuilder: (_, i) =>
                    _groupCard(context, outstanding[i], cs),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: AppConstants.primaryColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.handshake_outlined, size: 48, color: Colors.white),
          const SizedBox(height: 12),
          const Text(
            'Settle Up',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select a group to view optimised\nsettlements and record payments.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAllSettled() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 64,
              color: AppConstants.successColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'All Settled Up!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'No outstanding balances across any group.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(BuildContext context, GroupModel group, String cs) {
    final bal = groupBalances[group.groupId] ?? 0;
    final isOwed = bal > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.groupName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isOwed
                      ? 'You\'re owed $cs${bal.toStringAsFixed(2)}'
                      : 'You owe $cs${bal.abs().toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isOwed
                        ? AppConstants.successColor
                        : AppConstants.errorColor,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettlementsScreen(
                  group: group,
                  currentUserId: currentUserId,
                ),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
  }
}
