import 'package:ballys_reservation_app/models/marketing.dart';
import 'package:ballys_reservation_app/screens/marketing_detail_page.dart';
import 'package:ballys_reservation_app/screens/marketing_target_detail_page.dart';
import 'package:ballys_reservation_app/providers/app_mode_setting_provider.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import 'package:ballys_reservation_app/providers/marketing_provider.dart';

class MarketingPerformanceWidget extends ConsumerStatefulWidget {
  final bool isFullScreen;

  const MarketingPerformanceWidget({super.key, this.isFullScreen = false});

  @override
  ConsumerState<MarketingPerformanceWidget> createState() =>
      _MarketingPerformanceWidgetState();
}

class _MarketingPerformanceWidgetState
    extends ConsumerState<MarketingPerformanceWidget> {
  bool _tabsEnabled = false;
  AppMode? _previousAppMode;
  String? userName;
  bool _refreshEnabled = false;
  String? _userLevel;

  // Client-side search over the currently displayed rows (SM name for the
  // Performance/Result views, group name for the Target view). Filtering is
  // purely local — no extra API calls.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Captured in initState so dispose() never touches `ref` (illegal in
  // Riverpod once the element is disposed — it throws and corrupts the
  // element-tree teardown).
  MarketingNotifier? _marketingNotifier;

  // Max height for the content area when this widget is embedded
  // (not full screen). Beyond this, the content scrolls internally
  // instead of expanding the card indefinitely.
  static const double _embeddedMaxContentHeight = 320.0;

  @override
  void initState() {
    super.initState();
    _marketingNotifier = ref.read(marketingProvider.notifier);
    _loadUserName();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enableTabsAfterDelay();
    });
  }

  void _enableTabsAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _tabsEnabled = true;
      });
    }
  }

  Future<void> _loadUserName() async {
    final name = await StorageUtil.getUserName();
    final userLevel = await StorageUtil.getUserLevel();
    if (mounted) {
      setState(() {
        userName = name;
        _userLevel = userLevel;
      });
    }
  }

  /// Level 3 users may read this card but not drill into any row - every
  /// one of them shows Access Denied instead.
  void _showAccessDeniedDialog() {
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
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
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


  void _handleAppModeChange(AppMode currentAppMode) {
    if (_previousAppMode != null &&
        _previousAppMode != currentAppMode &&
        ref.read(marketingProvider).selectedTab != -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(marketingProvider.notifier).onAppModeChanged(currentAppMode);
        }
      });
    }
    _previousAppMode = currentAppMode;
  }

  List<dynamic> _calculatePercentages(List<dynamic> data) {
    if (data.isEmpty) return [];

    final maxAbsAmount = data.map((p) {
      if (p is MarketingPerformance) return p.winLost.abs();
      if (p is MarketingResult) return p.winLost.abs();
      return 0.0;
    }).reduce((a, b) => math.max(a, b));

    const double minVisibleWidth = 5.0;
    const double maxWidth = 100.0;

    return data.map((item) {
      double winLost = 0.0;
      bool isPositive = false;

      if (item is MarketingPerformance) {
        winLost = item.winLost;
        isPositive = item.isPositive;
      } else if (item is MarketingResult) {
        winLost = item.winLost;
        isPositive = item.isPositive;
      }

      double percentage = 0.0;
      if (maxAbsAmount > 0 && winLost != 0) {
        final absValue = winLost.abs();
        final linearRatio = absValue / maxAbsAmount;
        final logRatio = math.log(absValue + 1) / math.log(maxAbsAmount + 1);
        final blendedRatio = 0.85 * linearRatio + 0.15 * logRatio;
        percentage =
            minVisibleWidth + blendedRatio * (maxWidth - minVisibleWidth);
        percentage = math.min(math.max(percentage, minVisibleWidth), maxWidth);
      } else if (winLost != 0) {
        percentage = 50.0;
      }

      return _ItemWithPercentage(
        item: item,
        percentage: (percentage * 100).round() / 100,
        isPositive: isPositive,
      );
    }).toList();
  }

  // ── Wraps content so it scrolls within a bounded height when this
  // widget is embedded (not full screen). In full screen mode the
  // parent page already provides its own scroll view, so we return
  // the child unchanged there.
  Widget _wrapScrollable(Widget child,
      {double maxHeight = _embeddedMaxContentHeight}) {
    if (widget.isFullScreen) {
      return child;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final marketingState = ref.watch(marketingProvider);
    final appModeSettings = ref.watch(appmodeSettingsProvider);
    final currentAppMode = appModeSettings.appMode;
    final fontSettings = ref.watch(fontSettingsProvider);

    _handleAppModeChange(currentAppMode);

    // Determine current data
    final bool isTargetView =
        marketingState.viewType == MarketingViewType.target;
    final List<dynamic> allData =
        marketingState.viewType == MarketingViewType.performance
            ? marketingState.currentPerformanceData
            : marketingState.viewType == MarketingViewType.result
                ? marketingState.currentResultData
                : []; // target view — list built separately

    // Apply the search filter (SM name). Everything below — totals, bars,
    // sorting — works off the filtered list so the card stays consistent.
    final String query = _searchQuery.trim().toLowerCase();
    final List<dynamic> currentData = query.isEmpty
        ? allData
        : allData.where((item) {
            final String name = item is MarketingPerformance
                ? item.smName
                : item is MarketingResult
                    ? item.smName
                    : '';
            return name.toLowerCase().contains(query);
          }).toList();

    final bool tabsEnabled = _tabsEnabled && !marketingState.isLoading;
    final dataWithPercentages = _calculatePercentages(currentData);

    // Guest-count totals for the summary line under the title (new / old /
    // package guests), mirroring the "Last 3 Months Performance" card.
    // Both MarketingPerformance and MarketingResult expose newReg/oldReg/pkgG.
    int totalNewReg = 0;
    int totalOldReg = 0;
    int totalPkgG = 0;
    for (final item in currentData) {
      if (item is MarketingPerformance) {
        totalNewReg += item.newReg;
        totalOldReg += item.oldReg;
        totalPkgG += item.pkgG;
      } else if (item is MarketingResult) {
        totalNewReg += item.newReg;
        totalOldReg += item.oldReg;
        totalPkgG += item.pkgG;
      }
    }
    final int totalGuestCount = totalNewReg + totalOldReg;

    final positiveData = dataWithPercentages
        .where((item) => item.isPositive)
        .toList()
      ..sort((a, b) {
        final aVal = a.item is MarketingPerformance
            ? (a.item as MarketingPerformance).displayValue
            : (a.item as MarketingResult).displayValue;
        final bVal = b.item is MarketingPerformance
            ? (b.item as MarketingPerformance).displayValue
            : (b.item as MarketingResult).displayValue;
        return bVal.compareTo(aVal);
      });

    final negativeData = dataWithPercentages
        .where((item) => !item.isPositive)
        .toList()
      ..sort((a, b) {
        final aVal = a.item is MarketingPerformance
            ? (a.item as MarketingPerformance).displayValue
            : (a.item as MarketingResult).displayValue;
        final bVal = b.item is MarketingPerformance
            ? (b.item as MarketingPerformance).displayValue
            : (b.item as MarketingResult).displayValue;
        return aVal.compareTo(bVal);
      });

    final sortedData = [...positiveData, ...negativeData];

    // Target summary data (filtered by group name, sorted by achievement desc)
    final allTargetSummary = marketingState.currentTargetSummary;
    final targetSummary = [
      ...query.isEmpty
          ? allTargetSummary
          : allTargetSummary
              .where((t) => t.gName.toLowerCase().contains(query))
    ]..sort((a, b) => b.achievement.compareTo(a.achievement));

    // Show the search box whenever the current view actually has rows to
    // filter (or the user has typed something that filtered them all out).
    final bool hasRowsToSearch = isTargetView
        ? allTargetSummary.isNotEmpty
        : allData.isNotEmpty;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "MARKETING PERFORMANCE",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      // Guest-count summary (new / old / package) — shown for
                      // the Performance & Result views once data has loaded,
                      // same treatment as the "Last 3 Months Performance" card.
                      if (!isTargetView &&
                          !marketingState.isLoading &&
                          currentData.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            "$totalGuestCount guest${totalGuestCount == 1 ? '' : 's'} this period "
                            "($totalNewReg new, $totalOldReg old, $totalPkgG package)",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    widget.isFullScreen ? Icons.zoom_out : Icons.zoom_in,
                    color: Colors.blue,
                    size: 30,
                  ),
                  onPressed: () {
                    if (widget.isFullScreen) {
                      ref.read(marketingProvider.notifier).clearMarketing();
                      Navigator.pop(context);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: Text(
                                userName != null
                                    ? 'Welcome, $userName '
                                    : 'Loading...',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            body: const SafeArea(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.all(8),
                                child: MarketingPerformanceWidget(
                                    isFullScreen: true),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Time period tab buttons
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTabButton(
                        "Today", 0, marketingState.selectedTab == 0, tabsEnabled),
                    const SizedBox(width: 7),
                    _buildTabButton(
                        "Yesterday", 1, marketingState.selectedTab == 1, tabsEnabled),
                    const SizedBox(width: 7),
                    _buildTabButton(
                        "Monthly", 2, marketingState.selectedTab == 2, tabsEnabled),
                    const SizedBox(width: 7),
                    _buildTabButton(
                        "Last Month", 3, marketingState.selectedTab == 3, tabsEnabled),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // View type toggle (Performance / Result / Target)
            if (marketingState.selectedTab >= 0) ...[
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildViewTypeButton(
                        "Performance",
                        MarketingViewType.performance,
                        marketingState.viewType == MarketingViewType.performance,
                      ),
                      _buildViewTypeButton(
                        "Result",
                        MarketingViewType.result,
                        marketingState.viewType == MarketingViewType.result,
                      ),
                      // Target only for Monthly & Last Month tabs
                      if (marketingState.isTargetAvailable)
                        _buildViewTypeButton(
                          "Target",
                          MarketingViewType.target,
                          marketingState.viewType == MarketingViewType.target,
                          accentColor: Colors.deepPurple,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Search ──
            if (!marketingState.isLoading && hasRowsToSearch) ...[
              _buildSearchField(
                hintText:
                    isTargetView ? 'Search group name...' : 'Search SM name...',
              ),
              const SizedBox(height: 12),
            ],

            // ── Content ──
            if (marketingState.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text(
                        "Refreshing data...",
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else if (isTargetView) ...[
              // ── TARGET VIEW ──
              if (targetSummary.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      query.isNotEmpty && allTargetSummary.isNotEmpty
                          ? 'No groups match "$_searchQuery"'
                          : "No target data available",
                      style:
                          const TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                _wrapScrollable(
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Header intentionally omitted for Target view.
                        ...targetSummary.asMap().entries.map(
                              (entry) => _buildTargetItem(
                                entry.key + 1,
                                entry.value,
                                fontSettings,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
            ] else ...[
              // ── PERFORMANCE / RESULT VIEW ──
              if (currentData.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      query.isNotEmpty && allData.isNotEmpty
                          ? 'No SM matches "$_searchQuery"'
                          : "No data available",
                      style:
                          const TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                _wrapScrollable(
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: marketingState.viewType == MarketingViewType.result
                            ? Colors.grey[400]!
                            : Colors.transparent,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        if (marketingState.viewType == MarketingViewType.result)
                          _buildResultTableHeader(),
                        ...sortedData.map((itemWithPercentage) {
                          if (marketingState.viewType ==
                              MarketingViewType.performance) {
                            return _buildPerformanceItem(itemWithPercentage);
                          } else {
                            return _buildResultItem(itemWithPercentage);
                          }
                        }),
                      ],
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 16),

            // Legend + refresh
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!isTargetView)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text("WIN"),
                          const SizedBox(width: 20),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text("LOST"),
                          const SizedBox(width: 20),
                          Text("N",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700])),
                          const SizedBox(width: 4),
                          const Text("NEW"),
                          const SizedBox(width: 12),
                          Text("O",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700])),
                          const SizedBox(width: 4),
                          const Text("OLD"),
                          const SizedBox(width: 12),
                          Text("P",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple[400])),
                          const SizedBox(width: 4),
                          const Text("PACKAGE"),
                        ],
                      ),
                    ),
                  )
                else
                  // Target legend — achievement % colour bands
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildAchievementLegend("<30%", _achievementColor(0)),
                          const SizedBox(width: 12),
                          _buildAchievementLegend("30-60%", _achievementColor(30)),
                          const SizedBox(width: 12),
                          _buildAchievementLegend("60-90%", _achievementColor(60)),
                          const SizedBox(width: 12),
                          _buildAchievementLegend("90%+", _achievementColor(90)),
                        ],
                      ),
                    ),
                  ),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  color: (!_refreshEnabled || marketingState.isLoading)
                      ? Colors.grey
                      : Colors.blue,
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TextButton.icon(
                      onPressed:
                          !_refreshEnabled || marketingState.isLoading
                              ? null
                              : _refreshCurrentTab,
                      // icon: const Icon(Icons.refresh,
                      //     size: 14, color: Colors.white),
                      label: const Text(
                        "Refresh",
                        style:
                            TextStyle(fontSize: 14, color: Colors.white),
                      ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Search field ─────────────────────────────────────────────────────────
  // Filters the currently displayed rows locally as the user types.
  // Resets the filter — called when the tab or view type changes so the
  // user isn't left looking at an empty list filtered by a stale query.
  void _clearSearch() {
    if (_searchQuery.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  Widget _buildSearchField({required String hintText}) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[500]),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                  FocusScope.of(context).unfocus();
                },
              ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: const BorderSide(color: Colors.blue),
        ),
      ),
    );
  }

  // ── View type toggle button ──────────────────────────────────────────────
  // Widget _buildViewTypeButton(
  //   String text,
  //   MarketingViewType viewType,
  //   bool isSelected, {
  //   Color? accentColor,
  // }) {
  //   final color = accentColor ?? Colors.blue;
  //   return GestureDetector(
  //     onTap: () {
  //       final notifier = ref.read(marketingProvider.notifier);
  //       notifier.setViewType(viewType);

  //       // If switching to Target and we have no data yet, load it
  //       if (viewType == MarketingViewType.target) {
  //         final state = ref.read(marketingProvider);
  //         final hasData = state.selectedTab == 2
  //             ? state.monthlyTargetSummary.isNotEmpty
  //             : state.lastmonthTargetSummary.isNotEmpty;
  //         if (!hasData) {
  //           notifier.getTargetData(state.selectedTab);
  //         }
  //       }
  //     },
  //     child: Container(
  //       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  //       decoration: BoxDecoration(
  //         color: isSelected ? color : Colors.transparent,
  //         borderRadius: BorderRadius.circular(25),
  //       ),
  //       child: Text(
  //         text,
  //         style: TextStyle(
  //           color: isSelected ? Colors.white : Colors.black87,
  //           fontWeight: FontWeight.bold,
  //           fontSize: 14,
  //         ),
  //       ),
  //     ),
  //   );
  // }
Widget _buildViewTypeButton(
  String text,
  MarketingViewType viewType,
  bool isSelected, {
  Color? accentColor,
}) {
  final color = accentColor ?? Colors.blue;
  return GestureDetector(
    onTap: () {
      final notifier = ref.read(marketingProvider.notifier);
      final state = ref.read(marketingProvider);
      _clearSearch();
      notifier.setViewType(viewType);

      if (viewType == MarketingViewType.target) {
        // If switching to Target and we have no data yet, load it
        final hasData = state.selectedTab == 2
            ? state.monthlyTargetSummary.isNotEmpty
            : state.lastmonthTargetSummary.isNotEmpty;
        if (!hasData) {
          notifier.getTargetData(state.selectedTab);
        }
      } else {
        // Performance / Result tapped.
        // This is now the ONLY trigger for the performance/result API
        // call — switching between Today/Yesterday/Monthly/Last Month
        // (see _onTabSelected) no longer fetches anything by itself.
        switch (state.selectedTab) {
          case 0:
            // Today's numbers can change through the day, so always refresh.
            notifier.getTodayPerformance();
            break;
          case 1:
            if (state.yesterdayPerformance.isEmpty) {
              notifier.getYesterdayPerformance();
            }
            break;
          case 2:
            if (state.monthlyPerformance.isEmpty) {
              notifier.getMonthlyPerformance();
            }
            break;
          case 3:
            if (state.lastmonthPerformance.isEmpty) {
              notifier.getLastMonthPerformance();
            }
            break;
        }
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    ),
  );
}
  // ── Time period tab button ───────────────────────────────────────────────
  Widget _buildTabButton(
      String text, int index, bool isSelected, bool isEnabled) {
    Color borderColor;
    switch (index) {
      case 0: borderColor = Colors.orange; break;
      case 1: borderColor = Colors.green; break;
      case 2: borderColor = Colors.blue; break;
      case 3: borderColor = const Color.fromARGB(255, 203, 56, 196); break;
      default: borderColor = Colors.grey;
    }

    Color backgroundColor;
    Color textColor;
    if (!isEnabled) {
      backgroundColor = Colors.grey[200]!;
      textColor = Colors.grey[500]!;
    } else if (isSelected) {
      backgroundColor = borderColor;
      textColor = Colors.white;
    } else {
      backgroundColor = Colors.white;
      textColor = borderColor;
    }

    return GestureDetector(
      onTap: isEnabled ? () => _onTabSelected(index) : null,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Text(
            text,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // ── Performance bar item ─────────────────────────────────────────────────
  Widget _buildPerformanceItem(_ItemWithPercentage itemWithPercentage) {
    final performance = itemWithPercentage.item as MarketingPerformance;
    final percentage = itemWithPercentage.percentage;
    final double barWidthFactor = (percentage / 100.0).clamp(0.0, 1.0);

    return Consumer(
      builder: (context, ref, child) {
        final fontSettings = ref.watch(fontSettingsProvider);
        return GestureDetector(
          onTap: () => _navigateToMarketingDetail(
              performance.sm, performance.smName, performance.winLost),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Full-width name line (uses the whole row width).
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        performance.smName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fontSettings.fontSize,
                          fontWeight: fontSettings.fontWeight,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 12, color: Colors.grey[600]),
                  ],
                ),
                const SizedBox(height: 4),
                // Badges + bar on the line below.
                Row(
                  children: [
                    // New / old / package guest badges for this SM
                    // (N_Reg / O_Reg / PKG_G) — fixed width so every bar
                    // starts at the same point and is the same size.
                    SizedBox(
                      width: 150,
                      child: _buildGuestBadges(
                        newReg: performance.newReg,
                        oldReg: performance.oldReg,
                        pkgG: performance.pkgG,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: barWidthFactor,
                            child: Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: performance.isPositive
                                    ? Colors.green
                                    : Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Result row item ──────────────────────────────────────────────────────
  Widget _buildResultItem(_ItemWithPercentage itemWithPercentage) {
    final result = itemWithPercentage.item as MarketingResult;

    return Consumer(
      builder: (context, ref, child) {
        final fontSettings = ref.watch(fontSettingsProvider);
        return GestureDetector(
          onTap: () => _navigateToMarketingDetailFromResult(
            result.sm,
            result.smName,
            result.winLost,
            result.mDrop,
            result.cashOut,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!, width: 1)),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                result.smName,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: fontSettings.fontSize,
                                  fontWeight: fontSettings.fontWeight,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            // New / old / package guest badges for this SM
                            // (N_Reg / O_Reg / PKG_G).
                            _buildGuestBadges(
                              newReg: result.newReg,
                              oldReg: result.oldReg,
                              pkgG: result.pkgG,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios,
                          size: 14, color: Colors.grey[400]),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(flex: 1, child: SizedBox.shrink()),
                      Expanded(
                        flex: 4,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _formatCurrency(result.mDrop),
                                style: TextStyle(
                                  fontSize: fontSettings.fontSize - 1,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _formatCurrency(result.cashOut),
                                style: TextStyle(
                                  fontSize: fontSettings.fontSize - 1,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _formatCurrency(result.winLost*1000),
                                style: TextStyle(
                                  fontSize: fontSettings.fontSize - 1,
                                  fontWeight: FontWeight.bold,
                                  color: result.isPositive
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Result table header ──────────────────────────────────────────────────
  Widget _buildResultTableHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border(bottom: BorderSide(color: Colors.grey[400]!, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          const Expanded(
            flex: 2,
            child: Text(
              'SM Name',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Drop',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                      textAlign: TextAlign.center),
                ),
                Expanded(
                  child: Text('Cash Out',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                      textAlign: TextAlign.center),
                ),
                Expanded(
                  child: Text('Win/Lost',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                      textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Target summary row item ──────────────────────────────────────────────
  // Row 1: row number + group name (with arrow)
  // Row 2: "Drop"        -> actual drop value (thousand-separated)
  // Row 3: "Target"      -> monthly target value (thousand-separated)
  // Row 4: "Achievement" -> achievement percentage
  Widget _buildTargetItem(
      int rowNumber, MarketingTarget target, fontSettings) {
    return GestureDetector(
      onTap: () {
        if (_userLevel == '3') {
          _showAccessDeniedDialog();
          return;
        }
        final detailRows = ref
            .read(marketingProvider.notifier)
            .getTargetDetailForGroup(target.gcode);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MarketingTargetDetailPage(
              gcode: target.gcode,
              gName: target.gName,
              actualDrop: target.actualDrop,
              mTarget: target.mTarget,
              achievement: target.achievement,
              detailRows: detailRows,
              tabTitle: ref.read(marketingProvider).currentTabTitle,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
              bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: number + group name + arrow
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$rowNumber. ${target.gName}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: fontSettings.fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 12, color: Colors.grey[400]),
              ],
            ),
            const SizedBox(height: 6),
            // Row 2: Drop
            _buildTargetDetailRow(
              'Actual Drop',
              _formatWithThousands(target.actualDrop),
              fontSettings,
            ),
            // Row 3: Target
            _buildTargetDetailRow(
              'Target',
              _formatWithThousands(target.mTarget),
              fontSettings,
            ),
            // Row 4: Achievement
            _buildTargetDetailRow(
              'Achievement',
              '${target.achievement.toStringAsFixed(2)}%',
              fontSettings,
              valueColor: _achievementColor(target.achievement),
              labelColor: _achievementColor(target.achievement),
            ),
          ],
        ),
      ),
    );
  }

  // ── Achievement % legend chip ────────────────────────────────────────────
  Widget _buildAchievementLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  // ── Achievement % colour bands ───────────────────────────────────────────
  // < 30 red · 30–60 yellow · 60–90 blue · >= 90 green
  static Color _achievementColor(double achievement) {
    if (achievement < 30) return Colors.red;
    if (achievement < 60) return const Color(0xFFF9A825); // amber 800
    if (achievement < 90) return Colors.blue;
    return Colors.green;
  }

  // ── Helper row: label on the left, value on the right ───────────────────
  Widget _buildTargetDetailRow(
    String label,
    String value,
    fontSettings, {
    Color? valueColor,
    Color? labelColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSettings.fontSize,
              fontWeight:
                  labelColor != null ? FontWeight.w900 : FontWeight.normal,
              color: labelColor ?? const Color.fromARGB(255, 0, 0, 0),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSettings.fontSize,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            fontFeatures: const [FontFeature.tabularFigures()],
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ── Guest-count badges (new / old / package) ─────────────────────────────
  // Row of N / O / P pills shown under the SM name, mirroring the
  // "Last 3 Months Performance" card. Values come from N_Reg / O_Reg / PKG_G.
  Widget _buildGuestBadges({
    required int newReg,
    required int oldReg,
    required int pkgG,
  }) {
    return Row(
      children: [
        _buildRegBadge(
          count: newReg,
          label: 'N',
          background: Colors.green[50]!,
          foreground: Colors.green[700]!,
        ),
        const SizedBox(width: 4),
        _buildRegBadge(
          count: oldReg,
          label: 'O',
          background: Colors.blue[50]!,
          foreground: Colors.blue[700]!,
        ),
        const SizedBox(width: 4),
        _buildRegBadge(
          count: pkgG,
          label: 'P',
          background: Colors.deepPurple[50]!,
          foreground: Colors.deepPurple[400]!,
        ),
      ],
    );
  }

  // Small pill showing a guest count with a single-letter label
  // (N = new, O = old, P = package).
  Widget _buildRegBadge({
    required int count,
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String _formatCurrency(double amount) {
    if (amount == 0) return 'N/A';
    final absAmount = amount.abs();
    if (absAmount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    } else if (absAmount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(2)}K';
    }
    return amount.toStringAsFixed(2);
  }

  String _formatLargeNumber(double amount) {
    if (amount == 0) return 'N/A';
    final absAmount = amount.abs();
    if (absAmount >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(2)}B';
    } else if (absAmount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    } else if (absAmount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(2)}K';
    }
    return amount.toStringAsFixed(0);
  }

  // Formats a number with thousand separators, e.g. 1234567.5 -> "1,234,567.50"
  // String _formatWithThousands(double amount) {
  //   if (amount == 0) return 'N/A';
  //   final isNegative = amount < 0;
  //   final absAmount = amount.abs();
  //   final parts = absAmount.toStringAsFixed(2).split('.');
  //   final intPart = parts[0];
  //   final decPart = parts[1];

  //   final buffer = StringBuffer();
  //   for (int i = 0; i < intPart.length; i++) {
  //     final posFromEnd = intPart.length - i;
  //     buffer.write(intPart[i]);
  //     if (posFromEnd > 1 && posFromEnd % 3 == 1) {
  //       buffer.write(',');
  //     }
  //   }
  //   return '${isNegative ? '-' : ''}$buffer.$decPart';
  // }
String _formatWithThousands(double amount) {
  if (amount == 0) return 'N/A';
  final isNegative = amount < 0;
  final intPart = amount.abs().round().toString(); // use .truncate() instead of .round() if you want to chop decimals rather than round

  final buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    final posFromEnd = intPart.length - i;
    buffer.write(intPart[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return '${isNegative ? '-' : ''}$buffer';
}
  // ── Navigation ───────────────────────────────────────────────────────────
  void _navigateToMarketingDetail(
      String smCode, String smName, double winLost) {
    if (_userLevel == '3') {
      _showAccessDeniedDialog();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarketingDetailPage(
          smCode: smCode,
          smName: smName,
          winSpecificMember: winLost,
          currentTabIndex: ref.read(marketingProvider).selectedTab,
          viewType: MarketingViewType.performance,
        ),
      ),
    );
  }

  void _navigateToMarketingDetailFromResult(String smCode, String smName,
      double winLost, double mDrop, double cashOut) {
    if (_userLevel == '3') {
      _showAccessDeniedDialog();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarketingDetailPage(
          smCode: smCode,
          smName: smName,
          winSpecificMember: winLost,
          currentTabIndex: ref.read(marketingProvider).selectedTab,
          viewType: MarketingViewType.result,
          mDrop: mDrop,
          cashOut: cashOut,
        ),
      ),
    );
  }

  // ── Tab selection ─────────────────────────────────────────────────────────
  // void _onTabSelected(int index) {
  //   final notifier = ref.read(marketingProvider.notifier);
  //   final state = ref.read(marketingProvider);
  //   notifier.setSelectedTab(index);

  //   // Always reset to Performance when switching tabs
  //   notifier.setViewType(MarketingViewType.performance);

  //   if (!_refreshEnabled) {
  //     setState(() {
  //       _refreshEnabled = true;
  //     });
  //   }

  //   switch (index) {
  //     case 0:
  //       notifier.getTodayPerformance();
  //       break;
  //     case 1:
  //       if (state.yesterdayPerformance.isEmpty) {
  //         notifier.getYesterdayPerformance();
  //       }
  //       break;
  //     case 2:
  //       if (state.monthlyPerformance.isEmpty) {
  //         notifier.getMonthlyPerformance();
  //       }
  //       break;
  //     case 3:
  //       if (state.lastmonthPerformance.isEmpty) {
  //         notifier.getLastMonthPerformance();
  //       }
  //       break;
  //   }
  // }
void _onTabSelected(int index) {
  if (_userLevel == '3') {
    _showAccessDeniedDialog();
    return;
  }
  final notifier = ref.read(marketingProvider.notifier);
  _clearSearch();
  notifier.setSelectedTab(index);

  // Always reset to Performance when switching tabs.
  // NOTE: switching tabs no longer triggers an API call by itself —
  // the API is now only called when the user taps the Performance or
  // Result view-type button (see _buildViewTypeButton).
  notifier.setViewType(MarketingViewType.performance);

  if (!_refreshEnabled) {
    setState(() {
      _refreshEnabled = true;
    });
  }
}
  void _refreshCurrentTab() {
    final marketingState = ref.read(marketingProvider);
    final notifier = ref.read(marketingProvider.notifier);

    // If currently on target view, refresh target data too
    if (marketingState.viewType == MarketingViewType.target &&
        marketingState.isTargetAvailable) {
      notifier.getTargetData(marketingState.selectedTab);
      return;
    }

    switch (marketingState.selectedTab) {
      case 0:
        notifier.getTodayPerformance();
        break;
      case 1:
        notifier.getYesterdayPerformance();
        break;
      case 2:
        notifier.getMonthlyPerformance();
        break;
      case 3:
        notifier.getLastMonthPerformance();
        break;
      default:
        notifier.getTodayPerformance();
        break;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Defer the state reset: mutating a StateNotifier synchronously inside
    // dispose() runs during finalizeTree/lockState and notifying listeners
    // there is illegal. Use the captured notifier (NOT `ref`) on a microtask.
    final notifier = _marketingNotifier;
    if (notifier != null) {
      Future.microtask(notifier.clearMarketing);
    }
    super.dispose();
  }
}

class _ItemWithPercentage {
  final dynamic item;
  final double percentage;
  final bool isPositive;

  _ItemWithPercentage({
    required this.item,
    required this.percentage,
    required this.isPositive,
  });
}