import 'dart:async';
import 'package:flutter/material.dart';
import '../models/group_model.dart';
import '../services/group_service.dart';

/// Enum representing the current state of group operations.
/// 
/// Why use enum instead of multiple booleans?
/// - isLoading, hasError, isSuccess = 3 booleans = 8 combinations
/// - Many combinations are invalid (e.g., loading AND error)
/// - Enum ensures only valid states
/// - Easier to reason about in UI code
enum GroupStatus {
  initial,    // App just started, no data yet
  loading,    // Fetching/creating/updating
  loaded,     // Data successfully loaded
  error,      // Something went wrong
}

/// GroupProvider manages all group-related state.
/// 
/// Architecture: Provider Pattern with ChangeNotifier
/// 
/// Why ChangeNotifier?
/// - Built into Flutter (no extra dependencies)
/// - Simple: just call notifyListeners() when state changes
/// - Works perfectly with Consumer widget
/// - Sufficient for SmartSplit's complexity
/// 
/// Alternative considered: Riverpod
/// - More powerful, better for large apps
/// - Steeper learning curve
/// - Overkill for our needs
class GroupProvider extends ChangeNotifier {
  final GroupService _groupService = GroupService();

  // ============================================================
  // STATE VARIABLES
  // ============================================================

  /// Current status of group operations
  GroupStatus _status = GroupStatus.initial;
  
  /// List of all groups the user is a member of
  List<GroupModel> _groups = [];
  
  /// Currently selected group (for details screen)
  GroupModel? _selectedGroup;
  
  /// Error message if something went wrong
  String? _errorMessage;
  
  /// Subscription to the real-time groups stream
  /// 
  /// Why store this?
  /// - Need to cancel when user logs out
  /// - Prevents memory leaks
  /// - Can restart if needed
  StreamSubscription<List<GroupModel>>? _groupsSubscription;
  
  /// Subscription to selected group stream
  StreamSubscription<GroupModel?>? _selectedGroupSubscription;

  // ============================================================
  // GETTERS
  // ============================================================
  
  /// Why getters instead of public variables?
  /// - Encapsulation: external code can read but not modify
  /// - Can add logic later without changing interface
  /// - Consistent pattern with Flutter framework
  
  GroupStatus get status => _status;
  List<GroupModel> get groups => _groups;
  GroupModel? get selectedGroup => _selectedGroup;
  String? get errorMessage => _errorMessage;
  
  /// Convenience getters for common checks
  bool get isLoading => _status == GroupStatus.loading;
  bool get hasGroups => _groups.isNotEmpty;
  int get groupCount => _groups.length;

  // ============================================================
  // STREAM MANAGEMENT
  // ============================================================

  /// Starts listening to user's groups in real-time.
  /// 
  /// When to call:
  /// - After user logs in
  /// - After AuthProvider confirms authentication
  /// 
  /// What happens:
  /// 1. Cancel any existing subscription (prevents duplicates)
  /// 2. Start listening to Firestore stream
  /// 3. Update local state whenever data changes
  /// 4. UI automatically rebuilds via notifyListeners()
  void startListeningToGroups(String userId) {
    // Cancel existing subscription if any
    _groupsSubscription?.cancel();
    
    _status = GroupStatus.loading;
    notifyListeners();

    _groupsSubscription = _groupService.getUserGroups(userId).listen(
      (groups) {
        _groups = groups;
        _status = GroupStatus.loaded;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        _status = GroupStatus.error;
        _errorMessage = 'Failed to load groups.';
        notifyListeners();
      },
    );
  }

  /// Stops listening to groups stream.
  /// 
  /// When to call:
  /// - When user logs out
  /// - When disposing the provider
  /// 
  /// Why important:
  /// - Prevents memory leaks
  /// - Stops unnecessary Firestore reads (saves cost!)
  /// - Clean state for next user
  void stopListeningToGroups() {
    _groupsSubscription?.cancel();
    _groupsSubscription = null;
    _groups = [];
    _status = GroupStatus.initial;
    notifyListeners();
  }

  /// Starts listening to a specific group for details screen.
  /// 
  /// Why separate stream?
  /// - Group details need real-time updates
  /// - When member joins, details update immediately
  /// - Independent of the groups list stream
  void selectGroup(String groupId) {
    // Cancel previous selection if any
    _selectedGroupSubscription?.cancel();
    
    _selectedGroupSubscription = _groupService.getGroupStream(groupId).listen(
      (group) {
        _selectedGroup = group;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'Failed to load group details.';
        notifyListeners();
      },
    );
  }

  /// Clears the selected group.
  /// 
  /// When to call:
  /// - When leaving group details screen
  /// - Frees up resources
  void clearSelectedGroup() {
    _selectedGroupSubscription?.cancel();
    _selectedGroupSubscription = null;
    _selectedGroup = null;
    notifyListeners();
  }

  // ============================================================
  // CREATE OPERATIONS
  // ============================================================

  /// Creates a new group.
  /// 
  /// Flow:
  /// 1. Set loading state
  /// 2. Call service to create in Firestore
  /// 3. If success: Stream will automatically update _groups
  /// 4. If error: Set error message
  /// 5. Return result for UI to show feedback
  /// 
  /// Why return the created group?
  /// - UI might want to navigate to the new group
  /// - Can show the group code immediately
  Future<({GroupModel? group, String? error})> createGroup({
    required String groupName,
    String? description,
    required String createdBy,
  }) async {
    _status = GroupStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _groupService.createGroup(
      groupName: groupName,
      description: description,
      createdBy: createdBy,
    );

    if (result.group != null) {
      // Success! Stream will auto-update the list
      _status = GroupStatus.loaded;
      _errorMessage = null;
    } else {
      // Error occurred
      _status = GroupStatus.error;
      _errorMessage = result.error;
    }
    
    notifyListeners();
    return result;
  }

  // ============================================================
  // JOIN OPERATIONS
  // ============================================================

  /// Joins a group using the 6-digit code.
  /// 
  /// Similar flow to createGroup:
  /// - Service handles the Firestore operation
  /// - Stream auto-updates the groups list
  /// - Return result for UI feedback
  Future<({GroupModel? group, String? error})> joinGroup({
    required String code,
    required String userId,
  }) async {
    _status = GroupStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _groupService.joinGroupByCode(
      code: code,
      userId: userId,
    );

    if (result.group != null) {
      _status = GroupStatus.loaded;
      _errorMessage = null;
    } else {
      _status = GroupStatus.error;
      _errorMessage = result.error;
    }

    notifyListeners();
    return result;
  }

  // ============================================================
  // UPDATE OPERATIONS
  // ============================================================

  /// Updates group details (name, description).
  Future<bool> updateGroup({
    required String groupId,
    required String requestingUserId,
    String? groupName,
    String? description,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final result = await _groupService.updateGroup(
      groupId: groupId,
      requestingUserId: requestingUserId,
      groupName: groupName,
      description: description,
    );

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }
    // If success, stream will auto-update

    return result.success;
  }

  // ============================================================
  // DELETE / LEAVE OPERATIONS
  // ============================================================

  /// User leaves a group.
  Future<bool> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final result = await _groupService.leaveGroup(
      groupId: groupId,
      userId: userId,
    );

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }
    // If success, stream will auto-update (group removed from list)

    return result.success;
  }

  /// Deletes a group (owner only).
  Future<bool> deleteGroup({
    required String groupId,
    required String userId,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final result = await _groupService.deleteGroup(
      groupId: groupId,
      userId: userId,
    );

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }
    // If success, stream will auto-update

    return result.success;
  }

  // ============================================================
  // MEMBER OPERATIONS
  // ============================================================

  /// Removes a member from group (owner only).
  Future<bool> removeMember({
    required String groupId,
    required String memberId,
    required String requestingUserId,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final result = await _groupService.removeMember(
      groupId: groupId,
      memberId: memberId,
      requestingUserId: requestingUserId,
    );

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }

    return result.success;
  }

  // ============================================================
  // INVITE CODE OPERATIONS
  // ============================================================

  Future<({String? code, String? error})> generateInviteCode({
    required String groupId,
    required String userId,
  }) async {
    final result = await _groupService.generateInviteCode(
      groupId: groupId,
      userId: userId,
    );
    if (result.code == null) {
      _errorMessage = result.error;
      notifyListeners();
    }
    return result;
  }

  // ============================================================
  // ADMIN OPERATIONS
  // ============================================================

  Future<bool> assignAdmin({
    required String groupId,
    required String targetUserId,
    required String requestingUserId,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final result = await _groupService.assignAdmin(
      groupId: groupId,
      targetUserId: targetUserId,
      requestingUserId: requestingUserId,
    );

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }
    return result.success;
  }

  Future<bool> removeAdmin({
    required String groupId,
    required String targetUserId,
    required String requestingUserId,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final result = await _groupService.removeAdmin(
      groupId: groupId,
      targetUserId: targetUserId,
      requestingUserId: requestingUserId,
    );

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }
    return result.success;
  }

  // ============================================================
  // UTILITY METHODS
  // ============================================================

  /// Finds a group by ID from the local list.
  /// 
  /// Why this method?
  /// - Quick lookup without Firestore call
  /// - Useful when navigating from list to details
  /// - Returns null if not found (user left group?)
  GroupModel? getGroupById(String groupId) {
    final matches = _groups.where((g) => g.groupId == groupId);
    return matches.isEmpty ? null : matches.first;
  }

  /// Clears any error message.
  /// 
  /// When to call:
  /// - When user dismisses error dialog
  /// - Before starting new operation
  void clearError() {
    _errorMessage = null;
    if (_status == GroupStatus.error) {
      _status = _groups.isEmpty ? GroupStatus.initial : GroupStatus.loaded;
    }
    notifyListeners();
  }

  /// Clean up when provider is disposed.
  /// 
  /// Called automatically when:
  /// - App is closed
  /// - Provider is removed from widget tree
  /// 
  /// Why important:
  /// - Cancels all stream subscriptions
  /// - Prevents memory leaks
  /// - Stops Firestore listeners (saves cost!)
  @override
  void dispose() {
    _groupsSubscription?.cancel();
    _selectedGroupSubscription?.cancel();
    super.dispose();
  }
}
