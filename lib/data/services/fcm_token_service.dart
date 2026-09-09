import 'dart:async';

import 'package:ballys_reservation_app/data/services/firebase_api_service.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single owner of the FCM registration token: fetching it, keeping the copy in
/// SharedPreferences current, and mirroring it onto the chat backend.
///
/// Logout deliberately does NOT call FirebaseMessaging.deleteToken() any more.
/// Deleting the registration forced the SDK to re-register, and getToken() on
/// the next login could still hand back the just-deleted string out of its
/// cache — the backend then stored a token FCM had already invalidated and
/// every push to it failed as unregistered. The backend row is dropped
/// instead, which stops the pushes without invalidating the device token.
class FcmTokenService {
  /// Token as last seen on this device.
  static const String _tokenKey = 'FCMToken';

  /// Token the backend last confirmed. Differs from [_tokenKey] whenever a
  /// sync failed or the token rotated, which is what the startup re-sync uses
  /// to decide it has work to do.
  static const String _syncedTokenKey = 'FCMTokenSynced';

  static StreamSubscription<String>? _refreshSub;

  /// Registers the single global onTokenRefresh listener. Idempotent.
  ///
  /// This is the self-healing path: whatever the token was at login, once FCM
  /// hands out the real one it lands here and goes straight to the backend.
  static void startRefreshListener() {
    _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (String token) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenKey, token);
          await _syncIfLoggedIn(token);
        } catch (e) {
          print('FCM token refresh handling failed: $e');
        }
      },
      onError: (e) => print('FCM onTokenRefresh error: $e'),
    );
  }

  /// Current token, retried while the SDK finishes registering.
  ///
  /// The timeout only frees the caller — the native call keeps running — so a
  /// null return is not a failure, just a signal to let [startRefreshListener]
  /// deliver the token when it is ready.
  static Future<String?> getTokenWithRetry({int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 5));
        if (token != null) return token;
      } catch (e) {
        if (i == maxRetries - 1) return null;
      }
      await Future.delayed(Duration(seconds: 1 + i));
    }
    return null;
  }

  /// Post-login registration. Fire-and-forget: never blocks navigation.
  static Future<void> registerAfterLogin() async {
    try {
      final token = await getTokenWithRetry();
      if (token == null) return; // onTokenRefresh will deliver it.

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await _syncIfLoggedIn(token);
    } catch (e) {
      print('FCM registration after login failed: $e');
    }
  }

  /// App-start repair pass: pushes the token up when the backend is holding a
  /// different one, or when the login-time sync never got through.
  static Future<void> resyncOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('is_logged_in') ?? false)) return;

      final token = await getTokenWithRetry();
      if (token == null) return;

      await prefs.setString(_tokenKey, token);
      if (token == prefs.getString(_syncedTokenKey)) return; // already current

      await _syncIfLoggedIn(token);
    } catch (e) {
      print('FCM startup re-sync failed: $e');
    }
  }

  /// Drops this device's row on the backend. Call before clearing user data —
  /// the request needs the auth token and property url still in prefs.
  static Future<void> clearOnLogout() async {
    try {
      await FirebaseApiService.removeFcmToken();
    } catch (e) {
      print('FCM token removal failed: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_syncedTokenKey);
    } catch (e) {
      print('Clearing stored FCM token failed: $e');
    }
  }

  /// Sends [token] up, but only once there is a logged-in user with the fields
  /// the sync payload carries. Syncing early would overwrite a good backend row
  /// with a blank sales code or location.
  static Future<void> _syncIfLoggedIn(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('is_logged_in') ?? false)) return;

    final name = await StorageUtil.getChatUserName();
    final salesCode = await StorageUtil.getSalesCode();
    if (name == null || name.isEmpty) return;
    if (salesCode == null || salesCode.isEmpty) return;

    final response = await FirebaseApiService.syncFmcToken(name, token);
    if (response['success'] == true) {
      await prefs.setString(_syncedTokenKey, token);
    }
  }
}
