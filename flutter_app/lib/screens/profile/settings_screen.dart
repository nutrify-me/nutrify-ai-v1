import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../services/cache_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ─── Appearance ─────────────────────────
          _SectionHeader('Appearance'),
          _buildThemeTile(context, settings, notifier),
          const Divider(height: 1, indent: 72),

          // ─── Units ──────────────────────────────
          _SectionHeader('Units & Measurements'),
          _buildUnitTile(context, settings, notifier),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 4),
            child: Text(
              settings.unitSystem == UnitSystem.metric
                  ? 'Weight: kg  ·  Height: cm  ·  Distance: km  ·  Pace: min/km'
                  : 'Weight: lbs  ·  Height: ft/in  ·  Distance: mi  ·  Pace: min/mi',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
          const Divider(height: 16, indent: 72),

          // ─── Notifications ──────────────────────
          _SectionHeader('Notifications'),
          _NotifToggle(
            icon: Icons.wb_sunny_outlined,
            title: 'Daily Reminder',
            subtitle: 'Morning briefing at ${settings.dailyReminderTime}',
            value: settings.notifyDailyReminder,
            onChanged: notifier.setNotifyDailyReminder,
          ),
          if (settings.notifyDailyReminder)
            _buildReminderTimeTile(context, settings, notifier),
          _NotifToggle(
            icon: Icons.fitness_center,
            title: 'Workout Reminders',
            subtitle: 'Remind you to work out on scheduled days',
            value: settings.notifyWorkoutReminder,
            onChanged: notifier.setNotifyWorkoutReminder,
          ),
          _NotifToggle(
            icon: Icons.restaurant_outlined,
            title: 'Meal Reminders',
            subtitle: 'Remind you to log meals',
            value: settings.notifyMealReminder,
            onChanged: notifier.setNotifyMealReminder,
          ),
          _NotifToggle(
            icon: Icons.bar_chart,
            title: 'Weekly Report',
            subtitle: 'Summary of your weekly progress',
            value: settings.notifyWeeklyReport,
            onChanged: notifier.setNotifyWeeklyReport,
          ),
          _NotifToggle(
            icon: Icons.emoji_events_outlined,
            title: 'Achievements',
            subtitle: 'Celebrate when you hit milestones',
            value: settings.notifyAchievements,
            onChanged: notifier.setNotifyAchievements,
          ),
          const Divider(height: 16, indent: 72),

          // ─── Data & Storage ─────────────────────
          _SectionHeader('Data & Storage'),
          ListTile(
            leading: _iconBox(Icons.cached, Colors.orange),
            title: const Text('Clear Cache'),
            subtitle: const Text('Free up space by clearing cached data'),
            onTap: () => _showClearCacheDialog(context),
          ),
          ListTile(
            leading: _iconBox(Icons.download_outlined, Colors.blue),
            title: const Text('Export Data'),
            subtitle: const Text('Download your data as CSV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export coming soon!')),
              );
            },
          ),
          const Divider(height: 16, indent: 72),

          // ─── About ──────────────────────────────
          _SectionHeader('About'),
          const ListTile(
            leading: _iconBoxStatic(Icons.info_outline, Colors.grey),
            title: Text('Version'),
            subtitle: Text('1.0.0 (Nutrify-AI)'),
          ),
          ListTile(
            leading: _iconBox(Icons.description_outlined, Colors.grey),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () {},
          ),
          ListTile(
            leading: _iconBox(Icons.privacy_tip_outlined, Colors.grey),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () {},
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Theme selector ────────────────────────────────────

  Widget _buildThemeTile(
      BuildContext context, AppSettings settings, SettingsNotifier notifier) {
    return ListTile(
      leading: _iconBox(
        settings.theme == ThemePreference.dark
            ? Icons.dark_mode
            : settings.theme == ThemePreference.light
                ? Icons.light_mode
                : Icons.brightness_auto,
        Colors.deepPurple,
      ),
      title: const Text('Theme'),
      subtitle: Text(_themeLabel(settings.theme)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Choose Theme',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                for (final t in ThemePreference.values)
                  RadioListTile<ThemePreference>(
                    value: t,
                    groupValue: settings.theme,
                    title: Text(_themeLabel(t)),
                    secondary: Icon(_themeIcon(t)),
                    onChanged: (v) {
                      if (v != null) notifier.setTheme(v);
                      Navigator.pop(context);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  String _themeLabel(ThemePreference t) {
    switch (t) {
      case ThemePreference.system:
        return 'System Default';
      case ThemePreference.light:
        return 'Light';
      case ThemePreference.dark:
        return 'Dark';
    }
  }

  IconData _themeIcon(ThemePreference t) {
    switch (t) {
      case ThemePreference.system:
        return Icons.brightness_auto;
      case ThemePreference.light:
        return Icons.light_mode;
      case ThemePreference.dark:
        return Icons.dark_mode;
    }
  }

  // ─── Unit selector ─────────────────────────────────────

  Widget _buildUnitTile(
      BuildContext context, AppSettings settings, SettingsNotifier notifier) {
    return ListTile(
      leading: _iconBox(Icons.straighten, Colors.teal),
      title: const Text('Unit System'),
      trailing: SegmentedButton<UnitSystem>(
        segments: const [
          ButtonSegment(value: UnitSystem.metric, label: Text('Metric')),
          ButtonSegment(value: UnitSystem.imperial, label: Text('Imperial')),
        ],
        selected: {settings.unitSystem},
        onSelectionChanged: (s) => notifier.setUnitSystem(s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  // ─── Reminder time picker ──────────────────────────────

  Widget _buildReminderTimeTile(
      BuildContext context, AppSettings settings, SettingsNotifier notifier) {
    return ListTile(
      leading: const SizedBox(width: 40),
      title: const Text('Reminder Time'),
      subtitle: Text(settings.dailyReminderTime),
      trailing: const Icon(Icons.access_time),
      onTap: () async {
        final parts = settings.dailyReminderTime.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime:
              TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
        );
        if (picked != null) {
          notifier.setDailyReminderTime(
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
          );
        }
      },
    );
  }

  // ─── Clear cache dialog ────────────────────────────────

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text(
          'This will clear locally cached data. Your account data on the server will not be affected. '
          'The app may be slower until caches are rebuilt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await CacheService.instance.clearAll();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cache cleared'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable widgets ────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NotifToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: _iconBox(icon, value ? Colors.green : Colors.grey),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }
}

Widget _iconBox(IconData icon, Color color) {
  return Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: color, size: 20),
  );
}

class _iconBoxStatic extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _iconBoxStatic(this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
