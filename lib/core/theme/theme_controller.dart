import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

/// Global theme controller that holds the current [ThemeMode]
/// and lets any screen toggle between Light / Dark / System.
///
/// Exposed as a global singleton [themeController] and via a Riverpod-style
/// provider so both ValueListenableBuilder and ref.watch can react to toggles.
/// Persists the chosen mode via SharedPreferences across restarts.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.light) {
    _load();
  }

  /// Global singleton used by non-Riverpod screens (e.g. existing Stateless
  /// entry point). Toggling it triggers a rebuild of the app via
  /// ValueListenableBuilder in `main.dart`.
  static final ThemeController instance = ThemeController();

  static const String _prefKey = 'theme_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey);
      switch (stored) {
        case 'dark':
          value = ThemeMode.dark;
          break;
        case 'system':
          value = ThemeMode.system;
          break;
        default:
          value = ThemeMode.light;
      }
    } catch (_) {
      value = ThemeMode.light;
    }
  }

  bool get isDark => value == ThemeMode.dark;

  @override
  set value(ThemeMode newValue) {
    super.value = newValue;
    AppTheme.isDarkMode = newValue == ThemeMode.dark ||
        (newValue == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
  }

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {
      // persist is best-effort
    }
  }

  Future<void> toggle() async {
    await setMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Convenience: returns the active theme (light or dark) for inline
  /// theming in screens that don't use Theme.of(context).
  ThemeData get currentTheme =>
      isDark ? AppTheme.darkTheme : AppTheme.lightTheme;
}
