import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../utils/constants.dart';
import 'home_tab.dart';
import 'groups_tab.dart';
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

  final List<Widget> _tabs = const [
    HomeTab(),
    GroupsTab(),
    ActivityTab(),
    InsightsTab(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final userId = context.read<AuthProvider>().firebaseUser?.uid;
      if (userId != null) {
        context.read<GroupProvider>().startListeningToGroups(userId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          backgroundColor: Colors.white,
          indicatorColor: AppConstants.primaryColor.withValues(alpha: 0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 68,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: Colors.grey[600]),
              selectedIcon: const Icon(
                Icons.home_rounded,
                color: AppConstants.primaryColor,
              ),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.group_outlined, color: Colors.grey[600]),
              selectedIcon: const Icon(
                Icons.group_rounded,
                color: AppConstants.primaryColor,
              ),
              label: 'Groups',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined, color: Colors.grey[600]),
              selectedIcon: const Icon(
                Icons.receipt_long_rounded,
                color: AppConstants.primaryColor,
              ),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined, color: Colors.grey[600]),
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
