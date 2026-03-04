import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../models/nutrition.dart';
import '../services/api_service.dart';
import '../services/local_database.dart';
import 'auth_provider.dart';

final _logger = Logger();

// Nutrition state
class NutritionState {
  final NutritionPlan? currentPlan;
  final bool isLoading;
  final String? error;
  final bool isFromLocalCache;

  const NutritionState({
    this.currentPlan,
    this.isLoading = false,
    this.error,
    this.isFromLocalCache = false,
  });

  NutritionState copyWith({
    NutritionPlan? currentPlan,
    bool? isLoading,
    String? error,
    bool? isFromLocalCache,
  }) {
    return NutritionState(
      currentPlan: currentPlan ?? this.currentPlan,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isFromLocalCache: isFromLocalCache ?? this.isFromLocalCache,
    );
  }
}

// Nutrition notifier
class NutritionNotifier extends StateNotifier<NutritionState> {
  final ApiService _apiService;
  bool _hasLoadedOnce = false;
  String? _currentUserId;

  NutritionNotifier(this._apiService) : super(const NutritionState());

  void setUserId(String userId) {
    _currentUserId = userId;
  }

  /// Reset state when a new user logs in
  void resetForNewUser(String newUserId) {
    _currentUserId = newUserId;
    _hasLoadedOnce = false;
    state = const NutritionState();
    _logger.d('NutritionNotifier reset for new user: $newUserId');
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
        final localPlan = await LocalDatabase.getNutritionPlan(_currentUserId!);
        if (localPlan != null) {
          _logger.d('Loaded nutrition plan from local cache');
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
      final plan = await _apiService.getCurrentNutritionPlan(forceRefresh: forceRefresh);
      state = state.copyWith(
        currentPlan: plan,
        isLoading: false,
        isFromLocalCache: false,
      );

      // Save to local cache
      if (plan != null && _currentUserId != null) {
        await LocalDatabase.saveNutritionPlan(plan, _currentUserId!);
        _logger.d('Saved nutrition plan to local cache');
      }

      _hasLoadedOnce = true;
    } catch (e) {
      // If it's a 404, that's expected - no plan exists yet
      final errorMsg = e.toString();
      if (errorMsg.contains('404') || errorMsg.contains('No nutrition plan found')) {
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
      final plan = await _apiService.getCurrentNutritionPlan(forceRefresh: true);
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
          await LocalDatabase.saveNutritionPlan(plan, _currentUserId!);
        }
      }
    } catch (e) {
      // Silently fail background sync - user already has local data
      _logger.d('Background sync failed: $e');
    }
  }

  Future<bool> generateNewPlan() async {
    try {
      _logger.d('Starting nutrition plan generation...');
      state = state.copyWith(isLoading: true, error: null);
      final plan = await _apiService.generateNutritionPlan();
      _logger.d('Plan generated successfully: ${plan.id}');
      _logger.d('Plan has ${plan.meals.length} days of meals');
      state = state.copyWith(
        currentPlan: plan,
        isLoading: false,
        isFromLocalCache: false,
      );

      // Save to local cache
      if (_currentUserId != null) {
        await LocalDatabase.saveNutritionPlan(plan, _currentUserId!);
        _logger.d('Saved generated plan to local cache');
      }

      return true;
    } catch (e, stackTrace) {
      _logger.e('Failed to generate nutrition plan: $e');
      _logger.e('Stack trace: $stackTrace');
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  Future<bool> logMeal({
    required String mealDate,
    required String mealType,
    String? mealId,
    String? customMealName,
    int? calories,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    int? satisfactionRating,
  }) async {
    try {
      await _apiService.logMeal(
        mealDate: mealDate,
        mealType: mealType,
        mealId: mealId,
        customMealName: customMealName,
        calories: calories,
        proteinGrams: proteinGrams,
        carbsGrams: carbsGrams,
        fatGrams: fatGrams,
        satisfactionRating: satisfactionRating,
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getMealLogs({int days = 7}) async {
    try {
      return await _apiService.getMealLogs(days: days);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider
final nutritionNotifierProvider = StateNotifierProvider<NutritionNotifier, NutritionState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return NutritionNotifier(apiService);
});