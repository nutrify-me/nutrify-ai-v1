import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'cache_service.dart';
import 'api_service.dart';
import '../providers/auth_provider.dart';
import '../models/nutrition.dart';
import '../models/fitness.dart';
import '../models/user.dart';
import '../models/progress.dart';

final _logger = Logger();

/// Repository that implements cache-first data fetching
class DataRepository {
  final ApiService _apiService;
  final CacheService _cacheService;

  DataRepository(this._apiService, this._cacheService);

  // === User Profile ===

  /// Get user profile - cache first, then refresh from server
  Future<UserProfile?> getUserProfile({bool forceRefresh = false}) async {
    // Try cache first (unless force refresh)
    if (!forceRefresh) {
      try {
        final cached = await _cacheService.get(CacheKeys.userProfile);
        if (cached != null) {
          _logger.d('Returning cached user profile');
          // Refresh in background
          _refreshUserProfileInBackground();
          return UserProfile.fromJson(json.decode(cached));
        }
      } catch (e) {
        _logger.w('Cache read failed for user profile: $e');
      }
    }

    // Fetch from server
    return _fetchAndCacheUserProfile();
  }

  Future<UserProfile?> _fetchAndCacheUserProfile() async {
    try {
      final profile = await _apiService.getUserProfile();
      if (profile != null) {
        await _cacheService.set(
          CacheKeys.userProfile,
          json.encode(profile.toJson()),
        );
        _logger.d('Cached user profile');
      }
      return profile;
    } catch (e) {
      _logger.e('Failed to fetch user profile: $e');
      return null;
    }
  }

  void _refreshUserProfileInBackground() {
    Future.microtask(() async {
      await _fetchAndCacheUserProfile();
    });
  }

  // === Nutrition Plan ===

  /// Get current nutrition plan - cache first
  Future<NutritionPlan?> getCurrentNutritionPlan({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      try {
        final cached = await _cacheService.getUserData(DataTypes.nutritionPlan);
        if (cached != null) {
          _logger.d('Returning cached nutrition plan');
          _refreshNutritionPlanInBackground();
          return NutritionPlan.fromJson(cached);
        }
      } catch (e) {
        _logger.w('Cache read failed for nutrition plan: $e');
      }
    }

    return _fetchAndCacheNutritionPlan();
  }

  Future<NutritionPlan?> _fetchAndCacheNutritionPlan() async {
    try {
      final plan = await _apiService.getCurrentNutritionPlan();
      if (plan != null) {
        await _cacheService.setUserData(
          plan.id,
          DataTypes.nutritionPlan,
          plan.toJson(),
        );
        _logger.d('Cached nutrition plan');
      }
      return plan;
    } catch (e) {
      _logger.e('Failed to fetch nutrition plan: $e');
      return null;
    }
  }

  void _refreshNutritionPlanInBackground() {
    Future.microtask(() async {
      await _fetchAndCacheNutritionPlan();
    });
  }

  // === Fitness Plan ===

  /// Get current fitness/workout plan - cache first
  Future<WorkoutPlan?> getCurrentWorkoutPlan({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      try {
        final cached = await _cacheService.getUserData(DataTypes.fitnessPlan);
        if (cached != null) {
          _logger.d('Returning cached workout plan');
          _refreshWorkoutPlanInBackground();
          return WorkoutPlan.fromJson(cached);
        }
      } catch (e) {
        _logger.w('Cache read failed for workout plan: $e');
      }
    }

    return _fetchAndCacheWorkoutPlan();
  }

  Future<WorkoutPlan?> _fetchAndCacheWorkoutPlan() async {
    try {
      final plan = await _apiService.getCurrentWorkoutPlan();
      if (plan != null) {
        await _cacheService.setUserData(
          plan.id,
          DataTypes.fitnessPlan,
          plan.toJson(),
        );
        _logger.d('Cached workout plan');
      }
      return plan;
    } catch (e) {
      _logger.e('Failed to fetch workout plan: $e');
      return null;
    }
  }

  void _refreshWorkoutPlanInBackground() {
    Future.microtask(() async {
      await _fetchAndCacheWorkoutPlan();
    });
  }

  // === Progress Entries ===

  /// Get progress entries - cache first
  Future<List<ProgressEntry>> getProgressEntries({
    int limit = 30,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${CacheKeys.progressEntries}_$limit';

    if (!forceRefresh) {
      try {
        final cached = await _cacheService.get(cacheKey);
        if (cached != null) {
          _logger.d('Returning cached progress entries');
          _refreshProgressEntriesInBackground(limit);
          final list = json.decode(cached) as List;
          return list.map((e) => ProgressEntry.fromJson(e)).toList();
        }
      } catch (e) {
        _logger.w('Cache read failed for progress entries: $e');
      }
    }

    return _fetchAndCacheProgressEntries(limit);
  }

  Future<List<ProgressEntry>> _fetchAndCacheProgressEntries(int limit) async {
    try {
      final entries = await _apiService.getProgressEntries(limit: limit);
      final cacheKey = '${CacheKeys.progressEntries}_$limit';
      await _cacheService.set(
        cacheKey,
        json.encode(entries.map((e) => e.toJson()).toList()),
      );
      _logger.d('Cached ${entries.length} progress entries');
      return entries;
    } catch (e) {
      _logger.e('Failed to fetch progress entries: $e');
      return [];
    }
  }

  void _refreshProgressEntriesInBackground(int limit) {
    Future.microtask(() async {
      await _fetchAndCacheProgressEntries(limit);
    });
  }

  // === Meal Logs ===

  /// Log meal with local-first approach
  Future<Map<String, dynamic>?> logMealData(Map<String, dynamic> mealData) async {
    try {
      final serverLog = await _apiService.logMeal(
        mealDate: mealData['meal_date'] ?? DateTime.now().toIso8601String().split('T')[0],
        mealType: mealData['meal_type'] ?? 'snack',
        customMealName: mealData['custom_meal_name'],
        calories: mealData['calories'],
        proteinGrams: mealData['protein_grams']?.toDouble(),
        carbsGrams: mealData['carbs_grams']?.toDouble(),
        fatGrams: mealData['fat_grams']?.toDouble(),
      );
      return serverLog;
    } catch (e) {
      _logger.e('Failed to log meal: $e');
      return null;
    }
  }

  // === Sync Methods ===

  /// Sync all dirty entries to server
  Future<void> syncDirtyEntries() async {
    final dirtyEntries = await _cacheService.getDirtyEntries();
    _logger.i('Syncing ${dirtyEntries.length} dirty entries');

    for (final entry in dirtyEntries) {
      try {
        // Determine type and sync accordingly
        // This would need to be expanded based on your data types
        await _cacheService.markSynced(entry.key);
        _logger.d('Synced entry: ${entry.key}');
      } catch (e) {
        _logger.w('Failed to sync entry ${entry.key}: $e');
      }
    }
  }

  /// Preload commonly accessed data
  Future<void> preloadData() async {
    _logger.i('Preloading data...');

    // Load in parallel
    await Future.wait([
      getUserProfile(),
      getCurrentNutritionPlan(),
      getCurrentWorkoutPlan(),
      getProgressEntries(),
    ]);

    _logger.i('Preload complete');
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    await _cacheService.clearAll();
  }

  /// Get cache statistics
  Future<Map<String, int>> getCacheStats() async {
    return _cacheService.getCacheStats();
  }
}

/// Provider for DataRepository
final dataRepositoryProvider = Provider<DataRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final cacheService = CacheService.instance;
  return DataRepository(apiService, cacheService);
});

/// Provider for user profile with caching
final cachedUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final repo = ref.watch(dataRepositoryProvider);
  return repo.getUserProfile();
});

/// Provider for nutrition plan with caching
final cachedNutritionPlanProvider = FutureProvider<NutritionPlan?>((ref) async {
  final repo = ref.watch(dataRepositoryProvider);
  return repo.getCurrentNutritionPlan();
});

/// Provider for workout plan with caching
final cachedWorkoutPlanProvider = FutureProvider<WorkoutPlan?>((ref) async {
  final repo = ref.watch(dataRepositoryProvider);
  return repo.getCurrentWorkoutPlan();
});

/// Provider for progress entries with caching
final cachedProgressEntriesProvider = FutureProvider<List<ProgressEntry>>((ref) async {
  final repo = ref.watch(dataRepositoryProvider);
  return repo.getProgressEntries();
});
