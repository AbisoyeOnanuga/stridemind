import 'package:flutter/foundation.dart';

/// Notifies listeners (e.g. ActivityDashboard) to refresh the activity list.
/// Used when FCM delivers a new activity so the list updates without pull-to-refresh.
final class ActivityRefreshNotifier {
  ActivityRefreshNotifier._();

  static final ValueNotifier<int> _counter = ValueNotifier<int>(0);

  /// Listen to this to know when to refresh the activity list (e.g. after FCM activityId).
  static ValueNotifier<int> get instance => _counter;

  /// Call after fetching and upserting a new activity (e.g. from FCM).
  static void trigger() {
    _counter.value++;
  }
}
