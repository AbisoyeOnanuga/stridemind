/// Gear (e.g. shoes, bikes) from Strava or added manually. Open-ended brand/model like Garmin Connect.
class Gear {
  final int? id;
  final String? stravaGearId;
  final String name;
  final String? brand;
  final String? model;
  final String? nickname;
  final String? notes;
  final double distanceKm;
  final int? notifyAtKm;
  final String source; // 'strava' | 'manual'
  final int createdAt;
  final int updatedAt;
  /// 'shoe' | 'bike' | null. Used for context-aware icon (run vs bike).
  final String? gearType;

  Gear({
    this.id,
    this.stravaGearId,
    required this.name,
    this.brand,
    this.model,
    this.nickname,
    this.notes,
    required this.distanceKm,
    this.notifyAtKm,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.gearType,
  });

  factory Gear.fromJson(Map<String, dynamic> json) {
    return Gear(
      id: json['id'] as int?,
      stravaGearId: json['strava_gear_id'] as String?,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      nickname: json['nickname'] as String?,
      notes: json['notes'] as String?,
      distanceKm: (json['distance_km'] as num).toDouble(),
      notifyAtKm: json['notify_at_km'] as int?,
      source: json['source'] as String,
      createdAt: json['created_at'] as int,
      updatedAt: json['updated_at'] as int,
      gearType: json['gear_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (stravaGearId != null) 'strava_gear_id': stravaGearId,
        'name': name,
        if (brand != null) 'brand': brand,
        if (model != null) 'model': model,
        if (nickname != null) 'nickname': nickname,
        if (notes != null) 'notes': notes,
        'distance_km': distanceKm,
        if (notifyAtKm != null) 'notify_at_km': notifyAtKm,
        'source': source,
        'created_at': createdAt,
        'updated_at': updatedAt,
        if (gearType != null) 'gear_type': gearType,
      };

  /// Display name: nickname if set, else name.
  String get displayName => (nickname != null && nickname!.trim().isNotEmpty) ? nickname! : name;
}
