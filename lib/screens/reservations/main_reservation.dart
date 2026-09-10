import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

class ReservationMainScreen extends ConsumerStatefulWidget {
  const ReservationMainScreen({super.key});

  @override
  ConsumerState<ReservationMainScreen> createState() =>
      _ReservationMainScreenState();
}

class _ReservationMainScreenState extends ConsumerState<ReservationMainScreen>
    with ConnectivityMixin {
  /// Transport is a Bellagio-only (bty.world) feature.
  bool _isBellagio = false;

  /// Group Reservation is a Ballys-only card. Resolved up front rather than on
  /// tap, since it decides whether the card is drawn at all.
  bool _isBallys = false;

  /// Level 3 users may open this screen but not Reservations, Quick
  /// Reservation, Group Reservation or Amendments - those show Access Denied.
  String? _userLevel;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  Future<void> _resolveLocation() async {
    final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
    final isBallys = await _isBallysLocation();
    final userLevel = await StorageUtil.getUserLevel();
    if (!mounted) return;
    setState(() {
      _isBellagio = apiUrl.contains('bty.world');
      _isBallys = isBallys;
      _userLevel = userLevel;
    });
  }

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

  /// True when the logged-in device/user is on the Ballys location, which
  /// uses its own Quick Reservation flow.
  Future<bool> _isBallysLocation() async {
    final location = await StorageUtil.getCurrentLocation();
    if (location == null) return false;
    return location.code.split('_').first.toUpperCase() == 'BALLYS';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fontSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Reservations'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/menu');
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // ── Reservations ────────────────────────────────────────
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          if (_userLevel == '3') {
                            _showAccessDeniedDialog();
                            return;
                          }
                          // Ballys logins get their own Reservations screen;
                          // every other location keeps the shared one.
                          final isBallys = await _isBallysLocation();
                          if (!context.mounted) return;
                          context.go(
                            isBallys
                                ? '/reservationMain/reservations-ballys'
                                : '/reservationMain/reservations',
                          );
                        },
                        child: Card(
                          color: Colors.orange[700],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              children: [
                                Lottie.asset(
                                  'assets/icon/menu_screen/reservation.json',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.contain,
                                ),
                                const Text(
                                  'Reservations',
                                  style: TextStyle(
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
                    ),

                    // ── Quick Reservation ────────────────────────────────────
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          if (_userLevel == '3') {
                            _showAccessDeniedDialog();
                            return;
                          }
                          // Ballys logins get their own Quick Reservation
                          // screen; every other location keeps the shared one.
                          final isBallys = await _isBallysLocation();
                          if (!context.mounted) return;
                          context.go(
                            isBallys
                                ? '/reservationMain/quick-reservation-ballys'
                                : '/reservationMain/quick-reservation',
                          );
                        },
                        child: Card(
                          color: const Color.fromARGB(255, 4, 158, 143),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              children: [
                                Lottie.asset(
                                  'assets/icon/menu_screen/packageGuest.json',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.contain,
                                ),
                                const Text(
                                  'Quick Reservation',
                                  style: TextStyle(
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
                    ),
                  ],
                ),

                // ── Group Reservation (Ballys only) ──────────────────────
                // For a party arriving together: one lead guest plus an
                // uploaded sheet naming everybody else.
                if (_isBallys)
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_userLevel == '3') {
                              _showAccessDeniedDialog();
                              return;
                            }
                            context.go(
                              '/reservationMain/group-reservation-ballys',
                            );
                          },
                          child: Card(
                            color: const Color.fromARGB(255, 103, 58, 183),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                children: const [
                                  Icon(
                                    Icons.groups,
                                    size: 80,
                                    color: Colors.white,
                                  ),
                                  Text(
                                    'Group Reservation',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
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
                      ),
                      // ── Amendments (Ballys only) ──────────────────
                      // Everything raised off a confirmed reservation —
                      // hotel and air ticket changes — waiting to be
                      // checked and approved.
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_userLevel == '3') {
                              _showAccessDeniedDialog();
                              return;
                            }
                            context.go('/reservationMain/amendments-ballys');
                          },
                          child: Card(
                            color: const Color.fromARGB(255, 0, 121, 107),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                children: const [
                                  Icon(
                                    Icons.edit_note,
                                    size: 80,
                                    color: Colors.white,
                                  ),
                                  Text(
                                    'Amendments',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
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
                      ),
                    ],
                  ),

                // ── Coordinator Request (Ballys only) ────────────────────
                // For executives who would rather hand the booking to a
                // coordinator than key the reservation in themselves.
                if (_isBallys)
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            context.go(
                              '/reservationMain/coordinator-requests-ballys',
                            );
                          },
                          child: Card(
                            color: const Color.fromARGB(255, 63, 81, 181),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                children: const [
                                  Icon(
                                    Icons.support_agent,
                                    size: 80,
                                    color: Colors.white,
                                  ),
                                  Text(
                                    'Coordinator Request',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
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
                      ),
                      // Keeps the card the same width as the cards above.
                      const Expanded(child: SizedBox()),
                    ],
                  ),

                // ── Transport (Bellagio only) ────────────────────────────
                if (_isBellagio)
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            context.go('/reservationMain/transport');
                          },
                          child: Card(
                            color: const Color.fromARGB(255, 63, 81, 181),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                children: const [
                                  Icon(
                                    Icons.directions_car_filled,
                                    size: 80,
                                    color: Colors.white,
                                  ),
                                  Text(
                                    'Transport',
                                    style: TextStyle(
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
                      ),
                      // Keeps the card the same width as the cards above.
                      const Expanded(child: SizedBox()),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}