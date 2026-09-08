import 'package:ballys_reservation_app/core/chat_colors.dart';
import 'package:ballys_reservation_app/components/badge_service.dart';
import 'package:ballys_reservation_app/components/contact_picker.dart';
import 'package:ballys_reservation_app/components/group_avatar.dart';
import 'package:ballys_reservation_app/components/user_avatar.dart';
import 'package:ballys_reservation_app/components/group_details_sheet.dart';
import 'package:ballys_reservation_app/components/notification_banner.dart';
import 'package:ballys_reservation_app/data/services/firebase_api_service.dart';
import 'package:ballys_reservation_app/data/services/notification_store.dart';
import 'package:ballys_reservation_app/data/services/typing_service.dart';
import 'package:ballys_reservation_app/models/chat_contact.dart';
import 'package:ballys_reservation_app/models/chat_group.dart';
import 'package:ballys_reservation_app/providers/chat_font_settings_provider.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/providers/guest_booking_provider.dart';
import 'package:ballys_reservation_app/screens/chatDetail_screen.dart';
import 'package:ballys_reservation_app/screens/chat_settings_screen.dart';
import 'package:ballys_reservation_app/screens/new_chat_screen.dart';
import 'package:ballys_reservation_app/screens/new_group_screen.dart';
import 'package:ballys_reservation_app/screens/profile/chat_profile_screen.dart';
import 'package:ballys_reservation_app/utils/chat_text_format.dart';
import 'package:ballys_reservation_app/utils/badge_sync_helper.dart';
import 'package:ballys_reservation_app/utils/device_id.dart';
import 'package:ballys_reservation_app/utils/mention_tracker.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:flutter/material.dart';
import 'package:ballys_reservation_app/components/watermark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Row tint for a long-pressed chat or group row. WhatsApp washes the whole
/// row edge to edge instead of lifting a rounded card out of the list, so the
/// selected row is a flat full-width block of colour.
const Color _kChatSelectionColor = Color(0xFFE8F5E9);

class ChatScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? notificationData;
  const ChatScreen({super.key, this.notificationData});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver,ConnectivityMixin {
  late TabController _tabController;

  /// Marks a point inside [ChatFontScope], so sheets and dialogs opened from
  /// here inherit the chat font instead of the app-wide one — they get their
  /// own route, and only the themes above the context they are given travel
  /// with them.
  final GlobalKey _chatScopeKey = GlobalKey();
  BuildContext get _chatModalContext => _chatScopeKey.currentContext ?? context;
  List<ChatContact> _contacts = [];
  List<ChatContact> _filteredContacts = [];
  List<ChatContact> _allUsers = [];
  List<ChatGroup> _groups = [];
  // Ids of every known group, used to keep group conversations out of the
  // 1:1 chat tabs.
  Set<String> _groupIds = {};
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isLoadingGroups = false;
  String? _groupsErrorMessage;
  String? _errorMessage;
  String? _currentUserName;
  String? _currentUserUuid;
  /// Signed-in user's chat profile picture, straight from
  /// GET /api/users/{uuid}. Null until it loads, or when none is set.
  String? _myAvatarUrl;
  String? _selectedContactId;
  bool _hasProcessedNotification = false;

  /// How many conversations can be pinned at once, matching WhatsApp.
  static const int _maxPinnedChats = 3;

  /// appType of the Premier Rewards app. A chat whose other participant
  /// carries it is a member chat rather than a staff one.
  static const int _rewardsAppType = 1;

  /// Position of the Rewards tab in [_tabController].
  static const int _rewardsTabIndex = 4;

  /// Guards [_refreshGroupMentions]: chats and groups both trigger it, and the
  /// two refreshes often land together.
  bool _isScanningMentions = false;

  // Add message subscription
  StreamSubscription<RemoteMessage>? _messageSubscription;

  /// One Firestore typing listener per conversation on screen, so a row can
  /// say "typing…" in place of its last message the way WhatsApp does.
  final MultiChatTypingWatcher _typingWatcher = MultiChatTypingWatcher(
    maxChats: 40,
  );
  StreamSubscription<void>? _typingChanges;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 5, vsync: this);
    _initializeData();
    _setupNotificationListener();
    _syncBadgeCount();
    // Which chats are watched is decided in build; this only redraws the
    // rows when one of them starts or stops.
    _typingChanges = _typingWatcher.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A notification tap while this screen is already open re-runs the route
    // builder with fresh `extra` on the same state — initState never fires
    // again, so the tap has to be picked up here or it goes nowhere.
    if (!identical(widget.notificationData, oldWidget.notificationData)) {
      _hasProcessedNotification = false;
      _checkAndOpenNotificationChat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _messageSubscription?.cancel();
    _typingChanges?.cancel();
    _typingWatcher.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // Refresh when app comes to foreground
      _fetchChatsFromApi();
      BadgeService().clearBadge();
    } else if (state == AppLifecycleState.paused) {
      // Update badge when app goes to background
      final unreadCount = _getTotalUnreadCount();
      BadgeService().updateBadge(unreadCount);
    }
  }

  int _getTotalUnreadCount() {
    return _contacts.fold(0, (sum, contact) => sum + contact.unreadCount);
  }

  Future<void> _syncBadgeCount() async {
    try {
      final unreadCount = _getTotalUnreadCount();
      await BadgeService().updateBadge(unreadCount);
    
      // Then sync with server for accuracy
      await BadgeSyncHelper.syncBadgeWithServer();
    } catch (e) {

    }
  }
Future<void> _reloadGuestBookings() async {
  try {
    final container = ProviderScope.containerOf(context);
    await container.read(guestBookingProvider.notifier).getAllBookings();
  } catch (e) {
    print('Error reloading guest bookings: $e');
  }
}
//   void _setupNotificationListener() {
//   _messageSubscription = FirebaseMessaging.onMessage.listen((
//     RemoteMessage message,
//   ) {
//     if (message.data['msg_type'] == '35') {
//       _reloadGuestBookings();
//       return;
//     }

//     // Extract chatId from Details field as well
//     String? chatId = message.data['chatId'] ?? message.data['chat_id'];
//     final detailsJson = message.data['Details'];
//     if ((chatId == null || chatId.isEmpty) && detailsJson != null) {
//       try {
//         final details = jsonDecode(detailsJson);
//         chatId = details['chatId']?.toString();
//       } catch (_) {}
//     }

//     if (message.data['msg_type'] == '11' ||
//         message.data['type'] == 'chat' ||
//         message.data.containsKey('Details') ||
//         chatId != null) {
//       _fetchChatsFromApiSilently();
//     }
//   });
// }
  void _setupNotificationListener() {
    // Listen for foreground messages
    _messageSubscription = FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {
      
if (message.data['msg_type'] == '35') {
      _reloadGuestBookings();
      return;
    }
      // An edit rewrites the chat's last-message preview, so the list is
      // pulled again even though nothing new was said.
      if (NotificationStore.isSilentThreadUpdate(message)) {
        _fetchChatsFromApiSilently();
        return;
      }
      // Check if it's a chat notification
      if (message.data['msg_type'] == '11' ||
          message.data['type'] == 'chat' ||
          message.data.containsKey('Details')) {
        // Refresh silently without showing loading indicator
        _fetchChatsFromApiSilently();
      }
    });
  }
  // Silent refresh - no loading indicator
  Future<void> _fetchChatsFromApiSilently() async {
    try {
      final chatData = await FirebaseApiService.fetchUserChats();
      final userData = await FirebaseApiService.fetchAllUsers();

      if (chatData['chats'] != null) {
        final List<dynamic> chats = chatData['chats'];

        final String userIdentifier = await _resolveCurrentUserId();

        Map<String, dynamic> userDetailsMap = {};
        if (userData['users'] != null) {
          final List<dynamic> users = userData['users'];
          for (var user in users) {
            final userName = user['name'] ?? user['id'] ?? '';
            userDetailsMap[userName] = user;
          }
        }

        setState(() {
          _contacts = chats
              .map(
                (chat) => ChatContact.fromChatApiJson(
                  chat,
                  userIdentifier,
                  currentUserName: _currentUserName,
                  participantDetails: userDetailsMap,
                ),
              )
              .toList();
          _filteredContacts = List.from(_contacts);
        });

        await _saveChats();
        // Update badge with total unread count
        final unreadCount = _getTotalUnreadCount();
        await BadgeService().updateBadge(unreadCount);
        // Unread counts drive the "@" marker, so re-check it here too.
        unawaited(_refreshGroupMentions());
      }
      // Group tiles read their last-message preview from _groups, not
      // _contacts, so it must be refreshed here too or it goes stale.
      await _fetchGroupsSilently();
    } catch (e) {

    }
  }

  // Same as _fetchGroups but without the loading indicator, for push refreshes.
  Future<void> _fetchGroupsSilently() async {
    try {
      final groups = await FirebaseApiService.fetchUserGroups();

      if (!mounted) return;
      final parsed = groups.map(ChatGroup.fromApiJson).toList();
      setState(() {
        _groups = parsed;
        _groupIds = {
          for (final g in parsed) ...[g.groupId, g.id],
        }..removeWhere((id) => id.isEmpty);
      });
    } catch (e) {
      // Silent refresh: ignore errors, next manual refresh will retry.
    }
  }

  Future<void> _initializeData() async {
    await _getName();
    await _fetchChatsFromApi();
    await _fetchGroups();
    _checkAndOpenNotificationChat();
    // Sync badge after fetching chats
    await _syncBadgeCount();
  }

  void _checkAndOpenNotificationChat() {
    if (_hasProcessedNotification) return;

    if (widget.notificationData != null &&
        widget.notificationData!['openChat'] == true) {
      final chatId = widget.notificationData!['chatId'] as String?;
      final senderName = widget.notificationData!['senderName'] as String?;
      final senderId = widget.notificationData!['senderId'] as String?;
      // Group pushes carry action == 'group_message'; the chatId is the group
      // id, not a 1:1 chat.
      final action = widget.notificationData!['action']?.toString();

      if (chatId != null && chatId.isNotEmpty) {
        _hasProcessedNotification = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openSpecificChat(
            chatId,
            senderName,
            senderId,
            isGroup: action == 'group_message',
          );
        });
      }
    }
  }

  ChatGroup? _groupForId(String chatId) => _groups.cast<ChatGroup?>().firstWhere(
        (group) => group?.groupId == chatId || group?.id == chatId,
        orElse: () => null,
      );

  void _openSpecificChat(
    String chatId,
    String? senderName,
    String? senderId, {
    bool isGroup = false,
  }) {
    // Groups live in their own list, so resolve them first. Otherwise the
    // senderName fallback below would open a 1:1 chat with whoever posted in
    // the group instead of the group itself.
    final group = _groupForId(chatId);
    if (group != null) {
      _openGroupChat(group);
      return;
    }

    if (isGroup) {
      // The group isn't in the cached list yet (just created/added). Refetch
      // and retry once rather than falling through to the personal-chat match.
      _fetchGroups().then((_) {
        if (!mounted) return;
        final refreshed = _groupForId(chatId);
        if (refreshed != null) {
          _openGroupChat(refreshed);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Group chat not found.'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
      return;
    }

    ChatContact? targetContact = _contacts.cast<ChatContact?>().firstWhere(
      (contact) => contact?.chatUuid == chatId,
      orElse: () => null,
    );

    if (targetContact == null && senderName != null) {
      targetContact = _contacts.cast<ChatContact?>().firstWhere(
        (contact) =>
            contact?.name.toLowerCase().contains(senderName.toLowerCase()) ==
                true ||
            contact?.firstName.toLowerCase().contains(
                  senderName.toLowerCase(),
                ) ==
                true,
        orElse: () => null,
      );
    }

    if (targetContact != null) {

      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (context) => IndividualChatScreen(
                contact: targetContact!,
                onMessageSent: (String lastMessage) {
                  _updateContactLastMessage(targetContact!.id, lastMessage);
                },
              ),
            ),
          )
          .then((_) {
            _refreshChatsAndGroups();
          });
    } else {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            senderName != null
                ? 'Chat with $senderName not found. Refreshing...'
                : 'Chat not found. Refreshing...',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );

      _fetchChatsFromApi().then((_) {
        if (!mounted) return;
        if (_contacts.isNotEmpty) {
          final refreshedContact = _contacts.cast<ChatContact?>().firstWhere(
            (contact) =>
                contact?.chatUuid == chatId ||
                (senderName != null &&
                    contact?.name.toLowerCase().contains(
                          senderName.toLowerCase(),
                        ) ==
                        true),
            orElse: () => null,
          );

          if (refreshedContact != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    IndividualChatScreen(contact: refreshedContact!),
              ),
            );
          }
        }
      });
    }
  }

  Future<void> _getName() async {
    // The chat backend keys users by device id, so keep it around to spot
    // "you" in member lists. Resolve it first and on its own: it is the only
    // reliable identifier, and a failing name lookup used to leave it null.
    await _resolveCurrentUserId();

    try {
      final userName = await FirebaseApiService.getName();
      if (!mounted) return;
      setState(() {
        _currentUserName = userName;
      });
    } catch (e) {

    }

    // The cached name is only a fallback: the chat backend holds the display
    // name and the avatar the other participants actually see.
    await _loadMyProfile();
  }

  /// Pulls the signed-in user's chat profile so the header can show the name
  /// and photo the backend has, and so a fresh upload shows up straight away.
  Future<void> _loadMyProfile() async {
    try {
      final profile = await FirebaseApiService.fetchUserProfile(
        userUuid: await _resolveCurrentUserId(),
      );
      if (profile == null || !mounted) return;

      final name = profile['name']?.toString();
      final avatar = profile['profileImageUrl']?.toString();
      setState(() {
        if (name != null && name.isNotEmpty) _currentUserName = name;
        _myAvatarUrl = (avatar == null || avatar.isEmpty) ? null : avatar;
      });
    } catch (e) {
      print('_loadMyProfile error: $e');
    }
  }

  /// Returns the device id the chat backend stores this user under.
  ///
  /// A push can trigger a refresh before [_getName] has run, and an identifier
  /// that matches no participant makes every row fall back to the first
  /// participant — often the current user,  so the row showed the user's own
  /// name until a re-login refreshed the cache.
  Future<String> _resolveCurrentUserId() async {
    final cached = _currentUserUuid;
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final deviceId = await DeviceId.get();
      if (mounted) {
        setState(() {
          _currentUserUuid = deviceId;
        });
      } else {
        _currentUserUuid = deviceId;
      }
      return deviceId;
    } catch (e) {
      return '';
    }
  }

  void _showDeleteConfirmation(ChatContact contact) {
    final fontSettings = ref.read(chatFontSettingsProvider);

    showDialog(
      context: _chatModalContext,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Delete Chat',
            style: TextStyle(
              fontSize: fontSettings.fontSize + 2,
              fontWeight: fontSettings.fontWeight,
            ),
          ),
          content: Text(
            'Are you sure you want to delete the chat with ${contact.name}?',
            style: TextStyle(fontSize: fontSettings.fontSize - 2),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: fontSettings.fontSize - 2),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _selectedContactId = null;
                });
              },
            ),
            TextButton(
              child: Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: fontSettings.fontSize - 2,
                ),
              ),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);

                navigator.pop();

                // Clear selection FIRST
                setState(() {
                  _selectedContactId = null;
                });

                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Text('Deleting chat...'),
                      ],
                    ),
                    duration: Duration(seconds: 30),
                    backgroundColor: Colors.orange,
                  ),
                );



                final success = await FirebaseApiService.deleteChat(
                  contact.chatUuid,
                );

                scaffoldMessenger.hideCurrentSnackBar();

                if (success) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Chat deleted successfully. Refreshing...'),
                      backgroundColor: ChatColors.primary,
                      duration: Duration(seconds: 2),
                    ),
                  );

                  // Wait a moment for backend to process
                  await Future.delayed(const Duration(milliseconds: 500));

                  // Refresh from API
                  await _fetchChatsFromApi();

                } else {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Failed to delete chat'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchChatsFromApi() async {
    bool showLoading = !_isLoading;

    setState(() {
      if (showLoading) _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      final chatData = await FirebaseApiService.fetchUserChats();
      final userData = await FirebaseApiService.fetchAllUsers();

      if (chatData['chats'] != null) {
        final List<dynamic> chats = chatData['chats'];

        final String userIdentifier = await _resolveCurrentUserId();

        Map<String, dynamic> userDetailsMap = {};
        if (userData['users'] != null) {
          final List<dynamic> users = userData['users'];
          for (var user in users) {
            final userName = user['name'] ?? user['id'] ?? '';
            userDetailsMap[userName] = user;
          }
        }

        setState(() {
          _contacts = chats
              .map(
                (chat) => ChatContact.fromChatApiJson(
                  chat,
                  userIdentifier,
                  currentUserName: _currentUserName,
                  participantDetails: userDetailsMap,
                ),
              )
              .toList();
          _filteredContacts = List.from(_contacts);
          if (showLoading) _isLoading = false;
        });
        await _saveChats();
        // Update badge with total unread count
        final unreadCount = _getTotalUnreadCount();
        await BadgeService().updateBadge(unreadCount);
        unawaited(_refreshGroupMentions());
      } else {
        setState(() {
          _errorMessage = 'No chats data received';
          if (showLoading) _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        if (showLoading) _isLoading = false;
      });

      await _loadChats();
    }
  }

  /// Both lists feed the All/Unread tabs, so they refresh together.
  Future<void> _refreshChatsAndGroups() async {
    await Future.wait([_fetchChatsFromApi(), _fetchGroups()]);
  }

  Future<void> _fetchGroups() async {
    setState(() {
      _isLoadingGroups = true;
      _groupsErrorMessage = null;
    });

    try {
      final groups = await FirebaseApiService.fetchUserGroups();

      if (!mounted) return;
      final parsed = groups.map(ChatGroup.fromApiJson).toList();
      setState(() {
        _groups = parsed;
        _groupIds = {
          for (final g in parsed) ...[g.groupId, g.id],
        }..removeWhere((id) => id.isEmpty);
        _isLoadingGroups = false;
      });
      unawaited(_refreshGroupMentions());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupsErrorMessage = e.toString();
        _isLoadingGroups = false;
      });
    }
  }

  // Rest of the methods remain the same...
  Future<void> _fetchAllUsersForNewChat() async {
    try {
      final data = await FirebaseApiService.fetchAllUsers();

      if (data['users'] != null) {
        final List<dynamic> users = data['users'];
        final List<ChatContact> userContacts = users.map((user) {
          final String name = user['name'] ?? user['firstName'] ?? 'Unknown';
          final String firstName = user['firstName'] ?? name;
          final String initials = ChatContact.generateInitials(name);
          final Color avatarColor = ChatContact.generateColorFromName(name);

          return ChatContact(
            id: user['id'] ?? user['userUuid'] ?? '',
            chatUuid: '',
            name: name,
            firstName: firstName,
            lastMessage: user['isOnline'] == true ? 'Online' : 'Offline',
            time: '',
            isOnline: user['isOnline'] ?? false,
            avatarColor: avatarColor,
            initials: initials,
            unreadCount: 0,
            participants: [name],
            createdAt: DateTime.now(),
            lastMessageSenderName: null,
            appType: ChatContact.parseAppType(user['appType']),
            avatarUrl: ChatContact.parseAvatarUrl(
              Map<String, dynamic>.from(user as Map),
            ),
          );
        }).toList();

        setState(() {
          _allUsers = userContacts;
        });
      }
    } catch (e) {
    
    }
  }

  Future<void> _saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _contacts.map((contact) => contact.toJson()).toList();
    await prefs.setString('chat_contacts', jsonEncode(jsonList));
  }

  Future<void> _loadChats() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('chat_contacts');
    if (jsonString != null) {
      try {
        final jsonList = jsonDecode(jsonString) as List;
        setState(() {
          _contacts = jsonList
              .map((json) => ChatContact.fromJson(json))
              .toList();
          _filteredContacts = List.from(_contacts);
        });
      } catch (e) {
       
      }
    }
  }

  void _filterContacts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredContacts = List.from(_contacts);
      } else {
        _filteredContacts = _contacts
            .where(
              (contact) =>
                  contact.name.toLowerCase().contains(query.toLowerCase()) ||
                  contact.lastMessage.toLowerCase().contains(
                    query.toLowerCase(),
                  ) ||
                  contact.participants.any(
                    (participant) =>
                        participant.toLowerCase().contains(query.toLowerCase()),
                  ),
            )
            .toList();
      }
    });
  }

  /// Group conversations also come back from /api/chats/user/:id, where the
  /// row carries no group name — it renders as whichever participant happens
  /// to be listed first. Those rows are dropped and the group is rendered from
  /// the groups API instead (chatUuid and groupId are the same value).
  ///
  /// Matching is by id only: a multi-participant chat the groups API does not
  /// know about still belongs in the list, so it keeps showing as a chat.
  bool _isGroupChat(ChatContact contact) =>
      _groupIds.contains(contact.chatUuid) || _groupIds.contains(contact.id);

  List<ChatContact> _oneToOneChats() =>
      _filteredContacts.where((c) => !_isGroupChat(c)).toList();

  /// Rows for the All/Unread tabs: 1:1 chats and groups interleaved, newest
  /// first. Entries are either a [ChatContact] or a [ChatGroup]; the group
  /// copies that the chats API also returns are dropped by [_oneToOneChats] so
  /// each conversation appears exactly once.
  List<Object> _getItemsForTab(int tabIndex) {
    // Tab 2 (Groups) is served by _buildGroupList from the groups API, and
    // Favorites has nothing behind it yet.
    if (tabIndex == 3) return const [];

    // Rewards: 1:1 conversations with a Premier Rewards app user (appType 1).
    // They also stay in All/Unread — this tab is only a filtered view of them.
    if (tabIndex == _rewardsTabIndex) {
      return _oneToOneChats().where((c) => c.appType == _rewardsAppType).toList()
        ..sort(_compareRows);
    }

    final bool unreadOnly = tabIndex == 1;

    final items = <Object>[
      ..._oneToOneChats().where((c) => !unreadOnly || c.unreadCount > 0),
      ..._filteredGroups.where(
        (g) => !unreadOnly || _unreadForGroup(g) > 0,
      ),
    ];

    items.sort(_compareRows);

    return items;
  }

  /// Order of the merged list: pinned conversations first (newest pin on top,
  /// the way WhatsApp orders them), then everything else by last activity.
  int _compareRows(Object a, Object b) {
    final aPinned = _isRowPinned(a);
    final bPinned = _isRowPinned(b);
    if (aPinned != bPinned) return aPinned ? -1 : 1;

    if (aPinned && bPinned) {
      final ap = _pinnedAtOfRow(a);
      final bp = _pinnedAtOfRow(b);
      // A pin the backend gave no timestamp for falls through to the
      // last-activity comparison below rather than jumping the queue.
      if (ap != null && bp != null && ap != bp) return bp.compareTo(ap);
    }

    final at = a is ChatContact
        ? a.lastMessageTime
        : _lastActivityForGroup(a as ChatGroup);
    final bt = b is ChatContact
        ? b.lastMessageTime
        : _lastActivityForGroup(b as ChatGroup);
    if (at == null && bt == null) return 0;
    // Conversations without a message yet sink to the bottom.
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  bool _isRowPinned(Object row) =>
      row is ChatContact ? row.isPinned : (row as ChatGroup).isPinned;

  DateTime? _pinnedAtOfRow(Object row) =>
      row is ChatContact ? row.pinnedAt : (row as ChatGroup).pinnedAt;

  /// Conversations pinned right now, counted once each: the chats API also
  /// returns a row per group, and those copies are dropped from the list.
  int get _pinnedCount =>
      _contacts.where((c) => !_isGroupChat(c) && c.isPinned).length +
      _groups.where((g) => g.isPinned).length;

  /// Pins or unpins a row and re-sorts the list straight away, then tells the
  /// backend. A rejected call is rolled back so the list keeps matching the
  /// server.
  Future<void> _togglePin(Object row) async {
    final bool pin = !_isRowPinned(row);
    final String chatId = row is ChatContact
        ? (row.chatUuid.isNotEmpty ? row.chatUuid : row.id)
        : (row as ChatGroup).groupId;
    if (chatId.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);

    if (pin && _pinnedCount >= _maxPinnedChats) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'You can only pin $_maxPinnedChats chats. Unpin one first.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _selectedContactId = null;
      _applyPinnedLocally(chatId, pin);
    });

    final result = await FirebaseApiService.setChatPinned(
      chatId: chatId,
      pinned: pin,
    );

    if (!mounted) return;

    if (result['success'] != true) {
      setState(() => _applyPinnedLocally(chatId, !pin));
      messenger.showSnackBar(
        SnackBar(
          content: Text(pin ? 'Failed to pin chat' : 'Failed to unpin chat'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    unawaited(_saveChats());
  }

  /// Flips the pin flag on every in-memory copy of a conversation — the chat
  /// row, its filtered copy, and the group row when it is a group.
  void _applyPinnedLocally(String chatId, bool pinned) {
    final DateTime? pinnedAt = pinned ? DateTime.now() : null;

    ChatContact mapContact(ChatContact c) =>
        (c.chatUuid == chatId || c.id == chatId)
            ? c.copyWith(isPinned: pinned, pinnedAt: pinnedAt)
            : c;

    _contacts = _contacts.map(mapContact).toList();
    _filteredContacts = _filteredContacts.map(mapContact).toList();
    _groups = _groups
        .map(
          (g) => (g.groupId == chatId || g.id == chatId)
              ? g.copyWith(isPinned: pinned, pinnedAt: pinnedAt)
              : g,
        )
        .toList();
  }

  /// The small pushpin shown on a pinned row, as WhatsApp does.
  Widget _pinnedMarker() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Transform.rotate(
          angle: 0.6,
          child: Icon(Icons.push_pin, size: 14, color: Colors.grey[600]),
        ),
      );

  /// Pin/unpin button shown next to the other actions on a selected row.
  Widget _pinActionButton(Object row) {
    final bool pinned = _isRowPinned(row);
    return IconButton(
      icon: Icon(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        color: ChatColors.primary,
      ),
      onPressed: () => _togglePin(row),
      tooltip: pinned ? 'Unpin chat' : 'Pin chat',
    );
  }

  void _updateContactLastMessage(String contactId, String lastMessage) {
    setState(() {
      final index = _contacts.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        _contacts[index] = _contacts[index].copyWith(
          lastMessage: lastMessage,
          time: 'now',
          lastMessageTime: DateTime.now(),
          lastMessageSender: _currentUserName,
        );
      
        final filteredIndex = _filteredContacts.indexWhere(
          (c) => c.id == contactId,
        );
        if (filteredIndex != -1) {
          _filteredContacts[filteredIndex] = _contacts[index];
        }
      }
    });
    _saveChats();
  }

  /// The check mark WhatsApp stamps over the avatar of a selected row.
  Widget _selectionCheckBadge() => Positioned(
    bottom: 0,
    right: 0,
    child: Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: ChatColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.check, size: 12, color: Colors.white),
    ),
  );

  // ─── Typing indicators ──────────────────────────────────────────────────────

  /// Points the watcher at the conversations currently loaded. Cheap to call
  /// on every build — chats already watched keep their listener.
  ///
  /// Groups go first because there are usually far fewer of them, so they
  /// never lose their place to a long list of 1:1 chats at the ceiling.
  void _syncTypingWatches() {
    _typingWatcher.watchChats([
      for (final group in _groups) group.groupId,
      for (final contact in _contacts) contact.chatUuid,
    ]);
  }

  /// What a row says instead of its last message while someone is writing in
  /// it, or null when nobody is. Our own typing never counts — it would show
  /// on our own row as we typed in the chat we just left.
  String? _typingLabelFor(String chatId, {required bool isGroup}) {
    final typers = _typingWatcher
        .typersIn(chatId)
        .where((t) => !t.matches(_currentUserUuid, FirebaseApiService.appType))
        .toList();
    if (typers.isEmpty) return null;
    if (!isGroup) return 'typing…';

    // Several at once are counted rather than named: a row is one line wide,
    // and a string of names would be cut off before it said anything useful.
    if (typers.length > 1) return '${typers.length} people typing…';

    // Only the name the typist published is available out here — the list has
    // no group roster to fall back on, so an unnamed typist goes unnamed.
    final name = typers.first.userName.trim();
    return name.isEmpty ? 'typing…' : '$name is typing…';
  }

  /// The line itself, in the chat green so it reads as live rather than as a
  /// message somebody actually sent.
  Widget _typingSubtitle(String label, FontSettings fontSettings) {
    return Text(
      label,
      style: TextStyle(
        color: ChatColors.primary,
        fontSize: fontSettings.fontSize - 2,
        fontWeight: FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildContactCard(ChatContact contact, FontSettings fontSettings) {
    final typingLabel = _typingLabelFor(contact.chatUuid, isGroup: false);
    final bool hasLastMessage =
        contact.lastMessage.isNotEmpty &&
        contact.lastMessage != 'No messages yet';
    final bool isSelected = _selectedContactId == contact.id;

    return Material(
      color: isSelected ? _kChatSelectionColor : Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (isSelected) {
            setState(() {
              _selectedContactId = null;
            });
            return;
          }

          final chatId = await FirebaseApiService.createChat(
            contact.userUuid,
            userAppType: contact.appType,
          );

          final contactWithChatId = contact.copyWith(
            chatUuid: chatId ?? contact.chatUuid,
            firstName: contact.firstName.isNotEmpty
                ? contact.firstName
                : contact.name,
          );

          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => IndividualChatScreen(
                    contact: contactWithChatId,
                    onMessageSent: (String lastMessage) {
                      _updateContactLastMessage(contact.id, lastMessage);
                    },
                  ),
                ),
              )
              .then((_) {
                // Both lists, not just chats: a message can have been
                // forwarded from this conversation into a group, and the
                // All/Unread tabs sort chats and groups together.
                _refreshChatsAndGroups();
              });
        },
        onLongPress: () {
          setState(() {
            _selectedContactId = contact.id;
          });
        },
        child: ListTile(
          leading: Stack(
            children: [
              UserAvatar(
                avatarUrl: contact.avatarUrl,
                initials: contact.initials,
                backgroundColor: contact.avatarColor,
                radius: 25,
                fontSize: fontSettings.fontSize,
              ),
             if (contact.isOnline)
  Positioned(
    bottom: 0,
    right: 0,
    child: Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: ChatColors.accent, // WhatsApp's online dot
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    ),
  ),
              if (isSelected) _selectionCheckBadge(),
            ],
          ),
          title: Text(
            contact.name,
            style: TextStyle(
              fontSize: fontSettings.fontSize,
              fontWeight: fontSettings.fontWeight,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Typing takes the row over from the message preview while it
              // lasts, the way WhatsApp does it.
              if (typingLabel != null)
                _typingSubtitle(typingLabel, fontSettings)
              else if (hasLastMessage) ...[
                Text(
                  stripChatFormatting(contact.lastMessage),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: fontSettings.fontSize - 2,
                    fontWeight: contact.unreadCount > 0
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (contact.lastMessageSender != null)
                  Text(
                    'by ${contact.lastMessageSenderName}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: fontSettings.fontSize - 4,
                    ),
                  ),
              ] else
                Text(
                  'No messages yet',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: fontSettings.fontSize - 2,
                  ),
                ),
            ],
          ),
          trailing: isSelected
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _pinActionButton(contact),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _showDeleteConfirmation(contact),
                      tooltip: 'Delete chat',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () {
                        setState(() {
                          _selectedContactId = null;
                        });
                      },
                      tooltip: 'Cancel',
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      contact.time,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: fontSettings.fontSize - 4,
                      ),
                    ),
                    if (contact.unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: ChatColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${contact.unreadCount}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSettings.fontSize - 4,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (hasLastMessage && contact.unreadCount == 0)
                      Icon(
                        contact.lastMessageRead
                            ? Icons.done_all
                            : Icons.done,
                        color: contact.lastMessageRead
                            ? Colors.blue
                            : Colors.grey,
                        size: 16,
                      ),
                    if (contact.isPinned) _pinnedMarker(),
                  ],
                ),
        ),
      ),
    );
  }

  List<ChatGroup> get _filteredGroups {
    if (_searchQuery.isEmpty) return _groups;
    final query = _searchQuery.toLowerCase();
    return _groups
        .where(
          (group) =>
              group.groupName.toLowerCase().contains(query) ||
              group.lastMessage.toLowerCase().contains(query),
        )
        .toList();
  }

  /// The Groups tab orders rows the same way the merged list does, so a
  /// pinned group sits on top there too.
  List<ChatGroup> _sortedGroups() =>
      _filteredGroups.toList()..sort((a, b) => _compareRows(a, b));

  /// The groups API carries no unread count, but the same conversation comes
  /// back from the chats API — borrow the count from there.
  int _unreadForGroup(ChatGroup group) => _chatRowForGroup(group)?.unreadCount ?? 0;

  /// Works out which groups have unread messages naming the user, so their row
  /// can show the "@" marker. Runs in the background after a list refresh: a
  /// group is only looked at while it has something unread, and only when its
  /// unread count or last message moved since the previous scan.
  Future<void> _refreshGroupMentions() async {
    if (_isScanningMentions || _groups.isEmpty) return;
    _isScanningMentions = true;

    try {
      final userUuid = await _resolveCurrentUserId();
      var changed = false;

      for (final group in List<ChatGroup>.from(_groups)) {
        if (!mounted) return;
        final unread = _unreadForGroup(group);
        final signature =
            '$unread|${_lastActivityForGroup(group)?.millisecondsSinceEpoch ?? 0}';
        final moved = await MentionTracker.refresh(
          chatId: group.groupId,
          signature: signature,
          hasUnread: unread > 0,
          currentUserUuid: userUuid,
        );
        changed = changed || moved;
      }

      if (changed && mounted) setState(() {});
    } finally {
      _isScanningMentions = false;
    }
  }

  ChatContact? _chatRowForGroup(ChatGroup group) {
    for (final contact in _contacts) {
      if (contact.chatUuid == group.groupId || contact.id == group.groupId) {
        return contact;
      }
    }
    return null;
  }

  /// Sort key for the merged list. A group with no messages yet has no
  /// lastMessageTime of its own, so fall back to the chats API row, which
  /// reports the creation time — that keeps a brand new group near the top
  /// instead of at the very bottom.
  DateTime? _lastActivityForGroup(ChatGroup group) =>
      group.lastMessageTime ?? _chatRowForGroup(group)?.lastMessageTime;

  Widget _buildGroupCard(ChatGroup group, FontSettings fontSettings) {
    final bool hasLastMessage = group.lastMessage.isNotEmpty;
    final typingLabel = _typingLabelFor(group.groupId, isGroup: true);
    final int unreadCount = _unreadForGroup(group);
    // Unread messages in here name the user: the row gets the "@" marker,
    // which opens the conversation at the mention rather than at the end.
    final bool hasMentions = MentionTracker.hasMentions(group.groupId);
    // Long-pressing a group selects it the same way a 1:1 chat row does, so
    // the pin button appears in the same place for both kinds of row.
    final bool isSelected = _selectedContactId == group.groupId;

    return Material(
      color: isSelected ? _kChatSelectionColor : Colors.transparent,
      child: ListTile(
        leading: Stack(
          children: [
            GroupAvatar(
              avatarUrl: group.groupAvatarUrl,
              radius: 25,
              backgroundColor: group.avatarColor,
            ),
            if (isSelected) _selectionCheckBadge(),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                group.groupName,
                style: TextStyle(
                  fontSize: fontSettings.fontSize,
                  fontWeight: fontSettings.fontWeight,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (group.isAdmin) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ChatColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Admin',
                  style: TextStyle(
                    color: ChatColors.primaryDark,
                    fontSize: fontSettings.fontSize - 6,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (typingLabel != null)
              _typingSubtitle(typingLabel, fontSettings)
            else
              Text(
                hasLastMessage
                    ? stripChatFormatting(group.lastMessage)
                    : 'No messages yet',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: fontSettings.fontSize - 2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}'
              '${group.adminOnlyMessaging ? ' • Admins only' : ''}',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: fontSettings.fontSize - 4,
              ),
            ),
          ],
        ),
        trailing: isSelected
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pinActionButton(group),
                  IconButton(
                    icon: const Icon(Icons.info_outline, color: Colors.grey),
                    onPressed: () => _openGroupDetails(group, fontSettings),
                    tooltip: 'Group info',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () =>
                        setState(() => _selectedContactId = null),
                    tooltip: 'Cancel',
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    group.time,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: fontSettings.fontSize - 4,
                    ),
                  ),
                  if (hasMentions || unreadCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasMentions) ...[
                            InkWell(
                              onTap: () => _openGroupChat(group, jumpToMentions: true),
                              customBorder: const CircleBorder(),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: ChatColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.alternate_email,
                                  color: Colors.white,
                                  size: fontSettings.fontSize - 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: ChatColors.accent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$unreadCount',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: fontSettings.fontSize - 4,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (group.isPinned) _pinnedMarker(),
                      InkWell(
                        onTap: () => _openGroupDetails(group, fontSettings),
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        onTap: () {
          if (isSelected) {
            setState(() => _selectedContactId = null);
            return;
          }
          _openGroupChat(group);
        },
        onLongPress: () =>
            setState(() => _selectedContactId = group.groupId),
      ),
    );
  }

  void _openGroupDetails(ChatGroup group, FontSettings fontSettings) {
    showGroupDetailsSheet(
      context: _chatModalContext,
      groupId: group.groupId,
      avatarColor: group.avatarColor,
      fontSettings: fontSettings,
      currentUserUuid: _currentUserUuid,
      // A rename or member change shows up in the list straight away.
      onGroupChanged: _fetchGroups,
    );
  }

  /// Opens the group conversation. The group chat reuses the 1:1 screen with
  /// the groupId standing in for the chatId, which is how the backend models
  /// group messages too.
  /// [jumpToMentions] opens the conversation on the oldest unread message
  /// naming the user — what tapping the "@" marker does — instead of at the
  /// end of the conversation.
  void _openGroupChat(ChatGroup group, {bool jumpToMentions = false}) {
    final groupContact = ChatContact(
      id: group.groupId,
      chatUuid: group.groupId,
      userUuid: group.groupId,
      name: group.groupName,
      firstName: group.groupName,
      lastMessage: group.lastMessage,
      time: group.time,
      avatarColor: group.avatarColor,
      initials: group.initials,
      participants: const [],
      createdAt: DateTime.now(),
      lastMessageSenderName: group.lastMessageSender,
      appType: FirebaseApiService.appType,
      avatarUrl: group.groupAvatarUrl,
    );

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => IndividualChatScreen(
              contact: groupContact,
              isGroup: true,
              groupMemberCount: group.memberCount,
              canSendMessages: !group.adminOnlyMessaging || group.isAdmin,
              // Carried either way, so the "@" button inside the chat can
              // walk the unread mentions even when the row itself was tapped.
              mentionMessageIds: MentionTracker.mentionsIn(group.groupId),
              jumpToMentionOnOpen: jumpToMentions,
            ),
          ),
        )
        // Forwarding out of a group updates 1:1 chats too, so refresh both.
        .then((_) => _refreshChatsAndGroups());
  }

  Widget _buildGroupList(FontSettings fontSettings) {
    if (_isLoadingGroups && _groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: ChatColors.primary),
            const SizedBox(height: 16),
            Text(
              'Loading groups...',
              style: TextStyle(fontSize: fontSettings.fontSize - 2),
            ),
          ],
        ),
      );
    }

    if (_groupsErrorMessage != null && _groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 50, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _groupsErrorMessage!,
                style: TextStyle(
                  fontSize: fontSettings.fontSize,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchGroups,
              style: ElevatedButton.styleFrom(backgroundColor: ChatColors.primary),
              child: Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSettings.fontSize - 2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final groups = _sortedGroups();

    if (groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchGroups,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            const Icon(Icons.groups_outlined, size: 50, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: TextStyle(
                fontSize: fontSettings.fontSize,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => _openNewGroupScreen(),
                child: Text(
                  'Create a group',
                  style: TextStyle(
                    color: ChatColors.primary,
                    fontSize: fontSettings.fontSize - 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchGroups,
      child: ListView.builder(
        itemCount: groups.length,
        itemBuilder: (context, index) =>
            _buildGroupCard(groups[index], fontSettings),
      ),
    );
  }

  Widget _buildChatList(int tabIndex, FontSettings fontSettings) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: ChatColors.primary),
            const SizedBox(height: 16),
            Text(
              'Loading chats...',
              style: TextStyle(fontSize: fontSettings.fontSize - 2),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null && _contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 50, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: fontSettings.fontSize,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchChatsFromApi,
              style: ElevatedButton.styleFrom(backgroundColor: ChatColors.primary),
              child: Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSettings.fontSize - 2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final items = _getItemsForTab(tabIndex);

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 50, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              tabIndex == 0
                  ? "No chats found"
                  : "No ${['all', 'unread', 'groups', 'favorites', 'rewards'][tabIndex]} chats",
              style: TextStyle(
                fontSize: fontSettings.fontSize,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _refreshChatsAndGroups,
              child: Text(
                "Refresh chats",
                style: TextStyle(
                  color: ChatColors.primary,
                  fontSize: fontSettings.fontSize - 2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshChatsAndGroups,
      child: GestureDetector(
        onTap: () {
          if (_selectedContactId != null) {
            setState(() {
              _selectedContactId = null;
            });
          }
        },
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return item is ChatGroup
                ? _buildGroupCard(item, fontSettings)
                : _buildContactCard(item as ChatContact, fontSettings);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontSettings = ref.watch(chatFontSettingsProvider);
    _syncTypingWatches();

    return ChatFontScope(
      child: KeyedSubtree(
        key: _chatScopeKey,
        child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 8,
            title: Row(
              children: [
                // The header doubles as the profile entry point: tapping the
                // photo runs the same upload as the overflow menu's
                // "Change profile photo".
                // GestureDetector(
                //   behavior: HitTestBehavior.opaque,
                //  // onTap: _updateMyAvatar,
                //   child: _buildMyAvatar(),
                // ),
               // const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Chats",
                        style: TextStyle(
                          fontSize: fontSettings.fontSize + 2,
                          fontWeight: fontSettings.fontWeight,
                        ),
                      ),
                      // if ((_currentUserName ?? '').isNotEmpty)
                      //   Text(
                      //     _currentUserName!,
                      //     maxLines: 1,
                      //     overflow: TextOverflow.ellipsis,
                      //     style: TextStyle(
                      //       fontSize: fontSettings.fontSize - 5,
                      //       fontWeight: FontWeight.normal,
                      //       color: Colors.white70,
                      //     ),
                      //   ),
                    ],
                  ),
                ),
              ],
            ),
            // backgroundColor: _selectedContactId != null
            //     ? Colors.red
            //     : ChatColors.primary,
            backgroundColor: ChatColors.primary,
            foregroundColor: Colors.white,
            // leading: _selectedContactId != null
            //     ? IconButton(
            //         icon: const Icon(Icons.close),
            //         onPressed: () {
            //           setState(() {
            //             _selectedContactId = null;
            //           });
            //         },
            //       )
            //     : null,
            // actions: _selectedContactId != null
            //     ? [
            //         IconButton(
            //           icon: const Icon(Icons.delete),
            //           onPressed: () {
            //             final contact = _contacts.firstWhere(
            //               (c) => c.id == _selectedContactId,
            //             );
            //             _showDeleteConfirmation(contact);
            //           },
            //         ),
            //       ]
            actions: [
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  context.push('/menu');
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  _fetchChatsFromApi();
                  _fetchGroups();
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More',
                onSelected: (value) {
                  switch (value) {
                    case 'profile':
                      _openMyProfile();
                      break;
                    case 'chat_settings':
                      _openChatSettings();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'profile', child: Text('My profile')),
                  PopupMenuItem(
                    value: 'chat_settings',
                    child: Text('Chat settings'),
                  ),
                ],
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(100),
              child: Container(
                color: Colors.white,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        onChanged: _filterContacts,
                        style: TextStyle(fontSize: fontSettings.fontSize - 2),
                        decoration: InputDecoration(
                          hintText: "Search chats...",
                          hintStyle: TextStyle(
                            fontSize: fontSettings.fontSize - 2,
                          ),
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey.shade200,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: ChatColors.primary,
                      labelColor: ChatColors.primary,
                      unselectedLabelColor: Colors.black54,
                      labelStyle: TextStyle(
                        fontSize: fontSettings.fontSize - 4,
                        fontWeight: fontSettings.fontWeight,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: fontSettings.fontSize - 4,
                      ),
                      tabs: const [
                        Tab(text: "All"),
                        Tab(text: "Unread"),
                        Tab(text: "Groups"),
                        Tab(text: "Favorites"),
                        Tab(text: "Rewards"),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              const NotificationBanner(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildChatList(0, fontSettings),
                    _buildChatList(1, fontSettings),
                    _buildGroupList(fontSettings),
                    _buildChatList(3, fontSettings),
                    _buildChatList(_rewardsTabIndex, fontSettings),
                  ],
                ),
              ),
              if (_errorMessage != null && _contacts.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange.withOpacity(0.9),
                    child: Text(
                      'Warning: ${_errorMessage!}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSettings.fontSize - 4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: _selectedContactId == null
              ? FloatingActionButton(
                  // The FAB is the brighter green in WhatsApp, not the header's.
                  backgroundColor:ChatColors.primary,
                  onPressed: () => _openNewChatScreen(),
                  child: const Icon(Icons.chat, color: Colors.white),
                )
              : null,
        ),
        ),
      ),
    );
  }

  // ── New conversations ─────────────────────────────────────────────────────
  // Both pickers are full screens rather than sheets, the way WhatsApp does
  // it: they own an app bar with its own search, and they hand a result back
  // here because this is where the chat list and its refreshes live.

  Future<void> _openNewChatScreen() async {
    await _fetchAllUsersForNewChat();

    if (!mounted) return;

    final result = await Navigator.push<NewChatResult>(
      context,
      MaterialPageRoute(builder: (_) => NewChatScreen(contacts: _allUsers)),
    );

    if (!mounted || result == null) return;

    if (result.startGroup) {
      // The contact list was just loaded for the chat picker, so don't pull it
      // down a second time on the way into the group flow.
      await _openNewGroupScreen(fetchContacts: false);
    } else if (result.contact != null) {
      await _startChatWith(result.contact!);
    }
  }

  Future<void> _openNewGroupScreen({bool fetchContacts = true}) async {
    if (fetchContacts) await _fetchAllUsersForNewChat();

    if (!mounted) return;

    final draft = await Navigator.push<NewGroupDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => NewGroupMembersScreen(contacts: _allUsers),
      ),
    );

    if (!mounted || draft == null) return;

    await _createGroup(
      draft.name,
      draft.members,
      avatarPath: draft.avatarPath,
    );
  }

  /// Creates (or reuses) the 1:1 chat and opens it. On a backend failure it
  /// still opens the conversation, so the tap is not simply lost.
  Future<void> _startChatWith(ChatContact contact) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 16),
            Text('Creating chat...'),
          ],
        ),
        duration: Duration(seconds: 30),
        backgroundColor: Colors.blue,
      ),
    );

    final String fallbackFirstName = contact.firstName.isNotEmpty
        ? contact.firstName
        : contact.name;

    try {
      final chatId = await FirebaseApiService.createChat(
        contact.userUuid,
        userAppType: contact.appType,
      );

      scaffoldMessenger.hideCurrentSnackBar();

      await navigator.push(
        MaterialPageRoute(
          builder: (context) => IndividualChatScreen(
            contact: contact.copyWith(
              chatUuid: chatId,
              firstName: fallbackFirstName,
            ),
            onMessageSent: (String lastMessage) {
              _updateContactLastMessage(contact.id, lastMessage);
            },
          ),
        ),
      );

      _refreshChatsAndGroups();
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error creating chat: $e'),
          backgroundColor: Colors.orange,
        ),
      );

      await navigator.push(
        MaterialPageRoute(
          builder: (context) => IndividualChatScreen(
            contact: contact.copyWith(firstName: fallbackFirstName),
          ),
        ),
      );
    }
  }

  /// Chat carries its own font size, so the screen that changes it lives here
  /// rather than in the app-wide Settings screen.
  void _openChatSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatSettingsScreen()),
    );
  }

  /// Opens the signed-in user's chat profile. It pops `true` when the photo
  /// was replaced there, which the contact rows carry, so refresh on that.
  Future<void> _openMyProfile() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ChatProfileScreen()),
    );
    if (!mounted) return;

    await _loadMyProfile();
    if (changed == true) {
      _fetchChatsFromApi();
      _fetchGroups();
    }
  }

  /// Header avatar for the signed-in user: the uploaded photo when the
  /// backend has one, the first letter of the name otherwise, with a small
  /// camera badge so it reads as tappable.
  Widget _buildMyAvatar() {
    final name = (_currentUserName ?? '').trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final url = _myAvatarUrl;

    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: Colors.white,
            backgroundImage: url == null ? null : NetworkImage(url),
            child: url == null
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: ChatColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 10,
                color: ChatColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Picks an image and uploads it as the signed-in user's chat avatar.
  Future<void> _updateMyAvatar() async {
    final picked = await pickChatAvatarImage(context);
    if (picked == null || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Uploading profile photo...')),
    );

    final result = await FirebaseApiService.updateUserAvatar(
      avatarPath: picked.path,
    );
    if (!mounted) return;

    scaffoldMessenger.hideCurrentSnackBar();
    if (result['success'] == true) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated'),
          backgroundColor: ChatColors.primary,
        ),
      );
      // Contact rows carry the avatar url from the backend, so re-pull the
      // lists — and the user's own profile — to show the new picture straight
      // away.
      _loadMyProfile();
      _fetchChatsFromApi();
      _fetchGroups();
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not update the profile photo: ${result['error'] ?? ''}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Lets the user pick an avatar image from the camera or gallery — used for
  /// both the group photo and the signed-in user's own chat profile photo.
  Future<void> _createGroup(
    String name,
    List<ChatContact> members, {
    String? avatarPath,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 16),
            Text('Creating group...'),
          ],
        ),
        duration: Duration(seconds: 30),
        backgroundColor: Colors.blue,
      ),
    );

    final groupId = await FirebaseApiService.createGroup(
      name: name,
      members: members,
      avatarPath: avatarPath,
    );

    scaffoldMessenger.hideCurrentSnackBar();

    if (groupId != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Group "$name" created'),
          backgroundColor: ChatColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      await _fetchGroups();

      if (!mounted) return;
      // Jump to the Groups tab so the new group is visible right away.
      _tabController.animateTo(2);
    } else {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to create group'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
