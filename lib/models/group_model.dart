import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String groupId;
  final String groupName;
  final String? description;
  final String groupCode;
  final String createdBy;
  final List<String> members;
  final List<String> adminIds;
  final String? activeInviteCode;
  final DateTime? activeInviteExpiry;
  final DateTime createdAt;

  GroupModel({
    required this.groupId,
    required this.groupName,
    this.description,
    required this.groupCode,
    required this.createdBy,
    required this.members,
    List<String>? adminIds,
    this.activeInviteCode,
    this.activeInviteExpiry,
    required this.createdAt,
  }) : adminIds = adminIds ?? [createdBy];

  bool get hasActiveInvite =>
      activeInviteCode != null &&
      activeInviteExpiry != null &&
      activeInviteExpiry!.isAfter(DateTime.now());

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final createdBy = data['createdBy'] ?? '';

    return GroupModel(
      groupId: doc.id,
      groupName: data['groupName'] ?? '',
      description: data['description'],
      groupCode: data['groupCode'] ?? '',
      createdBy: createdBy,
      members: List<String>.from(data['members'] ?? []),
      adminIds: data['adminIds'] != null
          ? List<String>.from(data['adminIds'])
          : [createdBy],
      activeInviteCode: data['activeInviteCode'],
      activeInviteExpiry: data['activeInviteExpiry'] != null
          ? (data['activeInviteExpiry'] as Timestamp).toDate()
          : null,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'groupName': groupName,
      'description': description,
      'groupCode': groupCode,
      'createdBy': createdBy,
      'members': members,
      'adminIds': adminIds,
      'activeInviteCode': activeInviteCode,
      'activeInviteExpiry': activeInviteExpiry != null
          ? Timestamp.fromDate(activeInviteExpiry!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  GroupModel copyWith({
    String? groupName,
    String? description,
    List<String>? members,
    List<String>? adminIds,
  }) {
    return GroupModel(
      groupId: groupId,
      groupName: groupName ?? this.groupName,
      description: description ?? this.description,
      groupCode: groupCode,
      createdBy: createdBy,
      members: members ?? this.members,
      adminIds: adminIds ?? this.adminIds,
      activeInviteCode: activeInviteCode,
      activeInviteExpiry: activeInviteExpiry,
      createdAt: createdAt,
    );
  }

  bool isOwner(String userId) => createdBy == userId;
  bool isAdmin(String userId) => adminIds.contains(userId) || isOwner(userId);
  bool isMember(String userId) => members.contains(userId);
  int get memberCount => members.length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupModel && other.groupId == groupId;
  }

  @override
  int get hashCode => groupId.hashCode;

  @override
  String toString() =>
      'GroupModel(groupId: $groupId, groupName: $groupName, members: ${members.length})';
}
