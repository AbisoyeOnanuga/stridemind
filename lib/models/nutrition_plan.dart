import 'dart:convert';

class NutritionMeal {
  static const Object _unset = Object();

  final String name;
  final String? description;
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final String? timing;
  final List<String>? foods;
  final String? notes;

  const NutritionMeal({
    required this.name,
    this.description,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.timing,
    this.foods,
    this.notes,
  });

  factory NutritionMeal.fromJson(Map<String, dynamic> json) {
    final foodsRaw = json['foods'] as List<dynamic>?;
    return NutritionMeal(
      name: json['name'] as String? ?? 'Meal',
      description: json['description'] as String?,
      calories: _asInt(json['calories']),
      proteinG: _asDouble(json['protein_g']),
      carbsG: _asDouble(json['carbs_g']),
      fatG: _asDouble(json['fat_g']),
      timing: json['timing'] as String?,
      foods: foodsRaw?.map((f) => f.toString()).toList(),
      notes: json['notes'] as String?,
    );
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString().trim());
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (calories != null) 'calories': calories,
        if (proteinG != null) 'protein_g': proteinG,
        if (carbsG != null) 'carbs_g': carbsG,
        if (fatG != null) 'fat_g': fatG,
        if (timing != null) 'timing': timing,
        if (foods != null) 'foods': foods,
        if (notes != null) 'notes': notes,
      };

  String get macroSummary {
    final parts = <String>[];
    if (calories != null) parts.add('$calories kcal');
    if (proteinG != null) parts.add('P ${proteinG!.toStringAsFixed(0)}g');
    if (carbsG != null) parts.add('C ${carbsG!.toStringAsFixed(0)}g');
    if (fatG != null) parts.add('F ${fatG!.toStringAsFixed(0)}g');
    return parts.join(' · ');
  }

  NutritionMeal copyWith({
    String? name,
    Object? description = _unset,
    Object? calories = _unset,
    Object? proteinG = _unset,
    Object? carbsG = _unset,
    Object? fatG = _unset,
    Object? timing = _unset,
    Object? foods = _unset,
    Object? notes = _unset,
  }) {
    return NutritionMeal(
      name: name ?? this.name,
      description:
          identical(description, _unset) ? this.description : description as String?,
      calories: identical(calories, _unset) ? this.calories : calories as int?,
      proteinG:
          identical(proteinG, _unset) ? this.proteinG : proteinG as double?,
      carbsG: identical(carbsG, _unset) ? this.carbsG : carbsG as double?,
      fatG: identical(fatG, _unset) ? this.fatG : fatG as double?,
      timing: identical(timing, _unset) ? this.timing : timing as String?,
      foods: identical(foods, _unset) ? this.foods : foods as List<String>?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
    );
  }
}

class NutritionDay {
  static const Object _unset = Object();

  final String dayLabel;
  final int? totalCalories;
  final double? totalProteinG;
  final double? totalCarbsG;
  final double? totalFatG;
  final List<NutritionMeal> meals;
  final String? notes;

  const NutritionDay({
    required this.dayLabel,
    this.totalCalories,
    this.totalProteinG,
    this.totalCarbsG,
    this.totalFatG,
    required this.meals,
    this.notes,
  });

  factory NutritionDay.fromJson(Map<String, dynamic> json) {
    final mealsJson = json['meals'] as List<dynamic>? ?? [];
    return NutritionDay(
      dayLabel: json['day_label'] as String? ?? 'Day',
      totalCalories: NutritionMeal._asInt(json['total_calories']),
      totalProteinG: NutritionMeal._asDouble(json['total_protein_g']),
      totalCarbsG: NutritionMeal._asDouble(json['total_carbs_g']),
      totalFatG: NutritionMeal._asDouble(json['total_fat_g']),
      meals: mealsJson
          .map((m) => NutritionMeal.fromJson(m as Map<String, dynamic>))
          .toList(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'day_label': dayLabel,
        if (totalCalories != null) 'total_calories': totalCalories,
        if (totalProteinG != null) 'total_protein_g': totalProteinG,
        if (totalCarbsG != null) 'total_carbs_g': totalCarbsG,
        if (totalFatG != null) 'total_fat_g': totalFatG,
        'meals': meals.map((m) => m.toJson()).toList(),
        if (notes != null) 'notes': notes,
      };

  String get macroSummary {
    final parts = <String>[];
    if (totalCalories != null) parts.add('$totalCalories kcal');
    if (totalProteinG != null) {
      parts.add('P ${totalProteinG!.toStringAsFixed(0)}g');
    }
    if (totalCarbsG != null) parts.add('C ${totalCarbsG!.toStringAsFixed(0)}g');
    if (totalFatG != null) parts.add('F ${totalFatG!.toStringAsFixed(0)}g');
    return parts.join(' · ');
  }

  NutritionDay copyWith({
    String? dayLabel,
    Object? totalCalories = _unset,
    Object? totalProteinG = _unset,
    Object? totalCarbsG = _unset,
    Object? totalFatG = _unset,
    List<NutritionMeal>? meals,
    Object? notes = _unset,
  }) {
    return NutritionDay(
      dayLabel: dayLabel ?? this.dayLabel,
      totalCalories: identical(totalCalories, _unset)
          ? this.totalCalories
          : totalCalories as int?,
      totalProteinG: identical(totalProteinG, _unset)
          ? this.totalProteinG
          : totalProteinG as double?,
      totalCarbsG: identical(totalCarbsG, _unset)
          ? this.totalCarbsG
          : totalCarbsG as double?,
      totalFatG:
          identical(totalFatG, _unset) ? this.totalFatG : totalFatG as double?,
      meals: meals ?? this.meals,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
    );
  }
}

class NutritionPlan {
  static const Object _unset = Object();

  final String name;
  final String? goal;
  final int? dailyCalorieTarget;
  final double? dailyProteinTargetG;
  final double? dailyCarbsTargetG;
  final double? dailyFatTargetG;
  final String? generalGuidelines;
  final List<NutritionDay> days;
  final String source;
  final int createdAt;

  const NutritionPlan({
    required this.name,
    this.goal,
    this.dailyCalorieTarget,
    this.dailyProteinTargetG,
    this.dailyCarbsTargetG,
    this.dailyFatTargetG,
    this.generalGuidelines,
    required this.days,
    required this.source,
    required this.createdAt,
  });

  factory NutritionPlan.fromJson(Map<String, dynamic> json) {
    final daysJson = json['days'] as List<dynamic>? ?? [];
    return NutritionPlan(
      name: json['name'] as String? ?? 'Nutrition Plan',
      goal: json['goal'] as String?,
      dailyCalorieTarget: NutritionMeal._asInt(json['daily_calorie_target']),
      dailyProteinTargetG:
          NutritionMeal._asDouble(json['daily_protein_target_g']),
      dailyCarbsTargetG: NutritionMeal._asDouble(json['daily_carbs_target_g']),
      dailyFatTargetG: NutritionMeal._asDouble(json['daily_fat_target_g']),
      generalGuidelines: json['general_guidelines'] as String?,
      days: daysJson
          .map((d) => NutritionDay.fromJson(d as Map<String, dynamic>))
          .toList(),
      source: json['source'] as String? ?? 'upload',
      createdAt: NutritionMeal._asInt(json['created_at']) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (goal != null) 'goal': goal,
        if (dailyCalorieTarget != null)
          'daily_calorie_target': dailyCalorieTarget,
        if (dailyProteinTargetG != null)
          'daily_protein_target_g': dailyProteinTargetG,
        if (dailyCarbsTargetG != null)
          'daily_carbs_target_g': dailyCarbsTargetG,
        if (dailyFatTargetG != null) 'daily_fat_target_g': dailyFatTargetG,
        if (generalGuidelines != null) 'general_guidelines': generalGuidelines,
        'days': days.map((d) => d.toJson()).toList(),
        'source': source,
        'created_at': createdAt,
      };

  String toJsonString() => jsonEncode(toJson());

  String get dailyTargetSummary {
    final parts = <String>[];
    if (dailyCalorieTarget != null) parts.add('$dailyCalorieTarget kcal');
    if (dailyProteinTargetG != null) {
      parts.add('P ${dailyProteinTargetG!.toStringAsFixed(0)}g');
    }
    if (dailyCarbsTargetG != null) {
      parts.add('C ${dailyCarbsTargetG!.toStringAsFixed(0)}g');
    }
    if (dailyFatTargetG != null) {
      parts.add('F ${dailyFatTargetG!.toStringAsFixed(0)}g');
    }
    return parts.join(' · ');
  }

  /// Returns the day template matching today's day name, or the first day.
  NutritionDay? get todayTemplate {
    if (days.isEmpty) return null;
    final todayName =
        _weekdayName(DateTime.now().weekday); // 'Monday', 'Tuesday', …
    return days.firstWhere(
      (d) => d.dayLabel.toLowerCase().contains(todayName.toLowerCase()),
      orElse: () => days.first,
    );
  }

  static String _weekdayName(int weekday) {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return names[(weekday - 1).clamp(0, 6)];
  }

  NutritionPlan copyWith({
    String? name,
    Object? goal = _unset,
    Object? dailyCalorieTarget = _unset,
    Object? dailyProteinTargetG = _unset,
    Object? dailyCarbsTargetG = _unset,
    Object? dailyFatTargetG = _unset,
    Object? generalGuidelines = _unset,
    List<NutritionDay>? days,
    String? source,
    int? createdAt,
  }) {
    return NutritionPlan(
      name: name ?? this.name,
      goal: identical(goal, _unset) ? this.goal : goal as String?,
      dailyCalorieTarget: identical(dailyCalorieTarget, _unset)
          ? this.dailyCalorieTarget
          : dailyCalorieTarget as int?,
      dailyProteinTargetG: identical(dailyProteinTargetG, _unset)
          ? this.dailyProteinTargetG
          : dailyProteinTargetG as double?,
      dailyCarbsTargetG: identical(dailyCarbsTargetG, _unset)
          ? this.dailyCarbsTargetG
          : dailyCarbsTargetG as double?,
      dailyFatTargetG: identical(dailyFatTargetG, _unset)
          ? this.dailyFatTargetG
          : dailyFatTargetG as double?,
      generalGuidelines: identical(generalGuidelines, _unset)
          ? this.generalGuidelines
          : generalGuidelines as String?,
      days: days ?? this.days,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
