import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/data_repository.dart';
import '../services/offline_mutation_queue.dart';
import '../services/cache_service.dart';
import '../services/local_database.dart';

// Auth status enum for cleaner state management
enum AuthStatus {
  unknown,        // Initial state, checking auth
  unauthenticated, // No valid session
  authenticated,   // Logged in, onboarding completed
  needsOnboarding, // Logged in but needs onboarding
}

// Logout result enum
enum LogoutResult {
  success,            // Logout successful
  pendingSyncFailed,  // Has unsynced workouts that failed to sync
}

// Auth state
class AuthState {
  final User? user;
  final UserProfile? profile;
  final bool isLoading;
  final String? error;
  final AuthStatus status;

  const AuthState({
    this.user,
    this.profile,
    this.isLoading = false,
    this.error,
    this.status = AuthStatus.unknown,
  });

  AuthState copyWith({
    User? user,
    UserProfile? profile,
    bool? isLoading,
    String? error,
    AuthStatus? status,
  }) {
    return AuthState(
      user: user ?? this.user,
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      status: status ?? this.status,
    );
  }

  bool get isAuthenticated => user != null;
  bool get hasCompletedOnboarding => profile?.onboardingCompleted == true;
}

// Auth notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _apiService;

  AuthNotifier(this._apiService) : super(const AuthState(status: AuthStatus.unknown)) {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    if (await _apiService.isLoggedIn) {
      await _loadUserData();
    } else {
      // No stored token, user needs to log in
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _loadUserData() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final user = await _apiService.getCurrentUser();
      state = state.copyWith(user: user);

      // Try to load profile
      try {
        final profile = await _apiService.getUserProfile();
        final hasOnboarded = profile.onboardingCompleted ?? false;
        state = state.copyWith(
          profile: profile,
          isLoading: false,
          status: hasOnboarded ? AuthStatus.authenticated : AuthStatus.needsOnboarding,
        );

        // Warm all caches + process offline queue in background
        if (hasOnboarded) {
          _warmCachesInBackground();
        }
      } catch (e) {
        // Profile might not exist yet (404) - needs onboarding
        state = state.copyWith(
          isLoading: false,
          status: AuthStatus.needsOnboarding,
        );
      }
    } catch (e) {
      // Failed to get user - token might be invalid
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
        status: AuthStatus.unauthenticated,
      );
    }
  }

  /// Preload all caches + flush offline queue in background
  void _warmCachesInBackground() {
    Future.microtask(() async {
      try {
        // 1. Initialize cache service
        // CacheService initializes lazily on first access

        // 2. Preload common data into SQLite cache
        final repo = DataRepository(_apiService, CacheService.instance);
        await repo.preloadData();

        // 3. Process any mutations queued while offline
        await OfflineMutationQueue.instance.processQueue();

        // 4. Start periodic sync
        SyncService().initialize();
      } catch (e) {
        // Non-fatal — app works without warm cache
      }
    });
  }

  Future<bool> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final name = '$firstName $lastName';
      final authResponse = await _apiService.register(email, password, name);
      state = state.copyWith(user: authResponse.user);

      await _loadUserProfile();
      return true;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final authResponse = await _apiService.login(email, password);
      state = state.copyWith(user: authResponse.user);

      await _loadUserProfile();
      return true;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  Future<bool> loginWithGoogle() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      // For now, we'll use a placeholder implementation
      // TODO: Implement actual Google Sign-In
      final authResponse = await _apiService.googleSignIn();
      state = state.copyWith(user: authResponse.user);

      await _loadUserProfile();
      return true;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  Future<LogoutResult> logout() async {
    // Check for pending workouts before logging out
    final hasPending = await syncService.hasPendingWorkouts();

    if (hasPending) {
      // Try to sync pending workouts first
      final syncSuccess = await syncService.syncBeforeLogout();

      if (!syncSuccess) {
        // Sync failed - data may be lost
        return LogoutResult.pendingSyncFailed;
      }
    }

    // Safe to logout now
    await _apiService.logout();

    // Clear ALL cached data so next user doesn't see previous user's data
    try {
      await CacheService.instance.clearAll();
      await LocalDatabase.clearAllData();
    } catch (e) {
      // Non-fatal
    }

    state = const AuthState(status: AuthStatus.unauthenticated);
    return LogoutResult.success;
  }

  /// Force logout without syncing (use with caution!)
  Future<void> forceLogout() async {
    await _apiService.logout();

    // Clear ALL cached data
    try {
      await CacheService.instance.clearAll();
      await LocalDatabase.clearAllData();
    } catch (e) {
      // Non-fatal
    }

    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _loadUserProfile() async {
    try {
      final profile = await _apiService.getUserProfile();
      final hasOnboarded = profile.onboardingCompleted ?? false;
      state = state.copyWith(
        profile: profile,
        isLoading: false,
        status: hasOnboarded ? AuthStatus.authenticated : AuthStatus.needsOnboarding,
      );
    } catch (e) {
      // Profile might not exist yet - needs onboarding
      state = state.copyWith(
        isLoading: false,
        status: AuthStatus.needsOnboarding,
      );
    }
  }

  Future<void> refreshUserData() async {
    await _loadUserData();
  }

  Future<bool> updateProfile(Map<String, dynamic> profileData) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final updatedProfile = await _apiService.updateUserProfile(profileData);

      // Determine auth status based on onboarding completion
      final hasOnboarded = updatedProfile.onboardingCompleted ?? false;
      state = state.copyWith(
        profile: updatedProfile,
        isLoading: false,
        status: hasOnboarded ? AuthStatus.authenticated : AuthStatus.needsOnboarding,
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider definitions
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

// Provider
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return AuthNotifier(apiService);
});

