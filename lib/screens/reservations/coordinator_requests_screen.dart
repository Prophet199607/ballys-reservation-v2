import 'package:ballys_reservation_app/core/constants.dart';
import 'package:ballys_reservation_app/models/coordinator_request.dart';
import 'package:ballys_reservation_app/providers/coordinators_provider.dart';
import 'package:ballys_reservation_app/providers/font_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Sent Coordinator Requests (Ballys only).
///
/// The read side of [CoordinatorRequestBallysScreen]: every request the
/// logged-in user has handed to a coordinator. The list is scoped to them by
/// the `sales_code` / `user_name` the repository reads from storage, so there
/// is nothing to pick here.
class CoordinatorRequestsScreen extends ConsumerStatefulWidget {
  const CoordinatorRequestsScreen({super.key});

  @override
  ConsumerState<CoordinatorRequestsScreen> createState() =>
      _CoordinatorRequestsScreenState();
}

class _CoordinatorRequestsScreenState
    extends ConsumerState<CoordinatorRequestsScreen> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  Widget build(BuildContext context) {
    final fontSettings = ref.watch(fontSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('My Coordinator Requests'),
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
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myCoordinatorRequestsProvider),
          ),
        ],
      ),
      body: SafeArea(child: _requestList(fontSettings)),
    );
  }

  Widget _requestList(FontSettings fontSettings) {
    // No Coordinatorid on the login means there is nothing to fetch — say so,
    // rather than show the same empty list a coordinator with no requests sees.
    final coordinatorId = ref.watch(loggedInCoordinatorIdProvider).valueOrNull;
    if (ref.watch(loggedInCoordinatorIdProvider).hasValue &&
        coordinatorId == null) {
      return _placeholder(
        fontSettings,
        Icons.person_off_outlined,
        'This login is not linked to a coordinator.\n'
        'Log out and log in again if you were set up as one recently.',
      );
    }

    final requestsAsync = ref.watch(myCoordinatorRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _placeholder(
        fontSettings,
        Icons.error_outline,
        'Could not load your requests',
        action: TextButton.icon(
          onPressed: () => ref.invalidate(myCoordinatorRequestsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return _placeholder(
            fontSettings,
            Icons.inbox_outlined,
            'You have not sent any coordinator requests yet',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myCoordinatorRequestsProvider);
            await ref.read(myCoordinatorRequestsProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: requests.length,
            itemBuilder: (context, index) =>
                _requestCard(fontSettings, requests[index]),
          ),
        );
      },
    );
  }

  Widget _requestCard(FontSettings fontSettings, CoordinatorRequestRecord r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _requestTypeChip(fontSettings, r.requestType),
              ],
            ),
            const SizedBox(height: 8),
            // Who raised it. The list is already scoped to the logged-in
            // coordinator, so the requester is what this card has to name.
            Row(
              children: [
                Icon(Icons.account_circle_outlined,
                    size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: fontSettings.fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                      children: [
                        TextSpan(
                          text: r.userName.isEmpty ? 'Unknown user' : r.userName,
                        ),
                        // if (r.salesCode.isNotEmpty)
                        //   TextSpan(
                        //     text: '  (${r.salesCode})',
                        //     style: TextStyle(
                        //       fontWeight: FontWeight.normal,
                        //       fontSize: fontSettings.fontSize ,
                        //       color: Colors.grey.shade600,
                        //     ),
                        //   ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            for (final guest in r.guests)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person, size: 16, color: Constants.kPrimaryColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            guest.guestName,
                            style: TextStyle(
                              fontSize: fontSettings.fontSize - 3,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            guest.bmNumber,
                            style: TextStyle(
                              fontSize: fontSettings.fontSize - 5,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (r.remarks.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.remarks,
                  style: TextStyle(fontSize: fontSettings.fontSize),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                // When it was raised, under the guests rather than up top.
                Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  r.createdDate == null
                      ? '—'
                      : _dateFormat.format(r.createdDate!),
                  style: TextStyle(
                    fontSize: fontSettings.fontSize,
                    color: Colors.grey.shade600,
                  ),
                ),
               // const Spacer(),
              //  Icon(Icons.tag, size: 14, color: Colors.grey.shade600),
               // const SizedBox(width: 4),
                // Flexible(
                //   child: Text(
                //     // The reference the save returned.
                //     r.masterId,
                //     maxLines: 1,
                //     overflow: TextOverflow.ellipsis,
                //     style: TextStyle(
                //       fontSize: fontSettings.fontSize - 6,
                //       color: Colors.grey.shade600,
                //     ),
                //   ),
                // ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 'AIR_TICKET' | 'HOTEL' | 'BOTH' — anything else is shown as it came.
  Widget _requestTypeChip(FontSettings fontSettings, String requestType) {
    final (label, icon) = switch (requestType) {
      'AIR_TICKET' => ('Air Ticket', Icons.flight),
      'HOTEL' => ('Hotel', Icons.hotel),
      'BOTH' => ('Both', Icons.all_inclusive),
      _ => (requestType, Icons.help_outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Constants.kPrimaryColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Constants.kPrimaryColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSettings.fontSize - 6,
              fontWeight: FontWeight.bold,
              color: Constants.kPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(
    FontSettings fontSettings,
    IconData icon,
    String message, {
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSettings.fontSize - 3,
                color: Colors.grey.shade600,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      ),
    );
  }
}
