import 'dart:io';

import 'package:ballys_reservation_app/components/bottom_sheets/member_search-new_sheet.dart';
import 'package:ballys_reservation_app/components/guest_deatils_view_spGift.dart';
import 'package:ballys_reservation_app/components/passport_upload_widget_ballys.dart';
import 'package:ballys_reservation_app/data/repositories/group_reservation_repository.dart';
import 'package:ballys_reservation_app/data/repositories/guest_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/guest_modal.dart';
import 'package:ballys_reservation_app/models/guest_search_response.dart';
import 'package:ballys_reservation_app/models/reservation/group_guest_sheet.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/providers/member_search_provider.dart';
import 'package:ballys_reservation_app/providers/selected_guest_provider.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Group reservation (Ballys only).
///
/// Guests often arrive as a party rather than one at a time. Typing every
/// traveller into the normal reservation form does not scale, so this screen
/// takes only the lead guest's BM number and name, the Excel sheet listing the
/// rest of the party, and the passport pages (photos and PDFs) for the group.
class GroupReservationBallysScreen extends ConsumerStatefulWidget {
  const GroupReservationBallysScreen({super.key});

  @override
  ConsumerState<GroupReservationBallysScreen> createState() =>
      _GroupReservationBallysScreenState();
}

class _GroupReservationBallysScreenState
    extends ConsumerState<GroupReservationBallysScreen>
    with ConnectivityMixin {
  final _formKey = GlobalKey<FormState>();

  /// The full BM number ("BM1234"), assembled from [_selectedPrefix] and
  /// [_memberIdNumberController] — the same split the other Ballys forms use.
  final TextEditingController _memberIdController = TextEditingController();
  final TextEditingController _memberIdNumberController =
      TextEditingController();
  final TextEditingController _memberNameController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  /// Bellagio member ids carry no letter prefix; Ballys ones do.
  bool _isNumericOnlyLocation = false;
  List<String> _prefixes = const ["BM", "BL", "BN"];
  String _selectedPrefix = "BM";

  GroupGuestSheet? _guestSheet;
  List<PassportFileBallys> _passportFiles = const [];

  /// Bumped on reset so the passport uploader is rebuilt from scratch — it
  /// reads [PassportUploadWidgetBallys.initialFiles] once, in initState, so
  /// clearing our list alone would leave its thumbnails on screen.
  int _passportFormGeneration = 0;

  bool _isSearching = false;
  bool _isSaving = false;

  /// Spreadsheet formats the backend accepts for the guest list. CSV is in the
  /// list because exporting one is often the only option guests have.
  static const List<String> _sheetExtensions = ['xlsx', 'xls', 'csv'];

  @override
  void initState() {
    super.initState();
    _loadLocationPrefix();
    // Clearing the shared guest card has to wait for the first frame — writing
    // to a StateNotifier while the widget tree is still building throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(memberSearchProvider.notifier).resetState();
    });
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

  // ── Member lookup ─────────────────────────────────────────────────────────

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
    setState(() => _memberNameController.text = guest.mName);

    ref
        .read(memberSearchProvider.notifier)
        .updateMemberInfo(guest.mid, guest.mName);

    // Feeds the guest card below the fields (rating / last visit / photo).
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

  // ── Guest details sheet ───────────────────────────────────────────────────

  Future<void> _pickGuestSheet() async {
    FocusScope.of(context).unfocus();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _sheetExtensions,
      );
      final picked = result?.files.single;
      if (picked?.path == null) return;

      // The picker hands back a cache copy that can be evicted before the form
      // is submitted, so keep our own copy in app storage.
      final stored = await _persist(picked!.path!);
      if (!mounted) return;
      setState(() {
        _guestSheet = GroupGuestSheet(
          path: stored.path,
          fileName: picked.name,
          sizeBytes: stored.lengthSync(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not pick the guest sheet: $e', isError: true);
    }
  }

  Future<File> _persist(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final sheetDir = Directory('${dir.path}/group_guest_sheets');
    if (!await sheetDir.exists()) {
      await sheetDir.create(recursive: true);
    }
    final name = sourcePath.split('/').last;
    return File(sourcePath).copy(
      '${sheetDir.path}/${DateTime.now().microsecondsSinceEpoch}_$name',
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    _syncMemberId();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_guestSheet == null) {
      _showMessage('Attach the guest details Excel sheet', isError: true);
      return;
    }
    if (_passportFiles.isEmpty) {
      _showMessage('Add at least one passport page for the group',
          isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final result =
          await GroupReservationRepository(ApiService(SecureStorage.instance))
              .saveGroupReservation(
        bmNumber: _memberIdController.text.trim(),
        guestName: _memberNameController.text.trim(),
        guestSheet: _guestSheet,
        passportFiles: _passportFiles,
        remarks: _remarksController.text.trim(),
        log: (label, payload) => debugPrint('$label: $payload'),
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      _showMessage(
        result.message ?? 'Group reservation saved',
        isError: !result.success,
      );
      if (result.success) _resetForm();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage('Failed to save group reservation: $e', isError: true);
    }
  }

  void _resetForm() {
    setState(() {
      _memberIdController.clear();
      _memberIdNumberController.clear();
      _memberNameController.clear();
      _remarksController.clear();
      _guestSheet = null;
      _passportFiles = const [];
      _passportFormGeneration++;
    });
    ref.read(memberSearchProvider.notifier).resetState();
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

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Group Reservation'),
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
               //   const SizedBox(height: 16),
               //   _sectionTitle('One Guest'),
                  const SizedBox(height: 10),
                  _memberIdField(fontSettings),
                  const SizedBox(height: 10),
                  _memberNameField(fontSettings),
                  GuestDisplayCardSpecialGiftview(
                    memberIdText: _memberIdController.text,
                    memberNameText: _memberNameController.text,
                    showCard: _memberIdController.text.isNotEmpty &&
                        _memberNameController.text.isNotEmpty,
                    showLastVisitDate: true,
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Guest Details Sheet'),
                  const SizedBox(height: 4),
                  Text(
                    'Attach the Excel sheet listing everyone travelling  '
                    ' (.${_sheetExtensions.join(', .')}).',
                    style: TextStyle(
                      fontSize: fontSettings.fontSize - 4,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _guestSheetCard(fontSettings),
                  const SizedBox(height: 20),
                  PassportUploadWidgetBallys(
                    key: ValueKey('passports-$_passportFormGeneration'),
                    title: 'Guest Passport Details',
                    guestBmNumber: _memberIdController.text.trim(),
                    guestName: _memberNameController.text.trim(),
                    initialFiles: _passportFiles.isEmpty ? null : _passportFiles,
                    onFilesChanged: (files) =>
                        setState(() => _passportFiles = files),
                  ),
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
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.groups, color: Colors.deepPurple.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'For parties arriving together. Key in the one guest only — the '
              'rest of the group comes from the attached sheet.',
              style: TextStyle(
                fontSize: fontSettings.fontSize - 4,
                color: Colors.deepPurple.shade700,
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

  Widget _memberIdField(FontSettings fontSettings) {
    return TextFormField(
      controller: _memberIdNumberController,
      keyboardType: TextInputType.number,
      style: TextStyle(
        fontSize: fontSettings.fontSize,
        fontWeight: fontSettings.fontWeight,
      ),
      decoration: InputDecoration(
        labelText: 'BM Number *',
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
      validator: (value) => (value == null || value.trim().isEmpty)
          ? 'Guest BM Number is required'
          : null,
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
        labelText: 'Guest Name *',
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
      validator: (value) => (value == null || value.trim().isEmpty)
          ? 'Guest Name is required'
          : null,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _guestSheetCard(FontSettings fontSettings) {
    final sheet = _guestSheet;

    if (sheet == null) {
      return GestureDetector(
        onTap: _pickGuestSheet,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Icon(Icons.table_chart_outlined,
                  size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                'Tap to upload the guest details sheet',
                style: TextStyle(
                  fontSize: fontSettings.fontSize - 4,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        leading: const Icon(Icons.table_chart, color: Colors.green, size: 32),
        title: Text(
          sheet.fileName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSettings.fontSize - 3),
        ),
        subtitle: Text(sheet.readableSize),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_new, color: Colors.blue),
              onPressed: () => OpenFilex.open(sheet.path),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => setState(() => _guestSheet = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _remarksField(FontSettings fontSettings) {
    return TextFormField(
      controller: _remarksController,
      maxLines: 3,
      style: TextStyle(
        fontSize: fontSettings.fontSize,
        fontWeight: fontSettings.fontWeight,
      ),
      decoration: InputDecoration(
        labelText: 'Remarks',
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
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Submit Group Reservation',
          style: TextStyle(
            fontSize: fontSettings.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
