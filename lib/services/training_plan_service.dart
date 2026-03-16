import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stridemind/models/training_plan.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/utils/plan_file_reader.dart';
import 'package:stridemind/utils/training_plan_storage_config.dart';

/// SQLite can return INTEGER columns as double; safely coerce to int?.
int? _safeInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// A training plan with DB row metadata (id, active, archived).
class TrainingPlanEntry {
  const TrainingPlanEntry({
    required this.id,
    required this.isActive,
    required this.archived,
    required this.plan,
  });
  final int id;
  final bool isActive;
  final bool archived;
  final TrainingPlan plan;
}

class TrainingPlanService {
  final DatabaseService _db = DatabaseService();
  late final GenerativeModel _model;
  static const String _geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  static const List<String> _defaultDayLabels = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  TrainingPlanService()
      : _model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: _geminiApiKey,
        );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Parses an uploaded file into a structured [TrainingPlan] using Gemini.
  Future<TrainingPlan> parseFile(Uint8List bytes, String extension) async {
    _ensureGeminiConfigured();
    if (!PlanFileReader.isSupported(extension)) {
      throw UnsupportedError('File type .$extension is not supported.');
    }
    final text = PlanFileReader.extractText(bytes, extension);
    final plan = text != null
        ? await _parseTextContent(text)
        : await _parseMultimodal(bytes, PlanFileReader.mimeType(extension)!);
    return _normalisePlan(plan);
  }

  Future<void> savePlan(TrainingPlan plan) async {
    try {
      await _db.saveTrainingPlan(plan);
    } on DatabaseException catch (_) {
      throw StorageFullException();
    }
  }

  /// Updates the active plan in place (mark complete/incomplete, edit details, edit day).
  /// If no active row exists, saves the plan so it appears in history and can be archived/deleted.
  Future<void> updateActivePlan(TrainingPlan plan) async {
    final normalised = _normalisePlan(plan);
    final updated = await _db.updateActiveTrainingPlan(normalised);
    if (!updated) await savePlan(normalised);
  }

  /// Number of non-archived plans (for storage cap and soft warning).
  Future<int> getPlanCount() => _db.getTrainingPlanCount(includeArchived: false);

  /// Whether to show the "many plans" soft warning (e.g. at 80% of cap).
  bool shouldShowStorageWarning(int count) =>
      count >= TrainingPlanStorageConfig.softWarningThreshold;

  Future<List<TrainingPlanEntry>> getAllPlans({bool includeArchived = false}) async {
    final rows = await _db.getAllTrainingPlanRows(includeArchived: includeArchived);
    final list = <TrainingPlanEntry>[];
    for (final row in rows) {
      try {
        final planMap = jsonDecode(row['plan_json'] as String) as Map<String, dynamic>;
        final plan = _normalisePlan(TrainingPlan.fromJson(planMap));
        final id = _safeInt(row['id']);
        if (id == null) continue;
        list.add(TrainingPlanEntry(
          id: id,
          isActive: _safeInt(row['is_active']) == 1,
          archived: _safeInt(row['archived']) == 1,
          plan: plan,
        ));
      } catch (_) {}
    }
    return list;
  }

  Future<void> archivePlan(int id) => _db.updateTrainingPlanArchived(id, true);

  Future<void> unarchivePlan(int id) => _db.updateTrainingPlanArchived(id, false);

  Future<void> deletePlanById(int id) => _db.deleteTrainingPlanById(id);

  Future<void> setActivePlanById(int id) => _db.setActiveTrainingPlan(id);

  Future<void> clearActivePlan() => _db.clearActiveTrainingPlan();

  /// Returns a short summary of non-archived plans for AI coach context. Archived plans are excluded.
  /// Used when building the coach prompt so the coach can reference completed/active plan history.
  Future<String> getPlanHistorySummaryForCoach() async {
    final plans = await getAllPlans(includeArchived: false);
    if (plans.isEmpty) return '';
    final buffer = StringBuffer();
    for (final e in plans) {
      final status = e.isActive ? 'active' : (e.plan.completedAt != null ? 'completed' : 'saved');
      String dateStr = '';
      if (e.plan.completedAt != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(e.plan.completedAt!);
        dateStr = '; completed ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
      buffer.writeln('- ${e.plan.name} (goal: ${e.plan.goal ?? "—"}); $status$dateStr');
    }
    return buffer.toString();
  }

  Future<TrainingPlan?> getActivePlan() async {
    final plan = await _db.getActiveTrainingPlan();
    return plan != null ? _normalisePlan(plan) : null;
  }

  /// Ensures each week has exactly 7 days (Monday–Sunday). Fills missing with Rest; trims excess.
  TrainingPlan _normalisePlan(TrainingPlan plan) {
    return plan.copyWith(
      weeks: plan.weeks.map(_normaliseWeek).toList(),
    );
  }

  TrainingWeek _normaliseWeek(TrainingWeek week) {
    final List<TrainingDay> days = [];
    for (int i = 0; i < _defaultDayLabels.length; i++) {
      final label = _defaultDayLabels[i];
      if (i < week.days.length) {
        final d = week.days[i];
        if (d.isRest) {
          days.add(TrainingDay(dayLabel: label, workoutType: 'Rest'));
        } else {
          days.add(d.copyWith(dayLabel: label));
        }
      } else {
        days.add(TrainingDay(
          dayLabel: label,
          workoutType: 'Rest',
        ));
      }
    }
    return week.copyWith(days: days);
  }
  Future<void> deleteActivePlan() => _db.deleteActiveTrainingPlan();

  /// Extends or trims the plan to [targetTotalWeeks]. If longer, generates
  /// additional weeks via AI; if shorter, trims the weeks list.
  Future<TrainingPlan> extendPlan(TrainingPlan plan, int targetTotalWeeks) async {
    _ensureGeminiConfigured();
    if (targetTotalWeeks <= plan.weeks.length) {
      final trimmed = plan.copyWith(
        totalWeeks: targetTotalWeeks,
        weeks: plan.weeks.take(targetTotalWeeks).toList(),
      );
      return _normalisePlan(trimmed);
    }
    final weeksToGenerate = targetTotalWeeks - plan.weeks.length;
    final newWeeks = await _generateWeeks(
      existingPlan: plan,
      startWeekNumber: plan.weeks.length + 1,
      count: weeksToGenerate,
    );
    final allWeeks = [...plan.weeks, ...newWeeks];
    return _normalisePlan(plan.copyWith(
      totalWeeks: targetTotalWeeks,
      weeks: allWeeks,
    ));
  }

  // ---------------------------------------------------------------------------
  // Master prompt: Jack Daniels VDOT / V.O2max (runners)
  // ---------------------------------------------------------------------------

  static const String _jackDanielsMasterPrompt = '''
You are an expert running coach applying principles from Jack Daniels' "Daniels' Running Formula" and his framework based on V.O2max (VDOT). When generating or extending training plans:

- **Easy (E) pace**: ~59–74% VDOT; conversational; most of weekly volume.
- **Marathon (M) pace**: ~75–84% VDOT; steady race effort.
- **Threshold (T) pace**: ~83–88% VDOT; ~1-hour race effort; 20–60 min sustained.
- **Interval (I) pace**: ~95–100% VDOT; 3–5 min reps; quality with recovery.
- **Repetition (R) pace**: faster than I; 2 min or less; full recovery.

Principles to follow:
- Build volume gradually; one long run per week; 2–3 key workouts per week.
- Phase structure: base (E + some T) → build (add I) → sharpening (add R) → taper.
- Recovery days between hard sessions; avoid three hard days in a row.
- Long runs progress gradually; typical taper 2–3 weeks for marathon.
- Match workout types to the goal (e.g. marathon: more M and long E; 5K: more I and R).
''';

  // ---------------------------------------------------------------------------
  // Gemini parsing
  // ---------------------------------------------------------------------------

  static const String _jsonSchema = '''
{
  "name": "string — plan name",
  "goal": "string or null — e.g. '5K', 'Half Marathon', 'General Fitness'",
  "total_weeks": "integer or null",
  "start_date": "string (YYYY-MM-DD) or null",
  "end_date": "string (YYYY-MM-DD) or null",
  "weeks": [
    {
      "week_number": 1,
      "theme": "string or null — e.g. 'Base Building', 'Speed Work', 'Taper'",
      "days": [
        {
          "day_label": "string — e.g. 'Monday', 'Day 1'",
          "workout_type": "string — e.g. 'Easy Run', 'Long Run', 'Tempo', 'Intervals', 'Rest', 'Strength', 'Cross Training', 'Race'",
          "description": "string or null — brief description of the workout",
          "target_distance_km": "number or null",
          "target_duration_minutes": "integer or null",
          "target_pace": "string or null — e.g. '5:30 /km', 'easy', 'Zone 2'",
          "notes": "string or null — any additional instructions"
        }
      ]
    }
  ]
}''';

  static const String _parsingInstruction = '''
You are a training plan parser. Extract the structured training schedule from the provided content and return it as a single valid JSON object exactly matching this schema:

$_jsonSchema

Rules:
- Infer workout types from context (e.g. "jog" → "Easy Run", "lift" or "gym" → "Strength", "swim/bike" → "Cross Training").
- If the plan has no explicit weeks (e.g. it is a flat list of days), group days into weeks of 7.
- Convert all distances to kilometres. Convert miles to km (1 mile = 1.609 km).
- If a date range is mentioned, populate start_date and end_date.
- If the file has multiple plans or variants, extract only the primary/main plan.
- Your response MUST be a single JSON object only. No markdown fences, no extra text.
''';

  Future<TrainingPlan> _parseTextContent(String text) async {
    final prompt = '$_parsingInstruction\n\n--- TRAINING PLAN CONTENT ---\n$text';
    final response =
        await _model.generateContent([Content.text(prompt)]);
    return _buildPlanFromResponse(response.text);
  }

  Future<TrainingPlan> _parseMultimodal(
      Uint8List bytes, String mimeType) async {
    final response = await _model.generateContent([
      Content.multi([
        TextPart(_parsingInstruction),
        DataPart(mimeType, bytes),
      ]),
    ]);
    return _buildPlanFromResponse(response.text);
  }

  TrainingPlan _buildPlanFromResponse(String? rawResponse) {
    if (rawResponse == null || rawResponse.isEmpty) {
      throw const FormatException(
          'Gemini returned an empty response. The file may not contain a recognisable training plan.');
    }
    final cleaned = rawResponse
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    late Map<String, dynamic> planJson;
    try {
      planJson = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('TrainingPlanService: Failed to decode JSON:\n$cleaned');
      throw FormatException(
          'Could not understand the file as a training plan. Please check the file contains a structured schedule.');
    }
    planJson['source'] = 'upload';
    planJson['created_at'] = DateTime.now().millisecondsSinceEpoch;
    return TrainingPlan.fromJson(planJson);
  }

  Future<List<TrainingWeek>> _generateWeeks({
    required TrainingPlan existingPlan,
    required int startWeekNumber,
    required int count,
  }) async {
    final existingSummary = _summariseWeeksForPrompt(existingPlan);
    final prompt = '''
$_jackDanielsMasterPrompt

The user has a training plan with goal: ${existingPlan.goal ?? 'General'}.
Existing plan has ${existingPlan.weeks.length} weeks. Here is the structure of the last 2 weeks (for continuity):

$existingSummary

Generate exactly $count additional week(s), starting at week number $startWeekNumber.
Return a JSON array of week objects. Each week must match this schema:
{
  "week_number": integer,
  "theme": "string or null",
  "days": [
    {
      "day_label": "Monday" | "Tuesday" | ... | "Sunday",
      "workout_type": "Easy Run" | "Long Run" | "Tempo" | "Intervals" | "Rest" | "Strength" | "Cross Training" | "Race" | etc.,
      "description": "string or null",
      "target_distance_km": number or null,
      "target_duration_minutes": integer or null,
      "target_pace": "string or null",
      "notes": "string or null"
    }
  ]
}

- Use 7 days per week with day_label Monday through Sunday.
- Follow the same mix of workout types as the existing plan; progress logically (e.g. if building toward a race, add appropriate taper or intensity).
- Your response MUST be only the JSON array, no markdown fences or extra text.
''';
    final response = await _model.generateContent([Content.text(prompt)]);
    final raw = response.text;
    if (raw == null || raw.isEmpty) {
      throw const FormatException('AI did not return generated weeks.');
    }
    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    try {
      final list = jsonDecode(cleaned) as List<dynamic>;
      return list
          .map((e) => TrainingWeek.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('TrainingPlanService: Failed to decode generated weeks:\n$cleaned');
      throw FormatException('Could not parse generated weeks. Please try again.');
    }
  }

  String _summariseWeeksForPrompt(TrainingPlan plan) {
    final buffer = StringBuffer();
    final lastTwo = plan.weeks.length >= 2
        ? plan.weeks.sublist(plan.weeks.length - 2)
        : plan.weeks;
    for (final w in lastTwo) {
      buffer.writeln('Week ${w.weekNumber}${w.theme != null ? ' (${w.theme})' : ''}:');
      for (final d in w.days) {
        buffer.writeln('  ${d.dayLabel}: ${d.workoutType}'
            '${d.targetDistanceKm != null ? ' ${d.targetDistanceKm!.toStringAsFixed(1)} km' : ''}'
            '${d.targetDurationMinutes != null ? ' ${d.targetDurationMinutes} min' : ''}');
      }
    }
    return buffer.toString();
  }

  void _ensureGeminiConfigured() {
    if (_geminiApiKey.isEmpty) {
      throw StateError(
        'AI training-plan features are not configured for this build. '
        'Set GEMINI_API_KEY using --dart-define or route AI calls through a secure backend.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Prompt formatting (used by PromptService)
  // ---------------------------------------------------------------------------

  /// Returns a compact training plan summary for the AI coach prompt.
  /// Includes the current week and the next week (if available).
  String formatForCoachPrompt(TrainingPlan plan) {
    final buffer = StringBuffer();
    buffer.writeln('Training Plan: ${plan.name}');
    if (plan.goal != null) buffer.writeln('Goal: ${plan.goal}');
    if (plan.totalWeeks != null) {
      buffer.writeln('Total Weeks: ${plan.totalWeeks}');
    }

    final currentWeek = plan.currentWeek;
    if (currentWeek == null) return buffer.toString();

    buffer.writeln('');
    _appendWeek(buffer, currentWeek, label: 'Current Week');

    final nextIndex = plan.weeks.indexOf(currentWeek) + 1;
    if (nextIndex < plan.weeks.length) {
      buffer.writeln('');
      _appendWeek(buffer, plan.weeks[nextIndex], label: 'Next Week (Preview)');
    }

    return buffer.toString();
  }

  void _appendWeek(StringBuffer buffer, TrainingWeek week,
      {required String label}) {
    final theme = week.theme != null ? ' — ${week.theme}' : '';
    buffer.writeln('$label (Week ${week.weekNumber}$theme):');
    for (final day in week.days) {
      final parts = <String>[day.dayLabel, day.workoutType];
      if (day.targetDistanceKm != null) {
        parts.add('${day.targetDistanceKm!.toStringAsFixed(1)} km');
      }
      if (day.targetDurationMinutes != null) {
        parts.add('${day.targetDurationMinutes} min');
      }
      if (day.targetPace != null) parts.add(day.targetPace!);
      buffer.writeln('  ${parts.join(' · ')}');
      if (day.notes != null) buffer.writeln('    ↳ ${day.notes}');
    }
  }
}

/// Thrown when device storage is full (e.g. SQLite disk I/O error).
class StorageFullException implements Exception {
  @override
  String toString() =>
      'Device storage is full. Free space or archive/delete old plans to continue.';
}
