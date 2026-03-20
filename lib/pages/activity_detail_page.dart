import 'package:flutter/material.dart' hide Split;
import 'package:intl/intl.dart';
import 'package:stridemind/models/strava_activity.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/services/strava_api_service.dart';
import 'package:stridemind/services/strava_auth_service.dart';
import 'package:stridemind/utils/activity_display_utils.dart';

/// Coach-focused activity detail. Fetches full activity (with km splits) when
/// the summary has no splits. Tapping "Discuss with coach" pops with the activity.
class ActivityDetailPage extends StatefulWidget {
  final StravaActivity activity;
  final StravaAuthService authService;

  const ActivityDetailPage({
    super.key,
    required this.activity,
    required this.authService,
  });

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  late StravaActivity _activity;
  String? _loadError;
  bool _attemptedFullDetailsFetch = false;

  @override
  void initState() {
    super.initState();
    _activity = widget.activity;
    _loadFullDetailsIfNeeded();
  }

  /// Fetches full activity (splits, etc.) when the summary has no splits.
  /// Saves to cache so next open is instant. No loading spinner.
  Future<void> _loadFullDetailsIfNeeded() async {
    if (_attemptedFullDetailsFetch) return;

    // Backfill once if we don't yet have Strava laps/intervals, even if we have old cached splits.
    final needsLapsBackfill =
        _activity.type.toLowerCase() == 'run' && (_activity.laps == null || _activity.laps!.isEmpty);

    if (!needsLapsBackfill && _activity.canonicalSegments.isNotEmpty) return;

    setState(() => _loadError = null);
    _attemptedFullDetailsFetch = true;

    try {
      final token = await widget.authService.getValidAccessToken();
      if (token == null || !mounted) return;
      final api = StravaApiService(accessToken: token);
      final full = await api.getActivityDetails(_activity.id);
      if (mounted) {
        await DatabaseService().upsertActivities([full]);
        setState(() => _activity = full);
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Run':
        return Icons.directions_run;
      case 'Ride':
      case 'VirtualRide':
        return Icons.directions_bike;
      case 'Swim':
        return Icons.pool;
      case 'Walk':
        return Icons.directions_walk;
      case 'Hike':
        return Icons.hiking;
      case 'WeightTraining':
        return Icons.fitness_center;
      default:
        return Icons.sports;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRun = _activity.type.toLowerCase() == 'run';
    final hasLaps = _activity.laps != null && _activity.laps!.isNotEmpty;
    final segments = _activity.canonicalSegments;
    final kmSplits = ActivityDisplayUtils.getKmSplits(_activity.splits ?? const []);
    final derivedKmSplits = kmSplits.isNotEmpty
        ? kmSplits
        : ActivityDisplayUtils.deriveKmSplitsFromSegments(segments);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity details'),
        actions: [
          IconButton(
            tooltip: 'Discuss with coach',
            onPressed: () => Navigator.of(context).pop(_activity),
            icon: const Icon(Icons.chat_bubble_outline),
          )
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Row(
            children: [
              Icon(
                _iconForType(_activity.type),
                color: colorScheme.primary,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activity.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat.yMMMd().add_jm().format(_activity.startDateLocal),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _activity.type,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Section(title: 'Summary', children: [
            _StatRow('Distance', ActivityDisplayUtils.formatDistance(_activity.distance)),
            _StatRow('Moving time', ActivityDisplayUtils.formatDuration(_activity.movingTime)),
            if (_activity.totalElevationGain > 0)
              _StatRow('Elevation gain', '${_activity.totalElevationGain.toStringAsFixed(0)} m'),
          ]),
          if (isRun && (_activity.averageSpeed != null || _activity.averageHeartrate != null || _activity.averageCadence != null)) ...[
            const SizedBox(height: 16),
            _Section(title: 'Run stats', children: [
              if (_activity.averageSpeed != null && _activity.averageSpeed! > 0)
                _StatRow('Average pace', '${ActivityDisplayUtils.formatPace(_activity.averageSpeed!)} /km'),
              if (_activity.averageHeartrate != null)
                _StatRow('Average HR', '${_activity.averageHeartrate!.toStringAsFixed(0)} bpm'),
              if (_activity.averageCadence != null)
                _StatRow('Cadence', '${(_activity.averageCadence! * 2).toStringAsFixed(0)} spm'),
              if (_activity.sufferScore != null && _activity.sufferScore! > 0)
                _StatRow('Suffer score', '${_activity.sufferScore}'),
            ]),
          ],
          // Splits for runs (per km); equivalent "Splits / laps" for other types (no loading spinner; data appears when ready)
          if (_loadError != null && derivedKmSplits.isEmpty && (!hasLaps || segments.isEmpty)) ...[
            const SizedBox(height: 16),
            _Section(
              title: isRun ? 'Splits (per km)' : 'Splits / laps',
              children: [
                Text(
                  'Could not load split data.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ),
          ] else if (isRun && derivedKmSplits.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Section(
              title: 'Splits (per km)',
              children: [
                _KmSplitsTable(splits: derivedKmSplits),
                const SizedBox(height: 12),
                _SplitStatsChips(splits: derivedKmSplits),
              ],
            ),
            if (hasLaps) ...[
              const SizedBox(height: 16),
              _Section(
                title: 'Laps / intervals',
                children: [
                  _IntervalsTable(segments: segments),
                ],
              ),
            ],
          ] else if (!isRun && segments.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Section(
              title: hasLaps ? 'Splits / laps' : 'Splits',
              children: [
                _IntervalsTable(segments: segments),
              ],
            ),
          ],
          if (_activity.description != null && _activity.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Section(
              title: 'Notes',
              children: [
                Text(
                  _activity.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(_activity),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Discuss with coach'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _KmSplitsTable extends StatelessWidget {
  final List<Split> splits;

  const _KmSplitsTable({required this.splits});

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );
    final cellStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurface,
    );

    final borderColor = colorScheme.outline;
    final headerBg = colorScheme.surfaceContainerHigh;
    final cellBg = colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: cellBg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(0.8),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.0),
        },
        border: TableBorder.symmetric(
          inside: BorderSide(color: borderColor.withValues(alpha: 0.5)),
          outside: BorderSide.none,
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: headerBg),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('Km', style: headerStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('Pace (/km)', style: headerStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('Time', style: headerStyle),
              ),
            ],
          ),
          ...splits.asMap().entries.map((e) {
            final i = e.key + 1;
            final s = e.value;
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('$i', style: cellStyle),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(ActivityDisplayUtils.formatPace(s.averageSpeed), style: cellStyle),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(ActivityDisplayUtils.formatDuration(s.movingTime), style: cellStyle),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _IntervalsTable extends StatelessWidget {
  final List<Split> segments;

  const _IntervalsTable({required this.segments});

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );
    final cellStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurface,
    );

    final borderColor = colorScheme.outline;
    final headerBg = colorScheme.surfaceContainerHigh;
    final cellBg = colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: cellBg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(0.8),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.0),
          3: FlexColumnWidth(1.0),
        },
        border: TableBorder.symmetric(
          inside: BorderSide(color: borderColor.withValues(alpha: 0.5)),
          outside: BorderSide.none,
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: headerBg),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('#', style: headerStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('Distance', style: headerStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('Pace (/km)', style: headerStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('Time', style: headerStyle),
              ),
            ],
          ),
          ...segments.asMap().entries.map((e) {
            final i = e.key + 1;
            final s = e.value;
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('$i', style: cellStyle),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(ActivityDisplayUtils.formatDistance(s.distance), style: cellStyle),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(ActivityDisplayUtils.formatPace(s.averageSpeed), style: cellStyle),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(ActivityDisplayUtils.formatDuration(s.movingTime), style: cellStyle),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _SplitStatsChips extends StatelessWidget {
  final List<Split> splits;

  const _SplitStatsChips({required this.splits});

  @override
  Widget build(BuildContext context) {
    final stats = ActivityDisplayUtils.getSplitStatsForDisplay(splits);
    if (stats.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: stats.map((s) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s.value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
