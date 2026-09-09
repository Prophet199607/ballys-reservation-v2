import 'dart:convert';
import 'dart:math' as math;

import 'package:ballys_reservation_app/components/package_amount_field_ballys.dart';
import 'package:ballys_reservation_app/components/passport_upload_widget_ballys.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:country_picker/country_picker.dart';
import 'package:ballys_reservation_app/components/air_ticket_class_count_selector.dart';
// import 'package:ballys_reservation_app/components/passport_upload_widget.dart';
// import 'package:ballys_reservation_app/components/package_amount_field.dart';

import 'package:ballys_reservation_app/components/bottom_sheets/member_search-new_sheet.dart';
import 'package:ballys_reservation_app/components/guest_deatils_view_spGift.dart';
import 'package:ballys_reservation_app/components/location_search_field.dart';
import 'package:ballys_reservation_app/data/repositories/quick_reservation_repository.dart';
import 'package:ballys_reservation_app/models/airport_search_response.dart';
import 'package:ballys_reservation_app/models/authorization_level.dart';
import 'package:ballys_reservation_app/models/guest_modal.dart';
import 'package:ballys_reservation_app/models/guest_reservation_entryBallys.dart';
import 'package:ballys_reservation_app/models/guest_search_response.dart';
import 'package:ballys_reservation_app/models/reservation/assigned_guest.dart';
import 'package:ballys_reservation_app/models/reservation/air_ticket_class_count.dart';
import 'package:ballys_reservation_app/models/reservation/airline_response.dart';
import 'package:ballys_reservation_app/models/reservation/flight_bookng_ballys.dart';
import 'package:ballys_reservation_app/models/reservation/flight_sector_entry.dart';
import 'package:ballys_reservation_app/models/reservation/hotel_location.dart';
import 'package:ballys_reservation_app/models/reservation/hotel_room_catalog_entry.dart';
import 'package:ballys_reservation_app/models/reservation/hotel_response.dart';
import 'package:ballys_reservation_app/models/reservation/quick_hotel_entry.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/providers/hotel_catalog_provider.dart';
import 'package:ballys_reservation_app/providers/airports_provider.dart';
import 'package:ballys_reservation_app/providers/quick_reservation_provider_ballys.dart';
// import 'package:ballys_reservation_app/providers/new_reservation_provider.dart';
import 'package:ballys_reservation_app/providers/selected_guest_provider.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:intl/intl.dart';

enum _Section { airTicket, hotel, transport }

// Transport tab dropdown options.
const List<String> kCarTypes = [
  'Normal Car',
  'SUV / Jeep',
  'Voxy',
  'Prado',
  'Benz',
  'Limousine',
  'Alphard',
];

const List<String> kHireTypes = [
  'Pickup',
  'Drop',
];

// Digit count allowed in the contact number, excluding the country code.
const int kMinContactDigits = 9;
const int kMaxContactDigits = 10;

const TextStyle kInputTextStyle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w600,
  color: Colors.black,
);

class QuickReservationBallysScreen extends ConsumerStatefulWidget {
  const QuickReservationBallysScreen({super.key});
  @override
  ConsumerState<QuickReservationBallysScreen> createState() =>
      _QuickReservationBallysScreenState();
}

class _QuickReservationBallysScreenState extends ConsumerState<QuickReservationBallysScreen>
    with TickerProviderStateMixin, ConnectivityMixin {
  _Section _activeSection = _Section.airTicket;

  final _hotelFormKey = GlobalKey<FormState>();
  final _airFormKey = GlobalKey<FormState>();
  final _transportFormKey = GlobalKey<FormState>();

  /// The Hotel and Air Ticket tabs are two-step forms — who the reservation is
  /// for, then what is being booked — so the guest half gets its own [Form].
  /// "Next" can then check just the guest without the booking fields, which are
  /// still blank at that point, complaining first.
  ///
  /// Both halves stay in the widget tree (see the [IndexedStack] in
  /// [_HotelForm] / [_AirForm]) rather than being swapped out, so a save from
  /// the booking step still validates the guest step — and can send the user
  /// back to it when something there is wrong.
  final _hotelGuestFormKey = GlobalKey<FormState>();
  final _airGuestFormKey = GlobalKey<FormState>();

  /// Which step of the Hotel / Air Ticket tab is on screen: 0 guest, 1 booking.
  /// Transport is a single form and has no step of its own.
  int _hotelStep = 0;
  int _airStep = 0;

  /// Reference data, location rules and the in-flight flag all live on
  /// [quickReservationBallysProvider]; the widget keeps only its controllers.
  ///
  /// Captured in [initState] rather than read through `ref` at each use: these
  /// are routinely touched after an await, by which point the screen may be
  /// gone and `ref` unusable. Lowering the overlay has to land even then — the
  /// provider outlives the screen, so a flag left raised would greet the next
  /// visit with a stuck overlay.
  late final QuickReservationBallysNotifier _quickNotifier;

  /// The current provider state. [build] watches the provider, so a rebuild is
  /// already queued whenever this would return something new.
  QuickReservationBallysState get _quick => _quickNotifier.current;

  bool get _isLoading => _quick.isBusy;

  void _setBusy(bool busy) => _quickNotifier.setBusy(busy);

  bool get _isNumericOnlyLocation => _quick.isNumericOnlyLocation;
  List<String> get _prefixes => _quick.prefixes;
  String get _selectedPrefix => _quick.selectedPrefix;

  final _sharedMemberId = TextEditingController();
  final _sharedMidNumber = TextEditingController();
  final _sharedGuestName = TextEditingController();
  final _sharedPackageAmount = TextEditingController();

  /// The "Shared" tick beside the guest's package amount: they are on a shared
  /// package rather than one of their own. Recorded in its own right — a shared
  /// guest may still carry an amount — and travels as `IsSharedAmount`, the
  /// same way the new reservation screen sends it.
  bool _sharedPackageShared = false;
  // final _sharedReservationNo = TextEditingController();
  bool _sharedGuestCardVisible = false;

  /// Whether family members travel with the guest in the form — the first
  /// guest's own tick, matching the new reservation screen. Extra members carry
  /// their own on each card.
  bool _sharedHasFamilyMembers = false;

  // ── HOTEL members list ──────────────────────────────────────────────────────
  // Each member now has a 'hotels' list (List<QuickHotelEntry>) plus identity fields.
  List<Map<String, dynamic>> _hotelMembers = [];

  // Current hotel form fields (one hotel being edited at a time per guest)
  final _h_noOfRooms = TextEditingController(text: '1');
  final _h_noOfPax = TextEditingController(text: '1');
  final _h_noOfChildren = TextEditingController(text: '0');
  final _h_mealPlan = TextEditingController();
  // No default: "Payment By" is mandatory and starts unanswered.
  final _h_paymentBy = TextEditingController();
  final _h_remarks = TextEditingController();
  final _h_marketingPerson = TextEditingController();
  final _h_approvedBy = TextEditingController();
  final _h_arrivalCtrl = TextEditingController();
  final _h_departureCtrl = TextEditingController();

  // ── Approval routing ────────────────────────────────────────────────────
  // Who the reservation is being sent to for approval, from
  // `GetAuthorizationLevels` — the same dropdown the new reservation screen
  // carries. Held per tab because each tab saves its own reservation, the way
  // the remarks field is.
  AuthorizationLevel? _h_approver;
  AuthorizationLevel? _a_approver;

  DateTime? _h_arrivalDate;
  DateTime? _h_departureDate;

  String _h_eciLco = 'NA';

  /// Asked before the hotel: the hotel dropdown only offers hotels of this
  /// type, so a city stay is never picked off the out-of-Colombo list.
  HotelLocation? _selectedHotelLocation;
  Map<String, dynamic>? _selectedHotel;
  String? _selectedHotelName;
  double? _selectedHotelId;
  Map<String, dynamic>? _selectedRoomCategory;
  int? _selectedRoomCategoryId;
  String? _selectedRoomCategoryName;
  Map<String, dynamic>? _selectedRoomType;
  int? _selectedRoomTypeId;
  String? _selectedRoomTypeName;
  List<Map<String, dynamic>> _roomCategories = [];
  List<Map<String, dynamic>> _roomTypes = [];
  Key _hotelDropdownKey = UniqueKey();
  Key _roomCategoryDropdownKey = UniqueKey();
  Key _roomTypeDropdownKey = UniqueKey();

  // Pending hotels for the current guest (before the guest is fully "added")
  List<QuickHotelEntry> _pendingHotels = [];

  // ── AIR members list ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _airMembers = [];

  /// Tickets already added for the guest in the form, the air-tab counterpart
  /// of [_pendingHotels]. The ticket being edited is not in here until "Add
  /// Another Air Ticket" is tapped.
  List<Map<String, dynamic>> _pendingAirTickets = [];

  final _a_noOfSeats = TextEditingController(text: '1');
  // Children / infants travel on the same ticket as the seats above but are
  // counted separately, matching the new reservation screen's air ticket tab.
  final _a_noOfChildren = TextEditingController(text: '0');
  final _a_noOfInfants = TextEditingController(text: '0');
  /// Every cabin class on the ticket with its own seat count. A ticket can mix
  /// them — Economy x2 plus Business x1 is one ticket — so this is a list rather
  /// than a single pick, matching the new reservation screen.
  List<AirTicketClassCount> _a_ticketClasses = [];

  /// Set when a save or "Add Another Air Ticket" was attempted with no class
  /// picked, so the selector can say so.
  bool _a_classError = false;
  Key _a_classKey = UniqueKey();

  // Airlines — picked by name from the master list (API 90156)
  AirlineResponse? _a_selectedAirline;
  List<AirlineResponse> get _a_airlines => _quick.airlines;
  bool get _a_airlinesLoading => _quick.airlinesLoading;
  Key _a_airlineKey = UniqueKey();

  final _a_arrCtrl = TextEditingController();
  final _a_depCtrl = TextEditingController();
  final _a_remarksCtrl = TextEditingController(); // ← NEW: remarks for air tab

  DateTime? _a_arrDate;
  DateTime? _a_depDate;

  static const String _defaultToAirportCode = 'CMB';

  Airport? _a_fromAirport;
  Airport? _a_toAirport;
  Airport? _a_returnFromAirport;
  Airport? _a_returnToAirport;
  bool _a_isRoundTrip = false;

  /// No direct flight is available, so the ticket routes through transit
  /// airports the user adds between From and To on each leg.
  bool _a_isMultiSector = false;
  final List<FlightSectorEntry> _a_departureSectors = [];
  final List<FlightSectorEntry> _a_returnSectors = [];

  Key _a_fromAirportKey = UniqueKey();
  Key _a_toAirportKey = UniqueKey();
  Key _a_returnFromAirportKey = UniqueKey();
  Key _a_returnToAirportKey = UniqueKey();

  // ── Air ticket — additional facility radio options (NEW) ───────────────────
  String _a_skipRouteFacility = 'No';
  String _a_airportTransport = 'No';
  String _a_visa = 'No';
  // Ballys-only air ticket options (hidden for Bellagio)
  String _a_meal = 'No';
  String _a_extraLegroomSeat = 'No';
  String _a_goldRoute = 'No';

  /// Which leg the Silk / Gold Route facility applies to. Only asked for — and
  /// only submitted — while the matching option is Yes.
  String _a_silkRouteType = 'Arrival';
  String _a_goldRouteType = 'Arrival';

  /// Meal requirement, asked for only while Meal is Yes.
  final _a_mealRemarkCtrl = TextEditingController();

  // ── Payment By & Hamoos contact person ────────────────────────────────────
  // Both describe the reservation rather than an individual room or ticket, so
  // they are asked once per tab and sent at the top of the body. Each tab saves
  // a reservation of its own, hence one pair of answers per tab.
  List<String> get _hamoueContactPersons => _quick.contactPersons;
  String? _a_hamoueContactPerson;
  String? _h_hamoueContactPerson;

  /// The Air tab's counterpart of [_h_paymentBy]. A plain string rather than a
  /// controller — nothing is ever typed into it. Empty means "unanswered",
  /// which the save refuses: the field is mandatory and has no default.
  String _a_paymentBy = '';

  /// Set when a save is attempted with "Payment By" still unanswered, so the
  /// card can say so where the chips are.
  bool _h_paymentByError = false;
  bool _a_paymentByError = false;

  /// Bellagio (bty.world) hides the Hamoue contact person dropdown.
  bool get _isBellagio => _quick.isBellagio;

  // ── Air ticket — passport bio data page uploads (NEW) ──────────────────────
  /// Bio pages by guest, keyed the same way the assignment ticks are. One
  /// uploader per ticked guest, so a page is filed against the member it belongs
  /// to instead of landing on whoever owns the form — the same arrangement the
  /// new reservation screen's air ticket selector uses.
  final Map<String, List<PassportFileBallys>> _a_passportsByGuest = {};

  /// Pages picked while there was still nobody to name — they go out under the
  /// member the ticket was entered for.
  List<PassportFileBallys> _a_passportFiles = [];
  Key _a_passportUploadKey = UniqueKey();

  // ── TRANSPORT members list ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _transportMembers = [];

  final _t_pickupDateCtrl = TextEditingController();
  final _t_pickupTimeCtrl = TextEditingController();
  final _t_pickupLocationCtrl = TextEditingController();
  final _t_dropLocationCtrl = TextEditingController();
  final _t_noOfVehicles = TextEditingController(text: '1');
  final _t_contactNumber = TextEditingController();

  Country _t_country = _defaultCountry();

  DateTime? _t_pickupDate;
  TimeOfDay? _t_pickupTime;
  // One Car Type selection per vehicle — resized whenever "No of Vehicles"
  // changes (see _syncVehicleDetailsWithCount). Defaults to 'Normal Car'.
  List<String?> _t_carTypes = ['Normal Car'];
  // One passenger-count controller per vehicle, kept the same length as
  // _t_carTypes so each car's passengers are assigned individually.
  List<TextEditingController> _t_passengerCtrls = [
    TextEditingController(text: '1'),
  ];
  String? _t_hireType;
  String _t_pickupPlaceId = '';
  String _t_dropPlaceId = '';
  String _t_airportPickup = 'No';

  /// Extra members travelling on the SAME transport request as the guest in the
  /// form: they share its pickup, vehicles and dates, so they only carry who
  /// they are and their own package amount.
  final List<_ExtraMember> _t_extraMembers = [];

  /// The same "Add More Guest" rows for the hotel and air ticket tabs: extra
  /// members share the guest's rooms / tickets and dates, each billed their own
  /// package.
  final List<_ExtraMember> _h_extraMembers = [];
  final List<_ExtraMember> _a_extraMembers = [];

  /// The guests the hotel / air ticket currently in the form is booked for, by
  /// [_guestKey]. A room or ticket can go to one guest or to several, so this is
  /// a set of ticks rather than a single pick — the same assignment the new
  /// reservation screen's selector sheets collect.
  final Set<String> _h_assignedGuestKeys = {};
  final Set<String> _a_assignedGuestKeys = {};

  /// Set when a save or "Add Another…" was attempted with nobody ticked, so the
  /// assignment card can say what is missing.
  bool _h_guestAssignError = false;
  bool _a_guestAssignError = false;

  /// Keeps `_t_carTypes` and `_t_passengerCtrls` in sync with the "No of
  /// Vehicles" stepper so there is exactly one Car Type + Passengers pair
  /// per vehicle. Growing the count appends unset slots; shrinking trims
  /// from the end (disposing the removed controllers) and keeps the rest.
  void _syncVehicleDetailsWithCount() {
    final n = int.tryParse(_t_noOfVehicles.text) ?? 1;
    if (n == _t_carTypes.length) return;
    setState(() {
      if (n > _t_carTypes.length) {
        _t_carTypes.addAll(
            List<String?>.filled(n - _t_carTypes.length, 'Normal Car'));
        _t_passengerCtrls.addAll(List.generate(
          n - _t_passengerCtrls.length,
          (_) => TextEditingController(text: '1'),
        ));
      } else {
        _t_carTypes.removeRange(n, _t_carTypes.length);
        for (final c in _t_passengerCtrls.sublist(n)) {
          c.dispose();
        }
        _t_passengerCtrls.removeRange(n, _t_passengerCtrls.length);
      }
    });
  }

  static Country _defaultCountry() => Country(
    phoneCode: '94',
    countryCode: 'LK',
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: 'Sri Lanka',
    example: '712345678',
    displayName: 'Sri Lanka (LK) [+94]',
    displayNameNoCountryCode: 'Sri Lanka (LK)',
    e164Key: '',
  );

  void _showTransportCountryPicker() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (Country country) => setState(() => _t_country = country),
      countryListTheme: CountryListThemeData(
        borderRadius: BorderRadius.circular(8),
        inputDecoration: InputDecoration(
          labelText: 'Search',
          hintText: 'Start typing to search',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  static const _hotelColor = Color(0xFFE65C00);
  static const _airColor = Color(0xFF0277BD);
  static const _transportColor = Color(0xFF2E7D32);

  // Both steps of a tab are in the tree at once, so each needs a controller of
  // its own — one controller cannot drive two live scroll views.
  final _hotelGuestScrollCtrl = ScrollController();
  final _hotelScrollCtrl = ScrollController();
  final _airGuestScrollCtrl = ScrollController();
  final _airScrollCtrl = ScrollController();
  final _transportScrollCtrl = ScrollController();

  Color get _accentColor {
    switch (_activeSection) {
      case _Section.hotel:
        return _hotelColor;
      case _Section.airTicket:
        return _airColor;
      case _Section.transport:
        return _transportColor;
    }
  }

  @override
  void initState() {
    super.initState();
    _quickNotifier = ref.read(quickReservationBallysProvider.notifier);
    // Deferred past the first frame: these loaders write provider state, and
    // [loadAirlines] does so before its first await — a provider modified while
    // the tree is still building throws, which left the airline list empty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadHotels();
      _loadAirports();
      _loadLocationPrefix();
      _loadContactPersons();
      _loadAirlines();
      _loadAuthorizationLevels();
    });
  }

  @override
  void dispose() {
    for (final c in [
      _sharedMemberId,
      _sharedMidNumber,
      _sharedGuestName,
      _sharedPackageAmount,
      // _sharedReservationNo,
      _h_noOfRooms,
      _h_noOfPax,
      _h_noOfChildren,
      _h_mealPlan,
      _h_paymentBy,
      _h_remarks,
      _h_marketingPerson,
      _h_approvedBy,
      _h_arrivalCtrl,
      _h_departureCtrl,
      _a_noOfSeats,
      _a_noOfChildren,
      _a_noOfInfants,
      _a_mealRemarkCtrl,
      _a_arrCtrl,
      _a_depCtrl,
      _a_remarksCtrl,
      _t_pickupDateCtrl,
      _t_pickupTimeCtrl,
      _t_pickupLocationCtrl,
      _t_dropLocationCtrl,
      _t_noOfVehicles,
      _t_contactNumber,
    ]) {
      c.dispose();
    }
    for (final c in _t_passengerCtrls) {
      c.dispose();
    }
    for (final row in [..._t_extraMembers, ..._h_extraMembers, ..._a_extraMembers]) {
      row.dispose();
    }
    _hotelGuestScrollCtrl.dispose();
    _hotelScrollCtrl.dispose();
    _airGuestScrollCtrl.dispose();
    _airScrollCtrl.dispose();
    _transportScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocationPrefix() =>
      _quickNotifier.loadLocationPrefix();

  void _updateMemberIdFields(String fullMemberId) {
    if (fullMemberId.isEmpty) return;
    final (prefix, numberPart) = _quickNotifier.splitMemberId(fullMemberId);
    if (!_isNumericOnlyLocation) _quickNotifier.selectPrefix(prefix);
    setState(() {
      _sharedMidNumber.text = numberPart;
      _sharedMemberId.text = fullMemberId;
    });
  }

  /// Hotels, hotel categories, room categories, room types and meal plans all
  /// come back in one call — the dropdowns below filter it in memory. Refreshed
  /// on entry so the hotel dropdown reflects the API's current list instead of
  /// whatever was cached earlier in the session.
  Future<void> _loadHotels() async {
    await ref.read(hotelCatalogProvider.notifier).refresh();
  }

  Future<void> _loadAirports() async {
    try {
      final airports = ref.read(airportsProvider);
      if (airports.isEmpty)
        await ref.read(airportsProvider.notifier).getAllAirports();
      _applyDefaultToAirport();
    } catch (_) {}
  }

  /// The arrival ("To") airport defaults to CMB from the loaded list; the user
  /// can still pick another airport.
  void _applyDefaultToAirport() {
    if (_a_toAirport != null) return;
    final cmb =
        ref.read(airportsProvider.notifier).findByCode(_defaultToAirportCode);
    if (cmb == null || !mounted) return;
    setState(() {
      _a_toAirport = cmb;
      _a_toAirportKey = UniqueKey();
      if (_a_isRoundTrip) {
        _a_returnFromAirport = cmb;
        _a_returnFromAirportKey = UniqueKey();
      }
    });
  }

  Future<void> _loadContactPersons() async {
    await _quickNotifier.loadContactPersons();
  }

  /// Answers the hotel-type question. Everything picked under the old answer
  /// goes with it — the hotel below belongs to one list or the other, and so do
  /// its categories and room types.
  void _setHotelLocation(HotelLocation location) {
    if (_selectedHotelLocation == location) return;
    setState(() {
      _selectedHotelLocation = location;
      _selectedHotel = null;
      _selectedHotelName = null;
      _selectedHotelId = null;
      _selectedRoomCategory = null;
      _selectedRoomCategoryId = null;
      _selectedRoomCategoryName = null;
      _selectedRoomType = null;
      _selectedRoomTypeId = null;
      _selectedRoomTypeName = null;
      _h_mealPlan.clear();
      _roomCategories = [];
      _roomTypes = [];
      _hotelDropdownKey = UniqueKey();
      _roomCategoryDropdownKey = UniqueKey();
      _roomTypeDropdownKey = UniqueKey();
    });
  }

  void _loadRoomCategories(double hotelId) {
    final categories =
        ref.read(hotelCatalogProvider.notifier).categoriesFor(hotelId);
    setState(() {
      _roomCategories = categories;
      _selectedRoomCategory = null;
      _selectedRoomCategoryId = null;
      _selectedRoomCategoryName = null;
      _selectedRoomType = null;
      _selectedRoomTypeId = null;
      _selectedRoomTypeName = null;
      _h_mealPlan.clear();
      _roomTypes = [];
      _roomCategoryDropdownKey = UniqueKey();
      _roomTypeDropdownKey = UniqueKey();
    });
  }

  void _loadRoomTypes(double hotelId, int categoryId) {
    final roomTypes =
        ref.read(hotelCatalogProvider.notifier).roomTypesFor(hotelId, categoryId);
    setState(() {
      _roomTypes = roomTypes;
      _selectedRoomType = null;
      _selectedRoomTypeId = null;
      _selectedRoomTypeName = null;
      _h_mealPlan.clear();
      _roomTypeDropdownKey = UniqueKey();
    });
  }

  // ── Load airlines from API 90156 ───────────────────────────────────────────
  /// The list is the same whatever route is picked, so it is fetched once.
  /// Only the dropdown's rebuild key is the widget's — the list itself and its
  /// loading flag come off the provider.
  /// Pulls the approvers for the "Request Approval From" dropdown. A failure
  /// only empties the list — the reservation still saves without an approver.
  Future<void> _loadAuthorizationLevels() async {
    await _quickNotifier.loadAuthorizationLevels();
    if (!mounted) return;
    setState(() {
      // A list that came back without the approver already picked would leave
      // the dropdown asserting on a value it cannot show.
      final levels = _quick.authorizationLevels;
      if (_h_approver != null && !levels.contains(_h_approver)) {
        _h_approver = null;
      }
      if (_a_approver != null && !levels.contains(_a_approver)) {
        _a_approver = null;
      }
    });
  }

  Future<void> _loadAirlines() async {
    await _quickNotifier.loadAirlines();
    if (!mounted) return;
    setState(() => _a_airlineKey = UniqueKey());
  }

  // ── Shared helpers ──────────────────────────────────────────────────────────
  void _resetSharedGuest() {
    _sharedMemberId.clear();
    _sharedMidNumber.clear();
    _sharedGuestName.clear();
    _sharedGuestCardVisible = false;
    _sharedHasFamilyMembers = false;
  }

  void _resetHotelFields() {
    _sharedPackageAmount.clear();
    _sharedPackageShared = false;
    // _sharedReservationNo.clear();
    _h_noOfRooms.text = '1';
    _h_noOfPax.text = '1';
    _h_noOfChildren.text = '0';
    _h_mealPlan.clear();
    _h_paymentBy.clear();
    _h_paymentByError = false;
    _h_hamoueContactPerson = null;
    _h_remarks.clear();
    _h_marketingPerson.clear();
    _h_approvedBy.clear();
    _h_arrivalCtrl.clear();
    _h_departureCtrl.clear();
    _h_arrivalDate = null;
    _h_departureDate = null;
    _h_eciLco = 'NA';
    _selectedHotelLocation = null;
    _selectedHotel = null;
    _selectedHotelName = null;
    _selectedHotelId = null;
    _selectedRoomCategory = null;
    _selectedRoomCategoryId = null;
    _selectedRoomCategoryName = null;
    _selectedRoomType = null;
    _selectedRoomTypeId = null;
    _selectedRoomTypeName = null;
    _roomCategories = [];
    _roomTypes = [];
    _hotelDropdownKey = UniqueKey();
    _roomCategoryDropdownKey = UniqueKey();
    _roomTypeDropdownKey = UniqueKey();
    _pendingHotels = [];
    _h_assignedGuestKeys.clear();
    _h_guestAssignError = false;
  }

  void _showHotelAddedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.hotel_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Hotel ${_pendingHotels.length} added for this guest'),
          ],
        ),
        backgroundColor: _hotelColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Capture current hotel fields → QuickHotelEntry ──────────────────────────────
  QuickHotelEntry _captureCurrentHotelEntry() {
    return QuickHotelEntry(
      hotel: _selectedHotelName ?? '',
      hotelId: _selectedHotelId,
      arrival: _h_arrivalCtrl.text,
      departure: _h_departureCtrl.text,
      arrivalDate: _h_arrivalDate,
      departureDate: _h_departureDate,
      noOfRooms: _h_noOfRooms.text,
      noOfPax: _h_noOfPax.text,
      noOfChildren: _h_noOfChildren.text,
      roomType: _selectedRoomTypeName ?? '',
      roomTypeId: _selectedRoomTypeId,
      roomCategory: _selectedRoomCategoryName ?? '',
      roomCategoryId: _selectedRoomCategoryId,
      hotelCategory: (_selectedRoomCategory?['HotelCategory'] ?? '') as String,
      eciLco: _h_eciLco,
      mealPlan: _h_mealPlan.text,
      paymentBy: _h_paymentBy.text,
      remarks: _h_remarks.text,
      marketingPerson: _h_marketingPerson.text,
      approvedBy: _h_approvedBy.text,
      assignedGuests: _selectedHotelGuests(),
    );
  }

  // ── Add another hotel to the current pending-guest form ─────────────────────
  void _addAnotherHotel() {
    if (_selectedHotelName == null || _selectedHotelName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Please select a hotel first'),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    // The hotel about to be banked has to name who it is for, or it can never
    // be told apart from the next one on save.
    if (!_requireHotelGuestAssignment()) return;
    setState(() {
      _pendingHotels.add(_captureCurrentHotelEntry());
      // The banked hotel took its guests with it; the next one starts unticked
      // so those guests come up locked rather than silently double-booked.
      _h_assignedGuestKeys.clear();
      _h_guestAssignError = false;
      _preselectSoleHotelGuest();
      // Reset only the hotel-details fields, keep guest identity
      _h_noOfRooms.text = '1';
      _h_noOfPax.text = '1';
      _h_noOfChildren.text = '0';
      _h_mealPlan.clear();
      // Payment By is NOT cleared, for the same reason as the remarks below:
      // it belongs to the reservation, not to the room being banked.
      // Remarks are NOT cleared: the API takes one remark for the whole
      // reservation, and the field sits below this button — wiping it here is
      // what sent `"remarks": ""` whenever it was typed after banking a hotel.
      _h_marketingPerson.clear();
      _h_approvedBy.clear();
      _h_arrivalCtrl.clear();
      _h_departureCtrl.clear();
      _h_arrivalDate = null;
      _h_departureDate = null;
      _h_eciLco = 'NA';
      _selectedHotelLocation = null;
      _selectedHotel = null;
      _selectedHotelName = null;
      _selectedHotelId = null;
      _selectedRoomCategory = null;
      _selectedRoomCategoryId = null;
      _selectedRoomCategoryName = null;
      _selectedRoomType = null;
      _selectedRoomTypeId = null;
      _selectedRoomTypeName = null;
      _roomCategories = [];
      _roomTypes = [];
      _hotelDropdownKey = UniqueKey();
      _roomCategoryDropdownKey = UniqueKey();
      _roomTypeDropdownKey = UniqueKey();
    });
    _showHotelAddedSnack();
  }

  Map<String, dynamic> _captureCurrentAirMember() {
    return {
      'guestName': _sharedGuestName.text,
      'memberId': _sharedMemberId.text,
      'packageAmount': _sharedPackageAmount.text,
      'sharedPackage': _sharedPackageShared,
      'hasFamilyMembers': _sharedHasFamilyMembers,
      // 'reservationNo': _sharedReservationNo.text,
      ..._captureCurrentAirTicket(),
    };
  }

  /// Just the ticket half of the air form — everything that belongs to a single
  /// flight rather than to the guest. Kept separate so "Add Another Air Ticket"
  /// can bank one ticket and reset those fields while the guest stays put.
  ///
  /// The stops the user actually picked, in the order the rows are shown, each
  /// carrying the day it is flown. Copied out of the live [FlightSectorEntry]
  /// rows so a banked ticket keeps the route it was banked with when the form
  /// is edited for the next one.
  List<AirportInfo> _pickedSectorInfos(List<FlightSectorEntry> sectors) => sectors
      .where((sector) => sector.airport != null)
      .map((sector) => AirportInfo(
            airportCode: sector.airport!.airportCode ?? '',
            cityName: sector.airport!.cityName ?? '',
            airportName: sector.airport!.airportName ?? '',
            country: sector.airport!.country ?? '',
            sectorDate: sector.date,
          ))
      .toList();

  /// One leg written out with its transit stops, e.g.
  /// "Colombo (CMB) → Dubai (DXB) [12 Mar] → London (LHR)" — the same
  /// "City (CODE)" shape the other airport display strings use, with each
  /// stop's travel day beside it.
  String _airRouteText(
      Airport? from, List<FlightSectorEntry> sectors, Airport? to) {
    String endpoint(Airport? a) => a == null
        ? ''
        : '${a.cityName ?? ''} (${a.airportCode ?? ''})';
    String stopName(AirportInfo s) {
      final base = '${s.cityName} (${s.airportCode})';
      return s.sectorDate == null ? base : '$base [${_fmt(s.sectorDate!)}]';
    }

    final stops =
        _a_isMultiSector ? _pickedSectorInfos(sectors) : <AirportInfo>[];
    final parts = [
      endpoint(from),
      ...stops.map(stopName),
      endpoint(to),
    ].where((part) => part.trim().isNotEmpty && part != ' ()').toList();
    return parts.length < 2 ? '' : parts.join(' → ');
  }

  Map<String, dynamic> _captureCurrentAirTicket() {
    return {
      // display strings (used for copy text)
      'fromAirport': _a_fromAirport != null
          ? '${_a_fromAirport!.cityName ?? ''} (${_a_fromAirport!.airportCode ?? ''})'
          : '',
      'toAirport': _a_toAirport != null
          ? '${_a_toAirport!.cityName ?? ''} (${_a_toAirport!.airportCode ?? ''})'
          : '',
      'isRoundTrip': _a_isRoundTrip,
      'isMultiSector': _a_isMultiSector,
      // Full legs including transit stops, for the copy text and the ticket
      // chips — 'fromAirport' / 'toAirport' stay the leg endpoints.
      'departureRoute':
          _airRouteText(_a_fromAirport, _a_departureSectors, _a_toAirport),
      'returnRoute': _a_isRoundTrip
          ? _airRouteText(
              _a_returnFromAirport, _a_returnSectors, _a_returnToAirport)
          : '',
      'returnFrom': _a_returnFromAirport != null
          ? '${_a_returnFromAirport!.cityName ?? ''} (${_a_returnFromAirport!.airportCode ?? ''})'
          : '',
      'returnTo': _a_returnToAirport != null
          ? '${_a_returnToAirport!.cityName ?? ''} (${_a_returnToAirport!.airportCode ?? ''})'
          : '',
      'arrDate': _a_arrCtrl.text,
      'depDate': _a_depCtrl.text,
      'noOfSeats': _a_noOfSeats.text,
      'noOfChildren': _a_noOfChildren.text,
      'noOfInfants': _a_noOfInfants.text,
      // "Economy x2, Business x1" — every class on the ticket on one line, for
      // the copy text and the banked-ticket chips.
      'class': AirTicketClassCount.summary(_a_ticketClasses),
      'airline': _a_selectedAirline?.airlineName ?? '',
      'airlineCode': _a_selectedAirline?.airlineCode ?? '',
      'iataCode': _a_selectedAirline?.iataCode ?? '',
      'remarks': _a_remarksCtrl.text,
      'skipRouteFacility': _a_skipRouteFacility,
      'airportTransport': _a_airportTransport,
      'visa': _a_visa,
      'meal': _a_meal,
      'extraLegroomSeat': _a_extraLegroomSeat,
      'goldRoute': _a_goldRoute,
      // Follow-ups to the Yes answers above — only meaningful while their
      // option is Yes, which is where they are read back.
      'silkRouteType': _a_silkRouteType,
      'goldRouteType': _a_goldRouteType,
      'mealRemark': _a_mealRemarkCtrl.text.trim(),
      'hamoueContactPerson': _a_hamoueContactPerson ?? '',
      'passportFiles': _allAirPassports().map((f) => f.fileName).join(', '),
      // typed fields used when building API body
      'fromAirportData': _a_fromAirport,
      'toAirportData': _a_toAirport,
      'returnFromData': _a_returnFromAirport,
      'returnToData': _a_returnToAirport,
      'departureSectorData': _a_isMultiSector
          ? _pickedSectorInfos(_a_departureSectors)
          : <AirportInfo>[],
      // Return stops describe nothing without a return leg.
      'returnSectorData': _a_isMultiSector && _a_isRoundTrip
          ? _pickedSectorInfos(_a_returnSectors)
          : <AirportInfo>[],
      'arrDateObj': _a_arrDate,
      'depDateObj': _a_depDate,
      // Every class with its seat count, which is what goes out on save.
      'ticketClasses': List<AirTicketClassCount>.from(_a_ticketClasses),
      // Each page still naming the guest it was picked for.
      'passportFileObjects': _allAirPassports(),
      // Who the ticket is booked for, ticked on the assignment card.
      'assignedGuests': _selectedAirGuests(),
    };
  }

  /// Every bio page picked for the ticket on screen, in the order the guests
  /// appear on the reservation, each still naming its owner. Guests dropped from
  /// the reservation take their passports with them, so only the live buckets go
  /// out — plus whatever named nobody to begin with.
  List<PassportFileBallys> _allAirPassports() {
    final files = <PassportFileBallys>[];
    for (final guest in _airAssignableGuests) {
      files.addAll(_a_passportsByGuest[_guestKey(guest)] ?? const []);
    }
    files.addAll(_a_passportFiles);
    return files;
  }

  /// A full sector, which is what "Add Another Air Ticket" requires before it
  /// will bank the ticket on screen.
  bool get _hasCompleteAirSector =>
      _a_fromAirport != null && _a_toAirport != null;

  /// Picks the day a single transit stop is flown. Unlike the ticket's arrival
  /// and departure dates this writes straight onto the stop, so there is no
  /// controller to keep in step.
  ///
  /// The ticket's arrival date is the default starting point — a stop is flown
  /// on the way, so it is the day the journey begins that it hangs off.
  Future<void> _pickSectorDate(FlightSectorEntry sector, int stopNumber) async {
    final picked = await _pickDate(
      context,
      label: 'Select Stop $stopNumber Date',
      initial: sector.date ?? _a_arrDate,
    );
    if (picked == null) return;
    setState(() => sector.date = picked);
  }

  /// Multi Sector is on but the stops don't describe a route yet — a row with
  /// no airport, a row with no travel day, or every row deleted.
  bool get _hasIncompleteAirStops {
    if (!_a_isMultiSector) return false;
    if (_a_departureSectors.isEmpty && _a_returnSectors.isEmpty) return true;
    return _hasUndatedAirStops ||
        _a_departureSectors.any((sector) => sector.airport == null) ||
        (_a_isRoundTrip &&
            _a_returnSectors.any((sector) => sector.airport == null));
  }

  /// A stop with an airport but no day. The route is flown over several days, so
  /// without it the stops are just a list of airports in no particular order.
  bool get _hasUndatedAirStops =>
      _a_departureSectors.any((sector) => sector.date == null) ||
      (_a_isRoundTrip && _a_returnSectors.any((sector) => sector.date == null));

  /// The matching complaint for [_hasIncompleteAirStops].
  String get _incompleteAirStopsMessage {
    if (_a_departureSectors.isEmpty && _a_returnSectors.isEmpty) {
      return 'Please add at least one stop, or turn Multi Sector off';
    }
    final missingAirport = _a_departureSectors.any((s) => s.airport == null) ||
        (_a_isRoundTrip && _a_returnSectors.any((s) => s.airport == null));
    if (missingAirport) return 'Please select an airport for every stop';
    return 'Please select a date for every stop';
  }

  /// Whether the ticket on screen is worth submitting. After "Add Another Air
  /// Ticket" the form is blank on purpose and must not become an empty ticket,
  /// but anything the user has since touched brings it back — checking only for
  /// a complete sector would silently drop a half-filled ticket on save.
  ///
  /// `_a_toAirport` is deliberately not counted: the reset re-applies the
  /// default destination, so it is set even on an untouched form.
  bool get _hasCurrentAirTicket =>
      _a_fromAirport != null ||
      _a_selectedAirline != null ||
      _a_ticketClasses.isNotEmpty ||
      _a_arrDate != null ||
      _a_depDate != null ||
      _allAirPassports().isNotEmpty;
  // Remarks are deliberately not counted: they belong to the reservation, not
  // to a ticket, and survive banking — counting them would turn a blank form
  // with a leftover remark into a phantom ticket.

  /// Clears the ticket half of the air form, leaving the guest identity and
  /// package amount in place for the next ticket.
  void _resetAirTicketFields() {
    _a_noOfSeats.text = '1';
    _a_noOfChildren.text = '0';
    _a_noOfInfants.text = '0';
    _a_ticketClasses = [];
    _a_classError = false;
    _a_classKey = UniqueKey();
    _a_selectedAirline = null;
    _a_airlineKey = UniqueKey();
    _a_arrCtrl.clear();
    _a_depCtrl.clear();
    // Remarks are NOT cleared here: the API takes one remark for the whole
    // reservation and the field sits below "Add Another Air Ticket", so wiping
    // it on bank is what sent `"remarks": ""`. _clearAllAirForm clears it once
    // the reservation is actually saved.
    _a_arrDate = null;
    _a_depDate = null;
    _a_fromAirport = null;
    _a_toAirport =
        ref.read(airportsProvider.notifier).findByCode(_defaultToAirportCode);
    _a_returnFromAirport = null;
    _a_returnToAirport = null;
    _a_isRoundTrip = false;
    _a_isMultiSector = false;
    _a_departureSectors.clear();
    _a_returnSectors.clear();
    _a_fromAirportKey = UniqueKey();
    _a_toAirportKey = UniqueKey();
    _a_returnFromAirportKey = UniqueKey();
    _a_returnToAirportKey = UniqueKey();
    _a_skipRouteFacility = 'No';
    _a_airportTransport = 'No';
    _a_visa = 'No';
    _a_meal = 'No';
    _a_extraLegroomSeat = 'No';
    _a_goldRoute = 'No';
    _a_silkRouteType = 'Arrival';
    _a_goldRouteType = 'Arrival';
    _a_mealRemarkCtrl.clear();
    // The contact person is NOT cleared here: it belongs to the reservation
    // rather than to the ticket being banked. _clearAllAirForm drops it once
    // the reservation is actually saved.
    _a_passportFiles = [];
    // The banked ticket took its guests' pages with it, so the next ticket
    // starts with empty uploaders.
    _a_passportsByGuest.clear();
    _a_passportUploadKey = UniqueKey();
  }

  // ── Add another air ticket to the current pending-guest form ────────────────
  void _addAnotherAirTicket() {
    if (!_hasCompleteAirSector || _hasIncompleteAirStops) {
      final message = !_hasCompleteAirSector
          ? 'Please select the From and To airports first'
          : _incompleteAirStopsMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(message),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    // The ticket about to be banked has to name who it is for and what class
    // they fly, or it can never be told apart from the next one on save.
    if (!_requireAirGuestAssignment()) return;
    if (!_requireAirTicketClass()) return;
    setState(() {
      _pendingAirTickets.add(_captureCurrentAirTicket());
      // The banked ticket took its guests with it; the next one starts unticked
      // so those guests come up locked rather than silently double-booked.
      _a_assignedGuestKeys.clear();
      _a_guestAssignError = false;
      _resetAirTicketFields();
      _preselectSoleAirGuest();
    });
    _showAirTicketAddedSnack();
  }

  void _showAirTicketAddedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.flight_takeoff_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Air ticket ${_pendingAirTickets.length} added for this guest'),
          ],
        ),
        backgroundColor: _airColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── TRANSPORT ───────────────────────────────────────────────────────────────
  /// Captures the current form as a single transport entry. Per-vehicle Car
  /// Type + Passengers are carried as a `vehicleDetails` list (one map per
  /// vehicle) rather than flattened into separate entries.
  Map<String, dynamic> _captureCurrentTransportMember() {
    return {
      'guestName': _sharedGuestName.text,
      'memberId': _sharedMemberId.text,
      // Transport requests no longer capture a package amount; the API field is
      // kept so the payload shape stays unchanged.
      'packageAmount': '',
      'sharedPackage': false,
      // Guests riding along on this same request.
      'extraMembers': _captureExtraMembers(_t_extraMembers),
      'pickupDate': _t_pickupDateCtrl.text,
      'pickupTime': _t_pickupTimeCtrl.text,
      'hireType': _t_hireType ?? '',
      'pickupLocation': _t_pickupLocationCtrl.text,
      'dropLocation': _t_dropLocationCtrl.text,
      'vehicleDetails': List.generate(_t_carTypes.length, (i) {
        return {
          'carType': _t_carTypes[i] ?? '',
          'noOfPassengers': _t_passengerCtrls[i].text,
        };
      }),
      'contactNumber': _t_contactNumber.text.trim().isEmpty
          ? ''
          : '+${_t_country.phoneCode}${_t_contactNumber.text.trim()}',
      'silkRoute': 'No',
      'airportPickup': _t_airportPickup,
      // typed fields used when building the API body
      'pickupDateObj': _t_pickupDate,
      'pickupTimeObj': _t_pickupTime,
      'pickupPlaceId': _t_pickupPlaceId,
      'dropPlaceId': _t_dropPlaceId,
    };
  }

  void _resetTransportFields() {
    _t_pickupDateCtrl.clear();
    _t_pickupTimeCtrl.clear();
    _t_pickupLocationCtrl.clear();
    _t_dropLocationCtrl.clear();
    _t_noOfVehicles.text = '1';
    _t_contactNumber.clear();
    _t_country = _defaultCountry();
    _t_pickupDate = null;
    _t_pickupTime = null;
    _t_carTypes = ['Normal Car'];
    for (final c in _t_passengerCtrls) {
      c.dispose();
    }
    _t_passengerCtrls = [TextEditingController(text: '1')];
    _t_hireType = null;
    _t_pickupPlaceId = '';
    _t_dropPlaceId = '';
    _t_airportPickup = 'No';
    _clearExtraMembers(_t_extraMembers);
  }

  void _clearAllTransportForm() {
    setState(() {
      _transportMembers.clear();
      _resetSharedGuest();
      _resetTransportFields();
    });
  }

  // ── Extra guests sharing the transport request ──────────────────────────────

  void _addExtraMember(List<_ExtraMember> rows) {
    FocusScope.of(context).unfocus();
    setState(() {
      rows.add(
        _ExtraMember(
          prefix: _isNumericOnlyLocation ? '' : _selectedPrefix,
        ),
      );
    });
  }

  void _removeExtraMember(List<_ExtraMember> rows, int index) {
    setState(() {
      rows.removeAt(index).dispose();
    });
  }

  void _clearExtraMembers(List<_ExtraMember> rows) {
    for (final row in rows) {
      row.dispose();
    }
    rows.clear();
  }

  /// Rejects half-filled and duplicate rows before a save. A blank row is
  /// skipped, matching how [_captureExtraMembers] drops it.
  bool _validateExtraMembers(
    List<_ExtraMember> rows, {
    required String primaryMid,

    /// Transport rows have no Package Amount field, so an empty amount there is
    /// expected rather than a half-filled row.
    bool requirePackageAmount = true,
  }) {
    final seen = <String>{if (primaryMid.isNotEmpty) primaryMid};

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final mid = row.fullMid(numericOnly: _isNumericOnlyLocation);
      final name = row.nameController.text.trim();
      final packageAmount = row.packageAmountController.text.trim();

      if (mid.isEmpty && name.isEmpty && packageAmount.isEmpty) {
        continue; // blank row: ignored on save
      }
      if (mid.isEmpty || name.isEmpty) {
        _showSaveErrorSnack(
            'Guest ${i + 2}: both Membership No and Guest Name are required');
        return false;
      }
      if (requirePackageAmount &&
          packageAmount.isEmpty &&
          !row.sharedPackage) {
        _showSaveErrorSnack('Guest ${i + 2}: Package Amount is required');
        return false;
      }
      if (!seen.add(mid)) {
        _showSaveErrorSnack('$mid is already added to this reservation');
        return false;
      }
    }
    return true;
  }

  /// The filled-in extra rows as plain maps, in the same shape the primary
  /// guest's member map uses.
  List<Map<String, dynamic>> _captureExtraMembers(List<_ExtraMember> rows) {
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final mid = row.fullMid(numericOnly: _isNumericOnlyLocation);
      final name = row.nameController.text.trim();
      if (mid.isEmpty && name.isEmpty) continue;
      out.add({
        'memberId': mid,
        'guestName': name,
        // A shared member may still carry an amount of their own, so the tick
        // no longer wipes it — `sharedPackage` records the tick in its own
        // right, the way the new reservation screen sends `IsSharedAmount`.
        'packageAmount': row.packageAmountController.text.trim(),
        'sharedPackage': row.sharedPackage,
        'hasFamilyMembers': row.hasFamilyMembers,
      });
    }
    return out;
  }

  // ── Guest assignment ────────────────────────────────────────────────────────
  // A hotel or an air ticket is always booked *for* someone. Rather than
  // assuming it belongs to whoever is in the form, the booking step lists
  // everyone on the reservation and the room / ticket is ticked against them —
  // the same assignment the new reservation screen's selector sheets collect.

  /// Identifies a guest across rebuilds. BM number alone is not enough — a
  /// member typed in but not yet searched can still be sitting there nameless.
  String _guestKey(AccompanyingMember guest) =>
      "${guest.mid.trim()}|${guest.guestName.trim()}";

  /// Whether [assigned] is [guest] — by BM number where there is one, by name
  /// for a member typed in but never searched.
  bool _namesGuest(AssignedGuest assigned, AccompanyingMember guest) {
    final mid = assigned.mid.trim();
    return (mid.isNotEmpty && mid == guest.mid.trim()) ||
        (mid.isEmpty && assigned.guestName.trim() == guest.guestName.trim());
  }

  /// Everyone on this reservation: the guest from step ① plus every "Add More
  /// Guest" row on the tab. This is the list the assignment ticks against.
  List<AccompanyingMember> _reservationGuests(List<_ExtraMember> rows) {
    final guests = <AccompanyingMember>[];

    final mid = _sharedMemberId.text.trim();
    final name = _sharedGuestName.text.trim();
    if (mid.isNotEmpty || name.isNotEmpty) {
      guests.add(AccompanyingMember(
        mid: mid,
        guestName: name,
        hasFamilyMembers: _sharedHasFamilyMembers,
        packageAmount: _sharedPackageAmount.text.trim(),
        sharedPackage: _sharedPackageShared,
      ));
    }

    for (final row in _captureExtraMembers(rows)) {
      guests.add(AccompanyingMember(
        mid: row['memberId'] as String? ?? '',
        guestName: row['guestName'] as String? ?? '',
        hasFamilyMembers: row['hasFamilyMembers'] as bool? ?? false,
        packageAmount: row['packageAmount'] as String? ?? '',
        sharedPackage: row['sharedPackage'] as bool? ?? false,
      ));
    }

    return guests;
  }

  /// Guests a room can actually be booked for: a member with "Shared" ticked is
  /// on somebody else's package and sleeps in that guest's room, so they are
  /// listed on the assignment but never get a room of their own. Air tickets
  /// have no such rule — a shared member still flies on their own seat.
  List<AccompanyingMember> get _hotelAssignableGuests =>
      _reservationGuests(_h_extraMembers)
          .where((guest) => !guest.sharedPackage)
          .toList();

  List<AccompanyingMember> get _airAssignableGuests =>
      _reservationGuests(_a_extraMembers);

  /// Guests who already hold one of the hotels banked with "Add Another Hotel".
  /// They are shown greyed out rather than offered again — a guest sleeps in one
  /// room.
  Set<String> _guestsInPendingHotels() {
    final taken = <String>{};
    for (final hotel in _pendingHotels) {
      for (final guest in _hotelAssignableGuests) {
        if (hotel.assignedGuests.any((a) => _namesGuest(a, guest))) {
          taken.add(_guestKey(guest));
        }
      }
    }
    return taken;
  }

  /// The air tab's counterpart of [_guestsInPendingHotels] — a guest takes one
  /// ticket.
  Set<String> _guestsOnPendingAirTickets() {
    final taken = <String>{};
    for (final ticket in _pendingAirTickets) {
      final assigned =
          (ticket['assignedGuests'] as List<AssignedGuest>?) ?? const [];
      for (final guest in _airAssignableGuests) {
        if (assigned.any((a) => _namesGuest(a, guest))) {
          taken.add(_guestKey(guest));
        }
      }
    }
    return taken;
  }

  /// The guests still tickable for the booking in the form.
  List<AccompanyingMember> _selectableHotelGuests() {
    final locked = _guestsInPendingHotels();
    return _hotelAssignableGuests
        .where((guest) => !locked.contains(_guestKey(guest)))
        .toList();
  }

  List<AccompanyingMember> _selectableAirGuests() {
    final locked = _guestsOnPendingAirTickets();
    return _airAssignableGuests
        .where((guest) => !locked.contains(_guestKey(guest)))
        .toList();
  }

  /// The ticked guests as they travel on the booking, in reservation order.
  List<AssignedGuest> _selectedHotelGuests() => _hotelAssignableGuests
      .where((guest) => _h_assignedGuestKeys.contains(_guestKey(guest)))
      .map((guest) =>
          AssignedGuest(mid: guest.mid.trim(), guestName: guest.guestName.trim()))
      .toList();

  List<AssignedGuest> _selectedAirGuests() => _airAssignableGuests
      .where((guest) => _a_assignedGuestKeys.contains(_guestKey(guest)))
      .map((guest) =>
          AssignedGuest(mid: guest.mid.trim(), guestName: guest.guestName.trim()))
      .toList();

  /// Drops ticks for guests who are no longer on the reservation. Going back to
  /// step ① to rename a member or delete a row changes their key, and a tick
  /// left behind would assign the booking to somebody who isn't there.
  void _dropUnknownAssignedGuests(
    Set<String> keys,
    List<AccompanyingMember> guests,
  ) {
    final live = guests.map(_guestKey).toSet();
    keys.removeWhere((key) => !live.contains(key));
  }

  /// A single guest on the reservation is the only one a room / ticket can be
  /// for, so it starts ticked rather than making every add a two-step job —
  /// unless that guest already holds one.
  void _preselectSoleHotelGuest() {
    if (_h_assignedGuestKeys.isNotEmpty) return;
    final selectable = _selectableHotelGuests();
    if (selectable.length != 1) return;
    _h_assignedGuestKeys.add(_guestKey(selectable.first));
    _syncRoomCountToGuests();
  }

  void _preselectSoleAirGuest() {
    if (_a_assignedGuestKeys.isNotEmpty) return;
    final selectable = _selectableAirGuests();
    if (selectable.length != 1) return;
    _a_assignedGuestKeys.add(_guestKey(selectable.first));
    _trimTicketClassesToLimit();
    _syncSeatCountToGuests();
  }

  /// Rooms are counted per ticked guest: one room each. Never below one — a room
  /// is a room even before anybody is ticked.
  bool get _roomCountLocked => _h_assignedGuestKeys.isNotEmpty;

  void _syncRoomCountToGuests() {
    if (!_roomCountLocked) return;
    final rooms = _h_assignedGuestKeys.length;
    _h_noOfRooms.text = (rooms < 1 ? 1 : rooms).toString();
  }

  /// Whether any guest this ticket is booked for brings family along. Without
  /// family there is nobody on the ticket but the guests themselves, so the head
  /// counts are the ticked guests and the counters are read-only.
  bool get _airTicketHasFamily => _airAssignableGuests
      .where((guest) => _a_assignedGuestKeys.contains(_guestKey(guest)))
      .any((guest) => guest.hasFamilyMembers);

  bool get _seatCountLocked =>
      _a_assignedGuestKeys.isNotEmpty && !_airTicketHasFamily;

  void _syncSeatCountToGuests() {
    if (!_seatCountLocked) return;
    _a_noOfSeats.text = _a_assignedGuestKeys.length.toString();
    _a_noOfChildren.text = '0';
    _a_noOfInfants.text = '0';
  }

  /// Seats this ticket may hold across all classes: one per ticked guest, so a
  /// lone guest gets a single class and a single seat. Null is no ceiling —
  /// what a guest who brings family needs, since the family flying with them is
  /// counted on the ticket, not here.
  int? get _maxTicketSeats {
    if (_airTicketHasFamily) return null;
    final assigned = _a_assignedGuestKeys.length;
    return assigned == 0 ? null : assigned;
  }

  /// Unticking a guest can leave more seats on the ticket than the rest of them
  /// can hold, so the classes are pared back to fit — counts first, then whole
  /// classes off the end.
  void _trimTicketClassesToLimit() {
    final maxSeats = _maxTicketSeats;
    if (maxSeats == null) return;
    final trimmed = <AirTicketClassCount>[];
    var used = 0;
    for (final item in _a_ticketClasses) {
      final remaining = maxSeats - used;
      if (remaining < 1) break;
      final entry =
          item.count > remaining ? item.copyWith(count: remaining) : item;
      trimmed.add(entry);
      used += entry.count;
    }
    // Within the ceiling this is the same list it started as.
    _a_ticketClasses = trimmed;
  }

  /// Ticks or unticks one guest for the hotel in the form.
  void _toggleHotelGuest(String key, bool selected) {
    setState(() {
      if (selected) {
        _h_assignedGuestKeys.add(key);
      } else {
        _h_assignedGuestKeys.remove(key);
      }
      _h_guestAssignError = false;
      _syncRoomCountToGuests();
    });
  }

  void _toggleAirGuest(String key, bool selected) {
    setState(() {
      if (selected) {
        _a_assignedGuestKeys.add(key);
      } else {
        _a_assignedGuestKeys.remove(key);
      }
      _a_guestAssignError = false;
      _trimTicketClassesToLimit();
      _syncSeatCountToGuests();
    });
  }

  /// "Select all" / "Clear" on the assignment card.
  void _setAllHotelGuests(bool selectAll) {
    setState(() {
      _h_assignedGuestKeys.clear();
      if (selectAll) {
        _h_assignedGuestKeys
            .addAll(_selectableHotelGuests().map(_guestKey));
      }
      _h_guestAssignError = false;
      _syncRoomCountToGuests();
    });
  }

  void _setAllAirGuests(bool selectAll) {
    setState(() {
      _a_assignedGuestKeys.clear();
      if (selectAll) {
        _a_assignedGuestKeys.addAll(_selectableAirGuests().map(_guestKey));
      }
      _a_guestAssignError = false;
      _trimTicketClassesToLimit();
      _syncSeatCountToGuests();
    });
  }

  /// Complains when a booking is about to be banked or saved with nobody ticked
  /// — a room or ticket for no one cannot be assigned on the way out.
  bool _requireHotelGuestAssignment() {
    if (_h_assignedGuestKeys.isNotEmpty) return true;
    // Nothing to tick at all is a different problem, reported elsewhere.
    if (_selectableHotelGuests().isEmpty) return true;
    setState(() => _h_guestAssignError = true);
    _showSaveErrorSnack('Please select at least one guest for this hotel');
    return false;
  }

  bool _requireAirGuestAssignment() {
    if (_a_assignedGuestKeys.isNotEmpty) return true;
    if (_selectableAirGuests().isEmpty) return true;
    setState(() => _a_guestAssignError = true);
    _showSaveErrorSnack('Please select at least one guest for this air ticket');
    return false;
  }

  /// A ticket with no cabin class picked cannot be booked, so both banking and
  /// saving stop for it — the same check the new reservation screen makes.
  bool _requireAirTicketClass() {
    if (_a_ticketClasses.isNotEmpty) return true;
    setState(() => _a_classError = true);
    _showSaveErrorSnack('Please select at least one class for this air ticket');
    return false;
  }

  /// "Payment By" is mandatory on both tabs and starts unanswered, so a save
  /// stops on it and the booking step is brought back up with the card marked.
  bool _requireHotelPaymentBy() {
    if (_h_paymentBy.text.trim().isNotEmpty) return true;
    setState(() {
      _h_paymentByError = true;
      _hotelStep = 1;
    });
    _showSaveErrorSnack('Please select Payment By');
    return false;
  }

  bool _requireAirPaymentBy() {
    if (_a_paymentBy.trim().isNotEmpty) return true;
    setState(() {
      _a_paymentByError = true;
      _airStep = 1;
    });
    _showSaveErrorSnack('Please select Payment By');
    return false;
  }

  /// Member search for an extra-member row. Unlike the main fields these do not
  /// go through the shared guest controllers, so the pick comes back by row.
  Future<void> _openExtraMemberSearch(
    List<_ExtraMember> rows,
    int index,
    int iid,
  ) async {
    FocusScope.of(context).unfocus();

    final row = rows[index];
    final term = iid == 8002
        ? row.fullMid(numericOnly: _isNumericOnlyLocation)
        : row.nameController.text.trim();

    void showSheet(List<GuestSearchResponse> guests) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => MemberNewSearchBottomSheet(
          guests: guests,
          initialSearchTerm: term,
          searchIid: iid,
          onSearch: (newTerm, newIid) async {
            if (newTerm.length < 3) return;
            final r = await _quickNotifier.searchGuest(newIid, newTerm);
            if (!mounted) return;
            Navigator.of(ctx).pop();
            showSheet(r);
          },
          onGuestSelected: (guest) {
            final (prefix, number) = _quickNotifier.splitMemberId(guest.mid);
            setState(() {
              row.prefix = prefix;
              row.midNumberController.text = number;
              row.nameController.text = guest.mName;
            });
          },
        ),
      );
    }

    if (term.length < 3) {
      showSheet([]);
      return;
    }

    _setBusy(true);
    final guests = await _quickNotifier.searchGuest(iid, term);
    _setBusy(false);
    if (!mounted) return;
    showSheet(guests);
  }

  // ── Guest search ─────────────────────────────────────────────────────────────
  Future<void> _openGuestSearch({
    required int iid,
    required VoidCallback onCardVisible,
  }) async {
    final term = iid == 8002 ? _sharedMemberId.text : _sharedGuestName.text;
    if (term.length < 3) {
      _showSearchSheet([], term, iid, onCardVisible);
      return;
    }
    _setBusy(true);
    final guests = await _quickNotifier.searchGuest(iid, term);
    _setBusy(false);
    if (!mounted) return;
    _showSearchSheet(guests, term, iid, onCardVisible);
  }

  Future<void> _fetchAndSetGuest({
    required String mid,
    required String name,
    required VoidCallback onReady,
  }) async {
    final guest = await _quickNotifier.fetchGuestDetails(mid);
    if (!mounted) return;
    _publishGuest(guest, mid: mid, name: name);
    onReady();
  }

  /// Puts the picked member on [selectedGuestProvider] — the full record when
  /// the lookup found one, otherwise just the ID and name the caller already
  /// had, so the profile screen always has something to open with.
  void _publishGuest(GuestSearchResponse? g,
      {required String mid, required String name}) {
    if (g == null) {
      _setGuest(mid: mid, name: name);
      return;
    }
    ref.read(selectedGuestProvider.notifier).setSelectedGuest(
          Guest(
            mid: g.mid,
            memberName: g.mName,
            country: '',
            lastVisitDate: g.lvd?.toString() ?? '',
            age: 0,
            gRating: g.gRating ?? '',
            mGroup: '',
            gName: g.gName ?? '',
            memImage2: g.memImage2,
          ),
        );
  }

  void _showSearchSheet(
    List<GuestSearchResponse> guests,
    String term,
    int iid,
    VoidCallback onCardVisible,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => MemberNewSearchBottomSheet(
        guests: guests,
        initialSearchTerm: term,
        searchIid: iid,
        onSearch: (newTerm, newIid) async {
          if (newTerm.length < 3) return;
          final r = await _quickNotifier.searchGuest(newIid, newTerm);
          if (!mounted) return;
          Navigator.of(ctx).pop();
          _showSearchSheet(r, newTerm, newIid, onCardVisible);
        },
        // Taken straight from the sheet rather than through a provider: the
        // sheet publishes its pick on newReservationProvider, which this
        // screen — a Ballys screen on newReservationBallysProvider — never
        // sees, so the guest name never arrived.
        onGuestSelected: (guest) {
          _updateMemberIdFields(guest.mid);
          setState(() => _sharedGuestName.text = guest.mName);
          _fetchAndSetGuest(
            mid: guest.mid,
            name: guest.mName,
            onReady: onCardVisible,
          );
        },
      ),
    );
  }

  void _setGuest({required String mid, required String name}) {
    ref.read(selectedGuestProvider.notifier).setSelectedGuest(
          Guest(
            mid: mid,
            memberName: name,
            country: '',
            lastVisitDate: '',
            age: 0,
            gRating: '',
            mGroup: '',
            gName: '',
          ),
        );
  }

  Future<void> _navigateToProfile(String mid, String name) async {
    if (mid.isEmpty) return;
    final currentGuest = ref.read(selectedGuestProvider);
    if (currentGuest != null && currentGuest.mid == mid) {
      if (mounted) context.push('/home/profile');
      return;
    }
    _setBusy(true);
    final guest = await _quickNotifier.fetchGuestDetails(mid);
    _setBusy(false);
    _publishGuest(guest, mid: mid, name: name);
    if (mounted) context.push('/home/profile');
  }

  Future<DateTime?> _pickDate(
    BuildContext context, {
    String label = 'Select Date',
    DateTime? initial,
    DateTime? minDate,
  }) async {
    DateTime picked = initial ?? minDate ?? DateTime.now();
    // The picker asserts its initial value sits inside the allowed range, so a
    // stale value from before the minimum (e.g. yesterday) is pulled forward.
    if (minDate != null && picked.isBefore(minDate)) picked = minDate;
    DateTime? result;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 220,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: picked,
              minimumDate: minDate ?? DateTime(2000),
              maximumDate: DateTime(2101),
              onDateTimeChanged: (d) => picked = d,
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: TextButton(
                  onPressed: () {
                    result = picked;
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Confirm',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    return result;
  }

  Future<TimeOfDay?> _pickTime(
    BuildContext context, {
    String label = 'Select Time',
    TimeOfDay? initial,
    TimeOfDay? minTime,
  }) async {
    final now = DateTime.now();
    DateTime picked = DateTime(
      now.year,
      now.month,
      now.day,
      initial?.hour ?? now.hour,
      initial?.minute ?? now.minute,
    );
    // Cupertino's time-mode picker ignores minimumDate, so clamp the initial
    // value forward when a minimum is supplied and enforce it again on Confirm.
    if (minTime != null) {
      final minInMinutes = minTime.hour * 60 + minTime.minute;
      final pickedInMinutes = picked.hour * 60 + picked.minute;
      if (pickedInMinutes < minInMinutes) {
        picked = DateTime(
          now.year,
          now.month,
          now.day,
          minTime.hour,
          minTime.minute,
        );
      }
    }
    TimeOfDay? result;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 220,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              initialDateTime: picked,
              use24hFormat: false,
              onDateTimeChanged: (d) => picked = d,
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: TextButton(
                  onPressed: () {
                    if (minTime != null) {
                      final minInMinutes = minTime.hour * 60 + minTime.minute;
                      final pickedInMinutes =
                          picked.hour * 60 + picked.minute;
                      if (pickedInMinutes < minInMinutes) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Pickup time cannot be in the past'),
                          ),
                        );
                        return;
                      }
                    }
                    result =
                        TimeOfDay(hour: picked.hour, minute: picked.minute);
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Confirm',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    return result;
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Midnight today — the earliest day any arrival can be booked for.
  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// A departure is always at least one night after the arrival it belongs to,
  /// and never in the past when no arrival has been picked yet.
  DateTime _minDeparture(DateTime? arrival) =>
      (arrival ?? _today).add(const Duration(days: 1));

  String _fmtTime(TimeOfDay t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${h12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }

  // ── Message builders — HOTEL ─────────────────────────────────────────────────
  String _singleHotelEntryText(QuickHotelEntry h, {int? hotelIndex}) {
    final prefix =
        hotelIndex != null ? '  [Hotel ${hotelIndex + 1}]\n' : '';
    return '''${prefix}  Name of the Hotel    : ${h.hotel}
  Arrival              : ${h.arrival}
  Departure            : ${h.departure}
  No of Room/s         : ${h.noOfRooms}
  No Of Pax            : ${h.noOfPax}
  No Of Children       : ${h.noOfChildren}
  Room Type            : ${h.roomType}
  Room Category        : ${h.roomCategory}${h.hotelCategory.isEmpty ? '' : ' ${h.hotelCategory}'}
  Meal Plan            : ${h.mealPlan.isEmpty ? 'NA' : h.mealPlan}
  ECI/LCO Facility     : ${h.eciLco}
  Payment By           : ${_h_paymentBy.text}
  Remarks              : ${h.remarks}''';
  }

  String _singleHotelMemberText(Map<String, dynamic> m) {
    final hotels = (m['hotels'] as List<QuickHotelEntry>?) ?? [];
    final buf = StringBuffer();
    buf.writeln('*HOTEL RESERVATION REQUEST*');
    buf.writeln('Name of the Guest    : ${m['guestName']}');
    buf.writeln('Membership No        : ${m['memberId']}');
    buf.writeln('Reservation No       : ${m['reservationNo'] ?? ''}');
    buf.writeln('Package Amount       : ${_packageAmountText(m)}');
    buf.writeln(
        'Family Members       : ${(m['hasFamilyMembers'] as bool? ?? false) ? 'Yes' : 'No'}');
    if (!_isBellagio) {
      buf.writeln(
          'Hamoos Contact       : ${(_h_hamoueContactPerson ?? '').isEmpty ? 'NA' : _h_hamoueContactPerson}');
    }
    if (hotels.isEmpty) {
      buf.writeln('  (No hotels added)');
    } else if (hotels.length == 1) {
      buf.writeln(_singleHotelEntryText(hotels.first));
    } else {
      for (int i = 0; i < hotels.length; i++) {
        buf.writeln(_singleHotelEntryText(hotels[i], hotelIndex: i));
        if (i < hotels.length - 1) buf.writeln('  ─────────────────────');
      }
    }
    _appendExtraMembersText(buf, _h_extraMembers);
    buf.write('*');
    return buf.toString();
  }

  /// How a member's package reads in a copied message. A shared package is
  /// called out as such — and still names the amount, since a shared member can
  /// be billed one of their own.
  String _packageAmountText(Map<String, dynamic> m) {
    final amount = (m['packageAmount'] as String? ?? '').trim();
    if (!(m['sharedPackage'] as bool? ?? false)) return amount;
    return amount.isEmpty ? 'Shared' : 'Shared ($amount)';
  }

  /// Appends the "Add More Guest" rows to a copied message. They share the
  /// booking above, so only who they are and their package is worth repeating.
  void _appendExtraMembersText(StringBuffer buf, List<_ExtraMember> rows) {
    final extras = _captureExtraMembers(rows);
    for (int i = 0; i < extras.length; i++) {
      final e = extras[i];
      final amount = _packageAmountText(e);
      buf
        ..write('\n*Guest ${i + 2}*')
        ..write('\nMembership No      : ${e['memberId']}')
        ..write('\nGuest Name         : ${e['guestName']}')
        ..write('\nPackage Amount     : $amount')
        ..write(
            '\nFamily Members     : ${(e['hasFamilyMembers'] as bool? ?? false) ? 'Yes' : 'No'}');
    }
  }

  // Legacy signature kept for _addedMembersSection textBuilder
  String _singleHotelText(Map<String, dynamic> m) =>
      _singleHotelMemberText(m);

  String _buildHotelText() {
    // Build a "current" member snapshot from the form
    final currentHotels = List<QuickHotelEntry>.from(_pendingHotels);
    if (_selectedHotelName != null && _selectedHotelName!.isNotEmpty) {
      currentHotels.add(_captureCurrentHotelEntry());
    }
    final current = {
      'guestName': _sharedGuestName.text,
      'memberId': _sharedMemberId.text,
      'packageAmount': _sharedPackageAmount.text,
      'sharedPackage': _sharedPackageShared,
      'hasFamilyMembers': _sharedHasFamilyMembers,
      // 'reservationNo': _sharedReservationNo.text,
      'hotels': currentHotels,
    };

    if (_hotelMembers.isEmpty) return _singleHotelMemberText(current);
    final all = [
      ..._hotelMembers,
      if ((current['guestName'] as String).isNotEmpty ||
          (current['memberId'] as String).isNotEmpty)
        current,
    ];
    final buf = StringBuffer();
    for (int i = 0; i < all.length; i++) {
      if (i > 0) buf.writeln('\n');
      buf.writeln('*── Member ${i + 1} ──*');
      buf.write(_singleHotelMemberText(all[i]));
    }
    return buf.toString();
  }

  // ── Message builders — AIR ───────────────────────────────────────────────────
  String _singleAirText(Map<String, dynamic> m) {
    final isRound = m['isRoundTrip'] as bool? ?? false;
    final isMultiSector = m['isMultiSector'] as bool? ?? false;
    // The route strings already carry any transit stops; the plain endpoints
    // are the fallback for tickets captured before Multi Sector existed.
    final depRoute = (m['departureRoute'] as String? ?? '').isNotEmpty
        ? m['departureRoute'] as String
        : ((m['fromAirport'] as String).isNotEmpty &&
                (m['toAirport'] as String).isNotEmpty
            ? '${m['fromAirport']} → ${m['toAirport']}'
            : '');
    final retRoute = (m['returnRoute'] as String? ?? '').isNotEmpty
        ? m['returnRoute'] as String
        : ((m['returnFrom'] as String).isNotEmpty &&
                (m['returnTo'] as String).isNotEmpty
            ? '${m['returnFrom']} → ${m['returnTo']}'
            : '');
    String sector = depRoute;
    if (isRound && retRoute.isNotEmpty)
      sector += '\n                         $retRoute';
    final body = '''
*AIR TICKET REQUEST*
BM                       : ${m['memberId']}
Guest Name        : ${m['guestName']}
Reservation No    : ${m['reservationNo'] ?? ''}
Package Amount : ${_packageAmountText(m)}
Family Members : ${(m['hasFamilyMembers'] as bool? ?? false) ? 'Yes' : 'No'}
Sector                  : $sector
Arr Date              : ${m['arrDate']}
Dep Date             : ${m['depDate']}
No of Seats         : ${m['noOfSeats']}
No of Children     : ${m['noOfChildren'] ?? '0'}
No of Infants       : ${m['noOfInfants'] ?? '0'}
Class                    : ${m['class']}
Airline                  : ${m['airline']}
Multi Sector         : ${isMultiSector ? 'Yes' : 'No'}
Round Trip           : ${isRound ? 'Yes' : 'No'}
Slik Route Facility : ${m['skipRouteFacility']}${(m['skipRouteFacility'] as String?) == 'Yes' ? ' (${m['silkRouteType'] ?? ''})' : ''}
Airport Transport   : ${m['airportTransport']}
Visa                     : ${m['visa']}
Meal                     : ${m['meal']}${(m['meal'] as String?) == 'Yes' && (m['mealRemark'] as String? ?? '').isNotEmpty ? ' (${m['mealRemark']})' : ''}
Extra Legroom Seat  : ${m['extraLegroomSeat']}
Gold Route            : ${m['goldRoute']}${(m['goldRoute'] as String?) == 'Yes' ? ' (${m['goldRouteType'] ?? ''})' : ''}
Hamoue Contact   : ${(m['hamoueContactPerson'] as String? ?? '').isEmpty ? 'NA' : m['hamoueContactPerson']}
Payment By          : $_a_paymentBy
Passport File/s      : ${(m['passportFiles'] as String? ?? '').isEmpty ? 'None' : m['passportFiles']}
Remarks              : ${m['remarks']}''';
    final buf = StringBuffer(body);
    _appendExtraMembersText(buf, _a_extraMembers);
    return buf.toString();
  }

  String _buildAirText() {
    final current = _captureCurrentAirMember();

    // Every ticket banked for this guest, plus the one still on screen.
    final tickets = <Map<String, dynamic>>[
      ..._pendingAirTickets.map((t) => {
            'guestName': current['guestName'],
            'memberId': current['memberId'],
            'packageAmount': current['packageAmount'],
            'sharedPackage': current['sharedPackage'],
            'hasFamilyMembers': current['hasFamilyMembers'],
            ...t,
          }),
      if (_pendingAirTickets.isEmpty || _hasCurrentAirTicket) current,
    ];

    if (_airMembers.isEmpty) {
      if (tickets.length == 1) return _singleAirText(tickets.first);
      final buf = StringBuffer();
      for (int i = 0; i < tickets.length; i++) {
        if (i > 0) buf.writeln('\n');
        buf.writeln('*── Ticket ${i + 1} ──*');
        buf.write(_singleAirText(tickets[i]));
      }
      return buf.toString();
    }

    final all = [
      ..._airMembers,
      if ((current['guestName'] as String).isNotEmpty ||
          (current['memberId'] as String).isNotEmpty)
        ...tickets,
    ];
    final buf = StringBuffer();
    for (int i = 0; i < all.length; i++) {
      if (i > 0) buf.writeln('\n');
      buf.writeln('*── Member ${i + 1} ──*');
      buf.write(_singleAirText(all[i]));
    }
    return buf.toString();
  }

  // ── Message builders — TRANSPORT ─────────────────────────────────────────────
  String _singleTransportText(Map<String, dynamic> m) {
    final vehicles = (m['vehicleDetails'] as List?)?.cast<Map>() ?? const [];
    final buf = StringBuffer()
      ..writeln('*TRANSPORT REQUEST*')
      ..writeln('Membership No      : ${m['memberId']}')
      ..writeln('Guest Name         : ${m['guestName']}')
      ..writeln('Pickup Date        : ${m['pickupDate']}')
      ..writeln('Pickup Time        : ${m['pickupTime']}');
    for (int i = 0; i < vehicles.length; i++) {
      final prefix = vehicles.length > 1 ? 'Vehicle ${i + 1} ' : '';
      final carTypeLabel = '${prefix}Car Type'.padRight(19);
      final passengersLabel = '${prefix}Passengers'.padRight(19);
      buf
        ..writeln('$carTypeLabel: ${vehicles[i]['carType']}')
        ..writeln('$passengersLabel: ${vehicles[i]['noOfPassengers']}');
    }
    buf
      ..writeln('Hire Type          : ${m['hireType']}')
      ..writeln('Pickup Location    : ${m['pickupLocation']}')
      ..writeln('Drop Location      : ${m['dropLocation']}')
      ..writeln('No of Vehicles     : ${vehicles.length}')
      ..writeln('Contact Number     : ${m['contactNumber']}')
      ..write('Airport Pickup     : ${m['airportPickup'] ?? 'No'}');
    final extras =
        (m['extraMembers'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (int i = 0; i < extras.length; i++) {
      final e = extras[i];
      buf
        ..write('\n*Guest ${i + 2}*')
        ..write('\nMembership No      : ${e['memberId']}')
        ..write('\nGuest Name         : ${e['guestName']}');
    }
    return buf.toString();
  }

  String _buildTransportText() {
    final current = _captureCurrentTransportMember();
    if (_transportMembers.isEmpty) return _singleTransportText(current);
    final hasCurrentGuest = _sharedGuestName.text.trim().isNotEmpty ||
        _sharedMemberId.text.trim().isNotEmpty;
    final all = [
      ..._transportMembers,
      if (hasCurrentGuest) current,
    ];
    if (all.length == 1) return _singleTransportText(all.first);
    final buf = StringBuffer();
    for (int i = 0; i < all.length; i++) {
      if (i > 0) buf.writeln('\n');
      buf.writeln('*── Member ${i + 1} ──*');
      buf.write(_singleTransportText(all[i]));
    }
    return buf.toString();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Copied to clipboard'),
          ],
        ),
        backgroundColor: _accentColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _onCopy() {
    switch (_activeSection) {
      case _Section.hotel:
        _copyToClipboard(_buildHotelText());
        break;
      case _Section.airTicket:
        _copyToClipboard(_buildAirText());
        break;
      case _Section.transport:
        _copyToClipboard(_buildTransportText());
        break;
    }
  }

  // ── Save to API ─────────────────────────────────────────────────────────────

  void _showSaveErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.red.shade700,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _clearAllHotelForm() {
    setState(() {
      _hotelMembers.clear();
      _clearExtraMembers(_h_extraMembers);
      _resetSharedGuest();
      _resetHotelFields();
      // The reservation is saved, so its approver goes with it.
      _h_approver = null;
      // An emptied form starts over at the guest again.
      _hotelStep = 0;
    });
  }

  void _clearAllAirForm() {
    setState(() {
      _airMembers.clear();
      _pendingAirTickets = [];
      _clearExtraMembers(_a_extraMembers);
      _resetSharedGuest();
      _sharedPackageAmount.clear();
      _sharedPackageShared = false;
      // _sharedReservationNo.clear();
      _resetAirTicketFields();
      // The reservation is saved, so its remark, contact person and approver go
      // with it.
      _a_remarksCtrl.clear();
      _a_hamoueContactPerson = null;
      _a_paymentBy = '';
      _a_paymentByError = false;
      _a_approver = null;
      _a_assignedGuestKeys.clear();
      _a_guestAssignError = false;
      // An emptied form starts over at the guest again.
      _airStep = 0;
    });
  }

  /// Moves the Hotel tab on to its booking step, but only once the guest half
  /// holds a member worth booking for — the booking fields all hang off that
  /// guest, so letting a blank one through just defers the complaint.
  void _goToHotelBookingStep() {
    FocusScope.of(context).unfocus();
    if (!(_hotelGuestFormKey.currentState?.validate() ?? false)) return;
    if (!_validateExtraMembers(
      _h_extraMembers,
      primaryMid: _sharedMemberId.text.trim(),
    )) {
      return;
    }
    setState(() {
      // The guest list is only settled now, so the assignment is seeded here
      // rather than at build time.
      _dropUnknownAssignedGuests(_h_assignedGuestKeys, _hotelAssignableGuests);
      _preselectSoleHotelGuest();
      _hotelStep = 1;
    });
  }

  /// The Air Ticket tab's counterpart of [_goToHotelBookingStep].
  void _goToAirBookingStep() {
    FocusScope.of(context).unfocus();
    if (!(_airGuestFormKey.currentState?.validate() ?? false)) return;
    if (!_validateExtraMembers(
      _a_extraMembers,
      primaryMid: _sharedMemberId.text.trim(),
    )) {
      return;
    }
    setState(() {
      _dropUnknownAssignedGuests(_a_assignedGuestKeys, _airAssignableGuests);
      _preselectSoleAirGuest();
      _airStep = 1;
    });
  }

  /// Back to the guest step. Nothing is validated on the way back — the point
  /// of going back is usually to fix what the complaint was about.
  void _goToGuestStep() {
    FocusScope.of(context).unfocus();
    setState(() {
      _hotelStep = 0;
      _airStep = 0;
    });
  }

  Future<void> _onSave() async {
    switch (_activeSection) {
      case _Section.hotel:
        await _saveHotelSection();
        break;
      case _Section.airTicket:
        await _saveAirSection();
        break;
      case _Section.transport:
        await _saveTransportSection();
        break;
    }
  }

  // debugPrint truncates long lines, so emit the payload in chunks.
  /// Replaces base64 blobs with a short `<base64: n chars>` marker so a logged
  /// payload stays readable — an uploaded passport page is otherwise hundreds
  /// of thousands of characters and buries the rest of the body.
  Object? _shortenForLog(Object? value) {
    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(
          k,
          k == 'Base64Data' && v is String
              ? '<base64: ${v.length} chars>'
              : _shortenForLog(v),
        ),
      );
    }
    if (value is List) return value.map(_shortenForLog).toList();
    return value;
  }

  void _logLong(String label, Object? payload) {
    final text =
        const JsonEncoder.withIndent('  ').convert(_shortenForLog(payload));
    debugPrint('===== $label =====');
    for (final line in text.split('\n')) {
      for (var i = 0; i < line.length; i += 800) {
        debugPrint(line.substring(i, math.min(i + 800, line.length)));
      }
    }
    debugPrint('===== end $label =====');
  }

  Future<void> _saveTransportSection() async {
    final hasCurrentGuest = _sharedGuestName.text.trim().isNotEmpty ||
        _sharedMemberId.text.trim().isNotEmpty;

    // Only validate the on-screen form when it still holds a member that
    // will be submitted — after "Apply & Add" it is cleared on purpose.
    if (hasCurrentGuest && !(_transportFormKey.currentState?.validate() ?? false)) {
      return;
    }

    if (!_validateExtraMembers(
        _t_extraMembers,
        primaryMid: _sharedMemberId.text.trim(),
        requirePackageAmount: false)) {
      return;
    }

    final allMembers = <Map<String, dynamic>>[
      ..._transportMembers,
      if (hasCurrentGuest) _captureCurrentTransportMember(),
    ];

    if (allMembers.isEmpty) {
      _showSaveErrorSnack('Please add at least one guest before saving');
      return;
    }

    final result = await _quickNotifier.saveTransportReservation(
      members: allMembers,
      log: _logLong,
    );
    _handleSaveResult(
      result,
      onSuccess: _clearAllTransportForm,
      successFallback: 'Transport reservation saved successfully',
    );
  }

  /// Shared tail of the three saves: clear the tab and confirm, or say why not.
  void _handleSaveResult(
    QuickReservationResult result, {
    required VoidCallback onSuccess,
    required String successFallback,
  }) {
    if (!mounted) return;
    if (!result.success) {
      _showSaveErrorSnack(result.message ?? successFallback);
      return;
    }
    onSuccess();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(result.message ?? successFallback)),
      ]),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _saveHotelSection() async {
    // Collect current form's hotel entries
    final currentHotels = List<QuickHotelEntry>.from(_pendingHotels);
    if (_selectedHotelName != null && _selectedHotelName!.isNotEmpty) {
      currentHotels.add(_captureCurrentHotelEntry());
    }
    final hasCurrentGuest = _sharedGuestName.text.trim().isNotEmpty ||
        _sharedMemberId.text.trim().isNotEmpty;

    // Only validate the on-screen form when it still holds a member that will
    // be submitted — after "Apply & Add" it is cleared on purpose. The guest
    // half is checked first and, when it is the one at fault, the tab goes back
    // to it so the error is somewhere the user can actually see it.
    if (hasCurrentGuest || currentHotels.isNotEmpty) {
      if (!(_hotelGuestFormKey.currentState?.validate() ?? false)) {
        setState(() => _hotelStep = 0);
        return;
      }
      if (!(_hotelFormKey.currentState?.validate() ?? false)) return;
    }

    if (!_validateExtraMembers(
        _h_extraMembers,
        primaryMid: _sharedMemberId.text.trim())) {
      setState(() => _hotelStep = 0);
      return;
    }

    // The hotel still on screen goes out as its own room, so it has to name who
    // it is for just like the banked ones did.
    if (_selectedHotelName != null &&
        _selectedHotelName!.isNotEmpty &&
        !_requireHotelGuestAssignment()) {
      return;
    }

    if (!_requireHotelPaymentBy()) return;

    final allMembers = <Map<String, dynamic>>[
      ..._hotelMembers,
      if (hasCurrentGuest || currentHotels.isNotEmpty)
        {
          'guestName': _sharedGuestName.text,
          'memberId': _sharedMemberId.text,
          'packageAmount': _sharedPackageAmount.text,
          'sharedPackage': _sharedPackageShared,
          // 'reservationNo': _sharedReservationNo.text,
          'hotels': currentHotels,
        },
    ];

    if (allMembers.isEmpty) {
      _showSaveErrorSnack('Please add at least one guest before saving');
      return;
    }

    final result = await _quickNotifier.saveHotelReservation(
      members: allMembers,
      extraMembers: _captureExtraMembers(_h_extraMembers),
      liveRemarks: _h_remarks.text,
      hasFamilyMembers: _sharedHasFamilyMembers,
      approver: _h_approver,
      paymentBy: _h_paymentBy.text.trim(),
      contactPerson: _h_hamoueContactPerson ?? '',
      log: _logLong,
    );
    _handleSaveResult(
      result,
      onSuccess: _clearAllHotelForm,
      successFallback: 'Reservation saved successfully',
    );
  }

  Future<void> _saveAirSection() async {
    final hasCurrentGuest = _sharedGuestName.text.trim().isNotEmpty ||
        _sharedMemberId.text.trim().isNotEmpty;

    // Only validate the on-screen form when it still holds a member that will
    // be submitted — after "Apply & Add" it is cleared on purpose. The guest
    // half is checked first and, when it is the one at fault, the tab goes back
    // to it so the error is somewhere the user can actually see it.
    if (hasCurrentGuest) {
      if (!(_airGuestFormKey.currentState?.validate() ?? false)) {
        setState(() => _airStep = 0);
        return;
      }
      if (!(_airFormKey.currentState?.validate() ?? false)) return;
    }

    if (!_validateExtraMembers(
        _a_extraMembers,
        primaryMid: _sharedMemberId.text.trim())) {
      setState(() => _airStep = 0);
      return;
    }

    // A stop with no airport would just be dropped from the route, so ask for
    // it rather than saving a ticket that reads wrong.
    if (_hasIncompleteAirStops) {
      _showSaveErrorSnack(_incompleteAirStopsMessage);
      return;
    }

    // The ticket still on screen goes out as its own row, so it has to name who
    // it is for and what class they fly, just like the banked ones did.
    if (_pendingAirTickets.isEmpty || _hasCurrentAirTicket) {
      if (!_requireAirGuestAssignment()) return;
      if (!_requireAirTicketClass()) return;
    }

    if (!_requireAirPaymentBy()) return;

    final allMembers = <Map<String, dynamic>>[
      ..._airMembers,
      if (hasCurrentGuest) _captureCurrentAirMember(),
    ];

    if (allMembers.isEmpty) {
      _showSaveErrorSnack('Please add at least one guest before saving');
      return;
    }

    // Every ticket for this guest: the ones banked with "Add Another Air
    // Ticket" plus the one still on screen. A blank form after banking
    // contributes nothing. The repository tags each with the primary member.
    final tickets = <Map<String, dynamic>>[
      ..._pendingAirTickets,
      if (_pendingAirTickets.isEmpty || _hasCurrentAirTicket)
        _captureCurrentAirTicket(),
    ];

    final result = await _quickNotifier.saveAirReservation(
      members: allMembers,
      tickets: tickets,
      extraMembers: _captureExtraMembers(_a_extraMembers),
      liveRemarks: _a_remarksCtrl.text,
      hasFamilyMembers: _sharedHasFamilyMembers,
      approver: _a_approver,
      contactPerson: _a_hamoueContactPerson ?? '',
      paymentBy: _a_paymentBy,
      log: _logLong,
    );
    _handleSaveResult(
      result,
      onSuccess: _clearAllAirForm,
      successFallback: 'Reservation saved successfully',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fontSettingsProvider);
    // Reference data, the location's prefix rules and the in-flight flag: this
    // is what makes the getters above rebuild the tree when the notifier moves.
    ref.watch(quickReservationBallysProvider);
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          appBar: AppBar(
            centerTitle: true,
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'Quick Reservation',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop())
                  context.pop();
                else
                  context.go('/reservationMain');
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded),
                tooltip: 'Copy message',
                onPressed: _onCopy,
              ),
            ],
          ),
          body: Theme(
            data: Theme.of(context).copyWith(
              textTheme: Theme.of(context).textTheme.copyWith(
                    titleMedium: kInputTextStyle,
                  ),
            ),
            child: Column(
              children: [
                Container(
                  color: _accentColor,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Row(
                    children: [
                      _sectionTab(
                        _Section.airTicket,
                        Icons.flight_rounded,
                        'Air Ticket',
                      ),
                      const SizedBox(width: 8),
                      _sectionTab(
                          _Section.hotel, Icons.hotel_rounded, 'Hotel'),
                      const SizedBox(width: 8),
                      _sectionTab(
                        _Section.transport,
                        Icons.directions_car_rounded,
                        'Transport',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: switch (_activeSection) {
                      _Section.hotel =>
                        _HotelForm(key: const ValueKey('hotel'), state: this),
                      _Section.airTicket =>
                        _AirForm(key: const ValueKey('air'), state: this),
                      _Section.transport => _TransportForm(
                          key: const ValueKey('transport'), state: this),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isLoading)
          Container(
            color: const Color.fromARGB(120, 0, 0, 0),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _sectionTab(_Section section, IconData icon, String label) {
    final active = _activeSection == section;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeSection = section),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: active ? _accentColor : Colors.white),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? _accentColor : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper functions
// ─────────────────────────────────────────────────────────────────────────────
/// The "Request Approval From" dropdown — who the reservation is being sent to
/// for approval, from `GetAuthorizationLevels`. Same list and same payload as
/// the new reservation screen; leaving it alone saves without an approver.
///
/// An InputDecorator around a plain DropdownButton rather than a
/// DropdownButtonFormField, so the clear button can reset the field and a
/// reloaded list can drop the selection.
Widget _approverDropdown({
  required AuthorizationLevel? value,
  required List<AuthorizationLevel> levels,
  required bool loading,
  required ValueChanged<AuthorizationLevel?> onChanged,
  required Color accent,
}) {
  return InputDecorator(
    isEmpty: value == null,
    decoration: _fieldDeco(
      'Request Approval From',
      icon: Icons.verified_user_outlined,
      accent: accent,
    ).copyWith(
      suffixIcon: loading
          ? const Padding(
              padding: EdgeInsets.all(14.0),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : (value != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: () => onChanged(null),
                )
              : null),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<AuthorizationLevel>(
        value: value,
        isExpanded: true,
        style: kInputTextStyle,
        // The approver's name is all the row carries, so the closed field can
        // paint the same single line the menu does.
        selectedItemBuilder: (context) => levels
            .map(
              (level) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  level.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kInputTextStyle,
                ),
              ),
            )
            .toList(),
        items: levels
            .map(
              (level) => DropdownMenuItem<AuthorizationLevel>(
                value: level,
                child: Text(
                  level.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: levels.isEmpty ? null : onChanged,
      ),
    ),
  );
}

InputDecoration _fieldDeco(
  String label, {
  IconData? icon,
  Color accent = const Color(0xFFE65C00),
}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(
      color: Colors.black,
      fontWeight: FontWeight.bold,
      fontSize: 16,
    ),
    floatingLabelStyle: const TextStyle(
      color: Colors.black,
      fontWeight: FontWeight.bold,
      fontSize: 17,
    ),
    hintStyle: const TextStyle(
      color: Colors.black87,
      fontWeight: FontWeight.bold,
      fontSize: 16,
    ),
    prefixIcon: icon != null ? Icon(icon, size: 20, color: accent) : null,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: accent, width: 1.8),
    ),
  );
}

Widget _sectionHeader(String title, Color color, IconData icon) {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ],
    ),
  );
}

/// Read-only date field driven by a picker. When [onClear] is given, a ✕
/// appears while the field holds a date — the picker itself can only ever set
/// one, so without this a date picked by mistake could not be taken back.
Widget _dateField(
  BuildContext context,
  String label,
  TextEditingController ctrl,
  Color accent,
  VoidCallback onTap, {
  VoidCallback? onClear,
  String? Function(String?)? validator,
}) {
  final hasValue = ctrl.text.trim().isNotEmpty;
  return TextFormField(
    // The field's identity follows the value it shows. These are read-only
    // tap-to-pick fields, so keying on the text costs nothing and means a reset
    // can never leave the previous date on screen — clearing the controller
    // alone does, which is why every reset path used to have to remember to
    // bump a UniqueKey of its own. Missing one was the bug.
    key: ValueKey('$label|${ctrl.text}'),
    controller: ctrl,
    readOnly: true,
    style: kInputTextStyle,
    decoration: _fieldDeco(
      label,
      icon: Icons.calendar_today_rounded,
      accent: accent,
    ).copyWith(
      suffixIcon: (onClear != null && hasValue)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.close_rounded, color: accent, size: 20),
                  tooltip: 'Clear date',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                  onPressed: onClear,
                ),
                Icon(Icons.arrow_drop_down, color: accent),
                const SizedBox(width: 8),
              ],
            )
          : Icon(Icons.arrow_drop_down, color: accent),
    ),
    onTap: onTap,
    validator: validator,
  );
}

Widget _rowPair(Widget left, Widget right) {
  return Row(
    children: [
      Expanded(child: left),
      const SizedBox(width: 10),
      Expanded(child: right),
    ],
  );
}

Widget _guestIdentityRow({
  required BuildContext context,
  required TextEditingController memberIdCtrl,
  required TextEditingController memberIdNumberCtrl,
  required TextEditingController memberNameCtrl,
  required Color accent,
  required String midLabel,
  required String nameLabel,
  required VoidCallback onSearchById,
  required VoidCallback onSearchByName,
  required VoidCallback onProfileTap,
  required bool profileEnabled,
  required bool isNumericOnly,
  required List<String> prefixes,
  required String selectedPrefix,
  required ValueChanged<String> onPrefixChanged,
  FormFieldValidator<String>? memberIdValidator,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: memberIdNumberCtrl,
              style: kInputTextStyle,
              keyboardType: TextInputType.number,
              validator: memberIdValidator,
              decoration: _fieldDeco(midLabel, accent: accent).copyWith(
                prefixIcon: isNumericOnly
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedPrefix,
                            style: kInputTextStyle,
                            items: prefixes
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p, style: kInputTextStyle),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                onPrefixChanged(v);
                                memberIdCtrl.text =
                                    '$v${memberIdNumberCtrl.text}';
                              }
                            },
                          ),
                        ),
                      ),
                suffixIcon: IconButton(
                  icon: Icon(Icons.search, color: accent),
                  onPressed: () {
                    memberIdCtrl.text = isNumericOnly
                        ? memberIdNumberCtrl.text
                        : '$selectedPrefix${memberIdNumberCtrl.text}';
                    onSearchById();
                  },
                ),
              ),
              onChanged: (value) {
                memberNameCtrl.clear();
                memberIdCtrl.text =
                    isNumericOnly ? value : '$selectedPrefix$value';
              },
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: profileEnabled ? onProfileTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: profileEnabled
                  ? const Color.fromARGB(255, 0, 0, 0)
                  : Colors.grey.shade400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            ),
            child: const Icon(Icons.person_search, size: 25),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextFormField(
        controller: memberNameCtrl,
        style: kInputTextStyle,
        decoration: _fieldDeco(
          nameLabel,
          icon: Icons.person_outline,
          accent: accent,
        ).copyWith(
          suffixIcon: IconButton(
            icon: Icon(Icons.search, color: accent),
            onPressed: onSearchByName,
          ),
        ),
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => memberIdNumberCtrl.clear(),
      ),
    ],
  );
}

// ── Shared added-members section widget ──────────────────────────────────────
Widget _addedMembersSection({
  required List<Map<String, dynamic>> members,
  required Color accent,
  required String Function(Map<String, dynamic>) textBuilder,
  required VoidCallback Function(int) onRemove,
}) {
  if (members.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.people_alt_rounded, color: accent, size: 20),
            const SizedBox(width: 10),
            Text(
              'Added Members (${members.length})',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            Text(
              'Tap × to remove',
              style: TextStyle(color: accent.withOpacity(0.6), fontSize: 12),
            ),
          ],
        ),
      ),
      ...members.asMap().entries.map((e) {
        final i = e.key;
        final m = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withOpacity(0.45), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.07),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: accent.withOpacity(0.18),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (m['guestName'] as String? ?? '').isNotEmpty
                                ? m['guestName'] as String
                                : '—',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            m['memberId'] as String? ?? '',
                            style: TextStyle(
                              color: accent,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Remove member ${i + 1}',
                      onPressed: onRemove(i),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: _PreviewCard(text: textBuilder(m), accent: accent),
              ),
            ],
          ),
        );
      }).toList(),
    ],
  );
}

// ── Extra guest sharing the transport request ────────────────────────────────
/// One "Add More Guest" card: who the extra guest is and their own package
/// amount. They inherit the hotels / flights / vehicles and dates of the guest
/// in the form, so no booking fields appear here.
Widget _extraMemberCard(
  _QuickReservationBallysScreenState state,
  List<_ExtraMember> rows,
  int index,
  Color accent, {
  /// Label under the guest number — "Same Request" on transport, "Same
  /// Package" on the hotel and air ticket tabs.
  String subtitle = 'Same Request',

  /// The hotel and air ticket tabs carry the family-members tick, matching the
  /// new reservation screen's member card. Transport has no such field.
  bool showFamilyMembers = false,

  /// Transport requests are not billed against a package, so their extra guests
  /// only carry who they are.
  bool showPackageAmount = true,
}) {
  final row = rows[index];

  return Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: accent.withOpacity(0.35)),
    ),
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: accent,
                foregroundColor: Colors.white,
                child: Text('${index + 2}', style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Guest ${index + 2} — $subtitle',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2430),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => state._removeExtraMember(rows, index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: row.midNumberController,
            style: kInputTextStyle,
            keyboardType: TextInputType.number,
            decoration: _fieldDeco('Membership No', accent: accent).copyWith(
              prefixIcon: state._isNumericOnlyLocation
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: state._prefixes.contains(row.prefix)
                              ? row.prefix
                              : (state._prefixes.isEmpty
                                  ? null
                                  : state._prefixes.first),
                          style: kInputTextStyle,
                          items: state._prefixes
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              state.setState(() => row.prefix = value!),
                        ),
                      ),
                    ),
              suffixIcon: IconButton(
                icon: Icon(Icons.search, color: accent),
                onPressed: () =>
                    state._openExtraMemberSearch(rows, index, 8002),
              ),
            ),
            // The name belongs to the old ID — clear it so a stale pairing is
            // never submitted.
            onChanged: (_) =>
                state.setState(() => row.nameController.clear()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: row.nameController,
            style: kInputTextStyle,
            decoration: _fieldDeco('Guest Name', accent: accent).copyWith(
              suffixIcon: IconButton(
                icon: Icon(Icons.search, color: accent),
                onPressed: () =>
                    state._openExtraMemberSearch(rows, index, 8003),
              ),
            ),
          ),
          if (showPackageAmount) ...[
            const SizedBox(height: 12),
            // Keyed on the row itself so removing a card takes its picker state
            // with it instead of leaving it behind on the next row.
            PackageAmountFieldBallys(
              key: ValueKey(row),
              controller: row.packageAmountController,
              noPackage: row.sharedPackage,
              // A shared member can still be billed an amount of their own, so
              // ticking Shared records that and leaves the picker usable.
              allowAmountWhenShared: true,
              onNoPackageChanged: (value) =>
                  state.setState(() => row.sharedPackage = value),
              textStyle: kInputTextStyle,
              accent: accent,
              decoration: _fieldDeco(
                'Package Amount',
                icon: Icons.currency_rupee,
                accent: accent,
              ),
            ),
          ],
          if (showFamilyMembers) ...[
            const SizedBox(height: 12),
            _familyMembersTick(
              accent: accent,
              checked: row.hasFamilyMembers,
              onChanged: (value) =>
                  state.setState(() => row.hasFamilyMembers = value),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Full-width outlined button that banks the booking currently in the form and
/// clears it for the next one — "Add Another Hotel" / "Add Another Air Ticket".
Widget _addAnotherButton({
  required Color accent,
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withOpacity(0.6), width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        backgroundColor: accent.withOpacity(0.04),
      ),
      icon: Icon(icon),
      label: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Full-width primary action that posts the section to the API.
Widget _confirmReservationButton({
  required Color accent,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      icon: const Icon(Icons.done),
      label: const Text(
        'Confirm Reservation',
        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// The two-step progress bar at the top of the Hotel and Air Ticket tabs:
/// ① Guest → ② the booking itself.
///
/// The Guest pill is tappable from step 2 so a member can be corrected without
/// losing the booking below it. The second pill is not — stepping forward goes
/// through "Next", which is what validates the guest.
Widget _stepIndicator({
  required Color accent,
  required int step,
  required String bookingLabel,
  required IconData bookingIcon,
  required VoidCallback onGuestTap,
}) {
  Widget pill({
    required int index,
    required String label,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final active = step == index;
    final done = step > index;
    final filled = active || done;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? accent.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? accent : Colors.transparent,
                  border: Border.all(
                    color: filled ? accent : Colors.grey.shade400,
                    width: 1.6,
                  ),
                ),
                child: Icon(
                  done ? Icons.check_rounded : icon,
                  size: 15,
                  color: filled ? Colors.white : Colors.grey.shade500,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: filled ? accent : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
    child: Row(
      children: [
        pill(
          index: 0,
          label: 'Guest',
          icon: Icons.person_rounded,
          onTap: step == 0 ? null : onGuestTap,
        ),
        Container(
          width: 22,
          height: 2,
          color: step > 0 ? accent : Colors.grey.shade300,
        ),
        pill(index: 1, label: bookingLabel, icon: bookingIcon),
      ],
    ),
  );
}

/// Names the guest the booking step is filling in for — they were picked a step
/// back and are otherwise off screen. Tapping it returns to the guest step.
Widget _stepGuestBanner({
  required Color accent,
  required String memberId,
  required String guestName,
  required int extraGuests,
  required VoidCallback onTap,
}) {
  final id = memberId.trim();
  final name = guestName.trim();
  final title = [
    if (id.isNotEmpty) id,
    if (name.isNotEmpty) name,
  ].join('  •  ');

  return GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_rounded, color: accent, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'No guest selected' : title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: title.isEmpty ? Colors.grey.shade600 : Colors.black,
                  ),
                ),
                if (extraGuests > 0)
                  Text(
                    extraGuests == 1
                        ? '+1 more guest on this package'
                        : '+$extraGuests more guests on this package',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
              ],
            ),
          ),
          Icon(Icons.edit_rounded, color: accent, size: 17),
        ],
      ),
    ),
  );
}

/// Who the booking in the form is for: every guest on the reservation, ticked
/// one by one or several at a time. Mirrors the assignment card on the new
/// reservation screen's hotel and air ticket selectors.
///
/// [locked] guests already hold a booking of their own — a guest sleeps in one
/// room and flies on one ticket — so they are greyed out rather than offered
/// again.
Widget _guestAssignmentCard({
  required Color accent,
  required String title,
  required String emptyMessage,
  required String errorMessage,
  required List<AccompanyingMember> guests,
  required Set<String> selectedKeys,
  required Set<String> lockedKeys,
  required String Function(AccompanyingMember) keyOf,
  required void Function(String key, bool selected) onToggle,
  required void Function(bool selectAll) onSelectAll,
  required bool showError,
  required String lockedLabel,
}) {
  final selectable =
      guests.where((g) => !lockedKeys.contains(keyOf(g))).toList();
  final allSelected = selectable.isNotEmpty &&
      selectable.every((g) => selectedKeys.contains(keyOf(g)));

  Widget row(AccompanyingMember guest) {
    final key = keyOf(guest);
    final locked = lockedKeys.contains(key);
    final selected = selectedKeys.contains(key);
    final label = [
      if (guest.mid.trim().isNotEmpty) guest.mid.trim(),
      if (guest.guestName.trim().isNotEmpty) guest.guestName.trim(),
    ].join('  —  ');

    return InkWell(
      onTap: locked ? null : () => onToggle(key, !selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Checkbox(
                value: selected,
                activeColor: accent,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged:
                    locked ? null : (checked) => onToggle(key, checked == true),
              ),
            ),
            Expanded(
              child: Text(
                label.isEmpty ? '(unnamed guest)' : label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: locked ? Colors.grey : Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (locked) ...[
              Icon(Icons.check_circle_outline,
                  size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                lockedLabel,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ] else ...[
              Icon(
                guest.hasFamilyMembers
                    ? Icons.family_restroom
                    : Icons.person_outline,
                size: 16,
                color: guest.hasFamilyMembers
                    ? Colors.green.shade700
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Text(
                guest.hasFamilyMembers ? 'Family included' : 'No family',
                style: TextStyle(
                  fontSize: 12.5,
                  color: guest.hasFamilyMembers
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: showError ? Colors.red : const Color(0xFFDADDE3),
        width: showError ? 1.5 : 1,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.group, size: 18, color: accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$title (${selectedKeys.length}/${selectable.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (selectable.length > 1)
              TextButton(
                onPressed: () => onSelectAll(!allSelected),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  allSelected ? 'Clear' : 'Select all',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ...guests.map(row),
        if (guests.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Go back and add a guest first',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          )
        else if (selectable.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              emptyMessage,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
        if (showError)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorMessage,
              style: const TextStyle(fontSize: 13, color: Colors.red),
            ),
          ),
      ],
    ),
  );
}

/// Full-width "Next" that closes the guest step.
Widget _stepNextButton({
  required Color accent,
  required String label,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// "Back to Guest" on the booking step.
Widget _stepBackButton({
  required Color accent,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent, width: 1.6),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.arrow_back_rounded, size: 18),
      label: const Text(
        'Back to Guest',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// Full-width "Add More Guest" button that appends an extra-member row.
Widget _addMoreGuestButton({
  required Color accent,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent, width: 1.6),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const Icon(Icons.group_add, size: 18),
      label: const Text(
        'Add More Guest',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// "Family Members Included" tick, styled to sit alongside the other cards on
/// this screen. Mirrors the same field on the new reservation screen.
Widget _familyMembersTick({
  required Color accent,
  required bool checked,
  required ValueChanged<bool> onChanged,
}) {
  return InkWell(
    onTap: () => onChanged(!checked),
    borderRadius: BorderRadius.circular(10),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: checked ? accent : Colors.grey.shade300,
          width: checked ? 1.6 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            activeColor: accent,
            onChanged: (value) => onChanged(value ?? false),
          ),
          Icon(Icons.family_restroom, size: 20, color: accent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Family Members Included',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Airport dropdown
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Transit stops for one leg (Multi Sector)
// ─────────────────────────────────────────────────────────────────────────────
/// A picker per transit stop, in travel order, with the whole leg previewed
/// above so it is clear the stops sit between that leg's From and To.
class _SectorEditor extends StatelessWidget {
  final _QuickReservationBallysScreenState state;
  final String label;
  final Color accent;
  final List<FlightSectorEntry> sectors;
  final Airport? from;
  final Airport? to;

  const _SectorEditor({
    required this.state,
    required this.label,
    required this.accent,
    required this.sectors,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context) {
    final routeCodes = [
      from?.airportCode,
      ...sectors.map((sector) => sector.airport?.airportCode),
      to?.airportCode,
    ].map((code) => (code == null || code.trim().isEmpty) ? '...' : code);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.35), width: 1.2),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.connecting_airports_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            routeCodes.join(' → '),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          for (var i = 0; i < sectors.length; i++) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _AirportDropdown(
                    key: sectors[i].key,
                    label: 'Stop ${i + 1}',
                    accent: accent,
                    selectedAirport: sectors[i].airport,
                    onChanged: (a) =>
                        state.setState(() => sectors[i].airport = a),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove stop',
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      color: Colors.red, size: 22),
                  onPressed: () => state.setState(() => sectors.removeAt(i)),
                ),
              ],
            ),
            // The stop's own travel day, so a route spread over several days
            // reads in order rather than as a bare list of airports.
            Padding(
              // Lines up with the airport field above, clear of the remove
              // button's column.
              padding: const EdgeInsets.only(top: 8, right: 46),
              child: _SectorDateField(
                accent: accent,
                label: 'Stop ${i + 1} Date',
                date: sectors[i].date,
                onPick: () => state._pickSectorDate(sectors[i], i + 1),
                onClear: sectors[i].date == null
                    ? null
                    : () => state.setState(() => sectors[i].date = null),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  state.setState(() => sectors.add(FlightSectorEntry())),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text(
                'Add Stop',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: TextButton.styleFrom(foregroundColor: accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// One transit stop's travel day. Reads "Select date" until a day is picked,
/// which is what the save refuses to go out without.
class _SectorDateField extends StatelessWidget {
  final Color accent;
  final String label;
  final DateTime? date;
  final VoidCallback onPick;

  /// Null while there is no date to clear.
  final VoidCallback? onClear;

  const _SectorDateField({
    required this.accent,
    required this.label,
    required this.date,
    required this.onPick,
    this.onClear,
  });

  String get _text => date == null
      ? 'Select date'
      : '${date!.year}-${date!.month.toString().padLeft(2, '0')}'
          '-${date!.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _fieldDeco(
          label,
          icon: Icons.calendar_today_rounded,
          accent: accent,
        ).copyWith(
          suffixIcon: hasDate
              ? IconButton(
                  tooltip: 'Clear date',
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: Colors.grey.shade600),
                  onPressed: onClear,
                )
              : null,
        ),
        child: Text(
          _text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: hasDate ? Colors.black : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

class _AirportDropdown extends ConsumerWidget {
  final String label;
  final Color accent;
  final Airport? selectedAirport;
  final ValueChanged<Airport?> onChanged;
  const _AirportDropdown({
    super.key,
    required this.label,
    required this.accent,
    required this.selectedAirport,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final airports = ref.watch(airportsProvider);
    return DropdownSearch<Airport>(
      selectedItem: selectedAirport,
      items: (filter, _) {
        final notifier = ref.read(airportsProvider.notifier);
        if (filter.isEmpty) {
          final initial = [...airports];
          initial.sort((a, b) => (a.airportName ?? '')
              .toLowerCase()
              .compareTo((b.airportName ?? '').toLowerCase()));
          return initial;
        }
        final lf = filter.toLowerCase();
        final results = notifier.allAirports
            .where(
              (a) =>
                  (a.airportCode ?? '').toLowerCase().contains(lf) ||
                  (a.cityName ?? '').toLowerCase().contains(lf) ||
                  (a.airportName ?? '').toLowerCase().contains(lf) ||
                  (a.country ?? '').toLowerCase().contains(lf),
            )
            .toList();

        // Alphabetical order by airport name.
        results.sort((a, b) => (a.airportName ?? '')
            .toLowerCase()
            .compareTo((b.airportName ?? '').toLowerCase()));

        return results;
      },
      itemAsString: (a) =>
          '${a.airportCode ?? ''} · ${a.cityName ?? ''} · ${a.airportName ?? ''} · ${a.country ?? ''}',
      compareFn: (a, b) => a.airportCode == b.airportCode,
      decoratorProps: DropDownDecoratorProps(
        decoration: _fieldDeco(
          label,
          icon: Icons.flight_takeoff_rounded,
          accent: accent,
        ),
      ),
      dropdownBuilder: (context, item) {
        if (item == null) return const Text('');
        return Text(
          '${item.cityName ?? ''} (${item.airportCode ?? ''})',
          style: kInputTextStyle,
          overflow: TextOverflow.ellipsis,
        );
      },
      onChanged: onChanged,
      popupProps: PopupProps.dialog(
        showSearchBox: true,
        searchFieldProps: TextFieldProps(
          autofocus: true,
          style: kInputTextStyle,
          decoration: InputDecoration(
            hintText: 'Search by city, code or country...',
            hintStyle: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
            prefixIcon: const Icon(Icons.search),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        itemBuilder: (ctx, item, isSelected, isFocused) => ListTile(
          // Same display as the new reservation screen airport search.
          title: Text(
            '${item.airportName ?? "Unknown"} (${item.airportCode ?? "N/A"})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            [
              item.cityName,
              item.country,
              item.countryAbbr,
            ]
                .where((e) => e != null && e.isNotEmpty)
                .join(" · "),
            style: const TextStyle(fontSize: 13.0),
          ),
          selected: isSelected,
          tileColor: isFocused ? Colors.grey.shade100 : null,
        ),
        dialogProps: DialogProps(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Airline dropdown — the active airlines from API 90156, by name
// ─────────────────────────────────────────────────────────────────────────────
class _AirlineDropdown extends StatelessWidget {
  final Key dropdownKey;
  final List<AirlineResponse> items;
  final AirlineResponse? selectedItem;
  final bool isLoading;
  final Color accent;
  final ValueChanged<AirlineResponse?> onChanged;

  const _AirlineDropdown({
    required this.dropdownKey,
    required this.items,
    required this.selectedItem,
    required this.isLoading,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading airlines...',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

    return DropdownSearch<AirlineResponse>(
      key: dropdownKey,
      selectedItem: selectedItem,
      items: (filter, _) {
        if (filter.isEmpty) return items;
        final lf = filter.toLowerCase();
        return items
            .where((a) => a.airlineName.toLowerCase().contains(lf))
            .toList();
      },
      itemAsString: (airline) => airline.airlineName,
      compareFn: (a, b) => a.airlineName == b.airlineName,
      enabled: items.isNotEmpty,
      decoratorProps: DropDownDecoratorProps(
        decoration: _fieldDeco(
          items.isEmpty ? 'Airline  (unavailable)' : 'Select Airline',
          icon: Icons.airplanemode_active_rounded,
          accent: accent,
        ),
      ),
      dropdownBuilder: (context, item) {
        if (item == null) return const Text('');
        return Text(
          item.airlineName,
          style: kInputTextStyle,
          overflow: TextOverflow.ellipsis,
        );
      },
      onChanged: onChanged,
      popupProps: PopupProps.dialog(
        showSearchBox: true,
        searchFieldProps: TextFieldProps(
          autofocus: true,
          style: kInputTextStyle,
          decoration: InputDecoration(
            hintText: 'Search airline...',
            hintStyle: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
            prefixIcon: const Icon(Icons.search),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        itemBuilder: (ctx, item, isSelected, isFocused) => ListTile(
          title: Text(
            item.airlineName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          selected: isSelected,
          tileColor: isFocused ? Colors.grey.shade100 : null,
        ),
        dialogProps: DialogProps(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOTEL FORM
// ─────────────────────────────────────────────────────────────────────────────
class _HotelForm extends StatelessWidget {
  final _QuickReservationBallysScreenState state;
  const _HotelForm({super.key, required this.state});

  static String _hotelName(Map<String, dynamic>? item) =>
      (item?['hotel_name'] ?? '') as String;
  static double? _hotelId(Map<String, dynamic>? item) =>
      (item?['hotel'] as num?)?.toDouble();

  /// Grading of a room category, e.g. "(Standard)" — comes with the category
  /// in the combined catalog.
  static String _hotelCategory(Map<String, dynamic>? item) =>
      (item?['HotelCategory'] ?? '') as String;

  static String _categoryWithGrade(Map<String, dynamic>? item) {
    final name = (item?['CatName'] ?? '') as String;
    final grade = _hotelCategory(item);
    if (name.isEmpty) return '';
    return grade.isEmpty ? name : '$name $grade';
  }

  @override
  Widget build(BuildContext context) {
    const accent = _QuickReservationBallysScreenState._hotelColor;
    // Both locations arrive in the one catalog; the type picked in step ②
    // decides which half of it the hotel dropdown offers.
    final hotels =
        state.ref.watch(hotelCatalogHotelsProvider(state._selectedHotelLocation));
    return Column(
      children: [
        _stepIndicator(
          accent: accent,
          step: state._hotelStep,
          bookingLabel: 'Hotel',
          bookingIcon: Icons.hotel_rounded,
          onGuestTap: state._goToGuestStep,
        ),
        Expanded(
          // Both steps stay in the tree so their fields keep their state — and
          // stay validatable — while only the current one is on screen.
          child: IndexedStack(
            index: state._hotelStep,
            sizing: StackFit.expand,
            children: [
              _guestStep(context, accent),
              _bookingStep(context, accent, hotels),
            ],
          ),
        ),
      ],
    );
  }

  /// Step ① — who the reservation is for.
  Widget _guestStep(BuildContext context, Color accent) {
    return Form(
      key: state._hotelGuestFormKey,
      // A lazy ListView only builds the rows near the viewport, and
      // Form.validate() skips fields that are not mounted, so saving from the
      // top of the form silently bypassed every validator further down. A
      // Column keeps all fields alive at all times.
      child: SingleChildScrollView(
        controller: state._hotelGuestScrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _guestIdentityRow(
            context: context,
            memberIdCtrl: state._sharedMemberId,
            memberIdNumberCtrl: state._sharedMidNumber,
            memberNameCtrl: state._sharedGuestName,
            accent: accent,
            midLabel: 'Membership No *',
            nameLabel: 'Guest Name *',
            onSearchById: () => state._openGuestSearch(
              iid: 8002,
              onCardVisible: () =>
                  state.setState(() => state._sharedGuestCardVisible = true),
            ),
            onSearchByName: () => state._openGuestSearch(
              iid: 8003,
              onCardVisible: () =>
                  state.setState(() => state._sharedGuestCardVisible = true),
            ),
            onProfileTap: () => state._navigateToProfile(
              state._sharedMemberId.text,
              state._sharedGuestName.text,
            ),
            profileEnabled: state._sharedGuestCardVisible,
            isNumericOnly: state._isNumericOnlyLocation,
            prefixes: state._prefixes,
            selectedPrefix: state._selectedPrefix,
            onPrefixChanged: (v) {
              state._quickNotifier.selectPrefix(v);
              state.setState(() {
                state._sharedMemberId.text =
                    '$v${state._sharedMidNumber.text}';
              });
            },
          ),
          const SizedBox(height: 12),
          if (state._sharedGuestCardVisible &&
              state._sharedMemberId.text.isNotEmpty &&
              state._sharedGuestName.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GuestDisplayCardSpecialGiftview(
                memberIdText: state._sharedMemberId.text,
                memberNameText: state._sharedGuestName.text,
                showCard: true,
                showLastVisitDate: true,
              ),
            ),
          PackageAmountFieldBallys(
            controller: state._sharedPackageAmount,
            noPackage: state._sharedPackageShared,
            // Shared only records that the package is shared — an amount can
            // still be picked alongside it.
            allowAmountWhenShared: true,
            onNoPackageChanged: (v) =>
                state.setState(() => state._sharedPackageShared = v),
            textStyle: kInputTextStyle,
            accent: accent,
            decoration: _fieldDeco(
              'Package Amount',
              icon: Icons.currency_rupee,
              accent: accent,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Package Amount is required';
              }
              return null;
            },
          ),
          // const SizedBox(height: 12),
          // TextFormField(
          //   controller: state._sharedReservationNo,
          //   style: kInputTextStyle,
          //   decoration: _fieldDeco(
          //     'Manual Reservation No',
          //     icon: Icons.confirmation_number_outlined,
          //     accent: accent,
          //   ),
          // ),
          const SizedBox(height: 12),

          // ── Family members of THIS guest ────────────────────────────────────
          _familyMembersTick(
            accent: accent,
            checked: state._sharedHasFamilyMembers,
            onChanged: (v) =>
                state.setState(() => state._sharedHasFamilyMembers = v),
          ),
          const SizedBox(height: 12),

          // ── Extra guests on the SAME package ────────────────────────────────
          ...List.generate(
            state._h_extraMembers.length,
            (i) => _extraMemberCard(
              state,
              state._h_extraMembers,
              i,
              accent,
              subtitle: 'Same Package',
              showFamilyMembers: true,
            ),
          ),
          _addMoreGuestButton(
            accent: accent,
            onPressed: () => state._addExtraMember(state._h_extraMembers),
          ),
          const SizedBox(height: 24),
          _stepNextButton(
            accent: accent,
            label: 'Next: Hotel Details',
            onPressed: state._goToHotelBookingStep,
          ),
          const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Asked before the hotel: which of the two lists it comes from. Both arrive
  /// in the one catalog, so the answer only filters the dropdown below —
  /// switching type re-fetches nothing.
  ///
  /// A [FormField] rather than a plain row, so an unanswered type is caught by
  /// the same `validate()` as every other required field on this step instead
  /// of only showing up as an empty hotel dropdown.
  Widget _hotelLocationPicker(Color accent) {
    return FormField<HotelLocation>(
      initialValue: state._selectedHotelLocation,
      validator: (_) => state._selectedHotelLocation == null
          ? 'Select a hotel type'
          : null,
      builder: (field) {
        final bool hasError = field.errorText != null;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasError ? Colors.red.shade400 : Colors.grey.shade300,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hotel Type *',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final location in HotelLocation.values) ...[
                    Expanded(child: _hotelLocationOption(location, accent, field)),
                    if (location != HotelLocation.values.last)
                      const SizedBox(width: 10),
                  ],
                ],
              ),
              if (hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    field.errorText!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _hotelLocationOption(
    HotelLocation location,
    Color accent,
    FormFieldState<HotelLocation> field,
  ) {
    final bool selected = state._selectedHotelLocation == location;
    final IconData icon = location == HotelLocation.cityHotel
        ? Icons.location_city
        : Icons.landscape_outlined;

    return InkWell(
      onTap: () {
        state._setHotelLocation(location);
        field.didChange(location);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : Colors.grey.shade300,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 20, color: selected ? accent : Colors.grey.shade600),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                location.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? accent : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Step ② — what is being booked for the guest picked in step ①.
  Widget _bookingStep(
    BuildContext context,
    Color accent,
    List<HotelResponse> hotels,
  ) {
    return Form(
      key: state._hotelFormKey,
      // A lazy ListView only builds the rows near the viewport, and
      // Form.validate() skips fields that are not mounted, so saving from the
      // top of the form silently bypassed every validator further down. A
      // Column keeps all fields alive at all times.
      child: SingleChildScrollView(
        controller: state._hotelScrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _bookingGuestBanner(accent),
          const SizedBox(height: 14),

          // ── Who this hotel is booked for ────────────────────────────────────
          _guestAssignmentCard(
            accent: accent,
            title: 'Assign this hotel to',
            emptyMessage: 'Every guest already has a hotel',
            errorMessage: 'Select at least one guest for this hotel',
            guests: state._hotelAssignableGuests,
            selectedKeys: state._h_assignedGuestKeys,
            lockedKeys: state._guestsInPendingHotels(),
            keyOf: state._guestKey,
            onToggle: state._toggleHotelGuest,
            onSelectAll: state._setAllHotelGuests,
            showError: state._h_guestAssignError,
            lockedLabel: 'Already has a hotel',
          ),
          const SizedBox(height: 14),

          // ── Pending hotels list ─────────────────────────────────────────────
          if (state._pendingHotels.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.hotel_rounded, color: accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Hotels Added for This Guest (${state._pendingHotels.length})',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ...state._pendingHotels.asMap().entries.map((e) {
              final idx = e.key;
              final h = e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: accent.withOpacity(0.35), width: 1.2),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: accent.withOpacity(0.15),
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.hotel.isNotEmpty ? h.hotel : '—',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${h.arrival} → ${h.departure}  |  ${h.roomType}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => state.setState(
                          () => state._pendingHotels.removeAt(idx)),
                    ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 4),
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline,
                      color: accent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Fill in the next hotel details below',
                    style: TextStyle(
                        color: accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],

          _dateField(
            context,
            'Arrival Date *',
            state._h_arrivalCtrl,
            accent,
            () async {
              final d = await state._pickDate(
                context,
                label: 'Select Arrival Date',
                initial: state._h_arrivalDate,
                minDate: state._today,
              );
              if (d != null) {
                state._h_arrivalDate = d;
                state._h_arrivalCtrl.text = state._fmt(d);
                if (state._h_departureDate != null &&
                    !state._h_departureDate!.isAfter(d)) {
                  state._h_departureDate = null;
                  state._h_departureCtrl.clear();
                }
                // ignore: invalid_use_of_protected_member
                (context as Element).markNeedsBuild();
              }
            },
            // Clearing the arrival also drops the departure — it is only ever
            // constrained relative to an arrival date.
            onClear: () => state.setState(() {
              state._h_arrivalDate = null;
              state._h_arrivalCtrl.clear();
              state._h_departureDate = null;
              state._h_departureCtrl.clear();
            }),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Arrival Date is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _dateField(
            context,
            'Departure Date *',
            state._h_departureCtrl,
            accent,
            () async {
              final d = await state._pickDate(
                context,
                label: 'Select Departure Date',
                initial: state._h_departureDate,
                minDate: state._minDeparture(state._h_arrivalDate),
              );
              if (d != null) {
                state._h_departureDate = d;
                state._h_departureCtrl.text = state._fmt(d);
                // ignore: invalid_use_of_protected_member
                (context as Element).markNeedsBuild();
              }
            },
            onClear: () => state.setState(() {
              state._h_departureDate = null;
              state._h_departureCtrl.clear();
            }),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Departure Date is required';
              }
              return null;
            },
          ),
            const SizedBox(height: 12),
          _rowPair(
            _StepperField(
              controller: state._h_noOfRooms,
              label: 'No of Rooms',
              icon: Icons.door_back_door_outlined,
              accent: accent,
              // One room per ticked guest, so the count is the assignment's to
              // set once there is one.
              locked: state._roomCountLocked,
              lockedHint: 'One room per assigned guest',
            ),
            _StepperField(
              controller: state._h_noOfPax,
              label: 'No of Pax',
              icon: Icons.group_outlined,
              accent: accent,
            ),
          ),
          const SizedBox(height: 12),
          _StepperField(
            controller: state._h_noOfChildren,
            label: 'No of Children',
            icon: Icons.child_care_outlined,
            accent: accent,
            min: 0,
          ),
          const SizedBox(height: 12),
          _hotelLocationPicker(accent),
          const SizedBox(height: 12),
          DropdownSearch<Map<String, dynamic>>(
            key: state._hotelDropdownKey,
            enabled: state._selectedHotelLocation != null,
            items: (filter, _) {
              final mapped = hotels.map((h) => h.toJson()).toList();
              if (filter.isEmpty) return mapped;
              return mapped
                  .where(
                    (h) => _hotelName(h)
                        .toLowerCase()
                        .contains(filter.toLowerCase()),
                  )
                  .toList();
            },
            itemAsString: (item) => _hotelName(item),
            compareFn: (a, b) => _hotelId(a) == _hotelId(b),
            selectedItem: state._selectedHotel,
            validator: (value) =>
                value == null ? 'Hotel Name is required' : null,
            decoratorProps: DropDownDecoratorProps(
              decoration: _fieldDeco(
                state._selectedHotelLocation == null
                    ? 'Hotel Name  (select hotel type first)'
                    : 'Hotel Name *',
                icon: Icons.business_rounded,
                accent: accent,
              ),
            ),
            dropdownBuilder: (context, selectedItem) => Text(
              _hotelName(selectedItem),
              style: kInputTextStyle,
              overflow: TextOverflow.ellipsis,
            ),
            onChanged: (val) {
              state.setState(() {
                state._selectedHotel = val;
                state._selectedHotelName = _hotelName(val);
                state._selectedHotelId = _hotelId(val);
              });
              if (state._selectedHotelId != null)
                state._loadRoomCategories(state._selectedHotelId!);
            },
            popupProps: PopupProps.dialog(
              showSearchBox: true,
              searchFieldProps: TextFieldProps(
                autofocus: true,
                style: kInputTextStyle,
                decoration: InputDecoration(
                  hintText: 'Search hotel...',
                  hintStyle: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              itemBuilder: (ctx, item, isSelected, isFocused) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: accent.withOpacity(0.12),
                  child: Icon(Icons.hotel_rounded, color: accent, size: 18),
                ),
                title: Text(
                  _hotelName(item),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                selected: isSelected,
                tileColor: isFocused ? Colors.grey.shade100 : null,
              ),
              dialogProps: DialogProps(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownSearch<Map<String, dynamic>>(
            key: state._roomCategoryDropdownKey,
            items: (f, _) => state._roomCategories
                .where(
                  (c) => _categoryWithGrade(c)
                      .toLowerCase()
                      .contains(f.toLowerCase()),
                )
                .toList(),
            itemAsString: (item) => _categoryWithGrade(item),
            compareFn: (a, b) => a['CatCode'] == b['CatCode'],
            selectedItem: state._selectedRoomCategory,
            enabled: state._roomCategories.isNotEmpty,
            decoratorProps: DropDownDecoratorProps(
              decoration: _fieldDeco(
                state._roomCategories.isEmpty
                    ? 'Room Category  (select hotel first)'
                    : 'Room Category *',
                icon: Icons.category_outlined,
                accent: accent,
              ),
            ),
            dropdownBuilder: (context, selectedItem) => Text(
              _categoryWithGrade(selectedItem),
              style: kInputTextStyle,
              overflow: TextOverflow.ellipsis,
            ),
            onChanged: (val) {
              state.setState(() {
                state._selectedRoomCategory = val;
                state._selectedRoomCategoryId = val?['CatCode'] as int?;
                state._selectedRoomCategoryName =
                    (val?['CatName'] ?? '') as String;
              });
              if (state._selectedHotelId != null &&
                  state._selectedRoomCategoryId != null)
                state._loadRoomTypes(
                  state._selectedHotelId!,
                  state._selectedRoomCategoryId!,
                );
            },
            popupProps: PopupProps.dialog(
              showSearchBox: true,
              itemBuilder: (ctx, item, isSelected, isFocused) => ListTile(
                title: Text(
                  (item['CatName'] ?? '') as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: _hotelCategory(item).isEmpty
                    ? null
                    : Text(
                        _hotelCategory(item),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                selected: isSelected,
                tileColor: isFocused ? Colors.grey.shade100 : null,
              ),
              dialogProps: DialogProps(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownSearch<Map<String, dynamic>>(
            key: state._roomTypeDropdownKey,
            items: (f, _) => state._roomTypes
                .where(
                  (t) => ((t['RoomType'] ?? '') as String)
                      .toLowerCase()
                      .contains(f.toLowerCase()),
                )
                .toList(),
            itemAsString: (item) =>
                '${(item['RoomType'] ?? '')} - ${(item['MealPlan'] ?? '')}',
            compareFn: HotelRoomCatalogEntry.sameRoomType,
            selectedItem: state._selectedRoomType,
            enabled: state._roomTypes.isNotEmpty,
            decoratorProps: DropDownDecoratorProps(
              decoration: _fieldDeco(
                state._roomTypes.isEmpty
                    ? 'Room Type  (select category first)'
                    : 'Room Type *',
                icon: Icons.bed_outlined,
                accent: accent,
              ),
            ),
            dropdownBuilder: (context, selectedItem) {
              if (selectedItem == null) return const Text('');
              return Text(
                '${selectedItem['RoomType'] ?? ''} - ${selectedItem['MealPlan'] ?? ''}',
                style: kInputTextStyle,
                overflow: TextOverflow.ellipsis,
              );
            },
            onChanged: (val) {
              state.setState(() {
                state._selectedRoomType = val;
                state._selectedRoomTypeId = val?['ID'] as int?;
                state._selectedRoomTypeName =
                    '${val?['RoomType'] ?? ''} - ${val?['MealPlan'] ?? ''}';
                // The meal plan rides along with the room type in the catalog.
                state._h_mealPlan.text = (val?['MealPlan'] ?? '') as String;
              });
            },
            popupProps: PopupProps.dialog(
              showSearchBox: true,
              itemBuilder: (ctx, item, isSelected, isFocused) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: accent.withOpacity(0.12),
                    child: Icon(Icons.bed_outlined, color: accent, size: 18),
                  ),
                  title: Text(
                    (item['RoomType'] ?? '') as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    (item['MealPlan'] ?? '') as String,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  selected: isSelected,
                  tileColor: isFocused ? Colors.grey.shade100 : null,
                );
              },
              dialogProps: DialogProps(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          _estimatedCost(accent),
          // const SizedBox(height: 12),
          // _rowPair(
          //   _StepperField(
          //     controller: state._h_noOfRooms,
          //     label: 'No of Rooms',
          //     icon: Icons.door_back_door_outlined,
          //     accent: accent,
          //   ),
          //   _StepperField(
          //     controller: state._h_noOfPax,
          //     label: 'No of Pax',
          //     icon: Icons.group_outlined,
          //     accent: accent,
          //   ),
          // ),
          const SizedBox(height: 12),
          _LabeledCard(
            label: 'ECI / LCO Facility',
            accent: accent,
            child: _ChipSelector(
              options: const ['NA', 'ECI', 'LCO', 'ECI & LCO'],
              selected: state._h_eciLco,
              accent: accent,
              onChanged: (v) => state.setState(() => state._h_eciLco = v),
            ),
          ),
          const SizedBox(height: 12),
          _LabeledCard(
            label: 'Payment By *',
            accent: accent,
            errorText: state._h_paymentByError
                ? 'Please select Payment By'
                : null,
            child: _ChipSelector(
              key: ValueKey('payment_by_${state._isBellagio}'),
              options: state._isBellagio
                  ? const [
                      'By Guest',
                      'By Beyond Borders',
                      'By Guest & Beyond Borders',
                    ]
                  : const [
                      'By Guest',
                      'By Hamoos',
                      'By Guest & Hamoos',
                      'Recovery from Cashier',
                    ],
              selected: state._h_paymentBy.text,
              accent: accent,
              onChanged: (v) => state.setState(() {
                state._h_paymentBy.text = v;
                state._h_paymentByError = false;
              }),
            ),
          ),
          const SizedBox(height: 12),

          // ── Hamoos contact person ────────────────────────────────────────────
          if (!state._isBellagio) ...[
            DropdownButtonFormField<String>(
              value: state._h_hamoueContactPerson,
              style: kInputTextStyle,
              decoration: _fieldDeco(
                'Hamoos Contact Person',
                icon: Icons.support_agent_rounded,
                accent: accent,
              ),
              items: state._hamoueContactPersons
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) =>
                  state.setState(() => state._h_hamoueContactPerson = v),
            ),
            const SizedBox(height: 12),
          ],

          // ── Add Another Hotel button ─────────────────────────────────────────
          _addAnotherButton(
            accent: accent,
            icon: Icons.add_business_rounded,
            label: 'Add Another Hotel for This Guest',
            onPressed: state._addAnotherHotel,
          ),
          const SizedBox(height: 12),

          // ── Request Approval From ────────────────────────────────────────────
          _approverDropdown(
            value: state._h_approver,
            levels: state._quick.authorizationLevels,
            loading: state._quick.authorizationLevelsLoading,
            accent: accent,
            onChanged: (v) => state.setState(() => state._h_approver = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: state._h_remarks,
            style: kInputTextStyle,
            decoration: _fieldDeco(
              'Remarks',
              icon: Icons.notes_rounded,
              accent: accent,
            ),
            maxLines: 3,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: 20),
          _addedMembersSection(
            members: state._hotelMembers,
            accent: accent,
            textBuilder: state._singleHotelText,
            onRemove: (i) =>
                () => state.setState(() => state._hotelMembers.removeAt(i)),
          ),
          _stepBackButton(accent: accent, onPressed: state._goToGuestStep),
          const SizedBox(height: 10),
          _confirmReservationButton(
            accent: accent,
            onPressed: state._onSave,
          ),
          const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Est. cost for the stay, worked out from the room type's `NetRate` in the
  /// hotel catalog: rate x nights x rooms. Only the total is shown — the
  /// rate breakdown behind it stays out of the UI. Display only: nothing
  /// about it is saved with the reservation, it is there so the user sees
  /// what the rooms come to while they pick.
  Widget _estimatedCost(Color accent) {
    final rateValue = state._selectedRoomType?['NetRate'];
    final rate = rateValue is num ? rateValue.toDouble() : null;
    final arrival = state._h_arrivalDate;
    final departure = state._h_departureDate;
    if (rate == null || arrival == null || departure == null) {
      return const SizedBox.shrink();
    }
    final nights = departure.difference(arrival).inDays;
    if (nights <= 0) return const SizedBox.shrink();

    // The room count lives in a controller, so the total has to follow it as
    // the user steps it up and down.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: state._h_noOfRooms,
      builder: (context, value, _) {
        final rooms = int.tryParse(value.text.trim()) ?? 1;
        if (rooms <= 0) return const SizedBox.shrink();
        final money = NumberFormat('#,##0.00');
        final total = rate * nights * rooms;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _LabeledCard(
            label: 'Estimated Cost',
            accent: accent,
            child: Text(
              money.format(total),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Reminds the user which guest the rooms below are being booked for, since
  /// their name is a step behind. Tapping it goes back to change them.
  Widget _bookingGuestBanner(Color accent) => _stepGuestBanner(
        accent: accent,
        memberId: state._sharedMemberId.text,
        guestName: state._sharedGuestName.text,
        extraGuests: state._h_extraMembers.length,
        onTap: state._goToGuestStep,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// AIR TICKET FORM
// ─────────────────────────────────────────────────────────────────────────────
class _AirForm extends StatelessWidget {
  final _QuickReservationBallysScreenState state;
  const _AirForm({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const accent = _QuickReservationBallysScreenState._airColor;
    return Column(
      children: [
        _stepIndicator(
          accent: accent,
          step: state._airStep,
          bookingLabel: 'Air Ticket',
          bookingIcon: Icons.flight_rounded,
          onGuestTap: state._goToGuestStep,
        ),
        Expanded(
          // Both steps stay in the tree so their fields keep their state — and
          // stay validatable — while only the current one is on screen.
          child: IndexedStack(
            index: state._airStep,
            sizing: StackFit.expand,
            children: [
              _guestStep(context, accent),
              _bookingStep(context, accent),
            ],
          ),
        ),
      ],
    );
  }

  /// Step ① — who the ticket is for.
  Widget _guestStep(BuildContext context, Color accent) {
    return Form(
      key: state._airGuestFormKey,
      // A lazy ListView only builds the rows near the viewport, and
      // Form.validate() skips fields that are not mounted, so saving from the
      // top of the form silently bypassed every validator further down. A
      // Column keeps all fields alive at all times.
      child: SingleChildScrollView(
        controller: state._airGuestScrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _guestIdentityRow(
            context: context,
            memberIdCtrl: state._sharedMemberId,
            memberIdNumberCtrl: state._sharedMidNumber,
            memberNameCtrl: state._sharedGuestName,
            accent: accent,
            midLabel: 'Membership No *',
            nameLabel: 'Guest Name',
            onSearchById: () => state._openGuestSearch(
              iid: 8002,
              onCardVisible: () =>
                  state.setState(() => state._sharedGuestCardVisible = true),
            ),
            onSearchByName: () => state._openGuestSearch(
              iid: 8003,
              onCardVisible: () =>
                  state.setState(() => state._sharedGuestCardVisible = true),
            ),
            onProfileTap: () => state._navigateToProfile(
              state._sharedMemberId.text,
              state._sharedGuestName.text,
            ),
            profileEnabled: state._sharedGuestCardVisible,
            isNumericOnly: state._isNumericOnlyLocation,
            prefixes: state._prefixes,
            selectedPrefix: state._selectedPrefix,
            onPrefixChanged: (v) {
              state._quickNotifier.selectPrefix(v);
              state.setState(() {
                state._sharedMemberId.text =
                    '$v${state._sharedMidNumber.text}';
              });
            },
          ),
          const SizedBox(height: 12),
          if (state._sharedGuestCardVisible &&
              state._sharedMemberId.text.isNotEmpty &&
              state._sharedGuestName.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GuestDisplayCardSpecialGiftview(
                memberIdText: state._sharedMemberId.text,
                memberNameText: state._sharedGuestName.text,
                showCard: true,
                showLastVisitDate: true,
              ),
            ),
          PackageAmountFieldBallys(
            controller: state._sharedPackageAmount,
            noPackage: state._sharedPackageShared,
            // Shared only records that the package is shared — an amount can
            // still be picked alongside it.
            allowAmountWhenShared: true,
            onNoPackageChanged: (v) =>
                state.setState(() => state._sharedPackageShared = v),
            textStyle: kInputTextStyle,
            accent: accent,
            decoration: _fieldDeco(
              'Package Amount',
              icon: Icons.currency_rupee,
              accent: accent,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Package Amount is required';
              }
              return null;
            },
          ),
          // const SizedBox(height: 12),
          // TextFormField(
          //   controller: state._sharedReservationNo,
          //   style: kInputTextStyle,
          //   decoration: _fieldDeco(
          //     'Manual Reservation No',
          //     icon: Icons.confirmation_number_outlined,
          //     accent: accent,
          //   ),
          // ),
          const SizedBox(height: 12),

          // ── Family members of THIS guest ────────────────────────────────────
          _familyMembersTick(
            accent: accent,
            checked: state._sharedHasFamilyMembers,
            onChanged: (v) =>
                state.setState(() => state._sharedHasFamilyMembers = v),
          ),
          const SizedBox(height: 12),

          // ── Extra guests on the SAME package ────────────────────────────────
          ...List.generate(
            state._a_extraMembers.length,
            (i) => _extraMemberCard(
              state,
              state._a_extraMembers,
              i,
              accent,
              subtitle: 'Same Package',
              showFamilyMembers: true,
            ),
          ),
          _addMoreGuestButton(
            accent: accent,
            onPressed: () => state._addExtraMember(state._a_extraMembers),
          ),
          const SizedBox(height: 24),
          _stepNextButton(
            accent: accent,
            label: 'Next: Air Ticket Details',
            onPressed: state._goToAirBookingStep,
          ),
          const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Step ② — the ticket being booked for the guest picked in step ①.
  Widget _bookingStep(BuildContext context, Color accent) {
    return Form(
      key: state._airFormKey,
      // A lazy ListView only builds the rows near the viewport, and
      // Form.validate() skips fields that are not mounted, so saving from the
      // top of the form silently bypassed every validator further down. A
      // Column keeps all fields alive at all times.
      child: SingleChildScrollView(
        controller: state._airScrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _stepGuestBanner(
            accent: accent,
            memberId: state._sharedMemberId.text,
            guestName: state._sharedGuestName.text,
            extraGuests: state._a_extraMembers.length,
            onTap: state._goToGuestStep,
          ),
          const SizedBox(height: 14),

          // ── Who this ticket is booked for ───────────────────────────────────
          _guestAssignmentCard(
            accent: accent,
            title: 'Assign this ticket to',
            emptyMessage: 'Every guest already has a ticket',
            errorMessage: 'Select at least one guest for this ticket',
            guests: state._airAssignableGuests,
            selectedKeys: state._a_assignedGuestKeys,
            lockedKeys: state._guestsOnPendingAirTickets(),
            keyOf: state._guestKey,
            onToggle: state._toggleAirGuest,
            onSelectAll: state._setAllAirGuests,
            showError: state._a_guestAssignError,
            lockedLabel: 'Already has a ticket',
          ),
          const SizedBox(height: 14),

          // ── Tickets already added for this guest ────────────────────────────
          if (state._pendingAirTickets.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.flight_rounded, color: accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Air Tickets Added for This Guest '
                    '(${state._pendingAirTickets.length})',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ...state._pendingAirTickets.asMap().entries.map((e) {
              final idx = e.key;
              final t = e.value;
              // The route carries any transit stops; the endpoints are the
              // fallback for a ticket with none.
              final route = t['departureRoute'] as String? ?? '';
              final sector = route.isNotEmpty
                  ? route
                  : [
                      if ((t['fromAirport'] as String? ?? '').isNotEmpty)
                        t['fromAirport'],
                      if ((t['toAirport'] as String? ?? '').isNotEmpty)
                        t['toAirport'],
                    ].join(' → ');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: accent.withOpacity(0.35), width: 1.2),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: accent.withOpacity(0.15),
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sector.isNotEmpty ? sector : '—',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${t['arrDate']} → ${t['depDate']}  |  '
                            '${t['class']}  |  ${t['noOfSeats']} seat(s)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => state.setState(
                          () => state._pendingAirTickets.removeAt(idx)),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
          _dateField(
            context,
            'Arrival Date',
            state._a_arrCtrl,
            accent,
            () async {
              final d = await state._pickDate(
                context,
                label: 'Select Arrival Date',
                initial: state._a_arrDate,
                minDate: state._today,
              );
              if (d != null) {
                state._a_arrDate = d;
                state._a_arrCtrl.text = state._fmt(d);
                if (state._a_depDate != null &&
                    !state._a_depDate!.isAfter(d)) {
                  state._a_depDate = null;
                  state._a_depCtrl.clear();
                }
                // ignore: invalid_use_of_protected_member
                (context as Element).markNeedsBuild();
              }
            },
            // Clearing the arrival also drops the departure — it is only ever
            // constrained relative to an arrival date.
            onClear: () => state.setState(() {
              state._a_arrDate = null;
              state._a_arrCtrl.clear();
              state._a_depDate = null;
              state._a_depCtrl.clear();
            }),
          ),
          const SizedBox(height: 12),
          _dateField(
            context,
            'Departure Date',
            state._a_depCtrl,
            accent,
            () async {
              final d = await state._pickDate(
                context,
                label: 'Select Departure Date',
                initial: state._a_depDate,
                minDate: state._minDeparture(state._a_arrDate),
              );
              if (d != null) {
                state._a_depDate = d;
                state._a_depCtrl.text = state._fmt(d);
                // ignore: invalid_use_of_protected_member
                (context as Element).markNeedsBuild();
              }
            },
            onClear: () => state.setState(() {
              state._a_depDate = null;
              state._a_depCtrl.clear();
            }),
          ),
          const SizedBox(height: 12),
          _LabeledCard(
            label: 'Departure Flight',
            accent: accent,
            child: Column(
              children: [
                _AirportDropdown(
                  key: state._a_fromAirportKey,
                  label: 'From (Departure Airport)',
                  accent: accent,
                  selectedAirport: state._a_fromAirport,
                  onChanged: (a) {
                    state.setState(() {
                      state._a_fromAirport = a;
                      if (state._a_isRoundTrip) {
                        state._a_returnToAirport = a;
                        state._a_returnToAirportKey = UniqueKey();
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                _AirportDropdown(
                  key: state._a_toAirportKey,
                  label: 'To (Arrival Airport)',
                  accent: accent,
                  selectedAirport: state._a_toAirport,
                  onChanged: (a) {
                    state.setState(() {
                      state._a_toAirport = a;
                      if (state._a_isRoundTrip) {
                        state._a_returnFromAirport = a;
                        state._a_returnFromAirportKey = UniqueKey();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Asked before Round Trip: guests with no direct flight route through
          // transit airports, and that changes what each leg below looks like.
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.connecting_airports_rounded,
                    color: accent, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Multi Sector (No Direct Flight)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                      color: Colors.black,
                    ),
                  ),
                ),
                Switch(
                  value: state._a_isMultiSector,
                  activeColor: accent,
                  onChanged: (v) {
                    state.setState(() {
                      state._a_isMultiSector = v;
                      if (v) {
                        // Start each leg off with one empty stop, so there is
                        // something to fill in straight away.
                        if (state._a_departureSectors.isEmpty) {
                          state._a_departureSectors.add(FlightSectorEntry());
                        }
                        if (state._a_isRoundTrip &&
                            state._a_returnSectors.isEmpty) {
                          state._a_returnSectors.add(FlightSectorEntry());
                        }
                      } else {
                        state._a_departureSectors.clear();
                        state._a_returnSectors.clear();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          if (state._a_isMultiSector) ...[
            const SizedBox(height: 12),
            _SectorEditor(
              state: state,
              label: 'Departure Stops',
              accent: accent,
              sectors: state._a_departureSectors,
              from: state._a_fromAirport,
              to: state._a_toAirport,
            ),
          ],
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.compare_arrows_rounded, color: accent, size: 20),
                const SizedBox(width: 10),
                const Text(
                  'Round Trip',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15.5,
                    color: Colors.black,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: state._a_isRoundTrip,
                  activeColor: accent,
                  onChanged: (v) {
                    state.setState(() {
                      state._a_isRoundTrip = v;
                      if (v) {
                        state._a_returnFromAirport = state._a_toAirport;
                        state._a_returnToAirport = state._a_fromAirport;
                        state._a_returnFromAirportKey = UniqueKey();
                        state._a_returnToAirportKey = UniqueKey();
                        if (state._a_isMultiSector &&
                            state._a_returnSectors.isEmpty) {
                          state._a_returnSectors.add(FlightSectorEntry());
                        }
                      } else {
                        state._a_returnFromAirport = null;
                        state._a_returnToAirport = null;
                        state._a_returnSectors.clear();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          if (state._a_isRoundTrip) ...[
            const SizedBox(height: 12),
            _LabeledCard(
              label: 'Return Flight',
              accent: accent,
              child: Column(
                children: [
                  _AirportDropdown(
                    key: state._a_returnFromAirportKey,
                    label: 'Return From',
                    accent: accent,
                    selectedAirport: state._a_returnFromAirport,
                    onChanged: (a) =>
                        state.setState(() => state._a_returnFromAirport = a),
                  ),
                  const SizedBox(height: 10),
                  _AirportDropdown(
                    key: state._a_returnToAirportKey,
                    label: 'Return To',
                    accent: accent,
                    selectedAirport: state._a_returnToAirport,
                    onChanged: (a) =>
                        state.setState(() => state._a_returnToAirport = a),
                  ),
                  if (state._a_isMultiSector) ...[
                    const SizedBox(height: 10),
                    _SectorEditor(
                      state: state,
                      label: 'Return Stops',
                      accent: accent,
                      sectors: state._a_returnSectors,
                      from: state._a_returnFromAirport,
                      to: state._a_returnToAirport,
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Once the ticket is assigned to guests who bring no family there is
          // nobody on it but the guests themselves — one seat each, no children,
          // no infants — so the counters follow the ticks. A guest who brings
          // family hands them back, since the family flies on this ticket too.
          _StepperField(
            controller: state._a_noOfSeats,
            label: 'No of Adults',
            icon: Icons.event_seat_outlined,
            accent: accent,
            locked: state._seatCountLocked,
            lockedHint: 'One seat per assigned guest',
          ),
          const SizedBox(height: 12),
          _rowPair(
            _StepperField(
              controller: state._a_noOfChildren,
              label: 'Children',
              icon: Icons.child_care_outlined,
              accent: accent,
              min: 0,
              locked: state._seatCountLocked,
              lockedHint: 'Tick a guest with family to add',
            ),
            _StepperField(
              controller: state._a_noOfInfants,
              label: 'Infants',
              icon: Icons.child_friendly_outlined,
              accent: accent,
              min: 0,
              locked: state._seatCountLocked,
              lockedHint: 'Tick a guest with family to add',
            ),
          ),
          const SizedBox(height: 12),
          // A ticket can mix cabin classes — Economy x2 plus Business x1 is one
          // ticket, not two — so each class is ticked with its own seat count.
          // The ceiling is one seat per assigned guest, dropped when a ticked
          // guest brings family since their headcount isn't known here.
          AirTicketClassCountSelector(
            key: state._a_classKey,
            selectedClasses: state._a_ticketClasses,
            maxSeats: state._maxTicketSeats,
            hasError: state._a_classError,
            onChanged: (classes) => state.setState(() {
              state._a_ticketClasses = classes;
              if (classes.isNotEmpty) state._a_classError = false;
            }),
          ),
          const SizedBox(height: 12),

          // ── Airline dropdown (from API 90156) ────────────────────────────────
          _AirlineDropdown(
            dropdownKey: state._a_airlineKey,
            items: state._a_airlines,
            selectedItem: state._a_selectedAirline,
            isLoading: state._a_airlinesLoading,
            accent: accent,
            onChanged: (val) =>
                state.setState(() => state._a_selectedAirline = val),
          ),

          const SizedBox(height: 12),

          // ── Additional facilities (NEW) ──────────────────────────────────────
          _sectionHeader(
            'Amentities',
            accent,
            Icons.checklist_rtl_rounded,
          ),
          _YesNoRadioRow(
            label: 'Slik Route Facility',
            icon: Icons.alt_route_rounded,
            value: state._a_skipRouteFacility,
            accent: accent,
            // Silk and Gold Route are mutually exclusive — saying Yes to one
            // clears the other.
            onChanged: (v) => state.setState(() {
              state._a_skipRouteFacility = v;
              if (v == 'Yes') state._a_goldRoute = 'No';
            }),
          ),
            const SizedBox(height: 10),
            _YesNoRadioRow(
              label: 'Gold Route',
              icon: Icons.route_rounded,
              value: state._a_goldRoute,
              accent: accent,
              onChanged: (v) => state.setState(() {
                state._a_goldRoute = v;
                if (v == 'Yes') state._a_skipRouteFacility = 'No';
              }),
            ),
          const SizedBox(height: 10),
          _YesNoRadioRow(
            label: 'Airport Transport',
            icon: Icons.local_taxi_rounded,
            value: state._a_airportTransport,
            accent: accent,
            onChanged: (v) =>
                state.setState(() => state._a_airportTransport = v),
          ),
          const SizedBox(height: 10),
          _YesNoRadioRow(
            label: 'Visa',
            icon: Icons.badge_outlined,
            value: state._a_visa,
            accent: accent,
            onChanged: (v) => state.setState(() => state._a_visa = v),
          ),
          // Ballys-only options (hidden for Bellagio)
          if (!state._isBellagio) ...[
            const SizedBox(height: 10),
            _YesNoRadioRow(
              label: 'Meal',
              icon: Icons.restaurant_rounded,
              value: state._a_meal,
              accent: accent,
              onChanged: (v) => state.setState(() => state._a_meal = v),
            ),
            const SizedBox(height: 10),
            _YesNoRadioRow(
              label: 'Extra Legroom Seat',
              icon: Icons.airline_seat_legroom_extra_rounded,
              value: state._a_extraLegroomSeat,
              accent: accent,
              onChanged: (v) =>
                  state.setState(() => state._a_extraLegroomSeat = v),
            ),
          
          ],

          // ── Follow-ups for the Yes answers above ────────────────────────────
          // Full width, one per row: the leg pickers and the meal note need
          // more space than the half-width option rows.
          if (state._a_skipRouteFacility == 'Yes') ...[
            const SizedBox(height: 12),
            _LegSelector(
              label: 'Slik Route Facility For',
              value: state._a_silkRouteType,
              accent: accent,
              onChanged: (leg) =>
                  state.setState(() => state._a_silkRouteType = leg),
            ),
          ],
          if (!state._isBellagio && state._a_goldRoute == 'Yes') ...[
            const SizedBox(height: 12),
            _LegSelector(
              label: 'Gold Route For',
              value: state._a_goldRouteType,
              accent: accent,
              onChanged: (leg) =>
                  state.setState(() => state._a_goldRouteType = leg),
            ),
          ],
          if (!state._isBellagio && state._a_meal == 'Yes') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: state._a_mealRemarkCtrl,
              style: kInputTextStyle,
              decoration: _fieldDeco(
                'Meal Details',
                icon: Icons.restaurant_menu,
                accent: accent,
              ).copyWith(hintText: 'e.g. vegetarian, no nuts'),
            ),
          ],
          const SizedBox(height: 12),

          // ── Hamoue contact person (NEW, hardcoded test values) ──────────────
          if (!state._isBellagio) ...[
            DropdownButtonFormField<String>(
              value: state._a_hamoueContactPerson,
              style: kInputTextStyle,
              decoration: _fieldDeco(
                'Hamoos Contact Person',
                icon: Icons.support_agent_rounded,
                accent: accent,
              ),
              items: state._hamoueContactPersons
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) =>
                  state.setState(() => state._a_hamoueContactPerson = v),
            ),
            const SizedBox(height: 16),
          ],

          // ── Payment By ───────────────────────────────────────────────────────
          _LabeledCard(
            label: 'Payment By *',
            accent: accent,
            errorText: state._a_paymentByError
                ? 'Please select Payment By'
                : null,
            child: _ChipSelector(
              key: ValueKey('air_payment_by_${state._isBellagio}'),
              options: state._isBellagio
                  ? const [
                      'By Guest',
                      'By Beyond Borders',
                      'By Guest & Beyond Borders',
                    ]
                  : const [
                      'By Guest',
                      'By Hamoos',
                      'By Guest & Hamoos',
                      'Recovery from Cashier',
                    ],
              selected: state._a_paymentBy,
              accent: accent,
              onChanged: (v) => state.setState(() {
                state._a_paymentBy = v;
                state._a_paymentByError = false;
              }),
            ),
          ),
          const SizedBox(height: 16),

          // ── Passport bio data page upload ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _passportSection(accent),
          ),
          const SizedBox(height: 16),

          // ── Add Another Air Ticket button ────────────────────────────────────
          _addAnotherButton(
            accent: accent,
            icon: Icons.flight_takeoff_rounded,
            label: 'Add Another Air Ticket for This Guest',
            onPressed: state._addAnotherAirTicket,
          ),
          const SizedBox(height: 12),

          // ── Request Approval From ────────────────────────────────────────────
          _approverDropdown(
            value: state._a_approver,
            levels: state._quick.authorizationLevels,
            loading: state._quick.authorizationLevelsLoading,
            accent: accent,
            onChanged: (v) => state.setState(() => state._a_approver = v),
          ),
          const SizedBox(height: 12),

          // ── Remarks (Air Tab) ─────────────────────────────────────────────────
          TextFormField(
            controller: state._a_remarksCtrl,
            style: kInputTextStyle,
            decoration: _fieldDeco(
              'Remarks',
              icon: Icons.notes_rounded,
              accent: accent,
            ),
            maxLines: 3,
            keyboardType: TextInputType.multiline,
          ),

          const SizedBox(height: 20),
          _addedMembersSection(
            members: state._airMembers,
            accent: accent,
            textBuilder: state._singleAirText,
            onRemove: (i) =>
                () => state.setState(() => state._airMembers.removeAt(i)),
          ),
          _stepBackButton(accent: accent, onPressed: state._goToGuestStep),
          const SizedBox(height: 10),
          _confirmReservationButton(
            accent: accent,
            onPressed: state._onSave,
          ),
          const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// The bio pages for this ticket's guests: one uploader per ticked guest, so a
  /// passport is filed against the member it belongs to instead of landing on
  /// the guest that owns the form. Banking the ticket clears the ticks, which
  /// clears the uploaders — re-ticking a guest brings their pages back.
  Widget _passportSection(Color accent) {
    final guests = state._airAssignableGuests;

    // Nobody to name yet, so the page goes to whoever ends up owning the
    // ticket.
    if (guests.isEmpty) {
      return PassportUploadWidgetBallys(
        key: state._a_passportUploadKey,
        initialFiles: state._a_passportFiles,
        onFilesChanged: (files) =>
            state.setState(() => state._a_passportFiles = List.from(files)),
      );
    }

    final selected = guests
        .where((g) => state._a_assignedGuestKeys.contains(state._guestKey(g)))
        .toList();

    if (selected.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: accent),
              const SizedBox(width: 6),
              const Text(
                'Passport Bio Data Page',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select a guest above to upload their passport bio page.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < selected.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _guestPassportUploader(selected[i]),
        ],
      ],
    );
  }

  /// One guest's uploader, headed with their name so it is plain whose bio page
  /// is being picked. Every file it produces is stamped with that guest's BM
  /// number, which is what goes out as `GuestBMNumber`.
  Widget _guestPassportUploader(AccompanyingMember guest) {
    final key = state._guestKey(guest);
    final label = [
      if (guest.guestName.trim().isNotEmpty) guest.guestName.trim(),
      if (guest.mid.trim().isNotEmpty) guest.mid.trim(),
    ].join(' — ');

    return PassportUploadWidgetBallys(
      // Keyed by guest so switching who the ticket is for rebuilds the uploader
      // with that guest's own files rather than keeping the last guest's on
      // screen.
      key: ValueKey('passport-$key'),
      title: label.isNotEmpty
          ? 'Passport Bio Data Page — $label'
          : 'Passport Bio Data Page',
      guestBmNumber: guest.mid.trim(),
      guestName: guest.guestName.trim(),
      initialFiles: state._a_passportsByGuest[key] ?? const [],
      onFilesChanged: (files) => state.setState(
        () => state._a_passportsByGuest[key] = List.from(files),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSPORT FORM
// ─────────────────────────────────────────────────────────────────────────────
class _TransportForm extends StatelessWidget {
  final _QuickReservationBallysScreenState state;
  const _TransportForm({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const accent = _QuickReservationBallysScreenState._transportColor;
    return Form(
      key: state._transportFormKey,
      // A lazy ListView only builds the rows near the viewport, and
      // Form.validate() skips fields that are not mounted — so saving from the
      // top of the tab silently bypassed every validator further down. A Column
      // keeps all fields alive at all times.
      child: SingleChildScrollView(
        controller: state._transportScrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // _sectionHeader(
          //   'Transport Request',
          //   accent,
          //   Icons.directions_car_rounded,
          // ),
          _guestIdentityRow(
            context: context,
            memberIdCtrl: state._sharedMemberId,
            memberIdNumberCtrl: state._sharedMidNumber,
            memberNameCtrl: state._sharedGuestName,
            accent: accent,
            midLabel: 'Membership No *',
            nameLabel: 'Guest Name',
            onSearchById: () => state._openGuestSearch(
              iid: 8002,
              onCardVisible: () =>
                  state.setState(() => state._sharedGuestCardVisible = true),
            ),
            onSearchByName: () => state._openGuestSearch(
              iid: 8003,
              onCardVisible: () =>
                  state.setState(() => state._sharedGuestCardVisible = true),
            ),
            onProfileTap: () => state._navigateToProfile(
              state._sharedMemberId.text,
              state._sharedGuestName.text,
            ),
            profileEnabled: state._sharedGuestCardVisible,
            isNumericOnly: state._isNumericOnlyLocation,
            prefixes: state._prefixes,
            selectedPrefix: state._selectedPrefix,
            onPrefixChanged: (v) {
              state._quickNotifier.selectPrefix(v);
              state.setState(() {
                state._sharedMemberId.text =
                    '$v${state._sharedMidNumber.text}';
              });
            },
            memberIdValidator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Membership No is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          if (state._sharedGuestCardVisible &&
              state._sharedMemberId.text.isNotEmpty &&
              state._sharedGuestName.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GuestDisplayCardSpecialGiftview(
                memberIdText: state._sharedMemberId.text,
                memberNameText: state._sharedGuestName.text,
                showCard: true,
                showLastVisitDate: true,
              ),
            ),
          // ── Extra guests on the SAME transport request ─────────────────────
          ...List.generate(
            state._t_extraMembers.length,
            (i) => _extraMemberCard(
              state,
              state._t_extraMembers,
              i,
              accent,
              showPackageAmount: false,
            ),
          ),
          _addMoreGuestButton(
            accent: accent,
            onPressed: () => state._addExtraMember(state._t_extraMembers),
          ),
          const SizedBox(height: 16),
          // ── Pickup date & time ───────────────────────────────────────────────
          _dateField(
            context,
            'Pickup/ Drop Date *',
            state._t_pickupDateCtrl,
            accent,
            () async {
              final now = DateTime.now();
              final d = await state._pickDate(
                context,
                label: 'Select Pickup/ Drop Date',
                initial: state._t_pickupDate,
                minDate: DateTime(now.year, now.month, now.day),
              );
              if (d != null) {
                state.setState(() {
                  state._t_pickupDate = d;
                  state._t_pickupDateCtrl.text = state._fmt(d);
                });
              }
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Pickup/ Drop Date is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: state._t_pickupTimeCtrl,
            readOnly: true,
            style: kInputTextStyle,
            decoration: _fieldDeco(
              'Pickup/ Drop Time *',
              icon: Icons.access_time_rounded,
              accent: accent,
            ).copyWith(
              suffixIcon: Icon(Icons.arrow_drop_down, color: accent),
            ),
            onTap: () async {
              // Only restrict past times when pickup is for today; future
              // dates allow any time of day.
              final now = DateTime.now();
              final pickupDate = state._t_pickupDate;
              final isToday = pickupDate == null ||
                  (pickupDate.year == now.year &&
                      pickupDate.month == now.month &&
                      pickupDate.day == now.day);
              final t = await state._pickTime(
                context,
                label: 'Select Pickup/ Drop Time',
                initial: state._t_pickupTime,
                minTime: isToday
                    ? TimeOfDay(hour: now.hour, minute: now.minute)
                    : null,
              );
              if (t != null) {
                state.setState(() {
                  state._t_pickupTime = t;
                  state._t_pickupTimeCtrl.text = state._fmtTime(t);
                });
              }
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Pickup/ Drop Time is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // ── No of vehicles ───────────────────────────────────────────────────
          // Vehicle count is chosen before Car Type on purpose: bumping it
          // grows the Car Type + Passengers pairs below to one per vehicle.
          _StepperField(
            controller: state._t_noOfVehicles,
            label: 'No of Vehicles',
            icon: Icons.local_taxi_outlined,
            accent: accent,
            onChanged: state._syncVehicleDetailsWithCount,
          ),
          const SizedBox(height: 12),
          _YesNoRadioRow(
            label: 'Airport Pickup/ Drop',
            icon: Icons.flight_land_rounded,
            value: state._t_airportPickup,
            accent: accent,
            onChanged: (v) => state.setState(() => state._t_airportPickup = v),
          ),
          const SizedBox(height: 12),

          // ── Car type + passengers, one row per vehicle ────────────────────────
          for (int i = 0; i < state._t_carTypes.length; i++) ...[
            if (state._t_carTypes.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Vehicle ${i + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
            _rowPair(
              DropdownButtonFormField<String>(
                value: state._t_carTypes[i],
                style: kInputTextStyle,
                isExpanded: true,
                decoration: _fieldDeco(
                  'Car Type *',
                 // icon: Icons.directions_car_filled_outlined,
                  accent: accent,
                ),
                items: kCarTypes
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) =>
                    state.setState(() => state._t_carTypes[i] = v),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Car Type is required';
                  }
                  return null;
                },
              ),
              _StepperField(
                controller: state._t_passengerCtrls[i],
                label: 'Passengers',
                icon: Icons.group_outlined,
                accent: accent,
              ),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            value: state._t_hireType,
            style: kInputTextStyle,
            isExpanded: true,
            decoration: _fieldDeco(
              'Hire Type *',
              icon: Icons.assignment_outlined,
              accent: accent,
            ),
            items: kHireTypes
                .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                .toList(),
            onChanged: (v) => state.setState(() => state._t_hireType = v),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Hire Type is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // ── Pickup / drop locations (Google Places) ──────────────────────────
          _LabeledCard(
            label: 'Locations',
            accent: accent,
            child: Column(
              children: [
                LocationSearchField(
                  controller: state._t_pickupLocationCtrl,
                  textStyle: kInputTextStyle,
                  accent: accent,
                  sheetTitle: 'Search Pickup Location',
                  decoration: _fieldDeco(
                    'Pickup Location *',
                    icon: Icons.my_location_rounded,
                    accent: accent,
                  ),
                  onSelected: (description, placeId) => state.setState(() {
                    state._t_pickupLocationCtrl.text = description;
                    state._t_pickupPlaceId = placeId;
                  }),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Pickup Location is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                LocationSearchField(
                  controller: state._t_dropLocationCtrl,
                  textStyle: kInputTextStyle,
                  accent: accent,
                  sheetTitle: 'Search Drop Location',
                  decoration: _fieldDeco(
                    'Drop Location *',
                    icon: Icons.place_rounded,
                    accent: accent,
                  ),
                  onSelected: (description, placeId) => state.setState(() {
                    state._t_dropLocationCtrl.text = description;
                    state._t_dropPlaceId = placeId;
                  }),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Drop Location is required';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Contact number ───────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: state._showTransportCountryPicker,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state._t_country.flagEmoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+${state._t_country.phoneCode}',
                        style: kInputTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: accent, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: state._t_contactNumber,
                  style: kInputTextStyle,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(kMaxContactDigits),
                  ],
                  decoration: _fieldDeco(
                    'Contact Number *',
                    icon: Icons.phone_rounded,
                    accent: accent,
                  ),
                  validator: (value) {
                    final digits = (value ?? '').trim();
                    if (digits.isEmpty) {
                      return 'Contact Number is required';
                    }
                    if (digits.length < kMinContactDigits) {
                      return 'Enter at least $kMinContactDigits digits';
                    }
                    if (digits.length > kMaxContactDigits) {
                      return 'Enter no more than $kMaxContactDigits digits';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state._onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.save_alt),
              label: const Text(
                'Confirm Reservation',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// An extra guest sharing the transport request currently in the form
// ─────────────────────────────────────────────────────────────────────────────
/// One extra guest travelling on the same request as the guest in the form:
/// they share its hotels / flights / vehicles and dates, so they only carry who
/// they are and their own package amount. Used by all three tabs.
class _ExtraMember {
  final TextEditingController midNumberController;
  final TextEditingController nameController;

  /// This member's own package amount — they share the primary guest's booking
  /// and dates but are billed their own package.
  final TextEditingController packageAmountController;
  String prefix;

  /// Ticked when this member rides on someone else's package, which makes an
  /// empty [packageAmountController] a valid state rather than a missing field.
  bool sharedPackage;

  /// Whether family members travel with THIS guest. Only shown on the hotel and
  /// air ticket tabs, matching the new reservation screen's member card.
  bool hasFamilyMembers;

  _ExtraMember({
    this.prefix = 'BM',
    String midNumber = '',
    String name = '',
    String packageAmount = '',
    this.sharedPackage = false,
    this.hasFamilyMembers = false,
  })  : midNumberController = TextEditingController(text: midNumber),
        nameController = TextEditingController(text: name),
        packageAmountController = TextEditingController(text: packageAmount);

  /// The member ID as the API expects it: prefixed everywhere except the
  /// numeric-only locations, which have no prefix dropdown at all.
  String fullMid({required bool numericOnly}) {
    final number = midNumberController.text.trim();
    if (number.isEmpty) return '';
    return numericOnly ? number : '$prefix$number';
  }

  void dispose() {
    midNumberController.dispose();
    nameController.dispose();
    packageAmountController.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yes / No radio row — used for Skip Route Facility, Airport Transport, Visa
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Arrival / Departure picker — which leg a Silk or Gold Route facility is for.
// Only shown once its option is answered Yes.
// ─────────────────────────────────────────────────────────────────────────────
class _LegSelector extends StatelessWidget {
  final String label;
  final String value; // 'Arrival' or 'Departure'
  final Color accent;
  final ValueChanged<String> onChanged;

  const _LegSelector({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  Widget _leg(String leg, IconData icon) {
    final selected = value == leg;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(leg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: selected ? accent : Colors.grey.shade600),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  leg,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? accent : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flight_takeoff_rounded, size: 18, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _leg('Arrival', Icons.flight_land_rounded),
              const SizedBox(width: 10),
              _leg('Departure', Icons.flight_takeoff_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _YesNoRadioRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value; // 'Yes' or 'No'
  final Color accent;
  final ValueChanged<String> onChanged;

  /// Label on top, Yes/No underneath — matches [_StepperField]'s two-line card
  /// so the two sit level when paired half-width in a [_rowPair].
  final bool stacked;

  const _YesNoRadioRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.stacked = false,
  });

  Widget _option(String text) {
    final selected = value == text;
    return InkWell(
      onTap: () => onChanged(text),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<String>(
            value: text,
            groupValue: value,
            activeColor: accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => onChanged(v!),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? accent : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: stacked
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _option('Yes'),
                      _option('No'),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                _option('Yes'),
                _option('No'),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip selector
// ─────────────────────────────────────────────────────────────────────────────
class _ChipSelector extends StatefulWidget {
  final List<String> options;
  final String selected;
  final Color accent;
  final ValueChanged<String> onChanged;
  const _ChipSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.accent,
    required this.onChanged,
  });
  @override
  State<_ChipSelector> createState() => _ChipSelectorState();
}

class _ChipSelectorState extends State<_ChipSelector> {
  late String _selected;
  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
  }

  @override
  void didUpdateWidget(covariant _ChipSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The value also moves from the outside — a form reset after a save — and
    // the chips have to follow it rather than keep showing the old answer.
    if (widget.selected != oldWidget.selected) _selected = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: widget.options.map((opt) {
        final active = _selected == opt;
        return ChoiceChip(
          label: Text(opt),
          selected: active,
          selectedColor: widget.accent,
          labelStyle: TextStyle(
            fontSize: 14.5,
            color: active ? Colors.white : Colors.black,
            fontWeight: active ? FontWeight.bold : FontWeight.w600,
          ),
          onSelected: (_) {
            setState(() => _selected = opt);
            widget.onChanged(opt);
          },
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stepper field
// ─────────────────────────────────────────────────────────────────────────────
class _StepperField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color accent;
  final int min;
  final int max;
  /// Called after the controller's value changes, in addition to this
  /// widget's own rebuild — lets a parent react (e.g. resize a list that
  /// should track the count).
  final VoidCallback? onChanged;

  /// The count is somebody else's business — it follows the guests ticked on the
  /// assignment card — so the buttons are dead and [lockedHint] says why.
  final bool locked;
  final String? lockedHint;

  const _StepperField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.accent,
    this.min = 1,
    this.max = 99,
    this.onChanged,
    this.locked = false,
    this.lockedHint,
  });

  int get _value => int.tryParse(controller.text) ?? min;
  void _change(int delta, VoidCallback rebuild) {
    final next = (_value + delta).clamp(min, max);
    controller.text = next.toString();
    rebuild();
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _StepButton(
                    icon: Icons.remove,
                    accent: accent,
                    enabled: !locked && _value > min,
                    onTap: () => _change(-1, () => setState(() {})),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        controller.text,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: locked ? Colors.grey.shade600 : accent,
                        ),
                      ),
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add,
                    accent: accent,
                    enabled: !locked && _value < max,
                    onTap: () => _change(1, () => setState(() {})),
                  ),
                ],
              ),
              if (locked && (lockedHint?.isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    lockedHint!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;
  const _StepButton({
    required this.icon,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? accent.withOpacity(0.1) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? accent : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Labeled card
// ─────────────────────────────────────────────────────────────────────────────
class _LabeledCard extends StatelessWidget {
  final String label;
  final Color accent;
  final Widget child;

  /// Complaint shown under the field, in the same place a form field would put
  /// it — set only while the card holds an unanswered mandatory value.
  final String? errorText;
  const _LabeledCard({
    required this.label,
    required this.accent,
    required this.child,
    this.errorText,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: errorText == null
              ? Colors.grey.shade300
              : Colors.red.shade400,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          child,
          if (errorText != null) ...[
            const SizedBox(height: 6),
            Text(
              errorText!,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview card
// ─────────────────────────────────────────────────────────────────────────────
class _PreviewCard extends StatelessWidget {
  final String text;
  final Color accent;
  const _PreviewCard({required this.text, required this.accent});

  List<TextSpan> _buildSpans(String fullText) {
    final lines = fullText.split('\n');
    final spans = <TextSpan>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final colonIdx = line.indexOf(':');
      final trimmed = line.trim();
      final isTitleLine = trimmed.startsWith('*') &&
          trimmed.endsWith('*') &&
          !trimmed.contains('Member');

      if (colonIdx != -1) {
        spans.add(
          TextSpan(
            text: line.substring(0, colonIdx + 1),
            style: const TextStyle(
              fontSize: 18,
              height: 1.6,
              fontFamily: 'monospace',
              color: Color.fromARGB(255, 0, 0, 0),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        spans.add(
          TextSpan(
            text: line.substring(colonIdx + 1),
            style: const TextStyle(
              fontSize: 18,
              height: 1.6,
              fontFamily: 'monospace',
              color: Color.fromARGB(255, 0, 0, 0),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: line.replaceAll('*', ''),
            style: TextStyle(
              fontSize: isTitleLine ? 19 : 18,
              height: 1.6,
              fontFamily: 'monospace',
              color: accent,
              fontWeight: FontWeight.bold,
              letterSpacing: isTitleLine ? 0.5 : 0,
            ),
          ),
        );
      }
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                'Message Preview',
                style: TextStyle(
                  fontSize: 13,
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RichText(text: TextSpan(children: _buildSpans(text))),
        ],
      ),
    );
  }
}