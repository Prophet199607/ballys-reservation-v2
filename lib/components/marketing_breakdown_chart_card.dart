import 'dart:math';
import 'dart:ui' as ui;

import 'package:ballys_reservation_app/core/constants.dart';
import 'package:ballys_reservation_app/data/repositories/guest_repository.dart';
import 'package:ballys_reservation_app/models/guest_modal.dart';
import 'package:ballys_reservation_app/models/marketing_group.dart';
import 'package:ballys_reservation_app/providers/guests_provider.dart';
import 'package:ballys_reservation_app/providers/selected_guest_provider.dart';
import 'package:ballys_reservation_app/utils/connectivity_mixin.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

void showAccessDeniedDialog(BuildContext context) {
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Constants.kPrimaryColor,
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

// Groups guests by country, sorted by count desc
Map<String, List<Guest>> groupByCountry(List<Guest> guests) {
  final Map<String, List<Guest>> grouped = {};
  for (final g in guests) {
    final key = g.country.isNotEmpty ? g.country : 'Unknown';
    grouped.putIfAbsent(key, () => []).add(g);
  }
  return Map.fromEntries(
    grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length)),
  );
}

// Half-pie geometry, shared by the painter and the hit-test so they stay in sync.
const double _kRadiusFactor = 0.88;
const double _kMaxRadius = 150;
const double _kInnerRadiusFactor = 0.55;
const double _kBaselinePadding = 8;
// A hovered slice paints 6px thicker, half of which spills past the outer edge.
const double _kHoverExpand = 6;

// Every bottom sheet this card opens is tagged with this route name, so opening
// a member profile can pop the whole sheet stack — the country / sales-person
// list included — instead of just the topmost sheet.
const String _kVisitSheetRoute = 'visit-summary-sheet';
const RouteSettings _kVisitSheetSettings =
    RouteSettings(name: _kVisitSheetRoute);

double _radiusFor(double width) =>
    min((width / 2) * _kRadiusFactor, _kMaxRadius);

const List<Color> _sliceColors = [
  Color(0xFFE91E63),
  Color(0xFF00BCD4),
  Color(0xFFE4750E),
  Color(0xFF2A7DC0),
  Color(0xFF4CAF50),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
  Color(0xFFFF9800),
  Color(0xFF00BCD4),
  Color(0xFF795548),
];

class MarketingBreakdownHalfPieCard extends ConsumerStatefulWidget {
  const MarketingBreakdownHalfPieCard({super.key});

  @override
  ConsumerState<MarketingBreakdownHalfPieCard> createState() =>
      _MarketingBreakdownHalfPieCardState();
}

class _MarketingBreakdownHalfPieCardState
    extends ConsumerState<MarketingBreakdownHalfPieCard> with ConnectivityMixin{
  int _selectedPeriod = 0;
  String? _myDataCode;

  final Set<int> _loadedPeriods = {};

  static const List<String> _periodLabels = ['Today', 'Yesterday', 'Monthly'];
  static const List<Color> _tabColors = [
    Color(0xFFE4750E),
    Color(0xFF4CAF50),
    Color(0xFF2A7DC0),
  ];

  @override
  void initState() {
    super.initState();
    _loadMyDataCode();
  }

  Future<void> _loadMyDataCode() async {
    final code = await StorageUtil.getMarketingCode();
    if (mounted) setState(() => _myDataCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final guestsState = ref.watch(guestsProvider);

    final allGroups = [
      guestsState.todayMarketingGroups,
      guestsState.yesterdayMarketingGroups,
      guestsState.monthlyMarketingGroups,
    ];

    final allGuests = [
      guestsState.todayGuests,
      guestsState.yesterdayGuests,
      guestsState.monthlyGuests,
    ];

    final allMarketingGuests = [
      guestsState.todayAllMarketingGuests,
      guestsState.yesterdayAllMarketingGuests,
      guestsState.monthlyAllMarketingGuests,
    ];

    final allNonMarketingGuests = [
      guestsState.todayNonMarketingGuests,
      guestsState.yesterdayNonMarketingGuests,
      guestsState.monthlyNonMarketingGuests,
    ];

    final allOtherMarketingGuests = [
      guestsState.todayOtherMarketingGuests,
      guestsState.yesterdayOtherMarketingGuests,
      guestsState.monthlyOtherMarketingGuests,
    ];

    final allSalesPersonGroups = [
      guestsState.todaySalesPersonGroups,
      guestsState.yesterdaySalesPersonGroups,
      guestsState.monthlySalesPersonGroups,
    ];

    final allLayouts = [
      guestsState.todayLayout,
      guestsState.yesterdayLayout,
      guestsState.monthlyLayout,
    ];

    for (int i = 0; i < allGroups.length; i++) {
      if (allGroups[i].isNotEmpty) _loadedPeriods.add(i);
    }

    final selectedGroups = allGroups[_selectedPeriod];
    final isLoaded = _loadedPeriods.contains(_selectedPeriod);
    final total = selectedGroups.fold<int>(0, (s, g) => s + g.rc);

    final displayGroups = selectedGroups
        .where((g) => g.gCode.isNotEmpty && g.rc > 0)
        .toList()
      ..sort((a, b) => b.rc.compareTo(a.rc));

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pie_chart_rounded,
                    color: Color(0xFF2A7DC0), size: 22),
                SizedBox(width: 8),
                Text(
                  'Visit Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _PeriodTabBar(
              selectedIndex: _selectedPeriod,
              labels: _periodLabels,
              colors: _tabColors,
              onTap: (i) => setState(() => _selectedPeriod = i),
              fontSize: 15,
            ),
            const SizedBox(height: 16),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: !isLoaded
                  ? const _LoadingPlaceholder()
                  : displayGroups.isEmpty
                      ? const _EmptyPlaceholder()
                      : _HalfPieSection(
                          key: ValueKey(
                              '$_selectedPeriod-${displayGroups.length}'),
                          groups: displayGroups,
                          total: total,
                          myDataCode: _myDataCode,
                          selectedPeriod: _selectedPeriod,
                          tabColors: _tabColors,
                          marketingGuests: allMarketingGuests[_selectedPeriod],
                          nonMarketingGuests:
                              allNonMarketingGuests[_selectedPeriod],
                          myDataGuests: allGuests[_selectedPeriod],
                          otherMarketingGuests:
                              allOtherMarketingGuests[_selectedPeriod],
                          salesPersonGroups:
                              allSalesPersonGroups[_selectedPeriod],
                          layout: allLayouts[_selectedPeriod],
                          periodLabel: _periodLabels[_selectedPeriod],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Half-pie + legend
// ────────────────────────────────────────────────────────────────────────────
class _HalfPieSection extends StatefulWidget {
  final List<MarketingGroup> groups;
  final int total;
  final String? myDataCode;
  final int selectedPeriod;
  final List<Color> tabColors;
  final List<Guest> marketingGuests;
  final List<Guest> nonMarketingGuests;
  final List<Guest> myDataGuests;
  final List<Guest> otherMarketingGuests;
  final List<MarketingGroup> salesPersonGroups;
  final ResponseLayout layout;
  final String periodLabel;

  const _HalfPieSection({
    super.key,
    required this.groups,
    required this.total,
    required this.myDataCode,
    required this.selectedPeriod,
    required this.tabColors,
    required this.marketingGuests,
    required this.nonMarketingGuests,
    required this.myDataGuests,
    required this.otherMarketingGuests,
    required this.salesPersonGroups,
    required this.layout,
    required this.periodLabel,
  });

  @override
  State<_HalfPieSection> createState() => _HalfPieSectionState();
}

class _HalfPieSectionState extends State<_HalfPieSection>
    with SingleTickerProviderStateMixin,ConnectivityMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  int? _hoveredIndex;

  // Other Marketing is a Bellagio-only escape hatch: sales code AD001 may
  // open it there. Every other Bellagio user, and Bally's regardless of
  // sales code, sees Access Denied when tapping it.
  String? _userSalesCode;
  bool _isBellagio = false;

  // Level 3 users may read the Visit Summary chart but not drill into any of
  // its legend rows - every one of them shows Access Denied instead.
  String? _userLevel;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _animation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
    _loadAccessSettings();
  }

  Future<void> _loadAccessSettings() async {
    final userSalesCode = await StorageUtil.getSalesCode();
    final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
    final userLevel = await StorageUtil.getUserLevel();
    if (!mounted) return;
    setState(() {
      _userSalesCode = userSalesCode;
      _isBellagio = apiUrl.contains('bty.world');
      _userLevel = userLevel;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _colorFor(int index) {
    final g = widget.groups[index];
    final isMyData = widget.myDataCode != null &&
        (g.gCode == widget.myDataCode || g.gName == 'My Data');
    if (isMyData) return widget.tabColors[widget.selectedPeriod];
    return _sliceColors[index % _sliceColors.length];
  }

  void _showSheet(BuildContext context, MarketingGroup group, Color color) {
    if (_userLevel == '3') {
      showAccessDeniedDialog(context);
      return;
    }

    final gCode = group.gCode;
    final label = widget.periodLabel;

    // ── ADMIN layout ──────────────────────────────────────────────────────

    if (widget.layout == ResponseLayout.admin) {
      if (gCode == 'MKT') {
        // Drop the user's own group only when the pie carries a separate
        // "My Data" slice (My Data mode) — otherwise it would be counted
        // twice. In Overall Data mode the MKT slice covers every sales
        // person, so the breakdown must list them all, the user included.
        final hasMyDataSlice = widget.myDataCode != null &&
            widget.groups.any((g) =>
                g.gCode == widget.myDataCode || g.gName == 'My Data');
        final excludedCode = hasMyDataSlice ? widget.myDataCode : null;

        final Map<String, List<Guest>> personMap = {};
        for (final sp in widget.salesPersonGroups) {
          if (excludedCode != null && sp.gCode == excludedCode) continue;
          personMap[sp.gCode] =
              widget.marketingGuests.where((g) => g.mGroup == sp.gCode).toList();
        }
        final filteredOrder = widget.salesPersonGroups
            .where((sp) => excludedCode == null || sp.gCode != excludedCode)
            .toList();
        showModalBottomSheet(
          context: context,
          // Host on the root navigator: the shell Scaffold's body shrinks by
          // the keyboard inset, which would clamp this sheet and snap it to
          // the top of the screen the moment the search field gets focus.
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          routeSettings: _kVisitSheetSettings,
          builder: (_) => _SalesPersonsSheet(
            title: 'Marketing — $label',
            salesPersons: personMap,
            salesPersonOrder: filteredOrder,
            accentColor: color,
          ),
        );
        return;
      }

      if (gCode == 'NON') {
        showModalBottomSheet(
          context: context,
          // Host on the root navigator: the shell Scaffold's body shrinks by
          // the keyboard inset, which would clamp this sheet and snap it to
          // the top of the screen the moment the search field gets focus.
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          routeSettings: _kVisitSheetSettings,
          builder: (_) => _SalesPersonsSheet(
            title: 'Non Marketing — $label',
            salesPersons: groupByCountry(widget.nonMarketingGuests),
            accentColor: color,
            useKeyAsName: true,
            allowAllUsers: true,
          ),
        );
        return;
      }

      if (gCode == widget.myDataCode || group.gName == 'My Data') {
        showModalBottomSheet(
          context: context,
          // Host on the root navigator: the shell Scaffold's body shrinks by
          // the keyboard inset, which would clamp this sheet and snap it to
          // the top of the screen the moment the search field gets focus.
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          routeSettings: _kVisitSheetSettings,
          builder: (_) => _MemberVisitsSheet(
            title: 'My Visits — $label',
            guests: widget.myDataGuests,
            accentColor: color,
          ),
        );
        return;
      }

      return;
    }

    // ── REGULAR layouts ───────────────────────────────────────────────────

    if (gCode == 'NON') {
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        routeSettings: _kVisitSheetSettings,
        builder: (_) => _SalesPersonsSheet(
          title: 'Non Marketing — $label',
          salesPersons: groupByCountry(widget.nonMarketingGuests),
          accentColor: color,
          useKeyAsName: true,
          allowAllUsers: true,
        ),
      );
      return;
    }

    if (gCode == 'OTHER') {
      // Bellagio only: sale code AD001 can open Other Marketing; everyone
      // else gets Access Denied.
      if (_isBellagio && _userSalesCode != 'AD001') {
        showAccessDeniedDialog(context);
        return;
      }
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        routeSettings: _kVisitSheetSettings,
        builder: (_) => _SalesPersonsSheet(
          title: 'Other Marketing — $label',
          salesPersons: groupByMGroup(widget.otherMarketingGuests),
          accentColor: color,
          disableNavigation: true,
        ),
      );
      return;
    }

    if (gCode == widget.myDataCode || group.gName == 'My Data') {
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        routeSettings: _kVisitSheetSettings,
        builder: (_) => _MemberVisitsSheet(
          title: 'My Visits — $label',
          guests: widget.myDataGuests,
          accentColor: color,
        ),
      );
      return;
    }

    final personGuests =
        widget.marketingGuests.where((g) => g.mGroup == gCode).toList();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      routeSettings: _kVisitSheetSettings,
      builder: (_) => _MemberVisitsSheet(
        title: '${group.gName} — $label',
        guests: personGuests,
        accentColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final radius = _radiusFor(constraints.maxWidth);
            return AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                return SizedBox(
                  height: radius + _kHoverExpand / 2 + _kBaselinePadding,
                  child: GestureDetector(
                    onTapUp: (d) => _handleTap(d, constraints.maxWidth),
                    child: CustomPaint(
                      painter: _HalfPiePainter(
                        groups: widget.groups,
                        total: widget.total,
                        progress: _animation.value,
                        hoveredIndex: _hoveredIndex,
                        colorForIndex: _colorFor,
                        radius: radius,
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              bottom: _kBaselinePadding),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.total.toString(),
                                style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black87),
                              ),
                              const Text('Total Visits',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Color.fromARGB(255, 0, 0, 0))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 12),

        Column(
          children: List.generate(widget.groups.length, (i) {
            final g = widget.groups[i];
            final pct = widget.total > 0
                ? (g.rc / widget.total * 100).toStringAsFixed(1)
                : '0.0';
            final color = _colorFor(i);
            final isActive = _hoveredIndex == null || _hoveredIndex == i;

            return AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isActive ? 1.0 : 0.35,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showSheet(context, g, color),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            g.gName,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          g.rc.toString(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$pct %',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.chevron_right,
                            color: color.withOpacity(0.6), size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  void _handleTap(TapUpDetails details, double width) {
    final localPos = details.localPosition;
    final radius = _radiusFor(width);
    final innerRadius = radius * _kInnerRadiusFactor;

    // The GestureDetector spans the chart box, so localPosition is already
    // relative to it; mirror the painter's centre.
    final dx = localPos.dx - width / 2;
    final dy = localPos.dy - (radius + _kHoverExpand / 2);
    final distance = sqrt(dx * dx + dy * dy);

    if (distance < innerRadius || distance > radius) {
      setState(() => _hoveredIndex = null);
      return;
    }

    double total = widget.groups.fold(0, (s, g) => s + g.rc).toDouble();
    double start = 0;
    for (int i = 0; i < widget.groups.length; i++) {
      final sweep = (widget.groups[i].rc / total) * pi;
      final sliceStart = pi + start;
      final sliceEnd = sliceStart + sweep;

      double a = atan2(dy, dx);
      if (a < 0) a += 2 * pi;
      double ss = sliceStart < 0 ? sliceStart + 2 * pi : sliceStart;
      double se = sliceEnd < 0 ? sliceEnd + 2 * pi : sliceEnd;

      if (a >= ss && a <= se) {
        setState(() => _hoveredIndex = _hoveredIndex == i ? null : i);
        return;
      }
      start += sweep;
    }
    setState(() => _hoveredIndex = null);
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Sales-persons style sheet
// ────────────────────────────────────────────────────────────────────────────
class _SalesPersonsSheet extends StatefulWidget {
  final String title;
  final Map<String, List<Guest>> salesPersons;
  final Color accentColor;
  final bool useKeyAsName;
  final bool disableNavigation;
  final List<MarketingGroup>? salesPersonOrder;

  /// Bally's-only: let every user open these member profiles, ignoring the
  /// marketing-group check. See [_MemberVisitsSheet.allowAllUsers].
  final bool allowAllUsers;

  const _SalesPersonsSheet({
    required this.title,
    required this.salesPersons,
    required this.accentColor,
    this.useKeyAsName = false,
    this.salesPersonOrder,
    this.disableNavigation = false,
    this.allowAllUsers = false,
  });

  @override
  State<_SalesPersonsSheet> createState() => _SalesPersonsSheetState();
}

class _SalesPersonsSheetState extends State<_SalesPersonsSheet> with ConnectivityMixin {
  late List<_PersonRow> _all;
  late List<_PersonRow> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _all = _buildRows();
    _filtered = _all;
    _searchCtrl.addListener(_onSearch);
  }

  List<_PersonRow> _buildRows() {
    if (widget.salesPersonOrder != null) {
      return widget.salesPersonOrder!.map((sp) {
        final guests = widget.salesPersons[sp.gCode] ?? [];
        return _PersonRow(
          key: sp.gCode,
          displayName: sp.gName,
          count: sp.rc,
          guests: guests,
        );
      }).toList();
    }

    return widget.salesPersons.entries.map((e) {
      final guests = e.value;
      final displayName = widget.useKeyAsName
          ? e.key
          : (guests.isNotEmpty ? (guests.first.gName ?? e.key) : e.key);
      return _PersonRow(
        key: e.key,
        displayName: displayName,
        count: guests.length,
        guests: guests,
      );
    }).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all
              .where((r) => r.displayName.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.title,
      accentColor: widget.accentColor,
      count: _filtered.length,
      searchCtrl: _searchCtrl,
      searchHint:
          widget.useKeyAsName ? 'Search country…' : 'Search sales person…',
      child: _filtered.isEmpty
          ? _emptyWidget()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final row = _filtered[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 1.5,
                  child: ListTile(
                    onTap: row.guests.isEmpty
                        ? null
                        : () {
                            showModalBottomSheet(
                              context: context,
                              useRootNavigator: true,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              routeSettings: _kVisitSheetSettings,
                              builder: (_) => _MemberVisitsSheet(
                                title: widget.useKeyAsName
                                    ? row.displayName
                                    : '${row.displayName} — visits',
                                guests: row.guests,
                                accentColor: widget.accentColor,
                                showBackButton: true,
                                disableNavigation: widget.disableNavigation,
                                allowAllUsers: widget.allowAllUsers,
                              ),
                            );
                          },
                    title: Text(
                      row.displayName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    trailing: CircleAvatar(
                      radius: 20,
                      backgroundColor: widget.accentColor.withOpacity(0.15),
                      child: Text(
                        '${row.count}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PersonRow {
  final String key;
  final String displayName;
  final int count;
  final List<Guest> guests;
  _PersonRow({
    required this.key,
    required this.displayName,
    required this.count,
    required this.guests,
  });
}

// ────────────────────────────────────────────────────────────────────────────
// Member-visits style sheet
// ────────────────────────────────────────────────────────────────────────────
class _MemberVisitsSheet extends ConsumerStatefulWidget {
  final String title;
  final List<Guest> guests;
  final Color accentColor;
  final bool showBackButton;
  final bool disableNavigation;

  /// Bally's-only escape hatch for the Non Marketing breakdown: those guests
  /// carry no mGroup, so the usual marketing-group check would lock everyone
  /// but AD001 out. Ignored on Bellagio (bty.world).
  final bool allowAllUsers;

  const _MemberVisitsSheet({
    required this.title,
    required this.guests,
    required this.accentColor,
    this.showBackButton = false,
    this.disableNavigation = false,
    this.allowAllUsers = false,
  });

  @override
  ConsumerState<_MemberVisitsSheet> createState() => _MemberVisitsSheetState();
}

class _MemberVisitsSheetState extends ConsumerState<_MemberVisitsSheet> with ConnectivityMixin{
  late List<Guest> _filtered;
  final _searchCtrl = TextEditingController();

  // ── Profile access gating (mirrors MarketingDetailPage) ──
  bool? _memProfSH;
  String? _userMarketingCode;
  String? _userSalesCode;

  // ── Rating mode (mirrors ProfileScreen + MemberVisits) ──
  bool _useBadgeForRating = false;

  // Bally's is every deployment that is not bty.world (Bellagio).
  bool _isBallys = false;

  // static const Map<String, String> _ratingImages = {
  //   "CLASSIC": "assets/images/ratings/CLASSIC.png",
  //   "DIAMOND": "assets/images/ratings/DIAMOND.png",
  //   "GOLD": "assets/images/ratings/GOLD.png",
  //   "INFINITY": "assets/images/ratings/INFINITY.png",
  //   "PLATINUM": "assets/images/ratings/PLATINUM.png",
  //   "SILVER": "assets/images/ratings/SILVER.png",
  // };
 Color _getRatingColorBallys(String? rating) {
    switch ((rating ?? '').toUpperCase()) {
      case 'GOLD':
        return const Color(0xFFDAA520);
      case 'PLATINUM':
        return const Color(0xFF707070);
      case 'DIAMOND':
        return const Color(0xFF1565C0);
      case 'SILVER':
        return const Color(0xFF9E9E9E);
      case 'INFINITY':
        return const Color(0xFF4A148C);
      case 'CLASSIC':
        return const Color(0xFF5D4037);
      case 'PREMIER':
        return const Color(0xFF1B5E20);
      case 'RAFFELS CLUB':
        return const Color(0xFF880E4F);
      default:
        return Colors.grey;
    }
  }
  @override
  void initState() {
    super.initState();
    _filtered = widget.guests;
    _searchCtrl.addListener(_onSearch);
    _loadRatingMode();
    _loadAccessSettings();
  }

  Future<void> _loadRatingMode() async {
    final apiUrl = await StorageUtil.getCurrentApiUrl() ?? '';
    if (mounted) {
      setState(() {
        _useBadgeForRating = apiUrl.contains('bty.world');
        _isBallys = !apiUrl.contains('bty.world');
      });
    }
  }

  Future<void> _loadAccessSettings() async {
    final memProfSH = await StorageUtil.getMemProfSH();
    final userMarketingCode = await StorageUtil.getMarketingCode();
    final userSalesCode = await StorageUtil.getSalesCode();
    if (mounted) {
      setState(() {
        _memProfSH = memProfSH;
        _userMarketingCode = userMarketingCode;
        _userSalesCode = userSalesCode;
      });
    }
  }

  // Other Marketing member profiles are a Bellagio-only escape hatch: sales
  // code AD001 may open them there. Every other Bellagio user, and Bally's
  // regardless of sales code, sees Access Denied.
  bool _otherMarketingAccessAllowed() {
    return !_isBallys && _userSalesCode == 'AD001';
  }

  // Sales code AD001 can view every member profile.
  // Otherwise, when memProfSH is null or true, every member is accessible.
  // When memProfSH is false, only members in the logged-in user's
  // marketing group can be opened.

  bool _hasPermissionToViewMember(Guest guest) {
    if (_userSalesCode == 'AD001') {
      return true;
    }

    // Non Marketing on Bally's: open to every user.
    if (widget.allowAllUsers && _isBallys) {
      return true;
    }

    // if (_memProfSH == null || _memProfSH == true) {
    //   return true;
    // }

    if (_userSalesCode != 'AD001') {
      return _userMarketingCode != null &&
          (guest.mGroup ?? '').isNotEmpty &&
          _userMarketingCode == guest.mGroup;
    }

    return true;
  }

  Color _getRatingColor(String? rating) {
    switch ((rating ?? '').toUpperCase()) {
      case 'GOLD':
        return const Color(0xFFDAA520);
      case 'PLATINUM':
        return const Color(0xFF707070);
      case 'DIAMOND':
        return const Color(0xFF1565C0);
      case 'SILVER':
        return const Color(0xFF9E9E9E);
      case 'INFINITY':
        return const Color(0xFF4A148C);
      case 'PREMIER':
        return const Color(0xFF1B5E20);
      case 'RAFFELS CLUB':
        return const Color(0xFF880E4F);
      case 'CLASSIC':
        return const Color(0xFF5D4037);
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.guests
          : widget.guests.where((g) {
              return g.memberName.toLowerCase().contains(q) ||
                  g.mid.toLowerCase().contains(q) ||
                  g.country.toLowerCase().contains(q);
            }).toList();
    });
  }

  void _showAccessDeniedDialog() => showAccessDeniedDialog(context);

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: widget.title,
      accentColor: widget.accentColor,
      count: _filtered.length,
      searchCtrl: _searchCtrl,
      searchHint: 'Search by name, ID or country…',
      showBackButton: widget.showBackButton,
      child: _filtered.isEmpty
          ? _emptyWidget()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final guest = _filtered[index];

                return Stack(
                  children: [
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 1.5,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          final denied = widget.disableNavigation
                              ? !_otherMarketingAccessAllowed()
                              : !_hasPermissionToViewMember(guest);
                          if (denied) {
                            _showAccessDeniedDialog();
                            return;
                          }
                          ref
                              .read(selectedGuestProvider.notifier)
                              .setSelectedGuest(guest);
                          // Close this sheet *and* the list that opened it
                          // (country / sales person) — popping only the top
                          // one leaves that list sitting over the profile.
                          final router = GoRouter.of(context);
                          Navigator.of(context, rootNavigator: true).popUntil(
                            (route) =>
                                route.settings.name != _kVisitSheetRoute,
                          );
                          router.push('/home/profile');
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 28, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${guest.mid} — ${guest.memberName}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: ui.Color.fromARGB(255, 0, 0, 0),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.flag_outlined,
                                      size: 18,
                                      color: ui.Color.fromARGB(255, 0, 0, 0)),
                                  const SizedBox(width: 6),
                                  Text(
                                    guest.country,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color:
                                            ui.Color.fromARGB(255, 0, 0, 0)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 18,
                                      color: ui.Color.fromARGB(255, 0, 0, 0)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Last visit on ${DateFormat('dd MMM yyyy').format(DateTime.tryParse(guest.lastVisitDate) ?? DateTime(2000))}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color:
                                            ui.Color.fromARGB(255, 0, 0, 0)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Rating badge / image (mirrors ProfileScreen logic) ──
                    Positioned(
                      top: 6,
                      right: 2,
                    //   child: _useBadgeForRating
                    //       ? Container(
                    //           padding: const EdgeInsets.symmetric(
                    //               horizontal: 10, vertical: 6),
                    //           decoration: BoxDecoration(
                    //             color: _getRatingColor(guest.gRating),
                    //             borderRadius: BorderRadius.circular(12),
                    //             boxShadow: [
                    //               BoxShadow(
                    //                 color: Colors.black.withOpacity(0.25),
                    //                 blurRadius: 6,
                    //                 offset: const Offset(0, 3),
                    //               ),
                    //             ],
                    //           ),
                    //           child: Text(
                    //             guest.gRating ?? 'N/A',
                    //             style: const TextStyle(
                    //               color: Colors.white,
                    //               fontSize: 12,
                    //               fontWeight: FontWeight.bold,
                    //             ),
                    //           ),
                    //         )
                    //       : (_ratingImages[guest.gRating] != null
                    //           ? SizedBox(
                    //               width: 80,
                    //               height: 26,
                    //               child: Image.asset(
                    //                 _ratingImages[guest.gRating]!,
                    //                 fit: BoxFit.contain,
                    //               ),
                    //             )
                    //           : const SizedBox.shrink()),
                    // ),
                     child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _getRatingColor(guest.gRating),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                guest.gRating ?? 'N/A',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                        
                    ),
                  ],
                );
              },
            ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Shared sheet scaffold
// ────────────────────────────────────────────────────────────────────────────
class _SheetScaffold extends StatelessWidget {
  final String title;
  final Color accentColor;
  final int count;
  final TextEditingController searchCtrl;
  final String searchHint;
  final Widget child;
  final bool showBackButton;

  const _SheetScaffold({
    required this.title,
    required this.accentColor,
    required this.count,
    required this.searchCtrl,
    required this.searchHint,
    required this.child,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                if (showBackButton)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: Colors.black87,
                    onPressed: () => Navigator.of(context).pop(),
                  )
                else
                  const SizedBox(width: 12),
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: Colors.black54,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: searchHint,
                prefixIcon: Icon(Icons.search, color: accentColor),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: accentColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: accentColor, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Widget _emptyWidget() => Center(
      child: Text('No data available',
          style: TextStyle(color: Colors.grey.shade500)),
    );

// ────────────────────────────────────────────────────────────────────────────
// Painter
// ────────────────────────────────────────────────────────────────────────────
class _HalfPiePainter extends CustomPainter {
  final List<MarketingGroup> groups;
  final int total;
  final double progress;
  final int? hoveredIndex;
  final Color Function(int index) colorForIndex;
  final double radius;

  _HalfPiePainter({
    required this.groups,
    required this.total,
    required this.progress,
    required this.hoveredIndex,
    required this.colorForIndex,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0) return;

    final center = Offset(size.width / 2, radius + _kHoverExpand / 2);
    final innerRadius = radius * _kInnerRadiusFactor;
    final strokeWidth = radius - innerRadius;

    double startAngle = pi;
    final totalSweep = pi * progress;

    for (int i = 0; i < groups.length; i++) {
      final fraction = groups[i].rc / total;
      final sweep = fraction * totalSweep;
      final color = colorForIndex(i);
      final isHovered = hoveredIndex == i;
      final isOtherHovered = hoveredIndex != null && !isHovered;

      final paint = Paint()
        ..color = isOtherHovered ? color.withOpacity(0.3) : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHovered ? strokeWidth + 6 : strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: innerRadius + strokeWidth / 2),
        startAngle,
        sweep,
        false,
        paint,
      );

      if (progress > 0.85 && fraction > 0.07) {
        final midAngle = startAngle + sweep / 2;
        final labelRadius = innerRadius + strokeWidth / 2;
        final labelPos = Offset(
          center.dx + labelRadius * cos(midAngle),
          center.dy + labelRadius * sin(midAngle),
        );

        final tp = TextPainter(
          text: TextSpan(
            text: '${(fraction * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: Colors.white.withOpacity(progress),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();

        tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
      }

      startAngle += sweep + (pi / 180 * 1.5);
    }
  }

  @override
  bool shouldRepaint(_HalfPiePainter old) =>
      old.progress != progress || old.hoveredIndex != hoveredIndex;
}

// ────────────────────────────────────────────────────────────────────────────
// Period tab bar
// ────────────────────────────────────────────────────────────────────────────
class _PeriodTabBar extends StatelessWidget {
  final int selectedIndex;
  final List<String> labels;
  final List<Color> colors;
  final ValueChanged<int> onTap;
  final double fontSize;

  const _PeriodTabBar({
    required this.selectedIndex,
    required this.labels,
    required this.colors,
    required this.onTap,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final isSelected = i == selectedIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: i < labels.length - 1 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? colors[i] : colors[i].withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : colors[i],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Placeholders
// ────────────────────────────────────────────────────────────────────────────
class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text('Loading breakdown…',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text('No data available',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      ),
    );
  }
}