import 'package:ballys_reservation_app/data/repositories/coordinator_request_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/coordinator.dart';
import 'package:ballys_reservation_app/utils/secure_storage.dart';
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
