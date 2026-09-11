import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:country_picker/country_picker.dart';

import 'package:ballys_reservation_app/components/bottom_sheets/member_search-new_sheet.dart';
import 'package:ballys_reservation_app/components/guest_deatils_view_spGift.dart';
import 'package:ballys_reservation_app/components/location_search_field.dart';
import 'package:ballys_reservation_app/components/passport_upload_widget.dart';
import 'package:ballys_reservation_app/data/repositories/guest_repository.dart';
import 'package:ballys_reservation_app/data/repositories/transport_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/guest_modal.dart';
import 'package:ballys_reservation_app/models/guest_search_response.dart';
import 'package:ballys_reservation_app/providers/new_reservation_provider.dart';
import 'package:ballys_reservation_app/providers/selected_guest_provider.dart';
import 'package:ballys_reservation_app/providers/transport_provider.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:ballys_reservation_app/utils/device_id.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';

// Mirrors the Transport tab of the Quick Reservation screen as a standalone
// create screen, reached from the + action on TransportScreen.

const List<String> _kCarTypes = [
  'Normal Car',
  'SUV / Jeep',
  'Voxy',
  'Prado',
  'Benz',
  'Limousine',
  'Alphard',
];

const List<String> _kHireTypes = ['Pickup', 'Drop'];

// Placeholder saved as the drop location when the guest has not settled on one
// yet and will call it in later.
const String _kGuestWillInform = 'Guest Will Inform';

// Digit count allowed in the contact number, excluding the country code.
const int _kMinContactDigits = 9;
const int _kMaxContactDigits = 10;

const TextStyle _kInputTextStyle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w600,
  color: Colors.black,
);

const Color _kAccent = Color(0xFF2E7D32);

class TransportAddScreen extends ConsumerStatefulWidget {
  const TransportAddScreen({super.key});

  @override
  ConsumerState<TransportAddScreen> createState() => _TransportAddScreenState();
}

class _TransportAddScreenState extends ConsumerState<TransportAddScreen>
    with ConnectivityMixin {
  final _scrollCtrl = ScrollController();
  final _formKey = GlobalKey<FormState>();

  // Guest identity
  final _memberIdCtrl = TextEditingController();
  final _midNumberCtrl = TextEditingController();
  final _guestNameCtrl = TextEditingController();
  bool _guestCardVisible = false;
  bool _isNumericOnlyLocation = false;
  List<String> _prefixes = const ['BM', 'BL', 'BN'];
  String _selectedPrefix = 'BM';

  // Registered members are picked through the guest-search sheet, which fills
  // ID + name and unlocks the profile card. Non-registered ones already have a
  // DHL number issued outside the system: it can't be searched, so it is typed
  // by hand and saved into exactly the same membership-no field.
  bool _isRegisteredMember = true;

  /// Every non-registered number is issued under DHL, so the prefix is fixed
  /// instead of being picked from [_prefixes].
  static const String _nonRegisteredPrefix = 'DBH';

  // Transport fields
  final _pickupDateCtrl = TextEditingController();
  final _pickupTimeCtrl = TextEditingController();
  final _pickupLocationCtrl = TextEditingController();
  final _dropLocationCtrl = TextEditingController();
  final _noOfVehiclesCtrl = TextEditingController(text: '1');
  final _contactNumberCtrl = TextEditingController();

  Country _country = _defaultCountry();
  DateTime? _pickupDate;
  TimeOfDay? _pickupTime;
  // When set, no place is searched at all — the drop location is saved as
  // [_kGuestWillInform] and the guest phones the real one in later.
  bool _guestWillInformDrop = false;
  // One Car Type selection per vehicle — resized whenever "No of Vehicles"
  // changes (see _syncVehicleDetailsWithCount). Defaults to 'Normal Car'.
  List<String?> _carTypes = ['Normal Car'];
  // One passenger-count controller per vehicle, kept the same length as
  // _carTypes so each car's passengers are assigned individually.
  List<TextEditingController> _passengerCtrls = [
    TextEditingController(text: '1'),
  ];
  String? _hireType;
  String _pickupPlaceId = '';
  String _dropPlaceId = '';
  String _silkRoute = 'No';
  String _airportPickup = 'No';

  // Passport bio data pages (images / PDFs) for the member on screen.
  List<PassportFile> _passportFiles = [];
  Key _passportUploadKey = UniqueKey();

  final List<Map<String, dynamic>> _members = [];
  bool _isLoading = false;

  /// Keeps `_carTypes` and `_passengerCtrls` in sync with the "No of
  /// Vehicles" stepper so there is exactly one Car Type + Passengers pair
  /// per vehicle. Growing the count appends 'Normal Car' slots; shrinking
  /// trims from the end (disposing the removed controllers).
  void _syncVehicleDetailsWithCount() {
    final n = int.tryParse(_noOfVehiclesCtrl.text) ?? 1;
    if (n == _carTypes.length) return;
    setState(() {
      if (n > _carTypes.length) {
        _carTypes.addAll(
          List<String?>.filled(n - _carTypes.length, 'Normal Car'),
        );
        _passengerCtrls.addAll(
          List.generate(
            n - _passengerCtrls.length,
            (_) => TextEditingController(text: '1'),
          ),
        );
      } else {
        _carTypes.removeRange(n, _carTypes.length);
        for (final c in _passengerCtrls.sublist(n)) {
          c.dispose();
        }
        _passengerCtrls.removeRange(n, _passengerCtrls.length);
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

  @override
  void onConnectivityRestored() {}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _applyLocationPrefixes(),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    for (final c in [
      _memberIdCtrl,
      _midNumberCtrl,
      _guestNameCtrl,
      _pickupDateCtrl,
      _pickupTimeCtrl,
      _pickupLocationCtrl,
      _dropLocationCtrl,
      _noOfVehiclesCtrl,
      _contactNumberCtrl,
    ]) {
      c.dispose();
    }
    for (final c in _passengerCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _applyLocationPrefixes() async {
    final location = await StorageUtil.getCurrentLocation();
    if (location == null || !mounted) return;
    final isNumeric = location.code.split('_').first == 'BELLAGIO';
    if (isNumeric == _isNumericOnlyLocation) return;
    setState(() {
      _isNumericOnlyLocation = isNumeric;
      _prefixes = isNumeric ? [] : const ['BM', 'BL', 'BN'];
      _selectedPrefix = isNumeric ? '' : 'BM';
    });
  }

  // ── Guest search ───────────────────────────────────────────────────────────
  /// Switches between picking a registered member and typing a non-registered
  /// one. The identity fields are cleared either way so a member selected in
  /// one mode can never leak into the other.
  void _onMemberTypeChanged(bool isRegistered) {
    if (_isRegisteredMember == isRegistered) return;
    setState(() {
      _isRegisteredMember = isRegistered;
      // Going back to a searchable member restores the location's own prefix;
      // the non-registered side always shows DHL and ignores this.
      _selectedPrefix = _isNumericOnlyLocation ? '' : 'BM';
      _memberIdCtrl.clear();
      _midNumberCtrl.clear();
      _guestNameCtrl.clear();
      // The card belongs to a searched member; nothing backs it now.
      _guestCardVisible = false;
    });
    ref.read(selectedGuestProvider.notifier).clearGuest();
  }

  /// Keeps the saved membership no in sync while a non-registered number is
  /// typed. The registered flow gets this from the search sheet; here there is
  /// no search step, so DHL + the typed number is joined by hand.
  void _syncManualMemberId() {
    final numberPart = _midNumberCtrl.text.trim();
    _memberIdCtrl.text =
        numberPart.isEmpty ? '' : '$_nonRegisteredPrefix$numberPart';
  }

  void _updateMemberIdFields(String fullMemberId) {
    if (fullMemberId.isEmpty) return;
    // A DHL number was typed in by hand, so put the form back into
    // non-registered mode rather than treating it as a searchable member.
    if (fullMemberId.startsWith(_nonRegisteredPrefix)) {
      setState(() {
        _isRegisteredMember = false;
        _midNumberCtrl.text =
            fullMemberId.substring(_nonRegisteredPrefix.length);
        _memberIdCtrl.text = fullMemberId;
      });
      return;
    }
    if (_isNumericOnlyLocation) {
      setState(() {
        _midNumberCtrl.text = fullMemberId;
        _memberIdCtrl.text = fullMemberId;
      });
      return;
    }
    String prefix = 'BM';
    String numberPart = fullMemberId;
    for (final p in const ['BM', 'BL', 'BN']) {
      if (fullMemberId.startsWith(p)) {
        prefix = p;
        numberPart = fullMemberId.substring(2);
        break;
      }
    }
    setState(() {
      _selectedPrefix = prefix;
      _midNumberCtrl.text = numberPart;
      _memberIdCtrl.text = fullMemberId;
    });
  }

  Future<void> _openGuestSearch({required int iid}) async {
    final repo = GuestRepository(ApiService(SecureStorage.instance));
    final term = iid == 8002 ? _memberIdCtrl.text : _guestNameCtrl.text;
    if (term.length < 3) {
      _showSearchSheet([], term, iid);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final guests = await repo.searchGuest(iid, term);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSearchSheet(guests, term, iid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _showSearchSheet(
    List<GuestSearchResponse> guests,
    String term,
    int iid,
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
            final repo = GuestRepository(
              ApiService(SecureStorage.instance),
            );
            final r = await repo.searchGuest(newIid, newTerm);
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            _showSearchSheet(r, newTerm, newIid);
          } catch (_) {}
        },
      ),
    );
    ref.listenManual(newReservationProvider, (_, next) {
      if (next.bmNumber != null) {
        _updateMemberIdFields(next.bmNumber!);
        _guestNameCtrl.text = next.guestName ?? '';
        _fetchAndSetGuest(mid: next.bmNumber!, name: next.guestName ?? '');
        ref.read(newReservationProvider.notifier).resetState();
      }
    });
  }

  Future<void> _fetchAndSetGuest({
    required String mid,
    required String name,
  }) async {
    try {
      final repo = GuestRepository(ApiService(SecureStorage.instance));
      final guests = await repo.searchGuest(9021, mid);
      if (!mounted) return;
      if (guests.isNotEmpty) {
        final g = guests.first;
        ref
            .read(selectedGuestProvider.notifier)
            .setSelectedGuest(
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
      } else {
        _setGuest(mid: mid, name: name);
      }
    } catch (_) {
      if (!mounted) return;
      _setGuest(mid: mid, name: name);
    }
    if (mounted) setState(() => _guestCardVisible = true);
  }

  void _setGuest({required String mid, required String name}) {
    ref
        .read(selectedGuestProvider.notifier)
        .setSelectedGuest(
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

  Future<void> _navigateToProfile() async {
    final mid = _memberIdCtrl.text;
    if (mid.isEmpty) return;
    final currentGuest = ref.read(selectedGuestProvider);
    if (currentGuest != null && currentGuest.mid == mid) {
      if (mounted) context.push('/home/profile');
      return;
    }
    await _fetchAndSetGuest(mid: mid, name: _guestNameCtrl.text);
    if (mounted) context.push('/home/profile');
  }

  // ── Pickers ────────────────────────────────────────────────────────────────
  void _showCountryPicker() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (country) => setState(() => _country = country),
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

  Future<void> _pickPickupDate() async {
    final now = DateTime.now();
    DateTime picked = _pickupDate ?? now;
    DateTime? result;
    await _showPickerSheet(
      label: 'Select Pickup Date',
      picker: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: picked,
        minimumDate: DateTime(now.year, now.month, now.day),
        onDateTimeChanged: (d) => picked = d,
      ),
      onConfirm: () {
        result = picked;
        return true;
      },
    );
    if (result != null && mounted) {
      setState(() {
        _pickupDate = result;
        _pickupDateCtrl.text = _fmtDate(result!);
      });
    }
  }

  Future<void> _pickPickupTime() async {
    final now = DateTime.now();
    // Only restrict past times when pickup is for today; future dates allow
    // any time of day.
    final date = _pickupDate;
    final isToday = date == null ||
        (date.year == now.year &&
            date.month == now.month &&
            date.day == now.day);
    final minInMinutes = isToday ? now.hour * 60 + now.minute : null;

    DateTime picked = DateTime(
      now.year,
      now.month,
      now.day,
      _pickupTime?.hour ?? now.hour,
      _pickupTime?.minute ?? now.minute,
    );
    // Cupertino's time-mode picker ignores minimumDate, so clamp the initial
    // value forward and enforce the minimum again on Confirm.
    if (minInMinutes != null &&
        picked.hour * 60 + picked.minute < minInMinutes) {
      picked = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    }
    TimeOfDay? result;
    await _showPickerSheet(
      label: 'Select Pickup Time',
      picker: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: picked,
        use24hFormat: false,
        onDateTimeChanged: (d) => picked = d,
      ),
      onConfirm: () {
        if (minInMinutes != null &&
            picked.hour * 60 + picked.minute < minInMinutes) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pickup time cannot be in the past')),
          );
          return false;
        }
        result = TimeOfDay(hour: picked.hour, minute: picked.minute);
        return true;
      },
    );
    if (result != null && mounted) {
      setState(() {
        _pickupTime = result;
        _pickupTimeCtrl.text = _fmtTime(result!);
      });
    }
  }

  Future<void> _showPickerSheet({
    required String label,
    required Widget picker,
    // Return true to accept and close the sheet, false to keep it open
    // (e.g. when the selected value fails validation).
    required bool Function() onConfirm,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
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
          SizedBox(height: 220, child: picker),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
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
                    if (onConfirm()) Navigator.pop(ctx);
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
  }

  /// Swaps the drop location between a searched place and the "Guest Will
  /// Inform" placeholder. Any place already picked is dropped when the
  /// placeholder is turned on so a stale place id can never be saved with it.
  void _setGuestWillInformDrop(bool value) {
    setState(() {
      _guestWillInformDrop = value;
      _dropPlaceId = '';
      _dropLocationCtrl.text = value ? _kGuestWillInform : '';
    });
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(TimeOfDay t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${h12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }

  // ── Member list ────────────────────────────────────────────────────────────
  /// Captures the current form as a single transport entry. Per-vehicle Car
  /// Type + Passengers are carried as a `vehicleDetails` list (one map per
  /// vehicle) rather than a single scalar car type/passenger count.
  Map<String, dynamic> _captureCurrentMember() {
    return {
      'guestName': _guestNameCtrl.text,
      'memberId': _memberIdCtrl.text,
      'pickupDate': _pickupDateCtrl.text,
      'pickupTime': _pickupTimeCtrl.text,
      'hireType': _hireType ?? '',
      'pickupLocation': _pickupLocationCtrl.text,
      'dropLocation': _dropLocationCtrl.text,
      'vehicleDetails': List.generate(_carTypes.length, (i) {
        return {
          'carType': _carTypes[i] ?? '',
          'noOfPassengers': _passengerCtrls[i].text,
        };
      }),
      'contactNumber': _contactNumberCtrl.text.trim().isEmpty
          ? ''
          : '+${_country.phoneCode}${_contactNumberCtrl.text.trim()}',
      'silkRoute': _silkRoute,
      'airportPickup': _airportPickup,
      'passportFiles': _passportFiles.map((f) => f.fileName).join(', '),
      'passportFileObjects': List<PassportFile>.from(_passportFiles),
      'pickupDateObj': _pickupDate,
      'pickupTimeObj': _pickupTime,
      'pickupPlaceId': _pickupPlaceId,
      'dropPlaceId': _dropPlaceId,
    };
  }

  void _resetFields() {
    _pickupDateCtrl.clear();
    _pickupTimeCtrl.clear();
    _pickupLocationCtrl.clear();
    _dropLocationCtrl.clear();
    _noOfVehiclesCtrl.text = '1';
    _contactNumberCtrl.clear();
    _country = _defaultCountry();
    _pickupDate = null;
    _pickupTime = null;
    _guestWillInformDrop = false;
    _carTypes = ['Normal Car'];
    for (final c in _passengerCtrls) {
      c.dispose();
    }
    _passengerCtrls = [TextEditingController(text: '1')];
    _hireType = null;
    _pickupPlaceId = '';
    _dropPlaceId = '';
    _silkRoute = 'No';
    _airportPickup = 'No';
    _passportFiles = [];
    _passportUploadKey = UniqueKey();
  }

  void _clearGuestFields() {
    _memberIdCtrl.clear();
    _midNumberCtrl.clear();
    _guestNameCtrl.clear();
    _guestCardVisible = false;
  }

  bool _requireGuest() {
    if (_guestNameCtrl.text.trim().isEmpty &&
        _memberIdCtrl.text.trim().isEmpty) {
      _showErrorSnack('Please enter a guest name or membership number');
      return false;
    }
    return true;
  }

  /// Names of the required fields that are still empty/invalid, in the same
  /// order they appear on the page.
  List<String> _missingRequiredFields() {
    final missing = <String>[];
    void check(bool isMissing, String label) {
      if (isMissing) missing.add(label);
    }

    check(_midNumberCtrl.text.trim().isEmpty, 'Membership No');
    check(_pickupDateCtrl.text.trim().isEmpty, 'Pickup Date');
    check(_pickupTimeCtrl.text.trim().isEmpty, 'Pickup Time');
    check(
      _carTypes.any((c) => c == null || c.trim().isEmpty),
      'Car Type',
    );
    check((_hireType ?? '').trim().isEmpty, 'Hire Type');
    check(_pickupLocationCtrl.text.trim().isEmpty, 'Pickup Location');
    check(_dropLocationCtrl.text.trim().isEmpty, 'Drop Location');

    final digits = _contactNumberCtrl.text.trim();
    if (digits.isEmpty) {
      missing.add('Guest Mobile');
    } else if (digits.length < _kMinContactDigits ||
        digits.length > _kMaxContactDigits) {
      missing.add(
        'Guest Mobile ($_kMinContactDigits-$_kMaxContactDigits digits)',
      );
    }
    return missing;
  }

  /// Runs the form validators and, when something fails, names the offending
  /// fields in a bottom snack bar — the inline errors alone are easy to miss
  /// because the failing field is usually scrolled off-screen.
  bool _validateForm() {
    if (_formKey.currentState?.validate() ?? false) return true;
    final missing = _missingRequiredFields();
    _showErrorSnack(
      missing.isEmpty
          ? 'Please fill all required fields'
          : missing.length == 1
              ? '${missing.first} is required'
              : 'Required: ${missing.join(', ')}',
    );
    return false;
  }

  void _applyAndAddMember() {
    if (!_requireGuest()) return;
    if (!_validateForm()) return;
    setState(() {
      _members.add(_captureCurrentMember());
      _clearGuestFields();
      _resetFields();
    });
    _afterAdd();
  }

  void _addMemberWithSameDetails() {
    if (!_requireGuest()) return;
    if (!_validateForm()) return;
    setState(() {
      _members.add(_captureCurrentMember());
      _clearGuestFields();
      // Passport pages belong to the individual guest, not the shared trip
      // details, so they are cleared for the next member.
      _passportFiles = [];
      _passportUploadKey = UniqueKey();
    });
    _afterAdd();
  }

  void _afterAdd() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Member added (${_members.length} total)'),
        backgroundColor: _kAccent,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────
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

  Map<String, dynamic> _memberToDetail(Map<String, dynamic> m) {
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
          .map(
            (v) => {
              'car_type': v['carType'],
              'no_of_passengers':
                  int.tryParse(v['noOfPassengers'] as String? ?? '1') ?? 1,
            },
          )
          .toList(),
      'contact_number': m['contactNumber'],
      'silk_route': (m['silkRoute'] as String?) == 'Yes' ? 1 : 0,
      'airport_pickup': (m['airportPickup'] as String?) == 'Yes' ? 1 : 0,
    };
  }

  /// Flattens every member's uploaded passport files into the base64 payload
  /// the API expects, tagged with the member they belong to. Files that can no
  /// longer be read (moved/deleted since picking) are skipped rather than
  /// failing the whole save.
  List<Map<String, dynamic>> _buildPassportImages(
    List<Map<String, dynamic>> members,
  ) {
    final images = <Map<String, dynamic>>[];
    for (final m in members) {
      final memberId = m['memberId'] as String? ?? '';
      final files = m['passportFileObjects'] as List<PassportFile>? ?? [];
      for (final f in files) {
        try {
          images.add({
            'mid': memberId,
            'FileName': f.fileName,
            'IsPdf': f.isPdf,
            'Base64Data': base64Encode(File(f.path).readAsBytesSync()),
          });
        } catch (_) {}
      }
    }
    return images;
  }

  Future<void> _save() async {
    final hasCurrentGuest =
        _guestNameCtrl.text.trim().isNotEmpty ||
        _memberIdCtrl.text.trim().isNotEmpty;

    // Only validate the on-screen form when it still holds a member that
    // will be submitted — after "Apply & Add" it is cleared on purpose.
    if (hasCurrentGuest && !_validateForm()) {
      return;
    }

    final allMembers = <Map<String, dynamic>>[
      ..._members,
      if (hasCurrentGuest) _captureCurrentMember(),
    ];

    if (allMembers.isEmpty) {
      _showErrorSnack('Please add at least one guest before saving');
      return;
    }

    final primary = allMembers.first;
    final salesCode = await StorageUtil.getSalesCode();
    final userName = await StorageUtil.getUName();
    final deviceId = await DeviceId.get();
    final phoneNumber = await StorageUtil.getMobileNumber();

    final body = <String, dynamic>{
      'master_id': DateTime.now().millisecondsSinceEpoch.toString(),
      'MID': primary['memberId'],
      'guest_name': primary['guestName'],
      'pickup_date': _pickupIso(primary),
      'contact_number': phoneNumber,
      'reservation_status': 'Requested',
      'sales_code': salesCode,
      'user_name': userName,
      'device_id': deviceId,
      'transport_details': allMembers.map(_memberToDetail).toList(),
      'passport_images': _buildPassportImages(allMembers),
    };

    setState(() => _isLoading = true);
    try {
      _logLong('Saving transport reservation', body);
      final repo = TransportRepository(
        ApiService(SecureStorage.instance),
      );
      final result = await repo.insertTransport(body);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result.success) {
        await ref.read(transportProvider.notifier).getTransportData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.message ??
                        'Transport reservation saved successfully',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/reservationMain/transport');
        }
      } else {
        _showErrorSnack(
          result.message ?? 'Failed to save transport reservation',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnack(e.toString());
    }
  }

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

  void _logLong(String label, Map<String, dynamic> payload) {
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

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _memberSummary(Map<String, dynamic> m) {
    String v(String key) {
      final s = m[key] as String? ?? '';
      return s.isEmpty ? 'NA' : s;
    }

    final vehicles = (m['vehicleDetails'] as List?)?.cast<Map>() ?? const [];
    final buf = StringBuffer()
      ..writeln('Pickup Date        : ${v('pickupDate')}')
      ..writeln('Pickup Time        : ${v('pickupTime')}');
    for (int i = 0; i < vehicles.length; i++) {
      final prefix = vehicles.length > 1 ? 'Vehicle ${i + 1} ' : '';
      final carTypeLabel = '${prefix}Car Type'.padRight(19);
      final passengersLabel = '${prefix}Passengers'.padRight(19);
      buf
        ..writeln('$carTypeLabel: ${vehicles[i]['carType']}')
        ..writeln('$passengersLabel: ${vehicles[i]['noOfPassengers']}');
    }
    buf
      ..writeln('Hire Type          : ${v('hireType')}')
      ..writeln('Pickup Location    : ${v('pickupLocation')}')
      ..writeln('Drop Location      : ${v('dropLocation')}')
      ..writeln('No of Vehicles     : ${vehicles.length}')
      ..writeln('Contact Number     : ${v('contactNumber')}')
      ..writeln('Slik Route         : ${v('silkRoute')}')
      ..write('Airport Pickup     : ${v('airportPickup')}');
    final passports = m['passportFiles'] as String? ?? '';
    if (passports.isNotEmpty) {
      buf.write('\nPassport Files     : $passports');
    }
    return buf.toString();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Add Transport',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/reservationMain/transport');
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _save,
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.save_alt),
        label: const Text(
          'Confirm Reservation',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            // A lazy ListView only builds the rows near the viewport, and
            // Form.validate() skips fields that are not mounted — so saving
            // from the top of the page silently bypassed every validator
            // further down. A Column keeps all fields alive at all times.
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // _sectionHeader('Transport Request'),
                _guestIdentityRow(),
                const SizedBox(height: 12),
                if (_guestCardVisible &&
                    _memberIdCtrl.text.isNotEmpty &&
                    _guestNameCtrl.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GuestDisplayCardSpecialGiftview(
                      memberIdText: _memberIdCtrl.text,
                      memberNameText: _guestNameCtrl.text,
                      showCard: true,
                      showLastVisitDate: true,
                    ),
                  ),

                // Pickup date & time
                TextFormField(
                  controller: _pickupDateCtrl,
                  readOnly: true,
                  style: _kInputTextStyle,
                  decoration:
                      _fieldDeco(
                        'Pickup Date *',
                        icon: Icons.calendar_today_rounded,
                      ).copyWith(
                        suffixIcon: const Icon(
                          Icons.arrow_drop_down,
                          color: _kAccent,
                        ),
                      ),
                  onTap: _pickPickupDate,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Pickup Date is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pickupTimeCtrl,
                  readOnly: true,
                  style: _kInputTextStyle,
                  decoration:
                      _fieldDeco(
                        'Pickup Time *',
                        icon: Icons.access_time_rounded,
                      ).copyWith(
                        suffixIcon: const Icon(
                          Icons.arrow_drop_down,
                          color: _kAccent,
                        ),
                      ),
                  onTap: _pickPickupTime,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Pickup Time is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // No of vehicles + Slik Route. Vehicle count is chosen before
                // Car Type on purpose: bumping it grows the Car Type +
                // Passengers pairs below to one per vehicle.
                Row(
                  children: [
                    Expanded(
                      child: _StepperField(
                        controller: _noOfVehiclesCtrl,
                        label: 'No of Vehicles',
                        icon: Icons.local_taxi_outlined,
                        onChanged: _syncVehicleDetailsWithCount,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _YesNoRadioRow(
                        label: 'Slik Route',
                        icon: Icons.alt_route_rounded,
                        value: _silkRoute,
                        stacked: true,
                        onChanged: (v) => setState(() => _silkRoute = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _YesNoRadioRow(
                  label: 'Airport Pickup',
                  icon: Icons.flight_land_rounded,
                  value: _airportPickup,
                  onChanged: (v) => setState(() => _airportPickup = v),
                ),
                const SizedBox(height: 12),

                // Passport bio data pages — images or PDFs.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: PassportUploadWidget(
                    key: _passportUploadKey,
                    initialFiles: _passportFiles,
                    onFilesChanged: (files) =>
                        setState(() => _passportFiles = files),
                  ),
                ),
                const SizedBox(height: 12),

                // Car type + passengers, one row per vehicle
                for (int i = 0; i < _carTypes.length; i++) ...[
                  if (_carTypes.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Vehicle ${i + 1}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _kAccent,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _carTypes[i],
                          style: _kInputTextStyle,
                          isExpanded: true,
                          decoration: _fieldDeco(
                            'Car Type *',
                            //icon: Icons.directions_car_filled_outlined,
                          ),
                          items: _kCarTypes
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _carTypes[i] = v),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Car Type is required';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StepperField(
                          controller: _passengerCtrls[i],
                          label: 'Passengers',
                          icon: Icons.group_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                DropdownButtonFormField<String>(
                  initialValue: _hireType,
                  style: _kInputTextStyle,
                  isExpanded: true,
                  decoration: _fieldDeco(
                    'Hire Type *',
                    icon: Icons.assignment_outlined,
                  ),
                  items: _kHireTypes
                      .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                      .toList(),
                  onChanged: (v) => setState(() => _hireType = v),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Hire Type is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Locations
                LocationSearchField(
                  controller: _pickupLocationCtrl,
                  textStyle: _kInputTextStyle,
                  accent: _kAccent,
                  sheetTitle: 'Search Pickup Location',
                  decoration: _fieldDeco(
                    'Pickup Location *',
                    icon: Icons.my_location_rounded,
                  ),
                  onSelected: (description, placeId) => setState(() {
                    _pickupLocationCtrl.text = description;
                    _pickupPlaceId = placeId;
                  }),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Pickup Location is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                    
                _guestWillInformCheckbox(),
                      const SizedBox(height: 8),
                LocationSearchField(
                  controller: _dropLocationCtrl,
                  textStyle: _kInputTextStyle,
                  accent: _kAccent,
                  // Held by the "Guest Will Inform" placeholder — there is
                  // nothing to search for until the guest calls it in.
                  enabled: !_guestWillInformDrop,
                  sheetTitle: 'Search Drop Location',
                  decoration: _fieldDeco(
                    'Drop Location *',
                    icon: Icons.place_rounded,
                  ),
                  onSelected: (description, placeId) => setState(() {
                    _dropLocationCtrl.text = description;
                    _dropPlaceId = placeId;
                  }),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Drop Location is required';
                    }
                    return null;
                  },
                ),
      
                const SizedBox(height: 12),

                // Contact number with country code
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: _showCountryPicker,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 58,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _country.flagEmoji,
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '+${_country.phoneCode}',
                              style: _kInputTextStyle,
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: _kAccent,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _contactNumberCtrl,
                        style: _kInputTextStyle,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                            _kMaxContactDigits,
                          ),
                        ],
                        decoration: _fieldDeco(
                          'Guest Mobile *',
                          icon: Icons.phone_rounded,
                        ),
                        validator: (value) {
                          final digits = (value ?? '').trim();
                          if (digits.isEmpty) {
                            return 'Contact Number is required';
                          }
                          if (digits.length < _kMinContactDigits) {
                            return 'Enter at least $_kMinContactDigits digits';
                          }
                          if (digits.length > _kMaxContactDigits) {
                            return 'Enter no more than $_kMaxContactDigits digits';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _actionButtons(),
                const SizedBox(height: 20),
                _addedMembersSection(),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: const Color.fromARGB(135, 117, 115, 115),
                child: const Center(
                  child: RefreshProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_kAccent),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String label, {IconData? icon}) {
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
      prefixIcon: icon != null ? Icon(icon, size: 20, color: _kAccent) : null,
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
        borderSide: const BorderSide(color: _kAccent, width: 1.8),
      ),
    );
  }

  /// Marks the drop location as "the guest will call it in", for bookings made
  /// before the guest has settled on where they are going.
  Widget _guestWillInformCheckbox() {
    return InkWell(
      onTap: () => _setGuestWillInformDrop(!_guestWillInformDrop),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _guestWillInformDrop ? _kAccent : Colors.grey.shade300,
            width: _guestWillInformDrop ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: _guestWillInformDrop,
              activeColor: _kAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => _setGuestWillInformDrop(v ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _kGuestWillInform,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: _guestWillInformDrop ? _kAccent : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_rounded, color: _kAccent, size: 20),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: _kAccent,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }

  /// One tappable radio + label of the registered / non-registered pair.
  Widget _memberTypeOption({
    required String label,
    required bool isRegistered,
  }) {
    return InkWell(
      onTap: () => _onMemberTypeChanged(isRegistered),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<bool>(
            value: isRegistered,
            groupValue: _isRegisteredMember,
            activeColor: _kAccent,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => _onMemberTypeChanged(v!),
          ),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: _kInputTextStyle)),
        ],
      ),
    );
  }

  Widget _guestIdentityRow() {
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
              ),
            ),
            Expanded(
              child: _memberTypeOption(
                label: 'DB Holder',
                isRegistered: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _midNumberCtrl,
                style: _kInputTextStyle,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Membership No is required';
                  }
                  return null;
                },
                decoration: _fieldDeco('Membership No *').copyWith(
                  // Non-registered numbers are always issued under DHL, so the
                  // prefix is fixed rather than chosen.
                  prefixIcon: !_isRegisteredMember
                      ? const Padding(
                          padding: EdgeInsets.only(left: 12, right: 4),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              _nonRegisteredPrefix,
                              style: _kInputTextStyle,
                            ),
                          ),
                        )
                      : _isNumericOnlyLocation
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(left: 12, right: 4),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedPrefix,
                              style: _kInputTextStyle,
                              items: _prefixes
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p, style: _kInputTextStyle),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _selectedPrefix = v;
                                  _memberIdCtrl.text =
                                      '$v${_midNumberCtrl.text}';
                                });
                              },
                            ),
                          ),
                        ),
                  // A non-registered number exists only outside the system —
                  // there is nothing to search it against.
                  suffixIcon: !_isRegisteredMember
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.search, color: _kAccent),
                          onPressed: () {
                            _memberIdCtrl.text = _isNumericOnlyLocation
                                ? _midNumberCtrl.text
                                : '$_selectedPrefix${_midNumberCtrl.text}';
                            _openGuestSearch(iid: 8002);
                          },
                        ),
                ),
                onChanged: (value) {
                  if (!_isRegisteredMember) {
                    // Typed by hand, so this is the only place the saved
                    // membership no gets set.
                    _syncManualMemberId();
                    return;
                  }
                  _guestNameCtrl.clear();
                  _memberIdCtrl.text = _isNumericOnlyLocation
                      ? value
                      : '$_selectedPrefix$value';
                },
              ),
            ),
            // Non-registered members have no profile to open.
            if (_isRegisteredMember) ...[
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _guestCardVisible ? _navigateToProfile : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _guestCardVisible
                      ? Colors.black
                      : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 14,
                  ),
                ),
                child: const Icon(Icons.person_search, size: 25),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _guestNameCtrl,
          style: _kInputTextStyle,
          textCapitalization: TextCapitalization.words,
          decoration: _fieldDeco('Guest Name', icon: Icons.person_outline)
              .copyWith(
                suffixIcon: !_isRegisteredMember
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.search, color: _kAccent),
                        onPressed: () => _openGuestSearch(iid: 8003),
                      ),
              ),
          onChanged: (_) {
            // The name is typed alongside the number for a non-registered
            // member; clearing the number here would wipe what was just
            // entered.
            if (!_isRegisteredMember) return;
            _midNumberCtrl.clear();
          },
        ),
      ],
    );
  }

  Widget _actionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _applyAndAddMember,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
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
            onPressed: _addMemberWithSameDetails,
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAccent,
              side: const BorderSide(color: _kAccent, width: 1.8),
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

  Widget _addedMembersSection() {
    if (_members.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: _kAccent, size: 20),
              const SizedBox(width: 10),
              Text(
                'Added Members (${_members.length})',
                style: const TextStyle(
                  color: _kAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        ..._members.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _kAccent.withValues(alpha: 0.45),
                width: 1.5,
              ),
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
                    color: _kAccent.withValues(alpha: 0.07),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: _kAccent.withValues(alpha: 0.18),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: _kAccent,
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
                              style: const TextStyle(
                                color: _kAccent,
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
                        onPressed: () => setState(() => _members.removeAt(i)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _memberSummary(m),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── Yes / No radio card ──────────────────────────────────────────────────────
class _YesNoRadioRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value; // 'Yes' or 'No'
  final ValueChanged<String> onChanged;

  /// Label on top, Yes/No underneath — mirrors [_StepperField]'s two-line card
  /// so the two sit level when paired half-width in a row. Full-width cards
  /// keep the default single-line layout.
  final bool stacked;

  const _YesNoRadioRow({
    required this.label,
    required this.icon,
    required this.value,
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
            activeColor: _kAccent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => onChanged(v!),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? _kAccent : Colors.black87,
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
                    Icon(icon, size: 18, color: _kAccent),
                    const SizedBox(width: 6),
                    Expanded(
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
                  height: 32,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [_option('Yes'), _option('No')],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Icon(icon, size: 18, color: _kAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
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

// ── Stepper field ────────────────────────────────────────────────────────────
class _StepperField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  /// Called after the controller's value changes, in addition to this
  /// widget's own rebuild — lets a parent react (e.g. resize a list that
  /// should track the count).
  final VoidCallback? onChanged;
  const _StepperField({
    required this.controller,
    required this.label,
    required this.icon,
    this.onChanged,
  });

  @override
  State<_StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<_StepperField> {
  static const int _min = 1;
  static const int _max = 99;

  int get _value => int.tryParse(widget.controller.text) ?? _min;

  void _change(int delta) {
    setState(() {
      widget.controller.text = (_value + delta).clamp(_min, _max).toString();
    });
    widget.onChanged?.call();
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
              Icon(widget.icon, size: 18, color: _kAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
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
                enabled: _value > _min,
                onTap: () => _change(-1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    widget.controller.text,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _kAccent,
                    ),
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                enabled: _value < _max,
                onTap: () => _change(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: enabled
              ? _kAccent.withValues(alpha: 0.12)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: enabled ? _kAccent : Colors.grey),
      ),
    );
  }
}
