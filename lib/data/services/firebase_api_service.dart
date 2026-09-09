import 'dart:convert';
import 'dart:io';
import 'package:ballys_reservation_app/models/chat_contact.dart';
import 'package:ballys_reservation_app/utils/device_id.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // needed for MediaType
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseApiService {
  //   static const String domain = 'https://ballysnotifications.onimtaitsl.com';
  //  static const String fmcDomain = 'https://ballysnotifications.onimtaitsl.com';
  // Chat backend host, picked from the logged-in property: Bellagio logins
  // (API url on bty.world) talk to the Bellagio chat server, everything else —
  // including Bally's — stays on the default host.
  static const String ballysDomain = 'https://chat.bcqr.lk';
  static const String bellagioDomain = 'https://chat.bty.world';

  /// Chat host for the currently logged-in property. Every request resolves
  /// this first so a re-login onto another property switches servers.
  static Future<String> resolveDomain() async {
    final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
    return apiUrl.contains('bty.world') ? bellagioDomain : ballysDomain;
  }

  static const Map<String, String> endpoints = {
    'InsertFcmToken': '/api/users/update-fcm-token',
    'InsertChatFMCToken': '/api/users/sync',
    'RemoveFcmToken': '/api/users/remove-fcm-token',
    'sendMessage': '/api/chat/send-message-with-notification',
    'deleteMessage': '/api/chats',
    'createChat': '/api/chats/create',
    'fetchUserChats': '/api/chats/user',
    'fetchAllUsers': '/api/users/contacts',
     'users': '/api/users', // base; full path: /api/users/{userUuid}/avatar
    'markAsRead': '/api/chats',
    'fetchMessages': '/api/chats',
    'deleteMessageForEveryone': '/api/chats', // base; full path: /api/chats/{chatId}/messages/{messageId}/soft-delete
    'deleteMessageForMe': '/api/chats', // base; full path: /api/chats/{chatId}/messages/{messageId}/delete-for-me
    'forwardMessage': '/api/chats', // base; full path: /api/chats/{chatId}/messages/{messageId}/forward
    'reactToMessage': '/api/chats', // base; full path: /api/chats/{chatId}/messages/{messageId}/react
    'uploadFiles': '/api/chats', // base; full path: /api/chats/{chatId}/upload/multiple
    'sendVoice': '/api/chats', // base; full path: /api/chats/{chatId}/voice
    'pinChat': '/api/chats', // base; full path: /api/chats/{chatId}/pin | /unpin
    'typing': '/api/chats', // base; full path: /api/chats/{chatId}/typing
    'createGroup': '/api/groups/create',
    'fetchUserGroups': '/api/groups/user',
    'groups': '/api/groups', // base; full path: /api/groups/{groupId}
  };

  /// appType of this app, sent alongside every user id the chat backend needs
  /// to disambiguate (the same user uuid can exist under another app).
  static const int appType = 2;

  // ---------------------------------------------------------------------------
  // Auth helpers
  // ---------------------------------------------------------------------------

  static Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('Token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('Token') ?? '';
  }

  // ---------------------------------------------------------------------------
  // Generic HTTP helpers
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> postRequest(
    String url,
    Map<String, dynamic> body,
  ) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {
          'success': false,
          'error': 'Server returned status code: ${response.statusCode}',
          'statusCode': response.statusCode,
          'responseBody': response.body,
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> putRequest(
    String url,
    Map<String, dynamic> body,
  ) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {
          'success': false,
          'error': 'Server returned status code: ${response.statusCode}',
          'statusCode': response.statusCode,
          'responseBody': response.body,
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getRequest(String url) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {
          'success': false,
          'error': 'Server returned status code: ${response.statusCode}',
          'statusCode': response.statusCode,
          'responseBody': response.body,
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteRequest(String url) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.delete(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {
          'success': false,
          'error': 'Server returned status code: ${response.statusCode}',
          'statusCode': response.statusCode,
          'responseBody': response.body,
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteRequestWithBody(
    String url,
    Map<String, dynamic> body,
  ) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.delete(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        return {
          'success': false,
          'error': 'Server returned status code: ${response.statusCode}',
          'statusCode': response.statusCode,
          'responseBody': response.body,
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------------
  // Upload files  (POST /api/chats/{chatId}/upload/multiple)
  // Accepts one or more local file paths. Returns list of uploaded file info:
  // [{ messageId, attachmentId, url, filename, size, type }, ...]
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> uploadFiles({
    required String chatId,
    required List<String> filePaths,
  }) async {
    try {
      final domain = await resolveDomain();
     
      final token = await _getToken();
      final deviceId = await DeviceId.get();
      final senderName = await StorageUtil.getChatUserName() ?? '';
print("Uploading files to chat $chatId with sender: $senderName and deviceId: $deviceId");
      final url =
          Uri.parse('$domain/api/chats/$chatId/upload/multiple');

      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['senderId'] = deviceId ?? ''
        ..fields['senderName'] = senderName
        ..fields['senderAppType'] = '2'; // Assuming appType is always 2 for this app


      for (final path in filePaths) {
        final file = File(path);
        if (!file.existsSync()) continue;

        // Determine MIME type from extension and pass it explicitly.
        // Without this the http package defaults to application/octet-stream
        // which the server rejects.
        final ext = path.split('.').last.toLowerCase();
        final mimeString = _mimeFromExtension(ext);
        final mimeParts = mimeString.split('/');
        final contentType = MediaType(mimeParts[0], mimeParts[1]);

        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            path,
            contentType: contentType,
          ),
        );
      }

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'error':
              'Upload failed with status: ${streamedResponse.statusCode}',
          'statusCode': streamedResponse.statusCode,
          'responseBody': responseBody,
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------------
  // Send a voice message  (POST /api/chats/{chatId}/voice)
  //
  // A recorded clip, as opposed to an audio file someone attached: the backend
  // tags the attachment `isVoiceNote` and stores [durationSeconds], so clients
  // render a voice bubble with a known length instead of a generic file card.
  // The server cannot read the length out of the file, so the recorder has to
  // measure it and pass it here.
  //
  // Returns { messageId, attachmentId, url, duration, size, type }.
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> sendVoiceMessage({
    required String chatId,
    required String filePath,
    required int durationSeconds,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return {'success': false, 'error': 'Recording not found'};
      }
      // The endpoint requires a positive whole number of seconds, so a clip
      // that rounded down to nothing still goes across as one second.
      final duration = durationSeconds < 1 ? 1 : durationSeconds;

      final domain = await resolveDomain();
      final token = await _getToken();
      final deviceId = await DeviceId.get();
      final senderName = await StorageUtil.getChatUserName() ?? '';

      final url = Uri.parse('$domain/api/chats/$chatId/voice');

      final ext = filePath.split('.').last.toLowerCase();
      final mimeParts = _mimeFromExtension(ext).split('/');

      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['senderId'] = deviceId ?? ''
        ..fields['senderName'] = senderName
        ..fields['senderAppType'] = '$appType'
        ..fields['duration'] = '$duration'
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            contentType: MediaType(mimeParts[0], mimeParts[1]),
          ),
        );

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        return {
          'success': true,
          'data': jsonDecode(responseBody) as Map<String, dynamic>,
        };
      }
      return {
        'success': false,
        'error':
            'Voice upload failed with status: ${streamedResponse.statusCode}',
        'statusCode': streamedResponse.statusCode,
        'responseBody': responseBody,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static String _mimeFromExtension(String ext) {
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
      // Recorder output and the audio files the chat accepts. m4a is what the
      // composer records; the rest cover a file picked from storage.
      'm4a': 'audio/m4a',
      'mp4a': 'audio/mp4',
      'aac': 'audio/aac',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'opus': 'audio/ogg',
      'amr': 'audio/amr',
      '3gp': 'audio/3gpp',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  // ---------------------------------------------------------------------------
  // Chat operations
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> markMessagesAsRead(
    String chatId,
    List<String> messageIds,
  ) async {
    try {
      print('markMessagesAsRead called with chatId: $chatId, messageIds: $messageIds');
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['markAsRead']}/$chatId/messages/read';
      return await putRequest(url, {
        'messageIds': messageIds,
        'userId': deviceId,
        'appType': 2, 
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Publishes whether we are typing in [chatId]. The backend does not put
  /// this on the REST API or push — it writes `chats/{chatId}/typing/{uuid}_{appType}`
  /// in Firestore, which the other participants watch live (see TypingService).
  ///
  /// [userName] only matters when starting; stopping deletes the doc.
  static Future<Map<String, dynamic>> setTyping({
    required String chatId,
    required bool isTyping,
    String? userName,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['typing']}/$chatId/typing';
      return await postRequest(url, {
        'userId': deviceId,
        'appType': appType,
        'isTyping': isTyping,
        if (isTyping && userName != null && userName.isNotEmpty)
          'userName': userName,
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> syncFmcToken(
    String name,
    String fcmToken,
  ) async {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final actualSalesCode = await StorageUtil.getSalesCode();
     final phoneNumber = await StorageUtil.getMobileNumber();
    final url = '$domain${endpoints['InsertChatFMCToken']}';
    final timestamp = DateTime.now().toIso8601String();
  final location = await StorageUtil.getCurrentLocation();
  print('Syncing FCM token with deviceId: $deviceId, name: $name, fcmToken: $fcmToken, salesCode: $actualSalesCode, phoneNumber: $phoneNumber, location: ${location?.code ?? "N/A"}');
    final response = await postRequest(url, {
      'id': deviceId,
      'name': name,
      'email': timestamp,
      'fcmToken': fcmToken,
      'appId': 2,
      'salesCode': actualSalesCode,
      'phoneNo':phoneNumber,
      'location': location?.code ?? "",
    });

    final prefs = await SharedPreferences.getInstance();
    final user = response['data']?['user'];
    if (user != null && user['name'] != null) {
      await prefs.setString('name', user['name']);
    }
    print('syncFmcToken response: $response');
    return response;
  }

  /// Detaches this device's FCM token from the backend on logout.
  ///
  /// Called instead of FirebaseMessaging.deleteToken(): dropping the row stops
  /// the pushes without invalidating the device registration, so the next
  /// login cannot pick a just-deleted token out of the SDK cache.
  ///
  /// Must run before StorageUtil.clearUserData() — it needs the auth token and
  /// the property's api url, both of which live in SharedPreferences.
  static Future<Map<String, dynamic>> removeFcmToken() async {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final url = '$domain${endpoints['RemoveFcmToken']}';
    final response = await postRequest(url, {
      'userId': deviceId,
      'appType': appType,
    });
    print('removeFcmToken response: $response');
    return response;
  }

  static Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('name');
  }

  /// Opens the 1:1 chat with [userUid], creating it when there is none.
  ///
  /// [userAppType] is the other person's app, which defaults to this one —
  /// the same uuid can exist under another appType, so identity is the
  /// `(userUuid, appType)` pair the participants carry.
  ///
  /// Returns `{'chatId': String?, 'error': String?}`. [createChat] drops the
  /// reason on the floor, which the chat list can live with — it falls back to
  /// the contact's own chatUuid and still opens the screen — but a caller that
  /// needs a real chatId to upload into has nothing to tell the user without
  /// it.
  static Future<Map<String, dynamic>> createChatDetailed(
    String userUid, {
    int? userAppType,
  }) async {
    try {
      final deviceId = await DeviceId.get();
      final domain = await resolveDomain();
      final url = '$domain${endpoints['createChat']}';
      // Participants are `{userUuid, appType}` objects, not bare ids — a list
      // of plain strings is rejected with "At least 2 participants (userUuid,
      // appType) required".
      final response = await postRequest(url, {
        "participants": [
          {'userUuid': userUid, 'appType': userAppType ?? appType},
          {'userUuid': deviceId, 'appType': appType},
        ],
      });

      if (response['success'] != true) {
        return {'chatId': null, 'error': errorTextFrom(response)};
      }

      final chatId = _chatIdFrom(response['data']);
      return (chatId == null || chatId.isEmpty)
          ? {'chatId': null, 'error': 'The chat could not be opened'}
          : {'chatId': chatId, 'error': null};
    } catch (e) {
      return {'chatId': null, 'error': e.toString()};
    }
  }

  static Future<String?> createChat(String userUid, {int? userAppType}) async =>
      (await createChatDetailed(userUid, userAppType: userAppType))['chatId']
          as String?;

  /// Digs the chat id out of a create-chat response. The id has come back at
  /// the top level and nested under `chat` / `data` depending on the backend
  /// build, so read whichever shape answers instead of assuming one.
  static String? _chatIdFrom(dynamic data) {
    if (data is! Map) return null;

    for (final key in const ['chatId', 'chatUuid', 'id', '_id']) {
      final value = data[key];
      if (value is String && value.isNotEmpty) return value;
    }
    for (final key in const ['chat', 'data', 'result']) {
      final nested = _chatIdFrom(data[key]);
      if (nested != null) return nested;
    }
    return null;
  }

  /// The server's own message for a failed request, so the UI can show why
  /// instead of a bare status code. Falls back to the transport error.
  static String errorTextFrom(Map<String, dynamic> response) {
    final body = response['responseBody'];
    if (body is String && body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final message = decoded['message'] ?? decoded['error'];
          if (message is String && message.isNotEmpty) return message;
        }
      } catch (_) {
        // Not JSON — fall through to the generic error below.
      }
    }
    return response['error']?.toString() ?? 'Unknown error';
  }

  /// Creates a group with the current user as creator/admin.
  ///
  /// [members] are the other participants — each entry needs the user's uuid
  /// and the appType they belong to, since the same uuid can exist on another
  /// app. Returns the new groupId, or null when the call fails.
  static Future<String?> createGroup({
    required String name,
    required List<ChatContact> members,
    String? avatarPath,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final token = await _getToken();
      final url = Uri.parse('$domain${endpoints['createGroup']}');

      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['name'] = name
        ..fields['creatorId'] = deviceId
        ..fields['creatorAppType'] = appType.toString()
        // members travels as a JSON-encoded array inside the form field.
        ..fields['members'] = jsonEncode(
          members
              .map((m) => {'userUuid': m.userUuid, 'appType': m.appType})
              .toList(),
        );

      if (avatarPath != null && avatarPath.isNotEmpty) {
        final file = File(avatarPath);
        if (file.existsSync()) {
          final ext = avatarPath.split('.').last.toLowerCase();
          final mimeParts = _mimeFromExtension(ext).split('/');
          request.files.add(
            await http.MultipartFile.fromPath(
              'avatar',
              avatarPath,
              contentType: MediaType(mimeParts[0], mimeParts[1]),
            ),
          );
        }
      }

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      print('createGroup response: ${streamedResponse.statusCode} $responseBody');

      if (streamedResponse.statusCode == 200 ||
          streamedResponse.statusCode == 201) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        if (data['success'] == true || data['groupId'] != null) {
          return data['groupId']?.toString();
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Groups the current user belongs to.
  static Future<List<Map<String, dynamic>>> fetchUserGroups() async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      if (deviceId.isEmpty) {
        throw Exception('deviceId not found in storage');
      }
      final url =
          '$domain${endpoints['fetchUserGroups']}/$deviceId?appType=$appType';
      final response = await getRequest(url);
      if (response['success'] == true) {
        final groups = response['data']?['groups'];
        if (groups is List) {
          return groups.whereType<Map<String, dynamic>>().toList();
        }
        return [];
      }
      throw Exception(response['error'] ?? 'Failed to fetch groups');
    } catch (e) {
      throw Exception('Failed to fetch groups: $e');
    }
  }

  /// Sends a message to a group. Group messaging reuses the chat message
  /// endpoint with the groupId standing in for the chatId.
  ///
  /// [chatId] is a groupId for a group and a chatId for a 1:1 conversation —
  /// the backend treats them the same, so this one call serves both.
  ///
  /// [replyToMessageId] quotes an existing message — it must belong to this
  /// same chat, or the backend answers 400. The server snapshots the quoted
  /// text and sender name onto the new message, so nothing else is sent.
  ///
  /// [mentionedUserIds] flags the people named with an @ in [text] — each entry
  /// is `{userUuid, appType}`, since the uuid alone does not identify a user
  /// across apps. Mostly a group feature, but the endpoint accepts it for 1:1
  /// chats too.
  static Future<Map<String, dynamic>> sendChatMessage({
    required String chatId,
    required String text,
    String? replyToMessageId,
    List<Map<String, dynamic>>? mentionedUserIds,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final senderName =
          await StorageUtil.getChatUserName() ?? await getName() ?? '';
      final url = '$domain${endpoints['fetchMessages']}/$chatId/messages';
      print("Sending chat message to $senderName with text: $text");
print('sendChatMessage called with chatId: $chatId, text: $text, replyToMessageId: $replyToMessageId, mentionedUserIds: $mentionedUserIds');
      return await postRequest(url, {
        'senderId': deviceId,
        'senderAppType': appType,
        'senderName': senderName,
        'text': text,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (mentionedUserIds != null && mentionedUserIds.isNotEmpty)
          'mentionedUserIds': mentionedUserIds,
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Renames a group and/or flips admin-only messaging. Admins only — only the
  /// fields passed here are sent, so the rest keep their current values.
  static Future<Map<String, dynamic>> updateGroupSettings({
    required String groupId,
    String? name,
    bool? adminOnlyMessaging,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['groups']}/$groupId/settings';
      return await patchRequest(url, {
        'requesterId': deviceId,
        'requesterAppType': appType,
        if (name != null) 'name': name,
        if (adminOnlyMessaging != null)
          'adminOnlyMessaging': adminOnlyMessaging,
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Replaces a group's avatar. Admins only.
  ///
  /// The backend uploads the image to Cloud Storage and stores the resulting
  /// public url on the group in one step, so nothing else needs calling after
  /// this. Returns the same {success, data|error} shape as the other group
  /// admin actions, with `avatarUrl` inside `data` on success.
  static Future<Map<String, dynamic>> updateGroupAvatar({
    required String groupId,
    required String avatarPath,
  }) async {
    try {
      print('updateGroupAvatar called with groupId: $groupId, avatarPath: $avatarPath');
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final token = await _getToken();
      final url = Uri.parse('$domain${endpoints['groups']}/$groupId/avatar');

      final file = File(avatarPath);
      if (!file.existsSync()) {
        return {'success': false, 'error': 'Image file not found'};
      }

      final ext = avatarPath.split('.').last.toLowerCase();
      final mimeParts = _mimeFromExtension(ext).split('/');

      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['requesterId'] = deviceId
        ..fields['requesterAppType'] = appType.toString()
        ..files.add(
          await http.MultipartFile.fromPath(
            'avatar',
            avatarPath,
            contentType: MediaType(mimeParts[0], mimeParts[1]),
          ),
        );

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200 ||
          streamedResponse.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(responseBody)};
      }
      return {
        'success': false,
        'error': 'Server returned status code: ${streamedResponse.statusCode}',
        'statusCode': streamedResponse.statusCode,
        'responseBody': responseBody,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Uploads the signed-in user's chat profile picture.
  /// POST /api/users/{userUuid}/avatar — multipart with the appType field and
  /// the image under `avatar`.
  ///
  /// Like the group avatar endpoint the backend stores the image and returns
  /// the resulting public url, so nothing else needs calling afterwards.
  /// `userUuid` defaults to this device's id, which is what identifies the
  /// logged-in user everywhere else in the chat api.
  static Future<Map<String, dynamic>> updateUserAvatar({
    required String avatarPath,
    String? userUuid,
  }) async {
    try {
      final domain = await resolveDomain();
      final token = await _getToken();
      final uuid = userUuid ?? await DeviceId.get();
      final url = Uri.parse('$domain${endpoints['users']}/$uuid/avatar');

      final file = File(avatarPath);
      if (!file.existsSync()) {
        return {'success': false, 'error': 'Image file not found'};
      }

      final ext = avatarPath.split('.').last.toLowerCase();
      final mimeParts = _mimeFromExtension(ext).split('/');

      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['appType'] = appType.toString()
        ..files.add(
          await http.MultipartFile.fromPath(
            'avatar',
            avatarPath,
            contentType: MediaType(mimeParts[0], mimeParts[1]),
          ),
        );

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
print('updateUserAvatar response: ${streamedResponse.statusCode} $responseBody');
      if (streamedResponse.statusCode == 200 ||
          streamedResponse.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(responseBody)};
      }
      return {
        'success': false,
        'error': 'Server returned status code: ${streamedResponse.statusCode}',
        'statusCode': streamedResponse.statusCode,
        'responseBody': responseBody,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Reads a chat user's profile — `name`, `profileImageUrl`, `phoneNo` and
  /// the rest of the record the chat backend keeps.
  /// GET /api/users/{userUuid}?appType=2, defaulting to the signed-in user.
  ///
  /// Returns the `user` object out of the response, or null when the lookup
  /// fails so callers can keep showing whatever they had cached.
  static Future<Map<String, dynamic>?> fetchUserProfile({
    String? userUuid,
  }) async {
    try {
      final domain = await resolveDomain();
      final uuid = userUuid ?? await DeviceId.get();
      final url = '$domain${endpoints['users']}/$uuid?appType=$appType';
      final result = await getRequest(url);

      if (result['success'] == true) {
        final data = result['data'];
        if (data is Map && data['user'] is Map) {
          return Map<String, dynamic>.from(data['user'] as Map);
        }
      }
      print('fetchUserProfile failed: $result');
      return null;
    } catch (e) {
      print('fetchUserProfile exception: $e');
      return null;
    }
  }

  /// Adds members to a group. Admins only. Users already in the group are
  /// silently skipped by the backend.
  static Future<Map<String, dynamic>> addGroupMembers({
    required String groupId,
    required List<Map<String, dynamic>> members,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['groups']}/$groupId/members';
      return await postRequest(url, {
        'requesterId': deviceId,
        'requesterAppType': appType,
        'members': members,
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Removes someone else from a group. Admins only — leaving is a separate
  /// endpoint and cannot be done through this one.
  static Future<Map<String, dynamic>> removeGroupMember({
    required String groupId,
    required String userUuid,
    required int memberAppType,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url =
          '$domain${endpoints['groups']}/$groupId/members/$userUuid?appType=$memberAppType';
      return await deleteRequestWithBody(url, {
        'requesterId': deviceId,
        'requesterAppType': appType,
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Promotes a member to admin. Admins only.
  static Future<Map<String, dynamic>> promoteGroupAdmin({
    required String groupId,
    required String targetUserId,
    required int targetAppType,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['groups']}/$groupId/admins';
      return await postRequest(url, {
        'requesterId': deviceId,
        'requesterAppType': appType,
        'targetUserId': targetUserId,
        'targetAppType': targetAppType,
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Demotes an admin back to member. Admins only, and the backend rejects
  /// demoting the last remaining admin.
  static Future<Map<String, dynamic>> demoteGroupAdmin({
    required String groupId,
    required String userUuid,
    required int memberAppType,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url =
          '$domain${endpoints['groups']}/$groupId/admins/$userUuid?appType=$memberAppType';
      return await deleteRequestWithBody(url, {
        'requesterId': deviceId,
        'requesterAppType': appType,
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Leaves a group. Rejected for the sole admin while other members remain.
  static Future<Map<String, dynamic>> leaveGroup(String groupId) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['groups']}/$groupId/leave';
      return await postRequest(url, {'userId': deviceId, 'appType': appType});
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Deletes a group along with its messages and attachments. Creator only.
  static Future<Map<String, dynamic>> deleteGroup(String groupId) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['groups']}/$groupId';
      return await deleteRequestWithBody(url, {
        'requesterId': deviceId,
        'requesterAppType': appType,
      });
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Full details for one group, including its member list and their roles.
  static Future<Map<String, dynamic>> fetchGroupDetails(String groupId) async {
    try {
      final domain = await resolveDomain();
      final url = '$domain${endpoints['groups']}/$groupId';
      final response = await getRequest(url);
      if (response['success'] == true) {
        final group = response['data']?['group'];
        if (group is Map<String, dynamic>) return group;
        throw Exception('Group not found');
      }
      throw Exception(response['error'] ?? 'Failed to fetch group details');
    } catch (e) {
      throw Exception('Failed to fetch group details: $e');
    }
  }

  static Future<bool> deleteChat(String chatId) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['deleteMessage']}/$chatId/hide';
      final response = await postRequest(url, {'userId': deviceId, 'appType': 2});
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> fetchUserChats() async {
    try {
      print('fetchUserChats called');
      final domain = await resolveDomain();
      print('Resolved domain: $domain');
      final deviceId = await DeviceId.get();
      final location = await StorageUtil.getCurrentLocation();
      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('deviceId not found in storage');
      }
      final url = '$domain${endpoints['fetchUserChats']}/$deviceId?location=${location?.code}&appType=2';
      print('Fetching chats for deviceId: $url');
      final response = await getRequest(url);
      if (response['success'] == true) {
        print('Fetch chats response: ${response['data']}');
        return response['data'] ?? {};
      } else {
        throw Exception(response['error'] ?? 'Failed to fetch chats');
      }
    } catch (e) {
      throw Exception('Failed to fetch chats: $e');
    }
  }

  static Future<Map<String, dynamic>> fetchAllUsers() async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final location = await StorageUtil.getCurrentLocation();
      final url = '$domain${endpoints['fetchAllUsers']}/$deviceId?location=${location?.code}&appType=2';
    print('Fetching users from URL: $url');
      final response = await getRequest(url);
      print('Fetch users response: $response');
      if (response['success'] == true) {
        return response['data'] ?? {};
      } else {
        throw Exception(response['error'] ?? 'Failed to fetch users');
      }
    } catch (e) {
      throw Exception('Failed to fetch users: $e');
    }
  }

  /// One page of a chat's messages, minus the ones this user deleted for
  /// themselves — the backend only applies that filtering when it is told who
  /// is asking, hence the `userId`/`appType` query params.
  ///
  /// The endpoint is paginated: it answers with the [limit] most recent
  /// messages (server default 50, capped at 100) and, in `hasMore` and
  /// `nextCursor`, whether there is older history behind them. Pass that
  /// cursor back as [before] to fetch the page older than the one it came
  /// from; omit it for the most recent messages. Within a page the messages
  /// are still ordered oldest → newest.
  ///
  /// [before] is an opaque server id — it is passed through unchanged and
  /// must not be derived from a messageUuid or a timestamp.
  static Future<Map<String, dynamic>> fetchMessages(
    String chatId, {
    int? limit,
    int? before,
  }) async {
    try {
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['fetchMessages']}/$chatId/messages'
          '?userId=${Uri.encodeQueryComponent(deviceId)}'
          '&appType=$appType'
          '${limit == null ? '' : '&limit=$limit'}'
          '${before == null ? '' : '&before=$before'}';
      print("rrrr, $url");
      final response =
          await getRequest(url).timeout(const Duration(seconds: 10));
      return response;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> sendMessage({
    required String recipientUuid,
    required String message,
    required String title,
    required String body,
    required String chatId,
    int recipientAppType = 1,
  }) async {
    try {
      print(
          'sendMessage called with recipientUuid: $recipientUuid,recipientUuid: $title, chatId: $chatId, message: $message ,recipientAppType: $recipientAppType');
      final domain = await resolveDomain();
      final deviceId = await DeviceId.get();
      final url = '$domain${endpoints['sendMessage']}';
      print('sendMessage URL: $url');
      final response = await postRequest(url, {
        "senderUuid": deviceId,
        "recipientUuid": recipientUuid,
        "message": message,
        "title": title,
        "body": body,
        "chatId": chatId,
        "senderAppType": 2,
        "recipientAppType": recipientAppType,
      });
      print('sendMessage response: $response');
      return response;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

/// Deletes a message for everyone — WhatsApp's "delete for everyone".
///
/// Sender only (the backend answers 403 for anyone else), and it is a soft
/// delete: the message stays in the conversation and keeps coming back from
/// [fetchMessages], but with its real text replaced by a placeholder, its
/// attachment withheld and `isDeleted: true` set, so the thread shows a
/// tombstone instead of a gap. Reactions, mentions and seen-by are left as
/// they were, and the chat list skips past it when picking a preview.
///
/// Recoverable with [restoreMessage] — the real content is still on the
/// server.
static Future<Map<String, dynamic>> deleteMessageForEveryone(
  String chatId,
  String messageId,
) async {
  try {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final url = '$domain/api/chats/$chatId/messages/$messageId/soft-delete';
    final body = {'userId': deviceId, 'appType': appType};

    _logLong('deleteMessageForEveryone ▶ PATCH $url');
    _logLong('deleteMessageForEveryone ▶ body: ${jsonEncode(body)}');

    final result = await patchRequest(url, body);

    _logLong('deleteMessageForEveryone ◀ response: ${jsonEncode(result)}');
    return result;
  } catch (e) {
    print('deleteMessageForEveryone ✖ exception: $e');
    return {'success': false, 'error': e.toString()};
  }
}

/// Hides a message from this user's own view — WhatsApp's "delete for me".
///
/// Unlike [deleteMessageForEveryone] this is open to any participant on any
/// message, including one somebody else sent and one already deleted for
/// everyone: nothing changes for the other participants, the message simply
/// stops being returned by [fetchMessages] for this caller (which is why that
/// call passes `userId`/`appType`). Idempotent, and there is no undo — the
/// same rules WhatsApp applies.
static Future<Map<String, dynamic>> deleteMessageForMe(
  String chatId,
  String messageId,
) async {
  try {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final url = '$domain/api/chats/$chatId/messages/$messageId/delete-for-me';
    final body = {'userId': deviceId, 'appType': appType};

    _logLong('deleteMessageForMe ▶ POST $url');
    _logLong('deleteMessageForMe ▶ body: ${jsonEncode(body)}');

    final result = await postRequest(url, body);

    _logLong('deleteMessageForMe ◀ response: ${jsonEncode(result)}');
    return result;
  } catch (e) {
    print('deleteMessageForMe ✖ exception: $e');
    return {'success': false, 'error': e.toString()};
  }
}

/// Undoes a [deleteMessageForEveryone], putting the real text and attachment
/// back. Allowed for the sender or whoever deleted it.
static Future<Map<String, dynamic>> restoreMessage(
  String chatId,
  String messageId,
) async {
  try {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final url = '$domain/api/chats/$chatId/messages/$messageId/restore';
    final body = {'userId': deviceId, 'appType': appType};

    _logLong('restoreMessage ▶ PATCH $url');
    _logLong('restoreMessage ▶ body: ${jsonEncode(body)}');

    final result = await patchRequest(url, body);

    _logLong('restoreMessage ◀ response: ${jsonEncode(result)}');
    return result;
  } catch (e) {
    print('restoreMessage ✖ exception: $e');
    return {'success': false, 'error': e.toString()};
  }
}

/// Forwards one message into other chats/groups and/or straight to users.
///
/// [chatId]/[messageId] identify the message being forwarded. Targets are
/// given as either (or both) of:
///  * [targetChatIds] — chats or groups the user is already a participant of.
///  * [targetUsers] — `{userUuid, appType}` pairs; the backend finds or
///    creates the 1:1 chat with that person, so they need not be messaged
///    before.
///
/// Best-effort per target: the response carries a `results` list where each
/// entry reports its own success/error, so one rejected target (not a
/// participant, admin-only group, forwarding back into the source chat) does
/// not stop the rest.
static Future<Map<String, dynamic>> forwardMessage({
  required String chatId,
  required String messageId,
  List<String> targetChatIds = const [],
  List<Map<String, dynamic>> targetUsers = const [],
}) async {
  try {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final senderName = await StorageUtil.getChatUserName() ?? await getName() ?? '';
    final url = '$domain/api/chats/$chatId/messages/$messageId/forward';
    final body = {
      'userId': deviceId,
      'appType': appType,
      'senderName': senderName,
      if (targetChatIds.isNotEmpty) 'targetChatIds': targetChatIds,
      if (targetUsers.isNotEmpty) 'targetUserIds': targetUsers,
    };
    _logLong('forwardMessage ▶ POST $url');
    _logLong('forwardMessage ▶ body: ${jsonEncode(body)}');

    final result = await postRequest(url, body);

    _logLong('forwardMessage ◀ response: ${jsonEncode(result)}');
    return result;
  } catch (e) {
    print('forwardMessage ✖ exception: $e');
    return {'success': false, 'error': e.toString()};
  }
}

/// Pins or unpins a conversation for this user, WhatsApp style.
///
/// The same pair of endpoints covers 1:1 chats and groups — a group is
/// addressed by its groupId, which is also its chatId. Both are idempotent:
/// pinning an already pinned chat answers 200 without changing `pinnedAt`.
/// The pin is per-user, so it never moves the row for anyone else, and it
/// comes back on the list payloads as `isPinned`/`pinnedAt`.
static Future<Map<String, dynamic>> setChatPinned({
  required String chatId,
  required bool pinned,
}) async {
  try {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final url = '$domain/api/chats/$chatId/${pinned ? 'pin' : 'unpin'}';
    final body = {'userId': deviceId, 'appType': appType};

    _logLong('setChatPinned ▶ POST $url');
    _logLong('setChatPinned ▶ body: ${jsonEncode(body)}');

    final result = await postRequest(url, body);

    _logLong('setChatPinned ◀ response: ${jsonEncode(result)}');
    return result;
  } catch (e) {
    print('setChatPinned ✖ exception: $e');
    return {'success': false, 'error': e.toString()};
  }
}

/// print() drops very long lines on some platforms, so long payloads are
/// emitted in chunks that survive the terminal.
static void _logLong(String message, {int chunkSize = 800}) {
  for (var i = 0; i < message.length; i += chunkSize) {
    final end = (i + chunkSize < message.length) ? i + chunkSize : message.length;
    print(message.substring(i, end));
  }
}

/// Adds, changes or removes this user's emoji reaction on a message.
///
/// The backend keeps at most one reaction per user per message, so this one
/// endpoint covers all three cases: sending the emoji they already have
/// removes it, a different one replaces it. The response carries
/// `reacted: true` when a reaction was added or changed and `reacted: false`
/// when it was removed. Reacting to a deleted message is rejected with 400.
static Future<Map<String, dynamic>> reactToMessage({
  required String chatId,
  required String messageId,
  required String emoji,
}) async {
  try {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final url = '$domain/api/chats/$chatId/messages/$messageId/react';
    final body = {
      'userId': deviceId,
      'appType': appType,
      'emoji': emoji,
    };
    _logLong('reactToMessage ▶ POST $url');
    _logLong('reactToMessage ▶ body: ${jsonEncode(body)}');

    final result = await postRequest(url, body);

    _logLong('reactToMessage ◀ response: ${jsonEncode(result)}');
    return result;
  } catch (e) {
    print('reactToMessage ✖ exception: $e');
    return {'success': false, 'error': e.toString()};
  }
}

/// Rewrites the text of a message the user sent.
///
/// Sender only — the backend answers 403 for anyone else — and only within
/// 15 minutes of sending (ChatMessage.editWindow); a later attempt, or an
/// edit of a deleted message, comes back 400. The message is stamped `isEdited` and
/// `editedAt`, the chat's last-message preview is refreshed when this was the
/// latest one, and the other participants get a silent `message_edited` ping
/// so their cached copy can be refetched.
static Future<Map<String, dynamic>> editMessage({
  required String chatId,
  required String messageId,
  required String text,
}) async {
  try {
    final domain = await resolveDomain();
    final deviceId = await DeviceId.get();
    final url = '$domain/api/chats/$chatId/messages/$messageId/edit';
    final body = {
      'userId': deviceId,
      'appType': appType,
      'text': text,
    };
    _logLong('editMessage ▶ PATCH $url');
    _logLong('editMessage ▶ body: ${jsonEncode(body)}');

    final result = await patchRequest(url, body);

    _logLong('editMessage ◀ response: ${jsonEncode(result)}');
    return result;
  } catch (e) {
    print('editMessage ✖ exception: $e');
    return {'success': false, 'error': e.toString()};
  }
}

static Future<Map<String, dynamic>> patchRequest(
  String url,
  Map<String, dynamic> body,
) async {
  try {
    final headers = await getAuthHeaders();
    final response = await http.patch(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return {'success': true, 'data': jsonDecode(response.body)};
    } else {
      return {
        'success': false,
        'error': 'Server returned status code: ${response.statusCode}',
        'statusCode': response.statusCode,
        'responseBody': response.body,
      };
    }
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}
}