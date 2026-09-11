import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:country_picker/country_picker.dart';
import 'package:ballys_reservation_app/components/air_ticket_class_selector.dart';
import 'package:ballys_reservation_app/components/passport_upload_widget.dart';
import 'package:ballys_reservation_app/components/package_amount_field.dart';

import 'package:ballys_reservation_app/components/bottom_sheets/member_search-new_sheet.dart';
import 'package:ballys_reservation_app/components/guest_deatils_view_spGift.dart';
import 'package:ballys_reservation_app/components/location_search_field.dart';
import 'package:ballys_reservation_app/data/repositories/guest_repository.dart';
import 'package:ballys_reservation_app/data/repositories/hotel_repository.dart';
import 'package:ballys_reservation_app/data/repositories/airport_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/airport_search_response.dart';
import 'package:ballys_reservation_app/models/guest_modal.dart';
import 'package:ballys_reservation_app/models/guest_search_response.dart';
import 'package:ballys_reservation_app/models/reservation/airport_cost_response.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/providers/hotels_provider.dart';
import 'package:ballys_reservation_app/providers/airports_provider.dart';
import 'package:ballys_reservation_app/providers/new_reservation_provider.dart';
import 'package:ballys_reservation_app/providers/selected_guest_provider.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:ballys_reservation_app/data/repositories/contact_person_repository.dart';
import 'package:ballys_reservation_app/utils/device_id.dart';
import 'package:ballys_reservation_app/utils/amount_util.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';

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

// Placeholder saved as the transport drop location when the guest has not
// settled on one yet and will call it in later.
const String kGuestWillInform = 'Guest Will Inform';

// Digit count allowed in the contact number, excluding the country code.
const int kMinContactDigits = 9;
const int kMaxContactDigits = 10;

const TextStyle kInputTextStyle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w600,
  color: Colors.black,
);

// ─── Model: one hotel booking inside a guest member ──────────────────────────
class _HotelEntry {
  String hotel;
  double? hotelId;
  String arrival;
  String departure;
  DateTime? arrivalDate;
  DateTime? departureDate;
  String noOfRooms;
  String noOfPax;
  String roomType;
  int? roomTypeId;
  String roomCategory;
  int? roomCategoryId;
  String eciLco;
  String mealPlan;
  String paymentBy;
  String remarks;
  String marketingPerson;
  String approvedBy;

  _HotelEntry({
    this.hotel = '',
    this.hotelId,
    this.arrival = '',
    this.departure = '',
    this.arrivalDate,
    this.departureDate,
    this.noOfRooms = '1',
    this.noOfPax = '1',
    this.roomType = '',
    this.roomTypeId,
    this.roomCategory = '',
    this.roomCategoryId,
    this.eciLco = 'NA',
    this.mealPlan = '',
    this.paymentBy = 'NA',
    this.remarks = '',
    this.marketingPerson = '',
    this.approvedBy = '',
  });

  Map<String, dynamic> toMap() => {
        'hotel': hotel,
        'arrival': arrival,
        'departure': departure,
        'noOfRooms': noOfRooms,
        'noOfPax': noOfPax,
        'roomType': roomType,
        'roomCategory': roomCategory,
        'eciLco': eciLco,
        'mealPlan': mealPlan,
        'paymentBy': paymentBy,
        'remarks': remarks,
        'marketingPerson': marketingPerson,
        'approvedBy': approvedBy,
      };

  Map<String, dynamic> toApiJson() {
    final arrDt = arrivalDate;
    final depDt = departureDate;
    final nights =
        (arrDt != null && depDt != null) ? depDt.difference(arrDt).inDays : 0;
    return {
      'hotel': hotelId,
      'hotel_name': hotel,
      'room_category': roomCategoryId,
      'room_category_name': roomCategory,
      'room_type': roomTypeId,
      'room_type_name': roomType,
      'guest_count': int.tryParse(noOfPax) ?? 1,
      'children_count': 0,
      'room_count': int.tryParse(noOfRooms) ?? 1,
      'no_of_nights': nights,
      'arrival_date': arrDt?.toIso8601String(),
      'departure_date': depDt?.toIso8601String(),
      'selected_cost': 0.0,
      'cost_index': 0,
      'ec_lco_facility': eciLco,
      'payment_by': paymentBy,
    };
  }
}

class QuickReservationScreen extends ConsumerStatefulWidget {
  const QuickReservationScreen({super.key});
  @override
  ConsumerState<QuickReservationScreen> createState() =>
      _QuickReservationScreenState();
}

class _QuickReservationScreenState extends ConsumerState<QuickReservationScreen>
    with TickerProviderStateMixin, ConnectivityMixin {
  _Section _activeSection = _Section.airTicket;

  final _hotelFormKey = GlobalKey<FormState>();
  final _airFormKey = GlobalKey<FormState>();
  final _transportFormKey = GlobalKey<FormState>();

  bool _isLoading = false;

  bool _isNumericOnlyLocation = false;
  List<String> _prefixes = ["BM", "BL", "BN"];
  String _selectedPrefix = "BM";

  // Registered members are picked through the guest-search sheet, which fills
  // ID + name and unlocks the profile card. Non-registered ones already have a
  // DHL number issued outside the system: it can't be searched, so it is typed
  // by hand and saved into exactly the same membership-no field.
  bool _isRegisteredMember = true;

  /// Every non-registered number is issued under DHL, so the prefix is fixed
  /// instead of being picked from [_prefixes].
  static const String _nonRegisteredPrefix = "DBH";

  final _sharedMemberId = TextEditingController();
  final _sharedMidNumber = TextEditingController();
  final _sharedGuestName = TextEditingController();
  final _sharedPackageAmount = TextEditingController();
  // final _sharedReservationNo = TextEditingController();
  bool _sharedGuestCardVisible = false;

  // ── HOTEL members list ──────────────────────────────────────────────────────
  // Each member now has a 'hotels' list (List<_HotelEntry>) plus identity fields.
  List<Map<String, dynamic>> _hotelMembers = [];

  // Current hotel form fields (one hotel being edited at a time per guest)
  final _h_noOfRooms = TextEditingController(text: '1');
  final _h_noOfPax = TextEditingController(text: '1');
  final _h_mealPlan = TextEditingController();
  final _h_paymentBy = TextEditingController(text: 'NA');
  final _h_remarks = TextEditingController();
  final _h_marketingPerson = TextEditingController();
  final _h_approvedBy = TextEditingController();
  final _h_arrivalCtrl = TextEditingController();
  final _h_departureCtrl = TextEditingController();

  DateTime? _h_arrivalDate;
  DateTime? _h_departureDate;
  String _h_eciLco = 'NA';

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
  List<_HotelEntry> _pendingHotels = [];

  // ── AIR members list ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _airMembers = [];

  final _a_noOfSeats = TextEditingController(text: '1');
  Map<String, dynamic>? _a_selectedClass;
  Key _a_classKey = UniqueKey();

  // Airlines — now an AirportCostResponse selected from dropdown
  AirportCostResponse? _a_selectedAirline;
  List<AirportCostResponse> _a_airlineCosts = [];
  bool _a_airlinesLoading = false;
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

  // ── Air ticket — Hamoue contact person dropdown ───────────────────────────
  List<String> _hamoueContactPersons = [];
  String? _a_hamoueContactPerson;

  /// Bellagio (bty.world) hides the Hamoue contact person dropdown.
  bool _isBellagio = false;

  // ── Air ticket — passport bio data page uploads (NEW) ──────────────────────
  List<PassportFile> _a_passportFiles = [];
  Key _a_passportUploadKey = UniqueKey();

  // ── TRANSPORT members list (Bellagio only) ─────────────────────────────────
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
  // When set, no place is searched at all — the drop location is saved as
  // [kGuestWillInform] and the guest phones the real one in later.
  bool _t_guestWillInformDrop = false;
  String _t_silkRoute = 'No';
  String _t_airportPickup = 'No';

  // ── Transport — passport bio data page uploads ─────────────────────────────
  List<PassportFile> _t_passportFiles = [];
  Key _t_passportUploadKey = UniqueKey();

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

  final _hotelScrollCtrl = ScrollController();
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
    _loadHotels();
    _loadAirports();
    _loadLocationPrefix();
    _loadContactPersons();
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
      _h_mealPlan,
      _h_paymentBy,
      _h_remarks,
      _h_marketingPerson,
      _h_approvedBy,
      _h_arrivalCtrl,
      _h_departureCtrl,
      _a_noOfSeats,
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
    _hotelScrollCtrl.dispose();
    _airScrollCtrl.dispose();
    _transportScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocationPrefix() async {
    final location = await StorageUtil.getCurrentLocation();
    if (location == null) return;
    final code = location.code.split('_').first;
    final isNumeric = code == "BELLAGIO";
    if (isNumeric == _isNumericOnlyLocation) return;
    setState(() {
      _isNumericOnlyLocation = isNumeric;
      _prefixes = isNumeric ? [] : ["BM", "BL", "BN"];
      _selectedPrefix = isNumeric ? "" : "BM";
    });
  }

  /// Switches between picking a registered member and typing a non-registered
  /// one. The identity fields are cleared either way so a member selected in
  /// one mode can never leak into the other.
  void _onMemberTypeChanged(bool isRegistered) {
    if (_isRegisteredMember == isRegistered) return;
    setState(() {
      _isRegisteredMember = isRegistered;
      // Going back to a searchable member restores the location's own prefix;
      // the non-registered side always shows DHL and ignores this.
      _selectedPrefix = _isNumericOnlyLocation ? "" : "BM";
      _sharedMemberId.clear();
      _sharedMidNumber.clear();
      _sharedGuestName.clear();
      // The card belongs to a searched member; nothing backs it now.
      _sharedGuestCardVisible = false;
    });
    ref.read(selectedGuestProvider.notifier).clearGuest();
  }

  /// Keeps the saved membership no in sync while a non-registered number is
  /// typed. The registered flow gets this from the search sheet; here there is
  /// no search step, so DHL + the typed number is joined by hand.
  void _syncManualMemberId() {
    final numberPart = _sharedMidNumber.text.trim();
    _sharedMemberId.text =
        numberPart.isEmpty ? '' : '$_nonRegisteredPrefix$numberPart';
  }

  void _updateMemberIdFields(String fullMemberId) {
    if (fullMemberId.isEmpty) return;
    // A DHL number was typed in by hand, so put the form back into
    // non-registered mode rather than treating it as a searchable member.
    if (fullMemberId.startsWith(_nonRegisteredPrefix)) {
      setState(() {
        _isRegisteredMember = false;
        _sharedMidNumber.text =
            fullMemberId.substring(_nonRegisteredPrefix.length);
        _sharedMemberId.text = fullMemberId;
      });
      return;
    }
    if (_isNumericOnlyLocation) {
      setState(() {
        _sharedMidNumber.text = fullMemberId;
        _sharedMemberId.text = fullMemberId;
      });
      return;
    }
    String prefix = 'BM';
    String numberPart = fullMemberId;
    if (fullMemberId.startsWith('BM')) {
      prefix = 'BM';
      numberPart = fullMemberId.substring(2);
    } else if (fullMemberId.startsWith('BL')) {
      prefix = 'BL';
      numberPart = fullMemberId.substring(2);
    } else if (fullMemberId.startsWith('BN')) {
      prefix = 'BN';
      numberPart = fullMemberId.substring(2);
    }
    setState(() {
      _selectedPrefix = prefix;
      _sharedMidNumber.text = numberPart;
      _sharedMemberId.text = fullMemberId;
    });
  }

  Future<void> _loadHotels() async {
    final hotels = ref.read(hotelsProvider);
    if (hotels.isEmpty) await ref.read(hotelsProvider.notifier).getAllHotels();
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
    try {
      final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
      if (mounted) {
        setState(() {
          _isBellagio = apiUrl.contains('bty.world');
          // Bellagio uses "N/A" as the payment default instead of "NA".
          if (_isBellagio &&
              (_h_paymentBy.text.isEmpty || _h_paymentBy.text == 'NA')) {
            _h_paymentBy.text = 'N/A';
          }
        });
      }

      final repo = ContactPersonRepository(ApiService(SecureStorage.instance));
      final persons = await repo.getContactPersons();
      if (mounted) setState(() => _hamoueContactPersons = persons);
    } catch (_) {}
  }

  Future<void> _loadRoomCategories(double hotelId) async {
    try {
      final repo = HotelRepository(ApiService(SecureStorage.instance));
      final result = await repo.getSelectedHotelRoomCategories(hotelId);
      setState(() {
        _roomCategories = result.map((c) => c.toJson()).toList();
        _selectedRoomCategory = null;
        _selectedRoomCategoryId = null;
        _selectedRoomCategoryName = null;
        _selectedRoomType = null;
        _selectedRoomTypeId = null;
        _selectedRoomTypeName = null;
        _roomTypes = [];
        _roomCategoryDropdownKey = UniqueKey();
        _roomTypeDropdownKey = UniqueKey();
      });
    } catch (_) {
      setState(() => _roomCategories = []);
    }
  }

  Future<void> _loadRoomTypes(double hotelId, int categoryId) async {
    try {
      final repo = HotelRepository(ApiService(SecureStorage.instance));
      final result = await repo.getSelectedHotelCategoryRoomTypes(
        hotelId,
        categoryId,
      );
      setState(() {
        _roomTypes = result.map((t) => t.toJson()).toList();
        _selectedRoomType = null;
        _selectedRoomTypeId = null;
        _selectedRoomTypeName = null;
        _roomTypeDropdownKey = UniqueKey();
      });
    } catch (_) {
      setState(() => _roomTypes = []);
    }
  }

  // ── Load airline costs from API 9023 ────────────────────────────────────────
  Future<void> _loadAirlineCosts() async {
    final from = _a_fromAirport?.airportCode ?? '';
    final to = _a_toAirport?.airportCode ?? '';
    final returnTo = _a_returnToAirport?.airportCode ?? to;

    if (from.isEmpty || to.isEmpty) {
      setState(() {
        _a_airlineCosts = [];
        _a_selectedAirline = null;
        _a_airlineKey = UniqueKey();
      });
      return;
    }

    setState(() {
      _a_airlinesLoading = true;
      _a_selectedAirline = null;
      _a_airlineKey = UniqueKey();
    });

    try {
      final repo = AirportRepository(ApiService(SecureStorage.instance));
      final costs = await repo.getAirportCosts(
        departureFrom: from,
        departureTo: to,
        returnTo: returnTo,
      );
      setState(() {
        _a_airlineCosts = costs;
        _a_airlinesLoading = false;
        _a_airlineKey = UniqueKey();
      });
    } catch (_) {
      setState(() {
        _a_airlineCosts = [];
        _a_airlinesLoading = false;
        _a_airlineKey = UniqueKey();
      });
    }
  }

  // ── Shared helpers ──────────────────────────────────────────────────────────
  void _resetSharedGuest() {
    _sharedMemberId.clear();
    _sharedMidNumber.clear();
    _sharedGuestName.clear();
    _sharedGuestCardVisible = false;
  }

  void _resetHotelFields() {
    _sharedPackageAmount.clear();
    // _sharedReservationNo.clear();
    _h_noOfRooms.text = '1';
    _h_noOfPax.text = '1';
    _h_mealPlan.clear();
    _h_paymentBy.text = _isBellagio ? 'N/A' : 'NA';
    _h_remarks.clear();
    _h_marketingPerson.clear();
    _h_approvedBy.clear();
    _h_arrivalCtrl.clear();
    _h_departureCtrl.clear();
    _h_arrivalDate = null;
    _h_departureDate = null;
    _h_eciLco = 'NA';
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
  }

  void _showRequiredSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Please enter at least guest name or membership no'),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showAddedSnack(int count, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Member $count added — form reset for next member'),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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

  void _scrollToTop(ScrollController ctrl) {
    if (ctrl.hasClients) {
      ctrl.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Capture current hotel fields → _HotelEntry ──────────────────────────────
  _HotelEntry _captureCurrentHotelEntry() {
    return _HotelEntry(
      hotel: _selectedHotelName ?? '',
      hotelId: _selectedHotelId,
      arrival: _h_arrivalCtrl.text,
      departure: _h_departureCtrl.text,
      arrivalDate: _h_arrivalDate,
      departureDate: _h_departureDate,
      noOfRooms: _h_noOfRooms.text,
      noOfPax: _h_noOfPax.text,
      roomType: _selectedRoomTypeName ?? '',
      roomTypeId: _selectedRoomTypeId,
      roomCategory: _selectedRoomCategoryName ?? '',
      roomCategoryId: _selectedRoomCategoryId,
      eciLco: _h_eciLco,
      mealPlan: _h_mealPlan.text,
      paymentBy: _h_paymentBy.text,
      remarks: _h_remarks.text,
      marketingPerson: _h_marketingPerson.text,
      approvedBy: _h_approvedBy.text,
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
    setState(() {
      _pendingHotels.add(_captureCurrentHotelEntry());
      // Reset only the hotel-details fields, keep guest identity
      _h_noOfRooms.text = '1';
      _h_noOfPax.text = '1';
      _h_mealPlan.clear();
      _h_paymentBy.text = _isBellagio ? 'N/A' : 'NA';
      _h_remarks.clear();
      _h_marketingPerson.clear();
      _h_approvedBy.clear();
      _h_arrivalCtrl.clear();
      _h_departureCtrl.clear();
      _h_arrivalDate = null;
      _h_departureDate = null;
      _h_eciLco = 'NA';
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

  // ── Add Member with Same Details — HOTEL ────────────────────────────────────
  void _addMemberWithSameDetailsHotel() {
    if (_sharedGuestName.text.trim().isEmpty &&
        _sharedMemberId.text.trim().isEmpty) {
      _showRequiredSnack();
      return;
    }
    if (!(_hotelFormKey.currentState?.validate() ?? false)) return;
    // Collect current hotel if hotel name is filled
    final hotels = List<_HotelEntry>.from(_pendingHotels);
    if (_selectedHotelName != null && _selectedHotelName!.isNotEmpty) {
      hotels.add(_captureCurrentHotelEntry());
    }

    setState(() {
      _hotelMembers.add({
        'guestName': _sharedGuestName.text,
        'memberId': _sharedMemberId.text,
        'packageAmount': _sharedPackageAmount.text,
        // 'reservationNo': _sharedReservationNo.text,
        'hotels': hotels,
      });
      _resetSharedGuest();
      _pendingHotels = [];
    });
    _showAddedSnack(_hotelMembers.length, _hotelColor);
    _scrollToTop(_hotelScrollCtrl);
  }

  // ── Add Member with Same Details — AIR TICKET ───────────────────────────────
  void _addMemberWithSameDetailsAir() {
    if (_sharedGuestName.text.trim().isEmpty &&
        _sharedMemberId.text.trim().isEmpty) {
      _showRequiredSnack();
      return;
    }
    if (!(_airFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _airMembers.add(_captureCurrentAirMember());
      _resetSharedGuest();
    });
    _showAddedSnack(_airMembers.length, _airColor);
    _scrollToTop(_airScrollCtrl);
  }

  Map<String, dynamic> _captureCurrentAirMember() {
    return {
      'guestName': _sharedGuestName.text,
      'memberId': _sharedMemberId.text,
      'packageAmount': _sharedPackageAmount.text,
      // 'reservationNo': _sharedReservationNo.text,
      // display strings (used for copy text)
      'fromAirport': _a_fromAirport != null
          ? '${_a_fromAirport!.cityName ?? ''} (${_a_fromAirport!.airportCode ?? ''})'
          : '',
      'toAirport': _a_toAirport != null
          ? '${_a_toAirport!.cityName ?? ''} (${_a_toAirport!.airportCode ?? ''})'
          : '',
      'isRoundTrip': _a_isRoundTrip,
      'returnFrom': _a_returnFromAirport != null
          ? '${_a_returnFromAirport!.cityName ?? ''} (${_a_returnFromAirport!.airportCode ?? ''})'
          : '',
      'returnTo': _a_returnToAirport != null
          ? '${_a_returnToAirport!.cityName ?? ''} (${_a_returnToAirport!.airportCode ?? ''})'
          : '',
      'arrDate': _a_arrCtrl.text,
      'depDate': _a_depCtrl.text,
      'noOfSeats': _a_noOfSeats.text,
      'class': _a_selectedClass?['type'] ?? '',
      'airline': _a_selectedAirline?.airLine ?? '',
      'sector': _a_selectedAirline?.sector ?? '',
      'cost': _a_selectedAirline?.cost?.toString() ?? '',
      'remarks': _a_remarksCtrl.text,
      'skipRouteFacility': _a_skipRouteFacility,
      'airportTransport': _a_airportTransport,
      'visa': _a_visa,
      'meal': _a_meal,
      'extraLegroomSeat': _a_extraLegroomSeat,
      'goldRoute': _a_goldRoute,
      'hamoueContactPerson': _a_hamoueContactPerson ?? '',
      'passportFiles': _a_passportFiles.map((f) => f.fileName).join(', '),
      // typed fields used when building API body
      'fromAirportData': _a_fromAirport,
      'toAirportData': _a_toAirport,
      'returnFromData': _a_returnFromAirport,
      'returnToData': _a_returnToAirport,
      'arrDateObj': _a_arrDate,
      'depDateObj': _a_depDate,
      'classId': _a_selectedClass?['id'],
      'passportFileObjects': List<PassportFile>.from(_a_passportFiles),
    };
  }

  void _applyAndAddHotelMember() {
    if (_sharedGuestName.text.trim().isEmpty &&
        _sharedMemberId.text.trim().isEmpty) {
      _showRequiredSnack();
      return;
    }
    if (!(_hotelFormKey.currentState?.validate() ?? false)) return;
    final hotels = List<_HotelEntry>.from(_pendingHotels);
    if (_selectedHotelName != null && _selectedHotelName!.isNotEmpty) {
      hotels.add(_captureCurrentHotelEntry());
    }

    setState(() {
      _hotelMembers.add({
        'guestName': _sharedGuestName.text,
        'memberId': _sharedMemberId.text,
        'packageAmount': _sharedPackageAmount.text,
        // 'reservationNo': _sharedReservationNo.text,
        'hotels': hotels,
      });
      _resetSharedGuest();
      _resetHotelFields();
    });
    _showAddedSnack(_hotelMembers.length, _hotelColor);
    _scrollToTop(_hotelScrollCtrl);
  }

  // ── Apply & Add — AIR TICKET ────────────────────────────────────────────────
  void _applyAndAddAirMember() {
    if (_sharedGuestName.text.trim().isEmpty &&
        _sharedMemberId.text.trim().isEmpty) {
      _showRequiredSnack();
      return;
    }
    if (!(_airFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _airMembers.add(_captureCurrentAirMember());
      _resetSharedGuest();
      _sharedPackageAmount.clear();
      // _sharedReservationNo.clear();
      _a_noOfSeats.text = '1';
      _a_selectedClass = null;
      _a_classKey = UniqueKey();
      _a_selectedAirline = null;
      _a_airlineCosts = [];
      _a_airlineKey = UniqueKey();
      _a_arrCtrl.clear();
      _a_depCtrl.clear();
      _a_remarksCtrl.clear();
      _a_arrDate = null;
      _a_depDate = null;
      _a_fromAirport = null;
      _a_toAirport =
          ref.read(airportsProvider.notifier).findByCode(_defaultToAirportCode);
      _a_returnFromAirport = null;
      _a_returnToAirport = null;
      _a_isRoundTrip = false;
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
      _a_hamoueContactPerson = null;
      _a_passportFiles = [];
      _a_passportUploadKey = UniqueKey();
    });
    _showAddedSnack(_airMembers.length, _airColor);
    _scrollToTop(_airScrollCtrl);
  }

  // ── TRANSPORT ───────────────────────────────────────────────────────────────
  /// Captures the current form as a single transport entry. Per-vehicle Car
  /// Type + Passengers are carried as a `vehicleDetails` list (one map per
  /// vehicle) rather than flattened into separate entries.
  Map<String, dynamic> _captureCurrentTransportMember() {
    return {
      'guestName': _sharedGuestName.text,
      'memberId': _sharedMemberId.text,
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
      'silkRoute': _t_silkRoute,
      'airportPickup': _t_airportPickup,
      'passportFiles': _t_passportFiles.map((f) => f.fileName).join(', '),
      'passportFileObjects': List<PassportFile>.from(_t_passportFiles),
      // typed fields used when building the API body
      'pickupDateObj': _t_pickupDate,
      'pickupTimeObj': _t_pickupTime,
      'pickupPlaceId': _t_pickupPlaceId,
      'dropPlaceId': _t_dropPlaceId,
    };
  }

  /// Swaps the transport drop location between a searched place and the
  /// "Guest Will Inform" placeholder. Any place already picked is dropped when
  /// the placeholder is turned on so a stale place id can never be saved with
  /// it.
  void _setTransportGuestWillInformDrop(bool value) {
    setState(() {
      _t_guestWillInformDrop = value;
      _t_dropPlaceId = '';
      _t_dropLocationCtrl.text = value ? kGuestWillInform : '';
    });
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
    _t_guestWillInformDrop = false;
    _t_silkRoute = 'No';
    _t_airportPickup = 'No';
    _t_passportFiles = [];
    _t_passportUploadKey = UniqueKey();
  }

  /// Names of the transport tab's required fields that are still
  /// empty/invalid, in the same order they appear on the page.
  List<String> _missingTransportRequiredFields() {
    final missing = <String>[];
    void check(bool isMissing, String label) {
      if (isMissing) missing.add(label);
    }

    check(_sharedMidNumber.text.trim().isEmpty, 'Membership No');
    check(_t_pickupDateCtrl.text.trim().isEmpty, 'Pickup Date');
    check(_t_pickupTimeCtrl.text.trim().isEmpty, 'Pickup Time');
    check(
      _t_carTypes.any((c) => c == null || c.trim().isEmpty),
      'Car Type',
    );
    check((_t_hireType ?? '').trim().isEmpty, 'Hire Type');
    check(_t_pickupLocationCtrl.text.trim().isEmpty, 'Pickup Location');
    check(_t_dropLocationCtrl.text.trim().isEmpty, 'Drop Location');

    final digits = _t_contactNumber.text.trim();
    if (digits.isEmpty) {
      missing.add('Guest Mobile');
    } else if (digits.length < kMinContactDigits ||
        digits.length > kMaxContactDigits) {
      missing.add('Guest Mobile ($kMinContactDigits-$kMaxContactDigits digits)');
    }
    return missing;
  }

  /// Runs the transport form validators and, when something fails, names the
  /// offending fields in a bottom snack bar — the inline errors alone are easy
  /// to miss because the failing field is usually scrolled off-screen.
  bool _validateTransportForm() {
    if (_transportFormKey.currentState?.validate() ?? false) return true;
    final missing = _missingTransportRequiredFields();
    _showSaveErrorSnack(
      missing.isEmpty
          ? 'Please fill all required fields'
          : missing.length == 1
              ? '${missing.first} is required'
              : 'Required: ${missing.join(', ')}',
    );
    return false;
  }

  void _applyAndAddTransportMember() {
    if (_sharedGuestName.text.trim().isEmpty &&
        _sharedMemberId.text.trim().isEmpty) {
      _showRequiredSnack();
      return;
    }
    if (!_validateTransportForm()) return;
    setState(() {
      _transportMembers.add(_captureCurrentTransportMember());
      _resetSharedGuest();
      _resetTransportFields();
    });
    _showAddedSnack(_transportMembers.length, _transportColor);
    _scrollToTop(_transportScrollCtrl);
  }

  void _addMemberWithSameDetailsTransport() {
    if (_sharedGuestName.text.trim().isEmpty &&
        _sharedMemberId.text.trim().isEmpty) {
      _showRequiredSnack();
      return;
    }
    if (!_validateTransportForm()) return;
    setState(() {
      _transportMembers.add(_captureCurrentTransportMember());
      _resetSharedGuest();
      // Passport pages belong to the individual guest, not the shared trip
      // details, so they are cleared for the next member.
      _t_passportFiles = [];
      _t_passportUploadKey = UniqueKey();
    });
    _showAddedSnack(_transportMembers.length, _transportColor);
    _scrollToTop(_transportScrollCtrl);
  }

  void _clearAllTransportForm() {
    setState(() {
      _transportMembers.clear();
      _resetSharedGuest();
      _resetTransportFields();
    });
  }

  // ── Guest search ─────────────────────────────────────────────────────────────
  Future<void> _openGuestSearch({
    required int iid,
    required VoidCallback onCardVisible,
  }) async {
    final repo = GuestRepository(ApiService(SecureStorage.instance));
    final term = iid == 8002 ? _sharedMemberId.text : _sharedGuestName.text;
    if (term.length < 3) {
      _showSearchSheet([], term, iid, onCardVisible);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final guests = await repo.searchGuest(iid, term);
      setState(() => _isLoading = false);
      _showSearchSheet(guests, term, iid, onCardVisible);
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAndSetGuest({
    required String mid,
    required String name,
    required VoidCallback onReady,
  }) async {
    try {
      final repo = GuestRepository(ApiService(SecureStorage.instance));
      final guests = await repo.searchGuest(9021, mid);
      if (!mounted) return;
      if (guests.isNotEmpty) {
        final g = guests.first;
        ref.read(selectedGuestProvider.notifier).setSelectedGuest(
              Guest(
                mid: g.mid ?? mid,
                memberName: g.mName ?? name,
                country: '',
                lastVisitDate: g.lvd?.toString() ?? '',
                age: 0,
                gRating: g.gRating ?? '',
                mGroup: '',
                gName: g.gName ?? '',
                memImage2: g.memImage2,
              ),
            );
      } else {
        _setGuest(mid: mid, name: name);
      }
    } catch (_) {
      if (!mounted) return;
      _setGuest(mid: mid, name: name);
    }
    onReady();
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
          try {
            final repo =
                GuestRepository(ApiService(SecureStorage.instance));
            final r = await repo.searchGuest(newIid, newTerm);
            Navigator.of(ctx).pop();
            _showSearchSheet(r, newTerm, newIid, onCardVisible);
          } catch (_) {}
        },
      ),
    );
    ref.listenManual(newReservationProvider, (_, next) {
      if (next.bmNumber != null) {
        _updateMemberIdFields(next.bmNumber!);
        _sharedGuestName.text = next.guestName ?? '';
        _fetchAndSetGuest(
          mid: next.bmNumber!,
          name: next.guestName ?? '',
          onReady: onCardVisible,
        );
        ref.read(newReservationProvider.notifier).resetState();
      }
    });
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
    setState(() => _isLoading = true);
    try {
      final repo = GuestRepository(ApiService(SecureStorage.instance));
      final guests = await repo.searchGuest(9021, mid);
      setState(() => _isLoading = false);
      if (guests.isNotEmpty) {
        final g = guests.first;
        ref.read(selectedGuestProvider.notifier).setSelectedGuest(
              Guest(
                mid: g.mid ?? mid,
                memberName: g.mName ?? name,
                country: '',
                lastVisitDate: g.lvd?.toString() ?? '',
                age: 0,
                gRating: g.gRating ?? '',
                mGroup: '',
                gName: g.gName ?? '',
                memImage2: g.memImage2,
              ),
            );
      } else {
        _setGuest(mid: mid, name: name);
      }
    } catch (_) {
      setState(() => _isLoading = false);
      _setGuest(mid: mid, name: name);
    }
    if (mounted) context.push('/home/profile');
  }

  Future<DateTime?> _pickDate(
    BuildContext context, {
    String label = 'Select Date',
    DateTime? initial,
    DateTime? minDate,
  }) async {
    DateTime picked = initial ?? minDate ?? DateTime.now();
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

  String _fmtTime(TimeOfDay t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${h12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }

  // ── Message builders — HOTEL ─────────────────────────────────────────────────
  String _singleHotelEntryText(_HotelEntry h, {int? hotelIndex}) {
    final prefix =
        hotelIndex != null ? '  [Hotel ${hotelIndex + 1}]\n' : '';
    return '''${prefix}  Name of the Hotel    : ${h.hotel}
  Arrival              : ${h.arrival}
  Departure            : ${h.departure}
  No of Room/s         : ${h.noOfRooms}
  No Of Pax            : ${h.noOfPax}
  Room Type            : ${h.roomType}
  Room Category        : ${h.roomCategory}
  ECI/LCO Facility     : ${h.eciLco}
  Payment By           : ${h.paymentBy}
  Remarks              : ${h.remarks}''';
  }

  String _singleHotelMemberText(Map<String, dynamic> m) {
    final hotels = (m['hotels'] as List<_HotelEntry>?) ?? [];
    final buf = StringBuffer();
    buf.writeln('*HOTEL RESERVATION REQUEST*');
    buf.writeln('Name of the Guest    : ${m['guestName']}');
    buf.writeln('Membership No        : ${m['memberId']}');
    buf.writeln('Reservation No       : ${m['reservationNo'] ?? ''}');
    buf.writeln('Package Amount       : ${m['packageAmount']}');
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
    buf.write('*');
    return buf.toString();
  }

  // Legacy signature kept for _addedMembersSection textBuilder
  String _singleHotelText(Map<String, dynamic> m) =>
      _singleHotelMemberText(m);

  String _buildHotelText() {
    // Build a "current" member snapshot from the form
    final currentHotels = List<_HotelEntry>.from(_pendingHotels);
    if (_selectedHotelName != null && _selectedHotelName!.isNotEmpty) {
      currentHotels.add(_captureCurrentHotelEntry());
    }
    final current = {
      'guestName': _sharedGuestName.text,
      'memberId': _sharedMemberId.text,
      'packageAmount': _sharedPackageAmount.text,
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
    String sector = '';
    if ((m['fromAirport'] as String).isNotEmpty &&
        (m['toAirport'] as String).isNotEmpty)
      sector = '${m['fromAirport']} → ${m['toAirport']}';
    if (isRound &&
        (m['returnFrom'] as String).isNotEmpty &&
        (m['returnTo'] as String).isNotEmpty)
      sector +=
          '\n                         ${m['returnFrom']} → ${m['returnTo']}';
    return '''
*AIR TICKET REQUEST*
BM                       : ${m['memberId']}
Guest Name        : ${m['guestName']}
Reservation No    : ${m['reservationNo'] ?? ''}
Package Amount : ${m['packageAmount']}
Sector                  : $sector
Arr Date              : ${m['arrDate']}
Dep Date             : ${m['depDate']}
No of Seats         : ${m['noOfSeats']}
Class                    : ${m['class']}
Airline                  : ${m['airline']}${(m['sector'] as String? ?? '').isNotEmpty ? ' (${m['sector']})' : ''}
Cost                      : ${m['cost']}
Round Trip           : ${isRound ? 'Yes' : 'No'}
Slik Route Facility : ${m['skipRouteFacility']}
Airport Transport   : ${m['airportTransport']}
Visa                     : ${m['visa']}
Meal                     : ${m['meal']}
Extra Legroom Seat  : ${m['extraLegroomSeat']}
Gold Route            : ${m['goldRoute']}
Hamoue Contact   : ${(m['hamoueContactPerson'] as String? ?? '').isEmpty ? 'NA' : m['hamoueContactPerson']}
Passport File/s      : ${(m['passportFiles'] as String? ?? '').isEmpty ? 'None' : m['passportFiles']}
Remarks              : ${m['remarks']}''';
  }

  String _buildAirText() {
    final fromCode = _a_fromAirport?.airportCode ?? '';
    final fromCity = _a_fromAirport?.cityName ?? '';
    final toCode = _a_toAirport?.airportCode ?? '';
    final toCity = _a_toAirport?.cityName ?? '';
    final current = {
      'guestName': _sharedGuestName.text,
      'memberId': _sharedMemberId.text,
      'packageAmount': _sharedPackageAmount.text,
      // 'reservationNo': _sharedReservationNo.text,
      'fromAirport': (fromCode.isNotEmpty && fromCity.isNotEmpty)
          ? '$fromCity ($fromCode)'
          : '',
      'toAirport': (toCode.isNotEmpty && toCity.isNotEmpty)
          ? '$toCity ($toCode)'
          : '',
      'isRoundTrip': _a_isRoundTrip,
      'returnFrom': _a_returnFromAirport != null
          ? '${_a_returnFromAirport!.cityName ?? ''} (${_a_returnFromAirport!.airportCode ?? ''})'
          : '',
      'returnTo': _a_returnToAirport != null
          ? '${_a_returnToAirport!.cityName ?? ''} (${_a_returnToAirport!.airportCode ?? ''})'
          : '',
      'arrDate': _a_arrCtrl.text,
      'depDate': _a_depCtrl.text,
      'noOfSeats': _a_noOfSeats.text,
      'class': _a_selectedClass?['type'] ?? '',
      'airline': _a_selectedAirline?.airLine ?? '',
      'sector': _a_selectedAirline?.sector ?? '',
      'cost': _a_selectedAirline?.cost?.toString() ?? '',
      'remarks': _a_remarksCtrl.text,
      'skipRouteFacility': _a_skipRouteFacility,
      'airportTransport': _a_airportTransport,
      'visa': _a_visa,
      'meal': _a_meal,
      'extraLegroomSeat': _a_extraLegroomSeat,
      'goldRoute': _a_goldRoute,
      'hamoueContactPerson': _a_hamoueContactPerson ?? '',
      'passportFiles': _a_passportFiles.map((f) => f.fileName).join(', '),
    };
    if (_airMembers.isEmpty) return _singleAirText(current);
    final all = [
      ..._airMembers,
      if ((current['guestName'] as String).isNotEmpty ||
          (current['memberId'] as String).isNotEmpty)
        current,
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
      ..writeln('Slik Route         : ${m['silkRoute'] ?? 'No'}')
      ..write('Airport Pickup     : ${m['airportPickup'] ?? 'No'}');
    final passports = m['passportFiles'] as String? ?? '';
    if (passports.isNotEmpty) {
      buf.write('\nPassport Files     : $passports');
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

  Map<String, dynamic> _airMemberToTicketDetail(Map<String, dynamic> m) {
    final fromAirport = m['fromAirportData'] as Airport?;
    final toAirport = m['toAirportData'] as Airport?;
    final returnFrom = m['returnFromData'] as Airport?;
    final returnTo = m['returnToData'] as Airport?;
    final arrDate = m['arrDateObj'] as DateTime?;
    final depDate = m['depDateObj'] as DateTime?;
    return {
      'guest_count': int.tryParse(m['noOfSeats'] as String? ?? '1') ?? 1,
      'air_ticket_class': m['classId'],
      'air_ticket_class_name': m['class'],
      'air_line': m['airline'],
      'contact_person': m['hamoueContactPerson'],
      'visa': (m['visa'] as String?) == 'Yes',
      'meal': (m['meal'] as String?) == 'Yes',
      'extra_leg_room_seat': (m['extraLegroomSeat'] as String?) == 'Yes',
      'gold_route': (m['goldRoute'] as String?) == 'Yes',
      'is_round_trip': m['isRoundTrip'] as bool? ?? false,
      'silk_route': (m['skipRouteFacility'] as String?) == 'Yes' ? 1 : 0,
      'airport_transportation': (m['airportTransport'] as String?) == 'Yes' ? 1 : 0,
      'arrival_date': arrDate?.toIso8601String(),
      'departure_date': depDate?.toIso8601String(),
      'selected_cost': double.tryParse(m['cost'] as String? ?? '0') ?? 0.0,
      'BMNumber': m['memberId'],
      'DF_AirportCode': fromAirport?.airportCode,
      'DF_CityName': fromAirport?.cityName,
      'DF_AirportName': fromAirport?.airportName,
      'DF_Country': fromAirport?.country,
      'DT_AirportCode': toAirport?.airportCode,
      'DT_CityName': toAirport?.cityName,
      'DT_AirportName': toAirport?.airportName,
      'DT_Country': toAirport?.country,
      'RF_AirportCode': returnFrom?.airportCode,
      'RF_CityName': returnFrom?.cityName,
      'RF_AirportName': returnFrom?.airportName,
      'RF_Country': returnFrom?.country,
      'RT_AirportCode': returnTo?.airportCode,
      'RT_CityName': returnTo?.cityName,
      'RT_AirportName': returnTo?.airportName,
      'RT_Country': returnTo?.country,
    };
  }

  List<Map<String, dynamic>> _buildPassportImages(
      List<Map<String, dynamic>> members) {
    final images = <Map<String, dynamic>>[];
    for (final m in members) {
      final memberId = m['memberId'] as String? ?? '';
      final files = m['passportFileObjects'] as List<PassportFile>? ?? [];
      for (final f in files) {
        try {
          final bytes = File(f.path).readAsBytesSync();
          images.add({
            'mid': memberId,
            'FileName': f.fileName,
            'IsPdf': f.isPdf,
            'Base64Data': base64Encode(bytes),
          });
        } catch (_) {}
      }
    }
    return images;
  }

  void _clearAllHotelForm() {
    setState(() {
      _hotelMembers.clear();
      _resetSharedGuest();
      _resetHotelFields();
    });
  }

  void _clearAllAirForm() {
    setState(() {
      _airMembers.clear();
      _resetSharedGuest();
      _sharedPackageAmount.clear();
      // _sharedReservationNo.clear();
      _a_noOfSeats.text = '1';
      _a_selectedClass = null;
      _a_classKey = UniqueKey();
      _a_selectedAirline = null;
      _a_airlineCosts = [];
      _a_airlineKey = UniqueKey();
      _a_arrCtrl.clear();
      _a_depCtrl.clear();
      _a_remarksCtrl.clear();
      _a_arrDate = null;
      _a_depDate = null;
      _a_fromAirport = null;
      _a_toAirport =
          ref.read(airportsProvider.notifier).findByCode(_defaultToAirportCode);
      _a_returnFromAirport = null;
      _a_returnToAirport = null;
      _a_isRoundTrip = false;
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
      _a_hamoueContactPerson = null;
      _a_passportFiles = [];
      _a_passportUploadKey = UniqueKey();
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
    if (hasCurrentGuest && !_validateTransportForm()) {
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

    final transportDetails =
        allMembers.map((m) => _transportMemberToDetail(m)).toList();

    final guests = allMembers
        .map((m) => {
              'MID': m['memberId'],
              'GuestName': m['guestName'],
              'PickupDate': _pickupIso(m),
              'ContactNumber': m['contactNumber'],
            })
        .toList();

    final primary = allMembers.first;
    final salesCode = await StorageUtil.getSalesCode();
    final userName = await StorageUtil.getUName();
    final deviceId = await DeviceId.get();
    final masterId = DateTime.now().millisecondsSinceEpoch.toString();
final phoneNumber = await StorageUtil.getMobileNumber();
    final body = <String, dynamic>{
      'master_id': masterId,
      'MID': primary['memberId'],
      'guest_name': primary['guestName'],
      'pickup_date': _pickupIso(primary),
      'contact_number': phoneNumber,
      'reservation_status': 'Requested',
      'sales_code': salesCode,
      'user_name': userName,
      'device_id': deviceId,
      'transport_details': transportDetails,
      'passport_images': _buildPassportImages(allMembers),
      // 'guests': guests,
    };

    setState(() => _isLoading = true);
    try {
      _logLong('Saving transport reservation', body);
      final apiService = ApiService(SecureStorage.instance);
      final response = await apiService.post('Transport_Insert', body);
      if (!mounted) return;
      setState(() => _isLoading = false);
      final status = response['Status'] as bool? ?? false;
      if (status) {
        _clearAllTransportForm();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(response['Message'] as String? ??
                    'Transport reservation saved successfully')),
          ]),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      } else {
        _showSaveErrorSnack(response['Message'] as String? ??
            'Failed to save transport reservation');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSaveErrorSnack(e.toString());
    }
  }

  /// Pickup date and time combined into a single ISO timestamp.
  String? _pickupIso(Map<String, dynamic> m) {
    final date = m['pickupDateObj'] as DateTime?;
    if (date == null) return null;
    final time = m['pickupTimeObj'] as TimeOfDay?;
    return DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    ).toIso8601String();
  }

  Map<String, dynamic> _transportMemberToDetail(Map<String, dynamic> m) {
    final vehicles = (m['vehicleDetails'] as List?)?.cast<Map>() ?? const [];
    return {
      'MID': m['memberId'],
      'guest_name': m['guestName'],
      'pickup_date': _pickupIso(m),
      'pickup_time': m['pickupTime'],
      'hire_type': m['hireType'],
      'pickup_location': m['pickupLocation'],
      'pickup_place_id': m['pickupPlaceId'],
      'drop_location': m['dropLocation'],
      'drop_place_id': m['dropPlaceId'],
      'no_of_vehicles': vehicles.length,
      'vehicle_details': vehicles
          .map((v) => {
                'car_type': v['carType'],
                'no_of_passengers':
                    int.tryParse(v['noOfPassengers'] as String? ?? '1') ?? 1,
              })
          .toList(),
      'contact_number': m['contactNumber'],
      'silk_route': (m['silkRoute'] as String?) == 'Yes' ? 1 : 0,
      'airport_pickup': (m['airportPickup'] as String?) == 'Yes' ? 1 : 0,
    };
  }

  Future<void> _saveHotelSection() async {
    // Collect current form's hotel entries
    final currentHotels = List<_HotelEntry>.from(_pendingHotels);
    if (_selectedHotelName != null && _selectedHotelName!.isNotEmpty) {
      currentHotels.add(_captureCurrentHotelEntry());
    }
    final hasCurrentGuest = _sharedGuestName.text.trim().isNotEmpty ||
        _sharedMemberId.text.trim().isNotEmpty;

    // Only validate the on-screen form when it still holds a member that will
    // be submitted — after "Apply & Add" it is cleared on purpose.
    if ((hasCurrentGuest || currentHotels.isNotEmpty) &&
        !(_hotelFormKey.currentState?.validate() ?? false)) {
      return;
    }

    final allMembers = <Map<String, dynamic>>[
      ..._hotelMembers,
      if (hasCurrentGuest || currentHotels.isNotEmpty)
        {
          'guestName': _sharedGuestName.text,
          'memberId': _sharedMemberId.text,
          'packageAmount': _sharedPackageAmount.text,
          // 'reservationNo': _sharedReservationNo.text,
          'hotels': currentHotels,
        },
    ];

    if (allMembers.isEmpty) {
      _showSaveErrorSnack('Please add at least one guest before saving');
      return;
    }

    // Flatten all hotel entries from all members into room_details
    final roomDetails = <Map<String, dynamic>>[];
    for (final m in allMembers) {
      final hotels = (m['hotels'] as List<_HotelEntry>?) ?? [];
      roomDetails.addAll(hotels.map((h) => {
            ...h.toApiJson(),
            'BMNumber': m['memberId'],
          }));
    }

    // Pull the first non-empty remark from a member's hotel entries.
    String remarksForMember(Map<String, dynamic> m) {
      final hotels = (m['hotels'] as List<_HotelEntry>?) ?? [];
      for (final h in hotels) {
        if (h.remarks.trim().isNotEmpty) return h.remarks.trim();
      }
      return '';
    }

    final guests = allMembers
        .map((m) => {
              'BMNumber': m['memberId'],
              'GuestName': m['guestName'],
              'ArrivalDate': null,
              'DepartureDate': null,
              'HasAirTicketReservation': false,
              'Remarks': remarksForMember(m),
            })
        .toList();

    final primary = allMembers.first;
    final primaryHotels = (primary['hotels'] as List<_HotelEntry>?) ?? [];
    final firstHotel = primaryHotels.isNotEmpty ? primaryHotels.first : null;

    final salesCode = await StorageUtil.getSalesCode();
    final userName = await StorageUtil.getUName();
    final deviceId = await DeviceId.get();
    final masterId = DateTime.now().millisecondsSinceEpoch.toString();
    final body = <String, dynamic>{
       'master_id': masterId,
      'bm_number': primary['memberId'],
      'guest_name': primary['guestName'],
      'arrival_date': firstHotel?.arrivalDate?.toIso8601String(),
      'departure_date': firstHotel?.departureDate?.toIso8601String(),
      'no_of_nights': firstHotel != null &&
              firstHotel.arrivalDate != null &&
              firstHotel.departureDate != null
          ? firstHotel.departureDate!
              .difference(firstHotel.arrivalDate!)
              .inDays
          : 0,
      'has_air_ticket_reservation': false,
      'remarks': remarksForMember(primary),
      'manual_reserv_no': '',
      'package_amount': packageAmountToInt(primary['packageAmount'] as String?),
      'currency_type':
          packageAmountCurrency(primary['packageAmount'] as String?),
      'selected_marketing_person': '',
      "reservation_status":"Pending",
      'sales_code': salesCode,
      'user_name': userName,
      'device_id': deviceId,
      'room_details': roomDetails,
      'air_ticket_details': [],
      'guests': guests,
      'passport_images': [],
    };
print(" rrr : $body");
    setState(() => _isLoading = true);
    try {
      final apiService = ApiService(SecureStorage.instance);
      
      final response =
          await apiService.post('Reservation_InsertReservation', body);
          print("test3 $response");
      if (!mounted) return;
      setState(() => _isLoading = false);
      final status = response['Status'] as bool? ?? false;
      if (status) {
        _clearAllHotelForm();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(response['Message'] as String? ??
                    'Reservation saved successfully')),
          ]),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      } else {
        _showSaveErrorSnack(
            response['Message'] as String? ?? 'Failed to save reservation');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSaveErrorSnack(e.toString());
    }
  }

  Future<void> _saveAirSection() async {
    final hasCurrentGuest = _sharedGuestName.text.trim().isNotEmpty ||
        _sharedMemberId.text.trim().isNotEmpty;

    // Only validate the on-screen form when it still holds a member that will
    // be submitted — after "Apply & Add" it is cleared on purpose.
    if (hasCurrentGuest && !(_airFormKey.currentState?.validate() ?? false)) {
      return;
    }

    final allMembers = <Map<String, dynamic>>[
      ..._airMembers,
      if (hasCurrentGuest) _captureCurrentAirMember(),
    ];

    if (allMembers.isEmpty) {
      _showSaveErrorSnack('Please add at least one guest before saving');
      return;
    }

    final airTicketDetails =
        allMembers.map((m) => _airMemberToTicketDetail(m)).toList();

    final guests = allMembers
        .map((m) => {
              'BMNumber': m['memberId'],
              'GuestName': m['guestName'],
              'ArrivalDate': (m['arrDateObj'] as DateTime?)?.toIso8601String(),
              'DepartureDate':
                  (m['depDateObj'] as DateTime?)?.toIso8601String(),
              'HasAirTicketReservation': true,
              'Remarks': m['remarks'] ?? '',
            })
        .toList();

    final passportImages = _buildPassportImages(allMembers);

    final primary = allMembers.first;
    final salesCode = await StorageUtil.getSalesCode();
    final userName = await StorageUtil.getUName();
    final deviceId = await DeviceId.get();
    final masterId = DateTime.now().millisecondsSinceEpoch.toString();
print(" rrr : $airTicketDetails");
    final body = <String, dynamic>{
      'master_id': masterId,
      'bm_number': primary['memberId'],
      'guest_name': primary['guestName'],
      'arrival_date':
          (primary['arrDateObj'] as DateTime?)?.toIso8601String(),
      'departure_date':
          (primary['depDateObj'] as DateTime?)?.toIso8601String(),
      'no_of_nights': 0,
      'has_air_ticket_reservation': true,
      'remarks': primary['remarks'] ?? '',
      'manual_reserv_no': '',
      'package_amount': packageAmountToInt(primary['packageAmount'] as String?),
      'currency_type':
          packageAmountCurrency(primary['packageAmount'] as String?),
      'selected_marketing_person': '',
      "reservation_status":"Pending",
      'sales_code': salesCode,
      'user_name': userName,
      'device_id': deviceId,
      'room_details': [],
      'air_ticket_details': airTicketDetails,
      'guests': guests,
      'passport_images': passportImages,
    };
print(" rrr : $body");
    setState(() => _isLoading = true);
    try {
      final apiService = ApiService(SecureStorage.instance);
      final response =
          await apiService.post('Reservation_InsertReservation', body);
           print("test4 $response");
      if (!mounted) return;
      setState(() => _isLoading = false);
      final status = response['Status'] as bool? ?? false;
      if (status) {
        _clearAllAirForm();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(response['Message'] as String? ??
                    'Reservation saved successfully')),
          ]),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      } else {
        _showSaveErrorSnack(
            response['Message'] as String? ?? 'Failed to save reservation');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSaveErrorSnack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fontSettingsProvider);
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
                      // Transport is a Bellagio-only section.
                      if (_isBellagio) ...[
                        const SizedBox(width: 8),
                        _sectionTab(
                          _Section.transport,
                          Icons.directions_car_rounded,
                          'Transport',
                        ),
                      ],
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _onSave,
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.save_alt),
            label: const Text(
              'Confirm Reservation',
              style: TextStyle(fontWeight: FontWeight.w600),
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

Widget _dateField(
  BuildContext context,
  String label,
  TextEditingController ctrl,
  Color accent,
  VoidCallback onTap, {
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: ctrl,
    readOnly: true,
    style: kInputTextStyle,
    decoration: _fieldDeco(
      label,
      icon: Icons.calendar_today_rounded,
      accent: accent,
    ).copyWith(suffixIcon: Icon(Icons.arrow_drop_down, color: accent)),
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
  required bool isRegisteredMember,
  required ValueChanged<bool> onMemberTypeChanged,
  required VoidCallback onManualIdChanged,
  FormFieldValidator<String>? memberIdValidator,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ── Registered / Non-Registered member ──
      Row(
        children: [
          Expanded(
            child: _memberTypeOption(
              label: 'Member',
              isRegistered: true,
              groupValue: isRegisteredMember,
              accent: accent,
              onChanged: onMemberTypeChanged,
            ),
          ),
          Expanded(
            child: _memberTypeOption(
              label: 'DB Holder',
              isRegistered: false,
              groupValue: isRegisteredMember,
              accent: accent,
              onChanged: onMemberTypeChanged,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: memberIdNumberCtrl,
              style: kInputTextStyle,
              keyboardType: TextInputType.number,
              validator: memberIdValidator,
              decoration: _fieldDeco(midLabel, accent: accent).copyWith(
                // Non-registered numbers are always issued under DHL, so the
                // prefix is fixed rather than chosen.
                prefixIcon: !isRegisteredMember
                    ? Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            _QuickReservationScreenState._nonRegisteredPrefix,
                            style: kInputTextStyle,
                          ),
                        ),
                      )
                    : isNumericOnly
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
                // A non-registered number exists only outside the system —
                // there is nothing to search it against.
                suffixIcon: !isRegisteredMember
                    ? null
                    : IconButton(
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
                if (!isRegisteredMember) {
                  // Typed by hand, so this is the only place the saved
                  // membership no gets set.
                  onManualIdChanged();
                  return;
                }
                memberNameCtrl.clear();
                memberIdCtrl.text =
                    isNumericOnly ? value : '$selectedPrefix$value';
              },
            ),
          ),
          // Non-registered members have no profile to open.
          if (isRegisteredMember) ...[
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
          suffixIcon: !isRegisteredMember
              ? null
              : IconButton(
                  icon: Icon(Icons.search, color: accent),
                  onPressed: onSearchByName,
                ),
        ),
        textCapitalization: TextCapitalization.words,
        onChanged: (_) {
          // The name is typed alongside the number for a non-registered
          // member; clearing the number here would wipe what was just entered.
          if (!isRegisteredMember) return;
          memberIdNumberCtrl.clear();
        },
      ),
    ],
  );
}

/// One tappable radio + label of the registered / non-registered pair.
Widget _memberTypeOption({
  required String label,
  required bool isRegistered,
  required bool groupValue,
  required Color accent,
  required ValueChanged<bool> onChanged,
}) {
  return InkWell(
    onTap: () => onChanged(isRegistered),
    borderRadius: BorderRadius.circular(8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<bool>(
          value: isRegistered,
          groupValue: groupValue,
          activeColor: accent,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) => onChanged(v!),
        ),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: kInputTextStyle)),
      ],
    ),
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

// ── Action buttons: Apply & Add + Add with Same Details ──────────────────────
Widget _actionButtons({
  required Color accent,
  required VoidCallback onApplyAndAdd,
  required VoidCallback onSameDetails,
}) {
  return Column(
    children: [
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onApplyAndAdd,
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text(
            'Apply & Add Member',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onSameDetails,
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent, width: 1.8),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.group_add_rounded),
          label: const Text(
            'Add Member with Same Details',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Airport dropdown
// ─────────────────────────────────────────────────────────────────────────────
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
// Airline cost dropdown — fetches from API 9023
// ─────────────────────────────────────────────────────────────────────────────
class _AirlineDropdown extends StatelessWidget {
  final Key dropdownKey;
  final List<AirportCostResponse> items;
  final AirportCostResponse? selectedItem;
  final bool isLoading;
  final Color accent;
  final ValueChanged<AirportCostResponse?> onChanged;

  const _AirlineDropdown({
    required this.dropdownKey,
    required this.items,
    required this.selectedItem,
    required this.isLoading,
    required this.accent,
    required this.onChanged,
  });

  String _itemLabel(AirportCostResponse a) {
    final parts = <String>[];
    if ((a.airLine ?? '').isNotEmpty) parts.add(a.airLine!);
    if ((a.sector ?? '').isNotEmpty) parts.add(a.sector!.trim());
    if (a.cost != null) parts.add('LKR ${a.cost}');
    if ((a.travelClass ?? '').isNotEmpty) parts.add('Class: ${a.travelClass}');
    return parts.join(' | ');
  }

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

    return DropdownSearch<AirportCostResponse>(
      key: dropdownKey,
      selectedItem: selectedItem,
      items: (filter, _) {
        if (filter.isEmpty) return items;
        final lf = filter.toLowerCase();
        return items
            .where((a) =>
                (a.airLine ?? '').toLowerCase().contains(lf) ||
                (a.sector ?? '').toLowerCase().contains(lf) ||
                (a.travelClass ?? '').toLowerCase().contains(lf))
            .toList();
      },
      itemAsString: _itemLabel,
      compareFn: (a, b) =>
          a.airLine == b.airLine &&
          a.sector == b.sector &&
          a.cost == b.cost,
      enabled: items.isNotEmpty,
      decoratorProps: DropDownDecoratorProps(
        decoration: _fieldDeco(
          items.isEmpty
              ? 'Airline  (select From/To airports first)'
              : 'Select Airline *',
          icon: Icons.airplanemode_active_rounded,
          accent: accent,
        ),
      ),
      dropdownBuilder: (context, item) {
        if (item == null) return const Text('');
        return Text(
          _itemLabel(item),
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
            hintText: 'Search airline or sector...',
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
          leading: CircleAvatar(
            backgroundColor: accent.withOpacity(0.12),
            child: Text(
              (item.airLine ?? '??').length > 3
                  ? (item.airLine ?? '??').substring(0, 3)
                  : (item.airLine ?? '??'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
          title: Text(
            '${item.airLine ?? ''} — ${(item.sector ?? '').trim()}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((item.travelClass ?? '').isNotEmpty)
                Text('Class: ${item.travelClass}',
                    style:
                        const TextStyle(fontSize: 13, color: Colors.grey)),
              if (item.cost != null)
                Text('Cost: LKR ${item.cost}',
                    style: TextStyle(
                        fontSize: 13,
                        color: accent,
                        fontWeight: FontWeight.w600)),
              if (item.usRate != null)
                Text('USD Rate: ${item.usRate}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
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
  final _QuickReservationScreenState state;
  const _HotelForm({super.key, required this.state});

  static String _hotelName(Map<String, dynamic>? item) =>
      (item?['hotel_name'] ?? '') as String;
  static double? _hotelId(Map<String, dynamic>? item) =>
      (item?['hotel'] as num?)?.toDouble();

  @override
  Widget build(BuildContext context) {
    const accent = _QuickReservationScreenState._hotelColor;
    final hotels = state.ref.watch(hotelsProvider);
    return Form(
      key: state._hotelFormKey,
      // A lazy ListView only builds the rows near the viewport, and
      // Form.validate() skips fields that are not mounted, so saving from the
      // top of the form silently bypassed every validator further down. A
      // Column keeps all fields alive at all times.
      child: SingleChildScrollView(
        controller: state._hotelScrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _sectionHeader(
            'Hotel Reservation Request',
            accent,
            Icons.hotel_rounded,
          ),
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
            onPrefixChanged: (v) => state.setState(() {
              state._selectedPrefix = v;
              state._sharedMemberId.text =
                  '$v${state._sharedMidNumber.text}';
            }),
            isRegisteredMember: state._isRegisteredMember,
            onMemberTypeChanged: state._onMemberTypeChanged,
            onManualIdChanged: state._syncManualMemberId,
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
          PackageAmountField(
            controller: state._sharedPackageAmount,
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
                minDate: state._h_arrivalDate != null
                    ? state._h_arrivalDate!.add(const Duration(days: 1))
                    : null,
              );
              if (d != null) {
                state._h_departureDate = d;
                state._h_departureCtrl.text = state._fmt(d);
                // ignore: invalid_use_of_protected_member
                (context as Element).markNeedsBuild();
              }
            },
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
            ),
            _StepperField(
              controller: state._h_noOfPax,
              label: 'No of Pax',
              icon: Icons.group_outlined,
              accent: accent,
            ),
          ),
          const SizedBox(height: 12),
          DropdownSearch<Map<String, dynamic>>(
            key: state._hotelDropdownKey,
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
                'Hotel Name *',
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
                  (c) => ((c['CatName'] ?? '') as String)
                      .toLowerCase()
                      .contains(f.toLowerCase()),
                )
                .toList(),
            itemAsString: (item) => (item['CatName'] ?? '') as String,
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
              (selectedItem?['CatName'] ?? '') as String,
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
            compareFn: (a, b) => a['ID'] == b['ID'],
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
            dropdownBuilder: (context, selectedItem) => Text(
              selectedItem == null
                  ? ''
                  : '${selectedItem['RoomType'] ?? ''} - ${selectedItem['MealPlan'] ?? ''}',
              style: kInputTextStyle,
              overflow: TextOverflow.ellipsis,
            ),
            onChanged: (val) {
              state.setState(() {
                state._selectedRoomType = val;
                state._selectedRoomTypeId = val?['ID'] as int?;
                state._selectedRoomTypeName =
                    '${val?['RoomType'] ?? ''} - ${val?['MealPlan'] ?? ''}';
              });
            },
            popupProps: PopupProps.dialog(
              showSearchBox: true,
              itemBuilder: (ctx, item, isSelected, isFocused) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: accent.withOpacity(0.12),
                  child:
                      Icon(Icons.bed_outlined, color: accent, size: 18),
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
              ),
              dialogProps: DialogProps(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
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
            label: 'Payment By',
            accent: accent,
            child: _ChipSelector(
              key: ValueKey('payment_by_${state._isBellagio}'),
              options: state._isBellagio
                  ? const [
                      'N/A',
                      'By Guest',
                      'By Beyond Borders',
                      'By Guest & Beyond Borders',
                    ]
                  : const [
                      'NA',
                      'By Guest',
                      'By Hamoos',
                      'By Guest & Hamoos',
                    ],
              selected: state._h_paymentBy.text.isEmpty
                  ? (state._isBellagio ? 'N/A' : 'NA')
                  : state._h_paymentBy.text,
              accent: accent,
              onChanged: (v) =>
                  state.setState(() => state._h_paymentBy.text = v),
            ),
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
          const SizedBox(height: 12),

          // ── Add Another Hotel button ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: state._addAnotherHotel,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(
                    color: accent.withOpacity(0.6), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: accent.withOpacity(0.04),
              ),
              icon: const Icon(Icons.add_business_rounded),
              label: const Text(
                'Add Another Hotel for This Guest',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _actionButtons(
            accent: accent,
            onApplyAndAdd: state._applyAndAddHotelMember,
            onSameDetails: state._addMemberWithSameDetailsHotel,
          ),
          const SizedBox(height: 20),
          _addedMembersSection(
            members: state._hotelMembers,
            accent: accent,
            textBuilder: state._singleHotelText,
            onRemove: (i) =>
                () => state.setState(() => state._hotelMembers.removeAt(i)),
          ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AIR TICKET FORM
// ─────────────────────────────────────────────────────────────────────────────
class _AirForm extends StatelessWidget {
  final _QuickReservationScreenState state;
  const _AirForm({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const accent = _QuickReservationScreenState._airColor;
    return Form(
      key: state._airFormKey,
      // A lazy ListView only builds the rows near the viewport, and
      // Form.validate() skips fields that are not mounted, so saving from the
      // top of the form silently bypassed every validator further down. A
      // Column keeps all fields alive at all times.
      child: SingleChildScrollView(
        controller: state._airScrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _sectionHeader('Air Ticket Request', accent, Icons.flight_rounded),
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
            onPrefixChanged: (v) => state.setState(() {
              state._selectedPrefix = v;
              state._sharedMemberId.text =
                  '$v${state._sharedMidNumber.text}';
            }),
            isRegisteredMember: state._isRegisteredMember,
            onMemberTypeChanged: state._onMemberTypeChanged,
            onManualIdChanged: state._syncManualMemberId,
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
          PackageAmountField(
            controller: state._sharedPackageAmount,
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
          const SizedBox(height: 16),
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
              );
              if (d != null) {
                state._a_arrDate = d;
                state._a_arrCtrl.text = state._fmt(d);
                // ignore: invalid_use_of_protected_member
                (context as Element).markNeedsBuild();
              }
            },
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
                minDate: state._a_arrDate != null
                    ? state._a_arrDate!.add(const Duration(days: 1))
                    : null,
              );
              if (d != null) {
                state._a_depDate = d;
                state._a_depCtrl.text = state._fmt(d);
                // ignore: invalid_use_of_protected_member
                (context as Element).markNeedsBuild();
              }
            },
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
                      // Reset airline when route changes
                      state._a_selectedAirline = null;
                      state._a_airlineCosts = [];
                      state._a_airlineKey = UniqueKey();
                    });
                    state._loadAirlineCosts();
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
                      // Reset airline when route changes
                      state._a_selectedAirline = null;
                      state._a_airlineCosts = [];
                      state._a_airlineKey = UniqueKey();
                    });
                    state._loadAirlineCosts();
                  },
                ),
              ],
            ),
          ),
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
                      } else {
                        state._a_returnFromAirport = null;
                        state._a_returnToAirport = null;
                      }
                      state._a_selectedAirline = null;
                      state._a_airlineCosts = [];
                      state._a_airlineKey = UniqueKey();
                    });
                    state._loadAirlineCosts();
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
                    onChanged: (a) {
                      state.setState(() => state._a_returnFromAirport = a);
                      state._loadAirlineCosts();
                    },
                  ),
                  const SizedBox(height: 10),
                  _AirportDropdown(
                    key: state._a_returnToAirportKey,
                    label: 'Return To',
                    accent: accent,
                    selectedAirport: state._a_returnToAirport,
                    onChanged: (a) {
                      state.setState(() => state._a_returnToAirport = a);
                      state._loadAirlineCosts();
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _StepperField(
            controller: state._a_noOfSeats,
            label: 'No of Seats',
            icon: Icons.event_seat_outlined,
            accent: accent,
          ),
          const SizedBox(height: 12),
          AirTicketClassSelector(
            key: state._a_classKey,
            selectedClass: state._a_selectedClass,
            onClassSelected: (selectedClass) => state.setState(() {
              state._a_selectedClass = selectedClass;
            }),
          ),
          const SizedBox(height: 12),

          // ── Airline dropdown (from API 9023) ──────────────────────────────────
          _AirlineDropdown(
            dropdownKey: state._a_airlineKey,
            items: state._a_airlineCosts,
            selectedItem: state._a_selectedAirline,
            isLoading: state._a_airlinesLoading,
            accent: accent,
            onChanged: (val) =>
                state.setState(() => state._a_selectedAirline = val),
          ),

          // ── Selected airline info card ─────────────────────────────────────
          if (state._a_selectedAirline != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flight_rounded, color: accent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        state._a_selectedAirline!.airLine ?? '',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if ((state._a_selectedAirline!.sector ?? '').isNotEmpty)
                    Text(
                      'Sector: ${state._a_selectedAirline!.sector!.trim()}',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black87),
                    ),
                  if (state._a_selectedAirline!.cost != null)
                    Text(
                      'Cost: LKR ${state._a_selectedAirline!.cost}',
                      style: TextStyle(
                        fontSize: 14,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (state._a_selectedAirline!.usRate != null)
                    Text(
                      'USD Rate: ${state._a_selectedAirline!.usRate}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],

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
            onChanged: (v) =>
                state.setState(() => state._a_skipRouteFacility = v),
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
            const SizedBox(height: 10),
            _YesNoRadioRow(
              label: 'Gold Route',
              icon: Icons.route_rounded,
              value: state._a_goldRoute,
              accent: accent,
              onChanged: (v) => state.setState(() => state._a_goldRoute = v),
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

          // ── Passport bio data page upload (NEW) ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: PassportUploadWidget(
              key: state._a_passportUploadKey,
              initialFiles: state._a_passportFiles,
              onFilesChanged: (files) =>
                  state.setState(() => state._a_passportFiles = files),
            ),
          ),
          const SizedBox(height: 16),

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

          const SizedBox(height: 16),
          _actionButtons(
            accent: accent,
            onApplyAndAdd: state._applyAndAddAirMember,
            onSameDetails: state._addMemberWithSameDetailsAir,
          ),
          const SizedBox(height: 20),
          _addedMembersSection(
            members: state._airMembers,
            accent: accent,
            textBuilder: state._singleAirText,
            onRemove: (i) =>
                () => state.setState(() => state._airMembers.removeAt(i)),
          ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSPORT FORM (Bellagio only)
// ─────────────────────────────────────────────────────────────────────────────
class _TransportForm extends StatelessWidget {
  final _QuickReservationScreenState state;
  const _TransportForm({super.key, required this.state});

  /// Marks the drop location as "the guest will call it in", for bookings made
  /// before the guest has settled on where they are going.
  Widget _guestWillInformCheckbox(Color accent) {
    final checked = state._t_guestWillInformDrop;
    return InkWell(
      onTap: () => state._setTransportGuestWillInformDrop(!checked),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: checked ? accent : Colors.grey.shade300,
            width: checked ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              activeColor: accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: (v) =>
                  state._setTransportGuestWillInformDrop(v ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                kGuestWillInform,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: checked ? accent : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = _QuickReservationScreenState._transportColor;
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
          _sectionHeader(
            'Transport Request',
            accent,
            Icons.directions_car_rounded,
          ),
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
            onPrefixChanged: (v) => state.setState(() {
              state._selectedPrefix = v;
              state._sharedMemberId.text = '$v${state._sharedMidNumber.text}';
            }),
            isRegisteredMember: state._isRegisteredMember,
            onMemberTypeChanged: state._onMemberTypeChanged,
            onManualIdChanged: state._syncManualMemberId,
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
          // ── Pickup date & time ───────────────────────────────────────────────
          _dateField(
            context,
            'Pickup Date *',
            state._t_pickupDateCtrl,
            accent,
            () async {
              final now = DateTime.now();
              final d = await state._pickDate(
                context,
                label: 'Select Pickup Date',
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
                return 'Pickup Date is required';
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
              'Pickup Time *',
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
                label: 'Select Pickup Time',
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
                return 'Pickup Time is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // ── No of vehicles + Slik Route ───────────────────────────────────────
          // Vehicle count is chosen before Car Type on purpose: bumping it
          // grows the Car Type + Passengers pairs below to one per vehicle.
          _rowPair(
            _StepperField(
              controller: state._t_noOfVehicles,
              label: 'No of Vehicles',
              icon: Icons.local_taxi_outlined,
              accent: accent,
              onChanged: state._syncVehicleDetailsWithCount,
            ),
            _YesNoRadioRow(
              label: 'Slik Route',
              icon: Icons.alt_route_rounded,
              value: state._t_silkRoute,
              accent: accent,
              stacked: true,
              onChanged: (v) => state.setState(() => state._t_silkRoute = v),
            ),
          ),
          const SizedBox(height: 12),
          _YesNoRadioRow(
            label: 'Airport Pickup',
            icon: Icons.flight_land_rounded,
            value: state._t_airportPickup,
            accent: accent,
            onChanged: (v) => state.setState(() => state._t_airportPickup = v),
          ),
          const SizedBox(height: 12),

          // ── Passport bio data page upload ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: PassportUploadWidget(
              key: state._t_passportUploadKey,
              initialFiles: state._t_passportFiles,
              onFilesChanged: (files) =>
                  state.setState(() => state._t_passportFiles = files),
            ),
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
                  // Held by the "Guest Will Inform" placeholder — there is
                  // nothing to search for until the guest calls it in.
                  enabled: !state._t_guestWillInformDrop,
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
                const SizedBox(height: 8),
                _guestWillInformCheckbox(accent),
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
                    'Guest Mobile *',
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
          _actionButtons(
            accent: accent,
            onApplyAndAdd: state._applyAndAddTransportMember,
            onSameDetails: state._addMemberWithSameDetailsTransport,
          ),
          const SizedBox(height: 20),
          _addedMembersSection(
            members: state._transportMembers,
            accent: accent,
            textBuilder: state._singleTransportText,
            onRemove: (i) => () =>
                state.setState(() => state._transportMembers.removeAt(i)),
          ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yes / No radio row — used for Skip Route Facility, Airport Transport, Visa
// ─────────────────────────────────────────────────────────────────────────────
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
  const _StepperField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.accent,
    this.min = 1,
    this.max = 99,
    this.onChanged,
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
                    enabled: _value > min,
                    onTap: () => _change(-1, () => setState(() {})),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        controller.text,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add,
                    accent: accent,
                    enabled: _value < max,
                    onTap: () => _change(1, () => setState(() {})),
                  ),
                ],
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
  const _LabeledCard({
    required this.label,
    required this.accent,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
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