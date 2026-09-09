import 'dart:convert';

import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/utils/device_id.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';

/// One guest the coordinator is being asked to book for. Only the two fields
/// the backend needs — the screen keeps rating and photo for its own list.
class CoordinatorRequestGuest {
  const CoordinatorRequestGuest({required this.bmNumber, required this.name});

  final String bmNumber;
  final String name;
}

/// What came back from a coordinator request save, in the two parts the screen
/// reacts to: whether to clear the form, and what to put in the snack.
class CoordinatorRequestResult {
  final bool success;
  final String? message;

  const CoordinatorRequestResult({required this.success, this.message});
}

/// The API side of the Ballys coordinator request screen.
///
/// An executive who cannot key a reservation in themselves hands it to a
/// coordinator: who should do it, which guests it is for, and what they are
/// being asked to book.
class CoordinatorRequestRepository {
  final ApiService apiService;

  CoordinatorRequestRepository(this.apiService);

  /// Follows the `Reservation_*` naming the other reservation endpoints use.
  /// Confirm the exact name with the backend before shipping — the payload
  /// shape below mirrors `Reservation_InsertGroupReservation`, so only this
  /// constant should need changing.
  static const String _endpoint = 'Reservation_InsertCoordinatorRequest';

  Future<CoordinatorRequestResult> saveCoordinatorRequest({
required String coordinatorId,
    required String coordinatorName,
    required String requestType,
    required List<CoordinatorRequestGuest> guests,
    String remarks = '',
    void Function(String label, Object? payload)? log,
  }) async {
    final body = await buildBody(
   coordinatorId: coordinatorId,
      coordinatorName: coordinatorName,
      requestType: requestType,
      guests: guests,
      remarks: remarks,
    );
    log?.call('Saving coordinator request', jsonEncode(body));

    final response = await apiService.post(_endpoint, body);
    log?.call('Coordinator request response', response);

    final success = response['Status'] as bool? ?? false;
    return CoordinatorRequestResult(
      success: success,
      message: response['Message'] as String? ??
          (success ? null : 'Failed to send the coordinator request'),
    );
  }

  /// Built separately from the post so the payload can be inspected in tests
  /// without a live API.
  Future<Map<String, Object?>> buildBody({
    required String coordinatorId,
    required String coordinatorName,
    required String requestType,
    required List<CoordinatorRequestGuest> guests,
    String remarks = '',
  }) async {
    return {
      'master_id': DateTime.now().millisecondsSinceEpoch.toString(),
      'coordinator_id': coordinatorId,
      'coordinator_name': coordinatorName,
      // 'AIR_TICKET' | 'HOTEL' | 'BOTH' — what the coordinator should book.
      'request_type': requestType,
      'remarks': remarks,
      'sales_code': await StorageUtil.getSalesCode(),
      'user_name': await StorageUtil.getUserName(),
      'device_id': await DeviceId.get(),
      'guests': guests
          .map((g) => {
                'bm_number': g.bmNumber,
                'guest_name': g.name,
              })
          .toList(),
    };
  }
}
