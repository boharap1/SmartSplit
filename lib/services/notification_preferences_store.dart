import 'package:shared_preferences/shared_preferences.dart';

/// Typed, async-safe wrapper around SharedPreferences.
///
/// This is Flutter's equivalent of Android's `DataStore<Preferences>`.
/// All preference keys are private — callers use typed getters/setters only.
/// Instantiate once and inject; do not call SharedPreferences directly for
/// notification preferences anywhere else.
class NotificationPreferencesStore {
  static const _kPushEnabled  = 'pref_push_notifications_enabled';
  static const _kEmailEnabled = 'pref_email_notifications_enabled';

  final SharedPreferences _prefs;
  NotificationPreferencesStore._(this._prefs);

  /// Always use this factory; never construct directly.
  static Future<NotificationPreferencesStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationPreferencesStore._(prefs);
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  /// Whether the user wants device heads-up (local + FCM) push notifications.
  bool get pushEnabled  => _prefs.getBool(_kPushEnabled)  ?? true;

  /// Whether the user wants email notifications (backend-enforced).
  bool get emailEnabled => _prefs.getBool(_kEmailEnabled) ?? false;

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> setPushEnabled(bool value)  => _prefs.setBool(_kPushEnabled,  value);
  Future<void> setEmailEnabled(bool value) => _prefs.setBool(_kEmailEnabled, value);
}
