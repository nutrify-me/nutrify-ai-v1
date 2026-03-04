import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../models/gamification.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

final _logger = Logger();

/// State for gamification
class GamificationState {
  final UserStreak? streak;
  final List<AchievementProgress> achievements;
  final List<NewAchievementNotification> pendingNotifications;
  final bool isLoading;
  final String? error;

  const GamificationState({
    this.streak,
    this.achievements = const [],
    this.pendingNotifications = const [],
    this.isLoading = false,
    this.error,
  });

  GamificationState copyWith({
    UserStreak? streak,
    List<AchievementProgress>? achievements,
    List<NewAchievementNotification>? pendingNotifications,
    bool? isLoading,
    String? error,
  }) {
    return GamificationState(
      streak: streak ?? this.streak,
      achievements: achievements ?? this.achievements,
      pendingNotifications: pendingNotifications ?? this.pendingNotifications,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  int get totalPoints {
    int points = 0;
    for (final ap in achievements) {
      if (ap.earned) {
        points += ap.achievement.points;
      }
    }
    return points;
  }

  int get earnedCount => achievements.where((a) => a.earned).length;

  List<AchievementProgress> get earnedAchievements =>
      achievements.where((a) => a.earned).toList()
        ..sort((a, b) => (b.earnedAt ?? DateTime.now())
            .compareTo(a.earnedAt ?? DateTime.now()));

  List<AchievementProgress> get inProgressAchievements =>
      achievements.where((a) => !a.earned && a.progressPercentage > 0).toList()
        ..sort((a, b) => b.progressPercentage.compareTo(a.progressPercentage));

  List<AchievementProgress> get lockedAchievements =>
      achievements.where((a) => !a.earned && a.progressPercentage == 0).toList();
}

/// Notifier for gamification state
class GamificationNotifier extends StateNotifier<GamificationState> {
  final ApiService _apiService;

  GamificationNotifier(this._apiService) : super(const GamificationState());

  /// Load streak data
  Future<void> loadStreak({bool forceRefresh = false}) async {
    try {
      final streak = await _apiService.getStreak(forceRefresh: forceRefresh);
      state = state.copyWith(streak: streak);
      _logger.d('Loaded streak: ${streak.currentStreak} days');
    } catch (e) {
      _logger.e('Failed to load streak: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  /// Load all achievements with progress
  Future<void> loadAchievements({bool forceRefresh = false}) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final achievements = await _apiService.getAchievementsWithProgress(forceRefresh: forceRefresh);
      state = state.copyWith(
        achievements: achievements,
        isLoading: false,
      );
      _logger.d('Loaded ${achievements.length} achievements');
    } catch (e) {
      _logger.e('Failed to load achievements: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Check for unnotified achievements (new achievements to show)
  Future<List<NewAchievementNotification>> checkForNewAchievements() async {
    try {
      final notifications = await _apiService.getUnnotifiedAchievements();
      if (notifications.isNotEmpty) {
        state = state.copyWith(pendingNotifications: notifications);
        _logger.i('Found ${notifications.length} new achievements to show');
      }
      return notifications;
    } catch (e) {
      _logger.e('Failed to check for new achievements: $e');
      return [];
    }
  }

  /// Clear pending notifications
  void clearNotifications() {
    state = state.copyWith(pendingNotifications: []);
  }

  /// Refresh all gamification data
  Future<void> refresh() async {
    await Future.wait([
      loadStreak(),
      loadAchievements(),
    ]);
  }
}

/// Provider for gamification state
final gamificationProvider =
    StateNotifierProvider<GamificationNotifier, GamificationState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return GamificationNotifier(apiService);
});

/// Provider for just the streak (lighter weight)
final streakProvider = FutureProvider<UserStreak?>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  try {
    return await apiService.getStreak();
  } catch (e) {
    _logger.e('Failed to load streak: $e');
    return null;
  }
});

/// Provider for achievements with progress
final achievementsProvider = FutureProvider<List<AchievementProgress>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getAchievementsWithProgress();
});

/// Provider for gamification stats (for dashboard)
final gamificationStatsProvider = FutureProvider<GamificationStats?>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  try {
    return await apiService.getGamificationStats();
  } catch (e) {
    _logger.e('Failed to load gamification stats: $e');
    return null;
  }
});
