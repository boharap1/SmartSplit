import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/notification_model.dart';
import 'notification_preferences_store.dart';
import 'notification_service.dart';

// ── Payload ───────────────────────────────────────────────────────────────────

class DispatchPayload {
  final String title;
  final String body;

  /// All user IDs that should receive this notification.
  final List<String> recipientUserIds;

  /// The user who triggered the action — excluded from recipients so they
  /// don't notify themselves.
  final String? excludeUserId;

  final NotificationType type;
  final NotificationPriority priority;
  final String? groupId;
  final String? relatedId;
  final String? fromUserName;

  const DispatchPayload({
    required this.title,
    required this.body,
    required this.recipientUserIds,
    this.excludeUserId,
    required this.type,
    this.priority = NotificationPriority.normal,
    this.groupId,
    this.relatedId,
    this.fromUserName,
  });
}

// ── Dispatcher ────────────────────────────────────────────────────────────────

/// Routes a notification to the correct channels based on priority and
/// the recipient's stored preferences.
///
/// Routing table:
///
/// | Channel | normal           | critical |
/// |---------|------------------|----------|
/// | In-app  | always           | always   |
/// | Push    | if pref enabled  | always   |
/// | Email   | if pref enabled  | always   |
///
/// Failures in push or email are non-fatal — in-app is always committed first.
class NotificationDispatcher {
  static final NotificationDispatcher instance = NotificationDispatcher._();
  NotificationDispatcher._();

  static final _db = FirebaseFirestore.instance;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Dispatch a [NotificationPriority.normal] notification.
  /// Push and email fire only when the recipient has those channels enabled.
  Future<void> dispatch(
    DispatchPayload payload,
    NotificationPreferencesStore prefs,
  ) async {
    final recipients = _filterRecipients(payload);
    if (recipients.isEmpty) return;

    final sendPush  = prefs.pushEnabled;
    final sendEmail = prefs.emailEnabled;

    await _send(payload, recipients, sendPush: sendPush, sendEmail: sendEmail);
  }

  /// Dispatch a [NotificationPriority.critical] notification.
  /// All channels fire regardless of the recipient's preference settings.
  /// Use for payment requests, security alerts, and similar must-reach events.
  Future<void> dispatchCritical(DispatchPayload payload) async {
    final recipients = _filterRecipients(payload);
    if (recipients.isEmpty) return;

    await _send(payload, recipients, sendPush: true, sendEmail: true);
  }

  // ── Internal routing ──────────────────────────────────────────────────────

  List<String> _filterRecipients(DispatchPayload payload) => payload
      .recipientUserIds
      .where((id) => id != payload.excludeUserId)
      .toList();

  Future<void> _send(
    DispatchPayload payload,
    List<String> recipients, {
    required bool sendPush,
    required bool sendEmail,
  }) async {
    // In-app always runs first and independently of push/email.
    await _dispatchInApp(payload, recipients);

    await Future.wait([
      if (sendPush)  _dispatchPush(payload),
      if (sendEmail) _dispatchEmail(payload, recipients),
    ]);
  }

  // ── Channel: In-App (Firestore) ───────────────────────────────────────────

  Future<void> _dispatchInApp(
    DispatchPayload payload,
    List<String> recipients,
  ) async {
    try {
      final batch = _db.batch();
      for (final uid in recipients) {
        final ref = _db
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .doc();
        batch.set(ref, {
          'id':           ref.id,
          'type':         payload.type.name,
          'priority':     payload.priority.name,
          'title':        payload.title,
          'body':         payload.body,
          'isRead':       false,
          'createdAt':    FieldValue.serverTimestamp(),
          if (payload.groupId      != null) 'groupId':      payload.groupId,
          if (payload.relatedId    != null) 'relatedId':    payload.relatedId,
          if (payload.fromUserName != null) 'fromUserName': payload.fromUserName,
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[Dispatcher] in-app failed: $e');
    }
  }

  // ── Channel: Push (local heads-up) ────────────────────────────────────────

  Future<void> _dispatchPush(DispatchPayload payload) async {
    try {
      await NotificationService.instance.showLocal(
        title:   payload.title,
        body:    payload.body,
        payload: payload.groupId,
      );
    } catch (e) {
      // Non-fatal: in-app already committed.
      debugPrint('[Dispatcher] push failed: $e');
    }
  }

  // ── Channel: Email (backend-ready placeholder) ────────────────────────────

  Future<void> _dispatchEmail(
    DispatchPayload payload,
    List<String> recipients,
  ) async {
    try {
      await _sendEmailNotification(
        userIds:  recipients,
        subject:  payload.title,
        body:     payload.body,
        groupId:  payload.groupId,
        fromUser: payload.fromUserName,
      );
    } catch (e) {
      // Non-fatal: other channels already handled.
      debugPrint('[Dispatcher] email failed: $e');
    }
  }

  /// Backend stub — replace with your HTTP / Cloud Function call.
  ///
  /// ```dart
  /// await http.post(
  ///   Uri.parse('https://your-api.com/v1/notifications/email'),
  ///   headers: {'Content-Type': 'application/json',
  ///             'Authorization': 'Bearer $token'},
  ///   body: jsonEncode({
  ///     'userIds':  userIds,
  ///     'subject':  subject,
  ///     'body':     body,
  ///     'groupId':  groupId,
  ///     'fromUser': fromUser,
  ///   }),
  /// );
  /// ```
  Future<void> _sendEmailNotification({
    required List<String> userIds,
    required String subject,
    required String body,
    String? groupId,
    String? fromUser,
  }) async {
    debugPrint(
      '[Email stub] to=$userIds | subject="$subject" | from=$fromUser',
    );
  }
}
