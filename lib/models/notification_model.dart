import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  expenseAdded,
  expenseDeleted,
  paymentReceived,
  memberJoined,
  memberLeft,
  reminder,
  system,
}

class NotificationModel {
  final String id;
  final NotificationType type;
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
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.groupId,
    this.relatedId,
    this.fromUserName,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      type: _typeFromString(data['type'] as String? ?? 'system'),
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      isRead: data['isRead'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      groupId: data['groupId'] as String?,
      relatedId: data['relatedId'] as String?,
      fromUserName: data['fromUserName'] as String?,
    );
  }

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id,
        type: type,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        groupId: groupId,
        relatedId: relatedId,
        fromUserName: fromUserName,
      );

  static NotificationType _typeFromString(String s) => NotificationType.values
      .firstWhere((t) => t.name == s, orElse: () => NotificationType.system);
}
