import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:stridemind/models/nutrition_plan.dart';
import 'package:stridemind/services/nutrition_plan_service.dart';

class NutritionPlanPage extends StatefulWidget {
  const NutritionPlanPage({super.key});

  @override
  State<NutritionPlanPage> createState() => _NutritionPlanPageState();
}

class _NutritionPlanPageState extends State<NutritionPlanPage> {
  final _service = NutritionPlanService();
  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  NutritionPlan? _activePlan;
  bool _isLoading = true;
  bool _isParsing = false;
  String? _parsingStatus;

  @override
  void initState() {
    super.initState();
    _loadActivePlan();
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

    setState(() {
      _isParsing = true;
      _parsingStatus = 'Reading ${file.name}…';
    });

    try {
      setState(() =>
          _parsingStatus = 'Analysing with AI… (this may take 10–30 s)');
      final plan =
          await _service.parseFile(file.bytes!, file.extension ?? '');

      setState(() => _parsingStatus = 'Saving plan…');
      await _service.savePlan(plan);

      if (mounted) {
        setState(() {
          _activePlan = plan;
          _isParsing = false;
          _parsingStatus = null;
        });
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

  Future<void> _deletePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Nutrition Plan'),
        content: const Text(
            'This will remove the active nutrition plan from the AI coach context. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
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

  Future<void> _editPlanDetails(NutritionPlan plan) async {
    final result = await showDialog<NutritionPlan>(
      context: context,
      builder: (ctx) => _EditNutritionPlanDialog(plan: plan),
    );
    if (result != null && mounted) {
      await _service.savePlan(result);
      final refreshed = await _service.getActivePlan();
      if (!mounted) return;
      setState(() => _activePlan = refreshed ?? result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan updated'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _editDay(NutritionPlan plan, int dayIndex) async {
    final result = await showDialog<NutritionDay>(
      context: context,
      builder: (ctx) => _EditNutritionDayDialog(day: plan.days[dayIndex]),
    );
    if (result != null && mounted && _activePlan != null) {
      final newDays = List<NutritionDay>.from(plan.days)..[dayIndex] = result;
      final updated = plan.copyWith(days: newDays);
      await _service.savePlan(updated);
      final refreshed = await _service.getActivePlan();
      if (!mounted) return;
      setState(() => _activePlan = refreshed ?? updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Day updated'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _editMeal(NutritionPlan plan, int dayIndex, int mealIndex) async {
    final meal = plan.days[dayIndex].meals[mealIndex];
    final result = await showDialog<NutritionMeal>(
      context: context,
      builder: (ctx) => _EditNutritionMealDialog(meal: meal),
    );
    if (result != null && mounted && _activePlan != null) {
      final newMeals = List<NutritionMeal>.from(plan.days[dayIndex].meals)
        ..[mealIndex] = result;
      final newDay = plan.days[dayIndex].copyWith(meals: newMeals);
      final newDays = List<NutritionDay>.from(plan.days)..[dayIndex] = newDay;
      final updated = plan.copyWith(days: newDays);
      await _service.savePlan(updated);
      final refreshed = await _service.getActivePlan();
      if (!mounted) return;
      setState(() => _activePlan = refreshed ?? updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meal updated'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _regenerateDay(NutritionPlan plan) async {
    if (plan.days.isEmpty) {
      _showError('No days found in this plan.');
      return;
    }
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddDayLabelDialog(plan: plan),
    );
    if (label == null || label.trim().isEmpty || !mounted) return;
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
              Expanded(
                child: Text(
                  'Generating template…',
                  style: Theme.of(ctx).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final targetIndex = plan.days.indexWhere(
        (d) => d.dayLabel.toLowerCase() == label.trim().toLowerCase(),
      );
      final generated = await _service.generateDayTemplate(plan, label.trim());
      final newDay = generated.copyWith(dayLabel: label.trim());
      final newDays = List<NutritionDay>.from(plan.days);
      if (targetIndex >= 0) {
        newDays[targetIndex] = newDay;
      } else {
        newDays.add(newDay);
      }
      final updated = plan.copyWith(days: newDays);
      await _service.savePlan(updated);
      final refreshed = await _service.getActivePlan();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _activePlan = refreshed ?? updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Day template updated'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e, fallback: 'Could not generate day template.')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _autoGenerateMissingDays(NutritionPlan plan) async {
    final labels = plan.days
        .where((d) => d.meals.isEmpty)
        .map((d) => d.dayLabel)
        .toList();
    if (labels.isEmpty) {
      _showError('No missing day templates found.');
      return;
    }

    if (mounted) {
      setState(() {
        _isParsing = true;
        _parsingStatus = 'Preparing day templates...';
      });
    }

    var working = plan;
    final failed = <String>[];
    for (int i = 0; i < labels.length; i++) {
      final label = labels[i];
      if (mounted) {
        setState(() {
          _parsingStatus = 'Generating $label (${i + 1}/${labels.length})...';
        });
      }
      try {
        final generated = await _service.generateDayTemplate(working, label);
        final idx = working.days.indexWhere(
          (d) => d.dayLabel.toLowerCase() == label.toLowerCase(),
        );
        final nextDays = List<NutritionDay>.from(working.days);
        if (idx >= 0) {
          nextDays[idx] = generated.copyWith(dayLabel: label);
        } else {
          nextDays.add(generated.copyWith(dayLabel: label));
        }
        working = working.copyWith(days: nextDays);
      } catch (_) {
        failed.add(label);
      }
    }

    try {
      await _service.savePlan(working);
      final refreshed = await _service.getActivePlan();
      if (!mounted) return;
      setState(() {
        _activePlan = refreshed ?? working;
        _isParsing = false;
        _parsingStatus = null;
      });
      final successCount = labels.length - failed.length;
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed.isEmpty
                  ? 'Generated $successCount day template${successCount == 1 ? '' : 's'}.'
                  : 'Generated $successCount/${labels.length} day templates. Failed: ${failed.join(', ')}',
            ),
            backgroundColor: failed.isEmpty ? Colors.green : Colors.orange,
          ),
        );
      } else {
        _showError('Could not generate missing days. Check your connection and try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
        _parsingStatus = null;
      });
      _showError(_friendlyError(e, fallback: 'Could not save generated day templates.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isParsing
              ? _buildParsingState()
              : _activePlan == null
                  ? _buildEmptyState()
                  : _buildPlanView(_activePlan!),
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
            Text(_parsingStatus ?? 'Processing…',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('StrideMind is reading your nutrition plan with AI.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
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
            Icon(Icons.restaurant_menu,
                size: 72,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 24),
            Text('No Nutrition Plan Yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Upload your nutrition plan and StrideMind will structure it. '
              'The AI coach will use it to give personalised recovery and fuelling advice.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Supported: PDF · Image (JPG, PNG) · Word (.docx) · Excel (.xlsx) · Text (.txt, .csv)',
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
              label: const Text('Upload Nutrition Plan'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanView(NutritionPlan plan) {
    final missingDays = _weekdays
        .where(
          (d) => !plan.days.any((day) => day.dayLabel.toLowerCase() == d.toLowerCase()),
        )
        .toList();
    final placeholderDays = plan.days.where((d) => d.meals.isEmpty).map((d) => d.dayLabel).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPlanHeader(plan),
        if (plan.generalGuidelines != null) ...[
          const SizedBox(height: 12),
          _buildGuidelinesCard(plan.generalGuidelines!),
        ],
        const SizedBox(height: 16),
        if (missingDays.isNotEmpty || placeholderDays.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      missingDays.isNotEmpty
                          ? 'Some weekdays are missing from the upload (${missingDays.join(', ')}). Use "Regenerate day template" to auto-fill them.'
                          : 'Some days have no meal template yet (${placeholderDays.join(', ')}). Use "Regenerate day template" to fill them.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (missingDays.isNotEmpty || placeholderDays.isNotEmpty) const SizedBox(height: 12),
        ...plan.days.asMap().entries.map((e) => _buildDayCard(
              plan,
              e.key,
              e.value,
              isToday: e.value == plan.todayTemplate,
              onEdit: () => _editDay(plan, e.key),
            )),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Tap a day or meal to edit. Generate with AI to improve an existing day template.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isParsing ? null : () => _regenerateDay(plan),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Regenerate day template'),
        ),
        if (placeholderDays.isNotEmpty) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _isParsing ? null : () => _autoGenerateMissingDays(plan),
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text('Auto-generate missing days (${placeholderDays.length})'),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPlanHeader(NutritionPlan plan) {
    final targets = plan.dailyTargetSummary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant_menu,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(plan.name,
                        style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (plan.goal != null) _chip(Icons.flag, plan.goal!),
                if (targets.isNotEmpty) _chip(Icons.local_fire_department, targets),
                _chip(Icons.source, 'Uploaded'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidelinesCard(String guidelines) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 18, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
                child: Text(guidelines,
                    style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(NutritionPlan plan, int dayIndex, NutritionDay day,
      {required bool isToday, VoidCallback? onEdit}) {
    final macros = day.macroSummary;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isToday
            ? BorderSide(
                color: theme.colorScheme.primary,
                width: 1.5,
              )
            : BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.6),
                width: 1,
              ),
      ),
      child: ExpansionTile(
        initiallyExpanded: isToday,
        leading: Icon(
          Icons.today,
          color: isToday
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(day.dayLabel,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: macros.isNotEmpty ? Text(macros) : null,
        trailing: onEdit != null
            ? IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit day',
                onPressed: onEdit,
              )
            : null,
        children: [
          if (day.meals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No meals yet for ${day.dayLabel}. Use "Regenerate day template" to create one.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ...day.meals
              .asMap()
              .entries
              .map((e) => _buildMealTile(plan, dayIndex, e.key, e.value)),
          if (day.notes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(day.notes!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _buildMealTile(NutritionPlan plan, int dayIndex, int mealIndex, NutritionMeal meal) {
    final macros = meal.macroSummary;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18),
        tooltip: 'Edit meal',
        onPressed: () => _editMeal(plan, dayIndex, mealIndex),
      ),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: _mealColor(meal.name),
        child: Icon(_mealIcon(meal.name), size: 16, color: Colors.white),
      ),
      title: Text(
        meal.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meal.timing != null)
            Text(
              meal.timing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          if (macros.isNotEmpty) Text(macros),
          if (meal.foods != null && meal.foods!.isNotEmpty)
            Text(meal.foods!.join(', '),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (meal.notes != null)
            Text('↳ ${meal.notes}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic)),
        ],
      ),
      isThreeLine: (meal.foods?.isNotEmpty ?? false) || meal.notes != null,
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

  Color _mealColor(String name) {
    final n = name.toLowerCase();
    if (n.contains('breakfast') || n.contains('morning')) return Colors.orange;
    if (n.contains('lunch')) return Colors.green;
    if (n.contains('dinner') || n.contains('evening')) return Colors.indigo;
    if (n.contains('pre') || n.contains('before')) return Colors.blue;
    if (n.contains('post') || n.contains('after') || n.contains('recovery')) {
      return Colors.teal;
    }
    if (n.contains('snack')) return Colors.amber.shade700;
    return Colors.blueGrey;
  }

  IconData _mealIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('breakfast')) return Icons.free_breakfast;
    if (n.contains('lunch')) return Icons.lunch_dining;
    if (n.contains('dinner')) return Icons.dinner_dining;
    if (n.contains('snack')) return Icons.cookie;
    if (n.contains('pre') || n.contains('before')) return Icons.battery_charging_full;
    if (n.contains('post') || n.contains('after') || n.contains('recovery')) {
      return Icons.healing;
    }
    return Icons.restaurant;
  }
}

class _EditNutritionPlanDialog extends StatefulWidget {
  final NutritionPlan plan;

  const _EditNutritionPlanDialog({required this.plan});

  @override
  State<_EditNutritionPlanDialog> createState() => _EditNutritionPlanDialogState();
}

class _EditNutritionPlanDialogState extends State<_EditNutritionPlanDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _goalController;
  late final TextEditingController _calorieController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _guidelinesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plan.name);
    _goalController = TextEditingController(text: widget.plan.goal ?? '');
    _calorieController = TextEditingController(
      text: widget.plan.dailyCalorieTarget?.toString() ?? '',
    );
    _proteinController = TextEditingController(
      text: widget.plan.dailyProteinTargetG?.toString() ?? '',
    );
    _carbsController = TextEditingController(
      text: widget.plan.dailyCarbsTargetG?.toString() ?? '',
    );
    _fatController = TextEditingController(
      text: widget.plan.dailyFatTargetG?.toString() ?? '',
    );
    _guidelinesController = TextEditingController(
      text: widget.plan.generalGuidelines ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _goalController.dispose();
    _calorieController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _guidelinesController.dispose();
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
    final calorie = int.tryParse(_calorieController.text.trim());
    final protein = double.tryParse(_proteinController.text.trim());
    final carbs = double.tryParse(_carbsController.text.trim());
    final fat = double.tryParse(_fatController.text.trim());
    final goal = _goalController.text.trim().isEmpty
        ? null
        : _goalController.text.trim();
    final guidelines = _guidelinesController.text.trim().isEmpty
        ? null
        : _guidelinesController.text.trim();

    final updated = widget.plan.copyWith(
      name: name,
      goal: goal,
      dailyCalorieTarget: calorie,
      dailyProteinTargetG: protein,
      dailyCarbsTargetG: carbs,
      dailyFatTargetG: fat,
      generalGuidelines: guidelines,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
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
            TextField(
              controller: _goalController,
              decoration: const InputDecoration(
                labelText: 'Goal (e.g. Marathon fuelling)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _calorieController,
              decoration: const InputDecoration(
                labelText: 'Daily calorie target (kcal)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _proteinController,
              decoration: const InputDecoration(
                labelText: 'Daily protein target (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _carbsController,
              decoration: const InputDecoration(
                labelText: 'Daily carbs target (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fatController,
              decoration: const InputDecoration(
                labelText: 'Daily fat target (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _guidelinesController,
              decoration: const InputDecoration(
                labelText: 'General guidelines',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
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

class _EditNutritionDayDialog extends StatefulWidget {
  final NutritionDay day;

  const _EditNutritionDayDialog({required this.day});

  @override
  State<_EditNutritionDayDialog> createState() => _EditNutritionDayDialogState();
}

class _EditNutritionDayDialogState extends State<_EditNutritionDayDialog> {
  late final TextEditingController _dayLabelController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _dayLabelController = TextEditingController(text: widget.day.dayLabel);
    _caloriesController = TextEditingController(
      text: widget.day.totalCalories?.toString() ?? '',
    );
    _proteinController = TextEditingController(
      text: widget.day.totalProteinG?.toString() ?? '',
    );
    _carbsController = TextEditingController(
      text: widget.day.totalCarbsG?.toString() ?? '',
    );
    _fatController = TextEditingController(
      text: widget.day.totalFatG?.toString() ?? '',
    );
    _notesController = TextEditingController(text: widget.day.notes ?? '');
  }

  @override
  void dispose() {
    _dayLabelController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    final dayLabel = _dayLabelController.text.trim();
    if (dayLabel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day label is required')),
      );
      return;
    }
    final calories = int.tryParse(_caloriesController.text.trim());
    final protein = double.tryParse(_proteinController.text.trim());
    final carbs = double.tryParse(_carbsController.text.trim());
    final fat = double.tryParse(_fatController.text.trim());
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    final updated = widget.day.copyWith(
      dayLabel: dayLabel,
      totalCalories: calories,
      totalProteinG: protein,
      totalCarbsG: carbs,
      totalFatG: fat,
      notes: notes,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit day'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _dayLabelController,
              decoration: const InputDecoration(
                labelText: 'Day (e.g. Monday, Day 1)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caloriesController,
              decoration: const InputDecoration(
                labelText: 'Total calories (kcal)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _proteinController,
              decoration: const InputDecoration(
                labelText: 'Total protein (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _carbsController,
              decoration: const InputDecoration(
                labelText: 'Total carbs (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fatController,
              decoration: const InputDecoration(
                labelText: 'Total fat (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
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
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditNutritionMealDialog extends StatefulWidget {
  final NutritionMeal meal;

  const _EditNutritionMealDialog({required this.meal});

  @override
  State<_EditNutritionMealDialog> createState() => _EditNutritionMealDialogState();
}

class _EditNutritionMealDialogState extends State<_EditNutritionMealDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _timingController;
  late final TextEditingController _foodsController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.meal.name);
    _descriptionController = TextEditingController(text: widget.meal.description ?? '');
    _caloriesController = TextEditingController(
      text: widget.meal.calories?.toString() ?? '',
    );
    _proteinController = TextEditingController(
      text: widget.meal.proteinG?.toString() ?? '',
    );
    _carbsController = TextEditingController(
      text: widget.meal.carbsG?.toString() ?? '',
    );
    _fatController = TextEditingController(
      text: widget.meal.fatG?.toString() ?? '',
    );
    _timingController = TextEditingController(text: widget.meal.timing ?? '');
    _foodsController = TextEditingController(
      text: widget.meal.foods?.join(', ') ?? '',
    );
    _notesController = TextEditingController(text: widget.meal.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _timingController.dispose();
    _foodsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meal name is required')),
      );
      return;
    }
    final calories = int.tryParse(_caloriesController.text.trim());
    final protein = double.tryParse(_proteinController.text.trim());
    final carbs = double.tryParse(_carbsController.text.trim());
    final fat = double.tryParse(_fatController.text.trim());
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    final timing = _timingController.text.trim().isEmpty
        ? null
        : _timingController.text.trim();
    final foodsStr = _foodsController.text.trim();
    final foods = foodsStr.isEmpty
        ? null
        : foodsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    final updated = widget.meal.copyWith(
      name: name,
      description: description,
      calories: calories,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      timing: timing,
      foods: foods,
      notes: notes,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit meal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Meal name',
                border: OutlineInputBorder(),
              ),
            ),
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
              controller: _caloriesController,
              decoration: const InputDecoration(
                labelText: 'Calories (kcal)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _proteinController,
              decoration: const InputDecoration(
                labelText: 'Protein (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _carbsController,
              decoration: const InputDecoration(
                labelText: 'Carbs (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fatController,
              decoration: const InputDecoration(
                labelText: 'Fat (g)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timingController,
              decoration: const InputDecoration(
                labelText: 'Timing',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _foodsController,
              decoration: const InputDecoration(
                labelText: 'Foods (comma-separated)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
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

class _AddDayLabelDialog extends StatefulWidget {
  final NutritionPlan? plan;

  const _AddDayLabelDialog({this.plan});

  @override
  State<_AddDayLabelDialog> createState() => _AddDayLabelDialogState();
}

class _AddDayLabelDialogState extends State<_AddDayLabelDialog> {
  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final existingLabels = widget.plan?.days.map((d) => d.dayLabel).toList() ?? [];
    final options = <String>[..._weekdays];
    for (final label in existingLabels) {
      if (!options.any((o) => o.toLowerCase() == label.toLowerCase())) {
        options.add(label);
      }
    }
    String? selectedLabel = options.isNotEmpty ? options.first : null;
    return AlertDialog(
      title: const Text('Regenerate day template'),
      content: StatefulBuilder(
        builder: (context, setLocalState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select a day to regenerate with AI.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedLabel,
              decoration: const InputDecoration(
                labelText: 'Day',
                border: OutlineInputBorder(),
              ),
              items: options
                  .map((label) => DropdownMenuItem<String>(
                        value: label,
                        child: Text(
                          existingLabels.any((e) => e.toLowerCase() == label.toLowerCase())
                              ? '$label (existing)'
                              : '$label (missing)',
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                setLocalState(() => selectedLabel = value);
              },
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
          onPressed: () {
            if (selectedLabel != null && selectedLabel!.isNotEmpty) {
              Navigator.of(context).pop(selectedLabel);
            }
          },
          child: const Text('Generate'),
        ),
      ],
    );
  }
}
