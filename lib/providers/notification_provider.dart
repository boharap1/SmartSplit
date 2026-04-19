import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationProvider extends ChangeNotifier {
  static const _kEnabled = 'notifications_enabled';
  static final _db = FirebaseFirestore.instance;

  List<NotificationModel> _items = [];
  bool _enabled = true;
  String? _userId;
  StreamSubscription<QuerySnapshot>? _sub;
  bool _initialLoadDone = false;

  List<NotificationModel> get notifications => List.unmodifiable(_items);
  bool get enabled => _enabled;
  int get unreadCount => _items.where((n) => !n.isRead).length;
  bool get hasUnread => _items.any((n) => !n.isRead);

  // ── Initialise when user authenticates ────────────────────────────────────

  Future<void> initialize(String userId) async {
    if (_userId == userId) return;
    cleanup(); // clear any previous user's data
    _userId = userId;

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? true;
    notifyListeners();

    await NotificationService.instance.init(userId: userId, enabled: _enabled);
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

      // Show heads-up local notification only for newly arriving docs.
      if (_enabled) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final n = NotificationModel.fromFirestore(change.doc);
            if (!n.isRead) {
              NotificationService.instance.showLocal(
                title: n.title,
                body: n.body,
                payload: n.groupId,
              );
            }
          }
        }
      }
    });
  }

  // ── Toggle on / off ───────────────────────────────────────────────────────

  Future<void> setEnabled({required bool value}) async {
    if (_userId == null || _enabled == value) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);

    try {
      await _db
          .collection('users')
          .doc(_userId)
          .update({'notificationsEnabled': value});
    } catch (_) {}

    if (!value) {
      await NotificationService.instance.deleteToken(_userId!);
    } else {
      await NotificationService.instance.reRegisterToken(_userId!);
    }
    notifyListeners();
  }

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
