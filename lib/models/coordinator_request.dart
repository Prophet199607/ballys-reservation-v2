/// One guest on a request that was already sent, as `CoordinatorRequest/
/// GetByCoordinator` returns it.
class CoordinatorRequestRecordGuest {
  const CoordinatorRequestRecordGuest({
    required this.id,
    required this.bmNumber,
    required this.guestName,
    this.createdDate,
  });

  final int id;
  final String bmNumber;
  final String guestName;
  final DateTime? createdDate;

  factory CoordinatorRequestRecordGuest.fromJson(Map<String, dynamic> json) {
    return CoordinatorRequestRecordGuest(
      id: (json['id'] as num?)?.toInt() ?? 0,
      bmNumber: json['bm_number']?.toString() ?? '',
      guestName: json['guest_name']?.toString() ?? '',
      createdDate: DateTime.tryParse(json['created_date']?.toString() ?? ''),
    );
  }
}

/// A coordinator request that has already been sent — the read side of what
/// [CoordinatorRequestRepository.saveCoordinatorRequest] writes.
class CoordinatorRequestRecord {
  const CoordinatorRequestRecord({
    required this.id,
    required this.masterId,
    required this.coordinatorId,
    required this.coordinatorName,
    required this.requestType,
    this.remarks = '',
    this.salesCode = '',
    this.userName = '',
    this.createdDate,
    this.guests = const [],
  });

  final int id;

  /// The reference the save returned — what the backend keys the request on.
  final String masterId;

  final String coordinatorId;
  final String coordinatorName;

  /// 'AIR_TICKET' | 'HOTEL' | 'BOTH'.
  final String requestType;

  final String remarks;

  /// Who raised it.
  final String salesCode;
  final String userName;

  final DateTime? createdDate;
  final List<CoordinatorRequestRecordGuest> guests;

  factory CoordinatorRequestRecord.fromJson(Map<String, dynamic> json) {
    final guests = json['guests'];
    return CoordinatorRequestRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      masterId: json['master_id']?.toString() ?? '',
      coordinatorId: json['coordinator_id']?.toString() ?? '',
      coordinatorName: json['coordinator_name']?.toString() ?? '',
      requestType: json['request_type']?.toString() ?? '',
      remarks: json['remarks']?.toString() ?? '',
      salesCode: json['sales_code']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? '',
      createdDate: DateTime.tryParse(json['created_date']?.toString() ?? ''),
      guests: guests is List
          ? guests
              .whereType<Map>()
              .map((g) => CoordinatorRequestRecordGuest.fromJson(
                  Map<String, dynamic>.from(g)))
              .toList()
          : const [],
    );
  }
}
