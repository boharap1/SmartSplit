import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/notification_provider.dart';
import '../../utils/constants.dart';
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
      HomeTab(onSettleUp: _navigateToSettleUp),
      const ActivityTab(),
      const InsightsTab(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWelcome());
  }

  void _navigateToSettleUp() => setState(() => _currentIndex = 1);

  void _maybeShowWelcome() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.justRegistered) return;
    auth.consumeJustRegistered();
    final firstName = auth.user?.name.split(' ').first ?? 'there';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Welcome to SmartSplit, $firstName! Your account is ready.'),
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
        // Initialise notifications: request FCM permission, register token,
        // and begin streaming the user's notification subcollection.
        context.read<NotificationProvider>().initialize(userId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: cs.surface,
          indicatorColor: AppConstants.primaryColor.withValues(alpha: 0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 68,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: cs.onSurfaceVariant),
              selectedIcon: const Icon(
                Icons.home_rounded,
                color: AppConstants.primaryColor,
              ),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.group_outlined, color: cs.onSurfaceVariant),
              selectedIcon: const Icon(
                Icons.group_rounded,
                color: AppConstants.primaryColor,
              ),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined, color: cs.onSurfaceVariant),
              selectedIcon: const Icon(
                Icons.insights_rounded,
                color: AppConstants.primaryColor,
              ),
              label: 'Insights',
            ),
          ],
        ),
      ),
    );
  }
}
