import 'dart:convert';

import 'package:ballys_reservation_app/models/app_notification.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists received push notifications so the home screen bell can show them
/// even after the app is killed and relaunched.
///
/// Safe to call from the FCM background isolate — every read calls
/// [SharedPreferences.reload] first so the main isolate picks up whatever the
/// background isolate wrote.
class NotificationStore {
  static const String _key = 'app_notification_history';
  static const int _maxStored = 100;

  /// Pings that only tell the client a thread changed — an edited message, a
  /// reaction — and carry no body of their own. They must never raise a
  /// banner or bump the badge: nothing new was said.
  ///
  /// The backend sends these as an ordinary chat push (`msg_type: 11`) and
  /// says what they really are inside `Details`, in `action` and a `silent`
  /// flag — so the top-level type alone never identifies one.
  static bool isSilentThreadUpdate(RemoteMessage message) {
    const silentActions = {
      'message_edit',
      'message_edited',
      'message_reaction',
    };

    final type = (message.data['msg_type'] ?? message.data['type'])?.toString();
    if (silentActions.contains(type)) return true;

    final details = _details(message.data);
    if (details == null) return false;
    if (silentActions.contains(details['action']?.toString())) return true;
    return details['silent']?.toString().toLowerCase() == 'true';
  }

  /// The `Details` payload decoded, or null when the push has none or it is
  /// not the JSON object it is meant to be.
  static Map<String, dynamic>? _details(Map<String, dynamic> data) {
    final raw = data['Details']?.toString();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Chat pushes are handled by the chat screens, so they never enter history.
  static bool isChatMessage(RemoteMessage message) {
    final data = message.data;

    if (data['msg_type']?.toString() == '11') return true;
    if (data['screen']?.toString() == 'chat') return true;
    if (data['chatId'] != null || data['chat_id'] != null) return true;

    if (_details(data)?['chatId'] != null) return true;

    return false;
  }

  static AppNotification? fromRemoteMessage(RemoteMessage message) {
    if (isChatMessage(message)) return null;

    final data = message.data;
    final title =
        data['title'] ?? message.notification?.title ?? 'New Notification';
    final body = data['body'] ?? message.notification?.body ?? '';

    return AppNotification(
      id:
          message.messageId ??
          '${DateTime.now().microsecondsSinceEpoch}_${title.hashCode}',
      title: title,
      body: body,
      msgType: data['msg_type']?.toString() ?? '',
      data: data.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      ),
      receivedAt: DateTime.now(),
    );
  }

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Pull in writes made by the background isolate.
    await prefs.reload();
    return prefs;
  }

  static Future<List<AppNotification>> load() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getStringList(_key) ?? [];
      final items = raw
          .map((e) {
            try {
              return AppNotification.fromJson(json.decode(e));
            } catch (_) {
              return null;
            }
          })
          .whereType<AppNotification>()
          .toList();

      items.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      return items;
    } catch (e) {
      print('Error loading notification history: $e');
      return [];
    }
  }

  static Future<void> save(List<AppNotification> items) async {
    try {
      final prefs = await _prefs();
      final trimmed = items.take(_maxStored).toList();
      await prefs.setStringList(
        _key,
        trimmed.map((e) => json.encode(e.toJson())).toList(),
      );
    } catch (e) {
      print('Error saving notification history: $e');
    }
  }

  /// Adds a notification to history. Returns the updated list, or null when the
  /// message was a chat push (nothing stored) or a duplicate.
  static Future<List<AppNotification>?> add(RemoteMessage message) async {
    final notification = fromRemoteMessage(message);
    if (notification == null) return null;

    final existing = await load();
    if (existing.any((e) => e.id == notification.id)) return null;

    final updated = [notification, ...existing];
    await save(updated);
    return updated;
  }

  static Future<List<AppNotification>> markAllRead() async {
    final updated = (await load()).map((e) => e.copyWith(isRead: true)).toList();
    await save(updated);
    return updated;
  }

  static Future<List<AppNotification>> markRead(String id) async {
    final updated = (await load())
        .map((e) => e.id == id ? e.copyWith(isRead: true) : e)
        .toList();
    await save(updated);
    return updated;
  }

  static Future<List<AppNotification>> remove(String id) async {
    final updated = (await load()).where((e) => e.id != id).toList();
    await save(updated);
    return updated;
  }

  static Future<List<AppNotification>> clear() async {
    await save([]);
    return [];
  }
}
