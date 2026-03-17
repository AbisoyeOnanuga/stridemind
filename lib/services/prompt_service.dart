import 'package:stridemind/models/gear.dart';
import 'package:stridemind/models/nutrition_plan.dart';
import 'package:stridemind/models/runner_profile.dart';
import 'package:stridemind/models/strava_activity.dart' as strava_models;
import 'package:stridemind/models/training_plan.dart';
import 'package:stridemind/services/nutrition_plan_service.dart';
import 'package:stridemind/services/training_plan_service.dart';

class PromptService {
  String buildFeedbackPrompt(
      String dailyLog,
      List<strava_models.StravaActivity> activities,
      List<Map<String, dynamic>> history, {
      strava_models.StravaActivity? selectedContextActivity,
      TrainingPlan? trainingPlan,
      NutritionPlan? nutritionPlan,
      List<Gear>? gearList,
      RunnerProfile? runnerProfile,
      String? planHistorySummary}) {
    final bool isRestDay = activities.isEmpty;
    final workoutContext = isRestDay && selectedContextActivity != null
        ? _formatSingleActivityContext(selectedContextActivity, gearList: gearList)
        : _formatWorkoutContext(activities, gearList: gearList);
    final historyContext = _formatHistoryContext(history);
    final workoutHeader = isRestDay && selectedContextActivity != null
        ? 'Past Workout the User Wants to Discuss (not today\'s session)'
        : 'Today\'s Workout Data';

    final trainingPlanSection = trainingPlan != null
        ? '\n**Active Training Plan:**\n${TrainingPlanService().formatForCoachPrompt(trainingPlan)}'
        : '';
    final nutritionSection = nutritionPlan != null
        ? '\n**Active Nutrition Plan:**\n${NutritionPlanService().formatForCoachPrompt(nutritionPlan)}'
        : '';
    final runnerProfileSection = runnerProfile != null && !runnerProfile.isEmpty
        ? '\n**Runner profile (use to tailor advice):** target ${runnerProfile.targetGoal ?? "—"}; event ${runnerProfile.targetEventName ?? "—"}; target date ${runnerProfile.targetDate ?? "—"}; target goal time ${runnerProfile.targetGoalTime ?? "—"}; 5K ${runnerProfile.raceTime5k ?? "—"}; 10K ${runnerProfile.raceTime10k ?? "—"}; HM ${runnerProfile.raceTimeHalfMarathon ?? "—"}; M ${runnerProfile.raceTimeMarathon ?? "—"}; experience ${runnerProfile.experienceLevel ?? "—"}; notes: ${runnerProfile.notes ?? "—"}'
        : '';
    final planHistorySection = (planHistorySummary != null && planHistorySummary.isNotEmpty)
        ? '\n**Training plan history (non-archived; use for context e.g. past completed plans):**\n$planHistorySummary'
        : '';

    return """
You are an expert running and fitness coach named StrideMind. Your goal is to provide supportive, actionable, and personalized feedback as a structured JSON object designed for a mobile app screen.

**Your Persona & Tone:**
- You are encouraging, knowledgeable, and concise.
- You coach runners and other athletes, including those doing strength training, cross-training, and rehabilitation.

**JSON Output Schema & Formatting Rules:**
Your entire response MUST be a single, valid JSON object. Do not include any text outside of the JSON structure.
The root object must have a "feedback" key, which is an array of section objects.

Valid section types are:
1.  `"type": "heading"`: For a main section title and paragraph.
    - `"content"`: An object with a `"title"` (string, e.g., "🛌 Recovery") and `"text"` (string). The text should be concise. You can use simple markdown for **bolding** and bullet points (`- ` or `* `).

2.  `"type": "table"`: For structured data like a workout plan or decision matrix.
    - **IMPORTANT**: Tables must be for mobile screens. Use a maximum of 3 columns. Keep cell content very short. Use abbreviations if necessary.
    - `"content"`: An object with a `"title"` (string), `"headers"` (an array of strings), and `"rows"` (an array of arrays of strings).

3.  `"type": "bold_text"`: To emphasize a key takeaway or summary.
    - `"content"`: A single, impactful string.

**Analysis Guidelines:**
- Analyze the current data in the context of the conversation history. Note trends, improvements, or recurring issues (e.g., "I see you mentioned knee pain last week as well...").
- For running activities: look for patterns in pace, heart rate, and cadence. A significant pace drop on later splits may indicate fatigue.
- For strength or cross-training activities: focus on effort level, recovery needs, and how it fits the overall training load.
- On rest days or injury days: be empathetic, focus on recovery, and offer constructive guidance without pressure.

**Content Generation Rules:**
- Create at least three 'heading' sections appropriate to the context (e.g., Recovery, Adjustments, Encouragement).
- If the user is injured or on a rest day, tailor sections to rehabilitation, active recovery, and mental resilience.
- If a training plan is provided, reference it: check if today's workout matches the plan, note if the user is ahead/behind, and adjust upcoming suggestions to align with the plan.
- If a nutrition plan is provided, reference it when relevant: e.g. suggest pre/post-workout fuelling aligned to the plan, flag recovery nutrition, or note if today's guidelines support the training load.
- If a runner profile is provided (goals, race times, experience), use it to tailor advice (e.g. pace suggestions from known times, event-specific tips).
- If suggesting a workout plan, a 'table' is a good option, but you MUST follow the mobile screen constraints.
- Use a 'bold_text' section for a final, single-sentence motivational summary.

---
**CONVERSATION HISTORY (Most recent first):**
$historyContext
---
**CONTEXT FOR YOUR RESPONSE**

**Today's Runner's Log:**
"$dailyLog"

**$workoutHeader:**
$workoutContext
$trainingPlanSection
$nutritionSection
$planHistorySection
$runnerProfileSection
---

Now, generate the feedback as a single, valid JSON object based on the context above, following all schema, formatting, and content rules.
""";
  }

  String _formatHistoryContext(List<Map<String, dynamic>> history) {
    if (history.isEmpty) {
      return "No previous conversations. This is the first interaction.";
    }
    final buffer = StringBuffer();
    // Show the last 3 interactions to keep the prompt focused and within token limits.
    final recentHistory =
        history.length > 3 ? history.sublist(history.length - 3) : history;

    for (var i = 0; i < recentHistory.length; i++) {
      final turn = recentHistory[i];
      final log = turn['log'];
      // For now, we'll just include the user's previous log to give the AI context.
      // A more advanced version could summarize the AI's previous response.
      buffer.writeln("--- Previous Interaction ${i + 1} ---");
      buffer.writeln("User's Log: \"$log\"");
    }
    return buffer.toString();
  }

  String _formatWorkoutContext(List<strava_models.StravaActivity> activities,
      {List<Gear>? gearList}) {
    if (activities.isEmpty) {
      return "No workouts logged today. The user did not record any activity.";
    }

    final buffer = StringBuffer();
    for (final activity in activities) {
      buffer.write(_formatActivityDetails(activity, gearList: gearList));
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _formatSingleActivityContext(strava_models.StravaActivity activity,
      {List<Gear>? gearList}) {
    final buffer = StringBuffer();
    buffer.writeln(
        "Note: The user is discussing a past session, not today's workout.");
    buffer.writeln(
        "When no workout is logged today, the following context is the user's most recent (or selected) session; use it to give relevant feedback.");
    buffer.writeln(
        "Date: ${activity.startDateLocal.day}/${activity.startDateLocal.month}/${activity.startDateLocal.year}");
    buffer.write(_formatActivityDetails(activity, gearList: gearList));
    return buffer.toString();
  }

  String _formatActivityDetails(strava_models.StravaActivity activity,
      {List<Gear>? gearList}) {
    final buffer = StringBuffer();
    buffer.writeln("Activity: ${activity.name} (${activity.type})");

    if (activity.distance > 0) {
      buffer.writeln("Distance: ${_formatDistance(activity.distance)}");
    }
    buffer.writeln("Moving Time: ${_formatDuration(activity.movingTime)}");

    if (activity.gearId != null && gearList != null) {
      final gearMatch =
          gearList.where((g) => g.stravaGearId == activity.gearId);
      if (gearMatch.isNotEmpty) {
        buffer.writeln("Gear (shoes/bike): ${gearMatch.first.displayName}");
      }
    }

    if (activity.totalElevationGain > 0) {
      buffer.writeln(
          "Elevation Gain: ${activity.totalElevationGain.toStringAsFixed(0)} m");
    }

    if (activity.averageHeartrate != null) {
      buffer.writeln(
          "Average Heart Rate: ${activity.averageHeartrate!.toStringAsFixed(0)} bpm");
    }

    if (activity.sufferScore != null && activity.sufferScore! > 0) {
      buffer.writeln("Suffer Score: ${activity.sufferScore}");
    }

    if (activity.description != null && activity.description!.isNotEmpty) {
      buffer.writeln("Notes: ${activity.description}");
    }

    final isRun = activity.type.toLowerCase() == 'run';
    if (isRun && activity.averageSpeed != null && activity.averageSpeed! > 0) {
      buffer
          .writeln("Average Pace: ${_formatPace(activity.averageSpeed!)} /km");
    }

    if (isRun && activity.averageCadence != null) {
      buffer.writeln(
          "Average Cadence: ${(activity.averageCadence! * 2).toStringAsFixed(0)} spm");
    }

    final canonical = activity.canonicalSegments;
    if (isRun && canonical.isNotEmpty) {
      final kmSplits = canonical
          .where((s) => (s.distance - 1000.0).abs() < 5.0)
          .toList();
      if (kmSplits.isNotEmpty) {
        final csv = kmSplits.map((s) => _formatPace(s.averageSpeed)).join(',');
        buffer.writeln("Splits (${kmSplits.length} km, mm:ss/km CSV): $csv");
        buffer.writeln(_computeSplitStats(kmSplits));
      }
    }

    return buffer.toString();
  }

  String _computeSplitStats(List<strava_models.Split> splits) {
    if (splits.isEmpty) return '';

    // Overall average speed (weighted by distance is unnecessary since all are ~1km)
    final avgSpeed =
        splits.map((s) => s.averageSpeed).reduce((a, b) => a + b) /
            splits.length;

    // First-half / second-half averages
    final mid = splits.length ~/ 2;
    final firstHalf = splits.sublist(0, mid.clamp(1, splits.length));
    final secondHalf = splits.sublist(mid.clamp(0, splits.length));
    final firstAvg =
        firstHalf.map((s) => s.averageSpeed).reduce((a, b) => a + b) /
            firstHalf.length;
    final secondAvg =
        secondHalf.map((s) => s.averageSpeed).reduce((a, b) => a + b) /
            secondHalf.length;

    // Fastest and slowest by speed
    final fastest = splits.reduce((a, b) => a.averageSpeed > b.averageSpeed ? a : b);
    final slowest = splits.reduce((a, b) => a.averageSpeed < b.averageSpeed ? a : b);
    final fastestIdx = splits.indexOf(fastest) + 1;
    final slowestIdx = splits.indexOf(slowest) + 1;

    // Pacing trend: compare second-half avg pace to first-half avg pace
    // secondsPerKm = 1000 / speed; higher = slower pace
    final firstPaceSec = 1000 / firstAvg;
    final secondPaceSec = 1000 / secondAvg;
    final diffSec = (secondPaceSec - firstPaceSec).round();
    String trend;
    if (diffSec > 10) {
      trend = 'positive split — second half +${diffSec}s/km slower';
    } else if (diffSec < -10) {
      trend = 'negative split — second half ${(-diffSec)}s/km faster';
    } else {
      trend = 'even pacing';
    }

    return 'Pacing: avg ${_formatPace(avgSpeed)}/km'
        ' | first ${firstHalf.length} km avg ${_formatPace(firstAvg)}'
        ' | last ${secondHalf.length} km avg ${_formatPace(secondAvg)}'
        ' | fastest km $fastestIdx (${_formatPace(fastest.averageSpeed)})'
        ' | slowest km $slowestIdx (${_formatPace(slowest.averageSpeed)})'
        ' | $trend';
  }

  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)} m';
    }
    return '${(distanceInMeters / 1000).toStringAsFixed(2)} km';
  }

  String _formatPace(double speedInMps) {
    if (speedInMps <= 0) return 'N/A';
    final secondsPerKm = 1000 / speedInMps;
    final pace = Duration(seconds: secondsPerKm.round());
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(pace.inMinutes.remainder(60));
    final seconds = twoDigits(pace.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final secs = twoDigits(duration.inSeconds.remainder(60));

    if (hours > 0) {
      return "$hours:$minutes:$secs";
    }
    return "$minutes:$secs min";
  }
}