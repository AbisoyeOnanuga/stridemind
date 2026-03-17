import 'package:stridemind/models/strava_activity.dart';

/// Shared formatting for activity stats (pace, duration, distance, splits).
/// Used by ActivityDetailPage and can be used by PromptService for consistency.
class ActivityDisplayUtils {
  ActivityDisplayUtils._();

  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)} m';
    }
    return '${(distanceInMeters / 1000).toStringAsFixed(2)} km';
  }

  static String formatDuration(int seconds) {
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

  static String formatPace(double speedInMps) {
    if (speedInMps <= 0) return 'N/A';
    final secondsPerKm = 1000 / speedInMps;
    final pace = Duration(seconds: secondsPerKm.round());
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(pace.inMinutes.remainder(60));
    final seconds = twoDigits(pace.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  /// Returns only splits that are ~1 km (for table/display).
  static List<Split> getKmSplits(List<Split> splits) {
    if (splits.isEmpty) return [];
    return splits.where((s) => (s.distance - 1000.0).abs() < 5.0).toList();
  }

  /// Derive ~1km splits from arbitrary segments (e.g. Strava laps/intervals).
  ///
  /// This is a best-effort fallback when Strava `splits_metric` isn't available.
  /// It assumes each segment has distance (m) and moving time (s), and allocates
  /// time proportionally when a segment crosses a km boundary.
  static List<Split> deriveKmSplitsFromSegments(List<Split> segments) {
    if (segments.isEmpty) return [];

    const targetMeters = 1000.0;
    final out = <Split>[];

    double carriedMeters = 0.0;
    double carriedSeconds = 0.0;

    for (final seg in segments) {
      final segMeters = seg.distance;
      final segSeconds = seg.movingTime.toDouble();
      if (segMeters <= 0 || segSeconds <= 0) continue;

      double remainingMeters = segMeters;
      double remainingSeconds = segSeconds;

      while (remainingMeters > 0) {
        final needMeters = targetMeters - carriedMeters;
        if (needMeters <= 0) {
          final t = carriedSeconds.round().clamp(1, 24 * 60 * 60);
          out.add(Split(distance: targetMeters, movingTime: t, averageSpeed: targetMeters / t));
          carriedMeters = 0.0;
          carriedSeconds = 0.0;
          continue;
        }

        if (remainingMeters >= needMeters) {
          final fraction = needMeters / remainingMeters;
          final takeSeconds = remainingSeconds * fraction;
          carriedMeters += needMeters;
          carriedSeconds += takeSeconds;

          remainingMeters -= needMeters;
          remainingSeconds -= takeSeconds;

          final t = carriedSeconds.round().clamp(1, 24 * 60 * 60);
          out.add(Split(distance: targetMeters, movingTime: t, averageSpeed: targetMeters / t));
          carriedMeters = 0.0;
          carriedSeconds = 0.0;
        } else {
          carriedMeters += remainingMeters;
          carriedSeconds += remainingSeconds;
          remainingMeters = 0;
          remainingSeconds = 0;
        }
      }
    }

    return out;
  }

  /// Returns compact splits text: one line of CSV plus a pacing stats line
  /// (same format as coach prompt). Returns empty string if splits empty.
  static String formatSplitsCompact(List<Split> splits) {
    final kmSplits = getKmSplits(splits);
    if (kmSplits.isEmpty) return '';

    final csv = kmSplits.map((s) => formatPace(s.averageSpeed)).join(',');
    final stats = _computeSplitStatsString(kmSplits);
    return 'Splits (${kmSplits.length} km, mm:ss/km): $csv\n$stats';
  }

  /// Pacing stats as label/value pairs for UI (table, chips).
  static List<({String label, String value})> getSplitStatsForDisplay(List<Split> splits) {
    final kmSplits = getKmSplits(splits);
    if (kmSplits.isEmpty) return [];

    final avgSpeed =
        kmSplits.map((s) => s.averageSpeed).reduce((a, b) => a + b) / kmSplits.length;
    final firstSplit = kmSplits.first;
    final lastSplit = kmSplits.last;

    final mid = kmSplits.length ~/ 2;
    final firstHalf = kmSplits.sublist(0, mid.clamp(1, kmSplits.length));
    final secondHalf = kmSplits.sublist(mid.clamp(0, kmSplits.length));
    final firstAvg =
        firstHalf.map((s) => s.averageSpeed).reduce((a, b) => a + b) / firstHalf.length;
    final secondAvg =
        secondHalf.map((s) => s.averageSpeed).reduce((a, b) => a + b) / secondHalf.length;

    final fastest = kmSplits.reduce((a, b) => a.averageSpeed > b.averageSpeed ? a : b);
    final slowest = kmSplits.reduce((a, b) => a.averageSpeed < b.averageSpeed ? a : b);
    final fastestIdx = kmSplits.indexOf(fastest) + 1;
    final slowestIdx = kmSplits.indexOf(slowest) + 1;

    final firstPaceSec = 1000 / firstAvg;
    final secondPaceSec = 1000 / secondAvg;
    final diffSec = (secondPaceSec - firstPaceSec).round();
    String trend;
    if (diffSec > 10) {
      trend = 'Positive split (+${diffSec}s/km 2nd half)';
    } else if (diffSec < -10) {
      trend = 'Negative split (${-diffSec}s/km faster 2nd half)';
    } else {
      trend = 'Even pacing';
    }

    return [
      (label: 'Avg pace', value: '${formatPace(avgSpeed)}/km'),
      (label: 'First km split', value: formatPace(firstSplit.averageSpeed)),
      (label: 'Last km split', value: formatPace(lastSplit.averageSpeed)),
      (label: 'Fastest km', value: '#$fastestIdx ${formatPace(fastest.averageSpeed)}'),
      (label: 'Slowest km', value: '#$slowestIdx ${formatPace(slowest.averageSpeed)}'),
      (label: 'Trend', value: trend),
    ];
  }

  static String _computeSplitStatsString(List<Split> splits) {
    final stats = getSplitStatsForDisplay(splits);
    if (stats.isEmpty) return '';
    return stats.map((s) => '${s.label}: ${s.value}').join(' | ');
  }
}
