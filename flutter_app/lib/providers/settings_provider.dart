import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Settings State ──────────────────────────────────────

class AppSettings {
  final ThemePreference theme;
  final UnitSystem unitSystem;
  final bool notifyDailyReminder;
  final bool notifyWorkoutReminder;
  final bool notifyMealReminder;
  final bool notifyWeeklyReport;
  final bool notifyAchievements;
  final String dailyReminderTime; // HH:mm
  final String locale;

  const AppSettings({
    this.theme = ThemePreference.system,
    this.unitSystem = UnitSystem.metric,
    this.notifyDailyReminder = true,
    this.notifyWorkoutReminder = true,
    this.notifyMealReminder = false,
    this.notifyWeeklyReport = true,
    this.notifyAchievements = true,
    this.dailyReminderTime = '08:00',
    this.locale = 'en',
  });

  AppSettings copyWith({
    ThemePreference? theme,
    UnitSystem? unitSystem,
    bool? notifyDailyReminder,
    bool? notifyWorkoutReminder,
    bool? notifyMealReminder,
    bool? notifyWeeklyReport,
    bool? notifyAchievements,
    String? dailyReminderTime,
    String? locale,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      unitSystem: unitSystem ?? this.unitSystem,
      notifyDailyReminder: notifyDailyReminder ?? this.notifyDailyReminder,
      notifyWorkoutReminder: notifyWorkoutReminder ?? this.notifyWorkoutReminder,
      notifyMealReminder: notifyMealReminder ?? this.notifyMealReminder,
      notifyWeeklyReport: notifyWeeklyReport ?? this.notifyWeeklyReport,
      notifyAchievements: notifyAchievements ?? this.notifyAchievements,
      dailyReminderTime: dailyReminderTime ?? this.dailyReminderTime,
      locale: locale ?? this.locale,
    );
  }

  // Display helpers
  String get weightUnit => unitSystem == UnitSystem.metric ? 'kg' : 'lbs';
  String get heightUnit => unitSystem == UnitSystem.metric ? 'cm' : 'ft/in';
  String get distanceUnit => unitSystem == UnitSystem.metric ? 'km' : 'mi';
  String get paceUnit => unitSystem == UnitSystem.metric ? 'min/km' : 'min/mi';

  double convertWeight(double kg) =>
      unitSystem == UnitSystem.metric ? kg : kg * 2.20462;
  double convertHeight(double cm) =>
      unitSystem == UnitSystem.metric ? cm : cm / 2.54;
  double convertDistance(double km) =>
      unitSystem == UnitSystem.metric ? km : km * 0.621371;
}

enum ThemePreference { system, light, dark }

enum UnitSystem { metric, imperial }

// ─── Settings Notifier ───────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  static const _keyTheme = 'settings_theme';
  static const _keyUnits = 'settings_units';
  static const _keyNotifyDaily = 'settings_notify_daily';
  static const _keyNotifyWorkout = 'settings_notify_workout';
  static const _keyNotifyMeal = 'settings_notify_meal';
  static const _keyNotifyWeekly = 'settings_notify_weekly';
  static const _keyNotifyAchievements = 'settings_notify_achievements';
  static const _keyReminderTime = 'settings_reminder_time';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      theme: ThemePreference.values[prefs.getInt(_keyTheme) ?? 0],
      unitSystem: UnitSystem.values[prefs.getInt(_keyUnits) ?? 0],
      notifyDailyReminder: prefs.getBool(_keyNotifyDaily) ?? true,
      notifyWorkoutReminder: prefs.getBool(_keyNotifyWorkout) ?? true,
      notifyMealReminder: prefs.getBool(_keyNotifyMeal) ?? false,
      notifyWeeklyReport: prefs.getBool(_keyNotifyWeekly) ?? true,
      notifyAchievements: prefs.getBool(_keyNotifyAchievements) ?? true,
      dailyReminderTime: prefs.getString(_keyReminderTime) ?? '08:00',
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, state.theme.index);
    await prefs.setInt(_keyUnits, state.unitSystem.index);
    await prefs.setBool(_keyNotifyDaily, state.notifyDailyReminder);
    await prefs.setBool(_keyNotifyWorkout, state.notifyWorkoutReminder);
    await prefs.setBool(_keyNotifyMeal, state.notifyMealReminder);
    await prefs.setBool(_keyNotifyWeekly, state.notifyWeeklyReport);
    await prefs.setBool(_keyNotifyAchievements, state.notifyAchievements);
    await prefs.setString(_keyReminderTime, state.dailyReminderTime);
  }

  void setTheme(ThemePreference theme) {
    state = state.copyWith(theme: theme);
    _save();
  }

  void setUnitSystem(UnitSystem units) {
    state = state.copyWith(unitSystem: units);
    _save();
  }

  void setNotifyDailyReminder(bool v) {
    state = state.copyWith(notifyDailyReminder: v);
    _save();
  }

  void setNotifyWorkoutReminder(bool v) {
    state = state.copyWith(notifyWorkoutReminder: v);
    _save();
  }

  void setNotifyMealReminder(bool v) {
    state = state.copyWith(notifyMealReminder: v);
    _save();
  }

  void setNotifyWeeklyReport(bool v) {
    state = state.copyWith(notifyWeeklyReport: v);
    _save();
  }

  void setNotifyAchievements(bool v) {
    state = state.copyWith(notifyAchievements: v);
    _save();
  }

  void setDailyReminderTime(String time) {
    state = state.copyWith(dailyReminderTime: time);
    _save();
  }
}

// ─── Providers ───────────────────────────────────────────

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);
