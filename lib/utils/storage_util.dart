import 'dart:convert';

import 'package:ballys_reservation_app/data/services/device_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';

class StorageUtil {
  static const _storage = SecureStorage.instance;
  static const _keyAppVersion = 'app_version';
 static const _keyCurrentApiUrl = 'current_api_url';
  static const _keyCurrentLocation = 'current_location';
  static const _keyIsAdmin = 'is_admin';
  static const _keyLocations = 'locations';
  
  static Future<void> saveUserData(
    String userName,
    String userLevel,
    String salesCode,
    String marketingCode,
    String mobileNumber,
    bool? memProfSH,
    bool? giftApp,
    bool? resApp,
    bool? resChk,
    bool? otgiApp,
    bool? otgiChk,
    bool? bgApp,
    bool? bgChk,
    bool? marketingP, {
    String? uName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreservingDeviceConfig(prefs);
    await prefs.setString('userName', userName);
    // U_Name doesn't always come back on the login response, so it's only
    // written when present rather than clobbering it with an empty string.
    if (uName != null && uName.isNotEmpty) {
      await prefs.setString('uName', uName);
    }
    await prefs.setString('userLevel', userLevel);
    await prefs.setString('salesCode', salesCode);
    await prefs.setString('marketingCode', marketingCode);
    await prefs.setString('mobileNumber', mobileNumber);
    if (memProfSH != null) {
      await prefs.setBool('memProfSH', memProfSH);
    }
    if (giftApp != null) {
      await prefs.setBool('giftApp', giftApp);
    }
    if (resApp != null) {
      await prefs.setBool('resApp', resApp);
    }
    if (resChk != null) {
      await prefs.setBool('resChk', resChk);
    }
    if (otgiApp != null) {
      await prefs.setBool('otgiApp', otgiApp);
    }
    if (otgiChk != null) {
      await prefs.setBool('otgiChk', otgiChk);
    }
    if (bgApp != null) {
      await prefs.setBool('bgApp', bgApp);
    }
    if (bgChk != null) {
      await prefs.setBool('bgChk', bgChk);
    }
    if (marketingP != null) {
      await prefs.setBool('marketingP', marketingP);
    }
    final now = DateTime.now();
    final expiryTime = now.add(const Duration(days: 365));
    await prefs.setString('expiry', expiryTime.toIso8601String());
  }

  static Future<String?> getExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('expiry');
  }

  /// True while the saved session is still valid — the same expiry check the
  /// splash screen routes on. Logging out clears prefs, so the expiry is gone.
  /// Notification taps consult this so a logged-out user is never dropped into
  /// an authenticated screen.
  static Future<bool> hasActiveSession() async {
    final expiry = await getExpiry();
    if (expiry == null) return false;
    final expiryTime = DateTime.tryParse(expiry);
    return expiryTime != null && DateTime.now().isBefore(expiryTime);
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userName');
  }

  static Future<String?> getUName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('uName');
  }

  /// Name the chat backend knows this user by.
  ///
  /// Bellagio logins (API url on bty.world) are registered in chat under their
  /// U_Name, so every chat payload — sync, sender name, typing — has to carry
  /// that instead of the display name. Bally's and every other property keep
  /// using the display name. Falls back to the display name when U_Name is
  /// missing, since the login response does not always return it.
  static Future<String?> getChatUserName() async {
    final apiUrl = await getCurrentApiUrl() ?? '';
    if (apiUrl.contains('bty.world')) {
      final uName = await getUName();
      if (uName != null && uName.isNotEmpty) return uName;
    }
    return getUserName();
  }

  static Future<String?> getMobileNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mobileNumber');
  }

  static Future<String?> getUserLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userLevel');
  }

  static Future<String?> getSalesCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('salesCode');
  }

  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPreservingDeviceConfig(prefs);
  }

  static Future<String?> getMarketingCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('marketingCode');
    // Marketing_Code arrives via toString(), so a missing value lands as "null".
    if (code == null || code.isEmpty || code == 'null') return null;
    return code;
  }

  /// Sales code AD001 is the admin login. Overall data is theirs alone —
  /// every other sales code is scoped to their own numbers.
  static Future<bool> isAdminSalesCode() async {
    final salesCode = await getSalesCode();
    return salesCode != null && salesCode.trim().toUpperCase() == 'AD001';
  }

  /// MArketing_P from the login response — the user manages a marketing group,
  /// so their own numbers live under the marketing code, not the sales code.
  /// This is what unlocks the My Data / Overall Data switch in Settings.
  static Future<bool> getMarketingP() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('marketingP') ?? false;
  }

  /// Whether the user belongs to a marketing group at all. Marketing_Code 0
  /// means they don't, so there is no "my data" for them to look at — those
  /// users see overall data instead, whatever MArketing_P says.
  static Future<bool> hasOwnMarketingGroup() async {
    final code = await getMarketingCode();
    return code != null && code != '0';
  }

  /// The code to send as @Text1 on data-scoping reports (marketing performance,
  /// last three months, guests 9009-9011, birthdays 9004).
  ///
  /// A marketing-permission user asking for "Show My Data" is scoped by their
  /// marketing code — their rows are tagged with it rather than their sales
  /// code. Everyone else, and overall-data mode, keeps using the sales code.
  static Future<String?> getDataScopeCode({required bool isMyDataMode}) async {
    final salesCode = await getSalesCode();
    if (!isMyDataMode) return salesCode;
    if (!await getMarketingP()) return salesCode;
    if (!await hasOwnMarketingGroup()) return salesCode;
    return await getMarketingCode() ?? salesCode;
  }

  /// The code Iid 646 identifies the user by: AD001 is looked up by its sales
  /// code, every other user by their marketing code.
  static Future<String?> getAccessCheckCode() async {
    final salesCode = await getSalesCode();
    if (salesCode != null && salesCode.trim().toUpperCase() == 'AD001') {
      return salesCode;
    }
    return await getMarketingCode() ?? salesCode;
  }

  /// ReturnSatetus from Iid 646, stored right after login. True means the
  /// user's access is not restricted to their own marketing group, so screens
  /// that gate on the marketing code must skip their Access Denied check.
  ///
  /// Written after [saveUserData] — that call clears SharedPreferences first.
  static Future<void> saveAccessStatus(bool hasAccess) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('accessStatus', hasAccess);
  }

  static Future<bool> getAccessStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('accessStatus') ?? false;
  }

  static Future<void> saveAppVersion(String version) async {
    await _storage.write(key: _keyAppVersion, value: version);
  }

  static Future<String?> getAppVersion() async {
    return await _storage.read(key: _keyAppVersion);
  }

  static Future<bool> hasUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('userName') || prefs.containsKey('userLevel');
  }

  static Future<bool?> getMemProfSH() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('memProfSH');
  }

  static Future<bool?> getGiftApp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('giftApp');
  }

  static Future<bool?> getResApp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('resApp');
  }

  static Future<bool?> getResChk() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('resChk');
  }

  static Future<bool?> getOtgiApp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('otgiApp');
  }

  static Future<bool?> getOtgiChk() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('otgiChk');
  }

  static Future<bool?> getBgApp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('bgApp');
  }

  static Future<bool?> getBgChk() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('bgChk');
  }

  Future getToken() async {}
   static Future<void> saveCurrentLocation(LocationConfig location) async {
    await _writeDeviceConfig(_keyCurrentApiUrl, location.apiUrl);
    await _writeDeviceConfig(
      _keyCurrentLocation,
      jsonEncode(location.toJson()),
    );
  }

  /// Get current API URL
  static Future<String?> getCurrentApiUrl() async {
    return await _readDeviceConfig(_keyCurrentApiUrl);
  }

  /// Get current location
  static Future<LocationConfig?> getCurrentLocation() async {
    final locationJson = await _readDeviceConfig(_keyCurrentLocation);
    if (locationJson != null) {
      try {
        return LocationConfig.fromJson(jsonDecode(locationJson));
      } catch (_) {
        // A half-written or legacy-format entry is no better than none.
        return null;
      }
    }
    return null;
  }

  /// Save admin status
  static Future<void> saveAdminStatus(bool isAdmin) async {
    await _writeDeviceConfig(_keyIsAdmin, isAdmin.toString());
  }

  /// Check if user is admin
  static Future<bool> isAdmin() async {
    final isAdminStr = await _readDeviceConfig(_keyIsAdmin);
    return isAdminStr == 'true';
  }
   /// Save all locations (for admin)
  static Future<void> saveLocations(List<LocationConfig> locations) async {
    final locationsJson = jsonEncode(locations.map((loc) => loc.toJson()).toList());
    await _writeDeviceConfig(_keyLocations, locationsJson);
    await saveAdminStatus(true);
  }
  static Future<List<LocationConfig>> getLocations() async {
    final locationsJson = await _readDeviceConfig(_keyLocations);
    if (locationsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(locationsJson);
        return decoded.map((json) => LocationConfig.fromJson(json)).toList();
      } catch (_) {
        return [];
      }
    }
    return [];
  }
static Future<String> getStoredProcedureName() async {
  final location = await getCurrentLocation();
  return location?.storedProcedureName ?? 'sp_CRM_Common_API';
}
static Future<String?> getSmsGatewayUrl() async {
  final location = await getCurrentLocation();
  return location?.smsGatewayUrl;
}
  /// Clear location data (on logout)
  static Future<void> clearLocationData() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _deviceConfigKeys) {
      await prefs.remove(key);
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
  }

  // ── Device config (API URL, location, admin flag) ──────────────────────────
  //
  // These four keys used to live in secure storage alone. None of them is a
  // secret — the device-log endpoint hands them out for a device id — but
  // secure storage is exactly what an OEM keystore reset or an Auto Backup
  // restore wipes on Android, and losing the API URL points every request at a
  // hostless '/9009'. SharedPreferences is the source of truth now; secure
  // storage is written alongside it and read only as a migration fallback for
  // installs that still have the old copy.

  static const _deviceConfigKeys = <String>[
    _keyCurrentApiUrl,
    _keyCurrentLocation,
    _keyIsAdmin,
    _keyLocations,
  ];

  /// Wipes user state without taking the device config down with it.
  ///
  /// The config belongs to the device, not the account: it is fetched from the
  /// device-log endpoint against the device id. Both callers here reset
  /// SharedPreferences in the middle of a login — `completeLoginAfterOTP` calls
  /// [clearUserData] and then [saveUserData] — so a plain prefs.clear() would
  /// throw away the config the login flow had just fetched.
  static Future<void> _clearPreservingDeviceConfig(
    SharedPreferences prefs,
  ) async {
    final deviceConfig = <String, String>{
      for (final key in _deviceConfigKeys)
        if (prefs.getString(key) != null) key: prefs.getString(key)!,
    };
    await prefs.clear();
    for (final entry in deviceConfig.entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }

  static Future<void> _writeDeviceConfig(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // The mirror in SharedPreferences is what the app reads back.
    }
  }

  static Future<String?> _readDeviceConfig(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final mirrored = prefs.getString(key);
    if (mirrored != null && mirrored.isNotEmpty) return mirrored;

    String? legacy;
    try {
      legacy = await _storage.read(key: key);
    } catch (_) {
      legacy = null;
    }
    if (legacy != null && legacy.isNotEmpty) {
      await prefs.setString(key, legacy); // migrate forward, once
      return legacy;
    }
    return null;
  }
}
