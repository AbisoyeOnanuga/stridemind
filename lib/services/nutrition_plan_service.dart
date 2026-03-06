import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:stridemind/models/nutrition_plan.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/utils/plan_file_reader.dart';

class NutritionPlanService {
  final DatabaseService _db = DatabaseService();
  late final GenerativeModel _model;
  static const String _geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  NutritionPlanService()
      : _model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: _geminiApiKey,
        );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<NutritionPlan> parseFile(Uint8List bytes, String extension) async {
    _ensureGeminiConfigured();
    if (!PlanFileReader.isSupported(extension)) {
      throw UnsupportedError('File type .$extension is not supported.');
    }
    final text = PlanFileReader.extractText(bytes, extension);
    if (text != null) return _parseTextContent(text);
    final mime = PlanFileReader.mimeType(extension)!;
    return _parseMultimodal(bytes, mime);
  }

  Future<void> savePlan(NutritionPlan plan) => _db.saveNutritionPlan(_normalisePlan(plan));
  Future<NutritionPlan?> getActivePlan() async {
    final plan = await _db.getActiveNutritionPlan();
    if (plan == null) return null;
    return _normalisePlan(plan);
  }
  Future<void> deleteActivePlan() => _db.deleteActiveNutritionPlan();

  /// Generates a new day template (e.g. "Rest Day", "Race Day") consistent with
  /// the plan, using evidence-based sports nutrition principles.
  Future<NutritionDay> generateDayTemplate(
    NutritionPlan plan,
    String dayLabel,
  ) async {
    _ensureGeminiConfigured();
    final prompt = '''
$_nutritionMasterPrompt

The user's nutrition plan: "${plan.name}". Goal: ${plan.goal ?? 'General'}.
Daily targets: ${plan.dailyTargetSummary.isEmpty ? 'Not set' : plan.dailyTargetSummary}

Generate a single day template for "$dayLabel" that fits this plan.
Return a JSON object matching this schema only (no markdown, no extra text):
{
  "day_label": "string",
  "total_calories": integer or null,
  "total_protein_g": number or null,
  "total_carbs_g": number or null,
  "total_fat_g": number or null,
  "meals": [
    {
      "name": "string",
      "description": "string or null",
      "calories": integer or null,
      "protein_g": number or null,
      "carbs_g": number or null,
      "fat_g": number or null,
      "timing": "string or null",
      "foods": ["string"],
      "notes": "string or null"
    }
  ],
  "notes": "string or null"
}
''';
    final response = await _model.generateContent([Content.text(prompt)]);
    final raw = response.text;
    if (raw == null || raw.isEmpty) {
      throw const FormatException('AI did not return a day template.');
    }
    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    try {
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      return NutritionDay.fromJson(map);
    } catch (e) {
      debugPrint('NutritionPlanService: Failed to decode day:\n$cleaned');
      throw FormatException('Could not parse generated day. Please try again.');
    }
  }

  void _ensureGeminiConfigured() {
    if (_geminiApiKey.isEmpty) {
      throw StateError(
        'AI nutrition features are not configured for this build. '
        'Set GEMINI_API_KEY using --dart-define or route AI calls through a secure backend.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Master prompt: evidence-based sports nutrition (reputable/academic)
  // ---------------------------------------------------------------------------

  static const String _nutritionMasterPrompt = '''
You are an expert sports dietitian. When generating or extending nutrition plans, apply evidence-based principles from established sources (e.g. ACSM/AND joint position stands, ISSN, sports nutrition textbooks):

- **Energy availability**: Support training load; avoid low energy availability in athletes.
- **Macronutrients**: Protein ~1.2–2.0 g/kg for athletes; carbs 3–12 g/kg depending on load; fat 20–35% of energy.
- **Timing**: Carbohydrate and protein around sessions (pre, during if long, post) for performance and recovery.
- **Hydration**: Encourage fluid and electrolytes with activity.
- **Recovery**: Post-exercise window (e.g. 0.5–2 h) for protein and carbs when relevant.
- **Race/training day**: Align intake with load (e.g. higher carbs on hard days, adequate protein daily).
- **Rest day**: Slightly lower energy/carbs if appropriate; maintain protein for adaptation.
''';

  // ---------------------------------------------------------------------------
  // Gemini parsing
  // ---------------------------------------------------------------------------

  static const String _jsonSchema = r'''
{
  "name": "string — plan name",
  "goal": "string or null — e.g. 'Performance', 'Weight Loss', 'Muscle Gain', 'Race Prep'",
  "daily_calorie_target": "integer or null",
  "daily_protein_target_g": "number or null",
  "daily_carbs_target_g": "number or null",
  "daily_fat_target_g": "number or null",
  "general_guidelines": "string or null — key rules/principles of the plan",
  "days": [
    {
      "day_label": "string — e.g. 'Monday', 'Training Day', 'Race Day', 'Rest Day'",
      "total_calories": "integer or null",
      "total_protein_g": "number or null",
      "total_carbs_g": "number or null",
      "total_fat_g": "number or null",
      "meals": [
        {
          "name": "string — e.g. 'Breakfast', 'Pre-Run Snack', 'Post-Workout', 'Lunch', 'Dinner'",
          "description": "string or null",
          "calories": "integer or null",
          "protein_g": "number or null",
          "carbs_g": "number or null",
          "fat_g": "number or null",
          "timing": "string or null — e.g. '30 min before run', '7:00 AM'",
          "foods": ["list of food items with portions, e.g. 'Oatmeal 80g', 'Banana 1 medium'"],
          "notes": "string or null"
        }
      ],
      "notes": "string or null"
    }
  ]
}''';

  static const String _parsingInstruction = '''
You are a sports nutrition plan parser. Extract the structured nutrition schedule from the provided content and return it as a single valid JSON object exactly matching this schema:

$_jsonSchema

Rules:
- If the plan has a single template day (not day-specific), create one day labelled "Daily Template".
- If days are labelled by type (Training Day / Rest Day / Race Day), use those labels.
- If days are labelled by weekday, use Monday–Sunday.
- Extract all macro targets (protein, carbs, fat in grams). Convert oz to grams (1 oz = 28.35 g).
- Extract timing information for pre/post-workout meals where available.
- If foods are listed, include them as an array of strings with quantities.
- Your response MUST be a single JSON object only. No markdown fences, no extra text.
''';

  Future<NutritionPlan> _parseTextContent(String text) async {
    final prompt =
        '$_parsingInstruction\n\n--- NUTRITION PLAN CONTENT ---\n$text';
    final response = await _model.generateContent([Content.text(prompt)]);
    return _buildPlanFromResponse(response.text);
  }

  Future<NutritionPlan> _parseMultimodal(
      Uint8List bytes, String mimeType) async {
    final response = await _model.generateContent([
      Content.multi([
        TextPart(_parsingInstruction),
        DataPart(mimeType, bytes),
      ]),
    ]);
    return _buildPlanFromResponse(response.text);
  }

  NutritionPlan _buildPlanFromResponse(String? rawResponse) {
    if (rawResponse == null || rawResponse.isEmpty) {
      throw const FormatException(
          'Gemini returned an empty response. The file may not contain a recognisable nutrition plan.');
    }
    final cleaned =
        rawResponse.replaceAll('```json', '').replaceAll('```', '').trim();
    late Map<String, dynamic> planJson;
    try {
      planJson = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('NutritionPlanService: Failed to decode JSON:\n$cleaned');
      throw const FormatException(
          'Could not understand the file as a nutrition plan. Please check the file contains a structured meal schedule.');
    }
    planJson['source'] = 'upload';
    planJson['created_at'] = DateTime.now().millisecondsSinceEpoch;
    return _normalisePlan(NutritionPlan.fromJson(planJson));
  }

  NutritionPlan _normalisePlan(NutritionPlan plan) {
    final byWeekday = <String, NutritionDay>{};
    final extraDays = <NutritionDay>[];
    for (final day in plan.days) {
      final matched = _weekdayFromLabel(day.dayLabel);
      if (matched != null) {
        byWeekday[matched] = day.copyWith(dayLabel: matched);
      } else {
        extraDays.add(day);
      }
    }

    // Fill missing weekdays from extra templates where possible.
    final extrasQueue = List<NutritionDay>.from(extraDays);
    final ordered = <NutritionDay>[];
    for (final weekday in _weekdays) {
      if (byWeekday.containsKey(weekday)) {
        ordered.add(byWeekday[weekday]!);
        continue;
      }
      if (extrasQueue.isNotEmpty) {
        final seeded = extrasQueue.removeAt(0).copyWith(dayLabel: weekday);
        ordered.add(seeded);
      } else {
        ordered.add(
          NutritionDay(
            dayLabel: weekday,
            meals: const [],
            notes:
                'No template found in upload. Use "Regenerate day template" to build this day with AI.',
          ),
        );
      }
    }

    return plan.copyWith(days: ordered);
  }

  String? _weekdayFromLabel(String label) {
    final normalized = label.trim().toLowerCase();
    for (final weekday in _weekdays) {
      if (normalized == weekday.toLowerCase() ||
          normalized.contains(weekday.toLowerCase().substring(0, 3))) {
        return weekday;
      }
    }
    if (normalized.startsWith('mon')) return 'Monday';
    if (normalized.startsWith('tue')) return 'Tuesday';
    if (normalized.startsWith('wed')) return 'Wednesday';
    if (normalized.startsWith('thu')) return 'Thursday';
    if (normalized.startsWith('fri')) return 'Friday';
    if (normalized.startsWith('sat')) return 'Saturday';
    if (normalized.startsWith('sun')) return 'Sunday';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Prompt formatting
  // ---------------------------------------------------------------------------

  String formatForCoachPrompt(NutritionPlan plan) {
    final buffer = StringBuffer();
    buffer.writeln('Nutrition Plan: ${plan.name}');
    if (plan.goal != null) buffer.writeln('Goal: ${plan.goal}');

    final targets = plan.dailyTargetSummary;
    if (targets.isNotEmpty) buffer.writeln('Daily Targets: $targets');

    if (plan.generalGuidelines != null) {
      buffer.writeln('Guidelines: ${plan.generalGuidelines}');
    }

    final today = plan.todayTemplate;
    if (today != null) {
      buffer.writeln('');
      buffer.writeln("Today's Nutrition Template (${today.dayLabel}):");
      final dayMacros = today.macroSummary;
      if (dayMacros.isNotEmpty) buffer.writeln('  Total: $dayMacros');
      for (final meal in today.meals) {
        final parts = <String>[meal.name];
        if (meal.timing != null) parts.add(meal.timing!);
        final macros = meal.macroSummary;
        if (macros.isNotEmpty) parts.add(macros);
        buffer.writeln('  • ${parts.join(' | ')}');
        if (meal.foods != null && meal.foods!.isNotEmpty) {
          buffer.writeln('    Foods: ${meal.foods!.join(', ')}');
        }
        if (meal.notes != null) buffer.writeln('    ↳ ${meal.notes}');
      }
    }

    return buffer.toString();
  }
}
