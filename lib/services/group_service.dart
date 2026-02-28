import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group_model.dart';

class GroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _groupsCollection =>
      _firestore.collection('groups');

  // Create a new group
  Future<({GroupModel? group, String? error})> createGroup({
    required String groupName,
    String? description,
    required String createdBy,
  }) async {
    try {
      final String groupCode = await _generateUniqueCode();
      final String groupId = _groupsCollection.doc().id;

      final GroupModel group = GroupModel(
        groupId: groupId,
        groupName: groupName.trim(),
        description: description?.trim(),
        groupCode: groupCode,
        createdBy: createdBy,
        members: [createdBy],
        createdAt: DateTime.now(),
      );

      await _groupsCollection.doc(groupId).set(group.toFirestore());

      return (group: group, error: null);
    } catch (e) {
      // Show actual error for debugging
      return (group: null, error: 'Error: ${e.toString()}');
    }
  }

  // Generate unique 6-digit code
  Future<String> _generateUniqueCode() async {
    final Random random = Random();
    String code;
    bool isUnique = false;
    int attempts = 0;
    const int maxAttempts = 10;

    do {
      code = random.nextInt(1000000).toString().padLeft(6, '0');

      final QuerySnapshot existingGroups = await _groupsCollection
          .where('groupCode', isEqualTo: code)
          .limit(1)
          .get();

      isUnique = existingGroups.docs.isEmpty;
      attempts++;
    } while (!isUnique && attempts < maxAttempts);

    if (!isUnique) {
      throw Exception('Failed to generate unique code');
    }

    return code;
  }

  // Join group by code
  Future<({GroupModel? group, String? error})> joinGroupByCode({
    required String code,
    required String userId,
  }) async {
    try {
      final QuerySnapshot querySnapshot = await _groupsCollection
          .where('groupCode', isEqualTo: code.trim())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return (group: null, error: 'Invalid code. Group not found.');
      }

      final DocumentSnapshot doc = querySnapshot.docs.first;
      final GroupModel group = GroupModel.fromFirestore(doc);

      if (group.members.contains(userId)) {
        return (group: null, error: 'You are already a member of this group.');
      }

      await _groupsCollection.doc(group.groupId).update({
        'members': FieldValue.arrayUnion([userId]),
      });

      final updatedDoc = await _groupsCollection.doc(group.groupId).get();
      final updatedGroup = GroupModel.fromFirestore(updatedDoc);

      return (group: updatedGroup, error: null);
    } catch (e) {
      return (group: null, error: 'Error: ${e.toString()}');
    }
  }

  // Get user's groups (real-time stream)
  Stream<List<GroupModel>> getUserGroups(String userId) {
    return _groupsCollection
        .where('members', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GroupModel.fromFirestore(doc))
              .toList();
        });
  }

  // Get single group by ID
  Future<GroupModel?> getGroupById(String groupId) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (doc.exists) {
        return GroupModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get group stream (real-time)
  Stream<GroupModel?> getGroupStream(String groupId) {
    return _groupsCollection
        .doc(groupId)
        .snapshots()
        .map((doc) {
          if (doc.exists) {
            return GroupModel.fromFirestore(doc);
          }
          return null;
        });
  }

  // Update group
  Future<({bool success, String? error})> updateGroup({
    required String groupId,
    String? groupName,
    String? description,
  }) async {
    try {
      final Map<String, dynamic> updates = {};

      if (groupName != null) {
        updates['groupName'] = groupName.trim();
      }
      if (description != null) {
        updates['description'] = description.trim();
      }

      if (updates.isEmpty) {
        return (success: false, error: 'No changes to update.');
      }

      await _groupsCollection.doc(groupId).update(updates);
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Error: ${e.toString()}');
    }
  }

  // Leave group
  Future<({bool success, String? error})> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) {
        return (success: false, error: 'Group not found.');
      }

      final group = GroupModel.fromFirestore(doc);

      if (group.createdBy == userId) {
        return (
          success: false,
          error: 'As the group owner, you cannot leave. Delete the group instead.'
        );
      }

      await _groupsCollection.doc(groupId).update({
        'members': FieldValue.arrayRemove([userId]),
      });

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Error: ${e.toString()}');
    }
  }

  // Delete group
  Future<({bool success, String? error})> deleteGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) {
        return (success: false, error: 'Group not found.');
      }

      final group = GroupModel.fromFirestore(doc);

      if (group.createdBy != userId) {
        return (success: false, error: 'Only the group owner can delete this group.');
      }

      await _groupsCollection.doc(groupId).delete();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Error: ${e.toString()}');
    }
  }

  // Remove member
  Future<({bool success, String? error})> removeMember({
    required String groupId,
    required String memberId,
    required String requestingUserId,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) {
        return (success: false, error: 'Group not found.');
      }

      final group = GroupModel.fromFirestore(doc);

      if (group.createdBy != requestingUserId) {
        return (success: false, error: 'Only the group owner can remove members.');
      }

      if (memberId == group.createdBy) {
        return (success: false, error: 'Cannot remove the group owner.');
      }

      await _groupsCollection.doc(groupId).update({
        'members': FieldValue.arrayRemove([memberId]),
      });

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Error: ${e.toString()}');
    }
  }
}