import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:ballys_reservation_app/components/passport_upload_widget_ballys.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/models/airport_search_response.dart';
import 'package:ballys_reservation_app/models/authorization_level.dart';
import 'package:ballys_reservation_app/models/reservation/air_ticket_class_count.dart';
import 'package:ballys_reservation_app/models/reservation/assigned_guest.dart';
import 'package:ballys_reservation_app/models/reservation/flight_bookng_ballys.dart';
import 'package:ballys_reservation_app/models/reservation/quick_hotel_entry.dart';
import 'package:ballys_reservation_app/utils/amount_util.dart';
import 'package:ballys_reservation_app/utils/device_id.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';

/// What came back from a quick reservation save, in the two parts the screen
/// actually reacts to: whether to clear the form, and what to put in the snack.
class QuickReservationResult {
  final bool success;
  final String? message;

  const QuickReservationResult({required this.success, this.message});
}

/// The API side of the quick reservation screen (Ballys).
///
/// Owns both endpoints the screen used to call through a bare [ApiService] and
/// the payload construction that fed them, so the screen hands over the form's
/// contents and gets back a [QuickReservationResult].
class QuickReservationRepository {
  final ApiService apiService;

  QuickReservationRepository(this.apiService);

  static const String _reservationEndpoint = 'Reservation_InsertReservation';
  static const String _transportEndpoint = 'Transport_Insert';

  // ── Hotel ───────────────────────────────────────────────────────────────────

  /// [members] are the banked guests plus the one still on the form, each a map
  /// of `guestName` / `memberId` / `packageAmount` / `sharedPackage` and a
  /// `hotels` list of [QuickHotelEntry]. [extraMembers] are the captured
  /// share-the-booking rows. [liveRemarks] is the remark still on screen, which
  /// wins over anything banked with a hotel.
  Future<QuickReservationResult> saveHotelReservation({
    required List<Map<String, dynamic>> members,
    required List<Map<String, dynamic>> extraMembers,
    required String liveRemarks,
    required bool hasFamilyMembers,
    AuthorizationLevel? approver,
    String paymentBy = '',
    String contactPerson = '',
    void Function(String label, Object? payload)? log,
  }) async {
    final body = await buildHotelBody(
      members: members,
      extraMembers: extraMembers,
      liveRemarks: liveRemarks,
      hasFamilyMembers: hasFamilyMembers,
      approver: approver,
      paymentBy: paymentBy,
      contactPerson: contactPerson,
    );
    log?.call('Saving hotel reservation', body);
    final response = await apiService.post(_reservationEndpoint, body);
    log?.call('Hotel reservation response', response);
    return _toResult(response, 'Failed to save reservation');
  }

  Future<Map<String, dynamic>> buildHotelBody({
    required List<Map<String, dynamic>> members,
    required List<Map<String, dynamic>> extraMembers,
    required String liveRemarks,
    required bool hasFamilyMembers,
    AuthorizationLevel? approver,
    // Both belong to the reservation, not to a single room or ticket, so they
    // are sent once at the top of the body.
    String paymentBy = '',
    String contactPerson = '',
  }) async {
    // Flatten all hotel entries from all members into room_details. Each room
    // is sent once and names the guests it was ticked for inside its own
    // `assigned_guests`, so the row itself carries no BM number — the same
    // shape the new reservation screen sends. A room saved without a tick —
    // only possible when there is nobody to tick — falls back to the member it
    // was entered under, so every row still names somebody.
    final roomDetails = <Map<String, dynamic>>[];
    for (final m in members) {
      for (final h in _hotelsOf(m)) {
        final row = h.toApiJson();
        if (h.assignedGuests.isNotEmpty) {
          roomDetails.add(row);
        } else {
          roomDetails.add({
            ...row,
            'assigned_guests': [
              {
                'BMNumber': m['memberId'],
                'GuestName': m['guestName'],
              },
            ],
          });
        }
      }
    }

    // Every member is billed their own package, so the amount travels per
    // guest inside `guests` rather than on the reservation.
    final guests = members.map((m) {
      final hotels = _hotelsOf(m);
      final first = hotels.isNotEmpty ? hotels.first : null;
      final amount = m['packageAmount'] as String?;
      return <String, dynamic>{
        'BMNumber': m['memberId'],
        'GuestName': m['guestName'],
        'ArrivalDate': first?.arrivalDate?.toIso8601String(),
        'DepartureDate': first?.departureDate?.toIso8601String(),
        'HasFamilyMembers': hasFamilyMembers,
        'PackageAmount': packageAmountToInt(amount),
        'CurrencyType': packageAmountCurrency(amount),
        'IsSharedAmount': m['sharedPackage'] as bool? ?? false,
      };
    }).toList();

    final primary = members.first;
    final primaryHotels = _hotelsOf(primary);
    final firstHotel = primaryHotels.isNotEmpty ? primaryHotels.first : null;

    // Extra guests share the form guest's rooms and dates, so they add a
    // `guests` entry each — with their own package — and no room of their own.
    // `PrimaryBMNumber` / `IsSharedPackage` name the guest they hang off, which
    // is what marks them as that guest's members on the way back.
    for (final e in extraMembers) {
      final amount = e['packageAmount'] as String?;
      guests.add({
        'BMNumber': e['memberId'],
        'GuestName': e['guestName'],
        'PrimaryBMNumber': primary['memberId'],
        'IsSharedPackage': true,
        'ArrivalDate': firstHotel?.arrivalDate?.toIso8601String(),
        'DepartureDate': firstHotel?.departureDate?.toIso8601String(),
        'HasFamilyMembers': e['hasFamilyMembers'] as bool? ?? false,
        'PackageAmount': packageAmountToInt(amount),
        'CurrencyType': packageAmountCurrency(amount),
        'IsSharedAmount': e['sharedPackage'] as bool? ?? false,
      });
    }

    return {
      ...await _requestEnvelope(),
      'bm_number': primary['memberId'],
      'guest_name': primary['guestName'],
      'arrival_date': firstHotel?.arrivalDate?.toIso8601String(),
      'departure_date': firstHotel?.departureDate?.toIso8601String(),
      'has_air_ticket_reservation': false,
      'remarks': _hotelRemarks(primary, liveRemarks),
      'payment_by': paymentBy,
      'contact_person': contactPerson,
      'selected_marketing_person': '',
      'selected_marketing_person_code': '',
      'approve_person': approvePersonJson(approver),
      'reservation_status': 'Pending',
      'room_details': roomDetails,
      'air_ticket_details': <Map<String, dynamic>>[],
      'guests': guests,
      'passport_images': <Map<String, dynamic>>[],
    };
  }

  /// The approver block sent to `Reservation_InsertReservation` — the same
  /// shape `NewReservationBallys.approvePersonJson()` sends. Empty when the
  /// dropdown was left alone, so the key is always present in the body.
  Map<String, dynamic> approvePersonJson(AuthorizationLevel? approver) {
    if (approver == null) return <String, dynamic>{};
    return {
      'authorization_id': approver.idNo,
      'authorization_person': approver.name,
      'authorization_level': approver.levelNo,
      'authorization_category': approver.category,
    };
  }

  /// The reservation's remark. The field on screen wins — it is where the user
  /// last typed and it is never wiped by "Add Another Hotel" — falling back to
  /// the first non-empty remark banked with a hotel, which is where a remark
  /// typed before an older build's reset ended up.
  String _hotelRemarks(Map<String, dynamic> member, String liveRemarks) {
    final live = liveRemarks.trim();
    if (live.isNotEmpty) return live;
    for (final h in _hotelsOf(member)) {
      if (h.remarks.trim().isNotEmpty) return h.remarks.trim();
    }
    return '';
  }

  List<QuickHotelEntry> _hotelsOf(Map<String, dynamic> m) =>
      (m['hotels'] as List?)?.cast<QuickHotelEntry>() ?? const [];

  // ── Air ticket ──────────────────────────────────────────────────────────────

  /// [tickets] are the banked tickets plus the one still on the form. They are
  /// tagged here with the primary member so each row can name the guest it is
  /// booked for.
  Future<QuickReservationResult> saveAirReservation({
    required List<Map<String, dynamic>> members,
    required List<Map<String, dynamic>> tickets,
    required List<Map<String, dynamic>> extraMembers,
    required String liveRemarks,
    required bool hasFamilyMembers,
    AuthorizationLevel? approver,
    String paymentBy = '',
    String contactPerson = '',
    void Function(String label, Object? payload)? log,
  }) async {
    final body = await buildAirBody(
      members: members,
      tickets: tickets,
      extraMembers: extraMembers,
      liveRemarks: liveRemarks,
      hasFamilyMembers: hasFamilyMembers,
      approver: approver,
      paymentBy: paymentBy,
      contactPerson: contactPerson,
    );
    log?.call('Saving air ticket reservation', body);
    final response = await apiService.post(_reservationEndpoint, body);
    log?.call('Air ticket reservation response', response);
    return _toResult(response, 'Failed to save reservation');
  }

  Future<Map<String, dynamic>> buildAirBody({
    required List<Map<String, dynamic>> members,
    required List<Map<String, dynamic>> tickets,
    required List<Map<String, dynamic>> extraMembers,
    required String liveRemarks,
    required bool hasFamilyMembers,
    AuthorizationLevel? approver,
    // Reservation-level, exactly as in [buildHotelBody].
    String paymentBy = '',
    String contactPerson = '',
  }) async {
    final primary = members.first;
    final primaryMemberId = primary['memberId'];
    final primaryGuestName = primary['guestName'];

    // Every ticket for this guest, tagged with the guest's member ID and name
    // so each one can name the guest it is booked for inside its own
    // `assigned_guests`.
    final ticketSources = tickets
        .map((t) => <String, dynamic>{
              ...t,
              'memberId': primaryMemberId,
              'guestName': primaryGuestName,
            })
        .toList();

    final airTicketDetails =
        ticketSources.map(airTicketDetailOf).toList();

    // The reservation's dates come from the first ticket, which is not always
    // the one on screen — after banking every ticket the form is blank.
    final firstTicket = ticketSources.first;
    final primaryArrival = firstTicket['arrDateObj'] as DateTime?;
    final primaryDeparture = firstTicket['depDateObj'] as DateTime?;

    // Every member is billed their own package, so the amount travels per
    // guest inside `guests` rather than on the reservation.
    final guests = members.map((m) {
      final amount = m['packageAmount'] as String?;
      return <String, dynamic>{
        'BMNumber': m['memberId'],
        'GuestName': m['guestName'],
        'ArrivalDate': primaryArrival?.toIso8601String(),
        'DepartureDate': primaryDeparture?.toIso8601String(),
        'HasFamilyMembers': hasFamilyMembers,
        'PackageAmount': packageAmountToInt(amount),
        'CurrencyType': packageAmountCurrency(amount),
        'IsSharedAmount': m['sharedPackage'] as bool? ?? false,
      };
    }).toList();

    // Extra guests share the form guest's tickets and dates, so they add a
    // `guests` entry each — with their own package — and no ticket of their own.
    // `PrimaryBMNumber` / `IsSharedPackage` name the guest they hang off, which
    // is what marks them as that guest's members on the way back.
    for (final e in extraMembers) {
      final amount = e['packageAmount'] as String?;
      guests.add({
        'BMNumber': e['memberId'],
        'GuestName': e['guestName'],
        'PrimaryBMNumber': primaryMemberId,
        'IsSharedPackage': true,
        'ArrivalDate': primaryArrival?.toIso8601String(),
        'DepartureDate': primaryDeparture?.toIso8601String(),
        'HasFamilyMembers': e['hasFamilyMembers'] as bool? ?? false,
        'PackageAmount': packageAmountToInt(amount),
        'CurrencyType': packageAmountCurrency(amount),
        'IsSharedAmount': e['sharedPackage'] as bool? ?? false,
      });
    }

    return {
      ...await _requestEnvelope(),
      'bm_number': primaryMemberId,
      'guest_name': primaryGuestName,
      'arrival_date': primaryArrival?.toIso8601String(),
      'departure_date': primaryDeparture?.toIso8601String(),
      'has_air_ticket_reservation': true,
      // The field on screen wins — it is where the user last typed and it is
      // never wiped by "Add Another Air Ticket" — falling back to the remark
      // banked with the first ticket.
      'remarks': liveRemarks.trim().isNotEmpty
          ? liveRemarks.trim()
          : (firstTicket['remarks'] ?? ''),
      'payment_by': paymentBy,
      'contact_person': contactPerson,
      'selected_marketing_person': '',
       'selected_marketing_person_code': '',
      'approve_person': approvePersonJson(approver),
      'reservation_status': 'Pending',
      'room_details': <Map<String, dynamic>>[],
      'air_ticket_details': airTicketDetails,
      'guests': guests,
      // Passports are uploaded against whichever ticket was on screen at the
      // time, so every ticket contributes — not just the one left in the form.
      'passport_images': buildPassportImages(ticketSources),
    };
  }

  Map<String, dynamic> airTicketDetailOf(Map<String, dynamic> m) {
    final fromAirport = m['fromAirportData'] as Airport?;
    final toAirport = m['toAirportData'] as Airport?;
    final returnFrom = m['returnFromData'] as Airport?;
    final returnTo = m['returnToData'] as Airport?;
    final arrDate = m['arrDateObj'] as DateTime?;
    final depDate = m['depDateObj'] as DateTime?;
    final seats = int.tryParse(m['noOfSeats'] as String? ?? '1') ?? 1;
    final children = int.tryParse(m['noOfChildren'] as String? ?? '0') ?? 0;
    final infants = int.tryParse(m['noOfInfants'] as String? ?? '0') ?? 0;
    final ticketClasses = (m['ticketClasses'] as List<AirTicketClassCount>?) ??
        const <AirTicketClassCount>[];
    final assigned =
        (m['assignedGuests'] as List<AssignedGuest>?) ?? const <AssignedGuest>[];
    return {
      'guest_count': seats,
      'children_count': children,
      'infant_count': infants,
      // Every class on the ticket with its own seat count, replacing the single
      // `air_ticket_class` / `air_ticket_class_name` pair — the same shape
      // FlightBookingBallys.toJson() sends.
      'air_ticket_classes': ticketClasses.map((c) => c.toJson()).toList(),
      'air_line': m['airline'],
      'air_line_code': m['airlineCode'],
      'iata_code': m['iataCode'],
      // `contact_person` is a reservation-level field now, so it is sent once at
      // the top of the body rather than repeated on every ticket.
      'visa': (m['visa'] as String?) == 'Yes',
      'meal': (m['meal'] as String?) == 'Yes',
      'extra_leg_room_seat': (m['extraLegroomSeat'] as String?) == 'Yes',
      'gold_route': (m['goldRoute'] as String?) == 'Yes',
      'is_round_trip': m['isRoundTrip'] as bool? ?? false,
      'silk_route': (m['skipRouteFacility'] as String?) == 'Yes' ? 1 : 0,
      // Follow-ups ride along only when their option is Yes, matching
      // FlightBookingBallys.toJson().
      'silk_route_type': (m['skipRouteFacility'] as String?) == 'Yes'
          ? (m['silkRouteType'] as String? ?? '')
          : '',
      'gold_route_type': (m['goldRoute'] as String?) == 'Yes'
          ? (m['goldRouteType'] as String? ?? '')
          : '',
      'meal_remark': (m['meal'] as String?) == 'Yes'
          ? (m['mealRemark'] as String? ?? '')
          : '',
      'airport_transportation':
          (m['airportTransport'] as String?) == 'Yes' ? 1 : 0,
      'arrival_date': arrDate?.toIso8601String(),
      'departure_date': depDate?.toIso8601String(),
      // Air ticket costs are no longer captured on this screen.
      'selected_cost': 0.0,
      'DF_AirportCode': fromAirport?.airportCode,
      'DF_CityName': fromAirport?.cityName,
      'DF_AirportName': fromAirport?.airportName,
      'DF_Country': fromAirport?.country,
      'DT_AirportCode': toAirport?.airportCode,
      'DT_CityName': toAirport?.cityName,
      'DT_AirportName': toAirport?.airportName,
      'DT_Country': toAirport?.country,
      'RF_AirportCode': returnFrom?.airportCode,
      'RF_CityName': returnFrom?.cityName,
      'RF_AirportName': returnFrom?.airportName,
      'RF_Country': returnFrom?.country,
      'RT_AirportCode': returnTo?.airportCode,
      'RT_CityName': returnTo?.cityName,
      'RT_AirportName': returnTo?.airportName,
      'RT_Country': returnTo?.country,
      // Transit stops for guests with no direct flight, in travel order. The
      // DF_/DT_ and RF_/RT_ fields above stay the leg endpoints. Matches
      // FlightBookingBallys.toJson().
      'is_multi_sector': m['isMultiSector'] as bool? ?? false,
      'departure_sectors': _sectorsToJson(m['departureSectorData']),
      'return_sectors': _sectorsToJson(m['returnSectorData']),
      // Everyone the ticket was ticked for, named inside the row itself rather
      // than by a BM number on it — the same shape the new reservation screen
      // sends. A ticket saved without a tick — only possible when there is
      // nobody to tick — falls back to the member it was entered under.
      'assigned_guests': assigned.isNotEmpty
          ? assigned.map((g) => g.toJson()).toList()
          : [
              {
                'BMNumber': m['memberId'],
                'GuestName': m['guestName'] ?? '',
              },
            ],
    };
  }

  /// Transit stops in the shape `FlightBookingBallys` sends them, each with the
  /// day it is flown — `AirportInfo.toSectorJson()` is the same writer the new
  /// reservation screen goes through, so a route saved from either screen reads
  /// back identically.
  List<Map<String, dynamic>> _sectorsToJson(dynamic sectors) {
    if (sectors is! List) return const [];
    return sectors
        .whereType<AirportInfo>()
        .map((sector) => sector.toSectorJson())
        .toList();
  }

  List<Map<String, dynamic>> buildPassportImages(
      List<Map<String, dynamic>> members) {
    final images = <Map<String, dynamic>>[];
    for (final m in members) {
      final memberId = m['memberId'] as String? ?? '';
      final files = m['passportFileObjects'] as List<PassportFileBallys>? ?? [];
      for (final f in files) {
        try {
          final bytes = File(f.path).readAsBytesSync();
          // A page picked under a named guest goes out under that member; one
          // picked before anybody was ticked falls back to the member the
          // ticket was entered for. Same rule as
          // PassportImageBallys.toJsonWithGuest().
          final owner = f.guestBmNumber.trim();
          images.add({
            'GuestBMNumber': owner.isNotEmpty ? owner : memberId,
            'FileName': f.fileName,
            'IsPdf': f.isPdf,
            'Base64Data': base64Encode(bytes),
          });
        } catch (_) {}
      }
    }
    return images;
  }

  // ── Transport ───────────────────────────────────────────────────────────────

  Future<QuickReservationResult> saveTransportReservation({
    required List<Map<String, dynamic>> members,
    void Function(String label, Object? payload)? log,
  }) async {
    final body = await buildTransportBody(members: members);
    log?.call('Saving transport reservation', body);
    final response = await apiService.post(_transportEndpoint, body);
    log?.call('Transport reservation response', response);
    return _toResult(response, 'Failed to save transport reservation');
  }

  Future<Map<String, dynamic>> buildTransportBody({
    required List<Map<String, dynamic>> members,
  }) async {
    final transportDetails = members.map(transportDetailOf).toList();
    final primary = members.first;
    final phoneNumber = await StorageUtil.getMobileNumber();

    return {
      ...await _requestEnvelope(),
      'MID': primary['memberId'],
      'guest_name': primary['guestName'],
      'pickup_date': pickupIso(primary),
      'contact_number': phoneNumber,
      'reservation_status': 'Requested',
      'transport_details': transportDetails,
    };
  }

  Map<String, dynamic> transportDetailOf(Map<String, dynamic> m) {
    final vehicles = (m['vehicleDetails'] as List?)?.cast<Map>() ?? const [];
    return {
      'MID': m['memberId'],
      'guest_name': m['guestName'],
      // Guests sharing this request: same pickup, vehicles and dates, each
      // carrying their own package amount.
      'accompanying_members': _extraMembersOf(m)
          .map((e) => {
                'MID': e['memberId'],
                'guest_name': e['guestName'],
              })
          .toList(),
      'pickup_date': pickupIso(m),
      'pickup_time': m['pickupTime'],
      'hire_type': m['hireType'],
      'pickup_location': m['pickupLocation'],
      'pickup_place_id': m['pickupPlaceId'],
      'drop_location': m['dropLocation'],
      'drop_place_id': m['dropPlaceId'],
      'no_of_vehicles': vehicles.length,
      'vehicle_details': vehicles
          .map((v) => {
                'car_type': v['carType'],
                'no_of_passengers':
                    int.tryParse(v['noOfPassengers'] as String? ?? '1') ?? 1,
              })
          .toList(),
      'contact_number': m['contactNumber'],
      'airport_pickup': (m['airportPickup'] as String?) == 'Yes' ? 1 : 0,
    };
  }

  /// Pickup date and time combined into a single ISO timestamp.
  String? pickupIso(Map<String, dynamic> m) {
    final date = m['pickupDateObj'] as DateTime?;
    if (date == null) return null;
    final time = m['pickupTimeObj'] as TimeOfDay?;
    return DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    ).toIso8601String();
  }

  /// The extra guests captured alongside a transport member, typed for use.
  List<Map<String, dynamic>> _extraMembersOf(Map<String, dynamic> m) =>
      (m['extraMembers'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

  // ── Shared ──────────────────────────────────────────────────────────────────

  /// The identity fields every quick reservation carries, read once per save.
  Future<Map<String, dynamic>> _requestEnvelope() async => {
        'master_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'sales_code': await StorageUtil.getSalesCode(),
        'user_name': await StorageUtil.getUserName(),
        'device_id': await DeviceId.get(),
      };

  QuickReservationResult _toResult(
      Map<String, dynamic> response, String fallbackError) {
    final success = response['Status'] as bool? ?? false;
    return QuickReservationResult(
      success: success,
      message: response['Message'] as String? ?? (success ? null : fallbackError),
    );
  }
}
