import 'package:flutter/material.dart';
import 'package:stridemind/models/strava_activity.dart';

class WeeklySummaryPanel extends StatelessWidget {
  final List<StravaActivity> activities;

  const WeeklySummaryPanel({super.key, required this.activities});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    final weeklyActivities =
        activities.where((a) => a.startDateLocal.isAfter(weekStart)).toList();

    final double totalDistance =
        weeklyActivities.fold(0.0, (sum, a) => sum + a.distance);
    final int totalTime =
        weeklyActivities.fold(0, (sum, a) => sum + a.movingTime);
    final double totalElevation =
        weeklyActivities.fold(0.0, (sum, a) => sum + a.totalElevationGain);

    final duration = Duration(seconds: totalTime);
    final formattedTime =
        '${duration.inHours}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly summary (last 7 days)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryStat(
                  icon: Icons.straighten,
                  label: 'Total distance',
                  value: '${(totalDistance / 1000).toStringAsFixed(1)} km',
                  color: theme.colorScheme.primary,
                ),
                _SummaryStat(
                  icon: Icons.schedule,
                  label: 'Total time',
                  value: formattedTime,
                  color: theme.colorScheme.primary,
                ),
                _SummaryStat(
                  icon: Icons.terrain,
                  label: 'Total elevation',
                  value: '${totalElevation.toStringAsFixed(0)} m',
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}