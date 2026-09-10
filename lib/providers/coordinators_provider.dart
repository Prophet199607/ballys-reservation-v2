import 'package:ballys_reservation_app/data/repositories/coordinator_request_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/coordinator.dart';
import 'package:ballys_reservation_app/models/coordinator_request.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coordinatorRequestRepositoryProvider =
    Provider<CoordinatorRequestRepository>((ref) {
  return CoordinatorRequestRepository(ApiService(SecureStorage.instance));
});

/// The coordinator picker list from `Coordinators/Get` — active rows only,
/// sorted by name (the repository does both).
///
/// A [FutureProvider] so the list is fetched once and cached for the app
/// session: it changes rarely, and every screen that needs it gets the same
/// result. To force a refetch — a retry after a failed load — call
/// `ref.invalidate(coordinatorsProvider)`.
final coordinatorsProvider = FutureProvider<List<Coordinator>>((ref) async {
  return ref.read(coordinatorRequestRepositoryProvider).getCoordinators();
});

/// `Coordinatorid` from the login response, or null when this login is not a
/// coordinator. Kept as a provider so the screen can tell "not a coordinator"
/// apart from "no requests yet".
///
/// `autoDispose` because it is read from storage: logging out and back in as
/// someone else during the same app session must not be answered from a cache.
final loggedInCoordinatorIdProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final id = await StorageUtil.getCoordinatorId();
  debugPrint('Logged-in Coordinatorid: $id');
  return id;
});

/// The requests sent to the coordinator who is logged in, newest first.
///
/// The login response carries only `Coordinatorid`, while the endpoint wants
/// the name as well, so it is resolved off the cached [coordinatorsProvider]
/// list.
///
/// `autoDispose` so a request sent from this session shows up the next time
/// the list is opened; `ref.invalidate` forces a refetch while it is on screen.
final myCoordinatorRequestsProvider =
    FutureProvider.autoDispose<List<CoordinatorRequestRecord>>((ref) async {
  final coordinatorId = await ref.watch(loggedInCoordinatorIdProvider.future);
  if (coordinatorId == null) return const [];

  final coordinators = await ref.watch(coordinatorsProvider.future);
  final match = coordinators
      .where((c) =>
          c.coordinatorId.trim().toUpperCase() ==
          coordinatorId.trim().toUpperCase())
      .firstOrNull;

  debugPrint(
      'Fetching requests for $coordinatorId / ${match?.name ?? '(no name match)'}');

  return ref
      .read(coordinatorRequestRepositoryProvider)
      .getRequestsByCoordinator(
        coordinatorId: coordinatorId,
        // Unmatched id: send the name empty rather than guess at one.
        coordinatorName: match?.name ?? '',
      );
});
