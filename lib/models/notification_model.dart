import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  expenseAdded,
  expenseDeleted,
  paymentReceived,
  paymentReminder, // always critical — bypasses user preferences
  memberJoined,
  memberLeft,
  reminder,
  system,
}

/// Controls whether a notification bypasses user preference settings.
///
/// Stored as a string field `priority` on every Firestore notification doc.
/// [critical] notifications fire on all channels regardless of toggles.
enum NotificationPriority { normal, critical }

class NotificationModel {
  final String id;
  final NotificationType type;
  final NotificationPriority priority;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final String? groupId;
  final String? relatedId;
  final String? fromUserName;

  const NotificationModel({
    required this.id,
    required this.type,
    this.priority = NotificationPriority.normal,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.groupId,
    this.relatedId,
    this.fromUserName,
  });

  bool get isCritical => priority == NotificationPriority.critical;

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id:           doc.id,
      type:         _typeFromString(data['type'] as String? ?? 'system'),
      priority:     _priorityFromString(data['priority'] as String? ?? 'normal'),
      title:        data['title']       as String?  ?? '',
      body:         data['body']        as String?  ?? '',
      isRead:       data['isRead']      as bool?    ?? false,
      createdAt:    (data['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
      groupId:      data['groupId']     as String?,
      relatedId:    data['relatedId']   as String?,
      fromUserName: data['fromUserName'] as String?,
    );
  }

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id:           id,
        type:         type,
        priority:     priority,
        title:        title,
        body:         body,
        isRead:       isRead ?? this.isRead,
        createdAt:    createdAt,
        groupId:      groupId,
        relatedId:    relatedId,
        fromUserName: fromUserName,
      );

  static NotificationType _typeFromString(String s) =>
      NotificationType.values.firstWhere(
        (t) => t.name == s,
        orElse: () => NotificationType.system,
      );

  static NotificationPriority _priorityFromString(String s) =>
      NotificationPriority.values.firstWhere(
        (p) => p.name == s,
        orElse: () => NotificationPriority.normal,
      );
}
