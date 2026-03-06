import 'package:shared_preferences/shared_preferences.dart';

/// Which app is used for activity data: Strava or Samsung Health (Health Connect).
/// Only one can be active at a time.
class ActivitySourceService {
  static const String _keyActiveSource = 'active_activity_source';
  static const String valueStrava = 'strava';
  static const String valueSamsungHealth = 'samsung_health';

  Future<String?> getActiveSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActiveSource);
  }

  Future<void> setActiveSource(String? source) async {
    final prefs = await SharedPreferences.getInstance();
    if (source == null) {
      await prefs.remove(_keyActiveSource);
    } else {
      await prefs.setString(_keyActiveSource, source);
    }
  }

  /// Returns the effective active source: if null and [stravaConnected], defaults to strava for backwards compatibility.
  Future<String?> getEffectiveActiveSource({bool stravaConnected = false}) async {
    final active = await getActiveSource();
    if (active != null) return active;
    return stravaConnected ? valueStrava : null;
  }
}
