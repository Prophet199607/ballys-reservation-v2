import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ballys_reservation_app/components/badge_service.dart';
import 'package:ballys_reservation_app/data/services/notification_store.dart';
import 'package:ballys_reservation_app/main.dart' show navigatorKey;
import 'package:ballys_reservation_app/models/Guest/guest_booking.dart';
import 'package:ballys_reservation_app/navigation/app_navigation.dart';
import 'package:ballys_reservation_app/utils/chat_notification_sound.dart';
import 'package:ballys_reservation_app/utils/current_chat_state.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;

  /// Initialize local notifications WITHOUT requesting permission
  /// Permission will be requested ONLY after successful login
  Future<void> initializeLocalNotifications() async {
    if (_isInitialized) {
      return;
    }

    try {
      // The saved tone decides which chat channel a message notification is
      // posted to, so it has to be in hand before the first push arrives.
      await ChatNotificationSoundStore.load();

      // Initialize the notification channels (does NOT request permission)
      await AwesomeNotifications().initialize(null, [
        NotificationChannel(
          channelKey: 'high_importance_channel',
          channelName: 'High Importance Notifications',
          channelDescription:
              'This channel is used for important notifications',
          defaultColor: Color(0xFFDAB066),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
        ),
        // Chat messages get a channel per tone: Android freezes a channel's
        // sound when it first sees it, so the choice is made by posting to one
        // channel or the other rather than by editing a single channel.
        NotificationChannel(
          channelKey: ChatNotificationSoundStore.toneChannelKey,
          channelName: 'Chat Messages (app tone)',
          channelDescription: 'Chat messages with the app\'s own tone',
          defaultColor: Color(0xFFDAB066),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          soundSource: ChatNotificationSoundStore.androidSoundResource,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: ChatNotificationSoundStore.defaultChannelKey,
          channelName: 'Chat Messages (phone default)',
          channelDescription:
              'Chat messages with this phone\'s notification sound',
          defaultColor: Color(0xFFDAB066),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          defaultRingtoneType: DefaultRingtoneType.Notification,
          enableVibration: true,
        ),
      ]);

      // DO NOT request permission here - it will be done after login
      // Just set up the listeners
      AwesomeNotifications().setListeners(
        onActionReceivedMethod: onActionReceivedMethod,
        onNotificationCreatedMethod: onNotificationCreatedMethod,
        onNotificationDisplayedMethod: onNotificationDisplayedMethod,
        onDismissActionReceivedMethod: onDismissActionReceivedMethod,
      );

      _isInitialized = true;
      print('✅ Notification service initialized (permission NOT requested)');
    } catch (e) {
      print('❌ Error initializing notifications: $e');
    }
  }

  /// Call this ONLY after successful login to request permission
  Future<bool> requestNotificationPermission() async {
    try {
      final isAllowed = await AwesomeNotifications().isNotificationAllowed();

      if (!isAllowed) {
        // Request permission only if not already allowed
        final granted = await AwesomeNotifications()
            .requestPermissionToSendNotifications();
        print('🔔 Notification permission requested: $granted');
        return granted;
      }

      print('🔔 Notification permission already granted');
      return true;
    } catch (e) {
      print('❌ Error requesting notification permission: $e');
      return false;
    }
  }

  Future<void> showForegroundNotification(RemoteMessage message) async {
    print('Received foreground message: ${message.messageId}');
    print('Received foreground message: ${message.data}');
    try {
      // An edit or a reaction only asks the open chat to refetch — it is not
      // a new message, so it raises neither a banner nor the badge. Without
      // this it would fall through to the chat branch below and show an
      // empty "New Message".
      if (NotificationStore.isSilentThreadUpdate(message)) {
        print('PUSH branch -> SILENT THREAD UPDATE, no notification');
        return;
      }

      String? notificationChatId;

      // For iOS, skip custom notifications and let FCM handle natively. The
      // chat tone is played by AppDelegate.willPresent, which owns the banner
      // this push produces — doing it there rather than here keeps it off the
      // Dart round trip and out of step with the banner.
      if (Platform.isIOS) {
        await _updateBadgeCount(1);
        return;
      }

      // Android: Show custom notification
      String title =
          message.data['title'] ?? message.notification?.title ?? 'New Message';
      String body = message.data['body'] ?? message.notification?.body ?? '';
      print('PUSH branch -> msg_type=${message.data['msg_type']}');
      if (message.data['msg_type'] == '35') {
        print('PUSH branch -> GUEST BOOKING (35)');
        int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
          100000,
        );
        final badgeService = BadgeService();
        final currentBadge = await badgeService.getSavedBadgeCount();
        final newBadgeCount = currentBadge + 1;
        await badgeService.updateBadge(newBadgeCount);

        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: notificationId,
            channelKey: 'high_importance_channel',
            title: title,
            body: body,
            notificationLayout: NotificationLayout.Default,
            payload: {
              'type': '35',
              'MID': message.data['MID'] ?? '',
              'Pkg_Start': message.data['Pkg_Start'] ?? '',
              'Pkg_End': message.data['Pkg_End'] ?? '',
              'InsertDate': message.data['InsertDate'] ?? '',
            },
            icon: 'resource://mipmap/launcher_icon',
            wakeUpScreen: true,
            badge: newBadgeCount,
          ),
        );
        return; // ✅ Exit early, don't fall through to chat logic
      }

      // ─── Transport Assignment (msg_type: 10) ──────────────────────────────
      if (message.data['msg_type'] == '10') {
        print('PUSH branch -> TRANSPORT (10)');
        int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
          100000,
        );
        final badgeService = BadgeService();
        final currentBadge = await badgeService.getSavedBadgeCount();
        final newBadgeCount = currentBadge + 1;
        await badgeService.updateBadge(newBadgeCount);

        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: notificationId,
            channelKey: 'high_importance_channel',
            title: title,
            body: body,
            notificationLayout: NotificationLayout.Default,
            payload: {
              'type': '10',
              'MasterId': message.data['MasterId'] ?? '',
              'IsRejected': message.data['IsRejected'] ?? '',
              'IsReceived': message.data['IsReceived'] ?? '',
            },
            icon: 'resource://mipmap/launcher_icon',
            wakeUpScreen: true,
            badge: newBadgeCount,
          ),
        );
        return; // ✅ Exit early, don't fall through to chat logic
      }

      // Parse the Details field
      String? detailsJson = message.data['Details'];
      Map<String, dynamic>? chatDetails;

      if (detailsJson != null && detailsJson.isNotEmpty) {
        try {
          chatDetails = json.decode(detailsJson);
          notificationChatId = chatDetails?['chatId']?.toString();
        } catch (e) {
          print('Error parsing Details: $e');
        }
      }

      if (notificationChatId == null || notificationChatId.isEmpty) {
        notificationChatId =
            message.data['chatId']?.toString() ??
            message.data['chat_id']?.toString();
      }

      // The conversation is already open: no banner, but the tone still marks
      // the arrival the way it does in any messenger.
      if (notificationChatId != null &&
          CurrentChatState().isCurrentChat(notificationChatId)) {
        await _updateBadgeCount(1);
        unawaited(ChatNotificationSoundStore.playIfAppTone());
        return;
      }

      Map<String, String> payload = {
        'type': message.data['msg_type']?.toString() ?? 'chat',
        'screen': 'chat',
        'chatId': chatDetails?['chatId']?.toString() ?? '',
        'senderId': chatDetails?['senderId']?.toString() ?? '',
        'senderName': chatDetails?['senderName']?.toString() ?? '',
        'hostName': chatDetails?['hostName']?.toString() ?? '',
        // 'group_message' tells the chat screen the chatId is a group id.
        'action': chatDetails?['action']?.toString() ?? '',
      };

      print(
        'PUSH branch -> CHAT fallback (chatId=$notificationChatId) '
        '— any unknown msg_type lands here',
      );

      String? imageUrl = message.data['image_url'];
      int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
        100000,
      );

      final badgeService = BadgeService();
      final currentBadge = await badgeService.getSavedBadgeCount();
      final newBadgeCount = currentBadge + 1;

      await badgeService.updateBadge(newBadgeCount);

      bool created = await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notificationId,
          channelKey: ChatNotificationSoundStore.current.channelKey,
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
          payload: payload,
          largeIcon: imageUrl,
          bigPicture: imageUrl,
          icon: 'resource://mipmap/launcher_icon',
          wakeUpScreen: true,
          category: NotificationCategory.Message,
          badge: newBadgeCount,
        ),
      );

      if (created) {
        await _updateBadgeCount(1);
      }
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  Future<void> _updateBadgeCount(int increment) async {
    try {
      final badgeService = BadgeService();
      await badgeService.addBadge(increment);
    } catch (e) {
      print('Error updating badge: $e');
    }
  }

  /// GoRouter only owns the pages it built. A chat detail screen is opened
  /// with `Navigator.push`, so it is a pageless route sitting on top of them:
  /// a `go` swaps the pages underneath it and the user keeps looking at the
  /// same conversation. Drop those routes first so a notification tap really
  /// lands on the screen it points at.
  static void popPagelessRoutes() {
    navigatorKey.currentState?.popUntil((route) => route.settings is Page);
  }

  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(
    ReceivedAction receivedAction,
  ) async {
    try {
      await BadgeService().clearBadge();

      if (receivedAction.payload != null &&
          receivedAction.payload!.isNotEmpty) {
        final payload = receivedAction.payload!;

        // Logged out: the app belongs on the login screen, so drop the tap
        // rather than deep-linking into an authenticated screen.
        if (!await StorageUtil.hasActiveSession()) {
          print('NOTIFICATION tap ignored — no active session');
          return;
        }

        if (payload['type'] == '35') {
          final context = navigatorKey.currentContext;
          if (context != null && context.mounted) {
            await Future.delayed(Duration(milliseconds: 500));
            popPagelessRoutes();
            final booking = GuestBooking(
              idNo: 0,
              mid: payload['MID'] ?? '',
              pkgStart: payload['Pkg_Start'] ?? '',
              pkgEnd: payload['Pkg_End'] ?? '',
              insertDate: payload['InsertDate'] ?? '',
              pkgStatus: false,
            );
            context.go(
              '/guest-bookings/view-booking',
              extra: {'booking': booking, 'isPending': true},
            );
          }
          return;
        }
        if (payload['type'] == '10') {
          final context = navigatorKey.currentContext;
          if (context != null && context.mounted) {
            await Future.delayed(Duration(milliseconds: 500));
            // TransportScreen reloads from the API in its initState, so simply
            // landing on it gives the user fresh data. `masterId` tells it
            // which request to reveal and highlight.
            popPagelessRoutes();
            context.go(AppNavigation.transportLocation(payload['MasterId']));
          }
          return;
        }
        if (payload['type'] == '11' ||
            payload['screen'] == 'chat' ||
            payload.containsKey('chatId')) {
          final chatId = payload['chatId'] ?? '';
          final senderName = payload['senderName'] ?? '';
          final senderId = payload['senderId'] ?? '';
          final hostName = payload['hostName'] ?? '';
          final action = payload['action'] ?? '';

          final context = navigatorKey.currentContext;
          if (context != null && context.mounted) {
            await Future.delayed(Duration(milliseconds: 500));
            popPagelessRoutes();

            context.go(
              '/menu/chats',
              extra: {
                'chatId': chatId,
                'senderName': senderName,
                'senderId': senderId,
                'hostName': hostName,
                'action': action,
                'openChat': true,
              },
            );
          }
        }
      }
    } catch (e) {
      print('Error in onActionReceivedMethod: $e');
    }
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationCreatedMethod(
    ReceivedNotification receivedNotification,
  ) async {
    print('Notification created: ${receivedNotification.id}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayedMethod(
    ReceivedNotification receivedNotification,
  ) async {
    print('Notification displayed: ${receivedNotification.id}');
  }

  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceivedMethod(
    ReceivedAction receivedAction,
  ) async {
    print('Notification dismissed: ${receivedAction.id}');
  }

  void handleNotificationTap(RemoteMessage message) {
    try {
      BadgeService().clearBadge();

      String? detailsJson = message.data['Details'];
      Map<String, dynamic>? chatDetails;

      if (detailsJson != null && detailsJson.isNotEmpty) {
        try {
          chatDetails = json.decode(detailsJson);
        } catch (e) {
          print('Error parsing Details: $e');
        }
      }

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        popPagelessRoutes();
        context.go(
          '/menu/chats',
          extra: {
            'chatId': chatDetails?['chatId'] ?? '',
            'senderName': chatDetails?['senderName'] ?? '',
            'senderId': chatDetails?['senderId'] ?? '',
            'hostName': chatDetails?['hostName'] ?? '',
            'action': chatDetails?['action'] ?? '',
            'openChat': true,
          },
        );
      }
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

  Future<String?> getFCMToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  Future<void> deleteFCMToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
      await BadgeService().clearBadge();
    } catch (e) {
      print('Error deleting FCM token: $e');
    }
  }
}
