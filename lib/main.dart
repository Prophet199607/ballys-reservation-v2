import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:ballys_reservation_app/components/badge_service.dart';
import 'package:ballys_reservation_app/components/developer_banner.dart';
import 'package:ballys_reservation_app/components/localNotificationService.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/data/services/device_config_service.dart';
import 'package:ballys_reservation_app/data/services/fcm_token_service.dart';
import 'package:ballys_reservation_app/data/services/notification_store.dart';
import 'package:ballys_reservation_app/data/services/versioncehck_service.dart';
import 'package:ballys_reservation_app/models/Guest/guest_booking.dart';
import 'package:ballys_reservation_app/navigation/app_navigation.dart';
import 'package:ballys_reservation_app/providers/app_notifications_provider.dart';
import 'package:ballys_reservation_app/providers/auth_provider.dart';
import 'package:ballys_reservation_app/providers/guest_booking_provider.dart';
import 'package:ballys_reservation_app/providers/transport_provider.dart';
import 'package:ballys_reservation_app/utils/badge_sync_helper.dart';
import 'package:ballys_reservation_app/utils/connectivity_service.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:ballys_reservation_app/utils/token_refresh_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

Color customGoldColor = const Color(0xFFDAB066);

// Global navigator key for navigation from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Dumps the full push payload so unknown notification types can be identified.
/// Filter the terminal with: flutter logs | grep PUSH
void _logPushMessage(String source, RemoteMessage message) {
  print('=========== PUSH [$source] ===========');
  print('PUSH messageId : ${message.messageId}');
  print('PUSH msg_type  : ${message.data['msg_type']}');
  print('PUSH title     : ${message.data['title'] ?? message.notification?.title}');
  print('PUSH body      : ${message.data['body'] ?? message.notification?.body}');
  print('PUSH data keys : ${message.data.keys.toList()}');
  message.data.forEach((key, value) {
    print('PUSH   data[$key] = $value');
  });
  print('======================================');
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  _logPushMessage('background', message);

  // Silent thread updates (an edit, a reaction) carry no new message — the
  // chat is refetched when it is next opened, so nothing is stored or counted.
  if (NotificationStore.isSilentThreadUpdate(message)) return;

  // Keep non-chat notifications in local history so the home screen bell shows
  // them the next time the app is opened.
  try {
    await NotificationStore.add(message);
  } catch (e) {
    print('Error storing background notification: $e');
  }

  try {
    final badgeService = BadgeService();
    await badgeService.initialize();

    int systemBadge = 0;
    try {
      systemBadge = await AwesomeNotifications().getGlobalBadgeCounter();
    } catch (e) {
      // If plugin not available in background/isolate, ignore and use saved
    }

    final savedCount = await badgeService.getSavedBadgeCount();
    final base = systemBadge > savedCount ? systemBadge : savedCount;
    await badgeService.updateBadge(base + 1);

    try {
      await BadgeSyncHelper.syncBadgeWithServer();
    } catch (e) {
      print('Badge sync error in background: $e');
    }
  } catch (e) {
    print('Background handler error: $e');
  }
}

late ProviderContainer globalContainer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //await ScreenProtector.preventScreenshotOn();
 await ConnectivityService.instance.initialize();
  // Initialize Firebase
  await Firebase.initializeApp();

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notifications (WITHOUT requesting permission)
  await NotificationService().initializeLocalNotifications();

  // Initialize badge service
  await BadgeService().initialize();

  globalContainer = ProviderContainer();

  // ── Wire up the 401 auto-logout ───────────────────────────────────────────
  registerLogoutCallback(() {
    try {
      globalContainer.read(authProvider.notifier).logout().then((_) {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.lock_outline, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your session has expired. Please log in again.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red[700],
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );

          // Navigate after snackbar is visible
          Future.delayed(const Duration(seconds: 3), () {
            GoRouter.of(context).go('/login');
          });
        }
      });
    } catch (_) {}
  });

  runApp(ProviderScope(
    parent: globalContainer,
    child: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final BadgeService _badgeService = BadgeService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupFirebaseListenersOnly();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _syncBadgeIfLoggedIn();
      _reloadNotificationHistory();
    } else if (state == AppLifecycleState.paused) {
      _syncBadgeIfLoggedIn();
    }
  }

  Future<void> _reloadGuestBookingsGlobally() async {
    try {
      await globalContainer
          .read(guestBookingProvider.notifier)
          .getAllBookings();
      print('✅ Guest bookings reloaded from global listener');
    } catch (e) {
      print('Error reloading guest bookings globally: $e');
    }
  }

  Future<void> _reloadTransportGlobally() async {
    try {
      await globalContainer
          .read(transportProvider.notifier)
          .getTransportData();
      print('✅ Transport data reloaded from global listener');
    } catch (e) {
      print('Error reloading transport data globally: $e');
    }
  }

  Future<void> _syncBadgeIfLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      if (isLoggedIn) {
        BadgeSyncHelper.syncBadgeWithServer();
      }
    } catch (e) {
      print('Error checking login status: $e');
    }
  }

  Future<void> _setupFirebaseListenersOnly() async {
    // Owns the onTokenRefresh subscription: whenever FCM rotates the token it
    // is stored and pushed to the backend, so a stale row repairs itself
    // instead of waiting for the next logout/login.
    FcmTokenService.startRefreshListener();

    // Repairs a row the backend is holding from an earlier run.
    unawaited(FcmTokenService.resyncOnStartup());

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _logPushMessage('foreground', message);
      _recordNotification(message);

      final msgType = message.data['msg_type']?.toString();

      // An edited message or a reaction is a silent refetch ping: the chat
      // screens listen for it themselves, and it must not raise a banner or
      // the unread badge.
      if (NotificationStore.isSilentThreadUpdate(message)) return;

      _showForegroundNotification(message);
      _badgeService.addBadge(1);

      if (msgType == '35') {
        _reloadGuestBookingsGlobally();
      } else if (msgType == '10') {
        // Transport assignment / rejection — refresh the transport list so an
        // open TransportScreen picks up the new status without a manual pull.
        _reloadTransportGlobally();
      }
    });

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _logPushMessage('opened-app', message);
      _recordNotification(message);
      BadgeSyncHelper.syncBadgeWithServer();
      _handleNotificationTap(message);
    });

    // Handle notification tap when app was terminated
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        _logPushMessage('initial-message', message);
        _recordNotification(message);
        BadgeSyncHelper.syncBadgeWithServer();
        _handleNotificationTap(message);
      }
    });
  }

  /// Stores the push in the home screen's notification list.
  /// Chat pushes are skipped by [NotificationStore], and duplicates
  /// (already saved by the background isolate) are ignored.
  void _recordNotification(RemoteMessage message) {
    try {
      globalContainer
          .read(appNotificationsProvider.notifier)
          .addFromMessage(message);
    } catch (e) {
      print('Error recording notification: $e');
    }
  }

  /// Picks up notifications the background isolate wrote while we were away.
  void _reloadNotificationHistory() {
    try {
      globalContainer.read(appNotificationsProvider.notifier).load();
    } catch (e) {
      print('Error reloading notification history: $e');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    await _notificationService.showForegroundNotification(message);
  }

  Future<void> _handleNotificationTap(RemoteMessage message) async {
    // A tap must never jump past the login wall. When the session is gone the
    // app is either on the splash screen (which routes to /login itself) or
    // already sitting on /login, so dropping the tap leaves the user there.
    if (!await StorageUtil.hasActiveSession()) {
      print('PUSH tap ignored — no active session, staying on login flow');
      return;
    }

    // ─── Transport Notification (msg_type: 10) ──────────────────────────────
    if (message.data['msg_type']?.toString() == '10') {
      _reloadTransportGlobally();
      // The master id lets the transport list highlight the request this
      // notification is about.
      final masterId = message.data['MasterId']?.toString().trim() ?? '';
      _navigateOnNotificationTap((context) {
        context.go(AppNavigation.transportLocation(masterId));
      });
      return;
    }

    // ─── Guest Booking Notification (msg_type: 35) ───────────────────────────
    if (message.data['msg_type'] == '35') {
      _navigateOnNotificationTap((context) {
        final booking = GuestBooking(
          idNo: 0,
          mid: message.data['MID'] ?? '',
          pkgStart: message.data['Pkg_Start'] ?? '',
          pkgEnd: message.data['Pkg_End'] ?? '',
          insertDate: message.data['InsertDate'] ?? '',
          pkgStatus: false,
        );

        context.go('/guest-bookings/view-booking', extra: {
          'booking': booking,
          'isPending': true,
        });
      });
      return;
    }

    // ─── Chat Notification ────────────────────────────────────────────────────
    Map<String, dynamic>? chatData;
    String? detailsJson = message.data['Details'];

    if (detailsJson != null) {
      try {
        final chatDetails = json.decode(detailsJson);
        chatData = {
          'chatId': chatDetails['chatId'] ?? '',
          'senderName': chatDetails['senderName'] ?? '',
          'senderId': chatDetails['senderId'] ?? '',
          'action': chatDetails['action'] ?? '',
          'openChat': true,
        };
      } catch (e) {}
    }

    if (chatData == null &&
        (message.data['type'] == 'chat' ||
            message.data['screen'] == 'chat' ||
            message.data.containsKey('chatId'))) {
      chatData = {
        'chatId': message.data['chatId'] ?? '',
        'senderName': message.data['senderName'] ?? '',
        'senderId': message.data['senderId'] ?? '',
        'action': message.data['action'] ?? '',
        'openChat': true,
      };
    }

    _navigateOnNotificationTap((context) {
      if (chatData != null && chatData['chatId'] != '') {
        context.go('/menu/chats', extra: chatData);
      } else {
        context.go('/menu/chats');
      }
    });
  }

  /// Runs a notification tap's navigation once the app has had a moment to
  /// settle, dropping any pageless route (an open chat detail) on the way.
  ///
  /// This deliberately does not wrap the delay in `addPostFrameCallback`:
  /// that does not request a frame, and iOS resumes from a notification tap
  /// without necessarily producing one. The callback then stayed pending
  /// until the user happened to touch the screen — which is exactly when the
  /// deferred navigation used to fire. A timer runs regardless of frames, and
  /// go_router schedules its own frame when it routes.
  void _navigateOnNotificationTap(
    void Function(BuildContext context) navigate,
  ) {
    Future.delayed(const Duration(milliseconds: 500), () {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      NotificationService.popPagelessRoutes();
      navigate(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Bally\'s Reservation App',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.amber,
        textTheme: TextTheme(
          bodyMedium: TextStyle(fontFamily: 'ABCArizonaFlare'),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 20.0,
          selectedItemColor: Colors.black26,
          unselectedItemColor: Colors.black54,
        ),
      ),
      routerConfig: AppNavigation.router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SplashScreen — with fade-in → breathe logo animation
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  bool _hasInternet = true;
  double _loadingProgress = 0.0;

  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _entryController;
  late final AnimationController _breatheController;
  late final Animation<double> _opacityAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initializeSplash();
  }

  void _initAnimations() {
    // Phase 1: fade-in + rise — plays once on entry (800 ms)
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Phase 2: breathe loop — starts after Phase 1 completes (2400 ms)
    _breatheController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    );

    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );

    // Start entry animation, then hand off to breathe loop
    _entryController.forward().whenComplete(() {
      if (mounted) _breatheController.repeat();
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  // ── Animated logo builder ──────────────────────────────────────────────────
  Widget _buildAnimatedLogo() {
    return AnimatedBuilder(
      animation: Listenable.merge([_entryController, _breatheController]),
      builder: (context, child) {
        // Breathe: smooth sine-based scale & opacity ripple
        final breatheT =
            (1 - math.cos(_breatheController.value * 2 * math.pi)) / 2;
        final breatheScale = 1.0 + 0.06 * breatheT;
        final breatheOpacity = 0.9 + 0.1 * breatheT;

        return FadeTransition(
          opacity: _opacityAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Opacity(
              opacity: breatheOpacity,
              child: Transform.scale(
                scale: breatheScale,
                child: child,
              ),
            ),
          ),
        );
      },
      child: Image.asset(
        'assets/images/logo.png',
        width: 400,
        height: 400,
      ),
    );
  }

  // ── Internet & version check ───────────────────────────────────────────────
  Future<bool> _checkInternetConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);

      try {
        final request = await client
            .getUrl(Uri.parse('http://clients3.google.com/generate_204'))
            .timeout(const Duration(seconds: 2));

        final response =
            await request.close().timeout(const Duration(seconds: 2));
        client.close();

        return response.statusCode == 204 || response.statusCode == 200;
      } on SocketException catch (_) {
        client.close();
        return false;
      } on TimeoutException catch (_) {
        client.close();
        return false;
      } on HandshakeException catch (_) {
        client.close();
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  void _showNoInternetDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text(
                'No Internet Connection',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Please check your internet connection and try again. '
            'This app requires an active internet connection to function properly.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _initializeSplash();
              },
              child: Text(
                'Retry',
                style: TextStyle(
                  color: customGoldColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () => exit(0),
              child: const Text(
                'Exit',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async {
            exit(0);
          },
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.system_update, color: customGoldColor, size: 28),
                const SizedBox(width: 10),
                const Text(
                  'Update Available',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const Text(
              'A new version of the app is available. '
              'Please update to continue using the app.',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => exit(0),
                child: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                ).toString() == ''
                    ? const SizedBox()
                    : Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
              TextButton(
                onPressed: () async {
                  final url =
                      Uri.parse(VersionCheckService.getUpdateUrl());
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url,
                        mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open update link'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  'Update',
                  style: TextStyle(
                    color: customGoldColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _animateLoadingBar() async {
    for (int i = 0; i <= 100; i++) {
      if (mounted) {
        setState(() {
          _loadingProgress = i / 100;
        });
        await Future.delayed(const Duration(milliseconds: 25));
      }
    }
  }

  /// Master id of the transport request a terminated-app notification tap
  /// refers to, from either transport path (FCM or awesome_notifications).
  /// Null when the launch had nothing to do with transport.
  static String? _transportMasterIdFrom(
    RemoteMessage? initialMessage,
    ReceivedAction? receivedAction,
  ) {
    String? masterId;
    if (initialMessage?.data['msg_type']?.toString() == '10') {
      masterId = initialMessage!.data['MasterId']?.toString();
    } else if (receivedAction?.payload?['type'] == '10') {
      masterId = receivedAction!.payload!['MasterId'];
    }
    final trimmed = masterId?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Makes sure the app knows which API it is talking to before it routes.
  ///
  /// Returns false only when a signed-in user has no API URL and the device-log
  /// endpoint cannot supply one: the session is unusable, so the caller clears
  /// it and sends the user back to login.
  Future<bool> _ensureDeviceConfig() async {
    final apiUrl = await StorageUtil.getCurrentApiUrl();
    if (apiUrl != null && apiUrl.isNotEmpty) return true;

    // Nobody is signed in — the login screen fetches the config on its own.
    if (!await StorageUtil.hasActiveSession()) return true;

    try {
      final result = await DeviceConfigService.fetchDeviceConfig();
      return result.isConfigured && (result.apiUrl?.isNotEmpty ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<void> _initializeSplash() async {
    setState(() {
      _hasInternet = true;
      _loadingProgress = 0.0;
    });

    _animateLoadingBar();

    // Check internet connectivity first
    _hasInternet = await _checkInternetConnectivity();

    if (!_hasInternet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNoInternetDialog();
      });
      return;
    }

    // ─── Device config self-heal ────────────────────────────────────────────
    // The API URL used to live in secure storage alone, and some Android ROMs
    // drop the keystore key that protects it across a Play Store update. The
    // session in SharedPreferences survives regardless, so the splash would
    // hand the user a home screen whose every request has nowhere to go — the
    // username renders and nothing else loads. Re-fetch the config before
    // routing, and send them to login rather than to a blank home if even that
    // cannot be recovered.
    if (!await _ensureDeviceConfig()) {
      await StorageUtil.clearUserData();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', false);
      if (mounted) context.go('/login');
      return;
    }

    final versionCheck = await VersionCheckService.checkVersion();
    if (!versionCheck['isLatest']) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showUpdateDialog();
      });
      return;
    }

    // Check if app was opened from a terminated state via notification
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();

    // Check awesome notifications for initial action
    ReceivedAction? receivedAction = await AwesomeNotifications()
        .getInitialNotificationAction(removeFromActionEvents: true);

    // Initialize badge service
    await BadgeService().initialize();

    // ─── Guest Booking: terminated app tapped notification ──────────────────
    if (initialMessage != null &&
        initialMessage.data['msg_type'] == '35') {
      Future.delayed(const Duration(seconds: 3), () async {
        final expiry = await StorageUtil.getExpiry();
        if (expiry != null) {
          final expiryTime = DateTime.parse(expiry);
          if (DateTime.now().isBefore(expiryTime)) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_logged_in', true);

            final container = ProviderScope.containerOf(context);
            final authRepo = container.read(authRepositoryProvider);

            final booking = GuestBooking(
              idNo: 0,
              mid: initialMessage.data['MID'] ?? '',
              pkgStart: initialMessage.data['Pkg_Start'] ?? '',
              pkgEnd: initialMessage.data['Pkg_End'] ?? '',
              insertDate: initialMessage.data['InsertDate'] ?? '',
              pkgStatus: false,
            );

            context.go('/guest-bookings/view-booking', extra: {
              'booking': booking,
              'isPending': true,
            });
          } else {
            await StorageUtil.clearUserData();
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_logged_in', false);
            context.go('/login');
          }
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', false);
          context.go('/login');
        }
      });
      return;
    }

    // ─── Transport: terminated app tapped notification ──────────────────────
    // Without this the splash's own '/home' hop three seconds in would throw
    // the user off the transport screen the tap opened.
    final transportMasterId =
        _transportMasterIdFrom(initialMessage, receivedAction);

    // ─── Chat / Normal notification routing ─────────────────────────────────
    Map<String, dynamic>? notificationChatData;

    if (initialMessage != null) {
      String? detailsJson = initialMessage.data['Details'];
      if (detailsJson != null) {
        try {
          final chatDetails = json.decode(detailsJson);
          notificationChatData = {
            'chatId': chatDetails['chatId'] ?? '',
            'senderName': chatDetails['senderName'] ?? '',
            'senderId': chatDetails['senderId'] ?? '',
            'action': chatDetails['action'] ?? '',
            'openChat': true,
          };
        } catch (e) {}
      }

      // 1:1 pushes carry the chat fields flat instead of inside `Details`.
      // Without this the splash would send them to '/home' three seconds in
      // and race the tap handler that is opening the conversation.
      if (notificationChatData == null &&
          initialMessage.data.containsKey('chatId')) {
        notificationChatData = {
          'chatId': initialMessage.data['chatId'] ?? '',
          'senderName': initialMessage.data['senderName'] ?? '',
          'senderId': initialMessage.data['senderId'] ?? '',
          'action': initialMessage.data['action'] ?? '',
          'openChat': true,
        };
      }
    } else if (receivedAction != null &&
        receivedAction.payload != null) {
      notificationChatData = {
        'chatId': receivedAction.payload!['chatId'] ?? '',
        'senderName': receivedAction.payload!['senderName'] ?? '',
        'senderId': receivedAction.payload!['senderId'] ?? '',
        'action': receivedAction.payload!['action'] ?? '',
        'openChat': true,
      };
    }

    Future.delayed(const Duration(seconds: 3), () async {
      final expiry = await StorageUtil.getExpiry();
      if (expiry != null) {
        final expiryTime = DateTime.parse(expiry);
        if (DateTime.now().isBefore(expiryTime)) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', true);

          final container = ProviderScope.containerOf(context);
          final authRepo = container.read(authRepositoryProvider);

          if (notificationChatData != null &&
              notificationChatData['chatId'] != '') {
            context.go('/menu/chats', extra: notificationChatData);
          } else if (transportMasterId != null) {
            context.go(AppNavigation.transportLocation(transportMasterId));
          } else {
            context.go('/home');
          }
        } else {
          await StorageUtil.clearUserData();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', false);
          context.go('/login');
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', false);
        context.go('/login');
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // NOTE: not a Hero — the shared 'hero-image' tag caused
            // duplicate-GlobalKey crashes when flights were interrupted by
            // fast auth navigations.
            _buildAnimatedLogo(),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60.0),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _loadingProgress,
                    backgroundColor: Colors.grey[300],
                    color: customGoldColor,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}