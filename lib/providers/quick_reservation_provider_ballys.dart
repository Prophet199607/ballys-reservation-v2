import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:ballys_reservation_app/data/repositories/airport_repository.dart';
import 'package:ballys_reservation_app/data/repositories/authorization_level_repository.dart';
import 'package:ballys_reservation_app/data/repositories/contact_person_repository.dart';
import 'package:ballys_reservation_app/data/repositories/guest_repository.dart';
import 'package:ballys_reservation_app/data/repositories/quick_reservation_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/authorization_level.dart';
import 'package:ballys_reservation_app/models/guest_search_response.dart';
import 'package:ballys_reservation_app/models/reservation/airline_response.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';

/// Everything the quick reservation screen (Ballys) knows that is not a text
/// field: the reference data its dropdowns run on, the location-driven member
/// ID rules, and whether a request is in flight.
///
/// The form's own controllers stay on the widget — they are per-field editing
/// state — but nothing here needs a [setState] any more.
class QuickReservationBallysState {
  /// A request is in flight; the screen shows its blocking overlay.
  final bool isBusy;

  /// Contact persons for the air ticket tab (API 641).
  final List<String> contactPersons;

  /// Airlines for the air ticket dropdown (API 90156).
  final List<AirlineResponse> airlines;
  final bool airlinesLoading;

  /// Approvers for the "Request Approval From" dropdown
  /// (`GetAuthorizationLevels`), the same list the new reservation screen runs
  /// on. Empty until the fetch lands; a failed fetch leaves it empty rather
  /// than blocking the form.
  final List<AuthorizationLevel> authorizationLevels;
  final bool authorizationLevelsLoading;

  /// Bellagio runs on its own API host and uses "N/A" as the payment default
  /// instead of "NA".
  final bool isBellagio;

  /// Bellagio member IDs have no BM/BL/BN prefix, so the prefix dropdown is
  /// dropped and the number is the whole ID.
  final bool isNumericOnlyLocation;
  final List<String> prefixes;
  final String selectedPrefix;

  const QuickReservationBallysState({
    this.isBusy = false,
    this.contactPersons = const [],
    this.airlines = const [],
    this.airlinesLoading = false,
    this.authorizationLevels = const [],
    this.authorizationLevelsLoading = false,
    this.isBellagio = false,
    this.isNumericOnlyLocation = false,
    this.prefixes = const ['BM', 'BL', 'BN'],
    this.selectedPrefix = 'BM',
  });

  QuickReservationBallysState copyWith({
    bool? isBusy,
    List<String>? contactPersons,
    List<AirlineResponse>? airlines,
    bool? airlinesLoading,
    List<AuthorizationLevel>? authorizationLevels,
    bool? authorizationLevelsLoading,
    bool? isBellagio,
    bool? isNumericOnlyLocation,
    List<String>? prefixes,
    String? selectedPrefix,
  }) {
    return QuickReservationBallysState(
      isBusy: isBusy ?? this.isBusy,
      contactPersons: contactPersons ?? this.contactPersons,
      airlines: airlines ?? this.airlines,
      airlinesLoading: airlinesLoading ?? this.airlinesLoading,
      authorizationLevels: authorizationLevels ?? this.authorizationLevels,
      authorizationLevelsLoading:
          authorizationLevelsLoading ?? this.authorizationLevelsLoading,
      isBellagio: isBellagio ?? this.isBellagio,
      isNumericOnlyLocation: isNumericOnlyLocation ?? this.isNumericOnlyLocation,
      prefixes: prefixes ?? this.prefixes,
      selectedPrefix: selectedPrefix ?? this.selectedPrefix,
    );
  }
}

class QuickReservationBallysNotifier
    extends StateNotifier<QuickReservationBallysState> {
  final QuickReservationRepository reservationRepository;
  final ContactPersonRepository contactPersonRepository;
  final AirportRepository airportRepository;
  final GuestRepository guestRepository;
  final AuthorizationLevelRepository authorizationLevelRepository;

  QuickReservationBallysNotifier({
    required this.reservationRepository,
    required this.contactPersonRepository,
    required this.airportRepository,
    required this.guestRepository,
    required this.authorizationLevelRepository,
  }) : super(const QuickReservationBallysState());

  /// The current state, for callers holding the notifier rather than watching
  /// the provider — the screen captures this notifier in `initState` so it can
  /// still reach the state after an await that outlived the widget.
  QuickReservationBallysState get current => state;

  // ── Busy flag ───────────────────────────────────────────────────────────────

  void setBusy(bool busy) {
    if (state.isBusy == busy) return;
    state = state.copyWith(isBusy: busy);
  }

  // ── Reference data ──────────────────────────────────────────────────────────

  /// Reads the signed-in location and works out whether member IDs here carry a
  /// BM/BL/BN prefix.
  Future<void> loadLocationPrefix() async {
    final location = await StorageUtil.getCurrentLocation();
    if (location == null) return;
    final code = location.code.split('_').first;
    final isNumeric = code == 'BELLAGIO';
    if (isNumeric == state.isNumericOnlyLocation) return;
    state = state.copyWith(
      isNumericOnlyLocation: isNumeric,
      prefixes: isNumeric ? const <String>[] : const ['BM', 'BL', 'BN'],
      selectedPrefix: isNumeric ? '' : 'BM',
    );
  }

  void selectPrefix(String prefix) {
    state = state.copyWith(selectedPrefix: prefix);
  }

  /// Flags the Bellagio host and loads the air ticket contact persons. Both are
  /// read on entry; a failure leaves the previous list in place rather than
  /// blanking the dropdown.
  Future<void> loadContactPersons() async {
    try {
      final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
      state = state.copyWith(isBellagio: apiUrl.contains('bty.world'));

      final persons = await contactPersonRepository.getContactPersons();
      state = state.copyWith(contactPersons: persons);
    } catch (_) {}
  }

  /// The airline list is the same whatever route is picked, so it is fetched
  /// once. A failure empties the list — the dropdown then offers nothing rather
  /// than stale airlines.
  /// The whole body sits inside the try — including raising the flag. That
  /// write is the one that runs synchronously with the call, so it is the one
  /// that throws if a caller reaches this during a build; letting it escape
  /// used to skip the fetch entirely and strand the dropdown on an empty list.
  Future<void> loadAirlines() async {
    try {
      state = state.copyWith(airlinesLoading: true);
      final airlines = await airportRepository.getAirlines();
      state = state.copyWith(airlines: airlines, airlinesLoading: false);
    } catch (_) {
      state = state.copyWith(
          airlines: const <AirlineResponse>[], airlinesLoading: false);
    }
  }

  /// The approvers the reservation can be sent to. A failure empties the list —
  /// the dropdown is then disabled and the reservation still saves without an
  /// approver, the same as on the new reservation screen.
  Future<void> loadAuthorizationLevels() async {
    try {
      state = state.copyWith(authorizationLevelsLoading: true);
      final levels = await authorizationLevelRepository.getAuthorizationLevels();
      state = state.copyWith(
          authorizationLevels: levels, authorizationLevelsLoading: false);
    } catch (_) {
      state = state.copyWith(
          authorizationLevels: const <AuthorizationLevel>[],
          authorizationLevelsLoading: false);
    }
  }

  // ── Guest lookup ────────────────────────────────────────────────────────────

  /// Member search behind the search sheet. Returns an empty list rather than
  /// throwing, so the sheet always opens.
  Future<List<GuestSearchResponse>> searchGuest(int iid, String term) async {
    try {
      return await guestRepository.searchGuest(iid, term);
    } catch (_) {
      return const [];
    }
  }

  /// The full record behind a picked member ID (API 9021), or null when the
  /// lookup finds nothing or fails — the caller then falls back to the name and
  /// ID it already had.
  Future<GuestSearchResponse?> fetchGuestDetails(String mid) async {
    try {
      final guests = await guestRepository.searchGuest(9021, mid);
      return guests.isNotEmpty ? guests.first : null;
    } catch (_) {
      return null;
    }
  }

  /// Splits a full member ID into its prefix and number, honouring the
  /// numeric-only locations that have no prefix at all.
  (String, String) splitMemberId(String fullMemberId) {
    if (state.isNumericOnlyLocation) return ('', fullMemberId);
    for (final prefix in const ['BM', 'BL', 'BN']) {
      if (fullMemberId.startsWith(prefix)) {
        return (prefix, fullMemberId.substring(prefix.length));
      }
    }
    return ('BM', fullMemberId);
  }

  // ── Saving ──────────────────────────────────────────────────────────────────

  Future<QuickReservationResult> saveHotelReservation({
    required List<Map<String, dynamic>> members,
    required List<Map<String, dynamic>> extraMembers,
    required String liveRemarks,
    required bool hasFamilyMembers,
    AuthorizationLevel? approver,
    String paymentBy = '',
    String contactPerson = '',
    void Function(String label, Object? payload)? log,
  }) {
    return _guarded(() => reservationRepository.saveHotelReservation(
          members: members,
          extraMembers: extraMembers,
          liveRemarks: liveRemarks,
          hasFamilyMembers: hasFamilyMembers,
          approver: approver,
          paymentBy: paymentBy,
          contactPerson: contactPerson,
          log: log,
        ));
  }

  Future<QuickReservationResult> saveAirReservation({
    required List<Map<String, dynamic>> members,
    required List<Map<String, dynamic>> tickets,
    required List<Map<String, dynamic>> extraMembers,
    required String liveRemarks,
    required bool hasFamilyMembers,
    AuthorizationLevel? approver,
    String paymentBy = '',
    String contactPerson = '',
    void Function(String label, Object? payload)? log,
  }) {
    return _guarded(() => reservationRepository.saveAirReservation(
          members: members,
          tickets: tickets,
          extraMembers: extraMembers,
          liveRemarks: liveRemarks,
          hasFamilyMembers: hasFamilyMembers,
          approver: approver,
          paymentBy: paymentBy,
          contactPerson: contactPerson,
          log: log,
        ));
  }

  Future<QuickReservationResult> saveTransportReservation({
    required List<Map<String, dynamic>> members,
    void Function(String label, Object? payload)? log,
  }) {
    return _guarded(() => reservationRepository.saveTransportReservation(
          members: members,
          log: log,
        ));
  }

  /// Runs a save with the busy flag raised, turning a thrown error into a
  /// failed [QuickReservationResult] so callers have one thing to check. The
  /// flag is lowered even when the notifier has been disposed mid-request,
  /// which is why [mounted] guards the state write rather than the whole block.
  Future<QuickReservationResult> _guarded(
      Future<QuickReservationResult> Function() save) async {
    if (mounted) state = state.copyWith(isBusy: true);
    try {
      return await save();
    } catch (e) {
      return QuickReservationResult(success: false, message: e.toString());
    } finally {
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }
}

final quickReservationBallysStorageProvider =
    Provider<FlutterSecureStorage>((ref) => SecureStorage.instance);

final quickReservationBallysApiProvider = Provider<ApiService>((ref) {
  return ApiService(ref.read(quickReservationBallysStorageProvider));
});

final quickReservationRepositoryProvider =
    Provider<QuickReservationRepository>((ref) {
  return QuickReservationRepository(
      ref.read(quickReservationBallysApiProvider));
});

final quickReservationBallysProvider = StateNotifierProvider<
    QuickReservationBallysNotifier, QuickReservationBallysState>((ref) {
  final api = ref.read(quickReservationBallysApiProvider);
  return QuickReservationBallysNotifier(
    reservationRepository: ref.read(quickReservationRepositoryProvider),
    contactPersonRepository: ContactPersonRepository(api),
    airportRepository: AirportRepository(api),
    guestRepository: GuestRepository(api),
    authorizationLevelRepository: AuthorizationLevelRepository(api),
  );
});
