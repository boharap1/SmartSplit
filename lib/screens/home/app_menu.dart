import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/settlement_service.dart';
import '../../utils/constants.dart';
import '../profile/bank_details_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/personal_information_screen.dart';
import '../profile/verify_account_screen.dart';
import '../settings/language_screen.dart';
import '../settings/time_zone_screen.dart';
import '../settings/currency_screen.dart';
import '../settings/password_security_screen.dart';
import '../settings/notification_preferences_screen.dart';
import '../../providers/settings_provider.dart';

/// Opens the full-height slide-in app menu from the left edge.
void showAppMenu(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'AppMenu',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 270),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (_, animation, _, _) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _AppMenuPanel(parentContext: context),
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu panel widget
// ─────────────────────────────────────────────────────────────────────────────

class _AppMenuPanel extends StatefulWidget {
  final BuildContext parentContext;
  const _AppMenuPanel({required this.parentContext});

  @override
  State<_AppMenuPanel> createState() => _AppMenuPanelState();
}

class _AppMenuPanelState extends State<_AppMenuPanel> {
  bool _profileExpanded  = false;
  bool _settingsExpanded = false;
  bool _privacyExpanded  = false;

  // ── helpers ────────────────────────────────────────────────────────────────

  void _close() => Navigator.of(context).pop();

  /// Navigate to [screen] while cleanly closing the menu first.
  void _navigateTo(Widget screen) {
    final nav = Navigator.of(widget.parentContext);
    _close();
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }

  /// Show a "coming soon" snackbar after closing the menu.
  void _soon(String feature) {
    final sm = ScaffoldMessenger.of(widget.parentContext);
    _close();
    sm.showSnackBar(SnackBar(
      content: Text('$feature — coming soon'),
      backgroundColor: AppConstants.primaryColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _goToBankDetails() async {
    final userId =
        widget.parentContext.read<AuthProvider>().firebaseUser?.uid;
    if (userId == null) return;
    final nav = Navigator.of(widget.parentContext);
    _close();
    final details = await SettlementService().getBankDetails(userId);
    nav.push(MaterialPageRoute(
      builder: (_) => BankDetailsScreen(userId: userId, existingDetails: details),
    ));
  }

  void _showAboutDialog() {
    _close();
    showDialog(
      context: widget.parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 44,
                color: AppConstants.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'SmartSplit',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Version 1.0.0',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            const SizedBox(height: 14),
            Text(
              'Split expenses fairly with friends,\nfamily, and roommates.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppConstants.errorColor, size: 22),
            SizedBox(width: 10),
            Text('Logout'),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final auth = widget.parentContext.read<AuthProvider>();
              Navigator.pop(ctx);
              _close();
              await auth.signOut();
            },
            style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _confirmLogoutAllDevices() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.devices_outlined, color: AppConstants.primaryColor, size: 22),
            SizedBox(width: 10),
            Text('Logout All Devices'),
          ],
        ),
        content: const Text(
          'All other active sessions will be signed out the next time they open the app. '
          'Your current session will remain active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final auth = widget.parentContext.read<AuthProvider>();
              final sm   = ScaffoldMessenger.of(widget.parentContext);
              Navigator.pop(ctx);
              _close();
              final success = await auth.logoutAllDevices();
              sm.showSnackBar(SnackBar(
                content: Text(success
                    ? 'All other devices will be signed out.'
                    : auth.errorMessage ?? 'Failed to logout other devices.'),
                backgroundColor:
                    success ? AppConstants.successColor : AppConstants.errorColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            },
            style: TextButton.styleFrom(foregroundColor: AppConstants.primaryColor),
            child: const Text('Logout All'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    final passwordCtrl = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.delete_forever_rounded,
                  color: AppConstants.errorColor, size: 22),
              SizedBox(width: 10),
              Text('Delete Account'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This is permanent and cannot be undone. '
                'All your data will be permanently erased.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller:  passwordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText:   'Enter your password to confirm',
                  border:      OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setS(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                passwordCtrl.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final password = passwordCtrl.text.trim();
                if (password.isEmpty) return;
                final auth = widget.parentContext.read<AuthProvider>();
                final sm   = ScaffoldMessenger.of(widget.parentContext);
                passwordCtrl.dispose();
                Navigator.pop(ctx);
                _close();
                final success = await auth.deleteAccount(password: password);
                if (!success) {
                  sm.showSnackBar(SnackBar(
                    content: Text(
                        auth.errorMessage ?? 'Failed to delete account.'),
                    backgroundColor: AppConstants.errorColor,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ));
                }
              },
              style: TextButton.styleFrom(
                  foregroundColor: AppConstants.errorColor),
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactSheet() {
    _close();
    showModalBottomSheet(
      context: widget.parentContext,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Contact Us',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                "We'd love to hear from you.",
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
              const SizedBox(height: 20),
              _contactTile(
                icon: Icons.mail_outline_rounded,
                color: const Color(0xFF42A5F5),
                title: 'Email',
                subtitle: 'boharaprakash4444@gmail.com',
                onTap: () => launchUrl(Uri.parse(
                    'mailto:boharaprakash4444@gmail.com'
                    '?subject=SmartSplit%20Feedback')),
              ),
              const SizedBox(height: 12),
              _contactTile(
                icon: Icons.phone_outlined,
                color: AppConstants.successColor,
                title: 'Phone',
                subtitle: '+44 7901 327589',
                onTap: () => launchUrl(Uri.parse('tel:+447901327589')),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user     = context.watch<AuthProvider>().user;
    final settings = context.watch<SettingsProvider>();
    final cs       = Theme.of(context).colorScheme;
    final width         = MediaQuery.of(context).size.width * 0.82;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: double.infinity,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.only(
            topRight:    Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 24,
              offset: Offset(6, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(user),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  // ── Profile ─────────────────────────────────────────────
                  _buildExpandable(
                    icon: Icons.person_outline_rounded,
                    iconColor: AppConstants.primaryColor,
                    label: 'Profile',
                    expanded: _profileExpanded,
                    onToggle: () =>
                        setState(() => _profileExpanded = !_profileExpanded),
                    children: [
                      _subTile(
                        Icons.edit_outlined,
                        'Edit Profile',
                        () => _navigateTo(const EditProfileScreen()),
                      ),
                      _subTile(
                        Icons.badge_outlined,
                        'Personal Information',
                        () => _navigateTo(const PersonalInformationScreen()),
                      ),
                      _subTile(
                        Icons.verified_user_outlined,
                        'Verify Account',
                        () => _navigateTo(const VerifyAccountScreen()),
                      ),
                    ],
                  ),

                  // ── Settings ─────────────────────────────────────────────
                  _buildExpandable(
                    icon: Icons.tune_rounded,
                    iconColor: const Color(0xFFFF7043),
                    label: 'Settings',
                    expanded: _settingsExpanded,
                    onToggle: () =>
                        setState(() => _settingsExpanded = !_settingsExpanded),
                    children: [
                      _subTile(
                        Icons.language_rounded,
                        'Language',
                        () => _navigateTo(const LanguageScreen()),
                      ),
                      _subTile(
                        Icons.schedule_rounded,
                        'Time Zone',
                        () => _navigateTo(const TimeZoneScreen()),
                      ),
                      _subTile(
                        Icons.attach_money_rounded,
                        'Currency',
                        () => _navigateTo(const CurrencyScreen()),
                      ),
                      // Privacy nested
                      _buildPrivacySection(),
                    ],
                  ),

                  _divider(),

                  // ── Bank Details ──────────────────────────────────────────
                  _tile(
                    icon: Icons.account_balance_outlined,
                    iconColor: const Color(0xFF42A5F5),
                    label: 'Bank Details',
                    onTap: _goToBankDetails,
                  ),

                  // ── Dark Mode toggle ──────────────────────────────────────
                  _toggleTile(
                    icon: Icons.dark_mode_outlined,
                    iconColor: const Color(0xFF5C6BC0),
                    label: 'Dark Mode',
                    value: settings.isDarkMode,
                    onChanged: (_) => settings.toggleTheme(),
                  ),

                  // ── Notifications ─────────────────────────────────────────
                  _tile(
                    icon: Icons.notifications_outlined,
                    iconColor: const Color(0xFFAB47BC),
                    label: 'Notifications',
                    onTap: () => _navigateTo(const NotificationPreferencesScreen()),
                  ),

                  _divider(),

                  // ── Rate SmartSplit ───────────────────────────────────────
                  _tile(
                    icon: Icons.star_outline_rounded,
                    iconColor: const Color(0xFFFFB300),
                    label: 'Rate SmartSplit',
                    onTap: () => _soon('Rate SmartSplit'),
                  ),

                  // ── Contact Us ────────────────────────────────────────────
                  _tile(
                    icon: Icons.mail_outline_rounded,
                    iconColor: const Color(0xFF26A69A),
                    label: 'Contact Us',
                    onTap: _showContactSheet,
                  ),

                  // ── About ────────────────────────────────────────────────
                  _tile(
                    icon: Icons.info_outline_rounded,
                    iconColor: const Color(0xFF78909C),
                    label: 'About',
                    onTap: _showAboutDialog,
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),

            // ── Logout (fixed bottom) ────────────────────────────────────
            const Divider(height: 1, thickness: 1),
            _buildLogout(),
          ],
        ),
      ),
    );
  }

  // ── Header with user avatar ────────────────────────────────────────────────

  Widget _buildHeader(UserModel? user) {
    final words = (user?.name.trim() ?? '').split(' ').where((w) => w.isNotEmpty).toList();
    final initials = words.length >= 2
        ? '${words[0][0]}${words[1][0]}'.toUpperCase()
        : words.isNotEmpty
            ? words[0][0].toUpperCase()
            : '?';

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        left: 20,
        right: 16,
        bottom: 22,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00796B), AppConstants.primaryColor],
        ),
        borderRadius: BorderRadius.only(topRight: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: _close,
              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
            ),
          ),
          const SizedBox(height: 10),
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            backgroundImage: (user?.hasProfilePicture == true)
                ? NetworkImage(user!.profilePicture!)
                : null,
            child: (user?.hasProfilePicture == true)
                ? null
                : Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            user?.name ?? 'User',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            user?.email ?? '',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── Expandable section ────────────────────────────────────────────────────

  Widget _buildExpandable({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                _iconBox(icon, iconColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  // Sub-item under an expandable section (one indent level)
  Widget _subTile(IconData icon, String label, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 52, right: 16, top: 10, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 17, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  // ── Privacy nested section ────────────────────────────────────────────────

  Widget _buildPrivacySection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _privacyExpanded = !_privacyExpanded),
          child: Padding(
            padding: const EdgeInsets.only(
                left: 52, right: 16, top: 10, bottom: 10),
            child: Row(
              children: [
                Icon(Icons.security_outlined, size: 17, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Privacy',
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                  ),
                ),
                AnimatedRotation(
                  turns: _privacyExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: cs.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _privacySubTile(
                Icons.lock_outline_rounded,
                'Password & Security',
                () => _navigateTo(const PasswordSecurityScreen()),
              ),
              _privacySubTile(
                Icons.devices_outlined,
                'Logout from All Other Devices',
                _confirmLogoutAllDevices,
              ),
              _privacySubTile(
                Icons.delete_outline_rounded,
                'Delete Account',
                _confirmDeleteAccount,
                isDestructive: true,
              ),
            ],
          ),
          crossFadeState: _privacyExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _privacySubTile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = isDestructive ? AppConstants.errorColor : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(
            left: 72, right: 16, top: 10, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDestructive ? AppConstants.errorColor : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Regular tile ──────────────────────────────────────────────────────────

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            _iconBox(icon, iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18,
                color: Theme.of(context).colorScheme.outlineVariant),
          ],
        ),
      ),
    );
  }

  // ── Toggle tile ───────────────────────────────────────────────────────────

  Widget _toggleTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.82,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppConstants.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Logout row ────────────────────────────────────────────────────────────

  Widget _buildLogout() {
    return InkWell(
      onTap: _confirmLogout,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: MediaQuery.of(context).padding.bottom + 14,
        ),
        child: Row(
          children: [
            _iconBox(
              Icons.logout_rounded,
              AppConstants.errorColor,
            ),
            const SizedBox(width: 14),
            const Text(
              'Logout',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppConstants.errorColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Divider(height: 1),
      );
}
