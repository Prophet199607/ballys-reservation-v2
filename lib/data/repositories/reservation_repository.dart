import 'dart:convert';

import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/reervationBallys.dart';
import 'package:ballys_reservation_app/models/reservation.dart';
import 'package:ballys_reservation_app/models/reservation/new_reservation_ballys.dart';
import 'package:ballys_reservation_app/utils/amount_util.dart';
import 'package:ballys_reservation_app/models/reservation/new_reservation.dart';
import 'package:ballys_reservation_app/utils/device_id.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:intl/intl.dart';

class ReservationRepository {
  final ApiService apiService;

  ReservationRepository(this.apiService);

  /// Pretty-prints a request body to the terminal with the bulky base64
  /// passport data redacted, so the full structure stays readable instead of
  /// being truncated by the giant image blobs. Prints in chunks to avoid the
  /// platform logger cutting off long output.
  void debugPrintRequestBody(Map<String, dynamic> body) {
    final redacted = Map<String, dynamic>.from(body);
    final images = body['passport_images'];
    if (images is List) {
      redacted['passport_images'] = images.map((img) {
        if (img is Map) {
          final copy = Map<String, dynamic>.from(img);
          final data = copy['Base64Data'];
          if (data is String) {
            copy['Base64Data'] = '<base64: ${data.length} chars>';
          }
          return copy;
        }
        return img;
      }).toList();
    }

    final pretty = const JsonEncoder.withIndent('  ').convert(redacted);
    const chunkSize = 800;
    for (int i = 0; i < pretty.length; i += chunkSize) {
      final end = (i + chunkSize < pretty.length) ? i + chunkSize : pretty.length;
      print(pretty.substring(i, end));
    }
  }

  DateTime parseCustomDate(String dateString) {
    try {
      DateFormat format = DateFormat('yyyy/MM/dd');
      return format.parse(dateString);
    } catch (e) {

      return DateTime.now();
    }
  }

  Future<Map<String, List<Reservation>>> getReservations() async {
    final response = await apiService.get('Reservation_GetAllReservations');
    print('Response from getReservations API: $response');

    final Map<String, List<Reservation>> classifiedReservations = {
      'Pending': [],
      'Approved': [],
      'Rejected': [],
      'Checked': [],
    };

    final status = response['Status'] as bool? ?? false;
    final data = response['Data'];

    if (status && data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final reservation = Reservation.fromReservationData(item);
          // Bucket on the `reservation_status` the API returns; anything
          // unrecognised (or blank) shows up under Pending.
          final bucket =
              classifiedReservations.containsKey(reservation.requestStatus)
                  ? reservation.requestStatus
                  : 'Pending';
          classifiedReservations[bucket]!.add(reservation);
        }
      }
      return classifiedReservations;
    } else {
      throw Exception('Unexpected response structure');
    }
  }
 Future<Map<String, List<ReservationBallys>>> getBallysReservations() async {
    final response = await apiService.get('Reservation_GetAllReservations');
   // print('Response from getBallysReservations API: $response');

    final Map<String, List<ReservationBallys>> classifiedReservations = {
      'Pending': [],
      'Approved': [],
      'Rejected': [],
      'Checked': [],
    };

    final status = response['Status'] as bool? ?? false;
    final data = response['Data'];

    if (status && data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final reservation = ReservationBallys.fromReservationData(item);
          // Bucket on the `reservation_status` the API returns; anything
          // unrecognised (or blank) shows up under Pending.
          final bucket =
              classifiedReservations.containsKey(reservation.requestStatus)
                  ? reservation.requestStatus
                  : 'Pending';
          classifiedReservations[bucket]!.add(reservation);
        }
      }
      return classifiedReservations;
    } else {
      throw Exception('Unexpected response structure');
    }
  }
  /// Fetches the predefined package amounts (e.g. `"IND 10,000"`,
  /// `"USD 25,000"`). Returns an empty list when the request fails or the
  /// payload is unexpected, so the caller can fall back to free-text entry.
  ///
  /// The endpoint differs per brand: Bellagio (bty.world) exposes it as
  /// `MyAnalytics_GetPackageAmounts`, while Ballys uses the reversed
  /// `GetPackageAmounts_MyAnalytics`.
  Future<List<String>> getPackageAmounts() async {
    try {
      final baseUrl = await StorageUtil.getCurrentApiUrl() ?? '';
      final endpoint = baseUrl.contains('bty.world')
          ? 'MyAnalytics_GetPackageAmounts'
          : 'GetPackageAmounts_MyAnalytics';
      final response = await apiService.get(endpoint);
      final status = response['Status'] as bool? ?? false;
      final data = response['Data'];
      if (status && data is List) {
        return data.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Builds the `Reservation_InsertReservation` payload shared by insert and
  /// update. [masterId] is a fresh timestamp when inserting, or the existing
  /// reservation id when updating — the backend replaces the record with that
  /// id, so both paths send the exact same structure.
  Future<Map<String, dynamic>> _buildReservationBody(
    NewReservation newReservation, {
    required String masterId,
  }) async {
    final salesCode = await StorageUtil.getSalesCode();
    final userName = await StorageUtil.getUName();
    final deviceId = await DeviceId.get();

    return {
      'master_id': masterId,
      'bm_number': newReservation.bmNumber,
      'guest_name': newReservation.guestName,
      'arrival_date': newReservation.arrivalDate?.toIso8601String(),
      'departure_date': newReservation.departureDate?.toIso8601String(),
      'no_of_nights': newReservation.noOfNights,
      'has_air_ticket_reservation':
          newReservation.hasAirTicketReservation == '1',
      'remarks': newReservation.remarks,
      'manual_reserv_no': newReservation.reservationnewnumber ?? '',
      'package_amount': packageAmountToInt(newReservation.packageAmount),
      'currency_type': packageAmountCurrency(newReservation.packageAmount),
      'sales_code': salesCode,
      'user_name': userName,
      'device_id': deviceId,
      'selected_marketing_person':
          newReservation.selectedMarketingPerson ?? '',
      'reservation_status': 'Pending',
      'guests': newReservation.guests,
      'room_details': newReservation.roomDetails,
      'air_ticket_details': newReservation.airTicketDetails,
      'passport_images': newReservation.passportImages,
    };
  }
Future<Map<String, dynamic>> _buildReservationBodyBallys(
    NewReservationBallys newReservation, {
    required String masterId,
  }) async {
    final salesCode = await StorageUtil.getSalesCode();
    final userName = await StorageUtil.getUserName();
    final deviceId = await DeviceId.get();

    return {
      'master_id': masterId,
      'bm_number': newReservation.bmNumber,
      'guest_name': newReservation.guestName,
      'arrival_date': newReservation.arrivalDate?.toIso8601String(),
      'departure_date': newReservation.departureDate?.toIso8601String(),
      'has_air_ticket_reservation':
          newReservation.hasAirTicketReservation == '1',
      'remarks': newReservation.remarks,
      // Package amount is per guest and travels inside `guests` — every member
      // is billed their own package, so there is no reservation-level amount.
      // Payment By and the Hamoos contact person, on the other hand, are picked
      // once for the whole reservation rather than per room / per ticket.
      'payment_by': newReservation.paymentBy ?? '',
      'contact_person': newReservation.contactPerson ?? '',
      // Normally the logged-in user's own sales code. A reservation keyed in
      // off a coordinator request overrides it with the coordinator's id, and
      // credits the marketing person who raised the request below.
      'sales_code': (newReservation.salesCodeOverride?.trim().isNotEmpty ?? false)
          ? newReservation.salesCodeOverride!.trim()
          : salesCode,
      'user_name': userName,
      'device_id': deviceId,
      'selected_marketing_person':
          newReservation.selectedMarketingPerson ?? '',
      'selected_marketing_person_code':
          newReservation.selectedMarketingPersonCode ?? '',
      // Approver picked from `GetAuthorizationLevels` — who the reservation is
      // being sent to for approval. Always present; an untouched dropdown
      // sends it as an empty object.
      'approve_person': newReservation.approvePersonJson(),
      'reservation_status': 'Pending',
      'guests': newReservation.guests,
      'room_details': newReservation.roomDetails,
      'air_ticket_details': newReservation.airTicketDetails,
      'passport_images': newReservation.passportImages,
    };
  }
  Future<Reservation?> saveReservation(NewReservation newReservation) async {
    final requestBody = await _buildReservationBody(
      newReservation,
      masterId: DateTime.now().millisecondsSinceEpoch.toString(),
    );

    debugPrintRequestBody(requestBody);

    final response =
        await apiService.post('Reservation_InsertReservation', requestBody);
    final status = response['Status'] as bool? ?? false;
    print('Reservation save status: $status');
    if (status) {
      return Reservation.fromJson({
        'Reserv_No': response['ReservationId']?.toString() ?? '',
      });
    } else {
      throw Exception(response['Message'] ?? 'Failed to save reservation');
    }
  }

  Future<ReservationBallys?> saveReservationBallys(NewReservationBallys newReservations) async {
    final requestBody = await _buildReservationBodyBallys(
      newReservations,
      masterId: DateTime.now().millisecondsSinceEpoch.toString(),
    );

    debugPrintRequestBody(requestBody);

    final response =
        await apiService.post('Reservation_InsertReservation', requestBody);
    final status = response['Status'] as bool? ?? false;
    print('Reservation save status: $status');
    if (status) {
      return ReservationBallys.fromJson({
        'Reserv_No': response['ReservationId']?.toString() ?? '',
      });
    } else {
      throw Exception(response['Message'] ?? 'Failed to save reservation');
    }
  }

  /// Re-posts an existing reservation to `Reservation_InsertReservation` with a
  /// new `reservation_status` ("Checked" / "Approved" / "Rejected").
  ///
  /// Every other field is sent exactly as the reservation already holds it, and
  /// `master_id` carries the existing id so the backend updates that record
  /// rather than creating a new one.
  Future<bool> updateReservationStatus({
    required Reservation reservation,
    required String status,
    required String remarks,
  }) async {
    final salesCode = await StorageUtil.getSalesCode();
    final userName = await StorageUtil.getUName();
    final deviceId = await DeviceId.get();

    final guests = reservation.guests;

    // Older payloads carry no per-guest breakdown; fall back to the
    // reservation-level rooms / flights tagged with the primary BM number.
    final roomDetails = guests.isNotEmpty
        ? [for (final g in guests) ...g.toRoomDetailsJson()]
        : reservation.hotelDescip
            .map((h) => {...h.toJson(), 'BMNumber': reservation.mid})
            .toList();

    final airTicketDetails = guests.isNotEmpty
        ? [for (final g in guests) ...g.toAirTicketDetailsJson()]
        : reservation.airticketDescrip
            .map((f) => {...f.toJson(), 'BMNumber': reservation.mid})
            .toList();

    final currency = (reservation.currencyType?.trim().isNotEmpty ?? false)
        ? reservation.currencyType!.trim()
        : packageAmountCurrency(reservation.packageAmount);

    final requestBody = {
      'master_id': reservation.reservNo,
      'bm_number': reservation.mid,
      'guest_name': reservation.mName,
      'arrival_date': reservation.arrDate.toIso8601String(),
      'departure_date': reservation.depDate.toIso8601String(),
      'no_of_nights': reservation.noOfNights,
      'has_air_ticket_reservation':
          reservation.airticketReservationStatus == '1',
      'remarks': remarks,
      'manual_reserv_no': reservation.reservationnewnumber ?? '',
      'package_amount': packageAmountToInt(reservation.packageAmount),
      'currency_type': currency,
      'sales_code': salesCode,
      'user_name': userName,
      'device_id': deviceId,
      'selected_marketing_person': '',
      'reservation_status': status,
      'guests': guests.isNotEmpty
          ? guests.map((g) => g.toJson()).toList()
          : [
              {
                'BMNumber': reservation.mid,
                'GuestName': reservation.mName,
                'ArrivalDate': reservation.arrDate.toIso8601String(),
                'DepartureDate': reservation.depDate.toIso8601String(),
                'HasAirTicketReservation':
                    reservation.airticketReservationStatus == '1',
                'Remarks': reservation.remarks,
              }
            ],
      'room_details': roomDetails,
      'air_ticket_details': airTicketDetails,
      'passport_images': reservation.passportImages
          .map((p) => {
                'GuestBMNumber': p.guestBmNumber,
                'FileName': p.fileName,
                'IsPdf': p.isPdf,
                'Base64Data': p.base64Data,
              })
          .toList(),
    };

    debugPrintRequestBody(requestBody);

    final response =
        await apiService.post('Reservation_InsertReservation', requestBody);
    print('Reservation status update ($status) response: $response');

    return response['Status'] as bool? ?? false;
  }

  /// Ballys counterpart of [updateReservationStatus]: re-posts an existing
  /// Ballys reservation to `Reservation_InsertReservation` with a new
  /// `reservation_status` ("Checked" / "Approved" / "Rejected" / "Pending").
  ///
  /// The body is field-for-field the one [_buildReservationBodyBallys] sends
  /// for a new Ballys reservation — same keys, same order, same per-guest
  /// shapes — with only `reservation_status` (and the action `remarks`)
  /// differing. `master_id` carries the existing id so the backend overwrites
  /// that record instead of creating a new one.
  Future<bool> updateBallysReservationStatus({
    required ReservationBallys reservation,
    required String status,
    required String remarks,
  }) async {
  
    final userName = await StorageUtil.getUserName();
    final deviceId = await DeviceId.get();

    // The new-reservation payload mirrors the FIRST guest at the top level, so
    // do the same here; reservation-level fields only stand in for legacy rows
 

    final requestBody = {
      'master_id': reservation.reservNo,
      'reservation_status': status,
      'user_name': userName,
          'remark': remarks,
      'device_id': deviceId,
  

    };

    print(requestBody);

    final response =
        await apiService.post('Reservation_UpdateReservationStatus', requestBody);
    print('Ballys reservation status update ($status) response: $response');

    return response['Status'] as bool? ?? false;
  }

  /// Saves an edited reservation through the same endpoint as a new one. The
  /// existing reservation id travels as `master_id`, so the backend overwrites
  /// that record (guests, rooms, air tickets and passports included) instead of
  /// creating a second one.
  Future<Reservation?> updateReservation(NewReservation newReservation) async {
    final masterId = newReservation.reservationNo ?? '';
    if (masterId.isEmpty) {
      throw Exception('Cannot update a reservation without a reservation no');
    }

    final requestBody =
        await _buildReservationBody(newReservation, masterId: masterId);

    debugPrintRequestBody(requestBody);

    final response =
        await apiService.post('Reservation_InsertReservation', requestBody);
    final status = response['Status'] as bool? ?? false;
    print('Reservation update status: $status');
    if (status) {
      return Reservation.fromJson({
        'Reserv_No': (response['ReservationId'] ?? masterId).toString(),
      });
    } else {
      throw Exception(response['Message'] ?? 'Failed to update reservation');
    }
  }
  Future<ReservationBallys?> updateReservationBallys(NewReservationBallys newReservation) async {
    final masterId = newReservation.reservationNo ?? '';
    if (masterId.isEmpty) {
      throw Exception('Cannot update a reservation without a reservation no');
    }

    final requestBody =
        await _buildReservationBodyBallys(newReservation, masterId: masterId);

    debugPrintRequestBody(requestBody);

    final response =
        await apiService.post('Reservation_InsertReservation', requestBody);
    final status = response['Status'] as bool? ?? false;
    print('Reservation update status: $status');
    if (status) {
      return ReservationBallys.fromJson({
        'Reserv_No': (response['ReservationId'] ?? masterId).toString(),
      });
    } else {
      throw Exception(response['Message'] ?? 'Failed to update reservation');
    }
  }
  // Add this method to your ReservationRepository class

//   Future<bool> approveOrRejectReservation({
//     required String memberID,
//     required String reservationNo,
//     required String currentUName,
//     required String status,
//     required String remarks,

//   }) async {
//     final deviceId = await DeviceId.get();
//     final spName = await StorageUtil.getStoredProcedureName();
// print('Approving/Rejecting reservation with status: $status');
// print('Member ID: $memberID, Reservation No: $reservationNo, Current User: $currentUName, Remarks: $remarks');
//     final requestBody = {
//       "HasReturnData": "T",
//       "Parameters": [
//         {
//           "Para_Data": 8014,
//           "Para_Direction": "Input",
//           "Para_Lenth": 1,
//           "Para_Name": "@Iid",
//           "Para_Type": "int",
//         },
//         {
//           "Para_Data": memberID,
//           "Para_Direction": "Input",
//           "Para_Lenth": 100,
//           "Para_Name": "@Text1",
//           "Para_Type": "varchar",
//         },
//         {
//           "Para_Data": reservationNo,
//           "Para_Direction": "Input",
//           "Para_Lenth": 100,
//           "Para_Name": "@Text12",
//           "Para_Type": "varchar",
//         },
//         {
//           "Para_Data": currentUName,
//           "Para_Direction": "Input",
//           "Para_Lenth": 100,
//           "Para_Name": "@Text13",
//           "Para_Type": "varchar",
//         },
//         {
//           "Para_Data": status,
//           "Para_Direction": "Input",
//           "Para_Lenth": 100,
//           "Para_Name": "@Text14",
//           "Para_Type": "varchar",
//         },
//         {
//           "Para_Data": remarks,
//           "Para_Direction": "Input",
//           "Para_Lenth": 100,
//           "Para_Name": "@Text15",
//           "Para_Type": "varchar",
//         },
//         {
//           "Para_Data": deviceId,
//           "Para_Direction": "Input",
//           "Para_Lenth": 100,
//           "Para_Name": "@Text30",
//           "Para_Type": "varchar",
//         },
//       ],
//       "SpName": spName,
//       "con": "1",
//     };


//     printLargeBody(jsonEncode(requestBody));


//     try {
//       final response = await apiService.post('CommonExecute', requestBody);
// print('Response from approve/reject API: $response');
//       if (response['CommonResult'] != null) {
//         return true;
//       } else {
//         return false;
//       }
//     } catch (e) {
    
//       return false;
//     }
//   }

  // void printLargeBody(String body) {
  //   const chunkSize = 1024;
  //   for (int i = 0; i < body.length; i += chunkSize) {
     
  //   }
  // }
  void printLargeBody(String body) {
    const chunkSize = 800;
    for (int i = 0; i < body.length; i += chunkSize) {
      final end = (i + chunkSize < body.length) ? i + chunkSize : body.length;
      print(body.substring(i, end));
    }
  }
  String formatArrivalAndDepartureDate(DateTime? date) {
    if (date == null) {
      throw Exception('Arrival / Departure date is null');
    }
    return DateFormat('dd/MM/yyyy').format(date);
  }
}
