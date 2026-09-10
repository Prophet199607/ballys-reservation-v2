import 'package:ballys_reservation_app/components/air_ticket_class_count_selector.dart';
import 'package:ballys_reservation_app/components/custom_airport_field.dart';
import 'package:ballys_reservation_app/components/flight_card_ballys.dart';
import 'package:ballys_reservation_app/components/passport_upload_widget_ballys.dart';
import 'package:ballys_reservation_app/core/constants.dart';
import 'package:ballys_reservation_app/data/repositories/airport_repository.dart';
import 'package:ballys_reservation_app/providers/selected_passport_provider_ballys.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:ballys_reservation_app/models/airport_search_response.dart';
import 'package:ballys_reservation_app/models/guest_reservation_entryBallys.dart';
import 'package:ballys_reservation_app/models/reservation/air_ticket_class_count.dart';
import 'package:ballys_reservation_app/models/reservation/assigned_guest.dart';
import 'package:ballys_reservation_app/models/reservation/airline_response.dart';
import 'package:ballys_reservation_app/models/reservation/flight_bookng_ballys.dart';
import 'package:ballys_reservation_app/models/reservation/flight_sector_entry.dart';
import 'package:ballys_reservation_app/providers/airports_provider.dart';
import 'package:ballys_reservation_app/providers/selected_flight_provider_ballys.dart';
// import 'package:ballys_reservation_app/providers/selected_passport_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dropdown_search/dropdown_search.dart';

class AirTicketsSelectionBallysScreen extends ConsumerStatefulWidget {
  final AirportRepository airportRepository;
  final String arrivalDate;
  final String departureDate;

  /// Everyone already on the reservation, listed at the top of the form so a
  /// ticket can be assigned to the guest — or guests — it is booked for.
  final List<AccompanyingMember> guests;

  const AirTicketsSelectionBallysScreen(
    this.airportRepository, {
    super.key,
    required this.arrivalDate,
    required this.departureDate,
    this.guests = const [],
  });

  @override
  ConsumerState<AirTicketsSelectionBallysScreen> createState() =>
      _AirTicketsSelectionBallysScreenState();
}

class _AirTicketsSelectionBallysScreenState
    extends ConsumerState<AirTicketsSelectionBallysScreen> {
  late String _arrivalDate;
  late String _departureDate;
  final TextEditingController _departureFromController =
      TextEditingController();
  final TextEditingController _departureToController = TextEditingController();
  final TextEditingController _returnFromController = TextEditingController();
  final TextEditingController _returnToController = TextEditingController();
  final TextEditingController _departureDateController =
      TextEditingController();
  final TextEditingController _arrivalDateController = TextEditingController();

  final TextEditingController _hotelRoomController = TextEditingController();
  final TextEditingController _dateRangeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final ValueNotifier<List<Map<String, dynamic>>> roomCategoriesNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  final ValueNotifier<List<Map<String, dynamic>>> roomTypesNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  /// Airline master list (API 90156) and the one picked for this ticket.
  List<AirlineResponse> _airlines = [];
  AirlineResponse? _selectedAirline;
  bool _airlinesLoading = false;
  Key _airlineKey = UniqueKey();


  /// Passports picked on this screen, kept per guest by [_guestKey] so each
  /// member's bio page is filed against them. Only the guests ticked for the
  /// ticket being added are shown an uploader, so adding a ticket — which
  /// clears the ticks — clears the upload area and leaves the next guest a
  /// blank one, while what has already been picked stays put under its owner.
  final Map<String, List<PassportFileBallys>> _passportsByGuest = {};

  /// Passports no guest on this screen has an uploader for: picked while the
  /// reservation had nobody to name yet (the first guest is still being filled
  /// in), or tagged with a member who has since left the reservation. They are
  /// carried through untouched so nothing already picked is dropped.
  List<PassportFileBallys> _otherPassports = [];

  /// Set when a ticket was added or the changes accepted with a guest still
  /// missing their bio page, which marks the upload area red until one is
  /// picked. A ticket is issued against a passport, so it is required.
  bool _passportError = false;

  /// Bellagio (bty.world) hides the Hamoos contact person dropdown.
  bool _isBellagio = false;

  /// Ballys (non–bty.world) shows extra air-ticket options: Meal, Extra
  /// Legroom Seat and Gold Route.
  bool _isBallys = false;

  @override
  void initState() {
    super.initState();
    flightList = List.from(ref.read(selectedFlightBallysProvider));
    _restorePassports(ref.read(selectedPassportBallysProvider));
    _preselectSoleGuest();
    _syncHeadCountsToGuests();
    _getAirports();
    _loadBrand();
    _loadAirlines();
    _arrivalDate = widget.arrivalDate;
    _departureDate = widget.departureDate;
  }

  Future<void> _loadBrand() async {
    final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
    if (mounted) {
      setState(() {
        _isBellagio = apiUrl.contains('bty.world');
        _isBallys = !_isBellagio;
      });
    }
  }

  static const String _defaultToAirportCode = "CMB";

  Airport? _departureFromAirport;
  Airport? _departureToAirport;
  Airport? _returnFromAirport;
  Airport? _returnToAirport;

  Key _departureFromAirportKey = UniqueKey();
  Key _departureToAirportKey = UniqueKey();

  bool _isSameAsHotelForDeparture = false;
  bool _isSameAsHotelForArrival = false;

  String _silkRouteFacility = "No";

  /// Which leg the Silk / Gold Route facility applies to. Only asked for — and
  /// only sent — while that facility is set to Yes.
  String _silkRouteType = "Arrival";
  String _goldRouteType = "Arrival";

  /// Meal requirement, asked for only while Meal is Yes.
  final TextEditingController _mealRemarkController = TextEditingController();

  String _airportTranspotation = "No";

  /// The classes on the ticket being added, each with its own seat count. A
  /// ticket can mix them, so this is a list rather than a single pick; the
  /// first entry is what goes out as the ticket's primary class.
  List<AirTicketClassCount> _ticketClasses = [];

  // Validation error flags for required fields
  bool _departureFromError = false;
  bool _departureToError = false;
  bool _airTicketClassError = false;
  bool _arrivalDateError = false;
  bool _departureDateError = false;
  bool _guestAssignError = false;

  /// The guests the ticket being added is booked for, by [_guestKey]. A ticket
  /// can go to one guest or to several, so this is a set rather than a single
  /// pick.
  final Set<String> _assignedGuestKeys = {};

  /// Identifies a guest across rebuilds. BM number alone is not enough — a
  /// member typed in but not yet searched can still be sitting there nameless.
  String _guestKey(AccompanyingMember guest) =>
      "${guest.mid.trim()}|${guest.guestName.trim()}";

  /// The ticked guests, in the order they appear on the reservation. The first
  /// one owns the ticket; the rest each get their own copy of it on save.
  List<AssignedGuest> _selectedAssignedGuests() {
    return widget.guests
        .where((guest) => _assignedGuestKeys.contains(_guestKey(guest)))
        .map((guest) => AssignedGuest(
            mid: guest.mid.trim(), guestName: guest.guestName.trim()))
        .toList();
  }

  /// Ticks the guests a ticket already names, matching on BM number so a ticket
  /// pulled back for editing keeps its assignment even if the name was tidied
  /// up since.
  void _applyAssignedGuests(List<AssignedGuest> assigned) {
    _assignedGuestKeys.clear();
    for (final guest in widget.guests) {
      if (assigned.any((a) => _namesGuest(a, guest))) {
        _assignedGuestKeys.add(_guestKey(guest));
      }
    }
  }

  /// Whether [assigned] is [guest] — by BM number where there is one, by name
  /// for a member typed in but never searched.
  bool _namesGuest(AssignedGuest assigned, AccompanyingMember guest) {
    final mid = assigned.mid.trim();
    return (mid.isNotEmpty && mid == guest.mid.trim()) ||
        (mid.isEmpty && assigned.guestName.trim() == guest.guestName.trim());
  }

  /// Guests who already have a ticket on this reservation. A guest takes one
  /// ticket, so they are shown greyed out rather than offered again — the
  /// ticket being edited is skipped, so its own guests stay pickable.
  Set<String> _guestsOnOtherTickets() {
    final taken = <String>{};
    for (var i = 0; i < flightList.length; i++) {
      if (editMode && i == editIndex) continue;
      for (final guest in widget.guests) {
        if (flightList[i].assignedGuests.any((a) => _namesGuest(a, guest))) {
          taken.add(_guestKey(guest));
        }
      }
    }
    return taken;
  }

  /// A single guest on the reservation is the only one a ticket can be for, so
  /// it starts ticked rather than making every add a two-step job — unless that
  /// guest already has a ticket.
  void _preselectSoleGuest() {
    if (widget.guests.length != 1) return;
    final key = _guestKey(widget.guests.first);
    if (_guestsOnOtherTickets().contains(key)) return;
    _assignedGuestKeys.add(key);
  }

  /// Seats this ticket may hold across all classes: one per ticked guest, so a
  /// lone guest gets a single class and a single seat. Null is no ceiling —
  /// what a guest who brings family needs, since the family flying with them is
  /// counted on the ticket, not here.
  int? get _maxTicketSeats {
    if (_ticketHasFamily) return null;
    final assigned = _assignedGuestKeys.length;
    return assigned == 0 ? null : assigned;
  }

  /// Whether any guest this ticket is booked for brings family along. Without
  /// family there is nobody on the ticket but the guests themselves.
  bool get _ticketHasFamily => widget.guests
      .where((guest) => _assignedGuestKeys.contains(_guestKey(guest)))
      .any((guest) => guest.hasFamilyMembers);

  /// Head counts are the guests and nothing else once the ticket is assigned to
  /// guests who bring no family: one seat each, no children, no infants. The
  /// counters are read-only then, so the numbers can't drift off the ticket.
  bool get _headCountsLocked =>
      _assignedGuestKeys.isNotEmpty && !_ticketHasFamily;

  /// Pins the head counts to the ticked guests while [_headCountsLocked]. Call
  /// after every change to the assignment — ticking a guest who brings family
  /// hands the counters back, unticking them takes the counters away again.
  void _syncHeadCountsToGuests() {
    if (!_headCountsLocked) return;
    numberOfGuests = _assignedGuestKeys.length;
    numberOfChildren = 0;
    numberOfInfants = 0;
  }

  /// Unticking a guest can leave more seats on the ticket than the rest of them
  /// can hold, so the classes are pared back to fit — counts first, then whole
  /// classes off the end.
  void _trimTicketClassesToLimit() {
    final maxSeats = _maxTicketSeats;
    if (maxSeats == null) return;
    final trimmed = <AirTicketClassCount>[];
    var used = 0;
    for (final item in _ticketClasses) {
      final remaining = maxSeats - used;
      if (remaining < 1) break;
      final entry =
          item.count > remaining ? item.copyWith(count: remaining) : item;
      trimmed.add(entry);
      used += entry.count;
    }
    // Within the ceiling this is the same list it started as.
    _ticketClasses = trimmed;
  }

  /// Who the ticket being added is for: every guest on the reservation, ticked
  /// one by one or several at a time. Each ticked guest gets the ticket booked
  /// against their BM number.
  Widget _guestAssignment() {
    // Guests already on another ticket are along for the ride but can't be
    // picked, so "Select all" and its label only ever count the rest.
    final locked = _guestsOnOtherTickets();
    final selectable = widget.guests
        .where((guest) => !locked.contains(_guestKey(guest)))
        .toList();
    final allSelected = selectable.isNotEmpty &&
        selectable
            .every((guest) => _assignedGuestKeys.contains(_guestKey(guest)));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _guestAssignError ? Colors.red : const Color(0xFFDADDE3),
          width: _guestAssignError ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.group, size: 18, color: Constants.kPrimaryColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Assign this ticket to (${_assignedGuestKeys.length}/${selectable.length})",
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (selectable.length > 1)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _assignedGuestKeys.clear();
                      if (!allSelected) {
                        _assignedGuestKeys.addAll(selectable.map(_guestKey));
                      }
                      _guestAssignError = false;
                      _trimTicketClassesToLimit();
                      _syncHeadCountsToGuests();
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    allSelected ? "Clear" : "Select all",
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ...widget.guests.map((guest) =>
              _guestAssignmentRow(guest, locked.contains(_guestKey(guest)))),
          if (selectable.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Every guest already has a ticket",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          if (_guestAssignError)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Select at least one guest for this ticket",
                style: TextStyle(fontSize: 13, color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  /// One guest. [locked] means they already have a ticket, so the row is greyed
  /// out and says so instead of offering the tick again.
  Widget _guestAssignmentRow(AccompanyingMember guest, bool locked) {
    final key = _guestKey(guest);
    final selected = _assignedGuestKeys.contains(key);
    final label = [
      if (guest.mid.trim().isNotEmpty) guest.mid.trim(),
      if (guest.guestName.trim().isNotEmpty) guest.guestName.trim(),
    ].join(" — ");

    return InkWell(
      onTap: locked
          ? null
          : () {
              setState(() {
                if (selected) {
                  _assignedGuestKeys.remove(key);
                } else {
                  _assignedGuestKeys.add(key);
                }
                _guestAssignError = false;
                _trimTicketClassesToLimit();
                _syncHeadCountsToGuests();
              });
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Checkbox(
                value: selected,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: locked
                    ? null
                    : (checked) {
                        setState(() {
                          if (checked == true) {
                            _assignedGuestKeys.add(key);
                          } else {
                            _assignedGuestKeys.remove(key);
                          }
                          _guestAssignError = false;
                          _trimTicketClassesToLimit();
                          _syncHeadCountsToGuests();
                        });
                      },
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: locked ? Colors.grey : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (locked) ...[
              Icon(Icons.check_circle_outline,
                  size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                "Already has a ticket",
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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
                guest.hasFamilyMembers ? "Family included" : "No family",
                style: TextStyle(
                  fontSize: 13,
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

  // ── Passports ─────────────────────────────────────────────────────────────

  /// Files the screen to the guest each one names, so re-opening the screen
  /// shows every member's passport back under that member. A file naming
  /// nobody on the reservation is carried through as-is rather than being
  /// handed to a guest it does not belong to.
  void _restorePassports(List<PassportFileBallys> files) {
    _passportsByGuest.clear();
    _otherPassports = [];

    for (final file in files) {
      final bm = file.guestBmNumber.trim();
      AccompanyingMember? owner;
      if (bm.isNotEmpty) {
        for (final guest in widget.guests) {
          if (guest.mid.trim() == bm) {
            owner = guest;
            break;
          }
        }
      }

      if (owner == null) {
        _otherPassports.add(file);
      } else {
        _passportsByGuest.putIfAbsent(_guestKey(owner), () => []).add(file);
      }
    }
  }

  /// Every passport picked on this screen, in the order the guests appear on
  /// the reservation, each still naming its owner.
  List<PassportFileBallys> _allPassports() {
    final files = <PassportFileBallys>[];
    for (final guest in widget.guests) {
      files.addAll(_passportsByGuest[_guestKey(guest)] ?? const []);
    }
    // Guests dropped from the reservation take their passports with them, so
    // only the buckets above go out — plus whatever named nobody to begin with.
    files.addAll(_otherPassports);
    return files;
  }

  /// The bio pages for this ticket's guests: one uploader per ticked guest, so
  /// a passport is filed against the member it belongs to instead of landing
  /// on the guest that owns the reservation. Adding the ticket clears the
  /// ticks, which clears the uploaders — the next guest gets an empty one, and
  /// re-ticking a guest brings their pages back.
  Widget _passportSection() {
    // No guests to name yet (the first one is still being filled in), so the
    // passport goes to whoever ends up owning the entry.
    if (widget.guests.isEmpty) {
      return PassportUploadWidgetBallys(
        initialFiles: _otherPassports,
        onFilesChanged: (files) {
          setState(() {
            _otherPassports = List.from(files);
            _passportError = false;
          });
        },
      );
    }

    final selected = widget.guests
        .where((guest) => _assignedGuestKeys.contains(_guestKey(guest)))
        .toList();

    if (selected.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _passportError ? Colors.red : Colors.grey.shade300,
            width: _passportError ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Passport Bio Data Page",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Select a guest above to upload their passport bio page.",
              style: TextStyle(
                fontSize: 14,
                color: _passportError ? Colors.red : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    final uploaders = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < selected.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _guestPassportUploader(selected[i]),
        ],
      ],
    );

    // Untouched until a save complains, so the uploaders keep their own look
    // until there is something to point at.
    if (!_passportError) return uploaders;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red, width: 1.4),
      ),
      child: uploaders,
    );
  }

  /// One guest's uploader, headed with their name so it is plain whose bio
  /// page is being picked.
  Widget _guestPassportUploader(AccompanyingMember guest) {
    final key = _guestKey(guest);
    final label = [
      if (guest.guestName.trim().isNotEmpty) guest.guestName.trim(),
      if (guest.mid.trim().isNotEmpty) guest.mid.trim(),
    ].join(" — ");

    return PassportUploadWidgetBallys(
      // Keyed by guest so switching who the ticket is for rebuilds the
      // uploader with that guest's own files rather than keeping the last
      // guest's on screen.
      key: ValueKey("passport-$key"),
      title: label.isNotEmpty
          ? "Passport Bio Data Page — $label"
          : "Passport Bio Data Page",
      guestBmNumber: guest.mid.trim(),
      guestName: guest.guestName.trim(),
      initialFiles: _passportsByGuest[key] ?? const [],
      onFilesChanged: (files) {
        setState(() {
          _passportsByGuest[key] = List.from(files);
          _passportError = false;
        });
      },
    );
  }

  bool _isLoading = false;
  bool _isRoundTrip = false;

  /// No direct flight is available, so the ticket routes through transit
  /// airports the user adds between From and To on each leg.
  bool _isMultiSector = false;
  final List<FlightSectorEntry> _departureSectors = [];
  final List<FlightSectorEntry> _returnSectors = [];
  bool _visa = false;
  bool _meal = false;
  bool _extraLegroomSeat = false;
  bool _goldRoute = false;
  bool editMode = false;
  int? editIndex;

  DateTimeRange? selectedDateRange;
  DateTime? arrivalDate;
  DateTime? departureDate;

  double? selectedHotelId;
  String? selectedHotelName;
  Map<String, dynamic>? selectedHotel;

  int? selectedRoomCategoryId;
  String? selectedRoomCategoryName;
  Map<String, dynamic>? selectedRoomCategory;

  int? selectedRoomTypeId;
  String? selectedRoomTypeName;
  String? sRoomTypeName;
  String? sMealPlanName;
  Map<String, dynamic>? selectedRoomType;

  int? selectedHotelAndRoom;
  int? numberOfNights;

  int numberOfGuests = 1;
  int numberOfChildren = 0;
  int numberOfInfants = 0;
  int numberOfRooms = 1;

  List<FlightBookingBallys> flightList = [];
  void _selectDateRange(BuildContext context) async {
    DateTimeRange? pickedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: selectedDateRange,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDateRange != null) {
      setState(() {
        selectedDateRange = pickedDateRange;
        numberOfNights = pickedDateRange.duration.inDays;
        arrivalDate = pickedDateRange.start;
        departureDate = pickedDateRange.end;
        _dateRangeController.text =
            "${DateFormat('yyyy-MM-dd').format(pickedDateRange.start)} - ${DateFormat('yyyy-MM-dd').format(pickedDateRange.end)}";
      });    }
  }

  void _updateAdults(count) {
    if (_headCountsLocked) return;
    if (count >= 1) {
      setState(() {
        numberOfGuests = count;
      });    }
  }

  void _updateChildren(count) {
    if (_headCountsLocked) return;
    if (count >= 0) {
      setState(() {
        numberOfChildren = count;
      });    }
  }

  void _updateInfants(count) {
    if (_headCountsLocked) return;
    if (count >= 0) {
      setState(() {
        numberOfInfants = count;
      });    }
  }

  void _updateRooms(count) {
    if (count >= 1) {
      setState(() {
        numberOfRooms = count;
      });    }
  }

  Future<void> getSelectedHotelRoomCategories(double hotelId,
      {bool clearSelection = true}) async {
    try {
      final response =
          await widget.airportRepository.getSelectedHotelRoomCategories(hotelId);
      roomCategoriesNotifier.value =
          response.map((category) => category.toJson()).toList();

      if (clearSelection) {
        selectedRoomCategory = null;
        selectedRoomCategoryId = null;
        selectedRoomCategoryName = null;
        selectedRoomType = null;
        selectedRoomTypeId = null;
        selectedRoomTypeName = null;
        roomTypesNotifier.value = [];
      }
    } catch (e) {
      roomCategoriesNotifier.value = [];
    }
  }

  Future<void> getSelectedHotelCategoryRoomTypes(
      double hotelId, int categoryId,
      {bool clearSelection = true}) async {
    try {
      final response = await widget.airportRepository
          .getSelectedHotelCategoryRoomTypes(hotelId, categoryId);
      roomTypesNotifier.value =
          response.map((category) => category.toJson()).toList();

      if (clearSelection) {
        selectedRoomType = null;
        selectedRoomTypeId = null;
        selectedRoomTypeName = null;
      }
    } catch (e) {
      roomTypesNotifier.value = [];
    }
  }

  /// The airline list is the same whatever route is picked, so it is fetched
  /// once when the screen opens.
  Future<void> _loadAirlines() async {
    setState(() => _airlinesLoading = true);
    try {
      final airlines = await widget.airportRepository.getAirlines();
      if (!mounted) return;
      setState(() {
        _airlines = airlines;
        _airlinesLoading = false;
        _airlineKey = UniqueKey();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _airlines = [];
        _airlinesLoading = false;
        _airlineKey = UniqueKey();
      });
    }
  }

  /// The list entry matching a name saved on an earlier ticket, so editing one
  /// shows its airline selected instead of blank.
  AirlineResponse? _airlineByName(String? name) {
    final target = name?.trim();
    if (target == null || target.isEmpty) return null;
    for (final airline in _airlines) {
      if (airline.airlineName.trim().toLowerCase() == target.toLowerCase()) {
        return airline;
      }
    }
    return null;
  }

  void _setHotel(flight) {
    selectedHotel = flight;
    selectedHotelId = flight?['Hotel_IID'];
    selectedHotelName = flight?['HotelName'] ?? '';
    if (selectedHotelId != null) {
      roomCategoriesNotifier.value = [];
      roomTypesNotifier.value = [];
      getSelectedHotelRoomCategories(selectedHotelId!);
    }
  }

  void _setRoomCategory(roomCategory) {
    selectedRoomCategory = roomCategory;
    selectedRoomCategoryId = roomCategory?['CatCode'];
    selectedRoomCategoryName = roomCategory?['CatName'] ?? '';    if (selectedHotelId != null && selectedRoomCategoryId != null) {
      roomTypesNotifier.value = [];
      getSelectedHotelCategoryRoomTypes(
          selectedHotelId!, selectedRoomCategoryId!);
    }
  }

  void _setRoomType(roomtype) {
    selectedRoomType = roomtype;
    selectedRoomTypeId = roomtype?['ID'];
    sRoomTypeName = roomtype?['RoomType'] ?? '';
    sMealPlanName = roomtype?['MealPlan'] ?? '';
    selectedRoomTypeName = '$sRoomTypeName - $sMealPlanName';  }

  void __editFlightDetails(FlightBookingBallys flight, int index) {
    setState(() {
      editMode = true;
      editIndex = index;
      numberOfGuests = flight.guestCount;
      numberOfChildren = flight.childrenCount;
      numberOfInfants = flight.infantCount;

      // Tickets saved before classes could be mixed carry no breakdown; the
      // model builds one from their single class, so this is never empty.
      _ticketClasses = List<AirTicketClassCount>.from(flight.ticketClasses);

      final dateFormat = DateFormat('yyyy-MM-dd');
      _arrivalDateController.text = flight.arrivalDate != null
          ? dateFormat.format(flight.arrivalDate!)
          : '';
      _departureDateController.text = flight.departureDate != null
          ? dateFormat.format(flight.departureDate!)
          : '';
      // Tick only where the ticket really does run to the reservation's own
      // dates, so the box matches what is in the field above it.
      _isSameAsHotelForArrival = _arrivalDateController.text.isNotEmpty &&
          _arrivalDateController.text == _arrivalDate;
      _isSameAsHotelForDeparture = _departureDateController.text.isNotEmpty &&
          _departureDateController.text == _departureDate;

      _silkRouteFacility = flight.silkRoute == 1 ? "Yes" : "No";
      _airportTranspotation = flight.airportTransportation == 1 ? "Yes" : "No";
      _isRoundTrip = flight.isRoundTrip;
      _visa = flight.visa;
      _meal = flight.meal;
      _extraLegroomSeat = flight.extraLegroomSeat;
      _goldRoute = flight.goldRoute;
      // Blank on flights saved before these were captured — fall back to the
      // default leg rather than leaving the radios unselected.
      _silkRouteType = flight.silkRouteType?.trim().isNotEmpty == true
          ? flight.silkRouteType!
          : "Arrival";
      _goldRouteType = flight.goldRouteType?.trim().isNotEmpty == true
          ? flight.goldRouteType!
          : "Arrival";
      _mealRemarkController.text = flight.mealRemark ?? "";

      _departureFromAirport = flight.airports!.departure?.dFrom.toAirport();
      _departureToAirport = flight.airports!.departure?.dTo.toAirport();
      _returnFromAirport = flight.airports!.returnFlight?.rFrom.toAirport();
      _returnToAirport = flight.airports!.returnFlight?.rTo.toAirport();

      _departureFromAirportKey = UniqueKey();
      _departureToAirportKey = UniqueKey();

      // Flights saved before Multi Sector existed carry no stops; ones that do
      // carry stops are multi sector whatever the flag says.
      _isMultiSector = flight.isMultiSector ||
          flight.departureSectors.isNotEmpty ||
          flight.returnSectors.isNotEmpty;
      _departureSectors
        ..clear()
        ..addAll(flight.departureSectors.map((sector) => FlightSectorEntry(
            airport: sector.toAirport(), date: sector.sectorDate)));
      _returnSectors
        ..clear()
        ..addAll(flight.returnSectors.map((sector) => FlightSectorEntry(
            airport: sector.toAirport(), date: sector.sectorDate)));

      _selectedAirline = _airlineByName(flight.airLine);
      _airlineKey = UniqueKey();

      _applyAssignedGuests(flight.assignedGuests);
      _syncHeadCountsToGuests();
      _guestAssignError = false;
    });
  }

  /// The picked stops of a leg, in the order the rows are shown. Rows with no
  /// airport are dropped — [_saveTicketSelection] rejects those first anyway.
  List<AirportInfo> _sectorInfos(List<FlightSectorEntry> sectors) {
    return sectors
        .where((sector) => sector.airport != null)
        .map((sector) => AirportInfo(
              airportCode: sector.airport!.airportCode ?? '',
              cityName: sector.airport!.cityName ?? '',
              airportName: sector.airport!.airportName ?? '',
              country: sector.airport!.country ?? '',
              sectorDate: sector.date,
            ))
        .toList();
  }

  /// Whether every guest ticked for the ticket being added has their bio page
  /// picked. With nobody to tick yet the page goes to whoever ends up owning
  /// the ticket, so one file is all that can be asked for.
  bool _requireTicketPassports() {
    final selected = widget.guests
        .where((guest) => _assignedGuestKeys.contains(_guestKey(guest)))
        .toList();

    if (selected.isEmpty) {
      if (_otherPassports.isNotEmpty) return true;
      _reportMissingPassport();
      return false;
    }

    for (final guest in selected) {
      if ((_passportsByGuest[_guestKey(guest)] ?? const []).isNotEmpty) {
        continue;
      }
      _reportMissingPassport(guest: guest);
      return false;
    }
    return true;
  }

  /// Whether every guest already booked on a ticket has their bio page picked.
  /// The per-ticket check above covers tickets added on this visit; this one
  /// also catches tickets restored from a reservation that never had one.
  bool _requireAllPassports() {
    if (widget.guests.isEmpty) {
      if (_otherPassports.isNotEmpty) return true;
      _reportMissingPassport();
      return false;
    }

    for (final guest in widget.guests) {
      final booked = flightList
          .any((flight) => flight.assignedGuests.any((a) => _namesGuest(a, guest)));
      if (!booked) continue;
      if ((_passportsByGuest[_guestKey(guest)] ?? const []).isNotEmpty) {
        continue;
      }
      _reportMissingPassport(guest: guest);
      return false;
    }
    return true;
  }

  /// Marks the upload area and says whose page is missing — a ticket already
  /// added names its guest, so the fix is to edit that ticket, which ticks them
  /// back and brings their uploader up.
  void _reportMissingPassport({AccompanyingMember? guest}) {
    final who = guest == null
        ? ""
        : (guest.guestName.trim().isNotEmpty
            ? guest.guestName.trim()
            : guest.mid.trim());
    setState(() => _passportError = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Please upload the passport bio data page"
          "${who.isEmpty ? '' : ' for $who'}.",
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _removeFlight(int index) {
    setState(() {
      flightList.removeAt(index);
    });
  }

  void _saveTicketSelection() {
    final bool departureFromMissing = _departureFromAirport == null;
    final bool departureToMissing = _departureToAirport == null;
    final bool classMissing = _ticketClasses.isEmpty;
    final bool arrivalMissing = _arrivalDateController.text == "";
    // Departure date is only required for round trips; optional for one-way.
    final bool departureMissing =
        _isRoundTrip && _departureDateController.text == "";
    // A ticket has to name who it is for, but only once there is somebody on
    // the reservation to name — the very first guest is still being filled in.
    final bool guestsMissing =
        widget.guests.isNotEmpty && _assignedGuestKeys.isEmpty;

    if (departureFromMissing ||
        departureToMissing ||
        classMissing ||
        arrivalMissing ||
        departureMissing ||
        guestsMissing) {
      setState(() {
        _departureFromError = departureFromMissing;
        _departureToError = departureToMissing;
        _airTicketClassError = classMissing;
        _arrivalDateError = arrivalMissing;
        _departureDateError = departureMissing;
        _guestAssignError = guestsMissing;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all required fields.")),
      );
      return;
    }

    // A round trip without both return airports would save as a one-way
    // silently, so ask for them instead.
    if (_isRoundTrip &&
        (_returnFromAirport == null || _returnToAirport == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select the return From and To airports.")),
      );
      return;
    }

    // Every added stop has to name an airport and the day it is flown, or the
    // route it describes has a hole in it.
    if (_isMultiSector) {
      final bool hasEmptyStop = _departureSectors.any((s) => s.airport == null) ||
          (_isRoundTrip && _returnSectors.any((s) => s.airport == null));
      final bool hasUndatedStop = _departureSectors.any((s) => s.date == null) ||
          (_isRoundTrip && _returnSectors.any((s) => s.date == null));
      final bool hasNoStops = _departureSectors.isEmpty && _returnSectors.isEmpty;
      if (hasEmptyStop || hasUndatedStop || hasNoStops) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hasNoStops
                ? "Please add at least one stop, or turn Multi Sector off."
                : hasEmptyStop
                    ? "Please select an airport for every stop."
                    : "Please select a date for every stop."),
          ),
        );
        return;
      }
    }

    // A ticket cannot be issued without the traveller's bio page, and the
    // uploader for it is on screen only while its guest is ticked — so it is
    // asked for here rather than after the ticket is banked.
    if (!_requireTicketPassports()) return;

    // Cost is optional — no blocking if not calculated

    final FlightAirport airport = FlightAirport(
        departure: Departure(
            dFrom: AirportInfo(
              airportCode: _departureFromAirport!.airportCode!,
              cityName: _departureFromAirport!.cityName!,
              airportName: _departureFromAirport!.airportName!,
              country: _departureFromAirport!.country!,
            ),
            dTo: AirportInfo(
              airportCode: _departureToAirport!.airportCode!,
              cityName: _departureToAirport!.cityName!,
              airportName: _departureToAirport!.airportName!,
              country: _departureToAirport!.country!,
            )),
        returnFlight: _returnFromAirport != null && _returnToAirport != null
            ? ReturnFlight(
                rFrom: AirportInfo(
                  airportCode: _returnFromAirport!.airportCode!,
                  cityName: _returnFromAirport!.cityName!,
                  airportName: _returnFromAirport!.airportName!,
                  country: _returnFromAirport!.country!,
                ),
                rTo: AirportInfo(
                  airportCode: _returnToAirport!.airportCode!,
                  cityName: _returnToAirport!.cityName!,
                  airportName: _returnToAirport!.airportName!,
                  country: _returnToAirport!.country!,
                ))
            : null);

    final flightBooking = FlightBookingBallys(
      guestCount: numberOfGuests,
      childrenCount: numberOfChildren,
      infantCount: numberOfInfants,
      // The first picked class stays the ticket's primary one; the full
      // breakdown goes out beside it.
      airTicketClass: _ticketClasses.first.id,
      arrivalDate: DateFormat("yyyy-MM-dd").parse(_arrivalDateController.text),
      departureDate: _departureDateController.text.isEmpty
          ? null
          : DateFormat("yyyy-MM-dd").parse(_departureDateController.text),
      silkRoute: _silkRouteFacility == "Yes" ? 1 : 0,
      airportTransportation: _airportTranspotation == "Yes" ? 1 : 0,
      airTicketClassName: _ticketClasses.first.name,
      ticketClasses: List<AirTicketClassCount>.from(_ticketClasses),
      isRoundTrip: _isRoundTrip,
      // Air ticket costs are no longer captured on this screen.
      selectedCost: 0,
      airLine: _selectedAirline?.airlineName,
      airLineCode: _selectedAirline?.airlineCode,
      iataCode: _selectedAirline?.iataCode,
      visa: _visa,
      meal: _meal,
      extraLegroomSeat: _extraLegroomSeat,
      goldRoute: _goldRoute,
      // Only meaningful for the facilities that are switched on.
      silkRouteType: _silkRouteFacility == "Yes" ? _silkRouteType : null,
      goldRouteType: _goldRoute ? _goldRouteType : null,
      mealRemark: _meal ? _mealRemarkController.text.trim() : null,
      isMultiSector: _isMultiSector,
      departureSectors: _isMultiSector ? _sectorInfos(_departureSectors) : const [],
      // No return leg means the return stops describe nothing.
      returnSectors: _isMultiSector && airport.returnFlight != null
          ? _sectorInfos(_returnSectors)
          : const [],
      airports: airport,
      assignedGuests: _selectedAssignedGuests(),
    );

    setState(() {
      if (editMode) {
        flightList[editIndex!] = flightBooking;
      } else {
        flightList.add(flightBooking);
      }
    });

    _clearSelection();
  }

  void _acceptChanges() {
    // Last guard before the tickets go back to the reservation: a ticket
    // restored from an existing reservation may never have had a bio page.
    if (!_requireAllPassports()) return;
    ref.read(selectedFlightBallysProvider.notifier).addFlights(flightList);
    ref.read(selectedPassportBallysProvider.notifier).setFiles(_allPassports());
    Navigator.pop(context);
  }

  /// Lays [options] out two per row, with 16px vertical gaps between rows. A
  /// trailing odd option keeps the left column, leaving the right column empty.
  List<Widget> _buildOptionGrid(List<Widget> options) {
    final rows = <Widget>[];
    for (var i = 0; i < options.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: options[i]),
          Expanded(
            child:
                i + 1 < options.length ? options[i + 1] : const SizedBox(),
          ),
        ],
      ));
      if (i + 2 < options.length) {
        rows.add(const SizedBox(height: 16));
      }
    }
    return rows;
  }

  /// A right-aligned checkbox for the trip type answers ("Multi Sector",
  /// "Round Trip") that sit under the Departure airports.
  Widget _buildTripTypeCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
        ),
      ],
    );
  }

  /// The transit airports for one leg: a row per stop in travel order, an "Add
  /// Stop" button, and a preview of the full route so it is clear the stops sit
  /// between that leg's From and To.
  Widget _buildSectorSection({
    required String label,
    required List<FlightSectorEntry> sectors,
    required Airport? from,
    required Airport? to,
  }) {
    final routeCodes = [
      from?.airportCode,
      ...sectors.map((sector) => sector.airport?.airportCode),
      to?.airportCode,
    ].map((code) => (code == null || code.trim().isEmpty) ? "..." : code);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Constants.kPrimaryColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDADDE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            routeCodes.join(" → "),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Constants.kPrimaryColor,
            ),
          ),
          for (var i = 0; i < sectors.length; i++) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CustomAirportField(
                    key: sectors[i].key,
                    label: "Stop ${i + 1}",
                    prefixIcon: Icons.connecting_airports,
                    suffixIcon: Icons.arrow_drop_down,
                    cityCountryText: sectors[i].airport != null
                        ? "${sectors[i].airport!.cityName} - ${sectors[i].airport!.country}"
                        : null,
                    airportNameText: sectors[i].airport?.airportCode,
                    onAirportSelected: (selectedAirport) {
                      setState(() => sectors[i].airport = selectedAirport);
                    },
                  ),
                ),
                IconButton(
                  tooltip: "Remove stop",
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.red),
                  onPressed: () => setState(() => sectors.removeAt(i)),
                ),
              ],
            ),
            // The stop's own travel day, so a route spread over several days
            // reads in order rather than as a bare list of airports.
            Padding(
              // Lines the field up with the airport field above, clear of the
              // remove button's column.
              padding: const EdgeInsets.only(top: 8, right: 48),
              child: _buildSectorDateField(
                sector: sectors[i],
                label: "Stop ${i + 1} Date",
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => sectors.add(FlightSectorEntry())),
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text(
                "Add Stop",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Constants.kPrimaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The tap target for one stop's date. Reads "Select date" until a day is
  /// picked, which is also what [_saveTicketSelection] refuses to save.
  Widget _buildSectorDateField({
    required FlightSectorEntry sector,
    required String label,
  }) {
    final bool hasDate = sector.date != null;
    return InkWell(
      onTap: () => _selectSectorDate(sector, label),
      borderRadius: BorderRadius.circular(8.0),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              fontSize: 16,
              color: Color.fromARGB(255, 0, 0, 0),
              fontWeight: FontWeight.bold),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
          prefixIcon: const Icon(Icons.calendar_today),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Text(
          hasDate ? DateFormat('yyyy-MM-dd').format(sector.date!) : "Select date",
          style: TextStyle(
            fontSize: 16,
            color: hasDate ? Colors.black : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  /// Picks the day a single stop is flown. Unlike the ticket's arrival and
  /// departure dates this writes straight onto the stop, so there is no
  /// controller to keep in step.
  Future<void> _selectSectorDate(FlightSectorEntry sector, String title) async {
    final now = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    // A stop saved earlier can sit in the past; keep it inside the picker's
    // bounds rather than tripping its assertions when the ticket is reopened.
    final DateTime minimum =
        sector.date != null && sector.date!.isBefore(now) ? sector.date! : now;

    DateTime initial = sector.date ?? _arrivalDateOrNull() ?? now;
    if (initial.isBefore(minimum)) initial = minimum;

    final DateTime yearOut = DateTime(now.year + 1, now.month, now.day);
    final DateTime maximum = initial.isAfter(yearOut) ? initial : yearOut;

    DateTime selectedDate = initial;

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
                "Select $title",
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
                initialDateTime: initial,
                minimumDate: minimum,
                maximumDate: maximum,
                onDateTimeChanged: (DateTime newDate) {
                  selectedDate = newDate;
                },
              ),
            ),
            const Divider(height: 1),
            TextButton(
              onPressed: () {
                setState(() {
                  sector.date = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                  );
                });
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

  /// The ticket's arrival date, when one has been picked — stops usually fall
  /// around it, so it makes a better starting point than today.
  DateTime? _arrivalDateOrNull() {
    if (_arrivalDateController.text.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(_arrivalDateController.text);
    } catch (_) {
      return null;
    }
  }

  /// A labelled Yes/No radio group, sized to fill its column so several can be
  /// laid out side by side in a [Row].
  Widget _buildYesNoOption({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: value,
              onChanged: (v) => onChanged(v!),
            ),
            const Text("Yes", style: TextStyle(fontSize: 16)),
            Radio<bool>(
              value: false,
              groupValue: value,
              onChanged: (v) => onChanged(v!),
            ),
            const Text("No", style: TextStyle(fontSize: 16)),
          ],
        ),
      ],
    );
  }

  /// Full-width Arrival / Departure picker for the Silk and Gold Route
  /// facilities: two tap targets side by side, the chosen one filled and
  /// ticked, so the answer is readable at a glance instead of hunting for
  /// which small radio is filled.
  Widget _buildLegSelector({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    Widget leg(String leg, IconData icon) {
      final selected = value == leg;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(leg),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: selected
                  ? Constants.kPrimaryColor.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? Constants.kPrimaryColor
                    : const Color(0xFFDADDE3),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color:
                      selected ? Constants.kPrimaryColor : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    leg,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                      color: selected
                          ? Constants.kPrimaryColor
                          : Colors.black87,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Constants.kPrimaryColor,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            leg("Arrival", Icons.flight_land),
            const SizedBox(width: 12),
            leg("Departure", Icons.flight_takeoff),
          ],
        ),
      ],
    );
  }

  void _clearSelection() {
    setState(() {
      numberOfGuests = 1;
      numberOfChildren = 0;
      numberOfInfants = 0;
      arrivalDate = null;
      _arrivalDateController.text = "";
      _departureDateController.text = "";
      // The ticks belong to the dates they filled in — leaving them on with the
      // dates now blank reads as if the next ticket already has them.
      _isSameAsHotelForArrival = false;
      _isSameAsHotelForDeparture = false;
      _ticketClasses = [];

      _silkRouteFacility = "No";
      _airportTranspotation = "No";
      _isRoundTrip = false;
      _isMultiSector = false;
      _departureSectors.clear();
      _returnSectors.clear();
      _visa = false;
      _meal = false;
      _extraLegroomSeat = false;
      _goldRoute = false;
      _silkRouteType = "Arrival";
      _goldRouteType = "Arrival";
      _mealRemarkController.clear();

      _departureFromAirport = null;
      _departureToAirport = ref
          .read(airportsProvider.notifier)
          .findByCode(_defaultToAirportCode);
      _returnFromAirport = null;
      _returnToAirport = null;

      _departureFromAirportKey = UniqueKey();
      _departureToAirportKey = UniqueKey();

      _selectedAirline = null;
      _airlineKey = UniqueKey();

      editMode = false;
      editIndex = null;

      _departureFromError = false;
      _departureToError = false;
      _airTicketClassError = false;
      _arrivalDateError = false;
      _departureDateError = false;

      // The next ticket is booked for whoever it is booked for, so the ticks
      // start clean — except where there is only one guest to tick. Clearing
      // them also empties the passport uploaders, leaving the next guest a
      // blank one; what was already picked stays filed under its own guest.
      _assignedGuestKeys.clear();
      _preselectSoleGuest();
      _syncHeadCountsToGuests();
      _guestAssignError = false;
    });
  }

  /// Airline picker — the active airlines from API 90156, by name.
  Widget _buildAirlineDropdown() {
    if (_airlinesLoading) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: "Airline",
          labelStyle: const TextStyle(
              fontSize: 20,
              color: Color.fromARGB(255, 0, 0, 0),
              fontWeight: FontWeight.bold),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
          prefixIcon: const Icon(Icons.airplanemode_active),
        ),
        child: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text("Loading airlines...", style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return DropdownSearch<AirlineResponse>(
      key: _airlineKey,
      selectedItem: _selectedAirline,
      items: (filter, infiniteScrollProps) => _airlines
          .where((airline) => airline.airlineName
              .toLowerCase()
              .contains(filter.toLowerCase()))
          .toList(),
      itemAsString: (airline) => airline.airlineName,
      compareFn: (a, b) => a.airlineName == b.airlineName,
      enabled: _airlines.isNotEmpty,
      onChanged: (airline) => setState(() => _selectedAirline = airline),
      decoratorProps: DropDownDecoratorProps(
        decoration: InputDecoration(
          labelText: _airlines.isEmpty ? "Airline (unavailable)" : "Airline",
          labelStyle: const TextStyle(
              fontSize: 20,
              color: Color.fromARGB(255, 0, 0, 0),
              fontWeight: FontWeight.bold),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
          prefixIcon: const Icon(Icons.airplanemode_active),
        ),
      ),
      popupProps: PopupProps.menu(
        showSearchBox: true,
        searchFieldProps: const TextFieldProps(
          decoration: InputDecoration(
            hintText: "Search airline",
            border: OutlineInputBorder(),
          ),
        ),
        itemBuilder: (context, airline, isSelected, isFocused) => ListTile(
          title: Text(airline.airlineName,
              style: const TextStyle(fontSize: 16)),
          selected: isSelected,
        ),
      ),
    );
  }

  Future<void> _getAirports() async {
    try {
      final airports = ref.read(airportsProvider);

      if (airports.isEmpty) {
        setState(() {
          _isLoading = true;
        });
        await ref.read(airportsProvider.notifier).getAllAirports();
        setState(() {
          _isLoading = false;
        });
      }

      ref.read(airportsProvider.notifier).filterAirports("");
      _applyDefaultDepartureToAirport();
    } catch (e) {}
  }

  /// Departure "To" defaults to CMB (from the loaded airport list); the user
  /// can still pick another airport.
  void _applyDefaultDepartureToAirport() {
    if (_departureToAirport != null) return;
    final cmb = ref.read(airportsProvider.notifier).findByCode(_defaultToAirportCode);
    if (cmb == null || !mounted) return;
    setState(() {
      _departureToAirport = cmb;
      _departureToError = false;
      _departureToAirportKey = UniqueKey();
    });
  }

  Future<void> _selectDate(
      BuildContext context, TextEditingController controller) async {
    final now = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    DateTime selectedDate = now;

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
                controller == _arrivalDateController
                    ? "Select Arrival Date"
                    : "Select Departure Date",
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
                initialDateTime: now,
                minimumDate: now,
                maximumDate: DateTime(
                  now.year + 1,
                  now.month,
                  now.day,
                ),
                onDateTimeChanged: (DateTime newDate) {
                  selectedDate = newDate;
                },
              ),
            ),
            const Divider(height: 1),
            TextButton(
              onPressed: () {
                if (controller == _departureDateController &&
                    _arrivalDateController.text.isNotEmpty) {
                  final arrivalParsed = DateFormat('yyyy-MM-dd')
                      .parse(_arrivalDateController.text);
                  if (!selectedDate.isAfter(arrivalParsed)) {
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
                }
                setState(() {
                  controller.text = DateFormat('yyyy-MM-dd').format(selectedDate);
                });
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

  /// A head count. [enabled] false shows the number but takes the buttons away,
  /// for a count the ticket's guests have already settled.
  Widget _buildCounter(
      String label, int count, int type, Function(int) onCountChange,
      {bool enabled = true}) {
    final buttonColor = enabled ? Colors.grey : Colors.grey.shade300;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: enabled ? null : Colors.grey)),
            Row(
              children: [
                GestureDetector(
                  onTap: enabled ? () => onCountChange(count - 1) : null,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(Icons.remove, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40,
                  child: Text(
                    count.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      color: enabled ? null : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: enabled ? () => onCountChange(count + 1) : null,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotelsDropDownKey = GlobalKey<DropdownSearchState>();
    final roomCategoriesDropDownKey = GlobalKey<DropdownSearchState>();
    final roomTypeDropDownKey = GlobalKey<DropdownSearchState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Air Tickets Reservation",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 400,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    children: [
                      // ── Assign this ticket to guests ──────────────────
                      if (widget.guests.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _guestAssignment(),
                      ],
                      const SizedBox(height: 16),
                      _buildCounter("Guests", numberOfGuests, 1,
                          (count) => _updateAdults(count),
                          enabled: !_headCountsLocked),
                      const SizedBox(height: 12),
                      _buildCounter("Children", numberOfChildren, 2,
                          (count) => _updateChildren(count),
                          enabled: !_headCountsLocked),
                      const SizedBox(height: 12),
                      _buildCounter("Infants", numberOfInfants, 3,
                          (count) => _updateInfants(count),
                          enabled: !_headCountsLocked),
                      if (_headCountsLocked) ...[
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "This ticket is for the selected guest only — no family members to add",
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          "Departure",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                      ),
                      const SizedBox(height: 5),
                      CustomAirportField(
                        label: "From",
                        key: _departureFromAirportKey,
                        hasError: _departureFromError,
                        prefixIcon: Icons.airplane_ticket_outlined,
                        suffixIcon: Icons.arrow_drop_down,
                        cityCountryText: _departureFromAirport != null
                            ? "${_departureFromAirport!.cityName} - ${_departureFromAirport!.country}"
                            : null,
                        airportNameText: _departureFromAirport?.airportCode,
                        onAirportSelected: (selectedAirport) {
                          setState(() {
                            _departureFromAirport = selectedAirport;
                            _departureFromError = false;
                          });
                        },
                      ),
                      const SizedBox(height: 5),
                      CustomAirportField(
                        label: "To",
                        key: _departureToAirportKey,
                        hasError: _departureToError,
                        prefixIcon: Icons.airplane_ticket_outlined,
                        suffixIcon: Icons.arrow_drop_down,
                        cityCountryText: _departureToAirport != null
                            ? "${_departureToAirport!.cityName} - ${_departureToAirport!.country}"
                            : null,
                        airportNameText: _departureToAirport?.airportCode,
                        onAirportSelected: (selectedAirport) {
                          setState(() {
                            _departureToAirport = selectedAirport;
                            _departureToError = false;
                          });
                        },
                      ),
                      // Asked before Round Trip: guests with no direct flight
                      // route through transit airports, and that changes what
                      // each leg below looks like.
                      _buildTripTypeCheckbox(
                        label: "Multi Sector (No Direct Flight)",
                        value: _isMultiSector,
                        onChanged: (value) {
                          setState(() {
                            _isMultiSector = value;
                            if (_isMultiSector) {
                              // Start each leg off with one empty stop, so
                              // there is something to fill in straight away.
                              if (_departureSectors.isEmpty) {
                                _departureSectors.add(FlightSectorEntry());
                              }
                              if (_isRoundTrip && _returnSectors.isEmpty) {
                                _returnSectors.add(FlightSectorEntry());
                              }
                            } else {
                              _departureSectors.clear();
                              _returnSectors.clear();
                            }
                          });
                        },
                      ),
                      if (_isMultiSector)
                        _buildSectorSection(
                          label: "Departure Stops",
                          sectors: _departureSectors,
                          from: _departureFromAirport,
                          to: _departureToAirport,
                        ),
                      _buildTripTypeCheckbox(
                        label: "Round Trip",
                        value: _isRoundTrip,
                        onChanged: (value) {
                          setState(() {
                            _isRoundTrip = value;
                            if (_isRoundTrip) {
                              _returnFromAirport = _departureToAirport;
                              if (_isMultiSector && _returnSectors.isEmpty) {
                                _returnSectors.add(FlightSectorEntry());
                              }
                            } else {
                              // Departure date is optional for one-way.
                              _departureDateError = false;
                              _returnSectors.clear();
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 0),
                      if (_isRoundTrip)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                "Return",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                            ),
                            const SizedBox(height: 5),
                            CustomAirportField(
                              label: "From",
                              prefixIcon: Icons.airplane_ticket_outlined,
                              suffixIcon: Icons.arrow_drop_down,
                              cityCountryText: _departureToAirport != null
                                  ? "${_departureToAirport!.cityName} - ${_departureToAirport!.country}"
                                  : null,
                              airportNameText: _departureToAirport?.airportCode,
                              onAirportSelected: (selectedAirport) {
                                setState(() {
                                  _returnFromAirport = selectedAirport;
                                });
                              },
                            ),
                            const SizedBox(height: 5),
                            CustomAirportField(
                              label: "To",
                              prefixIcon: Icons.airplane_ticket_outlined,
                              suffixIcon: Icons.arrow_drop_down,
                              cityCountryText: _returnToAirport != null
                                  ? "${_returnToAirport!.cityName} - ${_returnToAirport!.country}"
                                  : null,
                              airportNameText: _returnToAirport?.airportCode,
                              onAirportSelected: (selectedAirport) {
                                setState(() {
                                  _returnToAirport = selectedAirport;
                                });
                              },
                            ),
                            if (_isMultiSector)
                              _buildSectorSection(
                                label: "Return Stops",
                                sectors: _returnSectors,
                                from: _returnFromAirport ?? _departureToAirport,
                                to: _returnToAirport,
                              ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      AirTicketClassCountSelector(
                        hasError: _airTicketClassError,
                        selectedClasses: _ticketClasses,
                        maxSeats: _maxTicketSeats,
                        onChanged: (classes) {
                          setState(() {
                            _ticketClasses = classes;
                            if (classes.isNotEmpty) {
                              _airTicketClassError = false;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildAirlineDropdown(),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _arrivalDateController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: "Arrival Date",
                          labelStyle: const TextStyle(
                              fontSize: 20,
                              color: Color.fromARGB(255, 0, 0, 0),
                              fontWeight: FontWeight.bold),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0)),
                          prefixIcon: const Icon(Icons.calendar_today),
                          errorText: _arrivalDateError ? "Required" : null,
                        ),
                        onTap: () async {
                          await _selectDate(context, _arrivalDateController);
                          setState(() {
                            // Picking a date by hand can move it off the
                            // reservation's own date, which unticks the box.
                            _isSameAsHotelForArrival =
                                _arrivalDateController.text.isNotEmpty &&
                                    _arrivalDateController.text == _arrivalDate;
                            if (_arrivalDateController.text.isNotEmpty) {
                              _arrivalDateError = false;
                            }
                          });
                        },
                      ),
                      if (_arrivalDate.isNotEmpty)
                        Row(
                          children: [
                            Checkbox(
                              value: _isSameAsHotelForArrival,
                              onChanged: (value) {
                                setState(() {
                                  _isSameAsHotelForArrival = value!;
                                  if (_isSameAsHotelForArrival &&
                                      _arrivalDate.isNotEmpty) {
                                    _arrivalDateController.text = _arrivalDate;
                                  }
                                });
                              },
                            ),
                            const Text("Same as flight reservation",
                                style: TextStyle(fontSize: 18)),
                          ],
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _departureDateController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: _isRoundTrip
                              ? "Departure Date"
                              : "Departure Date (Optional)",
                          labelStyle: const TextStyle(
                              fontSize: 20,
                              color: Color.fromARGB(255, 0, 0, 0),
                              fontWeight: FontWeight.bold),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0)),
                          prefixIcon: const Icon(Icons.calendar_today),
                          errorText: _departureDateError ? "Required" : null,
                        ),
                        onTap: () async {
                          await _selectDate(context, _departureDateController);
                          setState(() {
                            _isSameAsHotelForDeparture =
                                _departureDateController.text.isNotEmpty &&
                                    _departureDateController.text ==
                                        _departureDate;
                            if (_departureDateController.text.isNotEmpty) {
                              _departureDateError = false;
                            }
                          });
                        },
                      ),
                      if (_departureDate.isNotEmpty)
                        Row(
                          children: [
                            Checkbox(
                              value: _isSameAsHotelForDeparture,
                              onChanged: (value) {
                                setState(() {
                                  _isSameAsHotelForDeparture = value!;
                                  if (_isSameAsHotelForDeparture &&
                                      _departureDate.isNotEmpty) {
                                    _departureDateController.text =
                                        _departureDate;
                                  }
                                });
                              },
                            ),
                            const Text("Same as flight reservation",
                                style: TextStyle(fontSize: 18)),
                          ],
                        ),
                           const SizedBox(height: 16),
  _passportSection(),
  const SizedBox(height: 20),
// const Align(
//   alignment: Alignment.topLeft,
//   child: Text(
//     "Contact Person",
//     style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
//   ),
// ),
// const SizedBox(height: 5),
// The Hamoos contact person is picked once on the reservation form now — it
// describes the reservation, not the individual ticket, so it is no longer
// asked for here.
                      const SizedBox(height: 16),
                      ..._buildOptionGrid([
                        _buildYesNoOption(
                          label: "Visa",
                          value: _visa,
                          onChanged: (value) => setState(() => _visa = value),
                        ),
                        _buildYesNoOption(
                          label: "Airport Transpotation",
                          value: _airportTranspotation == "Yes",
                          onChanged: (value) => setState(() =>
                              _airportTranspotation = value ? "Yes" : "No"),
                        ),
                          _buildYesNoOption(
                          label: "Silk Route Facility",
                          value: _silkRouteFacility == "Yes",
                          // Silk and Gold Route are mutually exclusive —
                          // turning one on clears the other.
                          onChanged: (value) => setState(() {
                            _silkRouteFacility = value ? "Yes" : "No";
                            if (value) _goldRoute = false;
                          }),
                        ),

                        if (_isBallys) ...[
                          _buildYesNoOption(
                            label: "Meal",
                            value: _meal,
                            onChanged: (value) =>
                                setState(() => _meal = value),
                          ),
                          _buildYesNoOption(
                            label: "Extra Legroom Seat",
                            value: _extraLegroomSeat,
                            onChanged: (value) =>
                                setState(() => _extraLegroomSeat = value),
                          ),
                          _buildYesNoOption(
                            label: "Gold Route",
                            value: _goldRoute,
                            onChanged: (value) => setState(() {
                              _goldRoute = value;
                              if (value) _silkRouteFacility = "No";
                            }),
                          ),
                        ],
                      ]),

                      // ── Follow-ups for the Yes answers above ──────────
                      // Full width, one per row: the leg pickers and the meal
                      // note need more space than a half-width grid cell.
                      if (_silkRouteFacility == "Yes") ...[
                        const SizedBox(height: 20),
                        _buildLegSelector(
                          label: "Silk Route Facility For",
                          value: _silkRouteType,
                          onChanged: (leg) =>
                              setState(() => _silkRouteType = leg),
                        ),
                      ],
                      if (_isBallys && _goldRoute) ...[
                        const SizedBox(height: 20),
                        _buildLegSelector(
                          label: "Gold Route For",
                          value: _goldRouteType,
                          onChanged: (leg) =>
                              setState(() => _goldRouteType = leg),
                        ),
                      ],
                      if (_isBallys && _meal) ...[
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _mealRemarkController,
                          style: const TextStyle(fontSize: 16),
                          decoration: InputDecoration(
                            labelText: "Meal Details",
                            hintText: "e.g. vegetarian, no nuts",
                            prefixIcon: const Icon(Icons.restaurant_menu),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 35),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          width: double.infinity,
                          child: editMode
                              ? OutlinedButton(
                                  onPressed: _saveTicketSelection,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green,
                                    side: const BorderSide(
                                        color: Colors.green, width: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  child: const Text(
                                    "Update Air Ticket",
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                )
                              : OutlinedButton(
                                  onPressed: _saveTicketSelection,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Constants.kSecondaryColor,
                                    side: const BorderSide(
                                        color: Constants.kSecondaryColor,
                                        width: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  child: const Text(
                                    "Add Air Ticket",
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          width: double.infinity,
                          child: editMode
                              ? OutlinedButton(
                                  onPressed: _clearSelection,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.grey,
                                    side: const BorderSide(
                                        color: Colors.grey, width: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  child: const Text(
                                    "Cancel",
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      flightList.isEmpty
                          ? const Center(
                              heightFactor: 6.0,
                              child: Text(
                                'No air tickets available.',
                                style: TextStyle(fontSize: 16),
                              ),
                            )
                          : SizedBox(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: flightList.map((flight) {
                                    int index = flightList.indexOf(flight);
                                    return FlightCardBallys(
                                      flight: flight,
                                      index: index,
                                      showDelete: true,
                                      onDoubleTap: () {
                                        if (_scrollController.hasClients) {
                                          _scrollController.animateTo(
                                            0,
                                            duration: const Duration(
                                                milliseconds: 300),
                                            curve: Curves.easeInOut,
                                          );
                                        }
                                        __editFlightDetails(flight, index);
                                      },
                                      onDelete: () {
                                        _removeFlight(index);
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                      const SizedBox(height: 16),
                      AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                flightList.isNotEmpty ? _acceptChanges : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Constants.kSecondaryColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.save, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  "Accept Changes",
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
