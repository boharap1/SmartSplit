import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/notification_model.dart';
import '../../providers/notification_provider.dart';
import '../../utils/constants.dart';
import '../group/group_details_screen.dart';

class NotificationCenterScreen extends StatelessWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final notifications = provider.notifications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (provider.hasUnread)
            TextButton.icon(
              onPressed: () => provider.markAllRead(),
              icon: const Icon(Icons.done_all_rounded,
                  color: Colors.white, size: 18),
              label: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
              tooltip: 'Clear all',
              onPressed: () => _confirmClearAll(context, provider),
            ),
        ],
      ),
      body: notifications.isEmpty
          ? _buildEmpty(context)
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final n = notifications[i];
                return _NotificationTile(
                  notification: n,
                  onTap: () => _handleTap(context, n, provider),
                  onDismiss: () => provider.delete(n.id),
                );
              },
            ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 20),
            Text(
              'No notifications yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'When someone adds an expense or records\na payment you\'ll see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tap handler → mark read + navigate ────────────────────────────────────

  void _handleTap(
    BuildContext context,
    NotificationModel n,
    NotificationProvider provider,
  ) {
    provider.markRead(n.id);
    if (n.groupId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupDetailsScreen(groupId: n.groupId!),
        ),
      );
    }
  }

  // ── Clear all confirmation ─────────────────────────────────────────────────

  void _confirmClearAll(BuildContext context, NotificationProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications'),
        content: const Text(
            'This will permanently delete all notifications. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.clearAll();
            },
            style: TextButton.styleFrom(
                foregroundColor: AppConstants.errorColor),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

// ── Notification tile ──────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final cs = Theme.of(context).colorScheme;

    return Dismissible(
      key: Key(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppConstants.errorColor,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDismiss(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: n.isRead ? null : AppConstants.primaryColor.withValues(alpha: 0.05),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon bubble
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _typeColor(n.type).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _typeIcon(n.type),
                  size: 20,
                  color: _typeColor(n.type),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                              fontSize: 14,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppConstants.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      n.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _timeAgo(n.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.outlineVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  IconData _typeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.expenseAdded:
        return Icons.receipt_long_rounded;
      case NotificationType.expenseDeleted:
        return Icons.delete_outline_rounded;
      case NotificationType.paymentReceived:
        return Icons.payments_rounded;
      case NotificationType.memberJoined:
        return Icons.person_add_rounded;
      case NotificationType.memberLeft:
        return Icons.person_remove_rounded;
      case NotificationType.reminder:
        return Icons.alarm_rounded;
      case NotificationType.system:
        return Icons.info_outline_rounded;
    }
  }

  Color _typeColor(NotificationType type) {
    switch (type) {
      case NotificationType.expenseAdded:
        return AppConstants.primaryColor;
      case NotificationType.expenseDeleted:
        return AppConstants.errorColor;
      case NotificationType.paymentReceived:
        return AppConstants.successColor;
      case NotificationType.memberJoined:
        return const Color(0xFF42A5F5);
      case NotificationType.memberLeft:
        return const Color(0xFFFF7043);
      case NotificationType.reminder:
        return const Color(0xFFFFB300);
      case NotificationType.system:
        return const Color(0xFF78909C);
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final d = dt;
    return '${d.day}/${d.month}/${d.year}';
  }
}
