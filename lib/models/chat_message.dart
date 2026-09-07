import 'package:ballys_reservation_app/data/services/firebase_api_service.dart';
import 'package:ballys_reservation_app/models/chat_contact.dart';

/// A single attachment item (used inside groupedAttachments).
class AttachmentItem {
  final String? url;        // remote URL
  final String? localPath;  // local file path (pre-upload)
  final String? fileName;
  final String? mimeType;   // e.g. 'image/jpeg'
  final String? messageId;  // server-assigned messageId after upload

  /// A clip recorded in the composer rather than an audio file someone picked
  /// — the backend tags it `isVoiceNote` so it renders as a voice bubble.
  final bool isVoiceNote;

  /// Playback length in whole seconds, as measured while recording and sent
  /// with the upload. Only set on a voice note.
  final int? durationSeconds;

  const AttachmentItem({
    this.url,
    this.localPath,
    this.fileName,
    this.mimeType,
    this.messageId,
    this.isVoiceNote = false,
    this.durationSeconds,
  });

  bool get isImage =>
      (mimeType ?? '').startsWith('image/') ||
      _isImageExtension(localPath ?? url ?? '');

  static bool _isImageExtension(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  }

  AttachmentItem copyWith({
    String? url,
    String? localPath,
    String? fileName,
    String? mimeType,
    String? messageId,
    bool? isVoiceNote,
    int? durationSeconds,
  }) =>
      AttachmentItem(
        url: url ?? this.url,
        localPath: localPath ?? this.localPath,
        fileName: fileName ?? this.fileName,
        mimeType: mimeType ?? this.mimeType,
        messageId: messageId ?? this.messageId,
        isVoiceNote: isVoiceNote ?? this.isVoiceNote,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'localPath': localPath,
        'fileName': fileName,
        'mimeType': mimeType,
        'messageId': messageId,
        'isVoiceNote': isVoiceNote,
        'durationSeconds': durationSeconds,
      };

  static AttachmentItem fromJson(Map<String, dynamic> j) => AttachmentItem(
        url: j['url'],
        localPath: j['localPath'],
        fileName: j['fileName'],
        mimeType: j['mimeType'],
        messageId: j['messageId'],
        isVoiceNote: parseVoiceNoteFlag(j['isVoiceNote']),
        durationSeconds: parseDurationSeconds(j['durationSeconds']),
      );

  /// The backend sends this as true/false on some rows and 1/0 on others,
  /// matching how it sends `isForwarded` and `isEdited`.
  static bool parseVoiceNoteFlag(dynamic raw) => raw == true || raw == 1;

  /// Whole seconds, tolerating the number arriving as a string. A zero or
  /// negative length is no length at all, so it reads as absent.
  static int? parseDurationSeconds(dynamic raw) {
    final value = raw is num ? raw.round() : int.tryParse(raw?.toString() ?? '');
    return (value == null || value <= 0) ? null : value;
  }
}

// ---------------------------------------------------------------------------

/// Someone named with an @ in a message, as sent in `mentionedUserIds` and
/// returned in `mentions`.
///
/// The uuid alone does not identify a person — the same uuid can exist under
/// another app — so [appType] is part of the identity.
class MessageMention {
  final String userUuid;
  final int appType;

  const MessageMention({required this.userUuid, required this.appType});

  /// uuids arrive in mixed case (an Android device id versus an iOS vendor
  /// uuid), so compare case-insensitively.
  bool matches(String? userUuid, int appType) =>
      userUuid != null &&
      userUuid.toLowerCase() == this.userUuid.toLowerCase() &&
      appType == this.appType;

  Map<String, dynamic> toJson() => {'userUuid': userUuid, 'appType': appType};

  static MessageMention fromJson(Map<String, dynamic> json) => MessageMention(
        userUuid: json['userUuid']?.toString() ?? '',
        appType: ChatContact.parseAppType(json['appType']),
      );

  /// Tolerates a null, a non-list, or rows that are not objects — a malformed
  /// mentions field must not take out the whole message list.
  static List<MessageMention> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MessageMention.fromJson)
        .where((m) => m.userUuid.isNotEmpty)
        .toList();
  }
}

/// One person's reaction to a message, as returned in `reactions` and sent to
/// POST /api/chats/:chatId/messages/:messageId/react.
///
/// The backend keeps **at most one** reaction per user per message: sending
/// the emoji someone already has removes it, a different one replaces it. As
/// with [MessageMention], the uuid alone does not identify a person, so
/// [appType] is part of the identity.
class MessageReaction {
  final String userUuid;
  final int appType;
  final String emoji;

  const MessageReaction({
    required this.userUuid,
    required this.appType,
    required this.emoji,
  });

  /// uuids arrive in mixed case (an Android device id versus an iOS vendor
  /// uuid), so compare case-insensitively.
  bool matches(String? userUuid, int appType) =>
      userUuid != null &&
      userUuid.toLowerCase() == this.userUuid.toLowerCase() &&
      appType == this.appType;

  Map<String, dynamic> toJson() =>
      {'userUuid': userUuid, 'appType': appType, 'emoji': emoji};

  static MessageReaction fromJson(Map<String, dynamic> json) => MessageReaction(
        userUuid: json['userUuid']?.toString() ?? '',
        appType: ChatContact.parseAppType(json['appType']),
        emoji: json['emoji']?.toString() ?? '',
      );

  /// Tolerates a null, a non-list, or rows that are not objects — a malformed
  /// reactions field must not take out the whole message list.
  static List<MessageReaction> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MessageReaction.fromJson)
        .where((r) => r.userUuid.isNotEmpty && r.emoji.isNotEmpty)
        .toList();
  }
}

/// One person who has read this message, as returned in `seenBy`.
///
/// The backend appends a row per reader as they open the chat: in a 1:1 chat
/// that is at most the other party, in a group one row per member who has
/// caught up. The sender is never listed. As with [MessageReaction], the uuid
/// alone does not identify a person, so [appType] is part of the identity.
class MessageSeen {
  final String userUuid;
  final int appType;

  /// How the reader is titled ("Mr Pasindu") and their given name
  /// ("Pasindu"). Either can be missing on an older row.
  final String? name;
  final String? firstName;

  /// When they read it. Null when the backend sent no readAt or a malformed
  /// one — the row still counts as seen, just without a time.
  final DateTime? readAt;

  const MessageSeen({
    required this.userUuid,
    required this.appType,
    this.name,
    this.firstName,
    this.readAt,
  });

  /// What to put in a "Seen by" list: the full title when there is one, the
  /// given name otherwise, and never an empty string.
  String get displayName {
    final full = name?.trim() ?? '';
    if (full.isNotEmpty) return full;
    final first = firstName?.trim() ?? '';
    return first.isNotEmpty ? first : 'Unknown';
  }

  /// uuids arrive in mixed case (an Android device id versus an iOS vendor
  /// uuid), so compare case-insensitively.
  bool matches(String? userUuid, int appType) =>
      userUuid != null &&
      userUuid.toLowerCase() == this.userUuid.toLowerCase() &&
      appType == this.appType;

  Map<String, dynamic> toJson() => {
        'userUuid': userUuid,
        'appType': appType,
        'name': name,
        'firstName': firstName,
        'readAt': readAt?.toIso8601String(),
      };

  static MessageSeen fromJson(Map<String, dynamic> json) => MessageSeen(
        userUuid: json['userUuid']?.toString() ?? '',
        appType: ChatContact.parseAppType(json['appType']),
        name: json['name']?.toString(),
        firstName: json['firstName']?.toString(),
        readAt: ChatMessage._parseTimestamp(json['readAt']),
      );

  /// Tolerates a null, a non-list, or rows that are not objects — a malformed
  /// seenBy field must not take out the whole message list.
  static List<MessageSeen> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MessageSeen.fromJson)
        .where((s) => s.userUuid.isNotEmpty)
        .toList();
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final DateTime timestamp;
  final String? apiMessageId;
  final String? apiChatId;
  final bool? isRead;

  // Who sent it. Only meaningful for group chats, where several different
  // people appear on the incoming side.
  final String? senderId;
  final String? senderName;

  // Single-attachment fields (kept for backwards compat)
  final String? filePath;
  final String? fileType;
  final String? fileName;
  final String? attachmentUrl;
  final String? attachmentType;

  // Voice note: a clip recorded in the composer, as opposed to an audio file
  // someone attached. Carries its playback length so the bubble can show it
  // before the audio is loaded. [fileType] is 'voice' on these.
  final bool isVoiceNote;
  final int? voiceDurationSeconds;

  // Forwarded: set by the backend on messages produced by
  // POST /api/chats/:chatId/messages/:messageId/forward, so the bubble can
  // show a "Forwarded" tag naming whoever sent the original.
  final bool isForwarded;
  final String? forwardedFromSenderName;

  // Reply: set when this message quotes another one in the same chat. The
  // text and sender name are a snapshot taken at send time, so the quoted
  // preview survives the original being deleted.
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToSenderName;

  // Multi-attachment: when non-empty, render as image grid
  final List<AttachmentItem> groupedAttachments;

  // People @-mentioned in this message. Empty on messages with no mentions.
  final List<MessageMention> mentions;

  // Emoji reactions, one entry per person who reacted. Empty when nobody has.
  final List<MessageReaction> reactions;

  // Who has read this message, one entry per reader, in the order the backend
  // recorded them. Empty until somebody opens the chat, and always empty on
  // an incoming message the backend did not report readers for.
  final List<MessageSeen> seenBy;

  // Edited: the sender corrected the text after sending. [editedAt] is when
  // the last edit landed, and is null on a message that was never edited.
  final bool isEdited;
  final DateTime? editedAt;

  // Deleted for everyone: the sender removed it with the soft-delete
  // endpoint. The row stays in the conversation as a tombstone — the backend
  // keeps returning it but withholds the real text and attachment, sending
  // the placeholder in [text] instead — so the thread shows "this message was
  // deleted" rather than a silent gap. Deleting for yourself is a different
  // operation: the backend drops that message from your list entirely, so it
  // never reaches the client at all.
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedBy;

  // System: not written by anyone, but generated by the backend to narrate
  // something that happened to the chat itself — someone added or removed,
  // the group renamed, admin-only messaging toggled. Rendered as a centered
  // notice instead of a bubble, and it takes part in none of the message
  // actions (reply, forward, react, select, delete).
  final bool isSystem;
  final String? systemEvent;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isMe,
    required this.timestamp,
    this.apiMessageId,
    this.apiChatId,
    this.filePath,
    this.fileType,
    this.fileName,
    this.isRead,
    this.attachmentUrl,
    this.attachmentType,
    this.isVoiceNote = false,
    this.voiceDurationSeconds,
    this.senderId,
    this.senderName,
    this.isForwarded = false,
    this.forwardedFromSenderName,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderName,
    List<AttachmentItem>? groupedAttachments,
    List<MessageMention>? mentions,
    List<MessageReaction>? reactions,
    List<MessageSeen>? seenBy,
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
    this.isSystem = false,
    this.systemEvent,
  })  : groupedAttachments = groupedAttachments ?? const [],
        mentions = mentions ?? const [],
        reactions = reactions ?? const [],
        seenBy = seenBy ?? const [];

  bool get hasMentions => mentions.isNotEmpty;

  /// True when [userUuid]/[appType] is one of the people named in this
  /// message — i.e. "this one is for you".
  bool mentionsUser(String? userUuid, int appType) =>
      mentions.any((m) => m.matches(userUuid, appType));

  bool get hasReactions => reactions.isNotEmpty;

  /// The emoji [userUuid]/[appType] currently has on this message, or null if
  /// they have not reacted. At most one, by the backend's toggle rule.
  String? reactionOf(String? userUuid, int appType) {
    for (final r in reactions) {
      if (r.matches(userUuid, appType)) return r.emoji;
    }
    return null;
  }

  /// Reactions collapsed into `emoji -> count`, in the order each emoji was
  /// first used, so the summary bar does not reshuffle as people react.
  Map<String, int> get reactionCounts {
    final counts = <String, int>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    return counts;
  }

  bool get hasSeenBy => seenBy.isNotEmpty;

  /// The readers other than [userUuid]/[appType] — i.e. everyone the sender
  /// cares about, since your own read of your own message is not news.
  List<MessageSeen> seenByOthers(String? userUuid, int appType) =>
      seenBy.where((s) => !s.matches(userUuid, appType)).toList();

  /// Whether [userUuid]/[appType] has read this message.
  bool isSeenBy(String? userUuid, int appType) =>
      seenBy.any((s) => s.matches(userUuid, appType));

  /// When [userUuid]/[appType] read it, or null if they have not (or the
  /// backend recorded no time).
  DateTime? seenAt(String? userUuid, int appType) {
    for (final s in seenBy) {
      if (s.matches(userUuid, appType)) return s.readAt;
    }
    return null;
  }

  /// What a message deleted for everyone reads as. The backend sends its own
  /// placeholder in `text`; this stands in when an older row arrives flagged
  /// deleted but with nothing in it.
  static const String deletedPlaceholder = '⊘ This message was deleted';

  /// The tombstone line to render, whatever the backend put in `text`.
  String get deletedText =>
      text.trim().isEmpty ? deletedPlaceholder : text.trim();

  /// This message as the tombstone the server now holds: the real text and
  /// any attachment are gone, and only the placeholder is left. Used to
  /// rewrite the bubble in place after a delete-for-everyone, so the thread
  /// matches what the next fetch will return.
  ChatMessage asDeleted({String? deletedBy, DateTime? deletedAt}) => ChatMessage(
        id: id,
        text: deletedPlaceholder,
        isMe: isMe,
        timestamp: timestamp,
        apiMessageId: apiMessageId,
        apiChatId: apiChatId,
        isRead: isRead,
        senderId: senderId,
        senderName: senderName,
        replyToMessageId: replyToMessageId,
        replyToText: replyToText,
        replyToSenderName: replyToSenderName,
        mentions: mentions,
        reactions: reactions,
        seenBy: seenBy,
        isDeleted: true,
        deletedAt: deletedAt ?? DateTime.now(),
        deletedBy: deletedBy,
      );

  /// How long after sending the backend still accepts an edit. Rejected
  /// server-side past this, so the client only hides the action early enough
  /// to keep the user from writing a correction that would bounce.
  static const Duration editWindow = Duration(minutes: 15);

  /// Only a plain text message of the user's own can be edited: attachments
  /// have no text to correct, and one still on its way to the server has no
  /// id to address.
  bool get isEditable =>
      isMe &&
      !isSystem &&
      !isDeleted &&
      apiMessageId != null &&
      apiChatId != null &&
      fileType == null &&
      !hasGroupedAttachments &&
      text.trim().isNotEmpty;

  /// Whether the 15-minute window is still open, as of [now].
  bool isWithinEditWindow([DateTime? now]) =>
      (now ?? DateTime.now()).difference(timestamp) < editWindow;

  /// What is left of the edit window, or [Duration.zero] once it has closed.
  Duration editWindowRemaining([DateTime? now]) {
    final left = timestamp.add(editWindow).difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get hasGroupedAttachments => groupedAttachments.isNotEmpty;

  /// The recorded length, or null on anything that is not a voice note (and
  /// on one the backend gave no duration for).
  Duration? get voiceDuration => isVoiceNote && voiceDurationSeconds != null
      ? Duration(seconds: voiceDurationSeconds!)
      : null;

  bool get isImageGroup =>
      hasGroupedAttachments && groupedAttachments.every((a) => a.isImage);

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isMe,
    DateTime? timestamp,
    String? apiMessageId,
    String? apiChatId,
    String? filePath,
    String? fileType,
    String? fileName,
    bool? isRead,
    String? attachmentUrl,
    String? attachmentType,
    bool? isVoiceNote,
    int? voiceDurationSeconds,
    String? senderId,
    String? senderName,
    bool? isForwarded,
    String? forwardedFromSenderName,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderName,
    List<AttachmentItem>? groupedAttachments,
    List<MessageMention>? mentions,
    List<MessageReaction>? reactions,
    List<MessageSeen>? seenBy,
    bool? isEdited,
    DateTime? editedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    String? deletedBy,
    bool? isSystem,
    String? systemEvent,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        text: text ?? this.text,
        isMe: isMe ?? this.isMe,
        timestamp: timestamp ?? this.timestamp,
        apiMessageId: apiMessageId ?? this.apiMessageId,
        apiChatId: apiChatId ?? this.apiChatId,
        filePath: filePath ?? this.filePath,
        fileType: fileType ?? this.fileType,
        fileName: fileName ?? this.fileName,
        isRead: isRead ?? this.isRead,
        attachmentUrl: attachmentUrl ?? this.attachmentUrl,
        attachmentType: attachmentType ?? this.attachmentType,
        isVoiceNote: isVoiceNote ?? this.isVoiceNote,
        voiceDurationSeconds:
            voiceDurationSeconds ?? this.voiceDurationSeconds,
        senderId: senderId ?? this.senderId,
        senderName: senderName ?? this.senderName,
        isForwarded: isForwarded ?? this.isForwarded,
        forwardedFromSenderName:
            forwardedFromSenderName ?? this.forwardedFromSenderName,
        replyToMessageId: replyToMessageId ?? this.replyToMessageId,
        replyToText: replyToText ?? this.replyToText,
        replyToSenderName: replyToSenderName ?? this.replyToSenderName,
        groupedAttachments: groupedAttachments ?? this.groupedAttachments,
        mentions: mentions ?? this.mentions,
        reactions: reactions ?? this.reactions,
        seenBy: seenBy ?? this.seenBy,
        isEdited: isEdited ?? this.isEdited,
        editedAt: editedAt ?? this.editedAt,
        isDeleted: isDeleted ?? this.isDeleted,
        deletedAt: deletedAt ?? this.deletedAt,
        deletedBy: deletedBy ?? this.deletedBy,
        isSystem: isSystem ?? this.isSystem,
        systemEvent: systemEvent ?? this.systemEvent,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isMe': isMe,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'apiMessageId': apiMessageId,
        'apiChatId': apiChatId,
        'filePath': filePath,
        'fileType': fileType,
        'fileName': fileName,
        'isRead': isRead,
        'attachmentUrl': attachmentUrl,
        'attachmentType': attachmentType,
        'isVoiceNote': isVoiceNote,
        'voiceDurationSeconds': voiceDurationSeconds,
        'senderId': senderId,
        'senderName': senderName,
        'isForwarded': isForwarded,
        'forwardedFromSenderName': forwardedFromSenderName,
        'replyToMessageId': replyToMessageId,
        'replyToText': replyToText,
        'replyToSenderName': replyToSenderName,
        'groupedAttachments':
            groupedAttachments.map((a) => a.toJson()).toList(),
        'mentions': mentions.map((m) => m.toJson()).toList(),
        'reactions': reactions.map((r) => r.toJson()).toList(),
        'seenBy': seenBy.map((s) => s.toJson()).toList(),
        'isEdited': isEdited,
        'editedAt': editedAt?.millisecondsSinceEpoch,
        'isDeleted': isDeleted,
        'deletedAt': deletedAt?.millisecondsSinceEpoch,
        'deletedBy': deletedBy,
        'isSystem': isSystem,
        'systemEvent': systemEvent,
      };

  static ChatMessage fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        text: json['text'],
        isMe: json['isMe'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
        apiMessageId: json['apiMessageId'],
        apiChatId: json['apiChatId'],
        filePath: json['filePath'],
        fileType: json['fileType'],
        fileName: json['fileName'],
        isRead: json['isRead'],
        attachmentUrl: json['attachmentUrl'],
        attachmentType: json['attachmentType'],
        isVoiceNote: AttachmentItem.parseVoiceNoteFlag(json['isVoiceNote']),
        voiceDurationSeconds:
            AttachmentItem.parseDurationSeconds(json['voiceDurationSeconds']),
        senderId: json['senderId'],
        senderName: json['senderName'],
        isForwarded: json['isForwarded'] == true,
        forwardedFromSenderName: json['forwardedFromSenderName'],
        replyToMessageId: json['replyToMessageId'],
        mentions: MessageMention.listFrom(json['mentions']),
        reactions: MessageReaction.listFrom(json['reactions']),
        seenBy: MessageSeen.listFrom(json['seenBy']),
        replyToText: json['replyToText'],
        replyToSenderName: json['replyToSenderName'],
        groupedAttachments: (json['groupedAttachments'] as List<dynamic>?)
                ?.map((e) => AttachmentItem.fromJson(e))
                .toList() ??
            [],
        isEdited: json['isEdited'] == true,
        isSystem: json['isSystem'] == true || json['isSystem'] == 1,
        systemEvent: json['systemEvent'],
        editedAt: json['editedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['editedAt']),
        isDeleted: json['isDeleted'] == true,
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['deletedAt']),
        deletedBy: json['deletedBy'],
      );

  /// Create ChatMessage from API response.
  ///
  /// A uuid alone does not identify a person: the same device id exists under
  /// both appTypes when one phone has both apps installed, so "mine" is the
  /// `(senderId, senderAppType)` pair — matching how mentions and reactions
  /// already compare identity.
  static ChatMessage fromApiResponse(
    Map<String, dynamic> json,
    String currentUserID, {
    int currentAppType = FirebaseApiService.appType,
  }) {
    final senderID = json['senderId'] ?? '';
    final senderAppType = ChatContact.parseAppType(
      json['senderAppType'],
      fallback: currentAppType,
    );
    final isMe = senderID == currentUserID && senderAppType == currentAppType;

    String? attachmentUrl;
    String? attachmentType;
    String? fileType;
    String? fileName;
    bool isVoiceNote = false;
    int? voiceDurationSeconds;

    final attachment = json['attachment'] as Map<String, dynamic>?;
    if (attachment != null) {
      attachmentUrl = attachment['url'] as String?;
      attachmentType = attachment['type'] as String?;
      fileName = attachment['filename'] as String?;
      // A clip recorded in the composer, which the backend tags so it can be
      // told apart from an audio file someone attached. `duration` is the
      // length the recorder measured and sent with the upload.
      isVoiceNote = AttachmentItem.parseVoiceNoteFlag(attachment['isVoiceNote']);
      voiceDurationSeconds =
          AttachmentItem.parseDurationSeconds(attachment['duration']);
      final mime = attachmentType ?? '';
      fileType = isVoiceNote
          ? 'voice'
          : mime.startsWith('image/')
              ? 'image'
              : 'document';
    }

    return ChatMessage(
      id: json['id'] ?? json['messageUuid'],
      text: json['text'] ?? '',
      isMe: isMe,
      timestamp: DateTime.parse(json['timestamp']).toLocal(),
      apiMessageId: json['messageUuid'],
      apiChatId: json['chatUuid'],
      isRead: json['read'] == 1,
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentType,
      isVoiceNote: isVoiceNote,
      voiceDurationSeconds: voiceDurationSeconds,
      fileType: fileType,
      fileName: fileName,
      senderId: senderID.toString().isEmpty ? null : senderID.toString(),
      senderName: json['senderName'] as String?,
      // The backend sends these as 1/0 on some rows and true/false on others.
      isForwarded: json['isForwarded'] == true || json['isForwarded'] == 1,
      forwardedFromSenderName: json['forwardedFromSenderName'] as String?,
      // Null on every message that is not a reply.
      replyToMessageId: json['replyToMessageId'] as String?,
      replyToText: json['replyToText'] as String?,
      replyToSenderName: json['replyToSenderName'] as String?,
      mentions: MessageMention.listFrom(json['mentions']),
      reactions: MessageReaction.listFrom(json['reactions']),
      seenBy: MessageSeen.listFrom(json['seenBy']),
      // As with isForwarded, this arrives as 1/0 on some rows.
      isEdited: json['isEdited'] == true || json['isEdited'] == 1,
      editedAt: _parseTimestamp(json['editedAt']),
      // Deleted for everyone. The row still comes back — `text` already holds
      // the backend's placeholder and `attachment` is withheld — so only the
      // flag is needed to render it as a tombstone.
      isDeleted: json['isDeleted'] == true || json['isDeleted'] == 1,
      deletedAt: _parseTimestamp(json['deletedAt']),
      deletedBy: json['deletedBy'] as String?,
      // Same 1/0-or-boolean tolerance. `systemEvent` names which change it
      // narrates (member_added, group_renamed, …); `text` is the sentence the
      // backend already phrased for display.
      isSystem: json['isSystem'] == true || json['isSystem'] == 1,
      systemEvent: json['systemEvent'] as String?,
    );
  }

  /// A nullable ISO timestamp from the API. A malformed one is treated as
  /// absent rather than taking out the whole message list.
  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  // ---------------------------------------------------------------------------
  // Group consecutive same-sender image messages (same upload batch) into a
  // single ChatMessage with groupedAttachments. Call after building the list.
  // ---------------------------------------------------------------------------
  static List<ChatMessage> groupImageMessages(List<ChatMessage> messages) {
    final result = <ChatMessage>[];
    int i = 0;

    while (i < messages.length) {
      final msg = messages[i];

      if (!msg.isSystem &&
          msg.fileType == 'image' &&
          msg.attachmentUrl != null) {
        final group = <AttachmentItem>[
          AttachmentItem(
            url: msg.attachmentUrl,
            fileName: msg.fileName,
            mimeType: msg.attachmentType,
            messageId: msg.apiMessageId,
          ),
        ];

        // Collect consecutive image msgs from same sender within 30 seconds
        int j = i + 1;
        while (j < messages.length) {
          final next = messages[j];
          final sameWindow =
              next.timestamp.difference(msg.timestamp).abs() <
                  const Duration(seconds: 30);
          if (!next.isSystem &&
              next.fileType == 'image' &&
              next.attachmentUrl != null &&
              next.isMe == msg.isMe &&
              sameWindow) {
            group.add(AttachmentItem(
              url: next.attachmentUrl,
              fileName: next.fileName,
              mimeType: next.attachmentType,
              messageId: next.apiMessageId,
            ));
            j++;
          } else {
            break;
          }
        }

        result.add(ChatMessage(
          id: msg.id,
          text: '',
          isMe: msg.isMe,
          timestamp: msg.timestamp,
          apiMessageId: msg.apiMessageId,
          apiChatId: msg.apiChatId,
          isRead: msg.isRead,
          senderId: msg.senderId,
          senderName: msg.senderName,
          isForwarded: msg.isForwarded,
          forwardedFromSenderName: msg.forwardedFromSenderName,
          replyToMessageId: msg.replyToMessageId,
          replyToText: msg.replyToText,
          replyToSenderName: msg.replyToSenderName,
          mentions: msg.mentions,
          reactions: msg.reactions,
          seenBy: msg.seenBy,
          isEdited: msg.isEdited,
          editedAt: msg.editedAt,
          groupedAttachments: group,
        ));
        i = j;
      } else {
        result.add(msg);
        i++;
      }
    }

    return result;
  }
}