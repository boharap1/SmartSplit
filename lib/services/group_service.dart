import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';

class GroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _groupsCollection =>
      _firestore.collection('groups');

  Future<void> _logEvent(
    String groupId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _groupsCollection
          .doc(groupId)
          .collection('events')
          .add({...data, 'createdAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  Future<({GroupModel? group, String? error})> createGroup({
    required String groupName,
    String? description,
    required String createdBy,
    String? creatorName,
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
        adminIds: [createdBy],
        createdAt: DateTime.now(),
      );

      await _groupsCollection.doc(groupId).set(group.toFirestore());
      await _logEvent(groupId, {
        'type': 'group_created',
        'userId': createdBy,
        'userName': creatorName ?? 'Unknown',
      });
      return (group: group, error: null);
    } catch (e) {
      return (group: null, error: 'Failed to create group. Please try again.');
    }
  }

  Future<String> _generateUniqueCode() async {
    final Random random = Random();
    String code = '';
    bool isUnique = false;
    int attempts = 0;
    const int maxAttempts = 10;

    do {
      code = random.nextInt(1000000).toString().padLeft(6, '0');
      final QuerySnapshot existing = await _groupsCollection
          .where('groupCode', isEqualTo: code)
          .limit(1)
          .get();
      isUnique = existing.docs.isEmpty;
      attempts++;
    } while (!isUnique && attempts < maxAttempts);

    if (!isUnique) throw Exception('Failed to generate unique code');
    return code;
  }

  // Generates a temporary 6-digit invite code valid for 10 minutes.
  Future<({String? code, String? error})> generateInviteCode({
    required String groupId,
    required String userId,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) return (code: null, error: 'Group not found.');

      final group = GroupModel.fromFirestore(doc);
      if (!group.isAdmin(userId)) {
        return (code: null, error: 'Only group admins can generate invite codes.');
      }

      final code = await _generateUniqueInviteCode();
      final expiry = DateTime.now().add(const Duration(minutes: 10));

      await _groupsCollection.doc(groupId).update({
        'activeInviteCode': code,
        'activeInviteExpiry': Timestamp.fromDate(expiry),
      });

      return (code: code, error: null);
    } catch (e) {
      return (code: null, error: 'Failed to generate invite code. Please try again.');
    }
  }

  Future<String> _generateUniqueInviteCode() async {
    final Random random = Random();
    String code = '';
    int attempts = 0;
    const int maxAttempts = 10;

    do {
      code = random.nextInt(1000000).toString().padLeft(6, '0');
      final QuerySnapshot existing = await _groupsCollection
          .where('activeInviteCode', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) break;
      // Reuse if the existing code is already expired
      final existingGroup = GroupModel.fromFirestore(existing.docs.first);
      if (!existingGroup.hasActiveInvite) break;
      attempts++;
    } while (attempts < maxAttempts);

    return code;
  }

  Future<({GroupModel? group, String? error})> joinGroupByCode({
    required String code,
    required String userId,
    // Optional – used to build the member-joined notification.
    String? joiningUserName,
  }) async {
    try {
      final QuerySnapshot querySnapshot = await _groupsCollection
          .where('activeInviteCode', isEqualTo: code.trim())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return (group: null, error: 'Invalid or expired invite code.');
      }

      final DocumentSnapshot doc = querySnapshot.docs.first;
      final GroupModel group = GroupModel.fromFirestore(doc);

      if (!group.hasActiveInvite) {
        return (
          group: null,
          error: 'This invite code has expired. Ask an admin to generate a new one.',
        );
      }

      if (group.members.contains(userId)) {
        return (group: null, error: 'You are already a member of this group.');
      }

      await _groupsCollection.doc(group.groupId).update({
        'members': FieldValue.arrayUnion([userId]),
      });
      await _logEvent(group.groupId, {
        'type': 'member_joined',
        'userId': userId,
        'userName': joiningUserName ?? 'Someone',
      });

      // Notify existing members that someone joined.
      final joiner = joiningUserName ?? 'Someone';
      NotificationService.dispatch(
        toUserIds: group.members,
        excludeUserId: userId,
        type: NotificationType.memberJoined,
        title: 'New member in ${group.groupName}',
        body: '$joiner joined the group',
        groupId: group.groupId,
        fromUserName: joiningUserName,
      );

      final updatedDoc = await _groupsCollection.doc(group.groupId).get();
      return (group: GroupModel.fromFirestore(updatedDoc), error: null);
    } catch (e) {
      return (group: null, error: 'Failed to join group. Please try again.');
    }
  }

  Stream<List<GroupModel>> getUserGroups(String userId) {
    return _groupsCollection
        .where('members', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => GroupModel.fromFirestore(doc)).toList());
  }

  Future<GroupModel?> getGroupById(String groupId) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      return doc.exists ? GroupModel.fromFirestore(doc) : null;
    } catch (e) {
      return null;
    }
  }

  Stream<GroupModel?> getGroupStream(String groupId) {
    return _groupsCollection.doc(groupId).snapshots().map((doc) {
      return doc.exists ? GroupModel.fromFirestore(doc) : null;
    });
  }

  Future<({bool success, String? error})> updateGroup({
    required String groupId,
    required String requestingUserId,
    String? groupName,
    String? description,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) return (success: false, error: 'Group not found.');

      final group = GroupModel.fromFirestore(doc);
      if (!group.isAdmin(requestingUserId)) {
        return (success: false, error: 'Only group admins can edit the group.');
      }

      final Map<String, dynamic> updates = {};
      if (groupName != null) updates['groupName'] = groupName.trim();
      if (description != null) updates['description'] = description.trim();
      if (updates.isEmpty) return (success: false, error: 'No changes to update.');

      await _groupsCollection.doc(groupId).update(updates);
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to update group. Please try again.');
    }
  }

  Future<({bool success, String? error})> assignAdmin({
    required String groupId,
    required String targetUserId,
    required String requestingUserId,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) return (success: false, error: 'Group not found.');

      final group = GroupModel.fromFirestore(doc);
      if (!group.isOwner(requestingUserId)) {
        return (success: false, error: 'Only the group owner can assign admins.');
      }
      if (!group.members.contains(targetUserId)) {
        return (success: false, error: 'User is not a member of this group.');
      }
      if (group.adminIds.contains(targetUserId)) {
        return (success: false, error: 'User is already an admin.');
      }

      await _groupsCollection.doc(groupId).update({
        'adminIds': FieldValue.arrayUnion([targetUserId]),
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to assign admin role. Please try again.');
    }
  }

  Future<({bool success, String? error})> removeAdmin({
    required String groupId,
    required String targetUserId,
    required String requestingUserId,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) return (success: false, error: 'Group not found.');

      final group = GroupModel.fromFirestore(doc);
      if (!group.isOwner(requestingUserId)) {
        return (success: false, error: 'Only the group owner can remove admins.');
      }
      if (group.isOwner(targetUserId)) {
        return (success: false, error: 'Cannot remove admin role from the group owner.');
      }

      await _groupsCollection.doc(groupId).update({
        'adminIds': FieldValue.arrayRemove([targetUserId]),
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to remove admin role. Please try again.');
    }
  }

  Future<({bool success, String? error})> leaveGroup({
    required String groupId,
    required String userId,
    String? leavingUserName,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) return (success: false, error: 'Group not found.');

      final group = GroupModel.fromFirestore(doc);
      if (group.createdBy == userId) {
        return (
          success: false,
          error: 'As the group owner, you cannot leave. Delete the group instead.',
        );
      }

      await _groupsCollection.doc(groupId).update({
        'members': FieldValue.arrayRemove([userId]),
        'adminIds': FieldValue.arrayRemove([userId]),
      });
      await _logEvent(groupId, {
        'type': 'member_left',
        'userId': userId,
        'userName': leavingUserName ?? 'Someone',
      });

      final remaining = group.members.where((id) => id != userId).toList();
      if (remaining.isNotEmpty) {
        final name = leavingUserName ?? 'A member';
        NotificationService.dispatch(
          toUserIds: remaining,
          type: NotificationType.memberLeft,
          title: 'Member left ${group.groupName}',
          body: '$name has left the group',
          groupId: group.groupId,
          fromUserName: leavingUserName,
        );
      }

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to leave group. Please try again.');
    }
  }

  Future<({bool success, String? error})> deleteGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) return (success: false, error: 'Group not found.');

      final group = GroupModel.fromFirestore(doc);
      if (group.createdBy != userId) {
        return (success: false, error: 'Only the group owner can delete this group.');
      }

      await _groupsCollection.doc(groupId).delete();
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to delete group. Please try again.');
    }
  }

  Future<({bool success, String? error})> removeMember({
    required String groupId,
    required String memberId,
    required String requestingUserId,
    String? removedMemberName,
  }) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (!doc.exists) return (success: false, error: 'Group not found.');

      final group = GroupModel.fromFirestore(doc);
      if (!group.isAdmin(requestingUserId)) {
        return (success: false, error: 'Only group admins can remove members.');
      }
      if (memberId == group.createdBy) {
        return (success: false, error: 'Cannot remove the group owner.');
      }
      // Non-owner admins cannot remove other admins
      if (group.adminIds.contains(memberId) && !group.isOwner(requestingUserId)) {
        return (success: false, error: 'Only the owner can remove other admins.');
      }

      await _groupsCollection.doc(groupId).update({
        'members': FieldValue.arrayRemove([memberId]),
        'adminIds': FieldValue.arrayRemove([memberId]),
      });

      // Notify the removed member directly.
      NotificationService.dispatch(
        toUserIds: [memberId],
        type: NotificationType.memberLeft,
        title: 'Removed from ${group.groupName}',
        body: 'You have been removed from this group',
        groupId: group.groupId,
      );

      // Notify remaining members (excluding the admin who performed the action).
      final remaining = group.members
          .where((id) => id != memberId && id != requestingUserId)
          .toList();
      if (remaining.isNotEmpty) {
        final name = removedMemberName ?? 'A member';
        NotificationService.dispatch(
          toUserIds: remaining,
          excludeUserId: requestingUserId,
          type: NotificationType.memberLeft,
          title: 'Member removed from ${group.groupName}',
          body: '$name has been removed from the group',
          groupId: group.groupId,
        );
      }

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to remove member. Please try again.');
    }
  }
}
