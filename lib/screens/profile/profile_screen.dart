import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../models/bank_details_model.dart';
import '../../services/settlement_service.dart';
import '../../utils/constants.dart';
import 'bank_details_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SettlementService _settlementService = SettlementService();
  BankDetails? _bankDetails;
  bool _isLoadingBank = true;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBankDetails());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadBankDetails() async {
    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null) return;
    final details = await _settlementService.getBankDetails(userId);
    if (mounted)
      setState(() {
        _bankDetails = details;
        _isLoadingBank = false;
      });
  }

  void _navigateToBankDetails() async {
    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null) return;
    final result = await Navigator.push<BankDetails>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BankDetailsScreen(userId: userId, existingDetails: _bankDetails),
      ),
    );
    if (result != null) setState(() => _bankDetails = result);
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<GroupProvider>().stopListeningToGroups();
              context.read<AuthProvider>().signOut();
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppConstants.errorColor),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final groupCount = context.watch<GroupProvider>().groupCount;
    final isVerified = context.watch<AuthProvider>().isEmailVerified;

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppConstants.primaryColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00796B), AppConstants.primaryColor],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          user?.name.isNotEmpty == true
                              ? user!.name[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user?.name ?? 'User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _stat(
                            'Groups',
                            '$groupCount',
                            Icons.group_outlined,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: Colors.grey[200],
                        ),
                        Expanded(
                          child: _stat(
                            'Bank',
                            _isLoadingBank
                                ? '...'
                                : (_bankDetails != null ? 'Set up' : 'Not set'),
                            Icons.account_balance_outlined,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: Colors.grey[200],
                        ),
                        Expanded(
                          child: _stat(
                            'Verified',
                            isVerified ? 'Yes' : 'No',
                            Icons.verified_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Account
                  _sectionHeader('Account'),
                  _menuCard([
                    _menuItem(
                      Icons.person_outline,
                      AppConstants.primaryColor,
                      'Edit Profile',
                      'Update your name',
                      () => _showEditName(),
                    ),
                    _div(),
                    _menuItem(
                      Icons.account_balance_outlined,
                      const Color(0xFF5C6BC0),
                      'Bank Details',
                      _bankDetails != null
                          ? '${_bankDetails!.bankName} · ${_bankDetails!.maskedAccountNumber}'
                          : 'Add bank details',
                      _navigateToBankDetails,
                    ),
                    _div(),
                    _menuItem(
                      Icons.qr_code_rounded,
                      const Color(0xFF42A5F5),
                      'My QR Code',
                      'Share your profile',
                      () {},
                    ),
                  ]),
                  const SizedBox(height: 20),

                  _sectionHeader('Preferences'),
                  _menuCard([
                    _menuItem(
                      Icons.dark_mode_outlined,
                      const Color(0xFFAB47BC),
                      'Theme',
                      'Light mode',
                      () {},
                    ),
                    _div(),
                    _menuItem(
                      Icons.notifications_outlined,
                      const Color(0xFFFF7043),
                      'Notifications',
                      'Manage preferences',
                      () {},
                    ),
                  ]),
                  const SizedBox(height: 20),

                  _sectionHeader('Support'),
                  _menuCard([
                    _menuItem(
                      Icons.feedback_outlined,
                      const Color(0xFF26A69A),
                      'Send Feedback',
                      'Help us improve',
                      () {},
                    ),
                    _div(),
                    _menuItem(
                      Icons.star_outline_rounded,
                      const Color(0xFFFFA726),
                      'Rate SmartSplit',
                      'Leave a review',
                      () {},
                    ),
                    _div(),
                    _menuItem(
                      Icons.mail_outline_rounded,
                      const Color(0xFF42A5F5),
                      'Contact Us',
                      'Get in touch',
                      () {},
                    ),
                    _div(),
                    _menuItem(
                      Icons.info_outline_rounded,
                      Colors.grey,
                      'About',
                      'Version ${AppConstants.appVersion}',
                      () {},
                    ),
                  ]),
                  const SizedBox(height: 20),

                  _menuCard([
                    _menuItem(
                      Icons.logout_rounded,
                      AppConstants.errorColor,
                      'Sign Out',
                      'Sign out of your account',
                      _showLogoutDialog,
                      titleColor: AppConstants.errorColor,
                    ),
                  ]),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) => Column(
    children: [
      Icon(icon, color: AppConstants.primaryColor, size: 22),
      const SizedBox(height: 6),
      Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    ],
  );

  Widget _sectionHeader(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey[500],
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _menuCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(children: children),
  );

  Widget _menuItem(
    IconData icon,
    Color color,
    String title,
    String sub,
    VoidCallback onTap, {
    Color? titleColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? Colors.black87,
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey[400],
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _div() => Padding(
    padding: const EdgeInsets.only(left: 70),
    child: Divider(height: 1, color: Colors.grey[100]),
  );

  void _showEditName() {
    _nameController.text = context.read<AuthProvider>().user?.name ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Name'),
        content: TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Display Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Profile update coming soon'),
                  backgroundColor: AppConstants.primaryColor,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
