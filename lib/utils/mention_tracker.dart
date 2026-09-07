import 'package:ballys_reservation_app/data/services/firebase_api_service.dart';
import 'package:ballys_reservation_app/models/chat_message.dart';

/// Which conversations have unread messages that name the signed-in user, so
/// the chat list can show the "@" marker WhatsApp shows.
///
/// Neither the chats nor the groups list endpoint carries a mention flag, so
/// the marker is worked out on the client. Only a conversation with something
/// unread is scanned — nothing unread means nothing to flag — and each is
/// scanned again only once its unread count or last message has moved on, so
/// a list refresh that changed nothing costs no requests.
class MentionTracker {
  MentionTracker._();

  /// chatId → message ids of the unread messages naming the user, oldest first.
  static final Map<String, List<String>> _mentions = {};

  /// chatId → the signature the cached entry above was scanned for.
  static final Map<String, String> _signatures = {};

  static List<String> mentionsIn(String chatId) =>
      _mentions[chatId] ?? const <String>[];

  static bool hasMentions(String chatId) => mentionsIn(chatId).isNotEmpty;

  static void clear(String chatId) {
    _mentions.remove(chatId);
    _signatures.remove(chatId);
  }

  static void clearAll() {
    _mentions.clear();
    _signatures.clear();
  }

  /// Rescans [chatId] when [signature] shows something changed since the last
  /// look — pass whatever identifies "same state as before", such as the
  /// unread count and last message time.
  ///
  /// Returns true when the marker for this conversation changed, so the caller
  /// can rebuild only when there is something new to show.
  static Future<bool> refresh({
    required String chatId,
    required String signature,
    required bool hasUnread,
    required String? currentUserUuid,
  }) async {
    if (chatId.isEmpty) return false;

    // Read (or no identity to match against): drop the marker without asking
    // the server anything.
    if (!hasUnread || currentUserUuid == null || currentUserUuid.isEmpty) {
      final had = hasMentions(chatId);
      clear(chatId);
      return had;
    }

    if (_signatures[chatId] == signature) return false;

    final ids = await _scan(chatId, currentUserUuid);
    _signatures[chatId] = signature;

    final previous = mentionsIn(chatId);
    if (ids.isEmpty) {
      _mentions.remove(chatId);
      return previous.isNotEmpty;
    }
    _mentions[chatId] = ids;
    return !_sameIds(previous, ids);
  }

  /// Page size used while scanning, and how many pages back the scan is
  /// willing to walk.
  ///
  /// The messages endpoint is paginated, so the whole history no longer
  /// arrives in one response. Unread messages sit at the end of a
  /// conversation, so the scan walks back from the newest page only as long
  /// as it keeps finding unread ones — the cap is there for the pathological
  /// case of a conversation nobody has opened in a very long time.
  static const int _scanPageSize = 100;
  static const int _scanPageLimit = 5;

  /// The unread messages of [chatId] that name [userUuid], oldest first.
  /// Failures answer "no mentions" — a missed marker is better than a broken
  /// chat list.
  static Future<List<String>> _scan(String chatId, String userUuid) async {
    try {
      final hits = <ChatMessage>[];
      int? before;

      for (var page = 0; page < _scanPageLimit; page++) {
        final response = await FirebaseApiService.fetchMessages(
          chatId,
          limit: _scanPageSize,
          before: before,
        );
        if (response['success'] != true) break;

        final data = response['data'];
        if (data is! Map) break;
        final raw = data['messages'];
        if (raw is! List) break;

        var sawUnread = false;
        for (final row in raw.whereType<Map<String, dynamic>>()) {
          final ChatMessage message;
          try {
            message = ChatMessage.fromApiResponse(row, userUuid);
          } catch (_) {
            continue; // A single malformed row must not lose the rest.
          }
          if (message.isMe || message.isRead == true) continue;
          sawUnread = true;
          if (!message.mentionsUser(userUuid, FirebaseApiService.appType)) {
            continue;
          }
          hits.add(message);
        }

        // Nothing unread left in this page means everything before it has
        // been read too, so there is no older mention to find.
        if (!sawUnread) break;

        if (data['hasMore'] != true) break;
        final cursor = data['nextCursor'];
        before = cursor is num
            ? cursor.toInt()
            : int.tryParse(cursor?.toString() ?? '');
        if (before == null) break;
      }

      hits.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return hits.map((m) => m.apiMessageId ?? m.id).toList();
    } catch (_) {
      return const [];
    }
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
