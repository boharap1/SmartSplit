import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/notification_model.dart';

/// Top-level FCM background handler — must be outside any class.
/// Registered in main.dart via FirebaseMessaging.onBackgroundMessage().
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the plugin before this runs.
  // Heavy work (DB writes, navigation) must NOT happen here.
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'smartsplit_channel';
  static const _channelName = 'SmartSplit Notifications';
  static const _channelDesc = 'Expense and group activity notifications';

  static final _db = FirebaseFirestore.instance;
  static final _fcm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  bool _ready = false;

  // ── Initialise (call once after authentication) ───────────────────────────

  Future<void> init({required String userId, required bool enabled}) async {
    if (_ready) return;
    _ready = true;

    // Local notifications channel
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _local.initialize(initSettings);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );

    // FCM permission (required on Android 13+ / iOS)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Register / refresh device token
    if (enabled) {
      await _refreshToken(userId);
      _fcm.onTokenRefresh.listen((_) => _refreshToken(userId));
    }

    // Foreground FCM message → show heads-up local notification
    FirebaseMessaging.onMessage.listen((msg) {
      if (!enabled) return;
      final n = msg.notification;
      if (n != null) {
        showLocal(
          title: n.title ?? 'SmartSplit',
          body: n.body ?? '',
          payload: msg.data['groupId'] as String?,
        );
      }
    });
  }

  Future<void> _refreshToken(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;
      await _db.collection('users').doc(userId).update({'fcmToken': token});
    } catch (_) {}
  }

  /// Delete the FCM token (called when notifications are disabled).
  Future<void> deleteToken(String userId) async {
    try {
      await _fcm.deleteToken();
      await _db
          .collection('users')
          .doc(userId)
          .update({'fcmToken': FieldValue.delete()});
    } catch (_) {}
  }

  /// Re-register the FCM token (called when notifications are re-enabled).
  Future<void> reRegisterToken(String userId) async {
    _ready = false; // allow re-init
    await init(userId: userId, enabled: true);
    await _refreshToken(userId);
  }

  // ── Local notification display ────────────────────────────────────────────

  Future<void> showLocal({
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(''),
      ),
    );
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 % 2147483647,
      title,
      body,
      details,
      payload: payload,
    );
  }

  // ── Cross-device Firestore notification dispatch ──────────────────────────
  //
  // When a user performs an action (adds expense, records payment, joins group),
  // their client writes notification documents to each recipient's subcollection:
  //   users/{uid}/notifications/{notificationId}
  //
  // Recipients' apps pick this up via Firestore real-time listeners.
  // For background/terminated delivery, deploy the Cloud Functions in
  // functions/index.js which trigger FCM push on Firestore writes.

  static Future<void> dispatch({
    required List<String> toUserIds,
    String? excludeUserId,
    required NotificationType type,
    required String title,
    required String body,
    String? groupId,
    String? relatedId,
    String? fromUserName,
  }) async {
    final recipients =
        toUserIds.where((id) => id != excludeUserId).toList();
    if (recipients.isEmpty) return;

    try {
      final batch = _db.batch();
      for (final uid in recipients) {
        final ref = _db
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .doc();
        batch.set(ref, {
          'id': ref.id,
          'type': type.name,
          'title': title,
          'body': body,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          if (groupId != null) 'groupId': groupId,
          if (relatedId != null) 'relatedId': relatedId,
          if (fromUserName != null) 'fromUserName': fromUserName,
        });
      }
      await batch.commit();
    } catch (_) {
      // Notification dispatch is best-effort; never block the main action.
    }
  }
}
