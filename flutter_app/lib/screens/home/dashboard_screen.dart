import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/nutrition_provider.dart';
import '../../providers/fitness_provider.dart';
import '../../providers/progress_provider.dart';
import '../../models/progress.dart';
import '../../widgets/common/loading_overlay.dart';
import '../../widgets/dashboard/stats_card.dart';
import '../../widgets/dashboard/quick_actions.dart';
import '../../widgets/dashboard/recent_meals_card.dart';
import '../../widgets/dashboard/workout_progress_card.dart';
import '../../widgets/dashboard/water_intake_card.dart';
import '../../widgets/streak_card.dart';
import '../../providers/gamification_provider.dart';
import '../../services/workout_cache_service.dart';
import '../../providers/workout_session_provider.dart';
import '../../providers/settings_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _weeklyCompletedWorkouts = 0;

  @override
  void initState() {
    super.initState();
    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nutritionNotifierProvider.notifier).loadCurrentPlan();
      ref.read(fitnessNotifierProvider.notifier).loadCurrentPlan();
      ref.read(progressNotifierProvider.notifier).loadProgressEntries();

      // Refresh streak data to show updated streak after workouts
      ref.invalidate(streakProvider);

      // Load weekly completed workouts from local cache
      _loadWeeklyWorkouts();
    });
  }

  Future<void> _loadWeeklyWorkouts() async {
    try {
      final cache = WorkoutCacheService.instance;
      final now = DateTime.now();
      // Monday of this week
      final monday = now.subtract(Duration(days: now.weekday - 1));
      int count = 0;
      for (int i = 0; i < 7; i++) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        if (day.isAfter(now)) break;
        final workouts = await cache.getWorkoutsForDate(day);
        count += workouts.length;
      }
      if (mounted) {
        setState(() => _weeklyCompletedWorkouts = count);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.user;
    final profile = authState.profile;
    final nutritionState = ref.watch(nutritionNotifierProvider);
    final fitnessState = ref.watch(fitnessNotifierProvider);
    final progressState = ref.watch(progressNotifierProvider);

    final isLoading = nutritionState.isLoading || fitnessState.isLoading;

    // Get calorie target from AI-generated nutrition plan
    final calorieTarget = nutritionState.currentPlan?.dailyCalories ??
                         (profile != null ? _calculateCalorieTarget(profile) : 2000);

    // Calculate current calories from today's meals in the AI-generated plan
    final todayWeekday = DateTime.now().weekday;
    final todaysMeals = nutritionState.currentPlan?.meals.where(
      (meal) => _getDayNumber(meal.day) == todayWeekday,
    ).toList() ?? [];

    final currentCalories = todaysMeals.fold<int>(0, (sum, dailyMeal) {
      return sum +
             dailyMeal.breakfast.fold<int>(0, (s, m) => s + m.calories) +
             dailyMeal.lunch.fold<int>(0, (s, m) => s + m.calories) +
             dailyMeal.dinner.fold<int>(0, (s, m) => s + m.calories) +
             dailyMeal.snacks.fold<int>(0, (s, m) => s + m.calories);
    });

    final calorieProgress = calorieTarget > 0 ? currentCalories / calorieTarget : 0.0;

    // Get today's progress entry for water intake
    final today = DateTime.now().toIso8601String().split('T')[0];
    ProgressEntry? todayProgress;

    try {
      todayProgress = progressState.entries.firstWhere(
        (entry) => entry.entryDate.startsWith(today),
      );
    } catch (e) {
      // No entry for today
      todayProgress = null;
    }

    // Calculate water intake (convert ml to glasses, ~250ml per glass)
    final waterGlasses = (todayProgress?.waterIntakeMl ?? 0) ~/ 250;
    final waterTarget = 8; // Standard recommendation

    // Calculate weekly workouts from fitness plan
    final weeklyWorkoutTarget = fitnessState.currentPlan?.workouts.length ?? 4;
    final completedWorkouts = _weeklyCompletedWorkouts;

    return Scaffold(
      body: LoadingOverlay(
        isLoading: isLoading,
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverAppBar(
              expandedHeight: 120,
              floating: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Good ${_getGreeting()}, ${user?.firstName ?? 'there'}!',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile != null && profile.goals != null && profile.goals!.isNotEmpty
                            ? 'Working towards ${_formatGoal(profile.goals!.first)}'
                            : 'Ready to crush your goals today?',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.person_outlined),
                  onPressed: () => context.go('/profile'),
                ),
              ],
            ),

            // Content
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Streak Card - Top for motivation
                  StreakCard(
                    onTap: () => context.go('/achievements'),
                  ),

                  // Restored workout session banner
                  Builder(builder: (context) {
                    final sessionState = ref.watch(workoutSessionProvider);
                    if (!sessionState.hasActiveSession) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                        color: Colors.orange.shade50,
                        child: ListTile(
                          leading: Icon(Icons.fitness_center, color: Colors.orange.shade700),
                          title: Text(
                            'Resume: ${sessionState.activeSession?.workoutName ?? "Workout"}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('${(sessionState.elapsedSeconds ~/ 60)}min elapsed'),
                          trailing: FilledButton(
                            onPressed: () => context.go('/fitness'),
                            child: const Text('Resume'),
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 24),

                  // Quick Stats Row
                  Row(
                    children: [
                      Expanded(
                        child: StatsCard(
                          title: 'Calories Today',
                          value: currentCalories.toString(),
                          target: '/ ${calorieTarget.toStringAsFixed(0)}',
                          progress: calorieProgress,
                          color: Theme.of(context).colorScheme.primary,
                          icon: Icons.local_fire_department,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Water Intake Card - Quick tracking
                  const WaterIntakeCard(),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: Builder(builder: (context) {
                          final settings = ref.watch(settingsProvider);
                          final weightKg = profile?.weight;
                          final displayWeight = weightKg != null
                              ? settings.convertWeight(weightKg).toStringAsFixed(1)
                              : '--';
                          return StatsCard(
                            title: 'Current Weight',
                            value: displayWeight,
                            target: settings.weightUnit,
                            progress: 0.0,
                            color: Theme.of(context).colorScheme.secondary,
                            icon: Icons.monitor_weight,
                          );
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatsCard(
                          title: 'Workouts',
                          value: completedWorkouts.toString(),
                          target: '/ $weeklyWorkoutTarget per week',
                          progress: weeklyWorkoutTarget > 0 ? completedWorkouts / weeklyWorkoutTarget : 0.0,
                          color: Colors.indigo,
                          icon: Icons.fitness_center,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Quick Actions
                  const QuickActions(),

                  const SizedBox(height: 24),

                  // Today's Nutrition
                  RecentMealsCard(
                    breakfastMeals: nutritionState.currentPlan?.meals
                        .where((meal) => meal.day == DateTime.now().weekday.toString())
                        .expand((meal) => meal.breakfast)
                        .toList(),
                    lunchMeals: nutritionState.currentPlan?.meals
                        .where((meal) => meal.day == DateTime.now().weekday.toString())
                        .expand((meal) => meal.lunch)
                        .toList(),
                    snackMeals: nutritionState.currentPlan?.meals
                        .where((meal) => meal.day == DateTime.now().weekday.toString())
                        .expand((meal) => meal.snacks)
                        .toList(),
                    dinnerMeals: nutritionState.currentPlan?.meals
                        .where((meal) => meal.day == DateTime.now().weekday.toString())
                        .expand((meal) => meal.dinner)
                        .toList(),
                    aiSuggestion: nutritionState.currentPlan != null
                        ? 'You\'re on track! Keep up the great work.'
                        : null,
                    onViewAll: () => context.go('/nutrition'),
                  ),

                  const SizedBox(height: 16),

                  // Workout Progress
                  WorkoutProgressCard(
                    workouts: fitnessState.currentPlan?.workouts
                        .expand((daily) => daily.workouts)
                        .toList(),
                    completedCount: completedWorkouts,
                    onViewAll: () => context.go('/fitness'),
                    onStartWorkout: (workout) {
                      // TODO: Navigate to workout detail/start screen
                      context.go('/fitness');
                    },
                  ),

                  const SizedBox(height: 100), // Bottom padding for navigation
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'morning';
    } else if (hour < 17) {
      return 'afternoon';
    } else {
      return 'evening';
    }
  }

  int _calculateCalorieTarget(profile) {
    // Basic calorie calculation based on profile
    // BMR calculation (Mifflin-St Jeor Equation)
    if (profile.age == null || profile.weight == null || profile.height == null || profile.gender == null) {
      return 2000; // Default
    }

    double bmr;
    if (profile.gender?.toLowerCase() == 'male') {
      bmr = (10 * profile.weight!) + (6.25 * profile.height!) - (5 * profile.age!) + 5;
    } else {
      bmr = (10 * profile.weight!) + (6.25 * profile.height!) - (5 * profile.age!) - 161;
    }

    // Activity multiplier
    double activityMultiplier = 1.2; // sedentary default
    switch (profile.activityLevel?.toLowerCase()) {
      case 'sedentary':
        activityMultiplier = 1.2;
        break;
      case 'lightly_active':
        activityMultiplier = 1.375;
        break;
      case 'moderately_active':
        activityMultiplier = 1.55;
        break;
      case 'very_active':
        activityMultiplier = 1.725;
        break;
      case 'extremely_active':
        activityMultiplier = 1.9;
        break;
    }

    double tdee = bmr * activityMultiplier;

    // Adjust for goal
    switch (profile.primaryGoal?.toLowerCase()) {
      case 'weight_loss':
        return (tdee - 500).round(); // 500 cal deficit
      case 'muscle_gain':
        return (tdee + 300).round(); // 300 cal surplus
      case 'maintenance':
        return tdee.round();
      default:
        return tdee.round();
    }
  }

  String _formatGoal(String? goal) {
    if (goal == null) return 'your goals';
    return goal.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  }

  int _getDayNumber(String day) {
    final dayLower = day.toLowerCase();
    switch (dayLower) {
      case 'monday': return 1;
      case 'tuesday': return 2;
      case 'wednesday': return 3;
      case 'thursday': return 4;
      case 'friday': return 5;
      case 'saturday': return 6;
      case 'sunday': return 7;
      default: return 1;
    }
  }
}