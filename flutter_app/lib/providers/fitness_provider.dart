import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/fitness.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';
import '../services/workout_cache_service.dart';
import 'auth_provider.dart';

final _logger = Logger();

// Weekly stats model
class WeeklyWorkoutStats {
  final int completedWorkouts;
  final double totalDurationHours;
  final int totalCaloriesBurned;

  const WeeklyWorkoutStats({
    this.completedWorkouts = 0,
    this.totalDurationHours = 0.0,
    this.totalCaloriesBurned = 0,
  });
}

// Fitness state
class FitnessState {
  final WorkoutPlan? currentPlan;
  final bool isLoading;
  final String? error;
  final WeeklyWorkoutStats weeklyStats;
  final List<Map<String, dynamic>> workoutLogs;
  final bool isFromLocalCache;

  const FitnessState({
    this.currentPlan,
    this.isLoading = false,
    this.error,
    this.weeklyStats = const WeeklyWorkoutStats(),
    this.workoutLogs = const [],
    this.isFromLocalCache = false,
  });

  FitnessState copyWith({
    WorkoutPlan? currentPlan,
    bool? isLoading,
    String? error,
    WeeklyWorkoutStats? weeklyStats,
    List<Map<String, dynamic>>? workoutLogs,
    bool? isFromLocalCache,
  }) {
    return FitnessState(
      currentPlan: currentPlan ?? this.currentPlan,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      weeklyStats: weeklyStats ?? this.weeklyStats,
      workoutLogs: workoutLogs ?? this.workoutLogs,
      isFromLocalCache: isFromLocalCache ?? this.isFromLocalCache,
    );
  }
}

// Fitness notifier
class FitnessNotifier extends StateNotifier<FitnessState> {
  final ApiService _apiService;
  bool _hasLoadedOnce = false;
  String? _currentUserId;

  FitnessNotifier(this._apiService) : super(const FitnessState());

  void setUserId(String userId) {
    _currentUserId = userId;
  }

  /// Reset state when a new user logs in
  void resetForNewUser(String newUserId) {
    _currentUserId = newUserId;
    _hasLoadedOnce = false;
    state = const FitnessState();
    _logger.d('FitnessNotifier reset for new user: $newUserId');
  }

  Future<void> loadCurrentPlan({bool forceRefresh = false}) async {
    // Skip loading if we already have a plan and this isn't a force refresh
    if (!forceRefresh && _hasLoadedOnce && state.currentPlan != null) {
      return;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);

      // Try to load from local cache first (instant)
      if (_currentUserId != null && !forceRefresh) {
        final localPlan = await LocalDatabase.getFitnessPlan(_currentUserId!);
        if (localPlan != null) {
          _logger.d('Loaded fitness plan from local cache');
          state = state.copyWith(
            currentPlan: localPlan,
            isLoading: false,
            isFromLocalCache: true,
          );
          _hasLoadedOnce = true;

          // Sync from server in background
          _syncFromServerInBackground();
          return;
        }
      }

      // No local cache, fetch from server (use RequestCacheService)
      final plan = await _apiService.getCurrentWorkoutPlan(forceRefresh: forceRefresh);
      state = state.copyWith(
        currentPlan: plan,
        isLoading: false,
        isFromLocalCache: false,
      );

      // Save to local cache
      if (plan != null && _currentUserId != null) {
        await LocalDatabase.saveFitnessPlan(plan, _currentUserId!);
        _logger.d('Saved fitness plan to local cache');
      }

      _hasLoadedOnce = true;
    } catch (e) {
      // If it's a 404, that's expected - no plan exists yet
      final errorMsg = e.toString();
      if (errorMsg.contains('404') || errorMsg.contains('No workout plan found')) {
        state = state.copyWith(
          currentPlan: null,
          isLoading: false,
          error: null, // Clear error - this is an expected state
        );
      } else {
        state = state.copyWith(
          error: errorMsg,
          isLoading: false,
        );
      }
      _hasLoadedOnce = true;
    }
  }

  /// Sync from server in background (doesn't block UI)
  Future<void> _syncFromServerInBackground() async {
    try {
      final plan = await _apiService.getCurrentWorkoutPlan(forceRefresh: true);
      if (plan != null) {
        // Update state if plan is different
        if (state.currentPlan?.id != plan.id) {
          state = state.copyWith(
            currentPlan: plan,
            isFromLocalCache: false,
          );
        }

        // Update local cache
        if (_currentUserId != null) {
          await LocalDatabase.saveFitnessPlan(plan, _currentUserId!);
        }
      }
    } catch (e) {
      // Silently fail background sync - user already has local data
      _logger.d('Background sync failed: $e');
    }
  }

  Future<bool> generateNewPlan() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final plan = await _apiService.generateWorkoutPlan();
      state = state.copyWith(
        currentPlan: plan,
        isLoading: false,
        isFromLocalCache: false,
      );

      // Save to local cache
      if (_currentUserId != null) {
        await LocalDatabase.saveFitnessPlan(plan, _currentUserId!);
        _logger.d('Saved generated plan to local cache');
      }

      return true;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  Future<bool> logWorkout({
    required String workoutDate,
    required int durationMinutes,
    String? workoutId,
    String? workoutName,
    int? caloriesBurned,
    int? perceivedExertion,
    int? moodAfter,
    bool completed = true,
    int? completionPercentage,
    String? notes,
  }) async {
    try {
      await _apiService.logWorkout(
        workoutDate: workoutDate,
        durationMinutes: durationMinutes,
        workoutId: workoutId,
        workoutName: workoutName,
        caloriesBurned: caloriesBurned,
        perceivedExertion: perceivedExertion,
        moodAfter: moodAfter,
        completed: completed,
        completionPercentage: completionPercentage,
        notes: notes,
      );

      // Invalidate weekly stats cache since we logged a new workout
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('weekly_stats_cache');
      await prefs.remove('weekly_stats_cache_time');
      _logger.d('Invalidated weekly stats cache after logging workout');

      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getWorkoutLogs({int days = 7}) async {
    try {
      return await _apiService.getWorkoutLogs(days: days);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<void> loadWeeklyStats({bool forceRefresh = false}) async {
    try {
      // Try to load from SharedPreferences cache first (only if not force refresh)
      if (!forceRefresh) {
        final prefs = await SharedPreferences.getInstance();
        final cachedData = prefs.getString('weekly_stats_cache');
        final cacheTimestamp = prefs.getInt('weekly_stats_cache_time');

        if (cachedData != null && cacheTimestamp != null) {
          final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
          const twoMinutes = 2 * 60 * 1000;

          if (cacheAge < twoMinutes) {
            final Map<String, dynamic> cached = json.decode(cachedData);
            state = state.copyWith(
              weeklyStats: WeeklyWorkoutStats(
                completedWorkouts: cached['completedWorkouts'] ?? 0,
                totalDurationHours: (cached['totalDurationHours'] as num?)?.toDouble() ?? 0.0,
                totalCaloriesBurned: cached['totalCaloriesBurned'] ?? 0,
              ),
            );
            _logger.d('Loaded weekly stats from prefs cache (age: ${(cacheAge / 1000).toStringAsFixed(0)}s)');
            return;
          }
        }
      }

      // Compute stats from local workout cache (set-level tracking)
      final sessions = await WorkoutCacheService.instance.getRecentWorkouts(days: 7);

      int completedWorkouts = sessions.length;
      double totalDurationMinutes = 0;
      int totalCalories = 0;

      for (final session in sessions) {
        totalDurationMinutes += session.durationSeconds / 60.0;
        // Estimate calories: ~5 cal per minute of workout (rough avg)
        totalCalories += (session.durationSeconds / 60.0 * 5).round();
      }

      final weeklyStats = WeeklyWorkoutStats(
        completedWorkouts: completedWorkouts,
        totalDurationHours: totalDurationMinutes / 60,
        totalCaloriesBurned: totalCalories,
      );

      state = state.copyWith(
        weeklyStats: weeklyStats,
      );

      // Cache to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weekly_stats_cache', json.encode({
        'completedWorkouts': completedWorkouts,
        'totalDurationHours': totalDurationMinutes / 60,
        'totalCaloriesBurned': totalCalories,
      }));
      await prefs.setInt('weekly_stats_cache_time', DateTime.now().millisecondsSinceEpoch);
      _logger.d('Weekly stats: $completedWorkouts workouts, ${totalDurationMinutes.toStringAsFixed(0)}min, $totalCalories cal');
    } catch (e) {
      _logger.e('Failed to load weekly stats: $e');
      state = state.copyWith(
        weeklyStats: const WeeklyWorkoutStats(),
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider
final fitnessNotifierProvider = StateNotifierProvider<FitnessNotifier, FitnessState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return FitnessNotifier(apiService);
});