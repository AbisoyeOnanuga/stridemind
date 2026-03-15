import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyThemeMode = 'theme_mode';

/// Persists and loads app theme preference: light, dark, or system.
/// [themeModeNotifier] updates when [setThemeMode] is called so the app can rebuild without relying on callbacks.
class ThemeService {
  static const String valueLight = 'light';
  static const String valueDark = 'dark';
  static const String valueSystem = 'system';

  /// Notifier updated by [setThemeMode]. Main app listens to apply theme even when Settings callback was null.
  static final ValueNotifier<ThemeMode?> themeModeNotifier = ValueNotifier<ThemeMode?>(null);
  static SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  Future<ThemeMode> getThemeMode() async {
    final prefs = await _prefs();
    final value = prefs.getString(_keyThemeMode) ?? valueSystem;
    switch (value) {
      case valueLight:
        return ThemeMode.light;
      case valueDark:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    // Apply immediately for snappy UI; persist in background.
    themeModeNotifier.value = mode;

    final prefs = await _prefs();
    final value = mode == ThemeMode.light
        ? valueLight
        : mode == ThemeMode.dark
            ? valueDark
            : valueSystem;
    await prefs.setString(_keyThemeMode, value);
  }
}
