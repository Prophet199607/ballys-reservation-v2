import 'dart:convert';

import 'package:ballys_reservation_app/components/bottom_sheets/member_search-new_sheet.dart';
import 'package:ballys_reservation_app/core/constants.dart';
import 'package:ballys_reservation_app/data/repositories/coordinator_request_repository.dart';
import 'package:ballys_reservation_app/data/repositories/guest_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/coordinator.dart';
import 'package:ballys_reservation_app/models/guest_search_response.dart';
import 'package:ballys_reservation_app/providers/coordinators_provider.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// What the coordinator is being asked to book.
enum CoordinatorRequestType { airTicket, hotel, both }

extension CoordinatorRequestTypeX on CoordinatorRequestType {
  String get label => switch (this) {
        CoordinatorRequestType.airTicket => 'Air Ticket',
        CoordinatorRequestType.hotel => 'Hotel',
        CoordinatorRequestType.both => 'Both',
      };

  IconData get icon => switch (this) {
        CoordinatorRequestType.airTicket => Icons.flight,
        CoordinatorRequestType.hotel => Icons.hotel,
        CoordinatorRequestType.both => Icons.all_inclusive,
      };

  /// What goes on the wire — the label is for the screen only.
  String get code => switch (this) {
        CoordinatorRequestType.airTicket => 'AIR_TICKET',
        CoordinatorRequestType.hotel => 'HOTEL',
        CoordinatorRequestType.both => 'BOTH',
      };
}

/// A guest the coordinator is being asked to book for. Only [mid] and [name]
/// are sent; the rest is what the picker gave us, kept so the list on screen
/// can show the same card the other reservation screens do.
class CoordinatorGuest {
  const CoordinatorGuest({
    required this.mid,
    required this.name,
    this.rating = '',
    this.memberImage = '',
  });

  final String mid;
  final String name;
  final String rating;
  final String memberImage;
}

/// Coordinator Request (Ballys only).
///
/// Executives who cannot key a reservation in themselves hand it to a
/// coordinator instead. This screen collects who should do it, which guests it
/// is for, and what they are being asked to book.
class CoordinatorRequestBallysScreen extends ConsumerStatefulWidget {
  const CoordinatorRequestBallysScreen({super.key});

  @override
  ConsumerState<CoordinatorRequestBallysScreen> createState() =>
      _CoordinatorRequestBallysScreenState();
}

class _CoordinatorRequestBallysScreenState
    extends ConsumerState<CoordinatorRequestBallysScreen>
    with ConnectivityMixin {
  final _formKey = GlobalKey<FormState>();

  /// The picked coordinator, held as its `coordinator_id` rather than the
  /// object: [coordinatorsProvider] hands out fresh instances on every refetch,
  /// and a dropdown whose value is not in its own items asserts.
  String? _selectedCoordinatorId;

  CoordinatorRequestType? _requestType;

  /// The guests the request is for. A coordinator request can cover a party,
  /// so guests are staged in the two fields below and banked into this list.
  final List<CoordinatorGuest> _guests = [];

  /// Staging fields for the guest being added — cleared after each "Add Guest".
  /// [_memberIdController] holds the full BM number assembled from
  /// [_selectedPrefix] and [_memberIdNumberController], the same split the
  /// other Ballys forms use.
  final TextEditingController _memberIdController = TextEditingController();
  final TextEditingController _memberIdNumberController =
      TextEditingController();
  final TextEditingController _memberNameController = TextEditingController();

  /// Bellagio member ids carry no letter prefix; Ballys ones do.
  bool _isNumericOnlyLocation = false;
  List<String> _prefixes = const ["BM", "BL", "BN"];
  String _selectedPrefix = "BM";

  final TextEditingController _remarksController = TextEditingController();

  bool _isSearching = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadLocationPrefix();
  }

  @override
  void dispose() {
    _memberIdController.dispose();
    _memberIdNumberController.dispose();
    _memberNameController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadLocationPrefix() async {
    final location = await StorageUtil.getCurrentLocation();
    if (location == null || !mounted) return;
    final isNumeric = location.code.split('_').first == "BELLAGIO";
    setState(() {
      _isNumericOnlyLocation = isNumeric;
      _prefixes = isNumeric ? const [] : const ["BM", "BL", "BN"];
      _selectedPrefix = isNumeric ? "" : "BM";
    });
  }

  // ── Coordinators ───────────────────────────────────────────────────

  /// The loaded list, or empty while it is still loading or has failed.
  List<Coordinator> get _coordinators =>
      ref.read(coordinatorsProvider).valueOrNull ?? const [];

  Coordinator? get _selectedCoordinator {
    final id = _selectedCoordinatorId;
    if (id == null) return null;
    for (final c in _coordinators) {
      if (c.coordinatorId == id) return c;
    }
    return null;
  }

  // ── Guests ─────────────────────────────────────────────────────────

  /// Keeps the hidden full-id field in step with the prefix + number pair.
  void _syncMemberId() {
    _memberIdController.text = _isNumericOnlyLocation
        ? _memberIdNumberController.text
        : '$_selectedPrefix${_memberIdNumberController.text}';
  }

  /// Splits "BM1234" back into the dropdown prefix and the number, so a member
  /// picked from search lands in the right two fields.
  void _applyMemberId(String fullMemberId) {
    if (fullMemberId.isEmpty) return;
    if (_isNumericOnlyLocation) {
      setState(() {
        _memberIdNumberController.text = fullMemberId;
        _memberIdController.text = fullMemberId;
      });
      return;
    }
    var prefix = 'BM';
    var numberPart = fullMemberId;
    for (final candidate in const ["BM", "BL", "BN"]) {
      if (fullMemberId.startsWith(candidate)) {
        prefix = candidate;
        numberPart = fullMemberId.substring(candidate.length);
        break;
      }
    }
    setState(() {
      _selectedPrefix = prefix;
      _memberIdNumberController.text = numberPart;
      _memberIdController.text = fullMemberId;
    });
  }

  void _onMemberSelected(GuestSearchResponse guest) {
    _applyMemberId(guest.mid);
    setState(() {
      _memberNameController.text = guest.mName;
      _pendingRating = guest.gRating ?? '';
      _pendingImage = guest.memImage2;
    });
  }

  /// Rating and photo for the guest currently staged in the fields. Only a
  /// guest picked from search has them; one typed by hand carries neither.
  String _pendingRating = '';
  String _pendingImage = '';

  /// [iid] 8002 searches by member id, 8003 by name — the same pair the other
  /// reservation screens use.
  Future<void> _openMemberSearch(int iid) async {
    FocusScope.of(context).unfocus();
    final searchTerm =
        iid == 8002 ? _memberIdController.text : _memberNameController.text;

    if (searchTerm.trim().length < 3) {
      _showSearchSheet(const [], searchTerm, iid);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final guests = await GuestRepository(ApiService(SecureStorage.instance))
          .searchGuest(iid, searchTerm);
      if (!mounted) return;
      setState(() => _isSearching = false);
      _showSearchSheet(guests, searchTerm, iid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      _showMessage('Error searching guests: $e', isError: true);
    }
  }

  void _showSearchSheet(
    List<GuestSearchResponse> guests,
    String searchTerm,
    int iid,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MemberNewSearchBottomSheet(
        guests: guests,
        initialSearchTerm: searchTerm,
        searchIid: iid,
        onSearch: (term, searchIid) => _researchFromSheet(term, searchIid),
        onGuestSelected: _onMemberSelected,
      ),
    );
  }

  /// Re-runs the search from inside the sheet: the open sheet is closed and a
  /// fresh one shown with the new results.
  Future<void> _researchFromSheet(String searchTerm, int iid) async {
    if (searchTerm.trim().length < 3) return;
    try {
      final guests = await GuestRepository(ApiService(SecureStorage.instance))
          .searchGuest(iid, searchTerm);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSearchSheet(guests, searchTerm, iid);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Error searching guests: $e', isError: true);
    }
  }

  void _addGuest() {
    FocusScope.of(context).unfocus();
    _syncMemberId();

    final mid = _memberIdController.text.trim();
    final name = _memberNameController.text.trim();

    if (mid.isEmpty || (!_isNumericOnlyLocation && mid == _selectedPrefix)) {
      _showMessage('Enter the guest BM number', isError: true);
      return;
    }
    if (name.isEmpty) {
      _showMessage('Enter the guest name', isError: true);
      return;
    }
    // The same guest twice would have the coordinator booking them twice over.
    if (_guests.any((g) => g.mid.toUpperCase() == mid.toUpperCase())) {
      _showMessage('$mid is already on this request', isError: true);
      return;
    }

    setState(() {
      _guests.add(
        CoordinatorGuest(
          mid: mid,
          name: name,
          rating: _pendingRating,
          memberImage: _pendingImage,
        ),
      );
      _clearGuestFields();
    });
  }

  void _removeGuest(int index) {
    setState(() => _guests.removeAt(index));
  }

  void _clearGuestFields() {
    _memberIdController.clear();
    _memberIdNumberController.clear();
    _memberNameController.clear();
    _pendingRating = '';
    _pendingImage = '';
    _selectedPrefix = _isNumericOnlyLocation ? "" : "BM";
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final coordinator = _selectedCoordinator;
    if (coordinator == null) {
      _showMessage('Select a coordinator', isError: true);
      return;
    }
    if (_requestType == null) {
      _showMessage('Select what the coordinator should book', isError: true);
      return;
    }
    if (_guests.isEmpty) {
      _showMessage('Add at least one guest', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final result = await ref
          .read(coordinatorRequestRepositoryProvider)
          .saveCoordinatorRequest(
        coordinatorId: coordinator.coordinatorId,
        coordinatorName: coordinator.name,
        requestType: _requestType!.code,
        guests: _guests
            .map((g) => CoordinatorRequestGuest(bmNumber: g.mid, name: g.name))
            .toList(),
        remarks: _remarksController.text.trim(),
        log: (label, payload) => debugPrint('$label: $payload'),
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      _showMessage(
        result.message ?? 'Request sent to ${coordinator.name}',
        isError: !result.success,
      );
      if (result.success) _resetForm();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage('Failed to send the coordinator request: $e', isError: true);
    }
  }

  void _resetForm() {
    setState(() {
      _selectedCoordinatorId = null;
      _requestType = null;
      _guests.clear();
      _clearGuestFields();
      _remarksController.clear();
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fontSettings = ref.watch(fontSettingsProvider);
    final coordinatorsAsync = ref.watch(coordinatorsProvider);

    // A refetch can drop the coordinator that was picked — clear the selection
    // rather than leave the form pointing at someone no longer on the list.
    ref.listen(coordinatorsProvider, (_, next) {
      final list = next.valueOrNull;
      if (list == null || _selectedCoordinatorId == null) return;
      if (!list.any((c) => c.coordinatorId == _selectedCoordinatorId)) {
        setState(() => _selectedCoordinatorId = null);
      }
    });

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Coordinator Request'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/reservationMain');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Sent requests',
            icon: const Icon(Icons.history),
            onPressed: () => context.push(
              '/reservationMain/coordinator-requests-ballys',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _intro(fontSettings),
                  const SizedBox(height: 20),
                  _sectionTitle('Coordinator'),
                  const SizedBox(height: 10),
                  _coordinatorField(fontSettings, coordinatorsAsync),
                  const SizedBox(height: 20),
                  _sectionTitle('Guests'),
                  const SizedBox(height: 4),
                  Text(
                    'Who is the reservation for? Add every guest travelling.',
                    style: TextStyle(
                      fontSize: fontSettings.fontSize - 4,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _memberIdField(fontSettings),
                  const SizedBox(height: 10),
                  _memberNameField(fontSettings),
                  const SizedBox(height: 10),
                  _addGuestButton(fontSettings),
                  const SizedBox(height: 10),
                  _guestList(fontSettings),
                  const SizedBox(height: 20),
                  _sectionTitle('Request Type'),
                  const SizedBox(height: 4),
                  Text(
                    'What should the coordinator book?',
                    style: TextStyle(
                      fontSize: fontSettings.fontSize - 4,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _requestTypeSelector(fontSettings),
                  const SizedBox(height: 20),
                  _remarksField(fontSettings),
                  const SizedBox(height: 24),
                  _submitButton(fontSettings),
                ],
              ),
            ),
            if (_isSearching || _isSaving)
              Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _intro(FontSettings fontSettings) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.support_agent, color: Colors.indigo.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ask a coordinator to make the reservation on your behalf. '
              'Pick who should handle it and what needs to be booked.',
              style: TextStyle(
                fontSize: fontSettings.fontSize - 4,
                color: Colors.indigo.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      );

  /// An InputDecorator wrapping a plain DropdownButton rather than a
  /// DropdownButtonFormField: the field is fully controlled, so clearing it on
  /// reset actually empties it — the FormField's initialValue would not.
  ///
  /// The three states of [coordinatorsProvider] land here: loading shows a
  /// spinner in the suffix, an error swaps it for a retry that invalidates the
  /// provider, and data fills the dropdown.
  Widget _coordinatorField(
    FontSettings fontSettings,
    AsyncValue<List<Coordinator>> coordinatorsAsync,
  ) {
    final coordinators = coordinatorsAsync.valueOrNull ?? const <Coordinator>[];
    final isLoading = coordinatorsAsync.isLoading;
    final failed = coordinatorsAsync.hasError && !isLoading;
    final isEmpty = !isLoading && !failed && coordinators.isEmpty;
    final hasError = failed || isEmpty;

    final hint = isLoading
        ? 'Loading coordinators...'
        : failed
            ? 'Could not load coordinators'
            : isEmpty
                ? ''
                : '';

    final selected = _selectedCoordinator;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          isEmpty: selected == null,
          decoration: InputDecoration(
            labelText: 'Select Coordinator *',
            labelStyle: TextStyle(
              fontSize: fontSettings.fontSize,
              fontWeight: fontSettings.fontWeight,
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            prefixIcon: const Icon(Icons.person_outline),
            suffixIcon: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : hasError
                    ? IconButton(
                        tooltip: 'Retry',
                        icon: const Icon(Icons.refresh, color: Colors.red),
                        onPressed: () => ref.invalidate(coordinatorsProvider),
                      )
                    : null,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected?.coordinatorId,
              isExpanded: true,
              hint: Text(
                hint,
                style: TextStyle(
                  fontSize: fontSettings.fontSize - 2,
                  color: hasError ? Colors.red : Colors.grey.shade600,
                ),
              ),
              style: TextStyle(
                fontSize: fontSettings.fontSize,
                fontWeight: fontSettings.fontWeight,
                color: Colors.black,
              ),
              items: coordinators
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c.coordinatorId,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: coordinators.isEmpty
                  ? null
                  : (value) => setState(() => _selectedCoordinatorId = value),
            ),
          ),
        ),
        // The contact number is not asked for, but it is what an executive
        // needs to chase the request up, so it is shown once one is picked.
        if (selected != null && selected.contactNumber.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  selected.contactNumber,
                  style: TextStyle(
                    fontSize: fontSettings.fontSize - 5,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _memberIdField(FontSettings fontSettings) {
    return TextFormField(
      controller: _memberIdNumberController,
      keyboardType: TextInputType.number,
      style: TextStyle(
        fontSize: fontSettings.fontSize,
        fontWeight: fontSettings.fontWeight,
      ),
      decoration: InputDecoration(
        labelText: 'Guest BM Number',
        labelStyle: TextStyle(
          fontSize: fontSettings.fontSize,
          fontWeight: fontSettings.fontWeight,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        prefixIcon: _isNumericOnlyLocation
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _prefixes.contains(_selectedPrefix)
                        ? _selectedPrefix
                        : (_prefixes.isEmpty ? null : _prefixes.first),
                    style: TextStyle(
                      fontSize: fontSettings.fontSize,
                      fontWeight: fontSettings.fontWeight,
                      color: Colors.black,
                    ),
                    items: _prefixes
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedPrefix = value);
                      _syncMemberId();
                    },
                  ),
                ),
              ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            _syncMemberId();
            _openMemberSearch(8002);
          },
        ),
      ),
      onChanged: (_) {
        _syncMemberId();
        setState(() {});
      },
    );
  }

  Widget _memberNameField(FontSettings fontSettings) {
    return TextFormField(
      controller: _memberNameController,
      style: TextStyle(
        fontSize: fontSettings.fontSize,
        fontWeight: fontSettings.fontWeight,
      ),
      decoration: InputDecoration(
        labelText: 'Guest Name',
        labelStyle: TextStyle(
          fontSize: fontSettings.fontSize,
          fontWeight: fontSettings.fontWeight,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        suffixIcon: IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _openMemberSearch(8003),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _addGuestButton(FontSettings fontSettings) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _isSaving ? null : _addGuest,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(
          'Add Guest',
          style: TextStyle(
            fontSize: fontSettings.fontSize - 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Constants.kPrimaryColor,
          side: BorderSide(color: Constants.kPrimaryColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _guestList(FontSettings fontSettings) {
    if (_guests.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(
              'No guests added yet',
              style: TextStyle(
                fontSize: fontSettings.fontSize - 4,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_guests.length} guest${_guests.length == 1 ? '' : 's'} added',
          style: TextStyle(
            fontSize: fontSettings.fontSize - 4,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _guests.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: ListTile(
              leading: _guestAvatar(_guests[i]),
              title: Text(
                _guests[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSettings.fontSize - 3,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _guests[i].rating.isEmpty
                    ? _guests[i].mid
                    : '${_guests[i].mid}  •  ${_guests[i].rating}',
                style: TextStyle(fontSize: fontSettings.fontSize - 5),
              ),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _isSaving ? null : () => _removeGuest(i),
              ),
            ),
          ),
      ],
    );
  }

  /// The member photo comes back base64-encoded and is sometimes empty or
  /// malformed, so a bad decode falls back to the placeholder rather than
  /// throwing mid-build.
  Widget _guestAvatar(CoordinatorGuest guest) {
    if (guest.memberImage.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 20,
          backgroundImage: MemoryImage(base64Decode(guest.memberImage)),
        );
      } catch (_) {
        // Fall through to the placeholder below.
      }
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: Constants.kPrimaryColor.withOpacity(0.15),
      child: Icon(Icons.person, color: Constants.kPrimaryColor),
    );
  }

  Widget _requestTypeSelector(FontSettings fontSettings) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: CoordinatorRequestType.values.map((type) {
        final selected = _requestType == type;
        return ChoiceChip(
          avatar: Icon(
            type.icon,
            size: 18,
            color: selected ? Colors.white : Colors.black54,
          ),
          label: Text(type.label),
          selected: selected,
          selectedColor: Constants.kPrimaryColor,
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: fontSettings.fontSize - 4,
            fontWeight: selected ? FontWeight.bold : fontSettings.fontWeight,
          ),
          onSelected: (_) => setState(() => _requestType = type),
        );
      }).toList(),
    );
  }

  Widget _remarksField(FontSettings fontSettings) {
    return TextFormField(
      controller: _remarksController,
      maxLines: 4,
      style: TextStyle(
        fontSize: fontSettings.fontSize,
        fontWeight: fontSettings.fontWeight,
      ),
      decoration: InputDecoration(
        labelText: 'Remarks',
        hintText: 'Dates, flight or hotel preferences, anything else',
        labelStyle: TextStyle(
          fontSize: fontSettings.fontSize,
          fontWeight: fontSettings.fontWeight,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
      ),
    );
  }

  Widget _submitButton(FontSettings fontSettings) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _submit,
        icon: const Icon(Icons.send),
        label: Text(
          'Send Request',
          style: TextStyle(
            fontSize: fontSettings.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Constants.kPrimaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
