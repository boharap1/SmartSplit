import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../utils/constants.dart';

class NotificationPreferencesScreen extends StatelessWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Preferences'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 4),
          _SectionHeader('Channels'),
          _PreferenceCard(children: [
            // In-app — always on, read-only
            _PrefTile(
              icon: Icons.notifications_active_outlined,
              iconColor: AppConstants.primaryColor,
              title: 'In-App Notifications',
              subtitle: 'Activity feed & Notification Centre — always on',
              value: true,
              onChanged: null,
            ),
            const Divider(height: 1, indent: 72),
            // Push
            _PrefTile(
              icon: Icons.phone_android_outlined,
              iconColor: const Color(0xFF42A5F5),
              title: 'Push Notifications',
              subtitle: 'Heads-up alerts on this device',
              value: provider.pushEnabled,
              onChanged: (v) => provider.setPushEnabled(value: v),
            ),
            const Divider(height: 1, indent: 72),
            // Email
            _PrefTile(
              icon: Icons.mail_outline_rounded,
              iconColor: const Color(0xFF26A69A),
              title: 'Email Notifications',
              subtitle: 'Summaries and alerts sent to your email',
              value: provider.emailEnabled,
              onChanged: (v) => provider.setEmailEnabled(value: v),
            ),
          ]),
          const SizedBox(height: 20),
          _SectionHeader('Notify me about'),
          _PreferenceCard(children: [
            _InfoTile(
              icon: Icons.receipt_long_outlined,
              iconColor: AppConstants.primaryColor,
              title: 'New Expenses',
              subtitle: 'When someone adds an expense to your group',
            ),
            const Divider(height: 1, indent: 72),
            _InfoTile(
              icon: Icons.payments_outlined,
              iconColor: AppConstants.successColor,
              title: 'Payments Received',
              subtitle: 'When a group member settles up with you',
            ),
            const Divider(height: 1, indent: 72),
            _InfoTile(
              icon: Icons.group_add_outlined,
              iconColor: const Color(0xFF42A5F5),
              title: 'Group Activity',
              subtitle: 'When someone joins or leaves your groups',
            ),
          ]),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'In-app notifications are always delivered to your Notification Centre '
              'regardless of your push or email preferences.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.5),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey[500],
        letterSpacing: 1.2,
      ),
    ),
  );
}

// ── Card wrapper ───────────────────────────────────────────────────────────────

class _PreferenceCard extends StatelessWidget {
  final List<Widget> children;
  const _PreferenceCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
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
    child: Column(children: children),
  );
}

// ── Toggleable preference row ──────────────────────────────────────────────────

class _PrefTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool)? onChanged;

  const _PrefTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (disabled ? Colors.grey : iconColor).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: disabled ? Colors.grey : iconColor, size: 20),
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
                    color: disabled ? Colors.grey : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppConstants.primaryColor,
            activeTrackColor: AppConstants.primaryColor.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

// ── Read-only info row (no toggle) ─────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
        ),
        Icon(Icons.check_circle_rounded,
            size: 20,
            color: AppConstants.primaryColor.withValues(alpha: 0.6)),
      ],
    ),
  );
}
