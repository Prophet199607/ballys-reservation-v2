import 'package:ballys_reservation_app/core/constants.dart';
import 'package:ballys_reservation_app/data/repositories/hotel_repository.dart';
import 'package:ballys_reservation_app/models/reservation/hotel_cost_response.dart';
import 'package:ballys_reservation_app/models/reservation/hotel_desc.dart';
import 'package:ballys_reservation_app/providers/hotels_provider.dart';
import 'package:ballys_reservation_app/providers/selected_hotel_provider.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dropdown_search/dropdown_search.dart';

class HotelAndRoomSelectionBottomSheet extends ConsumerStatefulWidget {
  final HotelRepository hotelRepository;
  final VoidCallback? onClose;

  /// Arrival / departure dates already picked on the reservation form. When
  /// both are set the sheet offers a checkbox that copies them into the
  /// hotel date range.
  final DateTime? reservationArrivalDate;
  final DateTime? reservationDepartureDate;

  const HotelAndRoomSelectionBottomSheet(
    this.hotelRepository, {
    this.onClose,
    this.reservationArrivalDate,
    this.reservationDepartureDate,
    super.key,
  });

  @override
  ConsumerState<HotelAndRoomSelectionBottomSheet> createState() =>
      _HotelAndRoomSelectionBottomSheetState();
}

class _HotelAndRoomSelectionBottomSheetState
    extends ConsumerState<HotelAndRoomSelectionBottomSheet> {
  final TextEditingController _dateRangeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final ValueNotifier<List<Map<String, dynamic>>> roomCategoriesNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  final ValueNotifier<List<Map<String, dynamic>>> roomTypesNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  final ValueNotifier<String> costNotifier = ValueNotifier<String>("0");

  /// Bellagio (bty.world) swaps the "Payment By" options to the Beyond
  /// Borders wording.
  bool _isBellagio = false;

  @override
  void initState() {
    super.initState();
    hotelList = List.from(ref.read(selectedHotelProvider));
    _loadBrand();
  }

  Future<void> _loadBrand() async {
    final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
    if (!mounted) return;
    setState(() {
      _isBellagio = apiUrl.contains('bty.world');
      // Bellagio uses "N/A" as the payment default instead of "NA".
      if (_isBellagio &&
          (selectedByPaymnet.isEmpty || selectedByPaymnet == 'NA')) {
        selectedByPaymnet = 'N/A';
      }
    });
  }

  @override
  void dispose() {
    _dateRangeController.dispose();
    _scrollController.dispose();
    roomCategoriesNotifier.dispose();
    roomTypesNotifier.dispose();
    costNotifier.dispose();
    super.dispose();
  }

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

  int? numberOfNights;

  dynamic selectedCost;
  int? costIndex;

  int numberOfAdults = 1;
  int numberOfChildren = 0;
  int numberOfRooms = 1;

  List<HotelDescip> hotelList = [];
String selectedEcLcoFacility = 'NA';
String selectedByPaymnet = 'NA';

  // Validation error flags for required fields
  bool _dateRangeError = false;
  bool _hotelError = false;
  bool _roomCategoryError = false;
  bool _roomTypeError = false;

  /// When true the date range mirrors the reservation arrival / departure
  /// dates and the range picker is locked.
  bool _useReservationDates = false;

  bool get _hasReservationDates =>
      widget.reservationArrivalDate != null &&
      widget.reservationDepartureDate != null;

  String _formatRange(DateTime start, DateTime end) =>
      "${DateFormat('yyyy-MM-dd').format(start)} - ${DateFormat('yyyy-MM-dd').format(end)}";

  void _applyReservationDates() {
    final start = widget.reservationArrivalDate!;
    final end = widget.reservationDepartureDate!;
    final range = DateTimeRange(start: start, end: end);
    setState(() {
      selectedDateRange = range;
      arrivalDate = start;
      departureDate = end;
      numberOfNights = range.duration.inDays;
      _dateRangeError = false;
      _dateRangeController.text = _formatRange(start, end);
    });
    _clearSelectedCost();
  }

  void _toggleUseReservationDates(bool? value) {
    final checked = value ?? false;
    setState(() => _useReservationDates = checked);

    if (checked) {
      _applyReservationDates();
      return;
    }

    setState(() {
      selectedDateRange = null;
      arrivalDate = null;
      departureDate = null;
      numberOfNights = null;
      _dateRangeController.text = "";
    });
    _clearSelectedCost();
  }

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
        _dateRangeError = false;
        _dateRangeController.text =
            "${DateFormat('yyyy-MM-dd').format(pickedDateRange.start)} - ${DateFormat('yyyy-MM-dd').format(pickedDateRange.end)}";
      });
      _clearSelectedCost();
    }
  }

  void _updateAdults(int count) {
    if (count >= 1) {
      setState(() => numberOfAdults = count);
      _clearSelectedCost();
    }
  }

  void _updateChildren(int count) {
    if (count >= 0) {
      setState(() => numberOfChildren = count);
      _clearSelectedCost();
    }
  }

  void _updateRooms(int count) {
    if (count >= 1) {
      setState(() => numberOfRooms = count);
      _clearSelectedCost();
    }
  }

  Future<void> getSelectedHotelRoomCategories(
    double hotelId, {
    bool clearSelection = true,
  }) async {
    try {
      final response = await widget.hotelRepository
          .getSelectedHotelRoomCategories(hotelId);
      roomCategoriesNotifier.value = response
          .map((category) => category.toJson())
          .toList();

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
    double hotelId,
    int categoryId, {
    bool clearSelection = true,
  }) async {
    try {
      final response = await widget.hotelRepository
          .getSelectedHotelCategoryRoomTypes(hotelId, categoryId);
      roomTypesNotifier.value = response
          .map((category) => category.toJson())
          .toList();

      if (clearSelection) {
        selectedRoomType = null;
        selectedRoomTypeId = null;
        selectedRoomTypeName = null;
      }
    } catch (e) {
      roomTypesNotifier.value = [];
    }
  }

  Future<List<HotelCostResponse>?> getHotelCosts() async {
    try {
      final response = await widget.hotelRepository.getHotelCosts(
        hotelName: selectedHotelName!,
        roomCategory: selectedRoomCategoryName!,
        roomType: sRoomTypeName!,
        mealPlan: sMealPlanName!,
      );
      return response;
    } catch (e) {
      return null;
    }
  }

  void _setHotel(Map<String, dynamic>? hotel) {
    selectedHotel = hotel;
    selectedHotelId = hotel?['Hotel_IID'];
    selectedHotelName = hotel?['HotelName'] ?? '';
    if (_hotelError) setState(() => _hotelError = false);
    _clearSelectedCost();

    if (selectedHotelId != null) {
      roomCategoriesNotifier.value = [];
      roomTypesNotifier.value = [];
      getSelectedHotelRoomCategories(selectedHotelId!);
    }
  }

  void _setRoomCategory(Map<String, dynamic>? roomCategory) {
    selectedRoomCategory = roomCategory;
    selectedRoomCategoryId = roomCategory?['CatCode'];
    selectedRoomCategoryName = roomCategory?['CatName'] ?? '';
    if (_roomCategoryError) setState(() => _roomCategoryError = false);
    _clearSelectedCost();

    if (selectedHotelId != null && selectedRoomCategoryId != null) {
      roomTypesNotifier.value = [];
      getSelectedHotelCategoryRoomTypes(
        selectedHotelId!,
        selectedRoomCategoryId!,
      );
    }
  }

  void _setRoomType(Map<String, dynamic>? roomtype) {
    selectedRoomType = roomtype;
    selectedRoomTypeId = roomtype?['ID'];
    sRoomTypeName = roomtype?['RoomType'] ?? '';
    sMealPlanName = roomtype?['MealPlan'] ?? '';
    selectedRoomTypeName = '$sRoomTypeName - $sMealPlanName';
    if (_roomTypeError) setState(() => _roomTypeError = false);
    _clearSelectedCost();
  }

  void _handleItemSelected(HotelCostResponse cost, int index) {
    setState(() {
      costIndex = index;
      double calculation =
          ((cost.netRate! * numberOfNights!) * cost.usRate!) *
          numberOfAdults *
          numberOfRooms;
      costNotifier.value = NumberFormat().format(calculation.round());
    });
  }

  void _editHotel(HotelDescip hotel, int index) {
    setState(() {
      editMode = true;
      editIndex = index;
      numberOfAdults = hotel.guestCount!;
      numberOfChildren = hotel.childrenCount!;
      numberOfRooms = hotel.roomCount!;

      selectedDateRange = hotel.selectedDateRange;
      numberOfNights = hotel.noOfNights;
      arrivalDate = hotel.arrivalDate;
      departureDate = hotel.departureDate;
      _dateRangeController.text = _formatRange(
        hotel.selectedDateRange.start,
        hotel.selectedDateRange.end,
      );
      _useReservationDates = _hasReservationDates &&
          DateUtils.isSameDay(
            hotel.arrivalDate,
            widget.reservationArrivalDate,
          ) &&
          DateUtils.isSameDay(
            hotel.departureDate,
            widget.reservationDepartureDate,
          );

      selectedHotelId = hotel.hotel;
      selectedHotelName = hotel.hotelName;
      selectedHotel = {"Hotel_IID": hotel.hotel, "HotelName": hotel.hotelName};

      getSelectedHotelRoomCategories(selectedHotelId!, clearSelection: false);

      selectedRoomCategoryId = hotel.roomCategoryId;
      selectedRoomCategoryName = hotel.roomCategoryName;
      selectedRoomCategory = {
        "CatCode": hotel.roomCategoryId,
        "CatName": hotel.roomCategoryName,
      };

      getSelectedHotelCategoryRoomTypes(
        selectedHotelId!,
        selectedRoomCategoryId!,
        clearSelection: false,
      );

      selectedRoomTypeId = hotel.roomTypeId;
      selectedRoomTypeName = hotel.roomTypeName;
      List<String> parts = hotel.roomTypeName!.split("-");
      selectedRoomType = {
        "ID": hotel.roomTypeId,
        "RoomType": parts[0].trim(),
        "MealPlan": parts[1].trim(),
      };
      sRoomTypeName = parts[0].trim();
      sMealPlanName = parts[1].trim();
      selectedCost = hotel.selectedCost;
      costNotifier.value = hotel.selectedCost;
      costIndex = hotel.costIndex;
    });

    // Scroll to top so user sees the form
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _removeHotel(int index) {
    setState(() => hotelList.removeAt(index));
  }

  void _saveHotelSelection() {
    final bool dateMissing = selectedDateRange == null;
    final bool hotelMissing = selectedHotelId == null;
    final bool categoryMissing = selectedRoomCategoryId == null;
    final bool roomTypeMissing = selectedRoomTypeId == null;

    if (dateMissing || hotelMissing || categoryMissing || roomTypeMissing) {
      setState(() {
        _dateRangeError = dateMissing;
        _hotelError = hotelMissing;
        _roomCategoryError = categoryMissing;
        _roomTypeError = roomTypeMissing;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all required fields.")),
      );
      return;
    }

    // Cost is optional — no blocking if not calculated

    final hotel = HotelDescip(
      hotel: selectedHotelId,
      hotelName: selectedHotelName,
      roomCategoryId: selectedRoomCategoryId,
      roomCategoryName: selectedRoomCategoryName,
      roomTypeId: selectedRoomTypeId,
      roomTypeName: selectedRoomTypeName,
      guestCount: numberOfAdults,
      selectedDateRange: selectedDateRange,
      arrivalDate: arrivalDate,
      departureDate: departureDate,
      childrenCount: numberOfChildren,
      roomCount: numberOfRooms,
      noOfNights: numberOfNights,
      selectedCost: costNotifier.value,
      costIndex: costIndex,
      ecLcoFacility: selectedEcLcoFacility,
      paymentBy: selectedByPaymnet,
    );

    setState(() {
      if (editMode) {
        hotelList[editIndex!] = hotel;
      } else {
        hotelList.add(hotel);
      }
    });

    _clearSelection();
  }

  void _acceptChanges() {
    ref.read(selectedHotelProvider.notifier).addHotels(hotelList);
    Navigator.pop(context);
  }

  void _closeSheet() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  void _clearSelectedCost() {
    costNotifier.value = "0";
    selectedCost = null;
    costIndex = null;
  }

  void _clearSelection() {
    // Keep the "same as reservation dates" choice sticky across adds so a
    // second hotel on the same stay does not need the dates re-picked.
    final bool keepReservationDates =
        _useReservationDates && _hasReservationDates;

    setState(() {
      numberOfAdults = 1;
      numberOfChildren = 0;
      numberOfRooms = 1;

      selectedDateRange = null;
      arrivalDate = null;
      departureDate = null;
      numberOfNights = null;
      _dateRangeController.text = "";

      selectedHotelId = null;
      selectedHotelName = null;
      selectedHotel = null;

      selectedRoomCategory = null;
      selectedRoomCategoryId = null;
      selectedRoomCategoryName = null;
      roomCategoriesNotifier.value = [];

      selectedRoomType = null;
      selectedRoomTypeId = null;
      selectedRoomTypeName = null;
      sRoomTypeName = null;
      sMealPlanName = null;
      roomTypesNotifier.value = [];

      selectedCost = null;
      costNotifier.value = "0";
      costIndex = null;

      editMode = false;
      editIndex = null;
      selectedEcLcoFacility = 'NA';
      selectedByPaymnet = _isBellagio ? 'N/A' : 'NA';

      _useReservationDates = false;
      _dateRangeError = false;
      _hotelError = false;
      _roomCategoryError = false;
      _roomTypeError = false;
    });

    if (keepReservationDates) {
      _toggleUseReservationDates(true);
    }
  }

  void _showCostCalculator(BuildContext context) async {
    if (selectedHotelName == null ||
        selectedRoomCategoryName == null ||
        sRoomTypeName == null ||
        sMealPlanName == null ||
        numberOfNights == null ||
        selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please select Date range, hotel, category and room type.",
          ),
        ),
      );
      return;
    }
    final hotelCosts = await getHotelCosts();
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      builder: (BuildContext context) {
        return CostCalculatorBottomSheet(
          onBackPressed: () => Navigator.pop(context),
          onItemSelected: _handleItemSelected,
          hotelCosts: hotelCosts ?? [],
        );
      },
    );
  }

  Widget _buildCounter(String label, int count, Function(int) onCountChange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () => onCountChange(count - 1),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey,
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
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => onCountChange(count + 1),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey,
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
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header Row ──────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Select Hotels & Rooms",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  tooltip: "Close",
                  icon: const Icon(Icons.close),
                  onPressed: _closeSheet,
                ),
              ],
            ),
            const SizedBox(height: 5),
            // ── Scrollable Body ─────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // ── Date Range ─────────────────────────
                        const SizedBox(height: 5),
                        TextFormField(
                          controller: _dateRangeController,
                          readOnly: true,
                          enabled: !_useReservationDates,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            labelText: "Select Date Range",
                            labelStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            border: const OutlineInputBorder(),
                            errorText: _dateRangeError ? "Required" : null,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today),
                              onPressed: _useReservationDates
                                  ? null
                                  : () => _selectDateRange(context),
                            ),
                          ),
                        ),

                        // ── Same as reservation dates ──────────
                        CheckboxListTile(
                          value: _useReservationDates,
                          onChanged: _hasReservationDates
                              ? _toggleUseReservationDates
                              : null,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            "Same as Arrival & Departure Date",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            _hasReservationDates
                                ? _formatRange(
                                    widget.reservationArrivalDate!,
                                    widget.reservationDepartureDate!,
                                  )
                                : "Pick the reservation Arrival & Departure dates first",
                            style: const TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        if (selectedDateRange != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                "$numberOfNights night(s)",
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),

                        // ── Counters ───────────────────────────
                        _buildCounter("Adults", numberOfAdults, _updateAdults),
                        const SizedBox(height: 16),
                        _buildCounter(
                          "Children",
                          numberOfChildren,
                          _updateChildren,
                        ),
                        const SizedBox(height: 16),
                        _buildCounter("Rooms", numberOfRooms, _updateRooms),
                        const SizedBox(height: 16),

                        // ── Hotel Dropdown ─────────────────────
                        DropdownSearch<Map<String, dynamic>>(
                          selectedItem: selectedHotel,
                          items: (filter, infiniteScrollProps) =>
                              ref.watch(hotelsProvider.notifier).hotelsAsMap,
                          itemAsString: (item) => item['HotelName'] ?? '',
                          compareFn: (a, b) => a['Hotel_IID'] == b['Hotel_IID'],
                          decoratorProps: DropDownDecoratorProps(
                            decoration: InputDecoration(
                              labelText: 'Select Hotel',
                              labelStyle: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              border: const OutlineInputBorder(),
                              errorText: _hotelError ? "Required" : null,
                            ),
                          ),
                          suffixProps: DropdownSuffixProps(
                            dropdownButtonProps: DropdownButtonProps(
                              iconClosed: Icon(Icons.arrow_drop_down, size: 30),
                              iconOpened: Icon(Icons.arrow_drop_up, size: 30),
                            ),
                          ),
                          dropdownBuilder: (context, selectedItem) {
                            return Text(
                              selectedItem?['HotelName'] ?? '',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                          onChanged: _setHotel,
                          popupProps: PopupProps.dialog(
                            showSearchBox: true,
                            searchFieldProps: const TextFieldProps(
                              autofocus: true,
                            ),
                            itemBuilder:
                                (context, item, isSelected, isFocused) {
                                  return ListTile(
                                    title: Text(
                                      item['HotelName'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    selected: isSelected,
                                    tileColor: isFocused
                                        ? Colors.grey.shade200
                                        : null,
                                  );
                                },
                            dialogProps: DialogProps(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Room Category Dropdown ─────────────
                        ValueListenableBuilder<List<Map<String, dynamic>>>(
                          valueListenable: roomCategoriesNotifier,
                          builder: (context, roomCategories, _) {
                            return DropdownSearch<Map<String, dynamic>>(
                              selectedItem: selectedRoomCategory,
                              items: (filter, infiniteScrollProps) =>
                                  roomCategories,
                              itemAsString: (item) => item['CatName'] ?? '',
                              compareFn: (a, b) => a['CatCode'] == b['CatCode'],
                              decoratorProps: DropDownDecoratorProps(
                                decoration: InputDecoration(
                                  labelText: 'Select Category',
                                  labelStyle: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  border: const OutlineInputBorder(),
                                  errorText:
                                      _roomCategoryError ? "Required" : null,
                                ),
                              ),
                              suffixProps: DropdownSuffixProps(
                                dropdownButtonProps: DropdownButtonProps(
                                  iconClosed: Icon(
                                    Icons.arrow_drop_down,
                                    size: 30,
                                  ),
                                  iconOpened: Icon(
                                    Icons.arrow_drop_up,
                                    size: 30,
                                  ),
                                ),
                              ),
                              dropdownBuilder: (context, selectedItem) {
                                return Text(
                                  selectedItem?['CatName'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                              onChanged: _setRoomCategory,
                              popupProps: PopupProps.dialog(
                                showSearchBox: true,
                                searchFieldProps: const TextFieldProps(
                                  autofocus: true,
                                ),
                                itemBuilder:
                                    (context, item, isSelected, isFocused) {
                                      return ListTile(
                                        title: Text(
                                          item['CatName'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        selected: isSelected,
                                        tileColor: isFocused
                                            ? Colors.grey.shade200
                                            : null,
                                      );
                                    },
                                dialogProps: DialogProps(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // ── Room Type Dropdown ─────────────────
                        ValueListenableBuilder<List<Map<String, dynamic>>>(
                          valueListenable: roomTypesNotifier,
                          builder: (context, roomTypes, _) {
                            return DropdownSearch<Map<String, dynamic>>(
                              selectedItem: selectedRoomType,
                              items: (filter, infiniteScrollProps) => roomTypes,
                              itemAsString: (item) {
                                final rt = item['RoomType'] ?? '';
                                final mp = item['MealPlan'] ?? '';
                                return '$rt - $mp';
                              },
                              compareFn: (a, b) => a['ID'] == b['ID'],
                              decoratorProps: DropDownDecoratorProps(
                                decoration: InputDecoration(
                                  labelText: 'Select Room Type',
                                  labelStyle: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  border: const OutlineInputBorder(),
                                  errorText: _roomTypeError ? "Required" : null,
                                ),
                              ),
                              dropdownBuilder: (context, selectedItem) {
                                final rt = selectedItem?['RoomType'] ?? '';
                                final mp = selectedItem?['MealPlan'] ?? '';
                                return Text(
                                  selectedItem == null ? '' : '$rt - $mp',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                              onChanged: _setRoomType,
                              popupProps: PopupProps.dialog(
                                showSearchBox: true,
                                searchFieldProps: const TextFieldProps(
                                  autofocus: true,
                                ),
                                itemBuilder:
                                    (context, item, isSelected, isFocused) {
                                      final rt = item['RoomType'] ?? '';
                                      final mp = item['MealPlan'] ?? '';
                                      return ListTile(
                                        title: Text(
                                          '$rt - $mp',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        selected: isSelected,
                                        tileColor: isFocused
                                            ? Colors.grey.shade200
                                            : null,
                                      );
                                    },
                                dialogProps: DialogProps(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
// ── EC/LCO Facility Dropdown ────────────────────────────
DropdownButtonFormField<String>(
  value: selectedEcLcoFacility,
  decoration: const InputDecoration(
    labelText: 'EC/LCO Facility',
    labelStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
    border: OutlineInputBorder(),
  ),
  style: const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  ),
  icon: const Icon(Icons.arrow_drop_down, size: 30),
  items: const [
    DropdownMenuItem(value: 'NA',        child: Text('NA')),
    DropdownMenuItem(value: 'ECL',       child: Text('ECL')),
    DropdownMenuItem(value: 'LCO',       child: Text('LCO')),
    DropdownMenuItem(value: 'ECL & LCO', child: Text('ECL & LCO')),
  ],
  onChanged: (value) {
    setState(() => selectedEcLcoFacility = value ?? 'NA');
  },
),
const SizedBox(height: 16),
DropdownButtonFormField<String>(
  value: selectedByPaymnet,
  decoration: const InputDecoration(
    labelText: 'Payment By',
    labelStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
    border: OutlineInputBorder(),
  ),
  style: const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  ),
  icon: const Icon(Icons.arrow_drop_down, size: 30),
  items: _isBellagio
      ? const [
          DropdownMenuItem(value: 'N/A',               child: Text('N/A')),
          DropdownMenuItem(value: 'By Guest',          child: Text('By Guest')),
          DropdownMenuItem(value: 'By Beyond Borders', child: Text('By Beyond Borders')),
          DropdownMenuItem(value: 'By Guest & Beyond', child: Text('By Guest & Beyond Borders')),
        ]
      : const [
          DropdownMenuItem(value: 'NA',                child: Text('NA')),
          DropdownMenuItem(value: 'By Guest',          child: Text('By Guest')),
          DropdownMenuItem(value: 'By Hamoos ',        child: Text('By Hamoos')),
          DropdownMenuItem(value: 'By Guest & Hamoos', child: Text('By Guest & Hamoos')),
          DropdownMenuItem(value: 'Recovery from Cashier ', child: Text('Recovery from Cashier')),
        ],
  onChanged: (value) {
    setState(() => selectedByPaymnet = value ?? (_isBellagio ? 'N/A' : 'NA'));
  },
),
const SizedBox(height: 16),
                        // ── Cost Calculator Button ─────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _showCostCalculator(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Constants.kPrimaryColor,
                              foregroundColor: Colors.white,
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
                                Icon(Icons.calculate, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  "Cost Calculator",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Estimated Cost ─────────────────────
                        ValueListenableBuilder<String>(
                          valueListenable: costNotifier,
                          builder: (context, cost, _) {
                            final hasNoCost = cost == "0";
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                hasNoCost
                                    ? "Est. Cost: No cost calculation done"
                                    : "Est. Cost LKR $cost",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: hasNoCost
                                      ? const Color.fromARGB(255, 255, 30, 0)
                                      : Colors.black,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // ── Add / Update Hotel Button ──────────
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _saveHotelSelection,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: editMode
                                  ? Colors.green
                                  : Constants.kSecondaryColor,
                              side: BorderSide(
                                color: editMode
                                    ? Colors.green
                                    : Constants.kSecondaryColor,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              editMode ? "Update Hotel" : "Add Hotel",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        // ── Cancel Edit Button ─────────────────
                        if (editMode) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _clearSelection,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey,
                                side: const BorderSide(
                                  color: Colors.grey,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: const Text(
                                "Cancel",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // ── Hotel List ─────────────────────────
                        hotelList.isEmpty
                            ? const Center(
                                heightFactor: 4.0,
                                child: Text(
                                  'No hotels added yet.',
                                  style: TextStyle(fontSize: 16),
                                ),
                              )
                            : Column(
                                children: hotelList.map((hotel) {
                                  final index = hotelList.indexOf(hotel);
                                  return SizedBox(
                                    width: double.infinity,
                                    child: GestureDetector(
                                      onDoubleTap: () =>
                                          _editHotel(hotel, index),
                                      child: Card(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                          vertical: 8,
                                        ),
                                        child: Stack(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.all(
                                                12.0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    hotel.hotelName!,
                                                    style: const TextStyle(
                                                      fontSize: 19,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  RichText(
                                                    text: TextSpan(
                                                      children: [
                                                        const TextSpan(
                                                          text: "Category: ",
                                                          style: TextStyle(
                                                            fontSize: 18,
                                                            color: Colors.black,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        TextSpan(
                                                          text: hotel
                                                              .roomCategoryName,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 18,
                                                                color: Colors
                                                                    .black,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  RichText(
                                                    text: TextSpan(
                                                      children: [
                                                        const TextSpan(
                                                          text: "Room Type: ",
                                                          style: TextStyle(
                                                            fontSize: 18,
                                                            color: Colors.black,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        TextSpan(
                                                          text: hotel
                                                              .roomTypeName,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 18,
                                                                color: Colors
                                                                    .black,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  RichText(
                                                    text: TextSpan(
                                                      children: [
                                                        const TextSpan(
                                                          text:
                                                              "Arrival Date: ",
                                                          style: TextStyle(
                                                            fontSize: 18,
                                                            color: Colors.black,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        TextSpan(
                                                          text:
                                                              hotel.arrivalDate !=
                                                                  null
                                                              ? DateFormat(
                                                                  'yyyy-MM-dd',
                                                                ).format(
                                                                  hotel
                                                                      .arrivalDate!,
                                                                )
                                                              : '',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 18,
                                                                color: Colors
                                                                    .black,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  RichText(
                                                    text: TextSpan(
                                                      children: [
                                                        const TextSpan(
                                                          text:
                                                              "Departure Date: ",
                                                          style: TextStyle(
                                                            fontSize: 18,
                                                            color: Colors.black,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        TextSpan(
                                                          text:
                                                              hotel.arrivalDate !=
                                                                  null
                                                              ? DateFormat(
                                                                  'yyyy-MM-dd',
                                                                ).format(
                                                                  hotel
                                                                      .departureDate!,
                                                                )
                                                              : '',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 18,
                                                                color: Colors
                                                                    .black,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        "Guest Count: ${hotel.guestCount}",
                                                        style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 20),
                                                      Text(
                                                        "Nights: ${hotel.noOfNights}",
                                                        style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),

                                                  // ── Cost display with soft warning ──
                                                  Builder(
                                                    builder: (context) {
                                                      final hasNoCost =
                                                          hotel.selectedCost ==
                                                              null ||
                                                          hotel.selectedCost ==
                                                              "0";
                                                      return Text(
                                                        hasNoCost
                                                            ? "Estimated Cost: No cost calculation done"
                                                            : "Estimated Cost: LKR ${hotel.selectedCost}",
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: hasNoCost
                                                              ? const Color.fromARGB(255, 255, 30, 0)
                                                              : Colors.black,
                                                        ),
                                                      );
                                                    },
                                                  ),

                                                  const SizedBox(height: 24),
                                                  const Text(
                                                    "Double-tap to edit",
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Positioned(
                                              bottom: 0,
                                              right: 0,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                ),
                                                onPressed: () =>
                                                    _removeHotel(index),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),

                        const SizedBox(height: 16),

                        // ── Accept Changes Button ──────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: hotelList.isNotEmpty
                                ? _acceptChanges
                                : null,
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
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cost Calculator Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class CostCalculatorBottomSheet extends StatefulWidget {
  final Function onBackPressed;
  final List<HotelCostResponse>? hotelCosts;
  final Function(HotelCostResponse, int) onItemSelected;

  const CostCalculatorBottomSheet({
    super.key,
    required this.onBackPressed,
    required this.hotelCosts,
    required this.onItemSelected,
  });

  @override
  _CostCalculatorBottomSheetState createState() =>
      _CostCalculatorBottomSheetState();
}

class _CostCalculatorBottomSheetState extends State<CostCalculatorBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Cost Calculator",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => widget.onBackPressed(),
              ),
            ],
          ),

          // ── Tabs ─────────────────────────────────────────────
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "General"),
              Tab(text: "Guest's Prev Data"),
            ],
            labelColor: Colors.black,
            indicatorColor: Colors.blue,
          ),
          const SizedBox(height: 16),

          // ── Tab Views ────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // General tab
                widget.hotelCosts == null || widget.hotelCosts!.isEmpty
                    ? const Center(
                        child: Text(
                          "No data available.",
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.hotelCosts!.length,
                        itemBuilder: (context, index) {
                          final cost = widget.hotelCosts![index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              onTap: () {
                                widget.onItemSelected(cost, index);
                                Navigator.pop(context);
                              },
                              title: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Check-In: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(cost.checkIn!))}",
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        "Check-Out: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(cost.checkOut!))}",
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    children: [
                                      const Text("Net Rate: "),
                                      Text(
                                        cost.netRate!.toStringAsFixed(2),
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                // Guest's Prev Data tab
                const Center(
                  child: Text(
                    "No previous data available.",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}