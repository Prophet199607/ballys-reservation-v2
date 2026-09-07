import 'dart:convert';
import 'dart:io';
import 'package:ballys_reservation_app/components/bottom_sheets/member_search-new_sheet.dart';
import 'package:ballys_reservation_app/components/flight_card_ballys.dart';
import 'package:ballys_reservation_app/components/guest_deatils_view_spGift.dart';
import 'package:ballys_reservation_app/components/hotel_selection_ballys.dart';
import 'package:ballys_reservation_app/components/package_amount_field_ballys.dart';
import 'package:ballys_reservation_app/components/passport_upload_widget_ballys.dart';
import 'package:ballys_reservation_app/core/constants.dart';
import 'package:ballys_reservation_app/data/repositories/authorization_level_repository.dart';
import 'package:ballys_reservation_app/data/repositories/contact_person_repository.dart';
import 'package:ballys_reservation_app/data/repositories/guest_repository.dart';
import 'package:ballys_reservation_app/data/repositories/hotel_repository.dart';
import 'package:ballys_reservation_app/data/repositories/reservation_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/authorization_level.dart';
import 'package:ballys_reservation_app/models/guest_modal.dart';
import 'package:ballys_reservation_app/models/guest_reservation_entryBallys.dart';
import 'package:ballys_reservation_app/models/guest_search_response.dart';
import 'package:ballys_reservation_app/models/reervationBallys.dart';
import 'package:ballys_reservation_app/models/reservation/flight_bookng_ballys.dart';
import 'package:ballys_reservation_app/models/reservation/assigned_guest.dart';
import 'package:ballys_reservation_app/models/reservation/hotel_desc_ballys.dart';
import 'package:ballys_reservation_app/models/reservation/new_reservation_ballys.dart';
// import 'package:ballys_reservation_app/models/reservation/reservation_passport_image.dart';
import 'package:ballys_reservation_app/models/reservation/reservation_passport_image_ballys.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/providers/hotel_catalog_provider.dart';
import 'package:ballys_reservation_app/providers/member_search_provider.dart';
// import 'package:ballys_reservation_app/providers/new_reservation_provider.dart';

import 'package:ballys_reservation_app/components/passport_upload_widget.dart';
import 'package:ballys_reservation_app/providers/new_reservation_provider_ballys.dart';
import 'package:ballys_reservation_app/providers/reservation_provider_ballys.dart';
import 'package:ballys_reservation_app/providers/selectedReservationforBallys_provider.dart';
// import 'package:ballys_reservation_app/providers/selected_flight_provider.dart';
import 'package:ballys_reservation_app/providers/selected_flight_provider_ballys.dart';
 import 'package:ballys_reservation_app/providers/selected_guest_provider.dart';
import 'package:ballys_reservation_app/providers/selected_hotel_provider_ballys.dart';
import 'package:ballys_reservation_app/providers/selected_passport_provider_ballys.dart';
// import 'package:ballys_reservation_app/providers/selected_passport_provider.dart';
// import 'package:ballys_reservation_app/providers/selected_reservation_provider.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';

class NewReservationBallysScreen extends ConsumerStatefulWidget {
  const NewReservationBallysScreen({super.key});

  @override
  ConsumerState<NewReservationBallysScreen> createState() =>
      _NewReservationBallysScreenState();
}

class _NewReservationBallysScreenState extends ConsumerState<NewReservationBallysScreen>
    with ConnectivityMixin {
  final TextEditingController _reservationNoController =
      TextEditingController();
  final TextEditingController _memberIdController = TextEditingController();
  final TextEditingController _memberNameController = TextEditingController();

  final ValueNotifier<String> hotelRoomNotifier = ValueNotifier<String>("");
  final ValueNotifier<String> airTicketsNotifier = ValueNotifier<String>("");

  bool _isLoading = false;
  String _selectedPrefix = "BM";
  final TextEditingController _memberIdNumberController =
      TextEditingController();

  final TextEditingController _noOfNightsController = TextEditingController();
  final TextEditingController _arrivalDateController = TextEditingController();
  final TextEditingController _departureDateController =
      TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _reservationnewnumberController =
      TextEditingController();
        final TextEditingController _packageAmountController =
      TextEditingController();
  // Whether family members travel with the member currently in the form.
  bool _hasFamilyMembers = false;

  // Ticked when the member is on a shared package: an empty package amount is
  // accepted on save, and the tick itself is sent as a true/false of its own —
  // the amount stays editable, since a shared package can still carry one.
  bool _sharedPackage = false;

  DateTime? _arrivalDate;
  DateTime? _departureDate;
  String _airTicketRequisition = "No";
  bool _isEditMode = false;
  final _formKey = GlobalKey<FormState>();
  bool hasError = false;
  String? _hotelError;
  String? _airTicketError;
  bool _isNumericOnlyLocation = false;
  bool _isGuestLoading = false;
  List<String> _prefixes = ["BM", "BL", "BN"];

  // ── Multi-guest support ───────────────────────────────────────────────
  // Guests already "added" to this single reservation. They all share one
  // reservationNo but each carries its own hotel(s) / flight(s) / dates.
  final List<GuestReservationEntryBallys> _guestEntries = [];
  // Set when the user double-taps an added guest card to edit it; tells us
  // which index in _guestEntries to replace (instead of appending) on the
  // next Add Guest / Add New Guest tap.
  int? _editingGuestIndex;

  // ── Reservation-level payment & contact ───────────────────────────────
  // Both used to be picked inside the hotel sheet / the air ticket screen and
  // repeated on every room and every ticket. They describe the reservation
  // rather than a single booking, so they are picked once on this screen and
  // sent once at the top of the request body.
  /// Null until the user picks one — "Payment By" is mandatory and has no
  /// default, so the dropdown comes up empty and the save is blocked while it
  /// stays that way.
  String? _paymentBy;
  String? _paymentByError;
  String? _selectedContactPerson;
  List<String> _contactPersons = [];

  /// Bellagio (bty.world) swaps the "Payment By" options to the Beyond Borders
  /// wording and has no Hamoos contact person to pick.
  bool _isBellagio = false;

  // ── Approval routing ──────────────────────────────────────────────────
  // Who this reservation is being sent to for approval, from
  // `GetAuthorizationLevels`. Empty until the fetch lands; a failed fetch just
  // leaves the dropdown disabled rather than blocking the form.
  List<AuthorizationLevel> _authorizationLevels = [];
  AuthorizationLevel? _selectedAuthorization;
  bool _isLoadingAuthorizationLevels = false;

  // Extra members travelling on the SAME package as the member currently in the
  // form: they share its hotels, air tickets and dates, so they never add rooms
  // or tickets of their own — only who they are and their family members.
  final List<_ExtraMemberRow> _extraMembers = [];

  @override
  void initState() {
    super.initState();
    _getHotels();
    _loadLocationPrefix();
    _loadAuthorizationLevels();
    _loadBrand();
    _loadContactPersons();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(FocusNode());
      final selectedReservation = ref.watch(selectedReservationBallysProvider);
      if (selectedReservation != null) {
        _isEditMode = true;
        _populateFields(selectedReservation);
        _loadGuestEntriesForEdit(selectedReservation);
      }
    });
  }

  Future<void> _loadLocationPrefix() async {
    final location = await StorageUtil.getCurrentLocation();
    if (location != null) {
      final code = location.code.split('_').first; // "BELLAGIO"
      final isNumeric = code == "BELLAGIO";
      setState(() {
        _isNumericOnlyLocation = isNumeric;
        _prefixes = isNumeric ? [] : ["BM", "BL", "BN"];
        _selectedPrefix = isNumeric ? "" : "BM";
      });
    }
  }

  Future<void> _loadBrand() async {
    final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
    if (!mounted) return;
    setState(() {
      _isBellagio = apiUrl.contains('bty.world');
      // The two brands offer different values, so anything picked before the
      // brand landed is dropped rather than fed to a dropdown that no longer
      // offers it.
      final offered = _paymentByItems().map((i) => i.value).toSet();
      if (_paymentBy != null && !offered.contains(_paymentBy)) {
        _paymentBy = null;
      }
    });
  }

  /// The "Payment By" options. Bellagio bills through Beyond Borders, so it
  /// gets its own wording — the values are the ones the back office already
  /// stores, trailing space included.
  List<DropdownMenuItem<String>> _paymentByItems() {
    return _isBellagio
        ? const [
            DropdownMenuItem(value: 'By Guest', child: Text('By Guest')),
            DropdownMenuItem(
                value: 'By Beyond Borders', child: Text('By Beyond Borders')),
            DropdownMenuItem(
                value: 'By Guest & Beyond',
                child: Text('By Guest & Beyond Borders')),
          ]
        : const [
            DropdownMenuItem(value: 'By Guest', child: Text('By Guest')),
            DropdownMenuItem(value: 'By Hamoos ', child: Text('By Hamoos')),
            DropdownMenuItem(
                value: 'By Guest & Hamoos', child: Text('By Guest & Hamoos')),
          ];
  }

  /// Fills the Hamoos contact person dropdown. A failed fetch leaves it empty
  /// rather than blocking the form — the field is optional.
  Future<void> _loadContactPersons() async {
    try {
      final repo = ContactPersonRepository(ApiService(SecureStorage.instance));
      final persons = await repo.getContactPersons();
      if (mounted) setState(() => _contactPersons = persons);
    } catch (_) {
      // Leave the dropdown empty.
    }
  }

  @override
  void dispose() {
    _reservationNoController.dispose();
    _memberIdController.dispose();
    _memberNameController.dispose();
    _memberIdNumberController.dispose();
    _noOfNightsController.dispose();
    _arrivalDateController.dispose();
    _departureDateController.dispose();
    _remarksController.dispose();
    hotelRoomNotifier.dispose();
    airTicketsNotifier.dispose();
    _reservationnewnumberController.dispose();
    _packageAmountController.dispose();
    for (final row in _extraMembers) {
      row.dispose();
    }
    super.dispose();
  }

  /// Pulls the approvers for the "Request Approval From" dropdown. A failure
  /// only clears the list — the reservation still saves without an approver.
  Future<void> _loadAuthorizationLevels() async {
    // Assigned rather than setState'd: initState calls this while the element
    // is still building, and markNeedsBuild there asserts. The awaits below
    // land after the first frame, so the spinner still shows.
    _isLoadingAuthorizationLevels = true;
    try {
      final levels = await AuthorizationLevelRepository(
        ApiService(SecureStorage.instance),
      ).getAuthorizationLevels();
      if (!mounted) return;
      setState(() {
        _authorizationLevels = levels;
        // A reservation loaded for editing may already name an approver that
        // is no longer in the list; drop the selection rather than letting the
        // dropdown assert on a value it cannot show.
        if (_selectedAuthorization != null &&
            !levels.contains(_selectedAuthorization)) {
          _selectedAuthorization = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _authorizationLevels = []);
    } finally {
      if (mounted) {
        setState(() => _isLoadingAuthorizationLevels = false);
      }
    }
  }

  /// The "Request Approval From" dropdown. Each menu row shows the approver and
  /// their level on one line with the (long) job title underneath, while the
  /// closed field shows just the name and level so it never overflows.
  ///
  /// An InputDecorator wrapping a plain DropdownButton rather than a
  /// DropdownButtonFormField: the field is fully controlled — the clear button
  /// resets it and a reloaded list can drop the selection — which the
  /// FormField's initialValue no longer supports.
  Widget _buildAuthorizationDropdown(FontSettings fontSettings) {
    return InputDecorator(
      isEmpty: _selectedAuthorization == null,
      decoration: InputDecoration(
        labelText: "Request Approval From",
        labelStyle: TextStyle(
          fontSize: fontSettings.fontSize,
          fontWeight: fontSettings.fontWeight,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12.0,
          vertical: 8.0,
        ),
        suffixIcon: _isLoadingAuthorizationLevels
            ? const Padding(
                padding: EdgeInsets.all(14.0),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : (_selectedAuthorization != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: "Clear",
                    onPressed: () =>
                        setState(() => _selectedAuthorization = null),
                  )
                : null),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AuthorizationLevel>(
          value: _selectedAuthorization,
          isExpanded: true,
          // hint: Text(
          //   _isLoadingAuthorizationLevels
          //       ? "Loading approvers..."
          //       : "Select an approver",
          //   style: TextStyle(
          //     fontSize: fontSettings.fontSize,
          //     fontWeight: fontSettings.fontWeight,
          //     color: Colors.grey,
          //   ),
          // ),
          style: TextStyle(
            fontSize: fontSettings.fontSize,
            fontWeight: fontSettings.fontWeight,
            color: Colors.black,
          ),
          // The approver's name is all the row carries, so the closed field
          // can paint the same single line the menu does.
          selectedItemBuilder: (context) => _authorizationLevels
              .map(
                (level) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    level.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSettings.fontSize,
                      fontWeight: fontSettings.fontWeight,
                    ),
                  ),
                ),
              )
              .toList(),
          items: _authorizationLevels
              .map(
                (level) => DropdownMenuItem<AuthorizationLevel>(
                  value: level,
                  child: Text(
                    level.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSettings.fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: _authorizationLevels.isEmpty
              ? null
              : (value) => setState(() => _selectedAuthorization = value),
        ),
      ),
    );
  }

  void _updateMemberIdFields(String fullMemberId) {
    if (fullMemberId.isNotEmpty) {
      if (_isNumericOnlyLocation) {
        setState(() {
          _memberIdNumberController.text = fullMemberId;
          _memberIdController.text = fullMemberId;
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
        _memberIdNumberController.text = numberPart;
        _memberIdController.text = fullMemberId;
      });
    }
  }

  // ── Members sharing the same package ────────────────────────────────

  /// Splits "BM1234" into its dropdown prefix and number, mirroring
  /// [_updateMemberIdFields] but without touching the main form fields.
  (String, String) _splitMemberId(String fullMemberId) {
    if (_isNumericOnlyLocation) return ("", fullMemberId);
    for (final prefix in const ["BM", "BL", "BN"]) {
      if (fullMemberId.startsWith(prefix)) {
        return (prefix, fullMemberId.substring(prefix.length));
      }
    }
    return ("BM", fullMemberId);
  }

  void _addExtraMember() {
    FocusScope.of(context).unfocus();
    setState(() {
      _extraMembers.add(
        _ExtraMemberRow(prefix: _isNumericOnlyLocation ? "" : _selectedPrefix),
      );
    });
  }

  void _removeExtraMember(int index) {
    setState(() {
      _extraMembers.removeAt(index).dispose();
    });
  }

  void _clearExtraMembers() {
    for (final row in _extraMembers) {
      row.dispose();
    }
    _extraMembers.clear();
  }

  /// Replaces every extra-member row with the given accompanying members —
  /// used when a guest card is pulled back into the form for editing.
  void _loadExtraMembers(List<AccompanyingMember> members) {
    _clearExtraMembers();
    for (final member in members) {
      final (prefix, number) = _splitMemberId(member.mid);
      _extraMembers.add(
        _ExtraMemberRow(
          prefix: prefix.isEmpty ? "" : prefix,
          midNumber: number,
          name: member.guestName,
          hasFamilyMembers: member.hasFamilyMembers,
          packageAmount: member.packageAmount,
          sharedPackage: member.sharedPackage,
        ),
      );
    }
  }

  /// Extra-member rows that actually name someone, as accompanying members.
  List<AccompanyingMember> _collectExtraMembers() {
    return _extraMembers
        .map((row) => AccompanyingMember(
              mid: row.fullMid(numericOnly: _isNumericOnlyLocation),
              guestName: row.nameController.text.trim(),
              hasFamilyMembers: row.hasFamilyMembers,
              packageAmount: row.packageAmountController.text.trim(),
              sharedPackage: row.sharedPackage,
            ))
        .where((m) => m.mid.isNotEmpty || m.guestName.isNotEmpty)
        .toList();
  }

  /// Every extra-member row must be either fully filled or fully blank, and no
  /// member may appear twice on the reservation — rooms and air tickets are
  /// matched back to their owner by member ID, so a duplicate would merge.
  bool _validateExtraMembers({required String primaryMid}) {
    final seen = <String>{if (primaryMid.isNotEmpty) primaryMid};

    for (var i = 0; i < _extraMembers.length; i++) {
      final row = _extraMembers[i];
      final mid = row.fullMid(numericOnly: _isNumericOnlyLocation);
      final name = row.nameController.text.trim();
      final packageAmount = row.packageAmountController.text.trim();

      if (mid.isEmpty && name.isEmpty && packageAmount.isEmpty) {
        continue; // blank row: ignored on save
      }

      if (mid.isEmpty || name.isEmpty) {
        _showError('Guest ${i + 2}: both Member ID and Name are required');
        return false;
      }
      if (packageAmount.isEmpty && !row.sharedPackage) {
        _showError('Guest ${i + 2}: Package Amount is required');
        return false;
      }
      if (!seen.add(mid)) {
        _showError('$mid is already added to this reservation');
        return false;
      }
    }

    // Also guard against a member already sitting on an added guest card.
    for (var i = 0; i < _guestEntries.length; i++) {
      if (i == _editingGuestIndex) continue;
      final entry = _guestEntries[i];
      for (final mid in [
        entry.mid.trim(),
        ...entry.accompanyingMembers.map((m) => m.mid.trim()),
      ]) {
        if (mid.isNotEmpty && seen.contains(mid)) {
          _showError('$mid is already added to this reservation');
          return false;
        }
      }
    }

    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  /// Member search for an extra-member row. Unlike the main fields these do not
  /// go through newReservationProvider, so the pick comes back by callback.
  Future<void> _openExtraMemberSearch(int index, int iid) async {
    FocusScope.of(context).unfocus();

    final row = _extraMembers[index];
    final searchTerm = iid == 8002
        ? row.fullMid(numericOnly: _isNumericOnlyLocation)
        : row.nameController.text.trim();

    void showSheet(List<GuestSearchResponse> guests) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext context) {
          return MemberNewSearchBottomSheet(
            guests: guests,
            initialSearchTerm: searchTerm,
            searchIid: iid,
            onSearch: (String term, int searchIid) async {
              final results = await GuestRepository(
                ApiService(SecureStorage.instance),
              ).searchGuest(searchIid, term);
              if (!mounted) return;
              Navigator.of(context).pop();
              showSheet(results);
            },
            onGuestSelected: (guest) {
              final (prefix, number) = _splitMemberId(guest.mid);
              setState(() {
                row.prefix = prefix;
                row.midNumberController.text = number;
                row.nameController.text = guest.mName;
              });
            },
          );
        },
      );
    }

    if (searchTerm.length < 3) {
      showSheet([]);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final guests = await GuestRepository(
        ApiService(SecureStorage.instance),
      ).searchGuest(iid, searchTerm);
      if (!mounted) return;
      setState(() => _isLoading = false);
      showSheet(guests);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error searching guests: $e');
    }
  }

  /// Loads the reservation's guests as guest cards — each carrying its own
  /// hotels, air tickets, dates and passports — so an update shows exactly who
  /// booked what, and leaves the form blank for adding a further guest.
  Future<void> _loadGuestEntriesForEdit(ReservationBallys reservation) async {
    setState(() => _isLoading = true);

    final entries = <GuestReservationEntryBallys>[];

    if (reservation.guests.isNotEmpty) {
      // A passport is filed against the member it belongs to, which may be
      // somebody sharing the guest's package rather than the guest themselves,
      // so a guest's passports are its own plus its members'.
      bool ownedBy(
        ReservationPassportImageBallys image,
        GuestReservationEntryBallys guest,
      ) {
        final bm = image.guestBmNumber.trim();
        return bm == guest.mid.trim() ||
            guest.accompanyingMembers.any((m) => m.mid.trim() == bm);
      }

      // Passports naming nobody still on the reservation would be dropped by
      // the reload and lost on the next update, so they ride along on the first
      // guest — still tagged with the member they came back under.
      final unclaimed = reservation.passportImages
          .where((image) =>
              !reservation.guests.any((guest) => ownedBy(image, guest)))
          .toList();

      for (final guest in reservation.guests) {
        final isFirst = identical(guest, reservation.guests.first);
        entries.add(
          GuestReservationEntryBallys(
            mid: guest.mid,
            guestName: guest.guestName,
            hotels: List<HotelDescipBallys>.from(guest.hotels),
            flights: List<FlightBookingBallys>.from(guest.flights),
            arrivalDate: guest.arrivalDate ?? reservation.arrDate,
            departureDate: guest.departureDate ?? reservation.depDate,
            remarks: guest.remarks,
            airTicketRequisition: guest.airTicketRequisition,
            passportImages: await _materializePassports([
              ...reservation.passportImages
                  .where((image) => ownedBy(image, guest)),
              if (isFirst) ...unclaimed,
            ]),
            // Carried through so an update re-sends what was booked instead
            // of blanking these out.
            hasFamilyMembers: guest.hasFamilyMembers,
            accompanyingMembers: guest.accompanyingMembers,
            packageAmount: guest.packageAmount,
            sharedPackage: guest.sharedPackage,
          ),
        );
      }
    } else {
      // Reservations made before the multi-guest payload carry no per-guest
      // breakdown: every hotel and flight belongs to the single member on the
      // reservation.
      entries.add(
        GuestReservationEntryBallys(
          mid: reservation.mid,
          guestName: reservation.mName,
          hotels: List<HotelDescipBallys>.from(reservation.hotelDescip),
          flights: List<FlightBookingBallys>.from(reservation.airticketDescrip),
          arrivalDate: reservation.arrDate,
          departureDate: reservation.depDate,
          remarks: reservation.remarks,
          airTicketRequisition:
              reservation.airticketDescrip.isNotEmpty ? "Yes" : "No",
          passportImages:
              await _materializePassports(reservation.passportImages),
          // Pre-multi-guest records kept the amount on the reservation, and
          // carry no tick — a missing amount stands in for one.
          packageAmount: reservation.packageAmountDisplay,
          sharedPackage: reservation.packageAmountDisplay.trim().isEmpty,
        ),
      );
    }

    if (!mounted) return;

    setState(() {
      _guestEntries
        ..clear()
        ..addAll(entries);
      // Reservations saved before these moved up carry them on their rooms and
      // tickets, so the form is seeded from the first row that names one. A
      // payment value the current brand's dropdown does not offer is ignored —
      // feeding it to the dropdown would trip its own assertion.
      final offered = _paymentByItems().map((i) => i.value).toSet();
      for (final hotel in entries.expand((e) => e.hotels)) {
        final banked = hotel.paymentBy?.trim() ?? '';
        if (banked.isNotEmpty && offered.contains(banked)) {
          _paymentBy = banked;
          break;
        }
      }
      for (final flight in entries.expand((e) => e.flights)) {
        final banked = flight.contactPerson?.trim() ?? '';
        if (banked.isNotEmpty) {
          _selectedContactPerson = banked;
          break;
        }
      }
      _isLoading = false;
    });

    // The view screen fills these with every hotel/flight on the reservation to
    // render its summary. They now live on the guest cards, so start the form
    // empty for the next guest.
    ref.read(selectedHotelBallysProvider.notifier).setHotels([]);
    ref.read(selectedFlightBallysProvider.notifier).setFlights([]);
    ref.read(selectedPassportBallysProvider.notifier).setFiles([]);
    ref.read(selectedGuestProvider.notifier).clearGuest();
  }

  /// Writes API passport images (base64) to disk so they behave like freshly
  /// picked files: the upload widget can show them and they get re-encoded on
  /// save, which keeps existing passports attached when the record is replaced.
  Future<List<PassportImageBallys>> _materializePassports(
    Iterable<ReservationPassportImageBallys> images,
  ) async {
    final result = <PassportImageBallys>[];

    try {
      final dir = await getApplicationDocumentsDirectory();
      final passportDir = Directory('${dir.path}/passport_uploads');
      if (!await passportDir.exists()) {
        await passportDir.create(recursive: true);
      }

      for (final image in images) {
        final bytes = image.bytes;
        if (bytes == null) continue;
        final fileName = image.fileName.isNotEmpty
            ? image.fileName
            : 'passport${image.isPdf ? '.pdf' : '.jpg'}';
        final file = File(
          '${passportDir.path}/${DateTime.now().microsecondsSinceEpoch}_$fileName',
        );
        await file.writeAsBytes(bytes);
        result.add(
          PassportImageBallys(
            path: file.path,
            fileName: fileName,
            isPdf: image.isPdf,
            // Keeps the image with the member it came back under, so an update
            // re-sends it against them rather than against the guest it was
            // hung off for editing.
            guestBmNumber: image.guestBmNumber,
          ),
        );
      }
    } catch (_) {
      // Nothing to attach; the guest keeps whatever passports get picked next.
    }

    return result;
  }

  void _populateFields(ReservationBallys selectedReservation) {
    _reservationNoController.text = selectedReservation.reservNo;
    _noOfNightsController.text = selectedReservation.noOfNights.toString();
    _packageAmountController.text = selectedReservation.packageAmountDisplay;
    // Reservation-level rows carry no tick of their own, so a missing amount
    // still stands in for a shared package here.
    _sharedPackage = selectedReservation.packageAmountDisplay.trim().isEmpty;
    _reservationnewnumberController.text =
        selectedReservation.reservationnewnumber ?? '';
  }

  Future<void> _getHotels() async {
    // One call brings hotels, hotel categories, room categories, room types
    // and meal plans for the hotel selector. Only warms the cache so the sheet
    // opens with something on screen — the sheet itself re-reads the API, so a
    // hotel added since app start still shows up in the dropdown.
    await ref.read(hotelCatalogProvider.notifier).load();
  }

  String getGuestAndRoomCounts(List<HotelDescipBallys> hotels) {
    final totalGuests =
        hotels.fold<int>(0, (sum, hotel) => sum + hotel.guestCount!);
    // Children ride on their own count on every room, so they are summed and
    // shown next to the guests (adults) instead of being folded into them.
    final totalChildren =
        hotels.fold<int>(0, (sum, hotel) => sum + (hotel.childrenCount ?? 0));
    final totalRooms =
        hotels.fold<int>(0, (sum, hotel) => sum + hotel.roomCount!);

    final guestTxt =
        totalGuests == 1 ? "$totalGuests GUEST" : "$totalGuests GUESTS";
    final childTxt = totalChildren == 1
        ? "$totalChildren CHILD"
        : "$totalChildren CHILDREN";
    final roomTxt =
        totalRooms == 1 ? "$totalRooms ROOM" : "$totalRooms ROOMS";
    return totalChildren > 0
        ? "$guestTxt, $childTxt, $roomTxt"
        : "$guestTxt, $roomTxt";
  }

  String getGuestAndTicketCounts(List<FlightBookingBallys> flights) {
    final totalGuests = flights.fold<int>(0, (sum, f) => sum + f.guestCount);
    // guestCount is the adult count on a ticket; children travel on their own
    // count, so they get their own figure next to it.
    final totalChildren =
        flights.fold<int>(0, (sum, f) => sum + f.childrenCount);
    // A ticket is a seat, not a flight row: one booking can mix classes
    // (Economy x2 + Business x1 = 3 tickets), so the count is the seats across
    // every class. Rows saved without a class breakdown still count as one.
    final totalTickets = flights.fold<int>(
      0,
      (sum, f) => sum + (f.totalTicketCount > 0 ? f.totalTicketCount : 1),
    );

    final guestTxt =
        totalGuests == 1 ? "$totalGuests GUEST" : "$totalGuests GUESTS";
    final childTxt = totalChildren == 1
        ? "$totalChildren CHILD"
        : "$totalChildren CHILDREN";
    final ticketTxt =
        totalTickets == 1 ? "$totalTickets TICKET" : "$totalTickets TICKETS";
    return totalChildren > 0
        ? "$guestTxt, $childTxt, $ticketTxt"
        : "$guestTxt, $ticketTxt";
  }

  // ── Key fix: isDismissible: false + enableDrag: false so that
  //    dropdown dialog dismissal does NOT close the bottom sheet.
  /// Everyone currently on the reservation — guests already added to a card
  /// plus the member in the form and anyone sharing their package — flattened
  /// to BM number, name, family-members status and package amount for the
  /// selector sheets. The amount comes along because a room is counted per
  /// guest who carries one, so the hotel sheet has to see it.
  List<AccompanyingMember> _reservationGuestSummary() {
    final summary = <AccompanyingMember>[];

    for (var i = 0; i < _guestEntries.length; i++) {
      // The guest pulled back into the form is listed from the form fields
      // below, so skip its (stale) card here rather than showing it twice.
      if (i == _editingGuestIndex) continue;
      final entry = _guestEntries[i];
      summary.add(AccompanyingMember(
        mid: entry.mid,
        guestName: entry.guestName,
        hasFamilyMembers: entry.hasFamilyMembers,
        packageAmount: entry.packageAmount,
        sharedPackage: entry.sharedPackage,
      ));
      summary.addAll(entry.accompanyingMembers);
    }

    final mid = _memberIdController.text.trim();
    final name = _memberNameController.text.trim();
    if (mid.isNotEmpty || name.isNotEmpty) {
      summary.add(AccompanyingMember(
        mid: mid,
        guestName: name,
        hasFamilyMembers: _hasFamilyMembers,
        packageAmount: _packageAmountController.text.trim(),
        sharedPackage: _sharedPackage,
      ));
    }
    summary.addAll(_collectExtraMembers());

    return summary;
  }

  /// Hotels and air tickets are always booked *for* someone, so at least one
  /// guest — a card already added, or the member sitting in the form — has to
  /// exist before either selector is allowed to open. Without this the sheets
  /// come up with an empty guest list and nothing can be assigned.
  bool _requireGuestBeforeSelection({required bool forAirTickets}) {
    if (_reservationGuestSummary().isNotEmpty) {
      setState(() {
        if (forAirTickets) {
          _airTicketError = null;
        } else {
          _hotelError = null;
        }
      });
      return true;
    }

    final message = forAirTickets
        ? "Please add a guest before selecting air tickets"
        : "Please add a guest before selecting hotels & rooms";

    setState(() {
      if (forAirTickets) {
        _airTicketError = message;
      } else {
        _hotelError = message;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
    return false;
  }

  void _openHotelAndRoomSelectorBottomSheet(BuildContext context) {
    if (!_requireGuestBeforeSelection(forAirTickets: false)) return;
    FocusScope.of(context).requestFocus(FocusNode());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, // ← prevents tap-outside close
      enableDrag: false, // ← prevents swipe-down close
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return HotelAndRoomSelectionBallysBottomSheet(
          HotelRepository(ApiService(SecureStorage.instance)),
          onClose: () => Navigator.pop(context), // ← X button callback
          reservationArrivalDate: _arrivalDate,
          reservationDepartureDate: _departureDate,
          guests: _reservationGuestSummary(),
        );
      },
    );
  }

  void _openAirTicketsSelectorScreen(BuildContext context) {
    if (!_requireGuestBeforeSelection(forAirTickets: true)) return;
    FocusScope.of(context).requestFocus(FocusNode());
    context.push(
      "/reservationMain/reservations/new-reservation-ballys/air-tickets-selection",
      extra: {
        'arrivalDate': _arrivalDateController.text,
        'departureDate': _departureDateController.text,
        // Same list the hotel sheet gets, so a ticket can be assigned to the
        // guest(s) it is booked for.
        'guests': _reservationGuestSummary(),
      },
    );
  }

  bool _canChangeAirTicketToNo() {
    if (_isEditMode) {
      final selectedFlights = ref.watch(selectedFlightBallysProvider);
      return selectedFlights.isEmpty;
    }
    return true;
  }

  /// Applies a member picked from the search sheet to the main Member ID /
  /// Member Name pair.
  ///
  /// Without this the sheet falls back to writing into `newReservationProvider`
  /// — the non-Ballys provider, which this screen never reads — so the pick
  /// would load fine and then never reach the form.
  void _onPrimaryMemberSelected(GuestSearchResponse guest) {
    _updateMemberIdFields(guest.mid);
    setState(() {
      _memberNameController.text = guest.mName;
      _isGuestLoading = false;
    });

    ref
        .read(memberSearchProvider.notifier)
        .updateMemberInfo(guest.mid, guest.mName);
    ref
        .read(newReservationBallysProvider.notifier)
        .updateMemberInfo(guest.mid, guest.mName);

    // Feeds the guest card above the form (rating / last visit / photo).
    ref.read(selectedGuestProvider.notifier).setSelectedGuest(
          Guest(
            mid: guest.mid,
            memberName: guest.mName,
            country: "",
            lastVisitDate: guest.lvd?.toString() ?? "",
            age: 0,
            gRating: guest.gRating ?? "",
            mGroup: guest.mGroup ?? "",
            gName: guest.gName ?? "",
            memImage2: guest.memImage2,
          ),
        );
  }

  Future<void> _openMemberSearchBottomSheet(int iid) async {
    GuestRepository guestRepository = GuestRepository(
      ApiService(SecureStorage.instance),
    );

    String searchTerm =
        iid == 8002 ? _memberIdController.text : _memberNameController.text;

    if (searchTerm.length < 3) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext context) {
          return MemberNewSearchBottomSheet(
            guests: [],
            initialSearchTerm: searchTerm,
            searchIid: iid,
            onSearch: (String term, int searchIid) async {
              await _performGuestSearch(term, searchIid);
            },
            onGuestSelected: _onPrimaryMemberSelected,
          );
        },
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<GuestSearchResponse> guests =
          await guestRepository.searchGuest(iid, searchTerm);

      setState(() => _isLoading = false);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext context) {
          return MemberNewSearchBottomSheet(
            guests: guests,
            initialSearchTerm: searchTerm,
            searchIid: iid,
            onSearch: (String term, int searchIid) async {
              await _performGuestSearch(term, searchIid);
            },
            onGuestSelected: _onPrimaryMemberSelected,
          );
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _performGuestSearch(String searchTerm, int iid) async {
    if (searchTerm.length < 3) return;

    GuestRepository guestRepository = GuestRepository(
      ApiService(SecureStorage.instance),
    );

    try {
      List<GuestSearchResponse> guests =
          await guestRepository.searchGuest(iid, searchTerm);

      Navigator.of(context).pop();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext context) {
          return MemberNewSearchBottomSheet(
            guests: guests,
            initialSearchTerm: searchTerm,
            searchIid: iid,
            onSearch: (String term, int searchIid) async {
              await _performGuestSearch(term, searchIid);
            },
            onGuestSelected: _onPrimaryMemberSelected,
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error searching guests: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _validateUpdateFields() {
    setState(() {
      _hotelError = null;
      _airTicketError = null;
      hasError = false;
    });

    if (_arrivalDate != null && _departureDate != null) {
      if (_departureDate!.isBefore(_arrivalDate!) ||
          _departureDate!.isAtSameMomentAs(_arrivalDate!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Departure date must be after arrival date'),
            backgroundColor: Colors.red,
          ),
        );
        hasError = true;
      }
    }

    final selectedHotels = ref.watch(selectedHotelBallysProvider);
    final selectedFlights = ref.watch(selectedFlightBallysProvider);

    if (selectedHotels.isEmpty && selectedFlights.isEmpty) {
      setState(
          () => _hotelError = "Please select at least one hotel or flight");
      hasError = true;
    }

    if (_airTicketRequisition == "Yes" && selectedFlights.isEmpty) {
      setState(() => _airTicketError =
          "Please select at least one flight when air ticket requisition is 'Yes'");
      hasError = true;
    }

    if (selectedFlights.isNotEmpty &&
        _arrivalDate != null &&
        _departureDate != null) {
      for (var flight in selectedFlights) {
        if (flight.departureDate != null) {
          DateTime flightDate =
              DateTime.parse(flight.departureDate.toString());
          if (flightDate.isBefore(_arrivalDate!) ||
              flightDate.isAfter(_departureDate!)) {
            setState(() => _airTicketError =
                "Flight dates must be within the reservation period");
            hasError = true;
            break;
          }
        }
      }
    }

    if (_isEditMode && _airTicketRequisition == "No") {
      if (selectedFlights.isNotEmpty) {
        setState(() => _airTicketError =
            "Cannot set to 'No' when flights are already booked. Please remove flights first.");
        hasError = true;
      }
    }

    return !hasError;
  }

  /// Midnight today — the earliest day an arrival can be booked for.
  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _selectArrivalDate(BuildContext context) async {
    // Past days are not bookable, so the wheel starts at today and a stale
    // arrival from before today is pulled forward to keep the picker valid.
    final DateTime minimumDate = _today;
    DateTime selectedDate = _arrivalDate ?? minimumDate;
    if (selectedDate.isBefore(minimumDate)) selectedDate = minimumDate;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                "Select Arrival Date",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selectedDate,
                minimumDate: minimumDate,
                maximumDate: DateTime(2101),
                onDateTimeChanged: (DateTime newDate) {
                  selectedDate = newDate;
                },
              ),
            ),
            const Divider(height: 1),
            TextButton(
              onPressed: () {
                if (mounted) {
                  setState(() {
                    _arrivalDate = selectedDate;
                    _arrivalDateController.text =
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                    // Reset departure when arrival changes
                    _departureDate = null;
                    _departureDateController.clear();
                  });
                }
                Navigator.of(context).pop();
              },
              child: const Text(
                "Confirm",
                style: TextStyle(fontSize: 18, color: Colors.blue),
              ),
            ),
            const Divider(height: 1),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "Cancel",
                style: TextStyle(fontSize: 18, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _selectDepartureDate(BuildContext context) async {
    // A departure is always at least one night after the arrival it belongs to,
    // and never in the past when no arrival has been picked yet.
    final DateTime minimumDate =
        (_arrivalDate ?? _today).add(const Duration(days: 1));
    DateTime selectedDate = _departureDate ?? minimumDate;
    if (selectedDate.isBefore(minimumDate)) selectedDate = minimumDate;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                "Select Departure Date",
                style: TextStyle(
                  fontSize: 20,
                  color: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selectedDate,
                minimumDate: minimumDate,
                maximumDate: DateTime(2101),
                onDateTimeChanged: (DateTime newDate) {
                  selectedDate = newDate;
                },
              ),
            ),
            const Divider(height: 1),
            TextButton(
              onPressed: () {
                // Validate departure is after arrival
                if (_arrivalDate != null &&
                    !selectedDate.isAfter(_arrivalDate!)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Departure date must be after arrival date',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (mounted) {
                  setState(() {
                    _departureDate = selectedDate;
                    _departureDateController.text =
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                  });
                }
                Navigator.of(context).pop();
              },
              child: const Text(
                "Confirm",
                style: TextStyle(fontSize: 18, color: Colors.blue),
              ),
            ),
            const Divider(height: 1),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "Cancel",
                style: TextStyle(fontSize: 18, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  // ── Multi-guest helpers ─────────────────────────────────────────────

  /// Snapshots the guest currently on screen into a GuestReservationEntry.
  GuestReservationEntryBallys _snapshotCurrentGuest() {
    final selectedHotels = ref.read(selectedHotelBallysProvider);
    final selectedFlights = ref.read(selectedFlightBallysProvider);
    final selectedPassports = ref.read(selectedPassportBallysProvider);

    return GuestReservationEntryBallys(
      mid: _memberIdController.text.trim(),
      guestName: _memberNameController.text.trim(),
      hotels: List<HotelDescipBallys>.from(selectedHotels),
      flights: List<FlightBookingBallys>.from(selectedFlights),
      arrivalDate: _arrivalDate,
      departureDate: _departureDate,
      remarks: _remarksController.text,
      airTicketRequisition: _airTicketRequisition,
      // Each file keeps the member it was picked for on the air-ticket screen,
      // so a passport belonging to somebody sharing this guest's package goes
      // out under their own BM number.
      passportImages: selectedPassports
          .map((f) => PassportImageBallys(
                path: f.path,
                fileName: f.fileName,
                isPdf: f.isPdf,
                guestBmNumber: f.guestBmNumber,
                guestName: f.guestName,
              ))
          .toList(),
      hasFamilyMembers: _hasFamilyMembers,
      accompanyingMembers: _collectExtraMembers(),
      packageAmount: _packageAmountController.text.trim(),
      sharedPackage: _sharedPackage,
    );
  }

  /// Loads an already-added guest's data back into the form for editing,
  /// removing it from the list (it will be re-added on the next
  /// Add Guest / Add New Guest tap, or discarded if the user navigates away).
  void _editGuestEntry(int index) {
    final entry = _guestEntries[index];

    setState(() {
      _isGuestLoading = true;
      _editingGuestIndex = index;
      _memberIdController.text = entry.mid;
      _memberNameController.text = entry.guestName;
      _updateMemberIdFields(entry.mid);

      _arrivalDate = entry.arrivalDate;
      _departureDate = entry.departureDate;
      if (entry.arrivalDate != null) {
        _arrivalDateController.text =
            DateFormat('yyyy-MM-dd').format(entry.arrivalDate!);
      }
      if (entry.departureDate != null) {
        _departureDateController.text =
            DateFormat('yyyy-MM-dd').format(entry.departureDate!);
      }
      _remarksController.text = entry.remarks;
      _packageAmountController.text = entry.packageAmount;
      // The tick has to come back with the guest or re-saving would demand an
      // amount they were saved without.
      _sharedPackage = entry.sharedPackage;
      _airTicketRequisition = entry.airTicketRequisition;
      _hasFamilyMembers = entry.hasFamilyMembers;
      _loadExtraMembers(entry.accompanyingMembers);
    });

    ref.read(selectedHotelBallysProvider.notifier).setHotels(entry.hotels);
    ref.read(selectedFlightBallysProvider.notifier).setFlights(entry.flights);
    ref.read(selectedPassportBallysProvider.notifier).setFiles(
          entry.passportImages
              .map((p) => PassportFileBallys(
                    path: p.path,
                    fileName: p.fileName,
                    isPdf: p.isPdf,
                    guestBmNumber: p.guestBmNumber,
                    guestName: p.guestName,
                  ))
              .toList(),
        );

    // The guest card renders from selectedGuestProvider, which was cleared when
    // the guest was added, so its profile has to be fetched again.
    _loadGuestProfile(entry.mid, entry.guestName);
  }

  /// Fills selectedGuestProvider (rating / last visit / photo) for the member
  /// currently in the form.
  Future<void> _loadGuestProfile(String mid, String guestName) async {
    if (mid.isEmpty) {
      ref.read(selectedGuestProvider.notifier).clearGuest();
      if (mounted) setState(() => _isGuestLoading = false);
      return;
    }

    try {
      final guestRepository = GuestRepository(
        ApiService(SecureStorage.instance),
      );
      final guests = await guestRepository.searchGuest(9021, mid);

      final g = guests.isNotEmpty ? guests.first : null;
      ref.read(selectedGuestProvider.notifier).setSelectedGuest(
            Guest(
              mid: g?.mid ?? mid,
              memberName: g?.mName ?? guestName,
              country: "",
              lastVisitDate: g?.lvd?.toString() ?? "",
              age: 0,
              gRating: g?.gRating ?? "",
              mGroup: g?.mGroup ?? "",
              gName: g?.gName ?? "",
              memImage2: g?.memImage2,
            ),
          );
    } catch (_) {
      // Leave the card on the ID/name already in the form.
    } finally {
      if (mounted) setState(() => _isGuestLoading = false);
    }
  }

  void _removeGuestEntry(int index) {
    setState(() {
      _guestEntries.removeAt(index);
      if (_editingGuestIndex == index) {
        _editingGuestIndex = null;
      }
    });
  }

  String _summarizeGuestEntry(GuestReservationEntryBallys entry) {
    final hotelCount = entry.hotels.length;
    final flightCount = entry.flights.length;
    final parts = <String>[];
    if (hotelCount > 0) {
      parts.add(hotelCount == 1 ? "1 Hotel" : "$hotelCount Hotels");
    }
    if (flightCount > 0) {
      parts.add(flightCount == 1 ? "1 Flight" : "$flightCount Flights");
    }
    if (parts.isEmpty) parts.add("No hotel/flight");
    return parts.join(", ");
  }

  /// " · For: BM0012 — John, BM0043 — Mary" on a room / ticket booked for more
  /// than one guest. A single assignment is just the guest whose card this is,
  /// so it says nothing worth the space.
  String _assignedSuffix(List<AssignedGuest> assigned) {
    if (assigned.length < 2) return "";
    return " · For: ${assigned.map((g) => g.label).join(', ')}";
  }

  /// One line per hotel this guest booked, e.g.
  /// "Hilton Colombo — Deluxe, 2 Rooms, 3 Nights".
  List<String> _hotelLines(GuestReservationEntryBallys entry) {
    return entry.hotels.map((hotel) {
      final name = hotel.hotelName?.trim();
      final rooms = hotel.roomCount ?? 0;
      final nights = hotel.noOfNights ?? 0;
      final details = [
        if (hotel.roomCategoryName?.trim().isNotEmpty ?? false)
          hotel.roomCategoryName!.trim(),
        if (rooms > 0) rooms == 1 ? "1 Room" : "$rooms Rooms",
        if (nights > 0) nights == 1 ? "1 Night" : "$nights Nights",
      ];
      final title = (name != null && name.isNotEmpty) ? name : "Hotel";
      final line = details.isEmpty ? title : "$title — ${details.join(', ')}";
      return "$line${_assignedSuffix(hotel.assignedGuests)}";
    }).toList();
  }

  /// One line per air ticket this guest booked, e.g.
  /// "CMB → SIN — Round Trip, Business".
  List<String> _flightLines(GuestReservationEntryBallys entry) {
    return entry.flights.map((flight) {
      // Includes any transit stops, so a multi-sector ticket reads as
      // "CMB → DXB → LHR" rather than hiding the stops.
      final routeText = flight.departureRouteText;
      final route = routeText.isEmpty ? "Air Ticket" : routeText;
      final details = [
        if ((flight.airLine ?? '').trim().isNotEmpty) flight.airLine!.trim(),
        if (flight.isRoundTrip) "Round Trip",
        if (flight.isMultiSector) "Multi Sector",
        if (flight.ticketClassSummary.trim().isNotEmpty)
          flight.ticketClassSummary.trim(),
      ];
      final line = details.isEmpty ? route : "$route — ${details.join(', ')}";
      return "$line${_assignedSuffix(flight.assignedGuests)}";
    }).toList();
  }

  /// A single hotel / air-ticket row on a guest card: the icon is what tells
  /// the two apart at a glance.
  Widget _bookingLine({
    required IconData icon,
    required Color color,
    required String label,
    required double fontSize,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: fontSize + 2, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: fontSize, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  /// "Payment By" has to be answered before a reservation can be saved.
  bool _requirePaymentBy() {
    if ((_paymentBy ?? '').trim().isNotEmpty) return true;
    setState(() => _paymentByError = 'Please select Payment By');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please select Payment By'),
        backgroundColor: Colors.red,
      ),
    );
    return false;
  }

  void _confirmReservation() async {
    // The form-level validator on Member ID/Name only applies to whatever guest
    // is currently on screen. If guests have already been added and the current
    // fields are empty, that's fine — it just means the user is ready to submit
    // without a "dangling" extra guest. Update works the same way: the existing
    // guests are already loaded as cards.
    final hasDanglingGuestFields = _memberIdController.text.trim().isNotEmpty ||
        _memberNameController.text.trim().isNotEmpty;

    if (_guestEntries.isEmpty || hasDanglingGuestFields) {
      if (!_formKey.currentState!.validate()) return;
      if (!_validateUpdateFields()) return;
    }

    // Mandatory and with no default, so it is checked here rather than left to
    // the form validator — that one only runs for a guest still on screen.
    if (!_requirePaymentBy()) return;

    final selectedHotels = ref.read(selectedHotelBallysProvider);
    final selectedFlights = ref.read(selectedFlightBallysProvider);

    setState(() {
      _hotelError = null;
      _airTicketError = null;
      hasError = false;
    });

    // Build the final list of guests for this single reservation.
    final List<GuestReservationEntryBallys> allGuests =
        List<GuestReservationEntryBallys>.from(_guestEntries);

    final bool currentGuestHasData =
        _memberIdController.text.trim().isNotEmpty &&
            _memberNameController.text.trim().isNotEmpty;

    if (currentGuestHasData) {
      // Auto-append whatever is currently on screen as the final guest.
      if (selectedHotels.isEmpty && selectedFlights.isEmpty) {
        setState(() =>
            _hotelError = "Please select at least one hotel or flight");
        hasError = true;
      }
      if (_airTicketRequisition == "Yes" && selectedFlights.isEmpty) {
        setState(
            () => _airTicketError = "Please select at least one flight");
        hasError = true;
      }
      if (hasError) return;

      if (!_validateExtraMembers(
          primaryMid: _memberIdController.text.trim())) {
        return;
      }

      // The on-screen guest is either one pulled back from a card for editing
      // (replace it in place — appending would submit that guest twice) or a
      // brand-new one the user never pressed "Add Guest" for.
      if (_editingGuestIndex != null &&
          _editingGuestIndex! < allGuests.length) {
        allGuests[_editingGuestIndex!] = _snapshotCurrentGuest();
      } else {
        allGuests.add(_snapshotCurrentGuest());
      }
    }

    if (allGuests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one guest'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // The top-level bmNumber/guestName/dates mirror the FIRST guest for
    // backward compatibility. roomDetails/airTicketDetails span ALL guests,
    // each row naming the guests it was booked for in its own `assigned_guests`;
    // passportImages stay tagged with their owner's GuestBMNumber. The
    // lightweight per-guest payload travels in `guests`.
    final firstGuest = allGuests.first;

    final reservation = NewReservationBallys(
      bmNumber: firstGuest.mid,
      guestName: firstGuest.guestName,
      hotelName: "",
      roomDetails:
          allGuests.expand((g) => g.toRoomDetailsJson()).toList(),
      noOfNights: 0,
      arrivalDate: firstGuest.arrivalDate,
      departureDate: firstGuest.departureDate,
      hasAirTicketReservation: firstGuest.airTicketRequisition == "Yes"
          ? "1"
          : "0",
      remarks: firstGuest.remarks,
      airTicketDetails:
          allGuests.expand((g) => g.toAirTicketDetailsJson()).toList(),
      reservationnewnumber: _reservationnewnumberController.text,
      packageAmount: _packageAmountController.text,
      // Picked once on the form, so they leave the room / ticket rows and
      // travel at the top of the body.
      paymentBy: _paymentBy ?? '',
      contactPerson: _selectedContactPerson ?? '',
      isSharedAmount: _sharedPackage,
      authorizationId: _selectedAuthorization?.idNo,
      authorizationPerson: _selectedAuthorization?.name,
      authorizationLevelNo: _selectedAuthorization?.levelNo,
      authorizationCategory: _selectedAuthorization?.category,
      // Each guest expands to itself plus anyone sharing its package, so two
      // members on one package travel as two `guests` rows against one set of
      // rooms / air tickets.
      guests: allGuests.expand((g) => g.toGuestsJson()).toList(),
      passportImages: allGuests
          .expand((g) => g.toPassportImagesJson())
          .toList(),
    );

    if (_isEditMode) {
      reservation.reservationNo = _reservationNoController.text;
    }

    ReservationRepository reservationRepository = ReservationRepository(
      ApiService(SecureStorage.instance),
    );

    setState(() => _isLoading = true);

    try {
      ReservationBallys? response = !_isEditMode
          ? await reservationRepository.saveReservationBallys(reservation)
          : await reservationRepository.updateReservationBallys(reservation);

      // On update the caller reloads the list from the API; adding here would
      // show the reservation twice until that reload lands.
      if (response != null && !_isEditMode) {
        ref.read(reservationBallysProvider.notifier).addReservationToPending(response);
      }

      // Clear all form fields
      setState(() {
        _isLoading = false;
        _memberIdController.clear();
        _memberIdNumberController.clear();
        _memberNameController.clear();
        _noOfNightsController.clear();
        _arrivalDateController.clear();
        _departureDateController.clear();
        _remarksController.clear();
        _reservationnewnumberController.clear();
        _packageAmountController.clear();
        _reservationNoController.clear();
        _hasFamilyMembers = false;
        _sharedPackage = false;
        _paymentBy = null;
        _paymentByError = null;
        _selectedContactPerson = null;
        _selectedAuthorization = null;
        _clearExtraMembers();
        _arrivalDate = null;
        _departureDate = null;
        _airTicketRequisition = 'No';
        _guestEntries.clear();
        _editingGuestIndex = null;
        _hotelError = null;
        _airTicketError = null;
        hasError = false;
      });

      // Clear all provider state
      ref.read(selectedHotelBallysProvider.notifier).setHotels([]);
      ref.read(selectedFlightBallysProvider.notifier).setFlights([]);
      ref.read(selectedPassportBallysProvider.notifier).setFiles([]);
      ref.read(selectedGuestProvider.notifier).clearGuest();
      ref.read(newReservationBallysProvider.notifier).resetState();
      ref.read(memberSearchProvider.notifier).resetState();
      ref.read(selectedReservationBallysProvider.notifier).clearSelectedBallysReservation();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditMode
                  ? 'Reservation updated successfully'
                  : 'Reservation saved successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _navigateToProfile() async {
    try {
      final currentSelectedGuest = ref.read(selectedGuestProvider);
      if (currentSelectedGuest != null &&
          currentSelectedGuest.mid == _memberIdController.text) {
        context.push('/home/profile');
        return;
      }

      setState(() => _isLoading = true);

      GuestRepository guestRepository = GuestRepository(
        ApiService(SecureStorage.instance),
      );

      List<GuestSearchResponse> guests =
          await guestRepository.searchGuest(9021, _memberIdController.text);

      setState(() => _isLoading = false);

      Guest guest;
      if (guests.isNotEmpty) {
        final g = guests.first;
        guest = Guest(
          mid: g.mid ?? _memberIdController.text,
          memberName: g.mName ?? _memberNameController.text,
          country: "",
          lastVisitDate: g.lvd?.toString() ?? "",
          gift: "",
          age: 0,
          gRating: g.gRating ?? "",
          mGroup: "",
          gName: g.gName ?? "",
          memImage2: g.memImage2,
        );
      } else {
        guest = Guest(
          mid: _memberIdController.text,
          memberName: _memberNameController.text,
          country: "",
          lastVisitDate: "1990-01-01",
          gift: "",
          age: 0,
          gRating: "",
          mGroup: "",
          gName: "",
        );
      }

      ref.read(selectedGuestProvider.notifier).setSelectedGuest(guest);
      context.push('/home/profile');
    } catch (e) {
      setState(() => _isLoading = false);
      ref.read(selectedGuestProvider.notifier).setSelectedGuest(
            Guest(
              mid: _memberIdController.text,
              memberName: _memberNameController.text,
              country: "",
              lastVisitDate: "1990-01-01",
              gift: "",
              age: 0,
              gRating: "",
              mGroup: "",
              gName: "",
            ),
          );
      context.push('/home/profile');
    }
  }

  /// "Does this member bring family?" — a plain yes/no tick, so an unticked
  /// member is a deliberate "no family" rather than a box someone left blank.
  Widget _familyMembersField({
    required FontSettings fontSettings,
    required bool checked,
    required ValueChanged<bool> onCheckedChanged,
  }) {
    return InkWell(
      onTap: () => onCheckedChanged(!checked),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: checked ? Constants.kPrimaryColor : const Color(0xFFDADDE3),
            width: checked ? 1.6 : 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              activeColor: Constants.kPrimaryColor,
              onChanged: (value) => onCheckedChanged(value ?? false),
            ),
            const Icon(Icons.family_restroom, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Family Members Included",
                style: TextStyle(
                  fontSize: fontSettings.fontSize,
                  fontWeight: fontSettings.fontWeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One extra member sharing the on-screen member's package: who they are and
  /// which family members come with them. No hotel / flight / date fields —
  /// those are inherited from the member above.
  Widget _extraMemberCard(int index, FontSettings fontSettings) {
    final row = _extraMembers[index];

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDADDE3)),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Constants.kSecondaryColor,
                  foregroundColor: Colors.white,
                  child: Text(
                    "${index + 2}",
                    style: TextStyle(fontSize: fontSettings.fontSize * 0.8),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Guest ${index + 2} — Same Package",
                    style: TextStyle(
                      fontSize: fontSettings.fontSize * 0.9,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1F2430),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _removeExtraMember(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── MID ──
            TextFormField(
              controller: row.midNumberController,
              keyboardType: TextInputType.number,
              style: TextStyle(
                fontSize: fontSettings.fontSize,
                fontWeight: fontSettings.fontWeight,
              ),
              decoration: InputDecoration(
                labelText: "MID",
                labelStyle: TextStyle(
                  fontSize: fontSettings.fontSize,
                  fontWeight: fontSettings.fontWeight,
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: -5.0,
                ),
                prefixIcon: _isNumericOnlyLocation
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _prefixes.contains(row.prefix)
                                ? row.prefix
                                : (_prefixes.isEmpty ? null : _prefixes.first),
                            style: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                              color: Colors.black,
                            ),
                            items: _prefixes
                                .map((prefix) => DropdownMenuItem(
                                      value: prefix,
                                      child: Text(prefix),
                                    ))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => row.prefix = value!),
                          ),
                        ),
                      ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _openExtraMemberSearch(index, 8002),
                ),
              ),
              onChanged: (_) => setState(() => row.nameController.clear()),
            ),
            const SizedBox(height: 10),

            // ── Member Name ──
            TextFormField(
              controller: row.nameController,
              style: TextStyle(
                fontSize: fontSettings.fontSize,
                fontWeight: fontSettings.fontWeight,
              ),
              decoration: InputDecoration(
                labelText: "Member Name",
                labelStyle: TextStyle(
                  fontSize: fontSettings.fontSize,
                  fontWeight: fontSettings.fontWeight,
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: -5.0,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _openExtraMemberSearch(index, 8003),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── This guest's own package amount ──
            // Keyed on the row itself so removing a card takes its picker
            // state with it instead of leaving it behind on the next row.
            PackageAmountFieldBallys(
              key: ValueKey(row),
              controller: row.packageAmountController,
              noPackage: row.sharedPackage,
              // A shared member can still be billed an amount of their own, so
              // ticking Shared records that and leaves the picker usable.
              allowAmountWhenShared: true,
              onNoPackageChanged: (value) =>
                  setState(() => row.sharedPackage = value),
              textStyle: TextStyle(
                fontSize: fontSettings.fontSize,
                fontWeight: fontSettings.fontWeight,
                color: Colors.black,
              ),
              decoration: InputDecoration(
                labelText: "Package Amount *",
                labelStyle: TextStyle(
                  fontSize: fontSettings.fontSize,
                  fontWeight: fontSettings.fontWeight,
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: -5.0,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Family members of THIS guest ──
            _familyMembersField(
              fontSettings: fontSettings,
              checked: row.hasFamilyMembers,
              onCheckedChanged: (value) =>
                  setState(() => row.hasFamilyMembers = value),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedHotels = ref.watch(selectedHotelBallysProvider);
    hotelRoomNotifier.value = getGuestAndRoomCounts(selectedHotels);

    final selectedFlights = ref.watch(selectedFlightBallysProvider);
    airTicketsNotifier.value = getGuestAndTicketCounts(selectedFlights);

    final newReservation = ref.watch(newReservationBallysProvider);
    if (newReservation.bmNumber != null &&
        (_memberIdController.text != newReservation.bmNumber ||
            _memberNameController.text != (newReservation.guestName ?? ''))) {
      _memberIdController.text = newReservation.bmNumber!;
      _memberNameController.text = newReservation.guestName ?? '';
      _updateMemberIdFields(newReservation.bmNumber!);
    }

    final fontSettings = ref.watch(fontSettingsProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0.5,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.15),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: !_isEditMode
                    ? const [
                        Constants.kPrimaryColor,
                        Constants.kSecondaryColor,
                      ]
                    : const [
                        Color(0xFF2E7D5B),
                        Color(0xFF1B5E3F),
                      ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          title: Text(
            !_isEditMode ? "New Reservation" : "Update Reservation",
            style: TextStyle(
              fontSize: 18 * (fontSettings.fontSize / 16),
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
        body: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFDADDE3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFDADDE3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Constants.kPrimaryColor,
                  width: 1.6,
                ),
              ),
            ),
          ),
          child: Form(
          key: _formKey,
          child: PopScope(
            onPopInvokedWithResult: (bool didPop, dynamic result) {
              ref.read(newReservationBallysProvider.notifier).resetState();
              ref.read(memberSearchProvider.notifier).resetState();
              ref
                  .read(selectedReservationBallysProvider.notifier)
                  .clearSelectedBallysReservation();
              ref.read(selectedHotelBallysProvider.notifier).setHotels([]);
              ref.read(selectedFlightBallysProvider.notifier).setFlights([]);
              ref.read(selectedPassportBallysProvider.notifier).setFiles([]);
            },
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // ── Reservation No (edit mode only) ────
                        if (_isEditMode) ...[
                          TextFormField(
                            autofocus: false,
                            readOnly: true,
                            controller: _reservationNoController,
                            style: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                            decoration: InputDecoration(
                              labelText: "Reservation No",
                              labelStyle: TextStyle(
                                fontSize: fontSettings.fontSize,
                                fontWeight: fontSettings.fontWeight,
                              ),
                              border: const OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: -5.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10.0),
                        ],

                        if (newReservation.bmNumber != null)
                          const SizedBox(height: 16.0),

                        // ── Already-added guests banner ────────
                        // if (_guestEntries.isNotEmpty) ...[
                        //   Align(
                        //     alignment: Alignment.topLeft,
                        //     child: Text(
                        //       "Guests added: ${_guestEntries.length}"
                        //       "${_editingGuestIndex != null ? ' (editing #${_editingGuestIndex! + 1})' : ''}",
                        //       style: TextStyle(
                        //         fontSize: fontSettings.fontSize,
                        //         fontWeight: FontWeight.bold,
                        //         color: Constants.kSecondaryColor,
                        //       ),
                        //     ),
                        //   ),
                        //   const SizedBox(height: 8.0),
                        //   Column(
                        //     children:
                        //         _guestEntries.asMap().entries.map((mapEntry) {
                        //       final i = mapEntry.key;
                        //       final g = mapEntry.value;
                        //       return Card(
                        //         color: const Color.fromARGB(
                        //             255, 235, 245, 233),
                        //         margin: const EdgeInsets.symmetric(
                        //           horizontal: 3,
                        //           vertical: 6,
                        //         ),
                        //         child: ListTile(
                        //           leading: CircleAvatar(
                        //             backgroundColor:
                        //                 Constants.kSecondaryColor,
                        //             foregroundColor: Colors.white,
                        //             child: Text("${i + 1}"),
                        //           ),
                        //           title: Text(
                        //             g.guestName,
                        //             style: TextStyle(
                        //               fontWeight: FontWeight.bold,
                        //               fontSize: fontSettings.fontSize,
                        //             ),
                        //           ),
                        //           subtitle: Text(
                        //             "${g.mid}\n${_summarizeGuestEntry(g)}"
                        //             "${g.arrivalDate != null && g.departureDate != null ? '\n${DateFormat('yyyy-MM-dd').format(g.arrivalDate!)} → ${DateFormat('yyyy-MM-dd').format(g.departureDate!)}' : ''}",
                        //             style: TextStyle(
                        //               fontSize:
                        //                   fontSettings.fontSize * 0.85,
                        //             ),
                        //           ),
                        //           isThreeLine: true,
                        //           trailing: Row(
                        //             mainAxisSize: MainAxisSize.min,
                        //             children: [
                        //               IconButton(
                        //                 icon: const Icon(Icons.edit,
                        //                     color: Colors.blue),
                        //                 onPressed: () => _editGuestEntry(i),
                        //               ),
                        //               IconButton(
                        //                 icon: const Icon(Icons.delete,
                        //                     color: Colors.red),
                        //                 onPressed: () => _removeGuestEntry(i),
                        //               ),
                        //             ],
                        //           ),
                        //         ),
                        //       );
                        //     }).toList(),
                        //   ),
                        //   const SizedBox(height: 16.0),
                        // ],
 if (_guestEntries.isNotEmpty) ...[
                          // Align(
                          //   alignment: Alignment.topLeft,
                          //   child: Text(
                          //     "Guests added: ${_guestEntries.length}"
                          //     "${_editingGuestIndex != null ? ' (editing #${_editingGuestIndex! + 1})' : ''}",
                          //     style: TextStyle(
                          //       fontSize: fontSettings.fontSize,
                          //       fontWeight: FontWeight.bold,
                          //       color: Constants.kSecondaryColor,
                          //     ),
                          //   ),
                          // ),
                        //  const SizedBox(height: 8.0),
                          Column(
                            children:
                                _guestEntries.asMap().entries.map((mapEntry) {
                              final i = mapEntry.key;
                              final g = mapEntry.value;
                              // This guest is currently loaded into the form
                              // below; the form overwrites this card on save
                              // rather than adding a second guest.
                              final isEditing = _editingGuestIndex == i;
                              return Card(
                                elevation: 0,
                                color: isEditing
                                    ? const Color(0xFFFFF4E5)
                                    : const Color(0xFFEFF7F1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isEditing
                                        ? Colors.deepOrange
                                        : const Color(0xFFCADFD1),
                                    width: isEditing ? 1.6 : 1,
                                  ),
                                ),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 6,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5.0,
                                    horizontal: 8.0,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // ── Left column: number, edit, delete (stacked) ──
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            backgroundColor:
                                                Constants.kSecondaryColor,
                                            foregroundColor: Colors.white,
                                            child: Text("${i + 1}"),
                                          ),
                                          const SizedBox(height: 2),
                                          IconButton(
                                            icon: const Icon(Icons.edit,
                                                color: Colors.blue),
                                            onPressed: () =>
                                                _editGuestEntry(i),
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(),
                                          ),
                                          const SizedBox(height: 2),
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red),
                                            onPressed: () =>
                                                _removeGuestEntry(i),
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 10),
                                      // ── Right side: guest details ──
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    g.guestName,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                    ),
                                                  ),
                                                ),
                                                if (isEditing)
                                                  Text(
                                                    "EDITING BELOW",
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                              .fontSize *
                                                          0.75,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.deepOrange,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "${g.mid}\n${_summarizeGuestEntry(g)}"
                                              "${g.arrivalDate != null && g.departureDate != null ? '\n${DateFormat('yyyy-MM-dd').format(g.arrivalDate!)} → ${DateFormat('yyyy-MM-dd').format(g.departureDate!)}' : ''}",
                                              style: TextStyle(
                                                fontSize: fontSettings
                                                        .fontSize*0.90,
                                                fontWeight: fontSettings.fontWeight
                                              ),
                                            ),
                                            // Spell out what this guest booked
                                            // so a hotel is never mistaken for
                                            // an air ticket.
                                            ..._hotelLines(g).map(
                                              (line) => _bookingLine(
                                                icon: Icons.hotel,
                                                color: Constants.kSecondaryColor,
                                                label: line,
                                                fontSize:
                                                    fontSettings.fontSize * 0.85,
                                              ),
                                            ),
                                            ..._flightLines(g).map(
                                              (line) => _bookingLine(
                                                icon: Icons.flight_takeoff,
                                                color: Colors.deepOrange,
                                                label: line,
                                                fontSize:
                                                    fontSettings.fontSize * 0.85,
                                              ),
                                            ),
                                            if (g.hasFamilyMembers)
                                              _bookingLine(
                                                icon: Icons.family_restroom,
                                                color: Colors.blueGrey,
                                                label: "Family members included",
                                                fontSize:
                                                    fontSettings.fontSize * 0.85,
                                              ),
                                            // Members riding on this guest's
                                            // package — no rooms or tickets of
                                            // their own.
                                            ...g.accompanyingMembers.map(
                                              (m) => _bookingLine(
                                                icon: Icons.group,
                                                color: Constants.kPrimaryColor,
                                                label: [
                                                  "${m.guestName} (${m.mid})",
                                                  if (m.packageAmount
                                                      .trim()
                                                      .isNotEmpty)
                                                    m.packageAmount.trim(),
                                                  if (m.sharedPackage)
                                                    "shared package",
                                                  if (m.hasFamilyMembers)
                                                    "family members included",
                                                ].join(" — "),
                                                fontSize:
                                                    fontSettings.fontSize * 0.85,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8.0),
                        ],
                        // ── MID + Profile Button ───────────────
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                      controller: _memberIdNumberController,
                                      keyboardType: TextInputType.number,
                                      style: TextStyle(
                                        fontSize: fontSettings.fontSize,
                                        fontWeight: fontSettings.fontWeight,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: "MID *",
                                        labelStyle: TextStyle(
                                          fontSize: fontSettings.fontSize,
                                          fontWeight:
                                              fontSettings.fontWeight,
                                        ),
                                        border: const OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                              ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 12.0,
                                          vertical: -5.0,
                                        ),
                                        prefixIcon: _isNumericOnlyLocation
                                            ? null
                                            : Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                  left: 12,
                                                  right: 4,
                                                ),
                                                child:
                                                    DropdownButtonHideUnderline(
                                                  child: DropdownButton<String>(
                                                    value: _selectedPrefix,
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      fontWeight: fontSettings
                                                          .fontWeight,
                                                      color: Colors.black,
                                                    ),
                                                    items: _prefixes
                                                        .map((prefix) {
                                                      return DropdownMenuItem(
                                                        value: prefix,
                                                        child: Text(
                                                          prefix,
                                                          style: TextStyle(
                                                            fontSize:
                                                                fontSettings
                                                                    .fontSize,
                                                            fontWeight:
                                                                fontSettings
                                                                    .fontWeight,
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
                                                    onChanged: (value) {
                                                      setState(() =>
                                                          _selectedPrefix =
                                                              value!);
                                                    },
                                                  ),
                                                ),
                                              ),
                                        suffixIcon: IconButton(
                                          icon: const Icon(Icons.search),
                                          onPressed: () {
                                            FocusScope.of(context).unfocus();
                                            _memberIdController.text =
                                                _isNumericOnlyLocation
                                                    ? _memberIdNumberController
                                                        .text
                                                    : '$_selectedPrefix${_memberIdNumberController.text}';
                                            _openMemberSearchBottomSheet(
                                                8002);
                                          },
                                        ),
                                      ),
                                      validator: (value) {
                                        // Skip the "required" check when the
                                        // user has already added other
                                        // guests and intentionally left the
                                        // current fields blank to submit.
                                        if (_guestEntries.isNotEmpty &&
                                            (value == null ||
                                                value.trim().isEmpty) &&
                                            _memberNameController.text
                                                .trim()
                                                .isEmpty) {
                                          return null;
                                        }
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return "Member ID is required";
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        _memberNameController.text = '';
                                        ref
                                            .read(newReservationBallysProvider
                                                .notifier)
                                            .resetState();
                                      },
                                    ),
                            ),
                            const SizedBox(width: 10.0),
                            ElevatedButton(
                              onPressed: _memberIdController.text.trim().isEmpty
                                  ? null
                                  : _navigateToProfile,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _memberIdController.text.trim().isEmpty
                                        ? Colors.grey.shade400
                                        : const Color.fromARGB(
                                            255, 70, 70, 70),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 14,
                                ),
                              ),
                              child:
                                  const Icon(Icons.person_search, size: 25),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10.0),

                        // ── Member Name ────────────────────────
                        TextFormField(
                          autofocus: false,
                          controller: _memberNameController,
                          style: TextStyle(
                            fontSize: fontSettings.fontSize,
                            fontWeight: fontSettings.fontWeight,
                          ),
                          decoration: InputDecoration(
                            labelText: "Member Name *",
                            labelStyle: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                            border: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: -5.0,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () {
                                FocusScope.of(context)
                                    .requestFocus(FocusNode());
                                _openMemberSearchBottomSheet(8003);
                              },
                            ),
                          ),
                          validator: (value) {
                            // Same exemption as Member ID above.
                            if (_guestEntries.isNotEmpty &&
                                (value == null || value.trim().isEmpty) &&
                                _memberIdController.text.trim().isEmpty) {
                              return null;
                            }
                            if (value == null || value.trim().isEmpty) {
                              return "Member Name is required";
                            }
                            return null;
                          },
                          onChanged: (value) {
                            _memberIdController.text = '';
                            ref
                                .read(newReservationBallysProvider.notifier)
                                .resetState();
                          },
                        ),

                        // ── Guest Card ─────────────────────────
                        GuestDisplayCardSpecialGiftview(
                          memberIdText: _memberIdController.text,
                          memberNameText: _memberNameController.text,
                          showCard: _memberIdController.text.isNotEmpty &&
                              _memberNameController.text.isNotEmpty,
                          isLoading: _isGuestLoading,
                          showLastVisitDate: true,
                        ),
                        const SizedBox(height: 10.0),

                        // ── Family members of this member ──────
                        _familyMembersField(
                          fontSettings: fontSettings,
                          checked: _hasFamilyMembers,
                          onCheckedChanged: (value) =>
                              setState(() => _hasFamilyMembers = value),
                        ),
                        const SizedBox(height: 10.0),

                        // ── This member's package amount ───────
                        PackageAmountFieldBallys(
                          controller: _packageAmountController,
                          enabled: true,
                          noPackage: _sharedPackage,
                          // Shared only records that the package is shared —
                          // an amount can still be picked alongside it.
                          allowAmountWhenShared: true,
                          onNoPackageChanged: (value) =>
                              setState(() => _sharedPackage = value),
                          textStyle: TextStyle(
                            fontSize: fontSettings.fontSize,
                            fontWeight: fontSettings.fontWeight,
                            color: Colors.black,
                          ),
                          decoration: InputDecoration(
                            labelText: "Package Amount *",
                            labelStyle: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                            border: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: -5.0,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return "Package Amount Number is required";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10.0),

                        // ── Extra members on the SAME package ──
                        ..._extraMembers.asMap().entries.map(
                              (e) => _extraMemberCard(e.key, fontSettings),
                            ),

                        // ── Add More Guest ─────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _addExtraMember,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Constants.kPrimaryColor,
                              side: const BorderSide(
                                color: Constants.kPrimaryColor,
                                width: 1.6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.group_add, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  "Add More Guest",
                                  style: TextStyle(
                                    fontSize: fontSettings.fontSize * 0.9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // if (_extraMembers.isNotEmpty)
                        //   Padding(
                        //     padding: const EdgeInsets.only(top: 6.0),
                        //     child: Text(
                        //       "These members share the same hotel, air tickets "
                        //       "and dates as the member above, each with their "
                        //       "own package amount.",
                        //       style: TextStyle(
                        //         fontSize: fontSettings.fontSize * 0.75,
                        //         color: Colors.grey.shade600,
                        //       ),
                        //     ),
                        //   ),
                        const SizedBox(height: 10.0),

                          // ── Arrival Date ───────────────────────
                        TextFormField(
                          controller: _arrivalDateController,
                          readOnly: true,
                          style: TextStyle(
                            fontSize: fontSettings.fontSize,
                            fontWeight: fontSettings.fontWeight,
                          ),
                          decoration: InputDecoration(
                            labelText: "Arrival Date *",
                            labelStyle: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                            border: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: -5.0,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today),
                              onPressed: () => _selectArrivalDate(context),
                            ),
                          ),
                          validator: (value) {
                            if (_guestEntries.isNotEmpty &&
                                (value == null || value.trim().isEmpty) &&
                                _memberIdController.text.trim().isEmpty) {
                              return null;
                            }
                            if (value == null || value.trim().isEmpty) {
                              return "Arrival Date is required";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),

                        // ── Departure Date ─────────────────────
                        TextFormField(
                          controller: _departureDateController,
                          readOnly: true,
                          style: TextStyle(
                            fontSize: fontSettings.fontSize,
                            fontWeight: fontSettings.fontWeight,
                          ),
                          decoration: InputDecoration(
                            labelText: "Departure Date *",
                            labelStyle: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                            border: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: -5.0,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today),
                              onPressed: () => _selectDepartureDate(context),
                            ),
                          ),
                          validator: (value) {
                            if (_guestEntries.isNotEmpty &&
                                (value == null || value.trim().isEmpty) &&
                                _memberIdController.text.trim().isEmpty) {
                              return null;
                            }
                            if (value == null || value.trim().isEmpty) {
                              return "Departure Date is required";
                            }
                            if (_arrivalDate != null &&
                                _departureDate != null &&
                                _departureDate!.isBefore(_arrivalDate!)) {
                              return "Departure must be after Arrival";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
 // ── Air Ticket Requisition ─────────────
                        Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            "Air Ticket Requisition",
                            style: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Radio<String>(
                              value: "Yes",
                              groupValue: _airTicketRequisition,
                              onChanged: (value) => setState(
                                  () => _airTicketRequisition = value!),
                            ),
                            Text("Yes",
                                style: TextStyle(
                                  fontSize: fontSettings.fontSize,
                                  fontWeight: fontSettings.fontWeight,
                                )),
                            Radio<String>(
                              value: "No",
                              groupValue: _airTicketRequisition,
                              onChanged: _canChangeAirTicketToNo()
                                  ? (value) => setState(
                                      () => _airTicketRequisition = value!)
                                  : null,
                            ),
                            Text(
                              "No",
                              style: TextStyle(
                                fontSize: fontSettings.fontSize,
                                fontWeight: fontSettings.fontWeight,
                                color: _canChangeAirTicketToNo()
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),

                        // ── Air Tickets Selector ───────────────
                        if (_airTicketRequisition == "Yes") ...[
                          const SizedBox(height: 10.0),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ValueListenableBuilder<String>(
                                valueListenable: airTicketsNotifier,
                                builder: (context, value, _) {
                                  return TextFormField(
                                    controller:
                                        TextEditingController(text: value),
                                    readOnly: true,
                                    style: TextStyle(
                                      fontSize: fontSettings.fontSize,
                                      fontWeight: fontSettings.fontWeight,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: "Select Air Tickets",
                                      labelStyle: TextStyle(
                                        fontSize: fontSettings.fontSize,
                                        fontWeight:
                                            fontSettings.fontWeight,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: _airTicketError != null
                                              ? Colors.red
                                              : const Color(0xFFDADDE3),
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12.0,
                                        vertical: -5.0,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: _airTicketError != null
                                              ? Colors.red
                                              : const Color(0xFFDADDE3),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: _airTicketError != null
                                              ? Colors.red
                                              : Constants.kPrimaryColor,
                                          width: 1.6,
                                        ),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: const Icon(
                                            Icons.arrow_drop_down),
                                        onPressed: () =>
                                            _openAirTicketsSelectorScreen(
                                                context),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (_airTicketError != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 12.0, top: 4.0),
                                  child: Text(
                                    _airTicketError!,
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize:
                                          fontSettings.fontSize * 0.75,
                                      fontWeight: fontSettings.fontWeight,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16.0),
                          selectedFlights.isEmpty
                              ? Center(
                                  heightFactor: 6.0,
                                  child: Text(
                                    'No air tickets available.',
                                    style: TextStyle(
                                      fontSize: fontSettings.fontSize,
                                      fontWeight: fontSettings.fontWeight,
                                    ),
                                  ),
                                )
                              : Column(
                                  children: selectedFlights.map((flight) {
                                    final index =
                                        selectedFlights.indexOf(flight);
                                    return FlightCardBallys(
                                      flight: flight,
                                      index: index,
                                      showDelete: false,
                                    );
                                  }).toList(),
                                ),
                        ],
                   
                        const SizedBox(height: 10.0),

                      
     // ── Hotels & Rooms Selector ────────────
                        ValueListenableBuilder<String>(
                          valueListenable: hotelRoomNotifier,
                          builder: (context, value, _) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller:
                                      TextEditingController(text: value),
                                  readOnly: true,
                                  style: TextStyle(
                                    fontSize: fontSettings.fontSize,
                                    fontWeight: fontSettings.fontWeight,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: "Select Hotels & Rooms",
                                    labelStyle: TextStyle(
                                      fontSize: fontSettings.fontSize,
                                      fontWeight: fontSettings.fontWeight,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: _hotelError != null
                                            ? Colors.red
                                            : const Color(0xFFDADDE3),
                                      ),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 12.0,
                                      vertical: -5.0,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: _hotelError != null
                                            ? Colors.red
                                            : const Color(0xFFDADDE3),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: _hotelError != null
                                            ? Colors.red
                                            : Constants.kPrimaryColor,
                                        width: 1.6,
                                      ),
                                    ),
                                    suffixIcon: IconButton(
                                      icon:
                                          const Icon(Icons.arrow_drop_down),
                                      onPressed: () =>
                                          _openHotelAndRoomSelectorBottomSheet(
                                              context),
                                    ),
                                  ),
                                ),
                                if (_hotelError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 12.0, top: 4.0),
                                    child: Text(
                                      _hotelError!,
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize:
                                            fontSettings.fontSize * 0.75,
                                        fontWeight: fontSettings.fontWeight,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 10.0),

                        // ── Selected Hotels List ───────────────
                        selectedHotels.isEmpty
                            ? Center(
                                heightFactor: 3.0,
                                child: Text(
                                  'No hotels selected.',
                                  style: TextStyle(
                                    fontSize: fontSettings.fontSize,
                                    color: Colors.grey.shade500,
                                    fontWeight: fontSettings.fontWeight,
                                  ),
                                ),
                              )
                            : Column(
                                children: selectedHotels.map((hotel) {
                                  return SizedBox(
                                    width: double.infinity,
                                    child: Card(
                                      elevation: 0,
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        side: const BorderSide(
                                          color: Color(0xFFE4D9C2),
                                        ),
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                        vertical: 8,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              hotel.hotelName!,
                                              style: TextStyle(
                                                fontSize:
                                                    fontSettings.fontSize *
                                                        1.125,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    const Color(0xFF1F2430),
                                              ),
                                            ),
                                            // Who the room is booked for, as
                                            // ticked in the selector sheet.
                                            if (hotel.assignedGuests
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Icon(
                                                    Icons.group,
                                                    size: 16,
                                                    color: Colors.blueGrey,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      hotel.assignedGuests
                                                          .map((g) => g.label)
                                                          .join(", "),
                                                      style: TextStyle(
                                                        fontSize: fontSettings
                                                            .fontSize,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors.blueGrey,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: "Category: ",
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: hotel
                                                        .roomCategoryName,
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          fontSettings
                                                              .fontWeight,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: "Room Type: ",
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: hotel.roomTypeName,
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          fontSettings
                                                              .fontWeight,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: "Arrival Date: ",
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: hotel.arrivalDate !=
                                                            null
                                                        ? DateFormat(
                                                                'yyyy-MM-dd')
                                                            .format(hotel
                                                                .arrivalDate!)
                                                        : '',
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          fontSettings
                                                              .fontWeight,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: "Departure Date: ",
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: hotel
                                                                .departureDate !=
                                                            null
                                                        ? DateFormat(
                                                                'yyyy-MM-dd')
                                                            .format(hotel
                                                                .departureDate!)
                                                        : '',
                                                    style: TextStyle(
                                                      fontSize: fontSettings
                                                          .fontSize,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          fontSettings
                                                              .fontWeight,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 20,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  "Guests: ${hotel.guestCount}",
                                                  style: TextStyle(
                                                    fontSize: fontSettings
                                                        .fontSize,
                                                    fontWeight: fontSettings
                                                        .fontWeight,
                                                  ),
                                                ),
                                                Text(
                                                  "Children: ${hotel.childrenCount ?? 0}",
                                                  style: TextStyle(
                                                    fontSize: fontSettings
                                                        .fontSize,
                                                    fontWeight: fontSettings
                                                        .fontWeight,
                                                  ),
                                                ),
                                                Text(
                                                  "Nights: ${hotel.noOfNights}",
                                                  style: TextStyle(
                                                    fontSize: fontSettings
                                                        .fontSize,
                                                    fontWeight: fontSettings
                                                        .fontWeight,
                                                  ),
                                                ),
                                                Text(
                                                  "Rooms: ${hotel.roomCount}",
                                                  style: TextStyle(
                                                    fontSize: fontSettings
                                                        .fontSize,
                                                    fontWeight: fontSettings
                                                        .fontWeight,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                       
                        const SizedBox(height: 10.0),

                        // ── Payment By ─────────────────────────
                        // Reservation-level: one answer covers every room and
                        // ticket on this reservation.
                        DropdownButtonFormField<String>(
                          key: ValueKey('payment_by_$_isBellagio'),
                          value: _paymentBy,
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: fontSettings.fontSize,
                            fontWeight: fontSettings.fontWeight,
                            color: Colors.black,
                          ),
                          hint: Text(
                            "Select Payment By",
                            style: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                          ),
                          decoration: InputDecoration(
                            labelText: "Payment By *",
                            labelStyle: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                            errorText: _paymentByError,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 8.0,
                            ),
                          ),
                          items: _paymentByItems(),
                          onChanged: (value) => setState(() {
                            _paymentBy = value;
                            _paymentByError = null;
                          }),
                        ),
                        const SizedBox(height: 10.0),

                        // ── Hamoos Contact Person ──────────────
                        if (!_isBellagio) ...[
                          DropdownSearch<String>(
                            items: (filter, infiniteScrollProps) =>
                                _contactPersons
                                    .where((item) => item
                                        .toLowerCase()
                                        .contains(filter.toLowerCase()))
                                    .toList(),
                            selectedItem: _selectedContactPerson,
                            onChanged: (value) => setState(
                              () => _selectedContactPerson = value,
                            ),
                            decoratorProps: DropDownDecoratorProps(
                              decoration: InputDecoration(
                                labelText: "Hamoos Contact Person",
                                labelStyle: TextStyle(
                                  fontSize: fontSettings.fontSize,
                                  fontWeight: fontSettings.fontWeight,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                prefixIcon: const Icon(Icons.person_outline),
                              ),
                            ),
                            popupProps: PopupProps.menu(
                              showSearchBox: true,
                              searchFieldProps: const TextFieldProps(
                                decoration: InputDecoration(
                                  hintText: "Search contact person",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10.0),
                        ],

                        // ── Request Approval From ──────────────
                        _buildAuthorizationDropdown(fontSettings),
                        const SizedBox(height: 10.0),

                        // ── Remarks ────────────────────────────
                        TextFormField(
                          controller: _remarksController,
                          style: TextStyle(
                            fontSize: fontSettings.fontSize,
                            fontWeight: fontSettings.fontWeight,
                          ),
                          decoration: InputDecoration(
                            alignLabelWithHint: true,
                            labelText: "Remarks",
                            labelStyle: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                            ),
                            hintText: "Enter additional details...",
                            hintStyle: TextStyle(
                              fontSize: fontSettings.fontSize,
                              fontWeight: fontSettings.fontWeight,
                              color: Colors.grey,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                        ),
                        //const SizedBox(height: 10.0),
                        // TextFormField(
                        //   controller: _reservationnewnumberController,
                        //   readOnly: _isEditMode,
                        //   style: TextStyle(
                        //     fontSize: fontSettings.fontSize,
                        //     fontWeight: fontSettings.fontWeight,
                        //   ),
                        //   decoration: InputDecoration(
                        //     labelText: "Manual Reservation No",
                        //     labelStyle: TextStyle(
                        //       fontSize: fontSettings.fontSize,
                        //       fontWeight: fontSettings.fontWeight,
                        //     ),
                        //     border: const OutlineInputBorder(),
                        //     contentPadding: const EdgeInsets.symmetric(
                        //       horizontal: 12.0,
                        //       vertical: -5.0,
                        //     ),
                        //   ),
                        //   // validator: (value) {
                        //   //   if (value == null || value.trim().isEmpty) {
                        //   //     return "Manual Reservation Number is required";
                        //   //   }
                        //   //   return null;
                        //   // },
                        // ),
                        const SizedBox(height: 16.0),

                        // ── Confirm / Update Button ────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _confirmReservation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: !_isEditMode
                                  ? Constants.kSecondaryColor
                                  : Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.done, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  !_isEditMode
                                      ? "Confirm Reservation"
                                      : "Update Reservation",
                                  style: TextStyle(
                                    fontSize: fontSettings.fontSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Loading Overlay ──────────────────────────
                if (_isLoading)
                  Container(
                    decoration: const BoxDecoration(
                      color: Color.fromARGB(135, 117, 115, 115),
                    ),
                    child: const Center(
                      child: RefreshProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Constants.kSecondaryColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Editable form state for one extra member sharing the on-screen guest's
/// package. Owns its own controllers, so it must be disposed when the row is
/// removed or the form is cleared.
class _ExtraMemberRow {
  final TextEditingController midNumberController;
  final TextEditingController nameController;

  /// This member's own package amount — they share the primary guest's hotels,
  /// tickets and dates but are billed their own package.
  final TextEditingController packageAmountController;
  String prefix;
  bool hasFamilyMembers;

  /// Ticked when this member is on a shared package, which makes an empty
  /// [packageAmountController] a valid state rather than a missing field. The
  /// amount stays editable either way — a shared member may still have one —
  /// so the tick is saved as its own true/false rather than inferred.
  bool sharedPackage;

  _ExtraMemberRow({
    this.prefix = "BM",
    String midNumber = "",
    String name = "",
    this.hasFamilyMembers = false,
    String packageAmount = "",
    this.sharedPackage = false,
  })  : midNumberController = TextEditingController(text: midNumber),
        nameController = TextEditingController(text: name),
        packageAmountController = TextEditingController(text: packageAmount);

  /// The member ID as the API expects it: prefixed everywhere except the
  /// numeric-only locations, which have no prefix dropdown at all.
  String fullMid({required bool numericOnly}) {
    final number = midNumberController.text.trim();
    if (number.isEmpty) return "";
    return numericOnly ? number : "$prefix$number";
  }

  void dispose() {
    midNumberController.dispose();
    nameController.dispose();
    packageAmountController.dispose();
  }
}