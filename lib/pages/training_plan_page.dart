import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stridemind/models/training_plan.dart';
import 'package:stridemind/services/training_plan_service.dart';

class TrainingPlanPage extends StatefulWidget {
  const TrainingPlanPage({super.key});

  @override
  State<TrainingPlanPage> createState() => _TrainingPlanPageState();
}

const String _prefIncludeRestInCount = 'training_plan_include_rest_in_count';

const List<String> _workoutTypeOptions = [
  'Easy Run', 'Long Run', 'Tempo', 'Intervals', 'Rest',
  'Cross-training', 'Strength', 'Other',
];
const List<String> _paceOptions = ['Easy', 'Marathon', 'Half marathon', '10K', '5K', 'Custom'];

/// Standard pace options for custom pace dropdown (min/km). Includes elite paces under 3:00. Prevents typos and matches app conventions.
List<String> get _customPaceOptions {
  const fromMin = 2;
  const toMin = 10;
  final list = <String>[];
  for (int m = fromMin; m <= toMin; m++) {
    for (int s = 0; s < 60; s += 15) {
      if (m == toMin && s > 0) break;
      list.add('$m:${s.toString().padLeft(2, '0')} /km');
    }
  }
  return list;
}

bool _isRestType(String type) =>
    type.toLowerCase().contains('rest');
bool _isPaceRelevantType(String type) =>
    !_isRestType(type) && type != 'Cross-training' && type != 'Strength';

class _TrainingPlanPageState extends State<TrainingPlanPage> {
  final _service = TrainingPlanService();
  TrainingPlan? _activePlan;
  bool _isLoading = true;
  bool _isParsing = false;
  String? _parsingStatus;
  bool _includeRestInCount = true;
  bool _showStorageWarning = false;

  @override
  void initState() {
    super.initState();
    _loadActivePlan();
    _loadIncludeRestPreference();
    _loadPlanCount();
  }

  Future<void> _loadPlanCount() async {
    final count = await _service.getPlanCount();
    if (mounted) {
      setState(() {
        _showStorageWarning = _service.shouldShowStorageWarning(count);
      });
    }
  }

  Future<void> _loadIncludeRestPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _includeRestInCount = prefs.getBool(_prefIncludeRestInCount) ?? true);
  }

  Future<void> _loadActivePlan() async {
    setState(() => _isLoading = true);
    final plan = await _service.getActivePlan();
    if (mounted) setState(() { _activePlan = plan; _isLoading = false; });
  }

  Future<void> _pickAndParsePlan() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf', 'txt', 'csv', 'xlsx', 'docx',
          'jpg', 'jpeg', 'png', 'webp', 'heic',
        ],
        withData: true,
      );
    } catch (e) {
      _showError('Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      _showError('Could not read file data. Please try again.');
      return;
    }

    final extension = (file.extension ?? '').toLowerCase();

    setState(() {
      _isParsing = true;
      _parsingStatus = 'Reading ${file.name}…';
    });

    try {
      setState(() => _parsingStatus = 'Analysing with AI… (this may take 10–30 s)');
      final plan = await _service.parseFile(file.bytes!, extension);

      setState(() => _parsingStatus = 'Saving plan…');
      await _service.savePlan(plan);

      if (mounted) {
        setState(() {
          _activePlan = plan;
          _isParsing = false;
          _parsingStatus = null;
        });
        _loadPlanCount();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan "${plan.name}" saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isParsing = false; _parsingStatus = null; });
        _showError(_friendlyError(e, fallback: e.toString()));
      }
    }
  }

  Future<void> _openPlanHistory() async {
    final activeChanged = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (ctx) => _PlanHistoryPage(service: _service),
      ),
    );
    if (activeChanged == true && mounted) {
      _loadActivePlan();
      _loadPlanCount();
    }
  }

  Future<void> _deletePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Training Plan'),
        content: const Text(
            'This will remove the active training plan from the AI coach context. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deleteActivePlan();
    if (mounted) setState(() => _activePlan = null);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  bool _isNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return error is SocketException ||
        text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection closed');
  }

  String _friendlyError(Object error, {String fallback = 'Something went wrong.'}) {
    if (_isNetworkError(error)) {
      return 'No internet connection. Reconnect and try again.';
    }
    return fallback;
  }

  Future<void> _editPlanDetails(TrainingPlan plan) async {
    final result = await showDialog<TrainingPlan>(
      context: context,
      builder: (ctx) => _EditTrainingPlanDialog(plan: plan),
    );
    if (result == null || !mounted) return;
    TrainingPlan toSave = result;
    final targetWeeks = result.totalWeeks;

    if (targetWeeks != null && targetWeeks > result.weeks.length) {
      final generate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update plan with more weeks?'),
          content: Text(
            'The plan has ${result.weeks.length} weeks but you set duration to $targetWeeks weeks. '
            'Generate ${targetWeeks - result.weeks.length} more week(s) to match?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, keep as is'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, generate'),
            ),
          ],
        ),
      );
      if (generate == true && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    'Updating plan…',
                    style: Theme.of(ctx).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        );
        try {
          toSave = await _service.extendPlan(result, targetWeeks);
        } catch (e) {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_friendlyError(e, fallback: 'Could not generate weeks.')),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    } else if (targetWeeks != null && targetWeeks < result.weeks.length) {
      toSave = result.copyWith(
        totalWeeks: targetWeeks,
        weeks: result.weeks.take(targetWeeks).toList(),
      );
    }

    await _service.updateActivePlan(toSave);
    if (mounted) {
      setState(() => _activePlan = toSave);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan updated'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _editWeek(TrainingPlan plan, int weekIndex) async {
    final week = plan.weeks[weekIndex];
    final result = await showDialog<TrainingWeek>(
      context: context,
      builder: (ctx) => _EditTrainingWeekDialog(week: week),
    );
    if (result != null && mounted && _activePlan != null) {
      final newWeeks = List<TrainingWeek>.from(plan.weeks)..[weekIndex] = result;
      final updated = plan.copyWith(weeks: newWeeks);
      await _service.updateActivePlan(updated);
      setState(() => _activePlan = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Week updated'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _editDay(TrainingPlan plan, int weekIndex, int dayIndex) async {
    final day = plan.weeks[weekIndex].days[dayIndex];
    final result = await showDialog<TrainingDay>(
      context: context,
      builder: (ctx) => _EditTrainingDayDialog(day: day),
    );
    if (result != null && mounted && _activePlan != null) {
      final newDays = List<TrainingDay>.from(plan.weeks[weekIndex].days)..[dayIndex] = result;
      final newWeek = plan.weeks[weekIndex].copyWith(days: newDays);
      final newWeeks = List<TrainingWeek>.from(plan.weeks)..[weekIndex] = newWeek;
      final updated = plan.copyWith(weeks: newWeeks);
      await _service.updateActivePlan(updated);
      setState(() => _activePlan = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Day updated'), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Plan history',
            onPressed: _isParsing ? null : _openPlanHistory,
          ),
          if (_activePlan != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit plan details',
              onPressed: _isParsing ? null : () => _editPlanDetails(_activePlan!),
            ),
          if (_activePlan != null)
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Replace plan',
              onPressed: _isParsing ? null : _pickAndParsePlan,
            ),
          if (_activePlan != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove plan',
              onPressed: _isParsing ? null : _deletePlan,
            ),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showStorageWarning)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'You have many plans. Archive old ones in Plan history to free space.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _showStorageWarning = false),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _isParsing
                    ? _buildParsingState()
                    : _activePlan == null
                        ? _buildEmptyState()
                        : _buildPlanView(_activePlan!),
          ),
        ],
      ),
    );
  }

  Widget _buildParsingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _parsingStatus ?? 'Processing…',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'StrideMind is reading your plan with AI.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note,
                size: 72, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 24),
            Text('No Training Plan Yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Upload your training plan and StrideMind will structure it automatically. '
              'The AI coach will then use it as context for personalised feedback.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Supported formats: PDF · Image (JPG, PNG) · Word (.docx) · Excel (.xlsx) · Text (.txt, .csv)',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _pickAndParsePlan,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Training Plan'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14)),
            ),
            const SizedBox(height: 16),
            _buildStravaNote(),
          ],
        ),
      ),
    );
  }

  Widget _buildStravaNote() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Strava\'s training plan API is not publicly available. '
              'To use a Strava or Runna plan, export or screenshot it and upload here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanView(TrainingPlan plan) {
    final currentWeek = plan.currentWeek;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPlanHeader(plan),
        if (currentWeek != null) ...[
          const SizedBox(height: 16),
          _buildCurrentWeekBanner(currentWeek),
        ],
        const SizedBox(height: 16),
        ...plan.weeks.asMap().entries.map((e) => _buildWeekCard(
              plan,
              e.key,
              e.value,
              isCurrentWeek: e.value == currentWeek,
            )),
      ],
    );
  }

  Widget _buildPlanHeader(TrainingPlan plan) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(plan.name,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (plan.goal != null) _chip(Icons.flag, plan.goal!),
                if (plan.totalWeeks != null)
                  _chip(Icons.calendar_today, '${plan.totalWeeks} weeks'),
                if (plan.startDate != null)
                  _chip(Icons.play_arrow, 'Starts ${plan.startDate}'),
                if (plan.endDate != null)
                  _chip(Icons.sports_score, 'Ends ${plan.endDate}'),
                _chip(Icons.source, plan.source == 'upload' ? 'Uploaded' : 'Strava'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Include rest in count', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                Switch(
                  value: _includeRestInCount,
                  onChanged: (v) async {
                    setState(() => _includeRestInCount = v);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(_prefIncludeRestInCount, v);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _weekSummary(TrainingWeek week) {
    final workouts = week.days.where((d) => !d.isRest).length;
    final rest = week.days.length - workouts;
    if (_includeRestInCount) {
      return '${week.days.length} sessions · $workouts workouts';
    }
    if (rest > 0) {
      return '$workouts workouts · $rest rest';
    }
    return '$workouts workouts';
  }

  Future<void> _markWeekComplete(TrainingPlan plan, int weekIndex) async {
    final isLastWeek = weekIndex == plan.weeks.length - 1;
    if (isLastWeek) {
      final updated = plan.copyWith(
        currentWeekOverride: plan.weeks.length,
        completedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _service.updateActivePlan(updated);
      await _service.clearActivePlan();
      if (!mounted) return;
      setState(() => _activePlan = null);
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: const Text('Training plan complete'),
          content: const Text(
            "You've completed every week of this plan. Great work!\n\n"
            'The plan has been moved out of active focus and kept in Plan history. Use "Plan history" in the app bar to archive, delete, or set another plan active.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      return;
    }
    final nextWeekOneBased = (weekIndex + 2).clamp(1, plan.weeks.length);
    final updated = plan.copyWith(currentWeekOverride: nextWeekOneBased);
    await _service.updateActivePlan(updated);
    if (mounted) {
      setState(() => _activePlan = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Week ${weekIndex + 1} complete. Now on week $nextWeekOneBased.'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _markWeekIncomplete(TrainingPlan plan, int weekIndex) async {
    final prevWeekOneBased = (weekIndex).clamp(1, plan.weeks.length);
    final wasCompleted = plan.isCompleted;
    final updated = plan.copyWith(
      currentWeekOverride: prevWeekOneBased,
      clearCompletedAt: wasCompleted,
    );
    await _service.updateActivePlan(updated);
    if (mounted) {
      setState(() => _activePlan = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Back to week $prevWeekOneBased.')),
      );
    }
  }

  Widget _buildCurrentWeekBanner(TrainingWeek week) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.today, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are in Week ${week.weekNumber}'
              '${week.theme != null ? ' — ${week.theme}' : ''}',
              style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekCard(TrainingPlan plan, int weekIndex, TrainingWeek week,
      {required bool isCurrentWeek}) {
    final weekTheme = week.theme != null ? ' · ${week.theme}' : '';
    final themeData = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrentWeek
            ? BorderSide(color: themeData.colorScheme.primary, width: 1.5)
            : BorderSide(color: themeData.dividerColor.withValues(alpha: 0.6), width: 1),
      ),
      child: ExpansionTile(
        initiallyExpanded: isCurrentWeek,
        leading: CircleAvatar(
          backgroundColor: isCurrentWeek
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Text('${week.weekNumber}',
              style: TextStyle(
                  color: isCurrentWeek
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(
          'Week ${week.weekNumber}$weekTheme',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_weekSummary(week)),
            if (isCurrentWeek) ...[
              const SizedBox(height: 4),
              if (plan.isCompleted) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 18, color: themeData.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('Plan complete', style: TextStyle(color: themeData.colorScheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
                if ((plan.currentWeekOverride ?? plan.currentWeek?.weekNumber ?? 1) > 1)
                  TextButton.icon(
                    onPressed: () => _markWeekIncomplete(plan, weekIndex),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Mark incomplete'),
                  ),
              ] else ...[
                TextButton.icon(
                  onPressed: () => _markWeekComplete(plan, weekIndex),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Mark complete'),
                ),
                if ((plan.currentWeekOverride ?? plan.currentWeek?.weekNumber ?? 1) > 1)
                  TextButton.icon(
                    onPressed: () => _markWeekIncomplete(plan, weekIndex),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Mark incomplete'),
                  ),
              ],
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Edit week',
          onPressed: () => _editWeek(plan, weekIndex),
        ),
        children: week.days
            .asMap()
            .entries
            .map((e) => _buildDayTile(plan, weekIndex, e.key, e.value))
            .toList(),
      ),
    );
  }

  Widget _buildDayTile(TrainingPlan plan, int weekIndex, int dayIndex, TrainingDay day) {
    final isRest = day.isRest;
    final details = <String>[];
    if (day.targetDistanceKm != null) {
      details.add('${day.targetDistanceKm!.toStringAsFixed(1)} km');
    }
    if (day.targetDurationMinutes != null) {
      details.add('${day.targetDurationMinutes} min');
    }
    if (day.targetPace != null) details.add(day.targetPace!);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18),
        tooltip: 'Edit workout',
        onPressed: () => _editDay(plan, weekIndex, dayIndex),
      ),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isRest
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : _workoutColor(day.workoutType),
        child: Icon(
          isRest ? Icons.hotel : _workoutIcon(day.workoutType),
          size: 16,
          color: isRest
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Colors.white,
        ),
      ),
      title: Text(
        '${day.dayLabel}  ·  ${day.workoutType}',
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isRest ? Theme.of(context).colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty) Text(details.join(' · ')),
          if (day.description != null)
            Text(day.description!,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (day.notes != null)
            Text('↳ ${day.notes}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic)),
        ],
      ),
      isThreeLine: day.description != null || day.notes != null,
    );
  }

  Widget _chip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Color _workoutColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('easy')) return Colors.green;
    if (t.contains('long')) return Colors.blue;
    if (t.contains('tempo') || t.contains('threshold')) return Colors.orange;
    if (t.contains('interval') || t.contains('speed')) return Colors.red;
    if (t.contains('strength') || t.contains('gym')) return Colors.purple;
    if (t.contains('cross') || t.contains('swim') || t.contains('bike')) {
      return Colors.teal;
    }
    if (t.contains('race')) return Colors.amber.shade700;
    return Colors.blueGrey;
  }

  IconData _workoutIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('run') || t.contains('jog')) return Icons.directions_run;
    if (t.contains('strength') || t.contains('gym')) return Icons.fitness_center;
    if (t.contains('swim')) return Icons.pool;
    if (t.contains('bike') || t.contains('cycl')) return Icons.directions_bike;
    if (t.contains('race')) return Icons.flag;
    return Icons.sports;
  }
}

class _EditTrainingPlanDialog extends StatefulWidget {
  final TrainingPlan plan;

  const _EditTrainingPlanDialog({required this.plan});

  @override
  State<_EditTrainingPlanDialog> createState() => _EditTrainingPlanDialogState();
}

/// Standard race/event options for plan edit (short to longest).
const List<String> _planEventOptions = [
  'Mile', '5K', '10K', 'Half marathon', 'Marathon', '50K', '50 mile', '100K', '100 mile', 'Other',
];

/// Duration in weeks: 1–16 for training blocks.
const int _planDurationMin = 1;
const int _planDurationMax = 16;

class _EditTrainingPlanDialogState extends State<_EditTrainingPlanDialog> {
  late final TextEditingController _nameController;
  String? _goal; // from dropdown; must be in _planEventOptions or null
  late int _totalWeeks; // 1–16, set in initState
  String? _startDate;
  String? _endDate;
  int? _currentWeekOverride; // null = auto; when set must be 1.._totalWeeks

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plan.name);
    final goalStr = widget.plan.goal?.trim();
    _goal = goalStr != null && goalStr.isNotEmpty
        ? (_planEventOptions.contains(goalStr) ? goalStr : 'Other')
        : null;
    final tw = widget.plan.totalWeeks;
    final weeksLen = widget.plan.weeks.length;
    _totalWeeks = tw != null && tw >= _planDurationMin && tw <= _planDurationMax
        ? tw
        : (weeksLen < _planDurationMin ? _planDurationMin : (weeksLen > _planDurationMax ? _planDurationMax : weeksLen));
    _startDate = widget.plan.startDate?.trim().isEmpty == true ? null : widget.plan.startDate;
    _endDate = widget.plan.endDate?.trim().isEmpty == true ? null : widget.plan.endDate;
    var cw = widget.plan.currentWeekOverride;
    if (cw != null && (cw < 1 || cw > _totalWeeks)) cw = _totalWeeks;
    _currentWeekOverride = cw;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan name is required')),
      );
      return;
    }
    // Keep current week in valid range 1.._totalWeeks
    final cw = _currentWeekOverride != null && _currentWeekOverride! >= 1 && _currentWeekOverride! <= _totalWeeks
        ? _currentWeekOverride
        : (_currentWeekOverride != null ? _totalWeeks : null);

    // Validate dates: end must be on or after start
    String? startDate = _startDate?.trim().isEmpty == true ? null : _startDate?.trim();
    String? endDate = _endDate?.trim().isEmpty == true ? null : _endDate?.trim();
    if (startDate != null && endDate != null) {
      final start = DateTime.tryParse(startDate);
      final end = DateTime.tryParse(endDate);
      if (start != null && end != null && end.isBefore(start)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End date must be on or after start date')),
        );
        return;
      }
    }

    final updated = widget.plan.copyWith(
      name: name,
      goal: _goal,
      totalWeeks: _totalWeeks,
      startDate: startDate,
      endDate: endDate,
      clearCurrentWeekOverride: cw == null,
      currentWeekOverride: cw,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWeek = _totalWeeks.clamp(1, 999);
    // Only pass a week value that exists in the items list to avoid dropdown assertion
    final weekOptions = <int?>[null, ...List.generate(maxWeek, (i) => i + 1)];
    final safeCurrentWeek = _currentWeekOverride != null && _currentWeekOverride! >= 1 && _currentWeekOverride! <= maxWeek
        ? _currentWeekOverride
        : null;

    return AlertDialog(
      title: const Text('Edit plan details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Plan name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('goal-$_goal'),
              initialValue: _goal != null && _planEventOptions.contains(_goal) ? _goal : null,
              decoration: const InputDecoration(
                labelText: 'Event / goal',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Select…')),
                ..._planEventOptions.map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
              ],
              onChanged: (v) => setState(() => _goal = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('duration-$_totalWeeks'),
              initialValue: _totalWeeks.clamp(_planDurationMin, _planDurationMax),
              decoration: const InputDecoration(
                labelText: 'Duration (weeks)',
                border: OutlineInputBorder(),
              ),
              items: List.generate(_planDurationMax - _planDurationMin + 1, (i) {
                final w = i + _planDurationMin;
                return DropdownMenuItem<int>(value: w, child: Text('$w weeks'));
              }),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _totalWeeks = v;
                  if (_currentWeekOverride != null && _currentWeekOverride! > v) {
                    _currentWeekOverride = v;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Text(_startDate ?? 'Pick start date'),
              trailing: const Icon(Icons.calendar_today),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide()),
              onTap: () async {
                final now = DateTime.now();
                final initial = _startDate != null ? (DateTime.tryParse(_startDate!) ?? now) : now;
                final picked = await showDatePicker(context: context, initialDate: initial, firstDate: now.subtract(const Duration(days: 365 * 2)), lastDate: now.add(const Duration(days: 365 * 3)));
                if (picked != null && mounted) setState(() => _startDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              title: Text(_endDate ?? 'Pick end date'),
              subtitle: _startDate != null && _endDate == null
                  ? Text('Suggest: start + $_totalWeeks weeks', style: theme.textTheme.bodySmall)
                  : null,
              trailing: const Icon(Icons.calendar_today),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide()),
              onTap: () async {
                final now = DateTime.now();
                final start = _startDate != null ? DateTime.tryParse(_startDate!) : null;
                final firstDate = start ?? now;
                final initial = _endDate != null
                    ? (DateTime.tryParse(_endDate!) ?? firstDate.add(Duration(days: _totalWeeks * 7)))
                    : (start?.add(Duration(days: _totalWeeks * 7)) ?? now.add(const Duration(days: 90)));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial.isBefore(firstDate) ? firstDate : initial,
                  firstDate: firstDate,
                  lastDate: now.add(const Duration(days: 365 * 3)),
                );
                if (picked != null && mounted) setState(() => _endDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
              },
            ),
            const SizedBox(height: 16),
            Text('Which week are you in?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            DropdownButtonFormField<int?>(
              key: ValueKey('week-$safeCurrentWeek'),
              initialValue: safeCurrentWeek,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: weekOptions.map((w) => DropdownMenuItem<int?>(
                value: w,
                child: Text(w == null ? 'Auto (from start date)' : 'Week $w'),
              )).toList(),
              onChanged: (v) => setState(() => _currentWeekOverride = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditTrainingWeekDialog extends StatefulWidget {
  final TrainingWeek week;

  const _EditTrainingWeekDialog({required this.week});

  @override
  State<_EditTrainingWeekDialog> createState() => _EditTrainingWeekDialogState();
}

class _EditTrainingWeekDialogState extends State<_EditTrainingWeekDialog> {
  late final TextEditingController _themeController;

  @override
  void initState() {
    super.initState();
    _themeController = TextEditingController(text: widget.week.theme ?? '');
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  void _save() {
    final theme = _themeController.text.trim().isEmpty
        ? null
        : _themeController.text.trim();
    final updated = widget.week.copyWith(theme: theme);
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Week ${widget.week.weekNumber}'),
      content: TextField(
        controller: _themeController,
        decoration: const InputDecoration(
          labelText: 'Week theme (e.g. Base Building, Taper)',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.words,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _EditTrainingDayDialog extends StatefulWidget {
  final TrainingDay day;

  const _EditTrainingDayDialog({required this.day});

  @override
  State<_EditTrainingDayDialog> createState() => _EditTrainingDayDialogState();
}

class _EditTrainingDayDialogState extends State<_EditTrainingDayDialog> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _distanceController;
  late final TextEditingController _notesController;
  late final TextEditingController _workoutTypeOtherController;

  late String _workoutType;
  late int _durationMinutes;
  late String _pace;
  late String _customPaceValue;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.day.description ?? '');
    _distanceController = TextEditingController(
      text: widget.day.targetDistanceKm?.toString() ?? '',
    );
    _notesController = TextEditingController(text: widget.day.notes ?? '');
    final wt = widget.day.workoutType;
    _workoutType = _workoutTypeOptions.contains(wt) ? wt : 'Other';
    _workoutTypeOtherController = TextEditingController(
      text: _workoutType == 'Other' ? wt : '',
    );
    _durationMinutes = (widget.day.targetDurationMinutes ?? 0).clamp(0, 180);
    final p = widget.day.targetPace ?? '';
    _pace = _paceOptions.contains(p) ? p : (p.isEmpty ? 'Easy' : 'Custom');
    final customOptions = _customPaceOptions;
    _customPaceValue = customOptions.contains(p) ? p : (customOptions.isNotEmpty ? customOptions.first : '5:00 /km');
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _distanceController.dispose();
    _notesController.dispose();
    _workoutTypeOtherController.dispose();
    super.dispose();
  }

  void _save() {
    final workoutType = _workoutType == 'Other'
        ? _workoutTypeOtherController.text.trim()
        : _workoutType;
    if (workoutType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workout type is required')),
      );
      return;
    }
    final isRest = _isRestType(workoutType);
    final isPaceRelevant = _isPaceRelevantType(workoutType);

    if (isRest) {
      final updated = TrainingDay(
        dayLabel: widget.day.dayLabel,
        workoutType: workoutType,
        description: null,
        targetDistanceKm: null,
        targetDurationMinutes: null,
        targetPace: null,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      Navigator.of(context).pop(updated);
      return;
    }

    final distance = double.tryParse(_distanceController.text.trim());
    final paceStr = isPaceRelevant
        ? (_pace == 'Custom' ? _customPaceValue : (_pace == 'Easy' ? null : _pace))
        : null;
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    final updated = widget.day.copyWith(
      workoutType: workoutType,
      description: description,
      targetDistanceKm: distance,
      targetDurationMinutes: _durationMinutes > 0 ? _durationMinutes : null,
      targetPace: paceStr?.isEmpty ?? true ? null : paceStr,
      notes: notes,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit workout'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Text(
                widget.day.dayLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('workout-$_workoutType'),
              initialValue: _workoutType,
              decoration: const InputDecoration(
                labelText: 'Workout type',
                border: OutlineInputBorder(),
              ),
              items: _workoutTypeOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _workoutType = v ?? _workoutType),
            ),
            if (_workoutType == 'Other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _workoutTypeOtherController,
                decoration: const InputDecoration(
                  labelText: 'Custom workout type',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (!_isRestType(_workoutType)) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _distanceController,
                decoration: const InputDecoration(
                  labelText: 'Distance (km)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              Text('Duration: $_durationMinutes min', style: Theme.of(context).textTheme.bodyMedium),
              Slider(
                value: _durationMinutes.toDouble(),
                min: 0,
                max: 180,
                divisions: 36,
                label: '$_durationMinutes min',
                onChanged: (v) => setState(() => _durationMinutes = v.round()),
              ),
            ],
            if (_isPaceRelevantType(_workoutType)) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('pace-$_pace'),
                initialValue: _pace,
                decoration: const InputDecoration(
                  labelText: 'Target pace',
                  border: OutlineInputBorder(),
                ),
                items: _paceOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _pace = v ?? _pace),
              ),
              if (_pace == 'Custom') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('custom-pace-$_customPaceValue'),
                  initialValue: _customPaceOptions.contains(_customPaceValue) ? _customPaceValue : _customPaceOptions.first,
                  decoration: const InputDecoration(
                    labelText: 'Pace (min/km)',
                    border: OutlineInputBorder(),
                  ),
                  items: _customPaceOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _customPaceValue = v ?? _customPaceValue),
                ),
              ],
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _PlanHistoryPage extends StatefulWidget {
  const _PlanHistoryPage({required this.service});
  final TrainingPlanService service;

  @override
  State<_PlanHistoryPage> createState() => _PlanHistoryPageState();
}

class _PlanHistoryPageState extends State<_PlanHistoryPage> {
  List<TrainingPlanEntry> _entries = [];
  bool _includeArchived = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    List<TrainingPlanEntry> list = [];
    try {
      list = await widget.service.getAllPlans(includeArchived: _includeArchived);
      if (list.isEmpty && mounted) {
        final active = await widget.service.getActivePlan();
        if (active != null && mounted) {
          await widget.service.savePlan(active);
          list = await widget.service.getAllPlans(includeArchived: _includeArchived);
        }
      }
    } catch (_) {
      list = [];
    } finally {
      if (mounted) setState(() { _entries = list; _loading = false; });
    }
  }

  int get _listItemCount {
    if (_loading) return 1;
    return 1 + (_entries.isEmpty ? 1 : _entries.length);
  }

  Widget _listItem(BuildContext context, int index) {
    final theme = Theme.of(context);
    if (_loading) {
      return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    }
    if (index == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Set one as active, or archive/delete to manage space. Non-archived plans (including completed) are used for coach context.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              icon: Icon(_includeArchived ? Icons.visibility_off : Icons.visibility, size: 18),
              label: Text(_includeArchived ? 'Hide archived' : 'Show archived'),
              onPressed: () async {
                setState(() => _includeArchived = !_includeArchived);
                await _load();
              },
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            _includeArchived
                ? 'No plans. No archived plans yet.'
                : 'No plans yet. Your active and completed plans will appear here.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final e = _entries[index - 1];
    return ListTile(
      title: Text(e.plan.name),
      subtitle: Text(
        [
          if (e.plan.goal != null) e.plan.goal,
          if (e.isActive) 'Active',
          if (e.plan.completedAt != null) 'Completed',
          if (e.archived) 'Archived',
        ].whereType<String>().join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!e.isActive)
            TextButton(
              onPressed: () async {
                await widget.service.setActivePlanById(e.id);
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text('Set active'),
            ),
          if (e.archived)
            TextButton(
              onPressed: () async {
                await widget.service.unarchivePlan(e.id);
                await _load();
              },
              child: const Text('Restore'),
            )
          else
            TextButton(
              onPressed: () async {
                await widget.service.archivePlan(e.id);
                await _load();
              },
              child: const Text('Archive'),
            ),
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete plan?'),
                  content: Text('Permanently remove "${e.plan.name}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await widget.service.deletePlanById(e.id);
                if (mounted) await _load();
                if (!context.mounted) return;
                if (e.isActive) Navigator.of(context).pop(true);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan history'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView.builder(
        itemCount: _listItemCount,
        itemBuilder: _listItem,
      ),
    );
  }
}

