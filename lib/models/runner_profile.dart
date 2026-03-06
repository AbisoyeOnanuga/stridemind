/// User's training goals, target event, race times, and bio for coach context.
/// All fields optional; used in onboarding and profile.
class RunnerProfile {
  final String? targetGoal;
  final String? targetEventName;
  final String? targetDate;
  final String? raceTime5k;
  final String? raceTime10k;
  final String? raceTimeHalfMarathon;
  final String? raceTimeMarathon;
  final String? experienceLevel;
  /// Target time for the selected goal event (e.g. "3:30:00" for marathon). Optional.
  final String? targetGoalTime;
  final String? notes;

  const RunnerProfile({
    this.targetGoal,
    this.targetEventName,
    this.targetDate,
    this.raceTime5k,
    this.raceTime10k,
    this.raceTimeHalfMarathon,
    this.raceTimeMarathon,
    this.experienceLevel,
    this.targetGoalTime,
    this.notes,
  });

  factory RunnerProfile.fromJson(Map<String, dynamic> json) {
    return RunnerProfile(
      targetGoal: json['target_goal'] as String?,
      targetEventName: json['target_event_name'] as String?,
      targetDate: json['target_date'] as String?,
      raceTime5k: json['race_time_5k'] as String?,
      raceTime10k: json['race_time_10k'] as String?,
      raceTimeHalfMarathon: json['race_time_hm'] as String?,
      raceTimeMarathon: json['race_time_m'] as String?,
      experienceLevel: json['experience_level'] as String?,
      targetGoalTime: json['target_goal_time'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (targetGoal != null) 'target_goal': targetGoal,
        if (targetEventName != null) 'target_event_name': targetEventName,
        if (targetDate != null) 'target_date': targetDate,
        if (raceTime5k != null) 'race_time_5k': raceTime5k,
        if (raceTime10k != null) 'race_time_10k': raceTime10k,
        if (raceTimeHalfMarathon != null) 'race_time_hm': raceTimeHalfMarathon,
        if (raceTimeMarathon != null) 'race_time_m': raceTimeMarathon,
        if (experienceLevel != null) 'experience_level': experienceLevel,
        if (targetGoalTime != null) 'target_goal_time': targetGoalTime,
        if (notes != null) 'notes': notes,
      };

  bool get isEmpty =>
      targetGoal == null &&
      targetEventName == null &&
      targetDate == null &&
      raceTime5k == null &&
      raceTime10k == null &&
      raceTimeHalfMarathon == null &&
      raceTimeMarathon == null &&
      experienceLevel == null &&
      targetGoalTime == null &&
      (notes == null || notes!.trim().isEmpty);

  RunnerProfile copyWith({
    String? targetGoal,
    String? targetEventName,
    String? targetDate,
    String? raceTime5k,
    String? raceTime10k,
    String? raceTimeHalfMarathon,
    String? raceTimeMarathon,
    String? experienceLevel,
    String? targetGoalTime,
    String? notes,
  }) {
    return RunnerProfile(
      targetGoal: targetGoal ?? this.targetGoal,
      targetEventName: targetEventName ?? this.targetEventName,
      targetDate: targetDate ?? this.targetDate,
      raceTime5k: raceTime5k ?? this.raceTime5k,
      raceTime10k: raceTime10k ?? this.raceTime10k,
      raceTimeHalfMarathon: raceTimeHalfMarathon ?? this.raceTimeHalfMarathon,
      raceTimeMarathon: raceTimeMarathon ?? this.raceTimeMarathon,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      targetGoalTime: targetGoalTime ?? this.targetGoalTime,
      notes: notes ?? this.notes,
    );
  }
}
