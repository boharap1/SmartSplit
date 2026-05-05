import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationProvider extends ChangeNotifier {
  static const _kPushEnabled = 'push_notifications_enabled';
  static const _kEmailEnabled = 'email_notifications_enabled';
  static final _db = FirebaseFirestore.instance;

  List<NotificationModel> _items = [];
  // In-app (Notification Centre) is always on — not user-controllable.
  bool _pushEnabled = true;
  bool _emailEnabled = false;
  String? _userId;
  StreamSubscription<QuerySnapshot>? _sub;
  bool _initialLoadDone = false;

  List<NotificationModel> get notifications => List.unmodifiable(_items);

  /// Whether device heads-up (local + FCM push) notifications are enabled.
  bool get pushEnabled => _pushEnabled;

  /// Whether the user wants email notifications (stored for backend use).
  bool get emailEnabled => _emailEnabled;

  // Legacy alias — some widgets still read `.enabled` for the push toggle.
  bool get enabled => _pushEnabled;

  int get unreadCount => _items.where((n) => !n.isRead).length;
  bool get hasUnread => _items.any((n) => !n.isRead);

  // ── Initialise when user authenticates ────────────────────────────────────

  Future<void> initialize(String userId) async {
    if (_userId == userId) return;
    cleanup(); // clear any previous user's data
    _userId = userId;

    final prefs = await SharedPreferences.getInstance();
    _pushEnabled = prefs.getBool(_kPushEnabled) ?? true;
    _emailEnabled = prefs.getBool(_kEmailEnabled) ?? false;
    notifyListeners();

    await NotificationService.instance.init(userId: userId, enabled: _pushEnabled);
    _startStream(userId);
  }

  // ── Firestore real-time stream ─────────────────────────────────────────────

  void _startStream(String userId) {
    _sub?.cancel();
    _initialLoadDone = false;

    _sub = _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      _items = snapshot.docs
          .map((d) => NotificationModel.fromFirestore(d))
          .toList();
      notifyListeners();

      // Skip local notification on the initial batch download.
      if (!_initialLoadDone) {
        _initialLoadDone = true;
        return;
      }

      // Show heads-up local notification for newly arriving docs.
      // Critical notifications fire regardless of the push preference.
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final n = NotificationModel.fromFirestore(change.doc);
          if (!n.isRead && (_pushEnabled || n.isCritical)) {
            NotificationService.instance.showLocal(
              title: n.title,
              body: n.body,
              payload: n.groupId,
            );
          }
        }
      }
    });
  }

  // ── Toggle on / off ───────────────────────────────────────────────────────

  Future<void> setPushEnabled({required bool value}) async {
    if (_userId == null || _pushEnabled == value) return;
    _pushEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPushEnabled, value);

    try {
      await _db
          .collection('users')
          .doc(_userId)
          .update({'pushNotificationsEnabled': value});
    } catch (_) {}

    if (!value) {
      await NotificationService.instance.deleteToken(_userId!);
    } else {
      await NotificationService.instance.reRegisterToken(_userId!);
    }
    notifyListeners();
  }

  Future<void> setEmailEnabled({required bool value}) async {
    if (_emailEnabled == value) return;
    _emailEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEmailEnabled, value);

    try {
      await _db
          .collection('users')
          .doc(_userId)
          .update({'emailNotificationsEnabled': value});
    } catch (_) {}

    notifyListeners();
  }

  // Legacy alias kept for app_menu.dart compatibility.
  Future<void> setEnabled({required bool value}) => setPushEnabled(value: value);

  // ── Mark read ─────────────────────────────────────────────────────────────

  Future<void> markRead(String notificationId) async {
    if (_userId == null) return;
    try {
      await _db
          .collection('users')
          .doc(_userId)
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    if (_userId == null) return;
    final unread = _items.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;
    try {
      final batch = _db.batch();
      for (final n in unread) {
        batch.update(
          _db
              .collection('users')
              .doc(_userId)
              .collection('notifications')
              .doc(n.id),
          {'isRead': true},
        );
      }
      await batch.commit();
    } catch (_) {}
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> delete(String notificationId) async {
    if (_userId == null) return;
    try {
      await _db
          .collection('users')
          .doc(_userId)
          .collection('notifications')
          .doc(notificationId)
          .delete();
    } catch (_) {}
  }

  Future<void> clearAll() async {
    if (_userId == null || _items.isEmpty) return;
    try {
      final batch = _db.batch();
      for (final n in _items) {
        batch.delete(
          _db
              .collection('users')
              .doc(_userId)
              .collection('notifications')
              .doc(n.id),
        );
      }
      await batch.commit();
    } catch (_) {}
  }

  // ── Clean up when user signs out ──────────────────────────────────────────

  void cleanup() {
    _sub?.cancel();
    _sub = null;
    _items = [];
    _userId = null;
    _initialLoadDone = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
