import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:stridemind/models/nutrition_plan.dart';
import 'package:stridemind/models/strava_activity.dart' as strava_models;
import 'package:stridemind/models/training_plan.dart';
import 'package:stridemind/pages/nutrition_plan_page.dart';
import 'package:stridemind/pages/profile_page.dart';
import 'package:stridemind/pages/training_plan_page.dart';
import 'package:stridemind/services/strava_api_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:stridemind/services/strava_auth_service.dart';
import 'package:stridemind/services/feedback_service.dart';
import 'package:stridemind/services/nutrition_plan_service.dart';
import 'package:stridemind/services/prompt_service.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/services/training_plan_service.dart';

class CoachPage extends StatefulWidget {
  final StravaAuthService authService;
  final strava_models.StravaActivity? initialActivityToSelect;
  final VoidCallback? onInitialActivityApplied;

  const CoachPage({
    super.key,
    required this.authService,
    this.initialActivityToSelect,
    this.onInitialActivityApplied,
  });

  @override
  State<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends State<CoachPage> {
  final _noteController = TextEditingController();
  List<dynamic>? _aiFeedback;
  List<Map<String, dynamic>>? _conversationHistory;
  bool _isLoading = false;
  String _streamingFeedbackText = '';
  final _feedbackService = FeedbackService();
  final _promptService = PromptService();
  final _dbService = DatabaseService();

  Future<List<strava_models.StravaActivity>>? _todaysActivitiesFuture;
  Future<List<strava_models.StravaActivity>>? _recentActivitiesFuture;
  strava_models.StravaActivity? _selectedContextActivity;

  final _trainingPlanService = TrainingPlanService();
  TrainingPlan? _activePlan;
  bool _includeTrainingPlan = false;

  final _nutritionPlanService = NutritionPlanService();
  NutritionPlan? _activeNutritionPlan;
  bool _includeNutritionPlan = false;

  @override
  void initState() {
    super.initState();
    _todaysActivitiesFuture = _getTodaysActivities();
    _recentActivitiesFuture = _getRecentActivities();
    _loadConversationHistory();
    _loadActivePlan();
    _loadActiveNutritionPlan();
    if (widget.initialActivityToSelect != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedContextActivity = widget.initialActivityToSelect);
          widget.onInitialActivityApplied?.call();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant CoachPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialActivityToSelect != null &&
        widget.initialActivityToSelect != oldWidget.initialActivityToSelect) {
      // Defer to avoid parent setState during build (fixes "cannot be marked as needing to build").
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedContextActivity = widget.initialActivityToSelect);
        widget.onInitialActivityApplied?.call();
      });
    }
  }

  Future<void> _loadActivePlan() async {
    final plan = await _trainingPlanService.getActivePlan();
    if (mounted) setState(() => _activePlan = plan);
  }

  Future<void> _loadActiveNutritionPlan() async {
    final plan = await _nutritionPlanService.getActivePlan();
    if (mounted) setState(() => _activeNutritionPlan = plan);
  }

  Future<StravaApiService> _getApiService() async {
    final accessToken = await widget.authService.getValidAccessToken();
    if (accessToken == null) throw Exception('Authentication failed.');
    return StravaApiService(accessToken: accessToken);
  }

  Future<List<strava_models.StravaActivity>> _getTodaysActivities() async {
    final apiService = await _getApiService();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final afterTimestamp = startOfToday.millisecondsSinceEpoch ~/ 1000;

    final summaryActivities =
        await apiService.getRecentActivities(after: afterTimestamp);

    // Fetch detailed data for all activity types in parallel
    final detailedActivities =
        await Future.wait(summaryActivities.map((activity) async {
      try {
        return await apiService.getActivityDetails(activity.id);
      } catch (e) {
        debugPrint('Could not fetch details for activity ${activity.id}: $e');
        return activity;
      }
    }));

    return detailedActivities;
  }

  Future<List<strava_models.StravaActivity>> _getRecentActivities() async {
    final apiService = await _getApiService();
    // Fetch last 10 activities regardless of date, matching the history cap
    return apiService.getRecentActivities(perPage: 10);
  }

  Future<void> _loadConversationHistory() async {
    final history = await _dbService.getConversationHistory();
    if (mounted && history.isNotEmpty) {
      setState(() {
        _conversationHistory = history;
        // Display the last feedback from history on initial load
        _aiFeedback =
            history.last['feedback']?['feedback'] as List<dynamic>?;
      });
    }
  }

  void _reloadContextFutures() {
    if (!mounted) return;
    setState(() {
      _todaysActivitiesFuture = _getTodaysActivities();
      _recentActivitiesFuture = _getRecentActivities();
    });
  }

  bool _isNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return error is SocketException ||
        text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection closed') ||
        text.contains('connection refused');
  }

  String _friendlyErrorMessage(Object error) {
    if (_isNetworkError(error)) {
      return 'No internet connection. Reconnect and try again.';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('oauth') || text.contains('authentication failed')) {
      return 'Authentication expired. Reconnect Strava in Settings and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  void _generateFeedback() async {
    if (_noteController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a note about your day.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _aiFeedback = null; // Clear previous feedback while loading
      _streamingFeedbackText = '';
    });

    try {
      final todaysActivities = await _todaysActivitiesFuture;
      if (todaysActivities == null) {
        throw Exception("Workout data not loaded yet.");
      }

      strava_models.StravaActivity? contextActivity =
          todaysActivities.isEmpty ? _selectedContextActivity : null;
      if (contextActivity != null &&
          (contextActivity.splits == null || contextActivity.splits!.isEmpty)) {
        try {
          final api = await _getApiService();
          contextActivity = await api.getActivityDetails(contextActivity.id);
          if (mounted) setState(() => _selectedContextActivity = contextActivity);
        } catch (_) {}
      }

      final history = _conversationHistory ?? [];
      final gearList = await _dbService.getAllGear();
      final runnerProfile = await _dbService.getRunnerProfile();
      final planHistorySummary = await _trainingPlanService.getPlanHistorySummaryForCoach();
      final prompt = _promptService.buildFeedbackPrompt(
        _noteController.text,
        todaysActivities,
        history,
        selectedContextActivity: contextActivity,
        trainingPlan:
            (_activePlan != null && _includeTrainingPlan) ? _activePlan : null,
        nutritionPlan: (_activeNutritionPlan != null && _includeNutritionPlan)
            ? _activeNutritionPlan
            : null,
        gearList: gearList,
        runnerProfile: runnerProfile,
        planHistorySummary: planHistorySummary.isNotEmpty ? planHistorySummary : null,
      );

      final feedbackBuffer = StringBuffer();
      await for (final chunk in _feedbackService.streamFeedback(prompt)) {
        feedbackBuffer.write(chunk);
        if (mounted) {
          setState(() {
            _streamingFeedbackText = feedbackBuffer.toString();
          });
        }
      }
      final feedbackJsonString = feedbackBuffer.toString();
      // The AI might return the JSON string wrapped in markdown ```json ... ```, so we clean it.
      final cleanedJson =
          feedbackJsonString.replaceAll('```json', '').replaceAll('```', '').trim();
      final feedbackData = jsonDecode(cleanedJson);

      // Create new turn and add to history
      final newTurn = {
        'log': _noteController.text,
        'feedback': feedbackData,
      };

      // Save to DB. The service will handle trimming.
      await _dbService.addConversationTurn(newTurn);

      // For immediate UI update, we can just update the local list.
      // We should also trim it to match what the DB is doing.
      final updatedHistory = List<Map<String, dynamic>>.from(history)..add(newTurn);
      const maxHistoryLength = 10;
      if (updatedHistory.length > maxHistoryLength) {
        updatedHistory.removeAt(0); // remove the oldest one
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _conversationHistory = updatedHistory;
          _aiFeedback = feedbackData['feedback'] as List<dynamic>?; // Set display
          _streamingFeedbackText = '';
        });
      }
    } catch (e) {
      final friendly = _friendlyErrorMessage(e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _aiFeedback = [
            // Set display to an error message, but DO NOT save to history
            {'type': 'heading', 'content': {'title': 'Error', 'text': friendly}}
          ];
          _streamingFeedbackText = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendly),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildSectionCard(
          title: 'Training Log',
          icon: Icons.edit_note,
          child: TextField(
            controller: _noteController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'How was your training? How are you feeling?',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: "Today's Context",
          icon: Icons.checklist_rtl,
          child: _buildTodaysContext(),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _generateFeedback,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Get AI Feedback'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 24),
        if (_isLoading) ...[
          _buildSectionCard(
            title: 'AI Coach Feedback (live)',
            icon: Icons.chat_bubble_outline,
            child: _streamingFeedbackText.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : MarkdownBody(
                    data: _streamingFeedbackText,
                    styleSheet:
                        MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
          ),
          const SizedBox(height: 24),
        ],
        if (_aiFeedback != null)
          _buildSectionCard(
            title: 'AI Coach Feedback',
            icon: Icons.chat_bubble_outline,
            child: _buildFeedbackContent(_aiFeedback!),
          ),
      ],
    );
  }

  Widget _buildFeedbackContent(List<dynamic> feedbackSections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: feedbackSections.map<Widget>((section) {
        final type = section['type'];
        final content = section['content'];

        switch (type) {
          case 'heading':
            return _buildHeadingSection(content);
          case 'table':
            return _buildTableSection(content);
          case 'bold_text':
            return _buildBoldTextSection(content);
          case 'paragraph':
            return _buildParagraphSection(content);
          default:
            return Text('Unknown content type: $type');
        }
      }).toList(),
    );
  }

  Widget _buildHeadingSection(dynamic content) {
    final title = content['title'] as String? ?? 'Feedback';
    final text = content['text'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          MarkdownBody(
            data: text,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableSection(dynamic content) {
    final headers = (content['headers'] as List<dynamic>?)
            ?.map((h) => h.toString())
            .toList() ??
        [];

    final numColumns = headers.length;
    if (numColumns == 0) {
      return const SizedBox.shrink();
    }

    final List<List<String>> rows = [];
    if (content['rows'] is List) {
      for (final rowData in (content['rows'] as List)) {
        if (rowData is List && rowData.length == numColumns) {
          rows.add(rowData.map((c) => c.toString()).toList());
        } else {
          debugPrint(
              'Skipping malformed table row. Expected $numColumns cells. Row: $rowData');
        }
      }
    }

    final theme = Theme.of(context);
    final title = content['title'] as String? ?? '';
    // Use Table with fraction widths and wrapping text so content fits width — vertical scroll only, no horizontal.
    final columnWidths = Map<int, TableColumnWidth>.fromIterables(
      List.generate(numColumns, (i) => i),
      List.generate(numColumns, (_) => const FlexColumnWidth(1)),
    );
    final borderColor = theme.dividerColor.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Table(
              columnWidths: columnWidths,
              border: TableBorder.symmetric(
                inside: BorderSide(color: borderColor),
                outside: BorderSide.none,
              ),
              defaultColumnWidth: const FlexColumnWidth(1),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withValues(alpha: 0.25),
                  ),
                  children: headers.map<Widget>((h) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(
                        h,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        softWrap: true,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
                ...rows.map((row) => TableRow(
                  children: row.map<Widget>((cell) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: MarkdownBody(
                        data: cell,
                        selectable: false,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodySmall,
                          strong: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          em: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        shrinkWrap: true,
                        fitContent: true,
                      ),
                    );
                  }).toList(),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoldTextSection(dynamic content) {
    final text = content as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildParagraphSection(dynamic content) {
    final text = content as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: MarkdownBody(
        data: text,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildTodaysContext() {
    return FutureBuilder<List<strava_models.StravaActivity>>(
      future: _todaysActivitiesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          final friendly = _friendlyErrorMessage(snapshot.error!);
          return ListTile(
            leading: const Icon(Icons.wifi_off),
            title: Text(friendly),
            subtitle: const Text('Retry after reconnecting, or select a cached recent workout below.'),
            contentPadding: EdgeInsets.zero,
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry',
              onPressed: _reloadContextFutures,
            ),
          );
        }

        final activities = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activities.isEmpty) ...[
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('No activities logged today.'),
                subtitle: Text(
                    'Select a recent workout below to discuss with the coach.'),
                contentPadding: EdgeInsets.zero,
              ),
              _buildRecentActivityPicker(),
            ],
            ...activities.map((activity) {
              if (activity.type.toLowerCase() == 'run' &&
                  activity.averageSpeed != null) {
                return _buildRunDetails(activity);
              } else {
                return _buildActivitySummaryTile(activity);
              }
            }),
            const Divider(height: 16),
            _buildTrainingPlanTile(),
            _buildNutritionPlanTile(),
            _buildContextTile(
              icon: Icons.directions_run,
              title: 'Gear',
              subtitle: 'View and manage shoes, bikes',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfilePage(authService: widget.authService),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  DropdownMenuItem<strava_models.StravaActivity> _buildActivityDropdownItem(
      strava_models.StravaActivity activity) {
    final d = activity.startDateLocal;
    final dateLabel = '${d.day}/${d.month}/${d.year}';
    final dist = activity.distance > 0
        ? ' · ${_formatDistance(activity.distance)}'
        : '';
    return DropdownMenuItem(
      value: activity,
      child: Text(
        '${activity.name} · $dateLabel$dist',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildRecentActivityPicker() {
    return FutureBuilder<List<strava_models.StravaActivity>>(
      future: _recentActivitiesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _friendlyErrorMessage(snapshot.error!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        if (snapshot.data?.isEmpty ?? true) {
          return const SizedBox.shrink();
        }

        final recent = snapshot.data!;
        if (recent.isNotEmpty && _selectedContextActivity == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedContextActivity = recent.first);
          });
        }
        final isSelected = _selectedContextActivity != null;
        final primary = Theme.of(context).colorScheme.primary;

        // Value must be in items. If selected activity came from detail (different list),
        // include it in items so the dropdown can display it.
        final selectedId = _selectedContextActivity?.id;
        strava_models.StravaActivity? valueForDropdown;
        if (selectedId != null) {
          final match = recent.where((a) => a.id == selectedId);
          valueForDropdown = match.isEmpty ? _selectedContextActivity : match.first;
        }
        final dropdownItems = <DropdownMenuItem<strava_models.StravaActivity>>[
          if (_selectedContextActivity != null &&
              !recent.any((a) => a.id == _selectedContextActivity!.id))
            _buildActivityDropdownItem(_selectedContextActivity!),
          ...recent.map(_buildActivityDropdownItem),
        ];

        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Dropdown ──────────────────────────────────────────────────
              DropdownButtonFormField<strava_models.StravaActivity>(
                key: ValueKey('activity-${valueForDropdown?.id}'),
                initialValue: valueForDropdown,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: isSelected
                      ? 'Workout selected for discussion'
                      : 'Discuss a recent workout',
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: isSelected ? primary : Colors.grey.shade400,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  prefixIcon: Icon(
                    isSelected ? Icons.check_circle : Icons.history,
                    color: isSelected ? primary : null,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                hint: const Text('Select a workout (optional)'),
                items: dropdownItems,
                onChanged: (selected) =>
                    setState(() => _selectedContextActivity = selected),
              ),

              // ── Selection confirmation strip ──────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation,
                        child: SizeTransition(
                            sizeFactor: animation, child: child)),
                child: isSelected
                    ? Padding(
                        key: const ValueKey('confirm'),
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: primary.withValues(alpha: 0.3)),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 16, color: primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Coach will discuss:',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: primary,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                      _selectedContextActivity!.name,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                tooltip: 'Clear selection',
                                onPressed: () => setState(
                                    () => _selectedContextActivity = null),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivitySummaryTile(strava_models.StravaActivity activity) {
    final parts = <String>[activity.type];
    if (activity.distance > 0) parts.add(_formatDistance(activity.distance));
    parts.add(_formatDuration(activity.movingTime));
    if (activity.averageHeartrate != null) {
      parts.add('${activity.averageHeartrate!.toStringAsFixed(0)} bpm avg HR');
    }
    return _buildContextTile(
      icon: _getIconForActivityType(activity.type),
      title: activity.name,
      subtitle: parts.join(' · '),
    );
  }

  Widget _buildTrainingPlanTile() {
    return _buildPlanContextRow(
      icon: Icons.event_note,
      title: 'Training Plan',
      activePlanName: _activePlan != null
          ? () {
              final week = _activePlan!.currentWeek;
              if (week == null) return _activePlan!.name;
              final theme =
                  week.theme != null ? ' · ${week.theme}' : '';
              return '${_activePlan!.name} · Wk ${week.weekNumber}$theme';
            }()
          : null,
      isIncluded: _includeTrainingPlan,
      onToggle: _activePlan != null
          ? (v) => setState(() => _includeTrainingPlan = v)
          : null,
      onManage: () async {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => const TrainingPlanPage()));
        _loadActivePlan();
      },
      emptyLabel: 'Tap to upload your training plan',
    );
  }

  Widget _buildNutritionPlanTile() {
    return _buildPlanContextRow(
      icon: Icons.restaurant_menu,
      title: 'Nutrition Plan',
      activePlanName: _activeNutritionPlan?.name,
      isIncluded: _includeNutritionPlan,
      onToggle: _activeNutritionPlan != null
          ? (v) => setState(() => _includeNutritionPlan = v)
          : null,
      onManage: () async {
        await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NutritionPlanPage()));
        _loadActiveNutritionPlan();
      },
      emptyLabel: 'Tap to upload your nutrition plan',
    );
  }

  /// Reusable toggle row for training plan and nutrition plan.
  Widget _buildPlanContextRow({
    required IconData icon,
    required String title,
    required String? activePlanName,
    required bool isIncluded,
    required void Function(bool)? onToggle,
    required VoidCallback onManage,
    required String emptyLabel,
  }) {
    final hasPlan = activePlanName != null;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primary = colorScheme.primary;
    final activeColor = isIncluded && hasPlan
        ? primary
        : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onManage,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: activeColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    hasPlan
                        ? (isIncluded
                            ? activePlanName
                            : '$activePlanName  (excluded)')
                        : emptyLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: hasPlan && !isIncluded
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasPlan)
              Switch.adaptive(
                value: isIncluded,
                onChanged: onToggle,
                trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
                  if (states.contains(WidgetState.selected)) return primary;
                  return null;
                }),
                thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
                  if (states.contains(WidgetState.selected)) return colorScheme.onPrimary;
                  return null;
                }),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )
            else
              Icon(
                Icons.add_circle_outline,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildRunDetails(strava_models.StravaActivity activity) {
    final details = <String>[];
    if (activity.averageSpeed != null && activity.averageSpeed! > 0) {
      details.add('Avg Pace: ${_formatPace(activity.averageSpeed!)} /km');
    }
    if (activity.averageHeartrate != null) {
      details.add('Avg HR: ${activity.averageHeartrate!.toStringAsFixed(0)} bpm');
    }
    if (activity.averageCadence != null) {
      details.add('Avg Cadence: ${(activity.averageCadence! * 2).toStringAsFixed(0)} spm');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildContextTile(
          icon: _getIconForActivityType(activity.type),
          title: activity.name,
          subtitle:
              '${_formatDistance(activity.distance)} - ${_formatDuration(activity.movingTime)}',
        ),
        if (details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 4, bottom: 8),
            child: Text(details.join('  •  ')),
          ),
        if (activity.splits != null && activity.splits!.isNotEmpty)
          _buildSplitsTable(activity.splits!),
      ],
    );
  }

  Widget _buildSplitsTable(List<strava_models.Split> splits) {
    // Filter for metric splits (which are per km)
    final kmSplits =
        splits.where((s) => (s.distance - 1000.0).abs() < 5.0).toList();

    if (kmSplits.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 40.0, right: 16, top: 0, bottom: 8),
      child: DataTable(
        columnSpacing: 24,
        horizontalMargin: 0,
        headingRowHeight: 24,
        dataRowMinHeight: 24,
        dataRowMaxHeight: 32,
        columns: const [
          DataColumn(label: Text('Split')),
          DataColumn(label: Text('Pace/km'), numeric: true),
          DataColumn(label: Text('Time'), numeric: true),
        ],
        rows: List.generate(kmSplits.length, (index) {
          final split = kmSplits[index];
          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(_formatPace(split.averageSpeed))),
              DataCell(Text(_formatDuration(split.movingTime))),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildContextTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(title),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      trailing: onTap != null ? const Icon(Icons.chevron_right, size: 20) : null,
    );
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

  IconData _getIconForActivityType(String type) {
    switch (type.toLowerCase()) {
      case 'run':
        return Icons.directions_run;
      default:
        return Icons.fitness_center;
    }
  }
}