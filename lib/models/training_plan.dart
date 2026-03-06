import 'dart:convert';

class TrainingDay {
  final String dayLabel;
  final String workoutType;
  final String? description;
  final double? targetDistanceKm;
  final int? targetDurationMinutes;
  final String? targetPace;
  final String? notes;

  const TrainingDay({
    required this.dayLabel,
    required this.workoutType,
    this.description,
    this.targetDistanceKm,
    this.targetDurationMinutes,
    this.targetPace,
    this.notes,
  });

  factory TrainingDay.fromJson(Map<String, dynamic> json) {
    return TrainingDay(
      dayLabel: json['day_label'] as String? ?? 'Day',
      workoutType: json['workout_type'] as String? ?? 'Unknown',
      description: json['description'] as String?,
      targetDistanceKm: (json['target_distance_km'] as num?)?.toDouble(),
      targetDurationMinutes: json['target_duration_minutes'] as int?,
      targetPace: json['target_pace'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'day_label': dayLabel,
        'workout_type': workoutType,
        if (description != null) 'description': description,
        if (targetDistanceKm != null) 'target_distance_km': targetDistanceKm,
        if (targetDurationMinutes != null)
          'target_duration_minutes': targetDurationMinutes,
        if (targetPace != null) 'target_pace': targetPace,
        if (notes != null) 'notes': notes,
      };

  bool get isRest => workoutType.toLowerCase().contains('rest');

  TrainingDay copyWith({
    String? dayLabel,
    String? workoutType,
    String? description,
    double? targetDistanceKm,
    int? targetDurationMinutes,
    String? targetPace,
    String? notes,
  }) {
    return TrainingDay(
      dayLabel: dayLabel ?? this.dayLabel,
      workoutType: workoutType ?? this.workoutType,
      description: description ?? this.description,
      targetDistanceKm: targetDistanceKm ?? this.targetDistanceKm,
      targetDurationMinutes: targetDurationMinutes ?? this.targetDurationMinutes,
      targetPace: targetPace ?? this.targetPace,
      notes: notes ?? this.notes,
    );
  }
}

class TrainingWeek {
  final int weekNumber;
  final String? theme;
  final List<TrainingDay> days;

  const TrainingWeek({
    required this.weekNumber,
    this.theme,
    required this.days,
  });

  factory TrainingWeek.fromJson(Map<String, dynamic> json) {
    final daysJson = json['days'] as List<dynamic>? ?? [];
    return TrainingWeek(
      weekNumber: json['week_number'] as int? ?? 0,
      theme: json['theme'] as String?,
      days: daysJson
          .map((d) => TrainingDay.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'week_number': weekNumber,
        if (theme != null) 'theme': theme,
        'days': days.map((d) => d.toJson()).toList(),
      };

  TrainingWeek copyWith({
    int? weekNumber,
    String? theme,
    List<TrainingDay>? days,
  }) {
    return TrainingWeek(
      weekNumber: weekNumber ?? this.weekNumber,
      theme: theme ?? this.theme,
      days: days ?? this.days,
    );
  }
}

class TrainingPlan {
  final String name;
  final String? goal;
  final int? totalWeeks;
  final String? startDate;
  final String? endDate;
  final List<TrainingWeek> weeks;
  final String source;
  final int createdAt;
  /// User override for "which week I'm in" (1-based). If set, used instead of inferring from startDate.
  final int? currentWeekOverride;
  /// When the user marked the final week complete (epoch ms). Enables "plan complete" UX and future AI/history use.
  final int? completedAt;

  const TrainingPlan({
    required this.name,
    this.goal,
    this.totalWeeks,
    this.startDate,
    this.endDate,
    required this.weeks,
    required this.source,
    required this.createdAt,
    this.currentWeekOverride,
    this.completedAt,
  });

  factory TrainingPlan.fromJson(Map<String, dynamic> json) {
    final weeksJson = json['weeks'] as List<dynamic>? ?? [];
    return TrainingPlan(
      name: json['name'] as String? ?? 'Training Plan',
      goal: json['goal'] as String?,
      totalWeeks: json['total_weeks'] as int?,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      weeks: weeksJson
          .map((w) => TrainingWeek.fromJson(w as Map<String, dynamic>))
          .toList(),
      source: json['source'] as String? ?? 'upload',
      createdAt: json['created_at'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
      currentWeekOverride: json['current_week_override'] as int?,
      completedAt: json['completed_at'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (goal != null) 'goal': goal,
        if (totalWeeks != null) 'total_weeks': totalWeeks,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'weeks': weeks.map((w) => w.toJson()).toList(),
        'source': source,
        'created_at': createdAt,
        if (currentWeekOverride != null) 'current_week_override': currentWeekOverride,
        if (completedAt != null) 'completed_at': completedAt,
      };

  TrainingPlan copyWith({
    String? name,
    String? goal,
    int? totalWeeks,
    String? startDate,
    String? endDate,
    List<TrainingWeek>? weeks,
    String? source,
    int? createdAt,
    int? currentWeekOverride,
    bool clearCurrentWeekOverride = false,
    int? completedAt,
    bool clearCompletedAt = false,
  }) {
    return TrainingPlan(
      name: name ?? this.name,
      goal: goal ?? this.goal,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      weeks: weeks ?? this.weeks,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      currentWeekOverride: clearCurrentWeekOverride
          ? null
          : (currentWeekOverride ?? this.currentWeekOverride),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  bool get isCompleted => completedAt != null;

  String toJsonString() => jsonEncode(toJson());

  /// Returns the current week. Uses [currentWeekOverride] if set (1-based), else infers from startDate.
  TrainingWeek? get currentWeek {
    if (weeks.isEmpty) return null;
    if (currentWeekOverride != null) {
      final idx = (currentWeekOverride! - 1).clamp(0, weeks.length - 1);
      return weeks[idx];
    }
    if (startDate == null) return weeks.firstOrNull;
    try {
      final start = DateTime.parse(startDate!);
      final now = DateTime.now();
      final daysDiff = now.difference(start).inDays;
      if (daysDiff < 0) return weeks.first;
      final weekIndex = daysDiff ~/ 7;
      if (weekIndex >= weeks.length) return weeks.last;
      return weeks[weekIndex];
    } catch (_) {
      return weeks.firstOrNull;
    }
  }
}
