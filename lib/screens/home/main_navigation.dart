import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/notification_provider.dart';
import '../../utils/constants.dart';
import '../profile/profile_screen.dart';
import 'home_tab.dart';
import 'activity_tab.dart';
import 'insights_tab.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _initialized = false;

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      HomeTab(onSettleUp: _navigateToActivity),
      const ActivityTab(),
      const InsightsTab(),
      const ProfileScreen(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWelcome());
  }

  void _navigateToActivity() => setState(() => _currentIndex = 1);

  void _maybeShowWelcome() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.justRegistered) return;
    auth.consumeJustRegistered();
    final firstName = auth.user?.name.split(' ').first ?? 'there';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Welcome to SmartSplit, $firstName! Your account is ready.'),
        backgroundColor: AppConstants.successColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final userId = context.read<AuthProvider>().firebaseUser?.uid;
      if (userId != null) {
        context.read<GroupProvider>().startListeningToGroups(userId);
        context.read<NotificationProvider>().initialize(userId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFF0C2B22),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 24,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  index: 0,
                  current: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
                _NavItem(
                  icon: Icons.people_rounded,
                  label: 'Activity',
                  index: 1,
                  current: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
                _NavItem(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Insights',
                  index: 2,
                  current: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: 'Account',
                  index: 3,
                  current: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final void Function(int) onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: isActive
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          color: const Color(0xFF0C2B22), size: 18),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFF0C2B22),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : Icon(
                  icon,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 22,
                ),
        ),
      ),
    );
  }
}
