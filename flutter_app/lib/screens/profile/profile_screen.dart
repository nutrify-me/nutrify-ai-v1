import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/progress_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/fitness_provider.dart';
import '../../providers/nutrition_provider.dart';
import '../../services/workout_cache_service.dart';
import '../../widgets/streak_card.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _goalsMetCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateGoalsMet());
  }

  Future<void> _calculateGoalsMet() async {
    int met = 0;
    try {
      // Goal 1: Hit workout target this week
      final cache = WorkoutCacheService.instance;
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      int weeklyWorkouts = 0;
      for (int i = 0; i < 7; i++) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        if (day.isAfter(now)) break;
        weeklyWorkouts += (await cache.getWorkoutsForDate(day)).length;
      }
      final fitnessState = ref.read(fitnessNotifierProvider);
      final weeklyTarget = fitnessState.currentPlan?.workouts.length ?? 4;
      if (weeklyWorkouts >= weeklyTarget && weeklyTarget > 0) met++;

      // Goal 2: Has an active nutrition plan
      final nutritionState = ref.read(nutritionNotifierProvider);
      if (nutritionState.currentPlan != null) met++;

      // Goal 3: Logged progress this week
      final progressState = ref.read(progressNotifierProvider);
      final mondayStr = DateTime(monday.year, monday.month, monday.day).toIso8601String().split('T')[0];
      final hasRecentProgress = progressState.entries.any(
        (e) => e.entryDate.compareTo(mondayStr) >= 0,
      );
      if (hasRecentProgress) met++;

      // Goal 4: Maintained streak (at least 2 days)
      final streakAsync = ref.read(streakProvider);
      streakAsync.whenData((streak) {
        if (streak != null && streak.currentStreak >= 2) met++;
      });
    } catch (_) {}

    if (mounted) setState(() => _goalsMetCount = met);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.user;
    final profile = authState.profile;
    final progressState = ref.watch(progressNotifierProvider);
    final gamificationStats = ref.watch(gamificationStatsProvider);

    // Calculate stats from progress entries
    final daysActive = progressState.entries.length;
    final goalsMetCount = _goalsMetCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              context.push('/edit-profile');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Profile Header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        user?.firstName.isNotEmpty == true ? user!.firstName.substring(0, 1).toUpperCase() : 'U',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${user?.firstName ?? ''} ${user?.lastName ?? ''}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user?.email ?? '',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Stats Cards
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(context, 'Days Active', daysActive.toString(), Icons.calendar_today),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(context, 'Goals Met', goalsMetCount.toString(), Icons.emoji_events),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: gamificationStats.when(
                    data: (stats) => _buildStatCard(
                      context,
                      'Points',
                      stats?.totalPoints.toString() ?? '0',
                      Icons.star,
                    ),
                    loading: () => _buildStatCard(context, 'Points', '--', Icons.star),
                    error: (_, __) => _buildStatCard(context, 'Points', '0', Icons.star),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Streak Card
            const StreakStatsCard(),

            const SizedBox(height: 24),

            // Settings
            _buildSettingsSection(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _buildSettingsTile(
                context,
                'Achievements',
                'View your badges and progress',
                Icons.emoji_events,
                onTap: () {
                  context.push('/achievements');
                },
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                context,
                'Subscription',
                'Manage your subscription plan',
                Icons.card_membership,
                onTap: () {
                  context.push('/subscription');
                },
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                context,
                'Personal Information',
                'Update your profile details',
                Icons.person_outline,
                onTap: () {
                  context.push('/edit-profile');
                },
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                context,
                'Goals & Preferences',
                'Fitness and nutrition goals',
                Icons.track_changes,
                onTap: () {
                  context.push('/edit-profile');
                },
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                context,
                'Notifications',
                'Manage your notifications',
                Icons.notifications,
                onTap: () {
                  context.push('/settings');
                },
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                context,
                'Privacy & Security',
                'Account security settings',
                Icons.shield_outlined,
                onTap: () {
                  context.push('/settings');
                },
              ),
              const Divider(height: 1),
              _buildSettingsTile(
                context,
                'Help & Support',
                'FAQs and contact support',
                Icons.help_outline,
                onTap: () {
                  // TODO: Navigate to help
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Logout Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );

              if (shouldLogout == true) {
                // Show loading while syncing
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Syncing data before logout...'),
                    duration: Duration(seconds: 2),
                  ),
                );

                final result = await ref.read(authNotifierProvider.notifier).logout();

                if (result == LogoutResult.pendingSyncFailed) {
                  // Show warning dialog
                  if (context.mounted) {
                    final forceLogout = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Unsaved Workout Data'),
                        content: const Text(
                          'You have workouts that haven\'t been synced to the cloud. '
                          'If you log out now, this data may be lost.\n\n'
                          'Do you want to logout anyway?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.error,
                            ),
                            child: const Text('Logout Anyway'),
                          ),
                        ],
                      ),
                    );

                    if (forceLogout == true) {
                      await ref.read(authNotifierProvider.notifier).forceLogout();
                    }
                  }
                }
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}