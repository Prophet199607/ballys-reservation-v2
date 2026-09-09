import 'dart:async';

import 'package:ballys_reservation_app/components/Event/events.dart';
import 'package:ballys_reservation_app/components/lastThreemonth.dart';
import 'package:ballys_reservation_app/components/location_selector_widget.dart';
import 'package:ballys_reservation_app/components/marketing_breakdown_chart_card.dart';
import 'package:ballys_reservation_app/components/marketing_performance.dart';
import 'package:ballys_reservation_app/models/guest_modal.dart';
import 'package:ballys_reservation_app/providers/BirthdayGiftIncreesNotifier.dart';
import 'package:ballys_reservation_app/providers/app_mode_setting_provider.dart';
import 'package:ballys_reservation_app/providers/app_notifications_provider.dart';
import 'package:ballys_reservation_app/providers/birthdays_provider.dart';
import 'package:ballys_reservation_app/providers/daily_walking_provider.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/providers/guests_provider.dart';
import 'package:ballys_reservation_app/providers/marketing_provider.dart';
import 'package:ballys_reservation_app/providers/reservation_provider.dart';
import 'package:ballys_reservation_app/providers/run_date_provider.dart';
import 'package:ballys_reservation_app/providers/special_gift_provider.dart';
import 'package:ballys_reservation_app/screens/member_visits.dart';
import 'package:ballys_reservation_app/screens/member_visits/sales_persons.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// 🔹 Provider for guest counts
final guestCountsProvider = StateProvider<Map<String, int?>>(
  (ref) => {"today": null, "yesterday": null, "monthly": null},
);
final homeScreenInitializedProvider = StateProvider<bool>((ref) => false);

// 🔹 Single provider for active event
final activeEventProvider = StateProvider<EventType?>((ref) => null);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver,ConnectivityMixin {
  String? userName;
  bool _isLoadingData = false;
  String? locationLogo;
  Timer? _eventTimer;
  @override
  bool get wantKeepAlive => true;
@override
  void onConnectivityRestored() {
    _manualRefresh(); // reload data when back online
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserName();
    _loadLocationLogo();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 🔹 Fetch server run date via provider
      ref.read(runDateProvider.notifier).getRunDate();

      final userName = await StorageUtil.getUserName();
      final salesCode = await StorageUtil.getSalesCode();

      if (userName == null || salesCode == null) {
        ref.read(homeScreenInitializedProvider.notifier).state = false;
        ref.read(guestsProvider.notifier).resetData();
        ref.read(guestCountsProvider.notifier).state = {
          "today": null,
          "yesterday": null,
          "monthly": null,
        };
        return;
      }

      final hasInitialized = ref.read(homeScreenInitializedProvider);
      if (!hasInitialized) {
        ref.read(homeScreenInitializedProvider.notifier).state = true;
        _initializeAppMode();
        _loadGuestData();
        _checkAndShowEvent();
      } else {
    final guestsState = ref.read(guestsProvider);

    // ✅ Restore whatever counts are already in guestsProvider immediately
    ref.read(guestCountsProvider.notifier).state = {
      "today": guestsState.todayGuests.isEmpty
          ? null
          : guestsState.todayGuests.where((g) => g.mid.isNotEmpty).length,
      "yesterday": guestsState.yesterdayGuests.isEmpty
          ? null
          : guestsState.yesterdayGuests.where((g) => g.mid.isNotEmpty).length,
      "monthly": guestsState.monthlyGuests.isEmpty
          ? null
          : guestsState.monthlyGuests.where((g) => g.mid.isNotEmpty).length,
    };

    // ✅ Only reload keys that are genuinely missing
    final bool anyMissing =
        guestsState.todayGuests.isEmpty ||
        guestsState.yesterdayGuests.isEmpty ||
        guestsState.monthlyGuests.isEmpty;

    if (anyMissing) {
      _loadMissingData(guestsState);
    }
  }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 👈 Add this
    super.dispose();
  }

  /// 🎉 Unified event checking method
  void _checkAndShowEvent() {
    final now = DateTime.now();
    final currentEvent = ref.read(activeEventProvider);

    EventType? eventToShow;
    int displayDuration = 4;

    if (now.month == 12) {
      eventToShow = EventType.christmas;
      displayDuration = 4;
    } else if (now.month == 1 && now.day == 13) {
      eventToShow = EventType.lohri;
      displayDuration = 4;
    } else if (now.month == 1 && now.day == 14) {
      eventToShow = EventType.thaiPongal;
      displayDuration = 4;
    } else if (now.month == 1 && now.day == 26) {
      eventToShow = EventType.republicDay;
      displayDuration = 4;
    } else if (now.month == 2 && now.day == 4) {
      eventToShow = EventType.independence;
      displayDuration = 4;
    } else if (now.month == 2 && now.day == 14) {
      eventToShow = EventType.valentineDay;
      displayDuration = 4;
    } else if (now.month == 2 && now.day == 17) {
      eventToShow = EventType.chineseNewYear;
      displayDuration = 4;
    } else if (now.month == 3 && now.day == 4) {
      eventToShow = EventType.holi;
      displayDuration = 4;
    } else if (now.month == 3 && now.day == 8) {
      eventToShow = EventType.happyWomen;
      displayDuration = 4;
    } else if (now.month == 3 && now.day == 21) {
      eventToShow = EventType.ramadan;
      displayDuration = 4;
    } else if (now.month == 4 && now.day == 5) {
      eventToShow = EventType.easter;
      displayDuration = 4;
    } else if (now.month == 4 &&
        (now.day == 13 || now.day == 14 || now.day == 15)) {
      eventToShow = EventType.sinhalatamilNewYear;
      displayDuration = 4;
    } else if (now.month == 4 && now.day == 22) {
      eventToShow = EventType.earthDay;
      displayDuration = 4;
    } else if (now.month == 5 && now.day == 1) {
      eventToShow = EventType.labourDay;
      displayDuration = 4;
    } else if (now.month == 5 && now.day == 11) {
      eventToShow = EventType.mothersDay;
      displayDuration = 4;
    } else if (now.month == 5 && now.day == 26) {
      eventToShow = EventType.eidAlAdha;
      displayDuration = 4;
    } else if (now.month == 6 && now.day == 5) {
      eventToShow = EventType.environmentDay;
      displayDuration = 4;
    } else if (now.month == 6 && now.day == 15) {
      eventToShow = EventType.fathersDay;
      displayDuration = 4;
    } else if (now.month == 7 && now.day == 30) {
      eventToShow = EventType.friendshipDay;
      displayDuration = 4;
    } else if (now.month == 8 && now.day == 12) {
      eventToShow = EventType.youthDay;
      displayDuration = 4;
    } else if (now.month == 8 && now.day == 14) {
      eventToShow = EventType.pakistanIndependenceDay;
      displayDuration = 4;
    } else if (now.month == 8 && now.day == 15) {
      eventToShow = EventType.indianIndependenceDay;
      displayDuration = 4;
    } else if (now.month == 8 && now.day == 28) {
      eventToShow = EventType.rakshaBandhan;
      displayDuration = 4;
    } else if (now.month == 9 && now.day == 4) {
      eventToShow = EventType.janmashtamiEvent;
      displayDuration = 4;
    } else if (now.month == 9 && now.day == 21) {
      eventToShow = EventType.peaceDay;
      displayDuration = 4;
    } else if (now.month == 9 && now.day == 25) {
      eventToShow = EventType.autumnFestival;
      displayDuration = 4;
    } else if (now.month == 9 && now.day == 27) {
      eventToShow = EventType.travellingBags;
      displayDuration = 4;
    } else if (now.month == 10 && now.day == 31) {
      eventToShow = EventType.halloween;
      displayDuration = 4;
    } else if (now.month == 11 && now.day == 8) {
      eventToShow = EventType.diwali;
      displayDuration = 4;
    }

    // The notifier is captured up-front: activeEventProvider is a root (non
    // autoDispose) provider, so it outlives this widget. Dismissing through the
    // captured notifier instead of `ref` means the overlay is still cleared when
    // HomeScreen is disposed before the timer fires — otherwise the event stays
    // stuck on screen for the rest of the app's life.
    final notifier = ref.read(activeEventProvider.notifier);

    if (eventToShow != null) {
      notifier.state = eventToShow;
      _eventTimer?.cancel();
      _eventTimer = Timer(Duration(seconds: displayDuration), () {
        notifier.state = null;
      });
    } else if (currentEvent != null) {
      // Stale overlay left behind by a previous mount — nothing is due today.
      notifier.state = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      ref.read(runDateProvider.notifier).reset();
      ref.read(runDateProvider.notifier).getRunDate();
      // Pick up notifications delivered while the app was in the background.
      ref.read(appNotificationsProvider.notifier).load();
    }
  }
Future<void> _loadMissingData(GuestsState guestsState) async {
  final currentMode = ref.read(appmodeSettingsProvider).appMode;
  final scopeCode = await _guestScopeCode(currentMode);
  if (scopeCode == null || scopeCode.isEmpty) return;

  // Fire only the calls that are missing — don't touch already-loaded data
  if (guestsState.todayGuests.isEmpty) {
    unawaited(_fetchAndUpdateCount(9009, "today", scopeCode, currentMode));
  }
  if (guestsState.yesterdayGuests.isEmpty) {
    unawaited(_fetchAndUpdateCount(9010, "yesterday", scopeCode, currentMode));
  }
  if (guestsState.monthlyGuests.isEmpty) {
    unawaited(_fetchAndUpdateCount(9011, "monthly", scopeCode, currentMode));
  }
}

  // Guest reports are scoped by sales code, except for marketing-permission
  // users viewing "My Data" — their guests hang off the marketing code.
  Future<String?> _guestScopeCode(AppMode mode) {
    return StorageUtil.getDataScopeCode(isMyDataMode: mode == AppMode.myData);
  }
  Future<void> _initializeAppMode() async {
    try {
      final salesCode = await StorageUtil.getSalesCode();
      if (salesCode != null) {
        ref.read(appmodeSettingsProvider.notifier).setSalesCode(salesCode);
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _loadUserName() async {
    final name = await StorageUtil.getUserName();
    if (mounted) {
      setState(() {
        userName = name;
      });
    }
  }

  // Future<void> _loadGuestData() async {
  //   if (_isLoadingData) return;
  //   _isLoadingData = true;

  //   String? salesCode = await StorageUtil.getSalesCode();
  //   if (salesCode == null || salesCode.isEmpty) {
  //     _isLoadingData = false;
  //     return;
  //   }

  //   try {
  //     ref.read(guestCountsProvider.notifier).state = {
  //       "today": null,
  //       "yesterday": null,
  //       "monthly": null,
  //     };

  //     final currentMode = ref.read(appmodeSettingsProvider).appMode;
  //     ref.read(guestsProvider.notifier).resetData();

  //     // AFTER — staggered to avoid server collision
  //     await ref
  //         .read(guestsProvider.notifier)
  //         .getGuestData(9009, salesCode, currentMode);
  //     await Future.delayed(const Duration(milliseconds: 300));
  //     await ref
  //         .read(guestsProvider.notifier)
  //         .getGuestData(9010, salesCode, currentMode);
  //     await Future.delayed(const Duration(milliseconds: 300));
  //     await ref
  //         .read(guestsProvider.notifier)
  //         .getGuestData(9011, salesCode, currentMode);

  //     final guestsState = ref.read(guestsProvider);
  //     final finalMode = ref.read(appmodeSettingsProvider).appMode;

  //     if (currentMode != finalMode) {
  //       _isLoadingData = false;
  //       _loadGuestData();
  //       return;
  //     }

  //     ref.read(guestCountsProvider.notifier).state = {
  //       "today": guestsState.todayGuests.where((g) => g.mid.isNotEmpty).length,
  //       "yesterday": guestsState.yesterdayGuests
  //           .where((g) => g.mid.isNotEmpty)
  //           .length,
  //       "monthly": guestsState.monthlyGuests
  //           .where((g) => g.mid.isNotEmpty)
  //           .length,
  //     };
  //   } catch (e) {
  //     ref.read(guestCountsProvider.notifier).state = {
  //       "today": 0,
  //       "yesterday": 0,
  //       "monthly": 0,
  //     };
  //   } finally {
  //     _isLoadingData = false;
  //   }
  // }
Future<void> _loadGuestData() async {
  if (_isLoadingData) return;
  _isLoadingData = true;

  final currentMode = ref.read(appmodeSettingsProvider).appMode;
  final scopeCode = await _guestScopeCode(currentMode);
  if (scopeCode == null || scopeCode.isEmpty) {
    _isLoadingData = false;
    return;
  }

  ref.read(guestsProvider.notifier).resetData();
  ref.read(guestCountsProvider.notifier).state = {
    "today": null,
    "yesterday": null,
    "monthly": null,
  };

  // 🔥 Fire all 3 in background — no await, does NOT block navigation
  unawaited(_fetchAndUpdateCount(9009, "today", scopeCode, currentMode));
  unawaited(_fetchAndUpdateCount(9010, "yesterday", scopeCode, currentMode));
  unawaited(_fetchAndUpdateCount(9011, "monthly", scopeCode, currentMode));

  _isLoadingData = false; // immediately released
}

Future<void> _fetchAndUpdateCount(
  int iid,
  String key,
  String scopeCode,
  AppMode mode,
) async {
  try {
    await ref.read(guestsProvider.notifier).getGuestData(iid, scopeCode, mode);

    if (!mounted) return; // user navigated away — do nothing

    final guestsState = ref.read(guestsProvider);
    final List<Guest> guests = switch (key) {
      "today"     => guestsState.todayGuests,
      "yesterday" => guestsState.yesterdayGuests,
      "monthly"   => guestsState.monthlyGuests,
      _           => [],
    };

    ref.read(guestCountsProvider.notifier).state = {
      ...ref.read(guestCountsProvider),
      key: guests.where((g) => g.mid.isNotEmpty).length,
    };
  } catch (_) {
    if (!mounted) return;
    ref.read(guestCountsProvider.notifier).state = {
      ...ref.read(guestCountsProvider),
      key: 0,
    };
  }
}
  Future<void> _manualRefresh() async {
    if (_isLoadingData) return;

    setState(() {
      userName = null;
    });

    // 🔹 Reset run date so spinner shows while re-fetching
    ref.read(runDateProvider.notifier).reset();

    ref.read(guestCountsProvider.notifier).state = {
      "today": null,
      "yesterday": null,
      "monthly": null,
    };

    await Future.wait<void>([
      _loadUserName(),
      _loadGuestData(),
      ref.read(runDateProvider.notifier).getRunDate(),
      ref.read(appNotificationsProvider.notifier).load(),
    ]);
  }

  Future<void> _loadLocationLogo() async {
    final location = await StorageUtil.getCurrentLocation();
    if (mounted) {
      setState(() {
        locationLogo = location?.imageUrl;
      });
    }
  }

  /// Bell in the app bar with a red badge showing how many notifications
  /// arrived since the list was last opened.
  Widget _buildNotificationBell(int unreadCount) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          padding: const EdgeInsets.all(10.0),
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none, size: 30),
          onPressed: () => context.push('/home/notifications'),
        ),
        if (unreadCount > 0)
          Positioned(
            top: 6,
            right: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Level 3 users can see the counts but not drill into the guest lists -
  /// tapping a count box shows the same Access Denied dialog used elsewhere.
  void _showAccessDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    size: 50,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Access Denied",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Got It",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildCountBox({
    required int? count,
    required String label,
    required Color color,
  }) {
    final formatter = NumberFormat.decimalPattern();
    return SizedBox(
      height: 150,
      child: Card(
        color: color,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                count == null
                    ? const SizedBox(
                        height: 40,
                        width: 40,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : Text(
                        formatter.format(count),
                        style: const TextStyle(
                          fontSize: 40.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.normal,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final guests = ref.watch(guestsProvider);
    final counts = ref.watch(guestCountsProvider);
    final activeEvent = ref.watch(activeEventProvider);
    final unreadNotifications = ref.watch(unreadNotificationCountProvider);

    // Watch the new state
    final runDateState = ref.watch(runDateProvider);
    final formattedDate = runDateState.runDate != null
        ? DateFormat('EEEE, MMM d, yyyy').format(runDateState.runDate!.date)
        : null;

    ref.listen<AppModeSettings>(appmodeSettingsProvider, (prev, next) {
      if (prev?.appMode != next.appMode) {
        ref.read(guestCountsProvider.notifier).state = {
          "today": null,
          "yesterday": null,
          "monthly": null,
        };
        Future.delayed(const Duration(milliseconds: 100), () {
          _loadGuestData();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          userName != null ? 'Welcome, $userName ' : 'Loading...',
          style: const TextStyle(fontSize: 16, fontFamily: 'ABCArizonaFlare'),
        ),
        actions: [
          _buildNotificationBell(unreadNotifications),
          IconButton(
            padding: const EdgeInsets.all(10.0),
            icon: const Icon(Icons.refresh, size: 30),
            onPressed: _manualRefresh,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  // 🔹 Date card — spinner while runDate is null (loading)
                  FutureBuilder<bool>(
                    future: StorageUtil.isAdmin(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data == true) {
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8.0),
                          child: Card(
                            elevation: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 2.0,
                              ),
                              child: Row(
                                children: [
                                  // Bally's Logo
                                  Container(
                                    width: 60,
                                    height: 60,
                                    // decoration: BoxDecoration(
                                    //   shape: BoxShape.circle,
                                    //   color: Colors.grey.shade200,
                                    // ),
                                    // clipBehavior: Clip.antiAlias,
                                    child:
                                        locationLogo != null &&
                                            locationLogo!.isNotEmpty
                                        ? Image.network(
                                            locationLogo!,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                                  Icons.business,
                                                  size: 28,
                                                ),
                                          )
                                        : const Icon(Icons.business, size: 28),
                                  ),

                                  const SizedBox(width: 8),

                                  // Location Dropdown - Takes remaining space
                                  Expanded(
                                    child: LocationSelectorWidget(
                                      onLocationChanged: () {
                                        // Refresh data when location changes
                                        _manualRefresh();
                                        _loadLocationLogo();

                                        ref
                                            .read(reservationProvider.notifier)
                                            .clearReservations();
                                        ref
                                            .read(giftProvider.notifier)
                                            .clearGifts();
                                        ref
                                            .read(birthdayProvider.notifier)
                                            .clearBirthdays();
                                        ref
                                            .read(dailyWalkingProvider.notifier)
                                            .clearDailyWalkingGuests();
                                        ref
                                            .read(
                                              birthdayGiftIncreesProvider
                                                  .notifier,
                                            )
                                            .clearbirthdayGifts();
                                        ref
                                            .read(marketingProvider.notifier)
                                            .clearMarketing();
                                      },
                                    ),
                                  ),

                                  // Settings Icon
                                  // IconButton(
                                  //   icon: const Icon(
                                  //     Icons.tune,
                                  //     color: Colors.black54,
                                  //     size: 26,
                                  //   ),
                                  //   onPressed: () {
                                  //     // Handle settings action
                                  //   },
                                  // ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      // Return empty container for non-admin users
                      return const SizedBox.shrink();
                    },
                  ),

                  Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 1.0),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: Colors.blue,
                          ),
                          // Replace the formattedDate == null check with:
                          const SizedBox(width: 6),
                          runDateState.isLoading
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.blue,
                                  ),
                                )
                              : runDateState.hasError
                              ? GestureDetector(
                                  onTap: () => ref
                                      .read(runDateProvider.notifier)
                                      .getRunDate(),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.refresh,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Tap to retry',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                )
                              : Text(
                                  formattedDate ?? '',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),

                  // Performance heading
                  Consumer(
                    builder: (context, ref, _) {
                      final appMode = ref
                          .watch(appmodeSettingsProvider)
                          .appMode;
                      final heading = appMode == AppMode.myData
                          ? "MY PERFORMANCE"
                          : "OVERALL PERFORMANCE";
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              heading,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Today & Yesterday row
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final userLevel = await StorageUtil.getUserLevel();
                            if (!mounted) return;
                            if (userLevel == '3') {
                              _showAccessDeniedDialog();
                              return;
                            }
                            if (userLevel == '1') {
                              context.push(
                                '/home/sales-persons',
                                extra: {
                                  'title': 'All Sales Persons (Today)',
                                  'salesPersons': groupByMGroup(
                                    guests.todayGuests,
                                  ),
                                },
                              );
                            } else {
                              context.push(
                                '/home/member-visits',
                                extra: {
                                  'title': 'Today Member Visits',
                                  'guestList': guests.todayGuests,
                                },
                              );
                            }
                          },
                          child: buildCountBox(
                            count: counts["today"],
                            label: "Today",
                            color: const Color.fromARGB(255, 228, 117, 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final userLevel = await StorageUtil.getUserLevel();
                            if (!mounted) return;
                            if (userLevel == '3') {
                              _showAccessDeniedDialog();
                              return;
                            }
                            if (userLevel == '1') {
                              context.push(
                                '/home/sales-persons',
                                extra: {
                                  'title': 'All Sales Persons (Yesterday)',
                                  'salesPersons': groupByMGroup(
                                    guests.yesterdayGuests,
                                  ),
                                },
                              );
                            } else {
                              context.push(
                                '/home/member-visits',
                                extra: {
                                  'title': 'Yesterday Member Visits',
                                  'guestList': guests.yesterdayGuests,
                                },
                              );
                            }
                          },
                          child: buildCountBox(
                            count: counts["yesterday"],
                            label: "Yesterday",
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 3),

                  // Monthly row
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final userLevel = await StorageUtil.getUserLevel();
                            if (!mounted) return;
                            if (userLevel == '3') {
                              _showAccessDeniedDialog();
                              return;
                            }
                            if (userLevel == '1') {
                              context.push(
                                '/home/sales-persons',
                                extra: {
                                  'title': 'All Sales Persons (Monthly)',
                                  'salesPersons': groupByMGroup(
                                    guests.monthlyGuests,
                                  ),
                                },
                              );
                            } else {
                              context.push(
                                '/home/member-visits',
                                extra: {
                                  'title': 'Monthly Member Visits',
                                  'guestList': guests.monthlyGuests,
                                },
                              );
                            }
                          },
                          child: buildCountBox(
                            count: counts["monthly"],
                            label: "Monthly",
                            color: const Color.fromARGB(255, 42, 125, 192),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  const MarketingBreakdownHalfPieCard(),
                  const SizedBox(height: 8),
                  const MarketingPerformanceWidget(),
                  const SizedBox(height: 8),
const LastThreeMonthsGuestCard(), 
                ],
              ),
            ),
          ),

          EventOverlay(activeEvent: activeEvent),
        ],
      ),
    );
  }
}
