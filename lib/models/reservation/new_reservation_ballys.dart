
class NewReservationBallys {
  String? bmNumber;
  String? guestName;
  String? hotelName;
  List<Map<String, dynamic>>? roomDetails;
  int? noOfNights;
  DateTime? arrivalDate;
  DateTime? departureDate;
  String? hasAirTicketReservation;
  String? remarks;
  List<Map<String, dynamic>>? airTicketDetails;
  String? reservationNo;
  String? reservationnewnumber;
  String? packageAmount;

  /// Who settles the bill, and the Hamoos contact the reservation is handled
  /// by. Both used to be picked per room / per ticket and repeated inside
  /// `room_details` / `air_ticket_details`; they belong to the reservation, so
  /// they are chosen once on the form and sent once at the top of the body.
  String? paymentBy;
  String? contactPerson;

  /// The "Shared" tick beside the package amount: the reservation is on a
  /// shared package. Sent in its own right so an empty [packageAmount] no
  /// longer has to stand in for it — a shared package may still carry one.
  bool isSharedAmount;
  String? selectedMarketingPerson;

  /// Sales code of the marketing person named in [selectedMarketingPerson].
  /// Set when the reservation is keyed in off a coordinator request: the
  /// request carries who raised it, and the reservation has to credit them
  /// rather than the coordinator typing it.
  String? selectedMarketingPersonCode;

  /// Sent as `sales_code` instead of the logged-in user's own, again only on
  /// the coordinator-request path — there it carries the coordinator's id.
  /// Null on the normal path, where the repository uses the sales code in
  /// storage.
  String? salesCodeOverride;

  /// The approver this reservation is being sent to, picked from
  /// `GetAuthorizationLevels`. Null when the user left the dropdown empty.
  int? authorizationId;
  String? authorizationPerson;
  int? authorizationLevelNo;
  String? authorizationCategory;

  List<Map<String, dynamic>>? guests;
  List<Map<String, dynamic>>? passportImages;

  NewReservationBallys({
    this.bmNumber,
    this.guestName,
    this.hotelName,
    this.roomDetails,
    this.noOfNights,
    this.arrivalDate,
    this.departureDate,
    this.hasAirTicketReservation,
    this.remarks,
    this.airTicketDetails,
    this.reservationNo,
    this.reservationnewnumber,
    this.packageAmount,
    this.paymentBy,
    this.contactPerson,
    this.isSharedAmount = false,
    this.selectedMarketingPerson,
    this.selectedMarketingPersonCode,
    this.salesCodeOverride,
    this.authorizationId,
    this.authorizationPerson,
    this.authorizationLevelNo,
    this.authorizationCategory,
    this.guests,
    this.passportImages,
  });

  Map<String, dynamic> toJson() {
    return {
      'bm_number': bmNumber,
      'guest_name': guestName,
      'hotel_name': hotelName,
      'room_details': roomDetails,
      'no_of_nights': noOfNights,
      'arrival_date': arrivalDate?.toIso8601String(),
      'departure_date': departureDate?.toIso8601String(),
      'has_air_ticket_reservation': hasAirTicketReservation!,
      'remarks': remarks,
      'air_ticket_details': airTicketDetails,
      'reservation_no': reservationNo,
      'manual_reserv_no': reservationnewnumber,
      'package_amount': packageAmount,
      'payment_by': paymentBy,
      'contact_person': contactPerson,
      'is_shared_amount': isSharedAmount,
      'selected_marketing_person': selectedMarketingPerson,
      'selected_marketing_person_code': selectedMarketingPersonCode,
      'approve_person': approvePersonJson(),
      'guests': guests,
      'passport_images': passportImages,
    };
  }

  /// The approver block sent to `Reservation_InsertReservation`. Empty when no
  /// approver was picked, so the key is always present in the body.
  Map<String, dynamic> approvePersonJson() {
    if (authorizationId == null) return <String, dynamic>{};
    return {
      'authorization_id': authorizationId,
      'authorization_person': authorizationPerson ?? '',
      'authorization_level': authorizationLevelNo,
      'authorization_category': authorizationCategory ?? '',
    };
  }

  factory NewReservationBallys.fromJson(Map<String, dynamic> json) {
    return NewReservationBallys(
      bmNumber: json['bm_number'] ?? '',
      guestName: json['guest_name'] ?? '',
      hotelName: json['hotel_name'] ?? '',
      roomDetails: List<Map<String, dynamic>>.from(json['room_details'] ?? []),
      noOfNights: json['no_of_nights'] ?? 0,
      arrivalDate: json['arrival_date'] ?? '',
      departureDate: json['departure_date'] ?? '',
      hasAirTicketReservation: (json['has_air_ticket_reservation'] ?? '0'),
      remarks: json['remarks'] ?? '',
      airTicketDetails:
          List<Map<String, dynamic>>.from(json['air_ticket_details'] ?? []),
      reservationNo: json['reservNo'] ?? '',
      reservationnewnumber: json['Manual_Reserv_No'] ?? '',

    );
  }

  NewReservationBallys copyWith({
    String? bmNumber,
    String? guestName,
    String? hotelName,
    List<Map<String, dynamic>>? roomDetails,
    int? noOfNights,
    DateTime? arrivalDate,
    DateTime? departureDate,
    String? hasAirTicketReservation,
    String? remarks,
    List<Map<String, dynamic>>? airTicketDetails,
    String? reservationnewnumber,

  }) {
    return NewReservationBallys(
      bmNumber: bmNumber ?? this.bmNumber,
      guestName: guestName ?? this.guestName,
      hotelName: hotelName ?? this.hotelName,
      roomDetails: roomDetails ?? this.roomDetails,
      noOfNights: noOfNights ?? this.noOfNights,
      arrivalDate: arrivalDate ?? this.arrivalDate,
      departureDate: departureDate ?? this.departureDate,
      hasAirTicketReservation:
          hasAirTicketReservation ?? this.hasAirTicketReservation,
      remarks: remarks ?? this.remarks,
      airTicketDetails: airTicketDetails ?? this.airTicketDetails,
      reservationnewnumber: reservationnewnumber ?? this.reservationnewnumber,
    );
  }
}
