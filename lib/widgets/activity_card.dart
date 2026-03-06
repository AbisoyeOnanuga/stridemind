import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stridemind/models/strava_activity.dart';

class ActivityCard extends StatelessWidget {
  final StravaActivity activity;

  const ActivityCard({super.key, required this.activity});

  IconData _getIconForActivityType(String type) {
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
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getIconForActivityType(activity.type),
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    activity.name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat.yMMMd().add_jm().format(activity.startDateLocal),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${activity.distanceInKm.toStringAsFixed(2)} km',
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  activity.formattedMovingTime,
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}