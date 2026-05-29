/// Display row for a fitment (which vehicle a part fits). Pure domain.
class FitmentView {
  final String fitmentId;
  final String vehicleId;
  final String vehicleLabel;
  final String? note;
  const FitmentView({
    required this.fitmentId,
    required this.vehicleId,
    required this.vehicleLabel,
    this.note,
  });
}

/// Display row for a cross-reference / interchange number.
class CrossReferenceView {
  final String id;
  final String otherNumber;
  final String? otherBrand;
  final String refType; // 'oem' | 'interchange'
  const CrossReferenceView({
    required this.id,
    required this.otherNumber,
    this.otherBrand,
    required this.refType,
  });
}

/// Editable vehicle (Year/Make/Model/Engine).
class VehicleDraft {
  final String? id;
  final String make;
  final String model;
  final int? yearFrom;
  final int? yearTo;
  final String? engine;
  final String? body;
  const VehicleDraft({
    this.id,
    required this.make,
    required this.model,
    this.yearFrom,
    this.yearTo,
    this.engine,
    this.body,
  });
}
