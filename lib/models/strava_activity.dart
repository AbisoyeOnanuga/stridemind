/// Safely parses an optional int from JSON (handles int, double, or String from SQLite/API).
int? _jsonInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

int _jsonIntReq(dynamic v, [int fallback = 0]) => _jsonInt(v) ?? fallback;

class Split {
  final double distance; // in meters
  final int movingTime; // in seconds
  final double averageSpeed; // in m/s

  Split({
    required this.distance,
    required this.movingTime,
    required this.averageSpeed,
  });

  factory Split.fromJson(Map<String, dynamic> json) {
    return Split(
      distance: (json['distance'] ?? 0.0).toDouble(),
      movingTime: _jsonIntReq(json['moving_time']),
      averageSpeed: (json['average_speed'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'distance': distance,
        'moving_time': movingTime,
        'average_speed': averageSpeed,
      };
}

/// Strava "lap" / interval segment from GET /activities/{id}.
/// This is the closest API representation to what Strava shows under Laps/Intervals,
/// which is important for structured workouts (e.g. Garmin run/walk).
class Lap {
  final int? lapIndex;
  final double distance; // in meters
  final int movingTime; // in seconds
  final int elapsedTime; // in seconds
  final double averageSpeed; // in m/s

  Lap({
    this.lapIndex,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    required this.averageSpeed,
  });

  factory Lap.fromJson(Map<String, dynamic> json) {
    return Lap(
      lapIndex: _jsonInt(json['lap_index']),
      distance: (json['distance'] ?? 0.0).toDouble(),
      movingTime: _jsonIntReq(json['moving_time']),
      elapsedTime: _jsonIntReq(json['elapsed_time']),
      averageSpeed: (json['average_speed'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (lapIndex != null) 'lap_index': lapIndex,
        'distance': distance,
        'moving_time': movingTime,
        'elapsed_time': elapsedTime,
        'average_speed': averageSpeed,
      };

  Split toSplit() => Split(
        distance: distance,
        movingTime: movingTime,
        averageSpeed: averageSpeed,
      );
}

class StravaActivity {
  final int id;
  final String name;
  final String type;
  final double distance; // in meters
  final int movingTime; // in seconds
  final int elapsedTime; // in seconds
  final double totalElevationGain;
  final DateTime startDateLocal;
  final double? averageSpeed; // in m/s
  final double? averageHeartrate;
  final double? averageCadence;
  final List<Split>? splits;
  final List<Lap>? laps;
  final String? description;
  final int? sufferScore;
  /// Strava gear id (e.g. shoes or bike) used for this activity. Used for coach context.
  final String? gearId;
  /// Activity source (currently 'strava').
  final String? source;

  StravaActivity({
    required this.id,
    required this.name,
    required this.type,
    required this.distance,
    required this.movingTime,
    required this.elapsedTime,
    required this.totalElevationGain,
    required this.startDateLocal,
    this.averageSpeed,
    this.averageHeartrate,
    this.averageCadence,
    this.splits,
    this.laps,
    this.description,
    this.sufferScore,
    this.gearId,
    this.source,
  });

  factory StravaActivity.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? splitsJson = json['splits_metric'];
    final List<Split>? splits =
        splitsJson?.map((s) => Split.fromJson(s)).toList();

    final List<dynamic>? lapsJson = json['laps'];
    final List<Lap>? laps = lapsJson?.map((l) => Lap.fromJson(l)).toList();

    return StravaActivity(
      id: _jsonIntReq(json['id']),
      name: json['name'] ?? 'Unnamed Activity',
      type: json['type'] ?? 'Unknown',
      distance: (json['distance'] ?? 0.0).toDouble(),
      movingTime: _jsonIntReq(json['moving_time']),
      elapsedTime: _jsonIntReq(json['elapsed_time']),
      totalElevationGain: (json['total_elevation_gain'] ?? 0.0).toDouble(),
      startDateLocal: DateTime.parse(json['start_date_local']),
      averageSpeed: (json['average_speed'] as num?)?.toDouble(),
      averageHeartrate: (json['average_heartrate'] as num?)?.toDouble(),
      // Cadence is often steps per minute * 2 in Strava API for running
      averageCadence: (json['average_cadence'] as num?)?.toDouble(),
      splits: splits,
      laps: laps,
      description: json['description'] as String?,
      sufferScore: _jsonInt(json['suffer_score']),
      gearId: json['gear_id'] as String?,
      source: json['source'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'distance': distance,
        'moving_time': movingTime,
        'elapsed_time': elapsedTime,
        'total_elevation_gain': totalElevationGain,
        'start_date_local': startDateLocal.toIso8601String(),
        if (averageSpeed != null) 'average_speed': averageSpeed,
        if (averageHeartrate != null) 'average_heartrate': averageHeartrate,
        if (averageCadence != null) 'average_cadence': averageCadence,
        if (splits != null)
          'splits_metric': splits!.map((s) => s.toJson()).toList(),
        if (laps != null) 'laps': laps!.map((l) => l.toJson()).toList(),
        if (description != null) 'description': description,
        if (sufferScore != null) 'suffer_score': sufferScore,
        if (gearId != null) 'gear_id': gearId,
        if (source != null) 'source': source,
      };

  /// Canonical segments for display: prefer Strava laps/intervals when present.
  /// Falls back to Strava's per-km splits when laps aren't available.
  List<Split> get canonicalSegments {
    final l = laps;
    if (l != null && l.isNotEmpty) return l.map((e) => e.toSplit()).toList();
    return splits ?? const [];
  }

  // Helper to get distance in kilometers
  double get distanceInKm => distance / 1000;

  // Helper to format moving time into HH:MM:SS
  String get formattedMovingTime {
    final duration = Duration(seconds: movingTime);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }
}