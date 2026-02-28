import 'package:cloud_firestore/cloud_firestore.dart';

/// GroupModel represents a expense-sharing group in SmartSplit.
/// 
/// Design Decisions:
/// 1. Members stored as List<String> (userIds) not full UserModel objects
///    - Reduces data duplication
///    - Avoids sync issues when user updates their profile
///    - Firestore charges by document size, so smaller = cheaper
/// 
/// 2. groupCode is 6 digits (000000-999999)
///    - Easy to share verbally or via text
///    - 1 million combinations sufficient for our scale
///    - Future: Add expiry time for security
/// 
/// 3. createdBy stores the owner's userId
///    - Used for admin permissions (delete group, remove members)
///    - Future: Could add multiple admins with a List<String> adminIds
class GroupModel {
  final String groupId;
  final String groupName;
  final String? description;
  final String groupCode;
  final String createdBy;
  final List<String> members;
  final DateTime createdAt;

  GroupModel({
    required this.groupId,
    required this.groupName,
    this.description,
    required this.groupCode,
    required this.createdBy,
    required this.members,
    required this.createdAt,
  });

  /// Factory constructor to create GroupModel from Firestore document.
  /// 
  /// Why factory constructor?
  /// - Allows complex logic before creating the object
  /// - Can return cached instances if needed (future optimization)
  /// - Clearly separates "parsing" logic from the model itself
  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return GroupModel(
      groupId: doc.id,  // Document ID becomes groupId
      groupName: data['groupName'] ?? '',
      description: data['description'],
      groupCode: data['groupCode'] ?? '',
      createdBy: data['createdBy'] ?? '',
      // Why List<String>.from()? 
      // Firestore returns List<dynamic>, we need List<String>
      // .from() creates a new typed list from the dynamic list
      members: List<String>.from(data['members'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  /// Converts GroupModel to Map for saving to Firestore.
  /// 
  /// Note: groupId is NOT included because:
  /// - Firestore uses the document ID as the identifier
  /// - We set it when creating: collection.doc(groupId).set(toFirestore())
  /// - Including it would be redundant data
  Map<String, dynamic> toFirestore() {
    return {
      'groupName': groupName,
      'description': description,
      'groupCode': groupCode,
      'createdBy': createdBy,
      'members': members,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Creates a copy of GroupModel with some fields updated.
  /// 
  /// Why copyWith pattern?
  /// - Models should be immutable (fields are final)
  /// - Immutability prevents bugs from unexpected mutations
  /// - copyWith creates NEW object with changes, original unchanged
  /// - Essential for proper state management with Provider
  /// 
  /// Example usage:
  /// final updatedGroup = group.copyWith(groupName: 'New Name');
  GroupModel copyWith({
    String? groupName,
    String? description,
    List<String>? members,
  }) {
    return GroupModel(
      groupId: groupId,           // Can't change ID
      groupName: groupName ?? this.groupName,
      description: description ?? this.description,
      groupCode: groupCode,       // Can't change code
      createdBy: createdBy,       // Can't change owner
      members: members ?? this.members,
      createdAt: createdAt,       // Can't change creation time
    );
  }

  /// Check if a user is the owner/admin of this group.
  /// 
  /// Future upgrade: Support multiple admins
  /// bool isAdmin(String userId) => adminIds.contains(userId);
  bool isOwner(String userId) => createdBy == userId;

  /// Check if a user is a member of this group.
  bool isMember(String userId) => members.contains(userId);

  /// Get member count for display.
  int get memberCount => members.length;

  @override
  String toString() {
    return 'GroupModel(groupId: $groupId, groupName: $groupName, members: ${members.length})';
  }
}