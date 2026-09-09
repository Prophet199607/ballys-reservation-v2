/// One coordinator as the CRM returns it from `Coordinators/Get`.
class Coordinator {
  const Coordinator({
    required this.id,
    required this.coordinatorId,
    required this.name,
    this.contactNumber = '',
    this.email,
    this.isActive = true,
  });

  /// Row id in the CRM table.
  final int id;

  /// The business id — "COD009". This is what a request is saved against.
  final String coordinatorId;

  final String name;
  final String contactNumber;
  final String? email;
  final bool isActive;

  factory Coordinator.fromJson(Map<String, dynamic> json) {
    return Coordinator(
      id: (json['id'] as num?)?.toInt() ?? 0,
      coordinatorId: json['coordinator_id']?.toString() ?? '',
      name: json['coordinator_name']?.toString() ?? '',
      contactNumber: json['contact_number']?.toString() ?? '',
      email: json['email']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
