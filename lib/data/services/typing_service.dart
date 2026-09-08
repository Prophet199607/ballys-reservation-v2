import 'dart:async';

import 'package:ballys_reservation_app/data/services/firebase_api_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Someone currently typing in a chat, as read from Firestore.
class TypingUser {
  const TypingUser({
    required this.userUuid,
    required this.appType,
    required this.userName,
    required this.updatedAt,
  });

  final String userUuid;
  final int appType;
  final String userName;
  final DateTime updatedAt;

  /// Whether this entry is us, so the screen can leave our own typing out of
  /// the header. Uuids are compared case-insensitively, as elsewhere in chat.
  bool matches(String? uuid, int otherAppType) =>
      uuid != null &&
      uuid.isNotEmpty &&
      userUuid.toLowerCase() == uuid.toLowerCase() &&
      appType == otherAppType;

  static TypingUser? fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final updatedAt = data['updatedAt'];
    // The doc id is `{userUuid}_{appType}`, but the fields carry the same
    // values — fall back to the id only if a writer left them out.
    final uuid = (data['userUuid'] as String?) ?? _uuidFromId(doc.id);
    if (uuid == null || uuid.isEmpty) return null;
    return TypingUser(
      userUuid: uuid,
      appType: (data['appType'] as num?)?.toInt() ?? _appTypeFromId(doc.id) ?? 0,
      userName: (data['userName'] as String?)?.trim() ?? '',
      // A doc written with a server timestamp reads back null for the instant
      // between the local write and the server ack. Treating it as "now" keeps
      // the indicator from flickering off during that window.
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
    );
  }

  static String? _uuidFromId(String id) {
    final cut = id.lastIndexOf('_');
    return cut <= 0 ? id : id.substring(0, cut);
  }

  static int? _appTypeFromId(String id) {
    final cut = id.lastIndexOf('_');
    return cut < 0 ? null : int.tryParse(id.substring(cut + 1));
  }
}

/// Reads and writes typing status for one chat.
///
/// Writes go through the REST endpoint (`POST /api/chats/:chatId/typing`),
/// which is what actually touches Firestore; reads come straight from
/// Firestore, since the status is deliberately kept off the REST API and out
/// of push — it is far too chatty for either.
class TypingService {
  TypingService._();

  /// A typing doc older than this is ignored even if it was never deleted. A
  /// dropped connection or a killed app must not leave a stuck "typing…".
  static const Duration staleAfter = Duration(seconds: 6);

  /// How often the pruning pass re-runs. Firestore only pushes a snapshot when
  /// a doc changes, so without this a doc that simply went quiet would sit in
  /// the header until the next write.
  static const Duration _pruneInterval = Duration(seconds: 2);

  static CollectionReference<Map<String, dynamic>> _collection(String chatId) =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('typing');

  /// Everyone currently typing in [chatId], stale entries dropped — including
  /// us, so the caller decides how to treat its own echo.
  ///
  /// Firestore errors are swallowed into an empty list: typing is a nicety,
  /// and a missing index or a rules rejection must not break the chat.
  static Stream<List<TypingUser>> watch(String chatId) {
    final controller = StreamController<List<TypingUser>>.broadcast();
    List<TypingUser> latest = const [];
    List<TypingUser> emitted = const [];
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? snapshots;
    Timer? pruner;

    void publish() {
      final now = DateTime.now();
      // A negative age means the writer's clock ran ahead of ours; that is
      // skew, not staleness, so it still counts as typing.
      final fresh = latest
          .where((t) => now.difference(t.updatedAt) <= staleAfter)
          .toList();
      if (_sameTypers(fresh, emitted)) return;
      emitted = fresh;
      controller.add(fresh);
    }

    controller.onListen = () {
      snapshots = _collection(chatId).snapshots().listen(
        (snap) {
          latest = snap.docs
              .map(TypingUser.fromDoc)
              .whereType<TypingUser>()
              .toList();
          publish();
        },
        onError: (_) {
          latest = const [];
          publish();
        },
      );
      pruner = Timer.periodic(_pruneInterval, (_) => publish());
    };
    controller.onCancel = () async {
      pruner?.cancel();
      await snapshots?.cancel();
    };
    return controller.stream;
  }

  /// Compared by identity and order so the header only rebuilds when the set
  /// of typers actually changes — the pruning pass runs every couple of
  /// seconds and would otherwise emit constantly.
  static bool _sameTypers(List<TypingUser> a, List<TypingUser> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].userUuid != b[i].userUuid || a[i].appType != b[i].appType) {
        return false;
      }
    }
    return true;
  }
}

/// Debounces our own typing status for one chat.
///
/// [keystroke] is safe to call on every character: it posts `true` at most
/// once every [_resendAfter], and posts `false` on its own once typing has
/// paused for [_idleAfter], so the indicator clears even if the screen is
/// never told the user gave up.
class TypingSignal {
  TypingSignal({required this.chatId, this.userName});

  final String chatId;

  /// Shown by the other clients in groups ("John is typing…").
  final String? userName;

  /// The backend's doc is refreshed rather than re-created, so this only has
  /// to beat [TypingService.staleAfter].
  static const Duration _resendAfter = Duration(seconds: 2);

  /// A pause this long counts as having stopped typing.
  static const Duration _idleAfter = Duration(seconds: 4);

  bool _typing = false;
  DateTime? _lastSentAt;
  Timer? _idleTimer;
  bool _disposed = false;

  /// Call from the composer's `onChanged` whenever there is text.
  void keystroke() {
    if (_disposed) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleAfter, stop);

    final last = _lastSentAt;
    if (_typing && last != null && DateTime.now().difference(last) < _resendAfter) {
      return;
    }
    _typing = true;
    _lastSentAt = DateTime.now();
    _post(true);
  }

  /// Call when the composer is cleared, the message is sent, or the screen
  /// goes away. Idempotent — a stop with nothing to stop costs nothing.
  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_typing) return;
    _typing = false;
    _lastSentAt = null;
    _post(false);
  }

  /// Stops typing and blocks any further posts. The stop is still sent, so the
  /// indicator clears on the other side when the screen is closed mid-word.
  void dispose() {
    stop();
    _disposed = true;
  }

  /// Fire and forget: a typing ping that fails is not worth surfacing, and the
  /// staleness window clears whatever it left behind.
  void _post(bool isTyping) {
    FirebaseApiService.setTyping(
      chatId: chatId,
      isTyping: isTyping,
      userName: userName,
    ).catchError((_) => <String, dynamic>{'success': false});
  }
}
